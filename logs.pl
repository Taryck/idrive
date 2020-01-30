#!/usr/bin/env perl
#*****************************************************************************************************
# This scritp is used to view the selected logs
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Configuration;
use Time::Local;
use File::Basename;
use POSIX;

tie(my %dateMenuChoices, 'Tie::IxHash', '1' => 'last_one_week', '2' => 'last_two_weeks', '3' => 'last_30_days', '4' => 'selected_date_range');
tie(my %mainMenu, 'Tie::IxHash', '1' => 'view_logs', '2' => 'deleted_logs');
tie(my %deleteMenuChoices, 'Tie::IxHash', '1' => 'delete_all', '2' => 'retain_last_week', '3' => 'retain_last_month', '4' => 'date_range_to_delete');

my (%logMenuToPathMap, %optionwithLogName, $logDir);
Helpers::waitForUpdate();
Helpers::initiateMigrate();

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	system(Helpers::updateLocaleCmd('clear'));
	Helpers::loadAppPath();
	Helpers::loadServicePath() 			or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername()				or Helpers::retreat('login_&_try_again');
	my $errorKey = Helpers::loadUserConfiguration();
	Helpers::retreat($Configuration::errorDetails{$errorKey}) if($errorKey > 1);
	Helpers::isLoggedin()            	or Helpers::retreat('login_&_try_again');

	Helpers::displayHeader();

	Helpers::displayMainMenu(\%mainMenu,'select_operation_to_perform');
	my $userMenuChoice 	= Helpers::getUserMenuChoice(scalar keys %mainMenu);
	($userMenuChoice==1)?viewLog():deleteLogs();
	exit;
}

#*****************************************************************************************************
# Subroutine			: viewLog
# Objective				: This subroutine to display the logs based on user's option.
# Added By				: Senthil pandian
#****************************************************************************************************/
sub viewLog {
	# show log menu and get the input from user
	my $maxMenuChoice 	= displayLogMenu();
	my $userMenuChoice 	= Helpers::getUserMenuChoice($maxMenuChoice);

	$logDir = Helpers::getUserFilePath($logMenuToPathMap{$userMenuChoice}{'logs'});
	#Renaming the log file if backup process terminated improperly
	my $jobDir = $logDir;
	$jobDir =~ s/LOGS//;
	my $pidPath  = Helpers::getCatfile($jobDir, $Configuration::pidFile);
	Helpers::checkAndRenameFileWithStatus($jobDir, $logMenuToPathMap{$userMenuChoice}{'type'}) unless(-e $pidPath);

	my %logFileList = Helpers::getLogsList($logDir);

	# make sure the logs are present for the selected job type: backup, restore, express backup
	Helpers::retreat(["\n", 'no_logs_found', '.', ' ', 'please_try_again', '.']) unless scalar keys %logFileList;

	# show date menu and get inputs from user
	displayDateMenu();
	my $userDateChoice = Helpers::getUserMenuChoice(scalar keys %dateMenuChoices);
	my ($startEpoch, $endEpoch) = ('', '');
	if($userDateChoice == 4) {
		# Convert start and end time to epoch
		($startEpoch, $endEpoch) = getUserDateRange();
	} else {
		my $noOfDays = ($userDateChoice == 1) ? Configuration::ONEWEEK : ($userDateChoice == 2)? Configuration::TWOWEEK : Configuration::ONEMONTH;
		($startEpoch, $endEpoch) = Helpers::getStartAndEndEpochTime($noOfDays);
	}

	my $slf = Helpers::selectLogsBetween(\%logFileList, $startEpoch, $endEpoch, Helpers::getCatfile($jobDir, $Configuration::logStatFile));
	# show logs
	my ($logFileChoice, $viewLogConf) = ('', 'n');
	do {
		# show log list
		my $displayLogCount = displayLogList($slf);
		Helpers::display(["\n", '__note_please_press_ctrlc_exit']);

		$logFileChoice = getChoiceToViewLog($logFileChoice);

		Helpers::openEditor('view', qq($logDir/$optionwithLogName{$logFileChoice})) if(-e qq($logDir/$optionwithLogName{$logFileChoice}));
		if($displayLogCount > 1) {
			Helpers::display(['do_you_want_to_view_more_logs_yn', "\n"]);
			$viewLogConf = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		}
	} while($viewLogConf eq 'y');
}

