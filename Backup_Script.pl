#!/usr/bin/env perl

#######################################################################
#Script Name : Backup_Script.pl
#######################################################################

use lib map{if (__FILE__ =~ /\//) {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";}}else {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {"./$_";}}} qw(Idrivelib/lib .);

use FileHandle;
use POSIX ":sys_wait_h";

use AppConfig;
use Common;

Common::waitForUpdate();
Common::initiateMigrate();
#Common::loadUserConfiguration();

require 'Header.pl';

#use Constants 'CONST';
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
#my $pid_OutputProcess = undef;
#my $backupPid = undef; #Process ID of child process#
my $generateFilesPid = undef; #Process ID of child process for generate Backup set files#
my $displayProgressBarPid = undef;
my $errorFilePresent = false;
#Check if EVS Binary exists.
#my $lineCount; This variable is not used at any place in the script.
#my $prevLineCount; This variable is not used at any place in the script.
my $cancelFlag = 0;
my %backupExcludeHash = (); #Hash containing items present in Exclude List#
my $backupUtfFile = '';

my $maxNumRetryAttempts = 1000;
my $minRetryAttempts = 10;
my $totalSize = 0;
my $BackupsetFileTmp = "";
my $regexStr = '';
my $parStr = '';
#my $relativeAsPerOperation = undef; This variable is not used at any place in the script.
my $filesOnlyCount = 0;
my $prevFailedCount = 0;
my $excludedCount = 0;
my $noRelIndex = 0;
my $retrycount = 0;
my $exitStatus = 0;
my $pidOperationFlag = "main";
my $prevTime = time();
my $relativeFileset = "BackupsetFile_Rel";
my $filesOnly = "BackupsetFile_filesOnly";
my $noRelativeFileset = "BackupsetFile_NoRel";
$jobType = "Backup";
my $retry_failedfiles_index = 0;
my $engineID = 1;
my @BackupForkchilds;
#my $DefaultSet = undef; This variable is not used at any place in the script.

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
use constant EXCLUDED_MAX_COUNT => 30000;
my @commandArgs = qw(--silent SCHEDULED dashboard immediate);
if ($#ARGV >= 0){
	if(!validateCommandArgs(\@ARGV,\@commandArgs)){
		print Constants->CONST->{'InvalidCmdArg'}.$lineFeed;
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
$SIG{PWR}	= \&process_term;
$SIG{QUIT}	= \&process_term;
$SIG{TERM}	= \&process_term;
$SIG{TSTP}	= \&process_term;
$SIG{USR1}	= \&process_term;

#Assigning Perl path
my $perlPathCmd = Common::updateLocaleCmd('which perl');
my $perlPath = `$perlPathCmd`;
chomp($perlPath);
if($perlPath eq ''){
	$perlPath = '/usr/local/bin/perl';
}
###################################################
#The signal handler invoked when SIGINT or SIGTERM#
#signal is received by the script                 #
###################################################
sub process_term {
	my $signame = shift;
	unlink($pidPath);
	cancelSubRoutine();
	exit(0);
}

$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

loadUserData();

my $BackupsetFile = $backupsetFilePath;
chmod $filePermission, $BackupsetFile;
# Trace Log Entry #
my $curFile = basename(__FILE__);

#Flag to silently do backup operation.
my $silentBackupFlag = 0;
if (${ARGV[0]} eq '--silent' or ${ARGV[0]} eq 'dashboard'  or ${ARGV[0]} eq 'immediate') {
	$silentBackupFlag = 1;
}

Common::checkAccountStatus($silentBackupFlag? 0 : 1);

headerDisplay($0) if ($silentBackupFlag == 0 and $ARGV[0] ne 'SCHEDULED');
#Verifying if Backup scheduled or manual job
my $isScheduledJob = 0;
if((${ARGV[0]} eq "SCHEDULED") or (${ARGV[0]} eq "immediate")) {
	$pwdPath = $pwdPath."_SCH";
	$pvtPath = $pvtPath."_SCH";
	$isScheduledJob = 1;
	$taskType = "Scheduled";
	#$BackupsetFile = $backupsetSchFilePath;
#	$CurrentBackupsetSoftPath = $backupsetSchFileSoftPath;
	#chmod $filePermission, $BackupsetFile;
	if(!backupTypeCheck()) {
		$relative = 1;
	}
} else {
	$taskType = "Manual";
	if(!defined(${ARGV[0]}) or ${ARGV[0]} ne 'dashboard'){
		if(getAccountConfStatus($confFilePath)){
			Common::sendFailureNotice($userName,'update_backup_progress',$taskType);
			exit(0);
		}
		else{
			if(getLoginStatus($pwdPath)){
				Common::sendFailureNotice($userName,'update_backup_progress',$taskType);
				exit(0);
			}
		}
	}
	backupTypeCheck();
#	$CurrentBackupsetSoftPath = $backupsetFileSoftPath;
}

if(${ARGV[0]} eq '--silent') {
	$AppConfig::displayHeader = 0;
	Common::isLoggedin() or Common::retreat(["\n", 'login_&_try_again']);
}

if (! checkIfEvsWorking($dedup)){
	print Constants->CONST->{'EvsProblem'}.$lineFeed if($taskType eq "Manual");
	traceLog("Invalid EVS binary found!", __FILE__, __LINE__);
	Common::sendFailureNotice($userName,'update_backup_progress',$taskType);
	exit 0;
}

#Getting working dir path and loading path to all other files
$jobRunningDir = "$usrProfilePath/$userName/Backup/DefaultBackupSet";
$AppConfig::jobRunningDir = $jobRunningDir; # Added by Senthil on Nov 26, 2018
if(!-d $jobRunningDir) {
	mkpath($jobRunningDir);
	chmod $filePermission, $jobRunningDir;
}
exit 1 if(!checkEvsStatus(Constants->CONST->{'BackupOp'}));

my $cutOffReached = checkArchiveStatus();

#Checking if another job is already in progress
$pidPath = "$jobRunningDir/pid.txt";
if (!pidAliveCheck($pidPath)) {
	$pidMsg = "$jobType job is already in progress. Please try again later.\n";
	print $pidMsg if($taskType eq "Manual");
	traceLog($pidMsg, __FILE__, __LINE__);
	exit 1;
}

#Loading global variables
$statusFilePath = "$jobRunningDir/STATUS_FILE";
$retryinfo = "$jobRunningDir/".$retryinfo;
my $failedfiles = $jobRunningDir."/".$failedFileName;
my $info_file = $jobRunningDir."/info_file";
$idevsOutputFile = "$jobRunningDir/output.txt";
$idevsErrorFile = "$jobRunningDir/error.txt";
my $fileForSize = "$jobRunningDir/TotalSizeFile";
$relativeFileset = $jobRunningDir."/".$relativeFileset;
$noRelativeFileset	= $jobRunningDir."/".$noRelativeFileset;
$filesOnly	= $jobRunningDir."/".$filesOnly;
#my $incSize = "$jobRunningDir/transferredFileSize.txt";
my $trfSizeAndCountFile = "$jobRunningDir/trfSizeAndCount.txt";
$excludeDirPath  = "$jobRunningDir/Excluded";
$excludedLogFilePath  = "$excludeDirPath/excludedItemsLog.txt";
my $utf8Files = $jobRunningDir."/utf8.txt_";
$errorDir = $jobRunningDir."/ERROR";
my $engineLockFile = $jobRunningDir.'/'.ENGINE_LOCKE_FILE;
my $progressDetailsFile = $jobRunningDir.$pathSeparator."PROGRESS_DETAILS";
my $jobCancelFile = $jobRunningDir.'/exitError.txt';
my $summaryFilePath = "$jobRunningDir/".Constants->CONST->{'fileDisplaySummary'};
my $minimalErrorRetry = $jobRunningDir.'/errorretry.min';

#Renaming the log file if backup process terminated improperly
Common::checkAndRenameFileWithStatus($jobRunningDir, lc($jobType));

# pre cleanup for all intermediate files and folders.
Common::removeItems([$relativeFileset.'*', $noRelativeFileset.'*', $filesOnly.'*', $info_file, $retryinfo, $errorDir, $statusFilePath.'*', $excludeDirPath, $failedfiles.'*', $progressDetailsFile.'*', $jobCancelFile, $summaryFilePath, $minimalErrorRetry]);
#Start creating required file/folder
if(!-d $errorDir) {
	mkdir($errorDir);
	chmod $filePermission, $errorDir;
}

if(!-d $excludeDirPath) {
	mkdir($excludeDirPath);
	chmod $filePermission, $excludeDirPath;
}

#my $encType = checkEncType($isScheduledJob); # This function has been called inside getOperationFile() function.
my $maximumAttemptMessage = '';
# Commented as per Deepak's instruction: Senthil
# my $serverAddress = verifyAndLoadServerAddr();
# if ($serverAddress == 0){
	# exit_cleanup($errStr);
# }

#createUpdateBWFile(); #Commented by Senthil: 13-Aug-2018
my $isEmpty = checkPreReq($BackupsetFile,$jobType,$taskType,'NOBACKUPDATA');
if($isEmpty and $silentBackupFlag == 0 and $ARGV[0] ne 'SCHEDULED') {
	unlink($pidPath);
	Common::loadNotifications() and
		Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'no_files_to_backup'}) and Common::saveNotifications();
	Common::retreat($errStr) ;
}
elsif (not $isEmpty and Common::loadNotifications() and
	(Common::getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'no_files_to_backup'})) {
		Common::setNotification('alert_status_update', 0) and Common::saveNotifications();
}

#Common::setUsername($userName) if (defined($userName) and $userName ne '');

createLogFiles("BACKUP");
createBackupTypeFile();

if (Common::loadAppPath() and Common::loadServicePath() and Common::loadNotifications()) {
	Common::setNotification('update_backup_progress', ((split("/", $outputFilePath))[-1]));
	Common::saveNotifications();
}

#versionDevDisplay() if ($silentBackupFlag == 0);
if ($isScheduledJob == 0 and $silentBackupFlag == 0){
	if ($dedup eq 'off'){
		emptyLocationsQueries();
	}elsif($dedup eq 'on'){
		print qq{Your Backup Location name is "}.$backupHost.qq{". $lineFeed};
	}
}
#if($dedup eq 'on'){
#	$deviceID = (split('#',$backupHost))[0];
#}
$location = (($dedup eq 'on') and $backupHost =~ /#/)?(split('#',$backupHost))[1]:$backupHost;
getCursorPos() if ($isScheduledJob == 0 and $silentBackupFlag == 0 and !$isEmpty and -e $pidPath);
#$mail_content_head = writeLogHeader($isScheduledJob);
$AppConfig::mailContentHead = writeLogHeader($isScheduledJob);

startBackup() if(!$isEmpty and !$cutOffReached and -e $pidPath);
exit_cleanup($errStr);

#****************************************************************************************************
# Subroutine Name         : startBackup
# Objective               : This function will fork a child process to generate backupset files and get
#							count of total files considered. Another forked process will perform main
#							backup operation of all the generated backupset files one by one.
# Added By				  :
# Modified By			  : Senthil Pandian
#*****************************************************************************************************/
sub startBackup {
	loadFullExclude();
	loadPartialExclude();
	loadRegexExclude();

	$generateFilesPid = fork();

	if(!defined $generateFilesPid) {
		Common::traceLog(Constants->CONST->{'ForkErr'});
		$errStr = "Unable to start generateBackupsetFiles operation";
		return;
	}

	generateBackupsetFiles() if($generateFilesPid == 0);

	if($isScheduledJob == 0 and !$silentBackupFlag){
		$displayProgressBarPid = fork();

		if(!defined $displayProgressBarPid) {
			Common::traceLog(Constants->CONST->{'ForkErr'});
			$errStr = "Unable to start generateBackupsetFiles operation";
			return;
		}

		if($displayProgressBarPid == 0) {
			$pidOperationFlag = "DisplayProgress";
			while(1){
				displayProgressBar($progressDetailsFile);
				if (!-e $pidPath) {
					last;
				}
				#select(undef, undef, undef, 0.1);
				Common::sleepForMilliSec(100); # Sleep for 100 milliseconds
			}
			displayProgressBar($progressDetailsFile,Common::getTotalSize($fileForSize));
			exit(0);
		}
	}

	close(FD_WRITE);

	open(my $handle, '>', $engineLockFile) or Common::traceLog("Could not open file '$engineLockFile' $!");
	close $handle;
	chmod $filePermission, $engineLockFile;

	my $exec_cores = getSystemCpuCores();
START:
	if(!open(FD_READ, "<", $info_file)) {
		$errStr = Constants->CONST->{'FileOpnErr'}." info_file in startBackup: $info_file to read, Reason:$!";
		return;
	}

	my $lastFlag = 0;

	while (1) {
		if(!-e $pidPath){
			last;
		}
		my $backupPid = undef;
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
			$lastFlag = 1;
			$line = "";
			last;
		}

		$isEngineRunning = isEngineRunning($pidPath.'_'.$engineID);
		if (!$isEngineRunning) {
			while(1){
				last	if(!-e $pidPath or !isAnyEngineRunning($engineLockFile));

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

	Common::waitForEnginesToFinish(\@BackupForkchilds,$engineLockFile);
	close FD_READ;
	$nonExistsCount    = Common::readInfoFile('FAILEDCOUNT');
	$noPermissionCount = Common::readInfoFile('DENIEDCOUNT');
	$missingCount      = Common::readInfoFile('MISSINGCOUNT');

	waitpid($generateFilesPid,0);
	undef @linesStatusFile;

	if($totalFiles == 0 or $totalFiles !~ /\d+/) {
		$totalFiles    = Common::readInfoFile('TOTALFILES');
		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			traceLog("Unable to get total files count \n", __FILE__, __LINE__);
		}
	}


	if(-s $retryinfo > 0 && -e $pidPath &&
		((-f $minimalErrorRetry) ? ($retrycount <= $minRetryAttempts) : ($retrycount <= $maxNumRetryAttempts)) && $exitStatus == 0) {
		if ((-f $minimalErrorRetry) ? ($retrycount >= $minRetryAttempts) : ($retrycount >= $maxNumRetryAttempts)) {
			for (my $i=1; $i<= $totalEngineBackup; $i++) {
				if (-f $statusFilePath."_".$i  and  -s $statusFilePath."_".$i>0){
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
		if(!open(INFO, ">>",$info_file)){
			$errStr = Constants->CONST->{'FileOpnErr'}." info_file in startBackup : $info_file, Reason $!".$lineFeed;
			return;
		}
		print INFO "TOTALFILES $totalFiles\n";
		print INFO "FAILEDCOUNT $nonExistsCount\n";
		print INFO "DENIEDCOUNT $noPermissionCount\n";
		print INFO "MISSINGCOUNT $missingCount\n";
		close INFO;
		chmod $filePermission, $info_file;
		unlink($minimalErrorRetry) if (-f $minimalErrorRetry);
		traceLog("retrycount:$retrycount", __FILE__, __LINE__);
		$engineID = 1;
		goto START;
	}
}

#****************************************************************************************************
# Subroutine Name         : generateBackupsetFiles.
# Objective               : This function will generate backupset files.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub generateBackupsetFiles {
	$pidOperationFlag = "GenerateFile";
	if(!open(BACKUPSETFILE_HANDLE, $BackupsetFile)) {
		traceLog(Constants->CONST->{'BckFileOpnErr'}." $BackupsetFile, Reason: $!. $lineFeed", __FILE__, __LINE__);
		goto GENLAST;
	}
	@BackupArray = <BACKUPSETFILE_HANDLE>;
	close(BACKUPSETFILE_HANDLE);
	my $traceExist = $errorDir."/traceExist.txt";
	if(!open(TRACEERRORFILE, ">>", $traceExist)) {
		traceLog(Constants->CONST->{'FileOpnErr'}." $traceExist, Reason: $!. $lineFeed", __FILE__, __LINE__);
	}
	chmod $filePermission, $traceExist;

	my $permissionError = $errorDir."/permissionError.txt";
	if(!open(TRACEPERMISSIONERRORFILE, ">>", $permissionError)) {
		traceLog(Constants->CONST->{'FileOpnErr'}." $permissionError, Reason: $!. $lineFeed", __FILE__, __LINE__);
	}
	chmod $filePermission, $permissionError;

	# require to open excludedItems file to log excluded details
	if(!open(EXCLUDEDFILE, ">", $excludedLogFilePath)){
		print Constants->CONST->{'CreateFail'}." $excludedLogFilePath, Reason:$!";
		traceLog(Constants->CONST->{'CreateFail'}." $excludedLogFilePath, Reason:$!", __FILE__, __LINE__) and die;
	}
	chmod $filePermission, $excludedLogFilePath;

	$filesonlycount = 0;
	$excludedFileIndex = 1;
	my $j =0;
	chomp(@BackupArray);
	@BackupArray = uniqueData(@BackupArray);
	foreach my $item (@BackupArray) {
		if(!-e $pidPath){
			last;
		}
		$item =~ s/^[\/]+|[\/]+$/\//g; #Removing "/" if more than one found at beginning/end
		if($item =~ m/^$/) {
			next;
		}
		elsif($item =~ m/^[\s\t]+$/) {
			next;
		}
		elsif ($item eq "." or $item eq "..") {
			next;
		}
		elsif( -l $item # File is a symbolic link #
			 or -p $item # File is a named pipe #
			 or -S $item # File is a socket #
			 or -b $item # File is a block special file #
			 or -c $item )# File is a character special file #
		#	 or -t $item ) # Filehandle is opened to a tty #
		{
			print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$item]. Reason: Not a regular file/folder.$lineFeed";
			$excludedCount++;
			if($excludedCount == EXCLUDED_MAX_COUNT) {
				$excludedCount = 0;
				createExcludedLogFile30k();
			}
			next;
		}
		Chomp(\$item);
		if($item ne "/" && substr($item, -1, 1) eq "/") {
			chop($item);
		}

		if(checkForExclude($item)) {
			next;
		}
		if(-d $item) {
			if($relative == 0) {
				$noRelIndex++;
				$BackupsetFile_new = $noRelativeFileset."$noRelIndex";
				$filecount = 0;
				$a = rindex ($item, '/');
				$source[$noRelIndex] = substr($item,0,$a);
				if($source[$noRelIndex] eq "") {
					$source[$noRelIndex] = "/";
				}
				$current_source = $source[$noRelIndex];

				if(!open $filehandle, ">>", $BackupsetFile_new) {
					traceLog("cannot open $BackupsetFile_new to write ", __FILE__, __LINE__);
					goto GENLAST;
				}
				chmod $filePermission, $BackupsetFile_new;
			}

			if(!enumerate($item)){
				goto GENLAST;
			}

			if($relative == 0 && $filecount>0) {
				autoflush FD_WRITE;
				close $filehandle;
				#print FD_WRITE "$BackupsetFile_new ".RELATIVE." $current_source\n";
				print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
			}
		}
		else {
			if (!-r $item) {
				#write into error
				my $reason = $!;
				if ($reason =~ /Inappropriate ioctl for device/ or $reason =~ /Permission denied/) {
					$noPermissionCount++;
					print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: Permission denied".$lineFeed;
				}
				else {
					$totalFiles++;
					$nonExistsCount++;
					$missingCount++ if($reason =~ /No such file or directory/);
					print TRACEERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $reason".$lineFeed;
				}
				next;
			}

			$totalFiles++;
			$totalSize += -s $item;
			print NEWFILE $item.$lineFeed;
			$current_source = "/";

			if($relative == 0) {
				$filesonlycount++;
				$filecount = $filesonlycount;
			}
			else {
				$filecount++;
			}

			if($filecount == FILE_MAX_COUNT) {
				$filesonlycount = 0;
				if(!createBackupSetFiles1k("FILESONLY")){
					goto GENLAST;
				}
			}
		}
	}

	if($relative == 1 && $filecount > 0) {
		autoflush FD_WRITE;
		print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
	} elsif($filesonlycount >0) {
		$current_source = "/";
		autoflush FD_WRITE;
		print FD_WRITE "$current_source' '".NORELATIVE."' '$filesOnly\n";
	}

GENLAST:
	autoflush FD_WRITE;
	print FD_WRITE "TOTALFILES $totalFiles\n";
	print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
	print FD_WRITE "DENIEDCOUNT $noPermissionCount\n";
	print FD_WRITE "MISSINGCOUNT $missingCount\n";
	close FD_WRITE;
	close NEWFILE;
	$pidOperationFlag = "generateListFinish";
	close INFO;

	open FILESIZE, ">$fileForSize" or traceLog(Constants->CONST->{'FileOpnErr'}." $fileForSize. Reason: $!\n", __FILE__, __LINE__);
	print FILESIZE "$totalSize";
	close FILESIZE;
	chmod $filePermission, $fileForSize;

	close(TRACEERRORFILE);
	close(TRACEPERMISSIONERRORFILE);
	close(EXCLUDEDFILE);
	exit 0;
}
#****************************************************************************************************
# Subroutine Name         : enumerate.
# Objective               : This function will list files recursively.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub enumerate {
	my $item  = $_[0];
	my $retVal = 1;

	if (substr($item, -1, 1) ne "/") {
		$item .= "/";
	}
	if(opendir(DIR, $item)) {
		foreach my $file (readdir(DIR))  {
			if( !-e $pidPath) {
				last;
			}
			my $temp = $item.$file;
			chomp($temp);
			if($file =~ m/^$/) {
				next;
			}
			elsif($file =~ m/^[\s\t]+$/) {
				next;
			}
			if ( $file eq "." or $file eq "..") {
				next;
			}
			elsif( -l $temp # File is a symbolic link #
			 or -p $temp # File is a named pipe #
			 or -S $temp # File is a socket #
			 or -b $temp # File is a block special file #
			 or -c $temp )# File is a character special file #
			 #or -t $temp ) # Filehandle is opened to a tty #
			{
				print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$temp]. Reason: Not a regular file/folder.$lineFeed";
				$excludedCount++;
				if($excludedCount == EXCLUDED_MAX_COUNT) {
					$excludedCount = 0;
					createExcludedLogFile30k();
				}
				next;
			}

			if(checkForExclude($temp)) {
				next;
			}

			if(-d $temp){
				if(!enumerate($temp)){
					$retVal = 0;
					last;
				}
			}
			else {
				if (!-r $temp) {
					#write into error
					my $reason = $!;
					if ($reason =~ /Inappropriate ioctl for device/ or $reason =~ /Permission denied/){
						$noPermissionCount++;
						print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$temp]. Reason: Permission denied".$lineFeed;
					} else {
						$totalFiles++;
						$nonExistsCount++;
						$missingCount++ if($reason =~ /No such file or directory/);
						print TRACEERRORFILE "[".(localtime)."] [FAILED] [$temp]. Reason: $reason".$lineFeed;
					}
					next;
				}

				$totalFiles++;
				$totalSize += -s $temp;
				if($relative == 0) {
					$item_orig = $item;
					if($current_source ne "/") {
						$item_orig =~ s/$current_source//;
					}
					$temp = $item_orig.$file;
					print $filehandle $temp.$lineFeed;
				}
				else {
					$current_source = "/";
					print NEWFILE $temp.$lineFeed;
					$BackupsetFileTmp = $relativeFileset;
				}

				$filecount++;

				if($filecount == FILE_MAX_COUNT) {
					if(!createBackupSetFiles1k()){
						$retVal = 0;
						last;
					}
				}
			}
		}
		closedir(DIR);
	}
	else {
		#traceLog("Could not open Dir $item, Reason:$!", __FILE__, __LINE__);
		my $reason = $!;
		if($reason =~ /Permission denied/){
			$noPermissionCount++;
			print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $reason".$lineFeed;
		} else {
			$totalFiles++;
			$nonExistsCount++;
			$missingCount++ if($reason =~ /No such file or directory/);
			print TRACEERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $reason".$lineFeed;
		}
	}
	if($excludedCount == EXCLUDED_MAX_COUNT) {
		$excludedCount = 0;
		createExcludedLogFile30k();
	}
	return $retVal;
}

#****************************************************************************************************
# Subroutine Name		: cancelSubRoutine
# Objective				: This subroutine gets call if user cancel the execution of script. It will do all require cleanup before exiting.
# Added By				: Arnab Gupta
# Modified By			: Dhritikana, Sabin Cheruvattil
#*****************************************************************************************************/
sub cancelSubRoutine {
	if($pidOperationFlag eq "GenerateFile") {
		open FD_WRITE, ">>", $info_file or (print Constants->CONST->{'FileOpnErr'}."info_file in cancelSubRoutine: $info_file to write, Reason:$!"); # die handle?
		autoflush FD_WRITE;
		print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
		print FD_WRITE "DENIEDCOUNT $noPermissionCount\n";
		print FD_WRITE "MISSINGCOUNT $missingCount\n";
		close(FD_WRITE);
		close NEWFILE;
		exit 0;
	}

	exit(0) if($pidOperationFlag eq "DisplayProgress");

	if($pidOperationFlag eq "main") {
		my $evsCmd = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$backupUtfFile\'";
		$evsCmd = Common::updateLocaleCmd($evsCmd);
		$evsRunning = `$evsCmd`;

		@evsRunningArr = split("\n", $evsRunning);
		my $arrayData = ($machineInfo eq 'freebsd')? 1 : 3;

		foreach(@evsRunningArr) {
			next if($_ =~ /$evsCmd|grep/);

			my $pid = (split(/[\s\t]+/, $_))[$arrayData];
			$scriptTerm = system(Common::updateLocaleCmd("kill -9 $pid"));

			if(defined($scriptTerm)) {
				if($scriptTerm != 0 && $scriptTerm ne "") {
					Common::traceLog(Constants->CONST->{'KilFail'} . " Backup");
				}
			}
		}

		waitpid($generateFilesPid, 0) if($generateFilesPid);
		waitpid($displayProgressBarPid, 0) if($displayProgressBarPid);
		Common::waitForChildProcess();

		if(($totalFiles == 0 or $totalFiles !~ /\d+/) and (-s $info_file)) {
			my $fileCountCmd = "cat '$info_file' | grep \"^TOTALFILES\"";
			$fileCountCmd = Common::updateLocaleCmd($fileCountCmd);
			$totalFiles = `$fileCountCmd`;
			$totalFiles =~ s/TOTALFILES//;
		}

		Common::traceLog("Unable to get total files count") if($totalFiles == 0 or $totalFiles !~ /\d+/);

		if($nonExistsCount == 0) {
			my $nonExistCheckCmd = "cat '$info_file' | grep \"^FAILEDCOUNT\"";
			$nonExistCheckCmd = Common::updateLocaleCmd($nonExistCheckCmd);
			$nonExistsCount = `$nonExistCheckCmd`;
			$nonExistsCount =~ s/FAILEDCOUNT//;
		}

		#waitpid($pid_OutputProcess, 0) if($pid_OutputProcess);
		$errStr = Constants->CONST->{'operationFailUser'} unless($errStr);
		exit_cleanup($errStr);
	}
}

#****************************************************************************************************
# Subroutine Name : loadFullExclude.
# Objective       : This function will load FullExcludePaths to FullExcludeHash.
# Added By        : Dhritikana
# Modified By     : Yogesh Kumar
#*****************************************************************************************************/
sub loadFullExclude {
	my @excludeArray;
	#read full path exclude file and prepare a hash for it
	if(-e "$excludeFullPath.info" and 0 < -s "$excludeFullPath.info") {
		if(!open(EXFH, "$excludeFullPath.info")){
			$errStr = Constants->CONST->{'ExclFileOpnErr'}." $excludeFullPath.info. Reason:$!";
			traceLog("$errStr\n", __FILE__, __LINE__);
			return;
		}

		@excludeArray = grep { !/^\s*$/ } <EXFH>;
		close EXFH;
	}

	push @excludeArray, $currentDir;
	push @excludeArray, 'enabled';
	if(-l $idriveServicePath){
		my $sp = Common::getAbsPath($idriveServicePath) or Common::retreat('no_such_directory_try_again');
		push @excludeArray, $sp;
		push @excludeArray, 'enabled';
	} else {
		push @excludeArray, $idriveServicePath;
		push @excludeArray, 'enabled';
	}
	my @qFullExArr; # What is the use of this variable.
	chomp @excludeArray;

	for (my $i=0; $i<=$#excludeArray; $i++) {
		if ($excludeArray[$i+1] eq 'enabled') {
			if(substr($excludeArray[$i], -1, 1) eq "/") {
				chop($excludeArray[$i]);
			}
			$backupExcludeHash{$excludeArray[$i]} = 1;
			push(@qFullExArr, "^".quotemeta($excludeArray[$i]).'\/');
		}
		$i++;
	}
	$fullStr = join("\n", @qFullExArr);
	chomp($fullStr);
	$fullStr =~ s/\n/|/g;#First we join with '\n' and then replacing with '|'?
}

#****************************************************************************************************
# Subroutine Name : loadPartialExclude.
# Objective       : This function will load Partial Exclude string from PartialExclude File.
# Added By        : Dhritikana
# Modified By     : Yogesh Kumar
#*****************************************************************************************************/
sub loadPartialExclude {
	my (@excludeParArray, @qParExArr);

	#read partial path exclude file and prepare a partial match pattern
	if (-f "$excludePartialPath.info" and !-z "$excludePartialPath.info") {
		if (!open(EPF, "$excludePartialPath.info")) {
			$errStr = Constants->CONST->{'ExclFileOpnErr'}." $excludePartialPath.info. Reason:$!";
			traceLog("$errStr\n", __FILE__, __LINE__);
			return;
		}

		@excludeParArray = grep { !/^\s*$/ } <EPF>;
		close EPF;

		chomp(@excludeParArray);
		for(my $i = 0; $i <= $#excludeParArray; $i++) {
			if ($excludeParArray[$i+1] eq 'enabled') {
				$excludeParArray[$i] =~ s/[\s\t]+$//;
				push(@qParExArr, quotemeta($excludeParArray[$i]));
			}
			$i++;
		}

		# $parStr = join("\n", @qParExArr);
		# chomp($parStr);
		# $parStr =~ s/\n/|/g;
	}
	push(@qParExArr, quotemeta("/.")) unless(Common::getUserConfiguration('SHOWHIDDEN'));
	if(scalar(@qParExArr)>0){
		$parStr = join("|", @qParExArr);
		chomp($parStr);
	}
}

#****************************************************************************************************
# Subroutine Name : loadRegexExclude.
# Objective       : This function will load Regular Expression Exclude string from RegexExlude File.
# Added By        : Dhritikana
# Modified By     : Yogesh Kumar
#*****************************************************************************************************/
sub loadRegexExclude {
	#read regex path exclude file and find a regex match pattern
	if (-f "$regexExcludePath.info" and !-z "$regexExcludePath.info") {
		if(!open(RPF, "$regexExcludePath.info")) {
			$errStr = Constants->CONST->{'ExclFileOpnErr'}." $regexExcludePath.info. Reason:$!";
			traceLog("$errStr\n", __FILE__, __LINE__);
			return;
		}

		my @tmp;
		@excludeRegexArray = grep { !/^\s*$/ } <RPF>;
		close RPF;

		if(!scalar(@excludeRegexArray)) {
			$regexStr = undef;
		}
		else {
			for(my $i = 0; $i <= $#excludeRegexArray; $i++) {
				chomp($excludeRegexArray[$i+1]);
				if ($excludeRegexArray[$i+1] eq 'enabled') {
					my $a = $excludeRegexArray[$i];
					chomp($a);
					$b = eval { qr/$a/ };
					if ($@) {
						print OUTFILE " Invalid regex: $a";
						traceLog("Invalid regex: $a\n", __FILE__, __LINE__);
					}
					elsif($a) {
						push @tmp, $a;
					}
				}
				$i++;
			}
			$regexStr = join("\n", @tmp);
			chomp($regexStr);
			$regexStr =~ s/\n/|/g;
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : exit_cleanup.
# Objective               : This function will execute the major functions required at the time of exit
# Added By                : Deepak Chaurasia
# Modified By 			  : Dhritikana
# Mofidied By             : Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub exit_cleanup {
	if($silentBackupFlag == 0 and $taskType eq 'Manual'){
		system('stty', 'echo');
		system("tput sgr0");
	}

	unless($isEmpty){
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','DENIED_COUNT_FILES','MISSED_FILES_COUNT','TOTAL_TRANSFERRED_SIZE','EXIT_FLAG_INDEX');
		($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount, $transferredFileSize, $exit_flag) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
		chomp($exit_flag);
		if($errStr eq "" and -e $errorFilePath) {
			open ERR, "<$errorFilePath" or traceLog(Constants->CONST->{'FileOpnErr'}."errorFilePath in exit_cleanup: $errorFilePath, Reason: $!".$lineFeed, __FILE__, __LINE__);
			$errStr .= <ERR>;
			close(ERR);
			chomp($errStr);
		}

		if(!-e $pidPath or $exit_flag) {
			$cancelFlag = 1;

			# In childprocess, if we exit due to some exit scenario, then this exit_flag will be true with error msg
			@exit = split("-",$exit_flag,2);
			if (!$exit[0] and $errStr eq '') {
				if ($isScheduledJob == 1) {
					$errStr = Constants->CONST->{'operationFailCutoff'};
					if (!-e Common::getServicePath()) {
						$errStr = Constants->CONST->{'operationFailUser'};
					}
				}
				elsif($isScheduledJob == 0) {
					$errStr = Constants->CONST->{'operationFailUser'};
				}

				if ($errStr eq Constants->CONST->{'operationFailCutoff'}) {
					Common::loadNotifications() and
						Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'scheduled_cut_off'}) and Common::saveNotifications();
				}
			}
			else{
				if($exit[1] ne ""){
					$errStr = $exit[1];
					Common::checkAndUpdateAccStatError($userName, $errStr);
					#Below section has been added to provide user friendly message and clear instruction in case of password mismatch or encryption verification failed.
					#In this case we are removing the IDPWD file.So that user can login and recreate these files with valid credential.
					if ($errStr =~ /password mismatch|encryption verification failed/i){
						$errStr = $errStr.' '.Constants->CONST->{loginAccount}.$lineFeed;
						unlink($pwdPath);
						if($taskType == "Scheduled"){
							$pwdPath =~ s/_SCH$//g;
							unlink($pwdPath);
						}
					} elsif($errStr =~ /failed to get the device information|Invalid device id/i){
						$errStr = $errStr.' '.Constants->CONST->{backupLocationConfigAgain}.$lineFeed;
					} else {
						$errStr = Common::checkErrorAndLogout($errStr);
					}
				}
			}
		}
	}

	unlink($pidPath);
	waitpid($displayProgressBarPid, 0) if ($displayProgressBarPid);
	wait();
	writeOperationSummary(Constants->CONST->{'BackupOp'}, $cancelFlag, $transferredFileSize);

	my $subjectLine = getOpStatusNeSubLine();
	unlink($retryinfo);
	unlink($fileForSize);
	#unlink($incSize);
	unlink($trfSizeAndCountFile);
	unlink($info_file);
	unlink($jobCancelFile);
	#restoreBackupsetFileConfiguration();

	rmtree($errorDir) if(-d $errorDir);

	if (-e $outputFilePath and -s $outputFilePath > 0){
		my $finalOutFile = $outputFilePath;
		$finalOutFile =~ s/_Running_/_$status\_/;
		move($outputFilePath, $finalOutFile);

		if (Common::loadNotifications()) {
			Common::setNotification('update_backup_progress', ((split("/", $finalOutFile))[-1]));
			Common::setNotification('get_logs') and Common::saveNotifications();
		}

		$outputFilePath = $finalOutFile;
		$finalSummary .= Constants->CONST->{moreDetailsReferLog}.qq(\n); #Concat log file path with job summary. To access both at once while displaying the summary and log file location.
		$finalSummary .= "\n".$status."\n";

		if ($errStr ne "" &&  $status ne "Success") {
			$finalSummary .= $errStr;
		}

		#It is a generic function used to write content to file.
		#if ($silentBackupFlag == 0){
			writeToFile($summaryFilePath,$finalSummary);
			chmod $filePermission, $summaryFilePath;
		#}

		if ($taskType eq "Manual" and $silentBackupFlag == 0){
			displayProgressBar($progressDetailsFile,Common::getTotalSize($fileForSize)) unless($isEmpty);
			displayFinalSummary('Backup Job',$summaryFilePath);
		}
		#Above function display summary on stdout once backup job has completed.
		Common::saveLog($finalOutFile);
	}
	if ($isEmpty){
		Common::sendMail({
				'serviceType' => $taskType,
				'jobType' => '',
				'subject' => $subjectLine,
				'jobStatus' => lc($status),
				'errorMsg' => 'NOBACKUPDATA'
			});
	}
	else {
		Common::sendMail({
				'serviceType' => $taskType,
				'jobType' => '',
				'subject' => $subjectLine,
				'jobStatus' => lc($status)
			});
	}
#	terminateStatusRetrievalScript($summaryFilePath) if ($taskType eq "Scheduled"); #Commented by Senthil
#	unlink($progressDetailsFilePath);
	$operationsfile = $jobRunningDir.'/operationsfile.txt';
	my $doBackupOperationErrorFile = "$jobRunningDir/doBackuperror.txt_";
	Common::removeItems([$idevsErrorFile.'*', $idevsOutputFile.'*', $statusFilePath.'*', $utf8Files.'*', $operationsfile.'*', $doBackupOperationErrorFile.'*', $relativeFileset.'*', $noRelativeFileset.'*', $filesOnly.'*', $failedfiles.'*', $pidPath.'*', $errorFilePath, $minimalErrorRetry]);

	unlink($engineLockFile);
	if(defined(${ARGV[0]}) && ${ARGV[0]} eq 'immediate') {
		Common::loadCrontab();
		Common::updateCronTabToDefaultVal("backup") if(Common::getCrontab('backup', 'default_backupset', '{settings}{frequency}') eq 'immediate');
	}

	if ($successFiles > 0){#some file has been backed up during the process, getQuota call is done to calculate the fresh quota.
		my $childProc = fork();
		if ($childProc == 0){
			getQuota();
			exit(0);
		}
	}
	exit 0;
}

#****************************************************************************************************
# Subroutine Name         : checkForExclude.
# Objective               : This function will exclude the files that matched with exclude and partial list
# Added By                : Pooja Havaldar
# Modified By			  : Dhritikana
#*****************************************************************************************************/
sub checkForExclude {
	my $element = $_[0];
	my $returnvalue = 0;
	###$element the last slash needs to be removed before comparing with hash for full exclude
	if(exists $backupExcludeHash{$element} or $element =~ m/$fullStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. Reason: Full path excluded item.$lineFeed";
		$excludedCount++;
		$returnvalue = 1;
	} elsif($parStr ne "" and $element =~ m/$parStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. Reason: Partial path excluded item.$lineFeed";
		$excludedCount++;
		$returnvalue = 1;
	} elsif($regexStr ne "" and $element =~ m/$regexStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. Reason: Regex path excluded item.$lineFeed";
		$excludedCount++;
		$returnvalue = 1;
	}
	if($excludedCount == EXCLUDED_MAX_COUNT) {
		$excludedCount = 0;
		createExcludedLogFile30k();
	}

	return $returnvalue;
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
			#print FD_WRITE "$BackupsetFile_Only ".NORELATIVE." $current_source\n";
			print FD_WRITE "$current_source' '".NORELATIVE."' '$BackupsetFile_Only\n";
			$BackupsetFile_Only =  $filesOnly."_".$filesOnlyCount;
			close NEWFILE;
			if(!open NEWFILE, ">", $BackupsetFile_Only) {
				traceLog(Constants->CONST->{'FileOpnErr'}."filesOnly in 1k: $filesOnly to write, Reason: $!. $lineFeed", __FILE__, __LINE__);
				return 0;
			}
			chmod $filePermission, $BackupsetFile_Only;
		}
		else
		{
			#print FD_WRITE "$BackupsetFile_new#".RELATIVE."#$current_source\n";
			print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
			# traceLog("in NORELATIVE BackupsetFile_new = $BackupsetFile_new and BackupsetFileTmp = $BackupsetFileTmp");
			$BackupsetFile_new = $noRelativeFileset."$noRelIndex"."_$Backupfilecount";

			close $filehandle;
			if(!open $filehandle, ">", $BackupsetFile_new) {
				traceLog(Constants->CONST->{'FileOpnErr'}."BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!. $lineFeed", __FILE__, __LINE__);
				return 0;
			}
			chmod $filePermission, $BackupsetFile_new;
		}
	}
	else {
		#print FD_WRITE "$BackupsetFile_new ".RELATIVE." $current_source\n";
		print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
		$BackupsetFile_new = $relativeFileset."_$Backupfilecount";

		close NEWFILE;
		if(!open NEWFILE, ">", $BackupsetFile_new){
			traceLog(Constants->CONST->{'FileOpnErr'}."BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!. $lineFeed", __FILE__, __LINE__);
			return 0;
		}
		chmod $filePermission, $BackupsetFile_new;
	}

	autoflush FD_WRITE;
	$filecount = 0;

	if($Backupfilecount%15 == 0){
		sleep(1);
	}
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
	my $parameters   = $_[0];
	my $scheduleFlag = $_[1];
	my $operationEngineId = $_[2];
	my $retry_failedfiles_index = $_[3];
	my $doBackupOperationErrorFile = "$jobRunningDir/doBackuperror.txt_".$operationEngineId;
	@parameter_list = split /\' \'/,$parameters,3;
	$backupUtfFile = getOperationFile(Constants->CONST->{'BackupOp'}, $parameter_list[2] ,$parameter_list[1] ,$parameter_list[0],$operationEngineId);
	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	if(!flock($startPidFileLock, 1)){
		traceLog("Failed to lock engine file", __FILE__, __LINE__);
		return 0;
	}

	Common::fileWrite($pidPath.'_evs_'.$operationEngineId, 1); #Added for Harish_2.19_7_7, Harish_2.19_6_7
	open(my $engineFp, ">>", $pidPath.'_'.$operationEngineId) or return 0;
	if(!flock($engineFp, 2)){
		print "Unable to lock \n";
		return 0;
	}

	if(!$backupUtfFile) {
		traceLog("$errStr", __FILE__, __LINE__);
		return 0;
	}

	my $tmpbackupUtfFile = $backupUtfFile;
	$tmpbackupUtfFile =~ s/\'/\'\\''/g;

	my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
	$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;

	# EVS command to execute for backup
	$idevsutilCommandLine = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmpbackupUtfFile\'";

	my $backupPid = fork();
	if(!defined $backupPid) {
		$errStr = Constants->CONST->{'ForkErr'}.$whiteSpace.Constants->CONST->{"EvsChild"}.$lineFeed;
		return BACKUP_PID_FAIL;
	}

	if($backupPid == 0) {
		$pidOperationFlag = 'dobackup';
		if(-e $pidPath) {
			system(Common::updateLocaleCmd($idevsutilCommandLine." > /dev/null 2>'$doBackupOperationErrorFile'"));
			if(-e $doBackupOperationErrorFile && -s $doBackupOperationErrorFile) {
				my $error = Common::getFileContents($doBackupOperationErrorFile);
				if($error ne '' and $error !~ /no version information available/) {
					$errStr = Constants->CONST->{'DoBckOpErr'}.Constants->CONST->{'ChldFailMsg'};
					traceLog("$errStr", __FILE__, __LINE__);
					traceLog("Child Launch Error: $error", __FILE__, __LINE__);
					if (open(ERRORFILE, ">> $errorFilePath"))
					{
						autoflush ERRORFILE;
						print ERRORFILE $errStr;
						close ERRORFILE;
						chmod $filePermission, $errorFilePath;
					}
					else {
						traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}."errorFilePath in doBackupOperation:".$errorFilePath.", Reason:$! $lineFeed", __FILE__, __LINE__);
					}
				}
			}
			Common::removeItems($doBackupOperationErrorFile);
			if(open OFH, ">>", $idevsOutputFile."_".$operationEngineId) {
				print OFH "\nCHILD_PROCESS_COMPLETED\n";
				close OFH;
				chmod $filePermission, $idevsOutputFile."_".$operationEngineId;
			}
			else {
				print Constants->CONST->{'FileOpnErr'}." $outputFilePath. Reason: $!";
				traceLog(Constants->CONST->{'FileOpnErr'}." outputFilePath in doBackupOperation: $outputFilePath. Reason: $!", __FILE__, __LINE__);
				return 0;
			}
		}
		exit 1;
	}

	exit(1) if(!-e $pidPath);

	#$isLocalBackup = 0;
	$workingDir = $currentDir;
	$workingDir =~ s/\'/\'\\''/g;
	my $tmpoutputFilePath = $outputFilePath;
	$tmpoutputFilePath =~ s/\'/\'\\''/g;
	my $TmpBackupSetFile = $parameter_list[2];
	$TmpBackupSetFile =~ s/\'/\'\\''/g;
	my $TmpSource = $parameter_list[0];
	$TmpSource =~ s/\'/\'\\''/g;
	my $tmp_jobRunningDir = $jobRunningDir;
	$tmp_jobRunningDir =~ s/\'/\'\\''/g;
	my $tmpBackupHost = $backupHost;
	$tmpBackupHost =~ s/\'/\'\\''/g;
	#my $execString = Common::getStringConstant('support_file_exec_string');
	$fileChildProcessPath = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
