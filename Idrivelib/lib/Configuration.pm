#*****************************************************************************************************
# App configurations
#
# Created By : Yogesh Kumar @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#*****************************************************************************************************

package Configuration;
use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')); } else { use lib '.'; }

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(TRUE FALSE STATUS SUCCESS FAILURE);

use IxHash;

our $version         	= '2.24';
our $releasedate     	= '01-10-2020';
our $appType         	= 'IDrive';
our $servicePathName    = lc($appType).'It';
our $oldServicePathName = lc($appType);

our $language          = 'EN';       # EN-ENGLISH
our $staticPerlVersion = '1.3';
our $appCron = lc($appType).'cron';

use constant {
	SUCCESS  => 'SUCCESS',
	FAILURE  => 'FAILURE',
	STATUS   => 'STATUS',
	MSG      => 'MSG',
	DATA     => 'DATA',
	TRUE     => 1,
	FALSE    => 0,
	ONEWEEK  => 7,
	TWOWEEK  => 14,
	ONEMONTH => 30,
};

our $debug = 0;

our $displayHeader = 1;

our $hostname = `hostname`;
chomp($hostname);
our $mcUser = `whoami`;
chomp($mcUser);
our $rootAuth = '';
our $kver = `uname -r`;
chomp($kver);
if ($kver ne '') {
	$kver = substr($kver, 0, 1);
	if ($kver > 2) {
		$kver = 'k3';
	}
	else {
		$kver = 'k2';
	}
}
else {
	$kver = 'k3';
}

our $callerEnv = 'INTERACTIVE';

our $evsBinaryName        = 'idevsutil';
our $evsDedupBinaryName   = 'idevsutil_dedup';
our $staticPerlBinaryName = 'perl';
our $rRetryTimes          = 2;                   # Request retry for 2 more times(total 3).
our $perlBin              = `which perl`;
chomp($perlBin);
if (exists $ENV{'_'} and $ENV{'_'} and not ($ENV{'_'} =~ m/$servicePathName\/$staticPerlBinaryName/)) {
	$perlBin = $ENV{'_'};
}
if ($perlBin =~ /\.pl$/) {
	$perlBin = `which perl`;
	chomp($perlBin);
	$perlBin = '/usr/bin/perl' unless($perlBin);
}

our $errorMsg           = '';
our $utf8File           = 'utf8.cmd';
our $idriveLibPath      = 'Idrivelib/lib';
our $idriveDepPath      = 'Idrivelib/dependencies';
our $cronSetupPath      = 'Idrivelib/cronsetup';
our $defaultMountPath   = '/tmp';

chomp(our $machineOS = `uname -msr`);
our $freebsdProgress;
our $deviceType      = 'LINUX';
our $evsVersion      = 'evs005';
our $NSPort          = 443;
our $idriveLoginCGI  = 'https://tomcat.idrive.com/idrive/viewjsp/RemoteLogin.jsp';

our $deviceUIDPrefix= 'Linux';
our $deviceIDPrefix = '5c0b';
our $deviceIDSuffix = '4b5z';

our @dependencyBinaries = ('unzip', 'curl');

our $serviceLocationFile = '.serviceLocation';
our $updateVersionInfo   = '.updateVersionInfo';
our $forceUpdateFile     = '.forceupdate';

our $cachedFile            = 'cache/user.txt';
our $cachedIdriveFile      = 'cache/'.lc($appType).'user.txt';
our $userProfilePath       = 'user_profile';
our $userInfoPath          = '.userInfo';
our $idpwdFile             = "$userInfoPath/IDPWD";
our $idenpwdFile           = "$userInfoPath/IDENPWD";
our $idpwdschFile          = "$userInfoPath/IDPWD_SCH";
our $idpvtFile             = "$userInfoPath/IDPVT";
our $idpvtschFile          = "$userInfoPath/IDPVT_SCH";
our $serverAddressFile     = "$userInfoPath/serverAddress.txt";
our $validateRestoreFromFile = "validateRestoreFromFile.txt";
our $userConfigurationFile = 'CONFIGURATION_FILE';
our $quotaFile             = '.quota.txt';
our $downloadsPath         = 'downloads';
our $tmpPath               = 'tmp';
our $logDir                = 'LOGS';
our $traceLogDir           = '.trace';
our $traceLogFile          = 'traceLog.txt';
our $propsettingsFile      = 'propsettings.json';
our $masterPropsettingsFile= 'masterpropsettings.json';
our $utilityRequestFile    = 'utilityRequestFile.json';

our $maxLogSize            = 2 * 1024 * 1024;
our $maxChoiceRetry        = 3;
our $reportMaxMsgLength    = 4095;
our $bufferLimit           = 2*1024;

our $minEngineCount = 2;
our $maxEngineCount = 4;

our $fullExcludeListFile    = 'FullExcludeList.txt';
our $partialExcludeListFile = 'PartialExcludeList.txt';
our $regexExcludeListFile   = 'RegexExcludeList.txt';

our $searchDir          = 'Search';
our $evsOutputFile      = 'evsOutput.txt';
our $evsErrorFile       = 'evsError.txt';
our $versionRestoreFile = 'versionRestoresetFile.txt';

our $unzipLog     = 'unzipLog.txt';
our $updateLog    = '.updateLog.txt';
our $updatePid    = 'update.pid';
our $freshInstall = 'freshInstall';

our $isUserConfigModified = 0;
our $backupsetFile        = 'BackupsetFile.txt';
our $tempBackupsetFile    = 'tempBackupsetFile.txt';

