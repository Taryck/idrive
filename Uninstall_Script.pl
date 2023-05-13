#!/usr/bin/env perl
#####################################################################
##Script Name : Uninstall_Script.pl
######################################################################

$incPos = rindex(__FILE__, '/');
$incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

require 'Header.pl';

my $curl  = whichPackage(\"curl");
chomp(my $currentDir = $userScriptLocation);
my $crontabFilePath = "/etc/crontab";
#our @linesCrontab = ();
my ($isAnyOtherUserProcess, $unlinkPidFile, $noServicePath) = (0) x 3;
my $userCmd = Common::updateLocaleCmd('whoami');
my $user = `$userCmd`;
Chomp(\$user);

my ($pidsToBeKilled, $dashboardPidsToBeKilled) = (' ') x 2;
my (@linesCrontab, @idriveUsersList, @scheduledJobs, %idriveUserInfo) = () x 4;
my $sudoprompt = "please_provide_" . (Common::hasSudo()? 'sudoers' : 'root') . '_pwd_for_uninstall_process';
$sudoprompt = Common::getStringConstant($sudoprompt);

my @fileNames = ('account_setting.pl','Account_Setting.pl','archive_cleanup.pl','check_for_update.pl','Check_For_Update.pl','Backup_Script.pl','Constants.pm','Header.pl','Job_Termination_Script.pl','job_termination.pl','login.pl','Login.pl','logout.pl','Operations.pl','readme.txt','Restore_Script.pl','restore_version.pl','Restore_Version.pl','Scheduler_Script.pl','Status_Retrieval_Script.pl','status_retrieval.pl','edit_supported_files.pl','edit_supported_files.pl','View_Log.pl','logs.pl','Uninstall_Script.pl','.updateVersionInfo','.serviceLocation','freshInstall','.forceupdate','wgetLog.txt','AppConfig.pm', 'Common.pm','Configuration.pm', 'Helpers.pm','IxHash.pm', 'Strings.pm','local_backup.pl','local_restore.pl','send_error_report.pl', 'JSON.pm', 'utility.pl', 'view_log.pl','speed_analysis.pl', 'scheduler.pl', 'cron.pl', 'help.pl', 'idrivecron.service', 'idrivecron.conf', 'idrivecron', 'Idrivelib','uninstallcron.pl', 'relinkcron.pl', 'installcron.pl', 'dashboard.pl', 'migrateSuccess', 'migrate.lock', 'ca-certificates.crt', 'perl.core', 'debug.enable', '.haltcdp', 'cdp_client.pl', 'cdp_server.pl');

system("clear");

Common::loadAppPath();
Common::loadServicePath() or $noServicePath=1;
Common::displayHeader();

if(!$noServicePath && !Common::isLoggedin()) {
	unless (Common::hasPythonBinary()) {
		Common::display(['downloading_python_binary', '... ']);
		Common::downloadPythonBinary() or Common::retreat('unable_to_download_python_binary');
		Common::display('python_binary_downloaded_successfully');
	}

	#Senthil: Prompting here due to Snigdha_2.32_22_1
	#We are prompting this if login failed due to wrong proxy. So moved call here
	Common::askProxyDetails() unless(-f Common::getUserFilePath($AppConfig::proxyInfoFile));

	# SSO login.
	Common::display(["please_choose_the_method_to_authenticate_your_account", ":"]);
	my @options = (
		'idrive_login',
		'sso_login',
	);

	Common::displayMenu('', @options);
	my $loginType = Common::getUserMenuChoice(scalar(@options));

	my $uname = Common::getAndValidate(['enter_your', " ", $AppConfig::appType, " ", 'username', ': '], "username", 1);
	$uname = lc($uname); #Important
	my $emailID = $uname;

	Common::setUsername($uname);
	my $errorKey = Common::loadUserConfiguration();

	# If this account is not configured then prompt for proxy
	# Common::askProxyDetails() if($errorKey != 1); 
	#Senthil -> Reg:Snigdha_2.32_22_1: We are prompting this if login failed due to proxy. So moving up.

	#validate user account
	# Common::display(['verifying_your_account_info'],1);

	# Get IDrive/IBackup username list associated with email address	
	($uname) = Common::getUsernameList($uname) if (Common::isValidEmailAddress($uname));

	# validate IDrive user details
	my @responseData = Common::authenticateUser($uname, $emailID, 1, $loginType) or Common::retreat(['failed_to_authenticate_user',"'$uname'."]);
}

