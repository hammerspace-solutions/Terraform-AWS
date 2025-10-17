#!/bin/bash
#
# Ansible Job: Distribute SSH Keys to All Nodes
#
# This script distributes the Ansible controller's public key to all client, storage_server, and
# ecgroup nodes' root user.
# It also collects and distributes all public keys for full mesh root SSH across all nodes, and
# updates known_hosts on all nodes for passwordless access. It is idempotent but updates all nodes on changes.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
CONTROLLER_KEY_PATH="/etc/ansible/keys/ansible"
STATE_FILE="/var/run/ansible_jobs_status/configured_hosts.txt"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting SSH Key Distribution Job ---"

# 1. Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Parse [all:vars] for additional variables (if needed)
hs_username=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /hs_username = / {sub(/.*= /, ""); print}' "$INVENTORY_FILE")
hs_password=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /hs_password = / {sub(/.*= /, ""); print}' "$INVENTORY_FILE")
volume_group_name=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /volume_group_name = / {sub(/.*= /, ""); print}' "$INVENTORY_FILE")
share_name=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /share_name = / {sub(/.*= /, ""); print}' "$INVENTORY_FILE")

# Debug: Log parsed vars
echo "Parsed hs_username: $hs_username"
echo "Parsed hs_password: $hs_password"
echo "Parsed volume_group_name: $volume_group_name"
echo "Parsed share_name: $share_name"

# 3. Find all client, storage server, and ecgroup IPs from the inventory
all_clients=""
clients_map=() # Array of "IP:name"
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[clients\]$ ]]; then 
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[clients\]$ ]]; then 
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "")
    all_clients+="$ip"$'\n'
    clients_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

all_storage_servers=""
storage_servers_map=()
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[storage_servers\]$ ]]; then 
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[storage_servers\]$ ]]; then 
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "")
    all_storage_servers+="$ip"$'\n'
    storage_servers_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

all_ecgroup_nodes=""
ecgroup_nodes_map=()
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[ecgroup_nodes\]$ ]]; then 
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[ecgroup_nodes\]$ ]]; then 
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "")
    all_ecgroup_nodes+="$ip"$'\n'
    ecgroup_nodes_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

all_hammerspace=""
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[hammerspace\]$ ]]; then 
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[hammerspace\]$ ]]; then 
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    all_hammerspace+="$ip"$'\n'
  fi
done < "$INVENTORY_FILE"

# Clean up parsed lists
all_clients=$(echo "$all_clients" | grep -v '^$' | sort -u || true)
all_storage_servers=$(echo "$all_storage_servers" | grep -v '^$' | sort -u || true)
all_ecgroup_nodes=$(echo "$all_ecgroup_nodes" | grep -v '^$' | sort -u || true)
all_hammerspace=$(echo "$all_hammerspace" | grep -v '^$' | sort -u || true)

# Debug: Log parsed IPs
echo "Parsed clients: $all_clients"
echo "Parsed storage_servers: $all_storage_servers"
echo "Parsed ecgroup_nodes: $all_ecgroup_nodes"
echo "Parsed hammerspace: $all_hammerspace"

all_hosts=$(echo -e "$all_clients\n$all_storage_servers\n$all_ecgroup_nodes" | grep -v '^$' | sort -u)

if [ -z "$all_hosts" ]; then
    echo "No client, storage_server, or ecgroup hosts found in inventory. Exiting."
    exit 0
fi

# 4. Pre-scan host keys for all nodes
echo "Pre-scanning SSH host keys for all nodes..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
: > /root/.ssh/known_hosts
for host in $all_hosts; do
    ssh-keyscan -H "$host" >> /root/.ssh/known_hosts 2>/dev/null || {
        echo "WARNING: Failed to scan host key for $host"
    }
done
chmod 600 /root/.ssh/known_hosts

# 5. Identify new hosts (not in state file)
touch "$STATE_FILE"
new_hosts=()
for host in $all_hosts; do
    if ! grep -q -F -x "$host" "$STATE_FILE"; then
        new_hosts+=("$host")
    fi
done

