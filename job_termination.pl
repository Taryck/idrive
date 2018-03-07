#!/usr/bin/perl
use strict;
#use warnings;

#-------------------------------------------------------------------------------
# Find and terminate running jobs like backup/restore including scheduled ones.
#
# Created By : Yogesh Kumar
# Reviewed By: Deepak Chaurasia
#-------------------------------------------------------------------------------

use lib substr(__FILE__, 0, rindex(__FILE__, '/'));

use Helpers;
use Strings;
use Configuration;

my $cmdNumOfArgs = $#ARGV;

init();

#*******************************************************************************
# This script starts & ends in init()
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub init {
	Helpers::loadSourceCodesPath();
	$Configuration::callerEnv = 'SCHEDULER' unless ($cmdNumOfArgs == -1);

	Helpers::loadServicePath() or Helpers::retreat('invalid_service_directory');

	if ($cmdNumOfArgs == 1) {
		Helpers::setUsername($ARGV[1]);
	}
	else {
		Helpers::loadUsername() or Helpers::retreat('login_&_try_again');
	}

	Helpers::loadUserConfiguration() or Helpers::retreat('failed');
	Helpers::isLoggedin()            or Helpers::retreat('login_&_try_again');

	Helpers::displayHeader();

	my %jobs = getRunningJobs();
	if (!%jobs) {
		unless ($cmdNumOfArgs == -1){
			Helpers::display($ARGV[0].'_not_running');
		} else {
			Helpers::display('no_backup_or_restore_is_running');
		}
		exit 0;
	}

	my @options = getOptions(%jobs);
	my $userSelection;

	if ($cmdNumOfArgs == -1) {
		if (scalar(@options) > 1) {
			Helpers::display('you_can_stop_one_job_at_a_time')
		}

		Helpers::displayMenu('',@options);
		$userSelection = Helpers::getUserChoice(1,'select_the_job_from_the_above_list',scalar(@options));
	}
	else {
		$userSelection = 1;
	}

	if (Helpers::isValidSelection($userSelection, scalar(@options))) {
		$options[($userSelection - 1)] =~ s/stop_//g;
		my $pid = getPid($jobs{$options[($userSelection - 1)]});
		if ($options[($userSelection - 1)] =~ /^scheduled_/ and $cmdNumOfArgs == -1) {
			#my $cancelFile = ($jobs{$options[($userSelection - 1)]} =~ s/pid.txt$/cancel.txt/gr);
			my $cancelFile = $jobs{$options[($userSelection - 1)]};
			$cancelFile =~ s/pid.txt$/cancel.txt/g;
			if (open(my $fh, '>', $cancelFile)) {
				print $fh "Operation could not be completed, Reason: Operation Cancelled by user";
				close $fh;
			}
			else {
				Helpers::retreat(['unable_to_create_file', " \"$cancelFile\"" ]);
			}
		}
		
		if ($pid != "" && !killPid($pid)) {	
			exit(1);
		}
		else {
			if(-e $jobs{$options[($userSelection - 1)]}){
				unlink($jobs{$options[($userSelection - 1)]});
				Helpers::display([$options[($userSelection - 1)],
													" ",
													'job_terminated_successfully']);
			} else {
				Helpers::display('no_backup_or_restore_is_running');
				exit(1);
			}
		}
	}
	else {
		Helpers::display('invalid_option');
	}
}

#*******************************************************************************
# Find and return PID(s) of backup or restore processes
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getPid {
	my $parentpid;
	if (open(my $p, '<:encoding(UTF-8)', @_)) {
		$parentpid = <$p>;
		close($p);
	}
	else {
		#Helpers::display(['unable_to_read_file', ': ', @_]);
		return "";
	}
	chomp($parentpid);
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

#*******************************************************************************
# Terminate a process
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub killPid {
	my $pid = shift;
	$pid    =~ s/^\s+|\s+$//g;
	return 0 if (!$pid);

	my $errorFile = Helpers::getCatfile(Helpers::getServicePath(), 'kill.err');
	my $status = system("kill -9 $pid 2>$errorFile");
	my $errorStr;

	if ($? > 0) {
		if (open(my $p, '<:encoding(UTF-8)', $errorFile)) {
			$errorStr = <$p>;
			close($p);
			unlink($errorFile);
		}
		else {
			Helpers::display(['unable_to_read_file', ': ', $errorFile]);
		}
		if ($errorStr =~ 'Operation not permitted') {
			Helpers::retreat('operation_not_permitted');
		}
		elsif ($errorStr =~ 'No such process') {
			Helpers::display('this_job_might_be_stopped_already');
		}
		return 0;
	}
	unlink($errorFile);

	return 1;
}

#*******************************************************************************
# Check if pid file exists & file is locked, then return it all
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getRunningJobs {
	my @availableJobs;
	if ($cmdNumOfArgs > -1) {
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
	foreach (@availableJobs) {
		my @p = split '_', $_;
		
		unless (exists $Configuration::availableJobsSchema{$_}) {
			Helpers::retreat([
					'undefined_job_name',
					': ',
					$_]);
		}

		my $pidFile = Helpers::getCatfile(Helpers::getUserProfilePath(),
										ucfirst($p[1]), ucfirst($p[0]), 'pid.txt');

		if (-e $pidFile) {
			if (!Helpers::isFileLocked($pidFile)) {
				unlink($pidFile);
			}
			else {
				$runningJobs{$_} = $pidFile;
			}
		}
	}
	return %runningJobs;
}

#*******************************************************************************
# Prepare key-string values for all running jobs.
#
# Added By: Yogesh Kumar
#*******************************************************************************
sub getOptions {
	my %jobs = @_;
	my @options;
	foreach my $job (keys %jobs) {
		push @options, "stop_$job";
	}
	return @options;
}
