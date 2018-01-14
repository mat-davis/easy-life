#!/usr/bin/expect

#####################################################################################
#
# This script automates COAT for commercial firewalls
#
#####################################################################################

#******* check for input from command line *******
set HOSTIP [lindex $argv 0]
if {[llength $argv] == 0 } {
   puts "usage: coat2-asa <IP>\n"
   exit 1
}
#make sure entered IP address is valid
if {[regexp {^\d+\.\d+\.\d+\.\d+$} $HOSTIP]
 && [scan $HOSTIP %d.%d.%d.%d a b c d] == 4
 && 0 <= $a && $a <= 255 && 0 <= $b && $b <= 255
 && 0 <= $c && $c <= 255 && 0 <= $d && $d <= 255} {
} else {
    puts "Not a valid IP address $HOSTIP\n"
    exit 1
}

#******* set global variables *******

set DATE [exec date +%d%m%y]
set timeout 10
set count 0
set prompt "#$"
set missing "\033\[00;31m\[Command Missing\]\033\[;0m"
set manual "\033\[00;33m\[Manual] Please see the 'Manual Check' Section below\033\[;0m"
set context "\033\[00;34m\[Context] This check will be performed as part of the <system> COAT\033\[;0m"
set failover "\033\[00;35m\[No Failover configured]\033\[;0m"
set extra "\033\[00;31m\[Command Extra\]\033\[;0m"
set code_err "\033\[00;31m\[Code Error\]\033\[;0m"


#********** Set build check variables **********

set aaa_auth [list "aaa authentication login default group tacacs+ local" \
"aaa authentication login vty-auth group tacacs+ local" \
"aaa authentication login console-auth group tacacs+ local" \
"aaa authentication enable default group tacacs+ enable"]

set aaa_autho [list "aaa authorization commands 15 default group tacacs+ local" \
"aaa authorization config-commands" \
"aaa authorization exec default group tacacs+ none"]

set aaa_acco [list "aaa accounting exec default start-stop group tacacs+" \
"aaa accounting commands 15 default start-stop group tacacs+"]

set nameif [list "Interface conventions"\
"Name"\
" Internet      = Internet"\
" Management    = mgmt"\
" Backup        = backupnet"\
" Customer      = VLAN Name"\
"Security level"\
" 0  - Internet"\
" 25 - Management"\
" 50 - Customer"]

set banner [list "Banner from build guide:-" \
"********************************************************************************" \
"*                                                                              *" \
"* This computer system is the property of Vodafone Limited.                    *" \
"*                                                                              *" \
"* Only authorised users are entitled to connect and/or login to this           *" \
"* computer system. If you are not sure whether you are authorised, then you    *" \
"* should DISCONNECT IMMEDIATELY and seek advice from your line manager.        *" \
"*                                                                              *" \
"********************************************************************************"]

set aaa_auth [list "aaa authentication ssh console TACACS+ LOCAL" \
"aaa authentication enable console TACACS+ LOCAL"]

set aaa_autho [list "aaa authorization command TACACS+ LOCAL"]

set aaa_acco [list "aaa accounting command TACACS+"]

set bastions [list "ssh 217.135.0.67" \
"ssh 217.135.2.67" \
"ssh 217.135.5.67" \
"ssh 217.135.2.74" \
"ssh 217.135.0.77" \
"ssh 217.135.2.22"]

set policy_map [list "  inspect dns dns_inspect" \
"  inspect ftp" \
"  inspect h323 h225" \
"  inspect h323 ras" \
"  inspect http" \
"  inspect ils" \
"  inspect netbios" \
"  inspect rsh" \
"  inspect rtsp" \
"  inspect skinny" \
"  inspect icmp" \
"  inspect sqlnet" \
"  inspect sunrpc" \
"  inspect tftp" \
"  inspect xdmcp" ]


#********** Procedures **********

#Procedure for printing values to screen
proc printoutput {testno desc value result} {
  #set desc string to be 40 characters long, pad trailing with space
  set desc_len [string length $desc]
  set desc_len [expr 40 - $desc_len]
  for {set i 1} {$i <= $desc_len} {incr i} {
    append desc " "
  }
  #clear whitespaces from command output in value to tidy up display
  regsub -all { +} $value { } value
  #format output to screen depending on values passed to function
  if {$result == 0} {
    set result "\033\[00;31m\[FAIL\]\033\[;0m"
  }
  if {$result == 1} {
    set result "\033\[00;32m\[PASS\]\033\[;0m"
  }
  if {$result == 2} {
    set result "\033\[00;33m\[CHECK\]\033\[;0m"
  }
  if {$result == 3} {
    set result "\033\[00;34m\[CTX\]\033\[;0m"
  }
  if {$result == 4} {
    set result "\033\[00;35m\[SNGL\]\033\[;0m"
  }

  if {$value == 0} {
    puts "\033\[00;33m#$testno\033\[;0m\t$result\t$desc"
  } else {
    puts "\033\[00;33m#$testno\033\[;0m\t$result\t$desc\t$value"
  }
}

#Procedure to get over no lsearch -all in 8.3
proc allsearch {data regx} {
  set i 0
  set item_list {}
  foreach item $data { ;# loop through config file
    if {[regexp -- $regx $item] == 1} {
      lappend item_list $i
    }
    incr i
  }
  if {[llength $item_list] == 0} {
    return {}
  } else {
    return $item_list
  }
}

#Procedure to trim trailing whitespace from show output and create list
proc trim_show {output} {
  set newlist {}
  set output [split $output "\n"]
  foreach line $output {
    lappend newlist [string trimright $line]
  }
  return $newlist
}

#Procedure to issue send command and return output
#This procedure sends the cisco command and as expect_out buffer fills stores
#the output overcoming buffer size issues and loss of data
#The data is right space trimmed and returned
proc get_data {send_cmd} {
  set result {}
  global prompt
  log_user 0
  send "$send_cmd\r"
  expect {
    full_buffer {
      append result $expect_out(buffer)
      exp_continue
    }
    $prompt {
      append result $expect_out(buffer)
    }
  }
  log_user 1
  return [trim_show $result] ;#return the output trimmed of trailing spaces
}

