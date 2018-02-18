#!/usr/bin/perl
####################################################################
#Script Name : Login.pl
#####################################################################
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require 'Header.pl';
use File::Path;
use File::Copy;
#use Constants 'CONST';
require Constants;

#Configuration File Path#
system("clear");
my $isPrivate = 0;
my $encType = undef;
my $pvtKey = undef;
my $pvtKeyField = undef;
my $accDetailsCheck = 0;
headerDisplay($0);
my $CurrentUser = getCurrentUser();
if ($CurrentUser ne ""){
	print $lineFeed."User \"$CurrentUser\" ".Constants->CONST->{'alreadyLoginUser'}.'. '.Constants->CONST->{'logoutRequest'}." and try again.".$lineFeed.$lineFeed;
        exit 1;
}
print $lineFeed.Constants->CONST->{'displayUserMessage'}->('Enter your',$appType,'username: '); 
$userName = <STDIN>;
$userName =~ s/^[\s\t]+//;
$userName =~ s/[\s\t]+$//;
checkInput(\$userName);
unless (validateUserName($userName)){
      print Constants->CONST->{'InvalidUserPattern'}.$lineFeed;
      exit 0;
}
my $userDir = "$usrProfilePath/$userName";
$confFilePath = "$userDir/".Constants->CONST->{'configurationFile'};
checkIfDirExits($confFilePath);
if (! checkIfEvsWorking($dedup)){
        print Constants->CONST->{'EvsProblem'}.$lineFeed;
        exit 0;
}
if(getAccountConfStatus($confFilePath)){
	exit(0);
}
#Get Previous username
#my $CurrentUser = getCurrentUser();
my $TmpPwdPath = "$usrProfilePath/$CurrentUser/.userInfo/".Constants->CONST->{'IDPWD'};

if( -e $TmpPwdPath and -f $TmpPwdPath) {
	if($CurrentUser ne $userName) {
		print "User \"$CurrentUser\" ".Constants->CONST->{'alreadyLoginUser'}.'. '.Constants->CONST->{'logoutRequest'}." and try again.".$lineFeed;
		exit 1;
	}elsif($CurrentUser eq $userName) {
		getParameterValue(\"PVTKEY", \$hashParameters{PVTKEY});
		my $pvtKeyField = $hashParameters{PVTKEY};
		
		if($pvtKeyField ne "") {
			if(-e $pvtPath and -s $pvtPath) {
			#	print Constants->CONST->{'LoginAlready'}.$lineFeed;
				print $lineFeed.Constants->CONST->{'displayUserMessage'}->("\"$userName\"",Constants->CONST->{'alreadyLoginUser'} ).$lineFeed;
				putParameterValue(\"USERNAME", \$userName, $confFilePath);
				exit 1;
			} 
		} else {
#				print Constants->CONST->{'LoginAlready'}.$lineFeed;
				print $lineFeed.Constants->CONST->{'displayUserMessage'}->("\"$userName\"",Constants->CONST->{'alreadyLoginUser'}).$lineFeed;
				putParameterValue(\"USERNAME", \$userName, $confFilePath);
				exit 1;
		}
	}
}

