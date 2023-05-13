#*****************************************************************************************************
# Schema
#
# Created By : Yogesh Kumar @ IDrive Inc
#****************************************************************************************************/

package DashboardUtility;
use strict;
use warnings;

use JSON qw(from_json to_json);

our %propFields = (
	chk_update => '', fail_val  => '', ignore_accesserr => '',
	chk_asksave => '', chk_multiupld  => '', show_hidden => '',
	slide_throttle => '', notify_missing => '', missing_val => '',
	arch_cleanup_checked => '', freq_days => '', freq_percent => '',
	DefaultBackupSet  => '', LocalBackupSet => '', lst_fullexclude => '',
	lst_partexclude => '', lst_regexexclude => '', nxttrftime  => '',
	freq => '', cutoff => '', email  => '',
	mailnoti => '', txt_mpc => '', chk_cdp => '',
	cmb_cdp => '', verify_bkset => '',
);

my %prop = (
#	'nxttrftime' => sub {
#		my @time = split(':', $_[0]->{'value'});
#		my %d =  (
#			'h' => sprintf("%02d",$time[0]),
#			'm' => sprintf("%02d",$time[1])
#		);
#		if ($_[1] ne 'enabled' or $_[2] eq 'immediate') {
#			$d{'dom'} = '*';
#			$d{'mon'} = '*';
#			$d{'dow'} = '*';
#			$d{'settings'}{'status'} = 'enabled';
#			$d{'settings'}{'frequency'} = 'daily';
#		}
#
#		return \%d;
#	},
#	'freq' => sub {
#		my @v;
#		my $f = 'weekly';
#		my $s = 'enabled';
#		if (lc($_[0]->{'value'}) eq 'hourly') {
#			@v = ('*');
#			$f = 'hourly';
#		}
#		elsif ($_[0]->{'value'} eq '') {
#			$s = 'disabled';
#		}
#		else {
#			my @d = ('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat');
#			@v = split('', $_[0]->{'value'});
#			if (scalar @v == 7) {
#				$f = 'daily';
#			}
#			foreach (0 .. $#v) {
#				$v[$_] = $d[$v[$_] - 1];
#			}
#		}
#		my %d = (
#			'settings' => {
#				'frequency' => $f,
#				'status' => $s
#			}
#		);
#		$d{'dow'} = join(',', @v) if ($s ne 'disabled');
#		if ($f eq 'hourly') {
#			$d{'h'} = '*';
#			$d{'m'} = '0';
#		}
#
#		return \%d;
#	},
#	'cutoff' => sub {
#		my %d = ();
#		if ($_[0]->{'value'} eq '') {
#			%d = (
#				'settings' => {
#					'status' => 'disabled'
#				}
#			);
#		}
#		else {
#			my @time = split(':', $_[0]->{'value'});
#			%d = (
#				'h' => sprintf("%02d",$time[0]),
#				'm' => sprintf("%02d",$time[1]),
#				'settings' => {
#					'status' => 'enabled'
#				}
#			);
#		}
#		return \%d;
#	},
#	'email' => sub {
#		my $s = 'disabled';
#		my $e = '';
#		$s = 'enabled' if ($_[0]->{'value'} ne '');
#		$e = $_[0]->{'value'} if ($_[0]->{'value'} ne '');
#
#		return {
#			'settings' => {
#				'emails' => {
#					'ids' => $e,
#					'status' => $s
#				}
#			}
#		};
#	},
#	'mailnoti' => sub {
#		my $s = 'disabled';
#		if ($_[0]->{'value'} ne '') {
#			$s = 'notify_failure' if (int($_[0]->{'value'}) == 2);
#			$s = 'notify_always' if (int($_[0]->{'value'}) == 3);
#		}
#		return {
#			'settings' => {
#				'emails' => {
#					'status' => $s
#				}
#			}
#		};
#	},
#
#	'bkpset_linux' => sub {
#		my $bsf = Common::getJobsPath($_[0], 'file');
#		my %backupSet;
#		my $userHomeDirCmd = Common::updateLocaleCmd('echo ~');
#		my $userHomeDir = `$userHomeDirCmd`;
#		chomp($userHomeDir);
#
#		foreach my $fn (keys %{$_[1]}) {
#			if (substr($fn, 0, 2) eq '~/') {
#				$_[1]->{("$userHomeDir/" . substr($fn, 2))} = $_[1]->{$fn};
#				delete $_[1]->{$fn};
#			}
#		}
#
#		if (-e "$bsf.json" and !-z "$bsf.json") {
#			my %backupSetInfo = %{JSON::from_json(Common::getFileContents("$bsf.json"))};
#			foreach my $filename (keys %backupSetInfo) {
#				next if (exists $_[2]->{$filename} and not exists $_[1]->{$filename});
#				unless (exists $_[1]->{$filename} and ($_[1]->{$filename}{'type'} eq $backupSetInfo{$filename}{'type'}) and $_[1]->{$filename}{'disabled'}) {
#					$backupSet{$filename}{'type'} = $backupSetInfo{$filename}{'type'};
#				}
#
#				delete $_[1]->{$filename} if (exists $_[1]->{$filename});
#			}
#		}
#
#		foreach (keys %{$_[1]}) {
#			$backupSet{$_}{'type'} = $_[1]->{$_}{'type'} unless ($_[1]->{$_}{'disabled'});
#		}
#
#		my @newItemArray = keys %backupSet;
#		@newItemArray = Common::verifyEditedFileContent(\@newItemArray);
#		if(scalar(@newItemArray) > 0) {
#			%backupSet = Common::getLocalDataWithType(\@newItemArray, 'backup');
#			%backupSet = Common::skipChildIfParentDirExists(\%backupSet);
#		} else {
#			%backupSet= ();
#		}
#		return \%backupSet;
#	},
);

