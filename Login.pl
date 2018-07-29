#!/usr/bin/perl

#*****************************************************************************************************
# 						This script is used to login to your user account.
# 							Created By: Anil Kumar
#****************************************************************************************************/

use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')) ;	} else { use lib '.' ; } 

use Helpers;
use Strings;
use Configuration;
use File::Basename;
#use Data::Dumper qw(Dumper);
 
init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Anil Kumar
#****************************************************************************************************/
sub init {
	my $isAccountConfigured = 0;
	system("clear")	and Helpers::retreat('Failed to Clear screen');
	Helpers::loadAppPath() or Helpers::retreat('Failed to load source Code path');
	Helpers::loadServicePath() or Helpers::retreat('configure_&_try_again');
	# check if user exists and login sesion is intect before loading
	if(Helpers::loadUsername() and Helpers::isLoggedin()){
		Helpers::retreat('User "'.Helpers::getUsername(). '" is already logged in. Logout using Logout.pl and try again.');
	}

	Helpers::displayHeader();
	
	# Get user name and validate
	my $uname = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType, " ", 'username', ': '], "username", 1);
	
	# Verify user configuration file is valid if not ask for reconfigure
	Helpers::setUsername($uname);
	my $ucf = Helpers::getUserConfigurationFile();
	unless (-f $ucf and !-z $ucf) {
		Helpers::retreat('account_not_configured');
	}
	# Get password and validate
	my $upasswd = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType , " ", 'password', ': '], "password", 0);
	
	#validate user account
	Helpers::display(['verifying_your_account_info'],1);
	my @responseData = Helpers::authenticateUser($uname, $upasswd) or Helpers::retreat('failed');

	if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
		Helpers::retreat(ucfirst($responseData[0]->{'desc'}).". Please try again.")	if (exists $responseData[0]->{'desc'});
		if ((exists $responseData[0]->{'MSG'}) and ($responseData[0]->{'MSG'} =~ /Try again/)) {
			Helpers::retreat(ucfirst($responseData[0]->{'MSG'}));
		}
		Helpers::retreat(ucfirst($responseData[0]->{'MSG'}).". Please try again.");
	}
	elsif ($responseData[0]->{'STATUS'} eq 'SUCCESS') {
		if ((exists $responseData[0]->{'plan_type'}) and ($responseData[0]->{'plan_type'} eq 'Mobile-Only')) {
			Helpers::retreat(ucfirst($responseData[0]->{'desc'}));
		}
		elsif ((exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'M')) {
			Helpers::retreat('Your account is under maintenance. Please contact support for more information.');
		}
		Helpers::setUserConfiguration('USERNAME', $uname);
		Helpers::saveUserQuota(@responseData) or Helpers::retreat("Error in save user quota");
		Helpers::saveServerAddress(@responseData);
		Helpers::setUserConfiguration(@responseData);
	}

	#create password files
	Helpers::createEncodePwdFiles($upasswd);
	Helpers::getServerAddress();
	#Helpers::loadUserConfiguration() or Helpers::retreat('your_account_not_configured_properly');
	
	#configure user account for private/default key
	if (Helpers::getUserConfiguration('USERCONFSTAT') eq 'NOT SET') {
		Helpers::display(["\n",'please_configure_your', ' ', $Configuration::appType, ' ', 'account_with_encryption']);
		my @options = (
			'default_encryption_key',
			'private_encryption_key'
		);
		Helpers::displayMenu('', @options);
		my $configType = Helpers::getUserMenuChoice(scalar(@options));
	
		my @result;
		if ($configType == 2) {
			my $encKey = Helpers::getAndValidate(['set_your_encryption_key', ": "], "config_private_key", 0);
		
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

			Helpers::setUserConfiguration('ENCRYPTIONTYPE', 'PRIVATE');
			Helpers::createUTF8File('PRIVATECONFIG') or Helpers::retreat('failed_to_create_utf8_file');
		}
		else {
			Helpers::setUserConfiguration('ENCRYPTIONTYPE', 'DEFAULT');
			Helpers::createUTF8File('DEFAULTCONFIG') or Helpers::retreat('failed_to_create_utf8_file');
		}

		@result = Helpers::runEVS('tree');
		if ($result[0]->{'STATUS'} eq 'FAILURE') {
			Helpers::retreat(ucfirst($result[0]->{'desc'}));
		}
		Helpers::display('encryption_key_is_set_sucessfully',1);
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
		if (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'encryption_verification_failed')) {
			`rm -rf '$rmCmd'`;
			Helpers::retreat(['invalid_enc_key']);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407|execution_failed|kindly_verify_ur_proxy/)) {	
			Helpers::retreat(["\n", 'kindly_verify_ur_proxy']);	
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'private_encryption_key_must_be_between_4_and_256_characters_in_length')) {
			`rm -rf '$rmCmd'`;
			Helpers::retreat(['encryption_key_must_be_minimum_4_characters',"."]);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') && (Helpers::getUserConfiguration('DEDUP') eq 'on') ){
			if ($responseData[0]{'MSG'} ne 'No devices found') {
				Helpers::retreat(ucfirst($responseData[0]->{'MSG'}));
			}else {
				`rm -rf '$rmCmd'`;
			}
		}
		Helpers::display(['verification_of_encryption_key_is_sucessfull'],1);
	}
	Helpers::copy(Helpers::getIDPVTFile(), Helpers::getIDPVTSCHFile());
	Helpers::changeMode(Helpers::getIDPVTSCHFile());
	#create user.txt for logged in user
	Helpers::createCache($uname);
	
	# execute the cgi to update record in mysql db
	Helpers::checkAndUpdateClientRecord($uname,$upasswd);
	
	Helpers::display("\n\"".$uname .'" is logged in successfully.'."\n");
}
