#!/usr/bin/perl

###############################################################################
#Script Name : Restore_Version.pl
###############################################################################

unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require 'Header.pl';

use File::Path;
require Constants;

$SIG{INT} = \&cancelProcess;
$SIG{TERM} = \&cancelProcess;
$SIG{TSTP} = \&cancelProcess;
$SIG{QUIT} = \&cancelProcess;

#$userName = getCurrentUser(); 
#Check if EVS Binary exists.
headerDisplay($0);
my $err_string = checkBinaryExists();
if($err_string ne "") {
        print qq($err_string);
        exit 1;
}

$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 

getConfigHashValue();
loadUserData();

#getParameterValue(\"PVTKEY", \$hashParameters{PVTKEY});
my $logoutFlag = 0;
#my $pvtKey = $hashParameters{$pvtParam};

if(getAccountConfStatus($confFilePath)){
	exit(0);
}
else{
	if(getLoginStatus($pwdPath)){
		$logoutFlag = 1;
		exit(0);
	}
}

my $lastVersion = undef;
my @versionsArr = ();
my $fileVersionSize = '';

# Trace Log Entry #
my $curFile = basename(__FILE__);
traceLog("$lineFeed File: $curFile $lineFeed---------------------------------------$lineFeed", __FILE__, __LINE__);

displayMainMenu();
getMainMenuChoice();
$jobType = "Restore";
my $maximumRetryMessage = '';
emptyLocationsQueries(\$maximumRetryMessage,1);
getFilePath($maximumRetryMessage);
doMainOperation();

#**********************************************************************************
# Subroutine Name         : displayMainMenu.
# Objective               : Subroutine to display Main Menu.
# Added By                : Dhritikana Kalita.
#**********************************************************************************
sub displayMainMenu {
	system("clear");
	headerDisplay($0) if (!$logoutFlag);
	print Constants->CONST->{'AskOption'}."\n\n";
	print Constants->CONST->{'DisplayVer'}.$lineFeed;
	print Constants->CONST->{'RestoreVer'}.$lineFeed;
}

#**********************************************************************************
# Subroutine Name         : getMainMenuChoice.
# Objective               : Subroutine to get Main Menu choice from user.
# Added By                : Dhritikana Kalita.
#**********************************************************************************
sub getMainMenuChoice {

	my $count = 0;
	while(!defined $mainMenuChoice) {
		if($count == 4){
			print $lineFeed.Constants->CONST->{'maxRetryattempt'}.$lineFeed;
			exit 1;
		}
		
		print $lineFeed.Constants->CONST->{'EnterChoice'};
		$mainMenuChoice = <>;
		chomp($mainMenuChoice);
		
		if($mainMenuChoice =~ m/^\d$/) {
			if($mainMenuChoice < 1 || $mainMenuChoice > 2) {
				$count++;
				$mainMenuChoice = undef;
				
				print $lineFeed.Constants->CONST->{'InvalidChoice'}.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed if($count <= 3);
			} 
		}
		else {
			print $lineFeed.Constants->CONST->{'InvalidChoice'}.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed if($count <= 3);
			$count++;
			$mainMenuChoice = undef;
		}
	}
}

#***********************************************************************************************************
# Subroutine Name         : getFilePath.
# Objective               : Ask user for the file path for which he/she wants to do dispay/restore file version.
# Added By                : Dhritikana Kalita.
#**********************************************************************************************************
sub getFilePath {
	system("clear");
	print "\n$_[0]\n" if ($_[0] ne "");
	print Constants->CONST->{'AskFilePath'}.$lineFeed;
	$filePath = <STDIN>;
	Chomp(\$filePath);
	if(substr($filePath, 0, 1) ne "/") {
		$fullFilePath = $restoreHost."/".$filePath;
	} else {
		$fullFilePath = $restoreHost.$filePath;
	}
}

#*************************************************************************************************
# Subroutine Name         : doMainOperation.
# Objective               : Based on user's request, call restore function to perform restore job
# Added By                : Dhritikana Kalita.
#*************************************************************************************************
sub doMainOperation {
	getVerions();
	if($mainMenuChoice eq 1) {
		for (@versionsArr[1 .. $#versionsArr]) {
			print $_."\n";
		}
		print $lineFeed.Constants->CONST->{'AskRestoreVer'}.$whiteSpace;

		$confirmationChoice = getConfirmationChoice();
		if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
			print Constants->CONST->{'Exit'}.$lineFeed;
			unlink($idevsErrorFile);
			exit 0;
		} 
	}
	askRestoreLocation(\$maximumRetryMessage);
	print "$maximumRetryMessage" if ($maximumRetryMessage ne '');	
	createRestoresetFile();
	restoreVersion();
	unlink($idevsErrorFile);
}

