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

$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 

getConfigHashValue();
loadUserData();
if(getAccountConfStatus($confFilePath)){
	exit(0);
}
else{
	exit(0) if(getLoginStatus($pwdPath));
}
if (! checkIfEvsWorking($dedup)){
        print Constants->CONST->{'EvsProblem'}.$lineFeed;
        exit 0;
}
$jobRunningDir = "$usrProfilePath/$userName/Restore/Manual";
$idevsErrorFile = "$jobRunningDir/error.txt";
my $lastVersion = undef;
my @versionsArr = ();
#my @versionDetails =();
my $fileVersionSize = '';

my @columnNames = (['S.No.','Version','Modified Date','Size'],[8,9,25,17]);#Contains two annonymous array one contais table header conter and other spaces related to that.

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
	headerDisplay($0);
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
		
		if($mainMenuChoice !~ m/^\d+$/) {
			print $lineFeed.Constants->CONST->{'InvalidChoice'}.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed if($count <= 3);
			$count++;
			$mainMenuChoice = undef;
		}
		elsif($mainMenuChoice < 1 || $mainMenuChoice > 2) {
			$count++;
			$mainMenuChoice = undef;
			print $lineFeed.Constants->CONST->{'InvalidChoice'}.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed if($count <= 3);
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
	$restoreHost = "" if ($dedup eq 'on'); #Senthil Added. Needs to be removed later
	if(substr($filePath, 0, 1) ne "/") {
		$fullFilePath = $restoreHost."/".$filePath;
	} else {
		$fullFilePath = $restoreHost.$filePath;
	}
}
#*************************************************************************************************
# Subroutine Name         : getTableforVersionData
# Objective               : This function will show version details in tabular form to user
# Added By                : Dhritikana Kalita.
#*************************************************************************************************

sub getTableforVersionData
{
	my @parsedVersionData = @{$_[0]};
	my $tableHeader = getTableHeader(@columnNames);
	my ($tableContent,$spaceIndex,$lineChangeIndicator) = ('',0,0);
	
	foreach(@parsedVersionData){
		$tableContent .= $_;
		$tableContent .= (' ') x ($columnNames[1]->[$spaceIndex] - length($_));
		if($lineChangeIndicator == 3){
			$tableContent .= $lineFeed;
			($lineChangeIndicator,$spaceIndex) = (0) x 2;
		}else{
			$spaceIndex++;
			$lineChangeIndicator += 1;
		}
	}
	if ($tableContent ne ''){
		print $tableHeader.$tableContent.$lineFeed;
	}else{
		print qq(\nNo version found.\nExiting..\n);
		exit;
	}
}

#*************************************************************************************************
# Subroutine Name         : doMainOperation.
# Objective               : Based on user's request, call restore function to perform restore job
# Added By                : Dhritikana Kalita.
#*************************************************************************************************
sub doMainOperation {
	my @parsedVersionData = '';
	my $tableHeader = '';
	if($mainMenuChoice eq 1) {
	    print $lineFeed.Constants->CONST->{'checkingFileVersion'}.$lineFeed;
		@parsedVersionData = getFileVersions();
		$tableHeader = getTableHeader(@columnNames);
		getTableforVersionData(\@parsedVersionData);
		print Constants->CONST->{'AskRestoreVer'}.$whiteSpace;
		$confirmationChoice = getConfirmationChoice();
		if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
			print Constants->CONST->{'Exit'}.$lineFeed;
			unlink($idevsErrorFile);
			exit 0;
		} 
	}
	askRestoreLocation(\$maximumRetryMessage);
	print "$maximumRetryMessage" if ($maximumRetryMessage ne '');	
	createRestoresetFile(\@parsedVersionData);
	restoreVersion();
