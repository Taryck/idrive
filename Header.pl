#!/usr/bin/perl

###############################################################################
#Script Name : Header.pl
###############################################################################

use Cwd;
use Tie::File;
use File::Copy;
use File::Basename;
use File::Path;
use IO::Handle;
#use Fcntl;
use POSIX;
use Fcntl qw(:flock);
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
#use Constants 'CONST';
require Constants;
our $userScriptLocation  = findUserLocation();
our $logger;
our $logoutFlag = 0;
our $lineFeed = "\n";
our $proxyStr =  "";
#our $currentDir = getcwd;
our $currentDir = $userScriptLocation;
our $userName = undef;
our ( $proxyOn, $proxyIp, $proxyPort, $proxyUsername, $proxyPassword) = undef;
our $httpuser = `whoami`;
our ($appTypeSupport,$appType) = getAppType();
our $appMaintainer = getAppMaintainer();

chomp($httpuser);
#######################################################################
# APP_TYPE_SUPPORT should be ibackup for ibackup and idrive for idrive#
# APP_TYPE should be IBackup for ibackup and IDrive for idrive        #
#######################################################################
#use constant APP_TYPE_SUPPORT => "idrive";
#use constant APPTYPE => "IDrive";

#Configuration File Path#
our $confFilePath = "";

#Array containing the lines read from Configuration File#
my @linesConfFile = ();

###############################
#Hash to hold the values of   #
#Configuration File Parameters#
###############################
my %hashParameters = (
                       "USERNAME" => undef,
                       "PROXY" => undef,
                       "LOGDIR" => undef,
#                       "PVTKEY" => undef,
                       "NOTIFICATIONFLAG" => undef,
                       "EMAILADDRESS" => undef,
				       "BACKUPLOCATION" => undef,
				       "RETAINLOGS" => undef,
				       "BWTHROTTLE" => undef,                             
                       "RESTORELOCATION" => undef,
	    		       "RESTOREFROM" => undef,				
						"TBE_BASE_DIR" => undef,			# TBE : ENH-002 Add new param : Root Directory for relative backup
	    		       "BACKUPPATHTYPE" => undef   
                     );

##################################
#Operation Type                  #
##################################

our $backupOp = 'Backup';
our $restoreOp = 'Restore';
our $validateOp = 3;
our $getServerAddressOp = 4;
our $authListOp = 5;
our $configOp = 6;
our $getQuotaOp = 7;
our $propertiesOp = 8;
our $speedOp = 9;
our $createDirOp = 10;
our $searchOp = 11;
our $renameOp = 12;
our $itemStatOp = 13;
our $versionOp = 14;
our $verifyPvtOp = 15;
our $perlPath = "";
our $psPath = "";
our $pidIdx = "";
our $cronSeparator = "";
our $whiteSpace = " ";
our $assignmentOperator = "=";
our $fileOpenStatus = 0;
our $idevsutilArgument = "--utf8-cmd";
our $filePermission = 0777;
my $encTypeDir = "";

our $userCancelStr = Constants->CONST->{'OpUsrCancel'};
our @invalidCharsDirName = ("/",">","<","|",":","&"); #Array containing the characters which should not be present in a Directory name#

our $periodOperator = ".";
our $pathSeparator = "/";
our $serverAddressOperator = "@";
our $serverNameOperator = "::";
our $operationComplete = "100";
our $errorRedirection = "2>&1";
our $errorDevNull = '2>/dev/null';
our $serverName = "home";
our $progressDetailsFilePath = undef;
our $failedFileName = "failedfiles.txt";
our $retryinfo = "RetryInfo.txt";
our $nonExistsCount = 0;
our $curLines = 0;
our $cols = 0;

#Path change required 
our $pidPath = undef;
our $statusFilePath = undef;
our $idevsOutputFile = "output.txt";
our $idevsErrorFile = "error.txt";
#our $temp_file = undef;
our $evsTempDirPath = undef;
our $evsTempDir = "/tmp";
our $errorDir = undef;
our $jobRunningDir = undef;
our $notifyPath = undef;
our $data = undef;
#-------------------------------------------------

our $fileCountThreadStatus;
our $summary = undef;
our $finalSummery = undef; #This variable content will be shown on the terminal whenever jobs get completed,accidently/abrouptly terminated. 
our $summaryError = undef;
our $errStr = undef;
our $location = undef;
our $jobType = undef;
our $mail_content = undef;
our $mail_content_head = undef;
our %evsHashOutput = undef;
our $initCulmn = undef;
our $progressSizeOp = undef;

#*************************************************
our $serverAddress = undef;
our $mkDirFlag = undef;
our @linesStatusFile = undef;
our $outputFilePath = undef;
our $errorFilePath = undef;
our $taskType = undef;
our $status = undef;
our %statusHash = 	(	"COUNT_FILES_INDEX" => undef,
						"SYNC_COUNT_FILES_INDEX" => undef,
						"ERROR_COUNT_FILES" => undef,
						"FAILEDFILES_LISTIDX" => undef,
						"EXIT_FLAG" => undef,
					);

our $totalFiles = 0;
our $filesConsideredCount = undef;
our $successFiles = 0; #Count of files which have been backed up#
our $syncedFiles = 0; #Count of files which are in sync#
our $failedFilesCount = 0; #Total count of files which could not be backed up/synced #

use constant false => 0;
use constant true => 1;
use constant FILE_COUNT_THREAD_STARTED => 1;
use constant FILE_COUNT_THREAD_COMPLETED => 2;

use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";

use constant FULLSUCCESS => 1;
use constant PARTIALSUCCESS => 2;

#######################################################################
#Hash to hold the values of arguments to be passed to idevsutil binary#
#######################################################################
my %hashEvsParameters = ( 
			"SERVERADDRESS" => "--getServerAddress",
			"USERNAME" => "--user",
			"PASSWORD" => "--password-file",                       
			"ENCTYPE" => "--enc-type",
			"PVTKEY" => "--pvt-key",                       
			"VALIDATE" => "--validate",
			"CONFIG" => "--config-account",
			"PROXY" => "--proxy",
			"UTF8CMD" => "--utf8-cmd",
			"ENCODE" => "--encode",
			"FROMFILE" => "--files-from",
			"TYPE" => "--type",
			"BWFILE" => "--bw-file",
			"PROPERTIES" => "--properties",
			"XMLOUTPUT" => "--xml-output",
			"GETQUOTA" => "--get-quota",
			"AUTHLIST" => "--auth-list",
			"SPEED" => "--trf-",
			"OUTPUT" => "--o",
			"ERROR" => "--e",
			"PROGRESS" => "--100percent-progress",
			"QUOTAFROMFILE" => "--quota-fromfile",
			"CREATEDIR" => "--create-dir",
			"SEARCH" => "--search",
			"VERSION" => "--version-info",
			"RENAME" => "--rename",
			"OLDPATH" => "--old-path",
			"NEWPATH" => "--new-path",
			"FILE" => "--file",
			"ITEMSTATUS" => "--items-status",
			"ADDPROGRESS" => "--add-progress",
			"TEMP"		=> "--temp",
			"DEFAULTKEY"	=> "--default-key",
);

#Errors encountered during backup operation# 
#for which the script should retry the     #
#backup operation                          #
our @ErrorArgumentsRetry = ("idevs error",
                           "io timeout",
                           "Operation timed out",
                           "nodename nor servname provided, or not known",
                           "failed to connect",
                           "Connection refused",
                           "unauthorized user",
                           "connection unexpectedly closed",
                           "failed verification -- update",
                          );
                          
# Errors encountered during backup operation for which the script should not retry the backup operation                         
our @ErrorArgumentsNoRetry = ("No such file or directory",
                             "file name too long",
							 "skipping non-regular file",
							 "Permission Denied",
							 "SFERROR",
                             "IOERROR",
                             "mkstemp"
							);	

# Errors encountered during backup operation for which the script should not retry the backup operation                         
our @ErrorArgumentsExit = (  "encryption verification failed",
                             "some files could not be transferred due to quota over limit",
                             "skipped-over limit",
                             "quota over limit",
                             "account is under maintenance",
                             "account has been cancelled",
                             "account has been expired",
                             "protocol version mismatch",
                             "password mismatch",
                             "out of memory"
                            );
our $relative = 1;
our $defaultBw = undef;
our $defaultEncryptionKey = "DEFAULT";
our $privateEncryptionKey = "PRIVATE";
#----------------Get user service path from .serviceLocation directory-------#
my $userServicePath = '';
my $serviceFileLocation = qq{$userScriptLocation/}.Constants->CONST->{serviceLocation};
getServiceLocation();
#----------------------------------------------------------------------------#
our $percentageComplete = undef;
our $carriageReturn = "\r";
our $percent = "%";

my $indexLastDir = rindex($currentDir, "/");
our $parentDir = substr($currentDir, 0, $indexLastDir);
#our $idriveSerivePath = $userServicePath ne '' ? $userServicePath : getAbsolutePath(split('/',"$userScriptLocation/../$appTypeSupport"));
our $idriveSerivePath = $userServicePath;
our $usrProfilePath = "$idriveSerivePath/user_profile";
our $cacheDir = "$idriveSerivePath/cache";
our $userTxt = "$cacheDir/user.txt";

our $idevsutilBinaryName = "idevsutil";#Name of idevsutil binary#
our $idevsutilBinaryPath = "$idriveSerivePath/idevsutil";#Path of idevsutil binary#
our $idevsutilCommandLine = undef;
our $displayCurrentUser = getCurrentUser();
                   
#*******************************************************************************************************
#Global variables for Downloadable Binary Links

if($appType eq "IDrive") {
	our $EvsBin32 = "www.idrive.com/downloads/linux/download-for-linux/idevsutil_linux.zip";
	our $EvsBin64 = "www.idrive.com/downloads/linux/download-for-linux/idevsutil_linux64.zip";
	our $EvsQnapBin32_64 = "https://www.idrive.com/downloads/linux/download-options/QNAP_Intel_Atom_64_bit.zip";
	our $EvsSynoBin32_64 = "https://www.idrive.com/downloads/linux/download-options/synology_64bit.zip";
	our $EvsNetgBin32_64 = "https://www.idrive.com/downloads/linux/download-options/Netgear_64bit.zip";
	our $EvsUnvBin	= "https://www.idrive.com/downloads/linux/download-for-linux/idevsutil_linux_universal.zip";
	our $EvsQnapArmBin = "https://www.idrive.com/downloads/linux/download-options/QNAP_ARM.zip";
	our $EvsSynoArmBin = "https://www.idrive.com/downloads/linux/download-options/synology_ARM.zip";
	our $EvsNetgArmBin = "https://www.idrive.com/downloads/linux/download-options/Netgear_ARM.zip";
} elsif($appType eq "IBackup") {
	our $EvsBin32 = "www.ibackup.com/online-backup-linux/downloads/download-for-linux/idevsutil_linux.zip";
	our $EvsBin64 = "www.ibackup.com/online-backup-linux/downloads/download-for-linux/idevsutil_linux64.zip";
	our $EvsSynoArmBin = "https://www.ibackup.com/online-backup-linux/downloads/download-options/synology_ARM.zip";
	our $EvsSynoBin32_64 = "https://www.ibackup.com/online-backup-linux/downloads/download-options/synology_64bit";
	our $EvsQnapArmBin = "https://www.ibackup.com/online-backup-linux/downloads/download-options/QNAP_ARM.zip";
	our $EvsQnapBin32_64 = "https://www.ibackup.com/online-backup-linux/downloads/download-options/QNAP_Intel_Atom_64_bit.zip";
	our $EvsNetgArmBin = "https://www.ibackup.com/online-backup-linux/downloads/download-options/Netgear_ARM.zip";
	our $EvsNetgBin32_64 = "https://www.ibackup.com/online-backup-linux/downloads/download-options/Netgear_64bit.zip";
	our $EvsUnvBin = "https://www.ibackup.com/online-backup-linux/downloads/download-for-linux/idevsutil_linux_universal.zip";
	#Solaris: https://www.ibackup.com/online-backup-linux/downloads/download-options/idevsutil_SOLARIS_x86.zip
}

#CGI Links to verify Account:set number
#
#our $IDriveAccVrfLink = "https://www1.idrive.com/cgi-bin/get_idrive_evs_details_xml_ip.cgi?";
#our $IBackupAccVrfLink = "https://www1.ibackup.com/cgi-bin/get_ibwin_evs_details_xml_ip.cgi?";
#our $IDriveAccVrfLink = "https://www1.idrive.com/cgi-bin/get_idrive_evs_details_xml_ip.cgi?"; #old cgi url
our $IDriveAccVrfLink = qq(https://www1.idrive.com/cgi-bin/v1/user-details.cgi?);
our $IBackupAccVrfLink = "https://www1.ibackup.com/cgi-bin/get_ibwin_evs_details_xml_ip.cgi?";
#*******************************************************************************************************/

if(${ARGV[0]} eq "SCHEDULED") {
	if($ARGV[1] ne ""){
		$userName = $ARGV[1] ;
	}
}
else{
	$userName = getCurrentUser();
}
our $defRestoreLocation = qq($usrProfilePath/$userName/Restore_Data);
#********************************************************************************************************
# Subroutine Name         : loadUserData.
# Objective               : loading Path and creating files/folders based on username.
# Added By                : Dhritikana
#********************************************************************************************************/
sub loadUserData {
	$usrProfileDir = "$usrProfilePath/$userName";
#=====================================================================================================================
# TBE : ENH-002 set Root Directory for relative backup
# instead of having only last level of relative
# when this parameter is set the relative path starts from this point
# Read the additional Parameter
	our $backupBase_Dir = $hashParameters{TBE_BASE_DIR};
# check or add / at the end of BASE_DIR
	if(substr($backupBase_Dir, -1, 1) ne '/'){
		$backupBase_Dir .= '/';
	}
# TBE : ENH-002 set Root Directory for relative backup
#=====================================================================================================================
	if($proxyStr eq ""){
		$proxyStr = getProxy();
	}
	our $backupType = $hashParameters{BACKUPTYPE};	
	our $backupHost = $hashParameters{BACKUPLOCATION};
	$backupHost = checkLocationInput($backupHost);
	if($backupHost ne "" && substr($backupHost, 0, 1) ne "/") {
		$backupHost = "/".$backupHost;
	}
	$backupHost =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root 
	our $restoreHost = $hashParameters{RESTOREFROM};
	$restoreHost = checkLocationInput($restoreHost);
	if($restoreHost ne "" && substr($restoreHost, 0, 1) ne "/") {
		$restoreHost = "/".$restoreHost;
	}
	our $configEmailAddress = $hashParameters{EMAILADDRESS};
	our $bwThrottle = getThrottleVal(); 
	our $restoreLocation = $hashParameters{RESTORELOCATION};
	$restoreLocation = checkLocationInput($restoreLocation);
	#$restoreLocation =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root
	our $ifRetainLogs = $hashParameters{RETAINLOGS};
	our $backupPathType = $hashParameters{BACKUPTYPE};
	#our $currentDirforCmd = quotemeta($currentDir); # not used
	our $pwdPath = "$usrProfileDir/.userInfo/".Constants->CONST->{'IDPWD'};
	our $enPwdPath = "$usrProfileDir/.userInfo/".Constants->CONST->{'IDENPWD'};
	our $pvtPath = "$usrProfileDir/.userInfo/".Constants->CONST->{'IDPVT'};
	our $utf8File = "$usrProfileDir/.utf8File.txt";
	our $serverfile = "$usrProfileDir/.userInfo/".Constants->CONST->{'serverAddress'};
	our $bwPath = "$usrProfileDir/bw.txt";
	our $excludeFullPath =  "$usrProfileDir/FullExcludeList.txt";      
	our $excludePartialPath = "$usrProfileDir/PartialExcludeList.txt";
	our $regexExcludePath = "$usrProfileDir/RegexExcludeList.txt";
	our $backupsetFilePath = "$usrProfileDir/Backup/Manual/BackupsetFile.txt"; 
#	our $backupsetFileSoftPath = "$usrProfileDir/Manual_BackupsetFile.txt"; 
	our $RestoresetFile = "$usrProfileDir/Restore/Manual/RestoresetFile.txt"; 
#	our $RestoresetFileSoftPath = "$usrProfileDir/Manual_RestoresetFile.txt"; 
	our $backupsetSchFilePath = "$usrProfileDir/Backup/Scheduled/BackupsetFile.txt"; 
#	our $backupsetSchFileSoftPath = "$usrProfileDir/Scheduled_BackupsetFile.txt"; 
	our $RestoresetSchFile = "$usrProfileDir/Restore/Scheduled/RestoresetFile.txt"; 
#	our $RestoresetSchFileSoftPath = "$usrProfileDir/Scheduled_RestoresetFile.txt"; 
	chmod $filePermission, $usrProfilePath;

	if( -e $serverfile) {
		open FILE, "<", $serverfile or (traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}.$serverfile." , Reason:$! $lineFeed", __FILE__, __LINE__) and die);
		chomp($serverAddress = <FILE>);
#		chomp($serverAddress);
		close FILE;
	}
}

#********************************************************************************************************
# Subroutine Name         : addtionalErrorInfo.
# Objective               : Logs error info into temporay error text file which is displayed in Log page.
# Added By                : Basavaraj Bennur. [modified by dhriti]
#********************************************************************************************************/
sub addtionalErrorInfo()
{	
	my $TmpErrorFilePath = ${$_[0]};
	chmod $filePermission, $TmpErrorFilePath;
	
	if(!open(FHERR, ">>",$TmpErrorFilePath)){
		traceLog("Could not open file TmpErrorFilePath in additionalErrorInfo: $TmpErrorFilePath, Reason:$!\n", __FILE__, __LINE__);
		traceLog("${$_[1]}\n", __FILE__, __LINE__);
		return;
	}
	print FHERR "${$_[1]}\n";	
	close FHERR;
}

