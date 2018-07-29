#!/usr/bin/perl
#*****************************************************************************************************
# 						This scritp is used to view the selected logs									
# 							Created By: Sabin Cheruvattil												
#****************************************************************************************************/
use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')) ;	} else { use lib '.' ; }

use Helpers;
use Strings;
use Configuration;
use Time::Local;
use File::Basename;

tie(my %dateMenuChoices, 'Tie::IxHash', '1' => 'last_one_week', '2' => 'last_two_weeks', '3' => 'last_30_days', '4' => 'selected_date_range');

my (%logMenuToPathMap, %optionwithLogName);

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	system('clear');
	Helpers::loadAppPath();
	Helpers::loadServicePath() 			or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername()				or Helpers::retreat('login_&_try_again');
	Helpers::loadUserConfiguration()	or Helpers::retreat('your_account_not_configured_properly');
	Helpers::isLoggedin()            	or Helpers::retreat('login_&_try_again');
	
	Helpers::displayHeader();
	
	# show log menu and get the input from user
	my $maxMenuChoice = displayLogMenu();
	my $userMenuChoice = Helpers::getUserMenuChoice($maxMenuChoice);
	
	my $logDir			= Helpers::getUserFilePath($logMenuToPathMap{$userMenuChoice});
	my %logFileList		= getLogsList($logDir);
	
	# make sure the logs are present for the selected job type: backup, restore, express backup
	Helpers::retreat(["\n", 'no_logs_found', '.', ' ', 'please_try_again', '.']) unless scalar keys %logFileList;
	
	# show date menu and get inputs from user
	displayDateMenu();
	my $userDateChoice	= Helpers::getUserMenuChoice(scalar keys %dateMenuChoices);
	my ($startEpoch, $endEpoch) = ('', '');
	if($userDateChoice == 4) {
		# Convert start and end time to epoch
		($startEpoch, $endEpoch) = getUserDateRange();
	} else {
		($startEpoch, $endEpoch) = getStartAndEndEpochTime($userDateChoice);
	}
	
	# show logs
	my ($logFileChoice, $viewLogConf) = ('', 'n');
	do {
		# show log list
		my $displayLogCount = displayLogList(\%logFileList, $startEpoch, $endEpoch);
		Helpers::display(["\n", '__note_please_press_ctrlc_exit']);

		$logFileChoice = getChoiceToViewLog($logFileChoice);
		Helpers::openEditor('view', qq($logDir$optionwithLogName{$logFileChoice}));
		if($displayLogCount > 1) {
			Helpers::display(['do_you_want_to_view_more_logs_yn', "\n"]);
			$viewLogConf = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		}
	} while($viewLogConf eq 'y');
	
	exit;
}

#*****************************************************************************************************
# Subroutine			: getUserDate
# Objective				: This subroutine will get the date from the user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserDate {
	my($dateMessage, $date, $choiceRetry) = (shift, '', 0);
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		Helpers::display(["\n", $dateMessage, ': '], 0);
		$date 	= Helpers::getUserChoice();
		$date	=~ s/^[\s\t]+|[\s\t]+$//g;
		
		$choiceRetry++;
		if($date eq '') {
			Helpers::checkRetryAndExit($choiceRetry, 0);
			Helpers::display(["\n", 'cannot_be_empty', '.', ' ', 'please_try_again', '.']);
		} elsif(!Helpers::validateDatePattern($date) || !isValidDate($date)) {
			Helpers::checkRetryAndExit($choiceRetry, 1);
			Helpers::display(["\n", 'invalid_date_or_format', '.', ' ', 'please_try_again', '.']);
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
		$startDate 	= getUserDate('enter_log_start_date__');
		$endDate	= getUserDate('enter_log_end_date__');
		
		$choiceRetry++;
		if(!validateUsersDateRange(\$startDate, \$endDate, \$errorMessage)) {
			($startDate, $endDate) = ('') x 2;
			Helpers::checkRetryAndExit($choiceRetry, 1);
			Helpers::display(["\n", $errorMessage, '. ', 'please_try_again', '.']);
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
		$logFileChoice	= Helpers::getUserChoice();
		$logFileChoice	=~ s/^[\s\t]+|[\s\t]+$//g;
		$logFileChoice	=~ s/^0+(\d+)/$1/g;
		
		$choiceRetry++;
		if($logFileChoice eq '') {
			Helpers::checkRetryAndExit($choiceRetry, 0);
			Helpers::display(["\n", 'cannot_be_empty', '.', ' ', 'please_try_again', '.']);
		} elsif($logFileChoice !~ m/^\d+$/ || $logFileChoice > scalar keys %optionwithLogName || $logFileChoice <= 0) {
			Helpers::checkRetryAndExit($choiceRetry);
			$logFileChoice = '';
			Helpers::display(['invalid_choice', '.', ' ', 'please_try_again', '.']);
		} else {
			last;
		}
	}
	
	return $logFileChoice;
}