#	unlink($idevsErrorFile);
}
#********************************************************************************
# Subroutine Name         : getFileVersions.
# Objective               : Gets versions of user's requested file
# Added By                : Dhritikana Kalita.
#********************************************************************************
sub getFileVersions {
	my $versionUtfFile = getOperationFile(Constants->CONST->{'VersionOp'}, $fullFilePath);
	my $errorMessageHandler = {'No version found'=>qq(No version found for given file. ),'path not found'=>qq(Could not find given file.),'cleanupOperation'=> sub {unlink($idevsErrorFile);print Constants->CONST->{'Exit'}.$lineFeed;exit;}};
	chomp($versionUtfFile);
	$versionUtfFile =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$versionUtfFile."'".$whiteSpace.$errorRedirection;
	my $commandOutput = `$idevsutilCommandLine`;
	unlink $versionUtfFile;
	system("clear");
	
	if(-s $idevsErrorFile>0){
		my $fileOpened = 1;
		open READERROR, "<$idevsErrorFile" or $fileOpened = 0;
		
		if(!$fileOpened){
			traceLog(Constants->CONST->{'FileOpnErr'}.", Resaon: $!".$lineFeed, __FILE__, __LINE__);
		}
		else{
			my $errStr = <READERROR>;
			close READERROR;
			chomp($errStr);
			$errStr =~ s/^\s+|\s+$//g;
			if($errStr ne ''){
				if ($errStr =~ /password mismatch|encryption verification failed/i){
					print $lineFeed.$errStr.'. '.Constants->CONST->{loginAccount}.$lineFeed;
					unlink($pwdPath);
				} 
				elsif($errStr =~ /failed to get the device information|Invalid device id/i){
					print $lineFeed.$errStr.". ".Constants->CONST->{restoreFromLocationConfigAgain}.$lineFeed.$lineFeed;
				} 
				else {
					print $lineFeed.$errStr.$lineFeed.$lineFeed;
				}
				exit;
			}
		}
	}
	if ($commandOutput =~/No version found/){
		print $errorMessageHandler->{"$&"}.$lineFeed;
		$errorMessageHandler->{'cleanupOperation'}->();
	} elsif($commandOutput =~ /path not found/) {
		print $errorMessageHandler->{"$&"}.$lineFeed;
        $errorMessageHandler->{'cleanupOperation'}->();
	}	 
	
	return parseVersionData($commandOutput);
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
	
	my $itemStatUtfFile = getOperationFile(Constants->CONST->{'ItemStatOp'}, "stat.txt");
	chomp($itemStatUtfFile);
	$itemStatUtfFile =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$itemStatUtfFile."'".$whiteSpace.$errorRedirection;
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
	my @parsedVersionData = @{$_[0]};
	my $initialInputCount = 0;
	do{
		if ($initialInputCount > 3){
			print Constants->CONST->{'InvalidInput'}.qq(\nYour maximum attempt reached. Please try again..\n);
                        exit;
		}else{
			print Constants->CONST->{'InvalidInput'}.$whiteSpace if ($initialInputCount > 0);
			print $lineFeed.Constants->CONST->{'AskVersion'}.$lineFeed;
			$versionNo = <STDIN>;
			Chomp(\$versionNo);	
		}
	}while(++$initialInputCount and $versionNo !~ /^\d+$/);
 	my $count = 0;	
	while($mainMenuChoice == 1 && $versionNo > $lastVersion or $versionNo < 1){ # or !getSize()) {
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
	while($mainMenuChoice == 2 && $versionNo > 30 or $versionNo < 1){ # or !getSize()) {
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
	$fileVersionSize = $parsedVersionData[(($versionNo-1)*4) + 3];
	#$fileVersionSize = $versionDetails[$versionNo-1]->[3]; #this will give file size for selected version.
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
	my $restoreRunCommand = "perl '$userScriptLocation'/".Constants->FILE_NAMES->{restoreScript}.' '.Constants->CONST->{'versionRestore'};
	system($restoreRunCommand);
	#unlink("$jobRunningDir/versionRestoresetFile.txt");
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
#****************************************************************************
#Subroutine Name         : parseVersionData
#Objective               : To parse the version details from EVS output.
#Usgae                   : parseVersionData(VERSION_XML_DATA)
#Added By                : Abhishek Verma.
#****************************************************************************/
sub parseVersionData{
	my $versionXmlData = shift;
	my $serialNumber = 1;
	my @fileVersionData;

	while($versionXmlData =~ /<item\s+mod_time="(.*?)"\s+size="(.*?)"\s+ver="(.*?)"\/>/){
		$versionXmlData = $';
		$lastVersion = $3;#$lastVersion variable is used later in the code. it is used to hold the last version number
		push (@fileVersionData,$serialNumber);
		push (@fileVersionData,$lastVersion);#0 -> contains version
		push (@fileVersionData,$1);#1 -> contains modified date
		push (@fileVersionData,convertFileSize($2));#2 -> contains size
		$serialNumber += 1;
	}
	return @fileVersionData;
}
