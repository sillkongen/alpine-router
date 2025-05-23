# Alpine Router

A secure and feature-rich router setup for Alpine Linux, providing NAT, DHCP, DNS, time synchronization, and firewall protection.

## Features

- **Network Configuration**
  - WAN interface (eth0) with DHCP
  - LAN interface (eth1) with static IP (10.0.0.1/24)
  - NAT for internet sharing
  - Network interface hardening

- **DHCP Server**
  - Automatic IP assignment (10.0.0.10 - 10.0.0.100)
  - DNS server advertisement
  - NTP server advertisement
  - 12-hour lease time

- **DNS Server**
  - Local DNS caching
  - Forwarding to Cloudflare (1.1.1.1) and Google (8.8.8.8)
  - Security features enabled
  - Query logging

- **Time Synchronization**
  - Local NTP server (chronyd)
  - Serves time to LAN clients
  - Fallback to local time if internet unavailable
  - Detailed logging

- **Security Features**
  - Stateful firewall (iptables)
  - Intrusion prevention (fail2ban)
  - SSH protection
  - Network hardening
  - Kernel security parameters

## Requirements

- Alpine Linux installation
- Two network interfaces:
  - eth0: WAN (external network)
  - eth1: LAN (internal network)
- Root access
- Internet connection for initial setup

## Installation

### Option 1: Direct Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/alpine-router.git
   cd alpine-router
   ```

2. Make the setup script executable:
   ```bash
   chmod +x setup_router.sh
   ```

3. Run the setup script:
   ```bash
   ./setup_router.sh
   ```

### Option 2: Bootable USB Image

For a complete automated installation, you can create a bootable USB image:

1. Make the USB creator script executable:
   ```bash
   chmod +x create_alpine_usb.sh
   ```

2. Run the USB creator script:
   ```bash
   sudo ./create_alpine_usb.sh
   ```

3. Write the image to a USB drive:
   ```bash
   # First, find your USB device
   lsblk
   
   # Then write the image (replace sdX with your USB device)
   gunzip -c /tmp/alpine-usb/alpine-router.img.gz | sudo dd of=/dev/sdX bs=4M status=progress
   ```

4. Boot from the USB drive on your router hardware

The USB image includes:
- Alpine Linux Extended Edition
- Automatic first-boot configuration
- Router setup script
- All necessary packages
- Pre-configured boot parameters

The system will automatically:
1. Boot from the USB drive
2. Update the system
3. Clone the router repository
4. Run the setup script
5. Configure the router

After the first boot completes, you can:
1. Remove the USB drive
2. Boot from the installed system
3. The router will be fully configured and ready to use

The script will:
- Install required packages
- Configure network interfaces
- Set up DHCP and DNS
- Configure firewall rules
- Set up time synchronization
- Enable security features

## Configuration Files

The setup script creates/updates the following configuration files:
- `/etc/network/interfaces` - Network interface configuration
- `/etc/dnsmasq.conf` - DHCP and DNS server configuration
- `/etc/chrony/chrony.conf` - Time synchronization
- `/etc/iptables/rules` - Firewall rules
- `/etc/fail2ban/jail.local` - Intrusion prevention

All original configuration files are backed up with timestamps before modification.

## Services

The following services are installed and configured:
- `dnsmasq` - DHCP and DNS server
- `chronyd` - Time synchronization
- `iptables-load` - Firewall rules
- `fail2ban` - Intrusion prevention

All services are added to the default runlevel and will start automatically on boot.

## Network Layout

```
[Internet] <---> [eth0: WAN (DHCP)] <---> [Router] <---> [eth1: LAN (10.0.0.1/24)] <---> [Local Network]
```

## Default Settings

- LAN Network: 10.0.0.0/24
- Router IP: 10.0.0.1
- DHCP Range: 10.0.0.10 - 10.0.0.100
- DNS Servers: 1.1.1.1, 8.8.8.8
- NTP Server: pool.ntp.org
- SSH Access: Enabled on 10.0.0.1:22

## Maintenance

### Rerunning the Setup

The setup script can be safely rerun. It will:
- Detect previous runs
- Ask for confirmation
- Create new backups
- Clean up old backups (keeps last 5)
- Update configurations as needed

### Logs

Important log files:
- `/var/log/dnsmasq.log` - DHCP and DNS logs
- `/var/log/auth.log` - Authentication and security logs
- `/var/log/chrony/measurements.log` - Time synchronization logs
- `/var/log/fail2ban.log` - Intrusion prevention logs

### Backup Files

Configuration backups are stored with timestamps:
- `*.bak-YYYYMMDDHHMMSS`

## Security Notes

- The router uses a default-deny firewall policy
- SSH access is restricted to the LAN interface
- fail2ban protects against brute force attacks
- Network interfaces are hardened
- Kernel security parameters are optimized
- WAN access attempts are logged and monitored
- Automatic IP banning for suspicious WAN activity

## Logging

The router maintains several log files for monitoring and security:

### Security Logs
- `/var/log/iptables/wan-access.log` - Logs all WAN interface access attempts
- `/var/log/auth.log` - Authentication and SSH access logs
- `/var/log/fail2ban.log` - Intrusion prevention and IP banning logs

### Service Logs
- `/var/log/dnsmasq.log` - DHCP and DNS server logs
- `/var/log/chrony/measurements.log` - Time synchronization logs

### Log Rotation
- All logs are automatically rotated daily
- Keeps 7 days of compressed logs
- Iptables logs are specifically monitored for WAN access attempts

### Monitoring WAN Access
To monitor WAN access attempts:
```bash
# View recent WAN access attempts
tail -f /var/log/iptables/wan-access.log

# View banned IPs
fail2ban-client status wan-access

# View all firewall logs
iptables -L -v -n
```

## Troubleshooting

1. Check network connectivity:
   ```bash
   ip addr show
   ping 10.0.0.1
   ```

2. Check DHCP server:
   ```bash
   cat /var/log/dnsmasq.log
   ```

3. Check time synchronization:
   ```bash
   chronyc sources
   chronyc tracking
   ```

4. Check firewall rules:
   ```bash
   iptables -L -v -n
   iptables -t nat -L -v -n
   ```

5. Check fail2ban status:
   ```bash
   fail2ban-client status
   ```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
