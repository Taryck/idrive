#!/usr/bin/env perl
#*****************************************************************************************************
# Logout user from the current session
#
# Created By : Yogesh Kumar @ IDrive Inc
#*****************************************************************************************************

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common qw(getServicePath);
use AppConfig;

init();

#*****************************************************************************************************
# Subroutine| | | : init
# Objective|| | | : This function is entry point for the script
# Added By| | | | : Yogesh Kumar
# Modified By | | : Senthil Pandian
#****************************************************************************************************/
sub init {
	$AppConfig::callerEnv = 'BACKGROUND' if (defined $ARGV[0] and (${ARGV[0]} == 1));

	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::verifyVersionConfig();
	Common::loadUsername();
	if (defined($ARGV[2]) and $ARGV[2] eq 'NOUSERINPUT') {
		terminateAndLogoutAllUsers();
		exit;
	}
	elsif (!Common::isLoggedin()) {
		# $AppConfig::displayHeader = 0;
		# Common::retreat('no_user_is_logged_in');
        Common::display('no_user_is_logged_in');
        exit;
	}

	my $errorMsg = 'operation_cancelled_due_to_logout';
	my $jobType  = 1;
	$jobType = ${ARGV[1]} if (defined $ARGV[1]);

	my %rjs = Common::getRunningJobs(undef, $jobType);
	my $choice;

	if (%rjs) {
		$choice = 'y';
		my @rj = keys %rjs;
		my $lastrj = '';
		if (scalar @rj > 1) {
			$lastrj = pop @rj;
			@rj = map{($_, ', ')} @rj;
			pop @rj;
			push(@rj, (' and ', $lastrj));
		}

		if (defined $ARGV[2] and $ARGV[2] ne '') {
			#Added to handle error message which is passed as argument explicitly
			$errorMsg = $ARGV[2];
		} else {
			Common::display(['logging_out_from_your_account_will_terminate', ' ', ($jobType == 1 ? 'Manual' : ''), ' '], 0);
			Common::display(\@rj, 0);
			Common::display(['. ', 'do_you_want_to_continue_yn']);
			$choice = lc(Common::getAndValidate(['enter_your_choice'], "YN_choice", 1)) if($AppConfig::callerEnv ne 'BACKGROUND');
		}

		if ($choice eq 'y') {
			my $cmd = sprintf("%s %s 'allOp' %s %s 'allType' %s %s", $AppConfig::perlBin, Common::getScript('job_termination', 1), Common::getUsername(), $jobType, $AppConfig::mcUser, $errorMsg);
			my $res;
			$cmd = Common::updateLocaleCmd($cmd);
			$res = `$cmd 1>/dev/null 2>/dev/null`;
			if (($? != 0) or ($res =~ /Operation not permitted/)) {
				Common::retreat(['unable_to_logout', ' ', 'system_user', " $AppConfig::mcUser ", 'does_not_have_sufficient_permissions']);
			}
		}
		else {
			exit 0;
		}
	}

	doLogout();
}

#*****************************************************************************************************
# Subroutine| | | : doLogout
# Objective|| | | : Logout current user's a/c
# Added By| | | | : Yogesh Kumar
#****************************************************************************************************/
sub doLogout {
	my $usrtxt = Common::getFileContents(Common::getCatfile(getServicePath(), $AppConfig::cachedIdriveFile));
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		$usrtxt->{$AppConfig::mcUser}{'isLoggedin'} = 0;
		Common::fileWrite(Common::getCatfile(getServicePath(), $AppConfig::cachedIdriveFile), JSON::to_json($usrtxt));
		Common::display(["\"", Common::getUsername(), "\"", ' ', 'is_logged_out_successfully']);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine/Function   : terminateAndLogoutAllUsers
# In Param  : 
# Out Param : 
# Objective	: This subroutine to terminate all running jobs & logout all profile users
# Added By	: Senthil Pandian
# Modified By : 
#****************************************************************************************************/
sub terminateAndLogoutAllUsers {
	my @idriveUsersList = Common::getIDriveUserList();
	if (scalar @idriveUsersList > 0) {
		foreach my $usrProfileDir (@idriveUsersList)  {
			my @usrProfileDir = Common::fileparse($usrProfileDir);
			my $userName    = $usrProfileDir[0];
			chop($usrProfileDir[1]);
			my $profileName = (Common::fileparse($usrProfileDir[1]))[0];
			my $cmd = sprintf("%s %s 'allOp' %s %s 'allType' %s %s", $AppConfig::perlBin, Common::getScript('job_termination', 1), $userName, 0, $profileName, 'operation_cancelled_due_to_logout');
			my $res;
			$cmd = Common::updateLocaleCmd($cmd);
			$res = `$cmd 1>/dev/null 2>/dev/null`;
			if (($? != 0) or ($res =~ /Operation not permitted/)) {
				Common::retreat(['unable_to_logout', ' ', 'system_user', " $AppConfig::mcUser ", 'does_not_have_sufficient_permissions']);
			}
		}
	}

	my $usrtxt = Common::getFileContents(Common::getCatfile(getServicePath(), $AppConfig::cachedIdriveFile));
	return 0 unless($usrtxt =~ m/^\{/);

	my $isLoggedOut = 0;
	my $userName = '';
	$usrtxt = JSON::from_json($usrtxt);
	foreach my $profile (keys %{$usrtxt}){
		if(defined($usrtxt->{$profile}{'isLoggedin'}) and $usrtxt->{$profile}{'isLoggedin'}) {
			$usrtxt->{$profile}{'isLoggedin'} = 0;
			$isLoggedOut++;
			$userName = $usrtxt->{$profile}{'userid'} if(defined($usrtxt->{$profile}{'userid'}));
		}
	}
	Common::fileWrite(Common::getCatfile(getServicePath(), $AppConfig::cachedIdriveFile), JSON::to_json($usrtxt));
	if($isLoggedOut) {
		if($isLoggedOut>0) {
			Common::display(["\n",'all_the_profile_users_loggedout']);
		} elsif($userName) {
			Common::display(["\n","\"", $userName, "\"", ' ', 'is_logged_out_successfully']);
		}
	}
}

