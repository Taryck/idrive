#*****************************************************************************************************
# Dashboard client service script
#
# Created By : Yogesh Kumar @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#
# IMPORTANT  : Please do not run this script manually. Run dashboard using account_setting.pl
#*****************************************************************************************************

package DashboardClient;
use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Idrivelib;
use Sys::Hostname;
use POSIX ":sys_wait_h";
use IO::Socket;
use Scalar::Util qw(reftype);
use POSIX;
use Data::Dumper;

use Common qw(getUserConfiguration setUserConfiguration saveUserConfiguration getUsername getServicePath getParentRemoteManageIP getRemoteManageIP getRemoteAccessToken getMachineUser getCatfile getUserProfilePath loadNotifications setNotification saveNotifications loadNS getNS saveNS deleteNS getFileContents);
use AppConfig;

use JSON qw(from_json to_json);
use PropSchema;
use IO::Zlib;
use MIME::Base64;
use File::stat;
use WWW::Curl;
use WWW::Curl::Easy;
use Encode qw(encode decode);
use Fcntl qw(:flock);

#Common::checkAndAvoidExecution($ARGV[0]);

#my @browsers;   # Assign forked pid's for watching browser activities.
my $dashboardPID;
my @systemids;
my @activities;   # Assign dashboard activity pid's.
my @progressPIDs; # Assign all progress pid's.
my @others;

my $selfPIDFile;
my $at;