my %extractFields = (
	nxttrftime => sub {
		my $d = eval { from_json($_[0]->{'nxttrftime'}) };
		if ($@) {
			$d = $_[0]->{'nxttrftime'};
		}
		else {
			$d = $d->{'value'};
		}

		my @time = split(' ', $d);
		@time = split(':', $time[((scalar @time) - 1)]);
		$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'h'} = sprintf("%02d", $time[0]);
		$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'m'} = sprintf("%02d", $time[1]);

		my $status    = Common::getCrontab($_[3], $_[4], '{settings}{status}');
		my $frequency = Common::getCrontab($_[3], $_[4], '{settings}{frequency}');

		if ($status ne 'enabled' or $frequency eq 'immediate') {
			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'dom'} = '*';
			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'mon'} = '*';
			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'dow'} = '*';

			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'settings'}{'status'} = 'enabled';
			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'settings'}{'frequency'} = 'daily';
		}

		return 1;
	},

	freq => sub {
		my $d = eval { from_json($_[0]->{'freq'}) };
		if ($@) {
			$d = $_[0]->{'freq'};
		}
		else {
			$d = $d->{'value'};
		}

		my @v;
		my $f = 'weekly';
		my $s = 'enabled';

		if (lc($d) eq 'hourly') {
			@v = ('*');
			$f = 'hourly';
		}
		elsif (lc($d) eq 'immediate') {
			$f = 'immediate';
		}
		elsif ($d eq '') {
			$s = 'disabled';
		}
		else {
			my @d = ('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat');
			@v = split('', $d);
			if (scalar @v == 7) {
				$f = 'daily';
			}
			foreach (0 .. $#v) {
				$v[$_] = $d[$v[$_] - 1];
			}
		}

		$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'settings'}{'frequency'} = $f;
		$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'settings'}{'status'} = $s;
		$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'dow'} = join(',', @v) if ($s ne 'disabled');

		if ($f eq 'hourly') {
			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'h'} = '*';
			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'m'} = '0';
		}
		elsif ($f eq 'immediate') {
			($_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'m'},
				$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'h'}) = (localtime)[1,2];

			$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'m'}++;
		}

		return 1;
	},

	cutoff => sub {
		my $d = eval { from_json($_[0]->{'cutoff'}) };
		if ($@) {
			$d = $_[0]->{'cutoff'};
		}
		else {
			$d = $d->{'value'};
		}

		if ($d eq '') {
			$_[1]->{'content'}{'crontab'}{$_[2]}{'cancel'}{$_[4]}{'settings'}{'status'} = 'disabled';
		}
		else {
			my @time = split(':', $d);
			$_[1]->{'content'}{'crontab'}{$_[2]}{'cancel'}{$_[4]}{'h'} = sprintf("%02d",$time[0]);
			$_[1]->{'content'}{'crontab'}{$_[2]}{'cancel'}{$_[4]}{'m'} = sprintf("%02d",$time[1]);
			$_[1]->{'content'}{'crontab'}{$_[2]}{'cancel'}{$_[4]}{'settings'}{'status'} = 'enabled';
		}

		return 1;
	},

	email => sub {
		my $d = eval { from_json($_[0]->{'email'}) };
		if ($@) {
			$d = $_[0]->{'email'};
		}
		else {
			$d = $d->{'value'};
		}

		my $s = 'disabled';
		my $e = '';
		$s = 'enabled' if ($d ne '');
		$e = $d if ($d ne '');

		$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'settings'}{'emails'} = {
			ids => $e,
			status => $s
		};

		return 1;
	},

	mailnoti => sub {
		my $d = eval { from_json($_[0]->{'mailnoti'}) };
		if ($@) {
			$d = $_[0]->{'mailnoti'};
		}
		else {
			$d = $d->{'value'};
		}

		my $s = 'disabled';
		if ($d ne '') {
			$s = 'notify_failure' if (int($d) == 2);
			$s = 'notify_always' if (int($d) == 3);
		}
		$_[1]->{'content'}{'crontab'}{$_[2]}{$_[3]}{$_[4]}{'settings'}{'emails'}{'status'} = $s;

		return 1;
	},

	txt_mpc => sub {
		return 0 if ($_[0]->{'txt_mpc'} eq '');

		my $d = eval { from_json($_[0]->{'txt_mpc'}) };
		if ($@) {
			$d = $_[0]->{'txt_mpc'};
		}
		else {
			$d = $d->{'value'};
		}

		$_[1]->{'content'}{'user_settings'}{'BACKUPLOCATION'} = (Common::getBackupDeviceID() . '#' . $d);
	},

	lst_fullexclude => sub {
		my $d = eval { from_json($_[0]->{'lst_fullexclude'}) };
		if ($@) {
			$d = $_[0]->{'lst_fullexclude'};
		}
		else {
			$d = $d->{'value'};
		}
		$_[1]->{'content'}{'settings'}{'fullExclude'} = parseExcludeFiles($d, $AppConfig::fullExcludeListFile);
	},

	lst_partexclude => sub {
		my $d = eval { from_json($_[0]->{'lst_partexclude'}) };
		if ($@) {
			$d = $_[0]->{'lst_partexclude'};
		}
		else {
			$d = $d->{'value'};
		}
		$_[1]->{'content'}{'settings'}{'partialExclude'} = parseExcludeFiles($d, $AppConfig::partialExcludeListFile);
	},

	lst_regexexclude => sub {
		my $d = eval { from_json($_[0]->{'lst_regexexclude'}) };
		if ($@) {
			$d = $_[0]->{'lst_regexexclude'};
		}
		else {
			$d = $d->{'value'};
		}
		$_[1]->{'content'}{'settings'}{'regexExclude'} = parseExcludeFiles($d, $AppConfig::regexExcludeListFile);
	},

	chk_update => sub {
		my $d = eval { from_json($_[0]->{'chk_update'}) };
		if ($@) {
			$d = int($_[0]->{'chk_update'});
		}
		else {
			$d = int($d->{'value'});
		}

		$_[1]->{'content'}{'user_settings'}{'NOTIFYSOFTWAREUPDATE'} = $d;
	},

	fail_val => sub {
		my $d = eval { from_json($_[0]->{'fail_val'}) };
		if ($@) {
			$d = int($_[0]->{'fail_val'});
		}
		else {
			$d = int($d->{'value'});
		}

		$_[1]->{'content'}{'user_settings'}{'NFB'} = $d;
	},

	ignore_accesserr => sub {
		my $d = eval { from_json($_[0]->{'ignore_accesserr'}) };
		if ($@) {
			$d = int($_[0]->{'ignore_accesserr'});
		}
		else {
			$d = int($d->{'value'});
		}

		$_[1]->{'content'}{'user_settings'}{'IFPE'} = $d;
	},

	chk_asksave => sub {
		my $d = eval { from_json($_[0]->{'chk_asksave'}) };
		if ($@) {
			$d = int($_[0]->{'chk_asksave'});
		}
		else {
			$d = int($d->{'value'});
		}

		$_[1]->{'content'}{'user_settings'}{'RESTORELOCATIONPROMPT'} = $d;
	},

	chk_multiupld => sub {
		my $d = eval { from_json($_[0]->{'chk_multiupld'}) };
		if ($@) {
			$d = int($_[0]->{'chk_multiupld'});
		}
		else {
			$d = int($d->{'value'});
		}

		$_[1]->{'content'}{'user_settings'}{'ENGINECOUNT'} = ($d ? $AppConfig::maxEngineCount : $AppConfig::minEngineCount);
	},

	show_hidden => sub {
		my $d = eval { from_json($_[0]->{'show_hidden'}) };
		if ($@) {
			$d = int($_[0]->{'show_hidden'});
		}
		else {
			$d = int($d->{'value'});
		}

		$_[1]->{'content'}{'user_settings'}{'SHOWHIDDEN'} = $d;
	},

	slide_throttle => sub {
		my $d = eval { from_json($_[0]->{'slide_throttle'}) };
		if ($@) {
			$d = int($_[0]->{'slide_throttle'});
		}
		else {
			$d = int($d->{'value'});
		}

		$_[1]->{'content'}{'user_settings'}{'BWTHROTTLE'} = $d;
	},

	notify_missing => sub {
		my $d = eval { from_json($_[0]->{'notify_missing'}) };
		if ($@) {
			$d = int($_[0]->{'notify_missing'});
		}
		else {
			$d = int($d->{'value'});
		}

		my $d1 = eval { from_json($_[0]->{'missing_val'}) };
		if ($@) {
			$d1 = int($_[0]->{'missing_val'});
		}
		else {
			$d1 = int($d1->{'value'});
		}

		unless ($d) {
			$d1 = 0;
		}
		$_[1]->{'content'}{'user_settings'}{'NMB'} = $d1;
	},

	chk_cdp => sub {
		my $d = eval { from_json($_[0]->{'chk_cdp'}) };
		if ($@) {
			$d = int($_[0]->{'chk_cdp'});
		}
		else {
			$d = int($d->{'value'});
		}

		my $d1 = eval { from_json($_[0]->{'cmb_cdp'}) };
		if ($@) {
			$d1 = (split(" ", $_[0]->{'cmb_cdp'}))[0];
		}
		else {
			$d1 = (split(" ", $d1->{'value'}))[0];
		}

		unless ($d) {
			$d1 = '0';
		}
		if ($d1 eq 'Real-time') {
			$d1 = 1;
		}
		$_[1]->{'content'}{'user_settings'}{'CDP'} = int($d1);
	},

	verify_bkset => sub {
		my $d = eval { from_json($_[0]->{'verify_bkset'}) };
		if ($@) {
			$d = $_[0]->{'verify_bkset'};
		}
		else {
			$d = $d->{'value'};
		}

		$_[1]->{'content'}{'user_settings'}{'RESCANINTVL'} = $d;
	},
);

