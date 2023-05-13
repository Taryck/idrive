#!/usr/bin/env perl

###############################################################################
#Script Name : Operations.pl
###############################################################################

$incPos = rindex(__FILE__, '/');
$incLoc = ($incPos>=0)?substr(__FILE__, 0, $incPos): '.';
unshift (@INC,$incLoc);

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
my $fileBackupCount = 0;
my $fileRestoreCount = 0;
my $fileSyncCount = 0;
my $failedfiles_count = 0;
my $deniedFilesCount = 0;
my $missingCount = 0;
our $exit_flag = 0;
my $retryAttempt = false; # flag to indicate the backup script to retry the backup/restore
my @currentFileset = ();
my $totalSize = Constants->CONST->{'CalCulate'};
my $parseCount = 0;
my $IncFileSizeByte = 0;
my $modSize = 0;

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
if(!$userName) {
	$userName = $ARGV[1];
}

loadUserData();
# Reading the configurationFile - End

my $curFile = basename(__FILE__);
my $jobRunningDir = $ARGV[0];
my $operationEngineId = $ARGV[2];
my $retry_failedfiles_index = $ARGV[3];
my ($current_source)=('');
($progressSizeOp,$bwThrottle,$backupPathType) = ('') x 3;#These variables are initialized in operations subroutine after reading parameters from temp_file.
my $temp_file = "$jobRunningDir/operationsfile.txt";#This files contains value to the parameters which is used during backup, restore etc jobs. This file is written in Backup_Script.pl file and Restore_Script.pl file before call to operation file is done. In operation file various operation related to job is done.
my $pidPath = "$jobRunningDir/pid.txt";
my $evsTempDirPath = "$jobRunningDir/evs_temp";
$statusFilePath = "$jobRunningDir/STATUS_FILE";
my $retryinfo = "$jobRunningDir/".$retryinfo;
$idevsOutputFile = "$jobRunningDir/output.txt";
$idevsErrorFile = "$jobRunningDir/error.txt";
my $fileForSize = "$jobRunningDir/TotalSizeFile";
#my $incSize = "$jobRunningDir/transferredFileSize.txt";
my $trfSizeAndCountFile = "$jobRunningDir/trfSizeAndCount.txt";

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
# $SIG{INT} = \&process_term;
# $SIG{TERM} = \&process_term;
# $SIG{TSTP} = \&process_term;
# $SIG{QUIT} = \&process_term;
# $SIG{PWR} = \&process_term;
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
	#print "operationName:$operationName#\n\n";
	chomp (@param) if ($operationName ne 'WRITE_TO_CRON');
	($current_source,$progressSizeOp,$bwThrottle,$backupPathType,$flagForSchdule) = ($param[3],$param[4],$param[6],$param[8],$param[9]);
	$isScheduledJob = 1 if($flagForSchdule =~ /scheduled/i);
