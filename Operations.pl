#!/usr/bin/env perl

###############################################################################
#Script Name : Operations.pl
###############################################################################

use lib map{if (__FILE__ =~ /\//) {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";}}else {if ($_ eq '.') {substr(__FILE__, 0, rindex(__FILE__, '/'));}else {"./$_";}}} qw(Idrivelib/lib .);

use File::stat;
use POSIX;

require "Header.pl";
#use Constants 'CONST';
require Constants;
use constant CHILD_PROCESS_STARTED => 1;
use constant CHILD_PROCESS_COMPLETED => 2;
use constant LIMIT => 2*1024;

my $operationComplete = "100%";
my $lineCount;
my $prevLineCount;

use constant false => 0;
use constant true => 1;
use constant RELATIVE => "--relative";
use constant NORELATIVE => "--no-relative";

use constant false => 0;
use constant true => 1;
my $isScheduledJob = 0;
my $failedfiles_index = 0;
my %fileSetHash = ();
# my $fileRestoreCount = 0;
my $failedfiles_count = 0;
my $deniedFilesCount = 0;
my $missingCount = 0;
my $modifiedCount = 0;
our $exit_flag = 0;
#my $retryAttempt = false; # flag to indicate the backup script to retry the backup/restore
my @currentFileset = ();
my $totalSize = Constants->CONST->{'CalCulate'};
my $parseCount = 0;
my $IncFileSizeByte = 0;
my $modSize = 0;

# CDP Data
my %dbdumpdata;
my $cdpdumpidx = 0;

# Express data
my $folderid = '';
my $mpc = '';
my $encname = '';

my $Oflag = 0;
my $fileOpenflag = 0;
my $fieldSeparator = "\\] \\[";
my $skipFlag = 0;
my $fileNotOpened = 0;
my $buffer = "";
my $byteRead = 0;
my $lastLine  = "";
my $termData = "CHILD_PROCESS_COMPLETED";
my $prevLine = undef;
my $IncFileSize = undef;
my $sizeofSIZE = undef;
my $prevFile = undef;
my $tryCount = 0;
my $updateRetainedFilesSize = 0;
my $transferredFileSize = 0;
my $isbackupop	= 0;
Common::checkAndAvoidExecution();
$param = 0;
if($#ARGV > 0)
{
	#If arg 0 is handshake param
	if($ARGV[0] eq Common::getStringConstant('support_file_exec_string'))
	{
		$param = 1;
	}
}
if(!$userName) {
	$userName = $ARGV[$param+1];
}

loadUserData();
# Reading the configurationFile - End

my $curFile = basename(__FILE__);
my $jobRunningDir = $ARGV[$param];
my $operationEngineId = $ARGV[$param+2];
my $retry_failedfiles_index = $ARGV[$param+3];
my $restoreVersion = $ARGV[$param+4];
my ($current_source)=('');
($progressSizeOp,$bwThrottle,$backupPathType) = ('') x 3;#These variables are initialized in operations subroutine after reading parameters from temp_file.
my $temp_file = "$jobRunningDir/operationsfile.txt";#This files contains value to the parameters which is used during backup, restore etc jobs. This file is written in Backup_Script.pl file and Restore_Script.pl file before call to operation file is done. In operation file various operation related to job is done.
my $pidPath = "$jobRunningDir/pid.txt";
$statusFilePath = "$jobRunningDir/STATUS_FILE";
my $retryinfo = "$jobRunningDir/".$retryinfo;
$idevsOutputFile = "$jobRunningDir/output.txt";
$idevsErrorFile = "$jobRunningDir/error.txt";
my $fileForSize = "$jobRunningDir/TotalSizeFile";
#my $incSize = "$jobRunningDir/transferredFileSize.txt";
my $trfSizeAndCountFile = "$jobRunningDir/trfSizeAndCount.txt";
my $minimalErrorRetry = "$jobRunningDir/errorretry.min";
my $errorFilePath;

my $jobHeader = undef;
my $headerLen = undef;
my $pp = undef;

# Index number for statusFileArray
use constant COUNT_FILES_INDEX => 0;
use constant SYNC_COUNT_FILES_INDEX => 1;
use constant ERROR_COUNT_FILES => 2;
use constant FAILEDFILES_LISTIDX => 3;
use constant EXIT_FLAG_INDEX => 4;

# Status File Parameters
my @statusFileArray = 	( 	"COUNT_FILES_INDEX",
							"SYNC_COUNT_FILES_INDEX",
							"ERROR_COUNT_FILES",
							"FAILEDFILES_LISTIDX",
							"EXIT_FLAG",
						);

# signal handlers
# $SIG{INT}  = \&process_term;
# $SIG{TERM} = \&process_term;
# $SIG{TSTP} = \&process_term;
# $SIG{QUIT} = \&process_term;
# $SIG{PWR}  = \&process_term;
# $SIG{KILL} = \&process_term;
# $SIG{USR1} = \&process_term;

operations();

#****************************************************************************************************
# Subroutine Name         : operations
# Objective               : Makes call to the respective functions depending on variable $operationName.
# Added By                :
# Modified By		  : Abhishek Verma.
#*****************************************************************************************************/
sub operations
{
	my @param = readParamNcronEntryFromOperationsFile();
	chomp (our $operationName = shift(@param));
	#Common::traceLog("operationName:$operationName#\n\n");
	chomp (@param) if ($operationName ne 'WRITE_TO_CRON');
	($current_source, $progressSizeOp, $bwThrottle, $backupPathType, $flagForSchdule) = ($param[3], $param[4], $param[6], $param[8], $param[9]);
	$isScheduledJob = 1 if($flagForSchdule =~ /scheduled/i);
#====================================================Operation Based on operation name==========================#
	if($operationName eq 'WRITE_TO_CRON') {
		writeToCrontab(@param);
		exit;
    }
	elsif($operationName eq 'READ_CRON_ENTRIES') {
		readFromCrontab();
		print @linesCrontab;
		exit;
	}
	elsif($operationName eq 'BACKUP_OPERATION' or $operationName eq 'LOCAL_BACKUP_OPERATION') {
		$isbackupop = 1;
		Common::fileWrite($pidPath.'_proc_'.$operationEngineId, $$);
		my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_" . $operationEngineId;
		$jobType = q(backup);
		$errorFilePath = $jobRunningDir."/exitError.txt";
		if($operationName eq 'LOCAL_BACKUP_OPERATION'){
			$jobType = q(localbackup);
			$idevsOutputFile = "$jobRunningDir/evsOutput.txt";
			$idevsErrorFile  = "$jobRunningDir/evsError.txt";
		}
		getCurrentFileSet($param[1]);
		# $trfSizeAndCountFile = $trfSizeAndCountFile."_".$operationEngineId;
		# our ($ctrf,$fileTransferCount) = readTransferRateAndCount();
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX', 'SYNC_COUNT_FILES_INDEX', 'ERROR_COUNT_FILES', 'DENIED_COUNT_FILES', 'MISSED_FILES_COUNT');
		my ($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount) = getParameterValueFromStatusFile($operationEngineId, \@StatusFileFinalArray);
		my $fileTransferCount = ($successFiles+$syncedFiles+$failedFilesCount+$noPermissionCount+$missingCount);

		our $relative = $param[2];
		$backupHost = $param[5];
		getProgressDetails($progressDetailsFilePath);
		if($dedup eq 'on'){
			BackupDedupOutputParse($param[1],$param[7],$fileTransferCount,$operationEngineId);
		} else {
			BackupOutputParse($param[1],$param[7],$fileTransferCount,$operationEngineId);
		}

		subErrorRoutine($param[1]);
		updateUserLogForBackupRestoreFiles($param[0]);
		my ($fileBackupCount, $fileSyncCount) = getCountDetails();
		writeParameterValuesToStatusFile($fileBackupCount, $fileRestoreCount, $fileSyncCount, $failedfiles_count, $deniedFilesCount, $missingCount, $modifiedCount, $transferredFileSize, $exit_flag, $failedfiles_index, $operationEngineId);
		unlink $pidPath.'_proc_'.$operationEngineId;
	}
	elsif($operationName eq 'RESTORE_OPERATION' or $operationName eq 'LOCAL_RESTORE_OPERATION') {
# Common::traceLog(Dumper(\@param));
        Common::fileWrite($pidPath.'_proc_'.$operationEngineId, $$);
		my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_" . $operationEngineId;
		$jobType = q(restore);
		$restoreHost = $param[5];
# Common::traceLog("restoreHost:$restoreHost");	
		if($operationName eq 'LOCAL_RESTORE_OPERATION'){
			$jobType = q(localrestore);
			$idevsOutputFile = "$jobRunningDir/evsOutput.txt";
			$idevsErrorFile  = "$jobRunningDir/evsError.txt";
			$pathSeparator	 = ""; #To avoid double slash at beginning of file name			
		}

		$errorFilePath = $jobRunningDir."/exitError.txt";
		getCurrentFileSet($param[1]);
        $restoreLocation = $param[6];
		# $trfSizeAndCountFile = $trfSizeAndCountFile."_".$operationEngineId;
		# our ($ctrf,$fileTransferCount) = readTransferRateAndCount();
		my @StatusFileFinalArray = ('COUNT_FILES_INDEX', 'SYNC_COUNT_FILES_INDEX', 'ERROR_COUNT_FILES', 'DENIED_COUNT_FILES', 'MISSED_FILES_COUNT');
		my ($successFiles, $syncedFiles, $failedFilesCount, $noPermissionCount, $missingCount) = getParameterValueFromStatusFile($operationEngineId, \@StatusFileFinalArray);
		my $fileTransferCount = ($successFiles+$syncedFiles+$failedFilesCount+$noPermissionCount+$missingCount);

		our $relative = $param[2];
		getProgressDetails($progressDetailsFilePath);
		if($dedup eq 'on') {
			RestoreDedupOutputParse($param[1], $param[7], $fileTransferCount, $operationEngineId);
		} else {
			RestoreOutputParse($param[1], $param[7], $fileTransferCount, $operationEngineId);
		}
		subErrorRoutine($param[1]);
		updateUserLogForBackupRestoreFiles($param[0]);
		my ($fileRestoreCount, $fileSyncCount) = getCountDetails();
		writeParameterValuesToStatusFile($fileBackupCount, $fileRestoreCount, $fileSyncCount, $failedfiles_count, $deniedFilesCount, $missingCount, $modifiedCount, $transferredFileSize, $exit_flag, $failedfiles_index, $operationEngineId);
		unlink $pidPath.'_proc_'.$operationEngineId;
	}
	else{
		Common::traceLog("$operationName: function not in this file");
        return 0;
	}
	unlink $temp_file;
	exit;
}
#****************************************************************************************************
#Subroutine Name        : readParamNcronEntryFromOperationsFile
#Objective              : This subroutine will read data from operations file into an array and return that array. Returned data is further used based on the type of operation name which is the first entry of the array.
#Usage                  : readParamNcronEntryFromOperationsFile()
#Added By               : Abhishek Verma.
#****************************************************************************************************
sub readParamNcronEntryFromOperationsFile{
	my $operationEngineIdData = '';
	$operationEngineIdData = "_".$operationEngineId if ($operationEngineId ne "");

	if (-e $temp_file . $operationEngineIdData) {
		if(!open(TEMP_FILE, "<",$temp_file.$operationEngineIdData)){
			$errStr = "Could not open file temp_file in Child process: $temp_file, Reason:$!";
			Common::traceLog($errStr);
			return 0;
		}
		my @linestemp_file = <TEMP_FILE>;
		close TEMP_FILE;
		return @linestemp_file;
    }
}
#****************************************************************************************************
#Subroutine Name        : getCurrentFileSet
#Objective              : This subroutine will get current file set from file passed as arg and insert in an array and return that array.
#Usage                  : getCurrentFileSet($curFileset)
#Added By               : Abhishek Verma.
#****************************************************************************************************
sub getCurrentFileSet{
	my $curFileset = shift;
	open FILESET, "< $curFileset" or Common::traceLog("Couldn't open file $curFileset $!.") and return;
    if($restoreVersion > 0) {
        while(<FILESET>) {
            chomp($_);
            my @splitArr = split("_IBVER", $_);
            $fileSetHash{$splitArr[0]}{'status'} = 0;
            $fileSetHash{$splitArr[0]}{'detail'} = '';
            $fileSetHash{$splitArr[0]}{'size'} = '';
            $fileSetHash{$splitArr[0]}{'ver'} = $splitArr[1];
            push @currentFileset, $splitArr[0];
        }
    } else {
		while(<FILESET>) {
			chomp($_);
			$fileSetHash{$_}{'status'} = 0;
			$fileSetHash{$_}{'detail'} = '';
			if(-f $_) {
				my $fstat = stat($_);
				$fileSetHash{$_}{'size'} = $fstat->size;
				$fileSetHash{$_}{'mts'} = $fstat->mtime;
			} else {
				$fileSetHash{$_}{'size'} = '';
				$fileSetHash{$_}{'mts'} = '';
			}

			push @currentFileset, $_;
		}
	}
	close FILESET;
}
#****************************************************************************************************
#Subroutine Name	: getCurrentErrorFile
#Objective              : This subroutine returns error file name depending upon current file set name and in respective job running directory.
#Usage 			: getCurrentErrorFile($curFileset)
#Added By               : Abhishek Verma.
#****************************************************************************************************
sub getCurrentErrorFile{
	my $curFileset = shift;
	my $a = rindex ($curFileset, '/');
	my $error_file = substr($curFileset,$a+1)."_ERROR";
	$currentErrorFile = $jobRunningDir."/ERROR/".$error_file;
	return $currentErrorFile;
}
#****************************************************************************************************
#Subroutine Name         : getProgressDetails
#Objective               : This subroutine gives backup and restore progress details.
#			 : This subrutine evolved after merging backupProgressDetails and restoreProgressDetails subroutine. Few parts of this subroutine has been rmoved and added at other places so that functionalities can be made common.
#Added By                : Abhishek Verma.
#Modified By 			 : Senthil Pandian
#*****************************************************************************************************/
sub getProgressDetails{
	my ($progressDetailsFilePath) = @_;

	if(-e $progressDetailsFilePath and -s $progressDetailsFilePath > 0)
	{
		if(open(progressDetails, "<", $progressDetailsFilePath)) {
			chomp(my @progressDetailsFileData = <progressDetails>);
			$IncFileSizeByte = $progressDetailsFileData[2];
			chomp($IncFileSizeByte);
			$IncFileSizeByte = 0 if($IncFileSizeByte < 0);
		}
	}
}

#****************************************************************************************************
# Subroutine Name         : BackupOutputParse
# Objective               : This function monitors and parse the evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Deepak Chaurasia, Sabin Cheruvattil, Senthil Pandian
#**************************#***************************************************************************/
sub BackupOutputParse {
	our ($curFileset, $silentFlag, $fileTransferCount, $operationEngineId) = @_;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my ($prevSize, $currentSize, $cumulativeDataTransRate) = (0) x 3;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_" . $operationEngineId;
	my @PROGRESSFILE;
	my $initialSlash = ($operationName eq 'BACKUP_OPERATION')? '/' : '';
	my $completedFileSize = 0;

	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	$completedFileSize = $PROGRESSFILE[10] if($PROGRESSFILE[10]);
	chmod $filePermission, $progressDetailsFilePath;

	my $tempIdevsOutputFile = $idevsOutputFile . '_' . $operationEngineId;
	while(!$fileNotOpened) {
		last unless(-f $pidPath);
		if(-e $tempIdevsOutputFile) {
			chmod $filePermission, $tempIdevsOutputFile;
			open TEMPOUTPUTFILE, "<", $tempIdevsOutputFile and $fileNotOpened = 1;
		}
		else {
			sleep(2);
		}
	}

	my $cdpdump	= Common::getCDPDBDumpFile($jobType);
	Common::createDir(Common::dirname($cdpdump), 1) unless(-d Common::dirname($cdpdump));

	my ($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
	my $upddbpaths	= Common::getCDPDBPaths();
	my $cdpjobnames	= ();
	my $curdata		= {};

	while (1) {
		$byteRead = read(TEMPOUTPUTFILE, $buffer, LIMIT);
		if($byteRead == 0) {
			last if(!-e $pidPath or !-e $pidPath.'_evs_'.$operationEngineId);
			sleep(2);
			seek(TEMPOUTPUTFILE, 0, 1);		#to clear eof flag
			next;
		}

		#$tryCount = 0;

		# need to check appending partial record to packet or to first line of packet
		$buffer = $lastLine . $buffer if("" ne $lastLine);

		my @resultList = split /\n/, $buffer;

		#keep last line of buffer only when it not ends with newline.
		$lastLine = ($buffer !~ /\n$/)? pop @resultList : '';

		foreach my $tmpLine (@resultList) {
			if($tmpLine =~ /<item/) {
				my %fileName = parseXMLOutput(\$tmpLine);
				if(scalar(keys %fileName) < 5) {
					Common::traceLog("Backup output line: $tmpLine");
					next;
				}

				my $keyString 		= $initialSlash.$fileName{'fname'};
				my $fileSize 	    = $fileName{'size'};
				my $totsize 	    = $fileName{'size'};
				my $fileBackupType  = $fileName{'trf_type'};
				my $rateOfTransfer  = $fileName{'rate_trf'};

				my $currentSize     = $fileName{'size'};
				$currentSize        = $fileName{'offset'} if($fileName{'offset'});
				my $percentage		= $fileName{'per'};

				$mpc				= $fileName{'mpc'}? $fileName{'mpc'} : '';
				$encname			= $fileName{'enc_name'}? $fileName{'enc_name'} : '';
				$folderid			= $fileName{'folder_id'}? $fileName{'folder_id'} : '';

				$backupType = $fileBackupType;
				$backupType =~ s/FILE IN//;
				$backupType =~ s/\s+//;
				my $backupFinishTime = localtime;
				replaceXMLcharacters(\$keyString);
				my $pKeyString = $keyString;

				if(($relative eq NORELATIVE) and ($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL")) {
					my $indx = rindex ($pKeyString, '/');
					$pKeyString = substr($pKeyString, $indx);
				}

				if($tmpLine =~ m/$operationComplete/) {
					if($fileBackupType eq "FILE IN SYNC") { 		# check if file in sync
						if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 2;
							my $filefullpath	= $keyString;
							$filefullpath		= $current_source . $filefullpath if($current_source ne '/');

                            my $mtime = 0;
							if(-f $filefullpath) {
								$mtime = stat($filefullpath)->mtime;
							}
                            # $mtime = Common::strftime("%m/%d/%Y %r", localtime($mtime));  #Commented  to keep unixtimestamp : Senthil
                            # my $dt = strftime("%Y-%m-%d %H:%M:%S", localtime($time));
							$cdpjobnames	= Common::getDBJobsetsByFile($jsjobselems, $filefullpath);
							for my $i (0 .. $#{$cdpjobnames}) {
								$curdata = {'ITEM' => $filefullpath, 'JOBNAME' => $cdpjobnames->[$i], 'DBPATH' => $upddbpaths->{$cdpjobnames->[$i]}, 'OPERATION' => 'UPDATE', 'JOBTYPE' => $jobType, 'MPC' => $mpc, 'FOLDER_ID' => $folderid, 'ENC_NAME' => $encname,'SIZE'=>$fileSize,'MOD_TIME'=>$mtime};
								$dbdumpdata{$cdpdumpidx} = $curdata;
								$cdpdumpidx++;
							}
							
							$completedFileSize += $totsize;

							# @TODO: remove after debug
							# Common::traceLog("CDP IN SYNC: $filefullpath", undef, undef, 1) if($jobRunningDir =~ /CDP/);
						} else {
							$retVal = getFullPathofFile($keyString, $restoreFinishTime, $fileBackupType, $fileSize, 2);
							if($retVal) {
								$completedFileSize += $totsize;
							}

							next if($retVal == 2);
						}
					}
					elsif($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL") {  	# check if file is backing up as full or incremental
                        $modifiedCount++ if($fileBackupType eq 'INCREMENTAL');
                        if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 1;
                            my $logBackupType = ($fileBackupType eq 'INCREMENTAL')?$backupType:(((" ") x 4).$backupType.((" ") x 3));
                            $fileSetHash{$keyString}{'detail'} = "[$backupFinishTime] [SUCCESS] [$logBackupType]";
							$fileSetHash{$keyString}{'size'} = $fileSize;
							
							my $filefullpath	= $keyString;
							$filefullpath		= $current_source . $filefullpath if($current_source ne '/');
							# $fileBackupCount++;
							$transferredFileSize += $fileSize;
							
							if($percentage eq '100%') {
								$completedFileSize += $totsize;
							}

                            my $mtime = 0;
							if(-f $filefullpath) {
								$mtime = stat($filefullpath)->mtime;
							}
                            # $mtime = Common::strftime("%m/%d/%Y %r", localtime($mtime));  #Commented  to keep unixtimestamp : Senthil
							$cdpjobnames	= Common::getDBJobsetsByFile($jsjobselems, $filefullpath);
							for my $i (0 .. $#{$cdpjobnames}) {
								$curdata = {'ITEM' => $filefullpath, 'JOBNAME' => $cdpjobnames->[$i], 'DBPATH' => $upddbpaths->{$cdpjobnames->[$i]}, 'OPERATION' => 'UPDATE', 'JOBTYPE' => $jobType, 'MPC' => $mpc, 'FOLDER_ID' => $folderid, 'ENC_NAME' => $encname,'SIZE'=>$fileSize,'MOD_TIME'=>$mtime};
								$dbdumpdata{$cdpdumpidx} = $curdata;
								$cdpdumpidx++;
							}
						} else {
							$retVal = getFullPathofFile($keyString, $restoreFinishTime, $fileBackupType, $fileSize, 1);
							if ($retVal == 1) {
								$transferredFileSize += $fileSize;
								if($percentage eq '100%') {
									$completedFileSize += $totsize;
								}
							} elsif($retVal == 2){
								next;
							}
						}
					}
					else {
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}

					$parseCount++;
					$fileTransferCount++;
				}

				if($totalSize eq Constants->CONST->{'CalCulate'}) {
					if(open(FILESIZE, "<$fileForSize")) {
						$totalSize = <FILESIZE>;
						close(FILESIZE);
						chomp($totalSize);
						$totalSize = Constants->CONST->{'CalCulate'} if($totalSize eq "");
					}
				}

				if($prevFile eq $keyString) {
					if (($currentSize > $prevSize && $prevSize ne 0) or ($prevSize eq 0)) {
						$IncFileSizeByte = $IncFileSizeByte + $currentSize - $prevSize;
					}
				} elsif($prevFile ne $keyString) {
					$IncFileSizeByte = $IncFileSizeByte + $currentSize;
				}
				$prevSize = $currentSize;

				$prevLine = $tmpLine;
				$prevFile = $keyString;
				$backupType = ucfirst(lc($backupType));
				my $sizeInBytes = convertToBytes($rateOfTransfer);
				# if($sizeInBytes > 0) {
					# $ctrf += $sizeInBytes;
					# $cumulativeDataTransRate = ($fileTransferCount && $ctrf)?($ctrf/$fileTransferCount):$ctrf;
					# $fileTransferCount++;
				# }

				#if($totalSize ne Constants->CONST->{'CalCulate'}){
				$progress = "$backupType Backup" . "\n" . $fileSize . "\n" . $IncFileSizeByte . "\n" . $totalSize . "\n" . $sizeInBytes . "\n" . $pKeyString;
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " " x ($prevLen - $newLen);
					$pKeyString = $pKeyString . $pSpace;
				}
				$PROGRESSFILE[0] = "$backupType Backup";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$sizeInBytes";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";
				$PROGRESSFILE[8] = "$fileTransferCount";
				$PROGRESSFILE[9] = "$fileSize";
				$PROGRESSFILE[10] = "$completedFileSize";
				$prevLen = $newLen;
				#}
			}
			elsif($tmpLine =~ /$termData/is) {
				close TEMPOUTPUTFILE;
				$skipFlag = 1;
			}
			elsif($tmpLine ne '' and
			$tmpLine !~ m/building file list/ and
			$tmpLine !~ m/=============/ and
			$tmpLine !~ m/connection established/ and
			$tmpLine !~ m/bytes  received/ and
			$tmpLine !~ m/Number of files/ and
			$tmpLine !~ m/\| FILE SIZE \| TRANSFERED SIZE \| TOTAL SIZE \|/ and
			$tmpLine !~ m/\%\]\s+\[/ and
			$tmpLine !~ m/$termData/is) {
				$errStr = $tmpLine;
				addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
			}
		}

		last if($skipFlag);
	}

	Common::fileWrite($cdpdump, JSON::to_json(\%dbdumpdata));

	untie @PROGRESSFILE;
	# writeTransferRateAndCount($ctrf, $fileTransferCount);
}

#****************************************************************************************************
# Subroutine Name         : BackupDedupOutputParse.
# Objective               : This function parse the Dedup evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub BackupDedupOutputParse {
	our ($curFileset,$silentFlag,$fileTransferCount,$operationEngineId) = @_;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 21;
	my ($prevSize,$currentSize,$cumulativeDataTransRate) = (0) x 3;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @PROGRESSFILE;
	my $initialSlash =  ($operationName eq 'BACKUP_OPERATION')? '/' : '';
	my $completedFileSize = 0;

	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	$completedFileSize = $PROGRESSFILE[10] if($PROGRESSFILE[10]);
	chmod $filePermission, $progressDetailsFilePath;

	my $tempIdevsOutputFile = $idevsOutputFile . '_' . $operationEngineId;

	while(!$fileNotOpened) {
		last unless(-f $pidPath);

		if(-e $tempIdevsOutputFile) {
			chmod $filePermission, $tempIdevsOutputFile;
			open TEMPOUTPUTFILE, "<", $tempIdevsOutputFile and $fileNotOpened = 1;
		}
		else{
			sleep(2);
		}
	}

	my $cdpdump	= Common::getCDPDBDumpFile($jobType);
	Common::createDir(Common::dirname($cdpdump), 1) unless(-d Common::dirname($cdpdump));

	my ($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
	my $upddbpaths	= Common::getCDPDBPaths();
	my $cdpjobnames	= ();
	my $curdata		= {};
	# my $opinode		= Common::stat($tempIdevsOutputFile)->ino;
	

	while (1) {
		$byteRead = read(TEMPOUTPUTFILE, $buffer, LIMIT);
		if($byteRead == 0) {
			# last unless(-f $pidPath);
			last if(!-e $pidPath or !-e $pidPath . '_evs_' . $operationEngineId);
			# @TODO: compare inode number
			# last unless($opinode == Common::stat($tempIdevsOutputFile)->ino);
			sleep(2);
			seek(TEMPOUTPUTFILE, 0, 1);		#to clear eof flag
			next;
		}

		#$tryCount = 0;
		# need to check appending partial record to packet or to first line of packet
		$buffer = $lastLine . $buffer if("" ne $lastLine);

		my @resultList = split /\n/, $buffer;

		#keep last line of buffer only when it not ends with newline.
		$lastLine = ($buffer !~ /\n$/)? pop @resultList : '';

		foreach my $tmpLine (@resultList) {
			if($tmpLine =~ /<item/) {
				my %fileName = parseXMLOutput(\$tmpLine);
				if(scalar(keys %fileName) < 5) {
					Common::traceLog("Backup output line: $tmpLine");
					next;
				}

				my $keyString 		= $initialSlash.$fileName{'fname'};
				my $fileSize 	    = $fileName{'size'};
				my $totsize 	    = $fileName{'size'};
				my $fileBackupType  = $fileName{'trf_type'};
				   #$fileBackupType =~ s/^\s+//;
				my $rateOfTransfer  = $fileName{'rate_trf'};
				my $currentSize     = $fileName{'offset'};
				my $backupType      = $fileBackupType;
				$backupType =~ s/FILE IN//;
				$backupType =~ s/\s+//;
				my $percentage		= $fileName{'per'};

				$mpc				= $fileName{'mpc'}? $fileName{'mpc'} : '';
				$encname			= $fileName{'enc_name'}? $fileName{'enc_name'} : '';
				$folderid			= $fileName{'folder_id'}? $fileName{'folder_id'} : '';

				my $backupFinishTime = localtime;
				replaceXMLcharacters(\$keyString);
				my $pKeyString = $keyString;

				if($tmpLine =~ m/$operationComplete/) {
					if($fileBackupType eq "FILE IN SYNC") { 		# check if file in sync
						if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 2;
							my $filefullpath = $keyString;
							$filefullpath	 = $current_source . $filefullpath if($current_source ne '/');
                            
                            my $mtime = 0;
							if(-f $filefullpath) {
								$mtime = stat($filefullpath)->mtime;
							}
                            # $mtime = Common::strftime("%m/%d/%Y %r", localtime($mtime));  #Commented  to keep unixtimestamp : Senthil
							$cdpjobnames	= Common::getDBJobsetsByFile($jsjobselems, $filefullpath);
							# @TODO: remove after debug
							# Common::traceLog("CDP IN SYNC: $filefullpath", undef, undef, 1) if($jobRunningDir =~ /CDP/);
							for my $i (0 .. $#{$cdpjobnames}) {
								$curdata = {'ITEM' => $filefullpath, 'JOBNAME' => $cdpjobnames->[$i], 'DBPATH' => $upddbpaths->{$cdpjobnames->[$i]}, 'OPERATION' => 'UPDATE', 'JOBTYPE' => $jobType, 'MPC' => $mpc, 'FOLDER_ID' => $folderid, 'ENC_NAME' => $encname, 'SIZE'=>$fileSize, 'MOD_TIME' => $mtime, 'CMP_MTIME' => $fileSetHash{$keyString}{'mts'}, 'CMP_SIZE' => $fileSetHash{$keyString}{'size'}};
								$dbdumpdata{$cdpdumpidx} = $curdata;
								$cdpdumpidx++;
							}

							$completedFileSize += $totsize;
						} else {
							$fullPath = getFullPathofFile($keyString, $restoreFinishTime, $fileBackupType, $fileSize, 2);

							if($fullPath) {
								$completedFileSize += $totsize;
							}
						}
					}
					elsif($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL") {  	# check if file is backing up as full or incremental
                        $modifiedCount++ if($fileBackupType eq 'INCREMENTAL');
                        if(defined($fileSetHash{$keyString}{'status'})) {
							if($fileSetHash{$keyString}{'status'} != 1){
								$fileSetHash{$keyString}{'status'} = 1;
                                my $logBackupType = ($fileBackupType eq 'INCREMENTAL')?$backupType:(((" ") x 4).$backupType.((" ") x 3));
								$fileSetHash{$keyString}{'detail'} = "[$backupFinishTime] [SUCCESS] [$logBackupType]";
								$fileSetHash{$keyString}{'size'} = $fileSize;
								my $filefullpath	= $keyString;
								$filefullpath		= $current_source . $filefullpath if($current_source ne '/');
								$transferredFileSize += $fileSize;

								if($percentage eq '100%') {
									$completedFileSize += $totsize;
								}

                                my $mtime = 0;
								if(-f $filefullpath) {
									$mtime = stat($filefullpath)->mtime;
								}
                                # $mtime = Common::strftime("%m/%d/%Y %r", localtime($mtime)); #Commented  to keep unixtimestamp : Senthil
								
								$cdpjobnames	= Common::getDBJobsetsByFile($jsjobselems, $filefullpath);
								for my $i (0 .. $#{$cdpjobnames}) {
									$curdata = {'ITEM' => $filefullpath, 'JOBNAME' => $cdpjobnames->[$i], 'DBPATH' => $upddbpaths->{$cdpjobnames->[$i]}, 'OPERATION' => 'UPDATE', 'JOBTYPE' => $jobType, 'MPC' => $mpc, 'FOLDER_ID' => $folderid, 'ENC_NAME' => $encname, 'SIZE' => $fileSize, 'MOD_TIME' => $mtime, 'CMP_MTIME' => $fileSetHash{$keyString}{'mts'}, 'CMP_SIZE' => $fileSetHash{$keyString}{'size'}};
									$dbdumpdata{$cdpdumpidx} = $curdata;
									$cdpdumpidx++;
								}
							}
						}
						else {
							if (getFullPathofFile($keyString, $restoreFinishTime, $fileBackupType, $fileSize, 1) == 1) {
								$transferredFileSize += $fileSize;
								if($percentage eq '100%') {
									$completedFileSize += $totsize;
								}
							}
						}
					}
					else{
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}
					$parseCount++;
					$fileTransferCount++;
				}

				if($totalSize eq Constants->CONST->{'CalCulate'}) {
					if(open(FILESIZE, "<$fileForSize")) {
						$totalSize = <FILESIZE>;
						close(FILESIZE);
						chomp($totalSize);
						$totalSize = Constants->CONST->{'CalCulate'} if($totalSize eq "");
					}
				}

				if($prevFile eq $keyString) {
					if (($currentSize > $prevSize && $prevSize ne 0) or ($prevSize eq 0)) {
						$IncFileSizeByte = $IncFileSizeByte + $currentSize - $prevSize;
					}
				} elsif($prevFile ne $keyString) {
					$IncFileSizeByte = $IncFileSizeByte + $currentSize;
				}
				$prevSize = $currentSize;
				$prevLine = $tmpLine;
				$prevFile = $keyString;
				$backupType = ucfirst(lc($backupType));
				my $sizeInBytes = convertToBytes($rateOfTransfer);
				# if($sizeInBytes>0) {
					# $ctrf += $sizeInBytes;
					# $cumulativeDataTransRate = ($fileTransferCount && $ctrf)?($ctrf/$fileTransferCount):$ctrf;
					# $fileTransferCount++;
				# }

				$progress = "$backupType Backup" . "\n" . $fileSize . "\n" . $IncFileSizeByte . "\n" . $totalSize . "\n" . $sizeInBytes . "\n" . $pKeyString;
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " " x ($prevLen - $newLen);
					$pKeyString = $pKeyString . $pSpace;
				}
				$PROGRESSFILE[0] = "$backupType Backup";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$sizeInBytes";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";
				$PROGRESSFILE[8] = "$fileTransferCount";
				$PROGRESSFILE[9] = "$fileSize";
				$PROGRESSFILE[10] = "$completedFileSize";
				$prevLen = $newLen;

			}
			elsif($tmpLine =~ /$termData/is) {
				close TEMPOUTPUTFILE;
				$skipFlag = 1;
			}
			elsif($tmpLine ne '' and
			$tmpLine !~ m/building file list/ and
			$tmpLine !~ m/=============/ and
			$tmpLine !~ m/connection established/ and
			$tmpLine !~ m/bytes  received/ and
			$tmpLine !~ m/Number of files/ and
			$tmpLine !~ m/\| FILE SIZE \| TRANSFERED SIZE \| TOTAL SIZE \|/ and
			$tmpLine !~ m/\%\]\s+\[/ and
			$tmpLine !~ m/$termData/is) {
					$errStr = $tmpLine;
					addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
				}
		}

		last if($skipFlag);
	}

# Common::traceLog("dbdumpdata:\n\n".JSON::to_json(\%dbdumpdata));
	Common::fileWrite($cdpdump, JSON::to_json(\%dbdumpdata));
	untie @PROGRESSFILE;
	# writeTransferRateAndCount($ctrf,$fileTransferCount);
}
#****************************************************************************************************
# Subroutine Name         : subErrorRoutine.
# Objective               : This function monitors and parse the evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Deepak Chaurasia
# Modified By			  : Dhritikana, Senthil Pandian
#*****************************************************************************************************/
sub subErrorRoutine
{
	my $curFileset   = shift;
	my $retryAttempt = 0;
	my $reason;
	my $currentErrorFile = getCurrentErrorFile($curFileset);

	my @errorContent = readEVSErrorFile($currentErrorFile,$idevsErrorFile."_".$operationEngineId);
	#copyTempErrorFile($currentErrorFile,$operationEngineId);
	getUpdateRetainedFilesList(@errorContent);

	my ($failed_count, @failedfiles_array) = getFailedFileCount();
	getFinalErrorFile($curFileset, \$failed_count, \@failedfiles_array, \@errorContent);
	@failedfiles_array = getFailedFileArray();

	#Check if retry is required
	$failedfiles_index = getParameterValueFromStatusFile($operationEngineId, 'FAILEDFILES_LISTIDX');

	if(scalar @failedfiles_array > 0) {
		($retryAttempt, $reason) = checkretryAttempt(@errorContent);
		if(!$retryAttempt or $failedfiles_index == -1) {
			reduceUpdateRetainSizeInprogress();
			updateFailedFileCount($curFileset, $failed_count);
			return;
		}

		reduceRetryFileSizeInprogress();
	}
	else {
		reduceUpdateRetainSizeInprogress();
		updateFailedFileCount($curFileset, $failed_count);
		return;
	}

	if ($retryAttempt and $failedfiles_index != -1) {
		$failedfiles_index++;
		$failedfiles = $jobRunningDir."/".$failedFileName.$retry_failedfiles_index;
		my $oldfile_error = $currentErrorFile."_FINAL";
		my $newfile_error = $jobRunningDir."/ERROR/$failedFileName$retry_failedfiles_index"."_ERROR_FINAL";

		if(-e $oldfile_error) {
			rename $oldfile_error, $newfile_error;
		}

		if(!open(FAILEDLIST, "> $failedfiles")) {
			Common::traceLog("Could not open file failedfiles in SubErrorRoutine: $failedfiles, Reason:$!");
			reduceUpdateRetainSizeInprogress();
			updateFailedFileCount($curFileset, $failed_count);
			return;
		}
		chmod $filePermission, $failedfiles;
		chomp(@failedfiles_array);
        if($restoreVersion > 1) {
            for(my $i = 0; $i <= $#failedfiles_array; $i++) {
                my $ver = '';
# Common::traceLog("failedfiles_array:".$failedfiles_array[$i]);  
                if(exists($fileSetHash{$failedfiles_array[$i]}{'ver'}) and $fileSetHash{$failedfiles_array[$i]}{'ver'} ne '') {
                    $ver = '_IBVER'.$fileSetHash{$failedfiles_array[$i]}{'ver'};
                }
                print FAILEDLIST $failedfiles_array[$i].$ver."\n";
            }
        } else {
            for(my $i = 0; $i <= $#failedfiles_array; $i++) {
                print FAILEDLIST $failedfiles_array[$i]."\n";
            }
        }
		close FAILEDLIST;

		if(-e $failedfiles){
			open RETRYINFO, ">> $retryinfo";
			print RETRYINFO "$current_source' '$relative' '$failedfiles\n";
			close RETRYINFO;
			chmod $filePermission, $retryinfo;
		}
	}

	reduceUpdateRetainSizeInprogress();
	updateFailedFileCount($curFileset, $failed_count);
}