#*****************************************************************************************************
# Subroutine : parseSch
# In Param   : HASH, STRING
# Out Param  : HASH
# Objective  : Prase scheduled fields from dashboard.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub parseSch {
	my @sk = ('nxttrftime', 'freq', 'cutoff', 'email', 'mailnoti');
	my ($jobType, $jobName);
	my $mun;
	$mun = $_[2] if (defined($_[2]));

	my $d = {content => {channel => 'save_scheduler', crontab => {$_[1] => {}}}};

	Common::loadCrontab();

	foreach (@{$_[0]}) {
		return {} unless (exists $_->{'bksetname'});

		if ($mun) {
			$_->{'bksetname'} =~ s/_$mun$//g;
		}

		if ($_->{'bksetname'} =~ /^Default BackupSet/) {
			$jobType = 'backup';
			$jobName = 'default_backupset';
		}
		elsif ($_->{'bksetname'} =~ /^LocalBackupSet/) {
			$jobType = 'local_backup';
			$jobName = 'local_backupset';
		}

		foreach my $field (@sk) {
			if (exists $_->{$field} and exists $extractFields{$field}) {
				$extractFields{$field}($_, $d, $_[1], $jobType, $jobName);
			}
		}
	}

	return $d;
}

#*****************************************************************************************************
# Subroutine : parseSchForDHB
# In Param   : HASH, STRING
# Out Param  : HASH
# Objective  : Prase scheduled fields for dashboard.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub parseSchForDHB {
	my @schDetails = ();
	if (exists $_[0]->{$_[1]}) {
		my %weeks = (
			sun => 1,
			mon => 2,
			tue => 3,
			wed => 4,
			thu => 5,
			fri => 6,
			sat => 7,
			'*' => '1234567'
		);
		foreach (keys %{$_[0]->{$_[1]}}) {
			# next if ($_[0]->{$_[1]}{$_}{'settings'}{'status'} eq 'disabled');

			my %sd = ();

			$sd{'bksetname'} = sprintf("%sBackupSet_%s",
				(($_ eq 'default_backupset') ? 'Default ' : 'Local'), Common::getMachineUser());
			$sd{'nxttrftime'} = sprintf(" %02d:%02d:00", $_[0]->{$_[1]}{$_}{'h'}, $_[0]->{$_[1]}{$_}{'m'});

			if ($_[0]->{$_[1]}{$_}{'settings'}{'emails'}{'status'} ne 'disabled') {
				if ($_[0]->{$_[1]}{$_}{'settings'}{'emails'}{'status'} eq 'notify_failure') {
					$sd{'mailnoti'} = 2;
				}
				elsif ($_[0]->{$_[1]}{$_}{'settings'}{'emails'}{'status'} eq 'notify_always') {
					$sd{'mailnoti'} = 3;
				}

				$sd{'email'} = $_[0]->{$_[1]}{$_}{'settings'}{'emails'}{'ids'};
			}
			else {
				$sd{'mailnoti'} = 0;
				$sd{'email'} = '';
			}

			if (exists $_[0]->{'cancel'} and exists $_[0]->{'cancel'}{$_} and
				($_[0]->{'cancel'}{$_}{'settings'}{'status'} eq 'enabled')) {
				$sd{'cutoff'} = sprintf("%02d:%02d:00", $_[0]->{'cancel'}{$_}{'h'}, $_[0]->{'cancel'}{$_}{'m'});
			}
			else {
				$sd{'cutoff'} = '';
			}

			$sd{'freq'} = '';

			unless ($_[0]->{$_[1]}{$_}{'settings'}{'status'} eq 'disabled') {
				foreach my $day (split(/,/, $_[0]->{$_[1]}{$_}{'dow'})) {
					chomp($day);
					$sd{'freq'} .= $weeks{$day};
				}

				if ($_[0]->{$_[1]}{$_}{'settings'}{'frequency'} eq 'hourly') {
					$sd{'freq'} = 'Hourly';
				}
				elsif ($_[0]->{$_[1]}{$_}{'settings'}{'frequency'} eq 'immediate') {
					$sd{'freq'} = '';
				}
			}

			push(@schDetails, \%sd);
		}
	}

	return \@schDetails;
}

