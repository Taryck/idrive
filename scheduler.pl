#!/usr/bin/env perl
#*****************************************************************************************************
# Schedule IDrive jobs
#
# Created By: Yogesh Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use File::stat;
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
# Subroutine		: init
# Objective			: This function is entry point for the script
# Added By			: Yogesh Kumar
# Modified By		: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	Common::loadAppPath();
	Common::loadServicePath() or retreat('invalid_service_directory');
	Common::verifyVersionConfig();
	Common::loadUsername() or retreat('login_&_try_again');
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);
	Common::loadEVSBinary() or retreat('unable_to_find_or_execute_evs_binary');
	Common::isLoggedin() or retreat('login_&_try_again');
	Common::displayHeader();

	if(!Common::hasSQLitePreReq() || !Common::hasBasePreReq()) {
		Common::retreat(['basic_prereq_not_met_run_acc_settings']);
	}

	# check the status of cron job, if not running ask the user to start the cron
	unless(Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
		display(['cron_service_not_running', '.']);
		my $res = Common::confirmRestartIDriveCRON();
		unless(Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
			Common::retreat(['please_try_again', '.']) if($AppConfig::mcUser eq 'root');
			Common::retreat(['please_make_sure_you_are_sudoers_list_and_try']);
		}
	}

	Common::addBasicUserCRONEntires() if(-z Common::getCrontabFile());

	unless(Common::getUserConfiguration('CDPSUPPORT')) {
		Common::setCDPInotifySupport();
	}

	my $hasnotif = Common::hasFileNotifyPreReq();
	unless(Common::isCDPWatcherRunning()) {
		display(['cdp_service_not_running', '.']) if($hasnotif);
		Common::startCDPWatcher(1);
		if($hasnotif) {
			# Watcher has to start the job. client takes sometime to start
			Common::isCDPWatcherRunning()? display(['cdp_service_started', '.', "\n"]) : display(['failed_to_start_cdp_service', '.', "\n"]);
		}
	}

	if($hasnotif and Common::getUserConfiguration('CDPSUPPORT') and -f Common::getCDPHaltFile()) {
		unlink(Common::getCDPHaltFile());
		# let cdp start in time interval
		sleep(2);
	}

	checkActiveDashboard() if($AppConfig::appType eq 'IDrive');

	my @jobTypes = ("backup", "local_backup", "archive");
	my @jobNames = ("default_backupset", "local_backupset", "default_backupset");

	if(Common::getUserConfiguration('CDP')) {
		push @jobTypes, $AppConfig::cdp;
		push @jobNames, "default_backupset";
	}

	displayCrontab('tableHeader', " ", " ");
	# lock here and release from archive cmd fix -- start
	Common::lockCriticalUpdate("cron");
	loadCrontab(1);
    checkPeriodicCmdAndUpdateCron(); #Added for Suruchi_2.3_12_6 : Senthil
	# lock here and release from archive cmd fix -- end

	my $isScheduledJob = 0;
	for my $i (0 .. $#jobNames) {
		createCrontab($jobTypes[$i], $jobNames[$i]) or retreat('failed_to_load_crontab');
		displayCrontab('table', $jobTypes[$i], $jobNames[$i]);
		$isScheduledJob = 1 if(getCrontab($jobTypes[$i], $jobNames[$i], '{settings}{status}') eq 'enabled');
	}

	Common::display('no_schedule_job') unless($isScheduledJob);
	
	$AppConfig::crontabmts = stat(Common::getCrontabFile())->mtime;
	loadCrontab(1);

	tie(my %optionsInfo, 'Tie::IxHash',
		'schedule_your_backup_job' => \&scheduleBackupJob,
		'schedule_your_local_backup_job' => \&scheduleExpressBackupJob,
		'schedule_your_archive_job' => \&scheduleArchiveJob,
		'schedule_your_cdp_job' => \&scheduleCDPJob,
		'disable_scheduled_backup_job' => \&disable,
		'disable_scheduled_local_backup_job' => \&disable,
		'disable_scheduled_archive_job' => \&disable,
		'disable_scheduled_cdp_job' => \&disable,
		'exit' => sub {
			exit 0;
		},
	);

	for my $i (0 .. $#jobNames) {
		if (getCrontab($jobTypes[$i], $jobNames[$i], '{settings}{status}') ne 'enabled') {
			delete $optionsInfo{'disable_scheduled_'.$jobTypes[$i].'_job'};
		}
	}

	delete $optionsInfo{'disable_scheduled_cdp_job'} if(!Common::getUserConfiguration('CDP') && exists($optionsInfo{'disable_scheduled_cdp_job'}));

	if (!Common::getUserConfiguration('CDPSUPPORT') or !$hasnotif) {
		delete $optionsInfo{'schedule_your_cdp_job'} if(exists($optionsInfo{'schedule_your_cdp_job'}));
		delete $optionsInfo{'disable_scheduled_cdp_job'} if(exists($optionsInfo{'disable_scheduled_cdp_job'}));
	}

	my @options = keys %optionsInfo;

	while(1) {
		display(["\n", 'menu_options', ":\n"]);
		Common::displayMenu('enter_your_choice', @options);
		my $userSelection = Common::getUserChoice();
		if (Common::validateMenuChoice($userSelection, 1, scalar(@options))) {
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
# Added By				: Sabin Cheruvattil,
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub checkActiveDashboard {
	loadCrontab(1);
	my $crontab = Common::getCrontab();
	return 0 unless(exists $crontab->{$AppConfig::mcUser} && exists $crontab->{$AppConfig::mcUser}{Common::getUsername()});

	my %usercrons = %{$crontab->{$AppConfig::mcUser}{Common::getUsername()}};
	return 0 unless(%usercrons);

	my $curdashpath = Common::getDashboardScript();
	my $dashcmd = (($usercrons{$AppConfig::dashbtask})? $usercrons{$AppConfig::dashbtask}{$AppConfig::dashbtask}{'cmd'} : '');
    my $dsp = Common::getScriptPathOfDashboard($dashcmd);
    my $csp = Common::getScriptPathOfDashboard($curdashpath);

	if (defined($dashcmd) and $dashcmd ne '' and ($dashcmd ne $curdashpath) and ($dsp ne $csp)) {
		Common::display(["\n", 'user', ' "', Common::getUsername(), '" ', 'is_already_having_active_setup_path', '.']);
		Common::retreat(['re_configure_your_account_freshly', '.']);
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: scheduleArchiveJob
# Objective				: This function is used to schedule the archive job
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub scheduleArchiveJob {
	my $jobType = 'archive';
	my $jobName = 'default_backupset';
	my $backupType  = Common::getUserConfiguration('BACKUPTYPE');
	my $locktype	= 'arch_cleanup_checked';
	my @archlocks 	= ();
	@archlocks 	= PropSchema::getLockedArchiveFields() if($AppConfig::appType eq 'IDrive');

	displayScheduledDetail($jobType, $jobName);

	unless($backupType =~ /mirror/){
		Common::retreat(["\n",'backup_type_must_be_mirror']);
		exit 0;
	}
	my ($status, $errStr) = Common::validateBackupRestoreSetFile('backup');
	if($status eq 'FAILURE' && $errStr ne ''){
		#Common::retreat(["\n\n",'unable_to_schedule','no_items_to_cleanup','Reason',$errStr,"\nNote: ",'please_update',"\n"], 1);
		Common::Chomp(\$errStr);
		display(["\n",'unable_to_schedule','no_items_to_cleanup',' ','Reason',$errStr,"\nNote: ",'please_update'], 0);
		retreat("");
	}

    if ((Common::getUserConfiguration('DEDUP') eq 'off') and !Common::getArchiveAlertConfirmation()){            
        retreat(["\n",'unable_to_schedule_periodic_cleanup']);
    }

	if(grep(/^$locktype$/, @archlocks)) {
		display(["\n", 'admin_has_locked_settings']);
		if(getCrontab($jobType, $jobName, '{settings}{status}') eq 'disabled') {
			return 1;
		}

		my $cmd = getCrontab($jobType, $jobName, '{cmd}');
		my $fre = "daily";
		if($cmd ne "") {
			my @params = split(' ', $cmd);
			my $paramSize = @params;
			$fre = "every\ " . ordinal($params[$paramSize-4]) . "\ Day";
		}

		display(['your_archive_cleanup_schedule', ': ', $fre, ' at ',
		getCrontab($jobType, $jobName, '{h}'), ':', getCrontab($jobType, $jobName, '{m}'), '.']);

		return 1;
	} else {
		display(["\n", "enter_percentage_of_files_for_cleanup_periodic"], 1);
		my $percentage = Common::getAndValidate(['enter_percentage_of_files_for_periodic_cleanup'], "periodic_cleanup_per", 1);

		display(["\n", "number_of_days_of_the_month_after_which_it_should_be_automatically_cleaned_up"], 1);
		my $noOfDays = Common::getAndValidate(['enter_the_days_for_cleanup'], "periodic_cleanup_days", 1);

		my $deleteEmptyDir = 0;
        # Commented for unexpected empty dir list issue
		# display(["\n",'do_you_want_to_cleanup_empty_directories'], 1);
		# if (Common::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'y') {
			# $deleteEmptyDir = 1;
		# }
        
        #Periodic cmd: script_path username days percentage timestamp isEmptyDirDelete
		setCrontab($jobType, $jobName, 'cmd', "$noOfDays $percentage $deleteEmptyDir "); #Just passing input received from user
		setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
		setCrontab($jobType, $jobName, {'settings' => {'frequency' => ' '}});
	}

	updateInfoDetails($jobType, $jobName, 2);
}

#*****************************************************************************************************
# Subroutine			: scheduleCDPJob
# Objective				: This function is used to schedule the CDP job
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub scheduleCDPJob {
	my ($status, $errStr) = Common::validateBackupRestoreSetFile('CDP');
	if($status eq 'FAILURE' && $errStr ne '') {
		Common::Chomp(\$errStr);
		Common::retreat(["\n", 'unable_to_schedule', 'Reason', $errStr, "\n", 'note_title', ': ', 'please_update'], 0);
	}

	unless(Common::isCDPClientServerRunning()) {
		Common::retreat(["\n", 'cdp_service_not_running', '. ', 'please_contact_support_for_more_information']);
	}

	loadCrontab(1);

	my $jobType		= $AppConfig::cdp;
	my $jobName		= "default_backupset";
	my $jobfreq		= '';

	displayScheduledDetail($jobType, $jobName);

	display(["\n",'select_cdp_jobs_frequency'], 1);
	my $frequency = Common::getAndValidate(['enter_your_choice'], "cdp_frequency", 1);
	my %freqtotime = ('01' => '1', '02' => '10', '03' => '30', '04' => '60');
	$frequency = $freqtotime{sprintf("%02d", $frequency)};

	if ($frequency == '1') {
		$jobfreq	= '01' ;
	} elsif($frequency == '60') {
		$jobfreq	= '00';
	} else {
		$jobfreq	= $frequency;
	}

	# load crontab one more time, it may get updated in parallel.
	Common::lockCriticalUpdate("cron");
	loadCrontab(1);
	Common::createCrontab($jobType, $jobName);
	setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
	setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'hourly'}});
	
	if($jobfreq eq '00') {
		setCrontab($jobType, $jobName, 'm', "$jobfreq");
	} else {
		setCrontab($jobType, $jobName, 'm', "*/$jobfreq");
	}

	setCrontab($jobType, $jobName, 'h', '*');
	setCrontab($jobType, $jobName, 'dow', '*');
	setCrontab($jobType, $jobName, 'mon', '*');
	setCrontab($jobType, $jobName, 'dom', '*');

	Common::setCronCMD($jobType, $jobName);
	Common::saveCrontab();
	Common::unlockCriticalUpdate("cron");
	
	Common::setUserConfiguration('CDP', int($frequency));
	Common::saveUserConfiguration();

	display(["\n", ($frequency == '1')? ('cdp_job_has_been_scheduled_realtime') : ('cdp_job_has_been_scheduled_at_each', ' ', $frequency, ' ', 'minutes'), '.', "\n"], 1);

	return 1;
}

#*****************************************************************************************************
# Subroutine		: updateInfoDetails
# Objective			: This function is used to update the job details
# Added By			: Anil Kumar
# Modified By 		: Yogesh Kumar, Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub updateInfoDetails {
	my $jobType = $_[0];
	my $jobName = $_[1];
	my $backupType = $_[2];

	if (getCrontab($jobType, $jobName, '{settings}{status}') eq 'enabled') {
		Common::setCronCMD($jobType, $jobName);
		updateEmailIDs($jobType, $jobName);
	}

	if (getCrontab('cancel', $jobName, '{settings}{status}') eq 'enabled') {
		Common::setCronCMD('cancel', $jobName);
	}

	# handle the delay in setting cutoff and email options
	if($backupType == 1) {
		my @now	= localtime;
		my $st	= $now[1] + 1;
		$st		= 0 if($st > 59);

		Common::setCrontab($jobType, $jobName, 'm', $st);
	}

	Common::lockCriticalUpdate("cron");

	my $curcronmts = 0;
	$curcronmts = stat(Common::getCrontabFile())->mtime;
	if($AppConfig::crontabmts != $curcronmts) {
		my $modcrontab = getCrontab();
		loadCrontab(1);
		my $curcrontab = getCrontab();

		$curcrontab->{$jobType}{$jobName} = $modcrontab->{$jobType}{$jobName};

		if (getCrontab('cancel', $jobName, '{settings}{status}') eq 'enabled') {
			$curcrontab->{'cancel'}{$jobName} = $modcrontab->{'cancel'}{$jobName};
		}
	}

	Common::saveCrontab();
	Common::unlockCriticalUpdate("cron");
	
	if (($jobType eq 'backup') and Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
		Common::setNotification('get_scheduler') and Common::saveNotifications();

		if (Common::getNotifications('alert_status_update') eq $AppConfig::alertErrCodes{'no_scheduled_jobs'}) {
			Common::setNotification('alert_status_update', 0) and Common::saveNotifications();
		}

		Common::unlockCriticalUpdate("notification");
	}

	#need to check the backup set file to confirm whether it is empty or not.
	my ($jobRunningDir, $backupsetType) = ("") x 2;
	if ($jobType eq "local_backup") {
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
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub scheduleExpressBackupJob {
	my $backupType = 0;
	my $jobType    = "local_backup";
	my $jobName    = "local_backupset";

	displayScheduledDetail($jobType, $jobName);
	display('');

	my ($status, $errStr) = Common::validateBackupRestoreSetFile('localbackup');
	if($status eq 'FAILURE' && $errStr ne ''){
		Common::Chomp(\$errStr);
		display(['unable_to_schedule','Reason',$errStr,"\nNote: ",'please_update'], 0);
		retreat("");		
	}
	
	my $localMountPoint = Common::getUserConfiguration('LOCALMOUNTPOINT');
	Common::getAndSetMountedPath();
	if ($localMountPoint eq "") {
		$localMountPoint = Common::getUserConfiguration('LOCALMOUNTPOINT');
	}

	$backupType = updateBackupType($jobType, $jobName);

	updateInfoDetails($jobType, $jobName, $backupType);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: scheduleBackupJob
# Objective				: This function is used to schedule the backup job
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub scheduleBackupJob {
	my $backupType = 0;
	my $jobType  = 'backup';
	my $jobName = 'default_backupset';

	displayScheduledDetail($jobType, $jobName);

	my ($status, $errStr) = Common::validateBackupRestoreSetFile('backup');
	if($status eq 'FAILURE' && $errStr ne ''){
		Common::Chomp(\$errStr);
		display(["\n", 'unable_to_schedule','Reason',$errStr,"\nNote: ",'please_update'], 0);
		retreat("");
	}

	if (Common::getUserConfiguration('DEDUP') eq 'off') {
		display(["\n", "your_backup_to_device_name_is", ' "', Common::getUserConfiguration('BACKUPLOCATION'),"\"."], 0);
		display([' ', 'do_you_really_want_to_edit_(_y_n_)', '?']);
		my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);

		if ($yesorno eq 'y') {
			Common::setBackupToLocation() or retreat('failed_to_set_backup_location');
			Common::saveUserConfiguration() or retreat('failed_to_save_user_configuration');
		}
	} else {
		display(["\n", "your_backup_to_device_name_is", ' "', (index(Common::getUserConfiguration('BACKUPLOCATION'), '#') != -1 )? (split('#', (Common::getUserConfiguration('BACKUPLOCATION'))))[1] :  Common::getUserConfiguration('BACKUPLOCATION'),"\"."], 0);
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
# Modified By			: Sabin Cheruvattil, Senthil Pandian
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
		if($_[0] eq 'local_backup') {
			$jobRunningDir = Common::getJobsPath('localbackup');
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
		if(!-f $backupsetFile || -z _) {
			display(["\n\n", "Note: Your $backupsetType is empty. ", 'please_update', ' ', "\n"], 1);
			exit(0);
		}

		goToCutOff($_[0], $_[1], 'immediate');
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
	if ($jobType eq 'backup') {
		$jobRunningDir = $jobRunningDir."/Backup/DefaultBackupSet";
	} elsif($jobType eq 'local_backup') {
		$jobRunningDir = $jobRunningDir . "/LocalBackup/LocalBackupSet";
	}

	#Checking if another job is already in progress
	my $pidPath = "$jobRunningDir/pid.txt";

	if(Common::isFileLocked($pidPath)) {
		Common::retreat('Job is already in progress.');
	}

	if($_[2] eq 'hourly' && grep(/^$timetype$/, @schlocks)) {
		display(["\n", 'admin_has_locked_settings']);
		display(['current_backup_timing', ': ', 'hourly basis at every ', ordinal(getCrontab($jobType, $jobName, '{m}')), 'th minute']);
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
		$startTime = getCrontab($jobType, $jobName, '{m}');
	}

	setCrontab($jobType, $jobName, 'm', $startTime);
	setCrontab($jobType, $jobName, 'h', '*');
	setCrontab($jobType, $jobName, 'dow', '*');
	setCrontab($jobType, $jobName, 'mon', '*');
	setCrontab($jobType, $jobName, 'dom', '*');

	setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});

	return 1;
}

#*****************************************************************************************************
# Subroutine			: displayCrontab
# Objective				: This function is used to dispaly the cron jobs.
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub displayCrontab {
	my $displayFormat = $_[0] || 'table';

	my $jobType  = $_[1] || retreat('jobname_is_required');
	my $jobName = $_[2]  || retreat('jobtitle_is_required');
	if ($displayFormat eq 'tableHeader') {
		display(['your_scheduled_job_details_are_mentioned_below', ':'], 1);
		display('=' x 95);
		prettyPrint(['-17s', 'scheduled_job'], ['-29s', 'frequency'], ['-19s', 'next_schedule'], ['-11s', 'cut_-_off'], ['-16s', 'email_notification']);
		display(["\n", '=' x 95]);
	}
	elsif ($displayFormat eq 'table') {
		return 1 if(getCrontab($jobType, $jobName, '{settings}{status}') eq 'disabled');
		my $startDate = "NA";
		prettyPrint(['-17s', $jobType.'_title']);
		
		if($jobType eq $AppConfig::cdp) {
			my $min = getCrontab($jobType, $jobName, '{m}');
			$min	=~ s/\*\///;
			my $fre = "";

			if(sprintf("%02d", $min) eq '01') {
				$fre = 'Real time';
			} elsif($min eq '00') {
				$fre = "60 minutes";
			} else {
				$fre = sprintf("%02d", $min) . ' minutes';
			}

			prettyPrint(['-29s', $fre]);
		} else {
			if (((getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'daily') || (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'hourly')) && ($jobType ne "archive")) {
				prettyPrint(['-29s', ucfirst(getCrontab($jobType, $jobName, '{settings}{frequency}'))]);
			} elsif (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'weekly') {
				if (getCrontab($jobType, $jobName, '{dow}') eq join(',', @AppConfig::weekdays)) {
					prettyPrint(['-29s', 'Weekdays']);
				}
				elsif (getCrontab($jobType, $jobName, '{dow}') eq join(',', @AppConfig::weekends)) {
					prettyPrint(['-29s', 'Weekends']);
				}
				else {
					if(getCrontab($jobType, $jobName, '{dow}') eq '*') {
						prettyPrint(['-29s', 'NA']);
					} else {
						my $wfre = getCrontab($jobType, $jobName, '{dow}');
						$wfre = join ", ", map {ucfirst} split ",", $wfre;
						prettyPrint(['-29s', $wfre]);
					}
				}
			} elsif (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'immediate') {
				prettyPrint(['-29s', ucfirst(getCrontab($jobType, $jobName, '{settings}{frequency}'))]);
			}
		}

		if($jobType eq 'archive'){
			my $cmd = getCrontab($jobType, $jobName, '{cmd}');
			my $fre = 'daily';
			if($cmd ne '') {
				my @params = split(' ', $cmd);
				my $paramSize = @params;
				($fre, $startDate) = ("--") x 2;
				if(length($params[$paramSize-1]) > 1) {
					$fre = "Every\ ".ordinal($params[$paramSize-3])."\ Day" if(Common::validateMenuChoice($params[$paramSize-3], 5, 30));
					$startDate = Common::strftime('%Y-%m-%d', localtime($params[$paramSize-1])) if($params[$paramSize-1]);
				} else {
					$fre = "Every\ ".ordinal($params[$paramSize-4])."\ Day" if(Common::validateMenuChoice($params[$paramSize-4], 5, 30));
					$startDate = Common::strftime('%Y-%m-%d', localtime($params[$paramSize-2])) if($params[$paramSize-2]);
				}
			}
			prettyPrint(['-29s', $fre]);

			my $nextDate = getNextSchedule($jobType,$jobName);
			prettyPrint(['-19s', $nextDate],['-8s', 'NA']);
			my $emailStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}');
			$emailStatus = ($emailStatus eq 'disabled')?'disabled':'enabled';
			prettyPrint(['27s', Common::colorScreenOutput($emailStatus,'10s')]);

		} elsif($jobType eq $AppConfig::cdp) {
			my $nextDate = getNextSchedule($jobType, $jobName);
			prettyPrint(['-19s', $nextDate]);
			prettyPrint(['-11s', 'NA'], ['-15s', 'NA']);
		}
		else {
			my $nextDate = getNextSchedule($jobType,$jobName);
			prettyPrint(['-19s', $nextDate]);
			my $cutOffStatus = getCrontab('cancel', $jobName, '{settings}{status}');
			if($cutOffStatus eq 'enabled'){
				my $cutOffTime = getCrontab('cancel', $jobName, '{h}').':'.getCrontab('cancel', $jobName, '{m}');
				prettyPrint(['-11s', $cutOffTime]);
			} else {
				prettyPrint(['-25s', Common::colorScreenOutput($cutOffStatus,'10s')]);
			}
			my $emailStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}');
			$emailStatus = ($emailStatus eq 'disabled')?'disabled':'enabled';
			prettyPrint(['-15s', Common::colorScreenOutput($emailStatus,'10s')]);
		}
		display('');
	}
	else {
		my $tempJobType = ($jobType eq 'archive')?"periodic_archive_cleanup":$jobType;
		display([ "\n", $tempJobType, 'job_has_been_scheduled_successfully_on' ], 0);

		if (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'daily') {
			display(lc(getCrontab($jobType, $jobName, '{settings}{frequency}')), 0);
		}
		elsif (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'hourly') {
			display("on ".lc(getCrontab($jobType, $jobName, '{settings}{frequency}')), 0);
		}
		else {
			my $wfre = getCrontab($jobType, $jobName, '{dow}');
			$wfre = join ", ", split ",", $wfre;
			display($wfre, 0);
		}

		if (getCrontab($jobType, $jobName, '{settings}{frequency}') eq 'hourly') {
			display([' basis at every', ' ', getCrontab($jobType, $jobName, '{m}'), 'th minute'], 0);
		} else {
			display([ ' ', 'at', ' ', getCrontab($jobType, $jobName, '{h}'), ':', getCrontab($jobType, $jobName, '{m}'), ], 0);
		}

		if (getCrontab('cancel', $jobName, '{settings}{status}') eq 'enabled') {
			display([', ', 'with_cut_off_time_for'], 0);

			if (getCrontab('cancel', $jobName, '{settings}{frequency}') eq 'daily') {
				display([' ', lc(getCrontab('cancel', $jobName, '{settings}{frequency}'))], 0);
			} elsif(getCrontab('cancel', $jobName, '{dow}') ne '*') {
				my $wfre = getCrontab($jobType, $jobName, '{dow}');
				$wfre = join ", ", split ",", $wfre;
				display([' ', $wfre], 0);
			}

			display([' ', 'at', ' ', getCrontab('cancel', $jobName, '{h}'), ':', getCrontab('cancel', $jobName, '{m}')], 0);
		}

		display('.');
	}
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

			$cutoffHour = Common::getAndValidate(['enter_hour_0_-_23', ': '], '24hours_validator', 1);
			setCrontab('cancel', $jobName, 'h', sprintf("%02d", $cutoffHour));

			$cutoffMinute = Common::getAndValidate(['enter_minute_0_-_59', ': '], 'minutes_validator', 1);
			setCrontab('cancel', $jobName, 'm', sprintf("%02d", $cutoffMinute));

			$timeDiff = ((($scheduledHour * 60) + $scheduledMinute) - (($cutoffHour * 60) + $cutoffMinute));

			#Added by Senthil for Yuvaraj_2.17_23_6
			if ($timeDiff <= -1) {
				setCrontab('cancel', $jobName, 'dow', getCrontab($jobType, $jobName, '{dow}'));
			}

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
	goToCutOff($_[1], $_[2], 'hourly');
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
# Modified By			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub disable {
	my $operationType = $_[0];
	my $jobType = "";
	my $jobName = "";

	my @schlocks 	= ();
	@schlocks 		= PropSchema::getLockedScheduleFields() if($AppConfig::appType eq 'IDrive');
	my @archlocks 	= ();
	@archlocks 		= PropSchema::getLockedArchiveFields() if($AppConfig::appType eq 'IDrive');
	if ($operationType eq 'disable_scheduled_backup_job') {
		$jobType  = 'backup';
		$jobName = 'default_backupset';
		if(grep(/^backup_nxttrftime$/, @schlocks) || grep(/^backup_freq$/, @schlocks) || grep(/^backup_cutoff$/, @schlocks)) {
			display(["\n", 'admin_has_locked_settings', ' ', 'unable_to_proceed']);
			return 1;
		}
	}
	elsif ($operationType eq 'disable_scheduled_local_backup_job') {
		$jobType  = 'local_backup';
		$jobName = 'local_backupset';
		if(grep(/^localbackup_nxttrftime$/, @schlocks) || grep(/^localbackup_freq$/, @schlocks) || grep(/^localbackup_cutoff$/, @schlocks)) {
			display(["\n", 'admin_has_locked_settings', ' ', 'unable_to_proceed']);
			return 1;
		}
	}
	elsif ($operationType eq 'disable_scheduled_archive_job') {
		$jobType  = 'archive';
		$jobName = 'default_backupset';
		if(grep(/^arch_cleanup_checked$/, @archlocks)) {
			display(["\n", 'admin_has_locked_settings', ' ', 'unable_to_proceed']);
			return 1;
		}
	}
	elsif ($operationType eq "disable_scheduled_cdp_job") {
		$jobType  = $AppConfig::cdp;
		$jobName = "default_backupset";
	}

	display(["\n", 'do_you_really_want_to_disable_the_scheduled_'.$jobType.'_job_(_y_n_)', '?']);

	my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
	if ($yesorno eq 'y') {
		# dashboard allows schedule modification even if the job is in progress
		# checkRunningJobs($jobType);
		setCrontab($jobType, $jobName, {'settings' => {'status' => 'disabled'}});
		setCrontab('cancel', $jobName, {'settings' => {'status' => 'disabled'}}) unless($jobType eq 'archive');
		#$jobType =~ s/_/ /g	if($jobType eq "local_backup");

		if($jobType eq $AppConfig::cdp) {
			Common::setUserConfiguration('CDP', 0);
			Common::saveUserConfiguration();
		}

		$jobType = 'periodic_archive_cleanup' if($jobType eq 'archive');

		display([($jobType eq 'cdp')? uc($jobType) : $jobType, 'job_has_been_disabled_successfully']);
		if (($jobType eq 'backup') and Common::loadNotifications() and Common::lockCriticalUpdate("notification")) {
			 Common::setNotification('alert_status_update', $AppConfig::alertErrCodes{'no_scheduled_jobs'}) and Common::saveNotifications();
			 Common::unlockCriticalUpdate("notification")
		}
	}

	Common::lockCriticalUpdate("cron");

	my $curcronmts = 0;
	$curcronmts = stat(Common::getCrontabFile())->mtime;
	if($AppConfig::crontabmts != $curcronmts) {
		my $modcrontab = getCrontab();
		loadCrontab(1);
		my $curcrontab = getCrontab();

		$curcrontab->{$jobType}{$jobName} = $modcrontab->{$jobType}{$jobName};

		unless($jobType eq 'archive') {
			$curcrontab->{'cancel'}{$jobName} = $modcrontab->{'cancel'}{$jobName};
		}
	}

	Common::saveCrontab();
	Common::unlockCriticalUpdate("cron");

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
# Modified By			: Sabin Cheruvattil, Senthil Pandian
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
				my $pref = $AppConfig::notifOptions{'notify_always'};
				$pref = getNotificationPref()  if($jobType ne 'archive');
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => $pref}}});
			}
			else {
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
			}
		}
		else {
			if (getCrontab($jobType, $jobName, '{settings}{emails}{ids}') ne '') {
				display(["\n", 'your_email_notification_settings_are', ': ']);
				my $emailStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}');
				if($jobType eq 'archive') {
					$emailStatus = ($emailStatus eq 'disabled')?'disabled':'enabled';
					$emailStatus = Common::colorScreenOutput($emailStatus);
				}
				display(['email_notification_status', ': ', $emailStatus]);
				display(['email_address_(_es_)', ': ', getCrontab($jobType, $jobName, '{settings}{emails}{ids}')]);
			}

			display(["\n", 'do_you_want_to_disable_email_notification_(_y_n_)', '?']);
			my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
			if ($yesorno eq 'y') {
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
			}
			else {
				my $pref = $AppConfig::notifOptions{'notify_always'};
				$pref = getNotificationPref() if($jobType ne 'archive');				
				setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => $pref}}});
				display(["\n", 'do_you_want_to_change_email_id_(_s_)_(_y_n_)']);
				my $yesorno = Common::getAndValidate('enter_your_choice', 'YN_choice', 1);
				return 1 if($yesorno ne 'y');
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