#**********************************************************************************************************
# Subrotine Name         : getFailedFileCount
# Objective               : This subroutine gets the failed files count from the failedfiles array
# Modified By             : Pooja Havaldar
#********************************************************************************************************/
sub getFailedFileCount
{
	my $failed_count = 0;
	my @failedfiles_array = ();
	for(my $i = 0; $i <= $#currentFileset; $i++){
		chomp $currentFileset[$i];
		if(($fileSetHash{$currentFileset[$i]}{'status'} == 0)
			or ($fileSetHash{$currentFileset[$i]}{'status'} == 3))
		{
			push @failedfiles_array, $currentFileset[$i];
			$failed_count++;
		}
	}
	return ($failed_count, @failedfiles_array);
}

#**********************************************************************************************************
# Subrotine Name        : getFailedFileArray
# Objective             : This subroutine gets the failed files list from the failedfiles array
# Modified By           : Senthil Pandian
#********************************************************************************************************/
sub getFailedFileArray
{
	my @failedfiles_array = ();
	for(my $i = 0; $i <= $#currentFileset; $i++){
		#next if($currentFileset[$i] eq '');
		chomp $currentFileset[$i];
		if(($fileSetHash{$currentFileset[$i]}{'status'} == 0)
			or ($fileSetHash{$currentFileset[$i]}{'status'} == 3))
		{
			push @failedfiles_array, $currentFileset[$i];
		}
	}
	return @failedfiles_array;
}
#****************************************************************************************************
# Subroutine		: getFullPathofFile
# Objective			: Fill the hash if we are not able to find the reference
# Added By			: Pooja Havaldar
# Modified By		: Vijay Vinoth, Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************
sub getFullPathofFile {
	$fileToCheck = $_[0];
	my $restoreFinishTime = $_[1];
	my $restoreType = $_[2];
	my $fileSize = $_[3];
	my $status = $_[4];

	# CD Writer part
	my ($dirswatch, $jsjobselems, $jsitems) = Common::getCDPWatchEntities();
	my $upddbpaths	= Common::getCDPDBPaths();
	my $cdpjobnames	= ();
	my $curdata		= {};

	for(my $i = $#currentFileset; $i >= 0; $i--) {
		$a		= rindex($currentFileset[$i], '/');
		$match	= substr($currentFileset[$i], $a);

		if($fileToCheck eq $match) {
			next if($fileSetHash{$currentFileset[$i]}{'status'} == 1 or $fileSetHash{$currentFileset[$i]}{'status'} == 2);
			$fileSetHash{$currentFileset[$i]}{'status'} = $status;
            my $logType = ($restoreType eq 'INCREMENTAL')?$restoreType:(((" ") x 4).$restoreType.((" ") x 3));
			$fileSetHash{$currentFileset[$i]}{'detail'} = "[$restoreFinishTime] [SUCCESS] [$logType]";
			$fileSetHash{$currentFileset[$i]}{'size'} = $fileSize;

			if($isbackupop) {
				my $filefullpath	= $currentFileset[$i];
				$filefullpath		= $current_source . $currentFileset[$i] if($current_source ne '/');
                
                my $mtime = 0;
                if(-f $filefullpath) {
                	$mtime = stat($filefullpath)->mtime;
                }

				$cdpjobnames	= Common::getDBJobsetsByFile($jsjobselems, $filefullpath);
				for my $i (0 .. $#{$cdpjobnames}) {
					$curdata = {'ITEM' => $filefullpath, 'JOBNAME' => $cdpjobnames->[$i], 'DBPATH' => $upddbpaths->{$cdpjobnames->[$i]}, 'OPERATION' => 'UPDATE', 'JOBTYPE' => $jobType, 'MPC' => $mpc, 'FOLDER_ID' => $folderid, 'ENC_NAME' => $encname, 'CMP_MTIME' => 0, 'SIZE' => $fileSize, 'MOD_TIME' => $mtime};
					$dbdumpdata{$cdpdumpidx} = $curdata;
					$cdpdumpidx++;
				}
			}

			return 1;
		}
	}

	return 0;
}

