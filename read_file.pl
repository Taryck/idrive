#!/usr/bin/env perl
use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;
use Configuration;
use File::Basename;
use File::stat;
use JSON;

use constant NO_EXIT => 1;
#Signal handling. Signals received by the script during execution
$SIG{INT}  = \&cleanUp;
$SIG{TERM} = \&cleanUp;
$SIG{TSTP} = \&cleanUp;
$SIG{QUIT} = \&cleanUp;
#$SIG{PWR} = \&cleanUp;
$SIG{KILL} = \&cleanUp;
$SIG{USR1} = \&cleanUp;
my $isAccountConfigured = 0;

require 'Header.pl';
use Data::Dumper;

loadUserData();
	Helpers::loadUserConfiguration();

	my $ucf = Helpers::getUserConfigurationFile();
	if (-f $ucf and !-z $ucf) {
		my $ucj = Helpers::decryptString(Helpers::getFileContents($ucf));
		print $ucj;
}
