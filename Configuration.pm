package Configuration;
use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')); } else { use lib '.'; }

use IxHash;

our $version       = '2.16';
our $displayHeader = 1;
our $appType       = 'IDrive';

our $hostname = `hostname`;
chomp($hostname);

our $callerEnv = 'USER';

our $perlBin = $ENV{'_'} || '';
if ($perlBin =~ /\.pl$/) {
	$perlBin = '/usr/bin/perl';
} else {
	$perlBin = 'perl';
}
our $evsBinaryName      = 'idevsutil';
our $evsDedupBinaryName = 'idevsutil_dedup';
our $utf8File           = 'utf8.cmd';

our ($machineOS,$freebsdProgress);		
our $deviceType      = 'LINUX';
our $evsVersion      = 'evs003';
our $NSPort          = 443;
our $idriveLoginCGI  = 'https://www.idrive.com/idrive/viewjsp/RemoteLogin.jsp';

our $deviceIDPrefix = '5c0b';
our $deviceIDPostfix= '4b5z';

our @dependencyBinaries = ('unzip', 'curl');

our $servicePathName     = 'idrive';
our $serviceLocationFile = '.serviceLocation';
our $updateVersionInfo   = '.updateVersionInfo';
our $forceUpdateFile	 = '.forceupdate';

our $cachedFile            = 'cache/user.txt';
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
our $traceLogDir		   = '.trace';
our $traceLogFile		   = 'traceLog.txt';
our $maxLogSize			   = 2 * 1024 * 1024;
our $maxChoiceRetry 	   = 3;
our $reportMaxMsgLength	   = 1024;
our $bufferLimit	   	   = 2*1024;

our $searchDir			   = 'Search';
our $evsOutputFile		   = 'evsOutput.txt';
our $evsErrorFile		   = 'evsError.txt';
our $versionRestoreFile		= 'versionRestoresetFile.txt';

our $unzipLog				= 'unzipLog.txt';
our $updateLog				= '.updateLog.txt';
our $freshInstall			= 'freshInstall';

our $isUserConfigModified  = 0;
our $backupsetFile  	   = 'BackupsetFile.txt';
our $tempBackupsetFile	   = 'tempBackupsetFile.txt';

our $archiveFileListForView  = 'archiveFileListForView.txt';
our $archiveFileResultFile   = 'archiveFileResult.txt';
our $archiveFolderResultFile = 'archiveFolderResult.txt';

our $errorFile       = 'error.txt';
our $evsTempDir      = 'evs_temp';
our $statusFile      = 'STATUS_FILE';
our $infoFile        = 'infoFile';
our $fileForSize     = 'TotalSizeFile';
our $excludeDir      = 'Excluded';
our $errorDir 		 = 'ERROR';
our $pidFile 		 = 'pid.txt';
our $excludedLogFile = 'excludedItemsLog.txt';
our $mountPointFile  = 'mountPoint.txt';
our $trfSizeAndCountFile = 'trfSizeAndCount.txt';
our $progressDetailsFilePath = 'PROGRESS_DETAILS_BACKUP';
our $retryInfo = "RetryInfo.txt";
our $failedFileName = "failedFiles.txt";
our $relativeFileset = "BackupsetFile_Rel";
our $filesOnly = "BackupsetFile_filesOnly";
our $noRelativeFileset = "BackupsetFile_NoRel";
our $transferredFileSize = 'transferredFileSize.txt';
our $operationsfile  = 'operationsfile.txt';
our $fileSummaryFile = 'fileSummary.txt';
our $pidTestFlag  =  0;
our $pidOutputProcess = undef;
our $status = "SUCCESS";
our $opStatus = "SUCCESS";
our ($jobRunningDir,$outputFilePath,$errorFilePath,$mailContentHead) = ('') x 4;
our ($mailContent,$jobType,$expressLocalDir,$errStr,$finalSummery) = ('') x 5;
our ($fullStr,$parStr,$regexStr) = ('') x 3;
our ($excludedCount,$noRelIndex,$excludedFileIndex,$filesonlycount,$nonExistsCount,$retryCount,$cancelFlag) = (0) x 7;
our $totalFiles = 0;
our @linesStatusFile = undef;

our $filePermission  	= 0777;
our $filePermissionStr 	= "0777";
our $prevTime = time();

our $inputMandetory = 0;

our $accessTokenFile = 'accesstoken.txt';
our $notificationFile = 'notification.json';

our $logStatFile = 'logstat.json';

our $crontabFile = 'crontab.json';

