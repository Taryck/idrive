								IDrive for Linux
								=================

I. INTRODUCTION
================
Backup and protect your Linux machine data using scripts bundle provided by IDrive. Protect files during transfer and storage, using 256-bit AES encryption with an optional private key.

II. SYSTEM/SOFTWARE REQUIREMENTS
=================================
Linux(CentOS/Ubuntu/Fedora/OpenSUSE/FreeBSD/Linux Mint) - 32-bit/64-bit
Perl v5.8 or later

III. SCRIPT DOWNLOAD
=====================
STEP 1: Download the script bundle from "https://www.idrivedownloads.com/downloads/linux/download-for-linux/IDriveForLinux.zip".
		Downloaded script bundle needs to be extracted into a particular folder on your Linux machine.
		After extraction of the zip archive, you will find scripts folder in it. Below files will be present in the scripts folder:

		Executable Script files:
		1. account_setting.pl
		2. archive_cleanup.pl
		3. Backup_Script.pl
		4. check_for_update.pl
		5. edit_supported_files.pl
		6. express_backup.pl
		7. help.pl
		8. job_termination.pl
		9. login.pl
		10. logout.pl
		11. logs.pl
		12. Restore_Script.pl
		13. restore_version.pl
		14. scheduler.pl
		15. send_error_report.pl
		16. speed_analysis.pl
		17. Status_Retrieval_Script.pl
		18. Uninstall_Script.pl

		Other Supported files:
		1. ca-certificates.crt
		2. Constants.pm
		3. cron.pl
		4. dashboard.pl
		5. Header.pl
		6. Operations.pl
		7. readme.txt
		8. utility.pl

		Other Supported Folders:
		1. Idrivelib - Contains cron startup routine files for all supported platforms and required perl modules.
		
		Other Supported files/folders are used internally by executable script files and users must not try to execute these scripts for any reason.

STEP 2: Provide appropriate permissions (executable permission) to the scripts.
		Example:  chmod a+x *.pl

IV. SETUP YOUR IDRIVE ACCOUNT
==============================
STEP 1: You need to have an IDrive account to use the script bundle to backup your files. In case you do not have an account,
		please sign up and create an account at https://www.idrive.com/idrive/signup .

STEP 2: To set up IDrive script bundle locally with your IDrive account, run the below command and follow the instructions.
		$./account_setting.pl
		Note: Setting up the script bundle for the first time will ask user to enter the service path. This path will contain user specific data required to perform operations via script bundle.
		      For some IDrive accounts, while configuring account, 'Create new Backup Location'/'Select from existing Backup Locations' options will appear and Mirror/relative backup type option will not appear.

V. WORKING WITH THE SCRIPTS
============================
		Using IDrive scripts, you can:

		- Perform backup/express backup/restore/archive cleanup operations
		- View progress for backup/express backup/restore/archive cleanup 
		- Schedule backup/express backup/restore/archive cleanup job
		- View logs files and much more.

STEP 1: Login to your IDrive account
		If you are not logged in to your IDrive account while setting up your script bundle, run the below command to login.
		$./login.pl

		Note: Login script is a mandatory script to be executed before performing any operation. This script will authenticate your IDrive account details and will create a secure session for your backups.

