#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to display the Help content
#
# Created By: Senthil Pandian @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

my $incPos = rindex(__FILE__, '/');
my $incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

#use Data::Dumper;
use Common;
use AppConfig;

my (%LS,%Help) = () x 2;
if ($AppConfig::language eq 'EN') {
	use Locale::EN;
	# %LS = %Locale::EN::strings;
	%Help = %Locale::EN::content;
}
#my $tab = "      ";
#wrapTextAndDisplay($Help{'description'}->FETCH('edit_user_details_general_setting'));
#wrapTextAndDisplay("Backup Location:\n\tUse this option to update the backup location.\nBackup Type:\n\tUse this option to change the backup type from mirror to relative and vice versa.");
#wrapTextAndDisplay("Backup Location:\nUse this option to update the backup location.\nBackup Type:\nUse this option to change the backup type from mirror to relative and vice versa.");
#wrapTextAndDisplay("E-mail address:\n".$tab."Modify the email address provided at the time of setting up your account setup locally using this option.\nIgnore file/folder level permission error:\n".$tab."If your backup set contains files/folders that have insufficient access rights, $AppConfig::appType will not backup those files/folders. In such a case, your backup will be considered as 'Failure' by default. Enable this setting to ignore file/folder level access rights/permission errors.\nProxy details:");
#wrapTextAndDisplay($Help{'description'}->FETCH('schedule_online_backup'));
#our @ErrorArgumentsNoRetry = ("Permission denied",
                           # "Directory not empty",
                           # "No such file or directory"
                          # );
# idevs: delete_file: rmdir [/ubuntu/home] (in ibackup) failed: Directory not empty (39)
# idevs: delete_file: rmdir [/ubuntu/sys] (in ibackup) failed: Directory not empty (39)
# idevs error: some files could not be transferred (code 23) at main.c(3087) [sender=1.0.2.8]
# my $individual_errorfileContents = "idevs: delete_file: rmdir [/ubuntu/home] (in ibackup) failed: Directory not empty (39)";
# @ErrorArgumentsNoRetry = sort {$a cmp $b} @ErrorArgumentsNoRetry;
# foreach my $fileName (@ErrorArgumentsNoRetry) {
	# print "$fileName\n";
# }	
# exit;
init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub init {
	Common::loadAppPath();
	Common::loadServicePath();
	if(Common::loadUsername()){
		Common::loadUserConfiguration();
	}
	Common::displayHeader();
	#%desc	= %{$Help{'description'}};
	my ($continueMenu, $continueSearchMenu) = ('y') x 2;
	while(1) {
		displayHelpHeadings($Help{'heading'});
		Common::display(["\n", '__note_please_press_ctrlc_exit']);
		my $userMainChoice= Common::getUserMenuChoice(scalar $Help{'heading'}->Keys);
		$userMainChoice = $userMainChoice-1;
		if ($userMainChoice >= 0) {
			my $mainHeading = $Help{'heading'}[1][$userMainChoice];
			if (defined($Help{'sub_heading'}{$mainHeading})) {
				if (defined($Help{'description'}->FETCH($mainHeading))) {
					Common::displayTitlewithUnderline($Help{'heading'}->FETCH($mainHeading));
					wrapTextAndDisplay($Help{'description'}->FETCH($mainHeading));
					wrapTextAndDisplay($Help{'description'}->FETCH($mainHeading."_".$AppConfig::appType)) if($Help{'description'}->FETCH($mainHeading."_".$AppConfig::appType));
				}

				while(1) {
					displayHelpHeadings($Help{'sub_heading'}{$mainHeading}, 'Sub menus for "'.$Help{'heading'}->FETCH($mainHeading).'"');
					Common::display(["\n",'enter_the_serial_no_press_keys_to_go_back_or_exit']);
					my $userChoice = Common::getAndValidate('enter_your_choice',"help_menu",1,1,scalar $Help{'sub_heading'}{$mainHeading}->Keys);
					last if($userChoice eq 'p' or $userChoice eq 'P');

					$userChoice = $userChoice-1;
					my $sub = $Help{'sub_heading'}{$Help{'heading'}[1][$userMainChoice]};
					if ($Help{'description'}->FETCH($sub->[1][$userChoice])) {
						Common::displayTitlewithUnderline($Help{'heading'}->FETCH($mainHeading)." -> ".$sub->FETCH($sub->[1][$userChoice]));
						wrapTextAndDisplay($Help{'description'}->FETCH($sub->[1][$userChoice]));
						wrapTextAndDisplay($Help{'description'}->FETCH($sub->[1][$userChoice]."_".$AppConfig::appType)) if($Help{'description'}->FETCH($sub->[1][$userChoice]."_".$AppConfig::appType));

						Common::display(["\n",'press_keys_to_go_back_or_exit']);
						my $userChoice = Common::getAndValidate('enter_your_choice',"help_menu",1,1);
						next if($userChoice eq 'p' or $userChoice eq 'P');						
					}
				}
			} elsif (defined($Help{'description'}->FETCH($mainHeading))) {
				Common::displayTitlewithUnderline($Help{'heading'}->FETCH($mainHeading));
				wrapTextAndDisplay($Help{'description'}->FETCH($mainHeading));
				wrapTextAndDisplay($Help{'description'}->FETCH($mainHeading."_".$AppConfig::appType)) if($Help{'description'}->FETCH($mainHeading."_".$AppConfig::appType));

				my $userChoice = displayGoBackOrExitOption();
				next if($userChoice eq 'p' or $userChoice eq 'P');
			}
			elsif ($mainHeading =~ /search/i) {
				my $keyword = Common::getAndValidate(['enter_keyword',': '], 'non_empty', 1);
				my $result = searchByKeyword($keyword);
				if ($result->Length) {
					my $userChoice = displaySearchResult($result, $keyword);
					next if($userChoice eq 'p' or $userChoice eq 'P');
				} else {
					Common::display(["\n",'no_help_found']);
				}
			} else {
				Common::display(['no_help_found']);
			}
		}
	}
}

