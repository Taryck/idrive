#*****************************************************************************************************
# Prop settings
#
# Created By : Yogesh Kumar @ IDrive Inc
#****************************************************************************************************/

package PropSchema;
use strict;
use warnings;

our @propFields = (
	'chk_update', 'fail_val' , 'ignore_accesserr',
	'chk_asksave', 'chk_multiupld' , 'show_hidden',
	'slide_throttle', 'notify_missing', 'missing_val',
	'arch_cleanup_checked', 'freq_days', 'freq_percent',
	'DefaultBackupSet' , 'LocalBackupSet', 'lst_partexclude',
	'nxttrftime' , 'freq', 'cutoff',
	'email' , 'mailnoti'
);

my %prop = (
	'nxttrftime' => sub {
		my @time = split(':', $_[0]->{'value'});
		my %d =  (
			'h' => sprintf("%02d",$time[0]),
			'm' => sprintf("%02d",$time[1])
		);
		if ($_[1] ne 'enabled' or $_[2] eq 'immediate') {
			$d{'dom'} = '*';
			$d{'mon'} = '*';
			$d{'dow'} = '*';
			$d{'settings'}{'status'} = 'enabled';
			$d{'settings'}{'frequency'} = 'daily';
		}

		return \%d;
	},
	'freq' => sub {
		my @v;
		my $f = 'weekly';
		my $s = 'enabled';
		if (lc($_[0]->{'value'}) eq 'hourly') {
			@v = ('*');
			$f = 'hourly';
		}
		elsif ($_[0]->{'value'} eq '') {
			$s = 'disabled';
		}
		else {
			my @d = ('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat');
			@v = split('', $_[0]->{'value'});
			if (scalar @v == 7) {
				$f = 'daily';
			}
			foreach (0 .. $#v) {
				$v[$_] = $d[$v[$_] - 1];
			}
		}
		my %d = (
			'settings' => {
				'frequency' => $f,
				'status' => $s
			}
		);
		$d{'dow'} = join(',', @v) if ($s ne 'disabled');
		if ($f eq 'hourly') {
			$d{'h'} = '*';
			$d{'m'} = '0';
		}

		return \%d;
	},
	'cutoff' => sub {
		my %d = ();
		if ($_[0]->{'value'} eq '') {
			%d = (
				'settings' => {
					'status' => 'disabled'
				}
			);
		}
		else {
			my @time = split(':', $_[0]->{'value'});
			%d = (
				'h' => sprintf("%02d",$time[0]),
				'm' => sprintf("%02d",$time[1]),
				'settings' => {
					'status' => 'enabled'
				}
			);
		}
		return \%d;
	},
	'email' => sub {
		my $s = 'disabled';
		my $e = '';
		$s = 'enabled' if ($_[0]->{'value'} ne '');
		$e = $_[0]->{'value'} if ($_[0]->{'value'} ne '');

		return {
			'settings' => {
				'emails' => {
					'ids' => $e,
					'status' => $s
				}
			}
		};
	},
	'mailnoti' => sub {
		my $s = 'disabled';
		if ($_[0]->{'value'} ne '') {
			$s = 'notify_failure' if (int($_[0]->{'value'}) == 2);
			$s = 'notify_always' if (int($_[0]->{'value'}) == 3);
		}
		return {
			'settings' => {
				'emails' => {
					'status' => $s
				}
			}
		};
	},

	'bkpset_linux' => sub {
		my $bsf = Common::getJobsPath($_[0], 'file');
		my %backupSet;
		my $userHomeDirCmd = Common::updateLocaleCmd('echo ~');
		my $userHomeDir = `$userHomeDirCmd`;
		chomp($userHomeDir);

		foreach my $fn (keys %{$_[1]}) {
			if (substr($fn, 0, 2) eq '~/') {
				$_[1]->{("$userHomeDir/" . substr($fn, 2))} = $_[1]->{$fn};
				delete $_[1]->{$fn};
			}
		}

		if (-e "$bsf.json" and !-z "$bsf.json") {
			my %backupSetInfo = %{JSON::from_json(Common::getFileContents("$bsf.json"))};
			foreach my $filename (keys %backupSetInfo) {
				next if (exists $_[2]->{$filename} and not exists $_[1]->{$filename});
				unless (exists $_[1]->{$filename} and ($_[1]->{$filename}{'type'} eq $backupSetInfo{$filename}{'type'}) and $_[1]->{$filename}{'disabled'}) {
					$backupSetInfo{$filename}{'type'} = $backupSetInfo{$filename}{'type'};
				}

				delete $_[1]->{$filename} if (exists $_[1]->{$filename});
			}
		}

		foreach (keys %{$_[1]}) {
			$backupSet{$_}{'type'} = $_[1]->{$_}{'type'} unless ($_[1]->{$_}{'disabled'});
		}

		my @newItemArray = keys %backupSet;
		@newItemArray = Common::verifyEditedFileContent(\@newItemArray);
		if(scalar(@newItemArray) > 0) {
			%backupSet = Common::getLocalDataWithType(\@newItemArray, 'backup', 1);
			%backupSet = Common::skipChildIfParentDirExists(\%backupSet);
		} else {
			%backupSet= ();
		}
		return \%backupSet;
	},
);

