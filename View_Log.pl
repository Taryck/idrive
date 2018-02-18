#!/usr/bin/perl
##################################################
#Script Name : View_Log.pl
##################################################
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
use Time::Local;
require Constants;
require 'Header.pl';
#use strict;
#use warnings;
system("clear");
loadUserData();
headerDisplay($0);
my $confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

#This if and else block will check the user account configuration details and login details.

if(getAccountConfStatus($confFilePath)){
	exit(0);
}
else{
	if(getLoginStatus($pwdPath)){
			exit(0);
	}
}

my $menu        =       {'Backup'  => {1 => ["View logs for Manual Backup","$usrProfileDir/Backup/Manual/LOGS"],
				       2 => ["View logs for Scheduled Backup","$usrProfileDir/Backup/Scheduled/LOGS"]},
                         'Restore' => {3 => ["View logs for Manual Restore","$usrProfileDir/Restore/Manual/LOGS"], 
				       4 => ["View logs for Scheduled Restore","$usrProfileDir/Restore/Scheduled/LOGS"]},
                        };
my @columnNames = (['S.No.','Time & Date','Status'],[8,30,7]);#Contains two annonymous array one contais table header conter and other spaces related to that.
my $displayDateMenu = ['1) Last one week','2) Last two weeks','3) Last 30 days','4) Selected date range'];
my ($maxRangeForMenuChoice,$maxRangeForViewLogChoice) = (4,4);
my %optionwithLogName = (); 
my $currentEpochtime = time();
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Operation Start ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
print $lineFeed.Constants->CONST->{'AskOption'}.qq($lineFeed$lineFeed);
displayMenu($menu);
print $lineFeed.Constants->CONST->{'EnterChoice'};
my $userChoice = <STDIN>;
Chomp(\$userChoice);
$userChoice =~ s/^0+(\d+)/$1/g;#removing initial zero from the user input for given choice.
my $keyName = ($userChoice <= $maxRangeForMenuChoice) ? returnKeyName($userChoice,['Backup','Restore']) : q();
unless ($keyName){
        print $lineFeed.Constants->CONST->{'InvalidChoice'}.Constants->CONST->{'TryAgain'}.$lineFeed;
        exit(0);
}
my %logFileList = isLogFilesPresent();#this will check if log is present for the selected Job, i.e. Manual Backup/restore and scheduled backup/restore.

			## Logic to handle date range scenario. ##

my $userDateChoice = '';
my $userDateChoiceCount = 4;
print $lineFeed.Constants->CONST->{'viewLogMessage'}.$lineFeed;
displayMenu($displayDateMenu);
while($userDateChoiceCount != 0 and $userDateChoice eq ''){
	print $lineFeed.$lineFeed.Constants->CONST->{'EnterChoice'};
	$userDateChoice = <STDIN>;
	Chomp(\$userDateChoice);
	$userDateChoice =~ s/^0+(\d+)/$1/g;#removing initial zero from the user input for given choice.
        if(($userDateChoice eq '') or ($userDateChoice > 4 or $userDateChoice <= 0) or $userDateChoice !~ /\d+/ or $userDateChoice =~ /\s+/){
                print Constants->CONST->{'InvalidChoice'}.$whiteSpace;
                $userDateChoice = '';
        }
	$userDateChoiceCount--;
}
if($userDateChoiceCount == 0 and $userDateChoice eq ''){
	print Constants->CONST->{'TryAgain'}.$lineFeed;
        exit(0);
}
my ($startEpoch,$endEpoch) = ('') x 2;
if ($userDateChoice =~/^0?4$/){#This code will take start date and end date input from user.
	#This function will take date input from user by calling getUserDateRange() . Convert it to epoch time and assign to global variables $startEpoch,$endEpoch respectively. All the basic error handling is done in this function.
	convertUserDateToEpoch();
}else{
	($startEpoch,$endEpoch) = getStartAndEndEpochTime($userDateChoice);
}
			## Logic to handle date range scenario End. ##
viewLogFile();
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Operations End +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Defining utility functions ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#****************************************************************************
#Subroutine Name         : viewLogFile 
#Objective               : To select the log which user wants to view and open in vi editor .
#Usgae                   : viewLogFile()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub viewLogFile{
	my $showLogs = 1;
	while ($showLogs){# This loop is to display the log list again and again.
		displayLogList(\@columnNames,\%logFileList); #This function will display the log list.
		print Constants->CONST->{'ctrlc2Exit'}.$lineFeed;
		my $logFileChoice = '';
		getChoiceToViewLog(\$logFileChoice);
		openViEditor($menu,$keyName,$userChoice,$logFileChoice);
		print $lineFeed.Constants->CONST->{'viewMoreLogs'};
		my $viewLogconfirmation = getConfirmationChoice();
		if ($viewLogconfirmation eq 'N' or $viewLogconfirmation eq 'n'){
			$showLogs = 0;
		}
	}
}

