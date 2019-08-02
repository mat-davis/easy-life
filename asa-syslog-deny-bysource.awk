# AWK to parse Cisco PIX/ASA syslog for 'Deny' entries then display by source IP (no headers)
# Created 13/10/2015 by mat-davis
# Use with | sort | uniq -c | sort -r -n -k1 | head
/ ASA-4-106023/ {
 if ($7 ~ /^tcp$/ || $7 ~ /^udp$/) printf "%-16s\n" , substr($9,1+ index($9,":"),(index($9,"/") - (1+ index($9,":"))))
 }