#*****************************************************************************************************
# Subroutine			: openViEditor
# Objective				: To open vi editor for given file.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub openViEditor {
    my $fileLocation = $_[0];
	Helpers::display(["\n", 'press_esc_q_and_enter_to_exit_vi_editor']);
	Helpers::display(["\n", 'opening_log_file', '...']);
	sleep(2);
	
	my $logdisplayStatus = system("vi '$fileLocation'");
	if($logdisplayStatus == 0) {
		Helpers::display(["\n", 'log_displayed_successfully', '.']);
		return;
	}
	
	Helpers::display(["\n", 'error_in_display_log', '. ', ucfirst($Locale::strings{'reason'}), ': ', $!]);
}

#*****************************************************************************************************
# Subroutine			: displayLogList
# Objective				: To print the list of available logs in the of date & time when log was generated and status.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub displayLogList {
	my %logFileList = %{$_[0]};
	my ($startEpoch, $endEpoch) = ($_[1], $_[2]);
	my @columnNames = (['S.No.', 'Time & Date', 'Status'], [8, 30, 7]);
	my $tableHeader = getTableHeader(@columnNames);
	my ($displayCount, $spaceIndex, $tableContent) = (1, 0, '');
	
	foreach(sort {$b <=> $a} keys %logFileList) {
		if((($startEpoch <= $_) && ($endEpoch >= $_))) {
			$tableContent 	.= $displayCount;
			# (total_space - used_space by data) will be used to keep separation between 2 data
			$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($displayCount));
			$spaceIndex++;
			$tableContent 	.= localtime($_);
			# (total_space - used_space by data) will be used to keep separation between 2 data
			$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length(localtime($_)));
			$tableContent 	.= $logFileList{$_};
			$spaceIndex++;
			# (total_space - used_space by data) will be used to keep separation between 2 data
			$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($logFileList{$_}));
			$tableContent 	.= qq(\n);
			#creating another hash which contain serial number and log name as key and value pair so that later it can be used to display the log file.
			$optionwithLogName{$displayCount} = $_ . '_' . $logFileList{$_};
			$spaceIndex = 0;
			$displayCount++;	
		}
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
	
	$tmpStart		.= ' 00:00:00';
	$tmpEnd 		.= ' 23:59:59';
	
	$$startDate 	= `date --date="$tmpStart" +%s`;
	$$endDate		= `date --date="$tmpEnd" +%s`;
	
	Helpers::Chomp($startDate);
	Helpers::Chomp($endDate);
	
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
	
	foreach my $mainOperation (keys %Configuration::logMenuAndPaths) {
		Helpers::display([$mainOperation . '_title', ':']);
		# @menuOptions = keys $Configuration::logMenuAndPaths{$mainOperation};
		# @menuOptions = sort @menuOptions;
		@menuOptions = sort keys %{$Configuration::logMenuAndPaths{$mainOperation}};
		Helpers::display([map{qq(\t) . $opIndex++ . ") ", $Locale::strings{$_} . "\n"} @menuOptions], 0);
		%logMenuToPathMap = (%logMenuToPathMap, map{$pathIndex++ => $Configuration::logMenuAndPaths{$mainOperation}{$_}{'path'}} @menuOptions);
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
	Helpers::display([map{"\t" . $_ . ") ", $Locale::strings{$dateMenuChoices{$_}} . "\n"} keys %dateMenuChoices], 0);
}

#*****************************************************************************************************
# Subroutine			: getLogsList
# Objective				: This subroutine gathers the list of log files
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getLogsList {
	my %timestampStatus = ();
	my @tempLogFiles;
	my $logDir = $_[0];
	if (-e $logDir) {
		@tempLogFiles = `ls '$logDir'`;
		%timestampStatus = map {m/(\d+)_([A-Z]+)/} @tempLogFiles;
	}
	
	return %timestampStatus;
}

#*****************************************************************************************************
# Subroutine			: getStartAndEndEpochTime
# Objective				: To return the start and end date epoch time.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStartAndEndEpochTime {
	# $userChoice => 1) One week before, 2) Two week before, 3) One month before, 4) Given date range
	my $userOption 			= shift;
	my $currentTimeStamp 	= time();
	my $daysToSubstract 	= ($userOption == 1) ? 7 : ($userOption == 2) ? 14 : 30;
	my $startTimeStamp 		= $currentTimeStamp - ($daysToSubstract * 24 * 60 * 60);
	return ($startTimeStamp, $currentTimeStamp);
}
