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

use POSIX;
use POSIX ":sys_wait_h";
use File::Copy;
use File::stat;
use File::Basename;
use Fcntl qw(:flock SEEK_END);
use Common;
use AppConfig;
use constant NO_EXIT => 1;

if (scalar (@ARGV) == 0) {
	$AppConfig::displayHeader = 0;
	Common::retreat('you_cant_run_supporting_script');
}

if ($ARGV[0] !~ m/DECRYPT|ENCRYPT/) {
	Common::checkAndAvoidExecution();
}

if ($ARGV[0] eq Common::getStringConstant('support_file_exec_string')) {
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
	Common::loadAppPath();
	Common::loadServicePath();
	if (Common::loadUsername()){
		Common::loadUserConfiguration();
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
		Common::uploadLog($ARGV[$param]);
	}
	elsif ($operation eq 'UPLOADMIGRATEDLOG') {
		Common::uploadMigratedLog();
	}
	elsif ($operation eq 'INSTALLCRON') {
		installCRON();
	}
	elsif ($operation eq 'VERIFYPREUPDATE') {
		verifyPreUpdate();
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
		preUpdateOperation();
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
		# $AppConfig::callerEnv = 'BACKGROUND';
		my $result = {STATUS => AppConfig::FAILURE, DATA => ''};
		if (-e $ARGV[$param] and !-z $ARGV[$param]){
			$result = Common::request(\%{JSON::from_json(Common::getFileContents($ARGV[$param]))});
		}
		# print JSON::to_json(\%{$result});
		Common::fileWrite($ARGV[$param+1],JSON::to_json(\%{$result}));
	}
	elsif ($operation eq 'CALCULATEBACKUPSETSIZE') {
		calculateBackupSetSize($ARGV[1]);
	}
	else {
		Common::traceLog("Unknown operation: $operation");
	}
}

#*****************************************************************************************************
# Subroutine	: disableAutoInstallCRON
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Disable the auto install CRON job
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub disableAutoInstallCRON {
	# Disable the installation task so that cron wont launch this job again
	Common::loadCrontab(1);
	
	my $freq = Common::getCrontab($AppConfig::misctask, $AppConfig::miscjob, '{settings}{frequency}');
	Common::Chomp(\$freq);
	
	unless($freq) {
		Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, {'settings' => {'status' => 'disabled'}});
		Common::saveCrontab();
	}
}

#*****************************************************************************************************
# Subroutine		: verifyPreUpdate
# In Param			: UNDEF
# Out Param			: UNDEF
# Objective			: Verifies pre update 
# Added By			: Sabin Cheruvattil
#*****************************************************************************************************
sub verifyPreUpdate {
	exit(0) if(Common::hasSQLitePreReq() && Common::hasBasePreReq());
	exit(1);
}

