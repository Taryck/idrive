#*****************************************************************************************************
# Most commonly used subroutines are placed here for re-use
#
# Created By  : Yogesh Kumar @ IDrive Inc
# Reviewed By : Deepak Chaurasia
#****************************************************************************************************/

package Helpers;
use Taryck;
use strict;
use warnings;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(display getRemoteAccessToken encryptString getParentRemoteManageIP getRemoteManageIP getUsername getMachineUser getServicePath getCatfile retreat request getUserConfiguration loadCrontab createCrontab getCrontab getUserProfilePath setCrontab prettyPrint);

use Cwd 'abs_path';
use POSIX qw(strftime);
use File::Spec::Functions;
use File::Basename;
use Scalar::Util qw(reftype looks_like_number);
use File::Path qw(rmtree);
use File::Copy;
use File::stat;
use POSIX;
use Fcntl qw(:flock SEEK_END);
use IO::Handle;

use utf8;
use MIME::Base64;

use Sys::Hostname;

use Configuration;
use JSON;

# Locale Strings
my %LS = ();
if ($Configuration::language eq 'EN') {
	use Locale::EN;
	%LS = %Locale::EN::strings;
}

use constant STATUS => 'STATUS';
use constant MSG => 'MSG';
use constant DATA => 'DATA';

# CRON STATUS
use constant CRON_NOTRUNNING => 0;
use constant CRON_STARTED => 1;
use constant CRON_RUNNING => 2;

my $appPath;
my $servicePath = '';
my $username = '';
my $evsBinary;
my $storageUsed;
my $totalStorage;
my $storageUsed_Raw_TBE;
my $totalStorage_Raw_TBE;
my $utf8File;
my $serverAddress;
my $machineHardwareName;
my $muid;
my $mipa;
my $errorDevNull = '2>>/dev/null';

my %notifications;
our %crontab;
our $machineInfo;

use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";
use constant FILE_MAX_COUNT => 1000;
use constant EXCLUDED_MAX_COUNT => 30000;

my ($relative,$BackupsetFile_new,$BackupsetFile_Only,$current_source);
my $filecount = 0;

my %backupExcludeHash = (); #Hash containing items present in Exclude List#
my ($totalSize,$prevFailedCount,$cols,$latestCulmn,$backupfilecount,$skippedItem) = (0) x 6;
my $progressSizeOp = 1;
my ($backupLocationDir,$summaryError,$summary) = ('') x 4;
my $lineFeed = "\n";
my @startTime;
tie(my %userConfiguration, 'Tie::IxHash');
my %modifiedUserConfig;
our ($percentToNotifyForFailedFiles, $percentToNotifyForMissedFiles);

#------------------------------------------------- A -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: addCRONFallBack
# Objective				: This is to add the fallback logic for cron
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub addCRONFallBack {
	my $fc 			= getFileContents('/etc/crontab');
	my $cronentry 	= getIDriveFallBackCRONEntry();
	fileWrite('/etc/crontab', qq($fc\n$cronentry\n));
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : appendEndProcessInProgressFile.
# Objective               : This subroutine will append PROGRESS END string at the end of progress file.
# Modified By             : Abhishek Verma.
#*****************************************************************************************************/
sub appendEndProcessInProgressFile {
    open PROGRESS_DETAILS_FILE, ">>", $Configuration::progressDetailsFilePath or return "";
	print PROGRESS_DETAILS_FILE "\nPROGRESS END";
    close PROGRESS_DETAILS_FILE;
}

#****************************************************************************************************
# Subroutine Name         : appendErrorFileContents
# Objective               : This subroutine appends the contents of the error file to the output file
#							and deletes the error file.
# Modified By                : Deepak Chaurasia
#*****************************************************************************************************/
sub appendErrorFileContents
{
	my $errorDir = $_[0]."/";
	my @files_list = `ls '$errorDir'`;
	my $fileopen = 0;
	my $proxyErr = 0;

	chomp(@files_list);
	foreach my $file (@files_list) {
		chomp($file);
		if ( $file eq "." or $file eq "..") {
			next;
		}
		$file = $errorDir.$file;

		if (-s $file > 0){
			if ($fileopen == 0){
				$summaryError.="$lineFeed"."_______________________________________________________________________________________";
				$summaryError.="$lineFeed$lineFeed|Error Report|$lineFeed";
				$summaryError.="_______________________________________________________________________________________$lineFeed";
			}
			$fileopen = 1;
			open ERROR_FILE, "<", $file or traceLog($Locale::strings{'failed_to_open_file'}." $file. Reason $!");
			while(my $line = <ERROR_FILE>) {
				$summaryError.=$line;
				if ($line =~/.*(Proxy Authentication Required).*|.*(bad response from proxy).*/is){
					$proxyErr = 1;
				}
			}
			close ERROR_FILE;
		}
	}
	if ($proxyErr == 1){
		my $tokenMessage = $LS{'please_login_account_using_login_and_try'};
		#$tokenMessage =~ s/___login___/$Configuration::idriveScripts{'login'}/eg;
		$summaryError = "\nProxy Authentication Required or bad response from proxy. ".$tokenMessage.$lineFeed;
		my $pwdPath = getIDPWDFile();
		unlink($pwdPath);
	}
}

#*****************************************************************************************************
# Subroutine			: authenticateUser
# Objective				: Authenticate user credentials
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub authenticateUser {
	my $authCGI;
	my $uname = $_[0];
	my $upswd = $_[1];

	$authCGI = $Configuration::IDriveAuthCGI;
	$authCGI = $Configuration::IBackupAuthCGI	if ($Configuration::appType eq 'IBackup');
	my @responseData;
	my %params = (
		'host' => $authCGI,
		'method'=> 'POST',
		'data' => {
			'username' => $uname,
			'password' => $upswd
		}
	);

	my $res = requestViaUtility(\%params);

	# If cgi fails to provide any output then fallback to EVS commands for authentication
	unless ($res) {
		my $tmpPath = "$servicePath/$Configuration::mcUser/$Configuration::tmpPath";
		createDir($tmpPath);

		createUTF8File('STRINGENCODE',$upswd, ("$tmpPath/$_[0]\.tmp")) or
			retreat('failed_to_create_utf8_file');
		my @result = runEVS();

		if (($result[0]->{'STATUS'} eq Configuration::SUCCESS) and ($result[0]->{'MSG'} eq 'no_stdout')) {
			createUTF8File('VALIDATE',$_[0], ("$tmpPath/$_[0]\.tmp")) or
			retreat('failed_to_create_utf8_file');
			@responseData = runEVS('tree');

			if (defined($responseData[0]->{'MSG'}) && $responseData[0]->{'MSG'} =~ m/unable to reach the server/i) {
				retreat('please_check_internet_con_and_try');
			}
		}
		else {
			retreat(['Your account is under maintenance. Please contact support for more information',"."]) if ((defined($result[0]->{'desc'})) && ($result[0]->{'desc'} eq 'ACCOUNT IS UNDER MAINTENANCE'));
			retreat(ucfirst($result[0]->{'MSG'})) if (defined($result[0]->{'MSG'}));
			retreat(ucfirst($result[0]->{'desc'}));
		}
		rmtree("$servicePath/$Configuration::mcUser/$Configuration::tmpPath");
	}
	else {
		@responseData = parseEVSCmdOutput($res->{DATA}, 'login', 1);
	}
	return @responseData;
}

#*****************************************************************************************************
# Subroutine			: askProxyDetails
# Objective				: Ask user to provide proxy details.
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub askProxyDetails {
	display(["\n",'are_using_proxy_y_n', '? ', "\n"], 0);
	my $hasProxy = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($hasProxy) eq 'n') {
		setUserConfiguration('PROXYIP', '');
		setUserConfiguration('PROXYPORT', '');
		setUserConfiguration('PROXYUSERNAME', '');
		setUserConfiguration('PROXYPASSWORD', '');
		setUserConfiguration('PROXY', '');
		display(['your_proxy_has_been_disabled', "\n"],1) if (defined($_[0]));
	}
	else {
		display("\n",0);
		my $proxySIP = getAndValidate(['enter_proxy_server_ip', ': '], "ipaddress", 1);
		setUserConfiguration('PROXYIP',$proxySIP);

		my $proxySIPPort = getAndValidate(['enter_proxy_server_port',': '], "port_no", 1);
		setUserConfiguration('PROXYPORT',$proxySIPPort);

		display(['enter_proxy_server_username_if_set', ': '], 0);
		trim(my $proxySIPUname = getUserChoice());
		setUserConfiguration('PROXYUSERNAME',$proxySIPUname);

		my $proxySIPPasswd = '';
		if ($proxySIPUname ne ''){
			display(['enter_proxy_server_password_if_set', ': '], 0);
			trim($proxySIPPasswd = getUserChoice(0));
			$proxySIPPasswd = encryptString($proxySIPPasswd);
		}

		setUserConfiguration('PROXYPASSWORD',$proxySIPPasswd);

		my $proxyStr = "$proxySIPUname:$proxySIPPasswd\@$proxySIP:$proxySIPPort";
		setUserConfiguration('PROXY', $proxyStr);

		if (defined($_[0])) {
			# need to ping for proxy validation testing. .
			my @responseData = ();
			createUTF8File('PING')  or retreat('failed_to_create_utf8_file');
			@responseData = runEVS();
			if (($responseData[0]->{'STATUS'} eq Configuration::FAILURE) and ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Failed connect to .* Connection refused|Connection timed out|response code said error|407|execution_failed|kindly_verify_ur_proxy|No route to host|Could not resolve host/)) {

				retreat(["\n", 'kindly_verify_ur_proxy']) if (defined($_[1]));
				display(["\n", 'kindly_verify_ur_proxy']);
				askProxyDetails(@_,"NoRetry");

			}
			display(['proxy_details_updated_successfully', "\n"], 1) ;
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: askToCreateOrSelectADevice
# Objective				: This subroutine is used to ask usr to create or select a bucket
# Added By				: Anil Kumar
# Modified By     : Yogesh Kumar
#****************************************************************************************************/
sub askToCreateOrSelectADevice {
	tie(my %optionsInfo, 'Tie::IxHash',
		'create_new_backup_location' => \&createBucket,
		'select_from_existing_backup_locations' => sub {
			linkBucket('backup', $_[0], \&askToCreateOrSelectADevice);
		}
	);
	my @options = keys %optionsInfo;
	display(['multiple_backup_locations_are_configured', ". ", 'select_an_option', ": ", "\n"]);
	displayMenu('', @options);
	my $deviceSelection = getUserMenuChoice(scalar(@options));

	return $optionsInfo{$options[$deviceSelection - 1]}->($_[0]);
}

#*****************************************************************************************************
# Subroutine : addLogStat
# Objective  : Adds an entry to the log_summary.txt which contains job's status,
#              files, duration
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub addLogStat {
	unless (defined($_[0]) and defined($_[1])) {
		traceLog('both_job_path_and_log_summary_content_is_required');
		return 0;
	}

	my @now = localtime();
	#my $absLogStatFile = getCatfile($_[0], $Configuration::logDir, sprintf("$Configuration::logStatFile", ($now[4] + 1), ($now[5] += 1900)));
	my $absLogStatFile = getCatfile($_[0], sprintf("$Configuration::logStatFile", ($now[4] + 1), ($now[5] += 1900)));
	if (open(my $lsf, '>>', $absLogStatFile)) {
		my $lsc = JSON::to_json($_[1]);
		print $lsf ',';
		print $lsf substr($lsc, 1, (length($lsc) - 2));
		close($lsf);
	}
	else {
		traceLog(['unable_to_open_file', $absLogStatFile]);
		return 0;
	}
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : appendExcludedLogFileContents
# Objective               : This subroutine appends the contents of the excluded log file to the output file
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub appendExcludedLogFileContents
{
	my $excludeDirPath = $Configuration::jobRunningDir."/".$Configuration::excludeDir."/";
	my @files_list = `ls '$excludeDirPath'`;
	my $fileopen = 0;
	my $excludeLogSummary ='';
	chomp(@files_list);
	foreach my $file (@files_list) {
		Chomp(\$file);
		if ( $file eq "." or $file eq "..") {
			next;
		}
		$file = $excludeDirPath.$file;
		if (-e $file and -s $file > 0){
			if ($fileopen == 0){
				$excludeLogSummary.="$lineFeed"."_______________________________________________________________________________________";
				$excludeLogSummary.="$lineFeed$lineFeed|Excluded Files/Folders|$lineFeed";
				$excludeLogSummary.="_______________________________________________________________________________________$lineFeed$lineFeed";
			}
			$fileopen = 1;
			open EXCLUDED_FILE, "<", $file or traceLog($Locale::strings{'failed_to_open_file'}." $file. Reason $!");
			while(my $line = <EXCLUDED_FILE>) {
				$excludeLogSummary.=$line;
			}
			close EXCLUDED_FILE;
			unlink($file);
		}
	}
	if ($excludeLogSummary){
		$excludeLogSummary .= $lineFeed.$lineFeed;
	}
	if (-e $excludeDirPath and $excludeDirPath ne '/') {
		removeItems($excludeDirPath);
	}
	return $excludeLogSummary;
}
#------------------------------------------------- B -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: buildQuery
# Objective				: Build hash to http query string
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub buildQuery {
	my @qs;
	foreach my $key (keys %{$_[0]}) {
		push @qs, (urlEncode($key) . '=' . urlEncode($_[0]->{$key}));
	}
	if (exists $_[0]->{'ver'} and $_[0]->{'ver'} eq 'evs005') {
		return ('?' . join("&", @qs));
	}
	else {
		return join("&", @qs);
	}
}

#*****************************************************************************************************
# Subroutine			: backupTypeCheck
# Objective             : This subroutine checks if backup type is either Mirror or Relative
# Added By              : Dhritikana
#****************************************************************************************************/
sub backupTypeCheck {
	my $backupPathType = getUserConfiguration('BACKUPTYPE');
	my $relative;
	$backupPathType = lc($backupPathType);
	if ($backupPathType eq "relative") {
		$relative = 0;
	}else{
		$relative = 1;
	}
	return $relative;
}

#------------------------------------------------- C -------------------------------------------------#

############################################# START

#****************************************************************************************************
# Subroutine Name		: checkForRunningJobsInOtherUsers.
# Objective				: Check all the running jobs w.r.t other users in the service path.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#*****************************************************************************************************/
sub checkForRunningJobsInOtherUsers {
	# to get all jobs that needs to kill from different user profiles.
	my @idriveUsersList = ();
	#Getting IDrive user list
	@idriveUsersList = getIDriveUserList();
	if (scalar @idriveUsersList > 0) {
		foreach my $usrProfileDir (@idriveUsersList)  {
			next if (getUsername() eq basename($usrProfileDir));
			my @userJobpath = (qq($usrProfileDir/$Configuration::userProfilePaths{'backup'}/),
								qq($usrProfileDir/$Configuration::userProfilePaths{'restore'}/),
								qq($usrProfileDir/$Configuration::userProfilePaths{'localbackup'}),
								qq($usrProfileDir/$Configuration::userProfilePaths{'archive'}/));

			for(my $j=0; $j<=$#userJobpath; $j++) {
				my $pidPath =  getCatfile($userJobpath[$j], "pid.txt");
				if (isFileLocked($pidPath)) {
					# message needs to be reviewed and changed.
					#display("One or more backup/express backup/restore/archive cleanup jobs are in process with respect to Others users. Please make sure those are completed and try again.", 1);
					return 0;
				}
			}
		}
	}

	return 1;
}

#****************************************************************************************************
# Subroutine Name		: getIDriveUserList
# Objective				: Getting IDrive user list from service directory.
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#*****************************************************************************************************/
sub getIDriveUserList {
	my @idriveUsersList 	= ();
	my $usrProfileDirPath	= getCatfile(getServicePath(), $Configuration::userProfilePath);
	return @idriveUsersList unless(-d $usrProfileDirPath);

	if (opendir(MCUSERDIR, $usrProfileDirPath)) {
		foreach my $userName (readdir(MCUSERDIR)) {
			next if ($userName =~ /^\.\.?$/);

			my $mcUserProfileDir =  getCatfile(getServicePath(), $Configuration::userProfilePath, $userName);
			next unless (-d $mcUserProfileDir);

			if (opendir(DIR, $mcUserProfileDir)) {
				foreach my $userName (readdir(DIR)) {
					next if ($userName =~ /^\.\.?$/ || $userName eq ".trace");

					my $idriveUserProfileDir 	= "$mcUserProfileDir/$userName";
					$idriveUserProfileDir		=  getCatfile($mcUserProfileDir, $userName);
					push(@idriveUsersList, $idriveUserProfileDir) if (-d $idriveUserProfileDir);
				}
			}
		}
	}

	return @idriveUsersList;
}

############################################################ END


#*****************************************************************************************************
# Subroutine			: calculateBackupsetDirectorySize
# Objective				: Calculate backup set size
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub calculateBackupsetDirectorySize {
	my $backupsizelock	= getBackupsetSizeLockFile($_[0]);

	open(my $lockfh, ">>", $backupsizelock);
	return 1 if (!flock($lockfh, LOCK_EX|LOCK_NB));

	my $backuptype 		= $_[0];
	return 0 unless($backuptype);

	my $backupsizefile	= getCatfile(getUsersInternalDirPath($_[0]), $Configuration::backupsizefile);

	my $backupsetfile	= getCatfile(getUsersInternalDirPath($backuptype), $Configuration::backupsetFile);
	return 0 if (!-f $backupsetfile || !-s $backupsetfile);

	if (!open(BACKUPLISTFH, $backupsetfile)) {
		traceLog($Locale::strings{'failed_to_open_file'} . ": $backupsetfile, Reason: $!");
		return 0;
	}
	close(BACKUPLISTFH);

RERUNCALC:
	my %backupsetsizes 	= ((-f $backupsizefile && -s $backupsizefile)? %{JSON::from_json(getFileContents($backupsizefile))} : ());
	my $backupsetdata	= getFileContents($backupsetfile, 'array');
	my $prevbkpsetmodtm	= ((-f $backupsizefile)? stat($backupsizefile)->mtime : 0);

	loadUserConfiguration();
	loadFullExclude();
	loadPartialExclude();
	loadRegexExclude();
	my $showhidden = getUserConfiguration('SHOWHIDDEN');
	# calculate file size and write to the file
	my ($dirsizes, $filecount, $filename) = (0, 0, '');

	for my $i (0 .. $#{$backupsetdata}) {
		unlink($backupsizelock) if(defined($_[1]) && !isFileLocked($_[1]));
		exit(0) unless(-f $backupsizelock);
		$filename		= @{$backupsetdata}[$i];
		chomp($filename);
		next if ($filename eq '');
		next if ($backupsetsizes{$filename} && $backupsetsizes{$filename}{'size'} != -1);

		if (!-d $filename) {
			if (-f $filename) {
				$backupsetsizes{$filename} = {'ts' => mktime(localtime), 'size' => getFileSize($filename, \$filecount), 'filecount' => (isThisExcludedItemSet($filename . '/', $showhidden)? 'EX' : 'NA'), 'type' => 'f'};
				$filecount = 0;
			}
			else {
				$backupsetsizes{$filename} = {'ts' => mktime(localtime), 'size' => 0, 'filecount' => 'NA', 'type' => 'u'};
			}
		}
		else {
			$dirsizes		= getDirectorySize($filename, \$filecount);
			$backupsetsizes{$filename} = {'ts' => mktime(localtime), 'size' => $dirsizes, 'filecount' => $filecount, 'type' => 'd'};
			$filecount = 0;
		}

		fileWrite($backupsizefile, JSON::to_json(\%backupsetsizes));
	}

	goto RERUNCALC if ($prevbkpsetmodtm != 0 && $prevbkpsetmodtm != stat($backupsizefile)->mtime);

	# delete lock file
	unlink($backupsizelock) if (-f $backupsizelock);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkAndRenameFileWithStatus
# Objective				: This subroutine check and rename file with status
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkAndRenameFileWithStatus {
	my $jobDir		 = $_[0];
	my $isSummary	 = 0;
	my ($considered,$success,$synced,$failed,$status,$logFile);
	my $logPidFilePath = $jobDir."/".$Configuration::logPidFile;

	if (-e $logPidFilePath){
		open FILE, "<", $logPidFilePath or (traceLog($Locale::strings{'failed_to_open_file'}.":$logPidFilePath. Reason:$!") and die);
		chomp($logFile = <FILE>);
		close FILE;
		unlink($logPidFilePath);
	}
	return if (!defined($logFile) or !-e $logFile);

	my @logContent = `tail -n10 '$logFile'`;
	foreach (@logContent) {
		my $line = $_;
		if (!$isSummary and $line =~ m/Summary:/) {
			$isSummary = 1;
		}
		elsif ($isSummary and $line =~ m/considered/){
			$considered = (split(":", $line))[1];
			Chomp(\$considered);
		}
		elsif ($isSummary and $line =~ m/(backed|restored)/){
			$success = (split(":", $line))[1];
			Chomp(\$success);
		}
		elsif ($isSummary and $line =~ m/already present/){
			$synced = (split(":", $line))[1];
			Chomp(\$synced);
		}
		elsif ($isSummary and $line =~ m/failed/){
			$failed = (split(":", $line))[1];
			Chomp(\$failed);
		}
	}

	if ($isSummary){
		if ($failed > 0 or $considered == 0){
			$status = $Locale::strings{'failure'};
		}
		elsif ($considered == ($success+$synced)){
			$status = $Locale::strings{'success'};
		}
	}
	if (!$isSummary or !defined($status)){
		$status = $Locale::strings{'aborted'};
	}
	my $finalOutFile = $logFile;
	$finalOutFile =~ s/_Running_/_$status\_/;
	system("mv '$logFile' '$finalOutFile'");
	if (loadAppPath() and loadServicePath() and loadUsername()) {
		if ($logFile =~ m/_Running_/){
			my @logPath = split("_Running_",$logFile);
			my $tempOutputFilePath = (split("/", $logPath[0]))[-1];
			my %logStat = (
				(split('_', basename($tempOutputFilePath)))[0] => {
					'datetime' =>  strftime('%d/%m/%Y %H:%M:%S', localtime($tempOutputFilePath+15)),
					'duration' => "--",
					'filescount' => ($considered)?$considered:"--",
					'status' => $status."_".$logPath[1]
				}
			);
			addLogStat($jobDir, \%logStat);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateServerRoot
# Objective				: check and update if server root field is empty in configuration file
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub checkAndUpdateServerRoot {
	my $serverRoot;
	if (getUserConfiguration('DEDUP') eq 'on' && (!getUserConfiguration('SERVERROOT') || getUserConfiguration('SERVERROOT') eq '')) {
		my @devices = fetchAllDevices();
		my $uniqueID = getMachineUID() or retreat('unable_to_find_mac_address');
		foreach(@devices) {
			next if ($muid ne $_->{'uid'});
			if ($_->{'server_root'} ne '') {
				setUserConfiguration('SERVERROOT', $_->{'server_root'});
				saveUserConfiguration() or retreat('failed_to_save_user_configuration');
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: checkCRONServiceStatus
# Objective				: This is to check IDrive CRON service status
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkCRONServiceStatus {
	return CRON_RUNNING if (defined($_[0]) && -f $_[0]);
	return CRON_NOTRUNNING unless(-f $Configuration::cronlockFile);

	# As a double check, verify shared lock file
	return CRON_RUNNING if (!open(my $lockfh, ">>", $Configuration::cronlockFile) && $Configuration::mcUser ne 'root');
	return CRON_RUNNING unless(flock($lockfh, LOCK_EX|LOCK_NB));

	unlink($Configuration::cronlockFile);
	return CRON_NOTRUNNING;
}

#*****************************************************************************************************
# Subroutine			: coloredFormat
# Objective				: format text in the given color
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub coloredFormat {
	unless (defined &colored) {
		my $cmd = "$Configuration::perlBin -e 'use Term::ANSIColor;'";
		my $o = `$cmd 2>&1`;
		if ($? == 0) {
			use Term::ANSIColor;
		}
	}

	my $text  = $_[0];
	if (defined &colored) {
		my $color = 'black';
		my $bg    = 'yellow';
		if ((lc($text) eq 'on') or (lc($text) eq 'enabled') or (looks_like_number($text) and $text == 1)) {
			$color = 'green';
			$bg    = 'black';
		}
		elsif ((lc($text) eq 'off') or (lc($text) eq 'disabled') or (looks_like_number($text) and $text == 0)) {
			$color = 'red';
			$bg    = 'black';
			$text  = 'disabled' if (looks_like_number($text) and $text == 0);
		}

		$color = $_[2] if (defined $_[2]);
		$bg    = $_[3] if (defined $_[3]);

		$text = colored($text, "bold $color on_$bg");
		if (defined $_[1]) {
			my $sc = $_[1];
			$sc =~ s/s//g;
			$sc = $sc + 14;
			$sc .= 's';
			$text = sprintf("%-$sc", $text);
		}
	}
	else {
		if (defined $_[1]) {
			$text = sprintf("%-$_[1]", $text);
		}
	}

	return $text;
}

#*****************************************************************************************************
# Subroutine			: Chomp
# Objective				: Remove white-space at beginning & end
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub Chomp{
	chomp(${$_[0]});
	${$_[0]} =~ s/^[\s\t]+|[\s\t]+$//g;
}

#*****************************************************************************************************
# Subroutine Name         : checkPreReq
# Objective               : This function will check if restore/backup set file exists and filled.
#							Otherwise it will report error and terminate the script execution.
# Added By                : Abhishek Verma.
# Modified by             : Senthil Pandian
#*****************************************************************************************************
sub checkPreReq {
	my ($fileName,$jobType,$taskType,$reason) = @_;
	my $userName = getUsername();
	my $errorDir = $Configuration::jobRunningDir."/".$Configuration::errorDir;
	my $pidPath  = $Configuration::jobRunningDir."/".$Configuration::pidFile;
	my $isEmpty = 0;

	if ((!-e $fileName) or (!-s $fileName)) {
		$Configuration::errStr = "Your $jobType"."set is empty. ".$LS{'please_update'}."\n";
		$isEmpty = 1;
	}
	elsif (-s $fileName > 0 && -s $fileName <= 50){
		my $outfh;
		if (!open($outfh, "< $fileName")) {
			$Configuration::errStr = $LS{'failed_to_open_file'}.":$fileName, Reason:$!";
			traceLog($Configuration::errStr);
			$isEmpty = 1;
		}
		my $buffer = <$outfh>;
		close $outfh;
		Chomp(\$buffer);
		if ($buffer eq ''){
			$Configuration::errStr = "Your $jobType"."set is empty. ".$LS{'please_update'}."\n";
			$isEmpty = 1;
		}
		close($outfh);
	}

	# if ($isEmpty){
		# print $Configuration::errStr if ($taskType eq 'manual');
		# my $subjectLine = "$taskType $jobType Status Report "."[$userName]"." [Failed $jobType]";
		# $Configuration::status = Configuration::FAILURE;
		# sendMail($taskType,$jobType,$subjectLine,$reason,$fileName);
		# rmtree($errorDir);
		# unlink $pidPath;
		# exit 0;
	# }
	return $isEmpty;
}

#*****************************************************************************************************
# Subroutine			: checkExitError
# Objective				: This function will display the proper error message if evs error found in Exit argument.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkExitError {
	my $errorline = "idevs error";
	my $individual_errorfile   = $_[0];
	my $userJobPaths 		   = $_[1];
	my $needToSkippTermination = 0;
	$needToSkippTermination = 1 if(defined($_[2])); #Added to skip termination for archive cleanup.
	unless(-e $individual_errorfile or -s $individual_errorfile>0) {
		return 0;
	}
	#check for retry attempt
	if (!open(TEMPERRORFILE, "< $individual_errorfile")) {
		traceLog($LS{'failed_to_open_file'}.":$individual_errorfile, Reason:$! \n", __FILE__, __LINE__);
		return 0;
	}

	my @linesBackupErrorFile = <TEMPERRORFILE>;
	close TEMPERRORFILE;
	chomp(@linesBackupErrorFile);
	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;

		if ($linesBackupErrorFile[$i] eq "" or $linesBackupErrorFile[$i] =~ m/$errorline/){
			next;
		}

		foreach my $exitErrorMessage (@Configuration::errorArgumentsExit)
		{
			if ($linesBackupErrorFile[$i] =~ m/$exitErrorMessage/)
			{
				#Avoiding termination for archive cleanup when EVS connection timed out & retrying.
				if(!$needToSkippTermination or $exitErrorMessage !~ m/connection timed out/i) {
					$Configuration::errStr  = $LS{'operation_could_not_be_completed_reason'}.$exitErrorMessage.".";
					traceLog($Configuration::errStr, __FILE__, __LINE__);
					#kill evs and then exit
					my $username = getUsername();
					my $jobTerminationScript = getScript('job_termination', 1);
					system("$Configuration::perlBin $jobTerminationScript 1>/dev/null 2>/dev/null \'$userJobPaths\' \'$username\'");
					return "1-$Configuration::errStr";
				}
			}
		}
	}
	return 0;
}

#****************************************************************************************************
# Subroutine Name         : createBackupSetFiles1k.
# Objective               : This function will generate 1000 Backetupset Files
# Added By                : Pooja Havaldar
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub createBackupSetFiles1k {
	my $filesOnlyFlag = $_[0];
	$backupfilecount++;
	my $filesOnly	  		= $Configuration::jobRunningDir."/".$Configuration::filesOnly;
	my $noRelativeFileset   = $Configuration::jobRunningDir."/".$Configuration::noRelativeFileset;
	my $relativeFileset     = $Configuration::jobRunningDir."/".$Configuration::relativeFileset;
	my $relative = backupTypeCheck();

	if ($relative == 0) {
		if (defined($filesOnlyFlag) and $filesOnlyFlag eq "FILESONLY") {
			$Configuration::filesOnlyCount++;
			#print FD_WRITE "$BackupsetFile_Only ".NORELATIVE." $current_source\n";
			print FD_WRITE "$current_source' '".NORELATIVE."' '$BackupsetFile_Only\n";
			$BackupsetFile_Only =  $filesOnly."_".$Configuration::filesOnlyCount;
			close NEWFILE;
			if (!open NEWFILE, ">", $BackupsetFile_Only) {
				traceLog($Locale::strings{'failed_to_open_file'}."filesOnly in 1k: $filesOnly to write, Reason: $!. $lineFeed", __FILE__, __LINE__);
				return 0;
			}
			chmod $Configuration::filePermission, $BackupsetFile_Only;
		}
		else
		{
			#print FD_WRITE "$BackupsetFile_new#".RELATIVE."#$current_source\n";
			print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
			traceLog("\n in NORELATIVE BackupsetFile_new = $BackupsetFile_new", __FILE__, __LINE__);
			$BackupsetFile_new = $noRelativeFileset."$Configuration::noRelIndex"."_$backupfilecount";

			close FH;
			if (!open FH, ">", $BackupsetFile_new) {
				traceLog($Locale::strings{'failed_to_open_file'}."BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!. $lineFeed", __FILE__, __LINE__);
				return 0;
			}
			chmod $Configuration::filePermission, $BackupsetFile_new;
		}
	}
	else {
		#print FD_WRITE "$BackupsetFile_new ".RELATIVE." $current_source\n";
		print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
		$BackupsetFile_new = $relativeFileset."_$backupfilecount";

		close NEWFILE;
		if (!open NEWFILE, ">", $BackupsetFile_new){
			traceLog($Locale::strings{'failed_to_open_file'}."BackupsetFile_new in 1k: $BackupsetFile_new to write, Reason: $!. $lineFeed");
			return 0;
		}
		chmod $Configuration::filePermission, $BackupsetFile_new;
	}

	autoflush FD_WRITE;
	$filecount = 0;

	if ($backupfilecount%15 == 0){
		sleep(1);
	}
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	createBackupTypeFile
# Objective               :	Create files respective to Backup types (relative or no relative)
# Added By                : Dhritikana
#********************************************************************************************************
sub createBackupTypeFile {
	#opening info file for generateBackupsetFiles function to write backup set information and for main process to read that information
	my $info_file 			= $Configuration::jobRunningDir."/".$Configuration::infoFile;
	my $noRelativeFileset   = $Configuration::jobRunningDir."/".$Configuration::noRelativeFileset;
	my $filesOnly	        = $Configuration::jobRunningDir."/".$Configuration::filesOnly;
	my $relativeFileset     = $Configuration::jobRunningDir."/".$Configuration::relativeFileset;

	if (!open(FD_WRITE, ">", $info_file)){
		traceLog($LS{'failed_to_open_file'}.":$info_file. Reason:$!", __FILE__, __LINE__);
		return 0;
	}
	chmod $Configuration::filePermission, $info_file;
	close FD_WRITE; #Needs to be removed

	my $relative = backupTypeCheck();
	#Backupset File name for mirror path
	if ($relative != 0) {
		$BackupsetFile_new =  $relativeFileset;
		if (!open NEWFILE, ">>", $BackupsetFile_new) {
			traceLog($LS{'failed_to_open_file'}.":$BackupsetFile_new. Reason:$!", __FILE__, __LINE__);
			return 0;
		}
		chmod $Configuration::filePermission, $BackupsetFile_new;
	}
	else {
		#Backupset File Name only for files
		$BackupsetFile_Only = $filesOnly;
		if (!open NEWFILE, ">>", $BackupsetFile_Only) {
			traceLog($LS{'failed_to_open_file'}.":$filesOnly. Reason:$!", __FILE__, __LINE__);
			return 0;
		}
		chmod $Configuration::filePermission, $BackupsetFile_Only;
		$BackupsetFile_new = $noRelativeFileset;
	}
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : changeSizeVal.
# Objective               : Changes the size op value based on terminal size change.
# Modified By             : Dhritikana, Senthil pandian.
#*****************************************************************************************************/
sub changeSizeVal {
	$latestCulmn = `tput cols`;
	chomp($latestCulmn);
	if ($latestCulmn < 100) {
		$progressSizeOp = 2;
	} else {
		$progressSizeOp = 1;
	}
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateServicePath
# Objective				: check .serviceLocation file if exist then try to create servicePath
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub checkAndUpdateServicePath {
	if (loadServicePath()) {
		return 1;
	}
	else {
		my $serviceLocation = $appPath."/" . $Configuration::serviceLocationFile;
		return 0 if (!open(my $sp, '<:encoding(UTF-8)', $serviceLocation));
		my $s = <$sp> || '';
		close($sp);
		unless ($s eq '') {
			chomp($s);
			my $ret;
			if($Configuration::callerEnv ne 'BACKGROUND'){
				$Configuration::callerEnv = 'BACKGROUND';
				$ret = createDir($s);
				$Configuration::callerEnv = '' ;
			} else {
				$ret = createDir($s);
			}

			if ($ret eq 1) {
				display(["Service directory ", "\"$s\""," created successfully." ],1);
				$servicePath = $s;
				return 1;
			}
			#display(["Service Path ", "\"$s\""," does not exists." ],1);
		}
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: createDir
# Objective				: Create a directory
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createDir {
	$_[0] =~ s/\/$//;
	my @parentDir = fileparse($_[0]);
	my $recursive = 0;
	if (defined($_[1])) {
		$recursive = $_[1];
	}
	unless (-d $parentDir[1]) {
		if ($recursive) {
			chop($parentDir[1]) if ($parentDir[1] =~/\/$/);
			return 0 unless (createDir($parentDir[1], $recursive));
		}
		else {
			display(["$parentDir[1]: ", 'no_such_directory_try_again']);
			return 0;
		}
	}
	unless (-w $parentDir[1]) {
		display(['cannot_open_directory', " $parentDir[1]", 'permission_denied']);
		return 0;
	}
	if (mkdir($_[0], 0777)) {
		chmod $Configuration::filePermission, $_[0];
		return 1;
	}
	return 1 if ($! eq 'File exists');

	display(["$_[0]: ", $!]);

	return 0;
}

#*****************************************************************************************************
# Subroutine			: createPvtSCH
# Objective				: This is to create getIDPVTSCH file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub createPvtSCH {
	copy(getIDPVTFile(), getIDPVTSCHFile());
	changeMode(getIDPVTFile());
	changeMode(getIDPVTSCHFile());
}

#*************************************************************************************************
# Subroutine Name		: createLogFiles
# Objective			: Creates the Log Directory if not present, Creates the Error Log and
#					Output Log files based on the timestamp when the backup/restore
#					operation was started, Clears the content of the Progress Details file
# Added By			:
# Modified By 		   	: Abhishek Verma, Yogesh Kumar - Now the logfile name will contain epoch time and job status like (Success, Failure, Aborted) - 17/5/2017
#**************************************************************************************************
sub createLogFiles {
	my $jobType = $_[0];
	my $taskType = (defined($_[1]))?$_[1]:'';
	our $progressDetailsFileName = "PROGRESS_DETAILS";
	our $outputFileName = $jobType;
	our $errorFileName = $jobType."_ERRORFILE";
	my $logDir   = $Configuration::jobRunningDir."/".$Configuration::logDir;
	my $errorDir = $Configuration::jobRunningDir."/ERROR";
	my $ifRetainLogs = getUserConfiguration('RETAINLOGS');
	my $logPidFilePath = getCatfile($Configuration::jobRunningDir, $Configuration::logPidFile);

	if (!$ifRetainLogs) {
		chmod $Configuration::filePermission, $logDir;
		rmtree($logDir);
	}

	if (!-d $logDir)
	{
		mkdir $logDir;
		chmod $Configuration::filePermission, $logDir;
	}

#=====================================================================================================================
# TBE : ENH-003 TIMESTAMP fix to YYYY-MM-DD_HH-MM-SS
#	my $currentTime = localtime;
	my $currentTime = time;#This function will give the current epoch time.
	#previous log file name use to be like 'BACKUP Wed May 17 12:34:47 2017_FAILURE'.Now log name will be '1495007954_SUCCESS'.
# Correct timestamp string : YYYY-MM-DD_HH-MM-SS
	$currentTime = Taryck::TS2ISO($currentTime);
#=====================================================================================================================
	@startTime = localtime();
	$Configuration::outputFilePath = getCatfile($logDir, $currentTime."_Running_".$taskType);
	$Configuration::errorFilePath  = $errorDir."/".$errorFileName;
	$Configuration::progressDetailsFilePath = $Configuration::jobRunningDir."/".$progressDetailsFileName;

	#Keeping current log file name in logpid file
	fileWrite($logPidFilePath, $Configuration::outputFilePath) or traceLog('failed_to_open_file');
	chmod $Configuration::filePermission, $logPidFilePath;
}

#****************************************************************************************************
# Subroutine Name         : createUpdateBWFile.
# Objective               : Create or update bandwidth throttle value file(.bw.txt).
# Added By                : Avinash Kumar.
# Modified By		      : Dhritikana, Yogesh Kumar
#*****************************************************************************************************/
sub createUpdateBWFile {
	my $bwThrottle = defined $_[0]? $_[0]:getUserConfiguration('BWTHROTTLE');
	my $bwPath     = getUserProfilePath()."/bw.txt";
	fileWrite($bwPath, $bwThrottle) or traceLog('failed_to_open_file');
	chmod $Configuration::filePermission, $bwPath;
}

#*****************************************************************************************************
# Subroutine			: createUserDir
# Objective				: Create user profile directories
# Added By				: Yogesh Kumar
# Modified By           : Senthil Pandian
#****************************************************************************************************/
sub createUserDir {
	display(["\n",'creating_user_directories'],1);
	my $err = ();
	for my $path (keys %Configuration::userProfilePaths) {
		my $userPath = getUsersInternalDirPath($path);
		createDir($userPath,1);
	}
	display(['user_directory_has_been_created_successfully',"\n"],1);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: createUTF8File
# Objective				: Build valid evs parameters
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub createUTF8File {
	loadServerAddress();
	my $evsOP = $_[0];
	my $evsPattern;
	my $thirdParam = 0;
	unless(reftype(\$evsOP) eq 'SCALAR'){
		$evsPattern = $Configuration::evsAPIPatterns{$_[0]->[0]};
		$utf8File   = $_[0]->[1];
		$thirdParam = 1 if(defined($_[0]->[2]));
	}
	elsif (-d getUserProfilePath()) {
		$utf8File = (getUserProfilePath() ."/$Configuration::utf8File"."_".lc($evsOP));
		$evsPattern = $Configuration::evsAPIPatterns{$evsOP};
	}
	else {
		$utf8File = "$servicePath/$Configuration::tmpPath/$Configuration::utf8File"."_".lc($evsOP);
		$evsPattern = $Configuration::evsAPIPatterns{$evsOP};
	}

	my $encodeString = 0;
	$encodeString = 1 if ($evsPattern =~ /--string-encode/);

	my @ep = split(/\n/, $evsPattern);

	my $tmpInd;
	for my $pattern (@ep) {
		my @kNames = $pattern =~ /__[A-Za-z0-9]+__/g;
		for(@kNames) {
			if ($_ =~ /__ARG(.*?)__/) {
				$tmpInd = $1;
				#retreat('insufficient_arguments') unless (defined($_[$tmpInd]));
				$pattern =~ s/$_/$_[$tmpInd]/g;
				next;
			}

			$_ =~ s/__//g;
			my $func = \&{$_};
			my $v = &$func();
			$pattern =~ s/__$_\_\_/$v/g;
		}
	}

	my $evsParams 		= join("\n", @ep);
	my $isDedup  	   	= getUserConfiguration('DEDUP');
	my $backupLocation  = getUserConfiguration('BACKUPLOCATION');
	# Added to handle ITEMSTATUS for archive & remote validation
	if($evsOP eq 'FILEVERSION' or $thirdParam) {
		$backupLocation = getUserConfiguration('RESTOREFROM');
	}

	if ($isDedup eq "on" and $backupLocation) {
		if ($evsPattern !~ /(--list-device|--nick-update|--link-bucket|--create-bucket)/){
			my $deviceID 		= (split("#",$backupLocation))[0];
			$evsParams .= "\n--device-id=$deviceID";
		}
	}
	unless ($encodeString) {
		unless ($evsParams =~ /--password-file/) {
			$evsParams .= "\n--password-file=" . getIDPWDFile();
		}
		my $pvtKey = getIDPVTFile();
		if (-e $pvtKey) {
			$evsParams .= "\n--pvt-key=".$pvtKey;
		}
		my $proxyStr = getUserConfiguration('PROXY');
		if ($proxyStr){
			my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
			my @UnP = split(/\:/, $uNPword);
			if (scalar(@UnP) >1 and $UnP[0] ne "") {
				$UnP[1] = ($UnP[1] ne '')?decryptString($UnP[1]):$UnP[1];
				foreach ($UnP[0], $UnP[1]) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				$uNPword = join ":", @UnP;
				$proxyStr = "$uNPword\@$ipPort";
			}
			$evsParams .= "\n--proxy=$proxyStr";
		}
		$evsParams .= "\n--encode";
	}

	if (open(my $fh, '>', $utf8File)) {
		print $fh $evsParams;
		close($fh);
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: createCRONLink
# Objective				: This subroutine creates link to cron file to a common path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub createCRONLink {
	my $cronpath = getScript('cron', 1);
	`ln -s $cronpath '$Configuration::cronLinkPath'`;
	chmod($Configuration::execPermission, $Configuration::cronLinkPath);
}

#*****************************************************************************************************
# Subroutine			: checkRetryAndExit
# Objective				: This subroutine checks for retry count and exits if retry exceeded
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkRetryAndExit {
	my $choiceRetry = shift;
	my $newLine		= shift;
	display('') if $newLine;
	retreat('your_max_attempt_reached') if ($choiceRetry == $Configuration::maxChoiceRetry);
}

#*****************************************************************************************************
# Subroutine			: updateUserLoginStatus
# Objective				: This is to create cache folder for storing the user information.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub updateUserLoginStatus {
	# get user.txt full file name
	my $filename = getUserFile();

	# create cache directory if does not exist
	createDir(getCachedDir());

	my %loginData= ();

	###########################################
	# load user.txt content
	if (-e $filename){
		my $fc = "";
		$fc = getFileContents($filename);
		Chomp(\$fc);

		if ($fc =~ m/^\{/) {
			%loginData	= %{JSON::from_json($fc)};
		}
	}
	if ($_[1] == 0 and $loginData{$Configuration::mcUser}){
		return 0;
	}
	###########################################
	$loginData{$Configuration::mcUser} {'userid'} = $_[0];
	$loginData{$Configuration::mcUser} {'isLoggedin'} = $_[1];
	fileWrite($filename, JSON::to_json(\%loginData));
	chmod $Configuration::filePermission, $filename;

	# Updating the logged in user status to cron
	my $status = ($_[1])?'ACTIVE':'INACTIVE';
	loadCrontab();
	createCrontab('otherInfo', {'settings' => {'status' => $status, 'lastActivityTime' => time()}});
	setCrontab('otherInfo',  'settings', {'status' => $status} , ' ');
	saveCrontab();

	display(["\n", "\"$_[0]\"", 'is_logged_in_successfully', '.'], 1) if ($_[1]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: startJob
# Objective				: This is used to start the job immediately from scheduler
# Added By				: Anil Kumar
#****************************************************************************************************/
sub startJob {
	#start job immediately

	my $scriptName = $_[0];
	my $scriptArgs = $_[1];

	my $cmd = ("$Configuration::perlBin " . getScript($scriptName, 1));
	$cmd   .= (" 1>/dev/null 2>/dev/null $scriptArgs &");

	my %status;
	unless (system($cmd) == 0) {
		$status{'status'} = Configuration::FAILURE
	}
	else {
		$status{'status'} = Configuration::SUCCESS
	}

	return %status;
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateClientRecord
# Objective				: This is to check and update the client entry for stats
# Added By				: Anil Kumar
#****************************************************************************************************/
sub checkAndUpdateClientRecord {
	my $freshInstallFile = "$appPath/freshInstall";

	if (-e $freshInstallFile) {
		if (!open(FH, "<", $freshInstallFile)) {
			traceLog("Not able to open $freshInstallFile, Reason:$!");
			return;
		}
		my @idriveUsers = <FH>;
		close FH;
		chomp(@idriveUsers);
		foreach my $user (@idriveUsers) {
			return if ($_[0] eq $user);
		}
	}

	my $isUpdated = updateUserDetail($_[0],$_[1],1);
	if ($isUpdated){
		if (!open(FH, ">>", $freshInstallFile)) {
			return 0;
		}
		print FH $_[0]."\n";
		close FH;
		chmod $Configuration::filePermission, $freshInstallFile;
	}
}

#*****************************************************************************************************
# Subroutine			: changeMode
# Objective				: Change directory permission to 0777
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub changeMode {
	return `chmod -R 0777 '$_[0]' 2>/dev/null`;
}

#*****************************************************************************************************
# Subroutine			: createBucket
# Objective				: This subroutine is used to create a bucket
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createBucket {
	my $deviceName = getAndValidate(['enter_your_backup_location_optional', ': '], "backup_location", 1);
	if ($deviceName eq '') {
		$deviceName = $Configuration::hostname;
		$deviceName =~ s/[^a-zA-Z0-9_-]//g;
	}
	display('setting_up_your_backup_location',1);
	createUTF8File('CREATEBUCKET',$deviceName) or retreat('failed_to_create_utf8_file');
	my @result = runEVS('item');

	if ($result[0]{'STATUS'} eq Configuration::SUCCESS) {
		display(['your_backup_to_device_name_is',(" \"" . $result[0]{'nick_name'} . "\".")]);
		setUserConfiguration('SERVERROOT', $result[0]{'server_root'});
		setUserConfiguration('BACKUPLOCATION',
			($Configuration::deviceIDPrefix . $result[0]{'device_id'} . $Configuration::deviceIDSuffix .
				'#' . $result[0]{'nick_name'}));
		loadNotifications() and setNotification('register_dashboard') and saveNotifications();
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: createNotification
# Objective				: create file notification.json
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createNotification {
	my $nf = getNotificationFile();
	unless (-e $nf and !-z $nf) {
		if (open(my $fh, '>', $nf)) {
			map{$notifications{$_} = $Configuration::notificationsSchema{$_}} keys %Configuration::notificationsSchema;
			print $fh JSON::to_json(\%notifications);
			close($fh);
			return 1;
		}
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: createCrontab
# Objective				: create file crontab.json
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createCrontab {
	my $nf = getCrontabFile();
	my $jobType  = shift  || retreat('crontabs_jobname_is_required');
	my $jobName  = shift  || retreat('crontab_title_is_required');
	my $ctab     = shift;

	$jobType = $Configuration::availableJobsSchema{$jobType}{'type'} if (exists $Configuration::availableJobsSchema{$jobType});
	$jobType = 'backup' if ($jobType eq 'express_backup'); # TODO: IMPORTANT to review this statement again.

	#loadCrontab();
	if ($jobType eq "otherInfo") {
		$crontab{$Configuration::mcUser}{$username}{$jobType} = $jobName;
		return 1;
	}
	unless (exists $crontab{$Configuration::mcUser}{$username}{$jobType}{$jobName}) {
		$ctab = \%{deepCopyEntry(\%Configuration::crontabSchema)} unless (defined $ctab);
		if (open(my $fh, '>', $nf)) {
			$crontab{$Configuration::mcUser}{$username}{$jobType}{$jobName} = $ctab;
			print $fh encryptString(JSON::to_json(\%crontab));
			close($fh);
			chmod($Configuration::filePermission, $nf);
			return 1;
		}
		else {
			display(['failed_to_open_file', " crontab. $!"]);
		}
		return 0;
	}
	elsif (defined $ctab) {
		if (open(my $fh, '>', $nf)) {
			$crontab{$Configuration::mcUser}{$username}{$jobType}{$jobName} = deepCopyEntry(\%Configuration::crontabSchema, $ctab);
			print $fh encryptString(JSON::to_json(\%crontab));
			close($fh);
			chmod($Configuration::filePermission, $nf);
			return 1;
		}
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: createEncodePwdFiles
# Objective				: Encode user password
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createEncodePwdFiles {
	createUTF8File('STRINGENCODE', $_[0], getIDPWDFile()) or (retreat('failed_to_create_utf8_file'));
	my @responseData = runEVS('Encoded');
	if ($responseData[0]->{'STATUS'} eq Configuration::FAILURE) {
		retreat(ucfirst($responseData[0]->{'MSG'}));
	}
	changeMode(getIDPWDFile());
	copy(getIDPWDFile(), getIDPWDSCHFile());
	changeMode(getIDPWDSCHFile());
	encryptPWD($_[0]) or retreat('failed');
}

#*******************************************************************************************
# Subroutine Name         :	convertFileSize
# Objective               :	converts the file size of a file which has been backed up/synced
#                           into human readable format
# Added By                : Vijay Vinoth
#******************************************************************************************
sub convertFileSize
{
	my $fileSize = $_[0];

	my $fileSpec = $Configuration::fileSizeDetail{'bytes'};

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $Configuration::fileSizeDetail{'kb'};
	}

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $Configuration::fileSizeDetail{'mb'};
	}

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $Configuration::fileSizeDetail{'gb'};
	}

	if ($fileSize > 1023) {
		$fileSize /= 1024;
		$fileSpec = $Configuration::fileSizeDetail{'tb'};
	}

	$fileSize = sprintf "%.2f", $fileSize;
	if (0 == ($fileSize - int($fileSize))) {
		$fileSize = sprintf("%.0f", $fileSize);
	}
	return "$fileSize $fileSpec";
}

#*******************************************************************************************************
# Subroutine Name         : getProgressDetails
# Objective               : Calculate cummulative progress data.
# Added By                : Vijay Vinoth
# Modified By             : Yogesh Kumar
#********************************************************************************************************/
sub getProgressDetails {
	my @progressFileDetails;
	my @progressDetails = ('', 0, 0, 0, '', 0); # type, transfered size, total size, transfer rate, filename, filesize
	my $count = 1;
	my $progressDataFilename = $_[0];

	for(my $i = 1; $i <= $Configuration::totalEngineBackup; $i++) {
		my $progressDataFile = ($progressDataFilename . "_$i");
		if (-f $progressDataFile and !-z $progressDataFile) {
			my $progressData = getFileContents($progressDataFile, 'array');
			next if (scalar @$progressData < 6);
			my $type = $progressData->[0];
			chomp($type);
			my $filesize = $progressData->[1];
			chomp($filesize);
			my $filename = $progressData->[5];
			chomp($filename);
			$filename =~ s/^\s*(.*?)\s*$/$1/; # Remove spaces on both side
			unless ($filename eq '') {
				push (@progressFileDetails, {'type' => $type, 'filename' => $filename, 'filesize' => $filesize});
			}

			$progressDetails[1] += $progressData->[2] if ($progressData->[2] =~ /^\d+$/);
			$progressDetails[2]  = $progressData->[3];
			$progressDetails[3] += $progressData->[4] if ($progressData->[4] =~ /(\d+(\.\d+)?)/);
			$count++;
		}
	}

	if ($count > 1) {
		$progressDetails[3] = ($progressDetails[3]/$count);
		$progressDetails[3] = convertFileSize($progressDetails[3]);

		if (scalar(@progressFileDetails) > 0) {
			my $hr = $progressFileDetails[rand @progressFileDetails];
			$progressDetails[0] = $hr->{'type'};
			$progressDetails[4] = $hr->{'filename'};
			$progressDetails[5] = $hr->{'filesize'};
		}
	}
	return @progressDetails;
}

#******************************************************************************************************************
# Subroutine Name         : cancelProcess.
# Objective               : This subroutine Cancelling the process and removing the intermediate files/folders
# Added By                : Senthil Pandian
#******************************************************************************************************************/
sub cancelProcess {
	my $idevsOutputFile = $Configuration::jobRunningDir."/".$Configuration::evsOutputFile;
	my $idevsErrorFile  = $Configuration::jobRunningDir."/".$Configuration::evsErrorFile;
	my $pidPath  		= $Configuration::jobRunningDir."/".$Configuration::pidFile;

	#Default Cleanup
	system('stty','echo');
	unlink($idevsOutputFile);
	unlink($idevsErrorFile);
	unlink($pidPath);
	exit 1;
}
#****************************************************************************************************
# Subroutine Name         : createDBPathsXmlFile.
# Objective               : Creating DB paths XML file
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub createDBPathsXmlFile
{
    my $username       = getUsername();
	my $localUserPath  = $Configuration::expressLocalDir."/".$username;
	my $xmlFile = $localUserPath."/dbpaths.xml";
	my $xmlContent = '';
	my ($actualDeviceID,$nickName);
	my $dedup		= getUserConfiguration('DEDUP');

	if ($dedup eq 'off'){
		return;
	}
	my $backupTo	= getUserConfiguration('BACKUPLOCATION');
	my $serverRoot  = getUserConfiguration('SERVERROOT');
	my($backupDeviceID, $backupHost) = split("#",$backupTo);
	if ($backupHost and $backupDeviceID){
		($actualDeviceID,$nickName) = ($backupDeviceID,$backupHost);
		$actualDeviceID =~ s/$Configuration::deviceIDPrefix//;
		$actualDeviceID =~ s/$Configuration::deviceIDSuffix//;
	} else {
		display(['your_account_not_configured_properly',"\n\n"]);
		exit;
	}

	my $dbPath = "/LDBNEW/$serverRoot/$username.ibenc";
	if (-e $xmlFile and  -s $xmlFile>0){
		open my $fh, '<', $xmlFile;
		read $fh, my $oldXmlContent, -s $fh;
		close $fh;

		if ($oldXmlContent =~ /<dbpaths>/i){
			my @xmlArray = split("\n",$oldXmlContent);
			if (scalar(@xmlArray)>0){
				my $find = "serverroot=\"$serverRoot\"";
				my $isUpdated = 0;
				foreach(@xmlArray){
					my $row = $_;
					if ($row =~ /<dbpathinfo/i and $row =~ /$find/i){
						$row = '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />';
						$isUpdated = 1;
					}
					if ($row =~ /<\/dbpaths>/i){
						last;
					}
					$xmlContent .= $row."\n";
				}
				if ($isUpdated == 0){
					my $row = '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />';
					$xmlContent .= $row."\n";
				}
				$xmlContent .= '</dbpaths>'."\n";
			}
		}
	} else {
		$xmlContent  = '<?xml version="1.0" encoding="utf-8"?>'."\n";
		$xmlContent .= '<dbpaths>'."\n";
		$xmlContent .= '<dbpathinfo serverroot="'.$serverRoot.'" deviceid="'.$actualDeviceID.'" nickname="'.$nickName.'" dbpath="'.$dbPath.'" />'."\n";
		$xmlContent .= '</dbpaths>'."\n";
	}
	open XMLFILE, ">", $xmlFile or (print "Unable to create file: $xmlFile, Reason:$!" and die);
	print XMLFILE $xmlContent;
	close XMLFILE;
	chmod $Configuration::filePermission, $xmlFile;
}

#*********************************************************************************************************
# Subroutine Name		: createLocalBackupDir
# Objective				: This function will create the directories for local backup.
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#*********************************************************************************************************/
sub createLocalBackupDir {
    my $username       = getUsername();
	my $localUserPath  = $Configuration::expressLocalDir."/".$username;
	createDir($Configuration::expressLocalDir, 1);
	createDir($localUserPath, 1);
	my $serverRoot  = getUserConfiguration('SERVERROOT');
	my $dedup		= getUserConfiguration('DEDUP');

	if ($dedup eq 'on'){
		$backupLocationDir  = "$localUserPath/$serverRoot/";
	} else {
		my $backupHost	  = getUserConfiguration('BACKUPLOCATION');
		$backupLocationDir  = "$localUserPath/$backupHost/";
	}
	createDir($backupLocationDir, 1);
}

#*****************************************************************************************************
# Subroutine			: confirmStartDashboard
# Objective				: This is to restart IDrive Dashboard service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub confirmStartDashboard {
	my $display = ((defined($_[0]) && $_[0] == 1)? 1 : 0);

	if (isDashboardRunning()) {
		display(["\n", 'dashboard_service_running', '. ']) if ($display);
		return 1;
	}

	my $reflag = ((defined $_[1])? 're' : '');
	display(["\n", $reflag . 'starting_dashboard_service', '...']) if ($display);
	system(getIDrivePerlBin() . " " . getScript('dashboard', 1) . " 2>/dev/null &");
	sleep(1);

	if ($display) {
		if (isDashboardRunning()) {
			display(['dashboard_service_' . $reflag . 'started', '.', "\n"]);
		} else {
			display(['failed_to_' . $reflag . 'start_dashboard_service', '.', "\n"]);
		}
	}

	return 1;
}

#****************************************************************************************************
# Subroutine Name         : createExcludedLogFile30k
# Objective               : Create exclude log file.
# Added By                : Senthil Pandian
#*****************************************************************************************************/
sub createExcludedLogFile30k {
	my $excludeDir 	        = $Configuration::jobRunningDir."/".$Configuration::excludeDir;
	my $excludedLogFilePath = $excludeDir."/".$Configuration::excludedLogFile;
	my $excludedLogFilePath_new = $excludedLogFilePath.$Configuration::excludedFileIndex;
	# require to open excludedItems file to log excluded details
	if (!open(EXCLUDEDFILE, ">", $excludedLogFilePath_new)){
		$Configuration::errStr = $Locale::strings{'failed_to_open_file'}." : $excludedLogFilePath_new. Reason:$!\n";
		print $Configuration::errStr;
		traceLog($Configuration::errStr) and die;
	}
	chmod $Configuration::filePermission, $excludedLogFilePath_new;
	$Configuration::excludedFileIndex++;
}

#****************************************************************************************************
# Subroutine		: checkErrorAndLogout
# Objective			: This function will check the error & logout
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil	
#*****************************************************************************************************/
sub checkErrorAndLogout {
	return $_[0] if (!defined($_[0]) or $_[0] eq '');

	my $errStr = $_[0];
	my $cuser = getUsername();

	return 0 if(defined($_[1]) && defined($cuser) && $_[1] ne '' && $cuser ne '' && $_[1] ne $cuser);
	
	if ($errStr =~ /account is under maintenance|account has been cancelled|account has been blocked/i){
		my $cmd = sprintf("%s %s 1 0", $Configuration::perlBin, getScript('logout', 1));
		my $res = system($cmd);

		# if ($res){
			# traceLog('unable_to_logout');
		# } else {
			stopDashboardService($Configuration::mcUser, Helpers::getAppPath());
			if ($errStr =~ /account is under maintenance/i){
				if (defined($_[1])){
					$errStr	 = $LS{'your_account_is_under_maintenance'}
				} else {
					$errStr .= " ".$LS{'please_contact_support_for_more_information'};
				}
				loadCrontab();
				setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
				saveCrontab();
			}
			elsif ($errStr =~ /account has been blocked/i){
				if (defined($_[1])){
					$errStr	 = $LS{'your_account_has_been_blocked'}
				} else {
					$errStr .= " ".$LS{'please_contact_admin_to_unblock'};
				}
				loadCrontab();
				setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
				saveCrontab();
			}
			elsif ($errStr =~ /account has been cancelled/i){
				if (defined($_[1])){
					$errStr	 = $LS{'your_account_has_been_cancelled'}
				} else {
					$errStr .= " ".$LS{'please_contact_support_for_more_information'};
				}
				removeUsersCronEntry();
				removeIDriveUserFromUsersList();
			}
		#}
	}
	return $errStr;
}

#****************************************************************************************************
# Subroutine Name         : checkForExclude.
# Objective               : This function will exclude the files that matched with exclude and partial list
# Added By                : Senthil Pandian
# Modified By			  :
#*****************************************************************************************************/
sub checkForExclude {
	my $element = $_[0];
	my $returnvalue = 0;

	###$element the last slash needs to be removed before comparing with hash for full exclude
	if (exists $backupExcludeHash{$element} or $element =~ m/$Configuration::fullStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. reason: Full path excluded item.\n";
		$Configuration::excludedCount++;
		$returnvalue = 1;
	}
	elsif ($Configuration::parStr ne "" and $element =~ m/$Configuration::parStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. reason: Partial path excluded item.\n";
		$Configuration::excludedCount++;
		$returnvalue = 1;
	}
	elsif ($Configuration::regexStr ne "" and $element =~ m/$Configuration::regexStr/) {
		print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$element]. reason: Regex path excluded item.\n";
		$Configuration::excludedCount++;
		$returnvalue = 1;
	}
	if ($Configuration::excludedCount == EXCLUDED_MAX_COUNT) {
		$Configuration::excludedCount = 0;
		createExcludedLogFile30k();
	}
	return $returnvalue;
}


#*****************************************************************************************************
# Subroutine			: confirmRestartIDriveCRON
# Objective				: This confirms and restarts the cron service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub confirmRestartIDriveCRON {
	my $restartcron = 'y';
	if (checkCRONServiceStatus() == CRON_RUNNING) {
		display(["\n", 'cron_service_running', '. ', 'do_you_want_to_restart_cron_yn']);
		$restartcron = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	# if cron link is absent, reinstall the cron | this case can be caused by uninstallation from other installation
	unless(-f $Configuration::cronLinkPath) {
		my $sudoprompt = 'please_provide_' . ((isUbuntu() || isGentoo())? 'sudoers' : 'root') . '_pwd_for_cron';
		my $sudosucmd = getSudoSuCRONPerlCMD('installcron', $sudoprompt);
		system($sudosucmd);
		return 1;
	}

	restartIDriveCRON(1) if ($restartcron eq 'y');

	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkAndStartDashboard
# Objective				: This confirms and starts the dashboard service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkAndStartDashboard {
	unless (hasStaticPerlSupport()) {
		return 1;
	}

	if (isDashboardRunning()) {
#		display(["\n", 'dashboard_service_running', '. ']) if (!defined($_[0]) || $_[0] == 1);
		return 1;
	}

	confirmStartDashboard(1, $_[1]);
	sleep(3);

	return 1;
}

#****************************************************************************************************
# Subroutine Name	: checkAndUpdatePermissionDeniedList
# Objective			: This subroutine appends the contents of the permission denied list file to the output file
#					  and deletes file.
# Modified By		: Senthil Pandian
#*****************************************************************************************************/
sub checkAndUpdatePermissionDeniedList
{
	my $permissionError = $_[0];
	my $summaryError	= '';
	if (-e $permissionError and !-z $permissionError){
		$summaryError.=$lineFeed."_______________________________________________________________________________________";
		$summaryError.="$lineFeed$lineFeed|Information|$lineFeed";
		$summaryError.="_______________________________________________________________________________________$lineFeed";

		open DENIED_FILE, "<", $permissionError or traceLog(Constants->CONST->{'FileOpnErr'}." $permissionError. Reason $!\n", __FILE__, __LINE__);
		my $byteRead = read(DENIED_FILE, my $buffer, $Configuration::maxLogSize);
		$buffer =~ s/(\] \[FAILED\] \[)/\] \[INFORMATION\] \[/g; #Replacing "FAILED" with "INFORMATION"
		$summaryError.= $buffer.$lineFeed;
		close DENIED_FILE;
	}
	unlink($permissionError);
	return $summaryError;
}

#****************************************************************************************************
# Subroutine Name	: getPermissionDeniedCount
# Objective			: This subroutine will return the count of permission denied error given by EVS.
# Modified By		: Senthil Pandian
#*****************************************************************************************************/
sub getPermissionDeniedCount
{
	my $infoFile 		  = $Configuration::jobRunningDir."/".$Configuration::infoFile;
	my $noPermissionCount = 0;

	if (-e $infoFile and !-z $infoFile){
		$infoFile = getECatfile($Configuration::jobRunningDir,$Configuration::infoFile);
		my $deniedCountCheckCmd = "cat $infoFile | grep \"^DENIEDCOUNT\"";
		$noPermissionCount = `$deniedCountCheckCmd`;
		$noPermissionCount =~ s/DENIEDCOUNT//;
		Chomp(\$noPermissionCount);
	}
	return $noPermissionCount;
}

#****************************************************************************************************
# Subroutine Name         : createLogJsonForOldUser
# Objective               : Create log JSON file after migration of old user data
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub createLogJsonForOldUser {
	my @userList;
	if (-d "$servicePath/$Configuration::userProfilePath"){
		opendir(USERPROFILEDIR, "$servicePath/$Configuration::userProfilePath") or die $!;
		while (my $lmUserDir = readdir(USERPROFILEDIR)) {
			# Use a regular expression to ignore files beginning with a period
			next if ($lmUserDir =~ m/^\./);
			if (-d "$servicePath/$Configuration::userProfilePath/$lmUserDir"){
				opendir(LMUSERDIR, "$servicePath/$Configuration::userProfilePath/$lmUserDir") or die $!;
				while (my $idriveUserDir = readdir(LMUSERDIR)) {
					# Use a regular expression to ignore files beginning with a period
					next if ($idriveUserDir =~ m/^\./);
					if (-d "$servicePath/$Configuration::userProfilePath/$lmUserDir/$idriveUserDir"){
						push(@userList, "$servicePath/$Configuration::userProfilePath/$lmUserDir/$idriveUserDir");
					}
				}
				closedir(LMUSERDIR);
			}
		}
		closedir(USERPROFILEDIR);

		if (scalar(@userList)>0){
			my @jobTypes = ("backup", "localbackup", "restore", "archive");
			my $logFileListToUpload = "$servicePath/$Configuration::userProfilePath/".$Configuration::migratedLogFileList;
			if (!open NEWFILE, ">", $logFileListToUpload) {
				traceLog($LS{'failed_to_open_file'}.":$logFileListToUpload. Reason:$!", __FILE__, __LINE__);
				return 0;
			}
			chmod $Configuration::filePermission, $logFileListToUpload;
			for my $userDir (@userList){
				for my $job (@jobTypes){
					my $userLogDir = $userDir."/".$Configuration::userProfilePaths{$job}."/".$Configuration::logDir;
					if (defined($userLogDir) and -d $userLogDir){
						my %logFileList	= getLogsList($userLogDir);
						my ($startEpoch, $endEpoch) = ('', '');
						($startEpoch, $endEpoch) = getStartAndEndEpochTimeForMigration(\%logFileList);
						my $slf = getLastOneWeekLogs(\%logFileList, $startEpoch, $endEpoch,$userLogDir);
						my $logFileName;
						Helpers::addLogStat($userDir."/".$Configuration::userProfilePaths{$job}."/", $slf) if (%{$slf});
					}
				}
			}
			close NEWFILE;
			unlink($logFileListToUpload) if (-z $logFileListToUpload);
			saveMigratedLog();
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : createServiceDirectory
# Objective               : Create service directory
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub createServiceDirectory {
	Helpers::display('enter_your_service_path', 0);
	my $servicePathSelection = Helpers::getUserChoice();
	$servicePathSelection =~ s/^~/Helpers::getUserHomePath()/g;

	# In case user want to go for optional service path
	if ($servicePathSelection eq ''){
		$servicePathSelection = dirname(Helpers::getAppPath());
		Helpers::display(['your_default_service_directory'],1);
	}

	# Check if service path exist
	Helpers::retreat(['invalid_location', " \"$servicePathSelection\". ", "Reason: ", 'no_such_directory']) if (!-d $servicePathSelection);

	# Check if service path have write permission
	Helpers::retreat(['cannot_open_directory', " $servicePathSelection ", 'permission_denied'])	if (!-w $servicePathSelection);

	# get full path for service directory
	$servicePathSelection = Helpers::getCatfile($servicePathSelection, $Configuration::servicePathName);
	my $sp = '';
	my $servicePathExists = 0;
	$sp = Helpers::getAbsPath($servicePathSelection) or Helpers::retreat('no_such_directory_try_again');
	my $oldServiceLocation = $sp;
	$oldServiceLocation =~ s/$Configuration::servicePathName$/$Configuration::oldServicePathName/;
	if(-d $oldServiceLocation){
		Helpers::saveServicePath($oldServiceLocation) or Helpers::retreat('failed_to_create_service_location_file');
		Helpers::initiateMigrate();
	}

	if (-d $sp) {
		Helpers::display(["Service directory ", "\"$sp\" ", 'already_exists']);
	}
	else {
		Helpers::createDir($sp) or Helpers::retreat('failed');
	}

	Helpers::saveServicePath($sp) or Helpers::retreat('failed_to_create_service_location_file');
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	Helpers::display(["\n",'your_service_directory_is',Helpers::getServicePath()]);
}

#*****************************************************************************************************
# Subroutine			: customReName
# Objective				: Used to rename file/files inside the folder customReName($path,$find,$replace)
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub customReName{
	my $inputPath = $_[0];
	my $findPattern = $_[1];
	my $replacePattern = $_[2];
	if (-f $inputPath){
		my $newname = $inputPath;
		$newname =~ s/$findPattern/$replacePattern/g;
		rename $inputPath, $newname;
	}
	elsif (-d $inputPath){
		if (opendir(CUSTOMDIR, $inputPath)) {
			foreach my $file (readdir(CUSTOMDIR))  {
				if ($file eq '.' or $file eq '..') {
					next;
				}
				chomp($file);
				my $newname = $inputPath."/".$file;
				$newname = $newname."_ABORTED"	if (index($file, "_") == -1);
				$file = $inputPath."/".$file;
				$newname =~ s/$findPattern/$replacePattern/g;
				rename $file,$newname  or traceLog("rename failed because Reason:$! \n");
			}
			closedir(CUSTOMDIR);
		}
	}
}
#------------------------------------------------- D -------------------------------------------------#

#*******************************************************************************************************
# Subroutine Name         :	deactivateOtherUserCRONEntries
# Objective               :	Update cron entry with inactive status
# Added By                : Sabin Cheruvattil
#********************************************************************************************************/
sub deactivateOtherUserCRONEntries {
	return 0 unless($_[0]);
	my $curuser = $_[0];

	if(exists $crontab{$Configuration::mcUser}) {
		loadCrontab();

		foreach my $idusername (keys %{$crontab{$Configuration::mcUser}}) {
			if($curuser ne $idusername) {
				setUsername($idusername);
				createCrontab('otherInfo', {'settings' => {'status' => 'INACTIVE', 'lastActivityTime' => time()}});
				setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
				saveCrontab();
			}
		}
		
		setUsername($curuser);
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: deepCopyEntry
# Objective				: deep copy entries from the given args
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub deepCopyEntry {
	my ($ref) = $_[0];
	my ($ref2) = $_[1];

	if (ref($ref) eq 'HASH') {
		return ({map {$_ => deepCopyEntry($ref->{$_}, $ref2->{$_})} sort keys %$ref});
	}
	elsif (ref($ref) eq 'ARRAY') {
		return [map {deepCopyEntry($_)} @$ref];
	}
	else {
		return $ref2 || $ref;
	}
}

#*****************************************************************************************************
# Subroutine			: decryptString
# Objective				: Decrypt the given data
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub decryptString {
	return '' unless $_[0];
# TBE override
	return Taryck::decryptString($_[0]);
	my $encString  = $_[0];
	my $stringLength	= length $encString;
	my $swapLength		= $stringLength - ($stringLength % 4);
	my $shiftLength		= $swapLength/4;

	my $swpa			= substr($encString, 0, $shiftLength);
	my $swpb			= substr($encString, (3 * $shiftLength), $shiftLength);

	substr($encString, (3 * $shiftLength), $shiftLength) = $swpa;
	substr($encString, 0, $shiftLength) = $swpb;

	$encString = decode_base64($encString);

	return $encString;
}

#*****************************************************************************************************
# Subroutine			: display
# Objective				: Prints formated data to stdout
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub display {
	return 0 if ($Configuration::callerEnv eq 'BACKGROUND');
	my $message = $_[0];
	my $msg = '';
	my $endWithNewline = 1;

	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}
	for my $i (0 .. $#{$message}) {
		next if(!defined($message->[$i]) or $message->[$i] eq '');
		if (exists $LS{$message->[$i]}) {
			$msg .= $LS{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}
	if (defined($_[2])) {
		my $c = 1;
		for my $i (0 .. $#{$_[2]}) {
			$msg =~ s/__ARG$c\__/$_[2]->[$i]/g;
			$c++;
		}
	}
	print "$msg";
	$endWithNewline    = $_[1] if (defined($_[1]));
	print "\n" if ($endWithNewline);
}

#**********************************************************************************************
#Sbroutine Name         : displayFinalSummery(SCALAR,SCALAR);
#Objective              : It display the final summery after the backup/restore job has been completed.
#Usage                  : displayFinalSummery(JOB_TYPE,FINAL_SUMMARY_FILE_PATH);
#Added By               : Abhishek Verma.
#Modified By            : Senthil Pandian
#***********************************************************************************************/
sub displayFinalSummary{
	my ($jobType,$finalSummaryFile) = @_;
	my $errString = undef;
	my $jobStatus;

	if (open(FS,'<',$finalSummaryFile)){#FS file handel means (F)ile (S)ummary.
		chomp(my @fileSummary = <FS>);
		close(FS);
		$errString	= pop (@fileSummary) if ($#fileSummary > 8);
		$jobStatus	= pop (@fileSummary);
		my $logFilePath = pop (@fileSummary);
		my $fileSummary = join ("\n",@fileSummary);
#		if ($jobStatus eq 'SUCCESS' or $jobStatus eq 'SUCCESS*'){
		if ($jobStatus eq 'Success' or $jobStatus eq 'Success*'){
			$jobStatus = qq($jobType has completed.);
		}elsif ($jobStatus eq 'Failure' or $jobStatus eq 'Aborted'){
			$jobStatus = defined ($errString) ? $errString : qq($jobType has failed.);
		}
		print qq(\n$jobStatus\n$fileSummary\n\n$logFilePath\n);
		#unlink($finalSummaryFile);
	}#else{
	#	print qq(\nUnable to print status summary. Reason: $!\n);
	#}
}

#*****************************************************************************************************
# Subroutine			: displayHeader
# Objective				: Display header for the script files
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil
#****************************************************************************************************/
sub displayHeader {
	return 1 if ($Configuration::callerEnv eq 'BACKGROUND');

	if ($Configuration::displayHeader) {
		$Configuration::displayHeader = 0;
		my $w = (split(' ', $Configuration::screenSize))[-1];
		my $adjst = 0;
		$w += 0;
		$w = ($w > 80)?80:$w;

		my $header = qq(=) x $w;
		my $h = "Version: $Configuration::version";
		my $l = length($h);
		$header    .= qq(\n$h);
		$header    .= (qq( ) x (25 - ($l -$adjst)) . qq($LS{'developed_by'} ));
		$header    .= qq($LS{lc($Configuration::appType . '_maintainer')}\n);
		$header    .= (qq(-) x $l . qq( ) x (25 - ($l -$adjst)) . qq(-) x ($w - ($l+ (25 - ($l -$adjst)))));
		$h = "Status: ";
		if ($username) {
			$h .= $LS{isLoggedin().'_login_status'};
			#$h .= "Logged In";
		}
		else {
			$h .= "--";
		}
		$l = length($h);
		$header    .= qq(\n$h);
		$header    .= (qq( ) x (25 - ($l -$adjst)) . qq($LS{'logged_in_user'} ));
		$header    .= (($username ? $username: $LS{'no_logged_in_user'}) . qq(\n));


		# $h = qq($LS{'logged_in_user'});
		# $header    .= qq(\n$h);
		# $header    .= ((qq( ) x (20 - ($l -$adjst) + ($l - length($h)))) . ($username ? $username: $LS{'no_logged_in_user'}) . qq(\n));

		if ($username and -e getServerAddressFile()){
			if (loadStorageSize() or reCalculateStorageSize()) {
				$header    .= (qq(-) x $l . qq( ) x (25 - ($l -$adjst)) . qq(-) x ($w - ($l+ (25 - ($l -$adjst)))));
				$header    .= qq(\n);
				$h = qq($LS{'storage_used'});
				$header    .= qq($h);
				$header    .= ((qq( ) x (25 - ($l -$adjst) + ($l - length($h)))));
				$header    .= ((getUserConfiguration('ADDITIONALACCOUNT') eq 'true')? qq($storageUsed) : qq($storageUsed of $totalStorage));
				$header    .= " ( Available: ".getFreeStorage()." )";		#TBE Add
				$header    .= qq(\n);
			}
		}

		if (isUpdateAvailable() && getUserConfiguration('NOTIFYSOFTWAREUPDATE')) {
			$header    .= qq(-) x $w;
			$header    .= qq(\n);
			$h = qq($LS{'new_update_is_available'});
			$header    .= qq($h\n);
		}
		$header    .= qq(=) x $w . qq(\n);
		if ($username and -e getServerAddressFile()){
			my $warningCount = 0;
			my $warningHeader = '';
			if (isDashboardRunning() == 0){
				$warningHeader    .= qq(\n);
				$warningHeader .= qq(* $LS{'dashboard_service_stopped'});
				$warningCount++;
			}
			unless(checkCRONServiceStatus() == CRON_RUNNING) {
				$warningHeader    .= qq(\n);
				$warningHeader .= qq(* $LS{'cron_service_stopped'});
				$warningCount++;
			}
			if ($warningCount > 0){
				$header    .= qq($LS{'warning_header'});
				$header    .= $warningHeader. qq(\n);
				$header    .= qq(-) x $w . qq(\n);
			}
		}
		display($header);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: displayMenu
# Objective				: Display menu items and ask user for the action.
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub displayMenu {
	if ($Configuration::callerEnv eq 'BACKGROUND') {
		traceLog($Configuration::callerEnv." is caller environment");
	}

	my $c = 1;
	my ($message, @options) = @_;
	my @lables = ();
	my $lable = '';
	my $indent = '';
	foreach (@options) {
		@lables = $_ =~ /^__[a-z0-9_]+__/g;
		if (scalar @lables > 0) {
			if ($lable ne $lables[0]) {
				#display('');
				display($lables[0]);
				$lable = $lables[0];
				$indent = "\t";
			}
			$_ =~ s/^__[a-z0-9_]+__//g;
		}
		my $content = $c;
		$content = " ".$content		if (($#options > 9) and ($c <= 9));
		display(["$indent", "$content\) ", $LS{$_}]);
		$c++;
	}
	display($message, 0);
}

#****************************************************************************************************
# Subroutine			: displayProgress
# Objective				: This subroutine will display the progress in the terminal window.
# Added By				: Senthil Pandian
#****************************************************************************************************
sub displayProgress{
	$SIG{WINCH} = \&changeSizeVal;
	my $progressMsg = $_[0];
	if ($Configuration::machineOS =~ /freebsd/i){
		my $noOfLineToClean = $_[1];
		system("tput rc");
		system("tput ed");
		for(my $i=1;$i<=$noOfLineToClean;$i++){
			print $Configuration::freebsdProgress;
		}
	}
	system("tput rc");
	system("tput ed");
	print $progressMsg;
}

#*****************************************************************************************************
# Subroutine			: download
# Objective				: Download files from the given url
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub download {
	my $url           = $_[0];
	my $downloadsPath = $_[1];

	unless (defined($url)) {
		display('url_cannot_be_empty');
		return 0;
	}

	unless (defined($downloadsPath)) {
		$downloadsPath = "$servicePath/$Configuration::downloadsPath";
	}

	unless (-d $downloadsPath) {
		unless(createDir($downloadsPath)) {
			display(["$downloadsPath ", 'does_not_exists']);
			return 0;
		}
	}

	if (reftype(\$url) eq 'SCALAR') {
		$url = [$url];
	}

	my $proxy = '';
	if (getUserConfiguration('PROXYIP')) {
		$proxy = '-x http://';
		$proxy .= getUserConfiguration('PROXYIP');

		if (getUserConfiguration('PROXYPORT')) {
			$proxy .= (':' . getUserConfiguration('PROXYPORT'))
		}
		if (getUserConfiguration('PROXYUSERNAME')) {
			my $pu = getUserConfiguration('PROXYUSERNAME');
			foreach ($pu) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$proxy .= (' --proxy-user ' . $pu);

			if (getUserConfiguration('PROXYPASSWORD')) {
				my $ppwd = getUserConfiguration('PROXYPASSWORD');
				$ppwd = ($ppwd ne '')?decryptString($ppwd):$ppwd;
				foreach ($ppwd) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				$proxy .= (':' . $ppwd);
			}
		}
	}

	my $response;
	for my $i (0 .. $#{$url}) {
		my @parse = split('/', $url->[$i]);
		my $tmpErrorFile  = $downloadsPath."/".$Configuration::errorFile;
		my $cmd = "curl --tlsv1 --fail -k $proxy -L $url->[$i] -o '$downloadsPath/$parse[-1]' 2>>'$tmpErrorFile'";
		#print "cmd:$cmd#\n\n";
		$response = `$cmd`;

		if (-e $tmpErrorFile and -s $tmpErrorFile){
			# if (!open(FH, "<", $tmpErrorFile)) {
				# my $errStr = $Locale::strings{'failed_to_open_file'}.":$tmpErrorFile, Reason:$!";
				# traceLog($errStr);
			# }
			# my $byteRead = read(FH, $response, $Configuration::bufferLimit);
			$response = getFileContents($tmpErrorFile);
			close FH;
			Chomp(\$response);
		}
		#print "response:$response#\n\n";
		unlink($tmpErrorFile) if (-e $tmpErrorFile);
		if (($response =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Failed connect to .* Connection refused|Connection timed out|response code said error|407|No route to host|Could not resolve host/)) {

			retreat(["\n", 'kindly_verify_ur_proxy']) if (defined($_[2]));

			display(["\n", 'kindly_verify_ur_proxy']);
			askProxyDetails() or retreat('failed due to proxy');
			return download($url,$downloadsPath,"NoRetry") unless(defined($_[2] and $_[2] eq 'NoRetry'));

			# saveUserConfiguration() or retreat('failed to save user configuration');
		}
		elsif ($response =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
			retreat($response);
		} else {
			traceLog("CURL-ERROR: $response");
		}
		#Commented by Senthil for Senthil_2.17_54_1
		# if ($? > 0) {
			# traceLog($?);
			# return 0;
		# }
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: downloadEVSBinary
# Objective				: Download system compatible evs binary
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub downloadEVSBinary {
	my $status = 0;
	loadMachineHardwareName();
	my $ezf    = [@{$Configuration::evsZipFiles{$machineHardwareName}},
								@{$Configuration::evsZipFiles{'x'}}];
	my $downloadPage = $Configuration::evsDownloadsPage;
	my $domain       = lc($Configuration::appType);

	$domain .= 'downloads' if ($Configuration::appType eq 'IDrive');

	$downloadPage =~ s/__APPTYPE__/$domain/g;

	my $dp;
	for my $i (0 .. $#{$ezf}) {
		$ezf->[$i] =~ s/__APPTYPE__/$Configuration::appType/g;
		$dp = ($downloadPage . "/$ezf->[$i]");
		unless(download($dp)) {
			$status = 0;
			last;
		}
		unless (unzip("$servicePath/$Configuration::downloadsPath/$ezf->[$i]")) {
			$status = 0;
			last;
		}

		my $binPath = getServicePath() . "/$Configuration::downloadsPath/" . $ezf->[$i] ;
		$binPath =~ s/\.zip//g;
		if (hasEVSBinary($binPath)) {
			$status = 1;
			last;
		}
		last if ($status);
	}
	rmtree("$servicePath/$Configuration::downloadsPath");
	return $status;
}

#*****************************************************************************************************
# Subroutine			: downloadStaticPerlBinary
# Objective				: Download system compatible static perl binary
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub downloadStaticPerlBinary {
	my $status = 0;
	loadMachineHardwareName();
	my $ezf    = [@{$Configuration::staticperlZipFiles{$machineHardwareName}}];
	if ($Configuration::machineOS =~ /freebsd/i) {
		$ezf = [@{$Configuration::staticperlZipFiles{'freebsd'}}];
	}
	my $downloadPage = $Configuration::evsDownloadsPage;
	my $domain       = lc($Configuration::appType);

	$domain .= 'downloads' if ($Configuration::appType eq 'IDrive');

	$downloadPage =~ s/__APPTYPE__/$domain/g;

	my $dp;
	for my $i (0 .. $#{$ezf}) {
		$ezf->[$i] =~ s/__APPTYPE__/$Configuration::appType/g;
		$ezf->[$i] =~ s/__KVER__/$Configuration::kver/g;
		$dp = ($downloadPage . "/$ezf->[$i]");
		unless(download($dp)) {
			$status = 0;
			last;
		}
		unless (unzip("$servicePath/$Configuration::downloadsPath/" . (fileparse($ezf->[$i]))[0])) {
			$status = 0;
			last;
		}

		my $binPath = getCatfile(getServicePath(), $Configuration::downloadsPath, (fileparse($ezf->[$i]))[0]);
		$binPath =~ s/\.zip//g;
		if (hasStaticPerlBinary($binPath)) {
			$status = 1;
			last;
		}
		last if ($status);
	}
	rmtree("$servicePath/$Configuration::downloadsPath");
	return $status;
}

#*****************************************************************************************************
# Subroutine			: deleteLog
# Objective				: Delete a log from the record
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub deleteLog {
	my $logFile = getJobsPath($_[0]);
	my @time 	= localtime($_[1]);
	my $logstat = getCatfile($logFile, sprintf("$Configuration::logStatFile", ($time[4] + 1), ($time[5] += 1900)));

	my %logs;
	if (-f $logstat) {
		%logs = %{JSON::from_json(
			'{' .
			substr(getFileContents($logstat), 1) .
			'}'
		)};
	}

	if (exists $logs{$_[1]}) {
		delete $logs{$_[1]};

		my $logstatInStrings = JSON::to_json(\%logs);
		if ($logstatInStrings eq '{}') {
			$logstatInStrings = '';
		}
		elsif ($logstatInStrings ne '') {
			substr($logstatInStrings, 0, 1, ',');
			substr($logstatInStrings, -1, 1, '');
		}
		fileWrite($logstat, $logstatInStrings);

		$logFile = getCatfile(getJobsPath($_[0], lc($Configuration::logDir)), "$_[1]_$_[2]");
		unlink($logFile);
		return 1;
	}

	return 0;
}

#****************************************************************************************************
# Subroutine Name         : displayProgressBar.
# Objective               : This subroutine contains the logic to display the filename and the progress
#                           bar in the terminal window.
# Added By                : Senthil Pandian
# Modified By             : Yogesh Kumar
#*****************************************************************************************************/
sub displayProgressBar {
	my @progressDetails = getProgressDetails($_[0]);
	my $isDedup = getUserConfiguration('DEDUP');
	return '' if (scalar(@progressDetails) == 0);

	$SIG{WINCH} = \&changeSizeVal;

	my ($progress, $cellSize, $totalSizeUnit) = ('', '', '');
	my $fullHeader = $LS{lc($Configuration::jobType . '_progress')};
	my $incrFileSize = $progressDetails[1];
	my $TotalSize = $progressDetails[2];
	my $kbps = $progressDetails[3];
	my $percent = 0;
	$TotalSize = $_[1] if (defined $_[1] and $_[1] > 0);
	$TotalSize = 0 if ($TotalSize eq $LS{'calculating'});
	if ($TotalSize != 0) {
		$percent = int($incrFileSize/$TotalSize*100);
		$percent = 100	if ($percent > 100);
		$progress = "|"x($percent/$progressSizeOp);
		my $cellCount = (100-$percent)/$progressSizeOp;
		$cellCount = $cellCount - int $cellCount ? int $cellCount + 1 : $cellCount;
		$cellSize = " " x $cellCount;
		$totalSizeUnit = convertFileSize($TotalSize);
	}
	else {
		#$totalSizeUnit = convertFileSize($TotalSize);
		$totalSizeUnit = $LS{'calculating'};
	}

	my $fileSizeUnit = convertFileSize($incrFileSize);
	#$kbps =~ s/\s+//; Commented by Senthil : 26-Sep-2018
	$percent = sprintf "%4s", "$percent%";
	my $spAce = " "x6;
	my $boundary = "-"x(100/$progressSizeOp);
	my $spAce1 = " "x(38/$progressSizeOp);

	return if ($progressDetails[0] eq '');
	my $fileDetailRow = "\[$progressDetails[0]\] \[$progressDetails[4]\] \[$progressDetails[5]\]";

	my $strLen     = length $fileDetailRow;
	my $emptySpace = " ";
	$emptySpace = " "x($latestCulmn-$strLen) if($latestCulmn>$strLen);
	my $progressReturnData = $fullHeader;
	$progressReturnData .=  "$fileDetailRow $emptySpace\n\n";
	$progressReturnData .= "$spAce$boundary\n";
	$progressReturnData .= "$percent [";
	$progressReturnData .= $progress.$cellSize;
	$progressReturnData .= "]\n";
	$progressReturnData .= "$spAce$boundary\n";
	$progressReturnData .= "$spAce1\[$fileSizeUnit of $totalSizeUnit] [$kbps/s]$emptySpace\n";

	if ($Configuration::jobType =~ /Backup/i) {
		my $backupHost	  = getUserConfiguration('BACKUPLOCATION');
		my $backupPathType = getUserConfiguration('BACKUPTYPE');
		my $bwThrottle = getUserConfiguration('BWTHROTTLE');

		if ($isDedup eq 'on'){
			my $backupLoaction = ($backupHost =~ /#/)?(split('#',$backupHost))[1]:$backupHost;
			$progressReturnData .= "\nBackup Location       : $backupLoaction\n";
		} else {
			$progressReturnData .= "\nBackup Location       : $backupHost\n";
			$progressReturnData .= "Backup Type           : ".ucfirst($backupPathType)."\n";
		}
		$progressReturnData .= "Bandwidth Throttle(%) : $bwThrottle\n";
	}
	else {
		my $restoreHost  = getUserConfiguration('RESTOREFROM');
		my $restoreLocation  = getUserConfiguration('RESTORELOCATION');
		my $restoreFromLoaction = $restoreHost;
		if ($isDedup eq 'on') {
			$restoreFromLoaction = (split('#',$restoreHost))[1] if ($restoreHost =~ /#/);
		}
		$progressReturnData .= "\nRestore From Location : $restoreFromLoaction\n";
		$progressReturnData .= "Restore Location        : $restoreLocation\n";
	}
	displayProgress($progressReturnData, 11);
}

#****************************************************************************************************
# Subroutine Name : doBackupOperation.
# Objective       : This subroutine performs the actual task of backing up files. It creates
#							a child process which executes the backup command. It also creates a process
#							which continuously monitors the temporary output file. At the end of backup,
#							it inspects the temporary error file if present. It then deletes the temporary
#							output file, temporary error file and the temporary directory created by
#							idevsutil binary.
# Usage			  : doBackupOperation($line);
# Where			  : $line :
# Modified By     : Deepak Chaurasia, Vijay Vinoth
#*****************************************************************************************************/
sub doBackupOperation
{
	my $parameters       = $_[0];
	my $silentBackupFlag = $_[1];
	my $scheduleFlag     = $_[2];
	my $operationEngineId = $_[3];
	my $retry_failedfiles_index = $_[4];
	my $pidPath       = $Configuration::jobRunningDir."/".$Configuration::pidFile;
	my $backupUTFpath = $Configuration::jobRunningDir.'/'.$Configuration::utf8File."_".$operationEngineId;
	my $evsOutputFile = $Configuration::jobRunningDir.'/'.$Configuration::evsOutputFile.'_'.$operationEngineId;
	my $evsErrorFile  = $Configuration::jobRunningDir.'/'.$Configuration::evsErrorFile.'_'.$operationEngineId;
	my $isDedup  	      = getUserConfiguration('DEDUP');
	my $bwPath     	      = getUserProfilePath()."/bw.txt";
	my $defLocal	      = 1; #Need to tc
	my $backupHost	      = getUserConfiguration('BACKUPLOCATION');
	my $userName 	      = getUsername();
	my $backupLocationDir = getLocalBackupDir();
	my @parameter_list = split /\' \'/,$parameters,3;
	my $engineLockFile = $Configuration::jobRunningDir."/".Configuration::ENGINE_LOCKE_FILE;
	$backupUTFpath = $backupUTFpath;

	open(my $startPidFileLock, ">>", $engineLockFile) or return 0;
	if (!flock($startPidFileLock, 1)){
		traceLog("Failed to lock engine file");
		return 0;
	}

	open(my $engineFp, ">>", $pidPath.'_'.$operationEngineId) or return 0;

	if (!flock($engineFp, 2)){
		display('failed_to_lock',1);
		return 0;
	}

	createUTF8File(['EXPRESSBACKUP',$backupUTFpath],
				$parameter_list[2],
				$bwPath,
				$defLocal,
				$Configuration::jobRunningDir."/",
				$parameter_list[1],
				$evsOutputFile,
				$evsErrorFile,
				$backupLocationDir,
				$parameter_list[0],
				$backupLocationDir
				) or retreat('failed_to_create_utf8_file');

	my $backupPid = fork();
	if (!defined $backupPid) {
		$Configuration::errStr = $Locale::strings{'cannot_fork_child'}."\n";
		#return BACKUP_PID_FAIL;
		return 2;
	}

	if ($backupPid == 0) {
		$Configuration::pidOperationFlag = "EVS_process";
		if ( -e $pidPath) {
			#exec($idevsutilCommandLine);
			my @responseData = runEVS('item',1);
			if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
				if (open(ERRORFILE, ">> $Configuration::errorFilePath"))
				{
					autoflush ERRORFILE;
					print ERRORFILE $Configuration::errStr;
					close ERRORFILE;
					chmod $Configuration::filePermission, $Configuration::errorFilePath;
				}
				else {
					traceLog($Locale::strings{'failed_to_open_file'}."errorFilePath in doBackupOperation:".$Configuration::errorFilePath.", Reason:$! \n");
				}
			}

			if (open OFH, ">>", $evsOutputFile) {
				print OFH "\nCHILD_PROCESS_COMPLETED\n";
				close OFH;
				chmod $Configuration::filePermission, $evsOutputFile;
			}
			else {
				$Configuration::errStr = $Locale::strings{'failed_to_open_file'}.": $Configuration::outputFilePath in doBackupOperation. Reason: $!";
				print $Configuration::errStr;
				traceLog($Configuration::errStr);
				return 0;
			}
		}
		exit 1;
	}

	$Configuration::pidOperationFlag = "child_process";
	$Configuration::pidOutputProcess = $backupPid;
	exit(1) unless(-f $pidPath);

	#$isLocalBackup = 0;
	my $currentDir = getAppPath();
	my $workingDir = $currentDir;
	$workingDir =~ s/\'/\'\\''/g;
	my $tmpoutputFilePath = $Configuration::outputFilePath;
	$tmpoutputFilePath =~ s/\'/\'\\''/g;
	my $TmpBackupSetFile = $parameter_list[2];
	$TmpBackupSetFile =~ s/\'/\'\\''/g;
	my $TmpSource = $parameter_list[0];
	$TmpSource =~ s/\'/\'\\''/g;
	my $tmp_jobRunningDir = $Configuration::jobRunningDir;
	$tmp_jobRunningDir =~ s/\'/\'\\''/g;
	my $tmpBackupHost = $backupHost;
	$tmpBackupHost =~ s/\'/\'\\''/g;
	#$fileChildProcessPath = qq($userScriptLocation/).Constants->FILE_NAMES->{operationsScript};
	my $fileChildProcessPath = $currentDir.'/'.$Configuration::idriveScripts{'operations'};
	my $bwThrottle 			 = getUserConfiguration('BWTHROTTLE');
	my $backupPathType       = getUserConfiguration('BACKUPTYPE');
	my @param = join ("\n",('LOCAL_BACKUP_OPERATION',$tmpoutputFilePath,$TmpBackupSetFile,$parameter_list[1],$TmpSource,$progressSizeOp,$tmpBackupHost,$bwThrottle,$silentBackupFlag,$backupPathType,$scheduleFlag,$operationEngineId));

	writeParamToFile("$tmp_jobRunningDir/$Configuration::operationsfile"."_".$operationEngineId,@param);
	my $perlPath = getPerlBinaryPath();
	#traceLog("cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\'");
	{
	my $cmd = "cd \'$workingDir\'; $perlPath \'$fileChildProcessPath\' \'$tmp_jobRunningDir\' \'$userName\' \'$operationEngineId\' \'$retry_failedfiles_index\'";
	system($cmd);
	}
	waitpid($backupPid, 0);
	return 0 unless(updateServerAddr());

	unlink($parameter_list[2]);
	unlink($evsOutputFile.'_'.$operationEngineId);
	flock($startPidFileLock, 8);
	flock($engineFp, 8);
	unlink($pidPath.'_'.$operationEngineId);

	return 0 if(-e $Configuration::errorFilePath && -s $Configuration::errorFilePath);
	return 1; #Success
}

#*****************************************************************************************************
# Subroutine			: doSilentLogout
# Objective				: This function will Logout current user's a/c silently
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub doSilentLogout {
	my $usrtxt = getFileContents(getCatfile(getServicePath(), $Configuration::cachedIdriveFile));
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		$usrtxt->{$Configuration::mcUser}{'isLoggedin'} = 0;
		fileWrite(getCatfile(getServicePath(), $Configuration::cachedIdriveFile), JSON::to_json($usrtxt));
		return 1;
	}
	return 0;
}
#------------------------------------------------- E -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: editRestoreLocation
# Objective				: Edit restore location for the current user
# Added By				: Anil Kumar
#****************************************************************************************************/
sub editRestoreLocation {
	my $restoreLocation = getUserConfiguration('RESTORELOCATION');
	display(['your_restore_location_is_set_to', " \"$restoreLocation\". ", 'do_you_want_edit_this_y_or_n_?'],1);
	my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		setRestoreLocation($_[0]);
		return 1;
	}
	else {
		if (defined($_[0])) {
			return 0 ;
		}
		return 1;
	}
}

#*****************************************************************************************************
# Subroutine			: editRestoreFromLocation
# Objective				: Set restore from location for the current user
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar[26/04/2018]
#****************************************************************************************************/
sub editRestoreFromLocation {
	my $rfl = getUserConfiguration('RESTOREFROM');
	$rfl = (split('#', $rfl))[-1];
	display(["\n",'your_restore_from_device_is_set_to', " \"$rfl\". ", 'do_you_want_edit_this_y_or_n_?'],1);
	my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if (lc($answer) eq "y") {
		if (getUserConfiguration('DEDUP') eq 'on') {
			display(["\n",'loading_your_account_details_please_wait',"\n"],1);
			my @devices = fetchAllDevices();
			if ($devices[0]{'STATUS'} eq Configuration::FAILURE) {
				if ($devices[0]{'MSG'} =~ 'No devices found') {
					retreat('failed');
				}
			}
			elsif ($devices[0]{'STATUS'} eq Configuration::SUCCESS) {
				linkBucket('restore', \@devices) or retreat("Please try again.");
				return 1;
			}
		}
		elsif (getUserConfiguration('DEDUP') eq 'off') {
			display(['enter_your_restore_from_location_optional', ": "], 0);
				my $bucketName = getUserChoice();
				if ($bucketName ne ""){
					display(['Setting up your restore from location...'], 1);
					if (substr($bucketName, 0, 1) ne "/") {
						$bucketName = "/".$bucketName;
					}

					if (open(my $fh, '>', getValidateRestoreFromFile())) {
						print $fh $bucketName;
						close($fh);
						chmod 0777, getValidateRestoreFromFile();
					}
					else
					{
						traceLog("failed to create file. Reason: $!\n");
						return 0;
					}

					my $evsErrorFile      = getUserProfilePath().'/'.$Configuration::evsErrorFile;
					createUTF8File('ITEMSTATUS',getValidateRestoreFromFile(),$evsErrorFile) or retreat('failed_to_create_utf8_file');
					my @result = runEVS('item');
					if (-s $evsErrorFile > 0) {
						unlink($evsErrorFile);
						retreat('operation_could_not_be_completed_please_try_again');
					}
					unlink($evsErrorFile);

					if ($result[0]{'status'} =~ /No such file or directory|directory exists in trash/) {
						display(['failed_to_set_restore_from_location'], 1);
						display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\". ")],1);
					}
					else
					{
						$rfl = $bucketName;
						display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\". ")],1);
					}
					setUserConfiguration('RESTOREFROM', $rfl);
					unlink(getValidateRestoreFromFile());
				}
				else
				{
					display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\" ")],1);
					display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\". ")],1);
					setUserConfiguration('RESTOREFROM', $rfl);
				}
				return 1;
		}
		else {
			retreat('Unable_to_find_account_type_dedup_or_no_dedup');
		}
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: encryptPWD
# Objective				: Encrypt user passwd
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub encryptPWD {
	my $epf = getIDENPWDFile();
	my $len = length($username);
	my $ep = pack("u", $_[0]);
	chomp($ep);
	$ep = ($len . "_" . $ep);
	if (open(my $fh, '>', $epf)) {
		print $fh $ep;
		close($fh);
		changeMode(getIDENPWDFile());
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: encodePVT
# Objective				: This subroutine is used to create IDPVT and IDPVTSCH files
# Added By				: Anil Kumar
#****************************************************************************************************/
sub encodePVT {
	my $encKey = $_[0];
	createUTF8File('STRINGENCODE', $encKey, getIDPVTFile()) or retreat('failed_to_create_utf8_file');
	my @result = runEVS();
	unless (($result[0]->{'STATUS'} eq Configuration::SUCCESS) and ($result[0]->{'MSG'} eq 'no_stdout')) {
		retreat('failed_to_encode_private_key');
	}
	copy(getIDPVTFile(), getIDPVTSCHFile());
	changeMode(getIDPVTFile());
	changeMode(getIDPVTSCHFile());
}

#*****************************************************************************************************
# Subroutine			: encryptString
# Objective				: Encrypt the given data
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub encryptString {
	return '' unless $_[0];
# TBE override
	return Taryck::encryptString($_[0]);
	my $plainString  = $_[0];

	$plainString = encode_base64($plainString);
	chomp($plainString);
	my $stringLength	= length $plainString;
	my $swapLength		= $stringLength - ($stringLength % 4);
	my $shiftLength		= $swapLength/4;

	my $swpa			= substr($plainString, 0, $shiftLength);
	my $swpb			= substr($plainString, (3 * $shiftLength), $shiftLength);

	substr($plainString, (3 * $shiftLength), $shiftLength) = $swpa;
	substr($plainString, 0, $shiftLength) = $swpb;

	return $plainString;
}

#****************************************************************************************************
# Subroutine Name         : enumerate.
# Objective               : This function will list files recursively.
# Added By                : Dhritikana
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub enumerate {
	my $pidPath	= $Configuration::jobRunningDir."/".$Configuration::pidFile;
	my $item    = $_[0];
	my $retVal  = 1;
	my $relativeFileset = $Configuration::jobRunningDir."/".$Configuration::relativeFileset;
	my $relative = backupTypeCheck();
	if (substr($item, -1, 1) ne "/") {
		$item .= "/";
	}
	if (opendir(DIR, $item)) {
		my @files = readdir(DIR);
		closedir(DIR);
		foreach my $file (@files) {
			if ( !-e $pidPath) {
				last;
			}
			my $temp = $item.$file;
			chomp($temp);
			if ($file =~ m/^$/) {
				next;
			}
			elsif ($file =~ m/^[\s\t]+$/) {
				next;
			}
			if ( $file eq "." or $file eq "..") {
				next;
			}
			elsif ( -l $temp # File is a symbolic link #
			 or -p $temp # File is a named pipe #
			 or -S $temp # File is a socket #
			 or -b $temp # File is a block special file #
			 or -c $temp )# File is a character special file #
			 #or -t $temp ) # Filehandle is opened to a tty #
			{
				print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$temp]. reason: Not a regular file/folder.\n";
				$Configuration::excludedCount++;
				if ($Configuration::excludedCount == EXCLUDED_MAX_COUNT) {
					$Configuration::excludedCount = 0;
					createExcludedLogFile30k();
				}
				next;
			}
			if (checkForExclude($temp)) {
				next;
			}

			if (-d $temp){
				if (!enumerate($temp)){
					$retVal = 0;
					last;
				}
			}
			else {
				if (!-e $temp) {
					#write into error
					my $reason = $!;
					if ($reason =~ /Permission denied/){
						$Configuration::noPermissionCount++;
						print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$temp]. Reason: $reason \n";
					} else {
						$Configuration::totalFiles++;
						$Configuration::nonExistsCount++;
						$Configuration::missingCount++ if ($reason =~ /No such file or directory/);
						print TRACEERRORFILE "[".(localtime)."] [FAILED] [$temp]. Reason: $reason \n";
					}
					next;
				}

				$Configuration::totalFiles++;
				$totalSize += -s $temp;
				if ($relative == 0) {
					my $item_orig = $item;
					if ($current_source ne "/") {
						$item_orig =~ s/$current_source//;
					}
					$temp = $item_orig.$file;
					print FH $temp."\n";
				}
				else {
					$current_source = "/";
					print NEWFILE $temp."\n";
					#$BackupsetFileTmp = $relativeFileset;
				}

				$filecount++;

				if ($filecount == FILE_MAX_COUNT) {
					if (!createBackupSetFiles1k()){
						$retVal = 0;
						last;
					}
				}
			}
		}
	}
	else {
		#write into error
		my $reason = $!;
		if ($reason =~ /Permission denied/){
			$Configuration::noPermissionCount++;
			print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $reason \n";
		} else {
			$Configuration::totalFiles++;
			$Configuration::nonExistsCount++;
			$Configuration::missingCount++ if ($reason =~ /No such file or directory/);
			print TRACEERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $reason \n";
		}
	}
	if ($Configuration::excludedCount == EXCLUDED_MAX_COUNT) {
		$Configuration::excludedCount = 0;
		createExcludedLogFile30k();
	}
	return $retVal;
}

#------------------------------------------------- F -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: fetchAllDevices
# Objective				: Fetch all devices for the current in user.
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub fetchAllDevices {
	createUTF8File('LISTDEVICE', $_[0]) or
		retreat('failed_to_create_utf8_file');
	my @responseData = runEVS('item');
	return @responseData;
}

#*****************************************************************************************************
# Subroutine			: findDependencies
# Objective				: Find whether package dependencies are met
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub findDependencies {
	my $display = (!defined($_[0]) || $_[0] == 1)? 1 : 0;

	display('checking_for_dependencies') if ($display);
	my $status = 0;
	for my $binary (@Configuration::dependencyBinaries) {
		display("dependency_$binary...", 0) if ($display);
		my $r = `which $binary 2>/dev/null`;
		if ($? == 0) {
			display(['found']) if ($display);
			$status = 1;
		}
		else {
			#traceLog($binary." not found");
			display(['not_found',"\n", "Please install ", $binary, " and try again."]) if ($display);
			$status = 0;
			last;
		}
	}
	return $status;
}

#*****************************************************************************************************
# Subroutine			: fetchServerAddress
# Objective				: Fetch current user's evs server ip
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub fetchServerAddress {
	createUTF8File('GETSERVERADDRESS') or retreat('failed_to_create_utf8_file');
	my @responseData = runEVS('tree');
	retreat('failed_to_fetch_server_address') if ($responseData[0]->{'STATUS'} eq Configuration::FAILURE);
	return @responseData;
}

#*****************************************************************************************************
# Subroutine			: formatEmailAddresses
# Objective				: This subroutine alters the email address in the required format.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub formatEmailAddresses {
	my ($inputEmails, $invalidEmails, $validEmails) 	= (shift, '', '');
	my @emails 	= ($inputEmails =~ /\,|\;/)? split(/\,|\;/, $inputEmails) : ($inputEmails);
	# my @newarray = grep(s/^\s+|\s+$//g, @emails);
	map { s/^\s+|\s+$//g; } @emails;
	my %hash   = map { $_ => 1 } @emails;
	my @newarray = keys %hash;
	foreach my $email (@newarray) {
		$email 	=~ s/^[\s\t]+|[\s\t]+$//g;
		if ($email ne '') {
			$validEmails .= qq($email, );
		}
	}
	$inputEmails = substr($validEmails, 0, -1);
	return $inputEmails;
}

#*****************************************************************************************************
# Subroutine Name         : formSendMailCurlcmd
# Objective               : forms curl command to send mail based on proxy settings
# Added By                : Dhritikana
#*****************************************************************************************************
sub formSendMailCurlcmd {
	#Assigning curl path
	my $curlPath = `which curl`;
	chomp($curlPath);
	if ($curlPath eq ''){
		$curlPath = '/usr/local/bin/curl';
	}
	my $cmd  = '';
	my $data = $_[0];
	my $proxyStr = getUserConfiguration('PROXY');
	if ($proxyStr) {
		my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
		my @UnP = split(/\:/, $uNPword);
		if (scalar(@UnP) >1 and $UnP[0] ne "") {
			$UnP[1] = ($UnP[1] ne '')?decryptString($UnP[1]):$UnP[1];
			foreach ($UnP[0], $UnP[1]) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$uNPword = join ":", @UnP;
			$cmd = "$curlPath -x http://$uNPword\@$ipPort -s -d '$data' '$Configuration::notifyPath'";
		} else {
			$cmd = "$curlPath -x http://$ipPort -s -d '$data' '$Configuration::notifyPath'";
		}
	} else {
		$cmd = "$curlPath -s -d '$data' '$Configuration::notifyPath'";
	}
	return $cmd;
}

#*****************************************************************************************************
# Subroutine		: fileWrite
# Objective			: Write/create a file with given data
# Added By			: Yogesh Kumar
#****************************************************************************************************/
sub fileWrite {
	my $mode = '>';
	$mode .= '>' if (defined($_[2] and $_[2] eq 'APPEND'));
	if (open(my $fh, $mode, $_[0])) {
		print $fh $_[1];
		close($fh);
		return 1;
	}
	else {
		display(['failed_to_open_file', " $_[0]. $!"]);
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine		: findMyDevice
# Objective			: Find the bucket which was linked with this machine
# Added By			: Yogesh Kumar
# Modified By		: Senthil Pandian
#****************************************************************************************************/
sub findMyDevice {
	my $devices = $_[0];
	my $displayStatus = defined($_[1]);
	my $muid = getMachineUID() or retreat('unable_to_find_mac_address');
	foreach (@{$devices}) {
		next	if ($muid ne $_->{'uid'});

		display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\". "),'do_you_want_edit_this_y_or_n_?'], 1);

		my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if (lc($answer) eq 'y') {
			my $deviceName = getAndValidate(["\n", 'enter_your_backup_location_optional', ": "], "backup_location", 1);
			if ($deviceName eq '') {
				$deviceName = $Configuration::hostname;
				$deviceName =~ s/[^a-zA-Z0-9_-]//g;
			}
			display('setting_up_your_backup_location',1);
			if ($deviceName and ($deviceName ne $_->{'nick_name'})) {
				my $restoreFrom = getUserConfiguration('RESTOREFROM');
				my $bkpLoc      = getUserConfiguration('BACKUPLOCATION');
				my $isSameDeviceID = 1;
				if ($restoreFrom and $restoreFrom eq $bkpLoc){
					$isSameDeviceID = 1;
				}
				retreat('update_device_name_failed_try_again_later') unless (renameDevice($_, $deviceName));
				$_->{'nick_name'} = $deviceName; # Added for Snigdha_2.17_74_4
				setUserConfiguration('RESTOREFROM',($Configuration::deviceIDPrefix .
					$_->{'device_id'} .$Configuration::deviceIDSuffix ."#" . $_->{'nick_name'})) if ($isSameDeviceID);
			}
			$displayStatus = 0;
		}

		display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\".")]) unless($displayStatus);
		setUserConfiguration('SERVERROOT', $_->{'server_root'});
		setUserConfiguration('BACKUPLOCATION',($Configuration::deviceIDPrefix .
			$_->{'device_id'} .$Configuration::deviceIDSuffix ."#" . $_->{'nick_name'}));
		loadNotifications() and setNotification('register_dashboard') and saveNotifications();
		return 1;
	}

	foreach (@{$devices}) {
		$_->{'uid'} =~ s/_1$//g;
		next	if ($muid ne $_->{'uid'});

		createUTF8File('LINKBUCKET',
		$Configuration::evsAPIPatterns{'LINKBUCKET'},
		$_->{'nick_name'},
		$_->{'device_id'},
		getMachineUID()) or retreat('failed_to_create_utf8_file');
		my @result = runEVS('item');

		if ($result[0]->{'STATUS'} eq Configuration::FAILURE) {
			print "$result[0]->{'MSG'}\n";
			return 0;
		}
		elsif ($result[0]->{'STATUS'} eq Configuration::SUCCESS) {
			display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\".")]);

			setUserConfiguration('BACKUPLOCATION',
			($Configuration::deviceIDPrefix . $_->{'device_id'} . $Configuration::deviceIDSuffix .
			"#" . $_->{'nick_name'}));
			loadNotifications() and setNotification('register_dashboard') and saveNotifications();
		}

		setUserConfiguration('SERVERROOT', $_->{'server_root'});
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine		: fileLock
# Objective			: Create and/or lock the given file
# Added By			: Yogesh Kumar
#****************************************************************************************************/
sub fileLock {
	unless (defined $_[0]) {
		display('filename_is_required');
		return 0;
	}

	open(our $fh, ">>", $_[0]) or return 0;
	unless (flock($fh, 2|4)) {
		display('failed_to_lock');
		close($fh);
		unlink($_[0]);
		return 0;
	}
	else {
		print $fh $$;
		autoflush $fh;
		return 1;
	}
}

#------------------------------------------------- G -------------------------------------------------#
#*********************************************************************************************
#Subroutine Name       : getItemFullPath
#Objective             : Provides path where all the scripts are saved.
#Added By              : Abhishek Verma
#*********************************************************************************************/
sub getItemFullPath{
	my $partialPath = $_[0];
	chomp(my $presentWorkingDir =`pwd`);
	$partialPath =~ s/^\.\/// if ($partialPath =~ /^\.\//);
	#print "\n PartialPath :: $partialPath\n";
	#print "\n presentWorkingDir :: $presentWorkingDir\n";
	#print "\n PartialPath2 :: ".$partialPath =~/(.*)\//?$1:$presentWorkingDir ."\n";
	#my $finallPath = $partialPath =~/(.*)\//?$1:$presentWorkingDir;
	my $finallPath = $partialPath ;#=~/(.*)\//?$1:$presentWorkingDir;
	#print "\n FinallPath1 :: $finallPath\n";
	if ($finallPath ne ''){
		$finallPath = $finallPath =~ /^\//?$finallPath:$presentWorkingDir."/".$finallPath;

	}
	else{
		$finallPath = $presentWorkingDir;
	}
	# resolve all '..' from the path
	$finallPath = getAbsolutePath(split('/',$finallPath))	if ($finallPath =~ /\.\./g);
	#print "\n FinallPath5 :: $finallPath\n";
	return $finallPath;
 }

 #**********************************************************************************************
#Sbroutine Name         : getAbsolutePath
#Objective              : retuns Absolute path for given relative path
#Usage                  : getAbsolutePath(LIST); ~List should not be hash~. eg:@relativePath = '/a/b/c/d/../../e/f/../g' AbsolutePath: /a/b/e/g
#Added By               : Abhishek Verma
#***********************************************************************************************
sub getAbsolutePath {
	for(my $i=0; $i<=$#_; $i++) {
		if ($_[$i] eq '..') {
			splice (@_, $i-1, 2);
			$i = $i-2;
		}
	}

	return join ('/', @_);
}

#*****************************************************************************************************
# Subroutine			: getAbsPath
# Objective				: Get the absolute path of a file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getAbsPath {
	return abs_path(shift);
}

#*****************************************************************************************************
# Subroutine			: getBackupsetSizeLockFile
# Objective				: Get backup set size lock file path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetSizeLockFile {
	return getCatfile(getUsersInternalDirPath($_[0]), $Configuration::backupsizelock);
}

#*****************************************************************************************************
# Subroutine			: getBackupsetSizeSycnLockFile
# Objective				: Get backup set size sync lock file path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetSizeSycnLockFile {
	return getCatfile(getUsersInternalDirPath($_[0]), $Configuration::backupsizesynclock);
}

#*****************************************************************************************************
# Subroutine			: getBackupsetFileAndMissingCount
# Objective				: get backup set file and missing count
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetFileAndMissingCount {
	my $backupsetfilecount	= 0;
	my $backupsetfile		= $_[0];
	return $backupsetfilecount if (!-f $backupsetfile || !-s $backupsetfile);

	my $backupsetdata	= getFileContents($backupsetfile, 'array');
	my $fname			= '';
	for my $i (0 .. $#{$backupsetdata}) {
		$fname			= @{$backupsetdata}[$i];
		chomp($fname);
		next if ($fname eq '');

		unless(-e $fname) {
			$backupsetfilecount++;
			next;
		}

		$backupsetfilecount++ if (-f $fname);
	}

	return $backupsetfilecount;
}

#*****************************************************************************************************
# Subroutine			: getBackupsetItemCount
# Objective				: get backup set item count
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetItemCount {
	my $backupsetitemcount	= 0;
	my $backupsetfile		= $_[0];
	return $backupsetitemcount if (!-f $backupsetfile || !-s $backupsetfile);

	my $backupsetdata	= getFileContents($backupsetfile, 'array');
	my $fname			= '';
	for my $i (0 .. $#{$backupsetdata}) {
		$fname			= @{$backupsetdata}[$i];
		chomp($fname);
		next if ($fname eq '');

		$backupsetitemcount++;
	}

	return $backupsetitemcount;
}

#*****************************************************************************************************
# Subroutine			: getBackupsetFileSize
# Objective				: Calculate backup set size of the files
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getBackupsetFileSize {
	my $fc 					= 0;
	my $backupsetdata 		= $_[0];
	my %backupsetsizes		= ();
	my $filename			= '';
	my $processingreq = 0;

	loadUserConfiguration();
	loadFullExclude();
	loadPartialExclude();
	loadRegexExclude();
	my $showhidden = getUserConfiguration('SHOWHIDDEN');

	for my $i (0 .. $#{$backupsetdata}) {
		$filename = @{$backupsetdata}[$i];
		chomp($filename);
		next if ($filename eq '');

		if (!-e $filename) {
			$backupsetsizes{$filename} = {'size' => 0, 'filecount' => 'NA', 'type' => 'u'};
		}
		elsif (-f $filename) {
			$backupsetsizes{$filename} = {'size' => getFileSize($filename, \$fc), 'filecount' => (isThisExcludedItemSet($filename . '/', $showhidden)? 'EX' : 'NA'), 'type' => 'f'};
		} else {
			$processingreq = 1;
			$backupsetsizes{$filename} = {'size' => -1, 'filecount' => 'NA', 'type' => 'd'};
		}
	}

	return ($processingreq, %backupsetsizes);
}

#*****************************************************************************************************
# Subroutine			: getCatfile
# Objective				: Get concatenating several directory and file names into a single path
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getCatfile {
	return catfile(@_);
}

#*****************************************************************************************************
# Subroutine			: getECatfile
# Objective				: Get concatenating several directory and file names into a single path with
#                   escaping space character
# Added By				: Yogesh Kumar, Vijay Vinoth
#****************************************************************************************************/
sub getECatfile {
	my $file = catfile(@_);
	$file =~ s/([^a-zA-Z0-9_])/\\$1/g;
	return qq($file);
}

#*****************************************************************************************************
# Subroutine			: getIDrivePerlBin
# Objective				: Get IDrive perl binary
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDrivePerlBin {
	return getECatfile(getServicePath(), $Configuration::staticPerlBinaryName);
}

#*****************************************************************************************************
# Subroutine			: getEditor
# Objective				: Get user's editor name if it is available or return default "vi" editor
# Added By				: Senthil pandian
#****************************************************************************************************/
sub getEditor {
#	return $ENV{EDITOR} || 'vi';
	return $ENV{EDITOR} || 'nano';
}

#*****************************************************************************************************
# Subroutine      : getMountPoints
# Objective       : Get all mounted list of devices
# Usage			  : Parameter is optional. Parameters can be either one from list('all','Writeable','Read-only','No access')
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar
#****************************************************************************************************/
sub getMountPoints {
	my $permissionChoice = defined($_[0]) ? $_[0] : "all";
	my %mountPoints = ();
	my @linuxOwnDefaultPartitions = (
		'/',
		'/dev',
		'/dev/',
		'/boot',
		'/boot/',
		'/sys/',
		'/usr/',
		'/var/',
		'/run',
		'/run/',
		'/tmp',
		'/.snapshots',
		'/srv',
		'/opt',
		'/opt/',
		'/home'
	);

	my $fileSystems = `df -k | grep -v Filesystem`;
	my @fsDetails;
	my @matches;
	my $targetMountDevice;
	foreach my $fileSystem (split("\n", $fileSystems)) {
		@fsDetails = split(/[\s\t]+/, $fileSystem, 6);
		next if (scalar(@fsDetails) < 5 || $fsDetails[5] eq '/');
		$targetMountDevice = (split(/\//, $fsDetails[5]))[1];
		@matches = grep { /^\/$targetMountDevice$/ } @linuxOwnDefaultPartitions;
		if ((scalar(@matches) > 0) or ($fsDetails[1] < 512000)) {
			next;
		}

		my $permissionMode = getFileFolderPermissionMode($fsDetails[5]);
		if ($permissionChoice eq $permissionMode || $permissionChoice eq 'all') {
			$mountPoints{$fsDetails[5]}{'type'} = 'd';
			$mountPoints{$fsDetails[5]}{'mode'} = $permissionMode;
		}
	}

	#Adding default mount point
	if (-d $Configuration::defaultMountPath){
		my $permissionMode = getFileFolderPermissionMode($Configuration::defaultMountPath);
		if ($permissionChoice eq $permissionMode || $permissionChoice eq 'all') {
			$mountPoints{$Configuration::defaultMountPath}{'type'} = 'd';
			$mountPoints{$Configuration::defaultMountPath}{'mode'} = $permissionMode;
		}
	}

	return \%mountPoints;
}

#*****************************************************************************************************
# Subroutine			: getUserFile
# Objective				: Build path to cached file
# Added By				: Yogesh Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub getUserFile {
	return ("$servicePath/$Configuration::cachedIdriveFile");
}

#*****************************************************************************************************
# Subroutine			: getOldUserFile
# Objective				: Build path to cached idrive file
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub getOldUserFile {
	return ("$servicePath/$Configuration::cachedFile");
}

#*****************************************************************************************************
# Subroutine			: getCachedDir
# Objective				: Build path to cached Directory
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getCachedDir {
	return ("$servicePath/cache");
}

#*****************************************************************************************************
# Subroutine			: getCachedStorageFile
# Objective				: Build path to user quota.txt  file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getCachedStorageFile {
	return (getUserProfilePath() . "/$Configuration::quotaFile");
}

#*****************************************************************************************************
# Subroutine Name         : getCursorPos
# Objective               : gets the current cusror position
# Added By                : Dhritikana
# Modified By             : Yogesh Kumar
#********************************************************************************************************/
sub getCursorPos {
	system('stty', '-echo');
	my $x='';
	my $inputTerminationChar = $/;
	my $linesToRedraw = $_[0];

	system "stty cbreak </dev/tty >/dev/tty 2>&1";
	print "\e[6n";
	$/ = "R";
	$x = <STDIN>;
	$/ = $inputTerminationChar;

	system "stty -cbreak </dev/tty >/dev/tty 2>&1";
	my ($curLines, $cols)=$x=~m/(\d+)\;(\d+)/;
	system('stty', 'echo');
	my $totalLines = `tput lines`;

	chomp($totalLines);
	my $threshold = $totalLines-$linesToRedraw;
	if ($curLines >= $threshold) {
		system("clear");
		print "\n";
		$curLines = 0;
	} else {
		$curLines = $curLines-1;
	}

	changeSizeVal();
	#Added for FreeBSD machine's progress bar display
	if ($Configuration::machineOS =~ /freebsd/i) {
		$latestCulmn = `tput cols`;
		my $freebsdProgress .= (' ')x$latestCulmn;
		$freebsdProgress .= "\n";
		$Configuration::freebsdProgress = $freebsdProgress;
	}
	system("tput sc");
	print "$_[1]" if ($_[1] and $_[1] ne '');
}

#*****************************************************************************************************
# Subroutine			: getEVSBinaryFile
# Objective				: Build path to user EVS binary file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getEVSBinaryFile {
	return ((defined(getUserConfiguration('DEDUP')) && getUserConfiguration('DEDUP') eq 'off')? "$servicePath/$Configuration::evsBinaryName" : "$servicePath/$Configuration::evsDedupBinaryName");
}

#****************************************************************************************************
# Subroutine Name         : getFinalMailAddrList
# Objective               : To get valid multiple mail address list
# Added By                : Dhritikana
#*****************************************************************************************************
sub getFinalMailAddrList
{
	my $count = 0;
	my $finalAddrList = '';
	my $configEmailAddress = $_[0];

	if ($configEmailAddress ne "") {
		my @addrList = ();
		if ($configEmailAddress =~ /\,|\;/) {
			@addrList = split(/\,|\;/, $configEmailAddress);
		} else {
			push(@addrList, $configEmailAddress);
		}

		foreach my $addr (@addrList) {
			Chomp(\$addr);
			if ($addr eq "") {
				next;
			}

			if (isValidEmailAddress($addr)) {
				$count++;
				$finalAddrList .= "$addr,";
			} else {
				print $Locale::strings{'failed_to_send_mail'}.$Locale::strings{'invalid_email_addresses_are_'}." $addr $lineFeed";
				traceLog($Locale::strings{'failed_to_send_mail'}.$Locale::strings{'invalid_email_addresses_are_'}." $addr $lineFeed", __FILE__, __LINE__);
				open ERRORFILE, ">>", $Configuration::errorFilePath;
				chmod $Configuration::filePermission, $Configuration::errorFilePath;
				autoflush ERRORFILE;

				print ERRORFILE $Locale::strings{'failed_to_send_mail'}.$Locale::strings{'invalid_email_addresses_are_'}." $addr $lineFeed";
				close ERRORFILE;
			}
		}

		if ($count > 0) {
			return $finalAddrList;
		}
		else {
			traceLog($Locale::strings{'failed_to_send_mail'}.$Locale::strings{'no_emails_configured'});
			return "NULL";
		}
	}
}

#****************************************************************************************************
# Subroutine			: getFolderDetail
# Objective				: This function will get properties of folder.
# Added By				: Senthil Pandian
#*****************************************************************************************************
sub getFolderDetail {
	my $remoteFolder  = $_[0];
	my $jobType 	  = $_[1]; #manual_archive

	my $filesCount = 0;
	my $jobRunningDir  = getUsersInternalDirPath($jobType);
	my $isDedup  	   = getUserConfiguration('DEDUP');
	my $backupLocation = getUserConfiguration('BACKUPLOCATION');

	my $itemStatusUTFpath = $jobRunningDir.'/'.$Configuration::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$Configuration::evsErrorFile;
	createUTF8File(['PROPERTIES',$itemStatusUTFpath],
				$evsErrorFile,
				$remoteFolder
				) or retreat('failed_to_create_utf8_file');

	my @responseData = runEVS('item',1);
	if (-s $evsErrorFile > 0) {
		checkExitError($evsErrorFile,$jobType.'_archive');
	}
	unlink($evsErrorFile);
	if (defined($responseData[1]->{'files_count'})){
		$filesCount = $responseData[1]->{'files_count'};
	}
	return $filesCount;
}

#*****************************************************************************************************
# Subroutine			: getHumanReadableSizes
# Objective				: Return file size in human readable format
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getHumanReadableSizes {
	my ($sizeInBytes) = @_;
	if ($sizeInBytes > 1073741824) {       #GiB: 1024 GiB
		return sprintf("%.2f GB", $sizeInBytes / 1073741824);
	}
	elsif ($sizeInBytes > 1048576) {          #   MiB: 1024 KiB
		return sprintf("%.2f MB", $sizeInBytes / 1048576);
	}
	elsif ($sizeInBytes > 1024) {             #   KiB: 1024 B
		return sprintf("%.2f KB", $sizeInBytes / 1024);
	}
	return "$sizeInBytes byte" . ($sizeInBytes == 1 ? "" : "s");
}

#*****************************************************************************************************
# Subroutine			: getIDPWDFile
# Objective				: Build path to IDPWD file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPWDFile {
	return (getUserProfilePath() . "/$Configuration::idpwdFile");
}

#*****************************************************************************************************
# Subroutine			: getIDENPWDFile
# Objective				: Build path to IDENPWD file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDENPWDFile {
	return (getUserProfilePath() . "/$Configuration::idenpwdFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPVTFile
# Objective				: Build path to IDPVT file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPVTFile {
	return (getUserProfilePath() . "/$Configuration::idpvtFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPVTSCHFile
# Objective				: Build path to getIDPVTSCHFile file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getIDPVTSCHFile {
	return (getUserProfilePath() . "/$Configuration::idpvtschFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPWDSCHFile
# Objective				: Build path to IDPWDSCH file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPWDSCHFile {
	return (getUserProfilePath() . "/$Configuration::idpwdschFile");
}

#*****************************************************************************************************
# Subroutine			: getLogsList
# Objective				: This subroutine gathers the list of log files
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getLogsList {
	return Taryck::getLogsList(@_);
	my %timestampStatus = ();
	my @tempLogFiles;
	my $currentLogFile ='';
	my $logDir = $_[0];

	if (-e $logDir) {
		@tempLogFiles = `ls '$logDir'`;
		%timestampStatus = map {m/(\d+)_([A-Za-z\_]+)/} @tempLogFiles;
	}
	return %timestampStatus;
}

#*****************************************************************************************************
# Subroutine			: getValidateRestoreFromFile
# Objective				: Build path to validateRestoreFromFile file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getValidateRestoreFromFile {
	return (getUserProfilePath() . "/$Configuration::validateRestoreFromFile");
}

#*****************************************************************************************************
# Subroutine			: machineHardwareName
# Objective				: Return $machineHardwareName
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getMachineHardwareName {
	return $machineHardwareName;
}

#*****************************************************************************************************
# Subroutine			: getIPAddr
# Objective				: Find the ip address of this machine
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIPAddr {
	return $mipa if ($mipa);

	my $cmd;
	my $ifConfigPath = `which ifconfig 2>/dev/null`;
	$mipa = '0.0.0.0';
	my $result = '';
	chomp($ifConfigPath);
	if (-f '/sbin/ip') {
		my @ip = `/sbin/ip r | grep 'src'`;
		@ip = split(' ', (split(' src ', $ip[0]))[1]);
		$mipa = $ip[0];
	}
	elsif ($ifConfigPath ne '') {
		my $ip = `ifconfig -a`;
		if ($ip =~ m/\s*inet (?:addr:)?([\d.]+).*?cast/) {
			$mipa = qq($1);
		}
	}

	return $mipa;
}

#*****************************************************************************************************
# Subroutine			: getMachineUID
# Objective				: Find the mac address
# Added By				: Yogesh Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub getMachineUID {
	return $muid if ($muid);

	my $cmd;
	my $prepend = '';
	$prepend = 'Linux' unless (defined($_[0]));
	my $ifConfigPath = `which ifconfig 2>/dev/null`;
	chomp($ifConfigPath);
	if ($ifConfigPath ne '') {
		$cmd = 'ifconfig -a';
	}
	elsif (-f '/sbin/ifconfig') {
		$cmd = '/sbin/ifconfig -a';
	}
	elsif (-f '/sbin/ip') {
		$cmd = '/sbin/ip addr';
	}
	else {
		retreat('unable_to_find_mac_address');
	}

	my $result = `$cmd`;
	my ($a, $macAddr, $b) = split(/((?:[0-9A-Fa-f:]{2}[:-]){5}[0-9A-Fa-f:]{2})/,$result);
	$macAddr =~ s/|:|-//g;
	if ($macAddr) {
		return ($muid = ("$prepend" . $macAddr)) ;
	}
	my $hostName = $Configuration::hostname;
	$result = 'Linux'.$hostName;
	return $result;
}

#*********************************************************************************************************
# Subroutine Name        : getAndSetMountedPath
# Objective              : This function will set & return mounted path
# Added By               : Senthil Pandian.
# Modified By            : Yogesh Kumar
#*********************************************************************************************************/
sub getAndSetMountedPath {
	my @linkDataList = ();
	my ($userInput,$choice) = (0) x 2;
	my $maxNumRetryAttempts = 3;
	my $localBackupLocation = '';

	#Verifying existing mount point for scheduled backup
	my $silentBackupFlag = shift || 0;
	if ($silentBackupFlag) {
		$localBackupLocation = getUserConfiguration('LOCALMOUNTPOINT');
		chomp($localBackupLocation);
		if ($localBackupLocation ne '') {
			if (!-e "$localBackupLocation") {
				traceLog($LS{'mount_point_not_exist'});
				exit 0;
			}
			elsif (!-w "$localBackupLocation") {
				traceLog($LS{'mount_point_doesnt_have_permission'});
				exit 0;
			}
			return $localBackupLocation;
		} else {
			traceLog($LS{'unable_to_find_mount_point'});
			exit 0;
		}
	}

	$localBackupLocation = getUserConfiguration('LOCALMOUNTPOINT');
	chomp($localBackupLocation);
	if ($localBackupLocation ne '') {
		if (!-d $localBackupLocation or getFileFolderPermissionMode($localBackupLocation) ne 'Writeable'){
			$localBackupLocation ='';
		}
	}

	if ($localBackupLocation){
		#my $mountPointQuery = Constants->CONST->{'YourPreviousMountPoint'}->($localBackupLocation);
		my $mountPointQuery = $LS{'your_previous_mount_point'};
		$mountPointQuery =~ s/<ARG>/$localBackupLocation/;
		display("\n$mountPointQuery");
		my $msg = $LS{'enter_your_choice'};
		my $loginConfirmation = getAndValidate($msg, "YN_choice", 1);
		if (lc($loginConfirmation) eq 'n'){
			goto USEEXISTING;
		}
	} else {
		display(["\n",'do_you_want_enter_mount_point']);
		my $msg = $LS{'enter_your_choice'};
		my $loginConfirmation = getAndValidate($msg, "YN_choice", 1);
		if (lc($loginConfirmation) eq 'n'){
			# display(["\n",'exit',"\n"]);
			cancelProcess();
		}
	}

	display('loading_mount_points');
	my $mountedDevices = getMountPoints();
	#my %mountedPath = ();
	if (scalar(keys %{$mountedDevices})>0){
		display(['select_mount_point',"\n"]);
		my @mountPointcolumnNames = (['S.No','Mount Point','Permissions'],[8,30,15]);
		my $tableHeader = getTableHeader(@mountPointcolumnNames);
		my ($tableData,$columnIndex,$serialNumber,$index) = ('',1,1,0);

		foreach my $mountPath (keys %{$mountedDevices}){
			$columnIndex = 1;

			my $mountDevicePath     = $mountPath;
			my $mountDevicePathPerm = $mountedDevices->{$mountPath}{'mode'};
			$index++;
			$tableData .= $serialNumber;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[0] - length($serialNumber));

			$mountDevicePath = trimData($mountDevicePath,$mountPointcolumnNames[1]->[$columnIndex]) if ($columnIndex == 1 or $columnIndex == 3);
			$tableData .= $mountDevicePath;
			$tableData .= (' ') x ($mountPointcolumnNames[1]->[$columnIndex] - length($mountDevicePath));
			$tableData .= $mountDevicePathPerm;
			$columnIndex++;
			$tableData .= "\n";
			$serialNumber += 1;
			push (@linkDataList,$mountPath);
		}
		if ($tableData ne ''){
			print $tableHeader.$tableData;
		}
	} else {
		display('unable_to_find_mount_point');
		#print 'Please check whether the external disk mounted properly or not.';
	}

	if (scalar(@linkDataList)>0){
		my $userChoice = getUserMenuOrCustomChoice('Enter the S.No. to select mount point. Press \'q\' in case your mount point is not listed above: ',@linkDataList);
		if ($userChoice eq 'q' or $userChoice eq 'Q'){
			@linkDataList = ();
		}
		elsif ($userChoice ne '') {
			$localBackupLocation = $linkDataList[$userChoice - 1];
		}
	}

	if (scalar(@linkDataList)<=0) {
		while ($maxNumRetryAttempts){
			display(["\n",'enter_mount_point'],0);
			$localBackupLocation = <STDIN>;
			Chomp(\$localBackupLocation);chomp($localBackupLocation);
			if (!-e "$localBackupLocation"){
				display(['mount_point_not_exist']);
			}
			elsif (!-w "$localBackupLocation") {
				display(['mount_point_doesnt_have_permission',"\n"]);
			}
			else {
				my $tempLoc = $localBackupLocation;
				$tempLoc =~ s/^[\/]+|^[.]+//;
				if (!$tempLoc) {
					display(['invalid_mount_point',"\n"]);
				} else {
					last;
				}
			}
			$maxNumRetryAttempts -= 1;
		}
		if ($maxNumRetryAttempts == 0){
			display(["\n", 'max_retry',"\n\n"]);
			cancelProcess();
		}
	}
	my $str = $LS{'your_selected_mount_point'};
	$str =~ s/<ARG>/$localBackupLocation/;
	display("$str\n");
	if ($localBackupLocation =~ /[\/]$/){
		chop($localBackupLocation);
	}

	setUserConfiguration('LOCALMOUNTPOINT', $localBackupLocation);
	saveUserConfiguration() or retreat('failed_to_save_user_configuration');
USEEXISTING:
	return $localBackupLocation;
}

#***********************************************************************
# Subroutine Name         : getPdata
# Objective               : Get Pdata in order to send Mail notification
# Added By                : Dhritikana.
#***********************************************************************
sub getPdata
{
	my $udata     = $_[0];
	my $pdata     = '';
	my $enPwdPath = getIDENPWDFile();
	chmod $Configuration::filePermission, $enPwdPath;
	if (!open FILE, "<", "$enPwdPath"){
		traceLog($lineFeed.$LS{'failed_to_open_file'}.$enPwdPath." failed reason:$! $lineFeed");
		return $pdata;
	}
	my $enPdata = <FILE>; chomp($enPdata);
	close(FILE);

	my $len = length($udata);
	my ($a, $b) = split(/\_/, $enPdata, 2);
	$pdata = unpack( "u", "$b");
	if ($len eq $a) {
		return $pdata;
	}
}

#*****************************************************************************************************
# Subroutine			: getPerlBinaryPath
# Objective				: Build path of Perl binary
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getPerlBinaryPath {
	#Assigning Perl path
	my $perlPath = `which perl`;
	Chomp(\$perlPath);
	if ($perlPath eq ''){
		$perlPath = '/usr/local/bin/perl';
	}
	return $perlPath;
}

#*************************************************************************************************
# Subroutine			: getCRONScheduleTime
# Objective				: This subroutine helps to find cron ran time using crontab json entry
# Added By				: Sabin Cheruvattil
#*************************************************************************************************/
sub getCRONScheduleTime {
	Helpers::loadCrontab();
	my ($mcuser, $idriveuser, $job, $jobset) = ($_[0], $_[1], $_[2], $_[3]);
	my $crontab = Helpers::getCrontab();

	if (defined($crontab->{$mcuser}) && defined($crontab->{$mcuser}{$idriveuser}) && defined($crontab->{$mcuser}{$idriveuser}{$job}) &&
	defined($crontab->{$mcuser}{$idriveuser}{$job}{$jobset})) {
		# my @now = (localtime)[1,2,3,4,6,5];
		# my $timestring = sprintf('%.2d', ($now[3] + 1)) . '-' . sprintf('%.2d', $now[2]) . '-' . ($now[5] + 1900);
		# $timestring .= ' ' . sprintf('%.2d', $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'h'}) . ':' .
							 # sprintf('%.2d', $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'m'});

		my @now 		= localtime;
		$now[0] 		= 0;
		$now[1] 		= $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'m'};
		$now[2] 		= $crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'h'} if ($crontab->{$mcuser}{$idriveuser}{$job}{$jobset}{'h'} =~ /\d+/);
		my $timestring	= localtime(mktime(@now));

		return $timestring;
	}

	return '';
}

#*************************************************************************************************
# Subroutine			: getOSBuild
# Objective				: This subroutine helps to find OS build and release version
# Added By				: Sabin Cheruvattil
#*************************************************************************************************/
sub getOSBuild {
	my ($os, $build) = ('', 0);

	# check OS release file
	if (-f '/etc/os-release') {
		my $osres = `cat /etc/os-release`;
		Chomp(\$osres);

		$os		= $1 if ($osres =~ /ID=(.*?)\n/s);
		$os		=~ s/\"//gs;
		$os		= 'debian' if (index(`uname -n`, 'debian') != -1);

		$build	= $1 if ($osres =~ /VERSION_ID="(.*?)"\n/s);
		$build	= $1 if (($osres =~ /VERSION_ID=(.*?)\n/s) && $build == 0);

		if (($build eq '' || $build == 0) && -f '/etc/gentoo-release') {
			$osres = `uname -r`;
			Chomp(\$osres);
			$build = qq($1.$2) if ($osres =~ /(.*?)\.(.*?)\.(.*?)-(.*?)/is);
		}

		if (-f '/etc/issue') {
			$osres = `cat /etc/issue`;
			Chomp(\$osres);

			$os = 'opensuse' if (index(lc($osres), 'opensuse') != -1);
		}

		return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
	}

	# Check lsb_release is avaialble or not
	my $isLsbRelease = `which lsb_release 2>/dev/null`; #Added for FreeBSD: Senthil
	if ($isLsbRelease) {
		my $lsbres	= `lsb_release -a 2> /dev/null`;
		Chomp(\$lsbres);
		if ($lsbres ne '') {
			$os		= $2 if ($lsbres =~ /Distributor ID:(\s*)(.*?)(\s*)\n/s);
			$build	= $2 if ($lsbres =~ /Release:(\s*)(.*?)(\s*)\n/s);
			my @buildvers = split('\.', $build);
			$build	= qq($buildvers[0].$buildvers[1]) if (scalar(@buildvers) > 2);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $isHostnamectl = `which hostnamectl 2>/dev/null`; #Added for FreeBSD: Senthil
	if ($isHostnamectl) {
		my $hostctlstat = `hostnamectl status`;
		my $uname		= `uname -n`;
		Chomp(\$hostctlstat); Chomp(\$uname);
		if ($hostctlstat ne '' && $uname ne '') {
			$os		= $uname;
			$build	= $3 if ($hostctlstat =~ /Operating System:(\s*)$os(\s*)(.*?)(\s*)(.*?)\n/si);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	my $isSysctl = `which sysctl 2>/dev/null`; #Added by Senthil
	if ($isSysctl) {
		my $sysctlos = `sysctl -n kern.ostype 2>/dev/null`;
		my $sysctlbuild = `sysctl -n kern.osrelease 2>/dev/null`;
		chomp($sysctlos); chomp($sysctlbuild);
		if ($sysctlos ne '' && $sysctlbuild ne '') {
			$os		= $sysctlos;
			$build	= $1 if ($sysctlbuild =~ /(.*?)-(.*?)/i);
			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	if (-f '/etc/issue' && index(`uname -n`, 'debian') != -1) {
		my $osres = `cat /etc/issue`;
		Chomp(\$osres);

		$os			= 'debian';
		my @dbuild	= split('\ ', $osres);
		$build		= $dbuild[2];
		return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
	}

	if (-f '/etc/issue') {
		my $osres = `cat /etc/issue`;
		$os			= 'fedora' if (index($osres, 'Fedora') != -1);
		if ($os eq 'fedora') {
			$osres	= `cat /etc/fedora-release`;
			Chomp(\$osres);
			$build	= $1 if ($osres =~ /fedora release\s(.*)\s/si);

			return {'os' => lc($os), 'build' => $build} if ($os ne '' && ($build ne '' && $build != 0));
		}
	}

	return {'os' => $os, 'build' => $build};
}

#*****************************************************************************************************
# Subroutine			: getCRONSetupTemplate
# Objective				: This is get cron setup template
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getCRONSetupTemplate {
	my $opconf		= {};
	my $os 			= getOSBuild();
	my $oscronconfs = $Configuration::cronLaunchCodes{$os->{'os'}};

	foreach my $opkey (keys %{$oscronconfs}) {
		my @opver	= split('-', $opkey);
		if (($opver[0] eq 'btw' && (split('_', $opver[1]))[0] <= $os->{'build'} && $os->{'build'} <= (split('_', $opver[1]))[1]) ||
			($opver[0] eq 'gt' && $os->{'build'} > $opver[1]) || ($opver[0] eq 'lt' && $os->{'build'} < $opver[1]) ||
			($opver[0] eq 'gte' && $os->{'build'} >= $opver[1]) || ($opver[0] eq 'lte' && $os->{'build'} <= $opver[1])) {
			$opconf = $oscronconfs->{$opkey};
			last;
		}
	}

	return $opconf;
}

#*****************************************************************************************************
# Subroutine			: getIDriveFallBackCRONEntry
# Objective				: This is to prepare fall back cron entry
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getIDriveFallBackCRONEntry {
	# m h dom mon dow    user    command
	return qq(0 1 * * *    root    $Configuration::perlBin '$Configuration::cronLinkPath'\n);
}

#*************************************************************************************************
#Subroutine Name               : getPSoption
#Objective                     : This subroutine will return the machine based ps option.
#Added By                      : Senthil Pandian
#*************************************************************************************************/
sub getPSoption{
	my $psOption = "-elf";
	$machineInfo = `uname -a`;
	chomp($machineInfo);
	if ($machineInfo =~ /freebsd/i){
		$psOption = "-auxww";
	}
	return $psOption;
}

#*****************************************************************************************************
# Subroutine			: getRunningJobs
# Objective				: Check if pid file exists & file is locked, then return it all
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getRunningJobs {
	my @availableJobs;
	my $jobType = $_[1] || 0; # 0 - all, 1 - manual, 2 - scheduled

	if (defined($_[0]) and reftype(\$_[0]) eq 'SCALAR') {
		@availableJobs = $_[0];
	}
	elsif (defined($_[0])) {
		unless (exists $Configuration::availableJobsSchema{$ARGV[0]}) {
			push @availableJobs, lc($ARGV[0]);
		} else {
			push @availableJobs, $ARGV[0];
		}
	}
	else {
		@availableJobs = keys %Configuration::availableJobsSchema;
	}

	my %runningJobs;
	my ($ps, $psimmd, $pid, $cmd);
	foreach (@availableJobs) {
		my @p = split '_', $_;

		unless (exists $Configuration::availableJobsSchema{$_}) {
			retreat(['undefined_job_name', ': ', $_]);
		}

		my $pidFile = getCatfile(getUserProfilePath(), $Configuration::userProfilePaths{$_}, 'pid.txt');
		if (-f $pidFile) {
			if (!isFileLocked($pidFile)) {
				unlink($pidFile);
				next;
			}

			if ($jobType) {
				$pid = getFileContents($pidFile);
				$ps = `ps $pid | grep '.pl SCHEDULED $username'`;
				$psimmd = `ps $pid | grep '.pl immediate $username'`;
				next if (($ps ne '' || $psimmd ne '') and $jobType == 1);
				next if (($ps eq '' && $psimmd eq '') and $jobType == 2);
			}

			$runningJobs{$_} = $pidFile;
		}
	}
	return %runningJobs;
}

#*****************************************************************************************************
# Subroutine			: getServicePath
# Objective				: Build path to service location file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getServicePath {
	return $servicePath;
}

#*****************************************************************************************************
# Subroutine			: setServicePath
# Objective				: Assign service path
# Added By				: Deepak Chaurasia
#****************************************************************************************************/
sub setServicePath {
	$servicePath = $_[0];
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getServerAddressFile
# Objective				: Build path to serverAddress file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getServerAddressFile {
	return (getUserProfilePath() . "/$Configuration::serverAddressFile");
}

#*****************************************************************************************************
# Subroutine			: getAppPath
# Objective				: This subroutine helps to get scripts path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getAppPath {
	loadAppPath() unless $appPath;
	return $appPath;
}

#*****************************************************************************************************
# Subroutine			: getUserHomePath
# Objective				: Find and return the parent directory name
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUserHomePath {
	return $ENV{'HOME'};
}

#*****************************************************************************************************
# Subroutine			: getJobsPath
# Objective				: Build path to the given jobs path
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getJobsPath {
	unless (exists $Configuration::availableJobsSchema{$_[0]}) {
		retreat(['job_name', $_[0], 'doesn\'t exists'], 1);
	}

	my $key = $_[1];

	$key = 'path' unless (defined $_[1]);

	my $jp = $Configuration::availableJobsSchema{$_[0]}{$key};
	$jp =~ s/__SERVICEPATH__/getServicePath()/eg;
	$jp =~ s/__USERNAME__/getUsername()/eg;
	return $jp;
}

#*****************************************************************************************************
# Subroutine			: getUserChoice
# Objective				: Take the user input value and return
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUserChoice {
	my $echoBack = shift;
	$echoBack = 1 unless(defined($echoBack));
	my $input = '';

	unless ($Configuration::callerEnv eq 'BACKGROUND') {
		system('stty', '-echo') unless ($echoBack);
		chomp($input = <STDIN>);
	}
	else {
		$input = 'BACKGROUND';
	}
	# added by anil on 30may2018 to replace spaces and tab in user input.
	$input =~ s/^[\s\t]+|[\s\t]+$//g;
	unless ($echoBack) {
		system('stty', 'echo');
		display('');
	}
	return $input;
}

#*****************************************************************************************************
# Subroutine			: getTotalSize
# Objective				: Take the user input value and return
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub getTotalSize
{
	my $totalSizeFilePath = $_[0];
	my $totalSize = 0;
	if (-e $totalSizeFilePath and !-z $totalSizeFilePath){
		open totalSizeFileHandler, "< $totalSizeFilePath";
		$totalSize = <totalSizeFileHandler>;
		close totalSizeFileHandler;
		chomp($totalSize);
	}
	return $totalSize;
}
#*****************************************************************************************************
# Subroutine			: getUserChoiceWithRetry
# Objective				: Take input and give retry option if required after validating the input
# Added By				: Anil Kumar
#****************************************************************************************************/
# sub getUserChoiceWithRetry {
	# my $minRange = 1;
	# my $maxRange = shift;
	# my $userChoice = '';
	# my $maxRetry = 4;
	# while ($maxRetry and $userChoice eq ''){
		# display(["\n", 'enter_your_choice'], 0);
		# my $input = getUserChoice();
		# unless(validateMenuChoice($input, $minRange, $maxRange)) {
			# display('invalid_option', 1);
			# $userChoice = '';
			# $maxRetry--;
		# } else {
			# $userChoice = $input;
		# }
	# }
	# if ($maxRetry == 0 and $userChoice eq ''){
		# retreat('your_max_attempt_reached');
	# }else{
		# return $userChoice;
	# }
# }

#*****************************************************************************************************
# Subroutine			: getLocaleString
# Objective				: Gets the actual string using string token
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getLocaleString {
	return '' unless($_[0]);
	return '__no_locale__' unless(exists($LS{$_[0]}));
	return $LS{$_[0]};
}

#*****************************************************************************************************
# Subroutine			: getUserProfilePath
# Objective				: Build path to user profile info
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserProfilePath {
	return ("$servicePath/$Configuration::userProfilePath/$Configuration::mcUser/$username");
}

#****************************************************************************************************
# Subroutine    : getUsersInternalDirPath
# Objective		: Build path to user's internal directories
# Added By		: Sabin Cheruvattil
#****************************************************************************************************/
sub getUsersInternalDirPath {
	unless(exists $Configuration::userProfilePaths{$_[0]}) {
		retreat(["$_[0]: ", 'does_not_exists']);
	}
	return getUserProfilePath() . qq(/$Configuration::userProfilePaths{$_[0]});
}

#*****************************************************************************************************
# Subroutine			: getUserConfigurationFile
# Objective				: Build path to user configuration file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUserConfigurationFile {
	return getUserProfilePath() . ("/$Configuration::userConfigurationFile");
}

#*****************************************************************************************************
# Subroutine			: getUpdateVersionInfoFile
# Objective				: Build path to user .updateVersionInfo  file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUpdateVersionInfoFile {
	return ("$appPath/$Configuration::updateVersionInfo");
}

#*****************************************************************************************************
# Subroutine			: getUserConfiguration
# Objective				: Get user configured values
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserConfiguration {
	return %userConfiguration unless (defined $_[0]);
	my $field = (defined $_[1]) ? $_[1] : 'VALUE';

	if ($_[0] eq 'dashboard') {
		my %uc = ();
		map {
		$uc{$_} = $userConfiguration{$_}{$field} if ($Configuration::userConfigurationSchema{$_}{'for_dashboard'})
		} keys %Configuration::userConfigurationSchema;
		return %uc;
	}

	unless(exists $userConfiguration{$_[0]}) {
		#display(["WARNING: $_[0] ", 'is_not_set_in_user_configuration']);
		traceLog($_[0]." is not set in user configuration");
		return 0;
	}
	return $userConfiguration{$_[0]}{$field};
}

#*****************************************************************************************************
# Subroutine			: getUsername
# Objective				: Get username from $username
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUsername {
	return $username;
}

#*****************************************************************************************************
# Subroutine			: getServerAddress
# Objective				: Get server address from $serverAddress
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getServerAddress {
	unless ($serverAddress) {
		(saveServerAddress(fetchServerAddress()) and loadServerAddress() ) or retreat('failed_to_getserver_addr');
	}
	return $serverAddress;
}

#*****************************************************************************************************
# Subroutine			: getTotalStorage
# Objective				: This subroutine return the total storage available for the user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getTotalStorage {
	return $totalStorage;
}
sub getTotalStorage_raw {
	return $totalStorage_Raw_TBE;
}

#*****************************************************************************************************
# Subroutine			: getFreeStorage
# Objective				: This subroutine return the free storage 
# Added By				: TBE
#****************************************************************************************************/
sub getFreeStorage {
	return getHumanReadableSizes( $totalStorage_Raw_TBE - $storageUsed_Raw_TBE );
}
sub getFreeStorage_raw {
	return ( $totalStorage_Raw_TBE - $storageUsed_Raw_TBE );
}

#*****************************************************************************************************
# Subroutine			: getStorageUsed
# Objective				: This subroutine return the total storage used by the user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStorageUsed {
	return $storageUsed;
}
sub getStorageUsed_raw {
	return $storageUsed_Raw_TBE;
}
#*****************************************************************************************************
# Subroutine			: getTableHeader
# Objective				: This is to process table header to display list of buckets
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getTableHeader{
	my $logTableHeader = ('=') x (eval(join '+', @{$_[1]}));
	$logTableHeader .= "\n";
	for (my $contentIndex = 0; $contentIndex < scalar(@{$_[0]}); $contentIndex++){
		$logTableHeader .= $_[0]->[$contentIndex];
		#(total_space - used_space by data) will be used to keep separation between 2 data.
		$logTableHeader .= (' ') x ($_[1]->[$contentIndex] - length($_[0]->[$contentIndex]));
	}
	$logTableHeader .= "\n";
	$logTableHeader .= ('=') x (eval(join '+', @{$_[1]}));
	$logTableHeader .= "\n";
	return $logTableHeader;
}

#*****************************************************************************************************
# Subroutine			: getUserFilePath
# Objective				: This subroutine constructs the edit file path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserFilePath {
	my $pathHolder = shift;
	$pathHolder =~ s/__SERVICEPATH__/getServicePath()/eg;
	$pathHolder =~ s/__USERNAME__/getUsername()/eg;
	return $pathHolder;
}

#*****************************************************************************************************
# Subroutine			: getUserMenuChoice
# Objective				: This subroutine helps to get the user's choices
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserMenuChoice {
	my($userMenuChoice, $choiceRetry, $maxChoice) = (0, 0, shift);
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		display(["\n", 'enter_your_choice_', ': '], 0);
		$userMenuChoice = getUserChoice();
		$choiceRetry++;
		if ($userMenuChoice eq '') {
			display(['cannot_be_empty', '.', ' ', 'enter_again', '.']);
			checkRetryAndExit($choiceRetry);
		}
		elsif (!validateMenuChoice($userMenuChoice, 1, $maxChoice)) {
			$userMenuChoice = '';
			display(['invalid_choice', ' ', 'please_try_again', '.']);
			checkRetryAndExit($choiceRetry);
		} else {
			last;
		}
	}
	return $userMenuChoice;
}

#*****************************************************************************************************
# Subroutine			: getUserMenuOrCustomChoice
# Objective				: This subroutine helps to get the user's choices
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getUserMenuOrCustomChoice {
	my($userMenuChoice, $choiceRetry) = (0, 0);
	my($customMsg,@option) = @_;
	my $maxChoice = scalar(@option);
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		display(["\n", $customMsg], 0);
		$userMenuChoice = getUserChoice();
		$userMenuChoice	=~ s/^[\s\t]+|[\s\t]+$//g;
		$choiceRetry++;
		if ($userMenuChoice eq '') {
			display(['cannot_be_empty', '.', ' ', 'enter_again', '.']);
		}
		elsif ($userMenuChoice eq 'q' or $userMenuChoice eq 'Q'){
			last;
		}
		elsif (!validateMenuChoice($userMenuChoice, 1, $maxChoice)) {
			$userMenuChoice = '';
			display(['invalid_choice', ' ', 'please_try_again', '.']);
		}
		else {
			my $path 		   = $option[$userMenuChoice-1];
			my $permissionMode = getFileFolderPermissionMode($path);
			if ($permissionMode eq 'Writeable'){
				last;
			} else {
				display('mount_point_doesnt_have_permission');
			}
		}
		if ($choiceRetry == $Configuration::maxChoiceRetry){
			display(["\n", 'your_max_attempt_reached', "\n"]);
			cancelProcess();
		}
	}
	return $userMenuChoice;
}

#*****************************************************************************************************
# Subroutine			: getUserMenuChoiceBuckSel
# Objective				: This subroutine helps to get the user's choices
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserMenuChoiceBuckSel {
	my($userMenuChoice, $choiceRetry, $maxChoice) = ('', 0, shift);
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		display(["\n", 'enter_your_choice_', ': '], 0);
		$userMenuChoice = getUserChoice();
		$userMenuChoice	=~ s/^[\s\t]+|[\s\t]+$//g;
		$choiceRetry++;
		if ($userMenuChoice eq '') {
			last;
		}
		elsif (!validateMenuChoice($userMenuChoice, 1, $maxChoice)) {
			$userMenuChoice = '';
			display(['invalid_choice', ' ', 'please_try_again', '.']);
			checkRetryAndExit($choiceRetry);
		} else {
			last;
		}
	}
	return $userMenuChoice;
}

#*****************************************************************************************************
# Subroutine			: getStringWithScriptName
# Objective				: This subroutine helps to get the strings with script names
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStringWithScriptName {
	my ($stringToken, $tokenMessage, $opHolder) = (shift, '', '');
	return $tokenMessage if !$stringToken;

	$tokenMessage = $LS{'please_login_account_using_login_and_try'};
	foreach my $opScript (keys %Configuration::idriveScripts) {
		$opHolder = '___' . $opScript . '___';
		$tokenMessage =~ s/$opHolder/$Configuration::idriveScripts{$opScript}/eg
	}
	return $tokenMessage;
}

#*****************************************************************************************************
# Subroutine			: getMachineUser
# Objective				: This gets the name of the user who executes the script
# Added By				: Sabin Cheruvattil
# Modified By			: Anil, Senthil Pandian
#****************************************************************************************************/
sub getMachineUser {
	#return $ENV{'LOGNAME'};
	my $mcUser = `whoami`;
	Chomp(\$mcUser);
	return $mcUser;
}

#*****************************************************************************************************
# Subroutine			: getTraceLogPath
# Objective				: Helps to retrieve the log path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getTraceLogPath {
	$username = '' unless defined $username;
	return getUserProfilePath() . qq(/$Configuration::traceLogDir/$Configuration::traceLogFile);
}

#*****************************************************************************************************
# Subroutine			: getUserModUtilCMD
# Objective				: Helps to user mod change utility
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserModUtilCMD {
	my $modUtils	= ['runuser', 'su'];
	my $modFlags	= ['-l', '-m'];
	my $cmdCheck 	= '';

	return 'su -m ' if (isGentoo());

	for my $i (0 .. $#{$modUtils}) {
		$cmdCheck = `which $modUtils->[$i]`;
		Chomp(\$cmdCheck);

		return qq($modUtils->[$i] $modFlags->[$i]) if ($cmdCheck ne '');
	}

	return '';
}

#*****************************************************************************************************
# Subroutine			: getAndValidate
# Objective				: This subroutine is used to take input ad ask for the retry option if it fails to validate.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getAndValidate {
	my $message = $_[0];
	my $fieldType = $_[1];
	my $isEchoEnabled = $_[2];
	my $isMandatory = (defined($_[3]) ? $_[3] : 0) ;
	my ($userInput, $choiceRetry) = ('', 0);

	while($choiceRetry < $Configuration::maxChoiceRetry) {
		display($message, 0);
		$userInput = getUserChoice($isEchoEnabled);
		$choiceRetry++;
		if (($userInput eq '') && ($isMandatory)){
			display(['cannot_be_empty', '.', ' ', 'enter_again', '.', "\n"], 1);
			checkRetryAndExit($choiceRetry, 0);
		}
		elsif (!validateDetails($fieldType, $userInput)) {
			checkRetryAndExit($choiceRetry, 0);
		} else {
			last;
		}
	}
	return $userInput;
}

#*****************************************************************************************************
# Subroutine			: getInvalidEmailAddresses
# Objective				: This subroutine validates email addresses
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getInvalidEmailAddresses {
	my ($inputEmails, $invalidEmails) 	= (shift, '');
	my @emails 	= ($inputEmails =~ /\,|\;/)? split(/\,|\;/, $inputEmails) : ($inputEmails);
	foreach my $email (@emails) {
		$email 	=~ s/^[\s\t]+|[\s\t]+$//g;
		if ($email ne '' && !isValidEmailAddress($email)) {
			$invalidEmails .= qq($email, );
		}
	}
	if ($invalidEmails) {
		#$invalidEmails =~ s/(?<!\w)//g;
		$invalidEmails =~ s/\s+$//;
		substr($invalidEmails,-1,1,".");
		display(['invalid_email_addresses_are_', $invalidEmails]);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getRemoteAccessToken
# Objective				: Read from or write to accesstoken.txt file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteAccessToken {
	my %params = (
		'host'   => $Configuration::idriveLoginCGI,
		'method' => 'POST',
		'json'   => 1,
		'data'=> {
			'uid' => getUsername(),
			'pwd'  => &Helpers::getPdata(getUsername())
		}
	);

	my $response = request(\%params);
	if ($response->{STATUS} eq 'FAILURE') {
		return 0;
	}
	elsif (ref($response) eq 'HASH') {
		return $response->{DATA}{'token'};
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: getScript
# Objective				: get absolute path to the script file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getScript {
	my $script = getCatfile($appPath, $Configuration::idriveScripts{$_[0]});
	if (-f $script) {
		return $script unless(defined($_[1]) and $_[1] == 1);
		return getECatfile($script);
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getParentRemoteManageIP
# Objective				: Read remote manage address
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getParentRemoteManageIP {
	#return getUserConfiguration('PRMSH');
	return getUserConfiguration('PRMIH');
}

#*****************************************************************************************************
# Subroutine			: getRemoteManageIP
# Objective				: Read remote manage address
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteManageIP {
	#return getUserConfiguration('RMSH');
	return getUserConfiguration('RMIH');
}

#*****************************************************************************************************
# Subroutine			: getNotificationFile
# Objective				: Path to notification file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getNotificationFile {
	return (getUserProfilePath() . "/$Configuration::notificationFile");
}

#*****************************************************************************************************
# Subroutine			: getNotifications
# Objective				: Get notification value
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getNotifications {
	return \%notifications unless(defined $_[0]);

	if (exists $notifications{$_[0]}) {
		return $notifications{$_[0]};
	}
	elsif (exists $Configuration::notificationsSchema{$_[0]}) {
		loadNotifications();
		$notifications{$_[0]} = $Configuration::notificationsSchema{$_[0]};
		saveNotifications();
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getCrontabFile
# Objective				: Path to crontab data file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getCrontabFile {
	return qq(/etc/$Configuration::crontabFile);
}

#*****************************************************************************************************
# Subroutine			: getMigrateLockFile
# Objective				: Path to migrate user lock file
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub getMigrateLockFile {
	return getAppPath().$Configuration::migUserlock;
}


#*****************************************************************************************************
# Subroutine			: getMigrateCompletedFile
# Objective				: Path to migrate user lock file
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub getMigrateCompletedFile {
	return getAppPath().$Configuration::migUserSuccess;
}

#*****************************************************************************************************
# Subroutine			: getCRONLockInfo
# Objective				: This method gets the locks stats in array format
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getCRONLockInfo {
	return [] unless(-e $Configuration::cronlockFile);
	return split('--', getFileContents($Configuration::cronlockFile));
}

#*****************************************************************************************************
# Subroutine			: getSudoSuCRONPerlCMD
# Objective				: This is to get sudo/su command for running perl scripts in root mode
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getSudoSuCRONPerlCMD {
	return '' unless(defined($_[0]));
	return "$Configuration::perlBin '" . getAppPath() . $Configuration::idriveScripts{'utility'} . "' " . uc($_[0]) if ($Configuration::mcUser eq 'root');

	display(["\n", $_[1], '.']) if (!isUbuntu() && !isGentoo());

	my $command = "su -c \"$Configuration::perlBin '" . getAppPath() . $Configuration::idriveScripts{'utility'} . "' " . uc($_[0]) . "\" root";
	$command 	= "sudo -p '" . $LS{$_[1]} . ": ' " . $command if (isUbuntu() || isGentoo());

	return $command;
}

#*****************************************************************************************************
# Subroutine			: getSudoSuCMD
# Objective				: This is to get sudo/su command for running the scripts in root mode
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getSudoSuCMD {
	return '' unless(defined($_[0]));
	return $_[0] . (defined($_[2])? ' &' : '') if ($Configuration::mcUser eq 'root');
	my $message = (defined($LS{$_[1]}))?$LS{$_[1]}:$_[1];
	display(["\n", $message]) if (!isUbuntu() && !isGentoo());
	my $command = "su -c \"$_[0]" . (defined($_[2])? ' &' : '') . "\" root";
	$command 	= "sudo -p '" . $message . ": ' " . $command if (isUbuntu() || isGentoo());

	return $command;
}

#*****************************************************************************************************
# Subroutine			: getCrontab
# Objective				: Get crontab value
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getCrontab {
	return \%crontab unless(defined $_[0]);
	my $jobType = shift || retreat('crontabs_jobname_is_required');
	my $jobName = shift  || retreat('crontab_title_is_required');
	my $key     = shift;

	$jobType = $Configuration::availableJobsSchema{$jobType}{'type'} if (exists $Configuration::availableJobsSchema{$jobType});
	$jobType = 'backup' if ($jobType eq 'express_backup'); # TODO: IMPORTANT to review this statement again.

	if (exists $crontab{$Configuration::mcUser} && exists $crontab{$Configuration::mcUser}{$username} &&
		exists $crontab{$Configuration::mcUser}{$username}{$jobType} && exists $crontab{$Configuration::mcUser}{$username}{$jobType}{$jobName} &&
		eval("exists \$crontab{\$Configuration::mcUser}{\$username}{\$jobType}{\$jobName}$key")) {
		return eval("\$crontab{\$Configuration::mcUser}{\$username}{\$jobType}{\$jobName}$key");
	}

#TBE	return 0;
	return undef;
}

#*****************************************************************************************************
# Subroutine			: getFileContents
# Objective				: Get a file content
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getFileContents {
	unless (defined($_[0])) {
		retreat('filename_is_required');
	}
	my $returnType = 'string';
	$returnType = $_[1] if (defined $_[1]);

	my $fileContent = '';
	if (open(my $fileHandle, '<', $_[0])) {
		if ($returnType eq 'array') {
			chomp(my @fc = <$fileHandle>);
			$fileContent = \@fc;
		}
		else {
			$fileContent = join('', <$fileHandle>);
		}
		close($fileHandle);
		return $fileContent;
	}

	retreat(['unable_to_open_file',' : ', $_[0], " $!"]);
}

#*****************************************************************************************************
# Subroutine			: getStartAndEndEpochTime
# Objective				: To return the start and end date epoch time.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStartAndEndEpochTime {
	# $userChoice => 1) One week before, 2) Two week before, 3) One month before, 4) Given date range
	my $userOption = shift;
	my $currentTimeStamp = time();
	my $daysToSubstract = ($userOption == 1) ? 7 : ($userOption == 2) ? 14 : 30;
	my $startTimeStamp = $currentTimeStamp - ($daysToSubstract * 24 * 60 * 60);
#	my $startTimeStamp_ISO = Taryck::TS2ISO($startTimeStamp);
#	my $currentTimeStamp_ISO = Taryck::TS2ISO($currentTimeStamp);
#	return ($startTimeStamp_ISO, $currentTimeStamp_ISO);
	return ($startTimeStamp, $currentTimeStamp);
}

#*****************************************************************************************************
# Subroutine			: getStartAndEndEpochTimeForMigration
# Objective				: To return the start and end date epoch time.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getStartAndEndEpochTimeForMigration {
	my %logFilenames = %{$_[0]};
	my $lastLogTime  = time();
	foreach(sort {$b <=> $a} keys %logFilenames) {
		$lastLogTime = $_;
		last;
	}

	#my $currentTimeStamp = time();
	my $daysToSubstract = 7;
	my $startTimeStamp = $lastLogTime - ($daysToSubstract * 24 * 60 * 60);
	return ($startTimeStamp, $lastLogTime);
}

#*****************************************************************************************************
# Subroutine			: setCronCMD
# Objective				: Prepare cron command for available jobs
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Anil Kumar
#****************************************************************************************************/
sub setCronCMD {
	my $jobType = $_[0];
	$jobType = $Configuration::availableJobsSchema{$jobType}{'type'} if (exists $Configuration::availableJobsSchema{$jobType});
	$jobType = 'backup' if ($jobType eq 'express_backup'); # TODO: IMPORTANT to review this statement again.
	my $runas = 0;
	my %status = ();
	$status{"status"} = Configuration::FAILURE;
	$status{"errmsg"} = '';
	if (getCrontab($jobType, $_[1], '{settings}{frequency}') eq 'immediate') {

		# to intimate response to dashboard for start immediately.
		my $jt = $jobType;
		$jt = 'localbackup' if ($jobType eq 'express_backup');

		# my $isBackupRunning = 1;
		# $isBackupRunning = isJobRunning($jt,$Configuration::dashbtask);
		# if ($isBackupRunning) {
			# $status{"status"} = Configuration::FAILURE;
			# $status{"errmsg"} = $LS{$jt.'_in_progress_try_again'} ;
			# return %status;
		# }

		if($jt eq 'backup'){
			my $isArchiveRunning = 1;
			$isArchiveRunning = Helpers::isJobRunning('archive');
			if ($isArchiveRunning) {
				$status{"status"} = Configuration::FAILURE;
				$status{"errmsg"} = $LS{'archive_in_progress_try_again'} ;
				return %status;
			}
		}

		if (exists $Configuration::availableJobsSchema{$jt}) {
			my $fileset = Helpers::getJobsPath($jt, 'file');
			unless (-f $fileset and !-z $fileset) {
				$status{"status"} = Configuration::FAILURE;
				$status{"errmsg"} = "$_[1]: is empty";
				return %status;
			}
		}
		$status{'status'} = Configuration::SUCCESS;

		$runas = 1 ;
		my @now		= localtime;
		my $hrs = $now[2];
		my $min = $now[1];
		if ($min > 58) {
			$hrs = $hrs + 1;
			$min = -1;
		}
		setCrontab($jobType, $_[1], 'h', $hrs);
		setCrontab($jobType, $_[1], 'm', ($min + 1));
	}

	if ($jobType eq "cancel") {
		if ($_[1] eq 'default_backupset') {
			setCrontab($jobType, $_[1], 'cmd', sprintf("%s %s - 2", q(") . getScript('job_termination') . q("), 'backup'));
		}
		elsif ($_[1] eq 'local_backupset') {
			setCrontab($jobType, $_[1], 'cmd', sprintf("%s %s - 2", q(") . getScript('job_termination') . q("), 'localbackup'));
		}
		$status{'status'} = Configuration::SUCCESS;
	}
	elsif (($jobType eq 'backup') and ($_[1] eq 'default_backupset')) {
		setCrontab($jobType, $_[1], 'cmd', sprintf($Configuration::availableJobsSchema{$jobType}{'croncmd'}, q(") . getScript('backup_scripts') . q("), $Configuration::availableJobsSchema{$jobType}{'runas'}->[$runas], getUsername()));
		$status{'status'} = Configuration::SUCCESS;
	}
	elsif (($jobType eq 'backup') and ($_[1] eq 'local_backupset')) {
		setCrontab($jobType, $_[1], 'cmd', sprintf($Configuration::availableJobsSchema{$jobType}{'croncmd'}, q(") . getScript('express_backup') . q("), $Configuration::availableJobsSchema{$jobType}{'runas'}->[$runas], getUsername()));
		$status{'status'} = Configuration::SUCCESS;
	}
	elsif ($jobType eq 'archive') {
		my $cmd = getCrontab($jobType, $_[1], '{cmd}');
		my @params = split(' ', $cmd);
		my @now     = localtime;
		setCrontab($jobType, $_[1], 'cmd', sprintf($Configuration::availableJobsSchema{$jobType}{'croncmd'}, q(") . getScript('archive_cleanup') . q("), getUsername(), $params[0], $params[1], mktime(@now)));

		# Store previous minute
		my $acrchmin 	= $now[1];
		my $archhr		= $now[2];

		if ($acrchmin == 0) {
			$acrchmin 	= 59;
			$archhr		= (($archhr == 0)? 23 : ($archhr - 1));
		} else {
			$acrchmin--;
		}

		setCrontab($jobType, $_[1], 'h', $archhr);
		setCrontab($jobType, $_[1], 'm', $acrchmin);
		$status{'status'} = Configuration::SUCCESS;
	}
	elsif ($jobType eq $Configuration::dashbtask) {
		setCrontab($jobType, $_[1], 'cmd', getScript('dashboard'));
		$status{'status'} = Configuration::SUCCESS;
	}
	return %status;
}

#****************************************************************************************************
# Subroutine Name         : getFileFolderPermissionMode
# Objective               : This subroutine will return permission mode of file/folder.
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub getFileFolderPermissionMode
{
	my $path = $_[0];
	my $permissionMode = '';
	if (-w $path) {
		if (open(FH, ">$path/check_write.txt")){
			$permissionMode = 'Writeable';
			close(FH);
			#system "rm '$path/check_write.txt'";
			removeItems("$path/check_write.txt");
		} else {
			$permissionMode = 'Read-only';
		}
	}
	elsif (-r $path) {
		$permissionMode = 'Read-only';
	}
	else {
		$permissionMode = 'No access';
	}
	return $permissionMode;
}

#****************************************************************************************************
# Subroutine Name         : getParameterValueFromStatusFileFinal.
# Objective               : Fetches the value of individual parameters which are specified in the
#                           Status file.
# Added By                : Vijay Vinoth.
#*****************************************************************************************************/
sub getParameterValueFromStatusFileFinal
{
	my @linesStatusFile = @Configuration::linesStatusFile;
	undef @linesStatusFile;

	my @statusFinalHashData;
	my @inputData = @_;

	my $stf = readFinalStatus();
	my %statusFinalHash = %{$stf};
	foreach(@inputData) {
		if (defined $statusFinalHash{$_}){
			push (@statusFinalHashData, $statusFinalHash{$_});
		} else {
			push (@statusFinalHashData, 0);
		}
	}
	return (@statusFinalHashData);
}

#*******************************************************************************************************
# Subroutine Name         :	getSystemCpuCores
# Objective               :	Get system processor and core details.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/
sub getSystemCpuCores{
    my $cmd = "uname";
	chomp(my $OS = `$cmd`);
	$OS = lc $OS;
	my $retVal = 2;
	my ($cmdCpuCores,$totalCores);
	if ($OS eq "freebsd"){
	  $totalCores = `sysctl -a | grep 'hw.ncpu' | cut -d ':' -f2`;
	  chomp($totalCores);
	  $totalCores = int($totalCores);
	  $retVal = ($totalCores == 1 ? 2 : ($totalCores == 2 ? 4 : $totalCores));
    }
	elsif ($OS eq "linux"){
	  my $cpuProcessorCount = `cat /proc/cpuinfo | grep processor | wc -l`;
	  chomp($cpuProcessorCount);
	  $cmdCpuCores = `grep 'cpu cores' /proc/cpuinfo | tail -1 | cut -d ':' -f2`;
	  chomp($cmdCpuCores);

	  $cmdCpuCores = ($cmdCpuCores ne "" ? int($cmdCpuCores) : 1);
	  $cpuProcessorCount = ($cpuProcessorCount ne "" ? int($cpuProcessorCount) : 1);

	  $totalCores = $cpuProcessorCount*$cmdCpuCores;
	  $retVal = ($totalCores == 1 ? 2 : ($totalCores == 2 ? 4 : $totalCores));
	}

	return $retVal;
}

#*******************************************************************************************************
# Subroutine Name         :	getLoadAverage
# Objective               :	Get Average Load time of the machine.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/
sub getLoadAverage {
	my $cmd = "uname";
	my $load_avg;
	my ( @one_min_avg );
	chomp(my $OS = `$cmd`);
	$OS = lc $OS;
	if ($OS ne "freebsd"){
		open(LOAD, "/proc/loadavg") or die "Unable to get server load \n";
		$load_avg = <LOAD>;
		close LOAD;
		my ( @one_min_avg ) = split /\s/, $load_avg;
		return (sprintf '%.2f', $one_min_avg[1]);
	}else{
		my $load_avg_data = 'uptime | awk \'{print $(NF-2)" "$(NF-1)" "$(NF-0)}\' | tr "," " "\'\'';
		$load_avg = `$load_avg_data`;
		chomp($load_avg);
		my ( @one_min_avg ) = split /\s/, $load_avg;
		return (sprintf '%.2f', $one_min_avg[2]);
	}
}

#*********************************************************************************************************
#Subroutine Name        : getDeviceHash
#Objective              : This function will provide the device list.
#Added By               : Senthil Pandian.
#*********************************************************************************************************/
sub getDeviceHash {
	my @devices = fetchAllDevices();
	my %resultHash;
	foreach my $value (@devices){
		my $key = $value->{'uid'};
		Chomp(\$key);
		$resultHash{$key} = $value;
	}
	return %resultHash;
}

#****************************************************************************************************
# Subroutine Name         : generateBackupsetFiles.
# Objective               : This function will generate backupset files.
# Added By				  : Dhritikana
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub generateBackupsetFiles {
	my $pidPath				= $Configuration::jobRunningDir."/".$Configuration::pidFile;
	my $backupsetFile       = $Configuration::jobRunningDir."/".$Configuration::backupsetFile;
	my $relativeFileset     = $Configuration::jobRunningDir."/".$Configuration::relativeFileset;
	my $noRelativeFileset   = $Configuration::jobRunningDir."/".$Configuration::noRelativeFileset;
	my $filesOnly		    = $Configuration::jobRunningDir."/".$Configuration::filesOnly;
	my $errorDir 	        = $Configuration::jobRunningDir."/".$Configuration::errorDir;
	my $excludeDir 	        = $Configuration::jobRunningDir."/".$Configuration::excludeDir;
	my $excludedLogFilePath = $excludeDir."/".$Configuration::excludedLogFile;
	my $fileForSize			= $Configuration::jobRunningDir."/".$Configuration::fileForSize;
	my $info_file 			= $Configuration::jobRunningDir."/".$Configuration::infoFile;
	my $relative 		    = backupTypeCheck();
	my (@source);
	$Configuration::totalFiles = 0;

	open FD_WRITE, ">>", $info_file or (print $LS{'failed_to_open_file'}." info_file: $info_file to write, Reason:$!");

	$Configuration::pidOperationFlag = "GenerateFile";
	if (!open(BACKUPSETFILE_HANDLE, $backupsetFile)) {
		$Configuration::errStr = $LS{'failed_to_open_file'}." : $backupsetFile. Reason:$!\n";
		traceLog($Configuration::errStr);
		goto GENLAST;
	}
	my @BackupArray = <BACKUPSETFILE_HANDLE>;
	close(BACKUPSETFILE_HANDLE);
	my $traceExist = $errorDir."/traceExist.txt";
	if (!open(TRACEERRORFILE, ">>", $traceExist)) {
		$Configuration::errStr = $LS{'failed_to_open_file'}." : $traceExist. Reason:$!\n";
		traceLog($Configuration::errStr);
	}
	chmod $Configuration::filePermission, $traceExist;

	my $permissionError = $errorDir."/".$Configuration::permissionErrorFile;
	if (!open(TRACEPERMISSIONERRORFILE, ">>", $permissionError)) {
		$Configuration::errStr = $LS{'failed_to_open_file'}." : $permissionError. Reason:$!\n";
		traceLog($Configuration::errStr);
	}
	chmod $Configuration::filePermission, $permissionError;

	# require to open excludedItems file to log excluded details
	if (!open(EXCLUDEDFILE, ">", $excludedLogFilePath)){
		$Configuration::errStr = $LS{'failed_to_open_file'}." : $excludedLogFilePath. Reason:$!\n";
		retreat($Configuration::errStr);
	}
	chmod $Configuration::filePermission, $excludedLogFilePath;

	#my $filesonlycount = 0;
	$Configuration::excludedFileIndex = 1;
	my $j =0;
	chomp(@BackupArray);
	@BackupArray = uniqueData(@BackupArray);
	foreach my $item (@BackupArray) {
		if (!-e $pidPath){
			last;
		}
		$item =~ s/^[\/]+|[\/]+$/\//g; #Removing "/" if more than one found at beginning/end
		if ($item =~ m/^$/) {
			next;
		}
		elsif ($item =~ m/^[\s\t]+$/) {
			next;
		}
		elsif ($item eq "." or $item eq "..") {
			next;
		}
		elsif ( -l $item # File is a symbolic link #
			 or -p $item # File is a named pipe #
			 or -S $item # File is a socket #
			 or -b $item # File is a block special file #
			 or -c $item )# File is a character special file #
		#	 or -t $item ) # Filehandle is opened to a tty #
		{
			print EXCLUDEDFILE "[".(localtime)."] [EXCLUDED] [$item]. Reason: Not a regular file/folder \n";
			$Configuration::excludedCount++;
			if ($Configuration::excludedCount == EXCLUDED_MAX_COUNT) {
				$Configuration::excludedCount = 0;
				createExcludedLogFile30k();
			}
			next;
		}
		Chomp(\$item);
		if ($item ne "/" && substr($item, -1, 1) eq "/") {
			chop($item);
		}

		if (checkForExclude($item)) {
			next;
		}
		if (-d $item) {
			if ($relative == 0) {
				$Configuration::noRelIndex++;
				$BackupsetFile_new = $noRelativeFileset."$Configuration::noRelIndex";
				$filecount = 0;
				$a = rindex ($item, '/');
				$source[$Configuration::noRelIndex] = substr($item,0,$a);
				if ($source[$Configuration::noRelIndex] eq "") {
					$source[$Configuration::noRelIndex] = "/";
				}
				$current_source = $source[$Configuration::noRelIndex];

				if (!open FH, ">>", $BackupsetFile_new) {
					traceLog("cannot open $BackupsetFile_new to write ");
					goto GENLAST;
				}
				chmod $Configuration::filePermission, $BackupsetFile_new;
			}

			if (!enumerate($item)){
				goto GENLAST;
			}

			if ($relative == 0 && $filecount>0) {
				autoflush FD_WRITE;
				close FH;
				#print FD_WRITE "$BackupsetFile_new ".RELATIVE." $current_source\n";
				print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
			}
		}
		else {
			if (!-e $item) {
				#write into error
				my $reason = $!;
				if ($reason =~ /Permission denied/){
					$Configuration::noPermissionCount++;
					print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $reason \n";
				} else {
					$Configuration::totalFiles++;
					$Configuration::nonExistsCount++;
					$Configuration::missingCount++ if ($reason =~ /No such file or directory/);
					print TRACEERRORFILE "[".(localtime)."] [FAILED] [$item]. Reason: $reason \n";
				}
				next;
			}

			$Configuration::totalFiles++;
			$totalSize += -s $item;
			print NEWFILE $item."\n";
			$current_source = "/";

			if ($relative == 0) {
				$Configuration::filesonlycount++;
				$filecount = $Configuration::filesonlycount;
			}
			else {
				$filecount++;
			}

			if ($filecount == FILE_MAX_COUNT) {
				$Configuration::filesonlycount = 0;
				if (!createBackupSetFiles1k("FILESONLY")){
					goto GENLAST;
				}
			}
		}
	}

	if ($relative == 1 && $filecount > 0) {
		autoflush FD_WRITE;
		#print FD_WRITE "$BackupsetFile_new ".RELATIVE." $current_source \n";
		print FD_WRITE "$current_source' '".RELATIVE."' '$BackupsetFile_new\n";
	}
	elsif ($Configuration::filesonlycount >0) {
		$current_source = "/";
		autoflush FD_WRITE;
		#print FD_WRITE "$filesOnly ".NORELATIVE." $current_source\n";
		print FD_WRITE "$current_source' '".NORELATIVE."' '$filesOnly\n";
	}

GENLAST:
	autoflush FD_WRITE;
	print FD_WRITE "TOTALFILES $Configuration::totalFiles\n";
	print FD_WRITE "FAILEDCOUNT $Configuration::nonExistsCount\n";
	print FD_WRITE "DENIEDCOUNT $Configuration::noPermissionCount\n";
	print FD_WRITE "MISSINGCOUNT $Configuration::missingCount\n";
	close FD_WRITE;
	close NEWFILE;
	$Configuration::pidOperationFlag = "generateListFinish";
	#close INFO;

	open FILESIZE, ">$fileForSize" or traceLog($LS{'failed_to_open_file'}." : $fileForSize. Reason:$!\n");
	print FILESIZE "$totalSize";
	close FILESIZE;
	chmod $Configuration::filePermission, $fileForSize;

	close(TRACEERRORFILE);
	close(TRACEPERMISSIONERRORFILE);
	close(EXCLUDEDFILE);
	exit 0;
}

#******************************************************************************************************************
# Subroutine Name		: getEmailSubLine.
# Objective				: This subroutine returns email subject line
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#******************************************************************************************************************/
sub getEmailSubLine {
	my $taskType  = ucfirst($_[0]);
	my $opType    = ucfirst($_[1]);
	my $userName  = getUsername();
	my $subjectLine = "";
	my $chk = Configuration::JOBEXITCODE->{'SUCCESS'};

	if ($Configuration::opStatus =~ /$chk/) {
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX');
		my ($successfiles, $filetotal) = (0) x 2;

		($successfiles) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);

		if ($Configuration::totalFiles) {
			$filetotal = $Configuration::totalFiles;
			Chomp(\$filetotal);
		}

		if ($successfiles > 0) {
			$subjectLine = "$taskType $opType Status Report " . "[$userName]" . " [Backed up file(s): $successfiles of $filetotal]" . " [Successful $opType]";
		} else {
			$subjectLine = "$taskType $opType Status Report " . "[$userName]" . " [Successful $opType]";
		}
	} else {
		$subjectLine = "$taskType $opType Status Report " . "[$userName]" . " [$Configuration::opStatus $opType]";
	}

	return ($subjectLine);
}
#*********************************************************************************************************
# Subroutine Name		: getLocalBackupDir
# Objective				: This function will return the local backup location(Directory path)
# Added By				: Senthil Pandian.
# Modified By			: Sabin Cheruvattil
#*********************************************************************************************************/
sub getLocalBackupDir {
	return $backupLocationDir . '/';
}

#*****************************************************************************************************
# Subroutine			: getPropSettingsFile
# Objective				: Path to prop settings file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getPropSettingsFile {
	if (defined($_[0]) and $_[0] eq 'master') {
		return getCatfile(getUserProfilePath(), $Configuration::masterPropsettingsFile);
	}

	return getCatfile(getUserProfilePath(), $Configuration::propsettingsFile);
}

#****************************************************************************************************
# Subroutine Name : getPropSettings.
# Objective       : Load prop settings
# Added By        : Yogesh Kumar
#*****************************************************************************************************/
sub getPropSettings {
	my $ps = getPropSettingsFile($_[0]);
	return {} unless (-f $ps and !-z $ps);

	my $p = {};
	eval {
		$p = from_json(getFileContents($ps));
		1;
	}
	or do {
		fileWrite($ps, '');
		$p = {};
	};

	return $p;
}

#****************************************************************************************************
# Subroutine Name         : getParameterValueFromStatusFile.
# Objective               : Fetches the value of individual parameters which are specified in the
#                           Account Settings file.
# Added By                : Arnab Gupta.
# Modified By			  : Deepak Chaurasia, Dhritikana
#*****************************************************************************************************/
sub getParameterValueFromStatusFile
{
	my @linesStatusFile = @Configuration::linesStatusFile;
	if ($#linesStatusFile le 1) {
		readStatusFile($_[1]);
	}
	my @keys = keys %Configuration::statusHash;
	my $size = @keys;
	if ($size and defined($Configuration::statusHash{$_[0]})){
		return $Configuration::statusHash{$_[0]};
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine		: getConsideredFilesCountFromLog
# Objective			: Get considered files count from Log file content
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getConsideredFilesCountFromLog {
	my $logFile 	= $_[0];
	my @logContent  = `tail -n10 '$logFile'`;
	my $considered	= "--";
	my $isSummary	= 0;
	foreach (@logContent) {
		my $line = $_;
		if (!$isSummary and $line =~ m/Summary:/) {
			$isSummary = 1;
		}
		elsif ($isSummary and $line =~ m/considered/){
			$considered = (split(":", $line))[1];
			Chomp(\$considered);
			last;
		}
	}
	return $considered;
}

#*****************************************************************************************************
# Subroutine		: getDuration
# Objective			: Get duration in seconds between two dates
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getDuration {
	return int((($_[0] - $_[1]) % 86400) / 3600);
}

#*****************************************************************************************************
# Subroutine			: getDirectorySize
# Objective				: Get directory size
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getDirectorySize {
	my ($dir, $size, $fd, $fc) = ($_[0], 0, undef, $_[1]);
	my $path = '';
	my $showhidden = getUserConfiguration('SHOWHIDDEN');

	unless(opendir($fd, $dir)) {
		traceLog("Couldn't open the directory: $dir; $!");
		return 0;
	}

	for my $item(readdir($fd)) {
		next if ($item =~ /^\.\.?$/);
		$path = qq($dir/$item);
		next if (-l $path || -p $path || -S $path || -b $path || -c $path);

		if (-d $path && !-l $path) {
			$size += getDirectorySize($path, $fc);
		}
		elsif (!-l $path && !-p $path && !-S $path && !-b $path && !-c $path && -f $path){
			unless(isThisExcludedItemSet($path . '/', $showhidden)) {
				$size += -s $path;
				${$fc} += 1;
			}
		}
	}

	closedir($fd);
	return $size;
}

#*****************************************************************************************************
# Subroutine			: getFileSize
# Objective				: Get directory size
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getFileSize {
	if (-f $_[0] && !-l $_[0] && !-p $_[0] && !-S $_[0] && !-b $_[0] && !-c $_[0]) {
		${$_[1]} = ${$_[1]} + 1;
		return -s $_[0];
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine		: getFileModifiedTime
# Objective			: Get modified time of file
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getFileModifiedTime {
	my $epoch = stat($_[0])->mtime;
	return ($epoch)?$epoch:0;
}

#*****************************************************************************************************
# Subroutine		: getLastOneWeekLogs
# Objective			: get logs files for last 7 days from the last log file's date
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getLastOneWeekLogs {
	my (%logStat,$jobDir);
	my %logFilenames = ();

	unless (defined($_[1]) and defined($_[2])) {
		retreat('start_and_end_dates_are_required');
	}

	if (defined($_[0]) and defined($_[3])){
		$jobDir = $_[3];
	} else {
		return \%logStat;
	}

	if (defined($_[0]) and ref($_[0]) eq 'HASH') {
		%logFilenames = %{$_[0]};
	} else {
		return \%logStat;
	}

	#my $lf = tie(my %logFiles, 'Tie::IxHash');
	my $logsFound = 0;
	foreach(sort {$b <=> $a} keys %logFilenames) {
		if ((($_[1] <= $_) && ($_[2] >= $_))) {
			$logsFound = 1;
			my $file = $jobDir."/".$_."_".$logFilenames{$_};
			print NEWFILE $file."\n";
			my $modifiedTime = getFileModifiedTime($file);
			my $duration     = getDuration($_,$modifiedTime);
			$duration     	 = ($duration =~ /^\d+$/)?$duration:"--";
			my $filescount 	 = getConsideredFilesCountFromLog($file);
			$filescount    	 = ($filescount =~ /^\d+$/)?$filescount:"--";
			$logStat{$_} = {
				'filescount' 	=> $filescount,
				'duration'		=> $duration,
				'status'   		=> $logFilenames{$_},
				'datetime' 		=> strftime("%d/%m/%Y %H:%M:%S", localtime($_))
			};
		}
		elsif ($logsFound) {
			last;
		}
	}
	return \%logStat;
}

#*****************************************************************************************************
# Subroutine		: getLocalDataWithType
# Objective			: Get existing local file/folder names with type.
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getLocalDataWithType{
	my %list;
	foreach my $ori_item (@{$_[0]}){
		chomp($ori_item);
		my $item = Taryck::extendBackupItem($ori_item);
		if( -l $item # File is a symbolic link #
			or -p $item # File is a named pipe #
			or -S $item # File is a socket #
			or -b $item # File is a block special file #
			or -c $item )# File is a character special file #
		{
			display(["Skipped [$ori_item]. ", "Reason",'not_a_regular_file']);
			$skippedItem = 1;
			next;
		} elsif (-d $item) {
			$ori_item .= (substr($ori_item,-1) ne '/')?'/':'';
			$list{$ori_item}{'type'} = 'd';
		}
		elsif (-f $item) {
			$list{$item}{'type'} = 'f';
		} else {
			display(["Skipped [$ori_item]. ", "Reason",'file_folder_not_found']);
			$skippedItem = 1;
		}
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine		: getRemoteDataWithType
# Objective			: Get existing remote file/folder names with type.
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getRemoteDataWithType{
	my %list;
	my $jobRunningDir  = getUsersInternalDirPath('restore');
	my $isDedup  	   = getUserConfiguration('DEDUP');
	my $restoreFromLoc = getUserConfiguration('RESTOREFROM');
	$restoreFromLoc = '/'.$restoreFromLoc  if($isDedup eq 'off' and $restoreFromLoc !~ m/^\//);
	#print "restoreFromLoc:$restoreFromLoc\n";
	my $tempFilePath = $jobRunningDir."/".$Configuration::tempBackupsetFile;
	if(!open(ITEMLISTNEW, ">", $tempFilePath)){
		#$errMsg = $Locale::strings{'failed_to_open_file'}.": $tempFilePath, Reason: $!";
		return 0;
	}

	my $finalRestoreFromLoc= '';
	$finalRestoreFromLoc = $restoreFromLoc	if($isDedup eq 'off' and $restoreFromLoc ne '/');

	my @arryToCheck = ();
	foreach(@{$_[0]}) {
		push @arryToCheck, $finalRestoreFromLoc.$_."\n";
	}

	print ITEMLISTNEW @arryToCheck;
	close(ITEMLISTNEW);

	my $itemStatusUTFpath = $jobRunningDir.'/'.$Configuration::utf8File;
	my $evsErrorFile      = $jobRunningDir.'/'.$Configuration::evsErrorFile;
	createUTF8File(['ITEMSTATUS',$itemStatusUTFpath,1],
		$tempFilePath,
		$evsErrorFile
		) or retreat('failed_to_create_utf8_file');

	my @responseData = runEVS('item',1);
	unlink($tempFilePath);

	if(-s $evsErrorFile > 0) {
		my $errStr = checkExitError($evsErrorFile,'restore');
		retreat($errStr);
	}
	unlink($evsErrorFile);
	if($isDedup eq 'on'){
		foreach my $tmpLine (@responseData) {
			my @fields = $tmpLine;
			if (ref($fields[0]) ne "HASH") {
				next;
			}
			my $itemName = $fields[0]{'fname'};
			replaceXMLcharacters(\$itemName);
			#$itemName =~ s/^[\/]+/\//g;
			if($fields[0]{'status'} =~ /directory exists/) {
				$list{$itemName}{'type'} = 'd';
			}
			elsif($fields[0]{'status'} =~ /file exists/){
				$list{$itemName}{'type'} = 'f';
			}
			else {
				my $restoreFromBuck = (split("#",$restoreFromLoc))[1];
				$itemName =~ s/^\/(.*?)\//\/$restoreFromBuck\//;
				display(["Skipped [$itemName]. ", "Reason",'file_folder_not_found']);
				$skippedItem = 1;
			}
		}
	} else {
		foreach my $tmpLine (@responseData) {
			my @fields   = $tmpLine;
			if (ref($fields[0]) ne "HASH") {
				next;
			}
			my $itemName = $fields[0]{'fname'};
			replaceXMLcharacters(\$itemName);
			if($finalRestoreFromLoc ne '/'){
				$itemName =~ s/$finalRestoreFromLoc//;
			}
			if($fields[0]{'status'} =~ /directory exists/) {
				$list{$itemName}{'type'} = 'd';
			}
			elsif($fields[0]{'status'} =~ /file exists/){
				$list{$itemName}{'type'} = 'f';
			}
			else {
				$itemName = $fields[0]{'fname'};
				display(["Skipped [$itemName]. ", "Reason",'file_folder_not_found']);
				$skippedItem = 1;
			}
		}
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine		: getUniquePresentData
# Objective			: Remove duplicate items & return the unique file/folder names which is present.
# Added By 			: Senthil Pandian
#****************************************************************************************************/
sub getUniquePresentData
{
	my @itemArray = uniqueData(@{$_[0]});
	my $fileType = $_[1];
	my %list;
	if($fileType eq 'restore'){
		%list = getRemoteDataWithType(\@itemArray);
	} else {
		%list = getLocalDataWithType(\@itemArray);
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine		: getJobSetLogSummary
# Objective			: Prepares job set summary for operation logs
# Added By 			: Sabin Cheruvattil
#****************************************************************************************************/
sub getJobSetLogSummary {
	my $jobtype = $_[0];
	return '' unless($jobtype);

	my $jsf = Helpers::getJobsPath($jobtype, 'file');
	return '' if(!-f $jsf || -s $jsf == 0);

	my ($fsum, $dsum, $usum, $summary) = ('', '', '', '');
	if (open(my $jsc, '<', "$jsf.info")) {
		while(my $filename = <$jsc>) {
			chomp($filename);

			my $filetype = <$jsc>;
			chomp($filetype);
			
			next if($filename eq '');

			# IMPORTANT: DO NOT REMOVE: if($filetype eq 'f' || (lc($jobtype) =~ /backup/ && -f $filename)) {
			if($filetype eq 'f') {
				$fsum .= qq($filename\n);
			# IMPORTANT: DO NOT REMOVE: } elsif($filetype eq 'd' || (lc($jobtype) =~ /backup/ && -d $filename)) {
			} elsif($filetype eq 'd') {
				$dsum .= qq($filename\n);
			} else {
				$usum .= qq($filename\n);
			}
		}
		
		$summary .= (($fsum ne '')? "Files\n" . $fsum : '');
		$summary .= (($dsum ne '')? "Directories\n" . $dsum : '');
		$summary .= (($usum ne '')? "Unknown\n" . $usum : '');
		return $summary;
	}
	
	traceLog("failed to open file $jsf.info $!");
	return '';
}

#------------------------------------------------- H -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: hasEVSBinary
# Objective				: Execute evs binary and check it's working or not
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub hasEVSBinary {
	my $dir = shift;
	my @evsBinaries = (
		$Configuration::evsBinaryName,
		$Configuration::evsDedupBinaryName
	);
	my $duplicate = 1;

	unless(defined($dir)) {
		$dir = getServicePath();
		$duplicate = 0;
	}
	for (@evsBinaries) {
		my $evs = $dir."/".$_;
		my ($status, $msg) = verifyEVSBinary($evs);
		return 0 if (!$status);
		if ($duplicate) {
			copy($evs, getServicePath());
			chmod($Configuration::filePermission, getServicePath()."/".$_);
			chmod($Configuration::filePermission, $evs);
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: hasStaticPerlSupport
# Objective				: Check if we support dashboard for this arc
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub hasStaticPerlSupport {
	loadMachineHardwareName();
	if (exists $Configuration::staticperlZipFiles{$machineHardwareName}) {
		return 1;
	}
	else {
		traceLog("No dashboard support for $machineHardwareName.");
		return 0;
	}
}

#*****************************************************************************************************
# Subroutine			: hasStaticPerlBinary
# Objective				: Execute static perl binary and check it's working or not
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub hasStaticPerlBinary {
	my $dir = shift;
	my $duplicate = 1;

	unless(defined($dir)) {
		$dir = getServicePath();
		$duplicate = 0;
	}
	my $sp = getCatfile($dir, $Configuration::staticPerlBinaryName);
	$sp=~ s/__KVER__/$Configuration::kver/g;
	my ($status, $msg) = verifyStaticPerlBinary($sp);
	return 0 unless ($status);
	if ($duplicate) {
		copy($sp, getServicePath());
		chmod(0555, getCatfile(getServicePath(), $Configuration::staticPerlBinaryName));
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: hasCRONFallBackAdded
# Objective				: This is to verify fall back is added in crontab or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub hasCRONFallBackAdded {
	my $fc 		= getFileContents('/etc/crontab');
	return 1 if (index($fc, $Configuration::cronLinkPath) != -1);
	return 0;
}

#------------------------------------------------- I -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: init
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub initiateMigrate{
	loadAppPath();
	if (loadServicePath()){
		my $userServiceLocationFile = "$appPath/$Configuration::serviceLocationFile";
		my $migrateLockFile = getMigrateLockFile();
		my $migrateSuccessFile = getMigrateCompletedFile();
		return if (-e $migrateSuccessFile);
		return if (-e getUserFile() and -s getUserFile());

		my $ServiceLocation = getServicePath();
		$ServiceLocation =~ s/$Configuration::servicePathName$/$Configuration::oldServicePathName/;
		return if (!-e $ServiceLocation);
		my $ServiceLocationOld = $ServiceLocation;

		if (!-f $migrateLockFile or !isFileLocked($migrateLockFile)){
			open(my $lockfh, ">>", $migrateLockFile);
			print $lockfh $Configuration::mcUser;
			flock($lockfh, LOCK_EX|LOCK_NB);
			chmod($Configuration::filePermission, $migrateLockFile);

			display(["\n", 'do_you_want_to_migrate_user_data']);
			$Configuration::displayHeader = 0;
			my $restartcron = getAndValidate(['enter_your_choice'], "YN_choice", 1);
			$Configuration::displayHeader = 1;
			if ($restartcron eq 'y')
			{
				my $sudoprompt = 'please_provide_' . (isUbuntu() || isGentoo()? 'sudoers' : 'root') . '_pwd_for_migrate_process';

				my $sudosucmd = getSudoSuCRONPerlCMD('migrateuserdata', $sudoprompt);
				if (system($sudosucmd) != 0){
					$Configuration::displayHeader = 0;
					retreat(['migrate_reject_try_again',"\n"]);
				}
				fileWrite($migrateSuccessFile, '');
				chmod($Configuration::filePermission, $migrateSuccessFile);
				loadServicePath();

				unless (hasStaticPerlBinary()) {
					loadMachineHardwareName();
					if (defined $machineHardwareName){
						display(['downloading_static_perl_binary', '... ']);
						downloadStaticPerlBinary() or retreat('unable_to_download_static_perl_binary');
						display('static_perl_binary_downloaded_sucessfully');
					}
				}
				checkAndStartDashboard();
				doSilentLogout();
			}else{
				display(['migrate_reject_try_again',"\n"]);
				close($lockfh);
				exit;
			}
			flock($lockfh, LOCK_UN);
			close($lockfh);
			unlink $migrateLockFile;
		}
		else{
			$Configuration::displayHeader = 0;
			retreat(['migrate_reject_try_again',"\n"]);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: isInternetAvailable
# Objective				: This is to verify the machine has internet avaialbility
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isInternetAvailable {
	my $pingRes = `ping -c2 8.8.8.8 1>/dev/null 2>/dev/null`;
	return 0 if ($pingRes =~ /connect\: Network is unreachable/);
	return 0 if ($pingRes !~ /0\% packet loss/);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: isFileLocked
# Objective				: Check if the file is locked or not
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub isFileLocked {
	my ($f, $block) = ($_[0], $_[1]);
	return 0 unless (-f $f);
	open(my $fh, ">>", $f) or return 1;

	my $locktype = (defined($block) && $block == 1)? LOCK_EX : LOCK_EX|LOCK_NB;
	unless (flock($fh, $locktype)) {
		close($fh);
		return 1;
	}
	close($fh);
	unlink($f);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isThisExcludedItemSet
# Objective				: Checks whether the item is excluded or not
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub isThisExcludedItemSet {
	# user configuratin has to be loaded & exlude paths should be loaded
	return 1 unless(defined($_[0]));

	return 1 if ((!$_[1] && $_[0] =~ /\/\./) ||
			($Configuration::parStr ne "" && $_[0] =~ m/$Configuration::parStr/) ||
			($Configuration::fullStr ne "" && $_[0] =~ m/$Configuration::fullStr/) ||
			($Configuration::regexStr ne "" && $_[0] =~ m/$Configuration::regexStr/));

	return 0;
}

#*****************************************************************************************************
# Subroutine			: isUpdateAvailable
# Objective				: Check if latest version is available on the server
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar, Sabin Cheruvattil
#****************************************************************************************************/
sub isUpdateAvailable {
	return 0 if ($0 =~ m/$Configuration::idriveScripts{'check_for_update'}/i);

	my $updateInfoFile = getUpdateVersionInfoFile();
	return 1 if (-f $updateInfoFile and !-z $updateInfoFile);
	
	my $check4updateScript = "$Configuration::perlBin '$appPath/check_for_update.pl' checkUpdate";
	my $updateAvailStats = `$check4updateScript 1>/dev/null 2>/dev/null &`;
	return 1 if (-f $updateInfoFile and !-z $updateInfoFile);
	
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isUbuntu
# Objective				: This is to verify the machine is ubuntu or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isUbuntu {
	return 1 if (-e '/proc/version' && `cat /proc/version` =~ /ubuntu/);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isGentoo
# Objective				: This is to verify the machine is Gentoo or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isGentoo {
	return 1 if (-e '/proc/version' && `cat /proc/version` =~ /gentoo/);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isRunningJob
# Objective				: This function will return 1 if pid.txt file exists, otherwise 0.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isRunningJob {
	my $jobRunningFile	= shift;
	return (-e $jobRunningFile)? 1 : 0;
}

#*****************************************************************************************************
# Subroutine			: isDashboardRunning
# Objective				: This function will return 1 if dashboard is running
# Added By				: Sabin Cheruvattil
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub isDashboardRunning {
	my $selfPIDFile = getCatfile(getServicePath(), $Configuration::userProfilePath, $Configuration::mcUser, $Configuration::dashboardpid);
	return isFileLocked($selfPIDFile);
}

#*****************************************************************************************************
# Subroutine			: isUserDashboardRunning
# Objective				: This function will return 1 if user's dashboard is running
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isUserDashboardRunning {
	my $selfPIDFile = getCatfile(getServicePath(), $Configuration::userProfilePath, $Configuration::mcUser, $Configuration::dashboardpid);
	# username of the user who is currently configuring the account is already set by setUsername
	return (isFileLocked($selfPIDFile) && $_[0] eq getUsername());
}

#*****************************************************************************************************
# Subroutine			: inAppPath
# Objective				: Find a file in source codes path
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub inAppPath {
	my ($file) = @_;
	if (-f getCatfile($appPath, $file)) {
		return 1;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: isLoggedin
# Objective				: Check if PWD file exists
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub isLoggedin {
	if(!defined($username) || $username eq '') {
		$username = '';
		return 0;
	}

	my @pf = ($Configuration::idpwdFile, $Configuration::idenpwdFile,
		$Configuration::idpwdschFile);

	if (getUserConfiguration('ENCRYPTIONTYPE') eq 'PRIVATE') {
		push @pf, ($Configuration::idpvtFile, $Configuration::idpvtschFile);
	}

	my $status = 0;
	for(@pf) {
		my $file = getCatfile($servicePath, $Configuration::userProfilePath, $Configuration::mcUser, $username, $_);
		if (!-f $file or -z $file) {
			$status = 0;
			last;
		}
		$status = 1;
	}

	my $uf = getUserFile();
	if (-f $uf and !-z $uf) {
		my $fc = getFileContents($uf);
		Chomp(\$fc);

		my %loginData = ();
		if ($fc ne '') {
			%loginData = ($fc =~ m/^\{/) ? %{JSON::from_json($fc)} : ();
		}

		unless ($status) {
			if (exists $loginData{$Configuration::mcUser}) {
				$loginData{$Configuration::mcUser}{'userid'} = $username;
				$loginData{$Configuration::mcUser}{"isLoggedin"} = 0;
				fileWrite($uf, JSON::to_json(\%loginData));
			}
			return 0;
		}
		elsif (exists $loginData{$Configuration::mcUser} and $loginData{$Configuration::mcUser}{'userid'}) {
			if ($loginData{$Configuration::mcUser}{'userid'} eq $username) {
				return $loginData{$Configuration::mcUser}{"isLoggedin"};
			}
		}
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: isValidUserName
# Objective				: This subroutine helps to validate username
# Added By				: Anil Kumar
#****************************************************************************************************/
sub isValidUserName {
	my $validUserPattern = 1;
	if (length($_[0]) < 4)
	{
		display(['username_must_contain_4_characters', '.',"\n"],1) ;
		$validUserPattern = 0;
	}
	return $validUserPattern;
}

#*****************************************************************************************************
# Subroutine			: isProxyEnabled
# Objective				: Helps to understand if proxy is enabled or not
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isProxyEnabled {
	return getUserConfiguration('PROXYIP')? 1 : 0;
}

#*****************************************************************************************************
# Subroutine			: isValidEmailAddress
# Objective				: This is to validate email address
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub isValidEmailAddress {
	return (length($_[0]) > 5 && length($_[0]) <= 64 && (lc($_[0]) =~ m/^[a-zA-Z0-9]+(\.?[\*\+\-\_\=\^\$\#\!\~\?a-zA-Z0-9])*\.?\@([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)(\.[a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)*\.(?:([a-zA-Z0-9]+)|([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+))$/));
}

#*******************************************************************************************************
# Subroutine Name         :	isEngineRunning
# Objective               :	Checking the given engine is running or not.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/
sub isEngineRunning {
	my ($enginePidPath) = @_;
	my $fh;
	if (!-e $enginePidPath){
		return 0;
	}

	open($fh, ">", $enginePidPath) or return 1;
	if (flock($fh, 2|4)){
		flock($fh, 8);
		close $fh;
		return 0;
	}

	close $fh;
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	isAnyEngineRunning
# Objective               :	Checking the any engine is running or not.
# Added By             	  : Vijay Vinoth
#********************************************************************************************************/

sub isAnyEngineRunning
{
	my ($engineLockFile) = @_;
	open(my $handle, ">>", $engineLockFile) or return 0;
	if (!flock($handle, 2|4)){
		close $handle;
		return 1;
	}
	flock($handle, 8);
	close $handle;
	return 0;
}

#*******************************************************************************************************
# Subroutine Name         :	isJobRunning
# Objective               :	Checking whether any ( scheduled / dashboard related) job is running in the provided jobtype
# Added By             	  : Anil Kumar
# Modified By             : Vijay Vinoth
#********************************************************************************************************/
sub isJobRunning
{
	my $jobType = $_[0];
	my $jobRunningDir = getUserProfilePath();
	if ($jobType eq "backup" or $jobType eq "default_backupset") {
		$jobRunningDir .= "/Backup/DefaultBackupSet";
	}
	elsif ($jobType eq "express_backup" or $jobType eq "local_backupset" or $jobType eq "localbackup") {
		$jobRunningDir .= "/Backup/LocalBackupSet";
	}
	elsif ($jobType eq "archive") {
		$jobRunningDir .= "/Archive/DefaultBackupSet";
	}elsif ($jobType eq "restore") {
		$jobRunningDir .= "/Restore/DefaultBackupSet";
	}

	my $pidPath = $jobRunningDir."/".$Configuration::pidFile;
	if (Helpers::isFileLocked($pidPath)) {
		return 1;
	}
	return 0;


	# my $logPidFilePath = $jobRunningDir."/".$Configuration::logPidFile;
	# #print "\n JOB RUNNING DIR:: $logPidFilePath \n";
	# my $logFile;
	# if (-e $logPidFilePath){
		# open FILE, "<", $logPidFilePath or (traceLog($Locale::strings{'failed_to_open_file'}.":$logPidFilePath. Reason:$!") and die);
		# chomp($logFile = <FILE>);
		# close FILE;
	# }

	# return 0 unless($logFile);

	# my @list = split ( /(_)/, $logFile );
	# my $jobTypeRunning =  $list[-1];
	# if ($jobTypeRunning eq "Scheduled") {
		# return 1;
	# }

	# return 1 if (defined($_[1]));

	# return 0;

}

#------------------------------------------------- J -------------------------------------------------#
#------------------------------------------------- K -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: killPIDs
# Objective				: Kill all process id's passed to it
# Added By				: Yogesh Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub killPIDs {
	my $res;
	my $terminate = 1;
	$terminate    = $_[1] if (defined($_[1]));

	foreach my $index (0 .. (@{$_[0]}-1)) {
		if ($_[0]->[$index]) {
			$res = waitpid($_[0]->[$index], WNOHANG);
			if ($res == -1 || $res > 0) {
				splice(@{$_[0]}, $index, 1);
			}
			elsif ($terminate) {
				system("kill $_[0]->[$index] 1>/dev/null 2>/dev/null");
				if ($@) {
					traceLog("unable to kill pid $_[0]->[$index]");
					traceLog("Error: $@");
				}
			}
		}
	}
}

#------------------------------------------------- L -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: launchIDriveCRON
# Objective				: This is to launch IDrive CRON service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub launchIDriveCRON {
	my $opconf	= getCRONSetupTemplate();

	# Each time account settings runs, this will re-configure the cron
	if (%{$opconf}) {
		# prepare & copy the scripts replaced with the PATH
		processShellCopy($opconf);

		# shell linking
		processCRONShellLinks($opconf);

		# shell append
		processCRONConfAppends($opconf);

		# execute setup commands
		processCRONSetupCommands($opconf);

		return CRON_STARTED if (checkCRONServiceStatus($opconf->{'pidpath'}) == CRON_RUNNING);
	}

	traceLog('unable_to_install_idrive_cron');

	# fallback logic | if cron is not started we are asking user to restart it
	addCRONFallBack() unless(hasCRONFallBackAdded());

	# run cron manually in root mode
	my $croncmd = qq($Configuration::perlBin '$Configuration::cronLinkPath' 1>/dev/null 2>/dev/null &);
	system($croncmd);
	sleep(3);

	return CRON_STARTED if (checkCRONServiceStatus() == CRON_RUNNING);
	traceLog('unable_to_install_idrive_fallback_cron');
}

#*****************************************************************************************************
# Subroutine			: ltrim
# Objective				: This function will remove white spaces from the left side of a string.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub ltrim {
	my $s = shift;
	$s =~ s/^\s+//;
	return $s;
}

#*****************************************************************************************************
# Subroutine			: linkBucket
# Objective				: Choose a bucket from the list to backup/restore files
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub linkBucket {
	my @columnNames = (['S.No.', 'Device Name', 'Device ID', 'OS', 'Date & Time', 'IP Address'], [8, 24, 24, 15, 22, 16]);
	my $tableHeader = getTableHeader(@columnNames);
	display($tableHeader,0);
	my $tableData = "";
	my $devices = $_[1];
	my $columnIndex = 1;
	my $screenCols = (split(' ', $Configuration::screenSize))[-1];

	my @columnHeaderInfo = ('s_no', 'nick_name', 'device_id','os', 'bucket_ctime', 'ip');

	my $serialNumber = 1;
	for my $device (@{$devices}) {
		for (my $i=0; $i < scalar(@columnHeaderInfo); $i++) {
			if ($columnHeaderInfo[$i] eq 's_no') {
				$tableData .= $serialNumber;
				$tableData .= (' ') x ($columnNames[1]->[$i] - length($serialNumber));
			}
			else {
				my $displayData = $device->{$columnHeaderInfo[$i]};

				if (($columnNames[1]->[$i] - length($displayData)) > 0){
					$tableData .= $displayData;
					$tableData .= (' ') x ($columnNames[1]->[$i] - length($displayData)) if ($columnHeaderInfo[$i] eq 'nick_name'||'os');
				}
				else {
					$tableData .= trimDeviceInfo($displayData,$columnNames[1]->[$i]) if ($columnHeaderInfo[$i] eq 'nick_name'||'os');
					$tableData .= (' ') x 3;
				}
				$tableData .= (' ') x ($columnNames[1]->[$i] - length($displayData)) if ($columnHeaderInfo[$i] eq 's_no');
			}
		}
		$serialNumber = $serialNumber + 1;
		$tableData .= "\n";
	}

	display($tableData,1);
	my $slno;
	if ($_[0] eq "backup") {
		display(['enter_the_serial_no_to_select_your' , ucfirst($_[0]), 'location_press_enter_to_go_back_to_main_menu'], 0);
		$slno = getUserMenuChoiceBuckSel(scalar(@{$devices}));
	}
	else {
		display(['enter_the_serial_no_to_select_your' ,"Restore from location."], 0);
		$slno = getUserMenuChoice(scalar(@{$devices}));
	}

	if ($slno eq '') {
		unless (defined($_[2])) {
			return 0;
		}
		else {
			display('');
			return $_[2]->($devices);
		}

	}

	if ($_[0] eq 'backup') {
		createUTF8File('LINKBUCKET',
			$devices->[$slno -1]{'nick_name'},
			$devices->[$slno -1]{'device_id'},
			getMachineUID()) or retreat('failed_to_create_utf8_file');
		my @result = runEVS('item');

		if ($result[0]->{'STATUS'} eq Configuration::FAILURE) {
			print "$result[0]->{'MSG'}\n";
			return 0;
		}
		elsif ($result[0]->{'STATUS'} eq Configuration::SUCCESS) {

		$devices->[$slno -1]{'server_root'} = $result[0]->{'server_root'};
		$devices->[$slno -1]{'device_id'}   = $result[0]->{'device_id'};
		$devices->[$slno -1]{'nick_name'}   = $result[0]->{'nick_name'};

		#server root added by anil
			setUserConfiguration('SERVERROOT', $devices->[$slno -1]{'server_root'});
			setUserConfiguration('BACKUPLOCATION',
								($Configuration::deviceIDPrefix . $devices->[$slno -1]{'device_id'} . $Configuration::deviceIDSuffix .
									"#" . $devices->[$slno -1]{'nick_name'}));
			display([ "\n", 'your_backup_to_device_name_is', (" \"" . $devices->[$slno -1]{'nick_name'} . "\"")]);
			loadNotifications() and setNotification('register_dashboard') and saveNotifications();
			return 1;
		}
	}
	elsif ($_[0] eq 'restore') {
		setUserConfiguration('RESTOREFROM',
			($Configuration::deviceIDPrefix . $devices->[$slno -1]{'device_id'} . $Configuration::deviceIDSuffix .
			"#" . $devices->[$slno -1]{'nick_name'}));
		display([ "\n",'your_restore_from_device_is_set_to', (" \"" . $devices->[$slno -1]{'nick_name'} . "\".")]);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadEVSBinary
# Objective				: Assign evs binary filename to %evsBinary
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub loadEVSBinary {
	my $evs = getEVSBinaryFile();
	my ($status, $msg) = verifyEVSBinary($evs);
	return $status;
}

#*****************************************************************************************************
# Subroutine			: loadMachineHardwareName
# Objective				: Save machine hardware name to $machineHardwareName . This is used to download arch depedent binaries
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadMachineHardwareName {
	my $mhn = `uname -m`;
	if ($? > 0) {
		traceLog("Error in getting the machine name: ".$?);
		return 0;
	}
	chomp($mhn);

	if ($mhn =~ /i386|i686/) {
		$machineHardwareName = '32';
	}
	elsif ($mhn =~ /x86_64|ia64|amd|amd64/) {
		$machineHardwareName = '64';
	}
	elsif ($mhn =~ /arm/) {
		$machineHardwareName = 'arm';
	}
	else {
		$machineHardwareName = undef;
		traceLog("Error in getting the machine name: ".$mhn);
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: loadMachineHardwareName
# Objective				: Save Server address of the current logged in user to $serverAddress
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadServerAddress {
	my $gsa = getServerAddressFile();
	if (-f $gsa and !-z $gsa) {
		if (open(my $fileHandle, '<', $gsa)) {
			my $sa = <$fileHandle>;
			close($fileHandle);
			chomp($sa);
			if ($sa ne '') {
				$serverAddress = $sa;
				return 1;
			}
		}
	}
	$serverAddress = undef;
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadStorageSize
# Objective				: Save logged in user's available and used space
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadStorageSize {
	my $csf = getCachedStorageFile();
	my @accountStorageDetails;
	my $status = 0;
	if (-f $csf and !-z $csf) {
		if (open(my $s, '<', $csf)) {
			@accountStorageDetails = <$s>;
			for my $keyvaluepair (@accountStorageDetails) {
				my @kvp = split(/=/, $keyvaluepair);
				if (exists $Configuration::accountStorageSchema{$kvp[0]}) {
					my $func = \&{$Configuration::accountStorageSchema{$kvp[0]}{'func'}};
					chomp($kvp[1]);
					&$func($kvp[1]);
					$status = 1;
				}
				else {
					#In case if the key value changes then we have to remove the file and retreat.
					$status = 0;
					last;
				}
			}
			close($s);
		}
	}
	return $status;
}

#*****************************************************************************************************
# Subroutine			: loadAppPath
# Objective				: Assign perl scripts path to $appPath
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadAppPath {
	my $absFile = getAbsPath(__FILE__);
	my $replaceStr = getCatfile($Configuration::idriveLibPath, 'Helpers.pm');
	my @af = split(/$replaceStr$/, $absFile);
	$appPath = $af[0];
	return 1;
}

#*****************************************************************************************************
# Subroutine			: loadServicePath
# Objective				: Assign saved path of user data to $servicePath
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadServicePath {
	if (inAppPath($Configuration::serviceLocationFile)) {
		if (open(my $sp, '<',
				("$appPath/" . $Configuration::serviceLocationFile))) {
			my $s = <$sp> || '';
			close($sp);
			chomp($s);
			if (-d $s) {
				$servicePath = $s;
				return 1;
			}
		}
	}
	$servicePath = '';
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadUsername
# Objective				: Assign logged in user name to $username
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub loadUsername {
	my $cf = getUserFile();
	if (-f $cf and !-z $cf) {
		if (open(my $u, '<', $cf)) {
			my $userdata = <$u>;
			close($u);
			Chomp(\$userdata);
			my %datahash = ($userdata =~ m/^\{/)? %{JSON::from_json($userdata)} : {$Configuration::mcUser => $userdata};
			$username = (($datahash{$Configuration::mcUser}{'userid'})? $datahash{$Configuration::mcUser}{'userid'} : '');
			return 0 if ($username eq '');
			return 1;
		}
	}
	$username = '';
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadUserConfiguration
# Objective				: Assign user configurations to %userConfiguration
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub loadUserConfiguration {
	my $ucf = getUserConfigurationFile();
	my $errCode = 1;
	if (-f $ucf and !-z $ucf) {
		my $ucj = JSON::from_json(decryptString(getFileContents($ucf)));
		foreach my $key(keys %{$ucj}) {
			$userConfiguration{$key} = $ucj->{$key};
		}
		checkAndUpdateServerRoot(); # Added to check and update server root if it is empty
		proxyBackwardCompatability();
		if (defined($_[0])){
			$errCode = validateUserConfigurations($_[0]);
		} else {
			$errCode = validateUserConfigurations();
		}
	} else {
		$errCode = 101;
	}

	foreach my $confkey (keys %Configuration::userConfigurationSchema) {
		unless($userConfiguration{$confkey}) {
			$userConfiguration{$confkey} = {'VALUE' => $Configuration::userConfigurationSchema{$confkey}{'default'}};
			#$modifiedUserConfig{$confkey} = {'VALUE' => $Configuration::userConfigurationSchema{$confkey}{'default'}};
			$Configuration::isUserConfigModified = 1;
			if (-f $ucf and !-z $ucf) {
				$errCode =1 ;
				#traceLog("Added missed key:".$confkey);
			}
		}
	}

	return $errCode;
}

#*****************************************************************************************************
# Subroutine			: loadNotifications
# Objective				: load user activities on certain modules like start/stop backup/restore, etc...
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadNotifications {
	my $nf = getNotificationFile();
	createNotification() unless (-e $nf and !-z $nf);

	if (-e $nf) {
		if (open(my $n, '<', $nf)) {
			my $nc = <$n>;
			close($n);
			if ($nc ne '') {
				%notifications = %{JSON::from_json($nc)};
			}
			return 1;
		}
	}
	%notifications = ();
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadCrontab
# Objective				: Load crontab data
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadCrontab {
	my $ctf = getCrontabFile();
	my $loggedInUsersCrontab = 0;
	$loggedInUsersCrontab = $_[0] if (defined $_[0]);
	if (-e $ctf and !-z $ctf) {
		my $ctc = getFileContents($ctf);
		if ($ctc ne '') {
			%crontab = %{JSON::from_json(decryptString($ctc))};
			if ($loggedInUsersCrontab) {
				unless (exists $crontab{$Configuration::mcUser} && exists $crontab{$Configuration::mcUser}{$username}) {
					return 0;
				}
			}
			return 1;
		}
	}
	%crontab = ();
	return 0;
}

#****************************************************************************************************
# Subroutine Name : loadFullExclude.
# Objective       : This function will load FullExcludePaths to FullExcludeHash.
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar
#*****************************************************************************************************/
sub loadFullExclude {
	my @excludeArray;
	my $excludeFullPath = getUserFilePath($Configuration::excludeFilesSchema{'full_exclude'}{'file'});
	$excludeFullPath   .= '.info';

	#read full path exclude file and prepare a hash for it
	if (-f $excludeFullPath and !-z $excludeFullPath) {
		if (!open(EXFH, $excludeFullPath)) {
			$Configuration::errStr = $Locale::strings{'failed_to_open_file'}." : $excludeFullPath. Reason:$!\n";
			print $Configuration::errStr;
			traceLog($Configuration::errStr, __FILE__, __LINE__);
			return;
		}

		@excludeArray = grep { !/^\s*$/ } <EXFH>;
		close EXFH;
	}
	my $currentDir        = getAppPath();
	my $idriveServicePath = getServicePath();

	push @excludeArray, ($currentDir, 'enabled');
	push @excludeArray, ($idriveServicePath, 'enabled');
	push @excludeArray, ($Configuration::expressLocalDir, 'enabled');
	my @qFullExArr; # What is the use of this variable.
	chomp @excludeArray;

	for (my $i=0; $i<=$#excludeArray; $i++) {
		if ($excludeArray[$i+1] eq 'enabled') {
			if (substr($excludeArray[$i], -1, 1) eq "/") {
				chop($excludeArray[$i]);
			}
			$backupExcludeHash{$excludeArray[$i]} = 1;
			push(@qFullExArr, "^".quotemeta($excludeArray[$i]).'\/') if ($excludeArray[$i] ne '');
		}
		$i++;
	}

	$Configuration::fullStr = join("\n", @qFullExArr);
	chomp($Configuration::fullStr);
	$Configuration::fullStr =~ s/\n/|/g;#First we join with '\n' and then replacing with '|'?
}

#****************************************************************************************************
# Subroutine Name : loadPartialExclude.
# Objective       : This function will load Partial Exclude string from PartialExclude File.
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar, Senthil Pandian
#*****************************************************************************************************/
sub loadPartialExclude {
	my (@excludeParArray, @qParExArr);
	my $excludePartialPath = getUserFilePath($Configuration::excludeFilesSchema{'partial_exclude'}{'file'});
	$excludePartialPath   .= '.info';

	#read partial path exclude file and prepare a partial match pattern
	if (-f $excludePartialPath and !-z $excludePartialPath) {
		if (!open(EPF, $excludePartialPath)) {
			$Configuration::errStr = $Locale::strings{'failed_to_open_file'}." : $excludePartialPath. Reason:$!\n";
			print $Configuration::errStr;
			traceLog($Configuration::errStr, __FILE__, __LINE__);
			return;
		}

		@excludeParArray = grep { !/^\s*$/ } <EPF>;
		close EPF;

		chomp(@excludeParArray);
		for(my $i = 0; $i <= $#excludeParArray; $i++) {
			if ($excludeParArray[$i+1] eq 'enabled') {
				$excludeParArray[$i] =~ s/[\s\t]+$//;
				#push(@qParExArr, "^".quotemeta($excludeParArray[$i]).'\/');
				push(@qParExArr, quotemeta($excludeParArray[$i]));
			}
			$i++;
		}
		# $Configuration::parStr = join("\n", @qParExArr);
		# chomp($Configuration::parStr);
		# $Configuration::parStr =~ s/\n/|/g;
	}
	push(@qParExArr, quotemeta("/.")) unless(getUserConfiguration('SHOWHIDDEN'));
	if (scalar(@qParExArr)>0){
		$Configuration::parStr = join("|", @qParExArr);
		chomp($Configuration::parStr);
	}
}

#****************************************************************************************************
# Subroutine Name : loadRegexExclude.
# Objective       : This function will load Regular Expression Exclude string from RegexExlude File.
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar
#*****************************************************************************************************/
sub loadRegexExclude {
	my $regexExcludePath = getUserFilePath($Configuration::excludeFilesSchema{'regex_exclude'}{'file'});
	$regexExcludePath   .= '.info';

	#read regex path exclude file and find a regex match pattern
	if (-e $regexExcludePath and -s $regexExcludePath > 0) {
		if (!open(RPF, $regexExcludePath)) {
			$Configuration::errStr = $Locale::strings{'failed_to_open_file'}." : $regexExcludePath. Reason:$!\n";
			print $Configuration::errStr;
			traceLog($Configuration::errStr, __FILE__, __LINE__);
			return;
		}

		my @tmp;
		my @excludeRegexArray = grep { !/^\s*$/ } <RPF>;
		close RPF;

		if (!scalar(@excludeRegexArray)) {
			$Configuration::regexStr = undef;
		}
		else {
			for(my $i = 0; $i <= $#excludeRegexArray; $i++) {
				chomp($excludeRegexArray[$i+1]);
				if ($excludeRegexArray[$i+1] eq 'enabled') {
					my $a = $excludeRegexArray[$i];
					chomp($a);
					$b = eval { qr/$a/ };
					if ($@) {
						print OUTFILE " Invalid regex: $a";
						traceLog("Invalid regex: $a\n", __FILE__, __LINE__);
					}
					elsif ($a) {
						push @tmp, $a;
					}
				}
				$i++;
			}
			$Configuration::regexStr = join("\n", @tmp);
			chomp($Configuration::regexStr);
			$Configuration::regexStr =~ s/\n/|/g;
		}
	}
}

#------------------------------------------------- M -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: migrateUserFile
# Objective				:
# Added By				: Vijay Vinoth, Yogesh Kumar
#****************************************************************************************************/
sub migrateUserFile
{
	my $filename = getOldUserFile();
	my $idriveFilename = getUserFile();
	my $userServiceLocationFile = "$appPath/$Configuration::serviceLocationFile";
	my $ServiceLocation = getServicePath();
	my $fc = '';

	if (-e $filename){
		$fc = getFileContents($filename);
		Chomp(\$fc);
	}

	my $migrateLockFile = getMigrateLockFile();
	open MIGRATEMCDATA, "<$migrateLockFile";
	my $migrateMcUser = <MIGRATEMCDATA>;
	close MIGRATEMCDATA;
	Chomp(\$migrateMcUser);

	my %loginData	= ();
	if ($fc ne ''){
		$loginData{$migrateMcUser}{'userid'} = $fc;
		$loginData{$migrateMcUser}{'isLoggedin'} = 1;
	}
	migrateUserDirectories($migrateMcUser,$fc);

	my $ServiceLocationOld = $ServiceLocation;
	$ServiceLocation =~ s/$Configuration::oldServicePathName$/$Configuration::servicePathName/;

	rmtree($ServiceLocationOld."/".$Configuration::userProfilePath);
	unlink $filename;

	fileWrite($idriveFilename, JSON::to_json(\%loginData));
	chmod $Configuration::filePermission, $idriveFilename;

	system("cp -rpf \'$ServiceLocationOld/\'* \'$ServiceLocation\'");

	removeItems($ServiceLocationOld) if ($? == 0);
	fileWrite($userServiceLocationFile,$ServiceLocation);

	loadUsername();
	$Configuration::mcUser = `whoami`;
	chomp($Configuration::mcUser);
	setServicePath($ServiceLocation);
}

#*****************************************************************************************************
# Subroutine			: migrateUserDirectories
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserDirectories
{
    opendir(DIR, "$servicePath/$Configuration::userProfilePath") or die $!;
	my $mcUser = "";
	my $fileName = "";
	my $fileStat = "";

	my $migrateLockFile = getMigrateLockFile();
    while (my $userDir = readdir(DIR)) {
        # Use a regular expression to ignore files beginning with a period
        next if ($userDir =~ m/^\./);
		$fileName = "$servicePath/$Configuration::userProfilePath/$userDir";

		next if (!-e $fileName."/Backup");

		$fileStat = stat($fileName);
		$mcUser = getpwuid($fileStat->uid);
		if ($userDir eq $_[1]){
			$mcUser = $_[0];
			$fileStat = stat($migrateLockFile);
		}
		migrateUserPath($mcUser,$userDir,$fileStat);

    }

    closedir(DIR);
}

#*****************************************************************************************************
# Subroutine			: migrateUserPath
# Objective				: This will update older service path structue to latest one.
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserPath{
	my $mcUser = $_[0];
	my $idriveUser = $_[1];
	my $fileStat = $_[2];
	my $groupUser = getpwuid($fileStat->gid);
	my $linuxUserDir = "$servicePath/$Configuration::userProfilePath/$mcUser";
	my $idriveUserOldDir = "$servicePath/$Configuration::userProfilePath/$idriveUser";
	my $idriveUserDir = "$linuxUserDir/$idriveUser";

	$linuxUserDir = $linuxUserDir."_tmp"	if ($linuxUserDir eq $idriveUserOldDir);

	createDir($linuxUserDir) if (!-e $linuxUserDir);

	system('cp -rpf '.getECatfile($servicePath, $Configuration::userProfilePath, $idriveUser).' '. getECatfile($linuxUserDir, '/'));
	removeItems("$servicePath/$Configuration::userProfilePath/$idriveUser") if ($? == 0);

	if ($idriveUserOldDir."_tmp" eq $linuxUserDir){
		system('mv '.getECatfile($linuxUserDir).' '.getECatfile($idriveUserOldDir));
	}

	setUsername($idriveUser);
	$Configuration::mcUser = $mcUser;
	loadCrontab(1);

	my @jobTypes = ("backup", "archive");
	for my $i (0 .. $#jobTypes) {
		createCrontab($jobTypes[$i], "default_backupset") or retreat('failed_to_load_crontab');
	}

	createCrontab("cancel", "default_backupset") or retreat('failed_to_load_crontab');

	migrateUserLogs($idriveUserDir);
	migrateUserJobDirectories($idriveUserDir);
	migrateExcludeFileset($idriveUserDir);
	migrateCronEntry($idriveUserOldDir);

	my $updatedServiceLocation = $servicePath;
	$updatedServiceLocation =~ s/$Configuration::oldServicePathName$/$Configuration::servicePathName/;
	migrateConfigData($idriveUserOldDir, "$updatedServiceLocation/$Configuration::userProfilePath/$mcUser/$idriveUser");

    createLogJsonForOldUser();
	migrateUserNewServiceLocation("$updatedServiceLocation/$Configuration::userProfilePath/$mcUser",$idriveUserDir);
	system("chown -R  $mcUser:$groupUser ".getECatfile($updatedServiceLocation,$Configuration::userProfilePath,$mcUser,$idriveUser)." 2>/dev/null");
	system("chmod -R 0755 ".getECatfile($updatedServiceLocation,$Configuration::userProfilePath,$mcUser,$idriveUser,'/')." 2>/dev/null");
}

#*****************************************************************************************************
# Subroutine			: migrateUserLogs
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserLogs
{
	my $idriveUserDir = $_[0];
	#rename log files for local backup
	customReName("$idriveUserDir/LocalBackup/Manual/$Configuration::logDir/",'$',"_Manual");

	#rename log files for manual backup
	customReName("$idriveUserDir/Backup/Manual/$Configuration::logDir/",'$',"_Manual");

	#rename log files for schedule backup
	customReName("$idriveUserDir/Backup/Scheduled/$Configuration::logDir/",'$',"_Scheduled");

	#rename log files for schedule restore
	customReName("$idriveUserDir/Restore/Scheduled/$Configuration::logDir/",'$',"_Scheduled");

	#rename log files for manual restore
	customReName("$idriveUserDir/Restore/Manual/$Configuration::logDir/",'$',"_Manual");

	#rename log files for schedule Archive
	customReName("$idriveUserDir/Archive/Scheduled/$Configuration::logDir/",'$',"_Scheduled");

	#rename log files for manual Archive
	customReName("$idriveUserDir/Archive/Manual/$Configuration::logDir/",'$',"_Manual");
}

#*****************************************************************************************************
# Subroutine			: migrateUserJobDirectories
# Objective				:
# Added By				: Vijay Vinoth
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserJobDirectories
{
	my $idriveUserDir = $_[0];
	my $errorFile = "\'$idriveUserDir/$Configuration::traceLogFile\'";
	my $errorSkip = " 1>>$errorFile 2>>$errorFile";
	my $backupSetPath = $idriveUserDir."/".$Configuration::userProfilePaths{'backup'}."/".$Configuration::backupsetFile;
	my $localBackupSetPath = $idriveUserDir."/".$Configuration::userProfilePaths{'localbackup'}."/".$Configuration::backupsetFile;

	#move local backup job to new location
	createDir("$idriveUserDir/$Configuration::userProfilePaths{'localbackup'}")	if (!-e "$idriveUserDir/$Configuration::userProfilePaths{'localbackup'}");

	if (-e "$idriveUserDir/LocalBackup/Manual/"){
		system('cp -rpf '. getECatfile($idriveUserDir, 'LocalBackup', 'Manual', '/') . '* ' . getECatfile($idriveUserDir, $Configuration::userProfilePaths{'localbackup'}) . " $errorSkip");
		removeItems("$idriveUserDir/LocalBackup/Manual/") if ($? == 0);
	}

	if (-e $localBackupSetPath and !-z $localBackupSetPath) {
		updateJobsFileset($localBackupSetPath,'localbackup');
	}

	removeItems("$idriveUserDir/LocalBackup/") if ($? == 0);

	#move scheulde backup job to new location
	system('mv '.getECatfile($idriveUserDir,'Backup','Scheduled','/').' '. getECatfile($idriveUserDir,$Configuration::userProfilePaths{'backup'})." $errorSkip");

	if (-e $backupSetPath and !-z $backupSetPath) {
		updateJobsFileset($backupSetPath,'backup');
	}

	#move manual backup logs to new location
	createDir($idriveUserDir."/".$Configuration::userProfilePaths{'backup'})	if (!-e $idriveUserDir."/".$Configuration::userProfilePaths{'backup'});

	createDir($idriveUserDir."/".$Configuration::userProfilePaths{'backup'}."/LOGS")	if (!-e $idriveUserDir."/".$Configuration::userProfilePaths{'backup'}."/LOGS");

	if (-e $idriveUserDir."/".$Configuration::userProfilePaths{'backup'}."/LOGS"){
		system('cp -rpf '.getECatfile($idriveUserDir,'Backup','Manual','LOGS','/').'* '.getECatfile($idriveUserDir,$Configuration::userProfilePaths{'backup'},'LOGS','/')." $errorSkip");
	}
	removeItems("$idriveUserDir/Backup/Manual/");

	#move scheulde restore job to new location
	if (-e "$idriveUserDir/Restore/Scheduled/"){
		system('mv '.getECatfile($idriveUserDir,'Restore','Scheduled','/').' '.getECatfile($idriveUserDir,$Configuration::userProfilePaths{'restore'})." $errorSkip");
	}

	#move manual restore logs to new location
	createDir($idriveUserDir."/".$Configuration::userProfilePaths{'restore'})	if (!-e $idriveUserDir."/".$Configuration::userProfilePaths{'restore'});

	createDir($idriveUserDir."/".$Configuration::userProfilePaths{'restore'}."/LOGS")	if (!-e $idriveUserDir."/".$Configuration::userProfilePaths{'restore'}."/LOGS");

	if (-e $idriveUserDir."/".$Configuration::userProfilePaths{'restore'}."/LOGS"){
		system('cp -rpf '.getECatfile($idriveUserDir,'Restore','Manual','LOGS','/').'* '.getECatfile($idriveUserDir,$Configuration::userProfilePaths{'restore'},'LOGS','/')." $errorSkip");
	}

	removeItems("$idriveUserDir/Restore/Manual/");

	#move scheulde Archive job to new location
	if (-e "$idriveUserDir/Archive/Scheduled/"){
		system('mv '.getECatfile($idriveUserDir,'Archive','Scheduled','/').' '.getECatfile($idriveUserDir,$Configuration::userProfilePaths{'archive'})." $errorSkip");
	}

	#move manual Archive logs to new location
	createDir($idriveUserDir."/".$Configuration::userProfilePaths{'archive'})	if (!-e $idriveUserDir."/".$Configuration::userProfilePaths{'archive'});

	createDir($idriveUserDir."/".$Configuration::userProfilePaths{'archive'}."/LOGS")	if (!-e $idriveUserDir."/".$Configuration::userProfilePaths{'archive'}."/LOGS");

	if (-e "$idriveUserDir/Archive/Manual/LOGS/"){
		system('cp -rpf '.getECatfile($idriveUserDir,'Archive','Manual','LOGS','/').'* '.getECatfile($idriveUserDir,$Configuration::userProfilePaths{'archive'},'LOGS','/')." $errorSkip");
	}

	chmod $Configuration::filePermission, "$idriveUserDir/$Configuration::traceLogFile" if (-e "$idriveUserDir/$Configuration::traceLogFile");
	removeItems("$idriveUserDir/Archive/Manual/");
}

#*****************************************************************************************************
# Subroutine			: migrateExcludeFileset
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateExcludeFileset{
	my $idriveUserDir = $_[0];
	my $fullExcludeListPath = $idriveUserDir."/".$Configuration::fullExcludeListFile;
	my $partialExcludeListPath = $idriveUserDir."/".$Configuration::partialExcludeListFile;
	my $regexExcludeListPath = $idriveUserDir."/".$Configuration::regexExcludeListFile;

	if (-e $fullExcludeListPath and !-z $fullExcludeListPath) {
		updateExcludeFileset($fullExcludeListPath);
	}
	if (-e $partialExcludeListPath and !-z $partialExcludeListPath) {
		updateExcludeFileset($partialExcludeListPath);
	}
	if (-e $regexExcludeListPath and !-z $regexExcludeListPath) {
		updateExcludeFileset($regexExcludeListPath);
	}

}
#*****************************************************************************************************
# Subroutine			: migrateCronEntry
# Objective				:
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub migrateCronEntry{
	my $fc 			= getFileContents('/etc/crontab');
	my @fields = split /\n/, $fc;
	my $i=0;
	my @timeDetail = ();
	my $jobName = '';
	my $jobType = '';
	my $idriveUserOldDir = $_[0];
	while ($i<=$#fields) {
		@timeDetail = ();
		my $emailNotify = '';
		if (index($fields[$i], $idriveUserOldDir) != -1) {
			my @timeDetail = split / /, $fields[$i];
			if ((index($fields[$i], 'Restore_Script.pl') != -1) or (index($fields[$i], '/Restore/Scheduled') != -1)){
				$i++;
				next;
			}
			if (index($fields[$i], 'Backup_Script.pl') != -1){
				$emailNotify = "$servicePath/$Configuration::userProfilePath/$Configuration::mcUser/$username/$Configuration::userProfilePaths{'backup'}/BackupmailNotify.txt";
				$jobType = 'backup';
				$jobName = 'default_backupset';
			}
			elsif (index($fields[$i], 'archive_cleanup.pl') != -1){
				my $perlPath = `which perl`;
				chomp($perlPath);
				if ($perlPath eq ''){
					$perlPath = '/usr/local/bin/perl';
				}
				my @cmdDetails = split /$perlPath/, $fields[$i];
				my $customCmd = $cmdDetails[1];
				my @params = split(' ', $customCmd);
				my $paramSize = @params;
				$params[$paramSize-1] =~ s/\'//g;
				$params[$paramSize-2] =~ s/\'//g;
				my $tmpData = $params[$paramSize-2];
				$params[$paramSize-3] =~ s/\'//g;
				$params[$paramSize-2] = $params[$paramSize-3];
				$params[$paramSize-3] = $tmpData;
				$customCmd = join( " ", @params );

				$jobType = 'archive';
				$jobName = 'default_backupset';
				setCrontab($jobType, $jobName, {'cmd' => $customCmd});
			}
			elsif (index($fields[$i], 'job_termination.pl') != -1){
				$jobType = 'cancel';
				$jobName = 'default_backupset';
			}

			Chomp(\$timeDetail[0]);
			Chomp(\$timeDetail[1]);
			Chomp(\$timeDetail[4]);
			my $dow = lc $timeDetail[4];

			setCrontab($jobType, $jobName, {'settings' => {'status' => 'enabled'}});
			if($timeDetail[1] eq "*"){
				setCrontab($jobType, $jobName, 'h', '*');
			} else {
				setCrontab($jobType, $jobName, 'h', sprintf("%02d", $timeDetail[1]));
			}

			if($timeDetail[0] eq "*"){
				setCrontab($jobType, $jobName, 'm', '*');
			} else {
				setCrontab($jobType, $jobName, 'm', sprintf("%02d", $timeDetail[0]));
			}

			if ($timeDetail[4] eq "*"){
				setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'daily'}});
			} else {
				setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'weekly'}});
				setCrontab($jobType, $jobName, {'dow' => $dow});
			}

			if ($emailNotify ne ''){
				if (!-e $emailNotify ){
					setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
				}else{
					if (open NOTIFYFILE, "<", $emailNotify) {
						my @notifyData = <NOTIFYFILE>;
						chomp(@notifyData);
						my $notifyFlag = lc $notifyData[0];
						my $notifyEmailIds = $notifyData[1];
						close(NOTIFYFILE);
						if ($notifyFlag eq "enabled"){
							setCrontab($jobType, $jobName, {'settings' => {'emails' => {'ids' => $notifyEmailIds}}});
						}
						setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => $Configuration::notifOptions{'notify_always'}}}});
					}else{
						setCrontab($jobType, $jobName, {'settings' => {'emails' => {'status' => 'disabled'}}});
					}

					unlink($emailNotify) if (-f $emailNotify);
				}
			}

			setCronCMD($jobType, $jobName) unless ($jobType eq 'archive');
		}
		$i++;
	}
	createCrontab($Configuration::dashbtask, $Configuration::dashbtask);
	setCronCMD($Configuration::dashbtask, $Configuration::dashbtask);
	saveCrontab();
}
#*****************************************************************************************************
# Subroutine			: migrateConfigData
# Objective				: Migrate configuration data
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateConfigData {
	my $idriveUserOldPath = $_[0];
	my $idriveUserNewPath = $_[1];
	my $userConf = getUserConfigurationFile();
	my $userConfTmp = getUserConfigurationFile()."_tmp";

	return if (!-e $userConf);

	# Open file to read
	open(DATA1, "<$userConf");

	# Open new file to write
	open(DATA2, ">$userConfTmp");

	# Copy data from one file to another.
	while(<DATA1>) {
		$_ =~ s/$idriveUserOldPath/$idriveUserNewPath/ig;
		print DATA2 $_;
	}
	close( DATA1 );
	close( DATA2 );

	unlink $userConf if (-e $userConfTmp and -s $userConfTmp > 0);

	loadUserConfiguration();

	if (-f $userConfTmp and !-z $userConfTmp) {
		tie(my %newuserconfs, 'Tie::IxHash');
		map{$newuserconfs{$_} = ''} keys %Configuration::userConfigurationSchema;
		if (open(my $uc, '<', $userConfTmp)) {
			my @u = <$uc>;
			close($uc);
			map{my @x = split(/ = /, $_); chomp($x[1]); $x[1] =~ s/^\s+|\s+$//g; $newuserconfs{$x[0]} = $x[1];} @u;

			setUserConfiguration(\%newuserconfs);
			for my $key (keys %Configuration::userConfigurationSchema) {
				if (($Configuration::userConfigurationSchema{$key}{'default'} ne '') and
					(getUserConfiguration($key) eq '')) {
					setUserConfiguration($key, $Configuration::userConfigurationSchema{$key}{'default'});
				}
			}
			saveUserConfiguration(undef,1);
			chmod $Configuration::filePermission, $userConf;
			unlink $userConfTmp;
		}
	}
}

#*****************************************************************************************************
# Subroutine			: migrateUserNewServiceLocation
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub migrateUserNewServiceLocation{
	my $newServiceLocation = $_[0];
	my $idriveUserDir = $_[1];
	my $errorFile = "\'$newServiceLocation/$Configuration::traceLogFile\'";
	my $errorSkip = " 1>>$errorFile 2>>$errorFile";

	createDir($newServiceLocation, 1);
	chmod $Configuration::filePermission, $newServiceLocation;
	system('mv '.getECatfile($idriveUserDir).' '.getECatfile($newServiceLocation)." $errorSkip");
	chmod $Configuration::filePermission, "$newServiceLocation/$Configuration::traceLogFile" if (-e "$newServiceLocation/$Configuration::traceLogFile");
}

#------------------------------------------------- N -------------------------------------------------#

#------------------------------------------------- O -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: openEditor
# Objective				: This subroutine to view/edit the files using Linux editor
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub openEditor {
	my $action       = $_[0];
	my $fileLocation = $_[1];
	my $fileType     = $_[2];

	my $editorName = ((getUserConfiguration('DEFAULTTEXTEDITOR') ne '')? getUserConfiguration('DEFAULTTEXTEDITOR') : getEditor());
	my $editorHelpMsg = $editorName;
	my $operationStatus = 1;
	if ($editorName =~ /vi/){
		$editorHelpMsg = 'vi';
	}
	elsif ($editorName =~ /nano/){
		$editorHelpMsg = 'nano';
	}
	elsif ($editorName =~ /ee/){
		$editorHelpMsg = 'ee';
	}
	elsif ($editorName =~ /emacs/){
		$editorHelpMsg = 'emacs';
	}
	elsif ($editorName =~ /ne/){
		$editorHelpMsg = 'ne';
	}
	elsif ($editorName =~ /jed/){
		$editorHelpMsg = 'jed';
	}

	unless(`which $editorName 2>/dev/null`) {
		display(["\n", 'unable_to_find_editor']);
		display(['please_provide_name_of_editor_in_machine', ': '], 0);
		my $custeditor = getUserChoice();

		retreat(['unable_to_proceed', ' ', 'please_make_sure_you_have_editor']) unless($custeditor);
		retreat(['unable_to_proceed', ' ', 'unable_to_find_entered_editor']) unless(`which $custeditor 2>/dev/null`);

		$editorName = $custeditor;
		$editorHelpMsg = $editorName;
		setUserConfiguration('DEFAULTTEXTEDITOR', $custeditor);
		# saveUserConfiguration();
	}

	display(["\n", 'press_keys_to_close_' . $editorHelpMsg . '_editor'], 1) if ($action eq 'edit');
	display(["\n", 'press_keys_to_quit_' . $editorHelpMsg . '_editor'], 1) if ($action eq 'view');
	display(["\n", 'opening_file_to_' . $action, "\n"], 1);

	sleep(4);
	retreat(["\n", 'file_not_found', ":$fileLocation\n"]) if ($action eq 'view' and !-f "$fileLocation");

	my $initialts = ((-f $fileLocation)? stat($fileLocation)->mtime : 0);
	$operationStatus = system("$editorName '$fileLocation'");
	my $editedts = ((-f $fileLocation)? stat($fileLocation)->mtime : 0);

	return display(["\n", 'could_not_complete_operation', " Reason: $!\n"], 1) if ($operationStatus != 0);
	return if ($action ne 'edit');

	unless($fileType =~ /Partial/i or $fileType =~ /Regex/i){
		my @newItemArray = verifyEditedFileContent($fileLocation);
		if (scalar(@newItemArray)){
			my %newItemArray = getUniquePresentData(\@newItemArray,$fileType);
			my %list = skipChildIfParentDirExists(\%newItemArray);
			@newItemArray = keys %list;
		}
		my $content = '';
		$content = join("\n", @newItemArray) if (scalar(@newItemArray));
		Helpers::fileWrite($fileLocation,$content);
		display('') if ($skippedItem);
	}
	if ($initialts != $editedts or $skippedItem){
		$fileType = ($LS{$fileType})? $LS{$fileType} . "set" : $fileType if ($fileType);
		return display([$fileType, 'has_been_edited_successfully', "\n"], 1);
	}
	return display(['no_changes_has_been_made', "\n"], 1);
}

#------------------------------------------------- P -------------------------------------------------#

#*****************************************************************************************************
# Subroutine : prettyPrint
# Objective  : Pretty print strings
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub prettyPrint {
	my @data = @_;
	my $messages;
	my $msg = '';
	foreach (@data) {
		if (reftype(\$_->[1]) eq 'SCALAR') {
			$messages = [$_->[1]];
		}
		else {
			$messages = $_->[1];
		}

		my $m = '';
		for my $i (0 .. $#{$messages}) {
			if (exists $LS{$messages->[$i]}) {
				$m .= $LS{$messages->[$i]};
			}
			else {
				$m .= $messages->[$i];
			}
		}
		$msg .= sprintf("%$_->[0]", $m);
	}
	print $msg;
}

#*****************************************************************************************************
# Subroutine			: processShellCopy
# Objective				: This is to process shell script preparation and copying to launch path
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub processShellCopy {
	my $opconf = $_[0];

	return unless(%{$opconf->{'shellcp'}});

	my $setuppath = getAppPath() . $opconf->{'setupdir'};
	my $shellpath = '';
	foreach my $cpkey (keys %{$opconf->{'shellcp'}}) {
		$shellpath = $setuppath . $cpkey;
		# Replace the file path holder with cron script path
		my $fc 			= getFileContents($shellpath);
		Chomp(\$fc);
		$fc		=~ s/__LAUNCHPATH__/$Configuration::cronLinkPath/g;
		fileWrite($opconf->{'shellcp'}{$cpkey}, $fc);
		chmod($Configuration::execPermission, $opconf->{'shellcp'}{$cpkey}) unless((split('\.', basename($opconf->{'shellcp'}{$cpkey})))[1]);
	}
}

#*****************************************************************************************************
# Subroutine			: processCRONSetupCommands
# Objective				: This is to execute necessary commands for enabling the new cron service
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub processCRONSetupCommands {
	my $opconf = $_[0];

	return unless(@{$opconf->{'setupcmd'}});

	for my $i (0 .. $#{$opconf->{'setupcmd'}}) {
		`$opconf->{'setupcmd'}[$i] 1>/dev/null 2>/dev/null`;
	}

	sleep(5);
}

#*****************************************************************************************************
# Subroutine			: processCRONShellLinks
# Objective				: This is to create links to shell if required
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub processCRONShellLinks {
	my $opconf = $_[0];

	return unless(%{$opconf->{'shellln'}});

	foreach my $lndest (keys %{$opconf->{'shellln'}}) {
		`ln -s $opconf->{'shellln'}{$lndest} $lndest 1>/dev/null 2>/dev/null`;
	}
}

#*****************************************************************************************************
# Subroutine			: processCRONConfAppends
# Objective				: This is to process append contents to conf
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub processCRONConfAppends {
	my $opconf 		= $_[0];

	return unless(%{$opconf->{'confappend'}});

	my ($appendto, $appendfrom)	= ('', '');
	my $setuppath 	= getAppPath() . $opconf->{'setupdir'};
	foreach my $appkey (keys %{$opconf->{'confappend'}}) {
		$appendfrom = $setuppath . $appkey;
		$appendto 	= $opconf->{'confappend'}{$appkey};

		my $fc 			= getFileContents($appendto);
		Chomp(\$fc);
		my $appendcont	= getFileContents($appendfrom);
		Chomp(\$appendcont);

		if (index($fc, $appendcont) == -1) {
			$fc 		= qq($fc\n$appendcont);
			fileWrite($appendto, $fc);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: parseEVSCmdOutput
# Objective				: Parse evs response and return the same
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub parseEVSCmdOutput {
	my @parsedEVSCmdOutput;
	if (defined($_[0]) and defined($_[1])) {
		$_[0] =~ s/""/" "/g;
		my $endTag = '\/>';
		$endTag = "><\/$_[1]>" if (defined($_[2]));

		my @x = $_[0] =~ /(<$_[1]) (.+?)($endTag)/sg;

		for (1 .. (scalar(@x)/3)) {
			# following regex can be used when escaped double quote comes
			# my @keyValuePair = $x[(((3 * $_) - 2))] =~ /(.+?)="([^\\"]|.+?[^\\"])"/sg;
			my @keyValuePair = $x[(((3 * $_) - 2))] =~ /(.+?)="(.+?)"/sg;

			my %data;
			for (0 .. ((scalar(@keyValuePair)/2) - 1)) {
				$keyValuePair[($_ * 2)] =~ s/^\s+|\s+$//g;
				#$data{$keyValuePair[($_ * 2)]} = $keyValuePair[(($_ * 2) + 1)] =~ s/^\s$//gr;
				$keyValuePair[(($_ * 2) + 1)] =~ s/^\s$//g;
				$data{$keyValuePair[($_ * 2)]} = $keyValuePair[(($_ * 2) + 1)];
			}
			if (exists $data{'status'}) {
				$data{'STATUS'} = uc($data{'status'});
			}
			elsif (exists $data{'message'} and
							($data{'message'} eq Configuration::FAILURE or
								$data{'message'} eq Configuration::SUCCESS or
								$data{'message'} eq 'ERROR')) {
				if ($data{'message'} eq 'ERROR') {

					$data{'STATUS'} = Configuration::FAILURE;
				}
				else {
					$data{'STATUS'} = $data{'message'};
				}
			}
			else {
				$data{'STATUS'} = Configuration::SUCCESS;
			}
			push @parsedEVSCmdOutput, \%data;
		}
	}

	unless (@parsedEVSCmdOutput) {
		if (defined($_[0]) and ($_[0] ne '')) {
			$_[0] =~ s/connection established\n//g;
			chomp($_[0]);
		}

		push @parsedEVSCmdOutput, {
			'STATUS' => Configuration::FAILURE,
			'MSG'    => $_[0]
		};
	}

	return @parsedEVSCmdOutput;
}

#****************************************************************************************************
# Subroutine Name         : parseXMLOutput.
# Objective               : Parse evs command output and load the elements and values to an hash.
# Added By                : Dhritikana.
# Modified By 		  : Abhishek Verma - 7/7/2017 - Now this subroutine can parse multiple tags of xml. Previously it was restricted to one level.
#*****************************************************************************************************/
sub parseXMLOutput
{
	my %resultHash;
	my $parseDeviceList = $_[1];
	${$_[0]} =~ s/^$//;
	if (defined ${$_[0]} and ${$_[0]} ne "") {
		my $evsOutput = ${$_[0]};
		#clearFile($evsOutput);
		my @evsArrLine = ();
		if ($parseDeviceList){
			if ($evsOutput =~ /No devices found/){
				return %resultHash;
			} else {
				@evsArrLine = grep {/\w+/} grep {/bucket_type=\"D\"/} split(/(?:\<item|\<login|<tree)/, $evsOutput);
			}
		}else{
				@evsArrLine = grep {/\w+/} split(/(?:\<item|\<login|<tree)/, $evsOutput);
		}
		my $attributeCount = 1;
		foreach(@evsArrLine) {
			my @evsAttributes = grep {/\w+/} split(/\"[\s\n\>]+/s, $_);
			foreach (@evsAttributes){
				s/\"\/\>//;
				s/\"\>//;
				my ($key,$value) = split(/\=["]/, $_);
		 		&Chomp(\$key)	if (defined($key));
				#&Chomp(\$value); #Commented by Senthil for Harish_2.17_6_12 on 09-Aug-2018
				if ($parseDeviceList){
					my $subKey = $value.'_'.$attributeCount;
					$subKey = $value if (/(?:uid|device_id|server_root)/i);
					$resultHash{$key}{$subKey} = $attributeCount;
				}else{
					$resultHash{$key} = $value;
				}
			}
			$attributeCount++;
		}
	}
	return %resultHash;
}

#****************************************************************************************************
# Subroutine Name         : proxyBackwardCompatability
# Objective               : Backward compatability to update proxy fields
# Added By                : Anil
#*****************************************************************************************************/
sub proxyBackwardCompatability {
	my $proxyValue   = getUserConfiguration('PROXY');
	my $proxyIpValue = getUserConfiguration('PROXYIP');
	if ($proxyValue eq "" and !$proxyIpValue) {
		setUserConfiguration('PROXYIP', '');
		setUserConfiguration('PROXYPORT', '');
		setUserConfiguration('PROXYUSERNAME', '');
		setUserConfiguration('PROXYPASSWORD', '');
		setUserConfiguration('PROXY', '');
	}
	elsif (!$proxyIpValue or ($proxyValue ne "" and $proxyIpValue eq "")) {
		my @val = split('@',$proxyValue);
		my @userInfo = split(':',$val[0]);
		my @serverInfo = split(':',$val[1]);
		$userInfo[0] = ($userInfo[0])?$userInfo[0]:'';
		$userInfo[1] = ($userInfo[1])?$userInfo[1]:'';
		setUserConfiguration('PROXYIP',$serverInfo[0]);
		setUserConfiguration('PROXYPORT',$serverInfo[1]);
		setUserConfiguration('PROXYUSERNAME',$userInfo[0]);
		my $proxySIPPasswd = $userInfo[1];
		if ($proxySIPPasswd ne ''){
			trim($proxySIPPasswd);
			$proxySIPPasswd = encryptString($proxySIPPasswd);
		}
		setUserConfiguration('PROXYPASSWORD', $proxySIPPasswd);
		setUserConfiguration('PROXY', $userInfo[0].":".$proxySIPPasswd."@".$serverInfo[0].":".$serverInfo[1]);
	}
}

#****************************************************************************************************
# Subroutine Name         : putParameterValueInStatusFile.
# Objective               : Changes the content of STATUS FILE as per values passed
# Added By                : Dhritikana
#*****************************************************************************************************/
sub putParameterValueInStatusFile
{
	my $statusFilePath  = $Configuration::jobRunningDir."/".$Configuration::statusFile;
	open STAT_FILE, ">", $statusFilePath or (traceLog($Locale::strings{'failed_to_open_file'}." : $statusFilePath. Reason :$!") and die);
	#foreach my $keys(keys $Configuration::statusHash) {
	foreach my $keys(keys %Configuration::statusHash) {
		print STAT_FILE "$keys = $Configuration::statusHash{$keys}\n";
	}
	close STAT_FILE;
	chmod $Configuration::filePermission, $statusFilePath;
	undef @Configuration::linesStatusFile;
}
#------------------------------------------------- Q -------------------------------------------------#

#------------------------------------------------- R -------------------------------------------------#
#*****************************************************************************************************
# Subroutine		: readInfoFile
# Objective			: Read INFO file & return the value for key
# Added By 			: Senthil Pandian
#*****************************************************************************************************
sub readInfoFile {
	my $pattern = $_[0];
	my $count   = 0;
	my $infoFile = Helpers::getCatfile($Configuration::jobRunningDir, 'info_file');
	if (-e $infoFile and !-z $infoFile){
		my $fileCountCmd = "cat '$infoFile' | grep -m1 \"^$pattern\"";
		$count  = `$fileCountCmd`;
		if ($count =~ /$pattern/){
			$count =~ s/$pattern//;
			Chomp(\$count) if ($count);
		}
	}
	return $count;
}

#*****************************************************************************************************
# Subroutine		: replaceXMLcharacters
# Objective			: Replaces the special characters in XML output with their actual characters
# Added By 			: Senthil Pandian
#*****************************************************************************************************
sub replaceXMLcharacters {
	my ($fileToCheck) = @_;
	${$fileToCheck} =~ s/&apos;/'/g;
	${$fileToCheck} =~ s/&quot;/"/g;
	${$fileToCheck} =~ s/&amp;/&/g;
	${$fileToCheck} =~ s/&lt;/</g;
	${$fileToCheck} =~ s/&gt;/>/g;
}

#*****************************************************************************************************
# Subroutine			: rtrim
# Objective				: This function will remove white spaces from the right side of a string
# Added By				: Anil Kumar
#****************************************************************************************************/
sub rtrim {
	my $s = shift;
	$s =~ s/\s+$//;
	return $s;
}

#*****************************************************************************************************
# Subroutine			: retreat
# Objective				: Raise an exception and exit immediately
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub retreat {
	displayHeader();
	if ($servicePath ne '') {
		my ($package, $filename, $line) = caller;
		traceLog($_[0], basename($filename), $line) ;
	}
	unless ($Configuration::callerEnv eq 'BACKGROUND') {
		display($_[0]) unless (defined($_[1]) and ($_[1] == 1));
	}

	if ($servicePath ne '') {
		rmtree("$servicePath/$Configuration::downloadsPath");
		rmtree("$servicePath/$Configuration::tmpPath");
	}
	die "\n";
}

#*****************************************************************************************************
# Subroutine			: retreatDisplay
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub retreatDisplay {
	my $confStatus = $_[0];
	return	if ($confStatus == 0);
	retreat('login_&_try_again') if ($confStatus == 1);
	retreat('your_account_not_configured_properly') if ($confStatus == 2);
	retreat('Invalid Dir') if ($confStatus == 3);
	retreat('SERVERROOT is misssing') if ($confStatus == 4);
}

#*****************************************************************************************************
# Subroutine			: request
# Objective				: Make a server request
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub request {
	my $l = eval {
		require Idrivelib;
		Idrivelib->import();
		1;
	};
	my ($args) = $_[0];

	my $proxy = '';
	if (getUserConfiguration('PROXYIP')) {
		$proxy = '-x http://';
		$proxy .= getUserConfiguration('PROXYIP');

		if (getUserConfiguration('PROXYPORT')) {
			$proxy .= (':' . getUserConfiguration('PROXYPORT'))
		}
		if (getUserConfiguration('PROXYUSERNAME')) {
			my $pu = getUserConfiguration('PROXYUSERNAME');
			foreach ($pu) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$proxy .= (' --proxy-user ' . $pu);

			if (getUserConfiguration('PROXYPASSWORD')) {
				my $ppwd = getUserConfiguration('PROXYPASSWORD');
				$ppwd = ($ppwd ne '')?decryptString($ppwd):$ppwd;
				foreach ($ppwd) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				$proxy .= (':' . $ppwd);
			}
		}
	}

	my $curl = "curl --fail -ks $proxy -L --max-time 30";
	my $dataFile = '';

	if ($args->{'data'}) {
		$dataFile = getCatfile(getUserProfilePath(), $Configuration::tmpPath);
		unless (createDir($dataFile, 1) and fileWrite($dataFile = getCatfile($dataFile, mktime(localtime)), buildQuery($args->{'data'}))) {
			traceLog('unable_to_create_curl_form_data');
			return {STATUS => Configuration::FAILURE, DATA => ''};
		}
		chmod 0600, $dataFile;
		$curl .= (" -d \@'$dataFile'");
	}

	if ($args->{'encDATA'}) {
		$dataFile = getCatfile(getUserProfilePath(), $Configuration::tmpPath);
		unless (createDir($dataFile, 1) and fileWrite($dataFile = getCatfile($dataFile, mktime(localtime)), $args->{'encDATA'})) {
			traceLog('unable_to_create_curl_form_data');
			return {STATUS => Configuration::FAILURE, DATA => ''};
		}
		chmod 0600, $dataFile;
		$curl .= (" -d \@'$dataFile'");
	}

	if ($args->{'host'}) {
		$curl .= (' ' . $args->{'host'});
	}
	else {
		#retreat('no_url_specified');
		return {STATUS => Configuration::FAILURE, DATA => 'no_url_specified'};
	}

	if ($args->{'port'}) {
		$curl .= (':' . $args->{'port'});
	}

	if ($args->{'path'}) {
		$curl .= $args->{'path'};
	}

	if ($args->{'queryString'}) {
		$curl .= ('?\'' . buildQuery($args->{'queryString'}) . '\'');
	}

	my $tmpErrorFile  = (-e getServicePath())?getServicePath()."/".$Configuration::errorFile:"/tmp/".$Configuration::errorFile;
	unlink($tmpErrorFile) if (-e $tmpErrorFile);
	my $hostNotFound = 1;
CONNECT:
	my ($response, $page, %responseheaders);

	$response = `$curl 2>'$tmpErrorFile'`;
	if (($? > 0) and -f $tmpErrorFile and !-z $tmpErrorFile and
		getFileContents($tmpErrorFile) =~ 'unknown message digest algorithm') {
		traceLog("request failed: unknown message digest algorithm");
	}
	else {
		$hostNotFound = 0;
	}

	if ($hostNotFound and $l and $args->{'method'} eq 'POST') {
		eval "use Net::SSLeay qw(get_https post_https sslcat make_headers make_form)";
		#use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
		my $proxuser = getUserConfiguration('PROXYUSERNAME');
		my $proxpwd = getUserConfiguration('PROXYPASSWORD') ne ''? Helpers::decryptString(getUserConfiguration('PROXYPASSWORD')) : '';
		Net::SSLeay::set_proxy(getUserConfiguration('PROXYIP'), getUserConfiguration('PROXYPORT'), $proxuser, $proxpwd) if(getUserConfiguration('PROXY') ne '');
		$args->{'host'} =~ s/https:\/\///;
		my ($host, $path) = split(/\//, $args->{'host'},2);
		#traceLog("host:$host");
		#traceLog("path:$path");
		#traceLog($args->{'encDATA'});
		#my $data = (defined($args->{'encDATA'}))?$args->{'encDATA'}:$args->{'data'};
		if($args->{'method'} eq 'POST'){
			($response, $page, %responseheaders) =
			post_https($host, $args->{'port'} || 443, "/$path",
									'', (make_form(%{$args->{'data'}})));
		} else {
			if(defined($args->{'queryString'})) {
				$path .= "?".$args->{'queryString'};
			} elsif(defined($args->{'encDATA'})) {
				$path .= "?".$args->{'encDATA'};
			} elsif(defined($args->{'data'})) {
				$path .= buildQuery($args->{'data'});
			}
			($response, $page, %responseheaders) =
				post_https($host, $args->{'port'} || 443, "/$path",
									'', '');
		}

		if ($page =~ 'NET OR SSL ERROR') {
			traceLog("request failed: $page");
			return {STATUS => Configuration::SUCCESS, DATA => ''};
		}

		#traceLog("response:$response");
		#traceLog("page:$page");
	}

	Chomp(\$response);
	#traceLog("CURL-RESPONSE: $response");
	if (($? > 0 and ($?%256) > 0) or (-e $tmpErrorFile and -s $tmpErrorFile)) {
		unless ($Configuration::callerEnv eq 'BACKGROUND') {
			if (-e $tmpErrorFile and -s $tmpErrorFile){
				if (!open(FH, "<", $tmpErrorFile)) {
					my $errStr = $LS{'failed_to_open_file'}.":$tmpErrorFile, Reason:$!";
					traceLog($errStr);
				}
				my $byteRead = read(FH, $response, $Configuration::bufferLimit);
				close FH;
				Chomp(\$response);
			}
			unlink($tmpErrorFile) if (-e $tmpErrorFile);
			goto CONNECT if ($response eq '' && isInternetAvailable());

			#retreat(["\n", 'please_check_internet_con_and_try']) if ($response eq '' && !isInternetAvailable());
			return {STATUS => Configuration::FAILURE, DATA => 'please_check_internet_con_and_try'} if ($response eq '' && !isInternetAvailable());

			if (($response =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Failed connect to .* Connection refused|Connection timed out|response code said error|407|No route to host|Could not resolve host/)) {

				#retreat(["\n", 'kindly_verify_ur_proxy']) if (defined($_[2]));
				return {STATUS => Configuration::FAILURE, DATA => 'kindly_verify_ur_proxy'};

				display(["\n", 'kindly_verify_ur_proxy']);
				#askProxyDetails() or retreat('failed due to proxy');
				askProxyDetails() or return {STATUS => Configuration::FAILURE, DATA => 'failed due to proxy'};
				return request($_[0], "NoRetry");

				# saveUserConfiguration() or retreat('failed to save user configuration');
			}
			elsif ($response =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
				#retreat($response);
				return {STATUS => Configuration::FAILURE, DATA => $response};
			} else {
				traceLog("CURL-ERROR: $response");
			}
		}
		unlink($tmpErrorFile) if (-e $tmpErrorFile);
		unlink($dataFile);
		return {STATUS => Configuration::FAILURE, DATA => ''};
	}
	unlink($tmpErrorFile) if (-e $tmpErrorFile);
	unlink($dataFile);
	return {STATUS => Configuration::SUCCESS, DATA => JSON::from_json($response)} if ($args->{'json'});

	return {STATUS => Configuration::SUCCESS, DATA => $response};
}

#*****************************************************************************************************
# Subroutine			: removeIDriveCRON
# Objective				: This is to uninstall IDrive CRON service
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub removeIDriveCRON {
	loadCrontab(1);
	my %crontab = %{getCrontab()};
	my ($skipped, $cronLinkRemoved) = (0) x 2;
	my ($cronLinkPath, $cronScriptDir, $existingScriptDir) = ('') x 3;
	my $currentDir  	= getAppPath();
	if (-e $Configuration::cronLinkPath) {
		$cronLinkPath 	= readlink($Configuration::cronLinkPath);
		$cronScriptDir	= dirname($cronLinkPath) . '/' if ($cronLinkPath);

		foreach my $mcUser (keys %crontab){
			foreach my $idriveUser (keys %{$crontab{$mcUser}}){
				if ($crontab{$mcUser}{$idriveUser}{'dashboard'}{'dashboard'}{'cmd'}){
					my $dashboardCmd = $crontab{$mcUser}{$idriveUser}{'dashboard'}{'dashboard'}{'cmd'};
					if ($dashboardCmd ne '' && $dashboardCmd =~ /dashboard.pl/) {
						my $scriptPath = dirname($dashboardCmd) . '/';
						if ($scriptPath eq $currentDir || !-e $scriptPath) {
							delete $crontab{$mcUser}{$idriveUser};
							if ($scriptPath eq $cronScriptDir) {
								unlink($Configuration::cronLinkPath);
								$cronLinkRemoved = 1;
							}
						} else {
							$skipped++;
							$existingScriptDir = $scriptPath;
						}
					}
				}
			}
		}

		# Checking & saving the updated cron entries
		if ($skipped > 0) {
			saveCrontab();
			#Creating new link if cron link removed due to uninstalling the path
			if ($cronLinkRemoved) {
				my $cmd = "ln -s '" . $existingScriptDir . $Configuration::idriveScripts{'cron'} . "' '$Configuration::cronLinkPath'";
				chmod($Configuration::execPermission, $Configuration::cronLinkPath);
				system($cmd);
			}

			# Launch Cron service from here
			unless(checkCRONServiceStatus() == CRON_RUNNING) {
				launchIDriveCRON();
			} else {
				my @lockinfo 	= getCRONLockInfo();
				$lockinfo[2] = 'restart';
				fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
			}

			return;
		}
	}

	my $opconf	= getCRONSetupTemplate();
	if (%{$opconf}) {
		# execute stop commands
		if (@{$opconf->{'stopcmd'}}) {
			for my $i (0 .. $#{$opconf->{'stopcmd'}}) {
				`$opconf->{'stopcmd'}[$i] 1>/dev/null 2>/dev/null`;
			}
		}

		# remove created links
		if (%{$opconf->{'shellln'}}) {
			foreach my $lndest (keys %{$opconf->{'shellln'}}) {
				removeItems("$lndest");
			}
		}

		# remove all copied shells
		if (%{$opconf->{'shellcp'}}) {
			my $shellpath = '';
			foreach my $cpkey (keys %{$opconf->{'shellcp'}}) {
				removeItems("$opconf->{'shellcp'}{$cpkey}");
			}
		}

		if (%{$opconf->{'confappend'}}) {
			my ($appendto, $appendfrom)	= ('', '');
			my $setuppath 	= getAppPath() . $opconf->{'setupdir'};
			foreach my $appkey (keys %{$opconf->{'confappend'}}) {
				$appendfrom = $setuppath . $appkey;
				$appendto 	= $opconf->{'confappend'}{$appkey};

				my $fc 			= getFileContents($appendto);
				Chomp(\$fc);
				my $appendcont	= getFileContents($appendfrom);
				Chomp(\$appendcont);

				if (index($fc, $appendcont) != -1) {
					$fc 		=~ s/$appendcont\n//;
					fileWrite($appendto, $fc);
				}
			}
		}
	}

	# fallback logic has to be removed if added
	if (hasCRONFallBackAdded()) {
		traceLog(['checking_fallback_cron']);

		my $fc		= getFileContents('/etc/crontab');
		my @fch		= split("\n", $fc);
		for my $ind (0 .. $#fch) {
			splice(@fch, $ind, 1) if (index($fch[$ind], $Configuration::cronLinkPath) != -1)
		}

		$fc = join("\n", @fch);
		fileWrite('/etc/crontab', $fc);
	}

	# clean up the links and crontab file
	unlink($Configuration::cronlockFile) if (-f $Configuration::cronlockFile);
	unlink(getCrontabFile()) if (-f getCrontabFile());
	unlink($Configuration::cronLinkPath) if (-f $Configuration::cronLinkPath);
}

#*****************************************************************************************************
# Subroutine			: removeBKPSetSizeCache
# Objective				: This is to cleanup backupset size cache
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub removeBKPSetSizeCache {
	return 0 unless($_[0]);

	my $backupsizelock = getBackupsetSizeLockFile($_[0]);
	return 0 if (isFileLocked($backupsizelock));

	my $backupsizefile = getCatfile(getUsersInternalDirPath($_[0]), $Configuration::backupsizefile);
	unlink($backupsizefile) if (-f $backupsizefile);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: reCalculateStorageSize
# Objective				: Request IDrive server to re-calculate storage size
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub reCalculateStorageSize {
	my $calculateStorageSize = "$appPath/".$Configuration::idriveScripts{'utility'}." GETQUOTA";
	my $runCmd = `$Configuration::perlBin $calculateStorageSize 2>/dev/null&`; #2>/dev/null
	return 0;

	# my $csf = getCachedStorageFile();
	# unlink($csf);
	# createUTF8File('GETQUOTA') or
		# retreat('failed_to_create_utf8_file');
	# my @result = runEVS('tree');
	# if (exists $result[0]->{'message'}) {
		# if ($result[0]->{'message'} eq 'ERROR') {
			# display('unable_to_retrieve_the_quota') unless(defined($_[0]));
			# return 0;
		# }
	# }
	# if (saveUserQuota(@result)) {
		# return 1 if loadStorageSize();
	# }
	# traceLog('unable_to_cache_the_quota');
	# display('unable_to_cache_the_quota') unless(defined($_[0]));
	# return 0;
}

#*****************************************************************************************************
# Subroutine			: runEVS
# Objective				: Execute evs binary using backtick operator and return parsed output
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub runEVS {
	my $isErrorFile = 0;
	my $runInBackground = "";
	my $tempUtf8File = $utf8File;
	my $extras = '';

	$isErrorFile     = 1        if (defined($_[1]));
	$runInBackground = "&"      if (defined($_[2]));
	$tempUtf8File    = $_[3]    if (defined($_[3]));
	$extras         .= ";$_[4]" if (defined($_[4]));

	my ($idevscmdout,$idevcmd) = ('')x 2;
	my $evsPath = getEVSBinaryFile();
	if (-e $evsPath) {
		$idevcmd = ("'$evsPath' --utf8-cmd='$tempUtf8File'");
		if ($runInBackground) {
			$idevscmdout = system("($idevcmd $extras) 1>/dev/null 2>/dev/null $runInBackground");
		}
		else {
			$idevscmdout = `$idevcmd 2>&1`;
		}

		my @errArr;
		#if (($? > 0) and !$isErrorFile and $idevscmdout !~ /no version information available/) {
		# Modified by Senthil for Harish_2.17_55_2
		if (!$isErrorFile and $idevscmdout !~ /no version information available/) {
			my $msg = 'execution_failed';
			if (($idevscmdout =~ /\@ERROR: PROTOCOL VERSION MISMATCH on module ibackup/ or
						$idevscmdout =~ /Failed to validate. Try again/) and
					$userConfiguration{'DEDUP'} ne 'off') {
				setUserConfiguration('DEDUP', 'off');
				return runEVS($_[0]);
			}
			if (($? > 0)){
				if ($idevscmdout =~ /\@ERROR:/ and
					$idevscmdout =~ /encryption verification failed/) {
					$msg = 'encryption_verification_failed';
				}
				elsif ($idevscmdout =~ /private encryption key must be between 4 and 256 characters in length/) {
					$msg = 'private_encryption_key_must_be_between_4_and_256_characters_in_length';
				}
				elsif ($idevscmdout =~ /(failed to connect|Connection refused|407|Could not resolve proxy|Could not resolve host|No route to host)/i) {
					$msg = 'kindly_verify_ur_proxy';
				} else {
					traceLog($idevscmdout);
					$msg = checkErrorAndLogout($idevscmdout,1);
				}
				push @errArr, {
					'STATUS' => Configuration::FAILURE,
					'MSG'    => $msg
				};
				unlink($tempUtf8File);
				return @errArr;
			}
		}

		unlink($tempUtf8File) if ($runInBackground eq "");

		#Added by Senthil : 03-JULY-2018
		if ($idevscmdout =~ /no version information available/){
			my @linesOfRes = split(/\n/,$idevscmdout);
			my $warningString = "no version information available";
			my @finalLines = grep !/$warningString/, @linesOfRes;
			$idevscmdout  = join("\n",@finalLines);
		}
		if ($idevscmdout eq '') {
			my $status = ($isErrorFile)?Configuration::FAILURE:Configuration::SUCCESS;
			push @errArr, {
				'STATUS' => $status,
				'MSG'    => 'no_stdout'
			};
			return @errArr;
		}
		return parseEVSCmdOutput($idevscmdout, $_[0]);
	}
	else {
		my @errArr;
		push @errArr, {
			'STATUS' => Configuration::FAILURE,
			'MSG'    => 'Unable to find or execute EVS binary. Please configure or re-configure your account using account_setting.pl'
		};
		unlink($tempUtf8File);
		return @errArr;
	}
}


#*****************************************************************************************************
# Subroutine			: runningJobHandler
# Objective				: This function will allow to change the backup/restore from location only if no scheduled backup / restore job is running. if any of previously mentioned job is runnign then it will first ask for the termination of running job then allow to change location.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub runningJobHandler {
	my ($jobType, $jobMode, $username, $userProfilePath) = @_;
	my $pidPath = $userProfilePath.'/'.$username.'/'.$jobType.'/'.$jobMode.'/pid.txt';
	my $changeLocationStatus = 0;
	if (isRunningJob($pidPath)) {
		my $confMessage = "\n" . $LS{'changing_title'} . ' ' . $jobType . ' ' . $LS{'location_will_terminate'} . ' ';
		$confMessage 	.= $jobMode . ' ' . $jobType . ' ' . $LS{'in_progress'} . '... ' . $LS{'do_you_want_to_continue_yn'};
		my $choice = getAndValidate('enter_your_choice', "YN_choice", 1);
		if (($choice eq 'y')) {
			display([qq(\n$LS{'terminating_your_title'} $jobMode $jobType $LS{'job'}. $LS{'please_wait_title'}...)]);
			my $jobTerminationScript = getScript('job_termination', 1);
			my $jobTermCmd = "$Configuration::perlBin $jobTerminationScript ".lc($jobType)." $username";
			my $res = system($jobTermCmd);
			if ($res != 0) {
				traceLog(qq($LS{'error_in_terminating'} $jobMode $jobType $LS{'job'}.));
			} else {
				$changeLocationStatus = 1;
			}
		}
	} else {
		$changeLocationStatus = 1;
	}

	return $changeLocationStatus;
}

#*****************************************************************************************************
# Subroutine			: renameDevice
# Objective				: This subroutineis is used to change the device name to the given name
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub renameDevice {
	createUTF8File('NICKUPDATE',$_[1],($Configuration::deviceIDPrefix .$_[0]->{'device_id'} .$Configuration::deviceIDSuffix)) or retreat('failed_to_create_utf8_file');

	my @result = runEVS('item', undef, ($_[2] || undef));
	return 1 if ( defined $_[2]);
	return 1 if ($result[0]->{'STATUS'} eq Configuration::SUCCESS);
	return 0;
}

#****************************************************************************************************
# Subroutine Name         : readFinalStatus.
# Objective               : reads the overall status file based on engine
# Added By                : Vijay Vinoth
#*****************************************************************************************************/
sub readFinalStatus
{
	my %statusFinalHash = 	(	"FILES_COUNT_INDEX" => 0,
						"SYNC_COUNT_FILES_INDEX" => 0,
						"FAILED_COUNT_FILES_INDEX" => 0,
						"ERROR_COUNT_FILES" => 0,
						"COUNT_FILES_INDEX" => 0,
						"DENIED_COUNT_FILES" => 0,
						"MISSED_FILES_COUNT" => 0,
						"EXIT_FLAG_INDEX" => 0,
					);
	my $statusFilePath  = $Configuration::jobRunningDir."/".$Configuration::statusFile;
	for(my $i=1; $i<= $Configuration::totalEngineBackup; $i++){
		if (-e $statusFilePath."_$i" and -f $statusFilePath."_$i" and -s $statusFilePath."_$i" ) {
			readStatusFile($i);
			$statusFinalHash{'FILES_COUNT_INDEX'} += $Configuration::statusHash{'FILES_COUNT_INDEX'};
			$statusFinalHash{'SYNC_COUNT_FILES_INDEX'} += $Configuration::statusHash{'SYNC_COUNT_FILES_INDEX'};
			$statusFinalHash{'FAILED_COUNT_FILES_INDEX'} += $Configuration::statusHash{'FAILED_COUNT_FILES_INDEX'};
			$statusFinalHash{'ERROR_COUNT_FILES'} += $Configuration::statusHash{'ERROR_COUNT_FILES'};
			$statusFinalHash{'DENIED_COUNT_FILES'} += $Configuration::statusHash{'DENIED_COUNT_FILES'};
			$statusFinalHash{'MISSED_FILES_COUNT'} += $Configuration::statusHash{'MISSED_FILES_COUNT'};
			$statusFinalHash{'COUNT_FILES_INDEX'} += $Configuration::statusHash{'COUNT_FILES_INDEX'};

			if (!$statusFinalHash{'EXIT_FLAG_INDEX'} or !defined $Configuration::statusHash{'EXIT_FLAG_INDEX'}){
				$statusFinalHash{'EXIT_FLAG_INDEX'} = $Configuration::statusHash{'EXIT_FLAG_INDEX'};
			}
		}
	}
	return (\%statusFinalHash);
}

#****************************************************************************************************
# Subroutine Name         : restoreBackupsetFileConfiguration.
# Objective               : This subroutine moves the BackupsetFile to the original configuration
# Added By                : Dhritikana
#*****************************************************************************************************/
sub restoreBackupsetFileConfiguration
{
	my $relativeFileset   = $Configuration::jobRunningDir."/".$Configuration::relativeFileset;
	my $noRelativeFileset = $Configuration::jobRunningDir."/".$Configuration::noRelativeFileset;
	my $filesOnly		  = $Configuration::jobRunningDir."/".$Configuration::filesOnly;
	my $info_file 	   	  = $Configuration::jobRunningDir."/".$Configuration::infoFile;

	if ($relativeFileset ne "") {
		unlink <$relativeFileset*>;
	}
	if ($noRelativeFileset ne "") {
		unlink <$noRelativeFileset*>;
	}
	if ($filesOnly ne "") {
		unlink <$filesOnly*>;
	}
	unlink $info_file;
}

#****************************************************************************************************
# Subroutine Name         : readStatusFile.
# Objective               : reads the status file
# Added By                : Deepak Chaurasia
# Modified By 		      : Vijay Vinoth for multiple engine.
#*****************************************************************************************************/
sub readStatusFile
{
	my $operationEngineId = $_[0];
	my $statusFilePath  = $Configuration::jobRunningDir."/".$Configuration::statusFile."_".$operationEngineId;
	if (! -s $statusFilePath ) {
		return;
	}else{
		chmod $Configuration::filePermission, $statusFilePath;
		if (open(STATUS_FILE, "< $statusFilePath")) {
			my @linesStatusFile = <STATUS_FILE>;
			@Configuration::linesStatusFile = @linesStatusFile;
			close STATUS_FILE;
			if ($#linesStatusFile >= 0) {
				foreach my $line (@linesStatusFile) {
					chomp $line;
					my @keyValuePair = split /=/, $line;
					s/^\s+|\s+$//g for (@keyValuePair);
					$keyValuePair[1] = 0 if (!$keyValuePair[1]);
					Chomp(\$keyValuePair[0]);
					Chomp(\$keyValuePair[1]);
					$Configuration::statusHash{$keyValuePair[0]} = looks_like_number($keyValuePair[1])? int($keyValuePair[1]) : $keyValuePair[1];
				}
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: restartIDriveCRON
# Objective				: This is to restart IDrive CRON
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub restartIDriveCRON {
	my $display 	= ((defined($_[0]) && $_[0] == 1)? 1 : 0);
	my $restartflag = ((checkCRONServiceStatus() == CRON_RUNNING)? 're' : '');

	display(["\n", $restartflag . 'starting_cron_service', '...']) if ($display);
	my $opconf	= getCRONSetupTemplate();

	my @oldlock = getCRONLockInfo();

	my $sudoprompt = 'please_provide_' . ((isUbuntu() || isGentoo())? 'sudoers' : 'root') . '_pwd_for_cron_restart';
	if (%{$opconf} && $opconf->{'restartcmd'} ne '') {
		unlink($Configuration::cronlockFile);
		my $restartcmd = getSudoSuCMD("$opconf->{'restartcmd'} 1>/dev/null 2>/dev/null", $sudoprompt, 1);
		my $res = system($restartcmd);
		sleep(5) unless($res > 0);
	} else {
		unlink($Configuration::cronlockFile) if (-e $Configuration::cronlockFile);
		my $restartcmd = getSudoSuCMD("$Configuration::perlBin '$Configuration::cronLinkPath' 1>/dev/null 2>/dev/null", $sudoprompt, 1);
		my $res = system($restartcmd);
		sleep(5) unless($res > 0);
	}

	my @newlock = getCRONLockInfo();

	my $restartstat = 0;
	$restartstat 	= 1 if (!defined($oldlock[0]) && defined($newlock[0]));
	$restartstat 	= 1 if (defined($oldlock[0]) && defined($newlock[0]) && $oldlock[0] != $newlock[0]);

	display([((checkCRONServiceStatus() == CRON_RUNNING && $restartstat)? $restartflag . 'started_cron_service' : 'failed_to_' . $restartflag . 'start_cron'), '.']) if ($display);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: resetUserCRONSchemas
# Objective				: This is to restart IDrive CRON
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub resetUserCRONSchemas {
	my @jobTypes = ("backup", "backup", "cancel", "cancel", "archive");
	my @jobNames = ("default_backupset", "local_backupset", "default_backupset", "local_backupset", "default_backupset");

	loadCrontab(1);

	for my $i (0 .. $#jobNames) {
		createCrontab($jobTypes[$i], $jobNames[$i]);
	}

	createCrontab($Configuration::dashbtask, $Configuration::dashbtask);
	setCronCMD($Configuration::dashbtask, $Configuration::dashbtask);

	saveCrontab();

	return 1;
}

#*****************************************************************************************************
# Subroutine			: removeEntryInCrontabLines
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub removeEntryInCrontabLines
{
	my $jobExists = getAppPath();
	my @linesCrontab = @_;
	my @updatedLinesCrontab = grep !/$jobExists/, @linesCrontab;
	return @updatedLinesCrontab;
}

#*****************************************************************************************************
# Subroutine			: readCrontab
# Objective				:
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub readCrontab {
	my @linesCrontab = ();
	my $crontabFilePath = "/etc/crontab";
	if (-l $crontabFilePath){
		my $crontabFilePath_bak = $crontabFilePath."_bak";
		my $res = system("mv $crontabFilePath $crontabFilePath_bak 2>/dev/null");
		if ($res ne "0") {
			traceLog("Unable to move crontab link file");
		}
		elsif (open CRONTABFILE, ">", $crontabFilePath){
			close CRONTABFILE;
			chmod 0644, $crontabFilePath;
		} else {
			traceLog("Couldn't open file $crontabFilePath");
		}
	} else {
		if (open CRONTABFILE, "<", $crontabFilePath){
			@linesCrontab = <CRONTABFILE>;
			close CRONTABFILE;
		} else {
			traceLog("Couldn't open file $crontabFilePath");
		}
	}
	return @linesCrontab;
}

#*****************************************************************************************************
# Subroutine			: removeItems
# Objective				: Centralized all the remove commands and loaded all the files to a trace file.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub removeItems {
	my $lastItem = "";
	my $path = $_[0];
	my @list = ();

	if (reftype(\$path) eq 'SCALAR') {
		push(@list, $path);
	}
	else {
		for my $i (0 .. $#{$path}) {
			push(@list, $path->[$i]);
		}
	}

	foreach my $pathVal (@list) {
		my $val = $pathVal;

		next if (($val eq "/") or ($val eq "")or ($val eq "*"));
		$val = getItemFullPath($val);
		my ($package, $filename, $line) = caller;
		my $callerInfo = " [ " . basename($filename). "] [Line:: ". $line." ] ";
		my $cmd = 'rm';
		if (!-f $val && !-d $val){
			my @spl = split('/', $val);
			$lastItem = pop @spl;
			$val = join("/", @spl)."/";
		}

		if (-d $val) {
			my $checkPath  = substr $val, -1;
			$checkPath = substr($val, 0, -1) if ($checkPath eq '/');

			next if (($checkPath eq "/") or ($checkPath eq "") or (getServicePath() eq $checkPath) or (getAppPath() eq $checkPath));
			$cmd .= " -rf '$val'$lastItem";
		}
		elsif (-f $val) {
			$cmd .= " '$val'";
		}
		else {
			# could be a link or may not exist
		}

		if ($cmd ne 'rm') {
			my $traceLog = "/tmp/idriveTraceLog.txt";
			writeToTrace($traceLog, $callerInfo.$val.$lastItem."\n");
			system($cmd);
		}
	}
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : removeUsersCronEntry
# Objective               : This subroutine will remove the cron entry of particular IDrive user.
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub removeUsersCronEntry {
	loadUsername() or return;
	my $userName = getUsername();
	loadCrontab(1);
	if ($crontab{$Configuration::mcUser}{$userName}){
		delete $crontab{$Configuration::mcUser}{$userName};
	}
	saveCrontab();
}

#****************************************************************************************************
# Subroutine		: removeIDriveUserFromUsersList
# Objective			: This subroutine will remove the entry from idriveuser.txt.
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub removeIDriveUserFromUsersList {
	my $userfile = Helpers::getCatfile(getServicePath(), $Configuration::cachedIdriveFile);
	return unless(-f $userfile);

	my $usrtxt = Helpers::getFileContents($userfile);
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		if ($usrtxt->{$Configuration::mcUser}){
			fileWrite(getCatfile(getServicePath(), $Configuration::cachedIdriveFile), JSON::to_json($usrtxt));
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : requestViaUtility
# Objective               : This subroutine will make a server request via utility
# Added By				  : Senthil Pandian
#*****************************************************************************************************/
sub requestViaUtility {
	my $paramFilePath = Helpers::getCatfile(getServicePath(), $Configuration::utilityRequestFile);
	$paramFilePath = Helpers::getCatfile(getUserProfilePath(), $Configuration::utilityRequestFile) if(-d getUserProfilePath());
	if(-e getIDrivePerlBin()){
		fileWrite($paramFilePath,JSON::to_json($_[0]));
		my $cmd = (getIDrivePerlBin() . ' ' .getScript('utility', 1) . ' SERVERREQUEST '." '".$paramFilePath."' 2>/dev/null");
		my $perlOutput = `$cmd`;
		if($perlOutput eq ''){
			traceLog('failed_to_run_script',getScript('utility', 1),". Reason:".$?);
			retreat(['failed_to_connect',". Please try again."]);
		}
		unlink($paramFilePath);
		return \%{JSON::from_json($perlOutput)};
	} else {
		my $res = request($_[0]);
		return \%{$res};
	}
}
#------------------------------------------------- S -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: saveLog
# Objective				: Save log files to cloud
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveLog {
	system(getIDrivePerlBin() . ' ' .getScript('utility', 1) . ' UPLOADLOG ' . qq('$_[0]')  . " 2> /dev/null &");
}

#*****************************************************************************************************
# Subroutine			: saveMigratedLog
# Objective				: Save migrated log files to cloud
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub saveMigratedLog {
	system(getIDrivePerlBin() . ' ' .getScript('utility', 1) . ' UPLOADMIGRATEDLOG ' . " 2> /dev/null &");
}

#*****************************************************************************************************
# Subroutine			: checkEmailNotify
# Objective				: this is to check and update if there is any email for specific job
# Added By				: Anil Kumar
# Modified By			: Vijay Vinoth
#****************************************************************************************************/
sub checkEmailNotify {
	loadCrontab();
	my ($jobType, $jobName) = ($_[0],$_[1]);
	$jobType = "backup";
	my $emailStatus = getCrontab($jobType, $jobName, '{settings}{emails}{status}') ;
#TBE
	my $email = "" ;
	if ( defined $emailStatus ) {
		return "DISABLED" if ($emailStatus eq 'disabled') ;
		$email = getCrontab($jobType, $jobName, '{settings}{emails}{ids}');
	} else {
		$email = Helpers::getUserConfiguration('EMAILADDRESS');
		if ($email eq "") {
			$emailStatus = "DISABLED";
		} else {
			$emailStatus = "ENABLED";
		}
	}
	return ($emailStatus,$email) ;
}

#*****************************************************************************************************
# Subroutine Name         : sendMail
# Objective               : sends a mail to the user in case of successful/canceled/ failed scheduled backup/restore.
# Added By                : Dhritikana
# Modified By			  : Vijay Vinoth
#********************************************************************************************************************
sub sendMail {
	my $taskType = $_[0];
	my $jobType  = $_[1];
	if (lc($taskType) eq "manual") {
		return;
	}

	my $jobName = "";
	if ($jobType eq "backup") {
		$jobName = "default_backupset";
	}
	elsif ($jobType eq "Express Backup") {
		$jobName = "local_backupset";
	} else {
		$jobName = "default_backupset";
	}
	my @responseData = &checkEmailNotify($jobType, $jobName );
	my $notifyEmailStatus = $responseData[0];
	if ($notifyEmailStatus eq "DISABLED") {
		return;
	}

	my $configEmailAddress = $responseData[1] if (defined $responseData[1]);
	my $jobStatus = (split '\_', $Configuration::outputFilePath)[-2];
	$jobStatus = lc $jobStatus;

	if ($notifyEmailStatus eq 'notify_failure'){
		return if (index($jobStatus, 'success') != -1);
	}

	my $finalAddrList = getFinalMailAddrList($configEmailAddress);
	if ($finalAddrList eq "NULL") {
		return;
	}
	my $userName      = getUsername();
	my $pData = &getPdata("$userName");
	if ($pData eq ''){
		traceLog($LS{'failed_to_send_mail'}.$LS{'password_missing'}, __FILE__, __LINE__);
		return;
	}

	my $sender = "support\@".$Configuration::servicePathName.".com";
	my $content = "";
	my $subjectLine = $_[2];
	my $operationData = $_[3];
	my $backupRestoreFileLink = $_[4];

	$content = "Dear $Configuration::appType User, \n\n";
	$content .= "Ref: Username - $userName \n";

	if (defined($operationData) and $operationData eq 'NOBACKUPDATA'){
		$content .= $LS{'unable_to_perform_backup_operation'};
	}
	elsif (defined($operationData) and $operationData eq 'NORESTOREDATA'){
		$content .= $LS{'unable_to_perform_restore_operation'};
	} else {
		$content .= $Configuration::mailContentHead;
		$content .= $Configuration::mailContent;
	}

	$content .= "\n\nRegards, \n";
	$content .= "$Configuration::appType Support.\n";
	$content .= "Version: $Configuration::version\n";
	$content .= "Release date: $Configuration::releasedate" ;

	#URL DATA ENCODING#
	foreach ($userName,$pData,$finalAddrList,$subjectLine,$content) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}

	my $data = 'username='.$userName.'&password='.$pData.'&to_email='.$finalAddrList.'&subject='.$subjectLine.'&content='.$content;
	my $curlCmd = formSendMailCurlcmd($data);

	my $sendMailMsg = `$curlCmd`;
}

#*****************************************************************************************************
# Subroutine			: setRestoreFromLocPrompt
# Objective				: Set restore location prompt
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub setRestoreFromLocPrompt {
	my $prevStatus  = 'enabled';
	my $statusQuest = 'disable';
	if (Helpers::getUserConfiguration('RESTORELOCATIONPROMPT') ne '' || defined($_[0])) {
		if (!Helpers::getUserConfiguration('RESTORELOCATIONPROMPT') && !defined($_[0])) {
			$prevStatus  = 'disabled';
			$statusQuest = 'enable';
		}
		Helpers::display(["\n",'restore_loc_prompt_'.$prevStatus," ", 'do_you_want_to_'.$statusQuest], 1);
		my $choice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
		$choice = lc($choice);
		return 1 if ($choice eq "n");
	}

	Helpers::setUserConfiguration('RESTORELOCATIONPROMPT', ($prevStatus eq 'disabled')? 1 : 0);
	Helpers::display(['restore_loc_prompt_' . (($prevStatus eq 'disabled')? 'enabled' : 'disabled')]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setNotifySoftwareUpdate
# Objective				: Set software update status to configuration
# Added By				: Anil Kumar
#****************************************************************************************************/
sub setNotifySoftwareUpdate {
	my $promptSelected;

	my $status ;
	if (defined getUserConfiguration('NOTIFYSOFTWAREUPDATE')) {
		$status = getUserConfiguration('NOTIFYSOFTWAREUPDATE');
	}
	else {
		$status = 1;
	}

	$promptSelected = ($status)?'software_update_prompt_enabled_with_disable_choice':'software_update_prompt_disabled_with_enable_choice';
	display(["\n",$promptSelected], 1);
	my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	return 1	if (lc($choice) eq "n");
	setUserConfiguration('NOTIFYSOFTWAREUPDATE', ($status)? 0 : 1);
	display(['software_update_prompt_' . ((!$status)? 'enabled' : 'disabled')]);
	return 1;
}


#*****************************************************************************************************
# Subroutine			: setUploadMultipleChunks
# Objective				: Set engine count
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub setUploadMultipleChunks {
	my $promptSelected;
	my $chunksenabled = 1;
	if (getUserConfiguration('ENGINECOUNT') ne '') {
		$chunksenabled = (getUserConfiguration('ENGINECOUNT') == 2)? 0 : 1;
		display(["\n", "upload_multiple_chunks_$chunksenabled", " ", 'do_you_want_to_' . ($chunksenabled? 'disable' : 'enable')]);
		my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);
		return 1 if (lc($choice) eq "n");
	} else {
		$chunksenabled = 0;
		display(["\n", "upload_multiple_chunks_$chunksenabled", " ", 'do_you_want_to_' . ($chunksenabled? 'disable' : 'enable')]);
	}

	setUserConfiguration('ENGINECOUNT', ($chunksenabled)? 2 : 4);
	display(['upload_multiple_chunks_' . (($chunksenabled)? 'disabled' : 'enabled')]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setUsername
# Objective				: Assign username
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setUsername {
	$username = $_[0];
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setTotalStorage
# Objective				: Save total storage space of the current logged in user to $totalStorage
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setTotalStorage {
	$totalStorage_Raw_TBE = $_[0];
	$totalStorage = getHumanReadableSizes($_[0]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setStorageUsed
# Objective				: Save storage used space of the current logged in user to $storageUsed
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setStorageUsed {
	$storageUsed_Raw_TBE = $_[0];
	$storageUsed = getHumanReadableSizes($_[0]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setFreeStorage
# Objective				: Required
# Added By				: TBE
#****************************************************************************************************/
sub setFreeStorage {
# Dummy function : calculated value
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setUserConfiguration
# Objective				: Set user configuration values
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub setUserConfiguration {
	my $data;
	if (reftype(\$_[0]) eq 'SCALAR') {
		if (defined($_[1])) {
			$data = [{$_[0] => $_[1]}];
		}
		else {
			$data = [{$_[0] => ''}];
		}
	}
	else {
		$data = [$_[0]];
	}

	my %cgiNames;
	my %evsNames;
	my $keystring;
	my $isNothingFound = 1;
	for my $i (0 .. $#{$data}) {
		for my $key (keys %{$data->[$i]}) {
			$keystring = $key;
			unless (exists $Configuration::userConfigurationSchema{$key}) {
				unless (%cgiNames or %evsNames) {
					for my $rhs (keys %Configuration::userConfigurationSchema) {
						if ($Configuration::userConfigurationSchema{$rhs}{'cgi_name'} ne '') {
							$cgiNames{$Configuration::userConfigurationSchema{$rhs}{'cgi_name'}} = $rhs;
						}
						if ($Configuration::userConfigurationSchema{$rhs}{'evs_name'} ne '') {
							$evsNames{$Configuration::userConfigurationSchema{$rhs}{'evs_name'}} = $rhs;
						}
					}
				}

				if (exists $cgiNames{$key}) {
					$keystring = $cgiNames{$key};
					$isNothingFound = 0;
				}
				elsif (exists $evsNames{$key}) {
					$keystring = $evsNames{$key};
					$isNothingFound = 0;
				}
				else {
					#traceLog("user_configuration_".$key."_does_not_exists");
					next;
				}
			}

			unless ($userConfiguration{$keystring}{'VALUE'} eq $data->[$i]{$key}) {
				$userConfiguration{$keystring}{'VALUE'} = $data->[$i]{$key};
				$modifiedUserConfig{$keystring}{'VALUE'} = $data->[$i]{$key};
				$isNothingFound = 0 if ($isNothingFound);
			}
		}
	}

	unless ($isNothingFound) {
		$Configuration::isUserConfigModified = 1;
		return 1;
	}

	$Configuration::errorMsg = 'settings_were_not_changed';
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveServerAddress
# Objective				: Save user server address
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveServerAddress {
	my @data = @_;
	if (exists $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}} or
			exists $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'evs_name'}}) {

		my $gsa = getServerAddressFile();
		createDir(getUsersInternalDirPath('user_info')) if (!-d getUsersInternalDirPath('user_info'));

		if (open(my $fh, '>', $gsa)) {
			if (exists $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}}) {
				print $fh $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'cgi_name'}};
			}
			else {
				print $fh $data[0]->{$Configuration::ServerAddressSchema{'SERVERADDRESS'}{'evs_name'}};
			}
			close($fh);
			chmod $Configuration::filePermission, $gsa;
			return 1;
		} else {
			display("$0: close $gsa: $!");
		}
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveServicePath
# Objective				: Save user selected service path in the file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveServicePath {
	my $servicePathFile = ("$appPath/" . $Configuration::serviceLocationFile);
	if (open(my $spf, '>', $servicePathFile)) {
		print $spf $_[0];
		close($spf);
		return 1;
	}
	display(["\n",'failed_to_open_file', " $servicePathFile. Reason: $!"]);
	return 0
}

#*****************************************************************************************************
# Subroutine			: saveUserQuota
# Objective				: Save user quota to quota file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveUserQuota {
	my $csf = getCachedStorageFile();
	my @data = @_;
	if (open(my $fh, '>', $csf)) {
		my $first = 1;
		for my $key (keys %Configuration::accountStorageSchema) {
			# To read response from EVS.
			if (exists $data[0]->{lc($key)}) {
					($first == 0) ? (print $fh "\n") : ($first = 0) ;
					print $fh "$key=".$data[0]->{lc($key)};
			}
			# To read response from CGI.
			elsif (exists
				$data[0]->{$Configuration::accountStorageSchema{$key}{'cgi_name'}}) {
					($first == 0) ? (print $fh "\n") : ($first = 0) ;
					print $fh "$key=".$data[0]->{$Configuration::accountStorageSchema{$key}{'cgi_name'}};
			}
			elsif (exists
				$data[0]->{$Configuration::accountStorageSchema{$key}{'evs_name'}}) {
				($first == 0) ? (print $fh "\n") : ($first = 0) ;
				print $fh "$key=".$data[0]->{$Configuration::accountStorageSchema{$key}{'evs_name'}};
			}
		}
		close($fh);
		chmod 0777, $csf;
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveUserConfiguration
# Objective				: Save user selected configurations to a file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub saveUserConfiguration {
	return 1 unless ($Configuration::isUserConfigModified);
	loadUserConfiguration();
	foreach (keys %modifiedUserConfig) {
		next if ($_ !~ m/PROXY/ && $modifiedUserConfig{$_}{'VALUE'} eq '');
		$userConfiguration{$_}{'VALUE'} = $modifiedUserConfig{$_}{'VALUE'};
	}

	%modifiedUserConfig = ();
	$Configuration::isUserConfigModified = 0;

	my $ucf = getUserConfigurationFile();
	unless (defined($_[1]) and $_[1]) {
		return 0 if (validateUserConfigurations() != 1);
	}
	if (open(my $fh, '>', $ucf)) {
		print $fh encryptString(JSON::to_json(\%userConfiguration));
		close($fh);
		unless (defined($_[0]) and $_[0] == 0) {
			loadNotifications() and setNotification('get_user_settings') and saveNotifications();
		}
		createUpdateBWFile();

		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: setRestoreLocation
# Objective				: Set restore location for the current user
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar[26/04/2018]
#****************************************************************************************************/
sub setRestoreLocation {
	display(["\n", 'enter_your_restore_location_optional', ": "], 0);
	my $restoreLocation = getUserChoice();
	my $defaultRestoreLocation = getUsersInternalDirPath('restore_data');
	$restoreLocation =~ s/^~/getUserHomePath()/g;
	if ($restoreLocation eq '') {
		$restoreLocation = getUsersInternalDirPath('restore_data');
		display(['considering_default_restore_location', "\"$defaultRestoreLocation\"."]);
		$restoreLocation = $defaultRestoreLocation;
	}
	else {
		if (!-d $restoreLocation){
			display(['invalid_restore_location', "\"$restoreLocation\". ", "Reason: ", 'no_such_directory']);
			display(['considering_default_restore_location', "\"$defaultRestoreLocation\"."]);
			$restoreLocation = $defaultRestoreLocation;
		}
		elsif (!-w $restoreLocation){
			display(['cannot_open_directory', ": ", "\"$restoreLocation\" ", " Reason: ", 'permission_denied']);
			display(['considering_default_restore_location', "\"$defaultRestoreLocation\"."]);
			$restoreLocation = $defaultRestoreLocation;
		} else{
			display(["Restore Location ",  "\"$restoreLocation\" ", "exists."], 1);
		}
		$restoreLocation = getAbsPath($restoreLocation) or retreat('no_such_directory_try_again');

	}

	display(['your_restore_location_is_set_to', " \"$restoreLocation\"."],1);
	setUserConfiguration('RESTORELOCATION', $restoreLocation);
	saveUserConfiguration() if (defined($_[0]));
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setRestoreFromLocation
# Objective				: This subroutine will set value to restore from location based on the required checks.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub setRestoreFromLocation {
	my $rfl = getUserConfiguration('BACKUPLOCATION');
	my $removeDeviceID = (split('#', $rfl))[-1];
	display(["\n",'your_restore_from_device_is_set_to',(" \"" . $removeDeviceID . "\". "),'do_u_want_to_edit'],1);
	my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);
	if ($choice eq "y") {

		if (getUserConfiguration('DEDUP') eq 'on') {
			display(["\n",'loading_your_account_details_please_wait',"\n"],1);

			my @devices = fetchAllDevices();
			if ($devices[0]{'STATUS'} eq Configuration::FAILURE) {
				if ($devices[0]{'MSG'} =~ 'No devices found') {
					retreat('failed');
				}
			}
			elsif ($devices[0]{'STATUS'} eq Configuration::SUCCESS) {
				linkBucket('restore', \@devices) or retreat("Please try again.");
				return 1;
			}
		}
		else {
			display(['enter_your_restore_from_location_optional', ": "], 0);
			my $bucketName = getUserChoice();
			if ($bucketName ne ""){
				display(['Setting up your restore from location...'], 1);
				if (substr($bucketName, 0, 1) ne "/") {
					$bucketName = "/".$bucketName;
				}

				if (open(my $fh, '>', getValidateRestoreFromFile())) {
					print $fh $bucketName;
					close($fh);
					chmod 0777, getValidateRestoreFromFile();
				}
				else
				{
					traceLog("failed to create file. Reason: $!\n");
					return 0;
				}
				my $evsErrorFile      = getUserProfilePath().'/'.$Configuration::evsErrorFile;
				createUTF8File('ITEMSTATUS',getValidateRestoreFromFile(), $evsErrorFile) or retreat('failed_to_create_utf8_file');
				my @result = runEVS('item');
				if ($result[0]{'status'} =~ /No such file or directory|directory exists in trash/) {
					display(["Invalid Restore From Location. Reason: Path does not exist."], 1);
					display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\".")],1);
					display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\".")],1);
				}
				else
				{
					$rfl = $bucketName;
					display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\".")],1);
				}

				unlink(getValidateRestoreFromFile());
			}
			else
			{
				display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\".")],1);
				display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\".")],1);
			}
			setUserConfiguration('RESTOREFROM', $rfl);
		}
	}
	else {
		my $removeDeviceID = (split('#', $rfl))[-1];
		setUserConfiguration('RESTOREFROM', $rfl);
		display(['your_restore_from_device_is_set_to',(" \"" . $removeDeviceID . "\".")],1);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setBackupToLocation
# Objective				: Set backup to location for the current user
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar[26/04/2018]
#****************************************************************************************************/
sub setBackupToLocation {
	if (getUserConfiguration('DEDUP') eq 'on') {

		my @devices = fetchAllDevices();

		if ($devices[0]{'STATUS'} eq Configuration::FAILURE) {
			if ($devices[0]{'MSG'} =~ 'No devices found') {
				return createBucket();
			} else{
				display($devices[0]{'MSG'},1);
			}
		}
		elsif ($devices[0]{'STATUS'} eq Configuration::SUCCESS) {
			findMyDevice(\@devices) or askToCreateOrSelectADevice(\@devices) or retreat('failed');

			return 1;
		}
	}
	elsif (getUserConfiguration('DEDUP') eq 'off') {
		#my $backupLoc = validateBackupLoction();
		my $backupLoc = getAndValidate(["\n", 'enter_your_ndedup_backup_location_optional',": "], "backup_location", 1);
		if ($backupLoc eq '') {
			$backupLoc = $Configuration::hostname;
			$backupLoc =~ s/[^a-zA-Z0-9_-]//g;
		}

		display('setting_up_your_backup_location',1);
		unless ($backupLoc) {
			$backupLoc = $Configuration::hostname;
			$backupLoc =~ s/[^a-zA-Z0-9_-]//g;
			$backupLoc = "/".$backupLoc;
		}
		createUTF8File('CREATEDIR', $backupLoc) or
			retreat('failed_to_create_utf8_file');
		my @responseData = runEVS('item');
		if ($responseData[0]->{'STATUS'} eq Configuration::SUCCESS or ($responseData[0]->{'STATUS'} eq Configuration::FAILURE and $responseData[0]->{'MSG'} =~ /file or folder exists/)){
			setUserConfiguration('BACKUPLOCATION', $backupLoc);
			display(['your_backup_to_device_name_is',(" \"" . $backupLoc . "\".")]);
			loadNotifications() and setNotification('register_dashboard') and saveNotifications();
			return 1;
		}
	}
	else {
		retreat('Unable_to_find_account_type_dedup_or_no_dedup');
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: setNotification
# Objective				: set notification value to notifications
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setNotification {
	if (not exists $notifications{$_[0]} and exists $Configuration::notificationsSchema{$_[0]}) {
		$notifications{$_[0]} = $Configuration::notificationsSchema{$_[0]};
	}

	if (exists $notifications{$_[0]}) {
		if (defined($_[1])) {
			$notifications{$_[0]} = $_[1];
		}
		else {
			my $randomChars = '';
			$randomChars .= sprintf("%x", rand 16) for 1..9;
			$notifications{$_[0]} = $randomChars;
		}
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveNotifications
# Objective				: save notification values to a file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveNotifications {
	my $nf = getNotificationFile();

	if (open(my $fh, '>', $nf)) {
		print $fh JSON::to_json(\%notifications);
		close($fh);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: setCrontab
# Objective				: set crontab value to crontab
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub setCrontab {
	my $jobType = shift  || retreat('crontabs_jobname_is_required');
	my $jobName = shift  || retreat('crontab_title_is_required');
	my $key     = shift;
	my $value   = shift;

	$jobType = $Configuration::availableJobsSchema{$jobType}{'type'} if (exists $Configuration::availableJobsSchema{$jobType});
	$jobType = 'backup' if ($jobType eq 'express_backup'); # TODO: IMPORTANT to review this statement again.

	unless (exists $crontab{$Configuration::mcUser} and exists $crontab{$Configuration::mcUser}{$username}
		and exists $crontab{$Configuration::mcUser}{$username}{$jobType}
		and exists $crontab{$Configuration::mcUser}{$username}{$jobType}{$jobName}) {
		#$crontab{$jobType}{$jobName} = \%Configuration::crontabSchema;
		return 0;
	}

	if (ref($key) eq 'HASH') {
		%crontab = %{deepCopyEntry(\%crontab, {$Configuration::mcUser => {$username => {$jobType => {$jobName => $key}}}})};
	}
	else {
		if ($key eq 'h' && $value ne '*'){ $value = ($value > 23)?23:$value; }
		if ($key eq 'm' && $value ne '*'){ $value = ($value > 59)?59:$value; }
		%crontab = %{deepCopyEntry(\%crontab, {$Configuration::mcUser => {$username => {$jobType => {$jobName => {$key => $value}}}}})};
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: saveCrontab
# Objective				: save crontab values to a file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub saveCrontab {
	my $nf = getCrontabFile();
	if (open(my $fh, '>', $nf)) {
		print $fh encryptString(JSON::to_json(\%crontab));
		close($fh);
		chmod($Configuration::filePermission, $nf);
		loadNotifications() and setNotification('get_scheduler') and saveNotifications() unless (defined($_[0]) and ($_[0] == 0));
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: selectLogsBetween
# Objective				: select logs files between given two dates
# Added By				: Yogesh Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub selectLogsBetween {
	return Taryck::selectLogsBetween(@_);
	my %logStat = ();
	my %logFilenames = ();

	unless (defined($_[1]) and defined($_[2])) {
		retreat('start_and_end_dates_are_required');
	}

	#Added for Dashboard
	if (!defined($_[0]) and defined($_[3])){
		my $jobDir = (fileparse($_[3]))[0];
		if ($jobDir =~ m/\/LOGS\//){
			$jobDir =~ s/LOGS\///;
		}
		getLogsList($jobDir);
	}

	if (defined($_[3])) {
		my @t1 = localtime($_[1]);
		$t1[5] += 1900;
		$t1[4] += 1;
		my @t2 = localtime($_[2]);
		$t2[5] += 1900;
		$t2[4] += 1;

		my $tempLogFile;
		my $logInStrings = '';
		my $mon;
		my $pmon;
		for(my $y=$t1[5]; $y <= $t2[5]; $y++) {
			$mon = ($y == $t2[5])? $t2[4] : 12;
			$pmon = ($t1[4] > $mon)? $mon : $t1[4];

			for(my $m=$pmon; $m <= $mon; $m++) {
				$tempLogFile = sprintf("$_[3]", $m, $y);
				if (-f $tempLogFile) {
					$logInStrings .= getFileContents($tempLogFile);
				}
			}
		}

		if ($logInStrings ne '') {
			$logInStrings .= '}';
			substr($logInStrings, 0, 1, '{');
		}
		else {
			$logInStrings .= '{}';
		}
		%logFilenames = %logStat = %{JSON::from_json($logInStrings)};
	}

	if (defined($_[0]) and ref($_[0]) eq 'HASH') {
		%logFilenames = %{$_[0]};
	}

	my $lf = tie(my %logFiles, 'Tie::IxHash');
	my $logsFound = 0;
	foreach(sort {$b <=> $a} keys %logFilenames) {
		if ((($_[1] <= $_) && ($_[2] >= $_))) {
			$logsFound = 1;
			if (exists $logStat{$_}) {
				$logFiles{$_} = $logStat{$_};
			}
			else {
				$logFiles{$_} = {
					'status' => $logFilenames{$_},
					'datetime' => strftime("%d/%m/%Y %H:%M:%S", localtime($_))
				};
			}
		}
		elsif ($logsFound) {
			last;
		}
	}

	return $lf;
}

#*****************************************************************************************************
# Subroutine			: stopDashboardService
# Objective				: Stop a dashboard service for the given username
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub stopDashboardService {
	my ($mcUser, $scpath) = ($_[0], $_[1]);

	# if any of the value is not defined, return
	return 0 unless (defined($mcUser) && defined($scpath));

	# construct service file path to this user
	my $servicefile = getCatfile($scpath, $Configuration::serviceLocationFile);
	# if service path file not present, go back
	return 0 unless (-f $servicefile and !-z $servicefile);

	my $svfc = getFileContents($servicefile);
	Chomp(\$svfc);

	my $dashboardPID = getCatfile($svfc, $Configuration::userProfilePath, $mcUser, $Configuration::dashboardpid);
	return 0 unless (-f $dashboardPID and !-z $dashboardPID);

	my $dashpid = getFileContents($dashboardPID);
	Chomp(\$dashpid);
	system("kill $dashpid 2>/dev/null");

	#sleep(1);
	Helpers::sleepForMilliSec(250); # Sleep for 250 milliseconds
}

#*****************************************************************************************************
# Subroutine			: skipChildIfParentDirExists
# Objective				: Skip child items if parent directory present & return
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub skipChildIfParentDirExists{
	my %list = %{$_[0]};
	foreach my $item (sort(keys %list)) {
		foreach my $newItem (sort(keys %list)){
			if($list{$newItem}{'type'} eq 'f' ){
				next;
			}
			my $tempNewItem = quotemeta($newItem);
			if ($item ne $newItem && $item =~ m/^$tempNewItem/){
				display(["Skipped [$item]. ", "Reason",'parent_directory_present']);
				delete $list{$item};
				$skippedItem = 1;
				last;
			}
		}
	}
	return %list;
}

#*****************************************************************************************************
# Subroutine			: sendFailiourNotice
# Objective				: send the failure
# Added By				: Vijay Vinoth
#****************************************************************************************************/
sub sendFailureNotice{
	if (loadAppPath() and loadServicePath() and
		loadUsername($_[0]) and loadNotifications()) {
		my $currentTime = time();
		setNotification($_[1], $currentTime.'_'.Configuration::JOBEXITCODE->{'FAILURE'}."_".$_[2]);
		saveNotifications();
	}
}

#*****************************************************************************************************
# Subroutine			: sleepForMilliSec
# Objective				: Sleep for given milliseconds; Input should be integer
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub sleepForMilliSec {
	my $sleepTime = $_[0];
	$sleepTime = 1 if($sleepTime < 1);
	$sleepTime = ($sleepTime/1000);
	select(undef, undef, undef, $sleepTime);
}

#------------------------------------------------- T -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: trimDeviceInfo
# Objective				: This function will remove over-length characters and replace with the [...] at the end of the string to restrict data overflow.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub trimDeviceInfo{
	my ($data,$dataLength) = @_;
	my $displayLen = $dataLength - 3;
	if (length($data) > $displayLen){
		$data = substr($data,0,($displayLen-4)).'[..]';
	}
	return $data;
}

#*****************************************************************************************************
# Subroutine			: trim
# Objective				: This function will remove white spaces from both side of a string
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub trim {
	$_[0] =~ s/^\s+|\s+$//g; # Replace original string itself
	return 1;
}

#*********************************************************************************************************
# Subroutine			: trimData
# Objective             : This function will display the available list of devices with given account on the screen.
# Added By              : Abhishek Verma
#*********************************************************************************************************/
sub trimData {
	my ($data, $dataLength) = @_;
	my $displayLen = $dataLength - 3;
	if (length($data) > $displayLen) {
		$data = substr($data, 0, ($displayLen - 4)) . '[..]';
	}

	return $data;
}

#*****************************************************************************************************
# Subroutine      : traceLog
# Objective       : Trace log method
# Added By        : Sabin Cheruvattil
# Modified By     : Yogesh Kumar, Vijay Vinoth, Senthil Pandian
#****************************************************************************************************/
sub traceLog {
	my $message = ($_[0])? $_[0] : '';
	my $msg = "";
	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}

	for my $i (0 .. $#{$message}) {
		if (exists $LS{$message->[$i]}) {
			$msg .= $LS{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}
	my $trace = $msg;

	my ($package, $filename, $line) = (defined $_[1] && defined $_[2])?("",$_[1],$_[2]):caller;
	my $traceLog = getTraceLogPath();
	my $traceDir = dirname($traceLog);

	if (!-d $traceDir) {
		#my $mkRes = `mkdir -p '$traceDir' 2>&1`;
		#chomp($mkRes);
		#if ($mkRes ne '' and $mkRes !~ /Permission denied/) {
		my $mkRes = createDir($traceDir,1);
		unless($mkRes){
			changeMode(getServicePath());
		}
	}

	if (-e $traceLog && -s $traceLog >= $Configuration::maxLogSize) {
		my $tempTrace = qq('$traceLog) . qq(_) . localtime() . qq(');
		`mv '$traceLog' $tempTrace`;
	}

	if (!-e $traceLog) {
		writeToTrace($traceLog, qq($Configuration::appType ) . ucfirst($LS{'username'}) . qq(: ) .
					(getUsername() or ucfirst($LS{'no_logged_in_user'})) . qq( \n));
		chmod $Configuration::filePermission, $traceLog;
	}

	my @files        = glob($traceLog . qq(_*));
	my $remFileCount = scalar(@files) - 5;
	while($remFileCount > 0) {
		unlink pop(@files);
		$remFileCount--;
	}

	chomp($trace);
	my $logContent 		= qq([) . basename($filename) . qq(][Line: $line] $trace\n);
	writeToTrace($traceLog, $logContent);
}

#******************************************************************************
# Subroutine Name         : terminateStatusRetrievalScript
# Objective               : terminates the Status Retrieval script in case it is running
# Added By                :
# Modified By             : Senthil Pandian
#******************************************************************************
sub terminateStatusRetrievalScript
{
	my $psOption		 = getPSoption();
	my $statusScriptName = $Configuration::idriveScripts{'status_retrieval_script'};
	my $statusScriptCmd  = "ps $psOption | grep $statusScriptName | grep -v grep";

	my $statusScriptRunning = `$statusScriptCmd`;
	if ($statusScriptRunning ne "") {
		my @processValues = split /[\s\t]+/, $statusScriptRunning;
		my $pid = $processValues[3];
		   $pid = (split /[\s\t]+/, $statusScriptRunning)[3];
#		`kill -s SIGTERM $pid`;
	}
#	unlink($_[0]);
}

#------------------------------------------------- U -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: uniqueData
# Objective				: This will return unique data from given array.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub uniqueData{
	my %uniqueData = map{ $_ => 1 } @_;
	return sort {$a cmp $b} keys %uniqueData;
}

#*****************************************************************************************************
# Subroutine			: unzip
# Objective				: Read zip files and unzip the package
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub unzip {
	my $filename = shift;
	my $exDir    = shift;

	unless (defined($filename)) {
		display('ziped_filename_cannot_be_empty');
		return 0;
	}

	unless (defined($exDir)) {
		$exDir = "$servicePath/$Configuration::downloadsPath";
		createDir($exDir) or (display(["$exDir ", 'does_not_exists']) and return 0);
	}

	#print "Unziping the package... \n";
	my $output = `unzip -o '$filename' -d '$exDir'`;

	if ($? > 0) {
			traceLog($?);
			return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: updateDirSizes
# Objective				: Update directory sizes for sending back to dashboard
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub updateDirSizes {
	my $backupsetsizes = $_[0];
	my $notifsizes = $_[1];
	my $processeditemcount = $_[2];

	my $curtime = mktime(localtime);
	foreach my $key (keys %{$notifsizes}) {
		# if (defined($notifsizes->{$key}) && reftype(\$notifsizes->{$key}{'size'}) eq 'SCALAR' && $notifsizes->{$key}{'size'} == -1 &&
		# defined($backupsetsizes->{$key}) && ($curtime - $backupsetsizes->{$key}{'ts'}) <= $Configuration::sfmaxcachets)
		if (defined($notifsizes->{$key}) && reftype(\$notifsizes->{$key}{'size'}) eq 'SCALAR' && $notifsizes->{$key}{'size'} == -1 &&
		defined($backupsetsizes->{$key})) {
			$notifsizes->{$key} = $backupsetsizes->{$key};
			$processeditemcount++;
		}
	}

	return $processeditemcount;
}

#*****************************************************************************************************
# Subroutine			: updateUserDetail
# Objective				: This subroutine will update newly configured user details to MySQL table in our servers.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub updateUserDetail {
	my $device_name = $Configuration::hostname;
	chomp($device_name);

	my $os = $Configuration::appType."ForLinux";
	my $encodedOS    = $os;
	my $currentVersion = $Configuration::version;
	chomp($currentVersion);

	my $uniqueID 	 = getMachineUID() or retreat('unable_to_find_mac_address');
	my $encodedUname = $_[0];
	my $encodedPwod  = $_[1];
	my $enabled 	 = $_[2];

	my %params = (
		'host' => $Configuration::IDriveUserInoCGI,
		'method'=> 'POST',
		'data' => {
			'username'    => $encodedUname,
			'password'    => $encodedPwod,
			'device_name' => $device_name,
			'device_id'   => $uniqueID,
			'enabled'     => $enabled,
			'os' 		  => $encodedOS,
			'version'     => $currentVersion
		}
	);

	#my $res = request(\%params);
	my $res = requestViaUtility(\%params);
	if ($res){
		if ($res->{DATA} =~ /Error:/){
			traceLog("Failed to update user detail: ".$res->{DATA}."\n") if ($enabled ==1);
			return 0;
		}
		return 1 if ($res->{DATA} =~ /success/i);
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: urlEncode
# Objective				: Helps to encode url
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub urlEncode {
	my $rv = shift;
	$rv =~ s/([^a-z\d\Q.-_~ \E])/sprintf("%%%2.2X", ord($1))/geix;
	$rv =~ tr/ /+/;
	return $rv;
}

#*****************************************************************************************************
# Subroutine			: urlDecode
# Objective				: Helps to decode url
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub urlDecode {
	my $rv = shift;
	$rv =~ tr/+/ /;
	$rv =~ s/\%([a-f\d]{2})/ pack 'C', hex $1 /geix;
	return $rv;
}

#*****************************************************************************************************
# Subroutine			: uploadLog
# Objective				: Upload logs for backup, restore & archive
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar
#****************************************************************************************************/
sub uploadLog {
	my $l = eval {
		require Idrivelib;
		Idrivelib->import();
		1;
	};
	my $jobPath = (fileparse($_[0]))[1];
	$jobPath = getCatfile($jobPath, '..', 'tmp');
	if (createDir($jobPath)) {
		my $tempFile = getCatfile($jobPath, 'file.txt');
		my $outFile = getCatfile($jobPath, 'output.txt');
		my $errFile = getCatfile($jobPath, 'errfile.txt');
		if (fileWrite($tempFile, $_[0])) {
			my $utf8File = getCatfile($jobPath, $Configuration::utf8File);
			if (createUTF8File(['LOGBACKUP', $utf8File], $tempFile, ($jobPath."/"), $outFile, $errFile)) {
				Idrivelib::update_log_file($utf8File);
				runEVS('', undef, undef, undef);
				removeItems($jobPath);
				return 1;
			}
		}
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: uploadMigratedLog
# Objective				: Upload migrated logs for backup, express backup, restore & archive
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub uploadMigratedLog {
	my $l = eval {
		require Idrivelib;
		Idrivelib->import();
		1;
	};

	my $userProfilePath = "$servicePath/$Configuration::userProfilePath/";
	my $tempFile 		= getCatfile($userProfilePath, $Configuration::migratedLogFileList);

	if (-e $tempFile and !-z $tempFile){
		my $tempjobPath = getCatfile($userProfilePath,'tmp');
		if (createDir($tempjobPath)) {
			my $outFile = getCatfile($tempjobPath, 'output.txt');
			my $errFile = getCatfile($tempjobPath, 'errfile.txt');
			my $utf8File = getCatfile($tempjobPath, $Configuration::utf8File);
			if (createUTF8File(['LOGBACKUP', $utf8File], $tempFile, ($tempjobPath."/"), $outFile, $errFile)) {
				Idrivelib::update_log_file($utf8File);
				runEVS('', undef, undef, undef);
				removeItems([$tempjobPath,$tempFile]);
				return 1;
			}
		}
	}
	return 0;
}

#*******************************************************************************************************
# Subroutine Name         :	updateServerAddr
# Objective               :	handling wrong server address error msg
# Added By                : Senthil Pandian
#********************************************************************************************************
sub updateServerAddr {
	my $idevsErrorFile  = $Configuration::jobRunningDir.'/'.$Configuration::evsErrorFile;
	if (-e $idevsErrorFile and -s $idevsErrorFile > 0) {
		my $errorPatternServerAddr = "unauthorized user";
		open EVSERROR, "<", $idevsErrorFile or traceLog("\n Failed to open error.txt\n", __FILE__, __LINE__);
		my $errorContent = <EVSERROR>;
		close EVSERROR;

		if ($errorContent =~ m/$errorPatternServerAddr/){
			my $serverAddress = getServerAddress();
			if ($serverAddress == ''){
				#exit_cleanup($Configuration::errStr);
				return 0;
			}
			return 1;
		}
	}
	return 1;
}

#*******************************************************************************************************
# Subroutine Name         :	updateRetryCount
# Objective               :	updates retry count based on recent backup files.
# Added By                : Avinash
# Modified By             : Dhritikana
#********************************************************************************************************/
sub updateRetryCount()
{
	my $curFailedCount = 0;
	my $currentTime = time();
	my $statusFilePath  = $Configuration::jobRunningDir."/".$Configuration::statusFile;

	for(my $i=1; $i<= $Configuration::totalEngineBackup; $i++){
		if (-e $statusFilePath."_".$i  and  -s $statusFilePath."_".$i>0){
			$curFailedCount = $curFailedCount+getParameterValueFromStatusFile('ERROR_COUNT_FILES',$i);
			undef @Configuration::linesStatusFile;
		}
	}

	if ($curFailedCount < $prevFailedCount) {
		$Configuration::retryCount = 0;
	}
	else {
		if ($currentTime-$Configuration::prevTime < 120) {
			sleep 300;
		}
		$Configuration::retryCount++;
	}

	#assign the latest backedup and synced value to prev.
	$prevFailedCount = $curFailedCount;
	$Configuration::prevTime = $currentTime;
}

#*******************************************************************************************************
# Subroutine Name         :	updateCronForOldAndNewUsers
# Objective               :	Update cron details accordingly for old and new users at the time of account switching.
# Added By                : Anil kumar, Yogesh Kumar, Senthil Pandian
#********************************************************************************************************/
sub updateCronForOldAndNewUsers {
	# update previous user status to logged out
	setUsername($_[0]);

	if (isLoggedin()) {
		loadCrontab();
		#createCrontab('otherInfo', {'settings' => {'status' => 'INACTIVE'}});
		createCrontab('otherInfo', {'settings' => {'status' => 'INACTIVE', 'lastActivityTime' => time()}});
		setCrontab('otherInfo', 'settings', {'status' => 'INACTIVE'}, ' ');
		saveCrontab();

		my $cmd = sprintf("%s %s 1 0", $Configuration::perlBin, getScript('logout', 1));
		`$cmd`;
		Helpers::display(["\"$_[0]\"", ' ', 'is_logged_out_successfully']);
	}

	#set back the user name to new user
	setUsername($_[1]);

	return 0;
}

#*******************************************************************************************************
# Subroutine Name         :	updateCronTabToDefaultVal
# Objective               :	updates default values to crontab after immediate backup job has been completed
# Added By                : Anil kumar
#********************************************************************************************************/
sub updateCronTabToDefaultVal {
	my $jobType = $_[0];
	my $jobName = "";
	if ($jobType eq "backup") {
		$jobName = "default_backupset";
	} else {
		$jobName = "local_backupset";
	}
	loadCrontab();
	setCrontab($jobType, $jobName, {'settings' => {'frequency' => 'daily'}});
	setCrontab($jobType, $jobName, {'settings' => {'status' => 'disabled'}});
	setCrontab($jobType, $jobName, 'h', sprintf("%02d", 00));
	setCrontab($jobType, $jobName, 'm', sprintf("%02d", 00));
	setCrontab('cancel', $jobName, {'settings' => {'frequency' => 'daily'}});
	setCrontab('cancel', $jobName, {'settings' => {'status' => 'disabled'}});
	setCrontab('cancel', $jobName, 'h', sprintf("%02d", 00));
	setCrontab('cancel', $jobName, 'm', sprintf("%02d", 00));
	saveCrontab();
}


#*****************************************************************************************************
# Subroutine			: updateExcludeFileset
# Objective				:
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub updateExcludeFileset {
	my %ec = ();
	if (-f "$_[0].info") {
		my $excludeContent = getFileContents("$_[0].info");
		%ec = split("\n", $excludeContent);
	}

	if (open(my $filesetContentInfo, '>', ("$_[0].info")) and open(my $filesetContent, '<', $_[0])) {
		while(my $filename = <$filesetContent>) {
			chomp($filename);
			trim($filename);
			if (exists $ec{$filename}) {
				print $filesetContentInfo "$filename\n";
				print $filesetContentInfo "$ec{$filename}\n";
			}
			elsif ($filename ne '') {
				print $filesetContentInfo "$filename\n";
				print $filesetContentInfo "enabled\n";
			}
		}
		close($filesetContentInfo);
		close($filesetContent);

		loadNotifications() and setNotification('get_settings') and saveNotifications();
		removeBKPSetSizeCache('backup');
		removeBKPSetSizeCache('localbackup');
	}
}

#*****************************************************************************************************
# Subroutine			: updateJobsFileset
# Objective				: update *.info file, which contains more details of a file(ex: file/folder/undefined)
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub updateJobsFileset {
	if (open(my $filesetContentInfo, '>', ("$_[0].info")) and open(my $filesetContent, '<', $_[0])) {
		my @newItemArray = ();
		while(my $ori_filename = <$filesetContent>) {
			chomp($ori_filename);
			my $filename = Taryck::extendBackupItem($ori_filename);
			if (-f $filename) {
				print $filesetContentInfo "$ori_filename\n";
				print $filesetContentInfo "f\n";
				push @newItemArray, $filename;
			}
			elsif (-d $filename) {
				$ori_filename .= (substr($ori_filename,-1) ne '/')?'/':'';
				print $filesetContentInfo "$ori_filename\n";
				print $filesetContentInfo "d\n";
				push @newItemArray, $ori_filename;
			}
			else {
				display(["Skipped [$ori_filename]. ", "Reason",'file_folder_not_found']);
				next;
				#print $filesetContentInfo "$filename\n";
				#print $filesetContentInfo "u\n";
			}
		}
		close($filesetContentInfo);
		close($filesetContent);
		my $content = '';
		$content = join("\n", @newItemArray) if (scalar(@newItemArray));
		fileWrite($_[0],$content);
		loadNotifications() and setNotification("get_$_[1]set_content") and saveNotifications();
	}
}

#*****************************************************************************************************
# Subroutine			: unloadUserConfigurations
# Objective				: This subroutine empties user configurations
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub unloadUserConfigurations {
	%userConfiguration = ();
	%modifiedUserConfig = ();
}

#------------------------------------------------- V -------------------------------------------------#
#********************************************************************************
# Subroutine			: validateBackupRestoreSetFile
# Objective				: Validating Backupset/RestoreSet file
# Added By				: Senthil Pandian
#********************************************************************************
sub validateBackupRestoreSetFile {
	unless(defined($_[0])){
		retreat('filename_is_required');
	}
	my $errStr = '';
	my $filePath = getJobsPath(lc($_[0]),'file');
	my $status = Configuration::SUCCESS;

	if ((!-e $filePath) or (!-s $filePath)) {
		$errStr = "\n".$LS{'your_'.lc($_[0]).'set_is_empty'};
	}
	elsif (-s $filePath > 0 && -s $filePath <= 50){
		my $outfh;
		if (!open($outfh, "< $filePath")) {
			$errStr = $LS{'failed_to_open_file'}.":$filePath, Reason:$!";
		}
		else{
			my $buffer = <$outfh>;
			close($outfh);

			Chomp(\$buffer);
			if ($buffer eq ''){
				$errStr = "\n".$LS{'your_'.lc($_[0]).'set_is_empty'};
			}
		}
	}

	$status = Configuration::FAILURE	if ($errStr ne '');
	return ($status,$errStr);
}

#*****************************************************************************************************
# Subroutine			: validateChoiceOptions
# Objective				: This subroutine validates choice options y/n
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateChoiceOptions {
	my $choice = shift;
	if (lc($choice) eq 'y' || lc($choice) eq 'n') {
		return 1;
	}
	return 0;
}

#*********************************************************************************************************
# Subroutine			: validateDir
# Objective				: This function will check if the diretory exists, its writable. Returns 0 for true and 1 for false.
# Added By				: Abhishek Verma.
#*********************************************************************************************************/
sub validateDir {
	return (-d $_[0] && -w $_[0])? 1 : 0;
}
#*****************************************************************************************************
# Subroutine			: validateMenuChoice
# Objective				: This subroutine validates the log menu choice
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateMenuChoice {
	my ($choice, $lowerRange, $maxRange) = (shift, shift, shift);
	# validate for digits
	return 0 if ($choice !~ m/^[0-9]{1,3}$/);
	return 1 if ($choice >= $lowerRange && $maxRange >= $choice);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateUserConfigurations
# Objective				: Validate user provided values
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Vijay Vinoth
#****************************************************************************************************/
sub validateUserConfigurations {
	my @filedsToVerify = ();
	my $verifyAll = 1;
	if (defined($_[0])){
		@filedsToVerify = @{$_[0]};
		$verifyAll = 0;
	}
	for my $key (keys %Configuration::userConfigurationSchema) {
		if ($verifyAll == 0){
			unless(grep { $_ eq $key} @filedsToVerify){
				next;
			}
		}

		unless (exists $userConfiguration{$key}) {
			traceLog($key." is missing." );
			my $errCode = $Configuration::userConfigurationSchema{$key}{'required'};
			$errCode = 102 if (!Helpers::isLoggedin() and $errCode == 100);
			return $errCode;
		}
		if ($Configuration::userConfigurationSchema{$key}{'required'} and
			($userConfiguration{$key}{'VALUE'} eq '')) {
			traceLog($key." value is missing." );
			my $errCode = $Configuration::userConfigurationSchema{$key}{'required'};
			$errCode = 102 if (!Helpers::isLoggedin() and $errCode == 100);
			return $errCode;
		}
		if (($Configuration::userConfigurationSchema{$key}{'type'} eq 'dir') and
			($userConfiguration{$key}{'VALUE'} ne '') and (!-d $userConfiguration{$key}{'VALUE'})) {
			traceLog($key." is misssing." );
			return 101;
		}
		if (($Configuration::userConfigurationSchema{$key}{'type'} eq 'regex') and
			exists ($Configuration::userConfigurationSchema{$key}{'regex'}) and ($userConfiguration{$key}{'VALUE'} ne '')){
			if ($userConfiguration{$key}{'VALUE'} !~ m/$Configuration::userConfigurationSchema{$key}{'regex'}/){
				traceLog("Invalid $key value: ".$userConfiguration{$key}{'VALUE'});
				$userConfiguration{$key}{'VALUE'} = $Configuration::userConfigurationSchema{$key}{'default'};
				#return $Configuration::userConfigurationSchema{$key}{'required'};
			}
		}

		if (!defined($userConfiguration{$key}{'VALUE'})){
			$userConfiguration{$key}{'VALUE'} = $Configuration::userConfigurationSchema{$key}{'default'};
			#$modifiedUserConfig{$key}{'VALUE'} = $Configuration::userConfigurationSchema{$key}{'default'};
			$Configuration::isUserConfigModified = 1;
		}
		elsif (($Configuration::userConfigurationSchema{$key}{'default'} ne '') and
			($userConfiguration{$key}{'VALUE'} eq '')) {
			$userConfiguration{$key}{'VALUE'} = $Configuration::userConfigurationSchema{$key}{'default'};
			#$modifiedUserConfig{$key}{'VALUE'} = $Configuration::userConfigurationSchema{$key}{'default'};
			$Configuration::isUserConfigModified = 1;
		}
	}
	# Validating SERVERROOT value if dedup is ON
	if ($userConfiguration{'DEDUP'}{'VALUE'} eq 'on'){
		if ($userConfiguration{'SERVERROOT'}{'VALUE'} eq '') {
			traceLog("SERVERROOT is misssing." );
			return 101;
		}
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: verifyEVSBinary
# Objective				: This is to verify the EVS binary
# Added By				: Anil Kumar
#****************************************************************************************************/
sub verifyEVSBinary {
	my $evs = $_[0];
	unless (-f "$evs") {
		my $test = $LS{'unable_to_find'} . $evs;
		return (0, $test);
	}

	chmod(0777, "$evs");
	unless(-x "$evs") {
		return (0, $LS{'does_not_have_execute_permission'} .$evs);
	}
	$evs = getECatfile($evs);
	my $output = `$evs -h 2>/dev/null`;

	if ($? > 0) {
		return (0, "EVS execution error:".$?);
	}
	return (1, "");
}

#*****************************************************************************************************
# Subroutine			: verifyStaticPerlBinary
# Objective				: This is to verify the static perl binary
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub verifyStaticPerlBinary {
	my $sp = $_[0];
	unless (-f "$sp") {
		my $test = $LS{'unable_to_find'} . $sp;
		return (0, $test);
	}

	chmod(0555, "$sp");
	unless(-x "$sp") {
		return (0, $LS{'does_not_have_execute_permission'} . $sp);
	}

	my $output = `'$sp' -v 2>/dev/null`;

	if ($? > 0) {
		return (0, 'static_perl_execution_error:' . $?);
	}
	return (1, '');
}

#*****************************************************************************************************
# Subroutine			: validateIPaddress
# Objective				: This is to validate IP address
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateIPaddress{
	my $ipAddress = shift;
	unless ($ipAddress =~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/){
		display(['invalid_ip_address',"\n"], 1);
		return 0;
    }
    return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePercentage
# Objective				: This is to validate percentage of files for cleanup
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub validatePercentage {
	my $percentage    = $_[0];
	my $minPercentage = $_[1];
	my $maxPercentage = $_[2];
	if ($percentage !~ m/^[0-9]{1,3}$/ or !($percentage>=$minPercentage and $percentage<=$maxPercentage)) {
		display(['invalid_percentage', "\n"], 1);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePortNumber
# Objective				: This is to validate Port number
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validatePortNumber {
	my $portNumber = shift;
	unless ($portNumber =~ /^(0|[1-9][0-9]{0,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/){
		display(['invalid_port_number', "\n"], 1);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePassword
# Objective				: This subroutine helps to validate password
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validatePassword {
	if ((length($_[0]) < 6) || (length($_[0]) > 20)) {
		display(['password_should_be_at_least_6_20_characters',"\n"],1) ;
		return 0;
	}
	elsif ($_[0] =~ /^(?=.{6,20}$)(?!.*\s+.*)(?!.*[\:\\]+.*)/){
		return 1 ;
	}

}

#*****************************************************************************************************
# Subroutine			: validateDatePattern
# Objective				: This subroutine tests the date and validates the format
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateDatePattern {
	return $_[0] =~ m/^(0[1-9]|1[0-2])\/(0[1-9]|1\d|2\d|3[01])\/(19|20)\d{2}$/;
}

#*****************************************************************************************************
# Subroutine			: validateVersionNumber
# Objective				: This subroutine tests the version number and validates
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateVersionNumber {
	return !($_[0] !~ /^\d+$/ || $_[0] < 1 || $_[0] > $_[1]);
}

#*****************************************************************************************************
# Subroutine			: validateDetails
# Objective				: This subroutine is used to validate the user data as per the fields requested.
# Added By				: Anil Kumar
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub validateDetails {
	my $fieldType = $_[0];
	my $value = $_[1];

	# TODO: review emptying values.
	if ($Configuration::callerEnv eq 'BACKGROUND') {
		$value = $_[1] = '';
	}

	if ($fieldType eq "username"){
		return 0 unless(isValidUserName($value));
	}
	elsif ($fieldType eq "password"){
		return 0 unless(validatePassword($value));
	}
	elsif ($fieldType eq "private_key") {
		return 0 unless(validatePvtKey($value));
	}
	elsif ($fieldType eq "config_private_key") {
		return 0 unless(validateConfPvtKey($value));
	}
	elsif ($fieldType eq "single_email_address") {
		unless(isValidEmailAddress($value)) {
			return 1 if ($value eq "");
			display(['invalid_single_email_address'], 1);
			return 0 ;
		}
	}
	elsif ($fieldType eq "email_address") {
		return 0 unless(getInvalidEmailAddresses($value));
	}
	elsif ($fieldType eq "service_dir") {
		return 0 unless(validateServiceDir($value));
	}
	elsif ($fieldType eq "YN_choice") {
		return $_[1] = 'y' if ($Configuration::callerEnv eq 'BACKGROUND');
		unless(validateChoiceOptions($value)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "contact_no") {
		return 0 unless(validateContactNo($value));
	}
	elsif ($fieldType eq "ticket_no") {
		return 0 unless(validateUserTicket($value));
	}
	elsif ($fieldType eq "ipaddress") {
		return 0 unless(validateIPaddress($value));
	}
	elsif ($fieldType eq "port_no") {
		return 0 unless(validatePortNumber($value));
	}
	elsif ($fieldType eq "percentage_for_cleanup") {
		return 0 unless(validatePercentage($value,1,100));
	}
	elsif ($fieldType eq "bw_value") {
		unless(validateBandWidthValue($value, 1, 100)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "failed_percent") {
		return 0 unless(validatePercentage($value,1,10));
	}
	elsif ($fieldType eq "missed_percent") {
		return 0 unless(validatePercentage($value,0,10));
	}
	elsif ($fieldType eq "backup_location") {
		return 0 unless(validateBackupLoction($value));
	}
	elsif ($fieldType eq '24hours_validator') {
		if (($value !~ /\d/) || (($value =~ /\d/) && ($value < 0 || $value >= 24))) {
			display(['invalid_choice',"\n"], 1);
			return 0;
		}
	}
	elsif ($fieldType eq 'minutes_validator') {
		if (($value !~ /\d/) || (($value =~ /\d/) && ($value < 0 || $value > 59))) {
			display(['invalid_choice',"\n"], 1);
			return 0;
		}
	}
	elsif ($fieldType eq 'week_days_in_number') {
		foreach(split(',', $value)) {
			if (!$_ || ($_ !~ /\d/) || ($_ !~ /^0?[1-7]$/)) {
				display(['invalid_choice', "\n"], 1);
				return 0;
			}
		}
	}
	elsif ($fieldType eq "periodic_cleanup_per") {
		unless(validateMenuChoice($value, 5, 25)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "periodic_cleanup_days") {
		unless(validateMenuChoice($value, 5, 30)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif ($fieldType eq "non_empty") {		# no need to check the condition, but added for a safer purpose
		return 0 if $value eq '';
	}
	else{
		display("invalid_field_type_to_validate");
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateBandWidthValue
# Objective				: This is to validate the band width value
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateBandWidthValue {
	return validateMenuChoice(shift, shift, shift);
}

#*****************************************************************************************************
# Subroutine			: validateBackupLoction
# Objective				: This is to validate and return bucket name
# Added By				: Anil Kumar, Vijay Vinoth
#****************************************************************************************************/
sub validateBackupLoction {
	my $bucketName = $_[0];
	my $dedup = getUserConfiguration('DEDUP');
	if ($bucketName eq '') {
		$bucketName = $Configuration::hostname;
		$bucketName =~ s/[^a-zA-Z0-9_-]//g;
		display(['considering_default_backup_location',"\"$bucketName\""], 1);
		return 1;
	}elsif (length($bucketName) > 65) {
		display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_be_one_to_sixty_five_characters'], 1);
		return 0;
	}elsif ($dedup eq 'on' and $bucketName =~ /^[a-zA-Z0-9_-]*$/) {
		return 1;
	}elsif ($dedup eq 'off') {
		return 1;
	}else {
		display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_contain_only_letters_numbers_space_and_characters', "\n"], 1);
		return 0;
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateServiceDir
# Objective				: This subroutine is used to validate the service directory
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateServiceDir {
	my $dir = $_[0];
	if ($dir eq '') {
		$dir = dirname(getAppPath());
		display(['your_default_service_directory'],1);
	}
	my $oldServiceDir = getServicePath()."/";
	my $checkPath  = substr $dir, -1;
	$dir = $dir ."/" if ($checkPath ne '/');
	my $newServiceDir = $dir.$Configuration::servicePathName."/";
	#print "new: $dir ==== old: $oldServiceDir \n \n ";
	if (!-d $dir) {
		display(["$dir ", 'no_such_directory_try_again',"\n"]);
		return 0;
	}
	elsif (!-w $dir) {
		display(['cannot_open_directory', " $dir ", 'permission_denied',"\n"]);
		return 0;
	}
	elsif (index($dir, $oldServiceDir) != -1) {
		display(["\n",'invalid_location',". ",'Reason','new_service_dir_must_not_be_sub_dir_of_old',"\n"],1);
		return 0;
	}
	elsif ($newServiceDir eq $oldServiceDir) {
		display(["\n",'invalid_location',". ",'Reason','existing_service_directory_is_as_same_as_the_new',"\n"],1);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateContactNo
# Objective				: This subroutine is used to validate contact number
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateContactNo {
	my $reportUserContact = $_[0];
	if ($reportUserContact eq ""){
		return 1 ;
	}
	elsif (length($reportUserContact) < 5 || length($reportUserContact) > 20) {
		display(['invalid_contact_number', '. ', 'contact_number_between_5_20', '.']);
		return 0;
	}
	elsif ($reportUserContact ne '' && ($reportUserContact !~ m/^\d{5,20}$/)) {
		display(['invalid_contact_number', '. ', 'contact_number_only_digits', '.']);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateUserTicket
# Objective				: This subroutine is used to validate ticket number
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateUserTicket {
	my $ticketNo = $_[0];

	if ($ticketNo eq ""){
		return 1;
	}
	elsif (length($ticketNo) < 5 || length($ticketNo) > 30) {
		display(['invalid_ticket_number', '. ', 'ticket_number_between_5_30', '.']);
		return 0;
	}
	elsif ($ticketNo !~ m/^[a-zA-Z0-9]{5,30}$/) {
		display(['invalid_ticket_number', '. ', 'ticket_number_only_alphanumerics', '.']);
		return 0;
	}
	display('');
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePvtKey
# Objective				: This subroutine is used to validate private key pattern
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validatePvtKey {
	my $value = $_[0];
	if (length($value) < 4)
	{
		display(['encryption_key_must_be_minimum_4_characters', '.',"\n"]) ;
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validateConfPvtKey
# Objective				: This subroutine is used to validate private key pattern at the time of config
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateConfPvtKey {
	my $value = $_[0];
	if (length($value) < 6 || length($value) > 250)
	{
		display(['encryption_key_must_be_minimum_6_characters', '.',"\n"]) ;
		return 0;
	}
	elsif ( $value =~ /\s/ ) {
		display(['encryption_key_cannot_contain_blank_space',"\n"]) ;
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: versioncompare
# Objective				: This subroutine is for basic version compare. returns the result of comparsion
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub versioncompare {
	# version == : 0 | first version > : 1 | second version > : 2
	my @vera = split('\.', $_[0]);
	my @verb = split('\.', $_[1]);

	for my $i (0 .. scalar(@vera)) {
		if (defined($vera[$i]) && defined($verb[$i])) {
			return 1 if ($vera[$i] > $verb[$i]);
			return 2 if ($vera[$i] < $verb[$i]);
		}
	}
	
	return 1 if($#vera > $#verb);
	return 2 if($#verb > $#vera);

	return 0;
}

#*****************************************************************************************************
# Subroutine			: verifyEditedFileContent
# Objective				: Verify the edited supported file content
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub verifyEditedFileContent {
	my $filePath = $_[0];
	#my $fileType = $_[1];
	my (@itemArray,@newItemArray) = () x 2;

	if (-e $filePath and !-z $filePath){
		if (!open(FILE_HANDLE, $filePath)) {
			retreat($Locale::strings{'failed_to_open_file'}." : $filePath. Reason :$!");
		}
		@itemArray = <FILE_HANDLE>;
		close(FILE_HANDLE);
		display(['verifying_edited_file_content',"\n"]);
	} elsif(reftype(\$filePath) eq 'REF'){
		@itemArray = @{$_[0]};
	}

	if(scalar(@itemArray) > 0) {
		foreach my $item (@itemArray){
			chomp($item);
			my $orgItem = $item;
			my $item_ext = Taryck::extendBackupItem($item);
#			my $item_ext = $item;
			$item_ext =~ s/[\/]+/\//g; #Replacing multiple "/" with single "/"
			my $tempItem = $item_ext;
			Chomp(\$tempItem);

			if ($tempItem =~ m/^$/) {
				next;
			}
			elsif ($tempItem =~ m/^[\s\t]+$/) {
				next;
			}
			elsif ($tempItem eq "." or $tempItem eq ".." or $tempItem eq "/") {
				display(["Skipped [$orgItem]. ", "Reason",'invalid_file_folder_path']);
				$skippedItem = 1;
				next;
			} elsif (substr($tempItem,0,1) ne "/") {
				$item_ext = '/'.$item_ext;
			}
			push @newItemArray, $item;
		}
	}
	return @newItemArray;
}

#------------------------------------------------- W -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: writeToTrace
# Objective				: This subroutine writes to log
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub writeToTrace {
	if (open LOG_TRACE_HANDLE, ">>", $_[0]){
		my $date        	= strftime "%Y/%m/%d %H:%M:%S", localtime;
		# do not use getMachineUser() in the following line | in cli, it gives undef
		my $logContent 		= qq([$date][) . $Configuration::mcUser . qq(]$_[1]);
		print LOG_TRACE_HANDLE $logContent;
		close(LOG_TRACE_HANDLE);
	}
}

#*******************************************************************************************
# Subroutine Name         :	writeOperationSummary
# Objective               :	This subroutine writes the restore summary to the output file.
# Added By                : Senthil Pandian
# Modified By             : Yogesh Kumar
#******************************************************************************************
sub writeOperationSummary
{
	my @now     = localtime;
	my $endTime = localtime(mktime(@now));

	my $errorDir       = getCatfile($Configuration::jobRunningDir, $Configuration::errorDir);
	my $excludeDirPath = getCatfile($Configuration::jobRunningDir, $Configuration::excludeDir);
	my $infoFile       = getCatfile($Configuration::jobRunningDir, $Configuration::infoFile);

	my ($successFiles,$syncedFiles,$failedFilesCount,$filesConsideredCount,$noPermissionCount,$missingCount) = (0) x 6;

	if ($Configuration::totalFiles) {
		$filesConsideredCount = $Configuration::totalFiles;
		Chomp(\$filesConsideredCount);
	}
	my @StatusFileFinalArray = ('COUNT_FILES_INDEX','SYNC_COUNT_FILES_INDEX','ERROR_COUNT_FILES','DENIED_COUNT_FILES','MISSED_FILES_COUNT');
	($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount) = getParameterValueFromStatusFileFinal(@StatusFileFinalArray);
	chmod $Configuration::filePermission, $Configuration::outputFilePath;

	# If $outputFilePath exists then only summery will be written otherwise no summery file will exists.
	if (-e $Configuration::outputFilePath and -s $Configuration::outputFilePath > 0) {
		# open output.txt file to write restore summary.
		if (!open(OUTFILE, ">> $Configuration::outputFilePath")){
			traceLog(['failed_to_open_file', " : $Configuration::outputFilePath Reason:$!\n"]);
			return;
		}
		chmod $Configuration::filePermission, $Configuration::outputFilePath;

		if (-d $excludeDirPath) {
			$summary .= appendExcludedLogFileContents();
		}

		if ($_[0] eq $Configuration::evsOperations{'BackupOp'} || $_[0] eq $Configuration::evsOperations{'LocalBackupOp'}) {
			my $isIgnorePermissionErrors = (getUserConfiguration('IFPE') ne '')? getUserConfiguration('IFPE') :0;
			$isIgnorePermissionErrors    = ($isIgnorePermissionErrors ne '')?$isIgnorePermissionErrors:0;

			if ($isIgnorePermissionErrors){
				my $permissionError 	 = $errorDir."/".$Configuration::permissionErrorFile;
				$summary .= checkAndUpdatePermissionDeniedList($permissionError);
			} else {
				$failedFilesCount += $noPermissionCount;
				$Configuration::noPermissionCount = getPermissionDeniedCount();
				if ($Configuration::noPermissionCount){
					$filesConsideredCount += $Configuration::noPermissionCount;
					$failedFilesCount 	  += $Configuration::noPermissionCount;
				}
			}
		}

		if (($failedFilesCount ne "" and $failedFilesCount > 0) or ($Configuration::nonExistsCount > 0)) {
			appendErrorFileContents($errorDir);
			$summary .= $summaryError.$lineFeed;
			$failedFilesCount += $Configuration::nonExistsCount;
		}

		# construct summary message.
		my $mail_summary = undef;
		$summary      .= "\nSummary: \n";
		$Configuration::finalSummery = "\nSummary: \n";
		#Needs to be removed: Senthil
		#$filesConsideredCount = 99;
		#$failedFilesCount  = 5;

		if ($_[0] eq $Configuration::evsOperations{'BackupOp'} || $_[0] eq $Configuration::evsOperations{'LocalBackupOp'}) {
			# Prepare mail contents
			$mail_summary .= $Locale::strings{'files_considered_for_backup'} . $filesConsideredCount;
			$mail_summary .= "\n" . $Locale::strings{'files_backed_up_now'} . $successFiles;

			if ($_[0] eq $Configuration::evsOperations{'BackupOp'}) {
				$mail_summary .= "\n" . $Locale::strings{'files_already_present_in_your_account_conditional'} . $syncedFiles;
			} else {
				$mail_summary .= "\n" . $Locale::strings{'files_already_present_in_your_account'} . $syncedFiles;
			}

			$mail_summary .= "\n" . $Locale::strings{'files_failed_to_backup'} . $failedFilesCount;
			$mail_summary .= "\n" . $Locale::strings{'backup_end_time'} . "$endTime\n";
			$mail_summary .= "\n" . $Locale::strings{'files_in_trash_may_get_restored_notice'} . "\n" if ($_[0] eq $Configuration::evsOperations{'BackupOp'});

			# prepare summary content
			$Configuration::finalSummery .= $Locale::strings{'files_considered_for_backup'} . $filesConsideredCount;
			$Configuration::finalSummery .= "\n" . $Locale::strings{'files_backed_up_now'} . $successFiles;

			if ($_[0] eq $Configuration::evsOperations{'BackupOp'}) {
				$Configuration::finalSummery .= "\n" . $Locale::strings{'files_already_present_in_your_account_conditional'} . $syncedFiles;
			} else {
				$Configuration::finalSummery .= "\n" . $Locale::strings{'files_already_present_in_your_account'} . $syncedFiles;
			}

			$Configuration::finalSummery .= "\n" . $Locale::strings{'files_failed_to_backup'} . $failedFilesCount . "\n";
		} else 	{
			$mail_summary .= $Locale::strings{'files_considered_for_restore'}.$filesConsideredCount.
						"\n".$Locale::strings{'files_restored_now'}.$successFiles.
						"\n".$Locale::strings{'files_already_present_in_your_restore_location'}.$syncedFiles.
						"\n".$Locale::strings{'files_failed_to_restore'}.$failedFilesCount.
						"\n".$Locale::strings{'restore_end_time'}."$endTime\n";

			$Configuration::finalSummery .= $Locale::strings{'files_considered_for_restore'}.$filesConsideredCount.
						"\n".$Locale::strings{'files_restored_now'}.$successFiles.
						"\n".$Locale::strings{'files_already_present_in_your_restore_location'}.$syncedFiles.
						"\n".$Locale::strings{'files_failed_to_restore'}.$failedFilesCount."\n";
		}
		if ($Configuration::errStr ne "" &&  $Configuration::errStr ne "SUCCESS"){
			$mail_summary .= "\n\n".$Configuration::errStr."\n";
		}

		if ($Configuration::cancelFlag) {
			$Configuration::opStatus = Configuration::JOBEXITCODE->{'ABORTED'};
		}
		elsif ($failedFilesCount == 0 and $filesConsideredCount > 0) {
			$Configuration::opStatus = Configuration::JOBEXITCODE->{'SUCCESS'};
		}
		else {
			$Configuration::opStatus = Configuration::JOBEXITCODE->{'FAILURE'};
			# Considering the Failed case as Success if it less than the % user's selected
			if ($_[0] =~ /$Configuration::evsOperations{'BackupOp'}/){
				if ($percentToNotifyForFailedFiles and $failedFilesCount>0){
					my $perCount = ($failedFilesCount/$filesConsideredCount)*100;
					if ($percentToNotifyForFailedFiles >= $perCount){
						$Configuration::opStatus = Configuration::JOBEXITCODE->{'SUCCESS*'};
					}
				}

				if ($Configuration::opStatus ne Configuration::JOBEXITCODE->{'FAILURE'}){
					if ($percentToNotifyForMissedFiles && -e $infoFile){
						$infoFile       = getCatfile($Configuration::jobRunningDir, $Configuration::infoFile);
						my $missedCountCheckCmd = "cat '$infoFile' | grep \"^MISSINGCOUNT\"";
						my $missedCount = `$missedCountCheckCmd`;
						$missedCount =~ s/MISSINGCOUNT//;
						Chomp(\$missedCount) if ($missedCount);
						$missingCount += $missedCount if ($missedCount =~ /^\d+$/);

						my $perCount = ($missingCount/$filesConsideredCount)*100;
						if ($percentToNotifyForMissedFiles >= $perCount){
							$Configuration::opStatus = Configuration::JOBEXITCODE->{'SUCCESS*'};
						}
					}
				}
			}
		}
		my $tempOutputFilePath = $Configuration::outputFilePath;
		$tempOutputFilePath = (split("_Running_",$tempOutputFilePath))[0] if ($tempOutputFilePath =~ m/_Running_/);
		my %logStat = (
			(split('_', basename($tempOutputFilePath)))[0] => {
				'datetime' => strftime("%d/%m/%Y %H:%M:%S", localtime(mktime(@startTime))),
				'duration' => (mktime(@now) - mktime(@startTime)),
				'filescount' => $filesConsideredCount,
				'status' => $Configuration::opStatus . '_' . ucfirst($_[1])
			}
		);
		addLogStat($Configuration::jobRunningDir, \%logStat);
		#Removing the LOGPID file
		my $logPidFilePath 	= getCatfile($Configuration::jobRunningDir, $Configuration::logPidFile);
		unlink($logPidFilePath);

		$summary .= $mail_summary;
		$Configuration::mailContent .= $mail_summary;
		print OUTFILE $summary;
		close OUTFILE;
	}
}

#****************************************************************************************************
# Subroutine Name         : writeLogHeader.
# Objective               : This function will write user log header.
# Added By				  : Senthil Pandian
# Modified By             : Sabin Cheruvattil
#*****************************************************************************************************/
sub writeLogHeader {
	my $taskType = lc($_[0]);
	my $logTime = time;
	#Chomp(\$logTime); #Removing white-space and '\n'
	my $archiveLogDirpath = $Configuration::jobRunningDir.'/'.$Configuration::logDir;
	createDir($archiveLogDirpath, 1);
	#my $logOutputFile  = $archiveLogDirpath.'/'.$logTime;
	my $logOutputFile  = $Configuration::outputFilePath;
	my $backupPathType = getUserConfiguration('BACKUPTYPE');
	my $bwThrottle     = getUserConfiguration('BWTHROTTLE');
	my $restoreHost	   = getUserConfiguration('RESTOREFROM');
	my $backupTo	   = getUserConfiguration('BACKUPLOCATION');
	my $username       = getUsername();
	$percentToNotifyForFailedFiles = getUserConfiguration('NFB');
	$percentToNotifyForMissedFiles = getUserConfiguration('NMB');
	#my $logStartTime = `date +"%a %b %d %T %Y"`;

	#my $isScheduledJob = $_[0];
	# require to open log file to show job in progress as well as to log exclude details
	if (!open(OUTFILE, ">", $logOutputFile)){
		print Constants->CONST->{'CreateFail'}." $logOutputFile, Reason:$!";
		traceLog(Constants->CONST->{'CreateFail'}." $logOutputFile, Reason:$!") and die;
	}
	chmod $Configuration::filePermission, $logOutputFile;

	autoflush OUTFILE;
	my $host = `hostname`;
	chomp($host);

	autoflush OUTFILE;
	my $tempJobType = $Configuration::jobType;
	my $backupMountPath = '';
	if ($tempJobType =~ /Local/){
		$tempJobType =~ s/Local//;
		$backupMountPath = "Mount Path: $Configuration::expressLocalDir \n";
	}

	my $jobname = '';
	my $jt = 'backup';
	if (lc($Configuration::jobType) eq "backup") {
		$jobname = "default_backupset";
	}
	elsif ($Configuration::jobType eq "LocalBackup") {
		$jobname = "local_backupset";
		$jt = "localbackup";
	}
	else {
		$jobname = "default_backupset";
	}

	my $mailHeadA	= '';
	$mailHeadA 	= "\n$tempJobType Scheduled Time: " . getCRONScheduleTime($Configuration::mcUser, $username, lc($tempJobType), $jobname) unless($taskType eq "manual");
	$mailHeadA 		.= "\n$tempJobType Start Time: ".(localtime)."\n";

	my ($mailHeadB, $jsc) = ('', '');
	my $dedup  	      = getUserConfiguration('DEDUP');
	if ($Configuration::jobType eq "Backup" and $dedup eq 'off') {
		$mailHeadB = "$tempJobType Type: $backupPathType $tempJobType \n";
	}
	my $location = ($backupTo =~ /#/)?(split('#',$backupTo))[1]:$backupTo;
	$mailHeadB .= "Machine Name: $host \n";
	$mailHeadB .= "$tempJobType Location: $location \n";
	$mailHeadB .= $backupMountPath;
	if ($tempJobType eq "Restore") {
		my $fromLocation = ($restoreHost =~ /#/)?(split('#',$restoreHost))[1]:$restoreHost;
		$mailHeadB .= "$tempJobType From Location: $fromLocation \n";
		$jsc .= 'Restore Set Contents:' . $lineFeed;
		$jsc .= Helpers::getJobSetLogSummary(lc($tempJobType));
	}
	#$mailHeadB .= "Backup Failure(%): $percentToNotifyForFailedFiles\n" if ($Configuration::jobType =~ /Backup/);
	if ($Configuration::jobType =~ /Backup/){
		$mailHeadB .= "Failed files(%): $percentToNotifyForFailedFiles $lineFeed";
		$mailHeadB .= "Missing files(%): $percentToNotifyForMissedFiles $lineFeed";
		$mailHeadB .= "Throttle Value(%): $bwThrottle \n" if ($Configuration::jobType eq "Backup");
		$mailHeadB .= "Show hidden files/folders: ".(Helpers::getUserConfiguration('SHOWHIDDEN')? 'enabled' : 'disabled').$lineFeed;
		$mailHeadB .= "Ignore file/folder level permission errors: ".(Helpers::getUserConfiguration('IFPE')? 'enabled' : 'disabled').$lineFeed;
		$jsc .= ($jt eq 'backup'? 'Backup Set Contents:' : 'Express Backup Set Contents:') . "\n";
		$jsc .= Helpers::getJobSetLogSummary($jt);
	}
	my $LogHead = $mailHeadA . "Username: $username \n" . $mailHeadB . $jsc;
	print OUTFILE $LogHead."\n";

	my $mailHead = $mailHeadA.$mailHeadB;
	return $mailHead;
}

#****************************************************************************************************
# Subroutine Name         : writeParamToFile.
# Objective               : This subroutine will write parameters into a file named operations.txt. Later it is used in Operations.pl script.
# Modified By             : Abhishek Verma.
#*****************************************************************************************************/
sub writeParamToFile{
	my $fileName = shift;
	if (!open(PH,'>',$fileName)){ #PH means Parameter file handler.
		$Configuration::errStr = $Locale::strings{'failed_to_open_file'}.": $fileName, Reason:$!\n";
		traceLog($Configuration::errStr);
		print $Configuration::errStr;
		cancelProcess();
	}
	print PH @_;
	close (PH);
	chmod $Configuration::filePermission,$fileName;
}

#****************************************************************************************************
# Subroutine Name         : writeCrontab.
# Objective               :
# Added By				  : Vijay Vinoth
#*****************************************************************************************************/
sub writeCrontab {
	my $cron = "/etc/crontab";
	if (!open CRON, ">", $cron) {
		exit 0;
	}
	print CRON @_;
	close(CRON);
}
#------------------------------------------------- X -------------------------------------------------#
#------------------------------------------------- Y -------------------------------------------------#
#------------------------------------------------- Z -------------------------------------------------#
1;