#*****************************************************************************************************
# Subroutine : parseSettings
# In Param   : HASH
# Out Param  : HASH
# Objective  : Parse settings from dashboard.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub parseSettings {
	my $d = {content => {channel => 'save_user_settings', user_settings => {}}};
	$_[0] = [$_[0]] unless (ref($_[0]) eq 'ARRAY');

	foreach (@{$_[0]}) {
		foreach my $field (keys %{$_}) {
			if (exists $extractFields{$field}) {
				$extractFields{$field}($_, $d);
			}
		}
	}

	return $d;
}

#*****************************************************************************************************
# Subroutine			: parseFilenames
# Objective				: Parse filenames from the prop settings
# Added By				: Yogesh Kumar
# Modified By			: Sabin Cheruvattil
#****************************************************************************************************/
sub parseFilenames {
	my %fileInfo = ();
	my $filename = '';
	foreach (split(/^/, $_[0])) {
		$_ =~ s/\r//g;
		$_ =~ s/\n//g;
		if ($_ =~ /\\0$/) {
			$filename = $_[1] ? Common::urlDecode(substr($_, 0, -2)) : parseQuote(substr($_, 0, -2));
			next if ($filename =~ /^\s*$/);
			if (utf8::is_utf8($filename)) {
				utf8::downgrade($filename);
			}
			$fileInfo{$filename}{'type'} = 'd';
			$fileInfo{$filename}{'disabled'} = 1;
		}
		elsif ($_ =~ /0$/) {
			$filename = $_[1] ? Common::urlDecode(substr($_, 0, -1)) : parseQuote(substr($_, 0, -1));
			next if ($filename =~ /^\s*$/);
			if (utf8::is_utf8($filename)) {
				utf8::downgrade($filename);
			}
			$fileInfo{$filename}{'type'} = 'f';
			$fileInfo{$filename}{'disabled'} = 1;
		}
		elsif ($_ =~ /\\1$/) {
			$filename = $_[1] ? Common::urlDecode(substr($_, 0, -2)) : parseQuote(substr($_, 0, -2));
			next if ($filename =~ /^\s*$/);
			if (utf8::is_utf8($filename)) {
				utf8::downgrade($filename);
			}
			$fileInfo{$filename}{'type'} = 'd';
			$fileInfo{$filename}{'disabled'} = 0;
		}
		elsif ($_ =~ /1$/) {
			$filename = $_[1]? Common::urlDecode(substr($_, 0, -1)) : parseQuote(substr($_, 0, -1));
			next if ($filename =~ /^\s*$/);
			if (utf8::is_utf8($filename)) {
				utf8::downgrade($filename);
			}
			$fileInfo{$filename}{'type'} = 'f';
			$fileInfo{$filename}{'disabled'} = 0;
		}
	}

	return \%fileInfo;
}

