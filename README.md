# alpine-router
Setup a simple LAN router on a PC quickly with this script + Alpine.

## Requirements
Install alpine with "setup-alpine"

Reboot, do apk update

'''apk add git'''

Then do git clone https://github.com/sillkongen/alpine-router.git

Then cd alpine-router

Then run sh setup_router.sh

eth1 is your WAN port request an IP address via DHCP
eth2 is your LAN port. 
 - LAN Network will be on 10.0.0.0&24
 - DNS will be 1.1.1.1 and 8.8.8.8
 - There will be a firewall opening on LAN for port 22 to control the router
TODO
Figure out to scan for network devices
