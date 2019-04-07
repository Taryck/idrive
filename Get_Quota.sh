#!/bin/sh
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
#cd /Taryck/idrive
#echo $DIR
# Convert to cacti format with one line and : as seperator (<fieldname_1>:<value_1> <fieldname_2>:<value_2>)
#/Taryck/IDrive_/scripts/Get_Quota.pl $1  | tr '\n' ' ' | sed 's/\([[:alpha:]]*\)=\([[:digit:]]*\)/\1:\2/g'
$DIR/Get_Quota.pl $1  | tr '\n' ' ' | sed 's/\([[:alpha:]]*\)=\([[:digit:]]*\)/\1:\2/g'

