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

TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
SSH_KEYS="${SSH_KEYS}"

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

# Upgrade software and reboot

sudo dnf -y upgrade
sudo reboot
