#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to configure the user account.
#
# Created  By: Yogesh Kumar @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Configuration;
use File::Basename;
use File::stat;
use JSON;

use constant NO_EXIT => 1;
#Signal handling. Signals received by the script during execution
$SIG{INT}  = \&cleanUp;
$SIG{TERM} = \&cleanUp;
$SIG{TSTP} = \&cleanUp;
$SIG{QUIT} = \&cleanUp;
#$SIG{PWR} = \&cleanUp;
$SIG{KILL} = \&cleanUp;
$SIG{USR1} = \&cleanUp;
my $isAccountConfigured = 0;

Helpers::initiateMigrate();
init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [25/04/2018], Vijay Vinoth, Senthil Pandian
#****************************************************************************************************/
sub init {
	system("clear") and Helpers::retreat('failed_to_clear_screen');
	Helpers::loadAppPath();

	Helpers::loadMachineHardwareName() or Helpers::retreat('unable_to_find_system_information');

	#Verify hostname
	if ($Configuration::hostname eq '') {
		print Helpers::retreat('your_hostname_is_empty');
	}

	# If unable to load service path then take service path from user and create meta data for it
	unless (Helpers::loadServicePath()) {
		Helpers::displayHeader();
		processZIPPath();
		Helpers::findDependencies() or Helpers::retreat('failed');

		Helpers::display(["\n", 'please_provide_your_details_below',"\n"],1);
		unless (Helpers::checkAndUpdateServicePath()) {
			Helpers::createServiceDirectory();
		}
	}
	else {
		Helpers::loadUsername() and Helpers::loadUserConfiguration();
		Helpers::displayHeader();
		Helpers::unloadUserConfigurations();
		processZIPPath();
		Helpers::findDependencies() or Helpers::retreat('failed');
		Helpers::display(["\n",'your_service_directory_is',Helpers::getServicePath()]);
	}

	# Display machine hardware details
	Helpers::display(["\n", 'hardware_platform', '... '], 0);
	my $mcarc = Helpers::getMachineHardwareName();
	$mcarc .= '-bit' if(defined($mcarc) && $mcarc ne 'arm');
	Helpers::display($mcarc . "\n");

	# validate existing EVS binary or download compatible one
	my $isProxy=0;
	my %proxyDetails ;
	unless (Helpers::hasEVSBinary() and Helpers::hasStaticPerlBinary()) {
		if(defined($ARGV[0])){
			getDependentBinaries();
		}
		else {
			# If user name provided is not configured then ask proxy details
			Helpers::loadUserConfiguration();
			Helpers::askProxyDetails() or Helpers::retreat('kindly_verify_ur_proxy');
			unless (Helpers::hasEVSBinary()) {
				Helpers::display(['downloading_evs_binary', '... ']);
				Helpers::downloadEVSBinary() or Helpers::retreat('unable_to_download_evs_binary');
				Helpers::display('evs_binary_downloaded_sucessfully');
			}

			if (Helpers::hasStaticPerlSupport() and not Helpers::hasStaticPerlBinary()) {
				Helpers::display(['downloading_static_perl_binary', '... ']);
				Helpers::downloadStaticPerlBinary() or Helpers::retreat('unable_to_download_static_perl_binary');
				Helpers::display(['static_perl_binary_downloaded_sucessfully',"\n"]);
			}
			$isProxy=1;
			%proxyDetails = Helpers::getUserConfiguration('dashboard');
		}
	}

	Helpers::loadEVSBinary() or Helpers::retreat('unable_to_find_or_execute_evs_binary');

	# Get user name and validate
	my $uname = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType, " ", 'username', ': '], "username", 1);
	$uname = lc($uname); #Important
	# Get password and validate
	my $upasswd = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType, " ", 'password', ': '], "password", 0);

	# Load logged in user name
	Helpers::loadUsername();
	# NOTICE: -- variable not used -- decide removal
	my $loggedInUser = Helpers::getUsername();
	my $isLoggedin = Helpers::isLoggedin();

	# set provided user name to environment
	Helpers::setUsername($uname);

	my $errorKey = Helpers::loadUserConfiguration();

	# If user name provided is not configured then ask proxy details
	Helpers::askProxyDetails() or Helpers::retreat('failed') if($errorKey != 1 and !$isProxy);

	$isAccountConfigured = ($errorKey == 1 or $errorKey == 100) ? 1 : 0;

	Helpers::display('verifying_your_account_info',1);

	# validate IDrive user details
	my @responseData = Helpers::authenticateUser($uname, $upasswd) or Helpers::retreat('failed');

	if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
		Helpers::retreat(ucfirst($responseData[0]->{'desc'}).". Please try again.")	if (exists $responseData[0]->{'desc'});
		if ((exists $responseData[0]->{'MSG'}) and ($responseData[0]->{'MSG'} =~ /Try again/)) {
			Helpers::retreat(ucfirst($responseData[0]->{'MSG'}));
		}
		my $msg = ($responseData[0]->{'MSG'} eq "")?"failed to authenticate":$responseData[0]->{'MSG'};
		Helpers::retreat(ucfirst($msg).". Please try again.");
	}
	elsif ($responseData[0]->{'STATUS'} eq 'SUCCESS') {
		if ((exists $responseData[0]->{'plan_type'}) and ($responseData[0]->{'plan_type'} eq 'Mobile-Only')) {
			Helpers::retreat(ucfirst($responseData[0]->{'desc'}));
		}
		elsif ((exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'M')) {
			Helpers::checkErrorAndLogout('account is under maintenance', $loggedInUser);
			Helpers::retreat('your_account_is_under_maintenance');
		}
		elsif ((exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'B')) {
			Helpers::checkErrorAndLogout('account has been blocked', $loggedInUser);
			Helpers::retreat('your_account_has_been_blocked');
		}
		elsif ((exists $responseData[0]->{'accstat'}) and ($responseData[0]->{'accstat'} eq 'C')) {
			Helpers::checkErrorAndLogout('account has been cancelled', $loggedInUser);
			Helpers::retreat('your_account_has_been_cancelled');
		}
		Helpers::setUserConfiguration(\%proxyDetails);
		Helpers::setUserConfiguration('USERNAME', $uname);
		Helpers::createUserDir() unless($isAccountConfigured);
		Helpers::saveUserQuota(@responseData) or Helpers::retreat("Error in save user quota");
		Helpers::saveServerAddress(@responseData);
		Helpers::setUserConfiguration(@responseData);
	}

	# creates all password files
	Helpers::createEncodePwdFiles($upasswd);
	Helpers::getServerAddress();

	# ask user choice for account configuration and configure the account
	if (Helpers::getUserConfiguration('USERCONFSTAT') eq 'NOT SET') {
		my $configType;
		if(defined($responseData[0]->{'subacc_enckey_flag'}) and $responseData[0]->{'subacc_enckey_flag'} eq 'Y'){
			$configType = 2;
		} else {
			Helpers::display(['please_configure_your', ' ', $Configuration::appType, ' ', 'account_with_encryption']);
			my @options = (
				'default_encryption_key',
				'private_encryption_key'
			);
			Helpers::displayMenu('', @options);
			$configType = Helpers::getUserMenuChoice(scalar(@options));
		}
		my @result;
		if ($configType == 2) {
			my $encKey = Helpers::getAndValidate(['set_your_encryption_key',": "], "config_private_key", 0);
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
			Helpers::retreat(ucfirst($result[0]->{'MSG'}));
		}
		Helpers::display('encryption_key_is_set_sucessfully',1);
		$isAccountConfigured = 0;
		if(-e Helpers::getUserConfigurationFile()) {
			Helpers::setUserConfiguration('BACKUPLOCATION', "");
			Helpers::setUserConfiguration('RESTOREFROM', "");
		}
	}
	elsif (Helpers::getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
		my $needToRetry=0;
	VERIFY:
		my $encKey = Helpers::getAndValidate(['enter_your'," encryption key: "], "private_key", 0);
		my @responseData = ();
		Helpers::display('verifying_your_encryption_key',1);
		my $rmCmd   = Helpers::getIDPVTFile();
		my $rmCmdORG= $rmCmd . '_ORG';

		`mv "$rmCmd" "$rmCmdORG" 2>/dev/null` if(-f $rmCmd && !-f $rmCmdORG);

		# this is to create encrypted PVT file and PVTSCH file
		Helpers::encodePVT($encKey);
		my $isCreateBucket = 0;
		if (Helpers::getUserConfiguration('DEDUP') eq 'on') {
			@responseData = Helpers::fetchAllDevices();
		}
		else {
			# validate private key for no dedup account
			Helpers::createUTF8File('PING')  or Helpers::retreat('failed_to_create_utf8_file');
			@responseData = Helpers::runEVS();
		}
		my $userProfileDir  = Helpers::getUserProfilePath();
		if (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'encryption_verification_failed')) {
			Helpers::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			`mv "$rmCmdORG" "$rmCmd" 2>/dev/null` if(-f $rmCmdORG);
			Helpers::retreat('invalid_enc_key');
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/)) {
			if($isAccountConfigured and !$needToRetry){
				if(updateProxyOP()){
					$needToRetry=1;
					Helpers::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
					`mv "$rmCmdORG" "$rmCmd" 2>/dev/null` if(-f $rmCmdORG);
					goto VERIFY;
				}
			}
			Helpers::retreat(["\n", 'kindly_verify_ur_proxy']);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'private_encryption_key_must_be_between_4_and_256_characters_in_length')) {
			Helpers::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			`mv "$rmCmdORG" "$rmCmd" 2>/dev/null` if(-f $rmCmdORG);
			Helpers::retreat(['encryption_key_must_be_minimum_4_characters',"."]);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'account_is_under_maintenance')) {
			Helpers::removeItems($rmCmd) if($rmCmd =~ /$userProfileDir/);
			Helpers::retreat(['Your account is under maintenance. Please contact support for more information',"."]);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') && (Helpers::getUserConfiguration('DEDUP') eq 'on') ){
			if ($responseData[0]{'MSG'} =~ 'No devices found') {
				Helpers::display(['verification_of_encryption_key_is_sucessfull',"\n"],1);
				$isCreateBucket = createBucket();
			}
			else {
				Helpers::retreat(ucfirst($responseData[0]->{'MSG'}));
			}
		}
		Helpers::display(['verification_of_encryption_key_is_sucessfull',"\n"],1) unless($isCreateBucket);
	}

	verifyExistingBackupLocation();

	Helpers::copy(Helpers::getIDPVTFile(), Helpers::getIDPVTSCHFile());
	Helpers::changeMode(Helpers::getIDPVTSCHFile());

	# Launch Cron service from here
	manageCRONLaunch();

	# manage dashboard here
	manageDashboardJob($uname) unless($isAccountConfigured);

	if ($isAccountConfigured) {
		Helpers::display(['your_account_details_are', ":\n"]);
		Helpers::display([
			"__title_backup__","\n",
			"\t","backup_location_lc", (' ' x 33), ': ',
			(index(Helpers::getUserConfiguration('BACKUPLOCATION'), '#') != -1 )? (split('#', (Helpers::getUserConfiguration('BACKUPLOCATION'))))[1] :  Helpers::getUserConfiguration('BACKUPLOCATION'),"\n",
			(Helpers::getUserConfiguration('DEDUP') eq 'off')? ("\t",'backup_type', (' ' x 37), ': ', Helpers::getUserConfiguration('BACKUPTYPE'),"\n"): "",
			"\t",'bandwidth_throttle', (' ' x 27),     ': ', Helpers::getUserConfiguration('BWTHROTTLE'),"\n",
			"\t",'edit_failed_backup_per', (' ' x 33), ': ', Helpers::getUserConfiguration('NFB'), "\n",
			"\t",'edit_missing_backup_per', (' ' x 32),': ', Helpers::getUserConfiguration('NMB'), "\n",
			"__title_general_settings__","\n",
			"\t",'desktop_access', (' ' x 34),         ': ', (Helpers::getUserConfiguration('DDA')? 'disabled' : 'enabled'), "\n",
			"\t",'title_email_address', (' ' x 34),    ': ', editEmailsToDisplay(),"\n",
			"\t",'ignore_permission_denied', (' ' x 7),': ', (Helpers::getUserConfiguration('IFPE')? 'enabled' : 'disabled'), "\n",
			"\t",'edit_proxy', (' ' x 35),             ': ', editProxyToDisplay(),"\n",
			"\t",'retain_logs', (' ' x 37),            ': ', (Helpers::getUserConfiguration('RETAINLOGS')? 'enabled' : 'disabled'), "\n",
			"\t",'edit_service_path', (' ' x 36),      ': ', Helpers::getServicePath(), "\n",
			"\t",'show_hidden_files', (' ' x 23),      ': ', (Helpers::getUserConfiguration('SHOWHIDDEN')? 'enabled' : 'disabled'), "\n",
			"\t",'notify_software_update', (' ' x 20), ': ', (Helpers::getUserConfiguration('NOTIFYSOFTWAREUPDATE')? 'enabled' : 'disabled'), "\n",
			"\t",'upload_multiple_chunks', (' ' x 6),  ': ', ((Helpers::getUserConfiguration('ENGINECOUNT') == 4)? 'enabled' : 'disabled'),
			"\n",
			"__title_restore_settings__","\n",
			"\t",'restore_from_location', (' ' x 27), ': ',
			(index(Helpers::getUserConfiguration('RESTOREFROM'), '#') != -1 )? (split('#', (Helpers::getUserConfiguration('RESTOREFROM'))))[1] :  Helpers::getUserConfiguration('RESTOREFROM'),
			"\n",
			"\t",'restore_location', (' ' x 32),       ': ', Helpers::getUserConfiguration('RESTORELOCATION'),"\n",
			"\t",'restore_loc_prompt', (' ' x 25),     ': ', (Helpers::getUserConfiguration('RESTORELOCATIONPROMPT')? 'enabled' : 'disabled'), "\n",
			"__title_services__","\n",
			"\t",'app_dashboard_service', (' ' x 31),  ': ', ((Helpers::isUserDashboardRunning($loggedInUser))? 'c_running' : 'c_stopped'),"\n",
			"\t",'app_cron_service', (' ' x 29),       ': ', ((Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING)? 'c_running' : 'c_stopped'), "\n",
		]);

		my $confmtime = stat(Helpers::getUserConfigurationFile())->mtime;
		#display user configurations and edit/reset options.
		tie(my %optionsInfo, 'Tie::IxHash',
			're_configure_your_account_freshly' => sub { $isAccountConfigured = 0; },
			'edit_your_account_details' => sub { editAccount($loggedInUser, $confmtime); },
			'exit' => sub {
				Helpers::saveUserConfiguration();
				exit 0;
			},
		);

		my @options = keys %optionsInfo;

		while(1){
			Helpers::display(["\n", 'do_you_want_to', ':', "\n"]);
			Helpers::displayMenu('enter_your_choice', @options);
			my $userSelection = Helpers::getUserChoice();
			if (Helpers::validateMenuChoice($userSelection, 1, scalar(@options))) {
				$optionsInfo{$options[$userSelection - 1]}->();
				last;
			}
			else{
				Helpers::display(['invalid_choice', ' ', 'please_try_again', '.']);
			}
		}
	}

	# need to move all code to inside this and check once
	unless ($isAccountConfigured) {
		Helpers::setBackupToLocation()     or Helpers::retreat('failed_to_set_backup_location');
		Helpers::setRestoreLocation()      or Helpers::retreat('failed_to_set_restore_location');
		Helpers::setRestoreFromLocation()  or Helpers::retreat('failed_to_set_restore_from');
		Helpers::setRestoreFromLocPrompt(1)or Helpers::retreat('failed_to_set_restore_from_prompt');
		Helpers::setNotifySoftwareUpdate() or Helpers::retreat('failed_to_set_software_update_notification');
		setEmailIDs()                      or Helpers::retreat('failed_to_set_email_id');
		# setRetainLogs(1)                 or Helpers::retreat('failed_to_set_retain_log');
		setBackupType()                    or Helpers::retreat('failed_to_set_backup_type');
		installUserFiles()                 or Helpers::retreat('failed_to_install_user_files');
	}

	Helpers::saveUserConfiguration() or Helpers::retreat('failed_to_save_user_configuration');

	Helpers::checkAndUpdateClientRecord($uname,$upasswd);

	Helpers::display(["\n", "\"$uname\""." is configured successfully. "],0);
	if (($loggedInUser eq $uname) and $isLoggedin) {
		Helpers::display(["\n\n","User ", "\"$uname\"", " is already logged in." ],1);
	}
	else{
		Helpers::display(['do_u_want_to_login_as', "\"$uname\"", ' (y/n)?'],1);
		my $loginConfirmation = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if(lc($loginConfirmation) eq 'n' ) {
			Helpers::updateUserLoginStatus($uname,0);
			cleanUp();
			return;
		}

		if($loggedInUser ne "" && ($loggedInUser ne $uname)) {
			#Helpers::display(["\n\nSwitching user from \"", $loggedInUser , "\" to \"", $uname , "\" will stop all the scheduled jobs for \"", $loggedInUser, "\". Do you really want to continue(y/n)?"], 1);
			Helpers::display(["\nSwitching user from \"", $loggedInUser , "\" to \"", $uname , "\" will stop all your running jobs and disable all your schedules for \"", $loggedInUser, "\". Do you really want to continue (y/n)?"], 1);
			my $userChoice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

			if(lc($userChoice) eq 'n' ) {
				cleanUp();
				return;
			}
			Helpers::updateCronForOldAndNewUsers($loggedInUser, $uname);
			Helpers::deactivateOtherUserCRONEntries($uname);
		}

		Helpers::updateUserLoginStatus($uname,1) or Helpers::retreat('unable_to_login_please_try_login_script');
		#Helpers::display(['dashBoard_intro_notification']);
	}
	cleanUp();
}

