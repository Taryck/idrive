#!/usr/bin/perl

#######################################################################
#Script Name : Backup_Script.pl
#######################################################################
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));

require 'Header.pl';
use FileHandle;
use POSIX;

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
my $pid_OutputProcess = undef;
my $backupPid = undef; #Process ID of child process#
my $generateFilesPid = undef; #Process ID of child process for generate Backup set files#
my $errorFilePresent = false;
#Check if EVS Binary exists.
#my $lineCount; This variable is not used at any place in the script.
#my $prevLineCount; This variable is not used at any place in the script.
my $cancelFlag = 0;
my %backupExcludeHash = (); #Hash containing items present in Exclude List#
my $backupUtfFile = '';

my $maxNumRetryAttempts = 5;
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
my $pidTestFlag = 0;
my $prevTime = time();
my $relativeFileset = "BackupsetFile_Rel";
my $filesOnly = "BackupsetFile_filesOnly";
my $noRelativeFileset = "BackupsetFile_NoRel";
$jobType = "LocalBackup";
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
my @commandArgs = qw(--silent SCHEDULED);
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
$SIG{INT} = \&process_term;
$SIG{TERM} = \&process_term;
$SIG{TSTP} = \&process_term;
$SIG{QUIT} = \&process_term;
$SIG{PWR} = \&process_term;
$SIG{KILL} = \&process_term;
$SIG{USR1} = \&process_term;

#Assigning Perl path
my $perlPath = `which perl`;
chomp($perlPath);	
if($perlPath eq ''){
	$perlPath = '/usr/local/bin/perl';
}
###################################################
#The signal handler invoked when SIGINT or SIGTERM#
#signal is received by the script                 #
###################################################
sub process_term()
{
    #traceLog("$lineFeed Inside process_term--------------------- $lineFeed", __FILE__, __LINE__);
	my $signame = shift;
	unlink($pidPath);
	cancelSubRoutine();
	exit(0);
}

$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 

getConfigHashValue();
loadUserData();
my $BackupsetFile = $localBackupsetFilePath;

# Trace Log Entry #
my $curFile = basename(__FILE__);
#traceLog("$lineFeed File: $curFile ---------------------------------------- $lineFeed", __FILE__, __LINE__);
#Flag to silently do backup operation.
my $silentBackupFlag = 0;
if (${ARGV[0]} eq '--silent'){
	$silentBackupFlag = 1;
}

headerDisplay($0) if ($silentBackupFlag == 0 and $ARGV[0] ne 'SCHEDULED');
#Verifying if Backup scheduled or manual job
my $flagToCheckSchdule = 0;
if(${ARGV[0]} eq "SCHEDULED") {
	$pwdPath = $pwdPath."_SCH";
	$pvtPath = $pvtPath."_SCH";
	$flagToCheckSchdule = 1;
	$taskType = "Scheduled";
	$BackupsetFile = $backupsetSchFilePath;
#	$CurrentBackupsetSoftPath = $backupsetSchFileSoftPath;
	chmod $filePermission, $BackupsetFile;
	if(!backupTypeCheck()) {
		$relative = 1;
	}
} else {
	$taskType = "Manual";
#	getParameterValue(\"PVTKEY", \$hashParameters{PVTKEY});
#	my $pvtKey = $hashParameters{$pvtParam};
	if(getAccountConfStatus($confFilePath)){
        	exit(0);
	}
	else{
		if(getLoginStatus($pwdPath)){
            exit(0);
        }
	}

	backupTypeCheck();
#	$CurrentBackupsetSoftPath = $backupsetFileSoftPath;
}
if (! checkIfEvsWorking($dedup)){
        print Constants->CONST->{'EvsProblem'}.$lineFeed;
        exit 0;
}
if($dedup eq 'on' and !$serverRoot){
	print Constants->CONST->{'verifyAccount'}.$lineFeed;
	%evsDeviceHashOutput = getDeviceList();
	if(exists($evsDeviceHashOutput{uid}->{$uniqueID})){
		my %serverRootHash = reverse(%{$evsDeviceHashOutput{server_root}});
		$serverRoot  = $serverRootHash{$evsDeviceHashOutput{uid}->{$uniqueID}};
		putParameterValue(\"SERVERROOT",\"$serverRoot",$confFilePath);
	}

	if(!$serverRoot){
		print Constants->CONST->{'serverRootNotFound'}.$lineFeed.$lineFeed;
		exit;
	}
}
#traceLog("$lineFeed File: $curFile ---------------------------------------- $lineFeed", __FILE__, __LINE__);
#Getting working dir path and loading path to all other files
$jobRunningDir = "$usrProfilePath/$userName/$jobType/$taskType";

