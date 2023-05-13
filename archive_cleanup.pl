#!/usr/bin/env perl
#***************************************************************************************************************
# Find and deletes data permanently which no longer exists on local computer to free up space in IDrive account.
#
# Created By: Senthil Pandian @ IDrive Inc
#****************************************************************************************************************
system('clear');
use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use AppConfig;
use Common;

eval {
	require Tie::File;
	Tie::File->import();
};

use constant DIR_EMPTY => 0;
use constant DIR_NOT_TO_REMOVE => 1;
use constant DIR_HAVE_ITEM_TO_DELETE => 2;

use constant RETRYCOUNT  => 5;
my ($logOutputFile, $errMsg, $archiveStage) = ('') x 3;
my $jobType = 'manual';
my ($totalFileCount, $notExistCount, $deletedFilesCount, $noOfResultSetFiles) = (0) x 4;
my ($tempTotalFileCount, $tempNotExistCount, $tempNoOfResultSetFiles) = (0) x 3;
my ($foldersCountToBeDeleted, $deletedDirCount, $isDeleteEmptyDir) = (0) x 3;
my ($failedFileCount, $failedDirCount, $isExitCleanupStarted, $forkProcess) = (0) x 4;
my ($isPercentError, $needToDeleteFiles, $retryCounter, $searchStarted) = (0, 1, 10, 0);

my $resultSetLimit = 10000;
#my (%archivedDirAndFile,%isDirHaveFiles,@dirListForAuth,@startTime);
my (%isDirHaveFiles,%tempIsDirHaveFiles,@dirListForDelete,@startTime,%emptyDirHash);

$SIG{INT}  = \&terminateProcess;
$SIG{TERM} = \&terminateProcess;
$SIG{TSTP} = \&terminateProcess;
$SIG{QUIT} = \&terminateProcess;
$SIG{KILL} = \&terminateProcess;
$SIG{ABRT} = \&terminateProcess;
$SIG{PWR}  = \&terminateProcess if(exists $SIG{'PWR'});
$SIG{USR1} = \&terminateProcess;

Common::waitForUpdate();
Common::initiateMigrate();

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::verifyVersionConfig();

	if ($#ARGV > 0) {			#For periodic operation
		Common::setUsername($ARGV[0]);
		$jobType = 'periodic';
		$AppConfig::callerEnv = 'BACKGROUND';

		#Checking the periods between scheduled date & today
		my $periodicDays = getDaysBetweenTwoDates();
		exit 0	if(($periodicDays != 0 ) && (($periodicDays % $ARGV[1]) != 0));
	}
	else {
		Common::loadUsername() or Common::retreat('login_&_try_again');
	}

	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);

	if($jobType eq 'manual'){
		Common::isLoggedin() or Common::retreat('login_&_try_again');
		Common::displayHeader();
	}
	Common::loadEVSBinary() or Common::retreat('unable_to_find_or_execute_evs_binary');

	my ($isMirror,$isBackupSetEmpty,$exit) = (1,0,0);
	my $backupType  = Common::getUserConfiguration('BACKUPTYPE');
	unless($backupType =~ /mirror/){
		$isMirror = 0;
		if($jobType eq 'manual') {
			Common::retreat('backup_type_must_be_mirror');
		} else {
			my $errStr = Common::getStringConstant('backup_type_must_be_mirror');
            exitCleanup(1,$errStr);
		}
	}

	my ($status, $errStr) = Common::validateBackupRestoreSetFile('backup');
	if($status eq 'FAILURE' && $errStr ne ''){
		$isBackupSetEmpty = 1;
		if($jobType eq 'manual') {
			Common::Chomp(\$errStr);
			Common::display(['no_items_to_cleanup',' ','Reason',$errStr,"\nNote: ",'please_update'], 0);
			Common::retreat("");
		}
        exitCleanup(1,$errStr);
	}

    # Verify backup location and if the job is periodic, inform the user by email
    if (Common::getUserConfiguration('DEDUP') eq 'on') {
        my @verdevices = Common::fetchAllDevices();
        if (defined($verdevices[0]{'MSG'}) && $verdevices[0]{'MSG'} =~ 'No devices found') {
            Common::retreat(["\n", 'invalid_bkp_location_config_again', "\n"]) if($jobType eq 'manual');

            $errStr = Common::getStringConstant('invalid_bkp_location_config_again');
            exitCleanup(1,$errStr);
        }
    } elsif($jobType eq 'manual') {
        if(!Common::getArchiveAlertConfirmation()){
            Common::retreat(['archive_cleanup', ' ', 'operation_has_been_aborted']);
        } else {
            Common::display('');
        }
    }

    my $archivePercentage = getPercentageForCleanup();
    $isDeleteEmptyDir = askToDeleteEmptyDirectories();

    # check if any backup job in progress
    checkRunningBackupJobs();

    my $jobRunningDir = Common::getJobsPath('archive');
    Common::createDir($jobRunningDir, 1) unless(-e $jobRunningDir);

    #Checking if archive job is already in progress
    my $pidPath = $jobRunningDir.$AppConfig::pidFile;
    if (Common::isFileLocked($pidPath,1)) {
        Common::retreat('archive_running', $jobType eq 'manual' ? 0 : 1);
    }

    my $lockStatus = Common::fileLock($pidPath);
    Common::retreat([$lockStatus.'_file_lock_status', ": ", $pidPath]) if($lockStatus);

 	#Renaming the log file if archive process terminated improperly
	Common::checkAndRenameFileWithStatus($jobRunningDir, 'archive');

    removeIntermediateFiles(1);		#Removing all the intermediate files/folders

    $searchStarted = 1;
    getArchiveFileList();

    if($notExistCount and $totalFileCount>0) {
        $isPercentError = isFilesBeyondPercentage($archivePercentage, $notExistCount, $totalFileCount);
        if($isPercentError) {
            $needToDeleteFiles = 0;
            # if($jobType eq 'periodic' or (defined($isDeleteEmptyDir) and $isDeleteEmptyDir))
            # {
                # createUserLogFiles();
            # }
        }
        elsif($jobType eq 'manual')
        {
            displayStatusAndConfirmationMsgToView('file');
            my $toViewConfirmation = getConfirmationToViewArchiveList();
            if(lc($toViewConfirmation) eq 'y') {
                my $mergedArchiveList = mergeAllArchivedFiles($AppConfig::archiveFileResultSet);
                if (-f $mergedArchiveList) {
                    Common::openEditor('view',$mergedArchiveList);
                    unlink($mergedArchiveList);
                }
            }
            #Checking pid & cancelling process if job terminated by user or if there is no proper input
            cancelProcess()	unless(-e $pidPath);

            # Get user confirmation to delete files
            Common::display(["\n",'do_u_want_to_delete_files_permanently'], 1);
            $toViewConfirmation = Common::getAndValidate('enter_your_choice','YN_choice',1,1,undef,1);
            #Exiting process if there is no proper input
            exitCleanup(1,$errMsg) if($toViewConfirmation eq 'exit');
            if(lc($toViewConfirmation) eq 'n') {
                $needToDeleteFiles = 0;
                Common::removeItems($jobRunningDir.$AppConfig::archiveFileResultSet."*");
                $errMsg = "File delete operation skipped by user.\n\n";
                # Common::fileWrite($jobRunningDir.$AppConfig::archiveFileFailureReasonFile,$errMsg);
            }
        }
    }
    elsif(!$notExistCount) {
        $needToDeleteFiles = 0;
        my $scannedInfo    = Common::getStringConstant('total_files_scanned_and_to_be_deleted');
        $scannedInfo =~ s/<SCANNED>/$totalFileCount/;
        $scannedInfo =~ s/<FOUND>/$notExistCount/;
        # $errMsg = Common::getStringConstant('no_files_to_delete')."\n";
        # $errorMsg = $scannedInfo;
        Common::display("\n".$scannedInfo,1);
        # $errorMsg = '';
        # if($jobType eq 'periodic' or (defined($isDeleteEmptyDir) and $isDeleteEmptyDir))
        # {
            # createUserLogFiles();
        # }
        my $errorMsg = Common::getStringConstant('no_files_to_delete')."\n\n";
        Common::fileWrite($jobRunningDir.$AppConfig::archiveFileFailureReasonFile,$errorMsg);
    }

    # Common::fileWrite($jobRunningDir.$AppConfig::archiveFileFailureReasonFile,$errMsg) if($errMsg);
    createUserLogFiles();
    if($needToDeleteFiles) {
        #Displaying progress of file deletion
        if($jobType eq 'manual'){
            Common::getCursorPos(10,Common::getStringConstant('preparing_to_delete'));
        }
        deleteArchiveFiles();
    }
=beg    
    elsif($notExistCount) {
        $needToDeleteFiles = 1; #Added to append file summary when user doesn't want to delete scanned files. 
    }
=cut
    if (defined($isDeleteEmptyDir) and $isDeleteEmptyDir) {
        
        %emptyDirHash = getEmptyDirectoryList(%isDirHaveFiles);

        #Deleting empty folders
        $foldersCountToBeDeleted = createFolderResultSet(\%emptyDirHash);
        if($foldersCountToBeDeleted)
        {
            if($jobType eq 'manual') {
                displayStatusAndConfirmationMsgToView('directory',$foldersCountToBeDeleted);
                my $toViewConfirmation = getConfirmationToViewArchiveList();
                #Checking pid & cancelling process if job terminated by user or if there is no proper input
                cancelProcess()	if(!-e $pidPath);

                if(lc($toViewConfirmation) eq 'y') {
                    my $mergedArchiveList = mergeAllArchivedFiles($AppConfig::archiveDirResultSet);
                    if (-f $mergedArchiveList) {
                        Common::openEditor('view',$mergedArchiveList);
                        unlink($mergedArchiveList);
                    }
                }
            }

            #Checking pid & cancelling process if job terminated by user
            cancelProcess()	unless(-e $pidPath);

            my $deleteConfirmation = 'y';
            if($jobType eq 'manual') {
                Common::display(["\n",'do_u_want_to_delete_directories_permanently'], 1);
                $deleteConfirmation = Common::getAndValidate('enter_your_choice','YN_choice',1,1,undef,1);
                #Exiting process if there is no proper input
                exitCleanup(1,$errMsg) if($deleteConfirmation eq 'exit');
            }
            if(lc($deleteConfirmation) eq 'y') {
                # createUserLogFiles() unless(-f $logOutputFile);
                deleteEmptyDirectories($foldersCountToBeDeleted);
                consolidateDeletedFileListAndLog();
            } else {
                $isDeleteEmptyDir = 0; #To avoid summary for directories
            }
        }
    }
  #  if($deletedFilesCount and !$isDeleteEmptyDir) {
  #       print ARCHIVELOG "\n";
  #  }

    # writeSummary($isPercentError,$needToDeleteFiles,);
    exitCleanup(0,$errMsg);
	exit 0;
}

#*****************************************************************************************************
# Subroutine			: isArchiveRunning
# Objective				: Check if archive is running or not
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub isArchiveRunning {
	my %runningJobs = Common::getRunningJobs('archive');
	my @runningJobs = keys %runningJobs;

	if(scalar(@runningJobs)){
		Common::retreat(["\n",'unable_to_start_cleanup_operation',lc($runningJobs[0]).'_running',"\n"], $jobType eq 'manual' ? 0 : 1);
	}
}

