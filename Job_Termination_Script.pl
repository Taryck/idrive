#!/usr/bin/perl

##################################################################################
#Script Name: Job_Termination_Script.pl
#################################################################################

#my $userScriptLocation  = findUserLocation();
#unshift (@INC,$userScriptLocation);
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require 'Header.pl';
#use Constants 'CONST';
require Constants;
my $mainMenuChoice = undef;
my $scriptName = ""; #script name
my $statusScriptName = Constants->FILE_NAMES->{statusRetrivalScript}; #Status Retrieval script name#
my $statusScriptRunning = ""; #If status retrieval script is executing#
my $scriptCmd = undef;
my $user = '';
my $rootPassword = '';
$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 

getConfigHashValue();
loadUserData();

if(!($ARGV[0])) {
#	my $pvtParam = "PVTKEY";
#	getParameterValue(\$pvtParam, \$hashParameters{$pvtParam});
#	my $pvtKey = $hashParameters{$pvtParam};
#	if(! -e $pwdPath or ($pvtKey ne "" and ! -e $pvtPath)) {
	if(getAccountConfStatus($confFilePath,\&headerDisplay)){
        	exit(0);
	}
	else{
        	if(getLoginStatus($pwdPath,\&headerDisplay)){
                	exit(0);
        	}
	}
}

# Trace Log Entry #
my $curFile = basename(__FILE__);
traceLog("$lineFeed File: $curFile $lineFeed----------------------------------------$lineFeed", __FILE__, __LINE__);
my $jobRunningMode = 'Manual';
my $callingScript = '';  
checkUser(); 
my $createPasswordFlag = 0;
if($ARGV[0]) {
	chomp($ARGV[0]);
	if($ARGV[0] eq "Backup") {
		$mainMenuChoice = 1;
		$userName = $ARGV[1];
		$jobRunningMode = $ARGV[2];
	} elsif ($ARGV[0] eq "Restore") {
		$mainMenuChoice = 2;
		$userName = $ARGV[1];
		$jobRunningMode = $ARGV[2];
	} elsif($ARGV[0] eq "ManualBackup") {
		$createPasswordFlag = 1;
		$mainMenuChoice = 3;
		$callingScript = $ARGV[1];
	} elsif ($ARGV[0] eq "ManualRestore") {
		$createPasswordFlag = 1;
		$mainMenuChoice = 4;
		$callingScript = $ARGV[1];
	} elsif($ARGV[0] eq "retryExit") {
		$mainMenuChoice = "retryExit";
	}
	setUserProfileScriptName();		
	if(!$userName) {
		traceLog(Constants->CONST->{'userNameMissing'}.$lineFeed, __FILE__, __LINE__);
		print Constants->CONST->{'userNameMissing'}.$lineFeed;
		exit(1);
	}
} else {
	printMenu();
	getMenuChoice();
}
my $pidPath = $jobRunningDir."pid.txt";
my $utfFile = $jobRunningDir."utf8.txt";
my $errorKillingJob = $jobRunningDir."errorKillingJob";
my $searchUtfFile = undef;
if($scriptName =~ /Restore/) {
	$searchUtfFile = $jobRunningDir."searchUtf8.txt";
}

killRunningScript();
#killStatusScript();

#****************************************************************************************************
# Subroutine Name         : printMenu.
# Objective               : Subroutine to print Main Menu choice. 
# Added By                : 
#*****************************************************************************************************/
sub printMenu()
{
	system("clear");
	headerDisplay($0);
	print Constants->CONST->{'AskOption'}.$lineFeed.$lineFeed;
	print $whiteSapce."1) Kill Manual Backup Job$lineFeed";
	print $whiteSapce."2) Kill Scheduled Backup Job$lineFeed";
	print $whiteSapce."3) Kill Manual Restore Job$lineFeed";
	print $whiteSapce."4) Kill Scheduled Restore Job$lineFeed";
}