# goto REMOVESCRIPTS if($noServicePath);
unless($noServicePath) {
    #Getting IDrive user list
    @idriveUsersList = getIDriveUserList();
    if(scalar @idriveUsersList>0) {
        $pidsToBeKilled = getAllRunningJobsPids();
    }

    $noPermission = 0;
    $errorReason  = '';
    if(!-w $currentDir){
        $errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "script directory","'$currentDir'");
        $noPermission = 1;
    } elsif($idriveServicePath and -e $idriveServicePath and !-w $idriveServicePath){
        $errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "service directory","'$idriveServicePath'");
        $noPermission = 1;
    }
    # elsif(scalar(@scheduledJobs) > 0 && !-w $crontabFilePath){
        # $errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "crontab","entries");
        # $noPermission = 1;
    # }
    elsif($isAnyOtherUserProcess){
        $errorReason  = Constants->CONST->{'noPermissionToKill'}->($user);
        $noPermission = 1;
    } else {
        foreach $file (@fileNames){
            if(-e "$currentDir/$file"){
                if(!-w "$currentDir/$file"){
                    $errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "script file","'$currentDir/$file'");
                    $noPermission = 1;
                    last;
                }
            }
        }
    }

    # if($noPermission){
        # #print $lineFeed.$errorReason.$lineFeed;
        # #exit;
    # }

    #Get confirmation to uninstall the package.
    print $lineFeed.Constants->CONST->{'AskUninstallConfig'}->($AppConfig::appType).$whiteSpace;
    $confirmationChoice = getConfirmationChoice();
    exit(1) if(lc($confirmationChoice) eq "n");

    if(scalar @idriveUsersList>1) {
        #Get confirmation to uninstall the package when more than one user using this script.
        print $lineFeed.Constants->CONST->{'multiUserConfirm'}.$whiteSpace;
        $confirmationChoice = getConfirmationChoice();
        if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
            exit 0;
        }
    }

    getUsersInfoToUninstall(); #Getting IDrive users info

	my $sudomsgtoken = Common::hasSudo()? Constants->CONST->{'uninstallSudoPWDMSG'}->($AppConfig::appType) : Constants->CONST->{'uninstallRootPWDMSG'}->($AppConfig::appType);
    my $sudosucmd = getSudoSuCRONPerlCMD('uninstallcron', "\n" . $sudomsgtoken);

    if(system($sudosucmd) == 0) {
        print $lineFeed.$AppConfig::appType.Constants->CONST->{'cronUninstalled'}.$lineFeed;
    }
	else {
        print $lineFeed.Constants->CONST->{'UnableToUninstallCron'}->($AppConfig::appType).$lineFeed;
        exit(0);
    }

    # Checking the running & Killing Backup/Restore process.
    if(scalar @idriveUsersList > 0) {
        if($pidsToBeKilled ne '') {
            #Get confirmation to uninstall the package If any job is in progress.
            print $lineFeed . Constants->CONST->{'OneJobsRunning'} . $whiteSpace;
            $confirmationChoice = getConfirmationChoice();
            exit(0) if($confirmationChoice eq "N" || $confirmationChoice eq "n");

            $unlinkPidFile=1;
            $pidsToBeKilled = getAllRunningJobsPids();
            $pidsToBeKilled .= " $dashboardPidsToBeKilled" if($dashboardPidsToBeKilled); #Appending dashboard PIDs

            # Kill the running process.
            @scriptTerm = killAllJobs($pidsToBeKilled);
            displayKillMessage(@scriptTerm);
            sleep(10); #Added for Snigdha_2.3_10_17 : Senthil
        } elsif($dashboardPidsToBeKilled) {
            #killing dashboard service processes
            @scriptTerm = killAllJobs($dashboardPidsToBeKilled);
            displayKillMessage(@scriptTerm);
        }
    }

    #removeServiceDirectory();
    updateUsersUninstallInfo(); #stat CGI call
}

