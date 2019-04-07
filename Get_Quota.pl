#!/usr/bin/perl
####################################################################
#Script Name : Get_Quota.pl
#TBE : ENH-004 - Get Quota, compute remaining quota
# Get a fresh Quota, 
# Save it to .quota file
# Display Quota file content
#####################################################################
use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Helpers;

our $lineFeed = "\n";
our $userName = ${ARGV[0]};
if (! defined $userName or $userName eq "") {
#	$userName = getCurrentUser();
#}
#if ($userName eq "") {
	print 'Provide User as first parameter or login using Login.pl !'.$lineFeed;
	exit 1;
}
Helpers::loadAppPath();
Helpers::loadServicePath();
Helpers::setUsername($userName) if(defined($userName) && $userName ne '');
#if(Helpers::loadUsername()){
	Helpers::loadUserConfiguration();
#}
getAndUpdateQuota();
my $file = Helpers::getCachedStorageFile();
open QUOTA_FILE, "<", $file or die "Quota file $file do not exists";
my @QuotaFile = <QUOTA_FILE>;
close QUOTA_FILE;
				
print @QuotaFile;


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
	my $freeQuota = $result[0]->{'totalquota'} - $result[0]->{'usedquota'} ;
#	$result[0]->{$Configuration::accountStorageSchema{'freeQuota'}{'evs_name'}}
	$result[0]->{'remainingQuota'} = $freeQuota;
	if (Helpers::saveUserQuota(@result)) {
#		return 1 if(Helpers::loadStorageSize());
		return 1 ;
	}
	Helpers::traceLog('unable_to_cache_the_quota');
	Helpers::display('unable_to_cache_the_quota') ;
	return 0;
}