#****************************************************************************************************
# Subroutine Name		: checkUpdateRetainedForRelative
# Objective				: Fill the hash if we are not able to find the reference when update retained error comes.
# Added By				: Senthil Pandian
#*****************************************************************************************************
sub checkUpdateRetainedForRelative {
	my $fileToCheck = $_[0];
	for(my $i = $#currentFileset ; $i >= 0; $i--){
		my $a = rindex ($currentFileset[$i], '/');
		my $match = substr($currentFileset[$i],$a);

		if($fileToCheck eq $match){
			if($fileSetHash{$currentFileset[$i]}{'status'} >= 1) {
				# $fileBackupCount--;
				$fileSetHash{$currentFileset[$i]}{'status'} = 3;
				$updateRetainedFilesSize += $fileSetHash{$currentFileset[$i]}{'size'};
				return 1;
			}
		}
	}
	return 0;
}
#****************************************************************************************************************************
# Subroutine Name         : updateFailedFileCount
# Objective               : This subroutine gets the updated failed files count incase retry backup is in process
# Modified By             : Pooja Havaldar
#******************************************************************************************************************************/
sub updateFailedFileCount
{
	my $curFileset   = shift;
	my $failed_count = shift;
	$orig_count = getParameterValueFromStatusFile($operationEngineId, 'ERROR_COUNT_FILES');
	if($curFileset =~ m/failedfiles.txt/) {
		$size_Backupset = $#currentFileset + 1;
		$newcount = $orig_count - $size_Backupset + $failed_count;
		$failedfiles_count = $newcount;
	} else {
		$orig_count += $failed_count;
		$failedfiles_count = $orig_count;
	}
}

