#*****************************************************************************************************
# SQLITE management package
#
# Created By	: Vijay Vinoth @ IDrive Inc
#****************************************************************************************************/
package Sqlite;

use strict;
use warnings;

use File::stat;
use utf8;
use AppConfig;
use Common;
use File::Basename;

our ($dbh, $selDirID, $selFileInfo, $selAllFiles, $findAllFilesByDir, $dbhInsertFile, $dbhUpdateFile, $dbhInsertDir, $dbhUpdateDir, $dbhUpdateDirCount);
our ($selectFolderDetail, $deleteFileInfo, $dbhInsertProc, $dbhUpdateProc, $selProcData, $getChildDirsByDir, $deleteFilesByDirID, $deleteDirsByDirID, $cdpBackupsetquery, $backupsetquery);
our ($updBackUpSucc, $lastprocdata, $selsubdirs, $selfcds, $dbhUpdateFileStat, $resetBackedupStat, $updExpressBackUpSucc, $fcbydiridandstat, $fcbydirid);
our ($selconscount, $filecountbystatus, $selexclitems, $selExpressFiles, $selbkpsetitem, $addbkpitem, $updbkpitem, $selallbkpsetitems, $delbkpsetitem);
our ($delallfiles, $delalldirs, $selconf, $selallconf, $insconf, $updconf, $selallfc, $selfcbkdup);
our $dberror;
# @INFO: {JOBNAME, DBPATH, OPERATION, ITEM, DATA)

my $localDB;
my $ibFolder	= "ibfolder";
my $ibFile		= "ibfile";
my $ibProcess	= "ibprocess";
my $ibbkpset	= "ibbackupset";
my $ibconfig	= "ibconfig";

our ($dbh_LB, $selectFolderID, $selectFileInfo, $selectAllFile, $searchAllFileByDir, $dbh_ibFile_insert, $dbh_ibFile_update, $dbh_ibFolder_insert, $dbh_ibFolder_update, $selectBucketSize, $selectFileListByDir, $selectDirListByDir, $selectDirInfo);

#****************************************************************************************************
# Subroutine		: createLBDB
# Objective			: This subroutine connects to the Local Backup DB and then calls function to createTable.
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*****************************************************************************************************/
sub createLBDB {
	# my $localDB	= Common::getCatfile((defined($_[0]) && -d $_[0])? $_[0] : Common::getJobsPath('backup'), $AppConfig::dbname);
	$localDB	= Common::getCatfile((defined($_[0]) && -d $_[0])? $_[0] : Common::getJobsPath('backup'), $AppConfig::dbname);
	my ($useridLB, $passwordLB) = ("") x 2;
	my $stat = 1;

	unless(-f $localDB) {
		my $dbdir	= substr($localDB, 0, rindex($localDB, '/'));
		my $ecdbdir	= Common::getECatfile($dbdir);
		unless(-d $dbdir) {
			system("mkdir -p $ecdbdir");
			chmod($AppConfig::filePermission, $ecdbdir);
		}
	}

	# my ($package, $filename, $line) = caller;
	# Common::traceLog(["\n", 'opening DB: ' . $localDB . '# from: ' . $filename . '# line: ' . $line]);

	eval {
		my $dsnLB = "DBI:SQLite:dbname=$localDB";
		my %attr = (RaiseError => 1, AutoCommit => 1, PrintError => 0);
		$dbh = DBI->connect($dsnLB, $useridLB, $passwordLB, \%attr);
		
		unless(defined $dbh) {
			Common::traceLog("DB Error: " . $DBI::errstr);
			$stat = 0;
		} else {
			$dbh->do('PRAGMA synchronous = OFF');
			$dbh->do('PRAGMA read_uncommitted = ON');
			$dbh->do('PRAGMA case_sensitive_like = 1');
			$dbh->do('PRAGMA journal_mode = WAL');
			$dbh->do('PRAGMA cache_size = 10240');
		}

		1;
	} or do {
		$dberror = $DBI::errstr? $DBI::errstr : $@;
		Common::traceLog("DB Error: " . $dberror);

		if($dberror && $dberror =~ /disk is full|disk I\/O error/gi) {
			$dberror = 'disk is full';
			Common::retreat(['disk_is_full_aborting']);
			exit(1);
		}
	};

	if($@) {
		$stat = 0 ;
		Common::traceLog(['DB Error: ', $@]);
		$dberror = $DBI::errstr? $DBI::errstr : $@;
	}

	# place scan request if failed to open db
	if(!$stat || !createTableLB()) {
		Common::traceLog(['corrupted_db', '.', 'path: ', $localDB]);
		unlink($localDB);

		my $scanf		= '';
		if($_[1]) {
			my $dbpath	= dirname($localDB) . '/';
			my $jt		= lc(basename(dirname($dbpath)));
			$scanf		= Common::createScanRequest($dbpath, basename($dbpath), 0, $jt, 0, 1, 'all');
		}

		return (0, $scanf);
	}

	chmod($AppConfig::filePermission, $localDB);
	return (1, '');
}

#*****************************************************************************************************
# Subroutine		: createTable
# Objective			: This subroutine creates 3 tables - ibfile, ibfolder and ibprocess in DB only if it does not exist
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#******************************************************************************************************
sub createTableLB {
	eval {
		my $stmt = qq(CREATE TABLE IF NOT EXISTS ibfolder 
		   (DIRID integer primary key autoincrement,
			NAME char(1024) not null,
			DIR_LMD char(256),
			DIR_SIZE __int64 DEFAULT 0,
			DIR_COUNT __int64 DEFAULT 0,
			DIR_PARENT __int64,
			UNIQUE(NAME)););
		
		my $rv = $dbh->do($stmt);
		if($rv < 0) {
			Common::traceLog(['create_table_ibfolder_failed', $@]);
			return 0;
		}

		# $dbh->do("CREATE INDEX IF NOT EXISTS ibfolder_name on ibfolder (NAME)");
		# $dbh->do("CREATE INDEX IF NOT EXISTS ibfolder_parent on ibfolder (DIR_PARENT)");
		
		$stmt = qq(CREATE TABLE IF NOT EXISTS ibfile 
		   (FILEID integer primary key autoincrement,
			DIRID integer not null,
			NAME char(1024) not null,
			FILE_LMD DATETIME DEFAULT 0,
			FILE_SIZE __int64,
			FOLDER_ID char(1024) DEFAULT '-',
			ENC_NAME char(1024) DEFAULT '-',
			BACKUP_STATUS integer DEFAULT 0,
			CHECKSUM char(256) DEFAULT '-',
			LAST_UPDATED DATETIME DEFAULT CURRENT_TIMESTAMP,
			foreign key (DIRID) references ibfolder (DIRID),
			UNIQUE(DIRID, NAME)););

		$rv = $dbh->do($stmt);
		if($rv < 0) {
			Common::traceLog(['create_table_ibfile_failed', $@]);
			return 0;
		}

		# $dbh->do("CREATE INDEX IF NOT EXISTS ibfile_name on ibfile (NAME)");
		
		$stmt = qq(CREATE TABLE IF NOT EXISTS ibprocess 
		   (PROCESSID integer primary key autoincrement,
			START_TIME char(50),
			END_TIME char(50),
			JOB_TYPE char(50),
			UNIQUE(PROCESSID,JOB_TYPE)););
			
		$rv = $dbh->do($stmt);
		if($rv < 0) {
			Common::traceLog(['create_table_ibprocess_failed', $@]);
			return 0;
		}

		# $dbh->do("CREATE INDEX IF NOT EXISTS ibfile_type on ibprocess (JOB_TYPE)");

		$stmt = qq(CREATE TABLE IF NOT EXISTS ibbackupset 
		   (ITEM_ID integer primary key autoincrement,
			ITEM_NAME char(50),
			ITEM_TYPE char(2),
			ITEM_STATUS char(50),
			ITEM_LMD char(50) DEFAULT '0',
			UNIQUE(ITEM_NAME)););
			
		$rv = $dbh->do($stmt);
		if($rv < 0) {
			Common::traceLog(['create_table_ibbackupset_failed', $@]);
			return 0;
		}
		
		$stmt = qq(CREATE TABLE IF NOT EXISTS ibconfig 
		   (CONF_ID integer primary key autoincrement,
			CONF_NAME char(50),
			CONF_VAL char(50),
			UNIQUE(CONF_NAME)););
			
		$rv = $dbh->do($stmt);
		if($rv < 0) {
			Common::traceLog(['create_table_ibconfig_failed', $@]);
			return 0;
		}

		1;
	} or do {
		Common::traceLog(["DB Error: ", $@]);
		$dberror = $@;
		return 0;
	};

	return 1;
}

#*****************************************************************************************************
# Subroutine	: createTableIndexes
# In Param		: UNDEF
# Out Param		: UNDEF
# Objective		: Creates the table indexes if not created
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub createTableIndexes {
	$dbh->do("CREATE INDEX IF NOT EXISTS ibfolder_name on ibfolder (NAME)");
	$dbh->do("CREATE INDEX IF NOT EXISTS ibfolder_parent on ibfolder (DIR_PARENT)");
	$dbh->do("CREATE INDEX IF NOT EXISTS ibfile_name on ibfile (NAME)");
	$dbh->do("CREATE INDEX IF NOT EXISTS ibfile_type on ibprocess (JOB_TYPE)");
}

