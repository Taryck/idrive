#*****************************************************************************************************
# 						Most commonly used subroutines are placed here for re-use
# 							Created By	: Yogesh Kumar
#							Modified By	: Anil Kumar
#							Reviewed By	: Deepak Chaurasia
#****************************************************************************************************/

package Helpers;
use strict;
use warnings;
use Cwd 'abs_path';
use POSIX qw(strftime);
use File::Spec::Functions;
use File::Basename;
use Scalar::Util qw(reftype looks_like_number);
use File::Path qw(rmtree);
use File::Copy;
use POSIX;
use Fcntl qw(:flock SEEK_END);
use IO::Handle;

#use Data::Dumper;

use Configuration;
use Strings;

use utf8;
use MIME::Base64;

use Sys::Hostname;
#use JSON qw(from_json to_json);

use constant STATUS => 'STATUS';
use constant SUCCESS => 'SUCCESS';
use constant FAILURE => 'FAILURE';
use constant MSG => 'MSG';
use constant DATA => 'DATA';

my $appPath;
my $servicePath = '';
my $username = '';
my $evsBinary;
my $storageUsed;
my $totalStorage;
my $utf8File;
my $serverAddress;
my $machineHardwareName;
my $muid;
my $errorDevNull = '2>>/dev/null';
our $linuxUser = `whoami`;

my %notifications;
our %crontab;

use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";
use constant FILE_MAX_COUNT => 1000;
use constant EXCLUDED_MAX_COUNT => 30000;

my ($relative,$BackupsetFile_new,$BackupsetFile_Only,$current_source);
my $filecount = 0;

my %backupExcludeHash = (); #Hash containing items present in Exclude List#
my ($totalSize,$prevFailedCount,$curLines,$cols,$latestCulmn,$backupfilecount) = (0) x 5;
my $progressSizeOp = 1;
my ($backupLocationDir,$summaryError,$summary) = ('') x 4;
my $lineFeed = "\n";

tie(my %userConfiguration, 'Tie::IxHash');