#*****************************************************************************************************
# Subroutine			: deleteLogs
# Objective				: This subroutine to display the logs based on user's option.
# Added By				: Senthil pandian
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub deleteLogs {
	my %deletedLogs;
	Helpers::display(' ');
	Helpers::displayMainMenu(\%deleteMenuChoices);
	my ($startEpoch, $endEpoch) = ('', '');
	my $userMenuChoice 	= Helpers::getUserMenuChoice(scalar keys %deleteMenuChoices);

	if ($userMenuChoice == 1) {
		Helpers::display(["\n", 'do_u_really_want_to_delete_all_yn'],1);
		my $deleteAllConfirmation = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if (lc($deleteAllConfirmation) eq 'n' ) {
			exit 1;
		}
	}
	elsif ($userMenuChoice == 4) {
		# Convert start and end time to epoch
		($startEpoch, $endEpoch) = getUserDateRange();
	}
	else {
		my $noOfDays = ($userMenuChoice == 2) ? Configuration::ONEWEEK : Configuration::ONEMONTH;
		($startEpoch, $endEpoch) = Helpers::getStartAndEndEpochTime($noOfDays);
	}

	foreach my $jobType (keys %Configuration::availableJobsSchema) {
		$deletedLogs{$jobType} = 0;
		my $logDir = Helpers::getJobsPath($jobType, 'logs');
		my $jobDir = $logDir;
		$jobDir =~ s/LOGS//;

		my %logFileList = Helpers::getLogsList($logDir);
		my $logPIDFile = Helpers::getCatfile($jobDir, $Configuration::logPidFile);
		if (-f $logPIDFile) {
			delete $logFileList{(split('_', basename(Helpers::getFileContents($logPIDFile))))[0]};
		}
		if (scalar %logFileList) {
			my @allLogs = keys %logFileList;
			my $slf;
			if ($userMenuChoice != 1) {
				$slf = Helpers::selectLogsBetween(\%logFileList, $startEpoch, $endEpoch);
			}

			my @logsToDelete;
			if ($slf and $slf->Length) {
				# Date range selected to delete
				if  ($userMenuChoice == 4) {
					# Get the logs list if it falls within Date range selected
					@logsToDelete = $slf->Keys;
				}
				else {
					# Get the logs list if it is not within week/month range
					foreach my $logFileKey (@allLogs) {
						push(@logsToDelete, $logFileKey)	unless (defined($slf->[0]{$logFileKey}));
					}
				}
			}
			elsif ($userMenuChoice != 4) {
				@logsToDelete = keys %logFileList;
			}

			$deletedLogs{$jobType} = deleteSelectedLogs($jobType, \@logsToDelete, \%logFileList) if (scalar(@logsToDelete));
		}
	}

	Helpers::display("\n", 1);
	#Helpers::displayTitlewithUnderline(Helpers::getStringConstant('total_logs_deleted'));
	Helpers::display('summary_of_deleted_logs',1);
	foreach my $jobType (keys %Configuration::logMenuAndPaths) {
		Helpers::display([$jobType,': ',$deletedLogs{$jobType}],1);
	}
	Helpers::display('', 1);
}

#*****************************************************************************************************
# Subroutine			: getUserDate
# Objective				: This subroutine will get the date from the user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserDate {
	my($dateMessage, $date, $choiceRetry) = (shift, '', 0);
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		Helpers::display([$dateMessage, ': '], 0);
		$date 	= Helpers::getUserChoice();
		$date	=~ s/^[\s\t]+|[\s\t]+$//g;

		$choiceRetry++;
		if($date eq '') {
			Helpers::display(["\n", 'cannot_be_empty', '. '],0);
			Helpers::checkRetryAndExit($choiceRetry, 0);
			Helpers::display(['please_try_again', '.',"\n"],1);
			#Helpers::display(["\n", 'cannot_be_empty', '.', ' ', 'please_try_again', '.',"\n"],1);
		} elsif(!Helpers::validateDatePattern($date) || !isValidDate($date)) {
			Helpers::checkRetryAndExit($choiceRetry, 1);
			Helpers::display(['invalid_date_or_format', '.', ' ', 'please_try_again', '.',"\n"]);
		} else {
			last;
		}
	}

	return $date;
}

