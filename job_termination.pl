#!/usr/bin/env perl
#*****************************************************************************************************
# Find and terminate running jobs like backup/restore including scheduled ones.
#
# Created By : Yogesh Kumar @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Configuration;

my $cmdNumOfArgs = $#ARGV;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	Helpers::loadAppPath();
	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');
	$Configuration::callerEnv = 'BACKGROUND' unless ($cmdNumOfArgs == -1);
	my $killall = (defined($ARGV[3]) && $ARGV[3] eq 'all')? 1 : 0;

	if ($cmdNumOfArgs == 1) {
		Helpers::setUsername($ARGV[1]) if($ARGV[1] ne '-');
	}
	else {
		Helpers::loadUsername() or Helpers::retreat('login_&_try_again');
	}

	my $errorKey = Helpers::loadUserConfiguration();
	#Helpers::retreat($Configuration::errorDetails{$errorKey}) if($errorKey != 1);
	Helpers::loadEVSBinary()  or Helpers::retreat('unable_to_find_or_execute_evs_binary');
	Helpers::isLoggedin()     or Helpers::retreat('login_&_try_again') if($Configuration::callerEnv ne 'BACKGROUND');
	Helpers::displayHeader() unless($cmdNumOfArgs == 1);

	my %jobs = Helpers::getRunningJobs($ARGV[0] || undef, $ARGV[2] || 0);
	if (!%jobs) {
		if ($Configuration::callerEnv eq 'BACKGROUND'){
			Helpers::traceLog($ARGV[0],'_not_running');
		} else {
			Helpers::display('no_job_is_in_progress');
		}
		exit 0;
	}

	my @options = getOptions(%jobs);
	my $userSelection;

	if ($Configuration::callerEnv ne 'BACKGROUND') {
		if (scalar(@options) > 1) {
			Helpers::display('you_can_stop_one_job_at_a_time')
		}

		Helpers::displayMenu('select_the_job_from_the_above_list',@options);
		$userSelection = Helpers::getUserMenuChoice(scalar(@options));
	}
	else {
		$userSelection = 1;
	}

REPEAT:
	my $cancelFile = '';
	if (Helpers::validateMenuChoice($userSelection, 1, scalar(@options))) {
		$options[($userSelection - 1)] =~ s/stop_//g;
		my $pid = getPid($jobs{$options[($userSelection - 1)]});
		if ($cmdNumOfArgs == -1) {
			$cancelFile = $jobs{$options[($userSelection - 1)]};
			$cancelFile =~ s/pid.txt$/cancel.txt/g;
			if (open(my $fh, '>', $cancelFile)) {
				Helpers::traceLog('Operation Cancelled by user');
				print $fh "Operation could not be completed, Reason: Operation Cancelled by user";
				close $fh;
			}
			else {
				Helpers::retreat(['unable_to_create_file', " \"$cancelFile\"." ]);
			}
		}

		if ($pid ne "" && !killPid($pid)) {
			unlink($cancelFile) if(-f $cancelFile);
			exit(0) unless($killall);
		}
		else {
			if(-e $jobs{$options[($userSelection - 1)]}){
				unlink($jobs{$options[($userSelection - 1)]});
				if($Configuration::callerEnv eq 'BACKGROUND'){
					Helpers::traceLog([$options[($userSelection - 1)], " ", 'job_terminated_successfully']);
				} else {
					Helpers::display([$options[($userSelection - 1)], " ", 'job_terminated_successfully']);
				}
			} else {
				if($Configuration::callerEnv eq 'BACKGROUND'){
					Helpers::traceLog('no_job_is_in_progress');
				} else {
					Helpers::display('no_job_is_in_progress');
				}
				exit 0;
			}
		}

		if($killall) {
			exit(0) if($userSelection == scalar(@options));
			$userSelection++;
			goto REPEAT;
		}
	}
	else {
		Helpers::display(['invalid_choice',"\n"]);
	}
}

#*****************************************************************************************************
# Subroutine			: getPid
# Objective				: Find and return PID(s) of backup or restore processes
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getPid {
	my $parentpid;
	if(open(my $p, '<', @_)) {
		$parentpid = <$p>;
		close($p);
		chomp($parentpid) if($parentpid);
	}
	else {
		Helpers::traceLog(['failed_to_open_file', ": @_"]);
		return "";
	}

	my ($findpid, $r, $pid);
	my (@pid, @cmd);

	if($parentpid){
		$findpid = qq{ps -o sid= -p$parentpid | xargs pgrep -s | xargs ps -o pid,command -p | grep idev | grep -v "grep"};
		my @r    = `$findpid`;

		foreach(@r) {
			$_ =~ s/^\s+//;
			my ($p, $c) = split(/\s+/, $_, 2);
			chomp($p);
			push @pid, $p;
		}
	}
	return join(" ", @pid);
}

#*****************************************************************************************************
# Subroutine			: killPid
# Objective				: Terminate a process
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub killPid {
	my $pid = shift;
	$pid    =~ s/^\s+|\s+$//g;
	return 0 if (!$pid);

	my $errorFile = Helpers::getECatfile(Helpers::getServicePath(), 'kill.err');
	my $status = system("kill -9 $pid 2>$errorFile");
	my $errorStr;

	if ($? > 0 and -e $errorFile) {
		if (open(my $p, '<', $errorFile)) {
			$errorStr = <$p>;
			close($p);
			unlink($errorFile);
		}
		else {

			if($Configuration::callerEnv eq 'BACKGROUND'){
				Helpers::traceLog(['failed_to_open_file', ": $errorFile"]);
			} else {
				Helpers::display(['failed_to_open_file', ': ', $errorFile]);
			}
		}
		if ($errorStr =~ 'Operation not permitted') {
			if($Configuration::callerEnv eq 'BACKGROUND'){
				Helpers::traceLog('unable_to_kill_job');
			} else {
				Helpers::display('operation_not_permitted');
			}
		}
		elsif ($errorStr =~ 'No such process') {
			if($Configuration::callerEnv eq 'BACKGROUND'){
				Helpers::traceLog('this_job_might_be_stopped_already');
			} else {
				Helpers::display('this_job_might_be_stopped_already');
			}
		}
		return 0;
	}
	unlink($errorFile);

	return 1;
}

#*****************************************************************************************************
# Subroutine			: getOptions
# Objective				: Prepare key-string values for all running jobs.
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getOptions {
	my %jobs = @_;
	my @options;
	foreach my $job (keys %jobs) {
		push @options, "stop_$job";
	}
	return @options;
}
