#!/usr/bin/env perl
#*****************************************************************************************************
# Schedule IDrive jobs
#
# Created By: Yogesh Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common qw(display createCrontab loadCrontab getCrontab prettyPrint setCrontab retreat);
use AppConfig;

eval {
	if($AppConfig::appType eq 'IDrive') {
		require PropSchema;
	}
};

my $cmdNumOfArgs = $#ARGV;
Common::waitForUpdate();
Common::initiateMigrate();

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub init {
	Common::loadAppPath();
	Common::loadServicePath() or retreat('invalid_service_directory');
	Common::loadUsername() or retreat('login_&_try_again');
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);
	Common::loadEVSBinary() or retreat('unable_to_find_or_execute_evs_binary');
	Common::isLoggedin() or retreat('login_&_try_again');
	Common::displayHeader();

	# check the status of cron job, if not runnig ask the user to start the cron
	unless(Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
		display(['cron_service_not_running', '.']);
		my $res = Common::confirmRestartIDriveCRON();
		unless(Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
			if($AppConfig::mcUser eq 'root') {
				Common::retreat(['please_try_again', '.']);
			} else {
				Common::retreat(['please_make_sure_you_are_sudoers_list_and_try']);
			}
		}
	}

	checkActiveDashboard() if($AppConfig::appType eq 'IDrive');

	my @jobTypes = ("backup", "express_backup", "archive");
	my @jobNames = ("default_backupset", "local_backupset", "default_backupset");

	displayCrontab('tableHeader', " ", " ");
	loadCrontab(1);
	for my $i (0 .. $#jobNames) {
		createCrontab($jobTypes[$i], $jobNames[$i]) or retreat('failed_to_load_crontab');
		displayCrontab('table', $jobTypes[$i], $jobNames[$i]);
	}

	loadCrontab(1);

	tie(my %optionsInfo, 'Tie::IxHash',
		'schedule_your_backup_job' => \&scheduleBackupJob,
		'disable_scheduled_backup_job' => \&disable,
		'schedule_your_express_backup_job' => \&scheduleExpressBackupJob,
		'disable_scheduled_express_backup_job' => \&disable,
		'schedule_your_archive_job' => \&scheduleArchiveJob,
		'disable_scheduled_archive_job' => \&disable,
		'exit' => sub {
			exit 0;
		},
	);

	for my $i (0 .. $#jobNames)
	{
		if (getCrontab($jobTypes[$i], $jobNames[$i], '{settings}{status}') ne 'enabled') {
			delete $optionsInfo{'disable_scheduled_'.$jobTypes[$i].'_job'};
		}
	}

	my @options = keys %optionsInfo;

	while(1) {
		display(["\n", 'menu_options', ":\n"]);
		Common::displayMenu('enter_your_choice', @options);
		my $userSelection = Common::getUserChoice();
		if (Common::validateMenuChoice($userSelection, 1, scalar(@options))) {
			#$optionsInfo{$options[$userSelection - 1]}->($jobType, $jobName);
			$optionsInfo{$options[$userSelection - 1]}->($options[$userSelection - 1]);
			last;
		}
		else{
			display(['invalid_choice', ' ', 'please_try_again', '.']);
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkActiveDashboard
# Objective				: This function is to check active script directories.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkActiveDashboard {
	loadCrontab(1);
	my $crontab 	= Common::getCrontab();
	return 0 unless(exists $crontab->{$AppConfig::mcUser} && exists $crontab->{$AppConfig::mcUser}{Common::getUsername()});

	my %usercrons	= %{$crontab->{$AppConfig::mcUser}{Common::getUsername()}};
	return 0 unless(%usercrons);

	my $curdashpath	= Common::getScript($AppConfig::dashbtask);
	my $dashcmd 	= (($usercrons{$AppConfig::dashbtask})? $usercrons{$AppConfig::dashbtask}{$AppConfig::dashbtask}{'cmd'} : '');

	if(defined($dashcmd) && $dashcmd ne '' && ($dashcmd ne $curdashpath)) {
		Common::display(["\n", 'user', ' "', Common::getUsername(), '" ', 'is_already_having_active_setup_path', '.']);
		Common::retreat(['re_configure_your_account_freshly', '.']);
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: scheduleArchiveJob
# Objective				: This function is used to schedule the archive job
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub scheduleArchiveJob {
	my $opType = 0;
	my $jobType  = "archive";
	my $jobName = "default_backupset";
	my $backupType  = Common::getUserConfiguration('BACKUPTYPE');
	my $locktype	= 'arch_cleanup_checked';
	my @archlocks 	= ();
	@archlocks 	= PropSchema::getLockedArchiveFields() if($AppConfig::appType eq 'IDrive');
	unless($backupType =~ /mirror/){
		Common::retreat('backup_type_must_be_mirror');
		exit 0;
	}

	if(grep(/^$locktype$/, @archlocks)) {
		display(["\n", 'admin_has_locked_settings']);
		if(getCrontab($jobType, $jobName, '{settings}{status}') eq 'disabled') {
			# display(['your_archive_job_has_been_disabled_admin']);
			return 1;
		}

		my $cmd = getCrontab($jobType, $jobName, '{cmd}');
		my $fre = "daily";
		if($cmd ne "") {
			my @params = split(' ', $cmd);
			my $paramSize = @params;
			$fre = "every\ " . ordinal($params[$paramSize-3]) . "\ Day";
		}

		display(['your_archive_cleanup_schedule', ': ', $fre, ' at ',
			getCrontab($jobType, $jobName, '{h}'), ':', getCrontab($jobType, $jobName, '{m}'), '.']);

		return 1;
	} else {
		display(["\n", "enter_percentage_of_files_for_cleanup_periodic"], 1);
		my $percentage = Common::getAndValidate(['enter_percentage_of_files_for_periodic_cleanup'], "periodic_cleanup_per", 1);

		display(["\n", "number_of_days_of_the_month_after_which_it_should_be_automatically_cleaned_up"], 1);
		my $noOfDays = Common::getAndValidate(['enter_the_days_for_cleanup'], "periodic_cleanup_days", 1);

		setCrontab($jobType, $jobName, 'cmd', "$noOfDays $percentage");
		setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
		setCrontab($jobType, $jobName, {'settings' => {'frequency' => ' '}});
	}

	updateInfoDetails($jobType, $jobName, 2);
}

#*****************************************************************************************************
# Subroutine			: updateInfoDetails
# Objective				: This function is used to update the job details
# Added By				: Anil Kumar
# Modified By 		: Yogesh Kumar
#****************************************************************************************************/
sub updateInfoDetails {
	my $jobType = $_[0];
	my $jobName = $_[1];
	my $backupType = $_[2];

	if (getCrontab($jobType, $jobName, '{settings}{status}') eq 'enabled') {
		Common::setCronCMD($jobType, $jobName);
		updateEmailIDs($jobType, $jobName) if($jobType ne "archive");
	}
	if (getCrontab('cancel', $jobName, '{settings}{status}') eq 'enabled') {
		Common::setCronCMD('cancel', $jobName);
	}

	Common::saveCrontab();
	if (($jobType eq 'backup') and Common::loadNotifications()) {
		Common::setNotification('get_scheduler') and Common::saveNotifications();
		if (Common::getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'no_scheduled_jobs'}) {
			Common::setNotification('alert_status_update', 0) and Common::saveNotifications();
		}
	}

	#need to check the backup set file to confirm whether it is empty or not.
	my ($jobRunningDir, $backupsetType) = ("") x 2;
	if ($jobType eq "express_backup") {
		$jobRunningDir = Common::getJobsPath('localbackup');
		$backupsetType = 'express backupset';
	} else {
		$jobRunningDir = Common::getJobsPath($jobType);
		$backupsetType = 'backupset';
	}
	my $backupsetFile = Common::getCatfile($jobRunningDir, $AppConfig::backupsetFile);

	if ($backupType == 0) {
		displayCrontab('string', $jobType, $jobName);
	} elsif($backupType == 1) {
		display(["\n", $jobType.'_job_started_successfully'], 1) if(-s $backupsetFile);
	} else {
		display(["\n", 'periodic_archive_cleanup', 'has_been_scheduled_successfully'],1);
	}

	if ((!-s $backupsetFile) and ($jobType ne "archive")) {
		display(["\n\n","Note: Your $backupsetType is empty. ", 'please_update', "\n"], 1);
	}
}

#*****************************************************************************************************
# Subroutine			: scheduleExpressBackupJob
# Objective				: This function is used to schedule the express backup job
# Added By				: Anil Kumar
#****************************************************************************************************/
sub scheduleExpressBackupJob {
	my $localMountPoint = Common::getUserConfiguration('LOCALMOUNTPOINT');
	Common::getAndSetMountedPath();
	if ($localMountPoint eq "") {
		$localMountPoint = Common::getUserConfiguration('LOCALMOUNTPOINT');
	}

	my $backupType = 0;
	my $jobType  = "express_backup";
	my $jobName = "local_backupset";

	#display(["\n", "your_expressbackup_to_device_name_is", ' "', $localMountPoint,"\"."], 1);
	$backupType = updateBackupType($jobType, $jobName);

	updateInfoDetails($jobType, $jobName, $backupType);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: scheduleBackupJob
# Objective				: This function is used to schedule the backup job
# Added By				: Anil Kumar
#****************************************************************************************************/
sub scheduleBackupJob {
	my $backupType = 0;
	my $jobType  = "backup";
	my $jobName = "default_backupset";

	display(["\n", "your_backup_to_device_name_is", ' "', (Common::getUserConfiguration('DEDUP') eq 'on') ? (split('#', (Common::getUserConfiguration('BACKUPLOCATION'))))[1] :  Common::getUserConfiguration('BACKUPLOCATION'),"\"."], 0);

	if (Common::getUserConfiguration('DEDUP') eq 'off') {
		display([' ', 'do_you_really_want_to_edit_(_y_n_)', '?']);
		my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);

		if ($yesorno eq 'y') {
			Common::setBackupToLocation();
			Common::saveUserConfiguration() or retreat('failed_to_save_user_configuration');
		}
	}

	display('');
	$backupType = updateBackupType($jobType, $jobName);
	updateInfoDetails($jobType, $jobName, $backupType);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateBackupType
# Objective				: This function is used to descide the backup type (Schedule/Start Immediately)
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub updateBackupType {
	# dashboard allows schedule modification even if the job is in progress
	# need to check whether any scheduled job is running or not.
	# checkRunningJobs($_[0]);

	my @schlocks 	= ();
	@schlocks 	= PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my $freqtype		= (($_[0] eq 'backup')? 'backup_freq' : 'localbackup_freq');
	my $timetype		= (($_[0] eq 'backup')? 'backup_nxttrftime' : 'localbackup_nxttrftime');
	my $userSelection	= 1;

	unless(grep(/^$freqtype$/, @schlocks)) {
		display(['select_backup_schedule', ":\n"]);
		my @options = (
			'schedule_backup_for_later',
			'start_backup_immediately',
		);

		Common::displayMenu('', @options);
		$userSelection		= Common::getUserMenuChoice(scalar(@options));
		$userSelection		=~ s/0//g;
	} else {
		display(["\n", 'admin_has_locked_settings']);
		display(['current_backup_schedule', ': ', ucfirst(getCrontab($_[0], $_[1], '{settings}{frequency}'))]);
		$userSelection		= ((getCrontab($_[0], $_[1], '{settings}{frequency}') eq 'immediate')? 2 : 1);
	}

	if ($userSelection eq 1) {
		updateCrontab($_[0], $_[1]);
		return 0;
	} else {
		# check for empty backup set and exit if empty
		my ($jobRunningDir, $backupsetType) = ('') x 2;
		if($_[0] eq "express_backup") {
			$jobRunningDir = Common::getJobsPath("localbackup");
			$backupsetType = 'express backupset';
		} else {
			my $isArchiveRunning = 1;
			$isArchiveRunning = Common::isJobRunning('archive');
			if($isArchiveRunning){
				display(["\n", 'archive_in_progress_try_again'], 1);
				exit 0;
			}
			$jobRunningDir = Common::getJobsPath($_[0]);
			$backupsetType = 'backupset';
		}

		my $backupsetFile	= Common::getCatfile($jobRunningDir, $AppConfig::backupsetFile);
		if(!-f $backupsetFile || -z $backupsetFile) {
			# display(["\n\n", "Note: Your $backupsetType is empty. ", 'please_update', ' ', 'please_try_again', '.', "\n"], 1);
			display(["\n\n", "Note: Your $backupsetType is empty. ", 'please_update', ' ', "\n"], 1);
			exit(0);
		}

		goToCutOff($_[0], $_[1], "immediate");
		return 1;
	}
}

#*****************************************************************************************************
# Subroutine			: goToCutOff
# Objective				: This function Start jobs immediately with the cutoff details.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub goToCutOff {
	my $jobType = $_[0] || retreat('jobname_is_required');
	my $jobName = $_[1] || retreat('jobtitle_is_required');

	my @schlocks 	    = ();
	@schlocks 		    = PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my $cutofftype		= (($jobType eq 'backup')? 'backup_cutoff' : 'localbackup_cutoff');
	my $freqtype		= (($jobType eq 'backup')? 'backup_freq' : 'localbackup_freq');
	my $timetype		= (($jobType eq 'backup')? 'backup_nxttrftime' : 'localbackup_nxttrftime');

	my $jobRunningDir = Common::getUserProfilePath();
	#Getting working dir path and loading path to all other files
	if ($jobType eq "backup") {
		$jobRunningDir = $jobRunningDir."/Backup/DefaultBackupSet";
	} elsif($jobType eq "express_backup") {
		$jobRunningDir = $jobRunningDir."/Backup/LocalBackupSet";
	}

	#Checking if another job is already in progress
	my $pidPath = "$jobRunningDir/pid.txt";

	if(Common::isFileLocked($pidPath)) {
		Common::retreat("Job is already in progress.");
	}

	if($_[2] eq 'hourly' && grep(/^$timetype$/, @schlocks)) {
		display(["\n", 'admin_has_locked_settings']);
		display(['current_backup_timing', ': ', 'hourly basis at ', ordinal(getCrontab($jobType, $jobName, '{m}')), ' minutes']);
	}

	if(grep(/^$cutofftype$/, @schlocks)) {
		display(["\n", 'admin_has_locked_settings']);
		if(getCrontab('cancel', $jobName, '{settings}{status}') eq 'enabled') {
			display(['current_cutoff_timing', ': ' ], 0);
			display([getCrontab('cancel', $jobName, '{h}'), ':', getCrontab('cancel', $jobName, '{m}')]);
		} else {
			display(['cutoff_is_disabled']);
		}
	} else {
		display(["\n", 'do_you_want_to_have_cut_off_time_for_your_backup_y_n']);
		my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);

		if ($yesorno eq 'y') {
			createCrontab('cancel', $jobName) or retreat('failed_to_load_crontab');
			my $timeDiff = 0;
			my $cutoffHour;
			my $cutoffMinute;
			while(1) {
				$cutoffHour = Common::getAndValidate(['enter_hour_0_-_23', ': '], '24hours_validator', 1);
				setCrontab('cancel', $jobName, 'h', sprintf("%02d", $cutoffHour));

				$cutoffMinute = Common::getAndValidate(['enter_minute_0_-_59', ': '], 'minutes_validator', 1);
				setCrontab('cancel', $jobName, 'm', sprintf("%02d", $cutoffMinute));

				last;
			}

			setCrontab('cancel', $jobName, {'settings' => {'status' => 'enabled'}});
		}
		else {
			setCrontab('cancel', $jobName, 'h', sprintf("%2d", 00));
			setCrontab('cancel', $jobName, 'm', sprintf("%2d", 00));
			setCrontab('cancel', $jobName, {'settings' => {'status' => 'disabled'}});
		}
	}

	# Cutoff always depend on schedule. Hour and minutes are valid for cutoff | This can be hourly or immediate
	setCrontab('cancel', $jobName, 'dow', '*');
	setCrontab('cancel', $jobName, 'mon', '*');
	setCrontab('cancel', $jobName, 'dom', '*');

	setCrontab($jobType, $jobName, {'settings' => {'frequency' => $_[2]}});

	my @now			= localtime;
	my $startTime	= $now[1] + 1;
	$startTime		= 0 if($startTime > 59);

	if($_[2] eq 'hourly' && grep(/^$timetype$/, @schlocks)) {
		#display(["\n", 'admin_has_locked_settings']);
		#display(['current_backup_timing', ': ', 'hourly basis at ', ordinal(getCrontab($jobType, $jobName, '{m}')), ' minutes']);
		$startTime = getCrontab($jobType, $jobName, '{m}');
	}

	setCrontab($jobType, $jobName, 'm', $startTime);
	setCrontab($jobType, $jobName, 'h', '*');
	setCrontab($jobType, $jobName, 'dow', '*');
	setCrontab($jobType, $jobName, 'mon', '*');
	setCrontab($jobType, $jobName, 'dom', '*');

	# if(!grep(/^$timetype$/, @schlocks) && !grep(/^$freqtype$/, @schlocks) && !grep(/^$cutofftype$/, @schlocks)) {
		setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
	#}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: displayCrontab
# Objective				: This function is used to dispaly the cron jobs.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub displayCrontab {
	my $displayFormat = $_[0] || 'table';

	my $jobType  = $_[1] || retreat('jobname_is_required');
	my $jobName = $_[2]  || retreat('jobtitle_is_required');
	if ($displayFormat eq 'tableHeader') {
		display(["\n", 'your_scheduled_job_details_are_mentioned_below', ':',"\n"], 1);
		display('=' x 110);
		prettyPrint(['-16s', 'job_name'], ['-9s', 'status'], ['-25s', 'frequency'], ['-16s', 'scheduled_time'], ['-16s', 'cut_-_off'], ['-16s', 'cut_-_off_time'], ['-16s', 'start_date']);
		display(["\n", '=' x 110]);
	}
	elsif ($displayFormat eq 'table') {
		my $startDate = "NA";
		prettyPrint(['-16s', $jobType.'_title'], ['s', Common::colorScreenOutput(getCrontab($jobType, $jobName, '{settings}{status}'), '9s')]);

		if (((getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'daily') || (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'hourly')) && ($jobType ne "archive")) {
			prettyPrint(['-25s', getCrontab($jobType, $jobName, '{settings}{frequency}')]);
		}elsif (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'weekly')  {
			if (getCrontab($jobType, $jobName, '{dow}') eq join(',', @AppConfig::weekdays)) {
				prettyPrint(['-25s', 'weekdays']);
			}
			elsif (getCrontab($jobType, $jobName, '{dow}') eq join(',', @AppConfig::weekends)) {
				prettyPrint(['-25s', 'weekends']);
			}
			else {
				if(getCrontab($jobType, $jobName, '{dow}') eq '*') {
					prettyPrint(['-25s', 'NA']);
				} else {
					prettyPrint(['-25s', getCrontab($jobType, $jobName, '{dow}')]);
				}
			}
		}elsif (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'immediate') {
			prettyPrint(['-25s', getCrontab($jobType, $jobName, '{settings}{frequency}')]);
		}

		if($jobType eq "archive"){
			my $cmd = getCrontab($jobType, $jobName, '{cmd}');
			my $fre = "daily";
			if($cmd ne "") {
				my @params = split(' ', $cmd);
				my $paramSize = @params;
				($fre, $startDate) = ("--") x 2;
				$fre = "every\ ".ordinal($params[$paramSize-3])."\ Day" if(Common::validateMenuChoice($params[$paramSize-3], 5, 30));
				$startDate = Common::strftime('%Y-%m-%d', localtime($params[$paramSize-1])) if($params[$paramSize-1]);
			}
			prettyPrint(['-25s', $fre]);

			prettyPrint(['.2d', getCrontab($jobType, $jobName, '{h}')], ['s', ':'], ['-13.2d', getCrontab($jobType, $jobName, '{m}')],
			['s', Common::colorScreenOutput('disabled', '16s')],
			['.2d', '00'], ['s', ':'], ['-13.2d', '00'],
			['9s', $startDate]);
		}
		else {
			if(getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'hourly') {
				my $zeroapp = (getCrontab($jobType, $jobName, '{m}') <= 9)? '0' : '';
				prettyPrint(['4s', $zeroapp . ordinal(getCrontab($jobType, $jobName, '{m}')), '4s'], ['1s', ''], ['6s', ucfirst('minute')], ['5s', ''], ['s', Common::colorScreenOutput(getCrontab('cancel', $jobName, '{settings}{status}'), '16s')], ['.2d', getCrontab('cancel', $jobName, '{h}')], ['s', ':'], ['-13.2d', getCrontab('cancel', $jobName, '{m}')], ['9s', $startDate]);
			} else {
				prettyPrint(['.2d', ((getCrontab($jobType, $jobName, '{h}') eq '*')?'00':getCrontab($jobType, $jobName, '{h}'))], ['s', ':'], ['-13.2d', getCrontab($jobType, $jobName, '{m}')], ['s', Common::colorScreenOutput(getCrontab('cancel', $jobName, '{settings}{status}'), '16s')], ['.2d', getCrontab('cancel', $jobName, '{h}')], ['s', ':'], ['-13.2d', getCrontab('cancel', $jobName, '{m}')], ['9s', $startDate]);
			}

		}
		display('');
	}
	else {
		#if (getCrontab($jobType, $jobName, '{settings}{status}') eq 'enabled') {
			my $tempJobType = ($jobType eq 'archive')?"periodic_archive_cleanup":$jobType;
			display([ "\n", $tempJobType, 'job_has_been_scheduled_successfully_on' ], 0);

			if (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'daily') {
				display(lc(getCrontab($jobType, $jobName, '{settings}{frequency}')), 0);
			}
			elsif (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'hourly') {
				display("on ".lc(getCrontab($jobType, $jobName, '{settings}{frequency}')), 0);
			}
			else {
				display(uc(getCrontab($jobType, $jobName, '{dow}')), 0);
			}

			if (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'hourly') {
				display([' basis at', ' ', getCrontab($jobType, $jobName, '{m}'), ' minutes'], 0);
			} else {
				display([ ' ', 'at', ' ', getCrontab($jobType, $jobName, '{h}'), ':', getCrontab($jobType, $jobName, '{m}'), ], 0);
			}

			if (getCrontab('cancel', $jobName, '{settings}{status}') eq 'enabled') {
				display([', ', 'with_cut_off_time_for'], 0);

				if (getCrontab('cancel', $jobName, '{settings}{frequency}') eq 'daily') {
					display([' ', lc(getCrontab('cancel', $jobName, '{settings}{frequency}'))], 0);
				} elsif(getCrontab('cancel', $jobName, '{dow}') ne '*') {
					display([' ', uc(getCrontab('cancel', $jobName, '{dow}'))], 0);
				}

				display([' ', 'at', ' ', getCrontab('cancel', $jobName, '{h}'), ':', getCrontab('cancel', $jobName, '{m}')], 0);
			}

			display('.');
		}
	#}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: schedule
# Objective				: This function is used to schedule the cron jobs.
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub schedule {
	my $dailySchedule = $_[0];

	my $jobType = $_[1] || retreat('jobname_is_required');
	my $jobName = $_[2] || retreat('jobtitle_is_required');

	my @schlocks 	= ();
	@schlocks 	= PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my $freqtype		= (($jobType eq 'backup')? 'backup_freq' : 'localbackup_freq');
	my $timetype		= (($jobType eq 'backup')? 'backup_nxttrftime' : 'localbackup_nxttrftime');
	my $cutofftype		= (($jobType eq 'backup')? 'backup_cutoff' : 'localbackup_cutoff');
	my ($scheduledHour, $scheduledMinute) = (0, 0);

	if(grep(/^$timetype$/, @schlocks)) {
		display(['admin_has_locked_settings']);
		$scheduledHour = getCrontab($jobType, $jobName, '{h}');
		if($scheduledHour eq '*') {
			my @now			= localtime;
			$scheduledHour	= $now[2];
			setCrontab($jobType, $jobName, 'h', sprintf("%02d", $scheduledHour));
		}
		$scheduledMinute = getCrontab($jobType, $jobName, '{m}');
		display(['scheduled_time', ': ', "$scheduledHour:$scheduledMinute", "\n"]);
	} else {
		display(["\n", 'enter_time_of_the_day_when_backup_is_supposed_to_run']);

		$scheduledHour = Common::getAndValidate(['enter_hour_0_-_23', ': '], '24hours_validator', 1);
		setCrontab($jobType, $jobName, 'h', sprintf("%02d", $scheduledHour));

		$scheduledMinute = Common::getAndValidate(['enter_minute_0_-_59', ': '], 'minutes_validator', 1);
		setCrontab($jobType, $jobName, 'm', sprintf("%02d", $scheduledMinute));
	}

	if(grep(/^$cutofftype$/, @schlocks)) {
		display(['admin_has_locked_settings']);
		if(getCrontab('cancel', $jobName, '{settings}{status}') eq 'enabled') {
			display(['current_cutoff_timing', ': ' ], 0);
			display([getCrontab('cancel', $jobName, '{h}'), ':', getCrontab('cancel', $jobName, '{m}')]);
		} else {
			display(['cutoff_is_disabled']);
		}
	} else {
		display(["\n", 'do_you_want_to_have_cut_off_time_for_your_backup_y_n']);
		my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);

		if ($yesorno eq 'y') {
			createCrontab('cancel', $jobName) or retreat('failed_to_load_crontab');
			my $timeDiff = 0;
			my $cutoffHour;
			my $cutoffMinute;
			#while(1) {
				$cutoffHour = Common::getAndValidate(['enter_hour_0_-_23', ': '], '24hours_validator', 1);
				setCrontab('cancel', $jobName, 'h', sprintf("%02d", $cutoffHour));

				$cutoffMinute = Common::getAndValidate(['enter_minute_0_-_59', ': '], 'minutes_validator', 1);
				setCrontab('cancel', $jobName, 'm', sprintf("%02d", $cutoffMinute));

				$timeDiff = ((($scheduledHour * 60) + $scheduledMinute) - (($cutoffHour * 60) + $cutoffMinute));
				# unless (($timeDiff <= -5) or ($timeDiff > 0)) {
					# display(['scheduled_time_and_cut_off_time_should_have_minimum_5_minutes_of_difference', '.']);
				# }
				#Added by Senthil for Yuvaraj_2.17_23_6
				if ($timeDiff <= -1) {
					setCrontab('cancel', $jobName, 'dow', getCrontab($jobType, $jobName, '{dow}'));
				}
				# elsif($dailySchedule) {
					# setCrontab('cancel', $jobName, 'dow', '*');
					# setCrontab('cancel', $jobName, {'settings' => {'frequency' => 'daily'}});
				# }
				#last;
			#}

			setCrontab('cancel', $jobName, 'dom', '*');
			setCrontab('cancel', $jobName, 'mon', '*');
			setCrontab('cancel', $jobName, 'dow', '*') if($dailySchedule);
			setCrontab('cancel', $jobName, {'settings' => {'status' => 'enabled'}});
		}
		else {
			setCrontab('cancel', $jobName, {'settings' => {'status' => 'disabled'}});
		}
	}

	if(!grep(/^$timetype$/, @schlocks) or !grep(/^$freqtype$/, @schlocks) or !grep(/^$cutofftype$/, @schlocks)) {
		setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
	}

	unless(grep(/^$freqtype$/, @schlocks)) {
		if ($dailySchedule) {
			setCrontab($jobType, $jobName, 'dow', '*');
			setCrontab('cancel', $jobName, 'dow', '*');
			setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'daily'}});
			setCrontab('cancel', $jobName, {'settings' => {'frequency' => 'daily'}});
		}
		else {
			setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'weekly'}});
			setCrontab('cancel', $jobName, {'settings' => {'frequency' => 'weekly'}});
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: weeklySchedule
# Objective				: This function is get the week info of the schedule
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub weeklySchedule {
	my $jobType = $_[1] || retreat('jobname_is_required');
	my $jobName = $_[2] || retreat('jobtitle_is_required');

	my $dailySchedule = 0;

	my @schlocks 	= ();
	@schlocks 		= PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my $freqtype	= (($jobType eq 'backup')? 'backup_freq' : 'localbackup_freq');

	if(grep(/^$freqtype$/, @schlocks)) {
		display(['weekly_scheduled_days', ': ', uc(getCrontab($jobType, $jobName, '{dow}')), "\n"]);

		my $wday = join(',', @AppConfig::weeks);
		my $schdow = getCrontab($jobType, $jobName, '{dow}');
		$dailySchedule = 1 if(length $schdow == length $wday);
	} else {
		display([
			"\n",
			'enter_the_day_s_of_week_for_the_scheduled_backup_job',
		]);
		display('note_:_use_comma_separator_for_selecting_multiple_days_(_e_g_1_3_5_)');

		tie(my %optionsInfo, 'Tie::IxHash',
			'mon_u' => '',
			'tue_u' => '',
			'wed_u' => '',
			'thu_u' => '',
			'fri_u' => '',
			'sat_u' => '',
			'sun_u' => '',
		);

		my @options = keys %optionsInfo;
		Common::displayMenu('', @options);
		my $wd = Common::getAndValidate('enter_your_choice', 'week_days_in_number', 1);
		$wd		=~ s/\s+//g;
		$wd		=~ s/0//g;

		my $cwd = '';

		tie(my %days, 'Tie::IxHash');
		tie(my %cdays, 'Tie::IxHash');

		my @wdin = split(',', $wd);
		@wdin = sort { $a <=> $b } @wdin;

		my @cwdin = ();

		foreach my $value (@wdin) {
			$days{$AppConfig::weeks[($value - 1)]} = '';
			$value = 0 if ($value == 7);
			push @cwdin, $value;
		}

		@cwdin = sort { $a <=> $b } @cwdin;

		foreach my $value (@cwdin) {
			$cdays{$AppConfig::weeks[$value]} = '';
		}

		my $wday = join(',', @AppConfig::weeks);

		$wd = join(',', keys %days);

		if (length $wd == length $wday) {
			$dailySchedule = 1;
			$cwd = $wd;
		}
		else {
			$cwd = join(',', keys %cdays);
		}

		setCrontab($jobType, $jobName, 'dow', $wd);
		setCrontab('cancel', $jobName, 'dow', $cwd);
	}

	return schedule($dailySchedule, $jobType, $jobName, 'weekly');
}

