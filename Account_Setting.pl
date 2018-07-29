#!/usr/bin/perl
#*****************************************************************************************************
# 						This script is used to configure the user account.
# 							Created By: Yogesh Kumar
#****************************************************************************************************/

use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')) ;	} else { use lib '.' ; }

use Helpers;
use Strings;
use Configuration;
use File::Basename;

use constant NO_EXIT => 1;
#Signal handling. Signals received by the script during execution
$SIG{INT}	= \&cleanUp;
$SIG{TERM}	= \&cleanUp;
$SIG{TSTP}	= \&cleanUp;
$SIG{QUIT}	= \&cleanUp;
#$SIG{PWR}	= \&cleanUp;
$SIG{KILL}	= \&cleanUp;
$SIG{USR1}	= \&cleanUp;
my $isAccountConfigured = 0;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [25/04/2018]
#****************************************************************************************************/
sub init {
	system("clear") and Helpers::retreat('failed_to_clear_screen');
	Helpers::loadAppPath();

	Helpers::loadMachineHardwareName() or Helpers::retreat('unable_to_find_system_information');
	
	#Verify hostname
	if ($Configuration::hostname eq '') {
		print Helpers::retreat('your_hostname_is_empty');
	}
	
	# In case if user passed zip file of EVS binary.
	if(defined($ARGV[0])) {
		validateZipPath();
	}
	else {
		push @Configuration::dependencyBinaries, 'wget';
	}
	
	# If unable to load service path then take service path from user and create meta data for it
	unless (Helpers::loadServicePath()) {
		Helpers::displayHeader();
		Helpers::findDependencies() or Helpers::retreat('failed');
		
		Helpers::display(["\n", 'please_provide_your_details_below',"\n"],1);
		unless (Helpers::checkAndUpdateServicePath()) {
			Helpers::display('enter_your_service_path', 0);
			my $servicePathSelection = Helpers::getUserChoice();
			$servicePathSelection =~ s/^~/Helpers::getUserHomePath()/g;

			# In case user want to go for optional service path 
			if ($servicePathSelection eq ''){
				$servicePathSelection = dirname(Helpers::getAppPath());
				Helpers::display(['your_default_service_directory'],1);
			}
			
			# Check if service path exist
			Helpers::retreat(['invalid_location', " \"$servicePathSelection\". ", "Reason: ", 'no_such_directory']) if (!-d $servicePathSelection);

			# Check if service path have write permission
			Helpers::retreat(['cannot_open_directory', " $servicePathSelection ", 'permission_denied'])	if (!-w $servicePathSelection);

			# get full path for service directory
			$servicePathSelection = Helpers::getCatfile($servicePathSelection, $Configuration::servicePathName);
			
			my $sp = '';
			$sp = Helpers::getAbsPath($servicePathSelection) or Helpers::retreat('no_such_directory_try_again');
			
			if (-d $sp) {
				Helpers::display(["Service directory ", "\"$sp\" ", 'already_exists']);
			}
			else {
				Helpers::createDir($sp) or Helpers::retreat('failed');
			}

			Helpers::saveServicePath($sp) or Helpers::retreat(['failed_to_create_directory',": $sp"]);
			Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
			Helpers::display(["\n",'your_service_directory_is',Helpers::getServicePath()]);
		}
	}
	else{
		Helpers::loadUsername() and Helpers::loadUserConfiguration(NO_EXIT);
		Helpers::displayHeader();
		Helpers::findDependencies() or Helpers::retreat('failed');
		Helpers::display(["\n",'your_service_directory_is',Helpers::getServicePath()]);
	}
	
	# Display machine hardware details
	Helpers::display(["\n",'hardware_platform', '... '], 0);
	Helpers::display(Helpers::getMachineHardwareName() . "-bit\n");
	
	# validate existing EVS binary or download compatible one
	my $isProxy=0;
	unless (Helpers::hasEVSBinary()) {
		if(defined($ARGV[0])){
			getEVSBinaryFromZip();
		}
		else{
			# If user name provided is not configured then ask proxy details
			Helpers::askProxyDetails() or Helpers::retreat('kindly_verify_ur_proxy');
			Helpers::display(['downloading_evs_binary', '... ']);
			Helpers::downloadEVSBinary() or Helpers::retreat('unable_to_download_evs_binary');
			Helpers::display('evs_binary_downloaded_sucessfully');
			$isProxy=1;
		}
	}
	
	Helpers::loadEVSBinary() or Helpers::retreat('unable_to_find_or_execute_evs_binary');
	
	# Get user name and validate
	my $uname = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType, " ", 'username', ': '], "username", 1);
	
	# Get password and validate
	my $upasswd = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType, " ", 'password', ': '], "password", 0);
	
	# Load logged in user name
	Helpers::loadUsername();
	my $loggedInUser = Helpers::getUsername();
	
	# set provided user name to environment
	Helpers::setUsername($uname);
	
	$isAccountConfigured = Helpers::loadUserConfiguration(NO_EXIT);
	
	# If user name provided is not configured then ask proxy details
	Helpers::askProxyDetails() or Helpers::retreat('failed') if(!$isAccountConfigured and !$isProxy);
	
	Helpers::display('verifying_your_account_info',1);
	
	# validate IDrive user details
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
		Helpers::display(['please_configure_your', ' ', $Configuration::appType, ' ', 'account_with_encryption']);
		my @options = (
			'default_encryption_key',
			'private_encryption_key'
		);
		Helpers::displayMenu('', @options);
		my $configType = Helpers::getUserMenuChoice(scalar(@options));
	
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
		unlink(Helpers::getUserConfigurationFile()) if(-e Helpers::getUserConfigurationFile());
		
	}
	elsif (Helpers::getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
		my $needToRetry=0;
	VERIFY:
		my $encKey = Helpers::getAndValidate(['enter_your'," encryption key: "], "private_key", 0);
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
			Helpers::retreat('invalid_enc_key');			
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407|execution_failed|kindly_verify_ur_proxy/)) {			
			if($isAccountConfigured and !$needToRetry){
				if(updateProxyOP()){
					$needToRetry=1;
					goto VERIFY;
				}
			}
			Helpers::retreat(["\n", 'kindly_verify_ur_proxy']);	
		} 
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'private_encryption_key_must_be_between_4_and_256_characters_in_length')) {
			`rm -rf '$rmCmd'`;
			Helpers::retreat(['encryption_key_must_be_minimum_4_characters',"."]);
		}
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} eq 'account_is_under_maintenance')) {
			`rm -rf '$rmCmd'`;
			Helpers::retreat(['Your account is under maintenance. Please contact support for more information',"."]);
		}	
		elsif (($responseData[0]->{'STATUS'} eq 'FAILURE') && (Helpers::getUserConfiguration('DEDUP') eq 'on') ){
			if ($responseData[0]{'MSG'} =~ 'No devices found') {
				return createBucket();
			}
			else{
				`rm -rf '$rmCmd'`;
				Helpers::retreat(ucfirst($responseData[0]->{'MSG'}));
			}
		}
		Helpers::display(['verification_of_encryption_key_is_sucessfull',"\n"],1);
	}
	
	verifyExistingBackupLocation();
	
	Helpers::copy(Helpers::getIDPVTFile(), Helpers::getIDPVTSCHFile());
	Helpers::changeMode(Helpers::getIDPVTSCHFile());
	if ($isAccountConfigured) {
		Helpers::display(['your_account_details_are', ":\n"]);
		Helpers::display([
			"backup_location", '       : ',
			(index(Helpers::getUserConfiguration('BACKUPLOCATION'), '#') != -1 )? (split('#', (Helpers::getUserConfiguration('BACKUPLOCATION'))))[1] :  Helpers::getUserConfiguration('BACKUPLOCATION'),"\n", 
			'c_restore_location', '      : ',	Helpers::getUserConfiguration('RESTORELOCATION'),"\n", 
			'c_restore_from', '          : ',
			(index(Helpers::getUserConfiguration('RESTOREFROM'), '#') != -1 )? (split('#', (Helpers::getUserConfiguration('RESTOREFROM'))))[1] :  Helpers::getUserConfiguration('RESTOREFROM'),
			"\n", 
			'c_email_address', '         : ', editEmailsToDisplay(),"\n",
			'c_bandwidth_throttle_%', ' : ',	Helpers::getUserConfiguration('BWTHROTTLE'),"\n", 
			'c_retain_logs', '           : ',	Helpers::getUserConfiguration('RETAINLOGS'),"\n", 
			(Helpers::getUserConfiguration('DEDUP') eq 'off')?('c_backup_type', '           : ',	Helpers::getUserConfiguration('BACKUPTYPE'),"\n"):"", 
			'c_proxy_details', '           : ',	editProxyToDisplay(),"\n", 
			'c_service_dir', '           : ',	Helpers::getServicePath(),
		]);

		#display user configurations and edit/reset options.
		tie(my %optionsInfo, 'Tie::IxHash',
			're_configure_your_account_freshly' => sub {	$isAccountConfigured = 0;	},
			'edit_your_account_details' => \&editAccount,
			'exit' => sub {	exit 0;	},
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
		Helpers::setBackupToLocation()		or Helpers::retreat('failed');
		Helpers::setRestoreLocation()		or Helpers::retreat('failed');
		Helpers::setRestoreFromLocation()	or Helpers::retreat('failed');
		setEmailIDs()           			or Helpers::retreat('failed');
		setRetainLogs()						or Helpers::retreat('failed');
		setBackupType()						or Helpers::retreat('failed');
		installUserFiles()					or Helpers::retreat('failed');
	}
	
	Helpers::saveUserConfiguration() or Helpers::retreat('failed');
	Helpers::checkAndUpdateClientRecord($uname,$upasswd);
	
	Helpers::display(["\n", "\"$uname\""." is configured successfully. "],0);
	
	if($loggedInUser eq $uname){
		Helpers::display(["\n","User ", "\"$uname\"", " is already logged in." ],1);
	}
	else {
		Helpers::display(['do_u_want_to_login_as',"$uname",' (y/n)?'],1);
		my $loginConfirmation = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	
		cleanUp() if(lc($loginConfirmation) eq 'n');
		
		if($loggedInUser ne "") {
			Helpers::display(["\"",$loggedInUser, "\"", 'is_already_logged_in_wanna_logout'],1);
			
			my $userChoice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		
			cleanUp()	if(lc($userChoice) eq 'n') ;
			
			chomp (my $logoutStatus = `perl ./Logout.pl`);
			Helpers::display("$logoutStatus");
			cleanUp() if ($logoutStatus !~ /logged out successfully/) ;
		}
		Helpers::createCache($uname) or Helpers::retreat('unable_to_login_please_try_login_script');
		Helpers::display(["\n", "\"$uname\"", " is logged in successfully."],1);
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
		my $isDedup  	   = Helpers::getUserConfiguration('DEDUP');
		my $backupLocation = Helpers::getUserConfiguration('BACKUPLOCATION');
		my  $bucketName = ""; 
		my  $deviceID = "";
		my $jobRunningDir = Helpers::getUserProfilePath();
		if($isDedup eq "on") {
			$deviceID 		= (split("#",$backupLocation))[0];
			$bucketName = (split("#",$backupLocation))[1];
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
		if($isDedup eq 'off'){
			Helpers::createUTF8File(['ITEMSTATUS',$itemStatusUTFpath], $tempBackupsetFilePath, $evsErrorFile) or Helpers::retreat('failed_to_create_utf8_file');	
		} else {
			Helpers::createUTF8File(['ITEMSTATUSDEDUP',$itemStatusUTFpath], $deviceID, $tempBackupsetFilePath, $evsErrorFile) or Helpers::retreat('failed_to_create_utf8_file');	
		}
		my @responseData = Helpers::runEVS('item');
		#print Dumper(\@responseData);
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
	$emailAddresses 	= "no_emails_configured" if($emailAddresses eq "");
	
	return $emailAddresses;
}

#*****************************************************************************************************
# Subroutine			: validateZipPath
# Objective				: This subroutine will check the user provided zip file whether it is suitable to the machine or not.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub validateZipPath {
	Helpers::retreat(["\n", 'absolute_path_required', "\n"]) if($ARGV[0] =~ m/\.\./);
	Helpers::retreat(["\n", 'file_not_found', " ",  $ARGV[0], "\n"]) if(!-e $ARGV[0]);
	
	my $machineName = Helpers::getMachineHardwareName();
	if ($ARGV[0] !~ /$machineName/) {
		my $evsWebPath = "https://www.idrivedownloads.com/downloads/linux/download-options/IDrive_Linux_" . $machineName . ".zip";
		Helpers::retreat(["\n", 'invalid_zip_file', "\n", $evsWebPath, "\n"]);
	}
}

#*****************************************************************************************************
# Subroutine			: getEVSBinaryFromZip
# Objective				: This subroutine will check and get the suitable binary from the provides zip file.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getEVSBinaryFromZip {
	my $machineName = Helpers::getMachineHardwareName();
	my $zipFilePath = getZipPath($ARGV[0]);
	Helpers::unzip($zipFilePath, Helpers::getServicePath());
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
#****************************************************************************************************/
sub createBucket {
	my $deviceName = Helpers::getAndValidate(['enter_your_backup_location_optional', ": "], "backup_location", 1);
	if($deviceName eq '') {
		$deviceName = $Configuration::hostname;
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
			($Configuration::deviceIDPrefix . $result[0]{'device_id'} . $Configuration::deviceIDPostfix .
				"#" . $result[0]{'nick_name'}));
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateBackupLoction
# Objective				: This is to validate and return bucket name
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateBackupLoction {
	my ($bucketName, $choiceRetry) = ('', 0);
	Helpers::display(["\n",'enter_your_backup_location_optional', ': '], 0);
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
			Helpers::display(['enter_your_backup_location_optional', ': '], 0);
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
	my $emailAddresses = Helpers::getAndValidate(["\n", 'enter_your_email_id', ': '], "single_email_address", 1);
	
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
#****************************************************************************************************/
sub setRetainLogs {
	my $ifRetainLogs = "NO";
	Helpers::display(["\n",'do_u_want_to_retain_logs', "\n"], 0);
		
	my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	if($answer eq "y" or $answer eq "Y") {
		Helpers::display(['your_retain_logs_is_enabled',"\n"], 1);
		$ifRetainLogs = "YES";
	} else {
		Helpers::display(['your_retain_logs_is_disabled',"\n"], 1);
		$ifRetainLogs = "NO";
	}
	Helpers::setUserConfiguration('RETAINLOGS', $ifRetainLogs);
	
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
	if($backuptype == 1){
		Helpers::setUserConfiguration('BACKUPTYPE', 'mirror');
		return 1;
	}
	Helpers::setUserConfiguration('BACKUPTYPE', 'relative');
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
#****************************************************************************************************/
sub displayBackupTypeOP {
	Helpers::display(["select_op_for_backup_type"]);
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
		Helpers::display(["\n","Your proxy details are \"",$proxyDetails, "\" . ", 'do_you_want_edit_this_y_or_n_?'], 1);
	}

	my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		Helpers::askProxyDetails("update");
		Helpers::saveUserConfiguration() or Helpers::retreat('failed');
		return 1;
	}
	#Helpers::display('proxy_details_updated_successfully', 0);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: updateServiceDir
# Objective				: This subroutineis is used to update service path for scripts
# Added By				: Anil Kumar
#****************************************************************************************************/
sub updateServiceDir {
	my $oldServicedir = Helpers::getServicePath();
	Helpers::display(["\n","Your service directory is \"",$oldServicedir, "\" . ", 'do_you_want_edit_this_y_or_n_?'], 1);
	my $answer = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		my $servicePathSelection = Helpers::getAndValidate(['enter_your_new_service_path'], "service_dir", 1);
		my $checkPath  = substr $servicePathSelection, -1;
		$servicePathSelection = $servicePathSelection ."/" if($checkPath ne '/');
				
		my $moveResult = `mv '$oldServicedir' '$servicePathSelection' 2>/dev/null`;		
		#added by anil on 31may2018
		if ($moveResult eq '')
		{
			Helpers::saveServicePath($servicePathSelection."idrive") or Helpers::retreat(['failed_to_create_directory',": $servicePathSelection"]);
			my $restoreLocation = Helpers::getUserConfiguration('RESTORELOCATION');
			$servicePathSelection = $servicePathSelection."idrive";
			$restoreLocation =~ s/$oldServicedir/$servicePathSelection/; 
		
			my $oldPathForCron = $oldServicedir."/".$Configuration::userProfilePath;
			my $newPathForCron = $servicePathSelection."/".$Configuration::userProfilePath;
			#modified by anil on 01may2018
			my $updateCronEntry = `sed 's/'$oldPathForCron'/'$newPathForCron'/g' '/etc/crontabTest' 1>/dev/null 2>/dev/null `;
		
			Helpers::setUserConfiguration('RESTORELOCATION', $restoreLocation);
			Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
			Helpers::display(['service_dir_updated_successfully', "\"", $servicePathSelection, "\"."]);
			Helpers::saveUserConfiguration() or Helpers::retreat('failed');
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
# Modified By           : Senthil Pandian
#****************************************************************************************************/		
sub installUserFiles {
	tie(my %filesToInstall, 'Tie::IxHash',
		%Configuration::availableJobsSchema,
		%Configuration::excludeFilesSchema
	);

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
			Helpers::display(["\n","setting_up_your_default_$_\_file_as",
					" ",(fileparse($file))[0],".\nLocation: $file"]);
			close($fh);
			chmod 0777, $file;
		}
		else {
			Helpers::display(["\n",'unable_to_create_file', " \"$file\"" ]);
			return 0;
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: editAccount
# Objective				: This subroutineis is used to edit logged in user account
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar
#****************************************************************************************************/
sub editAccount {
	Helpers::display(["\n",'select_the_item_you_want_to_edit', ":","\n"]);
	
	tie(my %optionsInfo, 'Tie::IxHash',
		'backup_location_lc' => \&editBackupToLocation,
		'restore_location' => sub {	Helpers::editRestoreLocation();	},
		'restore_from_location' => sub { Helpers::editRestoreFromLocation();	},
		'title_email_address' => sub { updateEmailIDs(); },
		'bandwidth_throttle' => \&setBandwidthThrottle,
		'retain_logs' => \&setRetainLogs,
		'backup_type' => \&getAndSetBackupType,
		'edit_proxy' => \&updateProxyOP,
		'edit_service_path' => \&updateServiceDir,
		'exit' => \&updateAndExitFromEditMode,
	);
	if(Helpers::getUserConfiguration('DEDUP') eq 'on'){
		delete $optionsInfo{'backup_type'}	;
	}
	my @options = keys %optionsInfo;
	Helpers::displayMenu('enter_your_choice', @options);
	my $editItem = Helpers::getUserChoice();
	if (Helpers::validateMenuChoice($editItem, 1, scalar(@options))) {
		$optionsInfo{$options[$editItem - 1]}->() or Helpers::retreat('failed');
	}
	else{
		Helpers::display(['invalid_choice', ' ', 'please_try_again', '.']);
	}
	return editAccount();
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
		
	}elsif (Helpers::getUserConfiguration('DEDUP') eq 'on') {
		my @devices = Helpers::fetchAllDevices();
		Helpers::findMyDevice(\@devices,"editMode") or Helpers::displayOptions(\@devices) or Helpers::retreat('failed');
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
		Helpers::display(["\n",'configured_email_address_is', ' ', $emailList, '. ', 'do_you_want_edit_this_y_or_n_?'], 1);
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
	Helpers::saveUserConfiguration() or Helpers::retreat('failed');
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