#*****************************************************************************************************
# Subroutine			: displayHelpHeadings
# Objective				: List the help heading/sub-headings in tabular format.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub displayHelpHeadings {
	my $title = 'Main menus';
	$title = $_[1] if(defined($_[1]));

	my $length = length($title)+2;
	my @columnNames = (['S.No.', $title], [8, $length]);
	my $tableHeader = getTableHeader(@columnNames);
	my ($displayCount, $spaceIndex, $tableContent) = (1, 0, '');

#	print Dumper(\$_[0]);
	foreach($_[0]->Keys) {
		$tableContent 	.= qq(\n) if($_[0]->FETCH($_) =~ /search/i);

		$tableContent 	.= $displayCount;
		# (total_space - used_space by data) will be used to keep separation between 2 data
		$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($displayCount));
		$spaceIndex++;

		$tableContent 	.= $_[0]->FETCH($_);
		#$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($_[0]->FETCH($_)));
		$tableContent 	.= qq(\n);
		$spaceIndex = 0;
		$displayCount++;
	}

	if($tableContent ne '') {
		Common::display([$tableHeader . $tableContent], 0);
	} else {
		Common::retreat(["\n", 'no_help_found', ' ', 'please_try_again', '.']);
	}
}

#*****************************************************************************************************
# Subroutine			: displaySearchResult
# Objective				: List the result in tabular format.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub displaySearchResult {
	my @columnNames = (['S.No.', 'Search Result'], [8, 15]);
	my $tableHeader = getTableHeader(@columnNames);
	my ($displayCount, $spaceIndex, $tableContent) = (1, 0, '');
	my $userChoice;

	my $appType = ($AppConfig::appType eq 'IDrive')?'IBackup':'IDrive';
	foreach($_[0]->Keys) {
		$_[0]->Delete($_) if($_ =~ /$appType/); #Removing irrelevant content based on app type
	}

	if (scalar($_[0]->Keys)) {
		foreach($_[0]->Keys) {
			Common::display($tableHeader) if($displayCount == 1);
			$tableContent 	.= $displayCount;
			# (total_space - used_space by data) will be used to keep separation between 2 data
			$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($displayCount));
			$spaceIndex++;

			$tableContent 	.= $_[0]->FETCH($_);
			#$tableContent 	.= qq( ) x ($columnNames[1]->[$spaceIndex] - length($_[0]->FETCH($_)));
			$tableContent 	.= qq(\n);
			$spaceIndex = 0;
			if ($displayCount%20 == 0 and $displayCount < scalar($_[0]->Keys)) {
				Common::display($tableContent);
				Common::display(["\n",'press_keys_load_more_or_to_go_back_or_exit']);
				$userChoice = Common::getAndValidate('enter_your_choice',"help_search_menu",1,1,$displayCount);
				if($userChoice eq 'm' or $userChoice eq 'M') {
					$displayCount++;
					$userChoice = undef;
					next;
				} elsif ($userChoice eq 'p' or $userChoice eq 'P') {
					return $userChoice;
				}
				goto RESULT;
			}
			$displayCount++;
		}

		if(!defined($userChoice)) {
			if($tableContent ne '') {
				Common::display($tableContent);
				Common::display(["\n",'enter_the_serial_no_press_keys_to_go_back_or_exit']);
				$userChoice = Common::getAndValidate('enter_your_choice',"help_menu",1,1,scalar $_[0]->Keys);				
			} else {
				Common::display(["\n", 'no_help_found', ' ', 'please_try_again', '.']);
				Common::display(["\n",'press_keys_to_go_back_or_exit']);
				$userChoice = Common::getAndValidate('enter_your_choice',"help_menu",1,1);
			}

			if ($userChoice eq 'p' or $userChoice eq 'P') {
				return $userChoice;
			}
		}