our $restoresetFile        = 'RestoresetFile.txt';

our $archiveFileListForView  = 'archiveFileListForView.txt';
our $archiveFileResultFile   = 'archiveFileResult.txt';
our $archiveFolderResultFile = 'archiveFolderResult.txt';

our $alertStatusFile = 'alert.status';

our $cancelFile      = 'exitError.txt';
our $exitErrorFile   = 'exitError.txt';
our $errorFile       = 'error.txt';
our $evsTempDir      = 'evs_temp';
our $statusFile      = 'STATUS_FILE';
our $infoFile        = 'info_file';
our $fileForSize     = 'TotalSizeFile';
our $excludeDir      = 'Excluded';
our $errorDir        = 'ERROR';
our $pidFile         = 'pid.txt';
our $logPidFile      = 'LOGPID';
our $excludedLogFile = 'excludedItemsLog.txt';
our $mountPointFile  = 'mountPoint.txt';
our $trfSizeAndCountFile = 'trfSizeAndCount.txt';
our $progressDetailsFilePath = 'PROGRESS_DETAILS';
our $retryInfo = "RetryInfo.txt";
our $failedFileName = "failedFiles.txt";
our $relativeFileset = "BackupsetFile_Rel";
our $filesOnly = "BackupsetFile_filesOnly";
our $noRelativeFileset = "BackupsetFile_NoRel";
our $transferredFileSize = 'transferredFileSize.txt';
our $operationsfile  = 'operationsfile.txt';
our $fileSummaryFile = 'fileSummary.txt';
our $permissionErrorFile = 'permissionError.txt',
our $minimalErrorRetry = 'errorretry.min';
our $pidOperationFlag  =  'main';
our $pidOutputProcess = undef;
our $status = "Success";
our $opStatus = "Success";
our $dbPathsXML = 'dbpaths.xml';
our $dbMapFile = 'DB.map';
our $expressDbDir = 'ExpressDB';
our ($jobRunningDir,$outputFilePath,$errorFilePath,$mailContentHead) = ('') x 4;
our ($mailContent,$jobType,$expressLocalDir,$errStr,$finalSummary) = ('') x 5;
our ($fullStr,$parStr,$regexStr) = ('') x 3;
our ($excludedCount,$noRelIndex,$excludedFileIndex,$filesonlycount,$retryCount,$cancelFlag) = (0) x 6;
our ($totalFiles,$fileCount,$nonExistsCount,$noPermissionCount,$missingCount) = (0) x 5;
our ($localMountPath,$encType,$hashVal) = ('') x 3;
our $progressSizeOp = 1;

our @linesStatusFile = undef;

our $filePermission    = 0777;
our $execPermission    = 0755;
our $filePermissionStr = "0777";
our $prevTime = time();

our $inputMandetory = 1;

our $accessTokenFile = 'accesstoken.txt';
our $notificationFile = 'notification.json';
our $nsFile = 'ns.json';

our $logStatFile = "%02d%04dlogstat\.json";

our $crontabFile    = lc($appType).'crontab.json';
our $cronlockFile   = '/var/run/'.lc($appType).'cron.lock';
our $cronservicepid = '/var/run/'.lc($appType).'cron.pid';
our $cronLinkPath   = '/etc/'.lc($appType).'cron.pl';

our $migUserlock  = 'migrate.lock';
our $migUserSuccess = 'migrateSuccess';
our $migratedLogFileList = 'migratedLogFileList.txt';
our $backupsizefile = 'backupsetsize.json';
our $backupsizelock = 'backupsetsize.lock';
our $backupsizesynclock = 'backupsetsizesync.lock';
our $sfmaxcachets   = 7200; # 2 hrs | time in seconds | size json file
our $sizepollintvl  = 5; #120;
our $tempVar        = '';
our $expressDBMapFile = 'DB.map';
our $ldbNew			  = 'LDBNEW';

# dashboard lock
our $dashboardpid = 'dashboard.pid';
our $dashbtask    = 'dashboard';

our %userProfilePaths = (
	'archive'     => 'Archive/DefaultBackupSet',
	'backup'      => 'Backup/DefaultBackupSet',
	'localbackup' => 'Backup/LocalBackupSet',
	'restore'     => 'Restore/DefaultRestoreSet',
	'user_info'   => '.userInfo',
	'restore_data'=> 'Restore_Data',
	'trace'       => '.trace',
	'tmp'         => 'tmp',
);

our %jobDir = (
	'default_backupset'  => 'DefaultBackupSet',
	'local_backupset' 	 => 'LocalBackupSet',
	'default_restoreset' => 'DefaultRestoreSet',
);

our %fileSizeDetail = (
	'bytes' => 'bytes',
	'kb'    => 'KB',
	'mb'    => 'MB',
	'gb'    => 'GB',
	'tb'    => 'TB',
);

our $screenSize = '';
$screenSize     = `stty size` if (-t STDIN);

our $userConfChanged = 0;
our $tab = "      ";

our $proxyNetworkError = "failed to connect|Connection refused|Could not resolve proxy|Could not resolve host|No route to host|HTTP code 407|URL returned error: 407|407 Proxy Authentication Required|Connection timed out|response code said error|kindly_verify_ur_proxy";

#############Multiple Engine#############
our $totalEngineBackup = 4;
use constant ENGINE_LOCKE_FILE => "engine.lock";
#############Multiple Engine#############

