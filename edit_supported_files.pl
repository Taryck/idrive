#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to edit the supported files like Backup/Restore set files for both normal and scheduled
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;
use File::Basename;

Common::waitForUpdate();
Common::initiateMigrate();

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
# Modified By			: Anil Kumar [04/05/2018], Yogesh Kumar
#****************************************************************************************************/
sub init {
	system(Common::updateLocaleCmd('clear'));
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::loadUsername() or Common::retreat('login_&_try_again');
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);
	Common::isLoggedin() or Common::retreat('login_&_try_again');

	Common::displayHeader();
	Common::checkAccountStatus(1);

	my ($continueMenu, $menuUserChoice, $editFilePath, $maxMenuChoice) = ('y', 0, '', 0);
	my (%menuToPathMap, $fileType);
	while($continueMenu eq 'y') {
		$maxMenuChoice = displayMenu(\%menuToPathMap);

		Common::display(["\n", '__note_please_press_ctrlc_exit']);
		$menuUserChoice = Common::getUserMenuChoice($maxMenuChoice);
		$menuUserChoice += 0;

		my $propSettings = Common::getPropSettings('master');

		if ($menuToPathMap{$menuUserChoice} =~ '_exclude') {
			if ($menuToPathMap{$menuUserChoice} eq 'partial_exclude') {
				if (exists $propSettings->{'set'} and exists $propSettings->{'set'}{'lst_partexclude'} and
					$propSettings->{'set'}{'lst_partexclude'}{'islocked'}) {
					Common::display(["\n", 'admin_has_locked_settings', "\n"]);
					next;
				}
			}
			$editFilePath   = Common::getUserFilePath($AppConfig::excludeFilesSchema{$menuToPathMap{$menuUserChoice}}{'file'});
			$fileType  = $AppConfig::excludeFilesSchema{$menuToPathMap{$menuUserChoice}}{'title'};
		}
		else {
			if (($menuToPathMap{$menuUserChoice} eq 'backup') and exists $propSettings->{'bkpset_linux'} and exists $propSettings->{'bkpset_linux'}{'Default BackupSet'} and $propSettings->{'bkpset_linux'}{'Default BackupSet'}{'islocked'}) {
				Common::display(["\n", 'admin_has_locked_settings', "\n"]);
				next;
			}
			elsif (($menuToPathMap{$menuUserChoice} eq 'localbackup') and exists $propSettings->{'bkpset_linux'} and exists $propSettings->{'bkpset_linux'}{'LocalBackupSet'} and $propSettings->{'bkpset_linux'}{'LocalBackupSet'}{'islocked'}) {
				Common::display(["\n", 'admin_has_locked_settings', "\n"]);
				next;
			}

			my $editFilePathPid = Common::getJobsPath($menuToPathMap{$menuUserChoice}).$AppConfig::pidFile;
			if(-e $editFilePathPid){
				open(my $fh, ">>", $editFilePathPid) or return 0;
				unless (flock($fh, 2|4)) {
					Common::display(["\n",$menuToPathMap{$menuUserChoice}.'_in_progress_try_again']);
					Common::display(["\n",'do_you_want_to_edit_any_other_files_yn']);
					$continueMenu = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
					($continueMenu eq 'y')?	next:exit;
				}else{
					flock($fh, 8);
				}
			}

			$editFilePath = Common::getJobsPath($menuToPathMap{$menuUserChoice}, 'file');
			$fileType = $menuToPathMap{$menuUserChoice};
		}
		if($fileType eq 'restore') {
			Common::editRestoreFromLocation();
			Common::saveUserConfiguration() or Common::retreat('failed_to_save_user_configuration');
		}
		(-f $editFilePath)? Common::openEditor('edit', $editFilePath, $fileType) : Common::display(['unable_to_open', '. ', 'invalid_file_path', ' ', '["', $editFilePath, '"]']);

		if ($menuToPathMap{$menuUserChoice} =~ '_exclude') {
			Common::updateExcludeFileset($editFilePath, $menuToPathMap{$menuUserChoice});
			calculateJobsetSize('backup');
			calculateJobsetSize('localbackup');
		}
		else {
			Common::updateJobsFileset($editFilePath, $menuToPathMap{$menuUserChoice});
			calculateJobsetSize($menuToPathMap{$menuUserChoice}) if($menuToPathMap{$menuUserChoice} eq 'backup' || $menuToPathMap{$menuUserChoice} eq 'localbackup');
		}

		Common::display(['do_you_want_to_edit_any_other_files_yn']);
		$continueMenu = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}
}

#*****************************************************************************************************
# Subroutine			: calculateJobsetSize
# Objective				: Helps calculate backupset size
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub calculateJobsetSize {
	my $backupsizelock = Common::getBackupsetSizeLockFile($_[0]);
	return 0 if(Common::isFileLocked($backupsizelock));

	my $calcforkpid = fork();
	if($calcforkpid == 0) {
		$0 = 'IDrive:esf:szcal';
		Common::calculateBackupsetSize($_[0]);
		while(1) {
			if (Common::isFileLocked($backupsizelock)) {
				sleep(1);
			}
			else {
				last;
			}
		}

		Common::loadNotifications() and Common::setNotification(sprintf("get_%sset_content", $_[0])) and Common::saveNotifications();
		exit(0);
	}
}

#*****************************************************************************************************
# Subroutine			: displayMenu
# Objective				: Helps to display the menu
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub displayMenu {
	my ($opIndex, $pathIndex) = (1, 1);
	my @fileMenuOptions;

	tie (our %editFileOptions, 'Tie::IxHash',
		'backup'         => ['backup'],
		'express_backup' => ['localbackup'],
		'exclude'        => ['full_exclude', 'partial_exclude', 'regex_exclude'],
		'restore'        => ['restore'],
	);

	Common::display(['menu_options_title', ':', "\n"]);

	foreach my $mainOperation (keys %editFileOptions) {
		Common::display([$mainOperation . '_title', ':']);
		@fileMenuOptions = @{$editFileOptions{$mainOperation}};
		foreach (@fileMenuOptions) {
			Common::display(["\t" . $opIndex++ . ') ', "edit_$_\_file"]);
		}
		%{$_[0]} = (%{$_[0]}, map{$pathIndex++ => $_} @fileMenuOptions);
	}

	return $opIndex - 1;
}
