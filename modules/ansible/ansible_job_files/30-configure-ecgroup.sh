#!/bin/bash
#
# Ansible Job: Configure ECGroup Cluster
#
# This script configures the ECGroup cluster using the provided nodes from the inventory.
# It is idempotent and only configures new nodes based on the inventory.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/configured_ecgroup_nodes.txt"  # Track configured ECGroup nodes
ECGROUP_PRIVATE_KEY_PATH="/etc/ecgroups/keys/ecgroups"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Configure ECGroup Cluster Job ---"

# 1. Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Parse ecgroup_nodes with IPs and names

all_ecgroup_nodes=""
ecgroup_map=() # Array of "IP:name"
flag="0"  # Initialize flag for ecgroup_nodes parsing
while read -r line; do
  if [[ "$line" =~ ^\[ecgroup_nodes\]$ ]]; then 
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[ecgroup_nodes\]$ ]]; then 
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "${ip//./-}")
    all_ecgroup_nodes+="$ip"$'\n'
    ecgroup_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

all_ecgroup_nodes=$(echo "$all_ecgroup_nodes" | grep -v '^$' | sort -u || true)

# Debug: Log parsed IPs
echo "Parsed ecgroup_nodes: $all_ecgroup_nodes"

if [ -z "$all_ecgroup_nodes" ]; then
  echo "No ecgroup_nodes found in inventory. Exiting."
  exit 0
fi

all_hosts=$(echo -e "$all_ecgroup_nodes" | sort -u)

# 4. Identify new hosts (ecgroup_nodes not in state)
touch "$STATE_FILE"
new_hosts=()
for host in $all_hosts; do
  if ! grep -q -F -x "$host" "$STATE_FILE"; then
    new_hosts+=("$host")
  fi
done

# If new hosts, run configuration
if [ ${#new_hosts[@]} -gt 0 ]; then
  echo "Found ${#new_hosts[@]} new ECGroup nodes: ${new_hosts[*]}. Configuring them."

  # 5. Build ECGroup hosts list (IPs) and nodes list (names) from map
  ecgroup_hosts=""
  ecgroup_nodes=""
  for entry in "${ecgroup_map[@]}"; do
    ip=$(echo "$entry" | cut -d: -f1)
    name=$(echo "$entry" | cut -d: -f2-)
    ecgroup_hosts+="$ip "
    ecgroup_nodes+="$name "
  done
  ecgroup_hosts="${ecgroup_hosts% }"
  ecgroup_nodes="${ecgroup_nodes% }"

  # Assume ECGROUP_METADATA_ARRAY and ECGROUP_STORAGE_ARRAY are parsed or hardcoded; adjust as needed
  # For example, derive from inventory or vars if available
  ECGROUP_METADATA_ARRAY="/dev/sdb"  # Placeholder; customize based on your setup
  ECGROUP_STORAGE_ARRAY="/dev/sdc"   # Placeholder; customize
  ECGROUP_USER="admin"              # Adjust if different

  # 6. Create temporary ECGroup inventory
  tmp_inventory=$(mktemp)
  echo "[ecgroup]" > "$tmp_inventory"
  for host in $ecgroup_hosts; do
    echo "$host ansible_user=$ECGROUP_USER ansible_ssh_private_key_file=$ECGROUP_PRIVATE_KEY_PATH" >> "$tmp_inventory"
  done

  # 7. Combined playbook for configuring ECGroup
  tmp_playbook=$(mktemp)
  cat > "$tmp_playbook" <<EOF
- name: Configure ECGroup from the controller node
  hosts: ecgroup
  gather_facts: false
  vars:
    ecgroup_name: "ecg"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  become: true
  tasks:
    - name: Create the cluster
      shell: >
        /opt/rozofs-installer/rozo_rozofs_create.sh -n {{ ecgroup_name }} -s "$ecgroup_nodes" -t external -d 3
      register: create_cluster_result
      retries: 3
      delay: 10
      until: create_cluster_result.rc == 0

    - name: Add CTDB nodes
      shell: >
        /opt/rozofs-installer/rozo_rozofs_ctdb_node_add.sh -n {{ ecgroup_name }} -c "$ecgroup_nodes"
      register: ctdb_node_add_result
      retries: 3
      delay: 10
      until: ctdb_node_add_result.rc == 0

    - name: Setup DRBD
      shell: >
        /opt/rozofs-installer/rozo_drbd.sh -y -n {{ ecgroup_name }} -d "$ECGROUP_METADATA_ARRAY"
      register: drbd_result
      retries: 3
      delay: 10
      until: drbd_result.rc == 0

    - name: Create the array
      shell: >
        /opt/rozofs-installer/rozo_compute_cluster_balanced.sh -y -n {{ ecgroup_name }} -d "$ECGROUP_STORAGE_ARRAY"
      register: compute_cluster_result
      retries: 3
      delay: 10
      until: compute_cluster_result.rc == 0

    - name: Propagate the configuration
      shell: >
        /opt/rozofs-installer/rozo_rozofs_install.sh -n {{ ecgroup_name }}
      register: install_result
      retries: 3
      delay: 10
      until: install_result.rc == 0
  run_once: true
EOF

  # 8. Wait for instances to be ready (with timeout)
  echo "Waiting for ECGroup instances to be ready (port 22 open)..."
  for ip in $all_hosts; do
    SECONDS=0
    while ! nc -z -w1 "$ip" 22 &>/dev/null; do
      sleep 2
      if (( SECONDS >= 240 )); then
        echo "ERROR: $ip did not open port 22 after 240 seconds."
        exit 1
      fi
    done
  done

  # 9. Test SSH connectivity
  echo "Testing SSH connectivity to ECGroup nodes..."
  for node in $all_hosts; do
    ssh -i "$ECGROUP_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$ECGROUP_USER@$node" "echo 'SSH connection successful to $node'" || {
      echo "ERROR: Could not SSH to $node"
      exit 1
    }
  done

  # 10. Run the Ansible playbook
  echo "Running Ansible playbook to configure ECGroup..."
  ansible-playbook "$tmp_playbook" -i "$tmp_inventory"

  # 11. Update state file with new hosts
  echo "Playbook finished. Updating state file with new ECGroup nodes..."
  for host in "${new_hosts[@]}"; do
    echo "$host" >> "$STATE_FILE"
  done

  # 12. Clean up
  rm -f "$tmp_inventory" "$tmp_playbook"

else
  echo "No new ECGroup nodes detected. Exiting."
fi

echo "--- Configure ECGroup Cluster Job Complete ---"
