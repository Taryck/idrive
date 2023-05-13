#!/usr/bin/env perl
#-------------------------------------------------------------------------------
# Easily restore the bulk data from cloud account to Linux machines via physical storage shipment.
#
# Created By : Senthil Pandian
# Reviewed By: 
#-------------------------------------------------------------------------------
use strict;
use POSIX qw/mktime/;
use POSIX ":sys_wait_h";
use FileHandle;
use utf8;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;

# use Data::Dumper;

my $cmdNumOfArgs = $#ARGV;
my $jobType  = 'manual';
my $relative = 0;
my ($silentRestoreFlag,$isScheduledJob,$filesOnlyCount,$exitStatus,$prevFailedCount,$noRelIndex) = (0) x 6;
my ($Restorefilecount, $filecount, $retry_failedfiles_index, $isEmpty) = (0) x 4;
my ($displayProgressBarPid,$mountedPath,$RestoresetFile_new,$filehandle,$filehandle_org,$RestoresetFile_Only);
my ($generateFilesPid,$totalFiles,@restoreForkchilds,$restoresetFilePath);
my $engineID = 1;
my $current_source = "/";
my $playPause = 'running';

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

init();

#*******************************************************************************
# This script starts & ends in init()
#
# Added By   	: Senthil Pandian
# Modified By	: Sabin Cheruvattil
#*******************************************************************************
sub init {
	system("clear") and Common::retreat('failed_to_clear_screen') unless ($cmdNumOfArgs > -1);
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	if ($cmdNumOfArgs > -1) {
		if ((${ARGV[0]} eq "SCHEDULED") or (${ARGV[0]} eq "immediate")) {
			$AppConfig::callerEnv = 'BACKGROUND';
			Common::setUsername($ARGV[1]);
			$jobType = 'scheduled';
			$silentRestoreFlag = 1;
			$isScheduledJob = 1;
			Common::loadUserConfiguration();
		} 
		elsif (${ARGV[0]} eq '--silent' or ${ARGV[0]} eq 'dashboard' or ${ARGV[0]} eq 'immediate') {
			$AppConfig::callerEnv = 'BACKGROUND';
			$silentRestoreFlag = 1;
		}
	}

	if ($jobType eq 'manual') {
		Common::loadUsername() or Common::retreat('login_&_try_again');
		my $errorKey = Common::loadUserConfiguration();
		Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey != 1);		
	}	

	unless ($silentRestoreFlag) {
		Common::isLoggedin() or Common::retreat('login_&_try_again');
		Common::displayHeader();
	}
	my $username      = Common::getUsername();
	my $servicePath   = Common::getServicePath();
	my $jobRunningDir = Common::getUsersInternalDirPath('localrestore');
	$AppConfig::jobRunningDir = $jobRunningDir;
	$AppConfig::jobType		  = "LocalRestore";

	Common::loadEVSBinary() or Common::retreat('unable_to_find_or_execute_evs_binary');
	
	my $dedup  	      = Common::getUserConfiguration('DEDUP');
	my $serverRoot    = Common::getUserConfiguration('LOCALRESTORESERVERROOT');
	my $restoreLoc	  = Common::getUserConfiguration('RESTORELOCATION');
	# if($dedup eq 'on' and !$serverRoot){
	    ####($restoreLoc,my $deviceID)  = split("#",$restoreLoc);
		# Common::display(["\n",'verifying_your_account_info',"\n"]);
		# my %evsDeviceHashOutput = Common::getDeviceHash();
		# my $uniqueID = Common::getMachineUID() or Common::retreat('failed_to_get_machine_uid');
		# $uniqueID .= "_1";
		# if(exists($evsDeviceHashOutput{$uniqueID})){
			# $serverRoot  = $evsDeviceHashOutput{$uniqueID}{'server_root'};
			# Common::setUserConfiguration('SERVERROOT', $serverRoot);
			# Common::saveUserConfiguration() or Common::retreat('failed_to_save_user_configuration');
		# }

		# if(!$serverRoot){
			# Common::display(["\n",'your_account_not_configured_properly',"\n"])  unless ($silentRestoreFlag);
			# Common::traceLog(Common::getStringConstant('your_account_not_configured_properly'));
			# exit 1;
		# }
	# }
	Common::createDir($jobRunningDir, 1);

	# Checking if another job is already in progress
	my $pidPath = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
	if (Common::isFileLocked($pidPath)) {
		Common::retreat('local_restore_running', $silentRestoreFlag);
	}

	my $lockStatus = Common::fileLock($pidPath);
	Common::retreat([$lockStatus.'_file_lock_status', ": ", $pidPath]) if($lockStatus);

	#Renaming the log file if backup process terminated improperly
	Common::checkAndRenameFileWithStatus($jobRunningDir, 'localrestore');

	removeIntermediateFiles(); # pre cleanup for all intermediate files and folders.
	my $totalFileCountFile      = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::totalFileCountFile);
    my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::progressDetailsFilePath);
	Common::removeItems([$totalFileCountFile, $progressDetailsFilePath.'*']);

	my $restoresetFile     = Common::getCatfile($jobRunningDir, $AppConfig::restoresetFile);
	$isEmpty = Common::checkPreReq($restoresetFile, lc($AppConfig::jobType), 'NORESTOREDATA');
	if($isEmpty and $isScheduledJob == 0 and $silentRestoreFlag == 0) {
		unlink($pidPath);
		Common::retreat(["\n",$AppConfig::errStr]) 
	} else {
		$AppConfig::errStr = '';
	}

	#Added to handle for schema changed for 360
	my($schemaStat, $dbPath) = Common::isExpressDBschemaChanged('localrestore');
	if($schemaStat) {
		Common::traceLog('ExpressDBschemaChanged. Renaming DB '.$dbPath);
		system("mv '$dbPath' '$dbPath'"."_bak") if(-f $dbPath);
	};

    $mountedPath = Common::getUserConfiguration('LOCALRESTOREMOUNTPOINT');

	# Common::display(['your_previous_mount_point',"'$mountedPath'."]);
	$AppConfig::localMountPath	= $mountedPath;
	Common::checkPidAndExit(); #Checking pid if process cancelled by job termination

	my $expressLocalDir = Common::getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   = Common::getCatfile($expressLocalDir, $username);
	my $ldbNewDirPath	= Common::getCatfile($localUserPath, $AppConfig::ldbNew);
	my $dbPathsXML	    = Common::getCatfile($localUserPath, $AppConfig::dbPathsXML);
    $AppConfig::expressLocalDir = $expressLocalDir;

	if(!-d $ldbNewDirPath or ($dedup eq 'on' and !-e $dbPathsXML)){
		Common::startDBReIndex($mountedPath);
	}
	if($dedup eq 'on' and !-e $dbPathsXML) {
		Common::retreat(['mount_point_doesnt_have_user_data',"\n"]);
	}

	#Start creating required file/folder
	my $errorDir       = Common::getCatfile($jobRunningDir, $AppConfig::errorDir);
	Common::createDir($errorDir, 0);
	my $serverAddress = Common::getServerAddress();
	unless ($serverAddress){
		exitCleanup($AppConfig::errStr);
	}

	Common::createLogFiles("RESTORE",ucfirst($jobType));
	createRestoreTypeFile();
	# Common::editLocalRestoreFromLocation();
    # Common::display(""); #Added to keep newline symmetric
	Common::checkPidAndExit(); #Checking pid if process cancelled by job termination
	# Common::getAvailableBucketsInMountPoint();

	if($dedup eq 'on'){
		$serverRoot = Common::getUserConfiguration('LOCALRESTORESERVERROOT');
	}
    
    # my $restoreFrom  = Common::getUserConfiguration('LOCALRESTOREFROM');
	# Common::display(['your_local_restore_from_device_is', "'$restoreFrom'. \n\n"]);

    my $databaseLB   = Common::getExpressDBPath($mountedPath,$serverRoot);
    my $restoreFrom  = ($dedup eq 'on')?$serverRoot:Common::getUserConfiguration('LOCALRESTOREFROM');
	my $backedUpData = Common::getCatfile($localUserPath, $restoreFrom);

    if(!-d $backedUpData){
        $restoreFrom  = Common::getUserConfiguration('LOCALRESTOREFROM');
        if ($dedup eq 'on') {
            $restoreFrom = (split('#',$restoreFrom))[1] if ($restoreFrom =~ /#/);
        }	        
        my $error = Common::getStringConstant('local_restore_from_doesnt_have_data');
        $error =~ s/<DATA>/$restoreFrom/; 
		Common::retreat($error);
	}

=beg
	if(-d $backedUpData and !-f $databaseLB){
		Common::startDBReIndex($mountedPath);
	}

	if(!-e $databaseLB){
		Common::display('No database');
		exitCleanup('No database');
	}
=cut
	if (Common::getUserConfiguration('RESTORELOCATIONPROMPT')) {
        Common::editRestoreLocation(1) unless ($silentRestoreFlag);
        my $restloc = Common::getUserConfiguration('RESTORELOCATION');
		utf8::decode($restloc);

		unless(-w $restloc) {
            $AppConfig::errStr = Common::getStringConstant('operation_could_not_be_completed_reason').Common::getStringConstant('invalid_restore_location');
            Common::retreat(["\n",$AppConfig::errStr]) unless ($silentRestoreFlag);
        } else {
            Common::display("");
            sleep(2);
        }
	}

	Common::getCursorPos(15,Common::getStringConstant('preparing_file_list')) if (!$silentRestoreFlag and !$isEmpty and -e $pidPath);
	$AppConfig::mailContentHead = Common::writeLogHeader($jobType);
	if (Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
		Common::setNotification('update_localrestore_progress', ((split("/", $AppConfig::outputFilePath))[-1]));
		Common::saveNotifications();
		Common::unlockCriticalUpdate("notification");
	}

    #Verify DB & start DB ReIndex
	my $dbReindexDir = Common::getUsersInternalDirPath('dbreindex');
	my $dbReindexPid = $dbReindexDir."/".$AppConfig::pidFile;
	if((-d $backedUpData and !-f $databaseLB) or -f $dbReindexPid) {
        Common::display('');
		Common::startDBReIndex($mountedPath);
	}
	if(!-e $databaseLB) {
		Common::display('No database');
		exitCleanup('No database');
	}

	Common::writeAsJSON($totalFileCountFile, {});
	# Common::getCursorPos(40,"") if(-e $pidPath); #Resetting cursor position
	startRestore() if(!$isEmpty and -e $pidPath and !$AppConfig::errStr);
	exitCleanup($AppConfig::errStr);
}

