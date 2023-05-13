#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to send error report regarding the issues to the support
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Strings;
use Configuration;
use File::Basename;
use Scalar::Util qw(reftype);
Helpers::initiateMigrate();

init();

#****************************************************************************************************
# Subroutine Name         : init
# Objective               : This function is entry point for the script
# Added By                : Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	system('clear');
	my $totalNumberOfArgs = $#ARGV + 1;

	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername() && Helpers::loadUserConfiguration();
	Helpers::displayHeader() if ($totalNumberOfArgs != 5);
	Helpers::findDependencies(0) or Helpers::retreat('failed');

	my %reportInputs;
	if ($totalNumberOfArgs == 5) {
		$reportInputs{'reportUserName'}   = $ARGV[0];
		$reportInputs{'reportUserEmail'}  = $ARGV[1];
		$reportInputs{'reportUserContact'}= $ARGV[2];
		$reportInputs{'reportUserTicket'} = $ARGV[3];
		$reportInputs{'reportMessage'}    = $ARGV[4];

		$Configuration::callerEnv = 'BACKGROUND';
	}
	else {
		Helpers::isLoggedin() or Helpers::retreat('login_&_try_again');

		$reportInputs{'reportUserName'}   = getReportUserName();
		$reportInputs{'reportUserEmail'}  = getReportUserEmails();
		$reportInputs{'reportUserContact'}= getReportUserContact();
		$reportInputs{'reportUserTicket'} = getReportUserTicket();
		$reportInputs{'reportMessage'}    = getReportUserMessage();
	}

	my $reportSubject = qq($Configuration::appType $Locale::strings{'for_linux_user_feed'});
	$reportSubject   .= qq( [#$reportInputs{'reportUserTicket'}]) if($reportInputs{'reportUserTicket'} ne '');

	my $reportContents = getReportMailContent(%reportInputs);

	Helpers::display(["\n", 'sending_error_report']);
	# send email to server
	my $reportEmailCont = qq(Email=) . Helpers::urlEncode($Configuration::IDriveSupportEmail) . qq(&subject=) . Helpers::urlEncode($reportSubject);
	$reportEmailCont   .= qq(&content=) . Helpers::urlEncode($reportContents) . qq(&user_email=) . Helpers::urlEncode($reportInputs{'reportUserEmail'});

	my %params = (
		'host'   => $Configuration::IDriveErrorCGI,
		'method' => 'GET',
		'encDATA'=> $reportEmailCont,
	);

	#my $response = Helpers::request(\%params);
	my $response = Helpers::requestViaUtility(\%params);
	if(!$response || (reftype \$response eq 'REF' && $response->{STATUS} ne 'SUCCESS')) {
		Helpers::retreat('failed_to_report_error');
		return;
	}

	Helpers::display(["\n", 'successfully_reported_error', '.', "\n"]);
}

#*****************************************************************************************************
# Subroutine			: getReportUserName
# Objective				: This subroutine helps to collect the user name
# Added By				: Sabin Cheruvattil
# Modified By			: Anil Kumar [04/05/2018]
#****************************************************************************************************/
sub getReportUserName {
	my ($reportUserName, $choiceRetry) = ('', 0);

	if(Helpers::isLoggedin()) {
		Helpers::display(['current_loggedin_username_is', ': ', "\n\t", Helpers::getUsername()]);
	} else {
		# Get user name and validate
		$reportUserName = Helpers::getAndValidate(['enter_your', " ", $Configuration::appType, " ", 'username', ' : '], "username", 1);
		# need to set this for fetching the trace log for this user
		Helpers::setUsername($reportUserName);
		Helpers::loadServicePath();
		Helpers::loadUserConfiguration();
	}

	return $reportUserName;
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
		my $emailAddresses = Helpers::getAndValidate(["\n",'enter_your_email_id_mandatory', ":", "\n\t"], "single_email_address", 1, $Configuration::inputMandetory);
		$reportUserEmail = Helpers::formatEmailAddresses($emailAddresses);
	}
	return $reportUserEmail;
}

#*****************************************************************************************************
# Subroutine			: getReportUserContact
# Objective				: This subroutine helps to collect the user's contact
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getReportUserContact {
	my $returnUserContact = Helpers::getAndValidate(["\n",'enter_your'," ", 'contact_no', " ", '_optional_', ':', "\n\t"], "contact_no", 1);
	return $returnUserContact;
}