#****************************************************************************************************
# Subroutine Name         : getMenuChoice.
# Objective               : Subroutine to get Main Menu choice from user. 
# Added By                : 
#*****************************************************************************************************/
sub getMenuChoice()
{
	my $count = 0;
  	while(!defined $mainMenuChoice)
  	{
		if ($count < 4){
			print $lineFeed.Constants->CONST->{'EnterChoice'};
			$mainMenuChoice = <STDIN>;
			chomp($mainMenuChoice);
			if($mainMenuChoice eq 2) {
	        		$scriptName = "Scheduled Backup job";
			       	$jobRunningDir = "$usrProfilePath/$userName/Backup/Scheduled/";
			}elsif($mainMenuChoice eq 4) {
			        $scriptName = "Scheduled Restore job";
        			$jobRunningDir = "$usrProfilePath/$userName/Restore/Scheduled/";
			}elsif($mainMenuChoice eq 1) {
			        $scriptName = "Manual Backup job";
			        $jobRunningDir = "$usrProfilePath/$userName/Backup/Manual/";
			}elsif($mainMenuChoice eq 3) {
			        $scriptName = "Manual Restore job";
			        $jobRunningDir = "$usrProfilePath/$userName/Restore/Manual/";
			}elsif($mainMenuChoice eq "retryExit") {
		        	$scriptName = "$jobType job";
			        $jobRunningDir = $ARGV[2]."/";
			} else {
			        print Constants->CONST->{'InvalidChoice'}." ";
		        	$mainMenuChoice=undef;
			}
		}else{
			print Constants->CONST->{'maxRetryattempt'}.' '.Constants->CONST->{'pleaseTryAgain'}.$lineFeed;
			exit 0;
		}
		$count++;
	}
}

#****************************************************************************************************
# Subroutine Name         : killRunningScript.
# Objective               : Command to check if scripts are executing. 
# Added By                : 
#*****************************************************************************************************/
sub killRunningScript 
{
	my $evsCmd = "ps -elf | grep \"$idevsutilBinaryName\" | grep \'$utfFile\' | grep -v \'grep\'";
	$evsRunning = `$evsCmd`;
	if($scriptName =~ /Restore/) {
		$evsCmd = "ps -elf | grep \"$idevsutilBinaryName\" | grep \'$searchUtfFile\' | grep -v \'grep\'";
		$evsRunning .= `$evsCmd`;
	}
	my @evsRunningResult = split(/\s+/,$evsRunning);
	my $evsRunningUserName = '';
	my $scriptCommand = "ps -elf | grep \"".Constants->FILE_NAMES->{jobTerminationScript}."\" | grep -v grep";
	my $scriptRunning = '';
	if ($#evsRunningResult == -1){
		$scriptRunning = `$scriptCommand`;
		$evsRunningUserName = (split(/\s+/,$scriptRunning))[2];
	}else{
		chomp($evsRunningUserName = $evsRunningResult[2]);
	}
	my ($noRoot,$ifubuntu) = (0) x 2;
	if(($user ne "root") and ($user ne $evsRunningUserName)){
		$noRoot = 1;
=comment       
	         askRootPassword($user,$evsRunningUserName,\$rootPassword);
		Chomp(\$rootPassword);
		if ($rootPassword eq ''){
			 print "\nIncorrect password attempt. ".Constants->CONST->{'KilFail'}.$scriptName.'. '.Constants->CONST->{'TryAgain'}.$lineFeed;
        	        traceLog("\nIncorrect password attempt. ".Constants->CONST->{'KilFail'}.$scriptName.$lineFeed, __FILE__, __LINE__);
			if ($createPasswordFlag){
	                	open(IP,'>',Constants->CONST->{'incorrectPwd'});
		                close (IP);
			}
			exit;
        	}
=cut        
	}
	@evsRunningArr = split("\n", $evsRunning);
	my $jobCount = 0;
	my @pids;
	traceLog("\nEvs running result.:: $evsRunning".$scriptName.$lineFeed, __FILE__, __LINE__);	
	foreach(@evsRunningArr) {
		if($_ =~ /$evsCmd/) {
			next;
		}
		my @lines = split(/[\s\t]+/, $_);
		my $pid = $lines[3];
		push(@pids, $pid);
	}	
	chomp(@pids);
	s/^\s+$// for (@pids);
	$jobCount = @pids;
	if($jobCount eq 0) {
		if(-e $pidPath){
			if ($noRoot){
		      		my $rootCommand = "su -c \"unlink $pidPath\" ";
				if (ifUbuntu()){
					$ifubuntu = 1;
					$rootCommand = "sudo -Sk ".$rootCommand;
				}
				$scriptTermCmd = $rootCommand;	
			}else{
				$scriptTermCmd = "unlink $pidPath";
			}
			print qq(\nEnter root ) if (!$ifubuntu and $noRoot eq 1);
			$scriptTerm = system("$scriptTermCmd");
			displayKillMessage($scriptTerm);
		}
		else{
			print $scriptName.$whiteSpace.Constants->CONST->{'NotRng'}.$lineFeed; 	
		}
		exit 0;
	}else{# if backup/restore job is running, else part will be executed and cancel.txt file will be created.
		if (($jobRunningMode eq 'Manual') and ($mainMenuChoice eq 4 or $mainMenuChoice eq 2)){
 			my $dummyFile = $jobRunningDir.'cancel.txt';
			open (FH, ">$dummyFile") or die qq(\n Unalbe to open file. Reason : $! \n);
			print FH "Operation could not be completed, Reason: Operation Cancelled by user.";
		        close FH;
			chmod $filePermission,$dummyFile;
		}
	}
	my $pidString = join(" ", @pids);
	my $scriptTermCmd = '';
	if($noRoot) {
		my $rootCommand = "su -c \"kill -9 $pidString\" ";
		if (ifUbuntu()){
			$ifubuntu = 1;
			$rootCommand = "sudo -Sk ".$rootCommand;
 		}
		$scriptTermCmd = $rootCommand;
	} else {
		$scriptTermCmd = "kill -9 $pidString";
	}
	print qq(\nEnter root ) if (!$ifubuntu and $noRoot eq 1);
	$scriptTerm = system("$scriptTermCmd");
	displayKillMessage($scriptTerm);
}
#****************************************************************************************************
# Subroutine Name         : displayKillMessage.
# Objective               : Depending upon the result of kill / unlink command this method will display the message.
# Added By                : Abhishek Verma.
#*****************************************************************************************************/
sub displayKillMessage{
	my $scriptTerm = shift;
	if($scriptTerm) {
                print "\n".Constants->CONST->{'KilFail'}.$scriptName.'. '.Constants->CONST->{'TryAgain'}.$lineFeed;
                traceLog("\nIncorrect password attempt. ".Constants->CONST->{'KilFail'}.$scriptName.$lineFeed, __FILE__, __LINE__);
		if ($createPasswordFlag){
			open(IP,'>',Constants->CONST->{'incorrectPwd'});
			close (IP);
		}
		exit;
        }
        else {
                print "\n".Constants->CONST->{'KilSuccess'}.$scriptName.$lineFeed;
                unlink($pidPath);
        }
}

