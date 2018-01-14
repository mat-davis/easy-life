#!/usr/bin/expect

#####################################################################################
#
# This script automates COAT for cisco IOS switches
#
#####################################################################################

#******* check for input from command line *******
set HOSTIP [lindex $argv 0]
if {[llength $argv] == 0 } {
   puts "usage: coat2-switch <IP>\n"
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


#********** Set build check variables **********

set aaa_auth [list "aaa authentication login default group tacacs+ local" \
"aaa authentication login vty-auth group tacacs+ local" \
"aaa authentication login console-auth group tacacs+ local" \
"aaa authentication enable default group tacacs+ enable"]

set aaa_autho [list "aaa authorization commands 15 default group tacacs+ local" \
"aaa authorization exec default group tacacs+ none"]

set aaa_acco [list "aaa accounting exec default start-stop group tacacs+" \
"aaa accounting commands 15 default start-stop group tacacs+"]

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
  } else {
    set result "\033\[00;32m\[PASS\]\033\[;0m"
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
send_user -- "Password for $HOSTIP: "
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
   "#"
}
#send "enable\r"
#expect "word:"
#send "$PASSWORD\r"
#expect {
#   timeout {puts "Enable password timed out"; exit}
#   "word:" {puts "Enable password incorrect"; exit}
#   "#"
#}



log_user 0
#set pager to unlimited, get prompt
send "\r"
expect "#$"
set prompt [string trimleft $expect_out(buffer)]
send "terminal length 0\r"
expect $prompt
log_user 1

#The expect prompt is now $prompt = <hostname>#

#********** Grab data from show command into variables for later processing **********

#get running config
puts "\nGrabbing running config"
set data [get_data {more system:running-config}]

#get show commands output
puts "Grabbing COAT command show output"
set show_vtp [get_data {show vtp status}]
set show_ssh [get_data {show ip ssh}]
set show_log [get_data {show logging}]
#set show_log [get_data {show logging \| exclude \[0-9\]\[0-9\]:\[0-9\]\[0-9\]:\[0-9\]\[0-9]}]
set show_http [get_data {show ip http server status}]
set show_ntp [get_data {show ntp asso}]
set show_clock [get_data {show clock}]
set show_switchport [get_data {show interface switchport}]
set show_interfaces [get_data {show interfaces}]
set show_interface_st [get_data {show interface status}]
set show_version [get_data {show version}]
set show_span [get_data {show spanning-tree detail}]
set show_ether [get_data {show etherchannel port}]
set show_switch [get_data {show switch detail}]

#foreach item $show_vtp {
#  puts "show_vtp $item"
#}
#foreach item $show_ssh {
#  puts "show_ssh $item"
#}
#foreach item $show_log {
#  puts "show_log $item"
#}
#foreach item $show_http {
#  puts "show_http $item"
#}
#foreach item $show_ntp {
#  puts "show_ntp $item"
#}
#foreach item $show_clock {
#  puts "show_clock $item"
#}
#foreach item $show_switchport {
#  puts "show_switchport $item"
#}
#foreach item $show_interfaces {
#  puts "show_interfaces $item"
#}

puts "\n\n"

#********** Process each COAT check **********

#1.01
#manual test, log on via ssh and console, test tacacs authentication