#our $evsDownloadsPage = "https://www.__APPTYPE__.com/downloads/linux/download-options__EVSTYPE__";
our $evsDownloadsPage = "https://www.__APPTYPE__.com/downloads/linux/download-options";
#our $evsDownloadsPage = " -u deepak:deepak http://192.168.3.169/svn/linux_repository/trunk/PackagesForTesting/IDriveForLinux/binaries";
our $IDriveUsersCGI   = "https://www1.idrive.com/cgi-bin/v1/user-list.cgi";
our $IBackupUsersCGI  = "http://www1.ibackup.com/cgi-bin/ibackup_get_email_ibsync_user_v1.cgi";
our $IDriveAuthCGI  = "https://www1.idrive.com/cgi-bin/v1/user-details.cgi";
our $IBackupAuthCGI = "https://www1.ibackup.com/cgi-bin/get_ibwin_evs_details_xml_ip.cgi?";
our $IDriveErrorCGI = 'https://webdav.ibackup.com/cgi-bin/Notify_unicode';

# Software Update CGI
my $trimmedVersion = $version;
my @matches = split('\.', $trimmedVersion);
if (scalar(@matches) > 2) {
	$trimmedVersion = $matches[0].".".$matches[1];
}
our $checkUpdateBaseCGI = "https://www1.ibackup.com/cgi-bin/check_version_upgrades_idrive_evs_new.cgi?'appln=${appType}ForLinux&version=$trimmedVersion'";

our $IDriveBKPSummaryCGI = 'https://www1.idrive.com/cgi-bin/idrive_backup_summary.cgi';
our $IDriveSupportEmail = 'support@'.lc($appType).'.com';
our $notifyPath = 'https://webdav.ibackup.com/cgi-bin/Notify_email_ibl';

# production download URL
my $IDriveAppUrl = "https://www.idrivedownloads.com/downloads/linux/download-for-linux/IDriveForLinux.zip";
# SVN download URL
#my $IDriveAppUrl = " -u deepak:deepak http://192.168.3.169/svn/linux_repository/trunk/PackagesForTesting/IDriveForLinux/IDriveForLinux.zip";

# production download URL
my $IBackupAppUrl = "https://www.ibackup.com/online-backup-linux/downloads/download-for-linux/IBackup_for_Linux.zip";
# SVN download URL
#my $IBackupAppUrl = " -u deepak:deepak http://192.168.3.169/svn/linux_repository/trunk/PackagesForTesting/IBackupForLinux/IBackup_for_Linux.zip";
my $IDriveUserInoCGIUrl = "https://www1.idrive.com/cgi-bin/update_user_device_info.cgi?";
my $IBackupUserInoCGIUrl = "https://www1.ibackup.com/cgi-bin/update_user_device_info.cgi?";
our $accountSignupURL = "https://www.ibackup.com/newibackup/signup";
$accountSignupURL = "https://www.idrive.com/idrive/signup" if($appType eq 'IDrive');

our $appDownloadURL = ($appType eq 'IDrive')? $IDriveAppUrl : $IBackupAppUrl;
our $appPackageName = ($appType eq 'IDrive')?'IDriveForLinux':'IBackup_for_Linux';
our $appPackageExt  = '.zip';
our $IDriveUserInoCGI  =  ($appType eq 'IDrive')? $IDriveUserInoCGIUrl : $IBackupUserInoCGIUrl;

our %evsZipFiles = (
	'IDrive' => {
		'32' => ['__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip'],
		'64' => ['__APPTYPE___linux_64bit.zip', '__APPTYPE___QNAP_64bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___synology_aarch64bit.zip', '__APPTYPE___Netgear_64bit.zip', '__APPTYPE___Vault_64bit.zip', '__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip'],
		'freebsd' => ['__APPTYPE___Vault_64bit.zip'],
		'arm' => ['__APPTYPE___QNAP_ARM.zip', '__APPTYPE___synology_ARM.zip',
							'__APPTYPE___Netgear_ARM.zip', '__APPTYPE___synology_Alpine.zip'],
		'x' => ['__APPTYPE___linux_universal.zip'],
	},
	'IBackup' => {
		'32' => ['__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___Netgear_64bit.zip', '__APPTYPE___Vault_64bit.zip'],
		'64' => ['__APPTYPE___linux_64bit.zip', '__APPTYPE___QNAP_64bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___Netgear_64bit.zip', '__APPTYPE___Vault_64bit.zip', '__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip'],
		'freebsd' => ['__APPTYPE___Vault_64bit.zip'],
		'arm' => ['__APPTYPE___QNAP_ARM.zip', '__APPTYPE___synology_ARM.zip',
							'__APPTYPE___Netgear_ARM.zip', '__APPTYPE___synology_Alpine.zip'],
		'x' => ['__APPTYPE___linux_universal.zip'],
	},
);

our %staticperlZipFiles = (
	'32' => ['idrive_perl/__KVER__/x86.zip'],
	'64' => ['idrive_perl/__KVER__/x86_64.zip'],
	'freebsd' => ['idrive_perl/freebsd.zip'],
);

our %evsAPI = (
	'IDrive' => {
		'getServerAddress' => 'https://evs.idrive.com/evs/getServerAddress',
		'configureAccount' => 'https://EVSSERVERADDRESS/evs/configureAccount',
		'getAccountQuota'  => 'https://EVSSERVERADDRESS/evs/getAccountQuota',
	},
	'IBackup' => {
		'getServerAddress' => 'https://evs.ibackup.com/evs/getServerAddress',
		'configureAccount' => 'https://EVSSERVERADDRESS/evs/configureAccount',
		'getAccountQuota' => 'https://EVSSERVERADDRESS/evs/getAccountQuota',
	},
);