#*****************************************************************************************************
# Subroutine			: checkRunningBackupJobs
# Objective				: Check whether backup job running or not.When backup is in progress, 
#						  exit if manual archive or wait.
# Added By				: Senthil Pandian
# Modified By           : Deepak
#****************************************************************************************************/
sub checkRunningBackupJobs {
	my @availableBackupJobs = ('backup');
	my (%runningJobs,@runningJobs);
	my $runningJobName = '';

	# Check if no job running then return 
	%runningJobs = Common::getRunningJobs(@availableBackupJobs);
    @runningJobs = keys %runningJobs;
	my $totalRunningJobs = scalar(@runningJobs);
	if(!$totalRunningJobs) {
		return;
	}

	# If operation is manual then abort due to running backup
	if ($jobType eq 'manual') {
		$totalRunningJobs > 1 ? Common::retreat(["\n",'unable_to_start_cleanup_operation','manual_scheduled_backup_jobs_running',"\n"], 0) : Common::retreat(["\n",'unable_to_start_cleanup_operation',lc($runningJobs[0]).'_running',"\n"], 0);
	}

	# For periodic cleanup let us wait till backup jobs gets over
	while($totalRunningJobs) {
		Common::traceLog(['delaying_cleanup_operation_reason', lc($runningJobs[0]) . '_running']);
		sleep(60);
		%runningJobs = Common::getRunningJobs(@availableBackupJobs);
		@runningJobs = keys %runningJobs;
		$totalRunningJobs = scalar(@runningJobs);
	}
}

#*****************************************************************************************************
# Subroutine			: getArchiveFileList
# Objective				: Get archive file list to be deleted
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getArchiveFileList {
    my $displayProgressBarPid;
    my $isDedup  	         = Common::getUserConfiguration('DEDUP');
	my $jobRunningDir        = Common::getJobsPath('archive');
	my $archiveFileResultSet = Common::getCatfile($jobRunningDir, $AppConfig::archiveFileResultSet);
	my $archiveFileList      = Common::getCatfile($archiveFileResultSet, $AppConfig::archiveFileResultFile);
    my $progressPidFile      = Common::getCatfile($jobRunningDir, $AppConfig::progressPidFile);
    my $backupLocation	     = getBackupLocation();
    my $directoryID          = 0;

	Common::createDir($archiveFileResultSet, 1) unless(-d $archiveFileResultSet);

	my $progressDetailsFilePath = $jobRunningDir.$AppConfig::progressDetailsFilePath;
	my @PROGRESSFILE;
	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	chmod $AppConfig::filePermission, $progressDetailsFilePath;
	$PROGRESSFILE[0] = 'scanning_files';
	$PROGRESSFILE[1] = 'scanning_files';

	#Displaying progress of file scanning with count
    if($jobType eq 'manual') {
        # Common::display("\n");
        Common::getCursorPos(3,Common::getStringConstant('scanning_files')."\n");        
        $displayProgressBarPid = forkTodisplayArchiveProgressBar();
    }

	$archiveStage = 'scanning_files';
	my @itemsStat = checkBackupsetItemStatus();

	if(!open(ARCHIVE_FILE_ONLY_HANDLE, ">", $archiveFileList."_".$directoryID)) {
        my $errMsg = Common::getStringConstant('failed_to_open_file').": $archiveFileList. Reason:$!";
		Common::traceLog($errMsg);
        exitCleanup(1,$errMsg);
	}

	# createResultSetForFiles($archiveFileList);
    foreach my $tmpLine (@itemsStat) {
        my @fields = $tmpLine;
        if (ref($fields[0]) ne "HASH") {
            next;
        }

        my $itemName = $fields[0]{'fname'};
        Common::replaceXMLcharacters(\$itemName);
        $itemName =~ s/^[\/]+/\//g;

        if($fields[0]{'status'} =~ /directory exists/) {
            startSearchOperation($itemName);
        }
        elsif($fields[0]{'status'} =~ /file exists/){
            $totalFileCount++;
            my $tempItemName = $itemName;
            if($isDedup ne 'on' and $backupLocation ne '/'){
                $tempItemName =~ s/$backupLocation//;
            }

            unless(-e $tempItemName){
                $notExistCount++;
                print ARCHIVE_FILE_ONLY_HANDLE $itemName."\n";
            }
            my $progressMsg = Common::getStringConstant('files_scanned')." $totalFileCount\nScanning... $itemName";
            # Common::displayProgress($progressMsg,2);
            $PROGRESSFILE[1] = $progressMsg;
        }
    }
    close(ARCHIVE_FILE_HANDLE);
	close(ARCHIVE_FILE_ONLY_HANDLE);
	untie @PROGRESSFILE;

    Common::removeItems($progressPidFile);
    waitpid($displayProgressBarPid, 0) if($displayProgressBarPid);

	my $scannedInfo = Common::getStringConstant('total_files_scanned_and_to_be_deleted');
	$scannedInfo =~ s/<SCANNED>/$totalFileCount/;
	$scannedInfo =~ s/<FOUND>/$notExistCount/;
	$archiveStage = 'scan_completed';
	Common::fileWrite($progressDetailsFilePath,"scanning_files\nscan_completed\n$scannedInfo");
	Common::displayProgress(Common::getStringConstant('scan_completed'),2);
    Common::display("");
	Common::sleepForMilliSec(100) if($jobType eq 'periodic'); # Sleep for 100 milliseconds to display completed stage in status retrieval
	return 0;
}

#*****************************************************************************************************
# Subroutine			: checkBackupsetItemStatus
# Objective				: This function will get status of backup set items
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub checkBackupsetItemStatus {
	my $jobRunningDir	= Common::getJobsPath('archive');
	my $isDedup			= Common::getUserConfiguration('DEDUP');
	my $backupLocation	= getBackupLocation();

	my $encbkpfile		= Common::getCatfile(Common::getJobsPath('backup'), $AppConfig::backupsetFile);
	my $tmpbkpset		= Common::getDecBackupsetContents($encbkpfile, 'array');

	my $finalBackupLocation = '';
	$finalBackupLocation = $backupLocation if($isDedup eq 'off' and $backupLocation ne '/');

	my $tempBackupsetFilePath = Common::getCatfile($jobRunningDir, $AppConfig::tempBackupsetFile);
	if(!open(BACKUPLISTNEW, ">", $tempBackupsetFilePath)){
		$errMsg = Common::getStringConstant('failed_to_open_file').": $tempBackupsetFilePath, Reason: $!";
		return 0;
	}
	my @arryToCheck = ();
	my @backupSetArray	= @{$tmpbkpset};
	chomp(@backupSetArray);
    foreach(@backupSetArray){  
		Common::Chomp(\$_);
		next if($_ eq "");

		my $rItem = $finalBackupLocation.$_;
		if(substr($_, 0, 1) ne "/") {
			$rItem = "/".$_;
		}

		if ( grep{ $rItem."\n" eq $_ } @arryToCheck ) {
			next;
		}
		push @arryToCheck, $rItem."\n";
	}

	print BACKUPLISTNEW @arryToCheck;
	# close(BACKUPLIST);
	close(BACKUPLISTNEW);

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);
START:
	my $itemStatusUTFpath = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
	Common::createUTF8File(['ITEMSTATUS',$itemStatusUTFpath],
		$tempBackupsetFilePath,
		$evsErrorFile,
        ''
		) or Common::retreat('failed_to_create_utf8_file');

	my @responseData = Common::runEVS('item',1);
	unlink($tempBackupsetFilePath);

	if(-s $evsErrorFile > 0) {
		unless(Common::checkAndUpdateServerAddr($evsErrorFile)) {
			exitCleanup(Common::getStringConstant('operation_could_not_be_completed_please_try_again'));
		} else {
			my $errStr = Common::checkExitError($evsErrorFile,'archive');
			if($errStr and $errStr =~ /1-/){
				$errStr =~ s/1-//;
				exitCleanup($errStr);
			}
			elsif($errStr and $errStr =~ m/Name or service not known/i) {
				unlink($evsErrorFile);
				goto START;
			}
		}
		return 0;
	}
	unlink($evsErrorFile);
	return @responseData;
}

