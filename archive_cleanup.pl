#!/usr/bin/perl
use strict;
use warnings;

#***************************************************************************************************************
# Find and deletes data permanently which no longer exists on local computer to free up space in IDrive account. 
# 							Created By: Senthil Pandian													
#****************************************************************************************************************

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')); } else { use lib '.'; }

use Helpers;
use Strings;
use Configuration;

my ($logOutputFile, $errMsg);
my $jobType = 'manual';
my ($totalFileCount,$notExistCount,$deletedFilesCount) = (0) x 3;
my (%archivedDirAndFile,@dirListForAuth);

$SIG{INT}  = \&cancelProcess;
$SIG{TERM} = \&cancelProcess;
$SIG{TSTP} = \&cancelProcess;
$SIG{QUIT} = \&cancelProcess;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub init {
	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	
	if ($#ARGV > 0) {			#For periodic operation
		Helpers::setUsername($ARGV[0]);
		$jobType = 'periodic';
		
		#Checking the periods between scheduled date & today
		my $periodicDays = getDaysBetweenTwoDates();
		print "periodicDays:$periodicDays\n";
		exit 0	if(($periodicDays % $ARGV[2]) != 0);
	}
	else {
		Helpers::loadUsername() or Helpers::retreat('login_&_try_again');
	}
	
	Helpers::loadUserConfiguration() or Helpers::retreat('your_account_not_configured_properly');
	if($jobType eq 'manual'){
		Helpers::isLoggedin() or Helpers::retreat('login_&_try_again');
		Helpers::displayHeader();
	}

	my $backupType  = Helpers::getUserConfiguration('BACKUPTYPE');
	unless($backupType =~ /mirror/){
		Helpers::display(['backup_type_must_be_mirror'])	if($jobType eq 'manual');
		Helpers::traceLog($Locale::strings{'backup_type_must_be_mirror'});
		exit 0;
	}

	# check if any backup job in progress and if so exit
	getRunningBackupJobs();
		
	my $jobRunningDir = Helpers::getUsersInternalDirPath($jobType.'_archive');
	Helpers::createDir($jobRunningDir, 1) unless(-e $jobRunningDir);
	
	#Checking if archive job is already in progress
	my $pidPath = "$jobRunningDir/pid.txt";	
	if (Helpers::isFileLocked($pidPath)) {
		Helpers::retreat($jobType.'_archive_running',$jobType);
	}
	if(!Helpers::fileLock($pidPath)) {
		Helpers::retreat(['failed_to_open_file', ": ", $pidPath]);
	}
	
	Helpers::display(['__note_scheduled_backupset_considered_for_archive',"\n"]) if($jobType eq 'manual');
	my ($status, $errStr) = Helpers::validateBackupRestoreSetFile('scheduled_backup');
	if($status eq 'FAILURE' && $errStr ne ''){
		unlink($pidPath);
		if($jobType eq 'manual'){
			Helpers::retreat($errStr);
		} else {
			Helpers::traceLog($errStr);
			Helpers::retreat();
		}
	}
	
	my $archivePercentage = getPercentageForCleanup();
	my $searchDir = $jobRunningDir.'/'.$Configuration::searchDir;
	Helpers::createDir($searchDir, 1);
	
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
	my @availableBackupJobs = ('manual_backup','scheduled_backup');
	my %runningJobs;
	my ($isJobRunning, $runningJobName) = (0,'');
	my $archiveJobToCheck = ($jobType eq 'manual')?"periodic_archive":"manual_archive";
	%runningJobs = Helpers::getRunningJobs($archiveJobToCheck);
	my @runningJobs = keys %runningJobs;
	
	if(scalar(@runningJobs)){
		Helpers::retreat(["\n",'unable_to_start_cleanup_operation',lc($runningJobs[0]).'_running',"\n"],$jobType);
	} else {	
		while(1){
			%runningJobs = Helpers::getRunningJobs(@availableBackupJobs);	
			@runningJobs = keys %runningJobs;
			if($jobType eq 'periodic' and scalar(@runningJobs)){
				$runningJobName = 
				Helpers::traceLog($Locale::strings{'delaying_cleanup_operation_reason'}.$Locale::strings{$runningJobName.'_running'});
				sleep(60);
				next;
			}
			last;
		}

		if ($jobType eq 'manual' and scalar(keys %runningJobs)>0) {
			if(scalar(keys %runningJobs) > 1){
				Helpers::retreat(["\n",'unable_to_start_cleanup_operation','manual_scheduled_backup_jobs_running',"\n"],$jobType);
			} else {
				Helpers::retreat(["\n",'unable_to_start_cleanup_operation',lc($runningJobs[0]).'_running',"\n"],$jobType);
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
	my $jobRunningDir  = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $isDedup  	   = Helpers::getUserConfiguration('DEDUP');
	my $backupLocation = Helpers::getUserConfiguration('BACKUPLOCATION');
	$backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
		
	#Displaying progress of file scanning with count
	if($jobType eq 'manual'){
		Helpers::display("\n");
		Helpers::getCursorPos(3,$Locale::strings{'scanning_files'}."\n");
	}
	
	my @itemsStat = checkBackupsetItemStatus();
	exitCleanup()	if(scalar(@itemsStat)<1);
	
	my $archiveFileList = $jobRunningDir.'/'.$Configuration::archiveFileResultFile;
	if(!open(ARCHIVE_FILE_HANDLE, ">", $archiveFileList)) {
		Helpers::traceLog($Locale::strings{'failed_to_open_file'}.":$archiveFileList. Reason:$!");
		exitCleanup();
	}
	
	my $archiveFolderList = $jobRunningDir.'/'.$Configuration::archiveFolderResultFile;
	if(!open(ARCHIVE_FOLDER_HANDLE, ">", $archiveFolderList)) {
		Helpers::traceLog($Locale::strings{'failed_to_open_file'}.":$archiveFolderList. Reason:$!");
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
				my $progressMsg = $Locale::strings{'files_scanned'}." $totalFileCount\nScanning... $fields[0]{'fname'}";
				Helpers::displayProgress($progressMsg,2) if($jobType eq 'manual');
			}
		}		
	} else {
		foreach my $tmpLine (@itemsStat) {
			my @fields   = $tmpLine;
			if (ref($fields[0]) ne "HASH") {
				next;
			}			
			my $itemName = $fields[0]{'fname'};
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
				my $progressMsg = $Locale::strings{'files_scanned'}." $totalFileCount\nScanning... $tempItemName";
				Helpers::displayProgress($progressMsg,2) if($jobType eq 'manual');
			}
		}		
	}
	#print Dumper(\@dirList);
	foreach my $itemName (@dirListForAuth){
		startEnumerateOperation($itemName);
	}	
	close(ARCHIVE_FILE_HANDLE);
	close(ARCHIVE_FOLDER_HANDLE);
	Helpers::displayProgress($Locale::strings{'scan_completed'},2) if($jobType eq 'manual');
	return 0;
}

