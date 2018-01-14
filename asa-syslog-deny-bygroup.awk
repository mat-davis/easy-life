#AWK script to parse Cisco PIX/ASA syslog for Deny entries (access-group) then display source IP, destination IP, protocol & port (+ headers)
#Created 19/10/2015 by Mattd
/-4-106023/ {
 if (($7 ~ /^tcp$/ || $7 ~ /^udp$/) && $13 ~ /^access-group$/) printf "%-16s %-16s %-4s %-5s\n" ,substr($9,1+ index($9,":"),-2 + index($9,"/")),substr($11,1+ index($11,":"),-2 + index($11,"/")),$7,substr($11,1+index($11,"/"),5)
 }