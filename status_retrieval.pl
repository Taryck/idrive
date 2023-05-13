#!/usr/bin/env perl
#-------------------------------------------------------------------------------
# Created By : Senthil Pandian @ IDrive Inc
#-------------------------------------------------------------------------------
system('clear');
use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;
use File::Path;
use File::Basename;
use Time::Local;

my ($pathSeparator, $lineFeed, $jobType) = ('/', "\n", '');
my $keyPressEvent;
 
Common::waitForUpdate();
Common::initiateMigrate();

#Subroutine that processes SIGINT and SIGTERM signal received by the script#
$SIG{INT}  = \&processTerm;
$SIG{TERM} = \&processTerm;
$SIG{TSTP} = \&processTerm;
$SIG{QUIT} = \&processTerm;
$SIG{PWR}  = \&processTerm if(exists $SIG{'PWR'});
$SIG{KILL} = \&processTerm;
$SIG{USR1} = \&processTerm;

init();

#****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry & end point for the script
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub init {
	my @parsedVersionData = '';

	system('clear');
	Common::loadAppPath();
	Common::loadServicePath() or Common::retreat('invalid_service_directory');
	Common::verifyVersionConfig();
	Common::loadUsername() or Common::retreat('login_&_try_again');

	my $errorKey = Common::loadUserConfiguration();
	Common::retreat($AppConfig::errorDetails{$errorKey}) if ($errorKey > 1);

	Common::isLoggedin() or Common::retreat('login_&_try_again');
	Common::displayHeader();
	Common::checkAccountStatus(1);

	my (@runningJobs, @runningJobTitle, @runningDir);
	my $userProfilePath = Common::getUserProfilePath();
	foreach my $job (keys %AppConfig::availableJobsSchema) {
		my $pidFile = Common::getCatfile($userProfilePath, $AppConfig::userProfilePaths{$job}, $AppConfig::pidFile);
		if (Common::isFileLocked($pidFile)) {
			my $jobRunningDir  = Common::getJobsPath($job);
			push @runningJobTitle, $AppConfig::jobTitle{$job};
			push @runningDir, $jobRunningDir;
		}
	}

	# Added By Sabin | Scan Progress | Start
	my @scanjobs = ($AppConfig::bkpscan, $AppConfig::rescan);
	my $scanprog = Common::getCDPLockFile('scanprog');
	my $scanfor  = '';

	foreach my $cjob (@scanjobs) {
		my $scanlock = Common::getCDPLockFile($cjob);
		if(Common::isFileLocked($scanlock) && -f $scanprog) {
			if(Common::isThisOnlineBackupScan() || $cjob eq $AppConfig::rescan) {
				$scanfor = $AppConfig::backup;
			} else {
				$scanfor = $AppConfig::localbackup;
			}

			push @runningJobTitle, $AppConfig::jobTitle{$cjob};
			push @runningDir, dirname($scanlock);
			last;
		}
	}
	# Added By Sabin | Scan Progress | End

	Common::retreat(Common::getStringConstant('unable_to_find_any_active_job')) 	unless (scalar(@runningJobTitle) > 0);
	my $userSelection = 1;
	if(scalar(@runningJobTitle)>1) {
        Common::display('select_the_job_to_view_progress');
		Common::displayMenu(undef, @runningJobTitle);
		Common::display('');
		$userSelection = Common::getUserMenuChoice(scalar(@runningJobTitle));
	}

	my $selectedJob = (split("_", $runningJobTitle[($userSelection - 1)]))[0];
	$jobType        = uc($selectedJob);
	$AppConfig::jobType = $jobType;

	my $jobRunningDir = $runningDir[($userSelection - 1)];
	$AppConfig::jobRunningDir = $jobRunningDir;

	# Added to handle the job termination case: Senthil
	if($jobType =~ /$AppConfig::scan/i) {
		my $currPidFile = Common::getCDPLockFile(lc($jobType));
		Common::retreat('no_scan_job_in_progress') unless(-f $currPidFile);
	} else {
		my $pidFile = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
		Common::retreat(Common::getStringConstant('no_job_is_running_for_progress') . $lineFeed) if(!-f $pidFile);
	}

	if($jobType =~ /$AppConfig::archive/i) {
		archiveProgress($jobType);
	} elsif($jobType =~ /$AppConfig::restore/i) {
		restoreProgress($jobType);
	} elsif($jobType =~ /$AppConfig::scan/i) {
		scanProgress($jobType);
	} else {
		backupProgress($jobType, $scanfor);
	}

	Common::sleepForMilliSec(100);
	processTerm();
}

