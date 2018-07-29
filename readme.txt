								IDrive for Linux
								=================

I. INTRODUCTION
================
Backup and protect your Linux machine data using scripts bundle provided by IDrive. Protect files during transfer and storage, using 256-bit AES encryption with an optional private key.

II. SYSTEM/SOFTWARE REQUIREMENTS
=================================
Linux(CentOS/Ubuntu/Fedora/OpenSUSE/FreeBSD/Linux Mint/Gentoo) - 32-bit/64-bit
Perl v5.8 or later

III. SCRIPT DOWNLOAD
=====================
STEP 1: The script bundle can be downloaded from the link 		          			
		"https://www.idrivedownloads.com/downloads/linux/download-for-linux/IDriveForLinux.zip".
		After downloading, extract the zip file in your machine. Current unzipped folder ie IDriveForLinux should contain scripts folder. 
		Below files will be present in the scripts folder: 
		
		1. account_setting.pl
		2. archive_cleanup.pl
		3. Backup_Script.pl
		4. check_for_update.pl
		5. Configuration.pm
		6. Constants.pm
		7. edit_supported_files.pl
		8. express_backup.pl
		9. Header.pl
		10. Helpers.pm
		11. IxHash.pm
		12. JSON.pm
		13. job_termination.pl
		14. login.pl
		15. Logout.pl
		16. Operations.pl
		17. readme.txt
		18. Restore_Script.pl
		19. restore_version.pl
		20. Scheduler_Script.pl
		21. send_error_report.pl
		22. Status_Retrieval_Script.pl
		23. Strings.pm
		24. Uninstall_Script.pl
		25. utility.pl
		26. view_log.pl
		
	
STEP 2: Provide appropriate permissions (executable permission) to the scripts
		Example:  chmod a+x *.pl

IV. SETUP YOUR IDRIVE ACCOUNT
==============================
STEP 1: You need to have an IDrive account to use the script bundle to backup your files. In case you do not have an account, 
		please sign up and create an account at https://www.idrive.com/idrive/signup .
			
STEP 2: To set up IDrive script bundle locally with your IDrive account, run the below command and follow the instructions.
		$./account_setting.pl 
		Note: Setting up the script bundle for the first time will ask user to enter the service path. This path will contain user specific data required to perform operations via script bundle. 
		
V. WORKING WITH THE SCRIPTS
============================
Using IDrive scripts, you can perform backup/express backup/restore operations, view progress for backup/express backup/restore, schedule backup/restore job, view logs files and much more.

STEP 1: Login to your IDrive account
		If you are not logged in to your IDrive account while setting up your script bundle, run the below command to login.
		$./login.pl 
		
		Note: Login script is a mandatory script to be executed before performing any operation. This script will authenticate your IDrive account details	and will create a secure session for your backups. 
		
STEP 2: Edit your exclude files and Backup set files for your immediate or scheduled operations(backup/restore/Express-backup)
		Before starting an operation(backup/restore/Express-backup), the user must provide the list of files/folders required for the operation (backup/restore/Express-backup).
		To update the item list in the backup/Express-backup/restore set file you must execute the below command.
		$./edit_supported_files.pl 
		
		The menu option will be displayed. Select option 1 to edit backup set file for your immediate/manual backup. 
		Respective file will open in command line text editor to edit. Add the files/folders that needs to be backed up.
		Using same script you can update exclude and even schedule backup/express backup/restore set file by selecting the desired option.
		
STEP 3: Immediate/Manual backup
		You can perform immediate/manual backup using the below command:  
		$./Backup_Script.pl 

		When you run your backup script, it will reconfirm your backup location and allow you to change it. You can now view the graphical progress bar for your data backing up. 
		If you want your script not to ask for backup location and not to display progress bar then you can always use "--silent" flag with this command. 
		
STEP 4:	Immediate/Manual restore
		You can perform immediate/manual restore using the below command:  
		$./Restore_Script.pl

		When you run your restore script, it will reconfirm your restore and restore from location and will allow you to change it if required. 
		You can now view the graphical progress bar for your data restoring. If you want your script not to ask for restore location, restore from location and not to display progress bar then you can always use "--silent" flag with this command.