#init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: Config and start the dashboard service
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub init {
	$0 = 'IDrive:dashboard:HT';

	$dashboardPID = sprintf("%d%d", getppid(), $$);

	$AppConfig::callerEnv = 'BACKGROUND';
	$AppConfig::traceLogFile = 'dashboard.log';
	$AppConfig::displayHeader = 0;


	Common::loadAppPath();
	exit(1) unless Common::loadServicePath();

	$selfPIDFile = getCatfile(getServicePath(), $AppConfig::userProfilePath, $AppConfig::mcUser);
	exit(1) unless (-d $selfPIDFile);

	$selfPIDFile = getCatfile($selfPIDFile, 'dashboard.pid');

	my $firstTime = 1;
	my $selfPID;
	my $retryAttempts = 1;
	while(1) {
		$selfPID = (-f $selfPIDFile and getFileContents($selfPIDFile)) || -1;
		end() if ($$ != $selfPID);

		if (-f Common::getCatfile(Common::getAppPath(), 'debug.enable')) {
			unless ($AppConfig::debug) {
				$AppConfig::debug = 1;
				Common::traceLog('enabling debug mode');
			}
		}
		elsif ($AppConfig::debug) {
			$AppConfig::debug = 0;
			Common::traceLog('disabling debug mode');
		}

		unless (Common::loadServicePath() and Common::loadUsername()) {
			Common::traceLog('failed to load service path/username');
			stopDashboardRoutines();
			sleep(3);
			next;
		}

		if ($Idrivelib::VERSION ne $AppConfig::staticPerlVersion) {
			Common::traceLog('Dashboard version mismatch, please update to latest');
			unlink($selfPIDFile);
			exit 1;
		}

		unless (Common::loadUserConfiguration() == 1) {
			Common::traceLog('failed to load userconfig');
			stopDashboardRoutines();
			sleep(3);
			next;
		}

		if (getUserConfiguration('RMWS') eq 'yes') {
			Common::traceLog('Switch to RMWS');
			last;
		}

		if (getUserConfiguration('UPTIME') eq '') {
			my $uptimeCmd = Common::updateLocaleCmd('who -b');
			my $uptime = `$uptimeCmd`;
			chomp($uptime);
			$uptime =~ s/system boot//;
			$uptime =~ s/^\s+//;
			setUserConfiguration('UPTIME', $uptime);
			saveUserConfiguration(0);
		}
		elsif ($firstTime and (getUserConfiguration('DEDUP') eq 'on')) {
			my $uptimeCmd = Common::updateLocaleCmd('who -b');
			my $uptime = `$uptimeCmd`;
			chomp($uptime);
			$uptime =~ s/system boot//;
			$uptime =~ s/^\s+//;
			if (getUserConfiguration('UPTIME') ne $uptime) {
				my $uie = sprintf("date -d'%s' +%%s", $uptime);
				$uie = Common::updateLocaleCmd($uie);
				$uie = `$uie`;
				chomp($uie);
				if ((time() - $uie) >= 604800) {
					my @devices = Common::fetchAllDevices();
					unless (Common::findMyDevice(\@devices)) {
						Common::traceLog('backup_location_is_adopted_by_another_machine');
						setUserConfiguration('BACKUPLOCATION', '');
						Common::loadCrontab();
						Common::setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
						Common::saveCrontab(0);
						end();
					}
				}

				setUserConfiguration('UPTIME', $uptime);
				saveUserConfiguration(0, 1);
				my $cmd = sprintf("%s %s 1 0", $AppConfig::perlBin, Common::getScript('logout', 1));
				$cmd = Common::updateLocaleCmd($cmd);
				`$cmd`;
			}
		}

		my $today = (localtime())[3];
		my %data  = ();

		unless (getRemoteManageIP()) {
debug('notify update remote manage ip ' . __LINE__);
			%data = (
				'content' => {
					'channel' => 'update_remote_manage_ip',
					'notification_value' => ''
				}
			);
			my $ipStatus = startActivity(\%data, undef, 1);
			if ($ipStatus == 1) {
				Common::traceLog('Updated remote manage ip, re-loading dashboard');
				stopDashboardRoutines();
				next;
			}
			else {
				Common::traceLog('Failed to load remote manage ip');
				end();
			}
		}

		Common::traceLog('initDashboardRoutines');

		unless (loadAccessToken()) {
			Common::traceLog('failed to load access token');
			if ($retryAttempts < 5) {
				$retryAttempts += 1;
				sleep(60);
				next;
			}
			else {
				stopDashboardRoutines();
				end();
			}
		}

		unless (register()) {
			Common::traceLog('failed to register this machine');
			stopDashboardRoutines();
			sleep(3);
			next;
		}

		unless(loadNS()) {
			Common::traceLog('Failed to load notifications');
			stopDashboardRoutines();
			sleep(3);
			next;
		}

		if (getNS('update_device_info')) {
			%data = (
				'content' => {
					'channel' => 'update_device_info',
					'notification_value' => getNS('update_device_info')
				}
			);
			if (startActivity(\%data, undef, 1) > 0) {
				deleteNS('get_backupset_content');
				deleteNS('get_localbackupset_content');
				deleteNS('get_scheduler');
				deleteNS('get_user_settings');
				deleteNS('get_settings');
				deleteNS('update_device_info');
			}
		}

		Common::fileWrite2(getCatfile(getUserProfilePath(), 'stage.txt'), '0');

		Common::fileWrite2(getCatfile(getUserProfilePath(), 'browsers.txt'), '0');

		updateSystemIsAlive();

		if (getDDAStatus()) {
			%data = (
				'content' => {
					'channel' => 'update_acc_status',
					'notification_value' => ''
				}
			);
			startActivity(\%data, undef, 1);
			last if (getUserConfiguration('DDA'));
		}
		elsif (getUserConfiguration('DDA')) {
			stopDashboardRoutines();
			Common::traceLog('service stopping. DDA is enabled.');
			last;
		}

		unless (fetchPropSettings()) {
			Common::traceLog('failed to fetch prop settings');
			stopDashboardRoutines();
			sleep(3);
			next;
		}
		watchDeltaPropSettings();
		watchDashboardLoginActivity();
		$firstTime = 0 if ($firstTime);

		my $sc = 0;
		my $pushNotifications;
		my $uname = getUsername();
		my ($startTime, $timeDiff);
		while(scalar @systemids == 3) {
debug('All system ps OK. c: ' . scalar @systemids);
			$startTime = time();
			$selfPID = (-f $selfPIDFile and getFileContents($selfPIDFile)) || -1;
			if ($$ != $selfPID) {
				end();
				updateSystemIsOffline($uname);
			}

			$today = (localtime())[3];
			$pushNotifications = 0;

			if (open(my $s, '<', getCatfile(getUserProfilePath(), 'stage.txt'))) {
				$sc = <$s> || 0;
				chomp($sc);
				close($s);
			}
debug("stage $sc " . __LINE__);

			Common::killPIDs(\@progressPIDs, 0);

			if (getNS('update_device_info')) {
debug('notify device info change ' . __LINE__);
				%data = (
					'content' => {
						'channel' => 'update_device_info',
						'notification_value' => getNS('update_device_info')
					}
				);
				if (startActivity(\%data, undef, 1) > 0) {
					deleteNS('get_backupset_content');
					deleteNS('get_localbackupset_content');
					deleteNS('get_scheduler');
					deleteNS('get_user_settings');
					deleteNS('get_settings');
				}
			}

# TODO: Fix
#			if (getNS('update_remote_manage_ip') ne $today) {
#debug('notify update remote manage ip ' . __LINE__);
#				%data = (
#					'content' => {
#						'channel' => 'update_remote_manage_ip',
#						'notification_value' => ''
#					}
#				);
#				my $ipStatus = startActivity(\%data, undef, 1);
#				if ($ipStatus > 0) {
#					loadNotifications() and setNotification('update_remote_manage_ip', "$today") and saveNotifications();
#					$notifications{'update_remote_manage_ip'} = "$today";
#					if ($ipStatus == 1) {
#						stopDashboardRoutines();
#						last;
#					}
#				}
#				else {
#					$notifications{'update_remote_manage_ip'} = Common::getNotifications('update_remote_manage_ip');
#				}
#			}

			if (syncUpdates()) {
debug('sync notifications ' . __LINE__);
				%data = (
					'content' => {
						'channel' => 'push_notifications',
					}
				);
				startActivity(\%data, undef, 1);
			}

			unless (Common::loadServicePath() and Common::loadUsername() and
				(Common::loadUserConfiguration() == 1)) {
				Common::traceLog('service stopping. failed to load service path/username/userconfig.');
				last;
			}
			if (getUserConfiguration('DDA') or (('' ne getUsername()) and ($uname ne getUsername()))) {
				Common::traceLog('service stopping. failed to load username/user switched/DDA is enabled.');
				last;
			}

			Common::killPIDs(\@systemids, 0);
			Common::killPIDs(\@others, 0);

			if (-f Common::getCatfile(Common::getAppPath(), 'debug.enable')) {
				unless ($AppConfig::debug) {
					$AppConfig::debug = 1;
					Common::traceLog('enabling debug mode');
					stopDashboardRoutines();
					updateSystemIsOffline($uname);
					last;
				}
			}
			elsif ($AppConfig::debug) {
				$AppConfig::debug = 0;
				Common::traceLog('disabling debug mode');
				stopDashboardRoutines();
				updateSystemIsOffline($uname);
				last;
			}

			if (($timeDiff = (time() - $startTime)) <= 8) {
				sleep(8 - $timeDiff);
			}
		}

		if (getUserConfiguration('DDA')) {
			%data = (
				'content' => {
					'channel' => 'update_acc_status',
					'notification_value' => ''
				}
			);
			startActivity(\%data, undef, 1);
			Common::traceLog('DDA is enabled, going stop myself');
			stopDashboardRoutines();
			updateSystemIsOffline($uname);
			last;
		}
		elsif (('' ne getUsername()) and ($uname ne getUsername())) {
			Common::traceLog('username might be changed');
			stopDashboardRoutines();
			updateSystemIsOffline($uname);
		}
		else {
			Common::traceLog('deconstruct');
			stopDashboardRoutines();
			sleep(5);
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: syncUpdates
# Objective				: Push local changes to dashboard
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub syncUpdates {
	loadNS();
	my $nsFile = Common::getNSFile();
	my $pn = 0;
	my $nsfh;
	if (open($nsfh, '+<', $nsFile)) {
#		unless (flock($nsfh, LOCK_EX)) {
#traceLog("Cannot lock file $nsFile $!\n");
#			close($nsfh);
#			sleep(3);
#			return 0;
#		}
	}
	else {
		traceLog("Cannot open file $nsFile $!\n");
		sleep(3);
		return 0;
	}

	my %data;
	unless (defined $_[0]) {
		foreach my $n (keys %{getNS()->{'nsq'}}) {
			%data = (
			content => {
				channel => $n,
				notification_value => getNS($n)
			});
debug("notify $n " . __LINE__);
			if (startActivity(\%data, undef, 1)) {
debug("notify $n S" . __LINE__);
				deleteNS($n);
				unless ($pn) {
					$pn = 1 if (exists $AppConfig::notificationsForDashboard{$n});
				}
			}
		}
	}
	else {
	}

	saveNS($nsfh) if ($pn);

	close($nsfh);
	return $pn;
}

#*****************************************************************************************************
# Subroutine			: headerCallback
# Objective				: curl header callback function
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub headerCallback {
	my $header = shift;
	return length($header);
}

#*****************************************************************************************************
# Subroutine			: request
# Objective				: Wrapper for Common::request
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub request {
	my $rc = $AppConfig::rRetryTimes;

	my $curl = WWW::Curl::Easy->new;
	$curl->setopt(CURLOPT_HEADERFUNCTION, \&headerCallback);
	$curl->setopt(CURLOPT_CONNECTTIMEOUT, 10);
	$curl->setopt(CURLOPT_NOPROGRESS, 1);
	$curl->setopt(CURLOPT_URL, ('https://' . $_[0]->{'host'} . $_[0]->{'path'}));

	my $response;
	$curl->setopt(CURLOPT_WRITEDATA,\$response);
	$curl->setopt(CURLOPT_POST, 1);
	$curl->setopt(CURLOPT_SSL_VERIFYHOST, 0);
	$curl->setopt(CURLOPT_CAINFO, getCatfile(Common::getAppPath(), './ca-certificates.crt'));
#	$curl->setopt(CURLOPT_VERBOSE, 1);
	$curl->setopt(CURLOPT_POSTFIELDS, Common::buildQuery($_[0]->{'data'}));

	if (getUserConfiguration('PROXY') ne '') {
		my $proxyuser = getUserConfiguration('PROXYUSERNAME') ne ''? Common::urlEncode(getUserConfiguration('PROXYUSERNAME')) : '';
		my $proxypwd = getUserConfiguration('PROXYPASSWORD') ne ''? Common::decryptString(getUserConfiguration('PROXYPASSWORD')) : '';
		$curl->setopt(CURLOPT_PROXY, "http://" . getUserConfiguration('PROXYIP') . ":" . getUserConfiguration('PROXYPORT'));
		$curl->setopt(CURLOPT_PROXYUSERPWD, $proxyuser . (($proxypwd ne '')? ":$proxypwd" : '')) if ($proxyuser ne '');
	}
	my ($retcode, $responseCode, $jd);
	while($rc) {
		$retcode = $curl->perform;
debug(Dumper($_[0], $retcode, $response));
		if ($retcode == 0) {
			my $responseCode = $curl->getinfo(CURLINFO_HTTP_CODE);

			if (not $response) {
				Common::traceLog("Empty response: $retcode");
				if ($rc--) {
					Common::traceLog("Retrying for $rc times");
					sleep(2);
					next;
				}
				return {STATUS => AppConfig::FAILURE, AppConfig::DATA => ''};
			}
			elsif (($response =~ /404 Not Found/g) or ($response =~ /502 Bad Gateway/g) or ($response =~ /500 Internal Server Error/g)) {
				Common::traceLog("An error occured: $retcode, $response");
				if ($rc--) {
					Common::traceLog("Retrying for $rc times");
					sleep(2);
					next;
				}
				return {STATUS => AppConfig::FAILURE, AppConfig::DATA => $response};
			}
			elsif ($response =~ /^{|^\[/g) {
				$jd = from_json($response);
				if ((reftype($jd) eq 'HASH') and  exists $jd->{'type'} and
						$jd->{'type'} eq 'user authentication failed') {
					return {STATUS => AppConfig::FAILURE, AppConfig::DATA => $jd};
				}
				return {STATUS => AppConfig::SUCCESS, AppConfig::DATA => $jd};
			}

			return {STATUS => AppConfig::SUCCESS, AppConfig::DATA => $response};
		}
		else {
			Common::traceLog("An error occured: $retcode ".$curl->strerror($retcode).' - '.$curl->errbuf);
			if ($rc--) {
				Common::traceLog("Retrying for $rc times");
				sleep(2);
				next;
			}
		}
	}
	return {STATUS => AppConfig::FAILURE, AppConfig::DATA => $response};
}

#*****************************************************************************************************
# Subroutine			: debug
# Objective				: Wrapper for Common::traceLog
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub debug {
	if ($AppConfig::debug) {
		my $msg = "DA:DEBUG: ";
		$msg .= join('', @_);
		Common::traceLog($msg);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getDDAStatus
# Objective				: Get DDA status from dashboard
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getDDAStatus {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '11',
		'1000'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
		'111' => $AppConfig::evsVersion,
		'113' => lc($AppConfig::deviceType),
		'116' => 1,
		#'119' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	#$params->{port} = $AppConfig::NSPort;
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	if (($response->{'STATUS'} eq 'SUCCESS') and (reftype($response->{'DATA'}) eq 'HASH')) {
		$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
		if (exists $response->{'data'}->{'type'} and $response->{'data'}->{'type'} ne 'file') {
			return 0;
		}
		my @acStatus = Common::parseEVSCmdOutput($response->{'data'}->{'content'}, 'item');
		if (exists $acStatus[0]->{'disable'} and (int($acStatus[0]->{'disable'}) ne int(getUserConfiguration('DDA')))) {
			return 1;
		}
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: zlibRead
# Objective				: Read compressed data and return with uncompressed data
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub zlibRead {
	my $gzipFilename = getCatfile(getServicePath(), ('gzipfc' . time() . $$));
	Common::fileWrite($gzipFilename, decode_base64($_[0]));
	my $fh = new IO::Zlib;
	my $fc = '';

	if ($fh->open($gzipFilename, "rb")) {
		$fc = <$fh>;
		while(my $tfc = <$fh>) {
			$fc .= $tfc;
		}
		$fh->close;
	}
	else {
		Common::traceLog("failed to open zip file $gzipFilename $!");
	}
	unlink($gzipFilename);
	return $fc;
}

#*****************************************************************************************************
# Subroutine			: zlibCompress
# Objective				: Compress data and return
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub zlibCompress {
	my $gzipFilename = ('gzipfc' . time() . $$);
	my $fh = new IO::Zlib;
	my $fc = '';
	my $benc = '';

	utf8::downgrade($_[0]);
	encode("utf-8", $_[0]);
	if ($fh->open($gzipFilename, "wb")) {
		print $fh $_[0];
		$fh->close;
	}
	else {
		Common::traceLog("failed to open compress zip file $gzipFilename $!");
	}

	if (open(my $fileHandle, '<', $gzipFilename)) {
		$fc = join('', <$fileHandle>);
		close($fileHandle);
	}

	unlink($gzipFilename);

	$benc = encode_base64($fc);
	chomp($benc);

	return $benc;
}

#*****************************************************************************************************
# Subroutine			: stopDashboardRoutines
# Objective				: Stop all dashboard services(childrens only)
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub stopDashboardRoutines {
	Common::traceLog('stopDashboardRoutines');
	while(scalar @systemids > 0) {
		Common::killPIDs(\@systemids);
		sleep(1);
	}
	while(scalar @progressPIDs > 0) {
		Common::killPIDs(\@progressPIDs);
		sleep(1);
	}
	while(scalar @others > 0) {
		Common::killPIDs(\@others);
		sleep(1);
	}
}

#*****************************************************************************************************
# Subroutine			: loadAccessToken
# Objective				: Load access token
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadAccessToken {
debug('loadAccessToken');
	my $token = getRemoteAccessToken();

	return 0 unless $token;
	$at = Idrivelib::get_atd($token);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: register
# Objective				: Register this computer for dashboard service
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub register {
	my $host = getRemoteManageIP();
	my $isDedup = getUserConfiguration('DEDUP');
	my $backupLocation = getUserConfiguration('BACKUPLOCATION');

	if ($isDedup eq "on") {
		$backupLocation = (split("#", $backupLocation))[1];
	}

	my $params = Idrivelib::get_dashboard_params({
		'0'   => '3',
		'109' => getUsername(),
		'106' => getUsername(),
		'112' => Common::getMachineUID(0),
		'108' => hostname,
		'107' => getMachineUser(),
		'110' => $backupLocation,
		'111' => $AppConfig::evsVersion,
		'113' => lc($AppConfig::deviceType),
		#'119' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = $host;
	$params->{port} = $AppConfig::NSPort;
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	return 0 if ($response->{STATUS} eq AppConfig::FAILURE);
debug('register S' . __LINE__);

	if (getUserConfiguration('ADDITIONALACCOUNT') eq 'true') {
		$host = getParentRemoteManageIP();
		$params = Idrivelib::get_dashboard_params({
			'0'   => '3',
			'109' => (getUserConfiguration('PARENTACCOUNT')),
			'106' => getUsername(),
			'112' => Common::getMachineUID(0),
			'108' => hostname,
			'107' => getMachineUser(),
			'110' => $backupLocation,
			'111' => $AppConfig::evsVersion,
			'113' => lc($AppConfig::deviceType),
			#'119' => 1,
			'101' => $at
		}, 1, 0);
		$params->{host} = $host;
		#$params->{port} = $AppConfig::NSPort;
		$params->{method} = 'POST';
		$params->{json} = 1;
		my $response = request($params);
		return 0 if ($response->{STATUS} eq AppConfig::FAILURE);
debug('register A' . __LINE__);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateSystemIsAlive
# Objective				: Heart beat program
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub updateSystemIsAlive {
debug('ping heart beat' . __LINE__);
	my $pid = fork();

	unless (defined $pid) {
		Common::retreat('Unable to fork');
	}

	unless ($pid) {
		$0 = 'IDrive:dashboard:sa';
		my $content;
		my $params;
		my $response;
		my $UCMTS         = stat(Common::getUserConfigurationFile())->mtime;
		my $userConfigMTS = $UCMTS;
		my $pingTime      = time();

		while(1) {
			end() if ((getppid() == 1) or (!Common::isFileLocked($selfPIDFile)));
			$UCMTS = stat(Common::getUserConfigurationFile())->mtime if (-f Common::getUserConfigurationFile());
			if ($userConfigMTS != $UCMTS) {
				$userConfigMTS = $UCMTS;
				Common::loadUserConfiguration();
debug('userconfig has changed.');
				register();
			}
			my $backupLocation = getUserConfiguration('BACKUPLOCATION');

			if (getUserConfiguration('DEDUP') eq "on") {
				$backupLocation = (split("#", $backupLocation))[1];
			}

			my $entAC = lc(getUserConfiguration('PLANTYPE') . getUserConfiguration('PLANSPECIAL'));
			if (((time() >= $pingTime) and ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true') or ($entAC =~ /business/)))) {
				$pingTime = (time() + 870);
				$params = Idrivelib::get_dashboard_params({
					'0'   => '3',
					'109' => (
						($entAC =~ /business/) ? getUsername() : getUserConfiguration('PARENTACCOUNT')
					),
					'106' => getUsername(),
					'112' => Common::getMachineUID(0),
					'108' => hostname,
					'107' => getMachineUser(),
					'110' => $backupLocation,
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'121' => (time() + $at) . '_' . int(getUserConfiguration('DDA')),
					'124' => '',
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getParentRemoteManageIP();
				$params->{host} = getRemoteManageIP() if ($entAC =~ /business/);
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;
				$response = request($params);
debug('ping heart beat A' . __LINE__);
			}

			if (int(getFileContents(getCatfile(getUserProfilePath(), 'stage.txt'))) > 0) {
				$content = '<item alivetime="' . (time() + $at)  . '"/>';

				$params = Idrivelib::get_dashboard_params({
					'0'   => '2',
					'1001'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'130' => $content,
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getRemoteManageIP();
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;
				$response = request($params);
debug('ping heart beat S' . __LINE__);
			}
			else {
				sleep(4);
				next;
			}

			sleep(30);
		}
		exit(0);
	}

	push @systemids, $pid;
	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateSystemIsOffline
# Objective				: Heart beat program
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub updateSystemIsOffline {
debug('ping heart beat' . __LINE__);
	Common::setUsername($_[0]);
	if (Common::loadUserConfiguration() == 1) {
		my $content;
		my $params;
		my $response;

		my $backupLocation = getUserConfiguration('BACKUPLOCATION');

		if (getUserConfiguration('DEDUP') eq "on") {
			$backupLocation = (split("#", $backupLocation))[1];
		}

		my $entAC = lc(getUserConfiguration('PLANTYPE') . getUserConfiguration('PLANSPECIAL'));
		if ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true') or ($entAC =~ /business/)) {
			$params = Idrivelib::get_dashboard_params({
				'0'   => '3',
				'109' => (
					($entAC =~ /business/) ? getUsername() : getUserConfiguration('PARENTACCOUNT')
				),
				'106' => getUsername(),
				'112' => Common::getMachineUID(0),
				'108' => hostname,
				'107' => getMachineUser(),
				'110' => $backupLocation,
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'121' => ('0_' . int(getUserConfiguration('DDA'))),
				'124' => '',
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getParentRemoteManageIP();
			$params->{host} = getRemoteManageIP() if ($entAC =~ /business/);
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			$response = request($params);
debug('stop heart beat A' . __LINE__);
		}

		$content = '<item alivetime="0"/>';

		$params = Idrivelib::get_dashboard_params({
			'0'   => '2',
			'1001'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
			'111' => $AppConfig::evsVersion,
			'113' => lc($AppConfig::deviceType),
			'130' => $content,
			#'119' => 1,
			'101' => $at
		}, 1, 0);
		$params->{host} = getRemoteManageIP();
		#$params->{port} = $AppConfig::NSPort;
		$params->{method} = 'POST';
		$params->{json} = 1;
		$response = request($params);
debug('stop heart beat S' . __LINE__);
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: applyChangedFields
# Objective				: Apply prop settings to the current user
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub applyChangedFields {
debug('applyChangedFields ' . Dumper($_[0]));
	my $ps = Common::getPropSettings($_[1]);
	my $isModified = 0;
	my @z = @{$_[0]};
	my $lockSettings;
	my $oldValue = '';
	for (0 .. $#z) {
		# TODO: check to propagate for this user
		next if (exists $z[$_]->{'pusers'});

		unless (exists $z[$_]->{'type'}) {
			next if (exists $z[$_]->{'lousers'} and ($z[$_]->{'lousers'} ne 'all') and not ($z[$_]->{'lousers'} =~ getUsername()));

			next if (exists $z[$_]->{'ulusers'} and ($z[$_]->{'ulusers'} ne 'all') and not ($z[$_]->{'ulusers'} =~ getUsername()));

			$lockSettings = PropSchema::parse($z[$_]);
			next unless (exists $lockSettings->{'type'});
			if (($lockSettings->{'type'} eq 'sch')) {
				if (exists $lockSettings->{'bksetname'}) {
					$ps->{$lockSettings->{'type'}}{$lockSettings->{'key'}}{$lockSettings->{'bksetname'}}{'islocked'} = $lockSettings->{'islocked'};
				}
				else {
					$ps->{$lockSettings->{'type'}}{$lockSettings->{'key'}}{$lockSettings->{'backupSet'}}{'islocked'} = $lockSettings->{'islocked'};
				}
			}
			else {
				$ps->{$lockSettings->{'type'}}{$lockSettings->{'key'}}{'islocked'} = $lockSettings->{'islocked'};
			}
			$isModified = 1 unless ($isModified);
			next;
		}

		if (exists $ps->{$z[$_]->{'type'}}) {
			if ($z[$_]->{'type'} eq 'sch') {
				if (exists $z[$_]->{'bksetname'}) {
					if (exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}} and
						exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'bksetname'}} and
						exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'bksetname'}}{'id'} and
						(int($ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'bksetname'}}{'id'}) == int($z[$_]->{'id'}))) {
						next;
					}
				}
				elsif (exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}} and
					exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'backupSet'}} and
					exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'backupSet'}}{'id'} and
					(int($ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'backupSet'}}{'id'}) == int($z[$_]->{'id'}))) {
					next;
				}
			}
			elsif (exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}} and
				exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}->{'id'} and
				(int($ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}->{'id'}) == int($z[$_]->{'id'}))) {
				next;
			}
		}

		if (($z[$_]->{'type'} eq 'sch')) {
			if (exists $z[$_]->{'bksetname'}) {
				unless (exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'bksetname'}}{'islocked'}) {
					$ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'bksetname'}}{'islocked'} = 0;
				}
				$z[$_]->{'islocked'} = $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'bksetname'}}{'islocked'};
				$ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'bksetname'}} = $z[$_];
			}
			else {
				unless (exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'backupSet'}}{'islocked'}) {
					$ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'backupSet'}}{'islocked'} = 0;
				}
				$z[$_]->{'islocked'} = $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'backupSet'}}{'islocked'};
				$ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{$z[$_]->{'backupSet'}} = $z[$_];
			}
		}
		else {
			unless (exists $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{'islocked'}) {
				$ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{'islocked'} = 0;
			}
			$z[$_]->{'islocked'} = $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}{'islocked'};
			$oldValue = $ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}}->{'value'};
			$ps->{$z[$_]->{'type'}}{$z[$_]->{'key'}} = $z[$_];
			$z[$_]->{'oldvalue'} = $oldValue;
			$oldValue = '';
		}
		$isModified = 1 unless ($isModified);
		startActivity(PropSchema::parse($z[$_], getUsername()), undef, 1, 1);
		delete $z[$_]->{'oldvalue'};
	}
	Common::fileWrite(Common::getPropSettingsFile($_[1]), to_json($ps)) if ($isModified);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: fetchPropSettings