if(!-d $jobRunningDir) {
	mkpath($jobRunningDir);
	chmod $filePermission, $jobRunningDir;
}
exit 1 if(!checkEvsStatus(Constants->CONST->{'BackupOp'}));
#Checking if another job is already in progress
$pidPath = "$jobRunningDir/pid.txt";
if(!pidAliveCheck()) {
	$pidMsg = "Express backup is already in progress. Please try again later.\n";
	print $pidMsg;
	traceLog($pidMsg, __FILE__, __LINE__);
	exit 1;
}
#Loading global variables
$evsTempDirPath = "$jobRunningDir/evs_temp";
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
my $incSize = "$jobRunningDir/transferredFileSize.txt";
my $trfSizeAndCountFile = "$jobRunningDir/trfSizeAndCount.txt";
$excludeDirPath  = "$jobRunningDir/Excluded";
$excludedLogFilePath  = "$excludeDirPath/excludedItemsLog.txt";
my $mountPointFilePath = "$jobRunningDir/mountPoint.txt";
$errorDir = $jobRunningDir."/ERROR";
                     
# pre cleanup for all intermediate files and folders.
`rm -rf '$relativeFileset'* '$noRelativeFileset'* '$filesOnly'* '$info_file' '$retryinfo' '$errorDir' '$statusFilePath' '$excludeDirPath' '$incSize' '$failedfiles'*`;
unlink($progressDetailsFilePath);

our $mountedPath = getMountedPath();
our $IDriveLocal = "$mountedPath/IDriveLocal";
our $localUserPath = "$IDriveLocal/$userName";

#Start creating required file/folder
if(!-d $errorDir) {
	mkdir($errorDir);
	chmod $filePermission, $errorDir;
}

if(!-d $excludeDirPath) {
	mkdir($excludeDirPath);
	chmod $filePermission, $excludeDirPath;
}
	
#getParameterValue(\"PASSWORD",\$hashParameters{PASSWORD});
#my $encType = checkEncType($flagToCheckSchdule); # This function has been called inside getOperationFile() function.
my $maximumAttemptMessage = '';
my $serverAddress = verifyAndLoadServerAddr();
if ($serverAddress == 0){
	exit_cleanup($errStr);
}
createUpdateBWFile();
checkPreReq($BackupsetFile,$jobType,$taskType,'NOBACKUPDATA');
createLogFiles("BACKUP");
createBackupTypeFile();
#versionDevDisplay() if ($silentBackupFlag == 0);
if ($flagToCheckSchdule == 0 and $silentBackupFlag == 0){
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
getCursorPos() if ($flagToCheckSchdule == 0 and $silentBackupFlag == 0);	
$mail_content_head = writeLogHeader($flagToCheckSchdule);
startBackup();
exit_cleanup($errStr);

#****************************************************************************************************
# Subroutine Name         : startBackup
# Objective               : This function will fork a child process to generate backupset files and get
#							count of total files considered. Another forked process will perform main 
#							backup operation of all the generated backupset files one by one.
# Added By				  : 
#*****************************************************************************************************/
sub startBackup {
	loadFullExclude();
	loadPartialExclude();
	loadRegexExclude();
	createLocalBackupDir(); #Creating the local backup location directories
	createDBPathsXmlFile();	
	$generateFilesPid = fork();

	if(!defined $generateFilesPid) {
		traceLog(Constants->CONST->{'ForkErr'}."$lineFeed", __FILE__, __LINE__);
		$errStr = "Unable to start generateBackupsetFiles operation";
		return;
	}
	
	if($generateFilesPid == 0) {
		generateBackupsetFiles();
	}
	
	close(FD_WRITE);
START:
	if(!open(FD_READ, "<", $info_file)) {
		$errStr = Constants->CONST->{'FileOpnErr'}." info_file in startBackup: $info_file to read, Reason:$!";
		return;
	}
	
	while (1) {
		if(!-e $pidPath){
			last;
		}
		
		$line = <FD_READ>;
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
			last;
		}
		else {
			my $retType = doBackupOperation($line);
			if(BACKUP_SUCCESS ne $retType) {
				$exitStatus = 1;
				last;
			} 
		}
	}
	
	$nonExistsCount = <FD_READ>;
	if($nonExistsCount ne "") {
		$nonExistsCount =~ s/FAILEDCOUNT//;
	}
	else {
		$nonExistsCount = 0;
	}
	close FD_READ;
	waitpid($generateFilesPid,0);
	undef @linesStatusFile;
	
	if($totalFiles == 0 or $totalFiles !~ /\d+/) {
		my $fileCountCmd = "cat '$info_file' | grep \"^TOTALFILES\"";
		$totalFiles = `$fileCountCmd`; 
		$totalFiles =~ s/TOTALFILES//;
		
		if($totalFiles == 0 or $totalFiles !~ /\d+/){
			traceLog("Unable to get total files count \n", __FILE__, __LINE__);
		}
	} 
		
	if(-s $retryinfo > 0 && -e $pidPath && $retrycount <= $maxNumRetryAttempts && $exitStatus == 0) {
		if($retrycount == $maxNumRetryAttempts) {
			my $index = "-1";
			$statusHash{'FAILEDFILES_LISTIDX'} = $index;
			putParameterValueInStatusFile();
		}
		
		move($retryinfo, $info_file);
		updateRetryCount();
		
		#append total file number to info
		if(!open(INFO, ">>",$info_file)){
			$errStr = Constants->CONST->{'FileOpnErr'}." info_file in startBackup : $info_file, Reason $!".$lineFeed;
			return;
		}
		print INFO "TOTALFILES $totalFiles\n";
		close INFO;
		chmod $filePermission, $info_file;
		
		goto START;
	}
}

