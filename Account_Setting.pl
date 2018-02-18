#!/usr/bin/perl
##########################################
#Account_setting.pl
#########################################
use FileHandle;
use File::Path;
use File::Copy;
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require Constants;
require 'Header.pl';

my $encType = undef;
my $idevsZip = undef;
my $prevPathIdev = undef;
my $idevsHelpLen = undef;
my $wrtToErr = "2>$idriveServicePath/".Constants->CONST->{'tracelog'};
my $outputDevNull = '1>/dev/null';
my $idevsUtilLink = undef;
my $emailAddr = '';
my $loggedInStat = 0;
my $pvt = undef;
my $zipFilePath = '';
my $scriptPackageName = undef;
my $AccSettingsMenu = ['1) Re-configure your account freshly','2) Edit your account details','3) Exit'];#ArrRef to hold menu
# $appTypeSupport should be ibackup for ibackup and idrive for idrive#
# $appType should be IBackup for ibackup and IDrive for idrive        #

my ($desc, $plan_type, $message, $cnfgstat, $enctype) = ('') x 5;
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

#Validate the EVS binary ZIP file
if(defined($ARGV[0])){
	getCompatibleEvsLink();
	cleanupPrevEvsPackageDir(); #Clean up
	$idevsUtilLink = undef;
	if (!-e $ARGV[0]){
		print $lineFeed.Constants->CONST->{'NotFound'}.$ARGV[0].$lineFeed;
		exit;
	} 
	
	$zipFilePath = getZipPath($ARGV[0]);

	if ($zipFilePath !~ /$scriptPackageName/){
		print $lineFeed.Constants->CONST->{'InvalidZipFile'}.$lineFeed.$evsWebPath.$scriptPackageName.$lineFeed.$lineFeed;
		exit;
	}
}
	
print $lineFeed.Constants->CONST->{'CheckPreq'}.$lineFeed;
my $unzip = checkPrerequisite(\"unzip");
my $curl = checkPrerequisite(\"curl");
my $wget = checkPrerequisite(\"wget");

#Verify hostname
$machineName = `hostname`;
chomp($machineName);
if($machineName eq ''){
	print $lineFeed.Constants->CONST->{'YourHostnameEmpty'}.$lineFeed.$lineFeed;
	exit;	
}

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

$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};
my $userDir = "$usrProfilePath/$userName";
## loading username in global variables
$serverfile = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'serverAddress'};
$pwdPath = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'IDPWD'};
$pvtPath = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'IDPVT'};
$enPwdPath = "$usrProfilePath/$userName/.userInfo/".Constants->CONST->{'IDENPWD'};
$defRestoreLocation = qq($usrProfilePath/$userName/Restore_Data);
my $createdirFlag=1;
if(-e $confFilePath) {
	$createdirFlag=0;
	readConfigurationFile($confFilePath);
} 

my %ConfFileValues = getConfigHashValue();
#get Previous username
my $CurrentUser = getCurrentUser();
my $TmpPwdPath = "$usrProfilePath/$CurrentUser/.userInfo/".Constants->CONST->{'IDPWD'};

# get proxy details
getProxyDetails();
getAccountInfo();

# creating user profile path and job path
print $lineFeed.Constants->CONST->{'CrtUserDir'} if($createdirFlag);
createUserDir();
print $lineFeed.Constants->CONST->{'DirCrtMsg'}.$lineFeed if($mkDirFlag);
my $EvsOn = checkIfEvsWorking($dedup);
if($EvsOn eq 0) {
	getCompatibleEvsBin($dedup);
}
# create encode file for password
createPasswordFiles($pwd,$pwdPath,$userName,$enPwdPath);
setAccount($cnfgstat,\$pvt,$pvtPath);
putParameterValue(\"PROXY",\"$proxyStr",$confFilePath);

unless(-e $serverfile || -s $serverfile) {
        exit if(!(getServerAddr()));
}

if( -e $serverfile) {
        open FILE, "<", $serverfile or (traceLog($lineFeed.Constants->CONST->{'FileOpnErr'}.$serverfile." , Reason:$! $lineFeed", __FILE__, __LINE__) and die);
        chomp($serverAddress = <FILE>);
        close FILE;
} 
else {
        cancelProcess();
}

if(-e $confFilePath && -s $confFilePath) { 
	print $lineFeed.Constants->CONST->{'AlreadyConfig'}.$lineFeed.$lineFeed;
	viewConfigurationFile();
	optionsForAccountOperation();
}

# If option for account operation is selected as 1. Means user wants to set account freshly then below flow will be taken.
my $sameUser = ifLoggedInUser($TmpPwdPath);

#if ($sameUser){
#	print $userName.Constants->CONST->{'AlreadyLoginUser'}.$lineFeed;
#	exit 1;
#}

# Trace Log Entry #
my $curFile = basename(__FILE__);
traceLog("$lineFeed File: $curFile $lineFeed ---------------------------------------- $lineFeed", __FILE__, __LINE__);

