#!/usr/bin/perl
################################################################################
#Script Name : Scheduler_Script.pl
################################################################################

unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require 'Header.pl';
use File::Copy;

use constant false => 0;
use constant true => 1;

#use Constants 'CONST';
require  Constants;

#Whether the Scheduler script is invoked by the user or by the backup script#
my $invokedScript = false;
my ($terminateHour,$terminateMinute,$selectJobTermination,$editFlag,$noRoot,$rmFlag,$numArguments,$hour,$minute) = (0) x 9;
my ($user,$scheduleMsg,$emailAddr,$scriptType,$scriptName,$scriptPath,$checkScriptCronEntry,$confirmationChoice,$entryCrontabString,$crontabEntry,$crontabEntryStatus,$maximumAttemptMessage) = ('') x 12;
$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};
if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 
getConfigHashValue();
loadUserData();
#checkEncType(1); #Asuming not useful, its commented.
#$pvtParam = "PVTKEY";
#getParameterValue(\$pvtParam, \$hashParameters{$pvtParam});
#my $pvtKey = $hashParameters{$pvtParam};
if(getAccountConfStatus($confFilePath,\&headerDisplay)){
	exit(0);
}
else{
	if(getLoginStatus($pwdPath,\&headerDisplay)){
			exit(0);
	}
}
if (! checkIfEvsWorking($dedup)){
        print Constants->CONST->{'EvsProblem'}.$lineFeed;
        exit 0;
}
##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script during backup #
##############################################
$SIG{INT} = \&cancelProcess;
$SIG{TERM} = \&cancelProcess;
$SIG{TSTP} = \&cancelProcess;
$SIG{QUIT} = \&cancelProcess;

#Assigning Perl path
my $perlPath = `which perl`;
chomp($perlPath);	
if($perlPath eq ''){
	$perlPath = '/usr/local/bin/perl';
}

# Trace Log Entry #
my $curFile = basename(__FILE__);
traceLog("$lineFeed File: $curFile $lineFeed---------------------------------------- $lineFeed", __FILE__, __LINE__);

my $workingDir = $currentDir;

$workingDir =~ s/\'/\'\\''/g;
$workingDir =~ s/\"/\\\\\\"/g;
$workingDir =~ s/\\\$/\\\$/g;
$workingDir =~ s/\`/\\\\\\`/g;
$workingDir = "'".$workingDir."'";

quotemeta($workingDir);

my $choice = undef;
my @options = ();
#Hash containing the weekdays#
my %hashDays = ( 1 => "MON",
                 2 => "TUE",
                 3 => "WED",
                 4 => "THU",
                 5 => "FRI",
                 6 => "SAT",
                 7 => "SUN",
                 '*' => "daily"
               );
 