STEP 2: Edit your backup-set/express backup-set/restore-set, and exclude files
		Before starting any backup/express backup/restore operation, the user must add the list of files/folders required for each operation in the backup/express backup/restore set file.

		To update these details in the backup/express backup/restore set file, you must execute the below command:
		$./edit_supported_files.pl

		The menu option will be displayed. Select option 1 to edit the backup set file. Respective file will open in selected editor to edit. Add the files/folders that needs to be backed up.
		Using same script you can update backup set, express backup set, restore set and exclude files by selecting the desired option.

		Exclude Files/Folder from your backup set
		=========================================
		By using the Exclude option of edit supported file script, you can exclude files/ folders from being backed up to your IDrive account.

		1. Full Path Exclude
		2. Partial Path Exclude
		3. Regex Exclude

		Full Path Exclude
		=================
		To exclude files/folders with full path,

		1. Run 'edit_supported_files.pl' script and select option 'Edit Your Full Path Exclude List'. The 'FullExcludeList.txt' file will open in selected editor.
		2. Add full path of the files/folders that you wish to exclude.
		3. Enter each item in a new line.
		4. Save and exit.

		Example:
		Your Backupset contains /home/Documents and if you want to exclude /home/Documents/temp, enter the folder path ie: ‘/home/Documents/temp’ in FullExcludeList file.

		Partial Path Exclude
		====================
		To exclude files/folders with partial path,

		1. Run 'edit_supported_files.pl' script and select option 'Edit Your Partial Path Exclude List'. The 'PartialExcludeList.txt' file will open in selected editor.
		2. Add partial name of the files/folders that you wish to exclude.
		3. Enter each item in a new line.
		4. Save and exit.

		Example:
		Your Backupset contains /home/Documents and if you want to exclude all the pst files from this folder like /home/Documents/designtutorials.pst, /home/Documents/new.pst, /home/Documents/James/tutorials.pst etc, then enter ‘pst’ in PartialExcludeList file.

		Regex Exclude
		=============
		To exclude files/folders based on regex pattern,

		1. Run 'edit_supported_files.pl' script and select option 'Edit Your Regex Exclude List'. The 'RegexExcludeList.txt' file will open in selected editor.
		2. Add the regex pattern of the files/folders that you wish to exclude.
		3. Enter each item in a new line.
		4. Save and exit.

		Example:
		Your Backupset contains /home/Folder01 , /home/Folder02, /home/FolderA, /home/FolderB. If you want to exclude all folders/files that contains numeric values in name ie: /home/Folder01, /home/Folder02 etc, then enter ‘Folder\d+’ in RegexExcludeList file.

STEP 3: Immediate/Manual backup
		You can perform immediate/manual backup using the below command:
		$./Backup_Script.pl

		When you run your backup script, it will reconfirm your backup location and allow you to change it. You can now view the graphical progress bar for your data getting backed up.
		If you want your script not to ask for backup location and not to display progress bar then you can always use "--silent" flag with this command.

		Note: For some IDrive accounts this script will not provide an option to change 'Backup location'.


STEP 4: Immediate/Manual express backup
		You can perform immediate/manual express backup using the below command:
		$./express_backup.pl

		Using this script, you can backup your Linux machine data to the express device shipped to you. Once the data is backed up, you can ship this express device back to us and within a week your data will be available in your IDrive account.
		For more details on express, visit https://www.idrive.com/linux-express-backup

STEP 5:	Immediate/Manual restore
		You can perform immediate/manual restore using the below command:
		$./Restore_Script.pl

		When you run your restore script, it will reconfirm your restore and restore from location and will allow you to change it if required.
		You can now view the graphical progress bar for your data getting restored.
		If you want your script not to ask for restore location, restore from location and not to display progress bar then you can always use "--silent" flag with this command.

		Note: For some IDrive accounts, user will not be able to edit 'Restore From' manually and have to select 'Restore From' location from the list of existing locations.

STEP 6:	Schedule backup/express backup/archive cleanup job
		Run the below command to manage your schedule backup/express backup/archive cleanup job:
		$./scheduler.pl

		Select the desired menu option to create, edit, view or delete your schedule backup / express backup / archive cleanup job and follow the instructions.
		In case you want your schedule job to stop automatically at a scheduled time then set the cut-off time as well, while following the instructions.

STEP 7: View progress of scheduled backup/express backup/archive cleanup
		To view the progress of scheduled backup or express backup operation, run the below command:
		$./Status_Retrieval_Script.pl

STEP 8: View/restore previous versions of a file
		You can view the list of previous versions of any file and select any version that you want to restore. To retrieve a file with earlier versions, run the below command:
		$./restore_version.pl

		Note: For some IDrive accounts, user will not be able to edit 'Restore From' location manually and have to select 'Restore From' location from the list of existing locations.

STEP 9:	Stop ongoing backup/express backup/restore/archive operations
		To stop an ongoing backup or express backup or restore operation, run the below command:
		$./job_termination.pl

STEP 10: View/Delete operation logs
		You can view or delete the logs for backup, express backup, restore and archive cleanup operations using the below command:
		$./logs.pl