#****************************************************************************************************
# Subroutine Name         : generateBackupsetFiles.
# Objective               : This function will generate backupset files.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub generateBackupsetFiles {
	$pidTestFlag = "GenerateFile";
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
			print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$item]. reason: Not a regular file/folder.$lineFeed";
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
			$totalFiles++;
			if(!-e $item) {
				$nonExistsCount++;
				#write into error 
				print TRACEERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $!".$lineFeed;
				next;
			} 
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
		#print FD_WRITE "$BackupsetFile_new ".RELATIVE." $current_source \n";
		print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
	} elsif($filesonlycount >0) {
		$current_source = "/";
		autoflush FD_WRITE;
		#print FD_WRITE "$filesOnly ".NORELATIVE." $current_source\n";
		print FD_WRITE "$current_source' '".NORELATIVE."' '$filesOnly\n";
	}
	
GENLAST:
	autoflush FD_WRITE;
	print FD_WRITE "TOTALFILES $totalFiles\n";
	print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
	close FD_WRITE;
	close NEWFILE;
	$pidTestFlag = "generateListFinish";
	close INFO;

	open FILESIZE, ">$fileForSize" or traceLog(Constants->CONST->{'FileOpnErr'}." $fileForSize. Reason: $!\n", __FILE__, __LINE__);
	print FILESIZE "$totalSize";
	close FILESIZE;
	chmod $filePermission, $fileForSize;
	
	close(TRACEERRORFILE);
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
				print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$temp]. reason: Not a regular file/folder.$lineFeed";
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
				$totalFiles++;
				if(!-e $temp) {
					$nonExistsCount++;
					print TRACEERRORFILE "[".(localtime)."] [FAILED] [$temp]. Reason: $!".$lineFeed;
					next;
				}
				
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
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$item]. Reason: $!".$lineFeed;
		$excludedCount++;
		traceLog("Could not open Dir $item, Reason:$!", __FILE__, __LINE__);
	}
	if($excludedCount == EXCLUDED_MAX_COUNT) {
		$excludedCount = 0;
		createExcludedLogFile30k();
	}
	return $retVal;	
}

#****************************************************************************************************
# Subroutine Name         : cancelSubRoutine
# Objective               : This subroutine gets call if user cancel the execution of script. It will do
#							all require cleanup before exiting.
# Added By				  : Arnab Gupta
# Modified By				: Dhritikana.
#*****************************************************************************************************/
sub cancelSubRoutine()
{
	if($pidTestFlag eq "GenerateFile")  {
		open FD_WRITE, ">>", $info_file or (print Constants->CONST->{'FileOpnErr'}."info_file in cancelSubRoutine: $info_file to write, Reason:$!"); # die handle?
		autoflush FD_WRITE;
		print FD_WRITE "TOTALFILES $totalFiles\n";
		print FD_WRITE "FAILEDCOUNT $nonExistsCount\n";
		close(FD_WRITE);
		close NEWFILE;
		exit 0;
	} 
	waitpid($generateFilesPid,0);
	if(-e $info_file and ($totalFiles == 0 or $totalFiles !~ /\d+/)) {
		my $fileCountCmd = "cat '$info_file' | grep \"^TOTALFILES\"";
		$totalFiles = `$fileCountCmd`; 
		$totalFiles =~ s/TOTALFILES//;
	}	
	
	if($totalFiles == 0 or $totalFiles !~ /\d+/){
		traceLog(" Unable to get total files count \n", __FILE__, __LINE__);
	}
	
	if($nonExistsCount == 0 and -e $info_file) {
		my $nonExistCheckCmd = "cat '$info_file' | grep \"^FAILEDCOUNT\"";
		$nonExistsCount = `$nonExistCheckCmd`; 
		$nonExistsCount =~ s/FAILEDCOUNT//;
	}

	my $evsCmd = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$backupUtfFile\'";
	$evsRunning = `$evsCmd`;
	@evsRunningArr = split("\n", $evsRunning);
	
	foreach(@evsRunningArr) {
		if($_ =~ /$evsCmd|grep/) {
			next;
		}
#		my @lines = split(/[\s\t]+/, $_);
#		my $pid = $lines[3];
		my $pid = (split(/[\s\t]+/, $_))[3];
		$scriptTerm = system("kill -9 $pid");
		
		if(defined($scriptTerm)) {
			if($scriptTerm != 0 && $scriptTerm ne "") {
				my $msg = Constants->CONST->{'KilFail'}." Backup\n";
				traceLog("$msg\n", __FILE__, __LINE__);
			}
		}
	}
	waitpid($pid_OutputProcess, 0);
	exit_cleanup($errStr);
}

