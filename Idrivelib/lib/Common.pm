#*****************************************************************************************************
# Most commonly used subroutines are placed here for re-use
#
# Created By  : Yogesh Kumar @ IDrive Inc
# Reviewed By : Deepak Chaurasia
#****************************************************************************************************/

package Common;
use strict;
use warnings;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(display retreat getRemoteAccessToken encryptString getParentRemoteManageIP getRemoteManageIP getUsername getParentUsername getMachineUser getServicePath getCatfile retreat request getUserConfiguration setUserConfiguration saveUserConfiguration loadCrontab createCrontab getCrontab getUserProfilePath setCrontab prettyPrint loadNotifications setNotification saveNotifications loadNS getNS saveNS deleteNS getFileContents);

use Cwd 'abs_path';
use POSIX qw(strftime);
use File::Spec::Functions;
use File::Basename;
use Scalar::Util qw(reftype looks_like_number);
use File::Path qw(rmtree);

eval {
	require File::Copy;
	File::Copy->import();
};

use File::stat;
use POSIX;
use Fcntl qw(:flock SEEK_END);
use IO::Handle;

use utf8;
use MIME::Base64;

eval {
	require Sys::Hostname;
	Sys::Hostname->import();
};

use AppConfig;
use JSON;

eval {
	require DBI;
	DBI->import();
};

eval {
	require Sqlite;
	Sqlite->import();
};

#use locale;
my $isEngEnabled = currentLocale();

# Locale Strings
my (%LS, %Help) = () x 2;
if ($AppConfig::language eq 'EN') {
	use Locale::EN;
	%LS   = %Locale::EN::strings;
	%Help = %Locale::EN::content;
}

use constant STATUS => 'STATUS';
use constant MSG => 'MSG';
use constant DATA => 'DATA';

# CRON STATUS
use constant CRON_NOTRUNNING => 0;
use constant CRON_STARTED => 1;
use constant CRON_RUNNING => 2;

my $appPath;
my $servicePath = '';
my $username = '';
my $evsBinary;
my $storageUsed;
my $totalStorage;
my $utf8File;
my $serverAddress;
my $machineHardwareName;
my $muid;
my $mipa;
my $errorDevNull = '2>>/dev/null';

my (%notifications, %modifiedNotifications, %ns);
our %crontab;
our $machineInfo;

use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";
use constant FILE_MAX_COUNT => 1000;

my ($relative,$BackupsetFile_new,$BackupsetFile_Only,$current_source);
my $filecount = 0;

my %backupExcludeHash = (); #Hash containing items present in Exclude List#
my ($totalSize,$prevFailedCount,$cols,$latestCulmn,$backupfilecount,$skippedItem) = (0) x 6;
my ($backupLocationDir,$summaryError,$summary) = ('') x 4;
my $lineFeed = "\n";
my @startTime;
tie(my %userConfiguration, 'Tie::IxHash');
my %modifiedUserConfig;
our ($percentToNotifyForFailedFiles, $percentToNotifyForMissedFiles);
our ($dbh_LB, $selectFolderID, $selectFileInfo, $selectAllFile, $searchAllFileByDir, $dbh_ibFile_insert, $dbh_ibFile_update, $dbh_ibFolder_insert, $dbh_ibFolder_update);

#------------------------------------------------- A -------------------------------------------------#

#*****************************************************************************************************
# Subroutine	: addFallBackCRONRebootEntry
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Adds and entry to system cron to handle reboot for fallback cron
# Added By		: Sabin Cheruvattil
# Modified By	:
#*****************************************************************************************************
sub addFallBackCRONRebootEntry {
	my $cturi		= `which crontab 2>/dev/null`;
	Chomp(\$cturi);

	return 0 unless($cturi);

	my $fbrecron	= getFallBackCRONRebootEntry();
	return 0 if(!$fbrecron);

	my $command		= qq((crontab -u root -l 2>/dev/null; echo "$fbrecron") | crontab -u root -);
	system($command);
}

#*****************************************************************************************************
# Subroutine			: addCDPWatcherToCRON
# Objective				: Add CDP watcher in cron service so that cron can start watcher during restart
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub addCDPWatcherToCRON {
	lockCriticalUpdate("cron");
	loadCrontab(1);
	my $curdashscript = getCrontab($AppConfig::cdpwatcher, $AppConfig::cdpwatcher, '{cmd}');
	if($_[0] || !$curdashscript) {
		createCrontab($AppConfig::cdpwatcher, $AppConfig::cdpwatcher);
		setCronCMD($AppConfig::cdpwatcher, $AppConfig::cdpwatcher);
		saveCrontab();
	}

	unlockCriticalUpdate("cron");
}

#*****************************************************************************************************
# Subroutine			: addBasicUserCRONEntires
# Objective				: Add basic entries for the user
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub addBasicUserCRONEntires {
	# Add CDP watcher to CRON
	addCDPWatcherToCRON(1);

	lockCriticalUpdate("cron");
	loadCrontab(1);

	if ($AppConfig::appType eq 'IDrive') {
		my $curdashscript = getCrontab($AppConfig::dashbtask, $AppConfig::dashbtask, '{cmd}');
		# account not configured | no cron tab entry | dashboard script empty
		if (!$curdashscript || !-f $curdashscript) {
			createCrontab($AppConfig::dashbtask, $AppConfig::dashbtask);
			setCronCMD($AppConfig::dashbtask, $AppConfig::dashbtask);
			saveCrontab();
		}
	}

	unlockCriticalUpdate("cron");

	setCDPRescanCRON($AppConfig::defrescanday, $AppConfig::defrescanhr, $AppConfig::defrescanmin, 1);
	
}

#*****************************************************************************************************
# Subroutine	: addToEditBackupsetHistory
# In Param		: Path | String
# Out Param		: Status | Boolean
# Objective		: Records history of backup set
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub addToEditBackupsetHistory {
	my $bkfpath	= $_[0];

	return 0 if(!$bkfpath || !-f $bkfpath);

	my $bkpdir	= dirname($bkfpath);
	my $histdir	= getCatfile($bkpdir, dirname($AppConfig::backupsethist));
	my $histf	= getCatfile($bkpdir, strftime($AppConfig::backupsethist, localtime()));

	createDir($histdir, 1) unless(-d $histdir);

	my $history	= strftime('%d/%m/%Y %H:%M:%S', localtime());
	$history	.= "\n\n" . getFileContents($bkfpath) . "\n\n";
	$history	.= "--" x 25;
	$history	.= "\n\n";

	fileWrite($histf, $history, 'APPEND');

	my @logs		= glob(qq(*.log));
	my $rmc			= scalar(@logs) - $AppConfig::maxbackuphist;
	while($rmc > 0) {
		unlink pop(@logs);
		$rmc--;
	}

	return 1;
}

#****************************************************************************************************
# Subroutine Name         : appendEndProcessInProgressFile.
# Objective               : This subroutine will append PROGRESS END string at the end of progress file.
# Modified By             : Abhishek Verma.
#*****************************************************************************************************/
sub appendEndProcessInProgressFile {
    open PROGRESS_DETAILS_FILE, ">>", $AppConfig::progressDetailsFilePath or return "";
	print PROGRESS_DETAILS_FILE "\nPROGRESS END";
    close PROGRESS_DETAILS_FILE;
}

#****************************************************************************************************
# Subroutine Name         : appendErrorFileContents
# Objective               : This subroutine appends the contents of the error file to the output file
#							and deletes the error file.
# Modified By             : Deepak Chaurasia, Senthil Pandian
#*****************************************************************************************************/
sub appendErrorFileContents
{
	my $errorDir = $_[0]."/";
	my $filesListCmd = updateLocaleCmd("ls '$errorDir'");
	my @files_list = `$filesListCmd`;
	my $fileopen = 0;
	my $proxyErr = 0;
    my $summaryError = '';

	chomp(@files_list);
	foreach my $file (@files_list) {
		chomp($file);
		if ( $file eq "." or $file eq "..") {
			next;
		}
		$file = $errorDir.$file;

		if (-s $file > 0){
			if ($fileopen == 0){
				$summaryError.=$lineFeed."[ERROR REPORT]".$lineFeed;
				$summaryError .= (('-') x 14).$lineFeed;
            }
			$fileopen = 1;
			open ERROR_FILE, "<", $file or traceLog(['failed_to_open_file', " $file. Reason $!"]);
			while(my $line = <ERROR_FILE>) {
				$summaryError.=$line;
				if ($line =~/.*(Proxy Authentication Required).*|.*(bad response from proxy).*/is){
					$proxyErr = 1;
				}
			}
			close ERROR_FILE;
		}
	}
	if ($proxyErr == 1){
		my $tokenMessage = $LS{'please_login_account_using_login_and_try'};
		#$tokenMessage =~ s/___login___/$AppConfig::idriveScripts{'login'}/eg;
		$summaryError = "\nProxy Authentication Required or bad response from proxy. ".$tokenMessage.$lineFeed;
		my $pwdPath = getIDPWDFile();
		unlink($pwdPath);
	}

    return $summaryError;
}

#*****************************************************************************************************
# Subroutine	: autoDetectENVProxy
# In Param		: UNDEF
# Out Param		: Hash
# Objective		: Detects saved proxy info in this machine
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub autoDetectENVProxy {
	my %proxies = ("http" => {}, "https" => "");
	my ($httpenvcmd, $httpproxy) = ('', '');

	foreach my $proto (keys %proxies) {
		$httpenvcmd = 'env | grep -i ' . $proto . '_proxy | sed \'s/' . $proto . '_proxy=//i\' | sed \'s/' . $proto . '\:\/\///\' | sed \'s/\/$//\'';
		$httpproxy = `$httpenvcmd 2>/dev/null`;
		chomp($httpproxy);

		$proxies{$proto} = extractProxyString($httpproxy);
	}

	return \%proxies;
}

#*****************************************************************************************************
# Subroutine			: authenticateUser
# Objective				: Authenticate user credentials
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub authenticateUser {
	my $uname = $_[0];
	my $emailID = $_[1];
	my $quicklogin = (defined($_[2]) and $_[2])? 1 : 0;
	my $loginType = ((defined($_[3]) and ($_[3] == 2)) ? 111 : 1);
	if ($quicklogin) {
		$loginType = 1111;
	}

	my $retry   = 0;
RETRY:
	my $res = makeRequest($loginType, [$uname, getUserConfiguration("TRD")]);
	my @responseData;
	if ($res) {
		@responseData = parseEVSCmdOutput($res->{DATA}, 'login', 1);
		if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
			if($loginType == 111 and exists $res->{'SSO_MESSAGE'} and $res->{'SSO_MESSAGE'} ne '' and $res->{'SSO_MESSAGE'} =~ /SSO has not been enabled/) {
				retreat($res->{'SSO_MESSAGE'});
			}

			my $errorMsg = (defined($emailID) and $emailID ne $uname)? 'failed_to_authenticate_user_associated' : 'failed_to_authenticate_username';
			$errorMsg = getStringConstant($errorMsg);
			$errorMsg =~ s/__USER__/$uname/eg;
			$errorMsg =~ s/__EMAILID__/$emailID/eg;

			if (exists $responseData[0]->{'desc'}) {
				if (($responseData[0]->{'desc'} eq 'passwords do not match') and loadNotifications() and lockCriticalUpdate("notification")) {
					setNotification('alert_status_update', $AppConfig::alertErrCodes{'uname_pwd_mismatch'}) and saveNotifications();
					unlockCriticalUpdate("notification");
				}

				my $errmsg = $responseData[0]->{'desc'};
				if($errmsg =~ /invalid value passed for username/i) {
					retreat([$errorMsg, 'invalid_username_or_password', 'please_try_again']);
				}
				else {
					$errmsg = getStringConstant($responseData[0]->{'desc'});
					retreat([$errorMsg, ucfirst($errmsg), '. ', 'please_try_again']);
				}
			}

			if (exists $responseData[0]->{'MSG'} && $responseData[0]->{'MSG'} ne '') {
                removeItems(getUserFilePath($AppConfig::proxyInfoFile)); #Added for Harish_2.3_19_2: Senthil
				#Added for Harish_2.3_2_1
				if (!$quicklogin and $responseData[0]->{'MSG'} =~ /ProxyError/i) {
					# goto RETRY if(detectENVProxyAndUpdate());
					display(["\n", 'kindly_verify_ur_proxy'],1);
					if($retry < $AppConfig::maxChoiceRetry) {
						askProxyDetails();
						$retry++;
						goto RETRY;
					} else {
						retreat('max_retry');
					}
				}
				retreat($responseData[0]->{'MSG'}) if ($responseData[0]->{'MSG'} =~ /try_later|contact_support|two_factor_authentication|verfication_code_failed/i);
				#retreat(ucfirst($responseData[0]->{'MSG'})) if($responseData[0]->{'MSG'} =~ /Try again/);
				retreat([$errorMsg, ucfirst(getStringConstant($responseData[0]->{'MSG'}))]) if(getStringConstant($responseData[0]->{'MSG'}) =~ /Try again/i);
				retreat([$errorMsg, ucfirst(getStringConstant($responseData[0]->{'MSG'})), '. ', 'please_try_again']);
			}
			retreat([$errorMsg,'please_try_again']);
		}

		return @responseData if ($quicklogin);

		if(exists($res->{"p"})) {
			my ($a, $b) = split(/\_/, $res->{"p"}, 2);
			$responseData[0]->{'p'} = unpack("u", $b);
		}

		if (exists $res->{"TRD"}) {
			$responseData[0]->{'TRD'} = 1;
		}

		if ((exists $responseData[0]->{'plan_type'}) and ($responseData[0]->{'plan_type'} eq 'Mobile-Only')) {
			updateAccountStatus($uname, 'O');
			retreat(ucfirst($responseData[0]->{'desc'}));
		}

		updateAccountStatus($uname, uc($responseData[0]->{'accstat'})) if(exists $responseData[0]->{'accstat'});

		if ((exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'C')) {
			checkErrorAndLogout('account has been cancelled', undef, 1);
			if(loadNotifications() and lockCriticalUpdate("notification")) {
				setNotification('alert_status_update', $AppConfig::alertErrCodes{'account_cancelled'}) and saveNotifications();
				unlockCriticalUpdate("notification");
			}

			retreat('your_account_has_been_cancelled');
		}

		if ((exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'M')) {
			checkErrorAndLogout('account is under maintenance', undef, 1);
			if(loadNotifications() and lockCriticalUpdate("notification")) {
				setNotification('alert_status_update', $AppConfig::alertErrCodes{'account_under_maint'}) and saveNotifications();
				unlockCriticalUpdate("notification");
			}

			retreat('your_account_is_under_maintenance');
		}

		if ((exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'B')) {
			checkErrorAndLogout('account has been blocked', undef, 1);
			if(loadNotifications() and lockCriticalUpdate("notification")) {
				setNotification('alert_status_update', $AppConfig::alertErrCodes{'account_blocked'}) and saveNotifications();
				unlockCriticalUpdate("notification");
			}

			retreat('your_account_has_been_blocked');
		}
	}

	updateAccountStatus($uname, 'Y') if(exists $responseData[0]->{'accstat'});

	if (loadNotifications() and lockCriticalUpdate("notification") and ((getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'uname_pwd_mismatch'}) or
			(getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'account_cancelled'}) or
			(getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'account_under_maint'}) or
			(getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'account_blocked'}))) {
		setNotification('alert_status_update', 0) and saveNotifications();
	}

	unlockCriticalUpdate("notification");

	return @responseData;
}

#*****************************************************************************************************
# Subroutine			: autoConfigureCPAN
# Objective				: This will auto configure CPAN in special cases
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub autoConfigureCPAN {
	my $cpanconf	= $_[0];
	my $autoconf	= $_[1]? $_[1] : '';
	my $display		= $_[2];

	return 0 unless($cpanconf);

	display(['installing_perl_dependency', ': ']) if($display);
	my $os = getOSBuild();
	foreach my $verkey (keys(%{$cpanconf})) {
		my @opver	= split('-', $verkey);
		if (($opver[0] eq 'gte' && $os->{'build'} >= $opver[1]) || ($opver[0] eq 'lte' && $os->{'build'} <= $opver[1]) ||
		($opver[0] eq 'btw' && (split('_', $opver[1]))[0] <= $os->{'build'} && $os->{'build'} <= (split('_', $opver[1]))[1]) || 
		($opver[0] eq 'gt' && $os->{'build'} > $opver[1]) || ($opver[0] eq 'lt' && $os->{'build'} < $opver[1])) {
			for my $instidx (0 .. $#{$cpanconf->{$verkey}}) {
				$cpanconf->{$verkey}->[$instidx] =~ s/__APP_PATH__/getAppPath()/eg;
				$cpanconf->{$verkey}->[$instidx] =~ s/__CPAN_AUTOINSTALL__/$autoconf/g;
				# $cpanconf->{$verkey}->[$instidx] =~ s/ 2>\/dev\/null 1>\/dev\/null//g;
				# print "\n$cpanconf->{$verkey}->[$instidx]\n";
				$cpanconf->{$verkey}->[$instidx] =~ /(.*?)install\s(.*?)\'(.*?)/is;
				display([$2, '...']) if($display);
				system("$cpanconf->{$verkey}->[$instidx] 2>$AppConfig::repoerrpath 1>$AppConfig::repooppath");
			}

			last;
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine		: askProxyDetails
# Objective			: Ask user to provide proxy details.
# Added By			: Yogesh Kumar
# Modified By		: Anil Kumar, Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub askProxyDetails {
	my %proxTemplate = %{$AppConfig::proxyTemplate};
	my $proxyDetails = \%proxTemplate;
	my $proxstr = $_[0];

	createDir(getCachedDir(), 1) unless(-d getCachedDir());

	if ($AppConfig::isautoinstall && $proxstr) {
		my @marr = ($proxstr =~ /(.*):(.*)@(.*):(.*)|(.*)@(.*):(.*)|(.*):(.*)/);
		my ($uname, $pwd, $ip, $port) = ('', '', '', 0);

		if ($marr[0]) {
			($uname, $pwd, $ip, $port) = ($marr[0], $marr[1], $marr[2], $marr[3]);
		}
		elsif ($marr[4]) {
			($uname, $ip, $port) = ($marr[4], $marr[5], $marr[6]);
		}
		elsif($marr[7]) {
			($ip, $port) = ($marr[7], $marr[8]);
		}

		$proxyDetails->{'PROXYIP'} = $ip;
		$proxyDetails->{'PROXYPORT'} = $port;

		if ($uname) {
			$proxyDetails->{'PROXYUSERNAME'} = $uname;

			if ($pwd) {
				$pwd = encryptString($pwd);
				$proxyDetails->{'PROXYPASSWORD'} = $pwd;
			}
		}
		fileWrite(getUserFilePath($AppConfig::proxyInfoFile), JSON::to_json($proxyDetails));

		return 1;
	}

	display(["\n",'are_using_proxy_y_n', '? ', "\n"], 0);
	my $hasProxy = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($hasProxy) eq 'n') {
		fileWrite(getUserFilePath($AppConfig::proxyInfoFile), JSON::to_json($proxyDetails));
		display(['your_proxy_has_been_disabled', "\n"],1) if (defined($_[0]));
	}
	else {
		display("\n",0);

		my $autoProxy = autoDetectENVProxy();
		my ($useAutoProx, $autoProxIP, $autoProxPort, $autoProxUser, $autoProxPass) = (0, '', 0, '', '');
		if(scalar(keys(%{$autoProxy->{'https'}})) or scalar(keys(%{$autoProxy->{'http'}}))) {
			if($autoProxy->{'https'}{'PROXYIP'} and $autoProxy->{'https'}{'PROXYPORT'}) {
				$autoProxIP = $autoProxy->{'https'}{'PROXYIP'};
				$autoProxPort = $autoProxy->{'https'}{'PROXYPORT'};
				$autoProxUser = $autoProxy->{'https'}{'PROXYUSERNAME'};
				$autoProxPass = $autoProxy->{'https'}{'PROXYPASSWORD'};
			} elsif($autoProxy->{'http'}{'PROXYIP'} and $autoProxy->{'http'}{'PROXYPORT'}) {
				$autoProxIP = $autoProxy->{'http'}{'PROXYIP'};
				$autoProxPort = $autoProxy->{'http'}{'PROXYPORT'};
				$autoProxUser = $autoProxy->{'http'}{'PROXYUSERNAME'};
				$autoProxPass = $autoProxy->{'http'}{'PROXYPASSWORD'};
			}
		}

		if($autoProxIP and $autoProxPort) {
			my $proxdispstr = "$autoProxIP:$autoProxPort";
			if($autoProxUser) {
				if($autoProxPass) {
					$proxdispstr = $autoProxUser . ':*****@' . $proxdispstr;
				} else {
					$proxdispstr = $autoProxUser . '@' . $proxdispstr;
				}
			}

			display(['auto_detected_proxy', ': ', $proxdispstr, '. ', 'do_you_want_to_use_yn']);
			my $proxch = getAndValidate(['enter_your_choice'], "YN_choice", 1);
			$useAutoProx = 1 if(lc($proxch) eq 'y');
		}

		my ($proxySIP, $proxySIPPort, $proxySIPUname, $proxySIPPasswd) = ('') x 4;
		if($useAutoProx) {
			$proxyDetails->{'PROXYIP'} = $autoProxIP;
			$proxySIP = $autoProxIP;
			$proxyDetails->{'PROXYPORT'} = $autoProxPort;
			$proxySIPPort = $autoProxPort;

			if($autoProxUser) {
				$proxySIPUname = $autoProxUser;
				$proxyDetails->{'PROXYUSERNAME'} = $proxySIPUname;
				$proxySIPPasswd = encryptString($autoProxPass) if($autoProxPass);
				$proxyDetails->{'PROXYPASSWORD'} = $proxySIPPasswd;
			}
		} else{
			$proxySIP = getAndValidate(['enter_proxy_server_ip', ': '], "ipaddress", 1);
			$proxyDetails->{'PROXYIP'} = $proxySIP;

			$proxySIPPort = getAndValidate(['enter_proxy_server_port',': '], "port_no", 1);
			$proxyDetails->{'PROXYPORT'} = $proxySIPPort;

			display(['enter_proxy_server_username_if_set', ': '], 0);
			trim($proxySIPUname = getUserChoice());
			$proxyDetails->{'PROXYUSERNAME'} = $proxySIPUname;

			if ($proxySIPUname ne '') {
				display(['enter_proxy_server_password_if_set', ': '], 0);
				trim($proxySIPPasswd = getUserChoice(0));
				$proxySIPPasswd = encryptString($proxySIPPasswd);
			}

			$proxyDetails->{'PROXYPASSWORD'} = $proxySIPPasswd;
		}

		my $proxyStr = "$proxySIPUname:$proxySIPPasswd\@$proxySIP:$proxySIPPort";
		$proxyDetails->{'PROXY'} = $proxyStr;
        fileWrite(getUserFilePath($AppConfig::proxyInfoFile), JSON::to_json($proxyDetails));

		if (defined($_[0])) {
			# need to ping for proxy validation testing. .
			my @responseData = ();
			createUTF8File('PING')  or retreat('failed_to_create_utf8_file');
			@responseData = runEVS();
			if (($responseData[0]->{'STATUS'} eq AppConfig::FAILURE)) {
				traceLog("Proxy validation error: ".$responseData[0]->{'MSG'}) if(defined($responseData[0]->{'MSG'}));
				#if($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Failed connect to .* Connection refused|Connection timed out|response code said error|407 Proxy Authentication Required|HTTP code 407|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/) {}
				if ($responseData[0]->{'MSG'} =~ /$AppConfig::proxyNetworkError/i) {
                    removeItems(getUserFilePath($AppConfig::proxyInfoFile));
					retreat(["\n", 'kindly_verify_ur_proxy']) if (defined($_[1]));
				    display(["\n", 'kindly_verify_ur_proxy']);
				    askProxyDetails(@_,"NoRetry");
				}
			}
		}

		display(['proxy_details_updated_successfully', "\n"], 1) ;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine	  : detectENVProxyAndUpdate failed to connect
# Objective		  : This subroutine is used to detect & update the proxy detail when connection failed due to wrong proxy.
# Added By		  : Senthil Pandian
# Modified By     : 
#****************************************************************************************************/
sub detectENVProxyAndUpdate() {
	my $proxyDetails = ();
	my $autoProxy = autoDetectENVProxy();
	my ($useAutoProx, $autoProxIP, $autoProxPort, $autoProxUser, $autoProxPass) = (0, '', 0, '', '');
	if(scalar(keys(%{$autoProxy->{'https'}})) or scalar(keys(%{$autoProxy->{'http'}}))) {
		if($autoProxy->{'https'}{'PROXYIP'} and $autoProxy->{'https'}{'PROXYPORT'}) {
			$autoProxIP = $autoProxy->{'https'}{'PROXYIP'};
			$autoProxPort = $autoProxy->{'https'}{'PROXYPORT'};
			$autoProxUser = $autoProxy->{'https'}{'PROXYUSERNAME'};
			$autoProxPass = $autoProxy->{'https'}{'PROXYPASSWORD'};
		} elsif($autoProxy->{'http'}{'PROXYIP'} and $autoProxy->{'http'}{'PROXYPORT'}) {
			$autoProxIP = $autoProxy->{'http'}{'PROXYIP'};
			$autoProxPort = $autoProxy->{'http'}{'PROXYPORT'};
			$autoProxUser = $autoProxy->{'http'}{'PROXYUSERNAME'};
			$autoProxPass = $autoProxy->{'http'}{'PROXYPASSWORD'};
		}
	}

	if($autoProxIP and $autoProxPort) {
		$useAutoProx = 1;
	}

	my ($proxySIP, $proxySIPPort, $proxySIPUname, $proxySIPPasswd) = '' x 4;
	if($useAutoProx) {
		$proxyDetails->{'PROXYIP'} = $autoProxIP;
		$proxySIP = $autoProxIP;
		$proxyDetails->{'PROXYPORT'} = $autoProxPort;
		$proxySIPPort = $autoProxPort;

		if($autoProxUser) {
			$proxySIPUname = $autoProxUser;
			$proxyDetails->{'PROXYUSERNAME'} = $proxySIPUname;
			$proxySIPPasswd = encryptString($autoProxPass) if($autoProxPass);
			$proxyDetails->{'PROXYPASSWORD'} = $proxySIPPasswd;
		}

		my $proxyStr = "$proxySIPUname:$proxySIPPasswd\@$proxySIP:$proxySIPPort";
		$proxyDetails->{'PROXY'} = $proxyStr;
		fileWrite(getUserFilePath($AppConfig::proxyInfoFile), JSON::to_json($proxyDetails));

		# need to ping for proxy validation testing. .
		my @responseData = ();
		createUTF8File('PING') or retreat('failed_to_create_utf8_file');
		@responseData = runEVS();

		if (($responseData[0]->{'STATUS'} eq AppConfig::FAILURE)) {
			traceLog("Proxy validation error: ".$responseData[0]->{'MSG'}) if(defined($responseData[0]->{'MSG'}));
			#if($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Failed connect to .* Connection refused|Connection timed out|response code said error|407 Proxy Authentication Required|HTTP code 407|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/) {}
			if ($responseData[0]->{'MSG'} =~ /$AppConfig::proxyNetworkError/i) {
				removeItems(getUserFilePath($AppConfig::proxyInfoFile));
				# retreat(["\n", 'kindly_verify_ur_proxy']) if (defined($_[1]));
				# display(["\n", 'kindly_verify_ur_proxy']);
				# askProxyDetails(@_,"NoRetry");	
				$useAutoProx = 0;				
			}			
		}
	}
	return $useAutoProx;
}

#*****************************************************************************************************
# Subroutine			: askToCreateOrSelectADevice
# Objective				: This subroutine is used to ask usr to create or select a bucket
# Added By				: Anil Kumar
# Modified By     : Yogesh Kumar
#****************************************************************************************************/
sub askToCreateOrSelectADevice {
	tie(my %optionsInfo, 'Tie::IxHash',
		'create_new_backup_location' => \&createBucket,
		'select_from_existing_backup_locations' => sub {
			return linkBucket('backup', $_[0], \&askToCreateOrSelectADevice);
		}
	);
	my @options = keys %optionsInfo;
	display(['multiple_backup_locations_are_configured', ". ", 'select_an_option', ": ", "\n"]);
	displayMenu('', @options);
	my $deviceSelection = getUserMenuChoice(scalar(@options));

	return $optionsInfo{$options[$deviceSelection - 1]}->($_[0]);
}

#*****************************************************************************************************
# Subroutine  : addLogStat
# Objective   : Adds an entry to the log_summary.txt which contains job's status, files, duration
# Added By    : Yogesh Kumar
# Modified By : Sabin Cheruvattil
#****************************************************************************************************/
sub addLogStat {
	unless (defined($_[0]) and defined($_[1])) {
		traceLog('both_job_path_and_log_summary_content_is_required');
		return 0;
	}

	my @now = localtime();
	my $absLogStatFile = getCatfile($_[0], sprintf("$AppConfig::logStatFile", ($now[4] + 1), ($now[5] += 1900)));

	$_[0] = quotemeta($_[0]); #Added for Suruchi_2.32_21_11 : Senthil
	if(getJobsPath('cdp') =~ /$_[0]/ && -f $absLogStatFile && -s $absLogStatFile > 0) {
		my @tkey = keys(%{$_[1]});
		my %logs = %{JSON::from_json(
			'{' . substr(getFileContents($absLogStatFile), 1) . '}'
		)};

		if (exists $logs{$tkey[0]}) {
			delete $logs{$tkey[0]};

			my $logstatjson = JSON::to_json(\%logs);
			if ($logstatjson eq '{}') {
				$logstatjson = '';
			}
			elsif ($logstatjson ne '') {
				substr($logstatjson, 0, 1, ',');
				substr($logstatjson, -1, 1, '');
			}

			fileWrite($absLogStatFile, $logstatjson);
		}
	}

	if (open(my $lsf, '>>', $absLogStatFile)) {
		my $lsc = JSON::to_json($_[1]);
		print $lsf ',';
		print $lsf substr($lsc, 1, (length($lsc) - 2));
		close($lsf);
	}
	else {
		traceLog(['unable_to_open_file', $absLogStatFile]);
		return 0;
	}

	return 1;
}

#****************************************************************************************************
# Subroutine          : appendExcludedLogFileContents
# Objective           : This subroutine appends the contents of the excluded log file to the output file
# Modified By         : Sabin Cheruvattil
#*****************************************************************************************************/
sub appendExcludedLogFileContents {
	my $jobpath = $_[0]? $_[0] : $AppConfig::jobRunningDir;
	my $dbfile	= getCatfile($jobpath, $AppConfig::dbname);

	return '' unless(-f $dbfile);

	my $exsummary = '';
	my ($dbfstate, $scanfile) = Sqlite::createLBDB($jobpath, 1);

	if($dbfstate) {
		Sqlite::initiateDBoperation();
		$exsummary = getStringConstant('exclude_backup_notice') . "\n\n" if(Sqlite::hasExcludedItems());
		Sqlite::closeDB();
	}

	return $exsummary;
}
#------------------------------------------------- B -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: buildQuery
# Objective				: Build hash to http query string
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub buildQuery {
	my @qs;
	foreach my $key (keys %{$_[0]}) {
		push @qs, (urlEncode($key) . '=' . urlEncode($_[0]->{$key}));
	}
	if (exists $_[0]->{'ver'} and $_[0]->{'ver'} eq 'evs005') {
		return ('?' . join("&", @qs));
	}
	else {
		return join("&", @qs);
	}
}

#*****************************************************************************************************
# Subroutine			: backupTypeCheck
# Objective             : This subroutine checks if backup type is either Mirror or Relative
# Added By              : Dhritikana
#****************************************************************************************************/
sub backupTypeCheck {
	my $backupPathType = getUserConfiguration('BACKUPTYPE');
	my $relative;
	$backupPathType = lc($backupPathType);
	if ($backupPathType eq "relative") {
		$relative = 0;
	}else{
		$relative = 1;
	}
	return $relative;
}

#------------------------------------------------- C -------------------------------------------------#

#*****************************************************************************************************
# Subroutine	: catchPressedKey
# In Param		: 
# Out Param		: 
# Objective		: This subroutine for capturing a pressed key
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub catchPressedKey {
	my $keyname = '';
    chomp(my $stty = `stty -g`);                # Save 'cooked' mode tty
	$AppConfig::stty = $stty;
    `stty -icrnl -icanon -echo min 0 time 0`;   # Begin raw mode
    sub {                                       # Create a closure
        if (!$_[0]) {                           # If argument is zero ...
            system("stty $stty");               #   restore 'cooked' mode
        } else {                                # Otherwise get and return
            #$keyname = `dd bs=1 count=1 <&0 2>/dev/null`;  #   a single keystroke
			$keyname = `dd bs=1 count=1 2>/dev/null`;
			if(defined($keyname)) {
				chomp($keyname);
				$AppConfig::pressedKeyValue = lc($keyname);
			}
        }
    };
}

#*****************************************************************************************************
# Subroutine	: canKernelSupportInotify
# In Param		: UNDEF
# Out Param		: Status | Boolean
# Objective		: Checks if Inotify can be supported by kernel or not
# Added By		: Sabin Cheruvattil
# Modified By	: Senthil Pandian
#*****************************************************************************************************
sub canKernelSupportInotify {
    my $kernel	= 0;
	my $os = getOSBuild();
	return 0 if($os->{'os'} eq 'freebsd');

	my $kerstr	= `uname -r`;
	$kerstr		=~ /(\d*)\.(\d*)\.(\d*)(.*)/g;
	$kernel	= qq($1.$2.$3) if(defined($1) and defined($2) and defined($3));

	return versioncompare('2.6.13', $kernel) != 1? 1 : 0;
}

#****************************************************************************************************
# Subroutine Name		: checkForRunningJobsInOtherUsers.
# Objective				: Check all the running jobs w.r.t other users in the service path.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#*****************************************************************************************************/
sub checkForRunningJobsInOtherUsers {
	# to get all jobs that needs to kill from different user profiles.
	#Getting IDrive user list
	my @idriveUsersList = getIDriveUserList();
	if (scalar @idriveUsersList > 0) {
		foreach my $usrProfileDir (@idriveUsersList)  {
			next if (getUsername() eq basename($usrProfileDir));
			my @userJobpath = (qq($usrProfileDir/$AppConfig::userProfilePaths{'backup'}/),
								qq($usrProfileDir/$AppConfig::userProfilePaths{'restore'}/),
								qq($usrProfileDir/$AppConfig::userProfilePaths{'localbackup'}),
								qq($usrProfileDir/$AppConfig::userProfilePaths{'archive'}/));

			for(my $j=0; $j<=$#userJobpath; $j++) {
				my $pidPath =  getCatfile($userJobpath[$j], "pid.txt");
				if (isFileLocked($pidPath)) {
					# message needs to be reviewed and changed.
					#display("One or more backup/local backup/restore/archive cleanup jobs are in process with respect to Others users. Please make sure those are completed and try again.", 1);
					return 0;
				}
			}
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkAndRenameFileWithStatus
# Objective				: This subroutine check and rename file with status
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub checkAndRenameFileWithStatus {
	my $jobDir    = $_[0];
	my $isSummary = 0;
	my ($considered,$success,$synced,$failed,$status,$logFile);
	my $logPidFilePath = $jobDir."/".$AppConfig::logPidFile;

	my $tempJobDir = quotemeta($jobDir); #Added for Suruchi_2.32_21_11
	return 0 if(getJobsPath('cdp') =~ /$tempJobDir/);

	if (-f $logPidFilePath && !-z $logPidFilePath) {
		open FILE, "<", $logPidFilePath or (traceLog(['failed_to_open_file', ":$logPidFilePath. Reason:$!"]) and die);
		chomp($logFile = <FILE>);
		close FILE;
		unlink($logPidFilePath);
	}
	else {
		return 0;
	}

	return 0 if (!defined($logFile) or !-e $logFile);

	if (!defined($logFile) or !-e $logFile) {
		my $bkpStatusFile = getCatfile(getUserProfilePath(), $AppConfig::userInfoPath, $AppConfig::lastBkpStatusFile);
		
		my $fileContent	= "";
		$fileContent	= getFileContents($bkpStatusFile);
		Chomp(\$fileContent);

		return 0 if(!$fileContent or $fileContent !~ m/^\{/);

		my %bkpStatus = %{JSON::from_json($fileContent)};
		if(loadNotifications() and lockCriticalUpdate("notification")) {
			setNotification(sprintf("get_%sset_content", $bkpStatus{'last_backup_status'}{'jobType'})) and saveNotifications() if(exists $bkpStatus{'last_backup_status'}{'jobType'});
			unlockCriticalUpdate("notification");
		}

		return 0;
	}

	return 0 unless ($logFile =~ m/_Running_/);

    if(defined($_[1]) and $_[1] ne 'archive') {
        my $logContentCmd = updateLocaleCmd("tail -n10 '$logFile'");
        my @logContent = `$logContentCmd`;
        foreach (@logContent) {
            my $line = $_;
            if (!$isSummary and $line =~ m/Summary:/) {
                $isSummary = 1;
            }
            elsif ($isSummary and $line =~ m/considered/){
                $considered = (split(":", $line))[1];
                Chomp(\$considered);
            }
            elsif ($isSummary and $line =~ m/(backed|restored)/){
                $success = (split(":", $line))[1];
                Chomp(\$success);
            }
            elsif ($isSummary and $line =~ m/already present/){
                $synced = (split(":", $line))[1];
                Chomp(\$synced);
            }
            elsif ($isSummary and $line =~ m/failed/){
                $failed = (split(":", $line))[1];
                Chomp(\$failed);
            }
        }

        if ($isSummary){
            if ($failed > 0 or $considered == 0){
                $status = getStringConstant('failure');
            }
            elsif ($considered == ($success+$synced)){
                $status = getStringConstant('success');
            }
        }
    }

	if (!$isSummary or !defined($status)){
		$status = getStringConstant('aborted');
	}

    my $logFile_mtime = stat($logFile)->mtime;
	my $finalOutFile  = $logFile;
	$finalOutFile =~ s/_Running_/_$status\_/;
	system(updateLocaleCmd("mv '$logFile' '$finalOutFile'"));
	my @logPath = split("_Running_",$logFile);
	my $tempOutputFilePath = (split("/", $logPath[0]))[-1];
	my %logStat = (
		(split('_', basename($tempOutputFilePath)))[0] => {
			'datetime' =>  strftime('%m/%d/%Y %H:%M:%S', localtime($tempOutputFilePath + 15)),
			'duration' => "--",
			'filescount' => ($considered)?$considered:"--",
			'status' => $status."_".$logPath[1],
		}
	);

    if(defined($_[1]) and $_[1] ne 'archive') {
        $logStat{'bkpfiles'} = $success;
        $logStat{'size'}     =  "--";
    }

	addLogStat($jobDir, \%logStat);
	if(loadNotifications() and lockCriticalUpdate("notification")) {
		setNotification(sprintf("get_%sset_content", $_[1])) and saveNotifications();
		unlockCriticalUpdate("notification");
	}
	saveLog($finalOutFile, 0);

    return 1 if(defined($_[1]) and $_[1] ne 'backup');

    my $lpath	= basename($finalOutFile);
    my $taskType  = $logPath[1];
    my $startTime = $tempOutputFilePath + 15;
    my $endTime   = ($logFile_mtime > $startTime)?$logFile_mtime:$startTime;
    my %bkpsummary = (
        'st'		=> strftime("%Y-%m-%d %H:%M:%S", localtime($startTime)),
        'et'		=> strftime("%Y-%m-%d %H:%M:%S", localtime($endTime)),
        'uname'		=> getUsername(),
        'hostname'	=> $AppConfig::hostname,
        'files'		=> ($considered)?$considered:"--",
        'filesync'	=> ($synced)?$synced:"--",
        'status'	=> $status,
        'duration'	=> "--", #(mktime(@endTime) - mktime(@startTime)),
        'optype'	=> $taskType eq 'Manual'? 'Interactive Backup' : 'Backup',
        'lpath'		=> $lpath,
        'logfile'	=> $finalOutFile,
        'summary'	=> '',
    );

    $bkpsummary{'summary'} = getWebViewSummary(\%bkpsummary);
    saveWebViewXML(\%bkpsummary);    
    return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	checkAndUpdateServerAddr
# Objective               :	check and update server address if evs error due to invalid address
# Added By                : Senthil Pandian
#********************************************************************************************************
sub checkAndUpdateServerAddr {
	my $tempErrorFile = $_[0];
	my $tempErrorFileSize = 0;
	$tempErrorFileSize = -s $tempErrorFile if(-f $tempErrorFile);

	if($tempErrorFileSize > 0) {
		my $errorContent = getFileContents($tempErrorFile);
		if ($errorContent =~ /unauthorized user|user information not found/i) {
			updateAccountStatus(getUsername(), 'UA');
			saveServerAddress(fetchServerAddress());
			return 0;
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine		: checkAndUpdateAccStatError
# Objective			: Checks the error and updates the status if required
# Added By			: Sabin Cheruvattil
# Modified By       : Yogesh Kumar
#*****************************************************************************************************
sub checkAndUpdateAccStatError {
	my ($uname, $err) = ($_[0], $_[1]);
	return 0 if (!$uname or !$err);

	my $stat = '';
	if ($err =~ /maintenance/i) {
		$stat = 'M';
	}
	elsif($err =~ /account has been cancelled/i) {
		$stat = 'C';
	}
	elsif ($err =~ /blocked/i) {
		$stat = 'C';
		return 1; #Skipping the status change: Senthil
	}
	elsif ($err =~ /suspended/i) {
		$stat = 'S';
	}
	elsif ($err =~ /unauthorized user|user information not found/i) {
		$stat = 'UA';
	}
	# TODO: Delete Computer
	elsif ($err =~ /device is deleted\/removed/i) {
		deleteBackupDevice();
	}

	updateAccountStatus($uname, $stat) if ($stat);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateServerRoot
# Objective				: check and update if server root field is empty in configuration file
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub checkAndUpdateServerRoot {
	my $serverRoot;
	if (getUserConfiguration('DEDUP') eq 'on' && (!getUserConfiguration('SERVERROOT') || getUserConfiguration('SERVERROOT') eq '')) {
		my @result = fetchAllDevices();
		#Added to consider the bucket type 'D' only
		my @devices;
		foreach (@result){
			next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
			push @devices, $_;
		}

		$muid = getMachineUID() or retreat('unable_to_find_mac_address');
		foreach(@devices) {
			next if ($muid ne $_->{'uid'});
			if ($_->{'server_root'} ne '') {
				setUserConfiguration('SERVERROOT', $_->{'server_root'});
				saveUserConfiguration() or retreat('failed_to_save_user_configuration');
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: checkEmailNotify
# Objective				: this is to check and update if there is any email for specific job
# Added By				: Anil Kumar
# Modified By			: Vijay Vinoth, Senthil Pandian
#****************************************************************************************************/
sub checkEmailNotify {
	loadCrontab();
	my ($jobType, $jobName) = ($_[0],$_[1]);
	$jobType = "backup" if (not defined($jobType) or $jobType eq '' or $jobType =~ /backup/i);
	my $emailStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}') ;
	return "DISABLED" if ($emailStatus eq 'disabled') ;
	return ($emailStatus, getCrontab($jobType, $jobName, '{settings}{emails}{ids}')) ;
}

#*****************************************************************************************************
# Subroutine			: checkCRONServiceStatus
# Objective				: This is to check IDrive CRON service status
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkCRONServiceStatus {
	return CRON_RUNNING if (defined($_[0]) && -f $_[0]);
	return CRON_NOTRUNNING unless(-f $AppConfig::cronlockFile);

	# As a double check, verify shared lock file
	return CRON_RUNNING if (!open(my $lockfh, ">>", $AppConfig::cronlockFile) && $AppConfig::mcUser ne 'root');
	return CRON_RUNNING unless(flock($lockfh, LOCK_EX|LOCK_NB));

	unlink($AppConfig::cronlockFile);
	return CRON_NOTRUNNING;
}

#*****************************************************************************************************
# Subroutine			: checkInstallDBCDPPreRequisites
# Objective				: Verify if the pre-requesites
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub checkInstallDBCDPPreRequisites {
	return 1 if(hasSQLitePreReq() and hasBasePreReq() and (hasFileNotifyPreReq() or !canKernelSupportInotify()));

	my $os = getOSBuild();

	if((!hasBasePreReq() or !hasSQLitePreReq()) and !exists($AppConfig::depInstallUtils{$os->{'os'}})) {
		retreat(["\n", 'pre_req_not_met', '. ', 'unable_to_identify_your_os_requirements', "\n"]);
	}

	my $cdphalt = getCDPHaltFile();
	return 1 if(hasSQLitePreReq() and hasBasePreReq() and -f $cdphalt);

	my $pkginstallseq	= $AppConfig::depInstallUtils{$os->{'os'}}{'pkg-install'};
	my $cpaninstallseq	= $AppConfig::depInstallUtils{$os->{'os'}}{'cpan-install'};
	my $hasinotifykern	= canKernelSupportInotify();
	my ($packagenames, $cpanpacks);
	($pkginstallseq, $packagenames) = getPkgInstallables($pkginstallseq);
	($cpaninstallseq, $cpanpacks) = getCPANInstallables($cpaninstallseq);

	display(['pre_req_not_met', '. ', 'following_packages_will_be_att_installed', ':', "\n"]);
	display(['cc_packages', ': ', join(", ", @{$packagenames})]) if(@{$packagenames});
	display(['cc_perl_cpan_packages', ': ', join(", ", @{$cpanpacks})]) if(@{$cpanpacks});
	display(["\n", 'do_you_want_to_install_pre_req_yn']);

	my $uc = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if(lc($uc) eq 'n') {
		promptPreReqManualInstall($pkginstallseq, $cpaninstallseq);

		$AppConfig::displayHeader = 0;
		retreat(["\n", 'unable_to_proceed_db_uzip_curl_prereq_met', '.']) if(!hasSQLitePreReq() or !hasBasePreReq());
		fileWrite($cdphalt, '1') if(!hasFileNotifyPreReq() and !-f $cdphalt);
		display(['failed_to_install_file_notify_dependencies', '. ', 'cdp_will_not_work', '.']) if($hasinotifykern);

		return 0;
	}

	my $sudoprompt	= 'please_provide_' . (hasSudo()? 'sudoers' : 'root') . '_pwd_for_pre_req';
	my $sudosucmd	= getSudoSuCRONPerlCMD('installdependencies', $sudoprompt);
	my $execres		= system($sudosucmd);

	retreat(['failed_to_install_db_uzip_curl_dep', '. ', 'unable_to_continue', '.']) if($execres);

	if(!$hasinotifykern) {
		display(['your_machine_not_have_min_req_cdp', '. ', 'cdp_will_not_work', '.']);
		fileWrite($cdphalt, '1');
	} elsif(!hasFileNotifyPreReq()) {
		display(['failed_to_install_file_notify_dependencies', '. ', 'cdp_will_not_work', '.']) if($hasinotifykern);
		fileWrite($cdphalt, '1');
	} else {
		display(["\n", 'all_prereq_have_been_installed']);
		unlink($cdphalt) if(-f $cdphalt);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine	: checkBackupsetIntegrity
# In Param		: Path | String
# Out Param		: Status | Boolean
# Objective		: Checks and fixes the backupset table
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub checkBackupsetIntegrity {
	my ($path, $ttype, $pidpath, $iscdp) = ($_[0], $_[1], $_[2], $_[3]);
	return 0 unless($path);

	my $bkpsetfile = getCatfile($path, $AppConfig::backupsetFile);
	return if(!-d $path || !-f $bkpsetfile || -z _);

	my ($dbfstate, $scanfile) = Sqlite::createLBDB($path, 0);

	my $locbkpsetstat	= getLocalBkpSetStats($path);
	Sqlite::createLBDB($path, 0) unless($dbfstate);
	Sqlite::initiateDBoperation();

	my $dbbkpsetstat	= Sqlite::getBackupsetItemsWithStats();
	my $filecount		= Sqlite::getAllFileCount();

	Sqlite::closeDB();

	my $needscan	= 0;
	foreach my $litem (keys(%{$locbkpsetstat})) {
		unless(exists($dbbkpsetstat->{$litem})) {
			$needscan	= 1;
			last;
		}

		if($dbbkpsetstat->{$litem}{'stat'} ne $locbkpsetstat->{$litem}{'stat'} ||
		$dbbkpsetstat->{$litem}{'type'} ne $locbkpsetstat->{$litem}{'type'} ||
		$dbbkpsetstat->{$litem}{'lmd'} ne $locbkpsetstat->{$litem}{'lmd'}) {
			$needscan	= 1;
			last;
		}
	}

	return if(!$needscan && $filecount);

	if($filecount) {
		my $oldbkpsetfile	= qq($bkpsetfile$AppConfig::backupextn);
		copy($bkpsetfile, $oldbkpsetfile);
	}

	my $reqfile = createScanRequest($path, basename($path), 0, 'backup', $iscdp, 1);
	while(-f $reqfile) {
		sleep(2) unless(displayManualScanProgress($reqfile, $ttype, $pidpath));
	}

	return $needscan;
}

#*****************************************************************************************************
# Subroutine	: checkCrontabValidity
# In Param		: UNDEF
# Out Param		: Status | Boolean
# Objective		: Checks custom cron tab validity
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub checkCrontabValidity {
	my $ctf		= getCrontabFile();
	return 1 unless(-f $ctf);

	my $ctc		= getFileContents($ctf);
	my $stat	= 1;

	if ($ctc ne '') {
		eval {
			my %ct = %{JSON::from_json(decryptString($ctc))};
			1;
		} or do {
			$stat = 0;
		};
	}

	return $stat;
}

#*****************************************************************************************************
# Subroutine	: checkAccountStatus
# In Param		: UNDEF
# Out Param		: Boolean | Status
# Objective		: Checks account status
# Added By		: Sabin Cheruvattil
# Modified By	: Senthil Pandian
#*****************************************************************************************************
sub checkAccountStatus {
	my $filename = getUserFile();
	return 1 unless(-f $filename);

	my %loginData = ();
	my $fc	= "";
	$fc		= getFileContents($filename);
	Chomp(\$fc);

	return 1 unless($fc =~ m/^\{/);

	my $uname	= getUsername();
	%loginData	= %{JSON::from_json($fc)};
	return 1 if(!exists($loginData{$AppConfig::mcUser}) || !exists($loginData{$AppConfig::mcUser}{'userid'}) || $loginData{$AppConfig::mcUser}{'userid'} ne $uname);

	my $display = defined($_[0])? $_[0] : 1;
	my $accstat = defined($loginData{$AppConfig::mcUser}{'accstat'})? $loginData{$AppConfig::mcUser}{'accstat'} : '';

	return 1 unless($accstat);

	if($accstat ne $AppConfig::activestat) {
		updateUserLoginStatus($uname, 0);

		unless(exists($AppConfig::accfailstat{$accstat})) {
			traceLog('your_account_status_unknown');
			retreat('your_account_status_unknown') if($display);
		} elsif($accstat eq 'UA') {
			traceLog($AppConfig::accfailstat{$accstat});
			retreat('your_account_not_configured_properly_reconfigure') if($display);
		} else {
			traceLog($AppConfig::accfailstat{$accstat});
			retreat($AppConfig::accfailstat{$accstat}) if($display);
		}

		exit(0);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: colorScreenOutput
# Objective				: format text in the given color
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub colorScreenOutput {
	unless (defined &colored) {
		my $cmd = "$AppConfig::perlBin -e 'use Term::ANSIColor;'";
		$cmd = updateLocaleCmd($cmd);
		my $o = `$cmd 2>&1`;
		if ($? == 0) {
			use Term::ANSIColor;
		}
	}

	my $text = $_[0];
	if (defined &colored) {
		my $color = 'black';
		my $bg    = 'yellow';
		if ((lc($text) eq 'on') or (lc($text) eq 'enabled') or ($text eq 'c_running') or (looks_like_number($text) and $text == 1)) {
			$color = 'green';
			$bg    = 'black';
			$text  = 'enabled' if (looks_like_number($text) and $text == 1);
		}
		elsif ((lc($text) eq 'off') or (lc($text) eq 'disabled') or ($text eq 'c_stopped') or (looks_like_number($text) and $text == 0)) {
			$color = 'red';
			$bg    = 'black';
			$text  = 'disabled' if (looks_like_number($text) and $text == 0);
		}
		elsif (lc($text) eq 'running') {
			$color = 'green';
			$bg    = 'black';
		}
		elsif (lc($text) eq 'paused') {
			$color = 'red';
			$bg    = 'black';
		}

		$color = $_[2] if (defined $_[2]);
		$bg    = $_[3] if (defined $_[3]);

		$text = $LS{$text} if (exists $LS{$text});

		$text = colored($text, "bold $color on_$bg");
		if (defined $_[1]) {
			my $sc = $_[1];
			$sc =~ s/s//g;
			$sc = $sc + 14;
			$sc .= 's';
			$text = sprintf("%-$sc", $text);
		}
	}
	else {
		if (defined $_[1]) {
			$text = sprintf("%-$_[1]", $text);
		}
	}

	return $text;
}

#*****************************************************************************************************
# Subroutine			: Chomp
# Objective				: Remove white-space at beginning & end
# Added By				: Senthil Pandian
# Modified By           : Senthil Pandian
#****************************************************************************************************/
sub Chomp{
    if(defined($_[0])) {
        chomp(${$_[0]});
        ${$_[0]} =~ s/^[\s\t]+|[\s\t]+$//g;
    }
}

#*****************************************************************************************************
# Subroutine Name         : checkPreReq
# Objective               : This function will check if restore/backup set file exists and filled.
#							Otherwise it will report error and terminate the script execution.
# Added By                : Abhishek Verma.
# Modified by             : Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************
sub checkPreReq {
	my ($fileName,$jobType,$taskType,$reason) = @_;
	my $userName = getUsername();
	my $errorDir = $AppConfig::jobRunningDir."/".$AppConfig::errorDir;
	my $pidPath  = $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
	my $isEmpty = 0;

	if (!-e $fileName or !-s _) {
		#$AppConfig::errStr = "Your $jobType"."set is empty. ".$LS{'please_update'}."\n";
		#$errStr = "\n".$LS{'your_'.lc($_[0]).'set_is_empty'};
		$AppConfig::errStr = $LS{'your_'.lc($jobType).'set_is_empty'}."\n".$LS{'please_update'}."\n";
		$isEmpty = 1;
	}
	elsif (-s _ > 0 && -s _ <= 50){
		my $outfh;
		if (!open($outfh, "< $fileName")) {
			$AppConfig::errStr = $LS{'failed_to_open_file'}.":$fileName, Reason:$!";
			traceLog($AppConfig::errStr);
			$isEmpty = 1;
		}
		my $buffer = <$outfh>;
		close $outfh;
		Chomp(\$buffer);
		if ($buffer eq ''){
			#$AppConfig::errStr = "Your $jobType"."set is empty. ".$LS{'please_update'}."\n";
			$AppConfig::errStr = $LS{'your_'.lc($jobType).'set_is_empty'}."\n".$LS{'please_update'}."\n";
			$isEmpty = 1;
		}
		close($outfh);
	}

	# if ($isEmpty){
		# print $AppConfig::errStr if ($taskType eq 'manual');
		# my $subjectLine = "$taskType $jobType Status Report "."[$userName]"." [Failed $jobType]";
		# $AppConfig::status = AppConfig::FAILURE;
		# sendMail($taskType,$jobType,$subjectLine,$reason,$fileName);
		# rmtree($errorDir);
		# unlink $pidPath;
		# exit 0;
	# }
	return $isEmpty;
}

#*****************************************************************************************************
# Subroutine			: checkExitError
# Objective				: This function will display the proper error message if evs error found in Exit argument.
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub checkExitError {
	my $errorline = "idevs error";
	my $individual_errorfile   = $_[0];
	my $userJobPaths 		   = $_[1];
	my $needToSkippTermination = 0;
	$needToSkippTermination = 1 if (defined($_[2])); #Added to skip termination for archive cleanup.
	unless(-e $individual_errorfile or -s _ > 0) {
		return 0;
	}
	#check for retry attempt
	if (!open(TEMPERRORFILE, "< $individual_errorfile")) {
		traceLog($LS{'failed_to_open_file'}.":$individual_errorfile, Reason:$!");
		return 0;
	}

	my @linesBackupErrorFile = <TEMPERRORFILE>;
	close TEMPERRORFILE;
	chomp(@linesBackupErrorFile);
	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;

		if ($linesBackupErrorFile[$i] eq "" or $linesBackupErrorFile[$i] =~ m/$errorline/){
			next;
		}

		foreach my $exitErrorMessage (@AppConfig::errorArgumentsExit)
		{
			if ($linesBackupErrorFile[$i] =~ m/$exitErrorMessage/)
			{
				#Avoiding termination for archive cleanup when EVS connection timed out & retrying.
				if (!$needToSkippTermination or $exitErrorMessage !~ m/connection timed out/i) {
					$AppConfig::errStr  = $LS{'operation_could_not_be_completed_reason'}.$exitErrorMessage.".";
					traceLog($AppConfig::errStr);
					#kill evs and then exit
					my $username = getUsername();
					my $jobTerminationScript = getScript('job_termination', 1);
					system(updateLocaleCmd("$AppConfig::perlBin $jobTerminationScript 1>/dev/null 2>/dev/null \'$userJobPaths\' \'$username\'"));

					if ($exitErrorMessage =~ /device is deleted\/removed/i) {
						deleteBackupDevice();
					}

					return "1-$AppConfig::errStr";
				}
			}
		}

		if($linesBackupErrorFile[$i] =~ /unauthorized user|user information not found/i) {
			updateAccountStatus($username, 'UA');
			saveServerAddress(fetchServerAddress());
			#$AppConfig::errStr  = $LS{'operation_could_not_be_completed_please_try_again'};
			#return "1-$AppConfig::errStr";
		}

		if(checkErrorAndUpdateEVSDomainStat($linesBackupErrorFile[$i])) {
			return $linesBackupErrorFile[$i];
		}
	}

	return 0;
}

#****************************************************************************************************
# Subroutine Name         : checkRetryAttempt.
# Objective               : This function checks whether EVS to retry or exit
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub checkRetryAttempt
{
	my $retryAttempt 		 = 0;
	my $reason				 = '';
    my $jobType 		     = $_[0];
	my $path                 = $_[1];
    my @linesBackupErrorFile = ();
    my $errStr               = '';
    my $jobRunningDir        = getJobsPath($jobType);
    my $minimalErrorRetry    = getCatfile($jobRunningDir, "errorretry.min");
    my $pidPath              = getCatfile($jobRunningDir, $AppConfig::pidFile);
    my $errorFilePath        = getCatfile($jobRunningDir, $AppConfig::evsErrorFile);
    my $pwdPath              = getIDPWDFile();

    if (reftype(\$path) eq 'SCALAR') {
 		if (open my $fh, '+<', $path) {
			@linesBackupErrorFile = <$fh>;
			close $fh;
		}
       
    } else {
        @linesBackupErrorFile = $_[1];
    }
	chomp(@linesBackupErrorFile);

	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;
		next if($linesBackupErrorFile[$i] eq "");

        foreach my $err (@AppConfig::errorArgumentsExit)
		{
			if($linesBackupErrorFile[$i] =~ m/$err/)
			{
				if($err=~/skipped-over limit|quota over limit/i){
					$errStr = $LS{'operation_could_not_be_completed_reason'}.$LS{'quota_exceeded'};
				}
				else {
					$errStr = $LS{'operation_could_not_be_completed_reason'}."$err.";
				}
				# @TODO: Check and remove the following trace
				traceLog($errStr);
				#kill evs and then exit
				# my $jobTerminationPath = $currentDir.'/'.Constants->FILE_NAMES->{jobTerminationScript};
				# system(updateLocaleCmd("perl \'$jobTerminationPath\' \'$jobType\' \'$userName\' 1>/dev/null 2>/dev/null"));
                my $username = getUsername();
                my $jobTerminationScript = getScript('job_termination', 1);
                system(updateLocaleCmd("$AppConfig::perlBin $jobTerminationScript 1>/dev/null 2>/dev/null \'$jobType\' \'$username\'"));

				my $exit_flag = "1-$errStr";
				if($jobType =~ /backup/i) {
					unlink($pwdPath) if($errStr =~ /password mismatch/i);
				} else {
					unlink($pwdPath) if($errStr =~ /password mismatch|encryption verification failed/i);
				}
				return ($retryAttempt, $exit_flag);
			}
		}
		# @TODO: Check and remove the following trace
		traceLog("linesBackupErrorFile Line:".$linesBackupErrorFile[$i]);
		waitForNetworkConnection($jobType) if($linesBackupErrorFile[$i] =~ m/Network is unreachable/);
		foreach my $err (@AppConfig::errorListForMinimalRetry) {
			if ($linesBackupErrorFile[$i] =~ m/$err/) {
				$retryAttempt = 1;
				$reason = $err;
                if($err =~ /unauthorized user|user information not found/i) {
                    updateAccountStatus($username, 'UA');
                    saveServerAddress(fetchServerAddress());
                    #$AppConfig::errStr  = $LS{'operation_could_not_be_completed_please_try_again'};
                    #return "1-$AppConfig::errStr";
                }
				elsif($jobType ne 'archive') {
					fileWrite($errorFilePath,$LS{'operation_could_not_be_completed_reason'}.$reason);
					traceLog("Retry Reason: $reason");
				}
				unless (-f $minimalErrorRetry) {
					fileWrite($minimalErrorRetry, '');
				}
				return ($retryAttempt, $reason);
			}
		}

		for(my $j=0; $j<=($#AppConfig::errorArgumentsRetry) and !$retryAttempt; $j++) {
			if ($linesBackupErrorFile[$i] =~ m/$AppConfig::errorArgumentsRetry[$j]/) {
				$retryAttempt = 1;
				$reason = $AppConfig::errorArgumentsRetry[$j];
				# Handle cutoff scenario and if some error is present
				if(-f $pidPath) {
					fileWrite($errorFilePath, $LS{'operation_could_not_be_completed_reason'} . $reason);
					traceLog("Retry Reason: $reason");
				} else {
					traceLog('Job cutoff situation.' . $reason);
				}

				return ($retryAttempt, $reason);
			}
		}
	}

	return ($retryAttempt, $reason);
}

#****************************************************************************************************
# Subroutine Name         : createBackupSetFiles1k.
# Objective               : This function will generate 1000 Backetupset Files
# Added By                : Pooja Havaldar
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub createBackupSetFiles1k {
	my $filesOnlyFlag = $_[0];
	$backupfilecount++;
	my $filesOnly	  		= $AppConfig::jobRunningDir."/".$AppConfig::filesOnly;
	my $noRelativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::noRelativeFileset;
	my $relativeFileset     = $AppConfig::jobRunningDir."/".$AppConfig::relativeFileset;
	my $relative = backupTypeCheck();

	if ($relative == 0) {
		if (defined($filesOnlyFlag) and $filesOnlyFlag eq "FILESONLY") {
			$AppConfig::filesOnlyCount++;
			#print FD_WRITE "$BackupsetFile_Only ".NORELATIVE." $current_source\n";
			print FD_WRITE "$current_source' '".NORELATIVE."' '$BackupsetFile_Only\n";
			$BackupsetFile_Only =  $filesOnly."_".$AppConfig::filesOnlyCount;
			close NEWFILE;
			if (!open NEWFILE, ">", $BackupsetFile_Only) {
				traceLog(['failed_to_open_file', "filesOnly in 1k: $filesOnly to write, Reason: $!."]);
				return 0;
			}
			chmod $AppConfig::filePermission, $BackupsetFile_Only;
		}
		else
		{
			#print FD_WRITE "$BackupsetFile_new#".RELATIVE."#$current_source\n";
			print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
			$BackupsetFile_new = $noRelativeFileset."$AppConfig::noRelIndex"."_$backupfilecount";

			close FH;
			if (!open FH, ">", $BackupsetFile_new) {
				traceLog(['failed_to_open_file', "BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!."]);
				return 0;
			}
			chmod $AppConfig::filePermission, $BackupsetFile_new;
		}
	}
	else {
		#print FD_WRITE "$BackupsetFile_new ".RELATIVE." $current_source\n";
		print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
		$BackupsetFile_new = $relativeFileset."_$backupfilecount";

		close NEWFILE;
		if (!open NEWFILE, ">", $BackupsetFile_new){
			traceLog(['failed_to_open_file', "BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!."]);
			return 0;
		}
		chmod $AppConfig::filePermission, $BackupsetFile_new;
	}

	autoflush FD_WRITE;
	$filecount = 0;

	if ($backupfilecount%15 == 0){
		sleep(1);
	}
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	createBackupTypeFile
# Objective               :	Create files respective to Backup types (relative or no relative)
# Added By                : Dhritikana
#********************************************************************************************************
sub createBackupTypeFile {
	#opening info file for generateBackupsetFiles function to write backup set information and for main process to read that information
	my $info_file 			= $AppConfig::jobRunningDir."/".$AppConfig::infoFile;
	my $noRelativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::noRelativeFileset;
	my $filesOnly	        = $AppConfig::jobRunningDir."/".$AppConfig::filesOnly;
	my $relativeFileset     = $AppConfig::jobRunningDir."/".$AppConfig::relativeFileset;

	if (!open(FD_WRITE, ">", $info_file)){
		traceLog($LS{'failed_to_open_file'} . ":$info_file. Reason:$!");
		return 0;
	}
	chmod $AppConfig::filePermission, $info_file;
	close FD_WRITE; #Needs to be removed

	my $relative = backupTypeCheck();
	#Backupset File name for mirror path
	if ($relative != 0) {
		$BackupsetFile_new =  $relativeFileset;
		if (!open NEWFILE, ">>", $BackupsetFile_new) {
			traceLog($LS{'failed_to_open_file'} . ":$BackupsetFile_new. Reason:$!");
			return 0;
		}
		chmod $AppConfig::filePermission, $BackupsetFile_new;
	}
	else {
		#Backupset File Name only for files
		$BackupsetFile_Only = $filesOnly;
		if (!open NEWFILE, ">>", $BackupsetFile_Only) {
			traceLog($LS{'failed_to_open_file'}.":$filesOnly. Reason:$!");
			return 0;
		}
		chmod $AppConfig::filePermission, $BackupsetFile_Only;
		$BackupsetFile_new = $noRelativeFileset;
	}
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : changeSizeVal.
# Objective               : Changes the size op value based on terminal size change.
# Modified By             : Dhritikana, Senthil pandian.
#*****************************************************************************************************/
sub changeSizeVal {
    #Modified for half screen issue: Senthil
    if(-f $AppConfig::jobRunningDir.'/'.$AppConfig::pidFile) {
        clearScreenAndResetCurPos();
    }

	my $latestCulmnCmd = updateLocaleCmd('tput cols');
	$latestCulmn = `$latestCulmnCmd`;
	chomp($latestCulmn);
	if ($latestCulmn < 100) {
		$AppConfig::progressSizeOp = 2;
	} else {
		$AppConfig::progressSizeOp = 1;
	}
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateServicePath
# Objective				: check .serviceLocation file if exist then try to create servicePath
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub checkAndUpdateServicePath {
	if (loadServicePath()) {
		return 1;
	}
	else {
		my $serviceLocation = getCatfile($appPath, $AppConfig::serviceLocationFile);
		return 0 if (!open(my $sp, '<:encoding(UTF-8)', $serviceLocation));
		my $s = <$sp> || '';
		close($sp);
		unless ($s eq '') {
			chomp($s);
			my $ret;
			if ($AppConfig::callerEnv ne 'BACKGROUND') {
				$AppConfig::callerEnv = 'BACKGROUND';
				$ret = createDir($s);
				$AppConfig::callerEnv = '' ;
			}
			else {
				$ret = createDir($s);
			}

			if ($ret eq 1) {
                $s = getFileContents($serviceLocation); #Added for Suruchi_2.32_10_13: Senthil
				display(["Service directory ", "\"$s\""," created successfully." ],1);
				$servicePath = $s;
				return 1;
			}
			#display(["Service Path ", "\"$s\""," does not exists." ],1);
		}
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine		: createDir
# Objective			: Create a directory
# Added By			: Yogesh Kumar
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub createDir {
	$_[0] =~ s/\/$//;
	my @parentDir = fileparse($_[0]);
	my $recursive = 0;

	if (defined($_[1])) {
		$recursive = $_[1];
	}

	unless (-d $parentDir[1]) {
		if ($recursive) {
			chop($parentDir[1]) if ($parentDir[1] =~/\/$/);
			return 0 unless (createDir($parentDir[1], $recursive));
		}
		else {
			display(["$parentDir[1]: ", 'no_such_directory_try_again']);
			return 0;
		}
	}

	unless (-w $parentDir[1]) {
		display(['cannot_open_directory', " '$parentDir[1]'. ", 'permission_denied']);
		return 0;
	}

	if (mkdir($_[0], 0777)) {
		chmod $AppConfig::filePermission, $_[0];
		return 1;
	}

	return 1 if (($! eq 'File exists') or ($! eq 'Filen existerar') or ($! eq 'Arquivo existe'));

	display(["$_[0]: ", $!]);

	return 0;
}

#*****************************************************************************************************
# Subroutine			: createPvtSCH
# Objective				: This is to create getIDPVTSCH file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub createPvtSCH {
	copy(getIDPVTFile(), getIDPVTSCHFile());
	changeMode(getIDPVTFile());
	changeMode(getIDPVTSCHFile());
}

#*************************************************************************************************
# Subroutine Name		: createLogFiles
# Objective			: Creates the Log Directory if not present, Creates the Error Log and
#					Output Log files based on the timestamp when the backup/restore
#					operation was started, Clears the content of the Progress Details file
# Added By			:
# Modified By 		   	: Abhishek Verma, Yogesh Kumar - Now the logfile name will contain epoch time and job status like (Success, Failure, Aborted) - 17/5/2017
#**************************************************************************************************
sub createLogFiles {
	my $jobType = $_[0];
	my $taskType = (defined($_[1]))?$_[1]:'';
	#our $progressDetailsFileName = "PROGRESS_DETAILS";
	our $outputFileName = $jobType;
	#our $errorFileName = $jobType."_ERRORFILE";
	my $logDir   = $AppConfig::jobRunningDir."/".$AppConfig::logDir;
	my $errorDir = $AppConfig::jobRunningDir."/ERROR";
	#my $ifRetainLogs = getUserConfiguration('RETAINLOGS');
	my $logPidFilePath = getCatfile($AppConfig::jobRunningDir, $AppConfig::logPidFile);

	# if (!$ifRetainLogs) {
		# chmod $AppConfig::filePermission, $logDir;
		# rmtree($logDir);
	# }

	if (!-d $logDir)
	{
		mkdir $logDir;
		chmod $AppConfig::filePermission, $logDir;
	}

#	my $currentTime = localtime;
	my $currentTime = time;#This function will give the current epoch time.
	@startTime = localtime();
	#previous log file name use to be like 'BACKUP Wed May 17 12:34:47 2017_FAILURE'.Now log name will be '1495007954_SUCCESS'.
	my $logFilePath  = getCatfile($logDir, $currentTime."_Running_".$taskType);
	$AppConfig::outputFilePath  = $logFilePath;
	$AppConfig::errorFilePath   = $AppConfig::jobRunningDir."/".$AppConfig::exitErrorFile;
	#$AppConfig::progressDetailsFilePath = $AppConfig::jobRunningDir."/".$progressDetailsFileName;

	#Keeping current log file name in logpid file
	fileWrite($logPidFilePath, $logFilePath) or traceLog('failed_to_open_file');
	chmod $AppConfig::filePermission, $logPidFilePath;
	return $logFilePath;
}

#****************************************************************************************************
# Subroutine Name         : createUpdateBWFile.
# Objective               : Create or update bandwidth throttle value file(.bw.txt).
# Added By                : Avinash Kumar.
# Modified By		      : Dhritikana, Yogesh Kumar, Senthil Pandian
#*****************************************************************************************************/
sub createUpdateBWFile {
	my $bwThrottle = defined $_[0]? $_[0]:getUserConfiguration('BWTHROTTLE');
	my $bwPath     = getUserProfilePath()."/bw.txt";
	fileWrite($bwPath, $bwThrottle) or traceLog('failed_to_open_file');
	chmod $AppConfig::filePermission, $bwPath;
	my @jobs = ('backup','localbackup');
	foreach my $jobName (@jobs) {
		my $jobPath = getJobsPath($jobName, 'path');
		$bwPath     = "$jobPath/bw.txt";
		if(-f $bwPath) {
			my $bw = getFileContents($bwPath);
			if($bw>0) {
				fileWrite($bwPath, $bwThrottle) or traceLog(['failed_to_open_file', " : ", $bwPath]);
				chmod $AppConfig::filePermission, $bwPath;
			}
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : copyBWFile
# Objective               : Copy bandwidth throttle file(bw.txt) to job directory
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub copyBWFile {
	return unless(defined($_[0]));
	my $jobDir     = getJobsPath($_[0], 'path');
	my $userBWPath = getECatfile($jobDir,"bw.txt");
	my $jobBWPath = getECatfile(getUserProfilePath(),"bw.txt");
	system("cp -f $jobBWPath $userBWPath");
}

#*****************************************************************************************************
# Subroutine			: createUserDir
# Objective				: Create user profile directories
# Added By				: Yogesh Kumar
# Modified By           : Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub createUserDir {
	display(["\n",'creating_user_directories'], 1) if(!$AppConfig::isautoinstall and !$_[0]);

	my $err = ();
	for my $path (keys %AppConfig::userProfilePaths) {
		my $userPath = getUsersInternalDirPath($path);
		createDir($userPath, 1);
	}

	display(['user_directory_has_been_created_successfully'], 1) if(!$AppConfig::isautoinstall and !$_[0]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: createUTF8File
# Objective				: Build valid evs parameters
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub createUTF8File {
	loadServerAddress();
	my $evsOP = $_[0];
	my $evsPattern;
	my $thirdParam = 0;
	unless(reftype(\$evsOP) eq 'SCALAR'){
		$evsPattern = $AppConfig::evsAPIPatterns{$_[0]->[0]};
		$utf8File   = $_[0]->[1];
		$thirdParam = 1 if (defined($_[0]->[2]));
	}
	elsif (-d getUserProfilePath()) {
		$utf8File = (getUserProfilePath() ."/$AppConfig::utf8File"."_".lc($evsOP));
		$evsPattern = $AppConfig::evsAPIPatterns{$evsOP};
	}
	else {
		$utf8File = "$servicePath/$AppConfig::tmpPath/$AppConfig::utf8File"."_".lc($evsOP);
		$evsPattern = $AppConfig::evsAPIPatterns{$evsOP};
	}

	my $encodeString = 0;
	$encodeString = 1 if ($evsPattern =~ /--string-encode/);

	my @ep = split(/\n/, $evsPattern);

	my $tmpInd;
	for my $pattern (@ep) {
		my @kNames = $pattern =~ /__[A-Za-z0-9]+__/g;
		for(@kNames) {
			if ($_ =~ /__ARG(.*?)__/) {
				$tmpInd = $1;
				#retreat('insufficient_arguments') unless (defined($_[$tmpInd]));
				$pattern =~ s/$_/$_[$tmpInd]/g;
				next;
			}

			$_ =~ s/__//g;
			my $func = \&{$_};
			my $v = &$func();
			$pattern =~ s/__$_\_\_/$v/g;
		}
	}

	my $evsParams 		= join("\n", @ep);
	my $isDedup  	   	= getUserConfiguration('DEDUP');
	my $backupLocation  = getUserConfiguration('BACKUPLOCATION');
	# Added to handle ITEMSTATUS for archive & remote validation
	if ($evsOP eq 'FILEVERSION' or $thirdParam) {
		$backupLocation = getUserConfiguration('RESTOREFROM');
	}

	if ($isDedup eq "on" and $backupLocation) {
		if ($evsPattern !~ /(--list-device|--nick-update|--link-bucket|--create-bucket)/){
			my $deviceID = (split("#",$backupLocation))[0];
			$evsParams .= "\n--device-id=$deviceID";
		}
	}
	unless ($encodeString) {
		unless ($evsParams =~ /--password-file/) {
			$evsParams .= "\n--password-file=" . getIDPWDFile();
		}

		my $pvtKey  = getIDPVTFile();
		my $encType = getUserConfiguration('ENCRYPTIONTYPE');
		if ($encType eq 'PRIVATE') {
			$evsParams .= "\n--pvt-key=".$pvtKey;
		}

		my $proxyStr = getProxyDetails('PROXY');
		if ($proxyStr){
			my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
			my @UnP = split(/\:/, $uNPword);
			if (scalar(@UnP) >1 and $UnP[0] ne "") {
				$UnP[1] = ($UnP[1] ne '')?decryptString($UnP[1]):$UnP[1];
				foreach ($UnP[0], $UnP[1]) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				$uNPword = join ":", @UnP;
				$proxyStr = "$uNPword\@$ipPort";
			}
			$evsParams .= "\n--proxy=$proxyStr";
		}
		$evsParams .= "\n--encode";
	}
#traceLog("\nevsParams:\n$evsParams\n18425");
	if (open(my $fh, '>', $utf8File)) {
		print $fh $evsParams;
		close($fh);
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: createCRONLink
# Objective				: This subroutine creates link to cron file to a common path
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub createCRONLink {
	my $cronpath = getScript('cron', 1);
	my $linkCronPathCmd = updateLocaleCmd("ln -s $cronpath '$AppConfig::cronLinkPath'");
	`$linkCronPathCmd`;
	chmod($AppConfig::execPermission, $AppConfig::cronLinkPath);
}

#*****************************************************************************************************
# Subroutine			: createScanRequest
# Objective				: This subroutine creates request for scan
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub createScanRequest {
	return 0 unless($_[0]);

	my ($bkppath, $bkpname, $disp, $type, $iscdp, $ondemand, $tshandle) = ($_[0], $_[1], $_[2], $_[3], $_[4], $_[5], $_[6]);
	my $ts 			= $tshandle? time() : '';
	my $scanpath	= getCDPDBDumpFile('scan', lc($bkpname) . "$ts");
	my %scandata	= ();

	$scandata{'path'}		= $bkppath;
	$scandata{'type'}		= $type;
	$scandata{'iscdp'}		= $iscdp? 1 : 0;
	$scandata{'ondemand'}	= $ondemand? 1 : 0;
	if(fileWrite($scanpath, JSON::to_json(\%scandata))) {
		display([$type.'set_scan_request_placed_successfully', '.', "\n"], 1) if($disp);
		return $scanpath;
	}

	display([$type.'set_scan_request_failed', '.', "\n"], 1) if($disp);
	return 0;
}

#*****************************************************************************************************
# Subroutine	: createFailoverScanRequest
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Creates a fail over scan request updating online backup set
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createFailoverScanRequest {
	my $bkpath	= getJobsPath('backup');
	my $cdp		= getUserConfiguration('CDP')? 1 : 0;
	createScanRequest($bkpath, basename($bkpath), 0, 'backup', $cdp, 0);
}

#*****************************************************************************************************
# Subroutine	: createFullScanRequest
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Creates scan request for database
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createFullScanRequest {
	my ($dirswatch, $jsjobselems, $jsitems) = getCDPWatchEntities();
	my $reqfile = getCDPDBDumpFile('rescan', 'all');
	my %rescreq;

	$rescreq{'rsdata'} = $jsitems;
	return $reqfile if(fileWrite($reqfile, JSON::to_json(\%rescreq)));
	return 0;
}

#*****************************************************************************************************
# Subroutine			: createRescanRequest
# Objective				: This subroutine creates request for rescan
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub createRescanRequest {
	my ($dirswatch, $jsjobselems, $jsitems) = getCDPWatchEntities();
	my $reqfile = getCDPDBDumpFile('rescan', 'all');
	my %rescreq;

	my ($custrescan, $jbpath, $jt, $jbname) = (0, '', '', '');
	if($_[0] and $_[1] and exists $AppConfig::availableJobsSchema{$_[0]}) {
		$custrescan = 1;
		$jt = lc($_[0]);
		$jbpath = getJobsPath($jt);
		$jbname = basename($jbpath);
	}

	if($custrescan) {
		$rescreq{'rsdata'}{"$jt|$jbname"} = $_[1];
		$rescreq{'custom'} = 1;
	} else {
		# Exclude local backup from rescan. If local backup needs to be included, comment the following for-each loop.
		foreach my $jobparam (keys(%{$jsitems})) {
			if($jobparam =~ /^localbackup/) {
				delete ${$jsitems}{$jobparam};
				next;
			}
		}

		$rescreq{'rsdata'} = $jsitems;
	}

	return $reqfile if(fileWrite($reqfile, JSON::to_json(\%rescreq)));
	return 0;
}

#*****************************************************************************************************
# Subroutine			: createJobSetSizeCalcRequest
# Objective				: This subroutine creates request for preparing size and count JSON
# Added By				: Sabin Cheruvattil
# Modified By           : Senthil Pandian
#*****************************************************************************************************
sub createJobSetSizeCalcRequest {
	return 0 unless($_[0]);

	my $jobfile = $_[0];
	my %bkpsetinfo;

	$bkpsetinfo{'jsfile'}	= $jobfile;
	$bkpsetinfo{'jsdir'}	= dirname($jobfile) . '/';
	$bkpsetinfo{'jsname'}	= basename($bkpsetinfo{'jsdir'});
	$bkpsetinfo{'jobname'}	= lc(basename(dirname($bkpsetinfo{'jsdir'})));

	# return 1 if(fileWrite(getCDPDBDumpFile('jssize', $bkpsetinfo{'jsname'}), JSON::to_json(\%bkpsetinfo)));
	utf8::decode($bkpsetinfo{'jsname'});
    return 1 if(fileWrite(getCDPDBDumpFile('jssize', $bkpsetinfo{'jsname'}), JSON::to_json(\%bkpsetinfo))); #Modified for junk character in service directory. 

    traceLog("createJobSetSizeCalcRequest failed");
	return 0;
}

#*****************************************************************************************************
# Subroutine			: createJSSizeCalcReqByJobType
# Objective				: This subroutine creates request for preparing size and count JSON based on jobtype backup/localbackup
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub createJSSizeCalcReqByJobType {
	return 0 unless($_[0]);

	my $jobtype		= $_[0];
	my $jobpaths	= getJobsetPathsByJobType($jobtype);

	foreach my $jobname (keys(%{$jobpaths})) {
		createJobSetSizeCalcRequest(getCatfile($jobpaths->{$jobname}, $AppConfig::backupsetFile));
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: createJobSetExclDBRevRequest
# Objective				: Creates a request for revising the DB as the exclude list was modified
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub createJobSetExclDBRevRequest {
	# my $extype = $_[0]? $_[0] : 'all';
    my $extype = 'all';
	my $wait   = $_[1]? 1 : 0;
	my $alljobpaths = getAllBackupJobPaths();
	my $reqfile = getCDPDBDumpFile('ex_db_renew', $extype);

	return 0 if(!fileWrite($reqfile, JSON::to_json($alljobpaths)));

	if($wait) {
		while(-f $reqfile) {
			sleep(1);
			if(!isDBWriterRunning()) {
				unlink($reqfile);
				last;
			}
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine      : createBackupStatFullReset
# Objective       : Create backup status renew request
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub createBackupStatFullReset {
	my $upddbpaths	= getCDPDBPaths();

	foreach my $jbname (keys(%{$upddbpaths})) {
		createBackupStatRenewal($upddbpaths->{$jbname});
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine      : createBackupStatRenewal
# Objective       : Create backup status renew request for a single db
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub createBackupStatRenewal {
	my $dbpath		= $_[0];
	return 0 if(!$dbpath || !-d $dbpath);

	my %resetdata	= ();
	my $dumpfile	= getCDPDBDumpFile('bkpstat_reset', lc(basename($dbpath)));

	$resetdata{'path'} = $dbpath;
	fileWrite($dumpfile, JSON::to_json(\%resetdata));

	return $dumpfile;
}

#*****************************************************************************************************
# Subroutine	: createBackupStatRenewalByJob
# In Param		: Job Type | String
# Out Param		: Request file | String
# Objective		: Places a request for backup set renewal by job type
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createBackupStatRenewalByJob {
	my $job = $_[0];
	return 0 unless($job);

	my $jbpath = getJobsPath($job, 'path');
	return createBackupStatRenewal($jbpath);
}

#*****************************************************************************************************
# Subroutine	: createExpressBackupVerifyRequest
# In Param		: dbpath, mountpath
# Out Param		: Request file | String
# Objective		: Places a request for express backup verification
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createExpressBackupVerifyRequest {
	return '' if(!$_[0] || !$_[1]);

	my $dbpath	= $_[0];
	my $mntpath	= $_[1];

	my %verdata	= ();
	my $dumpfile	= getCDPDBDumpFile('verify_xpres', lc(basename($dbpath)));

	$verdata{'path'}	= $dbpath;
	$verdata{'mntpath'} = $mntpath;
	fileWrite($dumpfile, JSON::to_json(\%verdata));

	return $dumpfile;
}

#*****************************************************************************************************
# Subroutine	: createMPCSelfUpdRequest
# In Param		: dbpath
# Out Param		: Request file | String
# Objective		: Places a request for updating mpc in configuration table
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createMPCSelfUpdRequest {
	return '' unless(!$_[0]);

	my $path	= $_[0];

	my %verdata	= ();
	my $dumpfile	= getCDPDBDumpFile('upd_mpc_self', lc(basename($path)));

	$verdata{'path'}	= $path;
	fileWrite($dumpfile, JSON::to_json(\%verdata));

	return $dumpfile;
}

#*****************************************************************************************************
# Subroutine	: createDBCleanupReq
# In Param		: String | path
# Out Param		: UNDEF
# Objective		: Creates DB cleanup request
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createDBCleanupReq {
	my $dbpath	= $_[0];
	return 0 if(!$dbpath || !-d $dbpath);

	my %cleandata	= ();
	my $dumpfile	= getCDPDBDumpFile('db_cleanp', lc(basename($dbpath)));

	$cleandata{'path'} = getCatfile($dbpath, '');
	fileWrite($dumpfile, JSON::to_json(\%cleandata));

	return $dumpfile;
}

#*****************************************************************************************************
# Subroutine	: createCleanNpMsRequest
# In Param		: String | path, Hash | Files
# Out Param		: UNDEF
# Objective		: Creates missing/no permission file cleanup request
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createCleanNpMsRequest {
	my $dbpath = $_[0];
	my $cleandata = $_[1];

	return 0 if(!$dbpath or !-d $dbpath or !$cleandata);

	my $dumpfile	= getCDPDBDumpFile('rm_nonex_fl');

	my %reqdata;
	$reqdata{'path'} = getCatfile($dbpath, '');
	$reqdata{'npmsfiles'} = $cleandata;
	fileWrite($dumpfile, JSON::to_json(\%reqdata));

	return $dumpfile;
}

#*****************************************************************************************************
# Subroutine	: createCDPAndDBPaths
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks and creates CDP and DB dependency directories
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createCDPAndDBPaths {
	my $crdirs		= [getCDPDBDumpDir(), getFailedCommitDir(), getCommitVaultDir(), getJobsPath('cdp')];
	foreach my $dir (@{$crdirs}) {
		createDir($dir, 1) unless(-d $dir);
	}
}

#*****************************************************************************************************
# Subroutine	: createExcludeInfoFiles
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Creates info files for exclude if doesn't exists
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createExcludeInfoFiles {
	foreach my $excl (keys(%AppConfig::excludeFilesSchema)) {
		my $exinfofile = $AppConfig::excludeFilesSchema{$excl}{'file'};
		$exinfofile =~ s/__SERVICEPATH__/getServicePath()/eg;
		$exinfofile =~ s/__USERNAME__/getUsername()/eg;

		$exinfofile .= '.info';
		if(!-f $exinfofile) {
			fileWrite($exinfofile, "");
		}
	}
}

#*****************************************************************************************************
# Subroutine	: createVersionCache
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Creates version cache file
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createVersionCache {
	my $vcache = getVersionCachePath();
	createDir(getCachedDir(), 1) unless(-d getCachedDir());
	fileWrite($vcache, $_[0]);
	changeMode($vcache);
}

#*****************************************************************************************************
# Subroutine			: checkRetryAndExit
# Objective				: This subroutine checks for retry count and exits if retry exceeded
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkRetryAndExit {
	my $choiceRetry = shift;
	my $newLine		= shift;
	display('') if $newLine;
	retreat('your_max_attempt_reached') if ($choiceRetry == $AppConfig::maxChoiceRetry);
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateClientRecord
# Objective				: This is to check and update the client entry for stats
# Added By				: Anil Kumar
#****************************************************************************************************/
sub checkAndUpdateClientRecord {
	my $freshInstallFile = "$appPath/freshInstall";

	if (-e $freshInstallFile) {
		if (!open(FH, "<", $freshInstallFile)) {
			traceLog("Not able to open $freshInstallFile, Reason:$!");
			return;
		}
		my @idriveUsers = <FH>;
		close FH;
		chomp(@idriveUsers);
		foreach my $user (@idriveUsers) {
			return if ($_[0] eq $user);
		}
	}

	my $isUpdated = updateUserDetail($_[0],$_[1],1);
	if ($isUpdated){
		if (!open(FH, ">>", $freshInstallFile)) {
			return 0;
		}
		print FH $_[0]."\n";
		close FH;
		chmod $AppConfig::filePermission, $freshInstallFile;
	}
}

#*****************************************************************************************************
# Subroutine			: changeMode
# Objective				: Change directory permission to 0777
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub changeMode {
	my $changeModeCmd = updateLocaleCmd("chmod -R 0777 '$_[0]' 2>/dev/null");
	return `$changeModeCmd`;
}

#*****************************************************************************************************
# Subroutine			: createBucket
# Objective				: This subroutine is used to create a bucket
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub createBucket {
	my $deviceName = getAndValidate(['enter_your_backup_location_optional', ': '], "backup_location", 1);
	if ($deviceName eq '') {
		$deviceName = $AppConfig::hostname;
		$deviceName =~ s/[^a-zA-Z0-9_-]//g;
	}
	$AppConfig::deviceUIDsuffix = $deviceName;
	# setUserConfiguration('MUID', ''); #Added to handle dual OS.
	display('setting_up_your_backup_location', 1);
	createUTF8File('CREATEBUCKET',$deviceName) or retreat('failed_to_create_utf8_file');
# traceLog(getFileContents($utf8File));
	my @result = runEVS('item');

	if ($result[0]{'STATUS'} eq AppConfig::SUCCESS) {
		display(['your_backup_to_device_name_is',(" \"" . $result[0]{'nick_name'} . "\".")]);
		setUserConfiguration('SERVERROOT', $result[0]{'server_root'});
		setUserConfiguration('BACKUPLOCATION',
			($AppConfig::deviceIDPrefix . $result[0]{'device_id'} . $AppConfig::deviceIDSuffix .
				'#' . $result[0]{'nick_name'}));

		if(loadNotifications() and lockCriticalUpdate("notification")) {
			setNotification('register_dashboard') and saveNotifications();
			unlockCriticalUpdate("notification");
		}

		createBackupStatRenewalByJob('backup') if(getUsername() ne '' && getLoggedInUsername() eq getUsername());
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: createNotification
# Objective				: create file notification.json
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createNotification {
	my $nf = getNotificationFile();
	unless (-e $nf and !-z $nf) {
		if (open(my $fh, '>', $nf)) {
			unless (flock($fh, LOCK_EX)) {
				traceLog("Cannot lock file $nf $!");
				close($fh);
				return 0;
			}
			seek $fh, 0, 0;
			truncate $fh, 0;
			map{$notifications{$_} = $AppConfig::notificationsSchema{$_}} keys %AppConfig::notificationsSchema;
			print $fh JSON::to_json(\%notifications);
			close($fh);
			return 1;
		}
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: createCrontab
# Objective				: create file crontab.json
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createCrontab {
	my $nf = getCrontabFile();
	my $jobType  = shift  || retreat('crontabs_jobname_is_required');
	my $jobName  = shift  || retreat('crontab_title_is_required');
	my $ctab     = shift;

	$jobType = $AppConfig::availableJobsSchema{$jobType}{'type'} if (exists $AppConfig::availableJobsSchema{$jobType});
	$jobType = 'backup' if ($jobType eq 'local_backup'); # TODO: IMPORTANT to review this statement again.

	#loadCrontab();
	if ($jobType eq "otherInfo") {
		$crontab{$AppConfig::mcUser}{$username}{$jobType} = $jobName;
		return 1;
	}
	unless (exists $crontab{$AppConfig::mcUser}{$username}{$jobType}{$jobName}) {
		$ctab = \%{deepCopyEntry(\%AppConfig::crontabSchema)} unless (defined $ctab);
		if (open(my $fh, '>', $nf)) {
			$crontab{$AppConfig::mcUser}{$username}{$jobType}{$jobName} = $ctab;
			print $fh encryptString(JSON::to_json(\%crontab));
			close($fh);
			chmod($AppConfig::filePermission, $nf);
			return 1;
		}
		else {
			display(['failed_to_open_file', " crontab. $!"]);
		}
		return 0;
	}
	elsif (defined $ctab) {
		if (open(my $fh, '>', $nf)) {
			$crontab{$AppConfig::mcUser}{$username}{$jobType}{$jobName} = deepCopyEntry(\%AppConfig::crontabSchema, $ctab);
			print $fh encryptString(JSON::to_json(\%crontab));
			close($fh);
			chmod($AppConfig::filePermission, $nf);
			return 1;
		}
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: createEncodePwdFiles
# Objective				: Encode user password
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createEncodePwdFiles {
	createUTF8File('STRINGENCODE', $_[0], getIDPWDFile()) or (retreat('failed_to_create_utf8_file'));
	my @responseData = runEVS('Encoded');
	if ($responseData[0]->{'STATUS'} eq AppConfig::FAILURE) {
		retreat(ucfirst($responseData[0]->{'MSG'}));
	}
	changeMode(getIDPWDFile());
	copy(getIDPWDFile(), getIDPWDSCHFile());
	changeMode(getIDPWDSCHFile());
	encryptPWD($_[0]) or retreat('failed_to_encrypt');
}

#*******************************************************************************************
# Subroutine Name         :	convertFileSize
# Objective               :	converts the file size of a file which has been backed up/synced
#                           into human readable format
# Added By                : Vijay Vinoth
#******************************************************************************************
sub convertFileSize
{
	my $fileSize = $_[0];

	my $fileSpec = $AppConfig::fileSizeDetail{'bytes'};

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $AppConfig::fileSizeDetail{'kb'};
	}

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $AppConfig::fileSizeDetail{'mb'};
	}

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $AppConfig::fileSizeDetail{'gb'};
	}

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $AppConfig::fileSizeDetail{'tb'};
	}

	$fileSize = sprintf "%.2f", $fileSize;
	if (0 == ($fileSize - int($fileSize))) {
		$fileSize = sprintf("%.0f", $fileSize);
	}
	return "$fileSize $fileSpec";
}

#*******************************************************************************************
# Subroutine Name         : convertSecondsToReadableTime
# Objective               : Convert seconds to minute/hour/day
# Added By                : Senthil Pandian
# Modified By             : Sabin Cheruvattil
#******************************************************************************************
sub convertSecondsToReadableTime {
	my $secs = $_[0];
	return '0s' if($secs <= 0);

	my %units = (
			'd'	=> 86400, # 24*60*60
			'h'	=> 3600, # 60*60
			'm' => 60,
	);

	$units{'s'} = 1 if($secs < 60);

	my $dateData = 0;
	my $timeStr = '';

	foreach my $name (sort keys %units) {
		my $divisor = $units{$name};
		if (my $quot = int($secs / $divisor)) {
			if($quot > 5 and $name eq 'd') {
				$dateData = 1;
				last;
			}

			if(!($dateData == 1 && $name eq 'm')) {
				$timeStr .= "$quot$name";
				# $timeStr .= (abs($quot) > 1? "" : "") . " ";
				$timeStr .= " ";
				$secs -= $quot * $divisor;
			}
		}
	}

	$timeStr = '5d+ ' if($dateData);

	return $timeStr;
}

#******************************************************************************************************************
# Subroutine Name         : cancelProcess
# Objective               : This subroutine Cancelling the process and removing the intermediate files/folders
# Added By                : Senthil Pandian
#******************************************************************************************************************/
sub cancelProcess {
	my $idevsOutputFile = $AppConfig::jobRunningDir."/".$AppConfig::evsOutputFile;
	my $idevsErrorFile  = $AppConfig::jobRunningDir."/".$AppConfig::evsErrorFile;
	my $pidPath  		= $AppConfig::jobRunningDir."/".$AppConfig::pidFile;

	#Default Cleanup
	system('stty','echo') if(-t STDIN);
	unlink($idevsOutputFile);
	unlink($idevsErrorFile);
	unlink($pidPath);
	exit 1;
}

#****************************************************************************************************
# Subroutine Name         : createDBPathsXmlFile.
# Objective               : Creating DB paths XML file
# Added By                : Senthil Pandian
# Modified By             : Sabin Cheruvattil	
#*****************************************************************************************************/
sub createDBPathsXmlFile {
    my $username       = getUsername();
	my $localUserPath  = $AppConfig::expressLocalDir."/".$username;
	my $xmlFile = $localUserPath."/".$AppConfig::dbPathsXML;
	my $xmlContent = '';
	my ($actualDeviceID,$nickName);
	my $dedup		= getUserConfiguration('DEDUP');

	if ($dedup eq 'off'){
		return;
	}
	my $backupTo	= getUserConfiguration('BACKUPLOCATION');
	my $serverRoot  = getUserConfiguration('SERVERROOT');
	my($backupDeviceID, $backupHost) = split("#",$backupTo);
	if ($backupHost and $backupDeviceID){
		($actualDeviceID,$nickName) = ($backupDeviceID,$backupHost);
		$actualDeviceID =~ s/$AppConfig::deviceIDPrefix//;
		$actualDeviceID =~ s/$AppConfig::deviceIDSuffix//;
	} else {
		display(['your_account_not_configured_properly',"\n\n"]);
		exit;
	}

	my $dbPath = "/LDBNEW/$serverRoot/$username.ibenc";
	if (-e $xmlFile and -s _ > 0){
		open my $fh, '<', $xmlFile;
		read $fh, my $oldXmlContent, -s $fh;
		close $fh;

		if ($oldXmlContent =~ /<dbpaths>/i){
			my @xmlArray = split("\n",$oldXmlContent);
			if (scalar(@xmlArray)>0){
				my $find = "serverroot=\"$serverRoot\"";
				my $isUpdated = 0;
				foreach(@xmlArray){
					my $row = $_;
					if ($row =~ /<dbpathinfo/i and $row =~ /$find/i){
						$row = '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />';
						$isUpdated = 1;
					}
					if ($row =~ /<\/dbpaths>/i){
						last;
					}
					$xmlContent .= $row."\n";
				}
				if ($isUpdated == 0){
					my $row = '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />';
					$xmlContent .= $row."\n";
				}
				$xmlContent .= '</dbpaths>'."\n";
			}
		}
	} else {
		$xmlContent  = '<?xml version="1.0" encoding="utf-8"?>'."\n";
		$xmlContent .= '<dbpaths>'."\n";
		$xmlContent .= '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />'."\n";
		$xmlContent .= '</dbpaths>'."\n";
	}
	open XMLFILE, ">", $xmlFile or (print "Unable to create file: $xmlFile, Reason:$!" and die);
	print XMLFILE $xmlContent;
	close XMLFILE;
	chmod $AppConfig::filePermission, $xmlFile;
}

#*********************************************************************************************************
# Subroutine Name		: createLocalBackupDir
# Objective				: This function will create the directories for local backup.
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#*********************************************************************************************************/
sub createLocalBackupDir {
    my $username       = getUsername();
	my $localUserPath  = $AppConfig::expressLocalDir."/".$username;
	createDir($AppConfig::expressLocalDir, 1);
	createDir($localUserPath, 1);
	my $serverRoot  = getUserConfiguration('SERVERROOT');
	my $dedup		= getUserConfiguration('DEDUP');

	if ($dedup eq 'on'){
		$backupLocationDir  = "$localUserPath/$serverRoot/";
	} else {
		my $backupHost	  = getUserConfiguration('BACKUPLOCATION');
		if ($AppConfig::jobType eq "LocalBackup") {
			my @backupTo = split("/",$backupHost);
			$backupHost	 = (substr($backupHost,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
			$backupLocationDir  = "$localUserPath/$backupHost/";
		} else {
			$backupLocationDir  = "$localUserPath/$backupHost/";
		}
	}
	createDir($backupLocationDir, 1);
}

#*****************************************************************************************************
# Subroutine			: confirmStartDashboard
# Objective				: This is to restart IDrive Dashboard service
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub confirmStartDashboard {
	unless (hasDashboardSupport() and (getRemoteManageIP() ne '')) {
		display(['failed_to_start_dashboard_service', '.', "\n"]);
		return 0;
	}

	my $display = ((defined($_[0]) && $_[0] == 1)? 1 : 0);

	if (isDashboardRunning()) {
		display(["\n", 'dashboard_service_running', '. ']) if ($display and !$AppConfig::isautoinstall);
		return 1;
	}

	my $reflag = ((defined $_[1])? 're' : '');
	display(["\n", $reflag . 'starting_dashboard_service', '...']) if ($display and !$AppConfig::isautoinstall);
	system(updateLocaleCmd(getIDrivePerlBin() . " " . getDashboardScript(1) ." 2>/dev/null &"));
	sleep(3);

	if ($display) {
		if (isDashboardRunning()) {
			display(['dashboard_service_' . $reflag . 'started', '.', "\n"]) unless($AppConfig::isautoinstall);
		} else {
			display(['failed_to_' . $reflag . 'start_dashboard_service', '.', "\n"]);
		}
	}

	return 1;
}

#****************************************************************************************************
# Subroutine		: checkErrorAndReturnErrorMessage
# Objective			: This function will check the error & return proper error message
# Added By			: Senthil Pandian
#*****************************************************************************************************/
sub checkErrorAndReturnErrorMessage {
	return $_[0] if (!defined($_[0]) or $_[0] eq '');

    my $errStr = $_[0];
	if ($errStr =~ /account is under maintenance|account has been cancelled|account has been blocked/i){
		if ($errStr =~ /account is under maintenance/i){
			if (defined($_[1])){
				$errStr	 = $LS{'your_account_is_under_maintenance'}
			} else {
				$errStr .= " ".$LS{'please_contact_support_for_more_information'};
			}
		}
		elsif ($errStr =~ /account has been blocked/i){
			if (defined($_[1])){
				$errStr	 = $LS{'your_account_has_been_blocked'}
			} else {
				$errStr .= " ".$LS{'please_contact_admin_to_unblock'};
			}
		}
		elsif ($errStr =~ /account has been cancelled/i){
			if (defined($_[1])){
				$errStr	 = $LS{'your_account_has_been_cancelled'}
			} else {
				$errStr .= " ".$LS{'please_contact_support_for_more_information'};
			}
		}
	}

	return $errStr;
}

#****************************************************************************************************
# Subroutine		: checkErrorAndLogout
# Objective			: This function will check the error & logout
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil, Yogesh Kumar
#*****************************************************************************************************/
sub checkErrorAndLogout {
	return $_[0] if (!defined($_[0]) or $_[0] eq '');

	my $errStr = $_[0];
	my $cuser = getUsername();

	if (loadUsername() and (getUsername() ne $cuser)) {
		setUsername($cuser);
		return 0;
	}

	checkAndUpdateAccStatError($cuser, $errStr);

	if($_[2] && grep{$errStr =~ /\Q$_\E/} @AppConfig::errorLogoutArgs) {
		my $cmd = sprintf("%s %s 1 0", $AppConfig::perlBin, getScript('logout', 1));
		system($cmd);
		traceLog('logout');
	}

	if ($errStr =~ /account is under maintenance|account has been cancelled|account has been blocked/i){
		stopDashboardService($AppConfig::mcUser, getAppPath());
		if ($errStr =~ /account is under maintenance/i){
			if (defined($_[1])){
				$errStr	 = $LS{'your_account_is_under_maintenance'}
			} else {
				$errStr .= " ".$LS{'please_contact_support_for_more_information'};
			}

			lockCriticalUpdate("cron");
			loadCrontab();
			setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
			saveCrontab();
			unlockCriticalUpdate("cron");
		}
		elsif ($errStr =~ /account has been blocked/i){
			if (defined($_[1])){
				$errStr	 = $LS{'your_account_has_been_blocked'}
			} else {
				$errStr .= " ".$LS{'please_contact_admin_to_unblock'};
			}

			lockCriticalUpdate("cron");
			loadCrontab();
			setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
			saveCrontab();
			unlockCriticalUpdate("cron");
		}
		elsif ($errStr =~ /account has been cancelled/i){
			if (defined($_[1])){
				$errStr	 = $LS{'your_account_has_been_cancelled'}
			} else {
				$errStr .= " ".$LS{'please_contact_support_for_more_information'};
			}
			removeUsersCronEntry();
			removeIDriveUserFromUsersList();
		}
	}

	return $errStr;
}

#*****************************************************************************************************
# Subroutine			: confirmRestartIDriveCRON
# Objective				: This confirms and restarts the cron service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub confirmRestartIDriveCRON {
	my $restartcron = 'y';
	if (checkCRONServiceStatus() == CRON_RUNNING) {
		display(["\n", 'cron_service_running', '. ', 'do_you_want_to_restart_cron_yn']);
		$restartcron = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	# if cron link is absent, reinstall the cron | this case can be caused by uninstallation from other installation
	unless(-f $AppConfig::cronLinkPath) {
		my $sudoprompt = 'please_provide_' . (hasSudo()? 'sudoers' : 'root') . '_pwd_for_cron';
		my $sudosucmd = getSudoSuCRONPerlCMD('installcron', $sudoprompt);
		system($sudosucmd);

		display(['started_cron_service',"\n"]) if(checkCRONServiceStatus() == CRON_RUNNING);

		return 1;
	}

	restartIDriveCRON(1) if ($restartcron eq 'y');

	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkAndStartDashboard
# Objective				: This confirms and starts the dashboard service
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub checkAndStartDashboard {
	return 1 unless (hasDashboardSupport() and !getUserConfiguration('DDA'));

	if (isDashboardRunning()) {
#		display(["\n", 'dashboard_service_running', '. ']) if (!defined($_[0]) || $_[0] == 1);
		return 1;
	}

	# NO-DEDUP + aarch64 is not supported
	loadMachineHardwareName();
	return 0 if ((getUserConfiguration('DEDUP') eq 'off') and (getMachineHardwareName() eq "aarch64"));

	confirmStartDashboard(1, $_[1]);
	sleep(1);

	return 1;
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
	if (-e $permissionError and !-z $permissionError){
		$summaryError .= "[INFORMATION]".$lineFeed;
		$summaryError .= (('-') x 13).$lineFeed;
		open DENIED_FILE, "<", $permissionError or traceLog(Constants->CONST->{'FileOpnErr'}." $permissionError. Reason $!");
		my $byteRead = read(DENIED_FILE, my $buffer, $AppConfig::maxLogSize);
		$buffer =~ s/(\] \[FAILED\] \[)/\] \[INFORMATION\] \[/g; #Replacing "FAILED" with "INFORMATION"
		$summaryError.= $buffer;
		close DENIED_FILE;
	}
	unlink($permissionError);
	return $summaryError;
}


#****************************************************************************************************
# Subroutine Name	: currentLocale
# Objective			: Check current machine language is english.
# Modified By		: Vijay Vinoth
#*****************************************************************************************************/
sub currentLocale {
	my $current_locale = setlocale(LC_CTYPE);
	if(substr($current_locale, 0, 2) eq 'en'){
		return 1;
	}
	return 0;
}

#****************************************************************************************************
# Subroutine Name         : createLogJsonForOldUser
# Objective               : Create log JSON file after migration of old user data
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub createLogJsonForOldUser {
	my @userList;
	if (-d "$servicePath/$AppConfig::userProfilePath"){
		opendir(USERPROFILEDIR, "$servicePath/$AppConfig::userProfilePath") or die $!;
		while (my $lmUserDir = readdir(USERPROFILEDIR)) {
			# Use a regular expression to ignore files beginning with a period
			next if ($lmUserDir =~ m/^\./);
			if (-d "$servicePath/$AppConfig::userProfilePath/$lmUserDir"){
				opendir(LMUSERDIR, "$servicePath/$AppConfig::userProfilePath/$lmUserDir") or die $!;
				while (my $idriveUserDir = readdir(LMUSERDIR)) {
					# Use a regular expression to ignore files beginning with a period
					next if ($idriveUserDir =~ m/^\./);
					if (-d "$servicePath/$AppConfig::userProfilePath/$lmUserDir/$idriveUserDir"){
						push(@userList, "$servicePath/$AppConfig::userProfilePath/$lmUserDir/$idriveUserDir");
					}
				}
				closedir(LMUSERDIR);
			}
		}
		closedir(USERPROFILEDIR);

		if (scalar(@userList)>0){
			my @jobTypes = ("backup", "localbackup", "restore", "archive");
			my $logFileListToUpload = "$servicePath/$AppConfig::userProfilePath/".$AppConfig::migratedLogFileList;
			if (!open NEWFILE, ">", $logFileListToUpload) {
				traceLog($LS{'failed_to_open_file'}.":$logFileListToUpload. Reason:$!");
				return 0;
			}
			chmod $AppConfig::filePermission, $logFileListToUpload;
			for my $userDir (@userList){
				for my $job (@jobTypes){
					my $userLogDir = $userDir."/".$AppConfig::userProfilePaths{$job}."/".$AppConfig::logDir;
					if (defined($userLogDir) and -d $userLogDir){
						my %logFileList	= getLogsList($userLogDir);
						my ($startEpoch, $endEpoch) = ('', '');
						($startEpoch, $endEpoch) = getStartAndEndEpochTimeForMigration(\%logFileList);
						my $slf = getLastOneWeekLogs(\%logFileList, $startEpoch, $endEpoch,$userLogDir);
						my $logFileName;
						addLogStat($userDir."/".$AppConfig::userProfilePaths{$job}."/", $slf) if (%{$slf});
					}
				}
			}
			close NEWFILE;
			unlink($logFileListToUpload) if (-z $logFileListToUpload);
			saveMigratedLog();
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : createServiceDirectory
# Objective               : Create service directory
# Added By                : Senthil Pandian
# Modified By             : Sabin Cheruvattil
#*****************************************************************************************************/
sub createServiceDirectory {
	my $servicePathSelection = '';
	
	unless($AppConfig::isautoinstall) {
		display('enter_your_service_path', 0);
		$servicePathSelection = getUserChoice();
		$servicePathSelection =~ s/^~/getUserHomePath()/g;
	}

	# In case user want to go for optional service path
	if ($servicePathSelection eq ''){
		$servicePathSelection = dirname(getAppPath());
		display(['your_default_service_directory'], 1) unless($AppConfig::isautoinstall);
	}

	# Check if service path exist
	retreat(['invalid_location', " \"$servicePathSelection\". ", "Reason: ", 'no_such_directory']) if (!-d $servicePathSelection);

	# Check if service path have write permission
	retreat(['cannot_open_directory', " $servicePathSelection ", 'permission_denied'])	if (!-w $servicePathSelection);

	# get full path for service directory
	$servicePathSelection = getCatfile($servicePathSelection, $AppConfig::servicePathName);
	my $sp = '';
	my $servicePathExists = 0;
	$sp = getAbsPath($servicePathSelection) or retreat('no_such_directory_try_again');
	my $oldServiceLocation = $sp;
	$oldServiceLocation =~ s/$AppConfig::servicePathName$/$AppConfig::oldServicePathName/;
	if (-d $oldServiceLocation){
		saveServicePath($oldServiceLocation) or retreat('failed_to_create_service_location_file');
		initiateMigrate();
	}

	if (-d $sp) {
		display(["Service directory ", "\"$sp\" ", 'already_exists']) unless($AppConfig::isautoinstall);
	}
	else {
		createDir($sp) or retreat('failed');
	}

	saveServicePath($sp) or retreat('failed_to_create_service_location_file');
	loadServicePath() or retreat('invalid_service_directory');
	unless($AppConfig::isautoinstall) {
		display(["\n", 'your_service_directory_is', getServicePath()]);
	} else {
		display(['default_service_directory_path', ': ', getServicePath()]);
	}
}

#*****************************************************************************************************
# Subroutine			: customReName
# Objective				: Used to rename file/files inside the folder customReName($path,$find,$replace)
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub customReName{
	my $inputPath = $_[0];
	my $findPattern = $_[1];
	my $replacePattern = $_[2];
	if (-f $inputPath){
		my $newname = $inputPath;
		$newname =~ s/$findPattern/$replacePattern/g;
		rename $inputPath, $newname;
	}
	elsif (-d $inputPath){
		if (opendir(CUSTOMDIR, $inputPath)) {
			foreach my $file (readdir(CUSTOMDIR))  {
				if ($file eq '.' or $file eq '..') {
					next;
				}
				chomp($file);
				my $newname = $inputPath."/".$file;
				$newname = $newname."_ABORTED"	if (index($file, "_") == -1);
				$file = $inputPath."/".$file;
				$newname =~ s/$findPattern/$replacePattern/g;
				rename $file,$newname  or traceLog("rename failed because Reason:$!");
			}
			closedir(CUSTOMDIR);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: checkPidAndExit
# Objective				: Exit if pid not present & display error if exitError.txt present
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkPidAndExit{
	my $jobRunningDir	= defined($_[0])?$_[0]:$AppConfig::jobRunningDir;
	my $pidPath			= $jobRunningDir.'/'.$AppConfig::pidFile;
	unless (-e $pidPath){
		my $cancelExitFilePath = $jobRunningDir.'/'.$AppConfig::exitErrorFile;
		if (-e $cancelExitFilePath and (-s $cancelExitFilePath > 0)){
			retreat(['operation_cancelled_by_user']);
		}
		unlink($cancelExitFilePath);
	}
}

#*****************************************************************************************************
# Subroutine			: checkAndAvoidExecution
# Objective				: check and avoid the execution of supporting perl scripts.
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub checkAndAvoidExecution {
    return 1;
=beg
	$AppConfig::displayHeader = 0;

	my $ppid = getppid();
	my $ps = `ps -o command $ppid`;
	chomp $ps;
	if ($ps !~ /\.pl|cron|system|init|upstart|IDrive:dashboard|su\ \-m/ and $ps ne 'COMMAND' ) {
		traceLog("checkAndAvoidExecution ppid:$ppid#ps:$ps#");
		retreat('you_cant_run_supporting_script');
	}
=cut
}

#*****************************************************************************************************
# Subroutine			: checkMinMaxVersion
# Objective				: This subroutine is to check min/max version to update/downgrade the current package.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkMinMaxVersion {
	my @zipped  = split('\.', $_[1]);
    my $pos = getMinMaxVersion($_[0]);
	my %pos = %{$pos};

	if (scalar(keys %pos)) {
		my @min = split('\.', $pos{'min'});
		my @max = split('\.', $pos{'max'});
		for my $i (0 .. scalar(@zipped)) {
			if (defined($zipped[$i]) && defined($min[$i])) {
				return 2 if ($zipped[$i] < $min[$i]); # Returning if version is lower than limit.
			}
			# if (defined($zipped[$i]) && defined($max[$i])) {
				# return 3 if ($zipped[$i] > $max[$i]); # Returning if version is higher than limit.
			# }
		}
		return 1; # Returning if version is within limit.
	}
	return 0; # Returning if there is no limit avaialble for the current script version.
}

#*************************************************************************************************
# Subroutine		: cleanupUpdate
# Objective			: cleanup the update process
# Added By			: Sabin Cheruvattil
# Modified By		: Yogesh Kumar
#*************************************************************************************************/
sub cleanupUpdate {
	my $packageName = qq(/$AppConfig::tmpPath/$AppConfig::appPackageName$AppConfig::appPackageExt);
	unlink($packageName) if (-e $packageName && (!defined($ARGV[0]) or $ARGV[0] ne $packageName));

	my $packageDir = qq(/$AppConfig::tmpPath/$AppConfig::appPackageName);
	removeItems($packageDir) if ($packageDir ne '/' && -e $packageDir);
	my $scriptBackupDir = qq(/$AppConfig::tmpPath/$AppConfig::appType) . q(_backup);
	removeItems("$scriptBackupDir") if ($scriptBackupDir ne '/' && -e $scriptBackupDir);
	removeItems("$AppConfig::tmpPath/scripts") if (-e qq($AppConfig::tmpPath/scripts));
	unlink(getAppPath() . qq(/$AppConfig::unzipLog));
	unlink(getAppPath() . qq(/$AppConfig::updateLog));

	my $pidPath = getCatfile(getServicePath(), $AppConfig::pidFile);
	unlink($pidPath) if (-f $pidPath);

	my $preupdpid	= getCatfile(getCachedDir(), $AppConfig::preupdpid);
	my $updpid		= getCatfile(getCachedDir(), $AppConfig::updatePid);
	unlink($preupdpid) if(-f $preupdpid);
	unlink($updpid) if(-f $updpid);

	exit(0) unless(defined($_[0]));

	$AppConfig::displayHeader = 0;
	retreat($_[0]) if ($_[0] ne 'INIT');
}

#****************************************************************************************************
# Subroutine Name         : clearProgressScreen
# Objective               : This subroutine will clear the progress screen
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub clearProgressScreen
{
	my $freebsdProgress = '';
	my $latestCulmnCmd  = updateLocaleCmd('tput cols');
	my $latestCulmn     = `$latestCulmnCmd`;
	my $lineCount       = 40;
	my $totalLinesCmd   = updateLocaleCmd('tput lines');
	my $totalLines      = `$totalLinesCmd`;
	chomp($totalLines) if($totalLines);
	$lineCount = $totalLines if($totalLines);
	for(my $i=0; $i<=$lineCount; $i++){
		$freebsdProgress .= (' ')x$latestCulmn;
		$freebsdProgress .= "\n";
	}
	print $freebsdProgress;
}

#****************************************************************************************************
# Subroutine Name         : checkScreeSize
# Objective               : This subroutine will check scree size whether to expand the progress screen or not.
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub checkScreeSize
{
	# my $latestCulmnCmd  = updateLocaleCmd('tput cols');
	# my $latestCulmn     = `$latestCulmnCmd`;
    # chomp($latestCulmn) if($latestCulmn);
	my $totalLinesCmd   = updateLocaleCmd('tput lines');
	my $totalLines      = `$totalLinesCmd`;
	chomp($totalLines) if($totalLines);
    $AppConfig::allowExtentedView = 1;
    if($AppConfig::totalEngineBackup == $AppConfig::maxEngineCount) {
        if($totalLines < 30){
            $AppConfig::allowExtentedView = 0;
        } elsif($AppConfig::progressSizeOp == 2 and $totalLines < 40) {
            $AppConfig::allowExtentedView = 0;
        }
    } elsif($AppConfig::totalEngineBackup == $AppConfig::minEngineCount) {
        if($totalLines < 25){
            $AppConfig::allowExtentedView = 0;
        } elsif($AppConfig::progressSizeOp == 2 and $totalLines < 30) {
            $AppConfig::allowExtentedView = 0;
        }
    }
    return $AppConfig::allowExtentedView;
}

#****************************************************************************************************
# Subroutine Name         : clearScreenAndResetCurPos
# Objective               : This subroutine will clear the progress screen & reset the cursor position
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub clearScreenAndResetCurPos {
    system("clear");
    print " ".$lineFeed;
	system(updateLocaleCmd("tput sc"));
}

#*****************************************************************************************************
# Subroutine/Function   : configAccount
# In Param    : configType (DEFAULT/PRIVATE)
# Out Param   : 1 if success
# Objective	  : This subroutine to configure the user account
# Added By	  : Senthil Pandian
# Modified By : Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub configAccount {
	my $configType    = $_[0];
	my $encKey        = $_[1];
	my $evsWebServer  = getUserConfiguration('WEBAPI');
	my $configTypeKey = ($configType eq 'PRIVATE')?'PRIVATECONFIG':'DEFAULTCONFIG';
	createUTF8File($configTypeKey, $evsWebServer) or retreat('failed_to_create_utf8_file');
	my @result = runEVS('tree');
	if ($result[0]->{'STATUS'} eq 'FAILURE') {
		retreat($LS{'failed_to_configure'}.ucfirst($result[0]->{'MSG'}));
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: convert_seconds_to_hhmmss
# Objective				: This subroutine converts the seconds to hh:mm:ss format
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub convert_seconds_to_hhmmss {
  return $_[0] unless($_[0] =~ /^\d+$/);
  my $hourz=int($_[0]/3600);
  my $leftover=$_[0] % 3600;
  my $minz=int($leftover/60);
  my $secz=int($leftover % 60);
  return sprintf ("%02d:%02d:%02d", $hourz,$minz,$secz);
}

#*****************************************************************************************************
# Subroutine			: convert_to_unixtimestamp
# Objective				: This subroutine converts the localtime to unixtimestamp
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub convert_to_unixtimestamp {
	my ($date, $time, $ampm) = split(" ", $_[0]); #2021/08/26 14:14:16 
	my ($year, $mon, $mday) = split('/', $date);
	my ($hour, $min, $sec)  = split(':', $time);
	if(defined($ampm)) {
		#08/26/2021 12:14:16 am
		($mon, $mday, $year) = split('/', $date);
		$hour  = 0 if($hour ==12);
		$hour += 12 if($ampm eq 'pm');
	}
	my $timestamp = mktime($sec,$min,$hour,$mday,$mon-1,$year-1900);
	return $timestamp;
}

#********************************************************************************
# Subroutine	: checkAndUpdateEVSDomainConnStat
# In Param		: 
# Out Param		: Status | Boolean
# Objective		: This subroutine to check EVS domain connection & update stat.
# Added By		: Senthil Pandian
# Modified By	: 
#********************************************************************************
sub checkAndUpdateEVSDomainConnStat {
	if(getUserConfiguration('EVSSRVR')) {
		if(getUserConfiguration('DEDUP') eq 'on') {
			my @devices = fetchAllDevices();
			if ($devices[0]{'STATUS'} eq AppConfig::FAILURE) {
				if($devices[0]->{'MSG'} =~ /Name or service not known/i) {
					setUserConfiguration('EVSSRVRACCESS', 0);
					traceLog('EVS domain name not connecting');
					return 0;
				}
			}
		} elsif(getUserConfiguration('DEDUP') eq 'off') {
			createUTF8File('PING')  or retreat('failed_to_create_utf8_file');
			my @responseData = runEVS();
			if (($responseData[0]->{'STATUS'} eq AppConfig::FAILURE)) {
				setUserConfiguration('EVSSRVRACCESS', 0);
				traceLog('EVS domain name not connecting');
				return 0;
			}
		}
		setUserConfiguration('EVSSRVRACCESS', 1);
	} else {
		setUserConfiguration('EVSSRVRACCESS', 0);
	}
	saveUserConfiguration() or traceLog('failed_to_save_user_configuration') if(-f getUserConfigurationFile());
	return 1;
}

#********************************************************************************
# Subroutine	: checkErrorAndUpdateEVSDomainStat
# In Param		: 
# Out Param		: Status | Boolean
# Objective		: This subroutine to check EVS error & update stat.
# Added By		: Senthil Pandian
# Modified By	: 
#********************************************************************************
sub checkErrorAndUpdateEVSDomainStat {
	my $error = $_[0];
	if(getUserConfiguration('EVSSRVRACCESS') and ($error =~ m/Name or service not known/i)) {
		setUserConfiguration('EVSSRVRACCESS', 0);
		saveUserConfiguration() or traceLog('failed_to_save_user_configuration');
		traceLog("EVS domain failed & need to retry with IP");
		return 1;
	}
	return 0;
}

#------------------------------------------------- D -------------------------------------------------#

#*******************************************************************************************************
# Subroutine Name         :	deactivateOtherUserCRONEntries
# Objective               :	Update cron entry with inactive status
# Added By                : Sabin Cheruvattil
#********************************************************************************************************/
sub deactivateOtherUserCRONEntries {
	return 0 if($AppConfig::appType eq 'IBackup');
	return 0 unless($_[0]);

	my $curuser = $_[0];

	if (exists $crontab{$AppConfig::mcUser}) {
		lockCriticalUpdate("cron");
		loadCrontab();

		foreach my $idusername (keys %{$crontab{$AppConfig::mcUser}}) {
			if ($curuser ne $idusername) {
				setUsername($idusername);
				createCrontab('otherInfo', {'settings' => {'status' => 'INACTIVE', 'lastActivityTime' => time()}});
				setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
				saveCrontab();
			}
		}

		unlockCriticalUpdate("cron");

		setUsername($curuser);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: deepCopyEntry
# Objective				: deep copy entries from the given args
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub deepCopyEntry {
	my ($ref) = $_[0];
	my ($ref2) = $_[1];

	if (ref($ref) eq 'HASH') {
		return ({map {$_ => deepCopyEntry($ref->{$_}, $ref2->{$_})} sort keys %$ref});
	}
	elsif (ref($ref) eq 'ARRAY') {
		return [map {deepCopyEntry($_)} @$ref];
	}
	else {
		return $ref2 || $ref;
	}
}

#*****************************************************************************************************
# Subroutine			: decryptString
# Objective				: Decrypt the given data
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub decryptString {
	return '' unless $_[0];

	my $encString  = $_[0];
	my $stringLength	= length $encString;
	my $swapLength		= $stringLength - ($stringLength % 4);
	my $shiftLength		= $swapLength/4;

	my $swpa			= substr($encString, 0, $shiftLength);
	my $swpb			= substr($encString, (3 * $shiftLength), $shiftLength);

	substr($encString, (3 * $shiftLength), $shiftLength) = $swpa;
	substr($encString, 0, $shiftLength) = $swpb;

	$encString = decode_base64($encString);

	return $encString;
}

#*****************************************************************************************************
# Subroutine			: display
# Objective				: Prints formated data to stdout
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub display {
	return 0 if ($AppConfig::callerEnv eq 'BACKGROUND');
	my $message = $_[0];
	my $msg = '';
	my $endWithNewline = 1;

	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}
	for my $i (0 .. $#{$message}) {
		next if (!defined($message->[$i]) or $message->[$i] eq '');
		if (exists $LS{$message->[$i]}) {
			$msg .= $LS{$message->[$i]};
		}
		elsif (exists $Help{$message->[$i]}) {
			$msg .= $Help{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}

	if (defined($_[2])) {
		my $c = 1;
		for my $i (0 .. $#{$_[2]}) {
			$msg =~ s/__ARG$c\__/$_[2]->[$i]/g;
			$c++;
		}
	}
	print "$msg";
	$endWithNewline    = $_[1] if (defined($_[1]));
	print "\n" if ($endWithNewline);
}

#**********************************************************************************************
# Subroutine             : displayFinalSummary(SCALAR,SCALAR);
# Objective              : It display the final summary after the backup/restore job has been completed.
# Usage                  : displayFinalSummary(JOB_TYPE,FINAL_SUMMARY_FILE_PATH);
# Added By               : Abhishek Verma
# Modified By            : Senthil Pandian, Sabin Cheruvattil
#**********************************************************************************************
sub displayFinalSummary {
	my ($jobType,$finalSummaryFile) = @_;
	my $errString = undef;
	my $jobStatus;

	if (-f $finalSummaryFile and !-z _)
	{
		if($jobType !~ /archive/i){
			if (open(FS,'<',$finalSummaryFile)){#FS file handel means (F)ile (S)ummary.
				chomp(my @fileSummary = <FS>);
				close(FS);
				$errString	= pop (@fileSummary) if ($#fileSummary > 7);
				$jobStatus	= pop (@fileSummary);
				my $logFilePath = pop (@fileSummary);
				my $fileSummary = join ("\n",@fileSummary);
		#		if ($jobStatus eq 'SUCCESS' or $jobStatus eq 'SUCCESS*'){
				if ($jobStatus eq 'Success' or $jobStatus eq 'Success*'){
					$jobStatus = qq($jobType has been completed.);
				}elsif ($jobStatus eq 'Failure' or $jobStatus eq 'Aborted'){
					$jobStatus = defined ($errString) ? $errString : qq($jobType has failed.);
				}

                print qq(\n$jobStatus\n$fileSummary\n);
                print qq(\n$logFilePath\n) if($logFilePath);
				#unlink($finalSummaryFile);
			}
		} else {
			my $summary = getFileContents($finalSummaryFile);
			display($summary);
			# my @summaryArray = split("###",$summary);
			# my $fileSummary = $summaryArray[0];
			# $jobStatus = defined($summaryArray[1])?$summaryArray[1]:'';
			# if ($jobStatus eq 'Success' or $jobStatus eq 'Success*'){
				# $jobStatus = qq($jobType has completed.);
			# }elsif ($jobStatus eq 'Failure' or $jobStatus eq 'Aborted'){
				# $jobStatus = defined ($errString) ? $errString : qq($jobType has failed.);
			# }
			# $jobStatus .= "\n" if($jobStatus);
			# print qq(\n$jobStatus$fileSummary\n);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: displayHeader
# Objective				: Display header for the script files
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub displayHeader {
	return 1 if ($AppConfig::callerEnv eq 'BACKGROUND');

	if ($AppConfig::displayHeader) {
		$AppConfig::displayHeader = 0;
		my $w = (split(' ', $AppConfig::screenSize))[-1];
		my $adjust = 0;
		$w += 0;
		$w = ($w > 90)? 90 : $w;

		my $indent = 25;
		if ($username and -e getServerAddressFile()) {
			if (loadStorageSize()) {
				$indent = 45;
			} else {
				# Modified to fetch recalculted size : Senthil
				reCalculateStorageSize('header');
				$indent = 45 if(loadStorageSize());
			}
		}

		my $header = qq(=) x $w;
		my $h = "Version: $AppConfig::version";
		my $l = length($h);
		$header    .= qq(\n$h);
		$header    .= (qq( ) x ($indent - ($l - $adjust)) . qq($LS{'developed_by'} ));
		$header    .= qq($LS{lc($AppConfig::appType . '_maintainer')}\n);
		$header    .= (qq(-) x $l . qq( ) x ($indent - ($l - $adjust)) . qq(-) x ($w - ($l+ ($indent - ($l - $adjust)))));
		$h = "Status: ";
		if ($username) {
			$h .= $LS{isLoggedin().'_login_status'};
		}
		else {
			$h .= "--";
		}

		if($appPath) {
			$l = length($h);
			$header    .= qq(\n$h);
			$header    .= (qq( ) x ($indent - ($l -$adjust)) . qq($LS{'logged_in_user'} ));
			$header    .= (($username ? $username: $LS{'no_logged_in_user'}) . qq(\n));
		} else {
			getAppPath();
			$header    .= qq(\n);
		}

		$header    .= (qq(-) x $l . qq( ) x ($indent - ($l -$adjust)) . qq(-) x ($w - ($l+ ($indent - ($l -$adjust)))));
		$header    .= qq(\n);
		$h = qq($LS{'storage_used'} );

		if ($storageUsed and $totalStorage){
			$h .= ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true')? qq($storageUsed) : qq($storageUsed of $totalStorage));
			#$h .= qq(1000.26 GB of 1000.00 GB);
			$l  = length($h);
			$header   .= qq($h);
		}
		else {
			$h .= "--";
			$l  = length($h);
			$header    .= qq($h);
		}

		if ($indent > ($l -$adjust)) {
			$header    .= (qq( ) x ($indent - ($l -$adjust))) ;
		}
		else {
			$header    .= qq( );
		}
		$header    .= qq($LS{'linux_user'} ).$AppConfig::mcUser;
		$header    .= qq(\n);

		if (isUpdateAvailable() && getUserConfiguration('NOTIFYSOFTWAREUPDATE')) {
			$header    .= qq(-) x $w;
			$header    .= qq(\n);
			$h = qq($LS{'new_update_is_available'});
			$header    .= qq($h\n);
		}

		$header    .= qq(=) x $w . qq(\n);
		my $hasstoppedserv = 0;
		if ($username and -e getServerAddressFile()) {
			my $warningCount = 0;
			my $warningHeader = '';

			if(!isCDPWatcherRunning() and hasFileNotifyPreReq() and getUserConfiguration('CDPSUPPORT')) {
				$warningHeader    .= qq(\n);
				$warningHeader .= qq(* $LS{'cdp_service_stopped'});
				$warningCount++;
				$hasstoppedserv = 1;
			}

			if($AppConfig::appType eq 'IDrive' && isDashboardRunning() == 0) {
				$warningHeader    .= qq(\n);
				$warningHeader .= qq(* $LS{'dashboard_service_stopped'});
				$warningCount++;
				$hasstoppedserv = 1;
			}

			unless(checkCRONServiceStatus() == CRON_RUNNING) {
				$warningHeader    .= qq(\n);
				$warningHeader .= qq(* $LS{'cron_service_stopped'});
				$warningCount++;
				$hasstoppedserv = 1;
			}

			# if(!hasSQLitePreReq() or !hasBasePreReq()) {
				# $warningHeader    .= qq(\n);
				# $warningHeader .= qq(* $LS{'basic_prereq_not_met_run_acc_settings'});
				# $warningCount++;
			# }
			
			my ($scanstat, $scfdbs) = isLastDBScanComplete();
			unless($scanstat) {
				my @bkpnames = ();
				for my $didx(0 .. $#{$scfdbs}) {
					push @bkpnames, getStringConstant((split(/\|/, $scfdbs->[$didx]))[0]);
				}

				$warningHeader    .= qq(\n);
				$warningHeader .= qq(* $LS{'last_backupset_scan_failed'}: ) . join(', ', @bkpnames) . '.';
				$warningCount++;
			}

			$warningHeader .= qq(\n* $LS{'run_acc_setttings_edit_detail_start_serv'}) if($hasstoppedserv);

			if ($warningCount > 0){
				$header    .= qq($LS{'warning_header'});
				$header    .= $warningHeader. qq(\n);
				$header    .= qq(-) x $w . qq(\n);
			}
		}
		display($header);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: displayMenu
# Objective				: Display menu items and ask user for the action.
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub displayMenu {
	if ($AppConfig::callerEnv eq 'BACKGROUND') {
		traceLog($AppConfig::callerEnv." is caller environment");
	}

	my $c = 1;
	my ($message, @options) = @_;
	my @lables = ();
	my $lable = '';
	my $indent = '';
	foreach (@options) {
		@lables = $_ =~ /^__[a-z0-9_]+__/g;
		if (scalar @lables > 0) {
			if ($lable ne $lables[0]) {
				#display('');
				display($lables[0]);
				$lable = $lables[0];
				$indent = "\t";
			}
			$_ =~ s/^__[a-z0-9_]+__//g;
		}
		my $content = $c;
		$content = " ".$content		if (($#options > 9) and ($c <= 9));
		display(["$indent", "$content\) ", $LS{$_}]);
		$c++;
	}
	display($message, 0);
}

#****************************************************************************************************
# Subroutine			: displayProgress
# Objective				: This subroutine will display the progress in the terminal window.
# Added By				: Senthil Pandian
#****************************************************************************************************
sub displayProgress{
	return if($AppConfig::callerEnv eq 'BACKGROUND');

	$SIG{WINCH} = \&changeSizeVal;

    my $curProgressStrLen = length($_[0]);
	if ($AppConfig::machineOS =~ /freebsd/i){
		my $noOfLineToClean = $_[1];
		system("tput rc");
		system("tput ed") if($curProgressStrLen < $AppConfig::prevProgressStrLen);
		for(my $i=1;$i<=$noOfLineToClean;$i++){
			print $AppConfig::freebsdProgress;
		}
	}
	system("tput rc");
    # system("tput ed");
    my $screenLen = (160/$AppConfig::progressSizeOp);
    $screenLen += 6 if($AppConfig::progressSizeOp == 1);    
	system("tput ed") if($curProgressStrLen < $AppConfig::prevProgressStrLen || ($curProgressStrLen > $AppConfig::prevProgressStrLen and $curProgressStrLen > $screenLen));
    print $_[0];
    $AppConfig::prevProgressStrLen = $curProgressStrLen;
}

#*****************************************************************************************************
# Subroutine			: displayScanProgress
# Objective				: Display file scanning progress
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#*****************************************************************************************************
sub displayScanProgress {
	return '' if(!$_[0] || !-f $_[0] || -z _);

	my $progfile = $_[0];

	if ($AppConfig::machineOS =~ /freebsd/i) {
		my $noOfLineToClean = $_[1];
		system("tput rc");
		system("tput ed");
		for(my $i = 1; $i <= $noOfLineToClean; $i++) {
			print $AppConfig::freebsdProgress;
		}
	}

	my $fc = [];
	$fc = getFileContents($progfile, 'array') if(-f $progfile);
	return '' if(!$fc or !$fc->[0] or !$fc->[1]);

    my $curProgressStrLen = length($fc->[0].$fc->[1]);
	system("tput rc");
    # system("tput ed");
	system("tput ed") if($curProgressStrLen < $AppConfig::prevProgressStrLen);
    $AppConfig::prevProgressStrLen = $curProgressStrLen;

    #utf8::encode($fc->[1]); #Added for Harish_2.3_10_18:Senthil & #Commented for Harish_2.3_13_5:Senthil
    # my $jobProgress = ($_[2])? '_scan_progress':'backup_scan_progress'
	display([($_[2] || 'backup').'_scan_progress', 'total_files_scanned', ' : ', $fc->[0], "\n", 'file_scanned', (' 'x8).': ', $fc->[1], "\n"]);
}

#*****************************************************************************************************
# Subroutine	: displayManualScanProgress
# In Param		: request|string, task type|string, pid file|string
# Out Param		: UNDEF
# Objective		: Displays manual scanning progress
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub displayManualScanProgress {
	my ($reqfile, $ttype, $pidfile) = ($_[0], $_[1], $_[2]);
	return 0 if($ttype ne "Manual" || (!isThisOnlineBackupScan() && !isThisBackupRescan()));

	my ($scantype, $dp) = ('', 1);
	my $scanprog	= getCDPLockFile('scanprog');
	my $scanlock	= getCDPLockFile('bkpscan');
	my $rescanlock	= getCDPLockFile('rescan');

	if(isFileLocked($scanlock)) {
		$scantype	= 'scan';
	} elsif(isFileLocked($rescanlock)) {
		$scantype	= 'rescan';
		$scanlock	= $rescanlock;
	}

	if($scantype) {
		getCursorPos(3, getStringConstant('scanning_files'));

		do {
			displayScanProgress($scanprog, 4) if(-f $scanprog);
			$dp = 0 if(!-f $pidfile || !-f $scanlock || (defined($reqfile) && !-f $reqfile));
			sleepForMilliSec(50);
		} while($dp);
	}
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
}

#*****************************************************************************************************
# Subroutine	: displayInstallationProgress
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Display installation progress
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub displayInstallationProgress {
	my $lockfh;
	exit(0) unless(-f $AppConfig::instproglock);
	exit(0) unless(open($lockfh, "<", $AppConfig::instproglock));
	exit(0) unless(flock($lockfh, LOCK_EX|LOCK_NB));

	# display(['installation_progress', ':']);
	# getCursorPos(3, getStringConstant('installation_progress') . ':');
	getCursorPos(3, '', 0);

	my $dp			= 1;
	my $progfile	= $AppConfig::instprog;
	my $pkopfile	= $AppConfig::repooppath;
	while(1) {
		my $fc	= -f $progfile? `tail -n1 $progfile` : '';
		$fc = '' if(!$fc);
		chomp($fc);

		if(!$fc) {
			exit(0) unless(-f $AppConfig::instproglock);
			sleep(1);
			next;
		}

		my $ifc = -f $pkopfile? `tail -n2 $pkopfile` : '';
		$ifc = '' if(!$ifc);
		chomp($ifc);

		if ($AppConfig::machineOS =~ /freebsd/i) {
			my $noOfLineToClean = $_[0];
			system("tput rc");
			system("tput ed");
			for(my $i = 1; $i <= $noOfLineToClean; $i++) {
				print $AppConfig::freebsdProgress;
			}
		}

		system("tput rc");
		system("tput ed");

		display(["\n", $fc, "\n", $ifc]);

		exit(0) unless(-f $AppConfig::instproglock);
		sleepForMilliSec(300);
	}
}

#*****************************************************************************************************
# Subroutine			: displayDBCDPInstallSteps
# Objective				: Display manual installation steps
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub displayDBCDPInstallSteps {
	my ($pkginstallseq, $cpaninstallseq) = ($_[0], $_[1]);

	display(["\n", 'please_execute_the_below_commands_in_seq', ':']);
	my $cmdidx = 1;
	for my $instidx (0 .. $#$pkginstallseq) {
		$$pkginstallseq[$instidx] =~ s/ -y| -qq| -q| --noconfirm| --non-interactive//g;
		# $$pkginstallseq[$instidx] =~ s/\Q 2>$AppConfig::repoerrpath 1>$AppConfig::repooppath\E//g;
		display(["\t", $cmdidx++, ') ', $$pkginstallseq[$instidx]]);
	}

	for my $instidx (0 .. $#$cpaninstallseq) {
		# $$cpaninstallseq[$instidx]		=~ s/\Q 2>$AppConfig::repoerrpath 1>$AppConfig::repooppath\E//g;
		$cpaninstallseq->[$instidx]		=~ s/__CPAN_AUTOINSTALL__ //g;
		${$cpaninstallseq}[$instidx]	=~ s/yes \| |no \| //g;

		display(["\t", $cmdidx++, ') ', $$cpaninstallseq[$instidx]]);
	}

	display(['']);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: download
# Objective				: Download files from the given url
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub download {
	my $url           = $_[0];
	my $downloadsPath = $_[1];

	unless (defined($url)) {
		display('url_cannot_be_empty');
		return 0;
	}

	unless (defined($downloadsPath)) {
		$downloadsPath = getCatfile($servicePath, $AppConfig::downloadsPath);
	}

	unless (-d $downloadsPath) {
		unless(createDir($downloadsPath)) {
			display(["$downloadsPath ", 'does_not_exists']);
			return 0;
		}
	}

	if (reftype(\$url) eq 'SCALAR') {
		$url = [$url];
	}

	my $proxy = '';
	if (getProxyStatus() and getProxyDetails('PROXYIP')) {
		$proxy = '-x http://';
		$proxy .= getProxyDetails('PROXYIP');

		if (getProxyDetails('PROXYPORT')) {
			$proxy .= (':' . getProxyDetails('PROXYPORT'))
		}
		if (getProxyDetails('PROXYUSERNAME')) {
			my $pu = getProxyDetails('PROXYUSERNAME');
			foreach ($pu) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			# $proxy .= (' --proxy-user ' . $pu); #Modified for Harish_2.32_21_3: Senthil
			$proxy .= (' --proxy-user ' . $pu.':');

			if (getProxyDetails('PROXYPASSWORD')) {
				my $ppwd = getProxyDetails('PROXYPASSWORD');
				$ppwd = ($ppwd ne '')?decryptString($ppwd):$ppwd;
				foreach ($ppwd) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				# $proxy .= (':' . $ppwd); #Modified for Harish_2.32_21_3: Senthil
				$proxy .= ($ppwd);
			}
		}
	}

	my $response;
	for my $i (0 .. $#{$url}) {
		my @parse = split('/', $url->[$i]);
		my $tmpCErrorFile = getCatfile($downloadsPath, $AppConfig::errorFile);
		my $tmpEErrorFile = getECatfile($tmpCErrorFile);
		fileWrite($tmpCErrorFile, '');
		my $cmd = "curl --tlsv1 --fail -k $proxy -L $url->[$i] -o ";
		$cmd   .= getECatfile($downloadsPath, $parse[-1]);
		$cmd   .= " 2>>$tmpEErrorFile";
		#print "cmd:$cmd#\n\n";
		$cmd = updateLocaleCmd($cmd);
		$response = `$cmd`;

		if (-f $tmpCErrorFile and -s $tmpCErrorFile){
			# if (!open(FH, "<", $tmpCErrorFile)) {
				# my $errStr = $Locale::strings{'failed_to_open_file'}.":$tmpCErrorFile, Reason:$!";
				# traceLog($errStr);
			# }
			# my $byteRead = read(FH, $response, $AppConfig::bufferLimit);
			$response = getFileContents($tmpCErrorFile);
			close FH;
			Chomp(\$response);
		}
		#print "response:$response#\n\n";
		unlink($tmpCErrorFile) if (-f $tmpCErrorFile);
		# if (($response =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Failed connect to .* Connection refused|Failed to connect to .* port [0-9]+: Network is unreachable|Connection timed out|response code said error|407 Proxy Authentication Required|No route to host|Could not resolve host/)) {
		if($response =~ /$AppConfig::proxyNetworkError/i || ($proxy ne '' and $response =~ /The requested URL returned error: 403/)) {
			# unless(detectENVProxyAndUpdate()) {
				retreat(["\n", 'kindly_verify_ur_proxy']) if (defined($_[2]));
				display(["\n", 'kindly_verify_ur_proxy']);
				askProxyDetails() or retreat('failed due to proxy');
			# }
			return download($url,$downloadsPath,"NoRetry") unless(defined($_[2] and $_[2] eq 'NoRetry'));

			# saveUserConfiguration() or retreat('failed to save user configuration');
		}
		elsif ($response =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch|404 Not Found|The requested URL returned error: 404|Unknown SSL protocol error/) {
			#retreat($response);
			display($response);
			return 0;
		} else {
			traceLog("CURL-ERROR: $response");
		}
		#Commented by Senthil for Senthil_2.17_54_1
		# if ($? > 0) {
			# traceLog($?);
			# return 0;
		# }
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: downloadEVSBinary
# Objective				: Download system compatible evs binary
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018], Sabin Cheruvattil
#****************************************************************************************************/
sub downloadEVSBinary {
	my $status = 0;
	loadMachineHardwareName();
	my $ezf    = $AppConfig::evsZipFiles{$AppConfig::appType}{$machineHardwareName};
	if ($AppConfig::machineOS =~ /freebsd/i) {
		$ezf = $AppConfig::evsZipFiles{$AppConfig::appType}{'freebsd'};
	}
	my $downloadPage = $AppConfig::evsDownloadsPage;
	my $domain       = lc($AppConfig::appType);

	$domain .= 'downloads' if ($AppConfig::appType eq 'IDrive');

	$downloadPage =~ s/__APPTYPE__/$domain/g;

	my ($dp, $binPath);
	for my $i (0 .. $#{$ezf}) {
		$ezf->[$i] =~ s/__APPTYPE__/$AppConfig::appType/g;
		$dp = ("$downloadPage/$ezf->[$i]");

		$binPath = getCatfile(getAppPath(), $AppConfig::idriveDepPath, $ezf->[$i]);
		$binPath =~ s/\.zip//g;

		if (-d $binPath) {
			if (hasEVSBinary($binPath)) {
				$status = 1;
				last;
			}
		}

		unless(download($dp)) {
			$status = 0;
			last;
		}

		$binPath = getCatfile(getServicePath(), $AppConfig::downloadsPath, $ezf->[$i]);
		if (!-f $binPath or !unzip($binPath)) {
			$status = 0;
			last;
		}

		$binPath =~ s/\.zip//g;
		if (hasEVSBinary($binPath)) {
			$status = 1;
			last;
		}
		last if ($status);
	}
	rmtree(getCatfile($servicePath, $AppConfig::downloadsPath));
	return $status;
}

#*****************************************************************************************************
# Subroutine			: downloadPythonBinary
# Objective				: Download system compatible python binary
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub downloadPythonBinary {
	loadMachineHardwareName();
	my $pyexe = ($AppConfig::machineOS =~ /freebsd/i) ?
								$AppConfig::pythonZipFiles{"freebsd"} :
								$AppConfig::pythonZipFiles{$machineHardwareName};
	unless ($pyexe) {
		return 0;
	}
	$pyexe =~ s/__KVER__/$AppConfig::kver/g;

	my $downlURL = $AppConfig::dependencyDownloadsPage;
	if ($AppConfig::appType eq "IDrive") {
		my $dom = (lc($AppConfig::appType) . "downloads");
		$downlURL =~ s/__APPTYPE__/$dom/g;
	}
	unless(download("$downlURL/$pyexe")) {
		return 0;
	}
	unless (unzip(getCatfile($servicePath, $AppConfig::downloadsPath, (fileparse($pyexe))[0]))) {
		return 0;
	}
	my $pybin = getCatfile($servicePath, $AppConfig::downloadsPath, (fileparse($pyexe))[0]);
	$pybin =~ s/\.zip//g;
	$pybin = getECatfile($pybin);
	rmtree(getCatfile(getAppPath(), $AppConfig::idrivePythonBinPath));
	my $cppytbin = updateLocaleCmd(("cp -rf $pybin " . getECatfile(getAppPath(), $AppConfig::idriveDepPath)));
	`$cppytbin`;
	my $privl = updateLocaleCmd(("chmod -R 0755 " . getECatfile(getAppPath(), $AppConfig::idriveDepPath)));
	`$privl`;

	rmtree(getCatfile($servicePath, $AppConfig::downloadsPath));
	return 1;
}

#*****************************************************************************************************
# Subroutine			: downloadStaticPerlBinary
# Objective				: Download system compatible static perl binary
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub downloadStaticPerlBinary {
	my $status = 0;
	loadMachineHardwareName();
	my $ezf    = [$AppConfig::staticperlZipFiles{$machineHardwareName}];
	if ($AppConfig::machineOS =~ /freebsd/i) {
		$ezf = [$AppConfig::staticperlZipFiles{'freebsd'}];
	}
	my $downloadPage = $AppConfig::dependencyDownloadsPage;
	my $domain       = lc($AppConfig::appType);

	$domain .= 'downloads' if ($AppConfig::appType eq 'IDrive');

	$downloadPage =~ s/__APPTYPE__/$domain/g;

	my ($dp, $binPath);
	for my $i (0 .. $#{$ezf}) {
		$ezf->[$i] =~ s/__APPTYPE__/$AppConfig::appType/g;
		$ezf->[$i] =~ s/__KVER__/$AppConfig::kver/g;
		$dp = ("$downloadPage/$ezf->[$i]");

		$binPath = getCatfile(getAppPath(), $AppConfig::idriveDepPath, $ezf->[$i]);
		$binPath =~ s/\.zip//g;

		if (-d $binPath) {
			if (hasStaticPerlBinary($binPath)) {
				$status = 1;
				last;
			}
		}

		unless(download($dp)) {
			$status = 0;
			last;
		}
		unless (unzip(getCatfile($servicePath, $AppConfig::downloadsPath, (fileparse($ezf->[$i]))[0]))) {
			$status = 0;
			last;
		}

		$binPath = getCatfile(getServicePath(), $AppConfig::downloadsPath, (fileparse($ezf->[$i]))[0]);
		$binPath =~ s/\.zip//g;

		if (hasStaticPerlBinary($binPath)) {
			$status = 1;
			last;
		}
	}
	rmtree(getCatfile($servicePath, $AppConfig::downloadsPath));
	return $status;
}

#*****************************************************************************************************
# Subroutine			: doBackupSetScanAndUpdateDB
# Objective				: Helps to generate the files for backupset
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#*****************************************************************************************************
sub doBackupSetScanAndUpdateDB {
	my $defaultret		= 0;

	return $defaultret if(!$_[0] || !-d $_[0]);

	my $bkpdir			= $_[0];
	my $bkptype			= $_[1]? $_[1] : '';
	my $iscdp			= $_[2];
	my $bkpsetfile		= getCatfile($bkpdir, $AppConfig::backupsetFile);
	my $oldbkpsetfile	= qq($bkpsetfile$AppConfig::backupextn);

	return $defaultret unless(-f $bkpsetfile);

	my $cdpscanlock = getCDPLockFile('bkpscan');
	return -1 if(isFileLocked($cdpscanlock));

	fileWrite($cdpscanlock, $bkptype . '--');
	fileLock($cdpscanlock);

	# if DB not present we have to rescan | delete old backup set file
	unlink($oldbkpsetfile) unless(-f getCatfile($bkpdir, $AppConfig::dbname));

	my $oldbkpitems		= (-f $oldbkpsetfile)? getDecBackupsetContents($oldbkpsetfile, 'array') : [];
	my $newbkpitems		= getDecBackupsetContents($bkpsetfile, 'array');
	my $st =  localtime();
	my ($dbfstate, $scanfile) = Sqlite::createLBDB($bkpdir, 0);

	Sqlite::createLBDB($bkpdir, 0) unless($dbfstate);
	Sqlite::initiateDBoperation();
	Sqlite::insertProcess($st, 0);

	if($bkptype eq 'localbackup') {
		loadUserConfiguration();
		Sqlite::addConfiguration('DATAHASH', getEncDatahash());
		Sqlite::addConfiguration('MPC', getMPC());
	}

	$defaultret = generateDBFromBackupset($oldbkpitems, $newbkpitems, $iscdp);
	createDBCleanupReq($bkpdir) unless($newbkpitems);

	my $et =  localtime();
	Sqlite::updateIbProcess($st, $et);
	Sqlite::createTableIndexes();
	Sqlite::closeDB();

	undef $oldbkpitems;
	undef $newbkpitems;
	
	unlink($cdpscanlock) if(-f $cdpscanlock);
	unlink($oldbkpsetfile) if(-f $oldbkpsetfile);

	# return $defaultret;
	return 1;
}

#*****************************************************************************************************
# Subroutine			: doBackupSetReScanAndUpdateDB
# Objective				: Rescans the backup set and updates the DB
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub doBackupSetReScanAndUpdateDB {
	my $defaultret		= 0;

	return $defaultret if(!$_[0]);

	my $cdprescanlock	= getCDPLockFile('rescan');
	return -1 if(isFileLocked($cdprescanlock));

	fileLock($cdprescanlock);

	my $bkpitems	= $_[0];
	my ($st, $et)	= (0, 0);
	my $upddbpaths	= getCDPDBPaths();
	my ($dbfstate, $scanfile);

	foreach my $jbname (keys(%{$bkpitems})) {
		$st	= localtime();

		($dbfstate, $scanfile) = Sqlite::createLBDB($upddbpaths->{$jbname}, 0);
		Sqlite::createLBDB($upddbpaths->{$jbname}, 0) unless($dbfstate);
		Sqlite::initiateDBoperation();
		Sqlite::insertProcess($st, 0);

		my @scanset = @{$bkpitems->{$jbname}};
		@scanset = map{utf8::decode($_); $_;} @scanset;
		$defaultret = rescanAndUpdateBackupsetDB(\@scanset);
		createDBCleanupReq($upddbpaths->{$jbname}) if(!scalar @{$bkpitems->{$jbname}});
		$et =  localtime();

		Sqlite::updateIbProcess($st, $et);
		Sqlite::createTableIndexes();
		Sqlite::closeDB();
	}

	unlink($cdprescanlock) if(-f $cdprescanlock);
	# return $defaultret;
	return 1;
}

#*****************************************************************************************************
# Subroutine			: deleteLog
# Objective				: Delete a log from the record
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub deleteLog {
	my $logFile = getJobsPath($_[0]);
	my @time 	= localtime($_[1]);
	my $logstat = getCatfile($logFile, sprintf("$AppConfig::logStatFile", ($time[4] + 1), ($time[5] += 1900)));

	my %logs;
	if (-f $logstat) {
		%logs = %{JSON::from_json(
			'{' .
			substr(getFileContents($logstat), 1) .
			'}'
		)};
	}

	if (exists $logs{$_[1]}) {
		delete $logs{$_[1]};

		my $logstatInStrings = JSON::to_json(\%logs);
		if ($logstatInStrings eq '{}') {
			$logstatInStrings = '';
		}
		elsif ($logstatInStrings ne '') {
			substr($logstatInStrings, 0, 1, ',');
			substr($logstatInStrings, -1, 1, '');
		}
		fileWrite($logstat, $logstatInStrings);

		$logFile = getCatfile(getJobsPath($_[0], lc($AppConfig::logDir)), "$_[1]_$_[2]");
		unlink($logFile);
		return 1;
	}

	return 0;
}

#****************************************************************************************************
# Subroutine Name         : displayProgressBar.
# Objective               : This subroutine contains the logic to display the filename and the progress
#                           bar in the terminal window.
# Added By                : Senthil Pandian
# Modified By             : Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub displayProgressBar {
	return if($AppConfig::callerEnv eq 'BACKGROUND');

	my ($progressDetails, $individualProgressDetails) = getProgressDetails($_[0],$_[2]);
	my @progressDetails = @$progressDetails;
	my %individualProgressDetails = %{$individualProgressDetails};

	my $isDedup = getUserConfiguration('DEDUP');
	return '' if (scalar(@progressDetails) == 0);

	$SIG{WINCH} = \&changeSizeVal;

	my ($progress, $cellSize, $totalSizeUnit, $moreProgress) = ('')x4;
	my ($remainingFile, $remainingTime) = ('NA') x 2;

	my $fullHeader   = $LS{lc($AppConfig::jobType . '_progress')};
	my $incrFileSize = $progressDetails[1];
	my $TotalSize    = $progressDetails[2];
	my $kbps         = $progressDetails[3];
	my $totalTransferredFiles = $progressDetails[6];

	my $percent = 0;
	$TotalSize = $_[1] if (defined $_[1] and $_[1] > 0);
	$TotalSize = 0 if ($TotalSize eq $LS{'calculating'} or $TotalSize =~ /calculating/i);

	if ($TotalSize != 0) {
		$percent = int($incrFileSize/$TotalSize*100);
		$percent = 100	if ($percent > 100);
		$progress = "|"x($percent/$AppConfig::progressSizeOp);
		my $cellCount = (100-$percent)/$AppConfig::progressSizeOp;
		$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
		$cellSize = " " x $cellCount;
		$totalSizeUnit = convertFileSize($TotalSize);
		my $jobRunningDir = (fileparse($_[0]))[1];
		my $totalFileCountFile	= $jobRunningDir.'/'.$AppConfig::totalFileCountFile;
		# traceLog("totalFileCountFile:$totalFileCountFile\n\n");
		if(-f $totalFileCountFile and !-z _) {
			my %countHash = %{JSON::from_json(getFileContents($totalFileCountFile))};
			my $totalFileCount = (exists($countHash{$AppConfig::totalFileKey}))?$countHash{$AppConfig::totalFileKey}:0;
			# traceLog("totalFileCount:$totalFileCount\n\n");
			# traceLog("totalTransferredFiles:$totalTransferredFiles\n\n");
			$remainingFile = ($totalFileCount - $totalTransferredFiles);
			# traceLog("remainingFile1:$remainingFile\n\n");
			$remainingFile = 0 if($remainingFile<0);
			# traceLog("remainingFile2:$remainingFile\n\n");
		}

		my $seconds = ($TotalSize - $incrFileSize);
		$seconds = ($seconds/$kbps) if($kbps);

		# As per NAS: Need to display maximum time as 150 days only. 150*24*60*60 = 12960000
		my $maxtime = 12960000;
		if($seconds > $maxtime) {
			$remainingTime = convertSecondsToReadableTime(ceil($maxtime));
		} else {
			$remainingTime = convertSecondsToReadableTime(ceil($seconds));
		}

		$remainingTime = '0s' if(!$remainingTime || $remainingTime =~ /-/);
	}
	else {
		#$totalSizeUnit = convertFileSize($TotalSize);
		$totalSizeUnit = $LS{'calculating'};
		$cellSize = " " x (100/$AppConfig::progressSizeOp);
		$remainingFile = 'NA';
		$remainingTime = 'NA';
	}

	my $fileSizeUnit = convertFileSize($incrFileSize);
	#$kbps =~ s/\s+//; Commented by Senthil : 26-Sep-2018
	$percent = sprintf "%4s", "$percent%";
	my $spAce = " " x 6;
	my $boundary = "-"x(100/$AppConfig::progressSizeOp);
	my $spAce1 = " "x(38/$AppConfig::progressSizeOp);

	return if ($progressDetails[0] eq '');

    #Added to display compact view when resized the expanded view screen
    if ($AppConfig::progressSizeOp == 2 and $_[3] eq 'more') {
        $_[3] = 'less';
    }

	if(scalar(keys %individualProgressDetails) and (defined($_[3]) and $_[3] eq 'more')) {
        my $space = (100/$AppConfig::progressSizeOp) + 7;
		for(my $i=1;$i<=$AppConfig::totalEngineBackup;$i++) {
			next unless($individualProgressDetails{$i});
			$moreProgress .= $LS{'engine'}." $i: ";
			$moreProgress .= $individualProgressDetails{$i}{'data'}."\n";
			my $per = $individualProgressDetails{$i}{'per'};
			$per =~ s/%//;
			chomp($per);

            my $rate = $individualProgressDetails{$i}{'rate'};
            $rate = convertFileSize($rate)."/s";
            $rate =~ s/bytes/B/;
            $rate = sprintf "%10s", $rate;

            my $size = $individualProgressDetails{$i}{'size'};
            $size =~ s/bytes/B/;
            $size = sprintf "%10s", $size;

            my $rateBar     = "[".$rate."][";
            my $fileSizeBar = "][".$size."]";

            my $progressBar = "";
            $per = 100 - ($AppConfig::progressSizeOp * 23) if($per>80);
			$progressBar    = "-"x($per/$AppConfig::progressSizeOp);
            $progressBar   .= $individualProgressDetails{$i}{'per'};
            my $engBarLen   = (length($progressBar) + length($rateBar) + length($fileSizeBar));
            $progressBar    = colorScreenOutput($progressBar, undef, 'green', 'black');
            $progressBar   .= " "x($space - $engBarLen) if($space > $engBarLen);
			$moreProgress  .= $rateBar.$progressBar.$fileSizeBar."\n\n";
		}
	}
    elsif($_[4] and $AppConfig::progressSizeOp == 2 and $AppConfig::machineOS ne 'freebsd'){
		# traceLog("lessPressed:".$_[4]);
		system(updateLocaleCmd("tput rc"));
		system(updateLocaleCmd("tput ed"));
		clearProgressScreen();
	}

	my $fileDetailRow = "\[$progressDetails[0]\] \[$progressDetails[4]\] \[$progressDetails[5]\]";
    if(defined($_[3]) and $_[3] eq 'more'){
        $fileDetailRow = "\n".$LS{'cumulative_progress'};
    }
	my $strLen     = length $fileDetailRow;
	my $emptySpaceDetail = " ";
	# $emptySpaceDetail = " "x($latestCulmn-$strLen) if ($latestCulmn>$strLen);
	$kbps = convertFileSize($kbps);
	my $sizeRowDetail = "$spAce1\[$fileSizeUnit of $totalSizeUnit] [$kbps/s]";
	$strLen  = length $sizeRowDetail;
	my $emptySizeRowDetail = " ";
	# $emptySizeRowDetail = " "x($latestCulmn-$strLen) if ($latestCulmn>$strLen);

	# my $progressReturnData = $moreProgress.$fullHeader;
    my $progressReturnData = $fullHeader.$moreProgress;
	$progressReturnData .=  "$fileDetailRow $emptySpaceDetail\n";
    $progressReturnData .=  "\n" if($_[3] ne 'more');
	$progressReturnData .= "$spAce$boundary\n";
	$progressReturnData .= "$percent [";
	$progressReturnData .= $progress.$cellSize;
	$progressReturnData .= "]\n";
	$progressReturnData .= "$spAce$boundary\n";
	$progressReturnData .= "$sizeRowDetail $emptySizeRowDetail\n";

	my $space = 70;
	$space    = 56 if($AppConfig::progressSizeOp>1);

	if ($AppConfig::jobType =~ /Backup/i or $AppConfig::jobType =~ /cdp/i) {
		my $backupHost	   = getUserConfiguration('BACKUPLOCATION');
		my $backupPathType = getUserConfiguration('BACKUPTYPE');
		my $bwThrottle     = getThrottleVal();
		my $status = "";
		my ($backupLocation,$backupType) = ('') x 2;
		# my $space = (100/$AppConfig::progressSizeOp);

		if ($isDedup eq 'on'){
			$backupLocation = ($backupHost =~ /#/)?(split('#',$backupHost))[1]:$backupHost;
			$backupLocation = $LS{'backup_location_progress'}." : ".$backupLocation;
		} else {
			if($AppConfig::jobType eq 'LocalBackup') {
				my @backupTo = split("/",$backupHost);
				$backupHost	 = (substr($backupHost,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
			}
			$backupLocation = $LS{'backup_location_progress'}." : ".$backupHost;
			# $backupType = $LS{'backup_type'}.(' ' x 10)." : ".ucfirst($backupPathType).$lineFeed;
		}
		$backupLocation .= "  " if(length($backupLocation) >= $space);
		$spAce1 = ($space > length($backupLocation)) ? (" "x($space - length($backupLocation))) : (" "x$space);

		my $bwThrottleStr = $LS{'c_bw_throttle'}." : ".$bwThrottle."%";
		$progressReturnData .= $lineFeed.$backupLocation.$spAce1.$bwThrottleStr.$lineFeed;

		my $fCount = getStringConstant('files_count');
		$fCount =~ s/<CC>/$totalTransferredFiles/;
		$fCount =~ s/<RC>/$remainingFile/;
		my $remainingTime   = $LS{'estimated_time_left'}.(' ' x 6)." : ".$remainingTime;
        my $displayMoreLess = $LS{'display'}.(' ' x 8)." : ".(($_[3] eq 'more')?$LS{'press_to_collapse'}:$LS{'press_to_extend'});
		if($isDedup eq 'on') {
			$spAce1 = " "x($space - length($remainingTime));			
			$progressReturnData .= $remainingTime.$spAce1.$fCount.$lineFeed;
			# $spAce1 = " "x($space);
            
			if(defined($_[2])) {
				$spAce1 = " "x($space - length($displayMoreLess));
				$status = $LS{'status'}.(' ' x 5)." : ".colorScreenOutput(getStringConstant($_[2]));
				my $keyPress = ($_[2] eq 'paused')?'press_r_to_run':'press_p_to_pause';
				$status .= " ".getStringConstant($keyPress);
			}
			$progressReturnData .= $displayMoreLess.$spAce1.$status.$lineFeed;
		} else {
			my $backupType = getStringConstant('backup_type') . (' ' x 4) . " : " . ucfirst($backupPathType);
			$spAce1 = " "x($space - length($backupType));
			$progressReturnData .= $backupType.$spAce1.$fCount.$lineFeed;

			if(defined($_[2])) {
				$spAce1 = " "x($space - length($remainingTime));
				$status = $LS{'status'}.(' ' x 5)." : ".colorScreenOutput(getStringConstant($_[2]));
				my $keyPress = ($_[2] eq 'paused')?'press_r_to_run':'press_p_to_pause';
				$status .= " ".getStringConstant($keyPress);
			}
			$progressReturnData .= $remainingTime.$spAce1.$status.$lineFeed;
            $progressReturnData .= $displayMoreLess.$lineFeed;
		}
	}
	else {
		my $restoreHost  = ($isDedup eq 'on')?getUserConfiguration('RESTOREFROM'):getUserConfiguration('LOCALRESTOREFROM');
		my $restoreLocation  = getUserConfiguration('RESTORELOCATION');
		my $restoreFromLocation = $restoreHost;
		if ($isDedup eq 'on') {
			$restoreFromLocation = (split('#',$restoreHost))[1] if ($restoreHost =~ /#/);
		}
		my $restoreFromLocationStr = $LS{'restore_from_location_progress'}." : ".$restoreFromLocation.(' ' x 2);
		my $restoreLocationStr     = $LS{'restore_location_progress'}." : ".$restoreLocation.(' ' x 2);
		$spAce1 = " "x($space - length($restoreFromLocationStr));
		$progressReturnData .= $lineFeed.$restoreFromLocationStr.$spAce1.$restoreLocationStr.$lineFeed;
		my $fCount = $LS{'files_count'};
		$fCount =~ s/<CC>/$totalTransferredFiles/;
		$fCount =~ s/<RC>/$remainingFile/;
		$fCount =~ s/:/     :/;
		my $remainingTimeStr = $LS{'estimated_time_left'}.(' ' x 12)." : ".$remainingTime;
        my $displayMoreLess = $LS{'display'}.(' ' x 14)." : ".(($_[3] eq 'more')?$LS{'press_to_collapse'}:$LS{'press_to_extend'});
		$spAce1 = " "x($space - length($remainingTimeStr));
		$progressReturnData .= $remainingTimeStr.$spAce1.$fCount.$lineFeed;
        $progressReturnData .= $displayMoreLess.$lineFeed;
	}
	$progressReturnData .= $lineFeed.getStringConstant('note_completed_remaining').$lineFeed;

    unless($AppConfig::allowExtentedView) {
        my $alert    = colorScreenOutput(getStringConstant('can_not_display_in_extended_view'), undef, 'white', 'red');
        $progressReturnData .= $lineFeed.$alert.$lineFeed;
        $AppConfig::allowExtentedView = 1;
        displayProgress($progressReturnData, 30);
        sleep(1);
    } else {  
        displayProgress($progressReturnData, 30);
    }
}

#****************************************************************************************************
# Subroutine Name         : displayArchiveProgressBar.
# Objective               : This subroutine contains the logic to display the scanned/deleted filename and the progress
#                           bar in the terminal window in Archive Cleanup & Status Retrieval Scripts.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub displayArchiveProgressBar {
	return if($AppConfig::callerEnv eq 'BACKGROUND');
	my $progressDetailsFilePath = $_[0];
	return '' unless (-f $progressDetailsFilePath);
	if (!open(PROGRESS, "< $progressDetailsFilePath")) {
		traceLog($LS{'failed_to_open_file'}.":$progressDetailsFilePath, Reason:$!");
		return '';
	}
	my @progressDetails = <PROGRESS>;
	close PROGRESS;
	chomp(@progressDetails);

	return if (scalar(@progressDetails) == 0 or !defined($progressDetails[0]) or $progressDetails[0] eq '');
	# return if ($progressDetails[0] eq '');

	$SIG{WINCH} = \&changeSizeVal;

	my ($progress, $cellSize, $totalSizeUnit) = ('', '', '');
	if(scalar(@progressDetails)<=3) {
		my $progressReturnData = defined($LS{$progressDetails[0]})?$LS{$progressDetails[0]}."\n":$progressDetails[0]."\n";
		$progressReturnData = '' if(defined($progressDetails[1])); #Added to overwrite
		if(defined($progressDetails[1])) {
			$progressReturnData .= defined($LS{$progressDetails[1]})?$LS{$progressDetails[1]}."\n":$progressDetails[1]."\n";
		}
		if(defined($progressDetails[2])) {
			$progressReturnData .= defined($LS{$progressDetails[2]})?$LS{$progressDetails[2]}."\n":$progressDetails[2]."\n";
		}
		displayProgress($progressReturnData, 3);
	} else {
		my $heading    = defined($LS{$progressDetails[0]})?$LS{$progressDetails[0]}:$progressDetails[0];
		my $fileName   = $progressDetails[1];
		my $strLen     = length $fileName;
		my $deletedFilesCount = $progressDetails[2];
		my $totalFilesCount   = $progressDetails[3];
		return '' unless($deletedFilesCount =~ /^\d+$/);
		my $percent = 0;
		if ($totalFilesCount != 0) {
			$percent = int($deletedFilesCount/$totalFilesCount*100);
			$percent = 100	if ($percent > 100);
			$progress = "|"x($percent/$AppConfig::progressSizeOp);
			my $cellCount = (100-$percent)/$AppConfig::progressSizeOp;
			$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
			$cellSize = " " x $cellCount;
		}
		
		$percent = sprintf "%4s", "$percent%";
		my $spAce = " "x6;
		my $boundary = "-"x(100/$AppConfig::progressSizeOp);
		my $spAce1 = " "x(38/$AppConfig::progressSizeOp);

		my $emptySpaceDetail = " ";
		$emptySpaceDetail = " "x($latestCulmn-$strLen) if ($latestCulmn>$strLen);

		my $sizeRowDetail = "$spAce1\[$LS{'deleted'} $deletedFilesCount of $totalFilesCount]";
		$strLen  = length $sizeRowDetail;
		my $emptySizeRowDetail = " ";
		$emptySizeRowDetail = " "x($latestCulmn-$strLen) if ($latestCulmn>$strLen);

		my $progressReturnData = "$heading $emptySpaceDetail\n";
		$progressReturnData .=  "[$fileName] $emptySpaceDetail\n";
		$progressReturnData .= "$spAce$boundary\n";
		$progressReturnData .= "$percent [";
		$progressReturnData .= $progress.$cellSize;
		$progressReturnData .= "]\n";
		$progressReturnData .= "$spAce$boundary\n";
		$progressReturnData .= "$sizeRowDetail $emptySizeRowDetail\n";
		displayProgress($progressReturnData, 10);
	}
}

#*****************************************************************************************************
# Subroutine			: doSilentLogout
# Objective				: This function will Logout current user's a/c silently
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub doSilentLogout {
	my $usrtxt = getFileContents(getCatfile(getServicePath(), $AppConfig::cachedIdriveFile));
	if ($usrtxt =~ m/^\{/) {
		traceLog('logout');
		$usrtxt = JSON::from_json($usrtxt);
		$usrtxt->{$AppConfig::mcUser}{'isLoggedin'} = 0;
		fileWrite(getCatfile(getServicePath(), $AppConfig::cachedIdriveFile), JSON::to_json($usrtxt));
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine	: doAccountResetLogout
# In Param		: commit status, is retry, $process file, failed commit dir, commit vault dir
# Out Param		: Status | Boolean
# Objective		: Places a request for express backup verification
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub doAccountResetLogout {
	if ((loadUserConfiguration() == 1) and (getUserConfiguration('BACKUPLOCATION') ne '')) {
		createBackupStatRenewalByJob('backup');
	
		if($_[0] || getUserConfiguration('DEDUP') eq 'on') {
			traceLog('Backup location is deleted.');
			setUserConfiguration('BACKUPLOCATION', '');
			saveUserConfiguration(0, 1);
		}
	}

	my $cmd = sprintf("%s %s 1 0", $AppConfig::perlBin, getScript('logout', 1));
	`$cmd`;
	traceLog('logout');
}

#****************************************************************************************************
# Subroutine			: displayMainMenu
# Objective				: This subroutine displays the date options menu
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub displayMainMenu {
	unless (defined($_[0]) and ref($_[0]) eq 'HASH') {
		retreat('invalid_parameter');
	}
	my %mainMenuOptions = %{$_[0]};
	my $title = defined($_[1])?$_[1]:'menu_options_title';
	display([$title, ':', "\n"]);
	display([map{$_ . ") ", getStringConstant($mainMenuOptions{$_}) . "\n"} sort {$a <=> $b} keys %mainMenuOptions], 0);
}

#*****************************************************************************************************
# Subroutine			: displayTitlewithUnderline
# Objective				: To display the title with underline
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub displayTitlewithUnderline {
	return if(!defined($_[0]) or $_[0] eq '');
	my $underline 	= qq(\n).qq(=) x length($_[0]) . qq(\n);
	display(["\n",$_[0],$underline],0);
}

#*****************************************************************************************************
# Subroutine			: deleteNS
# Objective				: delete ns value
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub deleteNS {
	if (exists $ns{'nsq'}{$_[0]}) {
		$ns{'nsd'}{$_[0]} = $ns{'nsq'}{$_[0]};
		delete $ns{'nsq'}{$_[0]};
		return 1;
	}
	return 0;
}

#********************************************************************************
# Subroutine		: deleteBackupDevice
# Objective			: To delete backup device location, reset backupset, scheduler & inactivate  user account.
# Added By			: Yogesh Kumar
# Modified By		: Sabin Cheruvattil, Senthil Pandian
#********************************************************************************
sub deleteBackupDevice {
	if ((loadUserConfiguration() == 1) and (getUserConfiguration('BACKUPLOCATION') ne '')) {
		my @files = (
			getJobsPath('backup', 'file'),
			(getJobsPath('backup', 'file') . ".json"),
			getJobsPath('localbackup', 'file'),
			(getJobsPath('localbackup', 'file') . ".json"),
		);

		foreach my $file (@files) {
			if (-f $file) {
				if (open(my $fh, '>', $file)) {
					print $fh '{}' if ($file =~ /\.json$/);
					close($fh);
				}
			}

			my $dbpath = getCatfile(dirname($file), $AppConfig::dbname);
			unlink($dbpath) if(-f $dbpath);
		}
	
		unless (defined($_[0])) {
			traceLog('Backup location is deleted.');
			setUserConfiguration('BACKUPLOCATION', '');
			saveUserConfiguration(0, 1);
		}

		createCrontab('backup', 'default_backupset', \%AppConfig::crontabSchema);
		createCrontab('cancel', 'default_backupset', \%AppConfig::crontabSchema);
		createCrontab('backup', 'local_backupset', \%AppConfig::crontabSchema);
		createCrontab('cancel', 'local_backupset', \%AppConfig::crontabSchema);
		createCrontab($AppConfig::cdp, 'default_backupset', \%AppConfig::crontabSchema);
		createCrontab('archive', 'default_backupset', \%AppConfig::crontabSchema);
		createCrontab('otherInfo', {'settings' => {'status' => 'INACTIVE', 'lastActivityTime' => time()}});

		unless (defined($_[0])) {
			stopDashboardService($AppConfig::mcUser, getAppPath());
	 	}
	}

	my $cmd = sprintf("%s %s 1 0", $AppConfig::perlBin, getScript('logout', 1));
	$cmd = updateLocaleCmd($cmd);
	`$cmd`;
	traceLog('logout');
}

#*************************************************************************************************
# Subroutine		: deleteDeprecatedScripts
# Objective			: delete deprecated scripts if present
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub deleteDeprecatedScripts {
	foreach my $depScript (keys %AppConfig::idriveScripts) {
		unlink(getAppPath() . qq(/$AppConfig::idriveScripts{$depScript})) if ($depScript =~ m/deprecated_/);
	}
}

#*****************************************************************************************************
# Subroutine/Function   : getArchiveAlertConfirmation
# In Param    : 
# Out Param   : 0/1
# Objective	  : This subroutine to display alert/confirmation message for non-dedup users
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub getArchiveAlertConfirmation {
    my $alert = getStringConstant('alert');
    $alert    = colorScreenOutput($alert, undef, 'white', 'red');
    display(["\n",$alert]);
    display('archive_alert_message');
    my $isContinue = getAndValidate('enter_your_choice','YN_choice',1,1,undef,1);
	if(lc($isContinue) eq 'n') {
       #exit(0);
       return 0;
    }
    return 1;
}

#------------------------------------------------- E -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: editRestoreLocation
# Objective				: Edit restore location for the current user
# Added By				: Anil Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub editRestoreLocation {
	my $restoreLocation = getUserConfiguration('RESTORELOCATION');
	display(['your_restore_location_is_set_to', " \"$restoreLocation\". ", 'do_you_want_edit_this_y_or_n_?'],1);
	my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		setRestoreLocation($_[0]);
		return 1;
	}
	else {
        my $tempRestoreLocation = $restoreLocation;
        utf8::decode($tempRestoreLocation); #Added for Suruchi_2.3_10_8: Senthil
		if (-d $tempRestoreLocation){
			unless (validateDir($tempRestoreLocation)){
                display(['cannot_open_directory', ": ", "\"$restoreLocation\" ", " Reason: ", 'permission_denied']);
                return 0;
            }
		}
        else{
			display(['invalid_restore_location', "\"$restoreLocation\". ", "Reason: ", 'no_such_directory']);
            return 0;
		}
		display(['your_restore_location_remains',"'$restoreLocation'."]);
		return 1;
	}
}

#*****************************************************************************************************
# Subroutine			: editRestoreFromLocation
# Objective				: Set Restore From location for the current user
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar[26/04/2018]
#****************************************************************************************************/
sub editRestoreFromLocation {
	my $rfl = getUserConfiguration('RESTOREFROM');
	$rfl = (split('#', $rfl))[-1] if (getUserConfiguration('DEDUP') eq 'on');
	display(["\n",'your_restore_from_device_is_set_to', " \"$rfl\". ", 'do_you_want_edit_this_y_or_n_?'],1);
	my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		if (getUserConfiguration('DEDUP') eq 'on') {
			display(["\n",'loading_your_account_details_please_wait',"\n"],1);
			my @devices = fetchAllDevices();
			findMyDevice(\@devices) or retreat('unable_to_find_your_backup_location');
			if ($devices[0]{'STATUS'} eq AppConfig::FAILURE) {
				if ($devices[0]{'MSG'} =~ 'No devices found') {
					retreat('your_account_not_configured_properly');
				}
				elsif($devices[0]{'MSG'} =~ /unauthorized user|user information not found/i) {
					updateAccountStatus(getUsername(), 'UA');
					saveServerAddress(fetchServerAddress());
				}
				retreat('operation_could_not_be_completed_please_try_again');
				return 0;
			}
			elsif ($devices[0]{'STATUS'} eq AppConfig::SUCCESS) {
				linkBucket('restore', \@devices) or retreat('please_try_again');
				return 1;
			}
		}
		elsif (getUserConfiguration('DEDUP') eq 'off') {
			display(['enter_your_restore_from_location_optional', ": "], 0);
				my $bucketName = getUserChoice();
				if ($bucketName ne ""){
					display(['Setting up your restore from location...'], 1);
					if (substr($bucketName, 0, 1) ne "/") {
						$bucketName = "/".$bucketName;
					}

					if (open(my $fh, '>', getValidateRestoreFromFile())) {
						print $fh $bucketName;
						close($fh);
						chmod 0777, getValidateRestoreFromFile();
					}
					else
					{
						traceLog("failed to create file. Reason: $!");
						return 0;
					}

					my $evsErrorFile      = getUserProfilePath().'/'.$AppConfig::evsErrorFile;
					createUTF8File('ITEMSTATUS',getValidateRestoreFromFile(),$evsErrorFile,'') or retreat('failed_to_create_utf8_file');
					my @result = runEVS('item');
					if (-s $evsErrorFile > 0) {
						my $err = getFileContents($evsErrorFile);
						if($err =~ /unauthorized user|user information not found/i) {
							updateAccountStatus(getUsername(), 'UA');
							saveServerAddress(fetchServerAddress());
						}

						unlink($evsErrorFile);
						retreat('operation_could_not_be_completed_please_try_again');
					}
					unlink($evsErrorFile);

					if ($result[0]{'status'} =~ /No such file or directory|directory exists in trash/) {
						display(['failed_to_set_restore_from_location'], 1);
						display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\". ")],1);
					}
					else
					{
						$rfl = $bucketName;
						display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\". ")],1);
					}

					$rfl = removeMultipleSlashs($rfl);
					$rfl = removeLastSlash($rfl);					
					setUserConfiguration('RESTOREFROM', $rfl);
					unlink(getValidateRestoreFromFile());
				}
				else
				{
					display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\" ")],1);
					display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\". ")],1);

					$rfl = removeMultipleSlashs($rfl);
					$rfl = removeLastSlash($rfl);					
					setUserConfiguration('RESTOREFROM', $rfl);
				}
				return 1;
		}
		else {
			retreat('Unable_to_find_account_type_dedup_or_no_dedup');
		}
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: enumerateDirAndUpdateDB
# Objective				: Helps to enumerate directories and update database
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#*****************************************************************************************************
sub enumerateDirAndUpdateDB {
	my $item		= $_[0];
	my $bkparr		= $_[1];
	my $fc			= $_[2]? $_[2] : undef;
	my $relog		= $_[3];
	my $iscdp		= $_[4];
	my ($ret, $totalFiles, $dirsize, $commitstat, $opstat) = (1, 0, 0, 1, 1);
	my $fileListHash;

	my $showhidden	= getUserConfiguration('SHOWHIDDEN');

	$item .= "/" if (substr($item, -1, 1) ne "/");
	my $dirid = Sqlite::dirExistsInDB($item, '/');
	# Check for directory removal
	# Do not take all the sub-directories under a directory. we need to process only a single level directories
	if($dirid) {
		my $subdirs = Sqlite::getSubDirsByID($dirid);

		for my $didx (0 .. $#{$subdirs}) {
			$opstat = Sqlite::deleteDirsAndFilesByDirName($subdirs->[$didx]) unless(-d $subdirs->[$didx]);
			$commitstat = 0 unless($opstat);
		}

		undef $subdirs;
	}

	my $dirh;
	unless(opendir($dirh, $item)) {
		traceLog("Could not open Dir $item, Reason:$!");
		return 0;
	}

	if($dirid) {
		$fileListHash  =  Sqlite::getFileListByDIRID($dirid);
	}
	else{
		$item =~ s!/*$!/!; 
		$dirid = Sqlite::insertDirectories($item, '/');
		$commitstat = 0 unless($dirid);
	}

	my ($temp, $file, $fileName, $sf) = ('', '', '', undef);
	while (readdir $dirh) {
		$file = $_;
		$temp = $item . $file;
		chomp($temp);

		next if ($file =~ /^\.\.?$/ or !-e $temp);

		$sf			= lstat($temp);
		my $mode	= $sf->mode;
		my $restype	= $mode & 61440;

		if($restype == 16384) {
			push @{$bkparr}, $temp;
		} elsif($restype == 32768) {
			next if($temp =~ m/.swp$/ || $temp =~ m/.swpx$/ || $temp =~ m/.swx$/);

			$fileName = "'$file'";

			$totalFiles++;
			$AppConfig::dbFileIndex++;
			$dirsize = $dirsize + $sf->size;

			if(defined($fc)) {
				$fc->[0]++;
				$fc->[1] = $temp;
			}

			unless(exists $fileListHash->{$fileName}) {
				my $status = $AppConfig::dbfilestats{'NEW'};
				if(isThisExcludedItemSet($temp . '/', $showhidden)) {
					$status = $AppConfig::dbfilestats{'EXCLUDED'};
				} elsif($iscdp && $sf->size <= $AppConfig::cdpmaxsize) {
					$status	= $AppConfig::dbfilestats{'CDP'};
				}

				$opstat = Sqlite::insertIbFile(1, $dirid, $fileName, $sf->mtime, $sf->size, $status);
				$commitstat = 0 unless($opstat);
				rescanLog("Add: $temp") if($relog);

				$fileListHash->{$fileName}{'FILE_LMD'}	= $sf->mtime;
				$fileListHash->{$fileName}{'FILE_SIZE'}	= $sf->size;
				$fileListHash->{$fileName}{'exist'}		= 1;
			} else {
				if(($fileListHash->{$fileName}{'FILE_LMD'} ne $sf->mtime or $fileListHash->{$fileName}{'FILE_SIZE'} ne $sf->size)) {
					rescanLog("Update: $temp") if($relog);

					my $status = $AppConfig::dbfilestats{'MODIFIED'};
					if(isThisExcludedItemSet($temp . '/', $showhidden)) {
						$status = $AppConfig::dbfilestats{'EXCLUDED'};
					} elsif(($iscdp || $fileListHash->{$fileName}{'BACKUP_STATUS'} == $AppConfig::dbfilestats{'CDP'}) && $sf->size <= $AppConfig::cdpmaxsize) {
						$status	= $AppConfig::dbfilestats{'CDP'};
					}

					$opstat = Sqlite::updateIbFile(1, $dirid, $fileName, $sf->mtime, $sf->size, $status);
					$commitstat = 0 unless($opstat);
				}

				$fileListHash->{$fileName}{'exist'}	= 1;
			}

			if($AppConfig::dbFileIndex > 49999) {
				$AppConfig::dbFileIndex = 0;
				Sqlite::reBeginDBProcess($item);
			}
		}
	}

	closedir($dirh);

	Sqlite::updateIbFolderCount($totalFiles, $dirsize, $dirid);

	my $key = '';
	foreach $key (keys %{$fileListHash}) {
		unless($fileListHash->{$key}{'exist'}) {
			$opstat = Sqlite::deleteIbFile($key, $dirid);
			$commitstat = 0 unless($opstat);
			rescanLog("Delete: " . getCatfile($item, $key)) if($relog);
		}

		delete $fileListHash->{$key};
	}

	undef %{$fileListHash};

	return $commitstat;
}

#*****************************************************************************************************
# Subroutine			: encryptPWD
# Objective				: Encrypt user passwd
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub encryptPWD {
	my $epf = getIDENPWDFile();
	my $len = length($username);
	my $ep = pack("u", $_[0]);
	chomp($ep);
	$ep = ($len . "_" . $ep);
	if (open(my $fh, '>', $epf)) {
		print $fh $ep;
		close($fh);
		changeMode(getIDENPWDFile());
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: encodePVT
# Objective				: This subroutine is used to create IDPVT and IDPVTSCH files
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub encodePVT {
	my $encKey = $_[0];
	createUTF8File('STRINGENCODE', $encKey, getIDPVTFile()) or retreat('failed_to_create_utf8_file');
	my @result = runEVS();
	unless (($result[0]->{'STATUS'} eq AppConfig::SUCCESS) and ($result[0]->{'MSG'} eq 'no_stdout')) {
		retreat('failed_to_encode_private_key');
	}
	if (loadNotifications() and lockCriticalUpdate("notification") and (getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'pvt_verification_failed'})) {
		setNotification('alert_status_update', 0) and saveNotifications();
	}

	unlockCriticalUpdate("notification");

	copy(getIDPVTFile(), getIDPVTSCHFile());
	changeMode(getIDPVTFile());
	changeMode(getIDPVTSCHFile());
}

#*****************************************************************************************************
# Subroutine			: encryptString
# Objective				: Encrypt the given data
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub encryptString {
	return '' unless $_[0];

	my $plainString  = $_[0];

	$plainString = encode_base64($plainString);
	chomp($plainString);
	my $stringLength	= length $plainString;
	my $swapLength		= $stringLength - ($stringLength % 4);
	my $shiftLength		= $swapLength/4;

	my $swpa			= substr($plainString, 0, $shiftLength);
	my $swpb			= substr($plainString, (3 * $shiftLength), $shiftLength);

	substr($plainString, (3 * $shiftLength), $shiftLength) = $swpa;
	substr($plainString, 0, $shiftLength) = $swpb;

	return $plainString;
}

#*****************************************************************************************************
# Subroutine	: extractProxyString
# In Param		: Proxy | String
# Out Param		: Hash
# Objective		: Extracts proxy information from the provided proxy string
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub extractProxyString {
	my $proxstr = $_[0];
	my %proxdata = %{$AppConfig::proxyTemplate};
	return \%proxdata if(!$proxstr);

	my @marr = ($proxstr =~ /(.*):(.*)@(.*):(.*)|(.*)@(.*):(.*)|(.*):(.*)/);
	my ($uname, $pwd, $ip, $port) = ('', '', '', 0);

	if ($marr[0]) {
		($uname, $pwd, $ip, $port) = ($marr[0], $marr[1], $marr[2], $marr[3]);
	}
	elsif ($marr[4]) {
		($uname, $ip, $port) = ($marr[4], $marr[5], $marr[6]);
	}
	elsif($marr[7]) {
		($ip, $port) = ($marr[7], $marr[8]);
	}

	$proxdata{'PROXY'} = $proxstr;
	$proxdata{'PROXYIP'} = $ip;
	$proxdata{'PROXYPORT'} = $port;

	if ($uname) {
		$proxdata{'PROXYUSERNAME'} = $uname;

		if ($pwd) {
			$pwd = $pwd;
			$proxdata{'PROXYPASSWORD'} = $pwd;
		}
	}

	return \%proxdata;
}

#*****************************************************************************************************
# Subroutine/Function   : encodeServerAddress
# In Param    : serverAddress
# Out Param   : encodedString
# Objective	  : This subroutine to encode server address using EVS & return string.
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub encodeServerAddress {
	my $tmpFile    = getCatfile(getServicePath(), $AppConfig::tmpPath.time);
	my $encodedStr = '';
	createUTF8File('STRINGENCODE', $_[0], $tmpFile) or (retreat('failed_to_create_utf8_file'));
	my @responseData = runEVS('Encoded');

	if ($responseData[0]->{'STATUS'} eq AppConfig::FAILURE) {
		retreat(ucfirst($responseData[0]->{'MSG'}));
	}

	if(-f $tmpFile) {
		$encodedStr = getFileContents($tmpFile);
		Chomp(\$encodedStr);
		removeItems($tmpFile);
	}

	return $encodedStr;
}

#------------------------------------------------- F -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: fetchAllDevices
# Objective				: Fetch all devices for the current in user.
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub fetchAllDevices {
	createUTF8File('LISTDEVICE', $_[0]) or
		retreat('failed_to_create_utf8_file');
	my @responseData = runEVS('item');
	return @responseData;
}

#*****************************************************************************************************
# Subroutine			: findDependencies
# Objective				: Find whether package dependencies are met
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub findDependencies {
	my $display = (!defined($_[0]) || $_[0] == 1)? 1 : 0;

	display('checking_for_dependencies') if ($display);
	my $status = 0;
	for my $binary (@AppConfig::dependencyBinaries) {
		display("dependency_$binary...", 0) if ($display);
		my $findbinaryCmd = updateLocaleCmd("which $binary 2>/dev/null");
		my $r = `$findbinaryCmd`;
		if ($? == 0) {
			display(['found']) if ($display);
			$status = 1;
		}
		else {
			display(['not_found',"\n", "Please install ", $binary, " and try again."]) if ($display);
			$status = 0;
			last;
		}
	}
	return $status;
}

#*****************************************************************************************************
# Subroutine			: fixPathDeprecations
# Objective				: This will fix user path deprecations
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub fixPathDeprecations {
	my ($deppath, $fixpath) = ('', '');
	loadCrontab();
	my $crontab = getCrontab();

	foreach my $jk (keys(%AppConfig::deprecatedProfilePath)) {
		foreach my $muser (keys %{$crontab}) {
			foreach my $iduser (keys %{$crontab->{$muser}}) {
				$deppath	= getCatfile(getServicePath(), $AppConfig::userProfilePath, $muser, $iduser, $AppConfig::deprecatedProfilePath{$jk});
				$fixpath	= getCatfile(getServicePath(), $AppConfig::userProfilePath, $muser, $iduser, $AppConfig::userProfilePaths{$jk});

				if(-d $deppath and -w $deppath and !-d $fixpath) {
					createDir(dirname($fixpath), 1) unless(-d dirname($fixpath));
					system('mv ' . getECatfile($deppath, '') . ' ' . getECatfile($fixpath, '') . ' 2>/dev/null');
				}
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: fixBackupsetDeprecations
# In Param				: UNDEF
# Out Param				: UNDEF
# Objective				: Checks and fixes backup set deprecations
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#*****************************************************************************************************
sub fixBackupsetDeprecations {
	loadCrontab();
	my @jbtypes = ('backup', 'localbackup');
	my $crontab = getCrontab();

	# If older backup set is existing, we have to replace it with encrypted one
	foreach my $muser (keys %{$crontab}) {
		foreach my $iduser (keys %{$crontab->{$muser}}) {
			foreach my $jbt (@jbtypes) {
				my $obsf	= getCatfile(getServicePath(), $AppConfig::userProfilePath, $muser, $iduser, $AppConfig::userProfilePaths{$jbt}, $AppConfig::oldBackupsetFile);
				my $nbsf	= getCatfile(getServicePath(), $AppConfig::userProfilePath, $muser, $iduser, $AppConfig::userProfilePaths{$jbt}, $AppConfig::backupsetFile);

				if(-w dirname($nbsf)) {
					unlink("$obsf.info") if (-f "$obsf.info");

					my $obsjson = $obsf . '.json';
					if(-f $obsjson) {
						if(!-f "$nbsf.json") {
							rename $obsjson, "$nbsf.json";
						} else {
							unlink($obsjson);
						}
					}

					# Delete unencrypted backup set, create encrypted backup set if required
					if(-f $obsf) {
						if(-f $nbsf) {
							unlink($obsf);
							next;
						}

						if(!-z $obsf) {
							saveEncryptedBackupset($nbsf, getFileContents($obsf));
						} else {
							fileWrite($nbsf, '');
						}

						unlink($obsf);
					}
				}
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: fixDashbdDeprecPath
# In Param				: UNDEF
# Out Param				: UNDEF
# Objective				: Fixes dashboard path deprecations
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub fixDashbdDeprecPath {
	return 1 if($AppConfig::appType ne 'IDrive');

	lockCriticalUpdate("cron");
	loadCrontab();
	my $crontab = getCrontab();
	foreach my $muser (keys %{$crontab}) {
		foreach my $iduser (keys %{$crontab->{$muser}}) {
			# Check deprecated path
			my $dshpath = $crontab->{$muser}{$iduser}{$AppConfig::dashbtask}{$AppConfig::dashbtask}{'cmd'};
			my $depdshpath = getCatfile(getAppPath(), $AppConfig::idriveScripts{'dashboard'});
			if ((!$dshpath or $dshpath eq $depdshpath) and -d getCatfile(getServicePath(), $AppConfig::userProfilePath, $muser, $iduser)) {
				$crontab->{$muser}{$iduser}{$AppConfig::dashbtask}{$AppConfig::dashbtask}{'cmd'} = getDashboardScript();
			}
		}
	}

	saveCrontab(0);
	unlockCriticalUpdate("cron");
}

#*****************************************************************************************************
# Subroutine			: fetchServerAddress
# Objective				: Fetch current user's evs server ip
# Added By				: Yogesh Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub fetchServerAddress {
	my @responseData;
	my $res = makeRequest(12);
	if(defined($res->{DATA})) {
		my %evsServerHashOutput = parseXMLOutput(\$res->{DATA});
		$responseData[0] = \%evsServerHashOutput;
		updateAccountStatus(getUsername(), 'Y');
	}

	return @responseData;
}

#*************************************************************************************************
# Subroutine		: fetchInstalledEVSBinaryVersion
# Objective			: Get the installed EVS binaries version
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub fetchInstalledEVSBinaryVersion {
	my $needToDownload = 1;
	if ((hasEVSBinary())) {
		my @evsBinaries = (
			$AppConfig::evsBinaryName
		);
		push(@evsBinaries, $AppConfig::evsDedupBinaryName) if ($AppConfig::appType eq 'IDrive');

		my $servicePath = getServicePath();
		my %evs;
		#use Data::Dumper;
		for (@evsBinaries) {
			my $evs = $servicePath."/".$_;
			my $cmd = "'$evs' --client-version";
			$cmd = updateLocaleCmd($cmd);
			my $nonDedupVersion = `$cmd 2>/dev/null`;
			#print "nonDedupVersion:$nonDedupVersion\n\n\n";
			$nonDedupVersion =~ m/idevsutil version(.*)release date(.*)/;

			$evs{$_}{'version'} = $1;
			$evs{$_}{'release_date'} = $2;
			$evs{$_}{'release_date'} =~ s/\(DEDUP\)//;

			Chomp(\$evs{$_}{'version'});
			Chomp(\$evs{$_}{'release_date'});

			if ($evs{$_}{'version'} ne $AppConfig::evsVersionSchema{$AppConfig::appType}{$_}{'version'} or $evs{$_}{'release_date'} ne $AppConfig::evsVersionSchema{$AppConfig::appType}{$_}{'release_date'}) {
				$needToDownload = 1;
				last;
			}
			$needToDownload = 0;
		}
	}
	#print "needToDownload:$needToDownload\n\n";
	return $needToDownload;
}

#*************************************************************************************************
# Subroutine		: fetchInstalledPerlBinaryVersion
# Objective			: Get the installed Perl binary version
# Added By			: Senthil Pandian
# Modified By		: Yogesh Kumar
#*************************************************************************************************/
sub fetchInstalledPerlBinaryVersion {
	my $needToDownload = 1;
	if (hasStaticPerlBinary()) {
		my $sp = getIDrivePerlBin();
		my $cmd = ("$sp " . getDashboardScript(1). " --version");
		my $version = `$cmd 2>/dev/null`;
		Chomp(\$version);
		if ($version eq $AppConfig::staticPerlVersion) {
			$needToDownload = 0;
		}
	}
	return $needToDownload;
}

#*****************************************************************************************************
# Subroutine			: formatEmailAddresses
# Objective				: This subroutine alters the email address in the required format.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub formatEmailAddresses {
	my ($inputEmails, $invalidEmails, $validEmails) 	= (shift, '', '');
	my @emails 	= ($inputEmails =~ /\,|\;/)? split(/\,|\;/, $inputEmails) : ($inputEmails);
	# my @newarray = grep(s/^\s+|\s+$//g, @emails);
	map { s/^\s+|\s+$//g; } @emails;
	my %hash   = map { $_ => 1 } @emails;
	my @newarray = keys %hash;
	foreach my $email (@newarray) {
		$email 	=~ s/^[\s\t]+|[\s\t]+$//g;
		if ($email ne '') {
			$validEmails .= qq($email, );
		}
	}
	$inputEmails = substr($validEmails, 0, -1);
	if (substr($inputEmails, -1) eq ",") {
		$inputEmails = substr($inputEmails, 0, -1);
	}
	return $inputEmails;
}

#*****************************************************************************************************
# Subroutine		: fileWrite
# Objective			: Write/create a file with given data
# Added By			: Yogesh Kumar
# Modified By       : Senthil Pandian
#****************************************************************************************************/
sub fileWrite {
	my $mode = '>';
	$mode .= '>' if (defined($_[2] and $_[2] eq 'APPEND'));
    unless(defined($_[0])){
        display('1_file_lock_status');
        return 0;
    }

	if (open(my $fh, $mode, $_[0])) {
		print $fh $_[1];
		close($fh);
		return 1;
	}
	else {
		display(['failed_to_open_file', " $_[0]. $!"]);
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine	: fileWrite2
# Objective		: Write/create a file with given data and lock while modifying content
# Added By		: Yogesh Kumar
#****************************************************************************************************/
sub fileWrite2 {
	my $mode = '>';
	$mode .= '>' if (defined($_[2] and $_[2] eq 'APPEND'));
	if (open(my $fh, $mode, $_[0])) {
		unless (flock($fh, LOCK_EX)) {
			traceLog("Cannot lock file $_[0] $!");
			close($fh);
			return 0;
		}
		seek $fh, 0, 0;
		truncate $fh, 0;
		print $fh $_[1];
		close($fh);
		return 1;
	}

	display(['failed_to_open_file', " $_[0]. $!"]);
	return 0;
}

#*****************************************************************************************************
# Subroutine		: findMyDevice
# Objective			: Find the bucket which was linked with this machine
# Added By			: Yogesh Kumar
# Modified By		: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub findMyDevice {
	#Added to handle dual OS
	if((!getUserConfiguration('BACKUPLOCATION') and !defined($_[2])) or (getUserConfiguration('BACKUPLOCATION') and defined($_[2]))) {
		return 0;
	}
	my $devices = $_[0];
	my $displayStatus = defined($_[1]);
	my $muid = getMachineUID() or retreat('unable_to_find_mac_address');
	my $muname = getMachineUser();
=beg
	my @devices2 = ();
	my @devicesNotInTrash = ();
	my @devicesInTrash = ();
	foreach (@{$devices}) {
		if (defined($_->{'in_trash'}) and $_->{'in_trash'} eq '1') {
			push(@devicesInTrash, $_);
		}
		else {
			push(@devicesNotInTrash, $_);
		}
	}
	push(@devices2, @devicesNotInTrash);
	push(@devices2, @devicesInTrash);
=cut

	foreach (@{$devices}) {
		next if (!defined($_->{'uid'}) or ($muid ne $_->{'uid'} and $muid.$AppConfig::deviceUIDsuffix ne $_->{'uid'}));

		if ($_->{'in_trash'} eq '1') {
			my $deviceID = getBackupDeviceID();
			if ($deviceID) {
				$deviceID =~ s/$AppConfig::deviceIDPrefix//;
				$deviceID =~ s/$AppConfig::deviceIDSuffix//;
				if ($deviceID eq $_->{'device_id'}) {
					deleteBackupDevice();
					return 0;
				}
			}
			next;
		}

		if ('NA' eq $_->{'loc'}) {
			retreat('update_device_name_failed_try_again_later') unless (linkBucket('backup', [$_], undef, 1, 1));
			$_->{'loc'} = $muname;
			$_->{'server_root'} = getUserConfiguration('SERVERROOT');
			$_->{'device_id'} = getUserConfiguration('BACKUPLOCATION');
			$_->{'device_id'} = (split('#', $_->{'device_id'}))[0];
			$_->{'device_id'} =~ s/$AppConfig::deviceIDPrefix//;
			$_->{'device_id'} =~ s/$AppConfig::deviceIDSuffix//;
		}

		if ($displayStatus) {
			unless($AppConfig::isautoinstall) {
				# display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\". "),'do_you_want_edit_this_y_or_n_?'], 1);
				display(['your_backup_location_name_is',(" \"" . $_->{'nick_name'} . "\". "),'do_you_want_edit_bkploc_name_y_or_n_?'], 1);

				my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
				if (lc($answer) eq 'y') {
					my $deviceName = getAndValidate(["\n", 'enter_your_backup_location_name_optional', ": "], "backup_location", 1);
					if ($deviceName eq '') {
						$deviceName = $AppConfig::hostname;
						$deviceName =~ s/[^a-zA-Z0-9_-]//g;
					}
					# display('setting_up_your_backup_location',1);
					display('modifying_backup_location_name',1);
					if ($deviceName and ($deviceName ne $_->{'nick_name'})) {
						my $restoreFrom = getUserConfiguration('RESTOREFROM');
						my $bkpLoc      = getUserConfiguration('BACKUPLOCATION');
						my $isSameDeviceID = 1;
						if ($restoreFrom and $restoreFrom eq $bkpLoc){
							$isSameDeviceID = 1;
						}
						retreat('update_device_name_failed_try_again_later') unless (renameDevice($_, $deviceName));
						$_->{'nick_name'} = $deviceName; # Added for Snigdha_2.17_74_4
						setUserConfiguration('RESTOREFROM',($AppConfig::deviceIDPrefix .
							$_->{'device_id'} .$AppConfig::deviceIDSuffix ."#" . $_->{'nick_name'})) if ($isSameDeviceID);
					}
					$displayStatus = 0;
				}
			}

			# display(['your_backup_location_name_is',(" \"" . $_->{'nick_name'} . "\".")]);
			display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\".")]);
		} else {
			#Added for Snigdha_2.32_20_1: Senthil
			#Updating name when bucket name renamed by another user or from other script path
			my $restoreFrom = getUserConfiguration('RESTOREFROM');
			my $bkpLoc      = getUserConfiguration('BACKUPLOCATION');
			my $newBkpLoc   = ($AppConfig::deviceIDPrefix .
				$_->{'device_id'} .$AppConfig::deviceIDSuffix ."#" . $_->{'nick_name'});
			if ($bkpLoc ne $newBkpLoc and $restoreFrom and $restoreFrom eq $bkpLoc){
				setUserConfiguration('RESTOREFROM',$newBkpLoc);
			}
		}

		setUserConfiguration('SERVERROOT', $_->{'server_root'});
		setUserConfiguration('BACKUPLOCATION',($AppConfig::deviceIDPrefix .
			$_->{'device_id'} .$AppConfig::deviceIDSuffix ."#" . $_->{'nick_name'}));
		
		if(loadNotifications() and lockCriticalUpdate("notification")) {
			setNotification('register_dashboard') and saveNotifications();
			unlockCriticalUpdate("notification");
		}

		setUserConfiguration('MUID', $muid);
		return 1;
	}

	foreach (@{$devices}) {
		next unless(defined($_->{'uid'}));
		$_->{'uid'} =~ s/_1$//g;
		next	if ($muid ne $_->{'uid'});

		if ($muname ne $_->{'loc'}) {
			next;
		}

		if ($_->{'in_trash'} eq '1') {
			my $deviceID = getBackupDeviceID();
			if ($deviceID) {
				$deviceID =~ s/$AppConfig::deviceIDPrefix//;
				$deviceID =~ s/$AppConfig::deviceIDSuffix//;
				if ($deviceID eq $_->{'device_id'}) {
					deleteBackupDevice();
					return 0;
				}
			}
			next;
		}

		createUTF8File('LINKBUCKET',
		$AppConfig::evsAPIPatterns{'LINKBUCKET'},
		$_->{'nick_name'},
		$_->{'device_id'},
		$muid) or retreat('failed_to_create_utf8_file');
		my @result = runEVS('item');

		if ($result[0]->{'STATUS'} eq AppConfig::FAILURE) {
			print "$result[0]->{'MSG'}\n";
			return 0;
		}
		elsif ($result[0]->{'STATUS'} eq AppConfig::SUCCESS) {
			display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\".")]);

			setUserConfiguration('BACKUPLOCATION',
			($AppConfig::deviceIDPrefix . $_->{'device_id'} . $AppConfig::deviceIDSuffix .
			"#" . $_->{'nick_name'}));
			if(loadNotifications() and lockCriticalUpdate("notification")) {
				setNotification('register_dashboard') and saveNotifications();
				unlockCriticalUpdate("notification");
			}
		}

		setUserConfiguration('MUID', $muid);
		setUserConfiguration('SERVERROOT', $_->{'server_root'});
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine	: findMyBuckets
# In Param		: devicelist(arr)
# Out Param		: matchedBuckets(hash)
# Objective		: Find the bucket list which was linked with this machine
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub findMyBuckets {
	my @devices  = @{$_[0]};
	my $deviceID = '';
	if (Common::getUserConfiguration('BACKUPLOCATION')) {
		$deviceID = Common::getBackupDeviceID();
		$deviceID =~ s/$AppConfig::deviceIDPrefix//;
		$deviceID =~ s/$AppConfig::deviceIDSuffix//;
	}
	my $muid = Common::parseMachineUID() or Common::retreat('unable_to_find_mac_address');
	my $bucketExist    = 0;
	my %matchedBuckets = ();
	my ($serverRoot, $nickName);

	foreach (@devices) {
		next if (!defined($_->{'device_id'}) or ($deviceID ne $_->{'device_id'}));

		if ($_->{'in_trash'} eq '1') {
			if ($deviceID) {
				$deviceID =~ s/$AppConfig::deviceIDPrefix//;
				$deviceID =~ s/$AppConfig::deviceIDSuffix//;
				if ($deviceID eq $_->{'device_id'}) {
					Common::deleteBackupDevice();
					return %matchedBuckets;
				}
			}
			next;
		}
		$matchedBuckets{$_->{'device_id'}}{'nick_name'} = $_->{'nick_name'};
		$matchedBuckets{$_->{'device_id'}}{'server_root'} = $_->{'server_root'};
		$matchedBuckets{$_->{'device_id'}}{'uid'} = $_->{'uid'};
	}

	unless(scalar(keys %matchedBuckets)) {
		foreach (@devices) {
			my $uid = $_->{'uid'};
			next if (!defined($_->{'uid'}) or ($uid !~ /$muid/));

			$matchedBuckets{$_->{'device_id'}}{'nick_name'} = $_->{'nick_name'};
			$matchedBuckets{$_->{'device_id'}}{'server_root'} = $_->{'server_root'};
			$matchedBuckets{$_->{'device_id'}}{'uid'} = $_->{'uid'};
		}
	}
	return %matchedBuckets;
}

#*****************************************************************************************************
# Subroutine		: fileLock
# Objective			: Create and/or lock the given file
# Added By			: Yogesh Kumar
# Modified By		: Senthil Pandian
#****************************************************************************************************/
sub fileLock {
	unless (defined $_[0]) {
		#display('filename_is_required');
		return 1;
	}

	open(our $fh, ">>", $_[0]) or return 2;
	unless (flock($fh, LOCK_EX|LOCK_NB)) {
		#display('failed_to_lock');
		close($fh);
		unlink($_[0]);
		return 3;
	}
	else {
		print $fh $$;
		autoflush $fh;
		chmod $AppConfig::filePermission, $_[0];
		return 0;
	}
}

#------------------------------------------------- G -------------------------------------------------#
#*********************************************************************************************
#Subroutine Name    : getItemFullPath
#Objective          : Provides path where all the scripts are saved.
#Added By           : Abhishek Verma
#Modified By 		: Senthil Pandian
#*********************************************************************************************/
sub getItemFullPath{
	my $partialPath = $_[0];
	chomp($partialPath);
	my $pwdCmd = 'pwd';
	# $pwdCmd = updateLocaleCmd($pwdCmd);
	chomp(my $presentWorkingDir =`$pwdCmd`);
	$presentWorkingDir =~ s/\n//;
	$partialPath =~ s/^\.\/// if ($partialPath =~ /^\.\//);
	#print "\n PartialPath :: $partialPath\n";
	#print "\n presentWorkingDir :: $presentWorkingDir\n";
	#print "\n PartialPath2 :: ".$partialPath =~/(.*)\//?$1:$presentWorkingDir ."\n";
	#my $finallPath = $partialPath =~/(.*)\//?$1:$presentWorkingDir;
	my $finallPath = $partialPath; #=~/(.*)\//?$1:$presentWorkingDir;
	#print "\n FinallPath1 :: $finallPath\n";
	if ($finallPath ne ''){
		$finallPath = $finallPath =~ /^\//?$finallPath:$presentWorkingDir."/".$finallPath;
	}
	else{
		$finallPath = $presentWorkingDir;
	}
	# resolve all '..' from the path
	$finallPath = getAbsolutePath(split('/',$finallPath))	if ($finallPath =~ /\.\./g);
	#print "\n FinallPath5 :: $finallPath\n";
	return $finallPath;
}

#*******************************************************************************************************
# Subroutine Name         : getProgressDetails
# Objective               : Calculate cummulative progress data.
# Added By                : Vijay Vinoth
# Modified By             : Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#********************************************************************************************************/
sub getProgressDetails {
	my (@progressFileDetails, %individualProgressData);
	my @progressDetails = ('', 0, 0, 0, '', 0, 0); # type, transfered size, total size, transfer rate, filename, filesize, fileCount
	my $count = 1;
	my $progressDataFilename = $_[0];

	my $jobRunningDir = (fileparse($progressDataFilename))[1];
	my $statusFile    = getCatfile($jobRunningDir,$AppConfig::statusFile);
	my $pidFile       = getCatfile($jobRunningDir,$AppConfig::pidFile);
	my $infoFile      = getCatfile($jobRunningDir,$AppConfig::infoFile);
	my $infoFile1     = getECatfile($jobRunningDir,$AppConfig::infoFile);

	for(my $i = 1; $i <= $AppConfig::totalEngineBackup; $i++) {
		my $progressDataFile = ($progressDataFilename . "_$i");
		if (-f $progressDataFile and !-z _) {
			my $progressData = getFileContents($progressDataFile, 'array');
			next if (scalar @$progressData < 9);

			my $type = $progressData->[0];
			chomp($type);
			my $filesize = $progressData->[1];
			chomp($filesize);
			my $filename = $progressData->[5];
			chomp($filename);
			my $dataTransRate   = $progressData->[4];
			chomp($dataTransRate);
            # my $transferredSize = $progressData->[6];
            # chomp($transferredSize);

			$filename =~ s/^\s*(.*?)\s*$/$1/; # Remove spaces on both side
			unless ($filename eq '') {
				push (@progressFileDetails, {'type' => $type, 'filename' => $filename, 'filesize' => $filesize});
				# $individualProgressData{$i}{'data'} = "[$type] [$filename][$filesize][".convertFileSize($dataTransRate)."/s]";
				$individualProgressData{$i}{'data'} = "[$type] [$filename]";
				$individualProgressData{$i}{'per'}  = $progressData->[7];
                $individualProgressData{$i}{'rate'} = $dataTransRate;
                $individualProgressData{$i}{'size'} = $filesize;
			}

			$progressDetails[1] += $progressData->[2] if($progressData->[2] =~ /^\d+$/);
			$progressDetails[2]  = $progressData->[3];
			$progressDetails[3] += $dataTransRate if($dataTransRate =~ /^(\d+(\.\d+)?)$/);
			$progressDetails[6] += $progressData->[8] if($progressData->[8] =~ /^\d+$/);
			$count++;
		}
	}

	unless(-f $pidFile) {
        $progressDetails[6] = 0;
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES', 'DENIED_COUNT_FILES', 'MISSED_FILES_COUNT','TOTAL_TRANSFERRED_SIZE');
		my ($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount, $transferredFileSize) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
		# traceLog("$successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount");
		$progressDetails[6] += ($successFiles+$syncedFiles+$failedFilesCount+$noPermissionCount+$missingCount);
		if(-f $infoFile){
			my $syncCountCmd = "tail -10 $infoFile1 | grep \"^READYSYNC\"";
			$syncCountCmd = updateLocaleCmd("$syncCountCmd 2>/dev/null");
			my $syncCount = `$syncCountCmd`;
			$syncCount =~ s/READYSYNC//;
			Chomp(\$syncCount);
			$progressDetails[6] += $syncCount if($syncCount =~ /^\d+$/);
		}
	}

	if ($count > 1) {
		# $cumulativeCount, $cumulativeTransRate
		# if(defined($_[1]) and $_[1] ne 'paused') {
			# $AppConfig::cumulativeCount++;
			# $AppConfig::cumulativeTransRate += $progressDetails[3];
			# $progressDetails[3] = ($AppConfig::cumulativeTransRate/$AppConfig::cumulativeCount);
		# }
		#traceLog("cumulativeTransRate:".$AppConfig::cumulativeTransRate."#");
		#traceLog("Avg dataTransRate1:".$progressDetails[3]."#");
		# $progressDetails[3] = ($progressDetails[3]/$count);
		# $progressDetails[3] = convertFileSize($progressDetails[3]);
		for(my $i = 1; $i <= $AppConfig::totalEngineBackup; $i++) {
			if (scalar(@progressFileDetails) > 0) {
				my $hr = $progressFileDetails[rand @progressFileDetails];
				$progressDetails[0] = $hr->{'type'};
				$progressDetails[4] = $hr->{'filename'};
				$progressDetails[5] = $hr->{'filesize'};
			}
			last if($progressDetails[0] ne '');
		}
	}

	return (\@progressDetails,\%individualProgressData);
}

#****************************************************************************************************
# Subroutine Name	: getPermissionDeniedCount
# Objective			: This subroutine will return the count of permission denied error given by EVS.
# Modified By		: Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub getPermissionDeniedCount
{
	my $infoFile 		  = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;
	my $noPermissionCount = 0;

	if (-e $infoFile and !-z _) {
		$infoFile = getECatfile($AppConfig::jobRunningDir,$AppConfig::infoFile);
		my $deniedCountCheckCmd = "cat $infoFile | grep \"^DENIEDCOUNT\"";
		$deniedCountCheckCmd = updateLocaleCmd($deniedCountCheckCmd);
		$noPermissionCount = `$deniedCountCheckCmd`;
		$noPermissionCount =~ s/DENIEDCOUNT//;
		Chomp(\$noPermissionCount);
	}

	return $noPermissionCount;
}

#****************************************************************************************************
# Subroutine		: getReadySyncCount
# Objective			: Returns already synced count
# Added By			: Sabin Cheruvattil
#****************************************************************************************************
sub getReadySyncCount {
	my $synccount	= 0;
	my $info		= getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);

	if(-e $info && !-z _){
		my $synccmd = "cat '$info' | grep \"^READYSYNC\"";
		$synccount = `$synccmd`;
		$synccount =~ s/READYSYNC//;
		Chomp(\$synccount);
	}

	return $synccount? $synccount : 0;
}

#****************************************************************************************************
# Subroutine Name		: getIDriveUserList
# Objective				: Getting IDrive user list from service directory.
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#*****************************************************************************************************/
sub getIDriveUserList {
	my @idriveUsersList 	= ();
	my $usrProfileDirPath	= getCatfile(getServicePath(), $AppConfig::userProfilePath);
	return @idriveUsersList unless(-d $usrProfileDirPath);

	if (opendir(MCUSERDIR, $usrProfileDirPath)) {
		foreach my $userName (readdir(MCUSERDIR)) {
			next if ($userName =~ /^\.\.?$/ || $userName eq "tmp");

			my $mcUserProfileDir =  getCatfile(getServicePath(), $AppConfig::userProfilePath, $userName);
			next unless (-d $mcUserProfileDir);

			if (opendir(DIR, $mcUserProfileDir)) {
				foreach my $userName (readdir(DIR)) {
					next if ($userName =~ /^\.\.?$/ || $userName =~ /.trace|tmp/);

					my $idriveUserProfileDir 	= "$mcUserProfileDir/$userName";
					$idriveUserProfileDir		=  getCatfile($mcUserProfileDir, $userName);
					push(@idriveUsersList, $idriveUserProfileDir) if (-d $idriveUserProfileDir);
				}
			}
		}
	}

	return @idriveUsersList;
}

#*****************************************************************************************************
# Subroutine			: generateDBFromBackupset
# Objective				: Helps to generate the files for backupset
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#*****************************************************************************************************
sub generateDBFromBackupset {
	return 0 if(!$_[0] || !$_[1]);

	loadUserConfiguration();
	my $showhidden	= getUserConfiguration('SHOWHIDDEN');
	loadFullExclude();
	loadPartialExclude();
	loadRegexExclude();

	my ($oldbkpitems, $newbkpitems, $iscdp) = ($_[0], $_[1], $_[2]);
	my ($commitstat, $opstat) = (1, 1);

	Sqlite::beginDBProcess();

	my $scanprog	= getCDPLockFile('scanprog');
	unlink($scanprog) if(-f $scanprog);

	eval {
		require Tie::File;
		Tie::File->import();
	};

	tie my @fc, 'Tie::File', $scanprog;

	# Clean up the backup set db as some items would've got removed
	my $bsdbstats	= Sqlite::getBackupsetItemsWithStats();
	foreach my $bssdbitem (keys %{$bsdbstats}) {
		if(!grep(/^\Q$bssdbitem\E$/, @{$newbkpitems})) {
			# item not present in new backup set
			Sqlite::deleteFromBackupSet($bssdbitem);
		} elsif(-e $bssdbitem) {
			my $itype	= -d $bssdbitem? 'd' : -f _? 'f' : 'u';
			# corner case | no cdp, resource type changes [dir <--> file] | clean up
			Sqlite::deleteFromBackupSet($bssdbitem) if($bsdbstats->{$bssdbitem}{'type'} ne $itype);
		}
	}

	# collect the items 1 more time from DB, entries would've delete by clean up
	$bsdbstats		= Sqlite::getBackupsetItemsWithStats();
	# Remove items from old backup set, if items are missing or added back so that scan can process
	for my $obidx (0 .. $#{$oldbkpitems}) {
		my $obsitem	= $oldbkpitems->[$obidx];
		next unless(exists($bsdbstats->{$obsitem}));

		my $itype	= -d $obsitem? 'd' : -f _? 'f' : 'u';
		my $istat	= -e _;
		my $lmd		= $istat? stat($obsitem)->mtime : 0;

		if($bsdbstats->{$obsitem}{'stat'} ne $istat || $bsdbstats->{$obsitem}{'type'} ne $itype || $bsdbstats->{$obsitem}{'lmd'} ne $lmd) {
			delete($oldbkpitems->[$obidx]);
		}
	}

	# Remove the entries if not present in new backup set
	foreach my $item (@{$oldbkpitems}) {
		# Required | old backup check may remove the items from the array
		next unless($item);

		# GREP same exact element | check parent is present
		if(!grep(/^\Q$item\E$/, @{$newbkpitems}) && !scalar(hasParentInSet($item, $newbkpitems))) {
			if(-f $item) {
				my $fileName = (fileparse($item))[0];
				my $dirid = Sqlite::dirExistsInDB($item, '/');
				Sqlite::deleteIbFile($fileName, $dirid) if(Sqlite::checkItemInDB($item) ne '' && $dirid);
			} elsif(-d _) {
				Sqlite::deleteDirsAndFilesByDirName($item);
			} elsif(!-e _) {
				my $isdir = Sqlite::isPathDir($item);
				if($isdir) {
					Sqlite::deleteDirsAndFilesByDirName($item);
					next;
				}
				
				my $fileName = (fileparse($item))[0];
				my $dirid = Sqlite::dirExistsInDB($item, '/');
				$fileName = "'$fileName'";

				Sqlite::deleteIbFile($fileName, $dirid) if(Sqlite::checkItemInDB($item) ne '' && $dirid);
			}
		}
	}

	# Add/update files/directories
	my $item		= '';
	my @origbkpset	= @{$newbkpitems};
	my $obkicount	= scalar(@{$oldbkpitems});
	foreach $item (@{$newbkpitems}) {
		chomp($item);
		if(!-l $item && -d _) {
			eval {
				Sqlite::addToBackupSet($item, 'd', 1, stat($item)->mtime) if(grep(/^\Q$item\E$/, @origbkpset));
				1;
			} or do {
				traceLog($@);
			};

			next if(grep(/^\Q$item\E$/, @{$oldbkpitems}));

			# Enumerate recursively
			$opstat = enumerateDirAndUpdateDB($item, $newbkpitems, \@fc, undef, $iscdp);
			$commitstat = 0 unless($opstat);
		} elsif(!-l _ && -f _) {
			my $itype	= 'f';
			my $istat	= 1;
			my $sf		= stat($item);

			Sqlite::addToBackupSet($item, $itype, 1, $sf->mtime) if(grep(/^\Q$item\E$/, @origbkpset));

			if(!Sqlite::checkItemInDB($item) || 
			(defined($bsdbstats->{$item}) && ($bsdbstats->{$item}{'stat'} ne $istat || $bsdbstats->{$item}{'type'} ne $itype || $bsdbstats->{$item}{'lmd'} ne $sf->mtime))) {
				my $fileName	= (fileparse($item))[0];
				my $dirid		= Sqlite::dirExistsInDB($item, '/');

				$fileName		= "'$fileName'";
				$dirid			= Sqlite::insertDirectories($item, '/') unless($dirid);

				my $status		= $AppConfig::dbfilestats{'NEW'};
				$status			= $AppConfig::dbfilestats{'EXCLUDED'} if(isThisExcludedItemSet($item . '/', $showhidden));

				if($status eq $AppConfig::dbfilestats{'NEW'}) {
					my %fileListHash  =  Sqlite::fileListInDbDir(dirname($item) . '/');
					if(((exists $fileListHash{$fileName} && $fileListHash{$fileName}{'BACKUP_STATUS'} == $AppConfig::dbfilestats{'CDP'}) || $iscdp) && $sf->size <= $AppConfig::cdpmaxsize) {
						$status	= $AppConfig::dbfilestats{'CDP'};
					}

					undef %fileListHash;
				}

				$opstat = Sqlite::insertIbFile(1, $dirid, $fileName, $sf->mtime, $sf->size, $status);
				$commitstat = 0 unless($opstat);

				$fc[1]++;
				$fc[0]			= $item;
			}
		} elsif(!-e _) {
			Sqlite::addToBackupSet($item, 'u', 0, 0) if(grep(/^\Q$item\E$/, @origbkpset));
			my $isdir = Sqlite::isPathDir($item);
			if($isdir) {
				Sqlite::deleteDirsAndFilesByDirName($item);
				next;
			}

			my $fileName = (fileparse($item))[0];
			my $dirid = Sqlite::dirExistsInDB($item, '/');
			$fileName = "'$fileName'";

			Sqlite::deleteIbFile($fileName, $dirid) if(Sqlite::checkItemInDB($item) ne '' && $dirid);
		}
	}

	# let progress read the scan result
	sleepForMilliSec(500);

	untie @fc;
	undef @fc;
	unlink($scanprog);

	Sqlite::commitDBProcess($item);

	undef @origbkpset;
	undef @{$newbkpitems};
	undef %{$bsdbstats};

	return $commitstat;
}

#*************************************************************************************
# Subroutine		: getSizeLMD
# Objective			: This subroutine gets the last modified time and size
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub getSizeLMD {
	my $path	= $_[0];
	my ($lmd, $size) = (0, 0);

	if(-e $path) {
		my $stat	= stat($path);
		$lmd		= $stat->mtime;
		$size		= $stat->size;
	}

	return ($lmd, $size);
}

#**********************************************************************************************
#Sbroutine Name         : getAbsolutePath
#Objective              : retuns Absolute path for given relative path
#Usage                  : getAbsolutePath(LIST); ~List should not be hash~. eg:@relativePath = '/a/b/c/d/../../e/f/../g' AbsolutePath: /a/b/e/g
#Added By               : Abhishek Verma
#***********************************************************************************************
sub getAbsolutePath {
	for(my $i=0; $i<=$#_; $i++) {
		if ($_[$i] eq '..') {
			splice (@_, $i-1, 2);
			$i = $i-2;
		}
	}

	return join ('/', @_);
}

#*****************************************************************************************************
# Subroutine			: getAbsPath
# Objective				: Get the absolute path of a file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getAbsPath {
	return abs_path(shift);
}

#*****************************************************************************************************
# Subroutine			: getBackupsetSizeLockFile
# Objective				: Get backup set size lock file path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetSizeLockFile {
	return getCatfile(getUsersInternalDirPath($_[0]), $AppConfig::backupsizelock);
}

#*****************************************************************************************************
# Subroutine			: getCDPLockFile
# Objective				: Get cdp server/client lock file path
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPLockFile {
	return '' unless($_[0]);
	return '' unless(exists($AppConfig::cdplocks{$_[0]}));

	return ($_[1] and -d $_[1])? getCatfile($_[1], $AppConfig::cdplocks{$_[0]}) : getCatfile(dirname(getJobsPath('cdp')), $AppConfig::cdplocks{$_[0]});
}

#*****************************************************************************************************
# Subroutine			: getCDPHaltFile
# In Param				: None
# Out Param				: String | Path
# Objective				: Gets CDP Halt file path
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPHaltFile {
	return getCatfile(getAppPath(), $AppConfig::cdphalt);
}

#*****************************************************************************************************
# Subroutine			: getWebViewDir
# In Param				: None
# Out Param				: String | Path
# Objective				: Gets Web view xml directory
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getWebViewDir {
	return getCatfile(getUserProfilePath(), $AppConfig::webvxmldir, '');
}

#*****************************************************************************************************
# Subroutine			: getCDPLogName
# Objective				: Get cdp log name for the current path
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPLogName {
	return '' if(!$_[0] || !-d $_[0]);

	my $dir		= $_[0];
	my $dh;
	return '' unless(opendir($dh, $dir));

	my @now		= localtime;
	($now[0], $now[1], $now[2]) = (1, 0, 0);

	my $ct		= mktime(@now);
	my ($logname, $logpath) = ('', '');

	foreach my $exlog (readdir($dh)) {
		if($exlog =~ /^$ct/) {
			$logname = $exlog;
			last;
		}
	}

	closedir($dh);

	$logname	= $ct . '_Running_' . uc($AppConfig::cdp) if($logname eq '');
	$logpath	= getCatfile($dir, $logname);

	return $logpath;
}

#*****************************************************************************************************
# Subroutine			: getCDPDBPaths
# Objective				: Get the absolute paths to the db <- backup set name
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPDBPaths {
	my @jobs	= ('backup', 'localbackup');
	my %dbpaths	= ();

	for my $jidx (0 .. $#jobs) {
		my $jobsets	= getJobsetNamesbyJobType($jobs[$jidx]);
		my $dir		= dirname(getJobsPath($jobs[$jidx]));

		%dbpaths = (%dbpaths, map{$_ => getCatfile($dir, (split(/\|/, $_))[1]) . '/'} @{$jobsets});
	}

	return \%dbpaths;
}

#*****************************************************************************************************
# Subroutine			: getCDPDBDumpDir
# Objective				: Get the absolute paths to CDP DB Dump directory
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPDBDumpDir {
	return getCatfile(getUserProfilePath(), $AppConfig::cdpdbdumpdir);
}

#*****************************************************************************************************
# Subroutine			: getFailedCommitDir
# Objective				: Get the absolute paths to CDP DB Dump directory
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getFailedCommitDir {
	return getCatfile(getUserProfilePath(), $AppConfig::failcommitdir);
}

#*****************************************************************************************************
# Subroutine			: getCommitVaultDir
# Objective				: Get the absolute paths to CDP DB Dump directory
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCommitVaultDir {
	return getCatfile(getUserProfilePath(), $AppConfig::commitvault);
}

#*****************************************************************************************************
# Subroutine			: getCDPDBDumpFile
# Objective				: Get the absolute paths to CDP DB Dump file
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPDBDumpFile {
	return '' if(!$_[0] || !exists($AppConfig::dbdumpregs{$_[0]}));

	my $dumpdir		= getCDPDBDumpDir();
	createDir($dumpdir, 1) unless(-d $dumpdir);

	my $ts		= int(mktime(localtime) * 10000) + int(rand(10000));
	my $dfname	= $AppConfig::dbdumpregs{$_[0]};

	 if($_[1]) {
		$dfname	=~ s/\*/$_[1]/;
	} elsif($AppConfig::dbdumpregs{$_[0]} =~ /\*/) {
		$dfname	= $AppConfig::dbdumpregs{$_[0]} . $ts;
		$dfname	=~ s/\*//;
	}

	return getCatfile($dumpdir, $dfname . '.cdpdbdump');
}

#*****************************************************************************************************
# Subroutine			: getCDPWatchEntities
# Objective				: Get the directories/files for CDP watch
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPWatchEntities {
	my $jobsets = [];
	my @jobs	= ('backup', 'localbackup');

	for my $jidx (0 .. $#jobs) {
		push(@{$jobsets}, @{getJobsetNamesbyJobType($jobs[$jidx])});
	}

	my (@watchdirs, $jsc, %jsjobwatch, %jsitems, @jobinfo);

	return [] unless(scalar(@{$jobsets}));

	for my $i (0 .. $#{$jobsets}) {
		@jobinfo = split(/\|/, $jobsets->[$i]);
		$jsc = getJobsetContents($jobinfo[0], $jobinfo[1]);
		$jsitems{$jobsets->[$i]} = $jsc;

		for my $jscidx (0 .. scalar(@{$jsc})) {
			next unless($jsc->[$jscidx]);
			push(@watchdirs, $jsc->[$jscidx]);
			$jsjobwatch{$jsc->[$jscidx]} = [] unless(exists($jsjobwatch{$jsc->[$jscidx]}));
			push @{$jsjobwatch{$jsc->[$jscidx]}}, $jobsets->[$i];
		}
	}

	# check for duplicate entries
	if(scalar(@watchdirs)) {
		my %uniqehash	= getUniquePresentData(\@watchdirs, 'backup', 0, 1);
		%uniqehash		= skipChildIfParentDirExists(\%uniqehash, 0);
		@watchdirs		= keys %uniqehash;
	}

	return (\@watchdirs, \%jsjobwatch, \%jsitems);
}

#*****************************************************************************************************
# Subroutine			: getDBJobsetsByFile
# Objective				: Gets the name of backup sets by the item present in the backup sets
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#*****************************************************************************************************
sub getDBJobsetsByFile {
	return [] if(!$_[0] || !$_[1]);

	my (@jobnames, @matchitems);
	@matchitems = grep{$_[1] =~ /^\Q$_\E/} keys %{$_[0]};
	# @matchitems = grep{$_ =~ /^\Q$_[1]\E/} @{$incwatch} unless(@matchitems); #Added for Suruchi_1_13_4: Senthil

	@jobnames	= map{@{$_[0]->{$_}}} @matchitems;

	if(scalar(@jobnames) > 0) {
		my %index = ();
		@jobnames = grep{!$index{$_}++} @jobnames;
	}
	
	return \@jobnames;
}

#*****************************************************************************************************
# Subroutine			: getJobsetContents
# Objective				: Get the backup set contents by job type and name as Array
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getJobsetContents {
	return [] if(!$_[0] || !$_[1]);
	return [] unless(exists($AppConfig::availableJobsSchema{$_[0]}));
	
	my $dir		= dirname(getJobsPath($_[0]));
	my $jspath	= getCatfile($dir, $_[1], $AppConfig::backupsetFile);

	return getDecBackupsetContents($jspath, 'array') if(-f $jspath && -s _ > 0);
	return [];
}

#*****************************************************************************************************
# Subroutine	: getDecBackupsetContents
# In Param		: Path | String
# Out Param		: Contents | Mixed
# Objective		: Gets plain backup set either as string or array
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getDecBackupsetContents {
	my $jspath	= $_[0];
	return '' if(!$jspath || !-f $jspath);

	my $rtype	= !defined($_[1])? 0 : $_[1];
	my $bsc		= decryptString(getFileContents($jspath));

	if($rtype eq 'array') {
		my @barr = split("\n", $bsc);
		return \@barr;
	}

	return $bsc;
}

#*****************************************************************************************************
# Subroutine			: getJobsetNamesbyJobType
# Objective				: Gets the list of job names for a particular job type
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getJobsetNamesbyJobType {
	return [] unless($_[0]);
	return [] unless(exists($AppConfig::availableJobsSchema{$_[0]}));

	my ($dh, @jobnames);
	my $dir		= dirname(getJobsPath($_[0]));
	unless(AppConfig::MULTIPLE_BACKUP_SET) {
		push(@jobnames, qq($_[0]|) . basename(getJobsPath($_[0]))) if(-f getJobsPath($_[0]) && !-z _);
		return \@jobnames;
	}

	return [] unless(opendir($dh, $dir));

	foreach my $jsname (readdir($dh)) {
		next if($jsname =~ m/^$/ || $jsname =~ m/^[\s\t]+$/ || $jsname =~ /^\.\.?$/);
		push(@jobnames, qq($_[0]|$jsname)) if(-d getCatfile($dir, $jsname) && (-f getCatfile($dir, $jsname, $AppConfig::backupsetFile) || -f getCatfile($dir, $jsname, $AppConfig::restoresetFile)));
	}
	
	return \@jobnames;
}

#*****************************************************************************************************
# Subroutine			: getJobsetPathsByJobType
# Objective				: Gets the list of jobname -> job path for a particular job type
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getJobsetPathsByJobType {
	return [] unless($_[0]);
	return [] unless(exists($AppConfig::availableJobsSchema{$_[0]}));
	
	my ($dh, %jobpaths);
	unless(AppConfig::MULTIPLE_BACKUP_SET) {
		$jobpaths{basename(getJobsPath($_[0]))} = getJobsPath($_[0]);
		return \%jobpaths;
	}

	my $dir		= dirname(getJobsPath($_[0]));

	return [] unless(opendir($dh, $dir));

	foreach my $jsname (readdir($dh)) {
		next if($jsname =~ m/^$/ || $jsname =~ m/^[\s\t]+$/ || $jsname =~ /^\.\.?$/);
		$jobpaths{$jsname} = getCatfile($dir, $jsname) if(-d getCatfile($dir, $jsname) && (-f getCatfile($dir, $jsname, $AppConfig::backupsetFile) || -f getCatfile($dir, $jsname, $AppConfig::restoresetFile)));
	}
	
	return \%jobpaths;
}

#*****************************************************************************************************
# Subroutine			: getAllBackupJobPaths
# Objective				: Gets the list of job name -> job path for all backup jobs [backup & express backup]
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getAllBackupJobPaths {
	my %bkjobpaths;
	$bkjobpaths{'backup'}		= getJobsetPathsByJobType('backup');
	$bkjobpaths{'localbackup'}	= getJobsetPathsByJobType('localbackup');
	
	return \%bkjobpaths;
}

#*****************************************************************************************************
# Subroutine			: getBackupsetScanType
# Objective				: Gets the scan type of backupset if it is in progress
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getBackupsetScanType {
	my $scanlock	= getCDPLockFile('bkpscan');
	return '' if(!-f $scanlock || !isFileLocked($scanlock));

	my $fc	= getFileContents($scanlock);
	return '' unless($fc);

	my @fd	= split(/\-\-/, $fc);

	return $fd[0]? $fd[0] : '';
}

#*****************************************************************************************************
# Subroutine	: getLocalBkpSetStats
# In Param		: Path | String
# Out Param		: Status | Hash
# Objective		: Loads backup set stats in a hash
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getLocalBkpSetStats {
	my $path		= $_[0];
	my $bkpsetfile	= getCatfile($path, $AppConfig::backupsetFile);
	my $fca			= getDecBackupsetContents($bkpsetfile, 'array');
	my %locstats	= ();

	foreach my $item (@{$fca}) {
		next unless($item);

		my $itype	= -d $item? 'd' : -f _? 'f' : 'u';
		my $istat	= -e _? 1 : 0;
		my $lmd		= $istat? stat($item)->mtime : 0;

		$locstats{$item} = {'stat' => $istat, 'type' => $itype, 'lmd' => $lmd};
	}
	
	return \%locstats;
}

#*****************************************************************************************************
# Subroutine	: getExpressDBHashRoot
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Gets the server root stored in the DB
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getExpressDBHashRoot {
	my $dbpath	= getJobsPath('localbackup', 'path');
	my $dbfile	= getCatfile($dbpath, $AppConfig::dbname);

	return (undef, undef) unless(-f $dbfile);

	my ($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 0);
	return (undef, undef) unless($dbfstate);

	Sqlite::initiateDBoperation();
	my $exroot = Sqlite::getConfiguration('MPC');
	my $exhash = Sqlite::getConfiguration('DATAHASH');
	Sqlite::closeDB();

	return ($exroot, $exhash);
}

#*****************************************************************************************************
# Subroutine	: getReadySyncItemCount
# In Param		: String | Path
# Out Param		: Integer | Number of sync records
# Objective		: Gets the server root stored in the DB
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getReadySyncItemCount {
	return 0 if(!$_[0] || !-d $_[0]);

	my $dbpath	= $_[0];
	my $dbfile	= getCatfile($dbpath, $AppConfig::dbname);
	return 0 unless(-f $dbfile);
	
	my ($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 0);
	return 0 unless($dbfstate);

	Sqlite::initiateDBoperation();
	my $rsc = Sqlite::getReadySyncedCount();
	Sqlite::closeDB();

	return $rsc? $rsc : 0;
}

#*****************************************************************************************************
# Subroutine	: getMPC
# In Param		: UNDEF
# Out Param		: String | MPC
# Objective		: Gets the server root
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getMPC {
	my $mpc = '';
	if(getUserConfiguration('DEDUP') eq 'on') {
		$mpc = getUserConfiguration('SERVERROOT')
	} else {
		# Copied the logic from express backup backup to[$mpc] decide section
		$mpc	= getUserConfiguration('BACKUPLOCATION');
		my @mpc	= split("/", $mpc);
		$mpc	= (substr($mpc, 0, 1) eq '/')? '/' . $mpc[1] : '/' . $mpc[0];
	}

	return $mpc;
}

#*****************************************************************************************************
# Subroutine	: getEncDatahash
# In Param		: UNDEF
# Out Param		: String | datahash
# Objective		: Gets the encryption datahash
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getEncDatahash {
	my $datahash	= getUserConfiguration('ENCRYPTIONTYPE');
	if($datahash eq 'PRIVATE') {
		my $pvtk	= '';
		$pvtk = getFileContents(getIDPVTFile()) if(-f getIDPVTFile());
		$datahash .= '+' . $pvtk if($pvtk);
	}

	return encryptString($datahash);
}

#*****************************************************************************************************
# Subroutine	: getVersionCachePath
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Get version cache file
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getVersionCachePath {
	return getCatfile(getServicePath(), $AppConfig::versioncache);
}

#*****************************************************************************************************
# Subroutine			: getLoggedInUsername
# Objective				: Gives back current logged in user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getLoggedInUsername {
	my $cf		= getUserFile();
	my $cuser	= '';

	return '' if (!-f $cf || -z _);
	return '' unless (open(my $u, '<', $cf));

	my $userdata = <$u>;
	close($u);
	Chomp(\$userdata);

	my %datahash = %{JSON::from_json($userdata)};
	return '' unless(exists($datahash{$AppConfig::mcUser}));
	return '' if(!exists($datahash{$AppConfig::mcUser}{'userid'}) || !exists($datahash{$AppConfig::mcUser}{'isLoggedin'}));

	$cuser = $datahash{$AppConfig::mcUser}{'userid'} if($datahash{$AppConfig::mcUser}{'isLoggedin'} == 1);
	return $cuser;
}

#*****************************************************************************************************
# Subroutine			: getCurrentUsername
# Objective				: Gives back current user who is logged in/out
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getCurrentUsername {
	my $cf		= getUserFile();
	my $cuser	= '';

	return '' if (!-f $cf || -z _);
	return '' unless (open(my $u, '<', $cf));
	
	my $userdata = <$u>;
	close($u);
	Chomp(\$userdata);

	my %datahash = %{JSON::from_json($userdata)};
	return '' unless(exists($datahash{$AppConfig::mcUser}));
	return '' if(!exists($datahash{$AppConfig::mcUser}{'userid'}) || !exists($datahash{$AppConfig::mcUser}{'isLoggedin'}));

	$cuser = $datahash{$AppConfig::mcUser}{'userid'};
	return $cuser;
}

#*****************************************************************************************************
# Subroutine			: getBackupsetSizeSycnLockFile
# Objective				: Get backup set size sync lock file path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetSizeSycnLockFile {
	return getCatfile(getUsersInternalDirPath($_[0]), $AppConfig::backupsizesynclock);
}

#*****************************************************************************************************
# Subroutine			: getBackupsetFileAndMissingCount
# Objective				: get backup set file and missing count
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetFileAndMissingCount {
	my $backupsetfilecount	= 0;
	my $backupsetfile		= $_[0];
	return $backupsetfilecount if (!-f $backupsetfile or !-s _);

	my $backupsetdata	= getDecBackupsetContents($backupsetfile, 'array');
	my $fname			= '';
	for my $i (0 .. $#{$backupsetdata}) {
		$fname			= @{$backupsetdata}[$i];
		chomp($fname);
		next if ($fname eq '');

		unless(-e $fname) {
			$backupsetfilecount++;
			next;
		}

		$backupsetfilecount++ if (-f $fname);
	}

	return $backupsetfilecount;
}

#*****************************************************************************************************
# Subroutine			: getBackupsetItemCount
# Objective				: get backup set item count
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetItemCount {
	my $backupsetitemcount	= 0;
	my $backupsetfile		= $_[0];
	return $backupsetitemcount if (!-f $backupsetfile or !-s _);

	my $backupsetdata	= getDecBackupsetContents($backupsetfile, 'array');
	my $fname			= '';
	for my $i (0 .. $#{$backupsetdata}) {
		$fname			= @{$backupsetdata}[$i];
		chomp($fname);
		next if ($fname eq '');

		$backupsetitemcount++;
	}

	return $backupsetitemcount;
}

#*****************************************************************************************************
# Subroutine	: getBackupLocationSize
# In Param		: UNDEF
# Out Param		: Size | Integer
# Objective		: Check and gets the backup location size if it is non-dedup account
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getBackupLocationSize {
	return 0 if(getUserConfiguration('DEDUP') ne 'off');

	my $backuploc		= getUserConfiguration('BACKUPLOCATION');
	my $propdir			= getCatfile(getUserProfilePath(), 'tmp_prop');
	my $proputf8path	= getCatfile($propdir, $AppConfig::utf8File);
	my $properrorpath	= getCatfile($propdir, $AppConfig::evsErrorFile);

	mkdir($propdir, $AppConfig::execPermission) unless(-d $propdir);

	createUTF8File(['PROPERTIES', $proputf8path],
		$properrorpath,
		$backuploc
		) or retreat('failed_to_create_utf8_file');

	my $size		= 0;
	my @response	= runEVS('item', 1);
	if (defined($response[2]->{'size'})){
		$size	= $response[2]->{'size'};
		$size =~ s/ bytes//i;
	}

	removeItems($propdir);

	return $size;
}

#*****************************************************************************************************
# Subroutine			: getBackupsetFileSize
# Objective				: Calculate backup set size of the files
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetFileSize {
	my $fc 					= 0;
	my $backupsetdata 		= $_[0];
	my %backupsetsizes		= ();
	my $filename			= '';
	my $processingreq = 0;

	loadUserConfiguration();
	loadFullExclude();
	loadPartialExclude();
	loadRegexExclude();
	my $showhidden = getUserConfiguration('SHOWHIDDEN');

	for my $i (0 .. $#{$backupsetdata}) {
		$filename = @{$backupsetdata}[$i];
		chomp($filename);
		next if ($filename eq '');

		if (!-e $filename) {
			$backupsetsizes{$filename} = {'size' => 0, 'filecount' => 'NA', 'type' => 'u'};
		}
		elsif (-f _) {
			$backupsetsizes{$filename} = {'size' => getFileSize($filename, \$fc), 'filecount' => (isThisExcludedItemSet($filename . '/', $showhidden)? 'EX' : '1'), 'type' => 'f'};
		} else {
			$processingreq = 1;
			$backupsetsizes{$filename} = {'size' => -1, 'filecount' => 'NA', 'type' => 'd'};
		}
	}

	return ($processingreq, %backupsetsizes);
}

#*****************************************************************************************************
# Subroutine			: getCurrentConfScriptVersion
# In Param				: UNDEF
# Out Param				: String | Version
# Objective				: Gets the current scripts version
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCurrentConfScriptVersion {
	my $vpath	= getVersionCachePath();
	my $cachver	= '0';

	if(-f $vpath) {
		$cachver	= getFileContents($vpath);
		Chomp(\$cachver);
	}
	
	return $cachver;
}

#*****************************************************************************************************
# Subroutine	: getPkgInstallables
# In Param		: Hashref | std installables
# Out Param		: Hashref | installables
# Objective		: Gets a list of installables if its not installed in this machine
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getPkgInstallables {
	my $pkginstallseq = $_[0];
	my (@newpkginst, @packages);

	for my $instidx (0 .. $#{$pkginstallseq}) {
		$pkginstallseq->[$instidx] =~ /(.*?)install\s(.*)/is;

		my $packs = $2 || '';
		$packs =~ s/-qq //g;
		$packs =~ s/-q //g;
		$packs =~ s/-y //g;
		Chomp(\$packs);
		next if(!$packs || $packs =~ /refresh/i);

		# Check whether the package is installed or not
		my $inststat = `which $packs 2>/dev/null`;
		Chomp(\$inststat);
		next if($inststat);

		push(@newpkginst, $pkginstallseq->[$instidx]);
		push(@packages, $packs);
	}
	
	return (\@newpkginst, \@packages);
}

#*****************************************************************************************************
# Subroutine	: getCPANInstallables
# In Param		: Hashref | cpan installables
# Out Param		: Hashref | installables
# Objective		: Gets a list of cpan installables if its not installed in this machine
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getCPANInstallables {
	my $cpaninstallseq = $_[0];
	my (@newcpaninst, @cpanpacks);
	my $nopd	= 0;

	my $pdw		= `which perldoc 2>/dev/null`;
	chomp($pdw);
	$nopd		= 1 unless($pdw);

	for my $instidx (0 .. $#{$cpaninstallseq}) {
		$cpaninstallseq->[$instidx] =~ /(.*?)install\s(.*?)\'/s;
		my $cpanmod = `perldoc -l $2 2>/dev/null`;
		Chomp(\$cpanmod);

		if(!$cpanmod || $nopd) {
			push(@newcpaninst, $cpaninstallseq->[$instidx]);
			push(@cpanpacks, $2);
		}
	}

	return (\@newcpaninst, \@cpanpacks);
}

#*****************************************************************************************************
# Subroutine			: getCatfile
# Objective				: Get concatenating several directory and file names into a single path
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getCatfile {
	return catfile(@_);
}

#*****************************************************************************************************
# Subroutine	: getECatfile
# Objective		: Get concatenating several directory and file names into a single path with
#                   escaping space character
# Added By		: Yogesh Kumar, Vijay Vinoth
#****************************************************************************************************/
sub getECatfile {
	my $file = catfile(@_);
	$file =~ s/([^a-zA-Z0-9_\/.-@#])/\\$1/g;
	return qq($file);
}

#*****************************************************************************************************
# Subroutine			: getIDrivePerlBin
# Objective				: Get IDrive perl binary
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDrivePerlBin {
	if ($AppConfig::appType eq 'IDrive') {
		if (getUserConfiguration('RMWS') and getUserConfiguration('RMWS') eq 'yes') {
			return $AppConfig::perlBin;
		}
		else {
			if (-f getCatfile(getAppPath(), $AppConfig::idrivePerlBinPath, $AppConfig::staticPerlBinaryName)) {
				return getECatfile(getAppPath(), $AppConfig::idrivePerlBinPath, $AppConfig::staticPerlBinaryName);
			}
			else {
				return $AppConfig::perlBin;
			}
		}
	}
	else {
		return $AppConfig::perlBin;
	}
}

#*****************************************************************************************************
# Subroutine			: getEditor
# Objective				: Get user's editor name if it is available or return default "vi" editor
# Added By				: Senthil pandian
#****************************************************************************************************/
sub getEditor {
	return $ENV{EDITOR} || 'vi';
}

#*****************************************************************************************************
# Subroutine      : getMountPoints
# Objective       : Get all mounted list of devices
# Usage			  : Parameter is optional. Parameters can be either one from list('all','Writeable','Read-only','No access')
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar
#****************************************************************************************************/
sub getMountPoints {
	my $permissionChoice = defined($_[0]) ? $_[0] : "all";
	my %mountPoints = ();
	my @linuxOwnDefaultPartitions = (
		'/',
		'/dev',
		'/dev/',
		'/boot',
		'/boot/',
		'/sys/',
		'/usr/',
		'/var/',
		'/tmp',
		'/.snapshots',
		'/srv',
		'/opt',
		'/opt/',
		'/home'
	);

	my $FilesystemCmd = updateLocaleCmd('df -k | grep -v Filesystem');
	my $fileSystems = `$FilesystemCmd`;
	my @fsDetails;
	my @matches;
	my $targetMountDevice;
	foreach my $fileSystem (split("\n", $fileSystems)) {
		@fsDetails = split(/[\s\t]+/, $fileSystem, 6);
		next if (scalar(@fsDetails) < 5 || $fsDetails[5] eq '/');
		$targetMountDevice = (split(/\//, $fsDetails[5]))[1];
		@matches = grep { /^\/$targetMountDevice$/ } @linuxOwnDefaultPartitions;
		if ((scalar(@matches) > 0) or ($fsDetails[1] < 512000)) {
			next;
		}

		my $permissionMode = getFileFolderPermissionMode($fsDetails[5]);
		if ($permissionChoice eq $permissionMode || $permissionChoice eq 'all') {
			$mountPoints{$fsDetails[5]}{'type'} = 'd';
			$mountPoints{$fsDetails[5]}{'mode'} = $permissionMode;
		}
	}

	#Adding default mount point
	if (-d $AppConfig::defaultMountPath){
		my $permissionMode = getFileFolderPermissionMode($AppConfig::defaultMountPath);
		if ($permissionChoice eq $permissionMode || $permissionChoice eq 'all') {
			$mountPoints{$AppConfig::defaultMountPath}{'type'} = 'd';
			$mountPoints{$AppConfig::defaultMountPath}{'mode'} = $permissionMode;
		}
	}

    #Added to list the custom mount point used for local backup
    my $localBackupMountPoint = getUserConfiguration('LOCALMOUNTPOINT');
    if($localBackupMountPoint ne '' and !exists($mountPoints{$localBackupMountPoint})
        and -d $localBackupMountPoint) {
		my $permissionMode = getFileFolderPermissionMode($localBackupMountPoint);
		if ($permissionChoice eq $permissionMode || $permissionChoice eq 'all') {
			$mountPoints{$localBackupMountPoint}{'type'} = 'd';
			$mountPoints{$localBackupMountPoint}{'mode'} = $permissionMode;
		}        
    }

    #Added to list the custom mount point used for local restore
    my $localRestoreMountPoint = getUserConfiguration('LOCALRESTOREMOUNTPOINT');
    if($localRestoreMountPoint ne '' and !exists($mountPoints{$localRestoreMountPoint})
        and -d $localRestoreMountPoint) {
		my $permissionMode = getFileFolderPermissionMode($localRestoreMountPoint);
		if ($permissionChoice eq $permissionMode || $permissionChoice eq 'all') {
			$mountPoints{$localRestoreMountPoint}{'type'} = 'd';
			$mountPoints{$localRestoreMountPoint}{'mode'} = $permissionMode;
		}        
    }

	return \%mountPoints;
}

#*****************************************************************************************************
# Subroutine			: getUserFile
# Objective				: Build path to cached file
# Added By				: Yogesh Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub getUserFile {
	return ("$servicePath/$AppConfig::cachedIdriveFile");
}

#*****************************************************************************************************
# Subroutine			: getOldUserFile
# Objective				: Build path to cached idrive file
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub getOldUserFile {
	return ("$servicePath/$AppConfig::cachedFile");
}

#*****************************************************************************************************
# Subroutine			: getCachedDir
# Objective				: Build path to cached Directory
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getCachedDir {
	return ("$servicePath/cache");
}

#*****************************************************************************************************
# Subroutine			: getCachedStorageFile
# Objective				: Build path to user quota.txt  file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getCachedStorageFile {
	return (getUserProfilePath() . "/$AppConfig::quotaFile");
}

#************************************************************************************************
# Subroutine Name         : getCursorPos
# Objective               : gets the current cusror position
# Added By                : Senthil Pandian
# Modified By             : Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#*************************************************************************************************
sub getCursorPos {
	return if($AppConfig::callerEnv eq 'BACKGROUND');
=beg
	system('stty', '-echo');
	my $x='';
	my $inputTerminationChar = $/;
	my $linesToRedraw = $_[0];
	my $devtty	= 0;
	if(open(my $tty, "+</dev/tty")) {
		close($tty);
		$devtty = 1;
	}

	# In non-terminal mode, we don't have to check tty
	if($devtty) {
		system "stty cbreak </dev/tty >/dev/tty 2>&1";
	} else {
		system "stty cbreak";
	}

	print "\e[6n";
	$/ = "R";
	$x = <STDIN>;
	$/ = $inputTerminationChar;

	if($devtty) {
		system "stty -cbreak </dev/tty >/dev/tty 2>&1";
	} else {
		system "stty -cbreak";
	}

	my ($curLines, $cols) = $x =~ m/(\d+)\;(\d+)/;
	system('stty', 'echo');
	my $totalLinesCmd = updateLocaleCmd('tput lines');
	my $totalLines = `$totalLinesCmd`;

	chomp($totalLines);
	my $threshold = $totalLines - $linesToRedraw;
	if ($curLines >= $threshold) {
		system("clear") unless(defined($_[2]));
		# system("clear");
		print $lineFeed;
		$curLines = 0;
	} else {
		$curLines = $curLines-1;
	}
=cut
	changeSizeVal();
	#Added for FreeBSD machine's progress bar display
	if ($AppConfig::machineOS =~ /freebsd/i) {
		my $latestCulmnCmd = updateLocaleCmd('tput cols');
		$latestCulmn = `$latestCulmnCmd`;
		my $freebsdProgress .= (' ')x$latestCulmn;
		$freebsdProgress .= $lineFeed;
		$AppConfig::freebsdProgress = $freebsdProgress;
	}
	print " ".$lineFeed;
	system(updateLocaleCmd("tput sc"));
	print "$_[1]" if ($_[1] and $_[1] ne '');
}

#*****************************************************************************************************
# Subroutine			: getEVSBinaryFile
# Objective				: Build path to user EVS binary file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getEVSBinaryFile {
	if ($AppConfig::appType eq 'IDrive') {
		return ((defined(getUserConfiguration('DEDUP')) && getUserConfiguration('DEDUP') eq 'off')? "$servicePath/$AppConfig::evsBinaryName" : "$servicePath/$AppConfig::evsDedupBinaryName");
	} else {
		return "$servicePath/$AppConfig::evsBinaryName";
	}
}


#*****************************************************************************************************
# Subroutine			: getEVSBinaryDownloadPath
# Objective				: Return the EVS binary file download path based on app & arch
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getEVSBinaryDownloadPath {
	my $arch = $_[0];
	my $evsWebPath  = '';

	my $downloadPage = $AppConfig::evsDownloadsPage;
	my $domain       = lc($AppConfig::appType);
	$domain .= 'downloads' if ($AppConfig::appType eq 'IDrive');

	$downloadPage =~ s/__APPTYPE__/$domain/g;
	$downloadPage .= "/".$AppConfig::appType."_Linux_" . $arch . ".zip";

	return $downloadPage;
}

#****************************************************************************************************
# Subroutine Name         : getFinalMailAddrList
# Objective               : To get valid multiple mail address list
# Added By                : Dhritikana
# Modified By             : Senthil Pandian
#*****************************************************************************************************
sub getFinalMailAddrList
{
	my $count = 0;
	my $finalAddrList = '';
	my $configEmailAddress = $_[0];

	if ($configEmailAddress ne "") {
		my @addrList = ();
		if ($configEmailAddress =~ /\,|\;/) {
			@addrList = split(/\,|\;/, $configEmailAddress);
		} else {
			push(@addrList, $configEmailAddress);
		}

		foreach my $addr (@addrList) {
			Chomp(\$addr);
			if ($addr eq "") {
				next;
			}

			if (isValidEmailAddress($addr)) {
				$count++;
				$finalAddrList .= "$addr,";
			} else {
				#print $Locale::strings{'failed_to_send_mail'}.$Locale::strings{'invalid_email_addresses_are_'}." $addr $lineFeed";
				display(['failed_to_send_mail','invalid_email_addresses_are_'," $addr $lineFeed"]);
				traceLog($LS{'failed_to_send_mail'}.$LS{'invalid_email_addresses_are_'}." $addr");
				if (open ERRORFILE, ">>", $AppConfig::errorFilePath) {
					chmod $AppConfig::filePermission, $AppConfig::errorFilePath;
					autoflush ERRORFILE;

					print ERRORFILE $LS{'failed_to_send_mail'}.$LS{'invalid_email_addresses_are_'}." $addr $lineFeed";
					close ERRORFILE;
				}
			}
		}

		if ($count > 0) {
			if (substr($finalAddrList, -1) eq ",") {
				$finalAddrList = substr($finalAddrList, 0, -1);
			}
			return $finalAddrList;
		}
		else {
			traceLog($LS{'failed_to_send_mail'}.$LS{'no_emails_configured'});
			return "NULL";
		}
	}
}

#****************************************************************************************************
# Subroutine			: getFolderDetail
# Objective				: This function will get properties of folder.
# Added By				: Senthil Pandian
#*****************************************************************************************************
sub getFolderDetail {
	my $remoteFolder  = $_[0];
	my $jobType 	  = $_[1]; #manual_archive

	my $filesCount = 0;
	my $jobRunningDir  = getUsersInternalDirPath($jobType);
	# my $isDedup  	   = getUserConfiguration('DEDUP');
	# my $backupLocation = getUserConfiguration('BACKUPLOCATION');

	my $itemStatusUTFpath = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
	createUTF8File(['PROPERTIES',$itemStatusUTFpath],
				$evsErrorFile,
				$remoteFolder
				) or retreat('failed_to_create_utf8_file');

	my @responseData = runEVS('item',1);
	if (-s $evsErrorFile > 0) {
		checkExitError($evsErrorFile,$jobType.'_archive');
	}
	unlink($evsErrorFile);
	if (defined($responseData[1]->{'files_count'})){
		$filesCount = $responseData[1]->{'files_count'};
	}
	return $filesCount;
}

#*****************************************************************************************************
# Subroutine			: getHumanReadableSizes
# Objective				: Return file size in human readable format
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getHumanReadableSizes {
	my ($sizeInBytes) = @_;

	return 0 unless($sizeInBytes);

	unless($sizeInBytes =~ /^\d+|\.$/){
		traceLog("Not a integer: $sizeInBytes");
		return $sizeInBytes;
	}
	if ($sizeInBytes > 1073741824) {       #GiB: 1024 GiB
		return sprintf("%.2f GB", $sizeInBytes / 1073741824);
	}
	elsif ($sizeInBytes > 1048576) {          #   MiB: 1024 KiB
		return sprintf("%.2f MB", $sizeInBytes / 1048576);
	}
	elsif ($sizeInBytes > 1024) {             #   KiB: 1024 B
		return sprintf("%.2f KB", $sizeInBytes / 1024);
	}
	return "$sizeInBytes byte" . ($sizeInBytes == 1 ? "" : "s");
}

#*****************************************************************************************************
# Subroutine			: getIDPWDFile
# Objective				: Build path to IDPWD file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPWDFile {
	return (getUserProfilePath() . "/$AppConfig::idpwdFile");
}

#*****************************************************************************************************
# Subroutine			: getIDENPWDFile
# Objective				: Build path to IDENPWD file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDENPWDFile {
	return (getUserProfilePath() . "/$AppConfig::idenpwdFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPVTFile
# Objective				: Build path to IDPVT file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPVTFile {
	return (getUserProfilePath() . "/$AppConfig::idpvtFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPVTSCHFile
# Objective				: Build path to getIDPVTSCHFile file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getIDPVTSCHFile {
	return (getUserProfilePath() . "/$AppConfig::idpvtschFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPWDSCHFile
# Objective				: Build path to IDPWDSCH file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPWDSCHFile {
	return (getUserProfilePath() . "/$AppConfig::idpwdschFile");
}

#*****************************************************************************************************
# Subroutine			: getLogsList
# Objective				: This subroutine gathers the list of log files
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getLogsList {
	my %timestampStatus = ();
	my @tempLogFiles;
	my $currentLogFile ='';
	my $logDir = $_[0];

	if (-d $logDir) {
		my $tempLogFilesCmd = "ls '$logDir'";
		@tempLogFiles = `$tempLogFilesCmd`;
		%timestampStatus = map {m/(\d+)_([A-Za-z*\_]+)/} @tempLogFiles;
	}

	return %timestampStatus;
}

#*****************************************************************************************************
# Subroutine			: getValidateRestoreFromFile
# Objective				: Build path to validateRestoreFromFile file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getValidateRestoreFromFile {
	return (getUserProfilePath() . "/$AppConfig::validateRestoreFromFile");
}

#*****************************************************************************************************
# Subroutine			: machineHardwareName
# Objective				: Return $machineHardwareName
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getMachineHardwareName {
	return $machineHardwareName;
}

#*****************************************************************************************************
# Subroutine			: getIPAddr
# Objective				: Find the ip address of this machine
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIPAddr {
	return $mipa if ($mipa);

	my $cmd;
	my $ifConfigPathCmd = updateLocaleCmd('which ifconfig 2>/dev/null');
	my $ifConfigPath = `$ifConfigPathCmd`;
	$mipa = '0.0.0.0';
	my $result = '';
	chomp($ifConfigPath);
	if (-f '/sbin/ip') {
		my $ipCmd = updateLocaleCmd("/sbin/ip r | grep 'src'");
		my @ip = `$ipCmd`;
		@ip = split(' ', (split(' src ', $ip[0]))[1]);
		$mipa = $ip[0];
	}
	elsif ($ifConfigPath ne '') {
		my $ipCmd = updateLocaleCmd("ifconfig -a");
		my $ip = `$ipCmd`;
		if ($ip =~ m/\s*inet (?:addr:)?([\d.]+).*?cast/) {
			$mipa = qq($1);
		}
	}

	return $mipa;
}

#*****************************************************************************************************
# Subroutine			: getMachineUID
# Objective				: Find the mac address
# Added By				: Yogesh Kumar
# Modified By			: Vijay Vinoth, Senthil Pandian
#****************************************************************************************************/
sub getMachineUID {
	if (getUserConfiguration('MUID')) {
		$muid = getUserConfiguration('MUID');
	}
	elsif ((getUserConfiguration('DEDUP') eq 'on') and getUserConfiguration('BACKUPLOCATION')) {
		my $deviceID = (split('#', getUserConfiguration('BACKUPLOCATION')))[0];
		$deviceID =~ s/$AppConfig::deviceIDPrefix//g;
		$deviceID =~ s/$AppConfig::deviceIDSuffix//g;
		my @result = fetchAllDevices();
		#Added to consider the bucket type 'D' only
		my @devices;
		foreach (@result){
			next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
			push @devices, $_;
		}

		foreach(@devices) {
			next if (!defined($_->{'device_id'}) or ($deviceID ne $_->{'device_id'}));
			setUserConfiguration('MUID', $_->{'uid'});
			if (saveUserConfiguration(0, 1)) {
				$muid = $_->{'uid'};
			}
			last;
		}
	}

	unless($muid) {
		$muid  = parseMachineUID();
		$muid .= $AppConfig::deviceUIDsuffix;
		setUserConfiguration('MUID', $muid);
	}

	if (defined($_[0]) and $_[0] == 0) {
		$muid =~ s/$AppConfig::deviceUIDPrefix//;
	}
	elsif (!($muid =~ /^$AppConfig::deviceUIDPrefix/)) {
		$muid = ($AppConfig::deviceUIDPrefix . $muid);
	}

	return $muid;
}

#*********************************************************************************************************
# Subroutine		: getAndSetMountedPath
# Objective			: This function will set & return mounted path
# Added By			: Senthil Pandian
# Modified By		: Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#*********************************************************************************************************/
sub getAndSetMountedPath {
	my @linkDataList = ();
	my ($userInput,$choice) = (0) x 2;
	my $maxNumRetryAttempts = 3;
	my ($localBackupLocation,$errStr) = ('') x 2;

	#Verifying existing mount point for scheduled backup
	my $silentBackupFlag = $_[0] || 0;
	if ($silentBackupFlag) {
		$localBackupLocation = getUserConfiguration('LOCALMOUNTPOINT');
		chomp($localBackupLocation);
		if ($localBackupLocation ne '') {
			if (!-e "$localBackupLocation") {
				$errStr = 'mount_point_not_exist';
				return (0,$errStr);
			}
			elsif (!-w "$localBackupLocation") {
				$errStr = 'mount_point_doesnt_have_permission';
				return (0,$errStr);
			}
			return (1,$localBackupLocation);
		} else {
			$errStr = 'unable_to_find_mount_point';
			return (0,$errStr);
		}
	}

	$localBackupLocation = getUserConfiguration('LOCALMOUNTPOINT');
    my $invalidMountPoint = 0;
	chomp($localBackupLocation);
	if ($localBackupLocation ne '') {
		if (!-d $localBackupLocation or getFileFolderPermissionMode($localBackupLocation) ne 'Writeable'){
			# $localBackupLocation ='';
            $invalidMountPoint   = 1;
		}
	}

	if ($localBackupLocation ne '' and !$invalidMountPoint){
		display(['your_previous_mount_point',"'$localBackupLocation'.",' ', 'do_you_really_want_to_edit_(_y_n_)', '?']);

		my $msg = $LS{'enter_your_choice'};
		my $loginConfirmation = getAndValidate($msg, "YN_choice", 1);
		if (lc($loginConfirmation) eq 'n'){
			goto USEEXISTING;
		}
	} else {
        if($invalidMountPoint) {
            display(['mount_point', " '$localBackupLocation' is invalid. ", 'do_you_want_enter_mount_point']);
        } else {    
            display(['unable_to_find_mount_point', 'do_you_want_enter_mount_point']);
        }
        
		my $msg = $LS{'enter_your_choice'};
		my $loginConfirmation = getAndValidate($msg, "YN_choice", 1);
		if (lc($loginConfirmation) eq 'n'){
			# display(["\n",'exit',"\n"]);
			cancelProcess();
		}
	}

	display('loading_mount_points');
	my $mountedDevices = getMountPoints();
	#my %mountedPath = ();
	if (scalar(keys %{$mountedDevices})>0){
		display(['select_mount_point',"\n"]);
		my @mountPointcolumnNames = (['S.No','Mount Point','Permissions'],[8,30,15]);
		my $tableHeader = getTableHeader(@mountPointcolumnNames);
		my ($tableData,$columnIndex,$serialNumber,$index) = ('',1,1,0);

		foreach my $mountPath (keys %{$mountedDevices}){
			$columnIndex = 1;

			my $mountDevicePath     = $mountPath;
			my $mountDevicePathPerm = $mountedDevices->{$mountPath}{'mode'};
			$index++;
			$tableData .= $serialNumber;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[0] - length($serialNumber));

			$mountDevicePath = trimData($mountDevicePath,$mountPointcolumnNames[1]->[$columnIndex]) if ($columnIndex == 1 or $columnIndex == 3);
			$tableData .= $mountDevicePath;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[$columnIndex] - length($mountDevicePath));
			$tableData .= $mountDevicePathPerm;
			$columnIndex++;
			$tableData .= "\n";
			$serialNumber += 1;
			push (@linkDataList,$mountPath);
		}
		if ($tableData ne ''){
			display($tableHeader.$tableData);
		}
	} else {
		display('unable_to_find_mount_point');
		#print 'Please check whether the external disk mounted properly or not.';
	}

	if (scalar(@linkDataList)>0){
		my $userChoice = getValidMountPointChoice('Enter the S.No. to select mount point. Press \'q\' in case your mount point is not listed above: ',@linkDataList);
		if ($userChoice eq 'q' or $userChoice eq 'Q'){
			@linkDataList = ();
		}
		elsif ($userChoice ne '') {
			$localBackupLocation = $linkDataList[$userChoice - 1];
		}
	}

	if (scalar(@linkDataList)<=0) {
		while ($maxNumRetryAttempts){
			display(["\n",'enter_mount_point'],0);
			$localBackupLocation = <STDIN>;
			Chomp(\$localBackupLocation);chomp($localBackupLocation);
			if (!-e "$localBackupLocation"){
				display(['mount_point_not_exist']);
			}
			elsif (!-w "$localBackupLocation") {
				display(['mount_point_doesnt_have_permission']);
			}
			else {
				my $tempLoc = $localBackupLocation;
				$tempLoc =~ s/^[\/]+|^[.]+//;
				if (!$tempLoc) {
					display(['invalid_mount_point']);
				} else {
					last;
				}
			}
			$maxNumRetryAttempts -= 1;
		}
		if ($maxNumRetryAttempts == 0){
			display(["\n", 'max_retry',"\n\n"]);
			cancelProcess();
		}
	}
	my $str = $LS{'your_selected_mount_point'};
	$str =~ s/<ARG>/$localBackupLocation/;
	display("$str\n");
	if ($localBackupLocation =~ /[\/]$/){
		chop($localBackupLocation);
	}

	setUserConfiguration('LOCALMOUNTPOINT', $localBackupLocation);
	saveUserConfiguration() or retreat('failed_to_save_user_configuration');
	# reset the local backup db backup status
	my $expresspath = getJobsPath('localbackup');
	resetBackedupStatus($expresspath) if(!$_[1]);
USEEXISTING:
	return (1,$localBackupLocation);
}

#***********************************************************************
# Subroutine Name         : getPdata
# Objective               : Get Pdata in order to send Mail notification
# Added By                : Dhritikana.
#***********************************************************************
sub getPdata
{
	my $udata     = $_[0];
	my $pdata     = '';
	my $enPwdPath = getIDENPWDFile();
	chmod $AppConfig::filePermission, $enPwdPath;
	if (!open FILE, "<", "$enPwdPath"){
		traceLog($lineFeed.$LS{'failed_to_open_file'}.$enPwdPath." failed reason:$!");
		return $pdata;
	}
	my $enPdata = <FILE>; chomp($enPdata);
	close(FILE);

	my $len = length($udata);
	my ($a, $b) = split(/\_/, $enPdata, 2);
	$pdata = unpack( "u", "$b");
	if ($len eq $a) {
		return $pdata;
	}
}

#*****************************************************************************************************
# Subroutine			: getPerlBinaryPath
# Objective				: Build path of Perl binary
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getPerlBinaryPath {
	#Assigning Perl path
	my $perlPathCmd = updateLocaleCmd('which perl');
	my $perlPath = `$perlPathCmd`;
	Chomp(\$perlPath);
	if ($perlPath eq ''){
		$perlPath = '/usr/local/bin/perl';
	}
	return $perlPath;
}

#*************************************************************************************************
# Subroutine			: getCRONScheduleTime
# Objective				: This subroutine helps to find cron ran time using crontab json entry
# Added By				: Sabin Cheruvattil
#*************************************************************************************************/
sub getCRONScheduleTime {
	loadCrontab();
	my ($mcuser, $idriveuser, $job, $jobset) = ($_[0], $_[1], $_[2], $_[3]);
	my $crontab = getCrontab();

	if (defined($crontab->{$mcuser}) && defined($crontab->{$mcuser}{$idriveuser}) && defined($crontab->{$mcuser}{$idriveuser}{$job}) &&
	defined($crontab->{$mcuser}{$idriveuser}{$job}{$jobset})) {
		# my @now = (localtime)[1,2,3,4,6,5];
		# my $timestring = sprintf('%.2d', ($now[3] + 1)) . '-' . sprintf('%.2d', $now[2]) . '-' . ($now[5] + 1900);
		# $timestring .= ' ' . sprintf('%.2d', $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'h'}) . ':' .
							 # sprintf('%.2d', $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'m'});

		my @now 		= localtime;
		$now[0] 		= 0;
		$now[1] 		= $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'m'};
		$now[2] 		= $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'h'} if ($crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'h'} =~ /\d+/);
		my $timestring	= localtime(mktime(@now));

		return $timestring;
	}

	return '';
}

#*************************************************************************************************
# Subroutine			: getOSBuild
# Objective				: This subroutine helps to find OS build and release version
# Added By				: Sabin Cheruvattil
# Modified By           : Senthil Pandian
#*************************************************************************************************/
sub getOSBuild {
	my ($os, $build) = ('', 0);

	# check OS release file
	if (-f '/etc/os-release') {
		my $osresCmd = updateLocaleCmd('cat /etc/os-release');
		my $osres = `$osresCmd`;
		Chomp(\$osres);

        $osres  = "\n".$osres;
		$os		= $1 if ($osres =~ /\nID=(.*?)\n/s);
        $os		= $1 if ($os eq '' and $osres =~ /\nID=(.*?)$/s);
		$os		=~ s/\"//gs;

		my $hostnameCmd = updateLocaleCmd('uname -a');
		$os		= 'debian' if (index(lc(`$hostnameCmd`), 'debian') != -1);

		$build	= $1 if ($osres =~ /VERSION_ID="(.*?)"\n/s);
		$build	= $1 if (($osres =~ /VERSION_ID=(.*?)\n/s) && $build == 0);
		$build = 12 if ($os and ($os eq "debian") and ($osres =~ /VERSION_CODENAME=(.*?bookworm.*?)\n/s));

		if (($build eq '' || $build == 0) && -f '/etc/gentoo-release') {
			$osres = getFileContents('/etc/gentoo-release');
			Chomp(\$osres);
			$build = qq($2.$3) if ($osres =~ /(.*?)(\d*)\.(\d*)(.*?)/is);
		}

		if (-f '/etc/issue') {
			my $osresIssueCmd = updateLocaleCmd('cat /etc/issue');
			$osres = `$osresIssueCmd`;
			Chomp(\$osres);

			$os = 'opensuse' if (index(lc($osres), 'opensuse') != -1 || $os =~ /opensuse/);
		}

		return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
	}

	# Check lsb_release is avaialble or not
	my $isLsbReleaseCmd = updateLocaleCmd('which lsb_release 2>/dev/null');
	my $isLsbRelease = `$isLsbReleaseCmd`; #Added for FreeBSD: Senthil
	if ($isLsbRelease) {
		my $lsbresCmd = updateLocaleCmd('lsb_release -a 2> /dev/null');
		my $lsbres	= `$lsbresCmd`;
		Chomp(\$lsbres);
		if ($lsbres ne '') {
			$os		= $2 if ($lsbres =~ /Distributor ID:(\s*)(.*?)(\s*)\n/s);
			$build	= $2 if ($lsbres =~ /Release:(\s*)(.*?)(\s*)\n/s);
			my @buildvers = split('\.', $build);
			$build	= qq($buildvers[0].$buildvers[1]) if (scalar(@buildvers) > 2);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $isHostnamectlCmd = updateLocaleCmd('which hostnamectl 2>/dev/null');
	my $isHostnamectl = `$isHostnamectlCmd`; #Added for FreeBSD: Senthil
	if ($isHostnamectl) {
		my $hostctlstatCmd = updateLocaleCmd('hostnamectl status');
		my $hostctlstat = `$hostctlstatCmd`;
		my $unameCmd = updateLocaleCmd('uname -n');
		my $uname		= `$unameCmd`;
		Chomp(\$hostctlstat); Chomp(\$uname);
		if ($hostctlstat ne '' && $uname ne '') {
			$os		= $uname;
			$build	= $3 if ($hostctlstat =~ /Operating System:(\s*)$os(\s*)(.*?)(\s*)(.*?)\n/si);

			if(!$build and $hostctlstat =~ /debian/i and $hostctlstat =~ /buster/i) {
				$os = 'debian';
				$build = 10;
			}

			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $isSysctlCmd = updateLocaleCmd('which sysctl 2>/dev/null');
	my $isSysctl = `$isSysctlCmd`;
	if ($isSysctl) {
		my $sysctlosCmd = updateLocaleCmd('sysctl -n kern.ostype 2>/dev/null');
		my $sysctlos = `$sysctlosCmd`;
		my $sysctlbuildCmd = updateLocaleCmd('sysctl -n kern.osrelease 2>/dev/null');
		my $sysctlbuild = `$sysctlbuildCmd`;
		chomp($sysctlos); chomp($sysctlbuild);
		if ($sysctlos ne '' && $sysctlbuild ne '') {
			$os		= $sysctlos;
			$build	= $1 if ($sysctlbuild =~ /(.*?)-(.*?)/i);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $hostnameCmd = updateLocaleCmd('uname -n');
	if (-f '/etc/issue' && index(`$hostnameCmd`, 'debian') != -1) {
		my $osresDetailCmd = updateLocaleCmd('cat /etc/issue');
		my $osres = `$osresDetailCmd`;
		Chomp(\$osres);

		$os			= 'debian';
		my @dbuild	= split('\ ', $osres);
		$build		= $dbuild[2];
		return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
	}

	if (-f '/etc/issue') {
		my $osresCmd = updateLocaleCmd('cat /etc/issue');
		my $osres = `$osresCmd`;
		$os			= 'fedora' if (index($osres, 'Fedora') != -1);
		if ($os eq 'fedora') {
			my $osresCmd = updateLocaleCmd('cat /etc/fedora-release');
			$osres	= `$osresCmd`;
			Chomp(\$osres);
			$build	= $1 if ($osres =~ /fedora release\s(.*)\s/si);

			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	return {'os' => $os, 'build' => $build};
}

#*************************************************************************************************
# Subroutine			: getOSBuild
# Objective				: This subroutine helps to find OS build and release version
# Added By				: Sabin Cheruvattil
# Modified By           : Senthil Pandian
#*************************************************************************************************/
#We may need to use this function later
=beg
sub getOSBuild {
	my ($os, $build, $osDetail) = ('', '', {});
    my $osVersionFile = getCatfile(getServicePath(), $AppConfig::osVersionCache);
    my %osHash = ('os' => $os, 'build' => $build);

    if(!defined($_[0]) and -f $osVersionFile) {
        $osDetail = JSON::from_json(getFileContents($osVersionFile));
        if(defined($osDetail->{'os'}) and $osDetail->{'os'} ne '' and defined($osDetail->{'build'}) and $osDetail->{'build'} ne '') {
            return $osDetail;
        }
    }

    $osDetail = findOSBuild();
    if(defined($_[0]) and (!defined($osDetail->{'os'}) or $osDetail->{'os'} eq '')) {
        $os = getOSName();
        $os = lc($os);
    }
    elsif(defined($osDetail->{'os'}) and $osDetail->{'os'} ne '') {
        $os = lc($osDetail->{'os'});
    }

    if(defined($_[0]) and (!defined($osDetail->{'build'}) or $osDetail->{'build'} eq '')) {
        $build = getOSBuildVersion();
    }
    elsif(defined($osDetail->{'build'})) {
        $build = $osDetail->{'build'};
    }

    if($os eq '' or $build eq '') {
        retreat(['unable_to_fetch_os_details', ' ', 'please_reconfig_account_and_retry']);
    }

    %osHash = ('os' => $os, 'build' => $build);
    if(-d getServicePath() and defined($_[0])) {
        fileWrite($osVersionFile, JSON::to_json(\%osHash));
        chmod $AppConfig::filePermission, $osVersionFile;
    }

	return \%osHash;
}
=cut

#*************************************************************************************************
# Subroutine			: getOSName
# Objective				: This subroutine to get OS name from user.
# Added By				: Senthil Pandian
#*************************************************************************************************/
sub getOSName {
    display(["\n",'unable_to_find_linux_distribution_name'],1);
    displayMainMenu(\%AppConfig::supportedOSList,'select_your_linux_distribution');
    my $userMenuChoice 	= getUserMenuChoice(scalar keys %AppConfig::supportedOSList);
    display(["\n",'your_linux_distribution_name',"'$AppConfig::supportedOSList{$userMenuChoice}'."],1);
    return $AppConfig::supportedOSList{$userMenuChoice};
}

#*************************************************************************************************
# Subroutine			: getOSBuildVersion
# Objective				: This subroutine to get OS build version from user.
# Added By				: Senthil Pandian
#*************************************************************************************************/
sub getOSBuildVersion {
    display(["\n",'unable_to_find_linux_distribution_version'],1);
    my $build = getAndValidate(['enter_linux_distribution_version', ': '], "version", 1);
    display(["\n",'your_linux_distribution_version',"'$build'."],1);
    return $build;
}

#*************************************************************************************************
# Subroutine			: findOSBuild
# Objective				: This subroutine helps to find OS build and release version
# Added By				: Sabin Cheruvattil
# Modified By           : Senthil Pandian
#*************************************************************************************************/
sub findOSBuild {
	my ($os, $build) = ('', 0);

	# check OS release file
	if (-f '/etc/os-release') {
		my $osresCmd = updateLocaleCmd('cat /etc/os-release');
		my $osres = `$osresCmd`;
		Chomp(\$osres);

        $osres  = "\n".$osres;
		$os		= $1 if ($osres =~ /\nID=(.*?)\n/s);
        $os		= $1 if ($os eq '' and $osres =~ /\nID=(.*?)$/s);
		$os		=~ s/\"//gs;

		my $hostnameCmd = updateLocaleCmd('uname -a');
		$os		= 'debian' if (index(lc(`$hostnameCmd`), 'debian') != -1);

		$build	= $1 if ($osres =~ /VERSION_ID="(.*?)"\n/s);
		$build	= $1 if (($osres =~ /VERSION_ID=(.*?)\n/s) && $build == 0);

		if (($build eq '' || $build == 0) && -f '/etc/gentoo-release') {
			$osres = getFileContents('/etc/gentoo-release');
			Chomp(\$osres);
			$build = qq($2.$3) if ($osres =~ /(.*?)(\d*)\.(\d*)(.*?)/is);
		}

		if (-f '/etc/issue') {
			my $osresIssueCmd = updateLocaleCmd('cat /etc/issue');
			$osres = `$osresIssueCmd`;
			Chomp(\$osres);

			$os = 'opensuse' if (index(lc($osres), 'opensuse') != -1 || $os =~ /opensuse/);
		}

		return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
	}

	# Check lsb_release is avaialble or not
	my $isLsbReleaseCmd = updateLocaleCmd('which lsb_release 2>/dev/null');
	my $isLsbRelease = `$isLsbReleaseCmd`; #Added for FreeBSD: Senthil
	if ($isLsbRelease) {
		my $lsbresCmd = updateLocaleCmd('lsb_release -a 2> /dev/null');
		my $lsbres	= `$lsbresCmd`;
		Chomp(\$lsbres);
		if ($lsbres ne '') {
			$os		= $2 if ($lsbres =~ /Distributor ID:(\s*)(.*?)(\s*)\n/s);
			$build	= $2 if ($lsbres =~ /Release:(\s*)(.*?)(\s*)\n/s);
			my @buildvers = split('\.', $build);
			$build	= qq($buildvers[0].$buildvers[1]) if (scalar(@buildvers) > 2);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $isHostnamectlCmd = updateLocaleCmd('which hostnamectl 2>/dev/null');
	my $isHostnamectl = `$isHostnamectlCmd`; #Added for FreeBSD: Senthil
	if ($isHostnamectl) {
		my $hostctlstatCmd = updateLocaleCmd('hostnamectl status');
		my $hostctlstat = `$hostctlstatCmd`;
		my $unameCmd = updateLocaleCmd('uname -n');
		my $uname		= `$unameCmd`;
		Chomp(\$hostctlstat); Chomp(\$uname);
		if ($hostctlstat ne '' && $uname ne '') {
			$os		= $uname;
			$build	= $3 if ($hostctlstat =~ /Operating System:(\s*)$os(\s*)(.*?)(\s*)(.*?)\n/si);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $isSysctlCmd = updateLocaleCmd('which sysctl 2>/dev/null');
	my $isSysctl = `$isSysctlCmd`;
	if ($isSysctl) {
		my $sysctlosCmd = updateLocaleCmd('sysctl -n kern.ostype 2>/dev/null');
		my $sysctlos = `$sysctlosCmd`;
		my $sysctlbuildCmd = updateLocaleCmd('sysctl -n kern.osrelease 2>/dev/null');
		my $sysctlbuild = `$sysctlbuildCmd`;
		chomp($sysctlos); chomp($sysctlbuild);
		if ($sysctlos ne '' && $sysctlbuild ne '') {
			$os		= $sysctlos;
			$build	= $1 if ($sysctlbuild =~ /(.*?)-(.*?)/i);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $hostnameCmd = updateLocaleCmd('uname -n');
	if (-f '/etc/issue' && index(`$hostnameCmd`, 'debian') != -1) {
		my $osresDetailCmd = updateLocaleCmd('cat /etc/issue');
		my $osres = `$osresDetailCmd`;
		Chomp(\$osres);

		$os			= 'debian';
		my @dbuild	= split('\ ', $osres);
		$build		= $dbuild[2];
		return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
	}

	if (-f '/etc/issue') {
		my $osresCmd = updateLocaleCmd('cat /etc/issue');
		my $osres = `$osresCmd`;
		$os			= 'fedora' if (index($osres, 'Fedora') != -1);
		if ($os eq 'fedora') {
			my $osresCmd = updateLocaleCmd('cat /etc/fedora-release');
			$osres	= `$osresCmd`;
			Chomp(\$osres);
			$build	= $1 if ($osres =~ /fedora release\s(.*)\s/si);

			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		} elsif($os =~ 'arch') {
			return {'os' => 'archlinux', 'build' => 1};
		}
	}

	return {'os' => $os, 'build' => $build};
}

#*****************************************************************************************************
# Subroutine			: getCRONSetupTemplate
# Objective				: This is get cron setup template
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCRONSetupTemplate {
	my $opconf		= {};
	my $os 			= getOSBuild();
	my $oscronconfs = $AppConfig::cronLaunchCodes{$os->{'os'}};

	foreach my $opkey (keys %{$oscronconfs}) {
		my @opver	= split('-', $opkey);
		if (($opver[0] eq 'btw' && (split('_', $opver[1]))[0] <= $os->{'build'} && $os->{'build'} <= (split('_', $opver[1]))[1]) ||
			($opver[0] eq 'gt' && $os->{'build'} > $opver[1]) || ($opver[0] eq 'lt' && $os->{'build'} < $opver[1]) ||
			($opver[0] eq 'gte' && $os->{'build'} >= $opver[1]) || ($opver[0] eq 'lte' && $os->{'build'} <= $opver[1])) {
			$opconf = $oscronconfs->{$opkey};
			last;
		}
	}

	if($opconf->{'req-serv'}) {
		my $reqcmd	= "which $opconf->{'req-serv'} 2>/dev/null";
		my $reqres	= `$reqcmd`;
		Chomp(\$reqres);
		
		$opconf = $oscronconfs->{$opconf->{'base-conf-key'}} if(!$reqres && $opconf->{'base-conf-key'} && defined($oscronconfs->{$opconf->{'base-conf-key'}}));
	}

	if(grep(/$os->{'os'}/, ('centos', 'fedora', 'rocky')) and $opconf->{'serv-mod'} eq 'sd') {
	# if(grep(/$os->{'os'}/, ('fedora')) and $opconf->{'serv-mod'} eq 'sd') {
		my $slenabled = 0;
		# check security active security policy
		my $slpolutil = `which sestatus 2>/dev/null`;
		Chomp(\$slpolutil);

		if($slpolutil) {
			my $slpolicy = `$slpolutil | grep -i "current mode" | awk '{print \$3}' 2>/dev/null`;
			Chomp(\$slpolicy);

			$slenabled = 1 if($slpolicy =~ /enforcing/i);
		} else {
			# /etc/selinux/config read and check
			my $slconf = `cat /etc/selinux/config 2>/dev/null`;
			Chomp(\$slconf);

			if($slconf =~ /\nSELINUX=(.*?)\n/si) {
				$slenabled = 1 if($1 and lc($1) =~ /enforcing/i);
			}
		}

		if($slenabled) {
			$oscronconfs = $AppConfig::cronLaunchCodes{'selinux'};
			$opconf = $oscronconfs->{((keys(%{$oscronconfs}))[0])};
		}
	}

	return $opconf;
}

#*****************************************************************************************************
# Subroutine	: getFallBackCRONRebootEntry
# In Param		: UNDEF
# Out Param		: CRONTAB entry for reboot handling | String
# Objective		: IDrive cron restart entry for fallback cron | goes to crontab
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getFallBackCRONRebootEntry {
	my $opconf	= getCRONSetupTemplate();
	if (%{$opconf} && $opconf->{'startcmd'} ne '') {
		return "\@reboot sleep 10; $opconf->{'startcmd'}";
	}

	return '';
}

#*****************************************************************************************************
# Subroutine	: getOldFallBackCRONRebootEntry
# In Param		: UNDEF
# Out Param		: CRONTAB entry for reboot handling | String
# Objective		: Older IDrive cron restart entry for fallback cron | goes to crontab
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getOldFallBackCRONRebootEntry {
	return "\@reboot $AppConfig::perlBin " . getECatfile($AppConfig::cronLinkPath);
}

#*****************************************************************************************************
# Subroutine/Function   : getUsernameList
# In Param    : email address, password(Optional)
# Out Param   : username, password(Optional)
# Objective	  : This is to get IDrive/IBackup username list associated with email address
# Added By	  : Senthil Pandian
# Modified By : Yogesh Kumar
#****************************************************************************************************/
sub getUsernameList {
	my $uname   = $_[0];
	my $upasswd = $_[1];

	my $res = makeRequest(2, [$uname]);

	if(defined($res->{DATA})) {
		chomp($res->{DATA});
		# traceLog("getUsernameList Resp for '$uname' : ".$res->{DATA});
		$res->{'DATA'} =~ s/\n/ /g;
		my @splitUserList = split(" ",$res->{DATA});
		my @tempUserList = ();
		foreach my $username (@splitUserList){
			if ($username =~ s/:Active//i) {
				$username = (split(":",$username))[0];
				chomp($username);
				push @tempUserList, $username;
			}
		}
		@splitUserList = @tempUserList;

		if(scalar(@splitUserList) > 1) {
			my @userList = sort @splitUserList; #Ascending sort
			#my @userList = sort {$b cmp $a} @splitUserList; #Descending sort
			display(["\n",'multiple_acc_are_associated_with_email']);
			my @usernameColumnNames = (['S.No','Username'],[8,9]);
			my $tableHeader = getTableHeader(@usernameColumnNames);
			my ($tableData,$columnIndex,$serialNumber) = ('',1,1);

			foreach my $username (@userList){
				$columnIndex = 1;
				$tableData .= $serialNumber;
				$tableData .= (' ') x ($usernameColumnNames[1]->[0] - length($serialNumber));
				$tableData .= $username;
				$columnIndex++;
				$tableData .= "\n";
				$serialNumber += 1;
			}
			if ($tableData ne ''){
				display($tableHeader.$tableData);
			}

			my $userChoice= getUserMenuChoice(scalar(@userList));
			$userChoice = $userChoice-1;
			$uname = $userList[$userChoice] if ($userChoice >= 0);

			# TODO: remove
			#$upasswd = getAndValidate(['enter', " ", $AppConfig::appType, " ", 'password for', " '$uname'", ': '], "password", 0);
			#display('verifying_your_account_info', 1);
		}
		elsif(defined($splitUserList[0])) {
			$uname = $splitUserList[0];
		}
	}
	setUsername($uname); # Re-assign username
	# TODO: remove
	#return ($uname,$upasswd);
	return $uname;
}

#*************************************************************************************************
#Subroutine Name               : getPSoption
#Objective                     : This subroutine will return the machine based ps option.
#Added By                      : Senthil Pandian
#*************************************************************************************************/
sub getPSoption{
	my $psOption = "-elf";
	my $machineInfoCmd = updateLocaleCmd('uname -a');
	$machineInfo = `$machineInfoCmd`;
	chomp($machineInfo);
	if ($machineInfo =~ /freebsd/i){
		$psOption = "-auxww";
	}
	return $psOption;
}

#*****************************************************************************************************
# Subroutine			: getRunningJobs
# Objective				: Check if pid file exists & file is locked, then return it all
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub getRunningJobs {
	my @availableJobs;
	my $jobType  = $_[1] || 0; # 0 - all, 1 - manual, 2 - scheduled
	my $userProfilePath = getUserProfilePath();

	if(defined($_[2]) and defined($_[3])) {
		$userProfilePath = getCatfile($servicePath, $AppConfig::userProfilePath, $_[2], $_[3]);
	}

	if (defined($_[0]) and reftype(\$_[0]) eq 'REF') {
		@availableJobs = @{$_[0]};
	}
	elsif (defined($_[0]) and reftype(\$_[0]) eq 'SCALAR') {
		@availableJobs = $_[0];
	}
	elsif (defined($_[0]) and $_[0] ne 'allOp') {
		unless (exists $AppConfig::availableJobsSchema{$_[0]}) {
			push @availableJobs, lc($_[0]);
		}
		else {
			push @availableJobs, $_[0];
		}
	}
	else {
		@availableJobs = keys %AppConfig::availableJobsSchema;
	}
	my %runningJobs;
	my ($ps, $psimmd, $pscdp, $pid, $cmd);
	foreach (@availableJobs) {
		my @p = split '_', $_;

		unless (exists $AppConfig::availableJobsSchema{$_}) {
			retreat(['undefined_job_name', ': ', $_]);
		}

		my $pidFile = getCatfile($userProfilePath, $AppConfig::userProfilePaths{$_}, 'pid.txt');
		if (-f $pidFile) {
			if (!isFileLocked($pidFile)) {
				unlink($pidFile);
				next;
			}

			if ($jobType) {
				$pid = getFileContents($pidFile);
				my $psCmd = updateLocaleCmd("ps -w $pid | grep '.pl SCHEDULED $username'");
				$ps = `$psCmd`;
				my $psimmdCmd = updateLocaleCmd("ps -w $pid | grep '.pl immediate $username'");
				$psimmd = `$psimmdCmd`;
				my $pscdpcmd = updateLocaleCmd("ps -w $pid | grep '.pl CDP $username'");
				$pscdp = `$pscdpcmd`;
				next if (($ps ne '' || $psimmd ne '' || $pscdp ne '') and $jobType == 1);
				next if (($ps eq '' && $psimmd eq '') and $jobType == 2);
			}

			$runningJobs{$_} = $pidFile;
		}
	}
	return %runningJobs;
}

#*****************************************************************************************************
# Subroutine			: getServicePath
# Objective				: Build path to service location file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getServicePath {
	return $servicePath;
}

#*****************************************************************************************************
# Subroutine			: setServicePath
# Objective				: Assign service path
# Added By				: Deepak Chaurasia
#****************************************************************************************************/
sub setServicePath {
	$servicePath = $_[0];
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getServerAddressFile
# Objective				: Build path to serverAddress file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getServerAddressFile {
	return (getUserProfilePath() . "/$AppConfig::serverAddressFile");
}

#*****************************************************************************************************
# Subroutine			: getAppPath
# Objective				: This subroutine helps to get scripts path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getAppPath {
	loadAppPath() unless $appPath;
	return $appPath;
}

#*****************************************************************************************************
# Subroutine			: getUserHomePath
# Objective				: Find and return the parent directory name
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUserHomePath {
	return $ENV{'HOME'};
}

#*****************************************************************************************************
# Subroutine			: getJobsPath
# Objective				: Build path to the given jobs path
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getJobsPath {
	unless (exists $AppConfig::availableJobsSchema{$_[0]}) {
		retreat(['job_name', $_[0], 'doesn\'t exists'], 1);
	}

	my $key = $_[1];

	$key = 'path' unless (defined $_[1]);

	my $jp = $AppConfig::availableJobsSchema{$_[0]}{$key};
	$jp =~ s/__SERVICEPATH__/getServicePath()/eg;
	$jp =~ s/__USERNAME__/getUsername()/eg;
	return $jp;
}

#*****************************************************************************************************
# Subroutine			: getUserChoice
# Objective				: Take the user input value and return
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUserChoice {
	my $echoBack = shift;
	$echoBack = 1 unless(defined($echoBack));
	my $input = '';

	unless ($AppConfig::callerEnv eq 'BACKGROUND') {
		system('stty', '-echo') unless ($echoBack);
		chomp($input = <STDIN>);
	}
	else {
		$input = 'BACKGROUND';
	}
	# added by anil on 30may2018 to replace spaces and tab in user input.
	$input =~ s/^[\s\t]+|[\s\t]+$//g;
	unless ($echoBack) {
		system('stty', 'echo');
		display('');
	}
	return $input;
}

#*****************************************************************************************************
# Subroutine		: getTotalSize
# Objective			: Take the user input value and return
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub getTotalSize {
	my $totalSizeFilePath = $_[0];
	my $totalSize = 0;
	if (-e $totalSizeFilePath and !-z _){
		open totalSizeFileHandler, "< $totalSizeFilePath";
		$totalSize = <totalSizeFileHandler>;
		close totalSizeFileHandler;
		chomp($totalSize);
	}

	return $totalSize;
}
#*****************************************************************************************************
# Subroutine			: getUserChoiceWithRetry
# Objective				: Take input and give retry option if required after validating the input
# Added By				: Anil Kumar
#****************************************************************************************************/
# sub getUserChoiceWithRetry {
	# my $minRange = 1;
	# my $maxRange = shift;
	# my $userChoice = '';
	# my $maxRetry = 4;
	# while ($maxRetry and $userChoice eq ''){
		# display(["\n", 'enter_your_choice'], 0);
		# my $input = getUserChoice();
		# unless(validateMenuChoice($input, $minRange, $maxRange)) {
			# display('invalid_option', 1);
			# $userChoice = '';
			# $maxRetry--;
		# } else {
			# $userChoice = $input;
		# }
	# }
	# if ($maxRetry == 0 and $userChoice eq ''){
		# retreat('your_max_attempt_reached');
	# }else{
		# return $userChoice;
	# }
# }

#*****************************************************************************************************
# Subroutine			: getLocaleString
# Objective				: Gets the actual string using string token
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getLocaleString {
	return '' unless($_[0]);
	return '__no_locale__' unless(exists($LS{$_[0]}));
	return $LS{$_[0]};
}

#*****************************************************************************************************
# Subroutine			: getUserProfilePath
# Objective				: Build path to user profile info
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserProfilePath {
	return getCatfile($servicePath, $AppConfig::userProfilePath, $AppConfig::mcUser, $username);
}

#****************************************************************************************************
# Subroutine    : getUsersInternalDirPath
# Objective		: Build path to user's internal directories
# Added By		: Sabin Cheruvattil
#****************************************************************************************************/
sub getUsersInternalDirPath {
	unless(exists $AppConfig::userProfilePaths{$_[0]}) {
		retreat(["$_[0]: ", 'does_not_exists']);
	}
	return getCatfile(getUserProfilePath(), $AppConfig::userProfilePaths{$_[0]});
}

#*****************************************************************************************************
# Subroutine			: getUserConfigurationFile
# Objective				: Build path to user configuration file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUserConfigurationFile {
	return getCatfile(getUserProfilePath(), $AppConfig::userConfigurationFile);
}

#*****************************************************************************************************
# Subroutine			: getUpdateVersionInfoFile
# Objective				: Build path to user .updateVersionInfo  file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUpdateVersionInfoFile {
	return getCatfile(getServicePath(), 'cache', $AppConfig::updateVersionInfo);
}

#*****************************************************************************************************
# Subroutine			: getUserConfiguration
# Objective				: Get user configured values
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserConfiguration {
	return %userConfiguration unless (defined $_[0]);
	my $field = (defined $_[1]) ? $_[1] : 'VALUE';

	if ($_[0] eq 'dashboard') {
		my %uc = ();
		map {
		$uc{$_} = $userConfiguration{$_}{$field} if ($AppConfig::userConfigurationSchema{$_}{'for_dashboard'})
		} keys %AppConfig::userConfigurationSchema;
		return %uc;
	}

	unless(exists $userConfiguration{$_[0]}) {
		#display(["WARNING: $_[0] ", 'is_not_set_in_user_configuration']);
		traceLog($_[0]." is not set in user configuration");
		return 0;
	}
	return $userConfiguration{$_[0]}{$field};
}

#*****************************************************************************************************
# Subroutine			: getUsername
# Objective				: Get username from $username
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUsername {
	return $username;
}

#*****************************************************************************************************
# Subroutine : getParentUsername
# In Param   :
# Out Param  : STRING
# Objective  : Read parent account name
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub getParentUsername {
	if (getUserConfiguration('ADDITIONALACCOUNT') eq 'true') {
		return getUserConfiguration('PARENTACCOUNT');
	}

	return $username;
}

#*****************************************************************************************************
# Subroutine			: getServerAddress
# Objective				: Get server address from $serverAddress
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getServerAddress {
	unless ($serverAddress) {
		(saveServerAddress(fetchServerAddress()) and loadServerAddress() ) or retreat('failed_to_getserver_addr');
	}
	return $serverAddress;
}

#*****************************************************************************************************
# Subroutine			: getTotalStorage
# Objective				: This subroutine return the total storage available for the user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getTotalStorage {
	return $totalStorage;
}

#*****************************************************************************************************
# Subroutine			: getStorageUsed
# Objective				: This subroutine return the total storage used by the user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStorageUsed {
	return $storageUsed;
}

#*****************************************************************************************************
# Subroutine			: getTableHeader
# Objective				: This is to process table header to display list of buckets
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getTableHeader{
	my $logTableHeader = ('=') x (eval(join '+', @{$_[1]}));
	$logTableHeader .= "\n";
	for (my $contentIndex = 0; $contentIndex < scalar(@{$_[0]}); $contentIndex++){
		$logTableHeader .= $_[0]->[$contentIndex];
		#(total_space - used_space by data) will be used to keep separation between 2 data.
		$logTableHeader .= (' ') x ($_[1]->[$contentIndex] - length($_[0]->[$contentIndex]));
	}
	$logTableHeader .= "\n";
	$logTableHeader .= ('=') x (eval(join '+', @{$_[1]}));
	$logTableHeader .= "\n";
	return $logTableHeader;
}

#*****************************************************************************************************
# Subroutine			: getUserFilePath
# Objective				: This subroutine constructs the edit file path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserFilePath {
	my $pathHolder = shift;
	$pathHolder =~ s/__SERVICEPATH__/getServicePath()/eg;
	$pathHolder =~ s/__USERNAME__/getUsername()/eg;
	return $pathHolder;
}

#*****************************************************************************************************
# Subroutine			: getUserMenuChoice
# Objective				: This subroutine helps to get the user's choices
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getUserMenuChoice {
	my($userMenuChoice, $maxChoice) = (0, shift);
	$userMenuChoice = getAndValidate(['enter_your_choice'], "choice", 1,1,$maxChoice);
	return $userMenuChoice;
}

#*****************************************************************************************************
# Subroutine			: getValidMountPointChoice
# Objective				: Get the mount point choice & validate
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getValidMountPointChoice {
	my($userMenuChoice, $choiceRetry) = (0, 0);
	my($customMsg,@option) = @_;
	my $maxChoice = scalar(@option);
	while($choiceRetry < $AppConfig::maxChoiceRetry) {
		$userMenuChoice = getAndValidate([$customMsg], "Q_choice", 1,1,$maxChoice);
		if ($userMenuChoice eq 'q' or $userMenuChoice eq 'Q'){
			last;
		}
		my $path = $option[$userMenuChoice-1];
		my $permissionMode = getFileFolderPermissionMode($path);
		if ($permissionMode eq 'Writeable') {
			last;
		}
		else {
			display('mount_point_doesnt_have_permission');
			$choiceRetry++;
		}

		if ($choiceRetry == $AppConfig::maxChoiceRetry){
			display(["\n", 'your_max_attempt_reached', "\n"]);
			cancelProcess();
		}
	}
	return $userMenuChoice;
}

#*****************************************************************************************************
# Subroutine			: getUserMenuChoiceBuckSel
# Objective				: This subroutine helps to get the user's choices
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserMenuChoiceBuckSel {
	my($userMenuChoice, $choiceRetry, $maxChoice) = ('', 0, shift);
	while($choiceRetry < $AppConfig::maxChoiceRetry) {
		display(["\n", 'enter_your_choice'], 0);
		$userMenuChoice = getUserChoice();
		$userMenuChoice	=~ s/^[\s\t]+|[\s\t]+$//g;
		$choiceRetry++;
		if ($userMenuChoice eq '') {
			last;
		}
		elsif (!validateMenuChoice($userMenuChoice, 1, $maxChoice)) {
			$userMenuChoice = '';
			display(['invalid_choice', ' ', 'please_try_again']);
			checkRetryAndExit($choiceRetry);
		} else {
			last;
		}
	}
	return $userMenuChoice;
}

#*****************************************************************************************************
# Subroutine			: getStringWithScriptName
# Objective				: This subroutine helps to get the strings with script names
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStringWithScriptName {
	my ($stringToken, $tokenMessage, $opHolder) = (shift, '', '');
	return $tokenMessage if !$stringToken;

	$tokenMessage = $LS{'please_login_account_using_login_and_try'};
	foreach my $opScript (keys %AppConfig::idriveScripts) {
		$opHolder = '___' . $opScript . '___';
		$tokenMessage =~ s/$opHolder/$AppConfig::idriveScripts{$opScript}/eg
	}
	return $tokenMessage;
}

#*****************************************************************************************************
# Subroutine			: getMachineUser
# Objective				: This gets the name of the user who executes the script
# Added By				: Sabin Cheruvattil
# Modified By			: Anil, Senthil Pandian
#****************************************************************************************************/
sub getMachineUser {
	#return $ENV{'LOGNAME'};
	my $mcUserCmd = updateLocaleCmd('whoami');
	my $mcUser = `$mcUserCmd`;
	Chomp(\$mcUser);
	return $mcUser;
}

#*****************************************************************************************************
# Subroutine			: getTraceLogPath
# Objective				: Helps to retrieve the log path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getTraceLogPath {
	$username = '' unless defined $username;

	return getCatfile(getUserProfilePath(), $AppConfig::traceLogDir, $AppConfig::traceLogFile) if(loadServicePath());
	return getCatfile('/tmp/', $AppConfig::traceLogDir, $AppConfig::traceLogFile);
}

#*****************************************************************************************************
# Subroutine			: getUserModUtilCMD
# Objective				: Helps to user mod change utility
# Added By				: Sabin Cheruvattil
# Modified By           : Senthil Pandian
#****************************************************************************************************/
sub getUserModUtilCMD {
	my $modUtils	= ['runuser', 'su'];
	my $modFlags	= ['-l', '-m'];
	my $cmdCheck 	= '';

	return 'su -m ' if (isGentoo() or hasBSDsuRestrition());

	my $os = getOSBuild();
	if($os->{'os'} and grep(/$os->{'os'}/, ('centos', 'fedora'))) {
		if(-f '/sbin/runuser') {
			return '/sbin/runuser -l ';
		} elsif(-f '/usr/sbin/runuser') {
			return '/usr/sbin/runuser -l ';
		}
	}

	for my $i (0 .. $#{$modUtils}) {
		$cmdCheck = `which $modUtils->[$i] 2>/dev/null`;
		Chomp(\$cmdCheck);

		# Commented by Senthil to resolve FreeBSD scheduled job issue 
		# Got error "su: perl: command not found"
		# return qq($modUtils->[$i] $modFlags->[$i]) if ($cmdCheck ne '');

		return qq($cmdCheck $modFlags->[$i]) if ($cmdCheck ne '');
	}

	return '';
}

#*****************************************************************************************************
# Subroutine			: getAndValidate
# Objective				: This subroutine is used to take input ad ask for the retry option if it fails to validate.
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
=beg
sub getAndValidate1 {
	my $message = $_[0];
	my $fieldType = $_[1];
	my $isEchoEnabled = $_[2];
	my $isMandatory = (defined($_[3]) ? $_[3] : 0);
	my $maxLimit    = $_[4];
	my $dontExit    = (defined($_[5]) ? $_[5] : 0);
	my ($userInput, $choiceRetry) = ('', 0);

	while($choiceRetry < $AppConfig::maxChoiceRetry) {
		display($message, 0);
		$userInput = getUserChoice($isEchoEnabled);
		$choiceRetry++;
		if (($userInput eq '') && ($isMandatory)){
			display(['cannot_be_empty', '.', ' ', 'enter_again', '.', "\n"], 1);
			if($dontExit) {
				display('your_max_attempt_reached') if ($choiceRetry == $AppConfig::maxChoiceRetry);
				$userInput = 'exit';
			} else {
				checkRetryAndExit($choiceRetry, 0);
			}
		}
		elsif (!validateDetails($fieldType, $userInput, $maxLimit)) {
			if($dontExit) {
				display('your_max_attempt_reached') if ($choiceRetry == $AppConfig::maxChoiceRetry);
				$userInput = 'exit';
			} else {
				checkRetryAndExit($choiceRetry, 0);
			}			
		} else {
			last;
		}
	}
	return $userInput;
}
=cut
#*****************************************************************************************************
# Subroutine : getAndValidate
# Objective : This subroutine is used to take input ad ask for the retry option if it fails to validate.
# Added By : Anil Kumar
# Modified By : Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub getAndValidate {
    my $message = $_[0];
    my $fieldType = $_[1];
    my $isEchoEnabled = $_[2];
    my $isMandatory = (defined($_[3]) ? $_[3] : 0);
    my $maxLimit    = $_[4];
    my $dontExit    = (defined($_[5]) ? $_[5] : 0);
    my ($userInput, $choiceRetry) = ('', 0);

    while($choiceRetry < $AppConfig::maxChoiceRetry) {
        display($message, 0);
        $userInput = getUserChoice($isEchoEnabled);
        $choiceRetry++;
        if (($userInput eq '') && ($isMandatory)){
            display(['cannot_be_empty', '.', ' ', 'enter_again', '.', "\n"], 1);
            if ($choiceRetry == $AppConfig::maxChoiceRetry){
                $dontExit ? display('your_max_attempt_reached') : retreat('your_max_attempt_reached');
                $userInput = 'exit';
            }
        }
        elsif (!validateDetails($fieldType, $userInput, $maxLimit)) {
            if ($choiceRetry == $AppConfig::maxChoiceRetry){
                $dontExit ? display('your_max_attempt_reached') : retreat('your_max_attempt_reached');
                $userInput = 'exit';
            }
        }
        else {
			last;
		}
    }
    return $userInput;
}
#*****************************************************************************************************
# Subroutine			: getInvalidEmailAddresses
# Objective				: This subroutine validates email addresses
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getInvalidEmailAddresses {
	my ($inputEmails, $invalidEmails) 	= (shift, '');
	my @emails 	= ($inputEmails =~ /\,|\;/)? split(/\,|\;/, $inputEmails) : ($inputEmails);
	foreach my $email (@emails) {
		$email 	=~ s/^[\s\t]+|[\s\t]+$//g;
		if ($email ne '' && !isValidEmailAddress($email)) {
			$invalidEmails .= qq($email, );
		}
	}
	if ($invalidEmails) {
		#$invalidEmails =~ s/(?<!\w)//g;
		$invalidEmails =~ s/\s+$//;
		substr($invalidEmails,-1,1,".");
		display(['invalid_email_addresses_are_', $invalidEmails]);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getRemoteAccessToken
# Objective				: Read from or write to accesstoken.txt file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteAccessToken {
	my $t = 0;

	eval {
		my $response = makeRequest(10);
		$response = JSON::from_json($response);
		if (($response->{STATUS} eq 'FAILURE') or ($response->{'DATA'} eq '') or
						(lc($response->{'DATA'}) =~ 'invalid login')) {
			traceLog('Failed to get access token');
			$t = 0;
		}
		else {
			$response->{'DATA'} = JSON::from_json($response->{'DATA'});

			if (exists $response->{'DATA'}{'token'}) {
				$t = $response->{DATA}{'token'};
			}
		}
	};

	return $t;
}

#*****************************************************************************************************
# Subroutine			: getScript
# Objective				: get absolute path to the script file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getScript {
	my $script = getCatfile($appPath, $AppConfig::idriveScripts{$_[0]});
	if (-f $script) {
		return $script unless(defined($_[1]) and $_[1] == 1);
		return getECatfile($script);
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getDashboardScript
# Objective				: get absolute path to the dashboard file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getDashboardScript {
	my $script = getCatfile($appPath, $AppConfig::idriveLibPath, $AppConfig::idriveScripts{$AppConfig::dashbtask});
	if (-f $script) {
		return $script unless(defined($_[0]) and $_[0] == 1);
		return getECatfile($script);
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getParentRemoteManageIP
# Objective				: Read remote manage address
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getParentRemoteManageIP {
	#return getUserConfiguration('PRMSH');
	return getUserConfiguration('PRMIH');
}

#*****************************************************************************************************
# Subroutine			: getRemoteManageIP
# Objective				: Read remote manage address
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteManageIP {
	#return getUserConfiguration('RMSH');
	return getUserConfiguration('RMIH');
}

#*****************************************************************************************************
# Subroutine			: getNotificationFile
# Objective				: Path to notification file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getNotificationFile {
	return (getUserProfilePath() . "/$AppConfig::notificationFile");
}

#*****************************************************************************************************
# Subroutine			: getNSFile
# Objective				: Path to ns file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getNSFile {
	return (getUserProfilePath() . "/$AppConfig::nsFile");
}

#*****************************************************************************************************
# Subroutine			: getNotifications
# Objective				: Get notification value
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getNotifications {
	return \%notifications unless(defined $_[0]);

	if (exists $notifications{$_[0]}) {
		return $notifications{$_[0]};
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getNS
# Objective				: Get ns value
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getNS {
	return \%ns unless(defined $_[0]);

	if (exists $ns{'nsq'}{$_[0]}) {
		return $ns{'nsq'}{$_[0]};
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getCrontabFile
# Objective				: Path to crontab data file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getCrontabFile {
	return qq(/etc/$AppConfig::crontabFile);
}

#*****************************************************************************************************
# Subroutine			: getMigrateLockFile
# Objective				: Path to migrate user lock file
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub getMigrateLockFile {
	return getAppPath().$AppConfig::migUserlock;
}

#*****************************************************************************************************
# Subroutine			: getMigrateCompletedFile
# Objective				: Path to migrate user lock file
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub getMigrateCompletedFile {
	return getAppPath().$AppConfig::migUserSuccess;
}

#*****************************************************************************************************
# Subroutine			: getCRONLockInfo
# Objective				: This method gets the locks stats in array format
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getCRONLockInfo {
	return () unless(-f $AppConfig::cronlockFile);

	my $lockinfo = getFileContents($AppConfig::cronlockFile);
	chomp($lockinfo);

	return split('--', $lockinfo);
}

#*****************************************************************************************************
# Subroutine			: getSudoSuCRONPerlCMD
# Objective				: This is to get sudo/su command for running perl scripts in root mode
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getSudoSuCRONPerlCMD {
	return '' unless(defined($_[0]));
	return "$AppConfig::perlBin '" . getAppPath() . $AppConfig::idriveScripts{'utility'} . "' " . uc($_[0]) if ($AppConfig::mcUser eq 'root');

	my $command = "";
	if(hasSudo()) {
		display(["\n", $_[1], '.']) if (!isUbuntu() and !isGentoo() and !hasActiveSudo());

		my $message = exists($LS{$_[1]})? $LS{$_[1]} : $_[1];
		my $sudomsg = (isUbuntu() or isGentoo())? (" -p '" . $message . ": ' ") : "";
		$command = "sudo $sudomsg $AppConfig::perlBin '" . getAppPath() . $AppConfig::idriveScripts{'utility'} . "' " . uc($_[0]);
	}
	else {
		display(["\n", $_[1], '.']);

		my $sucurb = hasBSDsuRestrition()? ' -m root ' : '';
		$command = "su $sucurb -c \"$AppConfig::perlBin '" . getAppPath() . $AppConfig::idriveScripts{'utility'} . "' " . uc($_[0]) . "\"";
	}

	return $command;
}

#*****************************************************************************************************
# Subroutine			: getSudoSuCMD
# Objective				: This is to get sudo/su command for running the scripts in root mode
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getSudoSuCMD {
	return '' unless(defined($_[0]));
	return $_[0] . (defined($_[2])? ' &' : '') if ($AppConfig::mcUser eq 'root');

	my $message = exists($LS{$_[1]})? $LS{$_[1]} : $_[1];
	my $command = "";
	
	if(hasSudo()) {
		display(["\n", $message]) if (!isUbuntu() and !isGentoo() and !hasActiveSudo());
		my $sudomsg = (isUbuntu() or isGentoo())? (" -p '" . $message . ": ' ") : "";
		$command = "sudo $sudomsg $_[0]" . (defined($_[2])? ' &' : '');
	}
	else {
		display(["\n", $message]);
		my $sucurb = hasBSDsuRestrition()? ' -m root ' : '';
		$command = "su $sucurb -c \"$_[0]" . (defined($_[2])? ' &' : '') . "\"";
	}

	return $command;
}

#*****************************************************************************************************
# Subroutine			: getCrontab
# Objective				: Get crontab value
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getCrontab {
	return \%crontab unless(defined $_[0]);
	my $jobType = shift || retreat('crontabs_jobname_is_required');
	my $jobName = shift  || retreat('crontab_title_is_required');
	my $key     = shift;

	$jobType = $AppConfig::availableJobsSchema{$jobType}{'type'} if (exists $AppConfig::availableJobsSchema{$jobType});
	$jobType = 'backup' if ($jobType eq 'local_backup'); # TODO: IMPORTANT to review this statement again.

	if (exists $crontab{$AppConfig::mcUser} && exists $crontab{$AppConfig::mcUser}{$username} &&
		exists $crontab{$AppConfig::mcUser}{$username}{$jobType} && exists $crontab{$AppConfig::mcUser}{$username}{$jobType}{$jobName} &&
		eval("exists \$crontab{\$AppConfig::mcUser}{\$username}{\$jobType}{\$jobName}$key")) {
		return eval("\$crontab{\$AppConfig::mcUser}{\$username}{\$jobType}{\$jobName}$key");
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine	: getCurrentUserDashBdConfPath
# In Param		: crontab | hash, machine user | string, idrive user | string
# Out Param		: Command | String
# Objective		: Returns dashboard path
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getCurrentUserDashBdConfPath {
	my $ct = $_[0];
	my $mcu = $_[1];
	my $idu = $_[2];

	return '' unless($ct);

	if (exists $ct->{$mcu} && exists $ct->{$mcu}{$idu} && exists $ct->{$mcu}{$idu}{$AppConfig::dashbtask} && exists $ct->{$mcu}{$idu}{$AppConfig::dashbtask}{$AppConfig::dashbtask}) {
		return $ct->{$mcu}{$idu}{$AppConfig::dashbtask}{$AppConfig::dashbtask}{'cmd'};
	}

	return '';
}

#*****************************************************************************************************
# Subroutine			: getFileContents
# Objective				: Get a file content
# Added By				: Yogesh Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub getFileContents {
	unless (defined($_[0])) {
		retreat('filename_is_required');
	}
	my $returnType = 'string';
	$returnType = $_[1] if (defined $_[1]);

	my $fileContent = '';
	if (open(my $fileHandle, '<', $_[0])) {
		if ($returnType eq 'array') {
			chomp(my @fc = <$fileHandle>);
			$fileContent = \@fc;
		}
		else {
			$fileContent = join('', <$fileHandle>);
		}
		close($fileHandle);
		return $fileContent;
	}

	# retreat(['unable_to_open_file',' : ', $_[0], " $!"]);
	traceLog($LS{'unable_to_open_file'}.' : '.$_[0]." $!");
	return $fileContent;
}

#*****************************************************************************************************
# Subroutine : getBackupDeviceName
# In Param   : -
# Out Param  : STRING
# Objective  : Get's backup location name.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub getBackupDeviceName {
	if (getUserConfiguration('DEDUP') eq 'off') {
		return getUserConfiguration('BACKUPLOCATION');
	}

	return (split("#", getUserConfiguration('BACKUPLOCATION')))[1];
}

#*****************************************************************************************************
# Subroutine : getBackupDeviceID
# In Param   : -
# Out Param  : STRING
# Objective  : Get's backup location id.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub getBackupDeviceID {
	if (getUserConfiguration('DEDUP') eq 'off') {
		return getUserConfiguration('BACKUPLOCATION');
	}

	return (split("#", getUserConfiguration('BACKUPLOCATION')))[0];
}

#*****************************************************************************************************
# Subroutine			: getStartAndEndEpochTime
# Objective				: To return the start and end date epoch time.
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getStartAndEndEpochTime {
	my $currentTimeStamp = time();
	my $daysToSubstract = shift;
	my $startTimeStamp = $currentTimeStamp - ($daysToSubstract * 24 * 60 * 60);
	return ($startTimeStamp, $currentTimeStamp);
}

#*****************************************************************************************************
# Subroutine			: getStartAndEndEpochTimeForMigration
# Objective				: To return the start and end date epoch time.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getStartAndEndEpochTimeForMigration {
	my %logFilenames = %{$_[0]};
	my $lastLogTime  = time();
	foreach(sort {$b <=> $a} keys %logFilenames) {
		$lastLogTime = $_;
		last;
	}

	#my $currentTimeStamp = time();
	my $daysToSubstract = 7;
	my $startTimeStamp = $lastLogTime - ($daysToSubstract * 24 * 60 * 60);
	return ($startTimeStamp, $lastLogTime);
}

#*****************************************************************************************************
# Subroutine			: getStringConstant
# Objective				: To return the string constant.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getStringConstant {
	my $message = $_[0];
	my $msg		= '';

	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}
	for my $i (0 .. $#{$message}) {
		if (exists $LS{$message->[$i]}) {
			$msg .= $LS{$message->[$i]};
		}
		elsif (exists $Help{$message->[$i]}) {
			$msg .= $Help{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}
	if (defined($_[2])) {
		my $c = 1;
		for my $i (0 .. $#{$_[2]}) {
			$msg =~ s/__ARG$c\__/$_[2]->[$i]/g;
			$c++;
		}
	}
	return $msg;
}

#****************************************************************************************************
# Subroutine Name         : getFileFolderPermissionMode
# Objective               : This subroutine will return permission mode of file/folder.
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub getFileFolderPermissionMode
{
	my $path = $_[0];
	my $permissionMode = '';
	if (-w $path) {
		if (open(FH, ">$path/check_write.txt")){
			$permissionMode = 'Writeable';
			close(FH);
			#system "rm '$path/check_write.txt'";
			removeItems("$path/check_write.txt");
		} else {
			$permissionMode = 'Read-only';
		}
	}
	elsif (-r $path) {
		$permissionMode = 'Read-only';
	}
	else {
		$permissionMode = 'No access';
	}
	return $permissionMode;
}

#****************************************************************************************************
# Subroutine Name         : getParameterValueFromStatusFileFinal.
# Objective               : Fetches the value of individual parameters which are specified in the
#                           Status file.
# Added By                : Vijay Vinoth.
#*****************************************************************************************************/
sub getParameterValueFromStatusFileFinal
{
	my @linesStatusFile = @AppConfig::linesStatusFile;
	undef @linesStatusFile;

	my @statusFinalHashData;
	my @inputData = @_;

	my $stf = readFinalStatus();
	my %statusFinalHash = %{$stf};
	foreach(@inputData) {
		if (defined $statusFinalHash{$_}){
			push (@statusFinalHashData, $statusFinalHash{$_});
		} else {
			push (@statusFinalHashData, 0);
		}
	}
	return (@statusFinalHashData);
}

#*******************************************************************************************************
# Subroutine Name         :	getSystemCpuCores
# Objective               :	Get system processor and core details.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/
sub getSystemCpuCores{
    my $cmd = "uname";
	$cmd = updateLocaleCmd($cmd);
	chomp(my $OS = `$cmd`);
	$OS = lc $OS;
	my $retVal = 2;
	my ($cmdCpuCores,$totalCores);
	if ($OS eq "freebsd"){
	  my $totalCoresCmd = updateLocaleCmd("sysctl -a | grep 'hw.ncpu' | cut -d ':' -f2");
	  $totalCores = `$totalCoresCmd`;
	  chomp($totalCores);
	  $totalCores = int($totalCores);
	  $retVal = ($totalCores == 1 ? 2 : ($totalCores == 2 ? 4 : $totalCores));
    }
	elsif ($OS eq "linux"){
	  my $cpuProcessorCountCmd = updateLocaleCmd("cat /proc/cpuinfo | grep processor | wc -l");
	  my $cpuProcessorCount = `$cpuProcessorCountCmd`;
	  chomp($cpuProcessorCount);
	  my $cmdCpuCoresCmd = updateLocaleCmd("grep 'cpu cores' /proc/cpuinfo | tail -1 | cut -d ':' -f2");
	  $cmdCpuCores = `$cmdCpuCoresCmd`;
	  chomp($cmdCpuCores);

	  $cmdCpuCores = ($cmdCpuCores ne "" ? int($cmdCpuCores) : 1);
	  $cpuProcessorCount = ($cpuProcessorCount ne "" ? int($cpuProcessorCount) : 1);

	  $totalCores = $cpuProcessorCount*$cmdCpuCores;
	  $retVal = ($totalCores == 1 ? 2 : ($totalCores == 2 ? 4 : $totalCores));
	}

	return $retVal;
}

#*******************************************************************************************************
# Subroutine Name         :	getLoadAverage
# Objective               :	Get Average Load time of the machine.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/
sub getLoadAverage {
	my $cmd = "uname";
	my $load_avg;
	my ( @one_min_avg );
	$cmd = updateLocaleCmd($cmd);
	chomp(my $OS = `$cmd`);
	$OS = lc $OS;
	if ($OS ne "freebsd"){
		open(LOAD, "/proc/loadavg") or die "Unable to get server load \n";
		$load_avg = <LOAD>;
		close LOAD;
		my ( @one_min_avg ) = split /\s/, $load_avg;
		return (sprintf '%.2f', $one_min_avg[1]);
	}else{
		my $load_avg_data = 'uptime | awk \'{print $(NF-2)" "$(NF-1)" "$(NF-0)}\' | tr "," " "\'\'';
		$load_avg_data = updateLocaleCmd($load_avg_data);
		$load_avg = `$load_avg_data`;
		chomp($load_avg);
		my ( @one_min_avg ) = split /\s/, $load_avg;
		return (sprintf '%.2f', $one_min_avg[2]);
	}
}

#*****************************************************************************************************
# Subroutine	: getRecentLoadAverage
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks recent cpu usage in percentage, core average not considered
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getRecentLoadAverage {
	my $cpuavgfile	= "/proc/loadavg";
	my $uptimeutl	= `which uptime 2>/dev/null`;
	Chomp(\$uptimeutl);

	if ($uptimeutl) {
		my $avgloadstr = 'uptime | awk \'{print $(NF-2)" "$(NF-1)" "$(NF-0)}\' | tr "," " "';
		my $avgload = `$avgloadstr`;
		chomp($avgload);

		my @recentcpuload = split /\s+/, $avgload;
		my $loadperc = sprintf('%.2f', $recentcpuload[0]);

		$loadperc = 0 if(!$loadperc);
		$loadperc = $loadperc * 100;

		return $loadperc;
	}

	if(-f "/proc/loadavg") {
		my $avgloadstr = getFileContents("/proc/loadavg");
		my @recentcpuload = split /\s+/, $avgloadstr;
		my $loadperc = sprintf('%.2f', $recentcpuload[0]);
		
		$loadperc = 0 if(!$loadperc);
		$loadperc = $loadperc * 100;

		return $loadperc;
	}

	return 0;
}

#*********************************************************************************************************
#Subroutine Name        : getDeviceHash
#Objective              : This function will provide the device list.
#Added By               : Senthil Pandian.
#*********************************************************************************************************/
sub getDeviceHash {
	my %resultHash;
	my @result = fetchAllDevices();
	#Added to consider the bucket type 'D' only
	my @devices;
	foreach (@result){
		next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
		push @devices, $_;
	}

	foreach my $value (@devices){
		my $key = $value->{'uid'};
		Chomp(\$key);
		$resultHash{$key} = $value;
	}
	return %resultHash;
}

#*****************************************************************************************************
# Subroutine	: generateWebViewXML
# In Param		: String | XML Path, Hash | Contents
# Out Param		: Status | Boolean
# Objective		: Generates XML for web upload
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub generateWebViewXML {
	my $xmlpath	= $_[0];
	my $wvc		= $_[1];
	my $xmlrec	= getWebViewXMLRecord($wvc);
	my $wvxml	= '';
	
	if(-f $xmlpath && -s _) {
		my $fc	= getFileContents($xmlpath, 'array');
		pop(@{$fc});

		$wvxml	= join("\n", @{$fc});
		$wvxml	.= "\n" . $xmlrec . "\n</records>";
	} else {
		$wvxml	= qq(<?xml version="1.0" encoding="utf-8"?>\n);
		$wvxml	.= qq(<records>\n$xmlrec\n</records>);
	}

	fileWrite($xmlpath, $wvxml);
}

#****************************************************************************************************
# Subroutine		: generateBackupsetFiles.
# Objective			: This function will generate backupset files.
# Added By			: Dhritikana
# Modified By		: Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub generateBackupsetFiles {
	$AppConfig::pidOperationFlag = "GenerateFile";

	my $pidPath				= getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
	my $backupsetFile       = getCatfile($AppConfig::jobRunningDir, $AppConfig::backupsetFile);
	my $relativeFileset     = getCatfile($AppConfig::jobRunningDir, $AppConfig::relativeFileset);
	my $noRelativeFileset   = getCatfile($AppConfig::jobRunningDir, $AppConfig::noRelativeFileset);
	my $filesOnly		    = getCatfile($AppConfig::jobRunningDir, $AppConfig::filesOnly);
	my $errorDir 	        = getCatfile($AppConfig::jobRunningDir, $AppConfig::errorDir);
	my $fileForSize			= getCatfile($AppConfig::jobRunningDir, $AppConfig::fileForSize);
	my $info_file 			= getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);
	my $totalFileCountFile  = getCatfile($AppConfig::jobRunningDir, $AppConfig::totalFileCountFile);
	my $showhidden	        = getUserConfiguration('SHOWHIDDEN');

	my $relative 		    = backupTypeCheck();
	my (@source);
	$AppConfig::totalFiles = 0;

    loadFullExclude();
    loadPartialExclude(); 
    loadRegexExclude();

	open FD_WRITE, ">>", $info_file or 
		display(getStringConstant('failed_to_open_file') . " info_file: $info_file to write, Reason:$!");

	my $tmpbkpset	= getDecBackupsetContents($backupsetFile, 'array');
	my @BackupArray	= @{$tmpbkpset};
	chomp(@BackupArray);
	@BackupArray	= uniqueData(@BackupArray);

	unless(@BackupArray) {
		$AppConfig::errStr = getStringConstant('failed_to_open_file') . " : $backupsetFile. Reason:$!\n";
		traceLog($AppConfig::errStr);
		goto GENLAST;
	}

	my $traceExist = getCatfile($errorDir, 'traceExist.txt');
	unless(open(TRACEERRORFILE, ">>", $traceExist)) {
		$AppConfig::errStr = getStringConstant('failed_to_open_file') . " : $traceExist. Reason:$!\n";
		traceLog($AppConfig::errStr);
	}
	chmod $AppConfig::filePermission, $traceExist;

	my $permissionError = getCatfile($errorDir, $AppConfig::permissionErrorFile);
	unless(open(TRACEPERMISSIONERRORFILE, ">>", $permissionError)) {
		$AppConfig::errStr = getStringConstant('failed_to_open_file') . " : $permissionError. Reason:$!\n";
		traceLog($AppConfig::errStr);
	}
	chmod $AppConfig::filePermission, $permissionError;

	my $dbpath = getJobsPath('localbackup', 'path');
	my $dbfile = getCatfile($dbpath, $AppConfig::dbname);

	my $offset = 0;
	my $splitsize = 0;
	my $backupfiles;

	my ($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 1);
	unless($dbfstate) {
		sleep(2) while(-f $scanfile);
		($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 1);
		exit(0) unless($dbfstate);
	}

	Sqlite::initiateDBoperation();

	$AppConfig::readySyncedFiles = Sqlite::getReadySyncedCount();
	$AppConfig::readySyncedFiles = 0 unless($AppConfig::readySyncedFiles);

	foreach my $item (@BackupArray) {
		last unless(-f $pidPath);
		chomp($item);

		next unless($item);
		$offset = 0;
		$item =~ s/^[\/]+|[\/]+$/\//g; #Removing "/" if more than one found at beginning/end
		next if($item =~ m/^$/ || $item =~ m/^[\s\t]+$/ || $item =~ /^\.\.?$/);

		chop($item) if($item ne "/" && substr($item, -1, 1) eq "/");

		if (!-l $item && -d _) {
			my $filehandle;
			if ($relative == 0) {
				$AppConfig::noRelIndex++;
				$BackupsetFile_new = $noRelativeFileset . "$AppConfig::noRelIndex";
				$filecount = 0;
				$a = rindex ($item, '/');
				$source[$AppConfig::noRelIndex] = substr($item,0,$a);
				$source[$AppConfig::noRelIndex] = "/" if ($source[$AppConfig::noRelIndex] eq "");
				$current_source = $source[$AppConfig::noRelIndex];

				unless(open $filehandle, ">>", $BackupsetFile_new) {
					traceLog("cannot open $BackupsetFile_new to write ");
					goto GENLAST;
				}

				chmod $AppConfig::filePermission, $BackupsetFile_new;
			}

			my $bksetfiles = '';
			$backupfiles = Sqlite::getExpressBackupFilesByKilo($item . '/');
			while(my $filedata = $backupfiles->fetchrow_hashref) {
				my $dirpath		= (defined($filedata->{'DIRNAME'}))? $filedata->{'DIRNAME'} : '';
				$dirpath		=~ s/^'//i;
				$dirpath		=~ s/'$//i;

				my $filename	= (defined($filedata->{'FILENAME'}))? $filedata->{'FILENAME'} : '';
				$filename		=~ s/^'//i;
				$filename		=~ s/'$//i;

				my $filesize	= (defined($filedata->{'FILE_SIZE'}))? $filedata->{'FILE_SIZE'} : 0;
				my $filepath	= getCatfile($dirpath, $filename);
				
				last unless(-f $pidPath);
				chomp($filepath);
				next if($filepath =~ m/^$/ || $filepath =~ m/^[\s\t]+$/ || $filepath =~ /^\.\.?$/);

				unless(-r $filepath) {
					# write into error
					my $reason = $!;
					if ((-f $filepath && $reason =~ /no such file or directory/i) || $reason =~ /inappropriate ioctl for device/i || $reason =~ /permission denied/i) {
						$AppConfig::noPermissionCount++;
						print TRACEPERMISSIONERRORFILE "[" . (localtime) . "] [FAILED] [$filepath]. Reason: " . getStringConstant('permission_denied') . "\n";
					} else {
						$AppConfig::nonExistsCount++;
						$AppConfig::missingCount++ if($reason =~ /No such file or directory/);
						print TRACEERRORFILE "[" . (localtime) . "] [FAILED] [$filepath]. Reason: $reason\n";
					}

					next;
				}

				$totalSize += $filesize;
				$splitsize += $filesize;

				if($relative == 0) {
					my $temp = $filepath;
					$temp =~ s/$current_source// if($current_source ne "/");
					$bksetfiles .= qq($temp\n);
				}
				else {
					$current_source = "/";
					$bksetfiles .= qq($filepath\n);
				}

				$filecount++;
				$AppConfig::totalFiles++;

				if($filecount == FILE_MAX_COUNT || $splitsize >= $AppConfig::backupsetMaxSize) {
					if($relative == 0) {
						print $filehandle $bksetfiles;
					}
					else {
						print NEWFILE $bksetfiles;
					}

					$bksetfiles = '';
					$splitsize = 0;
					goto GENLAST unless(createBackupSetFiles1k());
				}
			}

			if($bksetfiles ne '') {
				if($relative == 0) {
					print $filehandle $bksetfiles;
				}
				else {
					print NEWFILE $bksetfiles;
				}

				$bksetfiles = '';
			}

			$backupfiles->finish();

			if ($relative == 0 && $filecount > 0) {
				autoflush FD_WRITE;
				close $filehandle;
				print FD_WRITE "$current_source' '" . RELATIVE . "' '$BackupsetFile_new\n";
			}
		}
		elsif(!-l $item) {
			my $fileinf	= Sqlite::getFileInfoByFilePath($item);
			# Check if file is already in sync or not
			next if(!exists($fileinf->{'BACKUP_STATUS'}));
			if($fileinf->{'BACKUP_STATUS'} eq $AppConfig::dbfilestats{'BACKEDUP'}) {
				next if(-f $item);
				$AppConfig::readySyncedFiles-- if($AppConfig::readySyncedFiles); #Added to handle when file is missing but still it counted as sync.
			}

			unless(-r $item) {
				# write into error
				my $reason = $!;
				if((-f $item && $reason =~ /no such file or directory/i) || $reason =~ /inappropriate ioctl for device/i || $reason =~ /permission denied/i) {
					$AppConfig::noPermissionCount++;
					print TRACEPERMISSIONERRORFILE "[" . (localtime) . "] [FAILED] [$item]. Reason: " . getStringConstant('permission_denied') . "\n";
				} else {
					$AppConfig::nonExistsCount++;
					$AppConfig::missingCount++ if ($reason =~ /No such file or directory/);
					print TRACEERRORFILE "[" . (localtime) . "] [FAILED] [$item]. Reason: $reason \n";
				}

				next;
			}
            next if(isThisExcludedItemSet($item . '/', $showhidden));

			$totalSize += -s $item;
			$splitsize += -s _;
			print NEWFILE qq($item\n);
			$current_source = "/";
			$AppConfig::totalFiles++;

			if ($relative == 0) {
				$AppConfig::filesonlycount++;
				$filecount = $AppConfig::filesonlycount;
			}
			else {
				$filecount++;
			}

			if ($filecount == FILE_MAX_COUNT || $splitsize >= $AppConfig::backupsetMaxSize) {
				$splitsize = 0;
				$AppConfig::filesonlycount = 0;
				goto GENLAST unless(createBackupSetFiles1k("FILESONLY"));
			}
		}
	}

	$AppConfig::totalFiles	+= ($AppConfig::readySyncedFiles + $AppConfig::missingCount);

	Sqlite::closeDB();

	if ($relative == 1 && $filecount > 0) {
		autoflush FD_WRITE;
		print FD_WRITE "$current_source' '" . RELATIVE . "' '$BackupsetFile_new\n";
	}
	elsif ($AppConfig::filesonlycount > 0) {
		$current_source = "/";
		autoflush FD_WRITE;
		print FD_WRITE "$current_source' '" . NORELATIVE . "' '$filesOnly\n";
	}

GENLAST:
	autoflush FD_WRITE;
	print FD_WRITE "TOTALFILES $AppConfig::totalFiles\n";
	print FD_WRITE "FAILEDCOUNT $AppConfig::nonExistsCount\n";
	print FD_WRITE "DENIEDCOUNT $AppConfig::noPermissionCount\n";
	print FD_WRITE "MISSINGCOUNT $AppConfig::missingCount\n";
	print FD_WRITE "READYSYNC $AppConfig::readySyncedFiles\n";
	close FD_WRITE;
	close NEWFILE;
	$AppConfig::pidOperationFlag = "generateListFinish";
	#close INFO;

	open FILESIZE, ">$fileForSize" or traceLog($LS{'failed_to_open_file'}." : $fileForSize. Reason:$!");
	print FILESIZE "$totalSize";
	close FILESIZE;
	chmod $AppConfig::filePermission, $fileForSize;
	# fileWrite($totalFileCountFile,$AppConfig::totalFiles);
	Common::loadAndWriteAsJSON($totalFileCountFile, {$AppConfig::totalFileKey =>$AppConfig::totalFiles});
	chmod $AppConfig::filePermission, $totalFileCountFile;
	close(TRACEERRORFILE);
	close(TRACEPERMISSIONERRORFILE);
	exit 0;
}

#******************************************************************************************************************
# Subroutine Name		: getEmailSubLine.
# Objective				: This subroutine returns email subject line
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#******************************************************************************************************************/
sub getEmailSubLine {
	my $taskType  = ucfirst($_[0]);
	my $opType    = ucfirst($_[1]);
	my $userName  = getUsername();
	my $subjectLine = "";
	my $chk = AppConfig::JOBEXITCODE->{'SUCCESS'};

	if ($AppConfig::opStatus =~ /$chk/) {
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX');
		my ($successfiles, $filetotal) = (0) x 2;

		($successfiles) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);

		if ($AppConfig::totalFiles) {
			$filetotal = $AppConfig::totalFiles;
			Chomp(\$filetotal);
		}

		if ($successfiles > 0) {
			$subjectLine = "$taskType $opType Status Report " . "[$userName]" . " [Backed up file(s): $successfiles of $filetotal]" . " [Successful $opType]";
		} else {
			$subjectLine = "$taskType $opType Status Report " . "[$userName]" . " [Successful $opType]";
		}
	} else {
		$subjectLine = "$taskType $opType Status Report " . "[$userName]" . " [$AppConfig::opStatus $opType]";
	}

	return ($subjectLine);
}
#*********************************************************************************************************
# Subroutine Name		: getLocalBackupDir
# Objective				: This function will return the local backup location(Directory path)
# Added By				: Senthil Pandian.
# Modified By			: Sabin Cheruvattil
#*********************************************************************************************************/
sub getLocalBackupDir {
	return $backupLocationDir . '/';
}

#*****************************************************************************************************
# Subroutine			: getPropSettingsFile
# Objective				: Path to prop settings file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getPropSettingsFile {
	if ((getUserConfiguration('DEDUP') eq 'off') and defined($_[0]) and ($_[0] eq 'master')) {
		return getCatfile(getUserProfilePath(), $AppConfig::masterPropsettingsFile);
	}

	return getCatfile(getUserProfilePath(), $AppConfig::propsettingsFile);
}

#****************************************************************************************************
# Subroutine		: getPropSettings.
# Objective			: Load prop settings
# Added By			: Yogesh Kumar
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub getPropSettings {
	my $ps = getPropSettingsFile($_[0]);
	return {} unless (-f $ps and !-z _);

	my $p = {};
	eval {
		$p = from_json(getFileContents($ps));
		1;
	}
	or do {
		fileWrite($ps, '');
		$p = {};
	};

	return $p;
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
	my %statusHash = readStatusFile($_[0]); #Read status file content & keep it in hash
	my @keys = keys %statusHash;
	my $size = @keys;
	if ($size and defined($statusHash{$_[1]})){
		return $statusHash{$_[1]};
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine		: getConsideredFilesCountFromLog
# Objective			: Get considered files count from Log file content
# Added By 			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub getConsideredFilesCountFromLog {
	my $logFile 	= $_[0];
	return (0, 0) unless(-f $logFile);

	my $logContentCmd = updateLocaleCmd("tail -n10 '$logFile'");
	my @logContent  = `$logContentCmd`;
	my $isSummary	= 0;
	my ($considered, $success) = ("--") x 2;

	foreach (@logContent) {
		my $line = $_;
		if (!$isSummary and $line =~ m/Summary:/) {
			$isSummary = 1;
		}
		elsif ($isSummary and $line =~ m/considered/){
			$considered = (split(":", $line))[1];
			Chomp(\$considered);
		}
		elsif ($isSummary and $line =~ m/(backed|restored)/){
			$success = (split(":", $line))[1];
			Chomp(\$success);
			last;
		}
	}

	return ($considered, $success);
}

#*****************************************************************************************************
# Subroutine		: getDuration
# Objective			: Get duration in seconds between two dates
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getDuration {
	return int((($_[0] - $_[1]) % 86400) / 3600);
}

#*****************************************************************************************************
# Subroutine			: getFileSize
# Objective				: Get directory size
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getFileSize {
	return 0 if(!-e $_[0]);

	my $sf		= lstat($_[0]);
	my $mode	= $sf->mode;
	my $restype	= $mode & 61440;

	if ($restype == 32768) {
		${$_[1]} = ${$_[1]} + 1;

		return $sf->size;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine		: getFileModifiedTime
# Objective			: Get modified time of file
# Added By 			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub getFileModifiedTime {
	return 0 if(!-e $_[0]);

	my $epoch = stat($_[0])->mtime;
	return ($epoch)?$epoch:0;
}

#*****************************************************************************************************
# Subroutine		: getLastOneWeekLogs
# Objective			: get logs files for last 7 days from the last log file's date
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getLastOneWeekLogs {
	my (%logStat,$jobDir);
	my %logFilenames = ();

	unless (defined($_[1]) and defined($_[2])) {
		retreat('start_and_end_dates_are_required');
	}

	if (defined($_[0]) and defined($_[3])){
		$jobDir = $_[3];
	} else {
		return \%logStat;
	}

	if (defined($_[0]) and ref($_[0]) eq 'HASH') {
		%logFilenames = %{$_[0]};
	} else {
		return \%logStat;
	}

	#my $lf = tie(my %logFiles, 'Tie::IxHash');
	my $logsFound = 0;
	foreach(sort {$b <=> $a} keys %logFilenames) {
		if ((($_[1] <= $_) && ($_[2] >= $_))) {
			$logsFound = 1;
			my $file = $jobDir."/".$_."_".$logFilenames{$_};
			print NEWFILE $file."\n";
			my $modifiedTime = getFileModifiedTime($file);
			my $duration     = getDuration($_,$modifiedTime);
			$duration     	 = ($duration =~ /^\d+$/)?$duration:"--";
			my ($filescount,$success) = getConsideredFilesCountFromLog($file);
			$filescount    	 = ($filescount =~ /^\d+$/)?$filescount:"--";
			$success    	 = ($success =~ /^\d+$/)?$success:"--";

			$logStat{$_} = {
				'filescount' => $filescount,
				'duration'	 => $duration,
				'status'   	 => $logFilenames{$_},
				'datetime' 	 => strftime("%m/%d/%Y %H:%M:%S", localtime($_)),
				'bkpfiles'   => $success,
				'size'       => "--",
			};
		}
		elsif ($logsFound) {
			last;
		}
	}

	return \%logStat;
}

#*****************************************************************************************************
# Subroutine		: getLocalDataWithType
# Objective			: Get existing local file/folder names with type.
# Added By 			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub getLocalDataWithType {
	my %list;
	my $display = $_[1];
	my $incluk	= $_[2];

	foreach my $item (@{$_[0]}) {
		chomp($item);

		# check if any of the parent is link
		# unless($incluk) {
			# my @uricomp = split(/\//, $item);
			# my $uri		= '/';
			# shift @uricomp;

			# foreach my $urifrag (@uricomp) {
				# $uri	= getCatfile($uri, $urifrag);

				# if(-l $uri) {
					# $item = $uri;
					# last;
				# }
			# }
		# }

		if (-l $item || -p _ || -S _ || -b _ || -c _) {
			display(["Skipped [$item]. ", "Reason", 'not_a_regular_file']) if(!defined($display) || $display);
			$skippedItem = 1;
			next;
		} elsif (-d _) {
			$item .= (substr($item, -1) ne '/')? '/' : '';
			$list{$item}{'type'} = 'd';
		}
		elsif (-f _) {
			$list{$item}{'type'} = 'f';
		} else {
			display(["Skipped [$item]. ", "Reason", 'file_folder_not_found']) if(!defined($display) || $display);
			$list{$item}{'type'} = 'u' if($incluk);
			$skippedItem = 1;
		}
	}

	return %list;
}

#*****************************************************************************************************
# Subroutine		: getRemoteDataWithType
# Objective			: Get existing remote file/folder names with type.
# Added By 			: Senthil Pandian
# Modified By 		: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteDataWithType{
	my %list;
	my $jobRunningDir  = getUsersInternalDirPath('restore');
	my $isDedup  	   = getUserConfiguration('DEDUP');
	my $restoreFromLoc = getUserConfiguration('RESTOREFROM');
	$restoreFromLoc = '/'.$restoreFromLoc  if ($isDedup eq 'off' and $restoreFromLoc !~ m/^\//);
	$restoreFromLoc = removeMultipleSlashs($restoreFromLoc);
	$restoreFromLoc = removeLastSlash($restoreFromLoc);

	#print "restoreFromLoc:$restoreFromLoc\n";
	my $tempFilePath = $jobRunningDir."/".$AppConfig::tempBackupsetFile;
	if (!open(ITEMLISTNEW, ">", $tempFilePath)){
		#$errMsg = $Locale::strings{'failed_to_open_file'}.": $tempFilePath, Reason: $!";
		return 0;
	}

	my $finalRestoreFromLoc= '';
	$finalRestoreFromLoc = $restoreFromLoc	if ($isDedup eq 'off' and $restoreFromLoc ne '/');

	my @arryToCheck = ();
	foreach(@{$_[0]}) {
		push @arryToCheck, $finalRestoreFromLoc.$_."\n";
	}

	print ITEMLISTNEW @arryToCheck;
	close(ITEMLISTNEW);

	my $itemStatusUTFpath = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
	createUTF8File(['ITEMSTATUS',$itemStatusUTFpath,1],
		$tempFilePath,
		$evsErrorFile,
		''		
		) or retreat('failed_to_create_utf8_file');

	my @responseData = runEVS('item',1);
	unlink($tempFilePath);

	if (-s $evsErrorFile > 0) {
		my $err = getFileContents($evsErrorFile);
		if($err =~ /unauthorized user|user information not found/i) {
			updateAccountStatus(getUsername(), 'UA');
			saveServerAddress(fetchServerAddress());
			retreat('operation_could_not_be_completed_please_try_again');
		}
		elsif ($err =~ /device is deleted\/removed|failed to get the device information|device has been logged out/i) {
			deleteBackupDevice();
			retreat('unable_to_find_your_restore_location');
		}
		else {
			my $errStr = checkExitError($evsErrorFile,'restore');
			if ($errStr and $errStr =~ /1-/) {
				$errStr =~ s/1-//;
				retreat($errStr);
			}
		}
	}
	unlink($evsErrorFile);
	if ($isDedup eq 'on'){
		foreach my $tmpLine (@responseData) {
			my @fields = $tmpLine;
			if (ref($fields[0]) ne "HASH") {
				next;
			}
			my $itemName = $fields[0]{'fname'};
			replaceXMLcharacters(\$itemName);
			#$itemName =~ s/^[\/]+/\//g;
			if ($fields[0]{'status'} =~ /directory exists/) {
				$list{$itemName}{'type'} = 'd';
			}
			elsif ($fields[0]{'status'} =~ /file exists/){
				$list{$itemName}{'type'} = 'f';
			}
			else {
				my $restoreFromBuck = (split("#",$restoreFromLoc))[1];
				$itemName =~ s/^\/(.*?)\//\/$restoreFromBuck\//;
				replaceXMLcharacters(\$itemName);
				display(["Skipped [$itemName]. ", "Reason",'file_folder_not_found']);
				$skippedItem = 1;
			}
		}
	} else {
		foreach my $tmpLine (@responseData) {
			my @fields   = $tmpLine;
			if (ref($fields[0]) ne "HASH") {
				next;
			}
			my $itemName = $fields[0]{'fname'};
			replaceXMLcharacters(\$itemName);
			if ($finalRestoreFromLoc ne '/'){
				$finalRestoreFromLoc =~ s/(["'*+\$^.])/\\$1/g;
				$itemName =~ s/$finalRestoreFromLoc//;
			}
			if ($fields[0]{'status'} =~ /directory exists/) {
				$list{$itemName}{'type'} = 'd';
			}
			elsif ($fields[0]{'status'} =~ /file exists/){
				$list{$itemName}{'type'} = 'f';
			}
			else {
				$itemName = $fields[0]{'fname'};
				replaceXMLcharacters(\$itemName);
				display(["Skipped [$itemName]. ", "Reason",'file_folder_not_found']);
				$skippedItem = 1;
			}
		}
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine		: getUniquePresentData
# Objective			: Remove duplicate items & return the unique file/folder names which is present.
# Added By 			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub getUniquePresentData {
	my @itemArray	= uniqueData(@{$_[0]});
	my $fileType	= $_[1];
	my %list;
	if ($fileType eq 'restore'){
		%list = getRemoteDataWithType(\@itemArray);
	} else {
		%list = getLocalDataWithType(\@itemArray, $_[2], $_[3]);
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine	: getExcludeSetSummary
# In Param		: job type, CDP
# Out Param		: Description | String
# Objective		: Prepares a summary of excluded items
# Added By		: Sabin Cheruvattil
# Modified By	: Senthil Pandian
#*****************************************************************************************************
sub getExcludeSetSummary {
	my $exsummary = '';
   
    my $fullStr  = getFullExcludeItems();
    my $parStr   = getPartialExcludeItems();
    my $regexStr = getRegexExcludeItems();

	my $dbpath		= getJobsPath($_[0], 'path');
	if($fullStr ne '') {
        my $exclude = $fullStr;
		Chomp(\$exclude);        
		$exsummary .= "[".getStringConstant('full_path_exclude') . "]\n";
		$exsummary .= $exclude . "\n\n";
	}

	if($parStr ne '') {
        my $exclude = $parStr;
		Chomp(\$exclude);

		if($exclude) {
			$exsummary .= "[".getStringConstant('partial_path_exclude') . "]\n";
			$exsummary .= $exclude . "\n\n";
		}
	}
	
	if($regexStr ne '') {
		my $exclude = $regexStr;
		Chomp(\$exclude);

		$exsummary .= "[".getStringConstant('regex_exclude') . "]\n";
		$exsummary .= $exclude . "\n\n";
	}

	if($exsummary ne '') {
        chomp($exsummary);
		$exsummary	= getStringConstant('exclude_set') . "\n" . $exsummary;
		my ($dbfstate, $scanfile) = Sqlite::createLBDB($dbpath, 1);
		if($dbfstate and !defined($_[1])) {
			Sqlite::initiateDBoperation();
            $AppConfig::excludedCount = Sqlite::getExcludedCount();
			$exsummary .= "\n" . getStringConstant('total_excluded_files') . ': ' . $AppConfig::excludedCount . "\n"; #Need not to print this for CDP log header
			Sqlite::closeDB();
		}
        $exsummary .= "\n";
	} else {
		$exsummary	= getStringConstant('exclude_set') . "\n" . getStringConstant('--not_applicable--'). "\n\n";
    }
	
	return $exsummary;
}

#*****************************************************************************************************
# Subroutine    : getJobSetLogSummary
# Objective     : Prepares job set summary for operation logs
# Added By      : Sabin Cheruvattil
# Modified By   : Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub getJobSetLogSummary {
	my $jobtype = $_[0];
	return '' unless($jobtype);

	my $jsf = getJobsPath($jobtype, 'file');
	#return '' unless (-f "$jsf.json"  and !-z "$jsf.json");
	unless (-f "$jsf.json"  and !-z "$jsf.json") {
		my $backupsizefile = getCatfile(getJobsPath($jobtype, 'path'), $AppConfig::backupsizefile);
		if (-f $backupsizefile and !-z $backupsizefile) {
			system("mv '$backupsizefile' '$jsf.json'");
		}
	}

	my ($fsum, $dsum, $usum, $summary) = ('', '', '', '');
	if (-f "$jsf.json"  and !-z "$jsf.json") {
		my %jsc = %{JSON::from_json(getFileContents("$jsf.json"))};
		foreach my $filename (keys %jsc) {
			next if ($filename eq '');

			# IMPORTANT: DO NOT REMOVE: if ($filetype eq 'f' || (lc($jobtype) =~ /backup/ && -f $filename)) {
			if ($jsc{$filename}{'type'} eq 'f') {
				$fsum .= qq($filename\n);
			}
			elsif ($jsc{$filename}{'type'} eq 'd') {
				$dsum .= qq($filename\n);
			}
			else {
				$usum .= qq($filename\n);
			}
		}
	} elsif (-f "$jsf.info"  and !-z "$jsf.info") {
		if (! open(FILE, "< $jsf.info")) {
			traceLog("Could not open file $jsf.info, Reason:$!");
			return '';
		}
		#read backup/restore set file content
		my @jsc = ();
		@jsc = <FILE>;
		close FILE;
		chomp(@jsc);

		for (my $i=0; $i<$#jsc; $i=$i+2) {
			next if ($jsc[$i] eq '');

			if ($jsc[$i+1] eq 'f') {
				$fsum .= $jsc[$i]."\n";
			}
			elsif ($jsc[$i+1] eq 'd') {
				$dsum .= $jsc[$i]."\n";
			}
			else {
				$usum .= $jsc[$i]."\n";
			}
		}
	} else {
		return '';
	}

	$summary .= (($fsum ne '')? "[Files]\n" . $fsum."\n" : '');
	$summary .= (($dsum ne '')? "[Directories]\n" . $dsum."\n" : '');
	$summary .= (($usum ne '')? "[Unknown]\n" . $usum."\n" : '');
	return $summary;
}

#*****************************************************************************************************
# Subroutine	: getWebViewSummary
# In Param		: Hash | Log details
# Out Param		: String | Summary
# Objective		: Gives back web view summary
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getWebViewSummary {
	my $wvc		= $_[0];
	my @desc	= ();

	push(@desc, getStringConstant('ref_username') . $wvc->{'uname'});
	push(@desc, getStringConstant('computer_name') . ' : ' . $wvc->{'hostname'});
	push(@desc, $wvc->{'optype'});
	push(@desc, getStringConstant('backup_start_time') . $wvc->{'st'});
	push(@desc, getStringConstant('backup_end_time') . $wvc->{'et'});
	push(@desc, getStringConstant('files_considered_for_backup') . $wvc->{'files'} . ' ' . getStringConstant('file_s'));
	push(@desc, getStringConstant('files_already_present_in_your_account') . $wvc->{'filesync'} . ' ' . getStringConstant('file_s'));
	push(@desc, '');

	return join('!!!', @desc);
}

#*****************************************************************************************************
# Subroutine	: getWebViewXMLRecord
# In Param		: String | XML Path, Hash | Contents
# Out Param		: Status | Boolean
# Objective		: Generates XML record tag for web upload
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getWebViewXMLRecord {
	my $wvc	= $_[0];
	my $xt	= "<record>\n";
	$xt		.= "<DateTime>$wvc->{'et'}</DateTime>\n";
	$xt		.= "<uname>$wvc->{'uname'}</uname>\n";
	$xt		.= "<files>$wvc->{'files'}</files>\n";
	$xt		.= "<filesinsync>$wvc->{'filesync'}</filesinsync>\n";
	$xt		.= "<status>$wvc->{'status'}</status>\n";
	$xt		.= "<duration>$wvc->{'duration'}</duration>\n";
	$xt		.= "<content>$wvc->{'summary'}</content>\n";
	$xt		.= "<optype>$wvc->{'optype'}</optype>\n";
	$xt		.= "<lpath>$wvc->{'lpath'}</lpath>\n";
	$xt		.= "<logfile>$wvc->{'logfile'}</logfile>\n";
	$xt		.= "</record>";

	return $xt;
}

#*****************************************************************************************************
# Subroutine			: getMinMaxVersion
# Objective				: This subroutine is to get min/max version for the current package version.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getMinMaxVersion {
	my @current = split('\.', $_[0]);
	my %list;
	my %minMaxVersionSchema = %{$AppConfig::minMaxVersionSchema{$AppConfig::appType}};
    foreach my $order (sort {$a cmp $b} keys %minMaxVersionSchema) {
		my @min = split('\.', $minMaxVersionSchema{$order}{'min'});
		my @max = split('\.', $minMaxVersionSchema{$order}{'max'});
		my $found = 0;
		for my $i (0 .. scalar(@current)) {
			if (defined($current[$i]) && defined($min[$i]) && defined($min[$i]) ) {
				if ($current[$i] >= $min[$i] && $current[$i] <= $max[$i]) {
					$found = 1;
					next;
				}
				$found = 0;
			}
		}

		if ($found) {
			$list{"min"} = $minMaxVersionSchema{$order}{'min'};
			$list{"max"} = $minMaxVersionSchema{$order}{'max'};
			last;
		}
	}

	return \%list;
}

#*****************************************************************************************************
# Subroutine	: getProxyDetails
# In Param		: STRING (Proxy key)
# Out Param		: HASH (proxy details)
# Objective		: Get proxy details
# Added By		: Yogesh Kumar
#*****************************************************************************************************
sub getProxyDetails {
	createDir(getCachedDir(), 1) unless(-d getCachedDir());
	if (-f getUserFilePath($AppConfig::proxyInfoFile) and !-z getUserFilePath($AppConfig::proxyInfoFile)) {
		my $proxyDetails = JSON::from_json(getFileContents(getUserFilePath($AppConfig::proxyInfoFile)));
		if (defined $_[0]) {
			if (exists $proxyDetails->{$_[0]}) {
				return $proxyDetails->{$_[0]};
			}
		}
		else {
			return $proxyDetails;
		}
	}
	return '';
}

#*****************************************************************************************************
# Subroutine	: getProxyStatus
# In Param		: None
# Out Param		: Boolean
# Objective		: Check if proxy is configured already
# Added By		: Yogesh Kumar
#*****************************************************************************************************
sub getProxyStatus {
	createDir(getCachedDir(), 1) unless(-d getCachedDir());
	my $useProxy = 0;
	if (-f getUserFilePath($AppConfig::proxyInfoFile) and !-z getUserFilePath($AppConfig::proxyInfoFile)) {
		return 1;
	}
	return 0;
}

#****************************************************************************************************
# Subroutine Name         : getThrottleVal.
# Objective               : Verify bandwidth throttle value from CONFIGURATION File
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getThrottleVal {
	# my $bwVal = getUserConfiguration('BWTHROTTLE');
    my $bwVal  = 100;
    my $bwPath = getUserProfilePath()."/bw.txt";
 	if(-f $bwPath and !-z _) {
		my $bw = getFileContents($bwPath);   
        if(defined($bw) and $bw =~ m/^\d+$/ and 0 <= $bw and 100 > $bw) {
            $bwVal = $bw;
        }
    }
	return $bwVal;
}


#****************************************************************************************************
# Subroutine Name : getFullExcludeItems.
# Objective       : This function will return Full Path Exclude items from full path exclude File.
# Added By        : Senthil Pandian
#*****************************************************************************************************/
sub getFullExcludeItems {
	my @excludeArray;
	my $excludeFullPath = getUserFilePath($AppConfig::excludeFilesSchema{'full_exclude'}{'file'});
	$excludeFullPath   .= '.info';

	#read full path exclude file and prepare a hash for it
	if (-f $excludeFullPath and !-z $excludeFullPath) {
		if (!open(EXFH, $excludeFullPath)) {
			$AppConfig::errStr = getStringConstant('failed_to_open_file')." : $excludeFullPath. Reason:$!\n";
			display($AppConfig::errStr);
			traceLog($AppConfig::errStr);
			return;
		}

		@excludeArray = grep { !/^\s*$/ } <EXFH>;
		close EXFH;
	}

	my $fullStr = '';

	my $currentDir			= getAppPath();
	my $homepath			= $currentDir;
	my $usrpath				= getCatfile('/usr', $currentDir);
	my $idriveServicePath	= getServicePath() . '/';
	my $usrservpath			= getCatfile('/usr', $idriveServicePath);
	my $usrservhomepath		= $idriveServicePath;

	push @excludeArray, ($currentDir, 'enabled');
	push @excludeArray, ($idriveServicePath, 'enabled');

    #Adding mount path to exclude list
    my ($isValidMountPath, $mountedPath) = getAndSetMountedPath(1, 1);
    if($mountedPath) {
        my $expressLocalDir = getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
        push @excludeArray, ($expressLocalDir, 'enabled') if(-d $expressLocalDir);
    }
   

	push @excludeArray, ($usrpath, 'enabled') if(-d $usrpath);
	push @excludeArray, ($usrservpath, 'enabled') if(-d $usrservpath);

	if($homepath =~ /^\/usr\/home\//) {
		$homepath =~ s/^\/usr//;
		push @excludeArray, ($homepath, 'enabled') if(-d $homepath);
	}

	if($usrservhomepath =~ /^\/usr\/home\//) {
		$usrservhomepath =~ s/^\/usr//;
		push @excludeArray, ($usrservhomepath, 'enabled') if(-d $usrservhomepath);
	}

	my @qFullExArr; # What is the use of this variable.
	chomp @excludeArray;

	return \@excludeArray if(defined($_[0]) and $_[0] eq 'array');

	for (my $i=0; $i<=$#excludeArray; $i++) {
		if ($excludeArray[$i+1] eq 'enabled') {
			if (substr($excludeArray[$i], -1, 1) eq "/") {
				chop($excludeArray[$i]);
			}
			$backupExcludeHash{$excludeArray[$i]} = 1;
			push(@qFullExArr, $excludeArray[$i]) if ($excludeArray[$i] ne '');
		}
		$i++;
	}
	$fullStr = join("\n", @qFullExArr) if(@qFullExArr);
    return $fullStr;
}

#****************************************************************************************************
# Subroutine Name : getPartialExcludeItems.
# Objective       : This function will return Partial Exclude items from partial exclude File.
# Added By        : Senthil Pandian
#*****************************************************************************************************/
sub getPartialExcludeItems {
	my (@excludeParArray, @qParExArr);
	my $excludePartialPath = getUserFilePath($AppConfig::excludeFilesSchema{'partial_exclude'}{'file'});
	$excludePartialPath   .= '.info';

	my $parStr = '';
	#read partial path exclude file and prepare a partial match pattern
	if (-f $excludePartialPath and !-z $excludePartialPath) {
		if (!open(EPF, $excludePartialPath)) {
			$AppConfig::errStr = getStringConstant('failed_to_open_file')." : $excludePartialPath. Reason:$!\n";
			display($AppConfig::errStr);
			traceLog($AppConfig::errStr);
			return;
		}

		@excludeParArray = grep { !/^\s*$/ } <EPF>;
		close EPF;

		chomp(@excludeParArray);
		for(my $i = 0; $i <= $#excludeParArray; $i++) {
			if ($excludeParArray[$i+1] eq 'enabled') {
				$excludeParArray[$i] =~ s/[\s\t]+$//;
				#push(@qParExArr, "^".quotemeta($excludeParArray[$i]).'\/');
				push(@qParExArr, $excludeParArray[$i]);
			}
			$i++;
		}
		$parStr = join("\n", @qParExArr) if(@qParExArr);
		# chomp($AppConfig::parStr);
		# $AppConfig::parStr =~ s/\n/|/g;
	}
    return $parStr;    
}

#****************************************************************************************************
# Subroutine Name : getRegexExcludeItems.
# Objective       : This function will return Regular Expression Exclude items from RegexExclude File.
# Added By        : Senthil Pandian
#*****************************************************************************************************/
sub getRegexExcludeItems {
	my $regexExcludePath = getUserFilePath($AppConfig::excludeFilesSchema{'regex_exclude'}{'file'});
	$regexExcludePath   .= '.info';

	my $regexStr = '';

	#read regex path exclude file and find a regex match pattern
	if (-e $regexExcludePath and -s $regexExcludePath > 0) {
		if (!open(RPF, $regexExcludePath)) {
			$AppConfig::errStr = getStringConstant('failed_to_open_file')." : $regexExcludePath. Reason:$!\n";
			display($AppConfig::errStr);
			traceLog($AppConfig::errStr);
			return;
		}

		my @tmp;
		my @excludeRegexArray = grep { !/^\s*$/ } <RPF>;
		close RPF;

		if (scalar(@excludeRegexArray)) 
        {
			for(my $i = 0; $i <= $#excludeRegexArray; $i++) {
				chomp($excludeRegexArray[$i+1]);
				if ($excludeRegexArray[$i+1] eq 'enabled') {
					my $a = $excludeRegexArray[$i];
					chomp($a);
					$b = eval { qr/$a/ };
					if ($@) {
						traceLog("Invalid regex: $a");
					}
					elsif ($a) {
						push @tmp, $a;
					}
				}
				$i++;
			}
			$regexStr = join("\n", @tmp) if(@tmp);
		}
	}
    return $regexStr;
}

#*****************************************************************************************************
# Subroutine	: getScriptPathOfDashboard
# In Param		: dashboardPath
# Out Param		: scriptPath
# Objective		: Get script path from dashboard path
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub getScriptPathOfDashboard
{
    my $dashboardPath = $_[0];
    my $scriptPath    = '';
    if($dashboardPath =~ /Idrivelib/) {
        $scriptPath = (split("Idrivelib", $dashboardPath))[0];
    } elsif ($dashboardPath =~ /$AppConfig::idriveScripts{'dashboard'}/) {
        $scriptPath = (split($AppConfig::idriveScripts{'dashboard'}, $dashboardPath))[0];
    }
    return $scriptPath;
}

#*****************************************************************************************************
# Subroutine	: getExistingBucketConfirmation
# In Param		: devicelist
# Out Param		: UNDEF
# Objective		: Get confirmation to use existing bucket 
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub getExistingBucketConfirmation {
	my @devices 	   = @{$_[0]};
	my %matchedDevices = %{$_[1]};
	my $answer 		   = 'n';
	my $deviceID;

# use Data::Dumper;
# print "\n devices \n";
# print Dumper(\@devices);
# print "\n matchedDevices \n";
# print Dumper(\%matchedDevices);
	if(scalar(keys %matchedDevices) > 1) {
		$answer = 'y';
	} else {
		my @deviceArr = (keys %matchedDevices);
		$deviceID     = $deviceArr[0];
# print "deviceID:$deviceID\n\n";
		display(["\n",'your_backup_to_device_name_is',(" \"" . $matchedDevices{$deviceID}{'nick_name'} . "\". "),'do_you_want_to_change_(_y_n_)'], 1);
		$answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	if (lc($answer) eq 'y') {
		my $status = askToCreateOrSelectADevice(\@devices);
		retreat('failed_to_set_backup_location') unless($status);
		$muid = getMachineUID();
		setUserConfiguration('MUID', $muid);
		# saveUserConfiguration();
	} else {
		# display("");
		setUserConfiguration('SERVERROOT', $matchedDevices{$deviceID}{'server_root'});
		setUserConfiguration('BACKUPLOCATION',($AppConfig::deviceIDPrefix .
			$deviceID .$AppConfig::deviceIDSuffix ."#" . $matchedDevices{$deviceID}{'nick_name'}));
		setUserConfiguration('MUID', $matchedDevices{$deviceID}{'uid'});
	}
	loadNotifications() and setNotification('register_dashboard') and saveNotifications();
}

#------------------------------------------------- H -------------------------------------------------#

#*****************************************************************************************************
# Subroutine	: hasParentInSet
# In Param		: item, parentItemSet
# Out Param		: Parent Item(s) | ARRAY
# Objective		: Helps to check parent item is present in set
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub hasParentInSet {
	return 0 if(!$_[0] || !$_[1]);

	my ($item, $parentset) = ($_[0], $_[1]);
	my @matchitems = grep{$item =~ /^\Q$_\E/} @{$parentset};

	return @matchitems;
}

#*****************************************************************************************************
# Subroutine	: hasChildInSet
# In Param		: item, childItemSet
# Out Param		: Child Item(s) | ARRAY
# Objective		: Helps to check child item is present in set
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub hasChildInSet {
	return 0 if(!$_[0] || !$_[1]);

	my ($item, $childset) = ($_[0], $_[1]);
	my @matchitems = grep(/^\Q$item\E/, @{$childset});

	return @matchitems;
}

#*****************************************************************************************************
# Subroutine			: hasEVSBinary
# Objective				: Execute evs binary and check it's working or not
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub hasEVSBinary {
	my $dir = shift;
	my @evsBinaries;
	if ($AppConfig::appType eq 'IDrive') {
		@evsBinaries = (
			$AppConfig::evsBinaryName,
			$AppConfig::evsDedupBinaryName
		);
	} else {
		@evsBinaries = (
			$AppConfig::evsBinaryName
		);
	}
	my $duplicate = 1;

	unless(defined($dir)) {
		$dir = getServicePath();
		$duplicate = 0;
	}
	for (@evsBinaries) {
		my $evs = getCatfile($dir, $_);
		my ($status, $msg) = verifyEVSBinary($evs);
		return 0 if (!$status);
		if ($duplicate) {
			eval {
				copy($evs, getServicePath());
			};

			chmod($AppConfig::filePermission, getCatfile(getServicePath(), $_));
			chmod($AppConfig::filePermission, $evs);
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: hasStaticPerlSupport
# Objective				: Check if we support dashboard for this arc
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub hasStaticPerlSupport {
	loadMachineHardwareName();
	if (exists $AppConfig::staticperlZipFiles{$machineHardwareName}) {
		return 1;
	}
	else {
		#traceLog("No dashboard support for $machineHardwareName.");
		return 0;
	}
}

#*****************************************************************************************************
# Subroutine			: hasDashboardSupport
# Objective				: Check if we support dashboard for this arc
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub hasDashboardSupport {
	loadMachineHardwareName();
	my $mhn = (($AppConfig::machineOS =~ /freebsd/i) ? 'freebsd' : $machineHardwareName);
	if (getUserConfiguration('RMWS') and getUserConfiguration('RMWS') eq 'yes') {
		if (exists $AppConfig::pythonZipFiles{$mhn}) {
			return 1
		}
	}
	elsif (exists $AppConfig::staticperlZipFiles{$mhn}) {
		return 1;
	}
	elsif (exists $AppConfig::pythonZipFiles{$mhn}) {
		return 1;
	}

	traceLog("No dashboard support for $mhn.");
	return 0;
}

#*****************************************************************************************************
# Subroutine			: hasStaticPerlBinary
# Objective				: Execute static perl binary and check it's working or not
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub hasStaticPerlBinary {
	my $dir = shift;
	my $duplicate = 1;

	unless(defined($dir)) {
		$dir = getCatfile(getAppPath(), $AppConfig::idrivePerlBinPath);
		$duplicate = 0;
	}
	$dir =~ s/__KVER__/$AppConfig::kver/g;
	my $sp = getCatfile($dir, $AppConfig::staticPerlBinaryName);
	my ($status, $msg) = verifyStaticPerlBinary($sp);
	return 0 unless ($status);
	if ($duplicate) {
		if (-f getCatfile(getAppPath(), $AppConfig::idrivePerlBinPath, $AppConfig::staticPerlBinaryName)) {
			rmtree(getCatfile(getAppPath(), $AppConfig::idrivePerlBinPath));
		}
		$dir = getECatfile($dir);
		my $cppltbin = updateLocaleCmd(("cp -rf $dir " . getECatfile(getAppPath(), $AppConfig::idriveDepPath)));
		`$cppltbin`;
		my $privl = updateLocaleCmd(("chmod -R 0755 " . getECatfile(getAppPath(), $AppConfig::idriveDepPath)));
		`$privl`;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: hasPythonBinary
# Objective				: Check if the installed python binary is compatible with this device. Remove if not supported.
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub hasPythonBinary {
	my $pybinpath = getCatfile(getAppPath(), $AppConfig::idrivePythonBinPath);
	my $pybin = getCatfile($pybinpath, $AppConfig::pythonBinaryName);
	if (-f $pybin) {
		$pybin = getECatfile($pybinpath, $AppConfig::pythonBinaryName);
		my $idrivepyver = "$pybin -v 2>/dev/null";
		$idrivepyver = `$idrivepyver`;
		chomp($idrivepyver);
		unless ($idrivepyver eq $AppConfig::pythonVersion) {
			if (-d $pybinpath) {
				rmtree($pybinpath);
			}

			return 0;
		}

		return 1;
	}
	elsif (-d $pybinpath) {
		rmtree($pybinpath);
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: hasCRONFallBackAdded
# Objective				: This is to verify fall back is added in crontab or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub hasCRONFallBackAdded {
	my $crontab	= '/etc/crontab';
	return 0 if(!-f $crontab || !-r $crontab);

	my $fc 		= getFileContents($crontab);
	return 1 if (index($fc, $AppConfig::cronLinkPath) != -1);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: hasSQLitePreReq
# Objective				: Verify sqlite3 prerequisites availablility & DB transaction is allowed
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub hasSQLitePreReq {
	my $pldoc = `which perldoc 2>/dev/null`;
	Chomp(\$pldoc);

	if($pldoc) {
		my $dbipm = `$pldoc -l DBI 2>/dev/null`;
		my $dbdpm = `$pldoc -l DBD::SQLite 2>/dev/null`;
		Chomp(\$dbipm);
		Chomp(\$dbdpm);

		return 0 if(!$dbipm || !$dbdpm);
	}

	# Check the availability by creating a temp DB
	my $dbfile = getCatfile('/tmp/', $AppConfig::dbname);
	eval {
		unlink($dbfile) if(-f $dbfile);

		my ($dbfstate, $scanfile) = Sqlite::createLBDB('/tmp/', 0);
		return 0 unless($dbfstate);

		Sqlite::initiateDBoperation();
		my $opstat	= Sqlite::insertProcess(localtime, 0);
		Sqlite::closeDB();

		return $opstat;
	};

	unlink($dbfile) if(-f $dbfile);
	return $@? 0 : 1;
}

#*****************************************************************************************************
# Subroutine			: hasFileNotifyPreReq
# Objective				: Verify Inotify2 prerequisites availability
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub hasFileNotifyPreReq {
	my $pldoc = `which perldoc 2>/dev/null`;
	Chomp(\$pldoc);

	if($pldoc) {
		my $inotify = `$pldoc -l Linux::Inotify2 2>/dev/null`;
		Chomp(\$inotify);

		return 0 unless($inotify);
	}

	eval {
		require Linux::Inotify2;
	};

	if ($@ && $@ =~ /attempt to reload/i){
		delete $INC{'Linux::Inotify2'};
		
		$@ = '';
		eval {
			require Linux::Inotify2;
		};
	}

	return $@? 0 : 1;
}

#*****************************************************************************************************
# Subroutine			: hasBasePreReq
# Objective				: Verify base prerequisites is present or not
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub hasBasePreReq {
	for my $dep (@AppConfig::dependencyBinaries) {
		`which $dep 2>/dev/null`;
		return 0 if($? != 0);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine	: hasDefaultExcludeInBackup
# In Param		: Job Type
# Out Param		: Boolean
# Objective		: Checks default exclude is present in job set
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub hasDefaultExcludeInBackup {
	my $jobtype = $_[0];
	return 0 if(!$_[0]);

	my $jobpath = getJobsPath($jobtype, 'file');
	my $backupset = getDecBackupsetContents($jobpath, 'array');

	foreach my $idx (0 .. $#{$backupset}) {
		return 1 if(grep {"$backupset->[$idx]/" =~ /^\Q$_\E/} @AppConfig::defexcl);
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine	: hasBSDsuRestrition
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks BSD restriction for su binary
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub hasBSDsuRestrition {
	my $os = getOSBuild();
	return 1 if($os->{'os'} eq 'freebsd' and $os->{'build'} >= 12);
	return 0;
}

#*****************************************************************************************************
# Subroutine	: hasSudo
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks machine has sudo or not
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub hasSudo {
	`which sudo >/dev/null 2>&1`;
	return 0 if($? != 0);
	return 1;
}

#*****************************************************************************************************
# Subroutine	: hasSu
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks machine has su or not
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub hasSu {
	`which su >/dev/null 2>&1`;
	return 0 if($? != 0);
	return 1;
}

#*****************************************************************************************************
# Subroutine	: hasActiveSudo
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks active sudo session is present or not
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub hasActiveSudo {
	`sudo -n true >/dev/null 2>&1`;
	return 0 if($? != 0);
	return 1;
}

#------------------------------------------------- I -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: init
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub initiateMigrate{
	loadAppPath();
	if (loadServicePath()){
		my $userServiceLocationFile = "$appPath/$AppConfig::serviceLocationFile";
		my $migrateLockFile = getMigrateLockFile();
		my $migrateSuccessFile = getMigrateCompletedFile();
		return if (-e $migrateSuccessFile);
		return if (-e getUserFile() and -s getUserFile());

		my $ServiceLocation = getServicePath();
		$ServiceLocation =~ s/$AppConfig::servicePathName$/$AppConfig::oldServicePathName/;
		return if (!-e $ServiceLocation);
		my $ServiceLocationOld = $ServiceLocation;

		if (!-f $migrateLockFile or !isFileLocked($migrateLockFile)){
			open(my $lockfh, ">>", $migrateLockFile);
			print $lockfh $AppConfig::mcUser;
			flock($lockfh, LOCK_EX|LOCK_NB);
			chmod($AppConfig::filePermission, $migrateLockFile);

			display(["\n", 'do_you_want_to_migrate_user_data']);
			$AppConfig::displayHeader = 0;
			my $restartcron = getAndValidate(['enter_your_choice'], "YN_choice", 1);
			$AppConfig::displayHeader = 1;
			if ($restartcron eq 'y')
			{
				my $sudoprompt = 'please_provide_' . (hasSudo()? 'sudoers' : 'root') . '_pwd_for_migrate_process';

				my $sudosucmd = getSudoSuCRONPerlCMD('migrateuserdata', $sudoprompt);
				$sudosucmd = updateLocaleCmd($sudosucmd);
				if (system($sudosucmd) != 0){
					$AppConfig::displayHeader = 0;
					retreat(['migrate_reject_try_again',"\n"]);
				}
				fileWrite($migrateSuccessFile, '');
				chmod($AppConfig::filePermission, $migrateSuccessFile);
				loadServicePath();

				if ($AppConfig::appType eq 'IDrive') {
					unless (hasStaticPerlBinary()) {
						loadMachineHardwareName();
						if (defined $machineHardwareName){
							display(['downloading_static_perl_binary', '... ']);
							downloadStaticPerlBinary() or retreat('unable_to_download_static_perl_binary');
							display('static_perl_binary_downloaded_successfully');
						}
					}
					checkAndStartDashboard();
				}
				doSilentLogout();
			}else{
				display(['migrate_reject_try_again',"\n"]);
				close($lockfh);
				exit;
			}
			flock($lockfh, LOCK_UN);
			close($lockfh);
			unlink $migrateLockFile;
		}
		else{
			$AppConfig::displayHeader = 0;
			retreat(['migrate_reject_try_again',"\n"]);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: installInotifyPreRequisites
# Objective				: Install Inotify pre-requesites
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub installInotifyFallBackPreReq {
	# Compile from source
	my $instpid		= fork();
	if(defined($instpid) && $instpid == 0) {
		traceLog('INotify2: Installing by dynamic compiling');
		my $inotifysrc	= getCatfile(getAppPath(), $AppConfig::inotifySourcePath) . '/';

		for my $instidx (0 .. $#{$AppConfig::cmdInotifySrcComp}) {
			# $AppConfig::cmdInotifySrcComp->[$instidx] =~ s/ 2>\/dev\/null 1>\/dev\/null//g;
			# print "\ncd $inotifysrc;$AppConfig::cmdInotifySrcComp->[$instidx]\n";
			system("cd $inotifysrc;$AppConfig::cmdInotifySrcComp->[$instidx] 2>$AppConfig::repoerrpath 1>$AppConfig::repooppath");
		}

		exit(0);
	}

	waitpid($instpid, 0) if($instpid);
	sleep(1);

	return 1 if(hasFileNotifyPreReq());

	traceLog('INotify2: Installing compiled resources');
	my $os			= getOSBuild();

	# If source compile doesn't work, try with copying the compiled files
	use Config;
	my $siteplarch	= $Config{'installsitearch'};
	chomp($siteplarch);

	my $sitepllib	= $Config{'installsitelib'};
	chomp($sitepllib);

	my $archpath	= $Config{'archlib'};
	chomp($archpath);

	my $man3path	= $Config{'man3dir'};
	chomp($man3path);

	my $man3site	= $Config{'installsiteman3dir'};
	chomp($man3site);

	return 0 if(!$siteplarch || !-d $siteplarch);

	loadMachineHardwareName();
	my $mcarc	= 'x' . getMachineHardwareName();
	
	my $osconfs;
	$osconfs = $AppConfig::inotifyCompiled->{$os->{'os'}} if(defined($AppConfig::inotifyCompiled->{$os->{'os'}}));
	return 0 unless($osconfs);
	
	my $procconfs;
	foreach my $verkey (keys(%{$osconfs})) {
		my @opver	= split('-', $verkey);
		if (($opver[0] eq 'gte' && $os->{'build'} >= $opver[1]) || ($opver[0] eq 'lte' && $os->{'build'} <= $opver[1]) ||
		($opver[0] eq 'btw' && (split('_', $opver[1]))[0] <= $os->{'build'} && $os->{'build'} <= (split('_', $opver[1]))[1]) || 
		($opver[0] eq 'gt' && $os->{'build'} > $opver[1]) || ($opver[0] eq 'lt' && $os->{'build'} < $opver[1])) {
			$procconfs = $AppConfig::inotifyCompiled->{$verkey};
		}
	}
	
	return 0 unless($procconfs);

	my $setupdir = $procconfs->{'setupdir'};
	return 0 unless($setupdir);
	
	$setupdir =~ s/__ARCH__/$mcarc/g;
	return 0 unless(-d $setupdir);
	
	if(defined($procconfs->{'copy'})) {
		foreach my $cpindex (keys(%{$procconfs->{'copy'}})) {
			my $srcpath		= getCatfile(getAppPath(), $setupdir, $cpindex);
			my $destpath	= $procconfs->{'copy'}{$cpindex};
			my $destdir		= dirname($destpath);
			$destpath		=~ s/__SITEPERL_ARCH_PATH__/$siteplarch/g;
			$destpath		=~ s/__MAN3_PATH__/$man3path/g;
			$destpath		=~ s/__MAN3_SITE__/$man3site/g;
			createDir($destdir, 1) unless(-d $destdir);
			copy($srcpath, $destpath);
		}
	}

	if(defined($procconfs->{'create'})) {
		foreach my $crtidx (keys(%{$procconfs->{'create'}})) {
			my $crtpath = $crtidx;
			$crtpath =~ s/__SITEPERL_ARCH_PATH__/$siteplarch/g;

			for my $appndidx (0 .. $#{$procconfs->{'create'}{$crtidx}}) {
				my $appendname = $procconfs->{'create'}{$crtidx}[$appndidx];
				$appendname =~ s/__SITEPERL_ARCH_PATH__/$siteplarch/g;
				$appendname =~ s/__MAN3_PATH__/$man3path/g;
				$appendname =~ s/__MAN3_SITE__/$man3site/g;

				fileWrite($crtpath, $appendname, 'APPEND');
			}
		}
	}

	if(defined($procconfs->{'append'})) {
		foreach my $apdidx (keys(%{$procconfs->{'append'}})) {
			my ($appcont, $destcont) = ('', '');
			my $appsrc	= getCatfile(getAppPath(), $setupdir, $apdidx);
			my $appdest	= $procconfs->{'append'}{$apdidx}{'file'};
			my $appdir	= dirname($appdest);
			$appdest	=~ s/__ARCHLIB_PATH__/$archpath/g;
			$appdest	=~ s/__SITEPERL_ARCH_PATH__/$siteplarch/g;

			# if(-f $appsrc && -f $appdest) {
			if(-f $appsrc) {
				$appcont	= getFileContents($appsrc);
				$appcont	=~ s/__SITEPERL_LIB_PATH__/$sitepllib/g;

				# verify its already appended or not
				$destcont	= getFileContents($appdest) if(-f $appdest);
				createDir($appdir, 1) unless(-d $appdir);
				if(index($destcont, $procconfs->{'append'}{$apdidx}{'verify'}) == -1) {
					fileWrite($appdest, $appcont, 'APPEND');
				}
			}
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: installDBCDPPreRequisites
# Objective				: Install DB & CDP pre-requesites
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub installDBCDPPreRequisites {
	my $pkgerr			= $_[0]->{'pkgerr'};
	my $display			= $_[0]->{'display'};
	my $cpanconf		= $_[0]->{'cpanconf'};
	my $pkginstallseq	= $_[0]->{'pkginstallseq'};
	my $pkgerrignore	= $_[0]->{'pkgerrignore'};
	my $cpancmdappend	= $_[0]->{'cpancmdappend'};
	my $silinstappend	= $_[0]->{'silinstappend'};
	my $cpaninstallseq	= $_[0]->{'cpaninstallseq'};
	
	# Auto install sqlite3 dependencies
	if($display) {
		display(["\n", 'this_may_take_miniutes_to_comp', '. ', 'please_wait', '...']);
		display(['installing_linux_dependencies', ': ']);

		my $prodisppid		= fork();
		if(defined($prodisppid) && $prodisppid == 0) {
			$0	= 'IDrive:InstProgress';

			fileWrite($AppConfig::instproglock, $$);
			sleep(2);
			displayInstallationProgress(3);
			exit(0);
		}

		waitpid($prodisppid, WNOHANG);
	}

	my ($packagenames, $cpanpacks);
	($pkginstallseq, $packagenames) = getPkgInstallables($pkginstallseq);
	($cpaninstallseq, $cpanpacks) = getCPANInstallables($cpaninstallseq);

	local $SIG{INT}		= sub {unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
	local $SIG{TERM}	= sub {unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
	local $SIG{KILL}	= sub {unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
	local $SIG{ABRT}	= sub {unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
	local $SIG{PWR}		= sub {unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);} if(exists $SIG{'PWR'});
	local $SIG{QUIT}	= sub {unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};

	for my $instidx (0 .. $#{$pkginstallseq}) {
		$pkginstallseq->[$instidx] =~ /(.*?)install\s(.*)/is;

		my $packs = $2 || '';
		$packs =~ s/-qq //g;
		$packs =~ s/-q //g;
		$packs =~ s/-y //g;
		Chomp(\$packs);
		next unless($packs);

		# Check whether the package is installed or not
		my $inststat = `which $packs 2>/dev/null`;
		Chomp(\$inststat);
		next if($inststat);

		# display([$packs, '...']) if($packs);
		fileWrite($AppConfig::instprog, getStringConstant('installing') . ' ' . $packs . '...') if($packs);

		if(!$display && $silinstappend) {
			system("$silinstappend;$pkginstallseq->[$instidx] 2>$AppConfig::repoerrpath 1>$AppConfig::repooppath;");
		} else {
			system("$pkginstallseq->[$instidx] 2>$AppConfig::repoerrpath 1>$AppConfig::repooppath");
		}

		if(-f $AppConfig::repoerrpath && !-z _) {
			my $instlog = `tail -n20 $AppConfig::repoerrpath`;
			next if($pkgerrignore && $instlog =~ /$pkgerrignore/gi);

			fileWrite($AppConfig::repoerrpath, "\nfailed to install: $packs\n", 'APPEND');
			unlink($AppConfig::instproglock) if(-f $AppConfig::instproglock);
			if($display) {
				`cat '$AppConfig::repoerrpath'`;
				retreat(["\n", 'package_installation_repo_error', '.']);
			} else {
				traceLog(['package_installation_repo_error']);
				exit(1);
			}
		}
	}

	sleep(2);

	# process cpan confs if items are present to configure
	if(scalar @{$cpaninstallseq} > 0) {
		my $confacc = autoConfigureCPAN($cpanconf, $cpancmdappend, $display);

		display(["\n", 'installing_perl_dependency', ': ']) if(!$confacc && $display);

		local $SIG{INT}		= sub {installCPANPerms(); unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
		local $SIG{TERM}	= sub {installCPANPerms(); unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
		local $SIG{KILL}	= sub {installCPANPerms(); unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
		local $SIG{ABRT}	= sub {installCPANPerms(); unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};
		local $SIG{PWR}		= sub {installCPANPerms(); unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);} if(exists $SIG{'PWR'});
		local $SIG{QUIT}	= sub {installCPANPerms(); unlink($AppConfig::instproglock); unlink($AppConfig::instprog); exit(0);};

		for my $instidx (0 .. $#{$cpaninstallseq}) {
			$cpaninstallseq->[$instidx] =~ s/__CPAN_AUTOINSTALL__/$cpancmdappend/g;
			$cpaninstallseq->[$instidx] =~ /(.*?)install\s(.*?)\'/is;

			fileWrite($AppConfig::instprog, getStringConstant('installing') . ' ' . $2 . '...');
			system("$cpaninstallseq->[$instidx] 2>$AppConfig::repoerrpath 1>$AppConfig::repooppath");
		}

		installCPANPerms();
	}

	unlink($AppConfig::instproglock) if(-f $AppConfig::instproglock);
	unlink($AppConfig::instprog) if(-f $AppConfig::instprog);

	return 1;
}

#*****************************************************************************************************
# Subroutine		: installCPANPerms
# In Param			: UNDEF
# Out Param			: UNDEF
# Objective			: Applies permission to CPAN created directories
# Added By			: Sabin Cheruvattil
#*****************************************************************************************************
sub installCPANPerms {
	# Apply permission for these directories recurseively: installsitelib, installsitearch
	use Config;
	my @permconfs	= ('installsitelib', 'installsitearch', 'archlib');
	my @permarr		= ('0755', '0775', '0777');
	foreach my $pmc (@permconfs) {
		my $spath	= $Config{$pmc};
		chomp($spath);

		fileWrite('/tmp/idrperm.log', "spath: $spath\n", 'APPEND');
		my @conmatch	= ($spath =~ /((.*)perl(.*))\/(.*)/);
		if(!$conmatch[0] || !-d $conmatch[0]) {
			@conmatch	= ($spath =~ /((.*)perl(.*))/);
			next if(!$conmatch[0] || !-d $conmatch[0]);
		}

		my $cperm		= sprintf("%04o", stat($conmatch[0])->mode & 07777);
		fileWrite('/tmp/idrperm.log', "DIR: $conmatch[0] | mode: $cperm\n", 'APPEND');
		`chmod -R $AppConfig::execPermissionStr $conmatch[0]` if(!grep(/$cperm/, @permarr));
	}
}

#*****************************************************************************************************
# Subroutine			: isInternetAvailable
# Objective				: This is to verify the machine has Internet availability
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isInternetAvailable {
	my $pingResCmd = updateLocaleCmd("ping -c2 8.8.8.8 2>/dev/null");
	my $pingRes = `$pingResCmd`;
	return 0 if ($pingRes =~ /connect\: Network is unreachable/);
	return 0 if ($pingRes !~ /0\% packet loss/);

	return 1;
}

# TODO new scripts headers
#
sub isLatest {
	my $uvf = getUpdateVersionInfoFile();
	return '1' if (-f $uvf and !-z $uvf);

	return '0';
}

#*****************************************************************************************************
# Subroutine			: isFileLocked
# Objective				: Check if the file is locked or not
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub isFileLocked {
	my ($f, $block, $noclean) = ($_[0], $_[1], ($_[2] || 0));
	return 0 unless (-f $f);
	open(my $fh, ">>", $f) or return 1;

	my $locktype = (defined($block) && $block == 1)? LOCK_EX : LOCK_EX|LOCK_NB;
	unless (flock($fh, $locktype)) {
		close($fh);
		return 1;
	}
	close($fh);
	unlink($f) unless($noclean);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isThisExcludedItemSet
# Objective				: Checks whether the item is excluded or not
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub isThisExcludedItemSet {
	# user configuration has to be loaded & exclude paths should be loaded
	return 1 unless(defined($_[0]));

	my $excat = $_[2]? $_[2] : 'all';

	if($excat eq 'hidden') {
		return 1 if(!$_[1] && $_[0] =~ /\/\./);
	} elsif($excat eq 'partial') {
		return 1 if($AppConfig::parStr ne "" && $_[0] =~ m/$AppConfig::parStr/);
	} elsif($excat eq 'full') {
		return 1 if($AppConfig::fullStr ne "" && $_[0] =~ m/$AppConfig::fullStr/);
	} elsif($excat eq 'regex') {
		return 1 if($AppConfig::regexStr ne "" && $_[0] =~ m/$AppConfig::regexStr/);
	} else {
		return 1 if ((!$_[1] && $_[0] =~ /\/\./) ||
			($AppConfig::parStr ne "" && $_[0] =~ m/$AppConfig::parStr/) ||
			($AppConfig::fullStr ne "" && $_[0] =~ m/$AppConfig::fullStr/) ||
			($AppConfig::regexStr ne "" && $_[0] =~ m/$AppConfig::regexStr/));
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine	: isBackupsetSame
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Compares the backup sets
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub isBackupsetSame {
	my $bsfc	= getFileContents($_[0], 'array');
	my $obsfc	= getFileContents($_[1], 'array');

	return 0 if($#{$bsfc} != $#{$obsfc});

	foreach my $fname (@{$bsfc}) {
		return 0 unless(grep(/^\Q$fname\E$/, @{$obsfc}));
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: isUpdateAvailable
# Objective				: Check if latest version is available on the server
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil
#****************************************************************************************************/
sub isUpdateAvailable {
	return 0 if ($0 =~ m/$AppConfig::idriveScripts{'check_for_update'}/i);

	my $updateInfoFile = getUpdateVersionInfoFile();
	return 1 if (-f $updateInfoFile and !-z $updateInfoFile);

	my $check4updateScript = getECatfile($appPath, 'check_for_update.pl');
	$check4updateScript = updateLocaleCmd("$AppConfig::perlBin $check4updateScript checkUpdate");
	my $updateAvailStats = `$check4updateScript 1>/dev/null 2>/dev/null &`;

	return 1 if (-f $updateInfoFile and !-z $updateInfoFile);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isUbuntu
# Objective				: This is to verify the machine is ubuntu or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isUbuntu {
	my $versionCmd = 'cat /proc/version';
	return 1 if (-e '/proc/version' && `$versionCmd` =~ /ubuntu/);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isGentoo
# Objective				: This is to verify the machine is Gentoo or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isGentoo {
	my $versionCmd = 'cat /proc/version';
	return 1 if (-e '/proc/version' && `$versionCmd` =~ /gentoo/);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isRunningJob
# Objective				: This function will return 1 if pid.txt file exists, otherwise 0.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isRunningJob {
	my $jobRunningFile	= shift;
	return (-e $jobRunningFile)? 1 : 0;
}

#*****************************************************************************************************
# Subroutine			: isDashboardRunning
# Objective				: This function will return 1 if dashboard is running
# Added By				: Sabin Cheruvattil
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub isDashboardRunning {
	my $selfPIDFile = getCatfile(getServicePath(), $AppConfig::userProfilePath, $AppConfig::mcUser, $AppConfig::dashboardpid);
	return isFileLocked($selfPIDFile);
}

#*****************************************************************************************************
# Subroutine			: isUserDashboardRunning
# Objective				: This function will return 1 if user's dashboard is running
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub isUserDashboardRunning {
	my $selfPIDFile = getCatfile(getServicePath(), $AppConfig::userProfilePath, $AppConfig::mcUser, $AppConfig::dashboardpid);
	# username of the user who is currently configuring the account is already set by setUsername
	return (isFileLocked($selfPIDFile) && $_[0] eq getUsername());
}

#*****************************************************************************************************
# Subroutine			: isCDPServicesRunning
# Objective				: This function helps to check any of the cdp service instance is running for the user
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub isCDPServicesRunning {
	my $cdphalt			= getCDPHaltFile();
	my $cdpclientlock	= getCDPLockFile('client');
	my $cdpserverlock	= getCDPLockFile('server');
	my $cdpwatcherlock	= getCDPLockFile('watcher');
	my $dbwritelock		= getCDPLockFile('dbwritelock');

	return 1 if((-f $cdphalt || (isFileLocked($cdpclientlock) && isFileLocked($cdpserverlock))) && 
			isFileLocked($cdpwatcherlock) && isFileLocked($dbwritelock));
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isCDPAuxServicesRunning
# Objective				: This function helps to check any of the cdp service instance is running for the user
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub isCDPAuxServicesRunning {
	my $cdpclientlock	= getCDPLockFile('client');
	my $cdpserverlock	= getCDPLockFile('server');
	my $dbwritelock		= getCDPLockFile('dbwritelock');
	my $cdphalt			= getCDPHaltFile();
	
	return 1 if((-f $cdphalt || (isFileLocked($cdpclientlock) && isFileLocked($cdpserverlock))) && 
			isFileLocked($dbwritelock));
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isCDPWatcherRunning
# Objective				: This function helps to check watcher process is running or not
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub isCDPWatcherRunning {
	my $cdpwatcherlock	= getCDPLockFile('watcher');
	
	return 1 if(isFileLocked($cdpwatcherlock));
	return 0;
}

#*****************************************************************************************************
# Subroutine	: isDBWriterRunning
# In Param		: UNDEF
# Out Param		: Boolean
# Objective		: Checks DB writer is running or not
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub isDBWriterRunning {
	my $dbwritelock	= getCDPLockFile('dbwritelock');

	return 1 if(isFileLocked($dbwritelock));
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isCDPClientServerRunning
# Objective				: Helps to check client server service is running or not
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub isCDPClientServerRunning {
	my $cdpclientlock	= getCDPLockFile('client');
	my $cdpserverlock	= getCDPLockFile('server');

	return 1 if(isFileLocked($cdpclientlock) && isFileLocked($cdpserverlock));
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isLastDBScanComplete
# Objective				: This function helps to check last DB scan was success or not
# Added By				: Sabin Cheruvattil
# Modified By 		    : Senthil Pandian
#*****************************************************************************************************
sub isLastDBScanComplete {
	my @dbs;
	my $proclast;

	my @scanjobs	= ('bkpscan', 'rescan');
	for my $li (0 .. $#scanjobs) {
		return 1 if(isFileLocked(getCDPLockFile($scanjobs[$li])));
	}

	my $upddbpaths	= getCDPDBPaths();
	my ($dbfstate, $scanfile);

	foreach my $jbname (keys(%{$upddbpaths})) {
		next unless(-f getCatfile($upddbpaths->{$jbname}, $AppConfig::dbname));

		($dbfstate, $scanfile) = Sqlite::createLBDB($upddbpaths->{$jbname}, 1);
		next unless($dbfstate);

		# Sqlite::initiateDBoperation();
		$proclast = Sqlite::getLastProcess();

		push(@dbs, $jbname) if($proclast->{'start'} and !$proclast->{'end'});
		Sqlite::closeDB();
		undef $proclast;
	}

	return (($#dbs == -1)? 1 : 0, \@dbs);
	# return ($#dbs == -1)? 1 : 0;
}

#*****************************************************************************************************
# Subroutine			: isThisExpressBackupScan
# Objective				: Checks current scan is express backedup scan or not
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub isThisExpressBackupScan {
	my $scantype = getBackupsetScanType();

	return 1 if($scantype && $scantype eq 'localbackup');
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isThisOnlineBackupScan
# Objective				: Checks current scan is online backedup scan or not
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub isThisOnlineBackupScan {
	my $scantype = getBackupsetScanType();

	return 1 if($scantype && $scantype eq 'backup');
	return 0;
}

#*****************************************************************************************************
# Subroutine	: isThisBackupRescan
# In Param		: UNDEF
# Out Param		: Status | Boolean
# Objective		: Checks the scan type is rescan or not
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub isThisBackupRescan {
	return isFileLocked(getCDPLockFile('rescan'));
}

#*****************************************************************************************************
# Subroutine			: inAppPath
# Objective				: Find a file in source codes path
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub inAppPath {
	my ($file) = @_;
	$appPath = (fileparse($appPath))[1] if(-f $appPath);
	if (-f getCatfile($appPath, $file)) {
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: isLoggedin
# Objective				: Check if PWD file exists
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub isLoggedin {
	if (!defined($username) || $username eq '') {
		$username = '';
		return 0;
	}

	my @pf = ($AppConfig::idpwdFile, $AppConfig::idenpwdFile,
		$AppConfig::idpwdschFile);

	if (getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
		push @pf, ($AppConfig::idpvtFile, $AppConfig::idpvtschFile);
	}

	my $status = 0;
	for(@pf) {
		my $file = getCatfile($servicePath, $AppConfig::userProfilePath, $AppConfig::mcUser, $username, $_);
		if (!-f $file or -z $file) {
			$status = 0;
			last;
		}
		$status = 1;
	}

	my $uf = getUserFile();
	if (-f $uf and !-z $uf) {
		my $fc = getFileContents($uf);
		Chomp(\$fc);

		my %loginData = ();
		if ($fc ne '') {
			%loginData = ($fc =~ m/^\{/) ? %{JSON::from_json($fc)} : ();
		}

		unless ($status) {
			if (exists $loginData{$AppConfig::mcUser}) {
				$loginData{$AppConfig::mcUser}{'userid'} = $username;
				$loginData{$AppConfig::mcUser}{"isLoggedin"} = 0;
				fileWrite($uf, JSON::to_json(\%loginData));
			}
			return 0;
		}
		elsif (exists $loginData{$AppConfig::mcUser} and $loginData{$AppConfig::mcUser}{'userid'}) {
			if ($loginData{$AppConfig::mcUser}{'userid'} eq $username) {
				return $loginData{$AppConfig::mcUser}{"isLoggedin"};
			}
		}
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine	: isLogoutRequired
# In Param		: Array | Quota Details
# Out Param		: Status | Boolean
# Objective		: Checks if logout is required or not
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub isLogoutRequired {
	my $qinf	= $_[0];
	my $stat	= 0;

	return $stat if(!$qinf || !defined($qinf->[0]{lc($AppConfig::accountStorageSchema{'usedQuota'}{'evs_name'})}));

	my $uquota	= int($qinf->[0]{lc($AppConfig::accountStorageSchema{'usedQuota'}{'evs_name'})});
	if($uquota == 0 && getUserConfiguration('DEDUP') ne 'on') {
		my $authcmdpath		= getCatfile(getUserProfilePath(), $AppConfig::utf8File . '_authlist');
		my $authevsoppath   = getCatfile(getUserProfilePath(), $AppConfig::evsOutputFile . '_authList');
		my $autherrpath		= getCatfile(getUserProfilePath(), $AppConfig::evsErrorFile . '_authlist');
		
		createUTF8File(['AUTHLIST', $authcmdpath],
			$authevsoppath,
			$autherrpath,
			''
		);

		my @resp	= runEVS('item');
		my $fc		= '';
		$fc			= getFileContents($autherrpath) if(-f $autherrpath && -s _);
		if($fc) {
			traceLog($fc);
			$stat = 1 if($fc =~ /encryption verification failed/i);
			createBackupStatRenewalByJob('backup') if($stat);
		}

		unlink($authcmdpath);
		unlink($authevsoppath);
		unlink($autherrpath);
	}

	return $stat;
}

#*****************************************************************************************************
# Subroutine			: isValidUserName
# Objective				: This subroutine helps to validate username
# Added By				: Anil Kumar
#****************************************************************************************************/
sub isValidUserName {
	my $validUserPattern = 1;
	if (length($_[0]) < 4)
	{
		display(['username_must_contain_4_characters', '.',"\n"],1) ;
		$validUserPattern = 0;
	}
	return $validUserPattern;
}

#*****************************************************************************************************
# Subroutine			: isProxyEnabled
# Objective				: Helps to understand if proxy is enabled or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isProxyEnabled {
	return getProxyDetails('PROXYIP') ? 1 : 0;
}

#*****************************************************************************************************
# Subroutine			: isValidEmailAddress
# Objective				: This is to validate email address
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isValidEmailAddress {
	return (length($_[0]) > 5 && length($_[0]) <= 64 && (lc($_[0]) =~ m/^[a-zA-Z0-9]+(\.?[\*\+\-\_\=\^\$\#\!\~\?a-zA-Z0-9])*\.?\@([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)(\.[a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)*\.(?:([a-zA-Z0-9]+)|([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+))$/));
}

#*******************************************************************************************************
# Subroutine Name         :	isEngineRunning
# Objective               :	Checking the given engine is running or not.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/
sub isEngineRunning {
	my ($enginePidPath) = @_;
	my $fh;
	if (!-e $enginePidPath){
		return 0;
	}

	open($fh, ">", $enginePidPath) or return 1;
	if (flock($fh, LOCK_EX|LOCK_NB)){
		flock($fh, LOCK_UN);
		close $fh;
		return 0;
	}

	close $fh;
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	isAnyEngineRunning
# Objective               :	Checking the any engine is running or not.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/

sub isAnyEngineRunning
{
	my ($engineLockFile) = @_;
	open(my $handle, ">>", $engineLockFile) or return 0;
	if (!flock($handle, LOCK_EX|LOCK_NB)){
		close $handle;
		return 1;
	}
	flock($handle, LOCK_UN);
	close $handle;
	return 0;
}

#*******************************************************************************************************
# Subroutine Name         :	isJobRunning
# Objective               :	Checking whether any ( scheduled / dashboard related) job is running in the provided jobtype
# Added By             	  : Anil Kumar
# Modified By             : Vijay Vinoth
#********************************************************************************************************/
sub isJobRunning
{
	my $jobType = $_[0];
	my $jobRunningDir = getUserProfilePath();
	if ($jobType eq "backup" or $jobType eq "default_backupset") {
		$jobRunningDir .= "/Backup/DefaultBackupSet";
	}
	elsif ($jobType eq "local_backup" or $jobType eq "local_backupset" or $jobType eq "localbackup") {
		$jobRunningDir .= "/Backup/LocalBackupSet";
	}
	elsif ($jobType eq "archive") {
		$jobRunningDir .= "/Archive/DefaultBackupSet";
	}elsif ($jobType eq "restore") {
		$jobRunningDir .= "/Restore/DefaultBackupSet";
	}

	my $pidPath = $jobRunningDir."/".$AppConfig::pidFile;
	return 1 if (isFileLocked($pidPath));
	return 0;

}

#------------------------------------------------- J -------------------------------------------------#
#------------------------------------------------- K -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: killPIDs
# Objective				: Kill all process id's passed to it
# Added By				: Yogesh Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub killPIDs {
	my $res;
	my $terminate = 1;
	$terminate    = $_[1] if (defined($_[1]));

	foreach my $index (0 .. (@{$_[0]}-1)) {
		if ($_[0]->[$index]) {
			$res = waitpid($_[0]->[$index], WNOHANG);
			if ($res == -1 || $res > 0) {
				splice(@{$_[0]}, $index, 1);
			}
			elsif ($terminate) {
				system(updateLocaleCmd("kill $_[0]->[$index] 1>/dev/null 2>/dev/null"));
				if ($@) {
					traceLog("Unable to kill pid $_[0]->[$index]; Error: $@");
				}
			}
		}
	}
}

#------------------------------------------------- L -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: launchIDriveCRON
# Objective				: This is to launch IDrive CRON service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub launchIDriveCRON {
	my $opconf	= getCRONSetupTemplate();

	# Each time account settings runs, this will re-configure the cron
	if (%{$opconf}) {
		# prepare & copy the scripts replaced with the PATH
		processShellCopy($opconf);

		# shell linking
		processCRONShellLinks($opconf);

		# shell append
		processCRONConfAppends($opconf);

		# execute setup commands
		processCRONSetupCommands($opconf);

		# Reboot handler
		removeOldFallBackCRONRebootEntry();
		removeFallBackCRONRebootEntry();
		addFallBackCRONRebootEntry();

		return CRON_STARTED if (checkCRONServiceStatus($opconf->{'pidpath'}) == CRON_RUNNING);
	}

	traceLog('unable_to_install_idrive_cron');

	# Handle reboot fallback
	removeOldFallBackCRONRebootEntry();
	removeFallBackCRONRebootEntry();
	addFallBackCRONRebootEntry();

	# run cron manually in root mode
	my $croncmd = qq($AppConfig::perlBin '$AppConfig::cronLinkPath' 1>/dev/null 2>/dev/null &);
	system($croncmd);
	sleep(3);

	return CRON_STARTED if (checkCRONServiceStatus() == CRON_RUNNING);
	traceLog('unable_to_install_idrive_fallback_cron');
}

#*****************************************************************************************************
# Subroutine			: ltrim
# Objective				: This function will remove white spaces from the left side of a string.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub ltrim {
	my $s = shift;
	$s =~ s/^\s+//;
	return $s;
}

#*****************************************************************************************************
# Subroutine			: linkBucket
# Objective				: Choose a bucket from the list to backup/restore files
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018], Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub linkBucket {
	my $devices = ();
	foreach my $device (@{$_[1]}) {
		next if ($device->{'in_trash'} eq '1');
		push @$devices, $device;
	}

	my $slno = '';
	unless (defined($_[3])) {
		my @columnNames = (['S.No.', 'Device Name', 'Device ID', 'OS', 'Date & Time', 'IP Address'], [8, 24, 24, 15, 22, 16]);
		my $tableHeader = getTableHeader(@columnNames);
		display($tableHeader,0);
		my $tableData = "";
		my $columnIndex = 1;
		my $screenCols = (split(' ', $AppConfig::screenSize))[-1];

		my @columnHeaderInfo = ('s_no', 'nick_name', 'device_id','os', 'bucket_ctime', 'ip');

		my $serialNumber = 1;
		for my $device (@{$devices}) {
			for (my $i=0; $i < scalar(@columnHeaderInfo); $i++) {
				if ($columnHeaderInfo[$i] eq 's_no') {
					$tableData .= $serialNumber;
					$tableData .= (' ') x ($columnNames[1]->[$i] - length($serialNumber));
				}
				else {
					my $displayData = $device->{$columnHeaderInfo[$i]};

					if (($columnNames[1]->[$i] - length($displayData)) > 0){
						$tableData .= $displayData;
						$tableData .= (' ') x ($columnNames[1]->[$i] - length($displayData)) if ($columnHeaderInfo[$i] eq 'nick_name'||'os');
					}
					else {
						$tableData .= trimDeviceInfo($displayData,$columnNames[1]->[$i]) if ($columnHeaderInfo[$i] eq 'nick_name'||'os');
						$tableData .= (' ') x 3;
					}
					$tableData .= (' ') x ($columnNames[1]->[$i] - length($displayData)) if ($columnHeaderInfo[$i] eq 's_no');
				}
			}
			$serialNumber = $serialNumber + 1;
			$tableData .= "\n";
		}

		display($tableData, 1);
		if ($_[0] eq 'backup') {
			display(['enter_the_serial_no_to_select_your' , ucfirst($_[0]), 'location_press_enter_to_go_back_to_main_menu'], 0);
			$slno = getUserMenuChoiceBuckSel(scalar(@{$devices}));
		}
		else {
			display(['enter_the_serial_no_to_select_your' , 'Restore from location.'], 1);
			$slno = getUserMenuChoice(scalar(@{$devices}));
		}

		if ($slno eq '') {
			unless (defined($_[2])) {
				return 0;
			}
			else {
				display('');
				return $_[2]->($devices);
			}
		}
	}
	else {
		$slno = 1;
	}

	if ($_[0] eq 'backup') {
		my $restorePC = 'n';
		if (not defined($_[3]) and ($devices->[$slno -1]{'uid'} =~ /^$AppConfig::deviceUIDPrefix/)) {
			display(["\n", 'setup_new_device_for_backup', "\"$devices->[$slno -1]{'nick_name'}\" ", 'your_settings_will_be_synced_after_successful_account_configuration', 'do_you_want_to_continue_or_skip_yn']);
			$restorePC = lc(getAndValidate(['enter_your_choice'], 'YN_choice', 1));
		}

		my $deviceName = $AppConfig::hostname;
		$deviceName =~ s/[^a-zA-Z0-9_-]//g;

		display('setting_up_your_backup_location', 1);
		$AppConfig::deviceUIDsuffix = $deviceName;
		createUTF8File('LINKBUCKET',
			$deviceName,
			$devices->[$slno -1]{'device_id'},
			getMachineUID()) or retreat('failed_to_create_utf8_file');
		my @result = runEVS('item');

		if ($result[0]->{'STATUS'} eq AppConfig::FAILURE) {
			# print "$result[0]->{'MSG'}\n";
			return 0;
		}
		elsif ($result[0]->{'STATUS'} eq AppConfig::SUCCESS) {
			setUserConfiguration('SERVERROOT', $result[0]->{'server_root'});
			setUserConfiguration('BACKUPLOCATION',
								($AppConfig::deviceIDPrefix . $result[0]->{'device_id'} . $AppConfig::deviceIDSuffix .
									"#" . $result[0]->{'nick_name'}));
			display([ "\n", 'your_backup_to_device_name_is', (" \"" . $result[0]->{'nick_name'} . "\"")]);
			if (loadNotifications() and lockCriticalUpdate("notification")) {
				setNotification('register_dashboard');
				unless (defined($_[4])) {
					my $ncv = ($devices->[$slno -1]{'uid'} . '-' . $devices->[$slno -1]{'device_id'} . '-' . $devices->[$slno -1]{'loc'});
					$ncv .= "-$restorePC";
					setNotification('update_device_info', $ncv);
				}

				saveNotifications();
				unlockCriticalUpdate("notification");
			}

			return (($restorePC eq 'n') ? 1 : 2);
		}
	}
	elsif ($_[0] eq 'restore') {
		setUserConfiguration('RESTOREFROM',
			($AppConfig::deviceIDPrefix . $devices->[$slno -1]{'device_id'} . $AppConfig::deviceIDSuffix .
			"#" . $devices->[$slno -1]{'nick_name'}));
		display([ "\n",'your_restore_from_device_is_set_to', (" \"" . $devices->[$slno -1]{'nick_name'} . "\".")]);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadEVSBinary
# Objective				: Assign evs binary filename to %evsBinary
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub loadEVSBinary {
	my $evs = getEVSBinaryFile();
	my ($status, $msg) = verifyEVSBinary($evs);
	return $status;
}

#*****************************************************************************************************
# Subroutine			: loadMachineHardwareName
# Objective				: Save machine hardware name to $machineHardwareName . This is used to download arch depedent binaries
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub loadMachineHardwareName {
	my $mhnCmd = 'uname -m';
	my $mhn = `$mhnCmd`;
	if ($? > 0) {
		traceLog("Error in getting the machine name: ".$?);
		return 0;
	}

	chomp($mhn);

	if ($mhn =~ /i386|i586|i686/i) {
		$machineHardwareName = '32';
	}
	elsif ($mhn =~ /x86_64|ia64|amd|amd64/i) {
		$machineHardwareName = '64';
	}
	elsif ($mhn =~ /arm/i) {
		$machineHardwareName = 'arm';
	}
	elsif ($mhn =~ /aarch64/i) {
		$machineHardwareName = 'aarch64';
	}
	else {
		$machineHardwareName = undef;
		traceLog("Error in getting the machine name: ".$mhn);
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: loadMachineHardwareName
# Objective				: Save Server address of the current logged in user to $serverAddress
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadServerAddress {
	if(getUserConfiguration('EVSSRVRACCESS')) {
		$serverAddress = getUserConfiguration('EVSSRVR');
		return 1;
	} else {
		my $gsa = getServerAddressFile();
		if (-f $gsa and !-z $gsa) {
			if (open(my $fileHandle, '<', $gsa)) {
				my $sa = <$fileHandle>;
				close($fileHandle);
				Chomp(\$sa);
				if ($sa ne '') {
					$serverAddress = $sa;
					return 1;
				}
			}
		}
	}
	$serverAddress = undef;
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadStorageSize
# Objective				: Save logged in user's available and used space
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadStorageSize {
	my $csf = getCachedStorageFile();
	my @accountStorageDetails;
	my $status = 0;
	if (-f $csf and !-z $csf) {
		if (open(my $s, '<', $csf)) {
			@accountStorageDetails = <$s>;
			for my $keyvaluepair (@accountStorageDetails) {
				my @kvp = split(/=/, $keyvaluepair);
				if (exists $AppConfig::accountStorageSchema{$kvp[0]}) {
					my $func = \&{$AppConfig::accountStorageSchema{$kvp[0]}{'func'}};
					chomp($kvp[1]);
					&$func($kvp[1]);
					$status = 1;
				}
				else {
					#In case if the key value changes then we have to remove the file and retreat.
					$status = 0;
					last;
				}
			}
			close($s);
		}
	}
	return $status;
}

#*****************************************************************************************************
# Subroutine			: loadAppPath
# Objective				: Assign perl scripts path to $appPath
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadAppPath {
	my $absFile = getAbsPath(__FILE__);
	my $replaceStr = getCatfile($AppConfig::idriveLibPath, 'Common.pm');
	my @af = split(/$replaceStr$/, $absFile);
	$appPath = $af[0];
	return 1;
}

#*****************************************************************************************************
# Subroutine			: loadServicePath
# Objective				: Assign saved path of user data to $servicePath
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadServicePath {
	if (inAppPath($AppConfig::serviceLocationFile)) {
		if (open(my $sp, '<',
				("$appPath/" . $AppConfig::serviceLocationFile))) {
			chmod 0777, $sp;
			my $s = <$sp> || '';
			close($sp);
			chomp($s);
			if (-d $s) {
				$servicePath = $s;
				return 1;
			}
		}
	}
	$servicePath = '';
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadUsername
# Objective				: Assign logged in user name to $username
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub loadUsername {
	my $cf = getUserFile();
	if (-f $cf and !-z $cf) {
		if (open(my $u, '<', $cf)) {
			my $userdata = <$u>;
			close($u);
			Chomp(\$userdata);
			my %datahash = ($userdata =~ m/^\{/)? %{JSON::from_json($userdata)} : {$AppConfig::mcUser => $userdata};
			$username = (($datahash{$AppConfig::mcUser}{'userid'})? $datahash{$AppConfig::mcUser}{'userid'} : '');
			# my $isLoggedin = (($datahash{$AppConfig::mcUser}{'isLoggedin'})? $datahash{$AppConfig::mcUser}{'isLoggedin'} : 0);
			# return 0 if ($username eq '' || !$isLoggedin); #Commented for Harish_2.21_07_2
			return 1;
		}
	}
	$username = '';
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadUserConfiguration
# Objective				: Assign user configurations to %userConfiguration
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub loadUserConfiguration {
	my $ucf = getUserConfigurationFile();
	my $errCode = 1;
	if (-f $ucf and !-z $ucf) {
        my $ucc = getFileContents($ucf);
traceLog("ucc:$ucc") if(length($ucc)<4); #Added to debug Harish_2.32_13_3: Senthil
		my $ucj = JSON::from_json(decryptString($ucc));
		foreach my $key(keys %{$ucj}) {
			$userConfiguration{$key} = $ucj->{$key};
		}
		checkAndUpdateServerRoot(); # Added to check and update server root if it is empty
		proxyBackwardCompatability();
		if (defined($_[0])) {
			$errCode = validateUserConfigurations($_[0]);
		}
		else {
			$errCode = validateUserConfigurations();
		}
	} else {
		$errCode = 104;
	}

	foreach my $confkey (keys %AppConfig::userConfigurationSchema) {
		unless($userConfiguration{$confkey}) {
			if ($AppConfig::userConfigurationSchema{$confkey}{'default'} =~ /^__/) {
				my @kNames = $AppConfig::userConfigurationSchema{$confkey}{'default'} =~ /__[A-Za-z0-9]+__/g;
				for(@kNames) {
					$_ =~ s/__//g;
					my $func = \&{$_};
					$userConfiguration{$confkey}{'VALUE'} = &$func();
				}
			}
			else {
				$userConfiguration{$confkey}  = {'VALUE' => $AppConfig::userConfigurationSchema{$confkey}{'default'}};
			}
			$AppConfig::isUserConfigModified = 1;
			if (-f $ucf and !-z $ucf) {
				$errCode =1 ;
			}
		}
	}
	$userConfiguration{'DEDUP'}{'VALUE'} = 'off' if($AppConfig::appType eq 'IBackup');

	return $errCode;
}

#*****************************************************************************************************
# Subroutine			: loadNotifications
# Objective				: load user activities on certain modules like start/stop backup/restore, etc...
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub loadNotifications {
	return 0 if($AppConfig::appType eq 'IBackup');
	%modifiedNotifications = ();

	my $nf = getNotificationFile();
	if (-f $nf) {
		if (-z $nf) {
			%notifications = ();
			return 1;
		}

		if (open(my $n, '<', $nf)) {
			my $nc = <$n>;
			close($n);
			if (defined($nc) and $nc ne '') {
				%notifications = %{JSON::from_json($nc)};
			}
			return 1;
		}
	}
	else {
		open(my $fh, '>', $nf);
		close($fh);
		%notifications = ();
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadNS
# Objective				: load user activities on certain modules like start/stop backup/restore, etc...
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadNS {
	return if ($AppConfig::appType eq 'IBackup');
	%ns = ();

	my $nsf = getNSFile();
	my $nf = getNotificationFile();

	unless (-f $nsf) {
		open(my $fh, '>', $nsf);
		close($fh);
	}

	if (open(my $nsfh, '+<', $nsf)) {
		unless (flock($nsfh, LOCK_EX)) {
			traceLog("Cannot lock file $nsf $!");
			close($nsfh);
			return 0;
		}
		my $nc = <$nsfh>;
		seek $nsfh, 0, 0;
		truncate $nsfh, 0;

		if ($nc and $nc ne '') {
			%ns = %{JSON::from_json($nc)};
		}

		if (open(my $fh, '+<', $nf)) {
			unless (flock($fh, LOCK_EX)) {
				traceLog("Cannot lock file $nf $!");
				close($fh);
				return 0;
			}
			my $nc = <$fh>;
			seek $fh, 0, 0;
			truncate $fh, 0;
			close($fh);

			if ($nc and $nc ne '') {
				my %n = %{JSON::from_json($nc)};
				foreach my $key (keys %n) {
					$ns{'nsq'}{$key} = $n{$key};
				}
			}
		}
		else {
			close($nsfh);
			return 0;
		}

		print $nsfh JSON::to_json(\%ns) if (%ns);
		close($nsfh);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadCrontab
# Objective				: Load crontab data
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadCrontab {
	my $ctf = getCrontabFile();
	my $loggedInUsersCrontab = 0;
	$loggedInUsersCrontab = $_[0] if (defined $_[0]);
	if (-e $ctf and !-z $ctf) {
		my $ctc = getFileContents($ctf);
		if ($ctc ne '') {
			%crontab = %{JSON::from_json(decryptString($ctc))};
			if ($loggedInUsersCrontab) {
				unless (exists $crontab{$AppConfig::mcUser} && exists $crontab{$AppConfig::mcUser}{$username}) {
					return 0;
				}
			}
			return 1;
		}
	}
	%crontab = ();
	return 0;
}

#****************************************************************************************************
# Subroutine Name : loadFullExclude.
# Objective       : This function will load FullExcludePaths to FullExcludeHash.
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub loadFullExclude {
	my @excludeArray;
	my $excludeFullPath = getUserFilePath($AppConfig::excludeFilesSchema{'full_exclude'}{'file'});
	$excludeFullPath   .= '.info';

	#read full path exclude file and prepare a hash for it
	if (-f $excludeFullPath and !-z $excludeFullPath) {
		if (!open(EXFH, $excludeFullPath)) {
			$AppConfig::errStr = getStringConstant('failed_to_open_file')." : $excludeFullPath. Reason:$!\n";
			display($AppConfig::errStr);
			traceLog($AppConfig::errStr);
			return;
		}

		@excludeArray = grep { !/^\s*$/ } <EXFH>;
		close EXFH;
	}

	$AppConfig::fullStr = '' if(-z $excludeFullPath);

	my $currentDir			= getAppPath();
	my $homepath			= $currentDir;
	my $usrpath				= getCatfile('/usr', $currentDir);
	my $idriveServicePath	= getServicePath() . '/';
	my $usrservpath			= getCatfile('/usr', $idriveServicePath);
	my $usrservhomepath		= $idriveServicePath;

	push @excludeArray, ($currentDir, 'enabled');
	push @excludeArray, ($idriveServicePath, 'enabled');

    #Adding mount path to exclude list
    my ($isValidMountPath, $mountedPath) = getAndSetMountedPath(1, 1);
    if($mountedPath) {
        my $expressLocalDir = getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
        push @excludeArray, ($expressLocalDir, 'enabled');
    }

	push @excludeArray, ($usrpath, 'enabled') if(-d $usrpath);
	push @excludeArray, ($usrservpath, 'enabled') if(-d $usrservpath);

	if($homepath =~ /^\/usr\/home\//) {
		$homepath =~ s/^\/usr//;
		push @excludeArray, ($homepath, 'enabled') if(-d $homepath);
	}

	if($usrservhomepath =~ /^\/usr\/home\//) {
		$usrservhomepath =~ s/^\/usr//;
		push @excludeArray, ($usrservhomepath, 'enabled') if(-d $usrservhomepath);
	}

	my @qFullExArr; # What is the use of this variable.
	chomp @excludeArray;

	map{push(@excludeArray, ($_, 'enabled'));} @AppConfig::defexcl;

	for (my $i=0; $i<=$#excludeArray; $i++) {
		if ($excludeArray[$i+1] eq 'enabled') {
			if (substr($excludeArray[$i], -1, 1) eq "/") {
				chop($excludeArray[$i]);
			}
			$backupExcludeHash{$excludeArray[$i]} = 1;
			push(@qFullExArr, "^".quotemeta($excludeArray[$i]).'\/') if ($excludeArray[$i] ne '');
		}
		$i++;
	}

	$AppConfig::fullStr = join("\n", @qFullExArr);
	chomp($AppConfig::fullStr);
	$AppConfig::fullStr =~ s/\n/|/g; # First we join with '\n' and then replacing with '|'?
}

#****************************************************************************************************
# Subroutine Name : loadPartialExclude.
# Objective       : This function will load Partial Exclude string from PartialExclude File.
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar, Sabin Cheruvattil
#*****************************************************************************************************/
sub loadPartialExclude {
	my (@excludeParArray, @qParExArr);
	my $excludePartialPath = getUserFilePath($AppConfig::excludeFilesSchema{'partial_exclude'}{'file'});
	$excludePartialPath   .= '.info';

	$AppConfig::parStr = '';
	#read partial path exclude file and prepare a partial match pattern
	if (-f $excludePartialPath and !-z $excludePartialPath) {
		if (!open(EPF, $excludePartialPath)) {
			$AppConfig::errStr = getStringConstant('failed_to_open_file')." : $excludePartialPath. Reason:$!\n";
			display($AppConfig::errStr);
			traceLog($AppConfig::errStr);
			return;
		}

		@excludeParArray = grep { !/^\s*$/ } <EPF>;
		close EPF;

		chomp(@excludeParArray);
		for(my $i = 0; $i <= $#excludeParArray; $i++) {
			if ($excludeParArray[$i+1] eq 'enabled') {
				$excludeParArray[$i] =~ s/[\s\t]+$//;
				#push(@qParExArr, "^".quotemeta($excludeParArray[$i]).'\/');
				push(@qParExArr, quotemeta($excludeParArray[$i]));
			}
			$i++;
		}
		# $AppConfig::parStr = join("\n", @qParExArr);
		# chomp($AppConfig::parStr);
		# $AppConfig::parStr =~ s/\n/|/g;
	}

	push(@qParExArr, quotemeta("/.")) unless(getUserConfiguration('SHOWHIDDEN'));

	if (scalar(@qParExArr)>0){
		$AppConfig::parStr = join("|", @qParExArr);
		chomp($AppConfig::parStr);
	}
}

#****************************************************************************************************
# Subroutine Name : loadRegexExclude.
# Objective       : This function will load Regular Expression Exclude string from RegexExlude File.
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar, Sabin Cheruvattil
#*****************************************************************************************************/
sub loadRegexExclude {
	my $regexExcludePath = getUserFilePath($AppConfig::excludeFilesSchema{'regex_exclude'}{'file'});
	$regexExcludePath   .= '.info';

	$AppConfig::regexStr = '' if(-z $regexExcludePath);

	#read regex path exclude file and find a regex match pattern
	if (-e $regexExcludePath and -s $regexExcludePath > 0) {
		if (!open(RPF, $regexExcludePath)) {
			$AppConfig::errStr = getStringConstant('failed_to_open_file')." : $regexExcludePath. Reason:$!\n";
			display($AppConfig::errStr);
			traceLog($AppConfig::errStr);
			return;
		}

		my @tmp;
		my @excludeRegexArray = grep { !/^\s*$/ } <RPF>;
		close RPF;

		if (!scalar(@excludeRegexArray)) {
			$AppConfig::regexStr = undef;
		}
		else {
			for(my $i = 0; $i <= $#excludeRegexArray; $i++) {
				chomp($excludeRegexArray[$i+1]);
				if ($excludeRegexArray[$i+1] eq 'enabled') {
					my $a = $excludeRegexArray[$i];
					chomp($a);
					$b = eval { qr/$a/ };
					if ($@) {
						print OUTFILE " Invalid regex: $a";
						traceLog("Invalid regex: $a");
					}
					elsif ($a) {
						push @tmp, $a;
					}
				}
				$i++;
			}
			$AppConfig::regexStr = join("\n", @tmp);
			chomp($AppConfig::regexStr);
			$AppConfig::regexStr =~ s/\n/|/g;
		}
	}
}

#*****************************************************************************************************
# Subroutine	: preUpdateOperation
# In Param		: Lock name | String
# Out Param		: UNDEF
# Objective		: Locks the requested lock file for update
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub lockCriticalUpdate {
	# my ($package, $filename, $line) = caller;
	# traceLog(["LOCK || ", $_[0], " ## $filename ## $line"]);

	my $locktype = $_[0];
	return 0 if(!$locktype);

	my $lockfile = "";
	if($locktype eq "cron") {
		$lockfile = getCatfile(getServicePath(), $AppConfig::userProfilePath, $AppConfig::cronlockfile);
	}
	elsif($locktype eq "notification") {
		$lockfile = getCatfile(getUserProfilePath(), $AppConfig::nslockfile);
	}

	my $fh;
	return 0 if (!open($fh, '>', $lockfile));
	chmod $AppConfig::filePermission, $lockfile;

	if (!flock($fh, LOCK_EX)) {
		traceLog("Unable lock file $lockfile: $!");
		close($fh);
		return 0;
	}

	print $fh $$;

	if($locktype eq "cron") {
		$AppConfig::cronlockfh = $fh;
	}
	elsif($locktype eq "notification") {
		$AppConfig::nslockfh = $fh;
	}
	
	return 1;
}

#*****************************************************************************************************
# Subroutine	: unlockCriticalUpdate
# In Param		: Lock name | String
# Out Param		: UNDEF
# Objective		: Unlocks the requested lock file for update
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub unlockCriticalUpdate {
	# my ($package, $filename, $line) = caller;
	# traceLog(["UNLOCK || ", $_[0], " ## $filename :: $line"]);

	my $locktype = $_[0];
	return 0 if(!$locktype);

	my $lockfile = "";
	if($locktype eq "cron") {
		$lockfile = getCatfile(getServicePath(), $AppConfig::userProfilePath, $AppConfig::cronlockfile);
	}
	elsif($locktype eq "notification") {
		$lockfile = getCatfile(getUserProfilePath(), $AppConfig::nslockfile);
	}

	return 1 if(!-f $lockfile);

	my $fh;
	if($locktype eq "cron") {
		$fh = $AppConfig::cronlockfh;
		$AppConfig::cronlockfh = NULL;
	}
	elsif($locktype eq "notification") {
		$fh = $AppConfig::nslockfh;
		$AppConfig::nslockfh = NULL;
	}

	if($fh) {
		if (!flock($fh, LOCK_UN)) {
			traceLog("Unable unlock file $lockfile: $!");
			eval { close($fh); };
			return 0;
		}

		eval { close($fh); };
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine	: loadAndWriteAsJSON
# In Param		: Path, hash
# Out Param		: Status | Boolean
# Objective		: Loads the JSON from file, writes the merged data to the file as JSON
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub loadAndWriteAsJSON {
	my $wfile = $_[0];
	my $whash = $_[1]? $_[1] : {};
	my %nhash = ();

	return 0 if(!$wfile);

	%nhash = %{readJSONFileToHash($wfile)};
	%nhash = (%nhash, %{$whash});

	writeAsJSON($wfile, \%nhash);
}

#------------------------------------------------- M -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: migrateUserFile
# Objective				:
# Added By				: Vijay Vinoth, Yogesh Kumar
#****************************************************************************************************/
sub migrateUserFile
{
	my $filename = getOldUserFile();
	my $idriveFilename = getUserFile();
	my $userServiceLocationFile = "$appPath/$AppConfig::serviceLocationFile";
	my $ServiceLocation = getServicePath();
	my $fc = '';

	if (-f $filename){
		$fc = getFileContents($filename);
		Chomp(\$fc);
	}

	my $migrateLockFile = getMigrateLockFile();
	open MIGRATEMCDATA, "<$migrateLockFile";
	my $migrateMcUser = <MIGRATEMCDATA>;
	close MIGRATEMCDATA;
	Chomp(\$migrateMcUser);

	my %loginData	= ();
	if ($fc ne ''){
		$loginData{$migrateMcUser}{'userid'} = $fc;
		$loginData{$migrateMcUser}{'isLoggedin'} = 1;
	}
	migrateUserDirectories($migrateMcUser,$fc);
	createDir(getCachedDir(),1) unless(-d getCachedDir());

	my $ServiceLocationOld = $ServiceLocation;
	$ServiceLocation =~ s/$AppConfig::oldServicePathName$/$AppConfig::servicePathName/;

	rmtree($ServiceLocationOld."/".$AppConfig::userProfilePath);
	unlink $filename;

	fileWrite($idriveFilename, JSON::to_json(\%loginData));
	chmod $AppConfig::filePermission, $idriveFilename if(-f $idriveFilename);
	createDir($ServiceLocation,1) unless(-d $ServiceLocation);
	system(updateLocaleCmd("cp -rpf \'$ServiceLocationOld/\'* \'$ServiceLocation\'"));

	removeItems($ServiceLocationOld) if ($? == 0);
	fileWrite($userServiceLocationFile,$ServiceLocation);

	loadUsername();
	my $mcUserCFCmd = updateLocaleCmd('whoami');
	$AppConfig::mcUser = `$mcUserCFCmd`;
	chomp($AppConfig::mcUser);
	setServicePath($ServiceLocation);
}

#*****************************************************************************************************
# Subroutine			: migrateUserDirectories
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserDirectories {
    return 1 unless (-d "$servicePath/$AppConfig::userProfilePath");

	opendir(DIR, "$servicePath/$AppConfig::userProfilePath") or die $!;
	my $mcUser = "";
	my $fileName = "";
	my $fileStat = "";

	my $migrateLockFile = getMigrateLockFile();
    while (my $userDir = readdir(DIR)) {
        # Use a regular expression to ignore files beginning with a period
        next if ($userDir =~ m/^\./);
		$fileName = "$servicePath/$AppConfig::userProfilePath/$userDir";

		next if (!-e $fileName."/Backup");

		$fileStat = stat($fileName);
		$mcUser = getpwuid($fileStat->uid);
		if ($userDir eq $_[1]){
			$mcUser = $_[0];
			$fileStat = stat($migrateLockFile);
		}
		migrateUserPath($mcUser,$userDir,$fileStat);
    }

    closedir(DIR);
}

#*****************************************************************************************************
# Subroutine			: migrateUserPath
# Objective				: This will update older service path structue to latest one.
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub migrateUserPath{
	my $mcUser = $_[0];
	my $idriveUser = $_[1];
	my $fileStat = $_[2];
	my $groupUser = getpwuid($fileStat->gid);
	$groupUser = (defined($groupUser))?$groupUser:'root';
	my $linuxUserDir = "$servicePath/$AppConfig::userProfilePath/$mcUser";
	my $idriveUserOldDir = "$servicePath/$AppConfig::userProfilePath/$idriveUser";
	my $idriveUserDir = "$linuxUserDir/$idriveUser";

	$linuxUserDir = $linuxUserDir."_tmp"	if ($linuxUserDir eq $idriveUserOldDir);

	createDir($linuxUserDir) if (!-e $linuxUserDir);

	system(updateLocaleCmd('cp -rpf '.getECatfile($servicePath, $AppConfig::userProfilePath, $idriveUser).' '. getECatfile($linuxUserDir, '/')));
	removeItems("$servicePath/$AppConfig::userProfilePath/$idriveUser") if ($? == 0);

	if ($idriveUserOldDir."_tmp" eq $linuxUserDir){
		system(updateLocaleCmd('mv '.getECatfile($linuxUserDir).' '.getECatfile($idriveUserOldDir)));
	}

	setUsername($idriveUser);
	$AppConfig::mcUser = $mcUser;
	lockCriticalUpdate("cron");
	loadCrontab(1);

	my @jobTypes = ("backup", "archive");
	for my $i (0 .. $#jobTypes) {
		createCrontab($jobTypes[$i], "default_backupset") or retreat('failed_to_load_crontab');
	}

	createCrontab("cancel", "default_backupset") or retreat('failed_to_load_crontab');

	migrateUserLogs($idriveUserDir);
	migrateUserJobDirectories($idriveUserDir);
	migrateExcludeFileset($idriveUserDir);
	migrateCronEntry($idriveUserOldDir);

	my $updatedServiceLocation = $servicePath;
	$updatedServiceLocation =~ s/$AppConfig::oldServicePathName$/$AppConfig::servicePathName/;
	migrateConfigData($idriveUserOldDir, "$updatedServiceLocation/$AppConfig::userProfilePath/$mcUser/$idriveUser");

    createLogJsonForOldUser();
	migrateUserNewServiceLocation("$updatedServiceLocation/$AppConfig::userProfilePath/$mcUser",$idriveUserDir);
	system(updateLocaleCmd("chown -R  $mcUser:$groupUser ".getECatfile($updatedServiceLocation,$AppConfig::userProfilePath,$mcUser,$idriveUser)." 2>/dev/null"));
	system(updateLocaleCmd("chmod -R 0755 ".getECatfile($updatedServiceLocation,$AppConfig::userProfilePath,$mcUser,$idriveUser,'/')." 2>/dev/null"));
}

#*****************************************************************************************************
# Subroutine			: migrateUserLogs
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserLogs
{
	my $idriveUserDir = $_[0];
	#rename log files for local backup
	customReName("$idriveUserDir/LocalBackup/Manual/$AppConfig::logDir/",'$',"_Manual");

	#rename log files for manual backup
	customReName("$idriveUserDir/Backup/Manual/$AppConfig::logDir/",'$',"_Manual");

	#rename log files for schedule backup
	customReName("$idriveUserDir/Backup/Scheduled/$AppConfig::logDir/",'$',"_Scheduled");

	#rename log files for schedule restore
	customReName("$idriveUserDir/Restore/Scheduled/$AppConfig::logDir/",'$',"_Scheduled");

	#rename log files for manual restore
	customReName("$idriveUserDir/Restore/Manual/$AppConfig::logDir/",'$',"_Manual");

	#rename log files for schedule Archive
	customReName("$idriveUserDir/Archive/Scheduled/$AppConfig::logDir/",'$',"_Scheduled");

	#rename log files for manual Archive
	customReName("$idriveUserDir/Archive/Manual/$AppConfig::logDir/",'$',"_Manual");
}

#*****************************************************************************************************
# Subroutine			: migrateUserJobDirectories
# Objective				:
# Added By				: Vijay Vinoth
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserJobDirectories
{
	my $idriveUserDir = $_[0];
	my $errorFile = "\'$idriveUserDir/$AppConfig::traceLogFile\'";
	my $errorSkip = " 1>>$errorFile 2>>$errorFile";
	my $backupSetPath = $idriveUserDir."/".$AppConfig::userProfilePaths{'backup'}."/".$AppConfig::backupsetFile;
	my $localBackupSetPath = $idriveUserDir."/".$AppConfig::userProfilePaths{'localbackup'}."/".$AppConfig::backupsetFile;

	#move local backup job to new location
	createDir("$idriveUserDir/$AppConfig::userProfilePaths{'localbackup'}",1) if (!-e "$idriveUserDir/$AppConfig::userProfilePaths{'localbackup'}");

	if (-e "$idriveUserDir/LocalBackup/Manual/"){
		system(updateLocaleCmd('cp -rpf '. getECatfile($idriveUserDir, 'LocalBackup', 'Manual', '/') . '* ' . getECatfile($idriveUserDir, $AppConfig::userProfilePaths{'localbackup'}) . " $errorSkip"));
		removeItems("$idriveUserDir/LocalBackup/Manual/") if ($? == 0);
	}

	if (-e $localBackupSetPath and !-z $localBackupSetPath) {
		updateJobsFileset($localBackupSetPath,'localbackup');
	}

	removeItems("$idriveUserDir/LocalBackup/") if ($? == 0);

	#move scheulde backup job to new location
	system(updateLocaleCmd('mv '.getECatfile($idriveUserDir,'Backup','Scheduled','/').' '. getECatfile($idriveUserDir,$AppConfig::userProfilePaths{'backup'})." $errorSkip"));

	if (-e $backupSetPath and !-z $backupSetPath) {
		updateJobsFileset($backupSetPath,'backup');
	}

	#move manual backup logs to new location
	createDir($idriveUserDir . "/" . $AppConfig::userProfilePaths{'backup'}, 1)	if (!-e $idriveUserDir."/".$AppConfig::userProfilePaths{'backup'});

	createDir($idriveUserDir . "/" . $AppConfig::userProfilePaths{'backup'} . "/LOGS", 1)	if (!-e $idriveUserDir."/".$AppConfig::userProfilePaths{'backup'}."/LOGS");

	if (-e $idriveUserDir."/".$AppConfig::userProfilePaths{'backup'}."/LOGS"){
		system(updateLocaleCmd('cp -rpf '.getECatfile($idriveUserDir,'Backup','Manual','LOGS','/').'* '.getECatfile($idriveUserDir,$AppConfig::userProfilePaths{'backup'},'LOGS','/')." $errorSkip"));
	}
	removeItems("$idriveUserDir/Backup/Manual/");

	#move scheulde restore job to new location
	if (-e "$idriveUserDir/Restore/Scheduled/"){
		system(updateLocaleCmd('mv '.getECatfile($idriveUserDir,'Restore','Scheduled','/').' '.getECatfile($idriveUserDir,$AppConfig::userProfilePaths{'restore'})." $errorSkip"));
	}

	#move manual restore logs to new location
	createDir($idriveUserDir."/".$AppConfig::userProfilePaths{'restore'},1)	if (!-e $idriveUserDir."/".$AppConfig::userProfilePaths{'restore'});

	createDir($idriveUserDir."/".$AppConfig::userProfilePaths{'restore'}."/LOGS",1)	if (!-e $idriveUserDir."/".$AppConfig::userProfilePaths{'restore'}."/LOGS");

	if (-e $idriveUserDir."/".$AppConfig::userProfilePaths{'restore'}."/LOGS"){
		system(updateLocaleCmd('cp -rpf '.getECatfile($idriveUserDir,'Restore','Manual','LOGS','/').'* '.getECatfile($idriveUserDir,$AppConfig::userProfilePaths{'restore'},'LOGS','/')." $errorSkip"));
	}

	removeItems("$idriveUserDir/Restore/Manual/");

	#move scheulde Archive job to new location
	if (-e "$idriveUserDir/Archive/Scheduled/"){
		system(updateLocaleCmd('mv '.getECatfile($idriveUserDir,'Archive','Scheduled','/').' '.getECatfile($idriveUserDir,$AppConfig::userProfilePaths{'archive'})." $errorSkip"));
	}

	#move manual Archive logs to new location
	createDir($idriveUserDir."/".$AppConfig::userProfilePaths{'archive'},1)	if (!-e $idriveUserDir."/".$AppConfig::userProfilePaths{'archive'});

	createDir($idriveUserDir."/".$AppConfig::userProfilePaths{'archive'}."/LOGS",1)	if (!-e $idriveUserDir."/".$AppConfig::userProfilePaths{'archive'}."/LOGS");

	if (-e "$idriveUserDir/Archive/Manual/LOGS/"){
		system(updateLocaleCmd('cp -rpf '.getECatfile($idriveUserDir,'Archive','Manual','LOGS','/').'* '.getECatfile($idriveUserDir,$AppConfig::userProfilePaths{'archive'},'LOGS','/')." $errorSkip"));
	}

	chmod $AppConfig::filePermission, "$idriveUserDir/$AppConfig::traceLogFile" if (-e "$idriveUserDir/$AppConfig::traceLogFile");
	removeItems("$idriveUserDir/Archive/Manual/");
}

#*****************************************************************************************************
# Subroutine			: migrateExcludeFileset
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateExcludeFileset{
	my $idriveUserDir = $_[0];
	my $fullExcludeListPath = $idriveUserDir."/".$AppConfig::fullExcludeListFile;
	my $partialExcludeListPath = $idriveUserDir."/".$AppConfig::partialExcludeListFile;
	my $regexExcludeListPath = $idriveUserDir."/".$AppConfig::regexExcludeListFile;

	if (-e $fullExcludeListPath and !-z $fullExcludeListPath) {
		updateExcludeFileset($fullExcludeListPath);
	}
	if (-e $partialExcludeListPath and !-z $partialExcludeListPath) {
		updateExcludeFileset($partialExcludeListPath);
	}
	if (-e $regexExcludeListPath and !-z $regexExcludeListPath) {
		updateExcludeFileset($regexExcludeListPath);
	}

}

#*****************************************************************************************************
# Subroutine			: migrateCronEntry
# Objective				:
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub migrateCronEntry{
	my $fc 			= getFileContents('/etc/crontab');
	my @fields = split /\n/, $fc;
	my $i=0;
	my @timeDetail = ();
	my $jobName = '';
	my $jobType = '';
	my $idriveUserOldDir = $_[0];
	while ($i<=$#fields) {
		@timeDetail = ();
		my $emailNotify = '';
		if (index($fields[$i], $idriveUserOldDir) != -1) {
			my @timeDetail = split / /, $fields[$i];
			if ((index($fields[$i], 'Restore_Script.pl') != -1) or (index($fields[$i], '/Restore/Scheduled') != -1)){
				$i++;
				next;
			}
			if (index($fields[$i], 'Backup_Script.pl') != -1){
				$emailNotify = "$servicePath/$AppConfig::userProfilePath/$AppConfig::mcUser/$username/$AppConfig::userProfilePaths{'backup'}/BackupmailNotify.txt";
				$jobType = 'backup';
				$jobName = 'default_backupset';
			}
			elsif (index($fields[$i], 'archive_cleanup.pl') != -1){
				my $perlPathCmd = updateLocaleCmd('which perl');
				my $perlPath = `$perlPathCmd`;
				chomp($perlPath);
				if ($perlPath eq ''){
					$perlPath = '/usr/local/bin/perl';
				}
				my @cmdDetails = split /$perlPath/, $fields[$i];
				my $customCmd = $cmdDetails[1];
				my @params = split(' ', $customCmd);
				my $paramSize = @params;
				$params[$paramSize-1] =~ s/\'//g;
				$params[$paramSize-2] =~ s/\'//g;
				my $tmpData = $params[$paramSize-2];
				$params[$paramSize-3] =~ s/\'//g;
				$params[$paramSize-2] = $params[$paramSize-3];
				$params[$paramSize-3] = $tmpData;
				$customCmd = join( " ", @params );

				$jobType = 'archive';
				$jobName = 'default_backupset';
				setCrontab($jobType, $jobName, {'cmd' => $customCmd});
			}
			elsif (index($fields[$i], 'job_termination.pl') != -1){
				$jobType = 'cancel';
				$jobName = 'default_backupset';
			}

			Chomp(\$timeDetail[0]);
			Chomp(\$timeDetail[1]);
			Chomp(\$timeDetail[4]);
			my $dow = lc $timeDetail[4];

			setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
			if ($timeDetail[1] eq "*") {
				setCrontab($jobType, $jobName, 'h', '*');
			} else {
				setCrontab($jobType, $jobName, 'h', sprintf("%02d", $timeDetail[1]));
			}

			if ($timeDetail[0] eq "*") {
				setCrontab($jobType, $jobName, 'm', '*');
			} else {
				setCrontab($jobType, $jobName, 'm', sprintf("%02d", $timeDetail[0]));
			}

			if ($timeDetail[4] eq "*"){
				setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'daily'}});
			} else {
				setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'weekly'}});
				setCrontab($jobType, $jobName, {'dow' => $dow});
			}

			if ($emailNotify ne ''){
				if (!-e $emailNotify ){
					setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
				}else{
					if (open NOTIFYFILE, "<", $emailNotify) {
						my @notifyData = <NOTIFYFILE>;
						chomp(@notifyData);
						my $notifyFlag = lc $notifyData[0];
						my $notifyEmailIds = $notifyData[1];
						close(NOTIFYFILE);
						if ($notifyFlag eq "enabled"){
							setCrontab($jobType, $jobName, {'settings' => {'emails' => {'ids' => $notifyEmailIds}}});
						}
						setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => $AppConfig::notifOptions{'notify_always'}}}});
					}else{
						setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
					}

					unlink($emailNotify) if (-f $emailNotify);
				}
			}

			setCronCMD($jobType, $jobName) unless ($jobType eq 'archive');
		}
		$i++;
	}
	createCrontab($AppConfig::dashbtask, $AppConfig::dashbtask);
	setCronCMD($AppConfig::dashbtask, $AppConfig::dashbtask);
	saveCrontab();
	unlockCriticalUpdate("cron");
}
#*****************************************************************************************************
# Subroutine			: migrateConfigData
# Objective				: Migrate configuration data
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateConfigData {
	my $idriveUserOldPath = $_[0];
	my $idriveUserNewPath = $_[1];
	my $userConf = getUserConfigurationFile();
	my $userConfTmp = getUserConfigurationFile()."_tmp";

	return if (!-e $userConf);

	# Open file to read
	open(DATA1, "<$userConf");

	# Open new file to write
	open(DATA2, ">$userConfTmp");

	# Copy data from one file to another.
	while(<DATA1>) {
		$_ =~ s/$idriveUserOldPath/$idriveUserNewPath/ig;
		print DATA2 $_;
	}
	close( DATA1 );
	close( DATA2 );

	unlink $userConf if (-e $userConfTmp and -s $userConfTmp > 0);

	loadUserConfiguration();

	if (-f $userConfTmp and !-z $userConfTmp) {
		tie(my %newuserconfs, 'Tie::IxHash');
		map{$newuserconfs{$_} = ''} keys %AppConfig::userConfigurationSchema;
		if (open(my $uc, '<', $userConfTmp)) {
			my @u = <$uc>;
			close($uc);
			map{my @x = split(/ = /, $_); chomp($x[1]); $x[1] =~ s/^\s+|\s+$//g; $newuserconfs{$x[0]} = $x[1];} @u;

			setUserConfiguration(\%newuserconfs);
			for my $key (keys %AppConfig::userConfigurationSchema) {
				if (($AppConfig::userConfigurationSchema{$key}{'default'} ne '') and
					(getUserConfiguration($key) eq '')) {
					setUserConfiguration($key, $AppConfig::userConfigurationSchema{$key}{'default'});
				}
			}
			saveUserConfiguration(undef,1);
			chmod $AppConfig::filePermission, $userConf;
			unlink $userConfTmp;
		}
	}
}

#*****************************************************************************************************
# Subroutine			: migrateUserNewServiceLocation
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserNewServiceLocation{
	my $newServiceLocation = $_[0];
	my $idriveUserDir = $_[1];
	my $errorFile = "\'$newServiceLocation/$AppConfig::traceLogFile\'";
	my $errorSkip = " 1>>$errorFile 2>>$errorFile";

	createDir($newServiceLocation, 1);
	chmod $AppConfig::filePermission, $newServiceLocation;
	system(updateLocaleCmd('mv '.getECatfile($idriveUserDir).' '.getECatfile($newServiceLocation)." $errorSkip"));
	chmod $AppConfig::filePermission, "$newServiceLocation/$AppConfig::traceLogFile" if (-e "$newServiceLocation/$AppConfig::traceLogFile");
}

#*****************************************************************************************************
# Subroutine			: makeRequest
# Objective				: make requests to IDrive server
# Added By				: Yogesh Kumar
# Modified By           : Senthil Pandian
#****************************************************************************************************/
sub makeRequest {
	unless (-f getCatfile(getAppPath(), $AppConfig::idrivePythonBinPath, $AppConfig::pythonBinaryName)) {
		retreat(['unable_to_find_python_binary']);
	}

	# my $filename = time() . $_[0];
    my $filename = time();
    $filename .= $_[0] if($_[0] ne '' and $_[0] =~ /^\d+$/);
	my $file = getCatfile(getServicePath(), $filename);
	if (defined($_[1])) {
		unless (defined($_[2])) {
			if (open(my $fh, ">", $file)) {
				print $fh pack("u", JSON::to_json($_[1]));
				close($fh);
			}
		}
		else {
			my $count = 1;
			foreach (@{$_[1]}){
				if (open(my $fh, ">", ($file . ".$count"))) {
					print $fh $_;
					$count += 1;
					close($fh);
				}
			}
		}
	}

	if (getProxyStatus() and getProxyDetails('PROXYIP')) {
		my $proxy = getProxyDetails('PROXYIP');

		if (getProxyDetails('PROXYPORT')) {
			$proxy .= (':' . getProxyDetails('PROXYPORT'))
		}

		if (getProxyDetails('PROXYUSERNAME')) {
			my $pu = getProxyDetails('PROXYUSERNAME');
			if (getProxyDetails('PROXYPASSWORD')) {
				my $ppwd = getProxyDetails('PROXYPASSWORD');
				$ppwd = ($ppwd ne '') ? decryptString($ppwd) : $ppwd;
				$pu .= (":" . $ppwd);
			}
			$proxy = ($pu . "@" . $proxy);
		}
		if (open(my $fh, ">", "$file.p")) {
			print $fh pack("u", $proxy);
			close($fh);
		}
	}

	my $cmd = getECatfile(getAppPath(), $AppConfig::idrivePythonBinPath, $AppConfig::pythonBinaryName);
	$cmd .= " $_[0] $filename";
	unless (looks_like_number($_[0]) and (($_[0] == 111) or ($_[0] == 1) or ($_[0] == 20) or ($_[0] == 21))) {
		$cmd .= " 2>/dev/null";
	}

	my $res = `$cmd`;

	removeItems([$file, "$file.p"]);#Added for Snigdha_2.3_11_6: Senthil
	unless ($res) {
		retreat(['failed_to_connect', ". ", 'please_try_again']);
	}

    #Condition modified for Suruchi_2.3_02_3: Senthil
	if (defined($_[1]) or ($_[0] =~ /^\d+$/ and $_[0] == 12)) {
		return JSON::from_json($res);
	}
	else {
		return $res;
	}
}

#*****************************************************************************************************
# Subroutine		: migrateLocalBackupCronEntry
# Objective			: Check and migrate the Local Backup Cron Entry. 
#                     Change script "express_backup.pl" to "local_backup.pl"
# Added By 			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub migrateLocalBackupCronEntry{
	lockCriticalUpdate("cron");
	loadCrontab();
	my %crontab    = %{getCrontab()};
	my $currentDir = getAppPath();
    my $modified   = 0;

    foreach my $mcUser (keys %crontab){
        foreach my $idriveUser (keys %{$crontab{$mcUser}}){
            my $cmd = $crontab{$mcUser}{$idriveUser}{'backup'}{'local_backupset'}{'cmd'};
            if ($cmd and $cmd ne '' and $cmd =~ /$currentDir/) {
                $cmd =~ s/express_backup.pl/local_backup.pl/;
                $crontab{$mcUser}{$idriveUser}{'backup'}{'local_backupset'}{'cmd'} = $cmd;
                $modified = 1;
            }
        }
    }

    saveCrontab() if($modified);
	unlockCriticalUpdate("cron");
}

#------------------------------------------------- N -------------------------------------------------#

#------------------------------------------------- O -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: openEditor
# Objective				: This subroutine to view/edit the files using Linux editor
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub openEditor {
	my $action       = $_[0];
	my $fileLocation = $_[1];
	my $fileType     = $_[2];
    my $altfiles     = $_[3];

	my $editorName      = ((getUserConfiguration('DEFAULTTEXTEDITOR') ne '')? getUserConfiguration('DEFAULTTEXTEDITOR') : getEditor());
	my $editorHelpMsg   = $editorName;
	my $operationStatus = 1;
	my ($readOnlyModePrefix, $readOnlyModePostfix, $postFix) = ('') x 3;

	if ($editorName =~ /vi/){
		$editorHelpMsg 		= 'vi';
		$readOnlyModePrefix = ' -R';

		#check if vi is symbolically linked to vim
		$readOnlyModePrefix = ' -M' if (`readlink -f \`which vi\` 2>/dev/null` =~ m/vim/);

	}
	elsif ($editorName =~ /nano/){
		$editorHelpMsg 		= 'nano';
		$readOnlyModePrefix = ' -v';
	}
	# unable to find read-only mode option
	# elsif ($editorName =~ /ee/){
	# 	$editorHelpMsg 		= 'ee';
	# }
	elsif ($editorName =~ /emacs/){
		$editorHelpMsg 		 = 'emacs';
		$readOnlyModePostfix = " --eval '(setq buffer-read-only t)'";
	}
	elsif ($editorName =~ /ne/){
		$editorHelpMsg      = 'ne';
		$readOnlyModePrefix = ' --read-only';
	}
	# unable to find read-only mode option
	# elsif ($editorName =~ /jed/){
	# 	$editorHelpMsg = 'jed';
	# }

	my $editorNameCmd = updateLocaleCmd("which $editorName 2>/dev/null");
	if(`$editorNameCmd` eq "" || $editorName !~ m/vi|nano|emacs|ne/) {
		display(["\n", 'unable_to_find_editor']);
		display(['please_provide_name_of_editor_in_machine', ': '], 0);
		my $custeditor = getUserChoice();

		retreat(['unable_to_proceed', ' ', 'please_make_sure_you_have_editor']) unless($custeditor);
		my $custeditorCmd = updateLocaleCmd("which $custeditor 2>/dev/null");
		retreat(['unable_to_proceed', ' ', 'unable_to_find_entered_editor']) unless(`$custeditorCmd`);

		$editorName = $custeditor;
		$editorHelpMsg = $editorName;
		setUserConfiguration('DEFAULTTEXTEDITOR', $custeditor);
		# saveUserConfiguration();
	}

	display(["\n", 'press_keys_to_close_' . $editorHelpMsg . '_editor'], 1) if ($action eq 'edit');
	display(["\n", 'press_keys_to_quit_' . $editorHelpMsg . '_editor'], 1) if ($action eq 'view');
	display(["\n", 'opening_file_to_' . $action, "\n"], 1);
	sleep(4);

	if($action eq 'view') {
		$fileLocation = (-f $fileLocation)? $fileLocation : $altfiles;
		$editorName .= $readOnlyModePrefix;
		$postFix = $readOnlyModePostfix;

		# Duplicating the file to be viewed
		if(defined($fileLocation) and -f $fileLocation) {
			my $tmpPath = $fileLocation;
			$fileLocation = $tmpPath."_temp";
			system("cp -fp '$tmpPath' '$fileLocation'");
		}
		retreat(["\n", 'file_not_found', ":$fileLocation\n"]) if (!defined($fileLocation) or !-f "$fileLocation");
	}

	my $initialts = ((-f $fileLocation)? stat($fileLocation)->mtime : 0);
	$operationStatus = system(updateLocaleCmd("$editorName '$fileLocation'$postFix"));
	my $editedts = ((-f $fileLocation)? stat($fileLocation)->mtime : 0);

	Common::removeItems($fileLocation) if($action eq 'view'); #Removing duplicated temp file 

	return display(["\n", 'could_not_complete_operation', " Reason: $!\n"], 1) if ($operationStatus != 0);
	return if ($action ne 'edit');

	my @itemsarr;
	if($fileType =~ /backup/i || $fileType =~ /restore/i) {
		processAndSaveJobsetContents($fileLocation, $fileType, $fileLocation, 0);
		createScanRequest(dirname($fileLocation) . '/', basename(dirname($fileLocation)), 1, $fileType) if($fileType =~ /backup/i);
		display('') if ($skippedItem);
	} elsif($fileType =~ /full/i) {
		@itemsarr = verifyEditedFileContent($fileLocation);
		if (scalar(@itemsarr)) {
			my %uniqhash	= getUniquePresentData(\@itemsarr, $fileType, 1);
			%uniqhash		= skipChildIfParentDirExists(\%uniqhash);
			@itemsarr		= keys %uniqhash;
		}
	} elsif($fileType =~ /regex/i) {
		@itemsarr = verifyEditedFileContent($fileLocation,$fileType);
    } elsif($fileType =~ /partial/i) {
		my $fc = getFileContents($fileLocation, 'array');
		@itemsarr = @{$fc};
	}

	if($fileType =~ /exclude/i) {
		my %index = ();
		# remove empty items
		@itemsarr = grep{$_} @itemsarr;

		# remove duplicates
		@itemsarr = grep{!$index{$_}++} @itemsarr;
		my $content = '';
		$content = join("\n", @itemsarr) if (scalar(@itemsarr));

		fileWrite($fileLocation, $content);
		display('') if ($skippedItem);
	}

	if ($initialts != $editedts or $skippedItem) {
        if($fileType =~ /exclude/i) {
            setUserConfiguration('EXCLUDESETUPDATED', 1);
            saveUserConfiguration();
        }
		$fileType = exists($LS{$fileType})? getStringConstant($fileType) . "set" : $fileType if ($fileType);
		return display([$fileType, 'has_been_edited_successfully', "\n"], 1);
	}

	return display(['no_changes_has_been_made', "\n"], 1);
}

#------------------------------------------------- P -------------------------------------------------#

#*****************************************************************************************************
# Subroutine	: pauseOrResumeEVSOp
# In Param		: 1.JobRunningDir 2.'p' or 'r'
# Out Param		: 
# Objective		: This subroutine to update the bandwidth throttle value in bw.txt file.
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub pauseOrResumeEVSOp {
	my $jobRunningDir = $_[0];
	my $status        = $_[1];
	my $bwPath        = "$jobRunningDir/bw.txt";

	if($status eq 'p'){
		fileWrite($bwPath, '-1') or traceLog(['failed_to_open_file', " : ", $bwPath]);
		chmod $AppConfig::filePermission, $bwPath;
	} elsif($status eq 'r') {
		my $jobBWPath  = getUserProfilePath()."/bw.txt";
		system("cp -f '$jobBWPath' '$bwPath'") if(-f $jobBWPath);
	}
}

#*************************************************************************************************
# Subroutine		: processAndSaveJobsetContents
# Objective			: Processes jobset contents and save it in job set file
# Added By			: Sabin Cheruvattil
# Modified By		: Deepak Chaurasia, Yogesh Kumar
#*************************************************************************************************
sub processAndSaveJobsetContents {
	my $item		= $_[0];
	my $fileType	= $_[1];
	my $jbsfile		= $_[2];
	my $dashboard	= $_[3];
	my $realkey 	= '';
	my @itemsarr;
	my %backupSet	= ();

	@itemsarr = $dashboard? (keys(%{$item})) : @{getFileContents($item, 'array')};
	if(!$dashboard) {
		@itemsarr = uniqueData(@itemsarr);
	}

	if ($fileType =~ /backup/i) {
		$jbsfile	= getCatfile(dirname($jbsfile), $AppConfig::backupsetFile);
		@itemsarr	= verifyEditedFileContent(\@itemsarr);

		if(scalar(@itemsarr) > 0) {
			%backupSet = getLocalDataWithType(\@itemsarr, 1);
			%backupSet = skipChildIfParentDirExists(\%backupSet, !$dashboard);
		}
	}
	elsif($fileType =~ /restore/) {
		if($dashboard) {
			%backupSet = map{$_ => 1} keys %{$item};
		}
		else{
			@itemsarr = verifyEditedFileContent(\@itemsarr);
			if(scalar(@itemsarr) > 0) {
				if($fileType eq 'localrestore') {
                    my $mountedPath = getUserConfiguration('LOCALRESTOREMOUNTPOINT');
                    checkAndStartDBReIndex($mountedPath);
					%backupSet = getDBDataWithType(\@itemsarr);
					Sqlite::disconnectExpressDB();
				} else {
				    %backupSet = getRemoteDataWithType(\@itemsarr);	
				}
			}
			%backupSet = skipChildIfParentDirExists(\%backupSet, !$dashboard);
		}
	}

	@itemsarr	= keys(%backupSet);

	my $jscontent = '';
	$jscontent = join("\n", @itemsarr) if (scalar(@itemsarr));

	if ($fileType =~ /backup/i) {
		saveEncryptedBackupset($jbsfile, $jscontent);
	} else {
		fileWrite($jbsfile, $jscontent);
	}

	my %backupSetInfo;
	if ($fileType =~ /backup/) {
		%backupSetInfo = %{JSON::from_json(getFileContents("$jbsfile.json"))} if(-f "$jbsfile.json");
		my %newBackupSetInfo = ();
		foreach my $key (keys %backupSet) {
			# avoid recalculating on adding filenames
			if (defined($backupSetInfo{$key}) and
					($backupSetInfo{$key}{'size'} != -1) and
					($backupSetInfo{$key}{'type'} ne 'f')) {
				$newBackupSetInfo{$key} = $backupSetInfo{$key};
			}

			$realkey = $key;
			$realkey =~ s/\/$// if($dashboard && !exists($item->{$realkey}));

			$newBackupSetInfo{$key} = {
				'size' => -f $key? -s $key : -1,
				'ts'   => '',
				'filecount' => 'NA',
				'type' => $dashboard? $item->{$realkey}{'type'} : $backupSet{$key}{'type'},
			}
		}

		fileWrite("$jbsfile.json", JSON::to_json(\%newBackupSetInfo));
	} elsif($fileType =~ /restore/) {
		my %backupsetsizes = (-f "$jbsfile.json")? %{JSON::from_json(getFileContents("$jbsfile.json"))} : ();

		foreach my $key (keys %backupSet) {
			$realkey = $key;
			$realkey =~ s/\/$// if($dashboard && !exists($item->{$realkey}));

			if (exists $backupsetsizes{$key}) {
				$backupSetInfo{$key} = $backupsetsizes{$key};
			}
			else {
				$backupSetInfo{$key} = {
					'size' => (($dashboard && exists $item->{$realkey}{'size'})? $item->{$realkey}{'size'} : -1),
					'ts'   => '',
					'filecount' => '-1',
					'type' => $dashboard? $item->{$realkey}{'type'} : $backupSet{$key}{'type'},
				};
			}
		}

		fileWrite2("$jbsfile.json", JSON::to_json(\%backupSetInfo));
	}

	if($fileType =~ /backup/) {
		my $obsf	= qq($jbsfile$AppConfig::backupextn);
		if(!-f $obsf || !isBackupsetSame($jbsfile, $obsf)) {
			addToEditBackupsetHistory($jbsfile);
		}
	}
}

#*************************************************************************************************
# Subroutine		: processDedupUpdateDelete
# Objective			: Process file status if web activity is present
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian
#*************************************************************************************************
sub processDedupUpdateDelete {
	# keep this commented | code review
	# display(['verifying_sync_items', '. ', 'please_wait', '...']) if($_[0]);
	my $retry = 0;
START:
	my $loopmax		= 4;
	my $utf8path	= getCatfile(getJobsPath('backup'), $AppConfig::utf8File);
	my $outputpath	= getCatfile(getJobsPath('backup'), $AppConfig::evsOutputFile);

	# max 5 retries for web index checking.
	while($loopmax) {
		createUTF8File(['CHANGEINDEX', $utf8path], getUserConfiguration('LASTFILEINDEX'), $outputpath);
		my @resp = runEVS('item');

		if(defined($resp[0]) && defined($resp[0]->{'STATUS'}) && $resp[0]->{'STATUS'} eq AppConfig::FAILURE) {
			traceLog($resp[0]->{'MSG'});

			if($resp[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|response code said error|407 Proxy Authentication Required|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/) {
				# @TODO: Decide whether to reset all fileset status or not
				display(["\n", 'kindly_verify_ur_proxy']);
				traceLog('kindly_verify_ur_proxy');
				return -1;
			} elsif($resp[0]->{'MSG'} eq 'account_is_under_maintenance') {
				retreat(['your_account_is_under_maintenance']);
			} elsif ($resp[0]->{'MSG'} =~ /failed to get the device information|invalid device id|encryption verification failed|device is deleted\/removed/i) {
				doAccountResetLogout();
				return 'error-' . $resp[0]->{'MSG'};
			} elsif($resp[0]->{'MSG'} =~ /connection timed out|io timeout/i) {
				traceLog('connection timed out');
			} elsif($resp[0]->{'MSG'} =~ /unauthorized user|user information not found/i) {
				traceLog('unauthorized user or user information not found');
			}

			$loopmax--;
			next;
		}

		last;
	}

	return -1 if(!$loopmax || !-f $outputpath || -z _);
	return 0 if(!isDBWriterRunning());

	# If user has no last index stored means the backup is fresh
	unless(getUserConfiguration('LASTFILEINDEX')) {
		my $ecopf	= getECatfile($outputpath);
		my $fc		= `tail -n5 $ecopf`;
		my @indres	= split /\n/, $fc;

		foreach my $opline (@indres) {
			if($opline =~ /<item/) {
				my %indhash = parseXMLOutput(\$opline);
				if(exists $indhash{'last_recreate_time'}) {
					setUserConfiguration('LASTFILEINDEX', $indhash{'index'});
					saveUserConfiguration();

					unlink($outputpath);
					return 1;
				}
			}	
		}
	}

	my ($dirswatch, $jsjobselems, $jsitems) = getCDPWatchEntities();
	my $dumpfile	= getCDPDBDumpFile('idx_del_upd');
	my $upddbpaths	= getCDPDBPaths();
	my $didx		= 0;
	my $cdpjobnames;
	my %upddump;
	my @dumpfiles	= ();
	my ($curdata, $buffer, $byteread);
	my ($fh, $ll) = (undef, '');

	if(-f $outputpath) {
		chmod $AppConfig::filePermission, $outputpath;
		open $fh, "<", $outputpath;
		# reset the file index if no output file
		return -1 unless($fh);
	}
	
	while (1) {
		$byteread = read($fh, $buffer, $AppConfig::bufferLimit);
		return 0 if($byteread == 0 && !-f $outputpath);

		# need to check appending partial record to packet or to first line of packet
		$buffer = $ll . $buffer if(defined($ll) and '' ne $ll);
		my @results = split /\n/, $buffer;
		# keep last line of buffer only when it not ends with newline.
		$ll = ($buffer !~ /\n$/)? pop @results : '';

		foreach my $opline (@results) {
			if($opline =~ /<item/) {
				my %indhash = parseXMLOutput(\$opline);
				if(exists($indhash{'restype'}) && ($indhash{'restype'} eq 'F' || $indhash{'restype'} eq 'D')) {
					$cdpjobnames = getDBJobsetsByFile($jsjobselems, $indhash{'fname'});
					for my $i (0 .. $#{$cdpjobnames}) {
						next if($cdpjobnames->[$i] =~ /localbackup/);

						$curdata = {'ITEM' => $indhash{'fname'}, 'ITEMTYPE' => $indhash{'restype'}, 'JOBTYPE' => 'backup', 'JOBNAME' => $cdpjobnames->[$i]};
						$upddump{$didx} = $curdata;
						$didx++;
					}
				} elsif(exists $indhash{'last_recreate_time'}) {
					if($indhash{'index'} != getUserConfiguration('LASTFILEINDEX')) {
						setUserConfiguration('LASTFILEINDEX', $indhash{'index'});
						saveUserConfiguration();
					} else {
						$retry = 1;
					}

					if((exists $indhash{'files_found'} && !$indhash{'files_found'}) || (exists $indhash{'items_found'} && !$indhash{'items_found'})) {
						unlink($outputpath);
						return 1;
					} elsif(!exists($indhash{'files_found'}) and !exists($indhash{'items_found'}) and !$retry) {
						#Added to retry with proper last index when there is no proper result for index used.
						$retry = 1;
						unlink($outputpath);
						traceLog("Retry LASTFILEINDEX");
						goto START;
					}

					$didx = -1;
				}
			}
		}

		if($didx >= $AppConfig::fsindexmax || $didx == -1) {
			fileWrite($dumpfile, JSON::to_json(\%upddump));
			push @dumpfiles, $dumpfile;
			last if($didx == -1);

			%upddump = ();
			$didx = 0;
			$dumpfile = getCDPDBDumpFile('idx_del_upd');
		}
	}

	unlink($outputpath);

	# sleep until the writer service considers the requests
	for my $rfidx (0 .. $#dumpfiles) {
		sleep(2) while(-f $dumpfiles[$rfidx]);
		delete $dumpfiles[$rfidx];
	}

	return 1;
}

#*************************************************************************************************
# Subroutine		: processNonDedupUpdateDelete
# Objective			: Process file status if web activity is present
# Added By			: Sabin Cheruvattil
#*************************************************************************************************
sub processNonDedupUpdateDelete {
	# keep this commented | code review
	# display(['verifying_sync_items', '. ', 'please_wait', '...']) if($_[0]);

	my $loopmax		= 4;
	my $utf8path	= getCatfile(getJobsPath('backup'), $AppConfig::utf8File);
	my $outputpath	= getCatfile(getJobsPath('backup'), $AppConfig::evsOutputFile);

	# max 5 retries for web index checking.
	while($loopmax) {
		createUTF8File(['CHANGENOINDEX', $utf8path], getUserConfiguration('LASTFILEINDEX'), $outputpath);
		my @resp = runEVS('item');
		
		if(defined($resp[0]) && defined($resp[0]->{'STATUS'}) && $resp[0]->{'STATUS'} eq AppConfig::FAILURE) {
			my $errmsg = $resp[0]->{'MSG'};
			traceLog($errmsg);

			if($errmsg =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|response code said error|407 Proxy Authentication Required|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/) {
				display(["\n", 'kindly_verify_ur_proxy']);
				traceLog('kindly_verify_ur_proxy');
				return -1;
			} elsif($errmsg eq 'account_is_under_maintenance') {
				retreat(['your_account_is_under_maintenance']);
			} elsif($errmsg eq 'encryption_verification_failed') {
				return 'error-' .$errmsg;
			} elsif($errmsg =~ /connection timed out/i) {
				traceLog('connection timed out');
				$loopmax--;
				next;
			}
		}

		last;
	}

	return -1 if(!$loopmax || !-f $outputpath || -z _);
	return 0 if(!isDBWriterRunning());

	my ($buffer, $byteread);
	my ($fh, $ll, $hasloc) = (undef, '', 0);
	my $bkl	= getUserConfiguration('BACKUPLOCATION');
	if(-f $outputpath) {
		chmod $AppConfig::filePermission, $outputpath;
		open $fh, "<", $outputpath;
		# reset the file index if no output file
		return -1 unless($fh);
	}
	
	while (1) {
		$byteread = read($fh, $buffer, $AppConfig::bufferLimit);
		last if($byteread == 0);

		# need to check appending partial record to packet or to first line of packet
		$buffer = $ll . $buffer if(defined($ll) and '' ne $ll);
		my @results = split /\n/, $buffer;
		# keep last line of buffer only when it not ends with newline.
		$ll = ($buffer !~ /\n$/)? pop @results : '';

		foreach my $opline (@results) {
			if($opline =~ /<item/) {
				my %indhash = parseXMLOutput(\$opline);
				if(exists($indhash{'fname'}) && $indhash{'fname'}) {
					$hasloc = 1 if($indhash{'fname'} =~ /^\Q$bkl\/\E/);
				}
			}

			last if($hasloc == 1);
		}

		last if($hasloc == 1);
	}

	my $ecopf	= getECatfile($outputpath);
	my $fc		= `tail -n5 $ecopf`;
	my @indres	= split /\n/, $fc;
	my $renew	= 0;
	my $lastind	= 0;
	foreach my $opline (@indres) {
		if($opline =~ /<item/) {
			my %indhash = parseXMLOutput(\$opline);
			if(exists($indhash{'fname'})) {
				$renew	= 1;
				$lastind = $indhash{'index'};
			} elsif(exists $indhash{'files_found'}) {
				if($lastind) {
					setUserConfiguration('LASTFILEINDEX', $lastind);
					saveUserConfiguration();
				}
			}
		}
	}
	
	unlink($outputpath);

	setBackupLocationSize(1) if($hasloc);

	return 1 unless($renew);
	return -1;
}

#*****************************************************************************************************
# Subroutine			: promptPreReqManualInstall
# Objective				: Prompt the user for manual backup
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub promptPreReqManualInstall {
	my ($pkginstallseq, $cpaninstallseq) = ($_[0], $_[1]);
	display(["\n", 'would_you_like_to_install_manually_yn']);
	my $miuc = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	
	if(lc($miuc) eq 'y') {
		displayDBCDPInstallSteps($pkginstallseq, $cpaninstallseq);
		exit(1);
	}
}

#*****************************************************************************************************
# Subroutine : prettyPrint
# Objective  : Pretty print strings
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub prettyPrint {
	my @data = @_;
	my $messages;
	my $msg = '';
	foreach (@data) {
		if (reftype(\$_->[1]) eq 'SCALAR') {
			$messages = [$_->[1]];
		}
		else {
			$messages = $_->[1];
		}

		my $m = '';
		for my $i (0 .. $#{$messages}) {
			if (exists $LS{$messages->[$i]}) {
				$m .= $LS{$messages->[$i]};
			}
			else {
				$m .= $messages->[$i];
			}
		}
		$msg .= sprintf("%$_->[0]", $m);
	}
	print $msg;
}

#*****************************************************************************************************
# Subroutine			: processShellCopy
# Objective				: This is to process shell script preparation and copying to launch path
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub processShellCopy {
	my $opconf = $_[0];

	return unless(%{$opconf->{'shellcp'}});

	my $setuppath = getAppPath() . $opconf->{'setupdir'};
	my $shellpath = '';
	foreach my $cpkey (keys %{$opconf->{'shellcp'}}) {
		$shellpath = $setuppath . $cpkey;
		# Replace the file path holder with cron script path
		my $fc 			= getFileContents($shellpath);
		Chomp(\$fc);
		$fc		=~ s/__LAUNCHPATH__/$AppConfig::cronLinkPath/g;
		my $app = lc($AppConfig::appType);
		$fc		=~ s/__APP__/$app/g;

		my $dirname = dirname($opconf->{'shellcp'}{$cpkey});
		mkdir($dirname) if(!-d $dirname);

		fileWrite($opconf->{'shellcp'}{$cpkey}, $fc);
		chmod($AppConfig::execPermission, $opconf->{'shellcp'}{$cpkey}) unless((split('\.', basename($opconf->{'shellcp'}{$cpkey})))[1]);
	}
}

#*****************************************************************************************************
# Subroutine			: processCRONSetupCommands
# Objective				: This is to execute necessary commands for enabling the new cron service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub processCRONSetupCommands {
	my $opconf = $_[0];

	return unless(@{$opconf->{'setupcmd'}});

	for my $i (0 .. $#{$opconf->{'setupcmd'}}) {
		my $opconfSetupCmd = updateLocaleCmd($opconf->{'setupcmd'}[$i]);
		`$opconfSetupCmd 1>/dev/null 2>/dev/null`;
	}

	sleep(5);
}

#*****************************************************************************************************
# Subroutine			: processCRONShellLinks
# Objective				: This is to create links to shell if required
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub processCRONShellLinks {
	my $opconf = $_[0];

	return unless(%{$opconf->{'shellln'}});

	foreach my $lndest (keys %{$opconf->{'shellln'}}) {
		my $opconfshelllnCmd = updateLocaleCmd("ln -s $opconf->{'shellln'}{$lndest}");
		`$opconfshelllnCmd $lndest 1>/dev/null 2>/dev/null`;
	}
}

#*****************************************************************************************************
# Subroutine			: processCRONConfAppends
# Objective				: This is to process append contents to conf
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub processCRONConfAppends {
	my $opconf 		= $_[0];

	return unless(%{$opconf->{'confappend'}});

	my ($appendto, $appendfrom)	= ('', '');
	my $setuppath 	= getAppPath() . $opconf->{'setupdir'};
	foreach my $appkey (keys %{$opconf->{'confappend'}}) {
		$appendfrom = $setuppath . $appkey;
		$appendto 	= $opconf->{'confappend'}{$appkey};

		my $fc 			= getFileContents($appendto);
		Chomp(\$fc);
		my $appendcont	= getFileContents($appendfrom);
		if($appendcont ne '') {
			Chomp(\$appendcont);
			my $app = lc($AppConfig::appType);
			$appendcont	=~ s/__APP__/$app/g;
		}

		if (index($fc, $appendcont) == -1) {
			$fc 		= qq($fc\n$appendcont);
			fileWrite($appendto, $fc);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: processCronForManualInstall
# In Param				: UNDEF
# Out Param				: UNDEF
# Objective				: Checks cron installation by older instance
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub processCronForManualInstall {
	return 0 if(checkCRONServiceStatus() != CRON_RUNNING);

	my $opconf	= getCRONSetupTemplate();
	return 0 if (!%{$opconf});

	my $misconf = 0;
	if (%{$opconf->{'shellcp'}}) {
		foreach my $cpkey (keys %{$opconf->{'shellcp'}}) {
			if(!-f $opconf->{'shellcp'}{$cpkey}) {
				$misconf = 1;
				last;
			}
		}
	}

	if($misconf) {
		my @lockinfo = getCRONLockInfo();
		$lockinfo[2] = $AppConfig::cronSetup;
		$lockinfo[3] = 'update';
		fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: parseEVSCmdOutput
# Objective				: Parse evs response and return the same
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub parseEVSCmdOutput {
	my @parsedEVSCmdOutput;
	if (defined($_[0]) and defined($_[1])) {
		$_[0] =~ s/""/" "/g;
		my $endTag = '\/>';
		$endTag = "><\/$_[1]>" if (defined($_[2]));

		my @x = $_[0] =~ /(<$_[1]) (.+?)($endTag)/sg;

		for (1 .. (scalar(@x)/3)) {
			# following regex can be used when escaped double quote comes
			# my @keyValuePair = $x[(((3 * $_) - 2))] =~ /(.+?)="([^\\"]|.+?[^\\"])"/sg;
			my @keyValuePair = $x[(((3 * $_) - 2))] =~ /(.+?)="(.+?)"/sg;

			my %data;
			for (0 .. ((scalar(@keyValuePair)/2) - 1)) {
				$keyValuePair[($_ * 2)] =~ s/^\s+|\s+$//g;
				#$data{$keyValuePair[($_ * 2)]} = $keyValuePair[(($_ * 2) + 1)] =~ s/^\s$//gr;
				$keyValuePair[(($_ * 2) + 1)] =~ s/^\s$//g;
				$data{$keyValuePair[($_ * 2)]} = $keyValuePair[(($_ * 2) + 1)];
			}
			if (exists $data{'status'}) {
				$data{'STATUS'} = uc($data{'status'});
			}
			elsif (exists $data{'message'} and
							($data{'message'} eq AppConfig::FAILURE or
								$data{'message'} eq AppConfig::SUCCESS or
								$data{'message'} eq 'ERROR')) {
				if ($data{'message'} eq 'ERROR') {
					$data{'MSG'}    = $data{'desc'} if(exists $data{'desc'});
					$data{'STATUS'} = AppConfig::FAILURE;
				}
				else {
					$data{'STATUS'} = $data{'message'};
				}
			}
			else {
				$data{'STATUS'} = AppConfig::SUCCESS;
			}
			push @parsedEVSCmdOutput, \%data;
		}
	}

	unless (@parsedEVSCmdOutput) {
		if (defined($_[0]) and ($_[0] ne '')) {
			$_[0] =~ s/connection established\n//g;
			chomp($_[0]);
		}

		my $status = AppConfig::FAILURE;
		$status = AppConfig::SUCCESS if($_[0] =~ /bytes  received/);
		push @parsedEVSCmdOutput, {
			'STATUS' => $status,
			'MSG'    => $_[0]
		};
	}

	return @parsedEVSCmdOutput;
}

#*****************************************************************************************************
# Subroutine			: parseXMLContent
# Objective				: Parse XML content and return the array
# Added By				: Senthil Pandian
# Usage					: parseXMLContent(XMLcontent, element)
#****************************************************************************************************/
sub parseXMLContent {
	#my %parsedEVSCmdOutput;
	my @parsedEVSCmdOutput;
	if (defined($_[0]) and defined($_[1])) {
		$_[0] =~ s/""/" "/g;
		my $endTag = '\/>';
		$endTag = "><\/$_[1]>" if (defined($_[2]));

		my @x = grep {/\w+/} grep {/$_[1]/} split(/(?:\<)/, $_[0]);
		foreach my $line (@x){
			$line =~ /($_[1])/sg;
			my @keyValuePair = $line =~ /(.+?)="(.+?)"/sg;
			my %data;
			for (0 .. ((scalar(@keyValuePair)/2) - 1)) {
				$keyValuePair[($_ * 2)] =~ s/^\s+|\s+$//g;
				$keyValuePair[(($_ * 2) + 1)] =~ s/^\s$//g;
				$data{$keyValuePair[($_ * 2)]} = $keyValuePair[(($_ * 2) + 1)];
			}
			push @parsedEVSCmdOutput, \%data;
		}
	}
	#print Dumper(\@parsedEVSCmdOutput);
	return @parsedEVSCmdOutput;
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
	if (defined ${$_[0]} and ${$_[0]} ne "") {
		my $evsOutput = ${$_[0]};
		#clearFile($evsOutput);
		my @evsArrLine = ();
		if ($parseDeviceList){
			if ($evsOutput =~ /No devices found/){
				return %resultHash;
			} else {
				@evsArrLine = grep {/\w+/} grep {/bucket_type=\"D\"/} split(/(?:\<item|\<login|<tree)/, $evsOutput);
			}
		}else{
				@evsArrLine = grep {/\w+/} split(/(?:\<item|\<login|<tree)/, $evsOutput);
		}
		my $attributeCount = 1;
		foreach(@evsArrLine) {
			my @evsAttributes = grep {/\w+/} split(/\"[\s\n\>]+/s, $_);
			foreach (@evsAttributes){
				s/\"\/\>//;
				s/\"\>//;
				my ($key,$value) = split(/\=["]/, $_);
		 		&Chomp(\$key)	if (defined($key));
				#&Chomp(\$value); #Commented by Senthil for Harish_2.17_6_12 on 09-Aug-2018
				if ($parseDeviceList){
					my $subKey = $value.'_'.$attributeCount;
					$subKey = $value if (/(?:uid|device_id|server_root)/i);
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
# Subroutine Name         : proxyBackwardCompatability
# Objective               : Backward compatability to update proxy fields
# Added By                : Anil
#*****************************************************************************************************/
sub proxyBackwardCompatability {
	my $proxyValue   = getUserConfiguration('PROXY');
	my $proxyIpValue = getUserConfiguration('PROXYIP');
	if ($proxyValue eq "" and !$proxyIpValue) {
		setUserConfiguration('PROXYIP', '');
		setUserConfiguration('PROXYPORT', '');
		setUserConfiguration('PROXYUSERNAME', '');
		setUserConfiguration('PROXYPASSWORD', '');
		setUserConfiguration('PROXY', '');
	}
	elsif (!$proxyIpValue or ($proxyValue ne "" and $proxyIpValue eq "")) {
		my @val = split('@',$proxyValue);
		my @userInfo = split(':',$val[0]);
		my @serverInfo = split(':',$val[1]);
		$userInfo[0] = ($userInfo[0])?$userInfo[0]:'';
		$userInfo[1] = ($userInfo[1])?$userInfo[1]:'';
		setUserConfiguration('PROXYIP',$serverInfo[0]);
		setUserConfiguration('PROXYPORT',$serverInfo[1]);
		setUserConfiguration('PROXYUSERNAME',$userInfo[0]);
		my $proxySIPPasswd = $userInfo[1];
		if ($proxySIPPasswd ne ''){
			trim($proxySIPPasswd);
			$proxySIPPasswd = encryptString($proxySIPPasswd);
		}
		setUserConfiguration('PROXYPASSWORD', $proxySIPPasswd);
		setUserConfiguration('PROXY', $userInfo[0].":".$proxySIPPasswd."@".$serverInfo[0].":".$serverInfo[1]);
	}
}

#****************************************************************************************************
# Subroutine Name         : putParameterValueInStatusFile.
# Objective               : Changes the content of STATUS FILE as per values passed
# Added By                : Dhritikana
#*****************************************************************************************************/
sub putParameterValueInStatusFile {
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;
	open STAT_FILE, ">", $statusFilePath or (traceLog(['failed_to_open_file', " : $statusFilePath. Reason :$!"]) and die);
	#foreach my $keys(keys $AppConfig::statusHash) {
	foreach my $keys(keys %AppConfig::statusHash) {
		print STAT_FILE "$keys = $AppConfig::statusHash{$keys}\n";
	}
	close STAT_FILE;
	chmod $AppConfig::filePermission, $statusFilePath;
	undef @AppConfig::linesStatusFile;
}

#*****************************************************************************************************
# Subroutine			: parseMachineUID
# Objective				: Parse uid from network configuration
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parseMachineUID {
	my $cmd;
	my $keyChar = '';
	my $prepend = '';
	$prepend = $AppConfig::deviceUIDPrefix unless (defined($_[0]) and ($_[0] == 0));
	my $ifConfigPathCmd = updateLocaleCmd("which ifconfig 2>/dev/null");
	my $ifConfigPath = `$ifConfigPathCmd`;
	chomp($ifConfigPath);
	if ($ifConfigPath ne '') {
		$cmd = 'ifconfig -a';
		$keyChar = 'HWaddr |ether ';
	}
	elsif (-f '/sbin/ifconfig') {
		$cmd = '/sbin/ifconfig -a';
		$keyChar = 'HWaddr | ether ';
	}
	elsif (-f '/sbin/ip') {
		$cmd = '/sbin/ip addr';
		$keyChar = 'ether ';
	}
	elsif (-d '/sys/class/net') {
		$cmd = 'cat /sys/class/net/*/address';
	}

	my ($a, $kc, $macAddr, $b) = ('', '', '', '');
	if (defined($cmd)) {
		$cmd = updateLocaleCmd($cmd);
		my $result = `$cmd`;
		if ($result =~ /hardware/i) {
			my @r = split(/hardware/, $result);
			if ($r[1]) {
				$result = $r[1];
				$keyChar = '';
			}
		}
		$result =~ s/00:00:00:00:00:00/loop/g;
	
		($a, $kc, $macAddr, $b) = split(/($keyChar)((?:[0-9A-Fa-f:]{2}[:-]){5}[0-9A-Fa-f:]{2})/, $result);
	}

	unless ($macAddr) {
		my $unameCmd = updateLocaleCmd("which uname 2>/dev/null");
		my $uname = `$unameCmd`;
		chomp($uname);
		my $result;
		if ($uname ne '') {
			$cmd = 'uname -rm';
			$result = `$cmd`;
			chomp($result);
		}
		else {
			$result = time();
		}
		$macAddr = ($result . $AppConfig::hostname);
	}

	$macAddr =~ s/|:|-|\.|_| //g if ($macAddr);
	return ("$prepend" . $macAddr);
}

#------------------------------------------------- Q -------------------------------------------------#

#------------------------------------------------- R -------------------------------------------------#
#*****************************************************************************************************
# Subroutine		: readInfoFile
# Objective			: Read INFO file & return the value for key
# Added By 			: Senthil Pandian
#*****************************************************************************************************
sub readInfoFile {
	my $pattern = $_[0];
	my $count   = 0;
	my $infoFile = getCatfile($AppConfig::jobRunningDir, 'info_file');
	if (-e $infoFile and !-z $infoFile){
		my $fileCountCmd = "cat '$infoFile' | grep -m1 \"^$pattern\"";
		$fileCountCmd = updateLocaleCmd($fileCountCmd);
		$count  = `$fileCountCmd`;
		if ($count =~ /$pattern/){
			$count =~ s/$pattern//;
			Chomp(\$count) if ($count);
		}
	}
	return $count;
}

#*****************************************************************************************************
# Subroutine		: replaceXMLcharacters
# Objective			: Replaces the special characters in XML output with their actual characters
# Added By 			: Senthil Pandian
#*****************************************************************************************************
sub replaceXMLcharacters {
	my ($fileToCheck) = @_;
	${$fileToCheck} =~ s/&apos;/'/g;
	${$fileToCheck} =~ s/&quot;/"/g;
	${$fileToCheck} =~ s/&amp;/&/g;
	${$fileToCheck} =~ s/&lt;/</g;
	${$fileToCheck} =~ s/&gt;/>/g;
}

#*****************************************************************************************************
# Subroutine			: rescanLog
# Objective				: Helps to create rescan log
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub rescanLog {
	return 0;

	return 0 unless($_[0]);
	my $rslog = getCatfile(getJobsPath('cdp'), $AppConfig::rescanlog);
	fileWrite($rslog, $_[0] . "\n", 'APPEND');
	return 1;
}

#*****************************************************************************************************
# Subroutine			: rtrim
# Objective				: This function will remove white spaces from the right side of a string
# Added By				: Anil Kumar
#****************************************************************************************************/
sub rtrim {
	my $s = shift;
	$s =~ s/\s+$//;
	return $s;
}

#*****************************************************************************************************
# Subroutine			: retreat
# Objective				: Raise an exception and exit immediately
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil
#****************************************************************************************************/
sub retreat {
	displayHeader();
	if ($servicePath ne '') {
		my ($package, $filename, $line) = caller;
		traceLog($_[0], basename($filename), $line) ;
	}
	unless ($AppConfig::callerEnv eq 'BACKGROUND') {
		display($_[0]) unless (defined($_[1]) and ($_[1] == 1));
	}

	if ($servicePath ne '') {
		rmtree("$servicePath/$AppConfig::downloadsPath") if(-e "$servicePath/$AppConfig::downloadsPath");
		rmtree("$servicePath/$AppConfig::tmpPath") if(-e "$servicePath/$AppConfig::tmpPath");
	}
	die "\n";
}

#*****************************************************************************************************
# Subroutine			: removeIDriveCRON
# Objective				: This is to uninstall IDrive CRON service
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub removeIDriveCRON {
	lockCriticalUpdate("cron");
	loadCrontab(1);
	my %crontab = %{getCrontab()};
	my ($skipped, $cronLinkRemoved) = (0) x 2;
	my ($cronLinkPath, $cronScriptDir, $existingScriptDir) = ('') x 3;
	my $currentDir  	= getAppPath();

	removeFallBackCRONEntry();

	if (-e $AppConfig::cronLinkPath) {
		$cronLinkPath 	= readlink($AppConfig::cronLinkPath);
		$cronScriptDir	= dirname($cronLinkPath) . '/' if ($cronLinkPath);

		foreach my $mcUser (keys %crontab){
			foreach my $idriveUser (keys %{$crontab{$mcUser}}){
				if ($crontab{$mcUser}{$idriveUser}{'dashboard'}{'dashboard'}{'cmd'}){
					my $dashboardCmd = $crontab{$mcUser}{$idriveUser}{'dashboard'}{'dashboard'}{'cmd'};
					if ($dashboardCmd ne '' && $dashboardCmd =~ /dashboard.pl|cron.pl/) {
						my $scriptPath = dirname($dashboardCmd) . '/';
						$scriptPath =~ s/${AppConfig::idriveLibPath}\/$//;

						if ($scriptPath eq $currentDir || !-e $scriptPath) {
							delete $crontab{$mcUser}{$idriveUser};
							if ($scriptPath eq $cronScriptDir) {
								unlink($AppConfig::cronLinkPath);
								$cronLinkRemoved = 1;
							}
						} else {
							$skipped++;
							$existingScriptDir = $scriptPath;
						}
					}
				}
			}
		}

		# Checking & saving the updated cron entries
		if ($skipped > 0) {
			saveCrontab();
			unlockCriticalUpdate("cron");
			#Creating new link if cron link removed due to uninstalling the path
			if ($cronLinkRemoved) {
				my $cmd = "ln -s '" . $existingScriptDir . $AppConfig::idriveScripts{'cron'} . "' '$AppConfig::cronLinkPath'";
				chmod($AppConfig::execPermission, $AppConfig::cronLinkPath);
				$cmd = updateLocaleCmd($cmd);
				system($cmd);
			}

			# Launch Cron service from here
			unless(checkCRONServiceStatus() == CRON_RUNNING) {
				launchIDriveCRON();
			} else {
				my @lockinfo 	= getCRONLockInfo();
				$lockinfo[2] = 'restart';
				fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
			}

			return;
		}
	}

	unlockCriticalUpdate("cron");

	my $opconf	= getCRONSetupTemplate();
	if (%{$opconf}) {
		# execute stop commands
		if (@{$opconf->{'stopcmd'}}) {
			for my $i (0 .. $#{$opconf->{'stopcmd'}}) {
				my $opConfStopCmd = updateLocaleCmd($opconf->{'stopcmd'}[$i]);
				`$opConfStopCmd 1>/dev/null 2>/dev/null`;
			}
		}

		# remove created links
		if (%{$opconf->{'shellln'}}) {
			foreach my $lndest (keys %{$opconf->{'shellln'}}) {
				removeItems("$lndest");
			}
		}

		# remove all copied shells
		if (%{$opconf->{'shellcp'}}) {
			my $shellpath = '';
			foreach my $cpkey (keys %{$opconf->{'shellcp'}}) {
				removeItems("$opconf->{'shellcp'}{$cpkey}");
			}
		}

		if (%{$opconf->{'confappend'}}) {
			my ($appendto, $appendfrom)	= ('', '');
			my $setuppath 	= getAppPath() . $opconf->{'setupdir'};
			foreach my $appkey (keys %{$opconf->{'confappend'}}) {
				$appendfrom = $setuppath . $appkey;
				$appendto 	= $opconf->{'confappend'}{$appkey};

				my $fc 			= getFileContents($appendto);
				Chomp(\$fc);
				my $appendcont	= getFileContents($appendfrom);
				Chomp(\$appendcont);

				if (index($fc, $appendcont) != -1) {
					$fc 		=~ s/$appendcont\n//;
					fileWrite($appendto, $fc);
				}
			}
		}
	}

	removeOldFallBackCRONRebootEntry();
	removeFallBackCRONRebootEntry();

	# clean up the links and crontab file
	unlink($AppConfig::cronlockFile) if (-f $AppConfig::cronlockFile);
	unlink(getCrontabFile()) if (-f getCrontabFile());
	unlink($AppConfig::cronLinkPath) if (-f $AppConfig::cronLinkPath);
}

#*****************************************************************************************************
# Subroutine	: removeFallBackCRONEntry
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Removes the fallback cron entry from crontab
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub removeFallBackCRONEntry {
	# fallback logic has to be removed if added
	return 0 if (!hasCRONFallBackAdded());

	my $crontabf	= '/etc/crontab';
	traceLog(['checking_fallback_cron']);

	my $fc		= getFileContents($crontabf);
	my @fch		= split("\n", $fc);
	for my $ind (0 .. $#fch) {
		#Added condition for Suruchi_2.3_22_3: Senthil
		Chomp(\$ind);
		if($AppConfig::cronLinkPath ne '' and $ind ne '' and defined($fch[$ind]) and $fch[$ind] ne '') {
			splice(@fch, $ind, 1) if (index($fch[$ind], $AppConfig::cronLinkPath) != -1);
		}
	}

	$fc = join("\n", @fch);
	fileWrite($crontabf, $fc);

	return 1;
}

#*****************************************************************************************************
# Subroutine	: removeFallBackCRONRebootEntry
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Removes the entry from system cron to handle reboot
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub removeFallBackCRONRebootEntry {
	my $cturi		= `which crontab 2>/dev/null`;
	Chomp(\$cturi);

	return 0 unless($cturi);

	my $fbrecron	= getFallBackCRONRebootEntry();
	return 0 if(!$fbrecron);

	my $command		= qq(crontab -u root -l 2>/dev/null | grep -v '$fbrecron' | crontab -u root -);

	system($command);
}

#*****************************************************************************************************
# Subroutine	: removeOldFallBackCRONRebootEntry
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Removes the entry from system cron to handle reboot
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub removeOldFallBackCRONRebootEntry {
	my $cturi		= `which crontab 2>/dev/null`;
	Chomp(\$cturi);

	return 0 unless($cturi);

	my $fbrecron	= getOldFallBackCRONRebootEntry();
	my $command		= qq(crontab -u root -l 2>/dev/null | grep -v '$fbrecron' | crontab -u root -);

	system($command);
}

#*****************************************************************************************************
# Subroutine			: removeBKPSetSizeCache
# Objective				: This is to cleanup backupset size cache
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub removeBKPSetSizeCache {
	return 0 unless($_[0]);

	my $bsf = getJobsPath($_[0], 'file');
	return 0 if (!-f "$bsf.json" || -z "$bsf.json");
	
	my $bkpszcache = JSON::from_json(getFileContents("$bsf.json"));

	foreach my $item (keys %{$bkpszcache}) {
		if($bkpszcache->{$item}{'type'} eq 'd') {
			$bkpszcache->{$item}{'ts'} = '';
			$bkpszcache->{$item}{'filecount'} = 'NA';
			$bkpszcache->{$item}{'size'} = -1;
		}
	}

	fileWrite("$bsf.json", JSON::to_json($bkpszcache));

	return 1;
}

#*****************************************************************************************************
# Subroutine			: removeDeprecatedDB
# In Param				: UNDEF
# Out Param				: UNDEF
# Objective				: Checks and removes deprecated DB
# Added By				: Sabin Cheruvattil
# Modified By			: 
#*****************************************************************************************************
sub removeDeprecatedDB {
	loadCrontab();
	my @jbtypes = ('backup', 'localbackup');
	my $crontab = getCrontab();

	# If older backup set is existing, we have to replace it with encrypted one
	foreach my $muser (keys %{$crontab}) {
		foreach my $iduser (keys %{$crontab->{$muser}}) {
			foreach my $jbt (@jbtypes) {
				my $dbbasename	= getCatfile(getServicePath(), $AppConfig::userProfilePath, $muser, $iduser, $AppConfig::userProfilePaths{$jbt}, $AppConfig::dbnamebase);
				my @avdbs = glob("$dbbasename*");

				foreach my $dbfile (@avdbs) {
					next if($AppConfig::dbname eq basename($dbfile));
					unlink($dbfile);
				}
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: reCalculateStorageSize
# Objective				: Request IDrive server to re-calculate storage size
# Added By				: Yogesh Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub reCalculateStorageSize {
	my $calculateStorageSize = "'$appPath/".$AppConfig::idriveScripts{'utility'} . '\' GETQUOTA';
	$calculateStorageSize .= " $_[0]" if(defined($_[0]));
	my $calculateStorageSizeCmd = updateLocaleCmd("$AppConfig::perlBin $calculateStorageSize");
	my $runCmd = `$calculateStorageSizeCmd 2>/dev/null&`; #2>/dev/null
	return 0;

	# my $csf = getCachedStorageFile();
	# unlink($csf);
	# createUTF8File('GETQUOTA') or
		# retreat('failed_to_create_utf8_file');
	# my @result = runEVS('tree');
	# if (exists $result[0]->{'message'}) {
		# if ($result[0]->{'message'} eq 'ERROR') {
			# display('unable_to_retrieve_the_quota') unless(defined($_[0]));
			# return 0;
		# }
	# }
	# if (saveUserQuota(@result)) {
		# return 1 if loadStorageSize();
	# }
	# traceLog('unable_to_cache_the_quota');
	# display('unable_to_cache_the_quota') unless(defined($_[0]));
	# return 0;
}

#*****************************************************************************************************
# Subroutine			: rescanAndUpdateBackupsetDB
# Objective				: Rescans and updates the db
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub rescanAndUpdateBackupsetDB {
	return 0 unless($_[0]);

	loadUserConfiguration();
	my $showhidden	= getUserConfiguration('SHOWHIDDEN');
	loadFullExclude();
	loadPartialExclude();
	loadRegexExclude();

	my $bkpitems = $_[0];
	my ($commitstat, $opstat) = (1, 1);

	my $rslog = getCatfile(getJobsPath('cdp'), $AppConfig::rescanlog);
	unlink($rslog) if(-f $rslog);

	rescanLog(getLocaleString('starting_rescan') . ': ' . localtime);

	Sqlite::beginDBProcess();

	my $scanprog	= getCDPLockFile('scanprog');

	eval {
		require Tie::File;
		Tie::File->import();
	};

	tie my @fc, 'Tie::File', $scanprog;

	my $item		= '';
	my @origbkpset	= @{$bkpitems};
	# Add/update files/directories
	foreach $item (@{$bkpitems}) {
		chomp($item);
		# utf8::decode($item);
		if(!-l $item && -d _) {
			Sqlite::addToBackupSet($item, 'd', 1, stat($item)->mtime) if(grep(/^\Q$item\E$/, @origbkpset));
			$opstat = enumerateDirAndUpdateDB($item, $bkpitems, \@fc, 1, undef);

			$commitstat = 0 unless($opstat);
		} elsif(!-l _ && -f _) {
			Sqlite::addToBackupSet($item, 'f', 1, stat($item)->mtime) if(grep(/^\Q$item\E$/, @origbkpset));

			my $fileName	= (fileparse($item))[0];
			$fileName		= "'$fileName'";
			my $sf			= stat($item);

			unless(Sqlite::checkItemInDB($item)) {
				my $dirid	= Sqlite::dirExistsInDB($item, '/');
				$dirid		= Sqlite::insertDirectories($item, '/') unless($dirid);

				my $status	= $AppConfig::dbfilestats{'NEW'};
				$status		= $AppConfig::dbfilestats{'EXCLUDED'} if(isThisExcludedItemSet($item . '/', $showhidden));
				$opstat 	= Sqlite::insertIbFile(1, $dirid, $fileName, $sf->mtime, $sf->size, $status);
				$commitstat = 0 unless($opstat);

				$fc[1]++;
				$fc[0]		= $item;
				rescanLog("Add: $item");
			} else {
				my %fileListHash  =  Sqlite::fileListInDbDir(dirname($item) . '/');

				if(exists $fileListHash{$fileName} && ($fileListHash{$fileName}{'FILE_LMD'} ne $sf->mtime || $fileListHash{$fileName}{'FILE_SIZE'} ne $sf->size)) {
					my $dirid	= Sqlite::dirExistsInDB($item, '/');
					my $status	= $AppConfig::dbfilestats{'MODIFIED'};
					if(isThisExcludedItemSet($item . '/', $showhidden)) {
						$status	= $AppConfig::dbfilestats{'EXCLUDED'};
					} elsif($fileListHash{$fileName}{'BACKUP_STATUS'} == $AppConfig::dbfilestats{'CDP'} && $sf->size <= $AppConfig::cdpmaxsize) {
						$status	= $AppConfig::dbfilestats{'CDP'};
					}

					$opstat = Sqlite::updateIbFile(1, $dirid, $fileName, $sf->mtime, $sf->size, $status);
					$commitstat = 0 unless($opstat);

					$fc[1]++;
					$fc[0]		= $item;
					rescanLog("Add: $item");
				}

				undef %fileListHash;
			}
		} elsif(!-e _) {
			Sqlite::addToBackupSet($item, 'u', 0, 0) if(grep(/^\Q$item\E$/, @origbkpset));

			my $isdir = Sqlite::isPathDir($item);
			if($isdir) {
				Sqlite::deleteDirsAndFilesByDirName($item);
				rescanLog("Delete: " . $item);
				next;
			}

			if(Sqlite::checkItemInDB($item)) {
				my $dirid	= Sqlite::dirExistsInDB($item, '/');
				next unless($dirid);

				$opstat = Sqlite::deleteIbFile(basename($item), $dirid);
				$commitstat = 0 unless($opstat);
				rescanLog("Delete: " . $item);
			}
		}
	}

	untie @fc;
	unlink($scanprog);

	Sqlite::commitDBProcess($item);
	rescanLog(getLocaleString('finishing_rescan') . ': ' . localtime);

	undef $bkpitems;
	undef @origbkpset;

	return $commitstat;
}

#*****************************************************************************************************
# Subroutine			: resetBackedupStatus
# Objective				: Resets the backup status in database
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub resetBackedupStatus {
	return 0 unless($_[0]);

	my $dbfile = getCatfile($_[0], $AppConfig::dbname);
	return 0 unless(-f $dbfile);

	my ($dbfstate, $scanfile) = Sqlite::createLBDB($_[0], 1);
	return 0 unless($dbfstate);
	Sqlite::initiateDBoperation();
	Sqlite::resetBackedupStatusNew();
	Sqlite::closeDB();

	return 1;
}

#*****************************************************************************************************
# Subroutine			: runEVS
# Objective				: Execute evs binary using backtick operator and return parsed output
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub runEVS {
	my $isErrorFile = 0;
	my $runInBackground = "";
	my $tempUtf8File = $utf8File;
	my $extras = '';

	$isErrorFile     = 1        if (defined($_[1]));
	$runInBackground = "&"      if (defined($_[2]) and $_[2] == 1);
	$tempUtf8File    = $_[3]    if (defined($_[3]));
	$extras         .= ";$_[4]" if (defined($_[4]));

	my ($idevscmdout,$idevcmd) = ('')x 2;
	my $evsPath = getEVSBinaryFile();
	if (-e $evsPath) {
		$idevcmd = ("'$evsPath' --utf8-cmd='$tempUtf8File'");
		if ($runInBackground) {
			my $idevSysCmd = updateLocaleCmd("$idevcmd $extras");
			$idevscmdout = system("($idevSysCmd) 1>/dev/null 2>/dev/null $runInBackground");
		}
		else {
			$idevcmd = updateLocaleCmd($idevcmd);
			$idevscmdout = `$idevcmd 2>&1`;
		}

		my @errArr;
		#if (($? > 0) and !$isErrorFile and $idevscmdout !~ /no version information available/) {
		# Modified by Senthil for Harish_2.17_55_2
		if (!$isErrorFile and $idevscmdout ne '' and $idevscmdout !~ /no version information available/) {
			my $msg = 'execution_failed';
			if (($idevscmdout =~ /\@ERROR: PROTOCOL VERSION MISMATCH on module ibackup/ or
						$idevscmdout =~ /Failed to validate. Try again/) and
					$userConfiguration{'DEDUP'} ne 'off') {
				setUserConfiguration('DEDUP', 'off');
				return runEVS($_[0]);
			}

			# if (($? > 0)){
			if (($? > 0) || $idevscmdout =~ /\@ERROR:|idevs error:/){
				if ($idevscmdout =~ /\@ERROR:/ and
					$idevscmdout =~ /encryption verification failed/) {
					$msg = 'encryption_verification_failed';
				}
				elsif ($idevscmdout =~ /private encryption key must be between 4 and 256 characters in length/) {
					$msg = 'private_encryption_key_must_be_between_4_and_256_characters_in_length';
				}
				elsif($idevscmdout =~ /$AppConfig::proxyNetworkError/i) {
				# elsif ($idevscmdout =~ /(failed to connect|Connection refused|407 Proxy Authentication Required|Could not resolve proxy|Could not resolve host|No route to host)/i) {
					$msg = 'kindly_verify_ur_proxy';
				}
				elsif ($idevscmdout =~ /Invalid username or Password/) {
					$msg = getStringConstant('invalid_username_or_password').getStringConstant('logout_&_login_&_try_again');
				}
				elsif ($idevscmdout =~ /unauthorized user|user information not found/i) {
					updateAccountStatus(getUsername(), 'UA');
					saveServerAddress(fetchServerAddress());
					$msg = $idevscmdout;
				} elsif (checkErrorAndUpdateEVSDomainStat($idevscmdout)) {
					$msg = $idevscmdout;
				}
				else {
					traceLog($idevscmdout);
					$msg = checkErrorAndLogout($idevscmdout, 1, 1);
				}
				push @errArr, {
					'STATUS' => AppConfig::FAILURE,
					'MSG'    => $msg
				};
				unlink($tempUtf8File);
				return @errArr;
			}
		}

		unlink($tempUtf8File) if ($runInBackground eq "");

		#Added by Senthil : 03-JULY-2018
		if ($idevscmdout =~ /no version information available/){
			my @linesOfRes = split(/\n/,$idevscmdout);
			my $warningString = "no version information available";
			my @finalLines = grep !/$warningString/, @linesOfRes;
			$idevscmdout  = join("\n",@finalLines);
		}
		if ($idevscmdout eq '') {
			my $status = ($isErrorFile)?AppConfig::FAILURE:AppConfig::SUCCESS;
			push @errArr, {
				'STATUS' => $status,
				'MSG'    => 'no_stdout'
			};
			return @errArr;
		}
		return parseEVSCmdOutput($idevscmdout, $_[0]);
	}
	else {
		my @errArr;
		push @errArr, {
			'STATUS' => AppConfig::FAILURE,
			'MSG'    => 'Unable to find or execute EVS binary. Please configure or reconfigure your account using account_setting.pl'
		};
		unlink($tempUtf8File);
		return @errArr;
	}
}


#*****************************************************************************************************
# Subroutine			: runningJobHandler
# Objective				: This function will allow to change the backup/restore from location only if no scheduled backup / restore job is running. if any of previously mentioned job is runnign then it will first ask for the termination of running job then allow to change location.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
=beg Not using this Subroutine: We need to remove it later:Senthil-Nov-12-2019
sub runningJobHandler {
	my ($jobType, $jobMode, $username, $userProfilePath) = @_;
	my $pidPath = $userProfilePath.'/'.$username.'/'.$jobType.'/'.$jobMode.'/pid.txt';
	my $changeLocationStatus = 0;
	if (isRunningJob($pidPath)) {
		my $confMessage = "\n" . $LS{'changing_title'} . ' ' . $jobType . ' ' . $LS{'location_will_terminate'} . ' ';
		$confMessage 	.= $jobMode . ' ' . $jobType . ' ' . $LS{'in_progress'} . '... ' . $LS{'do_you_want_to_continue_yn'};
		my $choice = getAndValidate('enter_your_choice', "YN_choice", 1);
		if (($choice eq 'y')) {
			display([qq(\n$LS{'terminating_your_title'} $jobMode $jobType $LS{'job'}. $LS{'please_wait_title'}...)]);
			my $jobTerminationScript = getScript('job_termination', 1);
			my $jobTermCmd = "$AppConfig::perlBin $jobTerminationScript ".lc($jobType)." $username";
			$jobTermCmd = updateLocaleCmd($jobTermCmd);
			my $res = system($jobTermCmd);
			if ($res != 0) {
				traceLog(qq($LS{'error_in_terminating'} $jobMode $jobType $LS{'job'}.));
			} else {
				$changeLocationStatus = 1;
			}
		}
	} else {
		$changeLocationStatus = 1;
	}

	return $changeLocationStatus;
}
=cut
#*****************************************************************************************************
# Subroutine			: renameDevice
# Objective				: This subroutineis is used to change the device name to the given name
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub renameDevice {
	createUTF8File('NICKUPDATE',$_[1],($AppConfig::deviceIDPrefix .$_[0]->{'device_id'} .$AppConfig::deviceIDSuffix)) or retreat('failed_to_create_utf8_file');

	my @result = runEVS('item', undef, ($_[2] || undef));
	return 1 if ( defined $_[2]);
	return 1 if ($result[0]->{'STATUS'} eq AppConfig::SUCCESS);
	return 0;
}

#****************************************************************************************************
# Subroutine Name         : readFinalStatus.
# Objective               : reads the overall status file based on engine
# Added By                : Vijay Vinoth
#*****************************************************************************************************/
sub readFinalStatus {
	my %statusFinalHash = 	(	"FILES_COUNT_INDEX" => 0,
						"SYNC_COUNT_FILES_INDEX" => 0,
						"FAILEDFILES_LISTIDX" => 0,
						"ERROR_COUNT_FILES" => 0,
						"COUNT_FILES_INDEX" => 0,
						"DENIED_COUNT_FILES" => 0,
						"MISSED_FILES_COUNT" => 0,
                        "MODIFIED_FILES_COUNT" => 0,
						"EXIT_FLAG_INDEX" => 0,
						"TOTAL_TRANSFERRED_SIZE" => 0,
					);
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;
	for(my $i=1; $i<= $AppConfig::totalEngineBackup; $i++){
		if (-e $statusFilePath."_$i" and -f $statusFilePath."_$i" and -s $statusFilePath."_$i" ) {
			my %statusHash = readStatusFile($i);
            if(scalar(keys %statusHash)) {
                $statusFinalHash{'FILES_COUNT_INDEX'} += $AppConfig::statusHash{'FILES_COUNT_INDEX'} if(defined($AppConfig::statusHash{'FILES_COUNT_INDEX'}));
                $statusFinalHash{'SYNC_COUNT_FILES_INDEX'} += $statusHash{'SYNC_COUNT_FILES_INDEX'};
                $statusFinalHash{'FAILEDFILES_LISTIDX'} += $AppConfig::statusHash{'FAILEDFILES_LISTIDX'};
                $statusFinalHash{'ERROR_COUNT_FILES'} += $statusHash{'ERROR_COUNT_FILES'};
                $statusFinalHash{'DENIED_COUNT_FILES'} += $statusHash{'DENIED_COUNT_FILES'};
                $statusFinalHash{'MISSED_FILES_COUNT'} += $statusHash{'MISSED_FILES_COUNT'};
                $statusFinalHash{'MODIFIED_FILES_COUNT'} += $statusHash{'MODIFIED_FILES_COUNT'};
                $statusFinalHash{'COUNT_FILES_INDEX'} += $statusHash{'COUNT_FILES_INDEX'};
                $statusFinalHash{'TOTAL_TRANSFERRED_SIZE'} += $statusHash{'TOTAL_TRANSFERRED_SIZE'};

                if (!$statusFinalHash{'EXIT_FLAG_INDEX'} or !defined $statusHash{'EXIT_FLAG_INDEX'}){
                    $statusFinalHash{'EXIT_FLAG_INDEX'} = $statusHash{'EXIT_FLAG_INDEX'};
                }
            }
		}
	}

	return (\%statusFinalHash);
}

#****************************************************************************************************
# Subroutine Name         : restoreBackupsetFileConfiguration.
# Objective               : This subroutine moves the BackupsetFile to the original configuration
# Added By                : Dhritikana
#*****************************************************************************************************/
sub restoreBackupsetFileConfiguration
{
	my $relativeFileset   = $AppConfig::jobRunningDir."/".$AppConfig::relativeFileset;
	my $noRelativeFileset = $AppConfig::jobRunningDir."/".$AppConfig::noRelativeFileset;
	my $filesOnly		  = $AppConfig::jobRunningDir."/".$AppConfig::filesOnly;
	my $info_file 	   	  = $AppConfig::jobRunningDir."/".$AppConfig::infoFile;

	if ($relativeFileset ne "") {
		unlink <$relativeFileset*>;
	}
	if ($noRelativeFileset ne "") {
		unlink <$noRelativeFileset*>;
	}
	if ($filesOnly ne "") {
		unlink <$filesOnly*>;
	}
	# unlink $info_file;
}

#****************************************************************************************************
# Subroutine Name         : readStatusFile.
# Objective               : reads the status file
# Added By                : Deepak Chaurasia
# Modified By 		      : Vijay Vinoth for multiple engine.
#*****************************************************************************************************/
sub readStatusFile {
	my $operationEngineId = $_[0];
	my %statusHash = ();
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile."_".$operationEngineId;

	if (-f $statusFilePath and -s _) {
		chmod $AppConfig::filePermission, $statusFilePath;
		if (open(STATUS_FILE, "< $statusFilePath")) {
			my @linesStatusFile = <STATUS_FILE>;
			@AppConfig::linesStatusFile = @linesStatusFile;
			close STATUS_FILE;
			if ($#linesStatusFile >= 0) {
				foreach my $line (@linesStatusFile) {
					chomp $line;
					my @keyValuePair = split /=/, $line;
					s/^\s+|\s+$//g for (@keyValuePair);
					$keyValuePair[1] = 0 if (!$keyValuePair[1]);
					Chomp(\$keyValuePair[0]);
					Chomp(\$keyValuePair[1]);
					#$AppConfig::statusHash{$keyValuePair[0]} = looks_like_number($keyValuePair[1])? int($keyValuePair[1]) : $keyValuePair[1];
					$statusHash{$keyValuePair[0]} = looks_like_number($keyValuePair[1])? int($keyValuePair[1]) : $keyValuePair[1];
				}
			}
		}
	}
	return %statusHash;
}

#*****************************************************************************************************
# Subroutine			: restartIDriveCRON
# Objective				: This is to restart IDrive CRON
# Added By				: Sabin Cheruvattil
# Modified By           : Senthil Pandian
#****************************************************************************************************/
sub restartIDriveCRON {
	my $display 	= ((defined($_[0]) && $_[0] == 1)? 1 : 0);
	my $restartflag = ((checkCRONServiceStatus() == CRON_RUNNING)? 're' : '');

	display(["\n", $restartflag . 'starting_cron_service', '...']) if ($display);
	my $opconf	= getCRONSetupTemplate();

	my @oldlock = getCRONLockInfo();

	my $sudoprompt = 'please_provide_' . (hasSudo()? 'sudoers' : 'root') . '_pwd_for_cron_restart';
	if (%{$opconf} and $opconf->{'restartcmd'} ne '') {
		unlink($AppConfig::cronlockFile);
		my $restartcmd = getSudoSuCMD("$opconf->{'restartcmd'} >/dev/null 2>&1", $sudoprompt);
		my $res = system($restartcmd);
        # sleep(15) unless($res > 0); #Changed 5 to 15 sec for Suruchi_2.32_09_1 : Senthil
        if($res == 0) {
traceLog("Waiting to restartIDriveCRON");
            my $minsToWait = 300; #5 Mins
            my $sleepSec   = 5;
            while($minsToWait) {
                sleep($sleepSec);
                $minsToWait -= $sleepSec;
                last if(checkCRONServiceStatus() == CRON_RUNNING);
            }
traceLog("minsToWait1:$minsToWait");
        }
	}
	else {
		unlink($AppConfig::cronlockFile) if (-e $AppConfig::cronlockFile);
		my $restartcmd = getSudoSuCMD("$AppConfig::perlBin '$AppConfig::cronLinkPath' >/dev/null 2>&1", $sudoprompt);
		my $res = system($restartcmd);
        # sleep(15) unless($res > 0); #Changed 5 to 15 sec for Suruchi_2.32_09_1 : Senthil
        unless($res > 0)
        {
traceLog("Waiting to restartIDriveCRON");
            my $minsToWait = 300; #5 Mins
            my $sleepSec   = 5; 
            while($minsToWait){
                sleep($sleepSec);
                $minsToWait -= $sleepSec;
                last if(checkCRONServiceStatus() == CRON_RUNNING);
            }
traceLog("minsToWait2:$minsToWait");
        }        
	}

	my @newlock = getCRONLockInfo();

	my $restartstat = 0;
	$restartstat 	= 1 if (!defined($oldlock[0]) && defined($newlock[0]));
	$restartstat 	= 1 if (defined($oldlock[0]) && defined($newlock[0]) && $oldlock[0] != $newlock[0]);

	display([((checkCRONServiceStatus() == CRON_RUNNING && $restartstat)? $restartflag . 'started_cron_service' : 'failed_to_' . $restartflag . 'start_cron'), '.']) if ($display);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: restartAllCDPServices
# Objective				: This is to restart CDP services
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub restartAllCDPServices {
	my $reflag	= isCDPServicesRunning()? 're' : '';
	my $cdphalt	= getCDPHaltFile();
	display(["\n", $reflag . 'starting_cdp_services'], '...') if(defined($_[0]) && $_[0] == 1);

	unlink($cdphalt) if(-f $cdphalt);
	stopCDPWatcher();
	stopCDPClient();
	stopCDPServer();
	stopDBService();
	startCDPWatcher();

	display([$reflag . 'startred_cdp_services'], '.') if(defined($_[0]) && $_[0] == 1);
}

#*****************************************************************************************************
# Subroutine			: restartDBServices
# Objective				: This is to restart DB services
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
# sub restartDBServices {
	# my $reflag = isDBWriterRunning()? 're' : '';
	# display(["\n", $reflag . 'starting_db_services', '...']) if(defined($_[0]) && $_[0] == 1);

	# stopDBService();
	# startDBWriter();

	# display([$reflag . 'startred_db_services', '.']) if(defined($_[0]) && $_[0] == 1);
# }

#*****************************************************************************************************
# Subroutine			: renameCDPLogAsRunning
# Objective				: Helps to rename the existing log to running status
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub renameCDPLogAsRunning {
	return $_[0] if(!$_[0] || !-f $_[0]);

	my $logpath = $_[0];
	my $logdir	= dirname($logpath);
	my @logname	= split('_', basename($logpath));
	$logname[1]	= 'Running';

	my $newlog	= getCatfile($logdir, join('_', @logname));
	move($logpath, $newlog);

	return $newlog;
}

#*****************************************************************************************************
# Subroutine			: resetUserCRONSchemas
# Objective				: This is to reset user cron schemas
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub resetUserCRONSchemas {
	my @jobTypes = ("backup", "backup", "cancel", "cancel", "archive", "cdp");
	my @jobNames = ("default_backupset", "local_backupset", "default_backupset", "local_backupset", "default_backupset", "default_backupset");

	lockCriticalUpdate("cron");
	loadCrontab(1);

	for my $i (0 .. $#jobNames) {
		createCrontab($jobTypes[$i], $jobNames[$i], \%AppConfig::crontabSchema);
	}

	unless($_[0]) {
		createCrontab($AppConfig::dashbtask, $AppConfig::dashbtask);
		setCronCMD($AppConfig::dashbtask, $AppConfig::dashbtask);
		saveCrontab();
	}

	unlockCriticalUpdate("cron");
	setUserConfiguration('CDP', 0);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: removeEntryInCrontabLines
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub removeEntryInCrontabLines
{
	my $jobExists = getAppPath();
	my @linesCrontab = @_;
	my @updatedLinesCrontab = grep !/$jobExists/, @linesCrontab;
	return @updatedLinesCrontab;
}

#*****************************************************************************************************
# Subroutine			: readCrontab
# Objective				:
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub readCrontab {
	my @linesCrontab = ();
	my $crontabFilePath = '/etc/crontab';

	if (-l $crontabFilePath){
		my $crontabFilePath_bak = $crontabFilePath."_bak";
		my $res = system(updateLocaleCmd("mv $crontabFilePath $crontabFilePath_bak 2>/dev/null"));
		if ($res ne "0") {
			traceLog("Unable to move crontab link file");
		}
		elsif (open CRONTABFILE, ">", $crontabFilePath){
			close CRONTABFILE;
			chmod 0644, $crontabFilePath;
		} else {
			traceLog("Couldn't open file $crontabFilePath");
		}
	} elsif(-f $crontabFilePath) {
		if (open CRONTABFILE, "<", $crontabFilePath){
			@linesCrontab = <CRONTABFILE>;
			close CRONTABFILE;
		} else {
			traceLog("Couldn't open file $crontabFilePath");
		}
	}

	return @linesCrontab;
}

#*****************************************************************************************************
# Subroutine	: readJSONFileToHash
# In Param		: Path
# Out Param		: Hash
# Objective		: Reads the JSON file data to a hash
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub readJSONFileToHash {
	my $rfile = $_[0];
	my %nhash = ();

	return {} if(!$rfile or !-f $rfile or -z $rfile);

	eval {
		%nhash = %{JSON::from_json(getFileContents($rfile))};
		1;
	};

	return \%nhash;
}

#*****************************************************************************************************
# Subroutine			: removeItems
# Objective				: Centralized all the remove commands and loaded all the files to a trace file.
# Added By				: Anil Kumar
# Modified By           : Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub removeItems {
	my $lastItem = "";
	my $path = $_[0];
	my @list = ();

	if (reftype(\$path) eq 'SCALAR') {
		chomp($path);
		push(@list, $path);
	}
	else {
		for my $i (0 .. $#{$path}) {
			next unless(defined($path->[$i]));
			chomp($path->[$i]);
			push(@list, $path->[$i]);
		}
	}

	foreach my $pathVal (@list) {
		my $val = $pathVal || '';

		next if (($val eq "/") or ($val eq "")or ($val eq "*"));

		$val = getItemFullPath($val);
		chomp($val);

		next if(!$val);

		my ($package, $filename, $line) = caller;
		my $callerInfo = " [ " . basename($filename). "] [Line:: ". $line." ] ";
		my $cmd = 'rm';
		$lastItem = "";
		if (!-f $val && !-d $val){
			my @spl = split('/', $val);
			$lastItem = pop @spl;
			$val = join("/", @spl)."/";
		}

		if (-d $val) {
			my $checkPath  = substr $val, -1;
			$checkPath = substr($val, 0, -1) if ($checkPath eq '/');

			next if (($checkPath eq "/") or ($checkPath eq "") or (getServicePath() eq $checkPath) or (getAppPath() eq $checkPath));
			$cmd .= " -rf '$val'$lastItem";
		}
		elsif (-f $val) {
			$cmd .= " -f '$val'";
		}
		else {
			# could be a link or may not exist
		}

		if ($cmd ne 'rm') {
			# my $traceLog = "/tmp/idriveTraceLog.txt";
			# writeToTrace($traceLog, $callerInfo.$val.$lastItem."\n");
			$cmd = updateLocaleCmd($cmd);
			system($cmd);
		}
	}
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : removeUsersCronEntry
# Objective               : This subroutine will remove the cron entry of particular IDrive user.
# Added By				  : Senthil Pandian
# Modified By			  : Sabin Cheruvattil
#*****************************************************************************************************/
sub removeUsersCronEntry {
	loadUsername() or return;
	my $userName = getUsername();

	lockCriticalUpdate("cron");
	loadCrontab(1);
	if ($crontab{$AppConfig::mcUser}{$userName}){
		delete $crontab{$AppConfig::mcUser}{$userName};
	}

	saveCrontab();
	unlockCriticalUpdate("cron");
}

#****************************************************************************************************
# Subroutine		: removeIDriveUserFromUsersList
# Objective			: This subroutine will remove the entry from idriveuser.txt.
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub removeIDriveUserFromUsersList {
	my $userfile = getCatfile(getServicePath(), $AppConfig::cachedIdriveFile);
	return unless(-f $userfile);

	my $usrtxt = getFileContents($userfile);
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		if ($usrtxt->{$AppConfig::mcUser}){
			fileWrite(getCatfile(getServicePath(), $AppConfig::cachedIdriveFile), JSON::to_json($usrtxt));
		}
	}
}

#*******************************************************************************************************
# Subroutine Name         :	removeLastSlash
# Objective               :	Remove the last slash if it present at end of string
# Added By                : Senthil Pandian
#********************************************************************************************************/
sub removeLastSlash {
	my $item = $_[0];
	if ($item ne "" && $item ne "/" && substr($item, -1, 1) eq "/") {
		chop($item);
	}
	return $item;
}

#*******************************************************************************************************
# Subroutine Name         :	removeMultipleSlashs
# Objective               :	Replace multiple slashes with single slash in a string
# Added By                : Senthil Pandian
#********************************************************************************************************/
sub removeMultipleSlashs {
	my $item = $_[0];
	if ($item ne "") {
		$item =~ s/[\/]+/\//g; #Removing "/" if more than one found at beginning/end
	}
	return $item;
}

#------------------------------------------------- S -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: saveLog
# Objective				: Save log files to cloud
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub saveLog {
	return if ($AppConfig::appType eq 'IBackup');
	return uploadLog($_[0], $_[1]);
}

#*****************************************************************************************************
# Subroutine	: saveWebViewXML
# In Param		: String | Log Path
# Out Param		: Status | Boolean
# Objective		: Places a request for express backup verification
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub saveWebViewXML {
	my $wvc		= $_[0];
	my $wvdir	= getWebViewDir();
	my $xmlfile	= strftime("%m-%d-%Y", localtime) . '.xml';
	my @files	= glob(getECatfile($wvdir) . '/*.xml');

	createDir($wvdir) unless(-d $wvdir);

	for my $fidx (0 .. $#files) {
		unlink($files[$fidx]) if(basename($files[$fidx]) ne $xmlfile && -f $files[$fidx]);
	}

	generateWebViewXML(getCatfile($wvdir, $xmlfile), $wvc);

	saveLog(getCatfile($wvdir, $xmlfile), 1);
}

#*****************************************************************************************************
# Subroutine			: saveMigratedLog
# Objective				: Save migrated log files to cloud
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub saveMigratedLog {
	my $cmd = updateLocaleCmd( 'perl ' .getScript('utility', 1) .' UPLOADMIGRATEDLOG ' . " 2> /dev/null &");
	system($cmd);
}

#*****************************************************************************************************
# Subroutine	: saveEncryptedBackupset
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Save backup set in encrypted format
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub saveEncryptedBackupset {
	my $bsf			= $_[0];
	my $backupset	= $_[1];
	my $bsc			= '';

	return 0 if(!$bsf);

	$bsc	= (reftype(\$backupset) eq 'SCALAR')? $backupset : join("\n", @{$backupset});
	$bsc	= encryptString($bsc);

	fileWrite($bsf, $bsc);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: sendMail
# Objective				: sends a mail to the user in case of successful/canceled/ failed scheduled backup/restore.
# Added By				: Dhritikana
# Modified By			: Vijay Vinoth, Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub sendMail {
	if (!exists($_[0]->{'serviceType'}) or !$_[0]->{'serviceType'} or lc($_[0]->{'serviceType'}) eq 'manual') {
		return 0;
	}

    my @emailSettings = &checkEmailNotify($_[0]->{'jobType'}, $_[0]->{'jobName'} );
	if ($emailSettings[0] eq 'DISABLED') {
		return 1;
	}

	if (($emailSettings[0] eq 'notify_failure') and ($_[0]->{'jobStatus'} eq 'success')) {
		return 0;
	}

	my $configEmailAddress = $emailSettings[1] if (defined $emailSettings[1]);

	my $finalAddrList = getFinalMailAddrList($configEmailAddress);
	if ($finalAddrList eq 'NULL') {
		return 0;
	}

	my $uname = getUsername();
	# my $pData = &getPdata($uname);
	# if ($pData eq ''){
		# traceLog(['failed_to_send_mail', 'password_missing']);
		# return 0;
	# }

	my $content = "";

	$content = "Dear $AppConfig::appType User, \n\n";
	$content .= "Ref: Username - $uname \n";

	$content .= $AppConfig::mailContentHead;
	if (exists ($_[0]->{'errorMsg'}) and ($_[0]->{'errorMsg'} eq 'NOBACKUPDATA')) {
		$content .= $LS{'unable_to_perform_backup_operation'}.$lineFeed.$lineFeed;
	}
	elsif (exists ($_[0]->{'errorMsg'}) and ($_[0]->{'errorMsg'} eq 'NORESTOREDATA')) {
		$content .= $LS{'unable_to_perform_restore_operation'}.$lineFeed.$lineFeed;
	}
	else {
		$content .= exists($LS{$AppConfig::mailContent})? $LS{$AppConfig::mailContent} : $AppConfig::mailContent;
        $content .= $lineFeed;
	}

	$content .= "Regards, \n";
	$content .= "$AppConfig::appType Support.\n";
	$content .= "Version: $AppConfig::version\n";
	$content .= "Release date: $AppConfig::releasedate" ;

	my $response = makeRequest(16, [
		$finalAddrList,
		$_[0]->{'subject'},
		$content
	]);

	if(!$response || (reftype \$response eq 'REF' && $response->{STATUS} ne 'SUCCESS')) {
		traceLog(['failed_to_send_mail', " Reason: ".$response->{DATA}]);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: setCronCMD
# Objective				: Prepare cron command for available jobs
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Anil Kumar
#****************************************************************************************************/
sub setCronCMD {
	my $jobType = $_[0];
	$jobType = $AppConfig::availableJobsSchema{$jobType}{'type'} if (exists $AppConfig::availableJobsSchema{$jobType});
	my $jt = $jobType;
	$jobType = 'backup' if ($jobType eq 'local_backup'); # TODO: IMPORTANT to review this statement again.
	my $runas = 0;
	my %status = ();
	$status{"status"} = AppConfig::FAILURE;
	$status{"errmsg"} = '';
	if (getCrontab($jobType, $_[1], '{settings}{frequency}') eq 'immediate') {

		# to intimate response to dashboard for start immediately.
		$jt = 'localbackup' if ($jt eq 'local_backup');

		# my $isBackupRunning = 1;
		# $isBackupRunning = isJobRunning($jt,$AppConfig::dashbtask);
		# if ($isBackupRunning) {
			# $status{"status"} = AppConfig::FAILURE;
			# $status{"errmsg"} = $LS{$jt.'_in_progress_try_again'} ;
			# return %status;
		# }

		if ($jt eq 'backup'){
			my $isArchiveRunning = 1;
			$isArchiveRunning = isJobRunning('archive');
			if ($isArchiveRunning) {
				$status{"status"} = AppConfig::FAILURE;
				$status{"errmsg"} = $LS{'archive_in_progress_try_again'} ;
				return %status;
			}
		}

		if (exists $AppConfig::availableJobsSchema{$jt}) {
			my $fileset = getJobsPath($jt, 'file');
			unless (-f $fileset and !-z $fileset) {
				$status{"status"} = AppConfig::FAILURE;
				$status{"errmsg"} = "$_[1]: is empty";
				return %status;
			}
		}
		$status{'status'} = AppConfig::SUCCESS;

		$runas = 1 ;
		my @now		= localtime;
		my $hrs = $now[2];
		my $min = $now[1];
		if ($min > 58) {
			$hrs = $hrs + 1;
			$min = -1;
		}
		setCrontab($jobType, $_[1], 'h', $hrs);
		setCrontab($jobType, $_[1], 'm', ($min + 1));
	}

	if ($jobType eq "cancel") {
		if ($_[1] eq 'default_backupset') {
			setCrontab($jobType, $_[1], 'cmd', sprintf("%s %s - 2", q(") . getScript('job_termination') . q("), 'backup'));
		}
		elsif ($_[1] eq 'local_backupset') {
			setCrontab($jobType, $_[1], 'cmd', sprintf("%s %s - 2", q(") . getScript('job_termination') . q("), 'localbackup'));
		}
		$status{'status'} = AppConfig::SUCCESS;
	}
	elsif (($jobType eq 'backup') and ($_[1] eq 'default_backupset')) {
		setCrontab($jobType, $_[1], 'cmd', sprintf($AppConfig::availableJobsSchema{$jobType}{'croncmd'}, q(") . getScript('backup_scripts') . q("), $AppConfig::availableJobsSchema{$jobType}{'runas'}->[$runas], getUsername()));
		$status{'status'} = AppConfig::SUCCESS;
	}
	elsif (($jobType eq 'backup') and ($_[1] eq 'local_backupset')) {
		setCrontab($jobType, $_[1], 'cmd', sprintf($AppConfig::availableJobsSchema{$jobType}{'croncmd'}, q(") . getScript('local_backup') . q("), $AppConfig::availableJobsSchema{$jobType}{'runas'}->[$runas], getUsername()));
		$status{'status'} = AppConfig::SUCCESS;
	}
	elsif ($jobType eq 'archive') {
		my $cmd = getCrontab($jobType, $_[1], '{cmd}');
		my @params = split(' ', $cmd);
		my @now     = localtime;

		if (scalar(@params) == 2) {
			push(@params, 0);
		}

		if (scalar(@params) == 3) {
			setCrontab($jobType, $_[1], 'cmd', sprintf($AppConfig::availableJobsSchema{$jobType}{'croncmd'}, q(") . getScript('archive_cleanup') . q("), getUsername(), $params[0], $params[1], mktime(@now), $params[2]));
	
			# Store previous minute
			my $acrchmin 	= $now[1];
			my $archhr		= $now[2];
	
			if ($acrchmin == 0) {
				$acrchmin 	= 59;
				$archhr		= (($archhr == 0)? 23 : ($archhr - 1));
			} else {
				$acrchmin--;
			}
	
			setCrontab($jobType, $_[1], 'h', $archhr);
			setCrontab($jobType, $_[1], 'm', $acrchmin);
		}
		$status{'status'} = AppConfig::SUCCESS;
	}
	elsif ($jobType eq $AppConfig::dashbtask) {
		if ($AppConfig::appType eq 'IDrive') {
			setCrontab($jobType, $_[1], 'cmd', getDashboardScript());
		}
		else {
			setCrontab($jobType, $_[1], 'cmd', getScript('cron'));
		}
		$status{'status'} = AppConfig::SUCCESS;
	}
	elsif ($jobType eq $AppConfig::cdpwatcher) {
		setCrontab($jobType, $_[1], 'cmd', q(") . getScript('utility') . q("). ' CDP');
		$status{'status'} = AppConfig::SUCCESS;
	} elsif ($jobType eq $AppConfig::cdp) {
		$runas	= 2;
		setCrontab($jobType, $_[1], 'cmd', sprintf($AppConfig::availableJobsSchema{$jobType}{'croncmd'}, q(") . getScript('backup_scripts') . q("), $AppConfig::availableJobsSchema{$jobType}{'runas'}->[$runas], getUsername()));
		$status{'status'} = AppConfig::SUCCESS;
	} elsif ($jobType eq $AppConfig::cdprescan) {
		setCrontab($jobType, $_[1], 'cmd',  q(") . getScript('utility').  q(") . " CDPRESCAN " . $_[2]);
		$status{'status'} = AppConfig::SUCCESS;
	}

	return %status;
}

#*****************************************************************************************************
# Subroutine			: setRestoreFromLocPrompt
# Objective				: Set restore location prompt
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub setRestoreFromLocPrompt {
	my $prevStatus  = 'enabled';
	my $statusQuest = 'disable';
	
	unless($AppConfig::isautoinstall) {
		if (getUserConfiguration('RESTORELOCATIONPROMPT') ne '' || defined($_[0])) {
			if (!getUserConfiguration('RESTORELOCATIONPROMPT') && !defined($_[0])) {
				$prevStatus  = 'disabled';
				$statusQuest = 'enable';
			}
			display(["\n",'restore_loc_prompt_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
			my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);
			$choice = lc($choice);
			return 1 if ($choice eq "n");
		}
	} else {
		$prevStatus = 'disabled';
	}

	if($AppConfig::isautoinstall) {
		my $msg	= getStringConstant('auto_restore_loc_prompt');
		display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', 'cc_enabled']);
	} else {
		display(['restore_loc_prompt_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);
	}

	setUserConfiguration('RESTORELOCATIONPROMPT', ($prevStatus eq 'disabled')? 1 : 0);
	return 1;
}

#*****************************************************************************************************
# Subroutine		: setNotifySoftwareUpdate
# Objective			: Set software update status to configuration
# Added By			: Anil Kumar
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************
sub setNotifySoftwareUpdate {
	my $promptSelected;
	my $status;

	unless($AppConfig::isautoinstall) {
		if (defined getUserConfiguration('NOTIFYSOFTWAREUPDATE')) {
			$status = getUserConfiguration('NOTIFYSOFTWAREUPDATE');
		}
		else {
			$status = 1;
		}

		$promptSelected = ($status)? 'software_update_prompt_enabled_with_disable_choice' : 'software_update_prompt_disabled_with_enable_choice';
		display(["\n",$promptSelected], 1);
		my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);
		return 1 if (lc($choice) eq "n");
	} else {
		$status = 1;
	}

	setUserConfiguration('NOTIFYSOFTWAREUPDATE', ($status)? 0 : 1);
	
	if($AppConfig::isautoinstall) {
		my $msg	= getStringConstant('notify_software_update');
		display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', 'cc_disabled']);
	} else {
		display(['software_update_prompt_' . ($status? 'disabled' : 'enabled')]);
	}

	return 1;
}


#*****************************************************************************************************
# Subroutine			: setUploadMultipleChunks
# Objective				: Set engine count
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub setUploadMultipleChunks {
	my $promptSelected;
	my $chunksenabled = 1;
	if (getUserConfiguration('ENGINECOUNT') ne '') {
		$chunksenabled = (getUserConfiguration('ENGINECOUNT') == $AppConfig::minEngineCount)? 0 : 1;
		display(["\n", "upload_multiple_chunks_$chunksenabled", " ", 'do_you_want_to_' . ($chunksenabled? 'disable' : 'enable')]);
		my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);

		return 1 if (lc($choice) eq "n");
	} else {
		# $chunksenabled = 0;
		display(["\n", "upload_multiple_chunks_$chunksenabled", " ", 'do_you_want_to_' . ($chunksenabled? 'disable' : 'enable')]);
	}

	my @appjobs = ('backup', 'localbackup');
	my %progjobs = getRunningJobs(\@appjobs);

	if(%progjobs) {
		display(["\n", 'backup_job_in_progress_change_engine_terminates_jobs', ' ', 'do_you_want_to_continue_yn']);
		my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);

		return 1 if (lc($choice) eq "n");

		foreach my $jt (keys %progjobs) {
			# my $cmd = ("$AppConfig::perlBin " . getScript('job_termination', 1) . " $jt " . getUsername() . ' 1>/dev/null 2>/dev/null &');
			my $cmd = sprintf("%s %s $jt - 0 allType %s %s 1>/dev/null 2>/dev/null &", $AppConfig::perlBin, getScript('job_termination', 1), $AppConfig::mcUser, 'operation_cancelled_by_user');
			system($cmd);
		}
	}

	setUserConfiguration('ENGINECOUNT', ($chunksenabled)? $AppConfig::minEngineCount : $AppConfig::maxEngineCount);
	display(['upload_multiple_chunks_' . (($chunksenabled)? 'disabled' : 'enabled')]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setUsername
# Objective				: Assign username
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setUsername {
	$username = $_[0];
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setTotalStorage
# Objective				: Save total storage space of the current logged in user to $totalStorage
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setTotalStorage {
	$totalStorage = getHumanReadableSizes($_[0]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setStorageUsed
# Objective				: Save storage used space of the current logged in user to $storageUsed
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setStorageUsed {
	$storageUsed = getHumanReadableSizes($_[0]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setUserConfiguration
# Objective				: Set user configuration values
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub setUserConfiguration {
	my $data;
	if (reftype(\$_[0]) eq 'SCALAR') {
		if (defined($_[1])) {
			$data = [{$_[0] => $_[1]}];
		}
		else {
			$data = [{$_[0] => ''}];
		}
	}
	else {
		$data = [$_[0]];
	}

	my %cgiNames;
	my %evsNames;
	my $keystring;
	my $isNothingFound = 1;
	for my $i (0 .. $#{$data}) {
		for my $key (keys %{$data->[$i]}) {
			$keystring = $key;
			unless (exists $AppConfig::userConfigurationSchema{$key}) {
				unless (%cgiNames or %evsNames) {
					for my $rhs (keys %AppConfig::userConfigurationSchema) {
						if ($AppConfig::userConfigurationSchema{$rhs}{'cgi_name'} ne '') {
							$cgiNames{$AppConfig::userConfigurationSchema{$rhs}{'cgi_name'}} = $rhs;
						}
						if ($AppConfig::userConfigurationSchema{$rhs}{'evs_name'} ne '') {
							$evsNames{$AppConfig::userConfigurationSchema{$rhs}{'evs_name'}} = $rhs;
						}
					}
				}

				if (exists $cgiNames{$key}) {
					$keystring = $cgiNames{$key};
					$isNothingFound = 0;
				}
				elsif (exists $evsNames{$key}) {
					$keystring = $evsNames{$key};
					$isNothingFound = 0;
				}
				else {
					#traceLog("user_configuration_".$key."_does_not_exists");
					next;
				}
			}

			if ($userConfiguration{$keystring}{'VALUE'} ne $data->[$i]{$key}) {
				$userConfiguration{$keystring}{'VALUE'} = $data->[$i]{$key};
				$modifiedUserConfig{$keystring}{'VALUE'} = $data->[$i]{$key};
				$isNothingFound = 0 if ($isNothingFound);
			}

			if($keystring eq 'WEBAPI' and $userConfiguration{$keystring}{'VALUE'} =~ /com/) {
				$userConfiguration{$keystring}{'VALUE'} = encodeServerAddress($userConfiguration{$keystring}{'VALUE'});
				$modifiedUserConfig{$keystring}{'VALUE'} = $userConfiguration{$keystring}{'VALUE'};
				$isNothingFound = 0 if ($isNothingFound);
			}
		}
	}

	unless ($isNothingFound) {
		$AppConfig::isUserConfigModified = 1;
		return 1;
	}

	$AppConfig::errorMsg = 'settings_were_not_changed';
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveServerAddress
# Objective				: Save user server address
# Added By				: Yogesh Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub saveServerAddress {
	my @data = @_;
	if (exists $data[0]->{$AppConfig::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}} or
			exists $data[0]->{$AppConfig::ServerAddressSchema{'SERVERADDRESS'}{'evs_name'}}) {

		my $gsa = getServerAddressFile();
		createDir(getUsersInternalDirPath('user_info')) if (!-d getUsersInternalDirPath('user_info'));

		if (open(my $fh, '>', $gsa)) {
			if (exists $data[0]->{$AppConfig::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}}) {
				print $fh $data[0]->{$AppConfig::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}};
			}
			else {
				print $fh $data[0]->{$AppConfig::ServerAddressSchema{'SERVERADDRESS'}{'evs_name'}};
			}
			close($fh);
			chmod $AppConfig::filePermission, $gsa;
			# return 1;
		} else {
			display("$0: close $gsa: $!");
		}
	}

	if (exists $data[0]->{$AppConfig::userConfigurationSchema{'EVSSRVR'}{'cgi_name'}} or
			exists $data[0]->{$AppConfig::ServerAddressSchema{'EVSSRVR'}{'evs_name'}}) {
		my $evssrvr = (exists $data[0]->{$AppConfig::userConfigurationSchema{'EVSSRVR'}{'cgi_name'}}) ? 	$data[0]->{$AppConfig::userConfigurationSchema{'EVSSRVR'}{'cgi_name'}} : $data[0]->{$AppConfig::userConfigurationSchema{'EVSSRVR'}{'evs_name'}};
		setUserConfiguration('EVSSRVR', $evssrvr);
		checkAndUpdateEVSDomainConnStat();
		saveUserConfiguration() or traceLog('failed_to_save_user_configuration') if(-f getUserConfigurationFile());
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveServicePath
# Objective				: Save user selected service path in the file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveServicePath {
	my $servicePathFile = ("$appPath/" . $AppConfig::serviceLocationFile);
	if (open(my $spf, '>', $servicePathFile)) {
		print $spf $_[0];
		close($spf);
		return 1;
	}
	display(["\n",'failed_to_open_file', " $servicePathFile. Reason: $!"]);
	return 0
}

#*****************************************************************************************************
# Subroutine			: saveUserQuota
# Objective				: Save user quota to quota file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveUserQuota {
	my $csf = getCachedStorageFile();
	my @data = @_;

	if (open(my $fh, '>', $csf)) {
		my $first = 1;
		for my $key (keys %AppConfig::accountStorageSchema) {
			# To read response from EVS.
			if (exists $data[0]->{lc($key)}) {
                ($first == 0) ? (print $fh "\n") : ($first = 0) ;
                print $fh "$key=".$data[0]->{lc($key)};
			}
			# To read response from CGI.
			elsif (exists
				$data[0]->{$AppConfig::accountStorageSchema{$key}{'cgi_name'}}) {
                ($first == 0) ? (print $fh "\n") : ($first = 0) ;
                print $fh "$key=".$data[0]->{$AppConfig::accountStorageSchema{$key}{'cgi_name'}};
			}
			elsif (exists
				$data[0]->{$AppConfig::accountStorageSchema{$key}{'evs_name'}}) {
				($first == 0) ? (print $fh "\n") : ($first = 0) ;
				print $fh "$key=".$data[0]->{$AppConfig::accountStorageSchema{$key}{'evs_name'}};
			}
		}
		close($fh);
		chmod 0777, $csf;
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveUserConfiguration
# Objective				: Save user selected configurations to a file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub saveUserConfiguration {
	return 1 unless ($AppConfig::isUserConfigModified);
	loadUserConfiguration();
	foreach (keys %modifiedUserConfig) {
		next if ($_ !~ m/PROXY|EMAILADDRESS|BACKUPLOCATION/ && $modifiedUserConfig{$_}{'VALUE'} eq '');
		$userConfiguration{$_}{'VALUE'} = $modifiedUserConfig{$_}{'VALUE'};
	}

	%modifiedUserConfig = ();
	$AppConfig::isUserConfigModified = 0;

	my $ucf = getUserConfigurationFile();
	unless (defined($_[1]) and $_[1]) {
		return 0 if (validateUserConfigurations() != 1);
	}
	if (open(my $fh, '>', $ucf)) {
		unless (flock($fh, LOCK_EX)) {
			traceLog("Cannot lock file $ucf $!");
			close($fh);
			return 0;
		}

		print $fh encryptString(JSON::to_json(\%userConfiguration));
		flock($fh, LOCK_UN);
		close($fh);

		unless (defined($_[0]) and $_[0] == 0) {
			if(loadNotifications() and lockCriticalUpdate("notification")) {
				setNotification('get_user_settings') and saveNotifications();
				unlockCriticalUpdate("notification");
			}
		}
		createUpdateBWFile();

		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: setRestoreLocation
# Objective				: Set restore location for the current user
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub setRestoreLocation {
	my $restoreLocation = '';
    my $prevRestoreLocation = getUserConfiguration('RESTORELOCATION');
    
	unless($AppConfig::isautoinstall) {
		display(["\n", 'enter_your_restore_location_optional', ": "], 0);
		$restoreLocation = getUserChoice();
		$restoreLocation =~ s/^~/getUserHomePath()/g;
	}

	my $defaultRestoreLocation = getUsersInternalDirPath('restore_data');
	if ($restoreLocation eq '') {
        if(defined($_[0]) and $prevRestoreLocation ne '' and -d $prevRestoreLocation) {
            $restoreLocation = $prevRestoreLocation;
            display(['your_restore_location_remains',"'$restoreLocation'."]);
        } else {
            $restoreLocation = getUsersInternalDirPath('restore_data');
            display(['considering_default_restore_location', "\"$defaultRestoreLocation\"."]) unless($AppConfig::isautoinstall);
            $restoreLocation = $defaultRestoreLocation;
        }
	}
	else {
		if (!-d $restoreLocation){
			display(['invalid_restore_location', "\"$restoreLocation\". ", "Reason: ", 'no_such_directory']);
			if(defined($_[0]) and $prevRestoreLocation ne '' and -d $prevRestoreLocation) {
                $restoreLocation = $prevRestoreLocation;
                display(['your_restore_location_remains',"'$restoreLocation'."]);
            } else {
                display(['considering_default_restore_location', "\"$defaultRestoreLocation\"."]);
                $restoreLocation = $defaultRestoreLocation;
            }
		}
		elsif (!-w $restoreLocation){
			display(['cannot_open_directory', ": ", "\"$restoreLocation\" ", " Reason: ", 'permission_denied']);
			if(defined($_[0]) and $prevRestoreLocation ne '' and -d $prevRestoreLocation) {
                $restoreLocation = $prevRestoreLocation;
                display(['your_restore_location_remains',"'$restoreLocation'."]);
            } else {
                display(['considering_default_restore_location', "\"$defaultRestoreLocation\"."]);
                $restoreLocation = $defaultRestoreLocation;
            }
		} else{
			display(["Restore Location ",  "\"$restoreLocation\" ", "exists."], 1);
		}
		$restoreLocation = getAbsPath($restoreLocation) or retreat('no_such_directory_try_again');
	}

	$restoreLocation .= '/' if(substr($restoreLocation,-1,1) ne '/'); #Adding '/' at end if its not
	display(['your_restore_location_is_set_to', " \"$restoreLocation\"."], 1) if(!$AppConfig::isautoinstall and !defined($_[0]));
	setUserConfiguration('RESTORELOCATION', $restoreLocation);
	saveUserConfiguration() if (defined($_[0]));
	return 1;
}

#*****************************************************************************************************
# Subroutine		: setRestoreFromLocation
# Objective			: This subroutine will set value to restore from location based on the required checks.
# Added By			: Anil Kumar
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub setRestoreFromLocation {
	my $rfl = getUserConfiguration('BACKUPLOCATION');
	my $removeDeviceID = (split('#', $rfl))[-1];
	my $choice = 'n';
	
	unless($AppConfig::isautoinstall) {
		display(["\n",'your_restore_from_device_is_set_to',(" \"" . $removeDeviceID . "\". "),'do_u_want_to_edit'],1);
		$choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}
	
	if (lc($choice) eq "y") {
		if (getUserConfiguration('DEDUP') eq 'on') {
			display(["\n",'loading_your_account_details_please_wait',"\n"],1);

			my @devices = fetchAllDevices();
			if ($devices[0]{'STATUS'} eq AppConfig::FAILURE) {
				if ($devices[0]{'MSG'} =~ 'No devices found') {
					retreat('your_account_not_configured_properly');
				}
			}
			elsif ($devices[0]{'STATUS'} eq AppConfig::SUCCESS) {
				linkBucket('restore', \@devices) or retreat('please_try_again');
				return 1;
			}
		}
		else {
			display(['enter_your_restore_from_location_optional', ": "], 0);
			my $bucketName = getUserChoice();
			if ($bucketName ne ""){
				display(['Setting up your restore from location...'], 1);
				if (substr($bucketName, 0, 1) ne "/") {
					$bucketName = "/".$bucketName;
				}

				if (open(my $fh, '>', getValidateRestoreFromFile())) {
					print $fh $bucketName;
					close($fh);
					chmod 0777, getValidateRestoreFromFile();
				}
				else
				{
					traceLog("failed to create file. Reason: $!");
					return 0;
				}
				my $evsErrorFile      = getUserProfilePath().'/'.$AppConfig::evsErrorFile;
				createUTF8File('ITEMSTATUS',getValidateRestoreFromFile(), $evsErrorFile,'') or retreat('failed_to_create_utf8_file');
				my @result = runEVS('item');
				if ($result[0]{'status'} =~ /No such file or directory|directory exists in trash/) {
					display(["Invalid Restore From location. Reason: Path does not exist."], 1);
					display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\".")],1);
					display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\".")],1);
				}
				else
				{
					$rfl = $bucketName;
					display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\".")],1);
				}

				unlink(getValidateRestoreFromFile());
			}
			else
			{
				display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\".")],1);
				display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\".")],1);
			}

			$rfl = removeMultipleSlashs($rfl);
			$rfl = removeLastSlash($rfl);
			setUserConfiguration('RESTOREFROM', $rfl);
		}
	}
	else {
		my $removeDeviceID = (split('#', $rfl))[-1];

		$rfl = removeMultipleSlashs($rfl);
		$rfl = removeLastSlash($rfl);
		setUserConfiguration('RESTOREFROM', $rfl);
		display(['your_restore_from_device_is_set_to',(" \"" . $removeDeviceID . "\".")], 1) unless($AppConfig::isautoinstall);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: setBackupToLocation
# Objective				: Set backup to location for the current user
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub setBackupToLocation {
	if (getUserConfiguration('DEDUP') eq 'on') {
		display('identifying_your_backup_location_please_wait');
		my @result = fetchAllDevices();
		#Added to consider the bucket type 'D' only
		my @devices;
		foreach (@result){
			next if(!defined($_->{'bucket_type'}) or ($_->{'bucket_type'} !~ /D/) or ($_->{'in_trash'} eq '1'));
			push @devices, $_;
		}

		unless(scalar(@devices)>0) {
			display('no_backup_location_found_please_create_new_one');
			return createBucket();
		}

		if ($devices[0]{'STATUS'} eq AppConfig::FAILURE) {
			if ($devices[0]{'MSG'} =~ 'No devices found') {
				display('no_backup_location_found_please_create_new_one');
				return createBucket();
			}
			else {
				display($devices[0]{'MSG'}, 1);
			}
		}
		elsif ($devices[0]{'STATUS'} eq AppConfig::SUCCESS) {
=beg
			unless (findMyDevice(\@devices, 'editMode', $_[0])) {
				my $status = askToCreateOrSelectADevice(\@devices);
				retreat('failed_to_set_backup_location') unless($status);
				return $status;
			}
=cut

			unless (findMyDevice(\@devices, 'editMode', $_[0])) {
				my %buckets = findMyBuckets(\@devices);
				unless (scalar(keys %buckets)) {
					my $status = askToCreateOrSelectADevice(\@devices);
					retreat('failed_to_set_backup_location') unless($status);
					return $status;
				} else {
					getExistingBucketConfirmation(\@devices, \%buckets);
				}			
			}
			return 1;
		}
	}
	elsif (getUserConfiguration('DEDUP') eq 'off') {
        my $userInput = '';
        my $backupLoc = getUserConfiguration('BACKUPLOCATION');
        if(!defined($backupLoc) or $backupLoc eq '') {
            $backupLoc = $AppConfig::hostname;
            $backupLoc =~ s/[^a-zA-Z0-9_-]//g;
            $backupLoc = "/".$backupLoc;

            display(['your_backup_to_device_name_is',(" \"" . $backupLoc . "\". "),'do_you_want_edit_this_y_or_n_?'], 1);
            my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
            if (lc($answer) eq 'y') {
                $userInput = getAndValidate(["\n", 'enter_your_ndedup_backup_location_optional',": "], "backup_location", 1);
            }
        } else {
            $userInput = getAndValidate(["\n", 'enter_your_ndedup_backup_location_optional',": "], "backup_location", 1);
        }

		display('setting_up_your_backup_location', 1);
        if ($userInput ne '') { 
            $userInput =~ s/^\/+$|^\s+\/+$//g; ## Removing if only "/"(s) to avoid root
            $backupLoc = $userInput;
        }

		createUTF8File('CREATEDIR', $backupLoc) or
			retreat('failed_to_create_utf8_file');
		my @responseData = runEVS('item');
		if ($responseData[0]->{'STATUS'} eq AppConfig::SUCCESS or ($responseData[0]->{'STATUS'} eq AppConfig::FAILURE and $responseData[0]->{'MSG'} =~ /file or folder exists/)){
			setUserConfiguration('BACKUPLOCATION', $backupLoc);
			display(['your_backup_to_device_name_is',(" \"" . $backupLoc . "\".")]);
			if(loadNotifications() and lockCriticalUpdate("notification")) {
				setNotification('register_dashboard') and saveNotifications();
				unlockCriticalUpdate("notification");
			}

			createBackupStatRenewalByJob('backup') if(getUsername() ne '' && getLoggedInUsername() eq getUsername());
			# fire folder size evs and store folder size
			setBackupLocationSize();
			return 1;
		}
	}
	else {
		retreat('Unable_to_find_account_type_dedup_or_no_dedup');
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine	: setBackupLocationSize
# In Param		: Save | Boolean
# Out Param		: Size | Integer
# Objective		: Check and set the backup location size if it is non-dedup account
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub setBackupLocationSize {
	return 0 if(getUserConfiguration('DEDUP') ne 'off');

	my $save	= $_[0]? 1 : 0;
	my $size	= getBackupLocationSize();
	
	setUserConfiguration('BACKUPLOCATIONSIZE', $size);
	saveUserConfiguration() if($save);
	
	return $size;
}

#*****************************************************************************************************
# Subroutine			: setNotification
# Objective				: set notification value to notifications
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub setNotification {
	return if($AppConfig::appType eq 'IBackup');

	if (not exists $notifications{$_[0]} and exists $AppConfig::notificationsSchema{$_[0]}) {
		$notifications{$_[0]}        = $AppConfig::notificationsSchema{$_[0]};
		$modifiedNotifications{$_[0]}= $AppConfig::notificationsSchema{$_[0]};
	}

	if (exists $notifications{$_[0]}) {
		if (defined($_[1])) {
			$notifications{$_[0]}         = $_[1];
			$modifiedNotifications{$_[0]} = $_[1];
		}
		else {
			my $randomChars = '';
			$randomChars .= sprintf("%x", rand 16) for 1..9;
			$notifications{$_[0]}         = $randomChars;
			$modifiedNotifications{$_[0]} = $randomChars;
		}
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveNotifications
# Objective				: save notification values to a file
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub saveNotifications {
	return if ($AppConfig::appType eq 'IBackup');

	my $nf = getNotificationFile();

	if (open(my $fh, '+<', $nf)) {
		unless (flock($fh, LOCK_EX)) {
			traceLog("Cannot lock file $nf $!");
			close($fh);
			return 0;
		}
		my $nc = <$fh>;
		seek $fh, 0, 0;
		truncate $fh, 0;
		if ($nc and $nc ne '') {
			%notifications = %{JSON::from_json($nc)};
		}
		else {
			%notifications = ();
		}

		foreach(keys %modifiedNotifications) {
			if (exists $AppConfig::notificationsSchema{$_}) {
				$notifications{$_} = $modifiedNotifications{$_};
			}
		}

		print $fh JSON::to_json(\%notifications);
		close($fh);
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveNS
# Objective				: save ns values to a file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveNS {
	return if ($AppConfig::appType eq 'IBackup');
	my $fh = shift;

	my $nsf = getNSFile();

	seek $fh, 0, 0;
	truncate $fh, 0;

	print $fh JSON::to_json(\%ns) if (%ns);
	return 1;

	return 0;
}

#*****************************************************************************************************
# Subroutine			: setCrontab
# Objective				: set crontab value to crontab
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub setCrontab {
	my $jobType = shift  || retreat('crontabs_jobname_is_required');
	my $jobName = shift  || retreat('crontab_title_is_required');
	my $key     = shift;
	my $value   = shift;

	$jobType = $AppConfig::availableJobsSchema{$jobType}{'type'} if (exists $AppConfig::availableJobsSchema{$jobType});
	$jobType = 'backup' if ($jobType eq 'local_backup'); # TODO: IMPORTANT to review this statement again.

	unless (exists $crontab{$AppConfig::mcUser} and exists $crontab{$AppConfig::mcUser}{$username}
		and exists $crontab{$AppConfig::mcUser}{$username}{$jobType}
		and exists $crontab{$AppConfig::mcUser}{$username}{$jobType}{$jobName}) {
		#$crontab{$jobType}{$jobName} = \%AppConfig::crontabSchema;
		return 0;
	}

	if (ref($key) eq 'HASH') {
		%crontab = %{deepCopyEntry(\%crontab, {$AppConfig::mcUser => {$username => {$jobType => {$jobName => $key}}}})};
	}
	else {
		if ($key eq 'h' && $value ne '*'){ $value = ($value > 23)?23:$value; }
		if ($key eq 'm' && $value ne '*') {
			if($value !~ /\*\/\d/) {
				$value = ($value > 59)? 59 : $value;
			}
		}

		%crontab = %{deepCopyEntry(\%crontab, {$AppConfig::mcUser => {$username => {$jobType => {$jobName => {$key => $value}}}}})};
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: setDefaultCDPJob
# Objective				: Helps to add CDP default cron job
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub setDefaultCDPJob {
	return 0 unless($_[0]);

	lockCriticalUpdate("cron");
	loadCrontab(1);

	my $interval	= $_[0];
	my $status		= $_[1]? 'enabled' : 'disabled';
	my $jobType		= $AppConfig::cdp;
	my $jobName		= "default_backupset";

	createCrontab($jobType, $jobName);
	setCrontab($jobType, $jobName, {'settings' => {'status' => $status}});
	setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'hourly'}});

	if($interval eq '60') {
		setCrontab($jobType, $jobName, 'm', "00");
	} else {
		setCrontab($jobType, $jobName, 'm', "*/$interval");
	}

	setCrontab($jobType, $jobName, 'h', '*');
	setCrontab($jobType, $jobName, 'dow', '*');
	setCrontab($jobType, $jobName, 'mon', '*');
	setCrontab($jobType, $jobName, 'dom', '*');

	setCronCMD($jobType, $jobName);
	saveCrontab($_[2]? 0 : 1);
	unlockCriticalUpdate("cron");

	setUserConfiguration('CDP', int($interval));
}

#*****************************************************************************************************
# Subroutine			: setCDPRescanCRON
# Objective				: Helps to add CDP rescan cron job
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#*****************************************************************************************************
sub setCDPRescanCRON {
	return if(!$_[0] or !canKernelSupportInotify());

	# If number of days is 0, then save default values.
	if (int($_[0]) == 0) {
		$_[0] = $AppConfig::defrescanday;
		$_[1] = $AppConfig::defrescanhr;
		$_[2] = $AppConfig::defrescanmin;
		$_[3] = 1;
	}

	lockCriticalUpdate("cron");
	loadCrontab(1);
	my $jobType		= $AppConfig::cdprescan;
	my $jobName		= 'default_backupset';

	createCrontab($jobType, $jobName);
	
	setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
	setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'daily'}});

	setCrontab($jobType, $jobName, 'h', sprintf("%02d", $_[1]));
	setCrontab($jobType, $jobName, 'm', sprintf("%02d", $_[2]));
	setCrontab($jobType, $jobName, 'dow', '*');
	setCrontab($jobType, $jobName, 'mon', '*');
	setCrontab($jobType, $jobName, 'dom', "*");

	my @now = localtime;
	setCronCMD($jobType, $jobName, "$_[0] " . mktime(@now));
	saveCrontab($_[3]? 0 : 1);
	unlockCriticalUpdate("cron");
	
	setUserConfiguration('RESCANINTVL', qq($_[0]:$_[1]:$_[2])) if($_[3]);

	return 1;
}

#*****************************************************************************************************
# Subroutine	: setCDPInotifySupport
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Sets CDP support status to user configuration
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub setCDPInotifySupport {
	loadUserConfiguration();
	setUserConfiguration('CDPSUPPORT', canKernelSupportInotify());
	saveUserConfiguration(0, 1);
}

#*****************************************************************************************************
# Subroutine			: saveCrontab
# Objective				: save crontab values to a file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub saveCrontab {
	my $nf = getCrontabFile();
	if (open(my $fh, '+<', $nf)) {
		unless (flock($fh, LOCK_EX)) {
			traceLog("Cannot lock file $nf $!");
			close($fh);
			return 0;
		}
		seek $fh, 0, 0;
		truncate $fh, 0;
		print $fh encryptString(JSON::to_json(\%crontab));
		close($fh);
		chmod($AppConfig::filePermission, $nf);
		if(loadNotifications() and lockCriticalUpdate("notification")) {
			setNotification('get_scheduler') and saveNotifications() unless (defined($_[0]) and ($_[0] == 0));
			unlockCriticalUpdate("notification");
		}

		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: selectLogsBetween
# Objective				: select logs files between given two dates
# Added By				: Yogesh Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub selectLogsBetween {
	my %logStat = ();
	my %logFilenames = ();

	unless (defined($_[1]) and defined($_[2])) {
		retreat('start_and_end_dates_are_required');
	}

	#Added for Dashboard
	if (!defined($_[0]) and defined($_[3])) {
		my $jobDir = (fileparse($_[3]))[0];
		if ($jobDir =~ m/\/LOGS\//){
			$jobDir =~ s/LOGS\///;
		}
		getLogsList($jobDir);
	}

	if (defined($_[3])) {
		my @t1 = localtime($_[1]);
		$t1[5] += 1900;
		$t1[4] += 1;
		my @t2 = localtime($_[2]);
		$t2[5] += 1900;
		$t2[4] += 1;

		my $tempLogFile;
		my $logInStrings = '';
		my $mon;
		my $pmon;
		for(my $y=$t1[5]; $y <= $t2[5]; $y++) {
			$mon = ($y == $t2[5])? $t2[4] : 12;
			$pmon = ($t1[4] > $mon)? $mon : $t1[4];

			for(my $m=$pmon; $m <= $mon; $m++) {
				my($filename, $directories, $suffix) = fileparse($_[3]);
				$filename = sprintf($filename, $m, $y);
				$tempLogFile = getCatfile($directories,$filename);
				if (-f $tempLogFile) {
					$logInStrings .= getFileContents($tempLogFile);
				}
			}
		}

		if ($logInStrings ne '') {
			$logInStrings .= '}';
			substr($logInStrings, 0, 1, '{');
		}
		else {
			$logInStrings .= '{}';
		}
		%logFilenames = %logStat = %{JSON::from_json($logInStrings)};
	}

	if (defined($_[0]) and ref($_[0]) eq 'HASH') {
		%logFilenames = %{$_[0]};
	}

	my $lf = tie(my %logFiles, 'Tie::IxHash');
	my $logsFound = 0;
	foreach(sort {$b <=> $a} keys %logFilenames) {
		if ((($_[1] <= $_) && ($_[2] >= $_))) {
			$logsFound = 1;
			if (exists $logStat{$_}) {
				$logFiles{$_} = $logStat{$_};
			}
			else {
				$logFiles{$_} = {
					'status' => $logFilenames{$_},
					'datetime' => strftime("%m/%d/%Y %H:%M:%S", localtime($_))
				};
			}
		}
		elsif ($logsFound) {
			last;
		}
	}

	return $lf;
}

#*****************************************************************************************************
# Subroutine			: stopDashboardService
# Objective				: Stop a dashboard service for the given username
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub stopDashboardService {
	my ($mcUser, $scpath) = @_;

	# if any of the value is not defined, return
	return 0 unless (defined($mcUser) && defined($scpath));

	# construct service file path to this user
	my $servicefile = getCatfile($scpath, $AppConfig::serviceLocationFile);
	# if service path file not present, go back
	return 0 unless (-f $servicefile and !-z $servicefile);

	my $svfc = getFileContents($servicefile);
	Chomp(\$svfc);

	my $dashboardPID = getCatfile($svfc, $AppConfig::userProfilePath, $mcUser, $AppConfig::dashboardpid);
	return 0 unless (-f $dashboardPID and !-z $dashboardPID);

	fileWrite($dashboardPID, '-1');

	while(isFileLocked($dashboardPID)) {
		sleep(1);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: skipChildIfParentDirExists
# Objective				: Skip child items if parent directory present & return
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub skipChildIfParentDirExists{
	my %list = %{$_[0]};
	my $display = $_[1]? 1 : 0;
	foreach my $item (sort(keys %list)) {
		foreach my $newItem (sort(keys %list)){
			if ($list{$newItem}{'type'} eq 'f' ){
				next;
			}
			my $tempNewItem = quotemeta($newItem);
			if ($item ne $newItem && $item =~ m/^$tempNewItem/){
				display(["Skipped [$item]. ", "Reason",'parent_directory_present']) if($display);
				delete $list{$item};
				$skippedItem = 1;
				last;
			}
		}
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine			: sendFailiourNotice
# Objective				: send the failure
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub sendFailureNotice{
	if (loadAppPath() and loadServicePath() and loadUsername($_[0]) and loadNotifications() and lockCriticalUpdate("notification")) {
		my $currentTime = time();
		setNotification($_[1], $currentTime.'_'.AppConfig::JOBEXITCODE->{'FAILURE'}."_".$_[2]);
		saveNotifications();
		unlockCriticalUpdate("notification");
	}
}

#*****************************************************************************************************
# Subroutine			: sleepForMilliSec
# Objective				: Sleep for given milliseconds; Input should be integer
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub sleepForMilliSec {
	my $sleepTime = $_[0];
	$sleepTime = 1 if ($sleepTime < 1);
	$sleepTime = ($sleepTime/1000);
	select(undef, undef, undef, $sleepTime);
}

#*****************************************************************************************************
# Subroutine      : startAuxCDPServices
# Objective       : This method helps to start all CDP services
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub startAuxCDPServices {
	startDBWriter();
	startCDPClientServer();
}

#*****************************************************************************************************
# Subroutine      : startCDPClientServer
# Objective       : This method helps to start CDP services[client & server]
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub startCDPClientServer {
	my $cdphalt = getCDPHaltFile();
	my $trial	= 2;

	return 0 if(-f $cdphalt);

	while($trial) {
		startCDPServer();
		# let the server start first, sleep for 2 seconds
		sleep(2);
		startCDPClient();

		return 1 if(isCDPClientServerRunning());

		if($trial <= 1) {
			traceLog('Unable to start CDP client server');
			fileWrite($cdphalt, '1');
		}

		$trial--;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine      : startCDPClient
# Objective       : This method helps to start CDP client service
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub startCDPClient {
	return 0 if(!canKernelSupportInotify());

	my $cdpclientlock	= getCDPLockFile('client');
	return 1 if(isFileLocked($cdpclientlock));

	system("$AppConfig::perlBin \"" . getScript('cdp_client') . "\" 1>/dev/null 2>/dev/null &");

	return 1;
}

#*****************************************************************************************************
# Subroutine      : startCDPServer
# Objective       : This method helps to start CDP server service
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub startCDPServer {
	return 0 if(!canKernelSupportInotify());

	my $cdpserverlock	= getCDPLockFile('server');
	return 1 if(isFileLocked($cdpserverlock));

	system("$AppConfig::perlBin \"" . getScript('cdp_server') . "\" 1>/dev/null 2>/dev/null &");

	return 1;
}

#*****************************************************************************************************
# Subroutine      : startCDPWatcher
# Objective       : This method helps to start CDP watcher service
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub startCDPWatcher {
	my $cdpclientlock	= getCDPLockFile('watcher');
	return 1 if(isFileLocked($cdpclientlock));

	system("$AppConfig::perlBin \"" . getScript('utility') . "\" CDP 1>/dev/null 2>/dev/null &");
	# Sleep is required for service to acquire the lock
	sleep(1);

	createFailoverScanRequest() if($_[0]);

	return 1;
}

#*****************************************************************************************************
# Subroutine      : startDBWriter
# Objective       : This method helps to start DB writer service
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub startDBWriter {
	my $dbwritelock	= getCDPLockFile('dbwritelock');
	return 1 if(isFileLocked($dbwritelock));

	system("$AppConfig::perlBin \"" . getScript('utility') . "\" DBWRITER 1>/dev/null 2>/dev/null &");

	# Sleep is required for service to acquire the lock
	sleep(1);

	return 1;
}

#*****************************************************************************************************
# Subroutine      : stopAuxCDPServices
# Objective       : This method helps to terminate CDP services
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub stopAuxCDPServices {
	stopCDPClient($_[0]);
	stopCDPServer($_[0]);
	stopDBService($_[0]);
}

#*****************************************************************************************************
# Subroutine      : stopAllCDPServices
# Objective       : This method helps to terminate all CDP services
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub stopAllCDPServices {
	stopAuxCDPServices($_[0]);
	stopCDPWatcher($_[0]);
}

#*****************************************************************************************************
# Subroutine      : stopCDPClient
# Objective       : This method helps to terminate CDP client if its is running
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub stopCDPClient {
	my $kabin = `which killall 2>/dev/null`;
	Chomp(\$kabin);

	if($kabin) {
		my $cdpclientname = $AppConfig::appType . ':CDP-client';
		`killall -9 '$cdpclientname' 2>/dev/null`;
	} else {
		my $killcmd = "ps -A | grep '$AppConfig::appType' | grep -E 'CDP-client' | awk '{print \$1}' | xargs kill -9 \$1";
		system("$killcmd 2>/dev/null");
	}

	my $cdpclientlock	= getCDPLockFile('client', $_[0]);
	return 1 if(!-f $cdpclientlock);

	if(isFileLocked($cdpclientlock)) {
		my $clientkillcmd = "kill -9 " . getFileContents($cdpclientlock) . " 1>/dev/null 2>/dev/null";
		system($clientkillcmd);
	}

	unlink($cdpclientlock) if(-f $cdpclientlock);

	return 1;
}

#*****************************************************************************************************
# Subroutine      : stopCDPServer
# Objective       : This method helps to terminate CDP service server if its running
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub stopCDPServer {
	my $kabin = `which killall 2>/dev/null`;
	Chomp(\$kabin);

	if($kabin) {
		my $cdpservname = $AppConfig::appType . ':CDP-server';
		`killall -9 '$cdpservname' 2>/dev/null`;
	} else {
		my $killcmd = "ps -A | grep '$AppConfig::appType' | grep -E 'CDP-server' | awk '{print \$1}' | xargs kill -9 \$1";
		system("$killcmd 2>/dev/null");
	}

	my $cdpserverlock	= getCDPLockFile('server', $_[0]);
	return 1 if(!-f $cdpserverlock);

	if(isFileLocked($cdpserverlock)) {
		my $clientkillcmd = "kill -9 " . getFileContents($cdpserverlock) . " 1>/dev/null 2>/dev/null";
		system($clientkillcmd);
	}

	unlink($cdpserverlock) if(-f $cdpserverlock);

	return 1;
}

#*****************************************************************************************************
# Subroutine      : stopCDPWatcher
# Objective       : This method helps to terminate CDP watcher if its is running
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub stopCDPWatcher {
	my $cdpwatcherlock	= getCDPLockFile('watcher', $_[0]);
	return 1 if(!-f $cdpwatcherlock);

	if(isFileLocked($cdpwatcherlock)) {
		my $clientkillcmd = "kill -9 " . getFileContents($cdpwatcherlock) . " 1>/dev/null 2>/dev/null";
		system($clientkillcmd);
	}

	unlink($cdpwatcherlock) if(-f $cdpwatcherlock);

	return 1;
}

#*****************************************************************************************************
# Subroutine      : stopDBService
# Objective       : This method helps to terminate db writer service
# Added By        : Sabin Cheruvattil
#*****************************************************************************************************
sub stopDBService {
	my $dbwriterlock	= getCDPLockFile('dbwritelock', $_[0]);
	return 1 if(!-f $dbwriterlock);

	if(isFileLocked($dbwriterlock)) {
		my $killcmd = "kill -9 " . getFileContents($dbwriterlock) . " 1>/dev/null 2>/dev/null";
		system($killcmd);
	}

	unlink($dbwriterlock) if(-f $dbwriterlock);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: saveAlertStatus
# Objective				: Save alert status code
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveAlertStatus {
	fileWrite(getCatfile(getUserProfilePath(), $AppConfig::alertStatusFile), ($_[0] || ''));
}

#------------------------------------------------- T -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: trimDeviceInfo
# Objective				: This function will remove over-length characters and replace with the [...] at the end of the string to restrict data overflow.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub trimDeviceInfo{
	my ($data,$dataLength) = @_;
	my $displayLen = $dataLength - 3;
	if (length($data) > $displayLen){
		$data = substr($data,0,($displayLen-4)).'[..]';
	}
	return $data;
}

#*****************************************************************************************************
# Subroutine			: trim
# Objective				: This function will remove white spaces from both side of a string
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub trim {
	$_[0] =~ s/^\s+|\s+$//g; # Replace original string itself
	return 1;
}

#*********************************************************************************************************
# Subroutine			: trimData
# Objective             : This function will display the available list of devices with given account on the screen.
# Added By              : Abhishek Verma
#*********************************************************************************************************/
sub trimData {
	my ($data, $dataLength) = @_;
	my $displayLen = $dataLength - 3;
	if (length($data) > $displayLen) {
		$data = substr($data, 0, ($displayLen - 4)) . '[..]';
	}

	return $data;
}

#*****************************************************************************************************
# Subroutine      : traceLog
# Objective       : Trace log method
# Added By        : Sabin Cheruvattil
# Modified By     : Yogesh Kumar, Vijay Vinoth, Senthil Pandian
#*****************************************************************************************************
sub traceLog {
	return 0 unless(-d getServicePath());
	my $message = ($_[0])? $_[0] : '';
	my $msg = "";
	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}

	for my $i (0 .. $#{$message}) {
		if (exists $LS{$message->[$i]}) {
			$msg .= $LS{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}
	my $trace = $msg;

	my ($package, $filename, $line) = (defined $_[1] && defined $_[2])? ("", $_[1], $_[2]) : caller;
	my $traceLog = getTraceLogPath();
	my $traceDir = dirname($traceLog);

	if (!-d $traceDir) {
		#my $mkRes = `mkdir -p '$traceDir' 2>&1`;
		#chomp($mkRes);
		#if ($mkRes ne '' and $mkRes !~ /Permission denied/) {
		my $mkRes = createDir($traceDir,1);
		unless($mkRes){
			changeMode(getServicePath());
		}
	}

	if (-e $traceLog and -s $traceLog >= $AppConfig::maxLogSize) {
		my $rnlock = getCatfile($traceDir, 'tracern.lock');
		if (!isFileLocked($rnlock)) {
			fileLock($rnlock);
			my $tempTrace = qq($traceLog) . qq(_) . localtime();
			my $mvTraceLogcmd = "mv '$traceLog' '$tempTrace'";
			if (!-f $tempTrace) {
				`$mvTraceLogcmd`;
			}

			unlink($rnlock) if(-f $rnlock);
		}
	}

	if (!-e $traceLog) {
		writeToTrace($traceLog, qq($AppConfig::appType ) . ucfirst($LS{'username'}) . qq(: ) .
			(getUsername() or ucfirst($LS{'no_logged_in_user'})) . qq( \n), 1);
		writeToTrace($traceLog, "Linux user     : $AppConfig::mcUser\n", 1);
		loadMachineHardwareName();
		my $osd = getOSBuild();
		writeToTrace($traceLog, "OS details     : $osd->{'os'}, $osd->{'build'}, $machineHardwareName\n\n", 1);
		chmod $AppConfig::filePermission, $traceLog;
	}

	my @files        = glob($traceLog . qq(_*));
	my $remFileCount = scalar(@files) - 5;
	while($remFileCount > 0) {
		unlink shift(@files);
		$remFileCount--;
	}

	chomp($trace);
	my $logContent 		= qq([) . basename($filename) . qq(][Line: $line] $trace\n);
	if (!defined($_[3]) or ($_[3] and -f getCatfile(getAppPath(), 'debug.enable'))) {
		writeToTrace($traceLog, $logContent);
	}
}

#******************************************************************************
# Subroutine Name         : terminateStatusRetrievalScript
# Objective               : terminates the Status Retrieval script in case it is running
# Added By                :
# Modified By             : Senthil Pandian
#******************************************************************************
sub terminateStatusRetrievalScript
{
	my $psOption		 = getPSoption();
	my $statusScriptName = $AppConfig::idriveScripts{'status_retrieval_script'};
	my $statusScriptCmd  = updateLocaleCmd("ps $psOption | grep $statusScriptName | grep -v grep");

	my $statusScriptRunning = `$statusScriptCmd`;
	if ($statusScriptRunning ne "") {
		my @processValues = split /[\s\t]+/, $statusScriptRunning;
		my $pid = $processValues[3];
		   $pid = (split /[\s\t]+/, $statusScriptRunning)[3];
#		`kill -s SIGTERM $pid`;
	}
#	unlink($_[0]);
}

#*****************************************************************************************************
# Subroutine	: trackDeviceTrust
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks device trust
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub trackDeviceTrust {
	my $cantrusted = 0;
	my $checkres = {};
	my $restorepath = getJobsPath("restore");
	my $reqpid = getCatfile($restorepath, $AppConfig::restorepidlock);

	exit(1) if(isFileLocked($reqpid));

	fileLock($reqpid);

	my $res = makeRequest(20);
	eval {
		$checkres = JSON::from_json($res);
		1;
	}
	or do {
		$checkres = {};
	};

	if(exists($checkres->{"STATUS"}) and $checkres->{"STATUS"} and ($checkres->{"STATUS"} eq "SUCCESS")) {
		$cantrusted = 1;
	}

	unlink($reqpid);

	return $cantrusted;
}

#------------------------------------------------- U -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: uniqueData
# Objective				: This will return unique data from given array.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub uniqueData{
	my %uniqueData = map{ $_ => 1 } @_;
	return sort {$a cmp $b} keys %uniqueData;
}

#*****************************************************************************************************
# Subroutine			: unzip
# Objective				: Read zip files and unzip the package
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub unzip {
	my $filename = shift;
	my $exDir    = shift;

	unless (defined($filename)) {
		display('ziped_filename_cannot_be_empty');
		return 0;
	}

	unless (defined($exDir)) {
		$exDir = getCatfile($servicePath, $AppConfig::downloadsPath);
		createDir($exDir) or (display(["$exDir ", 'does_not_exists']) and return 0);
	}

	#print "Unziping the package... \n";
	$exDir    = getECatfile($exDir);
	$filename = getECatfile($filename);
	my $unzipCmd = updateLocaleCmd("unzip -o $filename -d $exDir");
	my $output = `$unzipCmd`;

	if ($? > 0) {
			traceLog($?);
			return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateUserLoginStatus
# Objective				: This is to create cache folder for storing the user information.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub updateUserLoginStatus {
	# get user.txt full file name
	my $filename = getUserFile();
    my $loggedInUser = getUsername(); #Added for Yuvaraj_2.32_09_6: Senthil

	# create cache directory if does not exist
	createDir(getCachedDir());

	my %loginData= ();

	###########################################
	# load user.txt content
	if (-e $filename){
		my $fc = "";
		$fc = getFileContents($filename);
		Chomp(\$fc);

		if ($fc =~ m/^\{/) {
			%loginData	= %{JSON::from_json($fc)};
		}
	}

	if (defined($_[2]) and $_[2] and !$_[1]) {
		unless (exists $loginData{$AppConfig::mcUser} and $loginData{$AppConfig::mcUser}{'userid'} eq $_[0]) {
			$loginData{$AppConfig::mcUser} {'userid'} = $_[0];
			$loginData{$AppConfig::mcUser} {'isLoggedin'} = $_[1];
			fileWrite($filename, JSON::to_json(\%loginData));
			chmod $AppConfig::filePermission, $filename;
		}
	}
	else {
		$loginData{$AppConfig::mcUser} {'userid'} = $_[0];
		$loginData{$AppConfig::mcUser} {'isLoggedin'} = $_[1];
		fileWrite($filename, JSON::to_json(\%loginData));
		chmod $AppConfig::filePermission, $filename;

		updateAccountStatus($_[0], 'Y') if($_[1]);

		# Updating the logged in user status to cron
		my $status = ($_[1] or $AppConfig::appType eq 'IBackup')?'ACTIVE':'INACTIVE';

		lockCriticalUpdate("cron");
		loadCrontab();
		createCrontab('otherInfo', {'settings' => {'status' => $status, 'lastActivityTime' => time()}});
		setCrontab('otherInfo',  'settings', {'status' => $status} , ' ');
		saveCrontab();
		unlockCriticalUpdate("cron");
	}

	display(["\n", "\"$_[0]\"", 'is_logged_in_successfully', '.'], 1) if ($_[1] and ($loggedInUser ne $_[0] or $_[2]));
	return 1;
}

#*****************************************************************************************************
# Subroutine	: updateAccountStatus
# In Param		: String | username, String | Stat
# Out Param		: UNDEF
# Objective		: Updates account status
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub updateAccountStatus {
	return 0 if(!$_[0] || !$_[1]);

	my $uname	= $_[0];
	my $stat	= $_[1];

	my $filename = getUserFile();
	return 0 unless(-f $filename);

	my %loginData = ();
	my $fc	= "";
	$fc		= getFileContents($filename);
	Chomp(\$fc);

	return 0 unless($fc =~ m/^\{/);

	%loginData = %{JSON::from_json($fc)};
	return 0 if(!exists($loginData{$AppConfig::mcUser}) || $loginData{$AppConfig::mcUser}{'userid'} ne $uname);

	$loginData{$AppConfig::mcUser}{'accstat'} = $stat;
	fileWrite($filename, JSON::to_json(\%loginData));
}

#*****************************************************************************************************
# Subroutine			: updateDirSizes
# Objective				: Update directory sizes for sending back to dashboard
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub updateDirSizes {
	my $backupsetsizes = $_[0];
	my $notifsizes = $_[1];
	my $processeditemcount = $_[2];

	my $curtime = mktime(localtime);
	foreach my $key (keys %{$notifsizes}) {
		if (defined($notifsizes->{$key}) && defined($backupsetsizes->{$key}) && reftype(\$notifsizes->{$key}{'size'}) eq 'SCALAR' && defined($backupsetsizes->{$key}{'size'}) &&
		$notifsizes->{$key}{'size'} == -1 && $backupsetsizes->{$key}{'size'} != -1) {
			$notifsizes->{$key} = $backupsetsizes->{$key};
			$processeditemcount++;
		}
	}

	return $processeditemcount;
}

#*****************************************************************************************************
# Subroutine			: updateUserDetail
# Objective				: This subroutine will update newly configured user details to MySQL table in our servers.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub updateUserDetail {
	my $device_name = $AppConfig::hostname;
	chomp($device_name);

	my $os = $AppConfig::appType."ForLinux";
	my $encodedOS    = $os;
	my $currentVersion = $AppConfig::version;
	chomp($currentVersion);

	my $uniqueID		= getMachineUID() or retreat('unable_to_find_mac_address');
	my $encodedUname	= $_[0];
	my $encodedPwod		= $_[1];
	my $enabled			= $_[2];

	my $res = makeRequest(7, [
		$device_name,
		$uniqueID,
		$enabled,
		$encodedOS,
		$currentVersion
	]);

	if ($res){
		if ($res->{DATA} =~ /Error:/){
			traceLog("Failed to update user detail: ".$res->{DATA}."\n") if ($enabled ==1);
			return 0;
		}
		return 1 if ($res->{DATA} =~ /success/i);
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: urlEncode
# Objective				: Helps to encode url
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub urlEncode {
	my $rv = shift;
	$rv =~ s/([^a-z\d\Q.-_~ \E])/sprintf("%%%2.2X", ord($1))/geix;
	$rv =~ tr/ /+/;
	return $rv;
}

#*****************************************************************************************************
# Subroutine			: urlDecode
# Objective				: Helps to decode url
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub urlDecode {
	my $rv = shift;
	$rv =~ tr/+/ /;
	$rv =~ s/\%([a-f\d]{2})/ pack 'C', hex $1 /geix;
	return $rv;
}

#*****************************************************************************************************
# Subroutine			: uploadLog
# Objective				: Upload logs for backup, restore & archive
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil
#****************************************************************************************************/
sub uploadLog {
	my $jobPath = (fileparse($_[0]))[1];
	my $isxml	= $_[1];
	my $logpath	= $isxml? '' : 'log/';
	$jobPath = getCatfile($jobPath, '..', 'tmp');
	if (createDir($jobPath)) {
		my $tempFile = getCatfile($jobPath, 'file.txt');
		my $outFile = getCatfile($jobPath, 'output.txt');
		my $errFile = getCatfile($jobPath, 'errfile.txt');
		if (fileWrite($tempFile, $_[0])) {
			my $utf8File = getCatfile($jobPath, $AppConfig::utf8File);
			if (createUTF8File(['LOGBACKUP', $utf8File], $tempFile, ($jobPath."/"), $outFile, $errFile, $logpath)) {
				makeRequest(15, [$utf8File], 1);
				runEVS('', undef, undef, undef);
				removeItems($jobPath);
				return 1;
			}
		}
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: uploadMigratedLog
# Objective				: Upload migrated logs for backup, express backup, restore & archive
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub uploadMigratedLog {
	my $l = eval {
		require Idrivelib;
		Idrivelib->import();
		1;
	};

	my $userProfilePath = "$servicePath/$AppConfig::userProfilePath/";
	my $tempFile 		= getCatfile($userProfilePath, $AppConfig::migratedLogFileList);

	if (-e $tempFile and !-z $tempFile){
		my $tempjobPath = getCatfile($userProfilePath,'tmp');
		if (createDir($tempjobPath)) {
			my $outFile = getCatfile($tempjobPath, 'output.txt');
			my $errFile = getCatfile($tempjobPath, 'errfile.txt');
			my $utf8File = getCatfile($tempjobPath, $AppConfig::utf8File);
			if (createUTF8File(['LOGBACKUP', $utf8File], $tempFile, ($tempjobPath."/"), $outFile, $errFile)) {
				Idrivelib::update_log_file($utf8File);
				runEVS('', undef, undef, undef);
				removeItems([$tempjobPath,$tempFile]);
				return 1;
			}
		}
	}
	return 0;
}

#*******************************************************************************************************
# Subroutine Name         :	updateServerAddr
# Objective               :	handling wrong server address error msg
# Added By                : Senthil Pandian
#********************************************************************************************************
sub updateServerAddr {
	my $idevsErrorFile  = $AppConfig::jobRunningDir.'/'.$AppConfig::evsErrorFile;
	if (-e $idevsErrorFile and -s $idevsErrorFile > 0) {
		my $errorPatternServerAddr = "unauthorized user|user information not found";
		open EVSERROR, "<", $idevsErrorFile or traceLog("Failed to open $idevsErrorFile. Reason $!");
		my $errorContent = <EVSERROR>;
		close EVSERROR;

		if ($errorContent =~ m/$errorPatternServerAddr/){
			$serverAddress = getServerAddress();
			if ($serverAddress == ''){
				updateAccountStatus(getUsername(), 'UA');
				#exit_cleanup($AppConfig::errStr);
				return 0;
			}
			return 1;
		}
	}
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	updateRetryCount
# Objective               :	updates retry count based on recent backup files.
# Added By                : Avinash
# Modified By             : Dhritikana, Yogesh Kumar, Sabin Cheruvattil
#********************************************************************************************************/
sub updateRetryCount {
	my $curFailedCount = 0;
	my $currentTime = time();
	my $statusFilePath  = $AppConfig::jobRunningDir."/".$AppConfig::statusFile;

	for (my $i=1; $i<= $AppConfig::totalEngineBackup; $i++) {
		if (-e $statusFilePath."_".$i and -s _ > 0){
			$curFailedCount = $curFailedCount+getParameterValueFromStatusFile($i,'ERROR_COUNT_FILES');
			undef @AppConfig::linesStatusFile;
		}
	}

	if ($curFailedCount < $prevFailedCount) {
		$AppConfig::retryCount = 0;
	}
	else {
		if ($currentTime-$AppConfig::prevTime < 120) {
			sleep 300;
		}
		$AppConfig::retryCount++;
	}

	#assign the latest backedup and synced value to prev.
	$prevFailedCount = $curFailedCount;
	$AppConfig::prevTime = $currentTime;
}

#*******************************************************************************************************
# Subroutine Name         :	updateCronForOldAndNewUsers
# Objective               :	Update cron details accordingly for old and new users at the time of account switching.
# Added By                : Anil kumar
# Modified By             : Yogesh Kumar, Senthil Pandian
#********************************************************************************************************/
sub updateCronForOldAndNewUsers {
	# update previous user status to logged out
	setUsername($_[0]);
	loadUserConfiguration();
	my $errorMsg = 'operation_cancelled_due_to_account_switch';
	if (isLoggedin()) {
		lockCriticalUpdate("cron");
		loadCrontab();
		#createCrontab('otherInfo', {'settings' => {'status' => 'INACTIVE'}});
		createCrontab('otherInfo', {'settings' => {'status' => 'INACTIVE', 'lastActivityTime' => time()}});
		setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
		saveCrontab();
		unlockCriticalUpdate("cron");

		my $cmd = sprintf("%s %s 1 0 %s", $AppConfig::perlBin, getScript('logout', 1), $errorMsg);
		$cmd = updateLocaleCmd($cmd);
		`$cmd`;
		display(["\"$_[0]\"", ' ', 'is_logged_out_successfully']);
		traceLog('logout');
	}
	else {
		my $cmd = sprintf("%s %s 'allOp' - 0 'allType' %s %s", $AppConfig::perlBin, getScript('job_termination', 1), $AppConfig::mcUser, $errorMsg);
		$cmd = updateLocaleCmd($cmd);
		my $res = `$cmd 1>/dev/null 2>/dev/null`;
	}

	unloadUserConfigurations(); #Added for Harish_2.22_05_3
	#set back the user name to new user
	setUsername($_[1]);
	loadUserConfiguration();

	return 0;
}

#*******************************************************************************************************
# Subroutine Name         :	updateCronTabToDefaultVal
# Objective               :	updates default values to crontab after immediate backup job has been completed
# Added By                : Anil kumar
# Modified By			: Sabin Cheruvattil
#********************************************************************************************************/
sub updateCronTabToDefaultVal {
	my $jobType = $_[0];
	my $jobName = "";
	if ($jobType eq "backup") {
		$jobName = "default_backupset";
	} else {
		$jobName = "local_backupset";
	}
	lockCriticalUpdate("cron");
	loadCrontab();
	setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'daily'}});
	setCrontab($jobType, $jobName, {'settings' => {'status' => 'disabled'}});
	setCrontab($jobType, $jobName, 'h', sprintf("%02d", 00));
	setCrontab($jobType, $jobName, 'm', sprintf("%02d", 00));
	setCrontab('cancel', $jobName, {'settings' => {'frequency' => 'daily'}});
	setCrontab('cancel', $jobName, {'settings' => {'status' => 'disabled'}});
	setCrontab('cancel', $jobName, 'h', sprintf("%02d", 00));
	setCrontab('cancel', $jobName, 'm', sprintf("%02d", 00));
	saveCrontab();
	unlockCriticalUpdate("cron");
}

#*****************************************************************************************************
# Subroutine			: updateExcludeFileset
# Objective				:
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub updateExcludeFileset {
	my %ec = ();
	if (-f "$_[0].info") {
		my $excludeContent = getFileContents("$_[0].info");
		%ec = split("\n", $excludeContent);
	}

	if (open(my $filesetContentInfo, '>', ("$_[0].info")) and open(my $filesetContent, '<', $_[0])) {
		while(my $filename = <$filesetContent>) {
			chomp($filename);
			trim($filename);
			if (exists $ec{$filename}) {
				print $filesetContentInfo "$filename\n";
				print $filesetContentInfo "$ec{$filename}\n";
			}
			elsif ($filename ne '') {
				print $filesetContentInfo "$filename\n";
				print $filesetContentInfo "enabled\n";
			}
		}
		close($filesetContentInfo);
		close($filesetContent);

		if(loadNotifications() and lockCriticalUpdate("notification")) {
			setNotification('get_settings') and saveNotifications();
			unlockCriticalUpdate("notification");
		}

		removeBKPSetSizeCache('backup');
		removeBKPSetSizeCache('localbackup');
	}
}

#*************************************************************************************************
# Subroutine		: updateEVSBinary
# Objective			: download the latest EVS binary and update
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub updateEVSBinary {
	display(["\n", 'downloading_updated_evs_binary', '...']);
	if(downloadEVSBinary() and hasEVSBinary()) {
		display('evs_binary_downloaded_successfully');
	}
	else {
		display('unable_to_download_evs_binary');
	}
}

#*************************************************************************************************
# Subroutine		: updatePerlBinary
# Objective			: download the latest perl binary and update
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub updatePerlBinary {
	display(["\n", 'downloading_updated_static_perl_binary', '...']);
	if(downloadStaticPerlBinary() and hasStaticPerlBinary()) {
		display(['static_perl_binary_downloaded_successfully',"\n"]);
	}
	else {
		display('unable_to_download_static_perl_binary');
	}
}

#*************************************************************************************************
# Subroutine		: updatePythonBinary
# Objective			: download the latest python binary and install
# Added By			: Yogesh Kumar
#*************************************************************************************************/
sub updatePythonBinary {
	display(['downloading_python_binary', '... ']);
	unless (downloadPythonBinary()) {
        return 0;
		# retreat('unable_to_download_python_binary');
	}
	else {
        return 1;
		# display('python_binary_downloaded_successfully');
	}
}

#*****************************************************************************************************
# Subroutine			: updateJobsFileset
# Objective				: update *.json file, which contains more details of a file(ex: file/folder/undefined)
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub updateJobsFileset {
	return 0 unless (-f $_[0]);
	
	my $bsf = $_[0];
	my $canwrite = 1;

	unless (-f "$bsf.json") {
		unless (-w dirname($bsf)) {
			traceLog("Cannot open file $bsf.json $!");
			$canwrite = 0;
		} else {
			fileWrite("$bsf.json", '');
		}
	} else {
		$canwrite = 0 unless(-w "$bsf.json");
	}

	unless ($canwrite) {
		traceLog("Cannot lock file $bsf.json $!");
		return 0;
	}

	my $bsc = ($_[1] =~ /backup/)? getDecBackupsetContents($bsf, 'array') : getFileContents($bsf, 'array');

	my @itemarr = ();
	my %fci = ();
	if (defined($_[1]) and ($_[1] eq 'backup' || $_[1] eq 'localbackup')) {
		foreach my $filename (@{$bsc}) {
			chomp($filename);
			push @itemarr, $filename;

			if (-f $filename) {
				$fci{$filename} = {'size' => -s $filename, 'ts' => '', 'filecount' => '1', 'type' => 'f'};
			}
			elsif (-d $filename) {
				$filename .= (substr($filename, -1) ne '/')? '/' : '';
				$fci{$filename} = {'size' => -1, 'ts' => '', 'filecount' => 'NA', 'type' => 'd'};
			}
			else {
				next;
			}
		}
	}
	else {
		foreach my $filename (@{$bsc}) {
			chomp($filename);
			push @itemarr, $filename;
			$fci{$filename} = {'type' => (substr($filename, -1) ne '/')? 'f' : 'd'};
		}
	}

	fileWrite("$bsf.json", JSON::to_json(\%fci));

	my $content = '';
	$content = join("\n", @itemarr) if (scalar(@itemarr));
	saveEncryptedBackupset($bsf, $content);

	if(loadNotifications() and lockCriticalUpdate("notification")) {
		setNotification("get_$_[1]set_content") and saveNotifications();
		unlockCriticalUpdate("notification");
	}
}

#*****************************************************************************************************
# Subroutine			: unloadUserConfigurations
# Objective				: This subroutine empties user configurations
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub unloadUserConfigurations {
	%userConfiguration = ();
	%modifiedUserConfig = ();
}

#*****************************************************************************************************
# Subroutine			: updateLocaleCmd
# Objective				: This subroutine to update locale configuration.
#						  Mainly used for display from diffent languages to English
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub updateLocaleCmd {
	my $cmd = $_[0];
	$cmd = "LC_ALL=C ".$cmd		if($isEngEnabled == 0);
	return $cmd;
}

#*****************************************************************************************************
# Subroutine	: updateLastBackupStatus
# In Param		: backup status | file name
# Out Param		: 
# Objective		: Helps to update backup status
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub updateLastBackupStatus {
	my $jobType	 = $_[0];
	my $status   = $_[1];
	my $filename = $_[2];
	my $bkpStatusFile = getCatfile(getUserProfilePath(), $AppConfig::userInfoPath, $AppConfig::lastBkpStatusFile);
	my %bkpStatus = ('last_backup_status'=>{'jobType' => lc($jobType), 'status' => $status, 'filename' => $filename});
	fileWrite($bkpStatusFile, JSON::to_json(\%bkpStatus));
}

#------------------------------------------------- V -------------------------------------------------#
#********************************************************************************
# Subroutine		: validateBackupRestoreSetFile
# Objective			: Validating Backupset/RestoreSet file
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#********************************************************************************
sub validateBackupRestoreSetFile {
	retreat('filename_is_required') unless(defined($_[0]));

	my $errStr = '';
	my $jb = lc($_[0]);
	my $filePath = getJobsPath($jb, 'file');
	my $status = AppConfig::SUCCESS;

	if (!-e $filePath or !-s _) {
		$errStr = "\n" . getStringConstant('your_' . $jb . 'set_is_empty');
	}
	elsif (-s _ > 0 && -s _ <= 50) {
		my $outfh;
		if (!open($outfh, "< $filePath")) {
			$errStr = getStringConstant('failed_to_open_file') . ":$filePath, Reason:$!";
		}
		else{
			my $buffer = <$outfh>;
			close($outfh);

			Chomp(\$buffer);
			if ($buffer eq '') {
				$errStr = "\n" . getStringConstant('your_' . $jb . 'set_is_empty');
			}
		}
	}

	if($jb eq 'cdp' && $errStr eq '') {
		my $bkpset	= getDecBackupsetContents($filePath, 'array');
		my $hasitem	= 0;

		foreach my $bkitem (@{$bkpset}) {
			if(-e $bkitem) {
				$hasitem = 1;
				last;
			}
		}

		$errStr = "\n" . getStringConstant('your_' . $jb . 'set_is_empty') unless($hasitem);
	}

	$status = AppConfig::FAILURE if ($errStr ne '');
	return ($status, $errStr);
}

#*****************************************************************************************************
# Subroutine			: validateChoiceOptions
# Objective				: This subroutine validates choice options y/n or p/e
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub validateChoiceOptions {
	my $choice = $_[0];
	my $yes    = $_[1]; #y or p
	my $no     = $_[2]; #n or e
	if (lc($choice) eq $yes || lc($choice) eq $no) {
		return 1;
	}
	return 0;
}

#*********************************************************************************************************
# Subroutine			: validateDir
# Objective				: This function will check if the diretory exists, its writable. Returns 0 for true and 1 for false.
# Added By				: Abhishek Verma.
# Modified By			: Sabin Cheruvattil
#*********************************************************************************************************/
sub validateDir {
	return (-d $_[0] && -w _)? 1 : 0;
}
#*****************************************************************************************************
# Subroutine			: validateMenuChoice
# Objective				: This subroutine validates the log menu choice
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateMenuChoice {
	my ($choice, $lowerRange, $maxRange) = (shift, shift, shift);
	# validate for digits
	return 0 if ($choice !~ m/^[0-9]{1,3}$/);
	return 1 if ($choice >= $lowerRange && $maxRange >= $choice);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateUserConfigurations
# Objective				: Validate user provided values
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Vijay Vinoth
#****************************************************************************************************/
sub validateUserConfigurations {
	my @filedsToVerify = ();
	my $verifyAll = 1;
	if (defined($_[0])){
		@filedsToVerify = @{$_[0]};
		$verifyAll = 0;
	}
	for my $key (keys %AppConfig::userConfigurationSchema) {
		if ($verifyAll == 0){
			unless(grep { $_ eq $key} @filedsToVerify){
				next;
			}
		}

		unless (exists $userConfiguration{$key}) {
			# @TODO: Check and remove the following trace
			traceLog($key." is missing.", undef, undef, 1);
			my $errCode = $AppConfig::userConfigurationSchema{$key}{'required'};
			$errCode = 102 if (!isLoggedin() and $errCode == 100);
			$errCode = 103 if (!isLoggedin() and $errCode == 101);
			return $errCode;
		}
		if ($AppConfig::appType eq 'IDrive' and $AppConfig::userConfigurationSchema{$key}{'required'} and
			($userConfiguration{$key}{'VALUE'} eq '')) {
			# @TODO: Check and remove the following trace
			traceLog($key." value is missing.", undef, undef, 1);
			my $errCode = $AppConfig::userConfigurationSchema{$key}{'required'};
			unless (isLoggedin()) {
				return (int($errCode) + 2);
			}
			return $errCode;
		}
		if (($AppConfig::userConfigurationSchema{$key}{'type'} eq 'dir') and
			($userConfiguration{$key}{'VALUE'} ne '') and (!-d $userConfiguration{$key}{'VALUE'})) {
			# @TODO: Check and remove the following trace
			traceLog($key." is misssing.", undef, undef, 1);
			return 101;
		}
		if (($AppConfig::userConfigurationSchema{$key}{'type'} eq 'regex') and
			exists ($AppConfig::userConfigurationSchema{$key}{'regex'}) and ($userConfiguration{$key}{'VALUE'} ne '')) {
			if ($userConfiguration{$key}{'VALUE'} !~ m/$AppConfig::userConfigurationSchema{$key}{'regex'}/) {
				# @TODO: Check and remove the following trace
				traceLog("Invalid $key value: ".$userConfiguration{$key}{'VALUE'}, undef, undef, 1);
				$userConfiguration{$key}{'VALUE'} = $AppConfig::userConfigurationSchema{$key}{'default'};
				#return $AppConfig::userConfigurationSchema{$key}{'required'};
			}
		}

		if ((not defined($userConfiguration{$key}{'VALUE'})) or
				(($AppConfig::userConfigurationSchema{$key}{'default'} ne '') and
					($userConfiguration{$key}{'VALUE'} eq ''))) {

			if ($AppConfig::userConfigurationSchema{$key}{'default'} =~ /^__/) {
				my @kNames = $AppConfig::userConfigurationSchema{$key}{'default'} =~ /__[A-Za-z0-9]+__/g;
				for(@kNames) {
					$_ =~ s/__//g;
					my $func = \&{$_};
					$userConfiguration{$key}{'VALUE'} = &$func();
				}
			}
			else {
				$userConfiguration{$key}{'VALUE'} = $AppConfig::userConfigurationSchema{$key}{'default'};
			}
			$AppConfig::isUserConfigModified = 1;
		}
	}
	# Validating SERVERROOT value if dedup is ON
	if ($userConfiguration{'DEDUP'}{'VALUE'} eq 'on'){
		if ($userConfiguration{'SERVERROOT'}{'VALUE'} eq '') {
			traceLog("SERVERROOT is misssing." );
			return 101;
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: verifyEVSBinary
# Objective				: This is to verify the EVS binary
# Added By				: Anil Kumar
#****************************************************************************************************/
sub verifyEVSBinary {
	my $evs = $_[0];
	unless (-f $evs) {
		my $test = $LS{'unable_to_find'} . $evs;
		return (0, $test);
	}

	chmod(0777, $evs);
	unless(-x $evs) {
		#return (0, $LS{'does_not_have_execute_permission'} .$evs);
		retreat($LS{'evs_binary'}."'$evs' ".$LS{'does_not_have_execute_permission'}."\n".$LS{'please_provide_permission_try'});
	}
	$evs = getECatfile($evs);
	$evs = updateLocaleCmd($evs);
	my $output = `$evs -h 2>/dev/null`;

	if ($? > 0) {
		return (0, "EVS execution error:".$?);
	}
	return (1, "");
}

#*****************************************************************************************************
# Subroutine			: verifyStaticPerlBinary
# Objective				: This is to verify the static perl binary
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub verifyStaticPerlBinary {
	my $sp = $_[0];
	unless (-f $sp) {
		my $test = $LS{'unable_to_find'} . $sp;
		return (0, $test);
	}

	chmod(0755, $sp);
	unless(-x $sp) {
		#return (0, $sp.$LS{'does_not_have_execute_permission'});
		retreat($LS{'perl_binary'}."'$sp' ".$LS{'does_not_have_execute_permission'}."\n".$LS{'please_provide_permission_try'});
	}

	$sp = getECatfile($sp);
	$sp = updateLocaleCmd($sp);
	my $output = `$sp -v 2>/dev/null`;

	if ($? > 0) {
		return (0, 'static_perl_execution_error:' . $?);
	}
	return (1, '');
}

#*****************************************************************************************************
# Subroutine			: verifyVersionConfig
# In Param				: UNDEF
# Out Param				: String | Path
# Objective				: Verify the version and exit unless conditions match
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub verifyVersionConfig {
	# no need to version check if scripts not configured
	return 1 if(!loadServicePath() or (!-f getUserFile() and !-f getOldUserFile()));

	my $vpath	= getVersionCachePath();
	my $cachver	= 0;

	if(-f $vpath) {
		$cachver	= getFileContents($vpath);
		Chomp(\$cachver);
	}

	return 1 if(versioncompare($AppConfig::version, $cachver) == 0);

	retreat(['version_mismatch_detected', '. ', 'configure_&_try_again']);
}

#*****************************************************************************************************
# Subroutine			: validateIPaddress
# Objective				: This is to validate IP address
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateIPaddress{
	my $ipAddress = shift;
	unless ($ipAddress =~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/){
		display(['invalid_ip_address',"\n"], 1);
		return 0;
    }
    return 1;
}

#*****************************************************************************************************
# Subroutine			: validateVersion
# Objective				: This is to validate version number.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub validateVersion{
    my $version = shift;
    unless($version =~ /^(\d+(\.\d+)?)$/) {
		display(['invalid_version',"\n"], 1);
		return 0;        
    }
    return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePercentage
# Objective				: This is to validate percentage of files for cleanup
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub validatePercentage {
	my $percentage    = $_[0];
	my $minPercentage = $_[1];
	my $maxPercentage = $_[2];
	if ($percentage !~ m/^[0-9]{1,3}$/ or !($percentage>=$minPercentage and $percentage<=$maxPercentage)) {
		display(['invalid_percentage', "\n"], 1);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePortNumber
# Objective				: This is to validate Port number
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validatePortNumber {
	my $portNumber = shift;
	unless ($portNumber =~ /^(0|[1-9][0-9]{0,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/){
		display(['invalid_port_number', "\n"], 1);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePassword
# Objective				: This subroutine helps to validate password
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub validatePassword {
	if ((length($_[0]) < 3) || (length($_[0]) > 20)) {
		display(['password_should_be_at_least_3_20_characters',"\n"],1) ;
		return 0;
	}
	elsif ($_[0] =~ /^(?=.{3,20}$)(?!.*\s+.*)(?!.*[\:\\]+.*)/) {
		return 1 ;
	}
}

#*****************************************************************************************************
# Subroutine			: validateDatePattern
# Objective				: This subroutine tests the date and validates the format
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateDatePattern {
	return $_[0] =~ m/^(0[1-9]|1[0-2])\/(0[1-9]|1\d|2\d|3[01])\/(19|20)\d{2}$/;
}

#*****************************************************************************************************
# Subroutine			: validateVersionNumber
# Objective				: This subroutine tests the version number and validates
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateVersionNumber {
	return !($_[0] !~ /^\d+$/ || $_[0] < 1 || $_[0] > $_[1]);
}

#*****************************************************************************************************
# Subroutine			: validateDetails
# Objective				: This subroutine is used to validate the user data as per the fields requested.
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub validateDetails {
	my $fieldType = $_[0];
	my $value 	  = $_[1];
	my $maxLimit  = $_[2];

	# TODO: review emptying values.
	if ($AppConfig::callerEnv eq 'BACKGROUND') {
		$value = $_[1] = '';
	}

	if ($fieldType eq "username"){
		return 0 unless(isValidUserName($value));
	}
	elsif ($fieldType eq "password"){
		return 0 unless(validatePassword($value));
	}
	elsif ($fieldType eq "private_key") {
		return 0 unless(validatePvtKey($value));
	}
	elsif ($fieldType eq "config_private_key") {
		return 0 unless(validateConfPvtKey($value));
	}
	elsif ($fieldType eq "single_email_address") {
		unless(isValidEmailAddress($value)) {
			return 1 if ($value eq "");
			display(['invalid_single_email_address'], 1);
			return 0 ;
		}
	}
	elsif ($fieldType eq "email_address") {
		return 0 unless(getInvalidEmailAddresses($value));
	}
	elsif ($fieldType eq "service_dir") {
		return 0 unless(validateServiceDir($value));
	}
	elsif ($fieldType eq "YN_choice") {
		return $_[1] = 'y' if ($AppConfig::callerEnv eq 'BACKGROUND');
		unless(validateChoiceOptions($value,'y','n')) {
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "PE_choice") { #PE Previous/Exit
		return 0 unless(validateChoiceOptions($value,'p','e'));
	}
	elsif($fieldType eq "PEMenu_choice") {
		return 1 if(validateChoiceOptions($value, 'p', 'e'));
		return 1 if(validateMenuChoice($value, 1, $maxLimit));
		display(['invalid_choice', "\n"], 1);
		return 0;
	}
	elsif ($fieldType eq "contact_no") {
		return 0 unless(validateContactNo($value));
	}
	elsif ($fieldType eq "ticket_no") {
		my $isOptional = (defined($maxLimit))?$maxLimit:0;
		return 0 unless(validateUserTicketNum($value, $isOptional));
	}
	elsif ($fieldType eq "ipaddress") {
		return 0 unless(validateIPaddress($value));
	}
	elsif ($fieldType eq "port_no") {
		return 0 unless(validatePortNumber($value));
	}
	elsif ($fieldType eq "percentage_for_cleanup") {
		return 0 unless(validatePercentage($value,1,100));
	}
	elsif ($fieldType eq "bw_value") {
		unless(validateBandWidthValue($value, 1, 100)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "failed_percent") {
		return 0 unless(validatePercentage($value, 0, 10));
	}
	elsif ($fieldType eq "missed_percent") {
		return 0 unless(validatePercentage($value,0,10));
	}
	elsif ($fieldType eq "backup_location") {
		return 0 unless(validateBackupLoction($value));
	}
	elsif ($fieldType eq "local_restore_from_location") {
		return 0 unless(validateLocalRestoreFromLoction($value));
	}
	elsif ($fieldType eq '24hours_validator') {
		if (($value !~ /^\d+$/) || (($value =~ /\d/) && ($value < 0 || $value >= 24))) {
			display(['invalid_choice',"\n"], 1);
			return 0;
		}
	}
	elsif ($fieldType eq 'minutes_validator') {
		if (($value !~ /^\d+$/) || (($value =~ /\d/) && ($value < 0 || $value > 59))) {
			display(['invalid_choice',"\n"], 1);
			return 0;
		}
	}
	elsif ($fieldType eq 'week_days_in_number') {
		foreach(split(',', $value)) {
			if (!$_ || ($_ !~ /\d/) || ($_ !~ /^0?[1-7]$/)) {
				display(['invalid_choice', "\n"], 1);
				return 0;
			}
		}
	}
	elsif ($fieldType eq "periodic_cleanup_per") {
		unless(validateMenuChoice($value, 5, 25)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "periodic_cleanup_days") {
		unless(validateMenuChoice($value, 5, 30)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "cdp_frequency") {
		# if (!$value || ($value !~ /\d/) || ($value !~ /^1$|^10$|^30$|^60$/)) {
		if (!$value or ($value !~ /\d/) or !validateMenuChoice($value, 1, 4)) {
			display(['invalid_choice', "\n"], 1);
			return 0;
		}
	}
	elsif ($fieldType eq "cdp_rescan_interval") {
		unless(validateMenuChoice($value, 1, 30)){
			display(['invalid_choice', "\n"], 1);
			return 0;
		}
	}
	elsif ($fieldType eq "non_empty") {		# no need to check the condition, but added for a safer purpose
		if ($value eq '') {
			display(['cannot_be_empty', '.', ' ', 'please_try_again', '.',"\n"],1);
			return 0;
		}
	}
	elsif($fieldType eq "choice") {
		if (defined($maxLimit)) {
			if (!validateMenuChoice($value, 1, $maxLimit)) {
				display(['invalid_choice', ' ', 'please_try_again']);
			} else {
				return 1;
			}
		} else {
			display(['invalid_choice', ' ', 'please_try_again']);
		}
		return 0;
	}
	elsif($fieldType eq "Q_choice") {
		if ($value eq 'q' or $value eq 'Q') {
			return 1;
		}
		elsif (defined($maxLimit)) {
			if (!validateMenuChoice($value, 1, $maxLimit)) {
				display(['invalid_choice', ' ', 'please_try_again']);
			} else {
				return 1;
			}
		} else {
			display(['invalid_choice', ' ', 'please_try_again']);
		}
		return 0;
	}
	elsif($fieldType eq "help_menu" or $fieldType eq "help_search_menu") {
		if ($value eq 'p' or $value eq 'P') {
			return 1;
		}
		elsif ($value eq 'e' or $value eq 'E') {
			exit;
		}
		elsif ($fieldType eq "help_search_menu" and ($value eq 'm' or $value eq 'M')) {
			return 1;
		}
		elsif (defined($maxLimit)) {
			if (!validateMenuChoice($value, 1, $maxLimit)) {
				display(['invalid_choice', ' ', 'please_try_again']);
			} else {
				return 1;
			}
		} else {
			display(['invalid_choice', ' ', 'please_try_again']);
		}
		return 0;
	}
    elsif ($fieldType eq "version") {
		return 0 unless(validateVersion($value));
        # return 0 unless(validateVersionNumber($value));
	} 
	elsif ($fieldType eq "file_path") {
		return 0 unless(validateFilePath($value));
        # return 0 unless(validateVersionNumber($value));
	}
	else{
		display("invalid_field_type_to_validate");
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateBandWidthValue
# Objective				: This is to validate the band width value
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateBandWidthValue {
	return validateMenuChoice(shift, shift, shift);
}

#*****************************************************************************************************
# Subroutine			: validateBackupLoction
# Objective				: This is to validate and return bucket name
# Added By				: Anil Kumar, Vijay Vinoth
#****************************************************************************************************/
sub validateBackupLoction {
	my $bucketName = $_[0];
	my $dedup = getUserConfiguration('DEDUP');
	if ($bucketName eq '') {
		return 1;
	}elsif (length($bucketName) > 65) {
		display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_be_one_to_sixty_five_characters'], 1);
		return 0;
	}elsif ($dedup eq 'on' and $bucketName =~ /^[a-zA-Z0-9_-]*$/) {
		return 1;
	}elsif ($dedup eq 'off') {
		return 1;
	}else {
		display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_contain_only_letters_numbers_space_and_characters', "\n"], 1);
		return 0;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateLocalRestoreFromLoction
# Objective				: This is to validate the local restore from location
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub validateLocalRestoreFromLoction {
	my $locName = $_[0];
	my $dedup = getUserConfiguration('DEDUP');

	if ($locName eq '') {
		$locName = $AppConfig::hostname;
		$locName =~ s/[^a-zA-Z0-9_-]//g;
		#display(['considering_default_backup_location',"\"$locName\""], 1);
		return 1;
	} elsif (length($locName) > 65) {
		display(['invalid_location', "\"$locName\". ", 'local_restore_from_location_should_be_one_to_sixty_five_characters'], 1);
		return 0;
	} elsif ($dedup eq 'on' and $locName =~ /^[a-zA-Z0-9_-]*$/) {
		return 1;
	} elsif ($dedup eq 'off') {
		return 1;
	} else {
		display(['invalid_location', "\"$locName\". ", 'local_restore_from_location_should_contain_only_letters_numbers_space_and_characters', "\n"], 1);
		return 0;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateServiceDir
# Objective				: This subroutine is used to validate the service directory
# Added By				: Anil Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub validateServiceDir {
	my $dir = $_[0];
	if ($dir eq '') {
		$dir = dirname(getAppPath());
		display(['your_default_service_directory'],1);
	}
	my $oldServiceDir = getServicePath()."/";
	my $checkPath  = substr $dir, -1;
	$dir = $dir ."/" if ($checkPath ne '/');
	my $newServiceDir = $dir.$AppConfig::servicePathName."/";
	#print "new: $dir ==== old: $oldServiceDir \n \n ";
	if (!-d $dir) {
		display(["$dir ", 'no_such_directory_try_again',"\n"]);
		return 0;
	}
	elsif (!-w $dir) {
		display(['cannot_open_directory', " $dir ", 'permission_denied',"\n"]);
		return 0;
	}
	elsif (index($dir, $oldServiceDir) != -1) {
		display(["\n",'invalid_location',". ",'Reason','new_service_dir_must_not_be_sub_dir_of_old',"\n"],1);
		return 0;
	}
	elsif ($newServiceDir eq $oldServiceDir) {
		display(["\n",'invalid_location',". ",'Reason','existing_service_directory_is_as_same_as_the_new',"\n"],1);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateContactNo
# Objective				: This subroutine is used to validate contact number
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateContactNo {
	my $reportUserContact = $_[0];
	if ($reportUserContact eq ""){
		return 1 ;
	}
	elsif (length($reportUserContact) < 5 || length($reportUserContact) > 20) {
		display(['invalid_contact_number', '. ', 'contact_number_between_5_20', '.']);
		return 0;
	}
	elsif ($reportUserContact ne '' && ($reportUserContact !~ m/^\d{5,20}$/)) {
		display(['invalid_contact_number', '. ', 'contact_number_only_digits', '.']);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateUserTicketNum
# Objective				: This subroutine is used to validate ticket number
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub validateUserTicketNum {
	my $ticketNo = $_[0];
	my $appID    = substr($AppConfig::appType, 0, 2);

	if (!$_[1] && $ticketNo eq ""){
		return 1;
	}
	elsif ($ticketNo !~ m/^[a-zA-Z0-9]{5,30}$/) {
		display(['invalid_ticket_number', '. ', 'ticket_number_only_alphanumeric', '.']);
		return 0;
	} 	# elsif (length($ticketNo) < 5 || length($ticketNo) > 30) {
	elsif ($ticketNo eq "" or length($ticketNo) != 11) {
		display(['invalid_ticket_number', '. ', 'ticket_number_must_11_char', '.']);
		return 0;
	} elsif($ticketNo !~ m/^$appID(\d+){1,11}$/) {
		display(['invalid_ticket_number', '.']);
		return 0;
	}
	display('');
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePvtKey
# Objective				: This subroutine is used to validate private key pattern
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validatePvtKey {
	my $value = $_[0];
	if (length($value) < 4) {
		display(['encryption_key_must_be_minimum_4_characters', '.',"\n"]) ;
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateConfPvtKey
# Objective				: This subroutine is used to validate private key pattern at the time of config
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateConfPvtKey {
	my $value = $_[0];
	if (length($value) < 6 || length($value) > 250)
	{
		display(['encryption_key_must_be_minimum_6_characters', '.',"\n"]) ;
		return 0;
	}
	elsif ( $value =~ /\s/ ) {
		display(['encryption_key_cannot_contain_blank_space',"\n"]) ;
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: versioncompare
# Objective				: This subroutine is for basic version compare. returns the result of comparison
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub versioncompare {
	# version == : 0 | first version > : 1 | second version > : 2
	my @vera = split('\.', $_[0]);
	my @verb = split('\.', $_[1]);

	for my $i (0 .. scalar(@vera)) {
		if (defined($vera[$i]) && defined($verb[$i])) {
			return 1 if ($vera[$i] > $verb[$i]);
			return 2 if ($vera[$i] < $verb[$i]);
		}
	}

	return 1 if ($#vera > $#verb);
	return 2 if ($#verb > $#vera);

	return 0;
}

#*****************************************************************************************************
# Subroutine			: verifyEditedFileContent
# Objective				: Verify the edited supported file content
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub verifyEditedFileContent {
	my $filePath = $_[0];
	my $fileType = $_[1];
	my (@itemArray,@newItemArray) = () x 2;

	if (-e $filePath and !-z $filePath){
		if (!open(FILE_HANDLE, $filePath)) {
			retreat(getStringConstant('failed_to_open_file')." : $filePath. Reason :$!");
		}
		@itemArray = <FILE_HANDLE>;
		close(FILE_HANDLE);
	} elsif (reftype(\$filePath) eq 'REF') {
		@itemArray = @{$_[0]};
	}

	display(['verifying_edited_file_content',"\n"]);
	if (scalar(@itemArray) > 0) {
        #Regex exclude item 
        if(defined($fileType) and $fileType =~ /regex/i) {
            foreach my $item (@itemArray){
                chomp($item);
                if ($item =~ m/^$/) {
                    next;
                }
                elsif ($item =~ m/^[\s\t]+$/) {
                    next;
                }
                elsif ($item =~ m/^[\s\t]+$/) {
                    display(["Skipped [$item]. ", "Reason",'Invalid regex']);
                    $skippedItem = 1;
                    next;
                }

                my $b = eval { qr/$item/ };
                if ($@) {
                    display(["Skipped [$item]. ", "Reason",'Invalid regex']);
                    $skippedItem = 1;
                    next;
                }
                push @newItemArray, $item;
            }
        } 
        else {
            #Fullpath exclude, Backup, Restore items
            foreach my $item (@itemArray){
                chomp($item);
                my $orgItem = $item;
                $item =~ s/[\/]+/\//g; #Replacing multiple "/" with single "/"
                my $tempItem = $item;
                Chomp(\$tempItem);

                if ($tempItem =~ m/^$/) {
                    next;
                }
                elsif ($tempItem =~ m/^[\s\t]+$/) {
                    next;
                }
                elsif ($tempItem eq "." or $tempItem eq ".." or $tempItem eq "/") {
                    display(["Skipped [$orgItem]. ", "Reason",'invalid_file_folder_path']);
                    $skippedItem = 1;
                    next;
                } elsif (substr($tempItem,0,1) ne "/") {
                    $item = '/'.$item;
                }
                push @newItemArray, $item;
            }
        }
	}

	return @newItemArray;
}

#*****************************************************************************************************
# Subroutine			: validateEncryptionType
# Objective				: Re-check the encryption type whether configured account's type changed or not (It may happen in a/c reset case)
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************************************/
sub validateEncryptionType {
	my $uname = getUsername();
	my $upswd = &getPdata($uname);
	my $encType = getUserConfiguration('ENCRYPTIONTYPE');
	my @responseData;
	my $errStr = '';

	my $res = makeRequest(12);
	if ($res) {
		@responseData = parseEVSCmdOutput($res->{DATA}, 'login', 1);
		if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
			my $errorMsg = getStringConstant('failed_to_authenticate_username');
			$errorMsg =~ s/__USER__/$uname/;
			# print "errorMsg:$errorMsg#\n\n\n";
			if (exists $responseData[0]->{'MSG'}) {
				checkAndUpdateAccStatError($uname, $responseData[0]->{'MSG'});
				$errStr = "\n".$errorMsg.' '.ucfirst($responseData[0]->{'MSG'}).'. '.$LS{'please_try_again'};
				return (0,$errStr);
			} elsif (exists $responseData[0]->{'desc'}) {
				checkAndUpdateAccStatError($uname, $responseData[0]->{'desc'});
				$errStr = "\n".$errorMsg.' '.ucfirst($responseData[0]->{'desc'}).'. '.$LS{'please_try_again'};
				return (0,$errStr);
			} else {
				$errStr = "\n".$errorMsg.' '.$LS{'please_try_again'};
				return (0,$errStr);
			}
		}

		if ($responseData[0]->{'STATUS'} eq 'SUCCESS') {
			if($responseData[0]->{'enctype'} eq $encType) {
				return (1,$errStr);
			} elsif ($responseData[0]->{'cnfgstat'} eq 'NOT SET' || $responseData[0]->{'enctype'} ne $encType) {
				$errStr = "\n" . $LS{'your_account_not_configured_properly'};
				return (0, $errStr);
			}
		}
	}

	$errStr = "\n".$LS{'unable_to_verify_account_detail'}.' '.$LS{'please_try_again'};
	return (0,$errStr);
}
	
#*****************************************************************************************************
# Subroutine/Function   : validateEncryptionKey
# In Param  : 
# Out Param : 
# Objective	: This subroutine to validate encryption type & private key
# Added By	: Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub validateEncryptionKey {
	my @responseData;
	my $status = 1;
	my $totalNoOfRetry = $AppConfig::maxChoiceRetry;
	my $encType = getUserConfiguration('ENCRYPTIONTYPE');
	my $errStr = '';
	return ($status,$errStr) if ($encType ne 'PRIVATE');

RETRY:
	if (getUserConfiguration('DEDUP') eq 'on') {
		@responseData = fetchAllDevices();
	}
	else {
		# validate private key for non dedup account
		createUTF8File('PING');
		@responseData = runEVS();
	}
# use Data::Dumper;
# print Dumper(\@responseData);
	if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
		if($responseData[0]->{'MSG'} =~ /unauthorized user|user information not found/i) {
			updateAccountStatus(getUsername(), 'UA');
			saveServerAddress(fetchServerAddress());
			traceLog('validateEncryptionType Retry');
			$totalNoOfRetry--;			
			goto RETRY if($totalNoOfRetry);
		}
		$status = 0;
	}

	unless($status) {
		$errStr = $responseData[0]->{'MSG'};
		checkErrorAndLogout($errStr, undef, 1);
	}

	$AppConfig::encType = $encType;
	return ($status,$errStr);
}

#*****************************************************************************************************
# Subroutine/Function   : validatePrivateKeyContent
# In Param  : 
# Out Param : 
# Objective	: This subroutine to validate private key & hash
# Added By	: Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub validatePrivateKeyContent {
	my $encType = getUserConfiguration('ENCRYPTIONTYPE');
	if ($encType eq 'PRIVATE') {
		if(-e getIDPVTFile()) {
			my $hashVal = getFileContents(getIDPVTFile());
			return 0 if($hashVal ne $AppConfig::pvtKeyHash);
		} else {
			return 0;
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine/Function   : validateFilePath
# In Param  : filePath
# Out Param : Boolean
# Objective	: This subroutine to validate local file path
# Added By	: Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub validateFilePath {
	if($_[0] eq '') {
		display(['cannot_be_empty', '.', ' ', 'enter_again', '.',"\n"]);
		return 0;
	} elsif(!-f $_[0]) {
		display(['invalid_file_path', '.', ' ', 'enter_again', '.',"\n"]);
		return 0;
	}
	return 1;
}

#------------------------------------------------- W -------------------------------------------------#
#***************************************************************************************************
# Subroutine/Function   : waitForNetworkConnection
# In Param      : jobName
# Out Param     :
# Objective     : This subroutine to wait for network connection
# Added By      : Senthil Pandian
# Modified By   :
#****************************************************************************************************/
sub waitForNetworkConnection {
    my $jobType       = $_[0];
    my $jobRunningDir = getJobsPath($jobType);
    my $pidPath       = getCatfile($jobRunningDir, $AppConfig::pidFile);
    while(1) {
		last unless(-f $pidPath);
        my $isInternetAvailable = isInternetAvailable();
        # traceLog("isInternetAvailable:$operationEngineId: $isInternetAvailable");
        #last if(isInternetAvailable());
        last if($isInternetAvailable);
        # traceLog("waitForNetworkConnection:$operationEngineId: Network is unreachable");
        sleep(30);
    }
}

#*****************************************************************************************************
# Subroutine			: waitForUpdate
# Objective				: This subroutine to check whether script update begins or not and it will wait if it begins.
# Added By				: Senthil Pandian
# Modified By			: Yogesh Kumar, Sabin Cheruvattil
#****************************************************************************************************/
sub waitForUpdate {
	loadAppPath();
	return 0 unless(loadServicePath());

	my $updatePid = getCatfile(getCachedDir(), $AppConfig::updatePid);
    my $preupdpid = getCatfile(getCachedDir(), $AppConfig::preupdpid);

    $updatePid = (-f $updatePid)?$updatePid:$preupdpid;
	if (-f $updatePid) {
		if(isFileLocked($updatePid)) {
			display(['updating_scripts_wait', '...', "\n"]);
			traceLog('updating_scripts_wait');
		}

		while(isFileLocked($updatePid)) {
			sleepForMilliSec(100); # Sleep for 100 milliseconds
		}

		unlink($updatePid) if (-f $updatePid);
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: writeToTrace
# Objective				: This subroutine writes to log
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub writeToTrace {
	if (open my $log_trace_handle, ">>", $_[0]){
		my $date = strftime "%Y/%m/%d %H:%M:%S", localtime;
		# do not use getMachineUser() in the following line | in cli, it gives undef
		my $logContent;
		unless (defined($_[2]) and $_[2]) {
			$logContent = qq([$date][) . $AppConfig::mcUser . qq(]$_[1]);
		}
		else {
			$logContent = qq($_[1]);
		}

		print $log_trace_handle $logContent;
		close($log_trace_handle);
	}
}

#*******************************************************************************************
# Subroutine Name         :	writeOperationSummary
# Objective               :	This subroutine writes the restore summary to the output file.
# Added By                : Senthil Pandian
# Modified By             : Yogesh Kumar, Sabin Cheruvattil, Senthil Pandian
#******************************************************************************************
sub writeOperationSummary {
	my @now     = localtime;
	my $endTime = localtime(mktime(@now));

	my $errorDir       = getCatfile($AppConfig::jobRunningDir, $AppConfig::errorDir);
	# my $excludeDirPath = getCatfile($AppConfig::jobRunningDir, $AppConfig::excludeDir);
	my $infoFile       = getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);

	my ($successFiles,$syncedFiles,$failedFilesCount,$filesConsideredCount,$noPermissionCount,$missingCount,$transferredFileSize,$modifiedFilesCount) = (0) x 8;

	if ($AppConfig::totalFiles) {
		$filesConsideredCount = $AppConfig::totalFiles;
		Chomp(\$filesConsideredCount);
	} elsif (-f $infoFile) {
		my $totalCountCheckCmd = "cat '$infoFile' | grep \"^TOTALFILES\"";
		$totalCountCheckCmd = updateLocaleCmd($totalCountCheckCmd);
		$filesConsideredCount = `$totalCountCheckCmd`;
		$filesConsideredCount =~ s/TOTALFILES//;
		Chomp(\$filesConsideredCount) if ($filesConsideredCount);
	}

	my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','DENIED_COUNT_FILES','MISSED_FILES_COUNT','TOTAL_TRANSFERRED_SIZE','MODIFIED_FILES_COUNT');
	($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount, $transferredFileSize, $modifiedFilesCount) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
	chmod $AppConfig::filePermission, $AppConfig::outputFilePath;

	my $fs = convertFileSize($transferredFileSize);

	# If $outputFilePath exists then only summery will be written otherwise no summery file will exists.
	if ((-e $AppConfig::outputFilePath) and (!-z $AppConfig::outputFilePath)) {
		# open output.txt file to write restore summary.
		if (!open(OUTFILE, ">> $AppConfig::outputFilePath")){
			traceLog(['failed_to_open_file', " : $AppConfig::outputFilePath Reason:$!\n"]);
			return;
		}
		chmod $AppConfig::filePermission, $AppConfig::outputFilePath;

         unless($successFiles) {
            my $progressFile = getCatfile($AppConfig::jobRunningDir, $AppConfig::progressDetailsFilePath."_1");
            if(-f $progressFile) {
                if($_[0] =~ $AppConfig::evsOperations{'BackupOp'}) { #For online/Local Backup
                    $summary .= getStringConstant('no_items_to_backup')."\n\n";
                } else {
                    $summary .= getStringConstant('no_items_to_restore')."\n\n";
                }
            }
        } 
        else {
            $summary .= "\n";
        }
       
		$summary .= appendExcludedLogFileContents();

		if ($_[0] eq $AppConfig::evsOperations{'BackupOp'} || $_[0] eq $AppConfig::evsOperations{'LocalBackupOp'}) {
			my $isIgnorePermissionErrors = (getUserConfiguration('IFPE') ne '')? getUserConfiguration('IFPE') :0;
			$isIgnorePermissionErrors    = ($isIgnorePermissionErrors ne '')?$isIgnorePermissionErrors:0;

			if ($isIgnorePermissionErrors){
				my $permissionError 	 = $errorDir."/".$AppConfig::permissionErrorFile;
				$summary .= checkAndUpdatePermissionDeniedList($permissionError);
				$filesConsideredCount -= $noPermissionCount;
			} else {
				#$failedFilesCount += $noPermissionCount; #Commented by Senthil on 11-June-2019
				$AppConfig::noPermissionCount = getPermissionDeniedCount();
				if ($AppConfig::noPermissionCount){
					$filesConsideredCount += $AppConfig::noPermissionCount;
					$failedFilesCount 	  += $AppConfig::noPermissionCount;
				}
			}

			$syncedFiles += getReadySyncCount();
		}

		if (($failedFilesCount ne "" and $failedFilesCount > 0) or ($AppConfig::nonExistsCount ne '' && $AppConfig::nonExistsCount > 0)) {
			$summary .= appendErrorFileContents($errorDir);
			$failedFilesCount += $AppConfig::nonExistsCount;
		}

		# construct summary message.
		my $mail_summary = undef;
        $summary .= $lineFeed;
        $summary .= "[SUMMARY] ".$lineFeed.(('-') x 9).$lineFeed;
		$AppConfig::finalSummary = $lineFeed."[SUMMARY] ".$lineFeed;

		#Needs to be removed: Senthil
		#$filesConsideredCount = 99;
		#$failedFilesCount  = 5;

		# Avoid empty count
		$filesConsideredCount = 0 unless($filesConsideredCount);

		if ($_[0] eq $AppConfig::evsOperations{'BackupOp'} || $_[0] eq $AppConfig::evsOperations{'LocalBackupOp'}) {
			# Prepare mail contents
			$mail_summary .= getStringConstant('files_considered_for_backup') . $filesConsideredCount."\n";
            $mail_summary .= getStringConstant('files_backed_up_now') . $successFiles. " [Added(".($successFiles-$modifiedFilesCount).")/modified($modifiedFilesCount)] [".getStringConstant('size_of_backed_up_files').$fs."]\n";
			$mail_summary .= getStringConstant('files_already_present_in_your_account') . $syncedFiles."\n";
			$mail_summary .= getStringConstant('files_failed_to_backup') . $failedFilesCount."\n";
			$mail_summary .= getStringConstant('backup_end_time') . "$endTime\n";
			$mail_summary .= "\n" . getStringConstant('files_in_trash_may_get_restored_notice') . "\n" if ($_[0] eq $AppConfig::evsOperations{'BackupOp'});

			my $hasDefExcl = hasDefaultExcludeInBackup(lc($_[0]));
			$mail_summary .= "\n" . getStringConstant('default_exclude_note') . "\n" if($hasDefExcl);

			# prepare summary content
			$AppConfig::finalSummary .= getStringConstant('files_considered_for_backup') . $filesConsideredCount."\n";
            $AppConfig::finalSummary .= getStringConstant('files_backed_up_now') . $successFiles. " [Added(".($successFiles-$modifiedFilesCount).")/modified($modifiedFilesCount)] [".getStringConstant('size_of_backed_up_files').$fs."]\n";
			$AppConfig::finalSummary .= getStringConstant('files_already_present_in_your_account') . $syncedFiles."\n";
			$AppConfig::finalSummary .= getStringConstant('files_failed_to_backup') . $failedFilesCount . "\n";
		} else 	{
			$mail_summary .= getStringConstant('files_considered_for_restore').$filesConsideredCount.
						"\n".getStringConstant('files_restored_now').$successFiles." [Size: $fs]".
						"\n".getStringConstant('files_already_present_in_your_restore_location').$syncedFiles.
						"\n".getStringConstant('files_failed_to_restore').$failedFilesCount.
						"\n".getStringConstant('restore_end_time')."$endTime\n";

			$AppConfig::finalSummary .= getStringConstant('files_considered_for_restore').$filesConsideredCount.
						"\n".getStringConstant('files_restored_now').$successFiles." [Size: $fs]".
						"\n".getStringConstant('files_already_present_in_your_restore_location').$syncedFiles.
						"\n".getStringConstant('files_failed_to_restore').$failedFilesCount."\n";
		}

		my $locerror = '';
		if($AppConfig::errStr && $AppConfig::errStr =~ /^2\-/) {
			$locerror = $AppConfig::errStr;
			$AppConfig::errStr =~ s/^2\-//g;
		}
		
		if ($AppConfig::errStr ne "" &&  $AppConfig::errStr ne "SUCCESS"){
			$mail_summary .= "\n".$AppConfig::errStr."\n";
		}

		if ($AppConfig::cancelFlag) {
			$AppConfig::opStatus = AppConfig::JOBEXITCODE->{'ABORTED'};
		}
		elsif ($failedFilesCount == 0 and $filesConsideredCount > 0) {
			$AppConfig::opStatus = AppConfig::JOBEXITCODE->{'SUCCESS'};
		}
		else {
			$AppConfig::opStatus = AppConfig::JOBEXITCODE->{'FAILURE'};
			# Considering the Failed case as Success if it less than the % user's selected
			if ($_[0] =~ /$AppConfig::evsOperations{'BackupOp'}/){
				if ($filesConsideredCount && $percentToNotifyForFailedFiles and $failedFilesCount>0){
					my $perCount = ($failedFilesCount/$filesConsideredCount)*100;
					if ($percentToNotifyForFailedFiles >= $perCount){
						$AppConfig::opStatus = AppConfig::JOBEXITCODE->{'SUCCESS*'};
					}
				}

				if ($AppConfig::opStatus eq AppConfig::JOBEXITCODE->{'FAILURE'}){
					if ($percentToNotifyForMissedFiles && -e $infoFile){
						$infoFile       = getCatfile($AppConfig::jobRunningDir, $AppConfig::infoFile);
						my $missedCountCheckCmd = "cat '$infoFile' | grep \"^MISSINGCOUNT\"";
						$missedCountCheckCmd = updateLocaleCmd($missedCountCheckCmd);
						my $missedCount = `$missedCountCheckCmd`;
						$missedCount =~ s/MISSINGCOUNT//;
						Chomp(\$missedCount) if ($missedCount);
						$missingCount += $missedCount if ($missedCount =~ /^\d+$/);

						if($filesConsideredCount and $missingCount) {
							my $perCount = ($missingCount/$filesConsideredCount)*100;
							if ($percentToNotifyForMissedFiles >= $perCount){
								$AppConfig::opStatus = AppConfig::JOBEXITCODE->{'SUCCESS*'};
							}
						}
					}
				}
			}
		}

		if($locerror && $locerror =~ /^2\-/ && $locerror !~ /backupset is empty/) {
			$AppConfig::opStatus = AppConfig::JOBEXITCODE->{'ABORTED'};
		}

		my $tempOutputFilePath = $AppConfig::outputFilePath;
		$tempOutputFilePath = (split("_Running_",$tempOutputFilePath))[0] if ($tempOutputFilePath =~ m/_Running_/);
		my %logStat = (
			(split('_', basename($tempOutputFilePath)))[0] => {
				'datetime' => strftime("%m/%d/%Y %H:%M:%S", localtime(mktime(@startTime))),
				'duration' => (mktime(@now) - mktime(@startTime)),
				'filescount' => $filesConsideredCount,
				'bkpfiles' => $successFiles,
				'status' => $AppConfig::opStatus . '_' . ucfirst($_[1])
			}
		);
		addLogStat($AppConfig::jobRunningDir, \%logStat);
		#Removing the LOGPID file
		my $logPidFilePath 	= getCatfile($AppConfig::jobRunningDir, $AppConfig::logPidFile);
		unlink($logPidFilePath);

		$summary .= $mail_summary;
		$AppConfig::mailContent .= $mail_summary;

		print OUTFILE $summary;
		close OUTFILE;
	} else {
		# Added to debug Harish_1.0.2_2_5 : Senthil
		Common::traceLog("writeOperationSummary outputFilePath:$AppConfig::outputFilePath");
		if(-f $AppConfig::outputFilePath) {
			Common::traceLog("writeOperationSummary SIZE:".(-s $AppConfig::outputFilePath))
		} else {
			Common::traceLog("writeOperationSummary outputFilePath not found");
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : writeLogHeader.
# Objective               : This function will write user log header.
# Added By				  : Senthil Pandian
# Modified By             : Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub writeLogHeader {
	my $taskType = lc($_[0]);
	my $logTime = time;
	#Chomp(\$logTime); #Removing white-space and '\n'
	my $archiveLogDirpath = $AppConfig::jobRunningDir.'/'.$AppConfig::logDir;
	createDir($archiveLogDirpath, 1);
	#my $logOutputFile  = $archiveLogDirpath.'/'.$logTime;
	my $logOutputFile  = $AppConfig::outputFilePath;
	my $backupPathType = getUserConfiguration('BACKUPTYPE');
	my $bwThrottle     = getUserConfiguration('BWTHROTTLE');
	my $restoreHost	   = getUserConfiguration('RESTOREFROM');
	my $backupTo	   = getUserConfiguration('BACKUPLOCATION');
	my $username       = getUsername();
	$percentToNotifyForFailedFiles = getUserConfiguration('NFB');
	$percentToNotifyForMissedFiles = getUserConfiguration('NMB');
	#my $logStartTime = `date +"%a %b %d %T %Y"`;

	#my $isScheduledJob = $_[0];
	# require to open log file to show job in progress as well as to log exclude details
	if (!open(OUTFILE, ">", $logOutputFile)){
		$AppConfig::errStr = getStringConstant('failed_to_open_file').": $logOutputFile, Reason:$!\n";
		traceLog($AppConfig::errStr);
		display($AppConfig::errStr);
        return $lineFeed.$AppConfig::errStr;
	}
	chmod $AppConfig::filePermission, $logOutputFile;

	autoflush OUTFILE;
	my $hostCmd = updateLocaleCmd('hostname');
	my $host = `$hostCmd`;
	chomp($host);

	autoflush OUTFILE;
	my $tempJobType = $AppConfig::jobType;
	my $backupMountPath = '';
	if ($tempJobType =~ /Local/){
		$tempJobType =~ s/Local//;
        my $mountPoint = getUserConfiguration('LOCALMOUNTPOINT');
        $mountPoint    = getUserConfiguration('LOCALRESTOREMOUNTPOINT') if ($tempJobType eq "Restore");
        my $expressLocalDir = getCatfile($mountPoint, ($AppConfig::appType . 'Local'));
        $AppConfig::expressLocalDir = $expressLocalDir;       
		$backupMountPath = "[Mount Path: $AppConfig::expressLocalDir]";
	}

	my $jobname = '';
	my $jt = 'backup';
	if (lc($AppConfig::jobType) eq "backup") {
		$jobname = "default_backupset";
	}
	elsif (lc($AppConfig::jobType) eq "localbackup") {
		$jobname = "local_backupset";
		$jt = "localbackup";
	}
	elsif (lc($AppConfig::jobType) eq "restore") {
		$jobname = "default_restoreset";
		$jt = "restore";
	}
	elsif (lc($AppConfig::jobType) eq "localrestore") {
		$jobname = "local_restoreset";
		$jt = "localrestore";
	}
	else {
		$jobname = "default_backupset";
	}

	@startTime = localtime();
	my $st = localtime(mktime(@startTime));

	my ($jsc, $exclsum, $mailHead) = ('') x 3;
	my $dedup  	      = getUserConfiguration('DEDUP');
	my $location = ($dedup eq 'on' and $backupTo =~ /#/)?(split('#',$backupTo))[1]:$backupTo;
	if ($dedup eq 'off' and $AppConfig::jobType eq "LocalBackup") {
		my @backupTo = split("/",$location);
		$location	 = (substr($location,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
	}

	# $mailHeadB .= "Machine Name: $host \n";
	# $mailHeadB .= "$tempJobType Location: $location \n";
	# $mailHeadB .= $backupMountPath;

	if ($tempJobType eq "Restore") {
        my $restoreLoc	 = getUserConfiguration('RESTORELOCATION');
		my $fromLocation = ($dedup eq 'on' and $restoreHost =~ /#/)?(split('#',$restoreHost))[1]:$restoreHost;
		$mailHead .= "[$tempJobType From Location: $fromLocation] ";
        $mailHead .= "[".getStringConstant('restore_location_progress').": $restoreLoc] ".$lineFeed;
        $mailHead .= $backupMountPath.$lineFeed.$lineFeed;
        $mailHead .= "$tempJobType Scheduled Time: " . getCRONScheduleTime($AppConfig::mcUser, $username, lc($tempJobType), $jobname).$lineFeed if($taskType ne "manual");
        $mailHead .= "$tempJobType Start Time: ".($st)."$lineFeed$lineFeed";

        $jsc .= "[RESTORE SET CONTENT]\n";
        $jsc .= (('-') x 22). "\n";
		$jsc .= getJobSetLogSummary($jt);
	}

	if ($AppConfig::jobType =~ /Backup/){
		$mailHead .= "[Failed files(%): $percentToNotifyForFailedFiles] ";
		$mailHead .= "[Missing files(%): $percentToNotifyForMissedFiles] ";
        $mailHead .= "[" . getStringConstant('title_machine_name')."$host] $lineFeed";

        $mailHead .= "[".getStringConstant('backup_location_progress').": $location] ";
		$mailHead .= "[Show hidden files/folders: ".(getUserConfiguration('SHOWHIDDEN')? 'enabled' : 'disabled')."] ";
		$mailHead .= ($AppConfig::jobType eq "Backup")?"[Throttle Value(%): $bwThrottle] $lineFeed":$lineFeed;

		$mailHead .= "[Ignore file/folder level permission errors: ".(getUserConfiguration('IFPE')? 'enabled' : 'disabled')."] ";
        $mailHead .= $backupMountPath.$lineFeed;
		$mailHead .= ($AppConfig::jobType eq "Backup" and $dedup eq 'off')?" [".getStringConstant('backup_type').": ".ucfirst($backupPathType)."] $lineFeed$lineFeed":$lineFeed;

        $mailHead .= "$tempJobType Scheduled Time: " . getCRONScheduleTime($AppConfig::mcUser, $username, lc($tempJobType), $jobname).$lineFeed if($taskType ne "manual");
        $mailHead .= "$tempJobType Start Time: ".($st).$lineFeed.$lineFeed;

		$jsc .= ($jt eq 'backup'? '[BACKUP SET CONTENT]' : '[EXPRESS BACKUP SET CONTENT]') . "\n";
        $jsc .= ($jt eq 'backup'? (('-') x 20): (('-') x 28)).$lineFeed;
		$jsc .= getJobSetLogSummary($jt);
		$exclsum .= getExcludeSetSummary($jt);
	}

    my $LogHead  = getStringConstant('details_log_header') .$lineFeed;
    $LogHead .= (('-') x 9). $lineFeed;
    $LogHead .= "[" . getStringConstant('version_cc_label') . $AppConfig::version . '] ';
    $LogHead .= "[" . getStringConstant('release_date_cc_label') . $AppConfig::releasedate . "] ";
    $LogHead .= "[" . getStringConstant('username_cc') . ": $username] $lineFeed";
    $LogHead .= $mailHead . $jsc . $exclsum;
	print OUTFILE $LogHead;

	return $lineFeed.$mailHead;
}

#****************************************************************************************************
# Subroutine Name         : writeParamToFile.
# Objective               : This subroutine will write parameters into a file named operations.txt. Later it is used in Operations.pl script.
# Modified By             : Abhishek Verma, Senthil Pandian
#*****************************************************************************************************/
sub writeParamToFile {
	my $fileName = shift;
	if (!open(PH,'>',$fileName)){ #PH means Parameter file handler.
		$AppConfig::errStr = getStringConstant('failed_to_open_file').": $fileName, Reason:$!\n";
		traceLog($AppConfig::errStr);
		display($AppConfig::errStr);
		cancelProcess();
	}
	print PH @_;
	close (PH);
	chmod $AppConfig::filePermission,$fileName;
}

#****************************************************************************************************
# Subroutine Name         : writeCrontab.
# Objective               :
# Added By				  : Vijay Vinoth
#*****************************************************************************************************/
sub writeCrontab {
	my $cron = "/etc/crontab";
	if (!open CRON, ">", $cron) {
		exit 0;
	}
	print CRON @_;
	close(CRON);
}

#*****************************************************************************************************
# Subroutine	: writeAsJSON
# In Param		: Path, hash
# Out Param		: Status | Boolean
# Objective		: Writes to a file as JSON
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub writeAsJSON {
	my $wfile = $_[0];
	my $whash = $_[1]? $_[1] : {};

	return 0 if(!$wfile);
	return fileWrite($wfile, JSON::to_json($whash));
}

#*******************************************************************************************************
# Subroutine		: waitForEnginesToFinish
# Objective			: Check the status of all engines and wait to complete to finish the job
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#********************************************************************************************************/
sub waitForEnginesToFinish {
	my @BackupForkchilds = @{$_[0]};
	my $engineLockFile = $_[1];
	my $res = '';
	while(@BackupForkchilds > 0) {
		for (my $i=0; $i<=$#BackupForkchilds; $i++) {
			$res = waitpid($BackupForkchilds[$i], WNOHANG);
			splice(@BackupForkchilds, $i, 1)	if ($res == -1 || $res > 0);
			sleep(1);
		}
	}

	while(isAnyEngineRunning($engineLockFile)) {
		sleep(1);
	}

	return;
}

#*******************************************************************************************************
# Subroutine		: waitForChildProcess
# Objective			: Check the status of all engines and wait to complete to finish the job
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#********************************************************************************************************/
sub waitForChildProcess {
	my $enginePID			= $_[0];
	my $totalEngineBackup 	= (getUserConfiguration('ENGINECOUNT') eq $AppConfig::minEngineCount)? $AppConfig::minEngineCount : $AppConfig::maxEngineCount;

	if(defined($enginePID)) {
		if (-e $enginePID) {
			my $pid = getFileContents($enginePID);
			Chomp(\$pid);
			return unless($pid);
			while(kill( 0, $pid)) {
				sleepForMilliSec(100); # Sleep for 100 milliseconds
			}
			unlink($enginePID) if (-e $enginePID);
		}
	} else {
		my $pidPath = $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
		for (my $i=1; $i<=$totalEngineBackup; $i++) {
			my $procPidFile = $pidPath.'_proc_'.$i;
			if (-e $procPidFile) {
				my $pid = getFileContents($procPidFile);
				Chomp(\$pid);
				next unless($pid);
				while(kill( 0, $pid)) {
					sleepForMilliSec(100); # Sleep for 100 milliseconds
				}
				unlink($procPidFile) if (-e $procPidFile);
			}
		}
	}
}

#------------------------------------------------- X -------------------------------------------------#
#------------------------------------------------- Y -------------------------------------------------#
#------------------------------------------------- Z -------------------------------------------------#


#*********************************************************************************************************
# Subroutine Name        : getMountedPathForRestore 
# Objective              : This function will return mounted devices list to restore the data
# Added By               : Senthil Pandian.
#*********************************************************************************************************/
sub getMountedPathForRestore {
	my @linkDataList = ();
	my ($userInput,$choice) = (0) x 2;
	my $maxNumRetryAttempts = 3;
	my $localRestoreFromLocation = '';
	my $dedup = getUserConfiguration('DEDUP');
	#Verifying existing mount point for scheduled backup
	my $silentBackupFlag = shift || 0;
	if ($silentBackupFlag) {
		$localRestoreFromLocation = getUserConfiguration('LOCALRESTOREMOUNTPOINT');
		chomp($localRestoreFromLocation);
		if ($localRestoreFromLocation ne '') {
			if (!-e "$localRestoreFromLocation") {
				traceLog($LS{'mount_point_not_exist'});
				exit 0;
			}
			elsif(!-r "$localRestoreFromLocation") {
				traceLog($LS{'mount_point_doesnt_have_permission'});
				exit 0;
			}
			return $localRestoreFromLocation;
		} else {
			traceLog($LS{'unable_to_find_mount_point_with_data'});
			exit 0;
		}
	}

	display('loading_mount_points');
	my $mountedDevices = getMountPoints();
	if(scalar(keys %{$mountedDevices})>0){
		foreach my $mountPath (keys %{$mountedDevices}){
			my $expressLocalDir = getCatfile($mountPath, ($AppConfig::appType . 'Local'));
			my $localUserPath   = getCatfile($expressLocalDir, $username);
			#unless(-e $localUserPath."/".$AppConfig::dbPathsXML){
			unless(-d $localUserPath){
				delete $mountedDevices->{$mountPath};
			}
		}
	}

	if(scalar(keys %{$mountedDevices})>0){
		display(['select_mount_point_to_restore',"\n"]);
		my @mountPointcolumnNames = (['S.No','Mount Point','Permissions'],[8,30,15]);
		my $tableHeader = getTableHeader(@mountPointcolumnNames);
		my ($tableData,$columnIndex,$serialNumber,$index) = ('',1,1,0);

		foreach my $mountPath (keys %{$mountedDevices}){
			$columnIndex = 1;

			my $mountDevicePath     = $mountPath;
			my $mountDevicePathPerm = $mountedDevices->{$mountPath}{'mode'};
			$index++;
			$tableData .= $serialNumber;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[0] - length($serialNumber));

			$mountDevicePath = trimData($mountDevicePath,$mountPointcolumnNames[1]->[$columnIndex]) if($columnIndex == 1 or $columnIndex == 3);
			$tableData .= $mountDevicePath;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[$columnIndex] - length($mountDevicePath));
			$tableData .= $mountDevicePathPerm;
			$columnIndex++;
			$tableData .= "\n";
			$serialNumber += 1;
			push (@linkDataList,$mountPath);
		}
		if ($tableData ne ''){
			print $tableHeader.$tableData;
		}
	} else {
		display('unable_to_find_mount_point_with_data');
	}

	if(scalar(@linkDataList)>0){
		my $userChoice = getUserMenuOrCustomChoice('enter_sno_to_select_mount_point',@linkDataList);
		if($userChoice eq 'q' or $userChoice eq 'Q'){
			@linkDataList = ();
		} elsif($userChoice ne '') {
			$localRestoreFromLocation = $linkDataList[$userChoice - 1];
		}
	}

	if (scalar(@linkDataList)<=0) {
		$localRestoreFromLocation = getUserConfiguration('LOCALRESTOREMOUNTPOINT');
		chomp($localRestoreFromLocation);
		if ($localRestoreFromLocation ne '') {
			my $expressLocalDir = getCatfile($localRestoreFromLocation, ($AppConfig::appType . 'Local'));
			my $localUserPath   = getCatfile($expressLocalDir, $username);
			#if(!-d $localUserPath or !-w $localUserPath or !-e $localUserPath."/".$AppConfig::dbPathsXML){
			if(!-d $localUserPath or !-w $localUserPath){
				$localRestoreFromLocation ='';
			}
		}

		if($localRestoreFromLocation){
			#my $mountPointQuery = Constants->CONST->{'YourPreviousMountPoint'}->($localBackupLocation);
			#my $mountPointQuery = $LS{'your_previous_mount_point'};
			#$mountPointQuery =~ s/<ARG>/$localRestoreFromLocation/;
			#display("\n$mountPointQuery");
			display(['your_previous_mount_point',"'$localRestoreFromLocation'.",' ', 'do_you_really_want_to_edit_(_y_n_)', '?']);
			my $msg = $LS{'enter_your_choice'};
			my $loginConfirmation = getAndValidate($msg, "YN_choice", 1);
			if(lc($loginConfirmation) eq 'n'){
				goto USEEXISTING;
			}
		} else {
			display(["\n",'do_you_want_enter_mount_point_for_restore']);
			my $msg = $LS{'enter_your_choice'};
			my $loginConfirmation = getAndValidate($msg, "YN_choice", 1);
			if(lc($loginConfirmation) eq 'n'){
				display(["\n",'exit',"\n"]);
				cancelProcess();
			}
		}
		while ($maxNumRetryAttempts){
			display(["\n",'enter_mount_point'],0);
			$localRestoreFromLocation = <STDIN>;
			Chomp(\$localRestoreFromLocation);chomp($localRestoreFromLocation);
			my $expressLocalDir = getCatfile($localRestoreFromLocation, ($AppConfig::appType . 'Local'));
			my $localUserPath   = getCatfile($expressLocalDir, $username);

			if(!-e "$localRestoreFromLocation"){
				display(['mount_point_not_exist']);
			}
			#elsif($dedup eq 'on' and !-e $localUserPath."/".$AppConfig::dbPathsXML){
			elsif(!-e $localUserPath){
				# display(['mount_point_doesnt_have_user_data',"\n"]);
                retreat(['mount_point_doesnt_have_user_data']);
			}
			elsif(!-r "$localRestoreFromLocation") {
				display(['mount_point_doesnt_have_permission']);
			}
			else {
				my $tempLoc = $localRestoreFromLocation;
				$tempLoc =~ s/^[\/]+|^[.]+//;
				if(!$tempLoc) {
					display(['invalid_mount_point']);
				} else {
					last;
				}
			}
			$maxNumRetryAttempts -= 1;
		}
		if ($maxNumRetryAttempts == 0){
			display(['max_retry',"\n\n"]);
			cancelProcess();
		}
	}

	if($localRestoreFromLocation =~ /[\/]$/){
		chop($localRestoreFromLocation);
	}
	setUserConfiguration('LOCALRESTOREMOUNTPOINT', $localRestoreFromLocation);
	saveUserConfiguration() or retreat('failed_to_save_user_configuration');
USEEXISTING:
	my $str = $LS{'your_selected_mount_point_is'}."'$localRestoreFromLocation'.";
	#display([$str, "\n"]);
    display($str);
	return $localRestoreFromLocation;
}

#*****************************************************************************************************
# Subroutine			: getUserMenuOrCustomChoice
# Objective				: This subroutine helps to get the user's choices
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getUserMenuOrCustomChoice {
	my($userMenuChoice, $choiceRetry) = (0, 0);
	my($customMsg,@option) = @_;
	my $maxChoice = scalar(@option);
	while($choiceRetry < $AppConfig::maxChoiceRetry) {
		display(["\n", $customMsg], 0);
		$userMenuChoice = getUserChoice();
		$userMenuChoice	=~ s/^[\s\t]+|[\s\t]+$//g;
		$choiceRetry++;
		if ($userMenuChoice eq '') {
			display(['cannot_be_empty', '.', ' ', 'enter_again', '.']);
		}
		elsif ($userMenuChoice eq 'q' or $userMenuChoice eq 'Q'){
			last;
		}
		elsif (!validateMenuChoice($userMenuChoice, 1, $maxChoice)) {
			$userMenuChoice = '';
			display(['invalid_choice', ' ', 'please_try_again', '.']);
		}
		else {
			my $path 		   = $option[$userMenuChoice-1];
			my $permissionMode = getFileFolderPermissionMode($path);
			if ($permissionMode eq 'Writeable'){
				last;
			} else {
				display('mount_point_doesnt_have_permission');
			}
		}
		if ($choiceRetry == $AppConfig::maxChoiceRetry){
			display(["\n", 'your_max_attempt_reached', "\n"]);
			cancelProcess();
		}
	}
	return $userMenuChoice;
}

#*******************************************************************************************************
# Subroutine Name         :	startDBReIndex
# Objective               :	Start DB ReIndex operation when DB not exists & data missed
# Added By             	  : Senthil Pandian
#********************************************************************************************************/
sub startDBReIndex {
	my $mountedPath = $_[0];
	display('unable_to_fetch_regenerating_the_list');

	my $jobRunningDir   = getUsersInternalDirPath('dbreindex');
	my $pidPath 		= $jobRunningDir."/".$AppConfig::pidFile;
 	if (isFileLocked($pidPath)) {
		while(isFileLocked($pidPath)){
            sleep(1);
        }
	} else {    
        #my $cmd = (getIDrivePerlBin() . ' ' .getScript('utility', 1) . ' REINDEX '."'".$mountedPath."' 2>/dev/null"); We can use custom perl later
        my $cmd = "$AppConfig::perlBin '" . getAppPath() . $AppConfig::idriveScripts{'utility'} . "' 'REINDEX' '$AppConfig::jobType' '$mountedPath'";
        # print "\n\n\ncmd:$cmd\n\n\n";
        my $scriptTerm = system($cmd);
        if($scriptTerm) {
            my $reason = $?;
            # my $pid    = getFileContents($pidPath);
            # system("kill $pid");
            traceLog(['failed_to_run_script',$AppConfig::idriveScripts{'utility'},". Reason:".$reason]);
            retreat(['failed_to_reindex_database',". Reason:".$reason]);
        }
    }
}

#****************************************************************************************************
# Function Name         : getExpressDBPath
# Objective             : This will map the device and express DB real path
# Added By              : Senthil Pandian
#****************************************************************************************************/
sub getExpressDBPath
{
	my $expressLocalDBMapPath;
	my $mountedPath     		= (defined($_[0]) and $_[0])?$_[0]:getUserConfiguration('LOCALMOUNTPOINT');
    # $mountedPath     		    = getUserConfiguration('LOCALMOUNTPOINT') unless($mountedPath);
	my $userName 				= getUsername();
	my $expressDrive    		= getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   		= getCatfile($expressDrive, $userName);	
	my $dedup  	        		= getUserConfiguration('DEDUP');
	
	my $expressDriveDBMapPath 	= "$localUserPath/LDBNEW/";
	my $mapFile 				= $expressDriveDBMapPath.$AppConfig::dbMapFile;

	if(-f $mapFile){
		my $mapDir	= getFileContents($mapFile);
		Chomp(\$mapDir);
		$expressLocalDBMapPath	= getUserProfilePath()."/".$AppConfig::expressDbDir."/".$mapDir;
	} else {
        my $mapTime = time;
		$expressLocalDBMapPath	= getUserProfilePath()."/".$AppConfig::expressDbDir."/".$mapTime;
		createDir($expressDriveDBMapPath,1);
		createExpressDBMap($expressDrive, $mapTime);
	}

	if($dedup eq 'on') {
		if(defined($_[1])){
			$expressLocalDBMapPath	.= "/".$_[1];
		} else {
			$expressLocalDBMapPath	.= "/".getUserConfiguration('LOCALRESTORESERVERROOT');
		}		
	}
	unless(-d $expressLocalDBMapPath){
		createDir($expressLocalDBMapPath,1);
	}
	return $expressLocalDBMapPath.'/'.$userName.'.ibenc';
}

#****************************************************************************************************
# Function Name         : createExpressDBMap
# Objective             : This will create mapping for the Express Device and Actual DB Mapping
# Added By              : Senthil Pandian
#****************************************************************************************************
sub createExpressDBMap
{
	my $expressDrive 			= $_[0];
	my $mapTime					= $_[1];
	my $expressLocalDBMapPath	= '';
	my $dedup  	       			= getUserConfiguration('DEDUP');
	my $userName 				= getUsername();
	if($dedup eq 'on') {
		$expressLocalDBMapPath	.= "/".getUserConfiguration('SERVERROOT');
	}

	my $expressDBMapPath = "$expressDrive/$userName/LDBNEW/";
	if(!-d $expressDBMapPath) {
		createDir($expressDBMapPath,1);
	}

	# use glob to check if the map file is there or not
	my $mapPath  = $expressDBMapPath.$AppConfig::expressDBMapFile;
	if(-f $mapPath and !-z $mapPath) {
		return 1;
	}

	if(fileWrite($mapPath, $mapTime)) {
		createDir($expressDBMapPath,1);
		return 1;
	}
	return 0;
}

#****************************************************************************
# Subroutine			: editLocalRestoreFromLocation
# Objective				: Ask restore location and set the same
# Added By				: Senthil Pandian
#****************************************************************************/
sub editLocalRestoreFromLocation {
	my $rfl         = getUserConfiguration('LOCALRESTOREFROM');
    my $serverRoot  = getUserConfiguration('LOCALRESTORESERVERROOT');
	my $dedup       = getUserConfiguration('DEDUP');
    my $mountedPath = getUserConfiguration('LOCALRESTOREMOUNTPOINT');
	my $answer      = "y";
    my $dataPath    = getCatfile($mountedPath,$rfl);

	if ($dedup eq 'on'){
		$rfl = (split('#', $rfl))[-1];
        $dataPath    = getCatfile($mountedPath,$serverRoot);
	}

    #Added for Suruchi_2.32_17_4 : Senthil
    unless(-d $dataPath){
		$rfl        = getUserConfiguration('BACKUPLOCATION');
        $serverRoot = getUserConfiguration('SERVERROOT');

		if ($dedup eq 'on'){
			$rfl = (split('#', $rfl))[-1];
		} else {			
			my @backupTo = split("/",$rfl);
			$rfl	 	 = (substr($rfl,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
		}
        $rfl = removeMultipleSlashs($rfl);
        $rfl = removeLastSlash($rfl);
        setUserConfiguration('LOCALRESTOREFROM', $rfl);
        setUserConfiguration('LOCALRESTORESERVERROOT',$serverRoot);
        saveUserConfiguration() or retreat('failed_to_save_user_configuration');
    }

	if(!defined($rfl) or $rfl eq ""){
		$rfl        = getUserConfiguration('BACKUPLOCATION');
        $serverRoot = getUserConfiguration('SERVERROOT');
		if ($dedup eq 'on'){
			$rfl = (split('#', $rfl))[-1];
		} else {			
			my @backupTo = split("/",$rfl);
			$rfl	 	 = (substr($rfl,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
		}
		display(["\n",'as_per_your_backup_location_your','your_local_restore_from_device_is_set_to', " \"$rfl\". ", 'do_you_want_edit_this_y_or_n_?'],1);
		$answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	} elsif($rfl){
		display(["\n",'your_local_restore_from_device_is_set_to', " \"$rfl\". ", 'do_you_want_edit_this_y_or_n_?'],1);
		$answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	if (lc($answer) eq "y") {
		if ($dedup eq 'on') {
			getAvailableBucketsInMountPoint();
		} else {
			# if ($rfl ne ""){
				
			# } else {
				# display(['enter_your_local_restore_from_location_optional', ": "], 0);
			# }
			#display(['enter_your_local_restore_from_location_optional', ": "], 0);
			#my $bucketName = getUserChoice();
			my $bucketName = getAndValidate(["\n", 'enter_your_local_restore_from_location_optional',": "], "local_restore_from_location", 1);
			if($bucketName ne ""){
				display(['Setting up your local restore from location...'], 1);
				if(substr($bucketName, 0, 1) ne "/") {
					$bucketName = "/".$bucketName;
				}
				$rfl = $bucketName;
			}
			else
			{
				if($rfl eq ""){
					$rfl    = getUserConfiguration('BACKUPLOCATION');
                    $serverRoot = getUserConfiguration('SERVERROOT');
					if ($dedup eq 'on'){
						$rfl = (split('#', $rfl))[-1];
					} else {			
						my @backupTo = split("/",$rfl);
						$rfl	 	 = (substr($rfl,0,1) eq '/')? '/'.$backupTo[1]:'/'.$backupTo[0];
					}				
				}				
				display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\" ")],1);				
			}
			display(['your_local_restore_from_device_is_set_to',(" \"" . $rfl . "\" "),"\n"],1);

			$rfl = removeMultipleSlashs($rfl);
			$rfl = removeLastSlash($rfl);
			setUserConfiguration('LOCALRESTOREFROM', $rfl);
            setUserConfiguration('LOCALRESTORESERVERROOT',$serverRoot);
			saveUserConfiguration() or retreat('failed_to_save_user_configuration');
		}
	} else {
		$rfl = removeMultipleSlashs($rfl);
		$rfl = removeLastSlash($rfl);
		setUserConfiguration('LOCALRESTOREFROM', $rfl);
        setUserConfiguration('LOCALRESTORESERVERROOT',$serverRoot);
		saveUserConfiguration() or retreat('failed_to_save_user_configuration');	
	}
}

#****************************************************************************************************
# Function Name         : getAvailableBucketsInMountPoint
# Objective             : Get available buckets in current Mount Point
# Added By              : Senthil Pandian
#*****************************************************************************************************
sub getAvailableBucketsInMountPoint {
	my @devices;
	my $tableData 		= "";
	my $restoreHost 	= getUserConfiguration('LOCALRESTOREFROM');
	my $username		= getUsername();
	my $expressLocalDir = getCatfile($AppConfig::localMountPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   = getCatfile($expressLocalDir, $username);
	
	my $xmlFile = $localUserPath."/".$AppConfig::dbPathsXML;
	if(-f $xmlFile and !-z $xmlFile){
		my $data 	  = getFileContents($xmlFile);
		@devices = parseXMLContent($data,'dbpathinfo');
	} else {
		return 0;
	}
	#return @devices;
	my @columnNames = (['S.No.', 'Device Name', 'Device ID'], [8, 24, 24]);
	my $tableHeader = getTableHeader(@columnNames);
	display($tableHeader,0);
	my @columnHeaderInfo = ('s_no', 'nickname', 'deviceid');
	my $serialNumber = 1;

	for my $device (@devices) {
		for (my $i=0; $i < scalar(@columnHeaderInfo); $i++) {
			if ($columnHeaderInfo[$i] eq 's_no') {
				$tableData .= $serialNumber;
				$tableData .= (' ') x ($columnNames[1]->[$i] - length($serialNumber));
			}
			else {
				my $displayData = $device->{$columnHeaderInfo[$i]};

				if(($columnNames[1]->[$i] - length($displayData)) > 0){
					$tableData .= $displayData;
					$tableData .= (' ') x ($columnNames[1]->[$i] - length($displayData)) if ($columnHeaderInfo[$i] eq 'nick_name'||'os');
				}
				else {
					$tableData .= trimDeviceInfo($displayData,$columnNames[1]->[$i]) if($columnHeaderInfo[$i] eq 'nick_name'||'os');
					$tableData .= (' ') x 3;
				}
				$tableData .= (' ') x ($columnNames[1]->[$i] - length($displayData)) if ($columnHeaderInfo[$i] eq 's_no');
			}
		}
		$serialNumber = $serialNumber + 1;
		$tableData .= "\n";
	}
	display($tableData,1);
	display(['enter_the_serial_no_to_select_your' ,"Local Restore from location. "], 0);
	my $slno = getUserMenuChoice(scalar(@devices));
	if($slno){
		setUserConfiguration('LOCALRESTOREFROM',
		($AppConfig::deviceIDPrefix . $devices[$slno -1]{'deviceid'} . $AppConfig::deviceIDSuffix .
		"#" . $devices[$slno -1]{'nickname'}));
		setUserConfiguration('LOCALRESTORESERVERROOT',$devices[$slno -1]{'serverroot'});
		saveUserConfiguration() or retreat('failed_to_save_user_configuration');
		display([ "\n",'your_local_restore_from_device_is_set_to', (" \"" . $devices[$slno -1]{'nickname'} . "\"")]);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: checkAndCreateDBpathXMLfile
# Objective				: This method is used to create dbpaths.xml file if it not present or if bucket entry not present
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkAndCreateDBpathXMLfile
{
	unless(scalar(@{$_[1]})>0) {
		return 0;
	}
	my $xmlContent = '';
	my $needFile   = 0;
	my $dbPathsXMLPath = $_[0].'/'.$AppConfig::dbPathsXML;
	if(-e $dbPathsXMLPath and !-z $dbPathsXMLPath) {
		$xmlContent = getFileContents($dbPathsXMLPath);
		foreach my $backupLocation (@{$_[1]}) {
			if($xmlContent !~ /serverroot="$backupLocation"/) {
				$needFile = 1;
				last;
			}
		}
	} else {
		$needFile = 1;
	}

	if($needFile) {
		my @devices = fetchAllDevices();
		my %deviceList;
		#print Dumper(\@devices);
		foreach (@devices) {
			$deviceList{$_->{'server_root'}} = $_;
		}
		#print Dumper(\%deviceList);
		$xmlContent  = '<?xml version="1.0" encoding="utf-8"?>'."\n";
		$xmlContent .= '<dbpaths>'."\n";
		my $username = getUsername();
		foreach my $serverRoot (@{$_[1]}) {
			if($deviceList{$serverRoot}) {
				my $device_id = $deviceList{$serverRoot}->{'device_id'};
				my $nickName  = $deviceList{$serverRoot}->{'nick_name'};
				my $dbPath 	  = "/LDBNEW/$serverRoot/$username.ibenc";
				$xmlContent .= '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$device_id.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />'."\n";
			}
		}
		$xmlContent .= '</dbpaths>'."\n";
		#print $xmlContent;
		open XMLFILE, ">", $dbPathsXMLPath or (print "Unable to create file: $dbPathsXMLPath, Reason:$!" and die);
		print XMLFILE $xmlContent;
		close XMLFILE;
		chmod $AppConfig::filePermission, $dbPathsXMLPath;
	}
	return 1;
}


#*****************************************************************************************************
# Subroutine			: getUserBackupDirListFromMountPath
# Objective				: This method is used to get list of user's backup location directories from mount path
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getUserBackupDirListFromMountPath
{
	my $localUserPath     = $_[0];
	my @backupLocationDir = ();	
	if(-d $localUserPath) {
		if(opendir(DIR, $localUserPath)) {
			foreach my $dir (readdir(DIR))  {
				my $tempDir = $localUserPath.'/'.$dir;
				chomp($tempDir);
				if($dir =~ m/^$/) {
					next;
				}
				elsif($dir =~ m/^[\s\t]+$/) {
					next;
				}
				if ( $dir eq "." or $dir eq "..") {
					next;
				}
				elsif(!-d $tempDir){
					next;
				}
				elsif($dir =~ /LDBNEW/ or $dir =~ /dbpaths\.xml/){
					next;
				}
				push @backupLocationDir, $dir;
			}
		}
	}
	return @backupLocationDir;
}

#***********************************************************************************************************
# Subroutine Name         :	doRestoreOperation
# Objective               :	Performs the actual task of restoring files. It creates a child process which executes
#                           the restore command.
#							Creates an output thread which continuously monitors the temporary output file.
#							At the end of restore, it inspects the temporary error file if present.
#							It then deletes the temporary output file, temporary error file and the temporary
#							directory created by idevsutil binary.
# Added By                : Senthil Pandian
#************************************************************************************************************
sub doRestoreOperation
{
	my $parameters 	      = $_[0];
	my $silentRestoreFlag = $_[1];
	my $scheduleFlag      = $_[2];
	my $operationEngineId = $_[3];
	my $retry_failedfiles_index = $_[4];
	my $doRestoreOperationErrorFile = $AppConfig::jobRunningDir."/doRestoreError.txt_".$operationEngineId;
	
	my $pidPath        = $AppConfig::jobRunningDir."/".$AppConfig::pidFile;
	my $restoreUTFpath = $AppConfig::jobRunningDir.'/'.$AppConfig::utf8File."_".$operationEngineId;
	my $evsOutputFile  = $AppConfig::jobRunningDir.'/'.$AppConfig::evsOutputFile.'_'.$operationEngineId;
	my $evsErrorFile   = $AppConfig::jobRunningDir.'/'.$AppConfig::evsErrorFile.'_'.$operationEngineId;
	my $engineLockFile = $AppConfig::jobRunningDir."/".AppConfig::ENGINE_LOCKE_FILE;
	
	my @parameter_list = split(/\' \'/, $parameters, 3);
	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	if(!flock($startPidFileLock, LOCK_SH)){
		traceLog("Failed to lock engine file");
		return 0;
	}

	fileWrite($pidPath.'_evs_'.$operationEngineId, 1);
	open(my $engineFp, ">>", $pidPath.'_'.$operationEngineId) or return 0;

	if(!flock($engineFp, LOCK_EX)){
		display("Unable to lock \n");
		return 0;
	}
	my $username        = getUsername();
	my $expressLocalDir = getCatfile($AppConfig::localMountPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   = getCatfile($expressLocalDir, $username);
	my $dedup			= getUserConfiguration('DEDUP');
	my $restoreFrom     = getUserConfiguration('LOCALRESTOREFROM');
    my $defLocal	    = (getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE')?0:1;
	my $LocalRestoreFrom;

	if ($dedup eq 'on'){
		$restoreFrom      = getUserConfiguration('LOCALRESTORESERVERROOT');
		$LocalRestoreFrom = $localUserPath."/".$restoreFrom;
	} else {
		$LocalRestoreFrom = $localUserPath."/".$restoreFrom;			
	}
	$LocalRestoreFrom .= '/' if(substr($LocalRestoreFrom,-1,1) ne '/'); #Adding '/' at end if its not

	my $restoreLoc = getUserConfiguration('RESTORELOCATION');
	$restoreLoc   .= '/' if(substr($restoreLoc,-1,1) ne '/'); #Adding '/' at end if its not
	createUTF8File(['LOCALRESTORE',$restoreUTFpath],
				$parameter_list[2],
                $defLocal,
				$AppConfig::jobRunningDir."/",							
				$evsOutputFile,
				$evsErrorFile,
				$LocalRestoreFrom,
				$restoreLoc
				) or retreat('failed_to_create_utf8_file');
# traceLog("\n\n".getFileContents($restoreUTFpath)."\n\n");				
	my $restorePid = fork();
	if(!defined $restorePid) {
		$AppConfig::errStr = getStringConstant('cannot_fork_child')."\n";
		#return BACKUP_PID_FAIL;
		return 2;
	}

	if($restorePid == 0) {
		$AppConfig::pidOperationFlag = "EVS_process";
		if( -e $pidPath) {
			#exec($idevsutilCommandLine);
# traceLog("\n\n".getFileContents($restoreUTFpath)."\n\n");	
			my @responseData = runEVS('item',1);
# use Data::Dumper;
# traceLog("\n\n".Dumper(\@responseData)."\n\n");	
			if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
				if (open(ERRORFILE, ">> $AppConfig::errorFilePath"))
				{
					autoflush ERRORFILE;
					print ERRORFILE $AppConfig::errStr;
					close ERRORFILE;
					chmod $AppConfig::filePermission, $AppConfig::errorFilePath;
				}
				else {
					traceLog($LS{'failed_to_open_file'}."errorFilePath in doBackupOperation:".$AppConfig::errorFilePath.", Reason:$! \n");
				}
			}

			if(open OFH, ">>", $evsOutputFile) {
				print OFH "\nCHILD_PROCESS_COMPLETED\n";
				close OFH;
				chmod $AppConfig::filePermission, $evsOutputFile;
			}
			else {
				$AppConfig::errStr = getStringConstant('failed_to_open_file').": $AppConfig::outputFilePath in doBackupOperation. Reason: $!";
				display($AppConfig::errStr);
				traceLog($AppConfig::errStr);
				return 0;
			}
		}
		exit 1;
	}

	$AppConfig::pidOperationFlag = "child_process";
	if( !-e $pidPath) {
		exit 1;
	}
	
	my $currentDir = getAppPath();
	my $workingDir = $currentDir;
	$workingDir =~ s/\'/\'\\''/g;
	my $tmpoutputFilePath = $AppConfig::outputFilePath;
	$tmpoutputFilePath =~ s/\'/\'\\''/g;
	my $TmpBackupSetFile = $parameter_list[2]."_org";
	$TmpBackupSetFile =~ s/\'/\'\\''/g;
	my $TmpSource = $parameter_list[0];
	$TmpSource =~ s/\'/\'\\''/g;
	my $tmp_jobRunningDir = $AppConfig::jobRunningDir;
	$tmp_jobRunningDir =~ s/\'/\'\\''/g;
	
	my $fileChildProcessPath = $currentDir.'/'.$AppConfig::idriveScripts{'operations'};

	my $tmpRestoreHost = $restoreFrom;
	$tmpRestoreHost =~ s/\'/\'\\''/g;
	#$fileChildProcessPath = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
	my $tmpRestoreLoc = $restoreLoc;
	$tmpRestoreLoc =~ s/\'/\'\\''/g;
	my @param = join ("\n",('LOCAL_RESTORE_OPERATION',$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$AppConfig::progressSizeOp,$tmpRestoreHost,$tmpRestoreLoc,$silentRestoreFlag,'',$scheduleFlag));
	#my @param = join ("\n",('LOCAL_RESTORE_OPERATION',$tmpOpFilePath,$tmpRstSetFile,$parameter_list[1],$tmpSrc,$progressSizeOp,$tmpRestoreHost,$tmpRestoreLoc,$silentFlag,'',$scheduleFlag));
	
	writeParamToFile("$tmp_jobRunningDir/$AppConfig::operationsfile"."_".$operationEngineId,@param);
	my $perlPath = getPerlBinaryPath();
	# traceLog("cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$username\' \'$operationEngineId\' \'$retry_failedfiles_index\'");
	{
		my $cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$username\' \'$operationEngineId\' \'$retry_failedfiles_index\'";
		system($cmd);
	}
	# return 1;
	waitpid($restorePid,0);
	unlink($pidPath.'_evs_'.$operationEngineId);
	waitForChildProcess($pidPath.'_proc_'.$operationEngineId);
	unlink($pidPath.'_'.$operationEngineId);

	my $isServerAddr = updateServerAddr();
	return 0 if(!$isServerAddr);

	# unlink($parameter_list[2]);
	unlink($evsOutputFile);
	flock($startPidFileLock, LOCK_UN);
	flock($engineFp, LOCK_UN);

	return 0 if(-e $AppConfig::errorFilePath && -s $AppConfig::errorFilePath);
	return 1; #Success
}

#*****************************************************************************************************
# Subroutine	: getDBDataWithType
# In Param		: file/folder list(array)
# Out Param		: list(Hash)
# Objective		: Get existing file/folder names with type from database.
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub getDBDataWithType{
	my %list;
	my $restoreFrom     = getUserConfiguration('LOCALRESTOREFROM');
	my $dedup			= getUserConfiguration('DEDUP');
	my $tempRestoreFrom = $restoreFrom;
    my $serverRoot      = '';

	if($dedup eq 'on'){
		$restoreFrom     = getUserConfiguration('LOCALRESTORESERVERROOT');
        $serverRoot      = $restoreFrom;
		$tempRestoreFrom = "/".$restoreFrom;
	} elsif(substr($restoreFrom, 0, 1) ne "/"){
		$tempRestoreFrom = "/".$restoreFrom;
	}
    
    my $databaseLB = getExpressDBPath(getUserConfiguration('LOCALRESTOREMOUNTPOINT'),$serverRoot);
	if(!-e $databaseLB){
		retreat('No database');
	}
	Sqlite::initiateExpressDBoperation($databaseLB);
	foreach(@{$_[0]}) {
		chomp($_);
		$_ =~ s/^\s+//;
		if($_ eq "") {
			next;
		}
		my $rItem = "";
		my $item  = $_;
		if(substr($item, 0, 1) ne "/") {
			$rItem = $tempRestoreFrom."/".$item;
		} else {
			$rItem = $tempRestoreFrom.$item;
		}

		my $res = Sqlite::checkItemInExpressDB($rItem);
		if($res){
			if(substr($res,-1,1) eq '/'){
				$item = $item."/" unless(substr($item,-1,1) eq '/');
				$list{$item}{'type'} = 'd';
			} else {
				$list{$item}{'type'} = 'f';
			}
		} else {
			display(["Skipped [$item]. ", "Reason",'file_folder_not_found']);
			$skippedItem = 1;
		}
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine		: checkAndStartDBReIndex
# Objective			: Check and start DB ReIndex if DB not found/corrupted.
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub checkAndStartDBReIndex{
    my $mountedPath = $_[0];
    #Check & start DB-ReIndex Process - Start
	$mountedPath = $AppConfig::defaultMountPath unless( defined($mountedPath) or $mountedPath);
    my $username        = getUsername();
	my $expressLocalDir = getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   = getCatfile($expressLocalDir, $username);
	$AppConfig::expressLocalDir = $expressLocalDir;

	my $dbPathsXML	   = getCatfile($localUserPath, $AppConfig::dbPathsXML);
	my $ldbNewDirPath  = getCatfile($localUserPath, $AppConfig::ldbNew);
    my $dedup  	       = getUserConfiguration('DEDUP');
    my $serverRoot     = ($dedup eq 'on')?getUserConfiguration('SERVERROOT'):getUserConfiguration('BACKUPLOCATION');
	   $serverRoot     = ($dedup eq 'on')?getUserConfiguration('LOCALRESTORESERVERROOT'):getUserConfiguration('LOCALRESTOREFROM') unless(defined($_[1]));
    my $databaseLB     = getExpressDBPath($mountedPath,$serverRoot);
    my $localDataPath  = getCatfile($localUserPath, $serverRoot);

	if(!-d $ldbNewDirPath or ($dedup eq 'on' and !-f $dbPathsXML) or !-f $databaseLB or !Sqlite::createExpressDB($databaseLB, 1)){
        if(-d $localDataPath){
            startDBReIndex($mountedPath);
        }
        elsif(defined($_[1])) {
            if($dedup eq 'on') {
                my @backupLocationDir = ($serverRoot);
                checkAndCreateDBpathXMLfile($localUserPath, \@backupLocationDir);
            }
            Sqlite::createExpressDB($databaseLB, 1);
        }
	}
	if($dedup eq 'on' and !-e $dbPathsXML) {
		retreat(['mount_point_doesnt_have_user_data',"\n"]) unless($AppConfig::callerEnv eq 'BACKGROUND');
		return (0,'mount_point_doesnt_have_user_data');
	}
    #Check & start DB-ReIndex Process - End
	return (1,'');
}

#*****************************************************************************************************
# Subroutine/Function   : checkAndOpenUserDB
# In Param    : MOUNT PATH
# Out Param   : Boolean
# Objective	  : This function will validate user based DB in mount path and open the DB handle
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub checkAndOpenUserDB {
	loadUsername();
	my $errorKey = loadUserConfiguration();
	if($errorKey > 1){
		traceLog(['checkAndOpenUserDB:',$AppConfig::errorDetails{$errorKey}]);
		return 0;
	}
		
	my $username    = getUsername();
	my $dedup  	    = getUserConfiguration('DEDUP');
	my $mountedPath = (defined($_[0]) and $_[0])?$_[0]:getUserConfiguration('LOCALMOUNTPOINT');
	$AppConfig::localMountPath	= $mountedPath;

	my $expressLocalDir = getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   = getCatfile($expressLocalDir, $username);
	my $ldbNewDirPath	= getCatfile($localUserPath, $AppConfig::ldbNew);
	my $dbPathsXML	    = getCatfile($localUserPath, $AppConfig::dbPathsXML);
    $AppConfig::expressLocalDir = $expressLocalDir;

	my $serverRoot   = ($dedup eq 'on')?getUserConfiguration('SERVERROOT'):getUserConfiguration('BACKUPLOCATION');
	my $dbpath       = getExpressDBPath($AppConfig::localMountPath, $serverRoot);
	my $backedUpData = getCatfile($localUserPath, $serverRoot);

    #Verify DB & start DB ReIndex
	my $dbReindexDir = getUsersInternalDirPath('dbreindex');
	my $dbReindexPid = $dbReindexDir."/".$AppConfig::pidFile;

	if(!-d $ldbNewDirPath or ($dedup eq 'on' and !-e $dbPathsXML) or (-d $backedUpData and !-f $dbpath) or -f $dbReindexPid){
		$AppConfig::callerEnv = 'BACKGROUND';
		startDBReIndex($mountedPath);
	}
	if($dedup eq 'on' and !-e $dbPathsXML) {
		traceLog(['checkAndOpenUserDB:','mount_point_doesnt_have_user_data',"\n"]);
		return 0;
	}		
	unless(-f $dbpath) {
		traceLog(['checkAndOpenUserDB:','Database not found',"\n"]);
		return 0;		
	}

	my $dbfstate = Sqlite::createExpressDB($dbpath, 1);
	unless($dbfstate) {
		traceLog(['getLocalStorageUsed:','Failed to open database',"\n"]);
		return 0;
	}

	Sqlite::initiateExpressDBoperation($dbpath);

	return 1;
}

#*****************************************************************************************************
# Subroutine/Function   : getLocalStorageUsed 
# In Param    : MOUNT PATH
# Out Param   : USED SPACE
# Objective	  : This function will get local storage used
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub getLocalStorageUsed {
	unless(checkAndOpenUserDB($_[0])) {
		traceLog('getLocalStorageUsed: checkAndOpenUserDB failed');
		return 0;
	}
	my $storageUsed = Sqlite::getBucketSize();
	# $storageUsed = getHumanReadableSizes($storageUsed);
	return $storageUsed;
}

#*****************************************************************************************************
# Subroutine/Function   : getLocalRestoreItems
# In Param    : MOUNT PATH, DIRPATH, OUT_PARAMS, OUTPUT_FILE, FOLDER_LIST, SPLIT, START_INDEX, COUNT
# Out Param   : ITEMSLIST
# Objective	  : This function will fetch & return local restore list
# Added By	  : Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub getLocalRestoreItems {
	my $mountPath  = $_[0];
	my $dirPath    = $_[1];
	my $outParams  = $_[2];
	my $outputFile = $_[4];
	my $folderList = (defined($_[3]) and $_[3] =~ /^\d+$/)?$_[3]:0;
	my $split      = (defined($_[5]) and $_[5] =~ /^\d+$/)?$_[5]:0;
	my $startIndex = (defined($_[6]) and $_[6] =~ /^\d+$/)?$_[6]:0;
	my $itemsCount = (defined($_[7]) and $_[7] =~ /^\d+$/)?$_[7]:'';

	unless(reftype(\$outParams) eq 'SCALAR'){
		my $invalidFields = '';
		foreach (@{$outParams}) {
			next unless($_);
			$invalidFields .= $_.", " unless(exists($AppConfig::dbFields{$_}));				
		}

		if($invalidFields) {
			Chomp(\$invalidFields);
			chop($invalidFields);
			return (0, 'Invalid fields passed: '.$invalidFields);
		}
	}
	elsif($outParams and !exists($AppConfig::dbFields{$outParams})) {
		return (0, 'Invalid field passed: '.$outParams);
	}

	if($split and (!defined($outputFile) or $outputFile eq '')) {
		traceLog('getLocalRestoreItems: output file name is missing');
		return (0, 'output file name is missing');
	}

	my $userProfilePath = getCatfile(getUserProfilePath(), '');
	if(defined($outputFile) and $outputFile ne '' and $outputFile !~ /^$userProfilePath/) {
		traceLog('getLocalRestoreItems: output file doesn\'t belongs to user profile path');
		return (0, 'output file doesn\'t belongs to user profile path');
	}

	my $localRestoreJobDir = getJobsPath('localrestore');
	createDir($localRestoreJobDir, 1) unless(-d $localRestoreJobDir);

	my $pidPath	= getCatfile($localRestoreJobDir, $AppConfig::localrestoreListPid);
	if (isFileLocked($pidPath)) {
		traceLog('local_restore_list_running');
		return (0, 'local_restore_list_running');
	}

	my $lockStatus = fileLock($pidPath);
	if($lockStatus) {
		traceLog([$lockStatus.'_file_lock_status', ": ", $pidPath]);
		return (0, $lockStatus.'_file_lock_status');
	}

	setUserConfiguration('LOCALRESTOREMOUNTPOINT', $mountPath);
	saveUserConfiguration() or traceLog('failed_to_save_user_configuration');	
	my($schemaStat, $dbPath) = isExpressDBschemaChanged('localrestore');
	if($schemaStat) {
		traceLog('ExpressDBschemaChanged. Renaming DB '.$dbPath);
		system("mv '$dbPath' '$dbPath'"."_bak") if(-f $dbPath);
	};
	unless(checkAndOpenUserDB($mountPath)) {
		traceLog('getLocalRestoreItems: checkAndOpenUserDB failed');
		return (0, 'getLocalRestoreItems: checkAndOpenUserDB failed');
	}

	# Remove the existing output files
	removeItems($outputFile."*") if(defined($outputFile));

	my $dedup  	   = getUserConfiguration('DEDUP');
	my $serverRoot = ($dedup eq 'on')?getUserConfiguration('SERVERROOT'):getUserConfiguration('BACKUPLOCATION');
	$dirPath  = getCatfile($serverRoot, $dirPath);
	$dirPath  = "/".$dirPath if(substr($dirPath,0,1) ne '/');
	$dirPath .= '/' if(substr($dirPath,-1,1) ne '/');
	$dirPath  = removeMultipleSlashs($dirPath);

	my ($dirList, $fileList) = Sqlite::getExpressDataList($dirPath, $outParams, $outputFile, $folderList, $split, $startIndex, $itemsCount);

	my %items = ();
	if(!$split and defined($outputFile) and $outputFile ne '') {
		if($folderList) {
			fileWrite($outputFile, JSON::to_json($fileList));
			fileWrite($outputFile.$AppConfig::localFolderList, JSON::to_json($dirList));
		} else {
			fileWrite($outputFile, JSON::to_json($fileList));
		}
	}
	# else {
# print "ELSE:\n\n";
		# %items = (%{$dirList}, %{$fileList});
# print Dumper(\%items);
		# return JSON::to_json(\%items);
	# }
	removeItems($pidPath);
	return (1, [@$dirList, @$fileList]);
}

#*****************************************************************************************************
# Subroutine	: isExpressDBschemaChanged
# In Param		: jobtype
# Out Param		: Boolean, dbfile(path)
# Objective		: Check whether table schema changed or not
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub isExpressDBschemaChanged {
	my $mountedPath = getUserConfiguration('LOCALMOUNTPOINT');
	my $expressLocalDBMapPath = "/".getUserConfiguration('SERVERROOT');
	if($_[0] eq 'localrestore') {
		$mountedPath = getUserConfiguration('LOCALRESTOREMOUNTPOINT');
		$expressLocalDBMapPath = "/".getUserConfiguration('LOCALRESTORESERVERROOT');
	}

	my $dbfile	= getExpressDBPath($mountedPath, $expressLocalDBMapPath);
	return (0, '') unless(-f $dbfile);

	my ($dbfstate, $scanfile) = Sqlite::createExpressDB($dbfile, 0);
	return (0, '') unless($dbfstate);

	Sqlite::initiateExpressDBoperation();
	my $rsc = Sqlite::checkExpressDBschema();
	Sqlite::disconnectExpressDB();
	return ($rsc, $dbfile);
}

#********************************************************************************
# Subroutine	: createVersionRestoreJson
# In Param		: operation, itemsList, endDate
# Out Param		: 
# Objective		: This subroutine to create the version restoreset file for file version/folder version/snapshot
# Added By		: Senthil Pandian
# Modified By	: 
#********************************************************************************
sub createVersionRestoreJson {
	my $operation = $_[0];
	my $itemsList = $_[1];
	my $endDate   = $_[2];
	my %restoreSet = ('opType'=>$operation,'items'=>{%{$itemsList}});
	
	if($operation eq 'snapshot') {
		$restoreSet{'endDate'} = $endDate;
	}
	
	my $restoresetFilePath = getCatfile(getJobsPath('restore'), $AppConfig::versionRestoreFile);
	fileWrite($restoresetFilePath, JSON::to_json(\%restoreSet));
	chmod $AppConfig::filePermission, $restoresetFilePath; 
}

#****************************************************************************************************
# Subroutine Name         : displayFolderVersionProgressBar.
# Objective               : This subroutine contains the logic to display the filename and the progress
#                           bar in the terminal window.
# Added By                : Senthil Pandian
# Modified By             : 
#*****************************************************************************************************/
sub displayFolderVersionProgressBar {
	return if($AppConfig::callerEnv eq 'BACKGROUND');
	my ($progressDetails, $individualProgressDetails) = getProgressDetails($_[0],$_[2]);
	my @progressDetails = @$progressDetails;
	my %individualProgressDetails = %{$individualProgressDetails};

	my $isDedup = getUserConfiguration('DEDUP');
	return '' if (scalar(@progressDetails) == 0);

	$SIG{WINCH} = \&changeSizeVal;

	my ($progress, $cellSize, $totalSizeUnit, $moreProgress) = ('')x4;
	my ($remainingFile, $remainingTime) = ('NA') x 2;

	my $fullHeader   = $LS{lc($AppConfig::jobType . '_progress')};
	my $incrFileSize = $progressDetails[1];
	my $TotalSize    = $progressDetails[2];
	my $kbps         = $progressDetails[3];
	my $totalTransferredFiles = $progressDetails[6];

	my ($percent, $totalFileCount) = (0) x 2;
	$TotalSize = $_[1] if (defined $_[1] and $_[1] > 0);
	$TotalSize = 0 if ($TotalSize eq $LS{'calculating'} or $TotalSize =~ /calculating/i);

	my $spAce1 = " "x(38/$AppConfig::progressSizeOp);
    my $fCount = '[ '.$LS{'calculating'}.' ]';

	if ($TotalSize != 0) {
		my $jobRunningDir = (fileparse($_[0]))[1];
		my $totalFileCountFile	= $jobRunningDir.'/'.$AppConfig::totalFileCountFile;
		traceLog("totalFileCountFile:$totalFileCountFile\n\n");
		if(-f $totalFileCountFile and !-z _) {
			my %countHash = %{JSON::from_json(getFileContents($totalFileCountFile))};
			$totalFileCount = (exists($countHash{$AppConfig::totalFileKey}))?$countHash{$AppConfig::totalFileKey}:0;
			traceLog("totalFileCount:$totalFileCount\n\n");
			traceLog("totalTransferredFiles:$totalTransferredFiles\n\n");
			$remainingFile = ($totalFileCount - $totalTransferredFiles);
			# traceLog("remainingFile1:$remainingFile\n\n");
			$remainingFile = 0 if($remainingFile<0);
			# traceLog("remainingFile2:$remainingFile\n\n");

            $fCount = $LS{'restored_count'};
            $fCount =~ s/<CC>/$totalTransferredFiles/;
            $fCount =~ s/<TC>/$totalFileCount/;
		}
=beg
		$percent = int($incrFileSize/$TotalSize*100);
		$percent = 100	if ($percent > 100);
		$progress = "|"x($percent/$AppConfig::progressSizeOp);
		my $cellCount = (100-$percent)/$AppConfig::progressSizeOp;
		$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
		$cellSize = " " x $cellCount;
=cut
        $percent = int($totalTransferredFiles/$totalFileCount*100);
		$percent = 100	if ($percent > 100);
		$progress = "|"x($percent/$AppConfig::progressSizeOp);
		my $cellCount = (100-$percent)/$AppConfig::progressSizeOp;
		$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
		$cellSize = " " x $cellCount;
        $totalSizeUnit = convertFileSize($TotalSize);
		my $seconds = ($TotalSize - $incrFileSize);
		$seconds = ($seconds/$kbps) if($kbps);

		# As per NAS: Need to display maximum time as 150 days only. 150*24*60*60 = 12960000
		my $maxtime = 12960000;
		if($seconds > $maxtime) {
			$remainingTime = convertSecondsToReadableTime(ceil($maxtime));
		} else {
			$remainingTime = convertSecondsToReadableTime(ceil($seconds));
		}

		$remainingTime = '0s' if(!$remainingTime || $remainingTime =~ /-/);
	}
	else {
		#$totalSizeUnit = convertFileSize($TotalSize);
		$totalFileCount = $LS{'calculating'};
		$cellSize = " " x (100/$AppConfig::progressSizeOp);
		$remainingFile = 'NA';
		$remainingTime = 'NA';
	}

	my $fileSizeUnit = convertFileSize($incrFileSize);
	#$kbps =~ s/\s+//; Commented by Senthil : 26-Sep-2018
	$percent = sprintf "%4s", "$percent%";
	my $spAce = " " x 6;
	my $boundary = "-"x(100/$AppConfig::progressSizeOp);

	return if ($progressDetails[0] eq '');

	if(scalar(keys %individualProgressDetails) and (defined($_[3]) and $_[3] eq 'more')) {
        my $space = (100/$AppConfig::progressSizeOp) + 7;
		for(my $i=1;$i<=$AppConfig::totalEngineBackup;$i++) {
			next unless($individualProgressDetails{$i});
			$moreProgress .= $LS{'engine'}." $i: ";
			$moreProgress .= $individualProgressDetails{$i}{'data'}."\n";
			my $per = $individualProgressDetails{$i}{'per'};
			$per =~ s/%//;
			chomp($per);

            my $rate = $individualProgressDetails{$i}{'rate'};
            $rate = convertFileSize($rate)."/s";
            $rate =~ s/bytes/B/;
            $rate = sprintf "%10s", $rate;

            my $size = $individualProgressDetails{$i}{'size'};
            $size =~ s/bytes/B/;
            $size = sprintf "%10s", $size;

            my $rateBar     = "[".$rate."][";
            my $fileSizeBar = "][".$size."]";

            my $progressBar = "";
            $per = 100 - ($AppConfig::progressSizeOp * 23) if($per>80);
			$progressBar    = "-"x($per/$AppConfig::progressSizeOp);
            $progressBar   .= $individualProgressDetails{$i}{'per'};
            my $engBarLen   = (length($progressBar) + length($rateBar) + length($fileSizeBar));
            $progressBar    = colorScreenOutput($progressBar, undef, 'green', 'black');
            $progressBar   .= " "x($space - $engBarLen) if($space > $engBarLen);
			$moreProgress  .= $rateBar.$progressBar.$fileSizeBar."\n\n";
		}
	} elsif($_[4] and $AppConfig::progressSizeOp == 2 and $AppConfig::machineOS ne 'freebsd'){
		# traceLog("lessPressed:".$_[4]);
		system(updateLocaleCmd("tput rc"));
		system(updateLocaleCmd("tput ed"));
		clearProgressScreen();
	}

	my $fileDetailRow = "\[$progressDetails[0]\] \[$progressDetails[4]\] \[$progressDetails[5]\]";
    if($_[3] eq 'more'){
        $fileDetailRow = "\n".$LS{'cumulative_progress'};
    }
	my $strLen     = length $fileDetailRow;
	my $emptySpaceDetail = " ";
	$emptySpaceDetail = " "x($latestCulmn-$strLen) if ($latestCulmn>$strLen);
	$kbps = convertFileSize($kbps);
    # $totalSizeUnit = $fileSizeUnit unless($remainingFile);
	# my $sizeRowDetail = "$spAce1\[$fileSizeUnit of $totalSizeUnit] [$kbps/s]";
    $fCount = $spAce1.$fCount;
	$strLen  = length $fCount;
	my $emptySizeRowDetail = " ";
	$emptySizeRowDetail = " "x($latestCulmn-$strLen) if ($latestCulmn>$strLen);

	# my $progressReturnData = $moreProgress.$fullHeader;
    my $progressReturnData = $fullHeader.$moreProgress;
	$progressReturnData .=  "$fileDetailRow $emptySpaceDetail\n";
    $progressReturnData .=  "\n" if($_[3] ne 'more');
	$progressReturnData .= "$spAce$boundary\n";
	$progressReturnData .= "$percent [";
	$progressReturnData .= $progress.$cellSize;
	$progressReturnData .= "]\n";
	$progressReturnData .= "$spAce$boundary\n";
	$progressReturnData .= "$fCount $emptySizeRowDetail\n";

	my $space = 70;
	$space    = 56 if($AppConfig::progressSizeOp>1);

    my $restoreHost  = ($isDedup eq 'on')?getUserConfiguration('RESTOREFROM'):getUserConfiguration('LOCALRESTOREFROM');
    my $restoreLocation  = getUserConfiguration('RESTORELOCATION');
    my $restoreFromLocation = $restoreHost;
    if ($isDedup eq 'on') {
        $restoreFromLocation = (split('#',$restoreHost))[1] if ($restoreHost =~ /#/);
    }
    my $restoreFromLocationStr = $LS{'restore_from_location_progress'}." : ".$restoreFromLocation.(' ' x 2);
    my $restoreLocationStr     = $LS{'restore_location_progress'}." : ".$restoreLocation.(' ' x 2);
    $spAce1 = " "x($space - length($restoreFromLocationStr));
    $progressReturnData .= $lineFeed.$restoreFromLocationStr.$spAce1.$restoreLocationStr.$lineFeed;
    # my $fCount = $LS{'restored_count'};
    # $fCount =~ s/<CC>/$totalTransferredFiles/;
    # $fCount =~ s/<TC>/$remainingFile/;
    # $fCount =~ s/:/     :/;
    my $sizeRowDetail = $LS{'transferred_size'}." : $fileSizeUnit [Rate: $kbps/s]";
    my $remainingTimeStr = $LS{'estimated_time_left'}.(' ' x 12)." : ".$remainingTime;
    my $displayMoreLess = $LS{'display'}.(' ' x 14)." : ".(($_[3] eq 'more')?$LS{'press_to_collapse'}:$LS{'press_to_extend'});
    $spAce1 = " "x($space - length($remainingTimeStr));
    $progressReturnData .= $remainingTimeStr.$spAce1.$sizeRowDetail.$lineFeed;
    $progressReturnData .= $displayMoreLess.$lineFeed;

	# $progressReturnData .= $lineFeed.getStringConstant('note_completed_remaining').$lineFeed;
	displayProgress($progressReturnData, 20);
}

1;
