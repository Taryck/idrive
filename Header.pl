#!/usr/bin/env perl

###############################################################################
#Script Name : Header.pl
###############################################################################
# use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);
use lib map{if (__FILE__ =~ /\//) {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";}}else {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {"./$_";}}} qw(Idrivelib/lib .);

use Cwd;

eval {
	require Tie::File;
	Tie::File->import();
};

eval {
	require File::Copy;
	File::Copy->import();
};

use File::Basename;
use File::Path;
use File::stat;
use IO::Handle;
#use Fcntl;
use POSIX;
use Fcntl qw(:flock SEEK_END);
use JSON;
use Scalar::Util qw(reftype looks_like_number);
# use Data::Dumper;

#use Constants 'CONST';
require Constants;
#require Strings;
use AppConfig;
use Common;

Common::loadAppPath();
Common::loadServicePath();

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
my $mcUserLocaleCmd = Common::updateLocaleCmd('whoami');
our $mcUser = `$mcUserLocaleCmd`;
chomp($mcUser);
our ($appTypeSupport,$appType) = getAppType();
our $appMaintainer = getAppMaintainer();
our @columnNames = (['S.No.','Device Name','Device ID','OS','Date & Time','IP Address'],[8,24,24,15,22,15]);
our $freshInstallFile = "$userScriptLocation/freshInstall";
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
our $failedFileName = "failedfiles.txt";
our $retryinfo = "RetryInfo.txt";
our ($curLines, $cols, $nonExistsCount, $missingCount, $noPermissionCount, $transferredFileSize, $completedFileSize) = (0) x 7;
our $psOption = "-elf";
our $machineInfo;
my $freebsdProgress = "";
my ($latestCulmn,$latestRows) = (75)x2;
getPSoption(); #Getting PS option to get process id.

#Path change required
our $pidPath = undef;
our $statusFilePath = undef;
our $idevsOutputFile = "output.txt";
our $idevsErrorFile = "error.txt";
our $logPidFile     = "LOGPID";

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
our $finalSummary = undef; #This variable content will be shown on the terminal whenever jobs get completed,accidently/abrouptly terminated.
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
our @linesStatusFile = ();
our $outputFilePath = undef;
our $errorFilePath = undef;
our $taskType = undef;
our $status = undef;
our %statusHash = (
	"COUNT_FILES_INDEX" => undef,
	"SYNC_COUNT_FILES_INDEX" => undef,
	"ERROR_COUNT_FILES" => undef,
	"FAILEDFILES_LISTIDX" => undef,
	"DENIED_COUNT_FILES" => undef,
	"MISSED_FILES_COUNT" => undef,
	"MODIFIED_FILES_COUNT" => undef,
	"TOTAL_TRANSFERRED_SIZE" => undef,
	"EXIT_FLAG" => undef,
);

our %statusFinalHash = (
	"COUNT_FILES_INDEX" => undef,
	"SYNC_COUNT_FILES_INDEX" => undef,
	"ERROR_COUNT_FILES" => undef,
	"FAILEDFILES_LISTIDX" => undef,
	"DENIED_COUNT_FILES" => undef,
	"MISSED_FILES_COUNT" => undef,
	"MODIFIED_FILES_COUNT" => undef,
	"TOTAL_TRANSFERRED_SIZE" => undef,
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

our @startTime = 0;
our @endTime = 0;

use constant false => 0;
use constant true => 1;
use constant FILE_COUNT_THREAD_STARTED => 1;
use constant FILE_COUNT_THREAD_COMPLETED => 2;

use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";

use constant FULLSUCCESS => 1;
use constant PARTIALSUCCESS => 2;
use constant ENGINE_LOCKE_FILE => "engine.lock";

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
our @ErrorArgumentsRetry = (
	#"idevs error",
	"Connection timed out",
	"io timeout",
	"Operation timed out",
	"nodename nor servname provided, or not known",
	"failed to connect",
	"Connection reset",
	"connection unexpectedly closed",
	"failed to get the host name",
);

our @ErrorListForMinimalRetry = (
	'Connection refused',
	'failed verification -- update retained',
	'unauthorized user',
	'user information not found',
	'Name or service not known',
);

# Errors encountered during backup operation for which the script should not retry the backup operation
our @ErrorArgumentsExit = (
	"encryption verification failed",
	"some files could not be transferred due to quota over limit",
	"skipped-over limit",
	"quota over limit",
	"account is under maintenance",
	"account has been cancelled",
	"account has been expired",
	"account has been blocked",
	"PROTOCOL VERSION MISMATCH",
	"password mismatch",
	"out of memory",
	"failed to get the device information",
	"Proxy Authentication Required",
	"No route to host",
	#"Connection refused",
	#"failed to connect",
	"Invalid device id",
	"not enough free space on device",
	"Unable to proceed as device is deleted/removed",
    "invalid source path for operation",
);

our @ErrorArgumentsNoRetry = (
	"Permission denied",
	"Directory not empty",
	"No such file or directory"
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
our $usrProfilePath = ($idriveServicePath)?"$idriveServicePath/user_profile/$mcUser":"";
our $cacheDir = ($idriveServicePath)?"$idriveServicePath/cache":"";
#our $userTxt  = ($cacheDir)?"$cacheDir/idriveuser.txt":"";
#our $idriveUserTxt  = ($cacheDir)?"$cacheDir/idriveuser.txt":"";
our $userTxt  = ($cacheDir)?"$idriveServicePath/$AppConfig::cachedIdriveFile":"";
our $idriveUserTxt  = ($cacheDir)?"$idriveServicePath/$AppConfig::cachedIdriveFile":"";

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

our $faqURL			   = "https://www.idrive.com/faq_linux";
	$faqURL			   = "https://www.ibackup.com/backup-faq/faqqrsync.htm" if ($appType eq 'IBackup');
#*******************************************************************************************************/

if((${ARGV[0]} eq "SCHEDULED") || (${ARGV[0]} eq "immediate") || (${ARGV[0]} eq "dashboard") || (${ARGV[0]} eq "CDP")) {
	$userName = $ARGV[1] if($ARGV[1] ne "");
}
else{
	$userName = getCurrentUser();
	Common::loadUsername() if(!defined($userName) || $userName eq '');
}

Common::setUsername($userName) if(defined($userName) && $userName ne '');
Common::loadUserConfiguration();

# flag for CDP job
our $iscdp	= (${ARGV[0]} && ${ARGV[0]} eq 'CDP')? 1 : 0;

our $defRestoreLocation = qq($usrProfilePath/$userName/Restore_Data);
#********************************************************************************************************
# Subroutine Name         : loadUserData.
# Objective               : loading Path and creating files/folders based on username.
# Added By                : Dhritikana
# Modified By			  : Sabin Cheruvattil, Senthil Pandian
#********************************************************************************************************/
sub loadUserData {
    return if($usrProfilePath eq '' or $userName eq '');

	$usrProfileDir = "$usrProfilePath/$userName";
	if($proxyStr eq ""){
		$proxyStr = getProxy();
		if ($proxyStr =~ /(.*?):(.*)\@(.*?):(.*?)$/){
			($proxyUsername,$proxyPassword,$proxyIp,$proxyPort) = ($1,$2,$3,$4);
		}
	}
	our $backupType = Common::getUserConfiguration('BACKUPTYPE');
	$dedup = Common::getUserConfiguration('DEDUP') if(Common::getUserConfiguration('DEDUP') ne '');
	our $backupHost = Common::getUserConfiguration('BACKUPLOCATION');
	$backupHost = checkLocationInput($backupHost);
	if($backupHost ne "" && substr($backupHost, 0, 1) ne "/") {
		$backupHost = ($dedup eq 'off') ? "/".$backupHost : $backupHost;
	}
	$backupHost =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root
	our $restoreHost = Common::getUserConfiguration('RESTOREFROM');
	$restoreHost = checkLocationInput($restoreHost);
	if ($dedup eq 'on'){
		($restoreDeviceID,$restoreHost) = split ('#',$restoreHost);
		($backupDeviceID,$backupHost)  = split ('#',$backupHost);
    }
	if($restoreHost ne "" && substr($restoreHost, 0, 1) ne "/") {
		$restoreHost = ($dedup eq 'off') ? "/".$restoreHost : $restoreHost;
	}
	our $configEmailAddress = Common::getUserConfiguration('EMAILADDRESS');
	our $bwThrottle = getThrottleVal();
	our $restoreLocation = Common::getUserConfiguration('RESTORELOCATION');
	$restoreLocation = checkLocationInput($restoreLocation);
	$restoreLocation .= '/' if(substr($restoreLocation, -1, 1) ne '/');
	#$restoreLocation =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root
	#our $ifRetainLogs = Common::getUserConfiguration('RETAINLOGS');
	our $backupPathType = Common::getUserConfiguration('BACKUPTYPE');
	our $serverRoot = Common::getUserConfiguration('SERVERROOT');
	our $totalEngineBackup = $AppConfig::maxEngineCount;
	$totalEngineBackup = $AppConfig::minEngineCount if(Common::getUserConfiguration('ENGINECOUNT') eq $AppConfig::minEngineCount);

	our $percentToNotifyForFailedFiles = (Common::getUserConfiguration('NFB') ne '')? Common::getUserConfiguration('NFB'):5;
	our $percentToNotifyForMissedFiles = (Common::getUserConfiguration('NMB') ne '')? Common::getUserConfiguration('NMB'):5;

    our $isIgnorePermissionErrors = (Common::getUserConfiguration('IFPE') ne '')? Common::getUserConfiguration('IFPE'):0;
	#our $currentDirforCmd = quotemeta($currentDir); # not used
	our $pwdPath = "$usrProfileDir/.userInfo/".Constants->CONST->{'IDPWD'};
	our $enPwdPath = "$usrProfileDir/.userInfo/".Constants->CONST->{'IDENPWD'};
	our $pvtPath = "$usrProfileDir/.userInfo/".Constants->CONST->{'IDPVT'};
	our $utf8File = "$usrProfileDir/.utf8File.txt";
	our $serverfile = "$usrProfileDir/.userInfo/".Constants->CONST->{'serverAddress'};
	our $bwPath = "$usrProfileDir/bw.txt";
	our $backupsetFilePath = "$usrProfileDir/Backup/DefaultBackupSet/BackupsetFile.enc";
	our $RestoresetFile = "$usrProfileDir/Restore/DefaultRestoreSet/RestoresetFile.txt";
	#our $backupsetSchFilePath = "$usrProfileDir/Backup/DefaultBackupSet/BackupsetFile.txt";
	#our $RestoresetSchFile = "$usrProfileDir/Restore/Scheduled/RestoresetFile.txt";
	our $localBackupsetFilePath = "$usrProfileDir/LocalBackup/LocalBackupSet/BackupsetFile.enc";
	our $validateRestoreFromFile = "$usrProfileDir/validateRestoreFromFile.txt";
	chmod $filePermission, $usrProfilePath;

	if( -e $serverfile) {
		open FILE, "<", $serverfile or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $serverfile . " , Reason:$!") and die);
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
sub addtionalErrorInfo {
	my $TmpErrorFilePath = ${$_[0]};
	chmod $filePermission, $TmpErrorFilePath;
	Common::traceLog("${$_[1]}");
	if(!open(FHERR, ">>",$TmpErrorFilePath)){
		Common::traceLog("Could not open file TmpErrorFilePath in additionalErrorInfo: $TmpErrorFilePath, Reason:$!");
		return;
	}
	print FHERR "${$_[1]}\n";
	close FHERR;
}

#****************************************************************************************************
# Subroutine Name         : getCurrentUser.
# Objective               : Get previous logged in username from user.txt.
# Added By                : Dhritikana.
# Modified By             : Sabin Cheruvattil
#*****************************************************************************************************/
sub getCurrentUser {
	return '' if(!-e $userTxt or !-f _);

	unless(open USERFILE, "<", $userTxt) {
		Common::traceLog("Unable to open $userTxt");
		return '';
	}

	my $userdata 	= <USERFILE>;
	close USERFILE;
	Chomp(\$userdata);
	my %datahash 	= ();
	my $prevuser 	= '';
	if($userdata ne '') {
		%datahash 	= ($userdata =~ m/^\{/)? %{JSON::from_json($userdata)} : {$mcUser => $userdata};
		$prevuser 	= $datahash{$mcUser}{"userid"} if ($datahash{$mcUser}{'isLoggedin'});
	}

	my $pwdPath		= "$usrProfilePath/$prevuser/.userInfo/" . Constants->CONST->{'IDPWD'};
	return $prevuser if(-e $pwdPath);
	return '';
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
		Common::traceLog(Constants->CONST->{'InvLocInput'} . $whiteSpace . ${$_[0]});
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
	my $isScheduledJob = $_[0];
	my $encKeyType = $defaultEncryptionKey;
	if(-e $pvtPath && (-s $pvtPath > 0)) {
        	$encKeyType = $privateEncryptionKey;
 	}
=comment
	if(!$isScheduledJob) {
		if(-e $pvtPath && (-s $pvtPath > 0)) {
			$encKeyType = $privateEncryptionKey;
		}
	}
	elsif($isScheduledJob eq 1) {
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
	my $bwVal = Common::getUserConfiguration('BWTHROTTLE');
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

	open FILE, "<", $serverfile or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $serverfile . " , Reason:$!") and die);
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
# Subroutine	: createUpdateBWFile.
# Objective		: Create or update bandwidth throttle value file(.bw.txt).
# Added By		: Avinash Kumar.
# Modified By	: Dhritikana, Sabin Cheruvattil
#*****************************************************************************************************/
sub createUpdateBWFile {
	open BWFH, ">", $bwPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $bwPath . " , Reason:$!") and die);
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
	$appType = $AppConfig::appType;
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
# Subroutine	: createPwdFile.
# Objective		: Create password or private encrypted file.
# Added By		: Avinash Kumar
# Modified By	: Sabin Cheruvattil
#*****************************************************************************************************/
sub createEncodeFile {
	my $data = $_[0];
	my $path = $_[1];
	my $utfFile = "";
	$utfFile = getUtf8File($data, $path);
	chomp($utfFile);

	$idevsutilCommandLine = "'$idevsutilBinaryPath'".
	$whiteSpace.$hashEvsParameters{UTF8CMD}.$assignmentOperator."'".$utfFile."'".$whiteSpace.$errorRedirection;

	$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
	my $commandOutput = `$idevsutilCommandLine`;
	if ($commandOutput =~ /idevsutil: not found/){
		print "\nPlease reconfigure your account using account_setting.pl script or add this functionality to login \n";
		exit 0;
	}
	Common::traceLog(Constants->CONST->{'CrtEncFile'} . $whiteSpace . $commandOutput);
	chmod $filePermission,$path;
	unlink $utfFile;
}

#****************************************************************
# Subroutine	: createEncodeSecondaryFile
# Objective		: Create Secondary Encoded password
# Added By		: Dhritikana
# Modified By	: Sabin Cheruvattil
#****************************************************************
sub createEncodeSecondaryFile {
	my $pdata = $_[0];
	my $path = $_[1];
	my $udata = $_[2];

	my $len = length($udata);
	my $pwd = pack( "u", "$pdata"); chomp($pwd);
	$pwd = $len."_".$pwd;

	open FILE, ">", "$enPwdPath" or (Common::traceLog(Constants->CONST->{'FileCrtErr'} . $enPwdPath . "failed reason: $!") and die);
	chmod $filePermission, $enPwdPath;
	print FILE $pwd;
	close(FILE);
}

#***********************************************************************
# Subroutine	: getPdata
# Objective		: Get Pdata in order to send Mail notification
# Added By		: Dhritikana
# Modified By	: Sabin Cheruvattil
#***********************************************************************
sub getPdata {
	my $udata = $_[0];
	my $pdata = '';
	chmod $filePermission, $enPwdPath;
	if(!open FILE, "<", "$enPwdPath"){
		Common::traceLog(Constants->CONST->{'FileOpnErr'} . $enPwdPath . " failed reason:$!");
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
# Subroutine	: getUtf8File.
# Objective		: Create utf8 file.
# Added By		: Avinash Kumar.
# Modified By	: Sabin Cheruvattil
#*****************************************************************************************************/
sub getUtf8File {
	my ($getVal, $encPath) = @_;
	my $usrProfileDir = defined ($usrProfileDir) ? $usrProfileDir : $usrProfilePath	;
	if (!-e $usrProfileDir){
		my $usrProfileDirCmd = Common::updateLocaleCmd("mkdir -p '$usrProfileDir'");
		my $res = `$usrProfileDirCmd`;
	}
	#create utf8 file.
 	open FILE, ">", "$usrProfileDir/utf8.txt" or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . "utf8.txt. failed reason:$!") and die);
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
# Modified By			: Dhritikana, Sabin Cheruvattil, Yogesh Kumar
#*****************************************************************************************************/
sub getServerAddr {
	my (%evsServerHashOutput, $commandOutput, $addrMessage, $desc);
	if ($_[0]){
		open FILE, ">", $serverfile or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . "$serverfile for getServerAddress, Reason:$!") and die);
                print FILE $_[0];
                close FILE;
                chmod $filePermission, $serverfile;
		return 1;
	}
	my $res = Common::makeRequest(12);
	if(defined($res->{DATA})) {
		%evsServerHashOutput = parseXMLOutput(\$res->{DATA});
		my $hashref = (keys(%evsServerHashOutput))[0];
		my %servdata = ();
		eval {
			%servdata	= %{JSON::from_json($hashref)};
			1;
		} or do {
			%servdata	= ();
		};

		if(exists($servdata{'server'}) and exists($servdata{'server'}{'cmdUtilityServerIP'}) and $servdata{'server'}{'cmdUtilityServerIP'}) {
			$serverAddress = $servdata{'server'}{'cmdUtilityServerIP'};
		}
		# $addrMessage   = $evsServerHashOutput{'message'};
		#$serverAddress = $evsServerHashOutput{'cmdUtilityServerIP'};
		# $serverAddress = $evsServerHashOutput{'evssrvrip'};
		# $desc = $evsServerHashOutput{'desc'};	
	} else {
		return 0;
	}
	

	if($addrMessage =~ /ERROR/) {
		if($desc ne ''){
			print $lineFeed.$desc.$lineFeed.$whiteSpace;
			Common::checkAndUpdateAccStatError(Common::getUsername(), $desc);
		}
		if($mkDirFlag) {
			rmtree($usrProfileDir);
			unlink $pwdPath;
			unlink $enPwdPath;
		}
		return 0;
	}
	if(0 < length($serverAddress)) {
		open FILE, ">", $serverfile or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . "$serverfile for getServerAddress, Reason:$!") and die);
		print FILE $serverAddress;
		close FILE;
		chmod $filePermission, $serverfile;
	}
	else {
		Common::traceLog(Constants->CONST->{'GetSrvAdrErr'});
		return 0;
	}
	return 1;
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
# Modified By             : Sabin Cheruvattil
#********************************************************************************************************************
sub putParameterValue {
	Common::setUserConfiguration($_[0], $_[1]);
	Common::saveUserConfiguration();

	return 0;
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
	my $operationEngineId = $_[0];
	if(! -s $statusFilePath."_".$operationEngineId ) {
		return;
	}else{
		chmod $filePermission, $statusFilePath."_".$operationEngineId;

		if(open(STATUS_FILE, "< $statusFilePath"."_".$operationEngineId)) {
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
# Subroutine		: readFinalStatus
# Objective			: reads the overall status file based on engine
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub readFinalStatus {
	%statusFinalHash = ();
	for($i = 1; $i <= $totalEngineBackup; $i++) {
		if(-e $statusFilePath."_$i" and -f _ and -s _) {
			readStatusFile($i);
			$statusFinalHash{'FILES_COUNT_INDEX'}			+= $statusHash{'FILES_COUNT_INDEX'};
			$statusFinalHash{'SYNC_COUNT_FILES_INDEX'}		+= $statusHash{'SYNC_COUNT_FILES_INDEX'};
			# $statusFinalHash{'FAILED_COUNT_FILES_INDEX'}	+= $statusHash{'FAILED_COUNT_FILES_INDEX'};
			$statusFinalHash{'FAILEDFILES_LISTIDX'}			+= $statusHash{'FAILEDFILES_LISTIDX'};
			$statusFinalHash{'ERROR_COUNT_FILES'}			+= $statusHash{'ERROR_COUNT_FILES'};
			$statusFinalHash{'DENIED_COUNT_FILES'}			+= $statusHash{'DENIED_COUNT_FILES'};
			$statusFinalHash{'MISSED_FILES_COUNT'}			+= $statusHash{'MISSED_FILES_COUNT'};
			$statusFinalHash{'MODIFIED_FILES_COUNT'}		+= $statusHash{'MODIFIED_FILES_COUNT'};
			$statusFinalHash{'TOTAL_TRANSFERRED_SIZE'}		+= $statusHash{'TOTAL_TRANSFERRED_SIZE'};
			$statusFinalHash{'COUNT_FILES_INDEX'}			+= $statusHash{'COUNT_FILES_INDEX'};

			if(!$statusFinalHash{'EXIT_FLAG_INDEX'} or !defined $statusHash{'EXIT_FLAG_INDEX'}) {
				$statusFinalHash{'EXIT_FLAG_INDEX'}			= $statusHash{'EXIT_FLAG_INDEX'};
			}
		}
	}

	#return $statusFinalHash;
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
	readStatusFile($_[0]);
	if(reftype(\$_[1]) eq 'REF') {
		my @statusFinalHashData = ();
		foreach(@{$_[1]}) {
			if(defined $statusHash{$_}){
				push (@statusFinalHashData, $statusHash{$_});
			} else {
				push (@statusFinalHashData, 0);
			}
		}			
		return (@statusFinalHashData);
	}

	return defined($statusHash{$_[1]})?$statusHash{$_[1]}:0;
}

#****************************************************************************************************
# Subroutine Name         : getParameterValueFromStatusFileFinal.
# Objective               : Fetches the value of individual parameters which are specified in the
#                           Account Settings file.
# Added By                : Arnab Gupta.
# Modified By			  : Deepak Chaurasia, Dhritikana
#*****************************************************************************************************/
sub getParameterValueFromStatusFileFinal
{
	undef @linesStatusFile;
	my @statusFinalHashData;
	my @inputData = @_;

	readFinalStatus();
	foreach(@inputData) {
		if(defined $statusFinalHash{$_}){
			push (@statusFinalHashData, $statusFinalHash{$_});
		} else {
			push (@statusFinalHashData, 0);
		}
	}
	return (@statusFinalHashData);
}


#****************************************************************************************************
# Subroutine	: putParameterValueInStatusFile.
# Objective		: Changes the content of STATUS FILE as per values passed
# Added By		: Dhritikana
# Modified By	: Sabin Cheruvattil
#*****************************************************************************************************/
sub putParameterValueInStatusFile
{
	($operationEngineId) = @_;
	open STAT_FILE, ">", $statusFilePath."_".$operationEngineId or (Common::traceLog(Constants->CONST->{'StatMissingErr'} . " reason :$!") and die);
	foreach my $keys(keys %statusHash) {
		print STAT_FILE "$keys = $statusHash{$keys}\n";
	}
	close STAT_FILE;
	chmod $filePermission, $statusFilePath."_".$operationEngineId;
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
	$bwPath = "$jobRunningDir/bw.txt";
	my $serverAddressOperator = "@";
	my $serverName = "home";
	my $serverNameOperator = "::";
	my $operationType = $_[0];
	my $encType = checkEncType();
	Common::loadServerAddress();
	my $serverAddress = Common::getServerAddress();
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
                open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath." for validate, Reason:$!") and die);
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
		open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for validate, Reason:$!") and die);
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
		open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for validate, Reason:$!") and die);
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
		open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for validate, Reason:$!") and die);
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

			open UTF8FILE, ">", $utfPath ;
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
                open UTF8FILE, ">", $utfPath ;
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
                open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for config, Reason:$!") and die);
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
			    open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for createDir, Reason:$!") and die);
                $utfFile = $hashEvsParameters{PASSWORD}.$assignmentOperator.$pwdPath.$lineFeed;
#                if($_[1] eq "PRIVATE"){
			if ($encType eq "PRIVATE") {
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
		my $operationEngineId = $_[4];
		my $encryptionType = $encType;
		if($dedup eq 'on'){
			$relativeAsPerOperation = RELATIVE;
		}
		$backupLocation .= $pathSeparator if($backupLocation and substr($backupLocation,-1,1) ne $pathSeparator); #Adding '/' at end if not

		$utfPath = $utfPath."_".$operationEngineId;
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
					$hashEvsParameters{TEMP}.$assignmentOperator.$jobRunningDir."/".$lineFeed.
					$hashEvsParameters{OUTPUT}.$assignmentOperator.$idevsOutputFile."_".$operationEngineId.$lineFeed.
					$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile."_".$operationEngineId.$lineFeed.
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
		my $operationEngineId = $_[4];
		my $encryptionType  = $encType;
		my $restoreLocation = Common::getUserConfiguration('RESTORELOCATION');

		$source           .= $pathSeparator if(substr($source,-1,1) ne $pathSeparator); #Adding '/' at end if its not
		$restoreLocation  .= $pathSeparator if(substr($restoreLocation,-1,1) ne $pathSeparator); #Adding '/' at end if its not

	   $utfPath = $utfPath."_".$operationEngineId;
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
					$hashEvsParameters{TEMP}.$assignmentOperator.$jobRunningDir."/".$lineFeed.
					$hashEvsParameters{OUTPUT}.$assignmentOperator.$idevsOutputFile."_".$operationEngineId.$lineFeed.
					$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile."_".$operationEngineId.$lineFeed.
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
		my $operationEngineId = $_[4];
		$utfPath = $utfPath."_".$operationEngineId;

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
					$hashEvsParameters{TEMP}.$assignmentOperator.$jobRunningDir."/".$lineFeed.
					$hashEvsParameters{OUTPUT}.$assignmentOperator.$idevsOutputFile."_".$operationEngineId.$lineFeed.
					$hashEvsParameters{ERROR}.$assignmentOperator.$idevsErrorFile."_".$operationEngineId.$lineFeed.
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
		open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for properties, Reason:$!") and die);
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
			open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for properties, Reason:$!") and die);
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
			open UTF8FILE, ">", $utfPath or (Common::traceLog(Constants->CONST->{'FileOpnErr'} . $utfPath . " for properties, Reason:$!") and die);
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
			open UTF8FILE, ">", $utfPath or (Common::traceLog("Could not open file $utfPath for auth list, Reason:$!") and die);
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
		#$hashEvsParameters{TEMP}.$assignmentOperator.$evsTempDir.$lineFeed.
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
		Common::traceLog(Constants->CONST->{'InvalidOp'} . "-> $operationType");
		return;
	}

	print UTF8FILE $utfFile;
	close UTF8FILE;
	chmod $filePermission, $utfPath;
	return $utfPath;
}

#****************************************************************************************************
# Subroutine Name         : parseXMLOutput.
# Objective               : Parse evs command output and load the elements and values to an hash.
# Added By                : Dhritikana.
# Modified By 		      : Abhishek Verma - 7/7/2017 - Now this subroutine can parse multiple tags of xml. Previously it was restricted to one level.
#						  : Senthil Pandian
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
				# @evsArrLine = grep {/\w+/} grep {/bucket_type=\"D\"/} split(/(?:\<item|\<login|<tree)/g, $evsOutput);
				@evsArrLine = grep {/\w+/} split(/(?:\<item|\<login|<tree)/g, $evsOutput);
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
				#&Chomp(\$value); #Commented by Senthil for Harish_2.17_6_12 on 09-Aug-2018
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
# Modified By			  : Senthil Pandian
#*****************************************************************************************************/
sub getProxy
{
	my $proxy = Common::getProxyDetails('PROXY');
	my($proxyIP) = $proxy =~ /@(.*)\:/;
	if($proxyIP ne ""){
		$proxyOn = 1;
		my ($uNPword, $ipPort) = split(/\@/, $proxy);
		my @UnP = split(/\:/, $uNPword);
		if (scalar(@UnP) >1 and $UnP[0] ne "") {
			$UnP[1] = ($UnP[1] ne '')?Common::decryptString($UnP[1]):$UnP[1];
			foreach ($UnP[0], $UnP[1]) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$uNPword = join ":", @UnP;
			$proxy = "$uNPword\@$ipPort";
		}
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
				Common::traceLog(Constants->CONST->{'SendMailErr'} . Constants->CONST->{'InvalidEmail'} . " $addr");
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
			Common::traceLog(Constants->CONST->{'SendMailErr'} . Constants->CONST->{'EmlIdMissing'});
			return "NULL";
		}
	}
}

#*******************************************************************************************************************
# Subroutine Name         : sendMail
# Objective               : sends a mail to the user in case of successful/canceled/ failed scheduled backup/restore.
# Added By                : Dhritikana
# Modified By             : Yogesh Kumar
#********************************************************************************************************************
sub sendMail
{
	if ($taskType eq "Manual") {
		return;
	}
	my $jobName = '';
	if ($jobType eq "backup") {
		$jobName = "default_backupset";
	} elsif($jobType eq "Local Backup") {
		$jobName = "local_backupset";
	} else {
		$jobName = "default_backupset";
	}

	my @responseData = &Common::checkEmailNotify($jobType, $jobName );
	my $notifyEmailStatus = $responseData[0];
	if($notifyEmailStatus eq "DISABLED") {
			return;
	}
	$configEmailAddress = $responseData[1] if (defined $responseData[1]);
	my $jobStatus = (split '\_', $outputFilePath)[-2];

	if ($notifyEmailStatus eq 'notify_failure'){
		return if((index($jobStatus, 'Success') != -1) or (index($jobStatus, 'Success*') != -1));
	}
	my $finalAddrList = getFinalMailAddrList($configEmailAddress);

	if($finalAddrList eq "NULL") {
		return;
	}

	my $pData = &getPdata("$userName");
	if($pData eq ''){
		Common::traceLog(Constants->CONST->{'SendMailErr'} . Constants->CONST->{'passwordMissing'});
		return;
	}

	my $sender = "support\@".$appTypeSupport.".com";
	my $content = "";
	my $subjectLine = $_[0];
	my $operationData = $_[1];
	my $backupRestoreFileLink = $_[2];

	$content  = "Dear $appType User, \n\n";
	$content .= "Ref : Username - $userName \n\n";

	if ($operationData eq 'NOBACKUPDATA'){
		$content .= qq{\t Unable to perform backup operation. Your backupset is empty. To do backup again please fill your backupset.};
	} elsif($operationData eq 'NORESTOREDATA') {
		$content .= qq{\t Unable to perform restore operation. Your restoreset is empty. To do restore again please fill your restoreset.};
	} else {
		$content .= $mail_content_head;
		$content .= $mail_content;
	}

	$content .= "\n\nRegards, \n";
	$content .= "$appType Support.\n";
	$content .= "Version: " . Constants->CONST->{'ScriptBuildVersion'} . "\n";
	$content .= "Release date: " . Constants->CONST->{'ScriptReleaseDate'};

	# URL DATA ENCODING#
	Common::makeRequest(6, [
		$finalAddrList,
		$subjectLine,
		$content
	]);
}

#*****************************************************************************************************
# Subroutine Name         : formSendMailCurlcmd
# Objective               : forms curl command to send mail based on proxy settings
# Added By                : Dhritikana
#*****************************************************************************************************
sub formSendMailCurlcmd {
	my $curlPathCmd = Common::updateLocaleCmd('which curl');
	#Assigning curl path
	my $curlPath = `$curlPathCmd`;
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
# Added By                : Abhishek
# Modified By			  : Senthil Pandian
#******************************************************************************
sub terminateStatusRetrievalScript
{
	my $statusScriptName = Constants->FILE_NAMES->{statusRetrivalScript};
	my $statusScriptCmd = "ps $psOption | grep $statusScriptName | grep -v grep";

	$statusScriptCmd = Common::updateLocaleCmd($statusScriptCmd);
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
	my $idevsErrorFileEngineBased = $idevsErrorFile."_".$_[1];
	if(!-s $idevsErrorFileEngineBased){
		return;
	}

	#open the error file for read and if open fails then return
	if (! open(TEMP_ERRORFILE, "< $idevsErrorFileEngineBased")) {
		Common::traceLog("Could not open file $idevsErrorFileEngineBased, Reason:$!");
		return;
	}

	#read error file content
	my @tempErrorFileContents = ();
	@tempErrorFileContents = <TEMP_ERRORFILE>;
	close TEMP_ERRORFILE;

	my $file = $_[0];

	#open the App error file and if failed to open then return
	if (! open(ERRORFILE, ">> $file")) {
		Common::traceLog("Could not open file 'file' in copyTempErrorFile: $file, Reason:$!");
		return;
	}

	#write the content of error file in App error file
	#$errorStr = join('\n', @tempErrorFileContents);
	print ERRORFILE @tempErrorFileContents;
	close ERRORFILE;
	chmod $filePermission, $file;
}

#****************************************************************************************************
# Subroutine Name         : appendErrorFileContents
# Objective               : This subroutine appends the contents of the error file to the output file
#							and deletes the error file.
# Modified By             : Deepak Chaurasia, Senthil Pandian
#*****************************************************************************************************/
sub appendErrorFileContents
{
	my $error_dir = $_[0]."/";

	my $filesListCmd = Common::updateLocaleCmd("ls '$error_dir'");
	my @files_list = `$filesListCmd`;
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
				$summaryError.= "[ERROR REPORT]".$lineFeed;
                $summaryError.= (('-') x 14).$lineFeed;
			}
			$fileopen = 1;
			open ERROR_FILE, "<", $file or Common::traceLog(Constants->CONST->{'FileOpnErr'} . " $file. Reason $!");
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

#****************************************************************************************************
# Subroutine Name	: checkAndUpdatePermissionDeniedList
# Objective			: This subroutine appends the contents of the permission denied list file to the output file
#					  and deletes file.
# Modified By		: Senthil Pandian
#*****************************************************************************************************/
sub checkAndUpdatePermissionDeniedList
{
	my $permissionError = $_[0];
	my $summaryError	= '';
	if(-e $permissionError && !-z $permissionError){
		$summaryError.=$lineFeed."[INFORMATION]".$lineFeed;
		$summaryError.=(('-') x 13).$lineFeed;
		open DENIED_FILE, "<", $permissionError or Common::traceLog(Constants->CONST->{'FileOpnErr'} . " $permissionError. Reason $!");
		my $byteRead = read(DENIED_FILE, $buffer, $AppConfig::maxLogSize);
		$buffer =~ s/(\] \[FAILED\] \[)/\] \[INFORMATION\] \[/g; #Replacing "FAILED" with "INFORMATION"
		$summaryError.= $buffer;
		close DENIED_FILE;
	}
	unlink($permissionError);
	return $summaryError;
}

#****************************************************************************************************
# Subroutine Name	: getPermissionDeniedCount
# Objective			: This subroutine will return the count of permission denied error given by EVS.
# Modified By		: Senthil Pandian
#*****************************************************************************************************/
sub getPermissionDeniedCount
{
	my $deniedCount	  	= 0;
	my $infoFile 		= "$jobRunningDir/info_file";

	if(-e $infoFile && !-z $infoFile){
		my $deniedCountCheckCmd = "cat '$infoFile' | grep \"^DENIEDCOUNT\"";
		$deniedCountCheckCmd = Common::updateLocaleCmd($deniedCountCheckCmd);
		$deniedCount = `$deniedCountCheckCmd`;
		$deniedCount =~ s/DENIEDCOUNT//;
		Chomp(\$deniedCount);
	}
	return $deniedCount;
}

#****************************************************************************************************
# Subroutine		: getReadySyncCount
# Objective			: Returns already synced count
# Added By			: Sabin Cheruvattil
#****************************************************************************************************
sub getReadySyncCount {
	my $synccount	= 0;
	my $info		= "$jobRunningDir/info_file";

	if(-e $info && !-z _) {
		my $synccmd = "cat '$info' | grep \"^READYSYNC\"";
		$synccount = `$synccmd`;
		$synccount =~ s/READYSYNC//;
		Chomp(\$synccount);
	}

	return $synccount;
}

#*************************************************************************************************
# Subroutine		: createLogFiles
# Objective			: Creates the Log Directory if not present, Creates the Error Log and
#						Output Log files based on the timestamp when the backup/restore
#						operation was started, Clears the content of the Progress Details file
# Added By			: Abhishek Verma
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************
sub createLogFiles {
	my $jobType = $_[0];
	our $progressDetailsFileName = "PROGRESS_DETAILS";
	our $outputFileName = $jobType;
	# our $errorFileName = $jobType."_ERRORFILE";
	my $logDir = "$jobRunningDir/LOGS";
	$errorDir = "$jobRunningDir/ERROR";
	my $logPidFilePath = $jobRunningDir.$pathSeparator.$logPidFile;

	if(!-d $logDir) {
		mkdir $logDir;
		chmod $filePermission, $logDir;
	}

	my $currentTime = time; #This function will give the current epoch time.

	#previous log file name use to be like 'BACKUP Wed May 17 12:34:47 2017_FAILURE'.Now log name will be '1495007954_SUCCESS'.
	if($iscdp) {
		$outputFilePath	= Common::getCDPLogName($logDir);
		$outputFilePath = Common::renameCDPLogAsRunning($outputFilePath) if(-f $outputFilePath);
	} else {
		$outputFilePath = $logDir.$pathSeparator.$currentTime."_Running_".$taskType;
	}

	#$errorFilePath = $errorDir.$pathSeparator.$errorFileName;
	$errorFilePath = $jobRunningDir."/exitError.txt";
	#Keeping current log file name in logpid file
	open(my $handle, '>', $logPidFilePath) or Common::traceLog("Could not open file '$logPidFilePath' $!");
	print $handle $outputFilePath;
	close $handle;
	chmod $filePermission, $logPidFilePath;
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
# Subroutine	: displayProgressBar.
# Objective		: Display the filename and the progress bar in the terminal window
# Added By		:
# Modified By	: Sabin Cheruvattil
#*****************************************************************************************************/
sub displayProgressBar {
	# it may be time consuming | check and retain
	Common::loadUserConfiguration();
	$bwThrottle = getThrottleVal();
	my $retryCount = 0;
RETRY:
	my($progressDataHashRef,$progressDataFileDisplayHashRef,$individualProgressDataRef) = calculateProgress($_[0],$_[2]);
	my @progressDataHash = @$progressDataHashRef;
    my @progressDataFileDisplayHash = @$progressDataFileDisplayHashRef;
    my @individualProgressDataHash = @$individualProgressDataRef;
	if(scalar(@progressDataFileDisplayHash) == 0) {
		unless($retryCount) {
			$retryCount++;
			goto RETRY;
		}
		return "";
	}

	# $SIG{WINCH} = \&changeSizeVal;
	my ($progress, $cellSize, $totalSizeUnit, $emptySpace, $emptyLine, $moreProgress) = ('') x 6;
	my ($remainingFile, $remainingTime) = ('NA') x 2;

	my $fullHeader = '';
	if($jobType =~ /LOCALBACKUP/i) {
		$fullHeader = Constants->CONST->{'ExpressBackupProgress'};
	} elsif($jobType =~ /Backup/i) {
		$fullHeader = Constants->CONST->{'BackupProgress'};
	} elsif($jobType =~ /cdp/i) {
		$fullHeader = Constants->CONST->{'CDPProgress'};
	} else {
		$fullHeader = Constants->CONST->{'RestoreProgress'};
	}

	my $incrFileSize = $progressDataHash[0];
	my $TotalSize = $progressDataHash[1];
	my $kbps = $progressDataHash[2];
	my $totalTransferredFiles = $progressDataHash[3];
	# $curLines = $progressDataHash[6];
	my $percent = 0;

	$TotalSize = $_[1]	if(defined $_[1] and $_[1] > 0);

	if($TotalSize ne Constants->CONST->{'CalCulate'} and $TotalSize != 0){
		$percent = int(($incrFileSize/$TotalSize)*100);
		$percent = 100	if($percent > 100);
		$progress = "|"x($percent/$progressSizeOp);
		my $cellCount = (100-$percent)/$progressSizeOp;
		$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
		$cellSize = " "x$cellCount;
		$totalSizeUnit = convertFileSize($TotalSize);
		my $jobRunningDir = (fileparse($_[0]))[1];
		my $totalFileCountFile	= "$jobRunningDir/totalFileCountFile";
		if(-f $totalFileCountFile and !-z _) {
			$totalFileCount = Common::getFileContents($totalFileCountFile);
			$remainingFile = ($totalFileCount - $totalTransferredFiles);
			$remainingFile = 0 if($remainingFile<0);
		}

		$seconds = ($TotalSize-$incrFileSize);
		$seconds = ($seconds/$kbps) if($kbps);
		#As per NAS: Need to display maximum time as 150 days only. 150*24*60*60 = 12960000
		my $maxtime = 12960000;
		if($seconds > $maxtime) {
			$remainingTime = Common::convertSecondsToReadableTime(ceil($maxtime));
		} else {
			$remainingTime = Common::convertSecondsToReadableTime(ceil($seconds));
		}

		$remainingTime = '0s' if(!$remainingTime || (int($remainingTime) != 0 && $remainingTime < 0));
	}
	else{
		#$totalSizeUnit = convertFileSize($TotalSize);
		$totalSizeUnit = Constants->CONST->{'CalCulate'};
		$cellSize = " "x(100/$progressSizeOp);
		$remainingFile = 'NA';
		$remainingTime = 'NA';
	}

	my $fileSizeUnit = convertFileSize($incrFileSize);
	#$kbps =~ s/\s+//;
	$percent = sprintf "%4s", "$percent%";
	$spAce = " " x 6;
	$boundary = "-"x(100/$progressSizeOp);
	$spAce1 = " "x(38/$progressSizeOp);

	my $fileDetailRow = $progressDataFileDisplayHash[rand @progressDataFileDisplayHash];
	if($fileDetailRow eq "") {
		for(my $i=0;$i<$totalEngineBackup;$i++) {
			$fileDetailRow = $progressDataFileDisplayHash[$i];
			last if($fileDetailRow ne "");
		}
	}
	return if($fileDetailRow eq "");

	my $strLen  = length $fileDetailRow;
	$emptySpaceDetail = " "x($latestCulmn-$strLen);
	$kbps = convertFileSize($kbps);
	my $sizeRowDetail = "$spAce1\[$fileSizeUnit of $totalSizeUnit] [$kbps/s]";
	$strLen  = length $sizeRowDetail;
	$emptySizeRowDetail = " "x($latestCulmn-$strLen);

	if(@individualProgressDataHash and $_[3] eq 'more') {
		for(my $i=1;$i<=$totalEngineBackup;$i++) {
			next unless($individualProgressDataHash[$i]);
			$moreProgress .= "Engine $i:\n";
			$moreProgress .= $individualProgressDataHash[$i]{'data'}."\n";
			my $per = $individualProgressDataHash[$i]{'per'};
			$per =~ s/%//;
			chomp($per);
			my $progress = "="x($per/$progressSizeOp);
			$moreProgress .= "$per% $progress\n\n";
		}
	}
	elsif($_[4] and $progressSizeOp == 2 and $machineInfo ne 'freebsd'){
		system(Common::updateLocaleCmd("tput rc"));
		system(Common::updateLocaleCmd("tput ed"));
		clearProgressScreen();
	}

	if($machineInfo eq 'freebsd'){
		system(Common::updateLocaleCmd("tput rc"));
		system(Common::updateLocaleCmd("tput ed"));
		clearProgressScreen();
	}

	system(Common::updateLocaleCmd("tput rc"));
	system(Common::updateLocaleCmd("tput ed"));

	print $moreProgress;
	print $fullHeader;
	print "$fileDetailRow $emptySpaceDetail\n\n";
	print "$spAce$boundary\n";
	print "$percent [";
	print $progress.$cellSize;
	print "]\n";
	print "$spAce$boundary\n";
	print "$sizeRowDetail $emptySizeRowDetail\n";

	if($jobType =~ /Backup/i || $jobType =~ /cdp/i) {
		my $space = 65;
		# $space = (100/$progressSizeOp); 
		$space = 40 if($progressSizeOp>1);
		my ($status,$backupType,$backupLocation,$backupLocationStr,$statusStr) = ("\n",'','','','');

		if($dedup eq 'on'){
			$backupLocation = ($backupHost =~ /#/)?(split('#',$backupHost))[1]:$backupHost;
			$backupLocation = "Backup Location : $backupLocation"." ";
		
			# $bwThrottle     = "BW Throttle(%)  : ".$bwThrottle;
			$spAce1     = " "x($space - length($backupLocation));
			$bwThrottle = "BW Throttle : ".$bwThrottle."%"." ";
			$backupLocationStr = "\n".$backupLocation.$spAce1.$bwThrottle;

			$remainingTime  = Common::getStringConstant('estimated_time_left')." : ".$remainingTime;
			my $fCount = Common::getStringConstant('files_count')." ";
			# $totalTransferredFiles = (" "x(8 - length($totalTransferredFiles))).$totalTransferredFiles; #Keeping empty space to display 8digit numbers
			# $remainingFile         = (" "x(8 - length($remainingFile))).$remainingFile; #Keeping empty space to display 8digit numbers
			$fCount =~ s/<CC>/$totalTransferredFiles/;
			$fCount =~ s/<RC>/$remainingFile/;
			$spAce1        = " "x($space - length($remainingTime));
			$remainingTime = $remainingTime.$spAce1.$fCount;
            
			if(defined($_[2])) {
				#$spAce1 = " "x(($space - length($remainingTime)-25));
				$spAce1 = " "x($space);
				# $spAce1 .= " " if($_[2] eq 'paused');

				$status = $spAce1."Status      : ".Common::colorScreenOutput(Common::getStringConstant($_[2]));
				my $keyPress = ($_[2] eq 'paused')?'press_r_to_run':'press_p_to_pause';
				$status .= " ".Common::getStringConstant($keyPress)." ";
				$statusStr = $status."\n";
			}
			
		} else {
			$backupLocation = "Backup Location     : $backupHost"." ";
			$backupLocation .= "  " if(length($backupLocation) >= $space);
			$spAce1 = " " x ($space - length($backupLocation));
			$bwThrottle = "BW Throttle : ".$bwThrottle."%"." ";
			$backupLocationStr = "\n".$backupLocation.$spAce1.$bwThrottle;
			$backupType  = "Backup Type         : ".ucfirst($backupPathType)." ";
			# $backupType .= "  ";
			$spAce1    = " " x ($space - length($backupType));
            
			my $fCount = Common::getStringConstant('files_count')." ";
			# $totalTransferredFiles = (" "x(8 - length($totalTransferredFiles))).$totalTransferredFiles; #Keeping empty space to display 8digit numbers
			# $remainingFile         = (" "x(8 - length($remainingFile))).$remainingFile; #Keeping empty space to display 8digit numbers
			$fCount =~ s/<CC>/$totalTransferredFiles/;
			$fCount =~ s/<RC>/$remainingFile/;
			$backupType = $backupType.$spAce1.$fCount."\n";
			$remainingTime  = Common::getStringConstant('estimated_time_left')." : ".$remainingTime;
			# $spAce1    = " " x ($space - length($remainingTime));
			# $bwThrottle = $bwThrottle.$spAce1.$remainingTime."\n";
			if(defined($_[2])) {
				#$spAce1 = " "x(($space - length($remainingTime)-25));
				$spAce1 = " " x ($space - length($remainingTime));
				# $spAce1 .= " " if($_[2] eq 'paused');
				$status = $spAce1."Status      : ".Common::colorScreenOutput(Common::getStringConstant($_[2]));
				
				my $keyPress = ($_[2] eq 'paused')?'press_r_to_run':'press_p_to_pause';
				$status .= " ".Common::getStringConstant($keyPress)." ";
				$remainingTime = $remainingTime.$status;
			}
		}
		print $backupLocationStr."\n";
		print $backupType;
		print $remainingTime."\n";
		print $statusStr;
	} else {
		my $space = 68;
		# $space = (100/$progressSizeOp); 
		$space = 40 if($progressSizeOp>1);
	
		my $restoreFromLoaction = $restoreHost;
		if($dedup eq 'on'){
			$restoreFromLoaction = (split('#',$restoreHost))[1] if($restoreHost =~ /#/);
		}
		print $lineFeed;
		
		my $restoreFromLocationStr = "Restore From Location : $restoreFromLoaction  ";
		my $restoreLocationStr = "Restore Location : $restoreLocation  ";
		my $remainingTimeStr = "Estimated Time Left   : ".$remainingTime." ";
		my $fCount = Common::getStringConstant('files_count')." ";

		#$restoreLocationStr .= "  ";
		# my $space = (100/$progressSizeOp);
		my $spAce1 = " "x($space - length($restoreFromLocationStr));	
		# $totalTransferredFiles = (" "x(8 - length($totalTransferredFiles))).$totalTransferredFiles; #Keeping empty space to display 8digit numbers
		# $remainingFile         = (" "x(8 - length($remainingFile))).$remainingFile; #Keeping empty space to display 8digit numbers
		$fCount =~ s/<CC>/$totalTransferredFiles/;
		$fCount =~ s/<RC>/$remainingFile/;
		$fCount =~ s/:/     :/;

		print $restoreFromLocationStr.$spAce1.$restoreLocationStr.$lineFeed;
		$spAce1 = " "x($space - length($remainingTimeStr));	
		# print "Completed file count  : ".$totalTransferredFiles."\n";
		# print "Remaining file count  : ".$remainingFile."\n";
		print $remainingTimeStr.$spAce1.$fCount.$lineFeed;
		# print $restoreLocationStr.$lineFeed;
		# print $remainingTime.$lineFeed;
	}
	print $lineFeed.Common::getStringConstant('note_completed_remaining').$lineFeed;
	# print Common::getStringConstant('note_for_more_less').$lineFeed;
	print $emptyLine;
}

#****************************************************************************************************
# Subroutine		: writeLogHeader.
# Objective			: This function will write user log header.
# Added By			: Dhritikana
# Modified By		: Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub writeLogHeader {
	my $isScheduledJob = $_[0];
	# require to open log file to show job in progress as well as to log exclude details
	if(!open(OUTFILE, ">" . ($iscdp? '>' : ''), $outputFilePath)){
		print Constants->CONST->{'CreateFail'}." $outputFilePath, Reason:$!";
		Common::traceLog(Constants->CONST->{'CreateFail'} . " $outputFilePath, Reason:$!") and die;
	}
	chmod $filePermission, $outputFilePath;

	autoflush OUTFILE;
	my $hostCmd = Common::updateLocaleCmd('hostname');
	my $host = `$hostCmd`;
	chomp($host);

	autoflush OUTFILE;
	my $tempJobType = $jobType;
	my $backupMountPath = '';
	my $cdplog = '';

	@startTime = localtime();
	my $st = localtime(mktime(@startTime));

	if($tempJobType =~ /Local/){
		$tempJobType =~ s/Local//;
		$backupMountPath = "[Mount Path: $expressLocalDir] $lineFeed";
	}

	my $jobname = '';
	my $jt = 'backup';
	if($jobType eq "backup") {
		$jobname = "default_backupset";
	} elsif($jobType eq "Local Backup") {
		$jobname = "local_backupset";
		$jt = "localbackup";
	} else {
		$jobname = "default_backupset";
	}

	if($iscdp) {
        if(-z $outputFilePath) {
            $cdplog .= Common::getStringConstant('details_log_header') ."\n";
            $cdplog .= (('-') x 9). "\n";
            $cdplog .= "[" . Common::getStringConstant('version_cc_label') . $AppConfig::version . '] [';
            $cdplog .= Common::getStringConstant('release_date_cc_label') . $AppConfig::releasedate . "] [";
            $cdplog .= Common::getStringConstant('username_cc') . ": $userName] [";
            $cdplog .= Common::getStringConstant('title_machine_name')."$host] $lineFeed";
            $cdplog	.= (('=') x 100). "\n\n";            
        }

        if(-z $outputFilePath or Common::getUserConfiguration('EXCLUDESETUPDATED')) {
			$cdplog	.= Common::getExcludeSetSummary($jt, $iscdp);
            $cdplog	.= (('=') x 100). "\n\n";
            Common::setUserConfiguration('EXCLUDESETUPDATED', 0);
            Common::saveUserConfiguration();
        }

        $cdplog .= "$tempJobType Start Time: ".($st).$lineFeed;
        $cdplog .= "[".Common::getStringConstant('backup_location_progress').": $location] ";
		$cdplog .= "[".Common::getStringConstant('backup_type').": ".ucfirst($backupPathType)."] " if($dedup eq 'off');
        $cdplog .= "[Throttle Value(%): $bwThrottle] ";
		$cdplog .= "[Show hidden files/folders: ".(Common::getUserConfiguration('SHOWHIDDEN')? 'enabled' : 'disabled')."] ";
		$cdplog .= "[Ignore file/folder level permission errors: ".(Common::getUserConfiguration('IFPE')? 'enabled' : 'disabled')."]".$lineFeed.$lineFeed;
    }

    my ($jsc, $exclsum, $mailHead) = ('') x 3;
	if($tempJobType eq "Restore") {
		my $location = Common::getUserConfiguration('RESTORELOCATION');
		my $fromLocation = ($dedup eq 'on' and $restoreHost =~ /#/)?(split('#',$restoreHost))[1]:$restoreHost;
        $mailHead .= "[".Common::getStringConstant('restore_location_progress').": $location]".$lineFeed;
		$mailHead .= "[$tempJobType From Location: $fromLocation] ";

		#Ignoring if version restore
		if($_[1] ne Constants->CONST->{'VersionOp'}) {
			$jsc .= "[RESTORE SET CONTENT]\n";
            $jsc .= (('-') x 21). "\n";
			$jsc .= Common::getJobSetLogSummary(lc($tempJobType));
		} else {
            my $restoreFileName = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::versionRestoreFile);
            my $data = Common::getFileContents($restoreFileName);
            my %fileInfo	= %{JSON::from_json($data)};
			if($fileInfo{'opType'} eq 'snapshot') {
				my ($fileList, $folderList)  = ('') x 2;
				$AppConfig::versionToRestore = $fileInfo{'endDate'};
				foreach my $itemName (keys %{$fileInfo{'items'}}) {
					if(lc($fileInfo{'items'}{$itemName}{'type'}) eq 'f') {
						$fileList .= $itemName.$lineFeed;
					} else {
						$folderList .= $itemName.$lineFeed;
					}
				}
				my $version = $fileInfo{'endDate'};
				$version =~ s/000432//;
				$version = Common::strftime("%m/%d/%Y %H:%M:%S", localtime($version));
				$mailHead .= "[Operation: Snapshot] [Backed up on or before: $version]";
				$jsc .= "[RESTORE SET CONTENT]\n";
				$jsc .= (('-') x 21). "\n";
				$jsc .= (($fileList ne '')? "[Files]\n" . $fileList."\n" : '');
				$jsc .= (($folderList ne '')? "[Directories]\n" . $folderList."\n" : '');
			} else {
				my $item    = (keys %{$fileInfo{'items'}})[0];
				my $version = $fileInfo{'items'}{$item}{'ver'};
				$AppConfig::versionToRestore = $version;

				my $type = 'File';
				if($fileInfo{'opType'} eq 'folderVersioning') {
					$version = Common::getStringConstant($version.'_most_recent');
					$type = 'Directory';
				}
				$mailHead .= $lineFeed;
				$mailHead .= "[Operation: Restore Version] [Type: $type] [Name: $item] [Version To Restore: $version]";
			}
		}
        $mailHead .= $lineFeed.$lineFeed;
        $mailHead .= "$tempJobType Scheduled Time: " . Common::getCRONScheduleTime($AppConfig::mcUser, $userName, lc($tempJobType), $jobname).$lineFeed if($taskType ne "Manual");
        $mailHead .= "$tempJobType Start Time: ".($st).$lineFeed.$lineFeed;
    }
	else {
		$mailHead .= "[Failed files(%): $percentToNotifyForFailedFiles] ";
		$mailHead .= "[Missing files(%): $percentToNotifyForMissedFiles] ";
        $mailHead .= "[" . Common::getStringConstant('title_machine_name')." $host] $lineFeed";
        $mailHead .= "[".Common::getStringConstant('backup_location_progress').": $location] ";
		$mailHead .= "[Show hidden files/folders: ".(Common::getUserConfiguration('SHOWHIDDEN')? 'enabled' : 'disabled')."] ";
		$mailHead .= ($jobType eq "Backup")?"[Throttle Value(%): $bwThrottle] $lineFeed":$lineFeed;
		$mailHead .= "[Ignore file/folder level permission errors: ".(Common::getUserConfiguration('IFPE')? 'enabled' : 'disabled')."]";
		$mailHead .= ($jobType eq "Backup" and $dedup eq 'off')?" [".Common::getStringConstant('backup_type').": ".ucfirst($backupPathType)."] $lineFeed":$lineFeed;
        $mailHead .= $backupMountPath;

        $mailHead .= $lineFeed . "$tempJobType Scheduled Time: " . Common::getCRONScheduleTime($AppConfig::mcUser, $userName, lc($tempJobType), $jobname) if($taskType ne "Manual");
        $mailHead .= $lineFeed . "$tempJobType Start Time: ".($st).$lineFeed.$lineFeed;

		$jsc 		.= ($jt eq 'backup'? '[BACKUP SET CONTENT]' : '[LOCAL BACKUP SET CONTENT]') . "\n";
        $jsc 		.= ($jt eq 'backup'? (('-') x 20): (('-') x 28)).$lineFeed;
		$jsc 		.= Common::getJobSetLogSummary($jt, $iscdp);
		$exclsum	.= Common::getExcludeSetSummary($jt);
=beg
		if($iscdp) {
			# $cdplog	.= "Throttle Value(%): $bwThrottle\n";
			$cdplog	.= "[BACKUP CONTENT]\n";
            $cdplog	.= (('-') x 16). "\n";
			$cdplog	.= Common::getJobSetLogSummary($jt);
		}
=cut
	}

	if($iscdp) {
		print OUTFILE $cdplog;
	} else {
        my $LogHead = Common::getStringConstant('details_log_header') .$lineFeed;
        $LogHead .= (('-') x 9). $lineFeed;
        $LogHead .= "[" . Common::getStringConstant('version_cc_label') . $AppConfig::version . '] ';
        $LogHead .= "[" . Common::getStringConstant('release_date_cc_label') . $AppConfig::releasedate . "] ";
        $LogHead .= "[" . Common::getStringConstant('username_cc') . ": $userName] $lineFeed";
        $LogHead .= $mailHead.$jsc.$exclsum;
        print OUTFILE $LogHead;
	}

	return $lineFeed.$mailHead;
}

#****************************************************************************************************
# Subroutine		: writeCDPBackupsetToLog
# Objective			: This function will write CDP contents to log
# Added By			: Sabin Cheruvattil
# Modified By       : Senthil Pandian
#*****************************************************************************************************/
sub writeCDPBackupsetToLog {
	my $bkpc = $_[0];
	my $cdpdirs = $_[1];
	return 0 if(!$bkpc and !$cdpdirs);

	if(scalar @{$cdpdirs} > 0) {
		my %index = ();
		@{$cdpdirs} = grep{!$index{$_}++} @{$cdpdirs};
	}

	my $bkpcont	= Common::getStringConstant('backup_content_c') . "\n";
	$bkpcont   .= (('-') x 16). "\n";

	for my $cdpd (@{$cdpdirs}) {
		chomp($cdpd);

		for my $cdpfi (0 .. $#{$bkpc}) {
			# Avoid displaying files from the directory which is moved in
			if($bkpc->[$cdpfi] and $bkpc->[$cdpfi] =~ /^\Q$cdpd\E/) {
				delete $bkpc->[$cdpfi];
			}
		}
	}

	# Avoid empty array elements[in log] which got removed if dirs are present
	if(scalar @{$cdpdirs} > 0 and scalar @{$bkpc} > 0) {
		@$bkpc = grep{$_} @$bkpc;
	}

	if(scalar @{$cdpdirs} > 0) {
		$bkpcont .= "[Directories]\n" . join("\n", @{$cdpdirs}) . "\n";
	}

	if(scalar @{$bkpc} > 0) {
		$bkpcont .= "[Files]\n" . join("\n", @{$bkpc}) . "\n";
	}

	print OUTFILE $bkpcont. "\n";;
}

#*******************************************************************************************
# Subroutine Name         :	writeOperationSummary
# Objective               :	This subroutine writes the restore summary to the output file.
# Added By                :
# Modified By             : Yogesh Kumar, Vijay Vinoth, Sabin Cheruvattil, Senthil Pandian
#******************************************************************************************
sub writeOperationSummary {
	my $infoFile 		= "$jobRunningDir/info_file";
	$filesConsideredCount = $totalFiles;
	chomp($filesConsideredCount);

	my $transferredFileSize = $_[2] || 0;
	my $fs = convertFileSize($transferredFileSize);

	chmod $filePermission, $outputFilePath;
	$summary = '';
	$status  = "Aborted";
	if ((-e $outputFilePath) and (!-z $outputFilePath)){# If $outputFilePath exists then only summary will be written otherwise no summary file will exists.
		# open output.txt file to write restore summary.
		if (!open(OUTFILE, ">> $outputFilePath")){
			Common::traceLog(Constants->CONST->{'FileOpnErr'} . $outputFilePath.", Reason:$!");
			return;
		}
		chmod $filePermission, $outputFilePath;

        unless($successFiles) {
            my $progressFile = Common::getCatfile($jobRunningDir,$progressDetailsFileName."_1");
            if(-f $progressFile) {
                if($_[0] eq Constants->CONST->{'BackupOp'}) {
                    $summary .= Common::getStringConstant('no_items_to_backup')."\n\n";
                } else {
                    $summary .= Common::getStringConstant('no_items_to_restore')."\n\n";
                }
            }
        }  else {
            $summary .= "\n";
        }

		$summary .= appendExcludedLogFileContents() if($_[0] =~ Constants->CONST->{'BackupOp'} and !$iscdp);

		my $permissionError = $errorDir."/permissionError.txt";
		if($_[0] eq Constants->CONST->{'BackupOp'}){
			$isIgnorePermissionErrors = (Common::getUserConfiguration('IFPE') ne '')? Common::getUserConfiguration('IFPE') :0;
			if($isIgnorePermissionErrors){
				$filesConsideredCount -= $noPermissionCount;
				$summary .= checkAndUpdatePermissionDeniedList($permissionError).$lineFeed;
			} else {
				#$failedFilesCount += $noPermissionCount; #Commented by Senthil on 11-June-2019
				my $deniedCount = getPermissionDeniedCount();
				if($deniedCount =~ /^\d+$/){
					$failedFilesCount     += $deniedCount;
					$filesConsideredCount += $deniedCount;
				}
			}
			$syncedFiles += getReadySyncCount();
		}

		if($failedFilesCount > 0 or $nonExistsCount >0) {
			appendErrorFileContents($errorDir);
			$summary .= $summaryError.$lineFeed;
			$failedFilesCount += $nonExistsCount;
		}

		# construct summary message.
		my $mail_summary = undef;
        $summary .= "[SUMMARY] ".$lineFeed.(('-') x 9).$lineFeed unless($iscdp);
		$finalSummary =  $lineFeed."[SUMMARY] ".$lineFeed;
		Chomp(\$filesConsideredCount);
		#Needs to be removed: Senthil
		#$filesConsideredCount = 90;
		#$failedFilesCount  = 5;
		@endTime = localtime();
		my $et = localtime(mktime(@endTime));
		if($_[0] eq Constants->CONST->{'BackupOp'}) {
			$mail_summary .= Constants->CONST->{'TotalBckCnsdrdFile'} . $filesConsideredCount.
            $mail_summary .= $lineFeed . Constants->CONST->{'TotalBckFile'} . $successFiles . " [Added(".($successFiles-$modifiedCount).")/modified($modifiedCount)] [".Common::getStringConstant('size_of_backed_up_files').$fs."]" .
			$mail_summary .= $lineFeed . Constants->CONST->{'TotalCondSynFile'} . $syncedFiles;
			$mail_summary .= $lineFeed . Constants->CONST->{'TotalBckFailFile'} . $failedFilesCount;
			$mail_summary .= $lineFeed . Constants->CONST->{'BckEndTm'} . $et . $lineFeed;
			unless($iscdp) {
				$mail_summary .= $lineFeed . Common::getStringConstant('files_in_trash_may_get_restored_notice') . $lineFeed;
				my $hasDefExcl = Common::hasDefaultExcludeInBackup($AppConfig::jobType);
				$mail_summary .= $lineFeed . Common::getStringConstant('default_exclude_note') . $lineFeed if($hasDefExcl);
			}


			if($iscdp) {
				# $summary	.= "\n\n" . appendExcludedLogFileContents() . "\n\n";
                $summary .= "[".Common::getStringConstant('files_to_backup').$filesConsideredCount."] ";
                my $addedFiles = ($successFiles-$modifiedCount);
                my $countSummary = Common::getStringConstant('backed_up_now_cdp_summary');
                $countSummary =~ s/<TOTAL>/$successFiles/;
                $countSummary =~ s/<ADDED>/$addedFiles/;
                $countSummary =~ s/<MODIFIED>/$modifiedCount/;
                $summary .= "[".$countSummary."] ";
                $summary .= "[".Common::getStringConstant('size_of_backed_up_files').$fs."] ";
                $summary .= "[".Common::getStringConstant('failed_to_backup').$failedFilesCount."] ";
                $summary .= "[".Common::getStringConstant('total_excluded_files').": ".$AppConfig::excludedCount."] ".$lineFeed . $lineFeed;
				$summary .= Constants->CONST->{'BckEndTm'} . $et. $lineFeed;
                $summary .= appendExcludedLogFileContents();
                $summary .= $lineFeed unless($AppConfig::excludedCount);
				# $finalSummary .= Constants->CONST->{'TotalBckCnsdrdFile'} . $filesConsideredCount;
				$finalSummary .= Constants->CONST->{'TotalBckFile'} . $successFiles . " [Size: $fs]\n";
				# $finalSummary .= "\n" . Constants->CONST->{'TotalSynFile'} . $syncedFiles;
				$finalSummary .= Constants->CONST->{'TotalBckFailFile'} . $failedFilesCount . "\n";
			} else {
				$finalSummary .= Constants->CONST->{'TotalBckCnsdrdFile'}.$filesConsideredCount.
					$lineFeed.Constants->CONST->{'TotalBckFile'}.$successFiles . " [Added(".($successFiles-$modifiedCount).")/modified($modifiedCount)] [".Common::getStringConstant('size_of_backed_up_files').$fs."]" .
					$lineFeed.Constants->CONST->{'TotalSynFile'}.$syncedFiles.
					$lineFeed.Constants->CONST->{'TotalBckFailFile'}.$failedFilesCount.$lineFeed;
			}
		} else 	{
         # [Added(1000)/updated(100)] [Size of backed up files: 10.62 KB]

			$mail_summary .= Constants->CONST->{'TotalRstCnsdFile'}.$filesConsideredCount.
						$lineFeed.Constants->CONST->{'TotalRstFile'}.$successFiles. " [Size: $fs]".
						$lineFeed.Constants->CONST->{'TotalSynFileRestore'}.$syncedFiles.
						$lineFeed.Constants->CONST->{'TotalRstFailFile'}.$failedFilesCount.
						$lineFeed.Constants->CONST->{'RstEndTm'}.$et. $lineFeed;

			$finalSummary .= Constants->CONST->{'TotalRstCnsdFile'}.$filesConsideredCount.
					       $lineFeed.Constants->CONST->{'TotalRstFile'}.$successFiles." [Size: $fs]".
					       $lineFeed.Constants->CONST->{'TotalSynFileRestore'}.$syncedFiles.
					       $lineFeed.Constants->CONST->{'TotalRstFailFile'}.$failedFilesCount.$lineFeed;
		}
		# if($errStr ne "" &&  $errStr ne "SUCCESS"){
			# $mail_summary .= $lineFeed.$lineFeed.$errStr.$lineFeed;
		# }

		if ($_[1]) {
			$status = "Aborted";
		}
		elsif ($failedFilesCount == 0 and $filesConsideredCount > 0) {
			$status = "Success";
		}
		else {
			$status = "Failure";
			# Considering the Failed case as Success if it less than the % user's selected
			if($_[0] eq Constants->CONST->{'BackupOp'}){
				if($percentToNotifyForFailedFiles and $failedFilesCount>0){
					if($filesConsideredCount) {
						my $perCount = ($failedFilesCount/$filesConsideredCount)*100;
						if($percentToNotifyForFailedFiles >= $perCount){
							$status = "Success*";
						}
					}
				}

				if($status eq "Failure"){
					if($percentToNotifyForMissedFiles and -e $infoFile){
						my $missedCountCheckCmd = "cat '$infoFile' | grep \"^MISSINGCOUNT\"";
						$missedCountCheckCmd = Common::updateLocaleCmd($missedCountCheckCmd);
						my $missedCount = `$missedCountCheckCmd`;
						$missedCount =~ s/MISSINGCOUNT//;
						Chomp(\$missedCount) if($missedCount);
						$missingCount += $missedCount if($missedCount =~ /^\d+$/);
						if($filesConsideredCount and $missingCount) {
							my $perCount = ($missingCount/$filesConsideredCount)*100;
							if($percentToNotifyForMissedFiles >= $perCount){
								$status = "Success*";
							}
						}
					}
				}
			}
		}

		if ($errStr ne "" &&  $status ne "Success") {
			$mail_summary .= $lineFeed.$lineFeed.$errStr.$lineFeed;
		}

		if (Common::loadAppPath()  and Common::loadServicePath()) {
			Common::setUsername($userName) if(defined($userName) && $userName ne '');
			my $tempOutputFilePath = $outputFilePath;
			$tempOutputFilePath = (split("_Running_",$tempOutputFilePath))[0] if($tempOutputFilePath =~ m/_Running_/);
			my %logStat = (
				(split('_', basename($tempOutputFilePath)))[0] => {
					'datetime' => strftime("%m/%d/%Y %H:%M:%S", localtime(mktime(@startTime))),
					'duration' => (mktime(@endTime) - mktime(@startTime)),
					'filescount' => $filesConsideredCount,
                    'bkpfiles' => $successFiles,
					# 'status' => $iscdp? ($filesConsideredCount == 0? 'NoFiles_CDP' : $status . "_CDP") : ($status . "_" . $taskType),
					'status' => $iscdp? ($filesConsideredCount == 0? 'NoFiles_CDP' : $status . "_CDP") : ($status . "_" . $taskType),
					'size' => $fs,
				}
			);
			Common::addLogStat($jobRunningDir, \%logStat);
			if ($jobType eq 'Backup') {
				my $bs = 'F';
				if ($status =~ m/^A/) {
					$bs = 'C';
				}
				elsif ($status =~ m/^F/) {
					$bs = 'F';
				}
				elsif ($status =~ m/^S/) {
					$bs = 'S';
				}

				# backup summary update
				my $bkp = Common::getUserConfiguration('BACKUPLOCATION');
				$bkp = (split("#", $bkp))[1] if (Common::getUserConfiguration('DEDUP') eq 'on');
				Common::makeRequest(5, [
					'7',
					$bs,
					($taskType eq 'Manual') ? '1' : '2',
					$fs,
					strftime("%y-%m-%d %H:%M:%S", localtime(mktime(@endTime))),
					$AppConfig::hostname,
					$filesConsideredCount,
					$successFiles,
					$failedFilesCount,
					$syncedFiles,
				]);
			}
		}
		#Removing LOGPID file
		my $logPidFilePath = "$jobRunningDir/".$logPidFile;
		unlink($logPidFilePath);

		$summary .= $mail_summary unless($iscdp);
#		$mail_content .= $mail_summary;
		$AppConfig::mailContent .= $mail_summary;
		print OUTFILE $summary;
		close OUTFILE;
	} else {
		# Added to debug Harish_1.0.2_2_5 : Senthil
		Common::traceLog("writeOperationSummary outputFilePath:$outputFilePath");
		Common::traceLog("writeOperationSummary SIZE:".(-s $outputFilePath));
	}	
}

#*******************************************************************************************
# Subroutine Name         : createUserDir
# Objective               : This subroutine creates directory for given path.
# Added By                : Dhritikana
#******************************************************************************************
sub createUserDir {
	$usrProfileDir = "$usrProfilePath/$mcUser/$userName";
	my $usrBackupDir = "$usrProfileDir/Backup";
	my $usrBackupManualDir = "$usrProfileDir/Backup/DefaultBackupSet";
	my $usrlocalBackupManualDir = "$usrProfileDir/LocalBackup/LocalBackupSet";
	my $usrRestoreDir = "$usrProfileDir/Restore";
	my $usrRestoreManualDir = "$usrProfileDir/Restore/DefaultRestoreSet";
	my $userInfo = "$usrProfileDir/.userInfo";

	my @dirArr = ($usrProfilePath, $usrProfileDir, $usrBackupDir, $usrBackupManualDir, $usrRestoreDir, $usrRestoreManualDir,$userInfo,$usrlocalBackupManualDir);

	foreach my $dir (@dirArr) {
		if(! -d $dir) {
			$mkDirFlag = 1;
			my $ret = mkdir "$dir", $filePermission;
			if($ret ne 1) {
				print Constants->CONST->{'MkDirErr'}.$dir.": $!".$lineFeed;
				Common::traceLog(Constants->CONST->{'MkDirErr'} . $dir . ": $!");
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
	$pidPath = $_[0] if(defined($_[0]));
	if(!open(PIDFILE, '>', $pidPath)) {
		Common::traceLog("Cannot open '$pidPath' for writing: $!");
		return 0;
	}
	if(!flock(PIDFILE, LOCK_EX|LOCK_NB)) {
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
	if ($backupPathType eq "relative") {
		$relative = 0;
	}
	elsif($backupPathType eq "mirror") {
		$relative = 1;
	}
	else {
		print Constants->CONST->{'WrongBackupType'}.$lineFeed;
		Common::traceLog(Constants->CONST->{'WrongBackupType'});
		cancelProcess();
	}
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	getCursorPos
# Objective               :	gets the current cusror position
# Added By                : Dhritikana
# Modified By			  : Senthil Pandian
#********************************************************************************************************/
sub getCursorPos {
	# Added here to resolve: tput: no terminal type specified and no TERM environmental variable.
	# Added for FreeBSD machine's progress bar display
=beg
	if($machineInfo eq 'freebsd'){
		my $latestCulmnCmd = Common::updateLocaleCmd('tput cols');
		$latestCulmn = `$latestCulmnCmd`;
		my $lineCount = 20;
		my $totalLinesCmd = Common::updateLocaleCmd('tput lines');
		my $totalLines = `$totalLinesCmd`;
		chomp($totalLines) if($totalLines);

		$lineCount = $totalLines;
		for(my $i=0; $i<=$lineCount; $i++){
			$freebsdProgress .= (' ')x$latestCulmn;
			$freebsdProgress .= "\n";
		}
	}
=cut
=beg
	system('stty', '-echo');
	my $x='';
	my $inputTerminationChar = $/;

	system "stty cbreak </dev/tty >/dev/tty 2>&1" if(-e '/dev/tty');
	print "\e[6n";
	$/ = "R";
	$x = <STDIN>;
	$/ = $inputTerminationChar;

	system "stty -cbreak </dev/tty >/dev/tty 2>&1" if(-e '/dev/tty');
	my ($curLines, $cols)=$x=~m/(\d+)\;(\d+)/;
	system('stty', 'echo');
	my $totalLinesCmd = Common::updateLocaleCmd('tput lines');
	my $totalLines = `$totalLinesCmd`;
	chomp($totalLines);
	my $threshold = $totalLines-12;

	if($curLines >= $threshold) {
		system(Common::updateLocaleCmd("clear"));
		print $lineFeed;
		$curLines = 0;
	} else {
		$curLines = $curLines-1;
	}
=cut

    system(Common::updateLocaleCmd("clear"));

    changeSizeVal();
	print " ".$lineFeed;
	system(Common::updateLocaleCmd("tput sc"));
	print "\n$_[0]" if ($_[0] ne '');
	print Constants->CONST->{'PrepFileMsg'}.$lineFeed;
}

#****************************************************************************************************
# Subroutine Name         : changeSizeVal.
# Objective               : Changes the size op value based on terminal size change.
# Modified By             : Dhritikana, Senthil Pandian
#*****************************************************************************************************/
sub changeSizeVal {
	$progressSizeOp = 1;
	my $latestCulmnCmd = Common::updateLocaleCmd('tput cols');
	$latestCulmn = `$latestCulmnCmd`;
	chomp($latestCulmn);

	my $latestRowsCmd = Common::updateLocaleCmd('tput lines');
	$latestRows = `$totalLinesCmd`;
	chomp($latestRows);
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
# Modified By             :	Vijay Vinoth
#****************************************************************************/
sub emptyLocationsQueries {
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);

	my $hostNameCmd = Common::updateLocaleCmd('hostname');
	my $hostName = `$hostNameCmd`;
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
			$displayLocation = "/".$hostName;
			$defaultLocationFlag=1;
		}

		print $lineFeed.$locationQuery." \"$displayLocation\"\. ".Constants->CONST->{'reallyEditQuery'};
		my $choice = getConfirmationChoice();
		if(($choice eq "n" || $choice eq "N")) {
			$backupHost = "/".$hostName if($defaultLocationFlag);
            print qq{Your Backup location remains "$backupHost".$lineFeed};
            holdScreen2displayMessage(2) if ($_[0] eq '');
			print $lineFeed;
		}
		else {
			#if (runningJobHandler($jobType,'Scheduled',$userName,$usrProfilePath)){#This check will allow to change location only if backup job is not running.
				#get user backup location
				print Constants->CONST->{'AskLocforBackup'};
				if($dedup eq 'on'){
					while ($currentBackupLocation !~ /^(?=.{4,64}$)^[A-Za-z0-9_\-]+$/){
						if ($backupLocationCheckCount>0){
							print Constants->CONST->{'InvLocInput'};
							print $lineFeed.Constants->CONST->{'AskLocforBackup'};
						}
						$currentBackupLocation = getLocationInput("backupHost");
						if ($backupLocationCheckCount == 3) {
								$currentBackupLocation = q{Invalid Location};
								$backupLocationCheckCount=0;
								last;
						}
						$backupLocationCheckCount++;
					}
				}
                else{
					$currentBackupLocation = getLocationInput("backupHost");
					unless($currentBackupLocation){
						$currentBackupLocation = "/".$hostName;
					}
				}
				if ($currentBackupLocation eq 'Invalid Location'){
					if (ref $_[0] eq 'SCALAR'){
						${$_[0]} = qq{$currentBackupLocation.\nYour maximum attempt to change $locName location has reached.\nYour $locName location remains "$backupHost". $lineFeed};
					}
                    else{
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
						$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
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
								Common::createBackupStatRenewalByJob('backup');
								$backupHost = $oldBackupLoc;
								unlink($pwdPath);
								if (ref $_[0] eq 'SCALAR'){
                                	${$_[0]} = $lineFeed.ucfirst($&).'. '.Constants->CONST->{loginAccount}.$lineFeed.$lineFeed;
                                }
								else{
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
			# }else{
				# if (ref $_[0] eq 'SCALAR'){
					# ${$_[0]} = qq{\nYour Backup Location remains "$backupHost" . $lineFeed $lineFeed};
				# }else{
					# print qq{\nYour Backup Location remains "$backupHost" . $lineFeed $lineFeed};
					# holdScreen2displayMessage(2);
				# }
			# }
			if($isSameDeviceID){
				$restoreHost = $backupHost;
				$restoreHost = Common::removeMultipleSlashs($restoreHost);
				$restoreHost = Common::removeLastSlash($restoreHost);				
				Common::setUserConfiguration('RESTOREFROM', $restoreHost);
			}
		}
		
		$backupHost = Common::removeMultipleSlashs($backupHost);
		$backupHost = Common::removeLastSlash($backupHost);
		Common::setUserConfiguration('BACKUPLOCATION', $backupHost);
		Common::setUserConfiguration('SERVERROOT', $serverRoot);

		if(Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
			Common::setNotification('register_dashboard') and Common::saveNotifications();
			Common::unlockCriticalUpdate("notification");
		}

		unless($backupHost eq $tmpBackupHost) {
			Common::createBackupStatRenewalByJob('backup') if(Common::getUsername() ne '' && Common::getLoggedInUsername() eq Common::getUsername());
			Common::setBackupLocationSize();
		}

		if($restoreHost eq "") {
			$restoreHost = $backupHost;
			Common::setUserConfiguration('RESTOREFROM', $restoreHost);
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
			my $restoreLocationMess = qq{\nYour $locName from location is "$restoreHost". }.Constants->CONST->{'editQuery'};
			if($backupHost eq $restoreHost){
				my $val = $backupHost;
				$val  = (substr($val, 0, 1) eq "/")?substr($val, 1):$val;
				$restoreLocationMess = qq{\nAs per your Backup location your $locName from location is "$val". }.Constants->CONST->{'editQuery'};
			}
			print $restoreLocationMess;
			$choice = getConfirmationChoice();
		}

		if($choice eq 'y' || $choice eq 'Y') {
			#This check will allow to change location only if restore job is not running. If running, first terminate.
			#if (runningJobHandler('Restore','Scheduled',$userName,$usrProfilePath)){
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
                if($currentRestoreLocation eq 'Invalid Location') {
                    print qq{$currentRestoreLocation ... $lineFeed}.Constants->CONST->{'maxRetryRestoreFrom'}.qq{\nYour $locName from location remains "$restoreHost". $lineFeed};
                    holdScreen2displayMessage(2) if ($_[0] eq '');
                    $existCheck = 1;
                }
                else {
                    $tempRestoreHost = $currentRestoreLocation;
                }
#					if (comapareLocation($restoreHost,$tempRestoreHost) and $existCheck == 0){
#							print qq{Your Restore From location changed successfully to $restoreHost.$lineFeed};
#							holdScreen2displayMessage(2) if ($_[0] eq '');
#					}else{
                my $locationEntryCount = 0;
                while($existCheck eq 0){
                    #RHFileName has been used to keep the restore host name in file and pass it to Item status EVS commands.
                    open (RH,'>',"$usrProfileDir/Restore/DefaultRestoreSet/RHFileName") or die "unable to open file. Reason $!";
                    print RH $tempRestoreHost;
                    close(RH);
                    my $propertiesFile = getOperationFile(Constants->CONST->{'ItemStatOp'},"$usrProfileDir/Restore/DefaultRestoreSet/RHFileName");
#							my $propertiesFile = getOperationFile(Constants->CONST->{'PropertiesOp'},$tempRestoreHost);
                    chomp($propertiesFile);
                    $propertiesFile =~ s/\'/\'\\''/g;
#							$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$propertiesFile."'".$whiteSpace.$errorRedirection;
                    $idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$propertiesFile."'";
                    $idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
                    my $commandOutput = `$idevsutilCommandLine`;
                    unlink $propertiesFile;
                    my $invalidLocationFlag = 0;
                    if(-s "$usrProfileDir/Restore/DefaultRestoreSet/error.txt" > 0){
                        if(appLogout("$usrProfileDir/Restore/DefaultRestoreSet/error.txt")){
                             print Constants->CONST->{'UnableToConnect'}.$lineFeed;
                                                         cancelProcess();
                        }
                    }
                    else {
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
                                print  qq{Your maximum attempt to change Restore From location has reached. \nYour Restore From location remains "$restoreHost".$lineFeed $lineFeed};
                                $invalidLocationFlag = 1;
                                holdScreen2displayMessage(2) if ($_[0] eq '');
                                $existCheck = 1;
                            }
                            else{
                                $tempRestoreHost = $currentRestoreLocation if ($currentRestoreLocation ne '');
                            }
                            $restoreLocationCheckCount++;
                        }
                        elsif($commandOutput =~ /password mismatch|encryption verification failed/i){
                            Common::createBackupStatRenewalByJob('backup');
                            unlink($pwdPath);
                            if (ref $_[0] eq 'SCALAR'){
                                ${$_[0]} = $lineFeed.ucfirst($&).'. '.Constants->CONST->{loginAccount}.$lineFeed.$lineFeed;
                                last;
                            }
                            else {
                                print  ucfirst($&).'. '.Constants->CONST->{loginAccount}. $lineFeed.$lineFeed;
                                exit(0);
                            }
                        }
                        elsif($commandOutput =~ /idevs: failed to connect.*/i){
                            $backupHost = $oldBackupLoc;
                            if (ref $_[0] eq 'SCALAR'){
                                ${$_[0]} = qq(\nUnable to change your $locName location. Failed to connect.).' '.Constants->CONST->{ProxyErr}.$lineFeed;
                                last;
                            }
                            else {
                                print qq(\nUnable to change your $locName location. Failed to connect.).' '.Constants->CONST->{ProxyErr}.$lineFeed;
                                exit(0);
                            }
                        }
                        else{
                            $existCheck = 1;
                            $restoreHost = $tempRestoreHost;
                            $restoreHost = '/'.$restoreHost if ($restoreHost !~/^\//);
                            print qq{Your Restore From location has been changed to "$restoreHost".$lineFeed $lineFeed};
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
			}
            elsif($dedup eq 'on'){
                print $lineFeed.Constants->CONST->{'LoadingAccDetails'};
                %evsDeviceHashOutput = getDeviceList();
                my $totalElements = keys %evsDeviceHashOutput;
                if ($totalElements == 1 or $totalElements == 0){
                    print $lineFeed.$lineFeed.Constants->CONST->{'restoreFromLocationNotFound'}.$lineFeed.$lineFeed;
                    unlink($pidPath) if(-e $pidPath);
                    exit(0);
                }
                checkAndLinkBucketSilently(); #Added to update UID silently
                print $lineFeed.$lineFeed.Constants->CONST->{'selectRestoreFromLoc'}.$lineFeed;
                my @devicesToLink = displayDeviceList(\%evsDeviceHashOutput,\@columnNames);
                my $userChoice = getUserMenuChoice(scalar(@devicesToLink),4);
                $userChoice -= 1;
                $restoreHost = $deviceIdPrefix.$devicesToLink[$userChoice]->{device_id}.$deviceIdPostfix.'#'.$devicesToLink[$userChoice]->{nick_name};
                print $lineFeed.Constants->CONST->{'RestoreLocMsg'}.$whiteSpace.'"'.$devicesToLink[$userChoice]->{nick_name}.'".'.$lineFeed;
            }
            $restoreHost = Common::removeMultipleSlashs($restoreHost);
            $restoreHost = Common::removeLastSlash($restoreHost);
            Common::setUserConfiguration('RESTOREFROM', $restoreHost);
            if ($dedup eq 'on'){
                ($restoreDeviceID,$restoreHost) = split ('#',$restoreHost);
            }
        } else{
            print qq{Your Restore From location remains "$restoreHost".$lineFeed $lineFeed};
            holdScreen2displayMessage(2) if ($_[0] eq '');
        }
        #In case of restore version script call to below sub is restricted. Other cases it will work.
        if(Common::getUserConfiguration('RESTORELOCATIONPROMPT')) {
            #In case of restore script we r calling this sub seperately inside Restore_Version.pl script.
            # askRestoreLocation($_[0]);
            Common::editRestoreLocation(1);
            sleep(2);
        }
	}
	Common::saveUserConfiguration();
}
#****************************************************************************
# Subroutine		: appLogout
# Objective			: If error matched with the mentioned error messages. Then logout from the script.
# Added By			: Abhishek Verma.
# Modified By		: Sabin Cheruvattil
#****************************************************************************/
sub appLogout{
	my $errorMessage = $_[0];
	if (-f $_[0]) {
		if (!open(EF, '<', $_[0])) { # EF means error file handler.
			Common::traceLog("Failed to open $_[0], Reason:$!");
        	print "Failed to open $statusFilePath, Reason:$! \n";
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
# Modified By             : Senthil Pandian
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
        my $tempRestoreLocation = $restoreLocation;
        utf8::decode($tempRestoreLocation); #Added for Suruchi_2.3_10_8: Senthil
		if (-e $tempRestoreLocation){
			if (validateDir($tempRestoreLocation)){
				print Constants->CONST->{'InvRestoreLoc'}.qq(. Reason : "$restoreLocation" ).Constants->CONST->{'noSufficientPermission'}.'. '.Constants->CONST->{'providePermission'}.$lineFeed;
                #unlink($pidPath);
                cancelProcess();
            }
		}
        else{
			#print Constants->CONST->{'InvRestoreLoc'}.qq(. Reason : "$restoreLocation" ).Constants->CONST->{'notExists'}.'. '.Constants->CONST->{'TryAgain'}.$lineFeed;
			print Constants->CONST->{'YourRestoreLocationNotExist'}.$lineFeed;
			cancelProcess();
		}
		print Constants->CONST->{'restoreLocNoChange'}.qq( "$restoreLocation".$lineFeed);
	}

	$restoreLocation=~s/^\'//;
	$restoreLocation=~s/\'$//;
	putParameterValue("RESTORELOCATION", $restoreLocation);
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

	chomp($mcUser);
	my $logContent = "[$date][$mcUser]". $_[1];
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
		my $mkResCmd = Common::updateLocaleCmd("mkdir -p '$traceDir' $errorRedirection");
		my $mkRes = `$mkResCmd`;
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
	my $pwdCmd = Common::updateLocaleCmd('pwd');
	chomp(my $presentWorkingDir =`$pwdCmd`);
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
	for (my $i=0; $i<=$#_; $i++) {
		if ($_[$i] eq '..') {
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
#Sbroutine Name         : displayFinalSummary(SCALAR,SCALAR);
#Objective              : It display the final summary after the backup/restore job has been completed.
#Usage                  : displayFinalSummary(JOB_TYPE,FINAL_SUMMARY_FILE_PATH);
#Added By               : Abhishek Verma.
#***********************************************************************************************/
sub displayFinalSummary{
	my ($jobType,$finalSummaryFile) = @_;
	my $errString = undef;
	if (open(FS,'<',$finalSummaryFile)){#FS file handel means (F)ile (S)ummary.
		chomp(my @fileSummary = <FS>);
		close(FS);

		$errString	= pop (@fileSummary) if ($#fileSummary >= 8);
		$jobStatus	= pop (@fileSummary);
		my $logFilePath = pop (@fileSummary);
		my $fileSummary = join ("\n", @fileSummary);

		if ($jobStatus eq 'Success' or $jobStatus eq 'Success*'){
			$jobStatus = qq($jobType has been completed.);
			if($jobType eq "Backup" && $jobStatus eq "Success*") {
				$content .= "\n Note: Success* denotes \'mostly success\' or \'majority of files are successfully backed up\' \n";
			}
		}elsif($jobStatus eq 'Failure' or $jobStatus eq 'Aborted'){
			$jobStatus = defined ($errString) ? $errString : qq($jobType has been failed.);
			$jobStatus = "$jobStatus\n";
		} else {
			$jobStatus = '';
		}
		print qq(\n\n$jobStatus\n$fileSummary\n);
		print qq(\n$logFilePath\n) if($logFilePath);
		#unlink($finalSummaryFile);
	}
	# else{
		# print qq(\nUnable to print status summary. Reason: $!\n);
	# }
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
	my $versionCmd = Common::updateLocaleCmd('cat /proc/version');
	if (-e '/proc/version' && `$versionCmd` =~ /ubuntu/){
		$checkUbuntu = 1;
	}
	return $checkUbuntu;
}

#*****************************************************************************************************
# Subroutine			: isGentoo
# Objective				: This is to verify the machine is Gentoo or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isGentoo {
	my $versionCmd = Common::updateLocaleCmd('cat /proc/version');
	return 1 if(-e '/proc/version' && `$versionCmd` =~ /gentoo/);
	return 0;
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
		$cmd = Common::updateLocaleCmd($cmd);
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
# Subroutine		: setRestoreLocation(RESTORE_LOCATION);
# Objective			: This function will set restore location directory, which contains all the files that are restored.
# Usage				: setRestoreLocation($restoreLocation);
# Added By			: Abhishek Verma.
# Modified By		: Sabin Cheruvattil
#***********************************************************************************************/
sub setRestoreLocation{
	$restoreLocation   = ($_[0] ne '') ? $_[0] : $_[1];
	my $defaultRestoreLocation	= $_[1];
	my $defaultKey	   = isDefaultRestoreLoc($restoreLocation);
	my $userLocMessage = ($defaultKey eq 'DEFAULT')? Constants->CONST->{'defaultRestLocMess'}.qq( "$restoreLocation" $lineFeed) : Constants->CONST->{'restoreLocCreation'}.$lineFeed;
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
	my $changeModeCmd = Common::updateLocaleCmd("chmod -R 0777 '$_[0]' $errorDevNull");
	my $res	= `$changeModeCmd`;
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
#		$mail_content = qq{\n$err_string\nAfter complition, run scheduled $jobType Job again.};
		$AppConfig::mailContent = qq{\n$err_string\nAfter complition, run scheduled $jobType Job again.};
		my $subjectLine = "$taskType $jobType Status Report "."[$userName]"." [Failed $jobType]";
		$status = "FAILURE";
		Common::traceLog($err_string);
		Common::sendMail({
				'serviceType' => $taskType,
				'jobType' => $jobType,
				'subject' => $subjectLine,
				'jobStatus' => lc($status)
			});
	}
	print qq($err_string);
	return 0;
}
#****************************************************************************
# Subroutine Name : headerDisplay
# Objective       : To display header information
# Usgae 		  : headerDisplay($callingScript)
# 			      : where, $callingScript = From which script headerDisplay subroutine has been called.
# Added By        : Abhishek Verma.
# Modified By     : Senthil Pandian
#****************************************************************************/
sub headerDisplay{
	getQuotaDetails();
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	# Common::loadUsername() or Common::retreat('login_&_try_again');
	Common::setUsername($userName) if(defined($userName) && $userName ne '');
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);	
	Common::isLoggedin() or Common::retreat('login_&_try_again');
	Common::displayHeader();
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
	$serviceDir = $appTypeSupport eq 'ibackup' ? 'ibackup' : $AppConfig::servicePathName;
	if (${$servicePath} ne ''){
		if ((split('/',${$servicePath}))[-1] !~ /^($AppConfig::servicePathName|ibackup)\/?$/){
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

	open (AQ,'>',$usrProfileDir.'/.quota.txt') or (Common::traceLog(Constants->CONST->{'FileCrtErr'} . $enPwdPath . "failed reason: $!") and die);# File handler AQ means Account Quota.
	chmod $filePermission,$usrProfileDir.'/.quota.txt';
	if ($accountQuota =~/\d+/ and $quotaUsed =~ /\d+/){
		$quotaUsed =~ s/(\d+)\".*/$1/isg;
		print AQ "totalQuota=$accountQuota\n";
		print AQ "usedQuota=$quotaUsed\n";
	}
	close AQ;
}

#****************************************************************************
#Subroutine Name         : getQuota
#Objective               : This function will create a quota.txt file based on the quota details which is received during  final backup.
#Usgae                   : getQuota()
#Added By                : Abhishek Verma.
# Modified By            : Senthil Pandian, Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************/
sub getQuota{
	my $csf = Common::getCachedStorageFile();
	unlink($csf);

	my @result;
 
    my $planSpecial = Common::getUserConfiguration('PLANSPECIAL');
    if($planSpecial ne '' and $planSpecial =~ /business/i) {
        # my $uname = Common::getUsername();
        # my $upswd = &Common::getPdata($uname);
        # my $encType = Common::getUserConfiguration('ENCRYPTIONTYPE');
        # my @responseData;
        # my $errStr = '';

        my $res = Common::makeRequest(12);
        if ($res) {
            @result = Common::parseEVSCmdOutput($res->{DATA}, 'login', 1);
        }
    } else {
		Common::createUTF8File('GETQUOTA') or Common::retreat('failed_to_create_utf8_file');
		@result = Common::runEVS('tree');
		if (exists $result[0]->{'message'}) {
			if ($result[0]->{'message'} eq 'ERROR') {
				Common::traceLog($result[0]->{'MSG'}) if(exists $result[0]->{'MSG'});
				Common::display('unable_to_retrieve_the_quota');
				return 0;
			}
		}
    }

	unless (@result) {
		Common::traceLog('unable_to_cache_the_quota',".");
		Common::display('unable_to_retrieve_the_quota');
		return 0;
	}

	if (exists $result[0]->{'message'} && $result[0]->{'message'} eq 'ERROR') {
		Common::checkAndUpdateAccStatError(Common::getUsername(), $result[0]->{'desc'});
		Common::traceLog('unable_to_cache_the_quota',". ".ucfirst($result[0]->{'desc'}));
		Common::display('unable_to_retrieve_the_quota');
		return 0;
	}

	if (Common::saveUserQuota(@result)) {
		return 1 if (Common::loadStorageSize());
	}

	Common::traceLog('unable_to_cache_the_quota');
	# Common::display('unable_to_cache_the_quota');
	return 0;
}

#*****************************************************************************************************
# Subroutine	: checkAndUpdateQuota
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Places getquota request if required
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub checkAndUpdateQuota {
	my $qtfile	= Common::getCachedStorageFile();
	if(!-f $qtfile || time() - stat($qtfile)->mtime >= $AppConfig::quotatimeout) {
		my $procid = fork();
		if($procid == 0) {
			getQuota();
			exit(0);
		}
	}

	return 0;
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
		open (AQ,'<',$quotaFileLoc) or (Common::traceLog(Constants->CONST->{'FileCrtErr'} . $enPwdPath . "failed reason: $!") and die); #File handler AQ means Account Quota;
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
	my $loginReq = 0;

	#checking if user is logged in
	if(-e $userTxt && -e $pwdPath && -s $pwdPath > 0) {
		my $userdata	= '';
		if(open USERFILE, "<", $userTxt) {
			$userdata	= <USERFILE>;
			close USERFILE;
			Chomp(\$userdata);
		}

		my %datahash = ($userdata =~ m/^\{/)? %{JSON::from_json($userdata)} : {$mcUser => $userdata};
		$loginReq = 1 if((!$datahash{$mcUser}{'isLoggedin'}) && ($datahash{$mcUser}{"userid"} eq $userName));
	}

	if($loginReq) {
		#displaying script header if passed
		$displayHeader->($0) if (defined ($displayHeader));
		print $lineFeed.Constants->CONST->{'PlLogin'}.$whiteSpace.qq{$appType}.$whiteSpace.Constants->CONST->{'AccLogin'}.$lineFeed.$lineFeed;
        Common::traceLog(Constants->CONST->{'PlLogin'} . " $appType " . Constants->CONST->{'AccLogin'});
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
		Common::display(["\n",'invalid_service_directory',"\n"]);
        #print Constants->CONST->{'loginConfigAgain'}.$lineFeed;
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
#Modified By			 : Senthil Pandian
#****************************************************************************/
sub writeParameterValuesToStatusFile
{
	($fileBackupCount,$fileRestoreCount,$fileSyncCount,$failedfiles_count,$deniedFilesCount,$missingCount,$modifiedFilesCount,$transferredFileSize,$exit_flag,$failedfiles_index,$operationEngineId) = @_;

	my @StatusFileFinalArray = ('COUNT_FILES_INDEX', 'SYNC_COUNT_FILES_INDEX', 'ERROR_COUNT_FILES', 'DENIED_COUNT_FILES', 'MISSED_FILES_COUNT', 'MODIFIED_FILES_COUNT', 'TOTAL_TRANSFERRED_SIZE');
	my ($Count, $Synccount, $Errorcount, $Deniedcount, $Missedcount, $ModifiedCount, $TransferredSize) = getParameterValueFromStatusFile($operationEngineId, \@StatusFileFinalArray);

	# Calculate the backup, sync and error count based on new values
	if($jobType eq "backup" || $jobType eq "localbackup") {
		$Count += $fileBackupCount;
	} else {
		$Count += $fileRestoreCount;
	}

	$Synccount   += $fileSyncCount;
	$Errorcount   = $failedfiles_count;
	$Deniedcount += $deniedFilesCount;
	$Missedcount += $missingCount;
    $ModifiedCount += $modifiedFilesCount;
	$TransferredSize += $transferredFileSize;

	$statusHash{'COUNT_FILES_INDEX'} = $Count;
	$statusHash{'SYNC_COUNT_FILES_INDEX'} = $Synccount;
	$statusHash{'ERROR_COUNT_FILES'} = $Errorcount;
	$statusHash{'FAILEDFILES_LISTIDX'} = $failedfiles_index;
	$statusHash{'EXIT_FLAG_INDEX'} = $exit_flag;
	$statusHash{'DENIED_COUNT_FILES'} = $Deniedcount;
	$statusHash{'MISSED_FILES_COUNT'} = $Missedcount;
    $statusHash{'MODIFIED_FILES_COUNT'} = $ModifiedCount;
	$statusHash{'TOTAL_TRANSFERRED_SIZE'} = $TransferredSize;
	putParameterValueInStatusFile($operationEngineId);
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
	$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
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
	$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
	my $commandOutput = qx{$idevsutilCommandLine};
	unlink($linkBucketUtfFile);

	if ($commandOutput =~ /status=["]success["]/i){
		#$' =~ /device_id="(.*?)".*?nick_name="(.*?)".*/;
		$' =~ /device_id="(.*?)".*?server_root="(.*?)".*?nick_name="(.*?)".*/;
		$deviceID   = $deviceIdPrefix.$1.$deviceIdPostfix;
		$backupHost = $restoreHost =  "$deviceID#$3";
		$serverRoot = $2;
		# BackupLocation = "DeviceID#Nickname" Eg: "D01500371120000812023#/dedup1
		if(defined($isSameDeviceID)){
			if($isSameDeviceID){
				putParameterValue("RESTOREFROM", $restoreHost);
			}
			putParameterValue("BACKUPLOCATION", $backupHost);
			putParameterValue("SERVERROOT", $serverRoot);
			Common::createBackupStatRenewalByJob('backup') if(Common::getUsername() ne '' && Common::getLoggedInUsername() eq Common::getUsername());
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
	my $ifConfigPathCmd = Common::updateLocaleCmd('which ifconfig 2>/dev/null');
	my $ifConfigPath = `$ifConfigPathCmd`;
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

	$cmd = Common::updateLocaleCmd($cmd);
	my $result = `$cmd`;
	my @macAddr = $result =~ /HWaddr [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		$macAddr[0] =~ s/HWaddr |:|-//g;
		return ($muid = ('Linux' . $macAddr[0]));
	}

	@macAddr = $result =~ /ether [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		$macAddr[0] =~ s/ether |:|-//g;
		return ($muid = ('Linux' . $macAddr[0]));
	}
	my $hostNameCmd = Common::updateLocaleCmd('hostname');
	my $hostName = `$hostNameCmd`;
	chomp($hostName);
	$result = 'Linux'.$hostName;
	return $result;
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
			my $locationQuery = qq{Your Backup Location is "$backupHost". Do you wish to modify (y/n)?};
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
# Modified By           : Senthil Pandian
#*********************************************************************************************************/
sub getBucketName{
	my $oldBackupLocName = shift;
	my $retryCount = 4;
	while($retryCount){
		#print $lineFeed.Constants->CONST->{'AskBackupLoc'}.': ';
		#print $lineFeed.Constants->CONST->{'AskBackupLoc'}.' '.Constants->CONST->{'BackupLocNoteDedup'}.': ';
		Common::display([$lineFeed,'enter_your_backup_location_optional',': ']);
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
	$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
	my $commandOutput = qx{$idevsutilCommandLine};
	unlink($createBucketUtfFile);

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
	$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
	my $commandOutput = qx{$idevsutilCommandLine};
	unlink($nickUpdateUtfFile);

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
		$idevsUtilCommand = Common::updateLocaleCmd($idevsUtilCommand);
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
			Common::traceLog(Constants->CONST->{'maxRetry'});
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
				$idevsUtilCommand = Common::updateLocaleCmd($idevsUtilCommand);
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
# Objective               : This function will check if restore/backup set file exists and filled. else report error & terminate
# Added By                : Abhishek Verma.
# Modified by             : Sabin Cheruvattil, Senthil Pandian
#**************************************************************************************************************************
sub checkPreReq {
	my ($fileName, $jobType, $taskType, $reason) = @_;
	my $isEmpty = 0;
	if((!-e $fileName) or (!-s $fileName)) {
		$isEmpty = 1;
	} elsif(-s $fileName > 0 && -s $fileName <= 50) {
		Common::traceLog(['failed_to_open_file',":$fileName, Reason:$!"]) if(!open(OUTFH, "< $fileName"));
		eval { close OUTFH; 1; };

		my $buffer = Common::getFileContents($fileName);
		Chomp(\$buffer);

		$isEmpty = 1 if($buffer eq '');
	}

	if($isEmpty) {
		$errStr = "Your $jobType"."set is empty. ".Constants->CONST->{pleaseUpdate}.$lineFeed; # Added by Abhishek Verma.
		#print $errStr if(lc($taskType) eq 'manual');
		#$errStr = '';
		# $subjectLine = "$taskType $jobType Status Report "."[$userName]"." [Failed $jobType]";
		# $status = "FAILURE";
		#sendMail($taskType,$jobType,$subjectLine,$reason,$fileName);
		#sendMail($subjectLine,$reason,$fileName);
		#rmtree($errorDir);
		#unlink $pidPath;
		#exit 1;
	}
	return $isEmpty;
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
	$idevsutilCommandLine = Common::updateLocaleCmd($idevsutilCommandLine);
	my $commandOutput = `$idevsutilCommandLine`;
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
    configAccount($pvt,$pvtPath) if($cnfgstat eq "NOT SET");
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
                        Common::traceLog("Failed to open $_[0], Reason:$!");
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
# Subroutine Name         : writeParamToFile.
# Objective               : This subroutine will write parameters into a file named operations.txt. Later it is used in Operations.pl script.
# Modified By             : Abhishek Verma, Sabin Cheruvattil
#*****************************************************************************************************/
sub writeParamToFile {
	my $fileName = $_[0];
	if (!open(PH, '>', $fileName)){ #PH means Parameter file handler.
		Common::traceLog("Failed to open $fileName, Reason:$!");
		print "Failed to open $fileName, Reason:$! $lineFeed";
		cancelProcess();
	}

	print PH $_[1];
	close (PH);

	chmod $filePermission, $fileName;
}
#****************************************************************************************************
# Subroutine Name         : writeParamToFile.
# Objective               : This subroutine will write parameters into a file named operations.txt. Later it is used in Operations.pl script.
# Modified By             : Abhishek Verma.
#*****************************************************************************************************/
sub convertToBytes{
	my $dataTransferedInBytes;
    
 	if ($_[0] =~ /(.*?)byte/i){
		$dataTransferedInBytes = $1;
	}elsif($_[0] =~ /(.*?)KB/i){
		$dataTransferedInBytes = $1*1024;
	}elsif($_[0] =~ /(.*?)MB/i){
		$dataTransferedInBytes = $1*1024*1024;
	}elsif($_[0] =~ /(.*?)GB/i){
		$dataTransferedInBytes = $1*1024*1024*1024;
	}elsif($_[0] =~ /(.*?)TB/i){
		$dataTransferedInBytes = $1*1024*1024*1024*1024;
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
	my $whichCurlCmd = Common::updateLocaleCmd('which curl 2>/dev/null');
	my $curl = `$whichCurlCmd`;
	chomp($curl);

	if($proxyOn eq 1) {
		$curlCmd = "$curl --max-time 15 -x http://$proxyIp:$proxyPort --proxy-user $proxyUsername:$proxyPassword -L -s -k -d '$data' '$PATH'";
	} else {
		$curlCmd = "$curl --max-time 15 -s -k -d '$data' '$PATH'";
	}

	$curlCmd = Common::updateLocaleCmd($curlCmd);
	my $res = `$curlCmd`;
	if ($res =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
		Common::traceLog("Failed get curl Output: $res");
		undef $userName;
		return 0;
	}
	return $res;
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
			Common::traceLog("Not able to open $freshInstallFile, Reason:$!");
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

#*************************************************************************************************
#Subroutine Name               : whichPackage
#Objective                     : This subroutine will give you the path of given command.
#Usage                         : whichPackage()
#Added By                      : Abhishek Verma
#*************************************************************************************************/
sub whichPackage{
	my $pckg = ${$_[0]};
	my $pckgPathCmd = Common::updateLocaleCmd('which $pckg 2>/dev/null');
	my $pckgPath = `$pckgPathCmd`;
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
	my $pwdCmd = Common::updateLocaleCmd('pwd');
	$currDirLocal = `$pwdCmd`;
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
	my $machineInfoCmd = Common::updateLocaleCmd('uname -a');
	$machineInfo = `$machineInfoCmd`;
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
		$res = system(Common::updateLocaleCmd("mv $crontabFilePath $crontabFilePath_bak 2>/dev/null"));
		if($res ne "0") {
			Common::traceLog("Unable to move crontab link file");
			$retVal = 0;
		} elsif(open CRONTABFILE, ">", $crontabFilePath){
			close CRONTABFILE;
			chmod 0644, $crontabFilePath;
		} else {
			Common::traceLog("Couldn't open file $crontabFilePath");
			$retVal = 0;
		}
	} elsif(-f $crontabFilePath) {
		if(open CRONTABFILE, "<", $crontabFilePath){
			@linesCrontab = <CRONTABFILE>;
			close CRONTABFILE;
		} else {
			Common::traceLog("Couldn't open file $crontabFilePath");
			$retVal = 0;
		}
	}
	return $retVal;
}

#****************************************************************************************************
# Subroutine		: appendExcludedLogFileContents
# Objective			: This subroutine appends the contents of the excluded log file to the output file
# Modified By		: Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub appendExcludedLogFileContents {
    my $jtempJobRunningDir = $jobRunningDir;
    $jtempJobRunningDir = Common::getJobsPath('backup', 'path') if($jtempJobRunningDir =~ /CDP/); #Added to append exclude message for CDP
	return Common::appendExcludedLogFileContents(Common::getCatfile($jtempJobRunningDir, "/"));
}

#****************************************************************************************************
# Subroutine Name         : checkAndLinkBucketSilently
# Objective               : This subroutine will link the bucket silently if machine's UID having '_1'
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub checkAndLinkBucketSilently
{
	my $actualDeviceID;
	my $backupLoc = Common::getUserConfiguration('BACKUPLOCATION');
	my $restoreFrom = Common::getUserConfiguration('RESTOREFROM');
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
				putParameterValue("RESTOREFROM", $restoreHost);
			}
			putParameterValue("BACKUPLOCATION", $backupHost);
			Common::createBackupStatRenewalByJob('backup') if(Common::getUsername() ne '' && Common::getLoggedInUsername() eq Common::getUsername());
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


sub isEngineRunning {
	my ($enginePidPath) = @_;
	my $fh = '';
	if(!-e $enginePidPath){
		return 0;
	}

	open($fh, ">", $enginePidPath) or return 1;
	if(flock($fh, LOCK_EX|LOCK_NB)){
		flock($fh, LOCK_UN);
		close $fh;
		return 0;
	}

	close $fh;
	return 1;
}


sub isAnyEngineRunning
{
	my ($engineLockFile) = @_;
	open(my $handle, ">>", $engineLockFile) or return 0;
	if(!flock($handle, LOCK_EX|LOCK_NB)){
		close $handle;
		return 1;
	}
	flock($handle, LOCK_UN);
	close $handle;
	return 0;
}

#*****************************************************************************************************
# Subroutine			: calculateProgress
# Objective				: Calculates and aggregates progress data
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub calculateProgress {
	my (@progressDataHash, @progressDataFileDisplayHash, @individualProgressData);
	my $count		= 1;
	my $progdetfp	= $_[0];
	my $jobdir		= (fileparse($progdetfp))[1];
	my $statusFile	= "$jobdir/STATUS_FILE";
	my $pidFile		= "$jobdir/pid.txt";
	my $infoFile	= Common::getECatfile($jobdir, 'info_file');
	$progressDataHash[3] = 0;

	for(my $i = 1; $i <= $totalEngineBackup; $i++) {
		my $tempProgressFile = $progdetfp."_$i";
		my $tempStatusFile = $statusFile."_$i";
		if(-e $tempProgressFile and -s $tempProgressFile > 0) {
			if(open(progressDetails, "<", $tempProgressFile)) {
				chomp(my @progressDetailsFileData = <progressDetails>);
				close progressDetails;

				$type = $progressDetailsFileData[0];
				chomp($type);

				$trnsFileSize = $progressDetailsFileData[1];
				chomp($trnsFileSize);

				$fileName = $progressDetailsFileData[5];
				chomp($fileName);

				my $dataTransRate = $progressDetailsFileData[4];
				chomp($dataTransRate);

				$fileName =~ s/^\s*(.*?)\s*$/$1/; # Added to remove spaces from both side

				if($fileName ne ""){
					$progressDataFileDisplayHash[$i] = "[$type] [$fileName][$trnsFileSize]";
					$individualProgressData[$i]{'data'} = "[$type] [$fileName][$trnsFileSize][".convertFileSize($dataTransRate)."/s]";
					$individualProgressData[$i]{'per'} = $progressDetailsFileData[7];
				}

				$progressDataHash[0] += $progressDetailsFileData[2];
				$progressDataHash[1]  = $progressDetailsFileData[3];
				$progressDataHash[2] += $dataTransRate;
				$progressDataHash[3] += int($progressDetailsFileData[8]) if(-f $pidFile);
				$count++;
			}
		}
	}

	unless (-f $pidFile) {
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX', 'SYNC_COUNT_FILES_INDEX', 'ERROR_COUNT_FILES', 'DENIED_COUNT_FILES', 'MISSED_FILES_COUNT');
		my ($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
		$progressDataHash[3] += ($successFiles+$syncedFiles+$failedFilesCount+$noPermissionCount+$missingCount);
		if(-f $infoFile){
			my $syncCountCmd = "tail -10 '$infoFile' | grep \"^READYSYNC\"";
			$syncCountCmd = Common::updateLocaleCmd($syncCountCmd);
			my $syncCount = `$syncCountCmd`;
			$syncCount =~ s/READYSYNC//;
			Common::Chomp(\$syncCount);
			$progressDataHash[3] += $syncCount if($syncCount =~ /^\d+$/);
		}
	}

	# if($count > 1 and (defined($_[1]) and $_[1] ne 'paused')){
		# $cumulativeCount++;
		# $cumulativeTransRate += $progressDataHash[2];
		# $progressDataHash[2] = ($cumulativeTransRate/$cumulativeCount);
	# }

	return (\@progressDataHash,\@progressDataFileDisplayHash,\@individualProgressData);
}

sub get_load_average {
	my $cmd = "uname";
	my $load_avg;
	my ( @one_min_avg );
	$cmd = Common::updateLocaleCmd($cmd);
	chomp(my $OS = `$cmd`);
	$OS = lc $OS;
	if($OS ne "freebsd"){
		open(LOAD, "/proc/loadavg") or die "Unable to get server load \n";
		$load_avg = <LOAD>;
		close LOAD;
		my ( @one_min_avg ) = split /\s/, $load_avg;
		return (sprintf '%.2f', $one_min_avg[1]);
	}else{
		my $load_avg_data = 'uptime | awk \'{print $(NF-2)" "$(NF-1)" "$(NF-0)}\' | tr "," " "\'\'';
		$load_avg_data = Common::updateLocaleCmd($load_avg_data);
		$load_avg = `$load_avg_data`;
		chomp($load_avg);
		my ( @one_min_avg ) = split /\s/, $load_avg;
		return (sprintf '%.2f', $one_min_avg[2]);
	}
}


sub getSystemCpuCores{
    my $cmd = "uname";
	$cmd = Common::updateLocaleCmd($cmd);
	chomp(my $OS = `$cmd`);
	$OS = lc $OS;
	my $retVal = 2;
	my ($cmdCpuCores,$totalCores);
	if($OS eq "freebsd"){
	  my $totalCoresCmd = Common::updateLocaleCmd("sysctl -a | grep 'hw.ncpu' | cut -d ':' -f2");
	  $totalCores = `$totalCoresCmd`;
	  chomp($totalCores);
	  $totalCores = int($totalCores);
	  $retVal = ($totalCores == 1 ? 2 : ($totalCores == 2 ? 4 : $totalCores));
    }
	elsif($OS eq "linux"){
	  my $cpuProcessorCountCmd = Common::updateLocaleCmd("cat /proc/cpuinfo | grep processor | wc -l");
	  my $cpuProcessorCount = `$cpuProcessorCountCmd`;
	  chomp($cpuProcessorCount);
	  my $cmdCpuCoresCmd = Common::updateLocaleCmd("grep 'cpu cores' /proc/cpuinfo | tail -1 | cut -d ':' -f2");
	  $cmdCpuCores = `$cmdCpuCoresCmd`;
	  chomp($cmdCpuCores);

	  $cmdCpuCores = ($cmdCpuCores ne "" ? int($cmdCpuCores) : 1);
	  $cpuProcessorCount = ($cpuProcessorCount ne "" ? int($cpuProcessorCount) : 1);

	  $totalCores = $cpuProcessorCount*$cmdCpuCores;
	  $retVal = ($totalCores == 1 ? 2 : ($totalCores == 2 ? 4 : $totalCores));
	}

	return $retVal;
}

#****************************************************************************************************
# Subroutine Name         : clearProgressScreen
# Objective               : This subroutine will clear the progress screen
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub clearProgressScreen
{
	$freebsdProgress = '';
	my $latestCulmnCmd = Common::updateLocaleCmd('tput cols');
	$latestCulmn = `$latestCulmnCmd`;
	my $lineCount = 40;
	my $totalLinesCmd = Common::updateLocaleCmd('tput lines');
	my $totalLines = `$totalLinesCmd`;
	chomp($totalLines) if($totalLines);
	$lineCount = $totalLines if($totalLines);
	for(my $i=0; $i<=$lineCount; $i++){
		$freebsdProgress .= (' ')x$latestCulmn;
		$freebsdProgress .= "\n";
	}
	print $freebsdProgress;
}
1;