#****************************************************************************
#Subroutine Name         : getChoiceToViewLog(\logFileChoice)
#Objective               : Get user choice to view log file. A scalar referece is passed to avoid explicit return statement.
#Usgae                   : getChoiceToViewLog(\$logFileChoice)
#			   where : $logFileChoice : This variable contains the serial number corresponding to which user wants to view the log.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getChoiceToViewLog{
	my $logFileChoice = shift;
	my $userViewLogInputCount = 4;
	while ($userViewLogInputCount != 0 and ${$logFileChoice} eq ''){#This while loop is for user retry count.
                print $lineFeed.Constants->CONST->{'logChoice'};
                ${$logFileChoice} = <STDIN>;
                Chomp($logFileChoice);
                ${$logFileChoice} =~ s/^0+(\d+)/$1/g;#removing initial zero from the user input for given choice.
                if((${$logFileChoice} eq '') or (${$logFileChoice} > (scalar (keys %optionwithLogName)) or ${$logFileChoice} <= 0) or ${$logFileChoice} !~ /^\d+$/ or ${$logFileChoice} =~ /\s+/){
                        print $lineFeed.Constants->CONST->{'InvalidChoice'}.$whiteSpace;
                	${$logFileChoice} = '';
                }
        	$userViewLogInputCount--;
	}
        if ($userViewLogInputCount == 0 and ${$logFileChoice} eq ''){
	        print Constants->CONST->{'TryAgain'}.$lineFeed;
                exit(0);
        }
}
#****************************************************************************
#Subroutine Name         : getLogFileNames
#Objective               : To get the log file names in a hash where timestamp will be the key and log status will be the value.
#			   Note: log name is the combination of timestamp and log status, timestamp_status. Eg:1495015819_SUCCESS
#Usgae                   : getLogFileNames($menu,$keyName,$userChoice)
#                        : $menu	: A data structure which contains content for menu display and location related to displayed option from where data can be fetched.
#                          $keyName	: Name of the key which is related to user. Eg : Backup or Restore.   
#                          $userChoice	: Option selected by user. This will be used to find the location from where log files can be fetched.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub getLogFileNames{
	my $logFileLocation = $_[0]->{$_[1]}->{$_[2]}->[1];#HashRef->{keyName}->{keyName}->[arrRefIndex]
	my @logFiles = ();
	my %timestampStatus = ();
	if (-e $logFileLocation){
		@logFiles = `ls '$logFileLocation'`; #This is done to process ls command at one shot, if used with map processing of ls will continue till all the file processing has been completed.
		%timestampStatus = map {m/(\d+)_([A-Z]+)/} @logFiles;
		return %timestampStatus;
	}else{
		print $lineFeed.Constants->CONST->{'noLogs'}.$lineFeed;
		traceLog($whiteSpace.Constants->CONST->{'noLogs'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();
	}
}
#****************************************************************************
#Subroutine Name         : displayLogList
#Objective               : To print the list of available logs in the of date & time when log was generated and status.
#Usgae                   : displayLogList(\@columnNames,\%logFileList)
#                        : @columnNames       : second index array ref is used to give the spaces between the data.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub displayLogList{
	my @columnNames = @{$_[0]};
	my %logFileList = %{$_[1]};
	my $tableHeader = getTableHeader(@columnNames);
	my ($displayCount,$spaceIndex,$tableContent)= (1,0,'');#$displayCount is serial number which will be displayed. $spaceIndex is used to print number of required spaces as in @columnNames array.
	foreach (sort {$b <=> $a} keys %logFileList){
		if ((($startEpoch <= $_) and ( $endEpoch >= $_))){
			$tableContent .= $displayCount;
			$tableContent .= (' ') x ($columnNames[1]->[$spaceIndex] - length($displayCount));#(total_space - used_space by data) will be used to keep separation between 2 data
			$spaceIndex++;
			$tableContent .= localtime($_);
			$tableContent .= (' ') x ($columnNames[1]->[$spaceIndex] - length(localtime($_)));#(total_space - used_space by data) will be used to keep separation between 2 data
			$tableContent .= $logFileList{$_};
			$spaceIndex++;
			$tableContent .= (' ') x ($columnNames[1]->[$spaceIndex] - length($logFileList{$_}));#(total_space - used_space by data) will be used to keep separationbetween 2 data
			$tableContent .= $lineFeed;
			$optionwithLogName{$displayCount} = $_.'_'.$logFileList{$_};#creating another hash which contain searial number and logname as key and value pair so that later it can be used to display the log file.
			$spaceIndex = 0;
			$displayCount++;	
		}
	}
	if ($tableContent ne ''){
		print $lineFeed.Constants->CONST->{'logList'}.$lineFeed;;
		print $tableHeader.$tableContent.$lineFeed;
	}else{
		print $lineFeed.Constants->CONST->{'noLogs'}.$lineFeed;
		traceLog($whiteSpace.Constants->CONST->{'noLogs'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();		
	}
}

#****************************************************************************
#Subroutine Name         : openViEditor
#Objective               : To open vi editor for given file.
#Usgae                   : openViEditor($menu,$keyName,$userChoice)
#                        : $menu        : Contains data related to menu operation.
#                        : $keyName     : name of the key correcponding to user's choice from $menu.
#                        : $userChoice  : user's choice from $menu.
#                          $logFileChoice : Name of the logFile which user wants to view.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub openViEditor {
        my $fileLocation = $_[0]->{$_[1]}->{$_[2]}->[1].'/'.$optionwithLogName{$_[3]};
	print $lineFeed.Constants->CONST->{'viClosureMessage'}.$lineFeed;
	print $lineFeed.Constants->CONST->{'logOpeningMessage'}.$lineFeed;
	holdScreen2displayMessage(4);	
	my $logdisplayStatus = system "vi '$fileLocation'";
	if ($logdisplayStatus == 0){
		print $lineFeed.Constants->CONST->{'logDispSuccess'}.$lineFeed;
	}else{
		print $lineFeed.Constants->CONST->{'errorDisplayLog'}.$whiteSpace."Reason : $!\n";
	}
}
#****************************************************************************
#Subroutine Name         : convertUserDateToEpoch
#Objective               : To covert user date to epoch and assign it to lexical variable $startEpoch and $endEpoch.
#Usage                   : convertUserDateToEpoch()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub convertUserDateToEpoch{
        my ($startDate,$endDate,$invalidDateMessage) = ('') x 3;
        my $inputCount = 3;
        while($inputCount and ($startDate eq '' or $endDate eq '')){
                ($startDate,$endDate) = getUserDateRange();
                if ($startDate ne '' and $endDate ne ''){
	 		#finding epoch time for given user date under this section and handling some error.
			$startDate .= ' 00:00:00';
			$endDate .= ' 23:59:59';
                        my $stEpochTimeCmd = 'date --date="'.$startDate.'" +%s';
                        my $edEpochTimeCmd = 'date --date="'.$endDate.'" +%s';
                        $startEpoch = `$stEpochTimeCmd $errorRedirection`;#$startEpoch global variable
			Chomp(\$startEpoch);
			$invalidDateMessage = checkDateValidity($startEpoch);
                        $endEpoch = `$edEpochTimeCmd $errorRedirection`;#$endEpoch global variable 
			Chomp(\$endEpoch);
			$invalidDateMessage .= checkDateValidity($endEpoch);
			if ($invalidDateMessage ne ''){
				($startDate,$endDate,$startEpoch,$endEpoch) = ('') x 4;
				print $invalidDateMessage;
			}
			my $currentEpochPlusOne = $currentEpochtime + (1*24*60*60); 
                        if (($startEpoch > $currentEpochPlusOne) || ($endEpoch > $currentEpochPlusOne)){#Error handling if start date is grater than current date.
                                ($startDate,$endDate,$startEpoch,$endEpoch) = ('') x 4;
				print $lineFeed.Constants->CONST->{'stDatEdDateGraterCurrentDate'};
                        }
                        if($startEpoch > $endEpoch){#Error hanlding if start date is grater than end date.
				($startDate,$endDate,$startEpoch,$endEpoch) = ('') x 4;
				print $lineFeed.Constants->CONST->{'stDateGraterEndDate'};
                        }
                }else{
                        print $lineFeed.Constants->CONST->{'invalidDate'};
                }
                $inputCount--;
        }
        exit(0) if ($inputCount == 0 and ($startDate eq '' or $endDate eq ''));
}
#****************************************************************************
#Subroutine Name         : isLogFilesPresent
#Objective               : To check if for selected job i.e Manual/Scheduled Backup/Restore, log file is present or not. If not it will terminate the script by giving user error message else it will return the logfile name hash. Where key will be epoch time when log was created and value will be the status of log file.
#Usage                   : isLogFilesPresent()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub isLogFilesPresent{
	my %logFileList = getLogFileNames($menu,$keyName,$userChoice);
	if (scalar (keys %logFileList) > 0){
		return %logFileList;
	}else{
		print $lineFeed.Constants->CONST->{'noLogs'}.$lineFeed;
		traceLog($whiteSpace.Constants->CONST->{'noLogs'}.$lineFeed, __FILE__, __LINE__);
		exit(0);
	}	
}

sub checkDateValidity{
	if ($_[0] =~ /.*?(invalid date) \‘(\d{2}\/\d{2}\/\d{4}).*?\’/){
		return ucfirst($1).': '.$2.$lineFeed;
	}
}
