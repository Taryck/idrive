#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to run the independent functionalities
#
# Created By: Anil Kumar @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

my $incPos = rindex(__FILE__, '/');
my $incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

use Helpers;
use constant NO_EXIT => 1;
init();


#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Anil Kumar
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub init {
	Helpers::loadAppPath();
	Helpers::loadServicePath();
	if(Helpers::loadUsername()){
		Helpers::loadUserConfiguration();
	}
	performOperation($ARGV[0]);
}

#*****************************************************************************************************
# Subroutine			: performOperation
# Objective				: This method is used to differentiate the functionality based on the operation  required to done.
# Added By				: Anil Kumar
# Modified By 			: Sabin Cheruvattil, Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub performOperation {
	my $operation = '';
	$operation = $_[0] if($_[0]);
	if ($operation eq "GETQUOTA") {
		getAndUpdateQuota();
	} elsif($operation eq 'UPLOADLOG') {
		Helpers::uploadLog($ARGV[1]);
	} elsif($operation eq 'UPLOADMIGRATEDLOG') {
		Helpers::uploadMigratedLog();
	} elsif($operation eq 'INSTALLCRON') {
		installCRON();
	} elsif($operation eq 'RESTARTIDRIVESERVICES') {
		restartIdriveServices();
	} elsif($operation eq 'RELINKCRON') {
		relinkCRON();
	} elsif($operation eq 'UNINSTALLCRON') {
		uninstallCRON();
	} elsif($operation eq 'MIGRATEUSERDATA') {
		migrateUserData();
	} elsif($operation eq 'PREUPDATE') {
		$Configuration::callerEnv = 'BACKGROUND' if (defined $ARGV[2] and $ARGV[2] eq 'silent');
		#print "Version:".$ARGV[1]."\n\n" if (defined $ARGV[1]);
		#doLogout();
	} elsif($operation eq 'POSTUPDATE') {
		postUpdateOperation();
	} elsif ($operation eq 'DECRYPT') {
		decryptEncrypt('decrypt');
	} elsif ($operation eq 'ENCRYPT') {
		decryptEncrypt('encrypt');
	} elsif ($operation eq 'LOGIN') {
		my $uname	= $ARGV[1];
		my $upasswd = $ARGV[2];
		$Configuration::callerEnv = 'BACKGROUND';
		my @responseData = Helpers::authenticateUser($uname, $upasswd);
		print JSON::to_json(\@responseData);
	} elsif($operation eq 'SERVERREQUEST') {
		$Configuration::callerEnv = 'BACKGROUND';
		my $result = {STATUS => Configuration::FAILURE, DATA => ''};
		if(-e $ARGV[1] and !-z $ARGV[1]){
			$result = Helpers::request(\%{JSON::from_json(Helpers::getFileContents($ARGV[1]))});
		}
		print JSON::to_json(\%{$result});
	} else {
		Helpers::traceLog("Unknown operation: $operation");
		# Helpers::display(['Unknown operation: ', $operation]);
	}
}

