#!/usr/bin/perl

#################################################################################
#Script Name : Check_For_Update.pl
#################################################################################

unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));

our $lineFeed = undef;
our $whiteSpace = undef;
our $confFilePath = undef;
our $usrProfilePath = undef;

#use Constants 'CONST';
require Constants;
require 'Header.pl';


#-----------------------------------------Command Line ARG processing-------------------------------------------
my $availUpdateStats = $ARGV[0]; #This script is also used to check new version availability. So this variable is used. Requested by isUpdateAvailable() subroutine
				# Header.pl
#---------------------------------------------------------------------------------------------------------------

my $checkUpdateCGI = "https://www1.ibackup.com/cgi-bin/check_version_upgrades_idrive_evs_new.cgi?"; 
my $wget = whichWget(\"wget");
my $productLink = undef;
my $latestVersion = undef;
my $currentVersion = Constants->CONST->{'Version'};
my $product = $appType.Constants->CONST->{'Product'};
#my $currentDir = `pwd`;
chomp(my $currentDir = $userScriptLocation);
my $temp = "/tmp";
my $idriveZip = undef;
my $idriveDir = undef;
my $errMsg = undef;
my $idriveBackup = qq($temp/$appType).q(_backup);# This folder will be created in /tmp directory to keep the working directory .pl files as backup.
my $pos = rindex($currentDir, "/");
my $currentIdriveDir = substr($currentDir, 0, $pos);
my $wgetLogFile = $currentDir.'/wgetLog.txt';
my $updateLogFile = $currentDir.'/.updateLog.txt';
loadUserData();
#my $scrptDir = $currentDir;
my $fileNames = ['Account_Setting.pl','Check_For_Update.pl','Backup_Script.pl','Constants.pm','Header.pl','Job_Termination_Script.pl','Login.pl','Logout.pl','Operations.pl','readme.txt','Restore_Script.pl','Restore_Version.pl','Scheduler_Script.pl','Status_Retrieval_Script.pl','Edit_Supported_Files.pl','View_Log.pl'];
if(!$currentVersion) {
	$errMsg = "\n Couldn't extract current version number\n";
	cleanUp($errMsg);
}

if($product =~ /IDrive/) {
	$productLink = "http://www.idrive.com/downloads/linux/download-for-linux/IDrive_for_Linux.zip";
	#$productLink = "--user=deepak --password=deepak --http-user=deepak --http-password=deepak http://192.168.2.169/svn/linux_repository/trunk/PackagesForTesting/IDriveForLinux/IDrive_for_Linux.zip";
	$idriveZip = $temp."/"."IDrive_for_Linux.zip";
	$idriveDir = $temp."/"."IDrive_for_Linux";
} elsif($product =~ /IBackup/) {
	$productLink = "http://www.ibackup.com/online-backup-linux/downloads/download-for-linux/IBackup_for_Linux.zip";
	#$productLink = "--user=deepak --password=deepak --http-user=deepak --http-password=deepak https://192.168.2.169/svn/linux_repository/trunk/PackagesForTesting/IBackupForLinux/IBackup_for_Linux.zip";
	$idriveZip = $temp."/"."IBackup_for_Linux.zip";
	$idriveDir = $temp."/"."IBackup_for_Linux";
} else {
	$errMsg = "\n Couldn't extract product name\n";
	cleanUp($errMsg);
}
getProxyDetails() if(!($availUpdateStats eq 'availUpdate'));

$checkUpdateCGI = $checkUpdateCGI."appln='$product&version=$currentVersion'";
my ($cgiCmd, $wgetCmd) = formCmd();
my $updateExists = checkUpdate();

