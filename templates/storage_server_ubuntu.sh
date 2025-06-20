#!/bin/bash

# Update and install required packages
#
# You can modify this based upon your needs

sudo apt update
sudo apt install -y net-tools nfs-common nfs-kernel-server sysstat mdadm

# Upgrade all installed packages to their latest versions
sudo apt-get -y upgrade

# WARNING!!
# DO NOT MODIFY ANYTHING BELOW THIS LINE OR INSTANCES MAY NOT START CORRECTLY!
# ----------------------------------------------------------------------------

# Terraform-provided variables (single $ for Terraform interpolation)

SSH_KEYS="${SSH_KEYS}"
TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
EBS_COUNT="${EBS_COUNT}"
RAID_LEVEL="${RAID_LEVEL}"  # raid-0, raid-5, or raid-6

# Enable strict mode for better error handling

set -euo pipefail
shopt -s failglob

# Define minimum devices required for each RAID level ($$ for shell variables)

case "$${RAID_LEVEL}" in
  "raid-0") MIN_DEVICES=2 ;;
  "raid-5") MIN_DEVICES=3 ;;
  "raid-6") MIN_DEVICES=4 ;;
  *)
    echo "ERROR: Invalid RAID level '$${RAID_LEVEL}' (must be raid-0, raid-5, or raid-6)"
    exit 1
    ;;
esac

# Validate EBS_COUNT meets RAID requirements before proceeding

if [ "$${EBS_COUNT}" -lt "$${MIN_DEVICES}" ]; then
    echo "ERROR: Configuration mismatch - RAID-$${RAID_LEVEL#raid-} requires at least $${MIN_DEVICES} devices, but EBS_COUNT=$${EBS_COUNT}"
    exit 1
fi

# Wait for exactly EBS_COUNT NVMe devices

echo "Waiting for $${EBS_COUNT} NVMe devices (RAID-$${RAID_LEVEL#raid-} requires minimum $${MIN_DEVICES})"
while [ $(ls /dev/nvme[0-9]n[0-9] 2>/dev/null | wc -l) -lt "$${EBS_COUNT}" ]; do
    sleep 5
    echo "Found $(ls /dev/nvme[0-9]n[0-9] 2>/dev/null | wc -l) of $${EBS_COUNT} devices..."
done

# Function to get the physical device behind a mounted filesystem

get_physical_device() {
    local mount_point="$${1}"
    local device=$(findmnt -n -o SOURCE --target "$${mount_point}")

    # Handle LVM and partition cases
    if [[ "$${device}" =~ ^/dev/mapper/ ]]; then
        # LVM device - get underlying physical volume
        device=$(sudo lvdisplay --noheading -C -o "lv_dm_path" "$${device}" | tr -d ' ')
    elif [[ "$${device}" =~ ^/dev/nvme[0-9]+n[0-9]+p[0-9]+$ ]]; then
        # NVMe partition - get the whole device
        device=$${device%p[0-9]*}
    fi

    echo "$${device}"
}

# Identify boot device

BOOT_DEVICE=$(get_physical_device "/")

# Get all NVMe devices (whole devices, not partitions)

ALL_NVME_DEVICES=($(ls /dev/nvme[0-9]n[0-9] | sort))

# Filter out the boot device

RAID_DEVICES=()
for dev in "$${ALL_NVME_DEVICES[@]}"; do
    if [[ "$${dev}" != "$${BOOT_DEVICE}" ]]; then
        RAID_DEVICES+=("$${dev}")
    fi
done

# Final device count validation

if [ $${#RAID_DEVICES[@]} -ne "$${EBS_COUNT}" ]; then
    echo "ERROR: Device count mismatch - expected $${EBS_COUNT} non-boot devices, found $${#RAID_DEVICES[@]}"
    echo "Boot device: $${BOOT_DEVICE}"
    echo "All NVMe devices: $${ALL_NVME_DEVICES[@]}"
    echo "Available for RAID: $${RAID_DEVICES[@]}"
    exit 1
fi

# Build RAID array based on level

case "$${RAID_LEVEL}" in
  "raid-0")
    raid_options="--level=0 --raid-devices=$${EBS_COUNT}"
    ;;
  "raid-5")
    raid_options="--level=5 --raid-devices=$${EBS_COUNT}"
    ;;
  "raid-6")
    raid_options="--level=6 --raid-devices=$${EBS_COUNT}"
    ;;
esac

echo "Creating $${RAID_LEVEL} array with $${EBS_COUNT} devices: $${RAID_DEVICES[@]}"

sudo mdadm --create --verbose /dev/md0 \
    $${raid_options} \
    "$${RAID_DEVICES[@]}"

# Create filesystem

sudo mkfs -t xfs /dev/md0

# Create mountpoint

sudo mkdir /hsvol1

# Add to fstab

echo "/dev/md0 /hsvol1 xfs defaults,nofail,discard 0 0" | sudo tee -a /etc/fstab

# Mount filesystem

sudo mount /hsvol1

# Set permissions

sudo chmod 777 /hsvol1

# Configure NFS exports

echo "/hsvol1 *(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports

# Optimize NFS config

sudo tee /etc/nfs.conf.d/local.conf > /dev/null <<'EOF'
[nfsd]
threads = 128

[mountd]
manage-gids = 1
EOF

# Increase NFS threads

sudo tee /etc/default/nfs-kernel-server > /dev/null <<'EOF'
RPCNFSDCOUNT=128
RPCMOUNTDOPTS="--manage-gids"
EOF

# Start services

sudo systemctl restart nfs-kernel-server

# SSH Key Management

if [ -n "$${SSH_KEYS}" ]; then
    mkdir -p "$${TARGET_HOME}/.ssh"
    chmod 700 "$${TARGET_HOME}/.ssh"
    touch "$${TARGET_HOME}/.ssh/authorized_keys"

    # Process keys line by line
    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "$${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$${key}" >> "$${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "$${TARGET_USER}:$${TARGET_USER}" "$${TARGET_HOME}/.ssh"
fi

# Verify RAID

echo "RAID array created successfully:"
sudo mdadm --detail /dev/md0

# Final reboot to apply all changes
echo "Rebooting now..."
sudo reboot