#*****************************************************************************************************
# Subroutine			: parseSch
# Objective				: Parse scheduler fields from prop settings
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parseSch {
	my ($jobType, $jobName, $c);

	return {} unless (exists $_[0]->{'bksetname'});

	if ($_[0]->{'bksetname'} eq 'Default BackupSet') {
		$jobType = 'backup';
		$jobName = 'default_backupset';
	}
	elsif ($_[0]->{'bksetname'} eq 'LocalBackupSet') {
		$jobType = 'local_backup';
		$jobName = 'local_backupset';
	}

	Common::loadCrontab();
	my $status    = Common::getCrontab($jobType, $jobName, '{settings}{status}');
	my $frequency = Common::getCrontab($jobType, $jobName, '{settings}{frequency}');
	$c = 'save_scheduler' if ($_[0]->{'type'} eq 'sch');
	$jobType = 'cancel' if ($_[0]->{'key'} eq 'cutoff');

	return {
		content => {
			'channel' => $c,
			'crontab' => {
				$_[1] => {
					$jobType => {
						$jobName => $prop{$_[0]->{'key'}}($_[0], $status, $frequency)
					}
				}
			}
		}
	};
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

	foreach (split(/\n/, $_[0]->{$_[1]})) {
		if ($_ =~ /\\0$/) {
			$filename = $_[2]? Common::urlDecode(substr($_, 0, -2)) : parseQuote(substr($_, 0, -2));
			$fileInfo{$filename}{'type'} = 'd';
			$fileInfo{$filename}{'disabled'} = 1;
		}
		elsif ($_ =~ /0$/) {
			$filename = $_[2]? Common::urlDecode(substr($_, 0, -1)) : parseQuote(substr($_, 0, -1));
			$fileInfo{$filename}{'type'} = 'f';
			$fileInfo{$filename}{'disabled'} = 1;
		}
		elsif ($_ =~ /\\1$/) {
			$filename = $_[2]? Common::urlDecode(substr($_, 0, -2)) : parseQuote(substr($_, 0, -2));
			$fileInfo{$filename}{'type'} = 'd';
			$fileInfo{$filename}{'disabled'} = 0;
		}
		elsif ($_ =~ /1$/) {
			$filename = $_[2]? Common::urlDecode(substr($_, 0, -1)) : parseQuote(substr($_, 0, -1));
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
	return $_[0];
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
# Subroutine			: parsePartialBKPF
# Objective				: Parse partial filenames from prop settings
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parsePartialBKPF {
	my $pbkpf = Common::getCatfile(Common::getUserProfilePath(), $AppConfig::partialExcludeListFile);
	my $partialFilenames = '';
	my $fileInfo = parseFilenames($_[0], 'value', 0);
	my $oldFileInfo = parseFilenames($_[0], 'oldvalue', 0);

	if (-f $pbkpf and open(my $bsContents, '<', "$pbkpf.info")) {
		while(my $filename = <$bsContents>) {
			chomp($filename);
			my $fileType = <$bsContents>;
			chomp($fileType);

			next if (exists $oldFileInfo->{$filename} and not exists $fileInfo->{$filename});
			unless (exists $fileInfo->{$filename} and $fileInfo->{$filename}{'disabled'}) {
				$partialFilenames .= "$filename\n";
				$partialFilenames .= "$fileType\n";
			}

			delete $fileInfo->{$filename} if (exists $fileInfo->{$filename});
		}

		close($bsContents);
	}

	foreach (keys %{$fileInfo}) {
		unless ($fileInfo->{'disabled'}) {
			$partialFilenames .= "$_\n";
			$partialFilenames .= "enabled\n";
		}
	}

	return {
		'content' => {
			'channel' => 'save_settings',
			'settings' => {
				'partialExclude' => $partialFilenames
			}
		}
	};
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
		if (defined($AppConfig::tempVar2)) {
			$archiveSettings{'cmd'} = "$_[0]->{'value'} $AppConfig::tempVar2 0";
			$AppConfig::tempVar2 = undef;
		}
		else {
			$AppConfig::tempVar2 = int($_[0]->{'value'});
			return {};
		}
	}

	if ($_[0]->{'key'} eq 'freq_percent') {
		if (defined($AppConfig::tempVar2)) {
			$archiveSettings{'cmd'} = "$AppConfig::tempVar2 $_[0]->{'value'} 0";
			$AppConfig::tempVar = undef;
		}
		else {
			$AppConfig::tempVar2 = int($_[0]->{'value'});
			return {};
		}
	}

	if ($_[0]->{'key'} eq 'arch_email') {
		if ($_[0]->{'value'} eq '') {
			$archiveSettings{'settings'}{'emails'}{'status'} = 'disabled';
		}
		else {
			$archiveSettings{'settings'}{'emails'}{'status'} = 'notify_always';
			$archiveSettings{'settings'}{'emails'}{'ids'} = $_[0]->{'value'};
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
# Subroutine			: getLockSettings
# Objective				: Get all fields lock settings from prop
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub getLockSettings {
	my $isLocked = 1;
	$isLocked = 0 if (exists $_[0]->{'ulusers'} and $_[0]->{'ulusers'} eq 'all');

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
# Subroutine			: parse
# Objective				: Parse prop settings
# Added By				: Yogesh Kumar
#****************************************************************************************************/
sub parse {
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
			return parsePartialBKPF($_[0]);
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
		elsif ($_[0]->{'key'} eq 'chk_cdp') {
			$AppConfig::chk_cdp = int($_[0]->{'value'});
			if ($AppConfig::cmb_cdp) {
				unless ($AppConfig::chk_cdp) {
					$AppConfig::cmb_cdp = 0;
				}
				return {
					'content' => {
						'channel' => 'save_user_settings',
						'user_settings' => {
							'CDP' => int($AppConfig::cmb_cdp)
						}
					}
				};
				$AppConfig::chk_cdp = undef;
				$AppConfig::cmb_cdp = undef;
			}
			return {};
		}
		elsif ($_[0]->{'key'} eq 'cmb_cdp') {
			unless(defined($AppConfig::chk_cdp)) {
				$AppConfig::cmb_cdp = (split(" ", $_[0]->{'value'}))[0];
				return {};
			}
			my $cmb = int((split(" ", $_[0]->{'value'}))[0]);
			unless ($AppConfig::chk_cdp) {
				$cmb = 0;
			}
			$AppConfig::chk_cdp = undef;
			$AppConfig::cmb_cdp = undef;
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'CDP' => $cmb
					}
				}
			};
		}
		elsif ($_[0]->{'key'} eq 'verify_bkset') {
			return {
				'content' => {
					'channel' => 'save_user_settings',
					'user_settings' => {
						'RESCANINTVL' => $_[0]->{'value'}
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