#*****************************************************************************************************
# Subroutine			: hourlyschedule
# Objective				: This function is used to update info of hourly schedule
# Added By				: Anil Kumar
#****************************************************************************************************/
sub hourlyschedule {
	goToCutOff($_[1], $_[2], "hourly");
}

#*****************************************************************************************************
# Subroutine			: updateCrontab
# Objective				: This function is get the describe about the type of schedule.(Daily/Weekly)
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub updateCrontab {
	my $jobType = $_[0] || retreat('jobname_is_required');
	my $jobName = $_[1] || retreat('jobtitle_is_required');

	my @schlocks 	= ();
	@schlocks 		= PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my $freqtype	= (($jobType eq 'backup')? 'backup_freq' : 'localbackup_freq');

	tie(my %optionsInfo, 'Tie::IxHash',
		'hourly_u' => \&hourlyschedule,
		'daily_u' => \&schedule,
		'weekly_u' => \&weeklySchedule
	);

	# Modified by Senthil
	if(grep(/^$freqtype$/, @schlocks)) {
		$optionsInfo{getCrontab($jobType, $jobName, '{settings}{frequency}') . '_u'}->(1, $jobType, $jobName);
	} else {
		my @options = keys %optionsInfo;
		display(['select_schedule_frequency', ":\n"]);
		Common::displayMenu('', @options);
		my $userSelection = Common::getUserMenuChoice(scalar(@options));
		$optionsInfo{$options[$userSelection - 1]}->(1, $jobType, $jobName);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: disable
# Objective				: This function is used to display the options based on the requirement.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************************************/
sub disable {
	my $operationType = $_[0];
	my $jobType = "";
	my $jobName = "";

	my @schlocks 	= ();
	@schlocks 		= PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my @archlocks 	= ();
	@archlocks 		= PropSchema::getLockedArchiveFields() if($AppConfig::appType eq 'IDrive');
	if ($operationType eq "disable_scheduled_backup_job") {
		$jobType  = "backup";
		$jobName = "default_backupset";
		if(grep(/^backup_nxttrftime$/, @schlocks) || grep(/^backup_freq$/, @schlocks) || grep(/^backup_cutoff$/, @schlocks)) {
			display(["\n", 'admin_has_locked_settings', ' ', 'unable_to_proceed']);
			return 1;
		}
	}
	elsif ($operationType eq "disable_scheduled_express_backup_job") {
		$jobType  = "express_backup";
		$jobName = "local_backupset";
		if(grep(/^localbackup_nxttrftime$/, @schlocks) || grep(/^localbackup_freq$/, @schlocks) || grep(/^localbackup_cutoff$/, @schlocks)) {
			display(["\n", 'admin_has_locked_settings', ' ', 'unable_to_proceed']);
			return 1;
		}
	}
	elsif ($operationType eq "disable_scheduled_archive_job") {
		$jobType  = "archive";
		$jobName = "default_backupset";
		if(grep(/^arch_cleanup_checked$/, @archlocks)) {
			display(["\n", 'admin_has_locked_settings', ' ', 'unable_to_proceed']);
			return 1;
		}
	}

	display(["\n", "do_you_really_want_to_disable_the_scheduled_".$jobType."_job_(_y_n_)", '?']);

	my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
	if ($yesorno eq 'y') {
		# dashboard allows schedule modification even if the job is in progress
		# checkRunningJobs($jobType);
		setCrontab($jobType, $jobName, {'settings' => {'status' => 'disabled'}});
		setCrontab('cancel', $jobName, {'settings' => {'status' => 'disabled'}});
		#$jobType =~ s/_/ /g	if($jobType eq "express_backup");
		$jobType = "periodic_archive_cleanup" if($jobType eq "archive");
		display([$jobType, 'job_has_been_disabled_successfully']);
		if ($jobType eq 'backup') {
			Common::loadNotifications() and Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'no_scheduled_jobs'}) and Common::saveNotifications();
		}
	}

	Common::saveCrontab();
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getNotificationPref
# Objective				: This subroutine helps to get notification preference
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getNotificationPref {
	my @options = keys %AppConfig::notifOptions;
	display(["\n", 'please_select_notification_preference', ":"]);
	Common::displayMenu('', @options);

	my $userSelection = Common::getUserMenuChoice(scalar(@options));
	return $AppConfig::notifOptions{$options[$userSelection - 1]};
}

#*****************************************************************************************************
# Subroutine			: updateEmailIDs
# Objective				: This function is used to update the email id for cron entries
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub updateEmailIDs {
	my $jobType = $_[0] || retreat('jobname_is_required');
	my $jobName = $_[1] || retreat('jobtitle_is_required');

	my @schlocks 	= ();
	@schlocks 		= PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my $emaillock	= (($_[0] eq 'backup')? 'backup_email' : 'localbackup_email');

	if(grep(/^$emaillock$/, @schlocks)) {
		display(["\n", 'admin_has_locked_settings']);
		display(['email_notification_status', ': ', getCrontab($jobType, $jobName, '{settings}{emails}{status}')]);

		if(getCrontab($jobType, $jobName, '{settings}{emails}{ids}') ne '') {
			display(['email_address_(_es_)', ': ', getCrontab($jobType, $jobName, '{settings}{emails}{ids}')]);
		}
	} else {
		if (getCrontab($jobType, $jobName, '{settings}{emails}{status}') eq 'disabled') {
			display(["\n", 'do_you_want_to_enable_email_notification_(_y_n_)', '?']);

			my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
			if ($yesorno eq 'y') {
				my $pref = getNotificationPref();
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => $pref}}});
			}
			else {
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
			}
		}
		else {
			if (getCrontab($jobType, $jobName, '{settings}{emails}{ids}') ne '') {
				display(["\n", 'your_email_notification_settings_are', ': ']);
				display(['email_notification_status', ': ', getCrontab($jobType, $jobName, '{settings}{emails}{status}')]);

				display(['email_address_(_es_)', ': ', getCrontab($jobType, $jobName, '{settings}{emails}{ids}')]);
			}

			display(["\n", 'do_you_want_to_disable_email_notification_(_y_n_)', '?']);
			my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
			if ($yesorno eq 'y') {
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
			}
			else {
				my $pref = getNotificationPref();
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => $pref}}});
				display(["\n", 'do_you_want_to_change_email_id_(_s_)_(_y_n_)', '?']);
				my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
				if($yesorno ne 'y') {
					return 1;
				}
			}
		}

		my $getCrontabStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}');
		if($getCrontabStatus ne 'disabled') {
			#$AppConfig::notifOptions{$getCrontabStatus}; #Commented by Senthil
			my $accemail 	= Common::getUserConfiguration('EMAILADDRESS');
			my $confemails	= '';
			if($accemail ne '') {
				display(["\n", 'configured_email_address_is', ': ', $accemail, "\n", 'do_you_want_to_use_this_email_id_for_notif_yn']);
				my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
				$confemails	= $accemail if($yesorno eq 'y');
			}

			$confemails = Common::getAndValidate(["\n", 'enter_your_e_mail_id_(_s_)_[_for_multiple_e_mail_ids_use_(_,_)_or_(_;_)_as_separator_]', ': '], 'email_address', 1, 1) if($confemails eq '');
			setCrontab($jobType, $jobName, {'settings' => {'emails' => {'ids' => $confemails}}});
		}
	}

	return 1;
}
#*****************************************************************************************************
# Subroutine			: ordinal
# Objective				: This subroutine to describe the numerical position of an number
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub ordinal {
  $_[0] = ($_[0] =~ /^\d+$/)?$_[0]:0;
  return $_.(qw/th st nd rd/)[/(?<!1)([123])$/ ? $1 : 0] for int $_[0];
}