#****************************************************************************************************
# Subroutine Name         : checkretryAttempt.
# Objective               : This function checks whether backup has to retry
# Added By                : Pooja Havaldar
# Modified By             : Yogesh Kumar, Senthil Pandian
#*****************************************************************************************************/
sub checkretryAttempt
{
	#my $errorline 	     = "idevs error";
	my (@linesBackupErrorFile)	= @_;
	my $retryAttempt 		 	= 0;
	my $reason				 	= '';

	# traceLog(@linesBackupErrorFile);
	chomp(@linesBackupErrorFile);

	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;
		next if($linesBackupErrorFile[$i] eq "");
		# if($linesBackupErrorFile[$i] eq "" or $linesBackupErrorFile[$i] =~ m/$errorline/){
			# next;
		# }

		for(my $j=0; $j<=$#ErrorArgumentsExit; $j++)
		{
			if($linesBackupErrorFile[$i] =~ m/$ErrorArgumentsExit[$j]/)
			{
				#$errStr = "Operation could not be completed. Reason : $ErrorArgumentsExit[$j]. Please login using Login.pl script.";
				if($ErrorArgumentsExit[$j]=~/skipped-over limit|quota over limit/i){
					$errStr = Constants->CONST->{'operationNotcomplete'}." ".Constants->CONST->{'QuotaOverLimit'};
				}
				# elsif($ErrorArgumentsExit[$j] =~ /unauthorized user/i) {
					# Common::getServerAddress();
				# }
				else {
					$errStr = Constants->CONST->{'operationNotcomplete'}." Reason : $ErrorArgumentsExit[$j].";
				}
				Common::traceLog($errStr);
				#kill evs and then exit
				my $jobTerminationPath = $currentDir.'/'.Constants->FILE_NAMES->{jobTerminationScript};
				system($AppConfig::perlBin . " \'$jobTerminationPath\' \'$jobType\' \'$userName\' 1>/dev/null 2>/dev/null");

				$exit_flag = "1-$errStr";
				if($jobType =~ /backup/i) {
					unlink($pwdPath) if($errStr =~ /password mismatch/i);
				} else {
					unlink($pwdPath) if($errStr =~ /password mismatch|encryption verification failed/i);
				}
				return ($retryAttempt, $errStr);
			}
		}
		# @TODO: Check and remove the following trace
		Common::traceLog("linesBackupErrorFile Line:".$linesBackupErrorFile[$i]);
		waitForNetworkConnection() if($linesBackupErrorFile[$i] =~ m/Network is unreachable/);
		foreach my $err (@ErrorListForMinimalRetry) {
			if ($linesBackupErrorFile[$i] =~ m/$err/) {
				$retryAttempt = 1;
				$reason = $err;
				if($err =~ /unauthorized user|user information not found/i) {
					Common::updateAccountStatus($userName, 'UA');
					Common::saveServerAddress(Common::fetchServerAddress());
				}
				else {
					Common::checkErrorAndUpdateEVSDomainStat($err); #Checking error to try with IP 
					Common::fileWrite($errorFilePath,Constants->CONST->{'operationNotcomplete'}." Reason : ".$reason);
					Common::traceLog("Retry Reason: $reason");
				}
				unless (-f $minimalErrorRetry) {
					Common::fileWrite($minimalErrorRetry, '');
				}
				return ($retryAttempt, $reason);
			}
		}

		for(my $j=0; $j<=($#ErrorArgumentsRetry) and !$retryAttempt; $j++) {
			if ($linesBackupErrorFile[$i] =~ m/$ErrorArgumentsRetry[$j]/) {
				$retryAttempt = 1;
				$reason = $ErrorArgumentsRetry[$j];
				# Handle cutoff scenario and if some error is present
				if(-f $pidPath) {
					Common::fileWrite($errorFilePath, Constants->CONST->{'operationNotcomplete'} . " Reason : " . $reason);
					Common::traceLog("Retry Reason: $reason");
				} else {
					Common::traceLog('Job cutoff situation.' . $reason);
				}

				return ($retryAttempt, $reason);
			}
		}
	}

	return ($retryAttempt, $reason);
}

#****************************************************************************************************************************
# Subroutine Name         : getFinalErrorFile
# Objective               : This subroutine creates a final ERROR file for each backupset, which has to be displayed in LOGS
# Modified By             : Pooja Havaldar, Senthil Pandian, Sabin Cheruvattil
#****************************************************************************************************************************
sub getFinalErrorFile
{
	my $curFileset = $_[0];
	my @failedfiles_array = @{$_[2]};
	my @individual_errorfileContents = @{$_[3]};

	my $currentErrorFile = getCurrentErrorFile($curFileset);
	$cancel = 0;
	$cancel = 1 if($exit_flag == 0 && !-f $pidPath);

	my $failedWithReason = 0;
	my ($errFinal,$errMsgFinal) = ("") x 2;
	my ($fileOpenFlag,$traceFileOpenFlag,$noRetryFileOpenFlag) = (1) x 3;

	#if($#failedfiles_array > 0){ Modified By Senthil for Harish_2.12_3_2
	if($#failedfiles_array >= 0 and scalar(@individual_errorfileContents)> 0) {
		open ERROR_FINAL, ">", $currentErrorFile."_FINAL" or $fileOpenFlag = 0;
		#open ERROR_FINAL, ">", $currentErrorFile or $fileOpenFlag = 0;
		if(!$fileOpenFlag){
			Common::traceLog("\n Could not open file {$currentErrorFile}_FINAL: $! \n");
			return;
		}
		else{
			chmod $filePermission, $currentErrorFile."_FINAL";
		}

		my $traceExist = $jobRunningDir."/ERROR/traceExist.txt";
		if(!open(TRACEERRORFILE, ">>", $traceExist)) {
			Common::traceLog(Constants->CONST->{'FileOpnErr'}." $traceExist, Reason: $!. $lineFeed");
		} else {
			chmod $filePermission, $traceExist;
		}

		my $permissionError = $jobRunningDir."/ERROR/permissionError.txt";
		open TRACEPERMISSIONERRORFILE, ">>", $permissionError or $traceFileOpenFlag = 0;
		if(!$traceFileOpenFlag){
			Common::traceLog("\n Could not open file $permissionError: $! \n");
			return;
		}
		else{
			chmod $filePermission, $permissionError;
		}

		my $noRetryError = $currentErrorFile."_NoRetry.txt";
		open NORETRYERROR, ">", $noRetryError  or $noRetryFileOpenFlag = 0;
		if(!$noRetryFileOpenFlag) {
			Common::traceLog("\n Could not open file $noRetryError: $!");
			return 0;
		} else {
			chmod $filePermission, $noRetryError;
		}

		chomp(@failedfiles_array);
		chomp(@individual_errorfileContents);
		my $j = 0;
		@failedfiles_array = sort{$b cmp $a} @failedfiles_array;
		my $last_index = $#individual_errorfileContents;

		my @missitems = ();
		for($i = 0; $i <= $#failedfiles_array; $i++){
			if($fileSetHash{$failedfiles_array[$i]}{'status'} == 3){
				print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] failed verification -- update retained".$lineFeed;
				# @TODO: remove after debug
				Common::traceLog("Updated retained file: " . $failedfiles_array[$i], undef, undef, 1);
				$failedWithReason++;
				next;
			}
			$matched = 0;

			if($fileOpenFlag) {
				#reset the initial and last limit for internal for loop for new item if required
				if($j > $last_index) {
					$j = 0;
					$last_index = $#individual_errorfileContents;
				}

				#fill the last matched index for later use
				$index = $j;
				$failedfile = substr($failedfiles_array[$i],1);
				$failedfile = quotemeta($failedfile);

				#try to find a match between start and end point of error file
				for(;$j <= $last_index; $j++) {
					if($individual_errorfileContents[$j] =~ /$failedfile/) {
						chomp($individual_errorfileContents[$j]);
						$individual_errorfileContents[$j] =~ s/\s+\[$failedfile\]/\./;

						my $find = $failedfiles_array[$i];
						my $replace = '';
						substr($find, 0, 1, "") if "/" eq substr($find, 0, 1);

						$individual_errorfileContents[$j] =~ s/\Q$find\E/$replace/g;

						if($individual_errorfileContents[$j] =~ /Permission denied/i) {
							print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : Permission denied".$lineFeed;
							$$failed_count--;
							$deniedFilesCount++;
							$fileSetHash{$failedfiles_array[$i]}{'status'} = 4;
							
							if($operationName eq 'BACKUP_OPERATION') {
								push(@missitems, $failedfiles_array[$i]);
							}
						} elsif($individual_errorfileContents[$j] =~ /Directory not empty/i){
							print NORETRYERROR "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : A directory name with the same file name already exists ".$lineFeed;
							$fileSetHash{$failedfiles_array[$i]}{'status'} = 4;
						} elsif($individual_errorfileContents[$j] =~ /No such file or directory/i){
							print TRACEERRORFILE "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : No such file or directory".$lineFeed;
							$missingCount++;
							$fileSetHash{$failedfiles_array[$i]}{'status'} = 4;
						} elsif($individual_errorfileContents[$j] =~ /failed verification -- update retained/i){
							print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] failed verification -- update retained".$lineFeed;
							$fileSetHash{$failedfiles_array[$i]}{'status'} = 3;
							# @TODO: remove after debug
							Common::traceLog("Updated retained file: " . $failedfiles_array[$i], undef, undef, 1);
						}
						elsif($individual_errorfileContents[$j] =~ /not enough free space|error in file write for/i) {
							print ERROR_FINAL "[" . (localtime) . "] [FAILED] [$failedfiles_array[$i]] Reason: Not enough free space on device." . $lineFeed;
							$fileSetHash{$failedfiles_array[$i]}{'status'} = 4;
						}
						elsif($individual_errorfileContents[$j] =~ /skipped-over limit/i) {
							print ERROR_FINAL "[" . (localtime) . "] [FAILED] [$failedfiles_array[$i]]." . $lineFeed;
							# $fileSetHash{$failedfiles_array[$i]}{'status'} = 4;
						}
						elsif($individual_errorfileContents[$j] =~ /Reason:/i) {
							my $rep = ' [/]';
							$individual_errorfileContents[$j] =~ s/\Q$rep\E//g;
							$individual_errorfileContents[$j] =~ s/IOERROR.*\),//g;
							print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] $individual_errorfileContents[$j]".$lineFeed;
						} else {
							print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : $individual_errorfileContents[$j]".$lineFeed;
						}
						$matched = 1;
						$failedWithReason++;

						#got a match so resetting the last index
						$last_index = $#individual_errorfileContents;
						$j++;
						last;
					}

					#if no match till last item and intial index is not zero try for remaining error file content
					if($j == $last_index && $index != 0) {
						$j = -1;
						$last_index = $index-1;
						$index = $j;
					}
				}
			}

			if($matched == 0 and $exit_flag == 0 and $cancel == 0) {#if restore location is not having proper permission then restore job will fail. Giving this error in the log file.Here failure reason is not present
				print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]]".$lineFeed;
			}
		}
		
		Common::createCleanNpMsRequest("$jobRunningDir/", \@missitems) if(scalar @missitems > 0);
		
		close NORETRYERROR;
		close ERROR_FINAL;
		close TRACEPERMISSIONERRORFILE;
		unlink($noRetryError) if(-z $noRetryError);
	}
	elsif($#failedfiles_array >= 0 and $exit_flag == 0 and $cancel == 0){
		open ERROR_FINAL, ">", $currentErrorFile."_FINAL" or $fileOpenFlag = 0;
		#open ERROR_FINAL, ">", $currentErrorFile or $fileOpenFlag = 0;
		if(!$fileOpenFlag){
			Common::traceLog("Could not open file {$currentErrorFile}_FINAL: $!");
			return;
		}
		else{
			chmod $filePermission, $currentErrorFile."_FINAL";
		}			
		foreach my $failedfile (@failedfiles_array) {			
			print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfile]".$lineFeed;
		}
		close ERROR_FINAL;
	}

	$$failed_count = $failedWithReason - $deniedFilesCount if($exit_flag != 0 or $cancel != 0);
}