#Procedure to format manual output display
proc manual {testno desc output listtag} {
  puts "#\[$testno\]"
  puts "$desc"
  #check for string or list, output data
  if {[string length $output] > 0} {
    puts "\033\[;37m"
    if {$listtag == 1} {
      foreach i $output {puts $i}
    } else {
      puts $output
    }
    puts "\033\[;0m"
  }
  puts "\n\n"
}


#********** SSH to device and login **********

# grab the password
stty -echo
send_user -- "Password: "
expect_user -re "(.*)\n"
send_user "\n"
stty echo
set PASSWORD $expect_out(1,string)
set exp_internal 1

spawn /usr/bin/ssh $HOSTIP
expect {
   timeout {puts "Connection timed out"; exit}
   "RSA" {send "yes\r"; expect "word:"}
   "word:"
}
sleep 1
send "$PASSWORD\r"
expect {
   timeout {puts "Password timed out"; exit}
   "word:" {puts "Password incorrect"; exit}
   ">"
}
send "enable\r"
expect "word:"
send "$PASSWORD\r"
expect {
   timeout {puts "Enable password timed out"; exit}
   "word:" {puts "Enable password incorrect"; exit}
   "#"
}

log_user 0
#set pager to unlimited, get prompt
send "\r"
expect "#"
set prompt [string trimleft $expect_out(buffer)]
send "terminal pager 0\r"
expect $prompt

#The expect prompt is now $prompt = <hostname>#

log_user 1

#check firewall mode is single
send "show mode\r"
expect $prompt
if {[regexp {mode:\s+multiple} $expect_out(buffer)]} {
#  puts "\n\n** Firewall mode is Context based, this coat is for single mode firewalls **\n\n"
#  send "logout\r"
#  expect eof
#  exit 0

  #get running config of context
  puts "\nGrabbing running config"
  set data [get_data {show running-config}]
} else {
  #get running config
  puts "\nGrabbing running config"
  set data [get_data {more system:running-config}]
}

#********** Grab data from show command into variables for later processing **********


#get show commands output
puts "Grabbing COAT command show output"

#set show_aaa [get_data {show runn aaa-server}]
set show_dhcp [get_data {show dhcpd state}]
set show_policy [get_data {show runn policy-map}]
set show_cap [get_data {show capture}]
set show_clock [get_data {show clock}]
#set show_interfaces [get_data {show interface}]
#set show_ntp [get_data {show ntp asso}]
set show_sysopt [get_data {show run all sysopt}]
set show_logging [get_data {show logging | exclude [0-9][0-9]:[0-9][0-9]:[0-9][0-9]}]
set show_version [get_data {show version}]
set show_failover [get_data {show failover}]
set show_hostname [get_data {show hostname}]
set show_nameif [get_data {show nameif}]

#foreach item $show_nameif {
#  puts "nameif $item"
#}
#foreach item $show_logging {
#  puts "logging $item"
#}
#foreach item $show_policy {
#  puts "show_policy $item"
#}
#foreach item $show_cap {
#  puts "show_cap $item"
#}
#foreach item $show_clock {
#  puts "show_clock $item"
#}
#foreach item $show_interfaces {
#  puts "show_interfaces $item"
#}
#foreach item $show_ntp {
#  puts "show_ntp $item"
#}
#foreach item $show_sysopt {
#  puts "show_sysopt $item"
#}

puts "\n\n"

#********** Process each COAT check **********