# We know that 32 bit works on 64 bit machines, so we give it a try
# when 64 bit binaries fails to work on the same machine.
#$evsZipFiles{'64'} = [@{$evsZipFiles{'64'}}, @{$evsZipFiles{'32'}}];

tie (our %availableJobsSchema, 'Tie::IxHash',
	backup => {
		path => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'backup'}/",
		logs => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'backup'}/$logDir",
		file => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'backup'}/$backupsetFile",
		type => 'backup',
		runas => ['SCHEDULED', 'immediate'],
		croncmd => "%s %s %s", # Script name & username
	},
	restore => {
		path => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'restore'}/",
		logs => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'restore'}/$logDir",
		file => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'restore'}/$restoresetFile",
		type => 'restore',
		runas => [],
		croncmd => "",
	},
	localbackup => {
		path => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'localbackup'}/",
		logs => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'localbackup'}/$logDir",
		file => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'localbackup'}/$backupsetFile",
		type => 'backup',
		runas => ['SCHEDULED', 'immediate'],
		croncmd => "%s SCHEDULED %s", # Script name & username
	},
	archive => {
		path => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'archive'}/",
		logs => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'archive'}/$logDir",
		file => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'archive'}/$backupsetFile",
		type => 'archive',
		runas => [],
		croncmd => "%s %s %s %s %s", # script name, username, percentage, days & timestamp
	}
);

use constant JOBEXITCODE => {
	'SUCCESS' => 'Success',
	'SUCCESS*' => 'Success*',
	'FAILURE' => 'Failure',
	'ABORTED' => 'Aborted',
	'RUNNING' => 'Running',
};

tie (our %logMenuAndPaths, 'Tie::IxHash',
	'backup'      => 'backup_logs',
	'localbackup' => 'express_backup_logs',
	'restore'     => 'restore_logs',
	'archive'     => 'archive_cleanup_logs',
);

tie (our %excludeFilesSchema, 'Tie::IxHash',
	'full_exclude' => {
		'file' => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$fullExcludeListFile",
		'title' => "Full Path Exclude List",
	},
	'partial_exclude' => {
		'file' => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$partialExcludeListFile",
		'title' => "Partial Path Exclude List",
	},
	'regex_exclude' => {
		'file' => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$regexExcludeListFile",
		'title' => "Regex Exclude List",
	},
);

our %evsAPIPatterns = (
	'GETQUOTA'         => "--get-quota\n__getUsername__\@__getServerAddress__::home/",
	'STRINGENCODE'     => "--string-encode=__ARG1__\n--out-file=__ARG2__",
	'VALIDATE'         => "--validate\n--user=__ARG1__\n--password-file=__ARG2__",
	'GETSERVERADDRESS' => "--getServerAddress\n__getUsername__",
	'CREATEBUCKET'     => "--xml-output\n--create-bucket\n--nick-name=__ARG1__\n--os=Linux\n--uid=__getMachineUID__\n--bucket-type=D\n--location=__getMachineUser__\n__getUsername__\@__getServerAddress__::home/",
	'CREATEDIR'        => "--xml-output\n--create-dir=__ARG1__\n__getUsername__\@__getServerAddress__::home/",
	'LISTDEVICE'       => "--xml-output\n--list-device\n__getUsername__\@__getServerAddress__::home/",
	'NICKUPDATE'       => "--xml-output\n--nick-update\n--nick-name=__ARG1__\n--os=Linux\n--device-id=__ARG2__\n--location=__getMachineUser__\n__getUsername__\@__getServerAddress__::home/",
	'LINKBUCKET'       => "--xml-output\n--link-bucket\n--nick-name=__ARG1__\n--os=Linux\n__getUsername__\@__getServerAddress__::home/\n--device-id=$deviceIDPrefix\__ARG2__$deviceIDSuffix\n--uid=__ARG3__\n--bucket-type=D\n--location=__getMachineUser__",
	'DEFAULTCONFIG'    => "--config-account\n--user=__getUsername__\n--enc-type=DEFAULT",
	'PRIVATECONFIG'    => "--config-account\n--user=__getUsername__\n--enc-type=PRIVATE",
	'PING'             => "__getUsername__\@__getServerAddress__::home/",
	'FILEVERSION'      => "--version-info\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG1__",
	'SEARCH'           => "--search\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'SEARCHALL'        => "--search\n--all\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'ITEMSTATUS'       => "--items-status\n--files-from=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/",
	'PROPERTIES'       => "--properties\n--e=__ARG1__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG2__",
	'DELETE'           => "--delete-items\n--files-from=__ARG1__\n--o=__ARG2__\n--e=__ARG3__\n--xml-output\n__getUsername__\@__getServerAddress__::home/",
	'AUTHLIST'         => "--auth-list\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'EXPRESSBACKUP'    => "--files-from=__ARG1__\n--bw-file=__ARG2__\n--type\n--def-local=__ARG3__\n--add-progress\n--temp=__ARG4__\n--xml-output\n--enc-opt\n__ARG5__\n--portable\n--no-versions\n--o=__ARG6__\n--e=__ARG7__\n--portable-dest=__ARG8__\n__ARG9__\n__getUsername__\@__getServerAddress__::home/__ARG10__",
	'BACKUP'           => "--files-from=__ARG1__\n--bw-file=__ARG2__\n--type\n--add-progress\n--100percent-progress\n--temp=__ARG3__\n--xml-output\n--o=__ARG4__\n--e=__ARG5__\n__ARG6__\n__getUsername__\@__getServerAddress__::home/__ARG7__",
	'LOGBACKUP'        => "--files-from=__ARG1__\n--xml-output\n--backup-log\n--no-relative\n--temp=__ARG2__\n--o=__ARG3__\n--e=__ARG4__\n/\n__getUsername__\@__getServerAddress__::home/--ILD--/$hostname/log/",
);