#------------------------------------------------- A -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: authenticateUser
# Objective				: Authenticate user credentials
# Added By				: Yogesh Kumar
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
	my $res = request(%params);
	# If cgi fails to provide any output then fallback to EVS commands for authentication
	unless ($res) {
		my $tmpPath = "$servicePath/$Configuration::tmpPath";
		createDir($tmpPath);

		createUTF8File('STRINGENCODE',$upswd, ("$tmpPath/$_[0]\.tmp")) or
			retreat('failed_to_create_utf8_file');
		my @result = runEVS();

		if (($result[0]->{'STATUS'} eq 'SUCCESS') and ($result[0]->{'MSG'} eq 'no_stdout')) {
			createUTF8File('VALIDATE',$_[0], ("$tmpPath/$_[0]\.tmp")) or 
			retreat('failed_to_create_utf8_file');
			@responseData = runEVS('tree');
			
			if(defined($responseData[0]->{'MSG'}) && $responseData[0]->{'MSG'} =~ m/unable to reach the server/i) {
				retreat('please_check_internet_con_and_try');
			}
		}
		else {
			retreat(['Your account is under maintenance. Please contact support for more information',"."]) if((defined($result[0]->{'desc'})) && ($result[0]->{'desc'} eq 'ACCOUNT IS UNDER MAINTENANCE')); 
			retreat(ucfirst($result[0]->{'MSG'})) if(defined($result[0]->{'MSG'}));
			retreat(ucfirst($result[0]->{'desc'}));
		}
		rmtree("$servicePath/$Configuration::tmpPath");
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
		display(['your_proxy_has_been_disabled', "\n"],1) if(defined($_[0]));
	}
	else {	
		display("\n",0);
		
		my $proxySIP = getAndValidate(['enter_proxy_server_ip', ': '], "ipaddress", 1);
		setUserConfiguration('PROXYIP',$proxySIP);

		my $proxySIPPort = getAndValidate(['enter_proxy_server_port',': '], "port_no", 1);
		setUserConfiguration('PROXYPORT',$proxySIPPort);

		display(['enter_proxy_server_username_if_set', ': '], 0);
		my $proxySIPUname = trim(getUserChoice());
		setUserConfiguration('PROXYUSERNAME',$proxySIPUname);

		my $proxySIPPasswd = '';
		if($proxySIPUname ne ''){ 
			display(['enter_proxy_server_password_if_set', ': '], 0);
			$proxySIPPasswd = trim(getUserChoice(0));
			$proxySIPPasswd = encryptRAData($proxySIPPasswd);
		}
		
		setUserConfiguration('PROXYPASSWORD',$proxySIPPasswd);

		my $proxyStr = "$proxySIPUname:$proxySIPPasswd\@$proxySIP:$proxySIPPort";
		setUserConfiguration('PROXY', $proxyStr);

		if(defined($_[0])) {
			# need to ping for proxy validation testing. .
			my @responseData = ();
			if($userConfiguration{'DEDUP'} eq 'off') {
				createUTF8File('PING')  or retreat('failed_to_create_utf8_file');
			}
			else {
				my $deviceID    = getUserConfiguration('BACKUPLOCATION');
				$deviceID 		= (split("#",$deviceID))[0];
				createUTF8File('PINGDEDUP',$deviceID)  or retreat('failed_to_create_utf8_file');
			}
			@responseData = runEVS();
			if (($responseData[0]->{'STATUS'} eq 'FAILURE') and ($responseData[0]->{'MSG'} =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407|execution_failed|kindly_verify_ur_proxy/)) {
			
				retreat(["\n", 'kindly_verify_ur_proxy']) if(defined($_[1]));
				display(["\n", 'kindly_verify_ur_proxy']);
				askProxyDetails(@_,"NoRetry");
				
			} 
			display(['proxy_details_updated_successfully', "\n"], 1) ;
		}
	}
	return 1;
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

	my $absLogStatFile = "$_[0]/LOGS/$Configuration::logStatFile";
	if (open(my $lsf, '>>', $absLogStatFile)) {
		my $lsc = to_json($_[1]);
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

#------------------------------------------------- B -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: buildQuery
# Objective				: Build hash to http query string
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub buildQuery {
	my (%data) = @_;
	my @qs;
	foreach my $key (keys %data) {
		push @qs, (urlEncode($key) . '=' . urlEncode($data{$key}));
	}
	return join("&", @qs);
}

#*****************************************************************************************************
# Subroutine			: backupTypeCheck
# Objective               : This subroutine checks if backup type is either Mirror or Relative
# Added By                : Dhritikana
#****************************************************************************************************/
sub backupTypeCheck {
	my $backupPathType = getUserConfiguration('BACKUPTYPE');
	my $relative;
	$backupPathType = lc($backupPathType);
	if($backupPathType eq "relative") {
		$relative = 0;
	}else{
		$relative = 1;
	}	
	return $relative;
}

#------------------------------------------------- C -------------------------------------------------#
#*****************************************************************************************************
# Subroutine			: checkAndUpdateServerRoot
# Objective				: check and update if server root field is empty in configuration file
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkAndUpdateServerRoot {
	my $serverRoot;
	if($userConfiguration{'DEDUP'} eq 'on' and (!defined($userConfiguration{'SERVERROOT'}) or $userConfiguration{'SERVERROOT'} eq '')){
		my @devices = fetchAllDevices();
		my $uniqueID = getMachineUID() or retreat('failed');
		foreach (@devices) {
			next	if ($muid ne $_->{'uid'});
			if($_->{'server_root'} ne ''){
				setUserConfiguration('SERVERROOT', $_->{'server_root'});
				saveUserConfiguration() or retreat('failed');
			}
		}
	}
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
		if ((lc($text) eq 'on') or (lc($text) eq 'enabled')) {
			$color = 'green';
			$bg    = 'black';
		}
		elsif ((lc($text) eq 'off') or (lc($text) eq 'disabled')) {
			$color = 'red';
			$bg    = 'black';
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

	if((!-e $fileName) or (!-s $fileName)) {
		$Configuration::errStr = "Your $jobType"."set file \"$fileName\" is empty. ".$Locale::strings{'please_update'}."\n";
		$isEmpty = 1;
	}
	elsif(-s $fileName > 0 && -s $fileName <= 50){
		if(!open(OUTFH, "< $fileName")) {
			$Configuration::errStr = $Locale::strings{'failed_to_open_file'}.":$fileName, Reason:$!";
			traceLog($Configuration::errStr);
			$isEmpty = 1;
		}		
		my $buffer = <OUTFH>;
		close OUTFH;		
		Chomp(\$buffer);
		if($buffer eq ''){
			$Configuration::errStr = "Your $jobType"."set file \"$fileName\" is empty. ".$Locale::strings{'please_update'}."\n";
			$isEmpty = 1;
		}
		close(OUTFH);	
	}	
	if($isEmpty){
		print $Configuration::errStr if($taskType eq 'manual');
		my $subjectLine = "$taskType $jobType Email Notification "."[$userName]"." [Failed $jobType]";
		$Configuration::status = "FAILURE";
		sendMail($taskType,$jobType,$subjectLine,$reason,$fileName);
		rmtree($errorDir);
		unlink $pidPath;
		exit 0;	
	}
}

#*****************************************************************************************************
# Subroutine			: checkExitError
# Objective				: This function will display the proper error message if evs error found in Exit argument.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub checkExitError {
	my $errorline = "idevs error";
	my $individual_errorfile = $_[0];
	my $userJobPaths = $_[1];
	
	unless(-e $individual_errorfile or -s $individual_errorfile>0) {
		return 0;
	}
	#check for retry attempt
	if(!open(TEMPERRORFILE, "< $individual_errorfile")) {
		traceLog($Locale::strings{'failed_to_open_file'}.":$individual_errorfile, Reason:$! \n", __FILE__, __LINE__);
		return 0;
	}
	
	my @linesBackupErrorFile = <TEMPERRORFILE>;
	close TEMPERRORFILE;
	chomp(@linesBackupErrorFile);
	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;
		
		if($linesBackupErrorFile[$i] eq "" or $linesBackupErrorFile[$i] =~ m/$errorline/){
			next;
		}
		
		foreach my $exitErrorMessage (@Configuration::errorArgumentsExit)
		{
			if($linesBackupErrorFile[$i] =~ m/$exitErrorMessage/)
			{
				$Configuration::errStr  = $Locale::strings{'operation_could_not_be_completed_reason'}.$exitErrorMessage.".";
				traceLog($Configuration::errStr, __FILE__, __LINE__);
				#kill evs and then exit
				my $username = getUsername();
				my $jobTerminationScript = getScript('job_termination');
				
				system("$Configuration::perlBin \'$jobTerminationScript\' \'$userJobPaths\' \'$username\' 1>/dev/null 2>/dev/null");
				#unlink($pwdPath);
				return "1-$Configuration::errStr";
			}
		}		
	}
	return 0;
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
	
	if(!open(FD_WRITE, ">", $info_file)){
		traceLog($Locale::strings{'failed_to_open_file'}.":$info_file. Reason:$!", __FILE__, __LINE__);
		exit 0;
	}
	chmod $Configuration::filePermission, $info_file;
	close FD_WRITE; #Needs to be removed
	
	my $relative = backupTypeCheck();
	#Backupset File name for mirror path
	if($relative != 0) {
		$BackupsetFile_new =  $relativeFileset;
		if(!open NEWFILE, ">>", $BackupsetFile_new) {
			traceLog($Locale::strings{'failed_to_open_file'}.":$BackupsetFile_new. Reason:$!", __FILE__, __LINE__);
			exit 0;
		}
		chmod $Configuration::filePermission, $BackupsetFile_new;
	}
	else {
		#Backupset File Name only for files
		$BackupsetFile_Only = $filesOnly;
		if(!open NEWFILE, ">>", $BackupsetFile_Only) {
			traceLog($Locale::strings{'failed_to_open_file'}.":$filesOnly. Reason:$!", __FILE__, __LINE__);
			exit 0;
		}
		chmod $Configuration::filePermission, $BackupsetFile_Only;		
		$BackupsetFile_new = $noRelativeFileset;
	}
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateServicePath
# Objective				: check .serviceLocation file if exist then try to create servicePath
# Added By				: Anil Kumar
#****************************************************************************************************/
sub checkAndUpdateServicePath {
	my $serviceLocation = $appPath."/" . $Configuration::serviceLocationFile;
	return 0	if (!-e $serviceLocation or -z $serviceLocation);
	return 0	if (!open(my $sp, '<:encoding(UTF-8)', $serviceLocation));
		
	my $s = <$sp>;
	close($sp);
	chomp($s);
	if (-d $s) {
		$servicePath = $s;
		return 1;
	}
	else {
		my $ret = mkdir($s);
		chmod 0777, $s;
		if($ret eq 1) {
			display(["Service directory ", "\"$s\""," created successfully." ],1);
			$servicePath = $s;
			return 1;
		}
		display(["Service Path ", "\"$s\""," does not exists." ],1);
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
			chop($parentDir[1]) if($parentDir[1] =~/\/$/);
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
# Modified By 		   	: Abhishek Verma - Now the logfile name will contain epoch time and job status like (Success, Failure, Aborted) - 17/5/2017
#**************************************************************************************************
sub createLogFiles {
	my $jobType = $_[0];
	our $progressDetailsFileName = "PROGRESS_DETAILS_".$jobType;
	our $outputFileName = $jobType;
	our $errorFileName = $jobType."_ERRORFILE";
	my $logDir   = $Configuration::jobRunningDir."/LOGS";
	my $errorDir = $Configuration::jobRunningDir."/ERROR";
	my $ifRetainLogs = getUserConfiguration('RETAINLOGS');
	
	if($ifRetainLogs eq "NO") {
		chmod $Configuration::filePermission, $logDir;
		rmtree($logDir);
	}

	if(!-d $logDir)
	{
		mkdir $logDir;
		chmod $Configuration::filePermission, $logDir;
	}

#	my $currentTime = localtime;
	my $currentTime = time;#This function will give the current epoch time.
	#previous log file name use to be like 'BACKUP Wed May 17 12:34:47 2017_FAILURE'.Now log name will be '1495007954_SUCCESS'.
	$Configuration::outputFilePath = $logDir."/".$currentTime; 
	$Configuration::errorFilePath  = $errorDir."/".$errorFileName;
	$Configuration::progressDetailsFilePath = $Configuration::jobRunningDir."/".$progressDetailsFileName;
}

#****************************************************************************************************
# Subroutine Name         : createUpdateBWFile.
# Objective               : Create or update bandwidth throttle value file(.bw.txt). 
# Added By                : Avinash Kumar.
# Modified By		      : Dhritikana
#*****************************************************************************************************/
sub createUpdateBWFile() {
	my $bwThrottle = getUserConfiguration('BWTHROTTLE');
	my $bwPath     = getUserProfilePath()."/bw.txt";
	
	open BWFH, ">", $bwPath or (traceLog($Locale::strings{'failed_to_open_file'}.":$bwPath. Reason:$!", __FILE__, __LINE__) and die);
	chmod $Configuration::filePermission, $bwPath;
	print BWFH $bwThrottle;
	close BWFH;
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
	display(['user_directory_has_been_created_successfully', "\n"],1);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: createUTF8File
# Objective				: Build valid evs parameters
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createUTF8File {
	loadServerAddress();
	my $evsOP = $_[0];
	my $evsPattern;
	unless(reftype(\$evsOP) eq 'SCALAR'){
		$evsPattern = $Configuration::evsAPIPatterns{$_[0]->[0]};
		$utf8File   = $_[0]->[1];
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

	my $evsParams = join("\n", @ep);
	unless ($encodeString) {
		unless ($evsParams =~ /--password-file/) {
			$evsParams .= "\n--password-file=" . getIDPWDFile();
		}
		my $pvtKey = getIDPVTFile();
		if (-e $pvtKey) {
			$evsParams .= "\n--pvt-key=".$pvtKey;
		}
		my $proxyStr = getUserConfiguration('PROXY');
		
		if($proxyStr){
			my ($uNPword, $ipPort) = split(/\@/, $proxyStr);			
			my @UnP = split(/\:/, $uNPword);
			if(scalar(@UnP) >1 and $UnP[0] ne "") {
				$UnP[1] = ($UnP[1] ne '')?decryptRAData($UnP[1]):$UnP[1];
				foreach ($UnP[0], $UnP[1]) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				$uNPword = join ":", @UnP;
				$proxyStr = "http://$uNPword\@$ipPort";
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
# Subroutine			: checkRetryAndExit
# Objective				: This subroutine checks for retry count and exits if retry exceeded
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub checkRetryAndExit {
	my $choiceRetry = shift;
	my $newLine		= shift;
	display('') if $newLine;
	retreat('your_max_attempt_reached') if($choiceRetry == $Configuration::maxChoiceRetry);
}

#*****************************************************************************************************
# Subroutine			: createCache
# Objective				: This is to create cache folder for storing the user information.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub createCache {
	my $existingdir = getCachedDir();
	if( !-d $existingdir) {
		my $res = mkdir $existingdir ;
		if($res ne 1) {
			traceLog("Error in creating $existingdir.\n");
			return 0;
		}
		chmod $Configuration::filePermission, $existingdir;
	}
	
	my $filename = getCachedFile();
	my $fh;
	if(!open($fh, '>', $filename)){
		traceLog("Could not open file '$filename' $!");
		return 0;
	}
	print $fh $_[0];
	close $fh;
	return 1;
}

#*****************************************************************************************************
# Subroutine			: checkAndUpdateClientRecord
# Objective				: This is to check and update the client entry for stats
# Added By				: Anil Kumar
#****************************************************************************************************/
sub checkAndUpdateClientRecord {
	my $freshInstallFile = "$appPath/freshInstall";
	
	if(-e $freshInstallFile) {		
		if(!open(FH, "<", $freshInstallFile)) {
			traceLog("Not able to open $freshInstallFile, Reason:$!");
			return;
		}
		my @idriveUsers = <FH>;
		close FH;
		chomp(@idriveUsers);
		foreach my $user (@idriveUsers) {
			return	if($_[0] eq $user);
		}
	}
	
	my $isUpdated = updateUserDetail($_[0],$_[1],1);
	if($isUpdated){
		if(!open(FH, ">>", $freshInstallFile)) {
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
	if($deviceName eq '') {
		$deviceName = $Configuration::hostname;
	}
	display('setting_up_your_backup_location',1);
	createUTF8File('CREATEBUCKET',$deviceName) or retreat('failed_to_create_utf8_file');
	my @result = runEVS('item');

	if ($result[0]{'STATUS'} eq 'SUCCESS') {
		display(['your_backup_to_device_name_is',(" \"" . $result[0]{'nick_name'} . "\".")]);
		setUserConfiguration('SERVERROOT', $result[0]{'server_root'});
		setUserConfiguration('BACKUPLOCATION',
			($Configuration::deviceIDPrefix . $result[0]{'device_id'} . $Configuration::deviceIDPostfix .
				'#' . $result[0]{'nick_name'}));
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: createNotificationFile
# Objective				: create file notification.json
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createNotificationFile {
	my $nf = getNotificationFile();
	unless (-e $nf and !-z $nf) {
		if (open(my $fh, '>', $nf)) {
			map{$notifications{$_} = ''} keys %Configuration::notificationsSchema;
			print $fh to_json(\%notifications);
			close($fh);
			return 1;
		}
		return 0;
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: createCrontabFile
# Objective				: create file crontab.json
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub createCrontabFile {
	my $nf = getCrontabFile();
	my $title = shift || retreat('crontab_title_is_required');
	my $ctab = shift;

	loadCrontab();

	unless (exists $crontab{$title}) {
		$ctab = \%{deepCopyEntry(\%Configuration::crontabSchema)} unless (defined $ctab);
		if (open(my $fh, '>', $nf)) {
			$crontab{$title} = $ctab;
			print $fh to_json(\%crontab);
			close($fh);
			return 1;
		}
		return 0;
	}
	elsif (defined $ctab) {
		if (open(my $fh, '>', $nf)) {
			$crontab{$title} = deepCopyEntry(\%Configuration::crontabSchema, $ctab);
			print $fh to_json(\%crontab);
			close($fh);
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
	if ($responseData[0]->{'STATUS'} eq 'FAILURE') {
		retreat(ucfirst($responseData[0]->{'MSG'}));
	}
	changeMode(getIDPWDFile());
	copy(getIDPWDFile(), getIDPWDSCHFile());
	changeMode(getIDPWDSCHFile());
	encryptPWD($_[0]) or retreat('failed');
}


#------------------------------------------------- D -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: deepCopyEntry
# Objective				: deeply copy an entry in the given args 
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
# Subroutine			: display
# Objective				: Prints formated data to stdout
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub display {
	my $message = shift;
	my $msg;
	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}
	for my $i (0 .. $#{$message}) {
		if (exists $Locale::strings{$message->[$i]}) {
			$msg .= $Locale::strings{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}
	print "$msg";
	my $endWithNewline = 1;
	$endWithNewline    = shift if (scalar(@_) > 0);
	print "\n" if ($endWithNewline);
}

#*****************************************************************************************************
# Subroutine			: displayHeader
# Objective				: Display header for the script files
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub displayHeader {
	return 1 if ($Configuration::callerEnv eq 'SCHEDULER');

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
		$header    .= (qq( ) x (20 - ($l -$adjst)) . qq($Locale::strings{'developed_by'} ));
		$header    .= qq($Locale::strings{lc($Configuration::appType . '_maintainer')}\n);
		$header    .= (qq(-) x $l . qq( ) x (20 - ($l -$adjst)) . qq(-) x ($w - ($l+ (20 - ($l -$adjst)))));
		$h = qq($Locale::strings{'logged_in_user'});
		$header    .= qq(\n$h);
		$header    .= ((qq( ) x (20 - ($l -$adjst) + ($l - length($h)))) . ($username ? $username: $Locale::strings{'no_logged_in_user'}) . qq(\n));

		if ($username and -e getServerAddressFile()){
			if(loadStorageSize() or reCalculateStorageSize()) {
				$header    .= (qq(-) x $l . qq( ) x (20 - ($l -$adjst)) . qq(-) x ($w - ($l+ (20 - ($l -$adjst)))));
				$header    .= qq(\n);
				$h = qq($Locale::strings{'storage_used'});
				$header    .= qq($h);
				$header    .= ((qq( ) x (20 - ($l -$adjst) + ($l - length($h)))) . qq($storageUsed of $totalStorage) . qq(\n));
			}
		}

		if(isUpdateAvailable()) {
			$header    .= qq(-) x $w;
			$header    .= qq(\n);			
			$h = qq($Locale::strings{'new_update_is_available'});
			$header    .= qq($h\n);
		}
		$header    .= qq(=) x $w . qq(\n);
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
	if ($Configuration::callerEnv eq 'SCHEDULER') {
		traceLog($Configuration::callerEnv." is caller environment");
	}

	my $c = 1;
	my ($message, @options) = @_;
	print map{$c++ . ") ", $Locale::strings{$_} . "\n"} @options;
	print $Locale::strings{$message} if exists $Locale::strings{$message};
}

#****************************************************************************************************
# Subroutine			: displayProgress
# Objective				: This subroutine will display the progress in the terminal window.
# Added By				: Senthil Pandian
#****************************************************************************************************
sub displayProgress{
	#$SIG{WINCH} = \&changeSizeVal;
	my $progressMsg = $_[0];
	if($Configuration::machineOS =~ /freebsd/i){
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
#****************************************************************************************************/
sub download {
	my $url           = shift;
	my $downloadsPath = shift;
	
	unless (defined($url)) {
		display('url_cannot_be_empty');
		return 0;
	}

	unless (defined($downloadsPath)) {
		$downloadsPath = "$servicePath/$Configuration::downloadsPath";
		createDir($downloadsPath);
	}

	unless (-d $downloadsPath) {
		display(["$downloadsPath ", 'does_not_exists']);
		return 0;
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
				$ppwd = ($ppwd ne '')?decryptRAData($ppwd):$ppwd;
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
		#my $tmpErrorFile  = getServicePath()."/".$Configuration::errorFile;
		my $tmpErrorFile  = $downloadsPath."/".$Configuration::errorFile;
		$response = `curl --tlsv1 --fail -k $proxy -L $url->[$i] -o '$downloadsPath/$parse[-1]' 2>>'$tmpErrorFile'`;
		if(-e $tmpErrorFile and -s $tmpErrorFile){
			if(!open(FH, "<", $tmpErrorFile)) {
				my $errStr = $Locale::strings{'failed_to_open_file'}.":$tmpErrorFile, Reason:$!";
				traceLog($errStr);
			}
			my $byteRead = read(FH, $response, $Configuration::bufferLimit);
			close FH;		
			Chomp(\$response);
		}
		unlink($tmpErrorFile) if(-e $tmpErrorFile);

		if ($? > 0) {
			traceLog($?);
			return 0;
		}
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
	my $ezf    = [@{$Configuration::evsZipFiles{$machineHardwareName}},
								@{$Configuration::evsZipFiles{'x'}}];
	my $downloadPage = $Configuration::evsDownloadsPage;
	my $domain       = lc($Configuration::appType);

	$domain .= 'downloads' if($Configuration::appType eq 'IDrive');

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
		last if($status);
	}
	rmtree("$servicePath/$Configuration::downloadsPath");
	return $status;
}

#*****************************************************************************************************
# Subroutine			: decryptRAData
# Objective				: Decrypt the given data
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub decryptRAData {
	my $encodedString = '';
	if(!defined($_[0]) or (defined($_[0]) and $_[0] ne '')){
		$encodedString = decode_base64($_[0]);
		utf8::encode($encodedString);
		$encodedString = shiftString($encodedString);
		$encodedString = decode_base64($encodedString);
		utf8::encode($encodedString);
		if($encodedString){
			my $npad = hex(substr($encodedString, 0, 1));
			my $esLength = substr($encodedString, 1, 10);
			my $nLength = sprintf("%ld", qq{$esLength});

			$encodedString = substr($encodedString, 11);
			$encodedString = shiftString($encodedString);
			$encodedString = substr($encodedString, 0, -$npad) if ($npad > 0);
		}
	}
	return $encodedString;
}

#*****************************************************************************************************
# Subroutine			: decryptRATime
# Objective				: Decrypt the given token
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub decryptRATime {
	my $encryptedToken = $_[0];
	my @chunks = unpack("(a4)*", $encryptedToken);
	my @token;
	my @cs;
	for my $chunk (@chunks) {
		@cs = unpack("(a2)*", $chunk);
		push(@token, (join('', reverse @cs)));
	}
	return substr((join('', @token)), 0, 10);
}

#*****************************************************************************************************
# Subroutine			: displayOptions
# Objective				: This subroutine is used to display options like create or select bucket
# Added By				: Anil Kumar
#****************************************************************************************************/
sub displayOptions {
	tie(my %optionsInfo, 'Tie::IxHash',
		'create_new_backup_location' => \&createBucket,
		'select_from_existing_backup_locations' => sub {
			linkBucket('backup', $_[0], \&displayOptions);
		}
	);
	my @options = keys %optionsInfo;
	display(['multiple_backup_locations_are_configured', ". ", 'select_an_option', ": ", "\n"]);
	displayMenu('', @options);
	my $deviceSelection = getUserMenuChoice(scalar(@options));
	
	return $optionsInfo{$options[$deviceSelection - 1]}->($_[0]);
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
		setRestoreLocation();
		return 1;
	}
	else {
		if(defined($_[0])) {
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
			if ($devices[0]{'STATUS'} eq 'FAILURE') {
				if ($devices[0]{'MSG'} =~ 'No devices found') {
					retreat('failed');
				}
			}
			elsif ($devices[0]{'STATUS'} eq 'SUCCESS') {
				linkBucket('restore', \@devices) or retreat("Please try again.");
				return 1;
			}
		}
		elsif (getUserConfiguration('DEDUP') eq 'off') {	
			display(['enter_your_restore_from_location_optional', ": "], 0);
				my $bucketName = getUserChoice();
				if($bucketName ne ""){
					display(['Setting up your restore from location...'], 1);
					if(substr($bucketName, 0, 1) ne "/") {
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
					if(-s $evsErrorFile > 0) {
						unlink($evsErrorFile);
						retreat('operation_could_not_be_completed_please_try_again');
					}
					unlink($evsErrorFile);
		
					if ($result[0]{'status'} =~ /No such file or directory|directory exists in trash/) {
						display(['failed_to_set_restore_from_location'], 1);
						display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\" ")],1);
					}
					else
					{
						$rfl = $bucketName;
						display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\" ")],1);
					}
					setUserConfiguration('RESTOREFROM', $rfl);
					unlink(getValidateRestoreFromFile());
				}
				else
				{
					display(['considering_default_restore_from_location_as', (" \"" . $rfl . "\" ")],1);
					display(['your_restore_from_device_is_set_to',(" \"" . $rfl . "\" ")],1);
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
	unless (($result[0]->{'STATUS'} eq 'SUCCESS') and ($result[0]->{'MSG'} eq 'no_stdout')) {
		retreat('failed_to_encode_private_key');
	}
	changeMode(getIDPVTFile());
}

#*****************************************************************************************************
# Subroutine			: encryptRAData
# Objective				: Encrypt the given data
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub encryptRAData {
	my $plainString  = $_[0];
	my $stringLength = length $plainString;
	my $npad         = $stringLength % 4;

	unless ($npad == 0) {
		$npad         = (4 - $npad);
		$plainString .= ('#' x $npad);
	}

	$plainString   = shiftString($plainString, 1);
	$plainString   = ($npad . sprintf("%010s", $stringLength) . $plainString);
	utf8::encode($plainString);
	$plainString   = encode_base64($plainString, '');

	$plainString = shiftString($plainString, 1);
	utf8::encode($plainString);
	$plainString = encode_base64($plainString, '');

	return $plainString;
}

#*****************************************************************************************************
# Subroutine			: encryptRATime
# Objective				: Encrypt the given time
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub encryptRATime {
	my $timestamp = $_[0];
	$timestamp   .= '0' while 16 > length $timestamp;
	my @chunks    = unpack("(a4)*", $timestamp);
	my @token;
	my @cs;
	for my $chunk (@chunks) {
		@cs = unpack("(a2)*", $chunk);
		push(@token, (join('', reverse @cs)));
	}
	return join('', @token);
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
	
	display('checking_for_dependencies') if($display);
	my $status = 0;
	for my $binary (@Configuration::dependencyBinaries) {
		display("dependency_$binary...", 0) if($display);
		my $r = `which $binary 2>/dev/null`;
		if ($? == 0) {
			display(['found']) if($display);
			$status = 1;
		}
		else {
			#traceLog($binary." not found");
			display(['not_found',"\n", "Please install ", $binary, " and try again."]) if($display);
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
	retreat('failed_to_fetch_server_address') if ($responseData[0]->{'STATUS'} eq 'FAILURE');
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
		if($email ne '') {
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
	if($curlPath eq ''){
		$curlPath = '/usr/local/bin/curl';
	}
	my $cmd  = '';
	my $data = $_[0];
	my $proxyStr = getUserConfiguration('PROXY');
	if($proxyStr) {
		my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
		my @UnP = split(/\:/, $uNPword);
		if(scalar(@UnP) >1 and $UnP[0] ne "") {
			$UnP[1] = ($UnP[1] ne '')?decryptRAData($UnP[1]):$UnP[1];
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
# Subroutine			: fileWrite
# Objective			: Write/create a file with given data
# Added By			: Yogesh Kumar
#****************************************************************************************************/
sub fileWrite {
	if (open(my $fh, '>', $_[0])) {
		print $fh $_[1];
		close($fh);
	}
}

#*****************************************************************************************************
# Subroutine			: findMyDevice
# Objective			: Find the bucket which was linked with this machine
# Added By			: Yogesh Kumar
#****************************************************************************************************/
sub findMyDevice {
	my $devices = $_[0];
	my $displayStatus = defined($_[1]);
	my $muid = getMachineUID() or retreat('failed');
	foreach (@{$devices}) {
		next	if ($muid ne $_->{'uid'});
		
		display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\". "),'do_you_want_edit_this_y_or_n_?'], 1);
		
		my $answer = getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if (lc($answer) eq 'y') {
			my $deviceName = getAndValidate(["\n", 'enter_your_backup_location_optional', ": "], "backup_location", 1);
			if($deviceName eq '') {
				$deviceName = $Configuration::hostname;
			}
			display('setting_up_your_backup_location',1);
			if ($deviceName and ($deviceName ne $_->{'nick_name'})) {
				my $restoreFrom = getUserConfiguration('RESTOREFROM');
				my $bkpLoc      = getUserConfiguration('BACKUPLOCATION');
				my $isSameDeviceID = 1;
				if($restoreFrom and $restoreFrom eq $bkpLoc){
					$isSameDeviceID = 1;
				}
				retreat('update_device_name_failed_try_again_later') unless (renameDevice($_, $deviceName));
				setUserConfiguration('RESTOREFROM',($Configuration::deviceIDPrefix .
					$_->{'device_id'} .$Configuration::deviceIDPostfix ."#" . $_->{'nick_name'})) if($isSameDeviceID);				
			}
			$displayStatus = 0;
		}
		
		display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\".")]) unless($displayStatus);
		setUserConfiguration('SERVERROOT', $_->{'server_root'});
		setUserConfiguration('BACKUPLOCATION',($Configuration::deviceIDPrefix .
			$_->{'device_id'} .$Configuration::deviceIDPostfix ."#" . $_->{'nick_name'}));
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

		if ($result[0]->{'STATUS'} eq 'FAILURE') {
			print "$result[0]->{'MSG'}\n";
			return 0;
		}
		elsif ($result[0]->{'STATUS'} eq 'SUCCESS') {
			display(['your_backup_to_device_name_is',(" \"" . $_->{'nick_name'} . "\".")]);
			
			setUserConfiguration('BACKUPLOCATION',
			($Configuration::deviceIDPrefix . $_->{'device_id'} . $Configuration::deviceIDPostfix .
			"#" . $_->{'nick_name'}));
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

#*****************************************************************************************************
# Subroutine			: getAbsPath
# Objective				: Get the absolute path of a file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getAbsPath {
	return abs_path(shift);
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
# Subroutine			: getEditor
# Objective				: Get user's editor name if it is available or return default "vi" editor
# Added By				: Senthil pandian
#****************************************************************************************************/
sub getEditor {
	return $ENV{EDITOR} || 'vi';
}

#*****************************************************************************************************
# Subroutine      : getMountPoints
# Objective       : Get all mounted list of devices
# Added By        : Senthil Pandian
# Modified By     : Yogesh Kumar
#****************************************************************************************************/
sub getMountPoints {
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
	foreach my $fileSystem (split("\n", $fileSystems)) {
		@fsDetails = split(/[\s\t]+/, $fileSystem, 6);
		@matches = grep { /^$fsDetails[5]$/ } @linuxOwnDefaultPartitions;
		if ((scalar(@matches) > 0) or ($fsDetails[1] < 512000)) {
			next;
		}

		if (-w $fsDetails[5]) {
			$mountPoints{$fsDetails[5]}{'type'} = 'd';
		}
	}
	return \%mountPoints;
}

#*****************************************************************************************************
# Subroutine			: getCachedFile
# Objective				: Build path to cached file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getCachedFile {
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
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::quotaFile");
}

#*****************************************************************************************************
# Subroutine Name         :	getCursorPos
# Objective               :	gets the current cusror position
# Added By                : Dhritikana
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
	if($curLines >= $threshold) {
		system("clear");
		print "\n";
		$curLines = 0;
	} else {
		$curLines = $curLines-1;
	}
	
	#changeSizeVal();
	getMachineOSDetails(); #Calling for FreeBSD
	#Added for FreeBSD machine's progress bar display
	if($Configuration::machineOS =~ /freebsd/i){
		my $latestCulmn = `tput cols`;
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
#****************************************************************************************************/
sub getEVSBinaryFile {
	unless ($userConfiguration{'DEDUP'}) {
		$userConfiguration{'DEDUP'} = "";
	}

	return $userConfiguration{'DEDUP'} eq 'off'? "$servicePath/$Configuration::evsBinaryName" : "$servicePath/$Configuration::evsDedupBinaryName";
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
	if($isDedup eq 'off'){
		createUTF8File(['PROPERTIES',$itemStatusUTFpath],
					$evsErrorFile,
					$remoteFolder
					) or retreat('failed_to_create_utf8_file');	
	} else {
		my $deviceID    = getUserConfiguration('BACKUPLOCATION');
		$deviceID 		= (split("#",$deviceID))[0];		
		createUTF8File(['PROPERTIESDEDUP',$itemStatusUTFpath],
					$deviceID,
					$evsErrorFile,
					$remoteFolder					
					) or retreat('failed_to_create_utf8_file');	
	}
	my @responseData = runEVS('item',1);
	if(-s $evsErrorFile > 0) {
		checkExitError($evsErrorFile,$jobType.'_archive');
	}
	unlink($evsErrorFile);
	if(defined($responseData[1]->{'files_count'})){
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
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idpwdFile");
}

#*****************************************************************************************************
# Subroutine			: getIDENPWDFile
# Objective				: Build path to IDENPWD file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDENPWDFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idenpwdFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPVTFile
# Objective				: Build path to IDPVT file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPVTFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idpvtFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPVTSCHFile
# Objective				: Build path to getIDPVTSCHFile file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getIDPVTSCHFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idpvtschFile");
}

#*****************************************************************************************************
# Subroutine			: getIDPWDSCHFile
# Objective				: Build path to IDPWDSCH file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getIDPWDSCHFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::idpwdschFile");
}

#*****************************************************************************************************
# Subroutine			: getValidateRestoreFromFile
# Objective				: Build path to validateRestoreFromFile file
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getValidateRestoreFromFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::validateRestoreFromFile");
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
# Subroutine			: getMachineUID
# Objective				: Find the mac address
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getMachineUID {
	return $muid if ($muid);

	my $cmd;
	my $prepend = '';
	$prepend = 'Linux' unless (defined($_[0]));
	my $ifConfigPath = `which ifconfig 2>/dev/null`;
	chomp($ifConfigPath);
	if($ifConfigPath ne '') {
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
	my @macAddr = $result =~ /HWaddr [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		$macAddr[0] =~ s/HWaddr |:|-//g;
		return ($muid = ("$prepend" . $macAddr[0]));
	}

	@macAddr = $result =~ /ether [a-fA-F0-9:]{17}|[a-fA-F0-9]{12}/g;
	if (@macAddr) {
		$macAddr[0] =~ s/ether |:|-//g;
		return ($muid = ("$prepend" . $macAddr[0]));
	}

	return 0;
}

#*****************************************************************************************************
# Subroutine			: getRunningJobs
# Objective				: Check if pid file exists & file is locked, then return it all
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRunningJobs {
	my @availableJobs;
	if(defined($_[0]) and reftype(\$_[0]) eq 'SCALAR'){
		@availableJobs = $_[0];
	} elsif(defined($_[0])){
		unless (exists $Configuration::availableJobsSchema{$ARGV[0]}) {
			push @availableJobs, lc($ARGV[0]);
		} else {
			push @availableJobs, $ARGV[0];
		}		
	} else {
		@availableJobs = keys %Configuration::availableJobsSchema;
	}

	my %runningJobs;
	foreach (@availableJobs) {
		my @p = split '_', $_;
		
		unless (exists $Configuration::availableJobsSchema{$_}) {
			retreat(['undefined_job_name', ': ', $_]);
		}

		my $pidFile = getCatfile(getUserProfilePath(), $Configuration::userProfilePaths{$_}, 'pid.txt');
		if (-e $pidFile) {
			if (!isFileLocked($pidFile)) {
				unlink($pidFile);
			}
			else {
				$runningJobs{$_} = $pidFile;
			}
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
# Subroutine			: getServerAddressFile
# Objective				: Build path to serverAddress file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getServerAddressFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::serverAddressFile");
}

#*****************************************************************************************************
# Subroutine			: getappath
# Objective				: This subroutine helps to get the user's main choices
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
# Modified By			: Anil Kumar [27/04/2018]
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
		Helperss::retreat(['job_name', $_[0], 'doesn\'t exists']);
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

	system('stty', '-echo') unless ($echoBack);
	chomp(my $input = <STDIN>);
	# added by anil on 30may2018 to replace spaces and tab in user input.
	$input =~ s/^[\s\t]+|[\s\t]+$//g;
	unless ($echoBack) {
		system('stty', 'echo');
		display('');
	}
	return $input;
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
# Subroutine			: getUserProfilePath
# Objective				: Build path to user profile info
# Added By				: Yogesh Kumar
#Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getUserProfilePath {
	return ("$servicePath/$Configuration::userProfilePath/$username");
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
	return getUserProfilePath().qq(/$Configuration::userProfilePaths{$_[0]});
}

#*****************************************************************************************************
# Subroutine			: getUserConfigurationFile
# Objective				: Build path to user configuration file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getUserConfigurationFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::userConfigurationFile");
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
#****************************************************************************************************/
sub getUserConfiguration {
	return %userConfiguration unless (defined $_[0]);

	unless(exists $userConfiguration{$_[0]}) {
		#display(["WARNING: $_[0] ", 'is_not_set_in_user_configuration']);
		traceLog($_[0]." is not set in user configuration");
		return 0;
	}
	return $userConfiguration{$_[0]};
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

#*****************************************************************************************************
# Subroutine			: getStorageUsed
# Objective				: This subroutine return the total storage used by the user
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStorageUsed {
	return $storageUsed;
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
		$userMenuChoice	=~ s/^[\s\t]+|[\s\t]+$//g;
		$choiceRetry++;
		if($userMenuChoice eq '') {
			display(['cannot_be_empty', '.', ' ', 'enter_again', '.']);
			checkRetryAndExit($choiceRetry);
		} elsif(!validateMenuChoice($userMenuChoice, 1, $maxChoice)) {
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
		if($userMenuChoice eq '') {
			last;
		} elsif(!validateMenuChoice($userMenuChoice, 1, $maxChoice)) {
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
	
	$tokenMessage = $Locale::strings{'please_login_account_using_login_and_try'};
	foreach my $opScript (keys %Configuration::idriveScripts) {
		$opHolder = '___' . $opScript . '___';
		$tokenMessage =~ s/$opHolder/$Configuration::idriveScripts{$opScript}/eg
	}
	return $tokenMessage;
}

#*****************************************************************************************************
# Subroutine			: getMachineOSDetails
# Objective				: This gets the name of Operating system with architecture
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getMachineOSDetails {
	chomp(my $uname = `uname -msr`);
	$Configuration::machineOS = $uname;
	return $uname;
}

#*****************************************************************************************************
# Subroutine			: getMachineUser
# Objective				: This gets the name of the user who executes the script
# Added By				: Sabin Cheruvattil
# Modified By			: Anil
#****************************************************************************************************/
sub getMachineUser {
	return $ENV{'LOGNAME'};
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
# Subroutine			: getAndValidate
# Objective				: This subroutine is used to take input ad ask for the retry option if it fails to validate.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getAndValidate {
	my $message = $_[0];
	my $fieldType = $_[1];
	my $isEchoEnabled = $_[2];
	my $isMandatory = (defined($_[3]) ? $_[3] : 1) ;		
	my ($userInput, $choiceRetry) = ('', 0);
	
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		display($message, 0);
		$userInput = getUserChoice($isEchoEnabled);
	
		$choiceRetry++;


		if(($userInput eq '') && (!$isMandatory)){
			display(['cannot_be_empty', '.', ' ', 'enter_again', '.', "\n"], 1);
			checkRetryAndExit($choiceRetry, 0);
		} 
		elsif(!validateDetails($fieldType, $userInput)) {
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
		if($email ne '' && !isValidEmailAddress($email)) {
			$invalidEmails .= qq($email, );
		}
	}
	if($invalidEmails) {
		#$invalidEmails =~ s/(?<!\w)//g;
		$invalidEmails =~ s/\s+$//;
		substr($invalidEmails,-1,1,".");
		display(['invalid_email_addresses_are_', $invalidEmails]);
		return 0;
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: getRemoteAccessTokenFile
# Objective				: Build path to accesstoken.txt file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteAccessTokenFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::accessTokenFile");
}

#*****************************************************************************************************
# Subroutine			: getRemoteAccessTokenFile
# Objective				: Read from or write to accesstoken.txt file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteAccessToken {
	my $atf = getRemoteAccessTokenFile();
	if (-f $atf and !-z $atf) {
		if (open(my $a, '<:encoding(UTF-8)', $atf)) {
				my $accessToken = <$a>;
				close($a);
				chomp($accessToken);
				return $accessToken;
		}
	}

	my $username = 'yogeshkumar';
	my $password = 'y0g3shkumar';

	my %params = (
		'host'   => $Configuration::idriveLoginCGI,
		'method' => 'GET',
		'json'   => 1, 
		'queryString'=> {
			'uid' => urlEncode($username),
			'pwd'  => urlEncode($password)
		}
	);

	my $response = request(%params);
	if (not $response->{STATUS}) {
		# TODO:ERROR handling
	}
	else {
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
	if (-f "$appPath/$Configuration::idriveScripts{$_[0]}") {
		return "$appPath/$Configuration::idriveScripts{$_[0]}";
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getRemoteManageIP
# Objective				: Read remote manage address
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getRemoteManageIP {
	return getUserConfiguration('REMOTEMANAGEIP');
}

#*****************************************************************************************************
# Subroutine			: getNotificationFile
# Objective				: Path to notification file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getNotificationFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::notificationFile");
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
	return 0;
}

#*****************************************************************************************************
# Subroutine			: getCrontabFile
# Objective				: Path to crontab data file
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getCrontabFile {
	return ("$servicePath/$Configuration::userProfilePath/$username/$Configuration::crontabFile");
}

#*****************************************************************************************************
# Subroutine			: getCrontab
# Objective				: Get crontab value
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getCrontab {
	my $title = shift || retreat('crontab_title_is_required');
	my $key   = shift;

	if (eval("exists \$crontab{$title}$key")) {
		return eval("\$crontab{$title}$key");
	}
	return 0;
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

	my $fileContent = '';
	if (open(my $fileHandle, '<:encoding(UTF-8)', $_[0])) {
		$fileContent = join('', <$fileHandle>);
		close($fileHandle);
		return $fileContent;
	}

	retreat(['unable_to_open_file', $_[0]]);
}

#*****************************************************************************************************
# Subroutine			: getStartAndEndEpochTime
# Objective				: To return the start and end date epoch time.
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getStartAndEndEpochTime {
	# $userChoice => 1) One week before, 2) Two week before, 3) One month before, 4) Given date range
	my $userOption 			= shift;
	my $currentTimeStamp 	= time();
	my $daysToSubstract 	= ($userOption == 1) ? 7 : ($userOption == 2) ? 14 : 30;
	my $startTimeStamp 		= $currentTimeStamp - ($daysToSubstract * 24 * 60 * 60);
	return ($startTimeStamp, $currentTimeStamp);
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
		my $evs = $dir."/".$_ ;
		my ($status, $msg) = verifyEVSBinary($evs);
		return 0 if(!$status); 		
		if ($duplicate) {
			copy($evs, getServicePath());
			chmod($Configuration::filePermission, getServicePath()."/".$_);
			chmod($Configuration::filePermission, $evs);
		}
	}
	return 1;
}

#------------------------------------------------- I -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: isFileLocked
# Objective				: Check if the file is locked or not
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub isFileLocked {
	my ($f) = @_;
	return 0 unless (-e $f);
	open(my $fh, ">>", $f) or return 1;
	unless (flock($fh, 2|4)) {
		close($fh);
		return 1;
	}
	close($fh);
	unlink($f);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: isUpdateAvailable
# Objective				: Check if latest version is available on the server
# Added By				: Yogesh Kumar
# Modified By			: Anil Kumar [27/04/2018]
#****************************************************************************************************/
sub isUpdateAvailable {
	return 0 if($0 =~ m/$Configuration::idriveScripts{'check_for_update'}/i);

	my $updateInfoFile = getUpdateVersionInfoFile();
	if (-f $updateInfoFile and !-z $updateInfoFile) {
		return 1;
	}
	else {
		my $check4updateScript = "$Configuration::perlBin '$appPath/check_for_update.pl' checkUpdate";
		my $updateAvailStats = `$check4updateScript 1>/dev/null 2>/dev/null &`;
		if (-f $updateInfoFile and !-z $updateInfoFile) {
			return 1;
		}
	}
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
# Subroutine			: inAppPath
# Objective				: Find a file in source codes path
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub inAppPath {
	my ($file) = @_;
	if (-e ("$appPath/$file")) { 
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
	my @pf = ($Configuration::idpwdFile, $Configuration::idenpwdFile,
		$Configuration::idpwdschFile);

	$userConfiguration{'ENCRYPTIONTYPE'} = '' unless defined $userConfiguration{'ENCRYPTIONTYPE'};
	if ($userConfiguration{'ENCRYPTIONTYPE'} eq 'PRIVATE') {
		push @pf, ($Configuration::idpvtFile, $Configuration::idpvtschFile);
	}

	my $status = 0;
	$username 	= '' unless defined $username;
	for (@pf) {
		my $file = ("$servicePath/$Configuration::userProfilePath/$username/$_");
		if (!-f $file or -z $file) {
			$status = 0;
			last;
		}
		$status = 1;
	}
	return $status;
}

#*****************************************************************************************************
# Subroutine			: isValidUserName
# Objective				: This subroutine helps to validate username
# Added By				: Anil Kumar
#****************************************************************************************************/
sub isValidUserName {
	my $validUserPattern = 1;
	#if((length($_[0]) < 4) || (length($_[0]) > 20))
	if(length($_[0]) < 4)
	{
		display(['username_must_contain_4_characters', '.',"\n"],1) ;
		$validUserPattern = 0;
	}
=beg	elsif ($_[0] =~ /^(?=.{4,20}$)(?!.*[_]{2})(?!\s+)[a-z0-9_]+$/){
		$validUserPattern = 1;
	}elsif(isValidEmailAddress($_[0])){
		$validUserPattern = 1;
	}else {
		display(['username_should_contain_specific_characters', '.',"\n"],1) ;
		$validUserPattern = 0;
	}
=cut
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
	return (length($_[0]) > 5 && length($_[0]) <= 50 && (lc($_[0]) =~ m/^[a-zA-Z0-9]+(\.?[\*\+\-\_\=\^\$\#\!\~\?a-zA-Z0-9])*\.?\@([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)(\.[a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+)*\.(?:([a-zA-Z0-9]+)|([a-zA-Z0-9]+[a-zA-Z0-9\-]*[a-zA-Z0-9]+))$/));
}

#------------------------------------------------- J -------------------------------------------------#
#------------------------------------------------- K -------------------------------------------------#

#------------------------------------------------- L -------------------------------------------------#

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
	my @columnNames = (['S.No.', 'Device Name', 'Device ID', 'OS', 'Date & Time', 'IP Address'], [8, 24, 24, 15, 22, 15]);
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
				
				if(($columnNames[1]->[$i] - length($displayData)) >= 0){
					$tableData .= $displayData;
					$tableData .= (' ') x ($columnNames[1]->[$i] - length($displayData)) if ($columnHeaderInfo[$i] eq 'nick_name'||'os');
				}
				else { 
					$tableData .= trimDeviceInfo($displayData,$columnNames[1]->[$i]) if($columnHeaderInfo[$i] eq 'nick_name'||'os');
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
	if($_[0] eq "backup") {
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
		
		if ($result[0]->{'STATUS'} eq 'FAILURE') {
			print "$result[0]->{'MSG'}\n";
			return 0;
		}
		elsif ($result[0]->{'STATUS'} eq 'SUCCESS') {
		
		$devices->[$slno -1]{'server_root'} = $result[0]->{'server_root'};
		$devices->[$slno -1]{'device_id'}   = $result[0]->{'device_id'};
		$devices->[$slno -1]{'nick_name'}   = $result[0]->{'nick_name'};
		
		#server root added by anil
			setUserConfiguration('SERVERROOT', $devices->[$slno -1]{'server_root'});
			setUserConfiguration('BACKUPLOCATION',
								($Configuration::deviceIDPrefix . $devices->[$slno -1]{'device_id'} . $Configuration::deviceIDPostfix .
									"#" . $devices->[$slno -1]{'nick_name'}));
			display([ "\n", 'your_backup_to_device_name_is', (" \"" . $devices->[$slno -1]{'nick_name'} . "\"")]);
			return 1;
		}
	}
	elsif ($_[0] eq 'restore') {
		setUserConfiguration('RESTOREFROM',
			($Configuration::deviceIDPrefix . $devices->[$slno -1]{'device_id'} . $Configuration::deviceIDPostfix .
			"#" . $devices->[$slno -1]{'nick_name'}));
		display([ "\n",'your_restore_from_device_is_set_to', (" \"" . $devices->[$slno -1]{'nick_name'} . "\"")]);
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
		if (open(my $fileHandle, '<:encoding(UTF-8)', $gsa)) {
			my $sa = <$fileHandle>;
			close($fileHandle);
			chomp($sa);
			if ($sa ne '') {
				$serverAddress = $sa;
				return 1;
			}
		}
	}
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
		if (open(my $s, '<:encoding(UTF-8)', $csf)) {
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
	my @af = split(/\/Helpers\.pm$/, $absFile);
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
		if (open(my $sp, '<:encoding(UTF-8)',
				("$appPath/" . $Configuration::serviceLocationFile))) {
			my $s = <$sp>;
			close($sp);
			chomp($s);
			if (-d $s) {
				$servicePath = $s;
				return 1;
			}
		}
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadUsername
# Objective				: Assign logged in user name to $username
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadUsername {
	my $cf = getCachedFile();
	if (-f $cf and !-z $cf) {
		if (open(my $u, '<:encoding(UTF-8)', $cf)) {
			$username = <$u>;
			close($u);
			chomp($username);
			return 1;
		}
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadUserConfiguration
# Objective				: Assign user configurations to %userConfiguration
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub loadUserConfiguration {
	my $ucf = getUserConfigurationFile();
	my $status = 1;
	map{if(!defined($userConfiguration{$_})){$userConfiguration{$_} = ''}} keys %Configuration::userConfigurationSchema;
	if (-f $ucf and !-z $ucf) {
		if (open(my $uc, '<:encoding(UTF-8)', $ucf)) {
			my @u = <$uc>;
			close($uc);
			map{my @x = split(/ = /, $_); chomp($x[1]); $x[1] =~ s/^\s+|\s+$//g; $userConfiguration{$x[0]} = $x[1];} @u;
			checkAndUpdateServerRoot(); #Added to check and update server root if it is empty
			proxyBackwardCompatability();
			$status = 0 unless (validateUserConfigurations());
		}
	}
	elsif(!defined($_[0])) {
		retreat('account_not_configured');
	}
	else {
		$status = 0
	}
	return $status;
}
#*****************************************************************************************************
# Subroutine			: loadNotifications
# Objective				: load user activities on certain modules like start/stop backup/restore, etc...
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadNotifications {
	my $nf = getNotificationFile();
	createNotificationFile() unless (-e $nf and !-z $nf);

	if (-e $nf) {
		if (open(my $n, '<:encoding(UTF-8)', $nf)) {
			my $nc = <$n>;
			close($n);
			if ($nc ne '') {
				%notifications = %{from_json($nc)};
			}
			return 1;
		}
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: loadCrontab
# Objective				: Load crontab data
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub loadCrontab {
	my $sf = getCrontabFile();
	if (-e $sf and !-z $sf) {
		if (open(my $s, '<:encoding(UTF-8)', $sf)) {
			my $sc = <$s>;
			close($s);
			if ($sc ne '') {
				%crontab = %{from_json($sc)};
			}
			return 1;
		}
	}
	return 0;
}

#------------------------------------------------- M -------------------------------------------------#
#------------------------------------------------- N -------------------------------------------------#

#------------------------------------------------- O -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: openEditor
# Objective				: This subroutine to view/edit the files using Linux editor
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub openEditor {
	my $action       = shift;
	my $fileLocation = shift;
	my $editorName = getEditor();
	my $editorHelpMsg = $editorName;
	if($editorName =~ /vi/){
		$editorHelpMsg = 'vi';
	} elsif($editorName =~ /nano/){
		$editorHelpMsg = 'nano';
	} elsif($editorName =~ /ee/){
		$editorHelpMsg = 'ee';
	} elsif($editorName =~ /emacs/){
		$editorHelpMsg = 'emacs';
	} elsif($editorName =~ /ne/){
		$editorHelpMsg = 'ne';
	} elsif($editorName =~ /jed/){
		$editorHelpMsg = 'jed';
	}
	
	display(["\n",'press_keys_to_close_'.$editorHelpMsg.'_editor'], 1) if($action eq 'edit');
	display(["\n",'press_keys_to_quit_'.$editorHelpMsg.'_editor'], 1) if($action eq 'view');
	display(["\n",'opening_file_to_'.$action,"\n"], 1);
	
	sleep(4);

	my $operationStatus = system "$editorName '$fileLocation'";
	if ($operationStatus == 0){
		display(["\n",ucfirst($Locale::strings{'file'}), qq( "$fileLocation" ),'edited_successfully',"\n"], 1) if($action eq 'edit');
	}else{
		display(["\n",'could_not_complete_operation',"Reason: $!\n"], 1);
	}
}

#------------------------------------------------- P -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: parseEVSCmdOutput
# Objective				: Parse evs response and return the same
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parseEVSCmdOutput {
	my @parsedEVSCmdOutput;
	if (defined($_[0]) and defined($_[1])) {
		$_[0] =~ s/""/" "/g;
		my $endTag = '\/>';
		$endTag = "><\/$_[1]>" if (defined($_[2]));
		
		my @x = $_[0] =~ /(<$_[1]) (.+?)($endTag)/sg;
	
		for (1 .. (scalar(@x)/3)) {
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
							($data{'message'} eq 'FAILURE' or
								$data{'message'} eq 'SUCCESS' or
								$data{'message'} eq 'ERROR')) {
				if ($data{'message'} eq 'ERROR') {
				
					$data{'STATUS'} = 'FAILURE';
				}
				else {
					$data{'STATUS'} = $data{'message'};
				}
			}
			else {
				$data{'STATUS'} = 'SUCCESS';
			}
			push @parsedEVSCmdOutput, \%data;
		}
	}

	unless (@parsedEVSCmdOutput) {
		$_[0] =~ s/connection established\n//g;
		chomp($_[0]);
		
		push @parsedEVSCmdOutput, {
			'STATUS' => 'FAILURE',
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
	if(defined ${$_[0]} and ${$_[0]} ne "") {
		my $evsOutput = ${$_[0]};
		#clearFile($evsOutput);
		my @evsArrLine = ();
		if ($parseDeviceList){
			if($evsOutput =~ /No devices found/){
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
		 		&Chomp(\$key);
				&Chomp(\$value);
				if ($parseDeviceList){
					my $subKey = $value.'_'.$attributeCount;
					$subKey = $value if(/(?:uid|device_id|server_root)/i);
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
	if($proxyValue eq "" and !$proxyIpValue) {
		setUserConfiguration('PROXYIP', '');
		setUserConfiguration('PROXYPORT', '');
		setUserConfiguration('PROXYUSERNAME', '');
		setUserConfiguration('PROXYPASSWORD', '');
		setUserConfiguration('PROXY', '');
		saveUserConfiguration() or retreat('failed');
	}
	elsif(!$proxyIpValue or ($proxyValue ne "" and $proxyIpValue eq "")) {
		my @val = split('@',$proxyValue);
		my @userInfo = split(':',$val[0]);
		my @serverInfo = split(':',$val[1]);
		$userInfo[0] = ($userInfo[0])?$userInfo[0]:'';
		$userInfo[1] = ($userInfo[1])?$userInfo[1]:'';
		setUserConfiguration('PROXYIP',$serverInfo[0]);
		setUserConfiguration('PROXYPORT',$serverInfo[1]);
		setUserConfiguration('PROXYUSERNAME',$userInfo[0]);		
		my $proxySIPPasswd = $userInfo[1];
		if($proxySIPPasswd ne ''){ 
			$proxySIPPasswd = trim($proxySIPPasswd);
			$proxySIPPasswd = encryptRAData($proxySIPPasswd);
		}
		setUserConfiguration('PROXYPASSWORD', $proxySIPPasswd);
		setUserConfiguration('PROXY', $userInfo[0].":".$proxySIPPasswd."@".$serverInfo[0].":".$serverInfo[1]);
		saveUserConfiguration() or retreat('failed');
	}
}
#------------------------------------------------- Q -------------------------------------------------#

#------------------------------------------------- R -------------------------------------------------#

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
	if ($servicePath ne '') { traceLog($_[0]); }
	display($_[0]) if(!defined($_[1]) or lc($_[1]) eq 'manual');
	
	if ($servicePath ne '') {
		rmtree("$servicePath/$Configuration::downloadsPath");
		rmtree("$servicePath/$Configuration::tmpPath");
	}
	
	die "\n";
}

#*****************************************************************************************************
# Subroutine			: request
# Objective				: Make a server request
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub request {
	my (%args) = @_;

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
				$ppwd = ($ppwd ne '')?decryptRAData($ppwd):$ppwd;
				foreach ($ppwd) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				$proxy .= (':' . $ppwd);
			}
		}
	}

	my $curl = "curl --fail -sk $proxy -L --max-time 15";

	if ($args{'data'}) {
		$curl .= (' -d \'' . buildQuery(%{$args{'data'}}) . '\'');
	}

	if ($args{'encDATA'}) {
		$curl .= (' -d \'' . $args{'encDATA'} . '\'');
	}

	if ($args{'host'}) {
		$curl .= (' ' . $args{'host'});
	}
	else {
		retreat('no_url_specified');
	}

	if ($args{'port'}) {
		$curl .= (':' . $args{'port'});
	}
	
	if ($args{'path'}) {
		$curl .= $args{'path'};
	}

	if ($args{'queryString'}) {
		$curl .= ('?\'' . buildQuery(%{$args{'queryString'}}) . '\'');
	}

	my $tmpErrorFile  = (getServicePath())?getServicePath()."/".$Configuration::errorFile:"/tmp/".$Configuration::errorFile;
	#print "\n CURL: $curl 2>>'$tmpErrorFile'\n\n";
	my $response = `$curl 2>>'$tmpErrorFile'`;
	Chomp(\$response);
	#traceLog("CURL-RESPONSE: $response");
	if ($? > 0 or (-e $tmpErrorFile and -s $tmpErrorFile)) {
		unless ($Configuration::callerEnv eq 'SCHEDULER') {
			if(-e $tmpErrorFile and -s $tmpErrorFile){
				if(!open(FH, "<", $tmpErrorFile)) {
					my $errStr = $Locale::strings{'failed_to_open_file'}.":$tmpErrorFile, Reason:$!";
					traceLog($errStr);
				}
				my $byteRead = read(FH, $response, $Configuration::bufferLimit);
				close FH;		
				Chomp(\$response);
			}
			unlink($tmpErrorFile) if(-e $tmpErrorFile);
			if (($response =~ /Could not resolve proxy|Failed to connect to .* port [0-9]+: Connection refused|Connection timed out|response code said error|407/)) {
				
				retreat(["\n", 'kindly_verify_ur_proxy']) if(defined($_[2]));
			
				display(["\n", 'kindly_verify_ur_proxy']);
				askProxyDetails() or retreat('failed due to proxy');
				return request(@_, "NoRetry");
				
				# saveUserConfiguration() or retreat('failed to save user configuration');
			}
			elsif ($response =~ /SSH-2.0-OpenSSH_6.8p1-hpn14v6|Protocol mismatch/) {
				retreat($response);
			}
		}
		
		return 0;
	}

	return {STATUS => SUCCESS, DATA => from_json($response)} if ($args{'json'});
	return {STATUS => SUCCESS, DATA => $response};
}

#*****************************************************************************************************
# Subroutine			: reCalculateStorageSize
# Objective				: Request IDrive server to re-calculate storage size
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub reCalculateStorageSize {
	my $calculateStorageSize = "$appPath/".$Configuration::idriveScripts{'utility'}." $username GETQUOTA";
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
#****************************************************************************************************/
sub runEVS {
	my $isErrorFile = 0;
	my $runInBackground = "";
	my $tempUtf8File = $utf8File;

	$isErrorFile     = 1 if(defined($_[1]));
	$runInBackground = "&" if(defined($_[2]));
	$tempUtf8File 	 = $_[3] if(defined($_[3]));
	
	my ($idevscmdout,$idevcmd) = ('')x 2;
	my $evsPath = getEVSBinaryFile();
	if(-e $evsPath) {
		
	$idevcmd = ("'$evsPath' --utf8-cmd='$tempUtf8File'");
	$idevscmdout = `$idevcmd 2>&1 $runInBackground`;
	my @errArr;	
	#if (($? > 0 or $idevscmdout =~/failed/i) and !$isErrorFile and $idevscmdout !~ /no version information available/) {
	if (($? > 0) and !$isErrorFile and $idevscmdout !~ /no version information available/) {
		my $msg = 'execution_failed';
		if (($idevscmdout =~ /\@ERROR: PROTOCOL VERSION MISMATCH on module ibackup/ or
					$idevscmdout =~ /Failed to validate. Try again/) and
				$userConfiguration{'DEDUP'} ne 'off') {
			setUserConfiguration('DEDUP', 'off');
			return runEVS($_[0]);
		}
		elsif ($idevscmdout =~ /\@ERROR: auth failed/ and
			$idevscmdout =~ /encryption verification failed/) {
			$msg = 'encryption_verification_failed';
		}
		elsif ($idevscmdout =~ /private encryption key must be between 4 and 256 characters in length/) {
			$msg = 'private_encryption_key_must_be_between_4_and_256_characters_in_length';
		}
		elsif ($idevscmdout =~ /account is under maintenance/) {
			$msg = 'account_is_under_maintenance';
		} elsif ($idevscmdout =~ /(failed to connect|Connection refused|407|Could not resolve proxy)/i) {
			$msg = 'kindly_verify_ur_proxy';
		} 
		push @errArr, {
			'STATUS' => 'FAILURE',
			'MSG'    => $msg
		};
		unlink($tempUtf8File);
		return @errArr;
	}

	unlink($tempUtf8File) if($runInBackground eq "");
	
	#Added by Senthil : 03-JULY-2018
	if($idevscmdout =~ /no version information available/){
		my @linesOfRes = split(/\n/,$idevscmdout);
		my $warningString = "no version information available";
		my @finalLines = grep !/$warningString/, @linesOfRes;
		$idevscmdout  = join("\n",@finalLines);
	}
	if ($idevscmdout eq '') {
		my $status = ($isErrorFile)?'FAILURE':'SUCCESS'; 
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
			'STATUS' => 'FAILURE',
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
	if(isRunningJob($pidPath)) {
		my $confMessage = "\n" . $Locale::strings{'changing_title'} . ' ' . $jobType . ' ' . $Locale::strings{'location_will_terminate'} . ' ';
		$confMessage 	.= $jobMode . ' ' . $jobType . ' ' . $Locale::strings{'in_progress'} . '... ' . $Locale::strings{'do_you_want_to_continue_yn'};
		my $choice = getAndValidate(['enter_your_choice'], "YN_choice", 1);
		if(($choice eq 'y')) {
			display([qq(\n$Locale::strings{'terminating_your_title'} $jobMode $jobType $Locale::strings{'job'}. $Locale::strings{'please_wait_title'}...)]);
			my $jobTerminationScript = getScript('job_termination');
			my $jobTermCmd = "$Configuration::perlBin '$jobTerminationScript' manual_$jobType $username";
			my $res = system($jobTermCmd);
			if($res != 0) {
				traceLog(qq($Locale::strings{'error_in_terminating'} $jobMode $jobType $Locale::strings{'job'}.));
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
	createUTF8File('NICKUPDATE',$_[1],($Configuration::deviceIDPrefix .$_[0]->{'device_id'} .$Configuration::deviceIDPostfix)) or retreat('failed_to_create_utf8_file');

	my @result = runEVS('item');
	if ($result[0]->{'STATUS'} eq 'SUCCESS') {
		#<Deepak> remove below line 
		$_[0]->{'nick_name'} = $result[0]->{'nick_name'};
		return 1;
	}
	return 0;
}

#------------------------------------------------- S -------------------------------------------------#

#*****************************************************************************************************
# Subroutine Name         : sendMail
# Objective               : sends a mail to the user in ase of successful/canceled/ failed scheduled backup/restore.
# Added By                : Dhritikana
#********************************************************************************************************************
sub sendMail {
	my $taskType = $_[0];
	my $jobType  = $_[1];
	if($taskType eq "manual") {
		return;
	}
	my $mailNotifyFlagFile = $Configuration::jobRunningDir."/".$jobType."mailNotify.txt";
	my ($notifyFlag, $notifyEmailIds,$configEmailAddress) = undef;
	if(!-e $mailNotifyFlagFile) {
		return;
	} else {
		unless(open NOTIFYFILE, "<", $mailNotifyFlagFile) {
			traceLog($Locale::strings{'failed_to_open_file'}.": $mailNotifyFlagFile, Reason $!", __FILE__, __LINE__);
			return;
		}
		
		my @notifyData = <NOTIFYFILE>;
		chomp(@notifyData);
		$notifyFlag = $notifyData[0];
		$notifyEmailIds = $notifyData[1];
		close(NOTIFYFILE);
		
		if($notifyFlag eq "DISABLED") {
			return;
		}

		$configEmailAddress = $notifyEmailIds;
	}
	
	my $finalAddrList = getFinalMailAddrList($configEmailAddress);
	if($finalAddrList eq "NULL") {
		return;
	} 	
	my $userName      = getUsername();
	my $pData = &getPdata("$userName");
	if($pData eq ''){
		traceLog($Locale::strings{'failed_to_send_mail'}.$Locale::strings{'password_missing'}, __FILE__, __LINE__);
		return;
	}
	
	my $sender = "support\@".$Configuration::servicePathName.".com";
	my $content = "";
	my $subjectLine = $_[2];
	my $operationData = $_[3];
	my $backupRestoreFileLink = $_[4];
	
	$content = "Dear $Configuration::appType User, \n\n";	
	$content .= "Ref: Username - $userName \n";
	$content .= $Configuration::mailContentHead;
	$content .= $Configuration::mailContent;

	if ($operationData eq 'NOBACKUPDATA'){
		$content .= qq{ Unable to perform backup operation. Your backupset file is empty. To do backup again please fill your backupset file.Your backupset file location is "$backupRestoreFileLink".};
	}elsif($operationData eq 'NORESTOREDATA'){
		$content .= qq{ Unable to perform restore operation. Your restoreset file is empty. To do restore again please fill your restoreset file.Your restoreset file location is "$backupRestoreFileLink".};
	}

	$content .= "\n\nRegards, \n";
	$content .= "$Configuration::appType Support.\n";
	$content .= "Version ".$Configuration::version;
	
	#URL DATA ENCODING#
	foreach ($userName,$pData,$finalAddrList,$subjectLine,$content) {
		$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	}
	
	my $data = 'username='.$userName.'&password='.$pData.'&to_email='.$finalAddrList.'&subject='.$subjectLine.'&content='.$content;
	#`curl -d '$data' '$PATH' &>/dev/nul` or print $tHandle "$linefeed Couldn't send mail. $linefeed";
	my $curlCmd = formSendMailCurlcmd($data);
	
	my $sendMailMsg = `$curlCmd`;
	open (NOTIFYFILE, ">>", $mailNotifyFlagFile) or traceLog($Locale::strings{'failed_to_open_file'}.": $mailNotifyFlagFile, Reason $!", __FILE__, __LINE__) and return;
	#print NOTIFYFILE $sendMailMsg;
	close(NOTIFYFILE);
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
	$totalStorage = getHumanReadableSizes($_[0]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setStorageUsed
# Objective				: Save storage used space of the current logged in user to $storageUsed
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setStorageUsed {
	$storageUsed = getHumanReadableSizes($_[0]);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: setUserConfiguration
# Objective				: Set user configuration values
# Added By				: Yogesh Kumar
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
			$isNothingFound = 0;
			$userConfiguration{$keystring} = $data->[$i]{$key};
		}
	}
	unless ($isNothingFound){
		$Configuration::isUserConfigModified = 1;
		return 1;
	}
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
		createDir(getUsersInternalDirPath('user_info')) if(!-d getUsersInternalDirPath('user_info'));
		
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
#****************************************************************************************************/
sub saveUserConfiguration {
	return 1 unless ($Configuration::isUserConfigModified);

	my $ucf = getUserConfigurationFile();
	return 0 unless (validateUserConfigurations());
	if (open(my $fh, '>', $ucf)) {
		for my $key (keys %Configuration::userConfigurationSchema) {
			print $fh "$key = ";
			print $fh $userConfiguration{$key};
			print $fh "\n";
		}
		close($fh);

		# if (loadNotifications()) {
			# my $randChars;
			# $randChars .= sprintf("%x", rand 16) for 1..9;
			# setNotification('user_settings', $randChars);
			# saveNotifications();
		# }
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
		} elsif(!-w $restoreLocation){
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
	saveUserConfiguration();
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
	if($choice eq "y") {
		
		if (getUserConfiguration('DEDUP') eq 'on') {
			display(["\n",'loading_your_account_details_please_wait',"\n"],1);
			
			my @devices = fetchAllDevices();
			if ($devices[0]{'STATUS'} eq 'FAILURE') {
				if ($devices[0]{'MSG'} =~ 'No devices found') {
					retreat('failed');
				}
			}
			elsif ($devices[0]{'STATUS'} eq 'SUCCESS') {
				linkBucket('restore', \@devices) or retreat("Please try again.");
				return 1;
			}
		}
		else {
			display(['enter_your_restore_from_location_optional', ": "], 0);
			my $bucketName = getUserChoice();
			if($bucketName ne ""){
				display(['Setting up your restore from location...'], 1);
				if(substr($bucketName, 0, 1) ne "/") {
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
# Subroutine			: shiftString
# Objective				: Re-arrange encrypted data
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub shiftString {
	my $data         = $_[0];
	my $shiftRight   = $_[1] or 0;
	my $stringLength = length $data;

	my $s = '';
	my $x;
	my $xlength;
	for (my $i = 0; $i < int($stringLength/4); $i++) {
		$x = substr($data, ($i * 4), 4);
		$xlength = length $x;
		if ($shiftRight) {
			$s .= substr($x, 3, 1) if ($xlength >= 4);
			$s .= substr($x, 0, 3);
		}
		else {
			$s .= substr($x, 1);
			$s .= substr($x, 0, 1) if ($xlength >= 1);
		}
	}

	return $s;
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
		
		if ($devices[0]{'STATUS'} eq 'FAILURE') {
			if ($devices[0]{'MSG'} =~ 'No devices found') {
				return createBucket();
			} else{
				display($devices[0]{'MSG'},1);
			}
		}
		elsif ($devices[0]{'STATUS'} eq 'SUCCESS') {
			findMyDevice(\@devices) or displayOptions(\@devices) or retreat('failed');
			
			return 1;
		}
	}
	elsif (getUserConfiguration('DEDUP') eq 'off') {
		#my $backupLoc = validateBackupLoction();
		my $backupLoc = getAndValidate(["\n", 'enter_your_backup_location_optional',": "], "backup_location", 1);
		if($backupLoc eq '') {
			$backupLoc = $Configuration::hostname;
		}
	
		display('setting_up_your_backup_location',1);
		unless ($backupLoc) {
			$backupLoc = "/".$Configuration::hostname;
		}
		createUTF8File('CREATEDIR', $backupLoc) or
			retreat('failed_to_create_utf8_file');
		my @responseData = runEVS('item');
		if($responseData[0]->{'STATUS'} eq 'SUCCESS' or ($responseData[0]->{'STATUS'} eq 'FAILURE' and $responseData[0]->{'MSG'} =~ /file or folder exists/)){
			setUserConfiguration('BACKUPLOCATION', $backupLoc);
			display(['your_backup_to_device_name_is',(" \"" . $backupLoc . "\".")]);
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
	if (exists $notifications{$_[0]}) {
		$notifications{$_[0]} = $_[1];
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
		print $fh to_json($_[0] or \%notifications);
		close($fh);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: setCrontab
# Objective				: set crontab value to crontab
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub setCrontab {
	my $title = shift || retreat('crontab_title_is_required');
	my $key   = shift;
	my $value = shift;

	if (eval("exists \$crontab{$title}$key")) {
		eval("\$crontab{$title}$key = '$value'");
		return 1;
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
		print $fh to_json($_[0] or \%crontab);
		close($fh);
		return 1;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: selectLogsBetween
# Objective				: select logs files between given two dates
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub selectLogsBetween {
	my %logStat = ();
	my %logFilenames = ();

	unless (defined($_[1]) and defined($_[2])) {
		retreat('start_and_end_dates_are_required');
	}

	if (defined($_[3]) and -f $_[3]) {
		%logFilenames = %logStat = %{from_json(
			'{' .
			substr(getFileContents($_[3]), 1) .
			'}'
		)};
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
#****************************************************************************************************/
sub trim { 
	my $s = shift; 
	$s =~ s/^\s+|\s+$//g; 
	return $s;
}

#*****************************************************************************************************
# Subroutine      : traceLog
# Objective       : Trace log method
# Added By        : Sabin Cheruvattil
# Modified By     : Yogesh Kumar
#****************************************************************************************************/
sub traceLog {
	my $message = shift;
	my $msg = "";
	if (reftype(\$message) eq 'SCALAR') {
		$message = [$message];
	}
	for my $i (0 .. $#{$message}) {
		if (exists $Locale::strings{$message->[$i]}) {
			$msg .= $Locale::strings{$message->[$i]};
		}
		else {
			$msg .= $message->[$i];
		}
	}
	my $trace = $msg;
	
	my ($package, $filename, $line) = caller;
	my $traceLog = getTraceLogPath();
	my $traceDir = dirname($traceLog);
	
	if(!-d $traceDir) {
		my $mkRes = `mkdir -p '$traceDir' 2>&1`;
		chomp($mkRes);
		if($mkRes !~ /Permission denied/) {
			changeMode(getServicePath());
		}
	}
	
	if(-e $traceLog && -s $traceLog >= $Configuration::maxLogSize) {
		my $tempTrace = qq('$traceLog) . qq(_) . localtime() . qq(');
		`mv $traceLog $tempTrace`;
	}
	
	if(!-e $traceLog) {
		writeToTrace($traceLog, qq($Configuration::appType ) . ucfirst($Locale::strings{'username'}) . qq(: ) . 
					(getUsername() or ucfirst($Locale::strings{'no_logged_in_user'})) . qq( \n));
		chmod $Configuration::filePermission, $traceLog;
	}
	
	my @files 			= glob($traceLog . qq(_*));
	my $remFileCount 	= scalar(@files) - 5;
	while($remFileCount > 0) {
		unlink pop(@files);
		$remFileCount--;
	}

	chomp($trace);
	my $logContent 		= qq([) . basename($filename) . qq(][Line: $line] $trace\n);
	writeToTrace($traceLog, $logContent);
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
			return 0
	}
	return 1;
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

	my $uniqueID 	 = getMachineUID();
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
	
	my $res = request(%params);
	if($res){
		if($res->{DATA} =~ /Error:/){
			traceLog("Failed to update user detail: ".$res->{DATA}."\n") if($enabled ==1);
			return 0;
		}	
		return 1 if($res->{DATA} =~ /success/i);
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
	my $status = 'SUCCESS';
	
	if((!-e $filePath) or (!-s $filePath)) {
		$errStr = "\n".$Locale::strings{'your_'.lc($_[0]).'set_is_empty'};
	} 
	elsif(-s $filePath > 0 && -s $filePath <= 50){
		if(!open(OUTFH, "< $filePath")) {
			$errStr = $Locale::strings{'failed_to_open_file'}.":$filePath, Reason:$!"; 		
		}
		else{
			my $buffer = <OUTFH>;
			close(OUTFH);
			
			Chomp(\$buffer);
			if($buffer eq ''){
				$errStr = "\n".$Locale::strings{'your_'.lc($_[0]).'set_is_empty'};
			}
		}
	}
	
	$status = 'FAILURE'	if($errStr ne '');
	return ($status,$errStr);
}

#*****************************************************************************************************
# Subroutine			: validateChoiceOptions
# Objective				: This subroutine validates choice options y/n
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub validateChoiceOptions {
	my $choice = shift;
	if(lc($choice) eq 'y' || lc($choice) eq 'n') {
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
	return 0 if($choice !~ m/^[0-9]{1,3}$/);
	return 1 if($choice >= $lowerRange && $maxRange >= $choice);
	return 0;
}

#*****************************************************************************************************
# Subroutine			: validateUserConfigurations
# Objective				: Validate user provided values
# Added By				: Yogesh Kumar
# Modified By           : Senthil Pandian
#****************************************************************************************************/
sub validateUserConfigurations {
	for my $key (keys %Configuration::userConfigurationSchema) {
		if ($Configuration::userConfigurationSchema{$key}{'required'} and
			($userConfiguration{$key} eq '')) {
			traceLog($key." is misssing." );
			#display("user_config_" . lc($key)  . "_not_found");
			return 0;
		}
		if (($Configuration::userConfigurationSchema{$key}{'type'} eq 'dir') and
			($userConfiguration{$key} ne '') and (!-d $userConfiguration{$key})) {
			traceLog($key." is misssing." );
			#display("user_config_" . lc($key)  . "_not_found");
			return 0;
		}
		if (($Configuration::userConfigurationSchema{$key}{'default'} ne '') and
			($userConfiguration{$key} eq '')) {
			$userConfiguration{$key} = $Configuration::userConfigurationSchema{$key}{'default'};
		}
	}
	# Validating SERVERROOT value if dedup is ON
	if($userConfiguration{'DEDUP'} eq 'on'){
		if ($userConfiguration{'SERVERROOT'} eq '') {
			traceLog("SERVERROOT is misssing." );
			#display("user_config_" . lc('SERVERROOT')  . "_not_found");
			return 0;
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
		my $test = $Locale::strings{'unable_to_find'} . $evs;
		return (0, $test);
	}

	chmod(0777, "$evs");
	unless(-x "$evs") {
		return (0, $Locale::strings{'does_not_have_execute_permission'} .$evs);
	}
	
	my $output = `'$evs' -h 2>/dev/null`;
	
	if ($? > 0) {
		return (0, "EVS execution error:".$?);
	}
	return (1, "");
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
#****************************************************************************************************/
sub validatePercentage {
	my $percentage = shift;
	if($percentage !~ m/^[0-9]{1,3}$/ or !($percentage>0 and $percentage<=100)){
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
	if((length($_[0]) < 6) || (length($_[0]) > 20)) {
		display(['password_should_be_at_least_6_20_characters',"\n"],1) ;
		return 0;
	} elsif($_[0] =~ /^(?=.{6,20}$)(?!.*\s+.*)(?!.*[\:\\]+.*)/){
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
#****************************************************************************************************/
sub validateDetails {
	my $fieldType = $_[0];
	my $value = $_[1];
	
	if($fieldType eq "username"){
		return 0 unless(isValidUserName($value));
	}
	elsif($fieldType eq "password"){
		return 0 unless(validatePassword($value));
	}
	elsif($fieldType eq "private_key") {
		return 0 unless(validatePvtKey($value));
	}
	elsif($fieldType eq "config_private_key") {
		return 0 unless(validateConfPvtKey($value));
	}
	elsif($fieldType eq "single_email_address") {
		unless(isValidEmailAddress($value)) {
			return 1 if($value eq "");
			display(['invalid_single_email_address'], 1);
			return 0 ;
		}
	}
	elsif($fieldType eq "email_address") {
		return 0 unless(getInvalidEmailAddresses($value));
	}
	elsif($fieldType eq "service_dir") {
		return 0 unless(validateServiceDir($value));
	}
	elsif($fieldType eq "YN_choice") {
		unless(validateChoiceOptions($value)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif($fieldType eq "contact_no") {
		return 0 unless(validateContactNo($value));
	}
	elsif($fieldType eq "ticket_no") {
		return 0 unless(validateUserTicket($value));
	}
	elsif($fieldType eq "ipaddress") {
		return 0 unless(validateIPaddress($value));
	}
	elsif($fieldType eq "port_no") {
		return 0 unless(validatePortNumber($value));
	}
	elsif($fieldType eq "percentage_for_cleanup") {
		return 0 unless(validatePercentage($value));
	}
	elsif($fieldType eq "bw_value") {
		unless(validateBandWidthValue($value, 1, 100)){
			display(['invalid_choice',"\n"],1);
			return 0;
		}
	}
	elsif($fieldType eq "backup_location") {
		return 0 unless(validateBackupLoction($value));
	}
	elsif($fieldType eq "non_empty") {		# no need to check the condition, but added for a safer purpose
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
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validateBackupLoction {
	my $bucketName = $_[0];
	if($bucketName eq '') {
		$bucketName = $Configuration::hostname;
		display(['considering_default_backup_location',"\"$bucketName\""], 1);
		return 1;
	}elsif(length($bucketName) > 65) {
		display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_be_one_to_sixty_five_characters'], 1);
		return 0;
	}elsif($bucketName =~ /^[a-zA-Z0-9_-]*$/) {
		$bucketName = $bucketName;
		return 1;
	}else {
		display(['invalid_backup_location', "\"$bucketName\". ", 'backup_location_should_contain_only_letters_numbers_space_and_characters'], 1);
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
	$dir = $dir ."/" if($checkPath ne '/');
	my $newServiceDir = $dir."idrive/";
	#print "new: $dir ==== old: $oldServiceDir \n \n ";
	if(!-d $dir) {
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
	elsif($newServiceDir eq $oldServiceDir) {
		display(["\n",'invalid_location',". ",'Reason','Existing service directory is as same as the new',"\n"],1);
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
	if($reportUserContact eq ""){
		return 1 ;
	}elsif(length($reportUserContact) < 5 || length($reportUserContact) > 20) {
		display(['invalid_contact_number', '. ', 'contact_number_between_5_20', '.',"\n"]);
		return 0;
	} elsif($reportUserContact ne '' && ($reportUserContact !~ m/^\d{5,20}$/)) {
		display(['invalid_contact_number', '. ', 'contact_number_only_digits', '.',"\n"]);
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
	
	if($ticketNo eq ""){
		return 1 ;
	}elsif(length($ticketNo) < 5 || length($ticketNo) > 30) {
		display(['invalid_ticket_number', '. ', 'ticket_number_between_5_30', '.',"\n"]);
	} elsif($ticketNo ne '' && ($ticketNo !~ m/^[a-zA-Z0-9]{5,30}$/)) {
		display(['invalid_ticket_number', '. ', 'ticket_number_only_alphanumerics', '.',"\n"]);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: validatePvtKey
# Objective				: This subroutine is used to validate private key pattern
# Added By				: Anil Kumar
#****************************************************************************************************/
sub validatePvtKey {
	my $value = $_[0];
	if(length($value) < 4)
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
	if(length($value) < 6 || length($value) > 250)
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

#------------------------------------------------- W -------------------------------------------------#

#*****************************************************************************************************
# Subroutine			: writeToTrace
# Objective				: This subroutine writes to log
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub writeToTrace {
	if(open LOG_TRACE_HANDLE, ">>", $_[0]){
		my $date        	= strftime "%Y/%m/%d %H:%M:%S", localtime;
		my $logContent 		= qq([$date][) . getMachineUser() . qq(]$_[1]);
		print LOG_TRACE_HANDLE $logContent;
		close(LOG_TRACE_HANDLE);
	}
}

#------------------------------------------------- X -------------------------------------------------#
#------------------------------------------------- Y -------------------------------------------------#
#------------------------------------------------- Z -------------------------------------------------#
1;