#****************************************************************************************************
# Subroutine Name : startRestore
# Objective       : This function will fork a child process to generate restoreset files and get
#			    count of total files considered. Another forked process will perform main
#			    restore operation of all the generated restoreset files one by one.
# Added By		  : Senthil Pandian
#*****************************************************************************************************/
sub startRestore {
	my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::progressDetailsFilePath);
	my $pidPath	= Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
	$generateFilesPid = fork();

	if(!defined $generateFilesPid) {
		Common::traceLog(['cannot_fork_child', "\n"]);
		Common::display(['cannot_fork_child', "\n"]) unless ($silentRestoreFlag);
		return 0;
	}

	if($generateFilesPid == 0) {
		generateRestoresetFiles();
        exit(0);
	}

	if($isScheduledJob == 0 and $silentRestoreFlag == 0){
		$displayProgressBarPid = fork();

		if(!defined $displayProgressBarPid) {
			$AppConfig::errStr = Common::getStringConstant('unable_to_display_progress_bar');
			Common::traceLog($AppConfig::errStr);
			return 0;
		}

		if($displayProgressBarPid == 0) {
            displayRestoreProgress();
			exit(0);
		}
	}

	my $info_file = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);
	my $retryInfo = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::retryInfo);
	my $maxNumRetryAttempts = 1000;
	my $engineLockFile = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	my $line = '';
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;

	open(my $handle, '>', $engineLockFile) or traceLog("\n Could not open file '$engineLockFile' $! \n", __FILE__, __LINE__);
	close $handle;
	chmod $AppConfig::filePermission, $engineLockFile;
	my $exec_cores = Common::getSystemCpuCores();
	my $exec_loads;

