#!/bin/bash

# Variable placeholders - replaced by Terraform templatefile function

TARGET_USER='${TARGET_USER}'
TARGET_HOME='${TARGET_HOME}'
SSH_KEYS='${SSH_KEYS}'

# Other variables

PRIVATE_KEY_FILE="/home/ubuntu/.ssh/ansible_admin_key"

# --- Script ---

set -euo pipefail

# --- Package Installation ---

sudo apt-get -y update
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible jq net-tools

echo "Upgrade the OS to make sure we have the latest"
sudo apt-get -y upgrade

# Get rid of fingerprint checking on ssh
# We need this in case somebody wants to run automated scripts. Otherwise,
# they will have to modify their scripts to answer the stupid question of
# "are you sure"?

sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

# --- SSH Key Management for additional keys ---

if [ -n "$${SSH_KEYS}" ]; then

    echo "Starting SSH Key Management Deployment"
    mkdir -p "$${TARGET_HOME}/.ssh"
    chmod 700 "$${TARGET_HOME}/.ssh"
    touch "$${TARGET_HOME}/.ssh/authorized_keys"
    
    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "$${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$${key}" >> "$${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "$${TARGET_USER}:$${TARGET_USER}" "$${TARGET_HOME}/.ssh"
    echo "Ending SSH Key Management Deployment"
fi

# Wait for the Terraform provisioner to copy the admin private key.
# This loop prevents the script from running Ansible commands before the
# key is available, resolving the race condition.

echo "Waiting for Ansible private key to be provisioned at $${PRIVATE_KEY_FILE}..."
SECONDS_WAITED=0
while [ ! -f "$${PRIVATE_KEY_FILE}" ]; do
    if [ "$${SECONDS_WAITED}" -gt 1200 ]; then
        echo "ERROR: Timed out after 20 minutes waiting for private key." >&2
        exit 1
    fi
    sleep 5
    SECONDS_WAITED=$((SECONDS_WAITED + 5))
    echo "Still waiting for key..."
done
echo "Ansible private key found. Proceeding with configuration."
echo "Initial setup complete"