RESULT:
		$userChoice = $userChoice-1;
		if ( $_[0]->[1][$userChoice] =~ /$AppConfig::appType/ and $Help{'description'}->FETCH($_[0]->[1][$userChoice])) {
			my $key 	= $_[0]->[1][$userChoice];
			my $mainKey = $_[0]->[1][$userChoice];
			$appType = "_".$AppConfig::appType;
			$mainKey =~ s/$appType//;
			#print "mainKey:$mainKey#key:$key#\n\n";
			findHeadingsAndDisplay($mainKey);
			wrapTextAndDisplay($Help{'description'}->FETCH($mainKey));
			wrapTextAndDisplay($Help{'description'}->FETCH($key));
		}
		elsif ($Help{'description'}->FETCH($_[0]->[1][$userChoice])) {
			findHeadingsAndDisplay($_[0]->[1][$userChoice]);
			#print "Key:".($_[0]->[1][$userChoice])."#\n\n";
			wrapTextAndDisplay($Help{'description'}->FETCH($_[0]->[1][$userChoice]));
			wrapTextAndDisplay($Help{'description'}->FETCH($_[0]->[1][$userChoice]."_".$AppConfig::appType)) if($Help{'description'}->FETCH($_[0]->[1][$userChoice]."_".$AppConfig::appType));
		} else {
			Common::display(["\n", 'no_help_found', ' ', 'please_try_again', '.']);
		}

		Common::display(["\n",'press_keys_to_go_back_or_exit']);
		$userChoice = Common::getAndValidate('enter_your_choice',"help_menu",1,1);
		if ($userChoice eq 'p' or $userChoice eq 'P') {
			displaySearchResult($_[0]);
		}
	} else {
		Common::display(["\n", 'no_help_found', ' ', 'please_try_again', '.']);
	}
}

#*****************************************************************************************************
# Subroutine			: getTableHeader
# Objective				: To get the table header display with column name.
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub getTableHeader {
	#my $logTableHeader 	= qq(=) x (eval(join '+', @{$_[1]})) . qq(\n);
	my $logTableHeader 	 = qq(\n);
	for(my $contentIndex = 0; ($contentIndex <= scalar(@{$_[0]}) - 1); $contentIndex++) {
		#(total_space - used_space by data) will be used to keep separation between 2 data.
		$logTableHeader .= $_[0]->[$contentIndex] . qq( ) x ($_[1]->[$contentIndex] - length($_[0]->[$contentIndex]));
	}

	$logTableHeader 	.= qq(\n) . qq(=) x (eval(join '+', @{$_[1]})) . qq(\n);
	return $logTableHeader;
}

