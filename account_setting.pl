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

use Common;
use AppConfig;
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

# handle fedora 34 package missing
checkFedora34Packages() if(isFedora34());

Common::waitForUpdate();
Common::initiateMigrate();
init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [25/04/2018], Sabin Cheruvattil, Vijay Vinoth, Senthil Pandian
#*****************************************************************************************************
sub init {
	$AppConfig::isautoinstall = 1 if(defined($ARGV[0]) && $ARGV[0] eq $AppConfig::autoinstall);

	unless($AppConfig::isautoinstall) {
		system("clear") and Common::retreat('failed_to_clear_screen');
	}

	Common::loadAppPath();
	my $localeMvCmd = '';

	Common::loadMachineHardwareName() or Common::retreat('unable_to_find_system_information');

	#Verify hostname
	if ($AppConfig::hostname eq '') {
		Common::retreat('your_hostname_is_empty');
	}

	my $autoproxy = (defined($ARGV[1]) && $ARGV[1])? $ARGV[1] : '';

	Common::display(['setting_up_your_app_account', '...']) if($AppConfig::isautoinstall);

	# If unable to load service path then take service path from user and create meta data for it
	unless (Common::loadServicePath()) {
		Common::displayHeader();
		processZIPPath();

		Common::display(["\n", 'please_provide_your_details_below', "\n"], 1) unless($AppConfig::isautoinstall);
		unless (Common::checkAndUpdateServicePath()) {
			Common::createServiceDirectory();
		}

		Common::createVersionCache($AppConfig::version) if(!-f Common::getVersionCachePath());
	}
	else {
		Common::loadUsername() and Common::loadUserConfiguration();
		Common::displayHeader();
		Common::unloadUserConfigurations();
		processZIPPath();

		unless($AppConfig::isautoinstall) {
			Common::display(["\n", 'your_service_directory_is',Common::getServicePath()]);
		} else {
			Common::display(['default_service_directory_path', ': ', Common::getServicePath()]);
		}
	}

    # Fetching & verifying OS & build version
    Common::getOSBuild(1);

    Common::checkInstallDBCDPPreRequisites();

	my $confexists = 0;
	$confexists = 1 if(-f Common::getUserFile() or -f Common::getOldUserFile());

	# Display machine hardware details
	Common::display(["\n", 'hardware_platform', '... '], 0);
	my $mcarc = Common::getMachineHardwareName();
	$mcarc .= '-bit' if (defined($mcarc) && $mcarc ne 'arm');
	Common::display($mcarc . "\n");

	# validate existing EVS binary or download compatible one
	my $isProxy = 0;
	my %proxyDetails ;
	my $nl = 0;
	if (!Common::hasEVSBinary() or ($AppConfig::appType eq 'IDrive' and (Common::hasStaticPerlSupport() and !Common::hasStaticPerlBinary())) or
			!Common::hasPythonBinary()) {
		if (defined($ARGV[0]) and !$AppConfig::isautoinstall) {
			getDependentBinaries();
		}
		else {
			# If user name provided is not configured then ask proxy details
			Common::loadUserConfiguration();

			if ($AppConfig::isautoinstall and $autoproxy) {
				Common::askProxyDetails($autoproxy) or Common::retreat('kindly_verify_ur_proxy');
			}
			elsif (!$AppConfig::isautoinstall) {
				Common::askProxyDetails() or Common::retreat('kindly_verify_ur_proxy');
			}

			unless (Common::hasEVSBinary()) {
				$nl = 1;
				unless($AppConfig::isautoinstall) {
					Common::display(['downloading_evs_binary', '... ']);
				}
				else {
					Common::display(['downloading_auto_evs_binary', '... '], 0);
				}

				Common::downloadEVSBinary() or Common::retreat('unable_to_download_evs_binary');
				unless($AppConfig::isautoinstall) {
					Common::display('evs_binary_downloaded_successfully');
				}
				else {
					Common::display('ok_c');
				}
			}

			unless (Common::hasPythonBinary()) {
				$nl = 1;
				if($AppConfig::isautoinstall) {
					Common::display(['downloading_auto_python_binary', '... '], 0);
				}
				else {
					Common::display(['downloading_python_binary', '... ']);
				}

				Common::downloadPythonBinary() or Common::retreat('unable_to_download_python_binary');

				if($AppConfig::isautoinstall) {
					Common::display('ok_c');
				}
				else {
					Common::display('python_binary_downloaded_successfully');
				}
			}

			if ($AppConfig::appType eq 'IDrive') {
				if (Common::hasStaticPerlSupport() and not Common::hasStaticPerlBinary()) {
					$nl = 1;
					unless($AppConfig::isautoinstall) {
						Common::display(['downloading_static_perl_binary', '... ']);
					}
					else {
						Common::display(['downloading_auto_static_perl_binary', '... '], 0);
					}

					Common::downloadStaticPerlBinary() or Common::retreat('unable_to_download_static_perl_binary');
					unless($AppConfig::isautoinstall) {
						Common::display(['static_perl_binary_downloaded_successfully',"\n"]);
					}
					else {
						Common::display('ok_c');
					}
				}
				%proxyDetails = Common::getUserConfiguration('dashboard');
			}
			$isProxy=1;
		}
	}

	#Common::loadEVSBinary() or Common::retreat('unable_to_find_or_execute_evs_binary');
	#Commented & modified by Senthil for Yuvaraj_2.12_2_1 on 21-Mar-2019
	Common::loadEVSBinary() or Common::retreat('unable_to_find_compatible_evs_binary');

	Common::display('') if ($nl and $AppConfig::isautoinstall);

	if (!$AppConfig::isautoinstall) {
		Common::askProxyDetails() unless (Common::getProxyStatus());
	}
	elsif ($AppConfig::isautoinstall and $autoproxy) {
		Common::askProxyDetails($autoproxy) unless (Common::getProxyStatus());
	}

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

	Common::setUsername($uname);

	my $errorKey = Common::loadUserConfiguration();

	#validate user account
	#Common::display('verifying_your_account_info', 1);

	# Get IDrive/IBackup username list associated with email address
	$uname = Common::getUsernameList($uname) if (Common::isValidEmailAddress($uname));

	$errorKey = Common::loadUserConfiguration();
	$isAccountConfigured = ($errorKey == 1 or $errorKey == 100) ? 1 : 0;

	# validate IDrive user details
	my @responseData = Common::authenticateUser($uname, $emailID, 0, $loginType) or Common::retreat(['failed_to_authenticate_user',"'$uname'."]);
	my $upasswd = $responseData[0]->{'p'};

	Common::loadUsername();
	my $loggedInUser = Common::getUsername() || $uname;

	# Section to switch user - Start
	unless ($uname eq $loggedInUser) {
		Common::display(["\nSwitching user from \"", $loggedInUser , "\" to \"", $uname, "\" will stop all your running jobs and disable all your schedules for \"", $loggedInUser, "\". Do you really want to continue (y/n)?"], 1);
		my $userChoice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if (lc($userChoice) eq 'n' ) {
			cleanUp();
			return;
		}

		Common::stopDashboardService($AppConfig::mcUser, Common::getAppPath());
	}

	my $isLoggedin = Common::isLoggedin(); #Kept here for Harish_2.3_10_3: Senthil

	# check crontab validity
	unless(Common::checkCrontabValidity()) {
		Common::display(['corrupted_crontab_found', '.']);
		Common::display(['do_you_want_to_continue_yn']);
		my $resetchoice = Common::getAndValidate(['enter_your_choice'], 'YN_choice', 1);

		exit(0) if ($resetchoice ne 'y');

		Common::traceLog('Crontab corrupted. Resetting:');
		Common::traceLog(Common::getFileContents(Common::getCrontabFile()));

		Common::fileWrite(Common::getCrontabFile(), '');
		Common::addBasicUserCRONEntires();
	}

	processManualUpdate($confexists);

	my $accswitch = 0;
	if($AppConfig::appType eq 'IDrive') {
		Common::loadCrontab();
		my $ct = Common::getCrontab();
		my $ce = Common::getCurrentUserDashBdConfPath($ct, $AppConfig::mcUser, $uname);

		if ($ce and $ce ne '') {
			my $cip = Common::getDashboardScript();
            my $dsp = Common::getScriptPathOfDashboard($ce);
            my $csp = Common::getScriptPathOfDashboard($cip);

        	if ($ce ne $cip and $dsp ne $csp) {
				Common::display(["\n", 'Linux user', ' "', $AppConfig::mcUser, '" ', 'is_already_having_active_setup_path', ' ', '"' . $dsp . '"', '. '], 0);
				Common::display(["\n",'config_same_user_will_del_old_schedule', ' '], 0);
				Common::display([ 'do_you_want_to_continue_yn']);
				my $resetchoice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);

				# user doesn't want to reset the dashboard job, check and start dashboard job
				exit(0) if ($resetchoice eq 'n');
				$accswitch = 1;
				# Common::unloadUserConfigurations(); #Commented by Senthil : 17-Sep-2019
			}
		}
	}

	Common::setUsername($uname);
	# Section to switch user - End

	if ($responseData[0]->{'STATUS'} eq 'SUCCESS') {
		unless ($uname eq $loggedInUser) {
			Common::updateCronForOldAndNewUsers($loggedInUser, $uname);
			Common::deactivateOtherUserCRONEntries($uname);
			Common::updateUserLoginStatus($uname, 0);
		}
		else {
			Common::updateUserLoginStatus($uname, 0, 1);
		}

		Common::setUserConfiguration('USERNAME', $uname);
		
		Common::createUserDir($isAccountConfigured); #unless($isAccountConfigured); Commented by Senthil to create dir for Local Restore
		Common::saveUserQuota(@responseData) or Common::retreat("Error in save user quota");
		Common::setUserConfiguration(@responseData);
		Common::saveServerAddress(@responseData);
	}

	# creates all password files
	Common::createEncodePwdFiles($upasswd);
	Common::getServerAddress();

	# ask user choice for account configuration and configure the account
	if (Common::getUserConfiguration('USERCONFSTAT') eq 'NOT SET') {
		my ($configType, @result);
		my $encKey = '';
		if (defined($responseData[0]->{'subacc_enckey_flag'}) and $responseData[0]->{'subacc_enckey_flag'} eq 'Y'){
			$configType = 2;
		}
		else {
			Common::display(['please_configure_your', ' ', $AppConfig::appType, ' ', 'account_with_encryption']);
			my @options = (
				'default_encryption_key',
				'private_encryption_key'
			);
			Common::displayMenu('', @options);
			$configType = Common::getUserMenuChoice(scalar(@options));
		}

		if ($configType == 2) {
			$encKey = Common::getAndValidate(['set_your_encryption_key',": "], "config_private_key", 0);
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

		Common::setUserConfiguration('ENCRYPTIONTYPE', $configType);
		Common::configAccount($configType, $encKey);
		Common::display(['encryption_key_is_set_successfully', "\n"], 1);
		$isAccountConfigured = 0;
		if (-e Common::getUserConfigurationFile()) {
			Common::setUserConfiguration('BACKUPLOCATION', "");
			Common::setUserConfiguration('BACKUPLOCATIONSIZE', 0);
			Common::setUserConfiguration('RESTOREFROM', "");
			Common::createBackupStatRenewalByJob('backup') if(Common::getUsername() ne '' && Common::getLoggedInUsername() eq Common::getUsername());
		}
	}
	elsif (Common::getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
		my $needToRetry=0;
	VERIFY:
		my $encKey = Common::getAndValidate(["\n",'enter_your'," encryption key: "], "private_key", 0);
		my @responseData = ();
		Common::display('verifying_your_encryption_key',1);
		my $rmCmd   = Common::getIDPVTFile();
		my $rmCmdORG= $rmCmd . '_ORG';
		if (-f $rmCmd && !-f $rmCmdORG){
			my $localermCmd = Common::updateLocaleCmd("mv \"$rmCmd\" \"$rmCmdORG\" 2>/dev/null");
			`$localermCmd` ;
		}

		# this is to create encrypted PVT file and PVTSCH file
		Common::encodePVT($encKey);
		if (Common::getUserConfiguration('DEDUP') eq 'on') {
			@responseData = Common::fetchAllDevices();
		}
		else {
			# validate private key for non dedup account
			Common::createUTF8File('PING')  or Common::retreat('failed_to_create_utf8_file');
			@responseData = Common::runEVS();
		}
		my $userProfileDir  = Common::getUserProfilePath();
		if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
			if ($responseData[0]->{'MSG'} eq 'encryption_verification_failed') {
				Common::removeItems($rmCmd) if ($rmCmd and $rmCmd =~ /$userProfileDir/);
				if (-f $rmCmdORG){
					my $localermCmdORG = Common::updateLocaleCmd("mv \"$rmCmdORG\" \"$rmCmd\" 2>/dev/null");
					`$localermCmdORG` ;
				}

				if(Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
					Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'pvt_verification_failed'}) and Common::saveNotifications();
					Common::unlockCriticalUpdate("notification");
				}

				Common::retreat('invalid_enc_key');
			}
			elsif ($responseData[0]->{'MSG'} =~ /$AppConfig::proxyNetworkError/i) {
			#elsif ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407 Proxy Authentication Required|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/) {
				if ($isAccountConfigured and !$needToRetry){
					if (updateProxyOP()){
						$needToRetry=1;
						Common::removeItems($rmCmd) if ($rmCmd =~ /$userProfileDir/);
						if (-f $rmCmdORG){
							$localeMvCmd = Common::updateLocaleCmd("mv \"$rmCmdORG\" \"$rmCmd\" 2>/dev/null");
							`$localeMvCmd`;
						}
						goto VERIFY;
					}
				}
				Common::retreat(["\n", 'kindly_verify_ur_proxy']);
			}
			elsif ($responseData[0]->{'MSG'} eq 'private_encryption_key_must_be_between_4_and_256_characters_in_length') {
				Common::removeItems($rmCmd) if ($rmCmd =~ /$userProfileDir/);
				if (-f $rmCmdORG){
					$localeMvCmd = Common::updateLocaleCmd("mv \"$rmCmdORG\" \"$rmCmd\" 2>/dev/null");
					`$localeMvCmd`;
				}
				Common::retreat(['encryption_key_must_be_minimum_4_characters',"."]);
			}
			elsif ($responseData[0]->{'MSG'} =~ /account is under maintenance/i) {
				Common::removeItems($rmCmd) if ($rmCmd =~ /$userProfileDir/);
				Common::updateAccountStatus($uname, 'M');
				Common::retreat(['your_account_is_under_maintenance']);
			}
			elsif (Common::getUserConfiguration('DEDUP') eq 'on') {
				if ($responseData[0]{'MSG'} =~ 'No devices found') {
					Common::display(['verification_of_encryption_key_is_successfull',"\n"],1);
				}
				else {
					Common::retreat(ucfirst(Common::getLocaleString($responseData[0]->{'MSG'})));
				}
			}
		}
		else {
			Common::display(['verification_of_encryption_key_is_successfull',"\n"], 1);
		}
	}

	# Added as per Deepak review comment : Senthil
	if ($isAccountConfigured && (($loggedInUser ne $uname) || !$isLoggedin)) {
		my $loginConfirmation = 'y';		
		unless($AppConfig::isautoinstall) {
			Common::display(["\n",'do_u_want_to_login_as', "\"$uname\"", ' (y/n)?'],1);
			$loginConfirmation = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
            Common::display('',0);
            if (lc($loginConfirmation) eq 'y' ) {
                if ($loggedInUser ne "" && ($loggedInUser ne $uname)) {
                    Common::updateCronForOldAndNewUsers($loggedInUser, $uname);
                    Common::deactivateOtherUserCRONEntries($uname);
                }

                Common::updateUserLoginStatus($uname, 1) or Common::retreat('unable_to_login_please_try_login_script');
                Common::setCDPInotifySupport();
                Common::startCDPWatcher(1) unless(Common::isCDPServicesRunning());
            }
		}
	}

	verifyExistingBackupLocation();

	Common::copy(Common::getIDPVTFile(), Common::getIDPVTSCHFile());
	Common::changeMode(Common::getIDPVTSCHFile());

	# Launch CRON service from here
	manageCRONLaunch();

	if (-z Common::getCrontabFile() or $accswitch) {
		Common::addBasicUserCRONEntires();
		Common::resetUserCRONSchemas($accswitch);
	}

	# Add CDP watcher to CRON | it may just call in the next line | wont update if entry already present
	Common::addCDPWatcherToCRON();
	my ($dirswatch, $jsjobselems, $jsitems);
	if ($isAccountConfigured) {
		($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();

		unless(Common::getUserConfiguration('CDPSUPPORT')) {
			Common::setCDPInotifySupport();
		}
	}

	if(!Common::isCDPServicesRunning() or !Common::isCDPWatcherRunning()) {
		my $msgdisp = ($isAccountConfigured and Common::getUserConfiguration('CDPSUPPORT') and scalar(@{$dirswatch}))? 1 : 0;
		Common::display(['starting_cdp_services', '...']) if($msgdisp);
		Common::restartAllCDPServices();
		if($msgdisp) {
			Common::isCDPWatcherRunning()? Common::display(['cdp_service_started', '.']) : Common::display(['failed_to_start_cdp_service', '.']);
		}
	}

	if ((Common::getUserConfiguration('DELCOMPUTER') eq 'D_1') or (Common::getUserConfiguration('DELCOMPUTER') eq '')) {
			Common::setUserConfiguration('DELCOMPUTER', 'S_1');
			Common::saveUserConfiguration(0);
	}
	# manage dashboard here
	manageDashboardJob($accswitch) if ($AppConfig::appType eq 'IDrive');

	my $needsbasecron = 0;
	if ($isAccountConfigured) {
		Common::display(["\n",'your_account_details_are', ":\n"]);
		Common::display([
			"__title_backup__","\n",
			"\t","backup_location_lc", (' ' x 33), ': ',
			((Common::getUserConfiguration('DEDUP') eq 'on') and index(Common::getUserConfiguration('BACKUPLOCATION'), '#') != -1 )? (split('#', (Common::getUserConfiguration('BACKUPLOCATION'))))[1] :  Common::getUserConfiguration('BACKUPLOCATION'),"\n",
			(Common::getUserConfiguration('DEDUP') eq 'off')? ("\t",'backup_type', (' ' x 37), ': ', Common::getUserConfiguration('BACKUPTYPE'),"\n"): "",
			(Common::canKernelSupportInotify()? ("\t", 'backupset_rescan_interval', (' ' x 23),       ': ', getCDPRescanInterval(), "\n") : ''),
			"\t",'bandwidth_throttle', (' ' x 27),     ': ', Common::getUserConfiguration('BWTHROTTLE'),"\n",
			"\t",'edit_failed_backup_per', (' ' x 33), ': ', Common::getUserConfiguration('NFB'), "\n",
			"\t",'ignore_permission_denied', (' ' x 7),': ', Common::colorScreenOutput(Common::getUserConfiguration('IFPE')? 'enabled' : 'disabled'), "\n",
			"\t",'edit_missing_backup_per', (' ' x 32),': ', Common::getUserConfiguration('NMB'), "\n",
			# "__title_cdp__","\n",
			# "\t", 'cdp_title', (' ' x 45),       ': ', (Common::getUserConfiguration('CDP')? 'enabled' : 'disabled'), "\n",
			"\t",'show_hidden_files', (' ' x 23),      ': ', Common::colorScreenOutput(Common::getUserConfiguration('SHOWHIDDEN')? 'enabled' : 'disabled'), "\n",
			"\t",'upload_multiple_chunks', (' ' x 6),  ': ', Common::colorScreenOutput((Common::getUserConfiguration('ENGINECOUNT') != $AppConfig::minEngineCount)? 'enabled' : 'disabled'),"\n",
			"__title_general_settings__","\n",
		],0);

		if($AppConfig::appType eq 'IDrive' and (Common::getUserConfiguration('RMWS') ne 'yes')){
			Common::display([
			"\t",'desktop_access', (' ' x 34),         ': ', Common::colorScreenOutput(Common::getUserConfiguration('DDA')? 'disabled' : 'enabled')]);
		}

		Common::display([
			"\t",'title_email_address', (' ' x 34),    ': ', editEmailsToDisplay(),"\n",
			"\t",'edit_proxy', (' ' x 35),             ': ', editProxyToDisplay(),"\n",
			#"\t",'retain_logs', (' ' x 37),            ': ', (Common::getUserConfiguration('RETAINLOGS')? 'enabled' : 'disabled'), "\n",
			"\t",'edit_service_path', (' ' x 36),      ': ', Common::getServicePath(), "\n",
			"\t",'notify_software_update', (' ' x 20), ': ', Common::colorScreenOutput(Common::getUserConfiguration('NOTIFYSOFTWAREUPDATE')? 'enabled' : 'disabled'), "\n",
			"__title_restore_settings__","\n",
			"\t",'restore_from_location', (' ' x 27), ': ',
			((Common::getUserConfiguration('DEDUP') eq 'on') and index(Common::getUserConfiguration('RESTOREFROM'), '#') != -1 )? (split('#', (Common::getUserConfiguration('RESTOREFROM'))))[1] :  Common::getUserConfiguration('RESTOREFROM'),
			"\n",
			"\t",'restore_location', (' ' x 32),       ': ', Common::getUserConfiguration('RESTORELOCATION'),"\n",
			"\t",'restore_loc_prompt', (' ' x 25),     ': ', Common::colorScreenOutput(Common::getUserConfiguration('RESTORELOCATIONPROMPT')? 'enabled' : 'disabled'), "\n",
			"__title_services__",
		]);

		my $cdpstat = '';
		unless(Common::canKernelSupportInotify()) {
			$cdpstat = Common::colorScreenOutput('c_stopped');
		} else {
			$cdpstat = Common::colorScreenOutput(Common::isCDPWatcherRunning() and Common::hasFileNotifyPreReq()? 'c_running' : 'c_stopped');
		}
		
		Common::display([
			"\t", 'app_cdp_service', (' ' x 37),       ': ', $cdpstat,
		]);

		if($AppConfig::appType eq 'IDrive') {
			Common::display([
				"\t",'app_dashboard_service', (' ' x 31),  ': ', Common::colorScreenOutput((Common::isUserDashboardRunning($uname))? 'c_running' : 'c_stopped'), (Common::getUserConfiguration('DDA') ? 'c_disabled' : ''),"\n",
				"\t",'app_cron_service', (' ' x 29),       ': ', Common::colorScreenOutput((Common::checkCRONServiceStatus() == Common::CRON_RUNNING)? 'c_running' : 'c_stopped'), "\n",
			]);
		}
		else {
			Common::display([
				"\t",'app_cron_service', (' ' x 28),       ': ', Common::colorScreenOutput((Common::checkCRONServiceStatus() == Common::CRON_RUNNING)? 'c_running' : 'c_stopped'), "\n",
			]);
		}

		Common::createVersionCache($AppConfig::version);

		my $confmtime = stat(Common::getUserConfigurationFile())->mtime;
		#display user configurations and edit/reset options.
		tie(my %optionsInfo, 'Tie::IxHash',
			're_configure_your_account_freshly' => sub { $isAccountConfigured = 0; $needsbasecron = 1; },
			'edit_your_account_details' => sub { editAccount($loggedInUser, $confmtime); },
			'exit' => sub {
				if ((Common::getUserConfiguration('DELCOMPUTER') eq 'D_1') or (Common::getUserConfiguration('DELCOMPUTER') eq '')) {
					Common::setUserConfiguration('DELCOMPUTER', 'S_1');
				}
				Common::saveUserConfiguration();
				exit 0;
			},
		);

		my @options = keys %optionsInfo;

		while(1){
			Common::display(["\n", 'do_you_want_to', ':', "\n"]);
			Common::displayMenu('enter_your_choice', @options);
			my $userSelection = Common::getUserChoice();
			if (Common::validateMenuChoice($userSelection, 1, scalar(@options))) {
				$optionsInfo{$options[$userSelection - 1]}->();
				last;
			}
			else{
				Common::display(['invalid_choice', ' ', 'please_try_again', '.']);
			}
		}
	}

	Common::addBasicUserCRONEntires() if($needsbasecron);
	my $status = 0;
	unless ($isAccountConfigured) {
		$status = Common::setBackupToLocation();
		Common::retreat('failed_to_set_backup_location') unless ($status);
		Common::setRestoreLocation() or Common::retreat('failed_to_set_restore_location');
		Common::display('') if($AppConfig::isautoinstall);
		Common::setRestoreFromLocation() or Common::retreat('failed_to_set_restore_from');

		unless ($status == 2) {
			Common::setRestoreFromLocPrompt(1)or Common::retreat('failed_to_set_restore_from_prompt');
			Common::setNotifySoftwareUpdate() or Common::retreat('failed_to_set_software_update_notification');
			setEmailIDs()                      or Common::retreat('failed_to_set_email_id');
			# setRetainLogs(1)                 or Common::retreat('failed_to_set_retain_log');
			setBackupType()                    or Common::retreat('failed_to_set_backup_type');
			updateDefaultSettings()            or Common::retreat('failed_to_update_default_settings');
		}
		installUserFiles()                 or Common::retreat('failed_to_install_user_files');
	}

	Common::createVersionCache($AppConfig::version);

	if ((Common::getUserConfiguration('DELCOMPUTER') eq 'D_1') or (Common::getUserConfiguration('DELCOMPUTER') eq '')) {
		Common::setUserConfiguration('DELCOMPUTER', 'S_1');
	}

	Common::saveUserConfiguration((($status == 2) ? 0 : 1)) or Common::retreat('failed_to_save_user_configuration');
	Common::checkAndUpdateClientRecord($uname,$upasswd);
	Common::display(["\n", "\"$uname\""." is configured successfully. "], 0) unless($AppConfig::isautoinstall);

	if (($loggedInUser eq $uname) and $isLoggedin) {
		Common::display(["\n\n","User ", "\"$uname\"", " is already logged in." ], 1);
		# If bucket is deleted dashboard logs out the user while running account settings
		Common::updateUserLoginStatus($uname, 1);
	}
	else {
		my $loginConfirmation = 'y';
		
		unless($AppConfig::isautoinstall) {
			Common::display(['do_u_want_to_login_as', "\"$uname\"", ' (y/n)?'],1);
			$loginConfirmation = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		}

		if (lc($loginConfirmation) eq 'n' ) {
			Common::updateUserLoginStatus($uname, 0);
		}
		else {
			if ($loggedInUser ne "" && ($loggedInUser ne $uname)) {
				Common::updateCronForOldAndNewUsers($loggedInUser, $uname);
				Common::deactivateOtherUserCRONEntries($uname);
			}

			Common::updateUserLoginStatus($uname, 1, 1) or Common::retreat('unable_to_login_please_try_login_script');
			Common::setCDPInotifySupport();
			Common::startCDPWatcher(1) unless(Common::isCDPServicesRunning());
		}
	}

	if ($status == 2) {
		Common::display(["\n", 'syncing_your_settings_please_wait'], 1);
		if (Common::isDashboardRunning()) {
			while(Common::isDashboardRunning()) {
				last if (Common::loadNS() and not Common::getNS('update_device_info'));
				sleep(3);
			}

			Common::setCDPRescanCRON($AppConfig::defrescanday, $AppConfig::defrescanhr, $AppConfig::defrescanmin, 1);
			Common::display(['syncing_completed', "\n", 'note_for_replace_computer', "\n"]);
		}
		else {
			Common::display(['failed_to_restore_settings', "\n"]);
		}
	}

	if($AppConfig::isautoinstall) {
		Common::display(['scripts_are_setup_and_ready_to_use', '.', "\n"]);
		Common::display(['use_link_to_use_linux_web', '.']);
		Common::display([$AppConfig::IDriveWebURL, "\n"]);
	}
	
	cleanUp();
}

