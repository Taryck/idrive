#!/usr/bin/env perl

#######################################################################
#Script Name : Backup_Script.pl
#######################################################################
system('clear');
use lib map{if (__FILE__ =~ /\//) {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";}}else {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {"./$_";}}} qw(Idrivelib/lib .);

use FileHandle;
use POSIX;
use POSIX ":sys_wait_h";
use File::Basename;
use Fcntl qw(:flock SEEK_END);
use AppConfig;
use Common;
Common::waitForUpdate();
Common::initiateMigrate();

Common::verifyVersionConfig();

require 'Header.pl';

require Constants;
use constant false => 0;
use constant true => 1;
use constant CHILD_PROCESS_STARTED => 1;
use constant CHILD_PROCESS_COMPLETED => 2;
use constant FILE_COUNT_THREAD_STARTED => 1;
use constant FILE_COUNT_THREAD_COMPLETED => 2;
use constant LIMIT => 2*1024;
use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";

# $appTypeSupport should be ibackup for ibackup and idrive for idrive#
# $appType should be IBackup for ibackup and IDrive for idrive        #
$jobType = "Backup";
my $prevTime = time();
my ($generateFilesPid, $displayProgressBarPid, $errorFilePresent) = (undef, undef, false);
my ($cancelFlag, $backupUtfFile, $maxNumRetryAttempts, $totalSize, $BackupsetFileTmp, $regexStr, $parStr) = (0, '', 1000, 0, '', '', '');
my ($filesOnlyCount, $prevFailedCount, $noRelIndex, $retrycount, $exitStatus) = (0, 0, 0, 0, 0);
my ($pidOperationFlag, $relativeFileset, $filesOnly, $noRelativeFileset) = ("main", "BackupsetFile_Rel", "BackupsetFile_filesOnly", "BackupsetFile_NoRel");
my ($retry_failedfiles_index, $engineID, $minRetryAttempts) = (0, 1, 10);
my @BackupForkchilds;
my $current_source;

# Index number for arrayParametersStatusFile
use constant COUNT_FILES_INDEX => 0;
use constant SYNC_COUNT_FILES_INDEX => 1;
use constant ERROR_COUNT_FILES => 2;
use constant FAILEDFILES_LISTIDX => 3;
use constant EXIT_FLAG_INDEX => 4;

use constant BACKUP_SUCCESS => 1;
use constant BACKUP_PID_FAIL => 2;
use constant OUTPUT_PID_FAIL => 3;
use constant PID_NOT_EXIST => 4;
use constant FILE_MAX_COUNT => 1000;

Common::traceLog(['backup_started']) if(!$iscdp);

my @commandArgs = qw(--silent SCHEDULED dashboard immediate CDP);
if ($#ARGV >= 0) {
	unless(validateCommandArgs(\@ARGV,\@commandArgs)) {
		print Constants->CONST->{'InvalidCmdArg'} . "\n";
		Common::traceLog(['backup_aborted_invalid_cmd']);
		cancelProcess();
	}
}

# Status File Parameters
my @statusFileArray = 	( "COUNT_FILES_INDEX",
							"SYNC_COUNT_FILES_INDEX",
							"ERROR_COUNT_FILES",
							"FAILEDFILES_LISTIDX",
							"EXIT_FLAG"
						);

##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script during backup #
##############################################
$SIG{INT}	= \&process_term;
$SIG{KILL}	= \&process_term;
$SIG{ABRT}	= \&process_term;
$SIG{PWR}	= \&process_term if(exists $SIG{'PWR'});
$SIG{QUIT}	= \&process_term;
$SIG{TERM}	= \&process_term;
$SIG{TSTP}	= \&process_term;
$SIG{USR1}	= \&process_term;
$SIG{WINCH} = \&Common::changeSizeVal;

#Assigning Perl path
my $perlPathCmd = 'which perl';
my $perlPath = `$perlPathCmd`;
chomp($perlPath);
$perlPath = '/usr/local/bin/perl' if($perlPath eq '');

###################################################
#The signal handler invoked when SIGINT or SIGTERM#
#signal is received by the script                 #
###################################################
sub process_term {
	Common::traceLog(['backup_terminated_sig']);
	system("stty $AppConfig::stty") if($AppConfig::stty);	# restore 'cooked' mode
	unlink($pidPath);
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
	cancelSubRoutine();
	exit(0);
}

$confFilePath = Common::getUserConfigurationFile();

loadUserData();

my $BackupsetFile = $backupsetFilePath;
chmod $filePermission, $BackupsetFile;
# Trace Log Entry #
my $curFile = basename(__FILE__);

#Flag to silently do backup operation.
my $silentBackupFlag = 0;
if (${ARGV[0]} eq '--silent' or ${ARGV[0]} eq 'dashboard' or ${ARGV[0]} eq 'immediate' or ${ARGV[0]} eq 'SCHEDULED') {
	$AppConfig::callerEnv = 'BACKGROUND';
	$silentBackupFlag = 1;
}

Common::checkAccountStatus($silentBackupFlag? 0 : 1);

headerDisplay($0) if ($silentBackupFlag == 0 and $ARGV[0] ne 'SCHEDULED' && !$iscdp);

#Verifying if Backup scheduled or manual job
my $isScheduledJob = 0;
if((${ARGV[0]} eq "SCHEDULED") or (${ARGV[0]} eq "immediate") || $iscdp) {
	$pwdPath = $pwdPath . "_SCH";
	$pvtPath = $pvtPath . "_SCH";
	$isScheduledJob = 1;
	$taskType = "Scheduled";
	$relative = 1 unless(backupTypeCheck());
} else {
	$taskType = "Manual";
	if(!defined(${ARGV[0]}) or ${ARGV[0]} ne 'dashboard'){
		if(getAccountConfStatus($confFilePath)){
			Common::sendFailureNotice($userName,'update_backup_progress',$taskType) if(!$iscdp);
			exit(0);
		}
		else{
			if(getLoginStatus($pwdPath)){
				Common::sendFailureNotice($userName,'update_backup_progress',$taskType) if(!$iscdp);
				exit(0);
			}
		}
	}

	backupTypeCheck();
}

if(!Common::hasSQLitePreReq() || !Common::hasBasePreReq()) {
	$AppConfig::displayHeader = 0 if(${ARGV[0]} eq '--silent');
	Common::sendFailureNotice($userName, 'update_backup_progress', $taskType) if(!$iscdp);

	if(defined($Sqlite::dberror) and $Sqlite::dberror =~ /disk is full/ig) {
		Common::retreat('');
	} else {
		Common::retreat(['basic_prereq_not_met_run_acc_settings']);
	}
}

if(${ARGV[0]} eq '--silent') {
	$AppConfig::displayHeader = 0;
	Common::isLoggedin() or Common::retreat(["\n", 'login_&_try_again']);
}

unless(checkIfEvsWorking($dedup)) {
	print Constants->CONST->{'EvsProblem'} . "\n" if($taskType eq "Manual");
	Common::traceLog("Invalid EVS binary found!");
	Common::sendFailureNotice($userName, 'update_backup_progress', $taskType) if(!$iscdp);
	exit 0;
}

#Getting working dir path and loading path to all other files
$jobRunningDir = $iscdp? Common::getJobsPath('cdp', 'path') : Common::getJobsPath('backup', 'path');
$jobRunningDir =~ s/\/$//;
$AppConfig::jobRunningDir = $jobRunningDir; # Added by Senthil on Nov 26, 2018
$AppConfig::jobType = ($iscdp)?$AppConfig::cdp:$AppConfig::backup;

unless(-d $jobRunningDir) {
	mkpath($jobRunningDir);
	chmod $filePermission, $jobRunningDir;
}

exit 1 unless(checkEvsStatus(Constants->CONST->{'BackupOp'}));

my $cutOffReached = checkArchiveStatus();
#Checking if another job is already in progress
$pidPath = "$jobRunningDir/pid.txt";
if (!pidAliveCheck($pidPath)) {
	$pidMsg = "$AppConfig::jobType job is already in progress. Please try again later.\n";
	print $pidMsg if($taskType eq "Manual");
	Common::traceLog($pidMsg);
	exit 1;
}

#Loading global variables
$evsTempDirPath			= "$jobRunningDir/evs_temp";
$evsTempDir				= $evsTempDirPath;
$statusFilePath			= "$jobRunningDir/STATUS_FILE";
$retryinfo				= "$jobRunningDir/" . $retryinfo;
my $failedfiles			= $jobRunningDir . "/" . $failedFileName;
my $info_file			= $jobRunningDir . "/info_file";
$idevsOutputFile		= "$jobRunningDir/output.txt";
$idevsErrorFile			= "$jobRunningDir/error.txt";
my $fileForSize			= "$jobRunningDir/TotalSizeFile";
my $totalFileCountFile	= "$jobRunningDir/totalFileCountFile";
$relativeFileset		= $jobRunningDir . "/" . $relativeFileset;
$noRelativeFileset		= $jobRunningDir . "/" . $noRelativeFileset;
$filesOnly				= $jobRunningDir . "/" . $filesOnly;
my $trfSizeAndCountFile	= "$jobRunningDir/trfSizeAndCount.txt";
my $utf8Files			= $jobRunningDir . "/utf8.txt_";
$errorDir				= $jobRunningDir . "/ERROR";
my $engineLockFile		= $jobRunningDir . '/' . ENGINE_LOCKE_FILE;
my $progressDetailsFile = $jobRunningDir . "/PROGRESS_DETAILS";
my $jobCancelFile		= $jobRunningDir . '/cancel.txt';
my $summaryFilePath		= "$jobRunningDir/" . Constants->CONST->{'fileDisplaySummary'};
my $minimalErrorRetry	= $jobRunningDir.'/errorretry.min';
my $progexitfile		= Common::getCatfile($jobRunningDir, 'progress.exit');
my $schcancelfile		= Common::getCatfile($jobRunningDir, $AppConfig::schtermf);

#Added for IDrive360 to handle when backup started from Dashboard UI
#Delaying current job when previous job's cleanup process not completed. 
my $lockRetry = 0;
while(-f $engineLockFile) {
Common::traceLog("engineLockFile lockRetry:$lockRetry");
	sleep(1);
	last if($lockRetry == 60);
	$lockRetry++
}

#Renaming the log file if backup process terminated improperly
Common::checkAndRenameFileWithStatus($jobRunningDir, lc($jobType));

# pre cleanup for all intermediate files and folders.
Common::removeItems([$totalFileCountFile, $relativeFileset.'*', $noRelativeFileset.'*', $filesOnly.'*', $info_file, $retryinfo, $errorDir, $statusFilePath.'*', $excludeDirPath, $failedfiles.'*', $progressDetailsFile.'*', $jobCancelFile, $summaryFilePath, $minimalErrorRetry, $schcancelfile]);

#Start creating required file/folder
unless(-d $errorDir) {
	mkdir($errorDir);
	chmod $filePermission, $errorDir;
}

my $maximumAttemptMessage = '';
# Commented as per Deepak's instruction: Senthil
# my $serverAddress = verifyAndLoadServerAddr();
# if ($serverAddress == 0){
	# exit_cleanup($errStr);
# }

Common::copyBWFile($iscdp? $AppConfig::cdp : 'backup');
my $isEmpty = Common::checkPreReq($BackupsetFile, lc($jobType), $jobType, 'NOBACKUPDATA');
$errStr = $AppConfig::errStr; #Added for Harish_2.25_01_1

my $dbpath		= Common::getJobsPath('backup', 'path');
my $dbfile		= Common::getCatfile($dbpath, $AppConfig::dbname);
Common::createDBCleanupReq($dbpath) if($isEmpty and -f $dbfile and Common::isDBWriterRunning());

if($isEmpty and $isScheduledJob == 0 and $silentBackupFlag == 0) {
	unlink($pidPath);
	if(Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
		Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'no_files_to_backup'}) and Common::saveNotifications();
		Common::unlockCriticalUpdate("notification");
	}

	Common::retreat(["\n",$AppConfig::errStr]);
}
elsif (not $isEmpty and Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
	if(Common::getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'no_files_to_backup'}) {
		Common::setNotification('alert_status_update', 0) and Common::saveNotifications();
	}

	Common::unlockCriticalUpdate("notification");
}

