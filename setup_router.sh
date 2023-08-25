#!/bin/sh

# Enable all repositories (main, community, testing)
sed -i 's/^#http/http/g' /etc/apk/repositories

# Update and install necessary tools
apk update
apk add iptables dnsmasq

# Configure Network Interfaces
cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto eth1
iface eth1 inet dhcp

auto eth2
iface eth2 inet static
    address 10.0.0.1
    netmask 255.255.255.0
EOF

# Restart networking
/etc/init.d/networking restart

# Configure dnsmasq for DHCP and DNS
cat << EOF > /etc/dnsmasq.conf
interface=eth2
dhcp-range=10.0.0.10,10.0.0.100,12h
dhcp-option=option:router,10.0.0.1
dhcp-option=option:dns-server,1.1.1.1,8.8.8.8
EOF

# Restart dnsmasq
/etc/init.d/dnsmasq restart

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.conf
sysctl -p

# Default iptables policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow LAN traffic
iptables -A INPUT -i eth2 -j ACCEPT
iptables -A OUTPUT -o eth2 -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# NAT
iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# Allow SSH on 10.0.0.1
iptables -A INPUT -p tcp -d 10.0.0.1 --dport 22 -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables/rules

# Create OpenRC service for iptables
cat << EOF > /etc/init.d/iptables-load
#!/sbin/openrc-run

description="Load iptables rules"

start() {
    ebegin "Loading iptables rules"
    iptables-restore < /etc/iptables/rules
    eend $?
}
EOF

chmod +x /etc/init.d/iptables-load
rc-update add iptables-load default

echo "Setup complete. Please reboot."