# Trace Log Entry #
my $curFile = basename(__FILE__);
traceLog("$lineFeed File: $curFile $lineFeed---------------------------------------- $lineFeed", __FILE__, __LINE__);
print Constants->CONST->{'displayUserMessage'}->('Enter your',$appType,'password: '); 
system('stty','-echo');
$password = <STDIN>;
system('stty','echo');
chomp($password);
$password =~ s/^\s+|\s+$//g;
unless (validatePassword($password)){
	print $lineFeed.Constants->CONST->{'InvalidPassPattern'}.$lineFeed;
      	exit 0;
}
CHECK_ACC_DETAILS:
getAccountInfo();
my $serverAddress = verifyAndLoadServerAddr();
if ($serverAddress == 0){
	cancelProcess();
}
createPasswordFiles($password,$pwdPath,$userName,$enPwdPath);
setAccount($cnfgstat,\$pvt,$pvtPath);
if ($message eq 'SUCCESS'){
	getPvtKey();
    verifyAccount();
	checkAndUpdateClientRecord($userName,$password);
}
getQuotaForAccountSettings($accountQuota, $quotaUsed);
#****************************************************************************************************
# Subroutine Name         : validateAccount.
# Objective               : This subroutine validates an user account if the account is
#							private or default. It configues the previously not set Account.
# Added By                : 
#*****************************************************************************************************/
sub validateAccount
{	
#	print $lineFeed.$lineFeed.Constants->CONST->{'verifyAccount'}.$lineFeed;
	my $validateUtf8File = getOperationFile(Constants->CONST->{'ValidateOp'});
	chomp($validateUtf8File);

	#log API in trace file as well
	traceLog("$lineFeed validateAccount: ", __FILE__, __LINE__);
	$validateUtf8File =~ s/\'/\'\\''/g;
	
	my $idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$validateUtf8File."'".$whiteSpace.$errorRedirection;
	my $commandOutput = `$idevsutilCommandLine`;
	traceLog("$lineFeed $commandOutput $lineFeed", __FILE__, __LINE__);
	#print $tHandle "$lineFeed $commandOutput $lineFeed";
	unlink $validateUtf8File;

	if($commandOutput =~ m/configstatus\=\"NOT SET\"/i) { 
		print $lineFeed.Constants->CONST->{'AccCongiguringMsg'}.$lineFeed;
		configureAccount();
	}
	elsif($commandOutput =~ m/configtype\=\"PRIVATE\"/i) {
		#print CONST->{'PvtAccTypeMsg'}.$lineFeed;
		print $lineFeed.Constants->CONST->{'AskPvt'};
		system('stty','-echo');
		$pvtKey = <STDIN>;
		system('stty','echo');
		chomp($pvtKey);
		$pvtKey  =~ s/^\s+|\s+$//g;
		$isPrivate = 1;
	}
	elsif($commandOutput =~ m/configtype\=\"DEFAULT\"/i) {
		$encType = $defaultEncryptionKey;
		if (-e $pvtPath){
			unlink($pvtPath); #To handle the case if user Account reset to default if it was a private account.
			unlink($pvtPath.'_SCH');
		}
	}
	elsif($commandOutput =~ m/desc\=\"Invalid username or Password\"|desc\=\"Parameter 'password' too short\"|desc=\"Required param 'password' not passed\"/) {
		print $lineFeed.Constants->CONST->{'InvalidUnamePwd'}.$lineFeed;
		if(-e $enPwdPath){
			unlink($enPwdPath);
		}
		if(-e $pwdPath){		
			unlink($pwdPath);
		}
		exit;
	} elsif($commandOutput =~ m/bad response from proxy/) {
		if ($reloginStatus ne 'on'){
			if ($accDetailsCheck == 1){
				print Constants->CONST->{ProxyErr}.$lineFeed;
                                exit(0);
			}
			print Constants->CONST->{'issueWithProxy'};
			putParameterValue(\"PROXY",\"",$confFilePath);
			if (getProxyDetails()){
				putParameterValue(\"PROXY",\"$proxyStr",$confFilePath);
				getConfigHashValue();
				if($proxyStr eq ""){
					$proxyStr = getProxy();
				}
				if ($proxyStr ne ""){
					$commandOutput = '';
					createPasswordFiles($password,$pwdPath,$userName,$enPwdPath);
					$res = validateAccount('on');
					return $res;
				}
			}else{
				$commandOutput = '';
                                createPasswordFiles($password,$pwdPath,$userName,$enPwdPath);
				$accDetailsCheck = 1;
				goto CHECK_ACC_DETAILS;
			}
		}else{	
			print Constants->CONST->{'InvProxy'}.$lineFeed;
			if(-e $enPwdPath){
				unlink($enPwdPath);
			}
			if(-e $pwdPath){		
				unlink($pwdPath);
			}
			exit;
		}
	}elsif($commandOutput =~ /Unable to reach the server\; account validation has failed/i){
		if ($reloginStatus ne 'on'){
			 if ($accDetailsCheck == 1){
				print Constants->CONST->{ProxyErr}.$lineFeed;
				exit(0);
                         }
			 print Constants->CONST->{'InvProxy'};
			 getProxyDetails();
			 putParameterValue(\"PROXY",\"$proxyStr",$confFilePath);
			 getConfigHashValue();
			 if($proxyStr eq ""){
			         $proxyStr = getProxy();
 			 }
			 if ($proxyStr ne ""){
			        $commandOutput = '';
				createPasswordFiles($password,$pwdPath,$userName,$enPwdPath);
				$res = validateAccount('on');
				return $res;
			 }
		}else{
			print qq($lineFeed$& $lineFeed);
			print Constants->CONST->{ProxyErr}.$lineFeed;
			if(-e $enPwdPath){
				unlink($enPwdPath);
			}
			if(-e $pwdPath){
				unlink($pwdPath);
			}
			exit(0);
		}
	}else {
		print $lineFeed.$commandOutput.$lineFeed;
		if($commandOutput !~ /SUCCESS/) {
			exit(1);
		}
	}
	if ($commandOutput =~ /Unable to continue,reason: connect\(\) failed|Unable to reach the server; account validation has failed/){
		print Constants->CONST->{ProxyErr}.$lineFeed;
		exit(0);	
	}
	return $commandOutput;
}