#1.02
#Check SSH keys are 1024 bits
set testno "1.02"
set desc "Validate the crypto keys are a minimum of 1024 bits"
set value 0
set result 0
set value1 {}
#get ssh key string in single variable and test string length
set cmd_line_no [lsearch $show_ssh "ssh-rsa*"]
#grab the ssh key in do while loop, use counter to break out if ssh key maps out to exactly 80 chars like in a 4096 key
for {set counter 0} {$counter < 10} {incr counter} {
  append value1 [lindex $show_ssh $cmd_line_no] ;#add each ssh key line into value1
  if {[string length [lindex $show_ssh $cmd_line_no]] < 80} {
    break
  }
  incr cmd_line_no
}
#remove ssh key header text
regsub "ssh-rsa " $value1 "" value1
#rsa moulus 2048 = 372 characters 1024 = 204 characters 4096 = 712 characters
if {[string length $value1] == 372} {
  set result 1
  printoutput $testno $desc "SSH RSA key modulus 2048" $result
} elseif {[string length $value1] == 204} {
  printoutput $testno $desc "SSH RSA key modulus 1024" $result
} else  {
  printoutput $testno $desc $value $result
}
#check Diffie Helman keysize
set desc "SSH Diffie keys set to min size 2048"
set cmd_line_no [lsearch $show_ssh "*Diffie Hellman*"]
set cmd_line [lindex $show_ssh $cmd_line_no]
regexp {(2048)} $cmd_line value
if {$value == 2048} {
  set result 1
  printoutput $testno $desc $value $result
} else  {
  printoutput $testno $desc $value $result
}


#1.03
#Check if the password is encrypted
set testno "1.03"
set desc "Password Encryption Configured"
set regx "^service password-encryption$"
set value [lindex $data [lsearch -regexp $data $regx]]
set result 0
if {[string length $value] > 0} {
  set result 1q
  printoutput $testno $desc $value $result
} else {
  set value "$missing service password-encryption"
  printoutput $testno $desc $value $result
}


#1.04
#Check AAA servers are configured
set testno "1.04"
set desc "AAA Servers are Configured"
set value 0
set result 0
set tacserver {}
set tacserverip {}
set taccheck {}
set confpos [allsearch  $data {tacacs server}] ;# return all lines containing tacacs server new method
set oldconfpos [allsearch  $data {tacacs-server host}] ;# return all lines containing tacacs-server old method

#Cisco has two methods of configuring tacacs servers, old and new school, need
#to check for both as build guides, as always, are ambiguous

#check for new method
if {[llength $confpos] > 0} {
  #process each tacacs server
  foreach line $confpos {
    regexp -- {((\w|-)+)$} [lindex $data $line] tacserver   ;# Get tacacs server hostname
   # set tacserver [lindex $tacserv [expr [llength $tacserv] - 1]] ;# get hostname from stored list
    incr line ;#get next line in config
    while { [regexp {(tacacs server|\!)}  [lindex $data $line]] != 1 } { ;#parse tacacs section for address data
      if {[regexp address [lindex $data $line]] == 1} {
        regexp {(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})} [lindex $data $line] tacserverip ;# Get tacacs server ip address
        set value "$tacserver $tacserverip"
        append taccheck "$tacserverip " ;# Store IP address to check in next test
        set result 1
        printoutput $testno $desc $value $result
        break ;# process next host
      }
      incr line ;#get next line in config
    }
    if {$result == 0} {
      set value "$missing No IP configured for host $tacserver"
      printoutput $testno $desc $value $result
    }
    set result 0 ;#reset result counter
  }
} elseif {[llength $oldconfpos] > 0} { ;#Check for old school method
  #process each tacacs server
  foreach line $oldconfpos {
    regexp {(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})} [lindex $data $line] tacserverip ;# Get tacacs server ip address
    set value $tacserverip
    append taccheck "$tacserverip " ;# Store IP address to check in next test
    set result 1
    printoutput $testno $desc $value $result
  }
} else {
  set value "$missing No aaa servers configured"
  printoutput $testno $desc $value $result
}


