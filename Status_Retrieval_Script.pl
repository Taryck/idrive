#!/usr/bin/env perl

#########################################################################
#Script Name : Status_Retrieval_Script.pl
#########################################################################

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);
# $incPos = rindex(__FILE__, '/');
# $incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
# unshift (@INC,$incLoc);

use Common;
Common::waitForUpdate();
Common::initiateMigrate();

require 'Header.pl';
use FileHandle;

use constant false => 0;
use constant true => 1;

#use Constants 'CONST';
require Constants;

#File name of file which stores backup progress information   #
my $menuChoice = undef;
#my $Pflag = undef;
my $taskType = "SCHEDULE";
my $currPidFile = '';
my $prevLine = '';

$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

loadUserData();
headerDisplay($0);
if(!($ARGV[0])) {
	if(getAccountConfStatus($confFilePath)){
		exit(0);
	} else {
		exit(0) if(getLoginStatus($pwdPath));
	}
}
holdScreen2displayMessage(3);
#my $BackupScriptCmd = "ps -elf | grep \"Backup_Script.pl Backup $userName\" | grep -v cd | grep -v grep";
#my $RestoreScriptCmd = "ps -elf | grep \"Restore_Script.pl Restore $userName\" | grep -v cd | grep -v grep";

=beg
my $BackupScriptCmd  = "ps $psOption | grep \"".Constants->FILE_NAMES->{backupScript}." SCHEDULED $userName\" | grep -v grep";
my $RestoreScriptCmd = "ps $psOption | grep \"".Constants->FILE_NAMES->{restoreScript}." SCHEDULED $userName\" | grep -v grep";
my $ExpressScriptCmd = "ps $psOption | grep \"".Constants->FILE_NAMES->{expressBackupScript}." SCHEDULED $userName\" | grep -v grep";
$BackupScriptCmd = Common::updateLocaleCmd($BackupScriptCmd);
$RestoreScriptCmd = Common::updateLocaleCmd($RestoreScriptCmd);
$ExpressScriptCmd = Common::updateLocaleCmd($ExpressScriptCmd);
$BackupScriptRunning  = `$BackupScriptCmd`;
$RestoreScriptRunning = `$RestoreScriptCmd`;
$ExpressScriptRunning = `$ExpressScriptCmd`;
=cut

my (@runningJobs,@runningJobTitle,@runningDir);
my @jobNameArr = ('backup','localbackup','restore');
my $userProfilePath = Common::getUserProfilePath();
foreach my $job (@jobNameArr) {
	my $pidFile = Common::getCatfile($userProfilePath, $AppConfig::userProfilePaths{$job}, $AppConfig::pidFile);
	if (Common::isFileLocked($pidFile)) {
		my $jobRunningDir  = Common::getJobsPath($job);
		push @runningJobTitle, $job."_job";
		push @runningDir, $jobRunningDir;
	}
}

if (scalar(@runningJobTitle) > 0) {
	Common::display('');
	Common::displayMenu('select_the_job_from_the_above_list',@runningJobTitle);
	Common::display('');
	$userSelection = Common::getUserMenuChoice(scalar(@runningJobTitle));
}
else
{
	print Constants->CONST->{'NoOpRng'}.$lineFeed;
	exit;
}
$runningJobTitle[($userSelection - 1)] =~ s/_job//g;
$jobType       = uc($runningJobTitle[($userSelection - 1)]);
$jobRunningDir = $runningDir[($userSelection - 1)];

#Subroutine that processes SIGINT and SIGTERM signal received by the script#
$SIG{INT} = \&process_term;
$SIG{TERM} = \&process_term;
$SIG{TSTP} = \&process_term;
$SIG{QUIT} = \&process_term;

# Trace Log Entry #
my $curFile = basename(__FILE__);
#traceLog("$lineFeed File: $curFile $lineFeed---------------------------------------- $lineFeed", __FILE__, __LINE__);
my $displayProgress = 1;
constructProgressDetailsFilePath();

#Commented by Senthil as per Deepak's instruction
=beg
my $info_file = $jobRunningDir."/info_file";
my $progressDetailsFilePath = $jobRunningDir.$pathSeparator."PROGRESS_DETAILS";
my $exec_cores = Common::getSystemCpuCores();
my $isProgressStarted = 0;
for(my $i=1; $i<=$exec_cores; $i++){
	if(-e $progressDetailsFilePath."_".$i and -e $info_file){
		$isProgressStarted = 1;
		last;
	}
}
if($isProgressStarted == 0){
	print Constants->CONST->{'NoOpRng'}.$lineFeed;
	exit 0;
}
=cut
#system("clear");

