#!/usr/bin/env perl
#-------------------------------------------------------------------------------
# Easily transfer bulk data from Linux machines via physical storage shipment.
#
# Created By : Senthil Pandian @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#-------------------------------------------------------------------------------

use strict;
use POSIX qw/mktime/;
use POSIX ":sys_wait_h";
#use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Configuration;
use constant BACKUP_PID_FAIL => 2;

my $cmdNumOfArgs = $#ARGV;
my $jobType = 'manual';
my ($silentBackupFlag,$filesOnlyCount,$exitStatus,$prevFailedCount,$retry_failedfiles_index) = (0) x 5;
#our $signalTerm = 0;
our ($mountedPath,$expressLocalDir,$localUserPath,$backupsetFile,$relativeFileset,$noRelativeFileset,$filesOnly);
my ($generateFilesPid,$totalFiles,@BackupForkchilds,$backupsetFilePath,$displayProgressBarPid);

my $engineID = 1;
my ($isScheduledJob, $isEmpty) = (0) x 2;
use constant BACKUP_SUCCESS => 1;

##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script during backup #
##############################################
$SIG{INT}  = \&processTerm;
$SIG{TERM} = \&processTerm;
$SIG{TSTP} = \&processTerm;
$SIG{QUIT} = \&processTerm;
$SIG{PWR}  = \&processTerm;
$SIG{KILL} = \&processTerm;
$SIG{USR1} = \&processTerm;

Helpers::waitForUpdate();
Helpers::initiateMigrate();

init();

