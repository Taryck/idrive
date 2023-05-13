#*****************************************************************************************************
# App configurations
#
# Created By : Yogesh Kumar @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#*****************************************************************************************************

package AppConfig;
use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')); } else { use lib '.'; }

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(TRUE FALSE STATUS SUCCESS FAILURE);

use IxHash;

our $version          = '2.37';
my $buildVersion      = '';
$version             .= "$buildVersion" if ($buildVersion ne '');
our $releasedate      = '03-03-2023';
our $appType          = 'IDrive';
our $servicePathName    = lc($appType).'It';
our $oldServicePathName = lc($appType);

our $language = 'EN';       # EN-ENGLISH

our $staticPerlVersion    = '2.31';
our $staticPerlBinaryName = 'perl';

our $pythonVersion        = '2.37';
our $pythonBinaryName     = 'dashboard';

our $appCron = lc($appType).'cron';

our $dbversion = '2.0';

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
	TRY_UPDATE => 1,
	TRY_INSERT => 1,
	MULTIPLE_BACKUP_SET => 1,

};

our $debug = 0;

our $displayHeader = 1;

our $hostname = `uname -n`;
chomp($hostname);
unless ($hostname) {
	$hostname = `hostname`;
	chomp($hostname);
}
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

our $errorMsg           = '';
our $utf8File           = 'utf8.cmd';
our $idriveLibPath      = 'Idrivelib/lib';
# TODO: remove our $idrivePythonPath   = 'Idrivelib/python';
our $idriveDepPath      = 'Idrivelib/dependencies';
our $idrivePythonBinPath= "$idriveDepPath/python";
our $idrivePerlBinPath  = "$idriveDepPath/perl";
our $cronSetupPath      = 'Idrivelib/cronsetup';
our $cpanSetupPath      = 'Idrivelib/cpansetup';
our $inotifySourcePath	= 'Idrivelib/inotify2src';
our $inotifyBuiltPath	= 'Idrivelib/inotify2';
our $defaultMountPath   = '/tmp';

our $evsBinaryName        = 'idevsutil';
our $evsDedupBinaryName   = 'idevsutil_dedup';
our $rRetryTimes          = 2;                   # Request retry for 2 more times(total 3).
our $perlBin              = `which perl`;
chomp($perlBin);
if (exists $ENV{'_'} and $ENV{'_'} and not ($ENV{'_'} =~ m/$idriveDepPath/)) {
	$perlBin = $ENV{'_'};
}

if ($perlBin =~ /\.pl$/) {
	$perlBin = `which perl`;
	chomp($perlBin);
	$perlBin = '/usr/bin/perl' unless($perlBin);
}

chomp(our $machineOS = `uname -msr`);
our $freebsdProgress = '';
our $deviceType      = 'LINUX';
our $evsVersion      = 'evs005';
our $NSPort          = 443;

our $deviceUIDPrefix = 'Linux';
our $deviceUIDsuffix = '';
our $deviceIDPrefix  = '5c0b';
our $deviceIDSuffix  = '4b5z';

our @dependencyBinaries = ('unzip', 'curl');

our $serviceLocationFile = '.serviceLocation';
our $updateVersionInfo   = '.updateVersionInfo';
our $forceUpdateFile     = '.forceupdate';
our $autoinstall		= '--auto-setup';
our $isautoinstall		= 0;
our $autoconfspc		= 60;

our $versioncache          = 'cache/version';
our $cachedFile            = 'cache/user.txt';
our $cachedIdriveFile      = 'cache/'.lc($appType).'user.txt';
our $osVersionCache        = 'cache/os_detail.txt';
our $proxyInfoFile         = '__SERVICEPATH__/cache/proxy.info';
our $userProfilePath       = 'user_profile';
our $userInfoPath          = '.userInfo';
our $idpwdFile             = "$userInfoPath/IDPWD";
our $idenpwdFile           = "$userInfoPath/IDENPWD";
our $idpwdschFile          = "$userInfoPath/IDPWD_SCH";
our $idpvtFile             = "$userInfoPath/IDPVT";
our $idenpvtFile           = "$userInfoPath/IDENPVT";
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
our $bufferLimit           = 10 * 1024;
our $quotatimeout          = 36000;
our $maxFileVersion        = 30;

our $minEngineCount     = 2;
our $maxEngineCount     = 4;
our $restoreEngineCount	= 4;

our $fullExcludeListFile	= 'FullExcludeList.txt';
our $partialExcludeListFile	= 'PartialExcludeList.txt';
our $regexExcludeListFile	= 'RegexExcludeList.txt';
our $otherExcludetFile		= 'otherExclude.json';

our $searchDir          = 'Search';
our $evsOutputFile      = 'evsOutput.txt';
our $evsErrorFile       = 'evsError.txt';
our $versionRestoreFile = 'versionRestoresetFile.json';

our $unzipLog     = 'unzipLog.txt';
our $updateLog    = '.updateLog.txt';
our $updatePid    = 'update.pid';
our $preupdpid	  = 'preupdate.pid';
our $freshInstall = 'freshInstall';

our $isUserConfigModified	= 0;
our $backupsetFile			= 'BackupsetFile.enc';
our $transBackupsetFile		= 'BackupsetFile.trans';
our $oldBackupsetFile		= 'BackupsetFile.txt';
our $backupextn				= '.bkp';
our $tempBackupsetFile		= 'tempBackupsetFile.txt';
our $backupsetMaxSize		= 5000000000;
our $backupsethist			= 'HIST/track_%m_%Y.log';
our $maxbackuphist			= 12;

our $restoresetFile        = 'RestoresetFile.txt';
our $tempRestoresetFile    = 'tempRestoresetFile.txt';

our $restoresetFileRelative   = 'RestoreFileName_Rel.txt';
our $restoresetFileNoRelative = 'RestoreFileName_NoRel.txt';
our $restoresetFileOnlyFiles  = 'RestoreFileName_filesOnly';
our %fileInfoDB;

our $archiveFileResultSet    = 'archiveFileResultSet';
our $archiveDirResultSet     = 'archiveDirResultSet';
our $archiveFileListForView  = 'archiveFileListForView.txt';
our $archiveFileResultFile   = 'archiveFileResult.txt';
our $archiveFolderResultFile = 'archiveFolderResult.txt';
our $archiveSettingsFile     = 'archive_settings.json';
our $archiveStageDetailsFile = 'archiveStageDetails.txt';
our $archiveFileFailureReasonFile = 'archiveFileFailureReason.txt';

our $alertStatusFile = 'alert.status';