#****************************************************************************************************
# Subroutine Name			: getUserDateRange
# Objective					: This subroutine will get the date range from the user.
# Added By					: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserDateRange {
	my($startDate, $endDate) = ('') x 2;
	my($errorMessage, $choiceRetry) = ('', 0);

	while($choiceRetry < $Configuration::maxChoiceRetry) {
		Helpers::display(" ");
		$startDate 	= getUserDate('enter_log_start_date__');
		$endDate	= getUserDate('enter_log_end_date__');

		$choiceRetry++;
		if(!validateUsersDateRange(\$startDate, \$endDate, \$errorMessage)) {
			($startDate, $endDate) = ('') x 2;
			Helpers::display([$errorMessage, '. ', 'please_try_again', '.']);
			Helpers::checkRetryAndExit($choiceRetry, 1);
		} else {
			last;
		}
	}

	return ($startDate, $endDate);
}

#****************************************************************************************************
# Subroutine Name			: getChoiceToViewLog
# Objective					: Get user choice to view log file
# Added By					: Abhishek Verma
# Modified By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getChoiceToViewLog {
	my($dateMessage, $choiceRetry, $logFileChoice) = (shift, 0, 0);
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		Helpers::display(["\n", 'enter_sno_to_view_log', ': '], 0);
		$logFileChoice = Helpers::getUserChoice();
		$logFileChoice =~ s/^[\s\t]+|[\s\t]+$//g;
		$logFileChoice =~ s/^0+(\d+)/$1/g;

		$choiceRetry++;
		if($logFileChoice eq '') {
			Helpers::checkRetryAndExit($choiceRetry, 0);
			Helpers::display(["\n", 'cannot_be_empty', '.', ' ', 'please_try_again', '.']);
		} elsif($logFileChoice !~ m/^\d+$/ || $logFileChoice > scalar keys %optionwithLogName || $logFileChoice <= 0) {
			Helpers::checkRetryAndExit($choiceRetry);
			$logFileChoice = '';
			Helpers::display(['invalid_choice', ' ', 'please_try_again', '.']);
		} else {
			last;
		}
	}

	return $logFileChoice;
}

#*****************************************************************************************************
# Subroutine			: displayLogList
# Objective				: To print the list of available logs in the of date & time when log was generated and status.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub displayLogList {
	my @columnNames = (['S.No.', 'Date & Time', 'Duration', 'Status', 'Files', 'Job Type'], [8, 25, 15, 12, 15, 10]);
	my $tableHeader = getTableHeader(@columnNames);
	my ($displayCount, $spaceIndex, $tableContent, $duration, $filesCount) = (1, 0, '', '--', '--');
	my @jobStat;

	foreach($_[0]->Keys) {
		$tableContent 	.= $displayCount;
		# (total_space - used_space by data) will be used to keep separation between 2 data
		$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($displayCount));
		$spaceIndex++;

		$tableContent 	.= $_[0]->FETCH($_)->{'datetime'};
		$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($_[0]->FETCH($_)->{'datetime'}));
		$spaceIndex++;

		if(exists $_[0]->FETCH($_)->{'duration'}) {
			$duration	= Helpers::convert_seconds_to_hhmmss($_[0]->FETCH($_)->{'duration'});
			$filesCount = $_[0]->FETCH($_)->{'filescount'};
		} else {
			$duration 	= '-';
			$filesCount = '-';
		}

		# (total_space - used_space by data) will be used to keep separation between 2 data
		$tableContent 	.= $duration;
		$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($duration));
		$spaceIndex++;

		@jobStat 		= split('_', $_[0]->FETCH($_)->{'status'});
		$jobStat[0] 	= '-' unless($jobStat[0]);
		# (total_space - used_space by data) will be used to keep separation between 2 data
		$tableContent 	.= ($jobStat[0])?$jobStat[0]:'-';
		$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($jobStat[0]));
		$spaceIndex++;

		# (total_space - used_space by data) will be used to keep separation between 2 data
		$tableContent 	.= $filesCount;
		$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($filesCount));
		$spaceIndex++;

		# (total_space - used_space by data) will be used to keep separation between 2 data
		$tableContent 	.= (($jobStat[1] eq 'Manual')? Helpers::getStringConstant('immediate_job_type') : $jobStat[1]) if(defined($jobStat[1]));
		$tableContent 	.= qq(\n);

		#creating another hash which contain serial number and log name as key and value pair so that later it can be used to display the log file.
		$optionwithLogName{$displayCount} = $_ . '_' . $_[0]->FETCH($_)->{'status'};
		$spaceIndex = 0;
		$displayCount++;
	}

	if($tableContent ne '') {
		Helpers::display(["\n", 'log_list', ':']);
		Helpers::display([$tableHeader . $tableContent], 0);
	} else {
		Helpers::retreat(["\n", 'no_logs_found', '.', ' ', 'please_try_again', '.']);
	}

	return $displayCount - 1;
}