#1.01
#check passwords are encrypted
set testno "1.01"
set desc "All passwords encrypted"
set all {}
set enc_out {}
set value 0
set result 0
set enablepass [lindex $data [lsearch $data "enable password*"]]
set sso [lindex $data [lsearch $data "username sso-admin password *"]]
# set enc [lindex $data [lsearch $data "password encryption*"]]
# puts "$enablepass $sso $enc"
if {[regexp {.*encrypted} $enablepass all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "enable password not encrypted"
  printoutput $testno $desc $value $result
}
set result 0
if {[regexp {.*encrypted.*} $sso all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "sso password not encrypted"
  printoutput $testno $desc $value $result
}
set result 0i
# Following section only required in SECURE
# regexp {password encryption (aes)} $enc all enc_out
# if {$enc_out == "aes"} {
#   set result 1
#   set value $all
#   printoutput $testno $desc $value $result
# } else {
#   set value "$missing password encryption aes"
#   printoutput $testno $desc $value $result
# }
# set result 0


#1.02
#Check AAA servers are configured
set testno "1.02"
set desc "AAA Servers are Configured"
set value 0
set result 0
set tacserver {}
set interface {}
set confpos [allsearch  $data {aaa-server\sTACACS\+ \(}] ;# return all lines containing tacacs server for managment

if {[llength $confpos] > 0} {
  set result 1
  foreach line $confpos {
    regexp -- {\(([\w|\-]+)\)\shost\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})} [lindex $data $line] all interface tacserver   ;# Get tacacs server IP and interface
    #store tacacs server IP's in list for next coat test
    set value "$interface $tacserver"
    printoutput $testno $desc $value $result
  }
} else {
  set value "No aaa servers configured"
  printoutput $testno $desc $value $result
}

#1.03
#Validate the AAA servers are working
set testno "1.03"
set desc "Validate the AAA servers are working"
set value "\033\[00;33m\Please run command: test aaa-server authentication TACACS+ host <ip address>'\033\[;0m"
set result 2
printoutput $testno $desc $value $result

#1.04
#Check only local user sso-admin is configured?
set testno "1.04"
set desc "Username sso-admin present"
set value 0
set result 0
#get line number of all username line sections in config
set regx {^username.*$}
set cmd_lines [allsearch $data $regx]
set sso [lsearch $data "username sso-admin*"]
if {[llength $cmd_lines] > 1 } {
   set value "More than 1 username configured, check config"
   printoutput $testno $desc $value $result
   foreach user $cmd_lines {
     if {$user == $sso} { continue } ;#ignore the sso-admin line
     set value [lindex $data $user]
     printoutput $testno $desc $value $result
  }
}
#Check username sso-admin exists
if {$sso != -1} {
  set result 1
  set value [lindex $data $sso]
  printoutput $testno $desc $value $result
} else {
   set value "No sso-admin username present, check config"
   printoutput $testno $desc $value $result
}

#1.05
#Authentication is configured correctly?
set testno "1.05"
set desc "AAA Authentication Configured"
set value 0
set result 0
if {[regexp {aaa authentication} $data]} { ;#check aaa authentication is in config
  set tacpos [allsearch $data {aaa authentication}] ;# return all lines containing aaa authentication
  foreach group $aaa_auth { ;#check each line in config matches aaa authentication requirements (as set in list aaa_auth)
    foreach line $tacpos {
      set value $group
      if {[string equal $group [lindex $data $line]]} { ;#compare the line in config with the required setting
        set result 1
        printoutput $testno $desc $value $result
        break ;#match was found, get next setting
      }
    }
    if {$result == 0} { ;#there was no match, error with missing group
      set value "$missing $group"
      printoutput $testno $desc $value $result
    }
    set result 0
  }
} else {
  set result 0
  set value "$missing No aaa authentication config found"
  printoutput $testno $desc $value $result
}

#1.06
#Authorisation is configured correctly?
set testno "1.06"
set desc "AAA Authorization Configured"
set value 0
set result 0
if {[regexp {aaa authorization} $data]} {
  set tacpos [allsearch $data {aaa authorization}] ;# return all lines containing aaa authorization
  foreach group $aaa_autho { ;#check each line in config matches aaa autentication requirements
    foreach line $tacpos {
      set value $group
      if {[string equal $group [lindex $data $line]]} {
        set result 1
        printoutput $testno $desc $value $result
        break ;#match was found, get next setting
      }
    }
    if {$result == 0} {
      set value "$missing $group"
      printoutput $testno $desc $value $result
    }
    set result 0
  }
} else {
  set result 0
  set value "$missing No aaa authorization config found"
  printoutput $testno $desc $value $result
}

#1.07
#Accounting is configured correctly?
set testno "1.07"
set desc "AAA Accounting Configured"
set value 0
set result 0
if {[regexp {aaa accounting} $data]} {
  set tacpos [allsearch $data {aaa accounting}] ;# return all lines containing aaa authentication
  foreach group $aaa_acco { ;#check each line in config matches aaa autentication requirements
    foreach line $tacpos {
      set value $group
      if {[string equal $group [lindex $data $line]]} {
        set result 1
        printoutput $testno $desc $value $result
      }
    }
    if {$result == 0} {
      set value "$missing $group"
      printoutput $testno $desc $value $result
    }
    set result 0
  }
} else {
  set result 0
  set value "$missing No aaa accounting config found"
  printoutput $testno $desc $value $result
}

#2.01
#Check NTP status
set testno "2.01"
set desc "NTP servers configured and synchronised"
set value $context
set result 3
printoutput $testno $desc $value $result
# set cmd_lines [allsearch $show_ntp {\d+\.\d+\.\d+\.\d+}]
# if {[llength $cmd_lines] == 0} {
#   set result 0
#   set value "$missing No ntp servers seem to be configured"
#   printoutput $testno $desc $value $result
# } else {
#   foreach line $cmd_lines {
#     set cmd_line [lindex $show_ntp $line]
#     if {[regexp {(\*|\+)\~\d+\.\d+\.\d+\.\d+\s} $cmd_line value]} { #IP address configured and in sync with ntp server
#       set result 1
#       printoutput $testno $desc $value $result
#     } else { #IP address configured but not in sync with ntp server
#       set result 0
#       regexp {.\~\d+\.\d+\.\d+\.\d+\s} $cmd_line value
#       printoutput $testno $desc $value $result
#     }
#   }
# }

#2.02
#Interfaces show no errors
set testno "2.02"
set desc "No Interface Input/Output errors"
set value $context
set result 3
printoutput $testno $desc $value $result
#set error 0
#set port_count 0
#set int_name {}
#set limit [llength $show_interfaces]
#set cmd_lines [allsearch $show_interfaces {^Interface}]
##process each interface
#foreach cmd_line_no $cmd_lines {
#  #skip virtual interfaces beforing storing interface name
#  if {[regexp {VLAN identifier} [lindex $show_interfaces [expr $cmd_line_no + 2]]]} {
#    continue
#  }
#  #store interface name
#  regexp {^Interface\s+(\w+[0-9]+[\/0-9]*)\s} [lindex $show_interfaces $cmd_line_no] int_name
#  #increment lines until interface error line match
#  while {[regexp {(\d+)\s+input\s+errors} [lindex $show_interfaces $cmd_line_no] all port_count] != 1 && $cmd_line_no < $limit} {
#    incr cmd_line_no
#  }
#  #check interface input errors
#  if {$port_count != 0} {
#    #errors found report the fact
#    set value "$int_name: Input errors - $port_count"
#    printoutput $testno $desc $value $result
#    set error 1
#  }
#  incr cmd_line_no
#  #check output errors
#  while {[regexp {(\d+)\s+output\s+errors} [lindex $show_interfaces $cmd_line_no] all port_count] != 1 && $cmd_line_no < $limit} {
#    incr cmd_line_no
#  }
#  if { $port_count != 0} {
#    #errors found report the fact
#    set value "$int_name: Output errors - $port_count"
#    printoutput $testno $desc $value $result
#    set error 1
#  }
#}
#if {$error == 0} {
#  set result 1
#  set value "No Interface errors detected"
#  printoutput $testno $desc $value $result
#}

#2.03
#Check clock UTC
set testno "2.03"
set desc "Clock set to UTC Timezone"
set value 0
set result 0
set time [lindex $show_clock [lsearch -regexp $show_clock {\d\d:\d\d:\d+\d\.}]]
if {[regexp -nocase {(.*(?: utc ).*)} $time value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  set value $time
  printoutput $testno $desc $value $result
}

#2.04
#Validate Current Version matches Vodafone Standard Version
set testno "2.04"
set desc "Validate Current Version"
set value $manual
set result 2
printoutput $testno $desc $value $result

#2.05
#Validate the license is Installed on ASA
set testno "2.05"
set desc "Validate the license is Installed on ASA"
set value $context
set result 3
printoutput $testno $desc $value $result

#2.06
#Check for Errors in the start-up configuration
set testno "2.06"
set desc "Check for Errors in the start-up configuration"
set value $context
set result 3
printoutput $testno $desc $value $result

#2.07
#Validate Hostname
set testno "2.07"
set desc "Validate Hostname"
set value $manual
set result 2
printoutput $testno $desc $value $result

#2.08
#Validate Additional Files are Removed from Flash
set testno "2.08"
set desc "Validate Files are Removed from Flash"
set value $context
set result 3
printoutput $testno $desc $value $result

#2.09
#Validate motd banner is to the Vodafone standard
set testno "2.09"
set desc "Validate MOTD banner is standard"
set value 0
set result 0
if {[lsearch -regexp $data {^banner motd}] > 0} {
  set value "Banner motd detected, ensure only banner login set"
  printoutput $testno $desc $value $result
}
if {[lsearch -regexp $data {^banner login}] > 0} {
  set result 1
  set value "Banner login exists, ensure matches example below"
  printoutput $testno $desc $value $result
} else {
  set value "No banner login detected"
  printoutput $testno $desc $value $result
}

#2.10
#Check no names
set testno "2.10"
set desc "No names set"
set value 0
set result 0
if {[regexp -nocase {(no names)} $data value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  set value "names is set"
  printoutput $testno $desc $value $result
}

#2.11
#Basion ssh access
set testno "2.11"
set desc "ssh from bastions only"
set value 0
set result 0
set group {}
set bast {}
if {[regexp -- {ssh\s+\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}} $data]} { ;#check ssh access is in config
  set cmdline [allsearch $data {ssh \d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}}] ;# return all lines containing ssh <ip>
  #check all devices in required bastion list exist
  foreach group $bastions { ;#check each line in config matches bastion ssh requirements
    foreach line $cmdline {
      regexp {ssh\s+\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}} [lindex $data $line] bast
      set value $group
      if {[string equal $group $bast]} { ;#compare the line in config with the required setting
        set result 1
        printoutput $testno $desc $value $result
        break ;# process next host
      }
    }
    if {$result == 0} { ;#there was no match
      set value "$missing $group"
      printoutput $testno $desc $value $result
    }
    set result 0
  }
  #check for configured bastions outside the required list
  foreach line $cmdline {
    regexp {ssh\s+\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}} [lindex $data $line] bast
    foreach group $bastions { ;#check each line in config matches bastion ssh requirements
      if {[string equal $group $bast]} { ;#compare the line in config with the required setting
        set result 1
        break ;# match found process next host
      }
    }
    if {$result == 0} { ;#there was no match
      set value "Unknown bastion $bast"
      printoutput $testno $desc $value $result
    }
    set result 0
  }
} else {
  set value "No ssh access found"
  printoutput $testno $desc $value $result
}