#********************************************************************************
# Subroutine			: startSearchOperation
# Objective				: Start remote search operation
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#********************************************************************************
sub startSearchOperation{
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $isDedup  	   = Common::getUserConfiguration('DEDUP');
	my $archiveFileResultSet = $jobRunningDir.$AppConfig::archiveFileResultSet;
	my $archiveFileList      = $archiveFileResultSet.'/'.$AppConfig::archiveFileResultFile;
	my $totalNoOfRetry       = $AppConfig::maxChoiceRetry;

	Common::createDir($archiveFileResultSet, 1) unless(-d $archiveFileResultSet);

	my $remoteFolder = $_[0];
	if (substr($remoteFolder, -1, 1) ne "/") {
	   $remoteFolder .= "/";
	}
    
	my $errStr     = "";
	my $searchItem = "*";
	my $tempSearchUTFpath = $archiveFileResultSet.'/'.$AppConfig::utf8File;
	my $tempEvsOutputFile = $archiveFileResultSet.'/'.$AppConfig::evsOutputFile;
	my $tempEvsErrorFile  = $archiveFileResultSet.'/'.$AppConfig::evsErrorFile;

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = $jobRunningDir.$AppConfig::pidFile;
    my $res = 0;
    while(1) {
        cancelProcess()	unless(-e $pidPath);
        createResultSetForFiles($archiveFileList);
        Common::createUTF8File(['SEARCHARCHIVE',$tempSearchUTFpath],
                    $tempEvsOutputFile,
                    $tempEvsErrorFile,
                    $remoteFolder
                    ) or Common::retreat('failed_to_create_utf8_file');
        my @responseData = Common::runEVS('item',1,0,$tempSearchUTFpath);
        
        while(-e $pidPath){
            last if((-e $tempEvsOutputFile and -s _) or (-e $tempEvsErrorFile and -s _));
            sleep(2);
        }
        
        if(-s $tempEvsOutputFile == 0 and -s $tempEvsErrorFile > 0) {
            my $errStr = Common::checkExitError($tempEvsErrorFile,'archive');
            if($errStr and $errStr =~ /1-/){
                $errStr =~ s/1-//;
                exitCleanup(1,$errStr);
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
        if ($isDedup eq 'on') {
            $res = dedupSearchOutputParse($tempEvsOutputFile, $tempEvsErrorFile, $remoteFolder);
        } else {
            $res = nondedupSearchOutputParse($tempEvsOutputFile, $tempEvsErrorFile, $remoteFolder);
        }

        close(ARCHIVE_FILE_HANDLE);

        if($res) {
            last;
        } else {
            $totalNoOfRetry--;
            $retryCounter++;
            if(!$totalNoOfRetry or $retryCounter == 10) {
                my($retryAttempt, $reason) = Common::checkRetryAttempt('archive', $tempEvsErrorFile);
                $reason = Common::getStringConstant('operation_could_not_be_completed_reason').$reason;
                exitCleanup(1,$reason);
               # last;
            }
            removePartialSearchResultSetFiles($noOfResultSetFiles, $tempNoOfResultSetFiles, $archiveFileList);
            $tempNoOfResultSetFiles = $noOfResultSetFiles;
            Common::removeItems([$tempEvsOutputFile, $tempEvsErrorFile, $tempSearchUTFpath]);
        }
    }
    Common::removeItems([$tempEvsOutputFile, $tempEvsErrorFile, $tempSearchUTFpath]);
    my $lastResultSet = $archiveFileList."_".$tempNoOfResultSetFiles;
    if(-e $lastResultSet and -z $lastResultSet) {
        Common::removeItems($lastResultSet);
        $tempNoOfResultSetFiles--;
    }

    $totalFileCount     += $tempTotalFileCount;
    $notExistCount      += $tempNotExistCount;
    $noOfResultSetFiles  = $tempNoOfResultSetFiles;
    %isDirHaveFiles      = (%isDirHaveFiles, %tempIsDirHaveFiles) if(scalar(keys %tempIsDirHaveFiles));
	# Common::traceLog("startSearchOperation-End");
	# Common::traceLog("totalFileCount:$totalFileCount");
	return 0;
}

#********************************************************************************
# Subroutine			: fillDirectoryHasItemsToDelete
# Objective				: To find the directory which is having files to be deleted.
#                         Marking 2 to understand that directory may get empty after deleting file.
#                         2 will be replaced with 1 if any other file present in that directory.
# Added By				: Senthil Pandian
#********************************************************************************
sub fillDirectoryHasItemsToDelete{
	my @parentDir = Common::fileparse($_[0]);

	if (!defined($tempIsDirHaveFiles{$parentDir[1]}) or $tempIsDirHaveFiles{$parentDir[1]} == DIR_EMPTY)
	{
		$tempIsDirHaveFiles{$parentDir[1]} = DIR_HAVE_ITEM_TO_DELETE; 
	}
}

#********************************************************************************
# Subroutine			: getEmptyDirectoryList
# Objective				: To get empty directories list Before/After Delete & return in hash
# Added By				: Senthil Pandian
#********************************************************************************
sub getEmptyDirectoryList{
	my %tempDirHaveFiles = @_;
	my %folderListHash   = ();
	return %folderListHash unless(scalar(keys %tempDirHaveFiles));

	my %list = %tempDirHaveFiles;

    Common::display(["\n",'preparing_empty_dir_list']);

    #If there is no files to delete or If delete operation not performed due to percentage/user action
    if($isPercentError or !$needToDeleteFiles) {
        foreach my $item (sort(keys %list)) {
            foreach my $newItem (sort(keys %list)) {
                my $tempItem = quotemeta($item);
                if ($item ne $newItem && $newItem =~ m/^$tempItem/) {
                    if($tempDirHaveFiles{$newItem})
                    {
                        if($tempDirHaveFiles{$newItem} == DIR_NOT_TO_REMOVE) {
                            $isDirHaveFiles{$item} = DIR_NOT_TO_REMOVE;
                            delete $isDirHaveFiles{$newItem};
                            # delete $list{$newItem}; #Added for better performance.
                        }
                        $tempDirHaveFiles{$item} = DIR_NOT_TO_REMOVE;
                        delete $list{$item};
                        last;
                    }
                }
            }
            delete $list{$item}; #Added for better performance.
        }

        foreach my $item (sort(keys %tempDirHaveFiles))
        {
            unless($tempDirHaveFiles{$item})
            {
                $folderListHash{$item} = $tempDirHaveFiles{$item};
            }
        }
    }
    else {
        foreach my $item (sort(keys %list)) {
            foreach my $newItem (sort(keys %list)) {
                my $tempItem = quotemeta($item);
                if ($item ne $newItem && $newItem =~ m/^$tempItem/) {
                    if($tempDirHaveFiles{$newItem}==DIR_NOT_TO_REMOVE)
                    {
                        $tempDirHaveFiles{$item} = DIR_NOT_TO_REMOVE;
                        delete $list{$item};
                        # delete $list{$newItem}; #Added for better performance.
                        last;
                    }
                }
            }
            delete $list{$item}; #Added for better performance.
        }

        foreach my $item (sort(keys %tempDirHaveFiles))
        {
            if($tempDirHaveFiles{$item}!=DIR_NOT_TO_REMOVE)
            {
                $folderListHash{$item} = $tempDirHaveFiles{$item};
            }
        }
    }

	%folderListHash = skipChildIfParentDirExists(\%folderListHash);
	return %folderListHash;
}

#********************************************************************************
# Subroutine			: createFolderResultSet
# Objective				: To create folder result set file to delete empty directories
# Added By				: Senthil Pandian
#********************************************************************************
sub createFolderResultSet{
	my %folderListHash = %{$_[0]};
	return 0 unless(scalar(keys %folderListHash));

	my $jobRunningDir = Common::getJobsPath('archive');
	my $archiveDirResultSet = $jobRunningDir.$AppConfig::archiveDirResultSet;
	Common::createDir($archiveDirResultSet, 1) unless(-d $archiveDirResultSet);
	my $folderList = '';
	my $index = 1;
	my $emptyDirCount = 0;
	my $archiveFolderList = $archiveDirResultSet.'/'.$AppConfig::archiveFolderResultFile."_".$index;
	foreach my $item (sort(keys %folderListHash)) {
		$folderList .= $item."\n";
		$emptyDirCount++;
		if ($emptyDirCount%$resultSetLimit == 0) {
			Common::fileWrite($archiveFolderList,$folderList);
			$index++;
			$archiveFolderList = $archiveDirResultSet.'/'.$AppConfig::archiveFolderResultFile."_".$index;
			$folderList = '';
		}
	}
	Common::fileWrite($archiveFolderList,$folderList) if($folderList);
	return $emptyDirCount;
}

#*****************************************************************************************************
# Subroutine			: skipChildIfParentDirExists
# Objective				: Skip child items if parent directory present & return
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub skipChildIfParentDirExists{
	my %list = %{$_[0]};
	foreach my $item (sort(keys %list)) {
		foreach my $newItem (sort(keys %list)){
			my $tempNewItem = quotemeta($newItem);
			if ($item ne $newItem && $item =~ m/^$tempNewItem/)
			{
				delete $list{$item};
				last;
			}
		}
	}
	return %list;
}

#****************************************************************************************************
# Subroutine		: deleteArchiveFiles
# Objective			: This function will remove the Archive Files
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub deleteArchiveFiles {
	my $currErrorContent  = '';
	my $isDedup  	      = Common::getUserConfiguration('DEDUP');
	my $jobRunningDir     = Common::getJobsPath('archive');
	my $serverRoot        = Common::getUserConfiguration('SERVERROOT');
    
	my $pidPath              = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
	my $archiveFileResultSet = Common::getCatfile($jobRunningDir, $AppConfig::archiveFileResultSet);
	my $deleteFileUTFpath    = Common::getCatfile($jobRunningDir, $AppConfig::utf8File);
	my $evsOutputFile        = Common::getCatfile($jobRunningDir, $AppConfig::evsOutputFile);
	my $evsErrorFile         = Common::getCatfile($jobRunningDir, $AppConfig::evsErrorFile);
	my $archiveFilePath      = Common::getCatfile($archiveFileResultSet, $AppConfig::archiveFileResultFile);
	my $progressDetailsFilePath = Common::getCatfile($jobRunningDir, $AppConfig::progressDetailsFilePath);

	my $errorDir =  Common::getCatfile($jobRunningDir, $AppConfig::errorDir);
	Common::createDir($errorDir, 1);
	my $deleteErrorContentFile =  Common::getCatfile($errorDir, $AppConfig::archiveFileResultFile);

	# my $currErrorFile = $deleteErrorContentFile;
	my $totalNoOfRetry  = RETRYCOUNT+1;
	my $totalResultSetCount = $noOfResultSetFiles;
	my $errorCount = 1;

	my @PROGRESSFILE;
	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	chmod $AppConfig::filePermission, $progressDetailsFilePath;
	Common::fileWrite($progressDetailsFilePath,'preparing_to_delete');
	$archiveStage = 'preparing_to_delete';
	print ARCHIVELOG Common::getStringConstant('deleted_content_files');
    my $progressPidFile = Common::getCatfile($jobRunningDir, $AppConfig::progressPidFile);   
# Common::traceLog("deleteArchiveFiles: Start");
    my $displayProgressBarPid = forkTodisplayArchiveProgressBar();
    my $errStr = '';

	for (my $cnt=0; $cnt<=$noOfResultSetFiles and $totalNoOfRetry; $cnt++)
	{
		#Checking pid & cancelling process if job terminated by user
		cancelProcess()	unless(-e $pidPath);

        $evsErrorFile       = $deleteErrorContentFile."_".$cnt."_ERROR";
		my $archiveFileList = $archiveFilePath."_".$cnt;
		if(-e $archiveFileList and !-z _)
		{
			my $deleteRetryCount = $AppConfig::maxChoiceRetry;
            while(1) {
                Common::createUTF8File(['DELETE',$deleteFileUTFpath],
                            $archiveFileList,
                            $evsOutputFile,
                            $evsErrorFile
                            ) or Common::retreat('failed_to_create_utf8_file');
                my @responseData = Common::runEVS('item',1);

                if(-s $evsOutputFile < 5 and !-z $evsErrorFile) {
                    unless(Common::checkAndUpdateServerAddr($evsErrorFile)) {
                        Common::traceLog("Deleting files : RETRY");
                        $deleteRetryCount--;
                        next if($deleteRetryCount);
                    } else {
                        $errStr = Common::checkExitError($evsErrorFile,'archive');
                        if($errStr and $errStr =~ /1-/){
                            $errStr =~ s/1-//;
                            print ARCHIVELOG Common::getStringConstant('failed_to_delete_files')."\n\n" unless($deletedFilesCount); #Added for Snigdha_2.3_11_1
                            exitCleanup(1,$errStr);
                        }
                    }
                    return 0;
                }
                last;
            }

			# parse delete output.
			open OUTFH, "<", $evsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').": $evsOutputFile, Reason: $!");
			if($errStr ne ""){
				Common::traceLog($errStr);
				return 0;
			}

			# Appending deleted files/folders details to log
			my ($buffer,$lastLine) = ("") x 2;
			my $skipFlag = 0;
            my %archivedFileHash = getArchivedFileHash($archiveFileList);

			while(1){
				my $byteRead = read(OUTFH, $buffer, $AppConfig::bufferLimit);
				if($byteRead == 0) {
					if(!-e $pidPath or (-e $evsErrorFile and -s _)) {
						last;
					}
					sleep(2);
					seek(OUTFH, 0, 1);		#to clear eof flag
					next;
				}

				if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
					$buffer = $lastLine . $buffer;
				}
				my @resultList = split /\n/, $buffer;

				if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
					$lastLine = pop @resultList;
				}
				else {
					$lastLine = "";
				}

				foreach my $tmpLine (@resultList){
					if($tmpLine =~ /<item/ and $tmpLine !~ /tot_items_deleted/){
						my %fileName = Common::parseXMLOutput(\$tmpLine);
						next if (!defined($fileName{'fname'}) or !defined($fileName{'op'}));
						my $op		 = $fileName{'op'};
						my $fileName = $fileName{'fname'};
						Common::replaceXMLcharacters(\$fileName);

						if ($isDedup eq 'on'){
							$fileName =~ s/^\/$serverRoot//;
						}
						$archivedFileHash{$fileName}=1;
						print ARCHIVELOG "[$op] [$fileName]\n"; #Appending deleted file detail to log file			
						$deletedFilesCount++;

						$PROGRESSFILE[0] = 'files_delete_progress';
						$PROGRESSFILE[1] = $fileName;
						$PROGRESSFILE[2] = $deletedFilesCount;
						$PROGRESSFILE[3] = $notExistCount;
						# Common::displayArchiveProgressBar($progressDetailsFilePath);
					} elsif($tmpLine ne '' and $tmpLine !~ m/(connection established|receiving file list|tot_items_deleted)/){
						$currErrorContent = $tmpLine."\n";
					}
				}
				if($buffer ne '' and $buffer =~ m/End of operation/i) {
					# Common::displayArchiveProgressBar($progressDetailsFilePath);
					last;
				}
			}
			close(OUTFH);
            Common::removeItems($evsErrorFile) if(-e $evsErrorFile and -z _);

			my $lastSet = 0;
			if ($cnt==$totalResultSetCount) {
				$lastSet = 1;
				$errorCount++;
			}
			getFailedItemList($archiveFilePath,\$totalResultSetCount,\$totalNoOfRetry,$lastSet,\%archivedFileHash,$cnt);
			Common::removeItems([$evsOutputFile,$archiveFileList,$deleteFileUTFpath]);
		}
		last unless($totalNoOfRetry);
        if(-f $evsErrorFile)
        {
            my $evsErrorFilePath = $deleteErrorContentFile."_".$noOfResultSetFiles."_ERROR";
            rename($evsErrorFile, $evsErrorFilePath);

            # Calling function to wait for network restoration
            my $evsError     = Common::getFileContents($evsErrorFilePath);
            my $networkError = 'Network is unreachable';
            if($evsError =~ m/$networkError/)
            {
                my $deleteRetryCount = $AppConfig::maxChoiceRetry;
                while($deleteRetryCount) {
                    last unless(-f $pidPath);
                    my $isInternetAvailable = Common::isInternetAvailable();
                    $isInternetAvailable = 0;
                    # Common::traceLog("isInternetAvailable: $isInternetAvailable");
                    last if($isInternetAvailable);
                    # Common::traceLog("waitForNetworkConnection: Network is unreachable");
                    sleep(30);
                    $deleteRetryCount--;
                }
                unless($deleteRetryCount) {
                    if($deletedFilesCount) {
                        print ARCHIVELOG "\n";
                    } else {
                        print ARCHIVELOG Common::getStringConstant('failed_to_delete_files')."\n\n";
                    }
                    $errStr = Common::getStringConstant('operation_could_not_be_completed_reason').$networkError;
                    last;
                }
            }
        }
	}
	untie @PROGRESSFILE;
    # unless($deletedFilesCount) {
        # print ARCHIVELOG Common::getStringConstant('failed_to_delete_files')."\n";
    # }

    Common::removeItems($progressPidFile);
    waitpid($displayProgressBarPid, 0) if($displayProgressBarPid);

	$archiveStage = 'files_delete_operation_completed';
	Common::fileWrite($progressDetailsFilePath,'files_delete_progress'."\n".'files_delete_operation_completed');

	my $childProc = fork();
	if ($childProc == 0){
		Common::reCalculateStorageSize(0);
		exit(0);
	}

	Common::setBackupLocationSize(1);
	Common::sleepForMilliSec(101) if($jobType eq 'periodic'); # Sleep for 100 milliseconds to display completed stage in status retrieval

    if($errStr ne "") {
        exitCleanup(1,$errStr);
    } elsif($deletedFilesCount) {
        print ARCHIVELOG "\n";
    }
}

