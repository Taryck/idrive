#!/usr/bin/perl

###############################################################################
#Script Name : Operations.pl
###############################################################################

#my $userScriptLocation  = findUserLocation();
#unshift (@INC,$userScriptLocation);
unshift (@INC,substr(__FILE__, 0, rindex(__FILE__, '/')));
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
my $flagToCheckSchdule = 0;
my $failedfiles_index = 0;
my %fileSetHash = ();
my $fileBackupCount = 0;
my $fileRestoreCount = 0;
my $fileSyncCount = 0;
my $failedfiles_count = 0;
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

if(!$userName) {
	$userName = $ARGV[1];
}
$confFilePath = $usrProfilePath."/$userName/".Constants->CONST->{'configurationFile'};

# Reading the configurationFile  - Start
if(-e $confFilePath) {
	readConfigurationFile($confFilePath);
} 

getConfigHashValue();
loadUserData();
# Reading the configurationFile - End

my $curFile = basename(__FILE__);   
my $jobRunningDir = $ARGV[0];
my ($current_source)=('');
($progressSizeOp,$bwThrottle,$backupPathType) = ('') x 3;#These variables are initialized in operations subroutine after reading parameters from temp_file.
my $temp_file = "$jobRunningDir/operationsfile.txt";#This files contains value to the parameters which is used during backup, restore etc jobs. This file is written in Backup_Script.pl file and Restore_Script.pl file before call to operation file is done. In operation file various operation related to job is done.  
my $pidPath = "$jobRunningDir/pid.txt";
my $evsTempDirPath = "$evsTempDir/evs_temp";
$statusFilePath = "$jobRunningDir/STATUS_FILE";
my $retryinfo = "$jobRunningDir/".$retryinfo;
#my $progressDetailsFilePath = undef;
$idevsOutputFile = "$jobRunningDir/output.txt";
$idevsErrorFile = "$jobRunningDir/error.txt";
my $fileForSize = "$jobRunningDir/TotalSizeFile";
my $incSize = "$jobRunningDir/transferredFileSize.txt";
my $trfSizeAndCountFile = "$jobRunningDir/trfSizeAndCount.txt";

my $jobHeader = undef;
my $headerLen = undef;
my $pp = undef;

