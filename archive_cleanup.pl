#!/usr/bin/env perl
#***************************************************************************************************************
# Find and deletes data permanently which no longer exists on local computer to free up space in IDrive account.
#
# Created By: Senthil Pandian @ IDrive Inc
#****************************************************************************************************************

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;

my ($logOutputFile, $errMsg) = ('') x 2;
my $jobType = 'manual';
my ($totalFileCount,$notExistCount,$deletedFilesCount) = (0) x 3;
my (%archivedDirAndFile,@dirListForAuth,@startTime);

$SIG{INT}  = \&cancelProcess;
$SIG{TERM} = \&cancelProcess;
$SIG{TSTP} = \&cancelProcess;
$SIG{QUIT} = \&cancelProcess;

Common::waitForUpdate();
Common::initiateMigrate();
init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub init {
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
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

	my $backupType  = Common::getUserConfiguration('BACKUPTYPE');
	unless($backupType =~ /mirror/){
		Common::retreat('backup_type_must_be_mirror');
	}

	my ($status, $errStr) = Common::validateBackupRestoreSetFile('backup');
	if($status eq 'FAILURE' && $errStr ne ''){
		Common::retreat($errStr);
	}

	my $archivePercentage = getPercentageForCleanup();
	# check if any backup job in progress and if so exit
	getRunningBackupJobs();

	my $jobRunningDir = Common::getJobsPath('archive');
	Common::createDir($jobRunningDir, 1) unless(-e $jobRunningDir);

	#Checking if archive job is already in progress
	my $pidPath = "$jobRunningDir/pid.txt";
	if (Common::isFileLocked($pidPath)) {
		Common::retreat('archive_running', $jobType eq 'manual' ? 0 : 1);
	}
	if(!Common::fileLock($pidPath)) {
		Common::retreat(['failed_to_open_file', ": ", $pidPath]);
	}

#	my $archivePercentage = getPercentageForCleanup();
	my $searchDir = $jobRunningDir.'/'.$AppConfig::searchDir;
	Common::createDir($searchDir, 1);

	getArchiveFileList();
	checkAndDeleteItems($archivePercentage);
	renameLogFile();
	removeIntermediateFiles();
	exit 0;
}

#*****************************************************************************************************
# Subroutine			: getRunningBackupJobs
# Objective				: Check if pid file exists & file is locked, then return it all
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getRunningBackupJobs {
	my @availableBackupJobs = ('backup');
	my %runningJobs;
	my ($isJobRunning, $runningJobName) = (0,'');
	#my $archiveJobToCheck = ($jobType eq 'manual')?"periodic_archive":"manual_archive";
	%runningJobs = Common::getRunningJobs('archive');
	my @runningJobs = keys %runningJobs;

	if(scalar(@runningJobs)){
		Common::retreat(["\n",'unable_to_start_cleanup_operation',lc($runningJobs[0]).'_running',"\n"], $jobType eq 'manual' ? 0 : 1);
	} else {
		while(1){
			%runningJobs = Common::getRunningJobs(@availableBackupJobs);
			@runningJobs = keys %runningJobs;
			if($jobType eq 'periodic' and scalar(@runningJobs)){
				$runningJobName = lc($runningJobs[0]);
				Common::traceLog('delaying_cleanup_operation_reason',$runningJobName.'_running');
				sleep(60);
				next;
			}
			last;
		}

		if ($jobType eq 'manual' and scalar(keys %runningJobs)>0) {
			if(scalar(keys %runningJobs) > 1){
				Common::retreat(["\n",'unable_to_start_cleanup_operation','manual_scheduled_backup_jobs_running',"\n"], $jobType eq 'manual' ? 0 : 1);
			} else {
				Common::retreat(["\n",'unable_to_start_cleanup_operation',lc($runningJobs[0]).'_running',"\n"], $jobType eq 'manual' ? 0 : 1);
			}
		}
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getArchiveFileList
# Objective				: Get archive file list to be deleted
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getArchiveFileList {
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $isDedup  	   = Common::getUserConfiguration('DEDUP');
	my $backupLocation = Common::getUserConfiguration('BACKUPLOCATION');
	$backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);

	#Displaying progress of file scanning with count
	if($jobType eq 'manual'){
		Common::display("\n");
		Common::getCursorPos(3,Common::getStringConstant('scanning_files')."\n");
	}

	my @itemsStat = checkBackupsetItemStatus();
	exitCleanup()	if(scalar(@itemsStat)<1);

	my $archiveFileList = $jobRunningDir.'/'.$AppConfig::archiveFileResultFile;
	if(!open(ARCHIVE_FILE_HANDLE, ">", $archiveFileList)) {
		Common::traceLog('failed_to_open_file',":$archiveFileList. Reason:$!");
		exitCleanup();
	}

	my $archiveFolderList = $jobRunningDir.'/'.$AppConfig::archiveFolderResultFile;
	if(!open(ARCHIVE_FOLDER_HANDLE, ">", $archiveFolderList)) {
		Common::traceLog('failed_to_open_file',":$archiveFolderList. Reason:$!");
		exitCleanup();
	}

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);

	if($isDedup eq 'on'){
		foreach my $tmpLine (@itemsStat) {
			my @fields = $tmpLine;
			if (ref($fields[0]) ne "HASH") {
				next;
			}
			my $itemName = $fields[0]{'fname'};
			Common::replaceXMLcharacters(\$itemName);
			$itemName =~ s/^[\/]+/\//g;
			if($fields[0]{'status'} =~ /directory exists/) {
				if(-e $itemName){
					startEnumerateOperation($itemName);
				} else {
					print ARCHIVE_FOLDER_HANDLE $itemName."\n";
					startSearchOperation($itemName);
				}
			}
			elsif($fields[0]{'status'} =~ /file exists/){
				$totalFileCount++;
				unless(-e $fields[0]{'fname'}){
					$notExistCount++;
					print ARCHIVE_FILE_HANDLE $fields[0]{'fname'}."\n";
				}
				my $progressMsg = Common::getStringConstant('files_scanned')." $totalFileCount\nScanning... $fields[0]{'fname'}";
				Common::displayProgress($progressMsg,2) if($jobType eq 'manual');
			}
		}
	} else {
		foreach my $tmpLine (@itemsStat) {
			my @fields   = $tmpLine;
			if (ref($fields[0]) ne "HASH") {
				next;
			}
			my $itemName = $fields[0]{'fname'};
			Common::replaceXMLcharacters(\$itemName);
			my $tempItemName = $itemName;
			if($backupLocation ne '/'){
				$tempItemName =~ s/$backupLocation//;
			}
			if($fields[0]{'status'} =~ /directory exists/) {
				#print "\n[D] [$itemName] \n";
				if(-e $tempItemName){
					startEnumerateOperation($itemName);
				} else {
					print ARCHIVE_FOLDER_HANDLE $itemName."\n";
					startSearchOperation($itemName);
				}
			}
			elsif($fields[0]{'status'} =~ /file exists/){
				#print "\n[F] [$itemName] \n";
				$totalFileCount++;
				unless(-e $tempItemName){
					$notExistCount++;
					print ARCHIVE_FILE_HANDLE $itemName."\n";
				}
				my $progressMsg = Common::getStringConstant('files_scanned')." $totalFileCount\nScanning... $tempItemName";
				Common::displayProgress($progressMsg,2) if($jobType eq 'manual');
			}
		}
	}

	foreach my $itemName (@dirListForAuth){
		startEnumerateOperation($itemName);
	}
	close(ARCHIVE_FILE_HANDLE);
	close(ARCHIVE_FOLDER_HANDLE);
	Common::displayProgress(Common::getStringConstant('scan_completed'),2) if($jobType eq 'manual');
	return 0;
}

