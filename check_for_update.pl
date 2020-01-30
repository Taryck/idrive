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
use Configuration;
use File::Basename;
use File::Copy qw(copy);
use Scalar::Util qw(reftype);

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub init {
	Helpers::loadAppPath();
	Helpers::loadServicePath();
	Helpers::loadUsername();
	Helpers::loadUserConfiguration();
	checkWritePermission();

	my ($packageName, $updateAvailable, $taskParam) =  ('', 0, $ARGV[0]);

	$taskParam = '' unless (defined($taskParam));

	if ($taskParam eq 'checkUpdate') {
		$updateAvailable = checkForUpdate();
		updateVersionInfoFile() if ($updateAvailable);
		exit(0);
	}

	Helpers::findDependencies(0) or Helpers::retreat('failed');

	if ($taskParam eq '') {
		system(Helpers::updateLocaleCmd('clear'));
		Helpers::displayHeader();
		checkAndCreateServiceDirectory();

		my $usrProfileDirPath	= Helpers::getCatfile(Helpers::getServicePath(), $Configuration::userProfilePath);
		if(-d $usrProfileDirPath) {
			Helpers::display(['updating_script_will_logout_users','do_you_want_to_continue_yn']);
			Helpers::cleanupUpdate() if (Helpers::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
		}

		Helpers::askProxyDetails() unless (Helpers::getUserConfiguration('PROXYIP'));
		Helpers::display(["\n",'checking_for_updates', '...']);

		$packageName = qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		$updateAvailable = checkForUpdate();

		unless ($updateAvailable) {
			Helpers::display(['no_updates_but_still_want_to_update']);
			if (Helpers::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n') {
				Helpers::retreat([$Configuration::appType, ' ', 'is_upto_date']);
			}
		} else {
			Helpers::cleanupUpdate('INIT');
			Helpers::display(['new_updates_available_want_update']);
			Helpers::cleanupUpdate() if (Helpers::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
			Helpers::display(['updating_scripts_wait', '...']);
		}
	}
	elsif ($taskParam eq 'silent') {
		$Configuration::callerEnv = 'BACKGROUND';
		checkAndCreateServiceDirectory();
		$packageName = qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		Helpers::cleanupUpdate('INIT');
	}
	elsif ($taskParam =~ /.zip$/i) {
		system(Helpers::updateLocaleCmd('clear'));
		Helpers::displayHeader();
		checkAndCreateServiceDirectory();
		$packageName = $taskParam;
		Helpers::cleanupUpdate('INIT');
		Helpers::cleanupUpdate(['file_not_found', ": $packageName"]) unless (-e $packageName);

		my $usrProfileDirPath	= Helpers::getCatfile(Helpers::getServicePath(), $Configuration::userProfilePath);
		if(-d $usrProfileDirPath) {
			Helpers::display(['updating_script_will_logout_users','do_you_want_to_continue_yn']);
			Helpers::cleanupUpdate() if (Helpers::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
		}

		$packageName = qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		copy $taskParam, $packageName;
	}
	else{
		Helpers::retreat(['invalid_parameter', ': ', $taskParam, '. ', 'please_try_again', '.']);
	}

	if ($taskParam !~ /.zip$/i) {
		# Download the package to update the scripts
		Helpers::cleanupUpdate(['update_failed_to_download']) unless (Helpers::download($Configuration::appDownloadURL, qq(/$Configuration::tmpPath)));
		Helpers::cleanupUpdate(['update_failed_to_download']) unless (-e qq($packageName));
	}

	createUpdatePid();
	deleteVersionInfoFile();
	#preUpdate($taskParam);
	installUpdates($packageName, $taskParam);

	Helpers::display(['scripts_updated_successfully']) unless ($taskParam eq 'silent');

	postUpdate($taskParam);
	displayReleaseNotes() unless ($taskParam eq 'silent');
	Helpers::cleanupUpdate();
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
	my $whichTailCmd = Helpers::updateLocaleCmd('which tail 2>/dev/null');
	if (`$whichTailCmd`) {
		my $tailReadMePathCmd = Helpers::updateLocaleCmd("tail -50 '$readMePath' | grep \"Build\"");
		my @lastVersion = `$tailReadMePathCmd`;
		my $lastVersion = $lastVersion[scalar(@lastVersion) - 1];
		Helpers::Chomp(\$lastVersion);
		Helpers::display(["\n", 'release_notes', ':', "\n", '=' x 15]);
		my $catReadMePathCmd = Helpers::updateLocaleCmd("cat '$readMePath' | grep -A50 \"$lastVersion\"");
		Helpers::display([`$catReadMePathCmd`]);
		return 1;
	}
	my $tacReadMePathCmd = Helpers::updateLocaleCmd("tac '$readMePath' | grep -m1 -B50 \"Build\"");
	my @features = `$tacReadMePathCmd`;
	@features = reverse(@features);
	Helpers::display(['release_notes', ':', "\n", '=' x 15, "\n", (join "\n", @features)]);
	return 2;
}

#*************************************************************************************************
# Subroutine		: installUpdates
# Objective			: install downloaded update package
# Added By			: Sabin Cheruvattil
# Modified By		: Senthil Pandian, Yogesh Kumar
#*************************************************************************************************/
sub installUpdates {
	my $packageName 	= $_[0];
	#my $taskParam 		= 'silent';
	my $taskParam 		= $_[1];
	my $zipLogFile		= Helpers::getAppPath() . qq(/$Configuration::unzipLog);
	my $tempDir 		= qq(/$Configuration::tmpPath);
	my $unZipPackage 	= Helpers::updateLocaleCmd("unzip -o '$packageName' -d '$tempDir' 2>'$zipLogFile'");
	`$unZipPackage`;

	my $scriptBackupDir = qq(/$Configuration::tmpPath/$Configuration::appType) . q(_backup);
	Helpers::createDir($scriptBackupDir);
	chmod $Configuration::filePermission, $scriptBackupDir;

	Helpers::cleanupUpdate(['update_failed_unable_to_unzip']) if (-s $zipLogFile);

	my $packageDir = qq(/$Configuration::tmpPath/$Configuration::appPackageName/scripts);
	my $constantsFilePath = $packageDir.qq(/$Configuration::idriveScripts{'constants'});
	if (!-e $constantsFilePath){
		Helpers::cleanupUpdate([
				"\n", 'invalid_zip_file', "\n",
				$Configuration::appDownloadURL, "\n\n",
			]);
	}
	my $downloadedVersionCmd = Helpers::updateLocaleCmd("cat '$constantsFilePath' | grep -m1 \"ScriptBuildVersion => '\"");
	my $downloadedVersion = `$downloadedVersionCmd`;
	$downloadedVersion = (split(/'/, $downloadedVersion))[1];
	Helpers::Chomp(\$downloadedVersion);

	#To restrict the package upgrade/downgrade if ZIP version is beyond the limit
	my $versionLimit = Helpers::checkMinMaxVersion($Configuration::version, $downloadedVersion);
	if ($versionLimit > 1) {
		Helpers::cleanupUpdate([$versionLimit."_script_update_error","'$downloadedVersion'","."]);
	}

	if(defined($ARGV[0]) and $ARGV[0] =~ /.zip$/i) {
		my $isLatest = 1;
		if ($Configuration::version eq $downloadedVersion) {
			Helpers::display(["\n", 'your_both_package_versions_are_same']);
			$isLatest = 0;
		} else {
			unless (Helpers::versioncompare($Configuration::version, $downloadedVersion) == 2) {
				Helpers::display(["\n", 'your_current_package_version_is_higher']);
				$isLatest = 0;
			}
		}

		if ($isLatest == 0) {
			my $updateChoice = Helpers::getAndValidate('enter_your_choice','YN_choice', 1);
			if ($updateChoice eq "n" || $updateChoice eq "N" ) {
				Helpers::cleanupUpdate();
			}
		}
	}

	my @scriptNames;
	@scriptNames = (@scriptNames, map{$Configuration::idriveScripts{$_}} keys %Configuration::idriveScripts);

	# Take a backup
	my $moveRes = moveScripts(Helpers::getAppPath(), $scriptBackupDir, \@scriptNames);
	if (!$moveRes) {
		# Backup creation failed. Trying to revert the scripts to current location
		$moveRes = moveScripts($scriptBackupDir, Helpers::getAppPath(), \@scriptNames);
		unlink(Helpers::getAppPath() . qq(/$Configuration::updateLog)) if ($moveRes);
		Helpers::cleanupUpdate(['failed_to_update', '.']);
	}

	unlink(Helpers::getAppPath() . qq(/$Configuration::updateLog));

	# Move latest scripts to actual script folder
	Helpers::cleanupUpdate(['failed_to_update', '.']) unless (moveUpdatedScripts(\@scriptNames));

	# clear freshInstall file
	unlink(Helpers::getAppPath() . qq(/$Configuration::freshInstall));
}

#*************************************************************************************************
# Subroutine		: moveUpdatedScripts
# Objective			: Move updated scripts to the user working folder
# Added By			: Sabin Cheruvattil
# Modified By		: Yogesh Kumar
#*************************************************************************************************/
sub moveUpdatedScripts {
	my $packageDir = qq(/$Configuration::tmpPath/$Configuration::appPackageName/scripts);
	my $sourceDir = Helpers::getAppPath();
	my @scripts;

	opendir(my $dh, $packageDir);
	foreach my $script (readdir($dh)) {
		push @scripts, $script if ($script ne '.' && $script ne '..');
	}
	closedir $dh;

	my $moveRes = moveScripts($packageDir, $sourceDir, \@scripts);
	if (!$moveRes) {
		my $scriptBackupDir = qq(/$Configuration::tmpPath/$Configuration::appType) . q(_backup);
		my $moveBackRes = moveScripts($scriptBackupDir, $sourceDir, $_[0]);
		Helpers::cleanupUpdate(['failed_to_update', 'please_cp_perl_from', "$scriptBackupDir to $sourceDir"]) unless ($moveBackRes);
	}
	my $sourcDirPermCmd = Helpers::updateLocaleCmd("chmod 0755");
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
#*************************************************************************************************/
sub moveScripts {
	my ($src, $dest, $scripts) = ($_[0], $_[1], $_[2]);
	my $moveResult = '';

	return 0 if ($dest eq '' || $src eq '' || !-e $dest || !-e $src || reftype($scripts) ne 'ARRAY' || scalar @{$scripts} == 0);

	open(UPDATELOG, '>>', Helpers::getAppPath() . qq(/$Configuration::updateLog)) or
		Helpers::retreat(['unable_to_open_file', ': ', $!]);
	chmod $Configuration::filePermission, Helpers::getAppPath() . qq(/$Configuration::updateLog);

	foreach(@{$scripts}) {
		my $fileToTransfer = qq($src/$_);
		if (-e $fileToTransfer) {
			#$moveResult = `mv '$fileToTransfer' '$dest'`; #Commented by Senthil: 10-Aug-2018
			my $moveResultCmd = Helpers::updateLocaleCmd("cp -rf '$fileToTransfer' '$dest'");
			$moveResult = `$moveResultCmd`;
			print UPDATELOG qq(\n).Helpers::getStringConstant('move_file').qq(:: $fileToTransfer >> $dest :: $moveResult\n);
		}

		last if ($moveResult ne '');
	}

	Helpers::traceLog($moveResult);
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
	my %params = (
		'host'  => $Configuration::checkUpdateBaseCGI,
		'method'=> 'GET',
		'json'  => 0
	);

	#my $cgiResult = Helpers::request(\%params);
	my $cgiResult = Helpers::requestViaUtility(\%params);

	return 0 unless (ref($cgiResult) eq 'HASH');
	return 1 if ($cgiResult->{Configuration::DATA} eq 'Y');
	return 0 if ($cgiResult->{Configuration::DATA} eq 'N');

	Helpers::cleanupUpdate(['kindly_verify_ur_proxy']) if ($cgiResult->{Configuration::DATA} =~ /.*<h1>Unauthorized \.{3,3}<\/h1>.*/);
	my $pingCmd = Helpers::updateLocaleCmd('ping -c2 8.8.8.8');
	my $pingRes = `$pingCmd`;
	Helpers::cleanupUpdate([$pingRes]) if ($pingRes =~ /connect\: Network is unreachable/);
	Helpers::cleanupUpdate(['please_check_internet_con_and_try']) if ($pingRes !~ /0\% packet loss/);
	Helpers::cleanupUpdate(['kindly_verify_ur_proxy']) if ($cgiResult->{Configuration::DATA} eq '');
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
	my $perlBin = $Configuration::perlBin;
	$perlBin = Helpers::getIDrivePerlBin() if (Helpers::hasStaticPerlBinary());
	my $cmd = ($perlBin . ' ' .Helpers::getScript('utility', 1) . ' PREUPDATE '." '".$Configuration::version."' ".qq('$_[0]')." 2>/dev/null");
	$cmd = Helpers::updateLocaleCmd($cmd);
	my $res = system($cmd);
	if ($res){
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
	my $cmd = ($perlBin . ' ' .Helpers::getScript('utility', 1) . ' POSTUPDATE '." '".$Configuration::version."' ".qq('$_[0]')." 2>/dev/null");
	$cmd = Helpers::updateLocaleCmd($cmd);
	my $res = system($cmd);
	if ($res){
		Helpers::traceLog('failed_to_run_script',Helpers::getScript('utility', 1),". Reason:".$?);
	}
}

#*************************************************************************************************
# Subroutine		: checkAndCreateServiceDirectory
# Objective			: check and create service directory if not present
# Added By			: Senthil Pandian
# Modified By		: Yogesh Kumar
#*************************************************************************************************/
sub checkAndCreateServiceDirectory {
	unless (Helpers::loadServicePath()) {
		unless (Helpers::checkAndUpdateServicePath()) {
			Helpers::createServiceDirectory();
		}
	}
	Helpers::createDir(Helpers::getCachedDir(),1) unless(-d Helpers::getCachedDir());
}

#*************************************************************************************************
# Subroutine		: createUpdatePid
# Objective			: check and create update pid if not exists
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub createUpdatePid {
	my $updatePid = Helpers::getCatfile(Helpers::getCachedDir(), $Configuration::updatePid);
	# Check if another job is already in progress
	if (Helpers::isFileLocked($updatePid)) {
		Helpers::retreat('updating_scripts_wait');
	}
	elsif (!Helpers::fileLock($updatePid)) {
		Helpers::retreat($!);
	}
}

#*************************************************************************************************
# Subroutine		: checkWritePermission
# Objective			: check write permission of scripts
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub checkWritePermission {
	my $scriptDir = Helpers::getAppPath();
	my $noPerm = 0;
	if(!-w $scriptDir){
		Helpers::retreat(['system_user', " '$Configuration::mcUser' ", 'does_not_have_sufficient_permissions',' ','please_run_this_script_in_privileged_user_mode','update.']);
	}
	opendir(my $dh, $scriptDir);
	foreach my $script (readdir($dh)) {
		next if ($script eq '.' or $script eq '..');
		next if (-f $script and $script !~ /.pl|.pm/ and $script ne 'readme.txt');
		if(!-w $script){
			Helpers::retreat(['system_user', " '$Configuration::mcUser' ", 'does_not_have_sufficient_permissions',' ','please_run_this_script_in_privileged_user_mode','update.']);
		}
	}
	closedir $dh;
}