our $bwFile          = 'bw.txt';
our $cancelFile      = 'exitError.txt';
our $exitErrorFile   = 'exitError.txt';
our $schtermf		 = 'schedule.term';
our $errorFile       = 'error.txt';
our $evsTempDir      = 'evs_temp';
our $statusFile      = 'STATUS_FILE';
our $infoFile        = 'info_file';
our $fileForSize     = 'TotalSizeFile';
# our $excludeDir      = 'Excluded';
our $errorDir        = 'ERROR';
our $pidFile         = 'pid.txt';
our $progressPidFile = 'progressPidFile.txt';
our $logPidFile      = 'LOGPID';
# our $excludedLogFile = 'excludedItemsLog.txt';
our $mountPointFile  = 'mountPoint.txt';
our $trfSizeAndCountFile = 'trfSizeAndCount.txt';
our $progressDetailsFilePath = 'PROGRESS_DETAILS';
our $retryInfo = "RetryInfo.txt";
our $failedFileName = "failedFiles.txt";
our $failedFileWithReason = "failedFileWithReason.txt";
our $failedDirList = "failedDirList.txt";
our $finalErrorFile = "finalError.txt";
our $deletedFileList = "deletedFileList.txt";
our $deletedDirList = "deletedDirList.txt";
our $relativeFileset = "BackupsetFile_Rel";
our $filesOnly = "BackupsetFile_filesOnly";
our $noRelativeFileset = "BackupsetFile_NoRel";
our $transferredFileSize = 'transferredFileSize.txt';
our $totalFileCountFile = 'totalFileCountFile';
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
our ($mailContent, $jobType, $expressLocalDir, $errStr, $finalSummary) = ('') x 5;
our ($fullStr,$parStr,$regexStr) = ('') x 3;
our $regexcl = '';
our ($noRelIndex, $filesonlycount, $retryCount, $cancelFlag, $versionToRestore) = (0) x 5;
# our ($excludedCount,$noRelIndex,$excludedFileIndex,$filesonlycount,$retryCount,$cancelFlag) = (0) x 6;
our ($totalFiles, $totalSize, $fileCount, $nonExistsCount, $noPermissionCount, $missingCount, $readySyncedFiles, $excludedCount) = (0) x 8;
our ($localMountPath,$encType,$pvtKeyHash) = ('') x 3;
our $progressSizeOp = 1;
our $allowExtentedView = 1;
our $prevProgressStrLen = 10000;
our @linesStatusFile = undef;
# our ($cumulativeCount, $cumulativeTransRate) = (0)x2;

our $filePermission    = 0777;
our $execPermission    = 0755;
our $execPermissionStr = "0755";
our $filePermissionStr = "0777";
our $prevTime = time();

our $inputMandetory = 1;

our $totalFileKey = 'totalFiles';
our $startTimeKey = 'actStartTime';
our $accessTokenFile = 'accesstoken.txt';
our $notificationFile = 'notification.json';
our $nsFile = 'ns.json';

our $logStatFile = "%02d%04dlogstat\.json";

our $crontabFile    = lc($appType).'crontab.json';
our $cronlockFile   = '/var/run/'.lc($appType).'cron.lock';
our $cronservicepid = '/var/run/'.lc($appType).'cron.pid';
our $cronLinkPath   = '/etc/'.lc($appType).'cron.pl';
our $cronSetup = 'setup';

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
our $ldbNew           = 'LDBNEW';
our $xpressdir        = 'IDriveLocal';
our $pressedKeyValue  = '';

our $restorepidlock = "restore.pid";

# dashboard lock
our $dashboardpid = 'dashboard.pid';
our $dashbtask    = 'dashboard';

our $localHost		= 'localhost';
our $localPort		= 0;
our $localPortBase	= 22500;
our $localPortRange	= 4000;
our $protocol		= 'tcp';
our $listen			= 1;
our $reuse			= 1;
our $cdp			= 'cdp';
our	$cdpfn			= 'Continuous Data Protection';
our $cdpwatcher		= 'cdpwatcher';
our $cdprescan		= 'cdpDBScan';
our $dbnamebase		= 'cdp.ibenc';
our $dbname			= $dbnamebase . '_' . $dbversion;
our $rescanlog		= 'rescan.log';
our $cdpcpdircache	= 'cpentries.txt';
our $dbFileIndex	= 0;
our $cdpdbdumpdir	= 'CDPDBDUMP';
our $failcommitdir	= 'FAILED_COMMIT';
our $commitvault	= 'COMMIT_VAULT';
our $cdphalt		= '.haltcdp';
our $cdpmaxsize		= 1073741824000; # 1000000 * 1024 * 1024 * 1024 - 1000GB
our $fsindexmax		= 5000;
our $cdpscandet		= 5000;
our $cdpdumptimeout	= 5;
our $cdpdumpmaxrec	= 10000;
our $cdploadchkct	= 20;
our $repooppath		= '/tmp/pk-inst-op.log';
our $repoerrpath	= '/tmp/pk-inst-err.log';
our $instprog		= '/tmp/instprog.log';
our $instproglock	= '/tmp/instprog.lock';
# our $silinstprog	= '/tmp/silent_inst.prog';
our $silinstlock	= '/tmp/silent_inst.lock';
our $misctask		= 'miscellaneous';
our $miscjob		= 'install';
our $defrescanday	= '01';
our $defrescanhr	= '12';
our $defrescanmin	= '00';

our $silentflag = '--silent';
our $running = 'running';
our $paused  = 'paused';
our $more    = 'more';
our $less    = 'less';
our $backup  = 'backup';
our $restore = 'restore';
our $archive = 'archive';
our $bkpscan = 'bkpscan';
our $rescan  = 'rescan';
our $scan    = 'scan';
our $localbackup = 'localbackup';
our $processPattern = 'CDP|DBW';
our $lastBkpStatusFile = 'lastBackupStatus.txt';
our $localrestoreListPid = 'localrestorelistpid.txt';
our $splitCount          = 1000;
our $localFolderList     = '_folderlist';

our $nslockfh;
our $cronlockfh;
our $nslockfile = "notification.lock";
our $cronlockfile = "cron.lock";
our $crontabmts = 0;

our %jobTitle = ('backup' => 'backup_job', 'restore' => 'restore_job', 'archive' => 'archive_job', 'localbackup' => 'localbackup_job', 'cdp' => 'cdp_job', 'bkpscan' => 'bkpscan_job', 'rescan' => 'rescan_job', 'localrestore' => 'localrestore_job');

our %cdplocks		= ('client' => 'cdpclient.lock', 'server' => 'cdpserver.lock', 'watcher' => 'watcher.lock', 'bkpscan' => 'bkpscan.lock', 
						'dbwritelock' => 'dbwrite.lock', 'rescan' => 'rescan.lock', 'backup' => 'backup.lock', 'prog' => 'prog.lock', 'scanprog' => 'scan.prog', 
						'lport' => 'local.port');

tie (our %dbdumpregs, 'Tie::IxHash',
	'backup'		=> 'backup_dbupd_*',
	'localbackup'	=> 'localbackup_dbupd_*',
	'cdp'			=> 'cdp_dbupd_*',
	'rescan'		=> 'rescan_dbupd_*',
	'scan'			=> 'scan_dbupd_*',
	'jssize'		=> 'js_size_*',
	'ex_db_renew'	=> 'ex_db_renew_*',
	'idx_del_upd'	=> 'idx_del_upd_*',
	'bkpstat_reset'	=> 'bkpstat_reset_*',
	'verify_xpres'	=> 'verify_local_*',
	'db_cleanp'		=> 'db_cleanp_*',
	'upd_mpc_self'	=> 'mpc_upd_self_*',
	'rm_nonex_fl'	=> 'rm_nonex_fl_*',
);