checkUser();
system("clear");
headerDisplay($0);
PRINTMENU:
printMainMenu();
my $mainMenuChoice = getMenuChoice(6);	
loadType();
$crontabEntryStatus = checkEntryExistsCrontab();
if($mainMenuChoice == 1 || $mainMenuChoice == 3) {
	if ($mainMenuChoice == 1 and $dedup eq 'on'){
		print qq{Your Backup Location name is "}.$backupHost.qq{". $lineFeed};
	}else{
		emptyLocationsQueries(\$maximumAttemptMessage);
	} 
	#If the backup job already exists in crontab#
	if ($crontabEntryStatus){
		print $maximumAttemptMessage;
		exit(0) if($maximumAttemptMessage =~ /verify your proxy details or check connectivity|password mismatch|encryption verification failed|Failed to connect/i);
		print $lineFeed.Constants->CONST->{'existingSchJob'}." $jobType Job.";
		print $whiteSpace.Constants->CONST->{'schEditQuery'}.$whiteSpace;
	
		$confirmationChoice = getConfirmationChoice();
		if($confirmationChoice eq "n" || $confirmationChoice eq "N") {  
			exit;
		}
		$editFlag = 1;
	}
	scheduleJob();
	my $writeFlag = writeToCrontab();
	if(!$writeFlag) {
		print $lineFeed.$jobType.' '.Constants->CONST->{'jobNotSch'}.$lineFeed;
		exit(1);
	}
	system('stty','echo');
	print $scheduleMsg;
	createFileSet();
} elsif($mainMenuChoice == 2 || $mainMenuChoice == 4) {
	if(checkEntryExistsCrontab()) {
		$rmFlag = 1;
		print $lineFeed.Constants->CONST->{'delExistingSchJob'}." $jobType Job(y/n)?";
		$confirmationChoice = getConfirmationChoice();
		
		if($confirmationChoice eq "y" || $confirmationChoice eq "Y") {
			removeEntryFromCrontabLines();
			my $writeFlag = writeToCrontab();
			if(!$writeFlag) {
				print "\nUnable to delete Schedule $jobType Job.\n";
			} else {
				print $lineFeed.$jobType.' '.Constants->CONST->{'jobRemoveSuccess'}.$lineFeed;
			}
		}
	} else {
		print $lineFeed.Constants->CONST->{'noSchJob'}." $jobType Job. \n\n";
	}
	system('stty','echo');
}elsif ($mainMenuChoice == 5){
	displayScheduledJobs($jobType);
	goto PRINTMENU;
}elsif ($mainMenuChoice == 6){
	cancelProcess();	
}
sub displayScheduledJobs{
	my ($bCuttoffFlag,$rCuttoffFlag) = ('Off') x 2;
	my ($bCutMin,$bCutHr,$rCutMin,$rCutHr,$bCutTime,$rCutTime) = (undef) x 6;
	my ($bSchMin,$bSchHr,$bSchFrequency) = (undef) x 3;
	my ($rSchMin,$rSchHr,$rSchFrequency) = (undef) x 3;
	my (@schBackData,@schResData) = (()) x 2;
	my $tableData = '';
	my $backupScheduledJob = (split('/',$usrProfilePath))[-1]."/$userName/Backup/Scheduled";
	my $restoreScheduleJob = (split('/',$usrProfilePath))[-1]."/$userName/Restore/Scheduled";
	my $readable = readFromCrontab();
	if($readable == 0){
		@linesCrontab = readCrontabAsRoot();
	}
	my @schBackupJobs = grep /$backupScheduledJob/,@linesCrontab;
	if (scalar(@schBackupJobs) > 0 ){
		($bSchMin,$bSchHr,$bSchFrequency) = (split (/ /,$schBackupJobs[0]))[0,1,4];
		$bSchFrequency = 'DAILY' if ($bSchFrequency eq '*');
		if ($schBackupJobs[1] ne ''){
			$bCuttoffFlag = 'On';
			($bCutMin,$bCutHr) = (split (/ /,$schBackupJobs[1]))[0,1];
			$bCutTime = ($bCutMin ne '' and $bCutHr ne '') ? $bCutHr.':'.$bCutMin : '';
		}
		@schBackData = ('Backup',$bSchFrequency,"$bSchHr:$bSchMin",$bCuttoffFlag,$bCutTime);
	}
	my @schRestoreJobs = grep /$restoreScheduleJob/,@linesCrontab;
	if (scalar(@schRestoreJobs) > 0){
		($rSchMin,$rSchHr,$rSchFrequency) = (split (/ /,$schRestoreJobs[0]))[0,1,4];
		$rSchFrequency = 'DAILY' if ($rSchFrequency eq '*');
        	if ($schRestoreJobs[1] ne ''){
                	$rCuttoffFlag = 'On';
	                ($rCutMin,$rCutHr) = (split (/ /,$schRestoreJobs[1]))[0,1];
			$rCutTime = ($rCutMin ne '' and $rCutHr ne '') ? $rCutHr.':'.$rCutMin : '';
        	}
		@schResData = ('Restore',$rSchFrequency,"$rSchHr:$rSchMin",$rCuttoffFlag,$rCutTime);
	}
	my @columnNames = (['Job Name','Frequency','Scheduled Time','Cut-off','Cut-off Time'],[11,26,16,10,15]);
	my $tableHeader = (getTableHeader(@columnNames));
	$tableHeader  =~ s/\n$//;
	my $tableData = getScheduleJobTableData(\@schBackData,\@schResData,$columnNames[1]);
	if ($tableData ne ''){
		print $lineFeed.Constants->CONST->{'scheduleJobDet'}.$lineFeed;
		print $tableHeader.$lineFeed.$tableData;
	}else{
		print $lineFeed.Constants->CONST->{'noSchJob'}." Job. $lineFeed$lineFeed";
	}
	print $lineFeed;	
}
sub getScheduleJobTableData{
	my @displayData = (@{$_[0]},@{$_[1]});
	my @spacesBtwWords = @{$_[2]};
	my ($dataInOneLine,$spaceIndex,$tableData) = (5,0,'');
	foreach(@displayData){
		$tableData .= $_;
		$tableData .= ' ' x ($spacesBtwWords[$spaceIndex] - length($_));
		++$spaceIndex;
		if ($dataInOneLine == $spaceIndex){
			$spaceIndex = 0;
			$tableData .= $lineFeed;
		}
	}
	return $tableData;	
}
#****************************************************************************************************
# Subroutine Name         : scheduleJob.
# Objective               : Create a new backup/restore job /modify an existing backup job. 
# Added By                : Dhritikana
#*****************************************************************************************************/
sub scheduleJob {
	$crontabEntry =~ s/^\s+//;
	if(defined $crontabEntry) {
		my @optionsPresentCrontab = split / /, $crontabEntry;
		
		$dayOptionPresentCrontab = $optionsPresentCrontab[4];
		$hourOptionPresentCrontab = $optionsPresentCrontab[1];
		$minuteOptionPresentCrontab = $optionsPresentCrontab[0];
		
		my @dayOptionsPresentCrontab = ();
		if($dayOptionPresentCrontab ne '*') {
			@dayOptionsPresentCrontab = split /,/, $dayOptionPresentCrontab;
			$dayOptionPresentCrontab = undef;
			%reverseHashDays = reverse %hashDays;
			
			for(my $index = 0; $index <= $#dayOptionsPresentCrontab; $index++) {
				$dayOptionsPresentCrontab[$index] = $reverseHashDays{$dayOptionsPresentCrontab[$index]};
			}
			
			$dayOptionPresentCrontab = join ",", @dayOptionsPresentCrontab;
		}
	}
	mainOperation();
}

