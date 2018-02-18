package Helpers;
use strict;
use warnings;
use Cwd 'abs_path';
use File::Spec::Functions;
use File::Basename;
use Scalar::Util qw(reftype looks_like_number);
use File::Path qw(rmtree);
use File::Copy;

#use Data::Dumper;

use Configuration;

my $sourceCodesPath;
my $servicePath;
my $username;
my $evsBinary;
my $storageUsed;
my $totalStorage;
my $utf8File;
my $serverAddress;
my $machineHardwareName;
my $muid;

tie(my %userConfiguration, 'Tie::IxHash');

#-------------------------------------------------------------------------------
# Most commonly used subroutines
#
# Created By : Yogesh Kumar
# Reviewed By: Deepak Chaurasia
#-------------------------------------------------------------------------------

use Strings;

#*******************************************************************************
# Prints formated data to stdout
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub display {
	my $message        = shift;
	my $endWithNewline = 1;
	$endWithNewline    = shift if (scalar(@_) > 0);

	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}

	for my $i (0 .. $#{$message}) {
		if (exists $Locale::strings{$message->[$i]}) {
			print $Locale::strings{$message->[$i]};
		}
		else {
			print $message->[$i];
		}
	}

	print "\n" if ($endWithNewline);
}

#*******************************************************************************
# Display header block
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub displayHeader {
	return 1 if ($Configuration::callerEnv eq 'SCHEDULER');

	if ($Configuration::displayHeader) {
		$Configuration::displayHeader = 0;
		my $w = (split(' ', $Configuration::screenSize))[-1];
		my $adjst = 0;
		my $header = qq(=) x $w;
		my $h = "Version: $Configuration::version";
		my $l = length($h);
		$header    .= qq(\n$h);
		$header    .= (qq( ) x (20 - ($l -$adjst)) . qq($Locale::strings{'developed_by'} ));
		$header    .= qq($Locale::strings{lc($Configuration::appType . '_maintainer')}\n);
		$header    .= (qq(-) x $l . qq( ) x (20 - ($l -$adjst)) . qq(-) x ($w - ($l+ (20 - ($l -$adjst)))));
		$h = qq($Locale::strings{'logged_in_user'});
		$header    .= qq(\n$h);
		$header    .= ((qq( ) x (20 - ($l -$adjst) + ($l - length($h)))) . ($username ? $username: $Locale::strings{'no_logged_in_user'}) . qq(\n));
		$header    .= (qq(-) x $l . qq( ) x (20 - ($l -$adjst)) . qq(-) x ($w - ($l+ (20 - ($l -$adjst)))));
		$header    .= qq(\n);
		if ($username and (loadStorageSize() or reCalculateStorageSize())) {
			$h = qq($Locale::strings{'storage_used'});
			$header    .= qq($h);
			$header    .= ((qq( ) x (20 - ($l -$adjst) + ($l - length($h)))) . qq($storageUsed of $totalStorage) . qq(\n));
		}
		$header    .= qq(-) x $w;
		$header    .= qq(\n);
		if (isUpdateAvailable()) {
			$h = qq($Locale::strings{'new_update_is_available'});
			$header    .= qq($h\n);
		}
		$header    .= qq(=) x $w;
		display($header);
		return 1;
	}
	return 0;
}

#*******************************************************************************
# Create a directory
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub createDir {
	my @parentDir = fileparse($_[0]);
	my $recursive = 0;
	if (defined($_[1])) {
		$recursive = $_[1];
	}
	unless (-d $parentDir[1]) {
		if ($recursive) {
			return 0 unless (createDir($parentDir[1], $recursive));
		}
		else {
			display(["$parentDir[1]: ", 'no_such_directory_try_again']);
			return 0;
		}
	}
	unless (-w $parentDir[1]) {
		display(['cannot_open_directory', " $parentDir[1]", 'permission_denied']);
		return 0;
	}

	if (mkdir($_[0], 0770)) {
		return 1;
	}
	return 1 if ($! eq 'File exists');

	display(["$_[0]: ", $!]);

	return 0;
}

#*******************************************************************************
# Find whether package dependencies are met
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub findDependencies {
	display('');
	display('checking_for_dependencies');
	my $status = 0;
	for my $binary (@Configuration::dependencyBinaries) {
		display("dependency_$binary...", 0);
		my $r = `which $binary`;
		if ($? == 0) {
			display('found');
			$status = 1;
		}
		else {
			display('not_found');
			$status = 0;
			last;
		}
	}
	display('');
	return $status;
}