loadUserData();
getQuotaForAccountSettings($accountQuota, $quotaUsed);
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
#Subroutine Name         : getMachineArch 
#Objective               : Get the machine architecture. If it is 32, 64 bit or Arm.
#Usage			 : getMachineArch();
#Added By                : Abhishek Verma.
#*****************************************************************************************/
sub getMachineArch{
	my $machineArch = `uname -a`;
	chomp($machineArch);
	if($machineArch =~ /i686|i386/i){
		return 32;
	}elsif($machineArch =~ /x86_64|ia64|amd64/i){
		return 64;
	}elsif($machineArch =~ /arm/i){
		return 'arm';
	}
}
#***************************************************************************************
#Subroutine Name         : getEvsFromUserLocation
#Objective               : Get the evs from the user location provided in argument while running the script.
#Added By                : Abhishek Verma.
#*****************************************************************************************/
sub getEvsFromUserLocation{
	my ($idevsZipCmd,$optionSwitch,$idevsUnzipLoc) = @_;
	my $machineArchName = getMachineArch();
	if ($zipFilePath =~ /$machineArchName\./){
		system("$unzip -o $idevsZipCmd $optionSwitch $idevsUnzipLoc $outputDevNull");
		$idevsZipCmd =~/.*\/(.*?)\.zip/i;
		my $newLoc = $idevsUnzipLoc.'/'.$1;
		my $moveCmd = "mv $newLoc/* $idevsUnzipLoc";
		my $mvResult = system($moveCmd);
	}else{
		print $lineFeed.Constants->CONST->{'EvsMatchError'}.$lineFeed;
		traceLog($lineFeed.$whiteSpace.Constants->CONST->{'EvsMatchError'}.$lineFeed, __FILE__, __LINE__);
		cancelProcess();
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
	my $dedupStatus = shift;
	print $lineFeed.Constants->CONST->{'EvsCmplCheck'}.$lineFeed;
	my ($count,$optionSwitch) = (0,'-d');
	my $idevsUnzipLoc = $idriveServicePath;
        $idevsUnzipLoc =~ s/\'/\'\\''/g;
	$idevsUnzipLoc = "'".$idevsUnzipLoc."'";
	my $idevsZipCmd = $zipFilePath;
        $idevsZipCmd =~ s/\'/\'\\''/g;
        $idevsZipCmd = "'".$idevsZipCmd."'";
	if (defined $ARGV[0]){
		getEvsFromUserLocation($idevsZipCmd,$optionSwitch,$idevsUnzipLoc);
	}
#	exit(print "Exiting after initial unzip\n");
	while(1) {
		# Getting EVS link based on machine
		getCompatibleEvsLink();
		$idevsZipCmd = $idevsZip;
                $idevsZipCmd =~ s/\'/\'\\''/g;
                $idevsZipCmd = "'".$idevsZipCmd."'";
		if (! defined $ARGV[0]){	
			# removing old zip and downloading new zip based on EVS link received
			my $wgetCmd = formWgetCmd(\$proxyOn,$dedupStatus);		
			if(-e $idevsZip) {
				unlink $idevsZip;
			}
			`$wgetCmd`;
			# failure handling for wget command
			my $traceFile = "$idriveServicePath/".Constants->CONST->{'tracelog'};
		        open FILE, "<", $traceFile or die "Couldn't open file: [$traceFile] $!";
			my $wgetRes = join("", <FILE>); 
			close FILE;
			unlink "$idriveServicePath/".Constants->CONST->{'tracelog'};
			traceLog("wget res :$wgetRes", __FILE__, __LINE__);
	
			if($wgetRes =~ /failed:|failed: Connection refused|failed: Connection timed out|Giving up/ || $wgetRes eq "") {
				print $lineFeed.Constants->CONST->{'ProxyErr'}.$lineFeed;
				traceLog("$lineFeed WGET for EVS Bin: $wgetRes $lineFeed", __FILE__, __LINE__);
				cancelProcess();
			} elsif($wgetRes =~ /Unauthorized/) {
				print $lineFeed.Constants->CONST->{'ProxyUserErr'}.$lineFeed;
				traceLog("$lineFeed WGET for EVS Bin: $wgetRes $lineFeed", __FILE__, __LINE__);
				cancelProcess();
			} elsif($wgetRes =~ /Unable to establish/) {
				print $lineFeed.Constants->CONST->{'WgetSslErr'}.$lineFeed;
				traceLog("$lineFeed WGET for EVS Bin: $wgetRes $lineFeed", __FILE__, __LINE__);
				cancelProcess();
			}
			
			#cleanup the unzipped folder before unzipping new zipped file
			if(-e $prevPathIdev) {
				rmtree($prevPathIdev);
			}
			if(!-e $idevsZip) {
				exit;
			}	
			#unzip the zipped file and in case of error exit
			system("$unzip -o $idevsZipCmd $optionSwitch $idevsUnzipLoc $outputDevNull");
		
			if(-s "$idriveServicePath/".Constants->CONST->{'tracelog'}) {
				print $whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed;
				traceLog("$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed Error with unzip.", __FILE__, __LINE__);
				unlink "$idriveServicePath/".Constants->CONST->{'tracelog'};
				cancelProcess();
			}
			unlink "$idriveServicePath/".Constants->CONST->{'tracelog'};
		}
		
		#remove the old evs binary and copy the new one with idevsutil name
		unlink($idevsutilBinaryPath);

		my $PreEvsPath = $prevPathIdev.$idevsutilBinaryName;
		if(-e "$idriveServicePath/$PreEvsPath"){
			system("cp -f '$idriveServicePath/$PreEvsPath' '$idevsutilBinaryPath'");
		} else {
			traceLog($lineFeed.$whiteSpace.Constants->CONST->{'NotFound'}.': "$idriveServicePath/$PreEvsPath"'.$lineFeed, __FILE__, __LINE__);
			next;
		}
	
		# check if new evs binary exist or exit
		if(! -e $idevsutilBinaryPath) {
			print $lineFeed.Constants->CONST->{'TryAgain'}.$lineFeed;
			traceLog($lineFeed.$whiteSpace.Constants->CONST->{'TryAgain'}.$lineFeed, __FILE__, __LINE__);
			cancelProcess();
		}

		# provide permission to EVS binary and execute help command to find if binary is compatible one
		chmod $filePermission, $idevsutilBinaryPath;
		my @idevsHelp = `'$idevsutilBinaryPath' -h 2>/dev/null`;	
		if(50 <= scalar(@idevsHelp)) {
			if(defined $ARGV[0] and $appType eq "IDrive"){
				#Copying both Dedup & Non-Dedup binaries; Changing proper permission
				$copyCmd = "cp -f '$idriveServicePath/$PreEvsPath'* '$idriveServicePath'";
				#print $setPerm = "chmod '$filePermission' $idriveServicePath/idevsutil*";
				system("$copyCmd");
				my $evsFile = ($dedupStatus eq 'on')?"$idriveServicePath/$idevsutilBinaryName":"$idriveServicePath/$idevsutilDedupBinaryName";
				chmod $filePermission, $evsFile;
			}
			print Constants->CONST->{'EvsInstSuccess'}.$lineFeed;
			#Cleaning evs zip file and evs folder
			rmtree("$idriveServicePath/$prevPathIdev");
			unlink $idevsZip;
			my $filesToRemove = "'$idriveServicePath/$appType"."_'*";
			my $rmRes = `rm -rf $filesToRemove`;
			return;
		}
		else{
			if(-e $idevsZip) {
				unlink $idevsZip;
			}	
			#cleanup the unzipped folder before unzipping new zipped file
			if(-e $prevPathIdev) {
				my $dirToRemove = "$idriveServicePath/$prevPathIdev";
				`rm -rf '$dirToRemove'`;
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
			if($menuChoice =~ m/^\d+$/) {
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
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsQnapArmBin'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsQnapArmBin'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsQnapArmBin)
	{
		#try with synology arm evs binary
		$idevsUtilLink = $EvsSynoArmBin;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsSynoArmBin'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsSynoArmBin'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsSynoArmBin)
	{
		#try with netgear arm evs binary
		$idevsUtilLink = $EvsNetgArmBin;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsNetgArmBin'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsNetgArmBin'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsNetgArmBin)
	{
		#try with universal evs binary
		$idevsUtilLink = $EvsUnvBin;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsUnvBin'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsUnvBin'}{'folder'};
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
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsBin32'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsBin32'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsBin32){
		#try with qnap 32 evs binary
		$idevsUtilLink = $EvsQnapBin32;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsQnapBin32'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsQnapBin32'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsQnapBin32){
		#try with synology 32 evs binary
		$idevsUtilLink = $EvsSynoBin32_64;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsSynoBin32_64'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsSynoBin32_64'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsSynoBin32_64){
		#try with netgear 32 evs binary
		$idevsUtilLink = $EvsNetgBin32_64;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsNetgBin32_64'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsNetgBin32_64'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsNetgBin32_64){
		#try with vault evs binary
		$idevsUtilLink = $EvsVaultBin32_64;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsVaultBin32_64'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsVaultBin32_64'}{'folder'};
	}		
	elsif($idevsUtilLink eq $EvsVaultBin32_64){
		#try with linux universal evs binary
		$idevsUtilLink = $EvsUnvBin;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsUnvBin'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsUnvBin'}{'folder'};
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
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsBin64'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsBin64'}{'folder'};
		return;
	}
	elsif($idevsUtilLink eq $EvsBin64){
		#try with qnap 64 evs binary
		$idevsUtilLink = $EvsQnapBin64;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsQnapBin64'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsQnapBin64'}{'folder'};
		return;
    }
	elsif($idevsUtilLink eq $EvsQnapBin64){
		#try with synology 32 evs binary
		$idevsUtilLink = $EvsSynoBin32_64;
		$idevsZip = $idriveServicePath."/".$archiveNames{'EvsSynoBin32_64'}{'zip'};
		$prevPathIdev = $archiveNames{'EvsSynoBin32_64'}{'folder'};
	}
	elsif($idevsUtilLink eq $EvsQnapBin64){
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
	my $uname = getMachineArch();
	
	if($uname =~ /32/) {		# checking for all available 32 bit binaries
		get32bitEvsLink();
		$scriptPackageName = $appType."_Linux_32.zip";
	} 
	elsif($uname =~ /64/) {	# checking for all available 64 bit binaries
		get64bitEvsLink();
		$scriptPackageName = $appType."_Linux_64.zip";
	} 
	elsif($uname =~ /arm/i){			# checking for all available arm binaries
		getArmEvsLink();
		$scriptPackageName = $appType."_Linux_ARM.zip";
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
	my $dedupStatus = $_[1];
	my $copyIdevsUtilLink = $idevsUtilLink;
	
	$copyIdevsUtilLink =~ s/download-options/download-options-dedup/g if($dedupStatus eq 'on');
	my $wgetXmd = undef;
	if(${$_[0]} eq 1) {
		my $proxy = undef;
		if($proxyUsername eq "") {
			$proxy = 'http://'.$proxyIp.':'.$proxyPort;
		} else {
			$proxy = 'http://'.$proxyUsername.':'.$proxyPassword.'@'.$proxyIp.':'.$proxyPort;
		}
		$wgetCmd = "$wget \"--no-check-certificate\" \"--directory-prefix=$idriveServicePath\" \"--tries=2\" -e \"https_proxy = $proxy\" $copyIdevsUtilLink \"--output-file=$idriveServicePath/traceLog.txt\" ";
	} elsif(${$_[0]} eq 0) {
			$wgetCmd = "$wget \"--no-check-certificate\" \"--output-file=$idriveServicePath/traceLog.txt\" \"--directory-prefix=$idriveServicePath\" $copyIdevsUtilLink";
	}
	#traceLog("wget cmd :$wgetCmd", __FILE__, __LINE__);
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
		$curlCmd = "$curl --max-time 15 -s -k -d '$data' '$PATH'";
	}
	my $res = `$curlCmd`;
	if($res =~ /FAILURE/) {
		if($res =~ /passwords do not match|username doesn\'t exist|Username or Password not found|invalid value passed for username|password too short|username too short|password too long|username too long/i) {
			print ucfirst($&).". ".Constants->CONST->{'TryAgain'}."$lineFeed";
#			traceLog("$linefeed $curl failed, Reason: $&", __FILE__, __LINE__);
			cancelProcess();
		}
	} elsif ($res =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
		undef $userName;
		print "$res.\n";
		#traceLog("$linefeed $curl failed, Reason: $res\n", __FILE__, __LINE__);
		cancelProcess();
	}
	
	if(!$res or ($res eq '')) {
		$res = validateAccountUsingEvs($pwd);
		if (!$res){
			print Constants->CONST->{'NetworkErr'}.$lineFeed;
#			traceLog($lineFeed.$whiteSpace.Constants->CONST->{'NetworkErr'}.$lineFeed.$whiteSpace, __FILE__, __LINE__);
			cancelProcess();
		}elsif($res =~ /Failed to connect\. Verify proxy details/){
			 print Constants->CONST->{'ProxyUserErr'}.$lineFeed;
#			 traceLog($lineFeed.$whiteSpace.Constants->CONST->{'ProxyUserErr'}.$lineFeed.$whiteSpace, __FILE__, __LINE__);
			 cancelProcess();
		}
	} elsif( $res =~ /Unauthorized/) {
		$res = validateAccountUsingEvs($pwd);
		if ($res =~ /Unauthorized/){
			print Constants->CONST->{'ProxyUserErr'}.$lineFeed;
			#traceLog($lineFeed.$whiteSpace.Constants->CONST->{'ProxyUserErr'}.$lineFeed.$whiteSpace, __FILE__, __LINE__);
			cancelProcess();
		}
	}
	if($res =~ /FAILURE/) {
		if($res =~ /passwords do not match|username doesn\'t exist|Username or Password not found|invalid value passed for username|password too short|username too short|password too long|username too long/i) {
			print ucfirst($&).". ".Constants->CONST->{'TryAgain'}."$lineFeed";
#			traceLog("$linefeed $curl failed, Reason: $&", __FILE__, __LINE__);
			cancelProcess();
		}
	} elsif ($res =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
		undef $userName;
		#traceLog("$linefeed $curl failed, Reason: $res\n", __FILE__, __LINE__);
		cancelProcess();
	}	

	my %evsLoginHashOutput = parseXMLOutput(\$res);
	chomp(%evsLoginHashOutput);
	$encType = $evsLoginHashOutput{"enctype"} ne "" ? $evsLoginHashOutput{"enctype"} : $evsLoginHashOutput{"configtype"};
	$plan_type = $evsLoginHashOutput{"plan_type"};
	$message = $evsLoginHashOutput{"message"};
	$cnfgstat = $evsLoginHashOutput{"cnfgstat"} ne "" ? $evsLoginHashOutput{"cnfgstat"} : $evsLoginHashOutput{"configstatus"};
	$desc = $evsLoginHashOutput{"desc"};
	$accountQuota = $evsLoginHashOutput{"quota"};
	$quotaUsed = $evsLoginHashOutput{"quota_used"};
	$dedup = $evsLoginHashOutput{"dedup"} if($appType eq "IDrive");
	$serverAddress = $evsLoginHashOutput{"evssrvrip"};
	
	#Commented by Senthil - Nov 27, 2017 - for "Required param 'password' not passed"  issue	
	#getServerAddr($evsLoginHashOutput{evssrvrip});
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
	my $createDirUtfFile = getOperationFile(Constants->CONST->{'CreateDirOp'}, $encType);
	chomp($createDirUtfFile);
	$createDirUtfFile =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$createDirUtfFile."'".$whiteSpace.$errorRedirection;
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
		connectionIssueExit($commandOutput);
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
		print "\n ".$desc." \n";
		traceLog($desc, __FILE__, __LINE__);
		cancelProcess();
	}
	
	if($plan_type eq "Mobile-Only") {
		print "\n $desc\n";
		traceLog("\n $desc", __FILE__, __LINE__);
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
	my $pvtVerifyUtfFile = getOperationFile(Constants->CONST->{'validatePvtKeyOp'});
	
	my $tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
	$tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;
	my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
	$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
	my $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
	my $retType = `$idevsUtilCommand`;
	unlink($pvtVerifyUtfFile);
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
		$pvtVerifyUtfFile = getOperationFile(Constants->CONST->{'VerifyPvtOp'});
		$tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
		$tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;
		
		$tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
		$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
		
		$idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
		$retType = `$idevsUtilCommand`;
		unlink($pvtVerifyUtfFile);
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
		print Constants->CONST->{'SetRestoreFromLoc'}.$lineFeed;		
		if(substr($restoreHost, 0, 1) ne "/") {
			$restoreHost = "/".$restoreHost;
		}
		
		getItemStatusFileSet($restoreHost);
		my $itemStatUtfFile = getOperationFile(Constants->CONST->{'ItemStatOp'},$validateRestoreFromFile);
		chomp($itemStatUtfFile);
		$itemStatUtfFile =~ s/\'/\'\\''/g;
		
		$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$itemStatUtfFile."'".$whiteSpace.$errorRedirection;
		my $commandOutput = `$idevsutilCommandLine`;
		unlink $itemStatUtfFile;
		unlink $validateRestoreFromFile;
		
		if($commandOutput =~ /No such file or directory|directory exists in trash/) {
			$restoreHost='';
			print $lineFeed.Constants->CONST->{'NoFileEvsMsg'};
			print $lineFeed.Constants->CONST->{'RstFromGuidMsg'}.$lineFeed;
		} else {
			last;
		}
		$locationInputCount++;
	}
	if (-s "$usrProfilePath/$userName/error.txt" > 0){
		connectionIssueExit("$usrProfilePath/$userName/error.txt");
	}else{
		if($restoreHost ne "") {
			print Constants->CONST->{'RestoreLocMsg'}.$whiteSpace."\"$restoreHost\"".$lineFeed;
		}
	}
}
#**********************************************************************************************************
# Subroutine Name         : setConfDetails
# Objective               : This subroutine configures the user account if not set and asks user details 
#							which are required for setting the account.
# Added By                : Dhritikana
# Modified By		  	  : Abhishek Verma-12/01/2016-code added to show proper message, if restore location exists.
# 			   				Abhishek Verma-12/02/2016-code added to remove trailing and leading spaces from email id.
#*********************************************************************************************************/
sub setConfDetails 
{
	# For Private Account Verifies the Private Encryption Key
	if($cnfgstat eq "SET") {
		if($encType eq "PRIVATE") {
			print $lineFeed.Constants->CONST->{'AskPvtSetAcc'};
			system('stty','-echo');
			$pvt = getInput();
			checkInput(\$pvt,$lineFeed);
			system('stty','echo');
			createEncodeFile($pvt, $pvtPath);
			verifyPvtKey($dedup);
		}
	}
	
	# get and set user backup location
	if ($dedup eq 'off'){
		getAndSetBackupLocation();
	}else{
		checkDeviceID();
	}
	
	# get restore location from user.
	my $defaultRestoreLocation = $restoreLocation;
	getRestoreLocation($0);
	# check restore location. Here we check if given restore location exists or not and permission is there or not based on that we need to do certain task.
	my $restoreLocStatus = checkRestoreLocation($restoreLocation);
	my $newRestoreLocStatus = undef;
	# set restore location
	if ($restoreLocStatus == 0){#Given restore location doesnot exists.
		$newRestoreLocStatus = setRestoreLocation($restoreLocation,$defRestoreLocation);
	}elsif($restoreLocStatus == 1){
		print qq(Restore Location "$restoreLocation" exists.$lineFeed);
                print Constants->CONST->{'RestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
	}elsif($restoreLocStatus == 2){#Given restore location exists but does not have write permission.
		$restoreLocation = $defaultRestoreLocation;
		$newRestoreLocStatus = createDefaultRestoreLoc($restoreLocation);
	}
	if($restoreLocStatus == 0 || $restoreLocStatus == 2){
		if ($newRestoreLocStatus eq ""){
			$restoreLocation=~s/^\'//;
			$restoreLocation=~s/\'$//;
			print Constants->CONST->{'RestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
			chmod $filePermission, $restoreLocation;
		}else{
			if ($newRestoreLocStatus =~ /mkdir:.*(Permission denied)/i){
				print Constants->CONST->{'InvRestoreLoc'}.qq(: $restoreLocation. $1.\n);
				traceLog("$lineFeed Restore Location : $res $lineFeed", __FILE__, __LINE__);
				$restoreLocation=$defRestoreLocation;
				$newRestoreLocStatus = createDefaultRestoreLoc($restoreLocation);
				if ($newRestoreLocStatus ne ""){
					print Constants->CONST->{'RestoreLoc'}.$whiteSpace."\"$restoreLocation\"".$lineFeed;
					chmod $filePermission, $restoreLocation;
				}
			}
		}
	}
	
	# get and set user restore from location
	if ($dedup eq 'off'){
		getRestoreFromLoc(\$restoreHost);
	}elsif($dedup eq 'on'){
		if($restoreHost eq ""){
			$restoreHost = $backupHost;
		} 
		#print $lineFeed.Constants->CONST->{'RestoreLocMsg'}.$whiteSpace.'"'.(split('#',$restoreHost))[1].'"'.$lineFeed;
		my $restLoc = (($dedup eq 'on') and $restoreHost =~ /\#/) ? (split ('#',$restoreHost))[1] : $restoreHost;
		print $lineFeed.Constants->CONST->{'RestoreLocMsg'}.$whiteSpace.'"'.$restLoc.'"'.$lineFeed;
	}
	
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
	if ($dedup eq 'off'){
		getBackupType();
	}else{
		$backupType = "mirror";
	}
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
	if (! -e $backupsetFilePath){
		open(FH, ">", $backupsetFilePath) or (print $! and exit(1));	
		chmod $filePermission, $backupsetFilePath;
	}
	print Constants->CONST->{'LocationString'}.$backupsetFilePath.$lineFeed;

	print $lineFeed.Constants->CONST->{'SetRestoreList'}.$lineFeed;
	if (! -e $RestoresetFile){	
		open(FH, ">", $RestoresetFile)	or (print $! and exit(1)); 
		chmod $filePermission, $RestoresetFile;
	}
	print Constants->CONST->{'LocationString'}.$RestoresetFile.$lineFeed;

	print $lineFeed.Constants->CONST->{'SetBackupListSch'}.$lineFeed;
        if (! -e $backupsetSchFilePath){
                open(FH, ">", $backupsetSchFilePath) or (print $! and exit(1));
                chmod $filePermission, $backupsetSchFilePath;
        }
        print Constants->CONST->{'LocationString'}.$backupsetSchFilePath.$lineFeed;
	
	print $lineFeed.Constants->CONST->{'SetRestoreListSch'}.$lineFeed;
        if (! -e $RestoresetSchFile){
                open(FH, ">", $RestoresetSchFile)  or (print $! and exit(1));
                chmod $filePermission, $RestoresetSchFile;
        }
        print Constants->CONST->{'LocationString'}.$RestoresetSchFile.$lineFeed;

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
			checkAndUpdateClientRecord($userName,$pwd);
			print qq("$userName" ).Constants->CONST->{'LoginSuccess'}.$lineFeed; 
		}
	}
	# One user already logged in. And other account is configured and trying to do login.
	if ($loggedInStat == 1 and $CurrentUser ne '' and  $sameUser==0){
		my $usrProfileDir = "$usrProfilePath/$CurrentUser";
		$ManualBackupPidpath = $usrProfileDir."/Backup/Manual/pid.txt";
		$ManualRestorePidpath = $usrProfileDir."/Restore/Manual/pid.txt";
		print $lineFeed.qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed;
		if ((!-e $ManualBackupPidpath) and (!-e $ManualRestorePidpath)){			
			print $lineFeed.Constants->CONST->{'askfForLogin'}.qq{"$userName" (y/n)?};
                        my $confirmationChoiceLogin = getConfirmationChoice($0,Constants->CONST->{'AccountConfig'}.q(. Please try to login using ).Constants->FILE_NAMES->{loginScript});
			if ($confirmationChoiceLogin =~ /^y$/i){
				print $lineFeed.qq{"$CurrentUser" }.Constants->CONST->{'userLoggedIn'};
				$confirmationChoice = getConfirmationChoice($0,Constants->CONST->{'AccountConfig'}.q(. Please try to login using ).Constants->FILE_NAMES->{loginScript});
				if ($confirmationChoice eq 'y' || $confirmationChoice eq 'Y'){
					my $logoutScript = "$userScriptLocation/".Constants->FILE_NAMES->{logoutScript};
					chomp (my $logoutStatus = `perl '$logoutScript'`);
					if ($logoutStatus =~ /logged out successfully/)
					{
						print qq{"$CurrentUser" $& $lineFeed};
						$loggedInStat = 0;
						writeConfigurationFile($confFilePath,$confirmationChoice,$dummyString);
						createCache();
						checkAndUpdateClientRecord($userName,$pwd);
						#print qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed; Commented by Senthil for Snigdha_2.11_3_
						print qq("$userName").' '.Constants->CONST->{'LoginSuccess'}.$lineFeed;
					} else {
						print qq{"$logoutStatus"};
					}
				}else{
					print qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed;
				}
			}
			#else{
			#	print qq("$userName").' '.Constants->CONST->{'AccountConfig'}.$lineFeed;
			#} Commented by Senthil for Snigdha_2.11_3_
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
	}else{
		$pvt = "";
		# create private key file for schedule jobs
		if($encType eq "PRIVATE") {
			my $schPvtPath = $pvtPath."_SCH";
			copy($pvtPath, $schPvtPath);
			chmod $filePermission,$schPvtPath;
			$pvt = $dummyString;
		}
        
	}
	$confString	.=	"EMAILADDRESS = $emailAddr".$lineFeed.
					"RESTORELOCATION = $restoreLocation".$lineFeed.
					"BACKUPLOCATION = $backupHost".$lineFeed.
					"RESTOREFROM = $restoreHost".$lineFeed.
					"RETAINLOGS = $ifRetainLogs".$lineFeed.
					"PROXY = $proxyStr".$lineFeed.
					"BWTHROTTLE = 100".$lineFeed.
					"BACKUPTYPE = $backupType".$lineFeed.
					"DEDUP = $dedup";
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
	my $EvsOn = checkIfEvsWorking($dedup);
	if($EvsOn eq 0) {
		getCompatibleEvsBin($dedup);
	}
	$backupHost = `hostname`;
	chomp($backupHost);
	my $accountVerifyUtfFile = getOperationFile(Constants->CONST->{'ValidateOp'},$_[0]);
	my $tmp_accountVerifyUtfFile = $accountVerifyUtfFile;
	$tmp_accountVerifyUtfFile =~ s/\'/\'\\''/g;
	my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
	$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;

	my $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_accountVerifyUtfFile\'".$whiteSpace.$errorRedirection;
	my $retType = `$idevsUtilCommand`;
	if($retType =~ /Required param|PROTOCOL VERSION MISMATCH/i and $dedup eq "off"){
		$dedup = "on";
		$retType = validateAccountUsingEvs($_[0]);		
	}
	else{
		unlink($accountVerifyUtfFile);
	}
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
			$userServicePath = $idriveServicePath = getAbsolutePath(split('/',"$userScriptLocation/../$appTypeSupport"));
			$oldServiceFlag = 1;
		}else{
			my $retVal = validateServiceDir("$userServicePath");
			if ($retVal){
				if($retVal == 1){
					print Constants->CONST->{'InvalidUsrSerDir'}.$lineFeed 
				}
				else{
					print Constants->CONST->{'noSufficientPermission'}.$lineFeed 
				}
    	        	exit 0;
    		}
			$successMessage  = 1;
		}
	}
	$successMessage = 1 if (!-e $userServicePath);#if service folder is deleted and .serviceFile exists.
	my $resServicePath = createServicePath(\$userServicePath);
	my $servicePathStatus = $resServicePath eq '' ? Constants->CONST->{'successServicePath'}->('Service directory',$userServicePath) : qq(Service path "$userServicePath" exists.);
    if ($resServicePath eq '' || $resServicePath eq 'exists'){ #Create a hidden service path file containing user service path.
        print $servicePathStatus.$lineFeed if ($successMessage);
		print Constants->CONST->{'noChangeServicePath'}.qq{ "$idriveServicePath". }.$lineFeed if ($oldServiceFlag);
		writeToFile($serviceFileLocation,$userServicePath);
		changeMode($serviceFileLocation);
		changeMode(qq{$userServicePath});
        $idriveServicePath = $userServicePath;
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
		print $lineFeed.Constants->CONST->{'noChangeServicePath'}.qq{ "$idriveServicePath" $lineFeed};
	}
}
#*********************************************************************************************************
#Subroutine Name        : resetGlobalVariables
#Objective              : This function will reset mentioned global variables which are set by deafult when Header.pl is loaded using require.
#Usage                  : resetGlobalVariables();
#Added By               : Abhishek Verma.
#*********************************************************************************************************/
sub resetGlobalVariables{
	$wrtToErr = "2>$idriveServicePath/".Constants->CONST->{'tracelog'};
	$usrProfilePath = "$idriveServicePath/user_profile";
	$cacheDir = "$idriveServicePath/cache";
	$userTxt = "$cacheDir/user.txt";
	$idevsutilBinaryPath = "$idriveServicePath/idevsutil";#Path of idevsutil binary#
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
		if($userServicePath eq ''){
			getAndSetServicePath();
		}
		else{
			my ($usrInputSerPath) = $userServicePath =~ m{(.+)/([^/]+)$};
			$userServicePathExists = validateServiceDir("$userServicePath");
			if($userServicePathExists == 1){ 
				$usrInputSerPathExists = validateServiceDir("$usrInputSerPath");
			}
			if ($usrInputSerPathExists == 0 and $userServicePathExists == 1){
				getAndSetServicePath($userServicePath);
			}
			elsif($usrInputSerPathExists){
				#$retErr = ($usrInputSerPathExists == 1) ? Constants->CONST->{'notExists'} : Constants->CONST->{'noSufficientPermission'};
				if($usrInputSerPathExists == 1){
					print $lineFeed.Constants->CONST->{'displayUserMessage'}->(Constants->CONST->{'ServiceDirectory'},"\"$usrInputSerPath\"",Constants->CONST->{'notExists'}.'. '.Constants->CONST->{'changeServicePath'});
					my $choice = getConfirmationChoice();
					Chomp($choice);
					if ($choice =~/^n$/i){
						print $lineFeed.Constants->CONST->{'displayUserMessage'}->(Constants->CONST->{'RecreateServiceDir'},"\"$usrInputSerPath\"","and",lc(substr(Constants->CONST->{'TryAgain'},7))).$lineFeed;
						exit(0);
					}else{
						getAndSetServicePath();
					}					
				} else {
					print $lineFeed.Constants->CONST->{'displayUserMessage'}->(Constants->CONST->{'ServiceDirectory'},"\"$usrInputSerPath\"",Constants->CONST->{'noSufficientPermission'}.'. '.Constants->CONST->{'providePermission'}).$lineFeed.$lineFeed;
					exit(0);
				}
			}
			else{
				print $lineFeed.Constants->CONST->{'SetServiceLocation'}.qq("$userServicePath"$lineFeed);
			}
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
	(-d $_[0]) ? ((-w $_[0]) ? return 0 : return 2) : return 1;
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
	while (1){
		readConfigurationFile($confFilePath);
		getConfigHashValue();
		loadUserData(); #Calling this function to load all the user data before starting the operation.
		print $lineFeed.Constants->CONST->{'editConfig'}.$lineFeed;
		my $maxChoice = 8;
		my $configMenu = ['1) Backup Location','2) Restore Location','3) Restore From Location','4) Bandwidth Throttle','5) Backup Type','6) Retain Logs','7) Exit'];
		if ($dedup eq 'on'){
			$configMenu = ['1) Backup Location','2) Restore Location','3) Restore From Location','4) Bandwidth Throttle','5) Retain Logs','6) Exit'];
			$maxChoice = 7;	
		}
	        displayMenu($configMenu);
        	my $userChoice = getUserOption(Constants->CONST->{'EnterChoice'},0,$maxChoice,4);
		$userChoice = (($dedup eq 'on') and ($userChoice >= 5)) ? $userChoice+1 : $userChoice; 
       		if ($userChoice == 7){
			exit(0);
		}
		elsif ($userChoice == 2){#Editing Restore Location
			askRestoreLocation('',1);
		}
		elsif($userChoice == 1){#Editing backup location
			my $backLocation = (($dedup eq 'on') and $backupHost =~ /\#/) ? (split ('#',$backupHost))[1] : $backupHost;
			if ($dedup eq 'off'){
				print Constants->CONST->{'urBackupLocation'}." \"$backLocation\"\. ".Constants->CONST->{'reallyEditQuery'}; 
				my $choice = getConfirmationChoice();
				if ($choice =~ /^y$/i){
					getAndSetBackupLocation();
				}
			}elsif($dedup eq 'on'){	
				$isSameDeviceID = 0;
				$isSameDeviceID = 1 if($backupHost ne "" and $backupHost eq $restoreHost);
				checkDeviceID();
				if($isSameDeviceID){
					$restoreHost = $backupHost;
					putParameterValue(\"RESTOREFROM",\"$restoreHost",$configFilePath);#This function will update  restore location to conf file. Added do keep the same Nick name if device ids are same.
				}
			}
			putParameterValue(\"BACKUPLOCATION",\"$backupHost",$configFilePath);#This function will write the backuplocation to conf file.
		}
		elsif($userChoice == 3){
			my $restLoc = (($dedup eq 'on') and $restoreHost =~ /\#/) ? (split ('#',$restoreHost))[1] : $restoreHost;
			if ($dedup eq 'off'){
				print Constants->CONST->{'urRestoreFrom'}." \"$restLoc\"\. ".Constants->CONST->{'reallyEditQuery'};
				my $choice = getConfirmationChoice();
				if ($choice =~ /^y$/i){
					getRestoreFromLoc(\$restoreHost);
				}
			}else{
				print $lineFeed.Constants->CONST->{'LoadingAccDetails'};
				my %evsDeviceHashOutput = getDeviceList();
				my $totalElements = keys %evsDeviceHashOutput;
				if ($totalElements == 1 or $totalElements == 0){
					print $lineFeed.Constants->CONST->{'restoreFromLocationNotFound'}.$lineFeed;
					cancelProcess();
				}
				else{
					print $lineFeed.Constants->CONST->{'selectRestoreFromLoc'}.$lineFeed;
					my @devicesToLink = displayDeviceList(\%evsDeviceHashOutput,\@columnNames);
					print $lineFeed;
					my $userChoice = (getUserMenuChoice(scalar(@devicesToLink),4) - 1);
					$restoreHost = $deviceIdPrefix.$devicesToLink[$userChoice]->{device_id}.$deviceIdPostfix.'#'.$devicesToLink[$userChoice]->{nick_name};
					print $lineFeed.Constants->CONST->{'RestoreLocMsg'}.$whiteSpace.'"'.$devicesToLink[$userChoice]->{nick_name}.'"'.$lineFeed;
				}
			}
			putParameterValue(\"RESTOREFROM",\"$restoreHost",$configFilePath);#This function will write the restorelocation to conf file.
		}
		elsif($userChoice == 4){
			print Constants->CONST->{'urBWthrottle'}." \"$bwThrottle%\"\. ".Constants->CONST->{'reallyEditQuery'};
			my $choice = getConfirmationChoice();
			if ($choice =~ /^y$/i){
				getAndValidateBWthrottle(4);
				print Constants->CONST->{'bwThrottleSetTo'}." \"$bwThrottle%\" ".$lineFeed;
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
					#print Constants->CONST->{'urBackupTypeSetTo'}." \"$backupType\" ".$lineFeed;		
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
		if ($bwThrottle < 1 or $bwThrottle > 100 or $bwThrottle =~ /\d+\.\d+/){
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
	if($menuChoice == 1) {
        $backupType = "mirror";
		$$backupTypeSetFlag = 1 if (ref($backupTypeSetFlag) eq 'SCALAR');
	}elsif($menuChoice == 2) {
        $backupType = "relative";
		$$backupTypeSetFlag = 1 if (ref($backupTypeSetFlag) eq 'SCALAR'); 
	}
	print Constants->CONST->{'urBackupType'}.' '.ucfirst($backupType).$lineFeed; 
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
	print $lineFeed.$lineFeed.Constants->CONST->{'AskBackupLoc'}.': ';
	my $backupHostTemp = getLocationInput();
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
		$restoreHost=$backupHost;	
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
	@viewConfParameter = qw(BACKUPLOCATION RESTORELOCATION RESTOREFROM BWTHROTTLE RETAINLOGS) if ($dedup eq 'on');
	my %configData = (	BACKUPLOCATION => 'BACKUP LOCATION      :',
				RESTORELOCATION =>'RESTORE LOCATION     :',
				RESTOREFROM => 	  'RESTORE FROM         :',
				BWTHROTTLE  =>    'BANDWIDTH THROTTLE   :',
				BACKUPTYPE  =>    'BACKUP TYPE          :',   
				RETAINLOGS  =>    'RETAIN LOGS          :'
			);
	foreach (@viewConfParameter){
		if (exists $ConfFileValues{$_}){
			my $configFileData = (($dedup eq 'on') and $ConfFileValues{$_} =~ /\#/) ? (split('#',$ConfFileValues{$_}))[1] : $ConfFileValues{$_};
			$configFileData .='%' if ($configData{$_} =~ /BANDWIDTH THROTTLE/);
			print qq($configData{$_} $configFileData $lineFeed);
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
#*********************************************************************************************************
#Subroutine Name        : getItemStatusFileSet
#Objective              : This function will create item status set file with the passed item name
#Added By               : Deepak Chaurasia
#*********************************************************************************************************/
sub getItemStatusFileSet{
	if(!open(RESTORELISTNEW, ">", $validateRestoreFromFile)){
		traceLog(Constants->CONST->{'FileOpnErr'}." $validateRestoreFromFile , Reason: $!\n", __FILE__, __LINE__);
		return 0;
	}
	print RESTORELISTNEW $restoreHost.$lineFeed;
	close(RESTORELISTNEW);
}
#*********************************************************************************************************
#Subroutine Name        : cleanupPrevEvsPackageDir
#Objective              : This function will cleanup the previous Evs Package ZIP & Directories
#Added By               : Senthil Pandian
#*********************************************************************************************************/
sub cleanupPrevEvsPackageDir{
	$prevEvsPackagePath = $scriptPackageName;
	$prevEvsPackagePath =~ s/.zip//g;
	if($prevEvsPackagePath eq '' or (!defined $prevEvsPackagePath)){
		return;
	}
	$prevPath = "$idriveServicePath/$prevEvsPackagePath";

	if($prevPath ne '/' and -e $prevPath){
		`rm -rf '$prevPath'`; #Removing the extracted directory if it is there.
	}
	foreach $key (keys %archiveNames)
	{
		# do whatever you want with $key and $value here ...
		$value 			 = $archiveNames{$key}{'folder'};
		$prevEvsPackageDir = "$idriveServicePath/$value";
		if(-e $prevEvsPackageDir and $value ne ''){
			if($prevEvsPackageDir ne '/'){
				`rm -rf '$prevEvsPackageDir'`;
			}
		}	  
	}
}
