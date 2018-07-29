#!/bin/sh
#cd /Taryck/idrive
# Convert to cacti format with one line and : as seperator (<fieldname_1>:<value_1> <fieldname_2>:<value_2>)
/Taryck/idrive/Get_Quota.pl $1  | tr '\n' ' ' | sed 's/\([[:alpha:]]*\)=\([[:digit:]]*\)/\1:\2/g'