#*******************************************************************************
# Ask user for an action
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub displayMenu {
	if ($Configuration::callerEnv eq 'SCHEDULER') {
		# TODO: log this exception for debugging purpose.
		# This function must not be used in SCHEDULER environment
		retreat('');
	}

	my $c = 1;
	my ($message, @options) = @_;
	print map{$c++ . ") ", $Locale::strings{$_} . "\n"} @options;
	print $Locale::strings{$message} if exists $Locale::strings{$message};
}

#*******************************************************************************
# Validate user selected value from the menu.
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub isValidSelection {
	my ($userSelection, $numberOfItems) = @_;
	if (looks_like_number($userSelection) && ($userSelection >= 1) && ($userSelection <= $numberOfItems) ) {
		return 1;
	}
	return 0;
}

#*******************************************************************************
# Check if the file is locked
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub isFileLocked {
		 my ($f) = @_;
		 open(my $fh, ">>", $f) or return 1;
		 flock($fh, 2|4) or return 1;
		 close($fh);
		 return 0;
}

#*******************************************************************************
# Raise an exception and exit immediately
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub retreat {
	my $message = shift;
	my $msg;
	my ($package, $filename, $line) = caller;

	displayHeader();

	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}

	for my $i (0 .. $#{$message}) {
		if (exists $Locale::strings{$message->[$i]}) {
			$msg .= $Locale::strings{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}

	if ($servicePath) {
		rmtree("$servicePath/$Configuration::downloadsPath");
		rmtree("$servicePath/$Configuration::tmpPath");
	}
	die "$msg\n";
}

#*******************************************************************************
# Make a server request
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub request {
	# TODO:IMPORTANT to use proxy if set
	print "curl --fail -sk -L --max-time 15 -d '$_[1]' '$_[0]'";
	my $response = `curl --fail -sk -L --max-time 15 -d '$_[1]' '$_[0]'`;
	# TODO:IMPORTANT proxy error logs if proxy is set
	if ($? > 0) {
		# TODO:DEBUG
		# TODO:IMPORTANT to check if proxy is set and failed because of proxy then
		# ask for proxy settings. May be
		# we need to ask when failed to connect to internet
		#if ($Configuration::callerEnv eq 'SCHEDULER') {
			# TODO:IMPORTANT we shouldn't ask proxy in this case
		#}
		return 0
	}

	return $response;
}

#*******************************************************************************
# Download files from the given url
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub download {
	my $url           = shift;
	my $downloadsPath = shift;
	unless (defined($url)) {
		display('url_cannot_be_empty');
		return 0;
	}

	unless (defined($downloadsPath)) {
		$downloadsPath = "$servicePath/$Configuration::downloadsPath";
		createDir($downloadsPath);
	}

	unless (-d $downloadsPath) {
		display(["$downloadsPath ", 'does_not_exists']);
		return 0;
	}

	if (reftype(\$url) eq 'SCALAR') {
		$url = [$url];
	}

	my $response;
	for my $i (0 .. $#{$url}) {
		# TODO:IMPORTANT to use proxy if set
		my @parse = split('/', $url->[$i]);
		print "curl --fail -sk -L $url->[$i] -o $downloadsPath/$parse[-1]\n";
		$response = `curl --fail -sk -L $url->[$i] -o $downloadsPath/$parse[-1]`;
		if ($? > 0) {
			# TODO:DEBUG
			return 0
		}
	}

	return 1;
}

#*******************************************************************************
# Read zip files
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub unzip {
	my $filename = shift;
	my $exDir    = shift;

	unless (defined($filename)) {
		display('ziped_filename_cannot_be_empty');
		return 0;
	}

	unless (defined($exDir)) {
		$exDir = "$servicePath/$Configuration::downloadsPath";
		createDir($exDir) or (display(["$exDir ", 'does_not_exists']) and return 0);
	}

	print "unzip -o $filename -d $exDir\n";
	my $output = `unzip -o $filename -d $exDir`;
	if ($? > 0) {
			# TODO:DEBUG
			return 0
	}

	return 1;
}

#*******************************************************************************
# Validate user provided values
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub validateUserConfigurations {
	for my $key (keys %Configuration::userConfigurationSchema) {
		if ($Configuration::userConfigurationSchema{$key}{'required'} and
			($userConfiguration{$key} eq '')) {
			displayHeader();
			display("user_config_" . lc($key)  . "_not_found");
			return 0;
		}
		if (($Configuration::userConfigurationSchema{$key}{'type'} eq 'dir') and
			($userConfiguration{$key} ne '') and (!-d $userConfiguration{$key})) {
			displayHeader();
			display("user_config_" . lc($key)  . "_not_found");
			return 0;
		}
		if (($Configuration::userConfigurationSchema{$key}{'default'} ne '') and
			($userConfiguration{$key} eq '')) {
			$userConfiguration{$key} = $Configuration::userConfigurationSchema{$key}{'default'};
		}
	}
	return 1;
}

#*******************************************************************************
# Return $machineHardwareName
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getMachineHardwareName {
	return $machineHardwareName;
}

#*******************************************************************************
# Find the mac address
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getMachineUID {
	return $muid if ($muid);

	my $cmd;
	if (-f '/sbin/ifconfig') {
		$cmd = '/sbin/ifconfig -a';
	}
	elsif (-f '/sbin/ip') {
		$cmd = '/sbin/ip addr';
	}
	else {
		retreat('unable_to_find_mac_address');
	}

	my $result = `$cmd`;
	my @macAddr = $result =~ /HWaddr [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		$macAddr[0] =~ s/HWaddr |:|-//g;
		return ($muid = ('Linux' . $macAddr[0]));
	}

	@macAddr = $result =~ /ether [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		$macAddr[0] =~ s/ether |:|-//g;
		return ($muid = ('Linux' . $macAddr[0]));
	}

	return 0;
}

#*******************************************************************************
# Get the absolute path of a file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getAbsPath {
	return abs_path(shift);
}

