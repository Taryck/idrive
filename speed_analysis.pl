#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to analyze the speed of Backup and send error report from user machine.
#
# Created By: Anil Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Configuration;

#need to change to 200MB for production release
use constant SPEED_TEST_FILE_SIZE => "10M";

require Constants;
$SIG{INT}  = \&cancelProcess;
$SIG{TERM} = \&cancelProcess;
$SIG{TSTP} = \&cancelProcess;
$SIG{QUIT} = \&cancelProcess;
my $testFileName = "";

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Senthil pandian
#****************************************************************************************************/
sub init {
	system(Helpers::updateLocaleCmd("clear"));
	checkVersionInfo() if($Configuration::appType eq 'IDrive');

	Helpers::loadAppPath() or Helpers::retreat('Failed to load source Code path');
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername() or Helpers::retreat('login_&_try_again');
	Helpers::isLoggedin() or Helpers::retreat('login_&_try_again');
	my $errorKey = Helpers::loadUserConfiguration();
	Helpers::retreat($Configuration::errorDetails{$errorKey}) if($errorKey > 1);
	Helpers::displayHeader();
	displayDescription();

	my $tempBackupsetFilePath   = Helpers::getUserProfilePath()."/tempBackupsetFile.txt";
	my $ticketID  = getUserTicketID();

	Helpers::display(["\n", 'can_we_upload_a_sample_file_for_speed_test_analysis', "\n"], 0);
	my $userOpt = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	unless(lc($userOpt) eq 'y'){
		Helpers::display(["\n", 'aborting_the_operation', "\n"], 1);
		exit;
	}

	$testFileName = checkItemStatus();

	Helpers::display(['speed_test_file_created_successfully'], 1);
	my $backupFileList   = $tempBackupsetFilePath;
	my $testFile  = Helpers::getUserProfilePath()."/".$testFileName;

	generateFileForBackup($testFile);
	my $evsResult = speedTestViaEVS($backupFileList);
	deleteTestFileFromIDrive($testFileName);
	my $speedtesnetResult = speedTestViaSpeedtestnet();

	$evsResult .= Helpers::getStringConstant('speed_test_result_via_speed_test_net'). " \n===================================\n\t". $speedtesnetResult;
	Helpers::display(["\n", 'do_you_want_to_view_speed_analysis_report', "\n"], 0);
	my $displayChoice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	if(lc($displayChoice) eq 'y'){
		#Helpers::display(["\n", "SPEED ANALYSIS RESULT :::", "\n=======================\n", "\n"], 0);
		Helpers::display(["\n\n",$evsResult], 1);
	}

	Helpers::display(["\n", 'do_you_want_to_send_speed_analysis_report_to_idrive_team', "\n"], 0);
	my $askEmailChoice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);

	if(lc($askEmailChoice) eq 'y'){
		my $userEmail = getReportUserEmails();
		sendReportMail($ticketID,$evsResult,$userEmail);
	}
	else{
		Helpers::display(["\n", 'aborting_the_operation', "\n"], 1);
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
	$description .= Helpers::getStringConstant('description_for_speed_test');
	$description .= "\n";
	Helpers::display($description, 1);
}

#********************************************************************************
# Subroutine			: checkVersionInfo
# Objective				: This method is used to check the user scripts version.
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#********************************************************************************
sub checkVersionInfo {
	my $version = Constants->CONST->{'ScriptBuildVersion'};
	Helpers::retreat(["\n", 'please_update_your_script_to_latest_version', "\n"], 1) unless(Helpers::versioncompare('2.16', $version) == 2);
}