=comment
#****************************************************************************************************
# Subroutine Name         : killStatusScript.
# Objective               : If status retrieval script is running, then terminate status retrieval script. 
# Added By                : 
#*****************************************************************************************************/
sub killStatusScript 
{
	#Command to check if status retrieval script is executing #
	my $statusScriptCmd = "ps -elf | grep $statusScriptName | grep -v grep";
	$statusScriptRunning = `$statusScriptCmd`;
	
	if($statusScriptRunning ne "") {
		my @processValues = split /[\s\t]+/, $statusScriptRunning;
		my $pid = $processValues[3];  
		my $statusScriptTermCmd = "kill -s SIGTERM $pid";
		my $statusScriptTerm = system($statusScriptTermCmd);
		
		if($statusScriptTerm != 0) {
			traceLog(Constants->CONST->{'KilFail'}.$statusScriptName."$statusScriptTerm ".$lineFeed, __FILE__, __LINE__);
		}
	}
}
=cut
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
}
#*********************************************************************************************
#Subroutine Name       : setUserProfileScriptName
#Objective             : set user profile path and script name whenever this script is run from some other script as a different process.
#Added By              : Abhishek Verma
#*********************************************************************************************/
sub setUserProfileScriptName{
	 if($mainMenuChoice eq 1) {
	         $scriptName = "Scheduled Backup job";
        	 $jobRunningDir = "$usrProfilePath/$userName/Backup/Scheduled/";
	 }elsif($mainMenuChoice eq 2) {
        	 $scriptName = "Scheduled Restore job";
	         $jobRunningDir = "$usrProfilePath/$userName/Restore/Scheduled/";
	 }elsif($mainMenuChoice eq 3) {
        	 $scriptName = "Manual Backup job";
	         $jobRunningDir = "$usrProfilePath/$userName/Backup/Manual/";
	 }elsif($mainMenuChoice eq 4) {
        	 $scriptName = "Manual Restore job";
	         $jobRunningDir = "$usrProfilePath/$userName/Restore/Manual/";
	 }elsif($mainMenuChoice eq "retryExit") {
        	 $scriptName = "$jobType job";
	         $jobRunningDir = $ARGV[2]."/";
	}
}