#****************************************************************************************************
# Subroutine		: deleteEmptyDirectories
# Objective			: This function will generate empty folder result set & remove the empty folder
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub deleteEmptyDirectories {
    my $displayProgressBarPid;
	my $foldersCount	    = $_[0];
	my $currErrorContent    = '';
	my $isDedup  	        = Common::getUserConfiguration('DEDUP');
	my $jobRunningDir       = Common::getJobsPath('archive');
	my $serverRoot          = Common::getUserConfiguration('SERVERROOT');
	my $deleteDirUTFpath    = Common::getCatfile($jobRunningDir, $AppConfig::utf8File);
	my $evsOutputFile       = Common::getCatfile($jobRunningDir, $AppConfig::evsOutputFile);
	my $evsErrorFile        = Common::getCatfile($jobRunningDir, $AppConfig::evsErrorFile);
	my $archiveDirResultSet = Common::getCatfile($jobRunningDir, $AppConfig::archiveDirResultSet);
	my $archiveFolderPath   = Common::getCatfile($archiveDirResultSet, $AppConfig::archiveFolderResultFile);

	my $errorDir = $jobRunningDir.$AppConfig::errorDir;
	Common::createDir($errorDir, 1);
	my $deleteErrorContentFile = $errorDir.'/'.$AppConfig::archiveFolderResultFile;

	my $totalNoOfRetry = RETRYCOUNT+1;

    my $pidPath                 = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
    my $progressPidFile         = Common::getCatfile($jobRunningDir, $AppConfig::progressPidFile);
 	my $progressDetailsFilePath = Common::getCatfile($jobRunningDir, $AppConfig::progressDetailsFilePath);
   
	Common::fileWrite($jobRunningDir.$AppConfig::archiveStageDetailsFile,Common::getStringConstant('files_delete_operation_completed'),'APPEND');
	Common::fileWrite($progressDetailsFilePath,'deleting_empty_directories'."\n".'deleting_empty_directories');
	tie my @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	chmod $AppConfig::filePermission, $progressDetailsFilePath;

	if($jobType eq 'manual'){
		Common::display("\n");
		Common::getCursorPos(10,Common::getStringConstant('deleting_empty_directories'));
        $displayProgressBarPid = forkTodisplayArchiveProgressBar();
	}

	my $deletedDirList = $jobRunningDir."/".$AppConfig::deletedDirList;
	if(!open(DELETEDIR, ">", $deletedDirList)){
		$errMsg = Common::getStringConstant('failed_to_open_file').": $deletedDirList, Reason: $!";
		return 0;
	}
	$PROGRESSFILE[0] = 'deleting_empty_directories';
	$PROGRESSFILE[1] = 'deleting_empty_directories';
	$noOfResultSetFiles  = Common::ceil($foldersCount/$resultSetLimit);
	my $totalResultSetCount = $noOfResultSetFiles;
    my $errStr = "";

	for (my $cnt=1; $cnt<=$noOfResultSetFiles and $totalNoOfRetry; $cnt++)
	{
        $evsErrorFile = $deleteErrorContentFile."_".$cnt."_ERROR";
		my $archiveFolderList = $archiveFolderPath."_".$cnt;
		if(-e $archiveFolderList and !-z _)
		{
			my $deleteRetryCount = $AppConfig::maxChoiceRetry;
            while(1) {
                #Checking pid & cancelling process if job terminated by user
                cancelProcess()	unless(-e $pidPath);

                Common::createUTF8File(['DELETE',$deleteDirUTFpath],
                            $archiveFolderList,
                            $evsOutputFile,
                            $evsErrorFile
                            ) or Common::retreat('failed_to_create_utf8_file');
                my @responseData = Common::runEVS('item',1);

                if((-f $evsOutputFile && (-s $evsOutputFile < 5)) && (-f $evsErrorFile && !-z $evsErrorFile)) {
                    unless(Common::checkAndUpdateServerAddr($evsErrorFile)) {
                        Common::traceLog("Deleting folders : RETRY");
                        $deleteRetryCount--;
                        next if($deleteRetryCount);
                    } else {
                        $errStr = Common::checkExitError($evsErrorFile,'archive');
                        if($errStr and $errStr =~ /1-/){
                            $errStr =~ s/1-//;
                            exitCleanup(1,$errStr);
                        }
                    }
                    return 0;
                }
                last;
            }

			# parse delete output.
			open OUTFH, "<", $evsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').": $evsOutputFile, Reason: $!");
			if($errStr ne ""){
				Common::traceLog($errStr);
				return 0;
			}

			my $serverRoot = Common::getUserConfiguration('SERVERROOT');
			# Appending deleted files/folders details to log
			my ($buffer,$lastLine,$progressMsg) = ("") x 3;
			my $skipFlag = 0;
            my %archivedFileHash = getArchivedFileHash($archiveFolderList);

			while(1){
				my $byteRead = read(OUTFH, $buffer, $AppConfig::bufferLimit);
				if($byteRead == 0) {
					if(!-e $pidPath or (-e $evsErrorFile and -s _)) {
						last;
					}
					sleep(2);
					seek(OUTFH, 0, 1);		#to clear eof flag
					next;
				}

				if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
					$buffer = $lastLine.$buffer;
				}

				$lastLine = "";
				my @resultList = split /\n/, $buffer;
				if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
					$lastLine = pop @resultList;
				}

				foreach my $tmpLine (@resultList){
					if($tmpLine =~ /<item/ and $tmpLine !~ /tot_items_deleted/){
						my %deletedItem = Common::parseXMLOutput(\$tmpLine);
						next if (!defined($deletedItem{'fname'}) or !defined($deletedItem{'op'}));
						my $op		= $deletedItem{'op'};
						my $dirName = $deletedItem{'fname'};
						Common::replaceXMLcharacters(\$dirName);
						if ($isDedup eq 'on'){
							$dirName =~ s/^\/$serverRoot//;
						}
						$archivedFileHash{$dirName}=1;
						print DELETEDIR "$dirName\n"; #Appending deleted directory detail to log file
						$deletedDirCount++;
						# Common::displayArchiveProgressBar($progressDetailsFilePath);
						$PROGRESSFILE[0] = 'empty_directories_delete_progress';
						$PROGRESSFILE[1] = $dirName;
						$PROGRESSFILE[2] = $deletedDirCount;
						$PROGRESSFILE[3] = $foldersCount;						
					}
					elsif($tmpLine ne '' and $tmpLine !~ m/(connection established|receiving file list|tot_items_deleted)/)
					{
						$currErrorContent .= $tmpLine;
					}
				}
				if($buffer ne '' and $buffer =~ m/End of operation/i) {
					# Common::displayArchiveProgressBar($progressDetailsFilePath);
					last;
				}
			}

			close OUTFH;
            Common::removeItems($evsErrorFile) if(-e $evsErrorFile and -z _);

			my $lastSet = 0;
			if ($cnt==$totalResultSetCount) {
				$lastSet = 1;
			}
			getFailedItemList($archiveFolderPath,\$totalResultSetCount,\$totalNoOfRetry,$lastSet,\%archivedFileHash,$cnt);
			Common::removeItems([$evsOutputFile,$archiveFolderList,$deleteDirUTFpath]);
		}
        
		last unless($totalNoOfRetry);
        if(-f $evsErrorFile)
        {
            my $evsErrorFilePath = $deleteErrorContentFile."_".$noOfResultSetFiles."_ERROR";
            rename($evsErrorFile, $evsErrorFilePath);

            # Calling function to wait for network restoration
            my $evsError     = Common::getFileContents($evsErrorFilePath);
# Common::traceLog("evsError:$evsError");           
            my $networkError = 'Network is unreachable';
            if($evsError =~ m/$networkError/)
            {
                my $deleteRetryCount = $AppConfig::maxChoiceRetry;
                while($deleteRetryCount) {
                    last unless(-f $pidPath);
                    my $isInternetAvailable = Common::isInternetAvailable();
                    # Common::traceLog("isInternetAvailable:$operationEngineId: $isInternetAvailable");
                    last if($isInternetAvailable);
                    # Common::traceLog("waitForNetworkConnection:$operationEngineId: Network is unreachable");
                    sleep(30);
                    $deleteRetryCount--;
                }
                unless($deleteRetryCount) {
                    if($deletedFilesCount) {
                        print ARCHIVELOG "\n";
                    } else {
                        print ARCHIVELOG Common::getStringConstant('failed_to_delete_files')."\n\n";
                    }

                    $errStr = Common::getStringConstant('operation_could_not_be_completed_reason').$networkError;
                    last;
                }
            }
        }
	}
	untie @PROGRESSFILE;
	close DELETEDIR;

    Common::removeItems($progressPidFile);
    waitpid($displayProgressBarPid, 0) if($displayProgressBarPid);    
    exitCleanup(1,$errStr) if($errStr ne "");

# Common::traceLog("deleteEmptyDirectories: End"); 
}

#********************************************************************************
# Subroutine			: terminateProcess
# Objective				: Terminating the process and removing the intermediate files/folders when signal triggered.
# Added By				: Senthil Pandian
#********************************************************************************
sub terminateProcess {
    exit unless($searchStarted);
    cancelProcess();
}

#********************************************************************************
# Subroutine			: cancelProcess
# Objective				: Cancelling the process and removing the intermediate files/folders
# Added By				: Senthil Pandian
#********************************************************************************
sub cancelProcess {
	my $jobRunningDir = Common::getJobsPath('archive');
	my $pidPath = $jobRunningDir.$AppConfig::pidFile;
    my $progressDetailsFilePath = $jobRunningDir.$AppConfig::progressDetailsFilePath;
    return 1 if($forkProcess);
	$errMsg = Common::getStringConstant('operation_cancelled_by_user');
	if (-e $pidPath) {
		# Killing EVS operations
		my $username = Common::getUsername();
		my $cmd = sprintf("%s %s 'archive' - 0 allType %s %s", $AppConfig::perlBin, Common::getScript('job_termination', 1), $AppConfig::mcUser, 'operation_cancelled_by_user');
		$cmd = Common::updateLocaleCmd($cmd);
		`$cmd 1>/dev/null 2>/dev/null`;
	}

	Common::fileWrite($progressDetailsFilePath,"\n".$errMsg);
	exitCleanup(1,$errMsg);
}

