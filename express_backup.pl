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

use Common;
use AppConfig;
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

Common::waitForUpdate();
Common::initiateMigrate();

init();

#*******************************************************************************
# This script starts & ends in init()
#
# Added By   : Senthil Pandian
# Modified By: Yogesh Kumar
#*******************************************************************************
sub init {
	system(Common::updateLocaleCmd("clear")) and Common::retreat('failed_to_clear_screen') unless ($cmdNumOfArgs > -1);
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	if ($cmdNumOfArgs > -1) {
		if ((${ARGV[0]} eq "SCHEDULED") or (${ARGV[0]} eq "immediate")) {
			$AppConfig::callerEnv = 'BACKGROUND';
			Common::setUsername($ARGV[1]);
			$jobType = 'scheduled';
			$silentBackupFlag = 1;
			$isScheduledJob = 1;
			Common::loadUserConfiguration();
		}
		elsif (${ARGV[0]} eq '--silent' or ${ARGV[0]} eq 'dashboard' or ${ARGV[0]} eq 'immediate') {
			$AppConfig::callerEnv = 'BACKGROUND';
			$silentBackupFlag = 1;
		}
	}

	if ($jobType eq 'manual') {
		Common::loadUsername() or Common::retreat('login_&_try_again');
		my $errorKey = Common::loadUserConfiguration();
		Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);
	}

	unless ($silentBackupFlag) {
		Common::isLoggedin() or Common::retreat('login_&_try_again');
		Common::displayHeader();
	}

	my $username      = Common::getUsername();
	my $servicePath   = Common::getServicePath();
	my $jobRunningDir = Common::getJobsPath('localbackup');

	Common::checkAccountStatus($silentBackupFlag? 0 : 1);

	$AppConfig::jobRunningDir = $jobRunningDir;
	$AppConfig::jobType		  = "LocalBackup";
	if(!Common::loadEVSBinary()){
		Common::sendFailureNotice($username,'update_localbackup_progress',$jobType);
		Common::retreat('unable_to_find_or_execute_evs_binary');
	}

	my $dedup  	      = Common::getUserConfiguration('DEDUP');
	my $serverRoot    = Common::getUserConfiguration('SERVERROOT');
	my $backupTo	  = Common::getUserConfiguration('BACKUPLOCATION');
	if($dedup eq 'off') {
		my @backupTo = split("/",$backupTo);
		$backupTo	 = (substr($backupTo,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
	}
	if ($dedup eq 'on' and !$serverRoot) {
		(my $deviceID, $backupTo)  = split("#",$backupTo);
		Common::display(["\n",'verifying_your_account_info',"\n"]);
		my %evsDeviceHashOutput = Common::getDeviceHash();
		my $uniqueID = Common::getMachineUID() or Common::retreat('unable_to_find_mac_address');
		$uniqueID .= "_1";
		if(exists($evsDeviceHashOutput{$uniqueID})){
			$serverRoot  = $evsDeviceHashOutput{$uniqueID}{'server_root'};
			Common::setUserConfiguration('SERVERROOT', $serverRoot);
			Common::saveUserConfiguration() or Common::retreat('failed_to_save_user_configuration');
		}

		if(!$serverRoot){
			Common::display(["\n",'your_account_not_configured_properly',"\n"])  unless ($silentBackupFlag);
			Common::traceLog(Common::getStringConstant('your_account_not_configured_properly'));
			Common::sendFailureNotice($username,'update_localbackup_progress',$jobType);
			exit 1;
		}
	}
	Common::createDir($jobRunningDir, 1);

	#Checking if another job is already in progress
	my $pidPath = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
	if (Common::isFileLocked($pidPath)) {
		Common::retreat('express_backup_running', $silentBackupFlag);
	}
	else {
		Common::fileLock($pidPath);
	}

	#Renaming the log file if backup process terminated improperly
	Common::checkAndRenameFileWithStatus($jobRunningDir, 'localbackup');

	removeIntermediateFiles(); # pre cleanup for all intermediate files and folders.

	$backupsetFile     = Common::getCatfile($jobRunningDir, $AppConfig::backupsetFile);
	#Common::createUpdateBWFile(); #Commented by Senthil: 13-Aug-2018
	$isEmpty = Common::checkPreReq($backupsetFile, lc(Common::getStringConstant('localbackup')), $jobType, 'NOBACKUPDATA');
	if($isEmpty and $isScheduledJob == 0 and $silentBackupFlag == 0) {
		unlink($pidPath);
		Common::retreat(["\n",$AppConfig::errStr]);
	}
	# Commented as per Deepak's instruction: Senthil
	# my $serverAddress = Common::getServerAddress();
	# if ($serverAddress == 0){
		# exitCleanup($AppConfig::errStr);
	# }

	$mountedPath     = Common::getAndSetMountedPath($silentBackupFlag);
	$isEmpty = 1 if($silentBackupFlag and !$mountedPath);
	$expressLocalDir = Common::getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	$localUserPath   = Common::getCatfile($expressLocalDir, $username);
	$AppConfig::expressLocalDir = $expressLocalDir;

	#Verify dbpath.xml file
# TODO: Need to enable for local restore
#	if ($dedup eq 'on') {
#		my @backupLocationDir = Common::getUserBackupDirListFromMountPath($localUserPath);
#		if(scalar(@backupLocationDir)>0) {
#			Common::checkAndCreateDBpathXMLfile($localUserPath, \@backupLocationDir);
#		}
#	}

	#Start creating required file/folder
	my $excludeDirPath = Common::getCatfile($jobRunningDir, $AppConfig::excludeDir);
	my $errorDir       = Common::getCatfile($jobRunningDir, $AppConfig::errorDir);

	$relativeFileset   = Common::getCatfile($jobRunningDir, $AppConfig::relativeFileset);
	$noRelativeFileset = Common::getCatfile($jobRunningDir, $AppConfig::noRelativeFileset);
	$filesOnly         = Common::getCatfile($jobRunningDir, $AppConfig::filesOnly);

	Common::createDir($errorDir, 0);
	Common::createDir($excludeDirPath, 0);

	Common::createLogFiles("BACKUP",ucfirst($jobType));
	Common::createBackupTypeFile() or Common::retreat('failed_to_set_backup_type');
	unless ($silentBackupFlag) {
		if ($dedup eq 'off') {
			my $bl = Common::getUserConfiguration('BACKUPLOCATION');
			Common::display(["\n",'your_current_backup_location_is',"'$bl'."]);
			Common::display(['considered_backup_location_for_express',"'$backupTo'",".\n"]);
		}elsif($dedup eq 'on'){
			$backupTo = (split("#",$backupTo))[1];
			Common::display(["\n",'your_backup_location_is',"'$backupTo'",".\n"]);
		}
		Common::getCursorPos(11,Common::getStringConstant('preparing_file_list')) if (!$isEmpty and -e $pidPath);
	}

	$AppConfig::mailContentHead = Common::writeLogHeader($jobType);
	if (Common::loadNotifications()) {
		Common::setNotification('update_localbackup_progress', ((split("/", $AppConfig::outputFilePath))[-1]));
		Common::saveNotifications();
	}

	startBackup() if(!$isEmpty and -e $pidPath);
	exitCleanup($AppConfig::errStr);
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
	Common::loadFullExclude();
	Common::loadPartialExclude();
	Common::loadRegexExclude();
	Common::createLocalBackupDir(); #Creating the local backup location directories
	Common::createDBPathsXmlFile();
	my $progressDetailsFilePath = $AppConfig::progressDetailsFilePath;
	my $pidPath	  = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
	$generateFilesPid = fork();

	if(!defined $generateFilesPid) {
		Common::traceLog(['cannot_fork_child', "\n"]);
		Common::display(['cannot_fork_child', "\n"]) unless ($silentBackupFlag);
		return 0;
	}

	Common::generateBackupsetFiles() if($generateFilesPid == 0);

	if($isScheduledJob == 0 and $silentBackupFlag == 0){
		$displayProgressBarPid = fork();

		if(!defined $displayProgressBarPid) {
			$AppConfig::errStr = Common::getStringConstant('unable_to_display_progress_bar');
			Common::traceLog($AppConfig::errStr);
			return 0;
		}

		if($displayProgressBarPid == 0) {
			$AppConfig::pidOperationFlag = "DisplayProgress";
			while(1){
				Common::displayProgressBar($progressDetailsFilePath);
				if(!-e $pidPath){
					last;
				}
				#select(undef, undef, undef, 0.1);
				Common::sleepForMilliSec(100); # Sleep for 100 milliseconds
			}
			Common::displayProgressBar($progressDetailsFilePath,Common::getTotalSize($AppConfig::jobRunningDir."/".$AppConfig::fileForSize));
			exit(0);
		}
	}

	my $info_file = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);
	my $retryInfo = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::retryInfo);
	my $maxNumRetryAttempts = 1000;
	my $engineLockFile = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	my $line;
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;

	open(my $handle, '>', $engineLockFile) or traceLog("\n Could not open file '$engineLockFile' $! \n", __FILE__, __LINE__);
	close $handle;
	chmod $AppConfig::filePermission, $engineLockFile;
	my $exec_cores = Common::getSystemCpuCores();
	my $exec_loads;

