#!/bin/sh

# Alpine Linux USB Creator Script
# This script creates a bootable Alpine Linux USB image for router setup
# Author: System Administrator
# Last Modified: $(date +%Y-%m-%d)

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Default configuration
ALPINE_VERSION="3.19"  # Update this to match desired Alpine version
ALPINE_ARCH="x86_64"   # Architecture
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
DOWNLOAD_DIR="/tmp/alpine-usb"
MOUNT_DIR="/mnt/alpine-usb"
IMAGE_SIZE="2G"        # Size of the image file
ISO_PATH=""           # Will be set via command line argument

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Cleanup function
cleanup() {
    log "Running cleanup..."
    
    # Unmount any existing mounts in our mount points
    if mountpoint -q "$MOUNT_DIR"; then
        log "Unmounting $MOUNT_DIR..."
        umount -f "$MOUNT_DIR" 2>/dev/null || true
    fi
    
    if mountpoint -q "/mnt/iso"; then
        log "Unmounting /mnt/iso..."
        umount -f "/mnt/iso" 2>/dev/null || true
    fi
    
    # Detach all loop devices
    log "Detaching all loop devices..."
    for loop in $(losetup -a | cut -d: -f1); do
        log "Detaching loop device: $loop"
        losetup -d "$loop" 2>/dev/null || true
    done
    
    # Remove mount points if they exist
    [ -d "$MOUNT_DIR" ] && rmdir "$MOUNT_DIR" 2>/dev/null || true
    [ -d "/mnt/iso" ] && rmdir "/mnt/iso" 2>/dev/null || true
}

# Run cleanup on script exit
trap cleanup EXIT

# Usage function
usage() {
    echo "Usage: $0 --path <path_to_iso>"
    echo "Example: $0 --path ISOS/alpine-extended-3.21.3-x86_64.iso"
    echo ""
    echo "Options:"
    echo "  --path    Path to Alpine ISO file (relative to current directory)"
    echo "  --help    Show this help message"
    exit 1
}

# Parse command line arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        --path)
            ISO_PATH="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            log "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate ISO path
if [ -z "$ISO_PATH" ]; then
    error_exit "ISO path not provided. Use --path to specify the ISO file."
fi

# Convert relative path to absolute path
if [ ! "${ISO_PATH:0:1}" = "/" ]; then
    ISO_PATH="$(pwd)/$ISO_PATH"
fi

# Check if ISO file exists
if [ ! -f "$ISO_PATH" ]; then
    error_exit "ISO file not found: $ISO_PATH"
fi

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    error_exit "This script must be run as root"
fi

# Check for required commands and install if missing
log "Checking and installing required packages..."
for pkg in file util-linux e2fsprogs mount tar; do
    if ! apk info -e $pkg >/dev/null 2>&1; then
        log "Installing required package: $pkg"
        apk add $pkg || error_exit "Failed to install $pkg"
    fi
done

# Run initial cleanup
cleanup

# Create working directories
log "Creating working directories..."
mkdir -p "$DOWNLOAD_DIR" "$MOUNT_DIR" "/mnt/iso"

# Create image file
log "Creating image file..."
IMAGE_FILE="${DOWNLOAD_DIR}/alpine-router.img"
dd if=/dev/zero of="$IMAGE_FILE" bs=1 count=0 seek="$IMAGE_SIZE" || error_exit "Failed to create image file"

# Setup loop device
log "Setting up loop device..."
LOOP_DEV=$(losetup -f)
losetup "$LOOP_DEV" "$IMAGE_FILE" || error_exit "Failed to setup loop device"

# Create filesystem
log "Creating filesystem..."
echo "y" | mkfs.ext4 "$LOOP_DEV" || error_exit "Failed to create filesystem"

# Mount the image
log "Mounting image..."
if ! mount "$LOOP_DEV" "$MOUNT_DIR"; then
    error_exit "Failed to mount image to $MOUNT_DIR"
fi

# Verify mount
if ! mountpoint -q "$MOUNT_DIR"; then
    error_exit "Mount point $MOUNT_DIR is not mounted"
fi

# Create necessary directories in the image
log "Creating directory structure..."
mkdir -p "$MOUNT_DIR/etc" "$MOUNT_DIR/root" "$MOUNT_DIR/boot" || error_exit "Failed to create directory structure"

# Extract Alpine
log "Extracting Alpine Linux from $ISO_PATH..."

# Check ISO file type
log "Checking ISO file type..."
file_type=$(file -b "$ISO_PATH")
log "ISO file type: $file_type"