#*******************************************************************************
# Get the HOME directory from the environmental variable
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getUserHomePath {
	return $ENV{'HOME'};
}

#*******************************************************************************
# Get concatenating several directory and file names into a single path
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getCatfile {
	return catfile(@_);
}

#*******************************************************************************
# Asks user for an action
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getUserChoice {
	my $echoBack = shift;
	$echoBack = 1 unless(defined($echoBack));

	system('stty', '-echo') unless ($echoBack);
	chomp(my $input = <STDIN>);
	unless ($echoBack) {
		system('stty', 'echo');
		display('');
	}
	return $input;
}

#*******************************************************************************
# Build path to cached file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getCachedFile {
	return ("$servicePath/$Configuration::cachedFile");
}

#*******************************************************************************
# Build path to service location file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getServicePath {
	return $servicePath;
}

#*******************************************************************************
# Build path to user profile info
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getUserProfilePath {
	if (defined($_[0])) {
		unless (exists $Configuration::userProfilePaths{$_[0]}) {
			retreat(["$_[0]: ", 'does_not_exists']);
		}
		return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::userProfilePaths{$_[0]}");
	}
	else {
		return ("$servicePath/$Configuration::userProfilePath/$username");
	}
}

#*******************************************************************************
# Build path to IDPWD file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getIDPWDFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idpwdFile");
}

#*******************************************************************************
# Build path to IDENPWD file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getIDENPWDFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idenpwdFile");
}

#*******************************************************************************
# Build path to IDPVT file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getIDPVTFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idpvtFile");
}

#*******************************************************************************
# Build path to IDPWDSCH file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getIDPWDSCHFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idpwdschFile");
}

#*******************************************************************************
# Build path to user configuration file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getUserConfigurationFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::userConfigurationFile");
}

#*******************************************************************************
# Build path to serverAddress file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getServerAddressFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::serverAddressFile");
}

#*******************************************************************************
# Build path to user EVS binary file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getEVSBinaryFile {
	return ("$servicePath/$Configuration::evsBinaryName") if ($userConfiguration{'DEDUP'} eq 'off');

	return ("$servicePath/$Configuration::evsDedupBinaryName");
}

#*******************************************************************************
# Build path to user quota.txt  file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getCachedStorageFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::quotaFile");
}

#*******************************************************************************
# Build path to user .updateVersionInfo  file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getUpdateVersionInfoFile {
	return ("$sourceCodesPath/$Configuration::updateVersionInfo");
}