# check if there is any entry to be backed up if its CDP
if($iscdp) {
	unless(-f $dbfile) {
		Common::traceLog('No CDP DB Found');
		exit(0);
	}

	Common::restartAllCDPServices() if(Common::checkBackupsetIntegrity($dbpath, $taskType, $pidPath, $iscdp));

	my ($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 1);
	exit(0) unless($dbfstate);

	Sqlite::initiateDBoperation();
	my $itemstat = Sqlite::hasItemsForCDP();
	Sqlite::closeDB();

	unless($itemstat) {
		Common::traceLog('No Items Found For CDP', undef, undef, 1);
		exit(0);
	}
}

createLogFiles("BACKUP");
createBackupTypeFile();

if ((not $iscdp) and Common::loadAppPath() and Common::loadServicePath() and Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
	Common::setNotification('update_backup_progress', ((split("/", $outputFilePath))[-1]));
	Common::saveNotifications();
	Common::unlockCriticalUpdate("notification");
}

my $scanned = 0;
unless($iscdp) {
	my $rescan = 0;
	my ($dbfstate, $scanfile);

	if(!Common::isCDPServicesRunning()) {
		Common::restartAllCDPServices();
		$rescan = 1;
	}

	$rescan = 1 if(!Common::canKernelSupportInotify() or !Common::isCDPClientServerRunning());

	my $scanlock	= Common::getCDPLockFile('bkpscan');
	my $rescanlock	= Common::getCDPLockFile('rescan');
	my $isrescan	= Common::isFileLocked($rescanlock);
	my $validscan	= Common::isFileLocked($scanlock)? Common::isThisOnlineBackupScan() : 0;

	if(!$isrescan && !$validscan) {
		my $reqfile;

		if(-f $dbfile) {
			# if db file is present, check DB corruption | for corrupted DB, sqlite will place a scan request
			($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 1);
			if($dbfstate) {
				Sqlite::closeDB();
			} else {
				$rescan = 1;
			}
		} else {
			Common::display(['unable_to_find_backupset_db', '. ', 'creating_backupset_db', '.'], 1);

			$reqfile = Common::createScanRequest($dbpath, basename($dbpath), 0, 'backup', 0, 1);
			Common::retreat(['unable_to_update_backupset_db']) unless($reqfile);

			# created scan request may not have considered. Have this in a while
			while(-f $reqfile) {
				if(!Common::isDBWriterRunning()) {
					unlink($reqfile);
					last;
				}

				sleep(2) unless(Common::displayManualScanProgress($reqfile, $taskType, $pidPath));
			}

			Common::display(['backupset_db_created_successfully', '.', "\n"], 1);

			$rescan		= 0;
			$scanned	= 1;
		}

		if($rescan) {
			Common::display(['updating_backupset_db', '. ', 'please_wait', '...'], 1);
			
			if($scanfile) {
				$reqfile = $scanfile;
			} else {
				$reqfile = Common::createScanRequest($dbpath, basename($dbpath), 0, 'backup', 0, 1);
			}

			Common::retreat(['unable_to_update_backupset_db']) unless($reqfile);

			while(-f $reqfile) {
				if(!Common::isDBWriterRunning()) {
					unlink($reqfile);
					last;
				}

				sleep(2) unless(Common::displayManualScanProgress($reqfile, $taskType, $pidPath));
			}

			Common::display(['backupset_db_updated_successfully', '.', "\n"], 1);
			$scanned	= 1;
		}
	}

	# handle scanning for non manual jobs
	if($taskType ne "Manual") {
		while(1) {
			$isrescan	= Common::isFileLocked($rescanlock);
			$validscan	= Common::isFileLocked($scanlock)? Common::isThisOnlineBackupScan() : 0;

			if($isrescan || $validscan || ($scanfile && -f $scanfile)) {
				last if(!Common::isDBWriterRunning());
				sleep(1);
				$scanned	= 1;
			} else {
				last;
			}
		}
	} else {
		# If all are fine and scan is running
		Common::displayManualScanProgress(undef, $taskType, $pidPath);
	}
} else {
	my $scanlock	= Common::getCDPLockFile('bkpscan');
	my $rescanlock	= Common::getCDPLockFile('rescan');
	my ($isrescan, $validscan) = (0, 0);

	while(1) {
		$isrescan	= Common::isFileLocked($rescanlock);
		$validscan	= Common::isFileLocked($scanlock)? Common::isThisOnlineBackupScan() : 0;

		if($isrescan or $validscan) {
			last if(!Common::isDBWriterRunning());
			sleep(1);
		} else {
			last;
		}
	}
}

# Check backupset DB integrity
if(!$scanned && !$iscdp) {
	Common::restartAllCDPServices() if(Common::checkBackupsetIntegrity($dbpath, $taskType, $pidPath, $iscdp));
}

if ($isScheduledJob == 0 and $silentBackupFlag == 0 and -f $pidPath) {
	if ($dedup eq 'off') {
		emptyLocationsQueries();
	} elsif($dedup eq 'on') {
		print qq{Your Backup Location is "} . $backupHost . qq{". $lineFeed};
	}
}

