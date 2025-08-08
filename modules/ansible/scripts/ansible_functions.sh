#!/bin/bash

# Library of functions for the Ansible Controller

# --- State and Config Files ---
ALL_NODES_FILE="/etc/ansible/all_nodes.txt"
ANSIBLE_USER="ubuntu"
ADMIN_PRIVATE_KEY="/home/${ANSIBLE_USER}/.ssh/ansible_admin_key"
LOCK_FILE="/var/ansible_initial_setup.done"
STATUS_DIR="/var/run/ansible_jobs_status"


# --- Function: check_job_status ---
# Allows a script to check if a previous job succeeded.
# Usage: check_job_status "10-clients-ssh-keys.sh"
# Exits with 0 if the job was successful, 1 otherwise.
check_job_status() {
    local job_name="$1"
    if [ -f "$STATUS_DIR/$job_name.success" ]; then
        return 0 # Success
    else
        return 1 # Failure or not run
    fi
}


# --- Function: run_initial_setup ---
# Performs the one-time setup. It no longer contains the main logic itself,
# but instead PREPARES the very first job script using Terraform variables.
run_initial_setup() {
    echo "Preparing the initial system configuration job..."

    # Variable placeholders are expanded by Terraform into the first job script
    cat > /tmp/ansible_config/00-initial-system-setup.sh <<EOF
#!/bin/bash
# This script contains all the one-time setup logic for the entire cluster.

# --- Initial Terraform Variables ---
TARGET_NODES_JSON='${TARGET_NODES_JSON}'
# ... (and all your other Terraform variables: MGMT_IP, ANVIL_ID, etc.) ...
# ---

echo "--- Starting 00-initial-system-setup.sh ---"
set -euxo pipefail

# 1. Package Installation & Initial Config
echo "Installing prerequisite packages..."
sudo apt-get -y update > /dev/null
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible jq net-tools

# 2. Passwordless SSH Setup for the INITIAL set of nodes
if [ -n "\$TARGET_NODES_JSON" ] && [ "\$TARGET_NODES_JSON" != "[]" ]; then
    echo "Setting up initial passwordless SSH..."
    # Create the master list of all nodes
    mkdir -p /etc/ansible
    echo "\$TARGET_NODES_JSON" | jq -r '.[] | .private_ip' > "$ALL_NODES_FILE"
    
    # ... The rest of your original "Passwordless SSH Setup" Ansible playbook logic goes here ...
    # It will run against the initial inventory.
else
    echo "No initial nodes to configure."
    mkdir -p /etc/ansible
    touch "$ALL_NODES_FILE"
fi

# 3. ECGroup and Hammerspace Configuration
# ... Your original ECGroup and Hammerspace logic goes here ...
# This will only run once as part of this initial script.

echo "--- Finished 00-initial-system-setup.sh ---"

# 4. Create the lock file to prevent this function from running again
sudo touch "$LOCK_FILE"
EOF

    chmod +x /tmp/ansible_config/00-initial-system-setup.sh
    echo "Initial setup script has been created. The daemon will now pick it up and execute it."
}