#*****************************************************************************************************
# Subroutine			: installCRON
# Objective				: This subroutine will install and launch the cron job
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub installCRON {
	Helpers::setServicePath(".") if(!Helpers::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if($Configuration::mcUser ne 'root');

	# remove current cron link
	unlink($Configuration::cronLinkPath);
	# create cron link file
	Helpers::createCRONLink();

	my $cronstat = Helpers::launchIDriveCRON();
	unless(-f Helpers::getCrontabFile()) {
		Helpers::fileWrite(Helpers::getCrontabFile(), '');
		chmod($Configuration::filePermission, Helpers::getCrontabFile());
	}

	# wait for the cron to start | handle lock delay
	sleep(5);
	return 1;
}

#*****************************************************************************************************
# Subroutine			: relinkCRON
# Objective				: This subroutine will relink the cron job
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub relinkCRON {
	Helpers::setServicePath(".") if(!Helpers::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if($Configuration::mcUser ne 'root');

	# remove current cron link
	unlink($Configuration::cronLinkPath);
	# create cron link file
	Helpers::createCRONLink();

	unless(-e Helpers::getCrontabFile()) {
		Helpers::fileWrite(Helpers::getCrontabFile(), '');
		chmod($Configuration::filePermission, Helpers::getCrontabFile());
	}
}

#*****************************************************************************************************
# Subroutine			: restartIdriveServices
# Objective				: Restart all IDrive installed services
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub restartIdriveServices {
	my $filename = Helpers::getUserFile();
	my $fc = '';
	$fc = Helpers::getFileContents($filename) if (-f $filename);
	Helpers::Chomp(\$fc);

	my $mcUsers;
	if (eval { JSON::from_json($fc); 1 } and ($fc ne '')) {
		$mcUsers = JSON::from_json($fc);
		foreach(keys %{$mcUsers}) {
			Helpers::stopDashboardService($_, Helpers::getAppPath());
		}
	}

	if (Helpers::checkCRONServiceStatus() == Helpers::CRON_RUNNING) {
		my @lockinfo = Helpers::getCRONLockInfo();
		$lockinfo[2] = 'restart';
		Helpers::fileWrite($Configuration::cronlockFile, join('--', @lockinfo));
		return relinkCRON();
	}

	return installCRON();
}

#*****************************************************************************************************
# Subroutine			: uninstallCRON
# Objective				: This subroutine will uninstall the cron job
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub uninstallCRON {
	Helpers::setServicePath(".") if(!Helpers::loadServicePath());

	# make sure self is running with root permission, else exit;
	exit(0) if($Configuration::mcUser ne 'root');

	Helpers::removeIDriveCRON();
}

#*****************************************************************************************************
# Subroutine			: getAndUpdateQuota
# Objective				: This method is used to get the quota value and update in the file.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub getAndUpdateQuota {
	my $csf = Helpers::getCachedStorageFile();
	unlink($csf);
	Helpers::createUTF8File('GETQUOTA') or Helpers::retreat('failed_to_create_utf8_file');
	my @result = Helpers::runEVS('tree');

	if (exists $result[0]->{'message'}) {
		if ($result[0]->{'message'} eq 'ERROR') {
			Helpers::display('unable_to_retrieve_the_quota');
			return 0;
		}
	}
	if (Helpers::saveUserQuota(@result)) {
		return 1 if(Helpers::loadStorageSize());
	}
	Helpers::traceLog('unable_to_cache_the_quota');
	Helpers::display('unable_to_cache_the_quota') ;
	return 0;
}

#*****************************************************************************************************
# Subroutine			: migrateUserData
# Objective				: This method is used to migrate user data.
# Added By				: Vijay Vinodh
#****************************************************************************************************/
sub migrateUserData {

	exit(0) if($Configuration::mcUser ne 'root');
	my $migrateLockFile = Helpers::getMigrateLockFile();

	Helpers::display(["\n", 'migration_process_starting', '. ']);
	Helpers::migrateUserFile();
	Helpers::display(['migration_process_completed', '. ']);
	Helpers::display(["\n", 'starting_cron_service', '...']);

	if(installCRON()) {
		Helpers::display(['started_cron_service', '. ',"\n"]);
	} else {
		Helpers::display(['cron_service_not_running', '. ',"\n"]);
	}

	my @linesCrontab = ();
	my $getOldUserFile = Helpers::getOldUserFile();
	if(-e Helpers::getUserFile()) {
		@linesCrontab = Helpers::readCrontab();
		my @updatedLinesCrontab = Helpers::removeEntryInCrontabLines(@linesCrontab);
		Helpers::writeCrontab(@updatedLinesCrontab);
		unlink $getOldUserFile;
	}
	return 0;
}

#*****************************************************************************************************
# Subroutine			: doLogout
# Objective				: Logout current user's a/c
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub doLogout {
	my $cachedIdriveFile = Helpers::getCatfile(Helpers::getServicePath(), $Configuration::cachedIdriveFile);
	return 0 unless(-f $cachedIdriveFile);
	my $usrtxt = Helpers::getFileContents($cachedIdriveFile);
	if ($usrtxt =~ m/^\{/) {
		$usrtxt = JSON::from_json($usrtxt);
		$usrtxt->{$Configuration::mcUser}{'isLoggedin'} = 0;
		Helpers::fileWrite(Helpers::getCatfile(Helpers::getServicePath(), $Configuration::cachedIdriveFile), JSON::to_json($usrtxt));
		Helpers::display(["\"", Helpers::getUsername(), "\"", ' ', 'is_logged_out_successfully']);
	}
	return 1;
}

#*****************************************************************************************************
# Subroutine			: decryptEncrypt
# Objective				: Decrypt/Encrypt the file content & write into another file
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub decryptEncrypt {
	my $task 		 	= $_[0];
	my $sourceFile 	 	= $ARGV[1];
	my $destinationFile = $ARGV[2];
	if(!$sourceFile or !-e $sourceFile or -z $sourceFile) {
		Helpers::retreat(['Invalid source path',"\n"]);
	}
	unless($destinationFile) {
		Helpers::retreat(['Invalid destination path',"\n"]);
	}
	if($task eq 'decrypt') {
		my $string = Helpers::decryptString(Helpers::getFileContents($sourceFile));
		Helpers::fileWrite($destinationFile,$string);
	} else {
		my $string = Helpers::encryptString(Helpers::getFileContents($sourceFile));
		Helpers::fileWrite($destinationFile,$string);
	}
}

#*************************************************************************************************
# Subroutine		: postUpdateOperation
# Objective			: Check & update EVS/Perl binaries if any latest binary available and logout
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub postUpdateOperation {
	my $silent = 0;
	if (defined $ARGV[2] and $ARGV[2] eq 'silent') {
		$Configuration::callerEnv = 'BACKGROUND';
		$silent = 1;
	}

	if(Helpers::isLoggedin()){
		my $cmd = ("$Configuration::perlBin " . Helpers::getScript('logout', 1));
		$cmd   .= (" $silent 1 'NOUSERINPUT' 2>/dev/null");		
		my $res = `$cmd`;
		print $res;
	}
	
	updateEVSBinary() if(fetchInstalledEVSBinaryVersion());
	updatePerlBinary() if(fetchInstalledPerlBinaryVersion());
}

#*************************************************************************************************
# Subroutine		: fetchInstalledEVSBinaryVersion
# Objective			: Get the installed EVS binaries version
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub fetchInstalledEVSBinaryVersion {
	#print "hasEVSBinary:".Helpers::hasEVSBinary()."#\n";
	my $needToDownload = 1;
	if((Helpers::hasEVSBinary())) {
		my @evsBinaries = (
			$Configuration::evsBinaryName,
			$Configuration::evsDedupBinaryName
		);
		my $servicePath = Helpers::getServicePath();
		my %evs;
		#use Data::Dumper;
		for (@evsBinaries) {
			my $evs = $servicePath."/".$_;
			my $cmd = "$evs --client-version";
			my $nonDedupVersion = `$cmd 2>/dev/null`;
			#print "nonDedupVersion:$nonDedupVersion\n\n\n";
			$nonDedupVersion =~ m/idevsutil version(.*)release date(.*)/;

			$evs{$_}{'version'} = $1;
			$evs{$_}{'release_date'} = $2;
			$evs{$_}{'release_date'} =~ s/\(DEDUP\)//;
			
			Helpers::Chomp(\$evs{$_}{'version'});
			Helpers::Chomp(\$evs{$_}{'release_date'});
			
			if($evs{$_}{'version'} ne $Configuration::evsVersionSchema{$_}{'version'} or $evs{$_}{'release_date'} ne $Configuration::evsVersionSchema{$_}{'release_date'}) {
				$needToDownload = 1;
				last;
			}
			$needToDownload = 0;
		}
	}
	#print "needToDownload:$needToDownload\n\n";
	return $needToDownload;
}

#*************************************************************************************************
# Subroutine		: fetchInstalledPerlBinaryVersion
# Objective			: Get the installed Perl binary version
# Added By			: Senthil Pandian
#*************************************************************************************************/
sub fetchInstalledPerlBinaryVersion {
	my $l = eval {
		require Idrivelib;
		Idrivelib->import();
		1;
	};	
	my $needToDownload = 1;
	if (Helpers::hasStaticPerlBinary()) {
		my $servicePath = Helpers::getServicePath();
		my $sp = Helpers::getCatfile($servicePath, $Configuration::staticPerlBinaryName);
		if($l) {
			my $cmd = "$sp -MIdrivelib -e 'print $Idrivelib::VERSION'";
			my $version = `$cmd 2>/dev/null`;
			Helpers::Chomp(\$version);
			if($version eq $Configuration::staticPerlVersion) {
				$needToDownload = 0;
			}
		}
	}
	return $needToDownload;
}

#*************************************************************************************************
# Subroutine		: updatePerlBinary
# Objective			: download the latest perl binary and update 
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub updatePerlBinary {
	Helpers::display(["\n", 'downloading_updated_static_perl_binary', '...']);
	Helpers::downloadStaticPerlBinary() or Helpers::traceLog('unable_to_download_static_perl_binary');
	Helpers::display(['static_perl_binary_downloaded_sucessfully',"\n"]);
}

#*************************************************************************************************
# Subroutine		: updateEVSBinary
# Objective			: download the latest EVS binary and update 
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************************/
sub updateEVSBinary {
	Helpers::display(["\n", 'downloading_updated_evs_binary', '...']);
	Helpers::downloadEVSBinary() or Helpers::traceLog('unable_to_download_evs_binary');
	Helpers::display('evs_binary_downloaded_sucessfully');	
}
