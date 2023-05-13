#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to check update is available or not and manual update
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;
use File::Basename;

eval {
	require File::Copy;
	File::Copy->import();
};

use Scalar::Util qw(reftype);
use JSON;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub init {
	my ($packageName, $updateAvailable, $taskParam) =  ('', 0, $ARGV[0]);

	$taskParam = '' unless (defined($taskParam));

	if (($taskParam eq 'silent') or ($taskParam eq 'dispdependency')) {
		$AppConfig::callerEnv = 'BACKGROUND';
	}

	Common::loadAppPath();
	Common::loadServicePath();
	Common::loadUsername();
	Common::loadUserConfiguration();
	checkWritePermission();

	if ($taskParam eq 'checkUpdate') {
		$updateAvailable = checkForUpdate();
		updateVersionInfoFile() if ($updateAvailable);
		exit(0);
	}

	Common::findDependencies(0) or Common::retreat('failed');

	if($taskParam eq 'dispdependency' && Common::checkCRONServiceStatus() ne Common::CRON_RUNNING) {
		my $deps = {'pkg' => [], 'cpanpkg' => [], 'error' => 'cron_not_running'};
		Common::display(JSON::to_json($deps));
		exit(0);
	}

	if ($taskParam eq '') {
		system(Common::updateLocaleCmd('clear'));
		Common::displayHeader();
		checkAndCreateServiceDirectory();

        # Fetching & verifying OS & build version
        Common::getOSBuild(1);

		my $usrProfileDirPath	= Common::getCatfile(Common::getServicePath(), $AppConfig::userProfilePath);
		if(-d $usrProfileDirPath) {
			Common::display(['updating_script_will_logout_users','do_you_want_to_continue_yn']);
			Common::cleanupUpdate() if (Common::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
		}

		Common::askProxyDetails() unless (Common::getProxyDetails('PROXYIP'));
		Common::display(["\n",'checking_for_updates', '...']);

		$packageName = qq(/$AppConfig::tmpPath/$AppConfig::appPackageName$AppConfig::appPackageExt);
		$updateAvailable = checkForUpdate();

		unless ($updateAvailable) {
			Common::display(['no_updates_but_still_want_to_update']);
			if (Common::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n') {
				Common::retreat([$AppConfig::appType, ' ', 'is_upto_date']);
			}
		} else {
			Common::cleanupUpdate('INIT');
			Common::display(['new_updates_available_want_update']);
			Common::cleanupUpdate() if (Common::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
			Common::display(['updating_scripts_wait', '...']);
		}
	}
	elsif (($taskParam eq 'silent') or ($taskParam eq 'dispdependency')) {
		$AppConfig::callerEnv = 'BACKGROUND';
		checkAndCreateServiceDirectory();
		$packageName = qq(/$AppConfig::tmpPath/$AppConfig::appPackageName$AppConfig::appPackageExt);
		Common::cleanupUpdate('INIT');
	}
	else{
		Common::retreat(['invalid_parameter', ': ', $taskParam, '. ', 'please_try_again', '.']);
	}

	# Download the package to update the scripts
	Common::cleanupUpdate(['update_failed_to_download']) unless (Common::download($AppConfig::appDownloadURL, qq(/$AppConfig::tmpPath)));
	Common::cleanupUpdate(['update_failed_to_download']) unless (-e qq($packageName));

	my $packagedir	= extractPackage($packageName);

	displayPackageDep($packagedir) if($taskParam eq 'dispdependency');

	createUpdatePid('preupdate');
	preUpdate($taskParam, $packagedir);

	createUpdatePid('update');
	deleteVersionInfoFile();

	installUpdates($packagedir);

	Common::display(['scripts_updated_successfully']) unless ($taskParam eq 'silent');

	postUpdate($taskParam);
	displayReleaseNotes() unless ($taskParam eq 'silent');

	Common::cleanupUpdate();
}

#*************************************************************************************************
# Subroutine		: displayReleaseNotes
# Objective			: display release notes
# Added By			: Sabin Cheruvattil
# Modified By       : Senthil Pandian
#*************************************************************************************************/
sub displayReleaseNotes {
	my $readMePath = Common::getAppPath() . qq(/$AppConfig::idriveScripts{'readme'});
	my $whichTailCmd = Common::updateLocaleCmd('which tail 2>/dev/null');
	if (`$whichTailCmd`) {
		my $tailReadMePathCmd = Common::updateLocaleCmd("tail -50 '$readMePath' | grep \"Build\"");
		my @lastVersion = `$tailReadMePathCmd`;
		my $lastVersion = $lastVersion[scalar(@lastVersion) - 1];
		Common::Chomp(\$lastVersion);
		Common::display(["\n", 'release_notes', ':', "\n", '=' x 15]);
		$lastVersion =~ s/\[/\\[/;
		my $catReadMePathCmd = Common::updateLocaleCmd("cat '$readMePath' | grep -A50 \"$lastVersion\"");
		Common::display([`$catReadMePathCmd`]);
		return 1;
	}
	my $tacReadMePathCmd = Common::updateLocaleCmd("tac '$readMePath' | grep -m1 -B50 \"Build\"");
	my @features = `$tacReadMePathCmd`;
	@features = reverse(@features);
	Common::display(['release_notes', ':', "\n", '=' x 15, "\n", (join "\n", @features)]);
	return 2;
}

#*****************************************************************************************************
# Subroutine			: extractPackage
# In Param				: String | package
# Out Param				: String | Path
# Objective				: Extracts the package and returns the extract path
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub extractPackage {
	my $packageName 	= $_[0];
	my $packageDir		= qq(/$AppConfig::tmpPath/$AppConfig::appPackageName/scripts);

	Common::removeItems([$packageDir]) if(-d $packageDir);

	my $zipLogFile		= Common::getAppPath() . qq(/$AppConfig::unzipLog);
	my $tempDir 		= qq(/$AppConfig::tmpPath);
	my $unZipPackage 	= Common::updateLocaleCmd("unzip -o '$packageName' -d '$tempDir' 2>'$zipLogFile'");
	`$unZipPackage`;

	Common::cleanupUpdate(['update_failed_unable_to_unzip']) if (-s $zipLogFile);

	return $packageDir;
}

#*************************************************************************************************
# Subroutine		: displayPackageDep
# Objective			: Display future package dependencies.
# Added By			: Sabin Cheruvattil
#*************************************************************************************************
sub displayPackageDep {
	my $perlBin = $AppConfig::perlBin;
	my $cmd = $perlBin . ' ' . Common::getECatfile($_[0], $AppConfig::idriveScripts{'utility'}) . ' DISPLAYPACKAGEDEP 2>/dev/null';
	my $res = `$cmd`;

	$AppConfig::callerEnv = '';
	Common::display($res, 0);

	exit(0);
}

#*************************************************************************************************
# Subroutine		: installUpdates
# Objective			: install downloaded update package
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian, Yogesh Kumar
#*************************************************************************************************/
sub installUpdates {
	my $packageDir	= $_[0];

	my $scriptBackupDir	= qq(/$AppConfig::tmpPath/$AppConfig::appType) . q(_backup);
	Common::createDir($scriptBackupDir);
	chmod $AppConfig::filePermission, $scriptBackupDir;

	my $constantsFilePath = $packageDir.qq(/$AppConfig::idriveScripts{'constants'});
	if (!-e $constantsFilePath){
		Common::cleanupUpdate([
				"\n", 'invalid_zip_file', "\n",
				$AppConfig::appDownloadURL, "\n\n",
			]);
	}

	my $downloadedVersionCmd	= Common::updateLocaleCmd("cat '$constantsFilePath' | grep -m1 \"ScriptBuildVersion => '\"");
	my $downloadedVersion		= `$downloadedVersionCmd`;
	$downloadedVersion = (split(/'/, $downloadedVersion))[1];
	Common::Chomp(\$downloadedVersion);

	#To restrict the package upgrade/downgrade if ZIP version is beyond the limit
	my $versionLimit = Common::checkMinMaxVersion($AppConfig::version, $downloadedVersion);
	if ($versionLimit > 1) {
		Common::cleanupUpdate([$versionLimit."_script_update_error","'$downloadedVersion'","."]);
	}

	if(defined($ARGV[0]) and $ARGV[0] =~ /.zip$/i) {
		my $isLatest = 1;
		if ($AppConfig::version eq $downloadedVersion) {
			Common::display(["\n", 'your_both_package_versions_are_same']);
			$isLatest = 0;
		} else {
			unless (Common::versioncompare($AppConfig::version, $downloadedVersion) == 2) {
				Common::display(["\n", 'your_current_package_version_is_higher']);
				$isLatest = 0;
			}
		}

		if ($isLatest == 0) {
			my $updateChoice = Common::getAndValidate('enter_your_choice','YN_choice', 1);
			if ($updateChoice eq "n" || $updateChoice eq "N" ) {
				Common::cleanupUpdate();
			}
		}
	}

	my @scriptNames;
	@scriptNames = (@scriptNames, map{$AppConfig::idriveScripts{$_}} keys %AppConfig::idriveScripts);
	push(@scriptNames, 'Idrivelib');

	# Take a backup
	my $moveRes = moveScripts(Common::getAppPath(), $scriptBackupDir, \@scriptNames);
	if (!$moveRes) {
		# Backup creation failed. Trying to revert the scripts to current location
		$moveRes = moveScripts($scriptBackupDir, Common::getAppPath(), \@scriptNames);
		unlink(Common::getAppPath() . qq(/$AppConfig::updateLog)) if ($moveRes);
		Common::cleanupUpdate(['failed_to_update', '.']);
	}

	unlink(Common::getAppPath() . qq(/$AppConfig::updateLog));

	# Move latest scripts to actual script folder
	Common::cleanupUpdate(['failed_to_update', '.']) unless (moveUpdatedScripts(\@scriptNames));

	# clear freshInstall file
	unlink(Common::getAppPath() . qq(/$AppConfig::freshInstall));
}

#*************************************************************************************************
# Subroutine		: moveUpdatedScripts
# Objective			: Move updated scripts to the user working folder
# Added By			: Sabin Cheruvattil
# Modified By		: Yogesh Kumar
#*************************************************************************************************/
sub moveUpdatedScripts {
	my $packageDir = qq(/$AppConfig::tmpPath/$AppConfig::appPackageName/scripts);
	my $sourceDir = Common::getAppPath();
	my @scripts;

	opendir(my $dh, $packageDir);
	foreach my $script (readdir($dh)) {
		push @scripts, $script if ($script ne '.' && $script ne '..');
	}
	closedir $dh;

	my $moveRes = moveScripts($packageDir, $sourceDir, \@scripts);
	if (!$moveRes) {
		my $scriptBackupDir = qq(/$AppConfig::tmpPath/$AppConfig::appType) . q(_backup);
		my $moveBackRes = moveScripts($scriptBackupDir, $sourceDir, $_[0]);
		Common::cleanupUpdate(['failed_to_update', 'please_cp_perl_from', "$scriptBackupDir to $sourceDir"]) unless ($moveBackRes);
	}
	my $sourcDirPermCmd = Common::updateLocaleCmd("chmod 0755");
	`$sourcDirPermCmd '$sourceDir'`;
	`$sourcDirPermCmd '$sourceDir/'*.pl`;

	# moveBackRes will show the scprit backup revert failure.
	# we need to handle the display of update status as well.
	# If revert back failed, it would've exit in if (!$moveBackRes) condition itself

	return $moveRes;
}

#*************************************************************************************************
# Subroutine		: moveScripts
# Objective			: Helps tp move files between 2 directories
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian, Yogesh Kumar
#*************************************************************************************************/
sub moveScripts {
	my ($src, $dest, $scripts) = ($_[0], $_[1], $_[2]);
	my $moveResult = '';

	return 0 if ($dest eq '' || $src eq '' || !-e $dest || !-e $src || reftype($scripts) ne 'ARRAY' || scalar @{$scripts} == 0);

	open(UPDATELOG, '>>', Common::getAppPath() . qq(/$AppConfig::updateLog)) or
		Common::retreat(['unable_to_open_file', ': ', $!]);
	chmod $AppConfig::filePermission, Common::getAppPath() . qq(/$AppConfig::updateLog);

	foreach(@{$scripts}) {
		my $fileToTransfer = qq($src/$_);
		if (-e $fileToTransfer) {
			#$moveResult = `mv '$fileToTransfer' '$dest'`; #Commented by Senthil: 10-Aug-2018
			my $moveResultCmd = Common::updateLocaleCmd("cp -rf '$fileToTransfer' '$dest'");
			$moveResult = `$moveResultCmd`;
			print UPDATELOG qq(\n).Common::getStringConstant('move_file').qq(:: $fileToTransfer >> $dest :: $moveResult\n);
			if (-d $fileToTransfer and $moveResult eq '') {
				Common::removeItems([$fileToTransfer]);
			}
		}

		last if ($moveResult ne '');
	}

	Common::traceLog($moveResult) if($moveResult);
	close UPDATELOG;

	return ($moveResult ne '')? 0 : 1;
}

#*************************************************************************************************
# Subroutine		: checkForUpdate
# Objective			: check if version update exists for the product
# Added By			: Sabin Cheruvattil
# Modified By		: Yogesh Kumar
#*************************************************************************************************/
sub checkForUpdate {
	my $cgiResult = Common::makeRequest(4, [
		($AppConfig::appType . "ForLinux"),
		$AppConfig::trimmedVersion
	]);

	return 0 unless (ref($cgiResult) eq 'HASH');
	chomp($cgiResult->{AppConfig::DATA});
	return 1 if ($cgiResult->{AppConfig::DATA} eq 'Y');
	return 0 if ($cgiResult->{AppConfig::DATA} eq 'N');

	Common::cleanupUpdate(['kindly_verify_ur_proxy']) if ($cgiResult->{AppConfig::DATA} =~ /.*<h1>Unauthorized \.{3,3}<\/h1>.*/);
	my $pingCmd = Common::updateLocaleCmd('ping -c2 8.8.8.8');
	my $pingRes = `$pingCmd`;
	Common::cleanupUpdate([$pingRes]) if ($pingRes =~ /connect\: Network is unreachable/);
	Common::cleanupUpdate(['please_check_internet_con_and_try']) if ($pingRes !~ /0\% packet loss/);
	Common::cleanupUpdate(['kindly_verify_ur_proxy']) if ($cgiResult->{AppConfig::DATA} eq '');
}

#*************************************************************************************************
# Subroutine		: updateVersionInfoFile
# Objective			: update version infomation file
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub updateVersionInfoFile {
	my $versionInfoFile = Common::getUpdateVersionInfoFile();
	open (VN,'>', $versionInfoFile);
	print VN $AppConfig::version;
	close VN;
	chmod $AppConfig::filePermission, $versionInfoFile;
}

#*************************************************************************************************
# Subroutine		: deleteVersionInfoFile
# Objective			: clean version infomation file
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub deleteVersionInfoFile {
	my $versionInfoFile = Common::getUpdateVersionInfoFile();
	Common::removeItems($versionInfoFile);
}

#*************************************************************************************************
# Subroutine		: preUpdate
# Objective			: Execute the pre update script before updating the script package.
# Added By			: Senthil Pandian
# Modified By 		: Sabin Cheruvattil
#*************************************************************************************************
sub preUpdate {
	my $perlBin = $AppConfig::perlBin;
	my $cmd = ($perlBin . ' ' . Common::getECatfile($_[1], $AppConfig::idriveScripts{'utility'}) . ' PREUPDATE ' . "'" . $AppConfig::version . "' " . qq('$_[0]') . " '" . Common::getServicePath() . "' '" . Common::getUsername() . "'" . " 2>/dev/null");
	my $res = system($cmd);

	Common::retreat(['failed_to_complete_preupdate', "."], 0) if ($res);
}

#*************************************************************************************************
# Subroutine		: postUpdate
# Objective			: Execute the post update script after updating the script package.
# Added By			: Senthil Pandian
# Modified By 		: Sabin Cheruvattil
#*************************************************************************************************/
sub postUpdate {
	my $perlBin = $AppConfig::perlBin;
	my $cmd = ($perlBin . ' ' .Common::getScript('utility', 1) . ' POSTUPDATE ' . " '" . $AppConfig::version . "' " . qq('$_[0]') . " 2>/dev/null");

	my $res = system($cmd);
	Common::traceLog('Failed to complete post update') if ($res);
}

#*************************************************************************************************
# Subroutine		: checkAndCreateServiceDirectory
# Objective			: check and create service directory if not present
# Added By			: Senthil Pandian
# Modified By		: Yogesh Kumar, Sabin Cheruvattil
#*************************************************************************************************/
sub checkAndCreateServiceDirectory {
	unless (Common::loadServicePath()) {
		unless (Common::checkAndUpdateServicePath()) {
			Common::createServiceDirectory();
		}
	}

	Common::createDir(Common::getCachedDir(),1) unless(-d Common::getCachedDir());
}

#*************************************************************************************************
# Subroutine		: createUpdatePid
# Objective			: check and create update pid if not exists
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub createUpdatePid {
	my $updatePid = '';
	if($_[0] and $_[0] eq 'preupdate') {
		$updatePid = Common::getCatfile(Common::getCachedDir(), $AppConfig::preupdpid);
	} else {
		$updatePid = Common::getCatfile(Common::getCachedDir(), $AppConfig::updatePid);
	}

	# Check if another job is already in progress
	if (Common::isFileLocked($updatePid)) {
		Common::retreat('updating_scripts_wait');
	}
	elsif (Common::fileLock($updatePid)) {
		Common::retreat($!);
	}
}

#*************************************************************************************************
# Subroutine		: checkWritePermission
# Objective			: check write permission of scripts
# Added By			: Senthil Pandian
# Modified By		: Yogesh Kumar, Sabin Cheruvattil
#*************************************************************************************************/
sub checkWritePermission {
	my $scriptDir = Common::getAppPath();
	my $noPerm = 0;
	if (!-w $scriptDir){
		Common::retreat(['system_user', " '$AppConfig::mcUser' ", 'does_not_have_sufficient_permissions', ' ', 'please_run_this_script_in_privileged_user_mode','update.']);
	}

	opendir(my $dh, $scriptDir);
	foreach my $script (readdir($dh)) {
		next if ($script eq '.' or $script eq '..');
		next if (-f $script and $script !~ /.pl|.pm/ and $script ne 'readme.txt');
		if (!-w Common::getCatfile($scriptDir, $script)) {
			Common::retreat(['system_user', " '$AppConfig::mcUser' ", 'does_not_have_sufficient_permissions',' ','please_run_this_script_in_privileged_user_mode','update.']);
		}
	}
	closedir $dh;
}