#====================================================Operation Based on operation name==========================#
	if($operationName eq 'WRITE_TO_CRON') {
		writeToCrontab(@param);
		exit;
    }
	elsif($operationName eq 'READ_CRON_ENTRIES'){
		readFromCrontab();
		print @linesCrontab;
		exit;
	}
	elsif($operationName eq 'BACKUP_OPERATION' or $operationName eq 'LOCAL_BACKUP_OPERATION'){
		my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
		$jobType = q(backup);
		if($operationName eq 'LOCAL_BACKUP_OPERATION'){
			$jobType = q(localbackup);
			$idevsOutputFile = "$jobRunningDir/evsOutput.txt";
			$idevsErrorFile  = "$jobRunningDir/evsError.txt";
		}
		getCurrentFileSet($param[1]);
		our ($ctrf,$fileTransferCount) = readTransferRateAndCount();
		$backupHost = $param[5];
		getProgressDetais($progressDetailsFilePath);
		if($dedup eq 'on'){
			BackupDedupOutputParse($param[0],$param[1],$param[7],$fileTransferCount,$operationEngineId);
		} else {
			BackupOutputParse($param[0],$param[1],$param[2],$param[7],$fileTransferCount,$operationEngineId);
		}
		subErrorRoutine($param[1]);
		updateUserLogForBackupRestoreFiles($param[0]);
		writeParameterValuesToStatusFile($fileBackupCount, $fileRestoreCount, $fileSyncCount, $failedfiles_count, $deniedFilesCount, $missingCount, $transferredFileSize, $exit_flag, $failedfiles_index, $operationEngineId);
	}
	elsif($operationName eq 'RESTORE_OPERATION'){
		my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
		$jobType = q(restore);
		getCurrentFileSet($param[1]);
		$restoreHost = $param[5];
        $restoreLocation = $param[6];
		our ($ctrf,$fileTransferCount) = readTransferRateAndCount();
		getProgressDetais($progressDetailsFilePath);
		if($dedup eq 'on'){
			RestoreDedupOutputParse($param[0],$param[1],$param[7],$fileTransferCount,$operationEngineId);
		} else {
			RestoreOutputParse($param[0],$param[1],$param[2],$param[7],$fileTransferCount,$operationEngineId);
		}
		subErrorRoutine($param[1]);
		updateUserLogForBackupRestoreFiles($param[0]);
		writeParameterValuesToStatusFile($fileBackupCount, $fileRestoreCount, $fileSyncCount, $failedfiles_count, $deniedFilesCount, $missingCount, $transferredFileSize, $exit_flag, $failedfiles_index, $operationEngineId);
	}
	else{
		traceLog("$operationName : function not in this file",__FILE__, __LINE__);
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
	if ($operationEngineId ne ""){
		$operationEngineIdData = "_".$operationEngineId;
	}

	if (-e $temp_file.$operationEngineIdData){
		if(!open(TEMP_FILE, "<",$temp_file.$operationEngineIdData)){
			$errStr = "Could not open file temp_file in Child process: $temp_file, Reason:$!";
			traceLog($errStr,__FILE__, __LINE__);
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
	open FILESET, "< $curFileset" or traceLog("Couldn't open file $curFileset $!.",__FILE__, __LINE__) and return;
	if($curFileset =~ /versionRestore/) {
		my $param = <FILESET>;
		my $idx = rindex($param, "_");
		$param = substr($param, 0, $idx);
		$fileSetHash{$param}{'status'} = 0;
		$fileSetHash{$param}{'detail'} = '';
		$fileSetHash{$param}{'size'} = '';
		push @currentFileset, $param;
		#$versionRes = 1;
	} else {
		while(<FILESET>) {
			chomp($_);
			$fileSetHash{$_}{'status'} = 0;
			$fileSetHash{$_}{'detail'} = '';
			$fileSetHash{$_}{'size'} = '';
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
#Subroutine Name         : getProgressDetais
#Objective               : This subroutine gives backup and restore progress details.
#			 : This subrutine evolved after merging backupProgressDetails and restoreProgressDetails subroutine. Few parts of this subroutine has been rmoved and added at other places so that functionalities can be made common.
#Added By                : Abhishek Verma.
#*****************************************************************************************************/
sub getProgressDetais{
	my ($progressDetailsFilePath) = @_;

	if(-e $progressDetailsFilePath and -s $progressDetailsFilePath > 0)
	{
		if(open(progressDetails, "<", $progressDetailsFilePath)) {
			chomp(my @progressDetailsFileData = <progressDetails>);
			$IncFileSizeByte = $progressDetailsFileData[2];
			chomp($IncFileSizeByte);
		}
	}
}
#****************************************************************************************************
# Subroutine Name         : BackupOutputParse.
# Objective               : This function monitors and parse the evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Deepak Chaurasia
#**************************#***************************************************************************/
sub BackupOutputParse
{
	our ($outputFilePath,$curFileset,$relative,$silentFlag,$fileTransferCount,$operationEngineId) = @_;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my ($prevSize,$currentSize,$cumulativeDataTransRate) = (0) x 3;
	my $initialSlash;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @PROGRESSFILE;
	if($operationName eq 'BACKUP_OPERATION'){
		$initialSlash = '/';
	} else {
		$initialSlash = '';
	}


	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	chmod $filePermission, $progressDetailsFilePath;

	my $tempIdevsOutputFile = $idevsOutputFile.'_'.$operationEngineId;
	while(!$fileNotOpened) {
		if(!-e $pidPath){
			last;
		}
		if(-e $tempIdevsOutputFile) {
			chmod $filePermission, $tempIdevsOutputFile;
			open TEMPOUTPUTFILE, "<", $tempIdevsOutputFile and $fileNotOpened = 1;
		}
		else{
			sleep(2);
		}
	}

	while (1) {
		$byteRead = read(TEMPOUTPUTFILE, $buffer, LIMIT);
		if($byteRead == 0) {
			if(!-e $pidPath){
				last;
			}
			sleep(2);
			seek(TEMPOUTPUTFILE, 0, 1);		#to clear eof flag
			next;
		}

		$tryCount = 0;

		if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
			$buffer = $lastLine . $buffer;
		}

		my @resultList = split /\n/, $buffer;

		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			#$lastLine = $resultList[$#resultList];
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}

		foreach my $tmpLine (@resultList){
			if($tmpLine =~ /<item/) {
				my %fileName = parseXMLOutput(\$tmpLine);
				next if(scalar(keys %fileName) < 5);

				my $keyString 		= $initialSlash.$fileName{'fname'};
				my $fileSize 	    = $fileName{'size'};
				my $fileBackupType  = $fileName{'trf_type'};
				my $rateOfTransfer  = $fileName{'rate_trf'};

				my $currentSize     = $fileName{'size'};
				$currentSize        = $fileName{'offset'}	if($fileName{'offset'});
				my $percentage		= $fileName{'per'};

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
						$fileSyncCount++;
						if(defined($fileSetHash{$keyString}{'status'})) {
							next if($fileSetHash{$keyString}{'status'});
							$fileSetHash{$keyString}{'status'} = 1;
						} else {
							$retVal = getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize);
							next if($retVal==2);
						}
					}
					elsif($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL") {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString}{'status'})) {
							if($fileSetHash{$keyString}{'status'} != 1){
								$fileSetHash{$keyString}{'status'} = 1;
								$fileSetHash{$keyString}{'detail'} = "[$backupFinishTime] [$backupType Backup]";
								$fileSetHash{$keyString}{'size'} = $fileSize;
								$fileBackupCount++;
								$transferredFileSize += $fileSize;
							} else {
								next;
							}
						} else {
							$retVal = getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize);
							if($retVal == 1){
								$fileBackupCount++;
								$transferredFileSize += $fileSize;
							} elsif($retVal == 2){
								next;
							}
						}
					}
					else{
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}
					$parseCount++;
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
				$backupType = ucfirst(lc($backupType));
				my $sizeInBytes = convertToBytes($rateOfTransfer);
				if($sizeInBytes>0) {
					$ctrf += $sizeInBytes;
					$cumulativeDataTransRate = ($ctrf/$fileTransferCount);
					$fileTransferCount++;
				}

				#if($totalSize ne Constants->CONST->{'CalCulate'}){
				$progress = "$backupType Backup"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n".$cumulativeDataTransRate."\n".$pKeyString;
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " "x($prevLen-$newLen);
					$pKeyString = $pKeyString.$pSpace;
				}
				$PROGRESSFILE[0] = "$backupType Backup";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$cumulativeDataTransRate";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";
				$prevLen = $newLen;
				#}
			}
			elsif($tmpLine =~ /$termData/ ) {
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
			$tmpLine !~ m/$termData/) {
					$errStr = $tmpLine;
					addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
				}
			}

		if($skipFlag) {
			last;
		}
	}

	untie @PROGRESSFILE;
	writeTransferRateAndCount($ctrf,$fileTransferCount);
}

