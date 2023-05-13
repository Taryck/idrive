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
my $sudoprompt = "please_provide_" . (Common::isUbuntu() || Common::isGentoo()? 'sudoers' : 'root') . '_pwd_for_uninstall_process';
$sudoprompt = "\n".Common::getStringConstant($sudoprompt);
my @fileNames = ('account_setting.pl','Account_Setting.pl','archive_cleanup.pl','check_for_update.pl','Check_For_Update.pl','Backup_Script.pl','Constants.pm','Header.pl','Job_Termination_Script.pl','job_termination.pl','login.pl','Login.pl','logout.pl','Operations.pl','readme.txt','Restore_Script.pl','restore_version.pl','Restore_Version.pl','Scheduler_Script.pl','Status_Retrieval_Script.pl','edit_supported_files.pl','edit_supported_files.pl','View_Log.pl','logs.pl','Uninstall_Script.pl','.updateVersionInfo','.serviceLocation','freshInstall','.forceupdate','wgetLog.txt','Configuration.pm', 'Helpers.pm','IxHash.pm', 'Strings.pm','express_backup.pl','send_error_report.pl', 'JSON.pm', 'utility.pl', 'view_log.pl','speed_analysis.pl', 'scheduler.pl', 'cron.pl', 'help.pl', 'idrivecron.service', 'idrivecron.conf', 'idrivecron', 'Idrivelib','uninstallcron.pl', 'relinkcron.pl', 'installcron.pl', 'dashboard.pl', 'migrateSuccess', 'migrate.lock', 'ca-certificates.crt', 'perl.core', 'debug.enable');

system(Common::updateLocaleCmd("clear"));

Common::loadAppPath();
Common::loadServicePath() or $noServicePath=1;
Common::displayHeader();
unless(Common::isLoggedin()){
	my $uname = Common::getAndValidate(['enter_your', " ", $AppConfig::appType, " ", 'username', ': '], "username", 1);
	$uname = lc($uname); #Important
	my $emailID = $uname;

	# Get password and validate
	my $upasswd = Common::getAndValidate(['enter_your', " ", $AppConfig::appType , " ", 'password', ': '], "password", 0);

	Common::setUsername($uname);
	my $errorKey = Common::loadUserConfiguration();

	# If this account is not configured then prompt for proxy
	Common::askProxyDetails() if($errorKey != 1);

	#validate user account
	Common::display(['verifying_your_account_info'],1);

	# Get IDrive/IBackup username list associated with email address	
	($uname,$upasswd) = Common::getUsernameList($uname, $upasswd) if(Common::isValidEmailAddress($uname));

	# validate IDrive user details
	my @responseData = Common::authenticateUser($uname, $upasswd, $emailID, 1) or Common::retreat(['failed_to_authenticate_user',"'$uname'."]);
}
goto REMOVESCRIPTS if($noServicePath);

#Getting IDrive user list
@idriveUsersList = getIDriveUserList();
if(scalar @idriveUsersList>0) {
	$pidsToBeKilled = getAllRunningJobsPids();
}
#@scheduledJobs = checkCronEntries();
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
	#print $lineFeed.$errorReason.$lineFeed;
	#exit;
# }

#Get confirmation to uninstall the package.
print $lineFeed.Constants->CONST->{'AskUninstallConfig'}->($AppConfig::appType).$whiteSpace;
$confirmationChoice = getConfirmationChoice();
if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
	exit 0;
}

if(scalar @idriveUsersList>1) {
	#Get confirmation to uninstall the package when more than one user using this script.
	print $lineFeed.Constants->CONST->{'multiUserConfirm'}.$whiteSpace;
	$confirmationChoice = getConfirmationChoice();
	if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
		exit 0;
	}
}

# Checking the running & Killing Backup/Restore process.
if(scalar @idriveUsersList>0) {
	if($pidsToBeKilled ne ''){
		#Get confirmation to uninstall the package If any job is in progress.
		print $lineFeed.Constants->CONST->{'OneJobsRunning'}.$whiteSpace;
		$confirmationChoice = getConfirmationChoice();
		if($confirmationChoice eq "N" || $confirmationChoice eq "n") {
			exit 0;
		}
		$unlinkPidFile=1;
		$pidsToBeKilled = getAllRunningJobsPids();
		$pidsToBeKilled   .= " $dashboardPidsToBeKilled" if($dashboardPidsToBeKilled); #Appending dashboard PIDs

		# Kill the running process.
		@scriptTerm = killAllJobs($pidsToBeKilled);
		displayKillMessage(@scriptTerm);
	} elsif($dashboardPidsToBeKilled) {
		#killing dashboard service processes
		@scriptTerm = killAllJobs($dashboardPidsToBeKilled);
		displayKillMessage(@scriptTerm);
	}
}
getUsersInfoToUninstall(); #Getting IDrive users info
removeCronEntries(); #Removing the cron-entries of scheduled Backup/Restore
my $sudomsgtoken = (ifUbuntu() || isGentoo())? Constants->CONST->{'uninstallSudoPWDMSG'}->($AppConfig::appType) : Constants->CONST->{'uninstallRootPWDMSG'}->($AppConfig::appType);
my $sudosucmd = getSudoSuCRONPerlCMD('uninstallcron', "\n".$sudomsgtoken);
$sudosucmd = Common::updateLocaleCmd($sudosucmd);
if(system($sudosucmd)==0){
	print $lineFeed.$AppConfig::appType.Constants->CONST->{'cronUninstalled'}.$lineFeed;
} else {
	print $lineFeed.Constants->CONST->{'UnableToUninstallCron'}->($AppConfig::appType).$lineFeed;
	exit(0);
}

