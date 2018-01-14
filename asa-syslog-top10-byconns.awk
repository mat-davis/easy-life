#AWK script to parse Cisco PIX/ASA syslog for build entries then display source IP, destination IP, protocol & port (no headers)
#Created 29/09/2015 by Mattd
/Built/ {
 if (($8 ~ /^TCP$/ || $8 ~ /^UDP$/) && $7 ~ /^outbound$/) printf "%-16s %-16s %-8s %-5s\n" ,substr($16,1+ index($16,"("),-2 + index($16,"/")),substr($13,1+ index($13,"("),-2 + index($13,"/")),$8,substr($12,1+index($12,"/"),5)
 }
/Built/ {
 if (($8 ~ /^TCP$/ || $8 ~ /^UDP$/) && $7 ~ /^inbound$/) printf	 ,substr($13,1+ index($13,"("),-2 + index($13,"/")),substr($16,1+ index($16,"("),-2 + index($16,"/")),$8,substr($15,1+index($15,"/"),5)
 }
/Built/ {
 if ($8 ~ /^ICMP$/) printf "%-16s %-16s %-8s\n" ,substr($14,1+ index($14,"("),-1 + index($14,"/")),substr($12,0,-1 + index($12,"/")),$8
 }