STEP 11: Archive cleanup
		Archive Cleanup compares the files of your local storage, selected for backup, with the files in your IDrive online backup account. It then deletes the files present in your account but not on your local machine.
		This feature thus helps you to free up space in your online backup account.

		To perform archive cleanup run below command:
		$./archive_cleanup.pl

		When you run the script to perform archive cleanup, you can enter a percentage of the total no. of files to be considered for deletion. This percentage based control helps to avoid large-scale deletion of files in your account.

STEP 12: Send error report
		You can send error report to IDrive support by running the below command:
		$./send_error_report.pl

STEP 13: Logout from your IDrive account
		To end the logged in session for your IDrive account, run the below command:
		$./logout.pl

		You must logout (optional) from the account to avoid any unauthorized access to your IDrive account. After logout, you needs to login again to perform most of the operations.
		Note: Your scheduled backup / scheduled express backup / periodic cleanup jobs will run even after you logout.

STEP 14: Help
		To view help page content by running the below command and follow the instructions:
		$./help.pl

VI. UPDATING YOUR SCRIPT BUNDLE
================================
		Every script when gets executed displays a header which provide details of logged in IDrive account. Same header also displays information on any newly available script bundle.
		If Software Update Notification is enabled, you will see the message "A new update is available. Run check_for_update.pl to update to latest package", indicating a new improved version of script bundle has been released.

		To update to most recent available script bundle please perform the below command and follow the instructions.
		$./check_for_update.pl


VII. EDIT USER DETAILS
======================
		In case you want to reconfigure your IDrive account locally due to any reason or want to edit user details locally for your configured IDrive account then please perform the below command.
		$./account_setting.pl

		Only if your account is already configured in current machine you will find the menu which will allow you to reconfigure your IDrive account locally or will allow you to edit the user details locally for your IDrive account. You can configure the following settings:

		Backup Settings:
		================
		- Backup Location: Update the backup location using this option.
		- Backup Type: Change the backup type from mirror to relative and vice verse using this option.
		- Bandwidth throttle(%): Set the Internet bandwidth to be used by the scripts for backups using this option.
		- Failed files(%): By default failed files % to notify backup as 'Failure' is set to 5%. If the total files failed for backup is more than 5%, then backup will be notified as failure. Change the default setting using this option.
		- Missing files(%): By default missing files % to notify backup as 'Failure' is set to 5%. If the total files missing for backup is more than 5%, then backup will be notified as failure. Change the default setting using this option.

		General Settings:
		=================
		- Desktop access: Enable this setting to access your computer via dashboard.
		- E-mail address: Use this option to change the email address provided at the time of account setup locally.
		- Ignore file/folder level permission error: If your backup set contains files/folders that have insufficient access rights, IDrive will not backup those files/folders. Hence in such a case, by default, your backup will be considered as 'Failure'. To ignore file/folder level access rights/permission errors, enable this setting.
		- Proxy details: If you are behind a proxy address, you should update the proxy settings using this option.
		- Show hidden files/folders: Disable this setting to skip hidden files/folders from backup.
		- Software Update Notification: Enable this setting to get a notification for available updates in script header.
		- Upload multiple file chunks simultaneously: Enable this option to upload multiple file chunks simultaneously to improve overall data transfer speed.
		- Service path: Update the service path used by IDrive scripts using this option.

		Restore Settings:
		=================
		- Restore from location: Use this option to change the location from where backups will be restored.
		- Restore location: Use this option to change the restore location.
		- Restore Location Prompt: Enable this setting if you wish to receive notification about the restore location before starting restore.

		Services:
		=========
		- Start/Restart dashboard service: Use this option to start or restart dashboard service. This service must be up and running for your machine to be remotely managed from the Dashboard.
		- Start/Restart IDrive cron service: Use this option to start or restart IDrive cron service. This service is responsible for all the schedule jobs to work as expected.


		Select the desired option and follow the instructions.

		Note: For some users, while re-configuring or editing account, 'Backup Type' will not be displayed and also while editing 'Restore From' location, list of devices will appear.

VIII. UNINSTALLING YOUR SCRIPT BUNDLE
====================================
		Uninstalling the script package from your system will leave the files/folders of your system liable to digital disasters.

		To uninstall the script bundle, run the below command and follow the instructions.
		$./Uninstall_Script.pl

		This script will automatically remove all IDrive package files and other dependency files. It will also stop all IDrive specific services and cleanup the scheduled backup/express backup/restore/periodic cleanup jobs if any.

