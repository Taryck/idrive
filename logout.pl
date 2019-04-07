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
#****************************************************************************************************/
sub init {
	$Configuration::callerEnv = 'BACKGROUND' if (defined $ARGV[0] and (${ARGV[0]} == 1));

	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername();
	unless (Helpers::isLoggedin()) {
		$Configuration::displayHeader = 0;
		Helpers::retreat('no_user_is_logged_in');
	}

	my $jobType = 1;
	$jobType = ${ARGV[1]} if (defined $ARGV[1]);

	my %rjs = Helpers::getRunningJobs(undef, $jobType);
	if (%rjs) {
		my $choice = 'y';
		my @rj = keys %rjs;
		my $lastrj = '';
		if (scalar @rj > 1) {
			$lastrj = pop @rj;
			@rj = map{($_, ', ')} @rj;
			pop @rj;
			push(@rj, (' and ', $lastrj));
		}

		if(defined $ARGV[2] and $ARGV[2] eq 'NOUSERINPUT'){
			if(scalar(@rj) > 1) {
				Helpers::display(['Manual',' '],0);
				Helpers::display(\@rj, 0);
				Helpers::display(['jobs_are_cancelled',"\n"]);
			} else {
				Helpers::display(['Manual',' ',$rj[0],'job_has_been_cancelled',"\n"]);
			}
		} else {
			Helpers::display(['logging_out_from_your_account_will_terminate', ' ', ($jobType == 1 ? 'Manual' : ''), ' '], 0);
			Helpers::display(\@rj, 0);
			Helpers::display(['. ', 'do_you_want_to_continue_yn']);
			$choice = lc(Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1)) if($Configuration::callerEnv ne 'BACKGROUND');
		}


		if ($choice eq 'y') {
			my $cmd = sprintf("%s %s '' %s", $Configuration::perlBin, Helpers::getScript('job_termination', 1), Helpers::getUsername());
			my $res;
			$res = `$cmd $jobType all 1>/dev/null 2>/dev/null`;
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