our $webvxmldir = 'WebViewXML';

our %dbfilestats	= ('NEW' => 0, 'BACKEDUP' => 1, 'MODIFIED' => 2, 'EXCLUDED' => 3, 'DELETED' => 4, 'CDP' => 10);
our %deprecatedProfilePath = ('localbackup' => 'Backup/LocalBackupSet');

our %userProfilePaths = (
	'archive'		=> 'Archive/DefaultBackupSet',
	'cdp'			=> 'CDP/DefaultBackupSet',
	'backup'		=> 'Backup/DefaultBackupSet',
	'localbackup'	=> 'LocalBackup/LocalBackupSet',
	'restore'		=> 'Restore/DefaultRestoreSet',
	'localrestore'  => 'LocalRestore/LocalRestoreSet',
	'user_info'		=> '.userInfo',
	'restore_data'	=> 'Restore_Data',
	'trace'			=> '.trace',
	'tmp'			=> 'tmp',
	'dbreindex'     => 'DBReindex',
);

our @defexcl = ('/proc/', '/sys/');

our %fileSizeDetail = (
	'bytes' => 'bytes',
	'kb'    => 'KB',
	'mb'    => 'MB',
	'gb'    => 'GB',
	'tb'    => 'TB',
);

our %accfailstat = (
	'M' => 'your_account_is_under_maintenance',
	'B' => 'your_account_has_been_blocked',
	'C' => 'your_account_has_been_cancelled',
	'S' => 'your_account_has_been_suspended',
	'O' => 'your_account_status_unknown',
	'UA' => 'unauthorized_user',
);

our $activestat = 'Y';

our $screenSize = '';
$screenSize     = `stty size` if (-t STDIN);
our $sleepTimeForProgress = 100;
$sleepTimeForProgress = 500 if($machineOS =~ /freebsd/i);
our $userConfChanged = 0;
our $tab = "      ";

our $proxyNetworkError = "failed to connect|Connection refused|Could not resolve proxy|Could not resolve host|No route to host|HTTP code 407|URL returned error: 407|407 Proxy Authentication Required|Connection timed out|response code said error|kindly_verify_ur_proxy";

# Multiple Engine
our $totalEngineBackup = 4;
use constant ENGINE_LOCKE_FILE => "engine.lock";
# Multiple Engine

our $dependencyDownloadsPage = "https://www.__APPTYPE__.com/downloads/linux/download-options";
our $evsDownloadsPage = "https://www.__APPTYPE__.com/downloads/linux/download-options/secure_evs";
# our $evsDownloadsPage = " -u deepak:deepak http://192.168.3.169/svn/linux_repository/trunk/PackagesForTesting/IDriveForLinux/binaries";
our $IDriveWebURL	= 'https://www.idrive.com/idrive/login/loginAuto/showEntDesign';

# Software Update CGI
our $trimmedVersion = $version;
my @matches = split('\.', $trimmedVersion);
if (scalar(@matches) > 2) {
	$trimmedVersion = $matches[0].".".$matches[1];
}

our $IDriveSupportEmail = 'support@'.lc($appType).'.com';

# production download URL
my $IDriveAppUrl = "https://www.idrivedownloads.com/downloads/linux/download-for-linux/IDrive_Scripts/IDriveForLinux.zip";

# production download URL
my $IBackupAppUrl = "https://www.ibackup.com/online-backup-linux/downloads/download-for-linux/IBackup_for_Linux.zip";
# SVN download URL
#my $IBackupAppUrl = " -u deepak:deepak http://192.168.3.169/svn/linux_repository/trunk/PackagesForTesting/IBackupForLinux/IBackup_for_Linux.zip";
our $accountSignupURL = "https://www.ibackup.com/newibackup/signup";
$accountSignupURL = "https://www.idrive.com/idrive/signup" if($appType eq 'IDrive');

our $appDownloadURL = ($appType eq 'IDrive')? $IDriveAppUrl : $IBackupAppUrl;
our $appPackageName = ($appType eq 'IDrive')?'IDriveForLinux':'IBackup_for_Linux';
our $appPackageExt  = '.zip';

our %evsZipFiles = (
	'IDrive' => {
		'32' => ['__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip'],
		'64' => ['__APPTYPE___linux_64bit.zip', '__APPTYPE___QNAP_64bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___Vault_64bit.zip', '__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip'],
		'arm' => ['__APPTYPE___QNAP_ARM.zip', '__APPTYPE___synology_ARM.zip', '__APPTYPE___Netgear_ARM.zip', '__APPTYPE___synology_Alpine.zip', '__APPTYPE___synology_aarch64bit.zip'],
		'aarch64' => ['__APPTYPE___synology_aarch64bit.zip', '__APPTYPE___QNAP_ARM.zip', '__APPTYPE___synology_ARM.zip', '__APPTYPE___Netgear_ARM.zip', '__APPTYPE___synology_Alpine.zip'],
		'freebsd' => ['__APPTYPE___Vault_64bit.zip'],
	},
	'IBackup' => {
		'32' => ['__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___Netgear_64bit.zip', '__APPTYPE___Vault_64bit.zip'],
		'64' => ['__APPTYPE___linux_64bit.zip', '__APPTYPE___QNAP_64bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___Netgear_64bit.zip', '__APPTYPE___Vault_64bit.zip', '__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip'],
		'arm' => ['__APPTYPE___QNAP_ARM.zip', '__APPTYPE___synology_ARM.zip', '__APPTYPE___Netgear_ARM.zip', '__APPTYPE___synology_Alpine.zip'],
		'freebsd' => ['__APPTYPE___Vault_64bit.zip'],
	},
);

our %staticperlZipFiles = (
	'32'      => ("idrive_dependency/$staticPerlVersion/__KVER__/x86/perl.zip"),
	'64'      => ("idrive_dependency/$staticPerlVersion/__KVER__/x86_64/perl.zip"),
	'freebsd' => ("idrive_dependency/$staticPerlVersion/freebsd/perl.zip"),
);

