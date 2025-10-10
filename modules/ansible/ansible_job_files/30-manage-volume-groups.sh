#!/bin/bash
#
# Ansible Job: Manage Volume Group
#
# This script creates the volume group if missing or updates it to include new node locations.
# It is idempotent and only updates if necessary.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/volume_group_state.txt" # Track current nodes in VG
HS_USERNAME="admin"
HS_PASSWORD="secret"
VOLUME_GROUP_NAME="default-vg"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Manage Volume Group Job ---"

# Parse inventory (same as above)
# ... (copy parsing code from first script for all_hammerspace, all_storage_servers, storage_map)

if [ -z "$all_storage_servers" ] || [ -z "$all_hammerspace" ]; then
  echo "No storage_servers or hammerspace found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

# Build current node names from storage_map
current_nodes=()
for entry in "${storage_map[@]}"; do
  name=$(echo "$entry" | cut -d: -f2-)
  current_nodes+=("$name")
done
current_nodes_str=$(printf "%s\n" "${current_nodes[@]}" | sort | tr '\n' ',')

# Check state
touch "$STATE_FILE"
saved_nodes_str=$(cat "$STATE_FILE" | tr '\n' ',' || echo "")

if [ "$current_nodes_str" == "$saved_nodes_str" ]; then
  echo "Volume group already up to date with current nodes. Exiting."
  exit 0
fi

echo "Volume group needs update for nodes: ${current_nodes[*]}"

# Build vg_node_locations
vg_node_locations="["
for entry in "${storage_map[@]}"; do
  name=$(echo "$entry" | cut -d: -f2-)
  vg_node_locations+="{ \"_type\": \"NODE_LOCATION\", \"node\": { \"_type\": \"NODE\", \"name\": \"$name\" } },"
done
vg_node_locations="${vg_node_locations%,}]"

# Playbook for create/update VG
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
---
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    volume_group_name: "$VOLUME_GROUP_NAME"
    vg_node_locations: $vg_node_locations

  tasks:
    - name: Get all volume groups
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: volume_groups_response
      until: volume_groups_response.status == 200
      retries: 30
      delay: 10

    - name: Set fact for VG exists
      set_fact:
        vg_exists: "{{ volume_group_name in (volume_groups_response.json | map(attribute='name') | list) }}"

    - name: Create volume group if missing
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups"
        method: POST
        body: >-
          {{
            {
              "name": volume_group_name,
              "_type": "VOLUME_GROUP",
              "expressions": [
                {
                  "operator": "IN",
                  "locations": vg_node_locations
                }
              ]
            }
          }}
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 200
        body_format: json
        validate_certs: false
        timeout: 30
      when: not vg_exists
      register: vg_create
      until: vg_create.status == 200
      retries: 30
      delay: 10

    - name: Update volume group if exists (assume PUT for update)
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups/{{ volume_group_name }}"
        method: PUT
        body: >-
          {{
            {
              "name": volume_group_name,
              "_type": "VOLUME_GROUP",
              "expressions": [
                {
                  "operator": "IN",
                  "locations": vg_node_locations
                }
              ]
            }
          }}
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 200
        body_format: json
        validate_certs: false
        timeout: 30
      when: vg_exists
      register: vg_update
      until: vg_update.status == 200
      retries: 30
      delay: 10

    - name: Wait until volume group contains all nodes
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: volume_groups_updated
      until: >-
        (
          volume_groups_updated.json
          | selectattr('name', 'equalto', volume_group_name)
          | map(attribute='expressions')
          | map('first')
          | map(attribute='locations')
          | map('map', attribute='node')
          | map('map', attribute='name')
          | list
          | first
          | sort
        ) == (vg_node_locations | map(attribute='node') | map(attribute='name') | list | sort)
      retries: 30
      delay: 10
EOF

  echo "Running Ansible playbook to manage volume group..."
  ansible-playbook "$tmp_playbook"

  # Update state
  printf "%s\n" "${current_nodes[@]}" > "$STATE_FILE"

  # Clean up
  rm -f "$tmp_playbook"

  echo "--- Manage Volume Group Job Complete ---"
  
