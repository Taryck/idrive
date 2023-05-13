#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to edit the supported files like Backup/Restore set files for both normal and scheduled
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Fcntl qw(:flock SEEK_END);

use Common;
use AppConfig;
use File::Basename;

eval {
	require File::Copy;
	File::Copy->import();
};

use File::stat;
use POSIX;
use POSIX ":sys_wait_h";

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
	Common::verifyVersionConfig();
	Common::loadUsername() or Common::retreat('login_&_try_again');
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);
	Common::isLoggedin() or Common::retreat('login_&_try_again');

	Common::displayHeader();

	Common::checkAccountStatus(1);

	my $hasnotif = Common::hasFileNotifyPreReq();
	unless(Common::isCDPWatcherRunning()) {
		Common::display(['cdp_service_not_running', '.']) if($hasnotif);
		Common::startCDPWatcher(1);
		if($hasnotif) {
			# Watcher has to start the job. client takes sometime to start
			Common::isCDPWatcherRunning()? Common::display(['cdp_service_started', '.']) : Common::display(['failed_to_start_cdp_service', '.']);
		}
	}

	# Handle manual script update. If aborted at account settings login, migration won't happen.
	Common::fixBackupsetDeprecations();

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

			my $editFilePathPid = Common::getJobsPath($menuToPathMap{$menuUserChoice}) . $AppConfig::pidFile;
			if(-f $editFilePathPid) {
				open(my $fh, ">>", $editFilePathPid) or return 0;
				unless (flock($fh, LOCK_EX|LOCK_NB)) {
					Common::display(["\n", $menuToPathMap{$menuUserChoice} . '_in_progress_try_again']);
					Common::display(["\n", 'do_you_want_to_edit_any_other_files_yn']);
					$continueMenu = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
					($continueMenu eq 'y')?	next : exit;
				} else {
					unlink($editFilePathPid);
				}
			}

			$editFilePath = Common::getJobsPath($menuToPathMap{$menuUserChoice}, 'file');
			$fileType = $menuToPathMap{$menuUserChoice};
		}

		if($fileType eq 'localrestore') {
            $AppConfig::jobType	= "LocalRestore";
			Common::display("");
			getMountPointAndVerifyDB();
			# (-f $editFilePath)? Common::openEditor('edit', $editFilePath, $fileType) : Common::display(['unable_to_open', '. ', 'invalid_file_path', ' ', '["', $editFilePath, '"]']);
		} elsif($fileType eq 'restore') {
			Common::editRestoreFromLocation();
			Common::saveUserConfiguration() or Common::retreat('failed_to_save_user_configuration');
		}

		# create jobset file if missing, incase of permission issues it may fail to create and will be handled from the below condition
		Common::fileWrite($editFilePath, '') unless(-f $editFilePath);

		if(-f $editFilePath) {
			if($menuToPathMap{$menuUserChoice} eq 'backup' || $menuToPathMap{$menuUserChoice} eq 'localbackup') {
				my $oldbkpsetfile	= qq($editFilePath$AppConfig::backupextn);
				copy($editFilePath, $oldbkpsetfile);

				my $transfile		= Common::getCatfile(dirname($editFilePath), $AppConfig::transBackupsetFile);
				my $transcont		= Common::getDecBackupsetContents($editFilePath);

				Common::fileWrite($transfile, $transcont);
				$editFilePath		= $transfile;
			}

			Common::openEditor('edit', $editFilePath, $fileType);
			unlink($editFilePath) if (-f $editFilePath && $fileType =~ /backup/i);
		} else {
			Common::display(['unable_to_open', '. ', 'invalid_file_path', ' ', '["', $editFilePath, '"]']);
		}

		if ($menuToPathMap{$menuUserChoice} =~ '_exclude') {
			Common::updateExcludeFileset($editFilePath, $menuToPathMap{$menuUserChoice});
			Common::createJobSetExclDBRevRequest((split("_exclude", $menuToPathMap{$menuUserChoice}))[0]);
		}

		Common::display(['do_you_want_to_edit_any_other_files_yn']);
		$continueMenu = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1, 1);
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
		'local_backup'   => ['localbackup'],
		'exclude'        => ['full_exclude', 'partial_exclude', 'regex_exclude'],
		'restore'        => ['restore'],
		'local_restore'  => ['localrestore'],
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

#*****************************************************************************************************
# Subroutine			: getMountPointAndVerifyDB
# Objective				: This function will get mount point & verify the DB
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getMountPointAndVerifyDB {
	my $username    = Common::getUsername();
	my $dedup  	    = Common::getUserConfiguration('DEDUP');
	my $mountedPath = Common::getMountedPathForRestore();
	$AppConfig::localMountPath	= $mountedPath;
	Common::checkPidAndExit(); #Checking pid if process cancelled by job termination

	my $expressLocalDir = Common::getCatfile($mountedPath, ($AppConfig::appType . 'Local'));
	my $localUserPath   = Common::getCatfile($expressLocalDir, $username);
=beg
	my $ldbNewDirPath	= Common::getCatfile($localUserPath, $AppConfig::ldbNew);
	unless(-d $ldbNewDirPath or ($dedup eq 'on' and !-e $localUserPath."/".$AppConfig::dbPathsXML)){
		Common::startDBReIndex($mountedPath);
	}
	if($dedup eq 'on' and !-e $localUserPath."/".$AppConfig::dbPathsXML) {
		Common::retreat(['mount_point_doesnt_have_user_data',"\n"]);
	}
=cut

	Common::setUserConfiguration('LOCALRESTOREMOUNTPOINT', $mountedPath);
	Common::saveUserConfiguration() or Common::retreat('failed_to_save_user_configuration');

    if ($dedup eq 'on') {
		my @backupLocationDir = Common::getUserBackupDirListFromMountPath($localUserPath);
		if(scalar(@backupLocationDir)>0) {
			Common::checkAndCreateDBpathXMLfile($localUserPath, \@backupLocationDir);
		}
	}
	Common::editLocalRestoreFromLocation();

    my $serverRoot = '';
	if($dedup eq 'on'){
		$serverRoot = Common::getUserConfiguration('LOCALRESTORESERVERROOT');
	}

	my $restoreFrom  = ($dedup eq 'on')?$serverRoot:Common::getUserConfiguration('LOCALRESTOREFROM');
	my $backedUpData = Common::getCatfile($localUserPath, $restoreFrom);

    if(!-d $backedUpData){
        $restoreFrom  = Common::getUserConfiguration('LOCALRESTOREFROM');
        my $error = Common::getStringConstant('local_restore_from_doesnt_have_data');
        $error =~ s/<DATA>/$restoreFrom/; 
		Common::retreat($error);
	}

=beg
	my $databaseLB  = Common::getExpressDBPath($mountedPath,$serverRoot);
	if(!-f $databaseLB){
		Common::startDBReIndex($mountedPath);
	}

	if(!-e $databaseLB){
		Common::retreat('No database');
	}
=cut

}