START:
	if(!open(FD_READ, "<", $info_file)) {
		$AppConfig::errStr = Common::getStringConstant('failed_to_open_file')." info_file in startRestore: $info_file to read, Reason $! \n";
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
            my $outputHeading = Common::getStringConstant('heading_restore_output');
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
                    sleep(20);
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

            my $restorePid = fork();

            if(!defined $restorePid) {
                $AppConfig::errStr = "Cannot fork() child process :  for EVS \n";
                return RESTORE_PID_FAIL;
            }
            elsif($restorePid == 0) {
                # Common::traceLog("doRestoreOperation:$line");
                my $retType = Common::doRestoreOperation($line, $silentRestoreFlag, $jobType,$engineID,$retry_failedfiles_index);
                exit(0);
            }
            else{
                push (@restoreForkchilds, $restorePid);
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

        foreach (@restoreForkchilds) {
            my $res = waitpid($_, WNOHANG);
            if ($res > 0 or $res == -1) {
                @restoreForkchilds = grep(!/$_/, @restoreForkchilds);
            }
        }
	}

	waitForEnginesToFinish();
	close FD_READ;

	my $failedCount = Common::readInfoFile('FAILEDCOUNT');
	$AppConfig::nonExistsCount = $failedCount;

	waitpid($generateFilesPid,0);

	undef @AppConfig::linesStatusFile;
	if($totalFiles == 0 or $totalFiles !~ /\d+/) {
		$totalFiles = Common::readInfoFile('TOTALFILES');
		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			Common::traceLog("Unable to get total files count");
		}
	}
	$AppConfig::totalFiles = $totalFiles;

	if ((-f $retryInfo && -s $retryInfo > 0) && -e $pidPath && $AppConfig::retryCount <= $maxNumRetryAttempts && $exitStatus == 0) {
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
			$AppConfig::errStr = Common::getStringConstant('failed_to_open_file')." info_file in startRestore : $info_file, Reason $!\n";
			return $AppConfig::errStr;
		}
		print INFO "TOTALFILES $totalFiles\n";
		print INFO "FAILEDCOUNT $failedCount\n";
		close INFO;
		chmod $AppConfig::filePermission, $info_file;
		sleep 5; #5 Sec
		Common::traceLog("retrycount:".$AppConfig::retryCount);
		Common::loadUserConfiguration(); #Reloading to handle domain connection failure case
		goto START;
	}
}

#****************************************************************************************************
# Subroutine Name         : removeIntermediateFiles.
# Objective               : This function will remove all the intermediate files/folders
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub removeIntermediateFiles {
	# my $evsTempDirPath  = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::evsTempDir);
	my $statusFilePath  = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::statusFile);
	my $retryInfo       = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::retryInfo);
	my $failedFiles     = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::failedFileName);
	my $infoFile        = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::infoFile);
	my $filesOnly	    = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFileOnlyFiles);
	my $incSize 		= Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::transferredFileSize);
	my $errorDir 		= Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::errorDir);

	my $relativeFileset     = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::relativeFileset);
	my $noRelativeFileset  	= Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFileNoRelative);
	# my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::progressDetailsFilePath);
	my $engineLockFile = Common::getCatfile($AppConfig::jobRunningDir,AppConfig::ENGINE_LOCKE_FILE);

	my $idevsOutputFile	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsOutputFile;
	my $idevsErrorFile 	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsErrorFile;
	my $backupUTFpath   	= $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
	my $operationsFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::operationsfile;
	my $doBackupOperationErrorFile = $AppConfig::jobRunningDir."/doBackuperror.txt_";
	my $minimalErrorRetry = $AppConfig::jobRunningDir."/".$AppConfig::minimalErrorRetry;
    my $exitErrorFile     = $AppConfig::jobRunningDir."/".$AppConfig::exitErrorFile;

	my $fileForSize	= Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::fileForSize);
	#system("rm -rf '$evsTempDirPath' '$relativeFileset'* '$noRelativeFileset'* '$filesOnly'* '$infoFile' '$retryInfo' '$errorDir' '$statusFilePath' '$incSize' '$failedFiles'*");
	Common::removeItems([$errorDir, $statusFilePath, $incSize, $infoFile, $retryInfo, $statusFilePath."*", $failedFiles."*", $relativeFileset."*", $noRelativeFileset."*", $filesOnly."*", $fileForSize]);
	Common::removeItems([$idevsErrorFile.'*', $idevsOutputFile.'*', $backupUTFpath.'*', $operationsFilePath.'*', $doBackupOperationErrorFile.'*', $minimalErrorRetry, $exitErrorFile]);

	return 0;
}

###################################################
#The signal handler invoked when SIGINT or SIGTERM#
#signal is received by the script                 #
###################################################
sub processTerm()
{
	system("stty $AppConfig::stty") if($AppConfig::stty);	# restore 'cooked' mode
	my $pidPath  = $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
	unlink($pidPath) if(-f $pidPath);
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
	cancelRestoreSubRoutine();
	exit(0);
}

