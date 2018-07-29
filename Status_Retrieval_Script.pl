#!/usr/bin/perl

#########################################################################
#Script Name : Status_Retrieval_Script.pl
#########################################################################

$incPos = rindex(__FILE__, '/');
$incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

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
my $progressDetailsFilePath = '';
my $currPidFile = '';
my $prevLine = '';

$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 

getConfigHashValue();
loadUserData();
headerDisplay($0);
if(!($ARGV[0])) {
#	my $pvtParam = "PVTKEY";
#	getParameterValue(\$pvtParam, \$hashParameters{$pvtParam});
#	my $pvtKey = $hashParameters{$pvtParam};
#	if(! -e $pwdPath or ($pvtKey ne "" and ! -e $pvtPath)){

	if(getAccountConfStatus($confFilePath)){
		exit(0);
	}
	else{
                if(getLoginStatus($pwdPath)){
                        exit(0);
                }
        }
}
holdScreen2displayMessage(3);
#my $BackupScriptCmd = "ps -elf | grep \"Backup_Script.pl Backup $userName\" | grep -v cd | grep -v grep";
#my $RestoreScriptCmd = "ps -elf | grep \"Restore_Script.pl Restore $userName\" | grep -v cd | grep -v grep";

my $BackupScriptCmd  = "ps $psOption | grep \"".Constants->FILE_NAMES->{backupScript}." SCHEDULED $userName\" | grep -v grep";
my $RestoreScriptCmd = "ps $psOption | grep \"".Constants->FILE_NAMES->{restoreScript}." SCHEDULED $userName\" | grep -v grep";

$BackupScriptRunning = `$BackupScriptCmd`;
$RestoreScriptRunning = `$RestoreScriptCmd`;

if($BackupScriptRunning ne "" && $RestoreScriptRunning ne "") {
	printMenu();	
	getMenuChoice();
	if($menuChoice eq 1) {
		$jobType = "BACKUP";
	} elsif($menuChoice eq 2) {
		$jobType = "RESTORE";
	}else{
		print Constants->CONST->{'InvalidChoice'}.' '.Constants->CONST->{'TryAgain'};
		exit;
	}
} elsif($BackupScriptRunning ne "") {
	$jobType = "BACKUP";
} elsif($RestoreScriptRunning ne "") {
	$jobType = "RESTORE";
} else {
	print Constants->CONST->{'NoOpRng'}.$lineFeed;
	exit;
}

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
unless(-e $progressDetailsFilePath){
	print Constants->CONST->{'NoOpRng'}.$lineFeed;
	exit 0;
}
#system("clear");
getCursorPos();
do {
	my @lastLine = readProgressDetailsFile();
	chomp(@lastLine);
	@lastLine = grep {/\S/}@lastLine;
	my $lastLine = join "\n", @lastLine;
	
	if($lastLine ne "" and $lastLine ne $prevLine and scalar(@lastLine)>1) {
		if ($lastLine =~ /PROGRESS END/){
			$lastLine =~s/PROGRESS END//;
			if ($lastLine eq $prevLine){
				$displayProgress = 0;
			}
		}
		my @params = split( /\n/, $lastLine);
		displayProgressBar($params[0], $params[1], $params[2], $params[3], $params[4], $params[5], $params[6], $params[7]);
		$prevLine = $lastLine;
	} elsif($lastLine eq "" and !-e $progressDetailsFilePath and !-e $currPidFile){
		$displayProgress = 0;
	}
	select undef, undef, undef, 0.005;
}
while($displayProgress);
process_term();
#****************************************************************************************************
# Subroutine Name         : printMenu.
# Objective               : Subroutine to print options to do status Retrival.
# Modified By             : Dhritikana
#*****************************************************************************************************/
sub printMenu {
	system("clear");
	print $lineFeed.Constants->CONST->{'BothRunning'}.$lineFeed;
	print $lineFeed.Constants->CONST->{'AskStatusOp'}.$lineFeed;
  	print $lineFeed.Constants->CONST->{'StatBackOp'}.$lineFeed;
  	print Constants->CONST->{'StatRstOp'}.$lineFeed;
}

#****************************************************************************************************
# Subroutine Name         : getMenu.
# Objective               : Subroutine to get option to do status Retrival
# Added By                : 
#*****************************************************************************************************/
sub getMenu {
	print $lineFeed.Constants->CONST->{'EnterChoice'}; 
	while(!defined $menuChoice) {
		$menuChoice = <STDIN>;
		chomp($menuChoice);
	}
	return $menuChoice;
}
 
#****************************************************************************************************
# Subroutine Name         : constructProgressDetailsFilePath.
# Objective               : This subroutine frames the path of Progress Details file.
# Modified By             : Dhritikana
#*****************************************************************************************************/
sub constructProgressDetailsFilePath {
    my $wrokginDir = $currentDir;
    $wrokginDir =~ s/ /\ /g;
    
    $jobRunningDir = $usrProfileDir.$pathSeparator.ucfirst(lc($jobType)).$pathSeparator."Scheduled";
    $progressDetailsFilePath = $jobRunningDir.$pathSeparator."PROGRESS_DETAILS_".$jobType;
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
	my $jobType = lc($jobType) eq 'backup' ? 'Scheduled Backup Job':'Scheduled Restore Job';
	displayFinalSummary($jobType,$jobRunningDir.'/'.Constants->CONST->{'fileDisplaySummary'});#This function display summary on stdout once backup job has completed	
	exit 0;
}
#***************************************************************************************
# Subroutine Name         : getMenuChoice
# Objective               : get Menu choioce to check if user wants to configure his/her
#                                                       with Default or Private Key.
# Added By                : Dhritikana
#****************************************************************************************/
sub getMenuChoice {
    my $count = 0;
    while(!defined $menuChoice) {
        if ($count < 4){
            $count++;
            print Constants->CONST->{'EnterChoice'};
            $menuChoice = <STDIN>;
            chomp $menuChoice;
            $menuChoice =~ s/^\s+|\s+$//;
            if($menuChoice =~ m/^\d$/) {
                    if($menuChoice < 1 || $menuChoice > 2) {
                    $menuChoice = undef;
                    print Constants->CONST->{'InvalidChoice'}.$whiteSpace if ($count < 4);
            }
            }else {
                    $menuChoice = undef;
                    print Constants->CONST->{'InvalidChoice'}.$whiteSpace if ($count < 4);
            }
        }else{
            print Constants->CONST->{'maxRetry'}.$lineFeed;
            $menuChoice='';
            exit;
        }
    }
}