#*****************************************************************************************************
# Subroutine			: checkBackupsetItemStatus
# Objective				: This function will get status of backup set items
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkBackupsetItemStatus
{
	my $jobRunningDir  = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $isDedup  	   = Helpers::getUserConfiguration('DEDUP');
	my $backupLocation = Helpers::getUserConfiguration('BACKUPLOCATION');
	$backupLocation = '/'.$backupLocation  unless($backupLocation =~ m/^\//);
	
	my $backupsetFilePath = Helpers::getUsersInternalDirPath('scheduled_backup')."/".$Configuration::backupsetFile;
	if(!open(BACKUPLIST, $backupsetFilePath)){
		$errMsg = $Locale::strings{'failed_to_open_file'}.": $backupsetFilePath, Reason: $!";
		return 0;
	}
	my $tempBackupsetFilePath = $jobRunningDir."/".$Configuration::tempBackupsetFile;
	if(!open(BACKUPLISTNEW, ">", $tempBackupsetFilePath)){
		$errMsg = $Locale::strings{'failed_to_open_file'}.": $tempBackupsetFilePath, Reason: $!";
		return 0;
	}
	
	my $finalBackupLocation= '';
	$finalBackupLocation = $backupLocation		if($isDedup eq 'off' and $backupLocation ne '/');
	
	my @arryToCheck = ();
	while(<BACKUPLIST>) {
		Helpers::Chomp(\$_);
		next	if($_ eq "");
			
		my $rItem = $_;
		if(substr($_, 0, 1) ne "/") {
			$rItem = "/".$_;
		} 
		else {
			$rItem = $finalBackupLocation.$_;
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
	
	my $itemStatusUTFpath = $jobRunningDir.'/'.$Configuration::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$Configuration::evsErrorFile;
	if($isDedup eq 'off'){
		Helpers::createUTF8File(['ITEMSTATUS',$itemStatusUTFpath],
			$tempBackupsetFilePath,
			$evsErrorFile
			) or Helpers::retreat('failed_to_create_utf8_file');	
	} else {
		my $deviceID    = Helpers::getUserConfiguration('BACKUPLOCATION');
		$deviceID 		= (split("#",$deviceID))[0];		
		Helpers::createUTF8File(['ITEMSTATUSDEDUP',$itemStatusUTFpath],
			$deviceID,
			$tempBackupsetFilePath,					
			$evsErrorFile					
			) or Helpers::retreat('failed_to_create_utf8_file');	
	}
	my @responseData = Helpers::runEVS('item',1);
	unlink($tempBackupsetFilePath);
	
	if(-s $evsErrorFile > 0) {
		my $errStr = Helpers::checkExitError($evsErrorFile,$jobType.'_archive');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			$errMsg = $errStr;
			exitCleanup();
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
	my $jobRunningDir  = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $isDedup  	   = Helpers::getUserConfiguration('DEDUP');
	my $backupLocation = Helpers::getUserConfiguration('BACKUPLOCATION');
	   $backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
	my $searchDir 	   = $jobRunningDir.'/'.$Configuration::searchDir;
	
	my $remoteFolder = $_[0];
	if (substr($remoteFolder, -1, 1) ne "/") {
	   $remoteFolder .= "/";
	}	
	#print "remoteFolder: $remoteFolder\n";
	my $searchItem = "*";
	my $errStr = "";
	#my $searchUTFpath = $searchDir.'/'.$Configuration::utf8File;
	#my $evsOutputFile = $searchDir.'/'.$Configuration::evsOutputFile;
	#my $evsErrorFile  = $searchDir.'/'.$Configuration::evsErrorFile;
	my $tempSearchUTFpath = $searchDir.'/'.$Configuration::utf8File;
	my $tempEvsOutputFile = $searchDir.'/'.$Configuration::evsOutputFile;
	my $tempEvsErrorFile  = $searchDir.'/'.$Configuration::evsErrorFile;
	
	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);
	
	if($isDedup eq 'off'){
		Helpers::createUTF8File(['SEARCH',$tempSearchUTFpath],
					$tempEvsOutputFile,
					$tempEvsErrorFile,
					$remoteFolder
					) or Helpers::retreat('failed_to_create_utf8_file');	
	} else {	
		my $deviceID    = Helpers::getUserConfiguration('BACKUPLOCATION');
		$deviceID 		= (split("#",$deviceID))[0];		
		Helpers::createUTF8File(['SEARCHDEDUP',$tempSearchUTFpath],
					$deviceID,
					$tempEvsOutputFile,
					$tempEvsErrorFile,
					$remoteFolder
					) or Helpers::retreat('failed_to_create_utf8_file');	
	}
	my @responseData = Helpers::runEVS('item',1,1,$tempSearchUTFpath);
	while(1){
		if((-e $tempEvsOutputFile and -s $tempEvsOutputFile) or  (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
			last;
		}
		sleep(2);
		next;		
	}
	if(-s $tempEvsOutputFile == 0 and -s $tempEvsErrorFile > 0) {
		my $errStr = Helpers::checkExitError($tempEvsErrorFile,$jobType.'_archive');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			$errMsg = $errStr;
			exitCleanup();
		}		
		return 0;
	}
	
	my $tempRemoteFolder = $remoteFolder;
	   $tempRemoteFolder = substr($tempRemoteFolder,1) if(substr($tempRemoteFolder,0,1) eq '/');
	   chop($tempRemoteFolder) if(substr($tempRemoteFolder,-1,1) eq '/');
	   $tempRemoteFolder =~ s/[\s]+|[\/]+/_/g; #Replacing space & slash(/) with underscore(_)  
	my $tempArchiveListFile  = $searchDir.'/'."$tempRemoteFolder.txt";
	#print "tempArchiveListFile:$tempArchiveListFile\n";
	#if(!open($TEMPARCHIVELIST, ">>", $tempArchiveListFile)){
	#	Helpers::traceLog(['failed_to_open_file',": $tempArchiveListFile, Reason: $!"]);
	#	return 0;
	#}
	open my $TEMPARCHIVELIST, ">>", $tempArchiveListFile or ($errStr = $Locale::strings{'failed_to_open_file'}.":$tempArchiveListFile. Reason:$!");
	if($errStr ne ""){
		Helpers::traceLog($errStr);
		return 0;
	}
	
	# parse search output.
	open my $SEARCHOUTFH, "<", $tempEvsOutputFile or ($errStr = $Locale::strings{'failed_to_open_file'}.":$tempEvsOutputFile. Reason:$!");
	if($errStr ne ""){
		Helpers::traceLog($errStr);		
		return 0;
	}

	#my $splitLimit = 43;
	#if($isDedup eq 'off'){
	#	$splitLimit = 13;
	#}
	
	my @fileList =();
	my ($buffer,$lastLine) = ("") x 2;
	my $skipFlag = 0;
	while(1){
		my $byteRead = read($SEARCHOUTFH, $buffer, $Configuration::bufferLimit);
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
			#$lastLine = $resultList[$#resultList];
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}

		foreach my $tmpLine (@resultList){
			#print "\ntemp tmpLine::$tmpLine\n";
			if($tmpLine =~ /fname/) {
				my %fileName = Helpers::parseXMLOutput(\$tmpLine);	
				if(scalar(keys %fileName) < 5){
					next;
				}
				my $temp = $fileName{'fname'};
				#print "temp fileName::$temp\n";
				Helpers::replaceXMLcharacters(\$temp);
				my $tempItemName = $temp;
				if($isDedup eq 'off' and $backupLocation ne '/'){
					$tempItemName =~ s/$backupLocation//;
				}
				$totalFileCount++;
				print $TEMPARCHIVELIST $temp."\n";
				push(@fileList, $temp);
				$notExistCount++;
				my $progressMsg = $Locale::strings{'files_scanned'}." $totalFileCount\nScanning... $tempItemName";
				Helpers::displayProgress($progressMsg,2) if($jobType eq 'manual');
			} 
			elsif($tmpLine ne ''){
				if($tmpLine =~ m/(files_found|items_found)/){
					$skipFlag = 1;				
				}  elsif($tmpLine !~ m/(connection established|receiving file list)/) {
					Helpers::traceLog("Archive search:".$tmpLine);
				}
			}			
		}
		if($skipFlag) {
			last;
		}		
	}
	#$archivedDirAndFile{$remoteFolder} = @fileList;
	push @{$archivedDirAndFile{$remoteFolder}}, \@fileList;
	close($TEMPARCHIVELIST);
	close($SEARCHOUTFH);
	
	if(-s $tempEvsErrorFile > 0) {
		my $errStr = Helpers::checkExitError($tempEvsErrorFile,$jobType.'_archive');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			$errMsg = $errStr;
			exitCleanup();
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
	my $jobRunningDir  = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $isDedup  	   = Helpers::getUserConfiguration('DEDUP');
	my $backupLocation = Helpers::getUserConfiguration('BACKUPLOCATION');
	   $backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
	my $searchDir 	   = $jobRunningDir.'/'.$Configuration::searchDir;
	
	my $remoteFolder = $_[0];
	my $searchItem = "*";
	my $errStr = "";
	my $tempPath = $remoteFolder;
	   $tempPath =~ s/[\/]$//g; #Removing last "/"
	   $tempPath =~ s/[\s]+|[\/]+/_/g; #Replacing space & slash(/) with underscore(_)
	#my $tempAuthListUTFpath = $searchDir.'/'.$Configuration::utf8File.$tempPath;
	#my $tempEvsOutputFile   = $searchDir.'/'.$Configuration::evsOutputFile.$tempPath;
	#my $tempEvsErrorFile    = $searchDir.'/'.$Configuration::evsErrorFile.$tempPath;
	
	my $tempAuthListUTFpath = $searchDir.'/'.$Configuration::utf8File."_AuthList";
	my $tempEvsOutputFile   = $searchDir.'/'.$Configuration::evsOutputFile."_AuthList";
	my $tempEvsErrorFile    = $searchDir.'/'.$Configuration::evsErrorFile."_AuthList";
	
	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);
	
	if($isDedup eq 'off'){
		Helpers::createUTF8File(['AUTHLIST',$tempAuthListUTFpath],
					$tempEvsOutputFile,
					$tempEvsErrorFile,
					$remoteFolder
					) or Helpers::retreat('failed_to_create_utf8_file');	
	} else {
		my $deviceID    = Helpers::getUserConfiguration('BACKUPLOCATION');
		$deviceID 		= (split("#",$deviceID))[0];		
		Helpers::createUTF8File(['AUTHLISTDEDUP',$tempAuthListUTFpath],
					$deviceID,
					$tempEvsOutputFile,
					$tempEvsErrorFile,
					$remoteFolder
					) or Helpers::retreat('failed_to_create_utf8_file');	
	}
	my @responseData = Helpers::runEVS('item',1,1,$tempAuthListUTFpath);
	while(1){
		if((-e $tempEvsOutputFile and -s $tempEvsOutputFile) or  (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
			last;
		}
		sleep(2);
		next;		
	}
	if(-s $tempEvsOutputFile == 0 and -s $tempEvsErrorFile > 0) {
		my $errStr = Helpers::checkExitError($tempEvsErrorFile,$jobType.'_archive');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			$errMsg = $errStr;
			exitCleanup();
		}		
		return 0;
	}
	# parse search output.
	open my $OUTFH, "<", $tempEvsOutputFile or ($errStr = $Locale::strings{'failed_to_open_file'}.": $tempEvsOutputFile, Reason: $!");
	if($errStr ne ""){
		Helpers::traceLog($errStr);		
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
		my $byteRead = read($OUTFH, $buffer, $Configuration::bufferLimit);
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
			#$lastLine = $resultList[$#resultList];
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}	

		foreach my $tmpLine (@resultList){	
			if($tmpLine =~ /<item/) {
				my %fileName = Helpers::parseXMLOutput(\$tmpLine);	
				if(scalar(keys %fileName) < 5){
					next;
				}
				my $itemName = $fileName{'fname'};
				$itemName = $remoteFolder.$itemName unless($itemName =~/\//);
				Helpers::replaceXMLcharacters(\$itemName);
				my $tempItemName = $itemName;				
				if($isDedup eq 'off' and $backupLocation ne '/'){
					$tempItemName =~ s/$backupLocation//;
				}

				my $itemType = $fileName{'restype'};
				if($itemType eq "D") {
					if(-e $tempItemName){
						#startEnumerateOperation($itemName);
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
					my $progressMsg = $Locale::strings{'files_scanned'}." $totalFileCount\nScanning... $itemName";
					Helpers::displayProgress($progressMsg,2) if($jobType eq 'manual');
				}
			} 
			elsif($tmpLine ne ''){
				if($tmpLine =~ m/(bytes  received)/){
					$skipFlag = 1;				
				} elsif($tmpLine !~ m/(connection established|receiving file list)/) {
					Helpers::traceLog("Archive auth-list:".$tmpLine);
				}
			}
		}
		if($skipFlag) {
			last;
		}
	}
	close($OUTFH);
	
	if(-s $tempEvsErrorFile > 0) {
		my $errStr = Helpers::checkExitError($tempEvsErrorFile,$jobType.'_archive');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			$errMsg = $errStr;
			exitCleanup();
		}		
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
	my $isDedup  	      = Helpers::getUserConfiguration('DEDUP');
	my $jobRunningDir     = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $itemStatusUTFpath = $jobRunningDir.'/'.$Configuration::utf8File;
	my $evsOutputFile     = $jobRunningDir.'/'.$Configuration::evsOutputFile;
	my $evsErrorFile      = $jobRunningDir.'/'.$Configuration::evsErrorFile;
	my $archiveFileList   = $jobRunningDir.'/'.$Configuration::archiveFileResultFile;
	my $archiveFolderList = $jobRunningDir.'/'.$Configuration::archiveFolderResultFile;	
	my $errorContent	  = '';
	
	my $logTime = time;
	Helpers::Chomp(\$logTime); #Removing white-space and '\n'
	my $archiveLogDirpath = $jobRunningDir.'/'.$Configuration::logDir;
	Helpers::createDir($archiveLogDirpath, 1);
	$logOutputFile = $archiveLogDirpath.'/'.$logTime;
	
	my $logStartTime = `date +"%a %b %d %T %Y"`;
	Helpers::Chomp(\$logStartTime); #Removing white-space and '\n'
	
	#Opening to log file handle
	if(!open(ARCHIVELOG, ">", $logOutputFile)){
		Helpers::traceLog($Locale::strings{'failed_to_open_file'}.": $logOutputFile, Reason: $!");
		return 0;
	}
	
	print ARCHIVELOG $Locale::strings{'start_time'}.$logStartTime."\n\n";
	print ARCHIVELOG ucfirst($Locale::strings{'username'}).": ".Helpers::getUsername()."\n";
	print ARCHIVELOG $Locale::strings{'backupset'}.$Locale::strings{'scheduled_backup_set'}."\n";
	
	if($jobType eq 'periodic'){
		print ARCHIVELOG $Locale::strings{'periodic_cleanup_operation'}."\n\n";
	} else {
		print ARCHIVELOG $Locale::strings{'archive_cleanup_operation'}."\n\n";
	}

	#Checking pid & cancelling process if job terminated by user
	my $pidPath = "$jobRunningDir/pid.txt";
	cancelProcess()		unless(-e $pidPath);
	
	unless(defined($_[0])){
		#Displaying progress of file deletion
		if($jobType eq 'manual'){
			Helpers::display("\n");
			Helpers::getCursorPos(2,$Locale::strings{'preparing_to_delete'});
		}
		
		#Deleting files
		if(-e $archiveFileList and -s $archiveFileList>0){
			if($isDedup eq 'off'){
				Helpers::createUTF8File(['DELETE',$itemStatusUTFpath],
							$archiveFileList,
							$evsOutputFile,
							$evsErrorFile
							) or Helpers::retreat('failed_to_create_utf8_file');	
			} else {
				my $deviceID    = Helpers::getUserConfiguration('BACKUPLOCATION');
				$deviceID 		= (split("#",$deviceID))[0];		
				Helpers::createUTF8File(['DELETEDEDUP',$itemStatusUTFpath],
							$deviceID,
							$archiveFileList,
							$evsOutputFile,
							$evsErrorFile
							) or Helpers::retreat('failed_to_create_utf8_file');	
			}
			my @responseData = Helpers::runEVS('item',1,1);
			my $errStr = "";
			
			while(1){
				if((-e $evsOutputFile and -s $evsOutputFile) or  (-e $evsErrorFile and -s $evsErrorFile)){
					last;
				}
				sleep(2);
				next;		
			}
			if(-s $evsOutputFile == 0 and -s $evsErrorFile > 0) {
				my $errStr = Helpers::checkExitError($evsErrorFile,$jobType.'_archive');
				if($errStr and $errStr =~ /1-/){
					$errStr =~ s/1-//;
					$errMsg = $errStr;
					exitCleanup();
				}
				return 0;
			}
	
			# parse delete output.
			open OUTFH, "<", $evsOutputFile or ($errStr = $Locale::strings{'failed_to_open_file'}.": $evsOutputFile, Reason: $!");
			if($errStr ne ""){
				Helpers::traceLog($errStr);		
				return 0;
			}
			
			# Appending deleted files/folders details to log
			print ARCHIVELOG $Locale::strings{'deleted_content'}."\n\n";
			
			my ($buffer,$lastLine) = ("") x 2;	
			my $skipFlag = 0;
			while(1){
				my $byteRead = read(OUTFH, $buffer, $Configuration::bufferLimit);
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
						my %fileName = Helpers::parseXMLOutput(\$tmpLine);
						if(scalar(keys %fileName) < 2){
							next;
						}					
						my $op		 = $fileName{'op'};
						my $fileName = $fileName{'fname'};
						Helpers::replaceXMLcharacters(\$fileName);
						print ARCHIVELOG "[$op] [$fileName]\n"; #Appending deleted file detail to log file
						my $progressMsg = "[$op] [$fileName]";	
						Helpers::displayProgress($progressMsg,1) if($jobType eq 'manual');
						$deletedFilesCount++;
					} elsif($tmpLine ne '' and $tmpLine !~ m/(connection established|receiving file list)/){
						$errorContent .= $tmpLine."\n";
						Helpers::traceLog("Delete operation error content:$tmpLine");
					}
				}
				if($buffer ne '' and ($buffer =~ m/End of operation/)){
					last;			
				}
			}
			close(OUTFH);
			if(-e $evsErrorFile and -s $evsErrorFile > 0) {
				#Reading error file and appending to log file
				if(!open(TEMPERRORFILE, "< $evsErrorFile")) {
					Helpers::traceLog($Locale::strings{'failed_to_open_file'}.":$evsErrorFile, Reason:$!");
				}		
				$errorContent .= <TEMPERRORFILE>;
				close TEMPERRORFILE;		
			}
			unlink($evsOutputFile);
			unlink($evsErrorFile);
		}

		#Deleting folders
		if(-e $archiveFolderList and -s $archiveFolderList>0){
			if($isDedup eq 'off'){
				Helpers::createUTF8File(['DELETE',$itemStatusUTFpath],
							$archiveFolderList,
							$evsOutputFile,
							$evsErrorFile
							) or Helpers::retreat('failed_to_create_utf8_file');	
			} else {
				my $deviceID    = Helpers::getUserConfiguration('BACKUPLOCATION');
				$deviceID 		= (split("#",$deviceID))[0];		
				Helpers::createUTF8File(['DELETEDEDUP',$itemStatusUTFpath],
							$deviceID,
							$archiveFolderList,
							$evsOutputFile,
							$evsErrorFile
							) or Helpers::retreat('failed_to_create_utf8_file');	
			}
			my @responseData = Helpers::runEVS('item',1,1);
			my $errStr = "";
			while(1){
				if((-e $evsOutputFile and -s $evsOutputFile) or  (-e $evsErrorFile and -s $evsErrorFile)){
					last;
				}
				sleep(2);
				next;		
			}
			if(-s $evsOutputFile == 0 and -s $evsErrorFile > 0) {
				my $errStr = Helpers::checkExitError($evsErrorFile,$jobType.'_archive');
				if($errStr and $errStr =~ /1-/){
					$errStr =~ s/1-//;
					$errMsg = $errStr;
					exitCleanup();
				}				
				return 0;
			}
			
			# parse delete output.
			open OUTFH, "<", $evsOutputFile or ($errStr = $Locale::strings{'failed_to_open_file'}.": $evsOutputFile, Reason: $!");
			if($errStr ne ""){
				Helpers::traceLog($errStr);		
				return 0;
			}
			
			my $serverRoot = Helpers::getUserConfiguration('SERVERROOT');
			# Appending deleted files/folders details to log			
			my ($buffer,$lastLine) = ("") x 2;	
			my $skipFlag = 0;
			while(1){
				my $byteRead = read(OUTFH, $buffer, $Configuration::bufferLimit);
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
				#print "\n\n\nbuffer:$buffer\n\n\n";
				my @resultList = split /\n/, $buffer;
				
				if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
					$lastLine = pop @resultList;
				}
				else {
					$lastLine = "";
				}		

				foreach my $tmpLine (@resultList){
					if($tmpLine =~ /<item/){
						my %fileName = Helpers::parseXMLOutput(\$tmpLine);	
						if(scalar(keys %fileName) < 2){
							next;
						}					
					
						my $op		 = $fileName{'op'};
						my $fileName = $fileName{'fname'};
						Helpers::replaceXMLcharacters(\$fileName);
					
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
							Helpers::displayProgress($progressMsg,1) if($jobType eq 'manual');
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
			if(-e $evsErrorFile and -s $evsErrorFile > 0) {
				#Reading error file and appending to log file
				if(!open(TEMPERRORFILE, "< $evsErrorFile")) {
					Helpers::traceLog($Locale::strings{'failed_to_open_file'}.":$evsErrorFile, Reason:$!");
				}
				my @errorArray = <TEMPERRORFILE>;
				foreach my $errorLine (@errorArray){
					if($errorLine =~ /[IOERROR]/i){
						if($errorLine =~ /\[(.*?)\]/g){
							my $folderName = $1;
							Helpers::replaceXMLcharacters(\$folderName);
							#if (substr($folderName, -1, 1) eq "/") {
							#	chop($folderName);
							#}
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
		my $progressMsg = $Locale::strings{'delete_operation_has_been_completed'};
		Helpers::displayProgress($progressMsg,1) if($jobType eq 'manual');
		writeSummary();
	} else {
		print ARCHIVELOG $_[0]."\n";
	}	

	my $logEndTime = `date +"%a %b %d %T %Y"`;
	Helpers::Chomp(\$logEndTime); #Removing white-space and '\n'
	print ARCHIVELOG $Locale::strings{'end_time'}.$logEndTime."\n";
	
	#Appending error content to log file
	if($errorContent ne '') {
		print ARCHIVELOG "\n".$Locale::strings{'additional_information'};
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
	my $jobRunningDir = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $pidPath = $jobRunningDir.'/pid.txt';
	
	if(!-e $pidPath){
		$errMsg = 'operation_cancelled_by_user';
	} 
	else {
		# Killing EVS operations if job not terminated by job_termination script
		my $username = Helpers::getUsername();
		my $jobTerminationPath = Helpers::getScript('job_termination');
		my $archiveJobType = $jobType.'_archive';
		my $cmd = "$Configuration::perlBin \'$jobTerminationPath\' \'$archiveJobType\' \'$username\' 1>/dev/null 2>/dev/null";
		system($cmd);
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
	
	my $retVal = renameLogFile(1); 				#Renaming the log output file name with status
	if(defined($errStr) and $errStr ne ''){
		Helpers::display(["\n",$errStr,"\n"]);
	} elsif($retVal and $errMsg ne ''){
		Helpers::display([$errMsg,"\n"]); #Added to print the error message if there is no summary to display  
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
	my $jobRunningDir = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $searchDir     = $jobRunningDir.'/'.$Configuration::searchDir;
	my $pidPath   	  = $jobRunningDir.'/pid.txt';
	my $cancelFile 	  = $jobRunningDir.'/cancel.txt';
	my $evsOutputFile = $jobRunningDir.'/'.$Configuration::evsOutputFile;	
	my $evsErrorFile  = $jobRunningDir.'/'.$Configuration::evsErrorFile;
	my $itemStatusUTFpath       = $jobRunningDir.'/'.$Configuration::utf8File;
	my $archiveFileResultFile   = $jobRunningDir.'/'.$Configuration::archiveFileResultFile;
	my $archiveFolderResultFile = $jobRunningDir.'/'.$Configuration::archiveFolderResultFile;
	my $tempBackupsetFilePath   = $jobRunningDir."/".$Configuration::tempBackupsetFile;
	
	system("rm -rf '$searchDir'");
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
		$archivePercentage = Helpers::getAndValidate('enter_percentage_of_files_for_cleanup', "percentage_for_cleanup", 1);
		my $displayMsg = $Locale::strings{'you_have_selected_per_as_cleanup_limit'};
		$displayMsg =~ s/<PER>/$archivePercentage/;
		Helpers::display($displayMsg);
		sleep(2);	
	} else {
		$archivePercentage = int($ARGV[1]);
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
	my $jobRunningDir     = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $archiveFileList   = $jobRunningDir.'/'.$Configuration::archiveFileResultFile;
	
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
			$errMsg = $Locale::strings{'operation_aborted_due_to_percentage'};
			$errMsg =~ s/<PER1>/$perCount/;
			$errMsg =~ s/<PER2>/$archivePercentage/;
			$errMsg .= "\n\n".$Locale::strings{'total_files_in_your_backupset'}.$totalFileCount."\n";
			$errMsg .= $Locale::strings{'total_files_listed_for_deletion'}.$notExistCount."\n";

			if($jobType eq 'manual'){
				$errMsg = $Locale::strings{'archive_cleanup'}." ".$errMsg;
				Helpers::display(["\n\n",$errMsg]);
			} else {
				$errMsg = $Locale::strings{'periodic_cleanup'}." ".$errMsg."\n";
			}			
		} 
		elsif($jobType eq 'manual'){
			my $files;
			if($notExistCount>1){
				Helpers::display(["\n\n","$notExistCount ",'files_are_present_in_your_account','do_you_want_view_y_or_n'], 1);
				$files = "$notExistCount files are ";
			} else {
				Helpers::display(["\n\n","$notExistCount ",'file_is_present_in_your_account','do_you_want_view_y_or_n'], 1);
				$files = "$notExistCount file is ";
			}
			#my $toViewConfirmation = Helpers::getConfirmationChoice('enter_your_choice');
			my $toViewConfirmation = Helpers::getAndValidate('enter_your_choice','YN_choice');
			
			#Checking pid & cancelling process if job terminated by user
			cancelProcess()		unless(-e $pidPath);
			
			if(lc($toViewConfirmation) eq 'y') {
				my $mergedArchiveList = mergeAllArchivedFiles();
				Helpers::openEditor('view',$mergedArchiveList);
				unlink($mergedArchiveList);
			}
			
			#Checking pid & cancelling process if job terminated by user
			cancelProcess()		unless(-e $pidPath);
			
			Helpers::display(["\n",'do_u_want_to_delete_permanently'], 1);
			$toViewConfirmation = Helpers::getAndValidate('enter_your_choice','YN_choice');
			if(lc($toViewConfirmation) eq 'n') {
				removeIntermediateFiles();
				exit 0;
			}
		}
		if($jobType eq 'manual' or ($jobType eq 'periodic' and defined($_[0]))){
			deleteArchiveFiles($errMsg);
		}
	} elsif($jobType eq 'manual'){
		Helpers::display(["\n\n",'there_are_no_items_to_delete',"\n"], 1);
	} else {
		#$errMsg = $Locale::strings{'periodic_cleanup'}.": ".$Locale::strings{'there_are_no_items_to_delete'}."\n";
		$errMsg = $Locale::strings{'there_are_no_items_to_delete'}."\n";
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
# Subroutine			: getOperationStatus
# Objective				: Getting operation status & appending to output file and renaming file name with status
# Added By				: Senthil Pandian
#********************************************************************************
sub getOperationStatus{
	return 0	if(!defined($logOutputFile) or !-e $logOutputFile);

	my $logOutputFileStatusFile;
	my $jobRunningDir  = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $userCancelFile = $jobRunningDir.'/cancel.txt';
	if(-e $userCancelFile or defined($_[0])){
		unlink($userCancelFile);		
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'aborted'};
		writeSummary(1);
	}
	elsif(defined($errMsg) and $errMsg =~ /operation aborted/i){
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'aborted'};
	}
	elsif($notExistCount>0 and $notExistCount == $deletedFilesCount){
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'success'};
	}
	else {
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'failure'};
	}
		
	system("mv '$logOutputFile' '$logOutputFileStatusFile'");
	Helpers::display([$Locale::strings{'for_more_details_refer_the_log'},"\n","\"$logOutputFileStatusFile\"","\n"], 1) if($jobType eq 'manual');
}

#********************************************************************************
# Subroutine			: renameLogFile
# Objective				: Rename the log file name with status
# Added By				: Senthil Pandian
#********************************************************************************
sub renameLogFile{
	return 0	if(!defined($logOutputFile) or !-e $logOutputFile);

	my $logOutputFileStatusFile;
	my $jobRunningDir  = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $userCancelFile = $jobRunningDir.'/cancel.txt';
	if(-e $userCancelFile or defined($_[0])){
		unlink($userCancelFile);		
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'aborted'};
		writeSummary(1);
	}
	elsif(defined($errMsg) and $errMsg =~ /operation aborted/i){
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'aborted'};
	}
	elsif($notExistCount>0 and $notExistCount == $deletedFilesCount){
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'success'};
	}
	else {
		$logOutputFileStatusFile = $logOutputFile.'_'.$Locale::strings{'failure'};
	}
		
	system("mv '$logOutputFile' '$logOutputFileStatusFile'");
	Helpers::display([$Locale::strings{'for_more_details_refer_the_log'},"\n","\"$logOutputFileStatusFile\"","\n"], 1) if($jobType eq 'manual');
}

#********************************************************************************
# Subroutine			: mergeAllArchivedFiles
# Objective				: Merge all archive list files
# Added By				: Senthil Pandian
#********************************************************************************
sub mergeAllArchivedFiles{
	my $jobRunningDir     = Helpers::getUsersInternalDirPath($jobType.'_archive');
	my $searchDir     	  = $jobRunningDir.'/'.$Configuration::searchDir;
	my $archiveFileList   = $jobRunningDir.'/'.$Configuration::archiveFileResultFile;
	my $archiveFileView   = $jobRunningDir.'/'.$Configuration::archiveFileListForView;
	my $pidPath 		  = $jobRunningDir."/pid.txt";
	
	#Appending content of a file to another file
	if(-s $archiveFileList>0){
		my $appendFiles = "cat '$archiveFileList' > '$archiveFileView'";
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
	my $summary = "\n".$Locale::strings{'summary'}."\n";
	$summary   .= $Locale::strings{'items_considered_for_delete'}.$notExistCount."\n";
	$summary   .= $Locale::strings{'items_deletes_now'}.$deletedFilesCount."\n";
	if(defined($_[0])){
		$summary   .= $Locale::strings{'items_failed_to_delete'}."0\n\n";
		$summary   .= $Locale::strings{'operation_cancelled_by_user'}."\n\n";
	} else {
		$summary   .= $Locale::strings{'items_failed_to_delete'}.($notExistCount-$deletedFilesCount)."\n\n";
	}
	print ARCHIVELOG $summary;
	print "\n\n".$summary if($jobType eq 'manual');
}		