$location = (($dedup eq 'on') and $backupHost =~ /#/)? (split('#', $backupHost))[1] : $backupHost;
Common::getCursorPos(40,Common::getStringConstant('preparing_file_list')) if ($isScheduledJob == 0 and $silentBackupFlag == 0 and !$isEmpty and -e $pidPath);
#$mail_content_head = writeLogHeader($isScheduledJob);
$AppConfig::mailContentHead = writeLogHeader($isScheduledJob);

# handle web activity
unless($iscdp) {
	my $webstat = 0;
	if($dedup eq 'on') {
		$webstat = Common::processDedupUpdateDelete(!$silentBackupFlag);

		if($isScheduledJob && $webstat =~ /^error\-/) {
			if($webstat =~ /failed to get the device information|invalid device id|encryption verification failed|device is deleted\/removed/i) {
				unlink($pidPath);
				$webstat =~ s/^error\-//;
				$errStr = '2-' . $webstat;
				exit_cleanup($errStr);
			}
		} elsif($webstat =~ /^error\-/) {
			if($webstat =~ /failed to get the device information|invalid device id|device is deleted\/removed/i) {
				Common::doAccountResetLogout();
				Common::retreat(["\n", 'invalid_bkp_location_config_again', "\n"]);
			} elsif($webstat =~ /encryption_verification_failed/i) {
				Common::doAccountResetLogout();
				Common::retreat(["\n", 'encryption_verification_failed', "\n"]);
			}
		}
	} else {
		my $obls = Common::getUserConfiguration('BACKUPLOCATIONSIZE');
		if($obls != Common::setBackupLocationSize(1)) {
			$webstat = -1;
		} else {
			$webstat = Common::processNonDedupUpdateDelete(!$silentBackupFlag);
			if($webstat =~ /encryption_verification_failed/i) {
				Common::doAccountResetLogout(1);
			}
		}
	}

	if($webstat == -1) {
		my $dumpfile	= Common::createBackupStatRenewal(Common::getJobsPath('backup'));
		# sleep until the writer service considers the scan request
		while($dumpfile && -f $dumpfile) {
			sleep(2);
			if(!Common::isDBWriterRunning()) {
				unlink($dumpfile);
				last;
			}
		}
	}
}

Common::writeAsJSON($totalFileCountFile, {});
startBackup() if(!$isEmpty and !$cutOffReached and -e $pidPath);
exit_cleanup($errStr);

#****************************************************************************************************
# Subroutine Name         : startBackup
# Objective               : This function will fork a child process to generate backupset files and get
#							count of total files considered. Another forked process will perform main
#							backup operation of all the generated backupset files one by one.
# Added By				  :
# Modified By			  : Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub startBackup {
	$generateFilesPid = fork();

	unless(defined $generateFilesPid) {
		Common::traceLog(Constants->CONST->{'ForkErr'});
		$errStr = "Unable to start generateBackupsetFiles operation";
		return;
	}

    if($generateFilesPid == 0) {
        generateBackupsetFiles();
        exit(0);
    }

	if($isScheduledJob == 0 and !$silentBackupFlag) {
		unlink($progexitfile) if(-f $progexitfile);

		$displayProgressBarPid = fork();

		unless(defined $displayProgressBarPid) {
			Common::traceLog(Constants->CONST->{'ForkErr'});
			$errStr = "Unable to start progressbar operation";
			return;
		}

		if($displayProgressBarPid == 0) {
			displayBackupProgress();
			exit(0);
		}
	}

	close(FD_WRITE);

	open(my $handle, '>', $engineLockFile) or Common::traceLog("Could not open file '$engineLockFile' $!");
	close $handle;
	chmod $filePermission, $engineLockFile;

	my $exec_cores = getSystemCpuCores();
    my $writeOutputHeading = 1;
START:
	unless(open(FD_READ, "<", $info_file)) {
		$errStr = Constants->CONST->{'FileOpnErr'}." info_file in startBackup: $info_file to read, Reason:$!";
		return;
	}

	my $lastFlag = 0;
	while (1) {
		last unless(-f $pidPath);
		my $backupPid = undef;
		$line = <FD_READ> if($line eq "");

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
			$lastFlag = 1;
			$line = "";
			last;
		}

        if($writeOutputHeading){    
            my $outputHeading = Common::getStringConstant('heading_backup_output');
            $outputHeading	 .= "\n".(('-') x 78). "\n";
            print OUTFILE $outputHeading;
            $writeOutputHeading = 0;
        }

		$isEngineRunning = isEngineRunning($pidPath.'_'.$engineID);
		
		if (!$isEngineRunning) {
			while(1) {
				last if(!-e $pidPath or !isAnyEngineRunning($engineLockFile));

				$exec_loads = get_load_average();
				if($exec_loads > $exec_cores){
					sleep(10);
					next;
				}
				last;
			}

			if ($retry_failedfiles_index != -1) {
				$retry_failedfiles_index++;
				if($retry_failedfiles_index > 2000000000){
					$retry_failedfiles_index = 0;
				}
			}
			$backupPid = fork();
			if(!defined $backupPid) {
				$errStr = Constants->CONST->{'ForkErr'}.$whiteSpace.Constants->CONST->{"EvsChild"}.$lineFeed;
				return BACKUP_PID_FAIL;
			}
			elsif($backupPid == 0) {
                $pidOperationFlag = "ChildProcess";
				my $retType = doBackupOperation($line, $taskType, $engineID, $retry_failedfiles_index);
				exit(0);
			}
			else{
				push (@BackupForkchilds, $backupPid);
				if(defined($exec_loads) and ($exec_loads > $exec_cores)) {
					sleep(2);
				}
				else{
					sleep(1);
				}
			}
			$line = "";
		}

		Common::killPIDs(\@BackupForkchilds,0);

		if ($totalEngineBackup > 1) {
			$engineID++;
			if($engineID > $totalEngineBackup){
				$engineID = 1;
				sleep(1);
			}
		}
	}

	Common::waitForEnginesToFinish(\@BackupForkchilds, $engineLockFile);

	close FD_READ;
	$nonExistsCount		= Common::readInfoFile('FAILEDCOUNT');
	$noPermissionCount	= Common::readInfoFile('DENIEDCOUNT');
	$missingCount		= Common::readInfoFile('MISSINGCOUNT');
	$readySyncedFiles	= Common::readInfoFile('READYSYNC');

	waitpid($generateFilesPid, 0);
	undef @linesStatusFile;

	if($totalFiles == 0 or $totalFiles !~ /\d+/) {
		$totalFiles    = Common::readInfoFile('TOTALFILES');
		Common::traceLog("0 total files, check DB or cancel during backupset generation") if($totalFiles == 0 or $totalFiles !~ /\d+/);
	}

	if(-s $retryinfo > 0 && -e $pidPath &&
		((-f $minimalErrorRetry) ? ($retrycount <= $minRetryAttempts) : ($retrycount <= $maxNumRetryAttempts)) && $exitStatus == 0) {
		if ((-f $minimalErrorRetry) ? ($retrycount >= $minRetryAttempts) : ($retrycount >= $maxNumRetryAttempts)) {
			for (my $i=1; $i<= $totalEngineBackup; $i++) {
				if (-f $statusFilePath."_".$i  and  -s _ > 0) {
					readStatusFile($i);
					my $index = "-1";
					$statusHash{'FAILEDFILES_LISTIDX'} = $index;
					putParameterValueInStatusFile($i);
					undef @linesStatusFile;
				}
			}

			$retry_failedfiles_index = -1;
		}

		move($retryinfo, $info_file);
		updateRetryCount();

		#append total file number to info
		unless(open(INFO, ">>",$info_file)) {
			$errStr = Constants->CONST->{'FileOpnErr'}." info_file in startBackup : $info_file, Reason $!".$lineFeed;
			return;
		}

		print INFO "TOTALFILES $totalFiles\n";
		print INFO "FAILEDCOUNT $nonExistsCount\n";
		print INFO "DENIEDCOUNT $noPermissionCount\n";
		print INFO "MISSINGCOUNT $missingCount\n";
		print INFO "READYSYNC $readySyncedFiles\n";
		close INFO;
		chmod $filePermission, $info_file;
		unlink($minimalErrorRetry) if (-f $minimalErrorRetry);
		sleep 5; #5 Sec
		Common::traceLog("retrycount: $retrycount");
		$engineID = 1;
		Common::loadUserConfiguration(); #Reloading to handle domain connection failure case
		goto START;
	}
}