# If new hosts or changes, run full distribution on all
if [ ${#new_hosts[@]} -gt 0 ]; then
    echo "Found ${#new_hosts[@]} new hosts: ${new_hosts[*]}. Updating all nodes for full mesh."

    # 6. Create a temporary inventory with per-group SSH settings
    tmp_inventory=$(mktemp)
    cat > "$tmp_inventory" <<EOF
[clients]
$(for host in $all_clients; do echo "$host ansible_user=root ansible_ssh_private_key_file=$CONTROLLER_KEY_PATH"; done)

[storage_servers]
$(for host in $all_storage_servers; do echo "$host ansible_user=root ansible_ssh_private_key_file=$CONTROLLER_KEY_PATH"; done)

[ecgroup_nodes]
$(for host in $all_ecgroup_nodes; do echo "$host ansible_user=root ansible_ssh_private_key_file=$CONTROLLER_KEY_PATH"; done)

[all_nodes:children]
clients
storage_servers
ecgroup_nodes
EOF

    # 7. Combined playbook for gathering and distributing keys
    tmp_playbook=$(mktemp)
    cat > "$tmp_playbook" <<EOF
- hosts: all_nodes
  gather_facts: yes
  become: yes
  tasks:
    - name: Remove existing SSH key pair on ecgroup nodes
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /root/.ssh/id_rsa
        - /root/.ssh/id_rsa.pub
      when: "'ecgroup_nodes' in group_names"
    - name: Generate SSH key pair for root if not exists
      ansible.builtin.user:
        name: root
        generate_ssh_key: yes
        ssh_key_file: /root/.ssh/id_rsa
        ssh_key_type: ed25519
      register: ssh_key
      retries: 3
      delay: 5
      until: ssh_key is not failed
      ignore_errors: yes
    - name: Fetch public key
      ansible.builtin.slurp:
        src: /root/.ssh/id_rsa.pub
      register: public_key
      when: ssh_key is not failed
      retries: 3
      delay: 5
      until: public_key is not failed
      ignore_errors: yes
    - name: Set fact for public key
      ansible.builtin.set_fact:
        node_public_key: "{{ public_key.content | b64decode }}"
        cacheable: yes
      when: public_key is not failed

- hosts: all_nodes
  gather_facts: yes
  become: yes
  vars:
    controller_public_key_src: "${CONTROLLER_KEY_PATH}.pub"
    all_node_public_keys: "{{ hostvars | json_query('*.node_public_key') | select('defined') | list }}"

  tasks:
    - name: Ensure .ssh directory exists for root
      ansible.builtin.file:
        path: /root/.ssh
        state: directory
        owner: root
        group: root
        mode: '0700'
      retries: 3
      delay: 5
      until: result is not failed
      register: result
      ignore_errors: yes

    - name: Check if authorized_keys is immutable
      ansible.builtin.command: lsattr /root/.ssh/authorized_keys
      register: lsattr_result
      changed_when: false
      failed_when: false

    - name: Remove immutable attribute if present
      ansible.builtin.command: chattr -i /root/.ssh/authorized_keys
      when: lsattr_result.stdout is search('i-')
      changed_when: true
      failed_when: false

    - name: Add controller's public key to root's authorized_keys
      ansible.posix.authorized_key:
        user: root
        state: present
        key: "{{ lookup('file', controller_public_key_src) }}"
      retries: 3
      delay: 5
      until: result is not failed
      register: result
      ignore_errors: yes
      failed_when: result is failed and result.msg is not search('already exists')

    - name: Add all nodes' public keys to root's authorized_keys for full mesh SSH
      ansible.posix.authorized_key:
        user: root
        state: present
        key: "{{ item }}"
      loop: "{{ all_node_public_keys }}"
      retries: 3
      delay: 5
      until: result is not failed
      register: result
      ignore_errors: yes
      failed_when: result is failed and result.msg is not search('already exists')

    - name: Debug authorized_keys update
      ansible.builtin.debug:
        msg: "Authorized keys update for {{ inventory_hostname }}: {{ result }}"
      when: result is defined

    - name: Scan SSH host keys for all nodes
      ansible.builtin.command:
        cmd: "ssh-keyscan -H -T 10 {{ item }}"
      register: ssh_keyscan
      loop: "{{ groups['all'] }}"
      changed_when: false
      ignore_errors: yes
      retries: 3
      delay: 5

    - name: Update known_hosts for root
      ansible.builtin.known_hosts:
        name: "{{ item.item }}"
        key: "{{ item.stdout }}"
        path: "/root/.ssh/known_hosts"
        state: present
      loop: "{{ ssh_keyscan.results }}"
      when: item.stdout != ''
EOF

    echo "Running Ansible playbook to distribute SSH keys and update known_hosts..."
    ansible-playbook -i "$tmp_inventory" -e "ansible_connection=ssh ansible_ssh_private_key_file=$CONTROLLER_KEY_PATH ansible_ssh_extra_args='-o StrictHostKeyChecking=no'" --user root "$tmp_playbook"

    # 8. Update state file with all new hosts
    echo "Playbook finished. Updating state file with all hosts..."
    for host in $all_hosts; do
        if ! grep -q -F -x "$host" "$STATE_FILE"; then
            echo "$host" >> "$STATE_FILE"
        fi
    done

    # 9. Clean up temporary files
    rm -f "$tmp_inventory" "$tmp_playbook"

else
    echo "No changes detected. Exiting."
fi

echo "--- SSH Key Distribution Job Complete ---"
