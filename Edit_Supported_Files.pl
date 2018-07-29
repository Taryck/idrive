#!/usr/bin/perl
#*****************************************************************************************************
# This script is used to edit the supported files like Backup/Restore set files for both normal and scheduled
# 							Created By: Sabin Cheruvattil													
#****************************************************************************************************/
use strict;
use warnings;

if(__FILE__ =~ /\//) { use lib substr(__FILE__, 0, rindex(__FILE__, '/')) ;	} else { use lib '.' ; }

use Helpers;
use Strings;
use Configuration;
use File::Basename;


init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
# Modified By			: Anil Kumar [04/05/2018]
#****************************************************************************************************/
sub init {
	system('clear');
	Helpers::loadAppPath();
	Helpers::loadServicePath() 			or Helpers::retreat('invalid_service_directory');
	Helpers::loadUsername()				or Helpers::retreat('login_&_try_again');
	Helpers::loadUserConfiguration()	or Helpers::retreat('your_account_not_configured_properly');
	Helpers::isLoggedin()            	or Helpers::retreat('login_&_try_again');
	
	Helpers::displayHeader();
	
	my ($continueMenu, $menuUserChoice, $editFilePath, $maxMenuChoice) = ('y', 0, '', 0);
	my %menuToPathMap;
	while($continueMenu eq 'y') {
		$maxMenuChoice = displayMenu(\%menuToPathMap);
		
		Helpers::display(["\n", '__note_please_press_ctrlc_exit']);
		$menuUserChoice = Helpers::getUserMenuChoice($maxMenuChoice);
		$editFilePath 	= Helpers::getUserFilePath($menuToPathMap{$menuUserChoice});
		($editFilePath ne '')? Helpers::openEditor('edit', $editFilePath) : Helpers::display(['unable_to_open', '. ', 'invalid_file_path', ' ', '["', $editFilePath, '"]']);
		Helpers::display(['do_you_want_to_edit_any_other_files_yn']);
		$continueMenu = Helpers::getAndValidate(['enter_your_choice'], "YN_choice", 1);
	}
}

#*****************************************************************************************************
# Subroutine			: displayMenu
# Objective				: Helps to display the menu
# Added By				: Sabin Cheruvattil
#****************************************************************************************************/
sub displayMenu {
	my ($opIndex, $pathIndex) = (1, 1);
	my @fileMenuOptions;
	Helpers::display(['menu_options_title', ':', "\n"]);
	
	foreach my $mainOperation (keys %Configuration::editFileOptions) {
		Helpers::display([$mainOperation . '_title', ':']);
		@fileMenuOptions = sort keys %{$Configuration::editFileOptions{$mainOperation}};
		Helpers::display([map{qq(\t) . $opIndex++ . ") ", $Locale::strings{'edit_' . $_ . '_file'} . "\n"} @fileMenuOptions], 0);
		%{$_[0]} = (%{$_[0]}, map{$pathIndex++ => $Configuration::editFileOptions{$mainOperation}{$_}} @fileMenuOptions);
	}
	
	return $opIndex - 1;
}