#****************************************************************************************************
# Subroutine Name         : configureAccount.
# Objective               : This subroutine configures an user account if the 
#							account is not already configured.
# Added By                : 
#*****************************************************************************************************/
sub configureAccount() {
	if(! -f $pvtPath and $isPrivate == 1) {
		createEncodeFile($pvtKey, $pvtPath);
	}
		
	#--------------------------------------------------------------
	traceLog("$lineFeed configureAccount: ", __FILE__, __LINE__);
	#print $tHandle "$lineFeed configureAccount: ";
	
	my $configUtf8File = getOperationFile(Constants->CONST->{'ConfigOp'}, $encType);
	chomp($configUtf8File);
	$configUtf8File =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = "'$idevsutilBinaryPath'".$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$configUtf8File."'".$whiteSpace.$errorRedirection;
	my $commandOutput = `$idevsutilCommandLine`;
	traceLog("$lineFeed $commandOutput $lineFeed", __FILE__, __LINE__);
	#print $tHandle "$lineFeed $commandOutput $lineFeed";
	unlink $configUtf8File;
	#--------------------------------------------------------------
}

#****************************************************************************************************
# Subroutine Name         : verifyAccount.
# Objective               : This subroutine varifies the encryption key by creating Folder.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub verifyAccount
{
	if($isPrivate) {
		createEncodeFile($pvtKey, $pvtPath);
	}
	#get evs server address for other APIs
	getServerAddr();
	my $retType = '';
	if($isPrivate eq 1) {
		print $lineFeed.Constants->CONST->{'verifyPvt'}.$lineFeed;
		if ($dedup eq 'off'){
			my $pvtVerifyUtfFile = getOperationFile(Constants->CONST->{'validatePvtKeyOp'});
			my $tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
			$tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;
			my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
			$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
		
			my $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
			$retType = `$idevsUtilCommand`;
			chomp($retType);
			unlink($pvtVerifyUtfFile);
		}else{
			$retType = getDeviceList();
		}
		if($retType =~ /encryption verification failed|Unable to proceed; private encryption key must be between 4 and 256 characters in length/) {
#			print Constants->CONST->{'AskCorrectPvt'}.$lineFeed;
			print Constants->CONST->{InvalidPvtKey}.' '.Constants->CONST->{TryAgain}.$lineFeed;
			unlink($pwdPath);
			unlink($pvtPath);
			unlink($pvtPath."_SCH");
		} 
	#	elsif($retType =~ /verification success|connection established/) {
		else{
			#Create Cache Directory 
			createCache();
			updateConf();
#			print $lineFeed.Constants->CONST->{'LoginSuccess'}.$lineFeed;
			print $lineFeed.Constants->CONST->{'displayUserMessage'}->("\"$userName\"",Constants->CONST->{'LoginSuccess'}).$lineFeed;
		}
	} elsif ($isPrivate eq 0) {
		createCache();
		updateConf();
#		print $lineFeed.Constants->CONST->{'LoginSuccess'}.$lineFeed;
		print $lineFeed.Constants->CONST->{'displayUserMessage'}->("\"$userName\"",Constants->CONST->{'LoginSuccess'}).$lineFeed;	
	}
}
#****************************************************************************************************
# Subroutine Name         : updateConf.
# Objective               : This subroutine updates the Configuration file with account config status
#							and creates path for schedule Backup/Restore job.
# Added By                : 
#*****************************************************************************************************/
sub updateConf()
{
	#$dummyString = "XXXXX";
	$schPwdPath = "$pwdPath"."_SCH";
	copy($pwdPath, $schPwdPath);
	putParameterValue(\"DEDUP", \$dedup, $confFilePath);
	putParameterValue(\"USERNAME", \$userName, $confFilePath);
	if($isPrivate) {
		$schPvtPath = $pvtPath."_SCH";
		copy($pvtPath, $schPvtPath);
#		putParameterValue(\"PVTKEY", \$dummyString, $confFilePath);	
	}
}

