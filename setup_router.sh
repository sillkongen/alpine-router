#!/bin/sh

# Alpine Router Setup Script
# This script configures an Alpine Linux system as a router with NAT, DHCP, and basic firewall rules
# Author: System Administrator
# Last Modified: $(date +%Y-%m-%d)

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Configuration
CONFIG_DIR="/etc/router-setup"
LAST_RUN_FILE="$CONFIG_DIR/last-run"
MAX_BACKUPS=5  # Keep only last 5 backups

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    error_exit "This script must be run as root"
fi

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Check if this is a rerun
if [ -f "$LAST_RUN_FILE" ]; then
    last_run=$(cat "$LAST_RUN_FILE")
    log "This appears to be a rerun. Last run was on: $last_run"
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Setup cancelled by user"
        exit 0
    fi
fi

# Cleanup old backups
cleanup_old_backups() {
    local file=$1
    local dir=$(dirname "$file")
    local base=$(basename "$file")
    # Keep only the last MAX_BACKUPS backups
    ls -t "${dir}/${base}.bak-"* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm
}

# Backup original configuration files
backup_file() {
    if [ -f "$1" ]; then
        local backup="${1}.bak-$(date +%Y%m%d%H%M%S)"
        cp "$1" "$backup"
        log "Backed up $1 to $backup"
        cleanup_old_backups "$1"
    fi
}

# Check for existing configuration
check_existing_config() {
    local services="dnsmasq chronyd iptables-load fail2ban"
    local configs="/etc/network/interfaces /etc/dnsmasq.conf /etc/chrony/chrony.conf /etc/iptables/rules"
    
    log "Checking existing configuration..."
    
    # Check services
    for service in $services; do
        if rc-update show | grep -q "$service.*default"; then
            log "Service $service is already configured in default runlevel"
        fi
    done
    
    # Check config files
    for config in $configs; do
        if [ -f "$config" ]; then
            log "Configuration file $config already exists"
        fi
    done
}

# Run the check
check_existing_config

# Check for required commands and install if missing
log "Checking and installing required packages..."
for pkg in iproute2 openrc procps syslog-ng chrony; do
    if ! apk info -e $pkg >/dev/null 2>&1; then
        log "Installing required package: $pkg"
        apk add $pkg || error_exit "Failed to install $pkg"
    fi
done

# Check for required commands
for cmd in apk sed iptables dnsmasq fail2ban ip sysctl; do
    if ! command -v $cmd >/dev/null 2>&1; then
        log "Installing required package for command: $cmd"
        case $cmd in
            ip) apk add iproute2 || error_exit "Failed to install iproute2" ;;
            sysctl) apk add procps || error_exit "Failed to install procps" ;;
            *) apk add $cmd || error_exit "Failed to install $cmd" ;;
        esac
    fi
done

log "Starting router setup..."

# Backup original configuration files
backup_file "/etc/apk/repositories"
backup_file "/etc/network/interfaces"
backup_file "/etc/dnsmasq.conf"
backup_file "/etc/sysctl.conf"

# Enable all repositories (main, community, testing)
log "Configuring repositories..."
sed -i 's/^#http/http/g' /etc/apk/repositories || error_exit "Failed to configure repositories"

# Update and install necessary tools
log "Updating package list and installing required packages..."
apk update || error_exit "Failed to update package list"
apk add iptables dnsmasq fail2ban || error_exit "Failed to install required packages"

# Configure Network Interfaces
log "Configuring network interfaces..."
cat << EOF > /etc/network/interfaces
# Loopback interface
auto lo
iface lo inet loopback

# WAN interface (external network)
auto eth0
iface eth0 inet dhcp
    # Add some basic hardening
    up ip link set eth0 mtu 1500
    up ip link set eth0 txqueuelen 1000

# LAN interface (internal network)
auto eth1
iface eth1 inet static
    address 10.0.0.1
    netmask 255.255.255.0
    # Add some basic hardening
    up ip link set eth1 mtu 1500
    up ip link set eth1 txqueuelen 1000
EOF

# Restart networking
log "Restarting networking service..."
/etc/init.d/networking restart || error_exit "Failed to restart networking"

# Configure dnsmasq for DHCP and DNS
log "Configuring dnsmasq..."
cat << EOF > /etc/dnsmasq.conf
# Interface to listen on
interface=eth1

# DHCP configuration
dhcp-range=10.0.0.10,10.0.0.100,12h
dhcp-option=option:router,10.0.0.1
dhcp-option=option:dns-server,1.1.1.1,8.8.8.8

# DNS configuration
no-resolv
no-poll
server=1.1.1.1
server=8.8.8.8
cache-size=1000
log-queries
log-facility=/var/log/dnsmasq.log

# Security options
no-hosts
expand-hosts
domain-needed
bogus-priv

# NTP server configuration
dhcp-option=option:ntp-server,10.0.0.1
EOF

# Create log file for dnsmasq
touch /var/log/dnsmasq.log
chmod 644 /var/log/dnsmasq.log

# Restart dnsmasq
log "Restarting dnsmasq service..."
/etc/init.d/dnsmasq restart || error_exit "Failed to restart dnsmasq"

# Enable IP forwarding and other network optimizations
log "Configuring kernel parameters..."
cat << EOF > /etc/sysctl.conf
# Enable IP forwarding
net.ipv4.ip_forward=1

