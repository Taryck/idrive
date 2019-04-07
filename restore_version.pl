#!/usr/bin/env perl
#-------------------------------------------------------------------------------
# Created By : Sabin Cheruvattil @ IDrive Inc
#-------------------------------------------------------------------------------

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Strings;
use Configuration;
use File::Path;
use File::Basename;
use Time::Local;

my ($lastVersion, $fullFilePath) = (10, '');
tie(my %mainMenuOptions, 'Tie::IxHash', '1' => 'display_versions_for_your_file', '2' => 'restore_a_specific_version_of_your_file');
Helpers::initiateMigrate();

init();

#****************************************************************************************************
# Subroutine			: init
# Objective				: This invokes the view log functionality
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	my @parsedVersionData = '';

	system('clear');
	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername()    or Helpers::retreat('login_&_try_again');
	my $errorKey = Helpers::loadUserConfiguration();
	Helpers::retreat($Configuration::errorDetails{$errorKey}) if ($errorKey != 1);
	Helpers::loadEVSBinary() or Helpers::retreat('unable_to_find_or_execute_evs_binary');
	Helpers::isLoggedin()    or Helpers::retreat('login_&_try_again');

	Helpers::displayHeader();
	displayMainMenu();

	my $jobRunningDir = Helpers::getUsersInternalDirPath('restore');
	my $userMainChoice= Helpers::getUserMenuChoice(scalar keys %mainMenuOptions);

	#have to ask restore from
	editVersionRestoreFromLocation();

	$fullFilePath = getFilePath();

	#Display version
	if ($userMainChoice eq 1) {
		Helpers::display(["\n", 'checking_version_for_file', '...']);
		@parsedVersionData = getFileVersions();
		displayTableforVersionData(\@parsedVersionData);

		my $confirmationChoice = Helpers::getAndValidate(['do_you_want_to_restore_version_yn'], "YN_choice", 1);
		if ($confirmationChoice eq "n") {
			Helpers::display(["\n", 'exiting_title', "\n"]);
			my $idevsErrorFile = qq($jobRunningDir/error.txt);
			unlink($idevsErrorFile);
			exit 0;
		}
	}

	createRestoresetFile(\@parsedVersionData);
	sleep(2);

	restoreVersion();
}

#****************************************************************************
# Subroutine			: editVersionRestoreFromLocation
# Objective				: Ask restore location and set the same
# Added By				: Sabin Cheruvattil
#****************************************************************************/
sub editVersionRestoreFromLocation {
	my $currRestoreFrom = Helpers::getUserConfiguration('RESTOREFROM');
	Helpers::editRestoreFromLocation(1);
	Helpers::saveUserConfiguration() if ($currRestoreFrom ne Helpers::getUserConfiguration('RESTOREFROM'));
}

#********************************************************************************
# Subroutine			: restoreVersion.
# Objective				: Restore user's requested version of a file
# Added By				: Dhritikana Kalita.
#********************************************************************************
sub restoreVersion {
	my $restoreRunCommand = qq(perl ') . Helpers::getAppPath() . qq(/$Configuration::idriveScripts{'restore_script'}' 2);
	system($restoreRunCommand);
}

#*************************************************************************************************
# Subroutine			: createRestoresetFile.
# Objective				: create RestoresetFile based on user's given version number.
# Modified By			: Sabin Cheruvattil
#*************************************************************************************************
sub createRestoresetFile {
	my @parsedVersionData = @{$_[0]};

	Helpers::display(["\n", 'provide_the_version_no_for_file', '.'], 0);
	my $versionNo = Helpers::getUserMenuChoice($lastVersion);

	Helpers::display('');

	# If the restore location is changed, it must be acknowledged to user before restore script clear the screen. So adding a wait of 2 sec.
	sleep(2) if (Helpers::getUserConfiguration('RESTORELOCATIONPROMPT') && Helpers::editRestoreLocation(1));

	#this will give file size for selected version.
	my $fileVersionSize = (scalar @parsedVersionData > 0)? $parsedVersionData[(($versionNo - 1) * 4) + 3] : '';
	$fileVersionSize = '' unless $fileVersionSize;

	my $jobRunningDir  = Helpers::getUsersInternalDirPath('restore');
	my $restoresetFile = qq($jobRunningDir/$Configuration::versionRestoreFile);
	open(FILE, ">", $restoresetFile) or Helpers::traceLog(qq($Locale::strings{'couldnt_open'} $restoresetFile $Locale::strings{'for_restore_version_option'}. $Locale::strings{'reason'}: $!));
	chmod $Configuration::filePermission, $restoresetFile;
	print FILE $fullFilePath . '_IBVER' . $versionNo . "\n" . $fileVersionSize . "\n";
	close FILE;

	return $restoresetFile;
}

