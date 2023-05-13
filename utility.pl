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

eval {
	require File::Copy;
	File::Copy->import();
};

use File::stat;
use File::Basename;
use Fcntl qw(:flock SEEK_END);
use utf8;
use JSON qw(from_json to_json);
use Common;
use AppConfig;

use constant NO_EXIT => 1;

if (scalar (@ARGV) == 0) {
	$AppConfig::displayHeader = 0;
	Common::retreat('you_cant_run_supporting_script');
}

if ($ARGV[0] !~ m/DECRYPT|ENCRYPT|DISPCRONREBOOTCMD/) {
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
	if ($_[0]) {
		$operation = $_[0];
		chomp($operation);
	}

	if ($operation eq "GETQUOTA") {
		$AppConfig::callerEnv = 'BACKGROUND'; #Added to avoid unwanted error message display 
		getAndUpdateQuota($ARGV[1]);
	}
	elsif ($operation eq 'UPLOADMIGRATEDLOG') {
		Common::uploadMigratedLog();
	}
	elsif ($operation eq 'INSTALLCRON') {
		installCRON();
	}
	elsif ($operation eq 'INSTALLDEPENDENCIES') {
		installDependencies(1);
	}
	elsif ($operation eq 'SILENTDEPENDENCYINSTALL') {
		silentDependencyInstall();
	}
	elsif ($operation eq 'PREINSTDEPENDENCIES') {
		interactiveDepInstall();
	}
	elsif ($operation eq 'DISPLAYPACKAGEDEP') {
		displayPackageDep();
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
		my $result = {STATUS => AppConfig::FAILURE, DATA => ''};
		if (-e $ARGV[$param] and !-z $ARGV[$param]){
			$result = Common::request(\%{JSON::from_json(Common::getFileContents($ARGV[$param]))});
		}
		# print JSON::to_json(\%{$result});
		Common::fileWrite($ARGV[$param+1],JSON::to_json(\%{$result}));
	}
	elsif($operation eq 'CDP') {
		cdpWatch();
	}
	elsif($operation eq 'CDPRESCAN') {
		cdpRescan();
	}
	elsif($operation eq 'DBWRITER') {
		launchDBWriter();
	}
	elsif ($operation eq 'DASHBOARD1') {
		updateFileset($ARGV[$param]);
	}
	elsif ($operation eq 'DASHBOARD2') {
		recalFileset($ARGV[$param]);
	}
	elsif ($operation eq 'DASHBOARD3') {
		getLogs();
	}
	elsif ($operation eq 'DASHBOARD4') {
		getprogressdetails($ARGV[$param]);
	}
	elsif ($operation eq 'DASHBOARD6') {
		deleteLog($ARGV[$param], $ARGV[$param + 1]);
	}
	elsif ($operation eq 'DASHBOARD7') {
		renameBackupLocation($ARGV[$param]);
	}
	elsif ($operation eq 'DASHBOARD8') {
		getLocalDrives();
	}
	elsif ($operation eq 'DASHBOARD9') {
		deleteDashboard();
	}
	elsif ($operation eq 'DASHBOARD10') {
		getLogDetails($ARGV[$param], $ARGV[$param + 1]);
	}
	elsif ($operation eq 'UPDATEJOBSTATUS') {
		updateJobStatus($ARGV[$param]);
	}
	elsif ($operation eq 'SAVECDPSETTINGS') {
		saveCDPSettings($ARGV[$param]);
	}
	elsif ($operation eq 'VERIFYBACKUPSET') {
		verifyBackupset($ARGV[$param], $ARGV[$param + 1]);
	}
	elsif ($operation eq 'RECALCULATEBACKUPSETSIZE') {
		recalculateBackupsetSize();
	}
	elsif($operation eq 'GETLOCALBACKUPSIZE') {
		getLocalBackupSize();
	}
	elsif($operation eq 'GETLOCALRESTOREFILES') {
		getLocalRestoreFiles($ARGV[$param], $ARGV[$param + 1]);
	}
	elsif($operation eq "REINDEX") {
		#my $errorKey = Helpers::loadUserConfiguration();
		#Helpers::retreat($Configuration::errorDetails{$errorKey}) if($errorKey != 1);
		startReIndexOperation();
	}
	elsif($operation eq "DISPCRONREBOOTCMD") {
		displayCRONRebootCMD();
	}
	elsif($operation eq "PRINTVERSIONDATEFORDASHBOARD") {
		printVersionDateForDashboard();
	}
	elsif($operation eq "PRINTVERSIONFORDASHBOARD") {
		printVersionForDashboard();
	}
	# elsif($operation eq 'LAUNCHDEVICETRUSTCHECK') {
	# 	requestDevicetrust();
	# }
	else {
		Common::traceLog("Unknown operation: $operation");
	}
}

#*****************************************************************************************************
# Subroutine	: printVersionForDashboard
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Prints the scripts version for dashboard display
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub printVersionForDashboard {
	print($AppConfig::version);
	exit(0);
}

#*****************************************************************************************************
# Subroutine	: printVersionDateForDashboard
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Prints the scripts version and release date for dashboard display
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub printVersionDateForDashboard {
	my $ptver	= $AppConfig::version;
	my $ptdate	= $AppConfig::releasedate;
	$ptdate		=~ s/-/\//g;

	print($ptver . '_' . $ptdate);
	exit(0);
}

#*****************************************************************************************************
# Subroutine	: interactiveDepInstall
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Install dependencies in interactive mode
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub interactiveDepInstall {
	exit(1) unless(Common::checkInstallDBCDPPreRequisites());
	exit(0);
}

#*****************************************************************************************************
# Subroutine	: silentDependencyInstall
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Install dependencies in silent mode
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub silentDependencyInstall {
	exit(1) if($AppConfig::mcUser ne 'root');

	if(Common::hasSQLitePreReq() && Common::hasFileNotifyPreReq() && Common::hasBasePreReq()) {
		unlink($AppConfig::silinstlock) if(-f $AppConfig::silinstlock);
		exit(0);
	}

	# Do fork and perform the job, in case of failure installation will exit
	my $instpid = fork();
	if($instpid == 0) {
		installDependencies(0);
		exit(0);
	}

	waitpid($instpid, 0);

	unlink($AppConfig::silinstlock) if(-f $AppConfig::silinstlock);
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
	Common::lockCriticalUpdate("cron");
	# Disable the installation task so that cron wont launch this job again
	Common::loadCrontab(1);
	
	my $freq = Common::getCrontab($AppConfig::misctask, $AppConfig::miscjob, '{settings}{frequency}');
	Common::Chomp(\$freq);
	
	unless($freq) {
		Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, {'settings' => {'status' => 'disabled'}});
		Common::saveCrontab();
	}

	Common::unlockCriticalUpdate("cron");
}

#*****************************************************************************************************
# Subroutine		: displayPackageDep
# In Param			: UNDEF
# Out Param			: UNDEF
# Objective			: Prints required dependencies
# Added By			: Sabin Cheruvattil
#*****************************************************************************************************
sub displayPackageDep {
	my $deps;

	# if (Common::checkCRONServiceStatus() ne Common::CRON_RUNNING) {
		# $deps = {'pkg' => [], 'cpanpkg' => [], 'error' => 'cron_not_running'};
	# }

	if(Common::hasSQLitePreReq() && Common::hasBasePreReq() && (Common::hasFileNotifyPreReq() || !Common::canKernelSupportInotify())) {
		$deps = {'pkg' => [], 'cpanpkg' => [], 'error' => ''};
	} else {
		my $os		= Common::getOSBuild();
		my $pkgseq	= $AppConfig::depInstallUtils{$os->{'os'}}{'pkg-install'};
		my $cpseq	= $AppConfig::depInstallUtils{$os->{'os'}}{'cpan-install'};

		my ($packs, $cpanpacks);
		($pkgseq, $packs)		= Common::getPkgInstallables($pkgseq);
		($cpseq, $cpanpacks)	= Common::getCPANInstallables($cpseq);

		$deps = {'pkg' => $packs, 'cpanpkg' => $cpanpacks, 'error' => ''};
	}

	Common::display(JSON::to_json($deps));
	exit(0);
}

#*****************************************************************************************************
# Subroutine		: installDependencies
# In Param			: UNDEF
# Out Param			: UNDEF
# Objective			: install dependencies in root mode
# Added By			: Sabin Cheruvattil
#*****************************************************************************************************
sub installDependencies {
	exit(1) if($AppConfig::mcUser ne 'root');

	my $os				= Common::getOSBuild();
	my $installargs		= {
		'display'			=> $_[0],
		'pkginstallseq'		=> $AppConfig::depInstallUtils{$os->{'os'}}{'pkg-install'},
		'silinstappend'		=> $AppConfig::depInstallUtils{$os->{'os'}}{'pkg-sil-append-cmd'},
		'cpaninstallseq'	=> $AppConfig::depInstallUtils{$os->{'os'}}{'cpan-install'},
		'cpancmdappend'		=> $AppConfig::depInstallUtils{$os->{'os'}}{'cpan-append-cmd'},
		'pkgerr'			=> $AppConfig::depInstallUtils{$os->{'os'}}{'pkg-repo-error'},
		'cpanconf'			=> $AppConfig::depInstallUtils{$os->{'os'}}{'cpan-conf'},
		'pkgerrignore'		=> $AppConfig::depInstallUtils{$os->{'os'}}{'pkg-err-ignore'},
	};

	Common::installDBCDPPreRequisites($installargs);
	unlink($AppConfig::instproglock) if(-f $AppConfig::instproglock);

	# Do a final check for prerequisites
	exit(1) if(!Common::hasSQLitePreReq() || !Common::hasBasePreReq());

	Common::installInotifyFallBackPreReq() if(!Common::hasFileNotifyPreReq() && Common::canKernelSupportInotify());

	exit(0);
}

