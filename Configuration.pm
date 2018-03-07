package Configuration;
use strict;
use warnings;

use lib substr(__FILE__, 0, rindex(__FILE__, '/'));
use IxHash;

our $version       = '2.13';
our $displayHeader = 1;
our $appType       = 'IDrive';

our $hostname = `hostname`;
chomp($hostname);

our $callerEnv = 'USER';

our $evsBinaryName      = 'idevsutil';
our $evsDedupBinaryName = 'idevsutil_dedup';
our $utf8File           = 'utf8.cmd';

our @dependencyBinaries = ('unzip', 'curl');

our $servicePathName     = 'idrive';
our $serviceLocationFile = '.serviceLocation';
our $updateVersionInfo   = '.updateVersionInfo';

our $cachedFile            = 'cache/user.txt';
our $userProfilePath       = 'user_profile';
our $userInfoPath          = '.userInfo';
our $idpwdFile             = "$userInfoPath/IDPWD";
our $idenpwdFile           = "$userInfoPath/IDENPWD";
our $idpwdschFile          = "$userInfoPath/IDPWD_SCH";
our $idpvtFile             = "$userInfoPath/IDPVT";
our $idpvtschFile          = "$userInfoPath/IDPVT_SCH";
our $serverAddressFile     = "$userInfoPath/serverAddress.txt";
our $userConfigurationFile = 'CONFIGURATION_FILE';
our $quotaFile             = '.quota.txt';
our $downloadsPath         = 'downloads';
our $tmpPath               = 'tmp';

our $isUserConfigModified  = 0;

our $deviceIDPrefix = '5c0b';
our $deviceIDPostfix= '4b5z';

our %userProfilePaths = (
	'manual_backup'     => 'Backup/Manual',
	'scheduled_backup'  => 'Backup/Scheduled',
	'manual_restore'    => 'Restore/Manual',
	'scheduled_restore' => 'Restore/Scheduled',
	'user_info'         => '.userInfo',
	'restore_data'      => 'Restore_Data',
	'manual_localBackup'=> 'LocalBackup/Manual',
);

our $screenSize = `stty size`;

our $userConfChanged = 0;

our $evsDownloadsPage = "https://www.__APPTYPE__.com/downloads/linux/download-options__EVSTYPE__";

our $IDriveAuthCGI = "https://www1.idrive.com/cgi-bin/v1/user-details.cgi?";
our $IBackupAuthCGI = "https://www1.ibackup.com/cgi-bin/get_ibwin_evs_details_xml_ip.cgi?";

our %evsZipFiles = (
	'32' => ['__APPTYPE___linux_32bit.zip', '__APPTYPE___QNAP_32bit.zip'],
	'64' => ['__APPTYPE___linux_64bit.zip', '__APPTYPE___QNAP_64bit.zip',
						'__APPTYPE___synology_64bit.zip', '__APPTYPE___Netgear_64bit.zip',
						'__APPTYPE__Vault_64bit.zip'],
	'arm' => ['__APPTYPE___QNAP_ARM.zip', '__APPTYPE___synology_ARM.zip',
						'__APPTYPE___Netgear_ARM.zip'],
	'x' => ['__APPTYPE___linux_universal.zip'],
);

# We know that 32 bit works on 64 bit machines, so we give it a try
# when 64 bit binaries fails to work on the same machine.
$evsZipFiles{'64'} = [@{$evsZipFiles{'64'}}, @{$evsZipFiles{'32'}}];

tie (our %availableJobsSchema, 'Tie::IxHash',
	'manual_backup' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_backup'}/BackupsetFile.txt",
	},
	'scheduled_backup' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_backup'}/BackupsetFile.txt",
	},
	'manual_restore' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_restore'}/RestoresetFile.txt",
	},
	'scheduled_restore' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'scheduled_restore'}/RestoresetFile.txt",
	},
	'manual_localBackup' => {
		'file' => "__SERVICEPATH__/$userProfilePath/__USERNAME__/$userProfilePaths{'manual_localBackup'}/BackupsetFile.txt",
	},	
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

our %evsAPIPatterns = (
	'GETQUOTA' => "--get-quota\n__getUsername__\@__getServerAddress__::home/",
	'STRINGENCODE' => "--string-encode=__ARG1__\n--out-file=__ARG2__",
	'VALIDATE' => "--validate\n--user=__ARG1__\n--password-file=__ARG2__",
	'GETSERVERADDRESS' => "--getServerAddress\n__getUsername__",
	'CREATEBUCKET' => "--xml-output\n--create-bucket\n--nick-name=__ARG1__\n--os=Linux\n--uid=__getMachineUID__\n--bucket-type=D\n__getUsername__\@__getServerAddress__::home/",
	'LISTDEVICE' => "--xml-output\n--list-device\n__getUsername__\@__getServerAddress__::home/",
	'NICKUPDATE' => "--xml-output\n--nick-update\n--nick-name=__ARG1__\n--os=Linux\n--device-id=__ARG2__\n__getUsername__\@__getServerAddress__::home/",
	'LINKBUCKET' => "--xml-output\n--link-bucket\n--nick-name=__ARG1__\n--os=Linux\n__getUsername__\@__getServerAddress__::home/\n--device-id=$deviceIDPrefix\_\_ARG2\_\_$deviceIDPostfix\n--uid=__ARG3__\n--bucket-type=D",
	'DEFAULTCONFIG' => "--config-account\n--user=__getUsername__\n--enc-type=DEFAULT",
	'PRIVATECONFIG' => "--config-account\n--user=__getUsername__\n--enc-type=PRIVATE",
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
		'type' => 'dir',
	},
	'RETAINLOGS' => {
		'cgi_name' => '',
		'evs_name' => '',
		'required' => 1,
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
		'required' => 1,
		'default'  => '',
		'type' => 'regex',
	},
#	'ENCRYPTIONTYPE' => {
#		'cgi_name' => 'enctype',
#		'evs_name' => 'configtype',
#		'required' => 1,
#		'default'  => '',
#		'type' => 'regex',
#	},
#	'USERCONFSTAT' => {
#		'cgi_name' => 'cnfgstat',
#		'evs_name' => 'configstatus',
#		'required' => 1,
#		'default'  => '',
#		'type' => 'regex',
#	}
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
1;
