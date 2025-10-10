#!/bin/bash
#
# Ansible Job: Add Storage Nodes
#
# This script adds missing storage nodes (type OTHER) to the Hammerspace system using the API.
# It is idempotent and only adds new nodes based on the inventory.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/added_storage_nodes.txt"
HS_USERNAME="admin"  # Replace with actual or use env var
HS_PASSWORD="secret" # Replace with actual or use env var
VOLUME_GROUP_NAME="default-vg" # Customize as needed

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Add Storage Nodes Job ---"

# 1. Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Parse hammerspace and storage_servers with names (assuming inventory has IP node_name="name")
all_hammerspace=""
while read -r line; do
  if [ "$flag" = "hammerspace" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    all_hammerspace+="$line"$'\n'
  fi
  if [[ "$line" =~ ^\[hammerspace\]$ ]]; then flag="hammerspace"; elif [[ "$line" =~ ^\[ ]]; then flag=0; fi
done < "$INVENTORY_FILE"

all_storage_servers=""
storage_map=() # Array of "IP:name"
flag=0
while read -r line; do
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+')
    all_storage_servers+="$ip"$'\n'
    storage_map+=("$ip:$name")
  fi
  if [[ "$line" =~ ^\[storage_servers\]$ ]]; then flag=1; elif [[ "$line" =~ ^\[ ]]; then flag=0; fi
done < "$INVENTORY_FILE"

all_hammerspace=$(echo "$all_hammerspace" | grep -v '^$' | sort -u)
all_storage_servers=$(echo "$all_storage_servers" | grep -v '^$' | sort -u)

# Debug: Log parsed IPs
echo "Parsed hammerspace: $all_hammerspace"
echo "Parsed storage_servers: $all_storage_servers"

if [ -z "$all_storage_servers" ] || [ -z "$all_hammerspace" ]; then
  echo "No storage_servers or hammerspace found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

all_hosts=$(echo -e "$all_storage_servers" | sort -u)

# 3. Identify new hosts (storage_servers not in state)
touch "$STATE_FILE"
new_hosts=()
for host in $all_hosts; do
  if ! grep -q -F -x "$host" "$STATE_FILE"; then
    new_hosts+=("$host")
  fi
done

# If new hosts, run addition
if [ ${#new_hosts[@]} -gt 0 ]; then
  echo "Found ${#new_hosts[@]} new storage servers: ${new_hosts[*]}. Adding them."

  # 4. Build storages list from map (assume body for each: name from node_name, type OTHER)
  storages_json="["

  for entry in "${storage_map[@]}"; do
    ip=$(echo "$entry" | cut -d: -f1)
    name=$(echo "$entry" | cut -d: -f2-)
    if echo "${new_hosts[*]}" | grep -q "$ip"; then
      storages_json+="{ \"name\": \"$name\", \"_type\": \"NODE\", \"nodeType\": \"OTHER\" }," # Add more fields if known
    fi
  done
  storages_json="${storages_json%,}]"

  # 5. Combined playbook for adding nodes
  tmp_playbook=$(mktemp)
  cat > "$tmp_playbook" <<EOF
---
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    storages: $storages_json

  tasks:
    - name: Get all nodes (with retries)
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

    - name: Extract existing node names
      set_fact:
        existing_node_names: "{{ nodes_response.json | map(attribute='name') | list }}"

    - name: Add storage system if not present
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/nodes"
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        method: POST
        body: '{{ storage }}'
        force_basic_auth: yes
        status_code: 202
        body_format: json
        validate_certs: no
        timeout: 30
      loop: "{{ storages }}"
      loop_control:
        loop_var: storage
      when: storage.name not in existing_node_names and storage.nodeType == "OTHER"
      register: node_add
      until: node_add.status == 202
      retries: 30
      delay: 10

    - name: Pause for consistency
      pause:
        seconds: 10

    - name: Wait until all expected OTHER nodes are present
      vars:
        expected_other_nodes: "{{ storages | map(attribute='name') | list | sort }}"
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
      register: node_list_check
      until: >-
        (
          node_list_check.json
          | selectattr('nodeType', 'equalto', 'OTHER')
          | selectattr('nodeState', 'equalto', 'MANAGED')
          | selectattr('hwComponentState', 'equalto', 'OK')
          | map(attribute='name')
          | list
          | sort
        ) == expected_other_nodes
      retries: 30
      delay: 10
EOF

  echo "Running Ansible playbook to add storage nodes..."
  ansible-playbook "$tmp_playbook" 

  # 6. Update state file with new hosts
  echo "Playbook finished. Updating state file with new storage servers..."
  for host in "${new_hosts[@]}"; do
    echo "$host" >> "$STATE_FILE"
  done

  # 7. Clean up
  rm -f "$tmp_playbook"

else
  echo "No new storage servers detected. Exiting."
fi

echo "--- Add Storage Nodes Job Complete ---"