#****************************************************************************************************
# Subroutine Name         : cancelRestoreSubRoutine.
# Objective               : This function will cancel the execution of local restore script.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub cancelRestoreSubRoutine()
{
	my $restoreUTFpath = $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
	my $info_file      = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;
	exit(0)	if($AppConfig::pidOperationFlag eq "EVS_process");

	if($AppConfig::pidOperationFlag eq "GenerateFile")  {
		open FD_WRITE, ">>", $info_file or (print Common::getStringConstant('failed_to_open_file')." info_file in cancelSubRoutine: $info_file to write, Reason:$!"); # die handle?
		autoflush FD_WRITE;
		#print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "TOTALFILES $AppConfig::totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $AppConfig::nonExistsCount\n";
		close(FD_WRITE);
		# close NEWFILE;
		$AppConfig::pidOperationFlag ='';
		exit(0);
	}

    #Added to prevent multiple exit cleanup calls due to fork processes
    exit(0) if($AppConfig::pidOperationFlag =~ /DisplayProgress|ChildProcess|ExitCleanup/);

	waitpid($generateFilesPid,0) if($generateFilesPid);
	if(-e $info_file and (!defined($totalFiles) or $totalFiles !~ /\d+/ or $totalFiles == 0)) {
		my $fileCountCmd = "cat '$info_file' | grep -m1 \"^TOTALFILES\"";
		$totalFiles = `$fileCountCmd`;
		$totalFiles =~ s/TOTALFILES//;
		chomp($totalFiles) if($totalFiles ne '');
	}

	if(!defined($totalFiles) or ($totalFiles !~ /\d+/) or ($totalFiles == 0)) {
		Common::traceLog(" Unable to get total files count");
	} else {
		$AppConfig::totalFiles = $totalFiles;
	}

	if($AppConfig::nonExistsCount == 0 and -e $info_file) {
		my $nonExistCheckCmd = "cat '$info_file' | grep -m1 \"^FAILEDCOUNT\"";
		$AppConfig::nonExistsCount = `$nonExistCheckCmd`;
		$AppConfig::nonExistsCount =~ s/FAILEDCOUNT//;
		Common::Chomp(\$AppConfig::nonExistsCount);
	}
	
	$restoreUTFpath =~ s/\[/\\[/;
	$restoreUTFpath =~ s/{/[{]/;
	my $psOption = Common::getPSoption();
	my $evsCmd   = "ps $psOption | grep \"$AppConfig::evsBinaryName\" | grep \'$restoreUTFpath\'";
	my $evsRunning  = `$evsCmd`;
	my @evsRunningArr = split("\n", $evsRunning);
	my $arrayData = 3;
	if($Common::machineInfo =~ /freebsd/i){
		$arrayData = 1;
	}

	foreach(@evsRunningArr) {
		if($_ =~ /$evsCmd|grep/) {
			next;
		}
		my $pid = (split(/[\s\t]+/, $_))[$arrayData];
		my $scriptTerm = system("kill -9 $pid");

		if(defined($scriptTerm)) {
			if($scriptTerm != 0 && $scriptTerm ne "") {
				my $msg = Common::getStringConstant('failed_to_kil')." Restore\n";
				Common::traceLog($msg);
			}
		}
	}
	waitpid($AppConfig::pidOutputProcess, 0) if($AppConfig::pidOutputProcess);
	exitCleanup($AppConfig::errStr);
}

#****************************************************************************************************
# Subroutine Name         : exitCleanup.
# Objective               : This function will execute the major functions required at the time of exit
# Added By                : Senthil Pandian
# Modified By			  : Sabin Cheruvattil
#*****************************************************************************************************/
sub exitCleanup {
    $AppConfig::pidOperationFlag = 'ExitCleanup';

	my $pidPath 			= $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
	my $idevsOutputFile	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsOutputFile;
	my $idevsErrorFile 	 	= $AppConfig::jobRunningDir."/".$AppConfig::evsErrorFile;
	my $backupUTFpath   	= $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File;
	my $statusFilePath  	= $AppConfig::jobRunningDir."/".$AppConfig::statusFile;
	my $operationsFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::operationsfile;
	my $relativeFileset     = $AppConfig::jobRunningDir."/".$AppConfig::relativeFileset;
	my $noRelativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::restoresetFileNoRelative;
	my $filesOnly		    = $AppConfig::jobRunningDir."/".$AppConfig::restoresetFileOnlyFiles;
	my $pwdPath 			= Common::getIDPWDFile();
	my $retryInfo       	= $AppConfig::jobRunningDir."/".$AppConfig::retryInfo;
	my $incSize 			= $AppConfig::jobRunningDir."/".$AppConfig::transferredFileSize;
	my $fileForSize		    = $AppConfig::jobRunningDir."/".$AppConfig::fileForSize;
	my $trfSizeAndCountFile = $AppConfig::jobRunningDir."/".$AppConfig::trfSizeAndCountFile;
	# my $evsTempDirPath  	= $AppConfig::jobRunningDir."/".$AppConfig::evsTempDir;
	my $errorDir 		    = $AppConfig::jobRunningDir."/".$AppConfig::errorDir;
	my $fileSummaryFilePath = $AppConfig::jobRunningDir."/".$AppConfig::fileSummaryFile;
	my $engineLockFile 		= $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	my $progressDetailsFilePath    = $AppConfig::jobRunningDir."/".$AppConfig::progressDetailsFilePath;
	
	my $doBackupOperationErrorFile = $AppConfig::jobRunningDir."/doBackuperror.txt_";
	
	if($silentRestoreFlag == 0){
		system('stty', 'echo');
		system("tput sgr0");
	}
	my $displayJobFailMessage = undef;
	
	my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','EXIT_FLAG_INDEX');
	my ($successFiles, $syncedFiles, $failedFilesCount,$exit_flag) = Common::getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
	chomp($exit_flag);
	if($AppConfig::errStr eq "" and -e $AppConfig::errorFilePath) {
		open ERR, "<$AppConfig::errorFilePath" or Common::traceLog(Common::getStringConstant('failed_to_open_file')."errorFilePath in exitCleanup: $AppConfig::errorFilePath, Reason: $!");
		$AppConfig::errStr .= <ERR>;
		close(ERR);
		chomp($AppConfig::errStr);
	}

	if(!-e $pidPath or $exit_flag) {
		$AppConfig::cancelFlag = 1;

		# In childprocess, if we exit due to some exit scenario, then this exit_flag will be true with error msg
		my @exit = split("-",$exit_flag,2);
		Common::traceLog(" exit_flag = $exit_flag");
		if(!$exit[0]){
			if ($jobType eq 'scheduled') {
				$AppConfig::errStr = Common::getStringConstant('operation_cancelled_due_to_cutoff');
				my $checkJobTerminationMode = $AppConfig::jobRunningDir.'/cancel.txt';
				if (-e $checkJobTerminationMode and (-s $checkJobTerminationMode > 0)){
				        open (FH, "<$checkJobTerminationMode") or die $!;
				        my @errStr = <FH>;
				        chomp(@errStr);
				        $AppConfig::errStr = $AppConfig::errStr[0] if (defined $AppConfig::errStr[0]);
				}
				unlink($checkJobTerminationMode);
			}
			elsif ($jobType eq 'manual') {
				$AppConfig::errStr = Common::getStringConstant('operation_cancelled_by_user');
			}
		}
		else {
			if ($exit[1] ne '') {
				$AppConfig::errStr = $exit[1];
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
					$AppConfig::errStr = $AppConfig::errStr.' '.Common::getStringConstant('invalid_res_loc_edit_loc_acc_settings')."\n";
				} else {
					$AppConfig::errStr = Common::checkErrorAndLogout($AppConfig::errStr);
				}
			}
		}
	}	

	unlink($pidPath);
	waitpid($displayProgressBarPid,0) if($displayProgressBarPid);
	wait();
	Common::writeOperationSummary($AppConfig::evsOperations{'LocalRestoreOp'}, $jobType);
	my $subjectLine = Common::getEmailSubLine($jobType, Common::getStringConstant('localrestore'));
	unlink($retryInfo);
	unlink($incSize);
	unlink($fileForSize);
	unlink($trfSizeAndCountFile);
	unlink($engineLockFile);
	
	Common::restoreBackupsetFileConfiguration();
	# if(-d $evsTempDirPath) {
		# Common::rmtree($evsTempDirPath);
	# }
	if(-d $errorDir and $errorDir ne '/') {
		system("rm -rf '$errorDir'");
	}
	
	if ((-f $AppConfig::outputFilePath) and (!-z $AppConfig::outputFilePath)) {
		my $finalOutFile = $AppConfig::outputFilePath;
		$finalOutFile =~ s/_Running_/_$AppConfig::opStatus\_/;
		Common::move($AppConfig::outputFilePath, $finalOutFile);

		if (Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
			Common::setNotification('update_localrestore_progress', ((split("/", $finalOutFile))[-1]));
			Common::setNotification('get_logs') and Common::saveNotifications();
			Common::unlockCriticalUpdate("notification");
		}

		$AppConfig::outputFilePath = $finalOutFile;
		$AppConfig::finalSummary .= Common::getStringConstant('for_more_details_refer_the_log').qq(\n);
		#Concat log file path with job summary. To access both at once while displaying the summery and log file location.
		$AppConfig::finalSummary .= $AppConfig::opStatus."\n".$AppConfig::errStr;
		Common::fileWrite($fileSummaryFilePath, $AppConfig::finalSummary); #It is a generic function used to write content to file.
		if ($silentRestoreFlag == 0){
			# Common::displayProgressBar($progressDetailsFilePath,undef,$playPause) unless ($isEmpty);
			Common::displayFinalSummary(Common::getStringConstant('localrestore_job'), $fileSummaryFilePath);
			#Above function display summary on stdout once backup job has completed.
		}

		Common::saveLog($finalOutFile, 0);
	}
=beg
	Common::sendMail({
		'serviceType' => $jobType,
		'jobType' => Common::getStringConstant('localrestore'),
		'subject' => $subjectLine,
		'jobStatus' => lc($AppConfig::opStatus)
	});
=cut	
	# Common::removeItems([ $pidPath."*", $idevsOutputFile."*", $idevsErrorFile."*", $backupUTFpath."*", $statusFilePath."*", $operationsFilePath."*", $relativeFileset."*", $noRelativeFileset."*", $filesOnly."*", $doBackupOperationErrorFile."*" ]);
	Common::removeItems($pidPath."*");
	removeIntermediateFiles();

	exit 0;
}

#****************************************************************************************************
# Subroutine Name         : generateRestoresetFiles.
# Objective               : This function will generate restoreset files.
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub generateRestoresetFiles {
	my $restoresetFilePath = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFile);
	my $errorDir = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::errorDir);
	#my $tmpDir   = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::tmpPath);
	#Common::createDir($tmpDir,1);
	my $dedup	 = Common::getUserConfiguration('DEDUP');
	
	my $restoresetFile_relative = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFileRelative);
	my $noRelativeFileset		= Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFileNoRelative);
	my $filesOnly				= Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFileOnlyFiles);
	my $fileForSize				= Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::fileForSize);
	my $totalFileCountFile  	= Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::totalFileCountFile);

	#check if running for restore version pl, in that case no need of generate files.
	if($restoresetFilePath =~ m/versionRestore/) {
		if(!open(RFILE, "<", $restoresetFilePath)) {
			my $errStr = Common::getStringConstant('failed_to_open_file')." to read : $restoresetFilePath, Reason $!\n";
			Common::traceLog($errStr);
		}

		my $Rdata = '';
		while(<RFILE>) {
			$Rdata .= $_;
		}
		my ($versionedFile, $totalSize) = split(/\n/, $Rdata);
		close(RFILE);
		if(!open(WFILE, ">", $restoresetFilePath)) {
			my $errStr = Common::getStringConstant('failed_to_open_file')." to write : $restoresetFilePath, Reason $!\n";
			Common::traceLog($errStr);
		}
		print WFILE $versionedFile."\n";
		close(WFILE);
 
		$AppConfig::totalSize = $totalSize;
		my $totalFiles = 1;
		$current_source = "/";
		print FD_WRITE "$current_source' '".Common::RELATIVE."' '$restoresetFilePath\n";
		goto GENEND;
	}
	
	my $serverRoot = ($dedup eq 'on')?Common::getUserConfiguration('LOCALRESTORESERVERROOT'):Common::getUserConfiguration('LOCALRESTOREFROM');
	my $dbpath = Common::getExpressDBPath($AppConfig::localMountPath,$serverRoot);

	my $dbfstate = Sqlite::createExpressDB($dbpath, 1);
	goto GENEND unless($dbfstate);

	Sqlite::initiateExpressDBoperation($dbpath);

	my $traceExist = $errorDir."/traceExist.txt";
	if(!open(TRACEERRORFILE, ">>", $traceExist)) {
		Common::traceLog(Common::getStringConstant('failed_to_open_file')." : $traceExist, Reason $!\n");
	}
	chmod $AppConfig::filePermission, $traceExist;

	$AppConfig::pidOperationFlag = "GenerateFile";
	my @itemsStat = checkRestoreItem();	

	my ($j, $idx) = (0) x 4;
	my ($current_source, $sourceIdx) = ('/') x 2;
	my @source;
	if(scalar(@itemsStat)) {
		foreach my $tmpLine (@itemsStat) {
			if(substr($tmpLine, -1, 1) eq "/") {
                chop($tmpLine);
				if($relative == 0) {
					$noRelIndex++;
					$RestoresetFile_new = $noRelativeFileset."$noRelIndex";
					$AppConfig::fileCount = 0;
					$sourceIdx = rindex ($tmpLine, '/');
					$source[$noRelIndex] = substr($tmpLine,0,$sourceIdx);
					if($source[$noRelIndex] eq "") {
						$source[$noRelIndex] = "/";
					}
					$current_source = $source[$noRelIndex];
                    $current_source =~ s/$serverRoot//;
					# $current_source = "/";
					if(!open $filehandle, ">>", $RestoresetFile_new){
						Common::traceLog(Common::getStringConstant('failed_to_open_file')." : $RestoresetFile_new, Reason $!\n");
						goto GENEND;
					}
					chmod $AppConfig::filePermission, $RestoresetFile_new;

					if(!open $filehandle_org, ">>", $RestoresetFile_new."_org"){
						Common::traceLog(Common::getStringConstant('failed_to_open_file')." : $RestoresetFile_new"."_org, Reason $!\n");
						goto GENEND;
					}
					chmod $AppConfig::filePermission, $RestoresetFile_new."_org";
				}
				my $resEnumerate = 0;
				$resEnumerate = enumerateFromDB($tmpLine);

                if($resEnumerate and $resEnumerate == REMOTE_SEARCH_THOUSANDS_FILES_SET_ERROR){
                    Common::traceLog("Error in creating 1k files $tmpLine");
                    goto GENEND;
                }

                if($relative == 0 && $AppConfig::fileCount>0) {
                    print FD_WRITE "$current_source' '".Common::RELATIVE."' '$RestoresetFile_new\n"; 
                    close $filehandle;
                    close $filehandle_org;
                }
			} else {
				unless(defined $AppConfig::fileInfoDB{$tmpLine}){
					next;
				}
				$AppConfig::totalSize+= $AppConfig::fileInfoDB{$tmpLine}{'FILE_SIZE'};
				$current_source = "/";
				my $filePath = $current_source.$AppConfig::fileInfoDB{$tmpLine}{'FOLDER_ID'}."/".$AppConfig::fileInfoDB{$tmpLine}{'ENC_NAME'};
				print RESTORE_FILE $filePath."\n";
# Common::traceLog("tmpLine:$tmpLine");				
				$tmpLine =~ s/$serverRoot//;
				$tmpLine = Common::removeMultipleSlashs($tmpLine);
				print RESTORE_FILE_ORG $tmpLine."\n";

				if($relative == 0) {
					$AppConfig::filesonlycount++;
					$AppConfig::fileCount = $AppConfig::filesonlycount;
				}
				else {
					$AppConfig::fileCount++;
				}
				$AppConfig::totalFiles++;
				if($AppConfig::fileCount == Common::FILE_MAX_COUNT) {
					$AppConfig::filesonlycount = 0;
					Common::traceLog('createRestoreSetFiles1k');
					if(!createRestoreSetFiles1k("FILESONLY")){
						goto GENEND;
					}
				}			
			}
		}
	}
 	close RESTORE_FILE;
	close RESTORE_FILE_ORG;   
    close $filehandle if($filehandle);
    close $filehandle_org if($filehandle_org);

	if($AppConfig::filesonlycount > 0 and !-z $RestoresetFile_Only){
		# $current_source = "/";
		print FD_WRITE "$current_source' '".Common::RELATIVE."' '$RestoresetFile_Only\n"; #[dynamic]
	}
	