#****************************************************************************************************
# Subroutine Name         : process_term
# Objective               : The signal handler invoked when SIGTERM signal is received by the script
# Created By              : Arnab Gupta
#*****************************************************************************************************/
# sub process_term
# {
	# writeParameterValuesToStatusFile($fileBackupCount, $fileRestoreCount, $fileSyncCount, $failedfiles_count, $deniedFilesCount, $missingCount, $exit_flag, $failedfiles_index, $operationEngineId);
	# exit 0;
# }
#****************************************************************************************************
# Subroutine Name         : RestoreOutputParse.
# Objective               : This function monitors and parse the evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Deepak Chaurasia, Senthil Pandian
#*****************************************************************************************************/
sub RestoreOutputParse
{
	our ($curFileset,$silentFlag,$fileTransferCount,$operationEngineId) = @_;
    my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my ($prevSize,$cumulativeDataTransRate,$fileSyncCount) = (0) x 3;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @PROGRESSFILE;
	my $completedFileSize = 0;

	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	$completedFileSize = $PROGRESSFILE[10] if($PROGRESSFILE[10]);
	chmod $filePermission, $progressDetailsFilePath;

	my $tempIdevsOutputFile = $idevsOutputFile.'_'.$operationEngineId;
	while (!$fileNotOpened) {
		if(!-e $pidPath){
			last;
        }

		if(-e $tempIdevsOutputFile) {
			open TEMPOUTPUTFILE, "<", $tempIdevsOutputFile and $fileNotOpened = 1;
			chmod $filePermission, $tempIdevsOutputFile;
		}
		else{
			sleep(2);
		}
	}

	while (1) {
		$byteRead = read(TEMPOUTPUTFILE, $buffer, LIMIT);
		if($byteRead == 0) {
			if(!-e $pidPath or !-e $pidPath.'_evs_'.$operationEngineId){
				last;
			}
			sleep(2);
			seek(TEMPOUTPUTFILE, 0, 1);		#to clear eof flag
			next;
		}

		if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
			$buffer = $lastLine . $buffer;
		}

		my @resultList = split /\n/, $buffer;

		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}
		#for(my $cnt = 0; $cnt < $bufIndex; $cnt++) {
		foreach my $tmpLine (@resultList){
			if($tmpLine =~ /<item/) {
				my %fileName = parseXMLOutput(\$tmpLine);
				if(scalar(keys %fileName) < 5) {
					Common::traceLog("Restore output line: $tmpLine");
					next;
				}

				my $restoreFinishTime = localtime;
				my $keyString   = $pathSeparator.$fileName{'fname'};
				$keyString = '/'.$keyString if(substr($keyString,0,1) ne '/'); 
				$keyString =~ s/^$restoreHost// if($operationName eq 'LOCAL_RESTORE_OPERATION');
				$keyString = Common::removeMultipleSlashs($keyString);
				# replaceXMLcharacters(\$keyString);
				my $restoreType = $fileName{'trf_type'};
				$restoreType    =~ s/FILE IN//;
				$restoreType    =~ s/\s+//;
				my $pKeyString  = $keyString;
				my $kbps        = $fileName{'rate_trf'};
				my $fileSize    = $fileName{'size'};
				my $currentSize = defined($fileName{'offset'})?$fileName{'offset'}:$fileSize;
				my $percentage	= $fileName{'per'};
				my $totsize 	= $fileName{'size'};

				if($relative eq NORELATIVE) {
					my $indx = rindex ($pKeyString, '/');
					$pKeyString = substr($pKeyString, $indx);
				}

				if($tmpLine =~ m/$operationComplete/) {
					if($restoreType eq 'SYNC') { 		# check if file in sync
						if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 2;
							$completedFileSize += $totsize;
						} else {
							$fullPath = getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize, 2);
							if($fullPath) {
								$completedFileSize += $totsize;
							}
						}
						# $fileSyncCount++;
					}
					elsif($restoreType eq 'FULL' or $restoreType eq 'INCREMENTAL') {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString}{'status'})) {
							if($fileSetHash{$keyString}{'status'} != 1){
								$fileSetHash{$keyString}{'status'} = 1;
                                my $logRestoreType = ($restoreType eq 'INCREMENTAL')?$restoreType:(((" ") x 4).$restoreType.((" ") x 3));
                                $fileSetHash{$keyString}{'detail'} = "[$restoreFinishTime] [SUCCESS] [$logRestoreType]";
								$fileSetHash{$keyString}{'size'} = $fileSize;
								# $fileRestoreCount++;
								$transferredFileSize += $fileSize;
								if($percentage eq '100%') {
									$completedFileSize += $totsize;
								}
							}
						} 
						elsif(defined($fileSetHash{$current_source.$keyString}{'status'})) {
							if($fileSetHash{$current_source.$keyString}{'status'} != 1){
								$fileSetHash{$current_source.$keyString}{'status'} = 1;
                                my $logRestoreType = ($restoreType eq 'INCREMENTAL')?$restoreType:(((" ") x 4).$restoreType.((" ") x 3));
                                $fileSetHash{$current_source.$keyString}{'detail'} = "[$restoreFinishTime] [SUCCESS] [$logRestoreType]";
								$fileSetHash{$current_source.$keyString}{'size'} = $fileSize;
								# $fileRestoreCount++;
								$transferredFileSize += $fileSize;
							}
						}                        
                        else {
							if(getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize, 1) == 1) {
								# $fileRestoreCount++;
								$transferredFileSize += $fileSize;
								if($percentage eq '100%') {
									$completedFileSize += $totsize;
								}
							}
						}
                        $modifiedCount++ if($restoreType eq 'INCREMENTAL');
					}
					else {
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}
					$fileTransferCount++;
				}
				if($totalSize eq Constants->CONST->{'CalCulate'}) {
					if(open(FILESIZE, "<$fileForSize")) {
						$totalSize = <FILESIZE>;
						close(FILESIZE);
						chomp($totalSize);
						if($totalSize eq "") {
							$totalSize = Constants->CONST->{'CalCulate'};
						}
					}
				}

				if($prevFile eq $keyString) {
					if (($currentSize > $prevSize && $prevSize ne 0) or ($prevSize eq 0)) {
						$IncFileSizeByte = $IncFileSizeByte + $currentSize - $prevSize;
					}
				} elsif($prevFile ne $keyString) {
					$IncFileSizeByte = $IncFileSizeByte + $currentSize;
				}
				$prevSize = $currentSize;
				$prevLine = $tmpLine;
				$prevFile = $keyString;
				$restoreType = ucfirst(lc($restoreType));
				my $sizeInBytes = convertToBytes($kbps);
				# if($sizeInBytes>0) {
					# $ctrf += $sizeInBytes;
					# $cumulativeDataTransRate = ($fileTransferCount && $ctrf)?($ctrf/$fileTransferCount):$ctrf;
					# $fileTransferCount++;
				# }

			#	if($totalSize ne Constants->CONST->{'CalCulate'}){
				$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n".$sizeInBytes."\n".$pKeyString;
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " "x($prevLen-$newLen);
					$pKeyString = $pKeyString.$pSpace;
				}
				$PROGRESSFILE[0] = "$restoreType Restore";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$sizeInBytes";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";
				$PROGRESSFILE[8] = $fileTransferCount;
				$PROGRESSFILE[9] = $fileSize;
				$PROGRESSFILE[10] = $completedFileSize;
				$prevLen = $newLen;
				#}
			}
			elsif($tmpLine =~ /$termData/is) {
				close TEMPOUTPUTFILE;
				unlink($tempIdevsOutputFile);
				$skipFlag = 1;
			}
			elsif($tmpLine ne '' and
				$tmpLine !~ m/building file list/ and
				$tmpLine !~ m/=============/ and
				$tmpLine !~ m/connection established/ and
				$tmpLine !~ m/bytes  received/ and
				$tmpLine !~ m/receiving file list/ and
				$tmpLine !~ m/Number of files/ and
				$tmpLine !~ m/\| FILE SIZE \| TRANSFERED SIZE \| TOTAL SIZE \|/ and
				$tmpLine !~ m/\%\]\s+\[/ and
				$tmpLine !~ m/$termData/is) {
					$errStr = $tmpLine;
					addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
				}
		}

		if($skipFlag){
			last;
		}
	}

	untie @PROGRESSFILE;
	# writeTransferRateAndCount($ctrf,$fileTransferCount);
}