#********************************************************************************
# Subroutine			: exitCleanup
# Objective				: Cancelling the process and removing the intermediate files/folders
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#********************************************************************************
sub exitCleanup {
    return if($isExitCleanupStarted);
    $isExitCleanupStarted = 1;
    my $exit   = $_[0];
	my $errStr = $_[1];

	if($jobType eq 'manual'){
		system('stty', 'echo');
		system("tput sgr0");
	}

	# my ($isPercentError,$needToDeleteFiles) = (0) x 2;
#	$isPercentError = 1 if($foldersCountToBeDeleted); #If LOG file not created & but attempting to delete directory. So assuming that no file
    my $jobRunningDir = Common::getJobsPath('archive');
	my $exitErrorFile = $jobRunningDir.$AppConfig::exitErrorFile;
    if(-e $exitErrorFile){
		$errStr = Common::getFileContents($exitErrorFile);
    }
    elsif(defined($errStr)){
    	$errStr = Common::checkErrorAndLogout($errStr, undef, 1);
    }
    writeSummary($isPercentError,$needToDeleteFiles,$exit,$errStr);
 	my $retVal = renameLogFile($isPercentError,$errStr); #Renaming the log output file name with status
	removeIntermediateFiles();		#Removing all the intermediate files/folders
	# $errStr = '' unless($errStr);
	# Common::retreat($errStr) if($errStr);
    exit;
}

#********************************************************************************
# Subroutine			: removeIntermediateFiles
# Objective				: Removing all the intermediate files/folders
# Added By				: Senthil Pandian
#********************************************************************************
sub removeIntermediateFiles {
	my $jobRunningDir = Common::getJobsPath('archive');
	my $archiveFileResultSet = $jobRunningDir.$AppConfig::archiveFileResultSet;
	my $archiveDirResultSet = $jobRunningDir.$AppConfig::archiveDirResultSet;
	my $logPidFilePath = $jobRunningDir.$AppConfig::logPidFile;
	my $evsOutputFile = $jobRunningDir.$AppConfig::evsOutputFile;
	my $evsErrorFile  = $jobRunningDir.$AppConfig::evsErrorFile;
    my $errorFile     = $jobRunningDir.$AppConfig::errorFile;
	my $failedFiles   = $jobRunningDir.$AppConfig::failedFileName;
	my $failedDirList = $jobRunningDir.$AppConfig::failedDirList;
	my $itemStatusUTFpath       = $jobRunningDir.$AppConfig::utf8File;
	my $tempBackupsetFilePath   = $jobRunningDir.$AppConfig::tempBackupsetFile;
	my $archiveFileView         = $jobRunningDir.$AppConfig::archiveFileListForView;
	my $exitErrorFile           = $jobRunningDir.$AppConfig::exitErrorFile;	
	my $progressDetailsFilePath = $jobRunningDir.$AppConfig::progressDetailsFilePath;
	my $deletedDirList = $jobRunningDir.$AppConfig::deletedDirList;
	my $fileSummaryFile = $jobRunningDir.$AppConfig::fileSummaryFile;

	my $failedFileWithReason = $jobRunningDir.$AppConfig::failedFileWithReason;
	my $finalErrorFile = $jobRunningDir.$AppConfig::finalErrorFile;
	my $archiveFileFailureReasonFile = $jobRunningDir.$AppConfig::archiveFileFailureReasonFile;

	my $errorDir = $jobRunningDir.$AppConfig::errorDir;
	my $archiveStageDetailsFile = $jobRunningDir.$AppConfig::archiveStageDetailsFile;
    my $progressPidFile = Common::getCatfile($jobRunningDir, $AppConfig::progressPidFile);

	if(defined($_[0])) {
		#Removing previous error directory at beginning of next start time only-Senthil
		Common::removeItems([$errorDir,$fileSummaryFile]);
	} else {
		my $pidPath = $jobRunningDir.$AppConfig::pidFile;
		Common::removeItems($pidPath);
	}

	Common::removeItems([$progressPidFile,$archiveFileResultSet,$archiveDirResultSet,$logPidFilePath,$failedFileWithReason,$finalErrorFile,$archiveStageDetailsFile,$archiveFileFailureReasonFile]);
	Common::removeItems([$evsOutputFile,$evsErrorFile,$exitErrorFile,$errorFile,$itemStatusUTFpath,$tempBackupsetFilePath,$failedFiles,$failedDirList,$progressDetailsFilePath,$deletedDirList]);

	return 0;
}

#********************************************************************************
# Subroutine			: getPercentageForCleanup
# Objective				: Get percentage of files for cleanup
# Added By				: Senthil Pandian
#********************************************************************************
sub getPercentageForCleanup {
	my $archivePercentage = 0;
	if($jobType eq 'manual') {
		$archivePercentage = Common::getAndValidate('enter_percentage_of_files_for_cleanup', "percentage_for_cleanup", 1);
		my $displayMsg = Common::getStringConstant('you_have_selected_per_as_cleanup_limit');
		$displayMsg =~ s/<PER>/$archivePercentage/;
		Common::display($displayMsg);
		# sleep(2);
	} else {
		$archivePercentage = int($ARGV[2]);
	}
	return $archivePercentage;
}

#********************************************************************************
# Subroutine			: askToDeleteEmptyDirectories
# Objective				: Get option to cleanup empty directories
# Added By				: Senthil Pandian
#********************************************************************************
sub askToDeleteEmptyDirectories {
	my $option = 0;
	if($jobType eq 'manual') {
		Common::display(["\n",'do_you_want_to_cleanup_empty_directories']);
		my $deleteConfirmation = Common::getAndValidate('enter_your_choice','YN_choice', 1);
		if (lc($deleteConfirmation) eq 'y') {
			$option = 1;
		}
	}
    # We may need to uncomment later
    # elsif(defined($ARGV[4])) {
		# $option = int($ARGV[4]);
	# }
	return $option;
}

#********************************************************************************
# Subroutine			: getDaysBetweenTwoDates
# Objective				: Get days between two dates
# Added By				: Senthil Pandian
#********************************************************************************
sub getDaysBetweenTwoDates{
	my $s1 = $ARGV[3]; #Scheduled Time
	my $days = 0;
	if($s1){
		$days = int((time - $s1)/(24*60*60));
	}
	return $days;
}

#********************************************************************************
# Subroutine			: renameLogFile
# Objective				: Rename the log file name with status
# Added By				: Senthil Pandian
# Modified By			: Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#********************************************************************************
sub renameLogFile{
	return 0 if(!defined($logOutputFile) or !-e $logOutputFile);
	my $isPercentError = $_[0];
	my $error = $_[1];
	# my $skipSummary = $_[2];

	my ($needToDeleteFiles,$exit) = (1,1);
	my ($logOutputFileStatusFile, $status);
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $exitErrorFile = $jobRunningDir.$AppConfig::exitErrorFile;
	if(-e $exitErrorFile){
		# $error = Common::getFileContents($exitErrorFile);
		# writeSummary($isPercentError,$needToDeleteFiles,$exit,$error) unless(defined($skipSummary));
		$status = Common::getStringConstant('aborted');
	}
	elsif($isPercentError){
		$status = Common::getStringConstant('aborted');
	}
	elsif(defined($error) and $error ne ''){
		# writeSummary($isPercentError,$needToDeleteFiles,$exit,$error) unless(defined($skipSummary));
		$status = Common::getStringConstant('aborted');
	}
	elsif(defined($errMsg) and $errMsg =~ /operation aborted/i){
		$status = Common::getStringConstant('aborted');
	}
    elsif($notExistCount>0 and $notExistCount == $deletedFilesCount){
    # Modified for Yuvaraj_2.3_08_2: Senthil
	# elsif($notExistCount == 0 or ($notExistCount>0 and $notExistCount == $deletedFilesCount)){
		$status = Common::getStringConstant('success');
	}
	else {
		$status = Common::getStringConstant('failure');
	}
	$logOutputFileStatusFile = $logOutputFile;
	$logOutputFileStatusFile =~ s/_Running_/_$status\_/;
	system(Common::updateLocaleCmd("mv '$logOutputFile' '$logOutputFileStatusFile'"));
	Common::display('for_more_details_refer_the_log', 1) if($jobType eq 'manual');

	$AppConfig::finalSummary .= qq(\n).Common::getStringConstant('for_more_details_refer_the_log').qq(\n);
	Common::fileWrite("$jobRunningDir/$AppConfig::fileSummaryFile",$AppConfig::finalSummary);

    Common::saveLog($logOutputFileStatusFile, 0);

	my $tempOutputFilePath = $logOutputFile;
	$tempOutputFilePath = (split("_Running_",$tempOutputFilePath))[0] if($tempOutputFilePath =~ m/_Running_/);
	my @endTime = localtime();
	my %logStat = (
		(split('_', Common::basename($logOutputFile)))[0] => {
			'datetime' => Common::strftime("%m/%d/%Y %H:%M:%S", localtime(Common::mktime(@startTime))),
			'duration' => (Common::mktime(@endTime) - Common::mktime(@startTime)),
			'filescount' => $notExistCount,
			'status' => $status."_".ucfirst($jobType)
		}
	);

	if($jobType eq 'periodic'){
		my $userName = Common::getUsername();
		my $statusReport = Common::getStringConstant('status_report');
		my $subjectLine = Common::getStringConstant('periodic_archive_cleanup')." $statusReport [$userName] [$status]";
		#Ex-Sub: Periodic Cleanup Status Report [idrive_user] [Success]
		Common::sendMail({
			'serviceType' => $jobType,
			'jobType' => 'archive',
            'jobName' => 'default_backupset',
			'subject' => $subjectLine,
			'jobStatus' => lc($status),
		});
	}

	Common::addLogStat($jobRunningDir, \%logStat);

	if (Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
		Common::setNotification('get_logs') and Common::saveNotifications();
		Common::unlockCriticalUpdate("notification");
	}

	return 1;
}

#********************************************************************************
# Subroutine			: mergeAllArchivedFiles
# Objective				: Merge all archive list files
# Added By				: Senthil Pandian
#********************************************************************************
sub mergeAllArchivedFiles{
	my $archiveResultSetDir = $_[0];
	my $jobRunningDir    = Common::getJobsPath('archive');
	my $archiveResultSet = $jobRunningDir.$archiveResultSetDir;	
	my $archiveFileView  = $jobRunningDir.$AppConfig::archiveFileListForView;
	my $pidPath 		 = $jobRunningDir.$AppConfig::pidFile;

	#Appending content of a file to another file
	if(opendir(DIR, $archiveResultSet)) {
		foreach my $file (readdir(DIR))  {
			if( !-e $pidPath) {
				last;
			}
			chomp($file);
			unless($file =~ m/.txt/) {
				next;
			}
			my $temp = $archiveResultSet."/".$file;
			if(-s $temp>0){
				my $appendFiles = "cat '$temp' >> '$archiveFileView'";
				$appendFiles = Common::updateLocaleCmd($appendFiles);
				system($appendFiles);
			}
		}
		closedir(DIR);
	}
	chmod 0555,$archiveFileView;#Read-only
	return $archiveFileView;
}