#****************************************************************************************************
# Subroutine Name         	: checkCronPermission.
# Objective               	: Subroutine to print Main Menu choice.
# Modified By				: Dhritikana
#*****************************************************************************************************/
sub printMainMenu
{
	print Constants->CONST->{'AskOption'}."\n\n";
#	print "\n";
	print "1) Schedule Backup Job\n";
	print "2) Delete Scheduled Backup Job\n";
	print "3) Schedule Restore Job\n";
	print "4) Delete Scheduled Restore Job\n";
	print "5) View Scheduled Jobs\n";
	print "6) Exit\n";
#	print "\n";
}

#****************************************************************************************************
# Subroutine Name         : checkCronPermission.
# Objective               : Subroutine to check if user has permission to access crontab.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub checkCronPermission {
	if (!-w "/etc/crontab") {
		return 1;
	} 
	return 0;
}

#****************************************************************************************************
# Subroutine Name         : getMenuChoice.
# Objective               : Subroutine to get Main Menu choice from user. 
# Added By                : 
#*****************************************************************************************************/
sub getMenuChoice {
	my $choice = undef;
	my $maxVal = $_[0];
	my $count = 0;
	while(!defined $choice) {
		if ($count < 4){
			print $lineFeed.Constants->CONST->{'EnterChoice'};
			$choice = <>;
			Chomp(\$choice);
			$choice =~ s/^0+(\d+)/$1/g;
			if($choice =~ m/^\d$/) {
				if($choice < 1 || $choice > $maxVal) {
					$choice = undef;
					print Constants->CONST->{'InvalidChoice'}." " if ($count < 3);
				} 
			} else {
				$choice = undef;
				print Constants->CONST->{'InvalidChoice'}." " if ($count < 3);
			}
		}else{
			print Constants->CONST->{'maxRetryattempt'}.' '.Constants->CONST->{'pleaseTryAgain'}.$lineFeed;
			exit;
		}
		$count++;
	}
	return $choice;
}

#****************************************************************************************************
# Subroutine Name         : loadType.
# Objective               : Subrouting to load jobType (Backup/Restore) based on User Choice. 
# Added By                : Dhritikana
#*****************************************************************************************************/
sub loadType {
	if($mainMenuChoice eq 1 or $mainMenuChoice eq 2) {
		$jobType = "Backup";
		$scriptType = Constants->FILE_NAMES->{backupScript};
	} elsif($mainMenuChoice eq 3 or $mainMenuChoice eq 4) {
		$jobType = "Restore";
		$scriptType = Constants->FILE_NAMES->{restoreScript};
	}

	$jobRunningDir = "$usrProfilePath/$userName/$jobType/Scheduled";
	$checkScriptCronEntry = (split('/',$usrProfilePath))[-1]."/$userName/$jobType/Scheduled";
	if(!-e $jobRunningDir) {
		my $ret = mkdir($jobRunningDir);
		if($ret ne 1) {
			print Constants->CONST->{'MkDirErr'}.$jobRunningDir.": $!".$lineFeed;
			exit 1;
		}
	}
	chmod $filePermission, $jobRunningDir;

	$scriptName = qq{$perlPath "$userScriptLocation/$scriptType"};
	$scriptPath = "cd ".qq("$jobRunningDir")."; ".$scriptName." SCHEDULED $userName";
}

#****************************************************************************************************
# Subroutine Name         : printChoiceOfDayWk.
# Objective               : Subroutine to print the menu of daily or weekly choices 
# Added By                : Dhritikana
#*****************************************************************************************************/
sub printChoiceOfDayWk
{
	system("clear");
	print $maximumAttemptMessage if ($crontabEntryStatus eq 'False' || $crontabEntryStatus == 0);
	exit(0) if($maximumAttemptMessage =~ /verify your proxy details or check connectivity|password mismatch|encryption verification failed|Failed to connect/i);	
	print Constants->CONST->{'enterChoiceSchJob'}."$jobType Job: $lineFeed$lineFeed";
	print "1) DAILY \n";
	print "2) WEEKLY \n";
#	print "\n";
}

#****************************************************************************************************
# Subroutine Name         : printAddCrontabMenu.
# Objective               : Subroutine to print the menu for adding an entry to crontab. 
# Added By                : 
#*****************************************************************************************************/
sub printAddCrontabMenu
{
	system("clear");
	
	print "Enter the Day(s) of Week for the Scheduled $jobType Job \n";
	print "Note: Use comma separator for selecting multiple days (E.g. 1,3,5) \n";
#	print " \n";
	print "1) MON \n";
	print "2) TUE \n";
	print "3) WED \n";
	print "4) THU \n";
	print "5) FRI \n";
	print "6) SAT \n";
	print "7) SUN \n";
#	print " \n";
}