# REMOVESCRIPTS: #Added to remove script files if there is no '.serviceLocation' file/service directory
Common::stopAllCDPServices() if(Common::isCDPWatcherRunning());
removeScriptFiles();
my $scriptdirrm = removeScriptDirectory();
removeServiceDirectory(); #Added to remove if any trace file exists - fall back
removePackageDirectory() if($scriptdirrm);

#*****************************************************************************************************
# Subroutine			: getSudoSuCRONPerlCMD
# Objective				: This is to get sudo/su command for running the scripts in root mode
# Modified By			: Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************************************/
sub getSudoSuCRONPerlCMD {
	return '' unless(defined($_[0]));
	return "$AppConfig::perlBin '$userScriptLocation/" . Constants->FILE_NAMES->{utility} . "' " . uc($_[0]) if ($mcUser eq 'root');

	my $command = "";

	if(Common::hasSudo()) {
		print "$_[1]\n" if (!ifUbuntu() and !isGentoo() and !Common::hasActiveSudo());

		my $sudomsg = (ifUbuntu() or isGentoo())? (" -p '" . $_[1] . "' ") : "";
		$command = "sudo $sudomsg $AppConfig::perlBin '" . $userScriptLocation . '/' . Constants->FILE_NAMES->{utility} . "' " . uc($_[0]);
	}
	else {
		print("$_[1]\n");

		my $sucurb = Common::hasBSDsuRestrition()? ' -m root ' : '';
		$command = "su $sucurb -c \"$AppConfig::perlBin '" . $userScriptLocation . '/' . Constants->FILE_NAMES->{utility} . "' " . uc($_[0]) . "\"";
	}

	return $command;
}

#****************************************************************************************************
# Subroutine 		: killAllJobs.
# Objective			: Killing all the running process
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub killAllJobs
{
	$pidsToBeKilled   = shift;
	my $scriptTermCmd = '';
	my @scriptTerm    = ();

	if($isAnyOtherUserProcess) {
		print $lineFeed.Constants->CONST->{'killQueryUbuntu'}.$lineFeed;
		my $rootCommand = "su -c \"kill -9 $pidsToBeKilled  2>/dev/null\"";
		if (ifUbuntu()){
			$ifubuntu = 1;
			$rootCommand = "sudo -Sk ".$rootCommand;
		}

		$scriptTermCmd = $rootCommand;
	} else {
		$scriptTermCmd = "kill -9 $pidsToBeKilled 2>/dev/null";
	}

	print qq(\nEnter root ) if (!$ifubuntu and $isAnyOtherUserProcess eq 1);

	$scriptTermCmd = Common::updateLocaleCmd($scriptTermCmd);
    # Common::display(["\n",'terminating_ongoing_jobs']); #Commented for Snigdha_2.3_19_3: Senthil
	return @scriptTerm = `$scriptTermCmd`;
}