#*******************************************************************************
# Return file size in human readable format
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getHumanReadableSizes {
	my ($sizeInBytes) = @_;
	if ($sizeInBytes > 1099511627776) {       #TiB: 1024 GiB
		return sprintf("%.2f TB", $sizeInBytes / 1099511627776);
	}
	elsif ($sizeInBytes > 1073741824) {       #GiB: 1024 GiB
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

#*******************************************************************************
# Get username from $username
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getUsername {
	return $username;
}

#*******************************************************************************
# Get server address from $serverAddress
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getServerAddress {
	unless ($serverAddress) {
		(saveServerAddress(fetchServerAddress()) and loadServerAddress()) or
			retreat('failed');
	}
	return $serverAddress;
}

#*******************************************************************************
# Get user configured values
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getUserConfiguration {
	unless(exists $userConfiguration{$_[0]}) {
		display(["WARNING: $_[0] ", 'is_not_set_in_user_configuration']);
		return 0;
	}
	return $userConfiguration{$_[0]};
}

#*******************************************************************************
# Assign username
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub setUsername {
	$username = $_[0];
	return 1;
}

#*******************************************************************************
# Save total storage space of the current logged in user to $totalStorage
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub setTotalStorage {
	$totalStorage = getHumanReadableSizes($_[0]);
	return 1;
}

#*******************************************************************************
# Save storage used space of the current logged in user to $storageUsed
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub setStorageUsed {
	$storageUsed = getHumanReadableSizes($_[0]);
	return 1;
}

#*******************************************************************************
# Set user configuration values
#
# Added By: Yogesh Kumar
#*******************************************************************************
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
			unless (exists $Configuration::userConfigurationSchema{$key}) {
				unless (%cgiNames or %evsNames) {
					for my $rhs (keys %Configuration::userConfigurationSchema) {
						if ($Configuration::userConfigurationSchema{$rhs}{'cgi_name'} ne '') {
							$cgiNames{$Configuration::userConfigurationSchema{$rhs}{'cgi_name'}} = $rhs;
						}
						if ($Configuration::userConfigurationSchema{$rhs}{'evs_name'} ne '') {
							$evsNames{$Configuration::userConfigurationSchema{$rhs}{'evs_name'}} = $rhs;
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
					display(['user_configuration', "_$key\_", 'does_not_exists']);
					next;
				}
			}
			$isNothingFound = 0;
			$userConfiguration{$keystring} = $data->[$i]{$key};
		}
	}
	unless ($isNothingFound){
		$Configuration::isUserConfigModified = 1;
		return 1;
	}

	return 0;
}

#*******************************************************************************
# Save user server address
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub saveServerAddress {
	# TODO:CHANGE save server address in user configuration file itself
	my @data = @_;
	if (exists $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}} or
			exists $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'evs_name'}}) {
		my $gsa = getServerAddressFile();
		if (open(my $fh, '>', $gsa)) {
			if (exists $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}}) {
				print $fh $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}};
			}
			else {
				print $fh $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'evs_name'}};
			}
			close($fh);
			return 1;
		}
	}

	return 0;
}

#*******************************************************************************
# Save user quota to quota file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub saveUserQuota {
	my $csf = getCachedStorageFile();
	my @data = @_;
	if (open(my $fh, '>', $csf)) {
		my $first = 1;
		for my $key (keys %Configuration::accountStorageSchema) {
			# To read response from EVS.
			if (exists $data[0]->{lc($key)}) {
					if (!$first) {
						print $fh "\n";
					}
					else {
						$first = 0;
					}
					print $fh "$key=";
					print $fh $data[0]->{lc($key)};
			}
			# To read response from CGI.
			elsif (exists
				$data[0]->{$Configuration::accountStorageSchema{$key}{'cgi_name'}}) {
					if (!$first) {
						print $fh "\n";
					}
					else {
						$first = 0;
					}
					print $fh "$key=";
					print $fh $data[0]->{$Configuration::accountStorageSchema{$key}{'cgi_name'}};
			}
			elsif (exists
				$data[0]->{$Configuration::accountStorageSchema{$key}{'evs_name'}}) {
					if (!$first) {
						print $fh "\n";
					}
					else {
						$first = 0;
					}
					print $fh "$key=";
					print $fh $data[0]->{$Configuration::accountStorageSchema{$key}{'evs_name'}};
			}
		}
		close($fh);
		return 1;
	}
	return 0;
}

#*******************************************************************************
# Save user selected service path in the file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub saveServicePath {
	my $servicePathFile = ("$sourceCodesPath/" . $Configuration::serviceLocationFile);
	if (open(my $spf, '>', $servicePathFile)) {
		print $spf $_[0];
		close($spf);
		return 1;
	}
	return 0
}

#*******************************************************************************
# Save user selected configurations to a file
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub saveUserConfiguration {
	return 1 unless ($Configuration::isUserConfigModified);

	my $ucf = getUserConfigurationFile();
	return 0 unless (validateUserConfigurations());
	if (open(my $fh, '>', $ucf)) {
		for my $key (keys %Configuration::userConfigurationSchema) {
			print $fh "$key = ";
			print $fh $userConfiguration{$key};
			print $fh "\n";
		}
		close($fh);
		return 1;
	}
	return 0;
}

#*******************************************************************************
# Encode user passwd
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub encodePWD {
	createUTF8File($Configuration::evsAPIPatterns{'STRINGENCODE'},
		$_[0], getIDPWDFile()) or
		retreat('failed_to_create_utf8_file');
	runEVS('Encoded');

	# TODO:CLEANUP
	copy(getIDPWDFile(), getIDPWDSCHFile());
	chmod(0600, getIDPWDSCHFile());

	return 1;
}