#****************************************************************************************************
# Subroutine Name         : getDays.
# Objective               : Subroutine to get the days of week when the backup job should be executed. 
# Added By                : 
#*****************************************************************************************************/
sub getDays
{
=comment
	if(${$_[0]} ne "") {
		print Constants->CONST->{'previousChoice'};
		if(${$_[0]} eq '*') {
			print "daily\n";
		} else {
			print "${$_[0]}\n";
		}
	}
=cut
	my $choiceCount = 0;	
	while(!defined $choice) {
		if ($choiceCount == 3){
			print $lineFeed.Constants->CONST->{'maxRetry'}.$lineFeed;
			cancelProcess();
		}
		print Constants->CONST->{'EnterChoice'};
		chomp($choice = <>);
		$choice =~ s/,$//;
		Chomp(\$choice);
		$choice =~ s/\s+//g;
		$choice =~ s/^0+(\d+)/$1/g;
		$choiceCount ++;	
		if($choice =~ m/^(\d,)*\d$/) {
			@options = uniqueData(split /,/, $choice);
			$numArguments = $#options + 1;
			
			if($numArguments > 7) {
				$choice = undef;
				@options = ();
				print Constants->CONST->{'InvalidChoice'}." ";
			}
			else {
			#	my $duplicateExists = checkDuplicatesArray(\@options);
				
			#	if($duplicateExists) {
			#		$choice = undef;
			#		@options = ();
			#		print Constants->CONST->{'InvalidChoice'}." ";
			#	}
			#	else {
					my $entry;
					
					foreach $entry (@options) {
						if($entry < 1 || $entry > 7) {
							$choice = undef;
							@optionsoptions = ();
							print Constants->CONST->{'InvalidChoice'}." ";
							last;
						}
					} 
			#	}
			} 
		}
		else {
			$choice = undef;
			$choiceCount == 3 ? print Constants->CONST->{'InvalidChoice'} : print Constants->CONST->{'InvalidChoice'}." ";
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : getHour.
# Objective               : Subroutine to get the hour when the backup/restore job should be executed. 
# Added By                : 
#*****************************************************************************************************/
sub getHour
{
	if(!$selectJobTermination) {
		print "\nEnter Time of the Day when $jobType is supposed to run.\n";
	}
	
#	if(${$_[0]} ne "") {
#		print "Previously entered Hour: ${$_[0]} \n";
#	} 
	
	my $Choosenhour = undef;
	my $choiceCount = 0;
	while(!defined $Choosenhour) { 
		if ($choiceCount < 4){
			print "Enter Hour (0-23): ";
			chomp($Choosenhour = <>);
			Chomp(\$Choosenhour);
			if($Choosenhour eq "" or $Choosenhour =~ m/\D/ or $Choosenhour < 0 or $Choosenhour > 23 or $Choosenhour !~ m/^[0-9]{1,2}$/) {
				$Choosenhour = undef;
				print Constants->CONST->{'InvalidChoice'}." " if ($choiceCount < 3);
			}
			else {
				if(length $Choosenhour > 1 && $Choosenhour =~ m/^0/) {
				$Choosenhour = substr $Choosenhour, 1;  
				}
			return $Choosenhour;
			}
		}else{
			print Constants->CONST->{'maxRetry'}.$lineFeed;
			exit;
		}
		$choiceCount++;	
	}
}

#****************************************************************************************************
# Subroutine Name         : getMinute.
# Objective               : Subroutine to get the minute when the backup job should be executed. 
# Added By                : 
#*****************************************************************************************************/
sub getMinute
{
#	print "\n";
	
	if(${$_[0]} ne "") {
		print "Previously entered Minute: ${$_[0]}\n";
	}
	
	my $ChoosenMinute = undef;
	my $count = 0;
	while(!defined $ChoosenMinute) { 
		if ($count < 4){
			print "Enter Minute (0-59): ";
			chomp($ChoosenMinute = <>);
			Chomp(\$ChoosenMinute);
			if($ChoosenMinute eq "" or $ChoosenMinute =~ m/\D/ or $ChoosenMinute < 0 or $ChoosenMinute > 59 or $ChoosenMinute !~ /^[0-9]{1,2}$/){
				$ChoosenMinute = undef;
				print Constants->CONST->{'InvalidChoice'}." " if ($count < 3);
			}
			else {
				if(length $ChoosenMinute == 1) {
					$ChoosenMinute = "0".$ChoosenMinute;  
				}
				return $ChoosenMinute;
			}
		}else{
			print Constants->CONST->{'maxRetry'}.$lineFeed;
			exit;
		}
		$count++;
	}
	print "\n";
}

#****************************************************************************************************
# Subroutine Name         : getNscheduleCutOff.
# Objective               : Subroutine to get Cut Off Time from user and write to it crontab. 
# Added By                : Dhritikana Kalita
#*****************************************************************************************************/
sub getNscheduleCutOff {
	print "\n";
	print Constants->CONST->{'cuttoffNeeded'}." $jobType(y/n)? ";
	$confirmationChoice = getConfirmationChoice();
	if($confirmationChoice eq "y" || $confirmationChoice eq "Y") {  
		$selectJobTermination = 1;
		my $cuttoffretry = 3;	
		while($cuttoffretry) {
			$terminateHour = getHour();
			$terminateMinute = getMinute();
			my $cutoffDiff = 0;
			if($hour eq $terminateHour) {
				$cutoffDiff = $terminateMinute-$minute;
			}  
			elsif($terminateHour-$hour == 1 && $minute > 55) {
				$cutoffDiff = 60+$terminateMinute-$minute;
			} elsif($hour == 23 && $terminateHour == 0 && $minute > 55) {
				$cutoffDiff = 60+$terminateMinute-$minute;
			} else {
				last;
			}
			
			if($cutoffDiff >= 0 && $cutoffDiff < 5) {
				$cuttoffretry--;
				print Constants->CONST->{'WrongCutOff'}.$lineFeed;
			} else {
				last;
			}
		}
		if ($cuttoffretry == 0 ){# This code restricts user to enter cuttoff only till 3 retry after that it will come out.
			($terminateHour,$terminateMinute,$selectJobTermination) = (undef,undef,undef);
			print Constants->CONST->{'maxRetryCuttoff'}.$lineFeed;
		}else{# If user enters correct input the cutoff will be scheduled properly
			$scriptName = qq{$perlPath "$userScriptLocation/}.Constants->FILE_NAMES->{jobTerminationScript}.qq{"};
			$scriptPath = "cd ".qq("$jobRunningDir")."; ".$scriptName." scheduled_$jobType $userName";			
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : mainOperation.
# Objective               : Subroutine to get Cut Off Time from user. 
# Added By                : Dhritikana Kalita
#*****************************************************************************************************/
sub mainOperation {
	printChoiceOfDayWk();
	$dayWkOp = getMenuChoice(2);
	my $cuttOffDailyFlag = 0;
	if($dayWkOp eq 2) {
		printAddCrontabMenu();
#		getDays(\$dayOptionPresentCrontab);
		getDays();#As now we are not showing the previous choice so there is not point of sending $dayOptionPresentCrontab in argument.
	} else {
		$choice = "*";
		$cuttOffDailyFlag = 1;
		$numArguments = 7;
	}
	
	$hour = getHour();
	$minute = getMinute();
	
	if($editFlag) {
		removeEntryFromCrontabLines();
	}
	$entryCrontabString = createCrontabEntry(\$scriptPath, \$minute, \$hour);
	push(@linesCrontab, $entryCrontabString);

	my @daysEntered = ();
	if($choice ne '*') {
		@daysEntered = uniqueData(split /,/, $choice);
	} else {
		@daysEntered = '*';
	}
	if (scalar(@daysEntered) == 7){#If user enters all the days of week then coverting array entry to * so that daily can be displayed
                        @daysEntered = ('*');
                        $cuttOffDailyFlag = 1; #For cutt-off this flag should be initialized with 1 as user enter all days of the week after selecting weekly.
        }
	if(($mainMenuChoice == 1 || $mainMenuChoice == 3) and $editFlag == 0) {
		$scheduleMsg = "\n$jobType Job has been scheduled successfully for";
	
		foreach my $value (@daysEntered) {
			$scheduleMsg .= " $hashDays{$value}";
		}
		$scheduleMsg .= " at $hour:$minute ";
	}
	elsif(($mainMenuChoice == 1 || $mainMenuChoice == 3) and $editFlag == 1) {
		my @daysEnteredCrontab = ();
		if($dayOptionPresentCrontab ne '*') {
			@daysEnteredCrontab = split /,/, $dayOptionPresentCrontab;
		} else {
			@daysEnteredCrontab = '*';
		}
			
		$scheduleMsg .= "$jobType Job has been modified successfully to";
		
		#Commented by Senthil for Snigdha_2.11_7_2
		#foreach my $value (@daysEnteredCrontab) {
			#$scheduleMsg .= " $hashDays{$value}";
		#}		
		#$scheduleMsg .= " at $hourOptionPresentCrontab:$minuteOptionPresentCrontab to";
		
		foreach my $value (@daysEntered) {
			$scheduleMsg .= " $hashDays{$value}";
		}
		$scheduleMsg .= " at $hour:$minute ";
	}
	
	getNscheduleCutOff();
	if(!$selectJobTermination) {
		$scheduleMsg =~ s/\s$/\.$lineFeed/;#if no cutt off has been added then we need to put new line at the end of message.
		emailNotifyQueries();
		return;
	}
	
	#$scheduleMsg .= "Cut off for $jobType has been scheduled successfully for";
	$scheduleMsg .= "with cut off time for";
	if ($cuttOffDailyFlag == 1){
		$scheduleMsg .= " daily";
	}else{# code to calculate cut-off for shifting days 
		@options = ();
		foreach my $value (@daysEntered){
			if ($terminateHour <= $hour){# hour given in cut-off is less than actual hour for job then days will increment by 1
				if ($terminateMinute <= $minute){# cut-off and actual hr same min is comp. cut-off min less actual min day inc. 1
					$value = $value+1;
				}elsif((($terminateHour < $hour) and ($terminateMinute > $minute))){
					$value = $value+1;
				}
			}
			$value = 1 if($value == 8);
			push(@options, $value);
			$scheduleMsg .= " $hashDays{$value}";
		}
		$numArguments = $#options + 1;
	}
	
	$entryCrontabString = createCrontabEntry(\$scriptPath, \$terminateMinute, \$terminateHour);
	push(@linesCrontab, $entryCrontabString);
	
	$scheduleMsg .= " at $terminateHour:$terminateMinute.\n";
	
	emailNotifyQueries();
}

#****************************************************************************************************
# Subroutine Name         : checkDuplicatesArray.
# Objective               : Subroutine to check if the same day has been entered more than once by the user. 
# Added By                : 
#*****************************************************************************************************/
sub checkDuplicatesArray
{
	my $retVal = false;
	my @originalArray = @{$_[0]};  
	my %optionsHash = ();
	
	foreach $var (@originalArray) {
		if(exists $optionsHash{$var}) {
			$optionsHash{$var}++;
		}
		else {
			$optionsHash{$var} = 1;
		}
	}  
	
	while(($key,$value) = each(%optionsHash)) {
		if($value > 1) {
			$retVal = true;
			last;
		}
	}
	
	return $retVal;
}

#****************************************************************************************************
# Subroutine Name         : createCrontabEntry.
# Objective               : Subroutine to create the string to be entered into crontab. 
# Added By                : 
#*****************************************************************************************************/
sub createCrontabEntry
{
	my $scriptPath = ${$_[0]};
	my $entryCrontabString  = ${$_[1]};
	$entryCrontabString .= " ";
	$entryCrontabString .= ${$_[2]};
	$entryCrontabString .= " ";
	$entryCrontabString .= "*";
	$entryCrontabString .= " ";
	$entryCrontabString .= "*";
	$entryCrontabString .= " ";
	
	if($numArguments == 1) {
		$entryCrontabString .= $hashDays{$options[$numArguments - 1]};
	}
	elsif($numArguments < 7) {
		for(my $index=0; $index<$numArguments - 1; $index++) {
			$entryCrontabString .= $hashDays{$options[$index]};
			$entryCrontabString .= ",";
		}
		
		$entryCrontabString .= $hashDays{$options[$numArguments - 1]};
	} elsif($numArguments == 7) {
		$entryCrontabString .= "*";
	} 
	
	$entryCrontabString .= " ";
	$entryCrontabString .= $user;
	
	$entryCrontabString .= " ";
	$entryCrontabString .= $scriptPath;
	
	$entryCrontabString .= "\n";
	return $entryCrontabString;
}

#****************************************************************************************************
# Subroutine Name         : checkEntryExistsCrontab.
# Objective               : Subroutine to check if crontab has an existing backup job corresponding to 
#							the backup script. 
# Added By                : 
#*****************************************************************************************************/
sub checkEntryExistsCrontab{
	my $readable = readFromCrontab();
	if($readable == 0){
		@linesCrontab = readCrontabAsRoot();
	}
	foreach (@linesCrontab) {
		if (/$jobRunningDir/){
			$crontabEntry = $_;
			return true;
		}
	}
	return false;
}

#****************************************************************************************************
# Subroutine Name		: removeEntryFromCrontabLines.
# Objective				: Subroutine to remove an existing backup job from crontab corresponding
#							to the backup script. 
# Modified By			: Dhritikana
# Modified By 			: Abhishek Verma - 21/6/2017 - Now variable $jobExists will contain only 'user_profile/tester_1/Backup/Scheduled' for backup job and
# 				  'user_profile/tester_1/Backup/Scheduled' for Restore job, to remove job from crontab file. 
# 				  This has been done so that jobs can be deleted irrespective of the location from where job has been scheduled by the user.
#*****************************************************************************************************/
sub removeEntryFromCrontabLines
{
	my $jobExists = qq{$checkScriptCronEntry};
	@linesCrontab = grep !/$jobExists/, @linesCrontab;
}

#****************************************************************************************************
# Subroutine Name		: readCrontabAsRoot.
# Objective				: Read entire crontab file by root user mode.
# Modified By			: Senthil Pandian
#*****************************************************************************************************/
sub readCrontabAsRoot {
	my $command = '';
	my $temp = "$jobRunningDir/operationsfile.txt";
	if(!open TEMP, ">", $temp) {
		print $tHandle "$!\n";
		print "unable $!";
		exit;
	}
	
	print TEMP "READ_CRON_ENTRIES";
	close TEMP;
	chmod $filePermission, $temp;
	my $operationsScript = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
	if($noRoot) {
		$command = "su -c \"$perlPath '$operationsScript' '$jobRunningDir' \" root";
		if (ifUbuntu()){
			$command = "sudo -p\"".Constants->CONST->{'CronQueryUbuntu'}." $user: \" ".$command;
		}else{
			print Constants->CONST->{'CronQuery'};
		}
	} else {
		$command = qq{$perlPath '$operationsScript' '$jobRunningDir'};
	}
	
	traceLog("Read cron entry command: $command", __FILE__, __LINE__);
	my @res = `$command`;
	unlink($temp);
	return @res;
}
#****************************************************************************************************
# Subroutine Name		: writeToCrontab.
# Objective				: Append an entry to crontab file.
# Modified By			: Dhritikana
#*****************************************************************************************************/
sub writeToCrontab {
	my $command = '';
	s/^\s+// for @linesCrontab;
	my $temp = "$jobRunningDir/operationsfile.txt";
	if(!open TEMP, ">", $temp) {
		print $tHandle "$!\n";
		print "unable $!";
		exit;
	}
	print TEMP "WRITE_TO_CRON\n";
	print TEMP @linesCrontab;
	close TEMP;
	chmod $filePermission, $temp;
	my $operationsScript = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
	if($noRoot) {
		$command = "su -c \"$perlPath '$operationsScript' '$jobRunningDir' \" root";
		if (ifUbuntu()){
			$command = "sudo -p\"".Constants->CONST->{'CronQueryUbuntu'}." $user: \" ".$command;
		}else{
			print Constants->CONST->{'CronQuery'};
		}	
	} else {
		$command = qq{$perlPath '$operationsScript' '$jobRunningDir'};
	}
	traceLog(" Cron entry command: $command", __FILE__, __LINE__);
	my $res = system($command);
	unlink($temp);
	if($res ne "0") {
		return 0;
	}
	return 1;
}
#****************************************************************************************************
# Subroutine Name         : checkUser.
# Objective               : This function will check user and if not root will prompt for credentials.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub checkUser {
	system("clear");
	
	my $checkUserCmd = "whoami";
	$user = `$checkUserCmd`;
	chomp($user);
	if($user ne "root") {
		$noRoot = 1;
	}
}

#****************************************************************************
# Subroutine Name         : cancelProcess
# Objective               : Cleanup if user cancel.
# Added By                : Dhritikana
#****************************************************************************/
sub cancelProcess {
	system('stty','echo');
	exit(0);
}

#****************************************************************************
# Subroutine Name         : createFileSet
# Objective               : Creating File set for Backup/Restore job.
# Added By                : Dhritikana
#****************************************************************************/
sub createFileSet {	
	if($jobType eq "Backup") {
		$currentJobFileset = $backupsetSchFilePath;
		$currentJobFilesetSoftLink = $backupsetSchFilePath;
	} elsif($jobType eq "Restore") {
		$currentJobFileset = $RestoresetSchFile;
		$currentJobFilesetSoftLink	= $RestoresetSchFile;
	}
	
	if(!-e $currentJobFileset) {
		open(SETFILE, ">", $currentJobFileset) or die " Couldn't create $currentJobFileset, Reason: $!\n";
		close(SETFILE);
		chmod $filePermission, $currentJobFileset;
#		`ln -s $currentJobFileset $currentJobFilesetSoftLink`; 
	}
	
	if(!-s $currentJobFilesetSoftLink) {
		print "\nNote: Your $jobType"."set file \"$currentJobFilesetSoftLink\" is empty. ".Constants->CONST->{pleaseUpdate}.$lineFeed;
		exit(1);
	}
}

#****************************************************************************
# Subroutine Name         : emailNotifyQueries.
# Objective               : 
# Added By                : Dhritikana
#****************************************************************************/
sub emailNotifyQueries {
	my $mailNotifyFlagFile = $jobRunningDir."/".$jobType."mailNotify.txt";
	my ($notifyFlag, $notifyEmailIds, $notifyData, $messageFlag) = ('') x 4;
	if(!-e $mailNotifyFlagFile) {
		($notifyFlag, $notifyEmailIds) = ("DISABLED", $configEmailAddress);
	} else {
		unless(open NOTIFYFILE, "<", $mailNotifyFlagFile) {
			traceLog(Constants->CONST->{FileOpenErr}." $mailNotifyFlagFile, Reason: $!".$lineFeed, __FILE__, __LINE__);
			print $lineFeed.$whiteSpace.Constants->CONST->{'failedMailNotifyGet'}.$lineFeed;
			exit(1);
		}
		@notifyData = <NOTIFYFILE>;
		chomp(@notifyData);
		$notifyFlag = $notifyData[0];
		$notifyEmailIds = $notifyData[1];
		close(NOTIFYFILE);
		
		if($notifyEmailIds eq "") {
			$notifyEmailIds = $configEmailAddress;
		}
	}
	
	unless(open ENABLEFILE, ">", $mailNotifyFlagFile) {
		traceLog(Constants->CONST->{FileOpenErr}." $mailNotifyFlagFile, Reason: $!".$lineFeed, __FILE__, __LINE__);
		print $lineFeed.$whiteSpace.Constants->CONST->{'failedMailNotifySet'}.$lineFeed;
		exit(1);
	}
	chmod $filePermission, $mailNotifyFlagFile;
	
	if(($notifyFlag eq "DISABLED" or $notifyFlag eq "")) {
		print $whiteSpace.$lineFeed.Constants->CONST->{'notificationQuery'}.$whiteSpace;
		$confirmationChoice = getConfirmationChoice();
		if($confirmationChoice eq "n" or $confirmationChoice eq "N") {
			print ENABLEFILE "DISABLED\n";
			print ENABLEFILE $notifyEmailIds."\n";
			close(ENABLEFILE);
			return 1;
		} 
		
		if($notifyEmailIds) {
			print $lineFeed.Constants->CONST->{'existingEmail'}.$notifyEmailIds.$lineFeed;
			print $lineFeed.Constants->CONST->{'editQuery'}.$whiteSpace;
			$confirmationChoice = getConfirmationChoice();
			if($confirmationChoice eq "n" or $confirmationChoice eq "N") {
				my $str = "ENABLED\n".$notifyEmailIds."\n";
				print ENABLEFILE $str;
				close(ENABLEFILE);
				return 1;
			}
		} 
	}		
	elsif($notifyFlag eq "ENABLED") {
		print $lineFeed.Constants->CONST->{'emailNotificationSetting'}.$lineFeed;
		print Constants->CONST->{'emailNotificationStatus'}." ENABLED".$lineFeed;
		print Constants->CONST->{'emailIDs'}." $notifyEmailIds".$lineFeed;
		print $lineFeed.Constants->CONST->{'emailNotificationDisable'};
		$confirmationChoice = getConfirmationChoice();
		if($confirmationChoice eq "y" or $confirmationChoice eq "Y") {
			print ENABLEFILE "DISABLED\n";
			print ENABLEFILE $notifyEmailIds.$lineFeed;
			close(ENABLEFILE);
			return 1;
		}
		elsif($confirmationChoice eq 'N' or $confirmationChoice eq 'n'){
			print $lineFeed.Constants->CONST->{'emailIDChange'};
			$confirmationChoice = getConfirmationChoice();
			if ($confirmationChoice eq "n" or $confirmationChoice eq "N"){
				 print ENABLEFILE "ENABLED".$lineFeed;
				 print ENABLEFILE $notifyEmailIds.$lineFeed;
				 close(ENABLEFILE);
				 return 1;
			}
		}
	}
	print Constants->CONST->{'emailIDRequired'};
	my @finalEmail =();
	my $mailCount = 0;	
	my $wrongEmail = undef;
	while(1) {
			if ($mailCount == 4){
				if ($notifyEmailIds ne ''){
					print Constants->CONST->{'emailChangeMax'}.qq{ "$notifyEmailIds" $lineFeed$lineFeed};
				}else{
					print Constants->CONST->{'emailUpdateMax'}.$lineFeed.$lineFeed;
				}
				last;
			}	
			my $failed = undef;
			my @email = undef;
			my $email = <>;
			chomp($email);
			Chomp(\$email);
			if($email =~ /\,|\;/) {
				@email = split(/\,|\;/, $email);
			} else {
				push(@email, $email);
			}
			@email = grep /\S/, @email;	
			$mailCount++;
			if(scalar(@email) lt 1) {
				print Constants->CONST->{'EmptyEmailId'}.$lineFeed;
				print Constants->CONST->{'emailIDRequired'} if($mailCount < 4);
				$wrongEmail = undef;
				next;
			}
			foreach my $eachId (@email) {
				my $tmp = quotemeta($eachId);
				if($emailAddr =~ /^$tmp$/) {
					next;
				}
				$eachId =~s/^[\s\t]+|[\s\t]+$//g;
				my $eVal = validEmailAddress($eachId);
				if($eVal eq 0 ) {
					$wrongEmail .=	qq($eachId, );
					$failed = 1;
				} else {
#					$emailAddr .= $eachId.",";
					push(@finalEmail,$eachId);
				}
			}

			if($failed ne 1) {
				last;
			} else {
				$wrongEmail =~ s/,\s+$//g;
				print Constants->CONST->{'InvalidEmail'}.$whiteSpace.$wrongEmail.$lineFeed;
				print Constants->CONST->{'emailIDRequired'} if ($mailCount < 4);
				$wrongEmail = undef;
			}
	}#while closed.
	$notifyEmailIds = scalar(@finalEmail) > -1 ? join(',',uniqueData(@finalEmail)) : $notifyEmailIds;
	if ($notifyEmailIds ne ''){
		print Constants->CONST->{'ConfigEmailIDMess'}.qq{$notifyEmailIds$lineFeed$lineFeed};
		print ENABLEFILE "ENABLED\n";
		print ENABLEFILE $notifyEmailIds."\n";	
	}else{
		print ENABLEFILE "DISABLED\n";
	}
	close(ENABLEFILE);
}