#*****************************************************************************************************
# Subroutine			: parseQuote
# Objective				: Parse for double quote and replace
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar
#****************************************************************************************************/
sub parseQuote {
	return '' unless($_[0]);

	$_[0] =~ s/&apos;/'/;
	$_[0] =~ s/&quot;/"/;
	return Common::urlDecode($_[0]);
}

#*****************************************************************************************************
# Subroutine			: parseBackupSet
# Objective				: Parse backup sets from prop settings
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parseBackupSet {
	my $jobName   = 'backup';
	$jobName = 'localbackup' if ($_[0]->{'key'} eq 'LocalBackupSet');
	my $fileInfo = parseFilenames($_[0], 'value', 1);
	my $oldFileInfo = parseFilenames($_[0], 'oldvalue', 1);

	return {
		'content' => {
			'channel' => sprintf("save_%s%s_content", $jobName, 'set'),
			'files' => $prop{$_[0]->{'type'}}($jobName, $fileInfo, $oldFileInfo)
		}
	};
}

#*****************************************************************************************************
# Subroutine : parseExcludeFiles
# In Param   : STRING or HASH
# Out Param  : HASH
# Objective  : Prase scheduled fields from dashboard.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub parseExcludeFiles {
	my $pbkpf = Common::getCatfile(Common::getUserProfilePath(), $_[1]);
	my $partialFilenames = '';
	my $fileInfo = {};
	my $oldFileInfo = {};

	if (ref($_[0]) eq 'HASH') {
		$fileInfo = parseFilenames($_[0]->{'value'}, 0)                   if (exists $_[0]->{'value'});
		$oldFileInfo = parseFilenames($_[0]->{'oldvalue'}, 'oldvalue', 0) if (exists $_[0]->{'oldvalue'});
	}
	else {
		$fileInfo = parseFilenames($_[0], 0);
	}

	if (-f $pbkpf and open(my $bsContents, '<', "$pbkpf.info")) {
		while(my $filename = <$bsContents>) {
			chomp($filename);
			my $status = <$bsContents>;
			chomp($status);

			if (exists $fileInfo->{$filename}) {
				$partialFilenames .= "$filename\n";
				if ($fileInfo->{$filename}{'disabled'}) {
					$partialFilenames .= "disabled\n";
				}
				else {
					$partialFilenames .= "enabled\n";
				}
				delete $fileInfo->{$filename};
			}
			else {
				$partialFilenames .= "$filename\n$status\n";
			}
		}
		close($bsContents);

		foreach my $filename (keys %{$fileInfo}) {
			$partialFilenames .= "$filename\n";
			if ($fileInfo->{$filename}{'disabled'}) {
				$partialFilenames .= "disabled\n";
			}
			else {
				$partialFilenames .= "enabled\n";
			}
		}
	}

	return $partialFilenames;

