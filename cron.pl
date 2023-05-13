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

use POSIX qw(mktime strftime :sys_wait_h);
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

use lib map{if(cronabs() =~ /\//) { substr(cronabs(), 0, rindex(cronabs(), '/')) . "/$_";} else { "./$_"; }} qw(Idrivelib/lib);
use lib map{if (__FILE__ =~ /\//) { if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));} else {substr(__FILE__, 0, rindex(__FILE__, '/')) . "/$_";}} else {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));} else {"./$_";}}} qw(Idrivelib/lib .);

use AppConfig;
use Common;

unless(-l __FILE__) {
	$AppConfig::displayHeader = 0;
	Common::retreat('you_cant_run_supporting_script');
}

$SIG{INT}	= \&clearlock;
$SIG{TERM}	= \&clearlock;
$SIG{TSTP}	= \&clearlock;
$SIG{QUIT}	= \&clearlock;
#$SIG{PWR}	= \&clearlock;
$SIG{KILL}	= \&clearlock;
$SIG{STOP}	= \&clearlock;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is used to load and run cron jobs
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	Common::loadAppPath();
	Common::setServicePath(".") if (!Common::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if ($AppConfig::mcUser ne 'root');

	# IMPORTANT: DO NOT REMOVE: unconditional sleep to handle self restart situation
	sleep(3);

	# verify whether cron is already running or not. exit conditions met
	if (Common::checkCRONServiceStatus() == Common::CRON_RUNNING) {
		# execution reaches here in this scope if the cron is running from fallback logic
		my @lockinfo = Common::getCRONLockInfo();

		# if latest version of cron executes the script, then we need to perform a self reboot+abort.
		if (Common::versioncompare($AppConfig::version, $lockinfo[1]) == 1) {
			bootloadCronRestart();
		}
		else {
			exit(0);
		}
	}

	Common::fileWrite($AppConfig::cronlockFile, qq($$--$AppConfig::version--running));
	open(my $lockfh, ">>", $AppConfig::cronlockFile);
	# when the file lock check comes from non-root user, fopen fails. so need full permission to this lock
	chmod($AppConfig::filePermission, $AppConfig::cronlockFile);
	flock($lockfh, LOCK_EX|LOCK_NB);

	benchmark('init');
	$0 = $AppConfig::appType.':CRON';
	$AppConfig::displayHeader = 0;

	Common::loadCrontab();

	my $lastctmodtime = ((-f Common::getCrontabFile())? stat(Common::getCrontabFile())->mtime : 0);
	my @prevtime;
	my @curtime;

	my $srvpid = 0;
	if ($AppConfig::appType eq 'IDrive') {
		my $dashcrontab = Common::getCrontab();
		launchCDPJobs($dashcrontab);
		launchDashboardJobs($dashcrontab);
		sleep(3);
		
		if(!Common::isDashboardRunning()) {
			$srvpid = fork();
			if($srvpid == 0) {
				my $inc = 6;
				while($inc) {
					launchDashboardJobs($dashcrontab);
					sleep(5);

					exit(0) if(Common::isDashboardRunning());

					$inc--;
					sleep(5);
				}

				exit(0);
			}

			waitpid($srvpid, WNOHANG);
		}
		
	}

	my $prevtimesec = time();
	chomp($prevtimesec);

	while(1) {
		if($srvpid) {
			my $fres = waitpid($srvpid, WNOHANG);
			if($fres == -1 or $fres > 0) {
				$srvpid = 0;
			}
		}

		# exit if lock file is absent
		exit(0) unless(-f $AppConfig::cronlockFile);

		# check the lock file if there is a request to boot restart the cron service.
		my @lockinfo 	= Common::getCRONLockInfo();
		# exit if not lock process id same
		exit(0) if ($$ != $lockinfo[0]);

		bootloadCronRestart() if (defined($lockinfo[2]) && $lockinfo[2] eq 'restart');

		# Handle abrupt date/time change in server
		my $currtimesec = time();
		chomp($currtimesec);
		my $diff = $currtimesec - $prevtimesec ;
		if ($diff < 0 || $diff > 70) {
			if ($AppConfig::appType eq 'IDrive') {
				# kill all instances of dashboard
				if ($AppConfig::machineOS =~ /freebsd/i) {
					my $dashids = `"ps -x | awk '\$5==\"IDrive:dashboard\" {print \$1}'"`;
					my @dbids = split("\n", $dashids);
					for my $dbidkey(0 .. scalar(@dbids)) {
						system("kill $dbids[$dbidkey]") if ($dbids[$dbidkey]);
					}
				}
				else {
					system("killall IDrive:dashboard 1>/dev/null 2>/dev/null");
				}
			}
			$lockinfo[2] = 'restart';
			Common::fileWrite($AppConfig::cronlockFile, join('--', @lockinfo));
			benchmark("Due to abrupt change in Date/Time cron has been restarted.");
		}

		# this will handle the absence situation of cron tab file
		$prevtimesec = $currtimesec;

		unless(-f Common::getCrontabFile()) {
			benchmark("no cron tab, sleeping");
			Common::fileWrite(Common::getCrontabFile(), '');
			chmod($AppConfig::filePermission, Common::getCrontabFile());
			sleep(20);
			next;
		}

		# Handle empty cron tab file
		if(-z Common::getCrontabFile()) {
			benchmark("empty cron tab, sleeping");
			sleep(20);
			next;
		}

		# Launch dashboard and cron jobs once a day
		my ($locmin, $lochour, $locdom, $locmon, $locdow, $locyear) = (localtime)[1, 2, 3, 4, 6, 5];
		if($locmin == 1 && $lochour == 1 && $AppConfig::appType eq 'IDrive') {
			my $dashcrontab = Common::getCrontab();
			# launchDashboardJobs($dashcrontab);
			launchCDPJobs($dashcrontab);
		}

		if(($locmin % 10) == 0) {
			my $dashcrontab = Common::getCrontab();
			launchDashboardJobs($dashcrontab);
		}

		# if modified time stamp is greater than the previous time stamp, then load cron tab again
		if (stat(Common::getCrontabFile())->mtime > $lastctmodtime) {
			$lastctmodtime = stat(Common::getCrontabFile())->mtime;
			Common::loadCrontab();
		}

		my $crontab = Common::getCrontab();
		my $cronEntries = getEntries($crontab);
		@prevtime = localtime();
		my ($index, $launchTime);
		while ($cronEntries->[0]->Length > 0) {
			($index, $launchTime) = $cronEntries->[0]->Shift;
			execute($launchTime, $cronEntries->[1]->{$index});
		}

		$crontab = undef;
		$cronEntries = undef;

		# in case the execute method takes time we need to avoid un necessary cron restart
		$prevtimesec = time();

		@curtime 	= localtime();
		# check if the execution passed a minute or not while launching the cron entries
		# if it moves to next minute, then again we have to run the job.
		# sleep for 60 - secs, as we dont want to run the job again
		if (($curtime[1] - $prevtime[1]) == 0) {
			my $timeIndex = 60 - $curtime[0];
			while($timeIndex - 10 > 10) {
				my @lockinfo 	= Common::getCRONLockInfo();
				# exit if not lock process id same
				exit(0) if ($lockinfo[0] && $$ != $lockinfo[0]);

				bootloadCronRestart() if (defined($lockinfo[2]) && $lockinfo[2] eq 'restart');
				sleep(10);
				$timeIndex -= 10;
			}

			my @lockinfo 	= Common::getCRONLockInfo();
			# exit if not lock process id same
			exit(0) if ($$ != $lockinfo[0]);

			bootloadCronRestart() if (defined($lockinfo[2]) && $lockinfo[2] eq 'restart');
			sleep($timeIndex + 2); # Sleep 2 more seconds to fix the skew
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
	my ($nowMin, $nowHour, $nowDom, $nowMon, $nowDow, $nowYear) = (localtime)[1, 2, 3, 4, 6, 5];
	$nowMon++;
	$nowDow--;
	$nowYear += 1900;
	my %queue = ();
	my $queueCount = 0;
	my $indjob;
	my ($jobdom, $jobm);
	my $t = tie(my %sortedQueue, 'Tie::IxHash');

	foreach my $mcusername (keys %{$_[0]}) {
		foreach my $username (keys %{$_[0]->{$mcusername}}) {
			# cron from this user is disabled | go to next idriveuser
			next if(defined($_[0]->{$mcusername}{$username}{'otherInfo'}) && $_[0]->{$mcusername}{$username}{'otherInfo'}{'settings'}{'status'} eq 'INACTIVE');

			foreach my $jobType (keys %{$_[0]->{$mcusername}{$username}}) {
				next if($jobType eq $AppConfig::dashbtask || $jobType eq $AppConfig::cdpwatcher || $jobType eq 'otherInfo');

				foreach(keys %{$_[0]->{$mcusername}{$username}{$jobType}}) {
					$indjob = $_[0]->{$mcusername}{$username}{$jobType}{$_};
					$jobdom	= defined($indjob->{'dom'})? $indjob->{'dom'} : '';
					$jobdom	=~ s/\*\///;

					$jobm	= defined($indjob->{'m'})? $indjob->{'m'} : '';
					$jobm	=~ s/\*\///;

					if(defined($indjob->{'settings'}{'status'}) && $indjob->{'settings'}{'status'} eq 'disabled') {
						# benchmark("next #user: $username#mcusername: $mcusername#jobType: $jobType#jobset: $_# disabled");
						next;
					} elsif(!defined($indjob->{'mon'}) || not $indjob->{'mon'} =~ /\*|$nowMon/) {
						# benchmark("next #user: $username#mcusername: $mcusername#jobType: $jobType#jobset: $_#mon: $indjob->{'mon'}");
						next;
					} elsif(!defined($indjob->{'dom'}) || ($indjob->{'dom'} !~ /\*\/\d/ && not $indjob->{'dom'} =~ /\*|$nowDom/) || ($indjob->{'dom'} =~ /\*\/\d/ && ($nowDom % $jobdom != 0))) {
						# benchmark("next #user: $username#mcusername: $mcusername#jobType: $jobType#jobset: $_#dom: $indjob->{'dom'}");
						next;
					} elsif(!defined($indjob->{'dow'}) || not $indjob->{'dow'} =~ /\*|$AppConfig::weeks[$nowDow]/) {
						# benchmark("next #user: $username#mcusername: $mcusername#jobType: $jobType#jobset: $_#dow: $indjob->{'dow'}");
						next;
					} elsif(($indjob->{'h'} =~ /\d+/) && ($indjob->{'h'} < $nowHour)) {
						# benchmark("next #user: $username#mcusername: $mcusername#jobType: $jobType#jobset: $_#h: $indjob->{'h'}");
						next;
					} elsif(($indjob->{'m'} !~ /\*\/\d/ && $indjob->{'m'} < $nowMin) || ($indjob->{'m'} =~ /\*\/\d/ && ($nowMin % $jobm != 0))) {
						# benchmark("next #user: $username#mcusername: $mcusername#jobType: $jobType#jobset: $_#m: $indjob->{'m'}");
						next;
					}

					my $hour	= $indjob->{'h'};
					$hour		= $nowHour if($indjob->{'h'} eq '*');
					$jobm		= $nowMin if($indjob->{'m'} =~ /\*\/\d/ && $nowMin % $jobm == 0);
					my $time	= mktime(0, $jobm, $hour, $nowDom, ($nowMon - 1), ($nowYear - 1900));
					$sortedQueue{$queueCount} = $time;

					$queue{$queueCount}{'jobType'}	= $jobType;
					$queue{$queueCount}{'jobName'}	= $_;
					$queue{$queueCount}{'cmd'}		= $indjob->{'cmd'};
					
					if($jobType eq $AppConfig::misctask && $_ eq $AppConfig::miscjob) {
						$queue{$queueCount}{'mcUser'}	= 'root';
					} else {
						$queue{$queueCount}{'mcUser'}	= $mcusername;
					}
					
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
	return 0 unless (Common::hasDashboardSupport());

	my $djobs = $_[0];
	return 0 unless(%{$djobs});

	my $userModUtilCMD	= Common::getUserModUtilCMD();
	foreach my $mcusername (keys %{$djobs}) {
		foreach my $username (keys %{$djobs->{$mcusername}}) {
			# dashboard from this user is disabled | go to next idriveuser
			next if(defined($djobs->{$mcusername}{$username}{'otherInfo'}) && $djobs->{$mcusername}{$username}{'otherInfo'}{'settings'}{'status'} eq 'INACTIVE');

			next if(!defined($djobs->{$mcusername}{$username}{$AppConfig::dashbtask}) ||
				!%{$djobs->{$mcusername}{$username}{$AppConfig::dashbtask}{$AppConfig::dashbtask}} ||
				$djobs->{$mcusername}{$username}{$AppConfig::dashbtask}{$AppConfig::dashbtask}{'cmd'} eq '');

			my $dashcmd = $djobs->{$mcusername}{$username}{$AppConfig::dashbtask}{$AppConfig::dashbtask}{'cmd'};
			if($userModUtilCMD ne '') {
				$dashcmd	=~ s/'/'\\''/g;
				$dashcmd 	= "$userModUtilCMD $mcusername -c '" . Common::getIDrivePerlBin() . " \"$dashcmd\" &'";
				system($dashcmd);
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: launchCDPJobs
# Objective				: This function is to execute the CDP jobs
# Added By				: Vijay Vinoth
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub launchCDPJobs {
	my $djobs = $_[0];
	return 0 unless(%{$djobs});

	my $userModUtilCMD	= Common::getUserModUtilCMD();
	foreach my $mcusername (keys %{$djobs}) {
		foreach my $username (keys %{$djobs->{$mcusername}}) {
			# CDP from this user is disabled | go to next idriveuser
			next if(defined($djobs->{$mcusername}{$username}{'otherInfo'}) && $djobs->{$mcusername}{$username}{'otherInfo'}{'settings'}{'status'} eq 'INACTIVE');

			next if(!defined($djobs->{$mcusername}{$username}{$AppConfig::cdpwatcher}) ||
				!%{$djobs->{$mcusername}{$username}{$AppConfig::cdpwatcher}{$AppConfig::cdpwatcher}} ||
				$djobs->{$mcusername}{$username}{$AppConfig::cdpwatcher}{$AppConfig::cdpwatcher}{'cmd'} eq '');

			my $cdpcmd = $djobs->{$mcusername}{$username}{$AppConfig::cdpwatcher}{$AppConfig::cdpwatcher}{'cmd'};
			if($userModUtilCMD ne '') {
				unless($AppConfig::perlBin) {
					my $perlBin = Common::getPerlBinaryPath();
					$AppConfig::perlBin = $perlBin;
					$AppConfig::perlBin = 'perl' unless(-f $perlBin);
				}

				$cdpcmd	=~ s/'/'\\''/g;
				$cdpcmd = "$userModUtilCMD $mcusername -c '" . $AppConfig::perlBin . " $cdpcmd &'";
				system($cdpcmd);
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
	my ($nowSec, $nowMin, $nowHour, $nowDom, $nowMon, $nowYear) = (localtime)[0, 1, 2, 3, 4, 5];
	# With 0 seconds
	my $nowInEpoch2 = mktime(0, $nowMin, $nowHour, $nowDom, $nowMon, $nowYear);

	return 1 if ($_[0] > $nowInEpoch2);

	# exec never returns unless there was a failure.
	# So using a block by itself will not terminate the script.
	my $cronmcuser 		= $_[1]->{'mcUser'};
	my $escapeCMD 		= $_[1]->{'cmd'};
	my $userModUtilCMD	= Common::getUserModUtilCMD();
	
	if($_[1]->{'jobType'} eq "dashboardfallback") {
		my $dashcmd = $escapeCMD;
		if($userModUtilCMD ne '') {
			$dashcmd	=~ s/'/'\\''/g;
			$dashcmd 	= "$userModUtilCMD $cronmcuser -c '" . Common::getIDrivePerlBin() . " \"$dashcmd\" &'";
			system($dashcmd);
		}
	}
	elsif($userModUtilCMD ne '') {
		# $AppConfig::perlBin = 'perl' unless($AppConfig::perlBin);
		# Added to resolve the FreeBSD issue
		# Got error "su: perl: command not found"
		unless($AppConfig::perlBin) {
			my $perlBin = Common::getPerlBinaryPath();
			$AppConfig::perlBin = $perlBin;
			$AppConfig::perlBin = 'perl' unless(-f $perlBin);
		}

		$escapeCMD	=~ s/'/'\\''/g;
		$escapeCMD	= "$userModUtilCMD $cronmcuser -c '$AppConfig::perlBin $escapeCMD &'";

		# benchmark($escapeCMD);
		system($escapeCMD);
		# benchmark($!);
	}
	else {
		# benchmark("$AppConfig::perlBin $escapeCMD &");
		system("$AppConfig::perlBin $escapeCMD &");
	}

	# benchmark('end of execution');
	return 1;
}

#*****************************************************************************************************
# Subroutine			: clearlock
# Objective				: This method clears the shared cron lock
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub clearlock {
	unlink($AppConfig::cronlockFile);
}

#*****************************************************************************************************
# Subroutine			: bootloadCronRestart
# Objective				: This method should be invoked only from cron script
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub bootloadCronRestart {
	my $opconf			= Common::getCRONSetupTemplate();
	my @oldlockinfo		= Common::getCRONLockInfo();
	my $os				= Common::getOSBuild();

	if($opconf->{'restartcmd'} ne '') {
		# benchmark("start boot: ".$opconf->{'restartcmd'});
		unlink($AppConfig::cronlockFile);
		unlink($AppConfig::cronservicepid) if($AppConfig::machineOS =~ /gentoo/i);

		my $shpath = `which sh 2>/dev/null`;
		chomp($shpath);

		if($shpath && $opconf->{'serv-mod'} eq 'ups' && $os->{'os'} eq 'ubuntu') {
			if(defined($oldlockinfo[3]) && $oldlockinfo[3] eq 'update') {
				launchFallbackHandler();
				exit(0);
			} else {
				unlink($AppConfig::cronlockFile);
				system("sh -c $opconf->{'restartcmd'} 1>/dev/null 2>/dev/null");
			}
		} else {
			system("$opconf->{'restartcmd'} 1>/dev/null 2>/dev/null");
		}

		#benchmark("end boot");
		# in case restart cmd fails to restart, we need to wait for the script to acquire the lock
		sleep(5);
	}

	my @newlockinfo		= Common::getCRONLockInfo();

	if((defined($oldlockinfo[0]) && defined($newlockinfo[0]) && $oldlockinfo[0] == $newlockinfo[0]) ||
	Common::checkCRONServiceStatus() != Common::CRON_RUNNING) {
		launchFallbackHandler();
	}

	exit(0);
}

#*****************************************************************************************************
# Subroutine	: launchFallbackHandler
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Restarts the service with fallback method
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub launchFallbackHandler {
	my @lockinfo 	= Common::getCRONLockInfo();

	# unconditional sleep of 3 seconds added in the beginning to handle this fallback
	system("$AppConfig::perlBin $AppConfig::cronLinkPath &");

	# kill already running process so that it will release and remove share lock
	system("kill $lockinfo[0]") if ($lockinfo[0]);
}

#*****************************************************************************************************
# Subroutine			: benchmark
# Objective				: This method is to track the cron acrivity
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub benchmark {
	# print $_[0] . "\n";
	# Common::traceLog($_[0]);

	# if(open LOG_TRACE_HANDLE, ">>", "/tmp/testTrace.txt" ) {
	#	print LOG_TRACE_HANDLE $_[0]."\n";
	#	close(LOG_TRACE_HANDLE);
	# }

	# Common::traceLog(strftime("%d/%m/%Y %H:%M:%S", localtime(time)));
}