#*****************************************************************************************************
# Subroutine		: verifyPreUpdate
# In Param			: UNDEF
# Out Param			: UNDEF
# Objective			: Verifies pre update 
# Added By			: Sabin Cheruvattil
#*****************************************************************************************************
sub verifyPreUpdate {
	return 1 if(Common::hasSQLitePreReq() && Common::hasBasePreReq());
	return 0;
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

	Common::removeFallBackCRONEntry();

	# remove current cron link
	unlink($AppConfig::cronLinkPath);
	# create cron link file
	Common::createCRONLink();

	my $cronstat = Common::launchIDriveCRON();
	if(!-f Common::getCrontabFile() and -w dirname(Common::getCrontabFile())) {
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
# Modified By			: Sabin Cheruvattil
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

	Common::removeFallBackCRONEntry();

	if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
		my @lockinfo = Common::getCRONLockInfo();
		if($lockinfo[2] and $lockinfo[2] eq $AppConfig::cronSetup) {
			unlink($AppConfig::cronlockFile);
		} else {
			$lockinfo[2] = 'restart';
			Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
			return relinkCRON();
		}
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
	unlink($csf) unless(defined($_[0])); # Modified by Senthil to avoid quota display issue when EVS called to getQuota very frequently & failed to update file.
	my @result;
 
    my $planSpecial = Common::getUserConfiguration('PLANSPECIAL');
    if($planSpecial ne '' and $planSpecial =~ /business/i) {
        my $uname = Common::getUsername();
        my $upswd = &Common::getPdata($uname);
        my $encType = Common::getUserConfiguration('ENCRYPTIONTYPE');
        my @responseData;
        my $errStr = '';

        my $res = Common::makeRequest(12);
        if ($res) {
            @result = Common::parseEVSCmdOutput($res->{DATA}, 'login', 1);
        }
    } else {
		Common::createUTF8File('GETQUOTA') or Common::retreat('failed_to_create_utf8_file');
		@result = Common::runEVS('tree');
		if (exists $result[0]->{'message'}) {
			if ($result[0]->{'message'} eq 'ERROR') {
				Common::display('unable_to_retrieve_the_quota');
				return 0;
			}
		}
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
		if(Common::isLogoutRequired(\@result)) {
			doLogout();
			Common::retreat(['please_login_account_using_login_and_try']);
		}

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
		Common::traceLog('logout');
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
	my $servdir		= (defined $ARGV[$param + 1])? $ARGV[$param + 1] : '';
	my $username	= (defined $ARGV[$param + 2])? $ARGV[$param + 2] : '';

	Common::setServicePath($servdir) if($servdir && -d $servdir);
	Common::setUsername($username) if($username);

	if ($taskParam eq 'silent') {
		$AppConfig::callerEnv = 'BACKGROUND';
		$silent = 1;
	}

	unless($silent) {
		my $res = system("$AppConfig::perlBin " . Common::getScript('utility', 1) . " PREINSTDEPENDENCIES");

		if($res) {
			Common::display(['unable_to_complete_pre_update_checks', '. ', 'please_contact_support_for_more_information']);
			exit(1);
		}

		exit(0);
	} else {
		if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
			my $execmd	= Common::getScript('utility') . ' SILENTDEPENDENCYINSTALL';

			my @now		= localtime;
			my $stm		= $now[1] + 1;
			$stm		= 0 if($stm > 59);

			Common::lockCriticalUpdate("cron");
			Common::loadCrontab(1);
			Common::createCrontab($AppConfig::misctask, $AppConfig::miscjob);
			Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, 'cmd', $execmd);
			Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, {'settings' => {'status' => 'enabled'}});
			Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, {'settings' => {'frequency' => ' '}});
			Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, 'm', $stm);
			Common::setCrontab($AppConfig::misctask, $AppConfig::miscjob, 'h', '*');
			Common::saveCrontab();
			Common::unlockCriticalUpdate("cron");

			Common::fileWrite($AppConfig::silinstlock, 1);
			sleep(2) while(-f $AppConfig::silinstlock);

			disableAutoInstallCRON();

			# VERIFY THE DEPENDENCIES
			# my $verifycmd	= $AppConfig::perlBin . ' ' . Common::getScript('utility', 1) . ' VERIFYPREUPDATE';
			# my $res		= system($verifycmd);

			unless(verifyPreUpdate()) {
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

#*************************************************************************************************
# Subroutine		: postUpdateOperation
# Objective			: Check & update EVS/Perl binaries if any latest binary available and logout
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil, Senthil Pandian
#*************************************************************************************************
sub postUpdateOperation {
	# Do not execute post update if no service path is present.
	exit(1) unless(Common::getServicePath());

	my $silent = 0;
	my $taskParam = (defined $ARGV[$param])? $ARGV[$param] : '';

	if ($taskParam eq 'silent') {
		$AppConfig::callerEnv = 'BACKGROUND';
		$silent = 1;
	}

	Common::deleteDeprecatedScripts();

	# Express backup path under online backup is deprecated
	Common::fixPathDeprecations();
	Common::fixBackupsetDeprecations();
	Common::removeDeprecatedDB();
    Common::migrateLocalBackupCronEntry();
	# Create version file post update
	Common::createVersionCache($AppConfig::version);

	Common::addCDPWatcherToCRON(1);
	Common::setCDPInotifySupport();
	Common::stopAuxCDPServices() and Common::startAuxCDPServices();
	Common::startCDPWatcher() unless(Common::isCDPServicesRunning());

	Common::fixDashbdDeprecPath();
	Common::createExcludeInfoFiles();

	Common::loadCrontab(1);
	my $cdpcmd = Common::getCrontab($AppConfig::cdprescan, 'default_backupset', '{cmd}');
	Common::setCDPRescanCRON($AppConfig::defrescanday, $AppConfig::defrescanhr, $AppConfig::defrescanmin, 1) unless($cdpcmd);

	# Common::createRescanRequest();

	# Moved here to download latest binaries before restarting Cron/Dashboard services
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
            Common::traceLog('unable_to_download_python_binary');
            Common::display('unable_to_download_python_binary',1);
            # retreat('unable_to_download_python_binary');
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

	# verify, relink, launch|restart cron
	checkAndStartCRON($taskParam);

	my $cmd = ("$AppConfig::perlBin " . Common::getScript('logout', 1));
	$cmd   .= (" $silent 0 'NOUSERINPUT' 2>/dev/null");
	$cmd = Common::updateLocaleCmd($cmd);
	my $res = `$cmd`;
	print $res;
	Common::traceLog('logout');
	Common::initiateMigrate();
}

#*************************************************************************************************
# Subroutine		: checkAndStartCRON
# Objective			: Start the cron job | Do not move this method to Helpers
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian
#*************************************************************************************************/
sub checkAndStartCRON {
	my $taskParam = $_[0];
	# my $os = Common::getOSBuild();
	if ($AppConfig::appType eq 'IDrive') {
		Common::stopDashboardService($AppConfig::mcUser, Common::getAppPath());
	}

	if($AppConfig::mcUser eq 'root') {
		Common::removeFallBackCRONEntry();
		Common::removeOldFallBackCRONRebootEntry();
		Common::removeFallBackCRONRebootEntry();
		Common::addFallBackCRONRebootEntry();
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

	Common::processCronForManualInstall();

	if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
		my @lockinfo = Common::getCRONLockInfo();
		if($lockinfo[2] and $lockinfo[2] ne $AppConfig::cronSetup) {
			$lockinfo[2] = 'restart';
			$lockinfo[3] = 'update';
			Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
			return 1;
		}
	}

	# if cron link is absent, reinstall the cron | this case can be caused by un-installation from other installation
	Common::display(['cron_service_must_be_restarted_for_this_update']) if ($AppConfig::mcUser ne 'root');
	my $sudoprompt = 'please_provide_' . (Common::hasSudo()? 'sudoers' : 'root') . '_pwd_for_cron';
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
# Subroutine		: cdpWatch
# Objective			: This will launch the CDP servide workers
# Added By			: Sabin Cheruvattil
#*************************************************************************************************
sub cdpWatch {
	$0 = 'IDrive:service-watcher';
	$AppConfig::perlBin = 'perl' unless($AppConfig::perlBin);

	my $prevuser	= Common::getCurrentUsername();
	my $curuser		= '';

	exit(0) unless($prevuser);

	Common::createCDPAndDBPaths();

	my $cdpclientlock	= Common::getCDPLockFile('client');
	my $cdpserverlock	= Common::getCDPLockFile('server');
	my $cdpwatcherlock	= Common::getCDPLockFile('watcher');
	my $locksdir		= dirname($cdpwatcherlock);
	exit(0) if(Common::isFileLocked($cdpwatcherlock));

	# if watcher is starting fresh, remove existing file locks
	unlink($cdpclientlock) if(-f $cdpclientlock);
	unlink($cdpserverlock) if(-f $cdpserverlock);
	unlink($cdpwatcherlock) if(-f $cdpwatcherlock);

	my $lockfh;
	exit(0) unless(open($lockfh, ">", $cdpwatcherlock));
	print $lockfh $$;
	exit(0) unless(flock($lockfh, LOCK_EX|LOCK_NB));

	my $bsf		= Common::getJobsPath('backup', 'file');
	my $lbsf	= Common::getJobsPath('localbackup', 'file');
	my ($dirswatch, $jsjobselems, $jsitems);
	my ($looper, $serverpid, $clientpid) = (1, 0, 0);

	do {
		unless(-f $cdpwatcherlock) {
			`kill -9 $clientpid 2>/dev/null` if($clientpid);
			`kill -9 $serverpid 2>/dev/null` if($serverpid);

			Common::stopAllCDPServices();
			exit(0);
		}

		while(1) {
			exit(0) unless(-f $cdpwatcherlock);

			$curuser	= Common::getCurrentUsername();
			Common::stopAllCDPServices($locksdir) if($curuser ne $prevuser);

			unlink(Common::getCDPHaltFile()) if(-f Common::getCDPHaltFile() and Common::hasFileNotifyPreReq());

			($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
			last if(scalar(@{$dirswatch}));

			sleep(2);
		}

		unless(Common::isCDPAuxServicesRunning()) {
			Common::stopAuxCDPServices() and Common::startAuxCDPServices();
			($serverpid, $clientpid) = (0, 0);
		}

		if(!$serverpid or !$clientpid) {
			$serverpid = -f $cdpserverlock? Common::getFileContents($cdpserverlock) : 0;
			$clientpid = -f $cdpclientlock? Common::getFileContents($cdpclientlock) : 0;
		}

		my ($bkpsetmt, $lbkpsetmt, $newbkpsetmt, $newlbkpsetmt) = (0, 0, 0, 0);
		$bkpsetmt	= stat($bsf)->mtime if(-f $bsf);
		$lbkpsetmt	= stat($lbsf)->mtime if(-f $lbsf);

		while(1) {
			Common::sleepForMilliSec(100);

			# Check service path, watcher lock and scripts path.
			if(!-d Common::getServicePath() or !-d Common::getAppPath() or !-f $cdpwatcherlock) {
				`kill -9 $clientpid 2>/dev/null` if($clientpid);
				`kill -9 $serverpid 2>/dev/null` if($serverpid);

				Common::stopAllCDPServices();
				exit(0);
			}

			$curuser	= Common::getCurrentUsername();
			# if there are no user in user conf / if the user switches to new user we need to stop cdp services
			Common::stopAllCDPServices($locksdir) if($curuser eq '' or $curuser ne $prevuser);

			# Check if edit backup lock is present or not.
			# If present stop cdp client and server and let 'do' stmt handle the situation check terminate conditions here
			# Check the restart conditions also
			$newbkpsetmt	= -f $bsf? stat($bsf)->mtime : 0;
			$newlbkpsetmt	= -f $lbsf? stat($lbsf)->mtime : 0;
			if(!Common::isCDPAuxServicesRunning() or $newbkpsetmt != $bkpsetmt or $newlbkpsetmt != $lbkpsetmt) {
				Common::stopAuxCDPServices();
				last;
			}
		}
	} while($looper);
}

#*************************************************************************************************
# Subroutine		: cdpRescan
# Objective			: Rescans the backup set and updates the database
# Added By			: Sabin Cheruvattil
#*************************************************************************************************
sub cdpRescan {
	$0			= 'IDrive:CDP-Rescan';

	exit(0) if(!defined($ARGV[$param]) || !defined($ARGV[$param + 1]));

	my $stime	= $ARGV[$param + 1];
	my $ctime	= time;
	my $days	= int(($ctime - $stime) / (24 * 60 * 60));

	exit(0) if(($days != 0) && (($days % $ARGV[$param]) != 0));

	my ($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
	if(!@{$dirswatch}) {
		Common::traceLog(['unable_to_place_rescan_request', '. ', 'backupset_is_empty', '.']);
		exit(0);
	}

	Common::traceLog('unable_to_place_rescan_request') unless(Common::createRescanRequest());

	exit(0);
}

#*************************************************************************************************
# Subroutine		: launchDBWriter
# Objective			: Runs DB writer service
# Added By			: Sabin Cheruvattil
#*************************************************************************************************
sub launchDBWriter {
	my $dbwritelock		= Common::getCDPLockFile('dbwritelock');
	my $cdpwatcherlock	= Common::getCDPLockFile('watcher');
	my $cdpclientlock	= Common::getCDPLockFile('client');
	my $cdpserverlock	= Common::getCDPLockFile('server');

	exit(0) if(Common::isFileLocked($dbwritelock));

	my $lockfh;
	exit(0) unless(open($lockfh, ">", $dbwritelock));
	print $lockfh $$;

	exit(0) unless(flock($lockfh, LOCK_EX|LOCK_NB));

	$0 = 'IDrive:DBWriter';

	my @procfiles	= ();
	my $procdata	= undef;
	my $dumpdir		= Common::getCDPDBDumpDir();
	my $failcmtdir	= Common::getFailedCommitDir();
	my $cmtvaultdir	= Common::getCommitVaultDir();
	my $upddbpaths	= Common::getCDPDBPaths();
	
	# create directories if doesn't exists
	Common::createDir($dumpdir, 1) unless(-d $dumpdir);
	Common::createDir($failcmtdir, 1) unless(-d $failcmtdir);
	Common::createDir($cmtvaultdir, 1) unless(-d $cmtvaultdir);

	my $sf;
	my @watchfiles = ();
	my ($looper, $procfile, $dirid, $fname, $bkpstat, $cdpstat)	= (1, '', 0, '', '', 1);
	my ($lmt, $showhidden, $hasprocf, $iscmtretry, $jsonparstat) = (0, 1, 0, 0, 0);
	my ($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
	my $cdpsupport = Common::canKernelSupportInotify();
	
	my ($serverpid, $clientpid);

	for my $windex (0 .. $#{$dirswatch}) {
		push(@watchfiles, $dirswatch->[$windex]) if(defined($dirswatch->[$windex]) && -f $dirswatch->[$windex]);
	}

	do {
		if($cdpsupport) {
			if(!$serverpid || !$clientpid) {
				$serverpid = -f $cdpserverlock? Common::getFileContents($cdpserverlock) : 0;
				$clientpid = -f $cdpclientlock? Common::getFileContents($cdpclientlock) : 0;
			}

			unless(Common::isFileLocked($cdpwatcherlock)) {
				`kill $clientpid 2>/dev/null` if($clientpid);
				`kill $serverpid 2>/dev/null` if($serverpid);
				Common::stopAllCDPServices();
			}
		}

		exit(0) unless(-f $dbwritelock);

		$hasprocf	= 0;
		$procdata	= undef;

		Common::loadUserConfiguration();
		$showhidden	= Common::getUserConfiguration('SHOWHIDDEN');
		Common::loadFullExclude();
		Common::loadPartialExclude();
		Common::loadRegexExclude();

		$cdpstat	= Common::getUserConfiguration('CDP');
		foreach my $opx (keys(%AppConfig::dbdumpregs)) {
			$iscmtretry	= 0;
			@procfiles	= glob(Common::getCatfile(Common::getECatfile($dumpdir), $AppConfig::dbdumpregs{$opx}));
			unless(@procfiles) {
				@procfiles	= glob(Common::getCatfile(Common::getECatfile($failcmtdir), $AppConfig::dbdumpregs{$opx}));
				$iscmtretry = 1;
			}

			next unless(@procfiles);

			$hasprocf = 1;

			for my $fidx (0 .. $#procfiles) {
				$procfile	= $procfiles[$fidx];
				if(!-f $procfile || -s _ <= 0) {
					unlink($procfile) if(-f _);
					next;
				}

				if($opx eq 'cdp' and ($fidx and (($fidx % $AppConfig::cdploadchkct) == 0)) and (Common::getRecentLoadAverage() > 80)) {
					sleep(2);
				}

				if($opx eq 'backup' or $opx eq 'cdp' or $opx eq 'localbackup') {
					# check CDP timeout
					if($opx eq 'cdp') {
						my $psf = stat($procfile);
						if((time() - $psf->mtime) <= $AppConfig::cdpdumptimeout + 1) {
							$hasprocf = 0;
							next;
						}
					}

                    #DB for Express Backed up data
                    if($opx eq 'localbackup') {
                        # $AppConfig::localMountPath = Common::getUserConfiguration('LOCALMOUNTPOINT');
                        # Common::traceLog("localMountPath:".$AppConfig::localMountPath);
                        my $serverRoot = '';
                        $serverRoot = Common::getUserConfiguration('SERVERROOT');
                        # backupExistingDBAndCreateNew($serverRoot);
                        my $databaseLB = Common::getExpressDBPath(Common::getUserConfiguration('LOCALMOUNTPOINT'),$serverRoot);
                        Sqlite::initiateExpressDBoperation($databaseLB);
                        Sqlite::beginExpressDBProcess();
                    }

					my $hascmtfailed = 0;
					foreach my $jbname (keys(%{$upddbpaths})) {
						# If DB is not present, don't create one as we need to perform a scan/rescan
						next unless(-f Common::getCatfile($upddbpaths->{$jbname}, $AppConfig::dbname));
						next unless(-f $procfile);

						my $proctmp = Common::getFileContents($procfile);
						if($opx eq 'cdp') {
							$proctmp	=~ s/^\,//;
							$proctmp	=~ s/\,$//;
							$proctmp	= qq({$proctmp});
						}

						($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
						next unless($jsonparstat);

						my ($dbfstate, $scanfile) = Sqlite::createLBDB($upddbpaths->{$jbname}, 1);
						next unless($dbfstate);
						Sqlite::initiateDBoperation();

						my @procids		= keys(%{$procdata});
						my $bsdbstats	= Sqlite::getBackupsetItemsWithStats();
						# my $rtupd		= 0;
						foreach my $procidx (@procids) {
							next if($procdata->{$procidx}{'JOBNAME'} ne $jbname);

							# Backup operation data processing
							if($opx ne 'cdp') {
								my @jbdata = split(/\|/, $jbname);
								# check for express backup/backup

								next unless($jbdata[0] eq $procdata->{$procidx}{'JOBTYPE'});

                                # utf8::decode($procdata->{$procidx}{'ITEM'}); # accented files fails to commit
								my $commstat;
								if($opx eq 'backup') {
									$commstat	= Sqlite::updateBackUpSuccess($procdata->{$procidx}{'ITEM'}, $procdata->{$procidx}{'CMP_MTIME'});
								} elsif($opx eq 'localbackup') {
									$commstat = Sqlite::updateExpressBackUpSuccess($procdata->{$procidx}{'ITEM'}, $procdata->{$procidx}{'FOLDER_ID'}, $procdata->{$procidx}{'ENC_NAME'});
                                    my $commstat1 = Sqlite::updateExpressDB($procdata->{$procidx}{'ITEM'}, $procdata->{$procidx}{'FOLDER_ID'}, $procdata->{$procidx}{'ENC_NAME'}, $procdata->{$procidx}{'MPC'}, $procdata->{$procidx}{'SIZE'}, $procdata->{$procidx}{'MOD_TIME'});
									# unless($rtupd) {
										# Sqlite::addConfiguration('MPC', $procdata->{$procidx}{'MPC'});
										# $rtupd = 1;
									# }
								}

								unless($commstat) {
									Common::traceLog(['commit_failed', ': ', $procdata->{$procidx}{'ITEM'}]);
									$hascmtfailed = 1;
								}

								next;
							}

							my $decitempath = $procdata->{$procidx}{'ITEM'};
							utf8::decode($decitempath);

							if($procdata->{$procidx}{'OPERATION'} eq 'ADD') {
								# @TODO: Trace debug for tracking swap
								if($decitempath =~ m/.swp$/ || $decitempath =~ m/.swpx$/ || $decitempath =~ m/.swx$/) {
									Common::traceLog("Trace Swap: $decitempath");
									next;
								}

								$fname = "'" . (Common::fileparse($procdata->{$procidx}{'ITEM'}))[0] . "'";
								$dirid = Sqlite::dirExistsInDB($procdata->{$procidx}{'ITEM'}, '/');

								if(-l $decitempath) {
									next;
								} elsif(!-f _) {
									# Handle backup set file rename case & modified | rare case
									# if(grep(/^\Q$procdata->{$procidx}{'ITEM'}\E$/, @watchfiles) && $dirid) {
									if($dirid) {
										Sqlite::deleteIbFile(basename($procdata->{$procidx}{'ITEM'}), $dirid);
										if(exists($bsdbstats->{$procdata->{$procidx}{'ITEM'}}) && $bsdbstats->{$procdata->{$procidx}{'ITEM'}}->stat eq 1) {
											Common::traceLog('Backupset: file renamed.');
											Sqlite::addToBackupSet($procdata->{$procidx}{'ITEM'}, 'u', 0, 0);
											Sqlite::closeDB();
											exit(1);
										}

										# Watching dir renamed | event occurs inside that | gets old file path
										my $wndir		= dirname($procdata->{$procidx}{'ITEM'}) . '/';
										my $decwndir	= dirname($decitempath) . '/';
										my @wpars		= Common::hasParentInSet($wndir, $dirswatch);

										# Check for watching directory rename
										if(!-d $decwndir && (grep(/^\Q$wndir\E$/, @{$dirswatch}) || scalar(@wpars))) {
											# Mark the backup set table item with missing status
											foreach my $wparitem (@wpars) {
												Sqlite::addToBackupSet($wparitem, 'u', 0, 0) if(grep(/^\Q$wparitem\E$/, keys %{$bsdbstats}));
											}

											Sqlite::deleteDirsAndFilesByDirName($wndir);
											Common::traceLog('Backupset: directory renamed.');
											# Common::createRescanRequest(); # we are already removing the dirs and files
											Sqlite::closeDB();
											exit(1);
										}
									}

									next;
								}

								# make sure item is present in backup set | raise around condition | if watched file creates request while scan also in progress
								next if(!grep(/^\Q$procdata->{$procidx}{'ITEM'}\E$/, @{$jsitems->{$jbname}}) && !scalar(Common::hasParentInSet($procdata->{$procidx}{'ITEM'}, $jsitems->{$jbname})));

								$sf = stat($decitempath);
								$dirid = Sqlite::insertDirectories($procdata->{$procidx}{'ITEM'}, '/') unless($dirid);

								$bkpstat = ($sf->size > $AppConfig::cdpmaxsize || !$cdpstat)? $AppConfig::dbfilestats{'MODIFIED'} : $AppConfig::dbfilestats{'CDP'};
								$bkpstat = $AppConfig::dbfilestats{'EXCLUDED'} if(Common::isThisExcludedItemSet($procdata->{$procidx}{'ITEM'} . '/', $showhidden));

                                utf8::decode($fname); #Added by Senthil for Harish_2.3_10_9
								my $commstat = Sqlite::insertIbFile(1, $dirid, $fname, $sf->mtime, $sf->size, $bkpstat);
								$hascmtfailed = 1 unless($commstat);

								my $itemdir		= dirname($procdata->{$procidx}{'ITEM'}) . '/';
								my $bkexitem	= exists($bsdbstats->{$itemdir})? $itemdir : exists($bsdbstats->{$procdata->{$procidx}{'ITEM'}})? $procdata->{$procidx}{'ITEM'} : '';
								utf8::decode($bkexitem);
								Sqlite::addToBackupSet($bkexitem, -d $bkexitem? 'd' : -f $bkexitem? 'f' : 'u', 1, -e $bkexitem? stat($bkexitem)->mtime : 0) if($bkexitem);
							} elsif($procdata->{$procidx}{'OPERATION'} eq 'DELETE') {
								# IN_MOVED_FROM triggers this state added for tracking the same level file which causes delete.
								next if(-e $procdata->{$procidx}{'ITEM'});

								$dirid = Sqlite::getDirID($procdata->{$procidx}{'ITEM'});

								# Check parent directory is present or not.
								if($dirid) {
									Sqlite::addToBackupSet($procdata->{$procidx}{'ITEM'}, 'u', 0, 0) if(exists($bsdbstats->{$procdata->{$procidx}{'ITEM'}}));

									my $itemdir		= dirname($procdata->{$procidx}{'ITEM'}) . '/';
									if(-d $itemdir)  {
										# Same level file deletion changes dir mtime which causes an extra scan which is unnecessary[integrity check]. Avoid it.
										my $bkexitem	= exists($bsdbstats->{$itemdir})? $itemdir : '';
										Sqlite::addToBackupSet($bkexitem, 'd', 1, -e $bkexitem? stat($bkexitem)->mtime : 0) if($bkexitem);
									}

									# check if parent directories are missing
									my $missdir		= '';
									my $wdir		= $procdata->{$procidx}{'ITEM'};
									my $decwndir	= $procdata->{$procidx}{'ITEM'};
									utf8::decode($decwndir);

									while(1) {
										my $parent = dirname($wdir);
										my $decparent = dirname($decwndir);

										if(!-d $decparent) {
											$missdir = $parent . '/';
											Sqlite::addToBackupSet($missdir, 'u', 0, 0) if(grep(/^\Q$missdir\E$/, keys %{$bsdbstats}));
										} elsif(-d _ || $parent eq '/') {
											last;
										}

										$wdir = $parent;
										$decwndir = $decparent;
									}

									if($missdir) {
										Sqlite::deleteDirsAndFilesByDirName($missdir);
									} else {
										my $commstat = Sqlite::deleteIbFile(basename($procdata->{$procidx}{'ITEM'}), $dirid) if($dirid);
										$hascmtfailed = 1 unless($commstat);
									}
								}
							} elsif($procdata->{$procidx}{'OPERATION'} eq 'DIR_DELETE') {
								# if self delete item is dir and it belongs to backup set item level
								Sqlite::addToBackupSet($procdata->{$procidx}{'ITEM'}, 'u', 0, 0) if(exists($bsdbstats->{$procdata->{$procidx}{'ITEM'}}) && Sqlite::isPathDir($procdata->{$procidx}{'ITEM'}));
								Sqlite::deleteDirsAndFilesByDirName($procdata->{$procidx}{'ITEM'});
							} elsif($procdata->{$procidx}{'OPERATION'} eq 'DIR_ADD') {
								my @jbt	= split(/\|/, $procdata->{$procidx}{'JOBNAME'});
								my $iscdp = $jbt[0] eq 'backup'? 1 : 0;
								Common::traceLog("dir add event, trigger scan");
								Common::traceLog($procdata->{$procidx}{'ITEM'});
								Common::createScanRequest($procdata->{$procidx}{'DBPATH'}, $jbt[1], 0, $jbt[0], $iscdp, 0, 1);

								my $cpdircache = Common::getCatfile(Common::getJobsPath($AppConfig::cdp), $AppConfig::cdpcpdircache);
								my $fbct = 0;
								while(1) {
									if(Common::isFileLocked($cpdircache, 0, 1)) {
										Common::sleepForMilliSec(100);
									} else {
										my $fh;
										if(open($fh, ">>", $cpdircache)) {
											if(flock($fh, LOCK_EX|LOCK_NB)) {
												print $fh $procdata->{$procidx}{'ITEM'} . '/' . "\n";
												flock($fh, LOCK_UN);
												close($fh);
												last;
											}
										}

										close($fh) if($fh);
									}

									$fbct++;
									last if($fbct > 10);
								}
							}
						}

						undef $bsdbstats;

						Sqlite::closeDB();
					}

                    if($opx eq 'localbackup') {
                        Sqlite::commitExpressDBProcess();
                        Sqlite::disconnectExpressDB();
                    }

					# Handle commit failures and move the proc files
					handleCommitFailure(!$hascmtfailed, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir);

					unlink($procfile) if(-f $procfile);
				}
				elsif($opx eq 'scan' || $opx eq 'rescan') {
					my ($ongbackup, $onbacktype, $ondemand)	= (0, '', 0);
					my $scpid		= fork();
					if($scpid == 0) {
						my $opstat = 0;
						while(1) {
							$lmt	= stat($procfile)->mtime;

							my $proctmp = Common::getFileContents($procfile);
							($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);

							exit(0) unless($jsonparstat);

							# Check if backup jobs are running or not | if backup running and ondemand flag not set, skip scan
							my @jobnames = ('backup', 'localbackup');
							foreach my $job (@jobnames) {
								my $pidfile	= Common::getCatfile(Common::getJobsPath($job), $AppConfig::pidFile);
								if(Common::isFileLocked($pidfile)) {
									$ongbackup	= 1;
									$onbacktype	= $job;
									last;
								}
							}

							if($opx eq 'scan') {
								$ondemand = $procdata->{'ondemand'};
								if(!$ongbackup || $ondemand) {
                                    utf8::decode($procdata->{'path'}); #Added for Suruchi_2.3_11_9 : Senthil
									Common::traceLog("Starting $procdata->{'type'} set scan");
									$opstat = Common::doBackupSetScanAndUpdateDB($procdata->{'path'}, $procdata->{'type'}, $procdata->{'iscdp'});
									Common::traceLog("Ending $procdata->{'type'} set scan");
									$ongbackup	= 0;
									$ondemand	= 0;
								}
							} elsif(!$ongbackup) {
								Common::traceLog("Starting rescan");
								my $custom = (exists $procdata->{'custom'} and $procdata->{'custom'})? 1 : 0;
								$opstat = Common::doBackupSetReScanAndUpdateDB($procdata->{'rsdata'}, $custom);
								Common::traceLog("Ending rescan");
							}

							if(!$ongbackup && $lmt == stat($procfile)->mtime) {
								unlink($procfile) if($opstat && $opstat != -1);
								# place request for backup set size and file count calculation
								if($opstat && $opstat != -1) {
									if($opx eq 'scan') {
										Common::createJobSetSizeCalcRequest(Common::getCatfile($procdata->{'path'}, $AppConfig::backupsetFile));
									} else {
										foreach my $jbname (keys(%{$procdata->{'rsdata'}})) {
											Common::createJobSetSizeCalcRequest(Common::getCatfile($upddbpaths->{$jbname}, $AppConfig::backupsetFile));
										}
									}
								}

								last;
							}
							
							exit(0) if($ongbackup);
						}

						sleep(2) if(($ongbackup && !$ondemand) || $opstat == -1);

						# Handle commit failures and move the proc files
						handleCommitFailure($opstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir) unless($ongbackup);
						exit(0);
					}

					local $SIG{INT}		= sub {`kill $scpid`; exit(0);};
					local $SIG{TERM}	= sub {`kill $scpid`; exit(0);};
					local $SIG{KILL}	= sub {`kill $scpid`; exit(0);};
					local $SIG{ABRT}	= sub {`kill $scpid`; exit(0);};
					local $SIG{PWR}		= sub {`kill $scpid`; exit(0);};
					local $SIG{QUIT}	= sub {`kill $scpid`; exit(0);};

					waitpid($scpid, 0);
				}
				elsif($opx eq 'jssize') {
					my $proctmp = Common::getFileContents($procfile);
					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					next unless($jsonparstat);

					my $jsfile	= $procdata->{'jsfile'};
					my $filecount = 0;
					my $updjson	= "$jsfile.json";
					my %jsinfo;

					if(!-f $jsfile || -z _) {
						Common::fileWrite($updjson, JSON::to_json(\%jsinfo));
						unlink($procfile);
						next;
					}

					my ($dbfstate, $scanfile) = Sqlite::createLBDB(dirname($jsfile) . '/', 1);
					next unless($dbfstate);

					Sqlite::initiateDBoperation();
					my $jsc = Common::getDecBackupsetContents($jsfile, 'array');
					for my $jscidx (0 .. scalar(@{$jsc})) {
						next unless($jsc->[$jscidx]);

						if(-f $jsc->[$jscidx]) {
							$jsinfo{$jsc->[$jscidx]} = {'size' => Common::getFileSize($jsc->[$jscidx], \$filecount), 'filecount' => (Common::isThisExcludedItemSet($jsc->[$jscidx] . '/', $showhidden)? 'EX' : '1'), 'type' => 'f'};
							$filecount	= 0;
						} elsif(-d _) {
							my $dirattrs	= Sqlite::getDirectorySizeAndCount($jsc->[$jscidx]);
							my $filecount	= Common::isThisExcludedItemSet($jsc->[$jscidx] . '/', $showhidden)? 'EX' : $dirattrs->{'filecount'};
							$jsinfo{$jsc->[$jscidx]} = {'ts' => mktime(localtime), 'size' => $dirattrs->{'size'}, 'filecount' => $filecount, 'type' => 'd'};
							undef $dirattrs;
						} else {
							$jsinfo{$jsc->[$jscidx]} = {'size' => 0, 'filecount' => 'NA', 'type' => 'u'};
						}
					}
					
					Common::fileWrite($updjson, JSON::to_json(\%jsinfo));
					Sqlite::closeDB();
					if(Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
						Common::setNotification(sprintf("get_%sset_content", $procdata->{'jobname'})) and Common::saveNotifications();
						Common::unlockCriticalUpdate("notification");
					}

					unlink($procfile);
				}
				elsif($opx eq 'ex_db_renew') {
					my $commstat = 1;
					my $proctmp = Common::getFileContents($procfile);
					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					next unless($jsonparstat);

					my $extype	= (split(/\./, basename($procfile)))[0];
					$extype		=~ s/ex_db_renew_//;

					foreach my $jt (keys %{$procdata}) {
						foreach my $jb (keys %{$procdata->{$jt}}) {
							next unless(-f Common::getCatfile($procdata->{$jt}{$jb}, $AppConfig::dbname));

							my ($dbfstate, $scanfile) = Sqlite::createLBDB($procdata->{$jt}{$jb} . '/', 1);
							next unless($dbfstate);

							Sqlite::initiateDBoperation();
							$commstat = Sqlite::renewDBUpdateExcludeStat($extype);
							Sqlite::closeDB();

							Common::createJobSetSizeCalcRequest(Common::getCatfile($procdata->{$jt}{$jb}, $AppConfig::backupsetFile));
						}
					}

					handleCommitFailure($commstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir);

					unlink($procfile) if($commstat);
				}
				elsif($opx eq 'idx_del_upd') {
					my $commstat	= 1;
					my $proctmp		= Common::getFileContents($procfile);
					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					next unless($jsonparstat);

					foreach my $jbname (keys(%{$upddbpaths})) {
						next unless(-f Common::getCatfile($upddbpaths->{$jbname}, $AppConfig::dbname));
						my ($dbfstate, $scanfile) = Sqlite::createLBDB($upddbpaths->{$jbname}, 1);
						next unless($dbfstate);

						Sqlite::initiateDBoperation();

						$procdata	= JSON::from_json(Common::getFileContents($procfile));
						my @jbdata	= split(/\|/, $jbname);
						foreach my $procidx (keys(%{$procdata})) {
							next if($procdata->{$procidx}{'JOBNAME'} ne $jbname || $jbdata[0] ne $procdata->{$procidx}{'JOBTYPE'});

							my $tempName = $procdata->{$procidx}{'ITEM'};
							utf8::decode($tempName);

							if($procdata->{$procidx}{'ITEMTYPE'} eq 'F') {
								$commstat = Sqlite::updateCloudFileDelete($procdata->{$procidx}{'ITEM'}) if(-f $procdata->{$procidx}{'ITEM'} or -f $tempName);
							} elsif($procdata->{$procidx}{'ITEMTYPE'} eq 'D') {
								$commstat = Sqlite::updateCloudDirDelete($procdata->{$procidx}{'ITEM'}) if(-d $procdata->{$procidx}{'ITEM'} or -d $tempName);
							}
						}

						Sqlite::closeDB();
					}

					handleCommitFailure($commstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir);

					unlink($procfile) if($commstat);
				}
				elsif($opx eq 'bkpstat_reset') {
					my $commstat = 1;
					my $proctmp		= Common::getFileContents($procfile);
					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					next unless($jsonparstat);

					my $dbfile = Common::getCatfile($procdata->{'path'}, $AppConfig::dbname);
					# Check if DB exists, no need to proceed if DB is not present
					$commstat = Common::resetBackedupStatus($procdata->{'path'}) if(-f $dbfile);

					handleCommitFailure($commstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir);

					unlink($procfile) if($commstat);
				}
				elsif($opx eq 'verify_xpres') {
					my $commstat = 1;
					my $proctmp		= Common::getFileContents($procfile);
					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					next unless($jsonparstat);

					my $dbfile	= Common::getCatfile($procdata->{'path'}, $AppConfig::dbname);
					unless(-f $dbfile) {
						unlink($procfile);
						next;
					}
					
					my $mntpath = $procdata->{'mntpath'};
					if(!-d $mntpath) {
						$commstat = Common::resetBackedupStatus($procdata->{'path'});
						handleCommitFailure($commstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir);

						unlink($procfile) if($commstat);
						next;
					}

					my ($dbfstate, $scanfile) = Sqlite::createLBDB($procdata->{'path'}, 1);
					next unless($dbfstate);

					Sqlite::initiateDBoperation();
					my $filedata;
					my $mpc			= Sqlite::getConfiguration('MPC');

					unless(defined($mpc)) {
						# @TODO: DECIDE | If mpc is not defined, then place a request to update the mpc
						# my $mpcdf = Common::createMPCSelfUpdRequest($procdata->{'path'});
						# next if($mpcdf);
					}

					my $expfiles	= Sqlite::getExpressBackedupFiles();
					my $uexpdir		= Common::getCatfile($mntpath, $AppConfig::xpressdir, Common::getUsername());
					while($filedata = $expfiles->fetchrow_hashref) {
						my $fileid	= (defined($filedata->{'FILEID'}))? $filedata->{'FILEID'} : '';
						my $fdid	= (defined($filedata->{'FOLDER_ID'}))? $filedata->{'FOLDER_ID'} : '';
						my $encname	= (defined($filedata->{'ENC_NAME'}))? $filedata->{'ENC_NAME'} : '';

						if($fileid && (!defined($mpc) || !$encname || !-f Common::getCatfile($uexpdir, $mpc, $fdid, $encname))) {
							Sqlite::updateFileBackupStatus($fileid, $AppConfig::dbfilestats{'NEW'});
						}
					}

					$expfiles->finish() if($filedata);
					Sqlite::closeDB();
					handleCommitFailure($commstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir);

					unlink($procfile) if($commstat);
				}
				elsif($opx eq 'db_cleanp') {
					my $commstat = 1;
					my $proctmp		= Common::getFileContents($procfile);
					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					next unless($jsonparstat);

					my $dbfile	= Common::getCatfile($procdata->{'path'}, $AppConfig::dbname);
					unless(-f $dbfile) {
						unlink($procfile);
						next;
					}

					my ($dbfstate, $scanfile) = Sqlite::createLBDB($procdata->{'path'}, 1);
					next unless($dbfstate);

					Sqlite::initiateDBoperation();
					Sqlite::checkAndResetDB();
					Sqlite::closeDB();

					handleCommitFailure($commstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir);
					unlink($procfile) if($commstat);
				}
				elsif($opx eq 'upd_mpc_self') {
					my $proctmp		= Common::getFileContents($procfile);

					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					unless($jsonparstat) {
						unlink($procfile);
						next;
					}

					my $dbfile	= Common::getCatfile($procdata->{'path'}, $AppConfig::dbname);
					unless(-f $dbfile) {
						unlink($procfile);
						next;
					}

					my ($dbfstate, $scanfile) = Sqlite::createLBDB($procdata->{'path'}, 1);
					unless($dbfstate) {
						unlink($procfile);
						next;
					}

					Sqlite::initiateDBoperation();
					Sqlite::addConfiguration('MPC', Common::getMPC());

					Sqlite::closeDB();
					unlink($procfile) if(-f $procfile);
				}
				elsif($opx eq 'rm_nonex_fl') {
					my $commstat = 1;
					my $proctmp = Common::getFileContents($procfile);
					($jsonparstat, $procdata) = readJSONProcData($proctmp, $procfile, $cmtvaultdir);
					next if(!$jsonparstat);

					my $dbfile	= Common::getCatfile($procdata->{'path'}, $AppConfig::dbname);
					unless(-f $dbfile) {
						unlink($procfile);
						next;
					}

					my ($dbfstate, $scanfile) = Sqlite::createLBDB($procdata->{'path'}, 1);
					next unless($dbfstate);

					Sqlite::initiateDBoperation();

					for my $npmfile (@{$procdata->{'npmsfiles'}}) {
						my $dirid = Sqlite::getDirID($npmfile);
						Sqlite::deleteIbFile(basename($npmfile), $dirid) if($dirid);
					}

					Sqlite::closeDB();

					unlink($procfile) if(-f $procfile);
				}
			}
		}

		sleep(1) unless($hasprocf);
	} while($looper);
}

#*****************************************************************************************************
# Subroutine	: readJSONProcData
# In Param		: proctmp: process data | procfile: file to process | cmtvaultdir: Commit vault
# Out Param		: Mixed | (status, data)
# Objective		: Reads the input and processes the input
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub readJSONProcData {
	my ($proctmp, $procfile, $cmtvaultdir, $procdata, $status) = ($_[0], $_[1], $_[2], undef, 0);
	# EVAL is required as there can be file corruption.
	eval {
		$procdata	= JSON::from_json($proctmp);
		$status		= 1;
		1;
	} or do {
		$procdata	= {};
	};

	if($@) {
		# Corruption may happen as high speed transactions can happen.
		# Expected partial JSON may not come in this case.
		Common::traceLog(['corrupted request file', ': ', $procfile]);
		move($procfile, $cmtvaultdir);
	}

	return ($status, $procdata);
}

#*****************************************************************************************************
# Subroutine	: handleCommitFailure
# In Param		: commit status, is retry, $process file, failed commit dir, commit vault dir
# Out Param		: Status | Boolean
# Objective		: Places a request for express backup verification
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub handleCommitFailure {
	return 0 if(!defined($_[0]) || !defined($_[1]) || !defined($_[2]) || !defined($_[3]) || !defined($_[4]));

	my ($commstat, $iscmtretry, $procfile, $failcmtdir, $cmtvaultdir) = ($_[0], $_[1], $_[2], $_[3], $_[4]);

	return 1 if($commstat);

	if($iscmtretry) {
		Common::traceLog(['commit_retry_failed', '. ', 'moving_to_commit_vault', ': ', $procfile]);
		move($procfile, $cmtvaultdir) if(-f $procfile);
		
		return 1;
	}

	Common::traceLog(['commit_failed', '. ', 'moving_to_failed_commit', ': ', $procfile]);
	move($procfile, $failcmtdir) if(-f $procfile);

	return 1;
}

#*****************************************************************************************************
# Subroutine	: displayCRONRebootCMD
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Displays cron restart fall back handler
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub displayCRONRebootCMD {
	my $croncmd = Common::getFallBackCRONRebootEntry();
	Common::display(["\n", $croncmd, "\n"]);
	exit(0);
}

#*****************************************************************************************************
# Subroutine : updateFileset
# In Param   : (Job-Type) | (string)
# Out Param  : (Status) | (boolean)
# Objective  : Update backup/local-backup/restore set files.
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub updateFileset {
	my $bsf = Common::getJobsPath($_[0], 'file');

	if (($_[0] =~ /backup/) and -f $bsf) {
		my $oldbkpsetfile = qq($bsf$AppConfig::backupextn);
		Common::copy($bsf, $oldbkpsetfile);
	}

	my %backupSet;
	if (-f "$bsf.data") {
		my %backupSet2 = %{JSON::from_json(Common::getFileContents("$bsf.data"))};
		foreach my $key (keys %backupSet2) {
			my $key2 = $key;
			if (utf8::is_utf8($key2)) {
				utf8::encode($key2);
			}
			$backupSet{$key2} = $backupSet2{$key};
		}
		unlink("$bsf.data");
	}
	else {
		%backupSet = ();
	}

	Common::processAndSaveJobsetContents(\%backupSet, $_[0], $bsf, 1);

	if ($_[0] =~ /backup/) {
		my $jbpath = Common::getJobsPath($_[0]);
		Common::createScanRequest($jbpath, Common::basename($jbpath), 0, $_[0], 0, 0);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine : recalFileset
# In Param   : (Job-Type) | string
# Out Param  : (Status) | (boolean)
# Objective  : Re-verify backup/local-backup set file details.
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub recalFileset {
	Common::createJSSizeCalcReqByJobType($_[0]);
	return 1
}

#*****************************************************************************************************
# Subroutine : getLogs
# In Param   : None
# Out Param  : (logs) | (jsonstring)
# Objective  : All type of logs
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub getLogs {
	my %data = ();
	my @d = ();
	my $l = ();
	my ($startDate, $endDate) = Common::getStartAndEndEpochTime(7);

	foreach my $job (keys %AppConfig::availableJobsSchema) {
		$l = Common::selectLogsBetween(undef,
		 	$startDate,
			$endDate,
			(Common::getJobsPath($job) . "/$AppConfig::logStatFile"));
		push(@d, (map{{
					optype   => $job,
					datetime => $l->FETCH($_)->{'datetime'} =~ s/\//-/gr,
					duration => Common::convert_seconds_to_hhmmss($l->FETCH($_)->{'duration'}),
					status   => (split('_', $l->FETCH($_)->{'status'}))[0],
					files    => $l->FETCH($_)->{'filescount'},
					bkpfiles => $l->FETCH($_)->{'bkpfiles'},
					type     => $AppConfig::availableJobsSchema{$job}{'op'}{lc((split('_', $l->FETCH($_)->{'status'}))[1])},
					size     => $l->FETCH($_)->{'size'},
					filename => ("$_\_" . $l->FETCH($_)->{'status'}),
					lpath    => ("$_\_" . $l->FETCH($_)->{'status'}),
					mpc      => $l->FETCH($_)->{'mpc'}
				}} $l->Keys));
	}

	print(JSON::to_json(\@d));
}

#*****************************************************************************************************
# Subroutine : getprogressdetails
# In Param   : (Job-Type) | (string)
# Out Param  : (progress details) | (jsonstring)
# Objective  : Get the given jobtype's progress details
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub getprogressdetails {
# TODO: NEW
#-	my $progressDetailsFile = getCatfile(Common::getJobsPath($_[0]), $AppConfig::progressDetailsFilePath);
#-	my $pidFile = getCatfile(Common::getJobsPath($_[0]), 'pid.txt');
#-	if (!Common::isFileLocked($pidFile, undef, 1) and ($_[1]->[1] eq 'Running')) {
#-		if (-f getCatfile(Common::getJobsPath($_[0]), $AppConfig::logPidFile)) {
#-			Common::checkAndRenameFileWithStatus(Common::getJobsPath($_[0]), $_[0]) if (-f $pidFile);
#-			return {};
#-		}
#-
#-		loadNotifications() and setNotification(sprintf("update_%s_progress", $_[0]), "$_[1]->[0]_Aborted_$_[1]->[2]") and saveNotifications();
#-		unlink($pidFile) if (-f $pidFile);
#-
#-		return {};
#-	}
# TODO: NEW-end

	my $progressDetailsFile = Common::getCatfile(Common::getJobsPath($_[0]), $AppConfig::progressDetailsFilePath);
	my @progressData = Common::getProgressDetails($progressDetailsFile);
	print(JSON::to_json(\@progressData));
}

#*****************************************************************************************************
# Subroutine : updateJobStatus
# In Param   : Job-Type
# Out Param  : None
# Objective  : Update job operation status if failed to exit
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub updateJobStatus {
	Common::checkAndRenameFileWithStatus(Common::getJobsPath($_[0]), $_[0]);
}

#*****************************************************************************************************
# Subroutine : deleteLog
# In Param   : (jobtype, log-filename) | (string, string)
# Out Param  : (Status) | (boolean)
# Objective  : Delete given log file
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub deleteLog {
	my @filename = split('_', $_[1]);
	Common::deleteLog($_[0], $filename[0], ("$filename[1]_$filename[2]"));

	return 1;
}

#*****************************************************************************************************
# Subroutine : renameBackupLocation
# In Param   : (Nickname) | (string)
# Out Param  : (SUCCESS/FAILURE) | (string)
# Objective  : Rename backup location
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub renameBackupLocation {
	my @bl = split('#', Common::getUserConfiguration('BACKUPLOCATION'));
	$bl[0] = substr($bl[0], 4);
	$bl[0] = substr($bl[0], 0, -4);

	my %deviceDetails = ('device_id' => $bl[0]);
	unless (Common::renameDevice(\%deviceDetails, $_[0])) {
		print("FAILURE")
	}
	else {
		print("SUCCESS")
	}
}

#*****************************************************************************************************
# Subroutine : getLocalDrives
# In Param   : None
# Out Param  : (Local Drives) | (jsonstring)
# Objective  : Get local drives
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub getLocalDrives {
	my @files = ();
	foreach my $filename (keys %{Common::getMountPoints('Writeable')}) {
		push(@files, {
			type => 'folder',
			path => $filename
		});
	}
	print(JSON::to_json(\@files));
}

#*****************************************************************************************************
# Subroutine : deleteDashboard
# In Param   : None
# Out Param  : None
# Objective  : Delete dashbord for this computer
# Added By   : Yogesh Kumar
#*****************************************************************************************************
sub deleteDashboard {
	Common::deleteBackupDevice(1);
}

#*****************************************************************************************************
# Subroutine : getLog
# In Param   : (Jobtype, log filename) | (string, string)
# Out Param  : (log content) | (json string)
# Objective  : Get log summary
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub getLogDetails {
	my %logData = ();
	my $jbtype	= ($_[0] eq $AppConfig::cdpfn)? $AppConfig::cdp : $_[0];
	my $logFile = Common::getCatfile(Common::getJobsPath($jbtype, 'logs'), $_[1]);
	my $numberOfLines = "head -n20";
	if ($_[0] eq $AppConfig::cdp) {
		$numberOfLines = "tail -n100";
	}

	if (-f $logFile) {
		my $logContentCmd = Common::updateLocaleCmd("tail -n30 '$logFile'");
		my @logContent = `$logContentCmd`;

		my $copyFileLists = 0;
		my $copySummary   = 0;

		$logData{'status'} = AppConfig::SUCCESS;

		foreach (@logContent) {
			if (!$copySummary and substr($_, 0, 9) eq '[SUMMARY]') {
				$copySummary = 1;
			}
			elsif (!$copyFileLists and substr($_, 0, 1) eq '[') {
				$copyFileLists = 1;
			}

			if ($copySummary) {
				if ($_ =~ /^---------/) {
					next;
				}
				if ($_ =~ m/^Backup End Time/) {
					my @startTime = localtime((split('_', $_[1]))[0]);
					my $et = localtime(mktime(@startTime));
					$logData{'summary'} .= sprintf("Backup Start Time: %s\n", $et);
				}
				elsif ($_ =~ m/Restore End Time/) {
					my @startTime = localtime((split('_', $_[1]))[0]);
					my $et = localtime(mktime(@startTime));
					$logData{'summary'} .= sprintf("Restore Start Time: %s\n", $et);
				}
				elsif ($_ =~ m/End Time/) {
					my @startTime = localtime((split('_', $_[1]))[0]);
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

		my $logheadCmd = Common::updateLocaleCmd("$numberOfLines '$logFile'");
		my @loghead = `$logheadCmd`;
		# $logData{'details'}	= Common::getLocaleString('version_cc_label') . $AppConfig::version . "\n";
		# $logData{'details'} .= Common::getLocaleString('release_date_cc_label') . $AppConfig::releasedate . "\n";
		foreach(@loghead) {
			last if (substr($_, 0, 9) eq '[SUMMARY]');
			$logData{'details'} .= $_;
		}
	}

	print(JSON::to_json(\%logData));
}

#*****************************************************************************************************
# Subroutine : saveCDPSettings
# In Param   : (CDP frequency) | (int)
# Out Param  : (Status) | (boolean)
# Objective  : Update CDP settings
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub saveCDPSettings {
	if ($_[0]) {
		Common::setDefaultCDPJob(sprintf("%02d", $_[0]), $_[0], 0);
	}
	else {
		Common::setDefaultCDPJob(sprintf("%02d", 1), $_[0], 0);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine : verifyBackupset
# In Param   : (status, time) | (string, hh::mm::ss)
# Out Param  : (Status) | (boolean)
# Objective  : Update CDP settings
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub verifyBackupset {
	if ($_[0] ne Common::getUserConfiguration('RESCANINTVL')) {
		my @rsint = split(/\:/, $_[0]);
		Common::setCDPRescanCRON(sprintf("%02d", $rsint[0]), sprintf("%02d", $rsint[1]), sprintf("%02d", $rsint[2]), 0);
	}

	if ($_[1]) {
		my $errmsg = '';
		my $bsf = Common::getJobsPath('backup', 'file');
		if (!-f $bsf or -z $bsf) {
			# $errmsg = 'backupset_is_empty';
		}
		elsif (!Common::isCDPWatcherRunning()) {
			# $errmsg = 'database_service_not_running';
		}
		else {
			Common::createRescanRequest();
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine : recalculateBackupsetSize
# In Param   : (-) | (-)
# Out Param  : (status) | (boolean)
# Objective  : Recalculate online/local backupsets
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub recalculateBackupsetSize {
	Common::removeBKPSetSizeCache('backup');
	Common::removeBKPSetSizeCache('localbackup');
	Common::createJobSetExclDBRevRequest('all');

	return 1;
}

#*****************************************************************************************************
# Subroutine			: startReIndexOperation
# Objective				: This method is used to start re-index the database for local backup/restore
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub startReIndexOperation {
	$AppConfig::displayHeader  = 0; #To prevent header display on retreat
	my $dedup		    = Common::getUserConfiguration('DEDUP');
	my $username		= Common::getUsername();
	my $jobRunningDir   = Common::getUsersInternalDirPath('dbreindex');

	my $pidPath 		= $jobRunningDir."/".$AppConfig::pidFile;

	my $mountedPath;
	if(defined($ARGV[$param+1])) {
		$mountedPath     = $ARGV[$param+1];
		$AppConfig::callerEnv = 'BACKGROUND';
	} else {
		$mountedPath     = Common::getMountedPathForRestore();
	}

	$AppConfig::localMountPath	= $mountedPath;
	Common::createDir($jobRunningDir, 1);
	if (Common::isFileLocked($pidPath)) {
		Common::retreat('reindex_is_inprogress');
	}
    my $lockStatus = Common::fileLock($pidPath);
    Common::retreat([$lockStatus.'_file_lock_status', ": ", $pidPath]) if($lockStatus);

	my $expressLocalDir = Common::getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   = Common::getCatfile($expressLocalDir, $username);
	$AppConfig::expressLocalDir = $expressLocalDir;
	my @backupLocationDir = Common::getUserBackupDirListFromMountPath($localUserPath);
	unless(scalar(@backupLocationDir)>0) {
		return 0;
	}
	Common::checkAndCreateDBpathXMLfile($localUserPath, \@backupLocationDir) if($dedup eq 'on');
	backupExistingDBAndCreateNew() if($dedup eq 'off');

	foreach my $backupLocation (@backupLocationDir) {
		backupExistingDBAndCreateNew($backupLocation) if($dedup eq 'on');
Common::traceLog("reIndexDBOperation started for '$backupLocation'");
		reIndexDBOperation($localUserPath.'/'.$backupLocation,$backupLocation);
Common::traceLog("reIndexDBOperation completed for '$backupLocation'"); 
		if($dedup eq 'on') {
            Sqlite::createExpressTableIndexes();
            Sqlite::disconnectExpressDB();
        }       
	}

	unlink($pidPath);
    if($dedup eq 'off') {
        Sqlite::createExpressTableIndexes();
        Sqlite::disconnectExpressDB();
    }
    return 1;
}

#*****************************************************************************************************
# Subroutine			: reIndexDBOperation
# Objective				: This method is used to insert/update data into database
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub reIndexDBOperation {
	my ($buffer, $lastLine, $errStr, $errMsg) = ('') x 4;
	my $skipFlag 	    = 0;
	my $jobRunningDir   = Common::getUsersInternalDirPath('dbreindex');
	my $reIndexUTFpath  = $jobRunningDir.'/'.$AppConfig::utf8File;
	my $pidPath 		= $jobRunningDir."/".$AppConfig::pidFile;
	my $idevsOutputFile	= $jobRunningDir."/".$AppConfig::evsOutputFile;
	my $idevsErrorFile 	= $jobRunningDir."/".$AppConfig::evsErrorFile;
	my $dedup		    = Common::getUserConfiguration('DEDUP');
	my $backupDirLoc    = $_[0];
	my $backupLocation  = $_[1];
    
	my $reIndexPid = fork();
	if(!defined $reIndexPid) {
		Common::traceLog(['cannot_fork_child', "\n"]);
		return 0;
	}

	if($reIndexPid == 0) {
        Common::createUTF8File(['DBREINDEX',$reIndexUTFpath],
                    $idevsOutputFile,
                    $idevsErrorFile,
                    $backupDirLoc
                    ) or Common::retreat('failed_to_create_utf8_file');
        my @responseData = Common::runEVS('item',1);
        Common::traceLog('ReIndex EVS completed');
        exit;
    }

	while(1) {
		if((-e $idevsOutputFile and -s $idevsOutputFile) or  (-e $idevsErrorFile and -s $idevsErrorFile)) {
			last;
		}
		sleep(2);
		next;
	}
	if(-s $idevsOutputFile == 0 and -s $idevsErrorFile > 0) {
		$errStr = Common::checkExitError($idevsErrorFile,'dbreindex');
		if($errStr and $errStr =~ /1-/) {
			$errStr =~ s/1-//;
			$errMsg = $errStr;
		}
		return 0;
	}

	open my $OUTFH, "<", $idevsOutputFile or ($errStr = Common::getStringConstant('failed_to_open_file').": $idevsOutputFile, Reason: $!");
	if($errStr) {
		Common::traceLog($errStr);		
		return 0;
	}

	if (substr($backupLocation, 0, 1) ne "/") {
		$backupLocation = "/".$backupLocation;
	}

    Sqlite::beginExpressDBProcess();

	while(1) {
		my $byteRead = read($OUTFH, $buffer, $AppConfig::bufferLimit);
		if($byteRead == 0) {
			if(!-e $pidPath or (-e $idevsErrorFile and -s $idevsErrorFile)) {
				last;
			}
			sleep(2);
			seek($OUTFH, 0, 1);		#to clear eof flag
			next;
		}

		if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
			$buffer = $lastLine . $buffer;
		}
		my @resultList = split(/\n/, $buffer);
		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}

		foreach my $tmpLine (@resultList) {
			#print "tmpLine:$tmpLine#\n";
			if($tmpLine =~ /<item/) {
				my %fileName = Common::parseXMLOutput(\$tmpLine);
				next if(scalar(keys %fileName) < 7);

				my $itemName 		= $fileName{'fname'};
				my $fieldMPC 		= $fileName{'mpc'};
				my $modtime  		= $fileName{'mod_time'};
				my $fieldSize 		= $fileName{'size'};
				my $fieldFolderId 	= $fileName{'folder_id'};
				my $fieldEncName  	= $fileName{'enc_name'};
				# $itemName = $remoteFolder.$itemName unless($itemName =~/\//);
				Common::replaceXMLcharacters(\$itemName);
				#print "itemName:$backupLocation$itemName#\n";				
				#$fieldMPC = $backupLocation.$fieldMPC;
				$fieldMPC = $backupLocation;
				$modtime = Common::convert_to_unixtimestamp($modtime);
				my $dirID = Sqlite::checkFolderExistenceInExpressDB($itemName, $fieldMPC);
				if(!$dirID){
					$dirID = Sqlite::insertExpressFolders($fieldMPC.$itemName, $modtime);
				}
				my $fileName = (Common::fileparse($itemName))[0];
				$fileName = "'$fileName'";
				Sqlite::insertExpressIbFile(1, "$dirID","$fileName","$modtime","$fieldSize",'NA','NA','Default Backupset','0',"$fieldFolderId","$fieldMPC","$fieldEncName", '1', '1');
			}
			elsif($tmpLine ne '') {
				if($tmpLine =~ m/(End of database)/) {
                    Common::traceLog("ReIndex:".$tmpLine);
					$skipFlag = 1;
				} elsif($tmpLine !~ m/(connection established|receiving file list)/) {
					Common::traceLog("ReIndex:".$tmpLine);
				}
			}
		}
		if($skipFlag) {
			last;
		}
	}
	close($OUTFH);

    Sqlite::commitExpressDBProcess();

	if(-s $idevsErrorFile > 0) {
		my $errStr = Common::checkExitError($idevsErrorFile,'dbreindex');
		if($errStr and $errStr =~ /1-/){
			$errStr =~ s/1-//;
			$errMsg = $errStr;
		}
	}
	unlink($idevsOutputFile);
	unlink($idevsErrorFile);
	unlink($reIndexUTFpath);
	#print "Finished\n";
}

#*****************************************************************************************************
# Subroutine			: backupExistingDBAndCreateNew
# Objective				: This method is used to insert/update data into database
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub backupExistingDBAndCreateNew {
	my $serverRoot = (defined($_[0]) and $_[0] ne '')?$_[0]:'';
	my $databaseLB = Common::getExpressDBPath($AppConfig::localMountPath,$serverRoot);
	if(-e $databaseLB) {
		#Backup existing database
		system("mv '$databaseLB' '$databaseLB'"."_bak");
	}
	# print "\n\n databaseLB:$databaseLB \n\n";
	# Sqlite::createLBDB();
	Sqlite::initiateExpressDBoperation($databaseLB);
}

#*****************************************************************************************************
# Subroutine : getLocalBackupSize
# In Param   : None
# Out Param  : Bytes (INT)
# Objective  : Get local backup size
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub getLocalBackupSize {
	print(Common::getLocalStorageUsed());
}

#*****************************************************************************************************
# Subroutine : getLocalRestoreFiles
# In Param   : None
# Out Param  : files | jsonstring
# Objective  : Get local restore file list
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub getLocalRestoreFiles {
	my @fileList = Common::getLocalRestoreItems($_[0], $_[1], ["SIZE", "LMD"], 1);
	if ($fileList[0]) {
		print(JSON::to_json($fileList[1]));
	}
	else {
		print(JSON::to_json([]));
	}
}