#*****************************************************************************************************
# Subroutine	: isFedora34
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks if the current OS is Fedora 34 or not
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub isFedora34 {
	my $os = Common::getOSBuild();
	return 1 if(($os->{'os'} =~ 'fedora' and $os->{'build'} >= 34) or ($os->{'os'} =~ 'centos' and $os->{'build'} >= 8));
	return 0;
}

#*****************************************************************************************************
# Subroutine	: getMissingPackages
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks and collects the missing packages
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getMissingPackages {
	my @stdPackages = keys(%{$_[0]});
	my @missingPackages = ();

	foreach my $pkg (@stdPackages) {
		my $pkgExists = 0;
		my $pmFile = $pkg;
		$pmFile =~ s/::/\//;
		$pmFile .= ".pm";

		foreach my $incPath (@INC) {
			my $pmPath = "$incPath/$pmFile";
			 if(-f $pmPath) {
				 $pkgExists = 1;
				 last;
			 }
		}

		push(@missingPackages, $pkg) if(!$pkgExists);
	}

	return \@missingPackages;
}

#*****************************************************************************************************
# Subroutine	: checkFedora34Packages
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Checks and processes package missing issue in fedora 34
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub checkFedora34Packages {
	my $missPacks = getMissingPackages(\%AppConfig::pmDNFPacksFed34);
	return 0 if(!scalar @{$missPacks});

	my @dnfPacks = map{$AppConfig::pmDNFPacksFed34{$_}} (@{$missPacks});

	system("clear");
	Common::loadAppPath();
	Common::displayHeader();
	
	Common::display(["\n", 'unable_to_find_the_dependency_packages']);

	for my $idx (0 .. $#dnfPacks) {
		Common::display([$idx + 1, ') ', $dnfPacks[$idx]]);
	}

	Common::display(["\n", 'following_packages_installed_to_continue']);
	my $userChoice = Common::getAndValidate(['enter_your_choice'], 'YN_choice', 1);

	exit(0) if(lc($userChoice) eq 'n');

	my $dnfcmd = "dnf -y install " . join(" ", @dnfPacks);
	my $sudomsgtoken = Common::hasSudo()? 'please_provide_sudo_pwd_for_init_packs' : 'please_provide_root_pwd_for_init_packs';
	$dnfcmd = Common::getSudoSuCMD($dnfcmd, $sudomsgtoken);
	system($dnfcmd);

	# Again check for the missing packages
	my $newMissPacks = getMissingPackages(\%AppConfig::pmDNFPacksFed34);
	if(scalar @{$newMissPacks}) {
		@dnfPacks = map{$AppConfig::pmDNFPacksFed34{$_}} (@{$missPacks});
		$AppConfig::displayHeader = 0;
		Common::retreat(['failed_to_install_following_packages', join(", ", @dnfPacks), '.']);
	}

	# load the missing packages
	foreach my $missPack (@{$missPacks}) {
		eval "use $missPack;";
	}

	# eval {
		# delete $INC{'Common'};
		# use Common;
	# };

	$AppConfig::displayHeader = 1;
	return 1;
}