#1.05a
#Check AAA servers are configured
set testno "1.05a"
set desc "TACACS timeout 3 seconds"
set value 0
set result 0
set timeout 0
set cmd_line {}
#search for global setting
set cmd_line [lindex $data [lsearch -regexp $data {^tacacs-server timeout}]]
if {[llength $cmd_line] > 0} {
  regexp {(\d+)} $cmd_line timeout
  if {$timeout == 3} {
    set value "Timeout is set to $timeout"
    set result 1
    printoutput $testno $desc $value $result
  } else {
    set value $cmd_line
    printoutput $testno $desc $value $result
  }
} else {
  set confpos [allsearch  $data {tacacs server}] ;#look for all configured tacacs servers
  if {[llength $confpos] > 0} {
    #process each tacacs server
    foreach line $confpos {
      regexp -- {((\w|-)+)$} [lindex $data $line] tacserver   ;# Get tacacs server hostname
      incr line ;#get next line in config
      while { [regexp {(tacacs server|\!)}  [lindex $data $line]] != 1 } { ;#parse tacacs section for address data
        if {[regexp {^\stimeout} [lindex $data $line]] == 1} {
          regexp {(\d+)} [lindex $data $line] line timeout ;#get timeout setting
          if {$timeout == 3} {
            set value "$tacserver timeout is set to $timeout"
            set result 1
            printoutput $testno $desc $value $result
          } else {
            set value "$tacserver timeout is set to $timeout"
            printoutput $testno $desc $value $result
          }
          break ;# process next host
        }
        incr line ;#get next line in config
      }
      set result 0 ;#reset result counter
    }
  }
}


#1.06
#Check only local user sso-admin is configured?
set testno "1.06"
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
set value 0
set result 0
set cmd_line_no [lsearch $show_ntp "*offset*"]
set line_check [expr $cmd_line_no + 1] ;#record header line plus 1
set cmd_line_no [expr $cmd_line_no + 1] ;# get next line number
set cmd_line [lindex $show_ntp $cmd_line_no] ;#get data on line x
while {[lsearch $cmd_line "*falseticker*"] == -1 && $cmd_line_no < 6} { ;#check for last line of ntp output
  if {[regexp {(\*|\+)\~\d+\.\d+\.\d+\.\d+\s} $cmd_line value]} { #IP address configured and in sync with ntp server
    set result 1
    printoutput $testno $desc $value $result
  } else { #IP address configured but not in sync with ntp server
    set result 0
    regexp {.\~\d+\.\d+\.\d+\.\d+\s} $cmd_line value
    printoutput $testno $desc $value $result
  }
  incr cmd_line_no  ;# get next line and data on that line
  set cmd_line [lindex $show_ntp $cmd_line_no]
}
if {$cmd_line_no == $line_check} {
  set result 0
  set value "$missing No ntp servers seem to be configured"
  printoutput $testno $desc $value $result
}

#2.02
#Interfaces show no errors
set testno "2.02"
set desc "No Interface Input/Output errors"
set value 0
set result 0
set error 0
set int_name {}
set limit [llength $show_interfaces]
set cmd_lines [allsearch $show_interfaces {^.[A-Za-z]+Ethernet[0-9]}]
#process each interface
foreach cmd_line_no $cmd_lines {
  #store interface name
  regexp {^([A-Za-z]+Ethernet[0-9]+[\/0-9]*)\s} [lindex $show_interfaces $cmd_line_no] int_name
  #increment lines until interface error line match
  while {[regexp {(\d+)\sinput errors} [lindex $show_interfaces $cmd_line_no] all port_mode] != 1 && $cmd_line_no < $limit} {
    incr cmd_line_no
  }
  #check interface input errors
  if {$port_mode != 0} {
    #errors found report the fact
    set value "$int_name: Input errors - $port_mode"
    printoutput $testno $desc $value $result
    set error 1
  }
  #check output errors
  while {[regexp {(\d+)\soutput errors} [lindex $show_interfaces $cmd_line_no] all port_mode] != 1 && $cmd_line_no < $limit} {
    incr cmd_line_no
  }
  if { $port_mode != 0} {
    #errors found report the fact
    set value "$int_name: Output errors - $port_mode"
    printoutput $testno $desc $value $result
    set error 1
  }
}
if {$error == 0} {
  set result 1
  set value "No Interface errors detected"
  printoutput $testno $desc $value $result
}

#2.03
#duplex mismatch (output interface status?)

