#!/usr/bin/perl
#########################################################################################
#Script Name : Logout.pl
#########################################################################################
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require 'Header.pl';
require Constants;

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++Variable Handlings+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
my ($pwdPath,$pvtPath,$confFilePath,$ManualBackupPidpath,$ManualRestorePidpath) = ('') x 5;
my $CurrentUser = getCurrentUser();
my $usrProfileDir = "$usrProfilePath/$CurrentUser";
#if the current user dir doesn't exists
if($CurrentUser ne "" && -d $usrProfileDir) {
	$pwdPath = "$usrProfileDir/.userInfo/".Constants->CONST->{'IDPWD'};
	$pvtPath = "$usrProfileDir/.userInfo/.IDPVT";
	$confFilePath = "$usrProfileDir/".Constants->CONST->{'configurationFile'};
	$ManualBackupPidpath = $usrProfileDir."/Backup/Manual/pid.txt";
	$ManualRestorePidpath = $usrProfileDir."/Restore/Manual/pid.txt";
}else{
	print Constants->CONST->{'LogoutInfo'}.$lineFeed;
	exit(0);
}
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++Variable Handlings End++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Operation Start +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ 
killOrContinueJob();
finalLogout();
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Operations End +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#****************************************************************************
# Subroutine Name         : killOrContinueJob() 
# Objective               : To kill or continue with the running Job based on user Input.
# Usgae                   : killOrContinueJob()
# Added By                : Abhishek Verma.
#****************************************************************************/

sub killOrContinueJob{
	if ((-e $ManualBackupPidpath) and (-e $ManualRestorePidpath)){
		killJob(Constants->CONST->{'logoutBackupRestoreJob'},'ManualBackup');
		killJob('','ManualRestore');
	}else{
		if(-e $ManualBackupPidpath){
			killJob(Constants->CONST->{'logoutBackupJob'},'ManualBackup');
		}
		if(-e $ManualRestorePidpath){
			killJob(Constants->CONST->{'logoutRestoreJob'},'ManualRestore');
		}
	}
}

#****************************************************************************
#Subroutine Name         : killJob
#Objective               : To kill the running Job based on user Input.
#Usgae                   : killJob()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub killJob{
	my $userMessage = shift;
	my $jobToTerminate = shift;
	my  $confirmationChoice;
	my $jobTerminationScript = qq($userScriptLocation/).Constants->FILE_NAMES->{jobTerminationScript};
	if ($userMessage ne ''){
		print $lineFeed.$userMessage;
		$confirmationChoice = getConfirmationChoice();
	}else{
		$confirmationChoice = 'Y';
	}
	if ($confirmationChoice eq 'y' or $confirmationChoice eq 'Y'){
		$JobTermCmd = "perl $jobTerminationScript $jobToTerminate";
		system($JobTermCmd);
		if(-e Constants->CONST->{'incorrectPwd'}){
        		print Constants->CONST->{'noLogOut'}.$lineFeed;
	                traceLog("Error while logging out from the Account.", __FILE__, __LINE__);
        	        unlink (Constants->CONST->{'incorrectPwd'});
                	exit 0;
         	}
	}else{
        	#print $lineFeed.Constants->CONST->{'noLogOut'}.$lineFeed;
	        exit 0;
	}
}
#****************************************************************************
#Subroutine Name         : finalLogout 
#Objective               : To remove the password file, user.txt file, pvt key file. Inorder to logout finally.
#Usgae                   : finalLogout()
#Added By                : Abhishek Verma.
#****************************************************************************/
sub finalLogout {
	if(unlink($pwdPath)) {
        	unlink ($userTxt);
	        unlink ($pvtPath);
        	if(${ARGV[0]} ne 1) {#This scape is kept to avoid the message display when logout script is called from Account settings script.
                	print $lineFeed.Constants->CONST->{'displayUserMessage'}->("\"$CurrentUser\"",Constants->CONST->{'LogoutSuccess'}).$lineFeed;#Logout Success message.
        	}
	}else{
	        if(${ARGV[0]} ne 1){
        	        if($! =~ /No such file or directory/) {
                	        print Constants->CONST->{'LogoutInfo'}.$lineFeed;
	                } else {
        	                print $lineFeed.Constants->CONST->{'LogoutErr'}."$!".$lineFeed;
                	}
        	}else{
	                unlink($pvtPath);
        	}
	}
}