#****************************************************************************************************
# Subroutine Name         : createCache.
# Objective               : Create cache Folder and related files if not. 
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub createCache {
	if( !-d $cacheDir) {
		my $res = mkdir $cacheDir;
		if($res ne 1) {
			print Constants->CONST->{'MkDirErr'}.$cacheDir."$res $!".$lineFeed;
			traceLog(Constants->CONST->{'MkDirErr'}.$cacheDir."$res $!".$lineFeed, __FILE__, __LINE__);
			exit 1;
		}
		chmod $filePermission, $cacheDir;
	}
	
	unless( open USERFILE, ">", $userTxt ) {
		die " Unable to open $userTxt. Reason: $!\n";
		exit 1;
	}
	chmod $filePermission, $userTxt;
	print USERFILE $userName;
	close USERFILE; 
}

#****************************************************************************************************
# Subroutine Name         : getCurrentUser.
# Objective               : Get previous logged in username from user.txt. 
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub getCurrentUser {
	if(!-e $userTxt or !-f $userTxt){
		return;
	}

	unless( open USERFILE, "<", $userTxt ) {
		traceLog("Unable to open $userTxt\n", __FILE__, __LINE__);
		return;
	}
	my $PrevUser = <USERFILE>;
	chomp($PrevUser);
	close USERFILE;
	
	my $pwdPath = "$usrProfilePath/$PrevUser/.userInfo/".Constants->CONST->{'IDPWD'};
	if(-e $pwdPath) {
                return $PrevUser;
        }else{
		unlink ($userTxt);
	}
	return;
}

#****************************************************************************************************
# Subroutine Name         : checkLocationInput.
# Objective               : Checking if user give backup/restore location as root. 
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub checkLocationInput {
	my $input = $_[0];
	
	if($input eq "") {
		return $input;
	}

	$input =~ s/^\s+\/+|^\/+/\//g; ## Replacing starting "/"s with one "/"
	$input =~ s/^\s+//g; ## Removing Blank spaces
		
	if(length($input) <= 0) {
		print Constants->CONST->{'InvLocInput'}.$whiteSpace.${$_[0]}.$lineFeed;
		traceLog($whiteSpace.Constants->CONST->{'InvLocInput'}.$whiteSpace.${$_[0]}.$lineFeed, __FILE__, __LINE__);
		exit 1;
	} 
	return $input;
}

#****************************************************************************************************
# Subroutine Name         : checkEncType.
# Objective               : This function loads encType based on configuartion and user's actual profile.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub checkEncType {
	my $flagToCheckSchdule = $_[0];
	my $encKeyType = $defaultEncryptionKey;

	if(!$flagToCheckSchdule) {
		if(-e $pvtPath && (-s $pvtPath > 0)) {
			$encKeyType = $privateEncryptionKey;
		}
	}
	elsif($flagToCheckSchdule eq 1) {
		if(-e $pvtPath) {  
			$encKeyType = $privateEncryptionKey;
		} 
	}
	return $encKeyType;
}

#****************************************************************************************************
# Subroutine Name         : getThrottleVal.
# Objective               : Verify bandwidth throttle value from CONFIGURATION File 
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub getThrottleVal {
	my $bwVal = $hashParameters{BWTHROTTLE}; 
	if(defined $bwVal and $bwVal =~ m/^\d+$/ and 0 <= $bwVal and 100 > $bwVal) {
	} else {
		$defaultBw = 1;
		$bwVal = 100;
	}
	return $bwVal;
}

#****************************************************************************************************
# Subroutine Name         : verifyAndLoadServerAddr.
# Objective               : Verify if Server file exists and Get Server Address from server file 
#							and verify the IP. In case file doesn't exist excute getServeraddress.
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub verifyAndLoadServerAddr {
	my $fetchAddress = 0;
	if(!-e $serverfile) {
		#Excute Get Server Addr 
		if(!(getServerAddr())){
			return 0;
		}
		$fetchAddress = 1;
	}
	
	open FILE, "<", $serverfile or (traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}.$serverfile." , Reason:$! $lineFeed", __FILE__, __LINE__) and die);
	my $TmpserverAddress = <FILE>;
	chomp($TmpserverAddress);
	
	#verify if IP is valid
	if($TmpserverAddress =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ && ((0 <= $1 && $1 <= 255) && (0 <= $2 && $2 <= 255) && (0 <= $3 && $3 <= 255) && (0 <= $4 && $4 <= 255))) 
	{
		return $TmpserverAddress;
	} elsif(!$fetchAddress) 
	{
		if (!(getServerAddr())){
			return 0;
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : createUpdateBWFile.
# Objective               : Create or update bandwidth throttle value file(.bw.txt). 
# Added By                : Avinash Kumar.
# Modified By		    	: Dhritikana
#*****************************************************************************************************/
sub createUpdateBWFile()
{
	open BWFH, ">", $bwPath or (traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}.$bwPath." , Reason:$! $lineFeed", __FILE__, __LINE__) and die);
	chmod $filePermission, $bwPath;
	print BWFH $bwThrottle;
	close BWFH;
}

#****************************************************************************************************
# Subroutine Name         : getAppType.
# Objective               : Get application type like ibackup/IDrive. 
# Added By                : Avinash Kumar.
#*****************************************************************************************************/
sub getAppType
{
	$appType = "IDrive";
	$appTypeSupport = lc ($appType);
	return ($appTypeSupport,$appType);
}

#****************************************************************************************************
# Subroutine Name         : getAppMaintainer.
# Objective               : Get application Maintainer name based on product
# Added By                : Deepak Chaurasia
#*****************************************************************************************************/
sub getAppMaintainer
{
	$appMaintainer = Constants->CONST->{'IDriveMaintainer'};
	$appMaintainer = Constants->CONST->{'IBackupMaintainer'} if($appType eq "IBackup");
	return $appMaintainer;
}

#****************************************************************************************************
# Subroutine Name         : checkBinaryExists.
# Objective               : This subroutine checks for the existence of idevsutil binary in the
#							current directory and also if the binary has executable permission.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub checkBinaryExists()
{
	my $errMsg = "";
	if ($userServicePath ne ""){	
	  	if(!-e $idevsutilBinaryPath) {
			$errMsg = Constants->CONST->{'EvsMissingErr'}.$lineFeed;
	  	} elsif(!-x $idevsutilBinaryPath) {
			$errMsg = Constants->CONST->{'EvsPermissionErr'}.$lineFeed;
  		}
	}
  	return $errMsg;
}

#****************************************************************************************************
# Subroutine Name         : createPwdFile.
# Objective               : Create password or private encrypted file.
# Added By                : Avinash Kumar.
#*****************************************************************************************************/
sub createEncodeFile()
{
	my $data = $_[0];
	my $path = $_[1];
	my $utfFile = "";
	$utfFile = getUtf8File($data, $path);
	chomp($utfFile);
	
	$idevsutilCommandLine = $idevsutilBinaryPath.
	$whiteSpace.$hashEvsParameters{UTF8CMD}.$assignmentOperator."'".$utfFile."'";

	my $commandOutput = `$idevsutilCommandLine`;
	traceLog($lineFeed.Constants->CONST->{'CrtEncFile'}.$whiteSpace.$commandOutput.$lineFeed, __FILE__, __LINE__);
	unlink $utfFile;
}

#****************************************************************
# Subroutine Name         : createEncodeSecondaryFile           *
# Objective               : Create Secondary Encoded password.  *
# Added By                : Dhritikana.                         *
#****************************************************************
sub createEncodeSecondaryFile()
{
	my $pdata = $_[0];
	my $path = $_[1];
	my $udata = $_[2];
	
	my $len = length($udata); 
	my $pwd = pack( "u", "$pdata"); chomp($pwd);
	$pwd = $len."_".$pwd;
	
	open FILE, ">", "$enPwdPath" or (traceLog($lineFeed.Constants->CONST->{'FileCrtErr'}.$enPwdPath."failed reason: $! $lineFeed", __FILE__, __LINE__) and die);
	chmod $filePermission, $enPwdPath;
	print FILE $pwd;
	close(FILE);
}

#***********************************************************************
# Subroutine Name         : getPdata   
# Objective               : Get Pdata in order to send Mail notification 
# Added By                : Dhritikana.
#***********************************************************************
sub getPdata()
{
	my $udata = $_[0];
	
	chmod $filePermission, $enPwdPath;
	open FILE, "<", "$enPwdPath" or (traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}.$enPwdPath." failed reason:$! $lineFeed", __FILE__, __LINE__) and die);
	my $enPdata = <FILE>; chomp($enPdata);
	close(FILE);
	
	my $len = length($udata);
	my ($a, $b) = split(/\_/, $enPdata, 2); 
	my $pdata = unpack( "u", "$b");
	if($len eq $a) {
		return $pdata;
	}
}

#****************************************************************************************************
# Subroutine Name         : getUtf8File.
# Objective               : Create utf8 file.
# Added By                : Avinash Kumar.
#*****************************************************************************************************/
sub getUtf8File()
{
	my ($getVal, $encPath) = @_;
	my $usrProfileDir = defined ($usrProfileDir) ? $usrProfileDir : $usrProfilePath	;
	if (!-e $usrProfileDir){
		my $res = `mkdir -p $usrProfileDir`;
	}
	#create utf8 file.
 	open FILE, ">", "$usrProfileDir/utf8.txt" or (traceLog($lineFeed. $lineFeed.Constants->CONST->{'FileOpnErr'}."utf8.txt. failed reason:$! $lineFeed", __FILE__, __LINE__) and die);
  	print FILE "--string-encode=$getVal\n",
			"--out-file=$encPath\n";
	
  	close(FILE);
  	chmod $filePermission, "$usrProfileDir/utf8.txt";
	return "$usrProfileDir/utf8.txt";	
}

#****************************************************************************************************
# Subroutine Name		: updateServerAddr.
# Objective				: Construction of get-server address evs command and execution.
#			    			Parse the output and update same in Account Setting File.
# Added By				: Avinash Kumar.
# Modified By			: Dhritikana  
#*****************************************************************************************************/
sub getServerAddr()
{
	my $getServerUtfFile = undef;
	$getServerUtfFile = getOperationFile($getServerAddressOp);

	$getServerUtfFile =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$getServerUtfFile."'".$whiteSpace.$errorRedirection.$lineFeed;
	my $commandOutput = `$idevsutilCommandLine`;
	unlink($getServerUtfFile);
	
	parseXMLOutput(\$commandOutput);
	my $addrMessage = $evsHashOutput{'message'};
	$serverAddress = $evsHashOutput{'cmdUtilityServerIP'};
	my $desc = $evsHashOutput{'desc'};
	traceLog($lineFeed.Constants->CONST->{'GetServAddr'}.$commandOutput.$lineFeed, __FILE__, __LINE__);
	
	if($commandOutput =~ /reason\: connect\(\) failed/) {
		print $lineFeed.Constants->CONST->{'ProxyErr'}.$lineFeed.$whiteSpace;
		traceLog($lineFeed.Constants->CONST->{'ProxyErr'}.$lineFeed, __FILE__, __LINE__);
		if($mkDirFlag) {
			rmtree($userName);
		}
		return 0;	
	}
	if($commandOutput =~ /idevs error/ && $commandOutput !~ /Invalid username or Password|too short/) {
		traceLog($lineFeed.$commandOutput.$lineFeed, __FILE__, __LINE__);
	}
	if($addrMessage =~ /ERROR/) {
		if($desc eq ''){
			traceLog($lineFeed.$commandOutput.$lineFeed, __FILE__, __LINE__)
		}else{
			print $lineFeed.$desc.$lineFeed.$whiteSpace;
			traceLog($lineFeed.$desc.$lineFeed.$whiteSpace.$lineFeed, __FILE__, __LINE__);
		}
		if($mkDirFlag) {
			rmtree($usrProfileDir);
			unlink $pwdPath; 
			unlink $enPwdPath;
		}
		return 0;
	}
	if(0 < length($serverAddress)) {
		open FILE, ">", $serverfile or (print $tHandle $lineFeed.Constants->CONST->{'FileOpnErr'}."$serverfile for getServerAddress, Reason:$! $lineFeed" and die);
		print FILE $serverAddress;
		close FILE;
		chmod $filePermission, $serverfile;
	}
	else {
		traceLog($lineFeed.Constants->CONST->{'GetSrvAdrErr'}.$lineFeed, __FILE__, __LINE__);
		return 0;
	}
	return 1;
} 
#**********************************************************************************
# Subroutine Name         : readConfigurationFile
# Objective               : This subroutine reads the entire Configuration File
# Added By                :
# Modified By		  : Abhishek Verma - 09-03-17 - declared $confFilePath with my. 
#**********************************************************************************
sub readConfigurationFile
{
#=====================================================================================================================
# TBE : ENH-001 - Load local CONFIGURATION_FILE
# user local variable for file read, in order to readConfigurationFile to be cummulative
	my @ConfFile = () ;		# TBE : ENH-001 Temp file content
#=====================================================================================================================
	my $confFilePath = $_[0];
	if ((-e $confFilePath and -s $confFilePath > 0)){
		chmod $filePermission, $confFilePath;
		open CONF_FILE, "<", $confFilePath or (traceLog($lineFeed.Constants->CONST->{'ConfMissingErr'}." reason :$! $lineFeed", __FILE__, __LINE__) and die);
#=====================================================================================================================
# TBE : ENH-001 Cummulative content
#		@linesConfFile = <CONF_FILE>;  
		@ConfFile = <CONF_FILE>;
		push (@linesConfFile, @ConfFile);
# TBE : ENH-001 End of change
#=====================================================================================================================
		close CONF_FILE;
	}else{
		return 0;
	}
}

#*******************************************************************************************************************
# Subroutine Name         : getParameterValue
# Objective               : fetches the value of individual parameters which are specified in the configuration file
# Added By                : 
# Modified By 		  : Abhishek Verma - 17-03-2017 - Removed chomp function as through regex we remove leading and trailing spaces.
#********************************************************************************************************************
sub getParameterValue
{
	foreach (@linesConfFile) { 
		if(/${$_[0]}/) {
			my @keyValuePair = split /= /;
			${$_[1]} = $keyValuePair[1];
#			chomp ${$_[1]};
			${$_[1]} =~ s/^\s+//;
			${$_[1]} =~ s/\s+$//;
			last;
		}
	}
}

#****************************************************************************
# Subroutine Name         : getInput
# Objective               : Get user input from terminal. 
# Added By                : Dhritikana
# Modified By 		  : Abhishek Verma; 09/03/17 - Used Chomp function to remove space from both the ends of input.
#****************************************************************************/
sub getInput {
	my $input = <STDIN>;
	Chomp(\$input);
	return $input;
}

#****************************************************************************
# Subroutine Name         : checkInput
# Objective               : Get user input from terminal. 
# Added By                : Dhritikana
#****************************************************************************/
sub checkInput {
	my $inputCount=0;
	while(${$_[0]} eq "") {
		if ($inputCount == 3){ print $_[1].Constants->CONST->{'maxRetry'}.' '.$lineFeed;  system('stty','echo');exit(0);}
		print $_[1].Constants->CONST->{'InputEmptyErr'};
		${$_[0]} = getInput();
		$inputCount++;
	}
}

#*******************************************************************************************************************
# Subroutine Name         : putParameterValue
# Objective               : edits the value of individual parameters which are specified in the configuration file.
# Added By                : Dhritikana
#********************************************************************************************************************
sub putParameterValue
{
	my $matchFlag = 0;
	$confFilePath = $_[2];
	if ((-e $confFilePath and -s $confFilePath > 0)){
		readConfigurationFile($confFilePath);
		open CONF_FILE, ">", $confFilePath or (traceLog($lineFeed.Constants->CONST->{'ConfMissingErr'}." reason :$! $lineFeed", __FILE__, __LINE__) and die);
		foreach my $line (@linesConfFile) {
			if($matchFlag == 0 && $line =~ /${$_[0]}/) {
				$line = "${$_[0]} = ${$_[1]}\n";
				$matchFlag = 1;
			}
			print CONF_FILE $line;
		}
		close CONF_FILE;
	}else{
		return 0;
	}
}

#*******************************************************************************************************************
# Subroutine Name         : getConfigHashValue
# Objective               : fetches the value of individual parameters which are specified in the configuration file
# Added By                : Dhritikana
# Modified By 		  : Abhishek Verma - 09-03-17 - used Chomp in place of chomp and other regular expressions which was used to remove spaces from beginning and end.
#********************************************************************************************************************
sub getConfigHashValue
{	
	foreach my $line (@linesConfFile) { 
		my @keyValuePair = split /= /, $line;
		Chomp(\$keyValuePair[0]);
		Chomp(\$keyValuePair[1]);
		$hashParameters{$keyValuePair[0]} = $keyValuePair[1];
	}
	return %hashParameters;
}

#****************************************************************************************************
# Subroutine Name         : readStatusFile.
# Objective               : reads the status file 
# Added By                : Deepak Chaurasia
# Modified By 		  : Abhishek Verma - 15/03/17 - Added else, after first if{}.
#*****************************************************************************************************/
sub readStatusFile()
{
	#if(-e $statusFilePath and -f $statusFilePath and -s $statusFilePath ) {
	if(! -s $statusFilePath ) {
		return;
	}else{
		chmod $filePermission, $statusFilePath;
		if(open(STATUS_FILE, "< $statusFilePath")) { 
			@linesStatusFile = <STATUS_FILE>;
			close STATUS_FILE;
			if($#linesStatusFile >= 0) {
				foreach my $line (@linesStatusFile) { 
					my @keyValuePair = split /=/, $line;
					chomp @keyValuePair;
					s/^\s+|\s+$//g for (@keyValuePair);
					$keyValuePair[1] = 0 if(!$keyValuePair[1]);
					$statusHash{$keyValuePair[0]} = $keyValuePair[1];
				}
			}
		}
	}
}


