check_lsi_raid
==============

Icinga/Nagios module(s) for LSI RAID controller checks

check_lsi_battery.rb 

A Ruby script that checks the state of LSI RAID controller batteries and outputs in Icinga/Nagios plugin compatible format.

The script requires either MegaCLI(64) or strorctl(64) command line tools to be installed, which can be obtained from the LSI web site. The script tries to find the tools at different default locations. If the tools is not found, the location can easily be added to the list.

Run 

./check_lsi_battery.rb -h 

for a list of options.  

