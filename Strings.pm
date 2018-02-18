package Locale;
use strict;
use warnings;

#-------------------------------------------------------------------------------
# Locale Strings in EN
#
# Created By : Yogesh Kumar
# Reviewed By: Deepak Chaurasia
#-------------------------------------------------------------------------------

our %strings = (
# A
	'new_update_is_available' => "A new update is available, run Check_For_Update.pl to update to latest package",
	'already_exists' => "Already exists.",
	'account_with_encryption' => "account with encryption!",

# B

# C
	'cannot_open_directory' => "Cannot open directory",
	'checking_for_dependencies' => "Checking for package dependencies...",
	'dependency_curl...' => 'curl... ',
	'create_new_backup_location' => "Create new Backup Location",
	'confirm_your_encryption_key' => "Confirm your encryption key",

# D
	'developed_by' => "Developed By:",
	'please_provide_your_details_below' => "Dear User, Please provide your details below",
	'do_you_want_edit_this_y_or_n_?' => "Do you want to edit this(y/n)?",
	'default_encryption_key' => "Default encryption key",

# E
	'enter_your_service_path' => "Enter your service path [This location will be used to maintain the temporary data used by your scripts] [Optional]: ",
	'enter_your' => "Enter your",
	'enter_your_restore_location_optional' => "Enter your Restore Location [Optional]",
	'enter_your_choice' => "Enter your choice: ",
	'enter_your_backup_location_optional' => "Enter your Backup Location [Optional]",
	'encryption_key_and_confirm_encryption_key_must_be_the_same' => "Encryption key and confirm encryption key must be the same",
	'enter_the_encryption_key' => "Enter the encryption key",
	'enter_your_backup_location_optional' => "Enter your Backup Location [Optional]",

# F
	'failed_to_create_utf8_file' => "Failed to create utf8 file",
	'failed' => "Failed!!!",
	'found' => 'found.',

# I
	'idrive_maintainer' => "IDrive Inc.",
	'user_config_backuplocation_not_found' => "Invalid Backup Location\nPlease edit your account details using Account_Setting.pl",
	'user_config_backuptype_not_found' => "Invalid Backup Type\nPlease edit your account details using Account_Setting.pl",
	'user_config_bwthrottle_not_found' => "Invalid Bandwidth Throttle value\nPlease edit your account details using Account_Setting.pl",
	'user_config_encryptiontype_not_found' => "Invalid Encryption Type\nPlease re-login to your account using Login.pl",
	'invalid_option' => "Invalid Option",
	'user_config_restorefrom_not_found' => "Invalid Restore From\nPlease edit your account details using Account_Setting.pl",
	'user_config_restorelocation_not_found' => "Invalid Restore Location\nPlease edit your account details using Account_Setting.pl",
	'user_config_retainlogs_not_found' => "Invalid Retain Logs Value\nPlease edit your account details using Account_Setting.pl",
	'invalid_service_directory' => "Invalid service directory\nPlease reconfigure your account using Account_Setting.pl and try again!",
	'user_config_dedup_not_found' => "Invalid User Details\nPlease reconfigure your account using Account_Setting.pl",
	'user_config_username_not_found' => "Invalid Username\nPlease re-login to your account using Login.pl",
# J
	'job_terminated_successfully' => 'job terminated successfully',
# L
	'logged_in_user' => "Logged in user:",

# M
	'multiple_backup_locations_are_configured' => "Multiple Backup Locations are configured with this account",
	'manual_backup' => "Manual backup",
	'manual_restore' => "Manual restore",

# N
	'no_backup_or_restore_is_running' => "No Backup/Restore Job is running",
	'no_logged_in_user' => "No logged in user",
	'no_such_directory_try_again' => "No such directory. Please try again.",
	'not_found' => 'Not found.',
	'note_backup_to_device_name_should_contain_only_letters_numbers_space_&_characters' => "[Note: Backup location should contain only letters, numbers, space and characters(.-_)]",

#O
	'operation_not_permitted' => "Operation not permitted",

# P
	'login_&_try_again' => "Please Login-in to your Account using Login.pl and try again!",
	'ibackup_maintainer' => "Pro Softnet Corporation.",
	'permission_denied' => "Permission denied.",
	'password' => "password: ",
	'please_configure_your' => "Please configure your",
	'private_encryption_key' => "Private encryption key",

# S
	'select_the_job_from_the_above_list' => "Select the job from the above list: ",
	'stop_manual_backup' => "Stop Manual Backup",
	'stop_manual_restore' => "Stop Manual Restore",
	'stop_scheduled_backup' => "Stop Scheduled Backup",
	'stop_scheduled_restore' => "Stop Scheduled Restore",
	'storage_used' => "Storage Used:",
	'select_an_option' => "Select an option",
	'select_from_existing_backup_locations' => "Select from existing Backup Locations",
	'setting_up_your_default_manual_backup_file_as' => "Setting up your Default Manual Backupset File as",
	'setting_up_your_default_scheduled_backup_file_as' => "Setting up your Default Schedule Backupset File as",
	'setting_up_your_default_manual_restore_file_as' => "Setting up your Default Manual Restoreset File as",
	'setting_up_your_default_scheduled_restore_file_as' => "Setting up your Default Schedule Restoreset File as",
	'setting_up_your_default_full_exclude_file_as' => "Setting up your Default Full Exclude list File as",
	'setting_up_your_default_partial_exclude_file_as' => "Setting up your Default Partial Exclude list File as",
	'setting_up_your_default_regex_exclude_file_as' => "Setting up your Default Regex Exclude list File as",
	'set_your_encryption_key' => "Set your encryption key",
	'scheduled_backup' => "Scheduled backup",
	'scheduled_restore' => "Scheduled restore",

# T
	'this_job_might_be_stopped_already' => "This job might be stopped already",

# U
	'unable_to_cache_the_quota' => "Unable to cache the quota",
	'unable_to_execute_evs_binary' => "Unable to execute EVS binary\nPlease configure or re-configure your account using Account_Setting.pl",
	'unable_to_find_or_execute_evs_binary' => "Unable to find or execute EVS binary\nPlease configure or re-configure your account using Account_Setting.pl",
	'unable_to_retrieve_the_quota' => "Unable to retrieve the quota",
	'dependency_unzip...' => 'unzip... ',
	'username' => 'username: ',
	'undefined_job_name' => 'Undefined job name',

# W

# Y
	'you_can_stop_one_job_at_a_time' => "You can stop only one job at a time",
	'your_service_directory_is' => "Your service directory is ",
	'your_backup_to_device_name_is' => 'Your Backup To Device Name is',
	'your_restore_from_device_is_set_to' => 'Your Restore From Device is set to',
	'your_restore_location_is_set_to' => "Your Restore Location is set to",
	'your_account_details_are' => "Your account details are"
);
1;
