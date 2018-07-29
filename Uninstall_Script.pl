#!/usr/bin/perl
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
our @linesCrontab = ();
my $isAnyOtherUserProcess=0;
my $user;
my $pidsToBeKilled = ' ';
my @idriveUsersList = ();
my @scheduledJobs = ();
my $unlinkPidFile=0;
my %idriveUserInfo = ();

my @fileNames = ('account_setting.pl','Account_Setting.pl','archive_cleanup.pl','check_for_update.pl','Check_For_Update.pl','Backup_Script.pl','Constants.pm','Header.pl','Job_Termination_Script.pl','job_termination.pl','login.pl','Login.pl','Logout.pl','Operations.pl','readme.txt','Restore_Script.pl','restore_version.pl','Restore_Version.pl','Scheduler_Script.pl','Status_Retrieval_Script.pl','edit_supported_files.pl','edit_supported_files.pl','View_Log.pl','Uninstall_Script.pl','.updateVersionInfo','.serviceLocation','freshInstall','.forceupdate','wgetLog.txt','Configuration.pm', 'Helpers.pm','IxHash.pm', 'Strings.pm','express_backup.pl','send_error_report.pl', 'JSON.pm', 'utility.pl', 'view_log.pl');

system("clear");
loadUserData();
headerDisplay($0);
checkUser();

my $confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

#This if and else block will check the user account configuration details and login details.

if(getAccountConfStatus($confFilePath)){
	exit(0);
}
elsif(getLoginStatus($pwdPath)){
	exit(0);
}


#Getting IDrive user list
@idriveUsersList = getIDriveUserList();
if(scalar @idriveUsersList>0) {	
	$pidsToBeKilled = getAllRunningJobsPids();
}
@scheduledJobs = checkCronEntries();
$noPermission = 0;
$errorReason  = '';
if(!-w $currentDir){
	#$errorReason  = "noPermission:$currentDir".$lineFeed;
	$errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "script directory","'$currentDir'");
	$noPermission = 1;
} elsif($idriveServicePath and -e $idriveServicePath and !-w $idriveServicePath){
	#$errorReason  = "noPermission:$idriveServicePath\n".$lineFeed;
	$errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "service directory","'$idriveServicePath'");
	$noPermission = 1;
} elsif(scalar(@scheduledJobs) > 0 && !-w $crontabFilePath){
	#$errorReason  = "noPermission:$crontabFilePath".$lineFeed;
	$errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "crontab","entries");
	$noPermission = 1;
} 
elsif($isAnyOtherUserProcess){
	#$errorReason  = "noPermission:$isAnyOtherUserProcess".$lineFeed;
	$errorReason  = Constants->CONST->{'noPermissionToKill'}->($user);
	$noPermission = 1;
} else {
	foreach $file (@fileNames){
		if(-e "$currentDir/$file"){
			if(!-w "$currentDir/$file"){
				#$errorReason  = "noPermission:$currentDir/$file".$lineFeed;
				$errorReason  = Constants->CONST->{'DirectoryFileNotEmpty'}->($user, "script file","'$currentDir/$file'");
				$noPermission = 1;
				last;
			}
		}
	}
}

if($noPermission){
	print $lineFeed.$errorReason.$lineFeed;
	#print $lineFeed.Constants->CONST->{'noSufficientPermissionToCleanup'}->($user).$errorReason.$lineFeed.$lineFeed;
	exit;
}