# Objective				: Fetch prop settings from dashboard
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub fetchPropSettings {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '11',
		'1002'=> getUsername(),
		'111' => $AppConfig::evsVersion,
		'102' => 1,
		'113' => lc($AppConfig::deviceType),
		'116' => 1,
		#'119' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	#$params->{port} = $AppConfig::NSPort;
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	return 0 if ($response->{STATUS} eq AppConfig::FAILURE);

debug('fetch prop settings S ' . __LINE__);
	$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
	$response->{'data'}->{'content'} = Common::urlDecode($response->{'data'}->{'content'});
	if (utf8::is_utf8($response->{'data'}->{'content'})) {
		utf8::downgrade($response->{'data'}->{'content'});
	}
	my @z = Common::parseEVSCmdOutput($response->{'data'}->{'content'}, 'item');
debug(__LINE__ . ' ' . $response->{'data'}->{'content'});
debug(__LINE__ . ' ' . Dumper(\@z));
	applyChangedFields(\@z);

	my $entAC = lc(getUserConfiguration('PLANTYPE') . getUserConfiguration('PLANSPECIAL'));
	if ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true') or ($entAC =~ /business/)) {
		$params = Idrivelib::get_dashboard_params({
			'0'   => '11',
			'1003'=> (
				($entAC =~ /business/) ? getUsername() : getUserConfiguration('PARENTACCOUNT')
			),
			'111' => $AppConfig::evsVersion,
			'102' => 1,
			'113' => lc($AppConfig::deviceType),
			'116' => 1,
			#'119' => 1,
			'101' => $at
		}, 1, 0);
		$params->{host} = getParentRemoteManageIP();
		$params->{host} = getRemoteManageIP() if ($entAC =~ /business/);
		#$params->{port} = $AppConfig::NSPort;
		$params->{method} = 'POST';
		$params->{json} = 1;
		$response = request($params);
		return 0 if ($response->{STATUS} eq AppConfig::FAILURE);

debug('fetch prop settings A ' . __LINE__);
		$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
		return 1 unless (exists $response->{'data'}->{'content'});
		my $d = zlibRead($response->{'data'}->{'content'});
debug(__LINE__ . " $d");
		my $index = index($d, sprintf("<User id=\"%s\">", getUsername()));
		$d = substr($d, $index);
		$index = index($d, '</User>');
		$d = substr($d, 0, ($index + 7));
debug(__LINE__ . " $d");
		my (@z, @t);
		foreach (@PropSchema::propFields) {
			@t = Common::parseEVSCmdOutput($d, $_, 1);
			if ($t[0]->{'STATUS'} eq 'SUCCESS') {
				$_ = 'Default BackupSet' if ($_ eq 'DefaultBackupSet');
				$t[0]->{'key'} = $_;
				push(@z, $t[0]);
			}
		}
		@t = Common::parseEVSCmdOutput($d, 'lock', 1);
debug(__LINE__ . Dumper(\@t));
		if ($t[0]->{'STATUS'} eq 'SUCCESS') {
			my $keyid = 0;
			foreach (split //, $t[0]->{'value'}) {
				if (int($_)) {
					push(@z, {'key' => $keyid, 'STATUS' => 'SUCCESS'});
				}
				$keyid++;
			}
		}
debug(__LINE__ . Dumper(\@z));
		applyChangedFields(\@z, 'master');
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: watchDeltaPropSettings
# Objective				: Watch for delta prop settings from dashboard
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub watchDeltaPropSettings {
	my $pid = fork();

	unless (defined $pid) {
		Common::retreat('Unable to fork');
	}

	unless ($pid) {
		$0 = 'IDrive:dashboard:dp';
		my $prevData = '';
		my $curData  = '';
		my $entAC = lc(getUserConfiguration('PLANTYPE') . getUserConfiguration('PLANSPECIAL'));
		my $hasUpdates;
		my $sleepTime = 10;
		my ($params, $response);
		while(1) {
			end() if ((getppid() == 1) or (!Common::isFileLocked($selfPIDFile)));
			if (int(getFileContents(getCatfile(getUserProfilePath(), 'stage.txt'))) > 0) {
				$params = Idrivelib::get_dashboard_params({
					'0'   => '11',
					'1004'=> getUsername(),
					'111' => $AppConfig::evsVersion,
					'102' => 1,
					'113' => lc($AppConfig::deviceType),
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getRemoteManageIP();
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;
				$response = request($params);
debug('get delta prop settings S ' . __FILE__);
				if (($response->{'DATA'}) and (reftype($response->{'DATA'}) eq 'ARRAY')) {
					$response = Idrivelib::get_dashboard_params($response->{'DATA'}[0], 0, 0);
					$curData = $response->{'data'}->{'content'};

					if ($curData ne $prevData) {
						$curData = Common::urlDecode($curData);
						if (utf8::is_utf8($curData)) {
							utf8::downgrade($curData);
						}
debug("delta prop settings S data: $curData");
						my @z = Common::parseEVSCmdOutput($curData, 'item');
						applyChangedFields(\@z);
						$prevData = $curData;
					}
				}
			}

			if ($sleepTime == 10) {
				$sleepTime = 5;
			}
			elsif ($sleepTime == 5) {
				$sleepTime = 10;
			}
			elsif ($sleepTime == 0) {
				$sleepTime = 10;
				sleep($sleepTime);
				next;
			}

			sleep($sleepTime);
			end() if ((getppid() == 1) or (!Common::isFileLocked($selfPIDFile)));

			if ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true') or ($entAC =~ /business/)) {
				$hasUpdates = 0;
				$params = Idrivelib::get_dashboard_params({
					'0'   => '11',
					'1005'=> (
						($entAC =~ /business/) ? getUsername() : getUserConfiguration('PARENTACCOUNT')
					),
					'102' => 1,
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getParentRemoteManageIP();
				$params->{host} = getRemoteManageIP() if ($entAC =~ /business/);
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;
				$response = request($params);
debug('get delta prop settings A' . __FILE__);
				if (($response->{'DATA'}) and (reftype($response->{'DATA'}) eq 'ARRAY')) {
					$response = Idrivelib::get_dashboard_params($response->{'DATA'}[0], 0, 0);
					$curData = zlibRead($response->{'data'}->{'content'});

					$curData = Common::urlDecode($curData);
					if (utf8::is_utf8($curData)) {
						utf8::downgrade($curData);
					}
debug("delta prop settins A data: $curData");
					if ($curData ne $prevData) {
						my @z = Common::parseEVSCmdOutput($curData, 'item');
						for (0 .. $#z) {
							if (exists $z[$_]->{'pusers'} and (($z[$_]->{'pusers'} eq 'all') or ($z[$_]->{'pusers'} =~ getUsername()))) {
								$hasUpdates = 1;
								last;
							}
							if (exists $z[$_]->{'lousers'} and (($z[$_]->{'lousers'} eq 'all') or ($z[$_]->{'lousers'} =~ getUsername()))) {
								$hasUpdates = 1;
								last;
							}

							if (exists $z[$_]->{'ulusers'} and (($z[$_]->{'ulusers'} eq 'all') or ($z[$_]->{'ulusers'} =~ getUsername()))) {
								$hasUpdates = 1;
								last;
							}
						}
						applyChangedFields(\@z, 'master') if ($hasUpdates);
						$prevData = $curData;
					}
				}
			}
			if ($sleepTime == 10) {
				$sleepTime = 0;
			}
			elsif ($sleepTime == 5) {
				sleep($sleepTime);
			}
		}
		exit(0);
	}

	push @systemids, $pid;
	return 1;
}

#*****************************************************************************************************
# Subroutine			: restoreBackupset
# Objective				: Adopt restorebackupset from previous device
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restoreBackupset {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '11',
		'1007'=> (getUsername() . $_[0] . $_[1]),
		'111' => $AppConfig::evsVersion,
		'113' => lc($AppConfig::deviceType),
		'116' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	if (exists $response->{'DATA'} and exists $response->{'DATA'}{'content'}) {
		$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
		$response = from_json(zlibRead($response->{'data'}->{'content'}));
		my %data = ();
		$data{'content'}{'channel'} = 'save_backupset_content';
		$data{'content'}{'files'} = $response->{'files'};
		startActivity(\%data, undef, 1, -1);
	}
}

#*****************************************************************************************************
# Subroutine			: restoreLocalBackupset
# Objective				: Adopt localbackupset from previous device
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restoreLocalBackupset {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '11',
		'1008'=> (getUsername() . $_[0] . $_[1]),
		'111' => $AppConfig::evsVersion,
		'113' => lc($AppConfig::deviceType),
		'116' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	if (exists $response->{'DATA'} and exists $response->{'DATA'}{'content'}) {
		$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
		$response = from_json(zlibRead($response->{'data'}->{'content'}));
		my %data = ();
		$data{'content'}{'channel'} = 'save_localbackupset_content';
		$data{'content'}{'files'} = $response->{'files'};
		startActivity(\%data, undef, 1, -1);
	}
}

#*****************************************************************************************************
# Subroutine			: restoreSchduledJobs
# Objective				: Adopt scheduled settings from previous device
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restoreSchduledJobs {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '11',
		'1016'=> (getUsername() . $_[0] . $_[1]),
		'111' => $AppConfig::evsVersion,
		'113' => lc($AppConfig::deviceType),
		'116' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	if (exists $response->{'DATA'} and exists $response->{'DATA'}{'content'}) {
		$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
		$response = from_json(zlibRead($response->{'data'}->{'content'}));
		my %data = ();
		$data{'content'}{'channel'} = 'save_scheduler';
		foreach my $uname (keys %{$response}) {
			delete $response->{$uname}{'dashboard'} if (exists $response->{$uname}{'dashboard'});
			delete $response->{$uname}{'otherInfo'} if (exists $response->{$uname}{'otherInfo'});
			if (exists $response->{$uname}{'archive'}) {
				foreach my $name (keys %{$response->{$uname}{'archive'}}) {
					if (exists $response->{$uname}{'archive'}{$name}{'cmd'} and
						($response->{$uname}{'archive'}{$name}{'cmd'} =~ getUsername())) {
						my $tmp = (split((getUsername() . ' '), $response->{$uname}{'archive'}{$name}{'cmd'}))[1];
						my @tmp2= split(' ', $tmp);
						$response->{$uname}{'archive'}{$name}{'cmd'} = ($tmp2[0] . ' ' . $tmp2[1]);
					}
				}
			}
			$data{'content'}{'crontab'}{$uname} = $response->{$uname};
		}
		startActivity(\%data, undef, 1, 1);
	}
}

#*****************************************************************************************************
# Subroutine			: restoreUserSettings
# Objective				: Adopt user settings from previous device
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restoreUserSettings {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '11',
		'1013'=> (getUsername() . $_[0] . $_[1]),
		'111' => $AppConfig::evsVersion,
		'113' => lc($AppConfig::deviceType),
		'116' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	if (exists $response->{'DATA'} and exists $response->{'DATA'}{'content'}) {
		$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
		$response = from_json(zlibRead($response->{'data'}->{'content'}));
		delete $response->{'BACKUPLOCATION'} if (exists $response->{'BACKUPLOCATION'});
		delete $response->{'RESTORELOCATION'} if (exists $response->{'RESTORELOCATION'});
		delete $response->{'RESTOREFROM'} if (exists $response->{'RESTOREFROM'});
		delete $response->{'LOCALMOUNTPOINT'} if (exists $response->{'LOCALMOUNTPOINT'});

		my %data = ();
		$data{'content'}{'channel'} = 'save_user_settings';
		$data{'content'}{'user_settings'} = $response;
		startActivity(\%data, undef, 1, -1);
	}
}

#*****************************************************************************************************
# Subroutine			: restoreSettings
# Objective				: Adopt settings from previous device
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restoreSettings {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '11',
		'1015'=> (getUsername() . $_[0] . $_[1]),
		'111' => $AppConfig::evsVersion,
		'113' => lc($AppConfig::deviceType),
		'116' => 1,
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	$params->{method} = 'POST';
	$params->{json} = 1;
	my $response = request($params);
	if (exists $response->{'DATA'} and exists $response->{'DATA'}{'content'}) {
		$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
		$response = from_json(zlibRead($response->{'data'}->{'content'}));
		my %data = ();
		$data{'content'}{'channel'} = 'save_settings';
		$data{'content'}{'settings'} = $response;
		startActivity(\%data, undef, 1, -1);
	}
}

#*****************************************************************************************************
# Subroutine			: startActivity
# Objective				: Start an user activity
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub startActivity {
	my $data = $_[0] || return 0;
	my $content;
	my $ic = 0;
	$ic = $_[3] if (defined $_[3]);

	$AppConfig::errorMsg = undef;

debug("ic $ic " . __LINE__);
	if (defined($_[2]) and $_[2]) {
		$content = $data->{'content'};
	}
	else {
		return 1 if ((not exists $data->{'content'}) || ($data->{'content'} eq ''));
		eval {
			$content = from_json(zlibRead($data->{'content'}));
			1;
		} or do {
			if ($@) {
				Common::traceLog("Exception: $@");
			}
			else {
				Common::traceLog("Uncaught exception");
			}
			return 0;
		};
	}

	my %activity = (
		'register_dashboard' => \&register,

		'connect' => sub {
			my %d = (
				'ip'     => Common::getIPAddr(),
				'version'=> $AppConfig::version,
			);
			if (getUserConfiguration('DEDUP') eq 'off') {
				$d{'backuplocation'} = getUserConfiguration('BACKUPLOCATION');
			}
			else {
				$d{'backuplocation'} = (split("#", getUserConfiguration('BACKUPLOCATION')))[1];
			}

			my $uvf = getCatfile(Common::getAppPath(), $AppConfig::updateVersionInfo);
			if (-f $uvf and !-z $uvf) {
				$d{'hasupdate'} = 1;
			}
			else {
				$d{'hasupdate'} = 0;
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%d)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;

			my $response = request($params);

			updateFileSetSize('backup');
			updateFileSetSize('localbackup');

			return 1;
		},

		'get_fileset_size' => sub {
			my $bsf = Common::getJobsPath($content->{'jobtype'}, 'file');
			my $backupsizelock = Common::getBackupsetSizeLockFile($content->{'jobtype'});
			if (defined($content->{'ondemand'}) and $content->{'ondemand'} == 1 and
				-f "$bsf.json" and !Common::isFileLocked($backupsizelock)) {
				my %backupsetsizes = (-f "$bsf.json")? %{JSON::from_json(getFileContents("$bsf.json"))} : ();
				my %backupSetInfo;
				foreach my $filename (keys %backupsetsizes) {
					$backupSetInfo{$filename} = {
						'size' => -1,
						'ts'   => '',
						'filecount' => 'NA',
						'type' => $backupsetsizes{$filename}->{'type'}
					}
				}
				Common::fileWrite2("$bsf.json", JSON::to_json(\%backupSetInfo));
			}

			sendInitialFilesetUpdate($content->{'jobtype'});

			my $status = AppConfig::FAILURE;

			$status = AppConfig::SUCCESS if (updateFileSetSize($content->{'jobtype'}));
			my %d = ('status' => $status);
			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%d)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);

			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);
debug('get file size');

			return 1;
		},

		'update_remote_manage_ip' => sub {
			my @responseData = Common::authenticateUser(getUsername(), &Common::getPdata(getUsername())) or return 0;
			return 0 if ($responseData[0]->{'STATUS'} eq 'FAILURE');

			return 0 if ((exists $responseData[0]->{'plan_type'}) and ($responseData[0]->{'plan_type'} eq 'Mobile-Only') and
				(exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'M'));
			my $rmip = getRemoteManageIP();
			my $prmip= getParentRemoteManageIP();

			setUserConfiguration(@responseData);
			saveUserConfiguration() or return 0;

			if (($rmip ne getRemoteManageIP()) or ($prmip ne getParentRemoteManageIP())) {
				return 1;
			}

			return 2;
		},

		'push_notifications' => sub {
			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1006'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(getNS()->{'nsd'})),
				#'119' => 1,
				'116' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'get_file_lists' => sub {
			my $dirname = $content->{'path'};
			if (utf8::is_utf8($dirname)) {
				utf8::downgrade($dirname);
			}
			my %files;
			unless (-e $dirname) {
				$files{'status'} = AppConfig::FAILURE;
				$files{'errmsg'} = 'directory does not exists';
			}
			else {
				$dirname .= '/' unless (substr($dirname, -1) eq '/');
				opendir(my $dh, $dirname) or
					Common::retreat(['can not open', ":$dirname: $!"]);

				$files{'status'} = AppConfig::SUCCESS;
				# $files{'dir'} = $dirname;

				my $filename = '';
				my $totalFileNameLength=0;
				my $maxFileNameLength  = 8192; # 8KB
				while ($filename = readdir $dh) {
					next if (($filename =~ /^\.\.?$/) || (-l "$dirname$filename") || (!getUserConfiguration('SHOWHIDDEN') and "$dirname$filename" =~ /\/\./));

					$totalFileNameLength += (length("$filename")+13); #Restricting if file name's length is more than 4K
					# last if ($totalFileNameLength > $maxFileNameLength);

					if (-d "$dirname$filename") {
						$files{'files'}{"$filename"}{'type'} = 'd';
					}
					elsif (-f "$dirname$filename") {
						$files{'files'}{"$filename"}{'type'} = 'f';
					}
					$filename = '';
				}
				closedir $dh;
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%files)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'save_fileset_content' => sub {
			my $jobName = 'backup';
			$jobName   = $_[0] if (defined $_[0]);
			my $localSaveOnly = 0;
			$localSaveOnly = $_[1] if (defined $_[1] and $_[1]);

			$localSaveOnly = $ic if ($ic);

			# $content->{'files'} = zlibRead($content);

			my $bsf = Common::getJobsPath($jobName, 'file');
			open(my $bsContents, '>', $bsf) or return 0;

			my $realkey = '';
			my %backupSet;
			if ($jobName =~ /backup/) {
				my @itemsarr = ();
				foreach my $key (keys %{$content->{'files'}}) {
					if (utf8::is_utf8($key)) {
						utf8::downgrade($key);
					}
					push @itemsarr, $key;
				}
				@itemsarr = Common::verifyEditedFileContent(\@itemsarr);
				if (scalar(@itemsarr) > 0) {
					%backupSet = Common::getLocalDataWithType(\@itemsarr, 'backup');
					%backupSet = Common::skipChildIfParentDirExists(\%backupSet);
				}
				else {
					%backupSet= ();
				}
			}
			else {
				%backupSet = %{$content->{'files'}};
			}

			my %backupSetInfo;
			my %backupsetsizes = (-f "$bsf.json")? %{JSON::from_json(getFileContents("$bsf.json"))} : ();
			foreach my $key (keys %backupSet) {
				$realkey = $key;
				$realkey =~ s/\/$// unless(exists($content->{'files'}{$realkey}));

				print $bsContents "$key\n";
				if (exists $backupsetsizes{$key}) {
					$backupSetInfo{$key} = $backupsetsizes{$key};
				}
				else {
					$backupSetInfo{$key} = {
						'size' => -1,
						'ts'   => '',
						'filecount' => 'NA',
						'type' => $content->{'files'}{$realkey}{'type'}
					}
				}
			}
			Common::fileWrite2("$bsf.json", JSON::to_json(\%backupSetInfo));

			close($bsContents);

			if ($ic) {
				return 1 if ($ic < 0);
				loadNotifications() and setNotification(sprintf("get_%sset_content", $jobName)) and saveNotifications();
				return 1;
			}

			# calculate and send the backupset size
			my $processingreq;
			my %notifsizes;
			if ($jobName ne 'restore') {
				my $backupsetdata = getFileContents($bsf, 'array');
				($processingreq, %notifsizes) = Common::getBackupsetFileSize($backupsetdata);
				%backupsetsizes = (-f "$bsf.json")? %{JSON::from_json(getFileContents("$bsf.json"))} : ();
				Common::updateDirSizes(\%backupsetsizes, \%notifsizes, 0);
				my $rid = '1007';
				$rid = '1008' if ($jobName eq 'localbackup');

				my %syncdata;
				$syncdata{'status'} = AppConfig::SUCCESS;
				$syncdata{'ts'} = mktime(localtime);
				$syncdata{'files'} = {%notifsizes};

				my $scontent = to_json(\%syncdata);
				my $params = Idrivelib::get_dashboard_params({
					'0'   => '2',
					$rid  => (getUsername() . Common::getMachineUID(0) . getMachineUser()),
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'130' => zlibCompress($scontent),
					'116' => 1,
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getRemoteManageIP();
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;

				my $response = request($params);
			}

			unless ($localSaveOnly) {
				my %d = (
					'status' => AppConfig::SUCCESS
				);
				my $params = Idrivelib::get_dashboard_params({
					'0'   => '2',
					'1017'=> $data->{1017},
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'130' => zlibCompress(to_json(\%d)),
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getRemoteManageIP();
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;
				my $response = request($params);
			}

			if ($jobName ne 'restore') {
				updateFileSetSize($jobName);
			}

			return 1;
		},

		'get_fileset_content' => sub {
			my $jobName = 'backup';
			my $rid = '1007';
			if (defined $_[0] and defined $_[1]) {
				$jobName = $_[0];
				$rid = $_[1];
			}

			my $bsf = Common::getJobsPath($jobName, 'file');
			my %backupSet;
			my %backupsetsizes;
			my $backupsetdata = getFileContents($bsf, 'array');
			my ($processingreq, %notifsizes) = Common::getBackupsetFileSize($backupsetdata);
			if (-f "$bsf.json" and -s "$bsf.json" > 0) {
				$backupSet{'files'} = getFileContents("$bsf.json");
			}
			else {
				$backupSet{'status'} = AppConfig::SUCCESS;
				$backupSet{'files'} = '';
			}

			$backupSet{'ts'} = mktime(localtime);

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				$rid  => (getUsername() . Common::getMachineUID(0) . getMachineUser()),
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%backupSet)),
				#'119' => 1,
				'116' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			syncFilesetSizeWithFork($jobName);
			return 1;
		},

		'get_mount_points' => sub {
			my %d = (
				'files' => Common::getMountPoints('Writeable'),
				'status' => AppConfig::SUCCESS
			);
			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%d)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'start_job' => sub {
			my $scriptName;
			my $scriptArgs;
			my %status;
			my $errmsg = $_[2] || '';
			if (defined $_[0] and defined $_[1]) {
				$scriptName = $_[0];
				$scriptArgs = $_[1];
			}
			else {
				Common::tracelog('atleast_script_name_is_required');
				return 0;
			}

			if ($errmsg eq '') {
				my $cmd = ("$AppConfig::perlBin " . Common::getScript($scriptName, 1));
				$cmd   .= (" $scriptArgs " . getUsername() .  ' 1> /dev/null 2> /dev/null &');
				$cmd = Common::updateLocaleCmd($cmd);
				unless (system($cmd) == 0) {
					$status{'status'} = AppConfig::FAILURE
				}
				else {
					$status{'status'} = AppConfig::SUCCESS
				}
			}
			else {
				$status{'errmsg'} = $errmsg;
				$status{'status'} = AppConfig::FAILURE
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%status)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'stop_job' => sub {
			my %status;
			if (defined $_[0]) {
				if (!Common::isFileLocked(getCatfile(Common::getJobsPath($_[0]), 'pid.txt')) and
						(getNS(sprintf("update_%s_progress", $_[0])) =~ /_Running_/)) {
					my $nv = getNS(sprintf("update_%s_progress", $_[0]));
					$nv =~ s/_Running_/_Aborted_/g;
					loadNotifications() and setNotification(sprintf("update_%s_progress", $_[0]), $nv) and saveNotifications();
				}

				my $cmd = ("$AppConfig::perlBin " . Common::getScript('job_termination', 1));
				$cmd   .= (" $_[0] " . getUsername() . ' 1>/dev/null 2>/dev/null &');
				$cmd = Common::updateLocaleCmd($cmd);
				unless (system($cmd) == 0) {
					$status{'status'} = AppConfig::FAILURE
				}
				else {
					$status{'status'} = AppConfig::SUCCESS
				}
			}
			else {
				Common::tracelog('job_name_is_required');
				$status{'status'} = AppConfig::FAILURE
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%status)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'update_progress_details' => sub {
			my $jobName;
			my $rid;
			my $updateLastActivity = 0;
			my $backupActivityOnly = 0;

			if (defined $_[0]) {
				$jobName   = $_[0];
				$rid = $_[1];
			}
			else {
				Common::traceLog('job name is required');
				return 1;
			}

			if (defined $_[2]) {
				$updateLastActivity = $_[2];
			}

			if (defined $_[3]) {
				$backupActivityOnly = $_[3];
			}

			unless ($AppConfig::availableJobsSchema{$jobName}) {
				Common::traceLog('job name ' . $jobName . ' does not exsits');
				return 1;
			}

			my $progressDetailsFile = getCatfile(Common::getJobsPath($jobName), $AppConfig::progressDetailsFilePath);
			my $pidFile             = getCatfile(Common::getJobsPath($jobName), 'pid.txt');
			my $progressPidFile     = getCatfile(Common::getJobsPath($jobName), 'dashboardupdate.pid');

			my ($pdfHandle, @pdfContent, $pdfc, @progressData,
					$response, %params, %progressInfo, $p);

			%progressInfo = (
				'status' => $content->{'notification_value'},
				'type' => '',
				'transfered_size' => '',
				'total_size' => '',
				'transfer_rate' => '',
				'filename' => '',
			);

			my $params;
			unless ($backupActivityOnly) {
				$params = Idrivelib::get_dashboard_params({
					'0'   => '2',
					$rid  => (getUsername() . Common::getMachineUID(0) . getMachineUser()),
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'130' => zlibCompress(to_json(\%progressInfo)),
					#'119' => 1,
					'116' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getRemoteManageIP();
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;
				$response = request($params);
			}

			if ($backupActivityOnly or $updateLastActivity) {
				my $inProgress = 0;
				my $progressStatus = 0;
				my $backupTime;
				my @fn = split('_', $content->{'notification_value'});
				if ($fn[1] eq 'Running') {
					$inProgress = 1;
					$progressStatus = 0;
				}
				else {
					$inProgress = 0;
					if ($fn[1] eq 'Success') {
						$progressStatus = 0;
					}
					elsif ($fn[1] eq 'Failure') {
						$progressStatus = 1;
					}
					elsif ($fn[1] eq 'Aborted') {
						$progressStatus = 2;
					}
				}
				$fn[0] = 0 if ($fn[0] eq '');
				$backupTime = $fn[0];
				$backupTime = ($backupTime + $at) if ($backupTime);
				my $s = sprintf("<item inprogress=\"%d\" status=\"%d\" time=\"%d\"/>", $inProgress, $progressStatus, $backupTime);

				my $p = Idrivelib::get_dashboard_params({
					'0'   => '2',
					'1012'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'130' => $s,
					#'119' => 1,
					'116' => 1,
					'101' => $at
				}, 1, 0);
				$p->{host} = getRemoteManageIP();
				$p->{port} = $AppConfig::NSPort;
				$p->{method} = 'POST';
				$p->{json} = 1;
				my $response = request($p);

				my $entAC = lc(getUserConfiguration('PLANTYPE') . getUserConfiguration('PLANSPECIAL'));
				if ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true') or ($entAC =~ /business/)) {
					$progressStatus = 3 if ($inProgress);
					my $isDedup = getUserConfiguration('DEDUP');
					my $backupLocation = getUserConfiguration('BACKUPLOCATION');

					if ($isDedup eq "on") {
						$backupLocation = (split("#", $backupLocation))[1];
					}
					$params = Idrivelib::get_dashboard_params({
						'0'   => '3',
						'109' => (
							($entAC =~ /business/) ? getUsername() : getUserConfiguration('PARENTACCOUNT')
						),
						'110' => $backupLocation,
						'106' => getUsername(),
						'112' => Common::getMachineUID(0),
						'113' => lc($AppConfig::deviceType),
						'108' => hostname,
						'107' => getMachineUser(),
						'111' => $AppConfig::evsVersion,
						'113' => lc($AppConfig::deviceType),
						'123' => sprintf("%s_%d_%d", ($backupTime + $at), $progressStatus, 0),
						'124' => '',
						'125' => ($backupTime + $at),
						#'119' => 1,
						'101' => $at
					}, 1, 0);
					$params->{host} = getParentRemoteManageIP();
					$params->{host} = getRemoteManageIP() if ($entAC =~ /business/);
					#$params->{port} = $AppConfig::NSPort;
					$params->{method} = 'POST';
					$params->{json} = 1;
					$response = request($params);
				}

				#return 1 if ($backupActivityOnly);
			}

			unless (Common::isFileLocked($pidFile, undef, 1)) {
				if (getNS(sprintf("update_%s_progress", $_[0])) =~ /_Running_/) {
					if (-f getCatfile(Common::getJobsPath($jobName), $AppConfig::logPidFile)) {
						my $logStatus = Common::checkAndRenameFileWithStatus(Common::getJobsPath($jobName), $jobName);
						return 1;
					}

					my $nv = Common::getNotifications(sprintf("update_%s_progress", $jobName));
					$nv =~ s/_Running_/_Aborted_/g;

					loadNotifications() and setNotification(sprintf("update_%s_progress", $jobName), $nv) and saveNotifications();
					unlink($pidFile);
				}
				return 1;
			}

			if (Common::isFileLocked($progressPidFile)) {
				return 1;
			}

			my $pid = fork();

			unless (defined $pid) {
				Common::retreat('Unable to fork');
			}

			unless ($pid) {
				$0 = 'IDrive:dashboard:pd';
				my $previouspdfc = '';
				my $readTillEOF = 1;
				my $fh;

				if (open(my $fh, ">>", $progressPidFile)) {
					unless (flock($fh, 2|4)) {
						close($fh);
						Common::traceLog(['unable_to_lock_file', $progressPidFile]);
						return 1;
					}
				}
				else {
					Common::traceLog(['unable_to_open_file', $progressPidFile]);
					return 1;
				}

				do {{
					unless (int(getFileContents(getCatfile(getUserProfilePath(), 'browsers.txt'))) > 0) {
						if (-f $pidFile and !Common::isFileLocked($pidFile, undef, 1)) {
							if (-f getCatfile(Common::getJobsPath($jobName), $AppConfig::logPidFile)) {
								my $logStatus = Common::checkAndRenameFileWithStatus(Common::getJobsPath($jobName), $jobName);
							}
							close($fh);
							exit(0);
						}
						sleep(5);
						next;
					}
					@progressData = Common::getProgressDetails($progressDetailsFile);

					%progressInfo = (
						'status' => $content->{'notification_value'},
						'type' => $progressData[0],
						'transfered_size' => $progressData[1],
						'total_size' => $progressData[2],
						'transfer_rate' => $progressData[3],
						'filename' => $progressData[4],
						'file_size' => $progressData[5],
					);
					$params = Idrivelib::get_dashboard_params({
						'0'   => '2',
						$rid  => (getUsername() . Common::getMachineUID(0) . getMachineUser()),
						'111' => $AppConfig::evsVersion,
						'113' => lc($AppConfig::deviceType),
						'130' => zlibCompress(to_json(\%progressInfo)),
						#'119' => 1,
						'116' => 1,
						'101' => $at
					}, 1, 0);
					$params->{host} = getRemoteManageIP();
					#$params->{port} = $AppConfig::NSPort;
					$params->{method} = 'POST';
					$params->{json} = 1;
					$response = request($params);

					unless (Common::isFileLocked($pidFile, undef, 1)) {
						if ($readTillEOF) {
							$readTillEOF = 0;
						}
						else {
							if (-f $pidFile and loadNotifications() and (Common::getNotifications(sprintf("update_%s_progress", $_[0])) =~ /_Running_/)) {
								if (-f getCatfile(Common::getJobsPath($jobName), $AppConfig::logPidFile)) {
									my $logStatus = Common::checkAndRenameFileWithStatus(Common::getJobsPath($jobName), $jobName);
									close($fh);
									exit(0);
								}

								my $nv = Common::getNotifications(sprintf("update_%s_progress", $jobName));
								$nv =~ s/_Running_/_Aborted_/g;
								setNotification(sprintf("update_%s_progress", $jobName), $nv) and saveNotifications();
								unlink($pidFile);
							}
							close($fh);
							exit(0);
						}
					}

					sleep(8);
				}} while(1);

				close($fh);
				exit(0);
			}

			push @progressPIDs, $pid;
			return 1;
		},

		'get_user_settings' => sub {
			my %userConfig = getUserConfiguration('dashboard');

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1013'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%userConfig)),
				#'119' => 1,
				'116' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'save_user_settings' => sub {
			my @userConfig = ($content->{'user_settings'});
			my $errMsg = '';
			my %status;
			$status{'status'} = AppConfig::FAILURE;

			if (exists $userConfig[0]->{'BACKUPLOCATION'} and (getUserConfiguration('DEDUP') eq 'on') and
			($userConfig[0]->{'BACKUPLOCATION'} ne getUserConfiguration('BACKUPLOCATION'))) {
				my @bl = split('#', $userConfig[0]->{'BACKUPLOCATION'});
				my @rl = split('#', getUserConfiguration('RESTOREFROM'));
				$bl[0] = substr($bl[0], 4);
				$bl[0] = substr($bl[0], 0, -4);
				$rl[0] = substr($rl[0], 4);
				$rl[0] = substr($rl[0], 0, -4);

				my %deviceDetails = ('device_id' => $bl[0]);
				unless (Common::renameDevice(\%deviceDetails, $bl[1], $AppConfig::dashbtask)) {
					$errMsg = 'failed_to_rename_backup_location';
				}
				elsif ($bl[0] eq $rl[0]) {
					$userConfig[0]->{'RESTOREFROM'} = ($AppConfig::deviceIDPrefix .
						$deviceDetails{'device_id'} .$AppConfig::deviceIDSuffix ."#" . $bl[1]);
					loadNotifications() and setNotification('register_dashboard') and saveNotifications();
				}
			}
			elsif (exists $userConfig[0]->{'BDA'} and int($userConfig[0]->{'BDA'}) and Common::isLoggedin()) {
				my $cmd = sprintf("%s %s 1 1 1>/dev/null 2>/dev/null &", $AppConfig::perlBin, Common::getScript('logout', 1));
				$cmd = Common::updateLocaleCmd($cmd);
				`$cmd`;
			}

			if (!$ic && $userConfig[0]->{'SHOWHIDDEN'} ne getUserConfiguration('SHOWHIDDEN')) {
				Common::removeBKPSetSizeCache('backup');
				Common::removeBKPSetSizeCache('localbackup');
				sendInitialFilesetUpdate('backup');
				sendInitialFilesetUpdate('localbackup');
				updateFileSetSize('backup');
				updateFileSetSize('localbackup');
			}

			if (($errMsg eq '') and setUserConfiguration(@userConfig) and
				saveUserConfiguration(($ic > -1) ? $ic : 0)) {
				$status{'status'} = AppConfig::SUCCESS;
			}
			elsif ($AppConfig::errorMsg ne '') {
				if ($AppConfig::errorMsg eq 'settings_were_not_changed') {
					$status{'warnings'} = $AppConfig::errorMsg;
				}
				else {
					$status{'errmsg'} = $AppConfig::errorMsg;
				}
				$AppConfig::errorMsg = undef;
			}
			else {
				$status{'errmsg'} = $errMsg;
			}

			return 1 if ($ic);

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%status)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'get_logs' => sub {
			my %data = ();
			my $l = ();
			my ($startDate, $endDate) = Common::getStartAndEndEpochTime(1);
			foreach my $job (keys %AppConfig::availableJobsSchema) {
				$l = Common::selectLogsBetween(undef,
				 	$startDate,
					$endDate,
					(Common::getJobsPath($job) . "/$AppConfig::logStatFile"));
				foreach($l->Keys) {
					$data{'logs'}{$_} = $l->FETCH($_);
					$data{'logs'}{$_}{'type'} = $job;
				}
			}

			$data{'status'} = AppConfig::SUCCESS;

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1014'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%data)),
				#'119' => 1,
				'116' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'get_log' => sub {
			my %logData = ();
			my $logFile = getCatfile(Common::getJobsPath($content->{'type'}, 'logs'), $content->{'filename'});

			if (-f $logFile) {
				my $logContentCmd = Common::updateLocaleCmd("tail -n30 '$logFile'");
				my @logContent = `$logContentCmd`;

				my $copyFileLists = 0;
				my $copySummary   = 0;

				$logData{'status'} = AppConfig::SUCCESS;

				foreach (@logContent) {
					if (!$copySummary and substr($_, 0, 8) eq 'Summary:') {
						$copySummary = 1;
					}
					elsif (!$copyFileLists and substr($_, 0, 1) eq '[') {
						$copyFileLists = 1;
					}

					if ($copySummary) {
						if ($_ =~ m/^Backup End Time/) {
							my @startTime = localtime((split('_', $content->{'filename'}))[0]);
							my $et = localtime(mktime(@startTime));
							$logData{'summary'} .= sprintf("Backup Start Time: %s\n", $et);
						}
						elsif ($_ =~ m/Restore End Time/) {
							my @startTime = localtime((split('_', $content->{'filename'}))[0]);
							my $et = localtime(mktime(@startTime));
							$logData{'summary'} .= sprintf("Restore Start Time: %s\n", $et);
						}
						elsif ($_ =~ m/End Time/) {
							my @startTime = localtime((split('_', $content->{'filename'}))[0]);
							my $et = localtime(mktime(@startTime));
							$logData{'summary'} .= sprintf("Start Time: %s\n", $et);
						}

						$logData{'summary'} .= $_;
					}
					elsif ($copyFileLists) {
						# $logData{'details'} .= $_;
					}
				}

				# my $notemsg = Common::getLocaleString('files_in_trash_may_get_restored_notice');
				# $logData{'summary'} =~ s/$notemsg//gs;

				my $logheadCmd = Common::updateLocaleCmd("head -n20 '$logFile'");
				my @loghead = `$logheadCmd`;
				$logData{'details'}	= Common::getLocaleString('version_cc_label') . $AppConfig::version . "\n";
				$logData{'details'} .= Common::getLocaleString('release_date_cc_label') . $AppConfig::releasedate . "\n";
				foreach(@loghead) {
					last if (substr($_, 0, 8) eq 'Summary:');
					$logData{'details'} .= $_;
				}
			}
			else {
				$logData{'status'} = AppConfig::FAILURE;
				$logData{'errmsg'} = ($content->{'filename'} . ' not_found');
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%logData)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'delete_log' => sub {
			my %logData = ();
			if (Common::deleteLog($content->{'type'}, $content->{'filename'}, $content->{'status'})) {
				$logData{'status'} = AppConfig::SUCCESS;
			}
			else {
				$logData{'status'} = AppConfig::FAILURE;
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%logData)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'get_settings' => sub {
			my %settings = ();
			my $fullExcludeListFile = getCatfile(getUserProfilePath(), $AppConfig::fullExcludeListFile);
			$settings{'fullExclude'} = '';
			$settings{'fullExclude'} = getFileContents("$fullExcludeListFile.info") if (-f "$fullExcludeListFile.info");

			my $partialExcludeListFile = getCatfile(getUserProfilePath(), $AppConfig::partialExcludeListFile);
			$settings{'partialExclude'} = '';
			$settings{'partialExclude'} = getFileContents("$partialExcludeListFile.info") if (-f "$partialExcludeListFile.info");

			my $regexExcludeListFile = getCatfile(getUserProfilePath(), $AppConfig::regexExcludeListFile);
			$settings{'regexExclude'} = '';
			$settings{'regexExclude'} = getFileContents("$regexExcludeListFile.info") if (-f "$regexExcludeListFile.info");

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1015'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%settings)),
				#'119' => 1,
				'116' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			syncFilesetSizeWithFork('backup');
			syncFilesetSizeWithFork('localbackup');
			return 1;
		},

		'save_settings' => sub {
			my $fullExcludeListFile = getCatfile(getUserProfilePath(), $AppConfig::fullExcludeListFile);
			my $partialExcludeListFile = getCatfile(getUserProfilePath(), $AppConfig::partialExcludeListFile);
			my $regexExcludeListFile = getCatfile(getUserProfilePath(), $AppConfig::regexExcludeListFile);
			my $fileContent = '';

			if (defined $content->{'settings'}{'fullExclude'}) {
				Common::fileWrite("$fullExcludeListFile.info", $content->{'settings'}{'fullExclude'});
				foreach (split(/\n/, $content->{'settings'}{'fullExclude'})) {
					next if ($_ eq 'enabled' or $_ eq 'disabled');
					$fileContent .= "$_\n";
				}
				Common::fileWrite($fullExcludeListFile, $fileContent);
			}
			if (defined $content->{'settings'}{'partialExclude'}) {
				$fileContent = '';
				Common::fileWrite("$partialExcludeListFile.info", $content->{'settings'}{'partialExclude'});
				foreach (split(/\n/, $content->{'settings'}{'partialExclude'})) {
					next if ($_ eq 'enabled' or $_ eq 'disabled');
					$fileContent .= "$_\n";
				}
				Common::fileWrite($partialExcludeListFile, $fileContent);
			}
			if (defined $content->{'settings'}{'regexExclude'}) {
				$fileContent = '';
				Common::fileWrite("$regexExcludeListFile.info", $content->{'settings'}{'regexExclude'});
				foreach (split(/\n/, $content->{'settings'}{'regexExclude'})) {
					next if ($_ eq 'enabled' or $_ eq 'disabled');
					$fileContent .= "$_\n";
				}
				Common::fileWrite($regexExcludeListFile, $fileContent);
			}

			Common::removeBKPSetSizeCache('backup');
			Common::removeBKPSetSizeCache('localbackup');
			sendInitialFilesetUpdate('backup');
			sendInitialFilesetUpdate('localbackup');
			updateFileSetSize('backup');
			updateFileSetSize('localbackup');

			if ($ic) {
				return 1 if ($ic < 0);
				loadNotifications() and setNotification('get_settings') and saveNotifications();
				return 1;
			}

			my %status = (
				'status' => AppConfig::SUCCESS,
			);
			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%status)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'send_error_report' => sub {
			my $cmd = ("$AppConfig::perlBin " . Common::getScript('send_error_report', 1));
			$cmd   .= (' \'' . $content->{"username"} . '\' \'' . $content->{"emailids"} . '\' \'' . $content->{"phone"} . '\'');
			$cmd   .= (' \'' . $content->{'ticketid'} . '\' \'' . $content->{"message"} . '\'');

			my %status;
			$cmd = Common::updateLocaleCmd($cmd);
			unless (system($cmd) == 0) {
				$status{'status'} = AppConfig::FAILURE
			}
			else {
				$status{'status'} = AppConfig::SUCCESS
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%status)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'remote_install' => sub {
			my $cmd = sprintf("%s %s silent &", $AppConfig::perlBin, Common::getScript('check_for_update', 1));
			$cmd = Common::updateLocaleCmd($cmd);

			my %status;
			unless (system($cmd) == 0) {
			$status{'status'} = AppConfig::FAILURE;
			}
			else {
				$status{'status'} = AppConfig::SUCCESS;
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%status)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'get_scheduler' => sub {
			my %scheduler = ();
			if (Common::loadCrontab(getUsername())) {
				%scheduler = %{Common::getCrontab()};
				if (exists $scheduler{$AppConfig::mcUser} and exists $scheduler{$AppConfig::mcUser}{getUsername()}) {
					%scheduler = (
						getUsername() => $scheduler{$AppConfig::mcUser}{getUsername()}
					);
				}
				else {
					%scheduler = ();
				}
			}

			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1016'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%scheduler)),
				#'119' => 1,
				'116' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);

			return 1;
		},

		'save_scheduler' => sub {
			my $status = AppConfig::FAILURE;
			my $jt;
			my $fileset;
			my $errmsg = '';
			my $warnings = '';
			my %e;
			if (Common::checkCRONServiceStatus() != Common::CRON_RUNNING) {
				$errmsg = 'IDrive_cron_service_is_stopped';
			}
			elsif (exists $content->{'crontab'}{getUsername()} and Common::loadCrontab()) {
				foreach my $jobType (keys %{$content->{'crontab'}{getUsername()}}) {
					last if ($errmsg ne '');

					if ($jobType eq 'archive' and getUserConfiguration('DEDUP') eq 'off' and getUserConfiguration('BACKUPTYPE') =~ /relative/) {
						$warnings = 'no_archive_for_relative_backup_type';
						next;
					}

					foreach my $jobName (keys %{$content->{'crontab'}{getUsername()}{$jobType}}) {
						# if backup set is empty don't update the schedule
						$jt = $jobType;
						$jt = 'localbackup' if ($jobName eq 'local_backupset');
						$jt = 'backup' if ($jt eq 'archive');
						if (exists $AppConfig::availableJobsSchema{$jt}) {
							$fileset = Common::getJobsPath($jt, 'file');
							unless (-f $fileset and !-z $fileset) {
								$warnings = "$jobName: backup set is empty\n";
								if (exists $content->{'crontab'}{getUsername()}{$jobType}{$jobName}{'settings'} and
								exists $content->{'crontab'}{getUsername()}{$jobType}{$jobName}{'settings'}{'frequency'} and
								$content->{'crontab'}{getUsername()}{$jobType}{$jobName}{'settings'}{'frequency'} eq 'immediate') {
									next;
								}
							}
						}

						unless (Common::setCrontab($jobType, $jobName, $content->{'crontab'}{getUsername()}{$jobType}{$jobName})) {
							Common::createCrontab($jobType, $jobName);
							Common::setCrontab($jobType, $jobName, $content->{'crontab'}{getUsername()}{$jobType}{$jobName});
						}

						#Checking if another job is already in progress
						if (Common::getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'immediate') {
							my $isJobRunning = Common::isJobRunning($jobName);
							if ($isJobRunning) {
								# need to return error message to dashboard.
debug('backup_job_is_already_in_progress_try_again');
								$status = AppConfig::FAILURE;
								$errmsg = 'Job_is_already_in_progress_Please_try_again';
								last;
							}
						}
						%e = Common::setCronCMD($jobType, $jobName);
						if ($e{'status'} eq AppConfig::FAILURE) {
							$status = AppConfig::FAILURE;
							$errmsg = $e{'errmsg'} || '';
							last;
						}
					}
				}

				if ($errmsg eq '') {
					$status = AppConfig::SUCCESS;
					Common::saveCrontab((($ic > -1) ? $ic : 0));
				}
			}
			return 1 if ($ic);

			my %s = (
				'status' => $status,
				'errmsg' => $errmsg,
				'warnings' => $warnings,
			);
			my $params = Idrivelib::get_dashboard_params({
				'0'   => '2',
				'1017'=> $data->{1017},
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'130' => zlibCompress(to_json(\%s)),
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);
			return 1;
		},

		'alert_status_update' => sub {
			my $entAC = lc(getUserConfiguration('PLANTYPE') . getUserConfiguration('PLANSPECIAL'));
			if ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true') or ($entAC =~ /business/)) {
				my $backupLocation = getUserConfiguration('BACKUPLOCATION');
				if (getUserConfiguration('DEDUP') eq "on") {
					$backupLocation = (split("#", $backupLocation))[1];
				}

				my $params = Idrivelib::get_dashboard_params({
					'0'   => '3',
					'109' => (
						($entAC =~ /business/) ? getUsername() : getUserConfiguration('PARENTACCOUNT')
					),
					'106' => getUsername(),
					'112' => Common::getMachineUID(0),
					'108' => hostname,
					'107' => getMachineUser(),
					'110' => $backupLocation,
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'121' => (time() + $at) . '_' . int(getUserConfiguration('DDA')),
					'124' => sprintf("<item type=\"%d\" errcode=\"%s\"/>", (split('', $content->{'notification_value'}))[0], $content->{'notification_value'}),
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$params->{host} = getParentRemoteManageIP();
				$params->{host} = getRemoteManageIP() if ($entAC =~ /business/);
				$params->{method} = 'POST';
				$params->{json} = 1;
				my $response = request($params);
debug('update alert status' . __LINE__);
			}
			return 1;
		},

		'update_device_info' => sub {
			my @deviceInfo = split('-', $content->{'notification_value'});
			my $params = Idrivelib::get_dashboard_params({
				'0'   => '15',
				'1018'=> getUsername(),
				'107' => $deviceInfo[2],
				'112' => $deviceInfo[0],
				'147' => $deviceInfo[1],
				'148' => (time() + $at),
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);
			unless ($deviceInfo[3] eq 'n') {
				$deviceInfo[0] =~ s/$AppConfig::deviceUIDPrefix//g;
				restoreBackupset($deviceInfo[0], $deviceInfo[2]);
				restoreLocalBackupset($deviceInfo[0], $deviceInfo[2]);
				restoreSchduledJobs($deviceInfo[0], $deviceInfo[2]);
				restoreUserSettings($deviceInfo[0], $deviceInfo[2]);
				restoreSettings($deviceInfo[0], $deviceInfo[2]);

				return 1;
			}

			return -1;
		}
	);

	$activity{'send_error_msg'} = sub {
		my %s = (
			'status' => AppConfig::FAILURE,
			'errmsg' => ("unable_to_" . $content->{'channel'}),
			'warnings' => $_[0],
		);
		my $params = Idrivelib::get_dashboard_params({
			'0'   => '2',
			'1017'=> $data->{1017},
			'111' => $AppConfig::evsVersion,
			'113' => lc($AppConfig::deviceType),
			'130' => zlibCompress(to_json(\%s)),
			#'119' => 1,
			'101' => $at
		}, 1, 0);
		$params->{host} = getRemoteManageIP();
		#$params->{port} = $AppConfig::NSPort;
		$params->{method} = 'POST';
		$params->{json} = 1;
		my $response = request($params);
		return 1;
	};

	$activity{'update_acc_status'} = sub {
		my $c = sprintf("<item disable=\"%d\" block=\"%d\" hiddenFlag=\"0\"/>", getUserConfiguration('DDA'), getUserConfiguration('BDA'));
		my $params = Idrivelib::get_dashboard_params({
			'0'   => '2',
			'1000'=> (getUsername() . Common::getMachineUID(0) . getMachineUser()),
			'111' => $AppConfig::evsVersion,
			'113' => lc($AppConfig::deviceType),
			'130' => $c,
			'116' => 1,
			#'119' => 1,
			'101' => $at
		}, 1, 0);
		$params->{host} = getRemoteManageIP();
		#$params->{port} = $AppConfig::NSPort;
		$params->{method} = 'POST';
		$params->{json} = 1;
		my $response = request($params);
		return 1;
	};

	$activity{'save_backupset_content'} = sub {
		return $activity{'save_fileset_content'}('backup');
	};

	$activity{'save_localbackupset_content'} = sub {
		return $activity{'save_fileset_content'}('localbackup');
	};

	$activity{'get_backupset_content'} = sub {
		return $activity{'get_fileset_content'}('backup', '1007');
	};

	$activity{'get_localbackupset_content'} = sub {
		return $activity{'get_fileset_content'}('localbackup', '1008');
	};

	$activity{'start_backup'} = sub {
		my $errmsg = '';
		my %ArchJobDetails = Common::getRunningJobs('archive');
		$errmsg = 'archive_cleanup_is_in_progress_please_try_again_later' if (%ArchJobDetails);
		return $activity{'start_job'}('backup_scripts', 'dashboard', $errmsg);
	};

	$activity{'stop_backup'} = sub {
		return $activity{'stop_job'}('backup');
	};

	$activity{'start_localbackup'} = sub {
		return $activity{'start_job'}('express_backup', 'dashboard');
	};

	$activity{'stop_localbackup'} = sub {
		return $activity{'stop_job'}('localbackup');
	};

	$activity{'start_restore'} = sub {
		my @userConfig = ($content->{'user_settings'});
		if (exists $content->{'user_settings'} and setUserConfiguration(@userConfig)
				and saveUserConfiguration(0)) {
		}
		$activity{'save_fileset_content'}('restore', 1);
		return $activity{'start_job'}('restore_script', 'dashboard');
	};

	$activity{'stop_restore'} = sub {
		return $activity{'stop_job'}('restore');
	};

	$activity{'update_backup_activity'} = sub {
		return $activity{'update_progress_details'}('backup', '1009', 0, 1);
	};

	$activity{'update_backup_progress'} = sub {
		return $activity{'update_progress_details'}('backup', '1009', 1);
	};

	$activity{'update_localbackup_progress'} = sub {
		return $activity{'update_progress_details'}('localbackup', '1010');
	};

	$activity{'update_restore_progress'} = sub {
		return $activity{'update_progress_details'}('restore', '1011');
	};

	if ($content->{'channel'} and $activity{$content->{'channel'}}) {
debug("CHANNEL: $content->{'channel'}");

		my $uConfStatus = Common::loadUserConfiguration();
		if (defined($_[1]) and $_[1]) {
			if (($uConfStatus != 1) and ($content->{'channel'} ne 'connect')) {
				my $errMsg = '';
				$errMsg = $AppConfig::errorDetails{$uConfStatus} if (exists $AppConfig::errorDetails{$uConfStatus});
debug("error msg $errMsg ");
				return $activity{'send_error_msg'}($errMsg);
			}
		}
		my $actStatus = 0;
		eval {
			$actStatus = $activity{$content->{'channel'}}();
			1;
		} or do {
			$actStatus = 0;
			if ($@) {
				Common::traceLog("Exception: $@");
			}
			else {
				Common::traceLog("Uncaught exception");
			}
		};
		return $actStatus;
	}
	elsif (defined($_[2]) and $_[2]) {
		return 1;
	}

	Common::traceLog('CHANNEL: ' . ($content->{'channel'} || '') . ' not defined');
	return 0;
}

#*****************************************************************************************************
# Subroutine			: syncFilesetSizeWithFork
# Objective				: Helps to push sizes to the notification server with separate process
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub syncFilesetSizeWithFork {
	my $backuptype = $_[0];
	return 0 unless ($backuptype);

	my $bsf = Common::getJobsPath($backuptype, 'file');
	return 0 if (!-f $bsf || !-s $bsf);
	my $backupsizesynclock = Common::getBackupsetSizeSycnLockFile($backuptype);
	return 0 if (Common::isFileLocked($backupsizesynclock));

	my $syncforkid = fork();
	if ($syncforkid == 0) {
		$0 = 'IDrive:dashboard:sy';
		syncFilesetSizeOnIntervals($backuptype);
		exit(0);
	}

	push(@others, $syncforkid) if ($syncforkid);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: syncFilesetSizeOnIntervals
# Objective				: Helps to push sizes to the notification server with available data | has to be called only from a forked child
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub syncFilesetSizeOnIntervals {
	my $backuptype = $_[0];
	exit(0) unless ($backuptype);

	my $bsf = Common::getJobsPath($backuptype, 'file');
	exit(0) if (!-f $bsf || -s $bsf == 0);

	my $backupsizesynclock = Common::getBackupsetSizeSycnLockFile($backuptype);
	exit(0) if (Common::isFileLocked($backupsizesynclock));

	Common::fileLock($backupsizesynclock);

	my $lastts = $AppConfig::sizepollintvl;
	my %backupsetsizes = ();
	my %syncdata;
	my $rid = '1007';
	$rid = '1008' if ($backuptype eq 'localbackup');

	my $backupsetdata = getFileContents($bsf, 'array');
	my ($processingreq, %notifsizes) = Common::getBackupsetFileSize($backupsetdata);
	my $itemCount = Common::getBackupsetItemCount($bsf);
	my $processeditemcount = Common::getBackupsetFileAndMissingCount($bsf);
	my ($prevprocessedcount, $prepolltime) = (0, 0);

	while(1) {
		end() unless(Common::isFileLocked($selfPIDFile));
		if (!-f "$bsf.json") {
			sleep(2);
			next;
		}

		%backupsetsizes = (-f "$bsf.json")? %{JSON::from_json(getFileContents("$bsf.json"))} : ();
		$processeditemcount = Common::updateDirSizes(\%backupsetsizes, \%notifsizes, $processeditemcount);

		$syncdata{'status'} = AppConfig::SUCCESS;
		$syncdata{'ts'} = mktime(localtime);
		$syncdata{'files'} = {%notifsizes};
		if ($prepolltime < 60) {
			$AppConfig::sizepollintvl = 3;
			$prepolltime += 0.1;
		}
		elsif ($prepolltime < 120) {
			$AppConfig::sizepollintvl = 5;
			$prepolltime += 0.1;
		}

		if ($prevprocessedcount != $processeditemcount and ($lastts >= $AppConfig::sizepollintvl || $itemCount <= $processeditemcount)) {
			$prevprocessedcount = $processeditemcount;
			if ($prepolltime < 120) {
				my $scontent = to_json(\%syncdata);
				my $params = Idrivelib::get_dashboard_params({
					'0'   => '2',
					$rid  => (getUsername() . Common::getMachineUID(0) . getMachineUser()),
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					'130' => zlibCompress($scontent),
					'116' => 1,
					#'119' => 1,
					'101' => $at
				}, 1, 0);

				$params->{host} = getRemoteManageIP();
				#$params->{port} = $AppConfig::NSPort;
				$params->{method} = 'POST';
				$params->{json} = 1;
				my $response = request($params);
			}
			else {
				loadNotifications() and setNotification(sprintf("get_%sset_content", $backuptype)) and saveNotifications();
			}

			$lastts = 0;
		}

		if ($itemCount <= $processeditemcount) {
			# other browsers will not come to know about the changes
			if ($prepolltime < 120) {
#				loadNotifications() and setNotification(sprintf("get_%sset_content", $backuptype)) and saveNotifications();
			}

			$AppConfig::sizepollintvl = 5;
			unlink($backupsizesynclock);
			exit(0);
		}

		#select(undef, undef, undef, 0.1);
		Common::sleepForMilliSec(500); # Sleep for 100 milliseconds
		$lastts += 0.1;
	}
}

#*****************************************************************************************************
# Subroutine			: sendInitialFilesetUpdate
# Objective				: Helps to poll the notification server with initial set of available data
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub sendInitialFilesetUpdate {
	my $bsf = getCatfile(Common::getJobsPath($_[0]), $AppConfig::backupsetFile);
	my $processingreq = 0;
	my %notifsizes;
	if (-f $bsf and -s $bsf > 0) {
		my $backupsetdata = getFileContents($bsf, 'array');
		($processingreq, %notifsizes) = Common::getBackupsetFileSize($backupsetdata);

		my $rid = '1007';
		$rid = '1008' if ($_[0] eq 'localbackup');

		my %syncdata;
		$syncdata{'status'} = AppConfig::SUCCESS;
		$syncdata{'ts'} = mktime(localtime);
		$syncdata{'files'} = {%notifsizes};
		my $scontent = to_json(\%syncdata);
		my $params = Idrivelib::get_dashboard_params({
			'0'   => '2',
			$rid  => (getUsername() . Common::getMachineUID(0) . getMachineUser()),
			'111' => $AppConfig::evsVersion,
			'113' => lc($AppConfig::deviceType),
			'130' => zlibCompress($scontent),
			'116' => 1,
			#'119' => 1,
			'101' => $at
		}, 1, 0);

		$params->{host} = getRemoteManageIP();
		#$params->{port} = $AppConfig::NSPort;
		$params->{method} = 'POST';
		$params->{json} = 1;

		my $response = request($params);
	}
}

#*****************************************************************************************************
# Subroutine			: updateFileSetSize
# Objective				: Helps to poll the notification server with requested backup set sizes
# Added By				: Sabin Cheruvattil
# Modified By			: Deepak Chaurasia
#****************************************************************************************************/
sub updateFileSetSize {
	my %dirsizes = ();
	my $backuptype = $_[0];
	return 0 unless ($backuptype);

	my $backupsizelock = Common::getBackupsetSizeLockFile($backuptype);

	my $bsf = Common::getJobsPath($backuptype, 'file');
	return 0 if (!-f $bsf || !-s $bsf);

	my $forkpid = fork();
	if ($forkpid == 0) {
		$0 = 'IDrive:dashboard:fs';

		my $calcforkpid = fork();
		if ($calcforkpid == 0) {
			$0 = 'IDrive:dashboard:cc';
			Common::calculateBackupsetSize($backuptype, $selfPIDFile) unless (Common::isFileLocked($backupsizelock, 1));
			exit(0);
		}

		push(@others, $calcforkpid) if ($calcforkpid);

		syncFilesetSizeOnIntervals($backuptype);
	}

	push(@others, $forkpid);
	return (defined($forkpid)? 1 : 0);
}

#*****************************************************************************************************
# Subroutine			: watchDashboardActivities
# Objective				: Watch for dashboard activities
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub watchDashboardActivities {
	my $pid = fork();

	unless (defined $pid) {
		Common::retreat('Unable to fork');
	}

	unless ($pid) {
		$0 = 'IDrive:dashboard:da';

		my $host = (getRemoteManageIP());
		my $subscribe = 1;
		my ($response, $param);

	  my $c   = (getUsername() . Common::getMachineUID(0) . getMachineUser() . $_[0]);
		my $rmip= getRemoteManageIP();
		while(1) {
			end() if ((getppid() == 1) or (!Common::isFileLocked($selfPIDFile)));
debug('watchDashboardActivities');
			if ($subscribe) {
				$param = Idrivelib::get_dashboard_params({
					'0'   => '11',
					'1017'=> $c,
					'102' => 1,
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$param->{host} = $rmip;
				$param->{port} = $AppConfig::NSPort;
				$param->{method} = 'POST';
				$param->{json} = 1;
				$response = request($param);
				if (($response->{'DATA'}) and (reftype($response->{'DATA'}) eq 'ARRAY')) {
					$response->{'DATA'}[0] = Idrivelib::get_dashboard_params($response->{'DATA'}[0], 0, 0);
					$response->{'DATA'}[0] = $response->{'DATA'}[0]{'data'};
					$response->{'DATA'}[0]{1017} = (getUsername() . Common::getMachineUID(0) . getMachineUser() . $_[0]);

					if ($response->{'DATA'}[0]{'type'} eq 'data') {
						if (startActivity($response->{'DATA'}[0], 1)) {
						}
					}
				}
				$subscribe = 0;
			}
			else {
				$param = Idrivelib::get_dashboard_params({
					'0'   => '14',
					'1017'=> $c,
					'102' => 1,
					'111' => $AppConfig::evsVersion,
					'113' => lc($AppConfig::deviceType),
					#'119' => 1,
					'101' => $at
				}, 1, 0);
				$param->{host} = $rmip;
				$param->{port} = $AppConfig::NSPort;
				$param->{method} = 'POST';
				$param->{json} = 1;
				$response = request($param);
#debug(Common::encryptString(zlibCompress(Dumper($response))));
				if (($response->{'DATA'}) and (reftype($response->{'DATA'}) eq 'HASH')) {
					$response = Idrivelib::get_dashboard_params($response->{'DATA'}, 0, 0);
					$response = $response->{'data'};
					$response->{1017} = (getUsername() . Common::getMachineUID(0) . getMachineUser() . $_[0]);
					startActivity($response, 1);
					$subscribe = 0;
				}
		}

			Common::killPIDs(\@others, 0);
		}

		exit(0);
	}

	return $pid;
}
#*****************************************************************************************************
# Subroutine			: removeDeviceInfo
# Objective				: Remove the given device info from browsers section
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub removeDeviceInfo {
	my $params = Idrivelib::get_dashboard_params({
		'0'   => '15',
		'1018'=> getUsername(),
		'107' => $_[0]->{'pname'},
		'112' => $_[0]->{'mid'},
		'120' => 1,
		'147' => $_[0]->{'did'},
		'148' => (time() + $at),
		'101' => $at
	}, 1, 0);
	$params->{host} = getRemoteManageIP();
	$params->{method} = 'POST';
	$params->{json} = 1;
	return request($params);
}

#*****************************************************************************************************
# Subroutine			: watchDashboardLoginActivity
# Objective				: Watch for dashboard login activity
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub watchDashboardLoginActivity {
	my $pid = fork();

	unless (defined $pid) {
		Common::retreat('Unable to fork');
	}

	unless ($pid) {
		$0 = 'IDrive:dashboard:la';

		my $params;
		my $response;
		my %data;
		my (@temp);
		my (%activeBrowsers, %bt);
		my ($res, $td, $did);
		my $browsersCount = -1;
		my $muname = getMachineUser();
		my $UCMTS  = stat(Common::getUserConfigurationFile())->mtime;
		my $userConfigMTS = $UCMTS;
		while(1) {
			end() if ((getppid() == 1) or (!Common::isFileLocked($selfPIDFile)));
			$UCMTS = stat(Common::getUserConfigurationFile())->mtime if (-f Common::getUserConfigurationFile());
			if ($userConfigMTS != $UCMTS) {
				$userConfigMTS = $UCMTS;
				Common::loadUserConfiguration();
			}
			$params = Idrivelib::get_dashboard_params({
				'0'   => '11',
				'1018'=> getUsername(),
				'102' => 1,
				'111' => $AppConfig::evsVersion,
				'113' => lc($AppConfig::deviceType),
				'116' => 1,
				#'119' => 1,
				'101' => $at
			}, 1, 0);
			$params->{host} = getRemoteManageIP();
			#$params->{port} = $AppConfig::NSPort;
			$params->{method} = 'POST';
			$params->{json} = 1;
			my $response = request($params);
debug('watch for dashboard login ' . __LINE__);

			$bt{'count'} = 0;
			$bt{'stage'} = 0;

			if ($response->{'DATA'} and exists $response->{'DATA'}{'content'}) {
				if (exists $response->{'DATA'}{'content'}{'device'}) {
					$did = (split('#', getUserConfiguration('BACKUPLOCATION')))[0];
					$did =~ s/^$AppConfig::deviceIDPrefix//;
					$did =~ s/$AppConfig::deviceIDSuffix$//;
					foreach (@{$response->{'DATA'}{'content'}{'device'}}) {
						if (($_->{'mid'} eq Common::getMachineUID()) and ($_->{'did'} eq $did)) {
							Common::traceLog('backup_location_is_adopted_by_another_machine');
							Common::loadCrontab();
							Common::setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
							Common::saveCrontab(0);
							removeDeviceInfo($_);
							my $cmd = sprintf("%s %s 1 0", $AppConfig::perlBin, Common::getScript('logout', 1));
							$cmd = Common::updateLocaleCmd($cmd);
							`$cmd`;
							setUserConfiguration('BACKUPLOCATION', '');
							saveUserConfiguration(0, 1);
							Common::stopDashboardService($AppConfig::mcUser, Common::getAppPath());
							end();
						}
						elsif (($_->{'dtime'} ne '') and (time() - $_->{'dtime'}) >= 604800) {
							removeDeviceInfo($_);
						}
					}
				}
				if (exists $response->{'DATA'}{'content'}{'browser'}) {
					foreach (@{$response->{'DATA'}{'content'}{'browser'}}) {
						$td = ((time() + $at) - $_->{'time'});
						next if ($td >= 300);

						$bt{'stage'} = 1;
						if ($_->{'stage'} eq (Common::getMachineUID(0) . getMachineUser())) {
							$bt{'count'}++;
							$bt{$_->{'bid'}} = '';
							if (exists $activeBrowsers{$_->{'bid'}}) {
								$activeBrowsers{$_->{'bid'}}{'time'} = $_->{'time'};
								next;
							}

							$activeBrowsers{$_->{'bid'}}{'pid'} = watchDashboardActivities($_->{'bid'});
							$activeBrowsers{$_->{'bid'}}{'time'}= $_->{'time'};
debug("starting activity for browser $_->{'bid'} $activeBrowsers{$_->{'bid'}}{'pid'}");
						}
					}
				}
			}

			for my $browserID (keys %activeBrowsers) {
				$res = waitpid($activeBrowsers{$browserID}{'pid'}, WNOHANG);
				if ($res == -1 || $res > 0) {
debug("activity for browser $browserID $activeBrowsers{$browserID}{'pid'} has stopped");
					delete $activeBrowsers{$browserID};
					next;
				}

				$td = ((time() + $at) - $activeBrowsers{$browserID}{'time'});
				if (($td >= 300) and (($bt{'count'} == 0) or not exists $bt{$browserID})) {
					if ($td >= 300) {
debug("stoping activity for browser $browserID $activeBrowsers{$browserID}{'pid'}");
						eval {kill 9, $activeBrowsers{$browserID}{'pid'};};
						if ($@) {
							Common::traceLog("unable to kill pid: " . $activeBrowsers{$browserID}{'pid'});
							Common::traceLog("Error: $@");
						}
					}
					else {
						$bt{'stage'} = 1;
						$bt{'count'}++;
						$bt{$browserID} = '';
					}
				}
				push(@activities, $activeBrowsers{$browserID}{'pid'});
			}
debug('bt data: ' . Dumper(\%bt));

			if ($bt{'stage'}) {
				if (int(getFileContents(getCatfile(getUserProfilePath(), 'stage.txt'))) != $bt{'stage'}) {
					Common::fileWrite2(getCatfile(getUserProfilePath(), 'stage.txt'), '1');
				}
			}
			elsif (int(getFileContents(getCatfile(getUserProfilePath(), 'stage.txt'))) > 0) {
				Common::fileWrite2(getCatfile(getUserProfilePath(), 'stage.txt'), '0');
			}

			if ($bt{'count'} != $browsersCount) {
				if (open(my $b, '>', getCatfile(getUserProfilePath(), 'browsers.txt'))) {
					print $b $bt{'count'};
					close($b);
					$browsersCount = $bt{'count'};
				}
			}

			# TODO: IMPORTANT we need kill progress when no login users.
			Common::killPIDs(\@progressPIDs, 0);

			if ($bt{'stage'}) {
				sleep(4);
			}
			else {
				sleep(9);
			}
		}
		exit(0);
	}

	push @systemids, $pid;
	return 1;
}

#*****************************************************************************************************
# Subroutine			: end
# Objective				: Kill all process before this script exit
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub end {
	while(scalar @systemids > 0) {
		Common::killPIDs(\@systemids);
	}
	while(scalar @progressPIDs > 0) {
		Common::killPIDs(\@progressPIDs);
	}
	while(scalar @activities > 0) {
		Common::killPIDs(\@activities);
	}
	while(scalar @others > 0) {
		Common::killPIDs(\@others);
	}
	if (sprintf("%d%d", getppid(), $$) == $dashboardPID) {
		updateSystemIsOffline(getUsername());
		unlink($selfPIDFile);
	}
	exit(0);
}

1;