#*****************************************************************************************************
# Subroutine			: getTableHeader
# Objective				: To get the table header display with column name.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getTableHeader {
	my $logTableHeader 	= qq(=) x (eval(join '+', @{$_[1]})) . qq(\n);
	for(my $contentIndex = 0; ($contentIndex <= scalar(@{$_[0]}) - 1); $contentIndex++) {
		#(total_space - used_space by data) will be used to keep separation between 2 data.
		$logTableHeader .= $_[0]->[$contentIndex] . qq( ) x ($_[1]->[$contentIndex] - length($_[0]->[$contentIndex]));
	}

	$logTableHeader 	.= qq(\n) . qq(=) x (eval(join '+', @{$_[1]})) . qq(\n);
	return $logTableHeader;
}

#*****************************************************************************************************
# Subroutine			: isValidDate
# Objective				: This subroutine will validate the date using system
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isValidDate {
	my($date, $epochTimeCmd, $epochCheckMsg) = (shift, '', '');
	$date			.= ' 00:00:00';
	$epochTimeCmd 	= 'date --date="' . $date . '" +%s';
	$epochTimeCmd = Helpers::updateLocaleCmd($epochTimeCmd);
	$epochCheckMsg 	= `$epochTimeCmd 2>&1`;
	return $epochCheckMsg !~ m/.*?(invalid date) \‘(\d{2}\/\d{2}\/\d{4}).*?\’/;
}