if(!$updateExists and !($availUpdateStats eq 'availUpdate')) {
	$errMsg = $product.Constants->CONST->{'productUptoDate'}.$lineFeed;
	cleanUp($errMsg);
}
elsif($availUpdateStats eq 'availUpdate'){#If updated version of scripts are available then create updateVersionInfo and exit.
	if($updateExists == 1){
		open (VN,'>', $userScriptLocation.'/.updateVersionInfo'); #VN file handler means version number.
		print VN Constants->CONST->{'Version'}; 
		close VN;
		chmod $filePermission,$userScriptLocation.'/.updateVersionInfo';
	}
	exit;
}
		
print $lineFeed.Constants->CONST->{'verAvlqueryMsg'};
my $updateChoice = getConfirmationChoice();
if($updateChoice eq "n" || $updateChoice eq "N" ) {
	$errMsg = "";
	cleanUp($errMsg);
}
removeUpdateVersionInfoFile($userScriptLocation.'/.updateVersionInfo');#Remove the given file if exists.
if(!chdir($temp)) {
	$errMsg = "Unable to update: $!\n";
	cleanUp($errMsg);
}

print $lineFeed.Constants->CONST->{'updatingScripts'}.$lineFeed;
cleanUp("INIT");
updateOperation();

#*************************************************************************************************
# Subroutine Name		: cleanUp.
# Objective			: This subroutine cleans up the prexisting files that was created during 
#				  previous version update check.					
# Added By			: Dhritikana
#*************************************************************************************************/
sub cleanUp {
	if(-e $idriveZip) {
		unlink($idriveZip);
	}
	if($_[0] eq "SUCCESS" or $_[0] eq "INIT") {
		if(-e $idriveDir) {
			`rm -rf $idriveDir`;
		}
		if (-e $idriveBackup){
			`rm -rf $idriveBackup`;
		}
		if(-e $temp."/scripts"){
			`rm -rf $temp/scripts`;
		}
		unlink("$wgetLogFile");
		unlink("unzipLog.txt");
		unlink ($updateLogFile);
	}	
	if($_[0] ne "SUCCESS"  and $_[0] ne "INIT"){
		print $_[0];
		exit;
	}
}
#*************************************************************************************************
# Subroutine Name		: updateOperation.
# Objective				: This subroutine updates the version to latest.					
# Added By				: Dhritikana
#*************************************************************************************************/
sub updateOperation {
	`$wgetCmd`;
	
	# failure handling for wget command
	open FILE, "<", "$wgetLogFile";
	my $wgetRes = join("", <FILE>); 
	close FILE;
	
	if($wgetRes =~ /failed:|failed: Connection refused|failed: Connection timed out|Giving up/ || $wgetRes eq "") {
		$errMsg = $lineFeed.$whiteSpace.Constants->CONST->{'ProxyErr'}."\n";
		cleanUp($errMsg);
	}
	
	if(!-e $idriveZip) {
		$errMsg .= "\n Update failed. Reason: unable to download package.\n";
		cleanUp($errMsg);
	}
	
	`unzip $idriveZip 2>unzipLog.txt`;
	#Creating a temporary idrive_backup directory in /tmp directory to keep the backup of scripts from working directory.
	my $dirCreateResult = createDirectory($idriveBackup);
	if ($dirCreateResult ne ''){#error handling if the backup directory in /tmp not created.
		$errMsg = "\n Unable to create directory $idriveBackup to take backup of old scripts. $dirCreateResult \n";
		cleanUp($errMsg);
	}
	if(-s "unzipLog.txt") {
		$errMsg = "\n Update failed, Reason: unable to unzip. \n";
		cleanUp($errMsg);
	}
	my $res = moveFiles($idriveBackup,$currentDir,$fileNames);
	if($res ne '') {
		my $res = moveFiles($idriveBackup,$currentDir,$fileNames);
		if ($res ne ''){
			$errMsg = $lineFeed.$whiteSpace."Failed to Update.".$lineFeed;
			cleanUp($errMsg);
		}else{
			unlink ($updateLogFile);
		}
	}else{
		unlink ($updateLogFile);
	}	
	moveUpdates();
	cleanUp("SUCCESS");
	print Constants->CONST->{'UpdateFinished'}.$lineFeed;
	#displayReleaseNotes();
	my $readMePath = $currentDir."/".Constants->FILE_NAMES->{readMeFile};
	my @latestFeature = `tac $readMePath | grep -m1 -B20 "Build"`;
	my @rfetures = reverse(@latestFeature);
	print $lineFeed.$whiteSpace.CONST->{'ReleaseNotes'};
	print @rfetures;
}