#****************************************************************************************************
# Subroutine Name         : loadFullExclude.
# Objective               : This function will load FullExcludePaths to FullExcludeHash.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub loadFullExclude {
	my @excludeArray;
	#read full path exclude file and prepare a hash for it
	if(-e $excludeFullPath and 0 < -s $excludeFullPath) {
		if(!open(EXFH, $excludeFullPath)){
			$errStr = Constants->CONST->{'ExclFileOpnErr'}." $excludeFullPath. Reason:$!";
			print $errStr;
			traceLog("$errStr\n", __FILE__, __LINE__);
			return;
		}
		
		@excludeArray = grep { !/^\s*$/ } <EXFH>;
		close EXFH;
	}
	
	push @excludeArray, $currentDir;
	push @excludeArray, $idriveServicePath;
	push @excludeArray, $IDriveLocal;
	my @qFullExArr; # What is the use of this variable.
	chomp @excludeArray;

	for (my $i=0; $i<=$#excludeArray; $i++) {
		if(substr($excludeArray[$i], -1, 1) eq "/") {
			chop($excludeArray[$i]);
		}
		$backupExcludeHash{$excludeArray[$i]} = 1;
		$qFullExArr[$i] = "^".quotemeta($excludeArray[$i]).'\/';
	}
	$fullStr = join("\n", @qFullExArr);  
	chomp($fullStr);
	$fullStr =~ s/\n/|/g;#First we join with '\n' and then replacing with '|'?		
}

#****************************************************************************************************
# Subroutine Name         : loadPartialExclude.
# Objective               : This function will load Partial Exclude string from PartialExclude File.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub loadPartialExclude {
	my @excludeParArray;
	#read partial path exclude file and prepare a partial match pattern 
	if(-e $excludePartialPath and 0 < -s $excludePartialPath) {
		if(!open(EPF, $excludePartialPath)){
			$errStr = Constants->CONST->{'ExclFileOpnErr'}." $excludePartialPath. Reason:$!";
			print $errStr;
			traceLog("$errStr\n", __FILE__, __LINE__);
			return;
		}
		
		@excludeParArray = grep { !/^\s*$/ } <EPF>;
		close EPF;
		
		my @qParExArr;
		chomp(@excludeParArray);
		for(my $i = 0; $i <= $#excludeParArray; $i++) {
			$excludeParArray[$i] =~ s/[\s\t]+$//;
			$qParExArr[$i] = quotemeta($excludeParArray[$i]);
		}

		$parStr = join("\n", @qParExArr);  
		chomp($parStr);
		$parStr =~ s/\n/|/g;
	}
}