#*****************************************************************************************************
# Subroutine			: validateUsersDateRange
# Objective				: This subroutine will validate the date range
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateUsersDateRange {
	my($startDate, $endDate, $errorMessage) = (shift, shift, shift);
	my($tmpStart, $tmpEnd) 	= ($$startDate, $$endDate);
	my $incrementedEpoch 	= time() + (1 * 24 * 60 * 60);
	my $dateCmd = Helpers::updateLocaleCmd('date');

	$tmpStart		.= ' 00:00:00';
	$tmpEnd 		.= ' 23:59:59';

	if ($Configuration::machineOS =~ /freebsd/i) {
 		$$startDate 	= `$dateCmd -j -f "%m/%d/%Y %T" "$tmpStart" +%s`;
		$$endDate		= `$dateCmd -j -f "%m/%d/%Y %T" "$tmpEnd" +%s`;
	}
	else {
		$$startDate 	= `$dateCmd --date="$tmpStart" +%s`;
		$$endDate		= `$dateCmd --date="$tmpEnd" +%s`;
	}

	Helpers::Chomp(\$startDate);
	Helpers::Chomp(\$endDate);

	# Check start date is grater than current date
	if(($$startDate > $incrementedEpoch) || ($$endDate > $incrementedEpoch)) {
		$$errorMessage = 'start_date_or_end_date_not_greater';
		return 0;
	}

	# Error hanlding if start date is grater than end date.
	if($$startDate > $$endDate) {
		$$errorMessage = 'start_date_should_not_greater_end';
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: displayLogMenu
# Objective				: This subroutine displays the log menu
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub displayLogMenu {
	my ($opIndex, $pathIndex) = (1, 1);
	my @menuOptions;
	Helpers::display(["\n", 'menu_options_title', ':', "\n"]);

	foreach (keys %Configuration::logMenuAndPaths) {
		Helpers::display([$opIndex . ") " . Helpers::getStringConstant($Configuration::logMenuAndPaths{$_}) . "\n"], 0);
		$logMenuToPathMap{$opIndex++} = {
			'type' => $_,
			'logs' => Helpers::getJobsPath($_, 'logs')
		}
	}

	return ($opIndex - 1);
}

#*****************************************************************************************************
# Subroutine			: displayDateMenu
# Objective				: This subroutine displays the date options menu
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub displayDateMenu {
	Helpers::display(["\n", 'select_option_to_view_logs_for', ':']);
	Helpers::display([map{$_ . ") ", Helpers::getStringConstant($dateMenuChoices{$_}) . "\n"} keys %dateMenuChoices], 0);
}

#*****************************************************************************************************
# Subroutine			: deleteAllJobLogs
# Objective				: This subroutine to delete all Job's Logs
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub deleteAllJobLogs {
	my %deletedLogs;
	Helpers::display(["\n", 'do_u_really_want_to_delete_all_yn'],1);
	my $deleteAllConfirmation = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($deleteAllConfirmation) eq 'n' ) {
		exit 1;
	}
	foreach my $jobType (keys %Configuration::availableJobsSchema) {
		$deletedLogs{$jobType} = deleteAllLogs($jobType);
	}
	return \%deletedLogs;
}

#*****************************************************************************************************
# Subroutine			: deleteAllLogs
# Objective				: This subroutine to delete all Logs
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub deleteAllLogs {
	my $jobType = $_[0];
	my $logDir = Helpers::getJobsPath($jobType, 'logs');
	my $jobDir = $logDir;
	$jobDir =~ s/LOGS//;
	my $count = 0;

	#print "\n\nlogDir:$logDir\n\n\n";
	if (-d $logDir) {
		my $listLogDir = Helpers::getECatfile($logDir);
		$count = `ls $listLogDir | wc -l`;
		chomp($count);
		#print "\nlogDir:$logDir\n";
		Helpers::removeItems($logDir);
	}

	if(opendir(DIR, $jobDir)) {
		foreach my $file (readdir(DIR))  {
			my $filePath = $jobDir.$file;
			if (-f $filePath and $file =~ /^(\d+)logstat.json$/) {
				#print "filePath:$filePath\n";
				unlink($filePath);
			}
		}
	}

	return $count;
}

#*****************************************************************************************************
# Subroutine			: deleteSelectedLogs
# Objective				: This subroutine to delete selected Logs
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub deleteSelectedLogs {
	my $jobType		 = 	$_[0];
	my @logsToDelete =	@{$_[1]};
	my $deletedCount = 	0;
	my $logDir = Helpers::getJobsPath($jobType, 'logs');
	my $jobDir = $logDir;
	$jobDir =~ s/LOGS//;
	foreach my $fileKey (@logsToDelete) {
		next unless ($_[2]{$fileKey});
		my $fileName = $fileKey."_".$_[2]{$fileKey};
		my $filePath = $logDir."/".$fileName;

		if (unlink($filePath)) {
			$deletedCount++;
		}
	}

	my @statArray = ();
	if($deletedCount and opendir(DIR, $jobDir)) {
		foreach my $file (readdir(DIR))  {
			my $filePath = $jobDir.$file;
			if ((-f $filePath) and ($file =~ /^(\d+)logstat.json$/)) {
				push(@statArray,$filePath);
			}
		}
		close DIR;

		deleteLogStatJSON(\@statArray, \@logsToDelete);
	}

	return $deletedCount;
}


#*****************************************************************************************************
# Subroutine			: deleteLogStatJSON
# Objective				: Delete a log stat files
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub deleteLogStatJSON {
	foreach my $logstatFile (@{$_[0]}) {
		next unless (-f $logstatFile);
		my %logs;
		if (-f $logstatFile) {
			%logs = %{JSON::from_json(
				'{' .
				substr(Helpers::getFileContents($logstatFile), 1) .
				'}'
			)};
		}

		foreach (@{$_[1]}) {
			if (exists $logs{$_}) {
				delete $logs{$_};
			}
		}
		unless (%logs) {
			unlink($logstatFile);
		}
		else {
			my $logstatInStrings = JSON::to_json(\%logs);
			substr($logstatInStrings, 0, 1, ',');
			substr($logstatInStrings, -1, 1, '');
			Helpers::fileWrite($logstatFile, $logstatInStrings);
		}
	}
}
