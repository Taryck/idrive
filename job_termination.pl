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

use Common;
use AppConfig;

my $cmdNumOfArgs = $#ARGV;

init();

#*****************************************************************************************************
# Subroutine			: init
# In Param              : $ARGV[0]=>jobName, $ARGV[1]=>'IDrive user', $ARGV[2]=>JobType(all/manual/scheduled),
#						  $ARGV[3]=>force to kill all, $ARGV[4]=>'Linux user', $ARGV[5]=>'Error message/Reason for termination'
# Objective				: This function is entry point for the script
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub init {
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::verifyVersionConfig();

	$AppConfig::callerEnv = 'BACKGROUND' unless ($cmdNumOfArgs == -1);
	my $killall = (defined($ARGV[3]) && $ARGV[3] eq 'allType')? 1 : 0;

	if ($cmdNumOfArgs >= 1 and $ARGV[1] ne '-') {
		Common::setUsername($ARGV[1]);
	}
	else {
		Common::loadUsername() or Common::retreat('login_&_try_again');
	}

	$AppConfig::mcUser = $ARGV[4] if(defined($ARGV[4])); #Added to terminate all profile's jobs 
	my $errorKey = Common::loadUserConfiguration();
	# Common::retreat($AppConfig::errorDetails{$errorKey}) if($AppConfig::callerEnv ne 'BACKGROUND' and $errorKey == 104);
    Common::retreat($AppConfig::errorDetails{$errorKey}) if($AppConfig::callerEnv ne 'BACKGROUND' and defined($AppConfig::errorDetails{$errorKey}));
	Common::loadEVSBinary()  or Common::retreat('unable_to_find_or_execute_evs_binary');
	Common::isLoggedin()     or Common::retreat('login_&_try_again') if($AppConfig::callerEnv ne 'BACKGROUND');
	Common::displayHeader() unless($cmdNumOfArgs == 1);

	my $jobName = undef;
	$jobName = $ARGV[0] if(defined($ARGV[0]) and $ARGV[0] ne 'allOp');
	my %jobs = Common::getRunningJobs($jobName, $ARGV[2] || 0);
	if (!%jobs) {
		if ($AppConfig::callerEnv eq 'BACKGROUND'){
			if($ARGV[0] eq 'allOp'){
				Common::traceLog('no_job_is_in_progress');
			} else {
				Common::traceLog($ARGV[0].'_not_running');
			}
		} else {
			Common::display('no_job_is_in_progress');
		}
		exit 0;
	}

	my @options = getOptions(%jobs);
	my $userSelection = 1;

	if ($AppConfig::callerEnv ne 'BACKGROUND') {
		if (scalar(@options) > 1) {
			Common::display('you_can_stop_one_job_at_a_time')
		}

		Common::displayMenu('select_the_job_from_the_above_list', @options);
		Common::display('');
		$userSelection = Common::getUserMenuChoice(scalar(@options));
	}

REPEAT:
	my $cancelFile = '';
	if (Common::validateMenuChoice($userSelection, 1, scalar(@options))) {
		$options[($userSelection - 1)] =~ s/stop_//g;
		my $pid = getPid($jobs{$options[($userSelection - 1)]});
		$cancelFile = $jobs{$options[($userSelection - 1)]};
		$cancelFile =~ s/pid.txt$/exitError.txt/g;

		if ($cmdNumOfArgs == -1) {
			if (open(my $fh, '>', $cancelFile)) {
				Common::traceLog('Operation Cancelled by user');
				print $fh Common::getStringConstant('operation_cancelled_by_user');
				close $fh;
			}
			else {
				Common::retreat(['unable_to_create_file', " \"$cancelFile\". Reason: $!." ]);
			}
		}
		elsif (defined($ARGV[5])) {
			unless(Common::fileWrite($cancelFile,Common::getStringConstant($ARGV[5]))) {
				Common::retreat(['unable_to_create_file', " \"$cancelFile\"." ]);
			}
			Common::traceLog(Common::getStringConstant($ARGV[5]));
		}

		# Keep this file as a flag for checking scheduled backup was terminated by user or not
		if($cmdNumOfArgs == -1) {
			my $schcfile = $jobs{$options[($userSelection - 1)]};
			$schcfile =~ s/pid.txt$/$AppConfig::schtermf/g;
			Common::fileWrite($schcfile, '1');
		}

		if ($pid ne "" && !killPid($pid)) {
			unlink($cancelFile) if(-f $cancelFile);
			exit(0) unless($killall);
		}
		else {
			if (-e $jobs{$options[($userSelection - 1)]}) {
				unlink($jobs{$options[($userSelection - 1)]});
				if($AppConfig::callerEnv eq 'BACKGROUND'){
					Common::traceLog([$options[($userSelection - 1)], " ", 'job_terminated_successfully']);
				} else {
					Common::display([$options[($userSelection - 1)], " ", 'job_terminated_successfully']);
				}
			} else {
				if($AppConfig::callerEnv eq 'BACKGROUND'){
					Common::traceLog('no_job_is_in_progress');
				} else {
					Common::display('no_job_is_in_progress');
				}
				exit(0);
			}
		}

		if($killall) {
			exit(0) if($userSelection == scalar(@options));
			$userSelection++;
			goto REPEAT;
		}
	}
	else {
		Common::display(['invalid_choice',"\n"]);
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
		Common::traceLog(['failed_to_open_file', ": @_"]);
		return "";
	}

	my ($findpid, $r, $pid);
	my (@pid, @cmd);

	if($parentpid){
		$findpid = qq{ps -o sid= -p$parentpid | xargs pgrep -s | xargs ps -o pid,command -p | grep idev | grep -v "grep"};
		# $findpid = Common::updateLocaleCmd($findpid);
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
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub killPid {
	my $pid = shift;
	$pid    =~ s/^\s+|\s+$//g;
	return 0 if (!$pid);

	my $errorfile	= Common::getCatfile(Common::getServicePath(), 'kill.err');
	my $errescfile	= Common::getECatfile(Common::getServicePath(), 'kill.err');
	my $status = system("kill $pid 2>$errescfile");
	my $errorStr;

	if ($? > 0 and -f $errorfile) {
		if (open(my $p, '<', $errorfile)) {
			$errorStr = <$p>;
			close($p);
			unlink($errorfile);
		}
		else {
			if($AppConfig::callerEnv eq 'BACKGROUND'){
				Common::traceLog(['failed_to_open_file', ": $errorfile"]);
			} else {
				Common::display(['failed_to_open_file', ': ', $errorfile]);
			}
		}

		if ($errorStr =~ 'Operation not permitted') {
			if($AppConfig::callerEnv eq 'BACKGROUND'){
				Common::traceLog('unable_to_kill_job');
			} else {
				Common::display('operation_not_permitted');
			}
		}
		elsif ($errorStr =~ 'No such process') {
			if($AppConfig::callerEnv eq 'BACKGROUND'){
				Common::traceLog('this_job_might_be_stopped_already');
			} else {
				Common::display('this_job_might_be_stopped_already');
			}
		}

		return 0;
	}

	unlink($errorfile);
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