GENEND:	
	autoflush FD_WRITE;
	print FD_WRITE "TOTALFILES $AppConfig::totalFiles\n";
	print FD_WRITE "FAILEDCOUNT $AppConfig::nonExistsCount\n";
	close(FD_WRITE);

	Common::fileWrite($fileForSize,$AppConfig::totalSize);
	# Common::fileWrite($totalFileCountFile,$AppConfig::totalFiles);	
	Common::loadAndWriteAsJSON($totalFileCountFile, {$AppConfig::totalFileKey => $AppConfig::totalFiles});
	# Common::traceLog('generateRestoresetFiles-END');
	$AppConfig::pidOperationFlag = "generateListFinish";
	close(TRACEERRORFILE);
	exit 0;
}

#****************************************************************************************************
# Subroutine Name         : checkRestoreItem.
# Objective               : This function will check if restore items are files or folders
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub checkRestoreItem {
	my $restoresetFilePath = Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFile);
	my $restoreFrom        = Common::getUserConfiguration('LOCALRESTOREFROM');
	my $dedup			   = Common::getUserConfiguration('DEDUP');
	my @list;

	# if ($dedup eq 'on') {
		# $restoreFrom = (split('#',$restoreFrom))[1] if ($restoreFrom =~ /#/);
	# }
		
	if(!open(RESTORELIST, $restoresetFilePath)){
		Common::traceLog(Common::getStringConstant('failed_to_open_file')." : $restoresetFilePath, Reason $!");
		return 0;
	}

	my $tempRestoreFrom = $restoreFrom;
	if($dedup eq 'on'){
		$tempRestoreFrom = "/".Common::getUserConfiguration('LOCALRESTORESERVERROOT');
	} elsif(substr($restoreFrom, 0, 1) ne "/"){
		$tempRestoreFrom = "/".$restoreFrom;
	}
	while(<RESTORELIST>) {
		chomp($_);
		$_ =~ s/^\s+//;
		if($_ eq "") {
			next;
		}
		my $rItem = "";
		if(substr($_, 0, 1) ne "/") {
			$rItem = $tempRestoreFrom."/".$_;
		} else {
			$rItem = $tempRestoreFrom.$_;
		}

		my $res = Sqlite::checkItemInExpressDB($rItem);
		if($res){
			push @list, $res;
		} else {
			$AppConfig::totalFiles++;
			$AppConfig::nonExistsCount++;
			print TRACEERRORFILE "[".(localtime)."] [FAILED] [$rItem]. Reason: No such file or directory\n";
		}
	}
	close(RESTORELIST);
	return @list;
}

