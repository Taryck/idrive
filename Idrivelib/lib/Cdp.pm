#*****************************************************************************************************
# CDP management package
#
# Created By	: Vijay Vinoth @ IDrive Inc
#****************************************************************************************************/
use strict;
use warnings;

package Cdp;

use base 'Linux::Inotify2';
use Linux::Inotify2;
use File::Find;
use IO::Socket;   
use AppConfig;
use Common;

$SIG{INT}	= \&cleanUp;
$SIG{TERM}	= \&cleanUp;
$SIG{TSTP}	= \&cleanUp;
$SIG{QUIT}	= \&cleanUp;
$SIG{KILL}	= \&cleanUp;
$SIG{USR1}	= \&cleanUp;

my $socketClient;

#******************************************************************************************************************
# Subroutine		: new
# Objective			: This subroutine will initialize and start all event names and watcher
# Added By			: Vijay Vinoth
#******************************************************************************************************************
sub new {
	my ($class, $conf) = @_;
	my $self = $class->SUPER::new();

	# Initialize vars.
	$self->{cookies_to_rm} = {};
	# To Load all events name
	$self->load_ev_names();
	$self->set_watcher_sub();

	return $self;
}

#******************************************************************************************************************
# Subroutine Name   : load_ev_names.
# Objective         : This subroutine will load all event names ( Eg.IN_CREATE,IN_CLOSE_WRITE,IN_ACCESS)
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub load_ev_names {
	my ( $self ) = @_;
	no strict 'refs';
	for my $name (@Linux::Inotify2::EXPORT) {
		my $mask = &{"Linux::Inotify2::$name"};
		$self->{ev_names}->{$mask} = $name;
	}
	use strict 'refs';
}

#******************************************************************************************************************
# Subroutine Name   : inotify_watch.
# Objective         : This subroutine will intimate to watch the mentioned event names.Kind of filter for event names
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub inotify_watch {
	my ( $self, $dir, $initial_run ) = @_;
	$! = undef;
	my $watcher = $self->watch(
		$dir,
		# ( IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_CREATE | IN_DELETE | IN_IGNORED | IN_UNMOUNT | IN_DELETE_SELF ),
		(IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_CREATE | IN_DELETE | IN_DELETE_SELF),
		$self->{watcher_sub}
	);

	$self->{num_to_watch}++;
	if ( $watcher ) {
		$self->{num_watched}++;
	} else {
		Common::traceLog("Error adding watcher: $!", undef, undef, 1);
	}

	return $watcher;
}

#*****************************************************************************************************
# Subroutine	: watch_file
# In Param		: filename | String
# Out Param		: Watcher Instance | Mixed
# Objective		: Watches the mentioned event names for the type file
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub watch_file {
	my ($self, $file) = ($_[0], $_[1]);
	$! = undef;
	my $watcher = $self->watch(
		$file,
		(IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_CREATE | IN_DELETE),
		$self->{watcher_sub}
	);

	$self->{num_to_watch}++;

	if($watcher) {
		$self->{num_watched}++;
	} else {
		Common::traceLog("Error adding file[$file] watcher: $!");
	}

	return $watcher;
}

#******************************************************************************************************************
# Subroutine Name   : watch_this.
# Objective         : 
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub watch_this {
	my ( $self, $dir ) = @_;

	return 0 unless -d $dir;

	if ( defined $self->{grep_dirs_sub} ) {
		return 0 unless $self->{grep_dirs_sub}->( $dir );
	}
	return 1;
}

#******************************************************************************************************************
# Subroutine Name   : item_to_watch.
# Objective         : This subroutine is helps to watch the given file based on pre defined events
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub item_to_watch {
	my ( $self, $dir, $initial_run ) = @_;
	return undef unless $self->watch_this( $dir );
	return $self->inotify_watch( $dir, $initial_run );
}

#******************************************************************************************************************
# Subroutine Name   : items_to_watch_recursive.
# Objective         : Helps to add newly created dir/moved dir (recursively) in watcher
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub items_to_watch_recursive {
	my ( $self, $dirs_to_watch, $initial_run ) = @_;

	# Add watchers.
	return finddepth( {
		wanted => sub {
		$self->item_to_watch( $_, $initial_run ); # 
		},
		no_chdir => 1, # no need to change the dir
	},
		@$dirs_to_watch
	); #  It does a postorder traversal instead of a preorder traversal, working from the bottom of the directory tree up
}