#****************************************************************************************************
# Subroutine Name         : BackupDedupOutputParse.
# Objective               : This function parse the Dedup evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub BackupDedupOutputParse
{
	our ($outputFilePath,$curFileset,$silentFlag,$fileTransferCount,$operationEngineId) = @_;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 21;
	my ($prevSize,$currentSize,$cumulativeDataTransRate) = (0) x 3;
	my $initialSlash;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @PROGRESSFILE;
	if($operationName eq 'BACKUP_OPERATION'){
		$initialSlash = '/';
	} else {
		$initialSlash = '';
	}

	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
	$IncFileSizeByte = $PROGRESSFILE[2];
	chmod $filePermission, $progressDetailsFilePath;

	my $tempIdevsOutputFile = $idevsOutputFile.'_'.$operationEngineId;

	while(!$fileNotOpened) {
		if(!-e $pidPath){
			last;
		}
		if(-e $tempIdevsOutputFile) {
			chmod $filePermission, $tempIdevsOutputFile;
			open TEMPOUTPUTFILE, "<", $tempIdevsOutputFile and $fileNotOpened = 1;
		}
		else{
			sleep(2);
		}
	}
	while (1) {
		$byteRead = read(TEMPOUTPUTFILE, $buffer, LIMIT);
		if($byteRead == 0) {
			if(!-e $pidPath){
				last;
			}
			sleep(2);
			seek(TEMPOUTPUTFILE, 0, 1);		#to clear eof flag
			next;
		}

		$tryCount = 0;

		if("" ne $lastLine)	{		# need to check appending partial record to packet or to first line of packet
			$buffer = $lastLine . $buffer;
		}

		my @resultList = split /\n/, $buffer;

		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			#$lastLine = $resultList[$#resultList];
			$lastLine = pop @resultList;
		}
		else {
			$lastLine = "";
		}

		foreach my $tmpLine (@resultList){
			if($tmpLine =~ /<item/) {
				my %fileName = parseXMLOutput(\$tmpLine);
				if(scalar(keys %fileName) < 5){
					next;
				}

				#my $keyString = $initialSlash.$fields[($fields_in_progress-$fNamePos)];
				#my $fileSize = convertFileSize($fields[3]);
				#$backupType = $fields[($fields_in_progress-$typePos)];

				my $keyString 		= $initialSlash.$fileName{'fname'};
				my $fileSize 	    = $fileName{'size'};
				my $fileBackupType  = $fileName{'trf_type'};
				   #$fileBackupType =~ s/^\s+//;
				my $rateOfTransfer  = $fileName{'rate_trf'};
				my $currentSize     = $fileName{'offset'};
				my $backupType      = $fileBackupType;
				$backupType =~ s/FILE IN//;
				$backupType =~ s/\s+//;
				my $percentage		= $fileName{'per'};
				my $backupFinishTime = localtime;
				replaceXMLcharacters(\$keyString);
				my $pKeyString = $keyString;

				if($tmpLine =~ m/$operationComplete/) {

					if($fileBackupType eq "FILE IN SYNC") { 		# check if file in sync
						$fileSyncCount++;
						if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize);
						}
					}
					elsif($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL") {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString}{'status'})) {
							if($fileSetHash{$keyString}{'status'} != 1){
								$fileSetHash{$keyString}{'status'} = 1;
								$fileSetHash{$keyString}{'detail'} = "[$backupFinishTime] [$backupType Backup]";
								$fileSetHash{$keyString}{'size'} = $fileSize;
								$fileBackupCount++;
								$transferredFileSize += $fileSize;
							}
						} else {
							if(getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize) == 1){
								$fileBackupCount++;
								$transferredFileSize += $fileSize;
							}
						}
					}
					else{
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}
					$parseCount++;
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
				$backupType = ucfirst(lc($backupType));
				my $sizeInBytes = convertToBytes($rateOfTransfer);
				if($sizeInBytes>0) {
					$ctrf += $sizeInBytes;
					$cumulativeDataTransRate = ($ctrf/$fileTransferCount);
					$fileTransferCount++;
				}

				$progress = "$backupType Backup"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n".$cumulativeDataTransRate."\n".$pKeyString;
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " "x($prevLen-$newLen);
					$pKeyString = $pKeyString.$pSpace;
				}
				$PROGRESSFILE[0] = "$backupType Backup";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$cumulativeDataTransRate";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";

				$prevLen = $newLen;

			}
			elsif($tmpLine =~ /$termData/ ) {
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
			$tmpLine !~ m/$termData/) {
					$errStr = $tmpLine;
					addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
				}
		}

		if($skipFlag) {
			last;
		}
	}

	untie @PROGRESSFILE;
	writeTransferRateAndCount($ctrf,$fileTransferCount);
}
#****************************************************************************************************
# Subroutine Name         : subErrorRoutine.
# Objective               : This function monitors and parse the evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Deepak Chaurasia
# Modified By			  : Dhritikana
#*****************************************************************************************************/
sub subErrorRoutine
{
	my $curFileset = shift;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $individual_errorfile = "$currentErrorFile";
	copyTempErrorFile($individual_errorfile,$operationEngineId);
	getUpdateRetainedFilesList($currentErrorFile);
	$failedfiles_count = getFailedFileCount();
	#Check if retry is required
	$failedfiles_index = getParameterValueFromStatusFile('FAILEDFILES_LISTIDX',$operationEngineId);

	if($failedfiles_count > 0 and $failedfiles_index != -1) {
		if(!checkretryAttempt($individual_errorfile)){
			updateFailedFileCount($curFileset);
			getFinalErrorFile($curFileset);
			return;
		}
	} else {
		updateFailedFileCount($curFileset);
		getFinalErrorFile($curFileset);
		return;
	}

	if(!$retryAttempt or $failedfiles_index == -1) {
		getFinalErrorFile($curFileset);
	} else {
		$failedfiles_index++;
		$failedfiles = $jobRunningDir."/".$failedFileName.$retry_failedfiles_index;
		my $oldfile_error = $currentErrorFile;
		my $newfile_error = $jobRunningDir."/ERROR/$failedFileName$retry_failedfiles_index"."_ERROR";
		if(-e $oldfile_error) {
			rename $oldfile_error, $newfile_error;
		}
		if(!open(FAILEDLIST, "> $failedfiles")) {
			traceLog("Could not open file failedfiles in SubErrorRoutine: $failedfiles, Reason:$!",__FILE__, __LINE__);
			updateFailedFileCount($curFileset);
			return;
		}
		chmod $filePermission, $failedfiles;

		for(my $i = 0; $i <= $#failedfiles_array; $i++) {
			print FAILEDLIST "$failedfiles_array[$i]\n";
		}
		close FAILEDLIST;

		if(-e $failedfiles){
			open RETRYINFO, ">> $retryinfo";
			print RETRYINFO "$current_source' '$relative' '$failedfiles\n";
			close RETRYINFO;
			chmod $filePermission, $retryinfo;
		}
		reduceUpdateRetainSizeInprogress();
	}

	updateFailedFileCount($curFileset);
}
#**********************************************************************************************************
# Subrotine Name         : getFailedFileCount
# Objective               : This subroutine gets the failed files count from the failedfiles array
# Modified By             : Pooja Havaldar
#********************************************************************************************************/
sub getFailedFileCount
{
	my $failed_count = 0;
	for(my $i = 0; $i <= $#currentFileset; $i++){
		chomp $currentFileset[$i];
		if($fileSetHash{$currentFileset[$i]}{'status'} == 0){
			$failedfiles_array[$failed_count] = $currentFileset[$i];
			$failed_count++;
		}
	}
	return $failed_count;
}