#****************************************************************************************************
# Subroutine Name         : RestoreDedupOutputParse.
# Objective               : This function parse the Dedup evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub RestoreDedupOutputParse
{
	my ($curFileset,$silentFlag,$fileTransferCount,$operationEngineId) = @_;
	# my ($curFileset,$silentFlag,$operationEngineId) = @_;
    my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my ($prevSize,$cumulativeDataTransRate,$fileSyncCount) = (0) x 3;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @PROGRESSFILE;
	my $completedFileSize = 0;

	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	$completedFileSize = $PROGRESSFILE[10] if($PROGRESSFILE[10]);
	chmod $filePermission, $progressDetailsFilePath;

	my $tempIdevsOutputFile = $idevsOutputFile.'_'.$operationEngineId;
	while (!$fileNotOpened) {
		if(!-e $pidPath){
			last;
        }

		if(-e $tempIdevsOutputFile) {
			open TEMPOUTPUTFILE, "<", $tempIdevsOutputFile and $fileNotOpened = 1;
			chmod $filePermission, $tempIdevsOutputFile;
		}
		else{
			sleep(2);
		}
	}

	while (1) {
		$byteRead = read(TEMPOUTPUTFILE, $buffer, LIMIT);
		if($byteRead == 0) {
			if(!-e $pidPath or !-e $pidPath.'_evs_'.$operationEngineId){
				last;
			}
			sleep(2);
			seek(TEMPOUTPUTFILE, 0, 1);		#to clear eof flag
			next;
		}

		if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
			$buffer = $lastLine . $buffer;
		}

		my @resultList = split /\n/, $buffer;

		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}
		#for(my $cnt = 0; $cnt < $bufIndex; $cnt++) {
		foreach my $tmpLine (@resultList){
			#my $tmpLine = $resultList[$cnt];
			if($tmpLine =~ /<item/) {
				my %fileName = parseXMLOutput(\$tmpLine);
				if(scalar(keys %fileName) < 5) {
					Common::traceLog("Restore output line: $tmpLine");
					next;
				}

				my $restoreFinishTime = localtime;
				# my $fileSize = undef;
				#my $keyString = $pathSeparator.$fields[$fields_in_progress-2];
				my $keyString = $pathSeparator.$fileName{'fname'};
				$keyString =~ s/^$restoreHost// if($operationName eq 'LOCAL_RESTORE_OPERATION');
				replaceXMLcharacters(\$keyString);
				$keyString = Common::removeMultipleSlashs($keyString);
				my $pKeyString = $keyString;

				my $restoreType = $fileName{'trf_type'};
				$restoreType =~ s/FILE IN//;
				$restoreType =~ s/\s+//;

				my $kbps 	    = $fileName{'rate_trf'};
				my $fileSize    = $fileName{'size'};
				my $currentSize = defined($fileName{'offset'})?$fileName{'offset'}:$fileSize;
				my $percentage	= $fileName{'per'};
				my $totsize 	= $fileName{'size'};

				if($relative eq NORELATIVE) {
					my $indx = rindex ($pKeyString, '/');
					$pKeyString = substr($pKeyString, $indx);
				}

				if($tmpLine =~ m/$operationComplete/) {
					if($restoreType eq 'SYNC') { 		# check if file in sync
						if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 2;
							$completedFileSize += $totsize;
						} else {
							$fullPath = getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize, 2);
							if($fullPath) {
								$completedFileSize += $totsize;
							}
						}
						# $fileSyncCount++;
					}
					elsif($restoreType eq 'FULL' or $restoreType eq 'INCREMENTAL') {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString}{'status'})) {
							if($fileSetHash{$keyString}{'status'} != 1){
								$fileSetHash{$keyString}{'status'} = 1;
                                my $logRestoreType = ($restoreType eq 'INCREMENTAL')?$restoreType:(((" ") x 4).$restoreType.((" ") x 3));
                                $fileSetHash{$keyString}{'detail'} = "[$restoreFinishTime] [SUCCESS] [$logRestoreType]";
                                $fileSetHash{$keyString}{'size'} = $fileSize;
								# $fileRestoreCount++;
								$transferredFileSize += $fileSize;
								if($percentage eq '100%') {
									$completedFileSize += $totsize;
								}
							}
						}
						else {
							if(getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize, 1) == 1) {
								# $fileRestoreCount++;
								$transferredFileSize += $fileSize;
								if($percentage eq '100%') {
									$completedFileSize += $totsize;
								}
							}
						}
                        $modifiedCount++ if($restoreType eq 'INCREMENTAL');
					}
					else {
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}
					$fileTransferCount++;
				}
				if($totalSize eq Constants->CONST->{'CalCulate'}) {
					if(open(FILESIZE, "<$fileForSize")) {
						$totalSize = <FILESIZE>;
						close(FILESIZE);
						chomp($totalSize);
						if($totalSize eq "") {
							$totalSize = Constants->CONST->{'CalCulate'};
						}
					}
				}
				#$fields[1] =~ s/^\s+|\s+$//;
				#$currentSize = $fields[1];
				if($prevFile eq $keyString) {
					if (($currentSize > $prevSize && $prevSize ne 0) or ($prevSize eq 0)) {
						$IncFileSizeByte = $IncFileSizeByte + $currentSize - $prevSize;
					}
				} elsif($prevFile ne $keyString) {
					$IncFileSizeByte = $IncFileSizeByte + $currentSize;
				}
				$prevSize = $currentSize;
				$prevLine = $tmpLine;
				$prevFile = $keyString;
				$restoreType = ucfirst(lc($restoreType));
				my $sizeInBytes = convertToBytes($kbps);
				# Common::traceLog("keyString:$keyString#kbps:$kbps#sizeInBytes:$sizeInBytes#");
				# if($sizeInBytes>0) {
					# $ctrf += $sizeInBytes;
					# $cumulativeDataTransRate = ($fileTransferCount && $ctrf)?($ctrf/$fileTransferCount):$ctrf;
					# $fileTransferCount++;
				# }
				# Common::traceLog("cumulativeDataTransRate:$cumulativeDataTransRate#IncFileSizeByte:$IncFileSizeByte#");
				$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n".$sizeInBytes."\n".$pKeyString;
				
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " "x($prevLen-$newLen);
					$pKeyString = $pKeyString.$pSpace;
				}
				$PROGRESSFILE[0] = "$restoreType Restore";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$sizeInBytes";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";
				$PROGRESSFILE[8] = $fileTransferCount;
				$PROGRESSFILE[9] = $fileSize;
				$PROGRESSFILE[10] = $completedFileSize;
				$prevLen = $newLen;
			}
			elsif($tmpLine =~ /$termData/is) {
				close TEMPOUTPUTFILE;
				unlink($tempIdevsOutputFile);
				$skipFlag = 1;
			}
			elsif($tmpLine ne '' and
				$tmpLine !~ m/building file list/ and
				$tmpLine !~ m/=============/ and
				$tmpLine !~ m/connection established/ and
				$tmpLine !~ m/bytes  received/ and
				$tmpLine !~ m/receiving file list/ and
				$tmpLine !~ m/Number of files/ and
				$tmpLine !~ m/\| FILE SIZE \| TRANSFERED SIZE \| TOTAL SIZE \|/ and
				$tmpLine !~ m/\%\]\s+\[/ and
				$tmpLine !~ m/$termData/is) {
					$errStr = $tmpLine;
					addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
				}
		}

		if($skipFlag){
			last;
		}
	}

	untie @PROGRESSFILE;
	# writeTransferRateAndCount($ctrf,$fileTransferCount);
}
#****************************************************************************************************
# Subroutine Name         : writeToCrontab.
# Objective               : Append an entry to crontab file.
# Modified By             : Dhritikana.
#*****************************************************************************************************/
sub writeToCrontab {
	my $cron = "/etc/crontab";
	exit 0 if(!open CRON, ">", $cron);
	print CRON @_;
	close(CRON);
	exit 0;
}
#****************************************************************************************************
# Subroutine Name         : readTransferRateAndCount.
# Objective               : Read Transfer Rate And Count of previous operation.
# Modified By             : Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub readTransferRateAndCount {
	my @lines = (0,1);
	if(-e $trfSizeAndCountFile and -s _ > 0) {
		if(open FILEH, "<", $trfSizeAndCountFile){
			@lines = <FILEH>;
			close FILEH;
			Chomp(\$lines[0]);
			Chomp(\$lines[1]);
		}
	}
	return @lines;
}