#*******************************************************************************
# This script starts & ends in init()
#
# Added By   : Senthil Pandian
# Modified By: Yogesh Kumar
#*******************************************************************************
sub init {
	system(Helpers::updateLocaleCmd("clear")) and Helpers::retreat('failed_to_clear_screen') unless ($cmdNumOfArgs > -1);
	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	if ($cmdNumOfArgs > -1) {
		if ((${ARGV[0]} eq "SCHEDULED") or (${ARGV[0]} eq "immediate")) {
			$Configuration::callerEnv = 'BACKGROUND';
			Helpers::setUsername($ARGV[1]);
			$jobType = 'scheduled';
			$silentBackupFlag = 1;
			$isScheduledJob = 1;
			Helpers::loadUserConfiguration();
		}
		elsif (${ARGV[0]} eq '--silent' or ${ARGV[0]} eq 'dashboard' or ${ARGV[0]} eq 'immediate') {
			$Configuration::callerEnv = 'BACKGROUND';
			$silentBackupFlag = 1;
		}
	}

	if ($jobType eq 'manual') {
		Helpers::loadUsername() or Helpers::retreat('login_&_try_again');
		my $errorKey = Helpers::loadUserConfiguration();
		Helpers::retreat($Configuration::errorDetails{$errorKey}) if($errorKey > 1);
	}

	unless ($silentBackupFlag) {
		Helpers::isLoggedin() or Helpers::retreat('login_&_try_again');
		Helpers::displayHeader();
	}
	my $username      = Helpers::getUsername();
	my $servicePath   = Helpers::getServicePath();
	my $jobRunningDir = Helpers::getJobsPath('localbackup');
	$Configuration::jobRunningDir = $jobRunningDir;
	$Configuration::jobType		  = "LocalBackup";
	if(!Helpers::loadEVSBinary()){
		Helpers::sendFailureNotice($username,'update_localbackup_progress',$jobType);
		Helpers::retreat('unable_to_find_or_execute_evs_binary');
	}

	my $dedup  	      = Helpers::getUserConfiguration('DEDUP');
	my $serverRoot    = Helpers::getUserConfiguration('SERVERROOT');
	my $backupTo	  = Helpers::getUserConfiguration('BACKUPLOCATION');
	if($dedup eq 'off') {
		my @backupTo = split("/",$backupTo);
		$backupTo	 = (substr($backupTo,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
	}
	if ($dedup eq 'on' and !$serverRoot) {
		(my $deviceID, $backupTo)  = split("#",$backupTo);
		Helpers::display(["\n",'verifying_your_account_info',"\n"]);
		my %evsDeviceHashOutput = Helpers::getDeviceHash();
		my $uniqueID = Helpers::getMachineUID() or Helpers::retreat('unable_to_find_mac_address');
		$uniqueID .= "_1";
		if(exists($evsDeviceHashOutput{$uniqueID})){
			$serverRoot  = $evsDeviceHashOutput{$uniqueID}{'server_root'};
			Helpers::setUserConfiguration('SERVERROOT', $serverRoot);
			Helpers::saveUserConfiguration() or Helpers::retreat('failed_to_save_user_configuration');
		}

		if(!$serverRoot){
			Helpers::display(["\n",'your_account_not_configured_properly',"\n"])  unless ($silentBackupFlag);
			Helpers::traceLog(Helpers::getStringConstant('your_account_not_configured_properly'));
			Helpers::sendFailureNotice($username,'update_localbackup_progress',$jobType);
			exit 1;
		}
	}
	Helpers::createDir($jobRunningDir, 1);

	#Checking if another job is already in progress
	my $pidPath = Helpers::getCatfile($jobRunningDir, $Configuration::pidFile);
	if (Helpers::isFileLocked($pidPath)) {
		Helpers::retreat('express_backup_running', $silentBackupFlag);
	}
	else {
		Helpers::fileLock($pidPath);
	}

	#Renaming the log file if backup process terminated improperly
	Helpers::checkAndRenameFileWithStatus($jobRunningDir, 'localbackup');

	removeIntermediateFiles(); # pre cleanup for all intermediate files and folders.

	$backupsetFile     = Helpers::getCatfile($jobRunningDir, $Configuration::backupsetFile);
	#Helpers::createUpdateBWFile(); #Commented by Senthil: 13-Aug-2018
	$isEmpty = Helpers::checkPreReq($backupsetFile, lc(Helpers::getStringConstant('localbackup')), $jobType, 'NOBACKUPDATA');
	if($isEmpty and $isScheduledJob == 0 and $silentBackupFlag == 0) {
		unlink($pidPath);
		Helpers::retreat(["\n",$Configuration::errStr]);
	}
	# Commented as per Deepak's instruction: Senthil
	# my $serverAddress = Helpers::getServerAddress();
	# if ($serverAddress == 0){
		# exitCleanup($Configuration::errStr);
	# }

	$mountedPath     = Helpers::getAndSetMountedPath($silentBackupFlag);
	$isEmpty = 1 if($silentBackupFlag and !$mountedPath);
	$expressLocalDir = Helpers::getCatfile($mountedPath, ($Configuration::appType . 'Local'));
	$localUserPath   = Helpers::getCatfile($expressLocalDir, $username);
	$Configuration::expressLocalDir = $expressLocalDir;

	#Verify dbpath.xml file
# TODO: Need to enable for local restore
#	if ($dedup eq 'on') {
#		my @backupLocationDir = Helpers::getUserBackupDirListFromMountPath($localUserPath);
#		if(scalar(@backupLocationDir)>0) {
#			Helpers::checkAndCreateDBpathXMLfile($localUserPath, \@backupLocationDir);
#		}
#	}

	#Start creating required file/folder
	my $excludeDirPath = Helpers::getCatfile($jobRunningDir, $Configuration::excludeDir);
	my $errorDir       = Helpers::getCatfile($jobRunningDir, $Configuration::errorDir);

	$relativeFileset   = Helpers::getCatfile($jobRunningDir, $Configuration::relativeFileset);
	$noRelativeFileset = Helpers::getCatfile($jobRunningDir, $Configuration::noRelativeFileset);
	$filesOnly         = Helpers::getCatfile($jobRunningDir, $Configuration::filesOnly);

	Helpers::createDir($errorDir, 0);
	Helpers::createDir($excludeDirPath, 0);

	Helpers::createLogFiles("BACKUP",ucfirst($jobType));
	Helpers::createBackupTypeFile() or Helpers::retreat('failed_to_set_backup_type');
	unless ($silentBackupFlag) {
		if ($dedup eq 'off') {
			my $bl = Helpers::getUserConfiguration('BACKUPLOCATION');
			Helpers::display(["\n",'your_current_backup_location_is',"'$bl'."]);
			Helpers::display(['considered_backup_location_for_express',"'$backupTo'",".\n"]);
		}elsif($dedup eq 'on'){
			$backupTo = (split("#",$backupTo))[1];
			Helpers::display(["\n",'your_backup_location_is',"'$backupTo'",".\n"]);
		}
		Helpers::getCursorPos(11,Helpers::getStringConstant('preparing_file_list')) if (!$isEmpty and -e $pidPath);
	}

	$Configuration::mailContentHead = Helpers::writeLogHeader($jobType);
	if (Helpers::loadNotifications()) {
		Helpers::setNotification('update_localbackup_progress', ((split("/", $Configuration::outputFilePath))[-1]));
		Helpers::saveNotifications();
	}

	startBackup() if(!$isEmpty and -e $pidPath);
	exitCleanup($Configuration::errStr);
}
#****************************************************************************************************
# Subroutine		: startBackup
# Objective			: This function will fork a child process to generate backupset files and get
#						count of total files considered. Another forked process will perform main
#						backup operation of all the generated backupset files one by one.
# Added By			: Senthil Pandian
# Modified By       : Yogesh Kumar, Senthil Pandian
#*****************************************************************************************************/
sub startBackup {
	Helpers::loadFullExclude();
	Helpers::loadPartialExclude();
	Helpers::loadRegexExclude();
	Helpers::createLocalBackupDir(); #Creating the local backup location directories
	Helpers::createDBPathsXmlFile();
	my $progressDetailsFilePath = $Configuration::progressDetailsFilePath;
	my $pidPath	  = Helpers::getCatfile($Configuration::jobRunningDir, $Configuration::pidFile);
	$generateFilesPid = fork();

	if(!defined $generateFilesPid) {
		Helpers::traceLog(['cannot_fork_child', "\n"]);
		Helpers::display(['cannot_fork_child', "\n"]) unless ($silentBackupFlag);
		return 0;
	}

	Helpers::generateBackupsetFiles() if($generateFilesPid == 0);

	if($isScheduledJob == 0 and $silentBackupFlag == 0){
		$displayProgressBarPid = fork();

		if(!defined $displayProgressBarPid) {
			$Configuration::errStr = Helpers::getStringConstant('unable_to_display_progress_bar');
			Helpers::traceLog($Configuration::errStr);
			return 0;
		}

		if($displayProgressBarPid == 0) {
			$Configuration::pidOperationFlag = "DisplayProgress";
			while(1){
				Helpers::displayProgressBar($progressDetailsFilePath);
				if(!-e $pidPath){
					last;
				}
				#select(undef, undef, undef, 0.1);
				Helpers::sleepForMilliSec(100); # Sleep for 100 milliseconds
			}
			Helpers::displayProgressBar($progressDetailsFilePath,Helpers::getTotalSize($Configuration::jobRunningDir."/".$Configuration::fileForSize));
			exit(0);
		}
	}

	my $info_file = Helpers::getCatfile($Configuration::jobRunningDir, $Configuration::infoFile);
	my $retryInfo = Helpers::getCatfile($Configuration::jobRunningDir, $Configuration::retryInfo);
	my $maxNumRetryAttempts = 1000;
	my $engineLockFile = $Configuration::jobRunningDir.'/'.Configuration::ENGINE_LOCKE_FILE;
	my $line;
	my $statusFilePath  = $Configuration::jobRunningDir."/".$Configuration::statusFile;

	open(my $handle, '>', $engineLockFile) or traceLog("\n Could not open file '$engineLockFile' $! \n", __FILE__, __LINE__);
	close $handle;
	chmod $Configuration::filePermission, $engineLockFile;
	my $exec_cores = Helpers::getSystemCpuCores();
	my $exec_loads;

START:
	if(!open(FD_READ, "<", $info_file)) {
		$Configuration::errStr = Helpers::getStringConstant('failed_to_open_file')." info_file in startBackup: $info_file to read, Reason $! \n";
		Helpers::traceLog($Configuration::errStr);
		return 0;
	}
	while (1) {
		if(!-e $pidPath){
			last;
		}

		if($line eq "") {
			$line = <FD_READ>;
		}

		if($line eq "") {
			sleep(1);
			seek(FD_READ, 0, 1);		#to clear eof flag
			next;
		}

		chomp($line);
		$line =~ s/^[\s\t]+$//;			#space and tab also trim
		if($line =~ m/^TOTALFILES/) {
			$totalFiles = $line;
			$totalFiles =~ s/TOTALFILES//;
			$line = "";
			last;
		}

		my $isEngineRunning = Helpers::isEngineRunning($pidPath.'_'.$engineID);
		if(!$isEngineRunning){
			while(1){
				last	if(!-e $pidPath or !Helpers::isAnyEngineRunning($engineLockFile));

				$exec_loads = Helpers::getLoadAverage();
				if($exec_loads > $exec_cores){
					sleep(10);
					next;
				}
				last;
			}

			if($retry_failedfiles_index != -1){
				$retry_failedfiles_index++;
				if($retry_failedfiles_index > 2000000000){
					$retry_failedfiles_index = 0;
				}
			}

			my $backupPid = fork();

			if(!defined $backupPid) {
				$Configuration::errStr = "Cannot fork() child process :  for EVS \n";
				return BACKUP_PID_FAIL;
			}
			elsif($backupPid == 0) {
				my $retType = doBackupOperation($line, $silentBackupFlag, $jobType,$engineID,$retry_failedfiles_index);
				exit(0);
			}
			else{
				push (@BackupForkchilds, $backupPid);
				if(defined($exec_loads) and ($exec_loads > $exec_cores)){
					sleep(2);
				}
				else{
					sleep(1);
				}
			}
			$line = "";
		}

		if($Configuration::totalEngineBackup > 1)
		{
			$engineID++;
			if($engineID > $Configuration::totalEngineBackup){
				$engineID = 1;
				sleep(2);
			}
		}

		Helpers::killPIDs(\@BackupForkchilds,0);
	}
	Helpers::waitForEnginesToFinish(\@BackupForkchilds,$engineLockFile);
	close FD_READ;

	$Configuration::nonExistsCount    = Helpers::readInfoFile('FAILEDCOUNT');
	$Configuration::noPermissionCount = Helpers::readInfoFile('DENIEDCOUNT');
	$Configuration::missingCount      = Helpers::readInfoFile('MISSINGCOUNT');

	waitpid($generateFilesPid,0);
	undef @Configuration::linesStatusFile;
	if($totalFiles == 0 or $totalFiles !~ /\d+/) {
		$totalFiles    = Helpers::readInfoFile('TOTALFILES');
		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			Helpers::traceLog("Unable to get total files count");
		}
	}
	$Configuration::totalFiles = $totalFiles;

	if (-s $retryInfo > 0 && -e $pidPath && $Configuration::retryCount <= $maxNumRetryAttempts && $exitStatus == 0) {
		if ($Configuration::retryCount == $maxNumRetryAttempts) {

			for(my $i=1; $i<= $Configuration::totalEngineBackup; $i++){
				if(-e $statusFilePath."_".$i  and  -s $statusFilePath."_".$i>0){
					Helpers::readStatusFile($i);
					my $index = "-1";
					$Configuration::statusHash{'FAILEDFILES_LISTIDX'} = $index;
					Helpers::putParameterValueInStatusFile($i);
					putParameterValueInStatusFile();
					undef @Configuration::linesStatusFile;
				}
			}
			$retry_failedfiles_index = -1;
		}

		move($retryInfo, $info_file);
		Helpers::updateRetryCount();

		#append total file number to info
		if (!open(INFO, ">>",$info_file)){
			$Configuration::errStr = Helpers::getStringConstant('failed_to_open_file')." info_file in startBackup : $info_file, Reason $!\n";
			return $Configuration::errStr;
		}
		print INFO "TOTALFILES $totalFiles\n";
		print INFO "FAILEDCOUNT $Configuration::nonExistsCount\n";
		print INFO "DENIEDCOUNT $Configuration::noPermissionCount\n";
		print INFO "MISSINGCOUNT $Configuration::missingCount\n";
		close INFO;
		chmod $Configuration::filePermission, $info_file;
		sleep 5; #5 Sec
		Helpers::traceLog("retrycount:".$Configuration::retrycount);
		$engineID = 1;
		goto START;
	}
}

#****************************************************************************************************
# Subroutine		: removeIntermediateFiles
# Objective			: This function will remove all the intermediate files/folders
# Added By			: Senthil Pandian
#*****************************************************************************************************/
sub removeIntermediateFiles {
	my $evsTempDirPath  = $Configuration::jobRunningDir."/".$Configuration::evsTempDir;
	my $statusFilePath  = $Configuration::jobRunningDir."/".$Configuration::statusFile;
	my $retryInfo       = $Configuration::jobRunningDir."/".$Configuration::retryInfo;
	my $failedFiles     = $Configuration::jobRunningDir."/".$Configuration::failedFileName;
	my $infoFile        = $Configuration::jobRunningDir."/".$Configuration::infoFile;
	my $filesOnly	    = $Configuration::jobRunningDir."/".$Configuration::filesOnly;
	#my $incSize 		= $Configuration::jobRunningDir."/".$Configuration::transferredFileSize;
	my $excludeDirPath  = $Configuration::jobRunningDir."/".$Configuration::excludeDir;
	my $errorDir 		= $Configuration::jobRunningDir."/".$Configuration::errorDir;
	my $utf8File 		= $Configuration::jobRunningDir."/".$Configuration::utf8File."_";
	my $relativeFileset     = $Configuration::jobRunningDir."/".$Configuration::relativeFileset;
	my $noRelativeFileset   = $Configuration::jobRunningDir."/".$Configuration::noRelativeFileset;
	my $progressDetailsFilePath = $Configuration::jobRunningDir."/".$Configuration::progressDetailsFilePath."_";
	my $engineLockFile  = $Configuration::jobRunningDir.'/'.Configuration::ENGINE_LOCKE_FILE;
	my $summaryFilePath = $Configuration::jobRunningDir.'/'.$Configuration::fileSummaryFile;
	my $errorFilePath   = $Configuration::jobRunningDir."/".$Configuration::exitErrorFile;

	my $idevsOutputFile	 	= $Configuration::jobRunningDir."/".$Configuration::evsOutputFile;
	my $idevsErrorFile 	 	= $Configuration::jobRunningDir."/".$Configuration::evsErrorFile;
	my $backupUTFpath   	= $Configuration::jobRunningDir.'/'.$Configuration::utf8File;
	my $operationsFilePath  = $Configuration::jobRunningDir."/".$Configuration::operationsfile;
	my $doBackupOperationErrorFile = $Configuration::jobRunningDir."/doBackuperror.txt_";
	my $minimalErrorRetry = $Configuration::jobRunningDir."/".$Configuration::minimalErrorRetry;

	Helpers::removeItems([$evsTempDirPath, $relativeFileset.'*', $noRelativeFileset.'*', $filesOnly.'*', $infoFile, $retryInfo, $errorDir, $statusFilePath.'*', $excludeDirPath, $failedFiles.'*', $utf8File.'*', $progressDetailsFilePath.'*', $engineLockFile, $summaryFilePath, $errorFilePath]);
	Helpers::removeItems([$idevsErrorFile.'*', $idevsOutputFile.'*', $backupUTFpath.'*', $operationsFilePath.'*', $doBackupOperationErrorFile.'*', $minimalErrorRetry]);

	return 0;
}

#****************************************************************************************************
# Subroutine		: exitCleanup.
# Objective			: This function will execute the major functions required at the time of exit
# Added By			: Deepak Chaurasia
# Modified By		: Dhritikana, Yogesh Kumar
#*****************************************************************************************************/
sub exitCleanup {
	my $pidPath 			= $Configuration::jobRunningDir."/".$Configuration::pidFile;
#	my $idevsOutputFile	 	= $Configuration::jobRunningDir."/".$Configuration::evsOutputFile;
#	my $idevsErrorFile 	 	= $Configuration::jobRunningDir."/".$Configuration::evsErrorFile;
#	my $backupUTFpath   	= $Configuration::jobRunningDir.'/'.$Configuration::utf8File;
#	my $statusFilePath  	= $Configuration::jobRunningDir."/".$Configuration::statusFile;
	my $retryInfo       	= $Configuration::jobRunningDir."/".$Configuration::retryInfo;
	#my $incSize 			= $Configuration::jobRunningDir."/".$Configuration::transferredFileSize;
	my $fileForSize		    = $Configuration::jobRunningDir."/".$Configuration::fileForSize;
	my $trfSizeAndCountFile = $Configuration::jobRunningDir."/".$Configuration::trfSizeAndCountFile;
	my $evsTempDirPath  	= $Configuration::jobRunningDir."/".$Configuration::evsTempDir;
	my $errorDir 		    = $Configuration::jobRunningDir."/".$Configuration::errorDir;
	#my $operationsFilePath  = $Configuration::jobRunningDir."/".$Configuration::operationsfile;
	my $pwdPath = Helpers::getIDPWDFile();
	my $engineLockFile = $Configuration::jobRunningDir.'/'.Configuration::ENGINE_LOCKE_FILE;
	#my $doBackupOperationErrorFile = $Configuration::jobRunningDir."/doBackuperror.txt_";
	#my $relativeFileset   = $Configuration::jobRunningDir."/".$Configuration::relativeFileset;
	#my $noRelativeFileset = $Configuration::jobRunningDir."/".$Configuration::noRelativeFileset;
	#my $filesOnly		  = $Configuration::jobRunningDir."/".$Configuration::filesOnly;
	#my $progressDetailsFilePath = $Configuration::jobRunningDir."/".$Configuration::progressDetailsFilePath;

	my ($successFiles, $syncedFiles, $failedFilesCount,$transferredFileSize, $exit_flag) = (0) x 5;
	if($silentBackupFlag == 0){
		system('stty', 'echo');
		system("tput sgr0");
	}
	unless($isEmpty){
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','TOTAL_TRANSFERRED_SIZE','EXIT_FLAG_INDEX');
		($successFiles, $syncedFiles, $failedFilesCount,$transferredFileSize, $exit_flag) = Helpers::getParameterValueFromStatusFileFinal(@StatusFileFinalArray);

		chomp($exit_flag);
		if($Configuration::errStr eq "" and -e $Configuration::errorFilePath) {
			open ERR, "<$Configuration::errorFilePath" or Helpers::traceLog('failed_to_open_file',"errorFilePath in exitCleanup: $Configuration::errorFilePath, Reason: $!");
			$Configuration::errStr .= <ERR>;
			close(ERR);
			chomp($Configuration::errStr);
		}

		if(!-e $pidPath or $exit_flag) {
			$Configuration::cancelFlag = 1;

			# In childprocess, if we exit due to some exit scenario, then this exit_flag will be true with error msg
			my @exit = split("-",$exit_flag,2);
			Helpers::traceLog(" exit = $exit[0] and $exit[1]");
			if (!$exit[0] and $Configuration::errStr eq '') {
				if ($jobType eq 'scheduled') {
					$Configuration::errStr = Helpers::getStringConstant('operation_cancelled_due_to_cutoff');
					if (!-e Helpers::getServicePath()) {
						$Configuration::errStr = Helpers::getStringConstant('operation_cancelled_by_user');
					}
				}
				elsif ($jobType eq 'manual') {
					$Configuration::errStr = Helpers::getStringConstant('operation_cancelled_by_user');
				}
			}
			else {
				if ($exit[1] ne '') {
					$Configuration::errStr = $exit[1];
					# Below section has been added to provide user friendly message and clear
					# instruction in case of password mismatch or encryption verification failed.
					# In this case we are removing the IDPWD file.So that user can login and recreate these files with valid credential.
					if ($Configuration::errStr =~ /password mismatch|encryption verification failed/i) {
						my $tokenMessage = Helpers::getStringConstant('please_login_account_using_login_and_try');
						#$tokenMessage =~ s/___login___/$Configuration::idriveScripts{'login'}/eg;
						$Configuration::errStr = $Configuration::errStr.' '.$tokenMessage."\n";
						unlink($pwdPath);
						if ($jobType == "scheduled") {
							$pwdPath =~ s/_SCH$//g;
							unlink($pwdPath);
						}
					}
					elsif ($Configuration::errStr =~ /failed to get the device information|Invalid device id/i) {
						$Configuration::errStr = $Configuration::errStr.' '.Helpers::getStringConstant('invalid_bkp_location_config_again')."\n";
					} else {
						$Configuration::errStr = Helpers::checkErrorAndLogout($Configuration::errStr);
					}
				}
			}
		}
	}
	unlink($pidPath);
	waitpid($displayProgressBarPid,0);
	wait();
	Helpers::writeOperationSummary($Configuration::evsOperations{'LocalBackupOp'}, $jobType);
	my $subjectLine = Helpers::getEmailSubLine($jobType, 'Local Backup');
	unlink($retryInfo);
	#unlink($incSize);
	unlink($fileForSize);
	unlink($trfSizeAndCountFile);

	Helpers::restoreBackupsetFileConfiguration();
	if(-d $evsTempDirPath) {
		Helpers::rmtree($evsTempDirPath);
	}
	if(-d $errorDir and $errorDir ne '/') {
		system(Helpers::updateLocaleCmd("rm -rf '$errorDir'"));
	}

	if (-e $Configuration::outputFilePath and -s $Configuration::outputFilePath > 0) {
		my $finalOutFile = $Configuration::outputFilePath;
		$finalOutFile =~ s/_Running_/_$Configuration::opStatus\_/;
		Helpers::move($Configuration::outputFilePath, $finalOutFile);

		if (Helpers::loadNotifications()) {
			Helpers::setNotification('update_localbackup_progress', ((split("/", $finalOutFile))[-1]));
			Helpers::setNotification('get_logs') and Helpers::saveNotifications();
		}

		$Configuration::outputFilePath = $finalOutFile;
		$Configuration::finalSummary .= Helpers::getStringConstant('for_more_details_refer_the_log').qq(\n);
		#Concat log file path with job summary. To access both at once while displaying the summary and log file location.
		$Configuration::finalSummary .= "\n".$Configuration::opStatus."\n".$Configuration::errStr;
		Helpers::fileWrite("$Configuration::jobRunningDir/$Configuration::fileSummaryFile",$Configuration::finalSummary);
		if ($silentBackupFlag == 0){
			#It is a generic function used to write content to file.
			Helpers::displayProgressBar($Configuration::progressDetailsFilePath) unless ($isEmpty);
			Helpers::displayFinalSummary('Express Backup Job',"$Configuration::jobRunningDir/$Configuration::fileSummaryFile");
			#Above function display summary on stdout once backup job has completed.
		}
		Helpers::saveLog($finalOutFile);
	}
	unless ($isEmpty) {
		Helpers::sendMail({
				'serviceType' => $jobType,
				'jobType' => 'Express Backup',
				'subject' => $subjectLine,
				'jobStatus' => lc($Configuration::opStatus)
			});
	} else {
		Helpers::sendMail({
				'serviceType' => $jobType,
				'jobType' => 'Express Backup',
				'subject' => $subjectLine,
				'jobStatus' => lc($Configuration::opStatus),
				'errorMsg' => 'NOBACKUPDATA'
			});
	}

	Helpers::removeItems($pidPath.'*');
	removeIntermediateFiles();
	unlink($engineLockFile);

	# need to update the crontab with default values.
	if(defined(${ARGV[0]})  and ${ARGV[0]} eq 'immediate') {
		Helpers::updateCronTabToDefaultVal("localbackup");
	}

	if ($successFiles > 0){#some file has been backed up during the process, getQuota call is done to calculate the fresh quota.
		my $childProc = fork();
		if ($childProc == 0){
			#getQuota();
			Helpers::reCalculateStorageSize(0); #passing argument to avoid error message display
			exit(0);
		}
	}
	exit 0;
}

###################################################
#The signal handler invoked when SIGINT or SIGTERM#
#signal is received by the script                 #
###################################################
sub processTerm {
	my $pidPath  = $Configuration::jobRunningDir."/".$Configuration::pidFile;
	unlink($pidPath) if(-f $pidPath);
	cancelBackupSubRoutine();
	exit(0);
}

#*******************************************************************************************************
# Subroutine		: waitForEnginesToFinish
# Objective			: Cancel the execution of backup script
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#********************************************************************************************************/
sub cancelBackupSubRoutine {
	my $backupUTFpath = $Configuration::jobRunningDir.'/'.$Configuration::utf8File;
	my $info_file     = $Configuration::jobRunningDir."/".$Configuration::infoFile;

	if($Configuration::pidOperationFlag eq "EVS_process") {
		my $psOption = Helpers::getPSoption();
		my $evsCmd   = "ps $psOption | grep \"$Configuration::evsBinaryName\" | grep \'$backupUTFpath\'";
		$evsCmd = Helpers::updateLocaleCmd($evsCmd);
		my $evsRunning  = `$evsCmd`;
		my @evsRunningArr = split("\n", $evsRunning);
		my $arrayData = ($Helpers::machineInfo =~ /freebsd/i)? 1 : 3;

		foreach(@evsRunningArr) {
			next if($_ =~ /$evsCmd|grep/);

			my $pid = (split(/[\s\t]+/, $_))[$arrayData];
			my $scriptTerm = system(Helpers::updateLocaleCmd("kill -9 $pid"));
			Helpers::traceLog('failed_to_kil', ' Backup') if(defined($scriptTerm) && $scriptTerm != 0 && $scriptTerm ne '');
		}

		return;
	}

	waitpid($Configuration::pidOutputProcess, 0) if($Configuration::pidOutputProcess && $Configuration::pidOperationFlag eq "main");
	Helpers::waitForChildProcess();
	exit(0) if($Configuration::pidOperationFlag eq "DisplayProgress");

	if($Configuration::pidOperationFlag eq "GenerateFile") {
		open FD_WRITE, ">>", $info_file or Helpers::display(['failed_to_open_file'," info_file in cancelSubRoutine: $info_file to write, Reason:$!"]); # die handle?
		autoflush FD_WRITE;
		#print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "TOTALFILES $Configuration::totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $Configuration::nonExistsCount\n";
		print FD_WRITE "DENIEDCOUNT $Configuration::noPermissionCount\n";
		print FD_WRITE "MISSINGCOUNT $Configuration::missingCount\n";
		close FD_WRITE;
		close NEWFILE;
		$Configuration::pidOperationFlag ='';
		exit(0);
	}

	if($Configuration::pidOperationFlag eq "main") {
		waitpid($generateFilesPid, WNOHANG) if($generateFilesPid);
		if(-e $info_file and ($totalFiles == 0 or $totalFiles !~ /\d+/)) {
			my $fileCountCmd = "cat '$info_file' | grep -m1 \"^TOTALFILES\"";
			$totalFiles = `$fileCountCmd`;
			$totalFiles =~ s/TOTALFILES//;
			chomp($totalFiles) if($totalFiles ne '');
		}

		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			Helpers::traceLog(" Unable to get total files count");
		} else {
			$Configuration::totalFiles = $totalFiles;
		}

		if($Configuration::nonExistsCount == 0 and -e $info_file) {
			my $nonExistCheckCmd = "cat '$info_file' | grep -m1 \"^FAILEDCOUNT\"";
			$nonExistCheckCmd = Helpers::updateLocaleCmd($nonExistCheckCmd);
			$Configuration::nonExistsCount = `$nonExistCheckCmd`;
			$Configuration::nonExistsCount =~ s/FAILEDCOUNT//;
			Helpers::Chomp(\$Configuration::nonExistsCount);
		}

		# waitpid($Configuration::pidOutputProcess, 0) if($Configuration::pidOutputProcess);
		exitCleanup($Configuration::errStr);
	}
}