our %userProfilePaths = (
	'manual_archive'    => 'Archive/Manual',
	'periodic_archive'  => 'Archive/Scheduled',
	'manual_backup'     => 'Backup/Manual',
	'scheduled_backup'  => 'Backup/Scheduled',
	'manual_restore'    => 'Restore/Manual',
	'scheduled_restore' => 'Restore/Scheduled',
	'user_info'         => '.userInfo',
	'restore_data'      => 'Restore_Data',
	'manual_localBackup'=> 'LocalBackup/Manual',
	'trace'         	=> '.trace',
	'tmp'         		=> 'tmp',
);

our $screenSize = `stty size`;

our $userConfChanged = 0;

#our $evsDownloadsPage = "https://www.__APPTYPE__.com/downloads/linux/download-options__EVSTYPE__";
our $evsDownloadsPage = "https://www.__APPTYPE__.com/downloads/linux/download-options";
our $IDriveAuthCGI = "https://www1.idrive.com/cgi-bin/v1/user-details.cgi";
our $IBackupAuthCGI = "https://www1.ibackup.com/cgi-bin/get_ibwin_evs_details_xml_ip.cgi?";
our $IDriveErrorCGI = 'https://webdav.ibackup.com/cgi-bin/Notify_unicode';
our $checkUpdateBaseCGI = "\"https://www1.ibackup.com/cgi-bin/check_version_upgrades_idrive_evs_new.cgi?appln=${appType}ForLinux&version=$version\"";
our $IDriveSupportEmail = 'support@idrive.com';
our $notifyPath = 'http://webdav.ibackup.com/cgi-bin/Notify_email_ibl';

# production download URL
my $IDriveAppUrl 	= "https://www.idrivedownloads.com/downloads/linux/download-for-linux/IDriveForLinux.zip";
# SVN download URL
#my $IDriveAppUrl 	= " -u deepak:deepak http://192.168.2.169/svn/linux_repository/trunk/PackagesForTesting/IDriveForLinux/IDriveForLinux.zip";

# production download URL
my $IBackupAppUrl 	= "https://www.ibackup.com/online-backup-linux/downloads/download-for-linux/IBackup_for_Linux.zip";
# SVN download URL
#my $IBackupAppUrl 	= " -u deepak:deepak http://192.168.2.169/svn/linux_repository/trunk/PackagesForTesting/IBackupForLinux/IBackup_for_Linux.zip";
my $IDriveUserInoCGIUrl 	=  "https://www1.idrive.com/cgi-bin/update_user_device_info.cgi?";
my $IBackupUserInoCGIUrl 	=  "https://www1.ibackup.com/cgi-bin/update_user_device_info.cgi?";

our $appDownloadURL = ($appType eq 'IDrive')? $IDriveAppUrl : $IBackupAppUrl;
our $appPackageName = $appType . 'ForLinux';
our $appPackageExt	= '.zip';
our $IDriveUserInoCGI  =  ($appType eq 'IDrive')? $IDriveUserInoCGIUrl : $IBackupUserInoCGIUrl;

our %evsZipFiles = (
	'32' => ['__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___Vault_64bit.zip', '__APPTYPE___Netgear_64bit.zip'],
	'64' => ['__APPTYPE___linux_64bit.zip', '__APPTYPE___QNAP_64bit.zip', '__APPTYPE___synology_64bit.zip', '__APPTYPE___Netgear_64bit.zip', '__APPTYPE___Vault_64bit.zip','__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip' ],

	'arm' => ['__APPTYPE___QNAP_ARM.zip', '__APPTYPE___synology_ARM.zip',
						'__APPTYPE___Netgear_ARM.zip', '__APPTYPE___synology_Alpine.zip'],
	'x' => ['__APPTYPE___linux_universal.zip'],
);

# We know that 32 bit works on 64 bit machines, so we give it a try
# when 64 bit binaries fails to work on the same machine.
#$evsZipFiles{'64'} = [@{$evsZipFiles{'64'}}, @{$evsZipFiles{'32'}}];