our %pythonZipFiles = (
	'32'      => ("idrive_dependency/$pythonVersion/__KVER__/x86/python.zip"),
	'64'      => ("idrive_dependency/$pythonVersion/__KVER__/x86_64/python.zip"),
	'arm'     => ("idrive_dependency/$pythonVersion/__KVER__/arm/python.zip"),
	'aarch64' => ("idrive_dependency/$pythonVersion/__KVER__/aarch64/python.zip"),
	'freebsd' => ("idrive_dependency/$pythonVersion/freebsd/python.zip"),
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
	localrestore => {
		path => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'localrestore'}/",
		logs => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'localrestore'}/$logDir",
		file => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'localrestore'}/$restoresetFile",
		type => 'restore',
		runas => [],
		croncmd => "",
	},
	archive => {
		path => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'archive'}/",
		logs => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'archive'}/$logDir",
		file => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'archive'}/$backupsetFile",
		type => 'archive',
		runas => [],
        croncmd => "%s %s %s %s %s %s", # script name, username, days, percentage, timestamp, isEmptyDirDelete
	},
	cdp => {
		path => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'cdp'}/",
		logs => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'cdp'}/$logDir",
		file => "__SERVICEPATH__/$userProfilePath/$mcUser/__USERNAME__/$userProfilePaths{'backup'}/$backupsetFile",
		type => 'cdp',
		runas => ['SCHEDULED', 'immediate', 'CDP'],
		croncmd => "%s %s %s", # Script name, runas & username
	},
);

use constant JOBEXITCODE => {
	'SUCCESS' => 'Success',
	'SUCCESS*' => 'Success*',
	'FAILURE' => 'Failure',
	'ABORTED' => 'Aborted',
	'RUNNING' => 'Running',
};

tie (our %logMenuAndPaths, 'Tie::IxHash',
	'backup'		=> 'backup_logs',
	'localbackup'	=> 'local_backup_logs',
	'restore'		=> 'restore_logs',
	'localrestore'	=> 'local_restore_logs',
	'archive'		=> 'archive_cleanup_logs',
	'cdp'			=> 'cdp_logs',
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

our $proxyTemplate = {
	'PROXYIP'   => '',
	'PROXYPORT' => '',
	'PROXYUSERNAME' => '',
	'PROXYPASSWORD' => '',
	'PROXY' => '',
};

our %evsAPIPatterns = (
	'GETQUOTA'         => "--get-quota\n__getUsername__\@__getServerAddress__::home/",
	'STRINGENCODE'     => "--string-encode=__ARG1__\n--out-file=__ARG2__",
	'VALIDATE'         => "--validate\n--user=__ARG1__\n--password-file=__ARG2__",
	'GETSERVERADDRESS' => "--getServerAddress\n__getUsername__",
	'CREATEBUCKET'     => "--xml-output\n--create-bucket\n--nick-name=__ARG1__\n--os=Linux\n--uid=__getMachineUID__\n--bucket-type=D\n--location=__getMachineUser__\n__getUsername__\@__getServerAddress__::home/",
	'CREATEDIR'        => "--xml-output\n--create-dir=__ARG1__\n__getUsername__\@__getServerAddress__::home/",
	'LISTDEVICE'       => "--xml-output\n--list-device\n--all\n__getUsername__\@__getServerAddress__::home/",
	'NICKUPDATE'       => "--xml-output\n--nick-update\n--nick-name=__ARG1__\n--os=Linux\n--device-id=__ARG2__\n--location=__getMachineUser__\n__getUsername__\@__getServerAddress__::home/",
	'LINKBUCKET'       => "--xml-output\n--link-bucket\n--nick-name=__ARG1__\n--os=Linux\n__getUsername__\@__getServerAddress__::home/\n--device-id=$deviceIDPrefix\__ARG2__$deviceIDSuffix\n--uid=__ARG3__\n--bucket-type=D\n--location=__getMachineUser__",
	'DEFAULTCONFIG'    => "--config-account\n--enc-type=DEFAULT\n--wb-sr=__ARG1__\n__getUsername__\@__getServerAddress__::home/",
	'PRIVATECONFIG'    => "--config-account\n--enc-type=PRIVATE\n--wb-sr=__ARG1__\n__getUsername__\@__getServerAddress__::home/",
	'PING'             => "__getUsername__\@__getServerAddress__::home/",
	'FILEVERSION'      => "--version-info\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG1__",
	'SEARCH'           => "--search\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'SEARCHALL'        => "--search\n--all\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'SEARCHARCHIVE'    => "--search\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'PATTERNSEARCH'    => "--search\n--o=__ARG1__\n--e=__ARG2__\n--search-key=__ARG3__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG4__",
	'ITEMSTATUS3'      => "--items-status3\n--files-from=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'ITEMSTATUS'       => "--items-status\n--files-from=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'PROPERTIES'       => "--properties\n--e=__ARG1__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG2__",
	'DELETE'           => "--delete-items\n--files-from=__ARG1__\n--o=__ARG2__\n--e=__ARG3__\n--xml-output\n__getUsername__\@__getServerAddress__::home/",
	'AUTHLIST'         => "--auth-list\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'LOCALBACKUP'      => "--files-from=__ARG1__\n--bw-file=__ARG2__\n--type\n--def-local=__ARG3__\n--add-progress\n--temp=__ARG4__\n--xml-output\n--enc-opt\n__ARG5__\n--portable\n--no-versions\n--o=__ARG6__\n--e=__ARG7__\n--portable-dest=__ARG8__\n__ARG9__\n__getUsername__\@__getServerAddress__::home/__ARG10__",
	'BACKUP'           => "--files-from=__ARG1__\n--bw-file=__ARG2__\n--type\n--add-progress\n--100percent-progress\n--temp=__ARG3__\n--xml-output\n--o=__ARG4__\n--e=__ARG5__\n__ARG6__\n__getUsername__\@__getServerAddress__::home/__ARG7__",
	# 'LOGBACKUP'        => "--files-from=__ARG1__\n--xml-output\n--backup-log\n--no-relative\n--temp=__ARG2__\n--o=__ARG3__\n--e=__ARG4__\n/\n__getUsername__\@__getServerAddress__::home/--ILD--/$hostname/log/",
	'LOGBACKUP'        => "--files-from=__ARG1__\n--xml-output\n--backup-log\n--no-relative\n--temp=__ARG2__\n--o=__ARG3__\n--e=__ARG4__\n/\n__getUsername__\@__getServerAddress__::home/--ILD--/$hostname/__ARG5__",
	'CHANGEINDEX'		=> "--xml-output\n--port=443\n--type\n--search\n--timeout=60\n--file-index64=__ARG1__\n--app-index64\n--o=__ARG2__\n__getUsername__\@__getServerAddress__::home/",
	'CHANGENOINDEX'		=> "--xml-output\n--port=443\n--type\n--search\n--timeout=60\n--file-index64=__ARG1__\n--o=__ARG2__\n__getUsername__\@__getServerAddress__::home/",
	'LOCALRESTORE'	   => "--files-from=__ARG1__\n--add-progress\n--enc-opt\n--def-local=__ARG2__\n--temp=__ARG3__\n--xml-output\n--mask-name\n--o=__ARG4__\n--e=__ARG5__\n--portable\n--portable-dest=__ARG6__\n__getUsername__\@__getServerAddress__::home/__ARG6__\n__ARG7__\n",
	'DBREINDEX'		   => "--expressdb-recreate\n--xml-output\n--user=__getUsername__\n--o=__ARG1__\n--e=__ARG2__\n--portable-dest=__ARG3__\n",
	'SNAPSHOTLISTING'  => "--xml-output\n--snap-shot2\n--snapshot-sdate=__ARG1__\n--snapshot-edate=__ARG2__\n--o=__ARG3__\n--e=__ARG4__\n__getUsername__\@__getServerAddress__::home/__ARG5__\n",
	'SNAPSHOTSEARCH'  => "--xml-output\n--snap-shot2\n--snapshot-sdate=__ARG1__\n--snapshot-edate=__ARG2__\n--o=__ARG3__\n--e=__ARG4__\n__getUsername__\@__getServerAddress__::home/__ARG5__\n--all\n",
	'SNAPSHOTFOLDERSIZE'  => "--snap-shot2\n--xml-output\n--snapshot-sdate=__ARG1__\n--snapshot-edate=__ARG2__\n--o=__ARG3__\n--e=__ARG4__\n__getUsername__\@__getServerAddress__::home/__ARG5__\n--folder-size\n",
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
		required => 103,
		default  => '',
		type => 'regex',
		for_dashboard => 1,
	},
	MUID => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type => 'regex',
		for_dashboard => 0,
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
		regex	   => '^(?:[1-9]\d?|100)$',
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
		default => '',
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
	LOCALRESTOREFROM => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 1,
	},
	LOCALRESTOREMOUNTPOINT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 1,
	},
	LOCALRESTORESERVERROOT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		lockable => 0,
		for_dashboard => 0,
	},
	# Notify as Failure if the total files failed for backup is more than
	# % of the total files backed up
	NFB => {
		cgi_name => '',
		evs_name => '',
		required => 1001,
		default  => 5,
		type     => 'regex',
		regex    => '^(?:[0-9]\d?|10)$',
		for_dashboard => 1,
	},
	# Upload multiple file chunks simultaneously
	ENGINECOUNT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => $maxEngineCount,
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
		regex	 => '^(?:[0-9]\d?|10)$',
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
	CDP => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 1,
	},
	RESCANINTVL => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => "$defrescanday:$defrescanhr:$defrescanmin",
		type     => 'regex',
		for_dashboard => 1,
	},
	LASTFILEINDEX => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 0,
	},
	CDPSUPPORT => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 1,
	},
	WEBAPI => {
		cgi_name => 'evswebsrvr',
		evs_name => 'webApiServer',
		required => 1,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	DELCOMPUTER => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => '',
		type     => 'regex',
		for_dashboard => 0,
	},
	BACKUPLOCATIONSIZE => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 0,
	},
    EXCLUDESETUPDATED => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 0,
	},
	TRD => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 0,
	},
	EVSSRVR => {
		cgi_name => 'evssrvr',
		evs_name => 'cmdUtilityServer',
		required => 0,
		default  => 0,
		type     => 'regex',
		for_dashboard => 0,
	},
	EVSSRVRACCESS => {
		cgi_name => '',
		evs_name => '',
		required => 0,
		default  => 1,
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
		func => 'setTotalStorage',
	},
	'usedQuota' => {
		cgi_name => 'quota_used',
		evs_name => 'usedQuota',
		required => 1,
		type => 'regex',
		func => 'setStorageUsed',
	},
);