#*****************************************************************************************************
# Subroutine/Function : scanProgress
# In Param  		  : 
# Out Param 		  : 
# Objective	          : This subroutine to display progress of CDP scan
# Added By	          : Senthil Pandian
# Modified By         : Sabin Cheruvattil
#****************************************************************************************************/
sub scanProgress {
	my $jobType = $_[0];
	my $currPidFile 	        = Common::getCDPLockFile(lc($jobType));
	my $progressDetailsFilePath = Common::getCDPLockFile('scanprog');
    
    my $noOfRowsReq = ($jobType =~ /$AppConfig::scan/i)? 15 : 40;
	Common::getCursorPos($noOfRowsReq, Common::getStringConstant('preparing_file_list').$lineFeed);

	while(-f $currPidFile) {
		Common::displayScanProgress($progressDetailsFilePath, 4, $_[1]);
		Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);
	}

	Common::displayScanProgress($progressDetailsFilePath, 4, $_[1]);
    $AppConfig::prevProgressStrLen = 10000; #Resetting to clear screen
}

#*****************************************************************************************************
# Subroutine/Function : backupProgress
# In Param  		  : 
# Out Param 		  : 
# Objective	          : This subroutine to display progress of Backup/Local Backup
# Added By	          : Senthil Pandian
# Modified By         : 
#****************************************************************************************************/
sub backupProgress {
	my $jobType = $_[0];
	my $scanfor = $_[1];
	my $pidFile = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
	my $playPause   = $AppConfig::running;
	$playPause = undef if($jobType =~ /$AppConfig::cdp/i);

	my ($redrawForLess, $drawForPlayPause) = (0) x 2;
	my $temp   = $AppConfig::totalEngineBackup;
	my $bwPath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::bwFile);
	my $moreOrLess = $AppConfig::less;
    $moreOrLess    = $AppConfig::more if(Common::checkScreeSize());

	if($scanfor) {
		scanProgress($scanfor, lc($jobType));
	} else {
		Common::getCursorPos(40,Common::getStringConstant('preparing_file_list').$lineFeed);
	}

	my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::progressDetailsFilePath);
	$keyPressEvent = Common::catchPressedKey();
	while(-f $pidFile){
		($redrawForLess, $drawForPlayPause) = (0) x 2;
		# Checking & changing status if play/pause key pressed in status retrieval script
		if(-f $bwPath and $jobType =~ /$AppConfig::backup/i) {
			my $bw = Common::getFileContents($bwPath);
			if($bw ne '') {
				if(($bw < 0) and ($playPause eq $AppConfig::running)) {
					$drawForPlayPause = 1;
					$playPause = $AppConfig::paused;
				} elsif(($bw >= 0) and ($playPause eq $AppConfig::paused)) {
					$drawForPlayPause = 1;
					$playPause = $AppConfig::running;
				}
			}
		}

		if($keyPressEvent->(1)) {			
			if($jobType =~ /$AppConfig::backup/i){
				if(($AppConfig::pressedKeyValue eq 'p') and ($playPause eq $AppConfig::running)) {
					$drawForPlayPause = 1;
					$playPause = $AppConfig::paused;
					Common::pauseOrResumeEVSOp($AppConfig::jobRunningDir,'p');
				} elsif(($AppConfig::pressedKeyValue eq 'r') and ($playPause eq $AppConfig::paused)) {
					$drawForPlayPause = 1;
					$playPause = $AppConfig::running;
					Common::pauseOrResumeEVSOp($AppConfig::jobRunningDir,'r');
				}
			}

			if(($moreOrLess eq $AppConfig::more) and ($AppConfig::pressedKeyValue eq '-')) {
				$moreOrLess = $AppConfig::less;
				$redrawForLess = 1;
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
			} elsif(($moreOrLess eq $AppConfig::less) and ($AppConfig::pressedKeyValue eq '+')) {
				$moreOrLess = $AppConfig::more if(Common::checkScreeSize());
                $AppConfig::prevProgressStrLen = 10000;
                # Common::clearScreenAndResetCurPos();
			}
		}
		Common::displayProgressBar($progressDetailsFilePath,undef,$playPause,$moreOrLess,$redrawForLess)  if(!defined($playPause) || $playPause ne $AppConfig::paused)|| $drawForPlayPause;
		Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);
	}
	$keyPressEvent->(0);
	$AppConfig::pressedKeyValue = '';
	Common::displayProgressBar($progressDetailsFilePath,undef,$playPause,$moreOrLess,$redrawForLess);
	Common::removeItems("$progressDetailsFilePath*");
}