#****************************************************************************************************
# Subroutine Name         : writeTransferRateAndCount.
# Objective               : Write Transfer Rate And Count of current operation.
# Modified By             : Senthil Pandian.
#*****************************************************************************************************/
sub writeTransferRateAndCount {
	my ($trfRate,$count) = @_;
	if(open FILEH, ">", $trfSizeAndCountFile){
		print FILEH $trfRate.$lineFeed.$count;
		close FILEH;
	}
}

#****************************************************************************************************
# Subroutine Name         : updateUserLogForBackupRestoreFiles.
# Objective               : Writes the data in user log after one backup/Restore set complete.
# Modified By             : Vijay Vinoth.
#*****************************************************************************************************/
sub updateUserLogForBackupRestoreFiles {
	my $outputFilePath = $_[0];
	my $details = '';
	my $isLocked = 0;
	if(open(OUTFILE, ">> $outputFilePath")) {
		chmod $filePermission, $outputFilePath;
	}
	else {
		Common::traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."outputFilePath: ".$outputFilePath." Reason:$!");
		print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$outputFilePath: ".$outputFilePath." Reason:$! $lineFeed";
		return 0;
	}

	$isLocked = 1 if(flock(OUTFILE, LOCK_EX));

	my $pKeyString = '';
	foreach my $fileSetHashName (sort keys %fileSetHash) {
		$details = '';
		if($fileSetHash{$fileSetHashName}{'detail'} ne '' and $fileSetHash{$fileSetHashName}{'status'} == 1){
			$pKeyString = $fileSetHashName;
			if($relative eq NORELATIVE and $dedup ne 'on') {
				my $index = rindex ($pKeyString, '/');
				$pKeyString = substr($pKeyString, $index);
			}
			$details = "$fileSetHash{$fileSetHashName}{'detail'} [$pKeyString] [".Common::convertFileSize($fileSetHash{$fileSetHashName}{'size'})."]";
			print OUTFILE $details.$lineFeed;
		}
	}

	# if($isLocked){
		# flock(OUTFILE, LOCK_UN);
	# }
	# else{
		# traceLog("Unable to lock LOG file", __FILE__, __LINE__);
	# }
	close OUTFILE;
}