# Try different mount methods
log "Attempting to mount ISO..."
MOUNT_SUCCESS=false

# Method 1: Direct loop mount
if ! $MOUNT_SUCCESS; then
    log "Trying direct loop mount..."
    if mount -o loop "$ISO_PATH" /mnt/iso 2>/dev/null; then
        MOUNT_SUCCESS=true
        log "Direct loop mount successful"
    else
        log "Direct loop mount failed, trying alternative method..."
    fi
fi

# Method 2: Manual loop device setup
if ! $MOUNT_SUCCESS; then
    log "Trying manual loop device setup..."
    LOOP_ISO=$(losetup -f)
    if losetup "$LOOP_ISO" "$ISO_PATH"; then
        if mount "$LOOP_ISO" /mnt/iso 2>/dev/null; then
            MOUNT_SUCCESS=true
            log "Manual loop mount successful"
        else
            losetup -d "$LOOP_ISO"
            log "Manual loop mount failed"
        fi
    else
        log "Failed to setup loop device for ISO"
    fi
fi

# Method 3: Try with explicit filesystem type
if ! $MOUNT_SUCCESS; then
    log "Trying mount with explicit filesystem type..."
    if mount -t iso9660 -o loop "$ISO_PATH" /mnt/iso 2>/dev/null; then
        MOUNT_SUCCESS=true
        log "ISO9660 mount successful"
    else
        log "ISO9660 mount failed"
    fi
fi

# Check if any mount method succeeded
if ! $MOUNT_SUCCESS; then
    # Additional debugging information
    log "Mount failed. Debugging information:"
    log "ISO file size: $(du -h "$ISO_PATH" | cut -f1)"
    log "Available loop devices:"
    losetup -a
    log "Mount points:"
    mount | grep loop
    error_exit "Failed to mount ISO after multiple attempts. Please check if the ISO file is valid."
fi

# Verify ISO mount
if ! mountpoint -q "/mnt/iso"; then
    error_exit "ISO mount point /mnt/iso is not mounted"
fi

