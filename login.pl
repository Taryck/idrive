#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to login to your user account.
#
# Created By: Anil Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Configuration;
use File::Basename;

Helpers::waitForUpdate();
Helpers::initiateMigrate();

init();

#*****************************************************************************************************
# Subroutine		: init
# Objective			: This function is entry point for the script
# Added By			: Anil Kumar
# Modified By		: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub init {
	my $isAccountConfigured = 0;
	system(Helpers::updateLocaleCmd("clear"))	and Helpers::retreat('Failed to Clear screen');
	#Helpers::loadAppPath() or Helpers::retreat('Failed to load source Code path'); #Commented by Senthil: 25-July-2018
	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	# check if user exists and login sesion is intect before loading
	if (Helpers::loadUsername() and Helpers::isLoggedin()) {
		Helpers::retreat('your_account_not_configured_properly') if ( Helpers::loadUserConfiguration() == 101);
		Helpers::retreat('logout_&_login_&_try_again')           if ( Helpers::loadUserConfiguration() == 100);

		if (Helpers::getUserConfiguration('DEDUP') eq 'on') {
			Helpers::displayHeader();

			my @result = Helpers::fetchAllDevices();
			unless ($result[0]->{'STATUS'} eq 'SUCCESS') {
				Helpers::retreat('your_account_not_configured_properly');
			}

			#Added to consider the bucket type 'D' only
			my @devices;
			foreach (@result){
				next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
				push @devices, $_;
			}

			unless (Helpers::findMyDevice(\@devices)) {
				Helpers::setUserConfiguration('BACKUPLOCATION', '');
				Helpers::saveUserConfiguration(0, 1);
				my $cmd = sprintf("%s %s 1 0", $Configuration::perlBin, Helpers::getScript('logout', 1));
				$cmd = Helpers::updateLocaleCmd($cmd);
				`$cmd`;
				Helpers::retreat('backup_location_is_adopted_by_another_machine');
			}
		}

		Helpers::retreat('User "'. Helpers::getUsername(). '" is already logged in. Logout using logout.pl and try again.');
	}

	Helpers::loadUserConfiguration();
	Helpers::displayHeader();
	Helpers::unloadUserConfigurations();

	# Get user name and validate
	my $uname = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType, " ", 'username', ': '], "username", 1);
	$uname = lc($uname); #Important
	my $emailID = $uname;

	# Get password and validate
	my $upasswd = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType , " ", 'password', ': '], "password", 0);

	my $loggedInUser = Helpers::getUsername();
	my $isLoggedin = Helpers::isLoggedin();

	#validate user account
	Helpers::display(['verifying_your_account_info'],1);

	# Get IDrive/IBackup username list associated with email address
	($uname,$upasswd) = Helpers::getUsernameList($uname, $upasswd) if(Helpers::isValidEmailAddress($uname));

	# Verify user configuration file is valid if not ask for reconfigure
	Helpers::setUsername($uname);
	my $errorKey = Helpers::loadUserConfiguration();
	unless ($errorKey) {
		Helpers::retreat('account_not_configured');
	}
	elsif ($errorKey == 101 or $errorKey == 104) {
		Helpers::retreat($Configuration::errorDetails{$errorKey});
	}

	# validate IDrive user details
	my @responseData = Helpers::authenticateUser($uname, $upasswd, $emailID) or Helpers::retreat(['failed_to_authenticate_user',"'$uname'."]);

	my $switchAccount = 0;
	if ($loggedInUser && $loggedInUser ne $uname && !$isLoggedin) {
		Helpers::display(["\n\nSwitching user from \"", $loggedInUser , "\" to \"", $uname , "\" will stop all your running jobs and disable all your schedules for \"", $loggedInUser, "\". Do you really want to continue (y/n)?"], 1);
		my $userChoice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

		return if(lc($userChoice) eq 'n');

		$switchAccount = 1;
		Helpers::display('switching_user_please_wait');
	}

	Helpers::setUserConfiguration('USERNAME', $uname);
	Helpers::saveUserQuota(@responseData) or Helpers::retreat("Error in save user quota");
	Helpers::saveServerAddress(@responseData);
	Helpers::setUserConfiguration(@responseData);

	#create password files
	Helpers::createEncodePwdFiles($upasswd);
	Helpers::getServerAddress();
	#Helpers::loadUserConfiguration() or Helpers::retreat('your_account_not_configured_properly');

	#configure user account for private/default key
	if (Helpers::getUserConfiguration('USERCONFSTAT') eq 'NOT SET') {
		my ($configType, @result);
		my $encKey = '';
		if(defined($responseData[0]->{'subacc_enckey_flag'}) and $responseData[0]->{'subacc_enckey_flag'} eq 'Y'){
			$configType = 2;
		} else {
			Helpers::display(["\n",'please_configure_your', ' ', $Configuration::appType, ' ', 'account_with_encryption']);
			my @options = (
				'default_encryption_key',
				'private_encryption_key'
			);
			Helpers::displayMenu('', @options);
			$configType = Helpers::getUserMenuChoice(scalar(@options));
		}

		if ($configType == 2) {
			$encKey = Helpers::getAndValidate(['set_your_encryption_key', ": "], "config_private_key", 0);

			my $confirmEncKey = Helpers::getAndValidate(['confirm_your_encryption_key', ": "], "config_private_key", 0);

			if ($encKey ne $confirmEncKey) {
				Helpers::retreat('encryption_key_and_confirm_encryption_key_must_be_the_same');
			}
			Helpers::display('setting_up_your_encryption_key',1);
			#creating IDPVT temporarily to execute EVS commands

			Helpers::createUTF8File('STRINGENCODE', $encKey, Helpers::getIDPVTFile()) or
			Helpers::retreat('failed_to_create_utf8_file');

			@result = Helpers::runEVS();

			unless (($result[0]->{'STATUS'} eq 'SUCCESS') and ($result[0]->{'MSG'} eq 'no_stdout')) {
				Helpers::retreat('failed_to_encode_private_key');
			}
			$configType = 'PRIVATE';
			#Helpers::setUserConfiguration('ENCRYPTIONTYPE', 'PRIVATE');
			#Helpers::createUTF8File('PRIVATECONFIG') or Helpers::retreat('failed_to_create_utf8_file');
		}
		else {
			$configType = 'DEFAULT';
			#Helpers::setUserConfiguration('ENCRYPTIONTYPE', 'DEFAULT');
			#Helpers::createUTF8File('DEFAULTCONFIG') or Helpers::retreat('failed_to_create_utf8_file');
		}

		# @result = Helpers::runEVS('tree');
		# if ($result[0]->{'STATUS'} eq 'FAILURE') {
			# Helpers::retreat(ucfirst($result[0]->{'desc'}));
		# }

		Helpers::configAccount($configType,$encKey);
		Helpers::setUserConfiguration('ENCRYPTIONTYPE', $configType);
		Helpers::display('encryption_key_is_set_successfully',1);
	}
	elsif (Helpers::getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
		my $encKey = Helpers::getAndValidate(["\n", 'enter_your', " encryption key: "], "private_key", 0);
		my @responseData = ();
		Helpers::display('verifying_your_encryption_key',1);
		# this is to create encrypted PVT file and PVTSCH file
		Helpers::encodePVT($encKey);

		if (Helpers::getUserConfiguration('DEDUP') eq 'on') {
			@responseData = Helpers::fetchAllDevices();
		}
		else {
			# validate private key for no dedup account
			Helpers::createUTF8File('PING')  or Helpers::retreat('failed_to_create_utf8_file');
			@responseData = Helpers::runEVS();
		}
		my $rmCmd = Helpers::getIDPVTFile();
		my $userProfileDir  = Helpers::getUserProfilePath();
		if (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'encryption_verification_failed')) {
			Helpers::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			Helpers::loadNotifications() and
				Helpers::setNotification('alert_status_update', $Configuration::alertErrCodes{'pvt_verification_failed'}) and Helpers::saveNotifications();
			Helpers::retreat(['invalid_enc_key']);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /$Configuration::proxyNetworkError/i)) {
		# elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407 Proxy Authentication Required|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/)) {
			Helpers::retreat(["\n", 'kindly_verify_ur_proxy']);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'private_encryption_key_must_be_between_4_and_256_characters_in_length')) {
			Helpers::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			Helpers::retreat(['encryption_key_must_be_minimum_4_characters',"."]);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') && (Helpers::getUserConfiguration('DEDUP') eq 'on') ){
			if ($responseData[0]{'MSG'} ne 'No devices found') {
				Helpers::retreat(ucfirst($responseData[0]->{'MSG'}));
			}else {
				Helpers::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			}
		}
		Helpers::display(['verification_of_encryption_key_is_successfull'],1);
	}
	Helpers::copy(Helpers::getIDPVTFile(), Helpers::getIDPVTSCHFile());
	Helpers::changeMode(Helpers::getIDPVTSCHFile());

	if (int(Helpers::getUserConfiguration('BDA'))) {
		(Helpers::loadNotifications() and Helpers::setNotification('update_acc_status') and
			Helpers::saveNotifications() and Helpers::setUserConfiguration('BDA', 0));
	};

	if (Helpers::getUserConfiguration('DEDUP') eq 'on') {
		my @result = Helpers::fetchAllDevices();
		unless ($result[0]->{'STATUS'} eq 'SUCCESS') {
			Helpers::retreat('your_account_not_configured_properly');
		}

		#Added to consider the bucket type 'D' only
		my @devices;
		foreach (@result){
			next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
			push @devices, $_;
		}

		unless (Helpers::findMyDevice(\@devices)) {
			Helpers::setUserConfiguration('BACKUPLOCATION', '');
			Helpers::saveUserConfiguration(0, 1);
			my $cmd = sprintf("%s %s 1 0", $Configuration::perlBin, Helpers::getScript('logout', 1));
			$cmd = Helpers::updateLocaleCmd($cmd);
			`$cmd`;
			Helpers::retreat('backup_location_is_adopted_by_another_machine');
		}
	}
	Helpers::saveUserConfiguration();

	Helpers::updateCronForOldAndNewUsers($loggedInUser, $uname) if($switchAccount and $Configuration::appType eq 'IDrive');
	#create user.txt for logged in user
	Helpers::updateUserLoginStatus($uname,1);
	Helpers::deactivateOtherUserCRONEntries($uname);
	Helpers::saveMigratedLog(); #Added to upload the migrated log which is not yet uploaded
	# execute the cgi to update record in mysql db
	Helpers::checkAndUpdateClientRecord($uname,$upasswd);
	Helpers::display(['dashBoard_intro_notification']) if($Configuration::appType eq 'IDrive');
#	Helpers::display("\n\"".$uname .'" is logged in successfully.'."\n");
}