#****************************************************************************************************
# Subroutine Name         : getParameterValueFromStatusFile.
# Objective               : Fetches the value of individual parameters which are specified in the 
#                           Account Settings file.
# Added By                : Arnab Gupta.
# Modified By			  : Deepak Chaurasia, Dhritikana
#*****************************************************************************************************/
sub getParameterValueFromStatusFile
{
	if($#linesStatusFile le 1) {
		readStatusFile();
	}

	if($#linesStatusFile >= 0){
		return $statusHash{$_[0]};
	} else {
		return 0;
	}
}

#****************************************************************************************************
# Subroutine Name         : putParameterValueInStatusFile.
# Objective               : Changes the content of STATUS FILE as per values passed
# Added By                : Dhritikana
#*****************************************************************************************************/
sub putParameterValueInStatusFile()
{
	open STAT_FILE, ">", $statusFilePath or (traceLog($lineFeed.Constants->CONST->{'StatMissingErr'}." reason :$! $lineFeed", __FILE__, __LINE__) and die);
	foreach my $keys(keys %statusHash) {
		print STAT_FILE "$keys = $statusHash{$keys}\n";
	}
	close STAT_FILE;
	chmod $filePermission, $statusFilePath;
	undef @linesStatusFile;
}

#*******************************************************************************************************************
# Subroutine Name         : getOperationFile
# Objective               : Create utf8 file for EVS command respective to operation type(backup/restore/validate...)
# Added By                : Avinash Kumar.
#********************************************************************************************************************
sub getOperationFile
{
	my $opType = "";
	my $utfFile = "";
	my $utfValidate = "";
	my $utfPath = $jobRunningDir."/utf8.txt";
	my $serverAddressOperator = "@";
	my $serverName = "home";
	my $serverNameOperator = "::";
	my $encryptionType = "";

	my $operationType = $_[0];


	if($operationType == $validateOp)
        {       
			$utfPath = defined ($usrProfileDir) ? $usrProfileDir."/utf.txt" : $usrProfilePath.'/utf.txt';
		
			open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for validate, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{VALIDATE}.$lineFeed.
                           $hashEvsParameters{USERNAME}.$assignmentOperator.$userName.$lineFeed.
                           $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
                           $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
                           $hashEvsParameters{ENCODE}.$lineFeed;
                           #$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
        }
	elsif($operationType == $getServerAddressOp)
        {
		$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for getServerAddress, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{SERVERADDRESS}.$lineFeed.
                           $userName.$lineFeed.
                           $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
			   $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
			   $hashEvsParameters{ENCODE}.$lineFeed.
			   $hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
        }
	elsif($operationType == $configOp)
        {
				$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for config, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{CONFIG}.$lineFeed.
                           $hashEvsParameters{USERNAME}.$assignmentOperator.$userName.$lineFeed.
                           $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
                if("PRIVATE" eq $_[1]){
                        $utfFile .= $hashEvsParameters{ENCTYPE}.$assignmentOperator.$privateEncryptionKey.$lineFeed.
                                    $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
                }
                else{
                        $utfFile .= $hashEvsParameters{ENCTYPE}.$assignmentOperator.$defaultEncryptionKey.$lineFeed;
                }
                $utfFile .= $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
                            $hashEvsParameters{ENCODE}.$lineFeed;
        }
	elsif($operationType == $createDirOp)
        {
				$utfPath = $usrProfileDir."/utf.txt";
                #tie my @servAddress, 'Tie::File', "$currentDir/$userName/.serverAddress.txt" or (print $tHandle "Can not tie to $serverfile, Reason:$!");
			    open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for createDir, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
                if($_[1] eq "PRIVATE"){
                        $utfFile .= $hashEvsParameters{ENCTYPE}.$assignmentOperator.$privateEncryptionKey.$lineFeed.
                                    $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
                }
				
		$utfFile .= $hashEvsParameters{ENCODE}.$lineFeed.
		$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
		$hashEvsParameters{CREATEDIR}.$assignmentOperator.$backupHost.$lineFeed.
		$userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$lineFeed;
        }
	elsif($operationType eq $backupOp) {
		my $BackupsetFile = $_[1];
		my $relativeAsPerOperation = $_[2];
		my $source = $_[3];
		my $encryptionType = $_[4];

		#open UTF8FILE, ">", $utfPath or (print $tHandle CONST->{'FileOpnErr'}.$utfPath." for backup, Reason:$!" and return 0);
		open UTF8FILE, ">", $utfPath or ($errStr = Constants->CONST->{'FileOpnErr'}.$utfPath." for backup, Reason:$!" and return 0);
		$utfFile = $hashEvsParameters{FROMFILE}.$assignmentOperator.$BackupsetFile.$lineFeed.
   			   $hashEvsParameters{BWFILE}.$assignmentOperator.$bwPath.$lineFeed.
   			   $hashEvsParameters{TYPE}.$lineFeed.
   			   $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
		if($encryptionType =~ m/^$privateEncryptionKey$/i) {
			$utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
		}
		$utfFile .= $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
					$hashEvsParameters{ENCODE}.$lineFeed.
					$relativeAsPerOperation.$lineFeed.
					$hashEvsParameters{TEMP}.$assignmentOperator.$evsTempDir.$lineFeed.
					$hashEvsParameters{OUTPUT}.$assignmentOperator.$idevsOutputFile.$lineFeed.
					$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
					$hashEvsParameters{ADDPROGRESS}.$lineFeed.
					$source.$lineFeed.
					$userName.$serverAddressOperator.
					$serverAddress.$serverNameOperator.
					$serverName.$pathSeparator.$backupHost.$pathSeparator.$lineFeed;
	}
	elsif($operationType eq $restoreOp) {
		my $RestoresetFile = $_[1];
		my $relativeAsPerOperation = $_[2];
		my $source = $_[3];
		my $encryptionType = $_[4];
		
	   open UTF8FILE, ">", $utfPath or ($errStr = Constants->CONST->{'FileOpnErr'}.$utfPath." for restore, Reason:$!" and return 0);
	   $utfFile = $hashEvsParameters{FROMFILE}.$assignmentOperator.$RestoresetFile.$lineFeed.
				  $hashEvsParameters{TYPE}.$lineFeed.
				  $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
	   if($encryptionType =~ m/^$privateEncryptionKey$/i) {
				$utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
	   }
		$utfFile .= $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
					$hashEvsParameters{ENCODE}.$lineFeed.
					$relativeAsPerOperation.$lineFeed.
					$hashEvsParameters{TEMP}.$assignmentOperator.$evsTempDir.$lineFeed.
					$hashEvsParameters{OUTPUT}.$assignmentOperator.$idevsOutputFile.$lineFeed.
					$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
					$hashEvsParameters{ADDPROGRESS}.$lineFeed.
					$userName.$serverAddressOperator.
					$serverAddress.$serverNameOperator.
					$serverName.$source.$lineFeed.
					$restoreLocation.$lineFeed;
	}
	elsif($operationType == $propertiesOp) {
		##restoreHost [DHRITI: need removal of starting / if exists
		$utfPath = $usrProfileDir."/utf.txt";
		open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for properties, Reason:$!", __FILE__, __LINE__) and die);
		$utfFile =	$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
					$hashEvsParameters{PROPERTIES}.$lineFeed.
					$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
					$hashEvsParameters{ENCODE}.$lineFeed;
		if(!defined($_[1]) && $_[1] ne "modProxy") {
			$utfFile .=	$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
		}
		$utfFile .= $userName.$serverAddressOperator.
			    $serverAddress.$serverNameOperator.
			    $serverName.$pathSeparator.$_[1];
	}
	elsif($operationType == $versionOp) {
			my $filePath = $_[1];
			$utfPath = $usrProfileDir."/utf.txt";
			open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for properties, Reason:$!", __FILE__, __LINE__) and die);
			$utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
				   $hashEvsParameters{VERSION}.$lineFeed.
				   $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
			   	   $hashEvsParameters{ENCODE}.$lineFeed.
				   $hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
			   	   $userName.$serverAddressOperator.
			   	   $serverAddress.$serverNameOperator.
			   	   $serverName.$pathSeparator.$filePath;
	} elsif($operationType == $renameOp) {
			$utfPath = $usrProfileDir."/utf.txt";
			my $oldPath = $_[2];
			my $newPath = $_[3];
			open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for properties, Reason:$!", __FILE__, __LINE__) and die);
			$utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
				   $hashEvsParameters{RENAME}.$lineFeed.
				   $hashEvsParameters{OLDPATH}.$assignmentOperator.$oldPath.$lineFeed.
				   $hashEvsParameters{NEWPATH}.$assignmentOperator.$newPath.$lineFeed;
		   if("PRIVATE" eq $_[1]){
                        $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
			}
			$utfFile .=	   $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
			   	   $hashEvsParameters{ENCODE}.$lineFeed.
				   $hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
			   	   $userName.$serverAddressOperator.
			   	   $serverAddress.$serverNameOperator.
			   	   $serverName.$pathSeparator;
	}
	elsif($operationType == $authListOp)
	{
			open UTF8FILE, ">", $utfPath or (traceLog("Could not open file $utfPath for auth list, Reason:$!", __FILE__, __LINE__) and die);
			$utfFile = $hashEvsParameters{AUTHLIST}.$lineFeed.
				   $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
				   $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
				   $hashEvsParameters{ENCODE}.$lineFeed.
				   #$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
				   $userName.$serverAddressOperator.
				   $serverAddress.$serverNameOperator.
				   $serverName.$pathSeparator;
	}
	elsif($operationType == $searchOp) {
		my $searchUtfPath = "$jobRunningDir/searchUtf8.txt";
		open UTF8FILE, ">", $searchUtfPath or ($errStr = "Could not open file $utfFile for search, Reason:$!" and return 0);
		$utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
		$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
		$hashEvsParameters{ENCODE}.$lineFeed.
		$hashEvsParameters{OUTPUT}.$assignmentOperator.$jobRunningDir."/Search/output.txt".$lineFeed.
		$hashEvsParameters{ERROR}.$assignmentOperator.$jobRunningDir."/Search/error.txt".$lineFeed.
		#$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
		$hashEvsParameters{SEARCH}.$lineFeed.
		$hashEvsParameters{FILE}.$lineFeed.
		$userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$_[1].$pathSeparator.$lineFeed;
		print UTF8FILE $utfFile;
		close UTF8FILE;
		traceLog($searchUtfPath, __FILE__, __LINE__);
		chmod $filePermission, $searchUtfPath;
		return $searchUtfPath;
	}
	elsif($operationType == $itemStatOp) {
		open UTF8FILE, ">", $utfPath or ($errStr = "Could not open file $utfFile for search, Reason:$!" and return 0);
		$utfFile = $hashEvsParameters{FROMFILE}.$assignmentOperator.$_[1].$lineFeed.
		$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
		$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
		$hashEvsParameters{TEMP}.$assignmentOperator.$evsTempDir.$lineFeed.
		$hashEvsParameters{ERROR}.$assignmentOperator.$jobRunningDir."/error.txt".$lineFeed.
		$hashEvsParameters{ENCODE}.$lineFeed.
		#$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
		$hashEvsParameters{ITEMSTATUS}.$lineFeed.
		$userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$pathSeparator.$lineFeed;
	} elsif($operationType == $verifyPvtOp) {
		$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE,">",$utfPath or ($errStr="Could not open file $utfFile for search, Reason:$!" and return 0);
		$utfFile  = $hashEvsParameters{DEFAULTKEY}.$lineFeed;
                $utfFile .= $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
                $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
                $utfFile .= $hashEvsParameters{ENCODE}.$lineFeed.$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.$userName.$serverAddressOperator.$serverAddress.$serverNameOperator.$serverName.$lineFeed;
	}elsif ($operationType == $getQuotaOp){
		$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE,">",$utfPath or ($errStr="Could not open file $utfFile for search, Reason:$!" and return 0);
                $utfFile  = $hashEvsParameters{GETQUOTA}.$lineFeed;
                $utfFile .= $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
                $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed if ($_[1] eq $privateEncryptionKey);
                $utfFile .= $hashEvsParameters{ENCODE}.$lineFeed.$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.$userName.$serverAddressOperator.$serverAddress.$serverNameOperator.$serverName.$lineFeed;
	}else {
		traceLog(Constants->CONST->{'InvalidOp'}, __FILE__, __LINE__);
	}
	
	print UTF8FILE $utfFile;
	close UTF8FILE;
	traceLog($utfFile, __FILE__, __LINE__);
	chmod $filePermission, $utfPath;
	return $utfPath;
}

