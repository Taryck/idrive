#*****************************************************************************************************
# Dashboard for linux
#
# Created By : Yogesh Kumar @ IDrive Inc
# Reviewed By: Deepak Chaurasia
#
# IMPORTANT  : Please do not run this script manually. Run dashboard using account_setting.pl
#*****************************************************************************************************

use strict;
use warnings;

$| = 1;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Idrivelib;
use Common qw(retreat getUserConfiguration setUserConfiguration saveUserConfiguration getUsername getParentUsername getServicePath getParentRemoteManageIP getRemoteManageIP getRemoteAccessToken getMachineUser getCatfile getUserProfilePath loadNotifications setNotification saveNotifications loadNS getNS saveNS deleteNS getFileContents);
use AppConfig;

$AppConfig::callerEnv = 'BACKGROUND';
$AppConfig::traceLogFile = 'dashboard.log';
$AppConfig::displayHeader = 0;

my $dhbv;

#$SIG{INT}  = \&end;
$SIG{TERM} = \&end;
#$SIG{TSTP} = \&end;
#$SIG{QUIT} = \&end;
$SIG{PWR}  = \&end;
$SIG{KILL} = \&end;
#$SIG{USR1} = \&end;

$0 = 'IDrive:dashboard:IN';

Common::loadAppPath();
exit(1) unless Common::loadServicePath();

my $selfPIDFile = getCatfile(getServicePath(), $AppConfig::userProfilePath, $AppConfig::mcUser);
exit(1) unless (-d $selfPIDFile);

$selfPIDFile = getCatfile($selfPIDFile, 'dashboard.pid');
exit(1) if Common::isFileLocked($selfPIDFile);
exit(1) unless Common::fileLock($selfPIDFile);

while (1) {
	unless (Common::loadServicePath() and Common::loadUsername()) {
		Common::traceLog('failed to load service path/username');
		sleep(3);
		next;
	}

	unless (Common::loadUserConfiguration() == 1) {
		Common::traceLog('failed to load userconfig');
		sleep(3);
		next;
	}

	if (getUserConfiguration('RMWS') and getUserConfiguration('RMWS') eq 'yes') {
		$dhbv = 2;
		eval {
			Idrivelib::init();
			1;
		} or do {
			sleep(5);
			next;
		};
		last;
	}
	else {
		$dhbv = 1;
		require DashboardClient;
		DashboardClient->import();
		eval {
			DashboardClient::init();
			1;
		} or do {
			sleep(5);
			next;
		};
		last;
	}
}

sub end {
	if ($dhbv == 2) {
		Idrivelib::end();
	}
	else {
		DashboardClient::end();
	}
}