#****************************************************************************************************
# Subroutine Name         : checkIfDirExits.
# Objective               : 
# Added By                : Dhritikana
#*****************************************************************************************************/
sub checkIfDirExits {
	if(-d $userDir and -e $_[0] and -s $_[0] > 0) {
		readConfigurationFile($_[0]);
		getConfigHashValue();
		loadUserData();
		return 1;
	} else {
		print Constants->CONST->{'loginConfigAgain'}.$lineFeed;
		exit;
	}
}
#****************************************************************************************************
# Subroutine Name         : getAccountInfo.
# Objective               : Gets the user account information by using CGI.
# Added By                : Dhritikana.
#*****************************************************************************************************/
sub getAccountInfo {
	print $lineFeed.Constants->CONST->{'verifyAccount'}.$lineFeed;
	my $PATH = undef;
	if($appType eq "IDrive") {
		$PATH = $IDriveAccVrfLink;
	} elsif($appType eq "IBackup") {
		$PATH = $IBackupAccVrfLink;
	}
	
	my $encodedUname = $userName;
	my $encodedPwod = $password;
	#URL DATA ENCODING#
	foreach ($encodedUname, $encodedPwod) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}
	my $data = 'username='.$encodedUname.'&password='.$encodedPwod;
	my $curl = `which curl`;
	Chomp(\$curl);
	if($proxyOn eq 1) {
		$curlCmd = "$curl --max-time 15 -x http://$proxyIp:$proxyPort --proxy-user $proxyUsername:$proxyPassword -L -s -k -d '$data' '$PATH'";
	} else {
		$curlCmd = "$curl --max-time 15 -s -k -d '$data' '$PATH'";
	}
	my $res = `$curlCmd`;
	if($res =~ /FAILURE/) {
		if($res =~ /passwords do not match|Username or Password not found|invalid value passed for username|password too short|username too short|password too long|username too long/i) {
#			undef $userName; Any specific reason behind writing this statement.
			print ucfirst($&).". ".Constants->CONST->{'TryAgain'}."$lineFeed";
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
        	$res =	validateAccount();
        } elsif( $res =~ /Unauthorized/) {
            $res = validateAccount();
        }
        if ($res eq ''){
           $res =  validateAccount();
        }
	
	my %evsLoginHashOutput = parseXMLOutput(\$res);
	chomp(%evsLoginHashOutput);
	$encType = $evsLoginHashOutput{"enctype"} ne "" ? $evsLoginHashOutput{"enctype"} : $evsLoginHashOutput{"configtype"};
	$plan_type = $evsLoginHashOutput{"plan_type"};
	$message = $evsLoginHashOutput{"message"};
	$cnfgstat = $evsLoginHashOutput{"cnfgstat"} ne "" ? $evsLoginHashOutput{"cnfgstat"} : $evsLoginHashOutput{"configstatus"};
	$desc = $evsLoginHashOutput{"desc"};
	$dedup = $evsLoginHashOutput{"dedup"} if($appType eq "IDrive");
	$accountQuota = $evsLoginHashOutput{"quota"};
	$quotaUsed = $evsLoginHashOutput{"quota_used"};
	getServerAddr($evsLoginHashOutput{evssrvrip});	
	#dedup check
	if ($dedup eq 'on'){
		$idevsutilBinaryName = "idevsutil_dedup";#Name of idevsutil binary#
		$idevsutilBinaryPath = "$idriveServicePath/idevsutil_dedup";#Path of idevsutil binary#
	}		
}
#****************************************************************************************************
# Subroutine Name         : getPvtKey.
# Objective               : Get the input for private key from user.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub getPvtKey{
	if($cnfgstat eq "SET") {
	# For Private Account Verifies the Private Encryption Key
		if($encType eq "PRIVATE") {
			print $lineFeed.Constants->CONST->{'AskPvtSetAcc'};
			system('stty','-echo');
			$pvtKey = getInput();
			checkInput(\$pvtKey,$lineFeed);
			system('stty','echo');
			$isPrivate = 1;
		}
	}
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