tie (our %availableJobsSchema, 'Tie::IxHash',
	'manual_backup' => {
		'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_backup'}/",
		'logs' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_backup'}/$logDir",
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_backup'}/BackupsetFile.txt",
	},
	'scheduled_backup' => {
		'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_backup'}/",
		'logs' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_backup'}/$logDir",
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_backup'}/BackupsetFile.txt",
	},
	'manual_restore' => {
		'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_restore'}/",
		'logs' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_restore'}/$logDir",
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_restore'}/RestoresetFile.txt",
	},
	'scheduled_restore' => {
		'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_restore'}/",
		'logs' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_restore'}/$logDir",
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_restore'}/RestoresetFile.txt",
	},
	'manual_localBackup' => {
		'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_localBackup'}/",
		'logs' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_localBackup'}/$logDir",
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_localBackup'}/BackupsetFile.txt",
	},
	'manual_archive' => {
		'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_archive'}/",
		'logs' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_archive'}/$logDir",
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_archive'}/BackupsetFile.txt",
	},
	'periodic_archive' => {
		'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'periodic_archive'}/",
		'logs' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'periodic_archive'}/$logDir",
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'periodic_archive'}/BackupsetFile.txt",
	},	
);

tie (our %logMenuAndPaths, 'Tie::IxHash',
	'backup' => {
		'view_logs_for_manual_backup' => {
			'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_backup'}/LOGS/",
		},
		'view_logs_for_scheduled_backup' => {
			'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_backup'}/LOGS/",
		}
	},
	'express_backup' => {
		'view_logs_for_express_backup' => {
			'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_localBackup'}/LOGS/",
		}
	},
	'restore' => {
		'view_logs_for_manual_restore' => {
			'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_restore'}/LOGS/",
		},
		'view_logs_for_scheduled_restore' => {
			'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_restore'}/LOGS/",
		}
	},
	'archive' => {
		'view_logs_for_manual_cleanup' => {
			'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_archive'}/LOGS/",
		},
		'view_logs_for_periodic_cleanup' => {
			'path' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'periodic_archive'}/LOGS/",
		}
	}
);

tie (our %excludeFilesSchema, 'Tie::IxHash',
	'full_exclude' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/FullExcludeList.txt",
	},
	'partial_exclude' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/PartialExcludeList.txt",
	},
	'regex_exclude' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/RegexExcludeList.txt",
	},
);

tie (our %editFileOptions, 'Tie::IxHash', 
	'backup' => {
		'manual_backup' => $availableJobsSchema{'manual_backup'}{'file'},
		'scheduled_backup' => $availableJobsSchema{'scheduled_backup'}{'file'},
	},
	'express_backup' => {
		'manual_localBackup' => $availableJobsSchema{'manual_localBackup'}{'file'},
	},
	'exclude' => {
		'full_exclude' => $excludeFilesSchema{'full_exclude'}{'file'},
		'partial_exclude' => $excludeFilesSchema{'partial_exclude'}{'file'},
		'regex_exclude' => $excludeFilesSchema{'regex_exclude'}{'file'},
	},
	'restore' => {
		'manual_restore' => $availableJobsSchema{'manual_restore'}{'file'},
		'scheduled_restore' => $availableJobsSchema{'scheduled_restore'}{'file'},
	}
);