#*************************************************************************************************
# Subroutine Name	: checkUpdate.
# Objective		: check if version update exists for the product.					
# Added By		: Dhritikana
#*************************************************************************************************/
sub checkUpdate {
	if(!($availUpdateStats eq 'availUpdate')){
		system("clear");
		headerDisplay($0);
		print Constants->CONST->{'CheckVerMsg'}.$lineFeed;
	}
	my $cgiPostRes = `$cgiCmd`;
	chomp($cgiPostRes);
	if($cgiPostRes eq "Y") {
		return 1;
	} elsif($cgiPostRes eq "N") {
		return 0;
	} else {
		#<Deepak> check with ping command if internet is present. Or display error message "Please check your internet connectivity and try again.
		my $pingRes = `ping -c2 8.8.8.8`;
		if($pingRes =~ /connect\: Network is unreachable/) {
			$errMsg = $pingRes;
		} elsif($pingRes !~ /0\% packet loss/) { ###TEST
			$errMsg = "\n Please check your internet connectivity and try again.\n";
		}else{
			if ($cgiPostRes eq ''){
				print $lineFeed.Constants->CONST->{'ProxyUserErr'}.$lineFeed;
			}
		}
		cleanUp($errMsg);
	}
}
#*************************************************************************************************
# Subroutine Name		: moveUpdates.
# Objective				: This subroutine moves the updated files to the user working folder.					
# Added By				: Dhritikana
#*************************************************************************************************/
sub moveUpdates {
	my $moveItem = "$idriveDir/scripts";
	my $moveBackItemn = "$temp/scripts";

	my $res = moveFiles($currentDir,$moveItem,$fileNames);
	if($res ne '') {
		my $res = moveFiles($currentDir,$idriveBackup,$fileNames);
		if($res ne '') {
			$errMsg = $lineFeed.$whiteSpace."Failed to Update. Please copy perl libraries from $idriveBackup to $currentDir".$lineFeed;
			cleanUp($errMsg);
		} 
	}
	`chmod 0777 $currentDir`;
	`chmod 0777 $currentDir/*`;
}

#*************************************************************************************************
# Subroutine Name		: getConfirmationChoice.
# Objective				: This subroutine gets user input for yes/no.					
# Modified By			: Dhritikana
#*************************************************************************************************/
sub getConfirmationChoice {
	my $choice = undef;
	my $count = 0;
	while(!defined $choice) {
		$count++;
		if($count eq 4) {
			print Constants->CONST->{'maxRetry'}.$whiteSpace;
			exit;
		}
		print " ".Constants->CONST->{'EnterChoice'}." ";
		
		$choice = <STDIN>;
		Chomp(\$choice);	
		if($choice =~ m/^\w$/ && $choice !~ m/^\d$/) {
			if($choice eq "y" || $choice eq "Y" ||
				$choice eq "n" || $choice eq "N") {
			}
			else {
				$choice = undef;
				print " ".Constants->CONST->{'InvalidChoice'}." ";
			} 
		}
		else {
			$choice = undef;
			print " ".Constants->CONST->{'InvalidChoice'}." ";
		}
		$count++;
	}  
	print "\n";
	return $choice;
}