#	return {
#		'content' => {
#			'channel' => 'save_settings',
#			'settings' => {
#				'partialExclude' => $partialFilenames
#			}
#		}
#	};
}

#*****************************************************************************************************
# Subroutine : parseArchiveCleanup2
# In Param   : HASH, STRING
# Out Param  : HASH
# Objective  : Prase periodic archive cleanup from dashboard.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub parseArchiveCleanup2 {
	my %archiveSettings = ();
	if (ref $_[0] eq 'ARRAY') {
		return {} if ($_[0]->[0]->{'arch_cleanup_checked'} eq '');

		my $arch_cleanup_checked = from_json($_[0]->[0]->{'arch_cleanup_checked'});
		my $freq_days = from_json($_[0]->[0]->{'freq_days'});
		my $freq_percent = from_json($_[0]->[0]->{'freq_percent'});
		my $arch_email = from_json($_[0]->[0]->{'arch_email'});

		return {} if ($arch_cleanup_checked->{'value'} eq '');

		$archiveSettings{'settings'}{'status'} = (int($arch_cleanup_checked->{'value'}) ? 'enabled':'disabled');
		$archiveSettings{'cmd'} = "$freq_days->{'value'} $freq_percent->{'value'} 0";

		if ($arch_email->{'value'} eq "") {
			$archiveSettings{'settings'}{'emails'}{'status'} = 'disabled';
		}
		else {
			$archiveSettings{'settings'}{'emails'}{'status'} = 'notify_always';
			$archiveSettings{'settings'}{'emails'}{'ids'}    = $arch_email->{'value'};
		}
	}
	else {
		return {} if ($_[0]->{'arch_cleanup_checked'} eq '');

		$archiveSettings{'settings'}{'status'} = (int($_[0]->{'arch_cleanup_checked'}) ? 'enabled':'disabled');
		$archiveSettings{'cmd'} = "$_[0]->{'freq_days'} $_[0]->{'freq_percent'} 0";

		if ($_[0]->{"arch_email"} eq "") {
			$archiveSettings{'settings'}{'emails'}{'status'} = 'disabled';
		}
		else {
			$archiveSettings{'settings'}{'emails'}{'status'} = 'notify_always';
			$archiveSettings{'settings'}{'emails'}{'ids'}    = $_[0]->{"arch_email"};
		}
	}

	return {
		'content' => {
			'channel' => 'save_scheduler',
			'crontab' => {
				$_[1] => {
					'archive' => {
						'default_backupset' => \%archiveSettings
					}
				}
			}
		}
	};
}

