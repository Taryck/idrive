#!/usr/bin/env perl
#-------------------------------------------------------------------------------
# Created By : Sabin Cheruvattil @ IDrive Inc
#-------------------------------------------------------------------------------

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;
use File::Path;
use File::Basename;
use Time::Local;


my ($lastVersion, $fullFilePath, $versionRestoreType) = ($AppConfig::maxFileVersion, '', '');
tie(my %mainMenuOptions, 'Tie::IxHash', '1' => 'display_versions_for_your_file', '2' => 'restore_a_specific_version_of_your_file');

my $errorMessageHandler = {
                            Common::getStringConstant('no_version_found') => '"'.Common::getStringConstant('no_version_found_for_given_file').'."',
                            Common::getStringConstant('path_not_found') => '"'.Common::getStringConstant('could_not_find_given_file').'."',
                            'cleanupOperation' => sub {Common::display(['exiting_title']); exit(0);}
                        };

Common::waitForUpdate();
Common::initiateMigrate();

init();

#****************************************************************************************************
# Subroutine			: init
# Objective				: This invokes the view log functionality
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	my @parsedVersionData = ();

	system('clear');
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::verifyVersionConfig();
	Common::loadUsername() or Common::retreat('login_&_try_again');
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if ($errorKey > 1);
	Common::loadEVSBinary() or Common::retreat('unable_to_find_or_execute_evs_binary');
	Common::isLoggedin() or Common::retreat('login_&_try_again');

	Common::displayHeader();
	Common::checkAccountStatus(1);
	Common::displayMainMenu(\%mainMenuOptions);

	my $jobRunningDir = Common::getJobsPath('restore');
	my $userMainChoice= Common::getUserMenuChoice(scalar keys %mainMenuOptions);

	#have to ask restore from
	editVersionRestoreFromLocation();

	$fullFilePath = getFilePath();

	#Display version
	if ($userMainChoice eq 1) {
		Common::display(["\n", 'checking_version_for_file', '...']);
		@parsedVersionData = getFileVersions();
		displayTableforVersionData(\@parsedVersionData);

		my $confirmationChoice = Common::getAndValidate(['do_you_want_to_restore_version_yn'], "YN_choice", 1);
		if ($confirmationChoice eq "n") {
			Common::display(["\n", 'exiting_title', "\n"]);
			my $idevsErrorFile = qq($jobRunningDir/error.txt);
			unlink($idevsErrorFile);
			exit 0;
		}
	}

	createRestoresetFile(\@parsedVersionData, $userMainChoice);
	sleep(2);

	restoreVersion();
}

#****************************************************************************
# Subroutine			: editVersionRestoreFromLocation
# Objective				: Ask restore location and set the same
# Added By				: Sabin Cheruvattil
#****************************************************************************/
sub editVersionRestoreFromLocation {
	my $currRestoreFrom = Common::getUserConfiguration('RESTOREFROM');
	Common::editRestoreFromLocation(1);
	Common::saveUserConfiguration() if ($currRestoreFrom ne Common::getUserConfiguration('RESTOREFROM'));
}

#********************************************************************************
# Subroutine			: restoreVersion.
# Objective				: Restore user's requested version of a file
# Added By				: Dhritikana Kalita.
#********************************************************************************
sub restoreVersion {
	my $restoreRunCommand = qq($AppConfig::perlBin ') . Common::getAppPath() . qq(/$AppConfig::idriveScripts{'restore_script'}' 2);
	$restoreRunCommand = Common::updateLocaleCmd($restoreRunCommand);
	system($restoreRunCommand);
}

#*************************************************************************************************
# Subroutine			: createRestoresetFile.
# Objective				: create RestoresetFile based on user's given version number.
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#*************************************************************************************************
sub createRestoresetFile {
	my @parsedVersionData = @{$_[0]};

	Common::display(["\n", 'provide_the_version_no_for_file', '.']);
	my $versionNo = Common::getUserMenuChoice($lastVersion);

	#When option 2 selected
	if($_[1] == 2) {
		Common::display(["\n", 'checking_version_for_file', '...']);
		@parsedVersionData = getFileVersions();
		unless(scalar @parsedVersionData > 0 && $parsedVersionData[(($versionNo * 3)-2)]) {
			Common::display('Provided version number not found for the file.');
			Common::retreat('exiting_title');
		}
		Common::display('Version found');
	}
	Common::display('');

	# If the restore location is changed, it must be acknowledged to user before restore script clear the screen. So adding a wait of 2 sec.
	if(Common::getUserConfiguration('RESTORELOCATIONPROMPT')) {
        Common::editRestoreLocation(1);
        unless(-w Common::getUserConfiguration('RESTORELOCATION')) {
            my $errStr = Common::getStringConstant('operation_could_not_be_completed_reason').Common::getStringConstant('invalid_restore_location');
            Common::retreat(["\n",$errStr]);
        } else {
            Common::display("");
            sleep(2);
        }
    }

	#this will give file size for selected version.
	my $fileVersionSize = (scalar @parsedVersionData > 0)? $parsedVersionData[(($versionNo * 3)-1)] : '';
	$fileVersionSize = '' unless $fileVersionSize;

	my $restoresetFile = Common::getCatfile(Common::getJobsPath('restore'), $AppConfig::versionRestoreFile);
	my %fileInfo = ($fullFilePath => {
		type => 'f',
		ver  => $versionNo,
		size => $fileVersionSize,
	});
	Common::createVersionRestoreJson('fileVersioning', \%fileInfo);	
	return $restoresetFile;
}