#*************************************************************************************************
# Subroutine			: displayTableforVersionData
# Objective				: This function will show version details in tabular form to user
# Added By				: Dhritikana Kalita
# Modified				: Sabin Cheruvattil
#*************************************************************************************************
sub displayTableforVersionData {
	my @parsedVersionData = @{$_[0]};
	my @columnNames = (['Version No.', 'Modified Date', 'Size'], [13, 25, 17]);
	my $tableHeader = Helpers::getTableHeader(@columnNames);
	my ($tableContent, $spaceIndex, $lineChangeIndicator) = ("", 0, 0);

	foreach(@parsedVersionData) {
		$tableContent .= $_ . (' ') x ($columnNames[1]->[$spaceIndex] - length($_));
		if ($lineChangeIndicator == 2) {
			$tableContent .= "\n";
			($lineChangeIndicator, $spaceIndex) = (0) x 2;
		} else {
			$spaceIndex++;
			$lineChangeIndicator += 1;
		}
	}

	if ($tableContent ne '') {
		Helpers::display([$tableHeader . $tableContent]);
	} else {
		Helpers::display([qq(\n$Locale::strings{'no_version_found'}.\n$Locale::strings{'exiting_title'}...\n)]);
		exit(0);
	}
}

#********************************************************************************
# Subroutine			: getFileVersions.
# Objective				: Gets versions of user's requested file
# Modified By			: Sabin Cheruvattil
#********************************************************************************
sub getFileVersions {
	Helpers::createUTF8File('FILEVERSION', $fullFilePath) or Helpers::retreat('failed_to_create_utf8_file');
	my @result = Helpers::runEVS('item');
	my $errorMessageHandler = {
								$Locale::strings{'no_version_found'} => qq($Locale::strings{'no_version_found_for_given_file'}. ),
								$Locale::strings{'path_not_found'} => qq($Locale::strings{'could_not_find_given_file'}.),
								'cleanupOperation' => sub {Helpers::display(['exiting_title']); exit(0);}
							};

	# system("clear");
	if ($result[0]{'STATUS'} eq 'FAILURE') {
		my $errorMessage = $result[0]{'MSG'};
		$errorMessage =~ s/^\s+|\s+$//g;
		if ($errorMessage ne '') {
			if ($errorMessage =~ /password mismatch|encryption verification failed|encryption_verification_failed/i) {
				Helpers::display([$errorMessage, '. ', 'please_login_account_using_login_and_try']);
				unlink(Helpers::getIDPWDFile());
			}
			elsif ($errorMessage =~ /failed to get the device information|Invalid device id/i) {
				Helpers::display([$errorMessage, '. ', Helpers::getStringWithScriptName('invalid_res_loc_edit_loc_acc_settings'), "\n"]);
			}
			elsif ($errorMessage =~/No version found/i || $errorMessage =~ /path not found/i) {
				Helpers::display([$errorMessageHandler->{"$&"}]);
			}
			else {
				$errorMessage = Helpers::checkErrorAndLogout($errorMessage);
				Helpers::display([$errorMessage, "\n"]);
			}
		}
		$errorMessageHandler->{'cleanupOperation'}->();
	}

	return parseVersionData(@result);
}

#****************************************************************************
# Subroutine			: parseVersionData
# Objective				: To parse the version details from EVS output
# Added By				: Abhishek Verma
# Modified By			: Sabin Cheruvattil
#****************************************************************************/
sub parseVersionData {
	my @versionData = @_;
	my $serialNumber = 1;
	my @fileVersionData;

	foreach(@versionData) {
		# $versionData = $';
		# push(@fileVersionData, $serialNumber);
		push(@fileVersionData, $_[($serialNumber - 1)]{'ver'});#0 -> contains version
		push(@fileVersionData, $_[($serialNumber - 1)]{'mod_time'});#1 -> contains modified date
		push(@fileVersionData, Helpers::getHumanReadableSizes($_[($serialNumber - 1)]{'size'}));
		$serialNumber ++;
	}

	$lastVersion = $serialNumber -1;
	return @fileVersionData;
}

#***********************************************************************************************************
# Subroutine			: getFilePath
# Objective				: Ask user for the file path for which he/she wants to do dispay/restore file version.
# Added By				: Sabin Cheruvattil
#**********************************************************************************************************
sub getFilePath {
	Helpers::display('');
	my $filePath = Helpers::getAndValidate(['enter_your_file_path',': '], 'non_empty', 1);
	Helpers::Chomp(\$filePath);

	my $fileRestoreHost = Helpers::getUserConfiguration('RESTOREFROM');

	# $fileRestoreHost has the value: DEVICEID#HOSTNAME, so unset it
	$fileRestoreHost = "" if (Helpers::getUserConfiguration('DEDUP') eq 'on');

	my $fullFilePath = (substr($filePath, 0, 1) ne "/")? $fileRestoreHost . "/" . $filePath : $fileRestoreHost . $filePath;
	return $fullFilePath;
}

#****************************************************************************************************
# Subroutine			: displayMainMenu
# Objective				: This subroutine displays the date options menu
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub displayMainMenu {
	Helpers::display(['menu_options_title', ':', "\n"]);
	Helpers::display([map{$_ . ") ", $Locale::strings{$mainMenuOptions{$_}} . "\n"} keys %mainMenuOptions], 0);
}

1;