#********************************************************************************
# Subroutine			: writeSummary
# Objective				: Append/display summary of delete operation
# Added By				: Senthil Pandian
#********************************************************************************
sub writeSummary{
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $isPercentError = $_[0];
	my $needToDeleteFiles = $_[1];
	my $exit = $_[2];
	my $errorMsg = $_[3];

	my ($reason,$summary,$emptyDirDeleteSummary)  = ('') x 3;
	if($needToDeleteFiles) {
		if(-f $logOutputFile and !$isPercentError) {
			appendDeletedItems(); #To append deleted items list when job terminated
			consolidateFailedFilesAndError();
			my $finalErrorContent = finalFailedFilesAndDirs();
			# addEmptyDeletedContent();
			#Appending error content to log file
			if($finalErrorContent ne '') {
				print ARCHIVELOG Common::getStringConstant('archive_error_report');
				print ARCHIVELOG $finalErrorContent."\n";
			}

			my $errorContent = getErrorContent();
			#Appending error content to log file
            Common::Chomp(\$errorContent);
            Common::Chomp(\$finalErrorContent);
			if($errorContent ne '' and $errorContent ne $finalErrorContent) {
				print ARCHIVELOG Common::getStringConstant('additional_information');
				print ARCHIVELOG $errorContent."\n\n";
			}
		}

		$summary  = Common::getStringConstant('summary_for_files_delete');
        $summary .= (('-')x 26)."\n";
		if(-f $jobRunningDir.$AppConfig::archiveFileFailureReasonFile) {
			$summary .= Common::getFileContents($jobRunningDir.$AppConfig::archiveFileFailureReasonFile);
		} elsif(!$isPercentError) {
			$summary   .= Common::getStringConstant('files_considered_for_delete').$notExistCount."\n";
			$summary   .= Common::getStringConstant('files_deletes_now').$deletedFilesCount."\n";
			if($exit){
				if($failedFileCount) {
					$summary .= Common::getStringConstant('files_failed_to_delete').$failedFileCount."\n\n";
				} else {
					$summary .= Common::getStringConstant('files_failed_to_delete')."0\n\n";
				}
				$reason = $errorMsg."\n" if($errorMsg);
			}
			else {
				$summary .= Common::getStringConstant('files_failed_to_delete').($notExistCount-$deletedFilesCount)."\n\n";
			}
		} elsif($errorMsg) {
			$summary .= $errorMsg."\n";
		}
	}
	elsif(-f $jobRunningDir.$AppConfig::archiveFileFailureReasonFile) {
		#Added to handle the summary when cancelling job if no one file deleted due percentage or no file to delete
		$summary  = Common::getStringConstant('summary_for_files_delete');
        $summary .= (('-')x 26)."\n";
		$summary .= Common::getFileContents($jobRunningDir.$AppConfig::archiveFileFailureReasonFile);
        # $summary .= "\n\n";
		$reason = $errorMsg."\n" if($errorMsg);
	}
	else {
		# $summary .= "\n" unless($exit);
		$summary .= $errorMsg."\n";
	}

	if($isDeleteEmptyDir)
	{
		$emptyDirDeleteSummary .= Common::getStringConstant('summary_for_empty_directories_delete');
        $emptyDirDeleteSummary .= (('-')x 38)."\n";

		if($foldersCountToBeDeleted) {			
			$emptyDirDeleteSummary .= Common::getStringConstant('empty_directory_considered_for_delete').$foldersCountToBeDeleted."\n";
			$emptyDirDeleteSummary .= Common::getStringConstant('empty_directory_deleted_now').$deletedDirCount."\n";
			if($archiveStage eq 'deleting_empty_directories' or $archiveStage eq 'empty_dir_delete_operation_completed') {
				$emptyDirDeleteSummary .= Common::getStringConstant('empty_directory_failed_to_delete').($foldersCountToBeDeleted-$deletedDirCount)."\n\n";
			} else {
				$emptyDirDeleteSummary .= Common::getStringConstant('empty_directory_failed_to_delete')."0\n\n";
			}
		} else {
			$emptyDirDeleteSummary .= Common::getStringConstant('no_empty_directories_to_delete')."\n\n";
		}
	}
	$AppConfig::mailContent  .= $summary.$emptyDirDeleteSummary;
	$AppConfig::finalSummary .= $summary.$emptyDirDeleteSummary.$reason;
    # $summary .= $emptyDirDeleteSummary if($jobType eq 'periodic' or $needToDeleteFiles or $isPercentError);
    $summary .= $emptyDirDeleteSummary;
    
    $AppConfig::mailContent =~ s/[-]+\n//g; #Removing underline from headings
    
    if(-f $logOutputFile) {
		print ARCHIVELOG $summary;
		my $logEndTime = `date +"%a %b %d %T %Y"`;
		Common::Chomp(\$logEndTime); #Removing white-space and '\n'
		print ARCHIVELOG Common::getStringConstant('archive_cleanup').' '.Common::getStringConstant('end_time').$logEndTime."\n";
		print ARCHIVELOG $reason;
		close ARCHIVELOG; #Closing to log file handle
        $AppConfig::mailContent .= Common::getStringConstant('archive_cleanup').' '.Common::getStringConstant('end_time').$logEndTime;
	}

	if($jobType eq 'manual')
	{
		$summary .= $reason;
        my $tempSummary = $summary;
        Common::Chomp(\$tempSummary);
		Common::display(["\n",$summary]) if($tempSummary);
	}

	if($deletedFilesCount)
	{
		my $csf = Common::getCachedStorageFile();
		Common::removeItems($csf);
	}
}

#****************************************************************************************************
# Subroutine Name         : createResultSetForFiles
# Objective               : This function will generate 1000 result set Files
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub createResultSetForFiles {
	$tempNoOfResultSetFiles++;
	close ARCHIVE_FILE_HANDLE if ($tempNoOfResultSetFiles>1);

	my $archiveFileList = $_[0]."_".$tempNoOfResultSetFiles;
	if(!open(ARCHIVE_FILE_HANDLE, ">", $archiveFileList)) {
        my $errMsg = Common::getStringConstant('failed_to_open_file').": $archiveFileList. Reason:$!";
		Common::traceLog($errMsg);
        exitCleanup(1,$errMsg);
	}
    return 1;
}

#****************************************************************************************************
# Subroutine Name         : getFailedItemList
# Objective               : This function will generate failed result set Files to Retry
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getFailedItemList {
	my $archiveFileDirPath  = $_[0];
	my $totalResultSetCount = $_[1];
	my $totalNoOfRetry      = $_[2];
	my $lastSet = $_[3];
	my %archivedFileHash = %{$_[4]};

	return unless($$totalNoOfRetry);

	my $failedList = '';
	foreach my $fileName (keys %archivedFileHash)
	{
		$failedList .= $fileName."\n" unless($archivedFileHash{$fileName});
	}

	if($failedList ne '') {
		$noOfResultSetFiles++;
		Common::fileWrite($archiveFileDirPath."_".$noOfResultSetFiles,$failedList);
	}

	if($lastSet) {
		$$totalNoOfRetry--;
		$$totalResultSetCount = $noOfResultSetFiles;
	}
}

#****************************************************************************************************
# Subroutine Name         : getArchivedFileHash
# Objective               : This function will generate hash for the current result set
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getArchivedFileHash {
	my $resultSetFilePath = $_[0];
	my %archivedFileHash = ();
	if(!open(RESULTLIST, $resultSetFilePath)){
		my $errMsg = Common::getStringConstant('failed_to_open_file').": $resultSetFilePath, Reason: $!";
		Common::traceLog($errMsg);
		return 0;
	}

	while(<RESULTLIST>) {
		Common::Chomp(\$_);
		$archivedFileHash{$_}=0;
	}
	close RESULTLIST;
	return %archivedFileHash;
}

#****************************************************************************************************
# Subroutine Name         : consolidateDeletedFileListAndLog
# Objective               : This function will consolidate the deleted file List and append Log
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub consolidateDeletedFileListAndLog {
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $pidPath 	   = $jobRunningDir.$AppConfig::pidFile;
	my $deletedDirList = $jobRunningDir.$AppConfig::deletedDirList;
	my $archiveFileResultSet = $jobRunningDir.$AppConfig::archiveFileResultSet;
	my @matchedFileName = ();
	my @deletedDirArray = ();
	if(-f $deletedDirList) {
		my $deletedDirs = Common::getFileContents($deletedDirList);
		@deletedDirArray = split("\n",$deletedDirs);
	}

	if(($notExistCount-$deletedFilesCount) > 0 and $deletedDirCount > 0 and -d $archiveFileResultSet) {
		if(opendir(DIR, $archiveFileResultSet)) {
			foreach my $file (readdir(DIR))  {
				chomp($file);
				if( !-e $pidPath) {
					last;
				} elsif($file eq '' or $file =~ /^\./) {
					next;
				}
				my $failedFile = $archiveFileResultSet.'/'.$file;
				if(-f $failedFile) {
					my $failedFilesList = Common::getFileContents($failedFile);
					my @failedFilesArray = split("\n",$failedFilesList);
					my $failedFileList = '';
					foreach my $fileName (@failedFilesArray) {
						my $isMatched = 0;
						foreach my $dirName (@deletedDirArray) {
							my $tempDirName = quotemeta($dirName);
							if($fileName =~ m/^$tempDirName/) {
								push(@matchedFileName,$fileName);
								$deletedFilesCount++;
								$isMatched = 1;
							}							
						}
						$failedFileList .= $fileName."\n" unless($isMatched);						
					}
					Common::fileWrite($failedFile,$failedFileList);
				} else {
					Common::traceLog(['file_not_found', ": $failedFile, Reason: $!"]);
				}
			}
		}
		else {
			Common::traceLog(['failed_to_open_directory', ": $archiveFileResultSet, Reason: $!"]);
			return 0;
		}

		if(@matchedFileName) {
			foreach my $fileName (@matchedFileName) {
				print ARCHIVELOG "[deleted] [$fileName]\n"; #Appending deleted file detail to log file
			}
			updateFailedFileErrorContent(@matchedFileName);
		}
	}
    print ARCHIVELOG "\n" if($deletedFilesCount);

	#Appending deleted empty directories log
	$archiveStage = 'deleting_empty_directories';
	if(@deletedDirArray) {
        print ARCHIVELOG Common::getStringConstant('deleted_content_directories');
		foreach my $dirName (@deletedDirArray) {
			print ARCHIVELOG "[deleted] [$dirName]\n"; #Appending deleted file detail to log file
		}
        print ARCHIVELOG "\n";
	}
	$archiveStage = 'empty_dir_delete_operation_completed';
}

#****************************************************************************************************
# Subroutine Name         : createUserLogFiles
# Objective               : This function will create user log files & add header
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub createUserLogFiles {
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $logPidFilePath = Common::getCatfile($jobRunningDir, $AppConfig::logPidFile);
	my $archiveLogDirpath = $jobRunningDir.$AppConfig::logDir;
	Common::createDir($archiveLogDirpath, 1);
	$AppConfig::jobRunningDir = $jobRunningDir; #Added by Senthil

    @startTime  = localtime();
	$logOutputFile = Common::createLogFiles("ARCHIVE",ucfirst($jobType));
	my $logStartTime = `date +"%a %b %d %T %Y"`;
	Common::Chomp(\$logStartTime); #Removing white-space and '\n'

	#Opening to log file handle
	if(!open(ARCHIVELOG, ">", $logOutputFile)){
        my $errStr = Common::getStringConstant('failed_to_open_file').": $logOutputFile. Reason:$!";
		exitCleanup(1,$errStr);
	}
	Common::fileWrite($logPidFilePath,$logOutputFile);

    my $userHead = "[".ucfirst(Common::getStringConstant('username')).": ".Common::getUsername()."] ";
    my $logHead = '';
	my $host = Common::updateLocaleCmd('hostname');
	$host = `$host`;
	chomp($host);
	$logHead .= "[".Common::getStringConstant('title_machine_name').$host."] ";
    $logHead .= "[".Common::getStringConstant('operation').": ";
    if($jobType eq 'periodic'){
		$logHead .= Common::getStringConstant('periodic_archive_cleanup')."] ";
	} else {
		$logHead .= Common::getStringConstant('archive')."] ";
	}
	$logHead .= "[".Common::getStringConstant('cleanup_empty_directories').": ".Common::getStringConstant($isDeleteEmptyDir.'_status')."]\n\n";
	$logHead .= Common::getStringConstant('archive_cleanup').' '.Common::getStringConstant('start_time').$logStartTime."\n\n";
	print ARCHIVELOG $userHead.$logHead;
	$AppConfig::mailContentHead = $logHead;
}

