#!/usr/bin/perl
#*****************************************************************************************************
# 						This script is used to run the independent functionalities 
# 							Created By: Anil Kumar
#****************************************************************************************************/

$incPos = rindex(__FILE__, '/');
$incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

use strict;
use warnings;
use Helpers;
use constant NO_EXIT => 1;
init();


#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Anil Kumar
#****************************************************************************************************/
sub init {
	my $username = $ARGV[0];
	Helpers::loadAppPath();
	Helpers::loadServicePath();
	Helpers::loadUsername() and Helpers::loadUserConfiguration(NO_EXIT);
	
	performOperation($ARGV[1]);
	
}

#*****************************************************************************************************
# Subroutine			: performOperation
# Objective				: This method is used to differentiate the functionality based on the operation  required to done.
# Added By				: Anil Kumar
#****************************************************************************************************/
sub performOperation {
	my $operation = $_[0];
	if($operation eq "GETQUOTA")
	{
		getAndUpdateQuota();
	}
	else{
		Helpers::traceLog("Unknown operation: $operation");
		Helpers::display('Unknown operation: ', $operation);
	}
	
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
