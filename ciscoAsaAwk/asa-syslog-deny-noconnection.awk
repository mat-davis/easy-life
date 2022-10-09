# AWK to parse Cisco PIX/ASA syslog for Deny 'No Connection' entries then display source IP, destination IP, protocol & port (no headers)
# Created 29/09/2015 by mat-davis
# Use with | sort | uniq -c | sort -r -n -k1 | head
/Deny/ {
 if (($5 ~ /^%ASA-6-106015:/) printf "%-16s %- 16s %-8s %-5s\n" ,substr($10,1+ index($10,"("),-2 + index($10,"/")),substr($13,1+ index($13,"("),-2 + index($13,"/")),$8,substr($12,1+index($12,"/"),5)
 }