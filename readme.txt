								IDrive for Linux
								=================

I. INTRODUCTION
================
Backup and protect your Linux machine data using scripts bundle provided by IDrive. Protect files during transfer and storage, using 256-bit AES encryption 
with an optional private key.

II. SYSTEM/SOFTWARE REQUIREMENTS
=================================
Linux(CentOS/Ubuntu/Fedora) - 32-bit/64-bit
Perl v5.8 or later

III. SCRIPT DOWNLOAD
=====================
STEP 1: The script bundle can be downloaded from the link "https://www.idrive.com/downloads/linux/download-for-linux/IDrive_for_Linux.zip".
		After downloading, extract the zip file in your machine. Current unzipped folder ie IDrive_for_Linux should contain scripts folder. 
		Below files will be present in the scripts folder: 
		
		1. Account_Setting.pl
		2. Backup_Script.pl
		3. Check_For_Update.pl
		4. Constants.pm
		5. Edit_Supported_Files.pl
		6. Header.pl
		7. Job_Termination_Script.pl
		8. Login.pl
		9. Logout.pl
		10. Operations.pl
		11. readme.txt
		12. Restore_Script.pl
		13. Restore_Version.pl
		14. Scheduler_Script.pl
		15. Status_Retrieval_Script.pl
		16. View_Log.pl
	
STEP 2: Provide appropriate permissions (executable permission) to the scripts
		Example:  chmod a+x *.pl

IV. SETUP YOUR IDRIVE ACCOUNT
==============================
STEP 1: You need to have an IDrive account to use the script bundle to backup your files. In case you do not have an account, 
		please sign up and create an account at https://www.idrive.com/ .
			
STEP 2: To set up IDrive script bundle locally with your IDrive account, run the below command and follow the instructions.
		$./Account_Setting.pl 
		Note: Setting up the script bundle for the first time will ask user to enter the service path. This path will contain user specific data required to perform operations via script bundle. 
		
V. WORKING WITH THE SCRIPTS
============================
Using IDrive scripts, you can perform backup/restore operations, view progress for backup/restore, schedule backup/restore job, view logs files and much more.

STEP 1: Login to your IDrive account
		If you are not logged in to your IDrive account while setting up your script bundle, run the below command to login.
		$./Login.pl 
		
		Note: Login script is a mandatory script to be executed before performing any operation. This script will authenticate your IDrive account details 
		and will create a secure session for your backups. 
		
STEP 2: Edit, exclude and schedule the backup/restore set files
		Before starting backup/restore operation, the user must provide the file/folder list required to backup/restore in backup/restore set file. 
		To update these details in the backup/restore set file you must execute the below command.
		$./Edit_Supported_Files.pl 
		
		The menu option will be displayed. Select option 1 to edit backup set file for your immediate/manual backup. 
		Respective file will open in vi editor to edit. Add the files/folders that needs to be backed up.
		Using same script you can update exclude and even schedule backup/restore set file by selecting the desired option.
		
STEP 3: Immediate/Manual backup
		You can perform immediate/manual backup using the below command:  
		$./Backup_Script.pl 

		When you run your backup script, it will reconfirm your backup location and allow you to change it. You can now view the graphical progress bar for your data backing up. 
		If you want your script not to ask for backup location and not to display progress bar then you can always use “--silent” flag with this command. 
		
STEP 4:	Immediate/Manual restore
		You can perform immediate/manual restore using the below command:  
		$./Restore_Script.pl

		When you run your restore script, it will reconfirm your restore and restore from location and will allow you to change it if required. 
		You can now view the graphical progress bar for your data restoring. If you want your script not to ask for restore location, restore from location 
		and not to display progress bar then you can always use “--silent” flag with this command.

STEP 5:	Schedule backup/restore
		Run the below command to manage your schedule backup/restore job: 
		$./Scheduler_Script.pl 

		Select the desired menu option to create/edit or delete your schedule backup/restore job and follow the instructions. 
		In case you want your schedule job to stop automatically at a scheduled time then set the cut-off time as well while following the instructions.

STEP 6: View progress of scheduled backup/restore job 
		To view the progress of scheduled backup or restore operation, run the below command: 
		$./Status_Retrieval_Script.pl

STEP 7: View/restore previous versions of a file
		You can view the list of previous versions of any file and select any version that you want to restore. To retrieve a file with earlier versions, run the below command: 
		$./Restore_Version.pl 

STEP 8:	Stop ongoing backup/restore operations 
		To stop an ongoing backup or restore operation, run the below command: 
		$./Job_Termination_Script.pl 
		
STEP 9: View backup/restore logs
		You can view the backup or restore log files by running the below command: 
		$./View_Log.pl

STEP 10: Logout from your IDrive account 
		To end the logged in session for your IDrive account, run the below command: 
		$./Logout.pl
		
		User must logout (optional) from the account to avoid any unauthorized access to their IDrive account. After logout, user needs to login again to perform most of the operations.
		Note: Your scheduled backup or restore job will run even after you log out.

VI. UPDATING YOUR SCRIPT BUNDLE
================================
		Every script when gets executed displays a header which provide details of logged in IDrive account. Same header also displays information on any newly available script bundle.
		When you see a line "A new update is available. Run Check_For_Update.pl to update to latest package." means we have released a new improved version of script bundle. 
		To update to most recent available script bundle please perform the below command and follow the instructions.
		$./Check_For_Update.pl
		
VII. OTHERS
============
		Script bundle have few more supported script files (Header.pl, Constants.pm and Operations.pl) which are used internally by other scripts.
    
VIII. RELEASES
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
		2.  We have introduced service loaction concept in "Account_Setting.pl" script. This directory will contain all user specific data required to perform operations.
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
	======================================================================================