#****************************************************************************************************
# Subroutine Name		: getFullPathofFile.
# Objective				: Fill the hash if we are not able to find the reference
# Added By				: Pooja Havaldar
# Modified By			: Sabin Cheruvattil,Vijay Vinoth
#*****************************************************************************************************
sub getFullPathofFile {
	$fileToCheck = $_[0];
	my $restoreFinishTime = $_[1];
	my $restoreType = $_[2];
	my $fileSize = $_[3];
	for(my $i = $#currentFileset ; $i >= 0; $i--){
		$a = rindex ($currentFileset[$i], '/');
		$match = substr($currentFileset[$i],$a);

		if($fileToCheck eq $match){
			next if($fileSetHash{$currentFileset[$i]}{'status'} == 1);
			$fileSetHash{$currentFileset[$i]}{'status'} = 1;
			$fileSetHash{$currentFileset[$i]}{'detail'} = "[$restoreFinishTime] [$restoreType Restore]";
			$fileSetHash{$currentFileset[$i]}{'size'} = $fileSize;
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
			if($fileSetHash{$currentFileset[$i]}{'status'} == 1){
				$fileBackupCount--;
				$fileSetHash{$currentFileset[$i]}{'status'} = 0;
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
	my $curFileset = shift;
	$orig_count = getParameterValueFromStatusFile('ERROR_COUNT_FILES',$operationEngineId);
	if($curFileset =~ m/failedfiles.txt/) {
		$size_Backupset = $#currentFileset+1;
		$newcount = $orig_count - $size_Backupset + $failedfiles_count;
		$failedfiles_count = $newcount;
	} else {
		$orig_count += $failedfiles_count;
		$failedfiles_count = $orig_count;
	}
}

#****************************************************************************************************
# Subroutine Name         : checkretryAttempt.
# Objective               : This function checks whether backup has to retry
# Added By				  : Pooja Havaldar
#*****************************************************************************************************/
sub checkretryAttempt
{
	my $errorline = "idevs error";
	my $individual_errorfile = $_[0];

	if(!-e $individual_errorfile) {
		return 0;
	}
	#check for retry attempt
	if(!open(TEMPERRORFILE, "< $individual_errorfile")) {
		traceLog("Could not open file individual_errorfile in checkretryAttempt: $individual_errorfile, Reason:$!",__FILE__, __LINE__);
		return 0;
	}

	@linesBackupErrorFile = <TEMPERRORFILE>;
	close TEMPERRORFILE;
	# traceLog(@linesBackupErrorFile);
	chomp(@linesBackupErrorFile);
	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;

		if($linesBackupErrorFile[$i] eq "" or $linesBackupErrorFile[$i] =~ m/$errorline/){
			next;
		}

		for(my $j=0; $j<=$#ErrorArgumentsExit; $j++)
		{
			if($linesBackupErrorFile[$i] =~ m/$ErrorArgumentsExit[$j]/)
			{
				#$errStr = "Operation could not be completed. Reason : $ErrorArgumentsExit[$j]. Please login using Login.pl script.";
				if($ErrorArgumentsExit[$j]=~/skipped-over limit|quota over limit/i){
					$errStr = Constants->CONST->{'operationNotcomplete'}." ".Constants->CONST->{'QuotaOverLimit'};
				} elsif($ErrorArgumentsExit[$j] =~ /unauthorized user/i) {
					Helpers::getServerAddress();
				} else {
					$errStr = Constants->CONST->{'operationNotcomplete'}." Reason : $ErrorArgumentsExit[$j].";
				}
				traceLog($errStr,__FILE__, __LINE__);
				#kill evs and then exit
				#my $jn = 'manual';
				#$jn= 'scheduled' if ($isScheduledJob);
				my $jobTerminationPath = $currentDir.'/'.Constants->FILE_NAMES->{jobTerminationScript};
				system("perl \'$jobTerminationPath\' \'$jobType\' \'$userName\' 1>/dev/null 2>/dev/null");

				$exit_flag = "1-$errStr";
				unlink($pwdPath) if($errStr =~ /password mismatch|encryption verification failed/i);
				return 0;
			}
		}
	}

	chomp(@linesBackupErrorFile);
	for(my $i = 0; $i<= $#linesBackupErrorFile; $i++) {
		$linesBackupErrorFile[$i] =~ s/^\s+|\s+$//g;

		if($linesBackupErrorFile[$i] eq "" or $linesBackupErrorFile[$i] =~ m/$errorline/){
			next;
		}

		for(my $j=0; $j<=$#ErrorArgumentsRetry; $j++)
		{
			if($linesBackupErrorFile[$i] =~ m/$ErrorArgumentsRetry[$j]/){
				$retryAttempt = true;
				traceLog("Retry Reason : $ErrorArgumentsRetry[$j]. retryAttempt: $retryAttempt",__FILE__, __LINE__);
				last;
			}
		}
		if($retryAttempt){
			reduceRetryFileSizeInprogress();
			last;
		}
	}
	return 1;
}

#****************************************************************************************************************************
# Subroutine Name         : getFinalErrorFile
# Objective               : This subroutine creates a final ERROR file for each backupset, which has to be displayed in LOGS
# Modified By             : Pooja Havaldar
#****************************************************************************************************************************
sub getFinalErrorFile
{
	my $curFileset = shift;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	$cancel = 0;
	if($exit_flag == 0){
		if(!-e $pidPath){
			$cancel = 1;
		}
	}

	my $failedWithReason = 0;
	my ($errFinal,$errMsgFinal) = ("") x 2;
	my ($fileOpenFlag,$traceFileOpenFlag) = (1) x 2;
	my $individual_errorfile = "$currentErrorFile";

	if($failedfiles_count > 0){
		open ERROR_FINAL, ">", $individual_errorfile."_FINAL" or $fileOpenFlag = 0;
		if(!$fileOpenFlag){
			traceLog("\n Could not open file {$individual_errorfile}_FINAL: $! \n", __FILE__, __LINE__);
			return;
		}
		else{
			chmod $filePermission, $individual_errorfile."_FINAL";
			open BACKUP_RESTORE_ERROR, "<", $individual_errorfile or $fileOpenFlag = 0;
			if($fileOpenFlag){
				@individual_errorfileContents = <BACKUP_RESTORE_ERROR>;
				close BACKUP_RESTORE_ERROR;
			}
		}

		my $permissionError = $jobRunningDir."/ERROR/permissionError.txt";
		open TRACEPERMISSIONERRORFILE, ">>", $permissionError or $traceFileOpenFlag = 0;
		if(!$traceFileOpenFlag){
			traceLog("\n Could not open file $permissionError: $! \n", __FILE__, __LINE__);
			return;
		}
		else{
			chmod $filePermission, $permissionError;
		}

		chomp(@failedfiles_array);
		chomp(@individual_errorfileContents);
		my $j = 0;
		@failedfiles_array = sort @failedfiles_array;
		my $last_index = $#individual_errorfileContents;

		for($i = 0; $i <= $#failedfiles_array; $i++){
			$matched = 0;

			if($fileOpenFlag){
				#reset the initial and last limit for internal for loop for new item if required
				if($j > $last_index){
					$j = 0;
					$last_index = $#individual_errorfileContents;
				}

				#fill the last matched index for later use
				$index = $j;
				$failedfile = substr($failedfiles_array[$i],1);
				$failedfile = quotemeta($failedfile);

				#try to find a match between start and end point of error file
				for(;$j <= $last_index; $j++){

					if($individual_errorfileContents[$j] =~ /$failedfile/){
						chomp($individual_errorfileContents[$j]);
						$individual_errorfileContents[$j] =~ s/\s+\[$failedfile\]/\./;

						my $find = $failedfiles_array[$i];
						my $replace = '';
						substr($find, 0, 1, "") if "/" eq substr($find, 0, 1);

						$individual_errorfileContents[$j] =~ s/\Q$find\E/$replace/g;

						if($individual_errorfileContents[$j] =~ /Permission denied/i){
							print TRACEPERMISSIONERRORFILE "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : Permission denied".$lineFeed;
							$failedfiles_count--;
							$deniedFilesCount++;
						} elsif($individual_errorfileContents[$j] =~ /failed verification -- update retained/i){
							print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] failed verification -- update retained".$lineFeed;
						} elsif($individual_errorfileContents[$j] =~ /Directory not empty/i){
							print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : A directory name with the same file name already exists ".$lineFeed;
						} elsif($individual_errorfileContents[$j] =~ /Reason:/i){
							$missingCount++ if($individual_errorfileContents[$j] =~ /No such file or directory/);
							$individual_errorfileContents[$j] =~ s/IOERROR.*\),//g;
							print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] $individual_errorfileContents[$j]".$lineFeed;
						} else {
							print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : $individual_errorfileContents[$j]".$lineFeed;
							$missingCount++ if($individual_errorfileContents[$j] =~ /No such file or directory/);
						}
						$matched = 1;
						$failedWithReason++;

						#got a match so resetting the last index
						$last_index = $#individual_errorfileContents;
						$j++;
						last;
					}

					#if no match till last item and intial index is not zero try for remaining error file content
					if($j == $last_index && $index != 0){
						$j = -1;
						$last_index = $index-1;
						$index = $j;
					}
				}
			}

			if($matched == 0 and $exit_flag == 0 and $cancel == 0){#if restore location is not having proper permission then restore job will fail. Giving this error in the log file.Here failure reason is not present
				print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]]".$lineFeed;
			}
		}

		close ERROR_FINAL;
		close TRACEPERMISSIONERRORFILE;
	}

	if($exit_flag != 0 or $cancel != 0){
		$failedfiles_count = $failedWithReason;
	}
	unlink $individual_errorfile;
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
# Modified By             : Deepak Chaurasia
#*****************************************************************************************************/
sub RestoreOutputParse
{
	our ($outputFilePath,$curFileset,$relative,$silentFlag,$fileTransferCount,$operationEngineId) = @_;
    my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my ($prevSize,$cumulativeDataTransRate) = (0) x 2;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @PROGRESSFILE;

	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
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
			if(!-e $pidPath or -s $idevsErrorFile > 0){
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
				next if(scalar(keys %fileName) < 5);

				my $restoreFinishTime = localtime;
				my $keyString   = $pathSeparator.$fileName{'fname'};
				my $restoreType = $fileName{'trf_type'};
				$restoreType    =~ s/FILE IN//;
				$restoreType    =~ s/\s+//;
				my $pKeyString  = $keyString;
				my $kbps        = $fileName{'rate_trf'};
				my $fileSize    = $fileName{'size'};
				my $currentSize = $fileName{'size'};
				my $percentage	= $fileName{'per'};

				if($relative eq NORELATIVE) {
					my $indx = rindex ($pKeyString, '/');
					$pKeyString = substr($pKeyString, $indx);
				}

				if($tmpLine =~ m/$operationComplete/) {
					if($restoreType eq 'SYNC') { 		# check if file in sync
						if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize);
						}
						$fileSyncCount++;
					}
					elsif($restoreType eq 'FULL' or $restoreType eq 'INCREMENTAL') {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString}{'status'})) {
							if($fileSetHash{$keyString}{'status'} != 1){
								$fileSetHash{$keyString}{'status'} = 1;
								$fileSetHash{$keyString}{'detail'} = "[$restoreFinishTime] [$restoreType Restore]";
								$fileSetHash{$keyString}{'size'} = $fileSize;
								$fileRestoreCount++;
								$transferredFileSize += $fileSize;
							}
						} else {
							if(getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize) == 1){
								$fileRestoreCount++;
								$transferredFileSize += $fileSize;
							}
						}
					}
					else {
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}
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
				if($sizeInBytes>0) {
					$ctrf += $sizeInBytes;
					$cumulativeDataTransRate = ($ctrf/$fileTransferCount);
					$fileTransferCount++;
				}

			#	if($totalSize ne Constants->CONST->{'CalCulate'}){
				$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n"."$cumulativeDataTransRate"."\n".$pKeyString;
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " "x($prevLen-$newLen);
					$pKeyString = $pKeyString.$pSpace;
				}
				$PROGRESSFILE[0] = "$restoreType Restore";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$cumulativeDataTransRate";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";
				$prevLen = $newLen;
				#}
			}
			elsif($tmpLine =~ /$termData/ ) {
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
				$tmpLine !~ m/$termData/) {
					$errStr = $tmpLine;
					addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
				}
		}

		if($skipFlag){
			last;
		}
	}

	untie @PROGRESSFILE;
	writeTransferRateAndCount($ctrf,$fileTransferCount);
}
#****************************************************************************************************
# Subroutine Name         : RestoreDedupOutputParse.
# Objective               : This function parse the Dedup evs output file and creates the App
#							log file which is shown to user.
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub RestoreDedupOutputParse
{
	my ($outputFilePath,$curFileset,$silentFlag,$fileTransferCount,$operationEngineId) = @_;
    my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my ($prevSize,$cumulativeDataTransRate) = (0) x 2;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @PROGRESSFILE;

	tie @PROGRESSFILE, 'Tie::File', $progressDetailsFilePath;
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
			if(!-e $pidPath or -s $idevsErrorFile > 0){
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
				next if(scalar(keys %fileName) < 5);

				my $restoreFinishTime = localtime;
				my $fileSize = undef;
				#my $keyString = $pathSeparator.$fields[$fields_in_progress-2];
				my $keyString = $pathSeparator.$fileName{'fname'};
				replaceXMLcharacters(\$keyString);
				my $pKeyString = $keyString;

				my $restoreType = $fileName{'trf_type'};
				$restoreType =~ s/FILE IN//;
				$restoreType =~ s/\s+//;

				my $kbps 	    = $fileName{'rate_trf'};
				my $fileSize    = $fileName{'size'};
				my $currentSize = $fileName{'size'};
				my $percentage	= $fileName{'per'};

				if($relative eq NORELATIVE) {
					my $indx = rindex ($pKeyString, '/');
					$pKeyString = substr($pKeyString, $indx);
				}

				if($tmpLine =~ m/$operationComplete/) {
					if($restoreType eq 'SYNC') { 		# check if file in sync
						if(defined($fileSetHash{$keyString}{'status'})) {
							$fileSetHash{$keyString}{'status'} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize);
						}
						$fileSyncCount++;
					}
					elsif($restoreType eq 'FULL' or $restoreType eq 'INCREMENTAL') {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString}{'status'})) {
							if($fileSetHash{$keyString}{'status'} != 1){
								$fileSetHash{$keyString}{'status'} = 1;
								$fileSetHash{$keyString}{'detail'} = "[$restoreFinishTime] [$restoreType Restore]";
								$fileSetHash{$keyString}{'size'} = $fileSize;
								$fileRestoreCount++;
								$transferredFileSize += $fileSize;
							}
						}
						else {
							if(getFullPathofFile($keyString, $restoreFinishTime, $restoreType, $fileSize) == 1){
								$fileRestoreCount++;
								$transferredFileSize += $fileSize;
							}
						}
					}
					else {
						addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
					}
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
				if($sizeInBytes>0) {
					$ctrf += $sizeInBytes;
					$cumulativeDataTransRate = ($ctrf/$fileTransferCount);
					$fileTransferCount++;
				}

				$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n"."$cumulativeDataTransRate"."\n".$pKeyString;
				$newLen = length($progress);
				if($newLen < $prevLen) {
					$pSpace = " "x($prevLen-$newLen);
					$pKeyString = $pKeyString.$pSpace;
				}
				$PROGRESSFILE[0] = "$restoreType Restore";
				$PROGRESSFILE[1] = convertFileSize($fileSize);
				$PROGRESSFILE[2] = "$IncFileSizeByte";
				$PROGRESSFILE[3] = "$totalSize";
				$PROGRESSFILE[4] = "$cumulativeDataTransRate";
				$PROGRESSFILE[5] = "$pKeyString";
				$PROGRESSFILE[6] = "$currentSize";
				$PROGRESSFILE[7] = "$percentage";
				$prevLen = $newLen;
			}
			elsif($tmpLine =~ /$termData/ ) {
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
				$tmpLine !~ m/$termData/) {
					$errStr = $tmpLine;
					addtionalErrorInfo(\$currentErrorFile, \$tmpLine);
				}
		}

		if($skipFlag){
			last;
		}
	}

	untie @PROGRESSFILE;
	writeTransferRateAndCount($ctrf,$fileTransferCount);
}
#****************************************************************************************************
# Subroutine Name         : writeToCrontab.
# Objective               : Append an entry to crontab file.
# Modified By             : Dhritikana.
#*****************************************************************************************************/
sub writeToCrontab {
	my $cron = "/etc/crontab";
	if(!open CRON, ">", $cron) {
		exit 0;
	}
	print CRON @_;
	close(CRON);
	exit 0;
}
#****************************************************************************************************
# Subroutine Name         : readTransferRateAndCount.
# Objective               : Read Transfer Rate And Count of previous operation.
# Modified By             : Senthil Pandian.
#*****************************************************************************************************/
sub readTransferRateAndCount {
	my @lines = (0,1);
	if(-e $trfSizeAndCountFile and -s $trfSizeAndCountFile>0){
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
	if(open(OUTFILE, ">> $outputFilePath")){
		chmod $filePermission, $outputFilePath;
	}
	else {
		traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."outputFilePath: ".$outputFilePath." Reason:$!",__FILE__, __LINE__);
		print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$outputFilePath: ".$outputFilePath." Reason:$! $lineFeed";
		return 0;
	}

	$isLocked = 1	if(flock(OUTFILE, 2));

	my $pKeyString = '';
	foreach my $fileSetHashName (sort keys %fileSetHash) {
		$details = '';
		if($fileSetHash{$fileSetHashName}{'detail'} ne '' and $fileSetHash{$fileSetHashName}{'status'} == 1){
			$pKeyString = $fileSetHashName;
			if($relative eq NORELATIVE and $dedup ne 'on') {
				my $index = rindex ($pKeyString, '/');
				$pKeyString = substr($pKeyString, $index);
			}
			$details = "$fileSetHash{$fileSetHashName}{'detail'} [SUCCESS] [$pKeyString] [$fileSetHash{$fileSetHashName}{'size'}]";
			print OUTFILE $details.$lineFeed;
		}
	}

	if($isLocked){
		flock(OUTFILE, 8);
	}
	else{
		traceLog("Unable to lock LOG file", __FILE__, __LINE__);
	}
	close OUTFILE;
}

