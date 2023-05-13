#!/usr/bin/env perl
#-------------------------------------------------------------------------------
# Easily transfer bulk data from Linux machines via physical storage shipment.
#
# Created By : Senthil Pandian @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#-------------------------------------------------------------------------------
system('clear');
use strict;
use POSIX qw/mktime/;
use POSIX ":sys_wait_h";
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use File::Basename;
use Fcntl qw(:flock SEEK_END);

use Common;
use AppConfig;
use constant BACKUP_PID_FAIL => 2;

my $cmdNumOfArgs = $#ARGV;
my $jobType = 'manual';
my ($silentBackupFlag, $filesOnlyCount, $exitStatus, $prevFailedCount, $retry_failedfiles_index) = (0) x 5;
#our $signalTerm = 0;
our ($mountedPath, $expressLocalDir, $localUserPath, $backupsetFile, $relativeFileset, $noRelativeFileset, $filesOnly);
my ($generateFilesPid, $totalFiles, $readySyncFiles, @BackupForkchilds, $backupsetFilePath, $displayProgressBarPid);

my $engineID = 1;
my ($isScheduledJob, $isBackupSetEmpty,$isValidEncType,$isValidEncKey,$isValidMountPath) = (0) x 5;
use constant BACKUP_SUCCESS => 1;
my $playPause = 'running';

##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script during backup #
##############################################
$SIG{INT}  = \&processTerm;
$SIG{TSTP} = \&processTerm;
$SIG{QUIT} = \&processTerm;
$SIG{KILL} = \&processTerm;
$SIG{USR1} = \&processTerm;
$SIG{TERM} = \&processTerm;
$SIG{ABRT} = \&processTerm;
$SIG{PWR}  = \&processTerm if(exists $SIG{'PWR'});
$SIG{WINCH} = \&Common::changeSizeVal;

Common::waitForUpdate();
Common::initiateMigrate();

init();