#******************************************************************************************************************
# Subroutine		: initiateDBoperation
# Objective			: This subroutine initiates the dp operations
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#******************************************************************************************************************
sub initiateDBoperation {
	# Common::retreat("Create LBDB failed.") unless(createLBDB());
	
	my $ibFolder	= "ibfolder";
	my $ibFile		= "ibfile";
	my $ibProcess	= "ibprocess";
	my $ibbkpset	= "ibbackupset";
	my $ibconfig	= "ibconfig";
	
	eval {
		$selAllFiles			= $dbh->prepare("SELECT FILEID, NAME, FILE_LMD, BACKUP_STATUS, FILE_SIZE FROM $ibFile WHERE DIRID=?");
		$fcbydiridandstat		= $dbh->prepare("SELECT COUNT(FILEID) as FC FROM $ibFile WHERE DIRID=? AND BACKUP_STATUS=?");
		$fcbydirid				= $dbh->prepare("SELECT COUNT(FILEID) as FC FROM $ibFile WHERE DIRID=?");
		$filecountbystatus		= $dbh->prepare("SELECT COUNT(FILEID) as FC FROM $ibFile WHERE BACKUP_STATUS=?");
		$selallfc				= $dbh->prepare("SELECT COUNT(FILEID) as FC FROM $ibFile WHERE 1");
		$selconscount			= $dbh->prepare("SELECT COUNT(FILEID) as FC FROM $ibFile WHERE BACKUP_STATUS <> " . $AppConfig::dbfilestats{'EXCLUDED'});
		$selsubdirs				= $dbh->prepare("SELECT NAME FROM $ibFolder WHERE DIR_PARENT=?");
		$selDirID				= $dbh->prepare("SELECT DIRID FROM $ibFolder WHERE NAME=?");
		$selbkpsetitem			= $dbh->prepare("SELECT ITEM_ID, ITEM_TYPE, ITEM_STATUS FROM $ibbkpset WHERE ITEM_NAME=?");
		$selFileInfo			= $dbh->prepare("SELECT FILEID, FILE_LMD, FILE_SIZE, BACKUP_STATUS FROM $ibFile WHERE NAME=? AND DIRID=?");
		$selExpressFiles		= $dbh->prepare("SELECT FILEID, FOLDER_ID, ENC_NAME FROM $ibFile WHERE BACKUP_STATUS=" . $AppConfig::dbfilestats{'BACKEDUP'});
		$selallbkpsetitems		= $dbh->prepare("SELECT ITEM_ID, ITEM_NAME, ITEM_TYPE, ITEM_STATUS, ITEM_LMD FROM $ibbkpset WHERE 1");
		# $selProcData			= $dbh->prepare("SELECT * FROM $ibProcess WHERE 1 ORDER BY PROCESSID DESC LIMIT 1");
		$getChildDirsByDir		= $dbh->prepare("SELECT $ibFolder.DIRID as ID, $ibFolder.NAME as DIRNAME FROM $ibFolder WHERE $ibFolder.NAME LIKE ? ORDER BY ID DESC");
		$selfcds				= $dbh->prepare("SELECT COUNT($ibFile.FILEID) as FC, SUM($ibFile.FILE_SIZE) as FS FROM $ibFile INNER JOIN $ibFolder ON $ibFolder.DIRID = $ibFile.DIRID 
										WHERE $ibFile.BACKUP_STATUS <> " . $AppConfig::dbfilestats{'EXCLUDED'} . " AND $ibFolder.NAME LIKE ? ESCAPE '\\'");
		$selfcbkdup				= $dbh->prepare("SELECT COUNT($ibFile.FILEID) as FC FROM $ibFile INNER JOIN $ibFolder ON $ibFolder.DIRID = $ibFile.DIRID 
										WHERE $ibFile.BACKUP_STATUS = " . $AppConfig::dbfilestats{'BACKEDUP'} . " AND $ibFolder.NAME LIKE ? ESCAPE '\\'");
		$findAllFilesByDir		= $dbh->prepare("SELECT $ibFile.FILEID as FID, $ibFile.NAME as FNAME, $ibFile.BACKUP_STATUS, $ibFolder.NAME as DNAME FROM $ibFile 
										INNER JOIN $ibFolder ON $ibFolder.DIRID = $ibFile.DIRID WHERE $ibFolder.NAME LIKE ?");
		$selexclitems			= $dbh->prepare("SELECT $ibFile.FILEID as FID, $ibFile.NAME as FNAME, $ibFolder.NAME as DNAME FROM $ibFile INNER JOIN $ibFolder ON $ibFile.DIRID = $ibFolder.DIRID 
										WHERE $ibFile.BACKUP_STATUS = " . $AppConfig::dbfilestats{'EXCLUDED'});
		$selconf				= $dbh->prepare("SELECT CONF_VAL FROM $ibconfig WHERE CONF_NAME=?");
		$selallconf				= $dbh->prepare("SELECT CONF_ID, CONF_NAME, CONF_VAL FROM $ibconfig WHERE 1");
		$dbhInsertDir			= $dbh->prepare("INSERT INTO $ibFolder (NAME, DIR_LMD, DIR_SIZE, DIR_PARENT) values (?,?,?,?)");
		$dbhInsertProc			= $dbh->prepare("INSERT INTO $ibProcess (START_TIME, END_TIME) values (?,?)");
		$dbhInsertFile			= $dbh->prepare("INSERT INTO $ibFile (DIRID, NAME, FILE_LMD, FILE_SIZE, BACKUP_STATUS) VALUES (?,?,?,?,?)");
		$addbkpitem				= $dbh->prepare("INSERT INTO $ibbkpset (ITEM_NAME, ITEM_TYPE, ITEM_STATUS, ITEM_LMD) VALUES (?,?,?,?)");
		$insconf				= $dbh->prepare("INSERT INTO $ibconfig (CONF_NAME, CONF_VAL) values (?,?)");
		$dbhUpdateDir			= $dbh->prepare("UPDATE $ibFolder SET DIR_LMD=?, DIR_SIZE=? WHERE NAME=?");
		$updbkpitem				= $dbh->prepare("UPDATE $ibbkpset SET ITEM_TYPE=?, ITEM_STATUS=?, ITEM_LMD=? WHERE ITEM_ID=?");
		$dbhUpdateProc			= $dbh->prepare("UPDATE $ibProcess SET END_TIME=? WHERE START_TIME=?");
		$dbhUpdateDirCount		= $dbh->prepare("UPDATE $ibFolder SET DIR_COUNT=?, DIR_SIZE=? WHERE DIRID=?");
		$dbhUpdateFile			= $dbh->prepare("UPDATE $ibFile SET FILE_LMD=?, FILE_SIZE=?, BACKUP_STATUS=? WHERE NAME=? AND DIRID=?");
		$updBackUpSucc			= $dbh->prepare("UPDATE $ibFile SET BACKUP_STATUS=" . $AppConfig::dbfilestats{'BACKEDUP'} . " WHERE FILEID=? AND FILE_LMD=?");
		$updExpressBackUpSucc	= $dbh->prepare("UPDATE $ibFile SET BACKUP_STATUS=" . $AppConfig::dbfilestats{'BACKEDUP'} . ", FOLDER_ID=?, ENC_NAME=? WHERE FILEID=?");
		$updconf				= $dbh->prepare("UPDATE $ibconfig SET CONF_VAL=? WHERE CONF_NAME=?");
		$dbhUpdateFileStat		= $dbh->prepare("UPDATE $ibFile SET BACKUP_STATUS=? WHERE FILEID=?");
		$resetBackedupStat		= $dbh->prepare("UPDATE $ibFile SET BACKUP_STATUS=" . $AppConfig::dbfilestats{'NEW'} . " WHERE BACKUP_STATUS=" . $AppConfig::dbfilestats{'BACKEDUP'});
		$deleteFileInfo			= $dbh->prepare("DELETE FROM $ibFile WHERE NAME=? AND DIRID=?");
		$delbkpsetitem			= $dbh->prepare("DELETE FROM $ibbkpset WHERE ITEM_NAME=?");
		$deleteDirsByDirID		= $dbh->prepare("DELETE FROM $ibFolder WHERE DIRID=?");
		$delalldirs				= $dbh->prepare("DELETE FROM $ibFolder WHERE 1");
		$deleteFilesByDirID		= $dbh->prepare("DELETE FROM $ibFile WHERE DIRID=?");
		$delallfiles			= $dbh->prepare("DELETE FROM $ibFile WHERE 1");
		my $folderDetailsQuery	= qq(SELECT f.NAME, f.FILE_LMD, f.FILE_SIZE, f.DIRID, f.BACKUP_STATUS FROM $ibFile f INNER JOIN $ibFolder D on D.DIRID = f.DIRID WHERE D.NAME = ?);
		$selectFolderDetail		= $dbh->prepare($folderDetailsQuery);
		
		$cdpBackupsetquery		= qq(SELECT $ibFile.FILEID as FID, $ibFile.NAME as FILENAME, $ibFolder.NAME as DIRNAME, $ibFile.FILE_SIZE as FILE_SIZE
										FROM $ibFile 
										INNER JOIN $ibFolder ON $ibFolder.DIRID = $ibFile.DIRID 
										WHERE ($ibFile.FILE_SIZE <= $AppConfig::cdpmaxsize AND $ibFile.BACKUP_STATUS IN (%s) AND $ibFolder.NAME LIKE ?) ORDER BY $ibFile.FILE_SIZE DESC);

		$backupsetquery			= qq(SELECT $ibFile.FILEID as FID, $ibFile.NAME as FILENAME, $ibFolder.NAME as DIRNAME, $ibFile.FILE_SIZE as FILE_SIZE
										FROM $ibFile 
										INNER JOIN $ibFolder ON $ibFolder.DIRID = $ibFile.DIRID 
										WHERE ($ibFile.BACKUP_STATUS IN (%s) AND $ibFolder.NAME LIKE ?) ORDER BY $ibFile.FILE_SIZE ASC);
	};

	if($@) {
		Common::traceLog("Error: Prepare statement failed for insert/update for Local Backup.");
		$selfcds->finish();
		$selfcbkdup->finish();
		$fcbydiridandstat->finish();
		$fcbydirid->finish();
		$filecountbystatus->finish();
		$selDirID->finish();
		$selbkpsetitem->finish();
		$selsubdirs->finish();
		# $selProcData->finish();
		$selallfc->finish();
		$selAllFiles->finish();
		$selFileInfo->finish();
		$selExpressFiles->finish();
		$selallbkpsetitems->finish();
		$selconscount->finish();
		$selexclitems->finish();
		$selconf->finish();
		$selallconf->finish();
		$dbhInsertDir->finish();
		$dbhUpdateDir->finish();
		$dbhInsertProc->finish();
		$dbhInsertFile->finish();
		$dbhUpdateProc->finish();
		$dbhUpdateFile->finish();
		$updBackUpSucc->finish();
		$deleteFileInfo->finish();
		$resetBackedupStat->finish();
		$dbhUpdateFileStat->finish();
		$filecountbystatus->finish();
		$findAllFilesByDir->finish();
		$getChildDirsByDir->finish();
		$dbhUpdateDirCount->finish();
		$deleteDirsByDirID->finish();
		$deleteFilesByDirID->finish();
		$selectFolderDetail->finish();
		$updExpressBackUpSucc->finish();
		$dbh->disconnect();
		exit(0);
	}
}

#*****************************************************************************************************
# Subroutine	: getConfiguration
# In Param		: item: string
# Out Param		: String
# Objective		: Get the configuration from configuration table
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getConfiguration {
	return 0 if(!$_[0]);

	$selconf->execute($_[0]);
	my $conf	= $selconf->fetchrow_hashref;
	$selconf->finish();

	return $conf->{'CONF_VAL'} if(defined($conf->{'CONF_VAL'}));
	return undef;
}

#*****************************************************************************************************
# Subroutine	: addConfiguration
# In Param		: item: string, val: string
# Out Param		: Boolean
# Objective		: Adds the configuration to configuration table
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub addConfiguration {
	return 0 if(!$_[0] || !defined($_[1]));
	
	my ($conf, $confval) = ($_[0], $_[1]);
	my $exconf	= getConfiguration($conf);

	return updateConfiguration($conf, $confval) if(defined($exconf));

	# Add
	eval { $insconf->execute($conf, $confval); };
	return ($@ || $insconf->errstr)? 0 : 1;
}

#*****************************************************************************************************
# Subroutine	: updateConfiguration
# In Param		: item: string, val: string
# Out Param		: Boolean
# Objective		: Updates the configuration to configuration table
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub updateConfiguration {
	return 0 if(!$_[0] || !defined($_[1]));
	
	my ($conf, $confval) = ($_[0], $_[1]);
	
	# upddate
	eval { $updconf->execute($conf, $confval); };
	return ($@ || $updconf->errstr)? 0 : 1;
}

#*****************************************************************************************************
# Subroutine	: getAllConfigurations
# In Param		: UNDEF
# Out Param		: HASH | All configurations
# Objective		: Gets the list of configurations
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getAllConfigurations {
	my %confs = ();

	$selallconf->execute();
	while(my $conf = $selallconf->fetchrow_hashref) {
		$confs{$conf->{'CONF_NAME'}} = $conf->{'CONF_VAL'};
	}

	$selallconf->finish();

	return \%confs;
}

#*****************************************************************************************************
# Subroutine	: checkAndResetDB
# In Param		: UNDEF
# Out Param		: Status | Boolean
# Objective		: Checks and cleans up the database tables
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub checkAndResetDB {
	my $bkpsitems = getBackupsetItemsWithStats();
	return 0 if(%{$bkpsitems});

	cleanupFiles();
	cleanupDirectories();

	return 1;
}

#*****************************************************************************************************
# Subroutine	: cleanupFiles
# In Param		: UNDEF
# Out Param		: Status | Boolean
# Objective		: Cleans up all the files
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub cleanupFiles {
	eval {
		$delallfiles->execute();
		1;
	};

	return ($@ || $delallfiles->errstr)? 0 : 1;
}

#*****************************************************************************************************
# Subroutine	: cleanupDirectories
# In Param		: UNDEF
# Out Param		: Status | Boolean
# Objective		: Cleans up all the directories
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub cleanupDirectories {
	eval {
		$delalldirs->execute();
		1;
	};

	return ($@ || $delalldirs->errstr)? 0 : 1;
}

#*************************************************************************************
# Subroutine		: dirExistsInDB
# Objective			: This subroutine checks if dir present in db or not
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#**************************************************************************************
sub dirExistsInDB {
	return 0 if(!$_[0]);

	my $keyString = substr($_[0], 0, rindex($_[0], '/')) . '/';
	my $fieldMPC  = ($_[1] eq '/' && substr($keyString, 0, 1) eq '/')? '' : $_[1];
	my $searchItem = "\'" . $fieldMPC . $keyString . "\'";
	utf8::decode($searchItem);

	my $dirID = $dbh->selectrow_array("SELECT DIRID FROM ibfolder WHERE NAME = ?", undef, $searchItem);
	$dirID = $dirID? int($dirID) : 0;

	if($dirID) {
		my ($modtime, $fieldSize) = Common::getSizeLMD($keyString);
		updateIbFolder(1, $searchItem, $modtime, $fieldSize, 0);
	}

	return $dirID;
}

#********************************************************************************
# Subroutine		: getBackupFilesByKilo
# Objective			: Retrieves the backup set files for backup
# Added By			: Sabin Cheruvattil
#********************************************************************************
sub getBackupFilesByKilo {
	my $item			= $_[0];

	return 0 if(!$item);

	my $iscdp			= $_[1]? 1 : 0;
	my $dedup			= $_[2]? 1 : 0;
	my $prepsql			= '';
	my $sqlop;

	if($iscdp) {
		$prepsql		= sprintf($cdpBackupsetquery, $AppConfig::dbfilestats{'CDP'});
	} else {
		# For now keep the statuses as it is. For Non-Dedup it may get changed
		my $bkpstats	= qq($AppConfig::dbfilestats{'NEW'}, $AppConfig::dbfilestats{'MODIFIED'}, $AppConfig::dbfilestats{'DELETED'}, $AppConfig::dbfilestats{'CDP'});
		$prepsql		= sprintf($backupsetquery, $bkpstats);
	}

	utf8::decode($item);
	$sqlop				= $dbh->prepare($prepsql);
	$sqlop->execute("'$item%'");

	return $sqlop; 
}

#**************************************************************************************
# Subroutine		: getExpressBackupFilesByKilo
# Objective			: Retrieves the express backup set files batch by batch
# Added By			: Sabin Cheruvattil
#**************************************************************************************
sub getExpressBackupFilesByKilo {
	my $item			= $_[0];

	return 0 if(!$item);

	my $prepsql			= '';
	my $sqlop;
	my %bkpfiles;

	my $bkpstats	= qq($AppConfig::dbfilestats{'NEW'}, $AppConfig::dbfilestats{'MODIFIED'}, $AppConfig::dbfilestats{'DELETED'}, $AppConfig::dbfilestats{'CDP'});
	$prepsql		= sprintf($backupsetquery, $bkpstats);

	utf8::decode($item);
	$sqlop			= $dbh->prepare($prepsql);
	$sqlop->execute("'$item%'");

	return $sqlop;
}

#*****************************************************************************************************
# Subroutine	: addToBackupSet
# In Param		: item: string, type: string, exists: boolean
# Out Param		: Boolean
# Objective		: Adds the resource to backup set items
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub addToBackupSet {
	return 0 if(!$_[0] || !defined($_[1]) || !defined($_[2]) || !defined($_[3]));
	
	my ($item, $type, $stat, $lmd) = ($_[0], $_[1], $_[2], $_[3]);
	
	$selbkpsetitem->execute($item);
	my $itemdat	= $selbkpsetitem->fetchrow_hashref;
	$selbkpsetitem->finish();

	unless($itemdat->{'ITEM_ID'}) {
		# add
		eval { $addbkpitem->execute($item, $type, $stat, $lmd); };
		return ($@ || $addbkpitem->errstr)? 0 : 1;
	}
	
	# update
	eval { $updbkpitem->execute($type, $stat, $lmd, $itemdat->{'ITEM_ID'}); };
	return ($@ || $updbkpitem->errstr)? 0 : 1;
}

#*****************************************************************************************************
# Subroutine	: isThisDirIncForCDP
# In Param		: item[resource path] | String
# Out Param		: Mixed
# Objective		: Checks if all the items in directory are included in CDP
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub isThisDirIncForCDP {
	my $path	= $_[0];
	return 0 unless($path);

	my $dirid	= getDirID($path);
	my $cdpc	= getFCByDirIDAndStatus($dirid, $AppConfig::dbfilestats{'CDP'});
	my $dirfc	= getFCByDirID($dirid);

	return ($cdpc == $dirfc)? 1 : 0;
}

#*****************************************************************************************************
# Subroutine	: getFCByDirID
# In Param		: DIRID | Integer
# Out Param		: Integer | Count
# Objective		: Gets the count of files in directory by directory id
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getFCByDirID {
	my $dirid = $_[0];
	return 0 unless($dirid);

	$fcbydirid->execute($dirid);
	my $itemdat = $fcbydirid->fetchrow_hashref;
	$fcbydirid->finish();

	return $itemdat->{'FC'} if($itemdat->{'FC'});
	return 0;
}

#*****************************************************************************************************
# Subroutine	: getFCByDirIDAndStatus
# In Param		: DIRID | Integer, Status | Integer
# Out Param		: Integer | Count
# Objective		: Gets the count of files in directory by directory id and status
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getFCByDirIDAndStatus {
	my ($dirid, $stat) = ($_[0], $_[1]);
	return 0 if(!$dirid || !$stat);

	$fcbydiridandstat->execute($dirid, $stat);
	my $itemdat = $fcbydiridandstat->fetchrow_hashref;
	$fcbydiridandstat->finish();

	return $itemdat->{'FC'} if($itemdat->{'FC'});
	return 0;
}

#*****************************************************************************************************
# Subroutine	: deleteFromBackupSet
# In Param		: item[resource path] | String
# Out Param		: Boolean | Status
# Objective		: Deletes the entry from DB
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub deleteFromBackupSet {
	return 0 unless($_[0]);

	my $item = $_[0];
	eval {
		$delbkpsetitem->execute($item);
		1;
	};

	return ($@ || $delbkpsetitem->errstr)? 0 : 1;
}

#*****************************************************************************************************
# Subroutine	: getBackupsetItemsWithStats
# In Param		: UNDEF
# Out Param		: HASH | Backup set items with status
# Objective		: Gets the list of backup set items with status and type
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getBackupsetItemsWithStats {
	my %bkpitems = ();

	$selallbkpsetitems->execute();
	while(my $bkpelem = $selallbkpsetitems->fetchrow_hashref) {
		$bkpitems{$bkpelem->{'ITEM_NAME'}} = {'stat' => $bkpelem->{'ITEM_STATUS'}, 'type' => $bkpelem->{'ITEM_TYPE'}, 'lmd' => $bkpelem->{'ITEM_LMD'}};
	}

	$selallbkpsetitems->finish();

	return \%bkpitems;
}

#*****************************************************************************************************
# Subroutine	: getExpressBackedupFiles
# In Param		: NULL
# Out Param		: SQLite Resource
# Objective		: Returns the resource handler for file selection
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getExpressBackedupFiles {
	$selExpressFiles->execute();
	return $selExpressFiles;
}

#******************************************************************************
# Subroutine		: getConsideredFilesCount
# Objective			: Gets the considered count of entries for backup
# Added By			: Sabin Cheruvattil
#******************************************************************************
sub getConsideredFilesCount {
	$selconscount->execute();
	my $itemdat = $selconscount->fetchrow_hashref;
	$selconscount->finish();

	return $itemdat->{'FC'} if(defined($itemdat->{'FC'}));
	return 0;
}

#**********************************************************************
# Subroutine		: getCDPItemsCount
# Objective			: Gets the count of entries for CDP
# Added By			: Sabin Cheruvattil
#**********************************************************************
sub getCDPItemsCount {
	return getFileCountByStatus($AppConfig::dbfilestats{'CDP'});
}

#******************************************************************************
# Subroutine		: getReadySyncedCount
# Objective			: Gets the already synced count of file entries
# Added By			: Sabin Cheruvattil
#******************************************************************************
sub getReadySyncedCount {
	return getFileCountByStatus($AppConfig::dbfilestats{'BACKEDUP'});
}

#*****************************************************************************************************
# Subroutine	: getExcludedCount
# In Param		: 
# Out Param		: Count of excluded files | Integer
# Objective		: Gets back excluded file count
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getExcludedCount {
	return getFileCountByStatus($AppConfig::dbfilestats{'EXCLUDED'});
}

#***********************************************************************************
# Subroutine		: hasExcludedItems
# Objective			: Checks if the DB has excluded items
# Added By			: Sabin Cheruvattil
#***********************************************************************************
sub hasExcludedItems {
	return getFileCountByStatus($AppConfig::dbfilestats{'EXCLUDED'})? 1 : 0;
}

#***********************************************************************************
# Subroutine		: getFileCountByStatus
# Objective			: Gets the already synced count of file entries
# Added By			: Sabin Cheruvattil
#***********************************************************************************
sub getFileCountByStatus {
	return 0 unless(defined($_[0]));

	$filecountbystatus->execute($_[0]);
	my $itemdat = $filecountbystatus->fetchrow_hashref;
	$filecountbystatus->finish();

	return $itemdat->{'FC'} if(defined($itemdat->{'FC'}));
	return 0;
}

#*****************************************************************************************************
# Subroutine	: getAllFileCount
# In Param		: UNDEF
# Out Param		: Count | Integer
# Objective		: Gets the total number of files in the DB
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getAllFileCount {
	$selallfc->execute();
	my $itemdat = $selallfc->fetchrow_hashref;
	$selallfc->finish();

	return $itemdat->{'FC'} if(defined($itemdat->{'FC'}));
	return 0;
}

#****************************************************************************************************
# Subroutine		: resetBackedupStatusNew
# Objective			: Resets the backup status if the mount path is getting changed except excluded
# Added By			: Sabin Cheruvattil
#****************************************************************************************************
sub resetBackedupStatusNew {
	eval {
		$resetBackedupStat->execute();
	};

	return 0 if($@ || $resetBackedupStat->errstr);
	return 1;
}

#********************************************************************************
# Subroutine		: getDirectorySizeAndCount
# Objective			: Gets the directory size and number of files
# Added By			: Sabin Cheruvattil
#********************************************************************************
sub getDirectorySizeAndCount {
	my $item		= $_[0];
	my $dirattr		= {'size' => 0, 'filecount' => 0};

	return $dirattr if(!$item);

	utf8::decode($item);
	$item =~ s/\_/\\_/g;
	$selfcds->execute("'$item%'");

	my $dirdata				= $selfcds->fetchrow_hashref;
	$dirattr->{'size'}		= $dirdata->{'FS'} if(defined($dirdata->{'FS'}) && $dirdata->{'FS'} > 0);
	$dirattr->{'filecount'}	= $dirdata->{'FC'} if(defined($dirdata->{'FC'}) && $dirdata->{'FC'} > 0);
	
	$selfcds->finish();
	return $dirattr;
}

#*****************************************************************************************************
# Subroutine	: getBackedupCountUnderDir
# In Param		: Directory | String
# Out Param		: Count | Integer
# Objective		: Gets the total number of files in sync
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getBackedupCountUnderDir {
	my $item		= $_[0];

	return 0 if(!$item);

	utf8::decode($item);
	$item =~ s/\_/\\_/g;
	$selfcbkdup->execute("'$item%'");

	my $dirdata = $selfcbkdup->fetchrow_hashref;
	my $filecount = 0;
	$filecount = $dirdata->{'FC'} if(defined($dirdata->{'FC'}) && $dirdata->{'FC'} > 0);
	
	$selfcbkdup->finish();
	return $filecount;
}

#********************************************************************************
# Subroutine		: updateFileBackupStatus
# Objective			: Update DB file status by file ID
# Added By			: Sabin Cheruvattil
#********************************************************************************
sub updateFileBackupStatus {
	eval {
		$dbhUpdateFileStat->execute($_[1], $_[0]);
	};

	# return 0 if($@ || $dbhUpdateFileStat->rows <= 0);
	return ($@ || $dbhUpdateFileStat->errstr)? 0 : 1;
}

#**********************************************************************************
# Subroutine		: updateFileNotBackedup
# Objective			: Update DB file status by file path
# Added By			: Sabin Cheruvattil
#**********************************************************************************
sub updateFileNotBackedup {
	my $fileid = getFileIDByFilePath($_[0]);

	return updateFileBackupStatus($fileid, $AppConfig::dbfilestats{'NEW'}) if($fileid);
	return 0;
}

#*******************************************************************************
# Subroutine		: updateDirNotBackedup
# Objective			: Update DB file status by directory path
# Added By			: Sabin Cheruvattil
#*******************************************************************************
sub updateDirNotBackedup {
	return 0 unless($_[0]);

	my ($dirpath, $fid) = ($_[0], 0);
	$dirpath .= '/' if(substr($dirpath, -1, 1) ne '/');

	utf8::decode($dirpath);
	$dirpath =~s/\_/\\_/g;
	$findAllFilesByDir->execute("'$dirpath%'");
	while(my $filedata = $findAllFilesByDir->fetchrow_hashref) {
		$fid = (defined($filedata->{'FID'}))? $filedata->{'FID'} : 0;

		# Check and exclude the file entry in DB
		updateFileBackupStatus($fid, $AppConfig::dbfilestats{'NEW'}) if($fid);
	}

	$findAllFilesByDir->finish();

	return 1;
}

#*************************************************************************************
# Subroutine		: updateCloudFileDelete
# Objective			: Update DB file status as deleted by file path
# Added By			: Sabin Cheruvattil
#*************************************************************************************
sub updateCloudFileDelete {
	my $fileinfo = getFileInfoByFilePath($_[0]);

	return updateFileBackupStatus($fileinfo->{'FILEID'}, $AppConfig::dbfilestats{'DELETED'}) if($fileinfo->{'FILEID'} && $fileinfo->{'BACKUP_STATUS'} ne $AppConfig::dbfilestats{'EXCLUDED'});
	return 0;
}

#*******************************************************************************
# Subroutine		: updateCloudDirDelete
# Objective			: Update DB file status as deleted by directory path
# Added By			: Sabin Cheruvattil
#*******************************************************************************
sub updateCloudDirDelete {
	return 0 unless($_[0]);

	my ($dirpath, $fid, $opstat, $commstat) = ($_[0], 0, 1, 1);
	$dirpath .= '/' if(substr($dirpath, -1, 1) ne '/');

	utf8::decode($dirpath);
	$findAllFilesByDir->execute("'$dirpath%'");
	while(my $filedata = $findAllFilesByDir->fetchrow_hashref) {
		$fid = (defined($filedata->{'FID'}))? $filedata->{'FID'} : 0;

		# Check and exclude the file entry in DB
		$opstat = updateFileBackupStatus($fid, $AppConfig::dbfilestats{'DELETED'}) if($fid && $filedata->{'BACKUP_STATUS'} ne $AppConfig::dbfilestats{'EXCLUDED'});
		$commstat = 0 unless($opstat);
	}

	$findAllFilesByDir->finish();

	return $commstat;
}

#*************************************************************************************************
# Subroutine		: renewDBUpdateExcludeStat
# Objective			: Parses the DB and updates the file status to excluded if entry is matching 
# Added By			: Sabin Cheruvattil
#*************************************************************************************************
sub renewDBUpdateExcludeStat {
	Common::loadUserConfiguration();
	Common::loadFullExclude();
	Common::loadPartialExclude();
	Common::loadRegexExclude();

	my $showhidden = Common::getUserConfiguration('SHOWHIDDEN');
	my ($dirpath, $filename, $filepath, $fid) = ('', '', '', 0);
	my $extype	= $_[0]? 'all' : $_[0];
	my $commstat = 1;
	my $opstat	= 1;

	$findAllFilesByDir->execute("'/%'");
	while(my $filedata = $findAllFilesByDir->fetchrow_hashref) {
		$dirpath	= (defined($filedata->{'DNAME'}))? $filedata->{'DNAME'} : '';
		$dirpath	=~ s/^'//i;
		$dirpath	=~ s/'$//i;

		$filename	= (defined($filedata->{'FNAME'}))? $filedata->{'FNAME'} : '';
		$filename	=~ s/^'//i;
		$filename	=~ s/'$//i;

		$fid		= (defined($filedata->{'FID'}))? $filedata->{'FID'} : 0;
		$filepath	= Common::getCatfile($dirpath, $filename);

		# Check and exclude the file entry in DB
		if(Common::isThisExcludedItemSet($filepath . '/', $showhidden, $extype)) {
			$opstat = updateFileBackupStatus($fid, $AppConfig::dbfilestats{'EXCLUDED'});
			$commstat = 0 unless($opstat);
		} elsif($filedata->{'BACKUP_STATUS'} && $filedata->{'BACKUP_STATUS'} == $AppConfig::dbfilestats{'EXCLUDED'} && !Common::isThisExcludedItemSet($filepath . '/', $showhidden, 'all')) {
			$opstat = updateFileBackupStatus($fid, $AppConfig::dbfilestats{'NEW'});
			$commstat = 0 unless($opstat);
		}
	}

	$findAllFilesByDir->finish();

	return $commstat;
}

#****************************************************************************
# Subroutine		: hasItemsForCDP
# Objective			: Checks if any entry is present for CDP
# Added By			: Sabin Cheruvattil
#****************************************************************************
sub hasItemsForCDP {
	return getCDPItemsCount()? 1 : 0;
}

#********************************************************************
# Subroutine		: getSubDirsByID
# Objective			: Gets the list of sub directories
# Added By			: Sabin Cheruvattil
#********************************************************************
sub getSubDirsByID {
	return [] unless($_[0]);

	my $dirid = $_[0];
	my @subdirs;
	$selsubdirs->execute($dirid);
	
	while(my $sdir = $selsubdirs->fetchrow_hashref) {
		my $dirpath		= (defined($sdir->{'NAME'}))? $sdir->{'NAME'} : '';
		$dirpath		=~ s/^'//i;
		$dirpath		=~ s/'$//i;

		push(@subdirs, $dirpath);
	}
	
	$selsubdirs->finish();
	return \@subdirs;
}

#***************************************************************************************************
# Subroutine		: deleteDirsAndFilesByDirName
# Objective			: Deletes files/directories under the directory and current directory
# Added By			: Sabin Cheruvattil
#***************************************************************************************************
sub deleteDirsAndFilesByDirName {
	return 0 unless($_[0]);

	utf8::decode($_[0]);

	my @dirrow;
	my $dirname = "\'" . $_[0] . "%\'";

	$getChildDirsByDir->execute($dirname);
	while(@dirrow = $getChildDirsByDir->fetchrow_array()) {
		$deleteFilesByDirID->execute($dirrow[0]);
		$deleteDirsByDirID->execute($dirrow[0]);
	}

	$getChildDirsByDir->finish();

	return 0 if($@ || $deleteFilesByDirID->errstr || $deleteDirsByDirID->errstr);
	return 1;
}

#***************************************************************************************
# Subroutine		: updateBackUpSuccess
# Objective			: Update the file status as backed up
# Added By			: Sabin Cheruvattil
#***************************************************************************************
sub updateBackUpSuccess {
	return 0 unless($_[0]);
	my $fid			= getFileIDByFilePath($_[0]);
	my $cmplmd		= $_[1];

	eval {
		$updBackUpSucc->execute($fid, $cmplmd) if($fid);
	};
	
	return 0 if($@ || $updBackUpSucc->errstr || !$fid);
	return 1;
}

#******************************************************************************************************************
# Subroutine		: updateExpressBackUpSuccess
# Objective			: Update the file status and related things in express backup db
# Added By			: Sabin Cheruvattil
#******************************************************************************************************************
sub updateExpressBackUpSuccess {
	return 0 unless($_[0]);

	my $filepath	= $_[0];
	my $idfile		= $_[1];
	my $encname		= $_[2];
	my $fid			= getFileIDByFilePath($filepath);
	
	eval {
		$updExpressBackUpSucc->execute($idfile, $encname, $fid);
	};

	return 0 if($@ || $updExpressBackUpSucc->errstr || !$fid);
	return 1;
}

#******************************************************************************************************************
# Subroutine		: updateExpressBackUpSuccessByFID
# Objective			: Update the file status and related things in express backup db
# Added By			: Sabin Cheruvattil
#******************************************************************************************************************
# sub updateExpressBackUpSuccessByFID {
	# return 0 unless($_[0]);

	# my $fid			= $_[0];
	# my $idfile		= $_[1];
	# my $mpc			= $_[2];
	# my $encname		= $_[3];
	
	# eval {
		# $updExpressBackUpSucc->execute($idfile, $mpc, $encname, $fid);
	# };

	# return 0 if($@ || $updExpressBackUpSucc->rows <= 0);
	# return 1;
# }

#******************************************************************************************************************
# Subroutine		: insertDirectories
# Objective			: This subroutine inserts dir record to db
# Added By			: Sabin Cheruvattil
#******************************************************************************************************************
sub insertDirectories {
	return 0 unless($_[0]);

	my $insitem	= $_[0];
	my @dirfrag	= split('/', substr($insitem, 0, rindex($insitem, '/')) . '/');
	my ($catdir, $parent) = ($insitem, 0);
	my @insdirs;

	for(my $didx = $#dirfrag; $didx >= 0; $didx--) {
		$catdir = substr($catdir, 0, rindex($catdir, '/'));
		unless($parent = getDirID($catdir . '/')) {
			unshift(@insdirs, $catdir . '/');
			next;
		}

		last;
	}

	for my $diridx (0 .. $#insdirs) {
		my ($mtime, $flsize) = Common::getSizeLMD($insdirs[$diridx]);
		$parent = insertDirectory(1, "\'" . $insdirs[$diridx] . "\'", $mtime, $flsize, $parent);
	}

	return getDirID($insitem);
}

#*************************************************************************************
# Subroutine		: closeDB
# Objective			: This subroutine closes the DB connection
# Added By			: Sabin Cheruvattil
#*************************************************************************************
sub closeDB {
my ($package, $filename, $line) = caller;
	# Common::traceLog(['closing DB: ' . $localDB . '# from: ' . $filename . '# line: ' . $line, "\n\n"]);
	$dbh->disconnect();
}

#*************************************************************************************
# Subroutine		: getLastProcess
# Objective			: Gets the last record of process table
# Added By			: Sabin Cheruvattil
# Modified By 		: Senthil Pandian
#*************************************************************************************
sub getLastProcess {
	my %procdata = ();
	my $selProcData = $dbh->prepare("SELECT * FROM $ibProcess WHERE 1 ORDER BY PROCESSID DESC LIMIT 1");

	eval {
		$selProcData->execute();
		1;
	};

	my $proc	= $selProcData->fetchrow_hashref;
	$procdata{'start'}	= defined($proc->{'START_TIME'})? $proc->{'START_TIME'} : '';
	$procdata{'end'}	= defined($proc->{'END_TIME'})? $proc->{'END_TIME'} : '';
	$selProcData->finish();

	return \%procdata;
}

#*************************************************************************************
# Subroutine		: getDirID
# Objective			: This subroutine returns the dirID of full folder path
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub getDirID {
	return 0 unless($_[0]);

	my $keyString = $_[0];
	my $folderPath = substr($keyString, 0, rindex($keyString, '/')) . '/';
	my $finalPath = "\'" . $folderPath . "\'";
	
	utf8::decode($finalPath);
	$selDirID->execute($finalPath);

	my $dir = $selDirID->fetchrow_hashref;
	my $dirID = (defined($dir->{DIRID}))? $dir->{DIRID} : '';
	$dirID = 0 if($dirID eq "");
	$selDirID->finish();

	return $dirID;
}

#*************************************************************************************
# Subroutine		: isPathDirID
# Objective			: This subroutine returns the dirID of full folder path
# Added By			: Sabin Cheruvattil
#*************************************************************************************
sub isPathDir {
	return 0 unless($_[0]);

	my $path = $_[0];
	utf8::decode($path);

	$path = "\'" . $path . "\'";
	$selDirID->execute($path);

	my $dir = $selDirID->fetchrow_hashref;
	my $dirid = (defined($dir->{DIRID}))? $dir->{DIRID} : '';
	$selDirID->finish();
	$dirid = 0 if($dirid eq "");

	return $dirid;
}

#*************************************************************************************
# Subroutine		: getFileIDByFilePath
# Objective			: This subroutine returns the file ID using full file path
# Added By			: Sabin Cheruvattil
#*************************************************************************************
sub getFileIDByFilePath {
	return 0 unless($_[0]);

	my $dirid = getDirID($_[0]);
	return 0 unless($dirid);

	my @fileinfo = fileparse($_[0]);
	my $res = getFileInfo($dirid, $fileinfo[0]);

	return $res->{'FILEID'} if($res && $res->{'FILEID'});
	return 0;
}

#*****************************************************************************************************
# Subroutine	: getFileInfoByFilePath
# In Param		: File path | String
# Out Param		: File Info | Hash
# Objective		: Gets the file info using file path
# Added By		: Sabin Cheruvattil
# Modified By	: 
#*****************************************************************************************************
sub getFileInfoByFilePath {
	my $fobj = {'FILEID' => 0, 'FILE_SIZE' => 0, 'BACKUP_STATUS' => -1, 'FILE_LMD' => 0};

	return $fobj unless($_[0]);

	my $dirid = getDirID($_[0]);
	return $fobj unless($dirid);

	my $tmpfinfo = getFileInfo($dirid, basename($_[0]));
	return $fobj unless($tmpfinfo);

	$fobj->{'FILEID'}			= $tmpfinfo->{'FILEID'};
	$fobj->{'FILE_LMD'}			= $tmpfinfo->{'FILE_LMD'};
	$fobj->{'FILE_SIZE'}		= $tmpfinfo->{'FILE_SIZE'};
	$fobj->{'BACKUP_STATUS'}	= $tmpfinfo->{'BACKUP_STATUS'};

	return $fobj;
}

#*************************************************************************************
# Subroutine		: checkItemInDB
# Objective			: This subroutine checks for the passed item in db
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub checkItemInDB {
	return '' unless($_[0]);

	my $itemName = $_[0];
	my ($parentDirID, $dirID);

	$parentDirID = dirExistsInDB($itemName, '');

	return '' unless($parentDirID);
	return $itemName if(substr($itemName, -1, 1) eq '/');
	
	$dirID = dirExistsInDB($itemName . "/", '');
	return $itemName . "/" if($dirID);

	my @fileinfo = fileparse($itemName);
	my $res = getFileInfo($parentDirID, $fileinfo[0]);
	return $itemName if($res);

	return '';
}

#*************************************************************************************
# Subroutine		: insertIbFile
# Objective			: This subroutine inserts file to table
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub insertIbFile {
	eval {
		my $rows = $dbhInsertFile->execute($_[1], $_[2], $_[3], $_[4], $_[5]);
	};

	# if($@ or $dbhInsertFile->rows <= 0) {
	if($@ or $dbhInsertFile->errstr) {
		return updateIbFile(0, $_[1], $_[2], $_[3], $_[4], $_[5]) if($_[0] eq AppConfig::TRY_UPDATE);
		return 0;
	}

	$dbhInsertFile->finish();
	return 1;
}

#*************************************************************************************
# Subroutine		: insertDirectory
# Objective			: This subroutine inserts directory to table
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub insertDirectory {
	my $insid = 0;
	eval {
		my $rows = $dbhInsertDir->execute($_[1], $_[2], $_[3], $_[4]);
	};
	
	if($@ or $dbhInsertDir->rows <= 0) {
		$insid = updateIbFolder(0, $_[1], $_[2], $_[3], $_[4]) if(AppConfig::TRY_UPDATE eq $_[0]);
	} else {
		$insid = $dbh->sqlite_last_insert_rowid;
	}

	return $insid;
}

#*************************************************************************************
# Subroutine		: getFileInfo
# Objective			: This subroutine inserts directory to table
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub getFileInfo {
	my $dirID		= $_[0];
	my $fileName	= $_[1];
	my $finalPath	= "\'" . $fileName . "\'";
	utf8::decode($finalPath);

	$selFileInfo->execute($finalPath, $dirID);
	my $finfo = $selFileInfo->fetchrow_hashref;

	$selFileInfo->finish();
	return 0 unless($finfo);

	return $finfo; 
}

#*************************************************************************************
# Subroutine		: updateIbFolder
# Objective			: This subroutine updates the directory data
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub updateIbFolder {
	my $updid;
	eval {
		$dbhUpdateDir->execute($_[2], $_[3], $_[1]);
	};
	
	if($@ or $dbhUpdateDir->rows <= 0) {
		$updid = insertDirectory(0, $_[1],$_[2],$_[3],$_[4]) if(AppConfig::TRY_UPDATE == $_[0]);
	} else {
		$updid = getDirID($_[1]);
	}
	
	return $updid;
}

#*************************************************************************************
# Subroutine		: updateIbFolderCount
# Objective			: This subroutine updates directory count
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub updateIbFolderCount {
	eval {
		$dbhUpdateDirCount->execute($_[0], $_[1], $_[2]);
	};
}

#*************************************************************************************
# Subroutine		: updateIbFile
# Objective			: This subroutine updates directory count
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub updateIbFile {	
	eval {
		my $rows = $dbhUpdateFile->execute($_[3], $_[4], $_[5], $_[2], $_[1]);
	};
	
	if($@ or $dbhUpdateFile->errstr || $dbhUpdateFile->rows <= 0) {
		return insertIbFile(0, $_[1], $_[2], $_[3], $_[4], $_[5]) if($_[0] == AppConfig::TRY_UPDATE);
		return 0;
	}

	return 1;
}

#*************************************************************************************
# Subroutine		: beginDBProcess
# Objective			: This subroutine begin db process
# Added By			: Vijay Vinoth
#*************************************************************************************
sub beginDBProcess {
	$dbh->do('BEGIN');
}

#*************************************************************************************
# Subroutine		: reBeginDBProcess
# Objective			: This subroutine commit and begin db process
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub reBeginDBProcess {
	my $stat;
	$stat = commitDBProcess($_[0]);
	$dbh->do('BEGIN');
	return $stat;
}

#*************************************************************************************
# Subroutine		: commitDBProcess
# Objective			: This subroutine commit db process
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub commitDBProcess {
	unless($dbh->do('COMMIT')) {
		Common::traceLog('Commit failed.');
		Common::traceLog($_[0]) if($_[0]);
		return 0;
	}

	return 1;
}

#*************************************************************************************
# Subroutine		: fileListInDbDir
# Objective			: This subroutine get files in a dir read from DB
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub fileListInDbDir {
	utf8::decode($_[0]);

	my $searchItem = "\'" . $_[0] . "\'";
	$selectFolderDetail->execute($searchItem);
	my @row;
	my %fileListHash;
	while (@row = $selectFolderDetail->fetchrow_array()) {
		my ($NAME, $FILE_LMD, $FILE_SIZE, $DIRID, $bkpstat)	= @row;
		$fileListHash{$NAME}{'FILE_LMD'}			= $FILE_LMD;
		$fileListHash{$NAME}{'FILE_SIZE'}			= $FILE_SIZE;
		$fileListHash{$NAME}{'BACKUP_STATUS'}		= $bkpstat;
		$fileListHash{$NAME}{'exist'}				= 0;
	}
	$selectFolderDetail->finish();

	return %fileListHash;
}

#*************************************************************************************
# Subroutine		: getFileListByDIRID
# Objective			: This subroutine gets files in a dir by dir id
# Added By			: Sabin Cheruvattil
#*************************************************************************************
sub getFileListByDIRID {
	my %fileListHash;
	return \%fileListHash unless($_[0]);

	my $name = '';
	$selAllFiles->execute($_[0]);
	while(my $filedata = $selAllFiles->fetchrow_hashref) {
		$name = $filedata->{'NAME'};
		next unless($name);

		$fileListHash{$name}{'FILE_LMD'}			= $filedata->{'FILE_LMD'}? $filedata->{'FILE_LMD'} : 0;
		$fileListHash{$name}{'FILE_SIZE'}			= $filedata->{'FILE_SIZE'}? $filedata->{'FILE_SIZE'} : 0;
		$fileListHash{$name}{'BACKUP_STATUS'}		= $filedata->{'BACKUP_STATUS'}? $filedata->{'BACKUP_STATUS'} : 0;
		$fileListHash{$name}{'exist'}				= 0;
	}

	$selAllFiles->finish();

	return \%fileListHash;
}

#*************************************************************************************
# Subroutine		: deleteIbFile
# Objective			: This subroutine delete file from DB
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub deleteIbFile {
	eval{
		utf8::decode($_[0]);
		my $rows = $deleteFileInfo->execute("'$_[0]'", $_[1]);
	};
	
	return 0 if($@ or $deleteFileInfo->errstr);
	return 1;
}

#*************************************************************************************
# Subroutine		: insertProcess
# Objective			: This subroutine adds a record to proc table
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub insertProcess {
	eval {
		my $rows = $dbhInsertProc->execute($_[0], $_[1]);
	};

	if($@ or $dbhInsertProc->rows <= 0) {
		return updateIbProcess($_[0], $_[1]);
	}

	return 1;
}

#*************************************************************************************
# Subroutine		: updateIbProcess
# Objective			: This subroutine updates a record in proc table
# Added By			: Vijay Vinoth
# Modified By		: Sabin Cheruvattil
#*************************************************************************************
sub updateIbProcess {
	eval {
		$dbhUpdateProc->execute($_[1], $_[0]);
	};
	
	if($@ or $dbhUpdateProc->rows <= 0) {
		return AppConfig::TRY_UPDATE == $_[0] && insertProcess($_[0], $_[1]);
	}

	return 1;
}


#################   DB Operation for Express Backup/Restore            ######################


#****************************************************************************
# Subroutine Name         : initiateExpressDBoperation
# Objective               : This subroutine initiate Express DB operation like create DB, table, transaction
# Added By                : Senthil Pandian
#*****************************************************************************
sub initiateExpressDBoperation
{
	my $dbPath = undef;
	$dbPath = $_[0] if(defined($_[0]));
	if(!createExpressDB($dbPath)){
		Common::traceLog("Create LBDB failed.");
		exit 0;
	}

	my $ibFolder = "ibfolder";
	my $ibFile   = "ibfile";

	eval{
		$selectFolderID		 = $dbh_LB->prepare("SELECT DIRID FROM $ibFolder WHERE NAME=?");
		$selectFileInfo		 = $dbh_LB->prepare("SELECT * FROM $ibFile WHERE NAME=? AND DIRID=?");
		$selectAllFile		 = $dbh_LB->prepare("SELECT * FROM $ibFile WHERE DIRID=?");
		$searchAllFileByDir	 = $dbh_LB->prepare("SELECT FOLDER_ID, ENC_NAME, ibfile.NAME as FILENAME, ibfolder.NAME as DIRNAME, ibfile.FILE_SIZE from ibfile INNER JOIN ibfolder ON ibfolder.DIRID = ibfile.DIRID where ibfolder.NAME like ?");
		$dbh_ibFolder_insert = $dbh_LB->prepare("INSERT OR IGNORE INTO $ibFolder (NAME,FILE_LMD,FILE_SIZE) values (?,?,?)");
		$dbh_ibFile_insert   = $dbh_LB->prepare("INSERT OR IGNORE INTO $ibFile (DIRID,NAME,FILE_LMD,FILE_SIZE,BKSET_LMD,SYNC_DATE,BKSET_NAME,HASH_VALUE,FOLDER_ID,MPC,ENC_NAME,FILE_OR_FOLDER,BACKUP_STATUS) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)");
		$dbh_ibFolder_update = $dbh_LB->prepare("UPDATE $ibFolder SET FILE_LMD=? WHERE NAME=?");
		$dbh_ibFile_update   = $dbh_LB->prepare("UPDATE $ibFile SET FILE_LMD=?,FILE_SIZE=? WHERE NAME=? AND FOLDER_ID=?");
		$selectBucketSize	 = $dbh_LB->prepare("SELECT TOTAL(FILE_SIZE) as TOTALSIZE FROM $ibFile");
		# $selectFileListByDir = $dbh_LB->prepare("SELECT trim(ibfile.NAME,\"'\") as FILENAME, ibfile.FILE_SIZE as FILESIZE, ibfile.FILE_LMD as MOD FROM $ibFile INNER JOIN ibfolder ON ibfolder.DIRID = ibfile.DIRID WHERE ibfolder.NAME LIKE ? ORDER BY ibfile.NAME LIMIT ?, ?");
		$selectFileListByDir = qq(SELECT trim(ibfile.NAME,\"'\") as FILENAME %s FROM $ibFile INNER JOIN ibfolder ON ibfolder.DIRID = ibfile.DIRID WHERE ibfolder.NAME LIKE ? ORDER BY ibfile.NAME %s);
		# $selectDirListByDir  = $dbh_LB->prepare("SELECT trim(NAME,\"'\") as DIRNAME, FILE_LMD as LMD FROM $ibFolder WHERE NAME IN (SELECT substr(NAME, 0, instr(substr(NAME, ?),'/') + ?) FROM $ibFolder WHERE NAME LIKE ? AND NAME NOT LIKE ? ) ORDER BY NAME");
		$selectDirListByDir  = qq(SELECT trim(NAME,\"'\") as DIRNAME %s FROM $ibFolder WHERE NAME IN (SELECT substr(NAME, 0, instr(substr(NAME, ?),'/') + ?) FROM $ibFolder WHERE NAME LIKE ? AND NAME NOT LIKE ? ) ORDER BY NAME);
		$selectDirInfo       = qq(SELECT %s FROM $ibFile INNER JOIN $ibFolder ON ibfolder.DIRID = ibfile.DIRID WHERE ibfolder.NAME LIKE ?);
#select DIRID, trim(NAME,"'") from ibfolder where NAME IN (select substr(NAME, 0, instr(substr(NAME, 79),'/')+80) AS TEST from ibfolder where NAME LIKE "'/D01637046355000178630/home/test/Senthil/IDriveForLinux_2.31/IDriveForLinux/%'" AND NAME NOT LIKE "'/D01637046355000178630/home/test/Senthil/IDriveForLinux_2.31/IDriveForLinux/'") ORDER BY NAME;	

	};

	if($@){
		my $errStr = "Error: Prepare statement failed for insert/update for Local Backup.";
		Common::traceLog($errStr);
		disconnectExpressDB() if(defined $dbh_LB);
		exit 0;
	}
}

#****************************************************************************************************
# Subroutine Name         : createExpressDB
# Objective               : This subroutine connects to the Express Backup DB and then calls function to create Table.
# Added By                : Senthil Pandian
# Modified by			  : 
#****************************************************************************************************
sub createExpressDB
{
	my $dbCreate   = 0;
	my $databaseLB = (defined($_[0]))?$_[0]:Common::getExpressDBPath();
# Common::traceLog("createExpressDB databaseLB:$databaseLB");

	my ($useridLB, $passwordLB) = ("") x 2;
    my $stat = 1;

	eval {
		my $dsnLB = "DBI:SQLite:dbname=$databaseLB";
		my %attr = (RaiseError => 1, AutoCommit => 1, PrintError => 0);
		$dbh_LB = DBI->connect($dsnLB, $useridLB, $passwordLB, \%attr);

		if(!defined $dbh_LB){
			Common::traceLog("Error : ".$DBI::errstr);
			return 0;
		}
        $dbh_LB->do('PRAGMA synchronous = OFF');
		$dbh_LB->do('PRAGMA read_uncommitted = on');
		$dbh_LB->do('PRAGMA case_sensitive_like = 1');
		$dbh_LB->do('PRAGMA journal_mode = wal'); 
		$dbh_LB->do('PRAGMA cache_size = 10240');

		1;
	} or do {
		$dberror = $DBI::errstr? $DBI::errstr : $@;
		Common::traceLog("DB Error: " . $dberror);

		if($dberror && $dberror =~ /disk is full|disk I\/O error/gi) {
			$dberror = 'disk is full';
			Common::retreat(['disk_is_full_aborting']);
			exit(1);
		}
	};

	if($@) {
		$stat = 0;
		Common::traceLog(['DB Error: ', $@]);
		$dberror = $DBI::errstr? $DBI::errstr : $@;
	}

	# For local restore, no need to create table
	# Need to be enabled later: Senthil
	# if($isLocalRestore){
		# return 1;
	# }

	# place scan request if failed to open db
	if(!$stat || !createTableExpressLB()) {
		Common::traceLog(['corrupted_db', '.', 'path: ', $databaseLB]);
		unlink($databaseLB);
		return 0;
	}
	return 1;
}

#****************************************************************************************************
# Subroutine Name         : createTableExpressLB.
# Objective               : This subroutine creates 2 tables - IbFile and IbFolder in DB only if it already does not exist
# Added By                : Senthil Pandian
#****************************************************************************************************
sub createTableExpressLB
{
# traceLog('createTableExpressLB 1');
	my $stmt = qq(CREATE TABLE IF NOT EXISTS ibfolder 
	   (DIRID integer primary key autoincrement,
	    NAME char(1024) not null,
		FILE_LMD char(256),
		FILE_SIZE __int64,
		LEVEL_NO integer DEFAULT 0,
		SYNC_DATE char(50),
		UNIQUE(NAME)););

	my $rv = $dbh_LB->do($stmt);
	if($rv < 0){
		#traceLog('create_table_ibfolder_failed',$dbh_LB::errstr);
		return 0;
	}
	$dbh_LB->do("CREATE INDEX IF NOT EXISTS ibfolder_indx on ibfolder (NAME)");

	$stmt = qq(CREATE TABLE IF NOT EXISTS ibfile 
	   (FILEID integer primary key autoincrement,
	    DIRID integer not null,
		NAME char(1024) not null,
		FILE_LMD DATETIME DEFAULT 0,
		FILE_SIZE __int64,
		FILE_OR_FOLDER integer DEFAULT 0,
		BKSET_LMD char(50),
		SYNC_DATE char(50),
		BACKUP_STATUS integer DEFAULT 0,
		BKSET_NAME char(50),
		HASH_VALUE __int64,
		THUMB integer DEFAULT 0, 
		FOLDER_ID char(1024),
		MPC char(50),
		ENC_NAME char(1024), 
		foreign key (DIRID) references ibfolder (DIRID),
		UNIQUE(DIRID, NAME)););

	$rv = $dbh_LB->do($stmt);
	if($rv < 0){
		#traceLog('create_table_ibfile_failed',$dbh_LB::errstr);
		return 0;
	}
	$dbh_LB->do("CREATE INDEX IF NOT EXISTS ibfile_indx on ibfile (NAME)");
# traceLog('createTableExpressLB 2');
	return 1;
}

#****************************************************************************
# Subroutine Name         : updateExpressIbFolder
# Objective               : This subroutine updates entry to IbFolder
# Added By                : Senthil Pandian
#*****************************************************************************
sub updateExpressIbFolder
{
	eval{
		$dbh_ibFolder_update->bind_param( 1, "$_[1]" );
		$dbh_ibFolder_update->bind_param( 2, "$_[2]" );
		$dbh_ibFolder_update->execute();
	};

	if($@ or $dbh_ibFolder_update->rows <=0) {
		#traceLog("\n Update entry to IbFolder table has failed.", __FILE__, __LINE__);
		if(AppConfig::TRY_INSERT == $_[0]){
			insertExpressIbFolder(0, $_[2], $_[1], '0');	
		}	
	}
}

#*****************************************************************************************************
# Subroutine Name         : checkFolderExistenceInExpressDB
# Objective               : This subroutine checks whether the folder path already exists in the DB. 
#							If it does, updates entry and returns the resp dirID.
# Added By                : Senthil Pandian
#*****************************************************************************************************
sub checkFolderExistenceInExpressDB
{
	my $keyString = $_[0];
	my $fieldMPC  = $_[1];
	$keyString = substr($keyString,0,rindex ($keyString, '/'))."/";
	$fieldMPC  = '' if($fieldMPC eq '/' and substr($keyString,0,1) eq '/');
	my $searchItem = "\'".$fieldMPC.$keyString."\'";
	my $rows = $dbh_LB->selectrow_array("SELECT COUNT(*) FROM IbFolder WHERE NAME = ?", undef, $searchItem);
	my $dirID = 0;
	#print "rows:$rows#\n";

	if($rows){
		my ($modtime, $fieldSize) = Common::getSizeLMD($keyString);
		updateExpressIbFolder(1, $modtime, $searchItem);
		#$dbh_LB->commit();
		$selectFolderID->execute($searchItem);
		my $dir = $selectFolderID->fetchrow_hashref;
		#print Dumper(\$dir);
		$dirID = $dir->{DIRID};
		if($dirID eq ""){
			$dirID = 0;
		}
	}
	return $dirID;
}

#********************************************************************************************
# Subroutine Name         : insertExpressFolders
# Objective               : This subroutine makes level by level folder entry into the DB 
#							and returns the dirID of the full folder path
# Added By                : Senthil Pandian
#*********************************************************************************************
sub insertExpressFolders
{	
	my $keyString  = $_[0];
	my $fileLMD	   = (defined $_[1])?$_[1]:0;
	#my $mpcName    = (substr($_[1],0,1) eq '/')?$_[1]:"/".$_[1]; #Commented to avoid too many '/' at beginning
	my $mpcName    = '';
	my $folderPath = substr($keyString,0,rindex ($keyString, '/'))."/";
	my @array = split('/', $folderPath);
	
	for(my $index = $#array ; $index >= 0; $index--){
		$keyString = substr($keyString,0,rindex ($keyString, '/'));
		my $string = $keyString."/";
		#my $searchItem = "\'".$mpcName.$string."\'"; #Commented to avoid too many '/' at beginning
		my $searchItem = "\'".$string."\'";
		my $rows = $dbh_LB->selectrow_array("SELECT COUNT(*) FROM IbFolder WHERE NAME = ?", undef, $searchItem);
		if($rows > 0){
			last;
		}else{
			my ($modtime, $fieldSize) = Common::getSizeLMD($string);
			$modtime = ($modtime!=0)?$modtime:$fileLMD;
			insertExpressIbFolder(1, $searchItem,$modtime,'0');
		}
	}
	
	#$dbh_LB->commit();

	my $dirID = getExpressDirID($_[0], $mpcName);
	return $dirID; 
}

#*************************************************************************************
# Subroutine Name         : getExpressDirID
# Objective               : This subroutine returns the dirID of full folder path
# Added By                : Senthil Pandian
#*************************************************************************************
sub getExpressDirID
{
	my $keyString = $_[0];
	my $mpcName = $_[1];
	my $folderPath = substr($keyString,0,rindex ($keyString, '/'))."/";
	my $finalPath = "\'".$mpcName.$folderPath."\'";
	#print "finalPath:$finalPath#\n";
	$selectFolderID->execute($finalPath);
	my $dir = $selectFolderID->fetchrow_hashref;
	my $dirID = (defined($dir->{DIRID}))?$dir->{DIRID}:'';
	if($dirID eq ""){
		$dirID = 0;
	}
	return $dirID; 
}

#*************************************************************************************
# Subroutine Name         : getExpressFileInfo
# Objective               : This subroutine returns the file detail
# Added By                : Senthil Pandian
#*************************************************************************************
sub getExpressFileInfo
{
	my $dirID    = $_[0];
	my $fileName = $_[1];
	#my $folderPath = substr($fileName,0,rindex ($keyString, '/'))."/";
	my $finalPath = "\'".$fileName."\'";
	$selectFileInfo->execute($finalPath,$dirID);
	my $dir = $selectFileInfo->fetchrow_hashref;
	if(!defined($dir)){
		return 0;
	}
	return $dir; 
}

#******************************************************************************
# Subroutine Name         : insertExpressIbFile
# Objective               : This subroutine inserts entry to IbFile
# Added By                : Senthil Pandian
#******************************************************************************
sub insertExpressIbFile
{
	eval{
		$dbh_ibFile_insert->bind_param( 1, "$_[1]" );
		$dbh_ibFile_insert->bind_param( 2, "$_[2]" );
		$dbh_ibFile_insert->bind_param( 3, "$_[3]" );
		$dbh_ibFile_insert->bind_param( 4, "$_[4]" );
		$dbh_ibFile_insert->bind_param( 5, "$_[5]" );
		$dbh_ibFile_insert->bind_param( 6, "$_[6]" );
		$dbh_ibFile_insert->bind_param( 7, "$_[7]" );
		$dbh_ibFile_insert->bind_param( 8, "$_[8]" );
		$dbh_ibFile_insert->bind_param( 9, "$_[9]" );
		$dbh_ibFile_insert->bind_param( 10, "$_[10]" );
		$dbh_ibFile_insert->bind_param( 11, "$_[11]" );
		$dbh_ibFile_insert->bind_param( 12, "$_[12]" );
		$dbh_ibFile_insert->bind_param( 13, "$_[13]" );

		my $rows = $dbh_ibFile_insert->execute();
	};
	if($@ or $dbh_ibFile_insert->rows <=0) {
		#traceLog("\n Update entry to IbFile table has failed.", __FILE__, __LINE__);
		if($_[0] == AppConfig::TRY_UPDATE){
			updateExpressIbFile(0, $_[3], $_[4], $_[2], $_[1]);	
		}
	}
}

#************************************************************************************
# Subroutine Name         : insertExpressIbFolder
# Objective               : This subroutine inserts entry to IbFolder
# Added By                : Senthil Pandian
#*************************************************************************************
sub insertExpressIbFolder
{
	eval{
		$dbh_ibFolder_insert->bind_param( 1, "$_[1]" );
		$dbh_ibFolder_insert->bind_param( 2, "$_[2]" );
		$dbh_ibFolder_insert->bind_param( 3, "$_[3]" );
		$dbh_ibFolder_insert->bind_param( 4, "NA" );
		my $rows = $dbh_ibFolder_insert->execute();
	};

	if($@ or $dbh_ibFolder_insert->rows <=0) {
		#traceLog("\n Update entry to IbFolder table has failed.", __FILE__, __LINE__);
		if(AppConfig::TRY_UPDATE == $_[0]){
			updateExpressIbFolder(0, $_[2], $_[1]);	
		}
	}
}

#**************************************************************************
# Subroutine Name         : updateExpressIbFile
# Objective               : This subroutine updates entry to IbFile
# Added By                : Senthil Pandian
#***************************************************************************
sub updateExpressIbFile
{
	eval{
		$dbh_ibFile_update->bind_param( 1, "$_[1]" );
		$dbh_ibFile_update->bind_param( 2, "$_[2]" );
		$dbh_ibFile_update->bind_param( 3, "$_[3]" );
		$dbh_ibFile_update->bind_param( 4, "$_[4]" );

		my $rows = $dbh_ibFile_update->execute();
	};

	if($@ or $dbh_ibFile_update->rows <=0) {
		#traceLog("\n Update entry to IbFile table has failed.", __FILE__, __LINE__);
		if($_[0] == AppConfig::TRY_INSERT){
			insertExpressIbFile(0, $_[5], $_[3], $_[1], $_[2], 'NA', 'NA', "Default Backupset", '0', $_[4], $_[6], $_[7], '1', '1');
		}
	}
}

#************************************************************************************************
# Subroutine Name         : disconnectExpressDB
# Objective               : This subroutine to finish the DB opeartion & disconnect
# Added By                : Senthil Pandian.
#************************************************************************************************
sub disconnectExpressDB
{
	if($dbh_LB){
		$selectFolderID->finish();
		$selectFileInfo->finish();
		$selectAllFile->finish();
		$searchAllFileByDir->finish();
		$dbh_ibFolder_insert->finish();
		$dbh_ibFile_insert->finish();
		$dbh_ibFolder_update->finish();
		$dbh_ibFile_update->finish();
		$selectBucketSize->finish();
		$dbh_LB->disconnect();
		$dbh_LB = undef;
	}
}

#****************************************************************************************************
# Function Name         : checkItemInExpressDB
# Objective             : check whether item is in DB or not & it will return type(file/folder) of the item
# Added By              : Senthil Pandian
#*****************************************************************************************************
sub checkItemInExpressDB {
	my $itemName = $_[0];
	my $fieldMPC =  (Common::getUserConfiguration('DEDUP') eq "on")?"/":"";
	my ($parentDirID, $dirID);
	# initiateExpressDBoperation();

	Common::replaceXMLcharacters(\$itemName);
	$parentDirID = checkFolderExistenceInExpressDB($itemName, $fieldMPC);
	if(!$parentDirID){		
		return 0; #No file/folder
	} elsif(substr($itemName,-1,1) eq '/'){
		return $itemName;
	}

	$dirID = checkFolderExistenceInExpressDB($itemName."/", $fieldMPC);
	if($dirID){
		return $itemName."/";
	} else {
		my @parentDir = fileparse($itemName);
		my $res = getExpressFileInfo($parentDirID, $parentDir[0]);
		if($res){
			$AppConfig::fileInfoDB{$itemName} = $res;
			return $itemName;
		}
		return 0; #No file/folder
	}
}

#*************************************************************************************
# Subroutine		: searchAllFilesByDir
# Objective			: This subroutine gets all files from directory & its sub-directories
# Added By			: Senthil Pandian
#*************************************************************************************
sub searchAllFilesByDir {
	my %fileListHash;
	return \%fileListHash unless($_[0]);
	my $itemName = $_[0];

	$searchAllFileByDir->execute("'$itemName%");
	return $searchAllFileByDir;
}

#*************************************************************************************
# Subroutine		: updateExpressDB
# Objective			: This subroutine to update backed up data to express database
# Added By			: Senthil Pandian
#*************************************************************************************
sub updateExpressDB {
    my $itemName 		= $_[0];
    my $fieldFolderId 	= $_[1];
    my $fieldEncName  	= $_[2];
    my $fieldMPC 		= $_[3];
    my $fieldSize 		= $_[4];
    my $modtime  		= $_[5];

    # $itemName = $remoteFolder.$itemName unless($itemName =~/\//);
    # Common::replaceXMLcharacters(\$itemName);
    # print "itemName:$backupLocation$itemName#\n";
    # $fieldMPC = $backupLocation.$fieldMPC;

    # $fieldMPC = $backupLocation;
    utf8::decode($itemName);
    $itemName	    = "/".$itemName if(substr($itemName, 0, 1) ne "/");
    $fieldMPC	    = "/".$fieldMPC if(substr($fieldMPC, 0, 1) ne "/");
    my $dirID = checkFolderExistenceInExpressDB($itemName, $fieldMPC);
    if(!$dirID){
        $dirID = insertExpressFolders($fieldMPC.$itemName);
    }
    my $fileName = (Common::fileparse($itemName))[0];
    $fileName = "'$fileName'";
    insertExpressIbFile(1, "$dirID","$fileName","$modtime","$fieldSize",'NA','NA','Default Backupset','0',"$fieldFolderId","$fieldMPC","$fieldEncName", '1', '1');
}

#*****************************************************************************************************
# Subroutine	: createTableIndexes
# Objective		: Creates the table indexes if not created
# Added By		: Senthil Pandian
#*****************************************************************************************************
sub createExpressTableIndexes {
	$dbh_LB->do("CREATE INDEX IF NOT EXISTS ibfolder_name on ibfolder (NAME)");
	$dbh_LB->do("CREATE INDEX IF NOT EXISTS ibfile_name on ibfile (NAME)");
}

#*************************************************************************************
# Subroutine		: beginExpressDBProcess
# Objective			: This subroutine begin db process
# Added By			: Senthil Pandian
#*************************************************************************************
sub beginExpressDBProcess {
	$dbh_LB->do('BEGIN');
}

#*************************************************************************************
# Subroutine		: commitExpressDBProcess
# Objective			: This subroutine commit db process
# Added By			: Senthil Pandian
#*************************************************************************************
sub commitExpressDBProcess {
	unless($dbh_LB->do('COMMIT')) {
		Common::traceLog('Express Commit failed.');
		return 0;
	}
	return 1;
}

#*************************************************************************************
# Subroutine		: getBucketSize
# Objective			: This subroutine to get & return total size of files in a bucket.
# Added By			: Senthil Pandian
#*************************************************************************************
sub getBucketSize {
	$selectBucketSize->execute();
	my $res	= $selectBucketSize->fetchrow_hashref;
	$selectBucketSize->finish();

	my $size = $res->{'TOTALSIZE'};
	return 0 if(!$size);
	return $size;
}

#*************************************************************************************
# Subroutine		: getExpressDataList
# Objective			: This subroutine to get & return local backup items list.
# Added By			: Senthil Pandian
#*************************************************************************************
sub getExpressDataList {
	my $dirName    = $_[0];
	my $outParams  = $_[1];
	my $outputFile = $_[2];
	my $folderList = $_[3];
	my $split      = $_[4];
	my $offset     = $_[5];
	my $limit      = $_[6];
	my $splitCount = ($split and !$limit)?$AppConfig::splitCount:$limit;

	# $selectDirListByDir->execute($dirID, $limit, $offset);
	# (NAME, 0, instr(substr(NAME, ?),'/')+?) FROM $ibfolder WHERE NAME LIKE ?  AND NAME NOT LIKE ? ) ORDER BY NAME LIMIT ?,?")
	# $dirName .= '/' if(substr($dirName,-1,1) ne '/');
	my $finalDirPath  = "\'".$dirName."\'";
	my $searchDirPath = "\'".$dirName."%\'";
	my $dirStrLength  = length($dirName);
	my %dirList 	  = ();
	my %fileList	  = ();
	my @dirArr 		  = ();
	my @fileArr  	  = ();
	my @outParamsArr  = ();
	
	unless(Common::reftype(\$outParams) eq 'SCALAR'){
		@outParamsArr  = @{$outParams};
	} else {
		push(@outParamsArr, $outParams);
	}

	my ($fileFields, $dirFields, $dirInfo) = ('') x 3;
	my ($needDirFilesCount, $needDirTotalSize) = (0) x 2;
	my @fileFieldsArr = ();
	my @dirFieldsArr  = ();

	if(@outParamsArr) {
		foreach (@outParamsArr) {
			if($_ eq 'DIR_FILESCOUNT') {
				$needDirFilesCount = 1;
				$dirInfo .= $AppConfig::dbFields{$_}.', ';
				push(@dirFieldsArr, $_);
			} elsif($_ eq 'DIR_TOTALSIZE') {
				$needDirTotalSize  = 1;
				$dirInfo .= $AppConfig::dbFields{$_}.', ';
				push(@dirFieldsArr, $_);
			} else {
				# next if($_ eq 'TYPE');
				if($_ =~ /^DIR_/) {
					$dirFields .= ', '.$AppConfig::dbFields{$_};
					$_ =~ s/^DIR_//;
					push(@dirFieldsArr, $_);
				} elsif(exists($AppConfig::dbFields{$_})) {
					$fileFields .= ', '.$AppConfig::dbFields{$_};
					push(@fileFieldsArr, $_);
				}
			}
		}

		if($dirInfo) {
			Common::Chomp(\$dirInfo);
			chop($dirInfo) if(substr($dirInfo, -1, 1) eq ',');
		}
	}

# my $limitStr   = ($limit)?"LIMIT $offset,$limit":'';
# Common::traceLog("$dirStrLength+2, $dirStrLength+3, $searchDirPath, $finalDirPath, $offset, $limit");

# my $prepsql	= sprintf($selectDirListByDir);
# Common::traceLog("prepsql:$prepsql");
# my $sqlop = $dbh_LB->prepare($prepsql);

	if($folderList) {
		my $sqlop;
		if($dirInfo) {
			my $prepsql	= sprintf($selectDirInfo, $dirInfo);
		# Common::traceLog("prepsql:$prepsql");
			$sqlop = $dbh_LB->prepare($prepsql);
		}

		my $dirFieldsSQL	= sprintf($selectDirListByDir, $dirFields);
		my $dirSqlOp = $dbh_LB->prepare($dirFieldsSQL);
		$dirSqlOp->execute($dirStrLength+2, $dirStrLength+3, $searchDirPath, $finalDirPath);
		my ($index, $itemsCount) = (1, 0);
		while(my $filedata = $dirSqlOp->fetchrow_hashref) {
			next unless(defined($filedata->{'DIRNAME'}));

			my $dirName = Common::removeLastSlash($filedata->{'DIRNAME'});
			$dirName = substr($dirName, $dirStrLength);

			# $dirList{$dirName} = {};
			$dirList{'path'} = $dirName;
			$dirList{'type'} = "folder";
			$dirList{'size'} = "-";
			$dirList{'lmd'}  = "-";
			if($needDirFilesCount || $needDirTotalSize) {
				$sqlop->execute("'".$filedata->{'DIRNAME'}."%");
				my $res	= $sqlop->fetchrow_hashref;
				$sqlop->finish();
				if($needDirTotalSize) {
					$dirList{'DIR_TOTALSIZE'}  = ($res->{'TOTALSIZE'})?$res->{'TOTALSIZE'}:0;
				}
				if($needDirFilesCount) {
					$dirList{'DIR_FILESCOUNT'} = ($res->{'FILESCOUNT'})?$res->{'FILESCOUNT'}:0;
				}
			}

			$itemsCount++;
			foreach (@dirFieldsArr) {
# Common::traceLog("#".$_."#");
				if(exists $filedata->{$_}) {
					$dirList{lc($_)} = $filedata->{$_};
				}
				# elsif($_ =~ /TYPE/) {
					# $dirList{$dirName}{$_} = 'd';
				# } else {
					# $dirList{$dirName}{$_} = '-';
				# }
			}
			push(@dirArr,{%dirList}) if(%dirList);
			%dirList = ();
			if($split && $itemsCount == $splitCount) {
				Common::fileWrite($outputFile.$AppConfig::localFolderList.'_'.$index, JSON::to_json(\@dirArr));
				chmod($AppConfig::filePermission, $outputFile.$AppConfig::localFolderList.'_'.$index);
				@dirArr  = ();
				$itemsCount = 0;				
				$index++;
			}			
		}

		if($split && $itemsCount) {
			Common::fileWrite($outputFile.$AppConfig::localFolderList.'_'.$index, JSON::to_json(\@dirArr));
			chmod($AppConfig::filePermission, $outputFile.$AppConfig::localFolderList.'_'.$index);
			@dirArr  = ();
		}
		$sqlop->finish() if($sqlop);
		$dirSqlOp->finish() if($dirSqlOp);
	}

	# my $dirCount = scalar(keys %dirList);
# Common::traceLog("dirCount:$dirCount");
# Common::traceLog("limit:$limit");

	# if($fields) {
		# Common::Chomp(\$fields);
		# chop($fields);
		# $fields = ", ".$fields;
	# }
# Common::traceLog("selectFileListByDir:$selectFileListByDir");
# Common::traceLog("fields:$fields");
	my $limitStr = ($limit and !$split)?"LIMIT $offset,$limit":'';
	my $prepsql	= sprintf($selectFileListByDir, $fileFields, $limitStr);
# Common::traceLog("prepsql:$prepsql");
	my $sqlop = $dbh_LB->prepare($prepsql);
	$sqlop->execute($finalDirPath);

	my ($index, $itemsCount) = (1, 0);
	while(my $filedata = $sqlop->fetchrow_hashref) {
		next unless(defined($filedata->{'FILENAME'}));
# Common::traceLog("FILENAME:".$filedata->{'FILENAME'});
		$itemsCount++;
		$fileList{'path'} = $filedata->{'FILENAME'};
		$fileList{'type'} = 'file';
		foreach (@outParamsArr) {
			if(exists $filedata->{$_}) {
# Common::traceLog("$_:".$filedata->{$_});
				$fileList{lc($_)} = $filedata->{$_};
			}
			# elsif($_ =~ /TYPE/) {
				# $fileList{$filedata->{'FILENAME'}}{$_} = 'f'; 
			# }				
		}
		push(@fileArr,{%fileList}) if(%fileList);
		%fileList = ();
		if($split and $itemsCount == $splitCount) {
			Common::fileWrite($outputFile."_".$index, JSON::to_json(\%fileList));
			chmod($AppConfig::filePermission, $outputFile."_".$index);
			@fileArr = ();
			$itemsCount = 0;				
			$index++;
		}
	}

	if($split and $itemsCount) {
		Common::fileWrite($outputFile."_".$index, JSON::to_json(\%fileList));
		chmod($AppConfig::filePermission, $outputFile."_".$index);
		@fileArr = ();
	}
	$sqlop->finish() if($sqlop);
	return (\@dirArr, \@fileArr);
}

#*************************************************************************************
# Subroutine		: checkExpressDBschema
# Objective			: This subroutine to get & return local backup items list.
# Added By			: Senthil Pandian
#*************************************************************************************
sub checkExpressDBschema {
	my $isLMDChanged = 0;
	my $sqlop = $dbh_LB->prepare("PRAGMA table_info(ibfile)");
	$sqlop->execute();
	while(my $filedata = $sqlop->fetchrow_hashref) {
		if($filedata->{'name'} eq 'FILE_LMD' and $filedata->{'type'} =~ /char/) {
			$isLMDChanged = 1;
			last;
		}
	}
	return $isLMDChanged;
}

1;