#****************************************************************************************************
# Subroutine Name         : getErrorContent
# Objective               : This function will read the failed files/folders EVS error content
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getErrorContent {
	my $errorContent = '';
	my $jobRunningDir = Common::getJobsPath('archive');
	my $errorDir = $jobRunningDir.$AppConfig::errorDir;

	if(-d $errorDir)
	{
		if(opendir(DIR, $errorDir)) {
			foreach my $file (readdir(DIR))  {
				chomp($file);
				if($file eq '' or $file =~ /^\./) {
					next;
				}
				my $finalErrorFile = $errorDir.'/'.$file;
				if(-f $finalErrorFile) {
					$errorContent .= Common::getFileContents($finalErrorFile);
				}
			}
		}
	}
	return $errorContent;
}

#****************************************************************************************************
# Subroutine Name         : finalFailedFilesAndDirs
# Objective               : This function will read the final failed files/folders list for Log
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub finalFailedFilesAndDirs {
	my $errorContent = '';
	my $jobRunningDir = Common::getJobsPath('archive');
	my $pidPath = $jobRunningDir.$AppConfig::pidFile;
	my @dirList = ($jobRunningDir.$AppConfig::archiveFileResultSet);
	my $failedFileWithReason = $jobRunningDir.$AppConfig::failedFileWithReason;
	my $finalErrorFile = $jobRunningDir.$AppConfig::finalErrorFile;
	$errorContent .= Common::getFileContents($failedFileWithReason) if(-f $failedFileWithReason and !-z _);
	$errorContent .= Common::getFileContents($finalErrorFile) if(-f $finalErrorFile and !-z _);

	push(@dirList,$jobRunningDir.$AppConfig::archiveDirResultSet) if (defined($isDeleteEmptyDir) and $isDeleteEmptyDir);

	if(-e $pidPath) {
		foreach my $dirName (@dirList) {
			if(-d $dirName)
			{
				if(opendir(DIR, $dirName)) {
					foreach my $file (readdir(DIR))  {
						chomp($file);
						if($file eq '' or $file =~ /^\./) {
							next;
						}
						my $finalErrorFile = $dirName.'/'.$file;
						if(-f $finalErrorFile) {
							$errorContent .= Common::getFileContents($finalErrorFile);
						}
					}
				}
			}
		}
	}
	return $errorContent;
}

#****************************************************************************************************
# Subroutine		: updateFailedFileErrorContent
# Objective			: This function will remove the failed files from EVS error content if parent directory deleted & update
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub updateFailedFileErrorContent {
	my @matchedFileList = @_;
	my ($errorContent,$errStr) = ('') x 2;
	my $jobRunningDir = Common::getJobsPath('archive');
	my $errorDir = $jobRunningDir.$AppConfig::errorDir;
	if(-d $errorDir)
	{
		if(opendir(DIR, $errorDir)) {
			foreach my $file (readdir(DIR))  {
				chomp($file);
				if($file eq '' or $file =~ /^\./ or $file =~ /^dir/ ) {
					next;
				}

				my $evsErrorFile = $errorDir.'/'.$file;
				if(-f $evsErrorFile and !-z _) {
					open ERRORFH, "<", $evsErrorFile or ($errStr = Common::getStringConstant('failed_to_open_file').":$evsErrorFile. Reason:$!");
					if($errStr ne ""){
						Common::traceLog($errStr);
						return 0;
					}

					my $finalErrorFile = $errorDir.'/'.$AppConfig::finalErrorFile;
					if(!open(FINALERRORFH, ">>", $finalErrorFile)){
						$errMsg = Common::getStringConstant('failed_to_open_file').": $finalErrorFile, Reason: $!";
						Common::traceLog($errMsg);
						return 0;
					}

					my ($buffer,$lastLine) = ("") x 2;
					while(1){
						my $byteRead = read(ERRORFH, $buffer, $AppConfig::bufferLimit);
						last if($byteRead == 0);
						if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
							$buffer = $lastLine . $buffer;
						}

						$lastLine = "";
						my @errorFileContent = split /\n/, $buffer;
						if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
							$lastLine = pop @errorFileContent;
						}

						foreach my $errorLine (@errorFileContent){
							my $isMatched = 0;
							for(my $i = 0; $i <= $#matchedFileList; $i++){	
								my $tempFileName = quotemeta($matchedFileList[$i]);
								if($errorLine =~ /$tempFileName/){
									$isMatched = 1;
									splice @matchedFileList, $i, 1;
									last;
								}
							}
							print FINALERRORFH $errorLine."\n" unless($isMatched);
						}
					}
					close FINALERRORFH;
				}
			}
		}
	}
}

#****************************************************************************************************
# Subroutine		: consolidateFailedFilesAndError
# Objective			: This function will consolidate the final failed files/folders list and error
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub consolidateFailedFilesAndError {
	return unless($notExistCount and ($notExistCount-$deletedFilesCount));
	my ($errorContent,$errStr) = ('') x 2;
	my $jobRunningDir = Common::getJobsPath('archive');
	my @dirList  = ($jobRunningDir.$AppConfig::archiveFileResultSet, $jobRunningDir.$AppConfig::archiveDirResultSet);
	my $errorDir = $jobRunningDir.$AppConfig::errorDir;

	my $failedFileWithReason = $jobRunningDir.$AppConfig::failedFileWithReason;
	my $finalErrorFile = $jobRunningDir.$AppConfig::finalErrorFile;
	if(!open(FALIEDFH, ">", $failedFileWithReason)){
		$errMsg = Common::getStringConstant('failed_to_open_file').": $failedFileWithReason, Reason: $!";
		Common::traceLog($errMsg);
		return 0;
	}
	if(!open(FINALERRORFH, ">", $finalErrorFile)){
		$errMsg = Common::getStringConstant('failed_to_open_file').": $finalErrorFile, Reason: $!";
		Common::traceLog($errMsg);
		return 0;
	}

	foreach my $dirName (@dirList) {
		if(-d $dirName)
		{
			if(opendir(DIR, $dirName)) {
				foreach my $file (readdir(DIR))  {
					chomp($file);
					if($file eq '' or $file =~ /^\./) {
						next;
					}
					my $failedFile = $dirName.'/'.$file;
					my $errorFile = $errorDir.'/'.$file."_ERROR";
					
					if((-f $errorFile and !-z _) and (-f $failedFile and !-z _)) {
						my $errorList = Common::getFileContents($errorFile);
						my @errorListArray = split("\n",$errorList);

						my $failedFilesList = Common::getFileContents($failedFile);
						my @failedFilesArray = split("\n",$failedFilesList);
						my $failedFileList = '';

						foreach my $fileName (@failedFilesArray) {
							next unless(defined($fileName));

							my $i=0;
							my $isMatched = 0;
							foreach my $errorLine (@errorListArray) {
								unless(defined($errorLine))
								{
									$i++;
									next;
								}
								my $tempFileName = quotemeta($fileName);
								if($errorLine =~ m/\[$tempFileName\]/) {									
									$isMatched = 1;
									print FALIEDFH $errorLine."\n";
									$failedFileCount++;
									$errorListArray[$i] = undef;
								}
								$i++;
							}
							$failedFileList .= $fileName."\n" unless($isMatched);
						}
						
						foreach my $errorLine (@errorListArray) {
							print FINALERRORFH $errorLine."\n" if(defined($errorLine));
						}
						Common::fileWrite($failedFile,$failedFileList);
					}
				}
			}
			else {
				$errMsg = Common::getStringConstant('failed_to_open_directory').": $dirName, Reason: $!";
				Common::traceLog($errMsg);
			}
		}
	}

	close FINALERRORFH;
	close FALIEDFH;
}

#****************************************************************************************************
# Subroutine Name   : appendDeletedItems
# Objective         : This function will consolidate the final failed files/folders list and error
# Added By          : Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub appendDeletedItems {
	my $jobRunningDir = Common::getJobsPath('archive');
	my $evsErrorFile  = $jobRunningDir.$AppConfig::evsErrorFile;
	unless(-f  $evsErrorFile) {
        return 1;
    }

	my $archiveFileResultSet = $jobRunningDir.$AppConfig::archiveFileResultSet;
	#Appending deleted empty directories log
	my $deletedFileList = $archiveFileResultSet.'/'.$AppConfig::deletedFileList;
	if(-f $deletedFileList and !-z _) {
		print ARCHIVELOG Common::getStringConstant('deleted_content_files');
		print ARCHIVELOG Common::getFileContents($deletedFileList)."\n";
		Common::removeItems($deletedFileList);
	}

	my $deletedDirList = $jobRunningDir."/".$AppConfig::deletedDirList;
	if(-f $deletedDirList and !-z _) {
		consolidateDeletedFileListAndLog();
	}
}

#*****************************************************************************************************
# Subroutine/Function   : addEmptyDeletedContent
# In Param  : jobType, jobName
# Out Param : Next Schedule Date
# Objective	: This subroutine to add the empty Deleted Content for empty directories
# Added By	: Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub addEmptyDeletedContent {
	if($isDeleteEmptyDir and ($archiveStage eq 'deleting_empty_directories' or $archiveStage ne 'empty_dir_delete_operation_completed')) {
		print ARCHIVELOG Common::getStringConstant('operation_has_been_aborted')."\n" if($notExistCount and !$deletedFilesCount);
		print ARCHIVELOG Common::getStringConstant('deleted_content_directories');
		print ARCHIVELOG Common::getStringConstant('operation_has_been_aborted')."\n";
	}
}

#*****************************************************************************************************
# Subroutine/Function   : forkTodisplayArchiveProgressBar
# In Param    : 
# Out Param   : fork process id($displayProgressBarPid)
# Objective	  : This subroutine to display archive progress bar in fork(dedicated) process.
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub forkTodisplayArchiveProgressBar {
    my $jobRunningDir           = Common::getJobsPath('archive');
    my $pidPath                 = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
    my $progressPidFile         = Common::getCatfile($jobRunningDir, $AppConfig::progressPidFile);
	my $progressDetailsFilePath = Common::getCatfile($jobRunningDir, $AppConfig::progressDetailsFilePath);

    return if($jobType ne 'manual');
    
    my $displayProgressBarPid = fork();
    if(!defined $displayProgressBarPid) {
        $AppConfig::errStr = Common::getStringConstant('unable_to_display_progress_bar');
        Common::traceLog($AppConfig::errStr);
        # return 0;
    } 
    elsif($displayProgressBarPid == 0) {
        $forkProcess = 1;
        Common::fileLock($progressPidFile);
        while(-f $pidPath and -f $progressPidFile and -f $progressDetailsFilePath){
            # my $progressMsg = Common::getFileContents($progressDetailsFilePath);
            # Common::displayProgress($progressMsg,2);
            Common::displayArchiveProgressBar($progressDetailsFilePath);
            Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);
        }
        Common::displayArchiveProgressBar($progressDetailsFilePath);
        exit(0);
    }
    return $displayProgressBarPid;
}

#*****************************************************************************************************
# Subroutine/Function   : isFilesBeyondPercentage
# In Param    : 
# Out Param   : 0 or 1
# Objective	  : This subroutine to check the percentage limit.
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub isFilesBeyondPercentage {
    my $isPercentError    = 0;
    my $archivePercentage = $_[0];
    my $notExistCount     = $_[1];
    my $totalFileCount    = $_[2];

    #Calculating the % of files for cleanup
    my $perCount = ($notExistCount/$totalFileCount)*100;

    #Ex: if $perCount is 1.45. Difference value of integer is less than 0.5 then value will be considered as 1.
    $perCount = ((($perCount-int($perCount))<0.5) ? int($perCount) : int($perCount)+1);

    if($archivePercentage < $perCount)
    {
        my $reason = Common::getStringConstant('delete_operation_aborted_due_to_percentage');
        $reason =~ s/<TOTAL_FILES>/$totalFileCount/;
        $reason =~ s/<PER1>/$perCount/;
        $reason =~ s/<PER2>/$archivePercentage/;
        my $errMsg .= Common::getStringConstant('files_considered_for_delete').$notExistCount."\n";
        $errMsg .= Common::getStringConstant('files_deletes_now')."0\n";
        $errMsg .= Common::getStringConstant('files_failed_to_delete')."0\n";               
        $errMsg .= $reason."\n";
        $isPercentError = 1;
        # Common::removeItems($archiveFileResultSet);
        my $jobRunningDir = Common::getJobsPath('archive');
        Common::fileWrite($jobRunningDir.$AppConfig::archiveFileFailureReasonFile,$errMsg);
    }

    return $isPercentError;
}

