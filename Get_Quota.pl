#!/usr/bin/perl
####################################################################
#Script Name : Get_Quota.pl
#TBE : ENH-004 - Get Quota, compute remaining quota
# Get a fresh Quota, 
# Save it to .quota file
# Display Quota file content
#####################################################################
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
require 'Header.pl';
#use Constants 'CONST';
require Constants;

#Configuration File Path#
system("clear");
my $isPrivate = 0;
my $encType = undef;
my $pvtKey = undef;
my $pvtKeyField = undef;
#Check if EVS Binary exists.
my $err_string = checkBinaryExists();
if($err_string ne "") {
        print qq($err_string);
        exit 1;
}

our $userName = ${ARGV[0]};
if ($userName eq "") {
	$userName = getCurrentUser();
}
if ($userName eq "") {
	print 'Provide User as first parameter or login using Login.pl !'.$lineFeed;
	exit 1;
}
loadUserData();
if ( substr( $pwdPath, -4) ne "_SCH" ){
	$pwdPath = $pwdPath."_SCH";
}
my %Results = getQuota_Array();
WriteQuotaFile( $usrProfileDir.'/.quota.txt',
				$filePermission,
				$Results{totalquota},
				$Results{usedquota},
				$Results{remainingquota});

open QUOTA_FILE, "<", $usrProfileDir.'/.quota.txt' or (traceLog($lineFeed.Constants->CONST->{'ConfMissingErr'}." reason :$! $lineFeed", __FILE__, __LINE__) and die);
my @QuotaFile = <QUOTA_FILE>;
close QUOTA_FILE;
				
print @QuotaFile;
