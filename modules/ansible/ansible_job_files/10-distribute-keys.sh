#!/bin/bash
#
# Ansible Job: Distribute SSH Keys to New Nodes
#
# This script identifies new client and storage_server nodes from the inventory
# and distributes the Ansible controller's SSH key pair to them. It is idempotent
# and only targets hosts that have not been configured before.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/etc/ansible/inventory.ini"
CONTROLLER_KEY_PATH="/etc/ansible/ssh/id_rsa"
STATE_FILE="/var/run/ansible_jobs_status/configured_hosts.txt"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting SSH Key Distribution Job ---"

# 1. Ensure the state file exists
touch "$STATE_FILE"

# 2. Find all client and storage server instance IDs from the main inventory
current_hosts=$(grep -E '^(i-)' "$INVENTORY_FILE" || true)

if [ -z "$current_hosts" ]; then
    echo "No client or storage_server hosts found in inventory. Exiting."
    exit 0
fi

# 3. Identify which hosts are new
new_hosts=()
while IFS= read -r host_id; do
    if ! grep -q -F -x "$host_id" "$STATE_FILE"; then
        new_hosts+=("$host_id")
    fi
done <<< "$current_hosts"

if [ ${#new_hosts[@]} -eq 0 ]; then
    echo "No new hosts to configure. All nodes are up to date."
    exit 0
fi

echo "Found ${#new_hosts[@]} new hosts to configure: ${new_hosts[*]}"

# 4. Create a temporary inventory file for this run
tmp_inventory=$(mktemp)
echo "[new_nodes]" > "$tmp_inventory"
for host in "${new_hosts[@]}"; do
    echo "$host" >> "$tmp_inventory"
done

# 5. Create a temporary playbook file
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
---
- hosts: new_nodes
  gather_facts: yes
  become: yes

  vars:
    default_os_user: "{{ ansible_user_id }}"
    default_os_home: "{{ ansible_env.HOME }}"
    controller_private_key_src: "${CONTROLLER_KEY_PATH}"
    controller_public_key_src: "${CONTROLLER_KEY_PATH}.pub"

  tasks:
    - name: Ensure .ssh directory exists for root
      ansible.builtin.file:
        path: /root/.ssh
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Ensure .ssh directory exists for default OS user
      ansible.builtin.file:
        path: "{{ default_os_home }}/.ssh"
        state: directory
        owner: "{{ default_os_user }}"
        group: "{{ default_os_user }}"
        mode: '0700'

    - name: Copy controller's private key to root
      ansible.builtin.copy:
        src: "{{ controller_private_key_src }}"
        dest: /root/.ssh/id_rsa
        owner: root
        group: root
        mode: '0600'

    - name: Copy controller's private key to default OS user
      ansible.builtin.copy:
        src: "{{ controller_private_key_src }}"
        dest: "{{ default_os_home }}/.ssh/id_rsa"
        owner: "{{ default_os_user }}"
        group: "{{ default_os_user }}"
        mode: '0600'

    - name: Add controller's public key to root's authorized_keys
      ansible.posix.authorized_key:
        user: root
        state: present
        key: "{{ lookup('file', controller_public_key_src) }}"

    - name: Add controller's public key to default OS user's authorized_keys
      ansible.posix.authorized_key:
        user: "{{ default_os_user }}"
        state: present
        key: "{{ lookup('file', controller_public_key_src) }}"
EOF

# 6. Run the Ansible playbook using the temporary playbook file
echo "Running Ansible playbook to distribute SSH keys..."
ansible-playbook -i "$tmp_inventory" -e "ansible_connection=aws_ssm" --user root "$tmp_playbook"

# 7. Update the state file with the newly configured hosts
echo "Playbook finished. Updating state file..."
for host in "${new_hosts[@]}"; do
    echo "$host" >> "$STATE_FILE"
done

# 8. Clean up both temporary files
rm -f "$tmp_inventory" "$tmp_playbook"

echo "--- SSH Key Distribution Job Complete ---"