#*****************************************************************************************************
# Subroutine			: searchByKeyword
# Objective				: Return the help content by keyword
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub searchByKeyword {
	my $keyword = $_[0];
	my $desc 	= $Help{'description'};
	my $descRow;
	$keyword =~ s/(["'*+\$^.])/\\$1/g;
	my $result = Tie::IxHash->new();
	#my $skipAppType = ($AppConfig::appType eq 'IDrive')?'IBackup':'IDrive';
	foreach($desc->Keys) {
		#next if($_ =~ $skipAppType);
		$descRow = $desc->FETCH($_);
		my $tempDesc = $desc->FETCH($_);
		$tempDesc =~ s/\n+/ /g;
		$tempDesc =~ s/(["'*+\$^])/\\$1/g;

		if ($tempDesc =~ /$keyword/i) {
			my $trimmedResult	 = trimResult($descRow, $keyword);
			$result->Push($_ => $trimmedResult);
		}
	}
	return $result;
}

#*****************************************************************************************************
# Subroutine			: trimResult
# Objective				: Return the partial line of the result matched
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub trimResult {
	my $keyword	 = lc($_[1]);
	my $trimmedResult = $_[0];
	#$trimmedResult =~ s/\n+/ /g;
	$trimmedResult =~ s/(\$)/\$/g;

	my @result = split(/\n|\\n/,$trimmedResult);
	#print Dumper(\@result);
	#print "\n\n ========================= \n\n";
	foreach my $line (@result){
		if ($line =~ /$keyword/i) {
			$trimmedResult = $line;
			last;
		}
	}
	return $trimmedResult;
}

#*****************************************************************************************************
# Subroutine			: findHeadingsAndDisplay
# Objective				: 
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub findHeadingsAndDisplay {
	my $selectedKey = $_[0];
	my ($mainTitle, $subTitle);

	if($selectedKey =~ /$AppConfig::appType$/) {
		$selectedKey =~ s/_$AppConfig::appType$//;
	}

	if (defined($Help{'heading'}->FETCH($selectedKey))) {
		$mainTitle = $Help{'heading'}->FETCH($selectedKey);
	} else {
		foreach (keys %{$Help{'sub_heading'}}) {
			if(defined($Help{'sub_heading'}{$_}->FETCH($selectedKey))) {
				#print $Help{'sub_heading'}{$_}->FETCH($selectedKey)."\n";
				$subTitle 	= $Help{'sub_heading'}{$_}->FETCH($selectedKey);
				$mainTitle	= $Help{'heading'}->FETCH($_);
				last;
			}
		}
	}

	my $header = $mainTitle;
	$header .= " -> ".$subTitle if(defined($subTitle));
	Common::displayTitlewithUnderline($header);
}

#*****************************************************************************************************
# Subroutine			: displayGoBackOrExitOption
# Objective				: Display the option and Go Back Or Exit
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub displayGoBackOrExitOption {
	Common::display(["\n",'press_keys_to_go_back_or_exit']);
	my $continueMenu = Common::getAndValidate(['enter_your_choice'], "PE_choice", 1);
	exit if(lc($continueMenu) eq 'e');
	return $continueMenu;
}

#*****************************************************************************************************
# Subroutine			: wrapTextAndDisplay
# Objective				: This subroutine to wrap the text based on window-size and display
# Added By				: Senthil Pandian
#****************************************************************************************************/
sub wrapTextAndDisplay {
	my $text = $_[0];
	return $text if($text eq '');
	
	my $noOfColumn = `tput cols`;
	chomp($noOfColumn);

	#my $tempWrappedText = '';
	my $wrappedText = $text."\n";
	if (length($text) > $noOfColumn) {
		my @result = split(/\n|\\n/,$text);
		$wrappedText = '';

		foreach my $line (@result) {
			if (length($line) <= $noOfColumn) {
				$wrappedText .= $line."\n";
				next;
			}

			my $offset = 0;
			while(1) {
				my $partial = substr($line,$offset,$noOfColumn-1);

				if (length($partial) < $noOfColumn-1) {
					$wrappedText .= $partial;
					last;
				}
				else {
					my $end = rindex($partial," ");
					my $subStr = substr($partial,0,$end);
					$wrappedText = $wrappedText.substr($partial,0,$end)."\n";
					$offset = $offset+$end+1;
				}
			}

			#$tempWrappedText = "";
			$wrappedText .= "\n";
		}
	}

	Common::display($wrappedText,0);
	return $wrappedText;
}