#*****************************************************************************************************
# Subroutine	: displayBackupProgress
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Reads the keyboard input and processes the input w.r.t backup progress detail
# Added By		: Senthil Pandian
# Modified By	: Sabin Cheruvattil
#*****************************************************************************************************
sub displayBackupProgress {
	my $bwPath  = Common::getCatfile($jobRunningDir, "bw.txt");
	my $keyPressEvent = Common::catchPressedKey();
	$pidOperationFlag = "DisplayProgress";
	my $temp = $totalEngineBackup;
	# our ($cumulativeCount, $cumulativeTransRate) = (0)x2;
	my $playPause  = 'running';
	my ($redrawForLess, $drawForPlayPause) = (0) x 2;
	my $moreOrLess = 'less';
    $moreOrLess    = 'more' if(Common::checkScreeSize());

	while(1) {
		last if(!-f $pidPath || -f $progexitfile);

		($redrawForLess, $drawForPlayPause) = (0) x 2;
		# Checking & changing status if play/pause key pressed in status retrieval script
		if(-f $bwPath) {
			my $bw= Common::getFileContents($bwPath);
			if($bw ne '') {
				if(($bw < 0) and ($playPause eq 'running')) {
					$drawForPlayPause = 1;
					$playPause = 'paused';
				} elsif(($bw >= 0) and ($playPause eq 'paused')) {
					$drawForPlayPause = 1;
					$playPause = 'running';
				}
			}
		}

		if($keyPressEvent->(1)) {
			if(($playPause eq 'running') && ($AppConfig::pressedKeyValue eq 'p')) {
				$drawForPlayPause = 1;
				$playPause = 'paused';
				Common::pauseOrResumeEVSOp($jobRunningDir,'p');
			} elsif(($playPause eq 'paused') && ($AppConfig::pressedKeyValue eq 'r')) {
				$drawForPlayPause = 1;
				$playPause = 'running';
				Common::pauseOrResumeEVSOp($jobRunningDir,'r');
			}

			if(($moreOrLess eq 'more') && ($AppConfig::pressedKeyValue eq '-')) {
				$moreOrLess = 'less';
				$redrawForLess = 1;
				# Common::clearScreenAndResetCurPos();
                $AppConfig::prevProgressStrLen = 10000;
			} elsif(($moreOrLess eq 'less') && ($AppConfig::pressedKeyValue eq '+')) {
				$moreOrLess = 'more' if(Common::checkScreeSize());
				# Common::clearScreenAndResetCurPos();
                $AppConfig::prevProgressStrLen = 10000;
			}
		}
		Common::displayProgressBar($progressDetailsFile, undef, $playPause, $moreOrLess, $redrawForLess)  if($playPause ne 'paused' || $drawForPlayPause);
		Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);
	}

	$keyPressEvent->(0);
	$AppConfig::pressedKeyValue = '';
	Common::displayProgressBar($progressDetailsFile, undef, $playPause, $moreOrLess, $redrawForLess)  if($playPause ne 'paused' || $drawForPlayPause);
}

#****************************************************************************************************
# Subroutine		: generateBackupsetFiles
# Objective			: This function will generate backupset files.
# Added By			: Dhritikana
# Modified By		: Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub generateBackupsetFiles {
	$pidOperationFlag = "GenerateFile";

	my $backupref	= Common::getDecBackupsetContents($BackupsetFile, 'array');
	my @BackupArray	= @{$backupref};
	chomp(@BackupArray);

	unless(@BackupArray) {
		Common::traceLog(Constants->CONST->{'BckFileOpnErr'} . " $BackupsetFile, Reason: $!");
		goto GENLAST;
	}

	@BackupArray = uniqueData(@BackupArray);

	my $traceExist = $errorDir . "/traceExist.txt";
	unless(open(TRACEERRORFILE, ">>", $traceExist)) {
		Common::traceLog(Constants->CONST->{'FileOpnErr'} . " $traceExist, Reason: $!.");
	}
	chmod $filePermission, $traceExist;

	my $permissionError = $errorDir . "/permissionError.txt";
	unless(open(TRACEPERMISSIONERRORFILE, ">>", $permissionError)) {
		Common::traceLog(Constants->CONST->{'FileOpnErr'} . " $permissionError, Reason: $!.");
	}
	chmod $filePermission, $permissionError;

	Common::loadUserConfiguration();
	my $showhidden = Common::getUserConfiguration('SHOWHIDDEN');
	Common::loadFullExclude();
	Common::loadPartialExclude();
	Common::loadRegexExclude();

	$filesonlycount = 0;
	$filecount = 0;

	my ($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 1);
	unless($dbfstate) {
		sleep(2) while(-f $scanfile);
		($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 1);
		exit(0) unless($dbfstate);
	}

	Sqlite::initiateDBoperation();
	my $offset = 0;
	my $splitsize = 0;
	my $backupfiles;
	my @cdpjbssum = ();

	$readySyncedFiles = Sqlite::getReadySyncedCount();
	$readySyncedFiles = 0 if(!$readySyncedFiles || $iscdp);

	my $rawdirs;
	my $cpdircache	= Common::getCatfile(Common::getJobsPath($AppConfig::cdp), $AppConfig::cdpcpdircache);
	my $fbct		= 0;
	if($iscdp and -f $cpdircache and -s _ > 0) {
		while(1) {
			if(Common::isFileLocked($cpdircache, 0, 1)) {
				Common::sleepForMilliSec(100);
			} else {
				$rawdirs = Common::getFileContents($cpdircache, 'array');
				my $fh;
				if(open($fh, "+>", $cpdircache)) {
					if(flock($fh, LOCK_EX|LOCK_NB)) {
						print $fh "";
						flock($fh, LOCK_UN);
						close($fh);
						last;
					}
				}

				close($fh) if($fh);
			}

			$fbct++;
			last if($fbct > 10);
		}
	}

	my @cdpdirs = ();
	if($rawdirs) {
		for my $cdpd (@{$rawdirs}) {
			chomp($cdpd);
			next if(!$cdpd or !-d $cdpd);
			if(!Sqlite::getBackedupCountUnderDir($cdpd)) {
				push @cdpdirs, $cdpd;
			}
		}
	}

	my @missitems = ();
	foreach my $item (@BackupArray) {
		last unless(-f $pidPath);

		chomp($item);
		next unless($item);
		$offset = 0;
		$item =~ s/^[\/]+|[\/]+$/\//g; #Removing "/" if more than one found at beginning/end

		next if($item =~ m/^$/ || $item =~ m/^[\s\t]+$/ || $item =~ /^\.\.?$/);

		chop($item) if($item ne "/" && substr($item, -1, 1) eq "/");

		if(!-l $item && -d _) {
			if($relative == 0) {
				$noRelIndex++;
				$BackupsetFile_new = $noRelativeFileset . "$noRelIndex";
				$filecount = 0;
				$a = rindex ($item, '/');
				$source[$noRelIndex] = substr($item, 0, $a);
				$source[$noRelIndex] = "/" if($source[$noRelIndex] eq "");
				$current_source = $source[$noRelIndex];

				unless(open $filehandle, ">>", $BackupsetFile_new) {
					Common::traceLog("cannot open $BackupsetFile_new to write");
					goto GENLAST;
				}

				chmod $filePermission, $BackupsetFile_new;
			}

			$backupfiles = Sqlite::getBackupFilesByKilo($item . '/', $iscdp, ($dedup eq 'on')? 1 : 0);
			my $bksetfiles = '';
			while(my $filedata = $backupfiles->fetchrow_hashref) {
				my $dirpath		= (defined($filedata->{'DIRNAME'}))? $filedata->{'DIRNAME'} : '';
				$dirpath		=~ s/^'//i;
				$dirpath		=~ s/'$//i;

				my $filename	= (defined($filedata->{'FILENAME'}))? $filedata->{'FILENAME'} : '';
				$filename		=~ s/^'//i;
				$filename		=~ s/'$//i;

				my $filesize	= (defined($filedata->{'FILE_SIZE'}))? $filedata->{'FILE_SIZE'} : 0;
				my $filepath	= Common::getCatfile($dirpath, $filename);

				last if(!-f $pidPath);
				chomp($filepath);
				next if($filepath =~ m/^$/ || $filepath =~ m/^[\s\t]+$/ || $filepath =~ /^\.\.?$/);

				unless(-r $filepath) {
					# @TODO: remove after debug
					# write into error
					my $reason = $!;
Common::traceLog("CDP NP ITEM: $filepath # reason:$reason");

					if ((-f $filepath && $reason =~ /no such file or directory/i) || $reason =~ /inappropriate ioctl for device/i || $reason =~ /permission denied/i) {
						$noPermissionCount++;
						print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$filepath]. Reason: Permission denied\n";
					} else {
						$nonExistsCount++;
						$missingCount++ if($reason =~ /No such file or directory/);
						print TRACEERRORFILE "[" . (localtime) . "] [FAILED] [$filepath]. Reason: $reason\n";
					}

					push(@missitems, $filepath);
					if(scalar @missitems >= $AppConfig::fsindexmax) {
						Common::createCleanNpMsRequest("$jobRunningDir/", \@missitems);
						@missitems = ();
					}

					next;
				}

				push(@cdpjbssum, $filepath) if($iscdp);
				# if($iscdp && $#cdpjbssum < 4) {
					# # Remove child if upcoming path is already present
					# if(my @dupchild = Common::hasChildInSet(dirname($filepath), \@cdpjbssum)) {
						# @cdpjbssum = grep {$_ ne $dupchild[0] || !-d $dupchild[0]} @cdpjbssum;
					# }

					# if(!scalar(Common::hasParentInSet($filepath, \@cdpjbssum))) {
						# # Add items if parent is not present
						# if(Sqlite::isThisDirIncForCDP($filepath)) {
							# push(@cdpjbssum, dirname($filepath));
						# } else {
							# push(@cdpjbssum, $filepath);
						# }
					# }
				# }

				$totalSize += $filesize;
				$splitsize += $filesize;

				if($relative == 0) {
					$temp = $filepath;
					$temp =~ s/$current_source// if($current_source ne "/");
					$bksetfiles .= qq($temp\n);
				}
				else {
					$current_source = "/";
					$bksetfiles .= qq($filepath\n);
					$BackupsetFileTmp = $relativeFileset;
				}
				
				$filecount++;
				$totalFiles++;

				if($filecount == FILE_MAX_COUNT || $splitsize >= $AppConfig::backupsetMaxSize) {
					if($relative == 0) {
						print $filehandle $bksetfiles;
					}
					else {
						print NEWFILE $bksetfiles;
					}

					$bksetfiles = '';
					$splitsize = 0;
					goto GENLAST unless(createBackupSetFiles1k());
				}
			}
			
			if($bksetfiles ne '') {
				if($relative == 0) {
					print $filehandle $bksetfiles;
				}
				else {
					print NEWFILE $bksetfiles;
				}
				
				$bksetfiles = '';
			}
			
			$backupfiles->finish();

			if($relative == 0 && $filecount > 0) {
				autoflush FD_WRITE;
				close $filehandle;
				print FD_WRITE "$current_source' '" . RELATIVE . "' '$BackupsetFile_new\n";
			}
		} elsif(!-l $item) {
			my $fileinf	= Sqlite::getFileInfoByFilePath($item);

			# Check if file is already in sync or not
			if($fileinf && $fileinf->{'BACKUP_STATUS'} eq $AppConfig::dbfilestats{'BACKEDUP'}) {
				next if(-f $item);
				$readySyncedFiles-- if($readySyncedFiles); #Added to handle when file is missing but still it counted as sync.
			}

			# Check if file is ok for CDP or not.
			if($iscdp) {
				next if(!$fileinf || $fileinf->{'BACKUP_STATUS'} ne $AppConfig::dbfilestats{'CDP'});
			}

			next if(Common::isThisExcludedItemSet($item . '/', $showhidden));

			unless(-r $item) {
				# @TODO: remove after debug
				# write into error
				my $reason = $!;
Common::traceLog("CDP NP ITEM: $item # reason:$reason");

				if ((-f $item && $reason =~ /no such file or directory/i) || $reason =~ /inappropriate ioctl for device/i || $reason =~ /permission denied/i) {
					$noPermissionCount++;
					print TRACEPERMISSIONERRORFILE "[" . (localtime) . "] [FAILED] [$item]. Reason: Permission denied\n";
				} else {
					$nonExistsCount++;
					$missingCount++ if($reason =~ /No such file or directory/);
					print TRACEERRORFILE "[" . (localtime) . "] [FAILED] [$item]. Reason: $reason\n";
				}

				push(@missitems, $item);
				if(scalar @missitems >= $AppConfig::fsindexmax) {
					Common::createCleanNpMsRequest("$jobRunningDir/", \@missitems);
					@missitems = ();
				}

				next;
			}

			push(@cdpjbssum, $item) if($iscdp);
			# if($iscdp && $#cdpjbssum < 4) {
				# # Remove child if upcoming path is already present
				# if(my @dupchild = Common::hasChildInSet(dirname($item), \@cdpjbssum)) {
					# @cdpjbssum = grep {$_ ne $dupchild[0] || !-d $dupchild[0]} @cdpjbssum;
				# }

				# # Add items if parent is not present
				# if(!scalar(Common::hasParentInSet($item, \@cdpjbssum))) {
					# if(Sqlite::isThisDirIncForCDP($item)) {
						# push(@cdpjbssum, dirname($item));
					# } else {
						# push(@cdpjbssum, $item);
					# }
				# }
			# }

			$totalSize += -s $item;
			$splitsize += -s _;
			$totalFiles++;

			print NEWFILE qq($item\n);
			$current_source = "/";

			if($relative == 0) {
				$filesonlycount++;
				$filecount = $filesonlycount;
			}
			else {
				$filecount++;
			}

			if($filecount == FILE_MAX_COUNT || $splitsize >= $AppConfig::backupsetMaxSize) {
				$splitsize = 0;
				$filesonlycount = 0;
				goto GENLAST unless(createBackupSetFiles1k("FILESONLY"));
			}
		}
	}

	$totalFiles += ($readySyncedFiles + $missingCount) unless($iscdp);

	# if(!$totalFiles && $missingCount) {
		# $totalFiles = $missingCount;
	# }

	Sqlite::closeDB();

	if(scalar @missitems > 0) {
		Common::createCleanNpMsRequest("$jobRunningDir/", \@missitems);
		@missitems = ();
	}

	if($relative == 1 && $filecount > 0) {
		autoflush FD_WRITE;
		print FD_WRITE "$current_source' '" . RELATIVE . "' '$BackupsetFile_new\n";
	} elsif($filesonlycount > 0) {
		$current_source = "/";
		autoflush FD_WRITE;
		print FD_WRITE "$current_source' '" . NORELATIVE . "' '$filesOnly\n";
	}