#******************************************************************************************************************
# Subroutine Name   : item_to_remove_by_name.
# Objective         : Helps to remove old watch if exists
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub item_to_remove_by_name {
	my ( $self, $item_torm_base, $recursive ) = @_;

	my $ret_code = 1;

	# Removing by name.
	my $item_torm_len = length( $item_torm_base );
	foreach my $watch ( values %{ $self->{w} } ) {
		my $remove = 0;
		my $item_name = $watch->{name};
		if ( $recursive ) {
			if ( length($item_name) >= $item_torm_len
			&& substr($item_name,0,$item_torm_len) eq $item_torm_base
			) {
				$remove = 1;
			}

		} else {
			$remove = 1 if $item_name eq $item_torm_base;
		}

		if ( $remove ) {
			# @DBUG: Enable for debugging
			Common::traceLog("Stopping watch $item_name (by name '$item_torm_base', rec: $recursive).", undef, undef, 1);
			my $tmp_ret_code = $watch->cancel;
			# $self->dump_watched('removed by name') ;
			$ret_code = 0 unless $tmp_ret_code;
		}
	}

	return $ret_code;
}


#******************************************************************************************************************
# Subroutine Name   : item_to_remove_by_event.
# Objective         : Event on item itself to remove old watch if exists
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub item_to_remove_by_event {
	my ( $self, $item, $e, $recursive ) = @_;

	# @DBUG: Enable for debugging
	# Common::traceLog("Stopping watch $item (by object).");

	my $ret_code = 1;
	if ( $recursive ) {
		my $items_inside_prefix = $item . '/';
		$ret_code = $self->item_to_remove_by_name( $items_inside_prefix, $recursive );
	}
	my $tmp_ret_code = $e->{w}->cancel;
	$ret_code = 0 unless $tmp_ret_code;
	return $ret_code;

	Common::traceLog("Error: Can't remove item '$item' (not found).", undef, undef, 1);
	return 0;
}

#******************************************************************************************************************
# Subroutine Name   : set_watcher_sub.
# Objective         : Helps to set the files/dir details in watcher
# Added By          : Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#******************************************************************************************************************
sub set_watcher_sub {
	my ( $self ) = @_;
	$self->{watcher_sub} = sub {
		my $e = shift;
		my $fullname = $e->fullname;

		# Print event info.
		if($fullname !~ m/.swp/ && $fullname !~ m/.swpx/ && $fullname !~ m/.swx/) {
			my $mask = $e->{mask};
			if(defined $mask) {
				if((defined $self->{ev_names}->{$mask}) and !-d $fullname) {
					if($self->{ev_names}->{$mask} ne "IN_CREATE") {
						print $socketClient "$self->{ev_names}->{$mask}|$fullname \n";
					} else {
						# @TODO: Verify the above if condition
						print $socketClient "$self->{ev_names}->{$mask}|$fullname \n";
					}
				} elsif(!$self->{ev_names}->{$mask}) {
					# Handle directory rename
					if(-d $fullname) {
						print $socketClient "IDR_CST_POST_MOVE|$fullname \n";
					} else {
						print $socketClient "IDR_CST_PRE_MOVE|$fullname \n";
					}
				}
			}
		}

		my $is_dir = ($e->{mask} & IN_ISDIR);
		my $moved_from = undef;

		if($e->IN_CREATE) {
			if($is_dir) {
				#Update path inside existing watch
				$self->items_to_watch_recursive([$fullname], 0 );
			}
		} elsif ( $e->IN_MOVED_TO ) {
			my $cookie = $e->{cookie};
			if ( exists $self->{cookies_to_rm}->{$cookie} ) {
				if ( $self->{cookies_to_rm}->{$cookie}->[0] ) {
					# Check if we want to watch new name.
					if ( $self->watch_this($fullname) ) {
						# Update path inside existing watch.
						$self->items_to_watch_recursive( [ $fullname ], 0 );
						$moved_from = $self->{cookies_to_rm}->{$cookie}->[1];
						delete $self->{cookies_to_rm}->{$cookie};

						# Remove old watch if exists.
					} elsif ( defined $self->{cookies_to_rm}->{$cookie} ) {
						my $c_fullname = $self->{cookies_to_rm}->{$cookie};
						$self->item_to_remove_by_name( $c_fullname, 1 );
						$moved_from = $self->{cookies_to_rm}->{$cookie}->[1];
						delete $self->{cookies_to_rm}->{$cookie};

						# Remember new cookie.
					} else {
						$self->{cookies_to_rm}->{ $e->{cookie} } = undef;
					}

				} else {
					$moved_from = delete $self->{cookies_to_rm}->{$cookie}->[1];
				}

			} else {
				$self->items_to_watch_recursive( [ $fullname ], 0 );
			}
		}

		# Event on directory, but item inside changed.
		if ( length($e->{name}) ) {
			# Directory moved away.
			if ( $e->{mask} & IN_MOVED_FROM ) {
				my $cookie = $e->{cookie};
				if ( exists $self->{cookies_to_rm}->{$cookie} ) {
					# Nothing to do. As per assumption No MOVED_TO, MOVED_FROM order.
					Common::traceLog("Warning: Probably moved_from after moved_to occurs.", undef, undef, 1);
				} else {
					# We don't know new name yet, so we can't decide what to do (update or remove watch).
					# As per assumption No items related events between MOVED_FROM and MOVED_TO..
					my $is_watched = $is_dir;
					$self->{cookies_to_rm}->{ $cookie } = [ $is_watched, $fullname ];
				}
			}

		# Event on item itself.
		} elsif ( $e->{mask} & (IN_IGNORED | IN_UNMOUNT | IN_ONESHOT | IN_DELETE_SELF) ) {
			$self->item_to_remove_by_event( $fullname, $e, 1 );
		}

		return 1;
	};

	return 1;
}