tie(our %userConfigurationSchema, 'Tie::IxHash',
	USERNAME => {
		cgi_name => '',
		evs_name => '',
		required => 100,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	EMAILADDRESS => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	BACKUPLOCATION => {
		cgi_name => '',
		evs_name => '',
		required => 101,
		default  => '',
		type => 'regex',
		for_dashboard => 1,
	},
	'MUID' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
		'for_dashboard' => 0,
	},
	RESTOREFROM => {
		cgi_name => '',
		evs_name => '',
		required => 101,
		default  => '',
		type => 'regex',
		for_dashboard => 1,
	},
	RESTORELOCATION => {
		cgi_name => '',
		evs_name => '',
		required => 101,
		default  => '',
		type => 'regex',   # to avoid restore directory exist validation for now
		for_dashboard => 1,
	},
	RESTORELOCATIONPROMPT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 1,
		type => 'regex',
		for_dashboard => 1,
	},
	NOTIFYSOFTWAREUPDATE => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type => 'regex',
		for_dashboard => 1,
	},
	PROXYIP => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	PROXYPORT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	PROXYUSERNAME => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	PROXYPASSWORD => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	PROXY => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	BWTHROTTLE => {
		cgi_name => '',
		evs_name => '',
		required => 1000,
		default  => 100,
		type => 'regex',
		regex => '^(?:[1-9]\d?|100)$',
		for_dashboard => 1,
	},
	BACKUPTYPE => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 'mirror',
		type => 'regex',
		for_dashboard => 1,
	},
	DEDUP => {
		cgi_name => 'dedup',
		evs_name => 'dedup',
		required => 100,
		default  => '',
		type => 'regex',
		for_dashboard => 1,
	},
	ENCRYPTIONTYPE => {
		cgi_name => 'enctype',
		evs_name => 'configtype',
		required => 100,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	USERCONFSTAT => {
		cgi_name => 'cnfgstat',
		evs_name => 'configstatus',
		required => 100,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	SERVERROOT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	PLANTYPE => {
		cgi_name => 'plan_type',
		evs_name => '',
		required => 100,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	PLANSPECIAL => {
		cgi_name => 'plan_special',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	RMWS => {
		cgi_name => 'remote_manage_websock_server',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	RMI => {
		cgi_name => 'remote_manage_ip',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	RMS => {
		cgi_name => 'remote_manage_server',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	RMIH => {
		cgi_name => 'remote_manage_ip_https',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	RMSH => {
		cgi_name => 'remote_manage_server_https',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	ADDITIONALACCOUNT => {
		cgi_name => 'addtl_account',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	PRMI => {
		cgi_name => 'parent_remote_manage_ip',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	PRMS => {
		cgi_name => 'parent_remote_manage_server',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	PRMIH => {
		cgi_name => 'parent_remote_manage_ip_https',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	PRMSH => {
		cgi_name => 'parent_remote_manage_server_https',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	PARENTACCOUNT => {
		cgi_name => 'parent_account',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	LOCALMOUNTPOINT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 1,
	},
	# Notify as Failure if the total files failed for backup is more than
	# % of the total files backed up
	NFB => {
		cgi_name => '',
		evs_name => '',
		required => 1001,
		default  => 5,
		type     => 'regex',
		'regex'    => '^(?:[0-9]\d?|10)$',
		for_dashboard => 1,
	},
	# Upload multiple file chunks simultaneously
	ENGINECOUNT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 4,
		type => 'regex',
		for_dashboard => 1,
	},
	# Disable Desktop Access
	DDA => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type => 'regex',
		for_dashboard => 0,
	},
	# Block Desktop Access
	BDA => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type => 'regex',
		for_dashboard => 0,
	},
	DEFAULTTEXTEDITOR => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
	},
	# Ignore file/folder level access rights/permission errors
	# IFPE -> Ignore file permission errors
	IFPE => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 1,
	},
	# Notify as Failure if the total files missing for backup is more than
	# % of the total files backed up
	NMB => {
		cgi_name => '',
		evs_name => '',
		required => 1002,
		default  => 5,
		type     => 'regex',
		'regex'	   => '^(?:[0-9]\d?|10)$',
		for_dashboard => 1,
	},
	SHOWHIDDEN => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 1,
		type     => 'regex',
		for_dashboard => 1,
	},
	UPTIME => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	WEBAPI => {
		cgi_name => 'evswebsrvr',
		evs_name => 'webApiServer',
		required => 1,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
);

tie(our %ServerAddressSchema, 'Tie::IxHash',
	'SERVERADDRESS' => {
		cgi_name => 'evssrvrip',
		evs_name => 'cmdUtilityServerIP',
		required => 1,
		type => 'regex',
	},
);

tie(our %accountStorageSchema, 'Tie::IxHash',
	'totalQuota' => {
		cgi_name => 'quota',
		evs_name => 'totalQuota',
		required => 1,
		type => 'regex',
		'func' => 'setTotalStorage',
	},
	'usedQuota' => {
		cgi_name => 'quota_used',
		evs_name => 'usedQuota',
		required => 1,
		type => 'regex',
		'func' => 'setStorageUsed',
	},
);

our %notificationsSchema = (
	'update_backup_progress'      => '',
	'update_localbackup_progress' => '',
	'update_restore_progress'     => '',
	'get_user_settings'           => 'default_sync',
	'get_logs'                    => 'default_sync',
	'get_settings'                => 'default_sync',
	'get_scheduler'               => 'default_sync',
	'update_remote_manage_ip'     => '',
	'register_dashboard'          => '',
	'update_acc_status'           => '',
	'alert_status_update'         => '',
	'update_device_info'          => '',
);

@notificationsSchema{map{"get_$_".'set_content'} keys %availableJobsSchema} = map{"default_sync"} values %availableJobsSchema;
@notificationsSchema{map{"get_$_".'files_content'} keys %excludeFilesSchema} = map{"default_sync"} values %excludeFilesSchema;

our %notificationsForDashboard = (
	update_backup_progress      => '',
	update_localbackup_progress => '',
	update_restore_progress     => '',
	get_localbackupset_content     => '',
	get_backupset_content     => '',
	get_user_settings     => '',
	get_scheduler => '',
);

our %alertErrCodes = (
	'unexpected_error'        => 100,
	'no_files_to_backup'      => 103,
	'account_cancelled'       => 104,
	'account_under_maint'     => 105,
	'account_blocked'         => 106,
	'account_expired'         => 107,
	'uname_pwd_mismatch'      => 113,
	'pvt_verification_failed' => 114,
	'scheduled_cut_off'       => 115,
	'no_scheduled_jobs'       => 203,
);

our %crontabSchema = (
	'm' => '0',                   # 0-59
	'h' => '0',                   # 0-23
	'dom' => '*',                 # (month) 1-31
	'mon' => '*',                 # 1-12
	'dow' => '*',                 # (week) mon,tue,wed,thu,fri,sat,sun
	'cmd' => '',                  # command to execute
	'settings' => {
		'frequency' => 'daily',     # hourly/daily/weekly/immediate
		'status' => 'disabled',     # disabled/enabled
		'emails' => {
			'ids' => '',
			'status' => 'disabled'    # disabled/enabled
		}
	}
);

our @weekdays = (
	'mon', 'tue', 'wed', 'thu', 'fri'
);
our @weekends = (
	'sat', 'sun'
);

our @weeks = (@weekdays, @weekends);

tie(our %notifOptions, 'Tie::IxHash',
	'notify_always' => 'notify_always',
	'notify_failure' => 'notify_failure'
);

# TODO: need to analyze older version of the OS's and have to add configurations
# fallback will take care if schema not present
our %cronLaunchCodes = (
	'centos' => {
		'lt-6.00' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {'idrivecron' => "/etc/init.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["chkconfig --add $appCron", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "chkconfig --del $appCron"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/centos/lt-6.00/"
		},
		'btw-6.00_6.99' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron.conf" => "/etc/init/$appCron.conf",
			},
			'shellln' => {},
			'setupcmd' => ["initctl start $appCron"],
			'stopcmd' => ["initctl stop $appCron"],
			'restartcmd' => "initctl restart $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/centos/btw-6.00_6.99/"
		},
		'gte-7.00' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron.service" => "/lib/systemd/system/$appCron.service"},
			'shellln' => {},
			'setupcmd' => ["systemctl unmask $appCron", "systemctl enable $appCron", "systemctl start $appCron"],
			'stopcmd' => ["systemctl stop $appCron", "systemctl disable $appCron"],
			'restartcmd' => "systemctl restart $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/centos/gte-7.00/"
		}
	},
	'debian' => {
		'lt-6.00' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron" => "/etc/init.d/$appCron",
			},
			'shellln' => {},
			'setupcmd' => ["update-rc.d $appCron defaults", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "update-rc.d -f $appCron remove"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/debian/lt-6.00/"
		},
		'btw-6.00_8.50' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron" => "/etc/init.d/$appCron",
			},
			'shellln' => {},
			'setupcmd' => ["insserv $appCron", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "insserv -r $appCron"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/debian/btw-6.00_8.50/"
		},
		'gt-8.50' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron.service" => "/lib/systemd/system/$appCron.service"
			},
			'shellln' => {},
			'setupcmd' => ["systemctl enable $appCron", "systemctl start $appCron"],
			'stopcmd' => ["systemctl stop $appCron", "systemctl disable $appCron"],
			'restartcmd' => "systemctl restart $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/debian/gt-8.50/"
		},
	},
	'fedora' => {
		'lte-13.99' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron" => "/etc/init.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["chkconfig --add $appCron", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "chkconfig --del $appCron"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/fedora/lte-13.99/"
		},
		'gte-14.0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron.service" => "/lib/systemd/system/$appCron.service"},
			'shellln' => {},
			'setupcmd' => ["systemctl unmask $appCron.service", "systemctl enable $appCron.service", "systemctl start $appCron.service"],
			'stopcmd' => ["systemctl stop $appCron.service", "systemctl disable $appCron.service"],
			'restartcmd' => "systemctl restart $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/fedora/gte-14.0/"
		}
	},
	'fedoracore' => {
		'lt-7.00' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron" => "/etc/init.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["chkconfig --add $appCron", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "chkconfig --del $appCron"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/fedoracore/lt-7.00/"
		},
	},
	'freebsd' => {
		'gte-11.0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {'rc.conf' => '/etc/rc.conf'},
			'shellcp' => {"idrivecron" => "/etc/rc.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["service $appCron start"],
			'stopcmd' => ["service $appCron stop"],
			'restartcmd' => "service $appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/freebsd/gte-11.0/"
		},
	},
	'gentoo' => {
		'gte-1.0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron" => "/etc/init.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["rc-update add $appCron default", "service $appCron start"],
			'stopcmd' => ["service $appCron stop", "rc-update delete $appCron default"],
			'restartcmd' => "service $appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/gentoo/gte-1.0/"
		},
	},
	'linuxmint' => {
		'gte-15.0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron.service" => "/lib/systemd/system/$appCron.service"
			},
			'shellln' => {},
			'setupcmd' => ["systemctl enable $appCron", "systemctl start $appCron"],
			'stopcmd' => ["systemctl stop $appCron", "systemctl disable $appCron"],
			'restartcmd' => "systemctl restart $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/linuxmint/gte-15.0/"
		},
	},
	'manjarolinux' => {
		'gt-0.8' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				'idrivecron.service' => "/lib/systemd/system/$appCron.service"
			},
			'shellln' => {},
			'setupcmd' => ["systemctl enable $appCron", "systemctl start $appCron"],
			'stopcmd' => ["systemctl stop $appCron", "systemctl disable $appCron"],
			'restartcmd' => "systemctl restart $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/manjarolinux/gte-0.8/"
		},
	},
	'opensuse' => {
		'lte-14.99' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron" => "/etc/init.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["chkconfig --add $appCron", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "chkconfig --del $appCron"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/opensuse/lte-14.99/"
		},
		'gte-15.0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron.service" => "/usr/lib/systemd/system/$appCron.service"},
			'shellln' => {},
			'setupcmd' => ["systemctl unmask $appCron", "systemctl enable $appCron", "systemctl start $appCron"],
			'stopcmd' => ["systemctl stop $appCron", "systemctl disable $appCron"],
			'restartcmd' => "systemctl restart $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/opensuse/gte-15.0/"
		},
	},
	'ubuntu' => {
		'lte-9.04' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron" => "/etc/init.d/$appCron",
			},
			'shellln' => {},
			'setupcmd' => ["update-rc.d $appCron defaults", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "update-rc.d -f $appCron remove"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/ubuntu/lte-9.04/"
		},
		'btw-9.10_14.10' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron.conf" => "/etc/init/$appCron.conf",
			},
			'shellln' => {},
			'setupcmd' => ["service $appCron start"],
			'stopcmd' => ["service $appCron stop"],
			'restartcmd' => "service $appCron restart",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/ubuntu/btw-9.10_14.10/"
		},
		'gte-15.04' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron.service" => "/lib/systemd/system/$appCron.service"
			},
			'shellln' => {},
			'setupcmd' => ["systemctl enable $appCron.service", "systemctl start $appCron.service"],
			'stopcmd' => ["systemctl stop $appCron.service", "systemctl disable $appCron.service"],
			'restartcmd' => "systemctl restart $appCron.service",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/ubuntu/gte-15.00/"
		},
	},
);

