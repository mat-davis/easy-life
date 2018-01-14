#!/bin/bash
# --------------------
# This script will parse a Cisco ASA log file and output top 10 talkers & listeners
#
# Author: Matthew Davis (w132226)
# Date: 17/12/2013
# --------------------
#  use zcat to open files
#  extended grep for TCP/UDP teardown log entries
#  use sed to edit the ' ' to commas, chop everything before %ASA then
#  cut the 7th (src) or 9th (dst) & 13th (bytes tx) field
#  cut field 2 to keep 'src IP addr:port'
#  for each unique 'src IP addr:port', add up the bytes transferred
#  inverse numerical sort by the second field (bytes tx)
#  output the first  10 lines to screen
# --------------------

echo
echo --------------
echo Top 10 Talkers
echo --------------
echo

zcat $* | \
 egrep "%ASA-6-30201[46]" | \
 sed -n 's/.*\(%ASA.*\)/\1/ ; s/ /,/gp' | \
 cut -d "," -f 7,13 | \
 cut -d ":" -f 2 | \
 awk -F, '{a[$1]+=$2;}END{for(i in a)print i", "a[i];}' | \
 sort -t, -k2 -r -n | \
 head -n 10

echo
echo ----------------
echo Top 10 Listeners
echo ----------------
echo

zcat $* | \
 egrep "%ASA-6-30201[46]" | \
 sed -n 's/.*\(%ASA.*\)/\1/ ; s/ /,/gp' | \
 cut -d "," -f 9,13 | \
 cut -d ":" -f 2 | \
 awk -F, '{a[$1]+=$2;}END{for(i in a)print i", "a[i];}' | \
 sort -t, -k2 -r -n | \
 head -n 10