our %evsAPIPatterns = (
	'GETQUOTA' => "--get-quota\n__getUsername__\@__getServerAddress__::home/",
	'STRINGENCODE' => "--string-encode=__ARG1__\n--out-file=__ARG2__",
	'VALIDATE' => "--validate\n--user=__ARG1__\n--password-file=__ARG2__",
	'GETSERVERADDRESS' => "--getServerAddress\n__getUsername__",
	'CREATEBUCKET' => "--xml-output\n--create-bucket\n--nick-name=__ARG1__\n--os=Linux\n--uid=__getMachineUID__\n--bucket-type=D\n__getUsername__\@__getServerAddress__::home/",
	'CREATEDIR' => "--xml-output\n--create-dir=__ARG1__\n__getUsername__\@__getServerAddress__::home/",
	'LISTDEVICE' => "--xml-output\n--list-device\n__getUsername__\@__getServerAddress__::home/",
	'NICKUPDATE' => "--xml-output\n--nick-update\n--nick-name=__ARG1__\n--os=Linux\n--device-id=__ARG2__\n__getUsername__\@__getServerAddress__::home/",
	'LINKBUCKET' => "--xml-output\n--link-bucket\n--nick-name=__ARG1__\n--os=Linux\n__getUsername__\@__getServerAddress__::home/\n--device-id=$deviceIDPrefix\__ARG2__$deviceIDPostfix\n--uid=__ARG3__\n--bucket-type=D",
	'DEFAULTCONFIG' => "--config-account\n--user=__getUsername__\n--enc-type=DEFAULT",
	'PRIVATECONFIG' => "--config-account\n--user=__getUsername__\n--enc-type=PRIVATE",
	'PING' => "__getUsername__\@__getServerAddress__::home/",
	'FILEVERSION'=> "--version-info\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG1__",
	'FILEVERSIONDEDUP'=> "--version-info\n--device-id=__ARG1__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG2__",
	'PINGDEDUP' => "--device-id=__ARG1__\n__getUsername__\@__getServerAddress__::home/",
	'SEARCH'=> "--search\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'SEARCHDEDUP'=> "--search\n--device-id=__ARG1__\n--o=__ARG2__\n--e=__ARG3__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG4__",
	'ITEMSTATUS'=> "--items-status\n--files-from=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/",
	'ITEMSTATUSDEDUP'=> "--items-status\n--device-id=__ARG1__\n--files-from=__ARG2__\n--e=__ARG3__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/",
	'PROPERTIES'=> "--properties\n--e=__ARG1__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG2__",
	'PROPERTIESDEDUP'=> "--properties\n--device-id=__ARG1__\n--e=__ARG2__\n--xml-output\n--file\n__getUsername__\@__getServerAddress__::home/__ARG3__", 
	'DELETE'=> "--delete-items\n--files-from=__ARG1__\n--o=__ARG2__\n--e=__ARG3__\n--xml-output\n__getUsername__\@__getServerAddress__::home/",
	'DELETEDEDUP'=> "--delete-items\n--device-id=__ARG1__\n--files-from=__ARG2__\n--o=__ARG3__\n--e=__ARG4__\n--xml-output\n__getUsername__\@__getServerAddress__::home/",
	'AUTHLIST'=> "--auth-list\n--o=__ARG1__\n--e=__ARG2__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG3__",
	'AUTHLISTDEDUP'=> "--auth-list\n--device-id=__ARG1__\n--o=__ARG2__\n--e=__ARG3__\n--xml-output\n__getUsername__\@__getServerAddress__::home/__ARG4__",
	'EXPRESSBACKUP'=> "--files-from=__ARG1__\n--bw-file=__ARG2__\n--type\n--def-local=__ARG3__\n--add-progress\n--xml-output\n--enc-opt\n__ARG4__\n--portable\n--no-versions\n--o=__ARG5__\n--e=__ARG6__\n--portable-dest=__ARG7__\n__ARG8__\n__getUsername__\@__getServerAddress__::home/__ARG9__",
	'EXPRESSBACKUPDEDUP'=> "--device-id=__ARG1__\n--files-from=__ARG2__\n--bw-file=__ARG3__\n--type\n--def-local=__ARG4__\n--add-progress\n--xml-output\n--enc-opt\n__ARG5__\n--portable\n--no-versions\n--o=__ARG6__\n--e=__ARG7__\n--portable-dest=__ARG8__\n__ARG9__\n__getUsername__\@__getServerAddress__::home/__ARG10__",
);

tie(our %userConfigurationSchema, 'Tie::IxHash',
	'USERNAME' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 1,
		'default'  => '',
		'type' => 'regex',
	},
	'EMAILADDRESS' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'BACKUPLOCATION' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 1,
		'default'  => '',
		'type' => 'regex',
	},
	'RESTOREFROM' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 1,
		'default'  => '',
		'type' => 'regex',
	},
	'RESTORELOCATION' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 1,
		'default'  => '',
		'type' => 'regex',			# to avoid restore directory exist validation for now
	},
	'RETAINLOGS' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 1,
		'default'  => '',
		'type' => 'regex',
	},
	'PROXYIP' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'PROXYPORT' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'PROXYUSERNAME' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'PROXYPASSWORD' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'PROXY' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'BWTHROTTLE' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => 100,
		'type' => 'regex',
	},
	'BACKUPTYPE' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => 'mirror',
		'type' => 'regex',
	},
	'DEDUP' => {
		'cgi_name' => 'dedup',
		'evs_name' => 'dedup',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'ENCRYPTIONTYPE' => {
		'cgi_name' => 'enctype',
		'evs_name' => 'configtype',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'USERCONFSTAT' => {
		'cgi_name' => 'cnfgstat',
		'evs_name' => 'configstatus',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'SERVERROOT' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type' => 'regex',
	},
	'REMOTEMANAGEIP' => {
		'cgi_name' => 'remote_manage_ip',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type'     => 'regex'
	},
	'LOCALBACKUPLOCATION' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 0,
		'default'  => '',
		'type'     => 'regex'
	}
);

tie(our %ServerAddressSchema, 'Tie::IxHash',
	'SERVERADDRESS' => {
		'cgi_name' => 'evssrvrip',
		'evs_name' => 'cmdUtilityServerIP',
		'required' => 1,
		'type' => 'regex',
	},
);