#Added to handle the job termination case: Senthil
unless(-e $jobRunningDir.$pathSeparator.$AppConfig::pidFile){
	print Constants->CONST->{'NoOpRng'}.$lineFeed;
	exit 0;
}
getCursorPos();
do {
	displayProgressBar($progressDetailsFilePath);
	#if( !-e $jobRunningDir.$pathSeparator.$AppConfig::pidFile){
	#Modified by Senthil
	if(!-e $jobRunningDir.$pathSeparator.$AppConfig::pidFile){
		$displayProgress = 0;
		Common::removeItems("$progressDetailsFilePath*")
	}
	#select undef, undef, undef, 0.005;
	Common::sleepForMilliSec(100); # Sleep for 100 milliseconds
}
while($displayProgress);
process_term();
#****************************************************************************************************
# Subroutine Name         : printMenu.
# Objective               : Subroutine to print options to do status Retrival.
# Modified By             : Dhritikana
#*****************************************************************************************************/
# sub printMenu {
	# system("clear");
	# print $lineFeed.Constants->CONST->{'BothRunning'}.$lineFeed;
	# print $lineFeed.Constants->CONST->{'AskStatusOp'}.$lineFeed;
  	# print $lineFeed.Constants->CONST->{'StatBackOp'}.$lineFeed;
  	# print Constants->CONST->{'StatRstOp'}.$lineFeed;
# }

#****************************************************************************************************
# Subroutine Name         : getMenu.
# Objective               : Subroutine to get option to do status Retrival
# Added By                :
#*****************************************************************************************************/
# sub getMenu {
	# print $lineFeed.Constants->CONST->{'EnterChoice'};
	# while(!defined $menuChoice) {
		# $menuChoice = <STDIN>;
		# chomp($menuChoice);
	# }
	# return $menuChoice;
# }

#****************************************************************************************************
# Subroutine Name         : constructProgressDetailsFilePath.
# Objective               : This subroutine frames the path of Progress Details file.
# Modified By             : Dhritikana
#*****************************************************************************************************/
sub constructProgressDetailsFilePath {
    my $wrokginDir = $currentDir;
    $wrokginDir =~ s/ /\ /g;
    $progressDetailsFilePath = $jobRunningDir.$pathSeparator."PROGRESS_DETAILS";
	$currPidFile = $jobRunningDir.$pathSeparator."pid.txt";
}

#****************************************************************************************************
# Subroutine Name         : readProgressDetailsFile.
# Objective               : This subroutine reads the last line of Progress Details file. It then
#							parses the line to extract the filename and the backup progress for that file.
# Modified By             : Dhritikana
#*****************************************************************************************************/
sub readProgressDetailsFile {
	open PROGRESS_DETAILS_FILE, "<", $progressDetailsFilePath or return "";

	my @lastLine = <PROGRESS_DETAILS_FILE>;
	close PROGRESS_DETAILS_FILE;
	return @lastLine;
}
#****************************************************************************************************
# Subroutine Name         : process_term.
# Objective               : In case the script execution is canceled by the user,the script should exit.
#							bar in the terminal window.
# Added By                :
#*****************************************************************************************************/
sub process_term {
	my $jobType = lc($jobType);
	if($jobType eq 'backup'){
		$jobType = 'Backup Job';
	} elsif($jobType eq 'restore'){
		$jobType = 'Restore Job';
	} else {
		$jobType = 'Express Backup Job';
	}
	displayFinalSummary($jobType,$jobRunningDir.'/'.Constants->CONST->{'fileDisplaySummary'});#This function display summary on stdout once backup job has completed
	chmod $filePermission, $jobRunningDir.'/'.Constants->CONST->{'fileDisplaySummary'};
	exit 0;
}
#***************************************************************************************
# Subroutine Name         : getMenuChoice
# Objective               : get Menu choioce to check if user wants to configure his/her
#                                                       with Default or Private Key.
# Added By                : Dhritikana
#****************************************************************************************/
# sub getMenuChoice {
    # my $count = 0;
    # while(!defined $menuChoice) {
        # if ($count < 4){
            # $count++;
            # print Constants->CONST->{'EnterChoice'};
            # $menuChoice = <STDIN>;
            # chomp $menuChoice;
            # $menuChoice =~ s/^\s+|\s+$//;
            # if($menuChoice =~ m/^\d$/) {
				# if($menuChoice < 1 || $menuChoice > 3) {
					# $menuChoice = undef;
					# print Constants->CONST->{'InvalidChoice'}.$whiteSpace if ($count < 4);
				# }
            # }else {
                    # $menuChoice = undef;
                    # print Constants->CONST->{'InvalidChoice'}.$whiteSpace if ($count < 4);
            # }
        # }else{
            # print Constants->CONST->{'maxRetry'}.$lineFeed;
            # $menuChoice='';
            # exit;
        # }
    # }
# }
