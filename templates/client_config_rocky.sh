#!/bin/bash

# Update system and install required packages for Rocky Linux
#
# You can modify this based upon your needs

# Enable the EPEL repository to ensure all packages are available

sudo dnf -y install epel-release

# Update all packages

sudo dnf -y upgrade

# Install required packages

sudo dnf install -y python3-pip git bc nfs-utils screen net-tools fio

# WARNING!!
# DO NOT MODIFY ANYTHING BELOW THIS LINE OR INSTANCES MAY NOT START CORRECTLY!
# ----------------------------------------------------------------------------

TARGET_USER="%[1]s"
TARGET_HOME="%[2]s"
SSH_KEYS="%[3]s"
TIER0="%[4]s"

# Get rid of fingerprint checking on ssh
# We need this in case somebody wants to run automated scripts. Otherwise,
# they will have to modify their scripts to answer the stupid question of
# "are you sure"?

sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

# Build NFS mountpoint

sudo mkdir -p /mnt/nfs-test
sudo chmod 777 /mnt/nfs-test

# SSH Key Management

if [ -n "$${SSH_KEYS}" ]; then
    mkdir -p "$${TARGET_HOME}/.ssh"
    chmod 700 "$${TARGET_HOME}/.ssh"
    touch "$${TARGET_HOME}/.ssh/authorized_keys"

    # Process keys one by one to avoid multi-line issues
    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "$${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$${key}" >> "$${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "$${TARGET_USER}:$${TARGET_USER}" "$${TARGET_HOME}/.ssh"
fi

# If Tier0 is enabled, then work on the nvme drives

if [ -n "${TIER0}" ]; then
    echo "Tier0 is enabled (${TIER0}). Installing mdadm & detecing NVMe..."

    # Load packages needed for Tier0

    echo "Loading Tier0 packages"
    sudo dnf install -y mdadm nvme-cli jq sysstat

    # Read each matching NVMe device into one array element per line
    
    mapfile -t NVME_DEVICES < <(
      nvme list | awk '/Amazon EC2 NVMe Instance Storage/ {print $1}'
    )
    echo "Found ${#NVME_DEVICES[@]} NVMe device(s): ${NVME_DEVICES[*]}"

    # If none, bail out cleanly

    if [ "${#NVME_DEVICES[@]}" -eq 0 ]; then
        echo "No NVMe instance-store devices found; skipping RAID creation."
        exit 0
    fi

    # Determine minimum count per RAID level

    case "${TIER0}" in
	raid-0)
	    MIN_REQUIRED=2
	    raid_options="--level=0 --raid-devices=${TOTAL_DEVICES}"
	    ;;
	raid-5)
	    MIN_REQUIRED=3
	    raid_options="--level=5 --raid-devices=${TOTAL_DEVICES}"
	    ;;
	raid-6)
	    MIN_REQUIRED=4
	    raid_options="--level=6 --raid-devices=${TOTAL_DEVICES}"
	    ;;
      *)
        echo "Error: Invalid TIER0 value '${TIER0}'." >&2
        exit 1
        ;;
    esac

    TOTAL_DEVICES="${#NVME_DEVICES[@]}"
    if [ "${TOTAL_DEVICES}" -lt "${MIN_REQUIRED}" ]; then
        echo "Error: Insufficient devices (${TOTAL_DEVICES}) for ${TIER0} (needs ≥${MIN_REQUIRED}). Skipping."
        exit 1
    fi

    # Build the RAID device

    RAID_NUM="${TIER0#raid-}"
    echo "Creating RAID${RAID_NUM} on ${TOTAL_DEVICES} devices…"
    sudo mdadm --create --verbose /dev/md0 \
	 ${raid_options} ${NVME_DEVICES[*]}

    # Format, mount, permissions

    sudo mkfs.xfs /dev/md0
    sudo mkdir -p /tier0
    sudo mount /dev/md0 /tier0
    sudo chown -R "${TARGET_USER}":"${TARGET_USER}" /tier0
    sudo chmod 777 /tier0

    # Persist in fstab & mdadm config

    echo "/dev/md0 /tier0 xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
    sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
    sudo update-initramfs -u

    # Configure NFS exports

    echo "/tier0 *(rw,sync,no_root_squash,secure,mp,no_subtree_check)" | sudo tee -a /etc/exports

    # Optimize NFS config

    sudo tee /etc/nfs.conf.d/local.conf > /dev/null <<'EOF'
[nfsd]
threads = 128
vers3=y
vers4.0=n
vers4.1=n
vers4.2=y
rdma=y
rdma-port=20049

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

else
    echo "Tier0 is not enabled on this machine"
fi

# Reboot

sudo reboot
