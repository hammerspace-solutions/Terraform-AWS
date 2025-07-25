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

TARGET_USER="%[1]s"
TARGET_HOME="%[2]s"
SSH_KEYS="%[3]s"

# Get rid of fingerprint checking on ssh
# We need this in case somebody wants to run automated scripts. Otherwise,
# they will have to modify their scripts to answer the stupid question of
# "are you sure"?

sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

# SSH Key Management

if [ -n "${SSH_KEYS}" ]; then
    mkdir -p "${TARGET_HOME}"/.ssh
    chmod 700 "${TARGET_HOME}"/.ssh
    touch "${TARGET_HOME}"/.ssh/authorized_keys
    
    # Process keys one by one to avoid multi-line issues

    echo "${SSH_KEYS}" | while read -r key; do
        if [ -n "${key}" ] && ! grep -qF "${key}" "${TARGET_HOME}"/.ssh/authorized_keys; then
            echo "${key}" >> "${TARGET_HOME}"/.ssh/authorized_keys
        fi
    done

    chmod 600 "${TARGET_HOME}"/.ssh/authorized_keys
    chown -R "${TARGET_USER}":"${TARGET_USER}" "${TARGET_HOME}"/.ssh
fi

# Reboot
sudo reboot
