#!/usr/bin/perl
##########################################
#Account_setting.pl
#########################################
use FileHandle;
use File::Path qw(make_path);
use File::Copy;
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require Constants;
require 'Header.pl';
my $encType = undef;
my $dedup = "off";
my $idevsZip = undef;
my $prevPathIdev = undef;
my $idevsHelpLen = undef;
my $wrtToErr = "2>$idriveSerivePath/".Constants->CONST->{'tracelog'};
my $outputDevNull = '1>/dev/null';
my $idevsUtilLink = undef;
my $emailAddr = '';
my $loggedInStat = 0;
my $pvt = undef;
my $AccSettingsMenu = ['1) Re-configure your account freshly','2) Edit your account details','3) Exit'];#ArrRef to hold menu
# $appTypeSupport should be ibackup for ibackup and idrive for idrive#
# $appType should be IBackup for ibackup and IDrive for idrive        #
my ($desc, $plan_type, $message, $cnfgstat, $enctype, $res) = ('','','','','','');
##############################################
#Subroutine that processes SIGINT and SIGTERM#
#signal received by the script during backup #
##############################################
$SIG{INT} = \&cancelProcess;
$SIG{TERM} = \&cancelProcess;
$SIG{TSTP} = \&cancelProcess;
$SIG{QUIT} = \&cancelProcess;
system("clear");
headerDisplay($0);

print $lineFeed.Constants->CONST->{'CheckPreq'}.$lineFeed;
my $unzip = checkPrerequisite(\"unzip");
my $curl = checkPrerequisite(\"curl");
my $wget = checkPrerequisite(\"wget");

print $lineFeed.Constants->CONST->{'Instruct'}.$lineFeed;
checkAndCreateServicePath();
##get user name input
  print $lineFeed.Constants->CONST->{'displayUserMessage'}->('Enter your',$appType,'username: ');
  $userName = getInput();
  checkInput(\$userName);
  Chomp(\$userName);
  unless (validateUserName($userName)){
	print Constants->CONST->{'InvalidUserPattern'}.$lineFeed;
	exit 0;
  }
##get password input
  print Constants->CONST->{'displayUserMessage'}->('Enter your',$appType,'password: ');
  system('stty','-echo');
  my $pwd = getInput();
  checkInput(\$pwd,$lineFeed);
  system('stty','echo'); 
  unless (validatePassword($pwd)){
      print $lineFeed.Constants->CONST->{'InvalidPassPattern'}.$lineFeed;
      exit 0;
  }
##get the service path
#my $userServicePath ='';
#my $resServicePath = '';
#checkAndCreateServicePath();
$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};
my $userDir = "$usrProfilePath/$userName";
## loading username in global variables
$serverfile = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'serverAddress'};
$pwdPath = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'IDPWD'};
$pvtPath = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'IDPVT'};
$enPwdPath = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'IDENPWD'};
$defRestoreLocation = qq($usrProfilePath/$userName/Restore_Data);

if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 

my %ConfFileValues = getConfigHashValue();
#get Previous username
my $CurrentUser = getCurrentUser();
my $TmpPwdPath = "$usrProfilePath/$CurrentUser/.userInfo/".Constants->CONST->{'IDPWD'};
#if( -e $TmpPwdPath and -f $TmpPwdPath) {
#        $loggedInStat = 1;
#        if($CurrentUser eq $userName) {
#		$sameUser=1;
#               print $lineFeed.Constants->CONST->{'AlreadyLoginUser'}.$lineFeed;
#               exit 1; ##what need to be done
#	}
#}

# get proxy details
getProxyDetails();

# checking compatible idevsutil
my $EvsOn = checkIfEvsWorking();
if($EvsOn eq 0) {
        my $retType = getCompatibleEvsBin(\$wgetCommand);
}

# create encode file for password
createEncodeFile($pwd, $pwdPath) and $pathFlag = 1;

getAccountInfo();
if ($dedup eq 'on'){
	print $lineFeed.Constants->CONST->{'DedupAccError'}.$lineFeed.$lineFeed;
	cancelProcess();
}
putParameterValue(\"PROXY",\"$proxyStr",$confFilePath);
#checkAndCreateServicePath();
my $createdirFlag=1;

if(-d $userDir && -e $confFilePath && -s $confFilePath) { ####<NEED more CHECK? to identify if configured?)
	$createdirFlag=0;
	print $lineFeed.Constants->CONST->{'AlreadyConfig'}.$lineFeed.$lineFeed;
	viewConfigurationFile();
	optionsForAccountOperation();
}

# If option for account operation is selected as 1. Means user wants to set account freshly then below flow will be taken.
my $sameUser = ifLoggedInUser($TmpPwdPath);
if ($sameUser){
	print $userName.Constants->CONST->{'AlreadyLoginUser'}.$lineFeed;
	exit 1;
}
# creating user profile path and job path
print Constants->CONST->{'CrtUserDir'}.$lineFeed if($createdirFlag);
createUserDir();
print Constants->CONST->{'DirCrtMsg'}.$lineFeed if($mkDirFlag);

# Trace Log Entry #
my $curFile = basename(__FILE__);
traceLog("$lineFeed File: $curFile $lineFeed ---------------------------------------- $lineFeed", __FILE__, __LINE__);

# create encode file for password
#createEncodeFile($pwd, $pwdPath) and $pathFlag = 1;

# get server address
unless(-e $serverfile || -s $serverfile) {
	exit if(!(getServerAddr()));
}

if( -e $serverfile) {
	open FILE, "<", $serverfile or (traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}.$serverfile." , Reason:$! $lineFeed", __FILE__, __LINE__) and die);
	chomp($serverAddress = <FILE>);
#	chomp($serverAddress);
	close FILE;
} else {
	cancelProcess();
}

loadUserData();

#getQuota($0);
getQuotaForAccountSettings();
accountErrInfo();

setConfDetails();

updateConfFile();