#********************************************************************************
# Subroutine Name         : getVerions.
# Objective               : Gets versions of user's requested file
# Added By                : Dhritikana Kalita.
#********************************************************************************
sub getVerions {
	my $versionUtfFile = getOperationFile($versionOp, $fullFilePath);
	my $errorMessageHandler = {'No version found'=>qq(No version found for given file. ),'path not found'=>qq(Could not find given file.),'cleanupOperation'=> sub {unlink($idevsErrorFile);print Constants->CONST->{'Exit'}.$lineFeed;exit;}};
	chomp($versionUtfFile);
	$versionUtfFile =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$versionUtfFile."'".$whiteSpace.$errorRedirection;;
	my $commandOutput = `$idevsutilCommandLine`;
	unlink $versionUtfFile;
	system("clear");
	if ($commandOutput =~/No version found/){
		print $errorMessageHandler->{"$&"}.$lineFeed;
		$errorMessageHandler->{'cleanupOperation'}->();
	}	
	if($commandOutput =~ /path not found/) {
		print $errorMessageHandler->{"$&"}.$lineFeed;
                $errorMessageHandler->{'cleanupOperation'}->();

	}
	
	@versionsArr = split("\n", $commandOutput);
	$lastVersion = substr($versionsArr[-1], -4, -1);
}

#********************************************************************************
# Subroutine Name         : itemStat.
# Objective               : Check if file exits
# Added By                : Dhritikana Kalita.
#********************************************************************************
sub itemStat {
	
	open TEMP, ">stat.txt" or traceLog(Constants->CONST->{'FileOpnErr'}.", Resaon: $!".$lineFeed, __FILE__, __LINE__);
	print TEMP $fullFilePath;
	close TEMP;
	chmod $filePermission, "stat.txt";
	
	my $itemStatUtfFile = getOperationFile($itemStatOp, "stat.txt");
	chomp($itemStatUtfFile);
	$itemStatUtfFile =~ s/\'/\'\\''/g;
	
	
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$itemStatUtfFile."'".$whiteSpace.$errorRedirection;
	my $commandOutput = `$idevsutilCommandLine`;
	unlink $itemStatUtfFile;
	unlink("stat.txt");
	system("clear");
	
	if($commandOutput =~ /No such file or directory|directory exists/) {
		print $lineFeed.$whiteSpace.Constants->CONST->{'NonExist'};
		print $lineFeed.$whiteSpace.Constants->CONST->{'Exit'}.$lineFeed;
		traceLog($lineFeed."Restore Version: item stat: $commandOutput".$lineFeed, __FILE__, __LINE__);
		exit;
	}
}


#*************************************************************************************************
# Subroutine Name         : createRestoresetFile.
# Objective               : create RestoresetFile based on user's given version number.
# Added By                : Dhritikana Kalita.
#*************************************************************************************************
sub createRestoresetFile {
	print $lineFeed.Constants->CONST->{'AskVersion'}.$lineFeed;
	$versionNo = <STDIN>;
 	my $count = 0;	
	while($mainMenuChoice == 1 && $versionNo > $lastVersion or $versionNo < 1 or !getSize()) {
		if ($count < 3){
			$count++;
			print Constants->CONST->{'InvalidVersion'}.$lineFeed;
			print Constants->CONST->{'AskVersion'}.$lineFeed;
			$versionNo = <STDIN>;
		}
		else{
			print Constants->CONST->{'InvalidVersion'}.qq(\nYour maximum attempt reached. Please try again..\n);
			$count = 0;
			exit;
		}
	}
	while($mainMenuChoice == 2 && $versionNo > 30 or $versionNo < 1 or !getSize()) {
		if ($count < 3){
			print Constants->CONST->{'InvalidVersion'}.$lineFeed;
			print Constants->CONST->{'AskVersion'}.$lineFeed;
			$versionNo = <STDIN>;
		}
		else{
			print Constants->CONST->{'InvalidVersion'}.qq(\nYour maximum attempt reached. Please try again..\n);
                        $count = 0;
                        exit;
		}
	}
	
	Chomp(\$versionNo);
	$jobRunningDir = "$usrProfilePath/$userName/Restore/Manual"; 
	my $restoresetFile = $jobRunningDir."/versionRestoresetFile.txt";
	
	open(FILE, ">", $restoresetFile) or traceLog("Couldn't open $restoresetFile for restoreVersion option. Reason: $!\n", __FILE__, __LINE__);
	chmod $filePermission, $restoresetFile;
	print FILE $fullFilePath."_IBVER".$versionNo."\n".$fileVersionSize.$lineFeed;
	close(FILE);
}

#********************************************************************************
# Subroutine Name         : restoreVersion.
# Objective               : Restore user's requested version of a file
# Added By                : Dhritikana Kalita.
#********************************************************************************
sub restoreVersion {
	my $restoreRunCommand = "perl $userScriptLocation/".Constants->FILE_NAMES->{restoreScript}.' '.Constants->CONST->{'versionRestore'};
	system($restoreRunCommand);
	unlink("$jobRunningDir/versionRestoresetFile.txt");
}

#****************************************************************************************************
# Subroutine Name         : getSize.
# Objective               : This subroutine gets the size of the versioned file.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub getSize {
	Chomp(\$versionNo);
	for (@versionsArr[2 .. $#versionsArr]) {
		my $tmpLine = $_;
		my @tmpLineArr =  split("\\] \\[",$tmpLine, 3);
		$tmpLineArr[1] =~ s/\D+//g;
		$tmpLineArr[2] =~ s/\D+//g;
	
		if($versionNo eq $tmpLineArr[2]) {
			$fileVersionSize = $tmpLineArr[1];
			return 1;
		}
	}
	return 0;
}

#****************************************************************************
# Subroutine Name         : cancelProcess
# Objective               : Exit the process.
# Added By                : Dhritikana
#****************************************************************************/
sub cancelProcess {
	exit(1);
}