our %idriveScripts = (
	'account_settings'            => 'account_setting.pl',
	'archive_cleanup'             => 'archive_cleanup.pl',
	'backup_scripts'              => 'Backup_Script.pl',
	'check_for_update'            => 'check_for_update.pl',
	'configuration'               => 'Configuration.pm',
	'constants'                   => 'Constants.pm',
	'cron'                        => 'cron.pl',
	'dashboard'                   => 'dashboard.pl',
	'edit_supported_files'        => 'edit_supported_files.pl',
	'express_backup'              => 'express_backup.pl',
	'header'                      => 'Header.pl',
	'helpers'                     => 'Helpers.pm',
	'ixhash'                      => 'IxHash.pm',
	'installcron'                 => 'installcron.pl',
	'job_termination'             => 'job_termination.pl',
	'json'                        => 'JSON.pm',
	'login'                       => 'login.pl',
	'logout'                      => 'logout.pl',
	'operations'                  => 'Operations.pl',
	'utility'                     => 'utility.pl',
	'readme'                      => 'readme.txt',
	'relinkcron'                  => 'relinkcron.pl',
	'restore_script'              => 'Restore_Script.pl',
	'restore_version'             => 'restore_version.pl',
	'scheduler_script'            => 'Scheduler_Script.pl',
	'send_error_report'           => 'send_error_report.pl',
	'status_retrieval_script'     => 'Status_Retrieval_Script.pl',
	'strings'                     => 'Strings.pm',
	'uninstallcron'               => 'uninstallcron.pl',
	'uninstall_script'            => 'Uninstall_Script.pl',
	'view_log'                    => 'logs.pl',
	'post_update'                 => 'post_update.pl',
	'deprecated_account_settings' => 'Account_Setting.pl',
	'deprecated_check_for_update' => 'Check_For_Update.pl',
	'deprecated_edit_suppor_files'=> 'Edit_Supported_Files.pl',
	'deprecated_login'            => 'Login.pl',
	'deprecated_restore_version'  => 'Restore_Version.pl',
	'deprecated_view_log'         => 'View_Log.pl',
	'deprecated_logout'           => 'Logout.pl',
	'deprecated_strings'          => 'Strings.pm',
	'deprecated_configuration'    => 'Configuration.pm',
	'deprecated_helpers'          => 'Helpers.pm',
	'deprecated_viewlog'          => 'view_log.pl',
);