#*****************************************************************************************************
# Subroutine/Function : restoreProgress
# In Param  		  : 
# Out Param 		  : 
# Objective	          : This subroutine to display progress of Restore/Local Restore
# Added By	          : Senthil Pandian
# Modified By         : 
#****************************************************************************************************/
sub restoreProgress {
    my $pidFile = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
	my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::progressDetailsFilePath);
	my $redrawForLess = 0;
	my $moreOrLess = $AppConfig::less;
    $moreOrLess    = $AppConfig::more if(Common::checkScreeSize());

    Common::getCursorPos(15,Common::getStringConstant('preparing_file_list').$lineFeed) if(-e $pidFile);
	$keyPressEvent = Common::catchPressedKey();
    while(-f $pidFile) {
		$redrawForLess = 0;
		if($keyPressEvent->(1)) {
			if(($moreOrLess eq $AppConfig::more) and ($AppConfig::pressedKeyValue eq '-')) {
				$moreOrLess = $AppConfig::less;
				$redrawForLess = 1;
                $AppConfig::prevProgressStrLen = 10000;
			} elsif(($moreOrLess eq $AppConfig::less) and ($AppConfig::pressedKeyValue eq '+')) {
				$moreOrLess = $AppConfig::more if(Common::checkScreeSize());
                $AppConfig::prevProgressStrLen = 10000;
			}
		}
		Common::displayProgressBar($progressDetailsFilePath, undef, undef, $moreOrLess, $redrawForLess);
		Common::sleepForMilliSec($AppConfig::sleepTimeForProgress);
	}
	$keyPressEvent->(0);
	$AppConfig::pressedKeyValue = '';

    Common::displayProgressBar($progressDetailsFilePath, undef, undef, $moreOrLess, $redrawForLess);
    Common::removeItems("$progressDetailsFilePath*");
}

#*****************************************************************************************************
# Subroutine/Function : archiveProgress
# In Param  		  : 
# Out Param 		  : 
# Objective	          : This subroutine to display progress of archive cleanup
# Added By	          : Senthil Pandian
# Modified By         : 
#****************************************************************************************************/
sub archiveProgress {
	my $jobType = $_[0];
    my $pidFile = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);
	my $progressDetailsFilePath = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::progressDetailsFilePath);

	Common::getCursorPos(10,"");
    Common::display(['archive_cleanup',"\n==============="]);
	#Archive cleanup progress bar
	if(-f $AppConfig::jobRunningDir.$AppConfig::archiveStageDetailsFile)
	{
		my $status = Common::getFileContents($AppConfig::jobRunningDir.$AppConfig::archiveStageDetailsFile);
		Common::Chomp(\$status);
		Common::display($status) if($status);
	}

	Common::getCursorPos(10,"",0);
	my ($prevOp,$currOp) = ('scanning_files')x2;
	while(-f $pidFile)
	{
		if(-f $progressDetailsFilePath)
		{
			my $progStr = Common::getFileContents($progressDetailsFilePath);
			my @progArr = split($lineFeed,$progStr);
			$currOp = $progArr[0] if(defined($progArr[0]));
			if($prevOp ne $currOp){
				Common::display(" ");
				Common::getCursorPos(10,"",0);
				$prevOp = $currOp;
			}
			Common::displayArchiveProgressBar($progressDetailsFilePath);
		}
		Common::sleepForMilliSec(100); 
	}
	Common::displayArchiveProgressBar($progressDetailsFilePath);
	Common::removeItems($progressDetailsFilePath);
}

#*****************************************************************************************************
# Subroutine/Function : processTerm
# In Param  		  : 
# Out Param 		  : 
# Objective	          : The signal handler invoked when signal is received by the script
# Added By	          : Senthil Pandian
# Modified By         : Sabin Cheruvattil
#****************************************************************************************************/
sub processTerm {
	my $jobType = lc($jobType);
	$keyPressEvent->(0) if(defined($keyPressEvent));
    system("stty $AppConfig::stty") if($AppConfig::stty);	# restore 'cooked' mode

    if($jobType and $jobType !~ /$AppConfig::scan/i) {
        my $count = 0;
        my $finalSummaryFile = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::fileSummaryFile);
        my $pidFile = Common::getCatfile($AppConfig::jobRunningDir, $AppConfig::pidFile);

        while(!-f $pidFile) {
           last if((-f $finalSummaryFile and !-z _) or ($count > 30));
            Common::sleepForMilliSec(1000);
            $count++;
            next;
        }

        my $jobTitle = Common::getStringConstant($AppConfig::jobTitle{$jobType});
        Common::displayFinalSummary($jobTitle, $finalSummaryFile);
    }
	exit 0;
}

1;