STEP 5: Immediate/Manual express backup
		Before starting express backup operation, user must connect the external storage device to linux machine & make sure that it mounted properly.
		You can perform immediate/manual express backup using the below command and follow the instructions:  
		$./express_backup.pl

STEP 6:	Schedule backup/restore/periodic cleanup
		Run the below command to manage your schedule backup/restore/periodic cleanup job: 
		$./Scheduler_Script.pl 

		Select the desired menu option to create/edit or delete your schedule backup/restore/periodic cleanup job and follow the instructions. 
		In case you want your scheduled backup/restore job to stop automatically at a scheduled time then set the cut-off time as well while following the instructions.

STEP 7: View progress of scheduled backup/restore job 
		To view the progress of scheduled backup or restore operation, run the below command: 
		$./Status_Retrieval_Script.pl

STEP 8: View/restore previous versions of a file
		You can view the list of previous versions of any file and select any version that you want to restore. To retrieve a file with earlier versions, run the below command: 
		$./restore_version.pl 

STEP 9:	Stop ongoing backup/express backup/restore operations 
		To stop an ongoing backup or express backup or restore operation, run the below command: 
		$./job_termination.pl 
		
STEP 10: View backup/express backup/restore/archive cleanup logs
		You can view the backup or restore or express backup or archive cleanup log files by running the below command: 
		$./view_log.pl

STEP 11: Archive cleanup
		Archive Cleanup compares the files of your local data in the backup set, selected for cleanup, with the files in your IDrive online backup account. It then deletes the files 
		present in your account but not on your local machine. This feature thus helps you to free up space in your online backup account.  
		You can run below command for archive cleanup: 
		$./archive_cleanup.pl
		
		When you run your archive cleanup script, you need to enter the percentage limit beyond which cleanup will not take place.
		Note: Your scheduled backupset will be considered for archive cleanup.

STEP 12: Send error report
		You can send error report to IDrive support by running the below command: 
		$./send_error_report.pl

STEP 13: Logout from your IDrive account 
		To end the logged in session for your IDrive account, run the below command: 
		$./Logout.pl
		
		User must logout (optional) from the account to avoid any unauthorized access to their IDrive account. After logout, user needs to login again to perform most of the operations.
		Note: Your scheduled backup or restore job will run even after you log out.

VI. UPDATING YOUR SCRIPT BUNDLE
================================
		Every script when gets executed displays a header which provide details of logged in IDrive account. Same header also displays information on any newly available script bundle.
		When you see a line "A new update is available. Run Check_For_Update.pl to update to latest package." means we have released a new improved version of script bundle. 
		To update to most recent available script bundle please perform the below command and follow the instructions.
		$./check_for_update.pl

VII. UNINSTALLING YOUR SCRIPT BUNDLE
====================================
		Uninstalling the script package from your system will leave the files/folders of your system liable to digital disasters.

		To uninstall the script bundle please perform the below command and follow the instructions.
		$./Uninstall_Script.pl

		This script will automatically remove all package script files and other dependency files. It will also cleanup the scheduled backup/restore jobs if any.


VIII. OTHERS
============
		Script bundle have few more supported script files (Header.pl, Helpers.pm, Configuration.pm, Constants.pm, IxHash.pm, JSON.pm, Strings.pm, Operations.pl and utility.pl) which are used internally by other scripts.
    