START:
	if(!open(FD_READ, "<", $info_file)) {
		$AppConfig::errStr = Common::getStringConstant('failed_to_open_file')." info_file in startBackup: $info_file to read, Reason $! \n";
		Common::traceLog($AppConfig::errStr);
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

		my $isEngineRunning = Common::isEngineRunning($pidPath.'_'.$engineID);
		if(!$isEngineRunning){
			while(1){
				last	if(!-e $pidPath or !Common::isAnyEngineRunning($engineLockFile));

				$exec_loads = Common::getLoadAverage();
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
				$AppConfig::errStr = "Cannot fork() child process :  for EVS \n";
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

		if($AppConfig::totalEngineBackup > 1)
		{
			$engineID++;
			if($engineID > $AppConfig::totalEngineBackup){
				$engineID = 1;
				sleep(2);
			}
		}

		Common::killPIDs(\@BackupForkchilds,0);
	}
	Common::waitForEnginesToFinish(\@BackupForkchilds,$engineLockFile);
	close FD_READ;

	$AppConfig::nonExistsCount    = Common::readInfoFile('FAILEDCOUNT');
	$AppConfig::noPermissionCount = Common::readInfoFile('DENIEDCOUNT');
	$AppConfig::missingCount      = Common::readInfoFile('MISSINGCOUNT');

	waitpid($generateFilesPid,0);
	undef @AppConfig::linesStatusFile;
	if($totalFiles == 0 or $totalFiles !~ /\d+/) {
		$totalFiles    = Common::readInfoFile('TOTALFILES');
		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			Common::traceLog("Unable to get total files count");
		}
	}
	$AppConfig::totalFiles = $totalFiles;

	if (-s $retryInfo > 0 && -e $pidPath && $AppConfig::retryCount <= $maxNumRetryAttempts && $exitStatus == 0) {
		if ($AppConfig::retryCount == $maxNumRetryAttempts) {

			for(my $i=1; $i<= $AppConfig::totalEngineBackup; $i++){
				if(-e $statusFilePath."_".$i  and  -s $statusFilePath."_".$i>0){
					Common::readStatusFile($i);
					my $index = "-1";
					$AppConfig::statusHash{'FAILEDFILES_LISTIDX'} = $index;
					Common::putParameterValueInStatusFile($i);
					putParameterValueInStatusFile();
					undef @AppConfig::linesStatusFile;
				}
			}
			$retry_failedfiles_index = -1;
		}

		move($retryInfo, $info_file);
		Common::updateRetryCount();

		#append total file number to info
		if (!open(INFO, ">>",$info_file)){
			$AppConfig::errStr = Common::getStringConstant('failed_to_open_file')." info_file in startBackup : $info_file, Reason $!\n";
			return $AppConfig::errStr;
		}
		print INFO "TOTALFILES $totalFiles\n";
		print INFO "FAILEDCOUNT $AppConfig::nonExistsCount\n";
		print INFO "DENIEDCOUNT $AppConfig::noPermissionCount\n";
		print INFO "MISSINGCOUNT $AppConfig::missingCount\n";
		close INFO;
		chmod $AppConfig::filePermission, $info_file;
		sleep 5; #5 Sec
		Common::traceLog("retrycount:".$AppConfig::retrycount);
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
	my $evsTempDirPath  = $AppConfig::jobRunningDir."/".$AppConfig::evsTempDir;
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;
	my $retryInfo       = $AppConfig::jobRunningDir."/".$AppConfig::retryInfo;
	my $failedFiles     = $AppConfig::jobRunningDir."/".$AppConfig::failedFileName;
	my $infoFile        = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;
	my $filesOnly	    = $AppConfig::jobRunningDir."/".$AppConfig::filesOnly;
	#my $incSize 		= $AppConfig::jobRunningDir."/".$AppConfig::transferredFileSize;
	my $excludeDirPath  = $AppConfig::jobRunningDir."/".$AppConfig::excludeDir;
	my $errorDir 		= $AppConfig::jobRunningDir."/".$AppConfig::errorDir;
	my $utf8File 		= $AppConfig::jobRunningDir."/".$AppConfig::utf8File."_";
	my $relativeFileset     = $AppConfig::jobRunningDir."/".$AppConfig::relativeFileset;
	my $noRelativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::noRelativeFileset;
	my $progressDetailsFilePath = $AppConfig::jobRunningDir."/".$AppConfig::progressDetailsFilePath."_";
	my $engineLockFile  = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	my $summaryFilePath = $AppConfig::jobRunningDir.'/'.$AppConfig::fileSummaryFile;
	my $errorFilePath   = $AppConfig::jobRunningDir."/".$AppConfig::exitErrorFile;

	my $idevsOutputFile	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsOutputFile;
	my $idevsErrorFile 	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsErrorFile;
	my $backupUTFpath   	= $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
	my $operationsFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::operationsfile;
	my $doBackupOperationErrorFile = $AppConfig::jobRunningDir."/doBackuperror.txt_";
	my $minimalErrorRetry = $AppConfig::jobRunningDir."/".$AppConfig::minimalErrorRetry;

	Common::removeItems([$evsTempDirPath, $relativeFileset.'*', $noRelativeFileset.'*', $filesOnly.'*', $infoFile, $retryInfo, $errorDir, $statusFilePath.'*', $excludeDirPath, $failedFiles.'*', $utf8File.'*', $progressDetailsFilePath.'*', $engineLockFile, $summaryFilePath, $errorFilePath]);
	Common::removeItems([$idevsErrorFile.'*', $idevsOutputFile.'*', $backupUTFpath.'*', $operationsFilePath.'*', $doBackupOperationErrorFile.'*', $minimalErrorRetry]);

	return 0;
}

#****************************************************************************************************
# Subroutine		: exitCleanup.
# Objective			: This function will execute the major functions required at the time of exit
# Added By			: Deepak Chaurasia
# Modified By		: Dhritikana, Yogesh Kumar
#*****************************************************************************************************/
sub exitCleanup {
	my $pidPath 			= $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
#	my $idevsOutputFile	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsOutputFile;
#	my $idevsErrorFile 	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsErrorFile;
#	my $backupUTFpath   	= $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
#	my $statusFilePath  	= $AppConfig::jobRunningDir."/".$AppConfig::statusFile;
	my $retryInfo       	= $AppConfig::jobRunningDir."/".$AppConfig::retryInfo;
	#my $incSize 			= $AppConfig::jobRunningDir."/".$AppConfig::transferredFileSize;
	my $fileForSize		    = $AppConfig::jobRunningDir."/".$AppConfig::fileForSize;
	my $trfSizeAndCountFile = $AppConfig::jobRunningDir."/".$AppConfig::trfSizeAndCountFile;
	my $evsTempDirPath  	= $AppConfig::jobRunningDir."/".$AppConfig::evsTempDir;
	my $errorDir 		    = $AppConfig::jobRunningDir."/".$AppConfig::errorDir;
	#my $operationsFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::operationsfile;
	my $pwdPath = Common::getIDPWDFile();
	my $engineLockFile = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	#my $doBackupOperationErrorFile = $AppConfig::jobRunningDir."/doBackuperror.txt_";
	#my $relativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::relativeFileset;
	#my $noRelativeFileset = $AppConfig::jobRunningDir."/".$AppConfig::noRelativeFileset;
	#my $filesOnly		  = $AppConfig::jobRunningDir."/".$AppConfig::filesOnly;
	#my $progressDetailsFilePath = $AppConfig::jobRunningDir."/".$AppConfig::progressDetailsFilePath;

	my ($successFiles, $syncedFiles, $failedFilesCount,$transferredFileSize, $exit_flag) = (0) x 5;
	if($silentBackupFlag == 0){
		system('stty', 'echo');
		system("tput sgr0");
	}
	unless($isEmpty){
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','TOTAL_TRANSFERRED_SIZE','EXIT_FLAG_INDEX');
		($successFiles, $syncedFiles, $failedFilesCount,$transferredFileSize, $exit_flag) = Common::getParameterValueFromStatusFileFinal(@StatusFileFinalArray);

		chomp($exit_flag);
		if($AppConfig::errStr eq "" and -e $AppConfig::errorFilePath) {
			open ERR, "<$AppConfig::errorFilePath" or Common::traceLog('failed_to_open_file',"errorFilePath in exitCleanup: $AppConfig::errorFilePath, Reason: $!");
			$AppConfig::errStr .= <ERR>;
			close(ERR);
			chomp($AppConfig::errStr);
		}

		if(!-e $pidPath or $exit_flag) {
			$AppConfig::cancelFlag = 1;

			# In childprocess, if we exit due to some exit scenario, then this exit_flag will be true with error msg
			my @exit = split("-",$exit_flag,2);
			Common::traceLog(" exit = $exit[0] and $exit[1]");
			if (!$exit[0] and $AppConfig::errStr eq '') {
				if ($jobType eq 'scheduled') {
					$AppConfig::errStr = Common::getStringConstant('operation_cancelled_due_to_cutoff');
					if (!-e Common::getServicePath()) {
						$AppConfig::errStr = Common::getStringConstant('operation_cancelled_by_user');
					}
				}
				elsif ($jobType eq 'manual') {
					$AppConfig::errStr = Common::getStringConstant('operation_cancelled_by_user');
				}
			}
			else {
				if ($exit[1] ne '') {
					$AppConfig::errStr = $exit[1];
					Common::checkAndUpdateAccStatError(Common::getUsername(), $AppConfig::errStr);
					# Below section has been added to provide user friendly message and clear
					# instruction in case of password mismatch or encryption verification failed.
					# In this case we are removing the IDPWD file.So that user can login and recreate these files with valid credential.
					if ($AppConfig::errStr =~ /password mismatch|encryption verification failed/i) {
						my $tokenMessage = Common::getStringConstant('please_login_account_using_login_and_try');
						#$tokenMessage =~ s/___login___/$AppConfig::idriveScripts{'login'}/eg;
						$AppConfig::errStr = $AppConfig::errStr.' '.$tokenMessage."\n";
						unlink($pwdPath);
						if ($jobType == "scheduled") {
							$pwdPath =~ s/_SCH$//g;
							unlink($pwdPath);
						}
					}
					elsif ($AppConfig::errStr =~ /failed to get the device information|Invalid device id/i) {
						$AppConfig::errStr = $AppConfig::errStr.' '.Common::getStringConstant('invalid_bkp_location_config_again')."\n";
					} else {
						$AppConfig::errStr = Common::checkErrorAndLogout($AppConfig::errStr);
					}
				}
			}
		}
	}
	unlink($pidPath);
	waitpid($displayProgressBarPid,0);
	wait();
	Common::writeOperationSummary($AppConfig::evsOperations{'LocalBackupOp'}, $jobType);
	my $subjectLine = Common::getEmailSubLine($jobType, 'Local Backup');
	unlink($retryInfo);
	#unlink($incSize);
	unlink($fileForSize);
	unlink($trfSizeAndCountFile);

	Common::restoreBackupsetFileConfiguration();
	if(-d $evsTempDirPath) {
		Common::rmtree($evsTempDirPath);
	}
	if(-d $errorDir and $errorDir ne '/') {
		system(Common::updateLocaleCmd("rm -rf '$errorDir'"));
	}

	if (-e $AppConfig::outputFilePath and -s $AppConfig::outputFilePath > 0) {
		my $finalOutFile = $AppConfig::outputFilePath;
		$finalOutFile =~ s/_Running_/_$AppConfig::opStatus\_/;
		Common::move($AppConfig::outputFilePath, $finalOutFile);

		if (Common::loadNotifications()) {
			Common::setNotification('update_localbackup_progress', ((split("/", $finalOutFile))[-1]));
			Common::setNotification('get_logs') and Common::saveNotifications();
		}

		$AppConfig::outputFilePath = $finalOutFile;
		$AppConfig::finalSummary .= Common::getStringConstant('for_more_details_refer_the_log').qq(\n);
		#Concat log file path with job summary. To access both at once while displaying the summary and log file location.
		$AppConfig::finalSummary .= "\n".$AppConfig::opStatus."\n".$AppConfig::errStr;
		Common::fileWrite("$AppConfig::jobRunningDir/$AppConfig::fileSummaryFile",$AppConfig::finalSummary);
		if ($silentBackupFlag == 0){
			#It is a generic function used to write content to file.
			Common::displayProgressBar($AppConfig::progressDetailsFilePath) unless ($isEmpty);
			Common::displayFinalSummary('Express Backup Job',"$AppConfig::jobRunningDir/$AppConfig::fileSummaryFile");
			#Above function display summary on stdout once backup job has completed.
		}
		Common::saveLog($finalOutFile);
	}
	unless ($isEmpty) {
		Common::sendMail({
				'serviceType' => $jobType,
				'jobType' => 'Express Backup',
				'subject' => $subjectLine,
				'jobStatus' => lc($AppConfig::opStatus)
			});
	} else {
		Common::sendMail({
				'serviceType' => $jobType,
				'jobType' => 'Express Backup',
				'subject' => $subjectLine,
				'jobStatus' => lc($AppConfig::opStatus),
				'errorMsg' => 'NOBACKUPDATA'
			});
	}

	Common::removeItems($pidPath.'*');
	removeIntermediateFiles();
	unlink($engineLockFile);

	# need to update the crontab with default values.
	if(defined(${ARGV[0]})  and ${ARGV[0]} eq 'immediate') {
		Common::updateCronTabToDefaultVal("localbackup");
	}

	if ($successFiles > 0){#some file has been backed up during the process, getQuota call is done to calculate the fresh quota.
		my $childProc = fork();
		if ($childProc == 0){
			#getQuota();
			Common::reCalculateStorageSize(0); #passing argument to avoid error message display
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
	my $pidPath  = $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
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
	my $backupUTFpath = $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
	my $info_file     = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;

	if($AppConfig::pidOperationFlag eq "EVS_process") {
		my $psOption = Common::getPSoption();
		my $evsCmd   = "ps $psOption | grep \"$AppConfig::evsBinaryName\" | grep \'$backupUTFpath\'";
		$evsCmd = Common::updateLocaleCmd($evsCmd);
		my $evsRunning  = `$evsCmd`;
		my @evsRunningArr = split("\n", $evsRunning);
		my $arrayData = ($Common::machineInfo =~ /freebsd/i)? 1 : 3;

		foreach(@evsRunningArr) {
			next if($_ =~ /$evsCmd|grep/);

			my $pid = (split(/[\s\t]+/, $_))[$arrayData];
			my $scriptTerm = system(Common::updateLocaleCmd("kill -9 $pid"));
			Common::traceLog('failed_to_kil', ' Backup') if(defined($scriptTerm) && $scriptTerm != 0 && $scriptTerm ne '');
		}

		return;
	}

	waitpid($AppConfig::pidOutputProcess, 0) if($AppConfig::pidOutputProcess && $AppConfig::pidOperationFlag eq "main");
	Common::waitForChildProcess();
	exit(0) if($AppConfig::pidOperationFlag eq "DisplayProgress");

	if($AppConfig::pidOperationFlag eq "GenerateFile") {
		open FD_WRITE, ">>", $info_file or Common::display(['failed_to_open_file'," info_file in cancelSubRoutine: $info_file to write, Reason:$!"]); # die handle?
		autoflush FD_WRITE;
		#print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "TOTALFILES $AppConfig::totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $AppConfig::nonExistsCount\n";
		print FD_WRITE "DENIEDCOUNT $AppConfig::noPermissionCount\n";
		print FD_WRITE "MISSINGCOUNT $AppConfig::missingCount\n";
		close FD_WRITE;
		close NEWFILE;
		$AppConfig::pidOperationFlag ='';
		exit(0);
	}

	if($AppConfig::pidOperationFlag eq "main") {
		waitpid($generateFilesPid, WNOHANG) if($generateFilesPid);
		if(-e $info_file and ($totalFiles == 0 or $totalFiles !~ /\d+/)) {
			my $fileCountCmd = "cat '$info_file' | grep -m1 \"^TOTALFILES\"";
			$totalFiles = `$fileCountCmd`;
			$totalFiles =~ s/TOTALFILES//;
			chomp($totalFiles) if($totalFiles ne '');
		}

		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			Common::traceLog(" Unable to get total files count");
		} else {
			$AppConfig::totalFiles = $totalFiles;
		}

		if($AppConfig::nonExistsCount == 0 and -e $info_file) {
			my $nonExistCheckCmd = "cat '$info_file' | grep -m1 \"^FAILEDCOUNT\"";
			$nonExistCheckCmd = Common::updateLocaleCmd($nonExistCheckCmd);
			$AppConfig::nonExistsCount = `$nonExistCheckCmd`;
			$AppConfig::nonExistsCount =~ s/FAILEDCOUNT//;
			Common::Chomp(\$AppConfig::nonExistsCount);
		}

		# waitpid($AppConfig::pidOutputProcess, 0) if($AppConfig::pidOutputProcess);
		exitCleanup($AppConfig::errStr);
	}
}

#*******************************************************************************************************
# Subroutine			: waitForEnginesToFinish
# Objective				: Wait for all engines to finish in backup.
# Added By				: Vijay Vinoth
#********************************************************************************************************/
sub waitForEnginesToFinish{
	my $res = '';
	my $engineLockFile = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	while(@BackupForkchilds > 0) {
		foreach (@BackupForkchilds) {
			$res = waitpid($_, 0);
			if ($res > 0 or $res == -1) {
				#delete $BackupForkchilds{$key};
				@BackupForkchilds = grep(!/$_/, @BackupForkchilds);
			}
		}
	}

	while(Common::isAnyEngineRunning($engineLockFile)){
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
	my $pidPath       = $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
	my $backupUTFpath = $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File."_".$operationEngineId;
	my $evsOutputFile = $AppConfig::jobRunningDir.'/'.$AppConfig::evsOutputFile.'_'.$operationEngineId;
	my $evsErrorFile  = $AppConfig::jobRunningDir.'/'.$AppConfig::evsErrorFile.'_'.$operationEngineId;
	my $isDedup  	  = Common::getUserConfiguration('DEDUP');
	my $bwPath     	  = Common::getUserProfilePath()."/bw.txt";
	my $defLocal	  = (-e Common::getIDPVTFile())?0:1;
	my $backupHost	  = Common::getUserConfiguration('BACKUPLOCATION');
	if ($isDedup eq 'off' and $AppConfig::jobType eq "LocalBackup") {
		my @backupTo = split("/",$backupHost);
		$backupHost	 = (substr($backupHost,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
	}
	my $userName 	      = Common::getUsername();
	my $backupLocationDir = Common::getLocalBackupDir();
	my @parameter_list = split /\' \'/,$parameters,3;
	my $engineLockFile = $AppConfig::jobRunningDir."/".AppConfig::ENGINE_LOCKE_FILE;
	$backupUTFpath = $backupUTFpath;

	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	if (!flock($startPidFileLock, 1)){
		Common::traceLog("Failed to lock engine file");
		return 0;
	}

	Common::fileWrite($pidPath.'_evs_'.$operationEngineId, 1); #Added for Harish_2.19_7_7, Harish_2.19_6_7
	open(my $engineFp, ">>", $pidPath.'_'.$operationEngineId) or return 0;
	if (!flock($engineFp, 2)){
		Common::display('failed_to_lock',1);
		return 0;
	}

	Common::createUTF8File(['EXPRESSBACKUP',$backupUTFpath],
				$parameter_list[2],
				$bwPath,
				$defLocal,
				$AppConfig::jobRunningDir."/",
				$parameter_list[1],
				$evsOutputFile,
				$evsErrorFile,
				$backupLocationDir,
				$parameter_list[0],
				$backupLocationDir
				) or Common::retreat('failed_to_create_utf8_file');

	my $backupPid = fork();
	if (!defined $backupPid) {
		$AppConfig::errStr = Common::getStringConstant('cannot_fork_child')."\n";
		#return BACKUP_PID_FAIL;
		return 2;
	}

	if ($backupPid == 0) {
		$AppConfig::pidOperationFlag = "EVS_process";
		if ( -e $pidPath) {
			#exec($idevsutilCommandLine);
			my @responseData = Common::runEVS('item',1);
			if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
				if (open(ERRORFILE, ">> $AppConfig::errorFilePath"))
				{
					autoflush ERRORFILE;
					print ERRORFILE $AppConfig::errStr;
					close ERRORFILE;
					chmod $AppConfig::filePermission, $AppConfig::errorFilePath;
				}
				else {
					Common::traceLog('failed_to_open_file',"errorFilePath in doBackupOperation:".$AppConfig::errorFilePath.", Reason:$! \n");
				}
			}

			if (open OFH, ">>", $evsOutputFile) {
				print OFH "\nCHILD_PROCESS_COMPLETED\n";
				close OFH;
				chmod $AppConfig::filePermission, $evsOutputFile;
			}
			else {
				$AppConfig::errStr = Common::getStringConstant('failed_to_open_file').": $AppConfig::outputFilePath in doBackupOperation. Reason: $!";
				Common::display($AppConfig::errStr);
				Common::traceLog($AppConfig::errStr);
				return 0;
			}
		}
		exit 1;
	}

	$AppConfig::pidOperationFlag = "child_process";
	$AppConfig::pidOutputProcess = $backupPid;
	exit(1) unless(-f $pidPath);

	#$isLocalBackup = 0;
	my $currentDir = Common::getAppPath();
	my $workingDir = $currentDir;
	$workingDir =~ s/\'/\'\\''/g;
	my $tmpoutputFilePath = $AppConfig::outputFilePath;
	$tmpoutputFilePath =~ s/\'/\'\\''/g;
	my $TmpBackupSetFile = $parameter_list[2];
	$TmpBackupSetFile =~ s/\'/\'\\''/g;
	my $TmpSource = $parameter_list[0];
	$TmpSource =~ s/\'/\'\\''/g;
	my $tmp_jobRunningDir = $AppConfig::jobRunningDir;
	$tmp_jobRunningDir =~ s/\'/\'\\''/g;
	my $tmpBackupHost = $backupHost;
	$tmpBackupHost =~ s/\'/\'\\''/g;

	my $fileChildProcessPath = $currentDir.'/'.$AppConfig::idriveScripts{'operations'};
	my $bwThrottle 			 = Common::getUserConfiguration('BWTHROTTLE');
	my $backupPathType       = Common::getUserConfiguration('BACKUPTYPE');
	my @param = join ("\n",('LOCAL_BACKUP_OPERATION',$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$AppConfig::progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$scheduleFlag,$operationEngineId));

	Common::writeParamToFile("$tmp_jobRunningDir/$AppConfig::operationsfile"."_".$operationEngineId,@param);
	my $perlPath = Common::getPerlBinaryPath();
	#traceLog("cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\'");
	{
		#my $execString = getStringConstant('support_file_exec_string');
		my $cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\' \'$operationEngineId\' \'$retry_failedfiles_index\'";
		$cmd = Common::updateLocaleCmd($cmd);
		system($cmd);
	}

	waitpid($backupPid, 0);
	unlink($pidPath.'_evs_'.$operationEngineId);
	Common::waitForChildProcess($pidPath.'_proc_'.$operationEngineId);
	unlink($pidPath.'_'.$operationEngineId);

	return 0 unless(Common::updateServerAddr());

	unlink($parameter_list[2]);
	unlink($evsOutputFile.'_'.$operationEngineId);
	flock($startPidFileLock, 8);
	flock($engineFp, 8);

	return 0 if (-e $AppConfig::errorFilePath && -s $AppConfig::errorFilePath);
	return 1; #Success
}
