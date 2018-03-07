#!/usr/bin/perl
##################################################
#Edit_Supported_Files.pl
##################################################
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
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
$menu	=	{'1.Backup'  => {1 => ["Edit your Manual Backupset File","$backupsetFilePath"], 2 => ["Edit your Scheduled Backupset File","$backupsetSchFilePath"]},
				'2.Express Backup' => {3 => ["Edit your Express Backupset File","$localBackupsetFilePath"]},
				'3.Exclude' => {4 => ["Edit your FullExcludeList File","$excludeFullPath"], 5 => ["Edit your PartialExcludeList File","$excludePartialPath"], 6 => ["Edit your RegexExcludeList File","$regexExcludePath"]},
				'4.Restore' => {7 => ["Edit your Manual Restoreset File","$RestoresetFile"], 8 => ["Edit your Scheduled Restoreset File","$RestoresetSchFile"]}			 
				
			};
@menuArray = ['1.Backup','2.Express Backup','3.Exclude','4.Restore'];
		
my $filePermission = 0777;
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Operations Start ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
START:
print Constants->CONST->{'AskOption'}.qq($lineFeed$lineFeed);
displayMenu($menu);
print $lineFeed.Constants->CONST->{'ctrlc2Exit'}.$lineFeed;
print $lineFeed.Constants->CONST->{'EnterChoice'};
my $userChoice = <STDIN>;
Chomp(\$userChoice);
$userChoice =~ s/^0+(\d+)/$1/g;#removing initial zero from the user input for given choice.
my $keyName = returnKeyName($userChoice,@menuArray);#userChoice and array of keyname to be returned
unless ($keyName){
	print $lineFeed.Constants->CONST->{'InvalidChoice'}.Constants->CONST->{'TryAgain'}.$lineFeed;
	exit(0);
}
if (openViEditor($menu,$keyName,$userChoice)){
	print $lineFeed;
	goto START;
}
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Operations End ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Defining utility functions ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#****************************************************************************
#Subroutine Name         : openViEditor
#Objective               : To open vi editor for given file.
#Usgae                   : openViEditor($menu,$keyName,$userChoice)
#                        : $menu	: Contains data related to menu operation.
#                        : $keyName	: name of the key correcponding to user's choice from $menu.
#                        : $userChoice	: user's choice from $menu.
#Added By                : Abhishek Verma.
#****************************************************************************/
sub openViEditor {
	my $fileLocation = $_[0]->{$_[1]}->{$_[2]}->[1];
	if ($_[2] =~ /^[1267]$/){ # Handle case when schedulebackup / restore set file is not created.
		if (!-e $fileLocation){
			$fileLocation =~ /(.*\/)[a-zA-Z0-9.]/;
			my $scheduleDirLoc = $1;
			my $mkRes = `mkdir -p '$scheduleDirLoc' $errorRedirection`;
			open(SETFILE, ">", $fileLocation) or die "Couldn't create $fileLocation, Reason: $!\n";
	                close(SETFILE);
        	        chmod $filePermission, $fileLocation;
		}
	}
	print $lineFeed.Constants->CONST->{'viEditClosureMessage'}.$lineFeed;
	print $lineFeed.Constants->CONST->{'FileopeningMess'}.$lineFeed;
	holdScreen2displayMessage(4);
	#print $lineFeed.Constants->CONST->{'fileEditSuccessfully'}.$lineFeed;
	my $operationStatus = system "vi '$fileLocation'";
	if ($operationStatus == 0){
		print $lineFeed.qq(File "$fileLocation" ).Constants->CONST->{'fileEditSuccessfully'}.$lineFeed;
		print $lineFeed.Constants->CONST->{'editOtherSupportedFiles'};
		my $choice = getConfirmationChoice();
		Chomp($choice);
		return 1 if ($choice =~/^y$/i);
	}else{
		print $lineFeed.Constants->CONST->{'operationNotCompleted'}.qq(Reason : $!\n);
	}
}
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Functions defination End ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