#2.12
#Check ssh is version 2
set testno "2.12"
set desc "SSH set to version 2"
set value 0
set result 0
set val {}
set all {}
if {[regexp -- {ssh\s+version\s+(\d+)} $data all val]} {
  if {$val == 2} {
    set result 1
    set value $all
    printoutput $testno $desc $value $result
  } else {
    set value $all
    printoutput $testno $desc $value $result
  }
} else {
  set value "No ssh version value found"
  printoutput $testno $desc $value $result
}

#2.13
#Check ssh timeout is 9 minutes
set testno "2.13"
set desc "SSH timeout is 9 minutes"
set value 0
set result 0
set val {}
set all {}
if {[regexp -- {ssh\s+timeout\s+(\d+)} $data all val]} {
  if {$val == 9} {
    set result 1
    set value $all
    printoutput $testno $desc $value $result
  } else {
    set value $all
    printoutput $testno $desc $value $result
  }
} else {
  set value "No ssh timeout value found"
  printoutput $testno $desc $value $result
}

#2.14
#Check telnet disabled
set testno "2.14"
set desc "Telnet disabled"
set value 0
set result 0
set cmdline [allsearch $data {telnet\s+\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\s+\w+}] ;# return all lines containing telnet <ip>
if {[llength $cmdline] > 0} {
  foreach line $cmdline {
    set value [lindex $data $line]
    printoutput $testno $desc $value $result
  }
} else {
  set result 1
  set value "No telnet host allow found"
  printoutput $testno $desc $value $result
}

#2.15
#Check http enabled
set testno "2.15"
set desc "HTTP server enabled"
set value 0
set result 0
set all {}
if {[regexp -- {http\sserver\enable} $data all]} {
  set value $all
  printoutput $testno $desc $value $result
} else {
  set result 1
  set value "HTTP server disabled"
  printoutput $testno $desc $value $result
}

#2.16
#Check domain correct
set testno "2.16"
set desc "Domain name set correctly"
set value 0
set result 0
set all {}
set val {}
set line [lsearch -regexp $data {^domain-name} ]
if {$line > 0} {
  if {[regexp -- {vodafone.com} [lindex $data $line] all ] || [regexp -- {secure-ops.net} [lindex $data $line] all]} {
    set result 1
    set value $all
    printoutput $testno $desc $value $result
  } else {
    set value [lindex $data $line]
    printoutput $testno $desc $value $result
  }
} else {
  set value "No domain setting found"
  printoutput $testno $desc $value $result
}

#2.17
#Check prompt correct
set testno "2.17"
set desc "Prompt set correctly"
set value $context
set result 3
printoutput $testno $desc $value $result
# set all {}
# if {[regexp -- {prompt\s+hostname\scontext} $data all] || [regexp -- {prompt\s+hostname\spriority\sstate} $data all]} {
#   set result 1
#   set value $all
#   printoutput $testno $desc $value $result
# } else {
#   set value [lindex $data [lsearch -regexp $data {^prompt}]]
#   printoutput $testno $desc $value $result
# }