IX. RELEASES
================
	Build 1.0
	==============================================================================================================
		N/A

	Build 1.1
	==============================================================================================================
		1.	Fixed the backup/restore issue for password having special characters.
		2.	Fixed the backup/restore issue for encryption key having special characters.
		3.	Fixed the backup/restore issue for user name having special characters.
		4.	Fixed the backup/restore issue for backup/restore location name having special characters.
		5.	Moved LOGS folder inside user name folder for better management.
		6.	Avoided unnecessary calls to server at the time of backup as well as restore.
			Like create directory call, get server call and config account call. As before these calls
			was taking place with each backup and restore operation.
		7.	New file named header.pl has been created. It contains all common functionalities.

	Build 1.2
	==============================================================================================================
		1.	Avoided error in the log when email is not specified in CONFIGURATION_FILE after backup
			operation.
		2.	A new BACKUPLOCATION field has been introduced in CONFIGURATION_FILE. All the backed up
			files/folders will be stored in the server under this name.
		3.	A new RESTOREFROM field has been introduced in CONFIGURATION_FILE.  Any files/folders
			that exist under this name can be restored from server to local machine.

	Build 1.3
	==============================================================================================================
		1.	A new field RETAINLOGS has been introduced in CONFIGURATION_FILE. This field is used to
			determine if all the logs in LOGS folder have to be maintained or not.
		2.	Fixed Retry attempt issue if backup/restore is interrupted for certain reasons.

	Build 1.4
	==============================================================================================================
		1. 	A new field PROXY has been introduced in CONFIGURATION_FILE. This field if enabled will
			perform operations such as Backup/Restore via specified Proxy IP address.
		2. 	A new file login.pl has been introduced which reads required parameters from CONFIGURATION_FILE
			and validates IDrive credentials and create a logged in session.
		3. 	A new file logout.pl has been introduced which allow to log out from logged in session for IDrive account.
		      It also clears PASSWORD and PVTKEY fields in configuration file.

	Build 1.5
	==============================================================================================================
		1. 	A new field BWTHROTTLE has been introduced in CONFIGURATION_FILE. To restrict the bandwidth usage
		   for backup operation.
		2. 	Changes has been made to make script work on perl ver 5.8 as well.

	Build 1.6
	==============================================================================================================
		1.	Schedule backup issue has been fixed in user logged out mode.

	Build 1.7
	==============================================================================================================
		1. 	Support for multiple email notification on Schedule Backup has been implemented.
		2.	ENC TYPE has been removed from CONFIGURATION File.
		3. 	Schedule for Restore job has been implemented.
		4. 	Fixed login and logout issue.

	Build 1.8
	==============================================================================================================
		1. 	Support for multiple email notification on Schedule Restore has been implemented.
		2. 	Scheduler Script is enhanced to perform schedule Restore job.
		3.	Schedule restore is enhanced to run even after logout as well.
		4. 	Status retrieval support for manual as well as scheduled restore job has been implemented.
		5. 	Job termination script is enhanced to cancel ongoing backup or restore or both the job.
		6.	Fixed issue of deleting backup or restore set file.
		7. 	Showing of Exclude items on Log is implemented.
		8.	Login is enhanced to display certain error messages.

	Build 1.9
	==============================================================================================================
		1.	Partial Exclude has been implemented.
		2.	Added support of "cut off feature".
		3.	A new script "Restore_Version.pl" has been introduced to view/restore previous versions of a file.
		4.	A new script "Account_Setting.pl" has been introduced to setup user account locally.
		5.	Fixed login issue with wrong encryption key.
		6.	Fixed issue of skipping backup for hidden files.
		7.	Fixed the issue of retaining logs for "NO" option in some scenarios.
		8.	A new module called "Constants.pm" has been introduced to hold all display messages.
		9.	Full exclude issue has been fixed.
		10.	Enhanced logs for backup/restore for displaying machine name,Backup/Restore Location and backup/restore type like full backup or incremental backup.
		11.	Fixed the issue with sending e-mail under proxy settings.
		12.	Added script working folder as exclude entry for full path exclude to avoid any backup issue.
		13.	Fixed the issue of not deleting wrong password/private-key path during login.

	Build 2.0
	==============================================================================================================
		1.	operations.pl is introduced for centralizing some key operations.
		2. 	Replaced threads with fork processes.
		3.	Memory fixes for Backup and Restore processes.
		4.	Provided better Progress Details for manual and schedule job with size and transfer rate fields.
		5.	User logs has been enhanced for better understanding.
		6.	Removal of all downloaded zip and unzipped files after getting compatible binary in Account Setting pl
		7.	Avoided removing of trace log in failure cases in Account Setting pl.
		8.	Restricted user to provide backup location as "/".
		9.	Fixed for special character issue.
		10.	Fixed login issue when user tries to login without updating default configuration file.
		11.	Fixed the issue in Account setting pl for wrong proxy details.
		12.	Fixed the issue of not showing send mail error due to invalid email address in user log in case of manual configuration.
		13.	Removed FindBin dependency in Constants module.
		14. Fixed issue of user given invalid restore location in Account_Setting.pl.

	Build 2.1
	==============================================================================================================
		1. Modified Scheduler script to prompt for "Daily or Weekly" options for user to schedule job.
		2. User given Restore Location is created newly if not available by Account setting pl.
		3. Error message display if Backupset/Restore set file is empty.
		4. Fixed the issue of not allowing user to login when another user logged in.
		5. Fixed the issue of folder/file creation/access which is having special character.
		6. Fixed permission issue while accessing from upper level user.

	Build 2.2
	==============================================================================================================
		1. Enhanched Backup and Restore for better performance.
		2. Parallel Manual and Schedule Backup/Restore implementation.
		3. Better user log with failed files information.
		4. Provision of both mirror and relative Backup.
		5. Email address mandatory and semicolon (;) separation is also allowed.
		6. Cancellation of individual Manual/Schedule job is implemented via Job_Termination_Script.pl.

	Build 2.3
	==============================================================================================================
		1. Fixed Scheduler script issue for ubuntu machine.

	Build 2.4
	==============================================================================================================
		1. Fixed issue related to symlink exclude during Backup.
		2. Updated new idevsutil links.

	Build 2.5
	==============================================================================================================
		1. Fixed the issue related to exclude of symlinks in sub folders during Backup.
		2. Fixed the issue related to file names starting with 1,2 excluded during backup.

	Build 2.6
	==============================================================================================================
		1. Fixed the mentioned bugs in open issues list. Some are not reproducible please check it once again.
		2. Now using Account settings script, its possible to edit the account too.
		3. viewLog.pl script has been introduced to view the logs related to manual/scheduled backup/restore job.
		4. Permission issue fixed with .updateVersionInfo file.
		5. Fixed issues related to wget in checkforUpdate.pl
		6. Proxy related issue in account settings fixed.
		7. Restore location related bug fixed.
		8. Cosmetic changes done in editSupportFile.pl

	Build 2.7
	==============================================================================================================
		1.  Manual update of CONFIGURATION_FILE is not supported now. User must use "Account_Setting.pl" script to configure the account locally.
		2.  We have introduced service location concept in "Account_Setting.pl" script. This directory will contain all user specific data required to perform operations.
		3.  User details can be changed using Account_setting.pl file.
		4.  Progress bar has been implemented for backup/restore operations.
		5.  Backup location can be changed while initiating the backup via Backup_Script.pl.
		6.  Backup/Restore summary will be displayed for Immediate/Manual backup/Restore.
		7.  Restore location and Restore From location can be changed while initiating the restore via Restore_Script.pl.
		8.  "Edit_Supported_Files.pl" script is added to edit supported files like BackupsetFile.txt, RestoresetFile.txt etc.
		9.  "View_Log.pl" script is added to view manual/scheduled logs for Backup/Restore job.
		10. "Scheduler_Script.pl" script is updated to ask user for backup or restore related location changes.
		11. "Check_For_Update.pl" script is added which will allow to update the script bundle to the latest version.
		12. Every script will display a header to display script and user related information.
		13. "Logout.pl" script has been updated to kill manual backup/restore job if they are in progress based on user input.

	Build 2.8
	==============================================================================================================
		1.  Implemented support for all new IDrive accounts.
		2.  Account encryption key can be set using Login.pl script.
		3.  Fixed the invalid proxy issue for Login.pl script.
		4.  Using IDrive login cgi to validate IDrive accounts in Login.pl script.
		5.  Version display has been improved in Restore_Version.pl script.
		6.  Fixed all the issues related to IDrive account reset and password reset.

	Build 2.9
	==============================================================================================================
		1.  Fine tuned the backup process for better performance.

	Build 2.10
	==============================================================================================================
		1.  Fixed the private key validation issue.
		2.  Resolved the IDrive login issue w.r.t special characters.

	Build 2.11
	==============================================================================================================
		1.  A new script "Uninstall_Script.pl" has been introduced to uninstall package script and dependency files and to cleanup the scheduled jobs.
		2.  Introduced an argument for "Account_Setting.pl" script where user can input the zip file path based on his machine architecture. This zip will contain all the dependency files "Account_Setting.pl" script may require to download internally. This option can be used if wget does not work as expected from script.
		3.  Introduced an argument for "Check_For_Update.pl" script where user can input the package zip file path. Script will update the current scripts to the package scripts passed. Using this method user can upgrade and even downgrade (not recommended) his scripts to any version.
		4.  Fixed all the issues for scripts path having white-space.
		5.  Handled the issue when the backup failed due to quota exceed.
		6.  Extended Support for opensuse and fedora core.

	Build 2.12
	==============================================================================================================
		1.  Extended support for OpenSUSE,FreeBSD and Linux Mint.
		2.  Renamed the "Job_Termination_Script.pl" to "job_termination.pl" with new design.
		3.  Fixed restore issue when directory name in restore set file having white-space.
		4.  Fixed the scheduler issue when crontab path is link.
		5.  Fixed the status retrieval issue when the username having character "cd".
		6.  Fixed the transfer rate issue in Backup/Restore progress bar.
		7.  Fixed the linux binary finding issue in "Account_Setting.pl" script when zip file passed as argument.
		8.  Fixed the duplicate header display issue in Restore_Version.pl script.
		9.  Fixed the IDrive account validation issue with fallback logic.

	Build 2.13
	==============================================================================================================
		1.  A new script "express_backup.pl" has been introduced to do express backup.
		2.  Fixed the scheduled backup/restore operation summary issue when it terminated by cut-off.
		3.  Fixed the progress bar issue in status retrieval script when scheduled job terminated by cut-off.
                4.  Fixed the email notification issue when multiple email ids added.

	Build 2.14
	==============================================================================================================
		1.  Increased the retry attempt count from 5 to 1000 for Backup/Restore operations.
		2.  Fixed the issue for backup/restore retry in few scenarios.

	Build 2.15
	==============================================================================================================
		1.  Fixed the wrong UID fetching issue for few machines.
		2.  Fixed the logout script issue when backup/restore operation is in progress.
		3.  Fixed the restore from location update issue while editing backup location.
		4.  Fixed the cut-off issue when user logged out.

	Build 2.16
	==============================================================================================================
		1.  A new script "archive_cleanup.pl" has been introduced to delete data from your account if not available locally for your schedule backup set.
		2.  A new script "send_error_report.pl" has been introduced to send the error report to IDrive support.
		3.  Redesigned the "Account_Setting.pl" and renamed it to "account_setting.pl".
		4.  Redesigned the "Login.pl" and renamed it to "login.pl".
		5.  Redesigned the "Restore_Version.pl" and renamed it to "restore_version.pl".
		6.  Redesigned the "View_Log.pl" and renamed it to "view_log.pl".
		7.  Redesigned the "Edit_Supported_Files.pl" and renamed it to "edit_supported_files.pl".
		8.  Redesigned the "Check_For_Update.pl" and renamed it to "check_for_update.pl".
		9.  Fixed the backup/restore progress bar display issue w.r.t FreeBSD.
		10. Fixed the backup failure issue with retry attempt when server connection failed.
		11. Added support for Gentoo platform.

	Build 2.17
	==============================================================================================================
		1. Implemented 'multiple file chunks upload simultaneously' option to improve the data transfer speed.
		2. Introduced Dashboard functionality to access via web.
		3. Introduced IDrive cron service.
		4. Added Start immediately and hourly Backup feature for Backup / Express Backup in scheduler.
		5. Redesigned the "Logout.pl" and renamed it to "logout.pl".
		6. Redesigned the "Scheduler_Script.pl" and renamed it to "scheduler.pl".
		7. Removed schedule Restore feature in scheduler.pl script.
		8. Added schedule Express Backup feature in scheduler.pl script.
		9. Fixed the backup failure issue with retry attempt when file failed due to update retained error.
		10. Added validation in edit_supported_files.pl to ignore invalid/duplicate/child files & folders for backup/express backup/full path exclude options.
		11. Creating the log file for scheduled jobs for the operations backup/express backup/restore even if backupset/express backupset/restoreset file is empty.
		12. Fixed the progress bar display issue when retry attempt happening for backup/express backup/restore operations.
		13. Added valid failed reason for a file backup if same name directory already exist in idrive account.
		14. Fixed the proxy related issue.
		15. Modified the Archive cleanup log content.
		16. Enhanced the view log script for better status of all scheduled jobs.
		17. Reduced the send error report's message length from 32767 to 4095 characters.
		18. Added few improvements in account_setting.pl script.
		19. Added few new edit options with account_setting.pl as "file Missing percentage","Failed files percentage", "Ignore file permission/missed files", "Software update notification", "Start/Restart dashboard service", "Start/Restart IDrive cron service", "Added Enable/Disable Desktop access", "Enable/Disable Restore location prompt".
		20. Added few improvements for "check_for_update.pl".

	Build 2.18
	==============================================================================================================
		1. Fixed partial exclude parsing issue when policy is propagated.
		2. Added information if the dashboard doesn't support machine architecture.
		3. Added Backup/Express Backup/Restore file sets to logs.
		4. Fixed NET/SSL error issues.
		5. Fixed backup count mismatch issue.
		6. Added IDrive cron service support for opensuse leap 15 and Centos 6.*
		7. Implemented job handling when the system restart happens.
		8. Fixed account settings termination issue if the user account is cancelled.
		9. Fixed IDrive cron service restart issue when the script is not able to add linux service.
		10. Added improvements in check for update's EVS update and static perl update.

	Build 2.19
	==============================================================================================================
		1. A new script "help.pl" has been introduced to guide the user to use this package.
		2. Implemented delete functionality for user log files.
		3. Avoiding backup of files which is failed with valid reasons.
		4. Displaying Linux "logged in" user name also in header of executable scripts.
		5. Removed "Retain Logs" option in account_setting.pl.
		6. Syncing settings of old machine to new machine in case of adoption.
		7. Logging out from old machine's client gracefully when that machine is adopted by new client machine.
		8. Renaming old machine name to new machine name in case of adoption.
		9. Added machine information in reports sent via send error report.
		10. Providing an option in check for update for force update to latest version even if no update is available.
		11. Renamed the "view_log.pl" to "logs.pl".
		12. Fine tuned the dashboard service for better performance and reliability.
		13. Fine tuned the trace log writing.
		14. Handled multiple write scenarios for JSON files present with scripts to avoid possible corruption.
		15. Allowing to configure/re-configure scripts if remote manager http or https ip is missing.
		16. Handle dashboard stop issue due to disconnection on notification server.
		17. Providing limited retry count for specific errors.
		18. Merged BackupSet.info & backupsetsize.txt to BackupSet.txt.json file.
		19. Fine tuned the logic to generate machine id to identify each user machine uniquely.
		20. Added alerts status update in dashboard report's page.
		21. Modified the password input validation. Password should be at least 3 - 20 characters.
		22. Added color screen outputs to account details display.
		23. Fixed allowing 0% for NFB.
		24. Fixed updating last activity time.
		25. Fixed reading/writing utf-8 strings to and from dashboard.
		26. Fixed starting dashboard on reboot.
		27. Fixed updating loc param for dedup a/cs.
		28. Fixed updating job status on system restart.
		29. Fixed updating backuptime when it is not set
		30. Fixed failing cut-off for backup in freebsd.
		31. Fixed to add restore set contents to logs.
		32. Fixed self terminating dashboard while switching user.
		33. Fixed stop trying to start dashboard when DDA is enabled.
		34. Fixed sending mails only when notify on failure is enabled.
		35. Fixed relocate service dir when dashboard & other jobs are in progress.
		36. Fixed updating backupset contents with propagated files lists.
		37. Fixed displaying number of successful backedup count in reports page.
		38. Fixed marking IDrive account inactive on machine reboot for non-dedup a/cs.
		39. Fixed re-calculating backup set size on enabling/disabling show hidden option.
		40. Fixed displaying nick-name instead of location name while adopting a backup location.

	Build 2.20
	==============================================================================================================
		1. Fine tuned the express backup process.

	Build 2.21
	==============================================================================================================
		1. Added E-mail ID login support.
		2. Fixed replacing evs binaries on manual update.
		3. Fixed replacing Perl binaries on normal/manual update.
		4. Fixed finding registered MUID when there are multiples of them found.
		5. Allowing user to select any available locations as restore from location in Restore_Script.pl.
		6. Fixed the schedule job execution issue in FreeBSD.
		7. Fixed the environment variable related issues when job running through cron in FreeBSD.
		8. Fixed proxy issues for few scenarios.
		9. IDrive/IBackup script changes with REST APIs to handle the conflict of sslv3.
		10. Fixed the incremental backup issue for the huge size file.
		11. New startup routine Version extended for Gentoo.
		12. Fixed the IDrive cron restart issue.
		13. Debian configuration changes added for version 8.
		14. Fixed starting dashboard on machine reboot & fixed sync settings regardless of account login.
		15. Added to handle process 'upstart' in order to avoid the "supporting scripts run" error.
		16. Fixed the restore issue when it failed to restore the file due to unexpected error.
		17. Added retry case on archive cleanup/Restore(enumerate) w.r.t update server address.
		18. Fixed the issue of Backup/Restore job termination with error message.
		19. Fixed the error message display issue when user switching the IDrive account.
		20. Fixed the job termination issue when uninstalling package in FreeBSD.
		21. Fixed the restore set edit issue in edit_supported_files.pl when configured "restore from location" got adopted by other machine/IDrive application.
		22. Fixed the email notification issue for the scheduled job when server address gets changed.
		23. Displaying warning message in check for update script if any operation is in progress.
		24. Fixed the wrong message display issue when uninstall failed due to providing wrong password while deleting for IdriveIt folder.

	Build 2.22
	==============================================================================================================
		1. Fixed the dashboard restart issue on machine reboot for few scenarios.

	Build 2.23
	==============================================================================================================
		1. Disabling dashboard service for websock enabled dashboard which is currently not supported by Linux scripts.

	Build 2.24
	==============================================================================================================
		1. Worked on few enhancements to improve the overall performance of Dashboard.
		2. Changed the date format for user logs to MM/DD/YYYY.
		3. Fixed issue for finding unique ID for user's computer.
		4. Fixed archive cleanup user logs listing issue for dashboard.
		5. Fine tuned local notification design for dashboard to provide better handling of few scenarios.
		6. Removed the Desktop access enable and disable options for new accounts in "account_setting.pl".
		7. Fixed the parent account mismatch issue while switching and configuring the new IDrive account in "account_setting.pl".
		8. Fixed the login issue with IDrive account which is not configured.
		9. Fixed the progress bar display issue for backup and restore operation in "Status_Retrieval_Script.pl".
		10. Fixed the unwanted directory creation issue while switching IDrive accounts in account_setting.pl.
		11. Removed deprecated "Helpers.pm" file while updating the scripts using "check_for_update.pl".
		12. Added information on total size of backed up files along with files count in log Summary for Backup/Express Backup/Restore operations.

	Build 2.25
	==============================================================================================================
		1. Added version number & release date info in dashboard computer's page.
		2. Added multiple computer IDrive software update.
		3. Changed the date format for user logs to mm-dd-YYYY.

	Build 2.26
	==============================================================================================================
		1. Added delete computer from dashboard.
		2. Added delete backup location from cloud backup.
		3. Fixed taking long time to restore computer settings when a backup location is adopted to a new computer.
		4. Added IDrive CRON job machine restart fallback handler.
		5. Added account status handling to avoid unnecessary server calls.
		6. Renamed the "Helpers.pm" to "Common.pm".
		7. Renamed the "Configurations.pm" to "AppConfig.pm".