#removeServiceDirectory();
updateUsersUninstallInfo(); #stat CGI call

REMOVESCRIPTS: #Added to remove script files if there is no '.serviceLocation' file/service directory
removeScriptFiles();
removeScriptAndPackageDirectory();
removeServiceDirectory(); #Added to remove if any trace file exists - fall back

#*****************************************************************************************************
# Subroutine			: getSudoSuCRONPerlCMD
# Objective				: This is to get sudo/su command for running the scripts in root mode
# Modified By			: Sabin Cheruvattil, Yogesh Kumar
#****************************************************************************************************/
sub getSudoSuCRONPerlCMD {
	return '' unless(defined($_[0]));
	return "perl '$userScriptLocation/" . Constants->FILE_NAMES->{utility} . "' " . uc($_[0]) if ($mcUser eq 'root');

	print "$_[1]\n" if (!ifUbuntu() && !isGentoo());

	my $command = "su -c \"perl '" . $userScriptLocation . '/' . Constants->FILE_NAMES->{utility} . "' " . uc($_[0]) . "\" root";
	$command 	= "sudo -p '" . $_[1] . "' " . $command if (ifUbuntu() || isGentoo());

	return $command;
}

#****************************************************************************************************
# Subroutine Name         : killAllJobs.
# Objective               : Killing all the running process
# Added By                : Senthil Pandian
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
		my @userJobpath = ( "$usrProfileDir/Backup/DefaultBackupSet/", "$usrProfileDir/Restore/DefaultRestoreSet/","$usrProfileDir/Backup/LocalBackupSet/", "$usrProfileDir/Archive/DefaultBackupSet/" );
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
#****************************************************************************************************
# Subroutine Name         : removeServiceDirectory.
# Objective               : Removing the Service Directory
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub removeServiceDirectory
{
	my $rmCmd = '';
	my $res   = 1;
	if($idriveServicePath and -e $idriveServicePath){
		if($idriveServicePath ne "/" and $idriveServicePath =~ /\/$appTypeSupport/){	#<Deepak> Minimum validation to make sure it is our path
			$rmCmd = "rm -rf '$idriveServicePath' 2>/dev/null";
			$rmCmd = Common::getSudoSuCMD("$rmCmd", $sudoprompt, 1);
			$rmCmd = Common::updateLocaleCmd($rmCmd);
			$res = system($rmCmd);
		}

		if($rmCmd eq '' or $res){
			print $lineFeed.Constants->CONST->{'failedToRemove'}->('directory',$idriveServicePath).$lineFeed."Reason: ".$!.$lineFeed;
		} else {
			print $lineFeed.Constants->CONST->{'DirectoryRemoved'}->('Service directory',$idriveServicePath).$lineFeed;
		}
	}
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
# Subroutine Name         : removeScriptAndPackageDirectory.
# Objective               : Removing the Script/Package directory if it is empty
# Added By                : Senthil Pandian
# Modified By             : Senthil Pandian, Vijay Vinoth
#*****************************************************************************************************/
sub removeScriptAndPackageDirectory
{
	$scriptPathRemoved = 0;
	my $pwdCmd = Common::updateLocaleCmd('pwd');
	$pwd = `$pwdCmd`;
	chomp($pwd);
	if(isDirectoryEmpty($currentDir)) {
		$rmCmd = "rm -rf '$currentDir' 2>/dev/null";
		my $previllege    = (Common::isUbuntu() || Common::isGentoo()? 'sudoers' : 'root');
		my $sudopromptMsg = "\nInsufficient permissions for '$user' to remove script directory. Please provide $previllege password to continue.";
		$rmCmd = Common::getSudoSuCMD("$rmCmd", $sudopromptMsg);
		$rmCmd = Common::updateLocaleCmd($rmCmd);
		my $res = system($rmCmd);
		if(!$res){
			$scriptPathRemoved = 1;
		}

		my $idx = rindex($currentDir, "/");
		$packagePath = substr($currentDir, 0, $idx+1);#Getting package path from script path
		if($scriptPathRemoved and isDirectoryEmpty($packagePath)) {
			if($pwd =~ /$packagePath/){
				chdir("$packagePath/../");
			}
			$rmCmd = "rm -rf '$packagePath' 2>/dev/null";
			$sudopromptMsg = "\nInsufficient permissions for '$user' to remove package directory. Please provide $previllege password to continue.";
			$rmCmd = Common::getSudoSuCMD("$rmCmd", $sudopromptMsg, 1);
			$rmCmd = Common::updateLocaleCmd($rmCmd);
			my $res = system($rmCmd);
		}
		print $lineFeed.Constants->CONST->{'scriptRemoved'}->($AppConfig::appType).$lineFeed;
	}
}

#****************************************************************************************************
# Subroutine Name         : getRunningJobPid.
# Objective               : Getting List of Running Job's Pid
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub getRunningJobPid
{
	$jobRunningDir = shift;
	my $pidPath = $jobRunningDir."pid.txt";
	my $utfFile = $jobRunningDir."utf8.txt";
	my $errorKillingJob = $jobRunningDir."errorKillingJob";
	my $searchUtfFile = undef;
	unlink($pidPath) if($unlinkPidFile == 1);

	my $evsCmd   = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$utfFile\' | grep -v \'grep\'";
	$evsCmd = Common::updateLocaleCmd($evsCmd);
	$evsRunning  = `$evsCmd`;

	my $uninstallScript     = $currentDir."/".Constants->FILE_NAMES->{uninstallScript};
	my $checkForUpdateScript = $currentDir."/".Constants->FILE_NAMES->{checkForUpdateScript};
	my $evsCmd   = "ps $psOption | grep \"$currentDir\" | grep -v \'grep\' | grep -v \"$uninstallScript\" | grep -v \"$checkForUpdateScript\"";
	$evsCmd = Common::updateLocaleCmd($evsCmd);
	$evsRunning .= `$evsCmd`;

	if($jobRunningDir =~ /Restore/) {
		$searchUtfFile = $jobRunningDir."searchUtf8.txt";
		$evsCmd = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$searchUtfFile\' | grep -v \'grep\'";
		$evsCmd = Common::updateLocaleCmd($evsCmd);
		$evsRunning .= `$evsCmd`;
	}

	@evsRunningArr = split("\n", $evsRunning);
	my $jobCount = 0;
	my @pids;

	foreach(@evsRunningArr) {
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
# Subroutine Name         : checkCronEntries.
# Objective               : Check existing jobs in Cron Entries
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub checkCronEntries {
	my $readable = readFromCrontab();
	if($readable == 0){
		print $lineFeed.Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "crontab","entries").$lineFeed.$lineFeed;
		exit(0);
	}
	my @schJobs = ();
	return @schJobs = grep /$currentDir/,@linesCrontab;
}
#****************************************************************************************************
# Subroutine Name         : removeCronEntries.
# Objective               : Remove package related cron entries.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub removeCronEntries {
	if (scalar(@scheduledJobs) > 0 ){
		removeEntryFromCrontabLines();
		my $writeFlag = writeToCrontab();
		if(!$writeFlag) {
			print $lineFeed.Constants->CONST->{'UnableToRemoveCron'}->$AppConfig::appType.$lineFeed;
			exit(0);
		} else {
			print $lineFeed.Constants->CONST->{'RemovedCronEntries'}.$lineFeed;
		}
	}
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
# Subroutine Name		: removeEntryFromCrontabLines.
# Objective				: Subroutine to remove an existing backup job from crontab corresponding
#							to the backup script.
# Modified By			: Dhritikana
# Modified By 			: Abhishek Verma - 21/6/2017 - Now variable $jobExists will contain only 'user_profile/tester_1/Backup/Scheduled' for backup job and
# 				  'user_profile/tester_1/Backup/Scheduled' for Restore job, to remove job from crontab file.
# 				  This has been done so that jobs can be deleted irrespective of the location from where job has been scheduled by the user.
#*****************************************************************************************************/
sub removeEntryFromCrontabLines
{
	my $jobExists = qq{$currentDir};
	@linesCrontab = grep !/$jobExists/, @linesCrontab;
}
#****************************************************************************************************
# Subroutine Name		: writeToCrontab.
# Objective				: Append an entry to crontab file.
# Modified By			: Dhritikana
#*****************************************************************************************************/
sub writeToCrontab {
	my $command = '';
	s/^\s+// for @linesCrontab;
	my $temp = "$usrProfilePath/operationsfile.txt";
	if(!open TEMP, ">", $temp) {
		print $tHandle "$!\n";
		print "unable $!";
	}
	print TEMP "WRITE_TO_CRON\n";
	print TEMP @linesCrontab;
	close TEMP;
	chmod $filePermission, $temp;
	my $operationsScript = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
	#my $execString = Common::getStringConstant('support_file_exec_string');
	if($isAnyOtherUserProcess) {
		$command = "su -c \"perl '$operationsScript' '$usrProfilePath' \" root";
		if (ifUbuntu()){
			$command = "sudo -p\"".Constants->CONST->{'CronQueryUbuntu'}." $user: \" ".$command;
		}else{
			print Constants->CONST->{'CronQuery'};
		}
	} else {
		$command = qq{perl '$operationsScript'  '$execString' '$usrProfilePath'};
	}

	$command = Common::updateLocaleCmd($command);
	my $res = system($command);
	if($res ne "0") {
		return 0;
	}
	return 1;
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