#*************************************************************************************************
# Subroutine Name		: formCmd.
# Objective				: This subroutine forms wget and curl command based on proxy settings.					
# Modified By			: Dhritikana
#*************************************************************************************************/
sub formCmd {
	my $curlCmd = undef;
	my $wgetCmd = undef;
	if($proxyStr) {
		my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
		my @UnP = split(/\:/, $uNPword);
		$checkUpdateCGI =~ s/https\:\/\///;
		my $proxyAuth = "";
		if($UnP[0] ne "") {
			foreach ($UnP[0], $UnP[1]) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$uNPword = join ":", @UnP;
			$proxyAuth = "$uNPword\@";
		} 
		$curlCmd = "curl --proxy  https://$proxyAuth$ipPort -s $checkUpdateCGI";
		$wgetCmd = "$wget \"--no-check-certificate\" \"--tries=2\" \"--output-file=$wgetLogFile\" -e \"http_proxy = http://$proxyAuth$ipPort\" $productLink";
	} else {			
		$curlCmd = "curl -s $checkUpdateCGI";
		$wgetCmd = "$wget \"--no-check-certificate\" \"--tries=2\" \"--output-file=$wgetLogFile\" $productLink";
	}
	return ($curlCmd, $wgetCmd);	
}
#*************************************************************************************************
# Subroutine Name               : moveFiles 
# Objective                     : This subroutine will move file between two given location locations.
# Added By                      : Abhishek Verma
#*************************************************************************************************/
sub moveFiles{
	my $destination		= $_[0];
	my $source 		= $_[1];
	my $listOfFiles		= $_[2];
	my $moveResult		= '';
        open (UPDATELOG,'>>',$updateLogFile) or die "Unable to open file : $!";
	chmod $filePermission,$updateLogFile;
	if ($destination ne '' and $source ne '' and (-e $destination) and (-e $source)){
		foreach (@{$listOfFiles}){
			my $fileToTransfer = qq($source/$_);
			if (-e $fileToTransfer){
				$moveResult = `mv $fileToTransfer $destination`;
				print UPDATELOG "$lineFeed move file : $moveResult  $lineFeed";
#				traceLog("$lineFeed move file : $moveResult  $lineFeed", __FILE__, __LINE__);
			}
			last if ($moveResult ne '');
		}
	}else{
		$moveResult = -1;
	}
	close UPDATELOG;
	return $moveResult;
}
#*************************************************************************************************
# Subroutine Name               : displayReleaseNotes
# Objective                     : This subroutine reads the release notes array from Constants.pm file and print on the STDOUT.
# Usage				: displayReleaseNotes()
# Added By                      : Abhishek Verma
#*************************************************************************************************/
sub displayReleaseNotes{
	my $releaseNotes = Constants->CONST->{'ReleaseNotesDetail'};
	my $releaseContent = '';
	foreach (@{$releaseNotes}){
		if ($releaseContent eq ''){
			 $releaseContent = ": ".$_."\n";
		}else{
			 $releaseContent .= "          ".$_."\n";
		}
	}
	print Constants->CONST->{'ReleaseNotes'};
	print $releaseContent."\n";
}
#*************************************************************************************************
#Subroutine Name               : removeUpdateVersionInfoFile
#Objective                     : This subroutine reads the release notes array from Constants.pm file and print on the STDOUT.
#Usage                         : displayReleaseNotes()
#Added By                      : Abhishek Verma
#*************************************************************************************************/
sub removeUpdateVersionInfoFile{
	my $fileNameToRemove = shift;
	my $removeResult = '';
	if (-e $fileNameToRemove){
		$removeResult = `rm -f $fileNameToRemove $errorDevNull`;
	}
}
#*************************************************************************************************
#Subroutine Name               : whichWget
#Objective                     : This subroutine will give you the path of given command.
#Usage                         : whichWget()
#Added By                      : Abhishek Verma
#*************************************************************************************************/
sub whichWget{
        my $pckg = ${$_[0]};
        my $pckgPath = `which $pckg 2>/dev/null`;
        chomp($pckgPath);
        return $pckgPath;
}
