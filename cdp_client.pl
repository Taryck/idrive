#!/usr/bin/env perl
#*****************************************************************************************************
# This script runs as service for cdp client
#
# Created By: Vijay Vinoth @ IDrive Inc
# Modified By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Fcntl qw(:flock SEEK_END);
use AppConfig;
use Common;

Common::checkAndAvoidExecution($ARGV[0]);

eval {
	require Cdp;
	Cdp->import();
};

$SIG{INT}	= \&Cdp::cleanUp;
$SIG{TERM}	= \&Cdp::cleanUp;
$SIG{TSTP}	= \&Cdp::cleanUp;
$SIG{QUIT}	= \&Cdp::cleanUp;
$SIG{KILL}	= \&Cdp::cleanUp;
$SIG{USR1}	= \&Cdp::cleanUp;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This subroutine will initiate the cdp job
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub init {
	$0 = 'IDrive:CDP-client';

	Common::loadAppPath();
	Common::loadServicePath();
	Common::loadUserConfiguration() if(Common::loadUsername());

	my $cdpclientlock = Common::getCDPLockFile('client');
	exit(0) if(Common::isFileLocked($cdpclientlock));

	my $cdpserverlock	= Common::getCDPLockFile('server');
	my $cdpwatcherlock	= Common::getCDPLockFile('watcher');
	my $lpfile			= Common::getCDPLockFile('lport');

	exit(0) unless(-f $lpfile);

	my $lockfh;
	exit(0) unless(open($lockfh, ">", $cdpclientlock));
	print $lockfh $$;
	exit(0) unless(flock($lockfh, LOCK_EX|LOCK_NB));
	
	Common::traceLog('CDP client started');

	my ($dirswatch, $jsjobselems, $jsitems);
	while(1) {
		($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
		last if(scalar(@{$dirswatch}));
		sleep(5);
	}

	my $grepdirssub = sub {
		my ($dir) = @_;
		return 1;
	};

	# DO NOT change the following line
	my ($apppath, $servpath) = (Common::getCatfile(Common::getAppPath()), Common::getCatfile(Common::getServicePath()));

	$AppConfig::localPort = Common::getFileContents($lpfile);
	Cdp::clientSocketInit();

	my $inotify = new Cdp({
		'grep_dirs_sub' => $grepdirssub,
	}) or Common::traceLog(["Unable to create new inotify object: $!"]);

	my @wdirs = ();
	map{$_ =~ s/\/$//; push @wdirs, $_;} @{$dirswatch};
	# remove system folders so that inotify will not end up in watch error
	foreach my $pti (0 .. $#wdirs) {
		delete $wdirs[$pti] if(grep {"$wdirs[$pti]/" =~ /^\Q$_\E/} @AppConfig::defexcl);
	}

	my %index = ();
	# remove empty items
	@wdirs = grep{$_} @wdirs;
	# remove duplicates
	@wdirs = grep{!$index{$_}++} @wdirs;

	$inotify->add_dirs(\@wdirs);

	for my $windex (0 .. $#{$dirswatch}) {
		$inotify->watch_file($dirswatch->[$windex]) if(defined($dirswatch->[$windex]) && -f $dirswatch->[$windex]);
	}

	$inotify->item_to_remove_by_name($apppath, 1);
	$inotify->item_to_remove_by_name($servpath, 1);

	# Main event loop.
	my $ts		= time();
	my $wpid	= Common::getFileContents($cdpwatcherlock);
	chomp($wpid);

	1 while $inotify->pool(\$ts, $cdpclientlock, $cdpserverlock, $cdpwatcherlock, $wpid);
}