#*******************************************************************************************************
# Subroutine			: waitForEnginesToFinish
# Objective				: Wait for all engines to finish in backup.
# Added By				: Vijay Vinoth
#********************************************************************************************************/
sub waitForEnginesToFinish{
	my $res = '';
	my $engineLockFile = $Configuration::jobRunningDir.'/'.Configuration::ENGINE_LOCKE_FILE;
	while(@BackupForkchilds > 0) {
		foreach (@BackupForkchilds) {
			$res = waitpid($_, 0);
			if ($res > 0 or $res == -1) {
				#delete $BackupForkchilds{$key};
				@BackupForkchilds = grep(!/$_/, @BackupForkchilds);
			}
		}
	}

	while(Helpers::isAnyEngineRunning($engineLockFile)){
		sleep(1);
	}

	return;
}

#****************************************************************************************************
# Subroutine Name : doBackupOperation.
# Objective       : This subroutine performs the actual task of backing up files. It creates
#							a child process which executes the backup command. It also creates a process
#							which continuously monitors the temporary output file. At the end of backup,
#							it inspects the temporary error file if present. It then deletes the temporary
#							output file, temporary error file and the temporary directory created by
#							idevsutil binary.
# Usage			  : doBackupOperation($line);
# Where			  : $line :
# Modified By     : Deepak Chaurasia, Vijay Vinoth, Senthil Pandian
#*****************************************************************************************************/
sub doBackupOperation
{
	my $parameters       = $_[0];
	my $silentBackupFlag = $_[1];
	my $scheduleFlag     = $_[2];
	my $operationEngineId = $_[3];
	my $retry_failedfiles_index = $_[4];
	my $pidPath       = $Configuration::jobRunningDir."/".$Configuration::pidFile;
	my $backupUTFpath = $Configuration::jobRunningDir.'/'.$Configuration::utf8File."_".$operationEngineId;
	my $evsOutputFile = $Configuration::jobRunningDir.'/'.$Configuration::evsOutputFile.'_'.$operationEngineId;
	my $evsErrorFile  = $Configuration::jobRunningDir.'/'.$Configuration::evsErrorFile.'_'.$operationEngineId;
	my $isDedup  	  = Helpers::getUserConfiguration('DEDUP');
	my $bwPath     	  = Helpers::getUserProfilePath()."/bw.txt";
	my $defLocal	  = (-e Helpers::getIDPVTFile())?0:1;
	my $backupHost	  = Helpers::getUserConfiguration('BACKUPLOCATION');
	if ($isDedup eq 'off' and $Configuration::jobType eq "LocalBackup") {
		my @backupTo = split("/",$backupHost);
		$backupHost	 = (substr($backupHost,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
	}
	my $userName 	      = Helpers::getUsername();
	my $backupLocationDir = Helpers::getLocalBackupDir();
	my @parameter_list = split /\' \'/,$parameters,3;
	my $engineLockFile = $Configuration::jobRunningDir."/".Configuration::ENGINE_LOCKE_FILE;
	$backupUTFpath = $backupUTFpath;

	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	if (!flock($startPidFileLock, 1)){
		Helpers::traceLog("Failed to lock engine file");
		return 0;
	}

	Helpers::fileWrite($pidPath.'_evs_'.$operationEngineId, 1); #Added for Harish_2.19_7_7, Harish_2.19_6_7
	open(my $engineFp, ">>", $pidPath.'_'.$operationEngineId) or return 0;
	if (!flock($engineFp, 2)){
		Helpers::display('failed_to_lock',1);
		return 0;
	}

	Helpers::createUTF8File(['EXPRESSBACKUP',$backupUTFpath],
				$parameter_list[2],
				$bwPath,
				$defLocal,
				$Configuration::jobRunningDir."/",
				$parameter_list[1],
				$evsOutputFile,
				$evsErrorFile,
				$backupLocationDir,
				$parameter_list[0],
				$backupLocationDir
				) or Helpers::retreat('failed_to_create_utf8_file');

	my $backupPid = fork();
	if (!defined $backupPid) {
		$Configuration::errStr = Helpers::getStringConstant('cannot_fork_child')."\n";
		#return BACKUP_PID_FAIL;
		return 2;
	}

	if ($backupPid == 0) {
		$Configuration::pidOperationFlag = "EVS_process";
		if ( -e $pidPath) {
			#exec($idevsutilCommandLine);
			my @responseData = Helpers::runEVS('item',1);
			if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
				if (open(ERRORFILE, ">> $Configuration::errorFilePath"))
				{
					autoflush ERRORFILE;
					print ERRORFILE $Configuration::errStr;
					close ERRORFILE;
					chmod $Configuration::filePermission, $Configuration::errorFilePath;
				}
				else {
					Helpers::traceLog('failed_to_open_file',"errorFilePath in doBackupOperation:".$Configuration::errorFilePath.", Reason:$! \n");
				}
			}

			if (open OFH, ">>", $evsOutputFile) {
				print OFH "\nCHILD_PROCESS_COMPLETED\n";
				close OFH;
				chmod $Configuration::filePermission, $evsOutputFile;
			}
			else {
				$Configuration::errStr = Helpers::getStringConstant('failed_to_open_file').": $Configuration::outputFilePath in doBackupOperation. Reason: $!";
				Helpers::display($Configuration::errStr);
				Helpers::traceLog($Configuration::errStr);
				return 0;
			}
		}
		exit 1;
	}

	$Configuration::pidOperationFlag = "child_process";
	$Configuration::pidOutputProcess = $backupPid;
	exit(1) unless(-f $pidPath);

	#$isLocalBackup = 0;
	my $currentDir = Helpers::getAppPath();
	my $workingDir = $currentDir;
	$workingDir =~ s/\'/\'\\''/g;
	my $tmpoutputFilePath = $Configuration::outputFilePath;
	$tmpoutputFilePath =~ s/\'/\'\\''/g;
	my $TmpBackupSetFile = $parameter_list[2];
	$TmpBackupSetFile =~ s/\'/\'\\''/g;
	my $TmpSource = $parameter_list[0];
	$TmpSource =~ s/\'/\'\\''/g;
	my $tmp_jobRunningDir = $Configuration::jobRunningDir;
	$tmp_jobRunningDir =~ s/\'/\'\\''/g;
	my $tmpBackupHost = $backupHost;
	$tmpBackupHost =~ s/\'/\'\\''/g;

	my $fileChildProcessPath = $currentDir.'/'.$Configuration::idriveScripts{'operations'};
	my $bwThrottle 			 = Helpers::getUserConfiguration('BWTHROTTLE');
	my $backupPathType       = Helpers::getUserConfiguration('BACKUPTYPE');
	my @param = join ("\n",('LOCAL_BACKUP_OPERATION',$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$Configuration::progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$scheduleFlag,$operationEngineId));

	Helpers::writeParamToFile("$tmp_jobRunningDir/$Configuration::operationsfile"."_".$operationEngineId,@param);
	my $perlPath = Helpers::getPerlBinaryPath();
	#traceLog("cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\'");
	{
		#my $execString = getStringConstant('support_file_exec_string');
		my $cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\' \'$operationEngineId\' \'$retry_failedfiles_index\'";
		$cmd = Helpers::updateLocaleCmd($cmd);
		system($cmd);
	}

	waitpid($backupPid, 0);
	unlink($pidPath.'_evs_'.$operationEngineId);
	Helpers::waitForChildProcess($pidPath.'_proc_'.$operationEngineId);
	unlink($pidPath.'_'.$operationEngineId);

	return 0 unless(Helpers::updateServerAddr());

	unlink($parameter_list[2]);
	unlink($evsOutputFile.'_'.$operationEngineId);
	flock($startPidFileLock, 8);
	flock($engineFp, 8);

	return 0 if (-e $Configuration::errorFilePath && -s $Configuration::errorFilePath);
	return 1; #Success
}