#****************************************************************************************************
# Subroutine Name         : getUpdateRetainedFilesList.
# Objective               : Change the status from success to failure if failed verification data exists.
# Modified By             : Vijay Vinoth.
#*****************************************************************************************************/
sub getUpdateRetainedFilesList {
	my $currentErrorFile = $_[0];

	open BACKUP_RESTORE_ERROR_DATA, "<", $currentErrorFile;
	my @individual_errorfileContentsDetails = <BACKUP_RESTORE_ERROR_DATA>;
	close BACKUP_RESTORE_ERROR_DATA;
	chomp(@individual_errorfileContentsDetails);

	my $j = 0;
	my $serverRoot = '';
	my $replace = '';

	$serverRoot = Helpers::getUserConfiguration('BACKUPLOCATION');
	$serverRoot = "/".Helpers::getUserConfiguration('SERVERROOT')	if($dedup eq 'on');

	for(;$j <= $#individual_errorfileContentsDetails; $j++){
		chomp($individual_errorfileContentsDetails[$j]);
		if($individual_errorfileContentsDetails[$j] =~ /failed verification -- update retained/i){
			if($dedup eq 'on'){
				$individual_errorfileContentsDetails[$j] =~ s/\Q$serverRoot\E/$replace/g;
				$individual_errorfileContentsDetails[$j] =~ s/\QERROR: \E/$replace/g;
				$individual_errorfileContentsDetails[$j] =~ s/\Q failed verification -- update retained.\E/$replace/g;
			}else{
				$individual_errorfileContentsDetails[$j] =~ s/\Q$serverRoot\E/$replace/g;
				$individual_errorfileContentsDetails[$j] =~ s/\QWARNING: \E/$replace/g;
				$individual_errorfileContentsDetails[$j] =~ s/\Qfailed verification -- update retained (will try again).\E/$replace/g;
			}

			Helpers::Chomp(\$individual_errorfileContentsDetails[$j]);
			$individual_errorfileContentsDetails[$j] =~ s/\/\//\//;
			if($fileSetHash{$individual_errorfileContentsDetails[$j]}{'status'} == 1){
				$fileBackupCount--;
				$fileSetHash{$individual_errorfileContentsDetails[$j]}{'status'} = 0;
				$updateRetainedFilesSize += $fileSetHash{$individual_errorfileContentsDetails[$j]}{'size'};
			} else {
				checkUpdateRetainedForRelative($individual_errorfileContentsDetails[$j]);
			}
		}
	}
}

