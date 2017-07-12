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
#Check if EVS Binary exists.
my $err_string = checkBinaryExists();
if($err_string ne "") {
        print qq($err_string);
        exit 1;
}

headerDisplay($0);
my $CurrentUser = getCurrentUser();
if ($CurrentUser ne ""){
	print $lineFeed."User \"$CurrentUser\" ".Constants->CONST->{'alreadyLoginUser'}.'. '.Constants->CONST->{'logoutRequest'}." and try again.".$lineFeed.$lineFeed;
        exit 1;
}
print $lineFeed.Constants->CONST->{'displayUserMessage'}->('Enter your',$appType,'username: '); 
$userName = <STDIN>;
$userName =~ s/^[\s\t]+|[\s\t]+$//g;
checkInput(\$userName);
unless (validateUserName($userName)){
      print Constants->CONST->{'InvalidUserPattern'}.$lineFeed;
      exit 0;
}
my $userDir = "$usrProfilePath/$userName";
$confFilePath = "$userDir/".Constants->CONST->{'configurationFile'};
checkIfDirExits($confFilePath);

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

if(length($password) > 20) {
	print $lineFeed.Constants->CONST->{'InvalidUnamePwd'}.$lineFeed;
	exit;
}
createEncodeFile($password, $pwdPath);
createEncodeSecondaryFile($password, $enPwdPath, $userName);
validateAccount();
getQuota();
#****************************************************************************************************
# Subroutine Name         : validateAccount.
# Objective               : This subroutine validates an user account if the account is
#							private or default. It configues the previously not set Account.
# Added By                : 
#*****************************************************************************************************/
sub validateAccount
{	
	my $reloginStatus = shift;
	print $lineFeed.$lineFeed.Constants->CONST->{'verifyAccount'}.$lineFeed;
	my $validateUtf8File = getOperationFile($validateOp);
	chomp($validateUtf8File);

	#log API in trace file as well
	traceLog("$lineFeed validateAccount: ", __FILE__, __LINE__);
	$validateUtf8File =~ s/\'/\'\\''/g;
	
	my $idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$validateUtf8File."'".$whiteSpace.$errorRedirection;
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
			print Constants->CONST->{'InvProxy'};
			getProxyDetails();
			putParameterValue(\"PROXY",\"$proxyStr",$confFilePath);
			getConfigHashValue();
			if($proxyStr eq ""){
				$proxyStr = getProxy();
			}
			if ($proxyStr ne ""){
				$commandOutput = '';
				validateAccount('on');
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
			 print Constants->CONST->{'InvProxy'};
			 getProxyDetails();
			 putParameterValue(\"PROXY",\"$proxyStr",$confFilePath);
			 getConfigHashValue();
			 if($proxyStr eq ""){
			         $proxyStr = getProxy();
 			 }
			 if ($proxyStr ne ""){
			        $commandOutput = '';
				validateAccount('on');
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
	if ($reloginStatus ne 'on'){
		verifyAccount();
	}
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
	
	my $configUtf8File = getOperationFile($configOp, $encType);
	chomp($configUtf8File);
	$configUtf8File =~ s/\'/\'\\''/g;
	
	$idevsutilCommandLine = $idevsutilBinaryPath.$whiteSpace.$idevsutilArgument.$assignmentOperator."'".$configUtf8File."'".$whiteSpace.$errorRedirection;
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
sub verifyAccount()
{
	if($isPrivate) {
		createEncodeFile($pvtKey, $pvtPath);
	}
	#get evs server address for other APIs
	getServerAddr();
	if($isPrivate eq 1) {
		print $lineFeed.Constants->CONST->{'verifyPvt'}.$lineFeed;
		my $pvtVerifyUtfFile = getOperationFile($verifyPvtOp);
		my $tmp_pvtVerifyUtfFile = $pvtVerifyUtfFile;
		$tmp_pvtVerifyUtfFile =~ s/\'/\'\\''/g;
		my $tmp_idevsutilBinaryPath = $idevsutilBinaryPath;
		$tmp_idevsutilBinaryPath =~ s/\'/\'\\''/g;
		
		my $idevsUtilCommand = "\'$tmp_idevsutilBinaryPath\'".$whiteSpace.$idevsutilArgument.$assignmentOperator."\'$tmp_pvtVerifyUtfFile\'".$whiteSpace.$errorRedirection;
		my $retType = `$idevsUtilCommand`;
		chomp($retType);
		unlink($pvtVerifyUtfFile);
		if($retType !~ /verification success/) {
#			print Constants->CONST->{'AskCorrectPvt'}.$lineFeed;
			print Constants->CONST->{InvalidPvtKey}.' '.Constants->CONST->{TryAgain}.$lineFeed;
			unlink($pwdPath);
			unlink($pvtPath);
			unlink($pvtPath."_SCH");
		} 
		elsif($retType =~ /verification success/) {
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
	$dummyString = "XXXXX";
	$schPwdPath = "$pwdPath"."_SCH";
	copy($pwdPath, $schPwdPath);
#	putParameterValue(\"PASSWORD", \$dummyString, $confFilePath);
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