#****************************************************************************************************
# Subroutine Name         : parseXMLOutput.
# Objective               : Parse evs command output and load the elements and values to an hash.
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub parseXMLOutput
{
	${$_[0]} =~ s/^$//;
	if(defined ${$_[0]} and ${$_[0]} ne "") {
		my $evsOutput = ${$_[0]};
		$evsOutput  =~ s/\n\<(tree )?//;
		$evsOutput  =~ s/(?:connection\s+established)?//;
		#$evsOutput  =~ s/^\<tree\ //;
		#$evsOutput =~ s/\"\/\>$//;
		$evsOutput =~ s/\"\/\>//;
		my @evsArrLine = split(/\"[\s\n]+/sg, $evsOutput);
		foreach(@evsArrLine) {
			my ($key,$value) = split(/\="/, $_);
		 	&Chomp(\$key);
			&Chomp(\$value);
			$evsHashOutput{$key} = $value;
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : getProxy.
# Objective               : To get the proxy string
# Added By                : 
#*****************************************************************************************************/
sub getProxy
{
	my $proxy = $hashParameters{PROXY};
	my($proxyIP) = $proxy =~ /@(.*)\:/; 
	if($proxyIP ne ""){
		return $proxy;
	}
	return "";
}
   

#****************************************************************************************************
# Subroutine Name         : getFinalMailAddrList
# Objective               : To get valid multiple mail address list
# Added By                : Dhritikana
#*****************************************************************************************************
sub getFinalMailAddrList
{
	my $count = 0; 
	my $finalAddrList = ''; 
	my $configEmailAddress = $_[0];
	
	if($configEmailAddress ne "") {
		my @addrList = ();
		if($configEmailAddress =~ /\,/) {
			@addrList = split(/\,|\;/, $configEmailAddress);
		} else {
			push(@addrList, $configEmailAddress);
		}
		
		foreach my $addr (@addrList) {
			if($addr eq "") {
				next;
			}
			
			if(validEmailAddress($addr)) {
				$count++;
				$finalAddrList .= "$addr,";
			} else
			{
				print Constants->CONST->{'SendMailErr'}.Constants->CONST->{'InvalidEmail'}." $addr $lineFeed";
				traceLog(Constants->CONST->{'SendMailErr'}.Constants->CONST->{'InvalidEmail'}." $addr $lineFeed", __FILE__, __LINE__);
				open ERRORFILE, ">>", $errorFilePath;
				chmod $filePermission, $errorFilePath;
				autoflush ERRORFILE;
				
				print ERRORFILE Constants->CONST->{'SendMailErr'}.Constants->CONST->{'InvalidEmail'}." $addr $lineFeed";
				close ERRORFILE;
			}
		}
		
		if($count > 0) {
			return $finalAddrList;
		} 
		else {
			traceLog(Constants->CONST->{'SendMailErr'}.Constants->CONST->{'EmlIdMissing'}, __FILE__, __LINE__);
			return "NULL";
		}
	}
}

#*******************************************************************************************************************
# Subroutine Name         : sendMail
# Objective               : sends a mail to the user in ase of successful/canceled/ failed scheduled backup/restore.
# Added By                : Dhritikana
#********************************************************************************************************************
sub sendMail
{
	if($taskType eq "Manual") {
		return;
	}

	my $mailNotifyFlagFile = $jobRunningDir."/".$jobType."mailNotify.txt";
	my ($notifyFlag, $notifyEmailIds, $notifyData) = undef;
	if(!-e $mailNotifyFlagFile) {
		return;
	} else {
		unless(open NOTIFYFILE, "<", $mailNotifyFlagFile) {
			traceLog(Constants->CONST->{FileOpenErr}." $mailNotifyFlagFile, Reason: $!".$lineFeed, __FILE__, __LINE__);
			return;
		}
		
		@notifyData = <NOTIFYFILE>;
		chomp(@notifyData);
		$notifyFlag = $notifyData[0];
		$notifyEmailIds = $notifyData[1];
		close(NOTIFYFILE);
		
		if($notifyFlag eq "DISABLED") {
			return;
		}

		$configEmailAddress = $notifyEmailIds;
	}
	
	my $finalAddrList = getFinalMailAddrList($configEmailAddress);
	if($finalAddrList eq "NULL") {
		return;
	} 	
	
	my $sender = "support\@".$appTypeSupport.".com";
	my $content = "";
	my $subjectLine = $_[0];
	my $operationData = $_[1];
	my $backupRestoreFileLink = $_[2];
	
	$content = "Dear $appType User, \n\n";	
	$content .= "Ref : Username - $userName \n";
	$content .= $mail_content_head;
	$content .= $mail_content;

#	if($jobType eq "Backup" && $status eq "SUCCESS*") {	
#		$content .= "\n Note: Successful $jobType* denotes \'mostly success\' or \'majority of files are successfully backed up\' \n";
#	} elsif($jobType eq "Backup" && $status eq "SUCCESS*") {	
#		$content .= "\n Note: Successful $jobType* denotes \'mostly success\' or \'majority of files are successfully restored\' \n";
#	}
	if ($operationData eq 'NOBACKUPDATA'){
		$content .= qq{ Unable to perform backup operation. Your backupset file is empty. To do backup again please fill your backupset file.Your backupset file location is "$backupRestoreFileLink".};
	}elsif($operationData eq 'NORESTOREDATA'){
		$content .= qq{ Unable to perform restore operation. Your restoreset file is empty. To do restore again please fill your restoreset file.Your restoreset file location is "$backupRestoreFileLink".};

	}

	$content .= "\n\nRegards, \n";
	$content .= "$appType Support.\n";
	$content .= "Version ".Constants->CONST->{'Version'};
	
	my $pData = &getPdata("$userName");
	
	#URL DATA ENCODING#
	foreach ($userName,$pData,$finalAddrList,$subjectLine,$content) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}
	$notifyPath = 'http://webdav.ibackup.com/cgi-bin/Notify_email_ibl';
	$data = 'username='.$userName.'&password='.$pData.'&to_email='.$finalAddrList.'&subject='.$subjectLine.'&content='.$content;
	#`curl -d '$data' '$PATH' &>/dev/nul` or print $tHandle "$linefeed Couldn't send mail. $linefeed";
	my $curlCmd = formSendMailCurlcmd();
	
	my $sendMailMsg = `$curlCmd`;
	open (NOTIFYFILE, ">>", $mailNotifyFlagFile) or traceLog(Constants->CONST->{'FileOpnErr'}." $mailNotifyFlagFile . Reason: $!", __FILE__, __LINE__) and return;
	#print NOTIFYFILE $sendMailMsg;
	close(NOTIFYFILE);
}

#*****************************************************************************************************
# Subroutine Name         : formSendMailCurlcmd
# Objective               : forms curl command to send mail based on proxy settings
# Added By                : Dhritikana
#*****************************************************************************************************
sub formSendMailCurlcmd {
	my $cmd = '';
	if($proxyStr) {
		my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
		my @UnP = split(/\:/, $uNPword);
		if($UnP[0] ne "") {
			foreach ($UnP[0], $UnP[1]) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$uNPword = join ":", @UnP;
			$cmd = "curl -x http://$uNPword\@$ipPort -d '$data' '$notifyPath'";
		} else {
			$cmd = "curl -x http://$ipPort -d '$data' '$notifyPath'";
		}
	} else {			
		$cmd = "curl -d '$data' '$notifyPath'";
	}
	return $cmd;	
}

#*****************************************************************************************************
# Subroutine Name         : validEmailAddress
# Objective               : validates the email address provided by the user in the configuration file
# Added By                : Dhritikana
# Modified By 		  : Abhishek Verma - - Email ID validation regex changed.
#*****************************************************************************************************
sub validEmailAddress
{
	my $addr = $_[0];
	$addr = lc($addr);
#	return(0) unless ($addr =~ /^[^@]+@([-\w]+\.)+[a-z]{2,}$/);
	return(0) unless ($addr =~ /^[a-zA-Z0-9]+(\.?[\*\+\-\_\=\^\$\#\!\~\?a-zA-Z0-9])*\.?\@([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)(\.[a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)*\.(?:([a-zA-Z0-9]+)|([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+))$/);
	return(1);
}

#******************************************************************************
# Subroutine Name         : terminateStatusRetrievalScript
# Objective               : terminates the Status Retrieval script in case it is running
# Added By                : 
#******************************************************************************
sub terminateStatusRetrievalScript()
{
	my $statusScriptName = Constants->FILE_NAMES->{statusRetrivalScript};
	my $statusScriptCmd = "ps -elf | grep $statusScriptName | grep -v grep";
	
	my $statusScriptRunning = `$statusScriptCmd`;
	
	if($statusScriptRunning ne "") {
#		my @processValues = split /[\s\t]+/, $statusScriptRunning;
#		my $pid = $processValues[3];
		 my $pid = (split /[\s\t]+/, $statusScriptRunning)[3];		
		`kill -s SIGTERM $pid`;
	}
	unlink($_[0]);
}

#****************************************************************************************************
# Subroutine Name         : copyTempErrorFile
# Objective               : This subroutine copies the contents of the temporary error file to the 
#							Error File.
# Added By                : 
# Modified By			  : Deepak Chaurasia
#*****************************************************************************************************/
sub copyTempErrorFile()
{
	# if error file is empty then return 
	if(!-s $idevsErrorFile){
		return;
	}
	
	#open the error file for read and if open fails then return
	if (! open(TEMP_ERRORFILE, "< $idevsErrorFile")) {
		traceLog("Could not open file $idevsErrorFile, Reason:$! $lineFeed", __FILE__, __LINE__);
		return;
	}
	
	#read error file content 
	my @tempErrorFileContents = ();	
	@tempErrorFileContents = <TEMP_ERRORFILE>;
	close TEMP_ERRORFILE; 
	
	my $file = $_[0];
	
	#open the App error file and if failed to open then return
	if (! open(ERRORFILE, ">> $file")) {     
		traceLog("Could not open file 'file' in copyTempErrorFile: $file, Reason:$! $lineFeed", __FILE__, __LINE__);
		return;
	}

	#write the content of error file in App error file
	$errorStr = join('\n', @tempErrorFileContents);
	print ERRORFILE $errorStr;
	close ERRORFILE;
	chmod $filePermission, $file;
}

#*******************************************************************************************
# Subroutine Name         : cleanProgressFile
# Objective               : erases the contents of the progress file
# Added By                : 
#*******************************************************************************************
sub cleanProgressFile()
{
	my $progressDetailsFilePath = ${$_[0]};
	if (open(PROGRESSFILE, "> $progressDetailsFilePath"))
	{
		close PROGRESSFILE;
		chmod $filePermission, $progressDetailsFilePath;
	}
	else
	{
		traceLog(Constants->CONST->{'FileOpnErr'}.$progressDetailsFilePath." Reason:$! $lineFeed", __FILE__, __LINE__);
	}
}

#****************************************************************************************************
# Subroutine Name         : appendErrorFileContents
# Objective               : This subroutine appends the contents of the error file to the output file
#							and deletes the error file.
# Modified By                : Deepak Chaurasia
#*****************************************************************************************************/
sub appendErrorFileContents
{
	my $error_dir = $_[0]."/";
	my @files_list = `ls $error_dir`;
	my $fileopen = 0;
	chomp(@files_list);
	foreach my $file (@files_list) {
		chomp($file);
		if ( $file eq "." or $file eq "..") {
			next;
		}
		$file = $error_dir.$file;
		
		if(-s $file > 0){
			if($fileopen == 0){
				$summaryError.="$lineFeed"."_______________________________________________________________________________________";
				$summaryError.="$lineFeed"."|Error Report|"."$lineFeed";
				$summaryError.="_______________________________________________________________________________________$lineFeed";
			}
			$fileopen = 1;
			open ERROR_FILE, "<", $file or traceLog(Constants->CONST->{'FileOpnErr'}." $file. Reason $!\n", __FILE__, __LINE__);
			while(my $line = <ERROR_FILE>) { 
				$summaryError.=$line;
			}
			close ERROR_FILE;
		}
	}	
}

#*************************************************************************************************
# Subroutine Name		: createLogFiles
# Objective			: Creates the Log Directory if not present, Creates the Error Log and  
#					Output Log files based on the timestamp when the backup/restore
#					operation was started, Clears the content of the Progress Details file 
# Added By			:
# Modified By 		   	: Abhishek Verma - Now the logfile name will contain epoch time and job status like (Success, Failure, Aborted) - 17/5/2017
#**************************************************************************************************
sub createLogFiles() 
{
	my $jobType = $_[0];
	our $progressDetailsFileName = "PROGRESS_DETAILS_".$jobType;
	our $outputFileName = $jobType;
	our $errorFileName = $jobType."_ERRORFILE";
	my $logDir = "$jobRunningDir/LOGS";
	$errorDir = "$jobRunningDir/ERROR";
	
	if($ifRetainLogs eq "NO") {
		chmod $filePermission, $logDir;
		rmtree($logDir);
	}

	if(!-d $logDir)
	{
		mkdir $logDir;
		chmod $filePermission, $logDir;
	}

#=====================================================================================================================
# TBE : ENH-003 TIMESTAMP fix to YYYY-MM-DD_HH-MM-SS
	#previous log file name use to be like 'BACKUP Wed May 17 12:34:47 2017_FAILURE'.Now log name will be '1495007954_SUCCESS'.
	#	my $currentTime = localtime;
#	my $currentTime = time;#This function will give the current epoch time.
# Correct timestamp string : YYYY-MM-DD_HH-MM-SS
	my $currentTime = POSIX::strftime("%Y-%m-%d_%H-%M-%S", localtime);
#=====================================================================================================================
	
	$outputFilePath = $logDir.$pathSeparator.$currentTime; 
	$errorFilePath = $errorDir.$pathSeparator.$errorFileName;
	$progressDetailsFilePath = $jobRunningDir.$pathSeparator.$progressDetailsFileName;
}

#*******************************************************************************************
# Subroutine Name         :	convertFileSize
# Objective               :	converts the file size of a file which has been backed up/synced
#                           into human readable format
# Added By                : 
#******************************************************************************************
sub convertFileSize
{
	my $fileSize = $_[0];
	my $fileSpec = "bytes";
	
	if($fileSize > 1023)
	{
		$fileSize /= 1024;
		$fileSpec = "KB";
	}
	
	if($fileSize > 1023)
	{
		$fileSize /= 1024;
		$fileSpec = "MB";
	}
	
	if($fileSize > 1023)
	{
		$fileSize /= 1024;
		$fileSpec = "GB";
	}
	
	if($fileSize > 1023)
	{
		$fileSize /= 1024;
		$fileSpec = "TB";
	}
	
	$fileSize = sprintf "%.2f", $fileSize;
	if(0 == ($fileSize - int($fileSize)))
	{
		$fileSize = sprintf("%.0f", $fileSize);
	}
	return $fileSize.$whiteSpace.$fileSpec;
}

#****************************************************************************************************
# Subroutine Name         : displayProgressBar.
# Objective               : This subroutine contains the logic to display the filename and the progress
#							bar in the terminal window.
# Added By                : 
#*****************************************************************************************************/
sub displayProgressBar()
{
	$SIG{WINCH} = \&changeSizeVal;
	my $progress = undef;
	my $cellSize = undef;
	
	my $type = $_[0];
	my $trnsFileSize = $_[1];
	my $incrFileSize = $_[2];
	my $TotalSize = $_[3];
	my $kbps = $_[4];
	my $fullHeader = $_[5];
	my $fileName = $_[6];
	$curLines = $_[7];
	eval{
		$percent = $incrFileSize/$TotalSize*100; 
	};
	$percent = 100 if ($@ =~ /Illegal division by zero/i);
	$percent =~ s/\..*//;
	if($percent > 100){
		$percent = 100;
	}
	
	$progress = "|"x($percent/$progressSizeOp); 
	my $cellCount = (100-$percent)/$progressSizeOp;
	$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
	$cellSize = " "x$cellCount;

	my $totalSizeUnit = convertFileSize($TotalSize);
	my $fileSizeUnit = convertFileSize($incrFileSize);

	$kbps =~ s/\s+//;
	$percent = sprintf "%4s", "$percent%";
	$spAce = " "x6;
	$boundary = "-"x(100/$progressSizeOp);
	$spAce1 = " "x(38/$progressSizeOp);
	
	system("tput cup $curLines 0");
	system("tput ed");
	
	print $fullHeader;
	print "[$type] [$fileName][$trnsFileSize]\n\n";
	print "$spAce$boundary\n";
	print "$percent [";
	print $progress.$cellSize;
	print "]\n";
	print "$spAce$boundary\n";
	print "$spAce1\[$fileSizeUnit of $totalSizeUnit] [$kbps]\n";
	
	if($jobType =~ /Backup/i) {
		print "\nBackup Location    : $backupHost\n";
		print "Backup Type        : $backupPathType\n";	
		print "Bandwidth Throttle : $bwThrottle%\n";	
	} else {
		print "\nRestore From Location   : $restoreHost\n";
		print "Restore Location        : $restoreLocation\n";
	}
}

#****************************************************************************************************
# Subroutine Name         : writeLogHeader.
# Objective               : This function will write user log header.
# Added By				  : Dhritikana
#*****************************************************************************************************/
sub writeLogHeader {
	my $flagToCheckSchdule = $_[0];
	# require to open log file to show job in progress as well as to log exclude details
	if(!open(OUTFILE, ">", $outputFilePath)){
		print Constants->CONST->{'CreateFail'}." $outputFilePath, Reason:$!";
		traceLog(Constants->CONST->{'CreateFail'}." $outputFilePath, Reason:$!", __FILE__, __LINE__) and die;
	}
	chmod $filePermission, $outputFilePath;
	

	autoflush OUTFILE;
	my $host = `hostname`;
	chomp($host);
	
	autoflush OUTFILE;
	
	my $mailHeadA = $lineFeed."$jobType Start Time: ".(localtime)."$lineFeed";
	my $mailHeadB = '';
	
	if($jobType eq "Backup") {
		$mailHeadB = "$jobType Type: $backupPathType $jobType $lineFeed";
	}
	$mailHeadB .= "Machine Name: $host $lineFeed";
	$mailHeadB .= "Throttle Value: $bwThrottle $lineFeed" if ($jobType eq "Backup");
        $mailHeadB .= "$jobType Location: $location $lineFeed";
	
	my $LogHead = $mailHeadA."Username: $userName $lineFeed".$mailHeadB;				
	print OUTFILE $LogHead.$lineFeed;	
		
	my $mailHead = $mailHeadA.$mailHeadB;
	return $mailHead;	
}

#*******************************************************************************************
# Subroutine Name         :	writeOperationSummary
# Objective               :	This subroutine writes the restore summary to the output file.
# Added By                : 
#******************************************************************************************
sub writeOperationSummary()
{
	$filesConsideredCount = $totalFiles;
	chomp($filesConsideredCount);
	
	chmod $filePermission, $outputFilePath;
	if (-e $outputFilePath and -s $outputFilePath > 0){# If $outputFilePath exists then only summery will be written otherwise no summery file will exists.
		# open output.txt file to write restore summary.
		if (!open(OUTFILE, ">> $outputFilePath")){ 
			traceLog(Constants->CONST->{'FileOpnErr'}.$outputFilePath.", Reason:$! $lineFeed", __FILE__, __LINE__);
			return;
		}
		chmod $filePermission, $outputFilePath;
	
		if($failedFilesCount > 0 or $nonExistsCount >0) {
			appendErrorFileContents($errorDir);
			$summary .= $summaryError.$lineFeed;
			$failedFilesCount += $nonExistsCount;
		}	
	
		# construct summary message.
		my $mail_summary = undef;
		$summary .= $lineFeed."Summary: ".$lineFeed;
		$finalSummery .=  $lineFeed."Summary: ".$lineFeed;
		Chomp(\$filesConsideredCount);
#======================================================================
# TBE : Enh-006 : Add remaining Quota to summary
		my %quotaDetails = getQuotaDetails();
		my $TBE_Text = $lineFeed.'Remaining Free space : '. convertFileSize($quotaDetails{remainingQuota});
#======================================================================
		if($_[0] eq $backupOp) {
			$mail_summary .= Constants->CONST->{'TotalBckCnsdrdFile'}.$filesConsideredCount.
						$lineFeed.Constants->CONST->{'TotalBckFile'}.$successFiles.
						$lineFeed.Constants->CONST->{'TotalSynFile'}.$syncedFiles.
						$lineFeed.Constants->CONST->{'TotalBckFailFile'}.$failedFilesCount.
						$lineFeed.$TBE_Text.$lineFeed.		# TBE : Enh-006
						$lineFeed.Constants->CONST->{'BckEndTm'}.localtime, $lineFeed;
		
			$finalSummery .= Constants->CONST->{'TotalBckCnsdrdFile'}.$filesConsideredCount.
					       $lineFeed.Constants->CONST->{'TotalBckFile'}.$successFiles.
					       $lineFeed.Constants->CONST->{'TotalSynFile'}.$syncedFiles.
						$lineFeed.$TBE_Text.$lineFeed.		# TBE : Enh-006
					       $lineFeed.Constants->CONST->{'TotalBckFailFile'}.$failedFilesCount.$lineFeed;
			
		} else 	{
			$mail_summary .= Constants->CONST->{'TotalRstCnsdFile'}.$filesConsideredCount.
						$lineFeed.Constants->CONST->{'TotalRstFile'}.$successFiles.
						$lineFeed.Constants->CONST->{'TotalSynFileRestore'}.$syncedFiles.
						$lineFeed.Constants->CONST->{'TotalRstFailFile'}.$failedFilesCount.
						$lineFeed.Constants->CONST->{'RstEndTm'}.localtime, $lineFeed.
						$lineFeed.$TBE_Text;		# TBE : Enh-006

			$finalSummery .= Constants->CONST->{'TotalRstCnsdFile'}.$filesConsideredCount.
					       $lineFeed.Constants->CONST->{'TotalRstFile'}.$successFiles.
					       $lineFeed.Constants->CONST->{'TotalSynFileRestore'}.$syncedFiles.
					       $lineFeed.Constants->CONST->{'TotalRstFailFile'}.$failedFilesCount.$lineFeed.
						$lineFeed.$TBE_Text;		# TBE : Enh-006
		}
		if($errStr ne "" &&  $errStr ne "SUCCESS"){
			$mail_summary .= $lineFeed.$lineFeed.$errStr.$lineFeed;
		}
	
		$summary .= $mail_summary;	
		$mail_content .= $mail_summary;
		print OUTFILE $summary;			
		close OUTFILE;
	}
}

#*******************************************************************************************
# Subroutine Name         : createUserDir
# Objective               : This subroutine creates directory for given path.
# Added By                : Dhritikana
#******************************************************************************************
sub createUserDir {
	$usrProfileDir = "$usrProfilePath/$userName";
	my $usrBackupDir = "$usrProfilePath/$userName/Backup";
	my $usrBackupManualDir = "$usrProfilePath/$userName/Backup/Manual";
	my $usrRestoreDir = "$usrProfilePath/$userName/Restore";
	my $usrRestoreManualDir = "$usrProfilePath/$userName/Restore/Manual";
	
	my @dirArr = ($usrProfilePath, $usrProfileDir, $usrBackupDir, $usrBackupManualDir, $usrRestoreDir, $usrRestoreManualDir);
	
	foreach my $dir (@dirArr) {
		if(! -d $dir) {
			$mkDirFlag = 1;
			my $ret = mkdir($dir);
			if($ret ne 1) {
				print Constants->CONST->{'MkDirErr'}.$dir.": $!".$lineFeed;
				traceLog(Constants->CONST->{'MkDirErr'}.$dir.": $!", __FILE__, __LINE__);
				exit 1;
			}
		}
		chmod $filePermission, $dir;
	}	
}

#*******************************************************************************************
# Subroutine Name         :	pidAliveCheck
# Objective               :	This subroutine checks if another job is running via pidpath
#							path availability and creates pidpath if not available and locks it
# Added By                : Dhritikana
#************************************************************************************************/
sub pidAliveCheck {
	my $pidMsg = undef;
    
	if(!open(PIDFILE, '>>', $pidPath)) {
		traceLog("Cannot open '$pidPath' for writing: $!", __FILE__, __LINE__);
		return 0;
	}
	chmod $filePermission, $pidPath;

	if(!flock(PIDFILE, 2|4)) {
		$pidMsg = "$jobType job is already in progress. Please try again later.\n";
		print $pidMsg;
		traceLog($pidMsg, __FILE__, __LINE__);
		return 0;
	}
	return 1;
}

#*******************************************************************************************
# Subroutine Name         :	backupTypeCheck
# Objective               : This subroutine checks if backup type is either Mirror or Relative
# Added By                : Dhritikana
#************************************************************************************************/
sub backupTypeCheck {
	$backupPathType = lc($backupPathType);
	if($backupPathType eq "relative") {
		$relative = 0;
	}elsif($backupPathType eq "mirror") {
		$relative = 1;
	}
	else{
		print Constants->CONST->{'WrongBackupType'}.$lineFeed;
		traceLog(Constants->CONST->{'WrongBackupType'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();
	}
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	getCursorPos
# Objective               :	gets the current cusror position
# Added By                : Dhritikana
#********************************************************************************************************/
sub getCursorPos {
	system('stty', '-echo');
	my $x='';
	system "stty cbreak </dev/tty >/dev/tty 2>&1";
	print "\e[6n";
	$x=getc STDIN;
	$x.=getc STDIN;
	$x.=getc STDIN;
	$x.=getc STDIN;
	$x.=getc STDIN;
	$x.=getc STDIN;
	system "stty -cbreak </dev/tty >/dev/tty 2>&1";
	($curLines, $cols)=$x=~m/(\d+)\;(\d+)/;
	system('stty', 'echo');
	
	my $totalLines = `tput lines`;
	chomp($totalLines);
	my $threshold = $totalLines-11;
	
	if($curLines >= $threshold) {
		system("clear");
		$curLines = 0;
	} else {
		$curLines = $curLines-1;
	}
	print "\n$_[0]" if ($_[0] ne '');	
	changeSizeVal();
	print $lineFeed.Constants->CONST->{'PrepFileMsg'}.$lineFeed;
}

#****************************************************************************************************
# Subroutine Name         : changeSizeVal.
# Objective               : Changes the size op value based on terminal size change.				
# Modified By             : Dhritikana.
#*****************************************************************************************************/
sub changeSizeVal {
	my $latestCulmn = `tput cols`;
	chomp($latestCulmn);
	if($latestCulmn < 100) {
		$progressSizeOp = 2;
	} else {
		$progressSizeOp = 1;
	}
}

#****************************************************************************
# Subroutine Name         : emptyLocationsQueries.
# Objective               : 
# Added By                : Dhritikana
#****************************************************************************/
sub emptyLocationsQueries {
	my $hostName = `hostname`;
	chomp($hostName);
	my $noRestoreLocation = $_[1];#Used to negate the call of Restore location in case of running restore_version script.
	my $defaultLocationFlag = 0;
	my $locationQuery = q{Your Backup Location is};
	my $displayLocation = $backupHost;
	my $tmpBackupHost=$backupHost; 
	if($jobType eq "Backup") {
		my $encType = checkEncType(1);
		my $oldBackupLoc = '';
		my $backupLocationCheckCount = 0;
		my $currentBackupLocation='';
		my $locName = (($backupHost eq $hostName) or (substr($backupHost, 1) eq $hostName)) ? q{default Backup} : q{Backup};
		if($backupHost eq $hostName or substr($backupHost, 1) eq $hostName or $backupHost eq "") {
			$locationQuery = Constants->CONST->{'defBackupLocMsg'};
			$displayLocation = $hostName;
			$defaultLocationFlag=1;
		}
	       
		print $lineFeed.$locationQuery." \"$displayLocation\"\. ".Constants->CONST->{'editQuery'};
		my $choice = getConfirmationChoice();
		if(($choice eq "n" || $choice eq "N")) {
			$backupHost = "/".$hostName if($defaultLocationFlag);
		} else {
			if (runningJobHandler('Backup','Scheduled',$userName,$usrProfilePath)){#This check will allow to change location only if backup job is not running.
				# get user backup location
				print Constants->CONST->{'AskLocforBackup'};
				while ($currentBackupLocation !~ /[^\s\/]+/g){
				        print Constants->CONST->{'InvLocInput'}.Constants->CONST->{'locationQuery'} if ($backupLocationCheckCount>0);
        				$currentBackupLocation = getLocationInput("backupHost");
	        			if ($backupLocationCheckCount == 3) {
        	        			$currentBackupLocation = q{Invalid Location};
                				$backupLocationCheckCount=0;
                				last;
        				}
	        			$backupLocationCheckCount++;
				}
				if ($currentBackupLocation eq 'Invalid Location'){
					if (ref $_[0] eq 'SCALAR'){
						${$_[0]} = qq{$currentBackupLocation.\nYour maximum attempt to change $locName location has reached.\nYour $locName location remains "$backupHost". $lineFeed};
					}else{
						print qq{$currentBackupLocation.\nYour maximum attempt to change $locName location has reached.\nYour $locName location remains "$backupHost". $lineFeed};
						holdScreen2displayMessage(2);
					}
				}
				else{
					if (comapareLocation($backupHost,$currentBackupLocation)){
						 if (ref $_[0] eq 'SCALAR'){
						 	${$_[0]} = qq{Your Backup Location changed successfully to "$backupHost".$lineFeed};
						 }else{
							print qq{Your Backup Location changed successfully to "$backupHost".$lineFeed};
							holdScreen2displayMessage(2);
						 }
					}else{
						$oldBackupLoc = $backupHost;
						$backupHost = $currentBackupLocation;
						my $createDirUtfFile = getOperationFile($createDirOp, $encType);
						chomp($createDirUtfFile);
				        	$createDirUtfFile =~ s/\'/\'\\''/g;
					        $idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$createDirUtfFile."'".$whiteSpace.$errorRedirection;
				        
						$commandOutput = `$idevsutilCommandLine`;
					        unlink($createDirUtfFile);
						if ($commandOutput =~ /created successfull/){
							if (ref $_[0] eq 'SCALAR'){
								${$_[0]} = qq{Your Backup Location "$backupHost" created successfully.$lineFeed};
							}else{
								print qq{Your Backup Location "$backupHost" created successfully.$lineFeed};
								holdScreen2displayMessage(2);
							}
						}
						elsif($commandOutput=~/file or folder exists/){
							if (ref $_[0] eq 'SCALAR'){
								${$_[0]} = qq{Your Backup Location changed to "$backupHost" successfully. $lineFeed $lineFeed};
							}else{
								print  qq{Your Backup Location changed to "$backupHost" successfully. $lineFeed $lineFeed};
								holdScreen2displayMessage(2);
							}
						}elsif($commandOutput=~/bad response from proxy/){
							$backupHost = $oldBackupLoc;
							if (ref $_[0] eq 'SCALAR'){
								${$_[0]} = Constants->CONST->{'ProxyErr'}.$lineFeed.$lineFeed; 
							}else{
								print  Constants->CONST->{'ProxyErr'}.$lineFeed.$lineFeed;
								exit(0);
								#holdScreen2displayMessage(2);
							}
						}elsif($commandOutput=~/encryption verification failed|password mismatch/i){
							$backupHost = $oldBackupLoc;
							unlink($pwdPath);
							if (ref $_[0] eq 'SCALAR'){
                                                                ${$_[0]} = $lineFeed.ucfirst($&).'. '.Constants->CONST->{loginAccount}.$lineFeed.$lineFeed;
                                                        }else{
                                                                print  ucfirst($&).'. '.Constants->CONST->{loginAccount}. $lineFeed.$lineFeed;
                                                                exit(0);
                                                                #holdScreen2displayMessage(2);
							}
#							unlink($pwdPath);
						}elsif($commandOutput =~ /idevs: failed to connect.*/i){
							$backupHost = $oldBackupLoc;
							if (ref $_[0] eq 'SCALAR'){
								${$_[0]} = qq(\nUnable to change your $locName location. Failed to connect.).' '.Constants->CONST->{ProxyErr}.$lineFeed;
							}else{
								print qq(\nUnable to change your $locName location. Failed to connect.).' '.Constants->CONST->{ProxyErr}.$lineFeed;
								exit(0);
							}
						}else{
							$backupHost = $tmpBackupHost;
							if (ref $_[0] eq 'SCALAR'){
								${$_[0]} = qq{\nUnable to change, your $locName location remains "$backupHost". $lineFeed $lineFeed};
							}else{
								print qq{\nUnable to change, your $locName location remains "$backupHost". $lineFeed $lineFeed};
								holdScreen2displayMessage(2);
							}
						}
					}
				}
			}else{
				if (ref $_[0] eq 'SCALAR'){
					${$_[0]} = qq{\nYour Backup Location remains "$backupHost" . $lineFeed $lineFeed};
				}else{
					print qq{\nYour Backup Location remains "$backupHost" . $lineFeed $lineFeed};
					holdScreen2displayMessage(2);
				}
			}
		}
		putParameterValue(\"BACKUPLOCATION", \"$backupHost", $confFilePath);

		if($restoreHost eq "") {
			$restoreHost = $backupHost;
			putParameterValue(\"RESTOREFROM", \"$restoreHost", $confFilePath);
			print Constants->CONST->{'restoreFromSet'}." $restoreHost $lineFeed";
		}
	} elsif($jobType eq "Restore") {
		my $existCheck = 0;
		my $tempRestoreHost = $restoreHost; #to keep data of $restoreHost variable unchanged while checking location validity.
		my $currentRestoreLocation='';
		my $restoreLocationCheckCount = 0;
		my $locName = (($restoreHost eq $hostName) or (substr($restoreHost, 1) eq $hostName)) ? q{default Restore} : q{Restore};
		my $restoreLocationMess = qq{\nYour $locName From Location is "$restoreHost". }.Constants->CONST->{'editQuery'};
		if($backupHost eq $restoreHost){
			$restoreLocationMess = qq{\nAs per your Backup Location your $locName From Location is "$backupHost". }.Constants->CONST->{'editQuery'};
		}
		print $restoreLocationMess;
		$choice = getConfirmationChoice();
		if($choice eq 'y' || $choice eq 'Y') {
			#This check will allow to change location only if restore job is not running. If running, first terminate.
			if (runningJobHandler('Restore','Scheduled',$userName,$usrProfilePath)){
				print Constants->CONST->{'restoreFromDir'};
				while ($currentRestoreLocation !~ /[^\s\/]+/g){
					print Constants->CONST->{'InvLocInput'}.Constants->CONST->{'locationQuery'} if ($restoreLocationCheckCount>0);
					$currentRestoreLocation = getLocationInput("restoreHost");
					if ($restoreLocationCheckCount == 3) {
						$currentRestoreLocation = q{Invalid Location};
						$restoreLocationCheckCount=0; 
						last;
					}
					$restoreLocationCheckCount++;
				}
				if($currentRestoreLocation eq 'Invalid Location'){
					print qq{$currentRestoreLocation ... $lineFeed}.Constants->CONST->{'maxRetryRestoreFrom'}.qq{\nYour $locName from location remains "$restoreHost". $lineFeed};
					holdScreen2displayMessage(2) if ($_[0] eq '');
					$existCheck = 1;
				}
				else
				{ 
					$tempRestoreHost = $currentRestoreLocation;
				}
				if (comapareLocation($restoreHost,$tempRestoreHost) and $existCheck == 0){
						print qq{Your Restore from location changed successfully to $restoreHost.$lineFeed};
						holdScreen2displayMessage(2) if ($_[0] eq '');
				}else{
					my $locationEntryCount = 0;
					while($existCheck eq 0){
						my $propertiesFile = getOperationFile($propertiesOp,$tempRestoreHost);
						chomp($propertiesFile);
						$propertiesFile =~ s/\'/\'\\''/g;
						$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$propertiesFile."'".$whiteSpace.$errorRedirection;
						my $commandOutput = `$idevsutilCommandLine`;
						unlink $propertiesFile;
						my $invalidLocationFlag = 0;
						if($commandOutput =~ /No such file or directory/) {
							print Constants->CONST->{'NoFileEvsMsg'}.$lineFeed;
							print Constants->CONST->{'RstFromGuidMsg'}.$lineFeed;
							print Constants->CONST->{'restoreFromDir'};
							$currentRestoreLocation = getLocationInput("restoreHost");
							if ($restoreLocationCheckCount == 3) {
								$currentRestoreLocation = q{Invalid Location};
        	                                		$restoreLocationCheckCount=0;
	                                	        	$existCheck = 1;
                                			}
							if($currentRestoreLocation eq 'Invalid Location'){
								print  qq{Your maximum attempt to change $locName from location has reached. \nYour $locName from location remains "$restoreHost".$lineFeed $lineFeed};
								$invalidLocationFlag = 1;
								holdScreen2displayMessage(2) if ($_[0] eq '');
								$existCheck = 1;
							}
							else{
								$tempRestoreHost = $currentRestoreLocation if ($currentRestoreLocation ne '');
							}
							$restoreLocationCheckCount++;
                                                }elsif($commandOutput =~ /password mismatch|encryption verification failed/i){
							unlink($pwdPath);
							if (ref $_[0] eq 'SCALAR'){
                                                                ${$_[0]} = $lineFeed.ucfirst($&).'. '.Constants->CONST->{loginAccount}.$lineFeed.$lineFeed;
								last;
                                                        }else{
                                                                print  ucfirst($&).'. '.Constants->CONST->{loginAccount}. $lineFeed.$lineFeed;
                                                                exit(0);
							}
						}elsif($commandOutput =~ /idevs: failed to connect.*/i){
                                                        $backupHost = $oldBackupLoc;
                                                        if (ref $_[0] eq 'SCALAR'){
                                                                ${$_[0]} = qq(\nUnable to change your $locName location. Failed to connect.).' '.Constants->CONST->{ProxyErr}.$lineFeed;
								last;
                                                        }else{
                                                                print qq(\nUnable to change your $locName location. Failed to connect.).' '.Constants->CONST->{ProxyErr}.$lineFeed;
                                                        	exit(0);
							}
                                                }else{
							$existCheck = 1;
							$restoreHost = $tempRestoreHost;
							print qq{Your Restore from location has been changed to "$restoreHost".$lineFeed};
							holdScreen2displayMessage(2) if ($_[0] eq '');
						}
						if ($locationEntryCount==3){
						
                                                        print $lineFeed.Constants->CONST->{'maxRetryRestoreFrom'}.$lineFeed.qq{ Your $locName from location remains "$restoreHost".$lineFeed $lineFeed};
                                                        holdScreen2displayMessage(2) if ($_[0] eq '');
                                                        last;
                                                }
						$locationEntryCount++;
					}
				} 
			}else{
					print qq{\nYour Restore from location remains "$restoreHost".$lineFeed $lineFeed};
					holdScreen2displayMessage(2) if ($_[0] eq '');
			}
		}
		putParameterValue(\"RESTOREFROM", \"$restoreHost", $confFilePath);
		
		if(!$noRestoreLocation){#In case of restore version script call to below sub is restricted. Other cases it will work.
			#In case of restore script we r calling this sub seperately inside Restore_Version.pl script.
			askRestoreLocation($_[0]);
		}
	}
}
#****************************************************************************
# Subroutine Name         : emptyLocationsQueries.
# Objective               :
# Added By                : Dhritikana
#****************************************************************************/
sub askRestoreLocation{

	my $locName = ($restoreLocation =~ /\/?$usrProfilePath\/$userName\/Restore_Data\/?/) ? q{default Restore} : q{Restore};
	print qq{\nYour $locName Location is "$restoreLocation". }.Constants->CONST->{'editQuery'};
        my $choiceR = getConfirmationChoice();
        if($choiceR eq "y" || $choiceR eq "Y") {
	        my $resetRestoreLocation = $restoreLocation;#Copy of restore location
	        my $retryCount = 4;
	        my $mkdirErrorFlag = 0;
	        while($retryCount) {
	#		get and set user restore location
			my $askLocation = $retryCount == 4 ? Constants->CONST->{'AskRestoreLocRepet'} : Constants->CONST->{'InvLocInput'}.Constants->CONST->{'locationQuery'};
                	getRestoreLocation($0,$askLocation);
	                Chomp(\$restoreLocation);
			if ($restoreLocation ne ""){
				if (!(comapareLocation($restoreLocation,$resetRestoreLocation))){
					my $res = setRestoreLocation($restoreLocation,$resetRestoreLocation,$askLocation);
                                	$mkdirErrorFlag = 0; #For every fresh loop this flag is reset to zero.
	                                if ($res eq ""){
        	                        	if (ref $_[0] eq 'SCALAR'){
                	                        	${$_[0]} .= qq{Restore Location "$restoreLocation" created successfully }.$lineFeed;
                        	                }else{
                                	        	print qq{Restore Location "$restoreLocation" created successfully }.$lineFeed;
                                        	}
	                                        chmod $filePermission, $restoreLocation;
        	                                last;
                	                }elsif($res eq 'EXISTS'){
                        	        	if (ref $_[0] eq 'SCALAR'){
                                	        	${$_[0]} .= qq(\nRestore Location $restoreLocation exists... $lineFeed);
                                        	}else{
	                                        	print qq(\nRestore Location $restoreLocation exists... $lineFeed);
	                                        }	
        	                                last;
                	                }else{
         	        	               if ($res =~ /mkdir:.*(Permission denied)/i){
                	        	               $mkdirErrorFlag = 1;
	                                               print Constants->CONST->{'InvRestoreLoc'}.qq( $restoreLocation. $1.\n);
        	                                       $retryCount = $retryCount-1;
                	                       }
                        	        }
                                	if ($retryCount == 0){
	                         	       last;
        	                        }
				}else{
					if (ref $_[0] eq 'SCALAR'){
                                		${$_[0]} .= Constants->CONST->{'restoreLocNoChange'}.qq{ "$restoreLocation".};
	                                }else{
        	                        	print Constants->CONST->{'restoreLocNoChange'}.qq{ "$restoreLocation".};
                	                }
                        	        last;
	                        }	
			}else{
				$retryCount--;
			}	
		}
		if ($retryCount == 0 and $mkdirErrorFlag == 1){#user retry is 0 and mkdirErrorFlag is 1 then only default restore location will be created.
			$restoreLocation = $resetRestoreLocation;
			if (ref $_[0] eq 'SCALAR'){
				${$_[0]} .= Constants->CONST->{'maxRetryattempt'}.' '.Constants->CONST->{'restoreLocNoChange'}.qq( "$resetRestoreLocation".$lineFeed);
			}else{
				print Constants->CONST->{'maxRetryattempt'}.' '.Constants->CONST->{'restoreLocNoChange'}.qq( "$resetRestoreLocation".$lineFeed);
			}
		}elsif($retryCount == 0){
			$restoreLocation = $resetRestoreLocation;
			if (ref $_[0] eq 'SCALAR'){
				${$_[0]} .= Constants->CONST->{'maxRetryattempt'}.' '.Constants->CONST->{'restoreLocNoChange'}.qq( "$resetRestoreLocation".$lineFeed);
			}else{
				print Constants->CONST->{'maxRetryattempt'}.' '.Constants->CONST->{'restoreLocNoChange'}.qq( "$resetRestoreLocation".$lineFeed);
			}
		}
	}else{
		print Constants->CONST->{'restoreLocNoChange'}.qq( "$restoreLocation".$lineFeed);
	}
	$restoreLocation=~s/^\'//;
	$restoreLocation=~s/\'$//;
	putParameterValue(\"RESTORELOCATION", \"$restoreLocation", $confFilePath);
	holdScreen2displayMessage(2);
}
#****************************************************************************************************
# Subroutine Name         	: getConfirmationChoice.
# Objective               	: Subroutine to get confirmation choice from user. 
# Modified By				: Dhritikana
#*****************************************************************************************************/
sub getConfirmationChoice {
	$_[0] =~ s/.*\/(.*?)/$1/;	
	my $finalMessage  = $_[0] eq Constants->FILE_NAMES->{accountSettingsScript} ? $_[1] : Constants->CONST->{'TryAgain'};
#	$finalMessage = q(Please try to login using 'Login.pl');
	my $confirmChoice = undef;
	my $count = 0;
	while(!defined $confirmChoice) {
		$count++;
		if($count eq 5) {
			print "Your maximum retry attempts reached. $finalMessage \n";
			exit;
		}
		print $whiteSpace.Constants->CONST->{'EnterChoice'};
		$confirmChoice = <STDIN>;
		chop $confirmChoice;
		
		$confirmChoice =~ s/^\s+//;
		$confirmChoice =~ s/\s+$//;
		
		if($confirmChoice =~ m/^\w$/ && $confirmChoice !~ m/^\d$/) {
			if($confirmChoice eq "y" || $confirmChoice eq "Y" ||
				$confirmChoice eq "n" || $confirmChoice eq "N") {
			}
			else {
				$confirmChoice = undef;
				print Constants->CONST->{'InvalidChoice'} if ($count < 4);
			} 
		}
		else {
			$confirmChoice = undef;
			print Constants->CONST->{'InvalidChoice'} if ($count < 4);
		}
	}
	
#	print "\n";
	return $confirmChoice;
}

#****************************************************************************
# Subroutine Name         : getLocationInput
# Objective               : Get location input from terminal. 
# Added By                : Dhritikana
#****************************************************************************/
sub getLocationInput {
	my $flag = $_[0];
	my $input=<>;
	chomp($input);
	if($input eq "") {
		return $input;
	}
	$input =~ s/^\s+\/+|^\/+/\//g; ## Replacing starting "/"s with one "/"
	$input =~ s/^\s+//g; ## Removing Blank spaces
	$input =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root 
	return $input;
}

#****************************************************************************************************
# Subroutine Name                       : writeToTrace
# Objective                                     : This subroutine writes to log
# Added By                                      : Sabin Cheruvattil - 2016-06-01
#****************************************************************************************************
sub writeToTrace
{
	open LOG_TRACE_HANDLE, ">>", $_[0];
	($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	$year           += 1900;
	$mon            += 1;
	$mday           = (($mday < 10)? "0" . $mday : $mday);
	$mon            = (($mon < 10)? "0" . $mon : $mon);
	my $date        = strftime "%Y/%m/%d %H:%M:%S", localtime;

	chomp($httpuser);
	my $logContent = "[$date][$httpuser]". $_[1];
	print LOG_TRACE_HANDLE $logContent;
	close(LOG_TRACE_HANDLE);
}

#****************************************************************************************************
# Subroutine Name                       : traceLog
# Objective                                     : This subroutine helps to add log
# Added By                                      : Sabin Cheruvattil - 2016-05-10
# usage                                         : traceLog("Something goes to log", __FILE__, __LINE__);
#****************************************************************************************************
sub traceLog
{
	my $traceDir = "$usrProfilePath/$userName/.trace";

	if(!-d $traceDir) {
		my $mkRes = `mkdir -p $traceDir $errorRedirection`;
                Chomp(\$mkRes);
                if ($mkRes !~ /Permission denied/){
                         changeMode($idriveSerivePath);
                }else{
                        $mkRes =~ /mkdir:\s+(.*?)$/s;
                        print qq{\n$1\n};
                        exit;
                }
	}
	my $traceFileName = "$traceDir/".Constants->CONST->{'tracelog'};
	if((-s $traceFileName) >= (2*1024*1024)) {
			my $date = localtime();
			my $tempTrace = $traceFileName . "_" . $date;
			move($traceFileName, $tempTrace);
	}
	
	if(!-e $traceFileName){
		writeToTrace($traceFileName, "IDrive Username: " . $userName . "\n");
	}
	my ($logData, $fileName, $lineNumber)  = @_;
	opendir(DIR, $traceDir);
	@files = grep(/traceLog.txt_/, readdir(DIR));
	closedir(DIR);

	my $remFileCount = scalar(@files) - 5;
	while($remFileCount > 0) {
		unlink "$traceDir/" . pop(@files);
			$remFileCount--;
	}

	@fNameArr = split("/", $fileName);
	$logContent = "[$fNameArr[-1]][Line: $lineNumber] $logData\n";
	writeToTrace($traceFileName, $logContent);
}

#*********************************************************************************************
#Subroutine Name       : findUserLocation
#Objective             : Provides path where all the scripts are saved.
#Added By              : Abhishek Verma
#*********************************************************************************************/
sub findUserLocation{
         my $scriptFilePath = __FILE__;
         chomp(my $presentWorkingDir =`pwd`);
         $scriptFilePath =~ s/^\.\/// if ($scriptFilePath =~ /^\.\//);
	 
         my $scriptLoc = $scriptFilePath =~/(.*)\//?$1:$presentWorkingDir;
		 if ($scriptLoc ne ''){
			$scriptLoc = $scriptLoc =~ /^\//?$scriptLoc:$presentWorkingDir."/".$scriptLoc;
         }
		else{	
			$scriptLoc = $presentWorkingDir;
		}

#        This statement will check if script location path contains '..' pattern.
         if ($scriptLoc =~ /\.\./g){
                $scriptLoc = getAbsolutePath(split('/',$scriptLoc)); #getAbsolutePath subroutine will return the absolute path for the given relative path
         }
         return $scriptLoc;
 }
#**********************************************************************************************
#Sbroutine Name         : getAbsolutePath
#Objective              : retuns Absolute path for given relative path
#Usage                  : getAbsolutePath(LIST); ~List should not be hash~. eg:@relativePath = '/a/b/c/d/../../e/f/../g' AbsolutePath: /a/b/e/g
#Added By               : Abhishek Verma
#***********************************************************************************************
sub getAbsolutePath{
         for (my $i=0; $i<=$#_; $i++){
                 if ($_[$i] eq '..'){
                         splice (@_, $i-1,2);
                         $i=$i-2;
                 }
         }
         return join ('/',@_);
}
#**********************************************************************************************
#Sbroutine Name         : uniqueData
#Objective              : retuns unique data from given array.
#Usage                  : uniqueData(ARRAY);
#Added By               : Abhishek Verma.
#***********************************************************************************************
sub uniqueData{
        my %uniqueEmail = map{ $_ => 1 } @_;
        return sort {$a cmp $b} keys %uniqueEmail;
}

#**********************************************************************************************
#Sbroutine Name         : getValidateIPaddress
#Objective              : It takes IP address input from user and returns valid/invalid IP address.
#Usage                  : getValidateIPaddress(NUMBER_OF_REPETATION); eg getValidateIPaddress(3); if you want user to repeat or retry 3 times.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub getValidateIPaddress{
        my $exitStatus = shift;
        print Constants->CONST->{'AskProxyIp'}; 
        my $ipAddress = getInput();
        unless ($ipAddress =~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/){
                print Constants->CONST->{'InvalidIP'}.qq( $ipAddress \n);
                $ipAddress = $exitStatus ? getValidateIPaddress(--$exitStatus) : Constants->CONST->{'InvalidIP'}.qq( $ipAddress);
        }else{
                $ipAddress = qq(Valid IP Address  $ipAddress);
        }
        return $ipAddress;
}
#**********************************************************************************************
#Sbroutine Name         : getValidatePortNumber
#Objective              : It takes port number input from user and returns valid/invalid port number.
#Usage                  : getValidatePortNumber(NUMBER_OF_REPETATION); eg getValidatePortNumber(3); if you want user to repeat or retry 3 times.
#Added By               : Abhishek Verma.
#***********************************************************************************************/

sub getValidatePortNumber{
        my $exitStatus = shift;
        print Constants->CONST->{'AskProxyPort'};
	my $portNumber = getInput();
        unless ($portNumber =~ /^(0|[1-9][0-9]{0,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/){
                print Constants->CONST->{'InvalidPort'}.qq( $portNumber. );
                $portNumber = $exitStatus ? getValidatePortNumber(--$exitStatus) : Constants->CONST->{'InvalidPort'}.qq( $portNumber);
        }else{
                $portNumber = qq(Valid port number : $portNumber);
        }
        return $portNumber;

}

#**********************************************************************************************
# Subroutine Name         : getProxyDetails
# Objective               : Get proxy informations from user and form wget Command based on it. 
# Added By                : Dhritikana
# Modified By 		  : Abhishek Verma 22/12/16 added functions getValidateIPaddress(3),getValidatePortNumber(3) and error handling for proxy details.
#**********************************************************************************************/
sub getProxyDetails {
	my $confirmationChoice = shift;
	if ($confirmationChoice !~ /^y$/i){
		print $lineFeed.$lineFeed.Constants->CONST->{'AskIfProxy'}.$whiteSpace;
		$confirmationChoice = getConfirmationChoice();
	}
	
	if($confirmationChoice eq "n" || $confirmationChoice eq "N") {
		$proxyOn = 0;
		$proxyStr = '';
	} elsif( $confirmationChoice eq "y" || $confirmationChoice eq "Y") {
		$proxyIp = getValidateIPaddress(3);
		if ($proxyIp =~ /^Valid\s+IP\s+Address(.*?)$/ ){
			$proxyIp = $1; 
			$proxyIp =~ s/^\s+|\s+$//g;
			$proxyPort = getValidatePortNumber(3);
			if ($proxyPort =~ /^Valid\s+port\s+number\s*:\s*(.*?)$/ ){
				$proxyPort = $1;
				$proxyPort =~ s/^\s+|\s+$//g;				
				print Constants->CONST->{'AskProxyUname'};
				$proxyUsername = getInput();
				print Constants->CONST->{'AskProxyPass'};
				system('stty','-echo');
				$proxyPassword = getInput();
				system('stty','echo');
				$proxyOn = 1;
				$proxyStr = "$proxyUsername:$proxyPassword\@$proxyIp:$proxyPort";
				foreach ($proxyUsername, $proxyPassword) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
			}else{
				$proxyOn = 0;
				print $lineFeed.Constants->CONST->{'portError'};
	                        my $confirmationChoice = getConfirmationChoice();
        	                if ($confirmationChoice eq 'n' or $confirmationChoice eq 'N'){
                	                exit 0; 
                        	}else{
                                	$proxyPort = undef;
                        	}
			}
		}else{
			$proxyOn = 0;
			print $lineFeed.Constants->CONST->{'proxyError'};
			my $confirmationChoice = getConfirmationChoice();
			if ($confirmationChoice eq 'n' or $confirmationChoice eq 'N'){
				exit 0;
			}else{
				$proxyIp = undef;
			}
			
		}
	}
	print "\n\n" if ($_[0] eq '');
	return $proxyOn;
}
#**********************************************************************************************
#Sbroutine Name         : displayFinalSummery(SCALAR,SCALAR);
#Objective              : It display the final summery after the backup/restore job has been completed.
#Usage                  : displayFinalSummery(JOB_TYPE,FINAL_SUMMARY_FILE_PATH);
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub displayFinalSummary{
	my ($jobType,$finalSummaryFile) = @_;
	my $errString = undef;
	if (open(FS,'<',$finalSummaryFile)){#FS file handel means (F)ile (S)ummary.
		chomp(my @fileSummary = <FS>);
		close(FS);
		$errString	= pop (@fileSummary) if ($#fileSummary > 8);
		$jobStatus	= pop (@fileSummary);
		my $logFilePath = pop (@fileSummary);
		my $fileSummary = join ("\n",@fileSummary);
#		if ($jobStatus eq 'SUCCESS' or $jobStatus eq 'SUCCESS*'){
		if ($jobStatus eq 'SUCCESS'){
			$jobStatus = qq($jobType has completed.); 
		}elsif($jobStatus eq 'FAILURE' or $jobStatus eq 'ABORTED'){
			$jobStatus = defined ($errString) ? $errString : qq($jobType has failed.);
		}	
		print qq(\n$jobStatus\n$fileSummary\n\n$logFilePath\n);
		unlink($finalSummaryFile);
	}#else{
	#	print qq(\nUnable to print status summary. Reason: $!\n);
	#}
}
#**********************************************************************************************
#Sbroutine Name         : writeToFile(FILE_NAME,CONTENT_TO_WRITE);
#Objective              : This function used to write the content in file.
#Usage                  : writeToFile(FILE_NAME,CONTENT_TO_WRITE); eg: writeToFile($fileName,$content)
#			  Where:
#			  $fileName: File name/File name with location.
#			  $content : Content which you want to write in file.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub writeToFile{
	my ($fileName,$content)=@_;
	open (FS,'>',$fileName) or die qq(Unable to open file. Reason: $!);
	print FS $content;
	close (FS);
}
#**********************************************************************************************
#Sbroutine Name         : ifUbuntu(CHECK_IF_UBUNTU);
#Objective              : This function will set CHECK_IF_UBUNTU(means perl scalar having any name.) to 1 if the OS on which script is running is Ubuntu.
#Usage                  : ifUbuntu(CHECK_IF_UBUNTU);
#                         Where:
#                         $checkIfUbuntu is a global variable which is initially set to zero.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub ifUbuntu{
        my $checkUbuntu = 0;
        if (`cat /proc/version` =~ /ubuntu/){
                $checkUbuntu = 1;
        }
        return $checkUbuntu;
}
#**********************************************************************************************
#Sbroutine Name         : comapareLocation(LOCATION_FROM_CONF_FILE,LOCATION_INPUT_BY_USER);
#Objective              : This function will return 1 if LOCATION_FROM_CONF_FILE and LOCATION_INPUT_BY_USER are equal, otherwise 0.
#Usage                  : comapareLocation($previousLocation,$currentLocation);
#                         Where:
#                         $previousLocation = LOCATION_FROM_CONF_FILE
#			  $currentLocation  = LOCATION_INPUT_BY_USER
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub comapareLocation{
	my $previousLocation	= shift;
	my $currentLocation	= shift;
	my $locationStatus	= 0;
	clearSpecialChar(\$previousLocation);
	clearSpecialChar(\$currentLocation);
	if ($previousLocation eq $currentLocation){
		$locationStatus = 1;
	}
	return $locationStatus;
}
#**********************************************************************************************
#Sbroutine Name         : isRunningJob(PID_LOCATION);
#Objective              : This function will return 1 if pid.txt file exists, otherwise 0.
#Usage                  : isRunningJob($pidPath);
#                         Where:
#                         $pidPath = PID_LOCATION
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub isRunningJob{
	my $jobRunningFile	= shift;
	my $jobRunningStatus	= 0;
	if (-e $jobRunningFile){
		$jobRunningStatus = 1;
	}
	return $jobRunningStatus;
}
#**********************************************************************************************
#Sbroutine Name         : runningJobHandler(JOB_TYPE,JOB_MODE,USERNAME,USER_PROFILE_PATH);
#Objective              : This function will allow to change the backup/restore from location only if no scheduled backup / restore job is running. if any of previously mentioned job is runnign then it will first ask for the termination of running job then allow to change location.
#Usage                  : runningJobHandler($jobType,$jobMode,$username,$userProfilePath);
#                         Where:
#                         $jobType		: Backup/Restore
#			  $jobMode		: Scheduled/Manual (Manual if in future you allow to run multiple manual job)
#			  $username		: UserName
#			  $userProfilePath	:service directory path
#Result			: return 0 (means no change in location, go with older location) and return 1 (means change the location)
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub runningJobHandler{
	my ($jobType,$jobMode,$username,$userProfilePath) = @_;
	my $pidPath = $userProfilePath.'/'.$username.'/'.$jobType.'/'.$jobMode.'/pid.txt';
	my $changeLocationStatus = 0;
	if (isRunningJob($pidPath)){
		print qq{\nChanging $jobType location will terminate $jobMode $jobType in progress ... Do you want to continue(y/n)? };
		my $choice = getConfirmationChoice();
		if(($choice eq "y" || $choice eq "Y")) {
			print qq(\nTerminating your $jobMode $jobType job. Please Wait ... $lineFeed);
			my $jobTerminationScript = "$userScriptLocation/".Constants->FILE_NAMES->{jobTerminationScript};
			my $JobTermCmd = "perl  $jobTerminationScript $jobType $username Manual";	
			my $res = system($JobTermCmd);
			if($res != 0){
                        	traceLog("Error in terminating Manual Restore job.", __FILE__, __LINE__);
                	}else{
#				print qq(\n $jobType ).Constants->CONST->{'JobTerminateMessage'}.$lineFeed;
				$changeLocationStatus = 1;
			}
		}
	}else{
		$changeLocationStatus = 1;
	}
	return $changeLocationStatus;
}
#**********************************************************************************************
#Sbroutine Name         : createDefaultRestoreLoc(DEFAULT_RESTORE_LOCATION);
#Objective              : This function will create default restore location if user not provide any restore location or if user location has no permission to be created in a particular directory.
#Usage                  : createDefaultRestoreLoc($defaultRestoreLocation)
#                         Where:
#                         $defaultRestoreLocation = USER_PROFILE_PATH/USER_NAME/Restore_Data
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub createDefaultRestoreLoc{
        my $location    = shift;
        print Constants->CONST->{'defaultRestLocMess'}.qq( "$location").$lineFeed;
        my $res = createDirectory($location,"DEFAULT");
	return $res;
}
#**********************************************************************************************
#Sbroutine Name         : clearSpecialChar(REFERENCE_TO_VARIABLE);
#Objective              : This function will clear the special characters from the variable content.
#Usage                  : clearSpecialChar(\$someVariable)
#                         Where:
#                         $someVariable = variable name from where special characters should be removed.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub clearSpecialChar{
	${$_[0]} =~ s/^.\///;
        ${$_[0]} =~ s/^\'//;
        ${$_[0]} =~ s/\'$//;
        ${$_[0]} =~ s/^\s+//;
        ${$_[0]} =~ s/\s+$//;
	${$_[0]} =~ s/^\///;
	${$_[0]} =~ s/\/$//;
}
#**********************************************************************************************
#Sbroutine Name         : createDirectory(MULTI/SINGLE_LEVEL_DIR_LOC,['DEFAULT']);
#Objective              : This function will take multi/single level directory location and create directory/directories accordingly. if directory location is default(i.e. to be created in side service folder, mention the optional key 'DEFAULT' as second parameter)
#Usage                  : createDirectory(\$directoryLocation,'DEFAULT') or createDirectory(\$directoryLocation)
#                         Where:
#                         $directoryLocation = Multi/Single level directory location.
#			  'DEFAULT'	     = Optional parameter/ if dir loc passed in first parameter is a default service path. Then this parameter is passed.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub createDirectory {
        my $location            = shift;
        my $defaultDirFlag      = shift;
        my $result=q();
        if (isSingleLevelDirectory($location) or ($defaultDirFlag eq 'DEFAULT')){
                $result = `mkdir $location $errorRedirection`;
        }else{
                $result = `mkdir -p $location $errorRedirection`;
        }
        return $result;
}
#**********************************************************************************************
#Sbroutine Name         : isSingleLevelDirectory(USER_DIR_LOCATION);
#Objective              : This function will check if given user location is multilevel directory or single level directory. 
#			  returns 1 : For single level directory. Eg: /dirLocation
#			  returns 0 : For multi level directory.  Eg: /home/user/storage/primary/restoreData
#Usage                  : isSingleLevelDirectory($restoreLocation);
#                         Where:
#                         $restoreLocation = Any location which needs to be created.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub isSingleLevelDirectory{
        my $location = shift;
        clearSpecialChar(\$location);
        my $isSingleLevel = 1;
        if (scalar(grep /\S/,split('/',$location)) > 1){
                $isSingleLevel = 0;
        }
        return $isSingleLevel;
}

#**********************************************************************************************
#Sbroutine Name         : hasWritePermission();
#Objective              : This function will create a file in directory which already exists and check if the directory is having write permission or not.
#                         returns 1 : if directory having write permission.
#                         returns 0 : if directory is not having write permission.
#Usage                  : hasWritePermission();
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub hasWritePermission{
        my $testPath    = $restoreLocation."Idrivetest.txt";
        my $isWrite     = 0;
        if (open FILE, ">$testPath"){
                $isWrite = 1;
                close FILE;
                unlink $testPath;
        }
        return $isWrite;
}
#**********************************************************************************************
#Sbroutine Name         : isDefaultRestoreLoc(RESTORE_LOCATION);
#Objective              : This function will check if the restore location is default or not.
#                         returns 'DEFAULT' : if restore location is default.
#			  returns ''	    : if restore location is not default.
#Usage                  : isDefaultRestoreLoc($restoreLocation);
#                         Where:
#                         $restoreLocation = Any location which needs to be checked.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub isDefaultRestoreLoc{
	my $location	= shift;
	my $defaultKey	= q();
	if ($location =~ /\/?$usrProfilePath\/$userName\/Restore_Data\/?$/){
		$defaultKey = q(DEFAULT);
	}
	return $defaultKey;
}
#**********************************************************************************************
#Sbroutine Name         : setRestoreLocation(RESTORE_LOCATION);
#Objective              : This function will set restore location directory, which contains all the files that are restored.
#Usage                  : setRestoreLocation($restoreLocation);
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub setRestoreLocation{
        $restoreLocation		= ($_[0] ne '') ? $_[0] : $_[1];
	my $defaultRestoreLocation	= $_[1];
	my $defaultKey	  = isDefaultRestoreLoc($restoreLocation);
	my $userLocMessage= ($defaultKey eq 'DEFAULT')? Constants->CONST->{'defaultRestLocMess'}.qq( "$defaultRestoreLocation" $lineFeed) : Constants->CONST->{'restoreLocCreation'}.$lineFeed;
	my $res = q();
        $restoreLocation .= '/' if(substr($restoreLocation, -1, 1) ne "/");
        if (!-d $restoreLocation){
                if( -f $restoreLocation or -l $restoreLocation or -p $restoreLocation or -S $restoreLocation or -b $restoreLocation or -c $restoreLocation or -t $restoreLocation) {
                        print Constants->CONST->{'InvRestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
                        $restoreLocation = $defaultRestoreLocation;
                        $res = createDefaultRestoreLoc($restoreLocation);
                }else{
                        print $userLocMessage;
                        $restoreLocation = '/'.$restoreLocation if(substr($restoreLocation, 0, 1) ne "/");
                        $restoreLocation = qq('$restoreLocation');
                        $res = createDirectory($restoreLocation,$defaultKey);
                }
        }else{
                if (hasWritePermission()){
			print qq(Restore Location "$restoreLocation" exists.$lineFeed) if ($_[2] eq '');
                        print Constants->CONST->{'RestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
			$res = q(EXISTS);
                }else{
                        print Constants->CONST->{'InvRestoreLoc'}." \"$restoreLocation\". Reason: $!\n";
                        $restoreLocation = $defaultRestoreLocation;
                        $res = createDefaultRestoreLoc($restoreLocation);
                }
        }
	$res='' if ($res =~ /File exists/);
	return $res;
}
#*********************************************************************************************************
#Subroutine Name        : getRestoreLocation()
#Objective              : Get the restore location from user.
#Usage                  : getRestoreLocation();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getRestoreLocation{
	$_[0] =~ s/.*\/(.*?)/$1/ if ($_[0] =~ /\/\w/);
	clearSpecialChar(\$_[0]);
	my $userMessage = $_[0] eq Constants->FILE_NAMES->{accountSettingsScript} ? $lineFeed.Constants->CONST->{'AskRestoreLoc'} 
							: $_[1];
        print $userMessage;
        $restoreLocation = getLocationInput("rloc");
}
#**********************************************************************************************
#Sbroutine Name         : Chomp(REFERENCE_TO_VARIABLE);
#Objective              : This function will clear the space from beginning and end of content.
#Usage                  : Chomp(\$someVariable)
#                         Where:
#                         $someVariable = variable name from where space should be removed.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub Chomp{
        ${$_[0]} =~ s/^[\s+\t+]//;
        ${$_[0]} =~ s/[\s+\t+]$//;
}

#****************************************************************************
# Subroutine Name         : cancelProcess
# Objective               : Cleanup if user cancel, parameter contains the directory location which you want to remove or some files if you want to unlink.
# usage                   :  cancelProcess() # for default cleanup
# Added By                : Dhritikana
# Modified By             : Abhishek Verma
#****************************************************************************/
sub cancelProcess {
	#Default Cleanup
        system('stty','echo');
        unlink($idevsOutputFile);
        unlink($idevsErrorFile);
        exit 1;
}
#****************************************************************************
# Subroutine Name         : removeFilesFolders
# Objective               : removeFilesFolders, removes and cleans the gives folders and files. 
# usage                   : removeFilesFolders([DIR_NAME],[path_to_unlink])
#                           [DIR_NAME]          : list of directory names
#                           [path_to_unlink]    : list of paths you want to unlink.
# Added By                : Abhishek Verma
#****************************************************************************/
sub removeFilesFolders{
	my @dirNames    = defined ($_[0]) ? @{$_[0]} : ();
	my @pathUnlink  = defined ($_[1]) ? @{$_[1]} : ();
	foreach (@dirNames){
		rmtree($_);
	}
	foreach (@pathUnlink ){
		unlink($_);
	}
}
#****************************************************************************
# Subroutine Name         : changeMode
# Objective               : This will change the access permission of directory.
# Usgae                   : changeMode(LOCATION_NAME)
#			  : LOCATION_NAME = Name of the location whose permission you want to change.
# Added By                : Abhishek Verma.
#****************************************************************************/
sub changeMode{
	my $res	= `chmod -R 777 $_[0] $errorDevNull`;
	return $res;
}
#*******************************************************************************************************
# Subroutine Name         : checkEvsStatus
# Objective               : To check EVS status and take action.
# Usage                   : checkEvsStatus()
# Added By                : Abhishek Verma.
#********************************************************************************************************/
sub checkEvsStatus{
	my $jobType = defined($_[0]) ? $_[0] : undef; 
        my $err_string = checkBinaryExists();
        if($err_string ne "") {
                if ($taskType eq "Scheduled"){
                        $mail_content = qq{\n$err_string\nAfter complition, run scheduled $jobType Job again.};
                        my $subjectLine = "$taskType $jobType Email Notification "."[$userName]"." [Failed $jobType]";
                        $status = "FAILURE";
			sendMail($subjectLine);
                }
                print qq($err_string);
                traceLog($err_string."$lineFeed", __FILE__, __LINE__);
                exit 1;
        }
}
#****************************************************************************
# Subroutine Name         : headerDisplay
# Objective               : To display header information
# Usgae 		  : headerDisplay($callingScript)
# 			  : where, $callingScript = From which script headerDisplay subroutine has been called.
# Added By                : Abhishek Verma.
#****************************************************************************/
sub headerDisplay{
	my $callingScript = shift;
	$callingScript =~ s/.*\/(.*?)/$1/ if ($callingScript =~ /\/\w/);
	clearSpecialChar(\$callingScript);
	my $updateAvailMessage = qq(================================================================================ \nVersion : );
	$updateAvailMessage   .= Constants->CONST->{'Version'};
	$updateAvailMessage   .= qq(                    Developed By: $appMaintainer);
	$updateAvailMessage   .= qq(\n----------------                    --------------------------------------------\n);
	$updateAvailMessage   .= qq(Logged in user :                    );
	$updateAvailMessage   .= $displayCurrentUser eq '' ? "No Logged In User":$displayCurrentUser; 
	my %quotaDetails = getQuotaDetails();
#TBE : ENH-004 - Get Quota, compute remaining quota
#	if (scalar (keys %quotaDetails) == 2){  #TBE : ENH-004 - fix
		my $totalQuota = convertFileSize($quotaDetails{totalQuota});
		my $usedQuota = convertFileSize ($quotaDetails{usedQuota});
		my $remaining = convertFileSize ($quotaDetails{remainingQuota});			#TBE : ENH-004
		$updateAvailMessage .= qq(\n----------------                    --------------------------------------------\n);
		$updateAvailMessage .= qq(Quota Display  :  $remaining(free)/$usedQuota(used)/$totalQuota(total));
#	}
	if ($callingScript ne Constants->FILE_NAMES->{checkForUpdateScript} and !isUpdateAvailable()){ # Dont want to call subroutine isUpdateAvailable() in case of calling script is Check_For_Update.pl
		$updateAvailMessage .= qq(\n--------------------------------------------------------------------------------\n);
		$updateAvailMessage .= qq(A new update is available. Run ).Constants->FILE_NAMES->{checkForUpdateScript}.qq( to update to latest package.);
	}
	$updateAvailMessage .= qq(\n================================================================================ \n);
	print $updateAvailMessage;
}
#****************************************************************************
# Subroutine Name         : askRootPassword($user,$evsUser,\$password)
# Objective               : To ask the root password.
# Usgae                   : askRootPassword($user,$evsUSer,$password)
#			  : $user 	: username of system who is logged in.
#			  : $evsUser 	: username with which EVS was fired.
#			  : $password	: variable ref to hold the value entered by user.
# Added By                : Abhishek Verma.
#****************************************************************************/
sub askRootPassword{
	my $user 	= shift;
	my $evsUser 	= shift;
	my $password	= shift;
	my $sudoer	= 'root';
	$sudoer = 'sudo' if(ifUbuntu());
	if ($user ne $evsUser){
		print qq(\nEnter $sudoer password for $user: );
		system('stty','-echo');
		chomp(${$password} = <STDIN>);
		system('stty','echo');
	}	
}
#****************************************************************************
#Subroutine Name         : createServicePath(SERVICE_PATH_INPUT)
#Objective               : To create service path.
#Usgae                   : createServicePath($servicePath)
#                        : $servicePath       : service path input by user. 
#Added By                : Abhishek Verma.
#****************************************************************************/
sub createServicePath{
	my $servicePath = shift;
	my $res = '';
	my $serviceDir = $appTypeSupport eq 'ibackup' ? 'ibackup' : 'idrive';
	if (${$servicePath} ne ''){
		if ((split('/',${$servicePath}))[-1] !~ /^(idrive|ibackup)\/?$/){
			${$servicePath} = (${$servicePath} =~ /\/$/) ? ${$servicePath}.$serviceDir : ${$servicePath}.'/'.$serviceDir;
		}
		$res = (-d ${$servicePath}) ? 'exists' : createDirectory(${$servicePath});	
	}
	return $res;
}
#****************************************************************************
#Subroutine Name         : validateUserName(USER_NAME)
#Objective               : To validate user name given by end user.
#Usgae                   : validateUserName($userName)
#                        : $userName       : Input user name by end user.
#Added By                : Abhishek Verma.
#****************************************************************************/
=comment
        ### Rules for valid username ###
        1)It should be min 4 to max 20 character long.
        2)It should contain combination of a-z, 0-9 and underscore.
        3)It can be a valid email address syntax.
=cut
                        
sub validateUserName{
	my $validUserPattern = 0;
	if ($_[0] =~ /^(?=.{4,20}$)(?!.*[_]{2})(?!\s+)[a-z0-9_]+$/){
		$validUserPattern = 1;
	}elsif(validEmailAddress($_[0])){
		$validUserPattern = 1;
	}
	return $validUserPattern;
}

#****************************************************************************
#Subroutine Name         : validatePassword(PASSWORD)
#Objective               : To validate password i.e. it should be min 6 character and maximum 20 character long.
#Usgae                   : validatePassword($password)
#                        : $password       : Input password by end user.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub validatePassword{
	($_[0] =~ /^(?=.{4,20}$)(?!.*\s+.*)(?!.*[\:\\]+.*)/) ? return 1 : return 0;
}

#****************************************************************************
#Subroutine Name         : isUpdateAvailable 
#Objective               : To check if update is available, create a file with .updateVersionInfo and write the current version.
#Usgae                   : isUpdateAvailable()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub isUpdateAvailable{
	my $check4updateScript = $userScriptLocation.'/'.Constants->FILE_NAMES->{checkForUpdateScript}.' availUpdate';
	my $updateAvailStats = '';
	if (-e $userScriptLocation.'/.updateVersionInfo' and -s $userScriptLocation.'/.updateVersionInfo' > 0){
		return 0; #True
	}else{
	#	chomp($updateAvailStats = `perl $check4updateScript $usrProfileDir`);
		open (CHECKUPDATE,"$check4updateScript $usrProfileDir|") or die "Failed to create process: $!\n"; #Making Asynchronous call to Check_For_Update.pl.
		if (-e $userScriptLocation.'/.updateVersionInfo' and -s $userScriptLocation.'/.updateVersionInfo' > 0){
			return 0;
		}else{
			return 1;
		}
	}
}

#=====================================================================================================================
#TBE : ENH-004 - Quota remaining
#****************************************************************************
#Subroutine Name         : getQuota_HashTable 
#Objective               : This function will get fresh quota information and provide remaining byte count
#Usage                   : getQuota_HashTable() => %
#Added By                : Taryck BENSIALI
#****************************************************************************/
sub getQuota_HashTable(){
	my $encType = checkEncType(1);
	my $getQuotaUtfFile = getOperationFile($getQuotaOp,$encType);
	$getQuotaUtfFile =~ s/\'/\'\\''/g;
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$getQuotaUtfFile."'".$whiteSpace.$errorRedirection;
	my $commandOutput = `$idevsutilCommandLine`;
	unlink($getQuotaUtfFile);
	parseXMLOutput(\$commandOutput);
	if (($evsHashOutput{message} eq 'SUCCESS') and ($evsHashOutput{totalquota} =~/\d+/) and ($evsHashOutput{usedquota} =~/\d+/)){
		$evsHashOutput{usedquota} =~ s/(\d+)\".*/$1/isg;
		$evsHashOutput{remainingquota} = $evsHashOutput{totalquota} - $evsHashOutput{usedquota};
	}
	return %evsHashOutput;
}

#****************************************************************************
#Subroutine Name         : WriteQuotaFile
#Objective               : This function will create a quota.txt file based on the quota details provided 
#Usage                   : WriteQuotaFile()
#Added By                : Taryck BENSIALI
#****************************************************************************/

sub WriteQuotaFile($$$$$){
	my $FileName = shift;
	my $filePermission = shift;
	my $totalquota  = shift;
	my $usedquota = shift;
	my $remainingquota = shift;
	
	open (AQ,'>',$FileName) or (traceLog($lineFeed.Constants->CONST->{'FileCrtErr'}.$enPwdPath."failed reason: $! $lineFeed", __FILE__, __LINE__) and die);# File handler AQ means Account Quota.
	chmod $filePermission,$FileName;
	if ($totalquota =~/\d+/ and $usedquota =~ /\d+/ and $remainingquota =~ /\d+/){
		print AQ 'totalQuota=' . $totalquota . "\n";
		print AQ 'usedQuota=' . $usedquota . "\n";
		print AQ 'remainingQuota=' . $remainingquota . "\n";
	}
	close AQ;
}
#=====================================================================================================================#****************************************************************************
#Subroutine Name         : getQuotaForAccountSettings 
#Objective               : This function will create a quota.txt file based on the quota details which is received during Account setting. 
#Usgae                   : getQuotaForAccountSettings()
#Added By                : Abhishek Verma.
#****************************************************************************/

sub getQuotaForAccountSettings{
#=====================================================================================================================
#TBE : ENH-004 - Quota remaining
	my $totalquota = $evsHashOutput{quota};
	my $usedquota = $evsHashOutput{quota_used};
	my $remainingquota = $totalquota - $usedquota;
	WriteQuotaFile( $usrProfileDir.'/.quota.txt',
					$filePermission,
					$totalquota,
					$usedquota,
					$remainingquota);
# Mutualized code
	# open (AQ,'>',$usrProfileDir.'/.quota.txt') or (traceLog($lineFeed.Constants->CONST->{'FileCrtErr'}.$enPwdPath."failed reason: $! $lineFeed", __FILE__, __LINE__) and die);# File handler AQ means Account Quota.
	# chmod $filePermission,$usrProfileDir.'/.quota.txt';
	# if ($evsHashOutput{quota} =~/\d+/ and $evsHashOutput{quota_used} =~ /\d+/){
		# $evsHashOutput{quota_used} =~ s/(\d+)\".*/$1/isg;
		# print AQ "totalQuota=$evsHashOutput{quota}\n";
		# print AQ "usedQuota=$evsHashOutput{quota_used}\n";
		# print AQ "remainingQuota=" . $remainingquota . "\n";
	# }
	# close AQ;
#=====================================================================================================================
}

#****************************************************************************
#Subroutine Name         : getQuota 
#Objective               : This function will create a quota.txt file based on the quota details which is received during  final backup.
#Usgae                   : getQuota()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getQuota{
#=====================================================================================================================
#TBE : ENH-004 - Quota remaining
	my %evsHashOutput = getQuota_HashTable();
# Mutualized code
#	my $encType = checkEncType(1);
#	my $getQuotaUtfFile = getOperationFile($getQuotaOp,$encType);
#	$getQuotaUtfFile =~ s/\'/\'\\''/g;
#        $idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$getQuotaUtfFile."'".$whiteSpace.$errorRedirection;
#	my $commandOutput = `$idevsutilCommandLine`;
#        unlink($getQuotaUtfFile);
#	parseXMLOutput(\$commandOutput);
#=====================================================================================================================
	if (($evsHashOutput{message} eq 'SUCCESS') and ($evsHashOutput{totalquota} =~/\d+/) and ($evsHashOutput{usedquota} =~/\d+/)){
#=====================================================================================================================
#TBE : ENH-004 - Quota remaining
		WriteQuotaFile( $usrProfileDir.'/.quota.txt',
						$filePermission,
						$evsHashOutput{totalquota},
						$evsHashOutput{usedquota},
						$evsHashOutput{remainingquota});
# Mutualized code
		# open (AQ,'>',$usrProfileDir.'/.quota.txt') or (traceLog($lineFeed.Constants->CONST->{'FileCrtErr'}.$enPwdPath."failed reason: $! $lineFeed", __FILE__, __LINE__) and die);# File handler AQ means Account Quota.
		# chmod $filePermission,$usrProfileDir.'/.quota.txt';
		# $evsHashOutput{usedquota} =~ s/(\d+)\".*/$1/isg;
		# print AQ "totalQuota=$evsHashOutput{totalquota}\n";
		# print AQ "usedQuota=$evsHashOutput{usedquota}\n";
		# close AQ;
#=====================================================================================================================
	}
}
#****************************************************************************
#Subroutine Name         : getQuotaDetails 
#Objective               : This function will read quota.txt file for particular user.
#Usgae                   : getQuotaDetails()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getQuotaDetails{
	my %quotaDetails = ();
	if($displayCurrentUser ne ''){
		my $usrDir = "$usrProfilePath/$displayCurrentUser";
		if (!-e $usrDir.'/.quota.txt'){
			if($userName eq '' or $usrProfileDir eq ''){
				$userName = $displayCurrentUser;
	        	        loadUserData();
			}
			getQuota($0);
		}
		%quotaDetails = readQuota($usrDir.'/.quota.txt');
		#Below if is done handling in case if user will aulter the data in quota.txt or remove this file.
		if ($quotaDetails{totalQuota}!~/\d+/ or $quotaDetails{usedQuota}!~/\d+/){
			unlink($usrDir.'/.quota.txt');
			getQuota($0);
			%quotaDetails = readQuota($usrDir.'/.quota.txt');
		}
	}
	return %quotaDetails;
}
#**************************************************************************
#Subroutine Name         : readQuota
#Objective               : This file reads the quota from quota.txt file.
#Usgae                   : readQuota();
#Added By                : Abhishek Verma.
#****************************************************************************/
sub readQuota{
	my $quotaFileLoc = shift;
	my %quotaDetails = ();
	if (-e $quotaFileLoc){
		open (AQ,'<',$quotaFileLoc) or (traceLog($lineFeed.Constants->CONST->{'FileCrtErr'}.$enPwdPath."failed reason: $! $lineFeed", __FILE__, __LINE__) and die); #File handler AQ means Account Quota;
        	%quotaDetails = map {s/#.*//;
        	                s/^\s+//;
                	        s/\s+$//;
                        	m/(.*?)\s*=\s*(.*)/;} <AQ>;
	}
	return %quotaDetails;
}