#*****************************************************************************************************
# Subroutine	: getNextSchedule
# In Param		: jobType, jobName
# Out Param		: Next Schedule Date
# Objective		: This subroutine to return the next schedule date based on scheduled frequency
# Added By		: Senthil Pandian
# Modified By	: Sabin Cheruvattil
#*****************************************************************************************************
sub getNextSchedule {
	my $jobType = $_[0];
	my $jobName = $_[1];
	my $freq = getCrontab($jobType, $jobName, '{settings}{frequency}');
	my $nextSchedDate = 'NA';

	if($jobType eq 'archive'){
		my $cmd = getCrontab($jobType, $jobName, '{cmd}');
		my $fre = 'daily';
		if($cmd ne '') {
			my @params = split(' ', $cmd);
			my $paramSize = @params;
			my ($fre, $startDate) = ("--") x 2;

			if(length($params[$paramSize-1]) > 1) {
				$startDate = $params[$paramSize-1] if($params[$paramSize-1]);
				$fre = $params[$paramSize-3];
			} else {
				$startDate = $params[$paramSize-2] if($params[$paramSize-2]);
				$fre = $params[$paramSize-4];
			}

			my $diffDays = getDaysBetweenTwoDates($startDate);
			my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();

			$year += 1900;
			$mon++;
			my $schedhour = getCrontab($jobType, $jobName, '{h}');
			my $schedmin = getCrontab($jobType, $jobName, '{m}');

			if($diffDays == 0){
				if(($hour<$schedhour) or ($hour==$schedhour and $min<$schedmin)){
					$nextSchedDate = sprintf("%02d/%02d/%04d %02d:%02d",$mon,$mday,$year,$schedhour,$schedmin);
				} else {					
					my @startTime = (0,$schedmin,$schedhour,$mday+$fre,($mon-1),($year-1900));
					$nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));
				}
			} else {
				if($diffDays > $fre) {					
					$diffDays = ($diffDays%$fre);
					$diffDays = ($fre-$diffDays);
				}

				my @startTime = (0,$schedmin,$schedhour,$mday+$diffDays,($mon-1),($year-1900));
				$nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));			
			}
		}
	} elsif($jobType eq $AppConfig::cdp) {
		my $smin = getCrontab($jobType, $jobName, '{m}');
		$smin	=~ s/\*\///;

		if(sprintf("%02d", $smin) eq '01') {
			$nextSchedDate = 'Real time';
		} else {
			my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
			my @startTime;

			if(sprintf("%02d", $smin) eq '00') {
				@startTime = (0, 0, $hour + 1, $mday, $mon, $year);
			} else {
				@startTime = (0, ($min - ($min % $smin)) + $smin, $hour, $mday, $mon, $year);
			}
			
			$nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));
		}
	} else {
		my $cmd = getCrontab($jobType, $jobName, '{cmd}');
		if($freq eq 'weekly') {
			$nextSchedDate = getNextWeeklyScheduleTime($jobType,$jobName);
		} elsif($freq eq 'daily') {
            $nextSchedDate = getNextDailyScheduleTime($jobType,$jobName);
		} elsif($freq eq 'hourly') {
		    $nextSchedDate = getNextHourlyScheduleTime($jobType,$jobName);
		}
	}
	return $nextSchedDate;
}

