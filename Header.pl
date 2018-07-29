#!/usr/bin/perl

###############################################################################
#Script Name : Header.pl
###############################################################################
#use Data::Dumper;
use Cwd;
use Tie::File;
use File::Copy;
use File::Basename;
use File::Path;
use IO::Handle;
#use Fcntl;
use POSIX;
use Fcntl qw(:flock);

$incPos = rindex(__FILE__, '/');
$incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

#use Constants 'CONST';
require Constants;
require Strings;

our $userScriptLocation  = findUserLocation();
our $logger;
our $deviceIdPostfix = '4b5z';
our $deviceIdPrefix = '5c0b';
our $logoutFlag = 0;
our $lineFeed = "\n";
our $proxyStr =  "";
our $dedup = "off";
our $fileTransferCount = 1;
#our $currentDir = getcwd;
our $currentDir = $userScriptLocation;
our $userName = undef;
our ( $proxyOn, $proxyIp, $proxyPort, $proxyUsername, $proxyPassword) = (undef) x 5;
our $httpuser = `whoami`;
our ($appTypeSupport,$appType) = getAppType();
our $appMaintainer = getAppMaintainer();
our @columnNames = (['S.No.','Device Name','Device ID','OS','Date & Time','IP Address'],[8,24,24,15,22,15]);
our $freshInstallFile = "$userScriptLocation/freshInstall";
chomp($httpuser);
my $serviceDir = '';
our @linesCrontab = ();

#-------------------------------------------------------Function Prototypes-------------------------------------
#---------------------------------------------------------------------------------------------------------------
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
#GLOBAL                 #
##################################

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
my $repeatDisplayBlock = 4;
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
our $psOption = "-elf";
our $machineInfo;
my $freebsdProgress = "";
getPSoption(); #Getting PS option to get process id.
#Added for FreeBSD machine's progress bar display
if($machineInfo eq 'freebsd'){
	my $latestCulmn = `tput cols`;
	my $lineCount = 11;
	for(my $i=0; $i<=$lineCount; $i++){
		$freebsdProgress .= (' ')x$latestCulmn;
		$freebsdProgress .= "\n";
	}
}

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
#our ($deviceID,$deviceNickName) = ('') x 2;
our ($restoreDeviceID,$backupDeviceID) = ('') x 2;
our $uniqueID = getUniqueID();

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
			"LINKBUCKET" => "--link-bucket",
			"NICKUPDATE" => "--nick-update",
			"BUCKETTYPE" => "--bucket-type",
			"UNIQUEID" => "--uid",
			"OS" => "--os",
			"NICKNAME" => "--nick-name",
			"CREATEBUCKET" => "--create-bucket",
			"LISTDEVICE" => "--list-device", 
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
			"ITEMSTATUS3" => "--items-status3",
			"DEVICEID" => "--device-id",
			"ENCOPT" => "--enc-opt",
			"PORTABLE" => "--portable",
			"PORTABLEDEST" => "--portable-dest",
			"MASKNAME" => "--mask-name",
			"NOVERSIONS" => "--no-versions",
			"DEFLOCAL" => "--def-local",			
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
						   "user information not found",
						   "failed to get the host name"
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
our @ErrorArgumentsExit = ( "encryption verification failed",
							"some files could not be transferred due to quota over limit",
							"skipped-over limit",
							"quota over limit",
							"account is under maintenance",
							"account has been cancelled",
							"account has been expired",
							"PROTOCOL VERSION MISMATCH",
							"password mismatch",
							"out of memory",
							"failed to get the device information",
							"Proxy Authentication Required",
							"No route to host",
							"Connection refused",
							#"failed to connect",
							"Connection timed out",
							"Invalid device id",
							"not enough free space on device"
                        );
our $relative = 1;
our $defaultBw = undef;
our $defaultEncryptionKey = "DEFAULT";
our $privateEncryptionKey = "PRIVATE";
#----------------Get user service path from .serviceLocation directory-------#
my $serviceFileLocation = qq{$userScriptLocation/}.Constants->CONST->{serviceLocation};
my $userServicePath = getServiceLocation();
#----------------------------------------------------------------------------#
our $percentageComplete = undef;
our $carriageReturn = "\r";
our $percent = "%";

my $indexLastDir = rindex($currentDir, "/");
our $parentDir = substr($currentDir, 0, $indexLastDir);
our $idriveServicePath = $userServicePath;
our $usrProfilePath = ($idriveServicePath)?"$idriveServicePath/user_profile":"";
our $cacheDir = ($idriveServicePath)?"$idriveServicePath/cache":"";
our $userTxt  = ($cacheDir)?"$cacheDir/user.txt":"";

our $idevsutilBinaryName      = "idevsutil";#Name of idevsutil binary#
our $idevsutilDedupBinaryName = "idevsutil_dedup";#Name of dedup idevsutil binary#
our $idevsutilBinaryPath      = "$idriveServicePath/$idevsutilBinaryName";#Path of idevsutil binary#
our $idevsutilCommandLine     = undef;
our $displayCurrentUser       = getCurrentUser();
our %evsDeviceHashOutput      = ();
#*******************************************************************************************************
#Global variables for Downloadable Binary Links

our %archiveNames = (EvsBin32 => {
									folder => "${appType}_linux_32bit/",
									zip => "${appType}_linux_32bit.zip" },
						EvsBin64 => {
									folder => "${appType}_linux_64bit/",
									zip => "${appType}_linux_64bit.zip" },
						EvsQnapBin32 => {
									folder => "${appType}_QNAP_32bit/",
									zip => "${appType}_QNAP_32bit.zip" },
						EvsQnapBin64 => {
									folder => "${appType}_QNAP_64bit/",
									zip => "${appType}_QNAP_64bit.zip" },
						EvsSynoBin32_64 => {
									folder => "${appType}_synology_64bit/",
									zip => "${appType}_synology_64bit.zip" },
						EvsNetgBin32_64 => {
									folder => "${appType}_Netgear_64bit/",
									zip => "${appType}_Netgear_64bit.zip" },
						EvsUnvBin => {
									folder => "${appType}_linux_universal/",
									zip => "${appType}_linux_universal.zip" },
						EvsQnapArmBin => {
									folder => "${appType}_QNAP_ARM/",
									zip => "${appType}_QNAP_ARM.zip" },
						EvsSynoArmBin => {
									folder => "${appType}_synology_ARM/",
									zip => "${appType}_synology_ARM.zip" },
						EvsNetgArmBin => {
									folder => "${appType}_Netgear_ARM/",
									zip => "${appType}_Netgear_ARM.zip" },
						EvsVaultBin32_64 => {
									folder => "${appType}_Vault_64bit/",
									zip => "${appType}_Vault_64bit.zip" },
						EvsSynoAlphine => {
									folder => "${appType}_synology_Alpine/",
									zip => "${appType}_synology_Alpine.zip" }									
					);

our $evsWebPath = "https://www.${appTypeSupport}downloads.com/downloads/linux/download-options/";
	$evsWebPath = "https://www.${appTypeSupport}.com/downloads/linux/download-options/" if ($appType eq 'IBackup');
our $EvsBin32 = $evsWebPath.$archiveNames{'EvsBin32'}{'zip'};
our $EvsBin64 = $evsWebPath.$archiveNames{'EvsBin64'}{'zip'};
our $EvsQnapBin32 = $evsWebPath.$archiveNames{'EvsQnapBin32'}{'zip'};
our $EvsQnapBin64 = $evsWebPath.$archiveNames{'EvsQnapBin64'}{'zip'};
our $EvsSynoBin32_64 = $evsWebPath.$archiveNames{'EvsSynoBin32_64'}{'zip'};
our $EvsNetgBin32_64 = $evsWebPath.$archiveNames{'EvsNetgBin32_64'}{'zip'};
our $EvsUnvBin = $evsWebPath.$archiveNames{'EvsUnvBin'}{'zip'};
our $EvsQnapArmBin = $evsWebPath.$archiveNames{'EvsQnapArmBin'}{'zip'};
our $EvsSynoArmBin = $evsWebPath.$archiveNames{'EvsSynoArmBin'}{'zip'};
our $EvsNetgArmBin = $evsWebPath.$archiveNames{'EvsNetgArmBin'}{'zip'};
our $EvsVaultBin32_64 = $evsWebPath.$archiveNames{'EvsVaultBin32_64'}{'zip'};
our $EvsSynoAlphine = $evsWebPath.$archiveNames{'EvsSynoAlphine'}{'zip'};

#CGI Links to verify Account:set number
#
#our $IDriveAccVrfLink = "https://www1.idrive.com/cgi-bin/get_idrive_evs_details_xml_ip.cgi?";
#our $IBackupAccVrfLink = "https://www1.ibackup.com/cgi-bin/get_ibwin_evs_details_xml_ip.cgi?";
#our $IDriveAccVrfLink = "https://www1.idrive.com/cgi-bin/get_idrive_evs_details_xml_ip.cgi?"; #old cgi url
our $IDriveAccVrfLink = qq(https://www1.idrive.com/cgi-bin/v1/user-details.cgi?);
our $IBackupAccVrfLink = "https://www1.ibackup.com/cgi-bin/get_ibwin_evs_details_xml_ip.cgi?";
our $IDriveUserInoCGI  =  "https://www1.".$appTypeSupport.".com/cgi-bin/update_user_device_info.cgi?";
our $faqURL			   = "https://www.idrive.com/faq_linux";
	$faqURL			   = "https://www.ibackup.com/backup-faq/faqqrsync.htm" if ($appType eq 'IBackup');
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
		if ($proxyStr =~ /(.*?):(.*)\@(.*?):(.*?)$/){
			($proxyUsername,$proxyPassword,$proxyIp,$proxyPort) = ($1,$2,$3,$4);	
		}
	}
	our $backupType = $hashParameters{BACKUPTYPE};
	$dedup = $hashParameters{DEDUP} if (defined ($hashParameters{DEDUP}) and $hashParameters{DEDUP} ne '');	
	our $backupHost = $hashParameters{BACKUPLOCATION};
	$backupHost = checkLocationInput($backupHost);
	if($backupHost ne "" && substr($backupHost, 0, 1) ne "/") {
		$backupHost = ($dedup eq 'off') ? "/".$backupHost : $backupHost;
	}
	$backupHost =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root 
	our $restoreHost = $hashParameters{RESTOREFROM};
	$restoreHost = checkLocationInput($restoreHost);
	if ($dedup eq 'on'){
        	($restoreDeviceID,$restoreHost) = split ('#',$restoreHost);
		($backupDeviceID,$backupHost)  = split ('#',$backupHost);
    	}
	if($restoreHost ne "" && substr($restoreHost, 0, 1) ne "/") {
		$restoreHost = ($dedup eq 'off') ? "/".$restoreHost : $restoreHost;
	}
	our $configEmailAddress = $hashParameters{EMAILADDRESS};
	our $bwThrottle = getThrottleVal(); 
	our $restoreLocation = $hashParameters{RESTORELOCATION};
	$restoreLocation = checkLocationInput($restoreLocation);
	#$restoreLocation =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root
	our $ifRetainLogs = $hashParameters{RETAINLOGS};
	our $backupPathType = $hashParameters{BACKUPTYPE};
	our $serverRoot = $hashParameters{SERVERROOT};
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
	our $RestoresetFile = "$usrProfileDir/Restore/Manual/RestoresetFile.txt"; 
	our $backupsetSchFilePath = "$usrProfileDir/Backup/Scheduled/BackupsetFile.txt"; 
	our $RestoresetSchFile = "$usrProfileDir/Restore/Scheduled/RestoresetFile.txt"; 
	our $localBackupsetFilePath = "$usrProfileDir/LocalBackup/Manual/BackupsetFile.txt"; 
	our $validateRestoreFromFile = "$usrProfileDir/validateRestoreFromFile.txt";
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
	traceLog("${$_[1]}\n", __FILE__, __LINE__);
	if(!open(FHERR, ">>",$TmpErrorFilePath)){
		traceLog("Could not open file TmpErrorFilePath in additionalErrorInfo: $TmpErrorFilePath, Reason:$!\n", __FILE__, __LINE__);
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
	if(-e $pvtPath && (-s $pvtPath > 0)) {
        	$encKeyType = $privateEncryptionKey;
 	}
=comment
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
=cut
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
	#$appType = "IBackup";
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
sub checkBinaryExists
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
sub createEncodeFile
{
	my $data = $_[0];
	my $path = $_[1];
	my $utfFile = "";
	$utfFile = getUtf8File($data, $path);
	chomp($utfFile);
	
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".
	$whiteSpace.$hashEvsParameters{UTF8CMD}.$assignmentOperator."'".$utfFile."'".$whiteSpace.$errorRedirection;

	my $commandOutput = `$idevsutilCommandLine`;
	if ($commandOutput =~ /idevsutil: not found/){
		print "\nPlease reconfigure your account using account_setting.pl script or add this functionality to login \n";
		exit 0;
	}
	traceLog($lineFeed.Constants->CONST->{'CrtEncFile'}.$whiteSpace.$commandOutput.$lineFeed, __FILE__, __LINE__);
	chmod $filePermission,$path;
	unlink $utfFile;
}

#****************************************************************
# Subroutine Name         : createEncodeSecondaryFile           *
# Objective               : Create Secondary Encoded password.  *
# Added By                : Dhritikana.                         *
#****************************************************************
sub createEncodeSecondaryFile
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
sub getPdata
{
	my $udata = $_[0];
	my $pdata = '';
	chmod $filePermission, $enPwdPath;
	if(!open FILE, "<", "$enPwdPath"){
		traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}.$enPwdPath." failed reason:$! $lineFeed", __FILE__, __LINE__);
		return $pdata;
	}
	my $enPdata = <FILE>; chomp($enPdata);
	close(FILE);
	
	my $len = length($udata);
	my ($a, $b) = split(/\_/, $enPdata, 2); 
	$pdata = unpack( "u", "$b");
	if($len eq $a) {
		return $pdata;
	}
}

