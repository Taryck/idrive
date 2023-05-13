#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to analyze the speed of Backup and send error report from user machine.
#
# Created By: Anil Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;

#need to change to 200MB for production release
use constant SPEED_TEST_FILE_SIZE => "10M";

require Constants;
$SIG{INT}  = \&cancelProcess;
$SIG{TERM} = \&cancelProcess;
$SIG{TSTP} = \&cancelProcess;
$SIG{QUIT} = \&cancelProcess;
my ($testFileName, $speedTestErrorFile) = ('') x 2;
my $speedTestScriptURL = "https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py";
my $speedTestWebURL    = "https://www.speedtest.net/";

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Senthil pandian
#****************************************************************************************************/
sub init {
	system(Common::updateLocaleCmd("clear"));
	checkVersionInfo() if($AppConfig::appType eq 'IDrive');

	Common::loadAppPath() or Common::retreat('Failed to load source Code path');
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::loadUsername() or Common::retreat('login_&_try_again');
	Common::isLoggedin() or Common::retreat('login_&_try_again');
	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if($errorKey > 1);
	Common::displayHeader();
	displayDescription();

	my $tempBackupsetFilePath   = Common::getUserProfilePath()."/tempBackupsetFile.txt";
	$speedTestErrorFile = Common::getUserProfilePath().'/speedTestError.txt';
	$testFileName = "speedTest.txt_".time;

	my $msg = Common::getStringConstant('can_we_upload_a_sample_file_for_speed_test_analysis');
	$msg =~ s/SPEED_TEST_FILE/$testFileName/;
	Common::display(["\n", $msg, "\n"], 0);
	my $userOpt = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	unless(lc($userOpt) eq 'y'){
		Common::display(["\n", 'aborting_the_operation', "\n"], 1);
		exit;
	}

	# $testFileName = checkItemStatus();
	$msg = Common::getStringConstant('creating_the_speed_test_file_for_backup');
	$msg =~ s/SPEED_TEST_FILE/$testFileName/;
	Common::display(["\n", $msg], 1);
	my $backupFileList   = $tempBackupsetFilePath;
	my $testFile  = Common::getUserProfilePath()."/".$testFileName;
	generateFileForBackup($testFile);
	Common::display(["\"$testFileName\"", " ", 'created_successfully'], 1);

	my $evsResult = speedTestViaEVS($backupFileList);
	deleteTestFileFromIDrive($testFileName);
	my $speedtesnetResult = speedTestViaSpeedtestnet();

	$evsResult .= "\n";
	$evsResult .= Common::getStringConstant('speed_test_result_via_speed_test_net').$speedtesnetResult;

	Common::display(["\n\n",$evsResult], 1);

	my $ticketID  = getUserTicketID();
	if($ticketID) {
		my $userEmail = getReportUserEmails();
		sendReportMail($ticketID,$evsResult,$userEmail);
	}
	unlink($testFile);
}

#********************************************************************************
# Subroutine			: displayDescription
# Objective				: This method is used to display description about the file to user.
# Added By				: Anil Kumar
#********************************************************************************
sub displayDescription {
	my $description = "Description: \n\n";
	$description .= Common::getStringConstant('description_for_speed_test');
	$description .= "\n";
	Common::display($description, 1);
}

#********************************************************************************
# Subroutine			: checkVersionInfo
# Objective				: This method is used to check the user scripts version.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#********************************************************************************
sub checkVersionInfo {
	my $version = Constants->CONST->{'ScriptBuildVersion'};
	Common::retreat(["\n", 'please_update_your_script_to_latest_version', "\n"], 1) unless(Common::versioncompare('2.16', $version) == 2);
}