#*****************************************************************************************************
# Subroutine	: getNextWeeklyScheduleTime
# In Param		: jobType, jobName
# Out Param		: Next Schedule Date
# Objective		: This subroutine to calculate the next schedule date of daily schedule
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub getNextWeeklyScheduleTime {
	my $jobType = $_[0];
	my $jobName = $_[1];
	my $nextSchedDate = 'NA';
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	#Ex:(48,  27,   11,    24,  6, 2019,  3,   204,   0)
	$year += 1900;
	$mon++;

	my $days = getCrontab($jobType, $jobName, '{dow}');
	my $schedhour = getCrontab($jobType, $jobName, '{h}');
	my $schedmin = getCrontab($jobType, $jobName, '{m}');

	if($days =~ $AppConfig::weeks[$wday-1] and (($hour<$schedhour) or ($hour==$schedhour and $min<$schedmin))) {
        $nextSchedDate = sprintf("%02d/%02d/%04d %02d:%02d",$mon,$mday,$year,$schedhour,$schedmin);
	} else {
		my $next=0;
        for(my $i=$wday;$i<7;$i++){
			$next++;
            if($days =~ $AppConfig::weeks[$i]) {
				my @startTime = (0,$schedmin,$schedhour,$mday+$next,($mon-1),($year-1900));
				$nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));
				last;
			}
        }
		if($nextSchedDate eq 'NA'){
			$next=(7-$wday);
			for(my $i=0;$i<=$wday;$i++){
				$next++;
				if($days =~ $AppConfig::weeks[$i]) {
				    my @startTime = (0,$schedmin,$schedhour,$mday+$next,($mon-1),($year-1900));
				    $nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));					
					last;
				}
			}			
		}
	}
	return $nextSchedDate;
}