#		$ENV{'OPERATION_PARAM'}=join('::',($tmp_jobRunningDir,$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$curLines,$progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$errorDevNull));
	my @param = join ("\n",('BACKUP_OPERATION',$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$scheduleFlag,$operationEngineId));
	writeParamToFile("$tmp_jobRunningDir/operationsfile.txt_".$operationEngineId,@param);
	$cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\' \'$operationEngineId\' \'$retry_failedfiles_index\'";
	$pidOperationFlag = 'parseop';
	$cmd = Common::updateLocaleCmd("$cmd");
	$out = system("$cmd 2>/dev/null &");
	waitpid($backupPid, 0) if($backupPid);

	unlink($pidPath.'_evs_'.$operationEngineId);
	Common::waitForChildProcess($pidPath.'_proc_'.$operationEngineId);
	unlink($pidPath.'_'.$operationEngineId);
	updateServerAddr();

	unlink($parameter_list[2]);
	unlink($idevsOutputFile.'_'.$operationEngineId);
	flock($startPidFileLock, 8);
	flock($engineFp, 8);

	return 0 if(-e $errorFilePath && -s $errorFilePath);

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
# Subroutine Name         : restoreBackupsetFileConfiguration.
# Objective               : This subroutine moves the BackupsetFile to the original configuration
# Added By                : Dhritikana
#*****************************************************************************************************/
sub restoreBackupsetFileConfiguration
{
	if($relativeFileset ne "") {
		unlink <"$relativeFileset"*>;
	}
	if($noRelativeFileset ne "") {
		unlink <"$noRelativeFileset"*>;
	}
	if($filesOnly ne "") {
		unlink <"$filesOnly"*>;
	}
	if($failedfiles ne "") {
		unlink <"$failedfiles"*>;
	}
	unlink "$info_file";
}