#*************************************************************************************************
# Subroutine			: displayTableforVersionData
# Objective				: This function will show version details in tabular form to user
# Added By				: Dhritikana Kalita
# Modified				: Sabin Cheruvattil, Senthil Pandian
#*************************************************************************************************
sub displayTableforVersionData {
	my @parsedVersionData = @{$_[0]};
	my @columnNames = (['Version No.', 'Modified Date', 'Size'], [13, 25, 17]);
	my $tableHeader = Common::getTableHeader(@columnNames);
	my ($tableContent, $spaceIndex, $lineChangeIndicator) = ("", 0, 0);

	foreach(@parsedVersionData) {
		if ($lineChangeIndicator == 2) {
            my $size = Common::getHumanReadableSizes($_);
            $tableContent .= $size . (' ') x ($columnNames[1]->[$spaceIndex] - length($size));
			$tableContent .= "\n";
			($lineChangeIndicator, $spaceIndex) = (0) x 2;
		} else {
            $tableContent .= $_ . (' ') x ($columnNames[1]->[$spaceIndex] - length($_));
			$spaceIndex++;
			$lineChangeIndicator += 1;
		}
	}

	if ($tableContent ne '') {
		Common::display([$tableHeader . $tableContent]);
	} else {
		Common::display(["\n",'no_version_found',"\n",'exiting_title',"...\n"]);
		exit(0);
	}
}

#********************************************************************************
# Subroutine			: getFileVersions.
# Objective				: Gets versions of user's requested file
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#********************************************************************************
sub getFileVersions {
	Common::createUTF8File('FILEVERSION', $fullFilePath) or Common::retreat('failed_to_create_utf8_file');
	my @result = Common::runEVS('item');
	my $errorMessageHandler = {
								Common::getStringConstant('no_version_found') => '"'.Common::getStringConstant('no_version_found_for_given_file').'."',
								Common::getStringConstant('path_not_found') => '"'.Common::getStringConstant('could_not_find_given_file').'."',
								'cleanupOperation' => sub {Common::display(['exiting_title']); exit(0);}
							};

	if ($result[0]{'STATUS'} eq 'FAILURE') {
		my $errorMessage = $result[0]{'MSG'};
		$errorMessage =~ s/^\s+|\s+$//g;

		if ($errorMessage ne '') {
			if ($errorMessage =~ /password mismatch|encryption verification failed|encryption_verification_failed/i) {
				Common::createBackupStatRenewalByJob('backup') if(Common::getUserConfiguration('DEDUP') ne 'on');
				Common::display([$errorMessage, '. ', 'please_login_account_using_login_and_try']);
				unlink(Common::getIDPWDFile());
			}
			elsif ($errorMessage =~ /failed to get the device information|Invalid device id/gi) {
				Common::display(['invalid_res_loc_edit_loc_acc_settings', "\n"]);
			}
			elsif ($errorMessage =~/No version found/i || $errorMessage =~ /path not found/i) {
				Common::display([$errorMessageHandler->{"$&"}]);
			}
			elsif ($errorMessage =~ /device is deleted\/removed/i) {
				Common::deleteBackupDevice();
				Common::retreat('unable_to_find_your_restore_location');
			}
			else {
				$errorMessage = Common::checkErrorAndLogout($errorMessage, undef, 1);
				Common::display([$errorMessage, "\n"]);
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
        push(@fileVersionData, $_[($serialNumber - 1)]{'size'});
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
	Common::display('');
	my $filePath = Common::getAndValidate(['enter_your_file_path',': '], 'non_empty', 1);
	Common::Chomp(\$filePath);

	my $fileRestoreHost = Common::getUserConfiguration('RESTOREFROM');

	# $fileRestoreHost has the value: DEVICEID#HOSTNAME, so unset it
	$fileRestoreHost = "" if (Common::getUserConfiguration('DEDUP') eq 'on');

	my $fullFilePath = (substr($filePath, 0, 1) ne "/")? $fileRestoreHost . "/" . $filePath : $fileRestoreHost . $filePath;
	return $fullFilePath;
}

1;