#*****************************************************************************************************
# Subroutine			: getReportUserTicket
# Objective				: This subroutine helps to collect the user's ticket if there is 1 already created
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getReportUserTicket {
	my $returnUserTicket = Helpers::getAndValidate(["\n",'ticket_number_if_any', " ", '_optional_'," : ", "\n\t"], "ticket_no", 1, 0);
	return $returnUserTicket;
}

#*****************************************************************************************************
# Subroutine			: getReportUserMessage
# Objective				: This subroutine helps to collect the user's message
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getReportUserMessage {
	my ($choiceRetry, $reportMessage) = (0, '');
	while($choiceRetry < $Configuration::maxChoiceRetry) {
		Helpers::display(['message', ' ', '_max_4095_characters_', ':', "\n\t"], 0);
		$reportMessage = Helpers::getUserChoice();
		if($reportMessage eq '') {
			$choiceRetry++;
			Helpers::checkRetryAndExit($choiceRetry);
			Helpers::display(['cannot_be_empty', '.', ' ', 'enter_again', '.']);
		} else {
			if(length($reportMessage) > $Configuration::reportMaxMsgLength) {
				Helpers::display(["\n", 'truncating_report_message_', "\n"]) ;
				$reportMessage = substr($reportMessage, 0, $Configuration::reportMaxMsgLength - 1);
			}
			last;
		}
	}

	return $reportMessage;
}

#****************************************************************************************************
# Subroutine Name         : getReportUserInputs
# Objective               : This subroutine prepares the content for error report
# Added By                : Sabin Cheruvattil
# Modified By             : Yogesh Kumar
#****************************************************************************************************/
sub getReportMailContent {
	my %reportInputs = @_;
	my ($reportContent, $logContent) = ('', '');
	my $proxyEnabled = Helpers::isProxyEnabled()? 'Yes' : 'No';

	$reportContent .= qq(<<< Feedback from $Configuration::appType $Locale::strings{'linux_backup'} - $Configuration::version >>> \n);
	$reportContent .= qq($Locale::strings{'machine_details'}: ) . $Configuration::machineOS . qq( \n);
	$reportContent .= qq($Locale::strings{'computer_name'}: $Configuration::hostname \n);
	$reportContent .= qq($Locale::strings{'profile_name'}: ) . Helpers::getMachineUser() . qq( \n);
	$reportContent .= qq($Locale::strings{'proxy_server'}: $proxyEnabled \n);
	$reportContent .= qq($Configuration::appType ) . ucfirst($Locale::strings{'username'}) . qq(: $reportInputs{'reportUserName'} \n);

	if (Helpers::loadStorageSize() or Helpers::reCalculateStorageSize()) {
		$reportContent .= qq($Locale::strings{'total_quota'}: ) . Helpers::getTotalStorage() . qq( \n);
		$reportContent .= qq($Locale::strings{'used_space'}: ) . Helpers::getStorageUsed() . qq( \n);
	}

	$reportContent .= qq($Locale::strings{'title_email_address'}: $reportInputs{'reportUserEmail'} \n);
	$reportContent .= qq($Locale::strings{'tech_issue_comment_suggest'}: \n);
	$reportContent .= qq(\n);
	$reportContent .= qq($reportInputs{'reportMessage'} \n);

	my $traceLog = Helpers::getTraceLogPath();
	if (-f $traceLog and !-z $traceLog) {
		local $/ = undef;
		open LOGFILE, '<', $traceLog;
		$logContent = <LOGFILE>;
		close LOGFILE;

		$reportContent .= qq(\n) . qq($Configuration::appType $Configuration::traceLogFile \n);
		$reportContent .= qq(-) x 50 . qq(\n) . qq($logContent \n);
	}

	$Configuration::traceLogFile = 'dashboard.log';
	$traceLog = Helpers::getTraceLogPath();
	if (-f $traceLog and !-z $traceLog) {
		local $/ = undef;
		open LOGFILE, '<', $traceLog;
		$logContent = <LOGFILE>;
		close LOGFILE;

		$reportContent .= qq(\n) . qq($Configuration::appType $Configuration::traceLogFile \n);
		$reportContent .= qq(-) x 50 . qq(\n) . qq($logContent \n);
	}

	return $reportContent;
}

1;
