#!/bin/bash
# This script creates the daemon and function library, then starts the service.

# --- Script ---

set -euo pipefail

# --- Create the function library script ---
sudo mkdir -p /usr/local/lib
cat <<'EOF' | sudo tee /usr/local/lib/ansible_functions.sh > /dev/null
${functions_script}
EOF

# --- Create the daemon script ---
sudo mkdir -p /usr/local/bin
cat <<'EOF' | sudo tee /usr/local/bin/ansible_controller_daemon.sh > /dev/null
${daemon_script}
EOF

# --- Create the initial job script (as designed before) ---
# This part uses the other variables passed in from Terraform
sudo mkdir -p /tmp/ansible_config
cat <<EOF | sudo tee /tmp/ansible_config/00-initial-system-setup.sh > /dev/null
#!/bin/bash

# Variable placeholders - replaced by Terraform templatefile function

TARGET_USER='${TARGET_USER}'
TARGET_HOME='${TARGET_HOME}'
SSH_KEYS='${SSH_KEYS}'

# Some private variables for dealing with ssh-less logins using root

ROOT_USER='${ROOT_USER}'
ROOT_HOME='${ROOT_HOME}'

# --- Script ---

set -euo pipefail

# --- Package Installation ---

sudo apt-get -y update
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible jq net-tools

# --- Install Emacs (because I like it) ---

sudo DEBIAN_FRONTEND=noninteractive apt install -y emacs

echo "Upgrade the OS to make sure we have the latest"
sudo apt-get -y upgrade

# Restart the sshd

systemctl restart ssh

# --- SSH Key Management for additional keys ---

if [ -n "$${SSH_KEYS}" ]; then
    echo "Starting SSH Key Management Deployment"

    if [ ! -d "$${TARGET_HOME}/.ssh" ]; then
      mkdir -p "$${TARGET_HOME}/.ssh"
      chmod 700 "$${TARGET_HOME}/.ssh"
      touch "$${TARGET_HOME}/.ssh/authorized_keys"
    fi
    
    # Process keys one by one to avoid multi-line issues

    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "$${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$${key}" >> "$${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "$${TARGET_USER}:$${TARGET_USER}" "$${TARGET_HOME}/.ssh"
    echo "Ending SSH Key Management Deployment"
fi

# --- SSH Key Management for additional keys (This is ONLY for root) ---

if [ -n "$${SSH_KEYS}" ]; then
    echo "Starting SSH Key Management Deployment for root"

    if [ ! -d "$${ROOT_HOME}/.ssh" ]; then
      mkdir -p "$${ROOT_HOME}/.ssh"
      chmod 700 "$${ROOT_HOME}/.ssh"
      touch "$${ROOT_HOME}/.ssh/authorized_keys"
    fi
    
    # Process keys line by line
    
    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "$${ROOT_HOME}/.ssh/authorized_keys"; then
            echo "$${key}" >> "$${ROOT_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$${ROOT_HOME}/.ssh/authorized_keys"
    chown -R "$${ROOT_USER}":"$${ROOT_USER}" "$${ROOT_HOME}/.ssh"
    echo "Ending SSH Key Management Deployment for $${ROOT_USER}"
fi

echo "Ansible controller setup complete."
EOF

# --- Set permissions and launch the daemon ---
sudo chmod +x /usr/local/bin/ansible_controller_daemon.sh
sudo chmod +x /tmp/ansible_config/00-initial-system-setup.sh

# Redirect stdout/stderr and launch the daemon in the background
sudo /usr/local/bin/ansible_controller_daemon.sh > /var/log/ansible_controller_daemon.log 2>&1 &