#*****************************************************************************************************
# Subroutine	: getNextDailyScheduleTime
# In Param		: jobType, jobName
# Out Param		: Next Schedule Date
# Objective		: This subroutine to calculate the next schedule date of daily schedule
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub getNextDailyScheduleTime {
	my $jobType = $_[0];
	my $jobName = $_[1];
	my $nextSchedDate = 'NA';
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	#	(48,  27,   11,    24,  6, 2019,  3,   204,   0)
	$year += 1900;
	$mon++;

	my $schedhour = getCrontab($jobType, $jobName, '{h}');
	my $schedmin  = getCrontab($jobType, $jobName, '{m}');
	$schedhour =~ s/\*//g;
	$schedmin  =~ s/\*//g;
	if(($hour<$schedhour) or ($hour==$schedhour and $min<$schedmin)){
		$nextSchedDate = sprintf("%02d/%02d/%04d %02d:%02d",$mon,$mday,$year,$schedhour,$schedmin);
	} else {
		my @startTime = (0,$schedmin,$schedhour,$mday+1,($mon-1),($year-1900));
		$nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));
	}
	return $nextSchedDate;
}

#*****************************************************************************************************
# Subroutine	: getNextHourlyScheduleTime
# In Param		: jobType, jobName
# Out Param		: Next Schedule Date
# Objective		: This subroutine to calculate the next schedule date of hourly schedule
# Added By		: Senthil Pandian
# Modified By	: Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************
sub getNextHourlyScheduleTime {
	my $jobType = $_[0];
	my $jobName = $_[1];
	my $nextSchedDate = 'NA';
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	#	(48,  27,   11,    24,  6, 2019,  3,   204,   0)
	$year += 1900;
	$mon++;

	my $schedhour	= getCrontab($jobType, $jobName, '{h}');
	my $schedmin	= getCrontab($jobType, $jobName, '{m}');

    # Added for Harish_2.3_20_3: Senthil
    if($schedhour eq '*' and $min < $schedmin)  {
        $schedhour = $hour;
    } else {
        $schedhour = $hour + 1 if($schedhour eq '*');
    }
    
    # Modified for Harish_2.3_20_3: Senthil
    # if(($schedhour eq '*' || $hour < $schedhour) or ($hour == $schedhour and $min < $schedmin)) {
    if(($hour < $schedhour) or ($hour == $schedhour and $min < $schedmin)) {
		# $schedhour = $hour + 1 if($schedhour eq '*');
		$nextSchedDate = sprintf("%02d/%02d/%04d %02d:%02d", $mon, $mday, $year, $schedhour, $schedmin);
	} else {
		my @startTime = (0, $schedmin, $schedhour + 1, $mday, ($mon - 1), ($year - 1900));
		$nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));
	}

	return $nextSchedDate;
}

