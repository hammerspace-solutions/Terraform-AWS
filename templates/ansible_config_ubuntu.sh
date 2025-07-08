#!/bin/bash

# Variable placeholders - replaced by Terraform templatefile function)

TARGET_NODES_JSON='${TARGET_NODES_JSON}'

# --- Script ---
set -euo pipefail

# Update system and install required packages
#
# You can modify this based upon your needs

sudo apt-get -y update
sudo apt-get install -y pip git bc screen net-tools
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible jq

# Upgrade all the installed packages

echo "Upgrade the OS to make sure we have the latest"
sudo apt-get -y upgrade

# WARNING!!
# DO NOT MODIFY ANYTHING BELOW THIS LINE OR INSTANCES MAY NOT START CORRECTLY!
# ----------------------------------------------------------------------------

TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
SSH_KEYS="${SSH_KEYS}"

# Build NFS mountpoint

sudo mkdir -p /mnt/nfs-test
sudo chmod 777 /mnt/nfs-test

# SSH Key Management

if [ -n "$${SSH_KEYS}" ]; then
    mkdir -p "$${TARGET_HOME}/.ssh"
    chmod 700 "$${TARGET_HOME}/.ssh"
    touch "$${TARGET_HOME}/.ssh/authorized_keys"
    
    # Process keys one by one to avoid multi-line issues

    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "$${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$${key}" >> "$${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "$${TARGET_USER}:$${TARGET_USER}" "$${TARGET_HOME}/.ssh"
fi

# The 'community.crypto' collection is needed for the openssh_keypair module.

sudo -u ubuntu ansible-galaxy collection install community.crypto

# Create the inventory file for Ansible in the ubuntu user's home directory

INVENTORY_FILE="/home/ubuntu/inventory.ini"
echo "[all_nodes]" > "$INVENTORY_FILE"

# Parse the JSON passed from Terraform and create the inventory list

echo "$TARGET_NODES_JSON" | jq -r '.[] | .private_ip' >> "$INVENTORY_FILE"
chown ubuntu:ubuntu "$INVENTORY_FILE"

# Build the Anvil ansible playbook

cat > /tmp/anvil.yml << EOF
data_cluster_mgmt_ip: "${MGMT_IP}"
hsuser: admin 
password: "${ANVIL_ID}"
volume_group_name: "${VG_NAME}"
share_name: "${SHARE_NAME}"
EOF

# Build the Nodes ansible playbook

echo '${STORAGE_INSTANCES}' | jq -r '
  "storages:",
  map(
    "- name: \"" + .name + "\"\n" +
    "  nodeType: \"OTHER\"\n" +
    "  mgmtIpAddress:\n" +
    "    address: \"" + .private_ip + "\"\n" +
    "  _type: \"NODE\""
  )[]
' > /tmp/nodes.yml

echo 'share:
  name: "{{ share_name }}"
  path: "/{{ share_name }}"
  maxShareSize: 0
  alertThreshold: 90
  maxShareSizeType: TB
  smbAliases: []
  exportOptions:
  - subnet: "*"
    rootSquash: false
    accessPermissions: RW
  shareSnapshots: []
  shareObjectives:
  - objective:
      name: no-atime
    applicability: "TRUE"
  - objective:
      name: confine-to-{{ volume_group_name }}
    applicability: "TRUE"
  smbBrowsable: true
  shareSizeLimit: 0' > /tmp/share.yml

# Write the Ansible playbook to the disk

PLAYBOOK_FILE="/home/ubuntu/distribute_keys.yml"
cat > "$PLAYBOOK_FILE" << EOF
---
# Play 1: Generate keys on all hosts and gather their public keys
- name: Gather Host Keys
  hosts: all_nodes
  gather_facts: false
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /home/ubuntu/.ssh/ansible_admin_key

  tasks:
    - name: Ensure .ssh directory exists for user ubuntu
      become: true
      file:
        path: "/home/ubuntu/.ssh"
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0700'

    - name: Ensure SSH key pair exists for each host
      become: true
      community.crypto.openssh_keypair:
        path: /home/ubuntu/.ssh/id_rsa
        owner: ubuntu
        group: ubuntu
        mode: '0600'
      # This task is idempotent; it won't change existing keys.

    - name: Fetch the public key content from each host
      slurp:
        src: /home/ubuntu/.ssh/id_rsa.pub
      register: host_public_key

# Play 2: Distribute all collected public keys to all hosts
- name: Distribute All Keys
  hosts: all_nodes
  gather_facts: false # Facts were gathered in the previous play if needed
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /home/ubuntu/.ssh/ansible_admin_key

  tasks:
    - name: Add each host's public key to every other host's authorized_keys file
      authorized_key:
        user: ubuntu
        state: present
        key: "{{ hostvars[item].host_public_key.content | b64decode }}"
      # Loop over every host in the current Ansible run
      loop: "{{ ansible_play_hosts_all }}"

EOF
chown ubuntu:ubuntu "$PLAYBOOK_FILE"

# ssh-keyscan populates known_hosts to avoid interactive prompts about authenticity

echo "Scanning hosts to populate known hosts..."
sudo -u ubuntu bash -c "ssh-keyscan -H -f /home/ubuntu/inventory.ini >> /home/ubuntu/.ssh/known_hosts"
echo "End scanning of hosts"

# Get the main Ansible playbook from the git repository

echo "Get the Hammerspace ansible playbook from the git repository"
sudo wget -O /tmp/hs-ansible.yml https://raw.githubusercontent.com/hammerspace-solutions/Terraform-AWS/main/modules/ansible/hs-ansible.yml
echo "End of getting the ansible playbook"

# Run the Ansible playbook for the Anvil

echo "Run the Hammerspace ansible to add items to the Anvil"
sudo ansible-playbook /tmp/hs-ansible.yml -e @/tmp/anvil.yml -e @/tmp/nodes.yml -e @/tmp/share.yml
echo "End of the Hammerspace ansible"

# Run the Ansible playbook to distribute the SSH keys...

echo "Running Ansible playbook to distribute SSH keys..."
sudo -u ubuntu bash -c "ansible-playbook -i /home/ubuntu/inventory.ini /home/ubuntu/distribute_keys.yml"
echo "End of Ansible playbook to distribute SSH keys..."