#****************************************************************************
#Subroutine Name         : displayMenu
#Objective               : To display the menue.
#Usgae                   : displayMenu($menu)
#                        : $menu       : Contains data to display menu.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub displayMenu{
        my $userMenu = shift;
  	if (ref $userMenu eq 'ARRAY'){#This part is to display simple menu set.Eg : Menu shown in View_Log.pl while asking input for time from user to dipaly logs.
		foreach (@{$userMenu}){
			print $lineFeed.$_;
		}
	}else{# This part will display complex menu set. Eg Menu shown in the beginning of 'Edit_Supported_Files.pl' 
		foreach my $jobFileName ( sort {lc $a cmp lc $b} keys %{$userMenu}){
        	        print "$jobFileName:$lineFeed";
                	foreach my $filePosition ( sort {$a <=> $b} keys %{$userMenu->{$jobFileName}}){
                        	print qq(      $filePosition\) $userMenu->{$jobFileName}->{$filePosition}->[0]$lineFeed);
                	}
        	}
	}
}
#****************************************************************************
#Subroutine Name         : returnKeyName
#Objective               : To return the key name based on user input.
#Usgae                   : returnKeyName($userChoice,[List of key name to be returned])
#                        : $userChoice       : input given by user after looking into the menu.
#                        : Second Parameter is the list of key name you want to return corresponding to the user choice entered.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub returnKeyName{
        my $userChoice = $_[0];
	my @keyName2Return = @{$_[1]};
        my $keyName = $userChoice =~ /^1$|^2$/ ? $keyName2Return[0] : $userChoice =~ /^3$|^4$|^5$/ ? $keyName2Return[1]  :$userChoice =~ /^6$|^7$/ ? $keyName2Return[2] :'';
        return $keyName;
}
#****************************************************************************
#Subroutine Name         : getStartAndEndEpochTime 
#Objective               : To return the start and end date epoch time.
#Usgae                   : getStartAndEndEpochTime($userChoice)
#                        : $userChoice       : input given by user to check log for any of the one given below:
#                          1)One week before
#                          2)Two week before
#                          3)One month before
#                          4)Given date range
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getStartAndEndEpochTime{
	my $userOption = shift;
	my $currentTimeStamp = time();
	my $daysToSubstract = ($userOption == 1) ? 7 : ($userOption == 2) ? 14 : 30;
	my $startTimeStamp = $currentTimeStamp - ($daysToSubstract * 24 * 60 * 60);
	return ($startTimeStamp,$currentTimeStamp);
}