#*****************************************************************************************************
# Subroutine			: checkBackupsetItemStatus
# Objective				: This function will get status of backup set items
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkBackupsetItemStatus
{
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $isDedup  	   = Common::getUserConfiguration('DEDUP');
	my $backupLocation = Common::getUserConfiguration('BACKUPLOCATION');
	$backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);

	my $backupsetFilePath = Common::getJobsPath('backup')."/".$AppConfig::backupsetFile;
	if(!open(BACKUPLIST, $backupsetFilePath)){
		$errMsg = Common::getStringConstant('failed_to_open_file').": $backupsetFilePath, Reason: $!";
		return 0;
	}
	my $tempBackupsetFilePath = $jobRunningDir."/".$AppConfig::tempBackupsetFile;
	if(!open(BACKUPLISTNEW, ">", $tempBackupsetFilePath)){
		$errMsg = Common::getStringConstant('failed_to_open_file').": $tempBackupsetFilePath, Reason: $!";
		return 0;
	}

	my $finalBackupLocation= '';
	$finalBackupLocation = $backupLocation if($isDedup eq 'off' and $backupLocation ne '/');

	my @arryToCheck = ();
	while(<BACKUPLIST>) {
		Common::Chomp(\$_);
		next	if($_ eq "");

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
	close(BACKUPLIST);
	close(BACKUPLISTNEW);

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);

	my $itemStatusUTFpath = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
	Common::createUTF8File(['ITEMSTATUS',$itemStatusUTFpath],
		$tempBackupsetFilePath,
		$evsErrorFile
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
#********************************************************************************
sub startSearchOperation{
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $isDedup  	   = Common::getUserConfiguration('DEDUP');
	my $backupLocation = Common::getUserConfiguration('BACKUPLOCATION');
	   $backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
	my $searchDir 	   = $jobRunningDir.'/'.$AppConfig::searchDir;

	my $remoteFolder = $_[0];
	if (substr($remoteFolder, -1, 1) ne "/") {
	   $remoteFolder .= "/";
	}

	my $searchItem = "*";
	my $errStr = "";
	my $tempSearchUTFpath = $searchDir.'/'.$AppConfig::utf8File;
	my $tempEvsOutputFile = $searchDir.'/'.$AppConfig::evsOutputFile;
	my $tempEvsErrorFile  = $searchDir.'/'.$AppConfig::evsErrorFile;

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);
	my $searchRetryCount = 5;
RETRY:
	Common::createUTF8File(['SEARCH',$tempSearchUTFpath],
				$tempEvsOutputFile,
				$tempEvsErrorFile,
				$remoteFolder
				) or Common::retreat('failed_to_create_utf8_file');
	my @responseData = Common::runEVS('item',1,1,$tempSearchUTFpath);
	while(1){
		if(!-e $pidPath or (-e $tempEvsOutputFile and -s $tempEvsOutputFile) or  (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
			last;
		}
		sleep(2);
		next;
	}
	if(-s $tempEvsOutputFile == 0 and -s $tempEvsErrorFile > 0) {
		unless(Common::checkAndUpdateServerAddr($tempEvsErrorFile)) {
			#exitCleanup(Common::getStringConstant('operation_could_not_be_completed_please_try_again'));
			Common::traceLog("startSearchOperation : RETRY");
			$searchRetryCount--;
			goto RETRY if($searchRetryCount);
		} else {
			my $errStr = Common::checkExitError($tempEvsErrorFile,'archive');
			if($errStr and $errStr =~ /1-/){
				$errStr =~ s/1-//;
				exitCleanup($errStr);
			}
		}
		return 0;
	}

	my $tempRemoteFolder = $remoteFolder;
	   $tempRemoteFolder = substr($tempRemoteFolder,1) if(substr($tempRemoteFolder,0,1) eq '/');
	   chop($tempRemoteFolder) if(substr($tempRemoteFolder,-1,1) eq '/');
	   $tempRemoteFolder =~ s/[\s]+|[\/]+|[\']+/_/g; #Replacing space, single quote & slash(/) with underscore(_)
	my $tempArchiveListFile  = $searchDir.'/'."$tempRemoteFolder.txt";

	open my $TEMPARCHIVELIST, ">>", $tempArchiveListFile or ($errStr = Common::getStringConstant('failed_to_open_file').":$tempArchiveListFile. Reason:$!");
	if($errStr ne ""){
		Common::traceLog($errStr);
		return 0;
	}

	# parse search output.
	open my $SEARCHOUTFH, "<", $tempEvsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').":$tempEvsOutputFile. Reason:$!");
	if($errStr ne ""){
		Common::traceLog($errStr);
		return 0;
	}

	my @fileList =();
	my ($buffer,$lastLine) = ("") x 2;
	my $skipFlag = 0;
	while(1){
		my $byteRead = read($SEARCHOUTFH, $buffer, $AppConfig::bufferLimit);
		if($byteRead == 0) {
			if(!-e $pidPath or (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
				last;
			}
			sleep(2);
			seek($SEARCHOUTFH, 0, 1);		#to clear eof flag
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
			#print "\ntemp tmpLine::$tmpLine\n";
			if($tmpLine =~ /fname/) {
				my %fileName = Common::parseXMLOutput(\$tmpLine);
				next if (scalar(keys %fileName) < 5 or !defined($fileName{'fname'}));

				my $temp = $fileName{'fname'};
				#print "temp fileName::$temp\n";
				Common::replaceXMLcharacters(\$temp);
				my $tempItemName = $temp;
				if($isDedup eq 'off' and $backupLocation ne '/'){
					$tempItemName =~ s/$backupLocation//;
				}
				$totalFileCount++;
				print $TEMPARCHIVELIST $temp."\n";
				push(@fileList, $temp);
				$notExistCount++;
				my $progressMsg = Common::getStringConstant('files_scanned')." $totalFileCount\nScanning... $tempItemName";
				Common::displayProgress($progressMsg,2) if($jobType eq 'manual');
			}
			elsif($tmpLine ne ''){
				if($tmpLine =~ m/(files_found|items_found)/){
					$skipFlag = 1;
				}  elsif($tmpLine !~ m/(connection established|receiving file list)/) {
					Common::traceLog("Archive search:".$tmpLine);
				}
			}
		}
		if($skipFlag) {
			last;
		}
	}

	push @{$archivedDirAndFile{$remoteFolder}}, \@fileList;
	close($TEMPARCHIVELIST);
	close($SEARCHOUTFH);

	if(-s $tempEvsErrorFile > 0) {
		my $errStr = Common::checkExitError($tempEvsErrorFile,'archive');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			exitCleanup($errStr);
		}
	}
	unlink($tempEvsOutputFile);
	unlink($tempEvsErrorFile);
	unlink($tempSearchUTFpath);
	return 0;
}

#********************************************************************************
# Subroutine			: startEnumerateOperation
# Objective				: Start remote enumerate operation
# Added By				: Senthil Pandian
#********************************************************************************
sub startEnumerateOperation{
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $isDedup  	   = Common::getUserConfiguration('DEDUP');
	my $backupLocation = Common::getUserConfiguration('BACKUPLOCATION');
	   $backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
	my $searchDir 	   = $jobRunningDir.'/'.$AppConfig::searchDir;

	my $remoteFolder = $_[0];
	my $searchItem = "*";
	my $errStr = "";
	my $tempPath = $remoteFolder;
	   $tempPath =~ s/[\/]$//g; #Removing last "/"
	   $tempPath =~ s/[\s]+|[\/]+|[\']+/_/g; #Replacing space, single quote & slash(/) with underscore(_)

	my $tempAuthListUTFpath = $searchDir.'/'.$AppConfig::utf8File."_AuthList";
	my $tempEvsOutputFile   = $searchDir.'/'.$AppConfig::evsOutputFile."_AuthList";
	my $tempEvsErrorFile    = $searchDir.'/'.$AppConfig::evsErrorFile."_AuthList";

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);

	Common::createUTF8File(['AUTHLIST',$tempAuthListUTFpath],
				$tempEvsOutputFile,
				$tempEvsErrorFile,
				$remoteFolder
				) or Common::retreat('failed_to_create_utf8_file');
	my @responseData = Common::runEVS('item',1,1,$tempAuthListUTFpath);
	while(1){
		if(!-e $pidPath or (-e $tempEvsOutputFile and -s $tempEvsOutputFile) or  (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
			last;
		}
		sleep(2);
		next;
	}
	if(-s $tempEvsOutputFile == 0 and -s $tempEvsErrorFile > 0) {
		if(Common::checkAndUpdateServerAddr($tempEvsErrorFile)) {
			my $errStr = Common::checkExitError($tempEvsErrorFile,'archive');
			if($errStr and $errStr =~ /1-/){
				$errStr =~ s/1-//;
				exitCleanup($errStr);
			}
		}
		Common::traceLog("startEnumerateOperation : RETRY : $remoteFolder");
		push(@dirListForAuth,$remoteFolder);
		return 0;
	}
	# parse search output.
	open my $OUTFH, "<", $tempEvsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').": $tempEvsOutputFile, Reason: $!");
	if($errStr ne ""){
		Common::traceLog($errStr);
		return 0;
	}
	#seek($OUTFH, 0, 0);		#to clear eof flag

	#Adding '/' at end of folder path
	if (substr($remoteFolder, -1, 1) ne "/") {
		$remoteFolder .= "/";
	}

	my $splitLimit = 25;
	if($isDedup eq 'off'){
		$splitLimit = 13;
	}

	my ($buffer,$lastLine) = ("") x 2;
	my $skipFlag = 0;
	while(1){
		my $byteRead = read($OUTFH, $buffer, $AppConfig::bufferLimit);
		if($byteRead == 0) {
			if(!-e $pidPath or (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
				last;
			}
			sleep(2);
			seek($OUTFH, 0, 1);		#to clear eof flag
			next;
		}

		if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
			$buffer = $lastLine . $buffer;
		}
		my @resultList = split(/\n/, $buffer);

		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}

		foreach my $tmpLine (@resultList){
			if($tmpLine =~ /<item/) {
				my %fileName = Common::parseXMLOutput(\$tmpLine);
				next if (scalar(keys %fileName) < 5 or !defined($fileName{'fname'}));

				my $itemName = $fileName{'fname'};
				$itemName = $remoteFolder.$itemName unless($itemName =~/\//);
				Common::replaceXMLcharacters(\$itemName);
				my $tempItemName = $itemName;
				if($isDedup eq 'off' and $backupLocation ne '/'){
					$tempItemName =~ s/$backupLocation//;
				}

				my $itemType = $fileName{'restype'};
				if($itemType eq "D") {
					if(-e $tempItemName){
						push(@dirListForAuth,$itemName);
					} else {
						print ARCHIVE_FOLDER_HANDLE $itemName."\n";
						startSearchOperation($itemName);
					}
				}
				elsif($itemType eq "F" or $fileName{'file_ver'}>=1){
					$totalFileCount++;
					unless(-e $tempItemName){
						$notExistCount++;
						print ARCHIVE_FILE_HANDLE $itemName."\n";
					}
					my $progressMsg = Common::getStringConstant('files_scanned')." $totalFileCount\nScanning... $itemName";
					Common::displayProgress($progressMsg,2) if($jobType eq 'manual');
				}
			}
			elsif($tmpLine ne ''){
				if($tmpLine =~ m/(bytes  received)/){
					$skipFlag = 1;
				} elsif($tmpLine !~ m/(connection established|receiving file list)/) {
					Common::traceLog("Archive auth-list:".$tmpLine);
				}
			}
		}
		if($skipFlag) {
			last;
		}
	}
	close($OUTFH);

	if(-s $tempEvsErrorFile > 0) {
		my $errStr = Common::checkExitError($tempEvsErrorFile,'archive',1);
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			exitCleanup($errStr);
		}
		push(@dirListForAuth,$remoteFolder);
	}
	unlink($tempEvsOutputFile);
	unlink($tempEvsErrorFile);
	unlink($tempAuthListUTFpath);
	return 0;
}

#********************************************************************************
# Subroutine			: deleteArchiveFiles
# Objective				: This function will cleanup the files
# Added By				: Senthil Pandian
#********************************************************************************
sub deleteArchiveFiles
{
	my $isDedup  	      = Common::getUserConfiguration('DEDUP');
	my $jobRunningDir     = Common::getJobsPath('archive');
	my $itemStatusUTFpath = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $evsOutputFile     = $jobRunningDir.'/'.$AppConfig::evsOutputFile;
	my $evsErrorFile      = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
	my $archiveFileList   = $jobRunningDir.'/'.$AppConfig::archiveFileResultFile;
	my $archiveFolderList = $jobRunningDir.'/'.$AppConfig::archiveFolderResultFile;
	my $errorContent	  = '';
	my $filesToDelete	  = 0;
	my $logTime = time;
	@startTime  = localtime();
	Common::Chomp(\$logTime); #Removing white-space and '\n'
	my $archiveLogDirpath = $jobRunningDir.'/'.$AppConfig::logDir;
	Common::createDir($archiveLogDirpath, 1);
	$AppConfig::jobRunningDir = $jobRunningDir; #Added by Senthil
	Common::createLogFiles("ARCHIVE",ucfirst($jobType));
	$logOutputFile = $AppConfig::outputFilePath;
	#$logOutputFile = $archiveLogDirpath.'/'.$logTime;
	my $logStartTime = `date +"%a %b %d %T %Y"`;
	Common::Chomp(\$logStartTime); #Removing white-space and '\n'

	#Opening to log file handle
	if(!open(ARCHIVELOG, ">", $logOutputFile)){
		Common::traceLog('failed_to_open_file',": $logOutputFile, Reason: $!");
		return 0;
	}

	print ARCHIVELOG Common::getStringConstant('start_time').$logStartTime."\n";
	print ARCHIVELOG ucfirst(Common::getStringConstant('username')).": ".Common::getUsername()."\n";

	my $host = Common::updateLocaleCmd('hostname');
	$host = `$host`;
	chomp($host);
	print ARCHIVELOG "Machine Name: ".$host."\n";

	if($jobType eq 'periodic'){
		print ARCHIVELOG Common::getStringConstant('periodic_cleanup_operation')."\n\n";
	} else {
		print ARCHIVELOG Common::getStringConstant('archive_cleanup_operation')."\n\n";
	}

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);

	unless(defined($_[0]) and $_[0] ne ''){
		#Displaying progress of file deletion
		if($jobType eq 'manual'){
			Common::display("\n");
			Common::getCursorPos(2,Common::getStringConstant('preparing_to_delete'));
		}
		my $deleteRetryCount = 5;
FILERETRY:
		#Deleting files
		if(-e $archiveFileList and !-z $archiveFileList){
			Common::createUTF8File(['DELETE',$itemStatusUTFpath],
						$archiveFileList,
						$evsOutputFile,
						$evsErrorFile
						) or Common::retreat('failed_to_create_utf8_file');
			my @responseData = Common::runEVS('item',1,1);
			my $errStr = "";

			while(1){
				if(!-e $pidPath or (-e $evsOutputFile and -s $evsOutputFile) or  (-e $evsErrorFile and -s $evsErrorFile)){
					last;
				}
				sleep(2);
				next;
			}

			if(-s $evsOutputFile < 5 and !-z $evsErrorFile) {
				unless(Common::checkAndUpdateServerAddr($evsErrorFile)) {
					#exitCleanup(Common::getStringConstant('operation_could_not_be_completed_please_try_again'));
					Common::traceLog("Deleting files : RETRY");
					$deleteRetryCount--;
					goto FILERETRY if($deleteRetryCount);
				} else {
					my $errStr = Common::checkExitError($evsErrorFile,'archive');
					if($errStr and $errStr =~ /1-/){
						$errStr =~ s/1-//;
						exitCleanup($errStr);
					}
				}
				return 0;
			}

			# parse delete output.
			open OUTFH, "<", $evsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').": $evsOutputFile, Reason: $!");
			if($errStr ne ""){
				Common::traceLog($errStr);
				return 0;
			}

			# Appending deleted files/folders details to log
			print ARCHIVELOG Common::getStringConstant('deleted_content')."\n";
			$filesToDelete	  = 1;
			my ($buffer,$lastLine) = ("") x 2;
			my $skipFlag = 0;
			while(1){
				my $byteRead = read(OUTFH, $buffer, $AppConfig::bufferLimit);
				if($byteRead == 0) {
					if(!-e $pidPath or (-e $evsErrorFile and -s $evsErrorFile)){
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
					if($tmpLine =~ /<item/){
						my %fileName = Common::parseXMLOutput(\$tmpLine);
						next if (scalar(keys %fileName) < 2 or !defined($fileName{'fname'})) ;

						my $op		 = $fileName{'op'};
						my $fileName = $fileName{'fname'};
						Common::replaceXMLcharacters(\$fileName);
						print ARCHIVELOG "[$op] [$fileName]\n"; #Appending deleted file detail to log file
						my $progressMsg = "[$op] [$fileName]";
						Common::displayProgress($progressMsg,1) if($jobType eq 'manual');
						$deletedFilesCount++;
					} elsif($tmpLine ne '' and $tmpLine !~ m/(connection established|receiving file list)/){
						$errorContent .= $tmpLine."\n";
						Common::traceLog("Delete operation error content:$tmpLine");
					}
				}
				if($buffer ne '' and ($buffer =~ m/End of operation/)){
					last;
				}
			}
			close(OUTFH);
			if(-e $evsErrorFile and !-z $evsErrorFile) {
				#Reading error file and appending to log file
				if(!open(TEMPERRORFILE, "< $evsErrorFile")) {
					Common::traceLog('failed_to_open_file',":$evsErrorFile, Reason:$!");
				}
				$errorContent .= <TEMPERRORFILE>;
				close TEMPERRORFILE;
			}
			unlink($evsOutputFile);
			unlink($evsErrorFile);
		}

		$deleteRetryCount = 5;
EMPTYDIRRETRY:
		#Deleting folders
		if(-e $archiveFolderList and !-z $archiveFolderList){
			Common::createUTF8File(['DELETE',$itemStatusUTFpath],
						$archiveFolderList,
						$evsOutputFile,
						$evsErrorFile
						) or Common::retreat('failed_to_create_utf8_file');
			my @responseData = Common::runEVS('item',1,1);
			my $errStr = "";
			while(1){
				if(!-e $pidPath or (-e $evsOutputFile and -s $evsOutputFile) or  (-e $evsErrorFile and -s $evsErrorFile)){
					last;
				}
				sleep(2);
				next;
			}

			if((-f $evsOutputFile && (-s $evsOutputFile < 5)) && (-f $evsErrorFile && !-z $evsErrorFile)) {
				unless(Common::checkAndUpdateServerAddr($evsErrorFile)) {
					#exitCleanup(Common::getStringConstant('operation_could_not_be_completed_please_try_again'));
					Common::traceLog("Deleting folders : RETRY");
					$deleteRetryCount--;
					goto EMPTYDIRRETRY if($deleteRetryCount);
				} else {
					my $errStr = Common::checkExitError($evsErrorFile,'archive');
					if($errStr and $errStr =~ /1-/){
						$errStr =~ s/1-//;
						exitCleanup($errStr);
					}
				}
				return 0;
			}

			# parse delete output.
			open OUTFH, "<", $evsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').": $evsOutputFile, Reason: $!");
			if($errStr ne ""){
				Common::traceLog($errStr);
				return 0;
			}

			unless($filesToDelete){
				# Appending deleted files/folders details to log
				print ARCHIVELOG Common::getStringConstant('deleted_content')."\n";
			}

			my $serverRoot = Common::getUserConfiguration('SERVERROOT');
			# Appending deleted files/folders details to log
			my ($buffer,$lastLine) = ("") x 2;
			my $skipFlag = 0;
			while(1){
				my $byteRead = read(OUTFH, $buffer, $AppConfig::bufferLimit);
				if($byteRead == 0) {
					if(!-e $pidPath or (-e $evsErrorFile and -s $evsErrorFile)){
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
					if($tmpLine =~ /<item/){
						my %fileName = Common::parseXMLOutput(\$tmpLine);
						next if (scalar(keys %fileName) < 2 or !defined($fileName{'fname'}));

						my $op		 = $fileName{'op'};
						my $fileName = $fileName{'fname'};
						Common::replaceXMLcharacters(\$fileName);

						if ($isDedup eq 'off' and substr($fileName, -1, 1) ne "/") {
							$fileName .= '/';
						} elsif ($isDedup eq 'on'){
							$fileName =~ s/^\/$serverRoot//;
							if(substr($fileName, -1, 1) ne "/") {
								$fileName .= '/';
							}
						}
						if($archivedDirAndFile{$fileName}){
							my $progressMsg = "[$op] [$fileName]";
							Common::displayProgress($progressMsg,1) if($jobType eq 'manual');
							foreach my $fileName1 (@{$archivedDirAndFile{$fileName}[0]}){
								print ARCHIVELOG "[$op] [$fileName1]\n"; #Appending deleted file detail to log file
								$deletedFilesCount++;
							}
						}
					}
					elsif($tmpLine ne '' and $tmpLine !~ m/(connection established|receiving file list)/)
					{
						$errorContent .= $tmpLine;
					}
				}
				if($buffer ne '' and $buffer =~ m/End of operation/i){
					last;
				}
			}
			if(-e $evsErrorFile and !-z $evsErrorFile) {
				#Reading error file and appending to log file
				if(!open(TEMPERRORFILE, "< $evsErrorFile")) {
					Common::traceLog('failed_to_open_file',":$evsErrorFile, Reason:$!");
				}
				my @errorArray = <TEMPERRORFILE>;
				foreach my $errorLine (@errorArray){
					if($errorLine =~ /[IOERROR]/i){
						if($errorLine =~ /\[(.*?)\]/g){
							my $folderName = $1;
							Common::replaceXMLcharacters(\$folderName);
							if($archivedDirAndFile{$folderName}){
								foreach my $fileName (@{$archivedDirAndFile{$folderName}[0]}){
									my $tempLine = $errorLine;
									$tempLine =~ s/$folderName/$fileName/;
									$errorContent .= $tempLine;
								}
							}
						}
					} else{
						$errorContent .= $errorLine;
					}
				}
				close TEMPERRORFILE;
			}
			close OUTFH;
			unlink($evsOutputFile);
			unlink($evsErrorFile);
		}
		my $progressMsg = Common::getStringConstant('delete_operation_has_been_completed');
		if($deletedFilesCount == 0 and $errorContent ne ''){
			$errMsg = Common::checkErrorAndLogout($errorContent,1);
			if($errMsg ne $errorContent){
				$errorContent = $errMsg;
				$progressMsg  = $errMsg;
			}
		}
		Common::displayProgress($progressMsg,1) if($jobType eq 'manual');
		writeSummary();

		my $logEndTime = `date +"%a %b %d %T %Y"`;
		Common::Chomp(\$logEndTime); #Removing white-space and '\n'
		print ARCHIVELOG Common::getStringConstant('end_time').$logEndTime."\n";		
	} else {
		my $logEndTime = `date +"%a %b %d %T %Y"`;
		Common::Chomp(\$logEndTime); #Removing white-space and '\n'
		my $endTime = Common::getStringConstant('end_time').$logEndTime."\n";			
		$_[0] =~ s/<ENDTIME>/$endTime/;
		print ARCHIVELOG "\n".Common::getStringConstant('summary')."\n";
		print ARCHIVELOG $_[0]."\n";
	}


	#Appending error content to log file
	if($errorContent ne '') {
		print ARCHIVELOG "\n".Common::getStringConstant('additional_information') if($errMsg ne $errorContent);
		print ARCHIVELOG "\n$errorContent\n"
	}
	close ARCHIVELOG; #Closing to log file handle
	return 0;
}

#********************************************************************************
# Subroutine			: cancelProcess
# Objective				: Cancelling the process and removing the intermediate files/folders
# Added By				: Senthil Pandian
#********************************************************************************
sub cancelProcess {
	my $jobRunningDir = Common::getJobsPath('archive');
	my $pidPath = $jobRunningDir.'/pid.txt';

	if(!-e $pidPath){
		$errMsg = 'operation_cancelled_by_user';
	}
	else {
		# Killing EVS operations
		my $username = Common::getUsername();
		my $jobTerminationPath = Common::getScript('job_termination', 1);
		my $cmd = sprintf("%s %s 'archive' - 0 allType", $AppConfig::perlBin, Common::getScript('job_termination', 1));
		$cmd = Common::updateLocaleCmd($cmd);
		`$cmd 1>/dev/null 2>/dev/null`;	
	}

	exitCleanup($errMsg);
}

#********************************************************************************
# Subroutine			: exitCleanup
# Objective				: Cancelling the process and removing the intermediate files/folders
# Added By				: Senthil Pandian
#********************************************************************************
sub exitCleanup {
	my $errStr = $_[0];
	if($jobType eq 'manual'){
		system('stty', 'echo');
		system("tput sgr0");
	}
	$errStr = Common::checkErrorAndLogout($errStr);
	my $retVal = renameLogFile($errStr);				#Renaming the log output file name with status
	if(defined($errStr) and $errStr ne ''){
		Common::display(["\n",$errStr,"\n"]) if($jobType eq 'manual');
	} elsif($retVal and $errMsg ne ''){
		Common::display([$errMsg,"\n"]) if($jobType eq 'manual'); #Added to print the error message if there is no summary to display
	}
	removeIntermediateFiles();		#Removing all the intermediate files/folders
	exit 0;
}

#********************************************************************************
# Subroutine			: removeIntermediateFiles
# Objective				: Removing all the intermediate files/folders
# Added By				: Senthil Pandian
#********************************************************************************
sub removeIntermediateFiles {
	my $jobRunningDir = Common::getJobsPath('archive');
	my $searchDir     = $jobRunningDir.'/'.$AppConfig::searchDir;
	my $pidPath   	  = $jobRunningDir.'/pid.txt';
	my $cancelFile 	  = $jobRunningDir.'/cancel.txt';
	my $evsOutputFile = $jobRunningDir.'/'.$AppConfig::evsOutputFile;
	my $evsErrorFile  = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
	my $itemStatusUTFpath       = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $archiveFileResultFile   = $jobRunningDir.'/'.$AppConfig::archiveFileResultFile;
	my $archiveFolderResultFile = $jobRunningDir.'/'.$AppConfig::archiveFolderResultFile;
	my $tempBackupsetFilePath   = $jobRunningDir."/".$AppConfig::tempBackupsetFile;
	my $userProfileDir  = Common::getUserProfilePath();

	Common::removeItems($searchDir) if($searchDir =~ /$userProfileDir/);
	unlink($pidPath);
	unlink($cancelFile);
	unlink($evsOutputFile);
	unlink($evsErrorFile);
	unlink($itemStatusUTFpath);
	unlink($archiveFileResultFile);
	unlink($archiveFolderResultFile);
	unlink($tempBackupsetFilePath);

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
		sleep(2);
	} else {
		$archivePercentage = int($ARGV[2]);
	}
	return $archivePercentage;
}

#********************************************************************************
# Subroutine			: checkAndDeleteItems
# Objective				: Check the percentage of files & delete
# Added By				: Senthil Pandian
#********************************************************************************
sub checkAndDeleteItems {
	my $archivePercentage = $_[0];
	my $jobRunningDir     = Common::getJobsPath('archive');
	my $archiveFileList   = $jobRunningDir.'/'.$AppConfig::archiveFileResultFile;

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);

	#if(-e $archiveList and -s $archiveList>0 and $notExistCount>0 and $totalFileCount>0){
	if($notExistCount>0 and $totalFileCount>0){
		#Calculating the % of files for cleanup
		my $perCount = ($notExistCount/$totalFileCount)*100;
		$perCount = ((($perCount-int($perCount))<0.5) ? int($perCount) : int($perCount)+1);
		#print "\nperCount:'$perCount'\n";
		#print "archivePercentage:'$archivePercentage'\n";
		if($archivePercentage < $perCount){
			my $reason = Common::getStringConstant('operation_aborted_due_to_percentage');
			$reason =~ s/<PER1>/$perCount/;
			$reason =~ s/<PER2>/$archivePercentage/;
			$errMsg  = "\n".Common::getStringConstant('total_files_in_your_backupset').$totalFileCount."\n";
			$errMsg .= Common::getStringConstant('total_files_listed_for_deletion').$notExistCount."\n";

			if($jobType eq 'manual'){				
				$errMsg .= "\n".Common::getStringConstant('archive_cleanup')." ".$reason."\n";
				$errMsg  = "\n".Common::getStringConstant('summary').$errMsg;
				Common::display(["\n",$errMsg]);
				removeIntermediateFiles();
				exit 0;
			} else {
				$errMsg .= "<ENDTIME>\n\n";			
				$errMsg .= Common::getStringConstant('periodic_cleanup')." ".$reason."\n";
			}
		}
		elsif($jobType eq 'manual'){
			my $files;
			if($notExistCount>1){
				Common::display(["\n\n","$notExistCount ",'files_are_present_in_your_account','do_you_want_view_y_or_n'], 1);
				$files = "$notExistCount files are ";
			} else {
				Common::display(["\n\n","$notExistCount ",'file_is_present_in_your_account','do_you_want_view_y_or_n'], 1);
				$files = "$notExistCount file is ";
			}
			#my $toViewConfirmation = Common::getConfirmationChoice('enter_your_choice');
			my $toViewConfirmation = Common::getAndValidate('enter_your_choice','YN_choice', 1);

			#Checking pid & cancelling process if job terminated by user
			cancelProcess()		unless(-e $pidPath);

			if(lc($toViewConfirmation) eq 'y') {
				my $mergedArchiveList = mergeAllArchivedFiles();
				Common::openEditor('view',$mergedArchiveList);
				unlink($mergedArchiveList);
			}

			#Checking pid & cancelling process if job terminated by user
			cancelProcess()		unless(-e $pidPath);

			Common::display(["\n",'do_u_want_to_delete_permanently'], 1);
			$toViewConfirmation = Common::getAndValidate('enter_your_choice','YN_choice', 1);
			if(lc($toViewConfirmation) eq 'n') {
				removeIntermediateFiles();
				exit 0;
			}
		}
		if($jobType eq 'manual' or ($jobType eq 'periodic' and defined($_[0]))){
			deleteArchiveFiles($errMsg);
		}
	} elsif($jobType eq 'manual'){
		Common::display(["\n\n",'there_are_no_items_to_delete',"\n"], 1);
	} else {
		$errMsg = Common::getStringConstant('there_are_no_items_to_delete')."\n";
		deleteArchiveFiles($errMsg);
	}
	return 0;
}

#********************************************************************************
# Subroutine			: getDaysBetweenTwoDates
# Objective				: Get days between two dates
# Added By				: Senthil Pandian
#********************************************************************************
sub getDaysBetweenTwoDates{
	my $s1 = $ARGV[3]; #Scheduled Time
	my $s2 = time;
	my $days = int(($s2 - $s1)/(24*60*60));
	return $days;
}

#********************************************************************************
# Subroutine			: renameLogFile
# Objective				: Rename the log file name with status
# Added By				: Senthil Pandian
# Modified By			: Yogesh Kumar
#********************************************************************************
sub renameLogFile{
	return 0	if(!defined($logOutputFile) or !-e $logOutputFile);

	my ($logOutputFileStatusFile, $status);
	my $jobRunningDir  = Common::getJobsPath('archive');
	my $userCancelFile = $jobRunningDir.'/cancel.txt';
	if(-e $userCancelFile){
		unlink($userCancelFile);
		writeSummary(1);
		$status = Common::getStringConstant('aborted');
	}
	elsif(defined($_[0])){
		writeSummary(1, $_[0]);
		$status = Common::getStringConstant('aborted');
	}
	elsif(defined($errMsg) and $errMsg =~ /operation aborted/i){
		$status = Common::getStringConstant('aborted');
	}
	elsif($notExistCount>0 and $notExistCount == $deletedFilesCount){
		$status = Common::getStringConstant('success');
	}
	else {
		$status = Common::getStringConstant('failure');
	}
	$logOutputFileStatusFile = $logOutputFile;
	$logOutputFileStatusFile =~ s/_Running_/_$status\_/;
	system(Common::updateLocaleCmd("mv '$logOutputFile' '$logOutputFileStatusFile'"));
	Common::display(['for_more_details_refer_the_log',"\n"], 1) if($jobType eq 'manual');

	Common::saveLog($logOutputFileStatusFile);

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
	Common::addLogStat($jobRunningDir, \%logStat);

	if (Common::loadNotifications()) {
		Common::setNotification('get_logs') and Common::saveNotifications();
	}
}

#********************************************************************************
# Subroutine			: mergeAllArchivedFiles
# Objective				: Merge all archive list files
# Added By				: Senthil Pandian
#********************************************************************************
sub mergeAllArchivedFiles{
	my $jobRunningDir     = Common::getJobsPath('archive');
	my $searchDir     	  = $jobRunningDir.'/'.$AppConfig::searchDir;
	my $archiveFileList   = $jobRunningDir.'/'.$AppConfig::archiveFileResultFile;
	my $archiveFileView   = $jobRunningDir.'/'.$AppConfig::archiveFileListForView;
	my $pidPath 		  = $jobRunningDir."/pid.txt";

	#Appending content of a file to another file
	if(-s $archiveFileList>0){
		my $appendFiles = "cat '$archiveFileList' > '$archiveFileView'";
		$appendFiles = Common::updateLocaleCmd($appendFiles);
		system($appendFiles);
	}
	if(opendir(DIR, $searchDir)) {
		foreach my $file (readdir(DIR))  {
			if( !-e $pidPath) {
				last;
			}
			chomp($file);
			unless($file =~ m/.txt/) {
				next;
			}
			my $temp = $searchDir."/".$file;
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
	my $summary = "\n".Common::getStringConstant('summary')."\n";
	$summary   .= Common::getStringConstant('items_considered_for_delete').$notExistCount."\n";
	$summary   .= Common::getStringConstant('items_deletes_now').$deletedFilesCount."\n";
	if(defined($_[1])){
		$summary   .= Common::getStringConstant('items_failed_to_delete')."0\n\n";
		$summary   .= $_[1]."\n\n";
	}
	elsif(defined($_[0])){
		$summary   .= Common::getStringConstant('items_failed_to_delete')."0\n\n";
		$summary   .= Common::getStringConstant('operation_cancelled_by_user')."\n\n";
	}
	else {
		$summary   .= Common::getStringConstant('items_failed_to_delete').($notExistCount-$deletedFilesCount)."\n\n";
	}
	print ARCHIVELOG $summary;
	Common::display(["\n\n",$summary]) if($jobType eq 'manual');
}