#Get confirmation to uninstall the package.
#print $lineFeed.Constants->CONST->{'AskUninstallConfig'}.$whiteSpace;
print $lineFeed.Constants->CONST->{'AskUninstallConfig'}->($appType).$whiteSpace;
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
#print $lineFeed.Constants->CONST->{'checkingJobInProgress'}.$lineFeed;

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
		# Kill the running Backup/Restore process.
		@scriptTerm = killAllJobs($pidsToBeKilled);
		displayKillMessage(@scriptTerm);
	}
}
getUsersInfoToUninstall(); #Getting IDrive users info
removeCronEntries(); #Removing the cron-entries of scheduled Backup/Restore
removeServiceDirectory();
updateUsersUninstallInfo(); #stat CGI call
removeScriptFiles();
removeScriptAndPackageDirectory();
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
		$scriptTermCmd = "kill -9 $pidsToBeKilled";
	}
	#$scriptTermCmd .= "";		
	print qq(\nEnter root ) if (!$ifubuntu and $isAnyOtherUserProcess eq 1);
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
		my @userJobpath = ( "$usrProfileDir/Backup/Scheduled/", "$usrProfileDir/Restore/Scheduled/", "$usrProfileDir/Backup/Manual/", "$usrProfileDir/Restore/Manual/","$usrProfileDir/LocalBackup/Manual/" );
		for(my $j=0; $j<=$#userJobpath; $j++)
		{
			$pidsToBeKilled .= getRunningJobPid($userJobpath[$j]);
			if($unlinkPidFile == 0 and $pidsToBeKilled ne ' '){
				last;
			}
		}
	}
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
		$isUpdated = updateUserDetail($userName,$password,0);
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
	my $res   = '';
	if($idriveServicePath and -e $idriveServicePath){
		if($idriveServicePath ne "/" and $idriveServicePath =~ /\/$appTypeSupport/){	#<Deepak> Minimum validation to make sure it is our path
			$rmCmd = "rm -rf '$idriveServicePath'";
			$res = `$rmCmd`;
		}		
	
		if($rmCmd eq '' or $res ne ''){
			print $lineFeed.Constants->CONST->{'failedToRemove'}->('directory',$idriveServicePath).$lineFeed."Reason: ".$res.$lineFeed;
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
		if(-e "$currentDir/$file"){
			if(!unlink("$currentDir/$file")){
				print $lineFeed.Constants->CONST->{'failedToRemove'}->('file',"$currentDir/$file").$lineFeed;
			}
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : removeScriptAndPackageDirectory.
# Objective               : Removing the Script/Package directory if it is empty
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub removeScriptAndPackageDirectory 
{
	$scriptPathRemoved = 0;
	$pwd = `pwd`;
	if(isDirectoryEmpty($currentDir)) {
		$rmCmd = "rm -rf '$currentDir'";	
		$res = `$rmCmd`;
		if(!$res){
			$scriptPathRemoved = 1;
		}
		
		my $idx = rindex($currentDir, "/");
		$packagePath = substr($currentDir, 0, $idx+1);#Getting package path from script path
		if($scriptPathRemoved and isDirectoryEmpty($packagePath)) {
			if($pwd =~ /$packagePath/){
				chdir("$packagePath/../");
			}		
			$rmCmd = "rm -rf '$packagePath'";
			$res = `$rmCmd`;
		}
	} 
	print $lineFeed.Constants->CONST->{'scriptRemoved'}->($appType).$lineFeed;
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
	$evsRunning  = `$evsCmd`;
	
	my $uninstallScript     = $currentDir."/".Constants->FILE_NAMES->{uninstallScript};
	my $checkForUpdateScript = $currentDir."/".Constants->FILE_NAMES->{checkForUpdateScript};
	my $evsCmd   = "ps -elf | grep \"$currentDir\" | grep -v \'grep\' | grep -v \"$uninstallScript\" | grep -v \"$checkForUpdateScript\"";
	$evsRunning .= `$evsCmd`;
	
	if($jobRunningDir =~ /Restore/) {
		$searchUtfFile = $jobRunningDir."searchUtf8.txt";
		$evsCmd = "ps $psOption | grep \"$idevsutilBinaryName\" | grep \'$searchUtfFile\' | grep -v \'grep\'";
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
		$evsRunningUserName = $lines[2];
		if(($user ne "root") and ($evsRunningUserName) and ($user ne $evsRunningUserName)){
			$isAnyOtherUserProcess = 1;
		}		
		my $pid = $lines[3];
		$toCheckPid = " $pid ";
		if($pidsToBeKilled !~ /$toCheckPid/){
			push(@pids, $pid);
		}
	}	
	chomp(@pids);
	s/^\s+$// for (@pids);
	#$jobCount = @pids;
	
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
			print $lineFeed.Constants->CONST->{'UnableToRemoveCron'}.$lineFeed;
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
		#exit;
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
		#exit;
	}
	print TEMP "WRITE_TO_CRON\n";
	print TEMP @linesCrontab;
	close TEMP;
	chmod $filePermission, $temp;
	my $operationsScript = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
	
	if($isAnyOtherUserProcess) {
		$command = "su -c \"perl '$operationsScript' '$usrProfilePath' \" root";
		if (ifUbuntu()){
			$command = "sudo -p\"".Constants->CONST->{'CronQueryUbuntu'}." $user: \" ".$command;
		}else{
			print Constants->CONST->{'CronQuery'};
		}
	} else {
		$command = qq{perl '$operationsScript' '$usrProfilePath'};
	}

	my $res = system($command);
	#unlink($temp);
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
	$user = `$checkUserCmd`;
	chomp($user);
	#if($user ne "root") {
		#$noRoot = 1;
	#}
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
	my @usersList = ();
	if(-d $usrProfilePath) {	
		if(opendir(DIR, $usrProfilePath)) {	
			foreach my $userName (readdir(DIR))  {
				if ( $userName eq "." or $userName eq "..") {
					next;
				}		
				$usrProfileDir = "$usrProfilePath/$userName";
				if(-d $usrProfileDir) {
					push @usersList,$usrProfileDir;
				}
			}
		}
	}
	return @usersList;
}
#****************************************************************************************************
# Subroutine Name         : validateLinuxUser
# Objective               : Validating the linux user
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub validateLinuxUser
{
	print $lineFeed.Constants->CONST->{'ToUninstall'}.$lineFeed;
	my $inputCount=0;
	while(1){
		print $lineFeed.Constants->CONST->{'AskLinuxPword'}->($user);		
		system('stty','-echo');
		my $pwd = getInput();
		checkInput(\$pwd,$lineFeed);
		system('stty','echo');
		
		my @pwent = getpwnam($user);
		$passwordHash = $pwent[1];
		if($passwordHash eq ""){
			print "Can't read password DB or Ur not permitted to read from it \n";
		}
		else{
			$password = $pwd;
			my $checking_hash = crypt($password, $passwordHash);	
			if ($checking_hash eq $passwordHash) {
				print $lineFeed.$lineFeed.Constants->CONST->{'YourAuthSuccess'}.$lineFeed;
				last;
			}
			if($inputCount eq 3) {
				print $lineFeed.Constants->CONST->{'YourAuthFailed'}.$lineFeed.Constants->CONST->{'YourMaxAttemptReached'}.$lineFeed.$lineFeed;	
				exit(0);		
			}	
			print $lineFeed.Constants->CONST->{'YourAuthFailed'}.$whiteSpace.Constants->CONST->{'pleaseTryAgain'}.$lineFeed;	
			$inputCount++;	
		}	
	}
}
#****************************************************************************************************
# Subroutine Name         : validatePassword
# Objective               : Validate the linux password
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub validatePassword
{
	my $password = shift;
	$enc_pass = `echo "$password" | password_encryptor`;
	chomp($enc_pass);
	open(SHADOW, '</etc/shadow');
	foreach my $Line (<SHADOW>)
	{
		return 1 if ($Line =~ m/^$user:$enc_pass/); #check if the encrypted password is on the same line as the username with only one colon between them (follows format of the shadow file)
	}
	close(SHADOW);
}