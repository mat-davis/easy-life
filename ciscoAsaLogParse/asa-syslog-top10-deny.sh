#!/bin/bash
# --------------------
# Synopsis: This script will parse a Cisco ASA log file for the top 10 Denies
# Author: Matthew Davis (w132226)
# Date: 16/09/2015
# --------------------

# select the log file to parse
if [ X"$1" != X ]; then
 logfile=$1;
 else echo Please enter the log file name to parse
 read logfile
fi

echo
echo --------------
echo Top 10 Denied
echo --------------
echo

# unzip the logfile
#  extended grep for TCP DENY log entries
#  set field separator to be space and keep the 10th (src) & 12th (dst) field
#  set field separator to be colon to keep 'src IP addr'
#  for each unique 'src IP addr:port', add up the bytes transferred
#  edit the space to a comma, just needed to perform the next awk cmd
#  inverse numerical sort by the second field (bytes tx)
#  output the first  10 lines to screen

gunzip -c ./$logfile | \
 egrep "%ASA-4-106023" | \
 cut -d " " -f 10,12 | \
#cut -d ":" -f 2 | \
#cut -d "/" -f 1 | \
#sed 's/ /,/g' | \
#awk -F, '{a[$1]+=$2;}END{for(i in a)print i", "a[i];}' | \
 sort -t, -k2 -r -n | \
#head -n 10
 > srcdst.txt 