tie(our %accountStorageSchema, 'Tie::IxHash',
	'totalQuota' => {
		'cgi_name' => 'quota',
		'evs_name' => 'totalQuota',
		'required' => 1,
		'type' => 'regex',
		'func' => 'setTotalStorage',
	},
	'usedQuota' => {
		'cgi_name' => 'quota_used',
		'evs_name' => 'usedQuota',
		'required' => 1,
		'type' => 'regex',
		'func' => 'setStorageUsed',
	},
);

our %notificationsSchema = (
	'update_backup_progress' => '',
	'update_localbackup_progress' => '',
	'get_backupset_content' => '',
	'get_localbackupset_content' => '',
	'update_restore_progress' => '',
	'get_user_settings' => '',
	'crontab_content' => '',
	'get_logs' => '',
);

our %crontabSchema = (
	'm' => '0',                   # 0-59
	'h' => '0',                   # 0-23
	'dom' => '*',                 # (month) 1-31
	'mon' => '*',                 # 1-12
	'dow' => '*',                 # (week) mon,tue,wed,thu,fri,sat,sun
	'command' => '',              # command to execute
	'settings' => {
		'frequency' => 'daily',     # daily/weekly
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

our %idriveScripts = (
	'account_settings' 				=> 'account_setting.pl',
	'archive_cleanup'				=> 'archive_cleanup.pl',
	'backup_scripts' 				=> 'Backup_Script.pl',
	'check_for_update' 				=> 'check_for_update.pl',
	'configuration' 				=> 'Configuration.pm',
	'constants' 					=> 'Constants.pm',
	'edit_supported_files' 			=> 'edit_supported_files.pl',
	'express_backup' 				=> 'express_backup.pl',
	'header' 						=> 'Header.pl',
	'helpers' 						=> 'Helpers.pm',
	'ixhash' 						=> 'IxHash.pm',
	'job_termination' 				=> 'job_termination.pl',
	'json'							=> 'JSON.pm',
	'login' 						=> 'login.pl',
	'logout' 						=> 'Logout.pl',
	'operations' 					=> 'Operations.pl',
	'utility'						=> 'utility.pl',
	'readme' 						=> 'readme.txt',
	'restore_script' 				=> 'Restore_Script.pl',
	'restore_version' 				=> 'restore_version.pl',
	'scheduler_script' 				=> 'Scheduler_Script.pl',
	'send_error_report' 			=> 'send_error_report.pl',
	'status_retrieval_script' 		=> 'Status_Retrieval_Script.pl',
	'strings' 						=> 'Strings.pm',
	'uninstall_script' 				=> 'Uninstall_Script.pl',
	'view_log' 						=> 'view_log.pl',
	'deprecated_account_settings' 	=> 'Account_Setting.pl',
	'deprecated_check_for_update' 	=> 'Check_For_Update.pl',
	'deprecated_edit_suppor_files' 	=> 'Edit_Supported_Files.pl',
	'deprecated_login' 				=> 'Login.pl',
	'deprecated_restore_version' 	=> 'Restore_Version.pl',
	'deprecated_view_log' 			=> 'View_Log.pl',
);

our %evsOperations = (
	'LinkBucketOp' => 'LinkBucket',
	'NickUpdateOp' => 'NickUpdate',
	'ListDeviceOp' => 'ListDevice',
	'BackupOp' => 'Backup',
	'CreateBucketOp' => 'CreateBucket',
	'RestoreOp' => 'Restore',
	'ValidateOp' => 'Validate',
	'GetServerAddressOp' => 'GetServerAddress',
	'AuthListOp' => 'Authlist',
	'ConfigOp' => 'Config',
	'GetQuotaOp' => 'GetQuota',
	'PropertiesOp' => 'Properties',
	'CreateDirOp' => 'CreateDir',
	'SearchOp' => 'Search',
	'RenameOp' => 'Rename',
	'ItemStatOp' => 'ItemStatus',
	'VersionOp' => 'Version',
	'VerifyPvtOp' => 'VerifyPvtKey',		
	'validatePvtKeyOp' => 'validatePvtKey',
	'LocalBackupOp' => 'LocalBackup'
);

my %evsParameters = (
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
);

our @errorArgumentsExit = (
	"encryption verification failed",
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

our %statusHash = 	(	"COUNT_FILES_INDEX" => undef,
						"SYNC_COUNT_FILES_INDEX" => undef,
						"ERROR_COUNT_FILES" => undef,
						"FAILEDFILES_LISTIDX" => undef,
						"EXIT_FLAG" => undef,
					);
1;
