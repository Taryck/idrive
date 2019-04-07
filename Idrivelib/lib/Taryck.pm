#*****************************************************************************************************
# Most commonly used subroutines are placed here for re-use
#****************************************************************************************************/

package Taryck;
use strict;
use warnings;
use Time::Local;
use Helpers;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(getClearUserConfigurationFile atLoadUserConfiguration decodeUserConfiguration atSaveUserConfiguration);

use Cwd 'abs_path';
use POSIX qw(strftime);
use File::Spec::Functions;
use File::Basename;
use File::stat;
use Scalar::Util qw(reftype looks_like_number);
use File::Path qw(rmtree);
use File::Copy;
use File::stat;
use POSIX;
use Fcntl qw(:flock SEEK_END);
use IO::Handle;

use utf8;
use MIME::Base64;

use Sys::Hostname;

use Configuration;
use JSON;

#*****************************************************************************************************
# Subroutine			: getLogsList
# Objective				: This subroutine gathers the list of log files
# Added By				: Sabin Cheruvattil
# Modified By			: Senthil Pandian
#****************************************************************************************************/
sub getLogsList {
	my %timestampStatus = ();
	my @tempLogFiles;
	my $currentLogFile ='';
	my $logDir = $_[0];

	if (-e $logDir) {
		@tempLogFiles = `ls '$logDir'`;
#		%timestampStatus = map {m/(\d+)_([A-Za-z\_]+)/} @tempLogFiles;
#		%timestampStatus = map {m/([0-9\-\_]+)_([A-Za-z\_]+)/} @tempLogFiles;
		foreach (@tempLogFiles) {
			chomp($_);
			my @split = map {m/([0-9\-\_]+)_([A-Za-z\_]+)/} $_;
			my ($yyyy, $mo, $dd, $hh, $mn, $ss) = ($split[0] =~ /(\d+)-(\d+)-(\d+)_(\d+)-(\d+)-(\d+)/);
			if ( defined $yyyy and defined $ss ) {
# $mon is the month offset, in the range 0..11 with 0 indicating January and 11 indicating December. 
				$split[0] = timelocal($ss, $mn, $hh, $dd, $mo-1, $yyyy);
#				$_ = $split[0] ."_" . $split[1];
			}
			$timestampStatus{$_}{'TS'} = $split[0];
			$timestampStatus{$_}{'Status'} = $split[1];
		}
# #		%timestampStatus = map {m/(\d+)_([A-Za-z\_]+)/} @tempLogFiles;
	}
	return %timestampStatus;
}
#*****************************************************************************************************
# Subroutine			: selectLogsBetween
# Objective				: select logs files between given two dates
# Added By				: Yogesh Kumar
# Modified By 			: Senthil Pandian
#****************************************************************************************************/
sub selectLogsBetween {
	my %logStat = ();
	my %logFilenames = ();

	unless (defined($_[1]) and defined($_[2])) {
		retreat('start_and_end_dates_are_required');
	}

	#Added for Dashboard
	if (!defined($_[0]) and defined($_[3])){
		my $jobDir = (fileparse($_[3]))[0];
		if ($jobDir =~ m/\/LOGS\//){
			$jobDir =~ s/LOGS\///;
		}
		getLogsList($jobDir);
	}

	if (defined($_[3])) {
		my @t1 = localtime($_[1]);
		$t1[5] += 1900;
		$t1[4] += 1;
		my @t2 = localtime($_[2]);
		$t2[5] += 1900;
		$t2[4] += 1;

		my $tempLogFile;
		my $logInStrings = '';
		my $mon;
		my $pmon;
		for(my $y=$t1[5]; $y <= $t2[5]; $y++) {
			$mon = ($y == $t2[5])? $t2[4] : 12;
			$pmon = ($t1[4] > $mon)? $mon : $t1[4];

			for(my $m=$pmon; $m <= $mon; $m++) {
				$tempLogFile = sprintf("$_[3]", $m, $y);
				if (-f $tempLogFile) {
					$logInStrings .= Helpers::getFileContents($tempLogFile);
				}
			}
		}

		if ($logInStrings ne '') {
			$logInStrings .= '}';
			substr($logInStrings, 0, 1, '{');
		}
		else {
			$logInStrings .= '{}';
		}
		%logFilenames = %logStat = %{JSON::from_json($logInStrings)};
	}

	if (defined($_[0]) and ref($_[0]) eq 'HASH') {
		%logFilenames = %{$_[0]};
	}

	my $lf = tie(my %logFiles, 'Tie::IxHash');
	my $logsFound = 0;
# Numeric sort removed
#	foreach(sort {$b <=> $a} keys %logFilenames) {
	foreach(sort keys %logFilenames) {
		if ((($_[1] <= $logFilenames{$_}{'TS'}) && ($_[2] >= $logFilenames{$_}{'TS'}))) {
			$logsFound = 1;
			if (exists $logStat{$_}) {
				$logFiles{$_} = $logStat{$_};
			}
			else {
				$logFiles{$_} = {
					'status' => $logFilenames{$_}{'Status'},
					'datetime' => strftime("%d/%m/%Y %H:%M:%S", localtime($logFilenames{$_}{'TS'}))
				};
			}
		}
		elsif ($logsFound) {
			last;
		}
	}

	return $lf;
}
sub extendBackupItem($) {
	my $item = shift;
	my $backupBase_Dir = Helpers::getUserConfiguration('TBE_BASE_DIR');
	if($backupBase_Dir ne "") {
		if(substr($item, 0, 1) eq "/") {
			$item =~ s/^.//;
		}
		$item = $backupBase_Dir . $item;
	}
	return $item;
}
#*****************************************************************************************************
# Subroutine			: encryptString
# Objective				: Encrypt the given data
# Override By			: TBE
#****************************************************************************************************/
sub encryptString {
# No encrypption
	return $_[0];
}