#********************************************************************************
# Subroutine			: checkItemStatus
# Objective				: This is to check whether the test file is already exist in
#							user account and change the file name accordingly to avoid the file sync.
# Added By				: Anil Kumar
#********************************************************************************
sub checkItemStatus {

	Common::display(["\n", 'creating_the_speed_test_file_for_backup'], 1);

	my $isDedup  	   = Common::getUserConfiguration('DEDUP');
	my $backupLocation = Common::getUserConfiguration('BACKUPLOCATION');
	   $backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
	my $remoteFolder = "*speedTestFile.txt*";
	my $strReplace = "";

	my $searchDir 	   = Common::getUserProfilePath();
	my $tempSearchUTFpath = $searchDir.'/'.$AppConfig::utf8File;
	my $tempEvsOutputFile = $searchDir.'/'.$AppConfig::evsOutputFile;
	my $tempEvsErrorFile  = $searchDir.'/'.$AppConfig::evsErrorFile;

	if($isDedup eq 'off'){
		$strReplace = $backupLocation."/speedTestFile.txt";
	} else {
		$strReplace = "/speedTestFile.txt";
	}

START:
	Common::createUTF8File(['SEARCHALL', $tempSearchUTFpath], $tempEvsOutputFile, $tempEvsErrorFile, $remoteFolder);
	my @responseData = Common::runEVS('item', 1, 1, $tempSearchUTFpath);

	while(1){
		if((-e $tempEvsOutputFile and -s $tempEvsOutputFile) or  (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
			last;
		}
		sleep(2);
		next;
	}
	if((-z $tempEvsOutputFile) and (!-z $tempEvsErrorFile)) {
		my $buffer = Common::getFileContents($tempEvsErrorFile);
		if(Common::checkErrorAndUpdateEVSDomainStat($buffer)) {
			Common::loadServerAddress();
			unlink($tempEvsErrorFile);
			goto START;
		}
		print "\n\n Search Error \n\n";
	}
	unlink($tempSearchUTFpath) if(-f $tempSearchUTFpath);

	my @fileList =();
	my ($buffer,$lastLine) = ("") x 2;
	my $count = 0;
	while(1){
		if(-e $tempEvsOutputFile){
			my $fileSize = -s $tempEvsOutputFile;
			my $fh;
			if(open($fh, "<", $tempEvsOutputFile) and read($fh, $buffer, $fileSize)) {
				close($fh);
			}
		}

		my @resultList = split /\n/, $buffer;
		foreach my $tmpLine (@resultList){
			my %fileName = Common::parseXMLOutput(\$tmpLine);
			if($tmpLine =~ /fname/) {
				my $temp = $fileName{'fname'};
				# print "\nfile name:: $temp\n";
				$temp =~ s/$strReplace//g;
				if ($temp =~ /^\d+?$/) {
					$count = $temp if ($count < $temp);
				}
			}
		}
		last;
	}

	my $fileName .= "speedTestFile.txt".($count + 1);
	unlink($tempEvsOutputFile);
	unlink($tempEvsErrorFile);
	return  $fileName;
}

#********************************************************************************
# Subroutine			: generateFileForBackup
# Objective				: This is to create a temp file and create backupset file for new backup.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#********************************************************************************
sub generateFileForBackup {
	my $testFile  = $_[0];
	my $tempBackupsetFilePath  = Common::getUserProfilePath()."/tempBackupsetFile.txt";

	# need to update size to 200 MB for production release.
	my $cmdToCreateFile = "dd if=/dev/urandom of='$testFile' bs=".SPEED_TEST_FILE_SIZE." count=1 2>/dev/null";
	$cmdToCreateFile = Common::updateLocaleCmd($cmdToCreateFile);
	`$cmdToCreateFile`;

	if(open(my $fh, ">", $tempBackupsetFilePath)){
		print $fh $testFileName;
		close($fh);
	} else {
		Common::retreat(['failed_to_open_file',":$tempBackupsetFilePath","\n\n"]);
	}
	return $tempBackupsetFilePath;
}

#********************************************************************************
# Subroutine			: getUserTicketID
# Objective				: Get user's Ticket ID
# Added By				: Senthil Pandian
# Modified By			: Sabin Cheruvattil
#********************************************************************************
sub getUserTicketID {
	Common::display(["\n", 'do_you_want_to_send_the_speed_test_summary', "\n"], 0);
	my $displayChoice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	if(lc($displayChoice) eq 'y'){
		# my $ticketno = Common::getAndValidate(['Please enter the ticket number here', ' ', '_optional_', ': '], 'ticket_no', 1, 0);
		my $ticketno = Common::getAndValidate(["\n", 'please_enter_ticket_number_here', ': ',"\n\t"], 'ticket_no', 1, 0, 1);
		return $ticketno;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: speedTestViaEVS
# Objective				: Get the result of evs speed test.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub speedTestViaEVS {
	my $backupUTFpath  			= Common::getUserProfilePath()."/".$AppConfig::utf8File."_speed";
	my $evsOutputFile  			= Common::getUserProfilePath()."/".$AppConfig::evsOutputFile;
	my $evsErrorFile   			= Common::getUserProfilePath()."/".$AppConfig::evsErrorFile;
	my $isDedup  	   			= Common::getUserConfiguration('DEDUP');
	my $bwPath     	   			= Common::getUserProfilePath()."/bw.txt";
	my $backupLocation 			= "";

	my $tempBackupsetFilePath   = $_[0];
	my ($fh,$buffer,$fileSize);

	Common::createUpdateBWFile();
	Common::display(["\n",'starting_backup'], 1);
	if($isDedup eq 'off'){
		$backupLocation 	= Common::getUserConfiguration('BACKUPLOCATION');
	}

	Common::createUTF8File(['BACKUP',$backupUTFpath],$tempBackupsetFilePath,$bwPath,Common::getUserProfilePath()."/",$evsOutputFile,$evsErrorFile,
			'/'.Common::getUserProfilePath()."/",$backupLocation) or Common::retreat('failed_to_create_utf8_file');

	# my $reportMsg = "Bandwidth Throttle:\n===================\n";

	if(-e $bwPath){
		$fileSize = -s $bwPath;
		if(open($fh, "<", $bwPath) and read($fh, $buffer, $fileSize)) {
			close($fh);
			# $reportMsg .= "Bandwidth throttle:".$buffer."\n";
        }
	}

	my $backupStartTimeSec = time();
	my $backupStartTime = localtime $backupStartTimeSec;
	# $reportMsg .= "\t".$backupStartTime." \n\n";

	Common::display(['backup_in_progress'], 1);
	my @responseData = Common::runEVS('item');

	my $backupEndTimeSec = time();
	my $backupEndTime = localtime $backupEndTimeSec;

=beg
	if(-e $evsOutputFile){
		$fileSize =  -s $evsOutputFile;
        if(open($fh, "<", $evsOutputFile) and read($fh, $buffer, $fileSize)) {
			close($fh);
			$reportMsg .= "Backup Output:".$buffer."\n\n";
        }
		unlink($evsOutputFile);
	}
=cut

	Common::display(['backup_has_been_completed'], 1);
	my $idriveRes = '';
	if(-e $evsErrorFile and -s $evsErrorFile){
		$fileSize =  -s $evsErrorFile;
        if(open($fh, "<", $evsErrorFile) and read($fh, $buffer, $fileSize)) {
			close($fh);
			# $reportMsg .= "Backup Error:".$buffer."\n";
        }
	} else {
        # $reportMsg .= "Speed test result from IDrive:\n============================\n";
        my $time = $backupEndTimeSec - $backupStartTimeSec;
        my $size = 10485760/1048576;
        $idriveRes = ($size/$time)*8;
        $idriveRes = substr($idriveRes,0,4);
        # $reportMsg .= "Upload speed: ".$res." Mbit/s\n\n";
    }
	unlink($evsErrorFile);
	unlink($evsOutputFile);

	my $reportMsg = "Speed Test Summary:\n===================\n";
	$reportMsg   .= "Speed test result with IDrive: [Upload speed: ".$idriveRes." Mbit/s]\n";
	$reportMsg   .= "[Settings used:]\n";
	$reportMsg   .= "Bandwidth throttle:".$buffer."\n";
	$reportMsg   .= "Backup Start Time:".$backupStartTime."\n";
	$reportMsg   .= "Backup End Time:".$backupEndTime."\n";	
	return $reportMsg;
}

#*****************************************************************************************************
# Subroutine			: deleteTestFileFromIDrive
# Objective				: Delete the test file uploaded from user account.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub deleteTestFileFromIDrive {
	my $evsOutputFile  			= Common::getUserProfilePath()."/".$AppConfig::evsOutputFile;
	my $evsErrorFile   			= Common::getUserProfilePath()."/".$AppConfig::evsErrorFile;
	my $isDedup  	   			= Common::getUserConfiguration('DEDUP');
	my $backupLocation 			= Common::getUserConfiguration('BACKUPLOCATION');
	my $tempBackupsetFilePath   = Common::getUserProfilePath()."/tempBackupsetFile.txt";
	my $filename = $_[0];

	my $msg = Common::getStringConstant('deleting_speed_test_file_from_your_account');
	$msg =~ s/SPEED_TEST_FILE/$testFileName/;
	Common::display(["\n",$msg], 1);
	if($isDedup eq 'off'){
		$filename = $backupLocation."/".$filename;
	}
	Common::createUTF8File('DELETE',$tempBackupsetFilePath,$evsOutputFile,$evsErrorFile)
		or Common::retreat('failed_to_create_utf8_file');

	if(open(my $fh, ">", $tempBackupsetFilePath)){
		print $fh $filename;
		close($fh);
	}
	else {
		Common::retreat(['failed_to_open_file',":$tempBackupsetFilePath","\n\n"]);
	}

	my @responseData = Common::runEVS('item');

	# if($isDedup eq 'off'){
		# Common::createUTF8File('DELETEDROMTRASH',$tempBackupsetFilePath) or Common::retreat('failed_to_create_utf8_file');
		# Common::runEVS('item');
	 # }
	unlink($tempBackupsetFilePath);
	unlink($evsErrorFile);
	unlink($evsOutputFile);
}

#*****************************************************************************************************
# Subroutine			: cancelProcess
# Objective				: Cancelling the process and removing the intermediate files/folders
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub cancelProcess {
	my $idevsOutputFile 		= Common::getUserProfilePath()."/".$AppConfig::evsOutputFile;
	my $idevsErrorFile  		= Common::getUserProfilePath()."/".$AppConfig::evsErrorFile;
	my $tempBackupsetFilePath   = Common::getUserProfilePath()."/tempBackupsetFile.txt";
	my $testFile  				= Common::getUserProfilePath()."/".$testFileName;

	#Default Cleanup
	system('stty','echo');
	unlink($testFile);
	unlink($idevsOutputFile);
	unlink($idevsErrorFile);
	unlink($tempBackupsetFilePath);

	exit 1;
}
#*****************************************************************************************************
# Subroutine			: sendReportMail
# Objective				: Send report email to IDrive support team
# Added By				: Senthil Pandian
# Modified By     : Yogesh Kumar
#****************************************************************************************************/
sub sendReportMail {
	my $reportUserTicket = $_[0];
	my $reportContents   = $_[1];
	my $reportUserEmail  = $_[2];
	my $reportSubject 	 = qq($AppConfig::appType ).Common::getStringConstant('for_linux_user_feed');
	   $reportSubject 	.= qq( [#$reportUserTicket]) if($reportUserTicket ne '');
	my $response = Common::makeRequest(3, [
									$AppConfig::IDriveSupportEmail,
									$reportSubject,
									$reportContents,
									$reportUserEmail
								], 2);
	unless($response || $response->{STATUS} eq 'SUCCESS') {
		Common::retreat('failed_to_report_error');
		return;
	}

	Common::display(["\n", 'successfully_sent_speed_analysis', '.', "\n"]);
}
#*****************************************************************************************************
# Subroutine			: getReportUserEmails
# Objective				: This subroutine helps to collect the user emails
# Added By				: Sabin Cheruvattil
# Modified By			: Anil Kumar [04/05/2018]
#****************************************************************************************************/
sub getReportUserEmails {
	# if user is logged in, show the email address and ask if they want to change it
	my ($askEmailChoice, $reportUserEmail) = ('y', '');
	my $availableEmails = Common::getUserConfiguration('EMAILADDRESS');
	chomp($availableEmails);

	if($availableEmails ne '') {
		Common::display(["\n", 'configured_email_address_is', ': ', "\n\t", $availableEmails]);
		Common::display(["\n", 'do_you_want_edit_your_email_y_n', "\n\t"], 0);

		$askEmailChoice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	$reportUserEmail = $availableEmails;
	if(lc($askEmailChoice) eq 'y'){
		my $emailAddresses = Common::getAndValidate(['enter_your_email_id_mandatory', " : ", "\n\t"], "single_email_address", 1, $AppConfig::inputMandetory);
		$reportUserEmail = Common::formatEmailAddresses($emailAddresses);
	}
	return $reportUserEmail;
}

#*****************************************************************************************************
# Subroutine			: speedTestViaSpeedtestnet
# Objective				: This subroutine helps to collect the speed test result from the external python binary
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub speedTestViaSpeedtestnet {
	my @pybins = ("python3", "python");
	my $pythonbin   = "";
	my $speedNetRes = "\n";

	foreach my $pb (@pybins) {
		my $pythonbinCmd = "which $pb 2>/dev/null";
		$pythonbin = `$pythonbinCmd`;
		Common::Chomp(\$pythonbin);
		if ($pythonbin) {
			$pythonbin = $pb;
			last;
		}
	}

	my $cmdtoGetSpeedInfo = '';
	if ($pythonbin) {
		Common::display(["\n",'checking_network_speed_via_speedtestnet'], 1);
		my $proxy = '';
		if (Common::getProxyStatus() and Common::getProxyDetails('PROXYIP')) {
			$proxy = '-x http://';
			$proxy .= Common::getProxyDetails('PROXYIP');

			if (Common::getProxyDetails('PROXYPORT')) {
				$proxy .= (':' . Common::getProxyDetails('PROXYPORT'))
			}
			if (Common::getProxyDetails('PROXYUSERNAME')) {
				my $pu = Common::getProxyDetails('PROXYUSERNAME');
				foreach ($pu) {
					$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
				}
				$proxy .= (' --proxy-user ' . $pu);
	
				if (Common::getProxyDetails('PROXYPASSWORD')) {
					my $ppwd = Common::getProxyDetails('PROXYPASSWORD');
					$ppwd = ($ppwd ne '')?Common::decryptString($ppwd):$ppwd;
					foreach ($ppwd) {
						$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
					}
					$proxy .= (':' . $ppwd);
				}
			}
		}
		my $retryCount = 5;
RETRY:
		my $cmdtoGetSpeedInfoCmd = "curl -sk $proxy $speedTestScriptURL | $pythonbin";
		my $cmd       = "$cmdtoGetSpeedInfoCmd - 2>$speedTestErrorFile";
		my $speedInfo = `$cmd`;

		if(-f $speedTestErrorFile and !-z $speedTestErrorFile) {
			$retryCount--;
			if($retryCount) {
				Common::display('unable_to_fetch_the_details_trying_again');
				sleep(5);
				goto RETRY;
			}
			my $speedTestError = Common::getFileContents($speedTestErrorFile);
			Common::display($speedTestError);
			$speedInfo .= $speedTestError;

			Common::display('failed_to_fetch_the_speedtest_result');
			my $userOpt = Common::getAndValidate(['enter_your_choice_',"(y/n): "], "YN_choice", 1);
			if(lc($userOpt) eq 'y') {
				my $instruction = Common::getStringConstant('please_follow_instructions_for_speedtest_failure');
				$speedInfo = getSpeedTestResult($cmdtoGetSpeedInfoCmd, $speedInfo, $instruction);
			}
		}

		my $tempSpeedInfo  = $speedInfo;
		if ($tempSpeedInfo =~ /Upload:(.*?)\n/s) {
			$tempSpeedInfo = $1 ;
			Common::Chomp(\$tempSpeedInfo);
			$speedNetRes   = "[Upload speed: ".$tempSpeedInfo."]\n";
			$speedInfo = '';
		} elsif($tempSpeedInfo =~ /Upload:(.*?)$/s) {
			$tempSpeedInfo = $1;
			Common::Chomp(\$tempSpeedInfo);
			$speedNetRes   = "[Upload speed: ".$tempSpeedInfo."]\n";
			$speedInfo = '';			
		}

		Common::removeItems($speedTestErrorFile);
		return $speedNetRes.$speedInfo;
	}
	else {
		# Common::display(["\n",'checking_network_speed_via_speedtestnet'], 1);
		# $cmdtoGetSpeedInfo = Common::makeRequest('--speedtest');
        #Modified for Yuvaraj_2.32_13_1: Senthil
		Common::display(["\n",'python_not_found_no_speedtest'], 1);
		# return "\n".Common::getStringConstant('python_not_found_no_speedtest')."\n";
		my $speedInfo = "\n".Common::getStringConstant('python_not_found_no_speedtest')."\n";
		Common::display(["\n", 'to_continue_speedtest_via_browser']);
		my $userOpt = Common::getAndValidate(['enter_your_choice_',"(y/n): "], "YN_choice", 1);
		if(lc($userOpt) eq 'y') {
			my $instruction = Common::getStringConstant('please_follow_instructions_if_python_not_present');
			$speedInfo      = getSpeedTestResult('', $speedInfo, $instruction);
		}
		return $speedInfo;
	}
}

#*****************************************************************************************************
# Subroutine			: getSpeedTestResult
# Objective				: This subroutine helps to collect the speed test result from the external python binary
# Added By				: Senthil Pandian
# Modified By			: 
#****************************************************************************************************/
sub getSpeedTestResult {
	my $cmdtoGetSpeedInfoCmd = $_[0];
	my $speedInfo            = $_[1];
	my $str 				 = $_[2];
	$str =~ s/CMD/$cmdtoGetSpeedInfoCmd/;
	$str =~ s/URL/$speedTestWebURL/;
	Common::display(["\n", $str]);

	my $resultFilePath = Common::getAndValidate(['please_enter_speedtest_result_file_path_here'], 'file_path', 1, 0);
	if(-f $resultFilePath) {
		# Exiting if input file size is more than 1KB
		if(-s $resultFilePath <= 1024) {
			$speedInfo = Common::getFileContents($resultFilePath);
			Common::Chomp(\$speedInfo);
		} else {
			Common::retreat('speedtest_result_file_is_too_long');
		}
	}

	return $speedInfo;
}