our %notificationsSchema = (
	'update_backup_progress'      => '',
	'update_localbackup_progress' => '',
	'update_restore_progress'     => '',
	'update_localrestore_progress'=> '',
	'get_user_settings'           => 'default_sync',
	'get_logs'                    => 'default_sync',
	'get_settings'                => 'default_sync',
	'get_scheduler'               => 'default_sync',
	'update_remote_manage_ip'     => '',
	'register_dashboard'          => '',
	'update_acc_status'           => '',
	'alert_status_update'         => '',
	'update_device_info'          => '',
	'update_next_backup_time'     => '',
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
	'start_missed_backup'     => 202,
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

tie(our %supportedOSList, 'Tie::IxHash',
	1 => 'Centos',
	2 => 'Debian',
    3 => 'Fedora',
    4 => 'Fedoracore',
    5 => 'Freebsd',
    6 => 'Gentoo',
    7 => 'Linuxmint',
    8 => 'Manjarolinux',
    9 => 'Opensuse',
    10 => 'Ubuntu',
);

our %dbFields = (
	#Name field is mandatory and it was added in SQL query. So need not to add explicitly.
	# 'TYPE'      => 'TYPE',
	'DIR_LMD'        => 'ibfolder.FILE_LMD as LMD',
	'DIR_TOTALSIZE'  => 'TOTAL(ibfile.FILE_SIZE) AS TOTALSIZE',
	'DIR_FILESCOUNT' => 'COUNT(*) AS FILESCOUNT',
	'SIZE'       	 => 'ibfile.FILE_SIZE as SIZE',
	'LMD'        	 => 'ibfile.FILE_LMD as LMD',
	'FILEBKPSTATUS'  => 'ibfile.BACKUP_STATUS as FILEBKPSTATUS',
);

# @TODO: need to analyze older version of the OS's and have to add configurations
# fall back will take care if schema not present
our %cronLaunchCodes = (
	'archlinux' => {
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
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/archlinux/gte-0.8/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sd',
		},
	},
	'centos' => {
		'lt-6.00' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {'idrivecron' => "/etc/init.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["chkconfig --add $appCron", "/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop", "chkconfig --del $appCron"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/centos/lt-6.00/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
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
			'startcmd' => "initctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/centos/btw-6.00_6.99/",
			'req-serv' => 'initctl',
			'base-conf-key' => 'lt-6.00',
			'serv-mod' => 'ups',
		},
		'gte-7.00' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron.service" => "/lib/systemd/system/$appCron.service"},
			'shellln' => {},
			'setupcmd' => ["systemctl unmask $appCron.service", "systemctl enable $appCron.service", "systemctl start $appCron.service"],
			'stopcmd' => ["systemctl stop $appCron.service", "systemctl disable $appCron.service"],
			'restartcmd' => "systemctl restart $appCron",
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/centos/gte-7.00/",
			'req-serv' => 'systemctl',
			'base-conf-key' => 'lt-6.00',
			'serv-mod' => 'sd',
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
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/debian/lt-6.00/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
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
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/debian/btw-6.00_8.50/",
			'req-serv' => 'insserv',
			'base-conf-key' => 'lt-6.00',
			'serv-mod' => 'ups',
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
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/debian/gt-8.50/",
			'req-serv' => 'systemctl',
			'base-conf-key' => 'lt-6.00',
			'serv-mod' => 'sd',
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
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/fedora/lte-13.99/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
		},
		'gte-14.0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron.service" => "/lib/systemd/system/$appCron.service"},
			'shellln' => {},
			'setupcmd' => ["systemctl unmask $appCron.service", "systemctl enable $appCron.service", "systemctl start $appCron.service"],
			'stopcmd' => ["systemctl stop $appCron.service", "systemctl disable $appCron.service"],
			'restartcmd' => "systemctl restart $appCron",
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/fedora/gte-14.0/",
			'req-serv' => 'systemctl',
			'base-conf-key' => 'lte-13.99',
			'serv-mod' => 'sd',
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
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/fedoracore/lt-7.00/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
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
			'startcmd' => "service $appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/freebsd/gte-11.0/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'rc',
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
			'startcmd' => "service $appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/gentoo/gte-1.0/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
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
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/linuxmint/gte-15.0/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sd',
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
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/manjarolinux/gte-0.8/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sd',
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
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/opensuse/lte-14.99/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
		},
		'gte-15.0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron.service" => "/usr/lib/systemd/system/$appCron.service"},
			'shellln' => {},
			'setupcmd' => ["systemctl unmask $appCron", "systemctl enable $appCron", "systemctl start $appCron"],
			'stopcmd' => ["systemctl stop $appCron", "systemctl disable $appCron"],
			'restartcmd' => "systemctl restart $appCron",
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/opensuse/gte-15.0/",
			'req-serv' => 'systemctl',
			'base-conf-key' => 'lte-14.99',
			'serv-mod' => 'sd',
		},
	},
	'raspbian' => {
		'gt-1.00' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {
				"idrivecron.service" => "/lib/systemd/system/$appCron.service"
			},
			'shellln' => {},
			'setupcmd' => ["systemctl enable $appCron", "systemctl start $appCron"],
			'stopcmd' => ["systemctl stop $appCron", "systemctl disable $appCron"],
			'restartcmd' => "systemctl restart $appCron",
			'startcmd' => "systemctl start $appCron",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/debian/gt-8.50/",
			'req-serv' => 'systemctl',
			'base-conf-key' => '',
			'serv-mod' => 'sd',
		},
	},
	'selinux' => {
		'gt-0' => {
			'pidpath' => $cronservicepid,
			'confappend' => {},
			'shellcp' => {"idrivecron" => "/etc/init.d/$appCron"},
			'shellln' => {},
			'setupcmd' => ["/etc/init.d/$appCron start"],
			'stopcmd' => ["/etc/init.d/$appCron stop"],
			'restartcmd' => "/etc/init.d/$appCron restart",
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/selinux/gt-0/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
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
			'startcmd' => "/etc/init.d/$appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/ubuntu/lte-9.04/",
			'req-serv' => '',
			'base-conf-key' => '',
			'serv-mod' => 'sv',
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
			'startcmd' => "service $appCron start",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/ubuntu/btw-9.10_14.10/",
			'req-serv' => 'service',
			'base-conf-key' => 'lte-9.04',
			'serv-mod' => 'ups',
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
			'startcmd' => "systemctl start $appCron.service",
			'launcherdecoy' => '__LAUNCHPATH__',
			'setupdir' => "$cronSetupPath/ubuntu/gte-15.00/",
			'req-serv' => 'systemctl',
			'base-conf-key' => 'lte-9.04',
			'serv-mod' => 'sd',
		},
	},
);

