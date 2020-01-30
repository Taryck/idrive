#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to run the independent functionalities
#
# Created By: Anil Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

#use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);
use lib map{if (__FILE__ =~ /\//) {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";}}else {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {"./$_";}}} qw(Idrivelib/lib .);

my $incPos = rindex(__FILE__, '/');
my $incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

use Helpers;
use Configuration;
use constant NO_EXIT => 1;

if (scalar (@ARGV) == 0) {
	$Configuration::displayHeader = 0;
	Helpers::retreat('you_cant_run_supporting_script');
}

if ($ARGV[0] !~ m/DECRYPT|ENCRYPT/) {
	Helpers::checkAndAvoidExecution();
}

if ($ARGV[0] eq Helpers::getStringConstant('support_file_exec_string')) {
	my $ss = shift @ARGV;
}

my $operation = $ARGV[0];
my $param     = 1;
my $version;

if ($operation =~ m/PREUPDATE|POSTUPDATE/) {
	$version = $ARGV[1];
	$param   = 2;
}

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub init {
	Helpers::loadAppPath();
	Helpers::loadServicePath();
	if (Helpers::loadUsername()){
		Helpers::loadUserConfiguration();
	}

	performOperation($operation);
}

#*****************************************************************************************************
# Subroutine			: performOperation
# Objective				: This method is used to differentiate the functionality based on the operation  required to done.
# Added By				: Anil Kumar
# Modified By 			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub performOperation {
	my $operation = '';
	$operation = $_[0] if ($_[0]);
	if ($operation eq "GETQUOTA") {
		getAndUpdateQuota();
	}
	elsif ($operation eq 'UPLOADLOG') {
		Helpers::uploadLog($ARGV[$param]);
	}
	elsif ($operation eq 'UPLOADMIGRATEDLOG') {
		Helpers::uploadMigratedLog();
	}
	elsif ($operation eq 'INSTALLCRON') {
		installCRON();
	}
	elsif ($operation eq 'RESTARTIDRIVESERVICES') {
		restartIdriveServices();
	}
	elsif ($operation eq 'RELINKCRON') {
		relinkCRON();
	}
	elsif ($operation eq 'UNINSTALLCRON') {
		uninstallCRON();
	}
	elsif ($operation eq 'MIGRATEUSERDATA') {
		migrateUserData();
	}
	elsif ($operation eq 'PREUPDATE') {
		$Configuration::callerEnv = 'BACKGROUND' if (defined $ARGV[$param+1] and $ARGV[$param+1] eq 'silent');
		#print "Version:".$version."\n\n" if (defined $version);
		#doLogout();
	}
	elsif ($operation eq 'POSTUPDATE') {
		postUpdateOperation();
	}
	elsif (defined($operation) and $operation eq 'DECRYPT') {
		decryptEncrypt('decrypt');
	}
	elsif (defined($operation) and $operation eq 'ENCRYPT') {
		decryptEncrypt('encrypt');
	}
	elsif ($operation eq 'SERVERREQUEST') {
		# $Configuration::callerEnv = 'BACKGROUND';
		my $result = {STATUS => Configuration::FAILURE, DATA => ''};
		if (-e $ARGV[$param] and !-z $ARGV[$param]){
			$result = Helpers::request(\%{JSON::from_json(Helpers::getFileContents($ARGV[$param]))});
		}
		# print JSON::to_json(\%{$result});
		Helpers::fileWrite($ARGV[$param+1],JSON::to_json(\%{$result}));
	}
	elsif ($operation eq 'CALCULATEBACKUPSETSIZE') {
		calculateBackupSetSize($ARGV[1]);
	}
	else {
		Helpers::traceLog("Unknown operation: $operation");
	}
}

#*****************************************************************************************************
# Subroutine			: installCRON
# Objective				: This subroutine will install and launch the cron job
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub installCRON {
	Helpers::setServicePath(".") if (!Helpers::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($Configuration::mcUser ne 'root');

	# remove current cron link
	unlink($Configuration::cronLinkPath);
	# create cron link file
	Helpers::createCRONLink();

	my $cronstat = Helpers::launchIDriveCRON();
	unless(-f Helpers::getCrontabFile()) {
		Helpers::fileWrite(Helpers::getCrontabFile(), '');
		chmod($Configuration::filePermission, Helpers::getCrontabFile());
	}

	# wait for the cron to start | handle lock delay
	sleep(5);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: relinkCRON
# Objective				: This subroutine will relink the cron job
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub relinkCRON {
	Helpers::setServicePath(".") if (!Helpers::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($Configuration::mcUser ne 'root');

	# remove current cron link
	unlink($Configuration::cronLinkPath);
	# create cron link file
	Helpers::createCRONLink();

	unless (-e Helpers::getCrontabFile()) {
		Helpers::fileWrite(Helpers::getCrontabFile(), '');
		chmod($Configuration::filePermission, Helpers::getCrontabFile());
	}
}

#*****************************************************************************************************
# Subroutine			: restartIdriveServices
# Objective				: Restart all IDrive installed services
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restartIdriveServices {
	if ($Configuration::appType eq 'IDrive') {
		my $filename = Helpers::getUserFile();
		my $fc = '';
		$fc = Helpers::getFileContents($filename) if (-f $filename);
		Helpers::Chomp(\$fc);

		my $mcUsers;
		if (eval { JSON::from_json($fc); 1 } and ($fc ne '')) {
			$mcUsers = JSON::from_json($fc);
			foreach(keys %{$mcUsers}) {
				Helpers::stopDashboardService($_, Helpers::getAppPath());
			}
		}
	}

	if (Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
		my @lockinfo = Helpers::getCRONLockInfo();
		$lockinfo[2] = 'restart';
		Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
		return relinkCRON();
	}

	return installCRON();
}

#*****************************************************************************************************
# Subroutine			: uninstallCRON
# Objective				: This subroutine will uninstall the cron job
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub uninstallCRON {
	Helpers::setServicePath(".") if (!Helpers::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($Configuration::mcUser ne 'root');

	Helpers::removeIDriveCRON();
}

#*****************************************************************************************************
# Subroutine			: getAndUpdateQuota
# Objective				: This method is used to get the quota value and update in the file.
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getAndUpdateQuota {
	my $csf = Helpers::getCachedStorageFile();
	unlink($csf);

	my @result;
	my $webAPI = Helpers::getUserConfiguration('WEBAPI');
	unless($webAPI){
		Helpers::traceLog('your_account_not_configured_properly');
		Helpers::display('your_account_not_configured_properly');
		return 0;
	}

	my $getQuotaCGI = $Configuration::evsAPI{$Configuration::appType}{'getAccountQuota'};
	$getQuotaCGI =~ s/EVSSERVERADDRESS/$webAPI/;
	my %params = (
		'host' => $getQuotaCGI,
		'method' => 'POST',
		'data' => {
			'uid' => Helpers::getUsername(),
			'pwd' => &Helpers::getPdata(Helpers::getUsername()),
		}
	);
	my $res = Helpers::requestViaUtility(\%params);
	if(defined($res->{DATA})) {
		my %evsQuotaHashOutput = Helpers::parseXMLOutput(\$res->{DATA});
		@result = \%evsQuotaHashOutput;
	}

	unless (@result) {
		Helpers::traceLog('unable_to_cache_the_quota',".");
		Helpers::display('unable_to_retrieve_the_quota');
		return 0;
	}

	if (exists $result[0]->{'message'} && $result[0]->{'message'} eq 'ERROR') {
		Helpers::traceLog('unable_to_cache_the_quota',". ".ucfirst($result[0]->{'desc'}));
		Helpers::display('unable_to_retrieve_the_quota');
		return 0;
	}

	if (Helpers::saveUserQuota(@result)) {
		return 1 if (Helpers::loadStorageSize());
	}
	Helpers::traceLog('unable_to_cache_the_quota');
	Helpers::display('unable_to_cache_the_quota');
	return 0;
}

#*****************************************************************************************************
# Subroutine			: migrateUserData
# Objective				: This method is used to migrate user data.
# Added By				: Vijay Vinodh
#****************************************************************************************************/
sub migrateUserData {

	exit(0) if ($Configuration::mcUser ne 'root');
	my $migrateLockFile = Helpers::getMigrateLockFile();

	Helpers::display(["\n", 'migration_process_starting', '. ']);
	Helpers::migrateUserFile();
	Helpers::display(['migration_process_completed', '. ']);
	Helpers::display(["\n", 'starting_cron_service', '...']);

	if (installCRON()) {
		Helpers::display(['started_cron_service', '. ',"\n"]);
	} else {
		Helpers::display(['cron_service_not_running', '. ',"\n"]);
	}

	my @linesCrontab = ();
	my $getOldUserFile = Helpers::getOldUserFile();
	if (-e Helpers::getUserFile()) {
		@linesCrontab = Helpers::readCrontab();
		my @updatedLinesCrontab = Helpers::removeEntryInCrontabLines(@linesCrontab);
		Helpers::writeCrontab(@updatedLinesCrontab);
		unlink $getOldUserFile;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: doLogout
# Objective				: Logout current user's a/c
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub doLogout {
	my $cachedIdriveFile = Helpers::getCatfile(Helpers::getServicePath(), $Configuration::cachedIdriveFile);
	return 0 unless(-f $cachedIdriveFile);
	my $usrtxt = Helpers::getFileContents($cachedIdriveFile);
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		$usrtxt->{$Configuration::mcUser}{'isLoggedin'} = 0;
		Helpers::fileWrite(Helpers::getCatfile(Helpers::getServicePath(), $Configuration::cachedIdriveFile), JSON::to_json($usrtxt));
		Helpers::display(["\"", Helpers::getUsername(), "\"", ' ', 'is_logged_out_successfully']);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: decryptEncrypt
# Objective				: Decrypt/Encrypt the file content & write into another file
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub decryptEncrypt {
	my $task 		 	= $_[0];
	my $sourceFile 	 	= $ARGV[$param];
	my $destinationFile = $ARGV[$param+1];
	if (!$sourceFile or !-e $sourceFile) {
		Helpers::retreat(['Invalid source path',"\n"]);
	} elsif (-z $sourceFile) {
		Helpers::retreat(['Source ','file_is_empty',"\n"]);
	}
	unless($destinationFile) {
		Helpers::retreat(['Invalid destination path',"\n"]);
	}
	if ($task eq 'decrypt') {
		my $string = Helpers::decryptString(Helpers::getFileContents($sourceFile));
		Helpers::fileWrite($destinationFile,$string);
	} else {
		my $string = Helpers::encryptString(Helpers::getFileContents($sourceFile));
		Helpers::fileWrite($destinationFile,$string);
	}
}

#*************************************************************************************************
# Subroutine		: postUpdateOperation
# Objective			: Check & update EVS/Perl binaries if any latest binary available and logout
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub postUpdateOperation {
	my $silent = 0;
	my $taskParam = (defined $ARGV[$param])? $ARGV[$param] : '';

	if ($taskParam eq 'silent') {
		$Configuration::callerEnv = 'BACKGROUND';
		$silent = 1;
	}

	# Moved here to download latest binaries before restarting Cron/Dashboard services
	if (fetchInstalledEVSBinaryVersion()) {
		if (-f Helpers::getCatfile(Helpers::getServicePath(), $Configuration::evsBinaryName)) {
			Helpers::removeItems(Helpers::getCatfile(Helpers::getServicePath(), $Configuration::evsBinaryName));
		}
		if (-f Helpers::getCatfile(Helpers::getServicePath(), $Configuration::evsDedupBinaryName)) {
			Helpers::removeItems(Helpers::getCatfile(Helpers::getServicePath(), $Configuration::evsDedupBinaryName));
		}
		updateEVSBinary();
	}

	if ($Configuration::appType eq 'IDrive'){
		if (fetchInstalledPerlBinaryVersion()) {
			if (-f Helpers::getCatfile(Helpers::getServicePath(), $Configuration::staticPerlBinaryName)) {
				Helpers::removeItems(Helpers::getCatfile(Helpers::getServicePath(), $Configuration::staticPerlBinaryName));
			}
			updatePerlBinary();
		}
	}

	deleteDeprecatedScripts();

	my $bsf = Helpers::getJobsPath('backup', 'file');
	unlink("$bsf.info") if (-f "$bsf.info");

	if (-f Helpers::getCatfile(Helpers::getJobsPath('backup'), 'backupsetsize.json')) {
		rename Helpers::getCatfile(Helpers::getJobsPath('backup'), 'backupsetsize.json'), "$bsf.json";
	}

	# verify, relink, launch|restart cron
	checkAndStartCRON($taskParam);

	my $cmd = ("$Configuration::perlBin " . Helpers::getScript('logout', 1));
	$cmd   .= (" $silent 0 'NOUSERINPUT' 2>/dev/null");
	$cmd = Helpers::updateLocaleCmd($cmd);
	my $res = `$cmd`;
	print $res;

	Helpers::initiateMigrate();
}

#*************************************************************************************************
# Subroutine		: fetchInstalledEVSBinaryVersion
# Objective			: Get the installed EVS binaries version
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub fetchInstalledEVSBinaryVersion {
	#print "hasEVSBinary:".Helpers::hasEVSBinary()."#\n";
	my $needToDownload = 1;
	if ((Helpers::hasEVSBinary())) {
		my @evsBinaries = (
			$Configuration::evsBinaryName
		);
		push(@evsBinaries, $Configuration::evsDedupBinaryName) if ($Configuration::appType eq 'IDrive');

		my $servicePath = Helpers::getServicePath();
		my %evs;
		#use Data::Dumper;
		for (@evsBinaries) {
			my $evs = $servicePath."/".$_;
			my $cmd = "'$evs' --client-version";
			$cmd = Helpers::updateLocaleCmd($cmd);
			my $nonDedupVersion = `$cmd 2>/dev/null`;
			#print "nonDedupVersion:$nonDedupVersion\n\n\n";
			$nonDedupVersion =~ m/idevsutil version(.*)release date(.*)/;

			$evs{$_}{'version'} = $1;
			$evs{$_}{'release_date'} = $2;
			$evs{$_}{'release_date'} =~ s/\(DEDUP\)//;

			Helpers::Chomp(\$evs{$_}{'version'});
			Helpers::Chomp(\$evs{$_}{'release_date'});

			if ($evs{$_}{'version'} ne $Configuration::evsVersionSchema{$Configuration::appType}{$_}{'version'} or $evs{$_}{'release_date'} ne $Configuration::evsVersionSchema{$Configuration::appType}{$_}{'release_date'}) {
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
	if (Helpers::hasStaticPerlBinary()) {
		my $sp = Helpers::getIDrivePerlBin();
		my $cmd = "$sp -MIdrivelib -e 'print \$Idrivelib::VERSION'";
		my $version = `$cmd 2>/dev/null`;
		Helpers::Chomp(\$version);
		if ($version eq $Configuration::staticPerlVersion) {
			$needToDownload = 0;
		}
	}
	return $needToDownload;
}

#*************************************************************************************************
# Subroutine		: updatePerlBinary
# Objective			: download the latest perl binary and update
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub updatePerlBinary {
	Helpers::display(["\n", 'downloading_updated_static_perl_binary', '...']);
	if(Helpers::downloadStaticPerlBinary() and Helpers::hasStaticPerlBinary()) {
		Helpers::display(['static_perl_binary_downloaded_successfully',"\n"]);
	}
	else {
		Helpers::display('unable_to_download_static_perl_binary');
	}
}

#*************************************************************************************************
# Subroutine		: updateEVSBinary
# Objective			: download the latest EVS binary and update
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub updateEVSBinary {
	Helpers::display(["\n", 'downloading_updated_evs_binary', '...']);
	if(Helpers::downloadEVSBinary() and Helpers::hasEVSBinary()) {
		Helpers::display('evs_binary_downloaded_successfully');
	}
	else {
		Helpers::display('unable_to_download_evs_binary');
	}
}

#*************************************************************************************************
# Subroutine		: checkAndStartCRON
# Objective			: Start the cron job
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian
#*************************************************************************************************/
sub checkAndStartCRON {
	my $taskParam = $_[0];
	if ($Configuration::appType eq 'IDrive') {
		Helpers::stopDashboardService($Configuration::mcUser, Helpers::getAppPath());
	}
	if ($taskParam eq 'silent') {
		if (Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
			my @lockinfo = Helpers::getCRONLockInfo();
			$lockinfo[2] = 'restart';
			Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
		}
	}
	else {
		# if cron link is absent, reinstall the cron | this case can be caused by un-installation from other installation
		Helpers::display(['cron_service_must_be_restarted_for_this_update']) if ($Configuration::mcUser ne 'root');
		my $sudoprompt = 'please_provide_' . ((Helpers::isUbuntu() || Helpers::isGentoo())? 'sudoers' : 'root') . '_pwd_for_cron';
		my $sudosucmd = Helpers::getSudoSuCRONPerlCMD('restartidriveservices', $sudoprompt);
		#$sudosucmd = Helpers::updateLocaleCmd($sudosucmd); #Commented by Senthil to promt "Password:"
		unless (system($sudosucmd) == 0) {
			if (Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
				my @lockinfo = Helpers::getCRONLockInfo();
				$lockinfo[2] = 'restart';
				Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
			}
			else {
				Helpers::display('failed_to_restart_idrive_services');
			}
		}
		else {
			Helpers::display(['cron_service_has_been_restarted']);
		}
	}

	return 1;
}

#*************************************************************************************************
# Subroutine		: deleteDeprecatedScripts
# Objective			: delete deprecated scripts if present
# Added By			: Sabin Cheruvattil
# Modified By       : Senthil Pandian
#*************************************************************************************************/
sub deleteDeprecatedScripts {
	# my $packageDir = qq(/$Configuration::tmpPath/$Configuration::appPackageName/scripts);
	# my $constantsFilePath = $packageDir.qq(/$Configuration::idriveScripts{'constants'});
	# if (!-e $constantsFilePath){
		# Helpers::cleanupUpdate([
				# "\n", 'invalid_zip_file', "\n",
				# $Configuration::appDownloadURL, "\n\n",
			# ]);
	# }

	# my $downloadedVersionCmd = Helpers::updateLocaleCmd("cat '$constantsFilePath' | grep -m1 \"ScriptBuildVersion => '\"");
	# my $downloadedVersion = `$downloadedVersionCmd`;
	# $downloadedVersion = (split(/'/, $downloadedVersion))[1];
	# Helpers::Chomp(\$downloadedVersion);
	# if (Helpers::versioncompare($ARGV[$param], $downloadedVersion) == 1) {
		# return 1;
	# }
	foreach my $depScript (keys %Configuration::idriveScripts) {
		unlink(Helpers::getAppPath() . qq(/$Configuration::idriveScripts{$depScript})) if ($depScript =~ m/deprecated_/);
	}
}

#*****************************************************************************************************
# Subroutine : calculateBackupSetSize
# In Param   : STRING
# Out Param  : -
# Objective  : Calculate online/local backupset(files) size.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub calculateBackupSetSize {
	unless (Helpers::isFileLocked(Helpers::getBackupsetSizeLockFile($_[0]), 1)) {
		Helpers::updateBackupsetFileSize($_[0]);
		Helpers::loadNotifications() and
			Helpers::setNotification(sprintf("get_%sset_content", $_[0])) and Helpers::saveNotifications();

		Helpers::calculateBackupsetSize($_[0]);
		Helpers::loadNotifications() and
			Helpers::setNotification(sprintf("get_%sset_content", $_[0])) and Helpers::saveNotifications();
	}
	return 1;
}
