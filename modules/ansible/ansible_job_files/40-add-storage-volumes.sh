#!/bin/bash
#
# Ansible Job: Add Storage Volumes
#
# This script adds non-reserved logical volumes from storage nodes if not already added.
# It is idempotent and only adds new volumes.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/added_storage_volumes.txt" # Track added volume names
HS_USERNAME="admin"
HS_PASSWORD="secret"
VOLUME_GROUP_NAME="default-vg" # Not directly used, but for context

# --- Source the function library ---
# ... (same)

# --- Main Logic ---
# Parse (same)

if [ -z "$all_storage_servers" ] || [ -z "$all_hammerspace" ]; then
  echo "No storage_servers or hammerspace found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

# Build node_names from map
node_names=()
for entry in "${storage_map[@]}"; do
  name=$(echo "$entry" | cut -d: -f2-)
  node_names+=("$name")
done

# Playbook to get non-reserved volumes, add missing
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
---
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"

  tasks:
    - name: Get all nodes
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/nodes"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: nodes_response
      until: nodes_response.status == 200
      retries: 60
      delay: 30

    - name: Filter OTHER nodes
      set_fact:
        other_nodes: "{{ nodes_response.json | selectattr('nodeType', 'equalto', 'OTHER') | list }}"

    - name: Extract non-reserved logical volumes
      set_fact:
        non_reserved_volumes: >-
          {{
            other_nodes
            | map(attribute='platformServices')
            | flatten
            | selectattr('_type', 'equalto', 'LOGICAL_VOLUME')
            | selectattr('reserved', 'equalto', false)
            | list
          }}

    - name: Create volumes for addition
      set_fact:
        volumes_for_add: >-
          [{% for item in non_reserved_volumes %}
            {
              "name": "{{ item.node.name }}::{{ item.exportPath }}",
              "logicalVolume": {
                "name": "{{ item.exportPath }}",
                "_type": "LOGICAL_VOLUME"
              },
              "node": {
                "name": "{{ item.node.name }}",
                "_type": "NODE"
              },
              "_type": "STORAGE_VOLUME",
              "accessType": "READ_WRITE",
              "storageCapabilities": {
                "performance": {
                    "utilizationThreshold": 0.95,
                    "utilizationEvacuationThreshold": 0.9
                }
              }
            }{% if not loop.last %},{% endif %}
          {% endfor %}]

    - name: Add storage volumes
      block:
        - name: Check storage system
          uri:
            url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/nodes/{{ item.node.name|urlencode }}"
            method: GET
            user: "{{ hs_username }}"
            password: "{{ hs_password }}"
            force_basic_auth: true
            validate_certs: false
            status_code: 200
            timeout: 30
          register: __node_results
          until: __node_results.status == 200
          retries: 30
          delay: 10
          loop: "{{ volumes_for_add }}"

        - name: Add volume
          uri:
            url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/storage-volumes?force=true&skipPerfTest=false&createPlacementObjectives=true"
            method: POST
            body: '{{ item }}'
            user: "{{ hs_username }}"
            password: "{{ hs_password }}"
            force_basic_auth: true
            status_code: 202
            body_format: json
            validate_certs: false
            timeout: 30
          register: __results
          until: __results.status == 202
          retries: 30
          delay: 10
          loop: "{{ volumes_for_add }}"

        - name: Wait for completion
          uri:
            url: "{{ item.location }}"
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
          delay: 20
          when: item.status == 202
          loop: "{{ __results.results }}"
EOF

  echo "Running Ansible playbook to add storage volumes..."
  ansible-playbook "$tmp_playbook"

  # Update state with added volumes (extract from playbook or assume all)
  for volume in "$(ansible-playbook "$tmp_playbook" -e "dump_volumes=true" | grep volumes_for_add | jq -r '.[] .name')"; do # Hypothetical
    if ! grep -q -F -x "$volume" "$STATE_FILE"; then
      echo "$volume" >> "$STATE_FILE"
    fi
  done

  # Clean up
  rm -f "$tmp_playbook"

  echo "--- Add Storage Volumes Job Complete ---"
  