#2.04
#Check clock UTC
set testno "2.04"
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

#2.05
#IOS version check - manual

#2.06
#Banner correct - Manual check
set testno "2.06"
set desc "Login banner configured"
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


#2.07
#Check ssh is version 2
set testno "2.07"
set desc "SSH set to Version 2"
set value 0
set result 0
if {[regexp {ip ssh version 2} $data]} {
  set result 1
  set value [lindex $data [lsearch $data {*ip ssh version 2*}]]
  printoutput $testno $desc $value $result
} else {
  printoutput $testno $desc $value $result
}


#2.08
#Check SSH timeout is set to 120 seconds
set testno "2.08"
set desc "SSH Timeout set to 120 seconds"
set value 0
set result 0
#set cmd_line with line value that matches *timeout* within the show ssh output
set cmd_line [lindex $show_ssh [lsearch $show_ssh "*timeout*"]]
#Check line for correct setting of 120 seconds
if {[regexp {(.*120 secs.*)} $cmd_line value]} {
  #match test pass set value to line in config
  set result 1
  printoutput $testno $desc $value $result
} else {
  #match test fail set value to line in config
  regexp -nocase {(.*timeout.*)} $cmd_line value
  printoutput $testno $desc $value $result
}

#2.09
#Telnet access not enabled
set testno "2.09"
set desc "Telnet disabled on vty lines"
set value 0
set value1 0
set result 0
#get line number of all vty line sections in config
set cmd_lines [allsearch $data "line vty*"]
if {[llength $cmd_lines] > 2 } {
   set value "VTY section is greater than 2, check vty config"
   printoutput $testno $desc $value $result
}
#process each vty sections
foreach cmd_line_no $cmd_lines {
   set vty [lindex $data $cmd_line_no]
   while 1 {
     set cmd_line_no [expr $cmd_line_no + 1]
     if {[regexp {(transport input ssh$)} [lindex $data $cmd_line_no] value1]} {
       set result 1
       set value "$vty -> $value1"
       printoutput $testno $desc $value $result
     } elseif {[regexp {(input (.*telnet.*|.*none.*))} [lindex $data $cmd_line_no] value1]} {
       set result 0
       set value "$vty -> $value1"
       printoutput $testno $desc $value $result
     }
     if {[regexp {line vty} [lindex $data $cmd_line_no]] || [regexp {!} [lindex $data $cmd_line_no]]} {
       break
     }
  }
}


#2.10
#VTY Timeout set to 9 minutes
set testno "2.10"
set desc "vty timeout set to 9 minutes"
set value 0
set value1 0
set result 0
set cmd_lines [allsearch $data "line vty"]
#process each vty sections
foreach cmd_line_no $cmd_lines {
  set vty [lindex $data $cmd_line_no]
  while 1 {
    set cmd_line_no [expr $cmd_line_no + 1]
    if {[regexp {(exec-timeout 9 0)} [lindex $data $cmd_line_no] value1]} {
      set result 1
      set value "$vty -> $value1"
      printoutput $testno $desc $value $result
    } elseif {[regexp {(exec-timeout [^9].*)} [lindex $data $cmd_line_no] value1]} {
      set result 0
      set value "$vty -> $value1"
      printoutput $testno $desc $value $result
      break
    }
    if {[regexp {line vty} [lindex $data $cmd_line_no]] || [regexp {!} [lindex $data $cmd_line_no]]} {
      break
    }
  }
}


#2.11
#Password not set on vty lines
set testno "2.11"
set desc "No Password set on VTY lines"
set value 0
set value1 0
set result 0
set cmd_lines [allsearch $data "line vty"]
#process each vty sections
foreach cmd_line_no $cmd_lines {
  set vty [lindex $data $cmd_line_no]
  while 1 {
    set cmd_line_no [expr $cmd_line_no + 1]
    if {[regexp {^(?!pass).$} [lindex $data $cmd_line_no]]} {
      set result 1
    } elseif {[regexp {(pass.*)} [lindex $data $cmd_line_no] value1]} {
      set result 0
      set value "$vty -> $value1"
      printoutput $testno $desc $value $result
      break
    }
    if {[regexp {line vty} [lindex $data $cmd_line_no]] || [regexp {!} [lindex $data $cmd_line_no]]} {
      break
    }
  }
  if {$result == 1} {
    set value "$vty -> No password found"
    printoutput $testno $desc $value $result
  }
}