#****************************************************************************************************
# Subroutine Name         : getUpdateRetainedFilesList.
# Objective               : Change the status from success to failure if failed verification data exists.
# Modified By             : Vijay Vinoth.
#*****************************************************************************************************/
sub getUpdateRetainedFilesList {
	my @individual_errorfileContentsDetails = @_;
=beg
	open BACKUP_RESTORE_ERROR_DATA, "<", $currentErrorFile;
	my @individual_errorfileContentsDetails = <BACKUP_RESTORE_ERROR_DATA>;
	close BACKUP_RESTORE_ERROR_DATA;
	chomp(@individual_errorfileContentsDetails);
=cut
	my $j = 0;
	my $serverRoot = '';
	my $replace = '';

	$serverRoot = Common::getUserConfiguration('BACKUPLOCATION');
	$serverRoot = "/".Common::getUserConfiguration('SERVERROOT') if($dedup eq 'on');
	my $backupType = Common::getUserConfiguration('BACKUPTYPE');

	for(;$j <= $#individual_errorfileContentsDetails; $j++){
		chomp($individual_errorfileContentsDetails[$j]);
		if($dedup eq 'on'){
			if($individual_errorfileContentsDetails[$j] =~ /failed verification -- update retained/i){
				$individual_errorfileContentsDetails[$j] =~ s/\Q$serverRoot\E/$replace/g;
				$individual_errorfileContentsDetails[$j] =~ s/\QERROR: \E/$replace/g;
				$individual_errorfileContentsDetails[$j] =~ s/\Q failed verification -- update retained.\E/$replace/g;
			}
			else{
				next;
			}
		}
		elsif(($individual_errorfileContentsDetails[$j] =~ /idevs: read errors mapping /i)){
			if($individual_errorfileContentsDetails[$j] =~ m|\[(.*)\]|){
				$individual_errorfileContentsDetails[$j] = $1;
			}
		}
		else{
			next;
		}

		Common::Chomp(\$individual_errorfileContentsDetails[$j]);
		$individual_errorfileContentsDetails[$j] =~ s/\/\//\//;
		if($fileSetHash{$individual_errorfileContentsDetails[$j]}{'status'} >= 1){
			#$fileBackupCount--;
			$fileSetHash{$individual_errorfileContentsDetails[$j]}{'status'} = 3;
			$updateRetainedFilesSize += $fileSetHash{$individual_errorfileContentsDetails[$j]}{'size'};
		} elsif($dedup ne 'on' and $backupType ne 'mirror') {
			checkUpdateRetainedForRelative($individual_errorfileContentsDetails[$j]);
		}
	}
}

#****************************************************************************************************
# Subroutine Name     : reduceUpdateRetainSizeInprogress.
# Objective           : Change the status from success to failure if failed verification data exists.
# Added By            : Vijay Vinoth
# Modified By         : Senthil Pandian, Sabin Cheruvattil
#*****************************************************************************************************/
sub reduceUpdateRetainSizeInprogress {
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_" . $operationEngineId;
	my @progressDetailsFileData;
	if(-e $progressDetailsFilePath and !-z _ and $updateRetainedFilesSize > 0) {
		if (open my $fh, '+<', $progressDetailsFilePath) {
			@progressDetailsFileData = <$fh>;
			chomp($progressDetailsFileData[2]);
			$progressDetailsFileData[2] -= $updateRetainedFilesSize;
			close $fh;
		}

		if (open my $fhW, '>', $progressDetailsFilePath) {
			my $progressData = $progressDetailsFileData[0].$progressDetailsFileData[1].$progressDetailsFileData[2]."\n".$progressDetailsFileData[3].$progressDetailsFileData[4].$progressDetailsFileData[5];
			print $fhW $progressData;
			close $fhW;
		}
	}
}

#****************************************************************************************************
# Subroutine		: reduceRetryFileSizeInprogress.
# Objective			: Reduce the file size from progress when file is going to retry.
# Added By			: Senthil Pandian
# Modified By		: Sabin Cheruvattil, Senthil Pandian
#*****************************************************************************************************/
sub reduceRetryFileSizeInprogress {
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @progressDetailsFileData;
	if(-e $progressDetailsFilePath and !-z _) {
		if (open my $fh, '+<', $progressDetailsFilePath) {
			@progressDetailsFileData = <$fh>;
			chomp($progressDetailsFileData[2]);
			chomp($progressDetailsFileData[6]);
			chomp($progressDetailsFileData[7]);
			if($progressDetailsFileData[7] ne '100%' and $progressDetailsFileData[6] > 0 and $progressDetailsFileData[2] >= $progressDetailsFileData[6]) {
				$progressDetailsFileData[2] -= $progressDetailsFileData[6];
			}
			close $fh;
		}

		if (open my $fhW, '>', $progressDetailsFilePath) {
			my $progressData = $progressDetailsFileData[0].$progressDetailsFileData[1].$progressDetailsFileData[2]."\n".$progressDetailsFileData[3].$progressDetailsFileData[4].$progressDetailsFileData[5].$progressDetailsFileData[6]."\n".$progressDetailsFileData[7];
			print $fhW $progressData;
			close $fhW;
		}
	}
}

#****************************************************************************************************
# Subroutine Name     : getCountDetails.
# Objective           :
# Added By            : Vijay Vinoth
#*****************************************************************************************************/
sub getCountDetails{
	my ($fileSuccessCount,$fileSyncCount) = (0) x 2;
	foreach my $ref (keys %fileSetHash){
	   $fileSuccessCount++ if($fileSetHash{$ref}{'status'} == 1);
	   $fileSyncCount++ if($fileSetHash{$ref}{'status'} == 2);
	}
	return ($fileSuccessCount,$fileSyncCount);
}

#****************************************************************************************************
# Subroutine Name     : readEVSErrorFile.
# Objective           : Read the error content & keep it in array
# Added By            : Senthil Pandian
#*****************************************************************************************************/
sub readEVSErrorFile{
	my @errorContent = ();
	my $evsErrorFile 	 = $_[1];
	my $currentErrorFile = $_[0];

	if(-e $evsErrorFile and !-z $evsErrorFile) {
		if (open my $fh, '+<', $evsErrorFile) {
			@errorContent = <$fh>;
			close $fh;
			chomp(@errorContent);
		}
		unlink($evsErrorFile);
	}

	if(-e $currentErrorFile and !-z $currentErrorFile) {
		if (open my $fh, '+<', $currentErrorFile) {
			my @tempArray = <$fh>;
			close $fh;
			chomp(@tempArray);

			push(@errorContent, @tempArray) if(scalar(@tempArray));
		}
		unlink($currentErrorFile);
	}

	return @errorContent;
}
#***************************************************************************************************
# Subroutine/Function   : waitForNetworkConnection
# In Param  :
# Out Param :
# Objective     : This subroutine to wait for network connection
# Added By      : Senthil Pandian
# Modified By :
#****************************************************************************************************/
sub waitForNetworkConnection {
   while(1) {
		last unless(-f $pidPath);
        my $isInternetAvailable = Common::isInternetAvailable();
        Common::traceLog("isInternetAvailable:$operationEngineId: $isInternetAvailable");
        #last if(Common::isInternetAvailable());
        last if($isInternetAvailable);
        Common::traceLog("waitForNetworkConnection:$operationEngineId: Network is unreachable");
        sleep(30);
    }
=beg
        while(1) {
                last unless(-f $pidPath);
                unless(Common::isInternetAvailable()){
                        Common::fileWrite("/tmp/trace$operationEngineId","Network is unreachable\n","APPEND");
                        Common::traceLog("waitForNetworkConnection:$operationEngineId: Network is unreachable");
                        sleep(30); #Sleep for 30 sec
                        next;
                }
                Common::fileWrite("/tmp/trace$operationEngineId","Network is reachable\n","APPEND");
                Common::traceLog("waitForNetworkConnection:$operationEngineId: Network is reachable");
                last;
        }
=cut
}