#****************************************************************************
#Subroutine Name         : getUserDateRange
#Objective               : This subroutine will get the date range from the user..
#Usgae                   : getUserDateRange()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getUserDateRange{
	print $lineFeed.Constants->CONST->{'startDate'};
	my $stDate = <STDIN>;
	Chomp(\$stDate);
	unless (validateDatePattern($stDate)){
		$stDate = '';
        }
	print $lineFeed.Constants->CONST->{'endDate'};
        my $edDate = <STDIN>;
        Chomp(\$edDate);
        unless (validateDatePattern($edDate)){
                $edDate = '';
        }
	return ($stDate,$edDate);
}
#****************************************************************************
#Subroutine Name         : validateDatePattern
#Objective               : This subroutine will test the date and check whether date given by user is of valid pattern.
#Usgae                   : validateDatePattern(DATE)
#Added By                : Abhishek Verma.
#****************************************************************************/
sub validateDatePattern{
	if ($_[0] =~ /^(0[1-9]|1[0-2])\/(0[1-9]|1\d|2\d|3[01])\/(19|20)\d{2}$/){
		return 1;
	}else{
		return 0; 
	}
}
#****************************************************************************
#Subroutine Name         : getLoginStatus
#Objective               : This subroutine will give you the login status for user account.
#Usgae                   : getLoginStatus()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getLoginStatus{
	my $pwdPath = shift;
	my $displayHeader = shift; 
	my $loginReq = 1;

	#checking if user is logged in
	$loginReq = 0	if (-e $userTxt and -e $pwdPath and -s $pwdPath > 0);

	if($loginReq){
		#displaying script header if passed
		
		$displayHeader->($0) if (defined ($displayHeader));
		print Constants->CONST->{'PlLogin'}.$whiteSpace.qq{$appType}.$whiteSpace.Constants->CONST->{'AccLogin'}.$lineFeed;
                traceLog(Constants->CONST->{'PlLogin'}.$whiteSpace.$appType.$whiteSpace.Constants->CONST->{'AccLogin'}.$lineFeed, __FILE__, __LINE__);
	}
	return $loginReq;
}
#****************************************************************************
#Subroutine Name         : getAccountConfStatus 
#Objective               : This subroutine will give the status of configuration file for given user account.
#Usgae                   : getAccountConfStatus(CONF_FILE_PATH,[Display Header]);
#			 : CONF_FILE_PATH : Configuration file path so that we can check if this file exists and it has data.
#			 : Display Header : A function header passed as a ref. This is optional.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getAccountConfStatus{
        my $confFilePath = shift;
        my $displayHeader = shift;
        my $accountConfReq = 1;

	# checking for account configuration when user is logged in
	if (($userName ne '' and -e $serviceFileLocation and -s $serviceFileLocation > 0 and -e $usrProfileDir and -e $confFilePath and -s $confFilePath > 0) 
	# checking for account configuration when user is logged out
	or ($userName eq '' and -e $serviceFileLocation and -s $serviceFileLocation > 0 and -e $usrProfileDir)){
                $accountConfReq = 0;
	}	

	if($accountConfReq){
		#displaying script header if passed
		$displayHeader->($0) if (defined ($displayHeader));
                print Constants->CONST->{'loginConfigAgain'}.$lineFeed;
                #traceLog(Constants->CONST->{'loginConfigAgain'}.$lineFeed, __FILE__, __LINE__);
        }
	return $accountConfReq;
}
#****************************************************************************
#Subroutine Name         : getServiceLocation 
#Objective               : This subroutine will give the service location.
#Usgae                   : getServiceLocation()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getServiceLocation{
        if (-e $serviceFileLocation and -s $serviceFileLocation > 0){
                open(SP,"<$serviceFileLocation");
                local $\ = '';
                $userServicePath = <SP>;
                Chomp(\$userServicePath);
        }
}
#****************************************************************************
#Subroutine Name         : writeParameterValuesToStatusFile
#Objective               : This subroutine will write total file count,sync count and error count to the staus file.
#Usgae                   : writeParameterValuesToStatusFile()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub writeParameterValuesToStatusFile
{
	($fileBackupCount,$fileRestoreCount,$fileSyncCount,$failedfiles_count,$exit_flag,$failedfiles_index) = @_;
        my $Count= 0;
        my $Synccount = 0;
        my $Errorcount = 0;

        # read the backup, sync and error count from status file
        $Count = getParameterValueFromStatusFile('COUNT_FILES_INDEX');
        $Synccount = getParameterValueFromStatusFile('SYNC_COUNT_FILES_INDEX');
        $Errorcount = getParameterValueFromStatusFile('ERROR_COUNT_FILES');

        # open status file to modify
=beg        if(!open(STATUS_FILE, ">", $statusFilePath)) {
                traceLog("Failed to open $statusFilePath, Reason:$! $lineFeed", __FILE__, __LINE__);
                print "Failed to open $statusFilePath, Reason:$! $lineFeed";
                return;
        }
        chmod $filePermission, $statusFilePath;
        autoflush STATUS_FILE;
=cut
        # Calculate the backup, sync and error count based on new values
        if($jobType eq "BACKUP") {
                $Count += $fileBackupCount;
        } else {
                $Count += $fileRestoreCount;
        }

        $Synccount += $fileSyncCount;
        $Errorcount = $failedfiles_count;

        $statusHash{'COUNT_FILES_INDEX'} = $Count;
        $statusHash{'SYNC_COUNT_FILES_INDEX'} = $Synccount;
        $statusHash{'ERROR_COUNT_FILES'} = $Errorcount;
        $statusHash{'FAILEDFILES_LISTIDX'} = $failedfiles_index;
        $statusHash{'EXIT_FLAG_INDEX'} = $exit_flag;
        putParameterValueInStatusFile();
}

#****************************************************************************
#Subroutine Name         : holdScreen2displayMessage
#Objective               : To hold the execution flow for given time.
#Usgae                   : holdScreen2displayMessage()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub holdScreen2displayMessage{
	sleep($_[0]);
}
1;