#*******************************************************************************
# Encrypt user passwd
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub encryptPWD {
	my $epf = getIDENPWDFile();
	my $len = length($username);
	my $ep = pack("u", $_[0]);
	chomp($ep);
	$ep = ($len . "_" . $ep);
	if (open(my $fh, '>', $epf)) {
		print $fh $ep;
		close($fh);
		return 1;
	}

	return 0;
}

#*******************************************************************************
# Request IDrive server to re-calculate storage size
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub reCalculateStorageSize {
	my $csf = getCachedStorageFile();
	unlink($csf);
	createUTF8File($Configuration::evsAPIPatterns{'GETQUOTA'}) or
		retreat('failed_to_create_utf8_file');
	my @result = runEVS('tree');
	if (exists $result[0]->{'message'}) {
		if ($result[0]->{'message'} eq 'ERROR') {
			display('unable_to_retrieve_the_quota');
			return 0;
		}
	}
	if (saveUserQuota(@result)) {
		return 1 if loadStorageSize();
	}
	display('unable_to_cache_the_quota');
	return 0;
}

#*******************************************************************************
# Check if latest version is available on the server
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub isUpdateAvailable {
	my $u = getUpdateVersionInfoFile();
	if (-f $u and !-z $u) {
		return 1;
	}
	else {
		#TODO: request to check if update is available
	}
	return 0;
}

#*******************************************************************************
# Find a file in source codes path
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub inSourceCodesPath {
	my ($file) = @_;
	if (-e ("$sourceCodesPath/$file")) { 
		return 1;
	}

	return 0;
}

#*******************************************************************************
# Authenticate user credentials
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub authenticateUser {
	my $authCGI;
	my $uname = $_[0];
	if ($Configuration::appType eq 'IBackup') {
		$authCGI = $Configuration::IBackupAuthCGI;
	}
	else {
		$authCGI = $Configuration::IDriveAuthCGI;
	}

	foreach ($uname, $_[1]) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}

	my @responseData;
	my $res = request($authCGI, ('username='.$uname.'&password='.$_[1]));
	unless ($res) {
		my $tmpPath = "$servicePath/$Configuration::tmpPath";
		createDir($tmpPath);

		createUTF8File($Configuration::evsAPIPatterns{'STRINGENCODE'},
										$_[1], ("$tmpPath/$_[0]\.tmp")) or
			retreat('failed_to_create_utf8_file');
		my @result = runEVS();

		if (($result[0]->{'STATUS'} eq 'FAILURE') and
				($result[0]->{'MSG'} eq 'no_stdout')) {
				createUTF8File($Configuration::evsAPIPatterns{'VALIDATE'},
										$_[0], ("$tmpPath/$_[0]\.tmp")) or
					retreat('failed_to_create_utf8_file');
			@responseData = runEVS('tree');
		}
		else {
			retreat('authentication_failed');
		}

		rmtree("$servicePath/$Configuration::tmpPath");
	}
	else {
		@responseData = parseEVSCmdOutput($res, 'login', 1);
	}

	if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
		if (exists $responseData[0]->{'desc'}) {
			#display(lc($responseData[0]->{'desc'} =~ s/ /_/gr));
			my $desc = $responseData[0]->{'desc'};
			display(lc($desc =~ s/ /_/g));
		}
		else {
			display($responseData[0]->{'MSG'});
		}
		return 0;
	}
	elsif ($responseData[0]->{'STATUS'} eq 'SUCCESS') {
		if ((exists $responseData[0]->{'plan_type'}) and
			($responseData[0]->{'plan_type'} eq 'Mobile-Only')) {
			display('mobile_only');
			return 0;
		}

		setUserConfiguration('USERNAME', $_[0]);
		createUserDir();

		saveUserQuota(@responseData);
		saveServerAddress(@responseData);
		setUserConfiguration(@responseData);
		return 1;
	}

	return 0;
}

#*******************************************************************************
# Check if PWD file exists
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub isLoggedin {
	my @pf = ($Configuration::idpwdFile, $Configuration::idenpwdFile,
		$Configuration::idpwdschFile);

#	if ($userConfiguration{'ENCRYPTIONTYPE'} eq 'PRIVATE') {
#		push @pf, ($Configuration::idpvtFile, $Configuration::idpvtschFile);
#	}

	my $status = 0;
	for (@pf) {
		my $file = ("$servicePath/$Configuration::userProfilePath/$username/$_");
		if (!-f $file or -z $file) {
			$status = 0;
			last;
		}
		$status = 1;
	}
	return $status;
}