#2.12
#VTY ACL applied
set testno "2.12"
set desc "VTY ACL applied"
set value 0
set value1 0
set result 0
set cmd_lines [allsearch $data "line vty*"]
#process each vty sections
foreach cmd_line_no $cmd_lines {
  set vty [lindex $data $cmd_line_no]
  while 1 {
    set cmd_line_no [expr $cmd_line_no + 1]
    if {[regexp {(access-class 102 in)} [lindex $data $cmd_line_no] value1]} {
      set result 1
      set value "$vty -> $value1"
      printoutput $testno $desc $value $result
      break
    } elseif {[regexp {(?!access-class)} [lindex $data $cmd_line_no]]} {
      set result 0
    }
    if {[regexp {line vty} [lindex $data $cmd_line_no]] || [regexp {!} [lindex $data $cmd_line_no]]} {
      break
    }
  }
  if {$result == 0 } {
    set value "$vty -> No ACL line found or acl does not match build guide acl of 102"
    printoutput $testno $desc $value $result
  }
}


#2.13
#Check http(s) server status
set testno "2.13"
set desc "HTTP server disabled"
set value 0
set result 0
set cmd_line [lindex  $show_http [lsearch $show_http "*HTTP server status*"]]
set cmd_line1 [lindex $show_http [lsearch $show_http "*HTTP secure server status*"]]
if {([regexp -nocase {http server status.*disabled} $cmd_line value])} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(.*http server status.*)} $cmd_line value
  printoutput $testno $desc $value $result
}
set desc "HTTPS server disabled"
if {([regexp -nocase {http secure server status.*disabled} $cmd_line1 value])} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(.*http secure server status.*)} $cmd_line1 value
  printoutput $testno $desc $value $result
}

#2.14
#Check domain name
set testno "2.14"
set desc "Domain name set to secure-ops.net"
set value 0
set result 0
if {[regexp {ip domain-name vodafone.com} $data]} {
  set result 1
  set value [lindex $data [lsearch $data {*ip domain-name*}]]
  printoutput $testno $desc $value $result
} else {
  set value [lindex $data [lsearch $data {*ip domain-name*}]]
  printoutput $testno $desc $value $result
}

#2.15
#Check dhcp disabled
set testno "2.15"
set desc "DHCP disabled"
set value 0
set result 0
set cmd_line [lindex $data [lsearch $data "*dhcp*"]]
if {[string length $cmd_line] == 0 || [string equal $cmd_line "no service dhcp"]} {
  set result 1
  set value $cmd_line
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(.*dhcp.*)} $cmd_line value
  printoutput $testno $desc $value $result
}

#2.16
#Check no ip source route
set testno "2.16"
set desc "Check IP source route disabled"
set value 0
set result 0
if {[regexp -nocase {(no ip source-route)} $data value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(ip source-route)} $data value
  printoutput $testno $desc $value $result
}

#2.17
#Vlan 1 shutdown
set testno "2.17"
set desc "Check VLAN 1 shutdown"
set value 0
set value1 0
set result 0
set cmd_line_no [lsearch $data "interface Vlan1"]
#loop lines following Vlan1 checking for shutdown
while 1 {
  set cmd_line_no [expr $cmd_line_no + 1]
  if {[regexp {shutdown} [lindex $data $cmd_line_no]]} {
    set result 1
    set value "Vlan 1 shutdown"
    printoutput $testno $desc $value $result
    break
  } elseif {[regexp {!} [lindex $data $cmd_line_no]]} {
    set result 0
    set value "Vlan1 is not shutdown"
    printoutput $testno $desc $value $result
    break
  }
}