#****************************************************************************************************
# Subroutine Name     : reduceUpdateRetainSizeInprogress.
# Objective           : Change the status from success to failure if failed verification data exists.
# Added By            : Vijay Vinoth
# Modified By         : Senthil Pandian
#*****************************************************************************************************/
sub reduceUpdateRetainSizeInprogress{
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @progressDetailsFileData;
	if(-e $progressDetailsFilePath and !-z $progressDetailsFilePath and $updateRetainedFilesSize > 0) {
		if (open my $fh, '+<', $progressDetailsFilePath) {
			@progressDetailsFileData = <$fh>;
			#print "progressDetailsFileData1 --- $progressDetailsFileData[2] \n";
			#print "updateRetainedFilesSize --- $updateRetainedFilesSize \n";
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
# Subroutine Name     : reduceRetryFileSizeInprogress.
# Objective           : Reduce the file size from progress when file is going to retry.
# Added By            : Senthil Pandian
#*****************************************************************************************************/
sub reduceRetryFileSizeInprogress{
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_".$operationEngineId;
	my @progressDetailsFileData;
	if(-e $progressDetailsFilePath and !-z $progressDetailsFilePath) {
		if (open my $fh, '+<', $progressDetailsFilePath) {
			@progressDetailsFileData = <$fh>;
			chomp($progressDetailsFileData[2]);
			chomp($progressDetailsFileData[6]);
			chomp($progressDetailsFileData[7]);
			if($progressDetailsFileData[7] ne '100%' and $progressDetailsFileData[6] > 0){
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