#*******************************************************************************
# Create user profile directories
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub createUserDir {
	display(['creating_user_directories', '... '], 0);
	my $err = ();
	for my $path (keys %Configuration::userProfilePaths) {
		my $userPath = getUserProfilePath($path);
		`mkdir -p $userPath`;
		chmod 0770, $userPath;
		if(!-e $userPath){
			display("Unable to create $userPath");
			return 0;
		}
	}
	display('done');
	return 1;
}

#*******************************************************************************
# Execute evs binary and check it's working or not
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub hasEVSBinary {
	my $dir = shift;
	my @evsBinaries = (
		$Configuration::evsBinaryName,
		$Configuration::evsDedupBinaryName
	);
	my $duplicate = 1;

	unless(defined($dir)) {
		$dir = getServicePath();
		$duplicate = 0;
	}

	my $output;
	for (@evsBinaries) {
		print "$dir/$_\n";
		unless (-f "$dir/$_") {
			display(['unable_to_find', ": $dir/$_"]);
			return 0
		}

		chmod(0755, "$dir/$_");
		unless(-x "$dir/$_") {
			retreat(["$dir/$_: ", 'does_not_have_execute_permission'])
		}

		$output = `$dir/$_ -h`;
		if ($? > 0) {
			#TODO:DEBUG
			return 0;
		}
		if ($duplicate) {
			copy("$dir/$_", getServicePath());
		}
	}

	return 1;
}