#*****************************************************************************************************
# Subroutine/Function   : getConfirmationToViewArchiveList
# In Param    : 
# Out Param   : y or n
# Objective	  : This subroutine to get confirmation whether user want to view files to be deleted or not.
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub getConfirmationToViewArchiveList {
    my $jobRunningDir = Common::getJobsPath('archive');
    my $pidPath       = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
    my $toViewConfirmation = 'n';
    
    $toViewConfirmation = Common::getAndValidate('enter_your_choice','YN_choice',1,1,undef,1);
    #Exiting process if there is no proper input
    exitCleanup(1,$errMsg) if($toViewConfirmation eq 'exit');

    return $toViewConfirmation;
}

#*****************************************************************************************************
# Subroutine/Function   : displayStatusAndConfirmationMsgToView
# In Param    : file/directory, foldersCountToBeDeleted
# Out Param   : 
# Objective	  : This subroutine to display confirmation message.
# Added By	  : Senthil Pandian
#****************************************************************************************************/
sub displayStatusAndConfirmationMsgToView {
    if($_[0] eq 'file') {
        my $scannedInfo   = Common::getStringConstant('total_files_scanned_and_to_be_deleted');
        $scannedInfo =~ s/<SCANNED>/$totalFileCount/;
        $scannedInfo =~ s/<FOUND>/$notExistCount/;
        Common::display(["\n","$scannedInfo ",'do_you_want_view_files_y_or_n'], 1);
    } 
    else {
        if($_[1]>1){
            Common::display(["\n","$foldersCountToBeDeleted ",'empty_directories_are_present_in_your_account','do_you_want_view_directories_y_or_n'], 1);
        } else {
            Common::display(["\n","$foldersCountToBeDeleted ",'empty_directory_is_present_in_your_account','do_you_want_view_directories_y_or_n'], 1);
        }
    }
}

#*****************************************************************************************************
# Subroutine/Function   : getBackupLocation
# In Param    : 
# Out Param   : $backupLocation
# Objective	  : This subroutine to get & return backup location in proper format.
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub getBackupLocation {
	my $backupLocation = Common::getUserConfiguration('BACKUPLOCATION');
	$backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
	$backupLocation = Common::removeMultipleSlashs($backupLocation);
	$backupLocation = Common::removeLastSlash($backupLocation);
    return $backupLocation;
}

#*****************************************************************************************************
# Subroutine/Function   : dedupSearchOutputParse 
# In Param    : 
# Out Param   : 
# Objective	  : This subroutine to parse the output of dedup search operation.
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub dedupSearchOutputParse  {
    my $tempEvsOutputFile = $_[0];
    my $tempEvsErrorFile  = $_[1];
    my $remoteFolder      = $_[2];
    my $jobRunningDir     = Common::getJobsPath('archive');
    my $pidPath           = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
	my $archiveFileResultSet = $jobRunningDir.$AppConfig::archiveFileResultSet;
	my $archiveFileList      = $archiveFileResultSet.'/'.$AppConfig::archiveFileResultFile;
    my $errStr = "";
    ($tempTotalFileCount, $tempNotExistCount) = (0) x 2;
    %tempIsDirHaveFiles = ();

	# parse search output.
	open my $SEARCHOUTFH, "<", $tempEvsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').":$tempEvsOutputFile. Reason:$!");
	if($errStr ne ""){
		Common::traceLog($errStr);
		return 0;
	}

	my $progressDetailsFilePath = $jobRunningDir.$AppConfig::progressDetailsFilePath;
	my @PROGRESSFILE;
	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	chmod $AppConfig::filePermission, $progressDetailsFilePath;

	my ($buffer,$lastLine) = ("") x 2;
	my $skipFlag = 0;

    while(1){
        my $byteRead = read($SEARCHOUTFH, $buffer, $AppConfig::bufferLimit);
        if($byteRead == 0) {
            if(!-e $pidPath or (-e $tempEvsErrorFile and -s _)) {
                last;
            }
            sleep(2);
            seek($SEARCHOUTFH, 0, 1);		#to clear eof flag
            next;
        }

        if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
            $buffer = $lastLine . $buffer;
        }

        $lastLine = "";
        my @resultList = split /\n/, $buffer;
        if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
            $lastLine = pop @resultList;
        }

        foreach my $tmpLine (@resultList){
            if($tmpLine =~ /fname/) {
                my %fileName = Common::parseXMLOutput(\$tmpLine);

                if (!defined($fileName{'fname'}) or !defined($fileName{'restype'})) {
                    #Splitting file & directory name & marking directory that having file in remote
                    my @parentDir = Common::fileparse($remoteFolder);
                    $tempIsDirHaveFiles{$parentDir[1]} = DIR_NOT_TO_REMOVE;
                    next;
                }

                my $fname = $fileName{'fname'};
                Common::replaceXMLcharacters(\$fname);
                if ($fileName{'restype'} eq "F"){
                    $tempTotalFileCount++;
                    if (!-f $fname) {
                        if ($tempNotExistCount and ($tempNotExistCount%$resultSetLimit) == 0) {
                            createResultSetForFiles($archiveFileList);
                        }
                        print ARCHIVE_FILE_HANDLE $fname."\n";
                        $tempNotExistCount++;
                        fillDirectoryHasItemsToDelete($fname);
                    } else {
                        #Splitting file & directory name & marking directory that having file in remote
                        my @parentDir = Common::fileparse($fname);
                        $tempIsDirHaveFiles{$parentDir[1]} = DIR_NOT_TO_REMOVE;
                    }

                    $PROGRESSFILE[1] = Common::getStringConstant('files_scanned')." ".($totalFileCount+$tempTotalFileCount);
                    $PROGRESSFILE[2] = "Scanning... $fname";
                } elsif (!defined($tempIsDirHaveFiles{$fname})) {
                    $tempIsDirHaveFiles{$fname} = DIR_EMPTY;
                }
            }
            elsif($tmpLine ne ''){
                if($tmpLine =~ m/(files_found|items_found)/){
                    $skipFlag = 1;
                } elsif($tmpLine =~ m/failed to retrieve the information/){
                    last;
                } elsif($tmpLine !~ m/(connection established|receiving file list)/) {
                    Common::traceLog("Archive search:".$tmpLine);
                }
            }
        }
        last if($skipFlag);
    }
	close($SEARCHOUTFH);
	untie @PROGRESSFILE; 
    return $skipFlag;
}

#*****************************************************************************************************
# Subroutine/Function   : nondedupSearchOutputParse 
# In Param    : 
# Out Param   : 
# Objective	  : This subroutine to parse the output of nondedup search operation.
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub nondedupSearchOutputParse  {
    my $tempEvsOutputFile = $_[0];
    my $tempEvsErrorFile  = $_[1];
    my $remoteFolder      = $_[2];
    my $jobRunningDir     = Common::getJobsPath('archive');
    my $pidPath           = Common::getCatfile($jobRunningDir, $AppConfig::pidFile);
    my $backupLocation    = getBackupLocation();
	my $archiveFileResultSet = $jobRunningDir.$AppConfig::archiveFileResultSet;
	my $archiveFileList      = $archiveFileResultSet.'/'.$AppConfig::archiveFileResultFile;

    my $errStr = "";
    ($tempTotalFileCount, $tempNotExistCount) = (0) x 2;
    %tempIsDirHaveFiles = ();

	# parse search output.
	open my $SEARCHOUTFH, "<", $tempEvsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').":$tempEvsOutputFile. Reason:$!");
	if($errStr ne ""){
		Common::traceLog($errStr);
		return 0;
	}

	my $progressDetailsFilePath = $jobRunningDir.$AppConfig::progressDetailsFilePath;
	my @PROGRESSFILE;
	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	chmod $AppConfig::filePermission, $progressDetailsFilePath;

	my ($buffer,$lastLine) = ("") x 2;
	my $skipFlag = 0;

    while(1){
        my $byteRead = read($SEARCHOUTFH, $buffer, $AppConfig::bufferLimit);
        if($byteRead == 0) {
            if(!-e $pidPath or (-e $tempEvsErrorFile and -s _)) {
                last;
            }
            sleep(2);
            seek($SEARCHOUTFH, 0, 1);		#to clear eof flag
            next;
        }

        if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
            $buffer = $lastLine . $buffer;
        }
        
        $lastLine = "";
        my @resultList = split /\n/, $buffer;
        if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
            $lastLine = pop @resultList;
        }

        foreach my $tmpLine (@resultList){
            #print "\ntemp tmpLine::$tmpLine\n";
            if($tmpLine =~ /fname/) {
                my %fileName = Common::parseXMLOutput(\$tmpLine);

                if (!defined($fileName{'fname'}) or !defined($fileName{'file_ver'})) {
                    #Splitting file & directory name & marking directory that having file in remote
                    my @parentDir = Common::fileparse($remoteFolder);
                    $tempIsDirHaveFiles{$parentDir[1]} = DIR_NOT_TO_REMOVE;
                    next;
                }

                my $fname = $fileName{'fname'};
                #print "temp fileName::$fname\n";
                Common::replaceXMLcharacters(\$fname);
                my $tempItemName = $fname;
                $tempItemName =~ s/$backupLocation//;
                if ($fileName{'file_ver'}>=1) {
                    $tempTotalFileCount++;
                    if (!-f $tempItemName) {
                        if ($tempNotExistCount and ($tempNotExistCount%$resultSetLimit) == 0) {
                            createResultSetForFiles($archiveFileList);
                        }
                        print ARCHIVE_FILE_HANDLE $fname."\n";
                        $tempNotExistCount++;
                        fillDirectoryHasItemsToDelete($fname);
                    } else {
                        #Splitting file & directory name & marking directory that having file in remote
                        my @parentDir = Common::fileparse($fname);
                        $tempIsDirHaveFiles{$parentDir[1]} = DIR_NOT_TO_REMOVE;
                    }
                }  elsif(!defined($tempIsDirHaveFiles{$fname})) {
                    $tempIsDirHaveFiles{$fname} = DIR_EMPTY;
                }

                $PROGRESSFILE[1] = Common::getStringConstant('files_scanned')." ".($totalFileCount+$tempTotalFileCount);
                $PROGRESSFILE[2] = "Scanning... $fname";
            }
            elsif($tmpLine ne ''){
                if($tmpLine =~ m/(files_found|items_found)/){
                    $skipFlag = 1;
                } elsif($tmpLine =~ m/failed to retrieve the information/) {
                    last;
                } elsif($tmpLine !~ m/(connection established|receiving file list)/) {
                    Common::traceLog("Archive search:".$tmpLine);
                }
            }
        }
        last if($skipFlag);
    }
	close($SEARCHOUTFH);
	untie @PROGRESSFILE;

    return $skipFlag;
}

#*****************************************************************************************************
# Subroutine/Function   : removePartialSearchResultSetFiles 
# In Param    : 
# Out Param   : 
# Objective	  : This subroutine to remove partial search result set files
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub removePartialSearchResultSetFiles  {
    my $start = $_[0];
    my $end   = $_[1];
    my $archiveFileList = $_[2];
    for(my $i = $start+1; $i <= $end; $i++ ){
        Common::removeItems($archiveFileList."_".$i);
    }
}