# Security and performance optimizations
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=5
EOF

sysctl -p || error_exit "Failed to apply sysctl settings"

# Configure iptables
log "Configuring firewall rules..."

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -t mangle -F

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow LAN traffic
iptables -A INPUT -i eth1 -j ACCEPT
iptables -A OUTPUT -o eth1 -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Allow common services on LAN
iptables -A INPUT -p tcp -d 10.0.0.1 --dport 22 -j ACCEPT  # SSH
iptables -A INPUT -p tcp -d 10.0.0.1 --dport 53 -j ACCEPT  # DNS
iptables -A INPUT -p udp -d 10.0.0.1 --dport 53 -j ACCEPT  # DNS
iptables -A INPUT -p udp -d 10.0.0.1 --dport 67 -j ACCEPT  # DHCP
iptables -A INPUT -p udp -d 10.0.0.1 --dport 68 -j ACCEPT  # DHCP

# Allow ICMP (ping) on LAN
iptables -A INPUT -p icmp -i eth1 -j ACCEPT

# Allow NTP traffic
iptables -A INPUT -p udp --dport 123 -j ACCEPT  # NTP
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT  # NTP

# Configure logging for iptables
log "Setting up firewall logging..."
# Create log directory for iptables
mkdir -p /var/log/iptables
touch /var/log/iptables/wan-access.log
chmod 644 /var/log/iptables/wan-access.log

# Add logging rules before the default policies
iptables -N LOGGING
iptables -A LOGGING -j LOG --log-prefix "IPTables-Dropped: " --log-level 6
iptables -A LOGGING -j DROP

# Log WAN access attempts
iptables -A INPUT -i eth0 -j LOG --log-prefix "WAN-Access: " --log-level 6
iptables -A INPUT -i eth0 -j DROP  # Drop after logging

# Add logging to existing rules
iptables -A INPUT -i eth0 -p tcp --dport 22 -j LOG --log-prefix "WAN-SSH-Attempt: " --log-level 6
iptables -A INPUT -i eth0 -p tcp --dport 22 -j DROP

# Configure fail2ban for WAN monitoring
log "Configuring fail2ban for WAN monitoring..."
cat << EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

[wan-access]
enabled = true
filter = wan-access
logpath = /var/log/iptables/wan-access.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

# Create fail2ban filter for WAN access
cat << EOF > /etc/fail2ban/filter.d/wan-access.conf
[Definition]
failregex = WAN-Access: .* SRC=<HOST> .*
            WAN-SSH-Attempt: .* SRC=<HOST> .*
ignoreregex =
EOF

# Create logrotate configuration for iptables logs
cat << EOF > /etc/logrotate.d/iptables
/var/log/iptables/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

# Save iptables rules
log "Saving iptables rules..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules || error_exit "Failed to save iptables rules"

# Create OpenRC service for iptables
log "Creating iptables service..."
cat << EOF > /etc/init.d/iptables-load
#!/sbin/openrc-run

description="Load iptables rules"

depend() {
    need net
    after dnsmasq
}

start() {
    ebegin "Loading iptables rules"
    iptables-restore < /etc/iptables/rules
    eend $?
}

stop() {
    ebegin "Flushing iptables rules"
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    eend $?
}
EOF

chmod +x /etc/init.d/iptables-load
rc-update add iptables-load default

# Configure chronyd for time synchronization
log "Configuring time synchronization..."
cat << EOF > /etc/chrony/chrony.conf
# Use public NTP servers
pool pool.ntp.org iburst

# Allow LAN clients to sync time
allow 10.0.0.0/24

# Record the rate at which the system clock gains/losses time
driftfile /var/lib/chrony/drift

# Enable kernel synchronization of the real-time clock (RTC)
rtcsync

# Allow NTP client access from local network
local stratum 10

# Serve time even if not synchronized to a time source
local

# Specify file containing keys for NTP authentication
keyfile /etc/chrony/chrony.keys

# Specify directory for log files
logdir /var/log/chrony

# Select which information is logged
log measurements statistics tracking
EOF

# Create chrony log directory
mkdir -p /var/log/chrony
chown chrony:chrony /var/log/chrony

# Start and enable chronyd
rc-update add chronyd default
/etc/init.d/chronyd restart || error_exit "Failed to start chronyd"

# Add chronyd to iptables rules
log "Adding firewall rules for NTP..."
iptables -A INPUT -p udp --dport 123 -j ACCEPT  # NTP
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT  # NTP

# Save updated iptables rules
iptables-save > /etc/iptables/rules || error_exit "Failed to save iptables rules"

# Record this run
date '+%Y-%m-%d %H:%M:%S' > "$LAST_RUN_FILE"
log "Setup completed and recorded in $LAST_RUN_FILE"

log "Setup complete. Please reboot the system to apply all changes."
log "After reboot, check the following:"
log "1. Network connectivity on both interfaces"
log "2. DHCP server is working (try connecting a device)"
log "3. Internet access from LAN devices"
log "4. Check /var/log/dnsmasq.log for any DNS/DHCP issues"
log "5. Check /var/log/auth.log for any security issues"
log "6. Check /var/log/chrony/measurements.log for time sync status"
log "7. Check /var/log/iptables/wan-access.log for WAN access attempts"
log "8. Check /var/log/fail2ban.log for intrusion attempts"
