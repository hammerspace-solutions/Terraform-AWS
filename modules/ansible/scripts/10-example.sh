#!/bin/bash
# Job Script: Add a new storage server and integrate it into the SSH mesh.

# --- Source the Function Library ---
# This line makes functions like 'check_job_status' available to this script.
source /usr/local/lib/ansible_functions.sh

set -euxo pipefail

# --- Variables for this specific job (passed in by a new Terraform run) ---
NEW_NODE_IP="10.0.1.55"
NEW_NODE_NAME="storage-server-3"
# ---

echo "--- Starting job to add node $NEW_NODE_IP ---"

# --- Dependency Check ---
# Now this will work correctly because the function has been loaded.
if ! check_job_status "00-initial-system-setup.sh"; then
    echo "Dependency 00-initial-system-setup.sh failed or did not run. Aborting."
    exit 1
fi

# --- Main Logic ---
# ... (rest of the script remains the same) ...
ALL_NODES_FILE="/etc/ansible/all_nodes.txt"
ANSIBLE_USER="ubuntu"
# ... etc ...

echo "--- Successfully added node $NEW_NODE_IP ---"