#****************************************************************************************************
# Subroutine Name         : getAllRunningJobsPids.
# Objective               : getting all running jobs pid
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getAllRunningJobsPids
{
	$pidsToBeKilled = ' ';
	foreach my $usrProfileDir (@idriveUsersList)  {
		my @userJobpath = ( "$usrProfileDir/Backup/DefaultBackupSet/", "$usrProfileDir/Restore/DefaultRestoreSet/", "$usrProfileDir/LocalBackup/LocalBackupSet/", "$usrProfileDir/Archive/DefaultBackupSet/" );
		for(my $j=0; $j<=$#userJobpath; $j++)
		{
			$pidsToBeKilled .= getRunningJobPid($userJobpath[$j]);
			if($unlinkPidFile == 0 and $pidsToBeKilled ne ' '){
				last;
			}
		}
	}
	#Chomp(\$dashboardPidsToBeKilled); Commented by Senthil : 26-Sep-2018
	#$pidsToBeKilled   .= $dashboardPidsToBeKilled; #Appending dashboard PIDs
	Chomp(\$pidsToBeKilled);
	return $pidsToBeKilled;
}

#****************************************************************************************************
# Subroutine Name         : getUsersInfoToUninstall.
# Objective               : Get the client/IDrive user detail for stat.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getUsersInfoToUninstall
{
	if(-e $freshInstallFile) {
		if(!open(FH, "<", $freshInstallFile)) {
			return;
		}
		@idriveUsers = <FH>;
		close FH;
		chomp(@idriveUsers);
		foreach my $userName (@idriveUsers) {
			my $userDir = "$usrProfilePath/$userName";
			our $enPwdPath = "$userDir/.userInfo/".Constants->CONST->{'IDENPWD'};
			my $password = &getPdata("$userName");
			if($password ne ''){
				$idriveUserInfo{$userName} = $password; #Keeping user info in hash for later use
			}
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : updateUsersUninstallInfo.
# Objective               : Update the client/IDrive user detail for stat.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub updateUsersUninstallInfo
{
	foreach my $userName (sort keys %idriveUserInfo) {
		my $password = $idriveUserInfo{$userName};
		$isUpdated = Common::updateUserDetail($userName,$password,0);
	}
}

#*****************************************************************************************************
# Subroutine		: removeServiceDirectory
# Objective			: Removing the Service Directory
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil	
#*****************************************************************************************************
sub removeServiceDirectory
{
	my $rmCmd = '';
	my $res   = 1;

	return 0 if(!$idriveServicePath or !-d $idriveServicePath);

	if($idriveServicePath ne "/" and $idriveServicePath =~ /\/$appTypeSupport/) {	#<Deepak> Minimum validation to make sure it is our path
		$rmCmd = "rm -rf '$idriveServicePath' 2>/dev/null";
		$rmCmd = Common::getSudoSuCMD($rmCmd, $sudoprompt);
		chdir("../");
		$res = system($rmCmd);
	}

	if($rmCmd eq '' or $res) {
		print $lineFeed . Constants->CONST->{'failedToRemove'}->('directory', $idriveServicePath) . $lineFeed;
		print "Reason: " . $! . $lineFeed if($!);
		return 0;
	}

	print $lineFeed . Constants->CONST->{'DirectoryRemoved'}->('Service directory', $idriveServicePath) . $lineFeed;
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : removeScriptFiles.
# Objective               : Removing the script files
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub removeScriptFiles
{
	foreach $file (@fileNames){
		my $filePath = "$currentDir/$file";
		if (-f $filePath) {
			if (!unlink($filePath)) {
				print $lineFeed.Constants->CONST->{'failedToRemove'}->('file', $filePath).$lineFeed;
			}
		}
		elsif (-d "$currentDir/$file") {
			$res = Common::removeItems($filePath);
			if (!$res) {
				print $lineFeed.Constants->CONST->{'failedToRemove'}->('directory', $filePath).$lineFeed."Reason: ".$res.$lineFeed;
			}
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : removeScriptDirectory
# Objective               : Removing the Script/Package directory if it is empty
# Added By                : Senthil Pandian
# Modified By             : Senthil Pandian, Vijay Vinoth
#*****************************************************************************************************/
sub removeScriptDirectory
{
	my $pwdCmd = 'pwd';
	$pwd = `$pwdCmd 2>/dev/null`;
	chomp($pwd);

	return 0 if(!isDirectoryEmpty($currentDir));

	$rmCmd = "rm -rf '$currentDir' 2>/dev/null";
	my $previllege    = (Common::hasSudo()? 'sudoers' : 'root');
	my $sudopromptMsg = "\nInsufficient permissions for '$user' to remove script directory. Please provide $previllege password to continue.";
	$rmCmd = Common::getSudoSuCMD("$rmCmd", $sudopromptMsg);

	chdir("../");
	my $res = system($rmCmd);
	return 1 if(!$res);

	print $lineFeed.Constants->CONST->{'failedToRemove'}->('directory', $currentDir).$lineFeed;
	return 0;
}

#*****************************************************************************************************
# Subroutine	: removePackageDirectory
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Remove the scripts installation directory
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub removePackageDirectory {
	my $idx = rindex($currentDir, "/");
	my $packagePath = substr($currentDir, 0, $idx + 1); # Getting package path from script path

	my $pwdCmd = 'pwd';
	$pwd = `$pwdCmd 2>/dev/null`;
	chomp($pwd);

	return 0 if(!isDirectoryEmpty($packagePath));

	chdir("$packagePath/../") if($pwd =~ /$packagePath/);

	$rmCmd = "rm -rf '$packagePath' 2>/dev/null";
	$sudopromptMsg = "\nInsufficient permissions for '$user' to remove package directory. Please provide $previllege password to continue.";
	$rmCmd = Common::getSudoSuCMD($rmCmd, $sudopromptMsg);

	my $res = system($rmCmd);
	if($res) {
		#Added for Snigdha_2.3_12_17: Senthil
		print $lineFeed.Constants->CONST->{'failedToRemove'}->('directory', $packagePath).$lineFeed;
		return 0;
	}

	print $lineFeed.Constants->CONST->{'scriptRemoved'}->($AppConfig::appType).$lineFeed;
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : getRunningJobPid.
# Objective               : Getting List of Running Job's Pid
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getRunningJobPid
{
	my $jobRunningDir = shift;
	my $pidPath = $jobRunningDir."pid.txt";
	my $utfFile = $jobRunningDir."utf8";
	my $errorKillingJob = $jobRunningDir."errorKillingJob";
	my $searchUtfFile = undef;
	unlink($pidPath) if($unlinkPidFile == 1);

	$utfFile =~ s/\[/\\[/; #Added for Suruchi_2.32_21_1: Senthil
	$utfFile =~ s/{/[{]/;
	my $evsCmd   = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$utfFile\' | grep -v \'grep\'";
	$evsCmd = Common::updateLocaleCmd($evsCmd);
	$evsRunning  = `$evsCmd`;

	my $tempCurrentDir = $currentDir;
	$tempCurrentDir =~ s/\[/\\[/;
	$tempCurrentDir =~ s/{/[{]/;
	my $uninstallScript      = Common::getCatfile($tempCurrentDir, $AppConfig::idriveScripts{'uninstall_script'});
	my $checkForUpdateScript = Common::getCatfile($tempCurrentDir, $AppConfig::idriveScripts{'check_for_update'});
	
	$evsCmd   = "ps $psOption | grep \"$tempCurrentDir\" | grep -v \'grep\' | grep -v \"$uninstallScript\" | grep -v \"$checkForUpdateScript\"";
	$evsCmd = Common::updateLocaleCmd($evsCmd);
	$evsRunning .= `$evsCmd`;

	if($jobRunningDir =~ /Restore/) {
		$searchUtfFile = $jobRunningDir."searchUtf8.txt";
		$searchUtfFile =~ s/\[/\\[/;
		$searchUtfFile =~ s/{/[{]/;
		$evsCmd = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$searchUtfFile\' | grep -v \'grep\'";
		$evsCmd = Common::updateLocaleCmd($evsCmd);
		$evsRunning .= `$evsCmd`;
	}

	@evsRunningArr = split("\n", $evsRunning);
	my $jobCount = 0;
	my @pids;

	foreach(@evsRunningArr) {
		next unless($_);
		if($_ =~ /$evsCmd/) {
			next;
		}
		my @lines = split(/[\s\t]+/, $_);
		my $evsRunningUserName = $lines[2];
		$evsRunningUserName = $lines[0] if($AppConfig::machineOS =~ /freebsd/i);
		if(($user ne "root") and ($evsRunningUserName) and ($user ne $evsRunningUserName)){
			$isAnyOtherUserProcess = 1;
		}
		my $pid = $lines[3];
		$pid = $lines[1] if($AppConfig::machineOS =~ /freebsd/i);
		$toCheckPid = " $pid ";
		if($pidsToBeKilled !~ /$toCheckPid/){
			push(@pids, $pid);
		}
	}
	chomp(@pids);
	s/^\s+$// for (@pids);

	if(scalar @pids>0){
		my $pidString = join(" ", @pids);
		return "$pidString ";
	}
	return '';
}

#****************************************************************************************************
# Subroutine Name         : displayKillMessage.
# Objective               : Depending upon the result of kill / unlink command this method will display the message.
# Added By                : Abhishek Verma.
#*****************************************************************************************************/
sub displayKillMessage{
	my @scriptTerm = shift;
	my $killError  = '';
	my $isAnyError = 0;
	if(scalar @scriptTerm>0) {
		foreach $error (@scriptTerm){
			chomp($error);
			Chomp(\$error);
			if($error ne '' and $error !~ /No such process/i){
				$killError .= $error.$lineFeed;
				$isAnyError = 1;
			}
		}
		if($isAnyError == 1){
			print $lineFeed.Constants->CONST->{'KilFail'}.$killError.'.'.$lineFeed;
		}

		if ($createPasswordFlag){
			open(IP,'>',Constants->CONST->{'incorrectPwd'});
			close (IP);
		}
    }
}

#****************************************************************************************************
# Subroutine Name         : checkUser.
# Objective               : This function will check user and if not root will prompt for credentials.
# Added By                : Dhritikana
#*****************************************************************************************************/
sub checkUser {
	my $checkUserCmd = "whoami";
	$checkUserCmd = Common::updateLocaleCmd($checkUserCmd);
	$user = `$checkUserCmd`;
	chomp($user);
}

#****************************************************************************************************
# Subroutine Name         : isDirectoryEmpty.
# Objective               : Checking the directory whether is empty or not
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub isDirectoryEmpty {
    my $dirname = shift;
    if(opendir(my $dh, $dirname)){
    	return scalar(grep { $_ ne "." && $_ ne ".." } readdir($dh)) == 0;
	} else {
		return 1;
	}
}

#****************************************************************************************************
# Subroutine Name         : getIDriveUserList.
# Objective               : Getting IDrive user list from service directory.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getIDriveUserList
{
	my @mcUsersList = ();
	my @idriveUsersList = ();
	my $usrProfileDirPath = "$idriveServicePath/user_profile";
	if(-d $usrProfileDirPath) {
		if(opendir(MCUSERDIR, $usrProfileDirPath)) {
			foreach my $userName (readdir(MCUSERDIR))  {
				if ( $userName eq "." || $userName eq "..") {
					next;
				}
				my $mcUserProfileDir = "$usrProfileDirPath/$userName";
				if(-d $mcUserProfileDir) {
					push @mcUsersList,$mcUserProfileDir;
					#Get process id of all dashboard belongs to current script path
					if(-f "$mcUserProfileDir/$AppConfig::dashboardpid"){
						if (open(my $fileHandle, '<', "$mcUserProfileDir/$AppConfig::dashboardpid")) {
							my $pid = <$fileHandle>;
							close($fileHandle);
							chomp($pid);
							if ($pid ne '') {
								$dashboardPidsToBeKilled .= "$pid ";
							}
						}
					}
					if(opendir(DIR, $mcUserProfileDir)) {
						foreach my $userName (readdir(DIR))  {
							next if($userName eq "." || $userName eq ".." || $userName eq ".trace" || $userName eq "tmp");
							$idriveUserProfileDir = "$mcUserProfileDir/$userName";
							push(@idriveUsersList, $idriveUserProfileDir) if(-d $idriveUserProfileDir);
						}
					}
				}
			}
		}
	}
	Chomp(\$dashboardPidsToBeKilled);
	return @idriveUsersList;
}