#*****************************************************************************************************
# Subroutine : parseACForDHB
# In Param   : HASH, STRING
# Out Param  : HASH
# Objective  : Prase periodic archive cleanup fields for dashboard.
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub parseACForDHB {
	my %archiveCleanupDetails;
	if ($_[0]->{'settings'}{'status'} eq 'enabled') {
		$archiveCleanupDetails{'arch_cleanup_checked'} = 1;
	}
	else {
		$archiveCleanupDetails{'arch_cleanup_checked'} = 0;
	}

	if ($_[0]->{'cmd'} ne '') {
		my $c = substr($_[0]->{'cmd'}, rindex($_[0]->{'cmd'}, $_[1]), length $_[0]->{'cmd'});
		my @cv = split(' ', $c);
		$archiveCleanupDetails{'freq_days'} = $cv[1];
		$archiveCleanupDetails{'freq_percent'} = $cv[2];
	}

	if ($_[0]->{'settings'}{'emails'}{'status'} eq 'notify_always') {
		$archiveCleanupDetails{'arch_email'} = $_[0]->{'settings'}{'emails'}{'ids'};
	}
	return \%archiveCleanupDetails;
}

#*****************************************************************************************************
# Subroutine			: parseArchiveCleanup
# Objective				: Parse archive cleanup from prop settings
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parseArchiveCleanup {
	my %archiveSettings = ();
	$archiveSettings{'settings'}{'status'} = ($_[0]->{'value'} ? 'enabled':'disabled') if ($_[0]->{'key'} eq 'arch_cleanup_checked');

	if ($_[0]->{'key'} eq 'freq_days') {
		$AppConfig::tempVar = int($_[0]->{'value'});
		return {};
	}

	if ($_[0]->{'key'} eq 'freq_percent') {
		$archiveSettings{'cmd'} = "$AppConfig::tempVar $_[0]->{'value'}";
		$AppConfig::tempVar = undef;
	}

	return {
		'content' => {
			'channel' => 'save_scheduler',
			'crontab' => {
				$_[1] => {
					'archive' => {
						'default_backupset' => \%archiveSettings
					}
				}
			}
		}
	};
}

#*****************************************************************************************************
# Subroutine			: getLockSettings
# Objective				: Get all fields lock settings from prop
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getLockSettings {
	my $isLocked = $_[1];

	my %ls = (
		4 => {
			'type' => 'set',
			'key' => 'chk_asksave',
			'islocked' => $isLocked
		},
		5 => {
			'type' => 'set',
			'key' => 'chk_update',
			'islocked' => $isLocked
		},
		6 => {
			'type' => 'set',
			'key' => 'slide_throttle',
			'islocked' => $isLocked
		},
		9 => {
			'type' => 'set',
			'key' => 'lst_partexclude',
			'islocked' => $isLocked
		},
		10 => {
			'type' => 'sch',
			'key' => 'nxttrftime',
			'bksetname' => 'Default BackupSet',
			'islocked' => $isLocked
		},
		11 => {
			'type' => 'sch',
			'key' => 'freq',
			'bksetname' => 'Default BackupSet',
			'islocked' => $isLocked
		},
		12 => {
			'type' => 'sch',
			'key' => 'cutoff',
			'bksetname' => 'Default BackupSet',
			'islocked' => $isLocked
		},
		13 => {
			'type' => 'sch',
			'key' => 'email',
			'bksetname' => 'Default BackupSet',
			'islocked' => $isLocked
		},
		16 => {
			'type' => 'sch',
			'key' => 'nxttrftime',
			'bksetname' => 'LocalBackupSet',
			'islocked' => $isLocked
		},
		17 => {
			'type' => 'sch',
			'key' => 'freq',
			'bksetname' => 'LocalBackupSet',
			'islocked' => $isLocked
		},
		18 => {
			'type' => 'sch',
			'key' => 'cutoff',
			'bksetname' => 'LocalBackupSet',
			'islocked' => $isLocked
		},
		19 => {
			'type' => 'sch',
			'key' => 'email',
			'bksetname' => 'LocalBackupSet',
			'islocked' => $isLocked
		},
		24 => {
			'type' => 'arch_cleanup',
			'key' => 'arch_cleanup_checked',
			'islocked' => $isLocked
		},
		25 => {
			'type' => 'set',
			'key' => 'fail_val',
			'islocked' => $isLocked
		},
		26 => {
			'type' => 'set',
			'key' => 'ignore_accesserr',
			'islocked' => $isLocked
		},
		29 => {
			'type' => 'set',
			'key' => 'notify_missing',
			'islocked' => $isLocked
		},
		30 => {
			'type' => 'set',
			'key' => 'chk_multiupld',
			'islocked' => $isLocked
		},
		33 => {
			'type' => 'set',
			'key' => 'show_hidden',
			'islocked' => $isLocked
		},
		35 => {
			'type' => 'bkpset_linux',
			'key' => 'Default BackupSet',
			'islocked' => $isLocked
		},
		36 => {
			'type' => 'bkpset_linux',
			'key' => 'LocalBackupSet',
			'islocked' => $isLocked
		},
	);

	return $ls{$_[0]->{'key'}} || {};
}