GENLAST:
	autoflush FD_WRITE;
	print FD_WRITE "TOTALFILES $totalFiles\n";
	print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
	print FD_WRITE "DENIEDCOUNT $noPermissionCount\n";
	print FD_WRITE "MISSINGCOUNT $missingCount\n";
	print FD_WRITE "READYSYNC $readySyncedFiles\n";
	close FD_WRITE;
	close NEWFILE;
	$pidOperationFlag = "generateListFinish";
	close INFO;

	open FILESIZE, ">$fileForSize" or Common::traceLog(Constants->CONST->{'FileOpnErr'} . " $fileForSize. Reason: $!");
	print FILESIZE "$totalSize";
	close FILESIZE;
	chmod $filePermission, $fileForSize;

	close(TRACEERRORFILE);
	close(TRACEPERMISSIONERRORFILE);

	if($iscdp) {
		# Common::fileWrite($totalFileCountFile, $totalFiles);
		Common::loadAndWriteAsJSON($totalFileCountFile, {$AppConfig::totalFileKey => $totalFiles});
	} else {
		# Common::fileWrite($totalFileCountFile, ($totalFiles - $readySyncedFiles));
		Common::loadAndWriteAsJSON($totalFileCountFile, {$AppConfig::totalFileKey => ($totalFiles - $readySyncedFiles)});
	}

	chmod $filePermission, $totalFileCountFile;

	if($iscdp) { # Commented by Senthil, enabled by sabin as per Deepak's review comment.
		writeCDPBackupsetToLog(\@cdpjbssum, \@cdpdirs);
	} else {
		if(-f $cpdircache and -s _ and !Common::isFileLocked($cpdircache)) {
			Common::fileWrite($cpdircache, '');
		}
	}

	exit 0;
}