#*******************************************************************************
# This script starts & ends in init()
#
# Added By   : Senthil Pandian
# Modified By: Yogesh Kumar, Sabin Cheruvattil
#*******************************************************************************
sub init {
	system(Common::updateLocaleCmd("clear")) and Common::retreat('failed_to_clear_screen') unless ($cmdNumOfArgs > -1);
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::verifyVersionConfig();

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

	Common::traceLog(['backup_started']);
	# Express backup path under Online backup path is deprecated
	Common::fixPathDeprecations();
	Common::restartAllCDPServices() unless(Common::isCDPServicesRunning());

	my $dedup  	      = Common::getUserConfiguration('DEDUP');
	my $serverRoot    = Common::getUserConfiguration('SERVERROOT');
	my $backupTo	  = Common::getUserConfiguration('BACKUPLOCATION');
	if($dedup eq 'off') {
		my @backupTo = split("/",$backupTo);
		$backupTo	 = (substr($backupTo,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
	} elsif (!$serverRoot) {
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

	# Checking if another job is already in progress
	my $pidPath = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
	if (Common::isFileLocked($pidPath)) {
		Common::retreat('local_backup_running', $silentBackupFlag);
	}

	my $lockStatus = Common::fileLock($pidPath);
	Common::retreat([$lockStatus.'_file_lock_status', ": ", $pidPath]) if($lockStatus);

	#Renaming the log file if backup process terminated improperly
	Common::checkAndRenameFileWithStatus($jobRunningDir, 'localbackup');

	removeIntermediateFiles(); # pre cleanup for all intermediate files and folders.
	my $totalFileCountFile  = $AppConfig::jobRunningDir."/".$AppConfig::totalFileCountFile;
	Common::removeItems($totalFileCountFile);

	my $summaryFilePath = Common::getCatfile($jobRunningDir, $AppConfig::fileSummaryFile);
	Common::removeItems($summaryFilePath);

	Common::copyBWFile('localbackup');

	$backupsetFile = Common::getCatfile($jobRunningDir, $AppConfig::backupsetFile);
	$isBackupSetEmpty = Common::checkPreReq($backupsetFile, 'localbackup', 'NOBACKUPDATA');

	my $dbpath	= Common::getJobsPath('localbackup', 'path');
	my $dbfile	= Common::getCatfile($dbpath, $AppConfig::dbname);
	Common::createDBCleanupReq($dbpath) if($isBackupSetEmpty and -f $dbpath and Common::isDBWriterRunning());

	my ($dbmpc, $dbhash);
	my ($readysync, $expstatreset) = (0, 0);
	my $keyverified = 1;
	$mountedPath = Common::getUserConfiguration('LOCALMOUNTPOINT');
	unless($isBackupSetEmpty) {
		# Get ready sync files
		$readysync	= Common::getReadySyncItemCount($dbpath);
		if (Common::getUserConfiguration('DEDUP') eq 'on') {
			my @verdevices = Common::fetchAllDevices();
			if (exists($verdevices[0]{'MSG'}) and $verdevices[0]{'MSG'} =~ 'No devices found') {
				Common::createBackupStatRenewalByJob('backup');

				if($isScheduledJob == 0 and $silentBackupFlag == 0) {
					Common::doAccountResetLogout(1);
					Common::retreat(["\n", 'invalid_bkp_location_config_again']);
				}

				unlink($pidPath);
				$AppConfig::errStr = '2-failed to get the device information';
			}
		}

		# Added to validate encryption type & private key
		unless($AppConfig::errStr =~ /^2\-/) {
			#validate user account
			Common::display('verifying_your_account_info', 1);
			($isValidEncType, $AppConfig::errStr) = Common::validateEncryptionType();
			if($isValidEncType) {
				if(-f Common::getIDPVTFile()) {
					$AppConfig::pvtKeyHash = Common::getFileContents(Common::getIDPVTFile());
				}

				($isValidEncKey, $AppConfig::errStr) = Common::validateEncryptionKey();
				if($isValidEncKey) {
					 Common::display(['OK',"\n"]);
					($isValidMountPath, $mountedPath) = Common::getAndSetMountedPath($silentBackupFlag, 1);
					$AppConfig::errStr = Common::getStringConstant($mountedPath) unless($isValidMountPath);
				} else {
					$keyverified = 0;
				}
			}
			elsif($AppConfig::errStr =~ /Failed to authenticate/i) {
				if($isScheduledJob == 0 and $silentBackupFlag == 0) {
					Common::retreat(["\n", $AppConfig::errStr]);
				} else {
					$AppConfig::errStr = '2-' . $AppConfig::errStr;
				}
			}
			else {
				$keyverified = 0;
			}
		}
	}

    if($isScheduledJob and $AppConfig::errStr ne '' and $AppConfig::errStr =~ /Username or Password not found/i) {
        $AppConfig::errStr = Common::getStringConstant('operation_could_not_be_completed_reason').'password mismatch. '.Common::getStringConstant('login_&_try_again');
    }

	if(($isBackupSetEmpty or !$isValidEncType or !$isValidEncKey or !$isValidMountPath)) {
		if($isScheduledJob == 0 and $silentBackupFlag == 0) {
			unlink($pidPath);

			unless($keyverified) {
				Common::doAccountResetLogout(1);
				Common::retreat(["\n", 'your_account_not_configured_properly']);
			} else {
				Common::retreat(["\n", $AppConfig::errStr]);
			}
		}

		$AppConfig::errStr = '2-' . $AppConfig::errStr;
	}

    # Common::checkAndStartDBReIndex($mountedPath,$AppConfig::jobType);

	unless($AppConfig::errStr) {
		# Verify the sever root against DB root
		my $mpc			= Common::getMPC();
		my $datahash	= Common::getEncDatahash();

		($dbmpc, $dbhash) = Common::getExpressDBHashRoot();

		# Perform root and hash check only if sync files are present
		if($readysync && (($dbmpc && $dbmpc ne $mpc) || ($dbhash && $dbhash ne $datahash))) {
			if($isScheduledJob == 0 and $silentBackupFlag == 0) {
				Common::display('acc_reset_detected_need_fresh_backup');
				my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
				Common::retreat(["\n", 'unable_to_proceed_without_fresh_backup']) if(lc($choice) ne 'y');
			}

			# Delete the express DB and later we'll perform a fresh scan
			unlink($dbfile) if(-f $dbfile);

			# Delete directory from current mount path without waiting for mount path selection.
			# If mpc is present in the newly chosen mount path, that also we have to remove
			my ($mntpvalid, $mntp) = Common::getAndSetMountedPath(1);
			if($mntpvalid) {
				my $expdir	= Common::getCatfile($mntp, $AppConfig::appType . 'Local', $username, $dbmpc);
				Common::removeItems($expdir);
			}
			$expstatreset = 1;
		}
	}

	#Added to handle for schema changed for 360
	my($schemaStat, $dbPath) = Common::isExpressDBschemaChanged('localbackup');
	if($schemaStat) {
		Common::traceLog('ExpressDBschemaChanged. Renaming DB '.$dbPath);
		system("mv '$dbPath' '$dbPath'"."_bak") if(-f $dbPath);
	};

	# Commented as per Deepak's instruction: Senthil
	# my $serverAddress = Common::getServerAddress();
	# if ($serverAddress == 0){
		# exitCleanup($AppConfig::errStr);
	# }

    Common::createJobSetExclDBRevRequest('all', 1) if(!$isBackupSetEmpty);  #Added for Snigdha_2.3_11_5 : Senthil & Sabin

	# Remove the backedup items from the mounted path if required
	# if($expstatreset && $dbmpc) {
		# my $lcdir = Common::getCatfile($localUserPath, $dbmpc);
		# Common::removeItems($lcdir);
	# }

	#Start creating required file/folder
	my $errorDir       = Common::getCatfile($jobRunningDir, $AppConfig::errorDir);
	$relativeFileset   = Common::getCatfile($jobRunningDir, $AppConfig::relativeFileset);
	$noRelativeFileset = Common::getCatfile($jobRunningDir, $AppConfig::noRelativeFileset);
	$filesOnly         = Common::getCatfile($jobRunningDir, $AppConfig::filesOnly);

	Common::createDir($errorDir, 0);
	Common::createLogFiles("BACKUP",ucfirst($jobType));
	Common::createBackupTypeFile() or Common::retreat('failed_to_set_backup_type');

	# After log header creation check error if present
	# Added to handle when account related error comes during account_info verification
	exitCleanup($AppConfig::errStr) if($isScheduledJob == 0 and $AppConfig::errStr =~ /^2\-/i);

	unless ($silentBackupFlag) {
		if ($dedup eq 'off') {
			my $bl = Common::getUserConfiguration('BACKUPLOCATION');
			Common::display(["\n",'your_current_backup_location_is',"'$bl'."]);
			Common::display(['considered_backup_location_for_local',"'$backupTo'",".\n"]);
		} elsif($dedup eq 'on') {
			$backupTo = (split("#",$backupTo))[1];
			Common::display(["\n",'your_backup_location_is',"'$backupTo'",".\n"]);
		}
		Common::getCursorPos(15,Common::getStringConstant('preparing_file_list')) if(-e $pidPath);
	}

    #Verify DB & dbpath.xml file
	# exitCleanup(Common::getStringConstant('unable_to_find_mount_point')) unless($mountedPath);
	$mountedPath = $AppConfig::defaultMountPath unless($mountedPath);
	$expressLocalDir = Common::getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	$localUserPath   = Common::getCatfile($expressLocalDir, $username);
	$AppConfig::expressLocalDir = $expressLocalDir;
	$AppConfig::mailContentHead = Common::writeLogHeader($jobType);
	if (Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
		Common::setNotification('update_localbackup_progress', ((split("/", $AppConfig::outputFilePath))[-1]));
		Common::saveNotifications();
		Common::unlockCriticalUpdate("notification");
	}

    Common::display('');
    my($status, $reason) = Common::checkAndStartDBReIndex($mountedPath, 'backup');
	unless($status) {
		$AppConfig::errStr = '2-'.Common::getStringConstant('operation_could_not_be_completed_reason').Common::getStringConstant($reason);
		exitCleanup($AppConfig::errStr);
	}

	if ($dedup eq 'on') {
		my @backupLocationDir = Common::getUserBackupDirListFromMountPath($localUserPath);
		if(scalar(@backupLocationDir)>0) {
			Common::checkAndCreateDBpathXMLfile($localUserPath, \@backupLocationDir);
		}
	}

	# After log header creation check error if present
	exitCleanup($AppConfig::errStr) if($AppConfig::errStr =~ /^2\-/i);

	# We need to decide whether we need to run scan or not.
	# If user comes to backup immediately after edit backup set scan may already run.
	# We may not have to run this again.
	my $scanlock	= Common::getCDPLockFile('bkpscan');
	my $validscan	= Common::isFileLocked($scanlock)? Common::isThisExpressBackupScan() : 0;

	unless($validscan) {
		Common::traceLog(['updating_local_backupset_db']);
		# Common::display(["\n", 'updating_local_backupset_db', '.', "\n"], 1); # review comment
		my $reqfile = Common::createScanRequest($dbpath, basename($dbpath), 0, 'localbackup', 0, 1);
		Common::retreat(['unable_to_update_local_backupset_db', "\n"]) unless($reqfile);

		if($jobType eq 'manual') {
			my $scanprog	= Common::getCDPLockFile('scanprog');
			while(-f $reqfile && !-f $scanprog) {
				sleep(1);
				if(!Common::isDBWriterRunning()) {
					unlink($reqfile);
					last;
				}
			}

			displayManualScanProgress($pidPath, $reqfile);
		} elsif($jobType eq 'scheduled') {
			while(-f $reqfile) {
				sleep(1);
				if(!Common::isDBWriterRunning()) {
					unlink($reqfile);
					last;
				}
			}
		}

		# Common::display(["\n", 'local_backupset_db_updated_successfully', '.', "\n"], 1); # review comment
	} else {
		Common::traceLog(['updating_local_backupset_db_in_progress']);
		displayManualScanProgress($pidPath, undef) if($jobType eq 'manual');
	}

	# verify backed up files
	if($readysync && !$expstatreset) {
		Common::traceLog(['verifying_backup_files_in_mount_path']);

		my $reqfile = Common::createExpressBackupVerifyRequest($dbpath, $mountedPath);
		Common::retreat(['unable_to_verify_local_files_in_mount_path', '.', "\n"]) unless($reqfile);
		Common::display(["\n",'verifying_backup_files_in_mount_path', '. ', 'please_wait_title', '...', "\n"]);
		while(-f $reqfile) {
			sleep(1);
			if(!Common::isDBWriterRunning()) {
				unlink($reqfile);
				last;
			}
		}
	}

	Common::writeAsJSON($totalFileCountFile, {});
	# Common::getCursorPos(40,"") if(-e $pidPath); #Resetting cursor position
	startBackup() if(-e $pidPath and !$isBackupSetEmpty);
	exitCleanup($AppConfig::errStr);
}

#*************************************************************************************************
# Subroutine		: displayManualScanProgress
# Objective			: Displays progress of scan in manual backup
# Added By			: Sabin Cheruvattil
#*************************************************************************************************
sub displayManualScanProgress {
	my ($pidfile, $reqfile) = ($_[0], $_[1]);
	my $dp = 1;

	my $scanprog	= Common::getCDPLockFile('scanprog');
	Common::getCursorPos(2, Common::getStringConstant('scanning_files'));

	do {
		Common::displayScanProgress($scanprog, 4, 'localbackup') if(-f $scanprog);
		$dp = 0 if(!-f $pidfile || !-f $scanprog || (defined($reqfile) && !-f $reqfile));
		Common::sleepForMilliSec(50);
	} while($dp);
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
}

#****************************************************************************************************
# Subroutine		: startBackup
# Objective			: This function will fork a child process to generate backupset files and get
#						count of total files considered. Another forked process will perform main
#						backup operation of all the generated backupset files one by one.
# Added By			: Senthil Pandian
# Modified By       : Yogesh Kumar, Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub startBackup {
	Common::createLocalBackupDir(); #Creating the local backup location directories
	Common::createDBPathsXmlFile();

	my $pidPath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
	$generateFilesPid = fork();

	if(!defined $generateFilesPid) {
		Common::traceLog(['cannot_fork_child', "\n"]);
		Common::display(['cannot_fork_child', "\n"]) unless ($silentBackupFlag);
		return 0;
	}

    if($generateFilesPid == 0) {
        Common::generateBackupsetFiles();
        exit(0);
    }

	if($isScheduledJob == 0 and $silentBackupFlag == 0){
		$displayProgressBarPid = fork();

		if(!defined $displayProgressBarPid) {
			$AppConfig::errStr = Common::getStringConstant('unable_to_display_progress_bar');
			Common::traceLog($AppConfig::errStr);
			return 0;
		}

		if($displayProgressBarPid == 0) {
            displayBackupProgress();
			exit(0);
		}
	}

	my $info_file = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);
	my $retryInfo = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::retryInfo);
	my $maxNumRetryAttempts = 1000;
	my $engineLockFile = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	my $line = '';
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;

	open(my $handle, '>', $engineLockFile) or Common::traceLog("Could not open file '$engineLockFile' $!");
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

    my $writeOutputHeading = 1;
	while (1) {
		if(!-e $pidPath){
			last;
		}

		if($line eq "") {
			$line = <FD_READ>;
			$line = "" if(!$line);
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

        if($writeOutputHeading){
            my $outputHeading = Common::getStringConstant('heading_backup_output');
            $outputHeading	 .= "\n".(('-') x 78). "\n";
            # print OUTFILE $outputHeading;
            Common::fileWrite($AppConfig::outputFilePath,$outputHeading,'APPEND');
            $writeOutputHeading = 0;
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
			unless(Common::validatePrivateKeyContent()) {
				$AppConfig::errStr = Common::getStringConstant('invalid_enc_key_relogin');
				unlink($pidPath);
				return 0;
			}

			my $backupPid = fork();

			if(!defined $backupPid) {
				$AppConfig::errStr = "Cannot fork() child process :  for EVS \n";
				return BACKUP_PID_FAIL;
			}
			elsif($backupPid == 0) {
				$AppConfig::pidOperationFlag = "ChildProcess";
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

	$AppConfig::nonExistsCount		= Common::readInfoFile('FAILEDCOUNT');
	$AppConfig::noPermissionCount	= Common::readInfoFile('DENIEDCOUNT');
	$AppConfig::missingCount		= Common::readInfoFile('MISSINGCOUNT');
	$AppConfig::readySyncedFiles	= Common::readInfoFile('READYSYNC');

	waitpid($generateFilesPid,0);
	undef @AppConfig::linesStatusFile;
	if(!$totalFiles or $totalFiles !~ /\d+/ or $totalFiles == 0) {
		$totalFiles    = Common::readInfoFile('TOTALFILES');
		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			Common::traceLog("0 total files, Check DB/Cancelled during backupset generation");
		}
	}
	$AppConfig::totalFiles = $totalFiles;

	if ((-f $retryInfo && -s $retryInfo > 0) && -e $pidPath && $AppConfig::retryCount <= $maxNumRetryAttempts && $exitStatus == 0) {
		if ($AppConfig::retryCount == $maxNumRetryAttempts) {

			for(my $i=1; $i<= $AppConfig::totalEngineBackup; $i++){
				if(-e $statusFilePath."_".$i and -s _ > 0) {
					my %statusHash = Common::readStatusFile($i);
					my $index = "-1";
					$statusHash{'FAILEDFILES_LISTIDX'} = $index;
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
		print INFO "READYSYNC $AppConfig::readySyncedFiles\n";
		close INFO;
		chmod $AppConfig::filePermission, $info_file;
		sleep 5; #5 Sec
		Common::traceLog("retrycount:".$AppConfig::retryCount);
		$engineID = 1;
		Common::loadUserConfiguration(); #Reloading to handle domain connection failure case
		goto START;
	}
}

#****************************************************************************************************
# Subroutine		: removeIntermediateFiles
# Objective			: This function will remove all the intermediate files/folders
# Added By			: Senthil Pandian
#*****************************************************************************************************/
sub removeIntermediateFiles {
	# my $evsTempDirPath  = $AppConfig::jobRunningDir."/".$AppConfig::evsTempDir;
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;
	my $retryInfo       = $AppConfig::jobRunningDir."/".$AppConfig::retryInfo;
	my $failedFiles     = $AppConfig::jobRunningDir."/".$AppConfig::failedFileName;
	my $infoFile        = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;
	my $filesOnly	    = $AppConfig::jobRunningDir."/".$AppConfig::filesOnly;
	#my $incSize 		= $AppConfig::jobRunningDir."/".$AppConfig::transferredFileSize;
	my $errorDir 		= $AppConfig::jobRunningDir."/".$AppConfig::errorDir;
	my $utf8File 		= $AppConfig::jobRunningDir."/".$AppConfig::utf8File."_";
	my $relativeFileset     = $AppConfig::jobRunningDir."/".$AppConfig::relativeFileset;
	my $noRelativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::noRelativeFileset;
	my $progressDetailsFilePath = $AppConfig::jobRunningDir."/".$AppConfig::progressDetailsFilePath."_";
	my $engineLockFile  = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	# my $summaryFilePath = $AppConfig::jobRunningDir.'/'.$AppConfig::fileSummaryFile; #Should not delete this file after backu
	my $errorFilePath   = $AppConfig::jobRunningDir."/".$AppConfig::exitErrorFile;

	#my $totalFileCountFile  = $AppConfig::jobRunningDir."/".$AppConfig::totalFileCountFile;
	my $idevsOutputFile	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsOutputFile;
	my $idevsErrorFile 	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsErrorFile;
	my $backupUTFpath   	= $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
	my $operationsFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::operationsfile;
	my $doBackupOperationErrorFile = $AppConfig::jobRunningDir."/doBackuperror.txt_";
	my $minimalErrorRetry = $AppConfig::jobRunningDir."/".$AppConfig::minimalErrorRetry;

	Common::removeItems([$relativeFileset.'*', $noRelativeFileset.'*', $filesOnly.'*', $infoFile, $retryInfo, $errorDir, $statusFilePath.'*', $failedFiles.'*', $utf8File.'*', $progressDetailsFilePath.'*', $engineLockFile, $errorFilePath]);
	Common::removeItems([$idevsErrorFile.'*', $idevsOutputFile.'*', $backupUTFpath.'*', $operationsFilePath.'*', $doBackupOperationErrorFile.'*', $minimalErrorRetry]);

	return 0;
}

#****************************************************************************************************
# Subroutine		: exitCleanup.
# Objective			: This function will execute the major functions required at the time of exit
# Added By			: Deepak Chaurasia
# Modified By		: Dhritikana, Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub exitCleanup {
    return unless(-d $AppConfig::jobRunningDir); #Added for Snigdha_2.3_10_17 : Senthil
    $AppConfig::pidOperationFlag = 'ExitCleanup';

	my $locerror			= $_[0];
	my $pidPath 			= $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
	my $retryInfo       	= $AppConfig::jobRunningDir."/".$AppConfig::retryInfo;
	my $fileForSize		    = $AppConfig::jobRunningDir."/".$AppConfig::fileForSize;
	my $trfSizeAndCountFile = $AppConfig::jobRunningDir."/".$AppConfig::trfSizeAndCountFile;
	# my $evsTempDirPath  	= $AppConfig::jobRunningDir."/".$AppConfig::evsTempDir;
	my $errorDir 		    = $AppConfig::jobRunningDir."/".$AppConfig::errorDir;
	my $fileSummaryFile     = $AppConfig::jobRunningDir."/".$AppConfig::fileSummaryFile;
	my $pwdPath = Common::getIDPWDFile();
	my $engineLockFile = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;

	my ($successFiles, $syncedFiles, $failedFilesCount, $transferredFileSize, $exit_flag) = (0) x 5;
	if($silentBackupFlag == 0){
		system('stty', 'echo');
		system("tput sgr0");
	}

Common::traceLog("AppConfig::errStr1:".$AppConfig::errStr); #Needs to be removed later

	unless($isBackupSetEmpty){
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','TOTAL_TRANSFERRED_SIZE','EXIT_FLAG_INDEX');
		($successFiles, $syncedFiles, $failedFilesCount,$transferredFileSize, $exit_flag) = Common::getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
		chomp($exit_flag);
Common::traceLog("exit_flag:$exit_flag"); #Needs to be removed later
		if($AppConfig::errStr eq "" and -e $AppConfig::errorFilePath) {
			open ERR, "<$AppConfig::errorFilePath" or Common::traceLog(['failed_to_open_file', "errorFilePath in exitCleanup: $AppConfig::errorFilePath, Reason: $!"]);
			$AppConfig::errStr .= <ERR>;
			close(ERR);
			chomp($AppConfig::errStr);
Common::traceLog("AppConfig::errStr2:".$AppConfig::errStr); #Needs to be removed later
		}

		if(!-e $pidPath or $exit_flag) {
Common::traceLog("pid Not found"); #Needs to be removed later
        
			$AppConfig::cancelFlag = 1;

			# In childprocess, if we exit due to some exit scenario, then this exit_flag will be true with error msg
			my @exit = split("-", $exit_flag, 2);
			Common::traceLog("exit_flag = $exit_flag");

			if($AppConfig::errStr =~ /^2\-/i) {
				$exit[0] = 2;
				$AppConfig::errStr =~ s/^2\-//g;
				$exit[1] = $AppConfig::errStr;
			}
			
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
				if ($exit[1] and $exit[1] ne '') {
					$AppConfig::errStr = $exit[1];
					# Common::checkAndUpdateAccStatError(Common::getUsername(), $AppConfig::errStr);
					# Below section has been added to provide user friendly message and clear
					# instruction in case of password mismatch or encryption verification failed.
					# In this case we are removing the IDPWD file.So that user can login and recreate these files with valid credential.
					if ($AppConfig::errStr =~ /password mismatch|encryption verification failed/i) {
						Common::createBackupStatRenewalByJob('backup') if(Common::getUserConfiguration('DEDUP') ne 'on');
						my $tokenMessage = Common::getStringConstant('please_login_account_using_login_and_try');
						#$tokenMessage =~ s/___login___/$AppConfig::idriveScripts{'login'}/eg;
						$AppConfig::errStr = $AppConfig::errStr.' '.$tokenMessage."\n" unless($AppConfig::errStr =~ /try again/);
						unlink($pwdPath);
						if ($jobType eq "scheduled") {
							$pwdPath =~ s/_SCH$//g;
							unlink($pwdPath);
						}
					}
					elsif ($AppConfig::errStr =~ /failed to get the device information|Invalid device id/i) {
						$AppConfig::errStr = ($exit[0] eq 2? '' : $AppConfig::errStr . ' ') . Common::getStringConstant('invalid_bkp_location_config_again')."\n";
					} else {
						# $AppConfig::errStr = Common::checkErrorAndLogout($AppConfig::errStr, undef, 1);
                        $AppConfig::errStr = Common::checkErrorAndReturnErrorMessage($AppConfig::errStr);
					}
				}
			}
		}
	}
	unlink($pidPath);
	waitpid($displayProgressBarPid,0) if($displayProgressBarPid);
	wait();
Common::traceLog("AppConfig::errStr3:".$AppConfig::errStr); #Needs to be removed later

	Common::writeOperationSummary($AppConfig::evsOperations{'LocalBackupOp'}, $jobType);

    # Commented for Snigdha_2.3_05_2: Senthil
	# if($locerror && $locerror =~ /^2\-/) {
		# $AppConfig::mailContent = $AppConfig::errStr;
	# }

	my $subjectLine = Common::getEmailSubLine($jobType, 'Local Backup');

	unlink($fileForSize);
	unlink($trfSizeAndCountFile);

	Common::restoreBackupsetFileConfiguration();
	# if(-d $evsTempDirPath) {
		# Common::rmtree($evsTempDirPath);
	# }
	if(-d $errorDir and $errorDir ne '/') {
		system(Common::updateLocaleCmd("rm -rf '$errorDir'"));
	}

	if ((-f $AppConfig::outputFilePath) and (!-z $AppConfig::outputFilePath)) {
		my $finalOutFile = $AppConfig::outputFilePath;
		$finalOutFile =~ s/_Running_/_$AppConfig::opStatus\_/;
		Common::move($AppConfig::outputFilePath, $finalOutFile);
		Common::updateLastBackupStatus($AppConfig::jobType, $AppConfig::opStatus, basename($finalOutFile));

		if (Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
			Common::setNotification('update_localbackup_progress', ((split("/", $finalOutFile))[-1]));
			Common::setNotification('get_localbackupset_content');
			Common::setNotification('get_logs') and Common::saveNotifications();
			Common::unlockCriticalUpdate("notification");
		}

		$AppConfig::outputFilePath = $finalOutFile;
		$AppConfig::finalSummary .= Common::getStringConstant('for_more_details_refer_the_log').qq(\n);
		# Concat log file path with job summary. To access both at once while displaying the summary and log file location.
		$AppConfig::finalSummary .= $AppConfig::opStatus."\n".$AppConfig::errStr;
		Common::fileWrite($fileSummaryFile,$AppConfig::finalSummary);

		if ($silentBackupFlag == 0){
			#It is a generic function used to write content to file.
			# Common::displayProgressBar($AppConfig::progressDetailsFilePath,undef,undef) unless ($isBackupSetEmpty);
			Common::displayFinalSummary(Common::getStringConstant('localbackup_job'),$fileSummaryFile);
			#Above function display summary on stdout once backup job has completed.
		}

		Common::saveLog($finalOutFile, 0);
	}

	unless ($isBackupSetEmpty) {
		Common::sendMail({
				'serviceType' => $jobType,
				'jobType' => 'Local Backup',
                'jobName' => 'local_backupset',
				'subject' => $subjectLine,
				'jobStatus' => lc($AppConfig::opStatus)
			});
	} else {
		Common::sendMail({
				'serviceType' => $jobType,
				'jobType' => 'Local Backup',
                'jobName' => 'local_backupset',
				'subject' => $subjectLine,
				'jobStatus' => lc($AppConfig::opStatus),
				'errorMsg' => 'NOBACKUPDATA'
			});
	}

	Common::removeItems($pidPath.'*');
	removeIntermediateFiles();
	unlink($engineLockFile);

    $AppConfig::errStr = Common::checkErrorAndLogout($AppConfig::errStr, undef, 1);
	if($AppConfig::errStr) {
		Common::traceLog($AppConfig::errStr);
		if($AppConfig::errStr =~ /failed to get the device information|invalid device id|device is deleted\/removed|encryption verification failed/i) {
			Common::doAccountResetLogout(1);
		}
	}

	# need to update the crontab with default values.
	if(defined(${ARGV[0]})  and ${ARGV[0]} eq 'immediate') {
		Common::updateCronTabToDefaultVal("localbackup");
	}

	Common::traceLog(['backup_completed']);
	exit 0;
}

###################################################
#The signal handler invoked when SIGINT or SIGTERM#
#signal is received by the script                 #
###################################################
sub processTerm {
	my $pidPath  = $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
	system("stty $AppConfig::stty") if($AppConfig::stty);	# restore 'cooked' mode
	unlink($pidPath) if(-f $pidPath);
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
	cancelBackupSubRoutine();
	exit(0);
}

#*******************************************************************************************************
# Subroutine		: waitForEnginesToFinish
# Objective			: Cancel the execution of backup script
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil, Senthil Pandian
#********************************************************************************************************/
sub cancelBackupSubRoutine {
	my $backupUTFpath = $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
	my $info_file     = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;

	if($AppConfig::pidOperationFlag eq "EVS_process") {
		$backupUTFpath =~ s/\[/\\[/;
		$backupUTFpath =~ s/{/[{]/;
		my $psOption = Common::getPSoption();
		my $evsCmd   = "ps $psOption | grep \"$AppConfig::evsBinaryName\" | grep \'$backupUTFpath\'";
		$evsCmd = Common::updateLocaleCmd($evsCmd);
		my $evsRunning  = `$evsCmd`;
		my @evsRunningArr = split("\n", $evsRunning);
		my $arrayData = ($Common::machineInfo =~ /freebsd/i)? 1 : 3;

		foreach(@evsRunningArr) {
			next if($_ =~ /$evsCmd|grep/);

			my $pid = (split(/[\s\t]+/, $_))[$arrayData];
			my $scriptTerm = system(Common::updateLocaleCmd("kill -9 $pid 2>/dev/null"));
			Common::traceLog(['failed_to_kil', ' Backup']) if(defined($scriptTerm) && $scriptTerm != 0 && $scriptTerm ne '');
		}

		return;
	}

	waitpid($AppConfig::pidOutputProcess, 0) if($AppConfig::pidOutputProcess && $AppConfig::pidOperationFlag eq "main");
	Common::waitForChildProcess();

    #Added to prevent multiple exit cleanup calls due to fork processes
    exit(0) if($AppConfig::pidOperationFlag =~ /DisplayProgress|ChildProcess|ExitCleanup/);

	if($AppConfig::pidOperationFlag eq "GenerateFile") {
		open FD_WRITE, ">>", $info_file or Common::display(['failed_to_open_file'," info_file in cancelSubRoutine: $info_file to write, Reason:$!"]); # die handle?
		autoflush FD_WRITE;
		#print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "TOTALFILES $AppConfig::totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $AppConfig::nonExistsCount\n";
		print FD_WRITE "DENIEDCOUNT $AppConfig::noPermissionCount\n";
		print FD_WRITE "MISSINGCOUNT $AppConfig::missingCount\n";
		close FD_WRITE;
		# close NEWFILE;
		$AppConfig::pidOperationFlag ='';
		exit(0);
	}

	if($AppConfig::pidOperationFlag eq "main") {
		waitpid($generateFilesPid, WNOHANG) if($generateFilesPid);
		if(-e $info_file and (!defined($totalFiles) or $totalFiles == 0 or $totalFiles !~ /\d+/)) {
			my $fileCountCmd = "cat '$info_file' | grep -m1 \"^TOTALFILES\"";
			$totalFiles = `$fileCountCmd`;
			$totalFiles =~ s/TOTALFILES//;
			chomp($totalFiles) if($totalFiles ne '');
		}

		if(!$totalFiles or $totalFiles !~ /\d+/) {
			Common::traceLog("Unable to get total files count");
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
	my $pidPath       = $AppConfig::jobRunningDir.$AppConfig::pidFile;
	my $backupUTFpath = $AppConfig::jobRunningDir.$AppConfig::utf8File."_".$operationEngineId;
	my $evsOutputFile = $AppConfig::jobRunningDir.$AppConfig::evsOutputFile.'_'.$operationEngineId;
	my $evsErrorFile  = $AppConfig::jobRunningDir.$AppConfig::evsErrorFile.'_'.$operationEngineId;
	my $isDedup  	  = Common::getUserConfiguration('DEDUP');
	# my $bwPath     	  = Common::getUserProfilePath()."/bw.txt";
	my $bwPath     	  = $AppConfig::jobRunningDir."/bw.txt";
	#my $defLocal	  = (-e Common::getIDPVTFile())?0:1;
	my $defLocal	  = ($AppConfig::encType eq 'PRIVATE')?0:1;
	my $backupHost	  = Common::getUserConfiguration('BACKUPLOCATION');
	if ($isDedup eq 'off' and $AppConfig::jobType eq "LocalBackup") {
		my @backupTo = split("/",$backupHost);
		$backupHost	 = (substr($backupHost,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
		$backupHost	.= '/' if(substr($backupHost,-1,1) ne '/'); #Adding end slash if not
	}
	my $userName 	      = Common::getUsername();
	my $backupLocationDir = Common::getLocalBackupDir();
	my @parameter_list = split /\' \'/,$parameters,3;
	my $engineLockFile = $AppConfig::jobRunningDir."/".AppConfig::ENGINE_LOCKE_FILE;
	# $backupUTFpath = $backupUTFpath;

	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	if (!flock($startPidFileLock, LOCK_SH)){
		Common::traceLog("Failed to lock engine file");
		return 0;
	}

	Common::fileWrite($pidPath.'_evs_'.$operationEngineId, 1); #Added for Harish_2.19_7_7, Harish_2.19_6_7
	open(my $engineFp, ">>", $pidPath.'_'.$operationEngineId) or return 0;
	if (!flock($engineFp, LOCK_EX)){
		Common::display('failed_to_lock',1);
		return 0;
	}

	Common::createUTF8File(['LOCALBACKUP',$backupUTFpath],
				$parameter_list[2],
				$bwPath,
				$defLocal,
				$AppConfig::jobRunningDir,
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
					Common::traceLog(['failed_to_open_file', "errorFilePath in doBackupOperation:" . $AppConfig::errorFilePath . ", Reason:$!"]);
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
        sleep(1);
        unlink($pidPath.'_evs_'.$operationEngineId);
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
	{
		my $cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\' \'$operationEngineId\' \'$retry_failedfiles_index\'";
		$cmd = Common::updateLocaleCmd($cmd);
		system($cmd);
	}

	waitpid($backupPid, 0);
	Common::removeItems($pidPath.'_evs_'.$operationEngineId);
	Common::waitForChildProcess($pidPath.'_proc_'.$operationEngineId);
	unlink($pidPath.'_'.$operationEngineId);

	return 0 unless(Common::updateServerAddr());

	unlink($parameter_list[2]);
	unlink($evsOutputFile.'_'.$operationEngineId);
	flock($startPidFileLock, LOCK_UN);
	flock($engineFp, LOCK_UN);

	return 0 if (-e $AppConfig::errorFilePath && -s $AppConfig::errorFilePath);
	return 1; #Success
}

#*****************************************************************************************************
# Subroutine	: displayBackupProgress
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Reads the keyboard input and processes the input w.r.t backup progress detail
# Added By		: Senthil Pandian
#*****************************************************************************************************
sub displayBackupProgress {
	my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::progressDetailsFilePath);
	my $pidPath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);

    $AppConfig::pidOperationFlag = "DisplayProgress";
    my $keyPressEvent = Common::catchPressedKey();
    my $playPause  = $AppConfig::running;
    my ($redrawForLess, $drawForPlayPause) = (0) x 2;
    my $bwPath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::bwFile);
    my $temp   = $AppConfig::totalEngineBackup;
    my $moreOrLess = $AppConfig::less;
    $moreOrLess    = $AppConfig::more if(Common::checkScreeSize());

    while(-f $pidPath) {
        ($redrawForLess, $drawForPlayPause) = (0) x 2;
        # Checking & changing status if play/pause key pressed in status retrieval script
        my $bw= Common::getFileContents($bwPath);
        if($bw ne '') {
            if(($bw < 0) and ($playPause eq $AppConfig::running)) {
                $drawForPlayPause = 1;
                $playPause = $AppConfig::paused;
            } elsif(($bw >= 0) and ($playPause eq $AppConfig::paused)) {
                $drawForPlayPause = 1;
                $playPause = $AppConfig::running;
            }
        }

        if($keyPressEvent->(1)) {
            if(($AppConfig::pressedKeyValue eq 'p') and ($playPause eq $AppConfig::running)) {
                $drawForPlayPause = 1;
                $playPause = $AppConfig::paused;
                Common::pauseOrResumeEVSOp($AppConfig::jobRunningDir,'p');
            } elsif(($AppConfig::pressedKeyValue eq 'r') and ($playPause eq $AppConfig::paused)) {
                $drawForPlayPause = 1;
                $playPause = $AppConfig::running;
                Common::pauseOrResumeEVSOp($AppConfig::jobRunningDir,'r');
            }
    
            if(($moreOrLess eq $AppConfig::more) and ($AppConfig::pressedKeyValue eq '-')) {
                $moreOrLess  = $AppConfig::less;
                $redrawForLess = 1;
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
            } elsif(($moreOrLess eq $AppConfig::less) and ($AppConfig::pressedKeyValue eq '+')) {
                $moreOrLess = $AppConfig::more if(Common::checkScreeSize());
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
            }					
        }
        Common::displayProgressBar($progressDetailsFilePath,undef,undef,$moreOrLess,$redrawForLess)  if($playPause ne 'paused' || $drawForPlayPause);
        Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);# Sleep for 100/500 milliseconds				
    }
    $keyPressEvent->(0);
    $AppConfig::pressedKeyValue = '';
    # Common::displayProgressBar($progressDetailsFilePath,Common::getTotalSize($AppConfig::jobRunningDir."/".$AppConfig::fileForSize),$playPause);
    Common::displayProgressBar($progressDetailsFilePath,undef,undef,$moreOrLess,$redrawForLess);
}