$cronLaunchCodes{'almalinux'} = $cronLaunchCodes{'centos'};
$cronLaunchCodes{'nobara'} = $cronLaunchCodes{'fedora'};
$cronLaunchCodes{'ol'} = $cronLaunchCodes{'centos'};
$cronLaunchCodes{'pop'} = $cronLaunchCodes{'ubuntu'};
$cronLaunchCodes{'rocky'} = $cronLaunchCodes{'centos'};
$cronLaunchCodes{'zorin'} = $cronLaunchCodes{'ubuntu'};

our %pmDNFPacksFed34 = ('File::Copy' => 'perl-File-Copy', 'Sys::Hostname' => 'perl-Sys-Hostname', 'Tie::File' => 'perl-Tie-File');

our %depInstallUtils = (
	'archlinux' => {
		'pkg-install' => ["pacman --noconfirm -S unzip curl"],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => '',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBI'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install YAML'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'could not resolve|failed to retrieve|download library error',
		'rollback' => [],
	},
	'centos' => {
		'pkg-install' => [
			"yum -y groupinstall 'Development Tools'",
			"yum -y install gcc",
			"yum -y install unzip",
			"yum -y install curl",
			"yum -y install automake",
			"yum -y install perl-CPAN",
			"yum -y install perl-DBI",
			"yum -y install perl-DBD-SQLite",
			"yum -y install perl-Time-HiRes",
			"yum -y install perl-YAML",
		],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => 'yum groups mark|trying other mirror|no packages in any requested group|listed more than once|synchronize cache|valueerror|header v3 dsa signature|already installed|no match|no installed groups',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {
			'lt-6' => ["__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple' < \"__APP_PATH__/$cpanSetupPath/centos/lt-6.00/cpan.conf\""],
			'btw-6.00_6.99' => ["yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple'"],
			'gte-7' => ["__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple' < \"__APP_PATH__/$cpanSetupPath/centos/gte-7/cpan.conf\""],
		},
		'cpan-install' => [
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBI'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'could not resolve|valid baseurl for repo',
		'rollback' => [],
	},
	'debian' => {
		'pkg-install' => [
			"apt-get -y install unzip",
			"apt-get -y install curl",
			"apt-get -y install sqlite3",
			"apt-get -y install build-essential",
			"apt-get -y install perl-doc",
		],
		'pkg-sil-append-cmd' => 'export DEBIAN_FRONTEND=noninteractive',
		'pkg-err-ignore' => 'dpkg-preconfigure|extracting templates',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'insert the disk|404 not found|failed to fetch|could not resolve|unable to fetch',
		'rollback' => [],
	},
	'fedora' => {
		'pkg-install' => [
			"yum -y groupinstall 'Development Tools'",
			"yum -y install unzip",
			"yum -y install curl",
			"yum -y install automake",
			"yum -y install cronie",
			"yum -y install perl-CPAN",
			"yum -y install perl-DBI",
			"yum -y install perl-DBD-SQLite",
			"yum -y install perl-Time-HiRes",
			"yum -y install perl-YAML",
		],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => 'yum groups mark|trying other mirror|no packages in any requested group|listed more than once|synchronize cache|valueerror|header v3 dsa signature|already installed|no match|no installed groups|importing gpg key',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'could not resolve|valid baseurl for repo|synchronize cache for repo|resolve hostname for',
		'rollback' => [],
	},
	'fedoracore' => {
		'pkg-install' => [
			"yum -y groupinstall 'Development Tools'",
			"yum -y install unzip",
			"yum -y install curl",
			"yum -y install perl-DBI",
			"yum -y install perl-DBD-SQLite",
			"yum -y install inotify-tools",
			"yum -y install perl-Module-Load-Conditional",
			"yum -y install perl-core",
		],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => 'yum groups mark|trying other mirror|no packages in any requested group|listed more than once|synchronize cache|valueerror|header v3 dsa signature|already installed|no match|no installed groups',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {
			'lt-7' => ["__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple' < \"__APP_PATH__/$cpanSetupPath/fedoracore/lt-7.00/cpan.conf\""],
		},
		'cpan-install' => [
			"__CPAN_AUTOINSTALL__ PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install DBI'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install IO::Socket'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'could not resolve|valid baseurl for repo',
		'rollback' => [],
	},
	'freebsd' => {
		'pkg-install' => [
			# "pkg install -y binutils",
			# "pkg install -y gcc",
			# "pkg install -y autoconf",
			# "pkg install -y automake",
			"pkg install -y unzip",
			"pkg install -y curl",
			"pkg install -y sqlite3",
			"pkg install -y libdbi",
			"pkg install -y p5-DBD-SQLite",
			# "pkg install -y libyaml",
			# "pkg install -y libcyaml",
			# "pkg install -y p5-yaml",
			# "pkg install -y libtool",
			# "pkg install -y inotify-tools",
			# "pkg install -y libinotify",
			# "pkg install -y p5-Filesys-notify-KQueue",
		],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => 'no packages available',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			# "yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple'",
			# "__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install ExtUtils::MakeMaker'",
			# "__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			# "__CPAN_AUTOINSTALL__ cpan -T Linux::Inotify2",
		],
		'pkg-repo-error' => 'could not resolve|unable to update repo|error updating repo',
		'rollback' => [],
	},
	'gentoo' => {
		'pkg-install' => [],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => '',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBI'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => '',
		'rollback' => [],
	},
	'linuxmint' => {
		'pkg-install' => [
			"apt-get -y install unzip",
			"apt-get -y install curl",
			"apt-get -y install build-essential",
			"apt-get -y install sqlite3",
			"apt-get -y install perl-doc",
			"apt-get -y install libdbi-perl",
			"apt-get -y install libdbd-sqlite3-perl",
		],
		'pkg-sil-append-cmd' => 'export DEBIAN_FRONTEND=noninteractive',
		'pkg-err-ignore' => '',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => '404 not found|failed to fetch|could not resolve|unable to fetch',
		'rollback' => [],
	},
	'manjarolinux' => {
		'pkg-install' => ["pacman --noconfirm -S unzip curl"],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => '',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBI'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install YAML'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Test::Simple'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'could not resolve|failed to retrieve|download library error',
		'rollback' => [],
	},
	'opensuse' => {
		'pkg-install' => [
			"zypper --non-interactive refresh",
			"zypper --non-interactive -t install unzip",
			"zypper --non-interactive -t install curl",
			"zypper --non-interactive -t install gcc",
			"zypper --non-interactive -t install make",
			"zypper --non-interactive -t install pattern",
			"zypper --non-interactive -t install devel_C_C++",
		],
		'pkg-sil-append-cmd' => '',
		'pkg-err-ignore' => 'no provider of',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBI'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'could not resolve|404 not found|does not contain the desired',
		'rollback' => [],
	},
	'raspbian' => {
		'pkg-install' => [
			"apt-get -y install unzip",
			"apt-get -y install curl",
			"apt-get -y install build-essential",
			"apt-get -y install perl-doc",
			"apt-get -y install sqlite3",
			"apt-get -y install libdbi-perl",
			"apt-get -y install libdbd-sqlite3-perl",
		],
		'pkg-sil-append-cmd' => 'export DEBIAN_FRONTEND=noninteractive',
		'pkg-err-ignore' => 'dpkg-preconfigure|extracting templates',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install DBD::SQLite'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => 'insert the disk|404 not found|failed to fetch|could not resolve|unable to fetch',
		'rollback' => [],
	},	
	'ubuntu' => {
		'pkg-install' => [
			"apt-get -y install unzip",
			"apt-get -y install curl",
			"apt-get -y install build-essential",
			"apt-get -y install sqlite3",
			"apt-get -y install perl-doc",
			"apt-get -y install libdbi-perl",
			"apt-get -y install libdbd-sqlite3-perl",
		],
		'pkg-sil-append-cmd' => 'export DEBIAN_FRONTEND=noninteractive',
		'pkg-err-ignore' => 'dpkg-preconfigure|extracting templates',
		'cpan-append-cmd' => "PERL_AUTOINSTALL='--defaultdeps'",
		'cpan-conf' => {},
		'cpan-install' => [
			"yes | __CPAN_AUTOINSTALL__ perl -MCPAN -e 'install common::sense'",
			"__CPAN_AUTOINSTALL__ perl -MCPAN -e 'install Linux::Inotify2'",
		],
		'pkg-repo-error' => '404 not found|failed to fetch|could not resolve|unable to fetch',
		'rollback' => [],
	},
);

$depInstallUtils{'almalinux'} = $depInstallUtils{'fedora'};
$depInstallUtils{'nobara'} = $depInstallUtils{'fedora'};
$depInstallUtils{'ol'} = $depInstallUtils{'centos'};
$depInstallUtils{'pop'} = $depInstallUtils{'ubuntu'};
$depInstallUtils{'rocky'} = $depInstallUtils{'centos'};
$depInstallUtils{'zorin'} = $depInstallUtils{'ubuntu'};

our $cmdInotifySrcComp = [
	"perl Makefile.PL",
	"make",
	"make test",
	"make install"
];

our %inotifyCompiled = (
	'archlinux' => {
		'gt-0.8' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/manjarolinux/gt-0.8/__ARCH__/",
		},
	},
	'centos' => {
		'lt-7.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/centos/lt-7.00/__ARCH__/",
		},
		'gte-7.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/centos/gte-7.00/__ARCH__/",
		},
	},
	'debian' => {
		'lt-6.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__SITEPERL_ARCH_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/debian/lt-6.00/__ARCH__/",
		},
		'gte-6.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__SITEPERL_ARCH_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/debian/gte-6.00/__ARCH__/",
		},
	},
	'fedora' => {
		'lte-13.99' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/fedora/lte-13.99/__ARCH__/",
		},
		'gte-14.0' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/fedora/gte-14.0/__ARCH__/",
		},
	},
	'fedoracore' => {
		'lt-7.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/fedoracore/lt-7.00/__ARCH__/",
		},
	},
	# 'freebsd' => {
		# 'gte-11.0' => {
			# 'append' => {
				# "linux__inotify2.pod" => {
					# 'file' => '__ARCHLIB_PATH__/perllocal.pod',
					# 'verify' => 'Linux::Inotify2',
				# },
			# },
			# 'copy' => {
				# "Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				# "Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				# "Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
				# "Linux::Inotify2.3" => '__MAN3_SITE__/Linux::Inotify2.3',
			# },
			# 'create' => {
				# '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					# '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					# '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					# '__MAN3_SITE__/Linux::Inotify2.3pm'
				# ],
			# },
			# 'setupdir' => "$inotifyBuiltPath/freebsd/gte-11.0/__ARCH__/",
		# },
	# },
	'gentoo' => {
		'gte-1.0' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_SITE__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_SITE__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/gentoo/gte-1.0/__ARCH__/",
		},
	},
	'linuxmint' => {
		'gte-5.0' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__SITEPERL_ARCH_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_SITE__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_SITE__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/linuxmint/gte-5.0/__ARCH__/",
		},
	},
	'manjarolinux' => {
		'gt-0.8' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/manjarolinux/gt-0.8/__ARCH__/",
		},
	},
	'opensuse' => {
		'lte-14.99' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/opensuse/lte-14.99/__ARCH__/",
		},
		'gte-15.0' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__ARCHLIB_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/opensuse/gte-15.0/__ARCH__/",
		},
	},
	'raspbian' => {
		'gte-1.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__SITEPERL_ARCH_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/debian/gte-6.00/__ARCH__/",
		},
	},
	'ubuntu' => {
		'lt-10.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__SITEPERL_ARCH_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/ubuntu/lt-10.00/__ARCH__/",
		},
		'gte-10.00' => {
			'append' => {
				"linux__inotify2.pod" => {
					'file' => '__SITEPERL_ARCH_PATH__/perllocal.pod',
					'verify' => 'Linux::Inotify2',
				},
			},
			'copy' => {
				"Inotify2.so" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
				"Inotify2.bs" => '__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
				"Inotify2.pm" => '__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
				"Linux::Inotify2.3pm" => '__MAN3_PATH__/Linux::Inotify2.3pm',
			},
			'create' => {
				'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/.packlist' => [
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.so',
					'__SITEPERL_ARCH_PATH__/auto/Linux/Inotify2/Inotify2.bs',
					'__SITEPERL_ARCH_PATH__/Linux/Inotify2.pm',
					'__MAN3_PATH__/Linux::Inotify2.3pm'
				],
			},
			'setupdir' => "$inotifyBuiltPath/ubuntu/gte-10.00/__ARCH__/",
		},
	},
);