# Copy files from mounted ISO
log "Copying files from mounted ISO..."
if ! cp -a /mnt/iso/* "$MOUNT_DIR/"; then
    log "Failed to copy files. Debugging information:"
    log "ISO mount point contents:"
    ls -la /mnt/iso
    log "Target directory contents:"
    ls -la "$MOUNT_DIR"
    error_exit "Failed to copy files from ISO"
fi

# Verify essential directories exist
log "Verifying directory structure..."
for dir in "$MOUNT_DIR/etc" "$MOUNT_DIR/root" "$MOUNT_DIR/boot"; do
    if [ ! -d "$dir" ]; then
        error_exit "Required directory $dir does not exist after copy"
    fi
done

# Create fstab
log "Creating fstab..."
if [ ! -d "$MOUNT_DIR/etc" ]; then
    error_exit "Directory $MOUNT_DIR/etc does not exist"
fi

cat << EOF > "$MOUNT_DIR/etc/fstab"
# <file system> <mount point> <type> <options> <dump> <pass>
/dev/sda1 / ext4 defaults,noatime 0 1
EOF

# Create boot configuration
log "Configuring boot..."
if [ ! -d "$MOUNT_DIR/etc" ]; then
    error_exit "Directory $MOUNT_DIR/etc does not exist"
fi

cat << EOF > "$MOUNT_DIR/etc/update-extlinux.conf"
default_kernel_opts="quiet root=/dev/sda1 modules=sd-mod,usb-storage,ext4 nomodeset"
EOF

# Copy router setup script
log "Copying router setup script..."
if [ ! -d "$MOUNT_DIR/root" ]; then
    error_exit "Directory $MOUNT_DIR/root does not exist"
fi

cp setup_router.sh "$MOUNT_DIR/root/" || error_exit "Failed to copy setup script"
chmod +x "$MOUNT_DIR/root/setup_router.sh"

# Create firstboot script directory if it doesn't exist
log "Creating firstboot script..."
if [ ! -d "$MOUNT_DIR/etc/local.d" ]; then
    mkdir -p "$MOUNT_DIR/etc/local.d" || error_exit "Failed to create local.d directory"
fi

# Create network configuration
log "Configuring network..."
if [ ! -d "$MOUNT_DIR/etc/network" ]; then
    mkdir -p "$MOUNT_DIR/etc/network" || error_exit "Failed to create network directory"
fi

# Configure eth0 for DHCP
cat << 'EOF' > "$MOUNT_DIR/etc/network/interfaces"
# Network interface configuration
auto lo
iface lo inet loopback

# WAN interface (eth0) - DHCP client
auto eth0
iface eth0 inet dhcp
    hostname alpine-router

# LAN interface (eth1) - Will be configured by setup_router.sh
auto eth1
iface eth1 inet static
    address 192.168.1.1
    netmask 255.255.255.0
EOF

# Enable and configure SSH
log "Configuring SSH..."
if [ ! -d "$MOUNT_DIR/etc/ssh" ]; then
    mkdir -p "$MOUNT_DIR/etc/ssh" || error_exit "Failed to create SSH directory"
fi

# Generate SSH host keys if they don't exist
if [ ! -f "$MOUNT_DIR/etc/ssh/ssh_host_rsa_key" ]; then
    log "Generating SSH host keys..."
    ssh-keygen -t rsa -f "$MOUNT_DIR/etc/ssh/ssh_host_rsa_key" -N "" || error_exit "Failed to generate RSA key"
    ssh-keygen -t ecdsa -f "$MOUNT_DIR/etc/ssh/ssh_host_ecdsa_key" -N "" || error_exit "Failed to generate ECDSA key"
    ssh-keygen -t ed25519 -f "$MOUNT_DIR/etc/ssh/ssh_host_ed25519_key" -N "" || error_exit "Failed to generate ED25519 key"
fi

# Configure SSH
cat << 'EOF' > "$MOUNT_DIR/etc/ssh/sshd_config"
# SSH Server Configuration
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no

# Security
LoginGraceTime 60
MaxAuthTries 3
MaxSessions 10

# Logging
SyslogFacility AUTH
LogLevel INFO

# Other
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/ssh/sftp-server
EOF

# Update firstboot script to enable and start SSH
log "Updating firstboot script..."
cat << 'EOF' > "$MOUNT_DIR/etc/local.d/firstboot.start"
#!/bin/sh

# First boot configuration
if [ ! -f /etc/firstboot.done ]; then
    # Update system
    apk update
    apk upgrade

    # Install required packages
    apk add git openssh-server

    # Enable and start SSH
    rc-update add sshd default
    /etc/init.d/sshd start

    # Clone router repository
    cd /root
    git clone https://github.com/yourusername/alpine-router.git
    cd alpine-router

    # Run setup script
    ./setup_router.sh

    # Set root password (change this in production!)
    echo "root:alpine" | chpasswd

    # Mark firstboot as done
    touch /etc/firstboot.done

    # Print network information
    echo "================================================"
    echo "Router setup complete!"
    echo "SSH is enabled and accessible on eth0"
    echo "Default root password: alpine"
    echo "Please change the root password immediately!"
    echo "================================================"
fi
EOF

chmod +x "$MOUNT_DIR/etc/local.d/firstboot.start"

# Add network service to default runlevel
log "Configuring network services..."
if [ ! -d "$MOUNT_DIR/etc/runlevels/default" ]; then
    mkdir -p "$MOUNT_DIR/etc/runlevels/default" || error_exit "Failed to create runlevels directory"
fi

# Create network service symlinks
ln -sf /etc/init.d/networking "$MOUNT_DIR/etc/runlevels/default/networking" || error_exit "Failed to create networking service symlink"
ln -sf /etc/init.d/sshd "$MOUNT_DIR/etc/runlevels/default/sshd" || error_exit "Failed to create sshd service symlink"

# Cleanup
log "Cleaning up..."
umount "$MOUNT_DIR" || error_exit "Failed to unmount image"
losetup -d "$LOOP_DEV" || error_exit "Failed to detach loop device"

# Create final image
log "Creating final image..."
gzip -c "$IMAGE_FILE" > "${IMAGE_FILE}.gz" || error_exit "Failed to compress image"

# Print instructions
log "Image creation complete!"
log "Image file: ${IMAGE_FILE}.gz"
log ""
log "To write the image to a USB drive:"
log "1. Insert your USB drive"
log "2. Find your USB device (e.g., /dev/sdb) using 'lsblk'"
log "3. Run: gunzip -c ${IMAGE_FILE}.gz | dd of=/dev/sdX bs=4M status=progress"
log "   (Replace sdX with your USB device, e.g., sdb)"
log ""
log "WARNING: Make sure to use the correct device name to avoid overwriting your system disk!"
log ""
log "After writing to USB:"
log "1. Insert the USB drive into your router hardware"
log "2. Boot from the USB drive"
log "3. The system will automatically run the router setup on first boot"
log "4. After setup completes, you can remove the USB drive and boot from the installed system"

# Cleanup temporary files
rm -rf "$DOWNLOAD_DIR" "$MOUNT_DIR" 