#!/usr/bin/env perl
#*****************************************************************************************************
# This script runs as service for cdp server
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Fcntl qw(:flock SEEK_END);
use Common;

Common::checkAndAvoidExecution($ARGV[0]);

use IO::Socket;
use File::stat;
use Sqlite;
use JSON qw(from_json to_json);

$SIG{INT}	= \&cdpcleaup;
$SIG{TERM}	= \&cdpcleaup;
$SIG{TSTP}	= \&cdpcleaup;
$SIG{QUIT}	= \&cdpcleaup;
$SIG{KILL}	= \&cdpcleaup;
$SIG{USR1}	= \&cdpcleaup;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This subroutine will initiate the cdp server job
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub init {
	$0 = 'IDrive:CDP-server';

	Common::loadAppPath();
	Common::loadServicePath();
	Common::loadUserConfiguration() if(Common::loadUsername());

	my $socket_server;
	my $cdpserverlock	= Common::getCDPLockFile('server');
	my $cdpwatcherlock	= Common::getCDPLockFile('watcher');
	exit(0) if(Common::isFileLocked($cdpserverlock));

	my $lockfh;
	exit(0) unless(open($lockfh, ">", $cdpserverlock));
	print $lockfh $$;
	exit(0) unless(flock($lockfh, LOCK_EX|LOCK_NB));
	
	my ($dirswatch, $jsjobselems, $jsitems);
	while(1) {
		Common::stopAllCDPServices() unless(Common::isFileLocked($cdpwatcherlock));

		($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
		last if(scalar(@{$dirswatch}));
		sleep(5);
	}

	my $upddbpaths	= Common::getCDPDBPaths();
	my $cdpjobnames	= ();
	my $wpid		= Common::getFileContents($cdpwatcherlock);
	chomp($wpid);

	my $lpfile		= Common::getCDPLockFile('lport');
	$AppConfig::localPort = $AppConfig::localPortBase + int(rand($AppConfig::localPortRange));
	Common::fileWrite($lpfile, $AppConfig::localPort);

	$socket_server	= new IO::Socket::INET(
		LocalHost	=> $AppConfig::localHost,
		LocalPort 	=> $AppConfig::localPort,
		Proto 		=> $AppConfig::protocol,
		Listen 		=> $AppConfig::listen,
		Reuse 		=> $AppConfig::reuse,
	);

	Common::retreat(['could_not_create_server_socket', ': ',  $!]) unless($socket_server);
	Common::traceLog('CDP server started');

	my $cdpdump		= Common::getCDPDBDumpFile('cdp');
	Common::createDir(Common::dirname($cdpdump), 1) unless(-d Common::dirname($cdpdump));

	my %opdata		= ();
	my $curdata		= {};
	my $objapp		= '';
	my ($idx, $proctype, $proc, $item, $ts) = (0, '', '', '', time());
	my $servpath	= Common::getCatfile(Common::getServicePath(), '');

	my $new_socket	= $socket_server->accept();
	while(<$new_socket>) {
		if(time() - $ts >= $AppConfig::cdpdumptimeout || $idx >= $AppConfig::cdpdumpmaxrec) {
			$cdpdump	= Common::getCDPDBDumpFile('cdp');
			$ts			= time();
			$idx		= 0;

			# check stored watcher pid against the pid read from watcher pid file, exit if not matching, close socket | $wpid
			my $nwpid	= -f $cdpwatcherlock? Common::getFileContents($cdpwatcherlock) : '';
			chomp($nwpid);

			if($nwpid ne $wpid) {
				close($socket_server);
				exit(0);
			}
		}

		$proctype		= '';
		($proc, $item)	= split(/\|/, $_);
		chomp $item;

		$item			=~ s/\s+$//; # Remove last space from the filename

		# keeping this check slows down the notification handling
		# verify item not from service paths
		next if($item =~ /^$servpath/);

		if($proc eq 'IN_CLOSE_WRITE' || $proc eq 'IN_MOVED_TO' || $proc eq 'IN_CREATE') {
			$proctype	= 'ADD';
		} elsif($proc eq 'IN_MOVED_FROM' || $proc eq  'IN_DELETE' || $proc eq  'IN_IGNORED') {
			$proctype	= 'DELETE';
		} elsif($proc eq 'IDR_CST_POST_MOVE') {
			$proctype	= 'DIR_ADD';
		} elsif($proc eq 'IDR_CST_PRE_MOVE' || $proc eq 'IN_DELETE_SELF') {
			$proctype	= 'DIR_DELETE';
			$item = qq($item/);
		}

		next unless($proctype);

		$cdpjobnames	= Common::getDBJobsetsByFile($jsjobselems, $item);

		for my $i (0 .. $#{$cdpjobnames}) {
			$curdata = {'ITEM' => $item, 'JOBNAME' => $cdpjobnames->[$i], 'DBPATH' => $upddbpaths->{$cdpjobnames->[$i]}, 'OPERATION' => $proctype};
			$opdata{$idx} = $curdata;
			$idx++;
		}

		$objapp = to_json(\%opdata);
		$objapp =~ s/^\{//;
		$objapp =~ s/\}$//;
		
		%opdata = ();

		Common::fileWrite($cdpdump, ',' . $objapp, 'APPEND');
	}

	close($socket_server);
}

#*****************************************************************************************************
# Subroutine			: cdpcleaup
# Objective				: This subroutine will cleanup and handle interruptions
# Added By				: Sabin Cheruvattil
#*****************************************************************************************************
sub cdpcleaup {
	my $cdpserverlock = Common::getCDPLockFile('server');
	unlink($cdpserverlock) if(-f $cdpserverlock);
	exit(0);
}