#****************************************************************************************************
# Subroutine		: cancelSubRoutine
# Objective			: Call if user cancel the execution of script. It will do all require cleanup before exiting.
# Added By			: Arnab Gupta
# Modified By		: Dhritikana, Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************
sub cancelSubRoutine {
	if($pidOperationFlag eq "GenerateFile") {
		open FD_WRITE, ">>", $info_file or (print Constants->CONST->{'FileOpnErr'}."info_file in cancelSubRoutine: $info_file to write, Reason:$!"); # die handle?
		autoflush FD_WRITE;
		print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
		print FD_WRITE "DENIEDCOUNT $noPermissionCount\n";
		print FD_WRITE "MISSINGCOUNT $missingCount\n";
		print FD_WRITE "READYSYNC $readySyncedFiles\n";
		close(FD_WRITE);
		close NEWFILE;
		exit 0;
	}

    #Added to prevent multiple exit cleanup calls due to fork processes
    exit(0) if($pidOperationFlag =~ /DisplayProgress|ChildProcess|ExitCleanup/);

	if($pidOperationFlag eq "main") {
		my $tempBackupUtfFile = $backupUtfFile;
		$tempBackupUtfFile =~ s/\[/\\[/;
		$tempBackupUtfFile =~ s/{/[{]/;
		my $evsCmd = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$tempBackupUtfFile\'";
		$evsCmd = $evsCmd;
		$evsRunning = `$evsCmd`;

		@evsRunningArr = split("\n", $evsRunning);
		my $arrayData = ($machineInfo eq 'freebsd')? 1 : 3;

		foreach(@evsRunningArr) {
			next if($_ =~ /$evsCmd|grep/);

			my $pid = (split(/[\s\t]+/, $_))[$arrayData];
			$scriptTerm = system(Common::updateLocaleCmd("kill -9 $pid 2>/dev/null"));

			Common::traceLog(Constants->CONST->{'KilFail'} . " Backup") if(defined($scriptTerm) && $scriptTerm != 0 && $scriptTerm ne '');
		}

		waitpid($generateFilesPid, 0) if($generateFilesPid);
		waitpid($displayProgressBarPid, 0) if($displayProgressBarPid);
		Common::waitForChildProcess();

		if(($totalFiles == 0 or $totalFiles !~ /\d+/) and -s $info_file) {
			my $fileCountCmd = "cat '$info_file' | grep \"^TOTALFILES\"";
			$fileCountCmd = Common::updateLocaleCmd($fileCountCmd);
			$totalFiles = `$fileCountCmd`;
			$totalFiles =~ s/TOTALFILES//;
		}

		Common::traceLog("0 total files, check DB/cancel during backup set generation") if($totalFiles == 0 or $totalFiles !~ /\d+/);

		if($nonExistsCount == 0) {
			my $nonExistCheckCmd = "cat '$info_file' | grep \"^FAILEDCOUNT\"";
			$nonExistCheckCmd = Common::updateLocaleCmd($nonExistCheckCmd);
			$nonExistsCount = `$nonExistCheckCmd`;
			$nonExistsCount =~ s/FAILEDCOUNT//;
		}

		# waitpid($pid_OutputProcess, 0) if($pid_OutputProcess);
		$errStr = Constants->CONST->{'operationFailUser'} unless($errStr);
		exit_cleanup($errStr);
	}
}

#****************************************************************************************************
# Subroutine Name         : exit_cleanup
# Objective               : This function will execute the major functions required at the time of exit
# Added By                : Deepak Chaurasia
# Mofidied By             : Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub exit_cleanup {
    $pidOperationFlag = 'ExitCleanup';
	if($silentBackupFlag == 0 and $taskType eq 'Manual') {
		system('stty', 'echo');
		system("tput sgr0");
	}
Common::traceLog("iscdp:$iscdp"); #Needs to be removed later
Common::traceLog("errStr1:$errStr"); #Needs to be removed later
	unless($isEmpty) {
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX', 'SYNC_COUNT_FILES_INDEX', 'ERROR_COUNT_FILES', 'DENIED_COUNT_FILES', 'MISSED_FILES_COUNT', 'MODIFIED_FILES_COUNT', 'TOTAL_TRANSFERRED_SIZE', 'EXIT_FLAG_INDEX');
		($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount, $modifiedCount, $transferredFileSize, $exit_flag) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
		chomp($exit_flag);
Common::traceLog("exit_flag:$exit_flag"); #Needs to be removed later
		if($errStr eq "" and -e $errorFilePath) {
			open ERR, "<$errorFilePath" or Common::traceLog(Constants->CONST->{'FileOpnErr'}."errorFilePath in exit_cleanup: $errorFilePath, Reason: $!");
			$errStr = <ERR>;
			close(ERR);
			chomp($errStr);
Common::traceLog("errStr2:$errStr"); #Needs to be removed later
		}

		if(!-e $pidPath or $exit_flag) {
			$cancelFlag = 1;
Common::traceLog("pid not found"); #Needs to be removed later
			# In child process, if we exit due to some exit scenario, then this exit_flag will be true with error msg
			@exit = split("-", $exit_flag, 2);
			Common::traceLog(" exit = $exit[0] and $exit[1]");

			if($errStr =~ /^2\-/ig) {
				$exit[0] = 2;
				$exit[1] = $errStr;
			}

			if(!$exit[0] && !$errStr) {
				if($isScheduledJob == 1) {
					$errStr = Constants->CONST->{'operationFailCutoff'};
					$errStr = Constants->CONST->{'operationFailUser'} if(!-e Common::getServicePath());
					$errStr = Constants->CONST->{'operationFailUser'} if(-f $schcancelfile);
				}
				elsif($isScheduledJob == 0) {
					$errStr = Constants->CONST->{'operationFailUser'};
				}

				if($exit[1] =~ /failed to get the device information|invalid device id|device is deleted\/removed/i) {
					$errStr = $exit[1];
				} elsif($exit[1] =~ /quota exceeded/i) {
					$errStr = $exit[1];
				}

				if ($errStr eq Constants->CONST->{'operationFailCutoff'}) {
					if(Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
						Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'scheduled_cut_off'}) and Common::saveNotifications();
						Common::unlockCriticalUpdate("notification");
					}
				}
			}
			else {
				if($exit[1] ne "") {
					$errStr = $exit[1];
					# Common::checkAndUpdateAccStatError($userName, $errStr); #Commented by Senthil for Harish_2.3_08_5
					# Below section has been added to provide user friendly message and clear instruction in case of password mismatch or encryption verification failed. 
					# In this case we are removing the IDPWD file.So that user can login and recreate these files with valid credential.
					if ($errStr =~ /password mismatch|encryption verification failed/i) {
						Common::createBackupStatRenewalByJob('backup') if(Common::getUserConfiguration('DEDUP') ne 'on');
						$errStr = $errStr . ' ' . Constants->CONST->{loginAccount} . $lineFeed;
						# unlink($pwdPath);

						if($taskType eq "Scheduled") {
							unlink($pwdPath);
							# replace SCH with empty. later this will get handled
							$pwdPath =~ s/_SCH$//g;
						}
					} elsif($errStr =~ /failed to get the device information|invalid device id/i) {
						$errStr = ($exit[0] == 2? '' : $errStr . ' ') . Constants->CONST->{backupLocationConfigAgain} . $lineFeed;
					} else {
						# $errStr = Common::checkErrorAndLogout($errStr, undef, 1);
                        $errStr = Common::checkErrorAndReturnErrorMessage($errStr);
					}
				}
			}
		}
	}
Common::traceLog("errStr3:$errStr"); #Needs to be removed later

	if($pidPath and -d dirname($pidPath)) {
		unlink($pidPath) if(!Common::fileWrite($progexitfile, '1'));
	}

	waitpid($displayProgressBarPid, 0) if ($displayProgressBarPid);
	wait();

	$errStr =~ s/^2\-//g;

	writeOperationSummary(Constants->CONST->{'BackupOp'}, $cancelFlag, $transferredFileSize);
	my $subjectLine = getOpStatusNeSubLine();

	# rmtree($evsTempDirPath) if(-d $evsTempDirPath);
    Common::removeItems([$retryinfo, $fileForSize, $trfSizeAndCountFile, $jobCancelFile, $progexitfile, $errorDir, $pidPath]);

	if ((-f $outputFilePath) and (!-z $outputFilePath)) {
		my $finalOutFile = $outputFilePath;
		if($iscdp && $filesConsideredCount == 0) {
			$finalOutFile =~ s/_Running_/_NoFiles\_/;
		} else {
			$finalOutFile =~ s/_Running_/_$status\_/;
		}
		move($outputFilePath, $finalOutFile);
		Common::updateLastBackupStatus($AppConfig::backup, $status, basename($finalOutFile));

		if (Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
			Common::setNotification('update_backup_progress', ((split("/", $finalOutFile))[-1])) if(!$iscdp);
			Common::setNotification('get_logs') and Common::saveNotifications();
			Common::unlockCriticalUpdate("notification");
		}

		$outputFilePath = $finalOutFile;
		$finalSummary .= Constants->CONST->{moreDetailsReferLog}.qq(\n); #Concat log file path with job summary. To access both at once while displaying the summary and log file location.
		$finalSummary .= $status."\n";

		if ($errStr ne "" &&  $status ne "Success") {
			$finalSummary .= $errStr;
			Common::fileWrite($outputFilePath, qq($errStr\n), 'APPEND') if($iscdp);
		}
        Common::fileWrite($outputFilePath, (('=') x 150).$lineFeed.$lineFeed, 'APPEND') if($iscdp);
        
		#It is a generic function used to write content to file.
		#if ($silentBackupFlag == 0){
		# writeToFile($summaryFilePath, $finalSummary);
		Common::fileWrite($summaryFilePath,$finalSummary);
		chmod $filePermission, $summaryFilePath;
		#}

		if ($taskType eq "Manual" and $silentBackupFlag == 0) {
			# displayProgressBar($progressDetailsFile, Common::getTotalSize($fileForSize)) unless($isEmpty);
			displayFinalSummary(Common::getStringConstant('backup_job'), $summaryFilePath);
		}

        #Above function display summary on stdout once backup job has completed.
		# upload log
		Common::saveLog($finalOutFile, 0);

		$lpath	= basename($outputFilePath);

		my %bkpsummary = (
			'st'		=> strftime("%Y-%m-%d %H:%M:%S", localtime(mktime(@startTime))),
			'et'		=> strftime("%Y-%m-%d %H:%M:%S", localtime(mktime(@endTime))),
			'uname'		=> $userName,
			'hostname'	=> $AppConfig::hostname,
			'files'		=> $filesConsideredCount,
			'filesync'	=> $syncedFiles,
			'status'	=> $status,
			'duration'	=> (mktime(@endTime) - mktime(@startTime)),
			'optype'	=> $taskType eq 'Manual'? 'Interactive Backup' : 'Backup',
			'lpath'		=> $lpath,
			'logfile'	=> $outputFilePath,
			'summary'	=> '',
		);
		
		$bkpsummary{'summary'} = Common::getWebViewSummary(\%bkpsummary);
		# web view xml upload
		Common::saveWebViewXML(\%bkpsummary);
	}

    if ($isEmpty){
        Common::sendMail({
                'serviceType' => $taskType,
				'jobType' => 'backup',
                'jobName' => 'default_backupset',
                'subject' => $subjectLine,
                'jobStatus' => lc($status),
                'errorMsg' => 'NOBACKUPDATA'
            });
    }
    else {
        Common::sendMail({
                'serviceType' => $taskType,
				'jobType' => 'backup',
                'jobName' => 'default_backupset',
                'subject' => $subjectLine,
                'jobStatus' => lc($status)
            }) unless($iscdp);
    }

#	terminateStatusRetrievalScript($summaryFilePath) if ($taskType eq "Scheduled"); #Commented by Senthil

	$operationsfile = $jobRunningDir.'/operationsfile.txt';
	my $doBackupOperationErrorFile = "$jobRunningDir/doBackuperror.txt_";
	Common::removeItems([$info_file, $idevsErrorFile.'*', $idevsOutputFile.'*', $statusFilePath.'*', $utf8Files.'*', $operationsfile.'*', $doBackupOperationErrorFile.'*', $relativeFileset.'*', $noRelativeFileset.'*', $filesOnly.'*', $failedfiles.'*', $pidPath.'*', $errorFilePath, $minimalErrorRetry, $schcancelfile, $engineLockFile]);

	if(defined(${ARGV[0]}) && ${ARGV[0]} eq 'immediate') {
		Common::loadCrontab();
		Common::updateCronTabToDefaultVal("backup") if(Common::getCrontab('backup', 'default_backupset', '{settings}{frequency}') eq 'immediate');
	}

	# some file has been backed up during the process, getQuota call is done to calculate the fresh quota.
	if ($successFiles > 0) {
		my $childProc = fork();
		if ($childProc == 0) {
			$AppConfig::callerEnv = 'BACKGROUND'; #Added to ignore the error display
			getQuota();
			exit(0);
		}
		
		Common::setBackupLocationSize(1);
	} else {
		checkAndUpdateQuota();
	}

    $errStr = Common::checkErrorAndLogout($errStr, undef, 1);
	if($errStr) {
		Common::traceLog($errStr);
		if($errStr =~ /failed to get the device information|invalid device id|device is deleted\/removed|encryption verification failed/i) {
			Common::doAccountResetLogout(1);
			unlink($pwdPath) if($errStr =~ /password mismatch|encryption verification failed/i && -f $pwdPath);
		}
	}

	Common::traceLog(['backup_completed']);
	exit 0;
}

#****************************************************************************************************
# Subroutine Name         : createBackupSetFiles1k.
# Objective               : This function will generate 1000 Backetupset Files
# Added By                : Pooja Havaldar
#*****************************************************************************************************/
sub createBackupSetFiles1k {
	my $filesOnlyFlag = $_[0];
	$Backupfilecount++;

	if($relative == 0) {
		if($filesOnlyFlag eq "FILESONLY") {
			$filesOnlyCount++;
			print FD_WRITE "$current_source' '".NORELATIVE."' '$BackupsetFile_Only\n";
			$BackupsetFile_Only =  $filesOnly."_".$filesOnlyCount;
			close NEWFILE;
			unless(open NEWFILE, ">", $BackupsetFile_Only) {
				Common::traceLog(Constants->CONST->{'FileOpnErr'} . "filesOnly in 1k: $filesOnly to write, Reason: $!.");
				return 0;
			}

			chmod $filePermission, $BackupsetFile_Only;
		} else {
			print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
			$BackupsetFile_new = $noRelativeFileset."$noRelIndex"."_$Backupfilecount";

			close $filehandle;
			unless(open $filehandle, ">", $BackupsetFile_new) {
				Common::traceLog(Constants->CONST->{'FileOpnErr'} . "BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!.");
				return 0;
			}

			chmod $filePermission, $BackupsetFile_new;
		}
	}
	else {
		print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
		$BackupsetFile_new = $relativeFileset."_$Backupfilecount";

		close NEWFILE;
		unless(open NEWFILE, ">", $BackupsetFile_new) {
			Common::traceLog(Constants->CONST->{'FileOpnErr'} . "BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!.");
			return 0;
		}

		chmod $filePermission, $BackupsetFile_new;
	}

	autoflush FD_WRITE;
	$filecount = 0;

	sleep(1) if($Backupfilecount % 15 == 0);
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : doBackupOperation.
# Objective               : This subroutine performs the actual task of backing up files. It creates
#							a child process which executes the backup command. It also creates a process
#							which continuously monitors the temporary output file. At the end of backup,
#							it inspects the temporary error file if present. It then deletes the temporary
#							output file, temporary error file and the temporary directory created by
#							idevsutil binary.
# Usage			  : doBackupOperation($line);
# Where			  : $line :
# Modified By             : Deepak Chaurasia, Vijay Vinoth
#*****************************************************************************************************/
sub doBackupOperation {
	my $parameters				= $_[0];
	my $scheduleFlag			= $_[1];
	my $operationEngineId		= $_[2];
	my $retry_failedfiles_index = $_[3];
	my $doBackupOperationErrorFile = "$jobRunningDir/doBackuperror.txt_".$operationEngineId;
	@parameter_list				= split(/\' \'/, $parameters, 3);
	$backupUtfFile				= getOperationFile(Constants->CONST->{'BackupOp'}, $parameter_list[2], $parameter_list[1], $parameter_list[0], $operationEngineId);
	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	unless(flock($startPidFileLock, LOCK_SH)) {
		Common::traceLog("Failed to lock engine file");
		return 0;
	}

	Common::fileWrite($pidPath.'_evs_'.$operationEngineId, 1); #Added for Harish_2.19_7_7, Harish_2.19_6_7
	open(my $engineFp, ">>", $pidPath . '_' . $operationEngineId) or return 0;

	unless(flock($engineFp, LOCK_EX)) {
		print "Unable to lock \n";
		return 0;
	}

	unless($backupUtfFile) {
		Common::traceLog($errStr);
		return 0;
	}

	my $tmpbackupUtfFile = $backupUtfFile;
	$tmpbackupUtfFile =~ s/\'/\'\\''/g;

	my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
	$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;

	# EVS command to execute for backup
	$idevsutilCommandLine = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmpbackupUtfFile\'";

	my $backupPid = fork();
	unless(defined $backupPid) {
		$errStr = Constants->CONST->{'ForkErr'} . $whiteSpace . Constants->CONST->{"EvsChild"} . $lineFeed;
		return BACKUP_PID_FAIL;
	}

	if($backupPid == 0) {
		$pidOperationFlag = 'dobackup';
		if(-e $pidPath) {
			system($idevsutilCommandLine." > /dev/null 2>'$doBackupOperationErrorFile'");
			if(-e $doBackupOperationErrorFile && -s _) {
				my $error = Common::getFileContents($doBackupOperationErrorFile);
				if($error ne '' and $error !~ /no version information available/) {
					$errStr = Constants->CONST->{'DoBckOpErr'}.Constants->CONST->{'ChldFailMsg'};
					Common::traceLog("$errStr; Child Launch Error: $error");
					if (open(ERRORFILE, ">> $errorFilePath")) {
						autoflush ERRORFILE;
						print ERRORFILE $errStr;
						close ERRORFILE;
						chmod $filePermission, $errorFilePath;
					}
					else {
						Common::traceLog($lineFeed . Constants->CONST->{'FileOpnErr'} . "errorFilePath in doBackupOperation:" . $errorFilePath . ", Reason:$! $lineFeed");
					}
				}
			}

			Common::removeItems($doBackupOperationErrorFile);
			if(open OFH, ">>", $idevsOutputFile . "_" . $operationEngineId) {
				print OFH "\nCHILD_PROCESS_COMPLETED\n";
				close OFH;
				chmod $filePermission, $idevsOutputFile . "_" . $operationEngineId;
			}
			else {
				print Constants->CONST->{'FileOpnErr'} . " $outputFilePath. Reason: $!";
				Common::traceLog(Constants->CONST->{'FileOpnErr'} . " outputFilePath in doBackupOperation: $outputFilePath. Reason: $!");
				return 0;
			}
		}

		sleep(1);
        unlink($pidPath.'_evs_'.$operationEngineId);
		exit(1);
	}

	exit(1) if(!-e $pidPath);

	$workingDir				= $currentDir;
	$workingDir				=~ s/\'/\'\\''/g;
	my $tmpoutputFilePath	= $outputFilePath;
	$tmpoutputFilePath		=~ s/\'/\'\\''/g;
	my $TmpBackupSetFile	= $parameter_list[2];
	$TmpBackupSetFile		=~ s/\'/\'\\''/g;
	my $TmpSource			= $parameter_list[0];
	$TmpSource				=~ s/\'/\'\\''/g;
	my $tmp_jobRunningDir	= $jobRunningDir;
	$tmp_jobRunningDir		=~ s/\'/\'\\''/g;
	my $tmpBackupHost		= $backupHost;
	$tmpBackupHost			=~ s/\'/\'\\''/g;

	$fileChildProcessPath	= qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
	# $ENV{'OPERATION_PARAM'}=join('::',($tmp_jobRunningDir,$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$curLines,$progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$errorDevNull));
	my $param = join("\n", ('BACKUP_OPERATION',$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$scheduleFlag,$operationEngineId));
# @TODO: Remove after debugging | before release
# Common::fileWrite('/tmp/operation.log', "===================\n$param==================\n\n", 'APPEND');
	writeParamToFile("$tmp_jobRunningDir/operationsfile.txt_" . $operationEngineId, $param);
	$cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\' \'$operationEngineId\' \'$retry_failedfiles_index\'";
	$pidOperationFlag = 'parseop';
	$out = system("$cmd 2>/dev/null &");
	waitpid($backupPid, 0) if($backupPid);
	Common::waitForChildProcess($pidPath.'_proc_'.$operationEngineId);
	unlink($pidPath.'_'.$operationEngineId . ':waitchild done');
	updateServerAddr();

	unlink($parameter_list[2]);
	unlink($idevsOutputFile . '_' . $operationEngineId);
	flock($startPidFileLock, LOCK_UN);
	flock($engineFp, LOCK_UN);

	return 0 if(-e $errorFilePath && -s _);

	return BACKUP_SUCCESS;
}

#******************************************************************************************************************
# Subroutine Name         : getOpStatusNeSubLine.
# Objective               : This subroutine returns backup operation status and email subject line
# Added By                : Dhritikana
# Modified By             : Yogesh Kumar, Senthil Pandian
#******************************************************************************************************************/
sub getOpStatusNeSubLine {
	my $subjectLine= "";

	if ($status =~ /Success/) {
		if($successFiles > 0) {
			$subjectLine = "$taskType Backup Status Report " . "[$userName]" . " [Backed up file(s): $successFiles of $filesConsideredCount]" . " [Successful Backup]";
		} else {
			$subjectLine = "$taskType Backup Status Report " . "[$userName]" . " [Successful Backup]";
		}
	} else {
		$subjectLine = "$taskType Backup Status Report " . "[$userName]" . " [$status Backup]";
	}

	return ($subjectLine);
}

#****************************************************************************************************
# Subroutine		: restoreBackupsetFileConfiguration
# Objective			: This subroutine moves the BackupsetFile to the original configuration
# Added By			: Dhritikana
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub restoreBackupsetFileConfiguration {
	unlink <"$relativeFileset"*> if($relativeFileset ne "");
	unlink <"$noRelativeFileset"*> if($noRelativeFileset ne "");
	unlink <"$filesOnly"*> if($filesOnly ne "");
	unlink <"$failedfiles"*> if($failedfiles ne "");
	unlink "$info_file";
}

#*******************************************************************************************************
# Subroutine Name         :	updateServerAddr
# Objective               :	handling wrong server address error msg
# Added By                : Dhritikana
# Modified By			  : Sabin Cheruvattil
#********************************************************************************************************
sub updateServerAddr {
	my $tempErrorFileSize = -s $idevsErrorFile;
	if($tempErrorFileSize > 0) {
		my $errorPatternServerAddr = "unauthorized user";
		open EVSERROR, "<", $idevsErrorFile or Common::traceLog("Failed to open error.txt");
		$errorContent = <EVSERROR>;
		close EVSERROR;

		if($errorContent =~ m/$errorPatternServerAddr/) {
			unless(getServerAddr()) {
				Common::updateAccountStatus($userName, 'UA');
				exit_cleanup($errStr);
			}

			return 1;
		}
	}
}

#*******************************************************************************************************
# Subroutine Name         :	createBackupTypeFile
# Objective               :	Create files respective to Backup types (relative or no relative)
# Added By                : Dhritikana
#********************************************************************************************************
sub createBackupTypeFile {
	#opening info file for generateBackupsetFiles function to write backup set information and for main process to read that information
	if(!open(FD_WRITE, ">", $info_file)){
		$errStr = "Could not open file info_file in createBackupTypeFile: $info_file to write, Reason:$!";
		Common::traceLog($errStr) and die;
	}
	chmod $filePermission, $info_file;

	#Backupset File name for mirror path
	if($relative != 0) {
		$BackupsetFile_new =  $relativeFileset;
		if(!open NEWFILE, ">>", $BackupsetFile_new) {
			Common::traceLog(Constants->CONST->{'FileOpnErr'} . " relativeFileset in createBackupTypeFile $relativeFileset to write, Reason:$!.") and die;
		}
		chmod $filePermission, $BackupsetFile_new;
	}
	else {
		#Backupset File Name only for files
		$BackupsetFile_Only = $filesOnly;
		if(!open NEWFILE, ">>", $BackupsetFile_Only) {
			Common::traceLog(Constants->CONST->{'FileOpnErr'} . " filesOnly in createBackupTypeFile: $filesOnly to write, Reason:$!.") and die;
		}
		chmod $filePermission, $BackupsetFile_Only;

		$BackupsetFile_new = $noRelativeFileset;
	}
}

#*******************************************************************************************************
# Subroutine Name         :	updateRetryCount
# Objective               :	updates retry count based on recent backup files.
# Added By                : Avinash
# Modified By             : Dhritikana, Yogesh Kumar
#********************************************************************************************************/
sub updateRetryCount {
	my $curFailedCount = 0;
	my $currentTime = time();

	for(my $i = 1; $i <= $totalEngineBackup; $i++) {
		if(-e $statusFilePath . "_" . $i and -s _ > 0) {
			$curFailedCount = $curFailedCount + getParameterValueFromStatusFile($i,'ERROR_COUNT_FILES');
			undef @linesStatusFile;
		}
	}

	if (!-f $minimalErrorRetry and ($curFailedCount < $prevFailedCount)) {
		$retrycount = 0;
	}
	else {
		if ($currentTime-$prevTime < 90) {
			sleep 10;
		}
		$retrycount++;
	}

	#assign the latest backedup and synced value to prev.
	$prevFailedCount = $curFailedCount;
	$prevTime = $currentTime;
}
#*******************************************************************************************************
# Subroutine Name         :	checkArchiveStatus
# Objective               :	Check the status of archive cleanup & wait/terminate if archive is in-progress
# Added By                : Senthil Pandian
#********************************************************************************************************/
sub checkArchiveStatus {
	my $pidPath = "$usrProfilePath/$userName/Archive/DefaultBackupSet/pid.txt";
	my %cutOff;
	my $kill=0;
	%cutOff = getBackupCutOff() if($taskType eq "Scheduled");

	while(1){
		$isJobRunning=0;
		if (-e $pidPath) {
			if(!pidAliveCheck($pidPath)) {
				$isJobRunning=1;
			} elsif(-e $pidPath) {
				unlink($pidPath);
			}
		}
		if($isJobRunning==1){
			if($taskType eq "Scheduled"){
				if(scalar(keys %cutOff)) {
					if(checkBackupCutOff(\%cutOff)) {
						$errStr = Constants->CONST->{'operationFailCutoff'};
						$kill=1;
						last;
					}
				}
				sleep(60);
				next;
			} else {
				print $lineFeed."Archive cleanup is in progress. Please try again later.".$lineFeed.$lineFeed;
				exit 0;
			}
		}
		last;
	}
	return $kill;
}

#*******************************************************************************************************
# Subroutine Name         :	getBackupCutOff
# Objective               :	Get the backup cut-off hour & min
# Added By                : Senthil Pandian
#********************************************************************************************************/
sub getBackupCutOff {
	my %cutOff;
	Common::loadCrontab();
	if (Common::getCrontab('cancel', "default_backupset", '{settings}{status}') eq 'enabled') {
		my $hours = Common::getCrontab('cancel', "default_backupset", '{h}');
		my $mins  = Common::getCrontab('cancel', "default_backupset", '{m}');
		$cutOff{'hours'} = $hours;
		$cutOff{'mins'}  = $mins;
	}
	return %cutOff;
}

#*******************************************************************************************************
# Subroutine Name         :	checkBackupCutOff
# Objective               :	Check the cut-off
# Added By                : Senthil Pandian
#********************************************************************************************************/
sub checkBackupCutOff {
	my %cutOff   = %{$_[0]};
	my @now		 = localtime;
	my $currMin	 = $now[1];
	my $currHour = $now[2];
# use Data::Dumper;
# print Dumper(\%cutOff);
# $currHour = 6;
# $currMin = 35;
	# print "currHour:$currHour#cutOff:".$cutOff{'hours'}."#\n";
	if($currHour == $cutOff{'hours'}) {
		return 1 if($currMin >= $cutOff{'mins'});
	}
	return 0;
}
