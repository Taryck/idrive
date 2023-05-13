#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to send error report regarding the issues to the support
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;
use File::Basename;
use Scalar::Util qw(reftype);
Common::waitForUpdate();
Common::initiateMigrate();

init();

#****************************************************************************************************
# Subroutine Name         : init
# Objective               : This function is entry point for the script
# Added By                : Sabin Cheruvattil
# Modified By             : Senthil Pandian
#****************************************************************************************************/
sub init {
	system(Common::updateLocaleCmd('clear'));
	my $totalNumberOfArgs = $#ARGV + 1;

	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::loadUsername() && Common::loadUserConfiguration();
	Common::displayHeader() if ($totalNumberOfArgs != 5);
	Common::findDependencies(0) or Common::retreat('failed');

	my %reportInputs;
	if ($totalNumberOfArgs == 5) {
		$reportInputs{'reportUserName'}   = $ARGV[0];
		$reportInputs{'reportUserEmail'}  = $ARGV[1];
		$reportInputs{'reportUserContact'}= $ARGV[2];
		$reportInputs{'reportUserTicket'} = $ARGV[3];
		$reportInputs{'reportMessage'}    = $ARGV[4];

		$AppConfig::callerEnv = 'BACKGROUND';
	}
	else {
		Common::isLoggedin() or Common::retreat('login_&_try_again');

		$reportInputs{'reportUserName'}   = getReportUserName();
		$reportInputs{'reportUserEmail'}  = getReportUserEmails();
		$reportInputs{'reportUserContact'}= getReportUserContact();
		$reportInputs{'reportUserTicket'} = getReportUserTicket();
		$reportInputs{'reportMessage'}    = getReportUserMessage();
	}

	my $reportSubject = qq($AppConfig::appType ).Common::getStringConstant('for_linux_user_feed');
	$reportSubject   .= qq( [#$reportInputs{'reportUserTicket'}]) if($reportInputs{'reportUserTicket'} ne '');

	my $reportContents = getReportMailContent(%reportInputs);

	Common::display(["\n", 'sending_error_report']);
	# send email to server
	my $response = Common::makeRequest(3, [
									$AppConfig::IDriveSupportEmail,
									$reportSubject,
									$reportContents,
									$reportInputs{'reportUserEmail'}
								], 2);
	if(!$response || (reftype \$response eq 'REF' && $response->{STATUS} ne 'SUCCESS')) {
		Common::retreat('failed_to_report_error');
		return;
	}

	Common::display(["\n", 'successfully_reported_error', '.', "\n"]);
}

#*****************************************************************************************************
# Subroutine			: getReportUserName
# Objective				: This subroutine helps to collect the user name
# Added By				: Sabin Cheruvattil
# Modified By			: Anil Kumar [04/05/2018]
#****************************************************************************************************/
sub getReportUserName {
	my ($reportUserName, $choiceRetry) = ('', 0);

	if(Common::isLoggedin()) {
		$reportUserName = Common::getUsername();
		Common::display(['current_loggedin_username_is', ': ', "\n\t", $reportUserName]);
	} else {
		# Get user name and validate
		$reportUserName = Common::getAndValidate(['enter_your', " ", $AppConfig::appType, " ", 'username', ' : '], "username", 1);
		# need to set this for fetching the trace log for this user
		Common::setUsername($reportUserName);
		Common::loadServicePath();
		Common::loadUserConfiguration();
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
	my $availableEmails = Common::getUserConfiguration('EMAILADDRESS');
	chomp($availableEmails);

	if($availableEmails ne '') {
		Common::display(["\n", 'configured_email_address_is', ': ', "\n\t", $availableEmails]);
		Common::display(["\n", 'do_you_want_edit_your_email_y_n', "\n\t"], 0);

		$askEmailChoice = Common::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}

	$reportUserEmail = $availableEmails;
	if(lc($askEmailChoice) eq 'y'){
		my $emailAddresses = Common::getAndValidate(["\n",'enter_your_email_id_mandatory', ":", "\n\t"], "single_email_address", 1, $AppConfig::inputMandetory);
		$reportUserEmail = Common::formatEmailAddresses($emailAddresses);
	}
	return $reportUserEmail;
}

#*****************************************************************************************************
# Subroutine			: getReportUserContact
# Objective				: This subroutine helps to collect the user's contact
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getReportUserContact {
	my $returnUserContact = Common::getAndValidate(["\n",'enter_your'," ", 'contact_no', " ", '_optional_', ':', "\n\t"], "contact_no", 1);
	return $returnUserContact;
}

#*****************************************************************************************************
# Subroutine			: getReportUserTicket
# Objective				: This subroutine helps to collect the user's ticket if there is 1 already created
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getReportUserTicket {
	my $returnUserTicket = Common::getAndValidate(["\n",'ticket_number_if_any', " ", '_optional_'," : ", "\n\t"], "ticket_no", 1, 0);
	return $returnUserTicket;
}

#*****************************************************************************************************
# Subroutine			: getReportUserMessage
# Objective				: This subroutine helps to collect the user's message
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getReportUserMessage {
	my ($choiceRetry, $reportMessage) = (0, '');
	while($choiceRetry < $AppConfig::maxChoiceRetry) {
		Common::display(['message', ' ', '_max_4095_characters_', ':', "\n\t"], 0);
		$reportMessage = Common::getUserChoice();
		if($reportMessage eq '') {
			$choiceRetry++;
			Common::checkRetryAndExit($choiceRetry);
			Common::display(['cannot_be_empty', '.', ' ', 'enter_again', '.']);
		} else {
			if(length($reportMessage) > $AppConfig::reportMaxMsgLength) {
				Common::display(["\n", 'truncating_report_message_', "\n"]) ;
				$reportMessage = substr($reportMessage, 0, $AppConfig::reportMaxMsgLength - 1);
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
# Modified By             : Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub getReportMailContent {
	my %reportInputs = @_;
	my ($reportContent, $logContent) = ('', '');
	my $osd = Common::getOSBuild();
	my $proxyEnabled	= Common::isProxyEnabled()? 'Yes' : 'No';
	my $cdpsupport		= Common::canKernelSupportInotify()? 'Yes' : 'No';
	my $cronstat		= Common::getStringConstant((Common::checkCRONServiceStatus() == Common::CRON_RUNNING)? 'c_running' : 'c_stopped');

	$reportContent .= "<<< Feedback from $AppConfig::appType ".Common::getStringConstant('linux_backup')." - $AppConfig::version >>> \n";
	$reportContent .= Common::getStringConstant('machine_details').": $AppConfig::machineOS \n";
	$reportContent .= Common::getStringConstant('os_details').": $osd->{'os'} $osd->{'build'} \n";
	$reportContent .= Common::getStringConstant('computer_name').": $AppConfig::hostname \n";
	$reportContent .= Common::getStringConstant('profile_name').": " . $AppConfig::mcUser . qq( \n);
	$reportContent .= Common::getStringConstant('proxy_server').": $proxyEnabled \n";
	$reportContent .= Common::getStringConstant('cron_job').": $cronstat \n";
	$reportContent .= Common::getStringConstant('cdp_suppport').": $cdpsupport \n";
	$reportContent .= qq($AppConfig::appType ) . ucfirst(Common::getStringConstant('username')).": ".$reportInputs{'reportUserName'}."\n";

	# No need to explicitly call quota recalculation as we already have called the same from header display.
	# if (Common::loadStorageSize() or Common::reCalculateStorageSize()) {
	if (Common::loadStorageSize()) {
		$reportContent .= Common::getStringConstant('total_quota').": " . Common::getTotalStorage() . qq( \n);
		$reportContent .= Common::getStringConstant('used_space').": " . Common::getStorageUsed() . qq( \n);
	}

	$reportContent .= Common::getStringConstant('title_email_address').": $reportInputs{'reportUserEmail'} \n";
	$reportContent .= Common::getStringConstant('tech_issue_comment_suggest').": \n";
	$reportContent .= qq(\n);
	$reportContent .= qq($reportInputs{'reportMessage'} \n);

	my $traceLog = Common::getTraceLogPath();
	if (-f $traceLog and !-z $traceLog) {
		local $/ = undef;
		open LOGFILE, '<', $traceLog;
		$logContent = <LOGFILE>;
		close LOGFILE;

		$reportContent .= qq(\n) . qq($AppConfig::appType $AppConfig::traceLogFile \n);
		$reportContent .= qq(-) x 50 . qq(\n) . qq($logContent \n);
	}

	$AppConfig::traceLogFile = 'dashboard.log';
	$traceLog = Common::getTraceLogPath();
	if (-f $traceLog and !-z $traceLog) {
		local $/ = undef;
		open LOGFILE, '<', $traceLog;
		$logContent = <LOGFILE>;
		close LOGFILE;

		$reportContent .= qq(\n) . qq($AppConfig::appType $AppConfig::traceLogFile \n);
		$reportContent .= qq(-) x 50 . qq(\n) . qq($logContent \n);
	}

	return $reportContent;
}

1;