#2.18
#Check VPN not permitted by default (unless vpn device)
set testno "2.18"
set desc "VPN not permitted by default"
set value 0
set result 0
set all {}
if {[regexp -- {no\s+sysopt\s+connection\s+permit\-vpn} $show_sysopt all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value [lindex $show_sysopt [lsearch -regexp $show_sysopt {permit\-vpn}]]
  printoutput $testno $desc $value $result
}

#2.19
#Check DHCP not running
set testno "2.19"
set desc "DHCP Server not running"
set value 0
set result 0
set all {}
if {[regexp -- {Not\s+Configured\s+for\s+DHCP} $show_dhcp all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value [lindex $show_dhcp [lsearch -regexp $show_dhcp {DHCP}]]
  printoutput $testno $desc $value $result
}

#2.20
#Check no captures running
#set testno "2.20"
set desc "No captures running"
set value 0
set result 1
foreach line $show_cap {
  if {[regexp -- {^capture} $line]} {
    set result 0
    set value $line
    printoutput $testno $desc $value $result
  }
}
if {$result == 1} {
  set value "No captures found"
  printoutput $testno $desc $value $result
}

#2.21
#application inspection correct
set testno "2.21"
set desc "application inspection"
set value 0
set inspect_missing 0
set result 0
set line {}

set line [lsearch -regexp $data {inspect\s+dns\s+dns\_inspect} ]
if {$line >0 } {
  set value [lindex $data $line]
  set result 1
  printoutput $testno $desc $value $result
  set line [lsearch -regexp $data {message\-length\s+maximum\s+1280} ]
  if {$line >0 } {
    set value [lindex $data $line]
    set result 1
    printoutput $testno $desc $value $result
  } else {
    set value "message-length maximum 1280 not found"
    printoutput $testno $desc $value $result
  }
} else {
  set value "$missing policy-map type inspect dns_inspect"
  printoutput $testno $desc $value $result
}

#search for global policy
set line [lsearch -regexp $data {policy-map\s+global-policy} ]
if {$line >0 } {
  set value [lindex $data $line]
  set line [lsearch -regexp $data {ass inspection_default} ]
  if {$line >0 } {
    set result 1
    printoutput $testno $desc $value $result
  }
} else {
  set value "$missing policy-map global_policy"
  printoutput $testno $desc $value $result
}

set result 0
#check the build guide matches configured
set cmdline [allsearch $data {\s\sinspect\s+\w+}] ;# return all lines containing inspect
foreach inspect $policy_map {
  set value $inspect
  foreach line $cmdline {
    if {[string equal $inspect [lindex $data $line]]} { ;#compare the line in config with the required setting
      set result 1
      break ;# process next inspect line
    }
  }
  if {$result == 0} { ;#there was no match
    set value "$missing $value"
    printoutput $testno $desc $value $result
    set inspect_missing 1
  }
  set result 0
}
#check the configured matches build guide
foreach line $cmdline {
  set value [lindex $data $line]
  foreach inspect $policy_map {
    if {[string equal $inspect [lindex $data $line]]} { ;#compare the line in config with the required setting
      set result 1
      break ;# process next inspect line
    }
  }
  if {$result == 0} { ;#there was no  match
    set value "$extra $value"
    printoutput $testno $desc $value $result
    set inspect_missing 1
  }
  set result 0
}
if {$inspect_missing == 0} {
  set result 1
  set value "All inspect parameters correct"
  printoutput $testno $desc $value $result
}

#2.22
#Check service policy configured
set testno "2.22"
set desc "Service policy configured"
set value 0
set result 0
set all {}
if {[regexp -- {service-policy\sglobal-policy\sglobal} $data all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "$missing service-policy global_policy global"
  printoutput $testno $desc $value $result
}

#2.23
#Validate Vodafone standard interface naming convention
set testno "2.23"
set desc "Validate nameif name"
set value $manual
set result 2
printoutput $testno $desc $value $result

#2.24
#Validate Vodafone standard security level is configured
set testno "2.24"
set desc "Validate nameif security level"
set value $manual
set result 2
printoutput $testno $desc $value $result

#2.25
#Check reverse path
set testno "2.25"
set desc "Check reverse path configured per int"
set value 0
set result 0
set reverse_missing 0
set ipverify {}
set int1 {}
set int2 {}
set cmd_lines [allsearch $data {nameif\s\w}]
if {[llength $cmd_lines] == 0} {
  set result 0
  set value "$missing No nameif seem to be configured"
  printoutput $testno $desc $value $result
} else {
  set reverse [allsearch $data {reverse-path}]
  foreach line $cmd_lines {
    foreach ipverify $reverse {
      #get interface name from ip verify and interface nameif
      regexp -- {nameif\s([\w|\-]+)} [lindex $data $line] all int1
      regexp -- {reverse-path\sinterface\s([\w|\-]+)} [lindex $data $ipverify] all int2
      if {[string equal $int1 $int2]} {
        set result 1
        break ;#match so get next nameif
      }
    }
    if {$result == 0} { ;#there was no match
      set value "$missing ip verify reverse-path $int1"
      printoutput $testno $desc $value $result
      set reverse_missing 1
    }
    set result 0
  }
  if {$reverse_missing == 0} { ;#all interfaces match reverse path
      set value "All nameif matched reverse path"
      set result 1
      printoutput $testno $desc $value $result
  }
}

#3.01
#Validate logging
set testno "3.01"
set desc "Logging enabled"
set value 0
set result 0
set all {}
if {[regexp -- {Syslog\slogging\:\senabled} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "logging disabled"
  printoutput $testno $desc $value $result
}

#3.02
#Validate Timestamp
set testno "3.02"
set desc "Logging timestamp enabled"
set value 0
set result 0
set all {}
if {[regexp -- {Timestamp logging\:\senabled} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "logging timestamp disabled"
  printoutput $testno $desc $value $result
}

#3.03
#Validate standby
set testno "3.03"
set desc "Standby Logging disabled"
set value 0
set result 0
set all {}
if {[regexp -- {Standby\slogging\:\sdisabled} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "logging standby enabled"
  printoutput $testno $desc $value $result
}

#3.04
#Validate Trace logging
set testno "3.04"
set desc "Trace Logging disabled"
set value 0
set result 0
set all {}
if {[regexp -- {Debug-trace\slogging\:\sdisabled} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "Debug-trace Logging enabled"
  printoutput $testno $desc $value $result
}
#3.05
#Validate Console logging
set testno "3.05"
set desc "Console Logging Level Emergencies"
set value 0
set result 0
set all {}
if {[regexp -- {Console\slogging\:\slevel\semergencies} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {Console\slogging\:\slevel\s\w+} $show_logging value
  printoutput $testno $desc $value $result
}

#3.06
#Validate Monitor logging
set testno "3.06"
set desc "Monitor Logging Disabled"
set value 0
set result 0
set all {}
if {[regexp -- {Monitor\slogging\:\sdisabled} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {Monitor\slogging\:\s\w+} $show_logging value
  printoutput $testno $desc $value $result
}

#3.07
#Validate Buffer logging
set testno "3.07"
set desc "Buffer Logging Level Informational"
set value 0
set result 0
set all {}
if {[regexp -- {Buffer\slogging\:\slevel\sinformational} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {Buffer\slogging\:\slevel\s\w+} $show_logging value
  printoutput $testno $desc $value $result
}

#3.08
#Validate trap logging
set testno "3.08"
set desc "Trap Logging Level Informational"
set value 0
set result 0
set all {}
if {[regexp -- {Trap\slogging\:\slevel\sinformational} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {Trap\slogging\:\slevel\s\w+} $show_logging value
  printoutput $testno $desc $value $result
}

#3.09
#Validate logging hosts
set testno "3.09"
set desc "Configured logging hosts"
set value 0
set result 0
set all {}
set ip {}
set interface {}
set cmd_lines [allsearch $show_logging {Logging\sto\s}]
if {[llength $cmd_lines] == 0} {
  set result 0
  set value "$missing No logging hosts configured"
  printoutput $testno $desc $value $result
} else {
  set result 1
  foreach line $cmd_lines {
    regexp -- {Logging\sto\s([\w|\-]+)\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})} [lindex $show_logging $line] all interface ip
    set value "$ip Interface: $interface"
    printoutput $testno $desc $value $result
  }
}

#3.10
#Validate History logging
set testno "3.10"
set desc "History Logging Level alerts"
set value 0
set result 0
set all {}
if {[regexp -- {History\slogging\:\slevel\salerts} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {History\slogging\:\slevel\s\w+} $show_logging value
  printoutput $testno $desc $value $result
}

#3.11
#Validate Mail logging
set testno "3.11"
set desc "Mail Logging Disabled"
set value 0
set result 0
set all {}
if {[regexp -- {Mail\slogging\:\sdisabled} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {Mail\slogging\:\slevel\s\w+} $show_logging value
  printoutput $testno $desc $value $result
}

#3.12
#Validate ASDM logging
set testno "3.12"
set desc "ASDM Logging Disabled"
set value 0
set result 0
set all {}
if {[regexp -- {ASDM\slogging\:\sdisabled} $show_logging all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {ASDM\slogging\:\slevel\s\w+} $show_logging value
  printoutput $testno $desc $value $result
}

#3.13
#Validate SNMP Traps enabled
set testno "3.13"
set desc "SNMP Traps enabled"
set value 0
set result 0
set all {}
if {[regexp -- {snmp-server\senable\straps} $data all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "$missing No snmp traps enabled"
  printoutput $testno $desc $value $result
}

#3.14
#Validate SNMP Traps syslog enabled
set testno "3.14"
set desc "SNMP Traps syslog enabled"
set value 0
set result 0
set all {}
if {[regexp -- {snmp-server\senable\straps\ssyslog} $data all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  set value "$missing No snmp traps syslog enabled"
  printoutput $testno $desc $value $result
}

#3.15
#Validate SNMP community not public
set testno "3.15"
set desc "SNMP community not public"
set value 0
set result 0
set ispub 0
set all {}
set commstring {}
set cmd_lines [allsearch $data {community}]
if {[llength $cmd_lines] == 0} {
  set result 0
  set value "$missing no snmp community strings found"
  printoutput $testno $desc $value $result
} else {
  foreach line $cmd_lines {
    regexp -- {community\s(\w+)} [lindex $data $line] all commstring
    set commstring [string tolower $commstring]
    if {[string equal $commstring "public"]} {
      set value "Found - [lindex $data $line]"
      set ispub 1
      printoutput $testno $desc $value $result
    }
  }
  if {$ispub == 0} {
    set result 1
    set value "No public strings found"
    printoutput $testno $desc $value $result
  }
}

#5.00
#Check failover is being used

if {[regexp -- {Failover\sOff} $show_failover all]} {
 set testno "5.0"
 set desc "Failover"
 set value $failover
 set result 4
 printoutput $testno $desc $value $result

} else {
  #process failover checks

#***********if above true so process failover section*********

#get failover settings
set show_inv [get_data {show inventory}]
set show_inv_mate [get_data {failover exec mate show inventory}]
set show_ver [get_data {show version}]
set show_ver_mate [get_data {failover exec mate show version}]
set show_run_fail [get_data {show run failover}]
set show_run_fail_mate [get_data {failover exec mate show run failover}]
set show_version_mate [get_data {show version}]
set show_int [get_data {show int ip brief}]
set show_int_mate [get_data {failover exec mate show int ip brief}]

#5.02
#Validate failover same model
set testno "5.02"
set desc "Failover same model used"
set value 0
set result 0
set all {}
#get model numbers from failover
set pri_data {}
set sec_data {}
regexp -- {PID\:\s(\w+)} $show_inv all pri_data
regexp -- {PID\:\s(\w+)} $show_inv_mate all sec_data
if {[llength $pri_data] == 0 && [llength $sec_data] == 0} {
  set result 0
  set value "Error data not found"
  printoutput $testno $desc $value $result
} elseif {[string equal $pri_data $sec_data]} {
  set result 1
  set value "Pri: $pri_data Sec: $sec_data"
  printoutput $testno $desc $value $result
} else {
  set value "Do Not match Pri: $pri_data Sec: $sec_data"
  printoutput $testno $desc $value $result
}

#5.03
#Validate failover contain same RAM
set testno "5.03"
set desc "Failover same memory installed"
set value 0
set result 0
set all {}
set pri_data {}
set sec_data {}
regexp -- {Hardware\:\s+\w+\,\s+(\w+\s\w+)} $show_version all pri_data
regexp -- {Hardware\:\s+\w+\,\s+(\w+\s\w+)} $show_version_mate all sec_data
if {[llength $pri_data] == 0 && [llength $sec_data] == 0} {
  set result 0
  set value "Error data not found"
  printoutput $testno $desc $value $result
} elseif {[string equal $pri_data $sec_data]} {
  set result 1
  set value "Pri: $pri_data Sec: $sec_data"
  printoutput $testno $desc $value $result
} else {
  set value "Do Not match Pri: $pri_data Sec: $sec_data"
  printoutput $testno $desc $value $result
}

#5.04
#Validate failover have same number of interfaces
set testno "5.04"
set desc "Failover same interfaces available"
set value 0
set result 0
set match_err 0
set line 2 ;# set line number 2 so miss out header on interface check
set all {}
set pri_data {}
set sec_data {}
set list_len_pri [expr [llength $show_int] - 1]
set list_len_sec [expr [llength $show_int_mate] - 1]
while {$line != $list_len_pri} {
  regexp -- {([\w|\/]+)\s+} [lindex $show_int $line] all pri_data
  regexp -- {([\w|\/]+)\s+} [lindex $show_int_mate $line] all sec_data
  if {[string equal $pri_data $sec_data]} {
     #all ok
  } else {
    set match_err 1
    set value "Do Not match Pri: $pri_data Sec: $sec_data"
    printoutput $testno $desc $value $result
  }
  set line [expr $line + 1]
}
if {$match_err == 0} {
  set result 1
  set value "Interfaces match"
  printoutput $testno $desc $value $result
}

#5.06
#Validate IOS versions are same
set testno "5.06"
set desc "Software Image version same"
set value 0
set result 0
set all {}
set pri_data {}
set sec_data {}
#serach for software versions in show failover output
set line [lsearch -regexp $show_failover {^Version\:} ]
if {$line == -1} {
  set result 0
  set value "$code_err Version not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {Version\:\s+\w+\s(.+)\,\s\w+\s(.+)} [lindex $show_failover $line] all pri_data sec_data
  if {[string equal $pri_data $sec_data]} {
    set result 1
    set value "Pri: $pri_data Sec: $sec_data"
    printoutput $testno $desc $value $result
  } else {
    set value "Pri: $pri_data Sec: $sec_data"
    printoutput $testno $desc $value $result
  }
}


#5.07
#Validate primary as primary
set testno "5.05"
set desc "Failover primary set as primary"
set value 0
set result 0
set all {}
#check which firewall is active nd check failover
set active_fw {}
regexp -- {/((pri|sec))/} $prompt all active_fw
switch $active_fw {
  pri { set active_fw "$show_run_fail" }
  sec { set active_fw "$show_run_fail_mate" }
}
if {[regexp -- {unit\sprimary} $active_fw all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {failover\slan\sunit\s\w+} $active_fw all
  set value $all
  printoutput $testno $desc $value $result
}


#5.08
#Validate secondary as secondary
set testno "5.08"
set desc "Failover secondary set as secondary"
set value 0
set result 0
set all {}
#check which firewall is active and check failover
set active_fw {}
regexp -- {/((pri|sec))/} $prompt all active_fw
switch $active_fw {
  pri { set active_fw "$show_run_fail_mate" }
  sec { set active_fw "$show_run_fail" }
}

if {[regexp -- {unit\ssecondary} $active_fw all]} {
  set result 1
  set value $all
  printoutput $testno $desc $value $result
} else {
  regexp -- {failover\slan\sunit\s\w+} $active_fw all
  set value $all
  printoutput $testno $desc $value $result
}


#5.09
#Validate failover lan interface xover
set testno "5.09"
set desc "Failover LAN interface xover"
set value 0
set result 0
set all {}
set pri_data {}
set sec_data {}
set line [lsearch -regexp $show_run_fail {^failover\slan\sint} ]
if {$line == -1} {
  set result 0
  set value "$code_err failover lan not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {failover\slan\sinterface\s(\w+)\s(\w+[\d|\/]+)} [lindex $show_run_fail $line] all pri_data sec_data
  if {[string equal $pri_data {xover}]} {
    set result 1
    set value "Failover nameif: $pri_data Interface: $sec_data"
    printoutput $testno $desc $value $result
  } else {
    set value "Failover nameif: $pri_data Interface: $sec_data"
    printoutput $testno $desc $value $result
  }
}

#5.10
#Validate failover link interface xover
set testno "5.10"
set desc "Failover link interface xover"
set value 0
set result 0
set all {}
set line [lsearch -regexp $show_run_fail {^failover\slink} ]
if {$line == -1} {
  set result 0
  set value "$code_err failover link not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {failover\slink\s(\w+)\s(\w+[\d|\/]+)} [lindex $show_run_fail $line] all pri_data sec_data
  if {[string equal $pri_data {xover}]} {
    set result 1
    set value "Failover link: $pri_data Interface: $sec_data"
    printoutput $testno $desc $value $result
  } else {
    set value "Failover link: $pri_data Interface: $sec_data"
    printoutput $testno $desc $value $result
  }
}

#5.12
#Validate interfaces are monitored normal
set testno "5.12"
set desc "Failover interface normal"
set value 0
set result 0
set match_err 0
set all {}
set pri_data {}
set sec_data {}
set ip_data {}
set state {}
set cmd_lines [allsearch $show_failover {\s+Interface\s\w+\s\(}]
if {[llength $cmd_lines] == 0} {
  set result 0
  set value "$missing No failover int seem to be configured"
  printoutput $testno $desc $value $result
} else {
  foreach line $cmd_lines {
    #get interface state and look for interfaces not in shutdown or normal
    regexp -- {\s+Interface\s(\w+)\s\(([\d|\.]+)\)\:\s([\w+|\s+]+)\((\w+)} [lindex $show_failover $line] all pri_data ip_data sec_data state
    set sec_data [string trim $sec_data]
    if {[string equal $sec_data "Normal"] || [string equal $state "Shutdown"]} {
    } else {
      set value "Failover Interface $pri_data $ip_data $sec_data"
      printoutput $testno $desc $value $result
      set match_err 1
    }
  }
  if {$match_err == 0} {
    set result 1
    set value "All failover interfaces currently normal"
    printoutput $testno $desc $value $result
  }
}


#5.13
#Validate poll time values
set testno "5.13"
set desc "Polltimes are correct"
set value 0
set result 0
set all {}
set line [lsearch -regexp $show_failover {^Unit\sPoll} ]
if {$line == -1} {
  set result 0
  set value "$code_err Unit Poll not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {Unit\sPoll\sfrequency\s(\d+)\s\w+\,\s\w+\s(\d+)} [lindex $show_failover $line] all pri_data sec_data
  if {$pri_data == 1 && $sec_data == 3} {
    set result 1
    set value "Unit Poll freq: $pri_data holdtime: $sec_data"
    printoutput $testno $desc $value $result
  } else {
    set value "Unit Poll freq: $pri_data (1) holdtime: $sec_data (3)"
    printoutput $testno $desc $value $result
  }
}
set line [lsearch -regexp $show_failover {^Interface\sPoll} ]
if {$line == -1} {
  set result 0
  set value "$code_err Interface Poll not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {Interface\sPoll\sfrequency\s(\d+)\s\w+\,\s\w+\s(\d+)} [lindex $show_failover $line] all pri_data sec_data
  if {$pri_data == 3 && $sec_data == 15} {
    set result 1
    set value "Interface Poll freq: $pri_data holdtime: $sec_data"
    printoutput $testno $desc $value $result
  } else {
    set value "Interface Poll freq: $pri_data (3) holdtime: $sec_data (15)"
    printoutput $testno $desc $value $result
  }
}

#5.15
#Validate failover IP
set testno "5.15"
set desc "Failover IP's as build guide"
set value 0
set result 0
set all {}
set line [lsearch -regexp $show_run_fail {^failover\sinterface\sip} ]
if {$line == -1} {
  set result 0
  set value "$code_err failover interface ip not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {\w+\s\w+\s\w+\s\w+\s([\d|\.]+).*standby\s([\d|\.]+)} [lindex $show_run_fail $line] all pri_data sec_data
  if {[string equal $pri_data "10.99.99.1"] && [string equal $sec_data "10.99.99.2"]} {
    set result 1
    set value "Failover IP $pri_data $sec_data"
    printoutput $testno $desc $value $result
  } else {
    set value "Failover IP $pri_data (10.99.99.1) $sec_data (10.99.99.2)"
    printoutput $testno $desc $value $result
  }
}

#5.16
#Validate failover lan Giga int
set testno "5.16"
set desc "Failover LAN Gigabit Interface"
set value 0
set result 0
set all {}
set pri_data {}
set sec_data {}
set line [lsearch -regexp $show_run_fail {^failover\slan\sint} ]
if {$line == -1} {
  set result 0
  set value "$code_err failover lan not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {failover\slan\sinterface\s\w+\s([a-z|A-Z]+)} [lindex $show_run_fail $line] all pri_data
  if {[string equal $pri_data {GigabitEthernet}]} {
    set result 1
    set value "Failover xover $pri_data"
    printoutput $testno $desc $value $result
  } else {
    printoutput $testno $desc $value $result
  }
}

#5.17
#Validate prompt
set testno "5.17"
set desc "Prompt set corretly"
set value 0
set result 0
set all {}
set pri_data {}
set sec_data {}
set line [lsearch -regexp $data {^prompt} ]
if {$line == -1} {
  set result 0
  set value "$code_err Prompt not found"
  printoutput $testno $desc $value $result
} else {
  regexp -- {prompt\s(.*)} [lindex $data $line] all pri_data
  if {[string equal $pri_data {hostname priority state}]} {
    set result 1
    set value "Prompt: $pri_data"
    printoutput $testno $desc $value $result
  } else {
    set value "Prompt: $pri_data (hostname priority state)"
    printoutput $testno $desc $value $result
  }
}

#5.19
#Validate interfaces are monitored
set testno "5.19"
set desc "Failover interfaces are monitored"
set value 0
set result 0
set match_err 0
set all {}
set pri_data {}
set sec_data {}
set ip_data {}
set cmd_lines [allsearch $show_failover {\s+Interface\s[\w+|\-]+\s\(}]
if {[llength $cmd_lines] == 0} {
  set result 0
  set value "$missing No failover int seem to be configured"
  printoutput $testno $desc $value $result
} else {
  foreach line $cmd_lines {
   regexp -- {\s+Interface\s([\w|\-]+)\s\(([\d|\.]+)\)\:[\w|\s]+\((\w+)} [lindex $show_failover $line] all pri_data ip_data sec_data
    if {[string equal $sec_data "Monitored"] || [string equal $sec_data "Shutdown"]} {
    } else {
      set value "Failover Interface $pri_data $ip_data $sec_data"
      printoutput $testno $desc $value $result
      set match_err 1
    }
  }
  if {$match_err == 0} {
    set result 1
    set value "All failover interfaces currently monitored"
    printoutput $testno $desc $value $result
  }
}


#end failover else section
}
#*********** Manual Check Output ************

puts "\n"
puts "The following are manual checks.\n"

#2.04
#IOS version check - manual
set testno "2.04"
set desc "Check IOS version is as per current build software matrix"
set output {}
set output [lindex $show_version [lsearch $show_version "*Software*"]]
set listtag 0
manual $testno $desc $output $listtag

#2.07
#IOS Validate Hostname - manual
set tiestno "2.07"
set desc "Validate Hostname"
set output {}
set output $show_hostname
set listtag 0
manual $testno $desc $output $listtag

#2.09
#Banner correct - Manual check
set testno "2.09"
set desc "Check login banner correct. Config banner :-"
set output {}
set banner_cfg {}

#get existing banner if exists
set cmd_line [lsearch $data {*banner login*}]
if {$cmd_line > 0} {
  while {[regexp {^\^C$} [lindex $data $cmd_line]] == 0 && $count < 9} {
    incr count
    lappend banner_cfg [lindex $data $cmd_line]
    incr cmd_line
  }
  incr count
  lappend banner_cfg [lindex $data $cmd_line]
  set output $banner_cfg
  set listtag 1
  manual $testno $desc $output $listtag
} else {
  set output "No banner found"
  manual $testno $desc $output $listtag
}
foreach item $banner { puts $item }

#2.24 & 2.25
#nameif correct - Manual check
set testno "2.23"
set desc "Check nameif correct"
set output {}
set nameif_cfg {}

#get existing nameif if exists
set cmd_line [lsearch $data {*nameif*}]
if {$cmd_line > 0} {
  while {[regexp {^\^C$} [lindex $data $cmd_line]] == 0 && $count < 9} {
    incr count
    lappend nameif_cfg [lindex $data $cmd_line]
    incr cmd_line
  }
  incr count
  lappend nameif_cfg [lindex $data $cmd_line]
  set output $nameif_cfg
  set listtag 1
  manual $testno $desc $output $listtag
} else {
  set output "No nameif found"
  manual $testno $desc $output $listtag
}
foreach item $nameif { puts $item }

#*********** Logout of device *************
send "logout\r"
expect eof

exit 0