#****************************************************************************************************
# Subroutine Name         : loadRegexExclude.
# Objective               : This function will load Regular Expression Exclude string from RegexExlude File.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub loadRegexExclude {
	#read regex path exclude file and find a regex match pattern 
	if(-e $regexExcludePath and -s $regexExcludePath > 0) {
		if(!open(RPF, $regexExcludePath)) {
			$errStr = Constants->CONST->{'ExclFileOpnErr'}." $regexExcludePath. Reason:$!";
			print $errStr;
			traceLog("$errStr\n", __FILE__, __LINE__);
			return;
		}
		
		my @tmp;
		@excludeRegexArray = grep { !/^\s*$/ } <RPF>;
		close RPF;
	
		if(!scalar(@excludeRegexArray)) {
			$regexStr = undef;
		} else {
			foreach(@excludeRegexArray) {
				my $a = $_;
				chomp($a);
				$b = eval { qr/$a/ };
				if ($@) {
					print OUTFILE " Invalid regex: $a";
					traceLog("Invalid regex: $a\n", __FILE__, __LINE__);
				} elsif($a) {
					push @tmp, $a;
				}
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
#*****************************************************************************************************/
sub exit_cleanup {
	if($silentBackupFlag == 0){
		system('stty', 'echo');
		system("tput sgr0");
	}
	my $displayJobFailMessage = undef;
	$successFiles = getParameterValueFromStatusFile('COUNT_FILES_INDEX');
	$syncedFiles = getParameterValueFromStatusFile('SYNC_COUNT_FILES_INDEX');
	$failedFilesCount = getParameterValueFromStatusFile('ERROR_COUNT_FILES');
	$exit_flag = getParameterValueFromStatusFile('EXIT_FLAG_INDEX');
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
		traceLog(" exit = $exit[0] and $exit[1] \n", __FILE__, __LINE__);
		if(!$exit[0]){
			if($flagToCheckSchdule == 1){
#				$errStr = "Operation could not be completed. Reason : Operation Cancelled due to Cut off.";
				$errStr = Constants->CONST->{'operationFailCutoff'};				
				my $checkJobTerminationMode = $jobRunningDir.'/cancel.txt';
				if (-e $checkJobTerminationMode and (-s $checkJobTerminationMode > 0)){
				        open (FH, "<$checkJobTerminationMode") or die $!;
				        my @errStr = <FH>;
				        chomp(@errStr);
				        $errStr = $errStr[0] if (defined $errStr[0]);
				}
				unlink($checkJobTerminationMode);
			}
			elsif($flagToCheckSchdule == 0) {
#				$errStr = "Operation could not be completed, Reason: Operation Cancelled by User.";	
				$errStr = Constants->CONST->{'operationFailUser'};					
			}
		}else{
			if($exit[1] ne ""){
				$errStr = $exit[1];
#Below section has been added to provide user friendly message and clear instruction in case of password mismatch or encryption verification failed. In this case we are removing the IDPWD file.So that user can login and recreate these files with valid credential.		
				if ($errStr =~ /password mismatch|encryption verification failed/i){
                    $errStr = $errStr.' '.Constants->CONST->{loginAccount}.$lineFeed;
					unlink($pwdPath);
					if($taskType == "Scheduled"){
						$pwdPath =~ s/_SCH$//g;
						unlink($pwdPath);
					}
                } elsif($errStr =~ /failed to get the device information|Invalid device id/i){
                    $errStr = $errStr.' '.Constants->CONST->{backupLocationConfigAgain}.$lineFeed;
				}				
			}
		}
	}
	unlink($pidPath);
	writeOperationSummary(Constants->CONST->{'BackupOp'});
	unlink($idevsOutputFile);
	unlink($idevsErrorFile);
	unlink($backupUtfFile); 
	unlink($statusFilePath);
	unlink($retryinfo);
	unlink($fileForSize);
	unlink($incSize);
	unlink($trfSizeAndCountFile);
	restoreBackupsetFileConfiguration();
	
	if(-d $evsTempDirPath) {
		rmtree($evsTempDirPath);
	}
	
	if(-d $errorDir) {
		rmtree($errorDir); 
	}
	my $subjectLine = getOpStatusNeSubLine();
	if (-e $outputFilePath and -s $outputFilePath > 0){
		my $finalOutFile = $outputFilePath."_".$status;
		move($outputFilePath, $finalOutFile);
		$outputFilePath = $finalOutFile;
		$finalSummery .= Constants->CONST->{moreDetailsReferLog}.qq(\n"$finalOutFile"); #Concat log file path with job summary. To access both at once while displaying the summery and log file location.
		$finalSummery .= "\n".$status."\n".$errStr;
		writeToFile("$jobRunningDir/".Constants->CONST->{'fileDisplaySummary'},$finalSummery) if ($silentBackupFlag == 0);#It is a generic function used to write content to file.
		displayFinalSummary('Backup Job',"$jobRunningDir/".Constants->CONST->{'fileDisplaySummary'})  if ($taskType eq "Manual" and $silentBackupFlag == 0);
		#Above function display summary on stdout once backup job has completed.
	}
	sendMail($subjectLine);
	appendEndProcessInProgressFile();
	terminateStatusRetrievalScript("$jobRunningDir/".Constants->CONST->{'fileDisplaySummary'}) if ($taskType eq "Scheduled");
	unlink($progressDetailsFilePath);
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
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. reason: Full path excluded item.$lineFeed";
		$excludedCount++;
		$returnvalue = 1;
	} elsif($parStr ne "" and $element =~ m/$parStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. reason: Partial path excluded item.$lineFeed";
		$excludedCount++;
		$returnvalue = 1;
	} elsif($regexStr ne "" and $element =~ m/$regexStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. reason: Regex path excluded item.$lineFeed";
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
			traceLog("\n in NORELATIVE BackupsetFile_new = $BackupsetFile_new and BackupsetFileTmp = $BackupsetFileTmp", __FILE__, __LINE__);
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
			print $tHandle Constants->CONST->{'FileOpnErr'}."BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!. $lineFeed";
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
# Modified By             : Deepak Chaurasia
#*****************************************************************************************************/
sub doBackupOperation()
{ 
	my $parameters = $_[0];
	#@parameter_list = split / /,$parameters,3;
	@parameter_list = split /\' \'/,$parameters,3;
	$backupUtfFile = getOperationFile(Constants->CONST->{'LocalBackupOp'}, $parameter_list[2] ,$parameter_list[1] ,$parameter_list[0]);

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
	
	$backupPid = fork();
	if(!defined $backupPid) {
		$errStr = Constants->CONST->{'ForkErr'}.$whiteSpace.Constants->CONST->{"EvsChild"}.$lineFeed;
		return BACKUP_PID_FAIL;
	}
	
	if($backupPid == 0) {
		if( -e $pidPath) {
			exec($idevsutilCommandLine);
			$errStr = Constants->CONST->{'DoRstOpErr'}.Constants->CONST->{'ChldFailMsg'};
			print $errStr;
			traceLog("$errStr", __FILE__, __LINE__);
			
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
		exit 1;
	}
	
	$pid_OutputProcess = fork();
	if(!defined $pid_OutputProcess)
	{
		$errStr = Constants->CONST->{'ForkErr'}.$whiteSpace.Constants->CONST->{"LogChild"}.$lineFeed;
		return OUTPUT_PID_FAIL;
	}
	
	if($pid_OutputProcess == 0) {
		if( !-e $pidPath) {
			exit 1;
		}
		
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
		$fileChildProcessPath = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
#		$ENV{'OPERATION_PARAM'}=join('::',($tmp_jobRunningDir,$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$curLines,$progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$errorDevNull));
		my @param = join ("\n",('LOCAL_BACKUP_OPERATION',$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$curLines,$progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType));
		writeParamToFile("$tmp_jobRunningDir/operationsfile.txt",@param);
		traceLog("cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\'");
		exec("cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\'");		
		$errStr = Constants->CONST->{'bckProcessFailureMsg'};
		
		if(open(ERRORFILE, ">> $errorFilePath")) {
			autoflush ERRORFILE;
			print ERRORFILE $errStr;
			close ERRORFILE;
			chmod $filePermission, $errorFilePath;
		}
		else {
			traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace.$errorFilePath."1 Reason :$! $lineFeed", __FILE__, __LINE__);
		}		
		
		exit 1;
	}
	waitpid($backupPid,0);
	updateServerAddr();
	
	if(open OFH, ">>", $idevsOutputFile) {
		print OFH "CHILD_PROCESS_COMPLETED\n";
		close OFH;
		chmod $filePermission, $idevsOutputFile;
	}
	else {
		print Constants->CONST->{'FileOpnErr'}." $outputFilePath. Reason: $!";
		traceLog(Constants->CONST->{'FileOpnErr'}." outputFilePath in doBackupOperation: $outputFilePath. Reason: $!", __FILE__, __LINE__);
		return 0;
	}
	
	waitpid($pid_OutputProcess, 0);
	unlink($parameter_list[2]);
	unlink($idevsOutputFile);
	
	if(-e $errorFilePath && -s $errorFilePath) {
		return 0;
	}
	
	return BACKUP_SUCCESS;
}

#******************************************************************************************************************
# Subroutine Name         : getOpStatusNeSubLine.
# Objective               : This subroutine returns backup operation status and email subject line
# Added By                : Dhritikana
#******************************************************************************************************************/
sub getOpStatusNeSubLine()
{
	my $subjectLine= "";
	my $totalNumFiles = $filesConsideredCount-$failedFilesCount;
	if($cancelFlag){
		$status = "ABORTED";
		$subjectLine = "$taskType Backup Email Notification "."[$userName]"." [Aborted Backup]";
	}
#	elsif($filesConsideredCount == 0){
#		$status = "FAILURE";
#		$subjectLine = "$taskType Backup Email Notification "."[$userName]"." [Failed Backup]";
#	}
	elsif($failedFilesCount == 0 and $filesConsideredCount > 0)
	{
		$status = "SUCCESS";
		$subjectLine = "$taskType Backup Email Notification "."[$userName]"." [Successful Backup]";
	}
	else {
#		if(($failedFilesCount/$filesConsideredCount)*100 <= 5){				  
#			$status = "SUCCESS*";
#			$subjectLine = "$taskType Backup Email Notification "."[$userName]"." [Successful* Backup]";
#		}
#		else {
			$status = "FAILURE";
			$subjectLine = "$taskType Backup Email Notification "."[$userName]"." [Failed Backup]";
#		}
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
		unlink <$relativeFileset*>;
	}
	if($noRelativeFileset ne "") {
		unlink <$noRelativeFileset*>;
	}
	if($filesOnly ne "") {	
		unlink <$filesOnly*>;
	}
	if($failedfiles ne "") {
		unlink <$failedfiles*>;
	}
	unlink $info_file;
}

#*******************************************************************************************************
# Subroutine Name         :	updateServerAddr
# Objective               :	handling wrong server address error msg	
# Added By                : Dhritikana
#********************************************************************************************************
sub updateServerAddr {
	my $tempErrorFileSize = -s $idevsErrorFile;
	if($tempErrorFileSize > 0) {
		my $errorPatternServerAddr = "unauthorized user";
		open EVSERROR, "<", $idevsErrorFile or traceLog("\n Failed to open error.txt\n", __FILE__, __LINE__);
		$errorContent = <EVSERROR>;
		close EVSERROR;
		
		if($errorContent =~ m/$errorPatternServerAddr/){
			if(!(getServerAddr())){
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
# Modified By             : Dhritikana
#********************************************************************************************************/
sub updateRetryCount()
{
	my $curFailedCount = 0;
	my $currentTime = time();

	$curFailedCount = getParameterValueFromStatusFile('ERROR_COUNT_FILES');
	
	if($prevFailedCount == 0 or $curFailedCount < $prevFailedCount) {
		$retrycount = 0;
	}
	else {
		if($currentTime-$prevTime < 120) {
			sleep 300;
		}
		$retrycount++;
	}
	
	#assign the latest backedup and synced value to prev.
	$prevFailedCount = $curFailedCount;
	$prevTime = $currentTime;
}

#*********************************************************************************************************
#Subroutine Name        : getMountedPath 
#Objective              : This function will return mounted devices list
#Added By               : Senthil Pandian.
#*********************************************************************************************************/
sub getMountedPath
{
	our @linkDataList = ();
	my @mountedPath  = ();
	my @mountedPathPermission = ();
	my @fullPathSystemMountPoints = ('/','/dev','/boot','/home','/run','/tmp','/.snapshots','/srv','/opt');
	my @partPathSystemMountPoints = ('/boot/','/dev/','/sys/','/usr/','/var/','/opt/');
	
	my $cmd = "df -k | grep -v Filesystem";
	my $res = `$cmd`;
	
	if($res ne ''){
		@resData = split("\n", $res);	
		foreach(@resData) {
			my @mountArray = (split(/[\s\t]+/, $_,6));
			my $path = $mountArray[5];
			my $volumeSize = $mountArray[1]; #size in KB; 512000=500M
			#if(!-e $path."/System Volume Information/IndexerVolumeGuid" or $path eq '/'){
			#	next;
			#}
			my @matches = grep { /^$path$/ } @fullPathSystemMountPoints;
			if(scalar(@matches)>0 or $volumeSize<512000){
				next;
			}
			my $matched = 0;
			foreach(@partPathSystemMountPoints) {
				my $element = $_;
				if($path =~ /$element/){
					$matched = 1;
					last;			
				}		
			}
			if($matched == 1){ 
				next; 
			}		
			
			if(-w $path){
				$permissionMode = 'Writeable';
			} elsif(-r $path){
				$permissionMode = 'Read-only';
			} else {
				$permissionMode = 'No access';			
			}
			push (@mountedPath,$path);
			push (@mountedPathPermission,$permissionMode);			
		}
	}
	
	print $lineFeed.$lineFeed.Constants->CONST->{'LoadingMountPoints'}.$lineFeed.$lineFeed;
	if(scalar(@mountedPath)>0){
		print Constants->CONST->{'selectMountPoint'}.$lineFeed;
		my @mountPointcolumnNames = (['S.No','Mount Point','Permissions'],[8,30,15]);
		my $tableHeader = getTableHeader(@mountPointcolumnNames);
		my ($tableData,$columnIndex,$serialNumber,$index) = ('',1,1,0);
		
		foreach (@mountedPath){
			$columnIndex = 1;
			
			my $mountDevicePath     = $_;
			my $mountDevicePathPerm = $mountedPathPermission[$index];
			$index++;
			$tableData .= $serialNumber;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[0] - length($serialNumber));
	
			$mountDevicePath = trimData($mountDevicePath,$mountPointcolumnNames[1]->[$columnIndex]) if($columnIndex == 1 or $columnIndex == 3);
			$tableData .= $mountDevicePath;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[$columnIndex] - length($mountDevicePath));
			$tableData .= $mountDevicePathPerm;
			$columnIndex++;
			$tableData .= $lineFeed;
			$serialNumber += 1;
			push (@linkDataList,$_);
		}
		if ($tableData ne ''){
			print $tableHeader.$tableData;
		}		
	} else {
		print Constants->CONST->{'UnableToFindMountPoint'};
		#print 'Please check whether the external disk mounted properly or not.'.$lineFeed;
	}
	
	if(scalar(@linkDataList)>0){
		my $retryCount = 4;
		my $userChoice = getUserMenuChoice(scalar(@linkDataList),$retryCount,'Enter the S.No. to select mount point [Note: press \'q\' in case your mount point is not listed above]:','mount');
		if($userChoice eq 'q' or $userChoice eq 'Q'){
			@linkDataList = ();
		} elsif($userChoice ne '') {
			$localBackupLocationPath = $userChoice;			
		}
	}
	if(scalar(@linkDataList)<=0){
		if(-e $mountPointFilePath and -s $mountPointFilePath>0){
			if(!open(FD_READ, "<", $mountPointFilePath)) {
				my $openErrStr = Constants->CONST->{'FileOpnErr'}." $mountPointFilePath to read, Reason:$!";
				traceLog($openErrStr, __FILE__, __LINE__);
			}
			$localBackupLocationPath = <FD_READ>;			
			close FD_READ;
			chomp($localBackupLocationPath);
			if(!-d $localBackupLocationPath or !-w $localBackupLocationPath){
				$localBackupLocationPath ='';
			}
		}
		if($localBackupLocationPath){
			my $mountPointQuery = Constants->CONST->{'YourPreviousMountPoint'}->($localBackupLocationPath);
			$choice = $userInput;		
			unless (defined ($userInput)){
				print $mountPointQuery;
				$choice = getConfirmationChoice();
			}
			if($choice eq 'n' or $choice eq 'N'){
				goto USEEXISTING;
			}	
			
		} else {
			my $mountPointQuery = Constants->CONST->{'doUwant2EnterMountPoint'};
			$choice = $userInput;		
			unless (defined ($userInput)){
				print $mountPointQuery;
				$choice = getConfirmationChoice();
			}
			
			if($choice eq 'n' or $choice eq 'N'){
				print $lineFeed.Constants->CONST->{'Exit'}.$lineFeed;
				cancelProcess();
			}
		}
		while ($maxNumRetryAttempts){
			print $lineFeed.Constants->CONST->{'EnterMountPoint'};
			$localBackupLocationPath = <STDIN>;
			Chomp(\$localBackupLocationPath);chomp($localBackupLocationPath);
			if(!-e "$localBackupLocationPath"){
				print Constants->CONST->{'mountPointNotExist'}.$lineFeed;
			} 
			elsif(!-w "$localBackupLocationPath") {
				print Constants->CONST->{'mountPointDoesntPermission'}.$lineFeed;
			} 
			else {
				my $tempLoc = $localBackupLocationPath;
				$tempLoc =~ s/^[\/]+|^[.]+//;
				if(!$tempLoc) {
					print Constants->CONST->{'InvalidMountPoint'}.$lineFeed;
				} else {
					last;
				}
			}
			$maxNumRetryAttempts -= 1;
		}
		if ($maxNumRetryAttempts == 0){
			print Constants->CONST->{'maxRetry'}.$lineFeed.$lineFeed;
			cancelProcess();
		}
	}
	print Constants->CONST->{'YouSelectedBkpLoc'}->($localBackupLocationPath).$lineFeed;
	if($localBackupLocationPath =~ /[\/]$/){
		chop($localBackupLocationPath);
	}
	
	if(open(MOUNTPOINT, ">",$mountPointFilePath)){
		print MOUNTPOINT $localBackupLocationPath;
		close MOUNTPOINT;
		chmod $filePermission, $mountPointFilePath;
	} else {
		my $openErrStr = Constants->CONST->{'FileOpnErr'}." : $mountPointFilePath, Reason $!".$lineFeed;
		traceLog($openErrStr, __FILE__, __LINE__);
	}
USEEXISTING:	
	return $localBackupLocationPath;
}

#*********************************************************************************************************
#Subroutine Name        : createLocalBackupDir 
#Objective              : This function will create the directories for local backup.
#Added By               : Senthil Pandian.
#*********************************************************************************************************/
sub createLocalBackupDir{
	if(!-d $IDriveLocal) {
		if(!mkdir($IDriveLocal)){
			print "Unable to create directory: $IDriveLocal. Reason:$!".$lineFeed;
			cancelProcess();
		}
		chmod $filePermission, $IDriveLocal;
	}
	if(!-d $localUserPath) {
		if(!mkdir($localUserPath)){
			print "Unable to create directory: $localUserPath. Reason:$!".$lineFeed;
			cancelProcess();
		}
		chmod $filePermission, $localUserPath;
	}
	
	if($dedup eq 'on'){
		$backupLocationDir  = "$localUserPath/$serverRoot";
	} else {
		$backupLocationDir  = "$localUserPath$backupHost";
	}
	
	if(!-d $backupLocationDir) {
		mkdir($backupLocationDir);
		chmod $filePermission, $backupLocationDir;
	}	
}

#****************************************************************************************************
# Subroutine Name         : createDBPathsXmlFile.
# Objective               : Creating DB paths XML file
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub createDBPathsXmlFile
{
	$xmlFile = $localUserPath."/dbpaths.xml";
	if ($dedup eq 'off'){
		return;
	}
	if($backupHost and $backupDeviceID){
		($actualDeviceID,$nickName) = ($backupDeviceID,$backupHost);		
		$actualDeviceID =~ s/$deviceIdPostfix//;
		$actualDeviceID =~ s/$deviceIdPrefix//;
	} else {
		print Constants->CONST->{'serverRootNotFound'}.$lineFeed.$lineFeed;
		exit;
	}
	
	$dbPath = "/LDBNEW/$serverRoot/$userName.ibenc";
	if(-e $xmlFile and  -s $xmlFile>0){
		open my $fh, '<', $xmlFile;
		read $fh, my $oldXmlContent, -s $fh;
		close $fh;
		$xmlContent = '';
		
		if($oldXmlContent =~ /<dbpaths>/i){
			my @xmlArray = split("\n",$oldXmlContent);
			if(scalar(@xmlArray)>0){
				$find = "serverroot=\"$serverRoot\"";
				$isUpdated = 0;
				foreach(@xmlArray){
					$row = $_;
					if($row =~ /<dbpathinfo/i and $row =~ /$find/i){
						$row = '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />';
						$isUpdated = 1;
					}					
					if($row =~ /<\/dbpaths>/i){
						last;
					}
					$xmlContent .= $row.$lineFeed;
				}
				if($isUpdated == 0){
					$row = '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />';
					$xmlContent .= $row.$lineFeed;
				}
				$xmlContent .= '</dbpaths>'.$lineFeed;
			}
		}
	} else {
		$xmlContent  = '<?xml version="1.0" encoding="utf-8"?>'.$lineFeed;
		$xmlContent .= '<dbpaths>'.$lineFeed;
		$xmlContent .= '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />'.$lineFeed;
		$xmlContent .= '</dbpaths>'.$lineFeed;
	}	
	open XMLFILE, ">", $xmlFile or (print "Unable to create file: $xmlFile, Reason:$!" and die);
	print XMLFILE $xmlContent;
	close XMLFILE;
	chmod $filePermission, $xmlFile;
}