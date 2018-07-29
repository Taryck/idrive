#!/usr/bin/perl
#*****************************************************************************************************
# 				This script is used to check update is available or not and manual update
# 							Created By: Sabin Cheruvattil
#****************************************************************************************************/
use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')) ;	} else { use lib '.' ; }

use Helpers;
use Strings;
use Configuration;
use File::Basename;
use File::Copy qw(copy);
use Scalar::Util qw(reftype);

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
	Helpers::loadUserConfiguration(1);
	
	my ($packageName, $updateAvailable, $taskParam) =  ('', 0, $ARGV[0]);
	$taskParam = '' if(!defined($taskParam));
	
	if($taskParam =~ /.zip$/i or $taskParam eq ''){
		system('clear');
		Helpers::displayHeader();
	}
	Helpers::findDependencies(0) or Helpers::retreat('failed');
	
	if($taskParam =~ /.zip$/i) {
		#system('clear');
		#Helpers::displayHeader();
		$packageName		= $taskParam;
		deleteVersionInfoFile();
		cleanupUpdate('INIT');
		
		cleanupUpdate($Locale::strings{'file_not_found'} . ' ' . $packageName) if(!-e $packageName);
		$packageName	= qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		copy $taskParam, $packageName;
	} elsif($taskParam eq "checkUpdate") {
		$updateAvailable 	= checkForUpdate();
		updateVersionInfoFile()	if($updateAvailable);	
		exit(0);
	} elsif($taskParam eq '') {
		Helpers::askProxyDetails() or Helpers::retreat('failed') unless(Helpers::getUserConfiguration('PROXYIP'));
		#system('clear');
		#Helpers::displayHeader();
		Helpers::display(["\n",'checking_for_updates', '...']);
		
		$packageName 		= qq(/$Configuration::tmpPath/$Configuration::appPackageName$Configuration::appPackageExt);
		
		$updateAvailable 	= checkForUpdate();
		Helpers::retreat([$Configuration::appType, ' ', 'is_upto_date']) if(!$updateAvailable);
		deleteVersionInfoFile();
		cleanupUpdate('INIT');
		
		cleanupUpdate('') if(Helpers::getAndValidate($Locale::strings{'new_updates_available_want_update'} . ' ', 'YN_choice', 1) eq 'n');
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
	installUpdates($packageName);
	
	# Enable in Future
	deleteDeprecatedScripts();
	
	Helpers::display(['scripts_updated_successfully']);
	displayReleaseNotes();
	
	cleanupUpdate('');
}

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
		Helpers::display([`cat '$readMePath' | grep -A30 "$lastVersion"`]);
		return 1;
	}
	
	my @features = `tac '$readMePath' | grep -m1 -B20 "Build"`;
	@features = reverse(@features);
	Helpers::display(['release_notes', ':', "\n", '=' x 15, "\n", (join "\n", @features)]);
	return 2;
}

#*************************************************************************************************
# Subroutine		: installUpdates
# Objective			: install downloaded update package
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub installUpdates {
	my $packageName 	= $_[0];
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
	my @currentVersionSplit    = split(/\./, $Configuration::version);
	my @downloadedVersionSplit = split(/\./, $downloadedVersion);
	my $i=0;
	my $isLatest=1;
	foreach my $version (@currentVersionSplit){			
		if($version gt $downloadedVersionSplit[$i]){
			$isLatest = 0;
			last;
		}
		$i++;
	}
	if($isLatest==0){
		print $lineFeed.$Locale::strings{'zipped_package_not_latest'}.$lineFeed;
		my $updateChoice = Helpers::getAndValidate('enter_your_choice','YN_choice');
		if($updateChoice eq "n" || $updateChoice eq "N" ) {
			cleanupUpdate("");
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
			$moveResult = `mv '$fileToTransfer' '$dest'`;
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
	
	my $cgiResult 	= Helpers::request(%params);
	unless(ref($cgiResult) eq 'HASH'){
		return 0;
	}
	return 1 if($cgiResult->{DATA} eq "Y");
	return 0 if($cgiResult->{DATA} eq "N");
	cleanupUpdate($Locale::strings{'kindly_verify_ur_proxy'}) if($cgiResult->{DATA} =~ /.*<h1>Unauthorized \.{3,3}<\/h1>.*/);
	
	my $pingRes = `ping -c2 8.8.8.8`;
	cleanupUpdate($pingRes) if($pingRes =~ /connect\: Network is unreachable/);
	cleanupUpdate($Locale::strings{'please_check_internet_con_and_try'}) if($pingRes !~ /0\% packet loss/);
	cleanupUpdate($Locale::strings{'kindly_verify_ur_proxy'}) if($cgiResult->{DATA} eq '');
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
	`rm -rf '$packageDir'` if($packageDir ne '/' && -e $packageDir);
	
	my $scriptBackupDir	= qq(/$Configuration::tmpPath/$Configuration::appType) . q(_backup);
	`rm -rf '$scriptBackupDir'` if($scriptBackupDir ne '/' && -e $scriptBackupDir);
	
	`rm -rf $Configuration::tmpPath/scripts` if(-e qq($Configuration::tmpPath/scripts));
	
	unlink(Helpers::getAppPath() . qq(/$Configuration::unzipLog));
	unlink(Helpers::getAppPath() . qq(/$Configuration::updateLog));
	
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
	`rm -f $versionInfoFile`;
}