#*******************************************************************************************************
# Subroutine Name         :	updateServerAddr
# Objective               :	handling wrong server address error msg
# Added By                : Dhritikana, 
# Modified By			  : Sabin Cheruvattil
#********************************************************************************************************
sub updateServerAddr {
	my $tempErrorFileSize = -s $idevsErrorFile;
	if($tempErrorFileSize > 0) {
		my $errorPatternServerAddr = "unauthorized user";
		open EVSERROR, "<", $idevsErrorFile or traceLog("\n Failed to open error.txt\n", __FILE__, __LINE__);
		$errorContent = <EVSERROR>;
		close EVSERROR;

		if($errorContent =~ m/$errorPatternServerAddr/){
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
		traceLog("\n $errStr\n", __FILE__, __LINE__) and die;
	}
	chmod $filePermission, $info_file;

	#Backupset File name for mirror path
	if($relative != 0) {
		$BackupsetFile_new =  $relativeFileset;
		if(!open NEWFILE, ">>", $BackupsetFile_new) {
			traceLog(Constants->CONST->{'FileOpnErr'}." relativeFileset in createBackupTypeFile $relativeFileset to write, Reason:$!. $lineFeed", __FILE__, __LINE__) and die;
		}
		chmod $filePermission, $BackupsetFile_new;
	}
	else {
		#Backupset File Name only for files
		$BackupsetFile_Only = $filesOnly;
		if(!open NEWFILE, ">>", $BackupsetFile_Only) {
			traceLog(Constants->CONST->{'FileOpnErr'}." filesOnly in createBackupTypeFile: $filesOnly to write, Reason:$!. $lineFeed", __FILE__, __LINE__) and die;
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

	for(my $i=1; $i<= $totalEngineBackup; $i++){
		if (-e $statusFilePath."_".$i  and  -s $statusFilePath."_".$i>0){
			$curFailedCount = $curFailedCount+getParameterValueFromStatusFile('ERROR_COUNT_FILES',$i);
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
				#traceLog("Delaying backup operation. Reason: $runningJobName archive cleanup is in progress", __FILE__, __LINE__);
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