#*****************************************************************************************************
# Subroutine : updateLockSettings
# In Param   : STRING
# Out Param  : HASH
# Objective  : Update & save lock settings
# Added By   : Yogesh Kumar
#****************************************************************************************************/
sub updateLockSettings {
	my $keyid = 0;
	my ($ls, $pls);
	$pls = from_json($_[0]);

	unless (int($pls->{'time'}) > int($_[1]->{'locksettings'}{'time'})) {
		return 1;
	}

	$_[1]->{'locksettings'}{'time'} = $pls->{'time'};
	$_[1]->{'ismodified'} = 1;
	foreach (split //, $pls->{'value'}) {
		$ls = getLockSettings({key => $keyid++}, int($_));
		next unless (exists $ls->{'type'});
		if ($ls->{'type'} eq 'sch') {
			if (exists $ls->{'bksetname'}) {
				$_[1]->{$ls->{'type'}}{$ls->{'key'}}{$ls->{'bksetname'}}{'islocked'} = $ls->{'islocked'}
			}
			else {
				$_[1]->{$ls->{'type'}}{$ls->{'key'}}{$ls->{'backupSet'}}{'islocked'} = $ls->{'islocked'};
			}
		}
		else {
			$_[1]->{$ls->{'type'}}{$ls->{'key'}}{'islocked'} = $ls->{'islocked'};
		}
	}

	return 1;
}

#*****************************************************************************************************
# Subroutine			: parse
# Objective				: Parse prop settings
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parse {
use Data::Dumper;
return {};
	if ($_[0]->{'STATUS'} eq 'FAILURE') {
		return {};
	}

	unless (exists $_[0]->{'type'}) {
		return getLockSettings($_[0]);
	}

	if ($_[0]->{'type'} eq 'sch') {
		return parseSch($_[0], $_[1]);
	}
	elsif ($_[0]->{'type'} eq 'bkpset_linux') {
		return parseBackupSet($_[0]);
	}
	elsif ($_[0]->{'type'} eq 'set') {
		if ($_[0]->{'key'} eq 'lst_partexclude') {
#print "empty\n";
			return parseExcludeFiles($_[0], $AppConfig::partialExcludeListFile);
		}
		elsif ($_[0]->{'key'} eq 'chk_update') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'NOTIFYSOFTWAREUPDATE' => int($_[0]->{'value'})
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'fail_val') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'NFB' => int($_[0]->{'value'})
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'ignore_accesserr') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'IFPE' => int($_[0]->{'value'})
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'chk_asksave') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'RESTORELOCATIONPROMPT' => int($_[0]->{'value'})
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'chk_multiupld') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'ENGINECOUNT' => (int($_[0]->{'value'}) ? $AppConfig::maxEngineCount : $AppConfig::minEngineCount)
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'show_hidden') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'SHOWHIDDEN' => int($_[0]->{'value'})
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'slide_throttle') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'BWTHROTTLE' => int($_[0]->{'value'})
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'notify_missing') {
			$AppConfig::tempVar = int($_[0]->{'value'});
			return {};
		}
		elsif ($_[0]->{'key'} eq 'missing_val') {
			unless($AppConfig::tempVar) {
				$_[0]->{'value'} = 0;
				$AppConfig::tempVar = undef;
			}
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'NMB' => int($_[0]->{'value'})
					}
				}
			};
		}
	}
	elsif ($_[0]->{'type'} eq 'arch_cleanup') {
		return parseArchiveCleanup($_[0], $_[1]);
	}
	else {
		return {};
	}
}

#*****************************************************************************************************
# Subroutine			: getLockedScheduleFields
# Objective				: This function is used to get the locked schedule fileds
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getLockedScheduleFields {
	my $schpropsettings = Common::getPropSettings('master');
	return () unless(exists $schpropsettings->{'sch'});

	my @lockedfields = ();
	foreach my $key (keys %{$schpropsettings->{'sch'}}) {
		my $fieldkey = (keys(%{$schpropsettings->{'sch'}{$key}}))[0];
		my $optype = (($fieldkey eq 'Default BackupSet')? 'backup_' : 'localbackup_');
		push(@lockedfields, $optype . $key) if ($schpropsettings->{'sch'}{$key}{$fieldkey}{'islocked'} == 1);
	}

	return @lockedfields;
}

#*****************************************************************************************************
# Subroutine			: getLockedArchiveFields
# Objective				: This function is used to get the locked archive fileds
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub getLockedArchiveFields {
	my $archpropsettings = Common::getPropSettings('master');
	return () unless(exists $archpropsettings->{'arch_cleanup'});

	my @lockedfields = ();
	foreach my $key (keys %{$archpropsettings->{'arch_cleanup'}}) {
		push(@lockedfields, $key) if ($archpropsettings->{'arch_cleanup'}{$key}{'islocked'} == 1);
	}

	return @lockedfields;
}

1;