our %evsOperations = (
	'LinkBucketOp'       => 'LinkBucket',
	'NickUpdateOp'       => 'NickUpdate',
	'ListDeviceOp'       => 'ListDevice',
	'BackupOp'           => 'Backup',
	'CreateBucketOp'     => 'CreateBucket',
	'RestoreOp'          => 'Restore',
	'ValidateOp'         => 'Validate',
	'GetServerAddressOp' => 'GetServerAddress',
	'AuthListOp'         => 'Authlist',
	'ConfigOp'           => 'Config',
	'GetQuotaOp'         => 'GetQuota',
	'PropertiesOp'       => 'Properties',
	'CreateDirOp'        => 'CreateDir',
	'SearchOp'           => 'Search',
	'RenameOp'           => 'Rename',
	'ItemStatOp'         => 'ItemStatus',
	'VersionOp'          => 'Version',
	'VerifyPvtOp'        => 'VerifyPvtKey',
	'validatePvtKeyOp'   => 'validatePvtKey',
	'LocalBackupOp'      => 'LocalBackup'
);

my %evsParameters = (
	"LINKBUCKET"    => "--link-bucket",
	"NICKUPDATE"    => "--nick-update",
	"BUCKETTYPE"    => "--bucket-type",
	"UNIQUEID"      => "--uid",
	"OS"            => "--os",
	"NICKNAME"      => "--nick-name",
	"CREATEBUCKET"  => "--create-bucket",
	"LISTDEVICE"    => "--list-device",
	"SERVERADDRESS" => "--getServerAddress",
	"USERNAME"      => "--user",
	"PASSWORD"      => "--password-file",
	"ENCTYPE"       => "--enc-type",
	"PVTKEY"        => "--pvt-key",
	"VALIDATE"      => "--validate",
	"CONFIG"        => "--config-account",
	"PROXY"         => "--proxy",
	"UTF8CMD"       => "--utf8-cmd",
	"ENCODE"        => "--encode",
	"FROMFILE"      => "--files-from",
	"TYPE"          => "--type",
	"BWFILE"        => "--bw-file",
	"PROPERTIES"    => "--properties",
	"XMLOUTPUT"     => "--xml-output",
	"GETQUOTA"      => "--get-quota",
	"AUTHLIST"      => "--auth-list",
	"SPEED"         => "--trf-",
	"OUTPUT"        => "--o",
	"ERROR"         => "--e",
	"PROGRESS"      => "--100percent-progress",
	"QUOTAFROMFILE" => "--quota-fromfile",
	"CREATEDIR"     => "--create-dir",
	"SEARCH"        => "--search",
	"VERSION"       => "--version-info",
	"RENAME"        => "--rename",
	"OLDPATH"       => "--old-path",
	"NEWPATH"       => "--new-path",
	"FILE"          => "--file",
	"ITEMSTATUS"    => "--items-status",
	"ADDPROGRESS"   => "--add-progress",
	"TEMP"          => "--temp",
	"DEFAULTKEY"    => "--default-key",
	"ITEMSTATUS3"   => "--items-status3",
	"DEVICEID"      => "--device-id",
);