#*****************************************************************************************************
# Subroutine	: getDaysBetweenTwoDates
# In Param		: jobType, jobName
# Out Param		: Next Schedule Date
# Objective		: This subroutine to return the days between two dates
# Added By		: Senthil Pandian
# Modified By	: 
#*****************************************************************************************************
sub getDaysBetweenTwoDates {
	my $s1 = $_[0]; #Scheduled Time
	my $s2 = time;
	my $days = int(($s2 - $s1)/(24*60*60));
	return $days;
}

#*****************************************************************************************************
# Subroutine	: displayScheduledDetail
# In Param		: jobType, jobName
# Out Param		: 
# Objective		: This subroutine to display the Scheduled Detail
# Added By		: Senthil Pandian
# Modified By	: Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************
sub displayScheduledDetail{
	my $jobType = $_[0];
	my $jobName = $_[1];
	my $cmd = getCrontab($jobType, $jobName, '{cmd}');
    Common::Chomp(\$cmd);
	return if($cmd eq '');

	display(["\n",$jobType.'_title','job_details']);
	my $headLen = length Common::getStringConstant($jobType.'_title');
	$headLen += 13;
	display("="x$headLen);

    if($jobType eq 'backup' or $jobType eq 'local_backup'){
		my $status  = getCrontab($jobType, $jobName, '{settings}{status}');
		my $freq = getCrontab($jobType, $jobName, '{settings}{frequency}');

		if($freq eq 'weekly') {
			$freq = getCrontab($jobType, $jobName, '{dow}');
			$freq = join ", ", map {ucfirst} split ",", $freq;
		} else {
			$freq = ucfirst($freq);
		}
		
		my $schedTime = getCrontab($jobType, $jobName, '{h}').':'.getCrontab($jobType, $jobName, '{m}');
		my $cutOff = getCrontab('cancel', $jobName, '{settings}{status}');
		if($cutOff eq 'enabled'){
			$cutOff = getCrontab('cancel', $jobName, '{h}').':'.getCrontab('cancel', $jobName, '{m}');
		} else {
			$cutOff = Common::colorScreenOutput($cutOff);
		}
		my $emailStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}');
		display(['status',(' ' x 13), ' : ',Common::colorScreenOutput($status)]);
		if($jobType eq 'backup'){
			my $backupLoc = Common::getUserConfiguration('BACKUPLOCATION');
			$backupLoc = (split('#', $backupLoc))[1] if((Common::getUserConfiguration('DEDUP') eq 'on') and $backupLoc =~ /#/);
			display(['backup_location_lc',(' ' x 4),' : ',$backupLoc]);
		} else {
			display(['mount_point',(' ' x 8),' : ',Common::getUserConfiguration('LOCALMOUNTPOINT')]);
		}
		display(['scheduled_time',(' ' x 5),' : ',$schedTime]);
	    display(['frequency',(' ' x 10), ' : ', $freq]);
		display(['cut_-_off',(' ' x 12),' : ',$cutOff]);
		if($emailStatus eq 'disabled'){
			display(['email_notification',' : ', Common::colorScreenOutput($emailStatus)]);
		} else {
			display(['email_notification',' : ', Common::colorScreenOutput('enabled')]);
			display(['email_address_(_es_)',(' ' x 1),' : ', getCrontab($jobType, $jobName, '{settings}{emails}{ids}')]);
		}
		
	}
	elsif($jobType eq $AppConfig::cdp) {
		my $status		= getCrontab($jobType, $jobName, '{settings}{status}');
		my $backuploc	= Common::getUserConfiguration('BACKUPLOCATION');
		$backuploc	    = (split('#', $backuploc))[1] if((Common::getUserConfiguration('DEDUP') eq 'on') and ($backuploc =~ /#/));

		my $min		= getCrontab($jobType, $jobName, '{m}');
		$min		=~ s/\*\///;
		my $freq	= '--';

		if(sprintf("%02d", $min) eq '01') {
			$freq = 'Real time';
		} elsif($min eq '00') {
			$freq = "60 minutes";
		} else {
			$freq = sprintf("%02d", $min) . ' minutes';
		}

		display(['status',(' ' x 13), ' : ', Common::colorScreenOutput($status)]);
		display(['backup_location_lc',(' ' x 4),' : ', $backuploc]);
		# display(['scheduled_time', (' ' x 5), ' : ', getNextSchedule($jobType, $jobName)]); # Review change
		display(['scheduled_time', (' ' x 5), ' : ', '--']);
		display(['frequency',(' ' x 10), ' : ', $freq]);
		# Commented | Review Change
		# display(['cut_-_off',(' ' x 12),' : ', Common::colorScreenOutput('NA')]);
		# display(['email_notification',' : ', Common::colorScreenOutput('NA')]);
	}
	elsif($jobType eq 'archive') {
		# my $cmd = getCrontab($jobType, $jobName, '{cmd}');
        my $status  = getCrontab($jobType, $jobName, '{settings}{status}');
        my @params = split(' ', $cmd);
        my $paramSize = @params;
      
        my ($freq, $startDate) = ("--") x 2;
        my $schedTime;
        $startDate = $params[$paramSize-2] if($params[$paramSize-2]);
        $freq = "Every\ " . ordinal($params[$paramSize-4]) . "\ Day";
        
        if($params[$paramSize-2]) {
            # $nextSchedDate = Common::strftime("%m/%d/%Y %H:%M", localtime(Common::mktime(@startTime)));
            my $archHour = Common::strftime("%H", localtime($params[$paramSize-2]));
            my $archMin = Common::strftime("%M", localtime($params[$paramSize-2]));
            $archHour = sprintf("%02d", $archHour);
            $archMin = sprintf("%02d", $archMin);
            $schedTime = $archHour.':'.$archMin;
        } else {
            my $archHour = getCrontab($jobType, $jobName, '{h}');
            my $archMin = getCrontab($jobType, $jobName, '{m}');
            $archHour = sprintf("%02d", $archHour);
            $archMin = sprintf("%02d", $archMin);
            $schedTime = $archHour.':'.$archMin;
        }

        my $emailStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}');
        # my $cleanupEmptyDir = ($params[$paramSize-1])?'enabled':'disabled';
        display(['status',(' ' x 19), ' : ',Common::colorScreenOutput($status)]);
        display(['scheduled_time',(' ' x 11),' : ',$schedTime]);	
        display(['frequency',(' ' x 16), ' : ',$freq]);
        display(['percentage_limit',(' ' x 9), ' : ',$params[$paramSize-3]]);
        # display(['cleanup_empty_directories', ' : ',Common::colorScreenOutput($cleanupEmptyDir)]);
        if($emailStatus eq 'disabled'){
            display(['email_notification',(' ' x 6),' : ', Common::colorScreenOutput($emailStatus)]);
        } else {
            display(['email_notification',(' ' x 6),' : ', Common::colorScreenOutput('enabled')]);
            display(['email_address_(_es_)',(' ' x 7),' : ', getCrontab($jobType, $jobName, '{settings}{emails}{ids}')]);
        }
	}
	# display("");
}

#*****************************************************************************************************
# Subroutine	: checkPeriodicCmdAndUpdateCron
# In Param		: NONE
# Out Param		: NONE
# Objective		: This subroutine to check periodic cleanup command & disable the job if command is invalid
# Added By		: Senthil Pandian
# Modified By	: Sabin Cheruvattil
#*****************************************************************************************************
sub checkPeriodicCmdAndUpdateCron {
    my $jobType  = "archive";
    my $jobName  = "default_backupset";
    my $cmd = getCrontab($jobType, $jobName, '{cmd}');
    my $fre = 'daily';
    if($cmd ne '') {
        my @params = split(' ', $cmd);
        my $paramSize = @params;
        if($paramSize>=3) {
            if($params[$paramSize-1] !~ /^\d+$/ or $params[$paramSize-2] !~ /^\d+$/ or $params[$paramSize-3] !~ /^\d+$/){
                if (getCrontab($jobType, $jobName, '{settings}{status}') eq 'enabled') {
                    setCrontab($jobType, $jobName, {'settings' => {'status' => 'disabled'}});
                    Common::setCronCMD($jobType, $jobName);
                    Common::saveCrontab();
                    Common::traceLog("$jobType job skipped/disabled due to invalid command: $cmd");
                }
            }
        }
    }

	Common::unlockCriticalUpdate("cron");
}