#2.18
#Check vtp mode
set testno "2.18"
set desc "VTP mode set as transparent"
set value 0
set result 0
set cmd_line [lindex $show_vtp [lsearch $show_vtp "*\[Oo]perating \[Mm]ode*"]]
if {[regexp -nocase {(vtp operating mode.*transparent)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(vtp operating mode.*)} $cmd_line value
  printoutput $testno $desc $value $result
}

#2.19
#Domain lookup is disabled
set testno "2.19"
set desc "Domain lookup is disabled"
set value 0
set result 0
set cmd_line [lindex $data [lsearch $data "no ip domain-lookup"]]
if {[regexp -nocase {(no ip domain-lookup)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(.*domain-lookup.*)} $cmd_line value
  printoutput $testno $desc $value $result
}

#2.20
#IP subnet zero enabled
set testno "2.20"
set desc "ip subnet-zero is enabled"
set value 0
set result 0
set cmd_line [lindex $data [lsearch $data "*subnet-zero*"]]
if {[string length $cmd_line] == 0} {
  set result 1
  set value "ip subnet zero enabled"
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(.*subnet-zero.*)} $cmd_line value
  printoutput $testno $desc $value $result
}

#2.21
#Etherchannels between switches are set to ON
set testno "2.21"
set desc "Etherchanel mode is ON"
set value 0
set result 0
set port 0
set portmode 0
#get show etherchannel port size
set limit [llength $show_ether]
#get each line containing a port
set cmd_lines [allsearch $show_ether "^Port:"]
if {[llength $cmd_lines] > 0} {
#process each port
  foreach cmd_line_no $cmd_lines {
  #store interface name
    regexp {Port: (.*)} [lindex $show_ether $cmd_line_no] all port
    while {[regexp {Mode\s+=\s+(\w+)} [lindex $show_ether $cmd_line_no] all portmode] != 1 && $cmd_line_no < $limit} {
    incr cmd_line_no
    }
    set value "$port Mode: $portmode"
    if {[string equal $portmode "On"]} {
      set result 1
      printoutput $testno $desc $value $result
    } else {
      set result 0
      printoutput $testno $desc $value $result
    }
  }
} else {
  set value "No etherchannel config found"
}


#2.22
#Trunk native vlan 999
set testno "2.22"
set desc "Trunk native vlans set to 999"
set value 0
set result 0
set istrunk 0
set port_mode {}
set cmd_lines [allsearch $show_switchport "Name:*"]
set limit [llength $show_switchport]
#process each interface
foreach cmd_line_no $cmd_lines {
  #store interface name
  regexp {Name: (.*)} [lindex $show_switchport $cmd_line_no] all_match int_name
  #increment lines until admin mode match or all lines read. On match, store interface mode
  while {[regexp {Administrative Mode:\s+(\w+)} [lindex $show_switchport $cmd_line_no] all port_mode] != 1 && $cmd_line_no < $limit} {
    incr cmd_line_no
  }
  #check interface mode
  if {[string equal $port_mode "trunk"] == 0} {
    #its not a trunk get next interface
    continue
  }
  set istrunk 1 ;# trunk interface found record the fact
  #check next settings
  while {[regexp {Trunking Native Mode VLAN:\s+(\d+)} [lindex $show_switchport $cmd_line_no] all value] != 1 && $cmd_line_no < $limit} {
    incr cmd_line_no
  }
  if { $value == 999} {
    set result 1
    set value "$int_name: native VLAN $value"
    printoutput $testno $desc $value $result
    continue
  } else {
    set result 0
    set value "$int_name: native VLAN $value"
    printoutput $testno $desc $value $result
    continue
  }
}
if {$istrunk == 0} {
  set result 1
  set value "No trunk interfaces found"
  printoutput $testno $desc $value $result
}


#2.23
#Trunk ports not set to access vlan
set testno "2.23"
set desc "Access vlan not set on Trunk ports"
set value 0
set result 0
set cmd_lines [allsearch $show_switchport "Name:"]
#process each interface
foreach cmd_line_no $cmd_lines {
  #store interface name
  regexp {Name: (.*)} [lindex $show_switchport $cmd_line_no] all_match int_name
#increment lines until admin mode match or all lines read. On match, store interface mode
  while {[regexp {Administrative Mode:\s+(\w+)} [lindex $show_switchport $cmd_line_no] all port_mode] != 1 && $cmd_line_no < $limit} {
    incr cmd_line_no
  }
  #check interface mode
  if {[string equal $port_mode "trunk"] == 0} {
    #its not a trunk get next interface
    continue
  }
  set istrunk 1 ;# trunk interface found record the fact
  #check next settings
  while {[regexp {Access Mode VLAN:\s+(\d+)} [lindex $show_switchport $cmd_line_no] all value] != 1 && $cmd_line_no < $limit} {
    incr cmd_line_no
  }
  if { $value == 1} {
    set result 1
    set value "$int_name: No access vlan set"
    printoutput $testno $desc $value $result
    continue
  } else {
    set result 0
    set value "$int_name: access VLAN $value, remove access command"
    printoutput $testno $desc $value $result
    continue
  }
}
if {$istrunk == 0} {
  set result 1
  set value "No trunk interfaces found"
  printoutput $testno $desc $value $result
}


#3.01
#Check logging is enabled
set testno "3.01"
set desc "Logging is enabled"
set value 0
set result 0
set cmd_line [lindex $show_log [lsearch $show_log "*\[Ss]yslog \[Ll]ogging*"]]
if {[regexp -nocase {(syslog logging.*enabled)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(syslog logging.*)} $cmd_line value
  printoutput $testno $desc $value $result
}

#3.02
#Check timestamps are enabled
set testno "3.02"
set desc "Logging timestamps are enabled"
set value 0
set result 0
set cmd_line [lindex $show_log [lsearch $show_log "*timestamp*"]]
if {[regexp -nocase {(timestamp.*enabled)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  regexp -nocase {(timestamp.*)} $cmd_line value
  printoutput $testno $desc $value $result
}

#3.03
#Check console logging emergencies
set testno "3.03"
set desc "Logging console emergencies"
set value 0
set result 0
set cmd_line [lindex $show_log [lsearch $show_log "*\[Cc]onsole \[Ll]ogging*"]]
if {[regexp -nocase {(console logging.*level emergencies)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  printoutput $testno $desc $value $result
}

#3.04
#Check monitor logging disabled
set testno "3.04"
set desc "Logging monitor disabled"
set value 0
set result 0
set cmd_line [lindex $show_log [lsearch $show_log "*\[Mm]onitor \[Ll]ogging*"]]
if {[regexp -nocase {(monitor logging.*disabled)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  printoutput $testno $desc $value $result
}

#3.05
#Check buffer logging informational
set testno "3.05"
set desc "Logging buffer informational"
set value 0
set result 0
set cmd_line [lindex $show_log [lsearch $show_log "*\[Bb]uffer \[Ll]ogging*"]]
if {[regexp -nocase {(buffer logging.*informational)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  printoutput $testno $desc $value $result
}

#3.06
#Check trap logging informational
set testno "3.06"
set desc "Logging trap informational"
set value 0
set result 0
set cmd_line [lindex $show_log [lsearch $show_log "*\[Tt]rap \[Ll]ogging*"]]
if {[regexp -nocase {(trap logging.*informational)} $cmd_line value]} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  printoutput $testno $desc $value $result
}

#3.07
#logging to correct site, manual check possible auto

#3.08
#SNMP trap servers configured
set testno "3.08"
set desc "SNMP Trap servers configured"
set value 0
set result 0
set cmd_lines [allsearch $data "snmp-server host"]
if {[llength $cmd_lines] == 0} {
   set result 0
   set value "No SNMP trap servers configured"
   printoutput $testno $desc $value $result
} else {
  foreach cmd_line_no $cmd_lines {
    regexp {(snmp-server host \d+\.\d+\.\d+\.\d+)} [lindex $data $cmd_line_no] value
    set result 1
    printoutput $testno $desc $value $result
  }
}

#3.09
#Check snmp trap syslog
set testno "3.09"
set desc "SNMP traps to SYSLOG enabled"
set regx "^snmp-server enable traps syslog.*$"
set value [lindex $data [lsearch -regexp $data $regx]]
set result 0
if {[string length $value] > 0} {
  set result 1
  printoutput $testno $desc $value $result
} else {
  set value "Command not found"
  printoutput $testno $desc $value $result
}

#3.10
#Check snmp community not public
set testno "3.10"
set desc "SNMP not set to PUBLIC"
set value 0
set result 0
set regx "(?i)^snmp.*public.*$"
#search for case insensitive public in snmp commands
set value [lindex $data [lsearch -regexp $data $regx]]
if {[string length $value] > 0} {
  set result 0
  printoutput $testno $desc $value $result
} else {
  set result 1
  set value "No public string found in snmp settings"
  printoutput $testno $desc $value $result
}

#*********** Manual Check Output ************

puts "\n"
puts "The following are manual checks.\n"

#1.01
#manual test, log on via ssh and console, test tacacs authentication
set testno "1.01"
set desc "Log on via SSH and console, test tacacs+ authentication"
set output {}
set listtag 0
manual $testno $desc $output $listtag

#2.03
#duplex mismatch (output interface status?)
set testno "2.03"
set desc "Duplex missmatch, check output below"
set listtag 1
manual $testno $desc $show_interface_st $listtag


#2.05
#IOS version check - manual
set testno "2.05"
set desc "Check IOS version is as per current build software matrix"
set output {}
set output [lindex $show_version [lsearch $show_version "*Software*"]]
set listtag 0
manual $testno $desc $output $listtag


#2.06
#Banner correct - Manual check
set testno "2.06"
set desc "Check login banner correct. Config banner :-"
set output {}
set banner_cfg {}

#get existing banner if exists
set cmd_line [lsearch $data {*banner login*}]
if {$cmd_line > 0} {
  while {[regexp {^\^C$} [lindex $data $cmd_line]] == 0 && $count < 21} {
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

#3.11
#Check syslog for errors
set testno "3.11"
set desc "Check log for errors :-"
set output {}
set cmd_lines [allsearch $show_log "error"]
if {$cmd_line > 0} {
  foreach cmd_line $cmd_lines {
    lappend output [lindex $show_log $cmd_line]
  }
  set listtag 1
  manual $testno $desc $output $listtag
} else {
  set output "No errors found in syslog"
  manual $testno $desc $output $listtag
}

#4.01
#check switch stack
set testno "4.01"
set desc "Check switch stack working if stack set"
set output {}
set listtag 1
manual $testno $desc $show_switch $listtag

#4.02
#manual test, show serialnumber for cisco contract check
set testno "4.02"
set serial 0
set desc "Device is on valid cisco contract, run serial numbers :-"
set output {}
set cmd_lines [allsearch $show_version "System serial number"]
puts [llength $cmd_lines]
foreach cmd_line $cmd_lines {
  regexp {System serial number\s+:\s+(\w+)} $show_version all serial
  lappend output $serial
}
if {[llength $cmd_lines] > 1} {
  set listtag 1
} else {
  set listtag 0
}
manual $testno $desc $output $listtag


#2.26
#check channel mode is on, manual check - possible auto

#2.27
#check vlans on etherchannel, manual check

#2.28
#check vlans on trunks as dld, manual check


#*********** Logout of device *************
send "logout\r"
expect eof

exit 0
