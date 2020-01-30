#!/usr/bin/env perl
#*****************************************************************************************************
# Logout user from the current session
#
# Created By : Yogesh Kumar @ IDrive Inc
#*****************************************************************************************************

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers qw(getServicePath);
use Configuration;

init();

#*****************************************************************************************************
# Subroutine| | | : init
# Objective|| | | : This function is entry point for the script
# Added By| | | | : Yogesh Kumar
# Modified By | | : Senthil Pandian
#****************************************************************************************************/
sub init {
	$Configuration::callerEnv = 'BACKGROUND' if (defined $ARGV[0] and (${ARGV[0]} == 1));

	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername();

	if (defined($ARGV[2]) and $ARGV[2] eq 'NOUSERINPUT') {
		terminateAndLogoutAllUsers();
		exit;
	}
	elsif (!Helpers::isLoggedin()) {
		$Configuration::displayHeader = 0;
		Helpers::retreat('no_user_is_logged_in');
	}

	my $errorMsg = '';
	my $jobType  = 1;
	$jobType = ${ARGV[1]} if (defined $ARGV[1]);

	my %rjs = Helpers::getRunningJobs(undef, $jobType);
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
			Helpers::display(['logging_out_from_your_account_will_terminate', ' ', ($jobType == 1 ? 'Manual' : ''), ' '], 0);
			Helpers::display(\@rj, 0);
			Helpers::display(['. ', 'do_you_want_to_continue_yn']);
			$choice = lc(Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1)) if($Configuration::callerEnv ne 'BACKGROUND');
		}

		if ($choice eq 'y') {
			my $cmd = sprintf("%s %s 'allOp' %s %s 'allType' %s", $Configuration::perlBin, Helpers::getScript('job_termination', 1), Helpers::getUsername(), $jobType, $Configuration::mcUser);
			my $res;
			$cmd = Helpers::updateLocaleCmd($cmd);
			$res = `$cmd $errorMsg 1>/dev/null 2>/dev/null`;
			if (($? != 0) or ($res =~ /Operation not permitted/)) {
				Helpers::retreat(['unable_to_logout', ' ', 'system_user', " $Configuration::mcUser ", 'does_not_have_sufficient_permissions']);
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
	my $usrtxt = Helpers::getFileContents(Helpers::getCatfile(getServicePath(), $Configuration::cachedIdriveFile));
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		$usrtxt->{$Configuration::mcUser}{'isLoggedin'} = 0;
		Helpers::fileWrite(Helpers::getCatfile(getServicePath(), $Configuration::cachedIdriveFile), JSON::to_json($usrtxt));
		Helpers::display(["\"", Helpers::getUsername(), "\"", ' ', 'is_logged_out_successfully']);
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
	my @idriveUsersList = Helpers::getIDriveUserList();
	if (scalar @idriveUsersList > 0) {
		foreach my $usrProfileDir (@idriveUsersList)  {
			my @usrProfileDir = Helpers::fileparse($usrProfileDir);
			my $userName    = $usrProfileDir[0];
			chop($usrProfileDir[1]);
			my $profileName = (Helpers::fileparse($usrProfileDir[1]))[0];
			my $cmd = sprintf("%s %s 'allOp' %s %s 'allType' %s", $Configuration::perlBin, Helpers::getScript('job_termination', 1), $userName, 0, $profileName);
			my $res;
			$cmd = Helpers::updateLocaleCmd($cmd);
			$res = `$cmd 1>/dev/null 2>/dev/null`;
			if (($? != 0) or ($res =~ /Operation not permitted/)) {
				Helpers::retreat(['unable_to_logout', ' ', 'system_user', " $Configuration::mcUser ", 'does_not_have_sufficient_permissions']);
			}
		}
	}

	my $usrtxt = Helpers::getFileContents(Helpers::getCatfile(getServicePath(), $Configuration::cachedIdriveFile));
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
	Helpers::fileWrite(Helpers::getCatfile(getServicePath(), $Configuration::cachedIdriveFile), JSON::to_json($usrtxt));
	if($isLoggedOut) {
		if($isLoggedOut>0) {
			Helpers::display(["\n",'all_the_profile_users_loggedout']);
		} elsif($userName) {
			Helpers::display(["\n","\"", $userName, "\"", ' ', 'is_logged_out_successfully']);
		}
	}
}

