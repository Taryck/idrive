#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to check update is available or not and manual update
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Strings;
use Configuration;
use File::Basename;
use File::Copy qw(copy);
use Scalar::Util qw(reftype);

my $forceUpdate = 0;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	Helpers::loadAppPath();
	Helpers::loadServicePath();
	Helpers::loadUsername();
	Helpers::loadUserConfiguration();

	my ($packageName, $updateAvailable, $taskParam) =  ('', 0, $ARGV[0]);
	$taskParam = '' if(!defined($taskParam));

	if($taskParam =~ /.zip$/i or $taskParam eq ''){
		system('clear');
		Helpers::displayHeader();
		checkAndCreateServiceDirectory();
	}
	Helpers::findDependencies(0) or Helpers::retreat('failed');

	if($taskParam =~ /.zip$/i) {
		preUpdate('');
		$packageName		= $taskParam;
		deleteVersionInfoFile();
		cleanupUpdate('INIT');

		cleanupUpdate($Locale::strings{'file_not_found'} . ': ' . $packageName) if(!-e $packageName);
		$packageName	= qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		copy $taskParam, $packageName;
	} elsif($taskParam eq "checkUpdate") {
		$updateAvailable 	= checkForUpdate();
		updateVersionInfoFile()	if($updateAvailable);
		exit(0);
	} elsif($taskParam eq 'silent') {
		$Configuration::callerEnv = 'BACKGROUND';
		checkAndCreateServiceDirectory();
		preUpdate($taskParam);
		$packageName 		= qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		deleteVersionInfoFile();
		cleanupUpdate('INIT');
	} elsif($taskParam eq '') {
		preUpdate($taskParam);
		Helpers::askProxyDetails() or Helpers::retreat('failed') unless(Helpers::getUserConfiguration('PROXYIP'));
		Helpers::display(["\n",'checking_for_updates', '...']);

		$packageName 		= qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		$updateAvailable 	= checkForUpdate();

		if(!$updateAvailable and !$forceUpdate) {
			my $updateLock = Helpers::getCatfile(Helpers::getServicePath(), $Configuration::pidFile);
			unlink($updateLock) if(-f $updateLock);
			Helpers::retreat([$Configuration::appType, ' ', 'is_upto_date']);
		}

		deleteVersionInfoFile();
		cleanupUpdate('INIT');
		Helpers::display(['new_updates_available_want_update']);
		cleanupUpdate('') if(Helpers::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
		Helpers::display(['updating_scripts_wait', '...']);
	} else{
		Helpers::retreat(['invalid_parameter', ': ', $taskParam, '. ', 'please_try_again', '.']);
	}

	if($taskParam !~ /.zip$/i) {
		# In case param is not zip then need to download the package to update the scripts
		cleanupUpdate($Locale::strings{'update_failed_to_download'}) if(!Helpers::download($Configuration::appDownloadURL, qq(/$Configuration::tmpPath)));
		cleanupUpdate($Locale::strings{'update_failed_to_download'}) if(!-e qq($packageName));
	}

	# install updates
	installUpdates($packageName, $taskParam);

	# Enable in Future
	deleteDeprecatedScripts();

	Helpers::display(['scripts_updated_successfully']) unless($taskParam eq 'silent');

	# verify, relink, launch|restart cron
	checkAndStartCRON($taskParam);
	postUpdate($taskParam);
	displayReleaseNotes() unless($taskParam eq 'silent');
	cleanupUpdate('');
}

#*************************************************************************************************
# Subroutine		: checkAndStartCRON
# Objective			: Start the cron job
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub checkAndStartCRON {
	my $taskParam = $_[0];
	if($taskParam eq 'silent') {
		if(Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
			my @lockinfo = Helpers::getCRONLockInfo();
			$lockinfo[2] = 'restart';
			Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
		}
		Helpers::stopDashboardService($Configuration::mcUser, Helpers::getAppPath());
	} else {
		# if cron link is absent, reinstall the cron | this case can be caused by un-installation from other installation
		Helpers::display(['cron_service_must_be_restarted_for_this_update']) if($Configuration::mcUser ne 'root');
		my $sudoprompt = 'please_provide_' . ((Helpers::isUbuntu() || Helpers::isGentoo())? 'sudoers' : 'root') . '_pwd_for_cron';
		my $sudosucmd = Helpers::getSudoSuCRONPerlCMD('restartidriveservices', $sudoprompt);
		unless(system($sudosucmd) == 0) {
			if(Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
				my @lockinfo = Helpers::getCRONLockInfo();
				$lockinfo[2] = 'restart';
				Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
			} else {
				Helpers::display('failed_to_restart_idrive_services');
			}
		} else {
			Helpers::display(['cron_service_has_been_restarted']);
		}
	}

	return 1;
}

