#!/bin/bash

# Update system and install required packages
#
# You can modify this based upon your needs

sudo apt-get -y update
sudo apt-get install -y pip git bc nfs-common screen net-tools fio

# Upgrade all the installed packages

sudo apt-get -y upgrade

# WARNING!!
# DO NOT MODIFY ANYTHING BELOW THIS LINE OR INSTANCES MAY NOT START CORRECTLY!
# ----------------------------------------------------------------------------

TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
SSH_KEYS="${SSH_KEYS}"
TIER0="${TIER0}"

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

if [ -n "$${TIER0}" ]; then
    echo "Tier0 is enabled. Try to configure devices"
    
    sudo apt -y update && apt -y install -y mdadm nvme-cli jq

    NVME_DEVICES=($(nvme list | grep "Amazon EC2 NVMe Instance Storage" | awk '{print $1}'))
    if [ $($NVME_DEVICES[@]) -eq 0]; then
	echo "Error: No NVMe instance store devices found. Skipping RAID creation"
    else

	case "${TIER0}" in
	    "raid-0") MIN_REQUIRED=1 ;;
	    "raid-5") MIN_REQUIRED=3 ;;
	    "raid-6") MIN_REQUIRED=4 ;;
	    *) echo "Error: Invalid TIER0 value '${TIER0}'." >&2; exit 1 ;;
	esac
    fi

    # Make sure that we have enough drives for the type of raid they want

    TOTAL_DEVICES="${#NVME_DEVICES[@]}"

    if [ "${TOTAL_DEVICES}" -lt "${MIN_REQUIRED}" ]; then
	echo 'Error: Insufficent devices ("${TOTAL_DEVICES}") for "${TIER0}" (needs at least "${MIN_REQUIRED}"). skipping RAID creation.'
    else
	RAID_NUM="{TIER0#raid-}"

	# Build the raid

	sudo mdadm --create --verbose /dev/md0 --level="${RAID_NUM}" --raid-devices="${TOTAL_DEVICES}" "${NVME_DEVICES[@]}"

	# Create the filesystem

	sudo mkfs -t xfs /dev/md0

	# Create and mount the filesystem

	sudo mkdir /tier0
	sudo mount /dev/md0 /tier0
	sudo chown -R ${TARGET_UDSER}:${TARGET_USER} /tier0
	sudo chmod 777 /tier0

	# Add filesystem to fstab

	echo "/dev/md0 /tier0 xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab

	# Save mdadm config and update initramfs

	sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
	sudo update-initramfs -u
    fi
fi

# Reboot
sudo reboot