#*****************************************************************************************************
# Subroutine			: verifyExistingBackupLocation
# Objective				: This is to verify the whether the backup locations are available or not.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub verifyExistingBackupLocation
{
	if($isAccountConfigured) {
		my $isDedup        = Helpers::getUserConfiguration('DEDUP');
		my $backupLocation = Helpers::getUserConfiguration('BACKUPLOCATION');
		my $bucketName     = "";
		my $deviceID       = "";
		my $jobRunningDir  = Helpers::getUserProfilePath();
		if($isDedup eq "on") {
			if (index($backupLocation, "#") != -1) {
				$deviceID   = (split("#",$backupLocation))[0];
				$bucketName = (split("#",$backupLocation))[1];
			}
		} else {
			$bucketName = $backupLocation;
		}

		if(substr($bucketName, 0, 1) ne "/") {
			$bucketName = "/".$bucketName;
		}

		my $tempBackupsetFilePath = $jobRunningDir."/".$Configuration::tempBackupsetFile;
		if (open(my $fh, '>', $tempBackupsetFilePath)) {
			print $fh $bucketName;
			close($fh);
			chmod 0777, $tempBackupsetFilePath;
		}
		else
		{
			Helpers::traceLog("failed to create file. Reason: $!\n");
			return 0;
		}

		my $itemStatusUTFpath = $jobRunningDir.'/'.$Configuration::utf8File;
		my $evsErrorFile      = $jobRunningDir.'/'.$Configuration::evsErrorFile;
		Helpers::createUTF8File(['ITEMSTATUS',$itemStatusUTFpath], $tempBackupsetFilePath, $evsErrorFile) or Helpers::retreat('failed_to_create_utf8_file');

		my @responseData = Helpers::runEVS('item');

		unlink($tempBackupsetFilePath);

		if(-s $evsErrorFile > 0) {
			open(FILE,$evsErrorFile);
			if (grep{/failed to get the device information/} <FILE>){
				$isAccountConfigured = 0;

				unlink(Helpers::getUserConfigurationFile()) if(-e Helpers::getUserConfigurationFile());
			}
			close FILE;
		}
		unlink($evsErrorFile);
		if($isDedup eq 'off'){
			if ($responseData[0]{'status'} =~ /No such file or directory|directory exists in trash/) {
				$isAccountConfigured = 0;
				unlink(Helpers::getUserConfigurationFile()) if(-e Helpers::getUserConfigurationFile());
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: editProxyToDisplay
# Objective				: Edit and format the proxy details in order to display the user accordingly.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub editProxyToDisplay {
	my $proxyValue = Helpers::getUserConfiguration('PROXY');
	if($proxyValue ne "") {
		my ($pwd) = $proxyValue =~ /:([^\s@]+)/;
		$pwd = $pwd."@";
		my $newPwd = "***@";
		$proxyValue =~ s/$pwd/$newPwd/;
	}
	else{
		$proxyValue = "No Proxy";
	}
	return $proxyValue;
}

#*****************************************************************************************************
# Subroutine			: editEmailsToDisplay
# Objective				: Edit and format the emails in order to display the user accordingly.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub editEmailsToDisplay {
	my $emailAddresses = Helpers::getUserConfiguration('EMAILADDRESS');
	$emailAddresses    = "no_emails_configured" if($emailAddresses eq "");

	return $emailAddresses;
}

#*****************************************************************************************************
# Subroutine			: processZIPPath
# Objective				: This method checks and and verifies zip package if passed
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub processZIPPath {
	# In case if user passed zip file of EVS binary.
	if(defined($ARGV[0])) {
		validateZipPath();
	}
}

#*****************************************************************************************************
# Subroutine			: manageDashboardJob
# Objective				: This method checks and manages the dashboard related activities and setup
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub manageDashboardJob {
	Helpers::loadCrontab(1);
	my $curdashscript = Helpers::getCrontab($Configuration::dashbtask, $Configuration::dashbtask, '{cmd}');

	# account not configured | no cron tab entry | dashboard script empty
	if(!$curdashscript || $curdashscript eq '') {
		Helpers::createCrontab($Configuration::dashbtask, $Configuration::dashbtask);
		Helpers::setCronCMD($Configuration::dashbtask, $Configuration::dashbtask);
		Helpers::saveCrontab();
		Helpers::checkAndStartDashboard(0);
		return 1;
	}

	my $newdashscript = Helpers::getScript($Configuration::dashbtask);
	# check same path or not
	if($curdashscript eq $newdashscript) {
		# lets handle dashboard job; check and start dashboard
		return Helpers::checkAndStartDashboard(1);
	}

	# dashboard scripts are not the same. old path not valid | reset user's cron schemas to default
	unless(-f $curdashscript) {
		Helpers::resetUserCRONSchemas();
		return Helpers::checkAndStartDashboard(0);
	}

	Helpers::display(["\n", 'user', ' "', $_[0], '" ', 'is_already_having_active_setup_path', ' ', '"' . dirname($curdashscript) . '"', '. '], 0);
	Helpers::display(["\n",'config_same_user_will_del_old_schedule', ' '], 0);
	Helpers::display([ 'do_you_want_to_continue_yn']);
	my $resetchoice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	# user doesn't want to reset the dashboard job, check and start dashboard job
	if($resetchoice eq 'n') {
		exit(0);
	}

	# reset all the schemes of the user
	Helpers::resetUserCRONSchemas();
	# kill the running dashboard job
	Helpers::stopDashboardService($Configuration::mcUser, dirname($curdashscript));
	# kill all the running jobs belongs to this user
	my $cmd = sprintf("%s %s '' %s 0", $Configuration::perlBin, Helpers::getScript('job_termination', 1), Helpers::getUsername());
	`$cmd 1>/dev/null 2>/dev/null`;
	Helpers::checkAndStartDashboard(0);
}

#*****************************************************************************************************
# Subroutine			: manageCRONLaunch
# Objective				: This method checks the status of cron and launches it
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub manageCRONLaunch {
	unless(Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
		Helpers::display(["\n", 'setting_up_cron_service', ' ', 'please_wait_title', '...']);
		my $sudoprompt = 'please_provide_' . ((Helpers::isUbuntu() || Helpers::isGentoo())? 'sudoers' : 'root') . '_pwd_for_cron';
		my $sudosucmd = Helpers::getSudoSuCRONPerlCMD('installcron', $sudoprompt);
		system($sudosucmd);

		Helpers::display([((Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING)? 'cron_service_started' : 'unable_to_start_cron_service'), '.',"\n"]);
		return 1;
	}

	# compare the version of current script and the running script from the lock
	# if the running version is older, replace the link and update the lock file to self restart
	my @lockinfo = Helpers::getCRONLockInfo();
	if(Helpers::versioncompare($Configuration::version, $lockinfo[1]) == 1) {
		my $sudoprompt = 'please_provide_' . ((Helpers::isUbuntu() || Helpers::isGentoo())? 'sudoers' : 'root') . '_pwd_for_cron_update';
		my $sudosucmd = Helpers::getSudoSuCRONPerlCMD('restartidriveservices', $sudoprompt);
		system($sudosucmd);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateZipPath
# Objective				: This subroutine will check the user provided zip file whether it is suitable to the machine or not.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub validateZipPath {
	Helpers::retreat(["\n", 'absolute_path_required', "\n"]) if($ARGV[0] =~ m/\.\./);
	Helpers::retreat(["\n", 'file_not_found', ": ",  $ARGV[0], "\n"]) if(!-e $ARGV[0]);

	my $machineName = Helpers::getMachineHardwareName();
	if ($ARGV[0] !~ /$machineName/) {
		my $evsWebPath = "https://www.idrivedownloads.com/downloads/linux/download-options/IDrive_Linux_" . $machineName . ".zip";
		Helpers::retreat(["\n", 'invalid_zip_file', "\n", $evsWebPath, "\n"]);
	}
}

#*****************************************************************************************************
# Subroutine			: getDependentBinaries
# Objective				: Get evs & static perl binaries.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************************************/
sub getDependentBinaries {
	my $machineName = Helpers::getMachineHardwareName();
	my $zipFilePath = getZipPath($ARGV[0]);
	Helpers::unzip($zipFilePath, Helpers::getServicePath()) or Helpers::retreat('unzip_failed_unable_to_unzip');;
	#my $downloadsPath = Helpers::getServicePath() . "/". $ARGV[0]; #Commented by Senthil for Snigdha_2.16_13_3
	my $downloadsPath = Helpers::getServicePath() . "/". fileparse($ARGV[0]);
	$downloadsPath =~ s/.zip//g;
	$downloadsPath = $downloadsPath . "/";

	my $ezf    = [@{$Configuration::evsZipFiles{$machineName}}, @{$Configuration::evsZipFiles{'x'}}];
	for my $i (0 .. $#{$ezf}) {
		$ezf->[$i] =~ s/__APPTYPE__/$Configuration::appType/g;

		my $binPath = $downloadsPath.$ezf->[$i];
		$binPath =~ s/\.zip//g;
		`chmod $Configuration::filePermissionStr '$binPath/'*` if(-e $binPath);

		last if (Helpers::hasEVSBinary($binPath));

		#$downloadsPath = dirname($downloadsPath) . '/' . $ezf->[$i];
		# $downloadsPath = $downloadsPath .'/'. $ezf->[$i];
		# $downloadsPath =~ s/\.zip//g;
		# `chmod $Configuration::filePermissionStr '$downloadsPath/'*` if(-e $downloadsPath);
		# print "\n$downloadsPath\n";
		# last if (Helpers::hasEVSBinary($downloadsPath));
	}

	$ezf = [@{$Configuration::staticperlZipFiles{$machineName}}];
	if ($Configuration::machineOS =~ /freebsd/i) {
		$ezf = [@{$Configuration::staticperlZipFiles{'freebsd'}}];
	}

	for my $i (0 .. $#{$ezf}) {
		my $binPath = $downloadsPath.$ezf->[$i];
		$binPath =~ s/\.zip//g;
		`chmod $Configuration::filePermissionStr '$binPath/'*` if (-e $binPath);

		last if (Helpers::hasStaticPerlBinary($binPath));
	}

	Helpers::rmtree("$downloadsPath");
}

#*****************************************************************************************************
# Subroutine			: getZipPath
# Objective				: This subroutine will return the absolute path of the zip file path user provided.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getZipPath {
	my $zipPath = $_[0];
	if($zipPath =~ /^\//){
		return $zipPath;
	}

	my $currDirLocal = `pwd`;
	chomp($currDirLocal);

	$zipPath = $currDirLocal."/".$zipPath;
	chomp($zipPath);
	return $zipPath;
}

#*****************************************************************************************************
# Subroutine			: createBucket
# Objective				: This subroutine is used to create a bucket
# Added By				: Yogesh Kumar
# Modified By			: Vijay Vinoth, Senthil Pandian
#****************************************************************************************************/
sub createBucket {
	my $bkLocationEntry	= (Helpers::getUserConfiguration('DEDUP') eq 'on')?'enter_your_backup_location_optional':'enter_your_ndedup_backup_location_optional';
	my $deviceName = Helpers::getAndValidate([$bkLocationEntry, ": "], "backup_location", 1);
	if($deviceName eq '') {
		$deviceName = $Configuration::hostname;
		$deviceName =~ s/[^a-zA-Z0-9_-]//g;
	}
	#validateBackupLoction();
	Helpers::display('setting_up_your_backup_location',1);
	Helpers::createUTF8File('CREATEBUCKET',$deviceName) or Helpers::retreat('failed_to_create_utf8_file');
	my @result = Helpers::runEVS('item');

	if ($result[0]{'STATUS'} eq 'SUCCESS') {
		Helpers::display(['your_backup_to_device_name_is',(" \"" . $result[0]{'nick_name'} . "\".")]);
		#server root added by anil
		Helpers::setUserConfiguration('SERVERROOT', $result[0]{'server_root'});
		Helpers::setUserConfiguration('BACKUPLOCATION',
			($Configuration::deviceIDPrefix . $result[0]{'device_id'} . $Configuration::deviceIDSuffix .
				"#" . $result[0]{'nick_name'}));
		Helpers::loadNotifications() and Helpers::setNotification('register_dashboard') and Helpers::saveNotifications();
		return 1;
	} else {
		Helpers::retreat('failed_to_set_backup_location');
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateBackupLoction
# Objective				: This is to validate and return bucket name
# Added By				: Anil Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub validateBackupLoction {
	my ($bucketName, $choiceRetry) = ('', 0);
	my $bkLocationEntry = (Helpers::getUserConfiguration('DEDUP') eq 'on')?'enter_your_backup_location_optional':'enter_your_ndedup_backup_location_optional';
	Helpers::display(["\n",$bkLocationEntry, ': '], 0);
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		$bucketName = Helpers::getUserChoice();
		$choiceRetry++;
		if($bucketName eq '') {
			$bucketName = $Configuration::hostname;
			Helpers::display(['considering_default_backup_location',"\"$bucketName\""], 1);
			last;
		} elsif(length($bucketName) > 65) {
			Helpers::display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_be_one_to_sixty_five_characters', "\n"], 1);
		}#elsif($bucketName =~ /^[A-Za-z0-9_\-\.\s]+$/) {
		elsif($bucketName =~ /^[a-zA-Z0-9_-]*$/) {
			$bucketName = $bucketName;
			last;
		} else {
			Helpers::display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_contain_only_letters_numbers_space_and_characters', "\n"], 1);
		}

		if($choiceRetry == 3){
			Helpers::retreat(['max_retry']);
		}else{
			Helpers::display([$bkLocationEntry, ': '], 0);
		}
		next;
	}
		return $bucketName;
}


#*****************************************************************************************************
# Subroutine			: setEmailIDs
# Objective				: This subroutine is used to set email id's
# Added By				: Anil Kumar
#****************************************************************************************************/
sub setEmailIDs {
	my $emailAddresses = Helpers::getAndValidate(["\n", 'enter_your_email_id', ': '], "single_email_address", 1, 0);

	$emailAddresses =~ s/;/,/g;
	if($emailAddresses ne "") {
		my $editFormatToDisplay = $emailAddresses;
		Helpers::display(['configured_email_address_is', ' ', $editFormatToDisplay]);
	}
	else {
		Helpers::display(['no_emails_configured'],1);
	}

	Helpers::setUserConfiguration('EMAILADDRESS', $emailAddresses);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setBandwidthThrottle
# Objective				: This subroutineis is used to set BWTHROTTLE value
# Added By				: Anil Kumar
#****************************************************************************************************/
sub setBandwidthThrottle {
# modified by anil on 30may2018
	Helpers::display(['your_bw_value_set_to' , Helpers::getUserConfiguration('BWTHROTTLE'), '%. ', 'do_u_really_want_to_edit', "\n"],0);

	my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	if($choice eq "y" or $choice eq "Y") {
		my $answer = Helpers::getAndValidate(['enter_bw_value'], "bw_value", 1);
		Helpers::setUserConfiguration('BWTHROTTLE', $answer);
		Helpers::display(['your_bw_value_set_to', $answer, '%.', "\n\n"], 0);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setRetainLogs
# Objective				: This subroutineis is used to set retail logs value for an account
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************************************/
sub setRetainLogs {
	my $retainLogs = 1;

	if (Helpers::getUserConfiguration('RETAINLOGS') ne '' || (defined($_[0]) && $_[0] == 1)) {
		$retainLogs = 0 unless(Helpers::getUserConfiguration('RETAINLOGS'));
		$retainLogs = 0 if(defined($_[0]));

		unless(defined($_[0])) {
			Helpers::display(["\n", "your_retain_logs_is_$retainLogs\_?"], 1);
		} else {
			Helpers::display(["\n", "do_you_want_to_retain_logs"], 1);
		}

		my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		$retainLogs = ($retainLogs ? 0 : 1) if ($choice eq 'y');
		Helpers::setUserConfiguration('RETAINLOGS', $retainLogs);
	}

	Helpers::display(["your_retain_logs_is_$retainLogs"]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setBackupType
# Objective				: This subroutineis is used to set backup type value
# Added By				: Anil Kumar
#****************************************************************************************************/
sub setBackupType {
	if (Helpers::getUserConfiguration('DEDUP') eq 'on') {
		Helpers::setUserConfiguration('BACKUPTYPE', 'mirror');
		return 1;
	}

	my $backuptype = displayBackupTypeOP();
	Helpers::setUserConfiguration('BACKUPTYPE', ($backuptype == 1)?'mirror':'relative');
	Helpers::display(["your_backup_type_is_set_to", "\"", Helpers::getUserConfiguration('BACKUPTYPE'), "\"."]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getAndSetBackupType
# Objective				: This subroutineis is used to get Backup type value from user and set it
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getAndSetBackupType {
	if (Helpers::getUserConfiguration('DEDUP') eq 'on') {
		Helpers::display(['your_backup_type_is_set_to', "\"", Helpers::getUserConfiguration('BACKUPTYPE'),"\". ", "\n"]);
		return 1;
	}
	Helpers::display(['your_backup_type_is_set_to', "\"", Helpers::getUserConfiguration('BACKUPTYPE'),"\". ", 'do_u_really_want_to_edit' , "\n"]);
	my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if($answer eq "y" or $answer eq "Y") {
		my $backuptype = displayBackupTypeOP();
		Helpers::setUserConfiguration('BACKUPTYPE', ($backuptype == 1)?'mirror':'relative');
		Helpers::display(["your_backup_type_is_changed_to", "\"", Helpers::getUserConfiguration('BACKUPTYPE'), "\".\n"]);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: displayBackupTypeOP
# Objective				: This subroutineis is used to display options for Backup type
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub displayBackupTypeOP {
	Helpers::display(["\n", "select_op_for_backup_type"]);
	Helpers::display("1) Mirror");
	Helpers::display("2) Relative");

	my $answer = Helpers::getUserMenuChoice(2);
	return $answer;
}

#*****************************************************************************************************
# Subroutine			: updateProxyOP
# Objective				: This subroutineis is used to update proxy options
# Added By				: Anil Kumar
#****************************************************************************************************/
sub updateProxyOP {
	my $proxyDetails = editProxyToDisplay();
	if( $proxyDetails eq "No Proxy") {
		Helpers::display(["\n",'your_proxy_has_been_disabled'," ", 'do_you_want_edit_this_y_or_n_?'], 1);
	} else {
		Helpers::display(["\n","Your proxy details are \"",$proxyDetails, "\". ", 'do_you_want_edit_this_y_or_n_?'], 1);
	}

	my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		Helpers::askProxyDetails("update");
		Helpers::saveUserConfiguration() or Helpers::retreat('failed_to_save_user_configuration');
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateServiceDir
# Objective				: This subroutineis is used to update service path for scripts
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar, Vijay Vinoth, Sabin Cheruvattil
#****************************************************************************************************/
sub updateServiceDir {
	my $oldServicedir = Helpers::getServicePath();
	Helpers::display(["\n","Your service directory is \"",$oldServicedir, "\". ", 'do_you_want_edit_this_y_or_n_?'], 1);
	my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {

		# need to check any jobs are running here.
		Helpers::display(["\n","changing_service_directory_will_terminate_all_the_running_jobs", 'do_you_want_edit_this_y_or_n_?'], 1);
		$answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		return 1 	if (lc($answer) eq "n") ;

		Helpers::checkForRunningJobsInOtherUsers() or Helpers::retreat("One or more backup/express backup/restore/archive cleanup jobs are in process with respect to others users. Please make sure those are completed and try again.");
		my $cmd = sprintf("%s %s", $Configuration::perlBin, Helpers::getScript('job_termination', 1));
		my $res = `$cmd '' - 0 all 1>/dev/null 2>/dev/null`;

		my $servicePathSelection = Helpers::getAndValidate(["\n", 'enter_your_new_service_path'], "service_dir", 1);
		if ($servicePathSelection eq '') {
			$servicePathSelection = dirname(Helpers::getAppPath());
		}
		$servicePathSelection = Helpers::getAbsPath($servicePathSelection);
		my $checkPath         = substr $servicePathSelection, -1;
		$servicePathSelection = $servicePathSelection ."/" if($checkPath ne '/');
		my $newSerDir         = Helpers::getCatfile($servicePathSelection,$Configuration::servicePathName);
		my $oldSerDir         = Helpers::getCatfile($oldServicedir);
		if ($oldSerDir eq $newSerDir) {
			Helpers::display('same_service_dir_path_has_been_selected');
			return 1;
		}
		my $moveResult = moveServiceDirectory($oldSerDir, $newSerDir);
		#my $moveResult = `mv '$oldSerDir' '$newSerDir' 2>/dev/null`;

		# added by anil on 31may2018
		if ($moveResult) {
			Helpers::saveServicePath($servicePathSelection.$Configuration::servicePathName) or Helpers::retreat(['failed_to_create_directory',": $servicePathSelection"]);
			my $restoreLocation   = Helpers::getUserConfiguration('RESTORELOCATION');
			$servicePathSelection = $servicePathSelection.$Configuration::servicePathName;
			my $tempOldServicedir = Helpers::getECatfile($oldServicedir);
			$restoreLocation      =~ s/$tempOldServicedir/$servicePathSelection/;

			my $oldPathForCron    = Helpers::getECatfile($oldServicedir, $Configuration::userProfilePath);
			my $newPathForCron    = Helpers::getECatfile($servicePathSelection, $Configuration::userProfilePath);
			#modified by anil on 01may2018
			my $updateCronEntry   = `sed 's/'$oldPathForCron'/'$newPathForCron'/g' '/etc/crontabTest' 1>/dev/null 2>/dev/null `;

			Helpers::setUserConfiguration('RESTORELOCATION', $restoreLocation);
			Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');

			Helpers::retreat('failed_to_save_user_configuration') unless(Helpers::saveUserConfiguration());
			Helpers::display(['service_dir_updated_successfully', "\"", $servicePathSelection, "\"."]);

			# Restart Dashboard
			if(Helpers::isDashboardRunning()) {
				Helpers::stopDashboardService($Configuration::mcUser, dirname(__FILE__));
				Helpers::checkAndStartDashboard(0, 1);
			}

			if(Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
				my @lockinfo = Helpers::getCRONLockInfo();
				$lockinfo[2] = 'restart';
				Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
			}

			return 1;
		}
		Helpers::retreat('please_try_again');
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: installUserFiles
# Objective				: This subroutineis is used to Install files like backupset/restoreset/fullexlcude etc...
# Added By				: Yogesh Kumar
# Modified By           : Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub installUserFiles {
	tie(my %filesToInstall, 'Tie::IxHash',
		%Configuration::availableJobsSchema,
		%Configuration::excludeFilesSchema
	);

	if(-d $Configuration::defaultMountPath) {
		Helpers::display(["\n",'your_default_mount_point_for_local_backup_set_to', "\"$Configuration::defaultMountPath\"", ".\n"], 0);
		Helpers::setUserConfiguration('LOCALMOUNTPOINT', $Configuration::defaultMountPath);
	}

	Helpers::display(["\n", 'by_default_retain_logs_option_is_enabled']);
	Helpers::setUserConfiguration('RETAINLOGS', 1);

	my $failedPercent = $Configuration::userConfigurationSchema{'NFB'}{'default'};
	Helpers::setUserConfiguration('NFB', $failedPercent);
	Helpers::display(["\n",'your_default_failed_files_per_set_to', $failedPercent, "%.\n", 'if_total_files_failed_for_backup', "\n"], 0, [$failedPercent]);

	Helpers::display(["\n",'by_default_ignore_permission_is_disabled', "\n"],0);
	Helpers::setUserConfiguration('IFPE', $Configuration::userConfigurationSchema{'IFPE'}{'default'});

	Helpers::display(["\n",'by_default_show_hidden_option_is_enabled', "\n"],0);
	Helpers::setUserConfiguration('SHOWHIDDEN', $Configuration::userConfigurationSchema{'SHOWHIDDEN'}{'default'});

	Helpers::display(["\n",'your_desktop_access_is_enabled', "\n"],0);
	Helpers::setUserConfiguration('DDA', $Configuration::userConfigurationSchema{'DDA'}{'default'});

	Helpers::display(["\n",'by_default_upload_multiple_file_chunks_option_is_enabled', "\n"],0);
	Helpers::setUserConfiguration('ENGINECOUNT', $Configuration::userConfigurationSchema{'ENGINECOUNT'}{'default'});

	my $missingPercent = $Configuration::userConfigurationSchema{'NMB'}{'default'};
	Helpers::setUserConfiguration('NMB', $missingPercent);
	Helpers::display(["\n",'your_default_missing_files_per_set_to', $missingPercent, "%.\n", 'if_total_files_missing_for_backup', "\n"], 0, [$missingPercent]);

	Helpers::display(["\n",'your_default_bw_value_set_to', '100%.', "\n\n"], 0);

	Helpers::createUpdateBWFile($Configuration::userConfigurationSchema{'BWTHROTTLE'}{'default'});
	Helpers::setUserConfiguration('BWTHROTTLE', $Configuration::userConfigurationSchema{'BWTHROTTLE'}{'default'});

	# set default dashboard path if it is edit account
	Helpers::createCrontab($Configuration::dashbtask, $Configuration::dashbtask);
	Helpers::setCronCMD($Configuration::dashbtask, $Configuration::dashbtask);
	Helpers::saveCrontab();

	my $file;
	foreach (keys %filesToInstall) {
		$file = $filesToInstall{$_}{'file'};
		#Skipping for Archive as we not keeping any default backup set: Senthil
		if($file =~ m/archive/i){
			next;
		}
		$file =~ s/__SERVICEPATH__/Helpers::getServicePath()/eg;
		$file =~ s/__USERNAME__/Helpers::getUsername()/eg;
		if (open(my $fh, '>>', $file)) {
			Helpers::display(["your_default_$_\_file_created"]);
			close($fh);
			chmod 0777, $file;
		}
		else {
			Helpers::display(["\n",'unable_to_create_file', " \"$file\"." ]);
			return 0;
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: editAccount
# Objective				: This subroutineis is used to edit logged in user account
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil
#****************************************************************************************************/
sub editAccount {
	Helpers::display(["\n",'select_the_item_you_want_to_edit', ":\n"]);
	my $loggedInUser = $_[0];

	# load account settings if there has been a change in log
	my $confmtime = stat(Helpers::getUserConfigurationFile())->mtime;
	Helpers::loadUserConfiguration() if($confmtime != $_[1]);

	tie(my %optionsInfo, 'Tie::IxHash',
		'__title_backup__backup_location_lc'                => \&editBackupToLocation,
		'__title_backup__backup_type'                       => \&getAndSetBackupType,
		'__title_backup__bandwidth_throttle'                => \&setBandwidthThrottle,
		'__title_backup__edit_failed_backup_per'            => \&editFailedFilePercentage,
		'__title_backup__edit_missing_backup_per'           => \&editMissingFilePercentage,
		'__title_general_settings__desktop_access'          => \&editDesktopAccess,
		'__title_general_settings__title_email_address'     => sub { updateEmailIDs(); },
		'__title_general_settings__ignore_permission_denied'=> \&editIgnorePermissionDeniedError,
		'__title_general_settings__edit_proxy'              => \&updateProxyOP,
		'__title_general_settings__retain_logs'             => \&setRetainLogs,
		'__title_general_settings__edit_service_path'       => \&updateServiceDir,
		'__title_general_settings__show_hidden_files'       => \&editShowHiddenFiles,
		'__title_general_settings__notify_software_update'  => sub { Helpers::setNotifySoftwareUpdate(); },
		'__title_general_settings__upload_multiple_chunks'  => sub { Helpers::setUploadMultipleChunks(); },
		'__title_restore_settings__restore_from_location'   => sub { Helpers::editRestoreFromLocation(); },
		'__title_restore_settings__restore_location'        => sub { Helpers::editRestoreLocation();	},
		'__title_restore_settings__restore_loc_prompt'      => sub { Helpers::setRestoreFromLocPrompt(); },
		'__title_services__start_restart_dashboard_service' => sub { checkDashboardStart($loggedInUser); },
		'__title_services__restart_cron_service'            => sub { Helpers::confirmRestartIDriveCRON(); },
		'__title_empty__exit'                               => \&updateAndExitFromEditMode,
	);
	if (Helpers::getUserConfiguration('DEDUP') eq 'on') {
		delete $optionsInfo{'__title_backup__backup_type'};
	}
	my @options = keys %optionsInfo;
	Helpers::displayMenu('enter_your_choice', @options);
	my $editItem = Helpers::getUserChoice();
	if (Helpers::validateMenuChoice($editItem, 1, scalar(@options))) {
		if (!isSettingLocked($options[$editItem - 1])){
			$optionsInfo{$options[$editItem - 1]}->() or Helpers::retreat('failed');
		}
	}
	else{
		Helpers::display(['invalid_choice', ' ', 'please_try_again', '.']);
	}

	Helpers::saveUserConfiguration();
	$Configuration::isUserConfigModified = 0;

	return editAccount($_[0], $confmtime);
}

#*****************************************************************************************************
# Subroutine			: checkDashboardStart
# Objective				: Check | show status | start dashboard
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkDashboardStart {
	unless (Helpers::hasStaticPerlSupport()) {
		Helpers::display('dashboard_is_not_supported_for_this_arc_yet');
		return 1;
	}

	if (Helpers::isDashboardRunning()) {
		if($_[0] eq '') {
			Helpers::display(["\n", 'login_&_try_again']);
			return 1;
		}

		Helpers::display(((Helpers::getUsername() ne $_[0])? ["\n", 'dashboard_already_running_for_user', $_[0], ".\n"] : ["\n", 'dashboard_service_running', '. ']), 0);
		return 1 if(Helpers::getUsername() ne $_[0]);

		Helpers::display(['do_you_want_to_restart_dashboard']);
		my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if(lc($answer) eq 'y') {
			Helpers::stopDashboardService($Configuration::mcUser, dirname(__FILE__));
			Helpers::confirmStartDashboard(1, 1);
		}
		return 1;
	}

	return 1 if(confirmDuplicateDashboardInstance($_[0]) == 2);

	Helpers::confirmStartDashboard(1);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: confirmDuplicateDashboardInstance
# Objective				: Confirm and terminate any dashboard if running for same user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub confirmDuplicateDashboardInstance {
	Helpers::loadCrontab(1);
	my $curdashscript = Helpers::getCrontab($Configuration::dashbtask, $Configuration::dashbtask, '{cmd}');
	my $curdashscriptdir = (($curdashscript && $curdashscript ne '')? dirname($curdashscript) . '/' : '');
	# compare with current, if same return
	return 0 if($curdashscriptdir eq '' || $curdashscriptdir eq Helpers::getAppPath());

	# check existing dashboard path
	unless(-f $curdashscript) {
		Helpers::createCrontab($Configuration::dashbtask, $Configuration::dashbtask);
		Helpers::setCronCMD($Configuration::dashbtask, $Configuration::dashbtask);
		Helpers::saveCrontab();
		return 0;
	}

	my $newdashscript = Helpers::getScript($Configuration::dashbtask);
	# check same path or not
	if($curdashscript ne $newdashscript) {
		Helpers::display(["\n", 'user', ' "', $_[0], '" ', 'is_already_having_active_setup_path', ' ', '"' . dirname($curdashscript) . '"', '. ']);
		Helpers::display(['re_configure_your_account_freshly', '.']);
		return 2;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: editBackupToLocation
# Objective				: Edit backup to location for the current user
# Added By				: Anil Kumar
#****************************************************************************************************/
sub editBackupToLocation {
	if (Helpers::getUserConfiguration('DEDUP') eq 'off') {
		my $rfl = Helpers::getUserConfiguration('BACKUPLOCATION');
		Helpers::display(['your_backup_to_device_name_is',(" \"" . $rfl . "\". "),'do_you_want_edit_this_y_or_n_?'], 1);

		my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if (lc($answer) eq 'y') {
			Helpers::setBackupToLocation();
		}

	} elsif (Helpers::getUserConfiguration('DEDUP') eq 'on') {
		my @devices = Helpers::fetchAllDevices();
		Helpers::findMyDevice(\@devices,"editMode") or Helpers::askToCreateOrSelectADevice(\@devices) or Helpers::retreat('failed');
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateEmailIDs
# Objective				: This subroutineis is used to edit user email ids
# Added By				: Anil Kumar
#****************************************************************************************************/
sub updateEmailIDs {
	my $emailList = editEmailsToDisplay();
	if($emailList eq "no_emails_configured") {
		Helpers::display(["\n", 'no_emails_configured', " ", 'do_you_want_edit_this_y_or_n_?'], 1);
	} else {
		Helpers::display(["\n",'configured_email_address_is', ' ', "\"$emailList\"", '. ', 'do_you_want_edit_this_y_or_n_?'], 1);
	}

	my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if(lc($answer) eq "y") {
		setEmailIDs();
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateAndExitFromEditMode
# Objective				: This subroutineis is used to update the edited values and come out from the edit mode.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub updateAndExitFromEditMode {
	Helpers::saveUserConfiguration() or Helpers::retreat('failed_to_save_user_configuration');
	exit 0;
}

#*****************************************************************************************************
# Subroutine			: cleanUp
# Objective				: This subroutineis is used to clean the temp files.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub cleanUp {
	system('stty', 'echo');
	if (Helpers::getServicePath()) {
		Helpers::rmtree("Helpers::getServicePath()/$Configuration::downloadsPath");
		Helpers::rmtree("Helpers::getServicePath()/$Configuration::tmpPath");
	}
	exit;
}

#*****************************************************************************************************
# Subroutine			: editFailedFilePercentage
# Objective				: Edit the percentage to notify as 'Failure' if the total files failed for backup is more than it.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub editFailedFilePercentage {
	my $failedPercent = Helpers::getUserConfiguration('NFB');
	Helpers::display(["\n",'your_failed_files_per_set_to' , $failedPercent, '%. ',"\n", 'if_total_files_failed_for_backup', 'do_u_really_want_to_edit', "\n"], 0, [$failedPercent]);

	my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if($choice eq "y" or $choice eq "Y") {
		my $answer = Helpers::getAndValidate(['enter_failed_files_percentage_to_notify_as_failure'], "failed_percent", 1);
		Helpers::setUserConfiguration('NFB', $answer);
		Helpers::display(['your_failed_files_per_set_to', $answer, '%.', "\n\n"], 0);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: editMissingFilePercentage
# Objective				: Edit the percentage to notify as 'Failure' if the total files missing for backup is more than it.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub editMissingFilePercentage {
	my $missingPercent = Helpers::getUserConfiguration('NMB');
	Helpers::display(["\n",'your_missing_files_per_set_to' , $missingPercent, '%. ',"\n", 'if_total_files_missing_for_backup', 'do_u_really_want_to_edit', "\n"], 0, [$missingPercent]);

	my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if($choice eq "y" or $choice eq "Y") {
		my $answer = Helpers::getAndValidate(['enter_missing_files_percentage_to_notify_as_failure'], "missed_percent", 1);
		Helpers::setUserConfiguration('NMB', $answer);
		Helpers::display(['your_missing_files_per_set_to', $answer, '%.', "\n\n"], 0);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: editIgnorePermissionDeniedError
# Objective				: Ignore file/folder level access rights/permission errors
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub editIgnorePermissionDeniedError {
	my $prevStatus  = 'enabled';
	my $statusQuest = 'disable';
	if (Helpers::getUserConfiguration('IFPE') ne '') {
		unless(Helpers::getUserConfiguration('IFPE')){
			$prevStatus  = 'disabled';
			$statusQuest = 'enable';
		}
		Helpers::display(["\n",'your_ignore_permission_is_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
		my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		if ($choice eq "n") {
			return 1;
		}
	}

	Helpers::setUserConfiguration('IFPE', ($prevStatus eq 'disabled')? 1 : 0);
	Helpers::display(['your_ignore_permission_is_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: isSettingLocked
# Objective				: check and return whether settings locked or not.
# Added By				: Senthil Pandian, Yogesh Kumar
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub isSettingLocked {
	my $configField = $Configuration::userConfigurationLockSchema{$_[0]};
	return 0 unless($configField);
	my $ls = Helpers::getPropSettings('master');
	if (exists $ls->{'set'} and $ls->{'set'}{$configField} and $ls->{'set'}{$configField}{'islocked'}) {
		Helpers::display(['admin_has_locked_settings']);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: editShowHiddenFiles
# Objective				: Enable/Disable Show hidden files/folders
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub editShowHiddenFiles {
	my $prevStatus  = 'enabled';
	my $statusQuest = 'disable';
	if (Helpers::getUserConfiguration('SHOWHIDDEN') ne '') {
		unless(Helpers::getUserConfiguration('SHOWHIDDEN')){
			$prevStatus  = 'disabled';
			$statusQuest = 'enable';
		}
		Helpers::display(["\n",'your_show_hidden_is_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
		my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		if ($choice eq "n") {
			return 1;
		}
	}

	Helpers::setUserConfiguration('SHOWHIDDEN', ($prevStatus eq 'disabled')? 1 : 0);
	Helpers::display(['your_show_hidden_is_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);

	Helpers::removeBKPSetSizeCache('backup');
	Helpers::removeBKPSetSizeCache('localbackup');

	return 1;
}

#*****************************************************************************************************
# Subroutine			: editDesktopAccess
# Objective				: Enable/Disable Desktop Access
# Added By				: Senthil Pandian
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub editDesktopAccess {
	my $prevStatus  = 'disabled';
	my $statusQuest = 'enable';
	if (Helpers::getUserConfiguration('DDA') ne '') {
		unless(Helpers::getUserConfiguration('DDA')){
			$prevStatus  = 'enabled';
			$statusQuest = 'disable';
		}
		Helpers::display(["\n",'your_desktop_access_is_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
		my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		if ($choice eq "n") {
			return 1;
		}
	}

	Helpers::setUserConfiguration('DDA', ($prevStatus eq 'disabled')? 0 : 1);
	Helpers::display(['your_desktop_access_is_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);
	Helpers::saveUserConfiguration(0);
	Helpers::checkAndStartDashboard() unless(Helpers::getUserConfiguration('DDA'));
	return 1;
}

#*****************************************************************************************************
# Subroutine			: moveServiceDirectory
# Objective				: Move/copy current service directory to new.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub moveServiceDirectory
{
	my $servicePath        = $_[0];
	my $newServicePathPath = $_[1];
	my ($moveResult, $copyResult, $sourceUserPath, $destUserPath);
	if(!-d $newServicePathPath){
		$moveResult = system("mv '$servicePath' '$newServicePathPath' 2>/dev/null");
		return ($moveResult)?0:1;
	} else {
		Helpers::display(["Service directory ", "\"$newServicePathPath\" ", 'already_exists']);
		if(-d "$servicePath/cache"){
			unless(-d "$newServicePathPath/cache"){
				$moveResult = system("mv '$servicePath/cache' '$newServicePathPath/cache' 2>/dev/null");
				return 0 if($moveResult);
			} else {
				$sourceUserPath = "$newServicePathPath/$Configuration::cachedIdriveFile";
				$destUserPath   = "$newServicePathPath/$Configuration::cachedIdriveFile"."_bak_".time;
				$copyResult = system("cp -rpf '$sourceUserPath' '$destUserPath' 2>/dev/null");
				return 0 if($copyResult);
				$copyResult = system("cp -rpf '$servicePath/$Configuration::cachedIdriveFile' '$newServicePathPath/$Configuration::cachedIdriveFile' 2>/dev/null");
				return 0 if($copyResult);
			}
		}

		$sourceUserPath  = "$servicePath/$Configuration::userProfilePath";
		$destUserPath 	 = "$newServicePathPath/$Configuration::userProfilePath";
		if(-d $sourceUserPath){
			if(!-d $destUserPath){
				$moveResult = system("mv '$sourceUserPath' '$destUserPath' 2>/dev/null");
				return 0 if($moveResult);
				goto REMOVE;
			}
			opendir(USERPROFILEDIR, $sourceUserPath) or die $!;
			while (my $lmUserDir = readdir(USERPROFILEDIR)) {
				# Use a regular expression to ignore files beginning with a period
				next if ($lmUserDir =~ m/^\./);
				if(-d "$sourceUserPath/$lmUserDir"){
					if(!-d "$destUserPath/$lmUserDir"){
						$moveResult = system("mv '$sourceUserPath/$lmUserDir' '$destUserPath/$lmUserDir' 2>/dev/null");
						return 0 if($moveResult);
						next;
					}
					opendir(LMUSERDIR, "$sourceUserPath/$lmUserDir") or die $!;
					while (my $idriveUserDir = readdir(LMUSERDIR)) {
						# Use a regular expression to ignore files beginning with a period
						next if ($idriveUserDir =~ m/^\./);
						next unless(-d $idriveUserDir);
						my $source = "$sourceUserPath/$lmUserDir/$idriveUserDir";
						my $dest   = "$destUserPath/$lmUserDir/$idriveUserDir";
						if(!-e "$destUserPath/$lmUserDir/$idriveUserDir"){
							$moveResult = system("mv '$source' '$dest' 2>/dev/null");
							return 0 if($moveResult);
							next;
						}
						$sourceUserPath = $dest;
						$destUserPath   = $dest."_bak_".time;
						$copyResult = system("cp -rpf '$sourceUserPath' '$destUserPath' 2>/dev/null");
						return 0 if($copyResult);

						$copyResult = system("cp -rpf '$source' '$dest' 2>/dev/null");
						return 0 if($copyResult);
						next;
					}
					closedir(LMUSERDIR);
				}
			}
			closedir(USERPROFILEDIR);
		}
	}
REMOVE:
	system("rm -rf '$servicePath' 2>/dev/null");
	return 1;
}

# #*****************************************************************************************************
# # Subroutine			: addAndRemovePartialExcludeEntry
# # Objective				: Enable/Disable Show hidden files/folders
# # Added By				: Senthil Pandian
# #****************************************************************************************************/
# sub addAndRemovePartialExcludeEntry {
	# my $excludePartialPath  = Helpers::getUserFilePath($Configuration::excludeFilesSchema{'partial_exclude'}{'file'});
	# my @ec     = ();
	# my %ecInfo = ();
	# my $excludeStr = "^.";
	# if (-f $excludePartialPath) {
		# my $excludeContent	= Helpers::getFileContents($excludePartialPath);
		# @ec = split("\n", $excludeContent);
		# open(my $filesetContentInfo, '>', ($excludePartialPath));
		# if($_[0] eq 'y'){
			# print $filesetContentInfo "$excludeStr\n$excludeContent";
		# } else {
			# @ec = grep { !/^\^\.$/ } @ec;
			# my @ec1 = map{"$_\n"} @ec;
			# print $filesetContentInfo @ec1;
		# }
		# close($filesetContentInfo);
	# }

	# if (-f "$excludePartialPath.info") {
		# my $excludeInfoContent = Helpers::getFileContents("$excludePartialPath.info");
		# %ecInfo = split("\n", $excludeInfoContent);
	# }

	# if (open(my $filesetContentInfo, '>', ("$excludePartialPath.info")) and open(my $filesetContent, '<', $excludePartialPath)) {
		# while(my $filename = <$filesetContent>) {
			# chomp($filename);
			# Helpers::trim($filename);
			# if (exists $ecInfo{$filename}) {
				# print $filesetContentInfo "$filename\n";
				# print $filesetContentInfo "$ecInfo{$filename}\n";
			# }
			# elsif ($filename ne '') {
				# print $filesetContentInfo "$filename\n";
				# print $filesetContentInfo "enabled\n";
			# }
		# }
		# close($filesetContentInfo);
		# close($filesetContent);

		# Helpers::loadNotifications() and Helpers::setNotification('get_settings') and Helpers::saveNotifications();
	# } else {
		# Helpers::retreat(['failed_to_open_file',":$excludePartialPath.info","\n\n"]);
	# }
	# return 1;
# }