#*************************************************************************************************
# Subroutine		: manageCRONService
# Objective			: Check the cron job running status, relinks | restart the cron
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
# sub manageCRONService {
	# Helpers::display(["\n", 'restart_cron_service', '. ']);
	# Helpers::restartIDriveCRON();
	# return 1;
# }

#*************************************************************************************************
# Subroutine		: displayReleaseNotes
# Objective			: display release notes
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub displayReleaseNotes {
	my $readMePath = Helpers::getAppPath() . qq(/$Configuration::idriveScripts{'readme'});
	if(`which tail 2>/dev/null`) {
		my @lastVersion = `tail -50 '$readMePath' | grep "Build"`;
		my $lastVersion = $lastVersion[scalar(@lastVersion) - 1];
		Helpers::Chomp(\$lastVersion);
		Helpers::display(["\n", 'release_notes', ':', "\n", '=' x 15]);
		Helpers::display([`cat '$readMePath' | grep -A50 "$lastVersion"`]);
		return 1;
	}

	my @features = `tac '$readMePath' | grep -m1 -B50 "Build"`;
	@features = reverse(@features);
	Helpers::display(['release_notes', ':', "\n", '=' x 15, "\n", (join "\n", @features)]);
	return 2;
}

#*************************************************************************************************
# Subroutine		: installUpdates
# Objective			: install downloaded update package
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian
#*************************************************************************************************/
sub installUpdates {
	my $packageName 	= $_[0];
	#my $taskParam 		= 'silent';
	my $taskParam 		= $_[1];
	my $zipLogFile		= Helpers::getAppPath() . qq(/$Configuration::unzipLog);
	my $tempDir 		= qq(/$Configuration::tmpPath);
	`unzip -o '$packageName' -d '$tempDir' 2>'$zipLogFile'`;

	my $scriptBackupDir	= qq(/$Configuration::tmpPath/$Configuration::appType) . q(_backup);
	Helpers::createDir($scriptBackupDir);
	chmod $Configuration::filePermission, $scriptBackupDir;

	cleanupUpdate($Locale::strings{'update_failed_unable_to_unzip'}) if -s $zipLogFile;

	my $packageDir 	= qq(/$Configuration::tmpPath/$Configuration::appPackageName/scripts);
	my $constantsFilePath = $packageDir.qq(/$Configuration::idriveScripts{'constants'});
	my $lineFeed = "\n";
	if(!-e $constantsFilePath){
		my $errMsg = $lineFeed.$Locale::strings{'invalid_zip_file'}.$lineFeed.$Configuration::appDownloadURL.$lineFeed.$lineFeed;
		cleanupUpdate($errMsg);
	}

	my $downloadedVersion = `cat '$constantsFilePath' | grep -m1 "ScriptBuildVersion => '"`;
	$downloadedVersion = (split(/'/, $downloadedVersion))[1];
	Helpers::Chomp(\$downloadedVersion);

	my $isLatest = 1;
	$isLatest = 0 unless(Helpers::versioncompare($Configuration::version, $downloadedVersion) == 2);

	if($isLatest == 0) {
		if(defined($ARGV[0])) {
			Helpers::display(["\n", $Locale::strings{'zipped_package_not_latest'}]) unless($taskParam eq 'silent');
		} else {
			Helpers::display(["\n", $Locale::strings{'available_scripts_version_is_lower_than_current_scripts_version'}]) unless($taskParam eq 'silent');
		}

		unless($taskParam eq 'silent') {
			my $updateChoice = Helpers::getAndValidate('enter_your_choice','YN_choice', 1);
			if($updateChoice eq "n" || $updateChoice eq "N" ) {
				cleanupUpdate("");
			}
		}
	}

	my @scriptNames;
	@scriptNames		= (@scriptNames, map{$Configuration::idriveScripts{$_}} keys %Configuration::idriveScripts);

	# Take a backup
	my $moveRes 		= moveScripts(Helpers::getAppPath(), $scriptBackupDir, \@scriptNames);
	if(!$moveRes) {
		# Backup creation failed. Trying to revert the scripts to current location
		$moveRes = moveScripts($scriptBackupDir, Helpers::getAppPath(), \@scriptNames);
		unlink(Helpers::getAppPath() . qq(/$Configuration::updateLog)) if($moveRes);
		cleanupUpdate($Locale::strings{'failed_to_update'} . '.');
	}

	unlink(Helpers::getAppPath() . qq(/$Configuration::updateLog));

	# Move latest scripts to actual script folder
	cleanupUpdate($Locale::strings{'failed_to_update'} . '.') if(!moveUpdatedScripts(\@scriptNames));

	# clear freshInstall file
	unlink(Helpers::getAppPath() . qq(/$Configuration::freshInstall));
}

#*************************************************************************************************
# Subroutine		: moveUpdatedScripts
# Objective			: Move updated scripts to the user working folder
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub moveUpdatedScripts {
	my $packageDir 	= qq(/$Configuration::tmpPath/$Configuration::appPackageName/scripts);
	my $sourceDir 	= Helpers::getAppPath();
	my @scripts;

	opendir(my $dh, $packageDir);
	foreach my $script (readdir($dh)) {
		push @scripts, $script if($script ne '.' && $script ne '..');
	}

	closedir $dh;

	my $moveRes = moveScripts($packageDir, $sourceDir, \@scripts);
	if(!$moveRes) {
		my $scriptBackupDir	= qq(/$Configuration::tmpPath/$Configuration::appType) . q(_backup);
		my $moveBackRes = moveScripts($scriptBackupDir, $sourceDir, $_[0]);
		cleanupUpdate(qq($Locale::strings{'failed_to_update'}. $Locale::strings{'please_cp_perl_from'} $scriptBackupDir to $sourceDir)) if(!$moveBackRes);
	}

	`chmod $Configuration::filePermissionStr '$sourceDir'`;
	`chmod $Configuration::filePermissionStr '$sourceDir/'*`;

	# moveBackRes will show the scprit backup revert failure.
	# we need to handle the display of update status as well.
	# If revert back failed, it would've exit in if(!$moveBackRes) condition itself

	return $moveRes;
}

#*************************************************************************************************
# Subroutine		: moveScripts
# Objective			: Helps tp move files between 2 directories
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub moveScripts {
	my ($src, $dest, $scripts) = ($_[0], $_[1], $_[2]);
	my $moveResult		= '';

	return 0 if($dest eq '' || $src eq '' || !-e $dest || !-e $src || reftype($scripts) ne 'ARRAY' || scalar @{$scripts} == 0);

	open(UPDATELOG, '>>', Helpers::getAppPath() . qq(/$Configuration::updateLog)) or
		Helpers::retreat([$Locale::strings{'unable_to_open_file'}, ': ', $!]);
	chmod $Configuration::filePermission, Helpers::getAppPath() . qq(/$Configuration::updateLog);

	foreach(@{$scripts}) {
		my $fileToTransfer = qq($src/$_);
		if(-e $fileToTransfer) {
			#$moveResult = `mv '$fileToTransfer' '$dest'`; #Commented by Senthil: 10-Aug-2018
			$moveResult = `cp -rf '$fileToTransfer' '$dest'`;
			print UPDATELOG qq(\n$Locale::strings{'move_file'}:: $fileToTransfer >> $dest :: $moveResult\n);
		}

		last if($moveResult ne '');
	}

	Helpers::traceLog($moveResult);
	close UPDATELOG;
	return ($moveResult ne '')? 0 : 1;
}

#*************************************************************************************************
# Subroutine		: checkForUpdate
# Objective			: check if version update exists for the product
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub checkForUpdate {
	my %params = (
		'host'		=> $Configuration::checkUpdateBaseCGI,
		'method'	=> 'GET',
		'json'		=> 0
	);

	#my $cgiResult = Helpers::request(\%params);
	my $cgiResult = Helpers::requestViaUtility(\%params);

	return 0 unless(ref($cgiResult) eq 'HASH');
	return 1 if($cgiResult->{Configuration::DATA} eq "Y");
	return 0 if($cgiResult->{Configuration::DATA} eq "N");

	cleanupUpdate($Locale::strings{'kindly_verify_ur_proxy'}) if($cgiResult->{Configuration::DATA} =~ /.*<h1>Unauthorized \.{3,3}<\/h1>.*/);

	my $pingRes = `ping -c2 8.8.8.8`;
	cleanupUpdate($pingRes) if($pingRes =~ /connect\: Network is unreachable/);
	cleanupUpdate($Locale::strings{'please_check_internet_con_and_try'}) if($pingRes !~ /0\% packet loss/);
	cleanupUpdate($Locale::strings{'kindly_verify_ur_proxy'}) if($cgiResult->{Configuration::DATA} eq '');
}

#*************************************************************************************************
# Subroutine		: deleteDeprecatedScripts
# Objective			: delete deprecated scripts if present
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub deleteDeprecatedScripts {
	foreach my $depScript (keys %Configuration::idriveScripts) {
		unlink(Helpers::getAppPath() . qq(/$Configuration::idriveScripts{$depScript})) if($depScript =~ m/deprecated_/);
	}
}

#*************************************************************************************************
# Subroutine		: cleanupUpdate
# Objective			: cleanup the update process
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub cleanupUpdate {
	my $packageName 	= qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
	unlink($packageName) if(-e $packageName);

	my $packageDir 		= qq(/$Configuration::tmpPath/$Configuration::appPackageName);
	Helpers::removeItems($packageDir) if($packageDir ne '/' && -e $packageDir);
	my $scriptBackupDir	= qq(/$Configuration::tmpPath/$Configuration::appType) . q(_backup);
	Helpers::removeItems("$scriptBackupDir") if($scriptBackupDir ne '/' && -e $scriptBackupDir);
	Helpers::removeItems("$Configuration::tmpPath/scripts") if(-e qq($Configuration::tmpPath/scripts));
	unlink(Helpers::getAppPath() . qq(/$Configuration::unzipLog));
	unlink(Helpers::getAppPath() . qq(/$Configuration::updateLog));

	my $pidPath = Helpers::getCatfile(Helpers::getServicePath(), $Configuration::pidFile);
	unlink($pidPath) if(-e $pidPath);
	exit(0) if $_[0] eq '';

	$Configuration::displayHeader = 0;
	Helpers::retreat($_[0]) if($_[0] ne 'INIT');
}

#*************************************************************************************************
# Subroutine		: updateVersionInfoFile
# Objective			: update version infomation file
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub updateVersionInfoFile {
	my $versionInfoFile = Helpers::getAppPath() . '/' . $Configuration::updateVersionInfo;
	open (VN,'>', $versionInfoFile);
	print VN $Configuration::version;
	close VN;
	chmod $Configuration::filePermission, $versionInfoFile;
}

#*************************************************************************************************
# Subroutine		: deleteVersionInfoFile
# Objective			: clean version infomation file
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub deleteVersionInfoFile {
	my $versionInfoFile = Helpers::getAppPath() . '/' . $Configuration::updateVersionInfo;
	Helpers::removeItems($versionInfoFile);
}

#*************************************************************************************************
# Subroutine		: preUpdate
# Objective			: Execute the pre update script before updating the script package.
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub preUpdate {
	my $cmd = (Helpers::getIDrivePerlBin() . ' ' .Helpers::getScript('utility', 1) . ' PREUPDATE '." '".$Configuration::version."' ".qq('$_[0]')." 2>/dev/null");
	my $res = system($cmd);
	if($res){
		Helpers::traceLog('failed_to_run_script',Helpers::getScript('utility', 1),". Reason:".$?);
	}
}

#*************************************************************************************************
# Subroutine		: postUpdate
# Objective			: Execute the post update script after updating the script package.
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub postUpdate {
	my $perlBin = $Configuration::perlBin;
	$perlBin = Helpers::getIDrivePerlBin() if(Helpers::hasStaticPerlBinary());
	my $cmd = ($perlBin . ' ' .Helpers::getScript('utility', 1) . ' POSTUPDATE '." '".$Configuration::version."' ".qq('$_[0]')." 2>/dev/null");
	my $res = system($cmd);
	if($res){
		Helpers::traceLog('failed_to_run_script',Helpers::getScript('utility', 1),". Reason:".$?);
	}
}

#*************************************************************************************************
# Subroutine		: checkAndCreateServiceDirectory
# Objective			: check and create service directory if not present
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub checkAndCreateServiceDirectory {
	unless (Helpers::loadServicePath()) {
		unless (Helpers::checkAndUpdateServicePath()) {
			Helpers::createServiceDirectory();
		}
	}
	#Checking if another job is already in progress
	my $pidPath = Helpers::getCatfile(Helpers::getServicePath(), $Configuration::pidFile);
	$forceUpdate = 1 if(-f $pidPath);
	if (Helpers::isFileLocked($pidPath)) {
		Helpers::retreat('updating_scripts_wait');
	}
	else {
		Helpers::fileLock($pidPath);
	}
}
