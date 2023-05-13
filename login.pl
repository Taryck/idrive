#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to login to your user account.
#
# Created By: Anil Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;
use File::Basename;

Common::waitForUpdate();
Common::initiateMigrate();

init();

#*****************************************************************************************************
# Subroutine		: init
# Objective			: This function is entry point for the script
# Added By			: Anil Kumar
# Modified By		: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub init {
	my $isAccountConfigured = 0;
	system(Common::updateLocaleCmd("clear"))	and Common::retreat('Failed to Clear screen');
	#Common::loadAppPath() or Common::retreat('Failed to load source Code path'); #Commented by Senthil: 25-July-2018
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::verifyVersionConfig();

	unless (Common::hasPythonBinary()) {
		Common::display(['downloading_python_binary', '... ']);
		Common::downloadPythonBinary() or Common::retreat('unable_to_download_python_binary');
		Common::display('python_binary_downloaded_successfully');
	}

	# check if user exists and login sesion is intect before loading
	if (Common::loadUsername() and Common::isLoggedin()) {
		Common::retreat('your_account_not_configured_properly') if ( Common::loadUserConfiguration() == 101);
		Common::retreat('logout_&_login_&_try_again')           if ( Common::loadUserConfiguration() == 100);

		if (Common::getUserConfiguration('DEDUP') eq 'on') {
			Common::displayHeader();
			my @result = Common::fetchAllDevices();
			unless ($result[0]->{'STATUS'} eq 'SUCCESS') {
				Common::retreat('your_account_not_configured_properly');
			}

			#Added to consider the bucket type 'D' only
			my @devices;
			foreach (@result){
				next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
				push @devices, $_;
			}

			unless (Common::findMyDevice(\@devices)) {
				Common::setUserConfiguration('BACKUPLOCATION', '');
				Common::saveUserConfiguration(0, 1);
				my $cmd = sprintf("%s %s 1 0", $AppConfig::perlBin, Common::getScript('logout', 1));
				$cmd = Common::updateLocaleCmd($cmd);
				`$cmd`;
				Common::retreat('unable_to_find_your_backup_location');
			}
		}

		Common::retreat('User "'. Common::getUsername(). '" is already logged in. Logout using logout.pl and try again.');
	}

	Common::loadUserConfiguration();
	Common::displayHeader();
	Common::unloadUserConfigurations();

	# SSO login.
	Common::display(["please_choose_the_method_to_authenticate_your_account", ":"]);
	my @options = (
		'idrive_login',
		'sso_login',
	);
	Common::displayMenu('', @options);
	my $loginType = Common::getUserMenuChoice(scalar(@options));

	# Get user name and validate
	my $uname = Common::getAndValidate(['enter_your', " ", $AppConfig::appType, " ", 'username', ': '], "username", 1);
	$uname = lc($uname); #Important
	my $emailID = $uname;

	my $loggedInUser = Common::getUsername();
	my $isLoggedin = Common::isLoggedin();

	#validate user account
	#Common::display(['verifying_your_account_info'],1);

	# Get IDrive/IBackup username list associated with email address
	$uname = Common::getUsernameList($uname) if (Common::isValidEmailAddress($uname));

	# Verify user configuration file is valid if not ask for reconfigure
	Common::setUsername($uname);
	my $errorKey = Common::loadUserConfiguration();
	unless ($errorKey) {
		Common::retreat('account_not_configured');
	}
	elsif ($errorKey == 101 or $errorKey == 104 or $errorKey == 105) {
		Common::retreat($AppConfig::errorDetails{$errorKey});
	}

	# validate IDrive user details
	my @responseData = Common::authenticateUser($uname, $emailID, 0, $loginType) or Common::retreat(['failed_to_authenticate_user',"'$uname'."]);
	my $upasswd = $responseData[0]->{'p'};

	my $switchAccount = 0;

	if ($loggedInUser && $loggedInUser ne $uname && !$isLoggedin) {
		Common::display(["\n\nSwitching user from \"", $loggedInUser , "\" to \"", $uname , "\" will stop all your running jobs and disable all your schedules for \"", $loggedInUser, "\". Do you really want to continue (y/n)?"], 1);
		my $userChoice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);

		return if(lc($userChoice) eq 'n');

		$switchAccount = 1;
		Common::display('switching_user_please_wait');
	}

	Common::setUserConfiguration('USERNAME', $uname);
	Common::saveUserQuota(@responseData) or Common::retreat("Error in save user quota");
	Common::saveServerAddress(@responseData);
	Common::setUserConfiguration(@responseData);

	#create password files
	Common::createEncodePwdFiles($upasswd);
	Common::getServerAddress();
	#Common::loadUserConfiguration() or Common::retreat('your_account_not_configured_properly');

	#configure user account for private/default key
	if (Common::getUserConfiguration('USERCONFSTAT') eq 'NOT SET') {
		my ($configType, @result);
		my $encKey = '';
		if(defined($responseData[0]->{'subacc_enckey_flag'}) and $responseData[0]->{'subacc_enckey_flag'} eq 'Y'){
			$configType = 2;
		} else {
			Common::display(["\n",'please_configure_your', ' ', $AppConfig::appType, ' ', 'account_with_encryption']);
			my @options = (
				'default_encryption_key',
				'private_encryption_key'
			);
			Common::displayMenu('', @options);
			$configType = Common::getUserMenuChoice(scalar(@options));
		}

		if ($configType == 2) {
			$encKey = Common::getAndValidate(['set_your_encryption_key', ": "], "config_private_key", 0);

			my $confirmEncKey = Common::getAndValidate(['confirm_your_encryption_key', ": "], "config_private_key", 0);

			if ($encKey ne $confirmEncKey) {
				Common::retreat('encryption_key_and_confirm_encryption_key_must_be_the_same');
			}
			Common::display('setting_up_your_encryption_key',1);
			#creating IDPVT temporarily to execute EVS commands

			Common::createUTF8File('STRINGENCODE', $encKey, Common::getIDPVTFile()) or
			Common::retreat('failed_to_create_utf8_file');

			@result = Common::runEVS();

			unless (($result[0]->{'STATUS'} eq 'SUCCESS') and ($result[0]->{'MSG'} eq 'no_stdout')) {
				Common::retreat('failed_to_encode_private_key');
			}

			$configType = 'PRIVATE';
			# Common::setUserConfiguration('ENCRYPTIONTYPE', 'PRIVATE');
			# Common::createUTF8File('PRIVATECONFIG') or Common::retreat('failed_to_create_utf8_file');
		}
		else {
			$configType = 'DEFAULT';
			# Common::setUserConfiguration('ENCRYPTIONTYPE', 'DEFAULT');
			# Common::createUTF8File('DEFAULTCONFIG') or Common::retreat('failed_to_create_utf8_file');
		}

		# @result = Common::runEVS('tree');
		# if ($result[0]->{'STATUS'} eq 'FAILURE') {
			# Common::retreat(ucfirst($result[0]->{'desc'}));
		# }
		Common::setUserConfiguration('ENCRYPTIONTYPE', $configType);
		Common::configAccount($configType,$encKey);
		Common::display('encryption_key_is_set_successfully',1);
	}
	elsif (Common::getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
		my $encKey = Common::getAndValidate(["\n", 'enter_your', " encryption key: "], "private_key", 0);
		my @responseData = ();
		Common::display('verifying_your_encryption_key',1);
		# this is to create encrypted PVT file and PVTSCH file
		Common::encodePVT($encKey);

		if (Common::getUserConfiguration('DEDUP') eq 'on') {
			@responseData = Common::fetchAllDevices();
		}
		else {
			# validate private key for no dedup account
			Common::createUTF8File('PING')  or Common::retreat('failed_to_create_utf8_file');
			@responseData = Common::runEVS();
		}
		my $rmCmd = Common::getIDPVTFile();
		my $userProfileDir  = Common::getUserProfilePath();
		if (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'encryption_verification_failed')) {
			Common::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			if(Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
				Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'pvt_verification_failed'}) and Common::saveNotifications();
				Common::unlockCriticalUpdate("notification");
			}

			Common::retreat(['invalid_enc_key']);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /$AppConfig::proxyNetworkError/i)) {
		# elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407 Proxy Authentication Required|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/)) {
			Common::retreat(["\n", 'kindly_verify_ur_proxy']);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'private_encryption_key_must_be_between_4_and_256_characters_in_length')) {
			Common::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			Common::retreat(['encryption_key_must_be_minimum_4_characters',"."]);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') && (Common::getUserConfiguration('DEDUP') eq 'on') ){
			if ($responseData[0]{'MSG'} ne 'No devices found') {
				Common::retreat(ucfirst($responseData[0]->{'MSG'}));
			}else {
				Common::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			}
		}
		Common::display(['verification_of_encryption_key_is_successfull'],1);
	}
	Common::copy(Common::getIDPVTFile(), Common::getIDPVTSCHFile());
	Common::changeMode(Common::getIDPVTSCHFile());

	if (int(Common::getUserConfiguration('BDA'))) {
		if(Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
			Common::setNotification('update_acc_status') and Common::saveNotifications();
			Common::unlockCriticalUpdate("notification");
			Common::setUserConfiguration('BDA', 0);
		}
	}

	if (Common::getUserConfiguration('DEDUP') eq 'on') {
		my @result = Common::fetchAllDevices();
		unless ($result[0]->{'STATUS'} eq 'SUCCESS') {
			Common::retreat('your_account_not_configured_properly');
		}

		#Added to consider the bucket type 'D' only
		my @devices;
		foreach (@result){
			next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
			push @devices, $_;
		}

		unless (Common::findMyDevice(\@devices)) {
			Common::setUserConfiguration('BACKUPLOCATION', '');
			Common::saveUserConfiguration(0, 1);
			my $cmd = sprintf("%s %s 1 0", $AppConfig::perlBin, Common::getScript('logout', 1));
			$cmd = Common::updateLocaleCmd($cmd);
			`$cmd`;
			Common::retreat('unable_to_find_your_backup_location');
		}
	}

	if ((Common::getUserConfiguration('DELCOMPUTER') eq 'D_1') or (Common::getUserConfiguration('DELCOMPUTER') eq '')) {
		Common::setUserConfiguration('DELCOMPUTER', 'S_1');
	}

	Common::saveUserConfiguration();

	Common::updateCronForOldAndNewUsers($loggedInUser, $uname) if($switchAccount and $AppConfig::appType eq 'IDrive');
	#create user.txt for logged in user
	Common::updateUserLoginStatus($uname,1,1);
	unlink(Common::getCDPHaltFile()) if(Common::hasFileNotifyPreReq() and -f Common::getCDPHaltFile());
	Common::setCDPInotifySupport();
	Common::startCDPWatcher(1) unless(Common::isCDPServicesRunning());
	Common::deactivateOtherUserCRONEntries($uname);
	Common::saveMigratedLog(); #Added to upload the migrated log which is not yet uploaded
	# execute the cgi to update record in mysql db
	Common::checkAndUpdateClientRecord($uname,$upasswd);
	Common::display(['dashBoard_intro_notification']) if($AppConfig::appType eq 'IDrive');
#	Common::display("\n\"".$uname .'" is logged in successfully.'."\n");
}