#****************************************************************************************************
# Subroutine Name         : getUtf8File.
# Objective               : Create utf8 file.
# Added By                : Avinash Kumar.
#*****************************************************************************************************/
sub getUtf8File
{
	my ($getVal, $encPath) = @_;
	my $usrProfileDir = defined ($usrProfileDir) ? $usrProfileDir : $usrProfilePath	;
	if (!-e $usrProfileDir){
		my $res = `mkdir -p '$usrProfileDir'`;
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
# Subroutine Name		: getServerAddr.
# Objective				: Construction of get-server address evs command and execution.
#			    			Parse the output and update same in Account Setting File.
# Added By				: Avinash Kumar.
# Modified By			: Dhritikana  
#*****************************************************************************************************/
sub getServerAddr
{
	if ($_[0]){
		open FILE, ">", $serverfile or (print $tHandle $lineFeed.Constants->CONST->{'FileOpnErr'}."$serverfile for getServerAddress, Reason:$! $lineFeed" and die);
                print FILE $_[0];
                close FILE;
                chmod $filePermission, $serverfile;
		return 1;
	}
	my $getServerUtfFile = undef;
	$getServerUtfFile = getOperationFile(Constants->CONST->{'GetServerAddressOp'});

	$getServerUtfFile =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$getServerUtfFile."'".$whiteSpace.$errorRedirection.$lineFeed;
	my $commandOutput = `$idevsutilCommandLine`;
	unlink($getServerUtfFile);
	
	my %evsServerHashOutput = parseXMLOutput(\$commandOutput);
	my $addrMessage = $evsServerHashOutput{'message'};
	$serverAddress = $evsServerHashOutput{'cmdUtilityServerIP'};
	my $desc = $evsServerHashOutput{'desc'};
	traceLog($lineFeed.Constants->CONST->{'GetServAddr'}.$commandOutput.$lineFeed, __FILE__, __LINE__);
	
	if($commandOutput =~ /reason\: connect\(\) failed/) {
		print $lineFeed.Constants->CONST->{'ProxyErr'}.$lineFeed.$whiteSpace;
		traceLog($lineFeed.Constants->CONST->{'ProxyErr'}.$lineFeed, __FILE__, __LINE__);
		if($mkDirFlag) {
			rmtree($userName);
		}
		return 0;	
	}
	if($addrMessage =~ /ERROR/) {
		if($desc ne ''){
			print $lineFeed.$desc.$lineFeed.$whiteSpace;
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
	}
	else{
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
	if ($#linesConfFile < 0){
		readConfigurationFile($confFilePath);
	}

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
		if($matchFlag == 0 and ${$_[0]} =~ /SERVERROOT/){
			$line = "${$_[0]} = ${$_[1]}\n";
			print CONF_FILE $line;
		}
		close CONF_FILE;
		$#linesConfFile = -1;
	}else{
		return 0;
	}
}

#*******************************************************************************************************************
# Subroutine Name         : getConfigHashValue
# Objective               : fetches the value of individual parameters which are specified in the configuration file
# Added By                : Dhritikana
# Modified By 		  	  : Abhishek Verma - 09-03-17 - used Chomp in place of chomp and other regular expressions which was used to remove spaces from beginning and end.
#********************************************************************************************************************
sub getConfigHashValue
{	
	if ($#linesConfFile < 0){
		readConfigurationFile($confFilePath);
	}
	
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
sub readStatusFile
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
sub putParameterValueInStatusFile
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
	my $osType = 'Linux';
	my $bucketType = 'D';
	my ($opType,$utfFile,$utfValidate,$encryptionType)= ("") x 4;
	$jobRunningDir = $usrProfileDir if($jobRunningDir eq "");
	my $utfPath = $jobRunningDir."/utf8.txt";
	my $serverAddressOperator = "@";
	my $serverName = "home";
	my $serverNameOperator = "::";
	my $operationType = $_[0];
	my $encType = checkEncType();
	$xmlOutputParam  = '';
	$itemStatusParam = $hashEvsParameters{ITEMSTATUS}.$lineFeed;
	$backupLocation  = $backupHost.$pathSeparator;
	#$deviceID = "5c0bD015009889990006548954b5z"; #Senthil Added
	if($dedup eq 'on'){
		$xmlOutputParam  = $hashEvsParameters{XMLOUTPUT}.$lineFeed;
		$backupLocation  = '';
	}
	if ($operationType eq Constants->CONST->{'LinkBucketOp'}){
		$utfPath = defined ($usrProfileDir) ? $usrProfileDir."/utf.txt" : $usrProfilePath.'/utf.txt';
                open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for validate, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{XMLOUTPUT}.$lineFeed.
                $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
#                if("PRIVATE" eq $_[1]){
		if("PRIVATE" eq $encType){
                        $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
                }
                $utfFile .= $hashEvsParameters{LINKBUCKET}.$lineFeed.
		#$_[2] contains device nick name  as it is passed as 3rd  parameter to getOperationFile() subroutine.
                $hashEvsParameters{NICKNAME}.$assignmentOperator.$_[2].$lineFeed.
                $hashEvsParameters{OS}.$assignmentOperator.$osType.$lineFeed.
		$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
                $hashEvsParameters{ENCODE}.$lineFeed.
		$userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$pathSeparator.$lineFeed.
		#$_[1] contains deviceID as it is passed as 2nd parameter to getOperationFile() subroutine.
                $hashEvsParameters{DEVICEID}.$assignmentOperator.$_[1].$lineFeed.
		$hashEvsParameters{UNIQUEID}.$assignmentOperator.$uniqueID.$lineFeed.
		$hashEvsParameters{BUCKETTYPE}.$assignmentOperator.$bucketType;
	}elsif($operationType eq Constants->CONST->{'NickUpdateOp'}){
		$utfPath = defined ($usrProfileDir) ? $usrProfileDir."/utf.txt" : $usrProfilePath.'/utf.txt';
		open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for validate, Reason:$!", __FILE__, __LINE__) and die);
		$utfFile = $hashEvsParameters{XMLOUTPUT}.$lineFeed.
		$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
#		if("PRIVATE" eq $_[1]){
		if("PRIVATE" eq $encType){
			$utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
		}
		$utfFile .= $hashEvsParameters{NICKUPDATE}.$lineFeed;
		$utfFile .= $hashEvsParameters{NICKNAME}.$assignmentOperator.$backupHost.$lineFeed;
		$utfFile .= $hashEvsParameters{OS}.$assignmentOperator.$osType.$lineFeed.
		#$_[1] contains deviceID as it is passed as 2nd parameter to getOperationFile() subroutine.
		$hashEvsParameters{DEVICEID}.$assignmentOperator.$_[1].$lineFeed.
		$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
		$hashEvsParameters{ENCODE}.$lineFeed.
		$userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$pathSeparator.$lineFeed;
	}elsif($operationType eq Constants->CONST->{'CreateBucketOp'}){
		$utfPath = defined ($usrProfileDir) ? $usrProfileDir."/utf.txt" : $usrProfilePath.'/utf.txt';
		open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for validate, Reason:$!", __FILE__, __LINE__) and die);
		$utfFile = $hashEvsParameters{XMLOUTPUT}.$lineFeed.
		$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
#		if("PRIVATE" eq $_[1]){
		if("PRIVATE" eq $encType){
			$utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
		}
		$utfFile .= $hashEvsParameters{CREATEBUCKET}.$lineFeed.
		$hashEvsParameters{NICKNAME}.$assignmentOperator.$backupHost.$lineFeed.
		$hashEvsParameters{OS}.$assignmentOperator.$osType.$lineFeed.
		$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
		$hashEvsParameters{ENCODE}.$lineFeed.
		$userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$pathSeparator.$lineFeed.
		$hashEvsParameters{UNIQUEID}.$assignmentOperator.$uniqueID.$lineFeed.
		$hashEvsParameters{BUCKETTYPE}.$assignmentOperator.$bucketType;
	}elsif($operationType eq Constants->CONST->{'ListDeviceOp'}){
		$utfPath = defined ($usrProfileDir) ? $usrProfileDir."/utf.txt" : $usrProfilePath.'/utf.txt';
		open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for validate, Reason:$!", __FILE__, __LINE__) and die);
		$utfFile = 	$hashEvsParameters{XMLOUTPUT}.$lineFeed.
				$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
#		if("PRIVATE" eq $_[1]){
		if("PRIVATE" eq $encType){
			$utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
		}				
		$utfFile .= $hashEvsParameters{LISTDEVICE}.$lineFeed.
				$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
				$hashEvsParameters{ENCODE}.$lineFeed.
				$userName.$serverAddressOperator.
				$serverAddress.$serverNameOperator.
				$serverName.$pathSeparator.$lineFeed;
	}
	elsif($operationType eq Constants->CONST->{'ValidateOp'})
        {       
			$utfPath = defined ($usrProfileDir) ? $usrProfileDir."/utf.txt" : $usrProfilePath.'/utf.txt';
		
			open UTF8FILE, ">", $utfPath ;#or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for validate, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{VALIDATE}.$lineFeed.
                           $hashEvsParameters{USERNAME}.$assignmentOperator.$userName.$lineFeed.
                           $hashEvsParameters{PASSWORD}.$assignmentOperator.$_[1].$lineFeed.
                           $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed;
                           #$hashEvsParameters{ENCODE}.$lineFeed;
                           #$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
        }
	elsif($operationType eq Constants->CONST->{'GetServerAddressOp'})
        {
		$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE, ">", $utfPath ; #or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for getServerAddress, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{SERVERADDRESS}.$lineFeed.
                           $userName.$lineFeed.
                           $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
			   $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
			   $hashEvsParameters{ENCODE}.$lineFeed.
			   $hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
        }
	elsif($operationType eq Constants->CONST->{'ConfigOp'})
        {
				$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for config, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{CONFIG}.$lineFeed.
                           $hashEvsParameters{USERNAME}.$assignmentOperator.$userName.$lineFeed.
                           $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
#                if("PRIVATE" eq $_[1]){
		if("PRIVATE" eq $encType){
                        $utfFile .= $hashEvsParameters{ENCTYPE}.$assignmentOperator.$privateEncryptionKey.$lineFeed.
                                    $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
                }
                else{
                        $utfFile .= $hashEvsParameters{ENCTYPE}.$assignmentOperator.$defaultEncryptionKey.$lineFeed;
                }
                $utfFile .= $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
                            $hashEvsParameters{ENCODE}.$lineFeed;
        }
	elsif($operationType eq Constants->CONST->{'CreateDirOp'})
        {
				$utfPath = $usrProfileDir."/utf.txt";
                #tie my @servAddress, 'Tie::File', "$currentDir/$userName/.serverAddress.txt" or (print $tHandle "Can not tie to $serverfile, Reason:$!");
			    open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for createDir, Reason:$!", __FILE__, __LINE__) and die);
                $utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
#                if($_[1] eq "PRIVATE"){
		if($encType eq "PRIVATE"){
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
	elsif($operationType eq Constants->CONST->{'BackupOp'}) {
		my $BackupsetFile = $_[1];
		my $relativeAsPerOperation = $_[2];
		my $source = $_[3];
		my $encryptionType = $encType;
		if($dedup eq 'on'){
			$relativeAsPerOperation = RELATIVE;
		}

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
					$hashEvsParameters{ADDPROGRESS}.$lineFeed.$hashEvsParameters{XMLOUTPUT}.$lineFeed;
					if ($dedup eq 'on'){
						$utfFile .= $hashEvsParameters{DEVICEID}.$assignmentOperator.$backupDeviceID.$lineFeed;
					}
					$utfFile .= $source.$lineFeed.
					$userName.$serverAddressOperator.
					$serverAddress.$serverNameOperator.
					$serverName.$pathSeparator.$backupLocation.$lineFeed;
	}
	elsif($operationType eq Constants->CONST->{'RestoreOp'}) {
		my $RestoresetFile = $_[1];
		my $relativeAsPerOperation = $_[2];
		my $source = $_[3];
		my $encryptionType = $encType;
		
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
					$hashEvsParameters{ADDPROGRESS}.$lineFeed.$hashEvsParameters{XMLOUTPUT}.$lineFeed;
					if ($dedup eq 'on'){
						$utfFile .= $hashEvsParameters{DEVICEID}.$assignmentOperator.$restoreDeviceID.$lineFeed;
					}
			$utfFile .= $userName.$serverAddressOperator.
					$serverAddress.$serverNameOperator.
					$serverName.$source.$lineFeed.
					$restoreLocation.$lineFeed;
	}
	elsif($operationType eq Constants->CONST->{'LocalBackupOp'}) {
		my $BackupsetFile = $_[1];
		my $relativeAsPerOperation = RELATIVE;
		my $source = $_[3];
		my $encryptionType = $encType;

		open UTF8FILE, ">", $utfPath or ($errStr = Constants->CONST->{'FileOpnErr'}.$utfPath." for backup, Reason:$!" and return 0);
		$utfFile = $hashEvsParameters{FROMFILE}.$assignmentOperator.$BackupsetFile.$lineFeed.
   			   $hashEvsParameters{BWFILE}.$assignmentOperator.$bwPath.$lineFeed.
   			   $hashEvsParameters{TYPE}.$lineFeed.
   			   $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
		if($encryptionType =~ m/^$privateEncryptionKey$/i) {
			$utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
			$utfFile .= $hashEvsParameters{DEFLOCAL}.$assignmentOperator.'0'.$lineFeed;
		}else{
			$utfFile .= $hashEvsParameters{DEFLOCAL}.$assignmentOperator.'1'.$lineFeed;
		}		
		$utfFile .= $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
					$hashEvsParameters{ENCODE}.$lineFeed.
					$relativeAsPerOperation.$lineFeed.
					$hashEvsParameters{TEMP}.$assignmentOperator.$evsTempDir.$lineFeed.
					$hashEvsParameters{OUTPUT}.$assignmentOperator.$idevsOutputFile.$lineFeed.
					$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
					$hashEvsParameters{ADDPROGRESS}.$lineFeed.$hashEvsParameters{XMLOUTPUT}.$lineFeed;
					if ($dedup eq 'on'){
						$utfFile .= $hashEvsParameters{DEVICEID}.$assignmentOperator.$backupDeviceID.$lineFeed;
					}
		$utfFile .= $hashEvsParameters{ENCOPT}.$lineFeed.
					$hashEvsParameters{PORTABLE}.$lineFeed.
					$hashEvsParameters{NOVERSIONS}.$lineFeed.
					$hashEvsParameters{PORTABLEDEST}.$assignmentOperator.$backupLocationDir.$lineFeed;					
		$utfFile .= $source.$lineFeed.
					$userName.$serverAddressOperator.
					$serverAddress.$serverNameOperator.
					$serverName.$backupLocationDir.$lineFeed;
	}
	elsif($operationType eq Constants->CONST->{'PropertiesOp'}) {
		##restoreHost [DHRITI: need removal of starting / if exists
		$utfPath = $usrProfileDir."/utf.txt";
		open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for properties, Reason:$!", __FILE__, __LINE__) and die);
=begin		$utfFile =	$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
					$hashEvsParameters{PROPERTIES}.$lineFeed.
					$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
					$hashEvsParameters{ENCODE}.$lineFeed;
		if(!defined($_[1]) && $_[1] ne "modProxy") {
			$utfFile .=	$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
		}
		$utfFile .= $userName.$serverAddressOperator.
			    $serverAddress.$serverNameOperator.
			    $serverName.$pathSeparator.$_[1];
=cut
		
		$utfFile =	$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
					$hashEvsParameters{PROPERTIES}.$lineFeed;
					if ($dedup eq 'on'){
						$utfFile .= $hashEvsParameters{DEVICEID}.$assignmentOperator.$restoreDeviceID.$lineFeed;
					}
			$utfFile .= $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
					$hashEvsParameters{ENCODE}.$lineFeed;
		if(!defined($_[1]) && $_[1] ne "modProxy") {
			$utfFile .=	$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
		}
		$utfFile .= $userName.$serverAddressOperator.
			    $serverAddress.$serverNameOperator.
			    $serverName.$pathSeparator.$_[1];
				
	}
	elsif($operationType eq Constants->CONST->{'VersionOp'}) {
			my $filePath = $_[1];
			
			$utfPath = $usrProfileDir."/utf.txt";
			open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for properties, Reason:$!", __FILE__, __LINE__) and die);
			$utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
				   $hashEvsParameters{VERSION}.$lineFeed.
				   $hashEvsParameters{XMLOUTPUT}.$lineFeed.
				   $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
			   	   $hashEvsParameters{ENCODE}.$lineFeed.
				   $hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed;
				   if ($dedup eq 'on'){
					$utfFile .=  $hashEvsParameters{DEVICEID}.$assignmentOperator.$restoreDeviceID.$lineFeed;
				   }
		       $utfFile .= $userName.$serverAddressOperator.
			   	   $serverAddress.$serverNameOperator.
			   	   $serverName.$pathSeparator.$filePath.$lineFeed;
	} elsif($operationType eq Constants->CONST->{'RenameOp'}) {
			$utfPath = $usrProfileDir."/utf.txt";
			my $oldPath = $_[2];
			my $newPath = $_[3];
			open UTF8FILE, ">", $utfPath or (traceLog(Constants->CONST->{'FileOpnErr'}.$utfPath." for properties, Reason:$!", __FILE__, __LINE__) and die);
			$utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
				   $hashEvsParameters{RENAME}.$lineFeed.
				   $hashEvsParameters{OLDPATH}.$assignmentOperator.$oldPath.$lineFeed.
				   $hashEvsParameters{NEWPATH}.$assignmentOperator.$newPath.$lineFeed;
#		   if("PRIVATE" eq $_[1]){
		   if("PRIVATE" eq $encType){
                        $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
			}
			$utfFile .=	   $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
			   	   $hashEvsParameters{ENCODE}.$lineFeed.
				   $hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
			   	   $userName.$serverAddressOperator.
			   	   $serverAddress.$serverNameOperator.
			   	   $serverName.$pathSeparator;
	}
	elsif($operationType eq Constants->CONST->{'GetServerAddressOp'})
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
	elsif($operationType eq Constants->CONST->{'SearchOp'}) {
		my $searchUtfPath = "$jobRunningDir/searchUtf8.txt";
		open UTF8FILE, ">", $searchUtfPath or ($errStr = "Could not open file $utfFile for search, Reason:$!" and return 0);
		$utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed.
		$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
		$hashEvsParameters{ENCODE}.$lineFeed.
		$hashEvsParameters{OUTPUT}.$assignmentOperator.$jobRunningDir."/Search/output.txt".$lineFeed.
		$hashEvsParameters{ERROR}.$assignmentOperator.$jobRunningDir."/Search/error.txt".$lineFeed.
		#$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
		$hashEvsParameters{SEARCH}.$lineFeed.
		$hashEvsParameters{FILE}.$lineFeed.$xmlOutputParam;
		if ($dedup eq 'on'){
			$utfFile .= $hashEvsParameters{DEVICEID}.$assignmentOperator.$restoreDeviceID.$lineFeed;
		}
		$utfFile .= $userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$_[1].$pathSeparator.$lineFeed;
		print UTF8FILE $utfFile;
		close UTF8FILE;
		#traceLog($searchUtfPath, __FILE__, __LINE__);
		chmod $filePermission, $searchUtfPath;
		return $searchUtfPath;
	}
	elsif($operationType eq Constants->CONST->{'ItemStatOp'}) {
		open UTF8FILE, ">", $utfPath or ($errStr = "Could not open file $utfFile for search, Reason:$!" and return 0);
		$utfFile = $hashEvsParameters{FROMFILE}.$assignmentOperator.$_[1].$lineFeed.
		$hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
		if ($dedup eq 'on'){
			$utfFile .= $hashEvsParameters{DEVICEID}.$assignmentOperator.$restoreDeviceID.$lineFeed;
		}
		$utfFile .= $hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.
		$hashEvsParameters{TEMP}.$assignmentOperator.$evsTempDir.$lineFeed.
		$hashEvsParameters{ERROR}.$assignmentOperator.$jobRunningDir."/error.txt".$lineFeed.
		$hashEvsParameters{ENCODE}.$lineFeed.$itemStatusParam.
		#$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile.$lineFeed.
		$userName.$serverAddressOperator.
		$serverAddress.$serverNameOperator.
		$serverName.$pathSeparator.$lineFeed;
		
	} elsif($operationType eq Constants->CONST->{'VerifyPvtOp'}) {
		$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE,">",$utfPath or ($errStr="Could not open file $utfFile for search, Reason:$!" and return 0);
		$utfFile  = $hashEvsParameters{DEFAULTKEY}.$lineFeed;
                $utfFile .= $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
                $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
                $utfFile .= $hashEvsParameters{ENCODE}.$lineFeed.$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.$userName.$serverAddressOperator.$serverAddress.$serverNameOperator.$serverName.$lineFeed;
	}elsif($operationType eq Constants->CONST->{'validatePvtKeyOp'}){
		$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE,">",$utfPath or ($errStr="Could not open file $utfFile for search, Reason:$!" and return 0);
                $utfFile .= $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
                $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed;
                $utfFile .= $hashEvsParameters{ENCODE}.$lineFeed.$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.$userName.$serverAddressOperator.$serverAddress.$serverNameOperator.$serverName.$lineFeed;
	}elsif ($operationType eq Constants->CONST->{'GetQuotaOp'}){
		$utfPath = $usrProfileDir."/utf.txt";
                open UTF8FILE,">",$utfPath or ($errStr="Could not open file $utfFile for search, Reason:$!" and return 0);
                $utfFile  = $hashEvsParameters{GETQUOTA}.$lineFeed;
                $utfFile .= $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
                $utfFile .= $hashEvsParameters{PVTKEY}.$assignmentOperator.$pvtPath.$lineFeed if ($_[1] eq $privateEncryptionKey);
                $utfFile .= $hashEvsParameters{ENCODE}.$lineFeed.$hashEvsParameters{PROXY}.$assignmentOperator.$proxyStr.$lineFeed.$userName.$serverAddressOperator.$serverAddress.$serverNameOperator.$serverName.$lineFeed;
	}
	else {
		traceLog(Constants->CONST->{'InvalidOp'}."-> $operationType", __FILE__, __LINE__);
		return;
	}

	print UTF8FILE $utfFile;
	close UTF8FILE;
	#traceLog("$operationType has been executed", __FILE__, __LINE__);
	chmod $filePermission, $utfPath;
	return $utfPath;
}

#****************************************************************************************************
# Subroutine Name         : parseXMLOutput.
# Objective               : Parse evs command output and load the elements and values to an hash.
# Added By                : Dhritikana.
# Modified By 		  : Abhishek Verma - 7/7/2017 - Now this subroutine can parse multiple tags of xml. Previously it was restricted to one level. 
#*****************************************************************************************************/
sub parseXMLOutput
{
	my %resultHash;
	my $parseDeviceList = $_[1];
	${$_[0]} =~ s/^$//;
	if(defined ${$_[0]} and ${$_[0]} ne "") {
		my $evsOutput = ${$_[0]};
		clearFile($evsOutput);
		my @evsArrLine = ();
		if ($parseDeviceList){
			if($evsOutput =~ /No devices found/){
				return %resultHash;
			} else {
				@evsArrLine = grep {/\w+/} grep {/bucket_type=\"D\"/} split(/(?:\<item|\<login|<tree)/g, $evsOutput);
			}
		}else{
				@evsArrLine = grep {/\w+/} split(/(?:\<item|\<login|<tree)/g, $evsOutput);
		}
		my $attributeCount = 1;
		foreach(@evsArrLine) {
			my @evsAttributes = grep {/\w+/} split(/\"[\s\n\>]+/sg, $_);
			foreach (@evsAttributes){
				s/\"\/\>//;
				s/\"\>//;
				my ($key,$value) = split(/\=["]/, $_);
		 		&Chomp(\$key);
				&Chomp(\$value);
				if ($parseDeviceList){
					my $subKey = $value.'_'.$attributeCount;
					$subKey = $value if(/(?:uid|device_id|server_root)/i);
					$resultHash{$key}{$subKey} = $attributeCount;
				}else{
					$resultHash{$key} = $value;
				}
			}
			$attributeCount++;
		}
	}
	return %resultHash;
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
		$proxyOn = 1;
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
		if($configEmailAddress =~ /\,|\;/) {
			@addrList = split(/\,|\;/, $configEmailAddress);
		} else {
			push(@addrList, $configEmailAddress);
		}
		
		foreach my $addr (@addrList) {
			Chomp(\$addr);
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
	
	my $pData = &getPdata("$userName");
	if($pData eq ''){
		traceLog(Constants->CONST->{'SendMailErr'}.Constants->CONST->{'passwordMissing'}, __FILE__, __LINE__);
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
	$content .= "Version ".Constants->CONST->{'ScriptBuildVersion'};
	
	#URL DATA ENCODING#
	foreach ($userName,$pData,$finalAddrList,$subjectLine,$content) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}
	$notifyPath = 'https://webdav.ibackup.com/cgi-bin/Notify_email_ibl';
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
	#Assigning curl path
	my $curlPath = `which curl`;
	chomp($curlPath);	
	if($curlPath eq ''){
		$curlPath = '/usr/local/bin/curl';
	}
	my $cmd = '';
	if($proxyStr) {
		my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
		my @UnP = split(/\:/, $uNPword);
		if($UnP[0] ne "") {
			foreach ($UnP[0], $UnP[1]) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$uNPword = join ":", @UnP;
			$cmd = "$curlPath -x http://$uNPword\@$ipPort -s -d '$data' '$notifyPath'";
		} else {
			$cmd = "$curlPath -x http://$ipPort -s -d '$data' '$notifyPath'";
		}
	} else {			
		$cmd = "$curlPath -s -d '$data' '$notifyPath'";
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
	Chomp(\$addr);
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
sub terminateStatusRetrievalScript
{
	my $statusScriptName = Constants->FILE_NAMES->{statusRetrivalScript};
	my $statusScriptCmd = "ps $psOption | grep $statusScriptName | grep -v grep";
	
	my $statusScriptRunning = `$statusScriptCmd`;
	if($statusScriptRunning ne "") {
		my @processValues = split /[\s\t]+/, $statusScriptRunning;
		my $pid = $processValues[3];
		 my $pid = (split /[\s\t]+/, $statusScriptRunning)[3];		
#		`kill -s SIGTERM $pid`;
	}
#	unlink($_[0]);
}

#****************************************************************************************************
# Subroutine Name         : copyTempErrorFile
# Objective               : This subroutine copies the contents of the temporary error file to the 
#							Error File.
# Added By                : 
# Modified By			  : Deepak Chaurasia
#*****************************************************************************************************/
sub copyTempErrorFile
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
sub cleanProgressFile
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
	my @files_list = `ls '$error_dir'`;
	my $fileopen = 0;
	my ($proxyErr,$conOrProtocol) = (0) x 2;
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
				$summaryError.="$lineFeed$lineFeed|Error Report|$lineFeed";
				$summaryError.="_______________________________________________________________________________________$lineFeed";
			}
			$fileopen = 1;
			open ERROR_FILE, "<", $file or traceLog(Constants->CONST->{'FileOpnErr'}." $file. Reason $!\n", __FILE__, __LINE__);
			while(my $line = <ERROR_FILE>) { 
				$summaryError.=$line;
				if ($line =~ /.*error in idevs protocol data stream.*|.*connection unexpectedly closed.*/sg){
				#	$conOrProtocol = 1;
				}elsif ($line =~/.*(Proxy Authentication Required).*|.*(bad response from proxy).*/is){
					$proxyErr = 1;
				#	$line = ucfirst($&).'. '.Constants->CONST->{loginAccount}.$lineFeed;
				#	unlink($pwdPath);
				#	$summaryError.=$line;
				}
			}
			close ERROR_FILE;
		}
	}
	if ($proxyErr == 1){
		$summaryError = "\nProxy Authentication Required or bad response from proxy. ".Constants->CONST->{loginAccount}.$lineFeed;
		unlink($pwdPath);
	}
	if ($conOrProtocol == 1){
#		$summaryError = "\nEvs or connection issue. ".Constants->CONST->{loginAccount}.$lineFeed;
#		unlink($pwdPath);
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
sub createLogFiles
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
#	my $currentTime = localtime;
#	my $currentTime = time;#This function will give the current epoch time.
	#previous log file name use to be like 'BACKUP Wed May 17 12:34:47 2017_FAILURE'.Now log name will be '1495007954_SUCCESS'.
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
sub displayProgressBar
{
	return if($_[0] eq ""); #Returning if backup type is empty
	
	$SIG{WINCH} = \&changeSizeVal;
	my $progress = '';
	my $cellSize = '';
	my $fullHeader = ($jobType =~ /Backup/i) ? Constants->CONST->{'BackupProgress'} : Constants->CONST->{'RestoreProgress'};
	my $type = $_[0];
	my $trnsFileSize = $_[1];
	my $incrFileSize = $_[2];
	my $TotalSize = $_[3];
	my $kbps = $_[4];
	my $fileName = $_[5];
	my $percent = 0;
	my $totalSizeUnit = '';
	#$curLines = $_[6];	
	
	if($TotalSize ne Constants->CONST->{'CalCulate'}){
		$percent = int($incrFileSize/$TotalSize*100); 
		$percent = 100	if($percent > 100);
		$progress = "|"x($percent/$progressSizeOp); 
		my $cellCount = (100-$percent)/$progressSizeOp;
		$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
		$cellSize = " "x$cellCount;
		$totalSizeUnit = convertFileSize($TotalSize);
		
	}
	else{
		#$totalSizeUnit = convertFileSize($TotalSize);
		$totalSizeUnit = Constants->CONST->{'CalCulate'};
	}

	my $fileSizeUnit = convertFileSize($incrFileSize);
	$kbps =~ s/\s+//;
	$percent = sprintf "%4s", "$percent%";
	$spAce = " "x6;
	$boundary = "-"x(100/$progressSizeOp);
	$spAce1 = " "x(38/$progressSizeOp);
	
	my $fileDetailRow = "[$type] [$fileName][$trnsFileSize]";
	my $strLen  = length $fileDetailRow;
	$emptySpace = " "x($latestCulmn-$strLen);
	
	if($machineInfo eq 'freebsd'){
		system("tput rc");
		system("tput ed");	
		print $freebsdProgress;
	}
	
	system("tput rc");
	system("tput ed");
	
	print $fullHeader;
	print "$fileDetailRow $emptySpace\n\n";
	print "$spAce$boundary\n";
	print "$percent [";
	print $progress.$cellSize;
	print "]\n";
	print "$spAce$boundary\n";
	print "$spAce1\[$fileSizeUnit of $totalSizeUnit] [$kbps/s]$emptySpace\n";
	
	if($jobType =~ /Backup/i) {
		if($dedup eq 'on'){
			my $backupLoaction = $backupHost;
			print "\nBackup Location    : $backupLoaction\n";
		} else {
			print "\nBackup Location    : $backupHost\n";
			print "Backup Type        : ".ucfirst($backupPathType)."\n";			
		}
		print "Bandwidth Throttle : $bwThrottle%\n";	
	} else {
		my $restoreFromLoaction = $restoreHost;
		if($dedup eq 'on'){
			$restoreFromLoaction = (split('#',$restoreHost))[1] if($restoreHost =~ /#/);
		}	
		print "\nRestore From Location   : $restoreFromLoaction\n";
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
	my $tempJobType = $jobType;
	my $backupMountPath = '';
	if($tempJobType =~ /Local/){
		$tempJobType =~ s/Local//;
		$backupMountPath = "Mount Path : $expressLocalDir $lineFeed";
	}

	my $mailHeadA = $lineFeed."$tempJobType Start Time: ".(localtime)."$lineFeed";
	my $mailHeadB = '';
	
	if($jobType eq "Backup" and $dedup eq 'off') {
		$mailHeadB = "$tempJobType Type: ".ucfirst($backupPathType)." $lineFeed";
	}
	$mailHeadB .= "Machine Name: $host $lineFeed";
	$mailHeadB .= "Throttle Value: $bwThrottle% $lineFeed" if ($jobType eq "Backup");
	$mailHeadB .= "$tempJobType Location: $location $lineFeed";
	$mailHeadB .= $backupMountPath;
	if($tempJobType eq "Restore") {
		my $fromLocation = ($restoreHost =~ /#/)?(split('#',$restoreHost))[1]:$restoreHost;
		$mailHeadB .= "$tempJobType From Location: $fromLocation $lineFeed";
	}	
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
sub writeOperationSummary
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

		if(-d $excludeDirPath) {			
			$summary .= appendExcludedLogFileContents();			
		}
	
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
		if($_[0] eq Constants->CONST->{'BackupOp'}) {
			$mail_summary .= Constants->CONST->{'TotalBckCnsdrdFile'}.$filesConsideredCount.
						$lineFeed.Constants->CONST->{'TotalBckFile'}.$successFiles.
						$lineFeed.Constants->CONST->{'TotalSynFile'}.$syncedFiles.
						$lineFeed.Constants->CONST->{'TotalBckFailFile'}.$failedFilesCount.
						$lineFeed.$TBE_Text.$lineFeed.		# TBE : Enh-006
						$lineFeed.Constants->CONST->{'BckEndTm'}.localtime(). $lineFeed;
		
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
						$lineFeed.$TBE_Text.$lineFeed.		# TBE : Enh-006
						$lineFeed.Constants->CONST->{'RstEndTm'}.localtime(). $lineFeed;

			$finalSummery .= Constants->CONST->{'TotalRstCnsdFile'}.$filesConsideredCount.
					       $lineFeed.Constants->CONST->{'TotalRstFile'}.$successFiles.
					       $lineFeed.Constants->CONST->{'TotalSynFileRestore'}.$syncedFiles.
						$lineFeed.$TBE_Text.$lineFeed.		# TBE : Enh-006
					       $lineFeed.Constants->CONST->{'TotalRstFailFile'}.$failedFilesCount.$lineFeed;
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
	my $usrBackupManualDirSch = "$usrProfilePath/$userName/Backup/Scheduled";
	my $usrlocalBackupDir = "$usrProfilePath/$userName/LocalBackup";
	my $usrlocalBackupManualDir = "$usrProfilePath/$userName/LocalBackup/Manual";
	my $usrRestoreDir = "$usrProfilePath/$userName/Restore";
	my $usrRestoreManualDir = "$usrProfilePath/$userName/Restore/Manual";
	my $usrRestoreManualDirSch = "$usrProfilePath/$userName/Restore/Scheduled";
	my $userInfo = "$usrProfileDir/.userInfo";
	
	my @dirArr = ($usrProfilePath, $usrProfileDir, $usrBackupDir, $usrBackupManualDir, $usrRestoreDir, $usrRestoreManualDir,$usrBackupManualDirSch,$usrRestoreManualDirSch,$userInfo,$usrlocalBackupDir,$usrlocalBackupManualDir);
	
	foreach my $dir (@dirArr) {
		if(! -d $dir) {
			$mkDirFlag = 1;
			my $ret = mkdir "$dir", $filePermission;
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
    
	if(!open(PIDFILE, '>', $pidPath)) {
		traceLog("Cannot open '$pidPath' for writing: $!", __FILE__, __LINE__);
		return 0;
	}
	if(!flock(PIDFILE, 2|4)) {
		return 0;
	}
	autoflush PIDFILE;
	print PIDFILE $$;
	chmod $filePermission, $pidPath;	
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
	my $inputTerminationChar = $/;
	
	system "stty cbreak </dev/tty >/dev/tty 2>&1";
	print "\e[6n";
	$/ = "R";
	$x = <STDIN>;
	$/ = $inputTerminationChar;
	
	system "stty -cbreak </dev/tty >/dev/tty 2>&1";	
	my ($curLines, $cols)=$x=~m/(\d+)\;(\d+)/;
	system('stty', 'echo');
	my $totalLines = `tput lines`;
	chomp($totalLines);
	my $threshold = $totalLines-11;
	
	if($curLines >= $threshold) {
		system("clear");
		print "\n";
		$curLines = 0;
	} else {
		$curLines = $curLines-1;
	}
	
	changeSizeVal();
	print $lineFeed;
	system("tput sc");
	print "\n$_[0]" if ($_[0] ne '');	
	print Constants->CONST->{'PrepFileMsg'}.$lineFeed;
}

#****************************************************************************************************
# Subroutine Name         : changeSizeVal.
# Objective               : Changes the size op value based on terminal size change.				
# Modified By             : Dhritikana.
#*****************************************************************************************************/
sub changeSizeVal {
	$latestCulmn = `tput cols`;
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
	my $tmpBackupHost=$backupHost; 
	
	my $displayLocation = $backupHost;
	if($jobType eq "Backup" or $jobType eq "LocalBackup") {
		#my $encType = checkEncType(1);
		my $oldBackupLoc = '';
		my $backupLocationCheckCount = 0;
		my $currentBackupLocation='';
		my $locName = (($backupHost eq $hostName) or (substr($backupHost, 1) eq $hostName)) ? q{default Backup} : q{Backup};
		if($backupHost eq $hostName or substr($backupHost, 1) eq $hostName or $backupHost eq "") {
			$locationQuery = Constants->CONST->{'defBackupLocMsg'};
			$displayLocation = $hostName;
			$defaultLocationFlag=1;
		}
	       
		print $lineFeed.$locationQuery." \"$displayLocation\"\. ".Constants->CONST->{'reallyEditQuery'};
		my $choice = getConfirmationChoice();
		if(($choice eq "n" || $choice eq "N")) {
			$backupHost = "/".$hostName if($defaultLocationFlag);
			print $lineFeed;
		} 
		else {
			if (runningJobHandler($jobType,'Scheduled',$userName,$usrProfilePath)){#This check will allow to change location only if backup job is not running.
				#get user backup location
				print Constants->CONST->{'AskLocforBackup'};
				while ($currentBackupLocation !~ /^(?=.{4,64}$)^[A-Za-z0-9_\-]+$/){
				#while ($currentBackupLocation !~ /[^\s\/]+/g){
						
						if ($backupLocationCheckCount>0){
							print Constants->CONST->{'InvLocInput'};
							#print Constants->CONST->{'locationQuery'} ;
							#print $lineFeed.Constants->CONST->{'AskLocforBackupInRetry'}.' '.Constants->CONST->{'BackupLocNoteDedup'}.': ';
							print $lineFeed.$Locale::strings{'enter_your_backup_location_optional'}.': ';
						}
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
#					if (comapareLocation($backupHost,$currentBackupLocation)){
#						 if (ref $_[0] eq 'SCALAR'){
#						 	${$_[0]} = qq{Your Backup Location changed successfully to "$backupHost".$lineFeed};
#						 }else{
#							print qq{Your Backup Location changed successfully to "$backupHost".$lineFeed};
#							holdScreen2displayMessage(2);
#						 }
#					}else{
						$oldBackupLoc = $backupHost;
						$backupHost = $currentBackupLocation;
						print Constants->CONST->{'SetBackupLoc'}.$lineFeed;
						my $createDirUtfFile = getOperationFile(Constants->CONST->{'CreateDirOp'});
						chomp($createDirUtfFile);
				        	$createDirUtfFile =~ s/\'/\'\\''/g;
					        $idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$createDirUtfFile."'".$whiteSpace.$errorRedirection;
				        
						$commandOutput = `$idevsutilCommandLine`;
					        unlink($createDirUtfFile);
						$backupHost = '/'.$backupHost if ($backupHost !~/^\//);
                                                        if (appLogout($commandOutput)){
								print Constants->CONST->{'UnableToConnect'}.$lineFeed;
								cancelProcess();
							}
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
								$backupHost = '/'.$backupHost if ($backupHost !~/^\//);
								if (ref $_[0] eq 'SCALAR'){
									${$_[0]} = qq{\nUnable to change, your $locName location remains "$backupHost". $lineFeed $lineFeed};
								}else{
									print qq{\nUnable to change, your $locName location remains "$backupHost". $lineFeed $lineFeed};
									holdScreen2displayMessage(2);
								}
							}
						
				#		}
					}
			}else{
				if (ref $_[0] eq 'SCALAR'){
					${$_[0]} = qq{\nYour Backup Location remains "$backupHost" . $lineFeed $lineFeed};
				}else{
					print qq{\nYour Backup Location remains "$backupHost" . $lineFeed $lineFeed};
					holdScreen2displayMessage(2);
				}
			}
			if($isSameDeviceID){
				$restoreHost = $backupHost;
				putParameterValue(\"RESTOREFROM",\"$restoreHost",$configFilePath);#This function will update  restore location to conf file. Added do keep the same Nick name if device ids are same.
			}
		}
	
		putParameterValue(\"BACKUPLOCATION", \"$backupHost", $confFilePath);
		putParameterValue(\"SERVERROOT",\"$serverRoot",$configFilePath);

		if($restoreHost eq "") {
			$restoreHost = $backupHost;
			putParameterValue(\"RESTOREFROM", \"$restoreHost", $confFilePath);
			print Constants->CONST->{'restoreFromSet'}." $restoreHost $lineFeed";
		}
	} 
	elsif($jobType eq "Restore") {
		my ($existCheck, $restoreLocationCheckCount) = (0) x 2;
		my $tempRestoreHost = $restoreHost; #to keep data of $restoreHost variable unchanged while checking location validity.
		my ($currentRestoreLocation, $locName) = ('') x 2;
		
		$choice = 'y';
		if($dedup eq 'off' or ($dedup eq 'on' and $restoreHost ne '' )){
			$locName = (($restoreHost eq $hostName) or (substr($restoreHost, 1) eq $hostName)) ? q{default Restore} : q{Restore};
			my $restoreLocationMess = qq{\nYour $locName From Location is "$restoreHost". }.Constants->CONST->{'editQuery'};
			if($backupHost eq $restoreHost){
				$restoreLocationMess = qq{\nAs per your Backup Location your $locName From Location is "$backupHost". }.Constants->CONST->{'editQuery'};
			}
			print $restoreLocationMess;
			$choice = getConfirmationChoice();
		}
			
		if($choice eq 'y' || $choice eq 'Y') {
			#This check will allow to change location only if restore job is not running. If running, first terminate.
			if (runningJobHandler('Restore','Scheduled',$userName,$usrProfilePath)){
				if ($dedup eq 'off'){
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
#					if (comapareLocation($restoreHost,$tempRestoreHost) and $existCheck == 0){
#							print qq{Your Restore from location changed successfully to $restoreHost.$lineFeed};
#							holdScreen2displayMessage(2) if ($_[0] eq '');
#					}else{
						my $locationEntryCount = 0;
						while($existCheck eq 0){
							#RHFileName has been used to keep the restore host name in file and pass it to Item status EVS commands.
							open (RH,'>',"$usrProfileDir/Restore/Manual/RHFileName") or die "unable to open file. Reason $!";  
							print RH $tempRestoreHost;
							close(RH);
							my $propertiesFile = getOperationFile(Constants->CONST->{'ItemStatOp'},"$usrProfileDir/Restore/Manual/RHFileName");
#							my $propertiesFile = getOperationFile(Constants->CONST->{'PropertiesOp'},$tempRestoreHost);
							chomp($propertiesFile);
							$propertiesFile =~ s/\'/\'\\''/g;
#							$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$propertiesFile."'".$whiteSpace.$errorRedirection;
							$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$propertiesFile."'";
							my $commandOutput = `$idevsutilCommandLine`;
							unlink $propertiesFile;
                                                        my $invalidLocationFlag = 0;
							if(-s "$usrProfileDir/Restore/Manual/error.txt" > 0){
								if(appLogout("$usrProfileDir/Restore/Manual/error.txt")){
									 print Constants->CONST->{'UnableToConnect'}.$lineFeed;
		                                                         cancelProcess();
								}
							}
							else
							{
								if($commandOutput =~ /No such file or directory|directory exists in trash/) {
									$& =~ /directory exists in trash/ ? print Constants->CONST->{'NoDirectoryEvsMsg'}.$lineFeed : print Constants->CONST->{'NoFileEvsMsg'}.$lineFeed; 								
									print Constants->CONST->{'RstFromGuidMsg'}.$lineFeed;
									print Constants->CONST->{'restoreFromDir'};
									$currentRestoreLocation = getLocationInput("restoreHost");
									if ($restoreLocationCheckCount == 3) {
										$currentRestoreLocation = q{Invalid Location};
        	                                				$restoreLocationCheckCount=0;
		                                	        		$existCheck = 1;
        	                        				}
									if($currentRestoreLocation eq 'Invalid Location'){
										$restoreHost = '/'.$restoreHost if ($restoreHost !~/^\//); 
										print  qq{Your maximum attempt to change Restore from location has reached. \nYour Restore from location remains "$restoreHost".$lineFeed $lineFeed};
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
									$restoreHost = '/'.$restoreHost if ($restoreHost !~/^\//);
									print qq{Your Restore from location has been changed to "$restoreHost".$lineFeed};
									holdScreen2displayMessage(2) if ($_[0] eq '');
								}
							}
							if ($locationEntryCount==3){
							       	print $lineFeed.Constants->CONST->{'maxRetryRestoreFrom'}.$lineFeed.qq{ Your $locName from location remains "$restoreHost".$lineFeed $lineFeed};
		                                                holdScreen2displayMessage(2) if ($_[0] eq '');
        	                                               	last;
                	                                }
							$locationEntryCount++;
						}
					#} 
				}elsif($dedup eq 'on'){
					print $lineFeed.Constants->CONST->{'LoadingAccDetails'};
					%evsDeviceHashOutput = getDeviceList();
					my $totalElements = keys %evsDeviceHashOutput;
					if ($totalElements == 1 or $totalElements == 0){
						print $lineFeed.$lineFeed.Constants->CONST->{'restoreFromLocationNotFound'}.$lineFeed.$lineFeed;
						unlink($pidPath) if(-e $pidPath);
						exit(0);
					}
					checkAndLinkBucketSilently(); #Added to update UID silently
					print $lineFeed.Constants->CONST->{'selectRestoreFromLoc'}.$lineFeed;
					my @devicesToLink = displayDeviceList(\%evsDeviceHashOutput,\@columnNames);
					my $userChoice = getUserMenuChoice(scalar(@devicesToLink),4);
					$userChoice -= 1;
					$restoreHost = $deviceIdPrefix.$devicesToLink[$userChoice]->{device_id}.$deviceIdPostfix.'#'.$devicesToLink[$userChoice]->{nick_name};
					print $lineFeed.Constants->CONST->{'RestoreLocMsg'}.$whiteSpace.'"'.$devicesToLink[$userChoice]->{nick_name}.'"'.$lineFeed;
				}
			}else{
				print qq{\nYour Restore from location remains "$restoreHost".$lineFeed $lineFeed};
				holdScreen2displayMessage(2) if ($_[0] eq '');
			}
            	putParameterValue(\"RESTOREFROM", \"$restoreHost", $confFilePath);
        	if ($dedup eq 'on'){
	                ($restoreDeviceID,$restoreHost) = split ('#',$restoreHost);
            }
		}
		
		if(!$noRestoreLocation){#In case of restore version script call to below sub is restricted. Other cases it will work.
			#In case of restore script we r calling this sub seperately inside Restore_Version.pl script.
			askRestoreLocation($_[0]);
		}
	}
}
#****************************************************************************
# Subroutine Name         : appLogout
# Objective               : If error matched with the mentioned error messages. Then logout from the script.
# Added By                : Abhishek Verma.
#****************************************************************************/
sub appLogout{
	my $errorMessage = $_[0];
	if (-e $_[0] and -f $_[0]){
		if (!open(EF,'<',$_[0])){ #EF means error file handler.
			traceLog("Failed to open $_[0], Reason:$! $lineFeed", __FILE__, __LINE__);
        	print "Failed to open $statusFilePath, Reason:$! $lineFeed";
	        cancelProcess();
		}
		chop($errorMessage = <EF>);
		close(EF);
	}
	if (grep {$errorMessage =~ /$_/} @ErrorArgumentsExit){
		unlink($pwdPath);	
		return $errorMessage;
	}
	return 0;
}
#****************************************************************************
# Subroutine Name         : askRestoreLocation.
# Objective               :
# Added By                : Abhishek Verma.
#****************************************************************************/
sub askRestoreLocation{
	my $continue = $_[1];
	my $locName = ($restoreLocation =~ /\/?$usrProfilePath\/$userName\/Restore_Data\/?/) ? q{default Restore} : q{Restore};
	print qq{\nYour $locName Location is set to "$restoreLocation". }.Constants->CONST->{'reallyEditQuery'};
	my $choiceR = getConfirmationChoice();
	if($choiceR eq "y" || $choiceR eq "Y") {
		my $resetRestoreLocation = $restoreLocation;#Copy of restore location
		my $retryCount = 4;
		my $mkdirErrorFlag = 0;
		my $restoreLocStatus = 0;
		while($retryCount) {
	#		get and set user restore location
			if($restoreLocStatus == 2){
				$askLocation = $retryCount == 4 ? Constants->CONST->{'AskRestoreLocRepet'} : Constants->CONST->{'locationQuery'};
			} else {
				$askLocation = $retryCount == 4 ? Constants->CONST->{'AskRestoreLocRepet'} : Constants->CONST->{'InvLocInput'}.Constants->CONST->{'locationQuery'};			
			}
			getRestoreLocation($0,$askLocation);
			Chomp(\$restoreLocation);
			
			if ($restoreLocation ne "" or $continue){
				$restoreLocStatus = checkRestoreLocation($restoreLocation);
				if ($restoreLocStatus == 1){
					print qq(Restore Location "$restoreLocation" exists.$lineFeed);
					print Constants->CONST->{'RestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
					holdScreen2displayMessage(2);
					last;
				}elsif ($restoreLocStatus == 2){
					$retryCount = $retryCount-1;
				}else{
					if (!(comapareLocation($restoreLocation,$resetRestoreLocation))){
						my $res = setRestoreLocation("$restoreLocation","$resetRestoreLocation","$askLocation");
						
						$restoreLocation=~s/^\'//;
						$restoreLocation=~s/\'$//;
						$mkdirErrorFlag = 0; 					#For every fresh loop this flag is reset to zero.
						if ($res eq ""){
							if (ref $_[0] eq 'SCALAR'){
								${$_[0]} .= Constants->CONST->{'RestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
							}
							else{
								print Constants->CONST->{'RestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
							}
							chmod $filePermission, $restoreLocation;
							last;
						}
						elsif($res eq 'EXISTS'){
							if (ref $_[0] eq 'SCALAR'){
								${$_[0]} .= qq(\nRestore Location $restoreLocation exists... $lineFeed);
							}else{
								print qq(\nRestore Location $restoreLocation exists... $lineFeed);
							}	
							last;
						}
						else{
							if ($res =~ /mkdir:.*(Permission denied)/i){
								$mkdirErrorFlag = 1;
								print Constants->CONST->{'InvRestoreLoc'}.qq(: $restoreLocation. $1.\n);
								$retryCount = $retryCount-1;
							}
						}
						last	if ($retryCount == 0);
					}
					else{
						if (ref $_[0] eq 'SCALAR'){
							${$_[0]} .= Constants->CONST->{'restoreLocNoChange'}.qq{ "$restoreLocation".};
						}
						else{
							print Constants->CONST->{'restoreLocNoChange'}.qq{ "$restoreLocation".};
						}
						last;
					}
				}	
			}
			else{
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
	}
	else{
		if (-e $restoreLocation){
			if (validateDir($restoreLocation)){
				print Constants->CONST->{'InvRestoreLoc'}.qq(. Reason : "$restoreLocation" ).Constants->CONST->{'noSufficientPermission'}.'. '.Constants->CONST->{'providePermission'}.$lineFeed;
		                #unlink($pidPath);
        		        cancelProcess();
        		}
		}else{
			#print Constants->CONST->{'InvRestoreLoc'}.qq(. Reason : "$restoreLocation" ).Constants->CONST->{'notExists'}.'. '.Constants->CONST->{'TryAgain'}.$lineFeed;
			print Constants->CONST->{'YourRestoreLocationNotExist'}.$lineFeed;
			cancelProcess();
		}
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
#	$finalMessage = q(Please try to login using 'login.pl');
	my $confirmChoice = undef;
	my $count = 0;	
	while(!defined $confirmChoice) {
		$count++;
		if($count eq 5) {
			print "Your maximum retry attempts reached. $finalMessage \n";
			cancelProcess();
			exit;
		}
		print $lineFeed.Constants->CONST->{'EnterChoice'};
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

	return $confirmChoice;
}

#****************************************************************************
# Subroutine Name         : getLocationInput
# Objective               : Get location input from terminal. 
# Added By                : Dhritikana
#****************************************************************************/
sub getLocationInput {
	my $input=<STDIN>;
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
		my $mkRes = `mkdir -p '$traceDir' $errorRedirection`;
                Chomp(\$mkRes);
                if ($mkRes !~ /Permission denied/){
                         changeMode($idriveServicePath);
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
		writeToTrace($traceFileName, "$appType Username: " . $userName . "\n");
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
			$jobStatus = qq($jobType has been completed.); 
		}elsif($jobStatus eq 'FAILURE' or $jobStatus eq 'ABORTED'){
			$jobStatus = defined ($errString) ? $errString : qq($jobType has been failed.);
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
	if(open (FS,'>',$fileName)){
		print FS $content;
		close (FS);
	} else {
		if($! =~ /.*?(Permission\s+denied).*/){
			print qq(\nUnable to create the file "$fileName". Please provide the full permission to the parent directories.\n);
		} else {
			print qq(\nUnable to open file. Reason: $!\n);
		}
		cancelProcess();
	}
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
			my $JobTermCmd = "perl  '$jobTerminationScript' manual_$jobType $username";
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
        my $res = createDirectory("$location","DEFAULT");
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
#Sbroutine Name         : clearFile(REFERENCE_TO_VARIABLE);
#Objective              : This function will clear xml tags which are not required and some data which are not useful.
#Usage                  : clearSpecialChar(\$someVariable)
#                         Where:
#                         $someVariable = variable name from where unuseful data should be removed.
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub clearFile{
	my $fileData = shift;
	${$fileData} =~ s/<\?xml.*?\??>//g; #clearing xml header if any in the file data.
	${$fileData} =~ s/<root>//g;
	${$fileData} =~ s/<\/root>//g;
	${$fileData} =~ s/(?:connection\s+established)?//;
	${$fileData} =~ s/<\/login>//;
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
			$cmd = "mkdir '$location' $errorRedirection"; #Need not to add single quote again
        }else{
			$cmd = "mkdir -p '$location' $errorRedirection";
        }
		$result = `$cmd`;
		chmod $filePermission, $location;
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
        my $testPath    = $restoreLocation."/Idrivetest.txt";
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
	my $userLocMessage= ($defaultKey eq 'DEFAULT')? Constants->CONST->{'defaultRestLocMess'}.qq( "$restoreLocation" $lineFeed) : Constants->CONST->{'restoreLocCreation'}.$lineFeed;
	my $res = q();
        $restoreLocation .= '/' if(substr($restoreLocation, -1, 1) ne "/");
        if( -f $restoreLocation or -l $restoreLocation or -p $restoreLocation or -S $restoreLocation or -b $restoreLocation or -c $restoreLocation or -t $restoreLocation) {
		print Constants->CONST->{'InvRestoreLoc'}.$whiteSpace.": \"$restoreLocation\"".$lineFeed;
                $restoreLocation = $defaultRestoreLocation;
                $res = createDefaultRestoreLoc($restoreLocation);
        }else{
                print $userLocMessage;
                $restoreLocation = '/'.$restoreLocation if(substr($restoreLocation, 0, 1) ne "/");
                #$restoreLocation = qq('$restoreLocation');
                $res = createDirectory($restoreLocation,$defaultKey);
        }
	$res='' if ($res =~ /File exists/);
	return $res;
}
#*********************************************************************************************************
#Subroutine Name        : checkRestoreLocation
#Objective              : This function will check restore location and return following:
#			  If given Restore Location exists and has write permission then return 1.
#			  If given Restore Location exists and does not have write permission then return 2.
#			  If given Restore Location does not exists then return 0.
#Usage                  : checkRestoreLocation(RESTORE_LOCATION);
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub checkRestoreLocation{
	my $restoreLoc = shift;
	if (-d $restoreLoc){
		if (hasWritePermission()){#If restore location exists and has write permission then return 1.
                        return 1;
		}
		print Constants->CONST->{'InvRestoreLoc'}.qq(: "$restoreLocation". Permission denied.\n);		
		return 2;#If restore location exists but no write permission then return 2.
	}
	return 0;#If restore location does not exists.
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
		chomp(${$_[0]});
        ${$_[0]} =~ s/^[\s\t]+|[\s\t]+$//g;
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
	unlink($pidPath);
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
	#Keeping 0777 as hardcoded value only
	my $res	= `chmod -R 0777 '$_[0]' $errorDevNull`;
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
	return 1 if($err_string eq "");
	
	if ($taskType eq "Scheduled"){
		$mail_content = qq{\n$err_string\nAfter complition, run scheduled $jobType Job again.};
		my $subjectLine = "$taskType $jobType Email Notification "."[$userName]"." [Failed $jobType]";
		$status = "FAILURE";
		traceLog($err_string."$lineFeed", __FILE__, __LINE__);
		sendMail($subjectLine);
	}
	print qq($err_string);
	return 0;	
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
	$updateAvailMessage   .= Constants->CONST->{'ScriptBuildVersion'};
	$updateAvailMessage   .= qq(                    Developed By: $appMaintainer);
	$updateAvailMessage   .= qq(\n----------------                    --------------------------------------------\n);
	$updateAvailMessage   .= qq(Logged in user :                    );
	$updateAvailMessage   .= $displayCurrentUser eq '' ? "No Logged In User":$displayCurrentUser; 
	my %quotaDetails = getQuotaDetails();
#==================================================
#TBE : ENH-004 - Get Quota, compute remaining quota
#	if (scalar (keys %quotaDetails) == 2){  #TBE : ENH-004 - fix
		my $totalQuota = convertFileSize($quotaDetails{totalQuota});
		my $usedQuota = convertFileSize ($quotaDetails{usedQuota});
		my $remaining = convertFileSize ($quotaDetails{remainingQuota});			#TBE : ENH-004
		$updateAvailMessage .= qq(\n----------------                    --------------------------------------------\n);
#		$updateAvailMessage .= qq(Quota Display  :                    $usedQuota(used)/$totalQuota(total));
		$updateAvailMessage .= qq(Quota Display  :  $remaining(free)/$usedQuota(used)/$totalQuota(total));
#	}
#==================================================
	if ($callingScript ne Constants->FILE_NAMES->{checkForUpdateScript} and !isUpdateAvailable()){ # Dont want to call subroutine isUpdateAvailable() in case of calling script is check_for_update.pl
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
	$serviceDir = $appTypeSupport eq 'ibackup' ? 'ibackup' : 'idrive';
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
	#if ($_[0] =~ /^(?=.{4,20}$)(?!.*[_]{2})(?!\s+)[a-z0-9_]+$/){
	if ($_[0] =~ /^[a-z0-9\@_.-]{4,50}$/){
		$validUserPattern = 1;
	}
	#elsif(validEmailAddress($_[0])){
	#	$validUserPattern = 1;
	#}
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
# Subroutine Name			: isUpdateAvailable 
# Objective					: To check if update is available, create a file with .updateVersionInfo and write the current version.
# Usgae						: isUpdateAvailable
# Added By					: Abhishek Verma
# Modified By				: Sabin Cheruvattil
#****************************************************************************
sub isUpdateAvailable {
	my $check4updateScript	= "'$userScriptLocation/" . Constants->FILE_NAMES->{checkForUpdateScript} . "'";
	my $updateAvailStats = '';
	$check4updateScript 	= qq($check4updateScript checkUpdate);
	if(-e $userScriptLocation.'/.updateVersionInfo' and -s $userScriptLocation.'/.updateVersionInfo' > 0) {
		return 0; #True
	} else {
		# chomp($updateAvailStats = `perl $check4updateScript $usrProfileDir`);
		open (CHECKUPDATE, "perl $check4updateScript |") or die "Failed to create process: $!\n"; #Making Asynchronous call to check_for_update.pl
		if (-e $userScriptLocation.'/.updateVersionInfo' and -s $userScriptLocation.'/.updateVersionInfo' > 0) {
			return 0;
		}
		
		return 1;
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
	my $WaitTime = 0;
	my $Continue = 0;
	my $getQuotaUtfFile = '';
	my $commandOutput = '';
	my %evsHashOutput;
# Get a Valid answer
	do {
		sleep( $WaitTime );
		$WaitTime += 120 + rand( 30 );	# Ajoute Entre 50 et 60 secondes au prochain temps d'attente
		$getQuotaUtfFile = getOperationFile(Constants->CONST->{'GetQuotaOp'},$encType);
		$getQuotaUtfFile =~ s/\'/\'\\''/g;
		$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$getQuotaUtfFile."'".$whiteSpace.$errorRedirection;
		traceLog($idevsutilCommandLine."$lineFeed", __FILE__, __LINE__);
		$commandOutput = `$idevsutilCommandLine &`;
		%evsHashOutput = parseXMLOutput(\$commandOutput);
		$Continue = (	($evsHashOutput{message} eq 'ERROR') and ($evsHashOutput{desc} =~ /Try again/) and ($WaitTime < 600)	);
		traceLog('Outputs : '.$lineFeed.$commandOutput.$lineFeed, __FILE__, __LINE__);
	} while ($Continue eq 1);
	if (($evsHashOutput{message} eq 'SUCCESS') and ($evsHashOutput{totalquota} =~/\d+/) and ($evsHashOutput{usedquota} =~/\d+/)){
		$evsHashOutput{usedquota} =~ s/(\d+)\".*/$1/isg;
		$evsHashOutput{remainingquota} = $evsHashOutput{totalquota} - $evsHashOutput{usedquota};


	}
#	} while (	(	($evsHashOutput{message} eq 'ERROR') and ($evsHashOutput{desc} =~ /Try again/)	)	or ($WaitTime > 600)	);
	unlink($getQuotaUtfFile);
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
	
	open (AQ,'>',$FileName) or (traceLog($lineFeed.Constants->CONST->{'FileCrtErr'}.$FileName."failed reason: $! $lineFeed", __FILE__, __LINE__) and die);# File handler AQ means Account Quota.
	chmod $filePermission,$FileName;
	if ($totalquota =~/\d+/ and $usedquota =~ /\d+/ and $remainingquota =~ /\d+/){
		print AQ 'totalQuota=' . $totalquota . "\n";
		print AQ 'usedQuota=' . $usedquota . "\n";
		print AQ 'remainingQuota=' . $remainingquota . "\n";
	}
	close AQ;
	traceLog('Write File : '.$FileName."$lineFeed", __FILE__, __LINE__);
}
#=====================================================================================================================
#*********************************************************************************************************
#Subroutine Name         : getQuotaForAccountSettings 
#Objective               : This function will create a quota.txt file based on the quota details provided
#Usgae                   : getQuotaForAccountSettings()
#Added By                : Abhishek Verma.
#*********************************************************************************************************/
sub getQuotaForAccountSettings
{
	my $accountQuota = $_[0];
	my $quotaUsed = $_[1];
#=====================================================================================================================
#TBE : ENH-004 - Quota remaining
  my $remainingquota = $accountQuota - $quotaUsed;
	WriteQuotaFile( $usrProfileDir.'/.quota.txt',
					$filePermission,
					$accountQuota,
					$quotaUsed,
					$remainingquota);
# Mutualized code          
#	open (AQ,'>',$usrProfileDir.'/.quota.txt') or (traceLog($lineFeed.Constants->CONST->{'FileCrtErr'}.$enPwdPath."failed reason: $! $lineFeed", __FILE__, __LINE__) and die);# File handler AQ means Account Quota.
#	chmod $filePermission,$usrProfileDir.'/.quota.txt';
#	if ($accountQuota =~/\d+/ and $quotaUsed =~ /\d+/){
#		$quotaUsed =~ s/(\d+)\".*/$1/isg;
#		print AQ "totalQuota=$accountQuota\n";
#		print AQ "usedQuota=$quotaUsed\n";
#	}
#	close AQ;
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
	my %evsQuotaHashOutput = getQuota_HashTable();
# Mutualized code
#	my $encType = checkEncType(1);
#	my $getQuotaUtfFile = getOperationFile(Constants->CONST->{'GetQuotaOp'});
#	$getQuotaUtfFile =~ s/\'/\'\\''/g;
#        $idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$getQuotaUtfFile."'".$whiteSpace.$errorRedirection;
#	my $commandOutput = `$idevsutilCommandLine`;
#        unlink($getQuotaUtfFile);
#	my %evsQuotaHashOutput = parseXMLOutput(\$commandOutput);
#=====================================================================================================================

	if (($evsQuotaHashOutput{"message"} eq 'SUCCESS') and ($evsQuotaHashOutput{"totalquota"} =~/\d+/) and ($evsQuotaHashOutput{"usedquota"} =~/\d+/)){
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
		#foreach my $jobFileName ( sort {lc $a cmp lc $b} keys %{$userMenu}){
		foreach my $jobFileName ( sort keys %{$userMenu}){
		    my $job = $jobFileName;
			$job =~ s/^\d.//;
			print "$job:$lineFeed";
			foreach my $filePosition ( sort keys %{$userMenu->{$jobFileName}}){
				print qq(   $filePosition\) $userMenu->{$jobFileName}->{$filePosition}->[0]$lineFeed);
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
	my $totalChoice = $_[2];
	if($totalChoice==8){
        $keyName = $userChoice =~ /^1$|^2$/ ? $keyName2Return[0]:$userChoice =~ /^3$/ ? $keyName2Return[1]:$userChoice =~ /^4$|^5$|^6$/ ? $keyName2Return[2]:$userChoice =~ /^7$|^8$/ ? $keyName2Return[3]:'';
	} else {
        $keyName = $userChoice =~ /^1$|^2$/ ? $keyName2Return[0] : $userChoice =~ /^3$/ ? $keyName2Return[1]  :$userChoice =~ /^4$|^5$/ ? $keyName2Return[2]: $userChoice =~ /^6$|^7$/ ? $keyName2Return[3] :'';
	}
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
	my $daysToSubstract = ($userOption == 1) ? 6 : ($userOption == 2) ? 14 : 30;
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
	if(($userName ne '' and -e $serviceFileLocation and -s $serviceFileLocation > 0 and -e $usrProfileDir and -e $confFilePath and -s $confFilePath > 0) 
	# checking for account configuration when user is logged out
	or ($userName eq '' and -e $serviceFileLocation and -s $serviceFileLocation > 0 and -e $usrProfileDir)) {
		$accountConfReq = 0;
	}

	if($accountConfReq) {
		#displaying script header if passed
		$displayHeader->($0) if (defined ($displayHeader));
        print Constants->CONST->{'loginConfigAgain'}.$lineFeed;        
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
	my $serviceLocation = '';
	if (-e $serviceFileLocation and -s $serviceFileLocation > 0){
		open(SP,"<$serviceFileLocation");
		local $\ = '';
		$serviceLocation = <SP>;
		Chomp(\$serviceLocation);
	}
	return $serviceLocation;
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
        if($jobType eq "backup" || $jobType eq "localBackup") {
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
#Subroutine Name         : getTableHeader
#Objective               : To get the table header display with column name.
#Usgae                   : getTableHeader(@columnNames)
#                        : @columnNames       : This array contains the name of column and spaces required between two column nanes.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getTableHeader{
        my $logTableHeader = ('=') x (eval(join '+', @{$_[1]}));
        $logTableHeader .= $lineFeed;
        for (my $contentIndex = 0; $contentIndex <= scalar(@{$_[0]}); $contentIndex++){
                $logTableHeader .= $_[0]->[$contentIndex];
                $logTableHeader .= (' ') x ($_[1]->[$contentIndex] - length($_[0]->[$contentIndex]));#(total_space - used_space by data) will be used to keep separation between 2 data.
        }
        $logTableHeader .= $lineFeed;
        $logTableHeader .= ('=') x (eval(join '+', @{$_[1]}));
        $logTableHeader .= $lineFeed;
        return $logTableHeader;
}
#*********************************************************************************************************
#Subroutine Name        : getDeviceList
#Objective              : This function will provide the device list for particular IDrive dedup account.
#Usage                  : getDeviceList();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getDeviceList{
	my $dedupStatus = shift;
	my $listDeviceUtfFile = getOperationFile(Constants->CONST->{'ListDeviceOp'});
	chomp($listDeviceUtfFile);
	$listDeviceUtfFile =~ s/\'/\'\\''/g;
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$listDeviceUtfFile."'".$whiteSpace.$errorRedirection;
	$commandOutput = qx{$idevsutilCommandLine};
	unlink($listDeviceUtfFile);
	if ($commandOutput =~ /password\s+mismatch|encryption verification failed|Unable to proceed; private encryption key must be between 4 and 256 characters in length/i){
		return $commandOutput;
	}	
	return parseXMLOutput(\$commandOutput,Constants->CONST->{'parseDeviceList'});
}
#*********************************************************************************************************
#Subroutine Name        : displayDeviceList 
#Objective              : This function will display the available list of devices with given account on the screen.
#Usage                  : displayDeviceList(DEVICE_LIST,COLUM_NNAME);
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub displayDeviceList{
        my %evsHashData = %{$_[0]};
        my @columnNames = @{$_[1]};
        my $tableHeader = getTableHeader(@columnNames);
        my @dataToDisplay = qw(nick_name device_id os bucket_ctime ip);
        my ($tableData,$columnIndex,$serialNumber) = ('',1,1);
        my @uids = keys %{$evsHashData{uid}};
        my @linkDataList = ();
        foreach (@uids){
                my $positionNo = $evsHashData{uid}->{$_};
                $tableData .= $serialNumber;
                $tableData .= (' ') x ($columnNames[1]->[0] - length($serialNumber));
                my $linkDataHash = {};
                $columnIndex = 1;
                foreach(@dataToDisplay){
                        my %reversedHash = reverse(%{$evsHashData{$_}});
                        my $displayData = $reversedHash{$positionNo};
                        $displayData =~ s/(.*)\_\d+/$1/;
                        $linkDataHash->{$_} = $displayData;
			$displayData = trimData($displayData,$columnNames[1]->[$columnIndex]) if($columnIndex == 1 or $columnIndex == 3);
                        $tableData .= $displayData;
                        $tableData .= (' ') x ($columnNames[1]->[$columnIndex] - length($displayData));
                        $columnIndex++;
                }
                $tableData .= $lineFeed;
                $serialNumber += 1;
                push (@linkDataList,$linkDataHash);
        }
        if ($tableData ne ''){
                print "$tableHeader$tableData\n";
        }
        return @linkDataList;
}
#*********************************************************************************************************
#Subroutine Name        : trimData
#Objective              : This function will display the available list of devices with given account on the screen.
#Usage                  : trimData();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub trimData{
	my ($data,$dataLength) = @_;
	my $displayLen = $dataLength - 3;
	if (length($data) > $displayLen){
		$data = substr($data,0,($displayLen-4)).'[..]';
	}
	return $data;
}
#*********************************************************************************************************
#Subroutine Name        : getUserMenuChoice 
#Objective              : This function will get the user choice from device menu which is displayed on the screen.
#Usage                  : getUserMenuChoice(MAX_CHOICE,RETRY_COUNT,UserMessage);
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getUserMenuChoice{
    my $maxChoice   = shift;
    my $retryCount  = shift;	
	my $userMessage = shift;
	my $bucketOrMount = shift;
	$userMessage = defined($userMessage) ? $lineFeed.$lineFeed.$userMessage : 'Enter your choice: ';
    my $userChoice = 0;
    while ($retryCount){
		print $userMessage;
		$userChoice = <STDIN>;
		Chomp(\$userChoice);chomp($userChoice);
		if($bucketOrMount eq 'mount'){
			$userChoice =~ s/^0+//;
			if($userChoice eq 'q' or $userChoice eq 'Q'){
				last;				
			}
			if (!(($userChoice <= 0) || ($userChoice > $maxChoice))){
				$userChoice = $linkDataList[--$userChoice];
				if(-w $userChoice){
					last;
				}
				if($retryCount>1){
					print Constants->CONST->{'selectedMountNoPerm'}.' '.Constants->CONST->{'pleaseTryAgain'};
				} else {
					print Constants->CONST->{'selectedMountNoPerm'}.$lineFeed;
				}
			} else {
				print Constants->CONST->{'InvalidChoice'}.$whiteSpace;
			}
		}		
		else{
			last if ($userMessage =~ /Press Enter to go back to main menu/ and $retryCount <= 0);
			if ($userMessage =~ /Press Enter to go back to main menu/ and $userChoice eq ''){
				createOrLinkBucket(--$retryCount);
				return; # return the flow to calling place. Dont want ot return any value so no parameter passed
			}
			$userChoice =~ s/^0+//;
			if (!(($userChoice <= 0) || ($userChoice > $maxChoice))){
				last;
			}
			print Constants->CONST->{'InvalidChoice'}.$whiteSpace;
		} 
		$retryCount -= 1;
    }
	if ($retryCount == 0 or  $userChoice eq ''){
		print Constants->CONST->{'maxRetry'}.$lineFeed.$lineFeed;
        cancelProcess();	
	}
    return $userChoice;
}
#*********************************************************************************************************
#Subroutine Name        : linkBucket
#Objective              : This function will link with the available device/bucket in the account.
#Usage                  : linkBucket(DEVICE_ID);
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub linkBucket {
	#$encType = checkEncType(1) if($encType eq "");
	#my $linkToData = shift;
	#my $linkForRestore = shift if (scalar(@_)>-1);
	
	$configFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};
	my $deviceID = shift;
	my $deviceNickName = shift;
	my $isSameDeviceID = shift;
	if($deviceID eq '' or $deviceNickName eq ''){
		return 0;
	}
	#my ($deviceID,$deviceNickName) = ($deviceIdPrefix.$linkToData->{device_id}.$deviceIdPostfix,$linkToData->{nick_name});
	
	my $linkBucketUtfFile = getOperationFile(Constants->CONST->{'LinkBucketOp'},$deviceID,$deviceNickName);
	chomp($linkBucketUtfFile);
	$linkBucketUtfFile =~ s/\'/\'\\''/g;
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$linkBucketUtfFile."'".$whiteSpace.$errorRedirection;
	my $commandOutput = qx{$idevsutilCommandLine};
	unlink($linkBucketUtfFile);
	traceLog("DEBUG - link bucket :: $commandOutput", __FILE__, __LINE__);
	if ($commandOutput =~ /status=["]success["]/i){
		#$' =~ /device_id="(.*?)".*?nick_name="(.*?)".*/;
		$' =~ /device_id="(.*?)".*?server_root="(.*?)".*?nick_name="(.*?)".*/;
		$deviceID   = $deviceIdPrefix.$1.$deviceIdPostfix;
		$backupHost = $restoreHost =  "$deviceID#$3";
		$serverRoot = $2;
		# BackupLocation = "DeviceID#Nickname" Eg: "D01500371120000812023#/dedup1
		if(defined($isSameDeviceID)){	
			if($isSameDeviceID){
				putParameterValue(\"RESTOREFROM",\"$restoreHost",$configFilePath);
			}
			putParameterValue(\"BACKUPLOCATION",\"$backupHost",$configFilePath);
			putParameterValue(\"SERVERROOT",\"$serverRoot",$configFilePath);			
		} else {
			print Constants->CONST->{'BackupLocMsg'}.$whiteSpace."\"$3\"".$lineFeed;
		}
	}
}
#*********************************************************************************************************
#Subroutine Name        : getUniqueID
#Objective              : This function will return unique id.
#Usage                  : getUniqueID();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getUniqueID{
	my $cmd;
	my $ifConfigPath = `which ifconfig 2>/dev/null`;
	chomp($ifConfigPath);
	if($ifConfigPath ne '') {
		$cmd = 'ifconfig -a';
	}
	elsif (-f '/sbin/ifconfig') {
		$cmd = '/sbin/ifconfig -a';
		}
	elsif (-f '/sbin/ip') {
		$cmd = '/sbin/ip addr';
	}
	else {
		print "Unable to find MAC Address.".$lineFeed;
		return 0;
	}

	my $result = `$cmd`;
	my @macAddr = $result =~ /HWaddr [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		$macAddr[0] =~ s/HWaddr |:|-//g;
		#traceLog("NEW UID: $macAddr[0]", __FILE__, __LINE__);
		return ($muid = ('Linux' . $macAddr[0]));
	}

	@macAddr = $result =~ /ether [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		#traceLog("NEW UID: $macAddr[0]", __FILE__, __LINE__);
		$macAddr[0] =~ s/ether |:|-//g;
		return ($muid = ('Linux' . $macAddr[0]));
	}

	return 0;
}
#*********************************************************************************************************
#Subroutine Name        : checkIfEvsWorking
#Objective              : This function will check if the available EVS is working or not.
#Usage                  : checkIfEvsWorking(DEDUP_STATUS);
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub checkIfEvsWorking {
	my $dedupStatus = shift;
	$idevsutilBinaryPath = "$idriveServicePath/$idevsutilBinaryName";
	$idevsutilBinaryPath = "$idriveServicePath/$idevsutilDedupBinaryName" if ($dedupStatus eq 'on');#here binary path is created for dedup command.
	return 0 if (!-f $idevsutilBinaryPath);
		
	chmod $filePermission, $idevsutilBinaryPath;
	my @idevsHelp = `'$idevsutilBinaryPath' -h 2>/dev/null`;
	return 0 if(scalar(@idevsHelp) < 50 );
	
	return 1;
}
#*********************************************************************************************************
#Subroutine Name        : checkDeviceID
#Objective              : In case of dedup this function will check if the available uid exists based on that 3 operations will be carried out.
#			  			1. If no uid found matching and no devices present in the list of devices, get bucket name (backup location) from user and create it.
#			  			2. if uid matched the ask user for changing the name of the bucket.
#			  			3. if uid not matched in the list of devices and other devices are present in the account.Then option is displayed to link to existing bucket or create new bucket.
#Usage                  : checkDeviceID(); or checkDeviceID(USER_CHOICE) - this is called in case of backup script.
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub checkDeviceID{
	my $userInput = $_[0];
	%evsDeviceHashOutput = getDeviceList();
	return 0 if (keys %evsDeviceHashOutput == 1);
	my $totalElements = keys %evsDeviceHashOutput;
	my $needToUpdateRestFrom =0;
	   $needToUpdateRestFrom =1 if($backupLoc eq $restoreFrom);
	
	my %deviceIdHash = reverse(%{$evsDeviceHashOutput{device_id}});
	my %nickNameHash = reverse(%{$evsDeviceHashOutput{nick_name}});
	my %serverRootHash = reverse(%{$evsDeviceHashOutput{server_root}});
	my %uniqueIdHash = reverse(%{$evsDeviceHashOutput{uid}});

    if ($totalElements == 1 or $totalElements == 0){
		my ($listDeviceMessage) = keys %evsDeviceHashOutput;
		if ($listDeviceMessage =~ 'No devices found' or $totalElements == 0){
			getBucketName();
			createBucket();
		}
		return;
    }
	else{
		checkAndLinkBucketSilently();
    }
		
	if(exists($evsDeviceHashOutput{uid}->{$uniqueID})){#Verifying if the unique id exists in the list of devices. If true find the corresponding device id and write that to key "BACKUPLOCATION" and "RESTOREFROM" of configuration file respectively.
		my $locationQuery = '';
	    my $choice = '';

		%deviceIdHash = reverse(%{$evsDeviceHashOutput{device_id}});
		%nickNameHash = reverse(%{$evsDeviceHashOutput{nick_name}});
		%serverRootHash = reverse(%{$evsDeviceHashOutput{server_root}});	
		
        my $deviceId = $deviceIdHash{$evsDeviceHashOutput{uid}->{$uniqueID}};
		my $nickName = $nickNameHash{$evsDeviceHashOutput{uid}->{$uniqueID}};
		$serverRoot  = $serverRootHash{$evsDeviceHashOutput{uid}->{$uniqueID}};
		
		$nickName =~ s/(.*)_\d+/$1/;
        $deviceId = $deviceIdPrefix.$deviceId.$deviceIdPostfix;
		my $deviceID = '';
		if (defined ($backupHost)){
				($deviceID,$backupHost) = split ('#',$backupHost);
				$deviceID = $deviceId if($deviceID ne $deviceId); 			#If difference is found in device ID between One present in Config file and the other we found under list device. 
			}

			if ($deviceID eq '' or $backupHost eq ''){
				($deviceID,$backupHost) = ($deviceId,$nickName);
			}
			my $locationQuery = qq{Your Backup Location name is "$backupHost". Do you want to edit(y/n)?};
			$choice = $userInput;
			unless (defined ($userInput)){
				print $lineFeed.$locationQuery;
				$choice = getConfirmationChoice();
			}
			
			if($choice eq 'y' or $choice eq 'Y'){
				getBucketName($backupHost);
				nickUpdate($deviceID);
			#Added to update the nick name of Restore From if it is same
			if($needToUpdateRestFrom){
				$restoreHost = $backupHost;
			}
			}
			else{
				$backupHost = "$deviceID#$backupHost";
			}
        }
	else{
		createOrLinkBucket();
	}
}
#*********************************************************************************************************
#Subroutine Name        : createOrLinkBucket
#Objective              : This function will give user option to create bucket or link to existing bucket.
#Usage                  : getBucketName();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub createOrLinkBucket{
	my $retryCount = $#_ == -1 ? 4 : $_[0];
	print $lineFeed.Constants->CONST->{'selectLocation4Backup'};
	displayMenu(['1) '.Constants->CONST->{'createBucketMess'},'2) '.Constants->CONST->{'adoptLinkMess'}]);
	print $lineFeed;
	my $userChoice = getUserMenuChoice(2,4);
	
	if ($userChoice == 1){
		getBucketName();
		createBucket();
	}elsif($userChoice == 2){
		print $lineFeed.Constants->CONST->{'ListOfDevice'}.$lineFeed;
		my @devicesToLink = displayDeviceList(\%evsDeviceHashOutput,\@columnNames);
		print $lineFeed;
		if ($retryCount <= 0){
			print Constants->CONST->{'maxRetry'}.$lineFeed;
            #traceLog($lineFeed.Constants->CONST->{'maxRetry'}.$lineFeed, __FILE__, __LINE__);
            cancelProcess();	
		}
		my $userChoice = getUserMenuChoice(scalar(@devicesToLink),$retryCount,Constants->CONST->{'selectDevice'});
		if ($userChoice ne ''){
			my $linkToData = $devicesToLink[--$userChoice];
			my ($deviceID,$deviceNickName) = ($deviceIdPrefix.$linkToData->{device_id}.$deviceIdPostfix,$linkToData->{nick_name});
			linkBucket($deviceID,$deviceNickName);
		}
    }
}
#*********************************************************************************************************
#Subroutine Name        : getBucketName
#Objective              : This function will get the bucket name(backup location) from the user.
#Usage                  : getBucketName();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getBucketName{
	my $oldBackupLocName = shift;
	my $retryCount = 4;
	while($retryCount){
		#print $lineFeed.Constants->CONST->{'AskBackupLoc'}.': ';
		#print $lineFeed.Constants->CONST->{'AskBackupLoc'}.' '.Constants->CONST->{'BackupLocNoteDedup'}.': ';
		print $lineFeed.$Locale::strings{'enter_your_backup_location_optional'}.': ';
		my $backupHostTemp = getLocationInput();
		Chomp(\$backupHostTemp);#This will trim the spaces or tab from string
		#if ($backupHostTemp =~ /^(?=.{4,64}$)^[A-Za-z0-9_\-\.\s]+$/ or $backupHostTemp eq ''){
		if ($backupHostTemp =~ /^(?=.{4,64}$)^[A-Za-z0-9_\-]+$/ or $backupHostTemp eq ''){
			if($backupHostTemp ne "") {
				$backupHost = $backupHostTemp;
			}elsif($backupHostTemp eq '' and defined($oldBackupLocName)){#if some backup loc name is already configured and user press enter key then the same should be restored.
				$backupHost = $oldBackupLocName;
			}else{
				$backupHost = `hostname`;
				chomp($backupHost);
				print Constants->CONST->{'messDefaultBackupLoc'}.qq( "$backupHost").$lineFeed;
			}
			print Constants->CONST->{'SetBackupLoc'}.$lineFeed;
			if(substr($backupHost, 0, 1) eq "/") {
				$backupHost = s/^["]?\///;
			}
			last;
		}else{
			$retryCount -= 1;
			print Constants->CONST->{'BackupLocInvalidDedup'}.qq( "$backupHostTemp". );
			if ($backupHostTemp !~ /^(?=.{4,64}$)/){
				print Constants->CONST->{'BucketLength'}.$lineFeed;
			}
			undef ($backupHostTemp);
		}
	}
	if ($retryCount == 0 and !(defined $backupHostTemp)){
		print $lineFeed.Constants->CONST->{'BackupLocRetryDedup'}.$lineFeed;
		cancelProcess();
	}
}
#*********************************************************************************************************
#Subroutine Name        : createBucket
#Objective              : This function will create bucket/backup location in the user account. Used only in case of dedup.
#Usage                  : createBucket();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub createBucket{
#	$encType = checkEncType(1) if($encType eq "");
	my $createBucketUtfFile = getOperationFile(Constants->CONST->{'CreateBucketOp'});
	chomp($createBucketUtfFile);
	$createBucketUtfFile =~ s/\'/\'\\''/g;
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$createBucketUtfFile."'".$whiteSpace.$errorRedirection;
	my $commandOutput = qx{$idevsutilCommandLine};
	unlink($createBucketUtfFile);
	#traceLog("DEBUG create bucket :: $commandOutput", __FILE__, __LINE__);
	if ($commandOutput =~ /status=["]success["]/i){
			$' =~ /device_id="(.*?)".*?server_root="(.*?)".*?nick_name="(.*?)".*/;
			my $deviceID   = $deviceIdPrefix.$1.$deviceIdPostfix;
			$backupHost = $restoreHost =  "$deviceID#$3"; # BackupLocation = "DeviceID#Nickname" Eg: "D01500371120000812023#/dedup1 Constants->CONST->{'BackupLocMsg'}.$whiteSpace."\"$2\"".$lineFeed;			
			print Constants->CONST->{'BackupLocMsg'}.$whiteSpace."\"$3\"".$lineFeed;
			$serverRoot = $2;
	} elsif($commandOutput =~ /idevs error/i){
		print $commandOutput;
		exit 1;
	}
}
#*********************************************************************************************************
#Subroutine Name        : nickUpdate
#Objective              : This function will update the nickname of device in case of dedup only.
#Usage                  : nickUpdate();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub nickUpdate {
#	$encType = checkEncType(1) if($encType eq "");
	my $deviceID = shift;
	my $nickUpdateUtfFile = getOperationFile(Constants->CONST->{'NickUpdateOp'},$deviceID);
	chomp($nickUpdateUtfFile);
	$nickUpdateUtfFile =~ s/\'/\'\\''/g;
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$nickUpdateUtfFile."'".$whiteSpace.$errorRedirection;
	my $commandOutput = qx{$idevsutilCommandLine};
	unlink($nickUpdateUtfFile);
	#traceLog("DEBUG - nickupdate :: $commandOutput", __FILE__, __LINE__);
	if ($commandOutput =~ /status=["]success["]/i){
			$' =~ /nick_name=["](.*?)["].*/;
			$backupHost = "$deviceID#$1"; # BackupLocation = "DeviceID#Nickname"
		#$restoreHost=$1; #Commented by Senthil : 07-May-2018
			print Constants->CONST->{'BackupLocMsg'}.$whiteSpace."\"$1\"".$lineFeed;
			holdScreen2displayMessage(2);
	}
	elsif($commandOutput =~ /idevs error/i){
		print $commandOutput;
		exit 1;
	}
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

#**********************************************************************************************************
# Subroutine Name         : verifyPvtKey
# Objective               : This subroutine varifies the private key by trying to create backup directory.
# Added By                : Dhritikana
#*********************************************************************************************************/
sub verifyPvtKey {
	my $dedup = shift;
	my $retType = '';
        print $lineFeed.Constants->CONST->{'verifyPvt'}.$lineFeed;
	if ($dedup eq 'off'){
        my $pvtVerifyUtfFile = getOperationFile(Constants->CONST->{'validatePvtKeyOp'});
        my $tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
        $tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;
        my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
        $tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
        my $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
        $retType = `$idevsUtilCommand`;
		unlink($pvtVerifyUtfFile);
	}else{
		$retType = getDeviceList();
	}
    
        my $count = 0;
#        while($retType !~ /verification success/) {
	while($retType =~ /encryption verification failed|Unable to proceed; private encryption key must be between 4 and 256 characters in length/){
                if($count eq 3) {
                        print Constants->CONST->{'maxRetry'}.$lineFeed;
                        traceLog($lineFeed.Constants->CONST->{'maxRetry'}.$lineFeed, __FILE__, __LINE__);
                        cancelProcess();
                }
                $count++;
                print Constants->CONST->{'AskCorrectPvt'};
                system('stty','-echo');
                $pvt = getInput();
                checkInput(\$pvt,$lineFeed);
                system('stty','echo');
                createEncodeFile($pvt, $pvtPath);
                print $lineFeed.Constants->CONST->{'verifyPvt'}.$lineFeed;
		if ($dedup eq 'off'){
                $pvtVerifyUtfFile = getOperationFile(Constants->CONST->{'validatePvtKeyOp'});
                $tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
                $tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;

                $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
                $tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;

                $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
                $retType = `$idevsUtilCommand`;

	            unlink($pvtVerifyUtfFile);
		}else{
			$retType = getDeviceList();
		}
        }
		checkAndLinkBucketSilently() if($dedup eq 'on'); #Added to update UID silently
        print Constants->CONST->{'verifiedPvt'}.$lineFeed;
}

#**********************************************************************************************************
# Subroutine Name         : createPasswordFiles
# Objective               : This subroutine creates password files such as IDPWD, IDPWD_SCH and IDENCPWD. IDENCPWD password file used for mail sending.
# Added By                : Abhishek Verma.
#*********************************************************************************************************/
sub createPasswordFiles{
	my ($pwd,$pwdPath,$userName,$enPwdPath) = @_;
	createEncodeFile($pwd, $pwdPath);
	copy($pwdPath,$pwdPath."_SCH");
	createEncodeSecondaryFile($pwd, $enPwdPath, $userName);
	chmod $filePermission, $pwdPath;
	chmod $filePermission, $enPwdPath;
	chmod $filePermission, $pwdPath.'_SCH';
}

#**************************************************************************************************************************
# Subroutine Name         : replaceXMLcharacters
# Objective               : This subroutine replaces the special characters in XML output with their actual characters  
# Added By                : Senthil Pandian
# Modified by			  : 
#**************************************************************************************************************************
sub replaceXMLcharacters
{
=comment
	$matchedXMLcount = 0;
	$fileToCheck = ${$_[0]};
	$changedName = $_[0];
	if($fileToCheck =~ s/&apos;/'/g){
		$matchedXMLcount++;
	}
	if($fileToCheck =~ s/&quot;/"/g){
		$matchedXMLcount++;
	}
	if($fileToCheck =~ s/&amp;/&/g){
		$matchedXMLcount++;
	}
	if($fileToCheck =~ s/&lt;/</g){
		$matchedXMLcount++;
	}
	if($fileToCheck =~ s/&gt;/>/g){
		$matchedXMLcount++;
	}
	${$changedName} = $fileToCheck;
	return 0;
=cut 
	my ($fileToCheck) = @_;
	${$fileToCheck} =~ s/&apos;/'/g;
	${$fileToCheck} =~ s/&quot;/"/g;
	${$fileToCheck} =~ s/&amp;/&/g;
	${$fileToCheck} =~ s/&lt;/</g;
	${$fileToCheck} =~ s/&gt;/>/g;
}

#**************************************************************************************************************************
# Subroutine Name         : checkPreReq
# Objective               : This function will check if restore/backup set file exists and filled. Otherwise it will report error and terminate the script execution.
# Added By                : Abhishek Verma.
# Modified by             :
#**************************************************************************************************************************
sub checkPreReq{
	my ($fileName,$jobType,$taskType,$reason) = @_;
	my $isEmpty = 0;
	if((!-e $fileName) or (!-s $fileName)) {
		$isEmpty = 1;
	} 
	elsif(-s $fileName > 0 && -s $fileName <= 50){
		if(!open(OUTFH, "< $fileName")) {
			traceLog($Locale::strings{'failed_to_open_file'}.":$fileName, Reason:$!");
		}		
		my $buffer = <OUTFH>;
		close OUTFH;		
		Chomp(\$buffer);
		if($buffer eq ''){
			$isEmpty = 1;
		}
		close(OUTFH);	
	}
	
	if($isEmpty){
		my $errStr = "Your $jobType"."set file \"$fileName\" is empty. ".Constants->CONST->{pleaseUpdate}.$lineFeed; # Added by Abhishek Verma.
		print $errStr if(lc($taskType) eq 'manual');
		$subjectLine = "$taskType $jobType Email Notification "."[$userName]"." [Failed $jobType]";
		$status = "FAILURE";
		sendMail($subjectLine,$reason,$fileName);
		rmtree($errorDir);
		unlink $pidPath;
		exit 1;
	}
}
#***********************************************************************************
# Subroutine Name         : checkPvtKeyCondtions
# Objective               : check if given Private Key satisfy the conditions.
# Added By                : Dhritikana
#************************************************************************************/
sub checkPvtKeyCondtions {
        if(length(${$_[0]}) >= 6 && length(${$_[0]}) <= 250) {
                return 1;
        } else {
                print $lineFeed.Constants->CONST->{'AskPvtWithCond'}.$lineFeed.$whiteSpace;
                return 0;
        }
}
#********************************************************************************************
# Subroutine Name         : configAccount
# Objective               : used to configure the user account.
# Added By                : Dhritikana
#********************************************************************************************/
sub configAccount {
	unlink($pvtPath) if(-e $pvtPath);
	my ($pvt,$pvtPath) = @_;
        print $lineFeed.Constants->CONST->{'AskConfig'}.$whiteSpace;
        $confirmationChoice = getConfirmationChoice();
        if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
                exit 0;
        }
        print Constants->CONST->{'AskDefAcc'}.$lineFeed;
        print Constants->CONST->{'AskPvtAcc'}.$lineFeed;
        getMenuChoice();
        if($menuChoice eq "2") {
                $encType = "PRIVATE";
                my $retVal = undef;
                my $countPvtInput = 0;
                while(!$retVal) {
                        if ($countPvtInput < 4){
                                print $lineFeed.Constants->CONST->{'AskPvt'}.$lineFeed;
                                system('stty','-echo');
                                ${$pvt} = getInput();
                                system('stty','echo');
                                $retVal = checkPvtKeyCondtions($pvt);
                        }else{
                                print $lineFeed.Constants->CONST->{'TryAgain'}.$lineFeed;
                                #traceLog($lineFeed.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed, __FILE__, __LINE__);
                                cancelProcess();
                        }
                        $countPvtInput++;
                }
                confirmPvtKey(${$pvt});
                createEncodeFile(${$pvt}, $pvtPath);
        } elsif($menuChoice eq "1") {
                $encType = "DEFAULT";
        }

        my $configUtf8File = getOperationFile(Constants->CONST->{'ConfigOp'}, $encType);
        chomp($configUtf8File);
        $configUtf8File =~ s/\'/\'\\''/g;

        $idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$configUtf8File."'".$whiteSpace.$errorRedirection;
        my $commandOutput = `$idevsutilCommandLine`;
        #traceLog("$lineFeed $commandOutput $lineFeed", __FILE__, __LINE__);
        unlink $configUtf8File;
}
#***********************************************************************************
# Subroutine Name         : confirmPvtKey
# Objective               : check user given Private key equality and confirm.
# Added By                : Dhritikana
#************************************************************************************/
sub confirmPvtKey {
	my $pvt = shift;
	my $count = 0;
	while($count < 4) {
		print $lineFeed.Constants->CONST->{'AskPvtAgain'}.$lineFeed;
		system('stty','-echo');
		my $pvtKeyAgin = getInput();
		system('stty','echo');
		$count++;
		if($pvt ne $pvtKeyAgin) {
			print $lineFeed.Constants->CONST->{'PvtErr'}.$lineFeed;
			#$count++;
		} else {
			print $lineFeed.Constants->CONST->{'ConfirmPvt'}.$lineFeed;
			print $lineFeed.Constants->CONST->{'setEncKeyMess'}.$lineFeed;
			last;
		}
		if($count eq 3) {
			print $lineFeed.Constants->CONST->{'TryAgain'}.$lineFeed;
            #traceLog($lineFeed.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed, __FILE__, __LINE__);
			cancelProcess();
		}
	}
}
#**********************************************************************************************************
# Subroutine Name         : setAccount
# Objective               : This subroutine set the user account if not set.
# Added By                : Dhritikana
#*********************************************************************************************************/
sub setAccount{
	my ($cnfgstat,$pvt,$pvtPath) = @_;	
        if($cnfgstat eq "NOT SET") {
                configAccount($pvt,$pvtPath);
        }
}

#*********************************************************************************************************
#Subroutine Name        : validateDir
#Objective              : This function will check if the diretory exists, its writeabel and it has some size. Returns 0 for true and 1 for false.
#Usage                  : validateDir();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub validateDir{
        (-d $_[0]) ? ((-w $_[0]) ? return 0 : return 2) : return 1;
}
#*********************************************************************************************************
#Subroutine Name        : validateCommandArgs
#Objective              : This function will validate the elements in ARGV with expected script command line input.
#			: 1st parameter : ref to @ARGV
#			: 2nd parameter : ref to @commandlineArg
#Usage                  : validateCommandArgs();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub validateCommandArgs{
	#@_ first argument(0th element) is ref to @ARGV and second input (1st element) is array ref which shows valid command line inputs to be used in scripts.
	return $match = grep {my $argV = $_; grep {/^$argV$/}@{$_[1]}}@{$_[0]};
}
#****************************************************************************
# Subroutine Name         : connectionIssueExit
# Objective               : If error matched with the mentioned error messages in @ErrorArgumentsExit. Then exit from the script after giving appropriate error message.
# Added By                : Abhishek Verma.
#****************************************************************************/
sub connectionIssueExit{
	my $errorMessage = $_[0];
        if (-f $_[0]){
                if (!open(EF,'<',$_[0])){ #EF means error file handler.
                        traceLog("Failed to open $_[0], Reason:$! $lineFeed", __FILE__, __LINE__);
                        print "Failed to open $_[0], Reason:$! $lineFeed";
                        cancelProcess();
                }
                chop($errorMessage = <EF>);
                close(EF);
        }
        if (grep {$errorMessage =~ /$_/} @ErrorArgumentsExit){
                print Constants->CONST->{'ProxyErr'}.$lineFeed;
                cancelProcess();
        }
}
#****************************************************************************************************
# Subroutine Name         : appendEndProcessInProgressFile.
# Objective               : This subroutine will append PROGRESS END string at the end of progress file.
# Modified By             : Abhishek Verma.
#*****************************************************************************************************/
sub appendEndProcessInProgressFile {
        open PROGRESS_DETAILS_FILE, ">>", $progressDetailsFilePath or return "";
	print PROGRESS_DETAILS_FILE "\nPROGRESS END";
        close PROGRESS_DETAILS_FILE;
}
#****************************************************************************************************
# Subroutine Name         : writeParamToFile.
# Objective               : This subroutine will write parameters into a file named operations.txt. Later it is used in Operations.pl script.
# Modified By             : Abhishek Verma.
#*****************************************************************************************************/
sub writeParamToFile{
	my $fileName = shift;
	if (!open(PH,'>',$fileName)){ #PH means Parameter file handler.
		traceLog("Failed to open $fileName, Reason:$! $lineFeed", __FILE__, __LINE__);
		print "Failed to open $fileName, Reason:$! $lineFeed";
		cancelProcess();
	}
	print PH @_;
	close (PH);
	chmod $filePermission,$fileName;
}
#****************************************************************************************************
# Subroutine Name         : writeParamToFile.
# Objective               : This subroutine will write parameters into a file named operations.txt. Later it is used in Operations.pl script.
# Modified By             : Abhishek Verma.
#*****************************************************************************************************/
sub convertToBytes{
	my $dataTransferedInBytes;
 	if ($_[0] =~ /(.*?)kB\/s/i){
		$dataTransferedInBytes = $1*1024;
	}elsif($_[0] =~ /(.*?)MB\/s/i){
		$dataTransferedInBytes = $1*1024*1024;
	}	
	return $dataTransferedInBytes;
}
#****************************************************************************************************
# Subroutine Name         : getCurlOutput.
# Objective               : Get response from third party API/CGI using cURL
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub getCurlOutput{
	my $PATH = $_[0];
	my $data = $_[1];
	my $curl = `which curl 2>/dev/null`;
	chomp($curl);
	
	if($proxyOn eq 1) {
		$curlCmd = "$curl --max-time 15 -x http://$proxyIp:$proxyPort --proxy-user $proxyUsername:$proxyPassword -L -s -k -d '$data' '$PATH'";
	} else {
		$curlCmd = "$curl --max-time 15 -s -k -d '$data' '$PATH'";
	}

	my $res = `$curlCmd`;
	if ($res =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
		traceLog("Failed get curl Output: $res\n", __FILE__, __LINE__);
		undef $userName;
		return 0;
	}
	return $res;
}
#***************************************************************************************
# Subroutine Name         : checkAndUpdateClientRecord
# Objective               : Check & update the client/IDrive user detail for stat.
# Added By                : Senthil Pandian
#****************************************************************************************/
sub checkAndUpdateClientRecord {
	$updated = isUserDetailUpdated();
	if($updated){
		return;
	}
	$userName = $_[0];
	$password = $_[1];
	$isUpdated = updateUserDetail($userName,$password,1);
	if($isUpdated){
		if(!open(FH, ">>", $freshInstallFile)) {
			traceLog("Not able to open $freshInstallFile, Reason:$! $lineFeed", __FILE__, __LINE__);
			return 0;
		}	
		print FH $userName."\n";
		close FH;
		chmod $filePermission, $freshInstallFile;
	}
}
#***************************************************************************************
# Subroutine Name         : isUserDetailUpdated
# Objective               : Checking whether user detail already updated or not
# Added By                : Senthil Pandian
#****************************************************************************************/
sub isUserDetailUpdated {
	$userExist = 0;
	if(-e $freshInstallFile) {		
		if(!open(FH, "<", $freshInstallFile)) {
			traceLog("Not able to open $freshInstallFile, Reason:$! $lineFeed", __FILE__, __LINE__);
			return;
		}
		@idriveUsers = <FH>;
		close FH;
		chomp(@idriveUsers);
		foreach my $user (@idriveUsers) {
			if($userName eq $user){
				$userExist =1;
				last;
			}
		}
	}
	return $userExist;
}
#***************************************************************************************
# Subroutine Name         : updateUserDetail
# Objective               : Update the client/IDrive user detail for stat.
# Added By                : Senthil Pandian
#****************************************************************************************/
sub updateUserDetail {
	my $device_name = `hostname`;
	chomp($device_name);
	
	my $os = $appType."ForLinux";
	my $encodedOS    = $os;
	
	my $currentVersion = Constants->CONST->{'ScriptBuildVersion'};
	chomp($currentVersion);
	my $uniqueID = getUniqueID();

	my $encodedUname = $_[0];
	my $encodedPwod  = $_[1];
	my $enabled 	 = $_[2];

	foreach ($encodedUname, $encodedPwod, $encodedOS) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}
	
	my $data = 'username='.$encodedUname.'&password='.$encodedPwod.'&device_name='.$device_name.'&device_id='.$uniqueID.'&enabled='.$enabled.'&os='.$encodedOS.'&version='.$currentVersion;
	#print "CGI URL:$IDriveUserInoCGI$data\n\n";
	$res 	 = getCurlOutput($IDriveUserInoCGI,$data);
	if($res =~ /Error:/){
		#print "Failed to update user detail: $res\n";
		traceLog("Failed to update user detail: $res\n", __FILE__, __LINE__) if($enabled ==1);
		return 0;
	}
	#print "CGI output:$res\n\n";
	#traceLog("CGI output:$res") if($enabled ==1);
	if($res =~ /success/i){
		return 1;
	}
	return 0;
}

#*************************************************************************************************
#Subroutine Name               : whichPackage
#Objective                     : This subroutine will give you the path of given command.
#Usage                         : whichPackage()
#Added By                      : Abhishek Verma
#*************************************************************************************************/
sub whichPackage{
	my $pckg = ${$_[0]};
	my $pckgPath = `which $pckg 2>/dev/null`;
	chomp($pckgPath);
	return $pckgPath;
}
#*************************************************************************************************
#Subroutine Name               : getZipPath
#Objective                     : This subroutine will return the full path of ZIP file.
#Added By                      : Senthil Pandian
#*************************************************************************************************/
sub getZipPath{
	my $zipPath = $_[0];	
	if($zipPath =~ /^\//){
		return $zipPath;
	}
	$currDirLocal = `pwd`;
	chomp($currDirLocal);
	$zipPath = "$currDirLocal/$zipPath";
	chomp($zipPath);
	return $zipPath;
}

#*************************************************************************************************
#Subroutine Name               : getPSoption
#Objective                     : This subroutine will return the machine based ps option.
#Added By                      : Senthil Pandian
#*************************************************************************************************/
sub getPSoption{
	$machineInfo = `uname -a`;
	chomp($machineInfo);
	if($machineInfo =~ /freebsd/i){
		$psOption = "-auxww";
		$machineInfo = 'freebsd';
	}
}

#****************************************************************************************************
# Subroutine Name         : readFromCrontab.
# Objective               : Read entire crontab file.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub readFromCrontab {
	my $crontabFilePath = "/etc/crontab";
	my $retVal = 1;
	if(-l $crontabFilePath){
		my $crontabFilePath_bak = $crontabFilePath."_bak";
		$res = system("mv $crontabFilePath $crontabFilePath_bak 2>/dev/null");
		if($res ne "0") {
			traceLog("Unable to move crontab link file");
			$retVal = 0;
		} elsif(open CRONTABFILE, ">", $crontabFilePath){
			close CRONTABFILE;
			chmod 0644, $crontabFilePath;
		} else {
			traceLog("Couldn't open file $crontabFilePath");
			$retVal = 0;
		}
	} else {
		if(open CRONTABFILE, "<", $crontabFilePath){
			@linesCrontab = <CRONTABFILE>;  
			close CRONTABFILE;
		} else {
			traceLog("Couldn't open file $crontabFilePath");
			$retVal = 0;
		}
	}
	return $retVal;
}
#****************************************************************************************************
# Subroutine Name         : createExcludedLogFile30k
# Objective               : Create exclude log file.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub createExcludedLogFile30k {
	my $excludedLogFilePath_new = $excludedLogFilePath.$excludedFileIndex;
	# require to open excludedItems file to log excluded details
	if(!open(EXCLUDEDFILE, ">", $excludedLogFilePath_new)){
		print Constants->CONST->{'CreateFail'}." $excludedLogFilePath_new, Reason:$!";
		traceLog(Constants->CONST->{'CreateFail'}." $excludedLogFilePath_new, Reason:$!", __FILE__, __LINE__) and die;
	}
	chmod $filePermission, $excludedLogFilePath_new;
	$excludedFileIndex++;
}
#****************************************************************************************************
# Subroutine Name         : appendExcludedLogFileContents
# Objective               : This subroutine appends the contents of the excluded log file to the output file
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub appendExcludedLogFileContents
{
	my $exclude_dir = $excludeDirPath."/";
	my @files_list = `ls '$exclude_dir'`;
	my $fileopen = 0;
	my $excludeLogSummary ='';
	chomp(@files_list);
	foreach my $file (@files_list) {
		chomp($file);
		if ( $file eq "." or $file eq "..") {
			next;
		}
		$file = $exclude_dir.$file;
		
		if(-s $file > 0){
			if($fileopen == 0){
				$excludeLogSummary.="$lineFeed"."_______________________________________________________________________________________";
				$excludeLogSummary.="$lineFeed$lineFeed|Excluded Files/Folders|$lineFeed";
				$excludeLogSummary.="_______________________________________________________________________________________$lineFeed$lineFeed";
			}
			$fileopen = 1;
			open EXCLUDED_FILE, "<", $file or traceLog(Constants->CONST->{'FileOpnErr'}." $file. Reason $!\n", __FILE__, __LINE__);
			while(my $line = <EXCLUDED_FILE>) { 
				$excludeLogSummary.=$line;
			}
			close EXCLUDED_FILE;
		}
	}
	if($excludeLogSummary){
		$excludeLogSummary.$lineFeed.$lineFeed;
	}
	if(-e $exclude_dir){
		rmtree($exclude_dir);
	}
	return $excludeLogSummary;
}

#****************************************************************************************************
# Subroutine Name         : checkAndLinkBucketSilently
# Objective               : This subroutine will link the bucket silently if machine's UID having '_1'
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub checkAndLinkBucketSilently
{
	my %ConfFileValues = getConfigHashValue();
	my $actualDeviceID;
	my $backupLoc = $ConfFileValues{'BACKUPLOCATION'};
	my $restoreFrom = $ConfFileValues{'RESTOREFROM'};
	my $needToUpdateRestFrom =0;	
	   $needToUpdateRestFrom =1 if($backupLoc eq $restoreFrom);
	
	my %deviceIdHash = reverse(%{$evsDeviceHashOutput{device_id}});
	my %nickNameHash = reverse(%{$evsDeviceHashOutput{nick_name}});
	
	if (defined ($backupLoc) and $backupLoc ne ''){
		#print "backupHost:$backupHost\n";
		($deviceID,$backupHost) = split ('#',$backupLoc);
		$actualDeviceID = $deviceID;
		$actualDeviceID =~ s/$deviceIdPostfix//;
		$actualDeviceID =~ s/$deviceIdPrefix//;
	}
	
	if(!defined($backupHost) or $backupHost eq '' or !defined($evsDeviceHashOutput{device_id}->{$actualDeviceID})){
		#elsif(no <your device id> or <your device id != received ids>){
		$isExistFlag = exists ($evsDeviceHashOutput{uid}->{$uniqueID});
		if(!$isExistFlag){
			#$uniqueID detech _1
			$isExistFlag = exists ($evsDeviceHashOutput{uid}->{$uniqueID."_1"});
			if($isExistFlag){
				#//function to update to valid one
				my $deviceId = $deviceIdHash{$evsDeviceHashOutput{uid}->{$uniqueID."_1"}};
				my $nickName = $nickNameHash{$evsDeviceHashOutput{uid}->{$uniqueID."_1"}};
				$nickName =~ s/(.*)_\d+/$1/;
				$deviceId = $deviceIdPrefix.$deviceId.$deviceIdPostfix;
				linkBucket($deviceId,$nickName,$needToUpdateRestFrom);
				%evsDeviceHashOutput = getDeviceList();
			}
		} else {
			#Updating CONFIGURATION_FILE if the device id/nickname not present
			my $deviceId = $deviceIdHash{$evsDeviceHashOutput{uid}->{$uniqueID}};
			my $nickName = $nickNameHash{$evsDeviceHashOutput{uid}->{$uniqueID}};
			$nickName =~ s/(.*)_\d+/$1/;
			$deviceID   = $deviceIdPrefix.$deviceId.$deviceIdPostfix;
			$backupHost = $restoreHost =  "$deviceID#$nickName";
			$configFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};
			if($needToUpdateRestFrom){
				putParameterValue(\"RESTOREFROM",\"$restoreHost",$configFilePath);
			}
			putParameterValue(\"BACKUPLOCATION",\"$backupHost",$configFilePath);
		}
	} 
	elsif(defined($evsDeviceHashOutput{device_id}->{$actualDeviceID})){
		#elsif(<your device id == received ids>){
		#//but uid of one differ from other then function call to correct UID
		if(!defined($evsDeviceHashOutput{uid}->{$uniqueID})){
			my $deviceId = $deviceIdHash{$evsDeviceHashOutput{uid}->{$uniqueID."_1"}};
			my $nickName = $nickNameHash{$evsDeviceHashOutput{uid}->{$uniqueID."_1"}};
			$nickName =~ s/(.*)_\d+/$1/;	
			$deviceId = $deviceIdPrefix.$deviceId.$deviceIdPostfix;
			linkBucket($deviceId,$nickName,$needToUpdateRestFrom);
			%evsDeviceHashOutput = getDeviceList();
		}
	}
}
1;
