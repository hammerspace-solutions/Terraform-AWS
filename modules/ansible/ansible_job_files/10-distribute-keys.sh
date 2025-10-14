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

# 2. Find all client, storage server, and ecgroup IPs from the inventory (ignoring extra fields like node_name)
all_clients=$(awk '/^\[clients\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && NF {print $1}' "$INVENTORY_FILE" | grep -v '^$' || echo "")
all_storage_servers=$(awk '/^\[storage_servers\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && NF {print $1}' "$INVENTORY_FILE" | grep -v '^$' || echo "")
all_ecgroup_nodes=$(awk '/^\[ecgroup_nodes\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && NF {print $1}' "$INVENTORY_FILE" | grep -v '^$' || echo "")

# Debug: Log parsed IPs
echo "Parsed clients: $all_clients"
echo "Parsed storage_servers: $all_storage_servers"
echo "Parsed ecgroup_nodes: $all_ecgroup_nodes"

all_hosts=$(echo -e "$all_clients\n$all_storage_servers\n$all_ecgroup_nodes" | grep -v '^$' | sort -u)

if [ -z "$all_hosts" ]; then
    echo "No client, storage_server, or ecgroup hosts found in inventory. Exiting."
    exit 0
fi

# 3. Pre-scan host keys for all nodes
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

# 4. Identify new hosts (not in state file)
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

    # 5. Create a temporary inventory for all clients, storage_servers, and ecgroup
    tmp_inventory=$(mktemp)
    echo "[all_nodes]" > "$tmp_inventory"
    for host in $all_hosts; do
        echo "$host" >> "$tmp_inventory"
    done

    # 6. Combined playbook for gathering and distributing keys
    tmp_playbook=$(mktemp)
    cat > "$tmp_playbook" <<EOF
- hosts: all_nodes
  gather_facts: yes
  become: yes
  tasks:
    - name: Generate SSH key pair for root if not exists
      ansible.builtin.user:
        name: root
        generate_ssh_key: yes
        ssh_key_file: /root/.ssh/id_rsa
        ssh_key_type: ed25519
      register: ssh_key
    - name: Fetch public key
      ansible.builtin.slurp:
        src: /root/.ssh/id_rsa.pub
      register: public_key
    - name: Set fact for public key
      ansible.builtin.set_fact:
        node_public_key: "{{ public_key.content | b64decode }}"
        cacheable: yes

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

    - name: Add controller's public key to root's authorized_keys
      ansible.posix.authorized_key:
        user: root
        state: present
        key: "{{ lookup('file', controller_public_key_src) }}"

    - name: Add all nodes' public keys to root's authorized_keys for full mesh SSH
      ansible.posix.authorized_key:
        user: root
        state: present
        key: "{{ item }}"
      loop: "{{ all_node_public_keys }}"

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

    # 7. Update state file with all new hosts
    echo "Playbook finished. Updating state file with all hosts..."
    for host in $all_hosts; do
        if ! grep -q -F -x "$host" "$STATE_FILE"; then
            echo "$host" >> "$STATE_FILE"
        fi
    done

    # 8. Clean up temporary files
    rm -f "$tmp_inventory" "$tmp_playbook"

else
    echo "No changes detected. Exiting."
fi

echo "--- SSH Key Distribution Job Complete ---"
