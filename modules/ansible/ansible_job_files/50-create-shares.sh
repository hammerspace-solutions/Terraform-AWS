#!/bin/bash
#
# Ansible Job: Create Share
#
# This script creates the share if not existing.
# It is idempotent.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/created_shares.txt"
HS_USERNAME="admin"
HS_PASSWORD="secret"
SHARE_NAME="data-share" # Customize
# Assume share body, replace with actual JSON structure
SHARE_BODY='{ "name": "'$SHARE_NAME'", "_type": "SHARE" }' # Add more fields

# --- Source the function library ---
# ... (same)

# --- Main Logic ---
# Parse (same)

if [ -z "$all_storage_servers" ] || [ -z "$all_hammerspace" ]; then
  echo "No storage_servers or hammerspace found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

if grep -q -F -x "$SHARE_NAME" "$STATE_FILE"; then
  echo "Share $SHARE_NAME already created. Exiting."
  exit 0
fi

# Playbook for create share
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
---
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    share_name: "$SHARE_NAME"
    share: $SHARE_BODY

  tasks:
    - name: Get all shares
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/shares"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: shares_response
      until: shares_response.status == 200
      retries: 30
      delay: 10

    - name: Set fact for share exists
      set_fact:
        share_exists: "{{ share_name in (shares_response.json | map(attribute='name') | list) }}"

    - name: Create share if missing
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/shares"
        method: POST
        body: '{{ share }}'
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 202
        body_format: json
        validate_certs: false
        timeout: 30
      register: share_create
      until: share_create.status == 202
      retries: 30
      delay: 10
      when: not share_exists

    - name: Wait for completion
      uri:
        url: "{{ share_create.location }}"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        status_code: 200
        body_format: json
        timeout: 30
      register: _result
      until: _result.json.status == "COMPLETED"
      retries: 30
      delay: 10
      when: share_create.status == 202
EOF

  echo "Running Ansible playbook to create share..."
  ansible-playbook "$tmp_playbook"

  # Update state
  echo "$SHARE_NAME" >> "$STATE_FILE"

  # Clean up
  rm -f "$tmp_playbook"

  echo "--- Create Share Job Complete ---"
  