#****************************************************************************
# Subroutine Name         : checkPrerequisite
# Objective               : Check if required binary executables are installed in 
#							user system or not.
# Added By                : Dhritikana
#****************************************************************************/
sub checkPrerequisite {
	my $pckg = ${$_[0]};
	my $pckgPath = `which $pckg 2>/dev/null`;
	chomp($pckgPath);

	if($pckgPath) {
		print $pckg.$whiteSpace.Constants->CONST->{'IsAbvl'}.$lineFeed;
		return $pckgPath;
	} else {
		print $pckg.$whiteSpace.Constants->CONST->{'NotAbvl'};
		print $whiteSpace.Constants->CONST->{'SuggestInstall'}.$lineFeed;
		traceLog($whiteSpace.$pckg.$whiteSpace.Constants->CONST->{'NotAbvl'}.$whiteSpace.Constants->CONST->{'SuggestInstall'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();
	}
}
#***************************************************************************************
# Subroutine Name         : checkIfEvsWorking
# Objective               : Checks if existing EVS binary is working or not.
# Added By                : Dhritikana
# Modified By 		  : Abhishek Verma - 09-03-17 - removed some unnecessary lines and variables. 
#*****************************************************************************************/
sub checkIfEvsWorking {
	if (-f $idevsutilBinaryPath){
		chmod $filePermission, $idevsutilBinaryPath;
	        my @idevsHelp = `$idevsutilBinaryPath -h 2>/dev/null`;
	        if(scalar(@idevsHelp) < 50 ) {
        	        return 0;
	        }
	}else{
		return 0;
	}
}

#***************************************************************************************
# Subroutine Name         : getCompatibleEvsBin
# Objective               : Downloads the idevsutil binary zip freshly. Extracts it and 
#							keep in the working folder.
# Added By                : Dhritikana
# Modified By		  : Deepak
# Modified By 		  : Abhishek Verma - 11/24/2016 - To make subroutine functional even if user execute script from any location.
#*****************************************************************************************/
sub getCompatibleEvsBin {
	print Constants->CONST->{'EvsCmplCheck'}.$lineFeed;
	
	my $count = 0;
	while(1) {
		# Getting EVS link based on machine
		if ($proxyOn eq 1){
			$EvsBin32 = 'http://'.$EvsBin32;
			$EvsBin64 = 'http://'.$EvsBin64;
		}else{
			$EvsBin32 = 'https://'.$EvsBin32;
			$EvsBin64 = 'https://'.$EvsBin64;
		}
		getCompatibleEvsLink();
		
		# removing old zip and downloading new zip based on EVS link received
		my $wgetCmd = formWgetCmd(\$proxyOn);		
		if(-e $idevsZip) {
			unlink $idevsZip;
		}
		`$wgetCmd`;
		# failure handling for wget command
		my $traceFile = "$idriveSerivePath/".Constants->CONST->{'tracelog'};
	        open FILE, "<", $traceFile or die "Couldn't open file: [$traceFile] $!";
		my $wgetRes = join("", <FILE>); 
		close FILE;
		unlink "$idriveSerivePath/".Constants->CONST->{'tracelog'};
		traceLog("wget res :$wgetRes", __FILE__, __LINE__);
		
		if($wgetRes =~ /failed:|failed: Connection refused|failed: Connection timed out|Giving up/ || $wgetRes eq "") {
			print $lineFeed.Constants->CONST->{'ProxyErr'}.$lineFeed;
			traceLog("$lineFeed WGET for EVS Bin: $wgetRes $lineFeed", __FILE__, __LINE__);
			cancelProcess();
		}
		
		if($wgetRes =~ /Unauthorized/) {
			print $lineFeed.Constants->CONST->{'ProxyUserErr'}.$lineFeed;
			traceLog("$lineFeed WGET for EVS Bin: $wgetRes $lineFeed", __FILE__, __LINE__);
			cancelProcess();
		}
		
		#cleanup the unzipped folder before unzipping new zipped file
		if(-e $prevPathIdev) {
			rmtree($prevPathIdev);
		}

		if(!-e $idevsZip) {
			next;
		}
		#unzip the zipped file and in case of error exit
		my $idevsZipCmd = $idevsZip;                                                
		$idevsZipCmd =~ s/\'/\'\\''/g;    
		$idevsZipCmd = "'".$idevsZipCmd."'"; 
		my $optionSwitch = '-d';                     
		my $idevsUnzipLoc = $idriveSerivePath;
		$idevsUnzipLoc =~ s/\'/\'\\''/g;
		$idevsUnzipLoc = "'".$idevsUnzipLoc."'";
#		system("$unzip $idevsZipCmd $optionSwitch $idevsUnzipLoc $wrtToErr '1>/dev/null'");
		system("$unzip $idevsZipCmd $optionSwitch $idevsUnzipLoc $outputDevNull");
		
		if(-s "$idriveSerivePath/".Constants->CONST->{'tracelog'}) {
			print $whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed;
			traceLog("$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed Error with unzip.", __FILE__, __LINE__);
			unlink "$idriveSerivePath/".Constants->CONST->{'tracelog'};
			cancelProcess();
		}
		unlink "$idriveSerivePath/".Constants->CONST->{'tracelog'};
		#remove the old evs binary and copy the new one with idevsutil name
		unlink($idevsutilBinaryPath);
		my $PreEvsPath = $prevPathIdev."idevsutil";
		my $retVal = rename "$idriveSerivePath/$PreEvsPath", "$idevsutilBinaryPath";
	
		# check if new evs binary exist or exit
		if(! -e $idevsutilBinaryPath) {
			print $lineFeed.Constants->CONST->{'TryAgain'}.$lineFeed;
			traceLog($lineFeed.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed, __FILE__, __LINE__);
			cancelProcess();
		}

		# provide permission to EVS binary and execute help command to find if binary is compatible one
		chmod $filePermission, $idevsutilBinaryPath;
		my @idevsHelp = `$idevsutilBinaryPath -h 2>/dev/null`;	
		if(50 <= scalar(@idevsHelp)) {
			print Constants->CONST->{'EvsInstSuccess'}.$lineFeed;
			#Cleaning evs zip file and evs folder
			rmtree("$idriveSerivePath/$prevPathIdev");
			unlink $idevsZip;
			return;
		}
		else{
			if(-e $idevsZip) {
				unlink $idevsZip;
			}	
			#cleanup the unzipped folder before unzipping new zipped file
			if(-e $prevPathIdev) {
				rmtree("$idriveSerivePath/$prevPathIdev");
			}		
		}
	}
}

#***************************************************************************************
# Subroutine Name         : getMenuChoice
# Objective               : get Menu choioce to check if user wants to configure his/her 
#							with Default or Private Key.
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

#***********************************************************************************
# Subroutine Name         : checkPvtKeyCondtions
# Objective               : check if given Private Key satisfy the conditions.
# Added By                : Dhritikana
#************************************************************************************/
sub checkPvtKeyCondtions {
	if(length(${$_[0]}) >= 6 && length(${$_[0]}) <= 250) {
		return 1;
	} else {
		print $lineFeed.Constants->CONST->{'AskPvtWithCond'}.$lineFeed.$whiteSpace;
		return 0;
	}
}

#***********************************************************************************
# Subroutine Name         : confirmPvtKey
# Objective               : check user given Private key equality and confirm.
# Added By                : Dhritikana
#************************************************************************************/
sub confirmPvtKey {
	my $count = 0;
	while($count < 4) {
		print $lineFeed.Constants->CONST->{'AskPvtAgain'}.$lineFeed;
		system('stty','-echo');
		my $pvtKeyAgin = getInput();
		system('stty','echo');
		$count++;
		if($pvt ne $pvtKeyAgin) {
			print $lineFeed.Constants->CONST->{'PvtErr'}.$lineFeed;
			#$count++;
		} else {
			print $lineFeed.Constants->CONST->{'ConfirmPvt'}.$lineFeed;
			last;
		}
		if($count eq 3) {
			print $lineFeed.Constants->CONST->{'TryAgain'}.$lineFeed;
			traceLog($lineFeed.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed, __FILE__, __LINE__);
			cancelProcess();
		}
	}
}
#********************************************************************************************
# Subroutine Name         : configAccount 
# Objective               : used to configure the user account.
# Added By                : Dhritikana
#********************************************************************************************/
sub configAccount {
	print $lineFeed.Constants->CONST->{'AskConfig'}.$whiteSpace;
	$confirmationChoice = getConfirmationChoice();
	if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
		exit 0;
	}
	print Constants->CONST->{'AskDefAcc'}.$lineFeed;
	print Constants->CONST->{'AskPvtAcc'}.$lineFeed;
	getMenuChoice();
	if($menuChoice eq "2") {
		$encType = "PRIVATE";
		my $retVal = undef;
		my $countPvtInput = 0;
		while(!$retVal) {
			if ($countPvtInput < 4){
				print $lineFeed.Constants->CONST->{'AskPvt'}.$lineFeed;
				system('stty','-echo');
				$pvt = getInput();
				system('stty','echo');
				$retVal = checkPvtKeyCondtions(\$pvt);
			}else{
				print $lineFeed.Constants->CONST->{'TryAgain'}.$lineFeed;
				traceLog($lineFeed.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed, __FILE__, __LINE__);
				cancelProcess();
			}
			$countPvtInput++;
		}
		confirmPvtKey();
		createEncodeFile($pvt, $pvtPath);
	} elsif( $menuChoice eq "1") {
		$encType = "DEFAULT";
	}
		
	my $configUtf8File = getOperationFile($configOp, $encType);
	chomp($configUtf8File);
	$configUtf8File =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$configUtf8File."'".$whiteSpace.$errorRedirection;
	my $commandOutput = `$idevsutilCommandLine`;
	traceLog("$lineFeed $commandOutput $lineFeed", __FILE__, __LINE__);
	unlink $configUtf8File;
}

#****************************************************************************************************
# Subroutine Name         : getArmEvsLink
# Objective               : This subroutine finds the system compatible EVS binary downloadable link
#							for arm machines
# Added By                : Deepak.
#****************************************************************************************************/
sub getArmEvsLink
{
	#try with qnap arm evs binary
	if($idevsUtilLink eq ""){
		$idevsUtilLink = $EvsQnapArmBin;
#		$idevsZip = $currentDir."/QNAP_ARM.zip";
		$idevsZip = $idriveSerivePath."/QNAP_ARM.zip";
		$prevPathIdev = "QNAP ARM/";
	}
	elsif($idevsUtilLink eq $EvsQnapArmBin)
	{
		#try with synology arm evs binary
		$idevsUtilLink = $EvsSynoArmBin;
#		$idevsZip = $currentDir."/synology_ARM.zip";
		$idevsZip = $idriveSerivePath."/synology_ARM.zip";
		$prevPathIdev = "synology_ARM/";
	}
	elsif($idevsUtilLink eq $EvsSynoArmBin)
	{
		#try with netgear arm evs binary
		$idevsUtilLink = $EvsNetgArmBin;
#		$idevsZip = $currentDir."/Netgear_ARM.zip";
		$idevsZip = $idriveSerivePath."/Netgear_ARM.zip";
		$prevPathIdev = "Netgear_ARM/";
	}
	elsif($idevsUtilLink eq $EvsNetgArmBin)
	{
		#try with universal evs binary
		$idevsUtilLink = $EvsUnvBin;
#		$idevsZip = $currentDir."/idevsutil_linux_universal.zip";
		$idevsZip = $idriveSerivePath."/idevsutil_linux_universal.zip";
		$prevPathIdev = "idevsutil_linux_universal/";
	}
	else
	{
		print $lineFeed.Constants->CONST->{'EvsMatchError'}.$lineFeed;
		traceLog($lineFeed.$whiteSpace.Constants->CONST->{'EvsMatchError'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();
	}
}

#****************************************************************************************************
# Subroutine Name         : get32bitEvsLink
# Objective               : This subroutine finds the system compatible EVS binary downloadable link
#							for 32 bit and 64 bit machines
# Added By                : Deepak.
#****************************************************************************************************/
sub get32bitEvsLink {
	if($idevsUtilLink eq ""){
		#try with linux 32 evs binary
		$idevsUtilLink = $EvsBin32;
#		$idevsZip = $currentDir."/idevsutil_linux.zip";
		$idevsZip = $idriveSerivePath."/idevsutil_linux.zip";
		$prevPathIdev = "idevsutil_linux/";
	}
	elsif($idevsUtilLink eq $EvsBin32){
		#try with qnap 32 evs binary
		$idevsUtilLink = $EvsQnapBin32_64;
#		$idevsZip = $currentDir."/QNAP_Intel_Atom_64_bit.zip";
		$idevsZip = $idriveSerivePath."/QNAP_Intel_Atom_64_bit.zip";
		$prevPathIdev = "QNAP Intel Atom 64 bit/";
	}
	elsif($idevsUtilLink eq $EvsQnapBin32_64){
		#try with synology 32 evs binary
		$idevsUtilLink = $EvsSynoBin32_64;
#		$idevsZip = $currentDir."/synology_64bit.zip";
		$idevsZip = $idriveSerivePath."/synology_64bit.zip";
		$prevPathIdev = "synology_64bit/";
	}
	elsif($idevsUtilLink eq $EvsSynoBin32_64){
		#try with netgear 32 evs binary
		$idevsUtilLink = $EvsNetgBin32_64;
#		$idevsZip = $currentDir."/Netgear_64bit.zip";
		$idevsZip = $idriveSerivePath."/Netgear_64bit.zip";
		$prevPathIdev = "Netgear_64bit/";
	}
	elsif($idevsUtilLink eq $EvsNetgBin32_64){
		#try with linux universal evs binary
		$idevsUtilLink = $EvsUnvBin;
#		$idevsZip = $currentDir."/idevsutil_linux_universal.zip";
		$idevsZip = $idriveSerivePath."/idevsutil_linux_universal.zip";
		$prevPathIdev = "idevsutil_linux_universal/";
	}
	else{
		print $lineFeed.Constants->CONST->{'EvsMatchError'}.$lineFeed;
		traceLog($lineFeed.$whiteSpace.Constants->CONST->{'EvsMatchError'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();
	}
}

#****************************************************************************************************
# Subroutine Name         : get64bitEvsLink
# Objective               : This subroutine finds the system compatible EVS binary downloadable link
#							for 64 bit and 64 bit machines
# Added By                : Deepak.
#****************************************************************************************************/
sub get64bitEvsLink 
{
	if($idevsUtilLink eq ""){
		$idevsUtilLink = $EvsBin64;
#		$idevsZip = $currentDir."/idevsutil_linux64.zip";
#		$prevPathIdev = "$currentDir/idevsutil_linux64/";
		$idevsZip = $idriveSerivePath."/idevsutil_linux64.zip";
		$prevPathIdev = "idevsutil_linux64/";
		return;
	}
	elsif($idevsUtilLink eq $EvsBin64){
		$idevsUtilLink = undef;
	}
	get32bitEvsLink();
}

#****************************************************************************************************
# Subroutine Name         : getCompatibleEvsLink
# Objective               : This subroutine finds the system compatible EVS binary downloadable link.
# Added By                : Dhritikana.
#****************************************************************************************************/
sub getCompatibleEvsLink {
	my $uname = `uname -m`;
	
	if($uname =~ /i686|i386/) {		# checking for all available 32 bit binaries
		get32bitEvsLink();
	} 
	elsif($uname =~ /x86_64|ia64/) {	# checking for all available 64 bit binaries
		get64bitEvsLink();
	} 
	elsif($uname =~ /arm/){			# checking for all available arm binaries
		getArmEvsLink();
	}
	else {
		print $lineFeed.Constants->CONST->{'EvsMatchError'}.$lineFeed;
		traceLog($lineFeed.$whiteSpace.Constants->CONST->{'EvsMatchError'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();
	}
}

#**************************************************************************************************
# Subroutine Name         : formWgetCmd
# Objective               : Form wget command to download EVS binary based on proxy settings.
# Added By                : Dhritikana.
#**************************************************************************************************/
sub formWgetCmd {
	my $wgetXmd = undef;
	if(${$_[0]} eq 1) {
		my $proxy = undef;
		if($proxyUsername eq "") {
			$proxy = 'http://'.$proxyIp.':'.$proxyPort;
		} else {
			$proxy = 'http://'.$proxyUsername.':'.$proxyPassword.'@'.$proxyIp.':'.$proxyPort;
		}
		$wgetCmd = "$wget \"--no-check-certificate\" \"--directory-prefix=$idriveSerivePath\" \"--tries=2\" -e \"http_proxy = $proxy\" $idevsUtilLink \"--output-file=$idriveSerivePath/traceLog.txt\" ";
	} elsif(${$_[0]} eq 0) {
			$wgetCmd = "$wget \"--no-check-certificate\" \"--output-file=$idriveSerivePath/traceLog.txt\" \"--directory-prefix=$idriveSerivePath\" $idevsUtilLink";
	}
	traceLog("wget cmd :$wgetCmd", __FILE__, __LINE__);
	return $wgetCmd;
}

#****************************************************************************************************
# Subroutine Name         : getAccountInfo.
# Objective               : Gets the user account information by using CGI.
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub getAccountInfo {
	print Constants->CONST->{'verifyAccount'}.$lineFeed;
	my $PATH = undef;
	if($appType eq "IDrive") {
		$PATH = $IDriveAccVrfLink;
	} elsif($appType eq "IBackup") {
		$PATH = $IBackupAccVrfLink;
	}
	
	my $encodedUname = $userName;
	my $encodedPwod = $pwd;
	#URL DATA ENCODING#
	foreach ($encodedUname, $encodedPwod) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}
	
	my $data = 'username='.$encodedUname.'&password='.$encodedPwod;
	if($proxyOn eq 1) {
		$curlCmd = "$curl --max-time 15 -x http://$proxyIp:$proxyPort --proxy-user $proxyUsername:$proxyPassword -L -s -k -d '$data' '$PATH'";
	} else {
#		$curlCmd = "$curl --max-time 15 -s -k -d '$data' '$PATH'";
		$curlCmd = "$curl --max-time 15 -s -k -d '$data' '$PATH'";
	}
	$res = `$curlCmd`;
	if($res =~ /FAILURE/) {
		if($res =~ /passwords do not match|username doesn\'t exist|Username or Password not found|invalid value passed for username|password too short|username too short|password too long|username too long/i) {
#			undef $userName; Any specific reason behind writing this statement.
			print "$&. ".Constants->CONST->{'TryAgain'}."$lineFeed";
			traceLog("$linefeed $curl failed, Reason: $&", __FILE__, __LINE__);
#			removeFilesFolders(["$usrProfilePath/$userName"]);
			cancelProcess();
		}
	} elsif ($res =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
		undef $userName;
		print "$res.\n";
		traceLog("$linefeed $curl failed, Reason: $res\n", __FILE__, __LINE__);
		cancelProcess();
	}
	traceLog("curl res :$res", __FILE__, __LINE__);
	if(!$res) {
		$res = validateAccountUsingEvs();
		if (!$res){
			print Constants->CONST->{'NetworkErr'}.$lineFeed;
			traceLog($lineFeed.$whiteSpace.Constants->CONST->{'NetworkErr'}.$lineFeed.$whiteSpace, __FILE__, __LINE__);
			cancelProcess();
		}elsif($res =~ /Failed to connect\. Verify proxy details/){
			 print Constants->CONST->{'ProxyUserErr'}.$lineFeed;
			 traceLog($lineFeed.$whiteSpace.Constants->CONST->{'ProxyUserErr'}.$lineFeed.$whiteSpace, __FILE__, __LINE__);
			 cancelProcess();
		}
	} elsif( $res =~ /Unauthorized/) {
		$res = validateAccountUsingEvs();
		if ($res =~ /Unauthorized/){
			print Constants->CONST->{'ProxyUserErr'}.$lineFeed;
			traceLog($lineFeed.$whiteSpace.Constants->CONST->{'ProxyUserErr'}.$lineFeed.$whiteSpace, __FILE__, __LINE__);
			cancelProcess();
		}
	}
 	if ($res eq ''){
		$res = validateAccountUsingEvs();
		if ($res eq ''){
			print Constants->CONST->{'NetworkErr'}.$lineFeed;
        	        traceLog($lineFeed.$whiteSpace.Constants->CONST->{'NetworkErr'}.$lineFeed.$whiteSpace, __FILE__, __LINE__);
                	cancelProcess();
		}
	}
	parseXMLOutput(\$res);
	chomp(%evsHashOutput);
	$encType = $evsHashOutput{"enctype"} ne "" ? $evsHashOutput{"enctype"} : $evsHashOutput{"configtype"};
	$plan_type = $evsHashOutput{"plan_type"};
	$message = $evsHashOutput{"message"};
	$cnfgstat = $evsHashOutput{"cnfgstat"} ne "" ? $evsHashOutput{"cnfgstat"} : $evsHashOutput{"configstatus"};
	$desc = $evsHashOutput{"desc"};
	$dedup = $evsHashOutput{"dedup"} if($appType eq "IDrive");
}
#***************************************************************************************************
# Subroutine Name         : setBackupLocation
# Objective               : Create a backup directory on user account in order to check if 
#							user provided private key is correct. Ask user for correct private key
#							incase it is wrong.
# Added By                : Dhritikana.
#***************************************************************************************************/
sub setBackupLocation {
	# create user backup directory on IDrive account
	my $createDirUtfFile = getOperationFile($createDirOp, $encType);
	chomp($createDirUtfFile);
	$createDirUtfFile =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$createDirUtfFile."'".$whiteSpace.$errorRedirection;
	$commandOutput = qx{$idevsutilCommandLine};
	unlink($createDirUtfFile);
	
	if($commandOutput =~ /encryption verification failed|key must be between 4 and 256/){
		return 0;
	} 
	elsif($commandOutput =~ /created successfull/) {
		return 1;
	} elsif($commandOutput =~ /file or folder exists/) {
		return 2;
	}
	else {
		print "$commandOutput\n";
		exit 1;
	}
}

#***************************************************************************************
# Subroutine Name         : accountErrInfo
# Objective               : Provides the user account error information before 
#							proceeding Account setting.
# Added By                : Dhritikana
#****************************************************************************************/
sub accountErrInfo {
	if($message !~ /SUCCESS/) {
		print "";
		print "\n ".$evsHashOutput{'desc'}." \n";
		traceLog($evsHashOutput{'desc'}, __FILE__, __LINE__);
		cancelProcess();
	}
	
	if($plan_type eq "Mobile-Only") {
		print "\n $evsHashOutput{'desc'}\n";
		traceLog("\n $evsHashOutput{'desc'}", __FILE__, __LINE__);
		cancelProcess();
	}
}

#**********************************************************************************************************
# Subroutine Name         : verifyPvtKey
# Objective               : This subroutine varifies the private key by trying to create backup directory. 
# Added By                : Dhritikana
#*********************************************************************************************************/
sub verifyPvtKey {
#	$backupHost = `hostname`;
#	chomp($backupHost);
	print $lineFeed.Constants->CONST->{'verifyPvt'}.$lineFeed;
	my $pvtVerifyUtfFile = getOperationFile($verifyPvtOp);
	
	my $tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
	$tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;
	my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
	$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
	my $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
	my $retType = `$idevsUtilCommand`;
#`	unlink($pvtVerifyUtfFile);
	my $count = 0;
	while($retType !~ /verification success/) {
		if($count eq 3) {
			print Constants->CONST->{'maxRetry'}.$lineFeed;
			traceLog($lineFeed.Constants->CONST->{'maxRetry'}.$lineFeed, __FILE__, __LINE__);
			cancelProcess();
		}
		$count++;
		print Constants->CONST->{'AskCorrectPvt'};
		system('stty','-echo');
		$pvt = getInput();
		checkInput(\$pvt,$lineFeed);
		system('stty','echo');
		createEncodeFile($pvt, $pvtPath);
		print $lineFeed.Constants->CONST->{'verifyPvt'}.$lineFeed;	
		$pvtVerifyUtfFile = getOperationFile($verifyPvtOp);
		$tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
		$tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;
		
		$tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
		$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
		
		$idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
		$retType = `$idevsUtilCommand`;
		
#		unlink($pvtVerifyUtfFile);
	}
	print Constants->CONST->{'verifiedPvt'}.$lineFeed;
}
#****************************************************************************************************
#Subroutine Name        	: checkRestoreFromLoc
#Objective             		: This subroutine verifies if RestoreFrom Location exists
#Added By                	: Dhritikana
#****************************************************************************************************/
sub getRestoreFromLoc {
	my $locationInputCount=0;
	while(1) {
		if ($locationInputCount < 3){
			print $lineFeed.Constants->CONST->{'AskRestoreFrom'};
			$restoreHost = getLocationInput("restoreHost");
		}

		if($restoreHost eq "/") {
			last;
		}
		
		if($restoreHost eq "" || $locationInputCount == 3) {
			print Constants->CONST->{'maxRetryRestoreFrom'}.$lineFeed.$lineFeed if ($locationInputCount == 3);
			$restoreHost = $backupHost;
			print Constants->CONST->{'messDefaultRestoreFrom'}.qq{ "$restoreHost" $lineFeed};
		}
		
		if(substr($restoreHost, 0, 1) ne "/") {
			$restoreHost = "/".$restoreHost;
		}
		
		my $propertiesFile = getOperationFile($propertiesOp,$restoreHost);
		chomp($propertiesFile);
		$propertiesFile =~ s/\'/\'\\''/g;
		
		$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$propertiesFile."'".$whiteSpace.$errorRedirection;
		my $commandOutput = `$idevsutilCommandLine`;
		traceLog("$lineFeed $commandOutput $lineFeed", __FILE__, __LINE__);
		#print $tHandle "$lineFeed $commandOutput $lineFeed";
		unlink $authUtfFile;
		unlink $propertiesFile;
		
		if($commandOutput =~ /No such file or directory/) {
				$restoreHost='';
			print $lineFeed.Constants->CONST->{'NoFileEvsMsg'};
			print $lineFeed.Constants->CONST->{'RstFromGuidMsg'}.$lineFeed;
		} else {
			last;
		}
		$locationInputCount++;
	}
	if($restoreHost ne "") {
		print Constants->CONST->{'RestoreLocMsg'}.$whiteSpace."\"$restoreHost\"".$lineFeed;
	}
}
#**********************************************************************************************************
# Subroutine Name         : setConfDetails
# Objective               : This subroutine configures the user account if not set and asks user details 
#							which are required for setting the account.
# Added By                : Dhritikana
# Modified By		  : Abhishek Verma-12/01/2016-code added to show proper message, if restore location exists.
# 			    Abhishek Verma-12/02/2016-code added to remove trailing and leading spaces from email id.
#*********************************************************************************************************/
sub setConfDetails {
	# Based on Config Status configures the "NOT SET" account
	if($cnfgstat eq "NOT SET") {
		configAccount();
		$backupHost = `hostname`;	
	} elsif($cnfgstat eq "SET") {
		# For Private Account Verifies the Private Encryption Key
		if($encType eq "PRIVATE") {
			print $lineFeed.Constants->CONST->{'AskPvt'};
			system('stty','-echo');
			$pvt = getInput();
			checkInput(\$pvt,$lineFeed);
			system('stty','echo');
			createEncodeFile($pvt, $pvtPath);
			verifyPvtKey();
		}
	}
		
	# get and set user backup location
	getAndSetBackupLocation();
	
	# get restore location from user.
	getRestoreLocation($0);
	# set restore location
	my $res = setRestoreLocation($restoreLocation,$defRestoreLocation);
	if ($res eq ""){
		$restoreLocation=~s/^\'//;
		$restoreLocation=~s/\'$//;
		print qq{Restore Location "$restoreLocation" created successfully }.$lineFeed;
		chmod $filePermission, $restoreLocation;
	}else{
		if ($res =~ /mkdir:.*(Permission denied)/i){
			print Constants->CONST->{'InvRestoreLoc'}.qq($restoreLocation. $1.\n);
			traceLog("$lineFeed Restore Location : $res $lineFeed", __FILE__, __LINE__);
			$restoreLocation=$defRestoreLocation;
			$res = createDefaultRestoreLoc($restoreLocation);
             		if ($res ne ""){
                        	print qq{Restore Location "$restoreLocation" created successfully }.$lineFeed;
                        	chmod $filePermission, $restoreLocation;
               	 	}
		}
	}	
	# get and set user restore from location
	getRestoreFromLoc(\$restoreHost);
	
	# get user email address
	print $lineFeed.Constants->CONST->{'AskEmailId'};
	
	my $wrongEmail = undef;
	my $emailInputCount=0;
	my @finalEmail =();
	while(1) {	
		my $failed =undef;
		my @email = undef;
		my $email = getInput();
		$email =~s/^\s+|\s+$//;
		if($email =~ /\,|\;/) {
			@email = split(/\,|\;/, $email);
		} else {
			push(@email, $email);
		}
		
		@email = grep /\S/, @email;
		if(scalar(@email) lt 1) {
			last;
		}
		
		foreach my $eachId (@email) {
			my $tmp = quotemeta($eachId);
			if($emailAddr =~ /^$tmp$/) {
				next;
			}
			$eachId =~s/^[\s\t]+|[\s\t]+$//g;
			my $eVal = validEmailAddress($eachId);
			if($eVal eq 0 ) {
				$emailInputCount++;
				$wrongEmail .=	qq($eachId, );
				$failed = 1;
			} else {
				push(@finalEmail,$eachId);
			}
		}

		if($failed ne 1) {
			last;
		}
		elsif($emailInputCount == 4){
			$wrongEmail =~ s/,\s+$//g;
			print Constants->CONST->{'InvalidEmail'}.$whiteSpace.$wrongEmail.$lineFeed;
			print Constants->CONST->{'maxRetryEmailID'};
			last;
		}else {
			$wrongEmail =~ s/,\s+$//g;
			print Constants->CONST->{'InvalidEmail'}.$whiteSpace.$wrongEmail.$lineFeed;
			print Constants->CONST->{'AskEmailId'};
			$wrongEmail = undef;
		}
	}
	if ($#finalEmail > -1){	
		$emailAddr = join(', ',uniqueData(@finalEmail));
		print Constants->CONST->{'ConfigEmailIDMess'}.qq{$emailAddr $lineFeed};
	}else{
		print Constants->CONST->{'emailNotConfig'}.$lineFeed;
	}
	
	# ask user for retain logs
	print $lineFeed.Constants->CONST->{'AskRetainLogs'}.$whiteSpace;
	$confirmationChoice = getConfirmationChoice();
	if($confirmationChoice eq "y" or $confirmationChoice eq "Y") {
		print Constants->CONST->{'retainLogsEnable'}.$lineFeed;
		$ifRetainLogs = "YES";
	} else {
		print Constants->CONST->{'retainLogsDisabled'}.$lineFeed;
		$ifRetainLogs = "NO";
	}
	
	#ask user for Backup type
	getBackupType();
}

#*********************************************************************************************
# Subroutine Name	: updateConfFile
# Objective		: update Configuration file based on user provided details.
# Added By		: Dhritikana
# Modified By		: Abhishek Verma-Date: 14/10/2016-Fine tune login process in case to two user trying to login
#*********************************************************************************************/
sub updateConfFile {
	my $dummyString = "XXXXX";
	
	print $lineFeed.Constants->CONST->{'SetBackupList'}.$lineFeed;
	open(FH, ">", $backupsetFilePath) or (print $! and exit(1));	
	print Constants->CONST->{'LocationString'}.$backupsetFilePath.$lineFeed;
	chmod $filePermission, $backupsetFilePath;
#	`ln -s $backupsetFilePath $backupsetFileSoftPath $errorRedirection`;
	
	print $lineFeed.Constants->CONST->{'SetRestoreList'}.$lineFeed;
	open(FH, ">", $RestoresetFile)	or (print $! and exit(1)); 
	print Constants->CONST->{'LocationString'}.$RestoresetFile.$lineFeed;
	chmod $filePermission, $RestoresetFile;
#	`ln -s $RestoresetFile $RestoresetFileSoftPath $errorRedirection`; 
	
	print $lineFeed.Constants->CONST->{'SetFullExclList'}.$lineFeed; 
	open(FH, ">", $excludeFullPath)	or (print $! and exit(1));  
	print Constants->CONST->{'LocationString'}.$excludeFullPath.$lineFeed;
	chmod $filePermission, $excludeFullPath;
	
	print $lineFeed.Constants->CONST->{'SetParExclList'}.$lineFeed;
	open(FH, ">", $excludePartialPath) or (print $! and exit(1));  
	print Constants->CONST->{'LocationString'}.$excludePartialPath.$lineFeed;
	chmod $filePermission, $excludePartialPath;
	
	print $lineFeed.Constants->CONST->{'SetRgxExcludeList'}.$lineFeed;
	open(FH, ">", $regexExcludePath) or (print $! and exit(1));  
	print Constants->CONST->{'LocationString'}.$regexExcludePath.$lineFeed;
	chmod $filePermission, $regexExcludePath;
	# if same user is configurating account again and its logged in user then only config value should change other stat should be same.
	$confirmationChoice = ($loggedInStat == 1 and $sameUser == 1) ? 'Y':'N';
	
	#To write to configuration file & to prevent unlinking of .IDPWD and .IDPVT files (last parameter 0 has been passed to achieve this purpose.) 
	
	writeConfigurationFile($confFilePath,$confirmationChoice,$dummyString,0); 	
	
	if($loggedInStat ne 1) { # for fresh login
		print $lineFeed.Constants->CONST->{'AccountConfig'}.$whiteSpace.Constants->CONST->{'AskLogin'}.$whiteSpace;
		$confirmationChoice = getConfirmationChoice($0,q(Please try to login using ).Constants->FILE_NAMES->{loginScript});
		if ($confirmationChoice eq 'y' or $confirmationChoice eq 'Y'){
			writeConfigurationFile($confFilePath,$confirmationChoice,$dummyString,1);
			createCache();
			print qq("$userName" ).Constants->CONST->{'LoginSuccess'}.$lineFeed; 
		}
	}
	# One user already logged in. And other account is configured and trying to do login.
	if ($loggedInStat == 1 and $CurrentUser ne '' and  $sameUser==0){
		print $lineFeed.qq{"$CurrentUser" }.Constants->CONST->{'userLoggedIn'};
                $confirmationChoice = getConfirmationChoice($0,Constants->CONST->{'AccountConfig'}.q(. Please try to login using ).Constants->FILE_NAMES->{loginScript});
		if ($confirmationChoice eq 'y' || $confirmationChoice eq 'Y'){
			my $logoutScript = "$userScriptLocation/".Constants->FILE_NAMES->{logoutScript};
			chomp (my $logoutStatus = `perl $logoutScript`);
			if ($logoutStatus =~ /logged out successfully/)
			{
				print qq{"$CurrentUser" $&};
				print $lineFeed.Constants->CONST->{'askfForLogin'}.qq{"$userName" (y/n)?};
				$confirmationChoice = getConfirmationChoice($0,Constants->CONST->{'AccountConfig'}.q(. Please try to login using ).Constants->FILE_NAMES->{loginScript});
				if ($confirmationChoice eq 'y' || $confirmationChoice eq 'Y'){
					$loggedInStat = 0;
					writeConfigurationFile($confFilePath,$confirmationChoice,$dummyString);
					if ($confirmationChoice eq 'y' or $confirmationChoice eq 'Y'){
						createCache();
						print qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed;
						print qq("$userName").' '.Constants->CONST->{'LoginSuccess'}.$lineFeed;
					}
				}else{
					print qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed;
				}
			}
		}else{
			print qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed;
		}
	}
	elsif($sameUser==1){
		print $lineFeed.qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed;
		print qq{User "$CurrentUser" is already logged in. $lineFeed};
	}

}
#*********************************************************************************************************
#Subroutine Name	: writeConfigurationFile. 
#Objective		: To create and write in the configuration file.
#Usage			: writeConfigurationFile($confFilePath,$confirmationChoice,$loggedInStat);
#Added By 		: Abhishek Verma.
#*********************************************************************************************************/

sub writeConfigurationFile{
	my ($confFilePath,$confirmationChoice,$dummyString,$unlinkFlag) = @_;
	$restoreLocation=~s/^\'//;
	$restoreLocation=~s/\'$//;
	open CONF, ">", "$confFilePath" or print "\n Couldn't write into file $confFilePath. Reason: $!\n" and die;
	chmod $filePermission, $confFilePath;
	my $confString  = "USERNAME = $userName".$lineFeed;

	if(($confirmationChoice eq "n" || $confirmationChoice eq "N") ){
        	unlink($pwdPath) if ($unlinkFlag != 0);
       		if($encType eq "PRIVATE") {
                	unlink($pvtPath) if ($unlinkFlag != 0);
        	}

#        $confString .= "PASSWORD = $pwd".$lineFeed.
        #	       "PVTKEY = $pvt".$lineFeed;
	}else{
        	# create password file for schedule jobs
        	my $schPwdPath = $pwdPath."_SCH";
        	copy($pwdPath, $schPwdPath);
        	#create encoded password for sending email
                createEncodeSecondaryFile($pwd, $enPwdPath, $userName);
                $pvt = "";
                # create private key file for schedule jobs
                if($encType eq "PRIVATE") {
                	my $schPvtPath = $pvtPath."_SCH";
                        copy($pvtPath, $schPvtPath);
                        $pvt = $dummyString;
                }
#        	$confString     .=      "PASSWORD = $dummyString".$lineFeed.
#                                        "PVTKEY = $pvt".$lineFeed;
	}
        $confString     .=      "EMAILADDRESS = $emailAddr".$lineFeed.
                                "RESTORELOCATION = $restoreLocation".$lineFeed.
                                "BACKUPLOCATION = $backupHost".$lineFeed.
                                "RESTOREFROM = $restoreHost".$lineFeed.
                                "RETAINLOGS = $ifRetainLogs".$lineFeed.
                                "PROXY = $proxyStr".$lineFeed.
                                "BWTHROTTLE = 100".$lineFeed.
                                "BACKUPTYPE = $backupType";
	print CONF $confString;
	close CONF;

}
#*********************************************************************************************************
#Subroutine Name        : validateAccountUsingEvs
#Objective              : This function will validate user account using EVS. It will run only when curl user verification will fail.
#Usage                  : validateAccountUsingEvs();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub validateAccountUsingEvs{
	$backupHost = `hostname`;
	chomp($backupHost);
	my $accountVerifyUtfFile = getOperationFile($validateOp);
	my $tmp_accountVerifyUtfFile = $accountVerifyUtfFile;
	$tmp_accountVerifyUtfFile =~ s/\'/\'\\''/g;
	my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
	$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;

	my $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_accountVerifyUtfFile\'".$whiteSpace.$errorRedirection;
	my $retType = `$idevsUtilCommand`;
	unlink($accountVerifyUtfFile);
        return $retType;
}
#*********************************************************************************************************
#Subroutine Name        : getAndSetServicePath
#Objective              : This function will take service path input from user and create service path.
#Usage                  : getAndSetServicePath();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getAndSetServicePath{
	my $userServicePath	= shift;
	my $successMessage 	= 0;
	my $oldServiceFlag	= 0;
	my $serviceFileLocation = qq{$userScriptLocation/}.Constants->CONST->{serviceLocation};
	if ($userServicePath eq ''){
		print $lineFeed.Constants->CONST->{'AskServicePath'};
		$userServicePath = getInput();
		if (!$userServicePath){#if user gives no input, then initalize $userServicePath with default service Path.
			$userServicePath = $idriveSerivePath = getAbsolutePath(split('/',"$userScriptLocation/../$appTypeSupport"));
			$oldServiceFlag = 1;
		}else{
			if (validateServiceDir($userServicePath)){
        	        	print Constants->CONST->{'InvalidUsrSerDir'}.$lineFeed;
#	        	        traceLog($lineFeed.Constants->CONST->{'InvalidUsrSerDir'}.$lineFeed, __FILE__, __LINE__);
        	        	exit 0;
        		}
			$successMessage  = 1;
		}
	}
	$successMessage = 1 if (!-e $userServicePath);#if service folder is deleted and .serviceFile exists.
	my $resServicePath = createServicePath(\$userServicePath);
	my $servicePathStatus = $resServicePath eq '' ? Constants->CONST->{'successServicePath'}->('Service path',$userServicePath) : qq(Service path "$userServicePath" exists.);
        if ($resServicePath eq '' || $resServicePath eq 'exists'){ #Create a hidden service path file containing user service path.
        	print $servicePathStatus.$lineFeed if ($successMessage);
		print Constants->CONST->{'noChangeServicePath'}.qq{ "$idriveSerivePath". }.$lineFeed if ($oldServiceFlag);
		writeToFile($serviceFileLocation,$userServicePath);
		changeMode($serviceFileLocation);
		changeMode(qq{$userServicePath});
                $idriveSerivePath = $userServicePath;
		resetGlobalVariables();
        }elsif($resServicePath =~ /Permission\s+denied/i){
		my ($usrInputSerPath) = $userServicePath =~ m{(.+)/([^/]+)$};
		print $lineFeed.Constants->CONST->{'displayUserMessage'}->(Constants->CONST->{'ServiceDirectory'},"\"$usrInputSerPath\"",Constants->CONST->{'noSufficientPermission'}.'. '.Constants->CONST->{'changeServicePath'});
		my $choice = getConfirmationChoice();
		if ($choice =~/^n$/i){
			print $lineFeed.Constants->CONST->{'displayUserMessage'}->(Constants->CONST->{'RecreateServiceDir'},"\"$usrInputSerPath\"","and",lc(substr(Constants->CONST->{'TryAgain'},7))).$lineFeed;
			exit(0);
		}else{
			getAndSetServicePath();
		}
	}else{
		print $lineFeed.Constants->CONST->{'noChangeServicePath'}.qq{ "$idriveSerivePath" $lineFeed};
	}
}
#*********************************************************************************************************
#Subroutine Name        : resetGlobalVariables
#Objective              : This function will reset mentioned global variables which are set by deafult when Header.pl is loaded using require.
#Usage                  : resetGlobalVariables();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub resetGlobalVariables{
	$wrtToErr = "2>$idriveSerivePath/".Constants->CONST->{'tracelog'};
	$usrProfilePath = "$idriveSerivePath/user_profile";
	$cacheDir = "$idriveSerivePath/cache";
	$userTxt = "$cacheDir/user.txt";
	$idevsutilBinaryPath = "$idriveSerivePath/idevsutil";#Path of idevsutil binary#
}

#*********************************************************************************************************
#Subroutine Name        : checkAndCreateServicePath
#Objective              : This function will check & show the old service location and based on user input change the service location.
#Usage                  : checkAndCreateServicePath();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub checkAndCreateServicePath{
	my $serviceFileLocation = "$userScriptLocation/".Constants->CONST->{serviceLocation};
	if (!(-e $serviceFileLocation)){
		       	getAndSetServicePath();
	}else{
		my $usrInputSerPathExists = 0;
		my $userServicePathExists = 0;
	        open(SP,"<$serviceFileLocation");
	        local $\ = '';
	        my $userServicePath = <SP>;
	        Chomp(\$userServicePath);
		my ($usrInputSerPath) = $userServicePath =~ m{(.+)/([^/]+)$};
		$usrInputSerPathExists = validateServiceDir($usrInputSerPath);
		$userServicePathExists = validateServiceDir($userServicePath);
#		print $lineFeed.Constants->CONST->{'SetServiceLocation'}.qq("$userServicePath"$lineFeed);
		if ($usrInputSerPathExists == 0 and $userServicePathExists == 1){
#			print $lineFeed.Constants->CONST->{'SetServiceLocation'}.$userServicePath.$lineFeed;
			getAndSetServicePath($userServicePath);
		}elsif($userServicePath eq ''){
			getAndSetServicePath();
		}elsif($usrInputSerPathExists == 1){
			print $lineFeed.Constants->CONST->{'displayUserMessage'}->(Constants->CONST->{'ServiceDirectory'},"\"$usrInputSerPath\"",Constants->CONST->{'notExists'}.'. '.Constants->CONST->{'changeServicePath'});
			my $choice = getConfirmationChoice();
			Chomp($choice);
			if ($choice =~/^n$/i){
				print $lineFeed.Constants->CONST->{'displayUserMessage'}->(Constants->CONST->{'RecreateServiceDir'},"\"$usrInputSerPath\"","and",lc(substr(Constants->CONST->{'TryAgain'},7))).$lineFeed;
				exit(0);
			}else{
				getAndSetServicePath();
			}
		}else{
			print $lineFeed.Constants->CONST->{'SetServiceLocation'}.qq("$userServicePath"$lineFeed);
		}
	}
}
#*********************************************************************************************************
#Subroutine Name        : validateServiceDir
#Objective              : This function will check if the diretory exists, its writeabel and it has some size. Returns 0 for true and 1 for false.
#Usage                  : validateServiceDir();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub validateServiceDir{
	(-d $_[0] and -w $_[0] and -s $_[0] > 0) ? return 0 : return 1;
}

#*********************************************************************************************************
#Subroutine Name        : editConfigurationFile 
#Objective              : This function will edit the configuration file entry based on the option selected by user among displayed option. 
#Usage                  : editConfigurationFile(USER_DIRECTORY);
#			  USER_DIRECTORY : User directory is passed as a parameter so that path for CONFIGURATION_FILE and default Restore_Data can be formed.
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub editConfigurationFile {
	my ($userDir,$configFilePath,$defRestoreLocation) = @_;
	loadUserData(); #Calling this function to load all the user data before starting the operation.
	while (1){
		print $lineFeed.Constants->CONST->{'editConfig'}.$lineFeed;
		my $configMenu = ['1) Backup Location','2) Restore Location','3) Restore From Location','4) Bandwidth Throttle','5) Backup Type','6) Retain Logs','7) Exit'];
	        displayMenu($configMenu);
        	my $userChoice = getUserOption(Constants->CONST->{'EnterChoice'},0,8,4);
       		if ($userChoice == 7){
			exit(0);
		}
		elsif ($userChoice == 2){#Editing Restore Location
			print Constants->CONST->{'urRestoreLocation'}." \"$restoreLocation\"\. ".Constants->CONST->{'reallyEditQuery'};
			my $choice = getConfirmationChoice();
	                if ($choice =~ /^y$/i){
        			getRestoreLocation($0);
                		my $res = setRestoreLocation($restoreLocation,$defRestoreLocation);
		                if ($res eq ""){
	        	        	$restoreLocation=~s/^\'//;
                	        	$restoreLocation=~s/\'$//;
                        		print qq{Restore Location "$restoreLocation" created successfully }.$lineFeed;
	        	                chmod $filePermission, $restoreLocation;
				}else{#Error handling for wrong restore location provided.
	                		if ($res =~ /mkdir:.*(Permission denied)/i){
                        			print Constants->CONST->{'InvRestoreLoc'}.qq($restoreLocation. $1.\n);
                                		traceLog("$lineFeed Restore Location : $res $lineFeed", __FILE__, __LINE__);
	                	                $restoreLocation=$defRestoreLocation;
        		                        $res = createDefaultRestoreLoc($restoreLocation);
        	        	                if ($res ne ""){
	                        	        	print qq{Restore Location "$restoreLocation" created successfully }.$lineFeed;
                                	        	chmod $filePermission, $restoreLocation;
                                		}
                        		}
               			}
				putParameterValue(\"RESTORELOCATION",\"$restoreLocation",$configFilePath);
			}
		}
		elsif($userChoice == 1){#Editing backup location
			print Constants->CONST->{'urBackupLocation'}." \"$backupHost\"\. ".Constants->CONST->{'reallyEditQuery'}; 
			my $choice = getConfirmationChoice();
			if ($choice =~ /^y$/i){
				getAndSetBackupLocation();
				putParameterValue(\"BACKUPLOCATION",\"$backupHost",$configFilePath);#This function will write the backuplocation to conf file.	
			}
		}
		elsif($userChoice == 3){
			print Constants->CONST->{'urRestoreFrom'}." \"$restoreHost\"\. ".Constants->CONST->{'reallyEditQuery'};
			my $choice = getConfirmationChoice();
			if ($choice =~ /^y$/i){
				getRestoreFromLoc(\$restoreHost);
				putParameterValue(\"RESTOREFROM",\"$restoreHost",$configFilePath);#This function will write the restorelocation to conf file.
			}
		}
		elsif($userChoice == 4){
			print Constants->CONST->{'urBWthrottle'}." \"$bwThrottle\"\. ".Constants->CONST->{'reallyEditQuery'};
			my $choice = getConfirmationChoice();
			if ($choice =~ /^y$/i){
				getAndValidateBWthrottle(4);
				print Constants->CONST->{'bwThrottleSetTo'}." \"$bwThrottle\" ".$lineFeed;
				putParameterValue(\"BWTHROTTLE",\"$bwThrottle",$configFilePath);#This function will write the bwthrottle to conf file
			}
		}
		elsif($userChoice == 5){
			print Constants->CONST->{'urBackupType'}." \"$backupType\"\. ".Constants->CONST->{'reallyEditQuery'};
			my $choice = getConfirmationChoice();
			my $backupTypeSetFlag = 0;
			if ($choice =~ /^y$/i){
				getBackupType(\$backupTypeSetFlag);
				if ($backupTypeSetFlag == 1){
					print Constants->CONST->{'urBackupTypeSetTo'}." \"$backupType\" ".$lineFeed;		
					putParameterValue(\"BACKUPTYPE",\"$backupType",$configFilePath);#This function will write the Backup type to conf file
				}
			}
		}
		elsif($userChoice == 6){
			my $retainLogMess = Constants->CONST->{'retainLogEnabled'};
			my ($toggleRetainLogs,$retainLogFinalMess) = ('NO','Your Retain Logs option is "Disabled"');
			if ($ifRetainLogs =~/^NO$/i){
				$retainLogMess = Constants->CONST->{'retainLogDisabled'};
				$retainLogFinalMess = 'Your Retain Logs option is "Enabled"';
				$toggleRetainLogs = 'YES';
			}
			print $retainLogMess;	
			my $choice = getConfirmationChoice();
			if ($choice =~ /^y$/i){
				print $retainLogFinalMess.$lineFeed;
				$ifRetainLogs = $toggleRetainLogs;
				putParameterValue(\"RETAINLOGS",\"$ifRetainLogs",$configFilePath);
			}
		}
	}
}
#*********************************************************************************************************
#Subroutine Name        : getAndValidateBWthrottle
#Objective              : This function will get and validate the bandwidth taken from the user and initialize it to $bwThrottle global variable.
#Usage                  : getAndValidateBWthrottle();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getAndValidateBWthrottle{
	my $retryCount = shift;
	while($retryCount){
		print $lineFeed.Constants->CONST->{'useBWinput'};
		$bwThrottle = <STDIN>;
		Chomp(\$bwThrottle);
		if ($bwThrottle < 1 or $bwThrottle > 100){
			print $lineFeed.Constants->CONST->{'invalidBWinput'}.$lineFeed;
		}else{
			last;
		}
		$retryCount--;
	}
	if ($retryCount == 0 and ($bwThrottle eq '' or ($bwThrottle < 1 or $bwThrottle > 100))){
		$bwThrottle = 100;
	}
}
#*********************************************************************************************************
#Subroutine Name        : getBackupType
#Objective              : This function will get the backup from user. i.e morror/relative
#Usage                  : getBackupType([$backupTypeSetFlag]);
#			  $backupTypeSetFlag : optional parameter to be used only if you want to know your backupset type is set or not and based on that some operation is to be performed. Otherwise this parameter is not required.
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getBackupType{
	my ($backupTypeSetFlag) = @_;
	print $lineFeed.Constants->CONST->{'selectBackType'}.$lineFeed;
	print Constants->CONST->{'AskMirrorType'}.$lineFeed;
	print Constants->CONST->{'AskRelativeType'}.$lineFeed;
	$menuChoice = undef;
	getMenuChoice();
	if($menuChoice eq 1) {
        	$backupType = "mirror";
		$$backupTypeSetFlag = 1 if (ref($backupTypeSetFlag) eq 'SCALAR');
	}elsif($menuChoice eq 2) {
        	$backupType = "relative";
		$$backupTypeSetFlag = 1 if (ref($backupTypeSetFlag) eq 'SCALAR'); 
	}
}
#*********************************************************************************************************
#Subroutine Name        : getUserOption
#Objective              : This function will get the option displayed on the screen and validate the option with 3 retries in case the option enter in not valid.
#Usage                  : getUserOption($userMessage,$minOption,$maxOption,$maxRetry);
#			  $userMessage : Message which you want to display to the user on the screen.
#			  $minOption   : option 1 less than what is displayed on the screen. Eg: if 0 is the minimum option displayed on screen. then 0 will be the parameter.
#			  $maxOption   : option 1 more than what is displayed on the screen. Eg: if 8 is the maximum option displayed on screen. then 9 will be the parameter.
#			  $maxRetry    : how many time you allow user to input wright input if he inputs wrong value.
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getUserOption{
	my ($userMessage,$minOption,$maxOption,$maxRetry) = @_;#Subroutine parameter receiving.
	my $userChoice = '';#Defining variable $userChoice with blank.
	while ($maxRetry and $userChoice eq ''){
		print $lineFeed.$lineFeed.$userMessage;
		$userChoice = <STDIN>;#Taking user input from <STDIN>
		Chomp(\$userChoice); #removing leading and trailling spaces or tab if present.
		$userChoice =~ s/^0+(\d+)/$1/g;#removing initial zero from the user input for given choice.
		unless (($userChoice > $minOption and $userChoice < $maxOption)){#Validating the user input.
			print $lineFeed.Constants->CONST->{'InvalidChoice'}.Constants->CONST->{'TryAgain'};		
			$userChoice = '';
		}
		$maxRetry--;
	}
	if ($maxRetry == 0 and $userChoice eq ''){
		exit(0);
	}else{
		return $userChoice;
	}
}
#*********************************************************************************************************
#Subroutine Name        : getAndSetBackupLocation 
#Objective              : This function will get the backup location from user and set the backup loaction in idrive account.
#Usage                  : getAndSetBackupLocation();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub getAndSetBackupLocation{
	print $lineFeed.Constants->CONST->{'AskBackupLoc'};
	my $backupHostTemp = getLocationInput("backupHost");
	if($backupHostTemp ne "") {
	        $backupHost = $backupHostTemp;
	}else{
        	$backupHost = `hostname`;
		chomp($backupHost);
        	print Constants->CONST->{'messDefaultBackupLoc'}.qq( "/$backupHost").$lineFeed;
	}
	print Constants->CONST->{'SetBackupLoc'}.$lineFeed;
	if(substr($backupHost, 0, 1) ne "/") {
		$backupHost = "/".$backupHost;
	}
	$ret = setBackupLocation();
	if($ret eq 1|| $ret eq 2) {
		print Constants->CONST->{'BackupLocMsg'}.$whiteSpace."\"$backupHost\"".$lineFeed;
	}
}
#*********************************************************************************************************
#Subroutine Name        : optionsForAccountOperation
#Objective              : This function display menu to choose what changes you want to do in your account, provided if it is set.
#			: Operation like:
#			: -> Setting account freshly
#			: -> Edit your account 
#Usage                  : optionsForAccountOperation();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub optionsForAccountOperation{
	my $userInputCount = 4;
	my $userChoice = '';
	print $lineFeed.Constants->CONST->{'wantTo'}.$lineFeed;
	displayMenu($AccSettingsMenu);
	while ($userInputCount != 0 and $userChoice eq ''){
		print $lineFeed.$lineFeed.Constants->CONST->{'EnterChoice'};
		$userChoice = <STDIN>;
		Chomp(\$userChoice);
		$userChoice =~ s/^0+(\d+)/$1/g;
		if($userChoice !~ /^\d$/ or ($userChoice < 1 or $userChoice > 3)){
        		print $lineFeed.Constants->CONST->{'InvalidChoice'}.$whiteSpace;
			$userChoice = '';
		}elsif($userChoice == 2){
			editConfigurationFile($userDir,$confFilePath,$defRestoreLocation);
		}elsif($userChoice == 3){
			exit(0);
		}
		$userInputCount--;
	}
	if ($userInputCount == 0 and $userChoice eq ''){
		print Constants->CONST->{'pleaseTryAgain'}.$lineFeed;
		exit(0);
	}
}

