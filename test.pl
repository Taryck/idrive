#!/usr/bin/perl

use strict;
use warnings;

use DateTime::Format::Strptime;
use POSIX qw(strftime);

my $f = "%YT%mT%d TTTT%H:%M:%S";
my $s = strftime($f, localtime);

print "$s\n";

my $Strp = DateTime::Format::Strptime->new(
    pattern   => $f,
    locale    => 'en_US',
    time_zone => 'US/Eastern',
);

my $dt = $Strp->parse_datetime($s);

print $dt->epoch, "\n";
print scalar localtime $dt->epoch, "\n";