#********************************************************************************
# Subroutine			: checkItemStatus
# Objective				: This is to check whether the test file is already exist in
#							user account and change the file name accordingly to avoid the file sync.
# Added By				: Anil Kumar
#********************************************************************************
sub checkItemStatus {

	Helpers::display(["\n", 'creating_the_speed_test_file_for_backup'], 1);

	my $isDedup  	   = Helpers::getUserConfiguration('DEDUP');
	my $backupLocation = Helpers::getUserConfiguration('BACKUPLOCATION');
	   $backupLocation = '/'.$backupLocation unless($backupLocation =~ m/^\//);
	my $remoteFolder = "*speedTestFile.txt*";
	my $strReplace = "";

	my $searchDir 	   = Helpers::getUserProfilePath();
	my $tempSearchUTFpath = $searchDir.'/'.$Configuration::utf8File;
	my $tempEvsOutputFile = $searchDir.'/'.$Configuration::evsOutputFile;
	my $tempEvsErrorFile  = $searchDir.'/'.$Configuration::evsErrorFile;

	if($isDedup eq 'off'){
		$strReplace = $backupLocation."/speedTestFile.txt";
	} else {
		$strReplace = "/speedTestFile.txt";
	}

	Helpers::createUTF8File(['SEARCHALL', $tempSearchUTFpath], $tempEvsOutputFile, $tempEvsErrorFile, $remoteFolder);
	my @responseData = Helpers::runEVS('item', 1, 1, $tempSearchUTFpath);

	while(1){
		if((-e $tempEvsOutputFile and -s $tempEvsOutputFile) or  (-e $tempEvsErrorFile and -s $tempEvsErrorFile)){
			last;
		}
		sleep(2);
		next;
	}

	print "\n\n Search Error \n\n" if(-s $tempEvsOutputFile == 0 and -s $tempEvsErrorFile > 0);

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
			my %fileName = Helpers::parseXMLOutput(\$tmpLine);
			if($tmpLine =~ /fname/) {
				my $temp = $fileName{'fname'};
				print "\nfile name:: $temp\n";
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
	my $tempBackupsetFilePath  = Helpers::getUserProfilePath()."/tempBackupsetFile.txt";

	# need to update size to 200 MB for production release.
	my $cmdToCreateFile = "dd if=/dev/urandom of='$testFile' bs=".SPEED_TEST_FILE_SIZE." count=1 2>/dev/null";
	$cmdToCreateFile = Helpers::updateLocaleCmd($cmdToCreateFile);
	`$cmdToCreateFile`;

	if(open(my $fh, ">", $tempBackupsetFilePath)){
		print $fh $testFileName;
		close($fh);
	} else {
		Helpers::retreat(['failed_to_open_file',":$tempBackupsetFilePath","\n\n"]);
	}
	return $tempBackupsetFilePath;
}

#********************************************************************************
# Subroutine			: getUserTicketID
# Objective				: Get user's Ticket ID
# Added By				: Senthil Pandian
#********************************************************************************
sub getUserTicketID {
	my $returnUserTicket = Helpers::getAndValidate(['Enter the ticket number:', " "], "ticket_no", 1, $Configuration::inputMandetory);
	return $returnUserTicket;
}

#*****************************************************************************************************
# Subroutine			: speedTestViaEVS
# Objective				: Get the result of evs speed test.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub speedTestViaEVS {
	my $backupUTFpath  			= Helpers::getUserProfilePath()."/".$Configuration::utf8File."_speed";
	my $evsOutputFile  			= Helpers::getUserProfilePath()."/".$Configuration::evsOutputFile;
	my $evsErrorFile   			= Helpers::getUserProfilePath()."/".$Configuration::evsErrorFile;
	my $isDedup  	   			= Helpers::getUserConfiguration('DEDUP');
	my $bwPath     	   			= Helpers::getUserProfilePath()."/bw.txt";
	my $backupLocation 			= "";

	my $tempBackupsetFilePath   = $_[0];
	my ($fh,$buffer,$fileSize);

	Helpers::createUpdateBWFile();
	Helpers::display(["\n",'starting_backup'], 1);
	if($isDedup eq 'off'){
		$backupLocation 	= Helpers::getUserConfiguration('BACKUPLOCATION');
	}

	Helpers::createUTF8File(['BACKUP',$backupUTFpath],$tempBackupsetFilePath,$bwPath,Helpers::getUserProfilePath()."/",$evsOutputFile,$evsErrorFile,
			'/'.Helpers::getUserProfilePath()."/",$backupLocation) or Helpers::retreat('failed_to_create_utf8_file');

	my $reportMsg .= "Bandwidth Throttle:\n===================\n";
	if(-e $bwPath){
		$fileSize = -s $bwPath;
		if(open($fh, "<", $bwPath) and read($fh, $buffer, $fileSize)) {
			close($fh);
			$reportMsg .= "\t".$buffer."\n\n";
        }
	}

	$reportMsg .= "Backup Start Time:\n==================\n";
	my $backupStartTimeSec = time();
	my $backupStartTime = localtime $backupStartTimeSec;
	$reportMsg .= "\t".$backupStartTime." \n\n";

	Helpers::display(['backup_in_progress'], 1);
	my @responseData = Helpers::runEVS('item');

	$reportMsg .= "Backup End Time:\n================\n";
	my $backupEndTimeSec = time();
	my $backupEndTime = localtime $backupEndTimeSec;
	$reportMsg .= "\t".$backupEndTime." \n\n";

	$reportMsg .= "Backup Output:\n==============\n";
	if(-e $evsOutputFile){
		$fileSize =  -s $evsOutputFile;
        if(open($fh, "<", $evsOutputFile) and read($fh, $buffer, $fileSize)) {
			close($fh);
			$reportMsg .= "\t$buffer\n\n";
        }
		unlink($evsOutputFile);
	}
	Helpers::display(['backup_has_been_completed'], 1);

	if(-e $evsErrorFile and -s $evsErrorFile){
		$fileSize =  -s $evsErrorFile;
        if(open($fh, "<", $evsErrorFile) and read($fh, $buffer, $fileSize)) {
			close($fh);
			$reportMsg .= "Backup Error:\n============\n";
			$reportMsg .= "\t$buffer\n\n";
        }
	}

	$reportMsg .= "Speed test result from IDrive:\n============================\n";
	my $time = $backupEndTimeSec - $backupStartTimeSec;
	my $size = 10485760/1048576;
	my $res = ($size/$time)*8;
	$res = substr($res,0,4);
	$reportMsg .= "\tUpload: ".$res." Mbit/s\n\n";

	unlink($evsErrorFile);
	unlink($evsOutputFile);
	return $reportMsg;
}

#*****************************************************************************************************
# Subroutine			: deleteTestFileFromIDrive
# Objective				: Delete the test file uploaded from user account.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub deleteTestFileFromIDrive {
	my $evsOutputFile  			= Helpers::getUserProfilePath()."/".$Configuration::evsOutputFile;
	my $evsErrorFile   			= Helpers::getUserProfilePath()."/".$Configuration::evsErrorFile;
	my $isDedup  	   			= Helpers::getUserConfiguration('DEDUP');
	my $backupLocation 			= Helpers::getUserConfiguration('BACKUPLOCATION');
	my $tempBackupsetFilePath   = Helpers::getUserProfilePath()."/tempBackupsetFile.txt";
	my $filename = $_[0];

	Helpers::display(["\n",'deleting_speed_test_file_from_your_account'], 1);
	if($isDedup eq 'off'){
		$filename = $backupLocation."/".$filename;
	}
	Helpers::createUTF8File('DELETE',$tempBackupsetFilePath,$evsOutputFile,$evsErrorFile)
		or Helpers::retreat('failed_to_create_utf8_file');

	if(open(my $fh, ">", $tempBackupsetFilePath)){
		print $fh $filename;
		close($fh);
	}
	else {
		Helpers::retreat(['failed_to_open_file',":$tempBackupsetFilePath","\n\n"]);
	}

	my @responseData = Helpers::runEVS('item');

	# if($isDedup eq 'off'){
		# Helpers::createUTF8File('DELETEDROMTRASH',$tempBackupsetFilePath) or Helpers::retreat('failed_to_create_utf8_file');
		# Helpers::runEVS('item');
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
	my $idevsOutputFile 		= Helpers::getUserProfilePath()."/".$Configuration::evsOutputFile;
	my $idevsErrorFile  		= Helpers::getUserProfilePath()."/".$Configuration::evsErrorFile;
	my $tempBackupsetFilePath   = Helpers::getUserProfilePath()."/tempBackupsetFile.txt";
	my $testFile  				= Helpers::getUserProfilePath()."/".$testFileName;

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
#****************************************************************************************************/
sub sendReportMail {
	my $reportUserTicket = $_[0];
	my $reportContents   = $_[1];
	my $reportUserEmail  = $_[2];
	my $reportSubject 	 = qq($Configuration::appType ).Helpers::getStringConstant('for_linux_user_feed');
	   $reportSubject 	.= qq( [#$reportUserTicket]) if($reportUserTicket ne '');
	my $reportEmailCont	 = qq(Email=) . Helpers::urlEncode($Configuration::IDriveSupportEmail) . qq(&subject=) . Helpers::urlEncode($reportSubject);
	$reportEmailCont	.= qq(&content=).Helpers::urlEncode($reportContents).qq(&user_email=).Helpers::urlEncode($reportUserEmail);

	my %params = (
		'host'   => $Configuration::IDriveErrorCGI,
		'method' => 'GET',
		'encDATA' => $reportEmailCont,
	);

	#my $response = Helpers::request(\%params);
	my $response = Helpers::requestViaUtility(\%params);
	unless($response || $response->{STATUS} eq 'SUCCESS') {
		Helpers::retreat('failed_to_report_error');
		return;
	}

	Helpers::display(["\n", 'successfully_reported_error', '.', "\n"]);
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
	my $availableEmails = Helpers::getUserConfiguration('EMAILADDRESS');
	chomp($availableEmails);

	if($availableEmails ne '') {
		Helpers::display(["\n", 'configured_email_address_is', ': ', "\n\t", $availableEmails]);
		Helpers::display(["\n", 'do_you_want_edit_your_email_y_n', "\n\t"], 0);

		$askEmailChoice = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	$reportUserEmail = $availableEmails;
	if(lc($askEmailChoice) eq 'y'){
		my $emailAddresses = Helpers::getAndValidate(['enter_your_email_id_mandatory', " : ", "\n\t"], "single_email_address", 1, $Configuration::inputMandetory);
		$reportUserEmail = Helpers::formatEmailAddresses($emailAddresses);
	}
	return $reportUserEmail;
}

#*****************************************************************************************************
# Subroutine			: speedTestViaSpeedtestnet
# Objective				: This subroutine helps to collect the speed test result from the external python binary
# Added By				: Anil Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub speedTestViaSpeedtestnet {
	my $pythonbinCmd = Helpers::updateLocaleCmd('which python');
	my $pythonbin = `$pythonbinCmd`;
	Helpers::Chomp(\$pythonbin);
	unless($pythonbin) {
		Helpers::display(["\n",'python_not_found_no_speedtest'], 1);
		return "Python not found. Unable to get speedtest.net result.";
	}

	Helpers::display(["\n",'checking_network_speed_via_speedtestnet'], 1);
	my $proxy = "";
	my $proxyStr =  Helpers::getUserConfiguration('PROXY');
	if($proxyStr){
		my ($uNPword, $ipPort) = split(/\@/, $proxyStr);
		my @UnP = split(/\:/, $uNPword);
		if(scalar(@UnP) >1 and $UnP[0] ne "") {
			$UnP[1] = ($UnP[1] ne '')? Helpers::decryptString($UnP[1]):$UnP[1];
			foreach ($UnP[0], $UnP[1]) {
				$_ =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			}
			$uNPword = join ":", @UnP;
			$proxyStr = "http://$uNPword\@$ipPort";
		}
		$proxy = "--proxy $proxyStr";
	}

	my $cmdtoGetSpeedInfoCmd = Helpers::updateLocaleCmd('curl -sk $proxy https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python -');
	my $cmdtoGetSpeedInfo = `$cmdtoGetSpeedInfoCmd`;
	return $cmdtoGetSpeedInfo;
}