#*******************************************************************************
# Download system compatible evs binary
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub downloadEVSBinary {
	my $status = 0;
	# We always try with universal binaries if nothing works
	my $ezf    = [@{$Configuration::evsZipFiles{$machineHardwareName}},
								@{$Configuration::evsZipFiles{'x'}}];
	my $downloadPage = $Configuration::evsDownloadsPage;
	my $domain       = lc($Configuration::appType);

	$domain .= 'downloads' if($Configuration::appType eq 'IDrive');

	$downloadPage =~ s/__APPTYPE__/$domain/g;

	my $dp;
	for my $i (0 .. $#{$ezf}) {
		$ezf->[$i] =~ s/__APPTYPE__/$Configuration::appType/g;
		$dp = ($downloadPage . "/$ezf->[$i]");
		#unless(download($dp =~ s/__EVSTYPE__/-dedup/gr)) {
		my $desc = $dp;
		unless(download($desc =~ s/__EVSTYPE__/-dedup/g)) {
			$status = 0;
			last;
		}

		unless (unzip("$servicePath/$Configuration::downloadsPath/$ezf->[$i]")) {
			$status = 0;
			last;
		}
		#if (hasEVSBinary(getServicePath() . "/$Configuration::downloadsPath/" . $ezf->[$i] =~ s/.zip//gr)) {
		$desc = $ezf->[$i];
		if (hasEVSBinary(getServicePath() . "/$Configuration::downloadsPath/" . $desc =~ s/.zip//g)) {
			$status = 1;
			last;
		}

		last unless ($status);
	}
	rmtree("$servicePath/$Configuration::downloadsPath");
	return $status;
}

#*******************************************************************************
# Save machine hardware name to $machineHardwareName
# This is used to download arch depedent binaries
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadMachineHardwareName {
	my $mhn = `uname -m`;
	if ($? > 0) {
		# TODO:DEBUG log error statements
		return 0;
	}
	chomp($mhn);

	if ($mhn =~ /i386|i686/) {
		$machineHardwareName = '32';
	}
	elsif ($mhn =~ /x86_64|ia64/) {
		$machineHardwareName = '64';
	}
	elsif ($mhn =~ /arm/) {
		$machineHardwareName = 'arm';
	}
	else {
		# TODO:DEBUG log error statements
		return 0;
	}

	return 1;
}

#*******************************************************************************
# Save Server address of the current logged in user to $serverAddress
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadServerAddress {
	my $gsa = getServerAddressFile();
	if (-f $gsa and !-z $gsa) {
		if (open(my $g, '<:encoding(UTF-8)', $gsa)) {
			my $sa = <$g>;
			close($g);
			chomp($sa);
			if ($sa ne '') {
				$serverAddress = $sa;
				return 1;
			}
		}
	}
	return 0;
}

#*******************************************************************************
# Save logged in user's available and used space
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadStorageSize {
	my $csf = getCachedStorageFile();
	my @accountStorageDetails;
	my $status = 0;
	if (-f $csf and !-z $csf) {
		if (open(my $s, '<:encoding(UTF-8)', $csf)) {
			@accountStorageDetails = <$s>;
			for my $keyvaluepair (@accountStorageDetails) {
				my @kvp = split(/=/, $keyvaluepair);
				if (exists $Configuration::accountStorageSchema{$kvp[0]}) {
					my $func = \&{$Configuration::accountStorageSchema{$kvp[0]}{'func'}};
					chomp($kvp[1]);
					&$func($kvp[1]);
					$status = 1;
				}
				else {
					#TODO: remove file and request to get quota.
					$status = 0;
					last;
				}
			}
			close($s);
		}
	}
	return $status;
}

#*******************************************************************************
# Assign perl scripts path to $sourceCodesPath
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadSourceCodesPath {
	my $absFile = getAbsPath(__FILE__);
	my @af = split(/\/Helpers\.pm$/, $absFile);
	$sourceCodesPath = $af[0];
	return 1;
}

#*******************************************************************************
# Assign saved path of user data to $servicePath
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadServicePath {
	if (inSourceCodesPath($Configuration::serviceLocationFile)) {
		if (open(my $sp, '<:encoding(UTF-8)',
				("$sourceCodesPath/" . $Configuration::serviceLocationFile))) {
			my $s = <$sp>;
			close($sp);
			chomp($s);
			if (-d $s) {
				$servicePath = $s;
				return 1;
			}
		}
		# TODO:LOGGING
	}
	displayHeader();
	return 0;
}

#*******************************************************************************
# Assign logged in user name to $username
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadUsername {
	my $cf = getCachedFile();
	if (-f $cf and !-z $cf) {
		if (open(my $u, '<:encoding(UTF-8)', $cf)) {
				$username = <$u>;
				close($u);
				chomp($username);
				return 1
		}
	}
	displayHeader();
	return 0;
}

#*******************************************************************************
# Assign evs binary filename to %evsBinary
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadEVSBinary() {
	my $evs = getEVSBinaryFile();
	retreat('unable_to_find_or_execute_evs_binary') if (!-f $evs or !-X $evs);
	my $o = `$evs -h`;
	retreat('unable_to_execute_evs_binary') if ($? != 0);
	$evsBinary = $evs;
	return 1;
}

#*******************************************************************************
# Assign user configurations to %userConfiguration
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub loadUserConfiguration {
	my $ucf = getUserConfigurationFile();
	my $status = 1;
	map{$userConfiguration{$_} = ''} keys %Configuration::userConfigurationSchema;

	if (-f $ucf and !-z $ucf) {
		if (open(my $uc, '<:encoding(UTF-8)', $ucf)) {
			my @u = <$uc>;
			close($uc);
			map{my @x = split(/ = /, $_); chomp($x[1]); $x[1] =~ s/^\s+|\s+$//g; $userConfiguration{$x[0]} = $x[1];} @u;
			$status = 0 unless (validateUserConfigurations());
		}
	}
	else {
		$status = 0;
	}

	loadEVSBinary() or retreat('unable_to_find_or_execute_evs_binary');

	return $status;
}

#*******************************************************************************
# Ask user to provide proxy details.
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub askProxyDetails {
	# TODO:IMPORTANT to save proxy details
	
	return 1;
}

#*******************************************************************************
# Build valid evs parameters
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub createUTF8File {
	# TODO: to call reload serveraddress if this fails
	loadServerAddress();
	if (-d getUserProfilePath()) {
		$utf8File = (getUserProfilePath() ."/$Configuration::utf8File");
	}
	else {
		$utf8File = "$servicePath/$Configuration::tmpPath/$Configuration::utf8File";
	}
	my $evsPattern = $_[0];
	my $encodeString = 0;
	$encodeString = 1 if ($evsPattern =~ /--string-encode/);
	my @ep = split(/\n/, $evsPattern);
	my $tmpInd;
	for my $pattern (@ep) {
		my @kNames = $pattern =~ /__[A-Za-z0-9]+__/g;
		for(@kNames) {
			if ($_ =~ /__ARG(.*?)__/) {
				$tmpInd = $1;
				retreat('insufficient_arguments') unless (defined($_[$tmpInd]));
				$pattern =~ s/$_/$_[$tmpInd]/g;
				next;
			}

			$_ =~ s/__//g;
			my $func = \&{$_};
			my $v = &$func();
			$pattern =~ s/__$_\_\_/$v/g;
		}
	}

	my $evsParams = join("\n", @ep);
	unless ($encodeString) {
		unless ($evsParams =~ /--password-file/) {
			$evsParams .= "\n--password-file=" . getIDPWDFile();
		}

#		if (getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
#			$evsParams .= "\n--pvt-key=" . getIDPVTFile();
#		}
		$evsParams .= "\n--encode";
		$evsParams .= "\n--proxy=";
	}

	print "$evsParams\n";

	print "$utf8File\n";
	if (open(my $fh, '>', $utf8File)) {
		print $fh $evsParams;
		close($fh);
		return 1;
	}
	
	return 0;
}

#*******************************************************************************
# Parse evs response and return the same
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub parseEVSCmdOutput {
	#print "\n$_[0]\n";
	my @parsedEVSCmdOutput;
	if (defined($_[0]) and defined($_[1])) {
		$_[0] =~ s/""/" "/g;
		my $endTag = '\/>';
		$endTag = "><\/$_[1]>" if (defined($_[2]));
		print "/(<$_[1]) (.+?)($endTag)/sg\n";
		my @x = $_[0] =~ /(<$_[1]) (.+?)($endTag)/sg;
	
		for (1 .. (scalar(@x)/3)) {
			my @keyValuePair = $x[(((3 * $_) - 2))] =~ /(.+?)="(.+?)"/sg;
			my %data;
			for (0 .. ((scalar(@keyValuePair)/2) - 1)) {
				$keyValuePair[($_ * 2)] =~ s/^\s+|\s+$//g;
				#$data{$keyValuePair[($_ * 2)]} = $keyValuePair[(($_ * 2) + 1)] =~ s/^\s$//gr;
				my $desc = $keyValuePair[(($_ * 2) + 1)];				
				$data{$keyValuePair[($_ * 2)]} = $desc =~ s/^\s$//g;
			}
			if (exists $data{'status'}) {
				$data{'STATUS'} = uc($data{'status'});
			}
			elsif (exists $data{'message'} and
							($data{'message'} eq 'FAILURE' or
								$data{'message'} eq 'SUCCESS' or
								$data{'message'} eq 'ERROR')) {
				if ($data{'message'} eq 'ERROR') {
					$data{'STATUS'} = 'FAILURE';
				}
				else {
					$data{'STATUS'} = $data{'message'};
				}
			}
			else {
				$data{'STATUS'} = 'SUCCESS';
			}
			push @parsedEVSCmdOutput, \%data;
		}
	}

	# TODO:IMPORTANT to parse global error output
	unless (@parsedEVSCmdOutput) {
		$_[0] =~ s/connection established\n//g;
		chomp($_[0]);
		push @parsedEVSCmdOutput, {
			'STATUS' => 'FAILURE',
			'MSG'    => $_[0]
		};
	}

	return @parsedEVSCmdOutput;
}

#*******************************************************************************
# Execute evs binary using backtick operator and return parsed output
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub runEVS {
	my $idevcmd = (getEVSBinaryFile() . " --utf8-cmd=$utf8File");
	my $idevscmdout = `$idevcmd 2>&1`;

	my @o;
	if ($? > 0) {
		my $msg = 'execution_failed';
		if (($idevscmdout =~ /\@ERROR: PROTOCOL VERSION MISMATCH on module ibackup/ or
					$idevscmdout =~ /Failed to validate. Try again.\@IDEVSD: OK/) and
				$userConfiguration{'DEDUP'} eq '') {
			setUserConfiguration('DEDUP', 'off');
			return runEVS($_[0]);
		}
		elsif ($idevscmdout =~ /\@ERROR: auth failed/ and
			$idevscmdout =~ /encryption verification failed/) {
			$msg = 'encryption_verification_failed';
		}
		elsif ($idevscmdout =~ /private encryption key must be between 4 and 256 characters in length/) {
			$msg = 'private_encryption_key_must_be_between_4_and_256_characters_in_length';
		}

		push @o, {
			'STATUS' => 'FAILURE',
			'MSG'    => $msg
		};
		unlink($utf8File);
		return @o;
	}

	unlink($utf8File);

	if ($idevscmdout eq '') {
		push @o, {
			'STATUS' => 'FAILURE',
			'MSG'    => 'no_stdout'
		};
		return @o;
	}

	return parseEVSCmdOutput($idevscmdout, $_[0]);
}

#*******************************************************************************
# Fetch all devices for the current in user
# IMPORTANT: Only for dedup accounts
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub fetchAllDevices {
	createUTF8File($Configuration::evsAPIPatterns{'LISTDEVICE'}, $_[0]) or
		retreat('failed_to_create_utf8_file');
	my @responseData = runEVS('item');
	return @responseData;
}

#*******************************************************************************
# Fetch current user's evs server ip
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub fetchServerAddress {
	createUTF8File($Configuration::evsAPIPatterns{'GETSERVERADDRESS'}) or
		retreat('failed_to_create_utf8_file');
	my @responseData = runEVS('tree');
	if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
		retreat('failed_to_fetch_server_address');
	}
	return @responseData;
}
1;