#*****************************************************************************************************
# Subroutine			: decryptString
# Objective				: Decrypt the given data
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub decryptString {
# TBE no encyption
	return $_[0] ;
}

#=====================================================================================================================
# TBE : ENH-003 TIMESTAMP fix to YYYY-MM-DD_HH-MM-SS
sub TS2ISO {
# Correct timestamp string : YYYY-MM-DD_HH-MM-SS
	return POSIX::strftime("%Y-%m-%d_%H-%M-%S", localtime($_[0])); ;
}
#=====================================================================================================================

sub TS2Text {
# Correct timestamp string : YYYY-MM-DD_HH-MM-SS
	return POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime($_[0])); ;
}

# Not used
############################################
sub getClearUserConfigurationFile {
	return Helpers::getUserConfigurationFile().'.json';
}
#*****************************************************************************************************
# Subroutine			: loadUserConfiguration
# Objective				: Assign user configurations to %userConfiguration
# Added By				: Yogesh Kumar
# Modified By			: Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************/
sub atLoadUserConfiguration {
	my $ucf = Helpers::getUserConfigurationFile();
# .json.load fichier consommé	
	my $tbe_ucf = getClearUserConfigurationFile().'.load';
	if (-f $ucf and !-z $ucf and -f $tbe_ucf and !-z $tbe_ucf) {
#		my $ucf_ts = (stat($ucf)->mtime);
		#my $tbe_ts = (stat($tbe_ucf)->mtime);
#		if ( $tbe_ts gt $ucf_ts ) {
			my $content = Helpers::getFileContents($tbe_ucf);
			if (open(my $fh, '>', $ucf)) {
				print $fh Helpers::encryptString($content);
				close($fh);
			}
#		}
		unlink($tbe_ucf);
	}
}

sub decodeUserConfiguration ($) {
	my $ucj = shift;
	my $errCode = 0;
	my $ucf = getClearUserConfigurationFile();
	$ucj = JSON->new->ascii->pretty->encode( JSON::decode_json $ucj );
	if (open(my $fh, '>', $ucf)) { 
		print $fh $ucj;
		close($fh);
		return 1;
	}

	return $errCode;
}

#*****************************************************************************************************
# Subroutine			: saveUserConfiguration
# Objective				: Save user selected configurations to a file
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub atSaveUserConfiguration {
#	loadUserConfiguration();
	my %userConfiguration = Helpers::getUserConfiguration();
	my $content = JSON::to_json(\%userConfiguration);
	return decodeUserConfiguration($content);
}

1;
