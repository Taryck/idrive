#!/usr/bin/env perl

########################################################################
#Script Name : Restore_Script.pl
########################################################################
system('clear');
use lib map{if (__FILE__ =~ /\//) {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";}}else {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {"./$_";}}} qw(Idrivelib/lib .);

use FileHandle;

eval {
	require Sys::Hostname;
	Sys::Hostname->import();
};

use POSIX;
use Fcntl qw(:flock SEEK_END);

use Common;

Common::waitForUpdate();
Common::initiateMigrate();

Common::verifyVersionConfig();

require 'Header.pl';

use constant false => 0;
use constant true => 1;

#use Constants 'CONST';
require Constants;
# use of constants
use constant CHILD_PROCESS_STARTED => 1;
use constant CHILD_PROCESS_COMPLETED => 2;

use constant LIMIT => 2*1024;
use constant FILE_MAX_COUNT => 1000;
use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";

# use constant SEARCH => "Search";
use constant SPLIT_LIMIT_SEARCH_OUTPUT => 6;
use constant SPLIT_LIMIT_ITEMS_OUTPUT => 2;
use constant SPLIT_LIMIT_INFO_LINE => 3;

use constant RESTORE_PID_FAIL => 5;
use constant OUTPUT_PID_FAIL => 6;
use constant PID_NOT_EXIST => 7;
use constant RESTORE_SUCCESS => 8;

use constant REMOTE_SEARCH_FAIL => 12;
use constant REMOTE_SEARCH_CMD_ERROR => 13;
use constant REMOTE_SEARCH_OUTPUT_PARSE_FAIL => 14;
use constant REMOTE_SEARCH_SUCCESS => 15;
use constant CREATE_THOUSANDS_FILES_SET_SUCCESS => 16;
use constant REMOTE_SEARCH_THOUSANDS_FILES_SET_ERROR => 17;

# Index number for arrayParametersStatusFile
use constant COUNT_FILES_INDEX => 0;
use constant SYNC_COUNT_FILES_INDEX => 1;
use constant ERROR_COUNT_FILES => 2;
use constant FAILEDFILES_LISTIDX => 3;
use constant RETRY_ATTEMPT_INDEX => 4;
#use constant ERR_MSG_INDEX => 4;
use constant EXIT_FLAG_INDEX => 4;
my @commandArgs = ('--silent', 'dashboard', Constants->CONST->{'versionRestore'},'SCHEDULED');
if ($#ARGV >= 0){
	if (!validateCommandArgs(\@ARGV,\@commandArgs)){
		print Constants->CONST->{'InvalidCmdArg'}.$lineFeed;
		cancelProcess();
	}
}

# Status File Parameters
my @statusFileArray = (	
	"COUNT_FILES_INDEX",
	"SYNC_COUNT_FILES_INDEX",
	"ERROR_COUNT_FILES",
	"FAILEDFILES_LISTIDX",
	"RETRY_ATTEMPT_INDEX",
	"EXIT_FLAG"
	#"ERR_MSG_INDEX"
);

#Indicates whether child process#
#has started/completed          #
my $childProcessStatus : shared;
$childProcessStatus = undef;
#Check if EVS Binary exists.
my $silentFlag = 0;
if ($ARGV[0] eq '--silent' or ${ARGV[0]} eq 'dashboard'){
	$AppConfig::callerEnv = 'BACKGROUND';
    $silentFlag = 1;
}
$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

loadUserData(); # $restoreHost variable is not getting populated
$totalEngineBackup = $AppConfig::restoreEngineCount;
Common::checkAccountStatus($silentFlag? 0 : 1);

if ($silentFlag == 0 and $ARGV[0] != Constants->CONST->{'versionRestore'} and $ARGV[0] ne 'SCHEDULED'){ #To prevent the calling of headerDisplay() subroutine.
	headerDisplay($0);
}

my $errorFilePresent = false;
my $invalidCharPresent = false;
my $lineCount;
my $prevLineCount;
my $cancelFlag = false;
my $headerWrite = 0;
my $restoreUtfFile = '';
my $generateFilesPid = undef;
my $displayProgressBarPid = undef;
my $prevTime = time();
my $pidOperationFlag = "main";
my $countErrorFile = 0; 					#Count of files which could not be restored due to specified errors #
my $maxNumRetryAttempts = 1000;				#Maximum number of times the script should try to restore in case of errors#
my $filesonlycount = 0;
my $prevFailedCount = 0;
my $totalSize = 0;
my $relative = 0;
my $noRelIndex = 0;
my $exitStatus = 0;
my $retrycount = 0;
#my $RestoreItemCheck = $jobRunningDir."/"."RestoresetFile.txt.item";
my $RestoresetFile_new = '';

my $RestoresetFile_relative = "RestoreFileName_Rel";
my $filesOnly = "RestoreFileName_filesOnly";
my $noRelativeFileset = "RestoreFileName_NoRel";
our $exit_flag = 0;
$jobType = "Restore";
my $retry_failedfiles_index = 0;
my $engineID = 1;
my @RestoreForkchilds;
#Subroutine that processes SIGINT, SIGTERM and SIGTSTP#
#signal received by the script during restore#
$SIG{INT}  = \&process_term;
$SIG{TERM} = \&process_term;
$SIG{TSTP} = \&process_term;
$SIG{QUIT} = \&process_term;
$SIG{PWR}  = \&process_term if(exists $SIG{'PWR'});
$SIG{KILL} = \&process_term;
$SIG{USR1} = \&process_term;
$SIG{WINCH} = \&Common::changeSizeVal;

#Assigning Perl path
my $perlPath = $AppConfig::perlBin;

my $RestoreFileName = $RestoresetFile;
chmod $filePermission, $RestoreFileName;
# Trace Log Entry #
my $curFile = basename(__FILE__);

#Verifying if Restore scheduled or manual job
my $isScheduledJob = 0;
if($ARGV[0] eq "SCHEDULED") {
	$pwdPath = $pwdPath."_SCH";
	$pvtPath = $pvtPath."_SCH";
	$isScheduledJob = 1;
	$taskType = "Scheduled";
}else{
	$taskType = "Manual";
	if(!defined(${ARGV[0]}) or ${ARGV[0]} ne 'dashboard'){
		if(getAccountConfStatus($confFilePath)){
			Common::sendFailureNotice($userName,'update_restore_progress',$taskType);
			exit(0);
		}
		else{
			if(getLoginStatus($pwdPath)){
				Common::sendFailureNotice($userName,'update_restore_progress',$taskType);
				exit(0);
			}
		}
	}
#	$CurrentRestoresetSoftPath = $RestoresetFileSoftPath;
}

if(${ARGV[0]} eq '--silent') {
	$AppConfig::displayHeader = 0;
	Common::isLoggedin() or Common::retreat(["\n", 'login_&_try_again']);
}

if (! checkIfEvsWorking($dedup)){
    print Constants->CONST->{'EvsProblem'}.$lineFeed if($taskType eq "Manual");
	Common::traceLog(Constants->CONST->{'EvsProblem'});
	Common::sendFailureNotice($userName,'update_restore_progress',$taskType);
    exit 0;
}
# traceLog(qq(File: $curFile));
#Defining and creating working directory
$jobRunningDir = "$usrProfilePath/$userName/Restore/DefaultRestoreSet";
$AppConfig::jobRunningDir = $jobRunningDir; # Added by Senthil on Nov 26, 2018
$AppConfig::jobType = $AppConfig::restore;

if(!-d $jobRunningDir) {
	mkpath($jobRunningDir);
	chmod $filePermission, $jobRunningDir;
}
exit 1 if(!checkEvsStatus(Constants->CONST->{'RestoreOp'}));
$pidPath = "$jobRunningDir/pid.txt";

#Checking if another job in progress
if(!pidAliveCheck()){
	$pidMsg = "$jobType job is already in progress. Please try again later.\n";
	print $pidMsg if($taskType eq "Manual");
	Common::traceLog($pidMsg);
	exit 1;
}

# if(!$silentFlag) {
# 	Common::launchDevicetrustCheck();
# }

#Loading global variables
my $RestoreItemCheck = $jobRunningDir."/"."RestoresetFile.txt.item"; #"RestoresetFile.txt.item";
$statusFilePath = "$jobRunningDir/STATUS_FILE";
$search = "$jobRunningDir/Search";
my $info_file = "$jobRunningDir/info_file";
$retryinfo = "$jobRunningDir/$retryinfo";
# $evsTempDirPath = "$jobRunningDir/evs_temp";
# $evsTempDir = $evsTempDirPath;
my $failedfiles = $versionRestoresetFile."/".$failedFileName;
$idevsOutputFile = "$jobRunningDir/output.txt";
$idevsErrorFile = "$jobRunningDir/error.txt";
$RestoresetFile_relative = $jobRunningDir."/".$RestoresetFile_relative;
$noRelativeFileset	= $jobRunningDir."/".$noRelativeFileset;
$filesOnly	= $jobRunningDir."/".$filesOnly;
my $fileForSize = "$jobRunningDir/TotalSizeFile";
my $totalFileCountFile	= "$jobRunningDir/totalFileCountFile";
#my $incSize = "$jobRunningDir/transferredFileSize.txt";
my $trfSizeAndCountFile = "$jobRunningDir/trfSizeAndCount.txt";
my $utf8Files = $jobRunningDir."/utf8.txt_";
my $engineLockFile = $jobRunningDir.'/'.ENGINE_LOCKE_FILE;
my $progressDetailsFile = $jobRunningDir . $pathSeparator . "PROGRESS_DETAILS";
my $jobCancelFile = $jobRunningDir.'/exitError.txt';
my $summaryFilePath = "$jobRunningDir/".Constants->CONST->{'fileDisplaySummary'};

#Renaming the log file if restore process terminated improperly
Common::checkAndRenameFileWithStatus($jobRunningDir, lc($jobType));

# pre cleanup for all intermediate files and folders.
Common::removeItems([$totalFileCountFile,$RestoresetFile_relative."*", $noRelativeFileset."*", $filesOnly."*", $info_file, $retryinfo, "ERROR", $statusFilePath."*", $failedfiles."*", $progressDetailsFile."*", $jobCancelFile, $summaryFilePath]);
$errorDir = $jobRunningDir."/ERROR";
if(!-d $errorDir) {
	my $ret = mkdir($errorDir);
	if($ret ne 1) {
		Common::traceLog("Couldn't create $errorDir: $!");
		exit 1;
	}
	chmod $filePermission, $errorDir;
}

my $operationType = Constants->CONST->{'RestoreOp'};
# Deciding Restore set File based on normal restore or version restore
if($ARGV[0] eq Constants->CONST->{'versionRestore'} or (defined($ARGV[2]) and $ARGV[2] eq Constants->CONST->{'versionRestore'})) {
	$RestoreFileName = $jobRunningDir."/versionRestoresetFile.txt";
	$RestoreSetJsonFile = Common::getCatfile($jobRunningDir, $AppConfig::versionRestoreFile);
	Common::fileWrite($RestoreFileName, Common::getFileContents($RestoreSetJsonFile));
	$operationType = Constants->CONST->{'VersionOp'};
}

# Commented as per Deepak's instruction: Senthil
# my $serverAddress = verifyAndLoadServerAddr();
# if ($serverAddress == 0){
    # exit_cleanup($errStr);
# }

#my $encType = checkEncType($isScheduledJob); # This function has been called inside getOperationFile() function.
#createUpdateBWFile(); #Commented by Senthil: 13-Aug-2018
#my $isEmpty = checkPreReq($RestoreFileName,$jobType,$taskType,'NORESTOREDATA');
my $isEmpty = Common::checkPreReq($RestoreFileName, lc($jobType), 'NORESTOREDATA');
if($isEmpty and $isScheduledJob == 0 and $silentFlag == 0) {
	unlink($pidPath);
	Common::retreat(["\n",$AppConfig::errStr]);
}

createLogFiles("RESTORE");
#$info_file = $jobRunningDir."/info_file";
$failedfiles = $jobRunningDir."/".$failedFileName;
createRestoreTypeFile();

Common::setUsername($userName) if(defined($userName) && $userName ne '');
if (Common::loadAppPath() and Common::loadServicePath() and Common::isLoggedin() and Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
	Common::setNotification('update_restore_progress', ((split("/", $outputFilePath))[-1]));
	Common::saveNotifications();
	Common::unlockCriticalUpdate("notification");
}

=beg
if(${ARGV[0]} eq ""){				#Only for Manual Restore.
	emptyLocationsQueries();
}
=cut
# Modified as per review comment: Senthil
if (Common::getUserConfiguration('RESTORELOCATIONPROMPT') and $ARGV[0] ne Constants->CONST->{'versionRestore'}) {
    Common::editRestoreLocation(1) if($AppConfig::callerEnv ne 'BACKGROUND');
    $location = Common::getUserConfiguration('RESTORELOCATION');
	utf8::decode($location);

    unless(-w $location) {
        $errStr = Common::getStringConstant('operation_could_not_be_completed_reason').Common::getStringConstant('invalid_restore_location');
        Common::retreat(["\n",$errStr]) if($AppConfig::callerEnv ne 'BACKGROUND');
    } else {
        Common::display("");
        sleep(2);
    }
}

# check for trusted device
if(!$silentFlag) {
	if(!Common::trackDeviceTrust()) {
		$AppConfig::displayHeader = 0;
		exit_cleanup(Common::getLocaleString("device_trust_failed"));
	}

	Common::display(["\n", "your_device_has_been_added_as_trusted_device"]);
}

$mail_content_head = writeLogHeader($isScheduledJob,$operationType);
if($isScheduledJob == 0 and $silentFlag == 0 and !$isEmpty and -e $pidPath) {
	# getCursorPos();
    Common::getCursorPos(40,Common::getStringConstant('preparing_file_list'));
}

Common::writeAsJSON($totalFileCountFile, {});

startRestore() if(!$isEmpty and -e $pidPath and !$errStr);
exit_cleanup($errStr);

#****************************************************************************************************
# Subroutine Name         : startRestore
# Objective               : This function will fork a child process to generate restoreset files and get
#			    count of total files considered. Another forked process will perform main
#			    restore operation of all the generated restoreset files one by one.
# Added By		  :
# Modified By	  : Senthil Pandian
#*****************************************************************************************************/
sub startRestore {
	$generateFilesPid = fork();
	if(!defined $generateFilesPid) {
		$errStr = "Unable to start generateRestoresetFiles operation";
		Common::traceLog("Cannot fork() child process, Reason:$!");
		return;
	}

	if($generateFilesPid == 0) {
        generateRestoresetFiles();
        exit(0);
    }

	if($isScheduledJob == 0 and !$silentFlag){
		$displayProgressBarPid = fork();

		if(!defined $displayProgressBarPid) {
			Common::traceLog(Constants->CONST->{'ForkErr'}."$lineFeed");
			$errStr = "Unable to start generateBackupsetFiles operation";
			return;
		}

		if($displayProgressBarPid == 0) {
            my %fileInfo = ();
            my $restoreFileName = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::versionRestoreFile);

            if($operationType eq Constants->CONST->{'VersionOp'} and -f $restoreFileName){
                my $data  = Common::getFileContents($restoreFileName);
                %fileInfo = %{JSON::from_json($data)} unless($data =~ /_IBVER/);
            }
			
			if(exists($fileInfo{'opType'}) and $fileInfo{'opType'} =~ /folderVersioning|snapshot/) {
                displayFolderVersionRestoreProgress();
            } else {
                displayRestoreProgress();
            }
			exit(0);
		}
	}

	close(FD_WRITE);
	open(my $handle, '>', $engineLockFile) or Common::traceLog("Could not open file '$engineLockFile' $!");
	close $handle;
	chmod $filePermission, $engineLockFile;

	my $exec_cores = getSystemCpuCores();
    my $writeOutputHeading = 1;
	Common::loadAndWriteAsJSON($totalFileCountFile, {$AppConfig::startTimeKey => mktime(localtime)});

START:
	if (-e $info_file){
		if(!open(FD_READ, "<", $info_file)) {
			$errStr = Constants->CONST->{'FileOpnErr'}." $info_file to read, Reason:$!";
			Common::traceLog($errStr);
			return;
		}

		my $lastFlag = 0;
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
			$line =~ m/^[\s\t]+$/;
			#space and tab space also trim

			if($lastFlag eq 1) {
				last;
			}

			if($line =~ m/^TOTALFILES/) {
				$totalFiles = $line;
				$totalFiles =~ s/TOTALFILES//;
				$lastFlag = 1;
				$line = "";
				last;
			}
			else {

                if($writeOutputHeading){    
                    my $outputHeading = Common::getStringConstant('heading_restore_output');
                    $outputHeading	 .= "\n".(('-') x 78). "\n";
                    print OUTFILE $outputHeading;
                    $writeOutputHeading = 0;
                }

				$isEngineRunning = isEngineRunning($pidPath.'_'.$engineID);
				if(!$isEngineRunning){
					while(1){
						last	if(!-e $pidPath or !isAnyEngineRunning($engineLockFile));

						$exec_loads = get_load_average();
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

					$restorePid = fork();
					if(!defined $restorePid) {
						$errStr = Constants->CONST->{'ForkErr'}.$whiteSpace.Constants->CONST->{"EvsChild"}.$lineFeed;
						return RESTORE_PID_FAIL;
					}
					elsif($restorePid == 0) {
						$pidOperationFlag = "ChildProcess";
						my $retType = doRestoreOperation($line,$taskType,$engineID,$retry_failedfiles_index);
						exit(0);
					}
					else{
						push (@RestoreForkchilds, $restorePid);
						if(defined($exec_loads) and ($exec_loads > $exec_cores)){
							sleep(2);
						}
						else{
							sleep(1);
						}
					}
					$line = "";
				}
			}

			if($totalEngineBackup > 1)
			{
				$engineID++;
				if($engineID > $totalEngineBackup){
					$engineID = 1;
					sleep(2);
				}
			}

			Common::killPIDs(\@RestoreForkchilds,0);

			if( !-e $pidPath) {
				last;
			}
		}

		Common::waitForEnginesToFinish(\@RestoreForkchilds,$engineLockFile);
		close FD_READ;
		$nonExistsCount    = Common::readInfoFile('FAILEDCOUNT');
		waitpid($generateFilesPid,0);
		undef @linesStatusFile;

		if($totalFiles == 0 or $totalFiles !~ /\d+/) {
			if(-e $info_file){
				$totalFiles    = Common::readInfoFile('TOTALFILES');
				if($totalFiles == 0 or $totalFiles !~ /\d+/){
					Common::traceLog("Unable to get total files count: $totalFiles");
				}
			}
		}
		# if(-s $retryinfo > 0 && -e $pidPath && $retrycount <= $maxNumRetryAttempts && $exitStatus == 0) {
			# if($retrycount == $maxNumRetryAttempts) {
        if(-s $retryinfo > 0 && -e $pidPath &&
            ((-f $minimalErrorRetry) ? ($retrycount <= $minRetryAttempts) : ($retrycount <= $maxNumRetryAttempts)) && $exitStatus == 0) {
            if ((-f $minimalErrorRetry) ? ($retrycount >= $minRetryAttempts) : ($retrycount >= $maxNumRetryAttempts)) {
				for(my $i=1; $i<= $totalEngineBackup; $i++){
					if(-e $statusFilePath."_".$i  and  -s $statusFilePath."_".$i>0){
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
				$errStr = Constants->CONST->{'FileOpnErr'}." $info_file, Reason $!".$lineFeed;
				return;
			}
			print INFO "TOTALFILES $totalFiles\n";
			print INFO "FAILEDCOUNT $nonExistsCount\n";
			close INFO;
			chmod $filePermission, $info_file;
			sleep 5; #5 Sec
            Common::traceLog("retrycount: $retrycount");
			$engineID = 1;
			Common::loadUserConfiguration(); #Reloading to handle domain connection failure case
			goto START;
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : checkRestoreItem.
# Objective               : This function will check if restore items are files or folders
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub checkRestoreItem {
    my %list = ();
	if(!open(RESTORELIST, $RestoreFileName)){
		Common::traceLog(Constants->CONST->{'FileOpnErr'}." $RestoreFileName , Reason: $!");
		return %list;
	}
	if(!open(RESTORELISTNEW, ">", $RestoreItemCheck)){
		Common::traceLog(Constants->CONST->{'FileOpnErr'}." $RestoreItemCheck , Reason: $!");
		return %list;
	}
	$tempRestoreHost = $restoreHost;
	if($dedup eq 'on'){
		$tempRestoreHost = "";
	}
	while(<RESTORELIST>) {
		chomp($_);
		$_ =~ s/^\s+//;
		if($_ eq "") {
			next;
		}
		my $rItem = "";
		if(substr($_, 0, 1) ne "/") {
			$rItem = $tempRestoreHost."/".$_;
		} else {
			$rItem = $tempRestoreHost.$_;
		}
		print RESTORELISTNEW $rItem.$lineFeed;
	}
	close(RESTORELIST);
	close(RESTORELISTNEW);

GETSTAT:
=beg
	my @itemsStat = ();
	my $checkItemUtf = getOperationFile( Constants->CONST->{'ItemStatOp'}, $RestoreItemCheck);

	if(!$checkItemUtf) {
		Common::traceLog($errStr);
		return @itemsStat;
	}

	$checkItemUtf =~ s/\'/\'\\''/g;
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$checkItemUtf."'".$whiteSpace.$errorRedirection;
	$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
	my @itemsStat = `$idevsutilCommandLine`;

	# update server address if cmd failed due to wrong evs server address
	unless(updateServerAddr()){
		goto GETSTAT;
	}

	unlink($checkItemUtf);
	unlink($RestoreItemCheck);
	return @itemsStat;
=cut
	my $itemStatusUTFpath = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
	Common::createUTF8File(['ITEMSTATUS',$itemStatusUTFpath, 1],
		$RestoreItemCheck,
		$evsErrorFile,
        ''
		);

	if(!-f $itemStatusUTFpath) {
		Common::traceLog('failed_to_create_utf8_file');
		return %list;
	}

	my @responseData = Common::runEVS('item',1);
	unlink($RestoreItemCheck);

	if(-s $evsErrorFile > 0) {
		unless(Common::checkAndUpdateServerAddr($evsErrorFile)) {
			exit_cleanup(Common::getStringConstant('operation_could_not_be_completed_please_try_again'));
		} else {
			my $errStr = Common::checkExitError($evsErrorFile,'archive');
			if($errStr and $errStr =~ /1-/){
				$errStr =~ s/1-//;
				exit_cleanup($errStr);
			}
		}
		return %list;
	}
	unlink($evsErrorFile);
   
    foreach my $tmpLine (@responseData) {
        my @fields = $tmpLine;
        if (ref($fields[0]) ne "HASH") {
            next;
        }

        my $itemName = $fields[0]{'fname'};
        Common::replaceXMLcharacters(\$itemName);
        $itemName =~ s/^[\/]+/\//g;

        if($fields[0]{'status'} =~ /directory exists/) {
            # startSearchOperation($itemName);
            $list{$itemName} = 'd';
        }
        elsif($fields[0]{'status'} =~ /file exists/){
            $list{$itemName} = 'f';
        } else {
            $list{$itemName} = 0;
        }
    }
    return %list;
}

#****************************************************************************************************
# Subroutine Name         : enumerateRemote.
# Objective               : This function will search remote files for folders.
# Added By				  : Avinash Kumar.
# Modified By 			  : Dhritikana, Senthil Pandian
#*****************************************************************************************************/
sub enumerateRemote {
	my $remoteFolder  = $_[0];
	my $searchForRestore = 1;
	my $splitsize = 0;

	if( !-e $pidPath) {
		return 0;
	}
    # remove / from begining for folder to avoid // while creating utf8 file.

	#Commented by Senthil: 04-Jan-2022
	# if(substr($remoteFolder, -1, 1) eq "/") {
		# chop($remoteFolder);
	# }
	$remoteFolder .= '/' if(substr($remoteFolder, -1, 1) ne "/");

	# final EVS command to execute
	if(! -d $search) {
		if(!mkdir($search)) {
			$errStr = "Failed to create search directory\n";
			return 0;
		}
		chmod $filePermission, $search;
	}

	my $searchRetryCount = 5;
	my $tempSearchUTFpath = $search.'/'.$AppConfig::utf8File;
	my $tempEvsOutputFile = $search.'/'.$AppConfig::evsOutputFile;
	my $tempEvsErrorFile  = $search.'/'.$AppConfig::evsErrorFile;

STARTSEARCH:
	# my $searchOp = ($AppConfig::versionToRestore>$AppConfig::maxFileVersion)?'SNAPSHOTSEARCH':'SEARCH';
	if($AppConfig::versionToRestore>$AppConfig::maxFileVersion) {
		Common::createUTF8File(['SNAPSHOTSEARCH',$tempSearchUTFpath, 1],
					0,
					$AppConfig::versionToRestore,
					$tempEvsOutputFile,
					$tempEvsErrorFile,
					$remoteFolder,
					) or Common::retreat('failed_to_create_utf8_file');
	} else {
		Common::createUTF8File(['SEARCH',$tempSearchUTFpath, 1],
					$tempEvsOutputFile,
					$tempEvsErrorFile,
					$remoteFolder,
					) or Common::retreat('failed_to_create_utf8_file');
	}			
# print "\n".Common::getFileContents($tempSearchUTFpath)."\n";
	my @responseData = Common::runEVS('item',1,0,$tempSearchUTFpath);
	
	while(-e $pidPath){
		last if((-e $tempEvsOutputFile and -s _) or (-e $tempEvsErrorFile and -s _));
		sleep(2);
	}

	if(-s $tempEvsOutputFile == 0 and -s $tempEvsErrorFile > 0) {
		my $errStr = Common::checkExitError($tempEvsErrorFile,'archive');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			exit_cleanup($errStr);
		}
		Common::traceLog('SEARCHARCHIVE Retry');
		$totalNoOfRetry--;
		next if($totalNoOfRetry);
		return 0;
	}

	# parse search output.
	open my $SEARCHOUTFH, "<", $tempEvsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').":$tempEvsOutputFile. Reason:$!");
	if($errStr ne ""){
		Common::traceLog($errStr);
		return 0;
	}

	# update server address if cmd failed due to wrong evs server address
	unless(updateServerAddr($tempEvsErrorFile)){
		$searchRetryCount--;
		goto STARTSEARCH if($searchRetryCount);
	}

	if(-s $tempEvsErrorFile > 0) {
		$errStr = "Remote folder enumeration has failed.\n";
		checkExitError($tempEvsErrorFile);
		writeParameterValuesToStatusFile($fileBackupCount, $fileRestoreCount, $fileSyncCount, $failedfiles_count, $deniedFilesCount, $missingCount, 0, 0, $exit_flag, $failedfiles_index, $engineID);
		return REMOTE_SEARCH_FAIL;
	}
	unlink($searchUtfFile);

	# parse serach output.
	open OUTFH, "<", $tempEvsOutputFile or ($errStr = "cannot open :$tempEvsOutputFile: of search result for $remoteFolder");
	if($errStr ne ""){
		Common::traceLog($errStr);
		return REMOTE_SEARCH_OUTPUT_PARSE_FAIL;
	}
# print "versionToRestore:".$AppConfig::versionToRestore."\n";
	# if($dedup eq 'on'){
		while(<OUTFH>){
# Common::traceLog("itemName::".$_);
            if($_ =~ /<item/ and $_ !~ /tot_items_deleted|items_found|files_found|items_count/){
                my %itemName = Common::parseXMLOutput(\$_);
                my $fname = $itemName{'fname'};
				chomp($fname);
                replaceXMLcharacters(\$fname);               
				my $version = $itemName{'file_ver'};
 # Common::traceLog("fname::$fname#");
 # Common::traceLog("versionToRestore::".$AppConfig::versionToRestore);
 # Common::traceLog("version::".$version);
				if($AppConfig::versionToRestore > 30) {
					$fname .= "_IBVER".$version;
				} elsif($AppConfig::versionToRestore > 1) {
					next if(($version - ($AppConfig::versionToRestore - 1)) <= 0);
					$fname .= "_IBVER".($version - ($AppConfig::versionToRestore - 1));
				}

                my $quoted_current_source = quotemeta($current_source);
                if($relative == 0) {
                    if($current_source ne "/") {
                        if($fname =~ s/^$quoted_current_source//) {
                            print $filehandle $fname.$lineFeed;
                        } else {
                            next;
                        }
                    } else {
                        print $filehandle $fname.$lineFeed;
                    }
                }
                else {
                    if($fname =~ /\^$remoteFolder/) {
                        $current_source = "/";
                        print RESTORE_FILE $fname.$lineFeed;
                        $RestoresetFileTmp = $RestoresetFile_relative;
                    }
                }
                $totalFiles++;
                $filecount++;
                $size = $itemName{'size'};
                if($size =~ /^\d+$/) {
                    $totalSize += $size;
                    $splitsize += $size;
                }

                if($filecount == FILE_MAX_COUNT || $splitsize >= $AppConfig::backupsetMaxSize) {
                    $splitsize = 0;
                    if( !-e $pidPath) {
                        last;
                    }
                    if(!createRestoreSetFiles1k()){
                        Common::traceLog($errStr);
                        return REMOTE_SEARCH_THOUSANDS_FILES_SET_ERROR;
                    }
                }
            }
		}

	Common::traceLog($errStr) if($errStr);
	return REMOTE_SEARCH_SUCCESS;
}

#****************************************************************************************************
# Subroutine Name         : generateRestoresetFiles.
# Objective               : This function will generate restoreset files.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub generateRestoresetFiles {
    my ($itemHash, %itemsStat);

	#check if running for restore version pl, in that case no need of generate files.
	if($RestoreFileName =~ m/versionRestore/) {
		if(!open(RFILE, "<", $RestoreSetJsonFile)) {
			my $errStr = "Couldn't open file $RestoreSetJsonFile to read, Reason: $!\n";
			Common::traceLog($errStr);
		}

		my $versiondata = <RFILE>;
        close(RFILE);
        Common::Chomp(\$versiondata);
        $itemHash = JSON::from_json($versiondata);
# use Data::Dumper;
# print Dumper(\$itemHash);
        # print "opType:".$itemHash->{'opType'}."#\n";
        # print "itemType:".$itemHash->{'itemType'}."#\n";
        # print "itemSize:".$itemHash->{'itemSize'}."#\n";
        # print "itemVer:".$itemHash->{'itemVer'}."#\n";
        if($itemHash->{'opType'} eq 'fileVersioning') {
# print "RestoreFileName:$RestoreFileName\n\n";
            if(!open(WFILE, ">", $RestoreFileName)) {
                my $errStr = "Couldn't open file $RestoreFileName to write, Reason: $!\n";
                Common::traceLog($errStr);
            }
# my $name = keys $itemHash->{'items'}{1};
			my $name = (keys %{$itemHash->{'items'}})[0];
            print WFILE $name.'_IBVER'.$itemHash->{'items'}{$name}{'ver'}.$lineFeed;
            close(WFILE);
            $totalSize = $itemHash->{'items'}{$name}{'size'};
# Common::traceLog("itemName::".$name.'_IBVER'.$itemHash->{'items'}{$name}{'ver'});
# Common::traceLog("fileForSize:$fileForSize#itemSize:".$totalSize);
            $totalFiles = 1;
            $current_source = "/";
            #print FD_WRITE "$RestoreFileName ".NORELATIVE." $current_source\n";
            print FD_WRITE "$current_source' '".NORELATIVE."' '$RestoreFileName\n";
            goto GENEND;
        }
		elsif($itemHash->{'opType'} eq 'folderVersioning') {
			my $name = (keys %{$itemHash->{'items'}})[0];
            $itemsStat{$name} = 'd';
            # $AppConfig::versionToRestore = $itemHash->{'items'}{$name}{'ver'};
			Common::fileWrite($RestoreFileName, '');
            # startFolderSearchOperation($itemHash->{'itemName'}, $AppConfig::versionToRestore-1);
        }
		elsif($itemHash->{'opType'} eq 'snapshot') {
			$AppConfig::versionToRestore = $itemHash->{'endDate'};
			# my @variants = keys %{$itemHash->{'items'}};
			foreach my $name (keys %{$itemHash->{'items'}}) {
				$itemsStat{$name} = $itemHash->{'items'}{$name}{'type'};
			}
			Common::fileWrite($RestoreFileName, '');
		}
	}

    my $traceExist = $errorDir."/traceExist.txt";
    if(!open(TRACEERRORFILE, ">>", $traceExist)) {
        Common::traceLog(Constants->CONST->{'FileOpnErr'}." $traceExist, Reason: $!.");
    }
    chmod $filePermission, $traceExist;

    $pidOperationFlag = "GenerateFile";

    %itemsStat = checkRestoreItem() if($RestoreFileName !~ m/versionRestore/);

	$filesonlycount = 0;
	my $j = 0;
	my $idx = 0;
    my $splitsize = 0;

	if(scalar(keys %itemsStat) ge 1) {
		if($dedup eq 'on'){
			foreach my $itemName (keys %itemsStat) {
				if( !-e $pidPath) {
					last;
				}
# print "itemName:$itemName\n";
                unless($itemsStat{$itemName}) {
                    $totalFiles++;
                    $nonExistsCount++;
                    print TRACEERRORFILE "[".(localtime)."] [FAILED] [$itemName]. Reason: No such file or directory".$lineFeed;
                    next;

					#print "No such file or directory";
					$totalFiles++;
					$nonExistsCount++;
					my $rfl = index($itemName, '/', 1);
					my $mfile = (length($itemName) > 2)? substr($itemName, $rfl) : $itemName;
					print TRACEERRORFILE "[".(localtime)."] [FAILED] [$mfile]. Reason: No such file or directory".$lineFeed;
				    next;
                } elsif(lc($itemsStat{$itemName}) eq 'd') {
					#print "directory exists";
					chop($itemName) if(substr($itemName, -1, 1) eq '/');
					if($relative == 0) {
						$noRelIndex++;
						$RestoresetFile_new = $noRelativeFileset."$noRelIndex";
						$filecount = 0;
						$sourceIdx = rindex ($itemName, '/');
						$source[$noRelIndex] = substr($itemName,0,$sourceIdx);
						if($source[$noRelIndex] eq "") {
							$source[$noRelIndex] = "/";
						}
						$current_source = $source[$noRelIndex];
						if(!open $filehandle, ">>", $RestoresetFile_new){
							$errStr = "Unable to get list of files to restore.\n";
							Common::traceLog("cannot open $RestoresetFile_new to write");
							goto GENEND;
						}
						chmod $filePermission, $RestoresetFile_new;
					}
					my $resEnumerate = 0;
					$resEnumerate = enumerateRemote($itemName);
					if(!$resEnumerate){
						Common::traceLog(qq($errStr $itemName));
						goto GENEND;
					}
					elsif(REMOTE_SEARCH_CMD_ERROR == $resEnumerate or REMOTE_SEARCH_FAIL == $resEnumerate or REMOTE_SEARCH_OUTPUT_PARSE_FAIL == $resEnumerate){
						my $searchErrMsg = "[".(localtime)."]". "[".$itemName."] Failed. Reason: Search has failed for the item.$lineFeed";
						Common::traceLog("Search command failed due to syntax error for the folder ". $itemName);
						appendErrorToUserLog($searchErrMsg);
					}
					elsif(REMOTE_SEARCH_THOUSANDS_FILES_SET_ERROR == $resEnumerate){
						Common::traceLog("Error in creating 1k files ". $itemName);
						goto GENEND;
					}

					if($relative == 0 && $filecount>0) {
						autoflush FD_WRITE;
						#print FD_WRITE "$RestoresetFile_new#".RELATIVE."#$current_source\n";
						print FD_WRITE "$current_source' '".RELATIVE."' '$RestoresetFile_new\n";
					}
				} elsif(lc($itemsStat{$itemName}) eq 'f') {
					my $size = 0;
					if(exists $itemHash->{'items'}{$itemName}{'size'}) {
						$size = $itemHash->{'items'}{$itemName}{'size'};
						$itemName .= "_IBVER".$itemHash->{'items'}{$itemName}{'ver'} if(exists $itemHash->{'items'}{$itemName}{'ver'});
					} else  {
						#print "file exists";
						my $propertiesFile = getOperationFile(Constants->CONST->{'PropertiesOp'}, $itemName);
						my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
						$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
						my $tmp_propertiesFile = $propertiesFile;
						$tmp_propertiesFile =~ s/\'/\'\\''/g;

						# EVS command to execute for properties
						my $propertiesCmd = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_propertiesFile\'".$whiteSpace.$errorRedirection;
						$propertiesCmd = Common::updateLocaleCmd($propertiesCmd);
						my $commandOutput = `$propertiesCmd`;
						# traceLog($commandOutput);

						unlink $propertiesFile;

						$commandOutput =~ m/(size)(.*)/;
						$size = $2;
						$size =~ s/\D+//g;
					}
					$totalSize += $size;
                    $splitsize += $size;
					$current_source = "/";
					print RESTORE_FILE $itemName.$lineFeed;

					if($relative == 0) {
						$filesonlycount++;
						$filecount = $filesonlycount;
					}
					else {
						$filecount++;
					}

					$totalFiles++;

					if($filecount == FILE_MAX_COUNT || $splitsize >= $AppConfig::backupsetMaxSize) {
						$filesonlycount = 0;
                        $splitsize = 0;
						if(!createRestoreSetFiles1k("FILESONLY")){
							goto GENEND;
						}
					}
				}
			}
		} else {
			foreach my $itemName (keys %itemsStat) {
				if( !-e $pidPath) {
					last;
				}

                unless($itemsStat{$itemName}) {
                    $totalFiles++;
                    $nonExistsCount++;
                    print TRACEERRORFILE "[".(localtime)."] [FAILED] [$itemName]. Reason: No such file or directory".$lineFeed;
                    next;                  
                } elsif(lc($itemsStat{$itemName}) eq 'd') {
                    if($relative == 0) {
                        $noRelIndex++;
                        $RestoresetFile_new = $noRelativeFileset."$noRelIndex";
                        $filecount = 0;
                        $sourceIdx = rindex ($itemName, '/');
                        $source[$noRelIndex] = substr($itemName,0,$sourceIdx);
                        if($source[$noRelIndex] eq "") {
                            $source[$noRelIndex] = "/";
                        }
                        $current_source = $source[$noRelIndex];
                        if(!open $filehandle, ">>", $RestoresetFile_new){
                            $errStr = "Unable to get list of files to restore.\n";
                            Common::traceLog("cannot open $RestoresetFile_new to write ");
                            goto GENEND;
                        }
                        chmod $filePermission, $RestoresetFile_new;
                    }
                    my $resEnumerate = 0;
                    $resEnumerate = enumerateRemote($itemName);
                    if(!$resEnumerate){
                        Common::traceLog(qq($errStr $itemName));
                        goto GENEND;
                    }
                    elsif(REMOTE_SEARCH_CMD_ERROR == $resEnumerate or REMOTE_SEARCH_FAIL == $resEnumerate or REMOTE_SEARCH_OUTPUT_PARSE_FAIL == $resEnumerate){
                        my $searchErrMsg = "[".(localtime)."]". "[".$itemName."] Failed. Reason: Search has failed for the item.$lineFeed";
                        Common::traceLog("Search command failed due to syntax error for the folder ". $itemName);
                        appendErrorToUserLog($searchErrMsg);
                    }
                    elsif(REMOTE_SEARCH_THOUSANDS_FILES_SET_ERROR == $resEnumerate){
                        Common::traceLog("Error in creating 1k files ". $itemName);
                        goto GENEND;
                    }

                    if($relative == 0 && $filecount>0) {
                        autoflush FD_WRITE;
                        #print FD_WRITE "$RestoresetFile_new#".RELATIVE."#$current_source\n";
                        print FD_WRITE "$current_source' '".RELATIVE."' '$RestoresetFile_new\n";
                    }
                } elsif(lc($itemsStat{$itemName}) eq 'f') {
					my $size = 0;
					if(exists $itemHash->{'items'}{$itemName}{'size'}) {
						$size = $itemHash->{'items'}{$itemName}{'size'};
						$itemName .= "_IBVER".$itemHash->{'items'}{$itemName}{'ver'} if(exists $itemHash->{'items'}{$itemName}{'ver'});
					} else  {
						my $propertiesFile = getOperationFile(Constants->CONST->{'PropertiesOp'}, $itemName);
						my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
						$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
						my $tmp_propertiesFile = $propertiesFile;
						$tmp_propertiesFile =~ s/\'/\'\\''/g;

						# EVS command to execute for properties
						my $propertiesCmd = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_propertiesFile\'".$whiteSpace.$errorRedirection;
						$propertiesCmd = Common::updateLocaleCmd($propertiesCmd);
						my $commandOutput = `$propertiesCmd`;
						# traceLog($commandOutput);
						unlink $propertiesFile;

						$commandOutput =~ m/(size)(.*)/;
						$size = $2;
						$size =~ s/\D+//g;
					}
                    $totalSize += $size;
                    $splitsize += $size;

                    $current_source = "/";
                    print RESTORE_FILE $itemName.$lineFeed;

                    if($relative == 0) {
                        $filesonlycount++;
                        $filecount = $filesonlycount;
                    }
                    else {
                        $filecount++;
                    }

                    $totalFiles++;

                    if($filecount == FILE_MAX_COUNT || $splitsize >= $AppConfig::backupsetMaxSize) {
                        $filesonlycount = 0;
                        $splitsize = 0;
                        if(!createRestoreSetFiles1k("FILESONLY")){
                            goto GENEND;
                        }
                    }
                }				
			}
		}
	}
	else{
		checkExitError($idevsErrorFile);
		writeParameterValuesToStatusFile($fileBackupCount, $fileRestoreCount, $fileSyncCount, $failedfiles_count, $deniedFilesCount, $missingCount, 0, 0, $exit_flag, $failedfiles_index, $engineID);
	}

	if($relative == 1 && $filecount > 0){
		#print FD_WRITE "$RestoresetFile_new#".RELATIVE."#$current_source \n"; #[dynamic]
		print FD_WRITE "$current_source' '".RELATIVE."' '$RestoresetFile_new \n"; #[dynamic]
	}
	elsif($filesonlycount >0){
		$current_source = "/";
		#print FD_WRITE "$RestoresetFile_Only#".NORELATIVE."#$current_source\n"; #[dynamic]
		print FD_WRITE "$current_source' '".NORELATIVE."' '$RestoresetFile_Only\n"; #[dynamic]
	}

	GENEND:
	autoflush FD_WRITE;
	print FD_WRITE "TOTALFILES $totalFiles\n";
	print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
	close(FD_WRITE);
	close RESTORE_FILE;

	open FILESIZE, ">$fileForSize" or Common::traceLog(Constants->CONST->{'FileOpnErr'}." $fileForSize. Reason: $!");
	print FILESIZE "$totalSize";
	close FILESIZE;
	chmod $filePermission, $fileForSize;

	$pidOperationFlag = "generateListFinish";
	close(TRACEERRORFILE);
	# Common::fileWrite($totalFileCountFile,$totalFiles);
	Common::loadAndWriteAsJSON($totalFileCountFile, {$AppConfig::totalFileKey => $totalFiles});
	chmod $filePermission, $totalFileCountFile;	
	exit 0;
}

#****************************************************************************************************
# Subroutine Name         : createRestoreSetFiles1kcreateRestoreSetFiles1k.
# Objective               : This function will generate 1000 Backetupset Files
# Added By                : Pooja Havaldar
# Modified By			  : Avinash Kumar
#*****************************************************************************************************/
sub createRestoreSetFiles1k {
	my $filesOnlyFlag = $_[0];
	$Restorefilecount++;

	if($relative == 0) {
		if($filesOnlyFlag eq "FILESONLY") {
			$filesOnlyCount++;
			#print FD_WRITE "$RestoresetFile_Only#".NORELATIVE."#$current_source\n"; # 0
			print FD_WRITE "$current_source' '".NORELATIVE."' '$RestoresetFile_Only\n"; # 0
			$RestoresetFile_Only = $filesOnly."_".$filesOnlyCount;

			close RESTORE_FILE;
			if(!open RESTORE_FILE, ">", $RestoresetFile_Only) {
				Common::traceLog(Constants->CONST->{'FileOpnErr'}." $filesOnly to write, Reason: $!.");
				return 0;
			}
			chmod $filePermission, $RestoresetFile_Only;
		}
		else
		{
			#print FD_WRITE "$RestoresetFile_new#".RELATIVE."#$current_source\n";
			print FD_WRITE "$current_source' '".RELATIVE."' '$RestoresetFile_new\n";
			$RestoresetFile_new =  $noRelativeFileset."$noRelIndex"."_$Restorefilecount";

			close $filehandle;
			if(!open $filehandle, ">", $RestoresetFile_new) {
				Common::traceLog(Constants->CONST->{'FileOpnErr'}." $RestoresetFile_new to write, Reason: $!.");
				return 0;
			}
			chmod $filePermission, $RestoresetFile_new;
		}
	}
	else {
		#print FD_WRITE "$RestoresetFile_new#".RELATIVE."#$current_source\n";
		print FD_WRITE "$current_source' '".RELATIVE."' '$RestoresetFile_new\n";
		$RestoresetFile_new = $RestoresetFile_relative."_$Restorefilecount";

		close RESTORE_FILE;
		if(!open RESTORE_FILE, ">", $RestoresetFile_new){
			Common::traceLog(Constants->CONST->{'FileOpnErr'}." $RestoresetFile_new to write, Reason: $!.");
			return 0;
		}
		chmod $filePermission, $RestoresetFile_new;
	}

	autoflush FD_WRITE;
	$filecount = 0;

	if($Restorefilecount%15 == 0){
		sleep(1);
	}
	return CREATE_THOUSANDS_FILES_SET_SUCCESS;
}

#***********************************************************************************************************
# Subroutine Name         :	doRestoreOperation
# Objective               :	Performs the actual task of restoring files. It creates a child process which executes
#                           the restore command.
#							Creates an output thread which continuously monitors the temporary output file.
#							At the end of restore, it inspects the temporary error file if present.
#							It then deletes the temporary output file, temporary error file and the temporary
#							directory created by idevsutil binary.
# Added By                :
#************************************************************************************************************
sub doRestoreOperation {
	my $parameters 	 = $_[0];
	my $scheduleFlag = $_[1];
	my $operationEngineId = $_[2];
	my $retry_failedfiles_index = $_[3];
	my $doRestoreOperationErrorFile = "$jobRunningDir/doRestoreError.txt_".$operationEngineId;
	@parameter_list = split(/\' \'/, $parameters, SPLIT_LIMIT_INFO_LINE);
	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	if(!flock($startPidFileLock, LOCK_SH)){
		Common::traceLog("Failed to lock engine file");
		return 0;
	}

	Common::fileWrite($pidPath.'_evs_'.$operationEngineId, 1); #Added for Harish_2.19_7_5
	open(my $engineFp, ">>", $pidPath.'_'.$operationEngineId) or return 0;

	if(!flock($engineFp, LOCK_EX)){
		print "Unable to lock \n";
		return 0;
	}

	$restoreUtfFile = getOperationFile(Constants->CONST->{'RestoreOp'}, $parameter_list[2] ,$parameter_list[1] ,$parameter_list[0],$operationEngineId);
	if(!$restoreUtfFile) {
		Common::traceLog($errStr);
		return 0;
	}
	my $tmprestoreUtfFile = $restoreUtfFile;
	$tmprestoreUtfFile =~ s/\'/\'\\''/g;
	my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
	$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
	# EVS command to execute for backup
	$idevsutilCommandLine = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmprestoreUtfFile\'".$whiteSpace.$errorRedirection;
	$restorePid = fork();
	if(!defined $restorePid) {
		$errStr = Constants->CONST->{'ForkErr'}.$whiteSpace.Constants->CONST->{"EvsChild"}.$lineFeed;
		return RESTORE_PID_FAIL;
	}

	if($restorePid == 0) {
		if(-e $pidPath) {
			system(Common::updateLocaleCmd($idevsutilCommandLine." > /dev/null 2>'$doRestoreOperationErrorFile'"));
			if(-e $doRestoreOperationErrorFile && -s $doRestoreOperationErrorFile) {
				my $error = Common::getFileContents($doRestoreOperationErrorFile);
				if($error ne '' and $error !~ /no version information available/) {
					$errStr = Constants->CONST->{'DoRstOpErr'}.Constants->CONST->{'ChldFailMsg'};
					Common::traceLog("$errStr; Child Launch Error: $error");
					if(open(ERRORFILE, ">> $errorFilePath")) {
						autoflush ERRORFILE;

						print ERRORFILE $errStr;
						close ERRORFILE;
						chmod $filePermission, $errorFilePath;
					}
					else {
						Common::traceLog(Constants->CONST->{'FileOpnErr'}.$errorFilePath.", Reason:$!");
					}
				}
			}

			unlink($doRestoreOperationErrorFile);

			if(open OFH, ">>", $idevsOutputFile."_".$operationEngineId){
				print OFH "\nCHILD_PROCESS_COMPLETED\n";
				close OFH;
				chmod $filePermission, $idevsOutputFile."_".$operationEngineId;
			}
			else
			{
				Common::traceLog(Constants->CONST->{'FileOpnErr'}." $outputFilePath. Reason: $!");
				print  Constants->CONST->{'FileOpnErr'}." $outputFilePath. Reason: $!";
				return 0;
			}
		}
        sleep(1);
        unlink($pidPath.'_evs_'.$operationEngineId);
		exit 1;
	}

	{
		lock $childProcessStatus;
		$childProcessStatus = CHILD_PROCESS_STARTED;
	}

	exit 1 if( !-e $pidPath);
	# $pid_OutputProcess	= $pid;

	$isLocalRestore = 0;
	$workingDir = $currentDir;
	$workingDir =~ s/\'/\'\\''/g;
	my $tmpOpFilePath = $outputFilePath;
	$tmpOpFilePath =~ s/\'/\'\\''/g;
	my $tmpJobRngDir = $jobRunningDir;
	$tmpJobRngDir =~ s/\'/\'\\''/g;
	my $tmpRstSetFile = $parameter_list[2];
	$tmpRstSetFile =~ s/\'/\'\\''/g;
	my $tmpSrc = $parameter_list[0];
	$tmpSrc =~ s/\'/\'\\''/g;
	$fileChildProcessPath = $workingDir.'/'.Constants->FILE_NAMES->{operationsScript};
	my $tmpRestoreHost = $restoreHost;
	$tmpRestoreHost =~ s/\'/\'\\''/g;
	my $tmpRestoreLoc = $restoreLocation;
	$tmpRestoreLoc =~ s/\'/\'\\''/g;
	my $param = join ("\n",('RESTORE_OPERATION',$tmpOpFilePath,$tmpRstSetFile,$parameter_list[1],$tmpSrc,$progressSizeOp,$tmpRestoreHost,$tmpRestoreLoc,$silentFlag,'',$scheduleFlag));
	writeParamToFile("$tmpJobRngDir/operationsfile.txt_" . $operationEngineId, $param);
	$cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmpJobRngDir\' \'$userName\' \'$operationEngineId\' \'$retry_failedfiles_index\' \'$AppConfig::versionToRestore\'";
	$cmd = Common::updateLocaleCmd("$cmd 2>/dev/null &");

	system($cmd);

	waitpid($restorePid,0) if($restorePid);
	Common::waitForChildProcess($pidPath.'_proc_'.$operationEngineId);
	unlink($pidPath.'_'.$operationEngineId);
	updateServerAddr();

	unlink($parameter_list[2]);
	unlink($idevsOutputFile."_".$operationEngineId);
	flock($startPidFileLock, LOCK_UN);
	flock($engineFp, LOCK_UN);

	# return 0 if(-e $errorFilePath && -s $errorFilePath);

	return RESTORE_SUCCESS;
}

#*******************************************************************************************************
# Subroutine Name         :	verifyRestoreLocation
# Objective               :	This subroutine verifies if the directory where files are to be restored exists.
#                           In case the directory does	not exist, it sets the restore location to the
#							current directory.
# Added By                :
#********************************************************************************************************
sub verifyRestoreLocation()
{
	my $restoreLocationPath = ${$_[0]};
	if(!defined $restoreLocationPath or $restoreLocationPath eq "") {
		${$_[0]} = $usrProfileDir."/Restore_Data";
	}
	my $posLastSlash = rindex $restoreLocationPath, $pathSeparator;
	my $dirPath = substr $restoreLocationPath, 0, $posLastSlash + 1;
	my $dirName = substr $restoreLocationPath, $posLastSlash + 1;
	if(-d $dirPath) {
		foreach my $char (@invalidCharsDirName) {
			my $posInvalidChar = index $dirName, $char;
			if($posInvalidChar != -1) {
				${$_[0]} = $usrProfileDir."/Restore_Data";
				last;
			}
		}
	}
	else {
		${$_[0]} = $usrProfileDir."/Restore_Data";
	}
}

#*******************************************************************************************
# Subroutine		: process_term
# Objective			: The signal handler invoked when SIGINT or SIGTERM signal is received by the script
# Added By			: Deepak
# Modified By		: Sabin Cheruvattil
#******************************************************************************************
sub process_term {
	system("stty $AppConfig::stty") if($AppConfig::stty);	# restore 'cooked' mode
	unlink($pidPath);
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
	cancelSubRoutine();
}

#***********************************************************************************************************
# Subroutine Name         	:	cancelSubRoutine
# Objective               	:	In case the script execution is canceled by the user, the script should
#                           terminate the execution of the binary and perform cleanup operation.
#							It should then generate the restore summary report, append the contents of the
#							error file to the output file and delete the error file.
# Added By				  	: Arnab Gupta
# Modified By				: Dhritikana, Sabin Cheurvattil, Senthil Pandian
#************************************************************************************************************
sub cancelSubRoutine {
	if($pidOperationFlag eq "GenerateFile")  {
		#if info file doesn't have TOTALFILE then write to info
		open FD_WRITE, ">>", $info_file or (Common::traceLog(Constants->CONST->{'FileOpnErr'}." $info_file to write, Reason:$!")); # and die);
		autoflush FD_WRITE;
		print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
		close(FD_WRITE);
		close RESTORE_FILE;
		exit 0;
	}

    #Added to prevent multiple exit cleanup calls due to fork processes
    exit(0) if($pidOperationFlag =~ /DisplayProgress|ChildProcess|ExitCleanup/);

	if($pidOperationFlag eq "main") {
		Common::sendFailureNotice($userName, 'update_restore_progress', $taskType);
		my $tempJobRunningDir = $jobRunningDir;
		$tempJobRunningDir =~ s/\[/\\[/;
		$tempJobRunningDir =~ s/{/[{]/;
		my $evsCmd = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$tempJobRunningDir\'";
		$evsCmd = Common::updateLocaleCmd($evsCmd);
		$evsRunning = `$evsCmd`;
		@evsRunningArr = split("\n", $evsRunning);
		my $arrayData = ($machineInfo eq 'freebsd')? 1 : 3;

		foreach(@evsRunningArr) {
			next if($_ =~ /$evsCmd|grep/);
			my @lines = split(/[\s\t]+/, $_);
			my $pid = $lines[$arrayData];

			$scriptTerm = system(Common::updateLocaleCmd("kill -9 $pid 2>/dev/null"));
			Common::traceLog(Constants->CONST->{'KilFail'}." Restore") if(defined($scriptTerm) && $scriptTerm != 0 && $scriptTerm ne "")
		}

		waitpid($generateFilesPid, 0) if($generateFilesPid);
		waitpid($displayProgressBarPid, 0) if($displayProgressBarPid);
		Common::waitForChildProcess();

		if(($totalFiles == 0 or $totalFiles !~ /\d+$/) and (-s $info_file)) {
			my $fileCountCmd = "cat '$info_file' | grep \"^TOTALFILES\"";
			$fileCountCmd = Common::updateLocaleCmd($fileCountCmd);
			$totalFiles = `$fileCountCmd`;
			$totalFiles =~ s/TOTALFILES//;
		}

		Common::traceLog("Unable to get total files count2") if($totalFiles == 0 or $totalFiles !~ /\d+$/);

		if($nonExistsCount == 0 and -s $info_file) {
			my $nonExistCheckCmd = "cat '$info_file' | grep \"^FAILEDCOUNT\"";
			$nonExistCheckCmd = Common::updateLocaleCmd($nonExistCheckCmd);
			$nonExistsCount = `$nonExistCheckCmd`;
			$nonExistsCount =~ s/FAILEDCOUNT//;
		}

		waitpid($pid_OutputProcess, 0) if($pid_OutputProcess);
		$errStr = Constants->CONST->{'operationFailUser'};
		exit_cleanup($errStr);
	}
}

#****************************************************************************************************
# Subroutine Name         : exit_cleanup.
# Objective               : This function will execute the major functions required at the time of exit
# Added By                : Deepak Chaurasia
# Modified By 		  	  : Dhritikana, Sabin Cheruvattil
#*****************************************************************************************************/
sub exit_cleanup {
    $pidOperationFlag = 'ExitCleanup';
	if ($silentFlag == 0 and $taskType eq 'Manual'){
		system('stty', 'echo');
		system(Common::updateLocaleCmd("tput sgr0"));
	}

	unless($isEmpty) {
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','TOTAL_TRANSFERRED_SIZE','EXIT_FLAG_INDEX');
		($successFiles, $syncedFiles, $failedFilesCount,$transferredFileSize,$exit_flag) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);

		if($errStr eq "" and -e $errorFilePath) {
			open ERR, "<$errorFilePath" or Common::traceLog(Constants->CONST->{'FileOpnErr'}."errorFilePath in exit_cleanup: $errorFilePath, Reason: $!");
			$errStr .= <ERR>;
			close(ERR);
			chomp($errStr);
		}
		if(!-e $pidPath) {
			$cancelFlag = 1;

			# In childprocess, if we exit due to some exit scenario, then this exit_flag will be true with error msg
			@exit = split("-",$exit_flag,2);
			if(!$exit[0] and $errStr eq "") {
				if($isScheduledJob) {
					$errStr = Constants->CONST->{'operationFailCutoff'};
					if(!-e Common::getServicePath()) {
						$errStr = Constants->CONST->{'operationFailUser'};
					}
				}
				else {
					$errStr = Constants->CONST->{'operationFailUser'};
				}
			} else {
				if($exit[1] ne ""){
					$errStr = $exit[1];
					# Common::checkAndUpdateAccStatError($userName, $errStr);
					#Below section has been added to provide user friendly message and clear instruction in case of password mismatch or encryption verification failed.
					#In this case we are removing the IDPWD file.So that user can login and recreate these files with valid credential.
					if ($errStr =~ /password mismatch|encryption verification failed/i){
						Common::createBackupStatRenewalByJob('backup') if(Common::getUserConfiguration('DEDUP') ne 'on');
						$errStr = $errStr.'. '.Constants->CONST->{loginAccount}.$lineFeed;
						unlink($pwdPath);
						if($taskType eq "Scheduled") {
							$pwdPath =~ s/_SCH$//g;
							unlink($pwdPath);
						}
					} elsif($errStr =~ /failed to get the device information|Invalid device id/i){
						$errStr = $errStr.' '.Constants->CONST->{restoreFromLocationConfigAgain}.$lineFeed;
					} else {
						# $errStr = Common::checkErrorAndLogout($errStr, undef, 1);
                        $errStr = Common::checkErrorAndReturnErrorMessage($errStr);
					}
				}
			}
		}
	}

	if($errStr =~ /error code:/i) {
		$errStr .= ' ' . Common::getLocaleString('Please_try_again_issue_contact_support');
	}

    Common::removeItems($pidPath);
	waitpid($displayProgressBarPid,0);
	wait();
	writeOperationSummary(Constants->CONST->{'RestoreOp'}, $cancelFlag, $transferredFileSize);
    Common::removeItems([$fileForSize, $trfSizeAndCountFile, $retryinfo, $RestoreItemCheck, $jobCancelFile, $search, $errorDir]);
	restoreRestoresetFileConfiguration();

	my ($subjectLine) = getOpStatusNeSubLine();
	if ((-f $outputFilePath) and (!-z $outputFilePath)){
		my $finalOutFile = $outputFilePath;
		$finalOutFile =~ s/_Running_/_$status\_/;
		move($outputFilePath, $finalOutFile);

		if (Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
			Common::setNotification('update_restore_progress', ((split("/", $finalOutFile))[-1]));
			Common::setNotification('get_logs') and Common::saveNotifications();
			Common::unlockCriticalUpdate("notification");
		}

		$outputFilePath = $finalOutFile;

		$finalSummary .= Constants->CONST->{moreDetailsReferLog}.qq(\n);# Concat log file path with job summary. To access both at once while displaying the summary and log file location.
		$finalSummary .= $status."\n".$errStr;
		#if($silentFlag == 0){ #Commented by Senthil
			writeToFile($summaryFilePath,$finalSummary);
			chmod $filePermission, $summaryFilePath;
		#}
		#It is a generic function used to write content to file.
		if ($taskType eq "Manual" and $silentFlag == 0){
			# displayProgressBar($progressDetailsFile,Common::getTotalSize($fileForSize)) unless($isEmpty);
			displayFinalSummary(Common::getStringConstant('restore_job'), $summaryFilePath);
		}
		#This function display summary on stdout once backup job has completed.
		Common::saveLog($finalOutFile, 0);
	}
	if($isEmpty){
		sendMail($subjectLine,'NORESTOREDATA');
	} else {
		sendMail($subjectLine);
	}

    $errStr = Common::checkErrorAndLogout($errStr, undef, 1);
	#terminateStatusRetrievalScript($summaryFilePath) if ($taskType eq "Scheduled"); #Commented by Senthil
	$operationsfile = $jobRunningDir.'/operationsfile.txt';
	my $doBackupOperationErrorFile = "$jobRunningDir/doBackuperror.txt_";
	# unlink($totalFileCountFile);
	Common::removeItems([$info_file, $idevsErrorFile."*", $idevsOutputFile,"*", $statusFilePath."*", $utf8Files."*", $operationsfile."*", $doBackupOperationErrorFile."*", $RestoresetFile_relative."*", $noRelativeFileset."*", $filesOnly."*", $pidPath."*", $RestoreSetJsonFile ]);
	unlink($engineLockFile);
	exit 0;
}

#******************************************************************************************************************
# Subroutine Name         : getOpStatusNeSubLine.
# Objective               : This subroutine returns restore operation status and email subject line
# Added By                : Dhritikana
# # Modified By           : Yogesh Kumar
#******************************************************************************************************************/
sub getOpStatusNeSubLine {
	my $subjectLine= "$taskType Restore Status Report ";
	my $totalNumFiles = $filesConsideredCount-$failedFilesCount;

	if ($status eq "Aborted") {
		$subjectLine .= sprintf("[%s][Aborted Restore]", Common::getUserConfiguration('EMAILADDRESS'));
	}
	elsif ($failedFilesCount == 0 and $filesConsideredCount > 0) {
		$subjectLine .= sprintf("[%s][Successful Restore]", Common::getUserConfiguration('EMAILADDRESS'));
	}
	else {
		$subjectLine .= sprintf("[%s][Failed Restore]", Common::getUserConfiguration('EMAILADDRESS'));
	}
	return ($subjectLine);
}

#*******************************************************************************************************
# Subroutine Name         :	restoreRestoresetFileConfiguration
# Objective               :	This subroutine moves the RestoresetFile to the original configuration.
# Added By                :
#********************************************************************************************************
sub restoreRestoresetFileConfiguration()
{
	if($RestoresetFile_relative ne "") {
		unlink <"$RestoresetFile_relative"*>;
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
	# unlink "$info_file";
}

#*******************************************************************************************************
# Subroutine Name         :	updateServerAddr
# Objective               :	handling wrong server address error msg
# Added By                : Dhritikana
#********************************************************************************************************
sub updateServerAddr {
	my $tempErrorFileSize = undef;
	if($_[0]) {
		$tempErrorFileSize = -s $_[0];
	} else {
		$tempErrorFileSize = -s $idevsErrorFile;
	}
	if($tempErrorFileSize > 0) {
		my $errorPatternServerAddr = "unauthorized user|user information not found";
		open EVSERROR, "<", $idevsErrorFile or Common::traceLog("Failed to open error.txt Reason : $!");
		$errorContent = <EVSERROR>;
		close EVSERROR;
		if($errorContent =~ m/$errorPatternServerAddr/){
			# if (!(getServerAddr())){
				# Common::updateAccountStatus(Common::getUsername(), 'UA');
				# exit_cleanup($errStr);
				# return 1;
			# }
			
			if(Common::saveServerAddress(Common::fetchServerAddress())) {
				Common::loadServerAddress();
				return 0;
			}
		}
	}
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : appendErrorToUserLog.
# Objective               : Enumeration of a folder from restore set file gets fail then write
#							proper error message to log file.
# Added By                : Avinash Kumar.
#*****************************************************************************************************/
sub appendErrorToUserLog {
	# open log file to append serach failure message.
	if (!open(OUTFILE, ">> $outputFilePath")) {
		Common::traceLog("Could not open file $outputFilePath to append search error message for folder ".$_[0].", Reason:$!");
	}
	else {
		print OUTFILE $_[0];
		close OUTFILE;
		chmod $filePermission, $outputFilePath;
	}
}

#*******************************************************************************************************
# Subroutine Name         :	createRestoreTypeFile
# Objective               :	Create files respective to restore types (relative or no relative)
# Added By                : Dhritikana
#********************************************************************************************************
sub createRestoreTypeFile {
	#opening info file for generateBackupsetFiles function to write backup set information and for main process to read that information
	if(!open(FD_WRITE, ">", $info_file)){
		$errStr = "Could not open file $info_file to write, Reason:$!\n";
		Common::traceLog($errStr) and die;
	}
	chmod $filePermission, $info_file;

	#Restore File name for mirror path
	if($relative != 0) {
		$RestoresetFile_new =  $RestoresetFile_relative;

		if(!open RESTORE_FILE, ">>", $RestoresetFile_new) {
			Common::traceLog(Constants->CONST->{'FileOpnErr'}." $RestoresetFile_new to write, Reason:$!.");
			print Constants->CONST->{'FileOpnErr'}." $RestoresetFile_new to write, Reason:$!. $lineFeed";
			exit(1);
		}
		chmod $filePermission, $RestoresetFile_new;
	}
	else {
		#Restore File Name only for files
		$RestoresetFile_Only =  $filesOnly;

		if(!open RESTORE_FILE, ">>", $RestoresetFile_Only) {
			Common::traceLog(Constants->CONST->{'FileOpnErr'}." $RestoresetFile_Only to write, Reason:$!.");
			exit(1);
		}
		chmod $filePermission, $RestoresetFile_Only;
		$RestoresetFile_new =  $noRelativeFileset;
	}
}

#*******************************************************************************************************
# Subroutine Name         :	updateRetryCount
# Objective               :	updates retry count based on recent backup files.
# Added By                : Avinash
# Modified By             : Dhritikana
#********************************************************************************************************/
sub updateRetryCount {
	my $curFailedCount = 0;
	my $currentTime = time();

	for(my $i=1; $i<= $totalEngineBackup; $i++){
		if(-e $statusFilePath."_".$i  and  -s $statusFilePath."_".$i>0){
			$curFailedCount = $curFailedCount+getParameterValueFromStatusFile($i, 'ERROR_COUNT_FILES');
			undef @linesStatusFile;
		}
	}

	if($curFailedCount < $prevFailedCount) {
		$retrycount = 0;
	}
	else {
		if($currentTime-$prevTime < 90) {
			sleep 10;
		}
		$retrycount++;
	}

	#assign the latest backuped and synced value to prev.
	$prevFailedCount = $curFailedCount;
	$prevTime = $currentTime;
}

#****************************************************************************************************
# Subroutine Name         : checkExitError.
# Objective               : This function will display the proper error message if evs error found in Exit argument.
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub checkExitError
{
	my $errorline = "idevs error";
	my $individual_errorfile = $_[0];

	if(!-e $individual_errorfile) {
		return 0;
	}
	#check for retry attempt
	if(!open(TEMPERRORFILE, "< $individual_errorfile")) {
		Common::traceLog("Could not open file individual_errorfile in checkretryAttempt: $individual_errorfile, Reason:$!");
		return 0;
	}

	@linesBackupErrorFile = <TEMPERRORFILE>;
	close TEMPERRORFILE;
	chomp(@linesBackupErrorFile);
	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;

		if($linesBackupErrorFile[$i] eq "" or $linesBackupErrorFile[$i] =~ m/$errorline/){
			next;
		}

		for(my $j=0; $j<=$#ErrorArgumentsExit; $j++)
		{
			if($linesBackupErrorFile[$i] =~ m/$ErrorArgumentsExit[$j]/)
			{
				$errStr  = "Operation could not be completed. Reason : $ErrorArgumentsExit[$j].";
				#$errStr .= "Please login using login.pl script.";
				Common::traceLog($errStr);
				#kill evs and then exit
				my $jobTerminationPath = $currentDir.'/'.Constants->FILE_NAMES->{jobTerminationScript};
				my $jobToTerm = lc($jobType);
				system(Common::updateLocaleCmd("$perlPath \'$jobTerminationPath\' \'$jobToTerm\' \'$userName\' 1>/dev/null 2>/dev/null"));

				$exit_flag = "1-$errStr";
				#unlink($pwdPath);
				return 0;
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine	: displayRestoreProgress
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Reads the input and processes the input
# Added By		: Senthil Pandian
#*****************************************************************************************************
sub displayRestoreProgress {
    my $keyPressEvent = Common::catchPressedKey();
    $pidOperationFlag = "DisplayProgress";
    my $temp = $totalEngineBackup;
    my $redrawForLess = 0;
    my $vrestsize	  = 0;
    my $moreOrLess    = 'less';
    $moreOrLess = 'more' if(Common::checkScreeSize());

    while(1){
        Common::displayProgressBar($progressDetailsFile, undef, undef, $moreOrLess, $redrawForLess);
        $redrawForLess = 0;
        last if(!-e $pidPath);

        #select(undef, undef, undef, 0.100);
        Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);# Sleep for 100/500 milliseconds
        if($keyPressEvent->(1)) {
            # if(($playPause eq 'running') && ($AppConfig::pressedKeyValue eq 'p')) {
                # Common::pauseOrResumeEVSOp($jobRunningDir,'p');
                # $playPause = 'paused';
                # $totalEngineBackup = 1; #To avoid active progress move
            # } elsif(($playPause eq 'paused') && ($AppConfig::pressedKeyValue eq 'r')) {
                # Common::pauseOrResumeEVSOp($jobRunningDir,'r');
                # $playPause = 'running';
                # $totalEngineBackup = $temp; #Restoring the actual engine count
            # }

            if(($moreOrLess eq 'more') && ($AppConfig::pressedKeyValue eq '-')) {
                $moreOrLess = 'less';
                $redrawForLess = 1;
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
            } elsif(($moreOrLess eq 'less') && ($AppConfig::pressedKeyValue eq '+')) {
                $moreOrLess = 'more' if(Common::checkScreeSize());
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
            }
        }
=beg
        if($RestoreFileName =~ m/versionRestore/ && !$vrestsize) {
            # Works only in restore version case
            my $progfile = $progressDetailsFile . '_1';
            if(-f $progfile) {
                my $progdata = Common::getFileContents($progfile, 'array');
                if($#progdata) {
                    if($progdata->[9]) {
                        Common::fileWrite($fileForSize, $progdata->[9]);
                        $vrestsize = 1;
                    }
                }
            }
        }
=cut
    }

    $keyPressEvent->(0);
    $AppConfig::pressedKeyValue = '';			
    # displayProgressBar($progressDetailsFile, undef, undef, $moreOrLess, $redrawForLess);
    Common::displayProgressBar($progressDetailsFile,undef,undef,$moreOrLess,$redrawForLess)  if($playPause ne 'paused' || $drawForPlayPause);
}

#*****************************************************************************************************
# Subroutine	: displayFolderVersionRestoreProgress
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Reads the input and processes the input
# Added By		: Senthil Pandian
#*****************************************************************************************************
sub displayFolderVersionRestoreProgress {
    my $keyPressEvent = Common::catchPressedKey();
    $pidOperationFlag = "DisplayProgress";
    my $temp = $totalEngineBackup;
    # our ($cumulativeCount, $cumulativeTransRate) = (0)x2;
    my $redrawForLess = 0;
    my $vrestsize	  = 0;
    my $moreOrLess    = 'less';
    $moreOrLess = 'more' if(Common::checkScreeSize());

    while(1){
        Common::displayFolderVersionProgressBar($progressDetailsFile, undef, undef, $moreOrLess, $redrawForLess);
        $redrawForLess = 0;
        last if(!-e $pidPath);

        #select(undef, undef, undef, 0.100);
        Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);# Sleep for 100/500 milliseconds
        if($keyPressEvent->(1)) {
            if(($moreOrLess eq 'more') && ($AppConfig::pressedKeyValue eq '-')) {
                $moreOrLess = 'less';
                $redrawForLess = 1;
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
            } elsif(($moreOrLess eq 'less') && ($AppConfig::pressedKeyValue eq '+')) {
                $moreOrLess = 'more' if(Common::checkScreeSize());
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
            }
        }
    }

    $keyPressEvent->(0);
    $AppConfig::pressedKeyValue = '';			
    # displayProgressBar($progressDetailsFile, undef, undef, $moreOrLess, $redrawForLess);
    Common::displayFolderVersionProgressBar($progressDetailsFile,undef,undef,$moreOrLess,$redrawForLess)  if($playPause ne 'paused' || $drawForPlayPause);
}

#*****************************************************************************************************
# Subroutine	: getSnapshotSearchResult
# In Param		: item, endDate
# Out Param		: 
# Objective		: Start snapshot search operation
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub getSnapshotSearchResult {
	my $item    = $_[0];
	my $endDate = $_[1];
	
}