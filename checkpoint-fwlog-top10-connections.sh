#!/bin/bash
# --------------------
# This script will parse a Checkpoint fwlog file and display uniq top 10 flows by number of connections
#
# Author: Matthew Davis (w132226)
# Date: 11/01/2018
# --------------------
#  use zcat to open files
#  AWK to parse for 'accept' TCP/UDP connections then print src($17);dst($18);proto($19);service($20)
#  sort and uniq
#  output the first 10 lines to screen
# --------------------

echo
echo ---------------------
echo Top 10 by connections
echo ---------------------
echo

zcat $* | \
awk -F ";" '/accept/ {if ($19 ~ /^tcp$/ || $19 ~ /^udp$/) printf "%-16s %-16s %-8s %-5s\n" ,$17,$18,$19,$20}' | \
sort | uniq -c | \
sort -r -n -k1 | \
head -n 10

echo
echo ---------------------