#*****************************************************************************************************
# Subroutine			: verifyExistingBackupLocation
# Objective				: This is to verify the whether the backup locations are available or not.
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar, Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub verifyExistingBackupLocation {
	if ($isAccountConfigured) {
		my $isDedup	= Common::getUserConfiguration('DEDUP');
		my $qtf		= Common::getCachedStorageFile();
		if ($isDedup eq 'on') {
			my @result = Common::fetchAllDevices();
			#Added to consider the bucket type 'D' only
			my @devices;
			foreach (@result) {
				next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
				push @devices, $_;
			}

			my $isBucketAvailable = 1;
			unless(scalar(@devices)>0) {
				$isBucketAvailable = 0;
				# Common::display('no_backup_location_found_please_create_new_one');
				# return Common::createBucket();
			} else {
				unless (Common::findMyDevice(\@devices)) {
					#Ignoring deleted buckets
					my @availableBuckets;
					foreach (@devices) {
						next if ($_->{'in_trash'} eq '1');
						push @availableBuckets, $_;
					}
					unless(scalar(@availableBuckets)) {
						$isBucketAvailable = 0;
						# Common::display('no_backup_location_found_please_create_new_one');
						# return Common::createBucket();
					} else {
						my %buckets = Common::findMyBuckets(\@availableBuckets);
						unless (scalar(keys %buckets)) {
							$isBucketAvailable = 0;
						} else {
							Common::getExistingBucketConfirmation(\@devices, \%buckets);
						}
					}
				}
			}

			unless($isBucketAvailable) {
				$isAccountConfigured = 0;
				unlink($qtf) if(-f $qtf);
				unlink(Common::getUserConfigurationFile()) if (-f Common::getUserConfigurationFile());
				# If account reset happened or bucket got deleted and if dashboard didnt run
				Common::createBackupStatRenewalByJob('backup') if(Common::getUsername() ne '' && Common::getLoggedInUsername() eq Common::getUsername());
				return 0;
			}
			return 1;
		}

		my $jobRunningDir  = Common::getUserProfilePath();
		my $backupLocation = Common::getUserConfiguration('BACKUPLOCATION');

		if (substr($backupLocation, 0, 1) ne "/") {
			$backupLocation = ('/' . $backupLocation);
		}

		my $tempBackupsetFilePath = $jobRunningDir."/".$AppConfig::tempBackupsetFile;
		if (open(my $fh, '>', $tempBackupsetFilePath)) {
			print $fh $backupLocation;
			close($fh);
			chmod 0777, $tempBackupsetFilePath;
		}
		else
		{
			Common::traceLog("failed to create file. Reason: $!\n");
			return 0;
		}

		my $itemStatusUTFpath = $jobRunningDir.'/'.$AppConfig::utf8File;
		my $evsErrorFile      = $jobRunningDir.'/'.$AppConfig::evsErrorFile;
		Common::createUTF8File(['ITEMSTATUS',$itemStatusUTFpath], $tempBackupsetFilePath, $evsErrorFile,'') or Common::retreat('failed_to_create_utf8_file');

		my @responseData = Common::runEVS('item');

		unlink($tempBackupsetFilePath);

		if (-s $evsErrorFile > 0) {
			open(FILE, $evsErrorFile);
			if (grep{/failed to get the device information/} <FILE>){
				$isAccountConfigured = 0;
				unlink($qtf) if(-f $qtf);
				unlink(Common::getUserConfigurationFile()) if (-f Common::getUserConfigurationFile());
				Common::createBackupStatRenewalByJob('backup') if(Common::getUsername() ne '' && Common::getLoggedInUsername() eq Common::getUsername());
			}
			close FILE;
		}
		unlink($evsErrorFile);

		if ($isDedup eq 'off'){
			if ($responseData[0]{'status'} =~ /No such file or directory|directory exists in trash/) {
				$isAccountConfigured = 0;
				unlink($qtf) if(-f $qtf);
				unlink(Common::getUserConfigurationFile()) if (-e Common::getUserConfigurationFile());
				Common::createBackupStatRenewalByJob('backup') if(Common::getUsername() ne '' && Common::getLoggedInUsername() eq Common::getUsername());
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: editProxyToDisplay
# Objective				: Edit and format the proxy details in order to display the user accordingly.
# Added By				: Anil Kumar
# Modified By                           : Yogesh Kumar
#****************************************************************************************************/
sub editProxyToDisplay {
	my $proxyValue = Common::getProxyDetails('PROXY');
	if ($proxyValue ne "") {
		my ($pwd) = $proxyValue =~ /:([^\s@]+)/;
		$pwd = $pwd."@";
		my $newPwd = "***@";
		$proxyValue =~ s/$pwd/$newPwd/;
		$proxyValue =~ s/^://;
		$proxyValue =~ s/^@//;
		$proxyValue = $proxyValue;
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
	my $emailAddresses = Common::getUserConfiguration('EMAILADDRESS');
	$emailAddresses    = "no_emails_configured" if ($emailAddresses eq "");

	return $emailAddresses;
}

#*****************************************************************************************************
# Subroutine			: getCDPRescanInterval
# Objective				: This method gets the string to display the cdp rescan interval
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub getCDPRescanInterval {
	Common::loadCrontab(1);

	my $jobname	= 'default_backupset';
	my $h		= Common::getCrontab($AppConfig::cdprescan, $jobname, '{h}');
	$h			= sprintf("%02d", $h) if($h =~ /\d/);

	my $m		= Common::getCrontab($AppConfig::cdprescan, $jobname, '{m}');
	$m			= sprintf("%02d", $m) if($m =~ /\d/);

	my $cmd		= Common::getCrontab($AppConfig::cdprescan, $jobname, '{cmd}');
	my $dom		= (split(' ', $cmd))[-2];

	$dom		= '0' unless($dom);
Common::traceLog("dom:$dom#"); #Added to debug
	$dom		= sprintf("%02d", $dom) if($dom =~ /\d/);

	my $statmsg	= '';

	if($dom eq '01') {
		$statmsg	= Common::getLocaleString('daily_once') . " at $h:$m";
	} else {
		$statmsg	= Common::getLocaleString('once_in_x_days') . " at $h:$m";
		$statmsg	=~ s/__/$dom/;
	}

	return $statmsg;
}

#*****************************************************************************************************
# Subroutine			: processZIPPath
# Objective				: This method checks and and verifies zip package if passed
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub processZIPPath {
	# In case if user passed zip file of EVS binary.
	validateZipPath() if(defined($ARGV[0]) && !$AppConfig::isautoinstall);
}

#*****************************************************************************************************
# Subroutine			: manageDashboardJob
# Objective				: This method checks and manages the dashboard related activities and setup
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub manageDashboardJob {
	if(!$_[0]) {
		Common::lockCriticalUpdate("cron");
		Common::loadCrontab(1);
		my $curdashscript = Common::getCrontab($AppConfig::dashbtask, $AppConfig::dashbtask, '{cmd}');

		# account not configured | no cron tab entry | dashboard script empty
		if (!$curdashscript || $curdashscript eq '') {
			Common::createCrontab($AppConfig::dashbtask, $AppConfig::dashbtask);
			Common::setCronCMD($AppConfig::dashbtask, $AppConfig::dashbtask);
			Common::saveCrontab();
			Common::unlockCriticalUpdate("cron");
			Common::checkAndStartDashboard(0);
			return 1;
		}

		Common::unlockCriticalUpdate("cron");

		my $newdashscript = Common::getDashboardScript();
		# check same path or not
		if ($curdashscript eq $newdashscript) {
			# lets handle dashboard job; check and start dashboard
			return Common::checkAndStartDashboard(1);
		}

		# dashboard scripts are not the same. old path not valid | reset user's cron schemas to default
		unless(-f $curdashscript) {
			Common::resetUserCRONSchemas();
			return Common::checkAndStartDashboard(0);
		}
	}

	Common::lockCriticalUpdate("cron");
	Common::loadCrontab(1);
	my $curdashscript = Common::getCrontab($AppConfig::dashbtask, $AppConfig::dashbtask, '{cmd}');

	Common::createCrontab($AppConfig::dashbtask, $AppConfig::dashbtask);
	Common::setCronCMD($AppConfig::dashbtask, $AppConfig::dashbtask);
	Common::saveCrontab();
	Common::unlockCriticalUpdate("cron");
	
	# kill the running dashboard job
	$curdashscript = dirname($curdashscript);
	$curdashscript =~ s/$AppConfig::idriveLibPath//;
	Common::stopDashboardService($AppConfig::mcUser, $curdashscript);

	# kill all the running jobs belongs to this user
	my $cmd = sprintf("%s %s 'allOp' %s 0 'allType' %s %s", $AppConfig::perlBin, Common::getScript('job_termination', 1), Common::getUsername(), $AppConfig::mcUser, 'operation_cancelled_due_to_cron_reset');
	# $cmd = Common::updateLocaleCmd($cmd);
	`$cmd 1>/dev/null 2>/dev/null`;
	Common::checkAndStartDashboard(0);
}

#*****************************************************************************************************
# Subroutine			: manageCRONLaunch
# Objective				: This method checks the status of cron and launches it
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#*****************************************************************************************************
sub manageCRONLaunch {
	Common::removeFallBackCRONEntry() if($AppConfig::mcUser eq 'root');

	if(Common::checkCRONServiceStatus() != Common::CRON_RUNNING) {
		Common::display(["\n", 'setting_up_cron_service', ' ', 'please_wait_title', '...']);

		my $maxtry = $AppConfig::maxChoiceRetry;
		while($maxtry) {
			$maxtry--;

			my $sudoprompt = 'please_provide_' . (Common::hasSudo()? 'sudoers' : 'root') . '_pwd_for_cron';
			my $sudosucmd = Common::getSudoSuCRONPerlCMD('installcron', $sudoprompt);
			my $res = system($sudosucmd);

			if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
				Common::display(['cron_service_started',"\n"]);
				last;
			}
			else {
				Common::display('unable_to_start_cron_service', 0);
				Common::display('please_make_sure_you_are_sudoers_list') if($res);
				Common::display("\n");
			}

			if(!$maxtry) {
				Common::display(["\n", 'your_max_attempt_reached', "\n"]);
			}
		}

		return 1;
	}

	# compare the version of current script and the running script from the lock
	# if the running version is older, replace the link and update the lock file to self restart
	my @lockinfo = Common::getCRONLockInfo();
	if (Common::versioncompare($AppConfig::version, $lockinfo[1]) == 1) {
		my $sudoprompt = 'please_provide_' . (Common::hasSudo()? 'sudoers' : 'root') . '_pwd_for_cron_update';
		my $sudosucmd = Common::getSudoSuCRONPerlCMD('restartidriveservices', $sudoprompt);
		my $res = system($sudosucmd);
		if($res) {
			Common::display(['failed_to_update_cron'], 0);
			Common::display(['please_make_sure_you_are_sudoers_list']) if($AppConfig::mcUser ne 'root');
		} else {
			Common::display(['successfully_updated_cron', '.']);
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: processManualUpdate
# In Param				: UNDEF
# Out Param				: UNDEF
# Objective				: Checks and processes manual update
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub processManualUpdate {
	my $csrversion = Common::getCurrentConfScriptVersion();
	if(($csrversion ne '0' and Common::versioncompare($csrversion, $AppConfig::version)) or ($_[0] and !-f Common::getVersionCachePath() and -f Common::getCrontabFile())) {
		Common::display(["\n", 'updating_the_configuration_and_scripts']);
		Common::deleteDeprecatedScripts();
		Common::fixPathDeprecations();
		Common::fixBackupsetDeprecations();
		Common::removeDeprecatedDB();
		Common::addCDPWatcherToCRON(1);
		Common::setCDPInotifySupport();
		Common::startCDPWatcher();
		# Deprecated path validation is present in fixDashbdDeprecPath. So dont worry about multiple path profile configuration
		Common::fixDashbdDeprecPath();

		Common::loadCrontab(1);
		my $cdpcmd = Common::getCrontab($AppConfig::cdprescan, 'default_backupset', '{cmd}');
		Common::setCDPRescanCRON($AppConfig::defrescanday, $AppConfig::defrescanhr, $AppConfig::defrescanmin, 1) unless($cdpcmd);

		Common::createRescanRequest();

		# Download latest binaries before restarting Cron/Dashboard services
		if (Common::fetchInstalledEVSBinaryVersion()) {
			if (-f Common::getCatfile(Common::getServicePath(), $AppConfig::evsBinaryName)) {
				Common::removeItems(Common::getCatfile(Common::getServicePath(), $AppConfig::evsBinaryName));
			}
			if (-f Common::getCatfile(Common::getServicePath(), $AppConfig::evsDedupBinaryName)) {
				Common::removeItems(Common::getCatfile(Common::getServicePath(), $AppConfig::evsDedupBinaryName));
			}

			Common::updateEVSBinary();
		}

        unless (Common::hasPythonBinary())
		{
            if (Common::updatePythonBinary()) {
                Common::display('python_binary_downloaded_successfully');
            }
            else {
                Common::retreat('unable_to_download_python_binary');
            }
        }

		if ($AppConfig::appType eq 'IDrive') {
			if (Common::fetchInstalledPerlBinaryVersion()) {
				if (-f Common::getCatfile(Common::getServicePath(), $AppConfig::staticPerlBinaryName)) {
					Common::removeItems(Common::getCatfile(Common::getServicePath(), $AppConfig::staticPerlBinaryName));
				}

				Common::updatePerlBinary() if(Common::hasStaticPerlSupport());
			}
		}

		Common::createVersionCache($AppConfig::version);
		Common::stopDashboardService($AppConfig::mcUser, Common::getAppPath()) if ($AppConfig::appType eq 'IDrive');
		Common::processCronForManualInstall();

		if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
			my @lockinfo = Common::getCRONLockInfo();
			if($lockinfo[2] and $lockinfo[2] ne $AppConfig::cronSetup) {
				$lockinfo[2] = 'restart';
				$lockinfo[3] = 'update';
				Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
				Common::display(['updated_the_configuration_and_scripts', "\n"]);
				return 1;
			}
		}

		# if cron link is absent, reinstall the cron | this case can be caused by un-installation from other installation
		my $sudoprompt = 'please_provide_' . (Common::hasSudo()? 'sudoers' : 'root') . '_pwd_for_cron_update';
		my $sudosucmd = Common::getSudoSuCRONPerlCMD('restartidriveservices', $sudoprompt);

		 Common::display(system($sudosucmd) == 0? 'cron_service_has_been_restarted' : 'failed_to_restart_idrive_services');

		Common::display(["\n", 'updated_the_configuration_and_scripts']);
		return 1;
	}
}

#*****************************************************************************************************
# Subroutine			: validateZipPath
# Objective				: This subroutine will check the user provided zip file whether it is suitable to the machine or not.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub validateZipPath {
	Common::retreat(["\n", 'absolute_path_required', "\n"]) if ($ARGV[0] =~ m/\.\./);
	Common::retreat(["\n", 'file_not_found', ": ",  $ARGV[0], "\n"]) if (!-e $ARGV[0]);

	my $machineName = Common::getMachineHardwareName();
	if ($ARGV[0] !~ /$machineName/) {
		#my $evsWebPath = "https://www.idrivedownloads.com/downloads/linux/download-options/IDrive_Linux_" . $machineName . ".zip";
		my $evsWebPath = Common::getEVSBinaryDownloadPath($machineName);
		Common::retreat(["\n", 'invalid_zip_file', "\n", $evsWebPath, "\n"]);
	}
}

#*****************************************************************************************************
# Subroutine			: getDependentBinaries
# Objective				: Get evs & static perl binaries.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub getDependentBinaries {
	my $machineName = Common::getMachineHardwareName();
	my $zipFilePath = getZipPath($ARGV[0]);
	Common::unzip($zipFilePath, Common::getServicePath()) or Common::retreat('unzip_failed_unable_to_unzip');;
	#my $downloadsPath = Common::getServicePath() . "/". $ARGV[0]; #Commented by Senthil for Snigdha_2.16_13_3
	my $downloadsPath = Common::getServicePath() . "/". fileparse($ARGV[0]);
	$downloadsPath =~ s/.zip//g;
	$downloadsPath = $downloadsPath . "/";

	my $ezf    = $AppConfig::evsZipFiles{$AppConfig::appType}{$machineName};

	for my $i (0 .. $#{$ezf}) {
		$ezf->[$i] =~ s/__APPTYPE__/$AppConfig::appType/g;

		my $binPath = $downloadsPath.$ezf->[$i];
		$binPath =~ s/\.zip//g;
		my $changeMode = Common::updateLocaleCmd("chmod $AppConfig::filePermissionStr '$binPath/'*");
		`$changeMode` if (-e $binPath);

		last if (Common::hasEVSBinary($binPath));
	}

	unless (Common::hasPythonBinary()) {
		my $pyexe = ($AppConfig::machineOS =~ /freebsd/i) ?
									$AppConfig::pythonZipFiles{"freebsd"} :
									$AppConfig::pythonZipFiles{$machineName};
		$pyexe =~ s/__KVER__/$AppConfig::kver/g;

		my $pybin = Common::getCatfile($downloadsPath, $pyexe);
		$pybin =~ s/\.zip//g;
		$pybin = Common::getECatfile($pybin);
		Common::rmtree(Common::getCatfile(Common::getAppPath(), $AppConfig::idrivePythonBinPath));
		my $cppytbin = Common::updateLocaleCmd(("cp -rf $pybin " . Common::getECatfile(Common::getAppPath(), $AppConfig::idriveDepPath)));
		`$cppytbin`;
		my $privl = Common::updateLocaleCmd(("chmod -R 0755 " . Common::getECatfile(Common::getAppPath(), $AppConfig::idriveDepPath)));
		`$privl`;
	}

	if ($AppConfig::appType eq 'IDrive') {
		$ezf = [$AppConfig::staticperlZipFiles{$machineName}];
		if ($AppConfig::machineOS =~ /freebsd/i) {
			$ezf = [$AppConfig::staticperlZipFiles{'freebsd'}];
		}

		for my $i (0 .. $#{$ezf}) {
			my $binPath = $downloadsPath.$ezf->[$i];
			$binPath =~ s/\.zip//g;
			if (-e $binPath){
				my $currDirLocalCmd = Common::updateLocaleCmd("chmod $AppConfig::filePermissionStr '$binPath/'*");
				`$currDirLocalCmd` ;
			}

			last if (Common::hasStaticPerlBinary($binPath));
		}
	}
	Common::rmtree("$downloadsPath");
}

#*****************************************************************************************************
# Subroutine			: getZipPath
# Objective				: This subroutine will return the absolute path of the zip file path user provided.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getZipPath {
	my $zipPath = $_[0];
	if ($zipPath =~ /^\//){
		return $zipPath;
	}
	my $currDirLocalCmd = Common::updateLocaleCmd('pwd');
	my $currDirLocal = `$currDirLocalCmd`;
	chomp($currDirLocal);

	$zipPath = $currDirLocal."/".$zipPath;
	chomp($zipPath);
	return $zipPath;
}

#*****************************************************************************************************
# Subroutine		: setEmailIDs
# Objective			: This subroutine is used to set email id's
# Added By			: Anil Kumar
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************
sub setEmailIDs {
	return 1 if($AppConfig::isautoinstall);

	my $emailAddresses = Common::getAndValidate(["\n", 'enter_your_email_id', ': '], "single_email_address", 1, 0);

	$emailAddresses =~ s/;/,/g;
	if ($emailAddresses ne "") {
		my $editFormatToDisplay = '"'.$emailAddresses.'"';
		Common::display(['configured_email_address_is', ' ', $editFormatToDisplay]);
	}
	else {
		Common::display(['no_emails_configured'],1);
	}

	Common::setUserConfiguration('EMAILADDRESS', $emailAddresses);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setBandwidthThrottle
# Objective				: This subroutineis is used to set BWTHROTTLE value
# Added By				: Anil Kumar
#****************************************************************************************************/
sub setBandwidthThrottle {
# modified by anil on 30may2018
	Common::display(['your_bw_value_set_to' , Common::getUserConfiguration('BWTHROTTLE'), '%. ', 'do_u_really_want_to_edit', "\n"],0);

	my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	if ($choice eq "y" or $choice eq "Y") {
		my $answer = Common::getAndValidate(['enter_bw_value'], "bw_value", 1);
		Common::setUserConfiguration('BWTHROTTLE', $answer);
		Common::display(['your_bw_value_set_to', $answer, '%.', "\n\n"], 0);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setRetainLogs
# Objective				: This subroutineis is used to set retail logs value for an account
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************************************/
# sub setRetainLogs {
	# my $retainLogs = 1;

	# if (Common::getUserConfiguration('RETAINLOGS') ne '' || (defined($_[0]) && $_[0] == 1)) {
		# $retainLogs = 0 unless(Common::getUserConfiguration('RETAINLOGS'));
		# $retainLogs = 0 if (defined($_[0]));

		# unless(defined($_[0])) {
			# Common::display(["\n", "your_retain_logs_is_$retainLogs\_?"], 1);
		# } else {
			# Common::display(["\n", "do_you_want_to_retain_logs"], 1);
		# }

		# my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		# $choice = lc($choice);
		# $retainLogs = ($retainLogs ? 0 : 1) if ($choice eq 'y');
		# Common::setUserConfiguration('RETAINLOGS', $retainLogs);
	# }

	# Common::display(["your_retain_logs_is_$retainLogs"]);
	# return 1;
# }

#*****************************************************************************************************
# Subroutine			: setBackupType
# Objective				: This subroutineis is used to set backup type value
# Added By				: Anil Kumar
#****************************************************************************************************/
sub setBackupType {
	if (Common::getUserConfiguration('DEDUP') eq 'on' or $AppConfig::isautoinstall) {
		Common::setUserConfiguration('BACKUPTYPE', 'mirror');
		return 1;
	}

	my $backuptype = displayBackupTypeOP();
	Common::setUserConfiguration('BACKUPTYPE', ($backuptype == 1)?'mirror':'relative');
	Common::display(["your_backup_type_is_set_to", "\"", Common::getUserConfiguration('BACKUPTYPE'), "\"."]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getAndSetBackupType
# Objective				: This subroutineis is used to get Backup type value from user and set it
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getAndSetBackupType {
	if (Common::getUserConfiguration('DEDUP') eq 'on') {
		Common::display(['your_backup_type_is_set_to', "\"", Common::getUserConfiguration('BACKUPTYPE'),"\". ", "\n"]);
		return 1;
	}

	Common::display(['your_backup_type_is_set_to', "\"", Common::getUserConfiguration('BACKUPTYPE'),"\". ", 'do_u_really_want_to_edit' , "\n"]);
	my $answer = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if ($answer eq "y" or $answer eq "Y") {
		my $backuptype = displayBackupTypeOP();
		Common::setUserConfiguration('BACKUPTYPE', ($backuptype == 1)?'mirror':'relative');
		Common::display(["your_backup_type_is_changed_to", "\"", Common::getUserConfiguration('BACKUPTYPE'), "\".\n"]);

		Common::createBackupStatRenewalByJob('backup');
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
	Common::display(["\n", "select_op_for_backup_type"]);
	Common::display("1) Mirror");
	Common::display("2) Relative");

	my $answer = Common::getUserMenuChoice(2);
	return $answer;
}

#*****************************************************************************************************
# Subroutine			: updateProxyOP
# Objective				: This subroutineis is used to update proxy options
# Added By				: Anil Kumar
#****************************************************************************************************/
sub updateProxyOP {
	my $proxyDetails = editProxyToDisplay();
	if ( $proxyDetails eq "No Proxy") {
		Common::display(["\n",'your_proxy_has_been_disabled'," ", 'do_you_want_edit_this_y_or_n_?'], 1);
	}
	else {
		Common::display(["\n","Your proxy details are \"",$proxyDetails, "\". ", 'do_you_want_edit_this_y_or_n_?'], 1);
	}

	my $answer = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		Common::askProxyDetails("update");
		Common::saveUserConfiguration() or Common::retreat('failed_to_save_user_configuration');
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
	my $oldServicedir = Common::getServicePath();
	Common::display(["\n","Your service directory is \"",$oldServicedir, "\". ", 'do_you_want_edit_this_y_or_n_?'], 1);
	my $answer = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		# need to check any jobs are running here.
		Common::display(["\n","changing_service_directory_will_terminate_all_the_running_jobs", 'do_you_want_edit_this_y_or_n_?'], 1);
		$answer = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		return 1 if (lc($answer) eq "n") ;

		Common::checkForRunningJobsInOtherUsers() or Common::retreat("One or more backup/local backup/restore/archive cleanup/continuous data protection jobs are in process with respect to others users. Please make sure those are completed and try again.");

		my $servicePathSelection = Common::getAndValidate(["\n", 'enter_your_new_service_path'], "service_dir", 1);
		if ($servicePathSelection eq '') {
			$servicePathSelection = dirname(Common::getAppPath());
		}
		$servicePathSelection = Common::getAbsPath($servicePathSelection);
		my $checkPath         = substr $servicePathSelection, -1;
		$servicePathSelection = $servicePathSelection ."/" if ($checkPath ne '/');
		my $newSerDir         = Common::getCatfile($servicePathSelection,$AppConfig::servicePathName);
		my $oldSerDir         = Common::getCatfile($oldServicedir);
		if ($oldSerDir eq $newSerDir) {
			Common::display('same_service_dir_path_has_been_selected');
			return 1;
		}

		my $cmd = sprintf("%s %s allOp - 0 allType %s %s", $AppConfig::perlBin, Common::getScript('job_termination', 1), $AppConfig::mcUser, 'operation_cancelled_due_to_service_dir_change');
		$cmd = Common::updateLocaleCmd($cmd);
		my $res = `$cmd 1>/dev/null 2>/dev/null`;

		while (Common::getRunningJobs()) {
			sleep(1);
		}

		if (Common::isDashboardRunning()) {
			Common::stopDashboardService($AppConfig::mcUser, dirname(__FILE__));
			while (Common::isDashboardRunning()) {
				sleep(1);
			}
		}

		Common::stopAllCDPServices() if(Common::isCDPWatcherRunning());

		my $moveResult = moveServiceDirectory($oldSerDir, $newSerDir);
		#my $moveResult = `mv '$oldSerDir' '$newSerDir' 2>/dev/null`;

		# added by anil on 31may2018
		if ($moveResult) {
			Common::saveServicePath($servicePathSelection.$AppConfig::servicePathName) or Common::retreat(['failed_to_create_directory',": $servicePathSelection"]);
			my $restoreLocation   = Common::getUserConfiguration('RESTORELOCATION');
			$servicePathSelection = $servicePathSelection.$AppConfig::servicePathName;
			my $tempOldServicedir = Common::getECatfile($oldServicedir);
			$restoreLocation      =~ s/$tempOldServicedir/$servicePathSelection/;

			my $oldPathForCron    = Common::getECatfile($oldServicedir, $AppConfig::userProfilePath);
			my $newPathForCron    = Common::getECatfile($servicePathSelection, $AppConfig::userProfilePath);
			#modified by anil on 01may2018
			my $updateCronEntryCmd = Common::updateLocaleCmd("sed 's/'$oldPathForCron'/'$newPathForCron'/g' '/etc/crontabTest' 1>/dev/null 2>/dev/null ");
			my $updateCronEntry   = `$updateCronEntryCmd`;

			Common::setUserConfiguration('RESTORELOCATION', $restoreLocation);
			Common::loadServicePath() or Common::retreat('invalid_service_directory');

			Common::retreat('failed_to_save_user_configuration') unless(Common::saveUserConfiguration());
			Common::display(['service_dir_updated_successfully', "\"", $servicePathSelection, "\"."]);

			Common::createVersionCache($AppConfig::version);
			Common::startCDPWatcher();
			Common::checkAndStartDashboard(0, 1);

			if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
				my @lockinfo = Common::getCRONLockInfo();
				$lockinfo[2] = 'restart';
				Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
			}

			return 1;
		}

		Common::retreat('please_try_again');
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateDefaultSettings
# Objective				: Update default settings to configuration file
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub updateDefaultSettings {
	if (-d $AppConfig::defaultMountPath) {
		if($AppConfig::isautoinstall) {
			my $msg	= Common::getStringConstant('auto_default_mount_point_local_backup');
			Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', $AppConfig::defaultMountPath, '.']);
		} else {
			Common::display(["\n",'your_default_mount_point_for_local_backup_set_to', "\"$AppConfig::defaultMountPath\"", ".\n"], 0);
		}

		Common::setUserConfiguration('LOCALMOUNTPOINT', $AppConfig::defaultMountPath);
	}

	#Common::display(["\n", 'by_default_retain_logs_option_is_enabled']);
	#Common::setUserConfiguration('RETAINLOGS', 1);

	my $failedPercent = $AppConfig::userConfigurationSchema{'NFB'}{'default'};
	Common::setUserConfiguration('NFB', $failedPercent);
	if($AppConfig::isautoinstall) {
		my $msg	= Common::getStringConstant('auto_default_failed_files_per');
		Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', $failedPercent . '%', '.']);
	} else {
		Common::display(["\n",'your_default_failed_files_per_set_to', $failedPercent, "%.\n", 'if_total_files_failed_for_backup', "\n"], 0, [$failedPercent]);
	}

	Common::setUserConfiguration('IFPE', $AppConfig::userConfigurationSchema{'IFPE'}{'default'});
	if($AppConfig::isautoinstall) {
		my $msg	= Common::getStringConstant('auto_ignore_permission');
		Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', 'cc_disabled']);
	} else {
		Common::display(["\n",'by_default_ignore_permission_is_disabled', "\n"],0);
	}

	Common::setUserConfiguration('SHOWHIDDEN', $AppConfig::userConfigurationSchema{'SHOWHIDDEN'}{'default'});

	if ($AppConfig::appType eq 'IDrive') {
		Common::setUserConfiguration('DDA', $AppConfig::userConfigurationSchema{'DDA'}{'default'});

		if($AppConfig::isautoinstall) {
			my $msg	= Common::getStringConstant('auto_desktop_access');
			Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', 'cc_enabled']);
		} else {
			Common::display(["\n", 'your_desktop_access_is_enabled', "\n"],0);
		}
	}

	Common::setUserConfiguration('ENGINECOUNT', $AppConfig::userConfigurationSchema{'ENGINECOUNT'}{'default'});
	if($AppConfig::isautoinstall) {
		my $msg	= Common::getStringConstant('auto_upload_multiple_file_chunks');
		Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', 'cc_enabled']);
	} else {
		Common::display(["\n", 'by_default_upload_multiple_file_chunks_option_is_enabled', "\n"],0);
	}

	my $missingPercent = $AppConfig::userConfigurationSchema{'NMB'}{'default'};
	Common::setUserConfiguration('NMB', $missingPercent);
	if($AppConfig::isautoinstall) {
		my $msg	= Common::getStringConstant('auto_default_missing_files_per');
		Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', $missingPercent . '%.']);
	} else {
		Common::display(["\n",'your_default_missing_files_per_set_to', $missingPercent, "%.\n", 'if_total_files_missing_for_backup', "\n"], 0, [$missingPercent]);
	}

	# CDP
	Common::setUserConfiguration('CDP', $AppConfig::userConfigurationSchema{'CDP'}{'default'});
	# Common::setDefaultCDPJob('01', 0, 1);

	# Rescan
	if(Common::canKernelSupportInotify()) {
		Common::setCDPRescanCRON($AppConfig::defrescanday, $AppConfig::defrescanhr, $AppConfig::defrescanmin, 1);
		if($AppConfig::isautoinstall) {
			my $msg	= Common::getStringConstant('auto_default_backupset_scan_interval');
			Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', "'" . Common::getLocaleString('daily_once') . "' at 12:00."]);
		} else {
			Common::display(["\n", 'your_default_cdp_scan_interval_is_set_to', "'" . Common::getLocaleString('daily_once') . "' at 12:00.", "\n"], 0);
		}
	}

	Common::setUserConfiguration('CDPSUPPORT', Common::canKernelSupportInotify());

	if($AppConfig::isautoinstall) {
		my $msg	= Common::getStringConstant('auto_default_missing_files_per');
		Common::display([$msg, ' ' x ($AppConfig::autoconfspc - length($msg)), ': ', '100%.']);
	} else {
		Common::display(["\n",'your_default_bw_value_set_to', '100%.', "\n\n"], 0);
	}

	Common::createUpdateBWFile($AppConfig::userConfigurationSchema{'BWTHROTTLE'}{'default'});
	Common::setUserConfiguration('BWTHROTTLE', $AppConfig::userConfigurationSchema{'BWTHROTTLE'}{'default'});

	return 1;
}

#*****************************************************************************************************
# Subroutine			: installUserFiles
# Objective				: This subroutineis is used to Install files like backupset/restoreset/fullexlcude etc...
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub installUserFiles {
	tie(my %filesToInstall, 'Tie::IxHash',
		%AppConfig::availableJobsSchema,
		%AppConfig::excludeFilesSchema
	);

	Common::fixPathDeprecations();

	# set default dashboard path if it is edit account
	Common::createCrontab($AppConfig::dashbtask, $AppConfig::dashbtask);
	Common::setCronCMD($AppConfig::dashbtask, $AppConfig::dashbtask);
	Common::saveCrontab();

	my $file;
	foreach (keys %filesToInstall) {
		my $schemakey = $_;
		$file = $filesToInstall{$_}{'file'};
		#Skipping for Archive as we not keeping any default backup set: Senthil

		next if($file =~ m/archive/i || $_ =~ m/$AppConfig::cdp/gi);

		$file =~ s/__SERVICEPATH__/Common::getServicePath()/eg;
		$file =~ s/__USERNAME__/Common::getUsername()/eg;
		if (open(my $fh, '>>', $file)) {
			Common::display(["your_default_$_\_file_created"]) unless($AppConfig::isautoinstall);
			close($fh);
			chmod 0777, $file;
		}
		else {
			Common::display(["\n",'unable_to_create_file', " \"$file\"." ]);
			return 0;
		}

		Common::fileWrite($file . ".info", "") if($schemakey =~ /exclude/);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: editAccount
# Objective				: This subroutineis is used to edit logged in user account
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil
#*****************************************************************************************************
sub editAccount {
	Common::display(["\n",'select_the_item_you_want_to_edit', ":\n"]);
	my $loggedInUser = $_[0];

	# load account settings if there has been a change in log
	my $confmtime = stat(Common::getUserConfigurationFile())->mtime;
	Common::loadUserConfiguration() if ($confmtime != $_[1]);

	tie(my %optionsInfo, 'Tie::IxHash',
		'__title_backup__backup_location_lc'                => \&editBackupToLocation,
		'__title_backup__backup_type'                       => \&getAndSetBackupType,
		'__title_backup__backupset_rescan_interval'			=> \&verifyBackupset,
		'__title_backup__bandwidth_throttle'                => \&setBandwidthThrottle,
		'__title_backup__edit_failed_backup_per'            => \&editFailedFilePercentage,
		'__title_backup__ignore_permission_denied'			=> \&editIgnorePermissionDeniedError,
		'__title_backup__edit_missing_backup_per'           => \&editMissingFilePercentage,
		'__title_backup__show_hidden_files'					=> \&editShowHiddenFiles,
		'__title_backup__upload_multiple_chunks'  			=> sub { Common::setUploadMultipleChunks(); },
		'__title_general_settings__desktop_access'          => \&editDesktopAccess,
		'__title_general_settings__title_email_address'  	=> sub { updateEmailIDs(); },
		'__title_general_settings__edit_proxy'              => \&updateProxyOP,
		#'__title_general_settings__retain_logs'             => \&setRetainLogs,
		'__title_general_settings__edit_service_path'       => \&updateServiceDir,
		'__title_general_settings__notify_software_update'  => sub { Common::setNotifySoftwareUpdate(); },
		'__title_restore_settings__restore_from_location'   => sub { Common::editRestoreFromLocation(); },
		'__title_restore_settings__restore_location'        => sub { Common::editRestoreLocation();	},
		'__title_restore_settings__restore_loc_prompt'      => sub { Common::setRestoreFromLocPrompt(); },
		'__title_services__start_restart_cdp_service'		=> \&restartCDPService,
		'__title_services__start_restart_dashboard_service' => sub { checkDashboardStart($loggedInUser); },
		'__title_services__restart_cron_service'            => sub { Common::confirmRestartIDriveCRON(); },
		'__title_empty__exit'                               => \&updateAndExitFromEditMode,
	);
	
	delete($optionsInfo{'__title_backup__backup_type'}) if (Common::getUserConfiguration('DEDUP') eq 'on');
	delete($optionsInfo{'__title_backup__backupset_rescan_interval'}) if (!Common::canKernelSupportInotify());

	if($AppConfig::appType eq 'IBackup') {
		delete $optionsInfo{'__title_general_settings__desktop_access'};
		delete $optionsInfo{'__title_services__start_restart_dashboard_service'};
	}
	elsif (Common::getUserConfiguration('RMWS') and (Common::getUserConfiguration('RMWS') eq 'yes')) {
		delete $optionsInfo{'__title_general_settings__desktop_access'};
	}

	my @options = keys %optionsInfo;
	Common::displayMenu('enter_your_choice', @options);
	my $editItem = Common::getUserChoice();
	if (Common::validateMenuChoice($editItem, 1, scalar(@options))) {
		if (!isSettingLocked($options[$editItem - 1])){
			$optionsInfo{$options[$editItem - 1]}->() or Common::retreat('failed');
		}
	}
	else{
		Common::display(['invalid_choice', ' ', 'please_try_again', '.']);
	}

	Common::saveUserConfiguration();
	$AppConfig::isUserConfigModified = 0;

	return editAccount($_[0], $confmtime);
}

#*****************************************************************************************************
# Subroutine			: restartCDPService
# Objective				: Check | show status | start cdp service
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub restartCDPService {
	my $startcdp = 'y';

	Common::display(['failed_to_start_cdp_service', '. ', 'your_machine_not_have_min_req_cdp', '.']) unless(Common::canKernelSupportInotify());

	unless(Common::hasFileNotifyPreReq()) {
		unlink(Common::getCDPHaltFile()) if(-f Common::getCDPHaltFile());
		Common::checkInstallDBCDPPreRequisites();
		return 1;
	}

	if (Common::isCDPServicesRunning()) {
		Common::display(["\n", 'cdp_service_running', '. ', 'do_you_want_to_restart_cdp_yn']);
		$startcdp = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	Common::restartAllCDPServices(1) if($startcdp eq 'y');
	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkDashboardStart
# Objective				: Check | show status | start dashboard
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub checkDashboardStart {
	unless (Common::hasDashboardSupport()) {
		Common::display('dashboard_is_not_supported_for_this_arc_yet');
		return 1;
	}

	if (Common::isDashboardRunning()) {
		if ($_[0] eq '') {
			Common::display(["\n", 'login_&_try_again']);
			return 1;
		}

		Common::display(((Common::getUsername() ne $_[0])? ["\n", 'dashboard_already_running_for_user', $_[0], ".\n"] : ["\n", 'dashboard_service_running', '. ']), 0);
		return 1 if (Common::getUsername() ne $_[0]);

		Common::display(['do_you_want_to_restart_dashboard']);
		my $answer = lc(Common::getAndValidate(['enter_your_choice'], "YN_choice", 1));
		if ($answer eq 'y') {
			Common::stopDashboardService($AppConfig::mcUser, dirname(__FILE__));

			if (Common::getUserConfiguration('DDA')) {
				Common::setUserConfiguration('DDA', 0);
				Common::display(['enabling_your_desktop_access']);
				Common::saveUserConfiguration(0);
			}

			if ((Common::getUserConfiguration('DELCOMPUTER') eq 'D_1') or (Common::getUserConfiguration('DELCOMPUTER') eq '')) {
					Common::setUserConfiguration('DELCOMPUTER', 'S_1');
					Common::saveUserConfiguration(0);
			}

			Common::confirmStartDashboard(1, 1);
			Common::checkAndStartDashboard(0, 1);
		}
		return 1;
	}

	return 1 if (confirmDuplicateDashboardInstance($_[0]) == 2);

	if (Common::getUserConfiguration('DDA')) {
		Common::setUserConfiguration('DDA', 0);
		Common::display(['enabling_your_desktop_access']);
		Common::saveUserConfiguration(0);
	}

	if ((Common::getUserConfiguration('DELCOMPUTER') eq 'D_1') or (Common::getUserConfiguration('DELCOMPUTER') eq '')) {
			Common::setUserConfiguration('DELCOMPUTER', 'S_1');
			Common::saveUserConfiguration(0);
	}

	Common::confirmStartDashboard(1);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: verifyBackupset
# Objective				: Helps to place rescan request/schedule the time
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub verifyBackupset {
	Common::display(["\n", 'enter_sno_press_p_or_e_to_exit']);

	tie(my %optionsInfo, 'Tie::IxHash',
		'rescan_now'			=> \&rescanNow,
		'schedule_for_later'	=> \&editCDPRescanFrequency
	);

	my @options = keys(%optionsInfo);
	Common::displayMenu('', @options);
	my $choice = Common::getAndValidate(['enter_your_choice'], "PEMenu_choice", 1, 1, scalar(@options));

	return 1 if($choice eq 'p');
	exit(0) if($choice eq 'e');

	$optionsInfo{$options[$choice - 1]}->();
	return 1;
}

#*****************************************************************************************************
# Subroutine			: editCDPRescanFrequency
# Objective				: Helps to update CDP rescan interval
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub editCDPRescanFrequency {
	Common::loadCrontab(1);

	Common::display(["\n", 'your_cdp_rescan_interval_is_set_to', ': [', getCDPRescanInterval(), ']. ', 'do_u_really_want_to_edit', "\n"], 0);
	my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if(lc($choice) eq "y") {
		my $dom = Common::getAndValidate(['enter_backupset_rescan_interval_in_days'], "cdp_rescan_interval", 1);
		my $h = Common::getAndValidate(['enter_hour_0_-_23', ': '], '24hours_validator', 1);
		my $m = Common::getAndValidate(['enter_minute_0_-_59', ': '], 'minutes_validator', 1);

		Common::setCDPRescanCRON($dom, $h, $m, 1);
	}
	
	Common::display(["\n", 'your_cdp_rescan_interval_is_set_to', ': [', getCDPRescanInterval(), '].'], 1);
}

#*****************************************************************************************************
# Subroutine			: rescanNow
# Objective				: This helps to show rescan message and places rescan request
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub rescanNow {
	my ($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
	if(!@{$dirswatch}) {
		Common::display(["\n", 'unable_to_place_rescan_request', '. ', 'backupset_is_empty', '.'], 1);
		return 1;
	}

	if(Common::createRescanRequest()) {
		Common::display(["\n", 'rescan_request_placed_success', '.'], 1);
	} else {
		Common::display(["\n", 'unable_to_place_rescan_request', '.'], 1);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: confirmDuplicateDashboardInstance
# Objective				: Confirm and terminate any dashboard if running for same user
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub confirmDuplicateDashboardInstance {
	return 0 if ($AppConfig::appType ne 'IDrive');

	Common::lockCriticalUpdate("cron");
	Common::loadCrontab(1);
	my $curdashscript = Common::getCrontab($AppConfig::dashbtask, $AppConfig::dashbtask, '{cmd}');
	my $curdashscriptdir = (($curdashscript && $curdashscript ne '')? dirname($curdashscript) . '/' : '');
	# compare with current, if same return
	if ($curdashscriptdir eq '' || $curdashscriptdir eq Common::getAppPath()) {
		Common::unlockCriticalUpdate("cron");
		return 0;
	}

	# check existing dashboard path
	unless(-f $curdashscript) {
		Common::createCrontab($AppConfig::dashbtask, $AppConfig::dashbtask);
		Common::setCronCMD($AppConfig::dashbtask, $AppConfig::dashbtask);
		Common::saveCrontab();
		Common::unlockCriticalUpdate("cron");
		return 0;
	}

	Common::unlockCriticalUpdate("cron");

	my $newdashscript = Common::getDashboardScript();
	# check same path or not
	if ($curdashscript ne $newdashscript) {
		Common::display(["\n", 'user', ' "', $_[0], '" ', 'is_already_having_active_setup_path', ' ', '"' . dirname($curdashscript) . '"', '. ']);
		Common::display(['re_configure_your_account_freshly', '.']);
		return 2;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: editBackupToLocation
# Objective				: Edit backup to location for the current user
# Added By				: Anil Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub editBackupToLocation {
	if (Common::getUserConfiguration('DEDUP') eq 'off') {
		my $rfl = Common::getUserConfiguration('BACKUPLOCATION');
		Common::display(['your_backup_to_device_name_is',(" \"" . $rfl . "\". "),'do_you_want_edit_this_y_or_n_?'], 1);

		my $answer = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if (lc($answer) eq 'y') {
			Common::setBackupToLocation();
		}
	}
	elsif (Common::getUserConfiguration('DEDUP') eq 'on') {
		my @result = Common::fetchAllDevices();
		#Added to consider the bucket type 'D' only
		my @devices;
		foreach (@result){
			next if(!defined($_->{'bucket_type'}) or $_->{'bucket_type'} !~ /D/);
			push @devices, $_;
		}

		unless (Common::findMyDevice(\@devices, 'editMode')) {
			my $status = Common::askToCreateOrSelectADevice(\@devices);
			Common::retreat('failed_to_set_backup_location') unless($status);
		}
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
	if ($emailList eq "no_emails_configured") {
		Common::display(["\n", 'no_emails_configured', " ", 'do_you_want_edit_this_y_or_n_?'], 1);
	}
	else {
		Common::display(["\n",'configured_email_address_is', ' ', "\"$emailList\"", '. ', 'do_you_want_edit_this_y_or_n_?'], 1);
	}

	my $answer = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
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
	Common::saveUserConfiguration() or Common::retreat('failed_to_save_user_configuration');
	exit 0;
}

#*****************************************************************************************************
# Subroutine			: cleanUp
# Objective				: This subroutineis is used to clean the temp files.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub cleanUp {
	system('stty', 'echo');
	if (Common::getServicePath()) {
		Common::rmtree("Common::getServicePath()/$AppConfig::downloadsPath");
		Common::rmtree("Common::getServicePath()/$AppConfig::tmpPath");
	}
	exit;
}

#*****************************************************************************************************
# Subroutine			: editFailedFilePercentage
# Objective				: Edit the percentage to notify as 'Failure' if the total files failed for backup is more than it.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub editFailedFilePercentage {
	my $failedPercent = Common::getUserConfiguration('NFB');
	Common::display(["\n",'your_failed_files_per_set_to' , $failedPercent, '%. ',"\n", 'if_total_files_failed_for_backup', 'do_u_really_want_to_edit', "\n"], 0, [$failedPercent]);

	my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if ($choice eq "y" or $choice eq "Y") {
		my $answer = Common::getAndValidate(['enter_failed_files_percentage_to_notify_as_failure'], "failed_percent", 1);
		Common::setUserConfiguration('NFB', $answer);
		Common::display(['your_failed_files_per_set_to', $answer, '%.', "\n\n"], 0);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: editMissingFilePercentage
# Objective				: Edit the percentage to notify as 'Failure' if the total files missing for backup is more than it.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub editMissingFilePercentage {
	my $missingPercent = Common::getUserConfiguration('NMB');
	Common::display(["\n",'your_missing_files_per_set_to' , $missingPercent, '%. ',"\n", 'if_total_files_missing_for_backup', 'do_u_really_want_to_edit', "\n"], 0, [$missingPercent]);

	my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if ($choice eq "y" or $choice eq "Y") {
		my $answer = Common::getAndValidate(['enter_missing_files_percentage_to_notify_as_failure'], "missed_percent", 1);
		Common::setUserConfiguration('NMB', $answer);
		Common::display(['your_missing_files_per_set_to', $answer, '%.', "\n\n"], 0);
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
	if (Common::getUserConfiguration('IFPE') ne '') {
		unless(Common::getUserConfiguration('IFPE')){
			$prevStatus  = 'disabled';
			$statusQuest = 'enable';
		}
		Common::display(["\n",'your_ignore_permission_is_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
		my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		if ($choice eq "n") {
			return 1;
		}
	}

	Common::setUserConfiguration('IFPE', ($prevStatus eq 'disabled')? 1 : 0);
	Common::display(['your_ignore_permission_is_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: isSettingLocked
# Objective				: check and return whether settings locked or not.
# Added By				: Senthil Pandian, Yogesh Kumar
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub isSettingLocked {
	my $configField = $AppConfig::userConfigurationLockSchema{$_[0]};
	return 0 unless($configField);
	my $ls = Common::getPropSettings('master');
	if (exists $ls->{'set'} and $ls->{'set'}{$configField} and $ls->{'set'}{$configField}{'islocked'}) {
		Common::display(['admin_has_locked_settings']);
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
	if (Common::getUserConfiguration('SHOWHIDDEN') ne '') {
		unless(Common::getUserConfiguration('SHOWHIDDEN')){
			$prevStatus  = 'disabled';
			$statusQuest = 'enable';
		}
		Common::display(["\n",'your_show_hidden_is_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
		my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		if ($choice eq "n") {
			return 1;
		}
	}

	Common::setUserConfiguration('SHOWHIDDEN', ($prevStatus eq 'disabled')? 1 : 0);
	Common::display(['your_show_hidden_is_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);

	Common::removeBKPSetSizeCache('backup');
	Common::removeBKPSetSizeCache('localbackup');
	Common::createJobSetExclDBRevRequest('hidden');

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
	if (Common::getUserConfiguration('DDA') ne '') {
		unless(Common::getUserConfiguration('DDA')){
			$prevStatus  = 'enabled';
			$statusQuest = 'disable';
		}
		Common::display(["\n",'your_desktop_access_is_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
		my $choice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		if ($choice eq "n") {
			return 1;
		}
	}

	Common::setUserConfiguration('DDA', ($prevStatus eq 'disabled')? 0 : 1);
	Common::display(['your_desktop_access_is_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);
	Common::saveUserConfiguration(1);
	Common::checkAndStartDashboard(1) unless(Common::getUserConfiguration('DDA'));
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
	my $cmd = '';
	if (!-d $newServicePathPath){
		$cmd = Common::updateLocaleCmd("mv '$servicePath' '$newServicePathPath' 2>/dev/null");
		$moveResult = system($cmd);
		return ($moveResult)?0:1;
	}
	else {
		Common::display(["Service directory ", "\"$newServicePathPath\" ", 'already_exists']);
		if (-d "$servicePath/cache"){
			unless(-d "$newServicePathPath/cache"){
				$cmd = Common::updateLocaleCmd("mv '$servicePath/cache' '$newServicePathPath/cache' 2>/dev/null");
				$moveResult = system($cmd);
				return 0 if ($moveResult);
			}
			else {
				if (-f "$newServicePathPath/$AppConfig::cachedIdriveFile") {
					$sourceUserPath = "$newServicePathPath/$AppConfig::cachedIdriveFile";
					$destUserPath   = "$newServicePathPath/$AppConfig::cachedIdriveFile"."_bak_".time;
					$cmd = Common::updateLocaleCmd("cp -rpf '$sourceUserPath' '$destUserPath' 2>/dev/null");
					$copyResult = system($cmd);
					return 0 if($copyResult);
				}

				$copyResult = system(Common::updateLocaleCmd("cp -rpf '$servicePath/$AppConfig::cachedIdriveFile' '$newServicePathPath/$AppConfig::cachedIdriveFile' 2>/dev/null"));
				return 0 if($copyResult);
			}
		}
		my @array = ($AppConfig::evsBinaryName, $AppConfig::evsDedupBinaryName, $AppConfig::staticPerlBinaryName);
		foreach my $item (@array) {
			if (-f "$servicePath/$item"){
				unless(-f "$newServicePathPath/$item"){
					$moveResult = system(Common::updateLocaleCmd("mv '$servicePath/$item' '$newServicePathPath/$item' 2>/dev/null"));
					return 0 if($moveResult);
				}
				else {
					$sourceUserPath = "$newServicePathPath/$item";
					$destUserPath   = "$newServicePathPath/$item"."_bak_".time;
					$copyResult = system(Common::updateLocaleCmd("cp -pf '$sourceUserPath' '$destUserPath' 2>/dev/null"));
					return 0 if($copyResult);
					$copyResult = system(Common::updateLocaleCmd("cp -pf '$servicePath/$item' '$newServicePathPath/$item' 2>/dev/null"));
					return 0 if($copyResult);
				}
			}
		}

		$sourceUserPath  = "$servicePath/$AppConfig::userProfilePath";
		$destUserPath 	 = "$newServicePathPath/$AppConfig::userProfilePath";
		if (-d $sourceUserPath){
			if (!-d $destUserPath){
				$moveResult = system(Common::updateLocaleCmd("mv '$sourceUserPath' '$destUserPath' 2>/dev/null"));
				return 0 if ($moveResult);
				goto REMOVE;
			}
			opendir(USERPROFILEDIR, $sourceUserPath) or die $!;
			while (my $lmUserDir = readdir(USERPROFILEDIR)) {
				# Use a regular expression to ignore files beginning with a period
				next if ($lmUserDir =~ m/^\./);
				if (-d "$sourceUserPath/$lmUserDir"){
					if (!-d "$destUserPath/$lmUserDir"){
						$moveResult = system(Common::updateLocaleCmd("mv '$sourceUserPath/$lmUserDir' '$destUserPath/$lmUserDir' 2>/dev/null"));
						return 0 if ($moveResult);
						next;
					}
					opendir(LMUSERDIR, "$sourceUserPath/$lmUserDir") or die $!;
					while (my $idriveUserDir = readdir(LMUSERDIR)) {
						# Use a regular expression to ignore files beginning with a period
						next if ($idriveUserDir =~ m/^\./);
						next unless(-d $idriveUserDir);
						my $source = "$sourceUserPath/$lmUserDir/$idriveUserDir";
						my $dest   = "$destUserPath/$lmUserDir/$idriveUserDir";
						if (!-e "$destUserPath/$lmUserDir/$idriveUserDir"){
							$moveResult = system(Common::updateLocaleCmd("mv '$source' '$dest' 2>/dev/null"));
							return 0 if ($moveResult);
							next;
						}
						$sourceUserPath = $dest;
						$destUserPath   = $dest."_bak_".time;
						$copyResult = system(Common::updateLocaleCmd("cp -rpf '$sourceUserPath' '$destUserPath' 2>/dev/null"));
						return 0 if ($copyResult);

						$copyResult = system(Common::updateLocaleCmd("cp -rpf '$source' '$dest' 2>/dev/null"));
						return 0 if ($copyResult);
						next;
					}
					closedir(LMUSERDIR);
				}
			}
			closedir(USERPROFILEDIR);
		}
	}
REMOVE:
	system(Common::updateLocaleCmd("rm -rf '$servicePath' 2>/dev/null"));
	return 1;
}