#*****************************************************************************************************
# Subroutine			: installCRON
# Objective				: This subroutine will install and launch the cron job
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub installCRON {
	Common::setServicePath(".") if (!Common::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($AppConfig::mcUser ne 'root');

	# remove current cron link
	unlink($AppConfig::cronLinkPath);
	# create cron link file
	Common::createCRONLink();

	my $cronstat = Common::launchIDriveCRON();
	unless(-f Common::getCrontabFile()) {
		Common::fileWrite(Common::getCrontabFile(), '');
		chmod($AppConfig::filePermission, Common::getCrontabFile());
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
	Common::setServicePath(".") if (!Common::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($AppConfig::mcUser ne 'root');

	# remove current cron link
	unlink($AppConfig::cronLinkPath);
	# create cron link file
	Common::createCRONLink();

	unless (-e Common::getCrontabFile()) {
		Common::fileWrite(Common::getCrontabFile(), '');
		chmod($AppConfig::filePermission, Common::getCrontabFile());
	}
}

#*****************************************************************************************************
# Subroutine			: restartIdriveServices
# Objective				: Restart all IDrive installed services
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restartIdriveServices {
	if ($AppConfig::appType eq 'IDrive') {
		my $filename = Common::getUserFile();
		my $fc = '';
		$fc = Common::getFileContents($filename) if (-f $filename);
		Common::Chomp(\$fc);

		my $mcUsers;
		if (eval { JSON::from_json($fc); 1 } and ($fc ne '')) {
			$mcUsers = JSON::from_json($fc);
			foreach(keys %{$mcUsers}) {
				Common::stopDashboardService($_, Common::getAppPath());
			}
		}
	}

	if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
		my @lockinfo = Common::getCRONLockInfo();
		$lockinfo[2] = 'restart';
		Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
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
	Common::setServicePath(".") if (!Common::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($AppConfig::mcUser ne 'root');

	Common::removeIDriveCRON();
}

#*****************************************************************************************************
# Subroutine			: getAndUpdateQuota
# Objective				: This method is used to get the quota value and update in the file.
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getAndUpdateQuota {
	my $csf = Common::getCachedStorageFile();
	unlink($csf);

	my @result;
	my $webAPI = Common::getUserConfiguration('WEBAPI');
	unless($webAPI){
		Common::traceLog('your_account_not_configured_properly');
		Common::display('your_account_not_configured_properly');
		return 0;
	}

	my $getQuotaCGI = $AppConfig::evsAPI{$AppConfig::appType}{'getAccountQuota'};
	$getQuotaCGI =~ s/EVSSERVERADDRESS/$webAPI/;
	my %params = (
		'host' => $getQuotaCGI,
		'method' => 'POST',
		'data' => {
			'uid' => Common::getUsername(),
			'pwd' => &Common::getPdata(Common::getUsername()),
		}
	);
	my $res = Common::requestViaUtility(\%params);
	if(defined($res->{DATA})) {
		my %evsQuotaHashOutput = Common::parseXMLOutput(\$res->{DATA});
		@result = \%evsQuotaHashOutput;
	}

	unless (@result) {
		Common::traceLog('unable_to_cache_the_quota',".");
		Common::display('unable_to_retrieve_the_quota');
		return 0;
	}

	if (exists $result[0]->{'message'} && $result[0]->{'message'} eq 'ERROR') {
		Common::checkAndUpdateAccStatError(Common::getUsername(), $result[0]->{'desc'});
		Common::traceLog('unable_to_cache_the_quota',". ".ucfirst($result[0]->{'desc'}));
		Common::display('unable_to_retrieve_the_quota');
		return 0;
	}

	if (Common::saveUserQuota(@result)) {
		return 1 if (Common::loadStorageSize());
	}
	Common::traceLog('unable_to_cache_the_quota');
	Common::display('unable_to_cache_the_quota');
	return 0;
}

#*****************************************************************************************************
# Subroutine			: migrateUserData
# Objective				: This method is used to migrate user data.
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserData {
	exit(0) if ($AppConfig::mcUser ne 'root');
	my $migrateLockFile = Common::getMigrateLockFile();

	Common::display(["\n", 'migration_process_starting', '. ']);
	Common::migrateUserFile();
	Common::display(['migration_process_completed', '. ']);
	Common::display(["\n", 'starting_cron_service', '...']);

	if (installCRON()) {
		Common::display(['started_cron_service', '. ',"\n"]);
	} else {
		Common::display(['cron_service_not_running', '. ',"\n"]);
	}

	my @linesCrontab = ();
	my $getOldUserFile = Common::getOldUserFile();
	if (-e Common::getUserFile()) {
		@linesCrontab = Common::readCrontab();
		my @updatedLinesCrontab = Common::removeEntryInCrontabLines(@linesCrontab);
		Common::writeCrontab(@updatedLinesCrontab);
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
	my $cachedIdriveFile = Common::getCatfile(Common::getServicePath(), $AppConfig::cachedIdriveFile);
	return 0 unless(-f $cachedIdriveFile);
	my $usrtxt = Common::getFileContents($cachedIdriveFile);
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		$usrtxt->{$AppConfig::mcUser}{'isLoggedin'} = 0;
		Common::fileWrite(Common::getCatfile(Common::getServicePath(), $AppConfig::cachedIdriveFile), JSON::to_json($usrtxt));
		Common::display(["\"", Common::getUsername(), "\"", ' ', 'is_logged_out_successfully']);
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
	my $destinationFile = $ARGV[$param + 1];
	if (!$sourceFile or !-e $sourceFile) {
		Common::retreat(['Invalid source path',"\n"]);
	} elsif (-z $sourceFile) {
		Common::retreat(['Source ','file_is_empty',"\n"]);
	}
	unless($destinationFile) {
		Common::retreat(['Invalid destination path',"\n"]);
	}
	if ($task eq 'decrypt') {
		my $string = Common::decryptString(Common::getFileContents($sourceFile));
		Common::fileWrite($destinationFile,$string);
	} else {
		my $string = Common::encryptString(Common::getFileContents($sourceFile));
		Common::fileWrite($destinationFile,$string);
	}
}

#*****************************************************************************************************
# Subroutine	: preUpdateOperation
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Handles pre-update related tasks
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub preUpdateOperation {
	my $silent		= 0;
	my $taskParam	= (defined $ARGV[$param])? $ARGV[$param] : '';
	my $tmppkgdir	= (defined $ARGV[$param + 1])? $ARGV[$param + 1] : '';

	if ($taskParam eq 'silent') {
		$AppConfig::callerEnv = 'BACKGROUND';
		$silent = 1;
	}

	my $constpath	= qq($tmppkgdir/$AppConfig::idriveScripts{'constants'});
	my $dlvercmd	= Common::updateLocaleCmd("cat '$constpath' | grep -m1 \"ScriptBuildVersion => '\"");
	my $dlver		= `$dlvercmd`;
	$dlver			= (split(/'/, $dlver))[1];
	Common::Chomp(\$dlver);

	# @TODO: verify version
	# if(Common::versioncompare($version, '2.25') == 2 || Common::versioncompare($dlver, '2.25') == 1) {
	# execute for version greter than current release | don't use release version var
	if(Common::versioncompare($dlver, '2.27') != 2) {
		unless($silent) {
			my $res = system("$AppConfig::perlBin $tmppkgdir/" . $AppConfig::idriveScripts{'utility'} . " PREINSTDEPENDENCIES");

			if($res) {
				Common::display(['unable_to_complete_pre_update_checks', '.', 'please_contact_support_for_more_information']);
				exit(1);
			}

			exit(0);
		} else {
			if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
				my $execmd	= qq("$tmppkgdir/$AppConfig::idriveScripts{'utility'}" SILENTDEPENDENCYINSTALL);

				my @now		= localtime;
				my $stm		= $now[1] + 1;
				$stm		= 0 if($stm > 59);

				Common::loadCrontab(1);
				Common::createCrontab($AppConfig::misctask, $AppConfig::miscjob);
				Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, 'cmd', $execmd);
				Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, {'settings' => {'status' => 'enabled'}});
				Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, {'settings' => {'frequency' => ' '}});
				Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, 'm', $stm);
				Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, 'h', '*');
				Common::saveCrontab();

				Common::fileWrite($AppConfig::silinstlock, 1);
				sleep(2) while(-f $AppConfig::silinstlock);

				disableAutoInstallCRON();

				# VERIFY THE DEPENDENCIES
				my $verifycmd	= qq($AppConfig::perlBin "$tmppkgdir/$AppConfig::idriveScripts{'utility'}" VERIFYPREUPDATE);
				my $res			= system($verifycmd);

				if($res) {
					# @TODO: Send notification to dashboard
					Common::traceLog(['unable_to_complete_silent_pre_update_checks']);
					Common::traceLog(Common::getFileContents($AppConfig::repoerrpath)) if(-f $AppConfig::repoerrpath);
					exit(1);
				}

				Common::traceLog(['pre_update_check_completed', '.']);
				exit(0);
			} else {
				# CRON not running not able to install the dependencies.
				# @TODO: Send notification to dashboard | cron not running
				Common::traceLog(['cron_service_stopped', ' ', 'unable_to_complete_pre_update_checks', '.', ' ', 'please_contact_support_for_more_information']);
				exit(1);
			}
		}
	}
}

#*************************************************************************************************
# Subroutine		: postUpdateOperation
# Objective			: Check & update EVS/Perl binaries if any latest binary available and logout
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub postUpdateOperation {
	my $silent = 0;
	my $taskParam = (defined $ARGV[$param])? $ARGV[$param] : '';

	if ($taskParam eq 'silent') {
		$AppConfig::callerEnv = 'BACKGROUND';
		$silent = 1;
	}

	# Moved here to download latest binaries before restarting Cron/Dashboard services
	if (fetchInstalledEVSBinaryVersion()) {
		if (-f Common::getCatfile(Common::getServicePath(), $AppConfig::evsBinaryName)) {
			Common::removeItems(Common::getCatfile(Common::getServicePath(), $AppConfig::evsBinaryName));
		}
		if (-f Common::getCatfile(Common::getServicePath(), $AppConfig::evsDedupBinaryName)) {
			Common::removeItems(Common::getCatfile(Common::getServicePath(), $AppConfig::evsDedupBinaryName));
		}
		updateEVSBinary();
	}

	if ($AppConfig::appType eq 'IDrive'){
		if (fetchInstalledPerlBinaryVersion()) {
			if (-f Common::getCatfile(Common::getServicePath(), $AppConfig::staticPerlBinaryName)) {
				Common::removeItems(Common::getCatfile(Common::getServicePath(), $AppConfig::staticPerlBinaryName));
			}
			updatePerlBinary();
		}
	}

	deleteDeprecatedScripts();

	my $bsf = Common::getJobsPath('backup', 'file');
	unlink("$bsf.info") if (-f "$bsf.info");

	if (-f Common::getCatfile(Common::getJobsPath('backup'), 'backupsetsize.json')) {
		rename Common::getCatfile(Common::getJobsPath('backup'), 'backupsetsize.json'), "$bsf.json";
	}

	# Create version file post update
	Common::createVersionCache($AppConfig::version);
	# verify, relink, launch|restart cron
	checkAndStartCRON($taskParam);

	my $cmd = ("$AppConfig::perlBin " . Common::getScript('logout', 1));
	$cmd   .= (" $silent 0 'NOUSERINPUT' 2>/dev/null");
	$cmd = Common::updateLocaleCmd($cmd);
	my $res = `$cmd`;
	print $res;

	Common::initiateMigrate();
}

#*************************************************************************************************
# Subroutine		: fetchInstalledEVSBinaryVersion
# Objective			: Get the installed EVS binaries version
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub fetchInstalledEVSBinaryVersion {
	#print "hasEVSBinary:".Common::hasEVSBinary()."#\n";
	my $needToDownload = 1;
	if ((Common::hasEVSBinary())) {
		my @evsBinaries = (
			$AppConfig::evsBinaryName
		);
		push(@evsBinaries, $AppConfig::evsDedupBinaryName) if ($AppConfig::appType eq 'IDrive');

		my $servicePath = Common::getServicePath();
		my %evs;
		for (@evsBinaries) {
			my $evs = $servicePath."/".$_;
			my $cmd = "'$evs' --client-version";
			$cmd = Common::updateLocaleCmd($cmd);
			my $nonDedupVersion = `$cmd 2>/dev/null`;
			#print "nonDedupVersion:$nonDedupVersion\n\n\n";
			$nonDedupVersion =~ m/idevsutil version(.*)release date(.*)/;

			$evs{$_}{'version'} = $1;
			$evs{$_}{'release_date'} = $2;
			$evs{$_}{'release_date'} =~ s/\(DEDUP\)//;

			Common::Chomp(\$evs{$_}{'version'});
			Common::Chomp(\$evs{$_}{'release_date'});

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
	if (Common::hasStaticPerlBinary()) {
		my $sp = Common::getIDrivePerlBin();
		my $cmd = "$sp -MIdrivelib -e 'print \$Idrivelib::VERSION'";
		my $version = `$cmd 2>/dev/null`;
		Common::Chomp(\$version);
		if ($version eq $AppConfig::staticPerlVersion) {
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
	Common::display(["\n", 'downloading_updated_static_perl_binary', '...']);
	if(Common::downloadStaticPerlBinary() and Common::hasStaticPerlBinary()) {
		Common::display(['static_perl_binary_downloaded_successfully',"\n"]);
	}
	else {
		Common::display('unable_to_download_static_perl_binary');
	}
}

#*************************************************************************************************
# Subroutine		: updateEVSBinary
# Objective			: download the latest EVS binary and update
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub updateEVSBinary {
	Common::display(["\n", 'downloading_updated_evs_binary', '...']);
	if(Common::downloadEVSBinary() and Common::hasEVSBinary()) {
		Common::display('evs_binary_downloaded_successfully');
	}
	else {
		Common::display('unable_to_download_evs_binary');
	}
}

#*************************************************************************************************
# Subroutine		: checkAndStartCRON
# Objective			: Start the cron job | Do not move this method to Helpers
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian
#*************************************************************************************************/
sub checkAndStartCRON {
	my $taskParam = $_[0];
	my $os = Common::getOSBuild();
	if ($AppConfig::appType eq 'IDrive') {
		Common::stopDashboardService($AppConfig::mcUser, Common::getAppPath());
	}

	if ($taskParam eq 'silent') {
		if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
			my @lockinfo = Common::getCRONLockInfo();
			$lockinfo[2] = 'restart';
			$lockinfo[3] = 'update';
			Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
		}

		Common::stopDashboardService($AppConfig::mcUser, Common::getAppPath());
		return 1;
	}

	# @TODO: verify the release version
	# 2.25 CRON restart issue | Issue fixed in this release
	if(Common::versioncompare($version, '2.25') == 2 && $os->{'os'} eq 'ubuntu') {
		# Remove cron lock so that manual restart will happen
		unlink($AppConfig::cronlockFile);
	}

	if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
		my @lockinfo = Common::getCRONLockInfo();
		$lockinfo[2] = 'restart';
		$lockinfo[3] = 'update';
		Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
		return 1;
	}

	# if cron link is absent, reinstall the cron | this case can be caused by un-installation from other installation
	Common::display(['cron_service_must_be_restarted_for_this_update']) if ($AppConfig::mcUser ne 'root');
	my $sudoprompt = 'please_provide_' . ((Common::isUbuntu() || Common::isGentoo())? 'sudoers' : 'root') . '_pwd_for_cron';
	my $sudosucmd = Common::getSudoSuCRONPerlCMD('restartidriveservices', $sudoprompt);
	unless (system($sudosucmd) == 0) {
		Common::display('failed_to_restart_idrive_services');
	}
	else {
		Common::display(['cron_service_has_been_restarted']);
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
	foreach my $depScript (keys %AppConfig::idriveScripts) {
		unlink(Common::getAppPath() . qq(/$AppConfig::idriveScripts{$depScript})) if ($depScript =~ m/deprecated_/);
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
	unless (Common::isFileLocked(Common::getBackupsetSizeLockFile($_[0]), 1)) {
		Common::updateBackupsetFileSize($_[0]);
		Common::loadNotifications() and
			Common::setNotification(sprintf("get_%sset_content", $_[0])) and Common::saveNotifications();

		Common::calculateBackupsetSize($_[0]);
		Common::loadNotifications() and
			Common::setNotification(sprintf("get_%sset_content", $_[0])) and Common::saveNotifications();
	}
	return 1;
}