our @errorArgumentsExit = (
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
	"Connection refused",
	#"failed to connect",
	"Connection timed out",
	"Invalid device id",
	"not enough free space on device"
);

our %statusHash = (
	COUNT_FILES_INDEX => 0,
	SYNC_COUNT_FILES_INDEX => 0,
	ERROR_COUNT_FILES => 0,
	FAILEDFILES_LISTIDX => 0,
	EXIT_FLAG => 0,
	FILES_COUNT_INDEX => 0,
	DENIED_COUNT_FILES => 0,
	MISSED_FILES_COUNT => 0,
	FAILED_COUNT_FILES_INDEX => 0,
);

our %errorDetails = (
	100 => 'logout_&_login_&_try_again',
	101 => 'your_account_not_configured_properly',
	102 => 'login_&_try_again',
	103 => 'your_account_not_configured_properly_reconfigure',
	104 => 'account_not_configured',	
	1000 => 'invalid_bwt',
	1001 => 'invalid_nfb',
	1002 => 'invalid_nmb',
);

our %userConfigurationLockSchema = (
	'__title_backup__bandwidth_throttle' => 'slide_throttle',
	'__title_backup__edit_failed_backup_per' => 'fail_val',
	'__title_backup__edit_missing_backup_per' => 'notify_missing',
	'__title_general_settings__upload_multiple_chunks' => 'chk_multiupld',
	'__title_general_settings__ignore_permission_denied' => 'ignore_accesserr',
	'__title_general_settings__show_hidden_files' => 'show_hidden',
	'__title_restore_settings__restore_loc_prompt' => 'chk_asksave',
	'__title_general_settings__notify_software_update' => 'chk_update',
);

our %evsVersionSchema = (
	'IDrive' => {
		'idevsutil' => {
				'version' => '1.0.2.8',
				'release_date' => '05-JUNE-2018',
				},
		'idevsutil_dedup' => {
				'version' => '2.0.0.1',
				'release_date' => '21-MAY-2018',
				},
	},
	'IBackup' => {
		'idevsutil' => {
				'version' => '1.0.2.8',
				'release_date' => '18-MARCH-2015',
				},
	}
);
our %minMaxVersionSchema = (
	'IDrive' => {
		'1' => {
			'min' => '2.10',
			'max' => '2.18',
			},
		'2' => {
			'min' => '2.18',
			'max' => '2.18',
			},
	},
	'IBackup' => {
		'1' => {
			'min' => '2.7',
			'max' => '2.11',
			},
		'2' => {
			'min' => '2.12',
			'max' => '2.12',
			},
	}
);
1;
