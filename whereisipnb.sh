# --------------------
# simple bash command to grep files looking for an IP
# --------------------

#!/bin/bash
if [ X"$1" != X ]; then
IP=$1;
else echo Enter the IP you are looking for
read IP
fi

egrep  "$IP\ |$IP\/" /backup/*/*/ifconfig
egrep  "$IP\ |$IP\/" /backup/*/*/routes
egrep  "$IP\ |$IP\/" /backup/*/*/policy
