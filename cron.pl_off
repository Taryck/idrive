#!/usr/bin/env perl
#-------------------------------------------------------------------------------
# IDrive cron service
#
# Created By : Yogesh Kumar @ IDrive Inc
# Modified By: Sabin Cheruvattil
# Reviewed By: Deepak Chaurasia
#-------------------------------------------------------------------------------

use strict;
use warnings;

use POSIX qw(mktime strftime);
use Fcntl qw(:flock SEEK_END);
use File::stat;
use File::Basename;
use Cwd qw(abs_path);


#*****************************************************************************************************
# Subroutine			: cronabs | IMPORTANT: DO NOT MOVE THIS SUB
# Objective				: This function is to get absolute path of the script
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub cronabs {
	return ((-l __FILE__)? abs_path(readlink(__FILE__)) : dirname(__FILE__));
}

use lib map{if(cronabs() =~ /\//) { substr(cronabs(), 0, rindex(cronabs(), '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Configuration;
use Helpers;

unless(-l __FILE__) {
	$Configuration::displayHeader = 0;
	Helpers::retreat('you_cant_run_supporting_script');
}

$SIG{INT}  = \&clearlock;
$SIG{TERM} = \&clearlock;
$SIG{TSTP} = \&clearlock;
$SIG{QUIT} = \&clearlock;
#$SIG{PWR} = \&clearlock;
$SIG{KILL} = \&clearlock;
$SIG{STOP} = \&clearlock;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is used to load and run cron jobs
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	Helpers::loadAppPath();
	Helpers::setServicePath(".") if (!Helpers::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($Configuration::mcUser ne 'root');

	# IMPORTANT: DO NOT REMOVE: unconditional sleep to handle self restart situation
	sleep(3);

	# verify whether cron is already running or not. exit conditions met
	if (Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
		# execution reaches here in this scope if the cron is running from fallback logic
		my @lockinfo = Helpers::getCRONLockInfo();

		# if latest version of cron executes the script, then we need to perform a self reboot+abort.
		if (Helpers::versioncompare($Configuration::version, $lockinfo[1]) == 1) {
			bootloadCronRestart();
		}
		else {
			exit(0);
		}
	}

	Helpers::fileWrite($Configuration::cronlockFile, qq($$--$Configuration::version--running));
	open(my $lockfh, ">>", $Configuration::cronlockFile);
	# when the file lock check comes from non-root user, fopen fails. so need full permission to this lock
	chmod($Configuration::filePermission, $Configuration::cronlockFile);
	flock($lockfh, LOCK_EX|LOCK_NB);

	benchmark('init');
	$0 = $Configuration::appType.':CRON';
	$Configuration::displayHeader = 0;

	Helpers::loadCrontab();

	my $lastctmodtime = ((-f Helpers::getCrontabFile())? stat(Helpers::getCrontabFile())->mtime : 0);
	my @prevtime;
	my @curtime;

	# launch dashboard from here | only once we have to start when the cron launches
	if ($Configuration::appType eq 'IDrive') {
		my $dashcrontab = Helpers::getCrontab();
		launchDashboardJobs($dashcrontab);
	}

	my $prevtimesec = time();
	chomp($prevtimesec);

	while(1) {
		# exit if lock file is absent
		exit(0) unless(-f $Configuration::cronlockFile);

		# check the lock file if there is a request to boot restart the cron service.
		my @lockinfo 	= Helpers::getCRONLockInfo();
		# exit if not lock process id same
		exit(0) if ($$ != $lockinfo[0]);

		bootloadCronRestart() if (defined($lockinfo[2]) && $lockinfo[2] eq 'restart');

		# Handle abrupt date/time change in server
		my $currtimesec = time();
		chomp($currtimesec);
		my $diff = $currtimesec - $prevtimesec ;
		if ($diff < 0 || $diff > 70) {
			if ($Configuration::appType eq 'IDrive') {
				# kill all instances of dashboard
				if ($Configuration::machineOS =~ /freebsd/i) {
					my $dashidsCmd = Helpers::updateLocaleCmd("ps -x | awk '\$5==\"IDrive:dashboard\" {print \$1}'");
					my $dashids = `$dashidsCmd`;
					my @dbids = split("\n", $dashids);
					my $killDbIdCmd = '';
					for my $dbidkey(0 .. scalar(@dbids)) {
						if ($dbids[$dbidkey]){
							$killDbIdCmd = Helpers::updateLocaleCmd("kill $dbids[$dbidkey]");
							`$killDbIdCmd`;
						}
					}
				}
				else {
					my $killAllDashCmd = Helpers::updateLocaleCmd("killall IDrive:dashboard 1>/dev/null 2>/dev/null");
					`$killAllDashCmd`;
				}
			}
			$lockinfo[2] = 'restart';
			Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
			benchmark("Due to abrupt change in Date/Time cron has been restarted.");
		}

		# this will handle the absence situation of cron tab file
		$prevtimesec = $currtimesec;

		unless(-f Helpers::getCrontabFile()) {
			benchmark("no cron tab, sleeping");
			Helpers::fileWrite(Helpers::getCrontabFile(), '');
			chmod($Configuration::filePermission, Helpers::getCrontabFile());
			sleep(20);
			next;
		}

		# if modified time stamp is greater than the previous time stamp, then load cron tab again
		if (stat(Helpers::getCrontabFile())->mtime > $lastctmodtime) {
			$lastctmodtime = stat(Helpers::getCrontabFile())->mtime;
			Helpers::loadCrontab();
		}

		my $crontab = Helpers::getCrontab();
		my $cronEntries = getEntries($crontab);
		@prevtime = localtime();
		my ($index, $launchTime);
		while ($cronEntries->[0]->Length > 0) {
			($index, $launchTime) = $cronEntries->[0]->Shift;
			execute($launchTime, $cronEntries->[1]->{$index});
		}

		# in case the execute method takes time we need to avoid un necessary cron restart
		$prevtimesec = time();

		@curtime 	= localtime();
		# check if the execution passed a minute or not while launching the cron entries
		# if it moves to next minute, then again we have to run the job.
		# sleep for 60 - secs, as we dont want to run the job again
		if (($curtime[1] - $prevtime[1]) == 0) {
			my $timeIndex = 60 - $curtime[0];
			while($timeIndex - 10 > 10) {
				my @lockinfo 	= Helpers::getCRONLockInfo();
				# exit if not lock process id same
				exit(0) if ($$ != $lockinfo[0]);

				bootloadCronRestart() if (defined($lockinfo[2]) && $lockinfo[2] eq 'restart');
				sleep(10);
				$timeIndex -= 10;
			}

			my @lockinfo 	= Helpers::getCRONLockInfo();
			# exit if not lock process id same
			exit(0) if ($$ != $lockinfo[0]);

			bootloadCronRestart() if (defined($lockinfo[2]) && $lockinfo[2] eq 'restart');
			sleep($timeIndex);
		}
	}
}

#*****************************************************************************************************
# Subroutine			: getEntries
# Objective				: This function is to get the jobs for the present minute
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub getEntries {
	my ($nowMin, $nowHour, $nowDom, $nowMon, $nowDow, $nowYear) = (localtime)[1,2,3,4,6,5];
	$nowMon++;
	$nowDow--;
	$nowYear += 1900;
	my %queue = ();
	my $queueCount = 0;
	my $t = tie(my %sortedQueue, 'Tie::IxHash');

	foreach my $mcusername (keys %{$_[0]}) {
		foreach my $username (keys %{$_[0]->{$mcusername}}) {
			# cron from this user is disabled | go to next idriveuser
			next if (defined($_[0]->{$mcusername}{$username}{'otherInfo'}) && $_[0]->{$mcusername}{$username}{'otherInfo'}{'settings'}{'status'} eq 'INACTIVE');

			foreach my $jobType (keys %{$_[0]->{$mcusername}{$username}}) {
				next if ($jobType eq 'dashboard');
				next if ($jobType eq 'otherInfo');

				foreach(keys %{$_[0]->{$mcusername}{$username}{$jobType}}) {
					# benchmark("\n\n\nCMD: " . $_[0]->{$mcusername}{$username}{$jobType}{$_}{'cmd'});
					if (defined($_[0]->{$mcusername}{$username}{$jobType}{$_}{'settings'}{'status'}) &&
							$_[0]->{$mcusername}{$username}{$jobType}{$_}{'settings'}{'status'} eq 'disabled') {
						# benchmark("next -$username-0-" . $_);
						next;
					}
					elsif (!defined($_[0]->{$mcusername}{$username}{$jobType}{$_}{'mon'}) ||
							not $_[0]->{$mcusername}{$username}{$jobType}{$_}{'mon'} =~ /\*|$nowMon/) {
						# benchmark("\nnext 1 -$_-". $_[0]->{$mcusername}{$username}{$jobType}{$_}{'mon'});
						next;
					}
					elsif (!defined($_[0]->{$mcusername}{$username}{$jobType}{$_}{'dom'}) ||
							not $_[0]->{$mcusername}{$username}{$jobType}{$_}{'dom'} =~ /\*|$nowDom/) {
						# benchmark("\nnext 2 -$_-".$_[0]->{$mcusername}{$username}{$jobType}{$_}{'dom'});
						next;
					}
					elsif (!defined($_[0]->{$mcusername}{$username}{$jobType}{$_}{'dow'}) ||
							not $_[0]->{$mcusername}{$username}{$jobType}{$_}{'dow'} =~ /\*|$Configuration::weeks[$nowDow]/) {
						# benchmark("\nnext 3 -$_-".$_[0]->{$mcusername}{$username}{$jobType}{$_}{'dow'});
						next;
					}
					elsif (($_[0]->{$mcusername}{$username}{$jobType}{$_}{'h'} =~ /\d+/) && ($_[0]->{$mcusername}{$username}{$jobType}{$_}{'h'} < $nowHour)) {
						# benchmark("\nnext 4 -$_-". $_[0]->{$mcusername}{$username}{$jobType}{$_}{'h'});
						#benchmark('Time is past');
						next;
					}
					elsif ($_[0]->{$mcusername}{$username}{$jobType}{$_}{'m'} < $nowMin) {
						# benchmark("\nnext 5 -$_-". $_[0]->{$mcusername}{$username}{$jobType}{$_}{'m'});
						#benchmark('Time is past');
						next;
					}

					my $hour = $_[0]->{$mcusername}{$username}{$jobType}{$_}{'h'};
					$hour = $nowHour if ($_[0]->{$mcusername}{$username}{$jobType}{$_}{'h'} eq '*');
					my $time = mktime(0, $_[0]->{$mcusername}{$username}{$jobType}{$_}{'m'}, $hour, $nowDom, ($nowMon - 1), ($nowYear - 1900));
					$sortedQueue{$queueCount} = $time;

					$queue{$queueCount}{'jobType'} = $jobType;
					$queue{$queueCount}{'jobName'} = $_;
					$queue{$queueCount}{'cmd'} = $_[0]->{$mcusername}{$username}{$jobType}{$_}{'cmd'};
					$queue{$queueCount}{'mcUser'} = $mcusername;
					$queueCount++;
				}
			}
		}
	}
	$t->SortByValue;
	return [$t, \%queue];
}

#*****************************************************************************************************
# Subroutine			: launchDashboardJobs
# Objective				: This function is to execute the dashboard jobs
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub launchDashboardJobs {
	return 0 unless (Helpers::hasStaticPerlSupport());

	my $djobs = $_[0];
	return 0 unless(%{$djobs});

	my $userModUtilCMD	= Helpers::getUserModUtilCMD();
	#my $execString 		= Helpers::getStringConstant('support_file_exec_string');
	foreach my $mcusername (keys %{$djobs}) {
		foreach my $username (keys %{$djobs->{$mcusername}}) {
			# dashboard from this user is disabled | go to next idriveuser
			next if (defined($djobs->{$mcusername}{$username}{'otherInfo'}) && $djobs->{$mcusername}{$username}{'otherInfo'}{'settings'}{'status'} eq 'INACTIVE');

			next if (!defined($djobs->{$mcusername}{$username}{'dashboard'}) ||
				!%{$djobs->{$mcusername}{$username}{'dashboard'}{'dashboard'}} ||
				$djobs->{$mcusername}{$username}{'dashboard'}{'dashboard'}{'cmd'} eq '');

			my $dashcmd = $djobs->{$mcusername}{$username}{'dashboard'}{'dashboard'}{'cmd'};
			if ($userModUtilCMD ne '') {
				$dashcmd	=~ s/'/'\\''/g;
				$dashcmd 	= "$userModUtilCMD $mcusername -c '" . Helpers::getIDrivePerlBin() . " \"$dashcmd\" &'";
				$dashcmd = Helpers::updateLocaleCmd($dashcmd);
				system($dashcmd);
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: execute
# Objective				: This function is to execute the jobs
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil, Senthil Pandian
#****************************************************************************************************/
sub execute {
	my ($nowSec, $nowMin, $nowHour, $nowDom, $nowMon, $nowYear) = (localtime)[0,1,2,3,4,5];
	my $nowInEpoch  = mktime($nowSec, $nowMin, $nowHour, $nowDom, $nowMon, $nowYear);

	# With 0 seconds
	my $nowInEpoch2 = mktime(0, $nowMin, $nowHour, $nowDom, $nowMon, $nowYear);
	if ($_[0] > $nowInEpoch2) {
		# benchmark("sleeping for " . ($_[0] - $nowInEpoch));
		# sleep(($_[0] - $nowInEpoch));
		return 1;
	}

	# exec never returns unless there was a failure.
	# So using a block by itself will not terminate the script.
	my $cronmcuser = $_[1]->{'mcUser'};
	my $escapeCMD = $_[1]->{'cmd'};
	my $userModUtilCMD = Helpers::getUserModUtilCMD();
	if ($userModUtilCMD ne '') {
		# $Configuration::perlBin = 'perl' unless($Configuration::perlBin);
		# Added to resolve the FreeBSD issue
		# Got error "su: perl: command not found"
		unless($Configuration::perlBin) {
			my $perlBin = Helpers::getPerlBinaryPath();
			$Configuration::perlBin = $perlBin;
			$Configuration::perlBin = 'perl' unless(-f $perlBin);
		}
		$escapeCMD =~ s/'/'\\''/g;
		$escapeCMD = "$userModUtilCMD $cronmcuser -c '$Configuration::perlBin $escapeCMD &'";

		# benchmark($escapeCMD);
		$escapeCMD = Helpers::updateLocaleCmd($escapeCMD);
		system($escapeCMD);
		# benchmark($!);
	}
	else {
		# benchmark("$Configuration::perlBin $escapeCMD &");
		system(Helpers::updateLocaleCmd("$Configuration::perlBin $escapeCMD &"));
	}

	benchmark('end of execution');
	return 1;
}

#*****************************************************************************************************
# Subroutine			: clearlock
# Objective				: This method clears the shared cron lock
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub clearlock {
	unlink($Configuration::cronlockFile);
}

#*****************************************************************************************************
# Subroutine			: bootloadCronRestart
# Objective				: This method should be invoked only from cron script
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub bootloadCronRestart {
	my $opconf			= Helpers::getCRONSetupTemplate();
	my @oldlockinfo		= Helpers::getCRONLockInfo();

	if ($opconf->{'restartcmd'} ne '') {
		benchmark("start boot: ".$opconf->{'restartcmd'});
		unlink($Configuration::cronlockFile);
		unlink($Configuration::cronservicepid) if ($Configuration::machineOS =~ /gentoo/i);
		my $restartCmd = Helpers::updateLocaleCmd("$opconf->{'restartcmd'} 1>/dev/null 2>/dev/null");
		`$restartCmd`;
		benchmark("end boot");
		# in case restart cmd fails to restart, we need to wait for the script to acquire the lock
		sleep(5);
	}
	my @newlockinfo		= Helpers::getCRONLockInfo();

	if ((defined($oldlockinfo[0]) && defined($newlockinfo[0]) && $oldlockinfo[0] == $newlockinfo[0]) ||
	Helpers::checkCRONServiceStatus() != Helpers::CRON_RUNNING) {
		my @lockinfo 	= Helpers::getCRONLockInfo();

		# unconditional sleep of 3 seconds added in the beginning to handle this fallback
		my $runner = Helpers::getScript('cron', 1);
		system(Helpers::updateLocaleCmd("$Configuration::perlBin $runner &"));

		# kill already running process so that it will release and remove share lock
		if ($lockinfo[0]){
			my $killLockCmd = Helpers::updateLocaleCmd("kill $lockinfo[0]");
			`$killLockCmd`;
		}
	}

	exit(0);
}

#*****************************************************************************************************
# Subroutine			: benchmark
# Objective				: This method is to track the cron acrivity
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub benchmark {
	# print $_[0] . "\n";
	# Helpers::traceLog($_[0]);

	# if (open LOG_TRACE_HANDLE, ">>", "/tmp/testTrace.txt" ){
	#	print LOG_TRACE_HANDLE $_[0]."\n";
	#	close(LOG_TRACE_HANDLE);
	# }

	# Helpers::traceLog(strftime("%d/%m/%Y %H:%M:%S", localtime(time)));
}
