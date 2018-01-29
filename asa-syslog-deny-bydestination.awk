#AWK script to parse Cisco PIX/ASA syslog for 'Deny' entries then display by source IP (no headers)
#Created 13/10/2015 by mat-davis
#Amended (1) 28/01/2018 by mat-davis
#Amended (2) 28/01/2018 by mat-davis
#Amended (3) 28/01/2018 by mat-davis
#Amended (4) 28/01/2018 by mat-davis
#Amended (5) 28/01/2018 by mat-davis
/ASA-4-106023/ {
 if ($7 ~ /^tcp$/ || $7 ~ /^udp$/) printf "%-16s\n" , substr($11,1+ index($11,":"),(index($11,"/")))
 }