#******************************************************************************************************************
# Subroutine Name   : add_dirs.
# Objective         : Helps to add dir (recursively) in watcher. The call is from api
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub add_dirs {
	my ( $self, $dirs_to_watch ) = @_;

	$self->{num_watched} = 0;
	$self->{num_to_watch} = 0;

	$self->items_to_watch_recursive( $dirs_to_watch, 1 );
	return 1;
}

#******************************************************************************************************************
# Subroutine Name   : cleanup_moved_out.
# Objective         : Remove all IN_MOVE_FROM without IN_MOVE_TO.
# Added By          : Vijay Vinoth
#******************************************************************************************************************
sub cleanup_moved_out {
	my ( $self ) = @_;

	return 1 unless scalar keys %{ $self->{cookies_to_rm} };

	foreach my $cookie ( keys %{ $self->{cookies_to_rm} } ) {
		if ( defined $self->{cookies_to_rm}->{$cookie} ) {
			next unless $self->{cookies_to_rm}->{$cookie}->[0]; # check is_watched
			my $fullname = $self->{cookies_to_rm}->{$cookie};
			$self->item_to_remove_by_name( $fullname, 0 );
			my $items_inside_prefix = $fullname . '/';
			$self->item_to_remove_by_name( $items_inside_prefix, 1 );
			delete $self->{cookies_to_rm}->{$cookie};
		}
	}
	return 1;
}

#******************************************************************************************************************
# Subroutine Name   : pool
# Objective         : Helps to read the events in the current and Remove all IN_MOVE_FROM without IN_MOVE_TO.
# Added By          : Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#******************************************************************************************************************
sub pool {
	if(time() - ${$_[1]} > 60) {
		${$_[1]} = time();
		# when client exits server also exits
		exit(0) if(!-f $_[2] || !Common::isFileLocked($_[3]) || !Common::isFileLocked($_[4]));

		my $nwpid = Common::getFileContents($_[4]);
		chomp($nwpid);

		exit(0) if($nwpid ne $_[5]);
	}

	my $self = $_[0];
	$! = undef;
	
	my @events = $self->read;
	if(@events > 0) {
		$self->cleanup_moved_out();
		return 1;
	}

	Common::traceLog("Error: Event read error - $!", undef, undef, 1) if $!;
	return 1;
}

#******************************************************************************************************************
# Subroutine Name   : clientSocketInit
# Objective         : This subroutine will initialize client socket
# Added By          : Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#******************************************************************************************************************
sub clientSocketInit {
	$AppConfig::displayHeader = 0;

	$socketClient	= new IO::Socket::INET(
		PeerAddr	=> $AppConfig::localHost,
		PeerPort	=> $AppConfig::localPort,
		Proto		=> $AppConfig::protocol,
	);

	Common::retreat(["Could not create socket: $!"]) unless($socketClient);
	return 1;
}

#******************************************************************************************************************
# Subroutine		: cleanUp
# Objective			: This subroutine is to handle the signals
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#******************************************************************************************************************
sub cleanUp {
	my $cdpclientlock	= Common::getCDPLockFile('client');
	unlink($cdpclientlock) if(-f $cdpclientlock);

	close $socketClient if(defined($socketClient));
	exit(0);
}

=head1 Assumptions

a) No MOVED_TO, MOVED_FROM order.
b) No items related events between MOVED_FROM and MOVED_TO.

=head1 Troubleshooting

=head2 Error "no space left on device"

See Kernel Korner - Intro to inotify, Sep 28 2005, Robert Love, Linux Journal (L<http://www.linuxjournal.com/article/8478?page=0,3>)

Commands like

cat /proc/sys/fs/inotify/max_queued_events
cat /proc/sys/fs/inotify/max_user_watches

echo 65536 > /proc/sys/fs/inotify/max_queued_events
echo 32768 > /proc/sys/fs/inotify/max_user_watches

should help.

=head1 See also

L<Linux::Inotify2|Linux::Inotify2> CPAN module.

=head1 Author

Michal Jurosz - L<irc://irc.freenode.org/#mj41> - email: mj{$zav}mj41.cz

=cut

1;