#*********************************************************************************************************
#Subroutine Name        : viewConfigurationFile
#Objective              : This function will display the configuration file values. So that user can be sure that he wants to re-cofigure or edit the account.
#Usage                  : viewConfigurationFile();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub viewConfigurationFile{
	my @viewConfParameter = qw(BACKUPLOCATION RESTORELOCATION RESTOREFROM BWTHROTTLE BACKUPTYPE RETAINLOGS);
	my %configData = (	BACKUPLOCATION => 'BACKUP LOCATION      :',
				RESTORELOCATION =>'RESTORE LOCATION     :',
				RESTOREFROM => 	  'RESTORE FROM         :',
				BWTHROTTLE  =>    'BANDWIDTH THROTTLE   :',
				BACKUPTYPE  =>    'BACKUP TYPE          :',   
				RETAINLOGS  =>    'RETAIN LOGS          :'
			);
	foreach (@viewConfParameter){
		if (exists $ConfFileValues{$_}){
			print qq($configData{$_} $ConfFileValues{$_} $lineFeed)
		}	
	}
}

#*********************************************************************************************************
#Subroutine Name        : ifLoggedInUser
#Objective              : This function will if the same user is logged in or different user is logged in.
#Usage                  : ifLoggedInUser(PWD_FILE_PATH);
#			: PWD_FILE_PATH : This is password file path.
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub ifLoggedInUser{
	my $TmpPwdPath = shift;
	my $sameUser = 0;
	if( -e $TmpPwdPath and -f $TmpPwdPath) {
        	$loggedInStat = 1;
	        if($CurrentUser eq $userName) {
        	        $sameUser=1;
		}
	}
	return $sameUser;
}