$inotifyCompiled{'ol'} = $inotifyCompiled{'centos'};
$inotifyCompiled{'pop'} = $inotifyCompiled{'ubuntu'};
$inotifyCompiled{'rocky'} = $inotifyCompiled{'centos'};

our %idriveScripts = (
	'account_settings'				=> 'account_setting.pl',
	'archive_cleanup'				=> 'archive_cleanup.pl',
	'backup_scripts'				=> 'Backup_Script.pl',
	'check_for_update'				=> 'check_for_update.pl',
	'appconfig'						=> 'AppConfig.pm',
	'configuration'					=> 'Configuration.pm',
	'constants'						=> 'Constants.pm',
	'cron'							=> 'cron.pl',
	'cdp_client'					=> 'cdp_client.pl',
	'cdp_server'					=> 'cdp_server.pl',
	'dashboard'						=> 'dashboard.pl',
	'edit_supported_files'			=> 'edit_supported_files.pl',
	'local_backup'				    => 'local_backup.pl',
	'local_restore'				    => 'local_restore.pl',
	'header'						=> 'Header.pl',
	'common'						=> 'Common.pm',
	'helpers'						=> 'Helpers.pm',
	'ixhash'						=> 'IxHash.pm',
	'installcron'					=> 'installcron.pl',
	'job_termination'				=> 'job_termination.pl',
	'json'							=> 'JSON.pm',
	'login'							=> 'login.pl',
	'logout'						=> 'logout.pl',
	'operations'					=> 'Operations.pl',
	'utility'						=> 'utility.pl',
	'readme'						=> 'readme.txt',
	'restore_script'				=> 'Restore_Script.pl',
	'restore_version'				=> 'restore_version.pl',
	'scheduler_script'				=> 'scheduler.pl',
	'send_error_report'				=> 'send_error_report.pl',
	'status_retrieval'      		=> 'status_retrieval.pl',
	'strings'						=> 'Strings.pm',
	'uninstallcron'					=> 'uninstallcron.pl',
	'uninstall_script'				=> 'Uninstall_Script.pl',
	'view_log'                      => 'logs.pl',
	'deprecated_account_settings'	=> 'Account_Setting.pl',
	'deprecated_check_for_update'	=> 'Check_For_Update.pl',
	'deprecated_edit_suppor_files'	=> 'Edit_Supported_Files.pl',
	'deprecated_login'				=> 'Login.pl',
	'deprecated_restore_version'	=> 'Restore_Version.pl',
	'deprecated_view_log'			=> 'View_Log.pl',
	'deprecated_logout'				=> 'Logout.pl',
	'deprecated_relinkcron'			=> 'relinkcron.pl',
	'deprecated_strings'          => 'Strings.pm',
	'deprecated_configuration'    => 'Configuration.pm',
	'deprecated_viewlog'          => 'view_log.pl',
	'deprecated_helpers'          => 'Helpers.pm',
	'deprecated_scheduler_script' => 'Scheduler_Script.pl',
	'deprecated_status_retrieval' => 'Status_Retrieval_Script.pl',
	'deprecated_dashboard'        => 'dashboard.pl',
    'deprecated_express_backup'	  => 'express_backup.pl',
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
	'LocalBackupOp'      => 'LocalBackup',
	'LocalRestoreOp' 	 => 'LocalRestore',
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
	"Invalid device id",
	"not enough free space on device",
	"Unable to proceed as device is deleted/removed",
);