# Index number for statusFileArray
use constant COUNT_FILES_INDEX => 0;
use constant SYNC_COUNT_FILES_INDEX => 1;
use constant ERROR_COUNT_FILES => 2;
use constant FAILEDFILES_LISTIDX => 3;
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
$SIG{INT} = \&process_term;
$SIG{TERM} = \&process_term;
$SIG{TSTP} = \&process_term;
$SIG{QUIT} = \&process_term;
$SIG{PWR} = \&process_term;
$SIG{KILL} = \&process_term;
$SIG{USR1} = \&process_term;

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
	($current_source,$progressSizeOp,$bwThrottle,$backupPathType) = ($param[3],$param[5],$param[7],$param[9]);
	$flagToCheckSchdule = 1 if($jobRunningDir =~ /Scheduled/);
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
		$jobType = q(backup);
		$jobType = q(localBackup) if($operationName eq 'LOCAL_BACKUP_OPERATION');
		getCurrentFileSet($param[1]);
		our ($ctrf,$fileTransferCount) = readTransferRateAndCount();
		$backupHost = $param[6];
		getProgressDetais();
		if($dedup eq 'on'){			
			BackupDedupOutputParse($param[0],$param[1],$param[4],$param[8],$fileTransferCount);
		} else {
			BackupOutputParse($param[0],$param[1],$param[2],$param[4],$param[8],$fileTransferCount);
		}
		subErrorRoutine($param[1]);
		writeParameterValuesToStatusFile($fileBackupCount,$fileRestoreCount,$fileSyncCount,$failedfiles_count,$exit_flag,$failedfiles_index);	
	}
	elsif($operationName eq 'RESTORE_OPERATION'){
		$jobType = q(restore);
		getCurrentFileSet($param[1]);
		$restoreHost = $param[6];
        $restoreLocation = $param[7];
		our ($ctrf,$fileTransferCount) = readTransferRateAndCount();
		getProgressDetais();
		if($dedup eq 'on'){
				RestoreDedupOutputParse($param[0],$param[1],$param[4],$param[8],$fileTransferCount);
		} else {
				RestoreOutputParse($param[0],$param[1],$param[2],$param[4],$param[8],$fileTransferCount);
		}
		subErrorRoutine($param[1]);
		writeParameterValuesToStatusFile($fileBackupCount,$fileRestoreCount,$fileSyncCount,$failedfiles_count,$exit_flag,$failedfiles_index);

	}
	else{
		traceLog("\nfunction not in this file\n", __FILE__, __LINE__);
        return 0;
	}
	unlink $temp_file;
}
#****************************************************************************************************
#Subroutine Name        : readParamNcronEntryFromOperationsFile
#Objective              : This subroutine will read data from operations file into an array and return that array. Returned data is further used based on the type of operation name which is the first entry of the array.
#Usage                  : readParamNcronEntryFromOperationsFile() 
#Added By               : Abhishek Verma.
#****************************************************************************************************
sub readParamNcronEntryFromOperationsFile{
	if (-e $temp_file){
		if(!open(TEMP_FILE, "<",$temp_file)){
			$errStr = "Could not open file temp_file in Child process: $temp_file, Reason:$!";
			traceLog($errStr, __FILE__, __LINE__);
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
	open FILESET, "< $curFileset" or traceLog("Couldn't open file $curFileset $!.$lineFeed", __FILE__, __LINE__) and return;
        if($curFileset =~ /versionRestore/) {
                my $param = <FILESET>;
                my $idx = rindex($param, "_");
                $param = substr($param, 0, $idx);
                $fileSetHash{$param} = 0;
                push @currentFileset, $param;
#                $versionRes = 1;
        } else {
                while(<FILESET>) {
                        chomp($_);
                        $fileSetHash{$_} = 0;
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
        if(open(SIZE, "<", $incSize)) {
                $IncFileSizeByte = <SIZE>;
                chomp($IncFileSizeByte);
        } else {
                traceLog("Couldn't open $incSize, Reason: $!\n", __FILE__, __LINE__);
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
	my ($outputFilePath,$curFileset,$relative,$curLines,$silentFlag,$fileTransferCount) = @_;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my $prevSize = 0;
	my $currentSize = 0;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_BACKUP";	
	my $cumulativeDataTransRate = 0;

	if($operationName eq 'BACKUP_OPERATION'){
		$initialSlash = '/';
	} else {
		$initialSlash = '';
	}
	
	if(open(OUTFILE, ">> $outputFilePath")){
		chmod $filePermission, $outputFilePath;
	}
	else {
		$Oflag = 1;
		traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$outputFilePath: ".$outputFilePath." Reason:$! $lineFeed", __FILE__, __LINE__);
		print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$outputFilePath: ".$outputFilePath." Reason:$! $lineFeed";
		return 0;
	}

	if($flagToCheckSchdule and $fileOpenflag==0) {
		chmod $filePermission, $progressDetailsFilePath;
		if(!open(PROGRESSFILE, ">", $progressDetailsFilePath)) {
			traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath: ".$progressDetailsFilePath." Reason:$! $lineFeed", __FILE__, __LINE__);
			print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath ".$progressDetailsFilePath." Reason:$! $lineFeed";
		}
		$fileOpenflag = 1;
		chmod $filePermission, $progressDetailsFilePath;
	}

	while(!$fileNotOpened) {
		if(!-e $pidPath){
			last;
		}
		if(-e $idevsOutputFile) {
			chmod $filePermission, $idevsOutputFile;
			open TEMPOUTPUTFILE, "<", $idevsOutputFile and $fileNotOpened = 1;
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
		my $bufIndex = @resultList;
		
		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = $resultList[$#resultList];
			$bufIndex -= 1;
		}
		else {
			$lastLine = "";
		}
		
		for(my $cnt = 0; $cnt < $bufIndex; $cnt++) {
			my $tmpLine = $resultList[$cnt];
			my @fields = split("\\] \\[",$tmpLine, $fields_in_progress);
			my $total_fields = @fields;

			if($total_fields >= $fields_in_progress) {
				$fields[0] =~ s/^.//; # remove starting character [ from first field
				$fields[$fields_in_progress-1] =~ s/.$//; # remove last character ] from last field
				
				# remove spaces from beginning from required fields
				$fields[0] =~ s/^\s+//;
				$fields[0] =~ s/[\D]+//g;
				$fields[1] =~ s/[\D]+//g;
				$fields[$fields_in_progress-2] =~ s/^\s+//;
				
				my $keyString = "$initialSlash$fields[$fields_in_progress-1]";
				my $fileSize = convertFileSize($fields[1]);
				my $fileBackupType = $fields[$fields_in_progress-2]; 
				$backupType = $fileBackupType;
				$backupType =~ s/FILE IN//;
				$backupType =~ s/\s+//;
				
				my $backupFinishTime = localtime;
				my $pKeyString = $keyString;
				
				if(($relative eq NORELATIVE) and ($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL")) {
					my $indx = rindex ($pKeyString, '/');
					$pKeyString = substr($pKeyString, $indx);
				}
					
				if($tmpLine =~ m/$operationComplete/) { 
					if($fileBackupType eq "FILE IN SYNC") { 		# check if file in sync
						$fileSyncCount++;
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}	
					}
					elsif($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL") {  	# check if file is backing up as full or incremental
						$fileBackupCount++;
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}
						print OUTFILE "[$backupFinishTime] [$backupType Backup] [SUCCESS] [$pKeyString][$fileSize]".$lineFeed;
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

				$currentSize = $fields[0];				
				
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
				my $sizeInBytes = convertToBytes($fields[$fields_in_progress-4]);
				if($sizeInBytes>0) {
					$ctrf += $sizeInBytes;
					$cumulativeDataTransRate = ($ctrf/$fileTransferCount);
					$fileTransferCount++;					
				}
				
				if($totalSize ne Constants->CONST->{'CalCulate'}){
					my $dataTransRate = convertFileSize($cumulativeDataTransRate);
					if($flagToCheckSchdule && $fileOpenflag) {
						$progress = "$backupType Backup"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n".$dataTransRate."\n".$pKeyString;
						$newLen = length($progress);
						if($newLen < $prevLen) {
							$pSpace = " "x($prevLen-$newLen);
							$progress = $progress.$pSpace;
						}
						seek(PROGRESSFILE, 0, 0);
						print PROGRESSFILE $progress;
						$prevLen = $newLen; 
					} elsif(!$flagToCheckSchdule and !$silentFlag) {
						displayProgressBar("$backupType Backup", $fileSize, $IncFileSizeByte, $totalSize,$dataTransRate, $pKeyString, $curLines);
					}
				}
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
	
	if(!$Oflag) {
		close OUTFILE;
	}
	
	if($fileOpenflag) {
		close PROGRESSFILE;
	}
	
	writeTransferRateAndCount($ctrf,$fileTransferCount);
	if(open(SIZE, ">", $incSize)) {
		print SIZE $IncFileSizeByte;
		close SIZE;
		chmod $filePermission, $incSize;
	} else {
		traceLog(Constants->CONST->{'FileOpnErr'}." $incSize, Reason: $!\n", __FILE__, __LINE__);
	}
}

#****************************************************************************************************
# Subroutine Name         : BackupDedupOutputParse.
# Objective               : This function parse the Dedup evs output file and creates the App 
#							log file which is shown to user. 					
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub BackupDedupOutputParse
{
	my ($outputFilePath,$curFileset,$curLines,$silentFlag,$fileTransferCount) = @_;
	my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 21;
	my $prevSize = 0;
	my $currentSize = 0;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_BACKUP";	
	my $cumulativeDataTransRate = 0;
	
	if($operationName eq 'BACKUP_OPERATION'){
		$syncFieldsInProgress = 21;
		$syncBkpTypePos  = 4;
		$syncTrfPos   = 8;
		$syncFNamePos = 2;
		
		$fullFieldsInProgress = 23;
		$fullBkpTypePos  = 6;
		$fullTrfPos   = 10;
		$fullFNamePos = 2;
		
		$initialSlash = '/';
	} else {
		$syncFieldsInProgress = 27;
		$syncBkpTypePos  = 10;
		$syncTrfPos   = 14;
		$syncFNamePos = 2;
		
		$fullFieldsInProgress = 31;
		$fullBkpTypePos  = 14;
		$fullTrfPos   = 18;
		$fullFNamePos = 2;
		
		$initialSlash = '';
	}
	
	if(open(OUTFILE, ">> $outputFilePath")){
		chmod $filePermission, $outputFilePath;
	}
	else {
		$Oflag = 1;
		traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$outputFilePath: ".$outputFilePath." Reason:$! $lineFeed", __FILE__, __LINE__);
		print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$outputFilePath: ".$outputFilePath." Reason:$! $lineFeed";
		return 0;
	}

	if($flagToCheckSchdule and $fileOpenflag==0) {
		chmod $filePermission, $progressDetailsFilePath;
		if(!open(PROGRESSFILE, ">", $progressDetailsFilePath)) {
			traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath: ".$progressDetailsFilePath." Reason:$! $lineFeed", __FILE__, __LINE__);
			print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath ".$progressDetailsFilePath." Reason:$! $lineFeed";
		}
		$fileOpenflag = 1;
		chmod $filePermission, $progressDetailsFilePath;
	}

	while(!$fileNotOpened) {
		if(!-e $pidPath){
			last;
		}
		if(-e $idevsOutputFile) {
			chmod $filePermission, $idevsOutputFile;
			open TEMPOUTPUTFILE, "<", $idevsOutputFile and $fileNotOpened = 1;
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
		my $bufIndex = @resultList;
		
		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = $resultList[$#resultList];
			$bufIndex -= 1;
		}
		else {
			$lastLine = "";
		}
		
		for(my $cnt = 0; $cnt < $bufIndex; $cnt++) {
			my $tmpLine = $resultList[$cnt];
			if($tmpLine =~ /FILE IN SYNC/) {
				$fields_in_progress = $syncFieldsInProgress;
				$typePos  = $syncBkpTypePos;
				$trfPos   = $syncTrfPos;
				$fNamePos = $syncFNamePos;
			} elsif($tmpLine =~ /FULL/ or $tmpLine =~ /INCREMENTAL/) {
				$fields_in_progress = $fullFieldsInProgress;
				$typePos  = $fullBkpTypePos;
				$trfPos   = $fullTrfPos;
				$fNamePos = $fullFNamePos;
			}
			
			my @fields = split("\"",$tmpLine,$fields_in_progress);
			my $total_fields = @fields;
			if($total_fields >= $fields_in_progress) {
				my $keyString = $initialSlash.$fields[($fields_in_progress-$fNamePos)];
				my $fileSize = convertFileSize($fields[3]);
				$backupType = $fields[($fields_in_progress-$typePos)];
				$backupType =~ s/FILE IN//;
				$backupType =~ s/\s+//;
				
				my $backupFinishTime = localtime;
				replaceXMLcharacters(\$keyString);
				my $pKeyString = $keyString;
				
				if($tmpLine =~ m/$operationComplete/) { 
					my $fileBackupType = $fields[($fields_in_progress-$typePos)]; 

					if($fileBackupType eq "FILE IN SYNC") { 		# check if file in sync
						$fileSyncCount++;
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}	
					}
					elsif($fileBackupType eq "FULL" or $fileBackupType eq "INCREMENTAL") {  	# check if file is backing up as full or incremental
						$fileBackupCount++;
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}
						print OUTFILE "[$backupFinishTime] [$backupType Backup] [SUCCESS] [$pKeyString][$fileSize]".$lineFeed;
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

				$currentSize = $fields[1];				
				if($prevFile eq $keyString) {
					if (($currentSize > $prevSize && $prevSize ne 0) or ($prevSize eq 0)) {
						$IncFileSizeByte = $IncFileSizeByte + $currentSize - $prevSize;
					} 
				} elsif($prevFile ne $keyString) {
					$IncFileSizeByte = $IncFileSizeByte + $currentSize;
				} 
				$prevSize = $currentSize;
				my $trfRate = $fields[($fields_in_progress-$trfPos)];
				$prevLine = $tmpLine;
				$prevFile = $keyString;
				$backupType = ucfirst(lc($backupType));
				my $sizeInBytes = convertToBytes($trfRate);
				if($sizeInBytes>0) {
					$ctrf += $sizeInBytes;
					$cumulativeDataTransRate = ($ctrf/$fileTransferCount);
					$fileTransferCount++;					
				}
				
				if($totalSize ne Constants->CONST->{'CalCulate'}){
					my $dataTransRate = convertFileSize($cumulativeDataTransRate);
					if($flagToCheckSchdule && $fileOpenflag) {
					#	$progress = "$backupType Backup"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n".$fields[($fields_in_progress-$trfPos)]."\n".$pKeyString;
						$progress = "$backupType Backup"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n".$dataTransRate."\n".$pKeyString;
						$newLen = length($progress);
						if($newLen < $prevLen) {
							$pSpace = " "x($prevLen-$newLen);
							$progress = $progress.$pSpace;
						}
						seek(PROGRESSFILE, 0, 0);
						print PROGRESSFILE $progress;
						$prevLen = $newLen; 
					} elsif(!$flagToCheckSchdule and !$silentFlag) {
#						displayProgressBar("$backupType Backup", $fileSize, $IncFileSizeByte, $totalSize, $fields[($fields_in_progress-$trfPos)], $pKeyString, $curLines);
						displayProgressBar("$backupType Backup", $fileSize, $IncFileSizeByte, $totalSize, $dataTransRate, $pKeyString, $curLines);
					}
				}
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
	
	if(!$Oflag) {
		close OUTFILE;
	}
	
	if($fileOpenflag) {
		close PROGRESSFILE;
	}
	
	writeTransferRateAndCount($ctrf,$fileTransferCount);
	if(open(SIZE, ">", $incSize)) {
		print SIZE $IncFileSizeByte;
		close SIZE;
		chmod $filePermission, $incSize;
	} else {
		traceLog(Constants->CONST->{'FileOpnErr'}." $incSize, Reason: $!\n", __FILE__, __LINE__);
	}
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
	$failedfiles_count = getFailedFileCount();
	my $individual_errorfile = "$currentErrorFile";
	copyTempErrorFile($individual_errorfile);
	#Check if retry is required
	$failedfiles_index = getParameterValueFromStatusFile('FAILEDFILES_LISTIDX');
	
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
		$failedfiles = $jobRunningDir."/".$failedFileName.$failedfiles_index; 
		my $oldfile_error = $currentErrorFile;
		my $newfile_error = $jobRunningDir."/ERROR/$failedFileName.$failedfiles_index"."_ERROR";
		
		if(-e $oldfile_error or -e $currentErrorFile."_FINAL") {
			rename $oldfile_error, $newfile_error;
		}
		if(!open(FAILEDLIST, "> $failedfiles")) {
			traceLog("Could not open file failedfiles in SubErrorRoutine: $failedfiles, Reason:$!".$lineFeed, __FILE__, __LINE__);
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
			print RETRYINFO "$current_source $relative $failedfiles\n";
			close RETRYINFO;
			chmod $filePermission, $retryinfo;
		}
	}

	updateFailedFileCount($curFileset);
}
#**********************************************************************************************************
# Subrotine Name         : getFailedFileCount
# Objective               : This subroutine gets the failed files count from the failedfiles array  
# Modified By             : Pooja Havaldar
#**********************************************************************************************************
sub getFailedFileCount
{
	my $failed_count = 0;
	for(my $i = 0; $i <= $#currentFileset; $i++){
		chomp $currentFileset[$i];
		if($fileSetHash{$currentFileset[$i]} == 0){
			$failedfiles_array[$failed_count] = $currentFileset[$i];
			$failed_count++;
		}
	}
	return $failed_count;
}

#****************************************************************************************************
# Subroutine Name         : getFullPathofFile.
# Objective               :         
# Added By				  : Pooja Havaldar
#*****************************************************************************************************
sub getFullPathofFile
{
	$fileToCheck = $_[0];
	for(my $i = $#currentFileset ; $i >= 0; $i--){
		$a = rindex ($currentFileset[$i], '/');
		$match = substr($currentFileset[$i],$a);
		
		if($fileToCheck eq $match){
			$fileSetHash{$currentFileset[$i]} = 1;
			last;
		}
	}
}
#****************************************************************************************************************************
# Subroutine Name         : updateFailedFileCount
# Objective               : This subroutine gets the updated failed files count incase retry backup is in process  
# Modified By             : Pooja Havaldar
#******************************************************************************************************************************/
sub updateFailedFileCount
{
	my $curFileset = shift;
	$orig_count = getParameterValueFromStatusFile('ERROR_COUNT_FILES');
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
		traceLog("Could not open file individual_errorfile in checkretryAttempt: $individual_errorfile, Reason:$! $lineFeed", __FILE__, __LINE__);
		return 0;
	}
	
	@linesBackupErrorFile = <TEMPERRORFILE>;
	close TEMPERRORFILE;
	traceLog(@linesBackupErrorFile, __FILE__, __LINE__);
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
				} else {
					$errStr = "Operation could not be completed. Reason : $ErrorArgumentsExit[$j].";
				}
				traceLog($errStr, __FILE__, __LINE__);
				#kill evs and then exit
				my $jn = 'manual';
				$jn= 'scheduled' if ($flagToCheckSchdule);
				my $jobTerminationPath = $currentDir.'/'.Constants->FILE_NAMES->{jobTerminationScript}; 
				system("perl \'$jobTerminationPath\' \'$jn\_$jobType\' \'$userName\' 1>/dev/null 2>/dev/null");

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
				traceLog("\nRetry Reason : $ErrorArgumentsRetry[$j]. retryAttempt:  $retryAttempt".$lineFeed, __FILE__, __LINE__);
				last;
			}
		}	
		if($retryAttempt){
			last;
		}
	}
	return 1;
}


#****************************************************************************************************************************
# Subroutine Name         : getFinalErrorFile
# Objective               : This subroutine creates a final ERROR file for each backupset, which has to be displayed in LOGS  
# Modified By             : Pooja Havaldar
#******************************************************************************************************************************/
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
	my $errFinal = "";
	my $errMsgFinal = "";
	my $fileOpenFlag = 1;
	my $individual_errorfile = "$currentErrorFile";
	
	if($failedfiles_count > 0){
		open ERROR_FINAL, ">", $individual_errorfile."_FINAL" or $fileOpenFlag = 0;
		if(!$fileOpenFlag){
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
						print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]] Reason : $individual_errorfileContents[$j]".$lineFeed;
						$matched = 1;
						$failedWithReason++;	
							
						#got a match so resetting the last index 
						$last_index = $#individual_errorfileContents;
						$j++;
						last;
					}
				
					#if no match till last item and intial index is not zero try for remaining error file content
					if($j == $last_index && $index != 0){
						$j = 0;
						$last_index = $index;
						$index = $j;
					}
				}
			}
			
			if($matched == 0 and $exit_flag == 0 and $cancel == 0){#if restore location is not having proper permission then restore job will fail. Giving this error in the log file.Here failure reason is not present
				print ERROR_FINAL "[".(localtime)."] [FAILED] [$failedfiles_array[$i]]".$lineFeed;
			}
		}
		
		close ERROR_FINAL;
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
sub process_term
{
	#traceLog("$lineFeed Inside process_term--------------------- $lineFeed", __FILE__, __LINE__);
	writeParameterValuesToStatusFile($fileBackupCount,$fileRestoreCount,$fileSyncCount,$failedfiles_count,$exit_flag,$failedfiles_index);
	exit 0;
}
#****************************************************************************************************
# Subroutine Name         : RestoreOutputParse.
# Objective               : This function monitors and parse the evs output file and creates the App 
#							log file which is shown to user. 					
# Modified By             : Deepak Chaurasia
#*****************************************************************************************************/
sub RestoreOutputParse
{
	my ($outputFilePath,$curFileset,$relative,$curLines,$silentFlag,$fileTransferCount) = @_;
        my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my $prevSize = 0;
	my $currentSize = 0;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_RESTORE";	
	my $cumulativeDataTransRate = 0;
	
	if(open(OUTFILE, ">> $outputFilePath")) {
		chmod $filePermission, $outputFilePath;  
		autoflush OUTFILE;
	}
	else {
		$Oflag = 1;
		traceLog(Constants->CONST->{'FileOpnErr'}."\$outputFilePath : $outputFilePath, Reason:$! $lineFeed", __FILE__, __LINE__);
		return;
	}
	
	if($flagToCheckSchdule and $fileOpenflag==0) {
		chmod $filePermission, $progressDetailsFilePath;
		if(!open(PROGRESSFILE, ">", $progressDetailsFilePath)) {
			traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath: $progressDetailsFilePath Reason:$! $lineFeed", __FILE__, __LINE__);
			print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath: ".$progressDetailsFilePath." Reason:$! $lineFeed";
		}
		$fileOpenflag = 1;
		chmod $filePermission, $progressDetailsFilePath;
	}
	while (!$fileNotOpened) {
		if(!-e $pidPath){
			last;
                }

		if(-e $idevsOutputFile) {
			open TEMPOUTPUTFILE, "<", $idevsOutputFile and $fileNotOpened = 1;
			chmod $filePermission, $idevsOutputFile;
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
		my $bufIndex = @resultList;
		
		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = $resultList[$#resultList];
			$bufIndex -= 1;
		}
		else {
			$lastLine = "";
		}
		for(my $cnt = 0; $cnt < $bufIndex; $cnt++) {
			my $tmpLine = $resultList[$cnt];
			if($tmpLine =~ /FILE IN SYNC/) {
				$fields_in_progress = 7;
			} elsif($tmpLine =~ /FULL/ or $tmpLine =~ /INCREMENTAL/) {
				$fields_in_progress = 10;
			}
			
			my @fields = split("\\] \\[",$tmpLine,$fields_in_progress);
			my $total_fields = @fields;
			if($total_fields >= $fields_in_progress) {
				$fields[0] =~ s/^.//; # remove starting character [ from first field
				
				$fields[$fields_in_progress-1] =~ s/.$//; # remove last character ] from last field
				
				# remove spaces from beginning from required fields
				$fields[0] =~ s/^\s+//;
				$fields[0] =~ s/[\D]+//g;
				$fields[1] =~ s/[\D]+//g;
				
				my $restoreFinishTime = localtime;
				my $fileSize = undef;
				my $keyString = $pathSeparator.$fields[$fields_in_progress-1];
				$restoreType = $fields[$fields_in_progress-2];
				$restoreType =~ s/FILE IN//;
				$restoreType =~ s/\s+//;
				my $pKeyString = $keyString;
				if($tmpLine =~ /FILE IN SYNC/) { 		# check if file in sync
					$perCent = $fields[$fields_in_progress-4];
					$kbps = $fields[$fields_in_progress-3];
					$fileSize = convertFileSize($fields[0]);
					if($relative eq NORELATIVE) {
						my $indx = rindex ($pKeyString, '/');
						$pKeyString = substr($pKeyString, $indx);
					}
				}
				elsif($tmpLine =~ /FULL/ or $tmpLine =~ /INCREMENTAL/) {  	# check if file is backing up as full or incremental
					$perCent = $fields[$fields_in_progress-5];
					$kbps = $fields[$fields_in_progress-4];
					$fileSize = convertFileSize($fields[1]);
					$pKeyString = $keyString;
				}

				if($tmpLine =~ m/$operationComplete/) {
					if($tmpLine =~ /FILE IN SYNC/) { 		# check if file in sync
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}
						$fileSyncCount++;
					}
					elsif($tmpLine =~ /FULL/ or $tmpLine =~ /INCREMENTAL/) {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}
						
						$fileRestoreCount++;
						print OUTFILE "[$restoreFinishTime] [$restoreType Restore] [SUCCESS] [$pKeyString] [$fileSize]",$lineFeed;
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
				$fields[0] =~ s/^\s+|\s+$//;
				$currentSize = $fields[0];
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
				
				if($totalSize ne Constants->CONST->{'CalCulate'}){
					my $dataTransRate = convertFileSize($cumulativeDataTransRate);
					if($flagToCheckSchdule && $fileOpenflag) {
					#	$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n"."$kbps"."\n".$pKeyString;
						$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n"."$dataTransRate"."\n".$pKeyString;
						$newLen = length($progress);
						if($newLen < $prevLen) {
							$pSpace = " "x($prevLen-$newLen);
							$progress = $progress.$pSpace;
						}
						seek(PROGRESSFILE, 0, 0);
						print PROGRESSFILE $progress;
						$prevLen = $newLen;
					} elsif(!$flagToCheckSchdule and !$silentFlag) {
					#	displayProgressBar("$restoreType Restore", $fileSize, $IncFileSizeByte, $totalSize, "$kbps", $pKeyString, $curLines);
						displayProgressBar("$restoreType Restore", $fileSize, $IncFileSizeByte, $totalSize, "$dataTransRate", $pKeyString, $curLines);
					}
				}
			}
			elsif($tmpLine =~ /$termData/ ) {
				close TEMPOUTPUTFILE;				
				unlink($idevsOutputFile);
				$skipFlag = 1;
			}
			elsif($tmpLine ne '' and 
			$tmpLine !~ m/building file list/ and 
			$tmpLine !~ m/=============/ and 
			$tmpLine !~ m/connection established/ and 
			$tmpLine !~ m/bytes  received/ and 
			$tmpLine !~ m/receiving file list/ and 
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
	
	if(!$Oflag) {
		close OUTFILE;
	}
	
	if($fileOpenflag) {
		close PROGRESSFILE;
	}
	
	writeTransferRateAndCount($ctrf,$fileTransferCount);
	if(open(SIZE, ">", $incSize)) {
		print SIZE $IncFileSizeByte;
		close SIZE;
		chmod $filePermission, $incSize;
	} else {
		traceLog(Constants->CONST->{'FileOpnErr'}." $incSize, Reason: $!\n", __FILE__, __LINE__);
	}
}
#****************************************************************************************************
# Subroutine Name         : RestoreDedupOutputParse.
# Objective               : This function parse the Dedup evs output file and creates the App 
#							log file which is shown to user. 					
# Modified By             : Senthil Pandian
#*****************************************************************************************************/
sub RestoreDedupOutputParse
{
	my ($outputFilePath,$curFileset,$curLines,$silentFlag,$fileTransferCount) = @_;
        my $currentErrorFile = getCurrentErrorFile($curFileset);
	my $fields_in_progress = 10;
	my $prevSize = 0;
	my $currentSize = 0;
	my $progressDetailsFilePath = "$jobRunningDir/PROGRESS_DETAILS_RESTORE";
	my $cumulativeDataTransRate = 0;
	
	if(open(OUTFILE, ">> $outputFilePath")) {
		chmod $filePermission, $outputFilePath;  
		autoflush OUTFILE;
	}
	else {
		$Oflag = 1;
		traceLog(Constants->CONST->{'FileOpnErr'}."\$outputFilePath : $outputFilePath, Reason:$! $lineFeed", __FILE__, __LINE__);
		return;
	}
	
	if($flagToCheckSchdule and $fileOpenflag==0) {
		chmod $filePermission, $progressDetailsFilePath;
		if(!open(PROGRESSFILE, ">", $progressDetailsFilePath)) {
			traceLog(Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath: $progressDetailsFilePath Reason:$! $lineFeed", __FILE__, __LINE__);
			print Constants->CONST->{'FileOpnErr'}.$whiteSpace."\$progressDetailsFilePath: ".$progressDetailsFilePath." Reason:$! $lineFeed";
		}
		$fileOpenflag = 1;
		chmod $filePermission, $progressDetailsFilePath;
	}
	while (!$fileNotOpened) {
		if(!-e $pidPath){
			last;
        }

		if(-e $idevsOutputFile) {
			open TEMPOUTPUTFILE, "<", $idevsOutputFile and $fileNotOpened = 1;
			chmod $filePermission, $idevsOutputFile;
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
		my $bufIndex = @resultList;
		
		if($buffer !~ /\n$/) {      #keep last line of buffer only when it not ends with newline.
			$lastLine = $resultList[$#resultList];
			$bufIndex -= 1;
		}
		else {
			$lastLine = "";
		}
		for(my $cnt = 0; $cnt < $bufIndex; $cnt++) {
			my $tmpLine = $resultList[$cnt];
			if($tmpLine =~ /FILE IN SYNC/) {
				$fields_in_progress = 15;
			} elsif($tmpLine =~ /FULL/ or $tmpLine =~ /INCREMENTAL/) {
				$fields_in_progress = 21;
			}
			
			my @fields = split("\"",$tmpLine,$fields_in_progress);
			my $total_fields = @fields;
		
			if($total_fields >= $fields_in_progress) {
				my $restoreFinishTime = localtime;
				my $fileSize = undef;
				my $keyString = $pathSeparator.$fields[$fields_in_progress-2];
				replaceXMLcharacters(\$keyString);
				$restoreType = $fields[$fields_in_progress-4];
				$restoreType =~ s/FILE IN//;
				$restoreType =~ s/\s+//;
				my $pKeyString = $keyString;
				if($tmpLine =~ /FILE IN SYNC/) { 		# check if file in sync
					$perCent = $fields[$fields_in_progress-8];
					$kbps = $fields[$fields_in_progress-6];
					$fileSize = convertFileSize($fields[3]);
					if($relative eq NORELATIVE) {
						my $indx = rindex ($pKeyString, '/');
						$pKeyString = substr($pKeyString, $indx);
					}
				}
				elsif($tmpLine =~ /FULL/ or $tmpLine =~ /INCREMENTAL/) {  	# check if file is backing up as full or incremental
					$perCent = $fields[$fields_in_progress-10];
					$kbps = $fields[$fields_in_progress-8];
					$fileSize = convertFileSize($fields[3]);
					$pKeyString = $keyString;
				}
				
				if($tmpLine =~ m/$operationComplete/) {
					if($tmpLine =~ /FILE IN SYNC/) { 		# check if file in sync
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}
						$fileSyncCount++;
					}
					elsif($tmpLine =~ /FULL/ or $tmpLine =~ /INCREMENTAL/) {  	# check if file is backing up as full or incremental
						if(defined($fileSetHash{$keyString})) {
							$fileSetHash{$keyString} = 1;
						} else {
							$fullPath = getFullPathofFile($keyString);
						}

						$fileRestoreCount++;
						print OUTFILE "[$restoreFinishTime] [$restoreType Restore] [SUCCESS] [$pKeyString] [$fileSize]",$lineFeed;
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
				$fields[1] =~ s/^\s+|\s+$//;
				$currentSize = $fields[1];
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
				
				if($totalSize ne Constants->CONST->{'CalCulate'}){
					my $dataTransRate = convertFileSize($cumulativeDataTransRate);
					if($flagToCheckSchdule && $fileOpenflag) {
				#		$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n"."$kbps"."\n".$pKeyString;
						$progress = "$restoreType Restore"."\n".$fileSize."\n".$IncFileSizeByte."\n".$totalSize."\n"."$dataTransRate"."\n".$pKeyString;
						$newLen = length($progress);
						if($newLen < $prevLen) {
							$pSpace = " "x($prevLen-$newLen);
							$progress = $progress.$pSpace;
						}
						seek(PROGRESSFILE, 0, 0);
						print PROGRESSFILE $progress;
						$prevLen = $newLen;
					} elsif(!$flagToCheckSchdule and !$silentFlag) {	
				#		displayProgressBar("$restoreType Restore", $fileSize, $IncFileSizeByte, $totalSize, "$kbps", $pKeyString, $curLines);
						displayProgressBar("$restoreType Restore", $fileSize, $IncFileSizeByte, $totalSize, "$dataTransRate", $pKeyString, $curLines);
					}
				}
			}
			elsif($tmpLine =~ /$termData/ ) {
				close TEMPOUTPUTFILE;				
				unlink($idevsOutputFile);
				$skipFlag = 1;
			}
			elsif($tmpLine ne '' and 
				$tmpLine !~ m/building file list/ and 
				$tmpLine !~ m/=============/ and 
				$tmpLine !~ m/connection established/ and 
				$tmpLine !~ m/bytes  received/ and 
				$tmpLine !~ m/receiving file list/ and 
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
	
	if(!$Oflag) {
		close OUTFILE;
	}
	
	if($fileOpenflag) {
		close PROGRESSFILE;
	}
	
	writeTransferRateAndCount($ctrf,$fileTransferCount);
	if(open(SIZE, ">", $incSize)) {
		print SIZE $IncFileSizeByte;
		close SIZE;
		chmod $filePermission, $incSize;
	} else {
		traceLog(Constants->CONST->{'FileOpnErr'}." $incSize, Reason: $!\n", __FILE__, __LINE__);
	}
}
#****************************************************************************************************
# Subroutine Name         : writeToCrontab.
# Objective               : Append an entry to crontab file.				
# Modified By             : Dhritikana.
#*****************************************************************************************************/
sub writeToCrontab {
	my $cron = "/etc/crontab";
	if(!open CRON, ">", $cron) {
		exit 1;
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