#****************************************************************************************************
# Function Name         : enumerateFromDB
# Objective             : This function will search files for folders from DB.
# Added By              : Senthil Pandian
#*****************************************************************************************************
sub enumerateFromDB {
	my $itemName = $_[0];
	my $fieldMPC = "/";
	my ($dirID);
	my $dedup = Common::getUserConfiguration('DEDUP');
	my $serverRoot = ($dedup eq 'on')?Common::getUserConfiguration('LOCALRESTORESERVERROOT'):Common::getUserConfiguration('LOCALRESTOREFROM');

	# Common::initiateDBoperation();
	Common::replaceXMLcharacters(\$itemName);
	#print "enumerateFromDB:$itemName#\n\n";
	my $restoreSetFiles = Sqlite::searchAllFilesByDir($itemName);
	while(my $rows = $restoreSetFiles->fetchrow_hashref){
		#print Common::Dumper(\$rows);
		my $dirName  = $rows->{'DIRNAME'};
		chop($dirName);		
		$dirName	 = substr($dirName,1);

		my $fileName = $rows->{'FILENAME'};
		chop($fileName);
		$fileName = substr($fileName,1);	
		$fileName = $dirName.$fileName;
		$fileName =~ s/$serverRoot//;
		$fileName = Common::removeMultipleSlashs($fileName);
		print $filehandle_org $fileName."\n";
		print $filehandle $fieldMPC.$rows->{'FOLDER_ID'}."/".$rows->{'ENC_NAME'}."\n";
		$AppConfig::totalFiles++;
		$AppConfig::fileCount++;
		$AppConfig::totalSize += $rows->{'FILE_SIZE'};

		if($AppConfig::fileCount == Common::FILE_MAX_COUNT) {
# Common::traceLog('createRestoreSetFiles1k');
			if(!createRestoreSetFiles1k()){
				return REMOTE_SEARCH_THOUSANDS_FILES_SET_ERROR;
			}
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : createRestoreSetFiles1k
# Objective               : This function will generate 1000 Restore set Files
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub createRestoreSetFiles1k {
	my $filesOnly	  		= $AppConfig::jobRunningDir."/".$AppConfig::restoresetFileOnlyFiles;
	my $noRelativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::restoresetFileNoRelative;
	my $RestoresetFile_relative = $AppConfig::jobRunningDir."/".$AppConfig::restoresetFileRelative;
	my $filesOnlyFlag = $_[0]? $_[0] : "";
	$Restorefilecount++;

	if($relative == 0) {
		if($filesOnlyFlag eq "FILESONLY") {
			$filesOnlyCount++;
			print FD_WRITE "$current_source' '".Common::RELATIVE."' '$RestoresetFile_Only\n"; # 0
			$RestoresetFile_Only = $filesOnly."_".$filesOnlyCount;
			close RESTORE_FILE;
			close RESTORE_FILE_ORG;

			if(!open RESTORE_FILE_ORG, ">", $RestoresetFile_Only."_org") {
				Common::traceLog(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_Only"."_org, Reason $!\n");
				return 0;
			}
			chmod $AppConfig::filePermission, $RestoresetFile_Only."_org";
		}
		else
		{
			print FD_WRITE "$current_source' '".Common::RELATIVE."' '$RestoresetFile_new\n";
			$RestoresetFile_new =  $noRelativeFileset."$noRelIndex"."_$Restorefilecount";

			close $filehandle;
			close $filehandle_org;
			#print $filehandle_org #Need to add original file name
			if(!open $filehandle, ">", $RestoresetFile_new) {
				Common::traceLog(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_new, Reason $!\n");
				return 0;
			}
			chmod $AppConfig::filePermission, $RestoresetFile_new;

			if(!open $filehandle_org, ">", $RestoresetFile_new."_org") {
				Common::traceLog(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_new"."_org, Reason $!\n");
				return 0;
			}
			chmod $AppConfig::filePermission, $RestoresetFile_new."_org";			
		}
	}
	else {
		print FD_WRITE "$current_source' '".Common::RELATIVE."' '$RestoresetFile_new\n";
		$RestoresetFile_new = $RestoresetFile_relative."_$Restorefilecount";

		close RESTORE_FILE;
		close RESTORE_FILE_ORG;
		if(!open RESTORE_FILE, ">", $RestoresetFile_new){
			Common::traceLog(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_new, Reason $!\n");
			return 0;
		}
		chmod $AppConfig::filePermission, $RestoresetFile_new;

		if(!open RESTORE_FILE_ORG, ">", $RestoresetFile_new."_org"){
			Common::traceLog(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_new"."_org, Reason $!\n");
			return 0;
		}
		chmod $AppConfig::filePermission, $RestoresetFile_new."_org";		
	}

	#autoflush FD_WRITE;
	$AppConfig::fileCount = 0;

	if($Restorefilecount%15 == 0){
		sleep(1);
	}
	return CREATE_THOUSANDS_FILES_SET_SUCCESS;
}

#*******************************************************************************************************
# Subroutine Name         :	createRestoreTypeFile
# Objective               :	Create files respective to restore types (relative or no relative)
# Added By                : Senthil Pandian
#********************************************************************************************************
sub createRestoreTypeFile {
	#my $info_file = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;
	my $info_file = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);
	my $RestoresetFile_relative = $AppConfig::jobRunningDir."/".$AppConfig::restoresetFileRelative;
	my $noRelativeFileset	= Common::getCatfile($AppConfig::jobRunningDir,$AppConfig::restoresetFileNoRelative);
	#opening info file for generateBackupsetFiles function to write backup set information and for main process to read that information
	if(!open(FD_WRITE, ">", $info_file)){
		Common::traceLog(Common::getStringConstant('failed_to_open_file')." to write : $info_file, Reason $!\n") and die;
	}
	chmod $AppConfig::filePermission, $info_file;

	#Restore File name for mirror path
	if($relative != 0) {
		$RestoresetFile_new = $RestoresetFile_relative;
		if(!open RESTORE_FILE, ">>", $RestoresetFile_new) {
			Common::retreat(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_new, Reason $!\n");
		}
		chmod $AppConfig::filePermission, $RestoresetFile_new;
		
		if(!open RESTORE_FILE_ORG, ">>", $RestoresetFile_new."_org") {
			Common::retreat(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_new"."_org, Reason $!\n");
		}
		chmod $AppConfig::filePermission, $RestoresetFile_new."_org";		
	}
	else {
		$RestoresetFile_Only  = $AppConfig::jobRunningDir."/".$AppConfig::restoresetFileOnlyFiles;
		if(!open RESTORE_FILE, ">>", $RestoresetFile_Only) {
			Common::traceLog(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_Only, Reason $!\n");
			exit(1);
		}
		chmod $AppConfig::filePermission, $RestoresetFile_Only;
		$RestoresetFile_new =  $noRelativeFileset;

		if(!open RESTORE_FILE_ORG, ">>", $RestoresetFile_Only."_org") {
			Common::retreat(Common::getStringConstant('failed_to_open_file')." to write : $RestoresetFile_Only"."_org, Reason $!\n");
		}
		chmod $AppConfig::filePermission, $RestoresetFile_Only."_org";
	}
}

#*******************************************************************************************************
# Subroutine Name         :	waitForEnginesToFinish
# Objective               :	Wait for all engines to finish in backup.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/
sub waitForEnginesToFinish{
	my $res = '';
	my $engineLockFile = $AppConfig::jobRunningDir.'/'.AppConfig::ENGINE_LOCKE_FILE;
	while(@restoreForkchilds > 0) {
		foreach (@restoreForkchilds) {
			$res = waitpid($_, 0);
			if ($res > 0 or $res == -1) {
				@restoreForkchilds = grep(!/$_/, @restoreForkchilds);
			}
		}
	}
	while(Common::isAnyEngineRunning($engineLockFile)){
		sleep(1);
	}
	return;
}

#*****************************************************************************************************
# Subroutine	: displayRestoreProgress
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Reads the input and processes the input
# Added By		: Senthil Pandian
#*****************************************************************************************************
sub displayRestoreProgress {
	my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::progressDetailsFilePath);
	my $pidPath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);

    $AppConfig::pidOperationFlag = "DisplayProgress";
    my $keyPressEvent = Common::catchPressedKey();
    my $redrawForLess = 0;
    my $moreOrLess = $AppConfig::less;
    $moreOrLess    = $AppConfig::more if(Common::checkScreeSize());

    while(-f $pidPath) {
        $redrawForLess = 0;
        if($keyPressEvent->(1)) {
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
        Common::displayProgressBar($progressDetailsFilePath,undef,undef,$moreOrLess,$redrawForLess);
        Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);# Sleep for 100/500 milliseconds				
    }
    $keyPressEvent->(0);
    $AppConfig::pressedKeyValue = '';
    # Common::displayProgressBar($progressDetailsFilePath,Common::getTotalSize($AppConfig::jobRunningDir."/".$AppConfig::fileForSize),$playPause);
    Common::displayProgressBar($progressDetailsFilePath,undef,undef,$moreOrLess,$redrawForLess);
}