IX. RELEASES
================
	Build 1.0:
		N/A
	
	Build 1.1:
	
		1.	Fixed the backup/restore issue for password having special characters.
		2.	Fixed the backup/restore issue for encryption key having special characters.
		3.	Fixed the backup/restore issue for user name having special characters.
		4.	Fixed the backup/restore issue for backup/restore location name having special characters.
		5.	Moved LOGS folder inside user name folder for better management.
		6.	Avoided unnecessary calls to server at the time of backup as well as restore. 
			Like create directory call, get server call and config account call. As before these calls 
			was taking place with each backup and restore operation.
		7.	New file named header.pl has been created. It contains all common functionalities. 

	Build 1.2:
		
		1.	Avoided error in the log when email is not specified in CONFIGURATION_FILE after backup 
			operation.
		2.	A new BACKUPLOCATION field has been introduced in CONFIGURATION_FILE. All the backed up 
			files/folders will be stored in the server under this name.  
		3.	A new RESTOREFROM field has been introduced in CONFIGURATION_FILE.  Any files/folders 
			that exist under this name can be restored from server to local machine.

	Build 1.3:

		1.	A new field RETAINLOGS has been introduced in CONFIGURATION_FILE. This field is used to 
			determine if all the logs in LOGS folder have to be maintained or not.
		2.	Fixed Retry attempt issue if backup/restore is interrupted for certain reasons.  

	Build 1.4:

		1. 	A new field PROXY has been introduced in CONFIGURATION_FILE. This field if enabled will 
			perform operations such as Backup/Restore via specified Proxy IP address.
		2. 	A new file login.pl has been introduced which reads required parameters from CONFIGURATION_FILE
			and validates IDrive credentials and create a logged in session. 
		3. 	A new file logout.pl has been introduced which allow to log out from logged in session for IDrive account.
		      It also clears PASSWORD and PVTKEY fields in configuration file.
	Build 1.5:
		1. 	A new field BWTHROTTLE has been introduced in CONFIGURATION_FILE. To restrict the bandwidth usage
		   for backup operation.
		2. 	Changes has been made to make script work on perl ver 5.8 as well.

	Build 1.6:
		1.	Schedule backup issue has been fixed in user logged out mode.

	Build 1.7:
		1. 	Support for multiple email notification on Schedule Backup has been implemented.
		2.	ENC TYPE has been removed from CONFIGURATION File.
		3. 	Schedule for Restore job has been implemented.
		4. 	Fixed login and logout issue. 

	Build 1.8:
		1. 	Support for multiple email notification on Schedule Restore has been implemented.
		2. 	Scheduler Script is enhanced to perform schedule Restore job.
		3.	Schedule restore is enhanced to run even after logout as well.
		4. 	Status retrieval support for manual as well as scheduled restore job has been implemented. 
		5. 	Job termination script is enhanced to cancel ongoing backup or restore or both the job.
		6.	Fixed issue of deleting backup or restore set file.
		7. 	Showing of Exclude items on Log is implemented.
		8.	Login is enhanced to display certain error messages. 
		
	Build 1.9:
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
		1. Modified Scheduler script to prompt for "Daily or Weekly" options for user to schedule job.
		2. User given Restore Location is created newly if not available by Account setting pl.
		3. Error message diplay if Backupset/Restore set file is empty.
		4. Fixed the issue of not allowing user to login when another user logged in.
		5. Fixed the issue of folder/file creation/access which is having special character.
		6. Fixed permission issue while accessing from upper level user.
		
	Build 2.2
		1. Enhanched Backup and Restore for better performance.
		2. Parallel Manual and Schedule Backup/Restore implementation.
		3. Better user log with failed files information.
		4. Provision of both mirror and relative Backup.
		5. Email address mandatory and semicolon (;) sepeartion is also allowed.
		6. Cancellation of individual Manual/Schedule job is implemented via Job_Termination_Script.pl.
		
	Build 2.3
		1. Fixed Scheduler script issue for ubuntu machine.
		
	Build 2.4
		1. Fixed issue related to symlink exclude during Backup.
		2. Updated new idevsutil links.
		
	Build 2.5
		1. Fixed the issue related to exclude of symlinks in subfolders during Backup.
		2. Fixed the issue related to file names starting with 1,2 excluded during backup.

	Build 2.6
		1. Fixed the menthioned bugs in open issues list. Some are not reproducible please check it once again.
		2. Now using Account settings script, its possible to edit the account too.
		3. viewLog.pl script has been introduced to view the logs related to manual/scheduled backup/restore job.
		4. Permission issue fixed with .updateVersionInfo file.
		5. Fixed issues related to wget in checkforUpdate.pl
		6. Proxy related issue in account settings fixed.
		7. Restore location related bug fixed.
		8. Cosmetic changes done in editSupportFile.pl
		
	Build 2.7
		1.  Manual update of CONFIGURATION_FILE is not supported now. User must use "Account_Setting.pl" script to configure the account locally.
		2.  We have introduced service location concept in "Account_Setting.pl" script. This directory will contain all user specific data required to perform operations.
		3.  User details can be changed using Account_setting.pl file.
		4.  Progress bar has been implemented for backup/restore operations.
		5.  Backup location can be changed while initiating the backup via Backup_Script.pl.
		6.  Backup/Restore summery will be displayed for Immediate/Manual backup/Restore.
		7.  Restore location and Restore From location can be changed while initiating the restore via Restore_Script.pl.
		8.  "Edit_Supported_Files.pl" script is added to edit supported files like BackupsetFile.txt, RestoresetFile.txt etc. 
		9.  "View_Log.pl" script is added to view manual/scheduled logs for Backup/Restore job. 
		10. "Scheduler_Script.pl" script is updated to ask user for backup or restore related location changes.
		11. "Check_For_Update.pl" script is added which will allow to update the script bundle to the latest verison.
		12. Every script will display a header to display script and user related information.
		13. "Logout.pl" script has been updated to kill manual backup/restore job if they are in progress based on user input.
		
	Build 2.8
		1.  Implemented support for all new IDrive accounts.
		2.  Account encryption key can be set using Login.pl script.
		3.  Fixed the invalid proxy issue for Login.pl script.
		4.  Using IDrive login cgi to validate IDrive accounts in Login.pl script.
		5.  Version display has been improved in Restore_Version.pl script.
		6.  Fixed all the issues related to IDrive account reset and password reset.

	Build 2.9
		1.  Fine tunned the backup process for better performance.

	Build 2.10
		1.  Fixed the private key validation issue.
		2.  Resolved the IDrive login issue w.r.t special characters.

	Build 2.11
		1.  A new script "Uninstall_Script.pl" has been introduced to uninstall package script and dependency files and to cleanup the scheduled jobs.
		2.  Introduced an argument for "Account_Setting.pl" script where user can input the zip file path based on his machine architecture. This zip will contain all the dependency files "Account_Setting.pl" script may require to download internally. This option can be used if wget does not work as expected from script.
		3.  Introduced an argument for "Check_For_Update.pl" script where user can input the package zip file path. Script will update the current scripts to the package scripts passed. Using this method user can upgrade and even downgrade (not recommended) his scripts to any version. 
		4.  Fixed all the issues for scripts path having white-space.
		5.  Handled the issue when the backup failed due to quota exceed.
		6.  Extended Support for opensuse and fedora core.

	Build 2.12
		1.  Extended support for OpenSUSE,FreeBSD and Linux Mint.
		2.  Renamed the "Job_Termination_Script.pl" to "job_termination.pl" with new design.
		3.  Fixed restore issue when directory name in restore set file having white-space.
		4.  Fixed the scheduler issue when crontab path is link.
		5.  Fixed the status retrival issue when the username having character "cd".
		6.  Fixed the transfer rate issue in Backup/Restore progress bar.
		7.  Fixed the linux binary finding issue in "Account_Setting.pl" script when zip file passed as argument.
		8.  Fixed the duplicate header display issue in Restore_Version.pl script.
		9.  Fixed the IDrive account validation issue with fallback logic.

	Build 2.13
		1.  A new script "express_backup.pl" has been introduced to do express backup.
		2.  Fixed the scheduled backup/restore operation summary issue when it terminated by cut-off.
		3.  Fixed the progress bar issue in status retrieval script when scheduled job terminated by cut-off.
                4.  Fixed the email notification issue when multiple email ids added.

	Build 2.14
		1.  Increased the retry attempt count from 5 to 1000 for Backup/Restore operations.
		2.  Fixed the issue for backup/restore retry in few scenarios.

	Build 2.15
		1.  Fixed the wrong UID fetching issue for few machines.
		2.  Fixed the logout script issue when backup/restore operation is in progress.
		3.  Fixed the restore from location update issue while editing backup location.
		4.  Fixed the cut-off issue when user logged out.

	Build 2.16
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

	======================================================================================