our @errorArgumentsRetry = (
   "Connection timed out",
   "io timeout",
   "Operation timed out",
   "nodename nor servname provided, or not known",
   "Name or service not known",
   "failed to connect",
   "Connection reset",
   "connection unexpectedly closed",
   "user information not found",
   "failed to get the host name",
   "unauthorized user",
);

our @errorListForMinimalRetry = (
	'Connection refused',
	'failed verification -- update retained',
	'unauthorized user',
	'user information not found',
	'Name or service not known',
);

our @errorLogoutArgs = (
	'encryption verification failed',
	'account is under maintenance',
	'account has been cancelled',
	'account has been expired',
	'account has been blocked',
	'password mismatch',
	'failed to get the device information',
	'invalid device id',
	'unable to proceed as device is deleted/removed',
);

our %statusHash = 	(
	COUNT_FILES_INDEX => 0,
	SYNC_COUNT_FILES_INDEX => 0,
	ERROR_COUNT_FILES => 0,
	FAILEDFILES_LISTIDX => 0,
	EXIT_FLAG => 0,
	FILES_COUNT_INDEX => 0,
	DENIED_COUNT_FILES => 0,
	MISSED_FILES_COUNT => 0,
	FAILED_COUNT_FILES_INDEX => 0,
    MODIFIED_FILES_COUNT => 0,
);

our %errorDetails = (
	100 => 'logout_&_login_&_try_again',
	101 => 'your_account_not_configured_properly',
	102 => 'login_&_try_again',
	103 => 'your_account_not_configured_properly_reconfigure',
	104 => 'account_not_configured',
	105 => 'unable_to_find_your_backup_location',
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
				'version' => '1.0.2.10',
				'release_date' => '31/JAN/2023',
				},
		'idevsutil_dedup' => {
				'version' => '2.0.0.3',
				'release_date' => '10/NOV/2022',
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
