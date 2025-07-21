#!/bin/bash

# Variable placeholders - replaced by Terraform templatefile function
TARGET_NODES_JSON='${TARGET_NODES_JSON}'
MGMT_IP='${MGMT_IP}'
ANVIL_ID='${ANVIL_ID}'
STORAGE_INSTANCES='${STORAGE_INSTANCES}'
VG_NAME='${VG_NAME}'
SHARE_NAME='${SHARE_NAME}'
ECGROUP_INSTANCES='${ECGROUP_INSTANCES}'
ECGROUP_HOSTS='${ECGROUP_HOSTS}'
ECGROUP_NODES='${ECGROUP_NODES}'
ECGROUP_METADATA_ARRAY='${ECGROUP_METADATA_ARRAY}'
ECGROUP_STORAGE_ARRAY='${ECGROUP_STORAGE_ARRAY}'
TARGET_USER='${TARGET_USER}'
TARGET_HOME='${TARGET_HOME}'
SSH_KEYS='${SSH_KEYS}'

# --- Script ---
set -euo pipefail

# --- Package Installation ---
sudo apt-get -y update
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible jq net-tools

echo "Upgrade the OS to make sure we have the latest"
sudo apt-get -y upgrade

# --- SSH Key Management for additional keys ---
if [ -n "$${SSH_KEYS}" ]; then

    echo "Starting SSH Key Management Deployment"
    mkdir -p "$${TARGET_HOME}/.ssh"
    chmod 700 "$${TARGET_HOME}/.ssh"
    touch "$${TARGET_HOME}/.ssh/authorized_keys"
    
    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "$${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$${key}" >> "$${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "$${TARGET_USER}:$${TARGET_USER}" "$${TARGET_HOME}/.ssh"
    echo "Ending SSH Key Management Deployment"
fi

# Wait for the Terraform provisioner to copy the admin private key.
# This loop prevents the script from running Ansible commands before the
# key is available, resolving the race condition.

PRIVATE_KEY_FILE="/home/ubuntu/.ssh/ansible_admin_key"
echo "Waiting for Ansible private key to be provisioned at $${PRIVATE_KEY_FILE}..."
SECONDS_WAITED=0
while [ ! -f "$${PRIVATE_KEY_FILE}" ]; do
    if [ "$${SECONDS_WAITED}" -gt 1200 ]; then
        echo "ERROR: Timed out after 20 minutes waiting for private key." >&2
        exit 1
    fi
    sleep 5
    SECONDS_WAITED=$((SECONDS_WAITED + 5))
    echo "Still waiting for key..."
done
echo "Ansible private key found. Proceeding with configuration."

# --- Passwordless SSH Setup (for clients and storage) ---

if [ -n "$${TARGET_NODES_JSON}" ] && [ "$${TARGET_NODES_JSON}" != "[]" ]; then
    echo "Setting up for passwordless SSH..."
    sudo -u ubuntu ansible-galaxy collection install community.crypto

    INVENTORY_FILE="/home/ubuntu/inventory.ini"
    echo "[all_nodes]" > "$INVENTORY_FILE"
    echo "$TARGET_NODES_JSON" | jq -r '.[] | .private_ip' >> "$INVENTORY_FILE"
    chown ubuntu:ubuntu "$INVENTORY_FILE"

    PLAYBOOK_FILE="/home/ubuntu/distribute_keys.yml"
    cat > "$PLAYBOOK_FILE" << EOF
---
- name: Gather Host Keys
  hosts: all_nodes
  gather_facts: false
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /home/ubuntu/.ssh/ansible_admin_key
  tasks:
    - name: Ensure .ssh directory exists
      become: true
      file: { path: "/home/ubuntu/.ssh", state: directory, owner: ubuntu, group: ubuntu, mode: '0700' }
    - name: Ensure SSH key pair exists for each host
      become: true
      community.crypto.openssh_keypair: { path: /home/ubuntu/.ssh/id_rsa, owner: ubuntu, group: ubuntu, mode: '0600' }
    - name: Fetch the public key content from each host
      slurp: { src: /home/ubuntu/.ssh/id_rsa.pub }
      register: host_public_key

- name: Distribute All Keys
  hosts: all_nodes
  gather_facts: false
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /home/ubuntu/.ssh/ansible_admin_key
  tasks:
    - name: Add all public keys to every host
      authorized_key:
        user: ubuntu
        state: present
        key: "{{ hostvars[item].host_public_key.content | b64decode }}"
      loop: "{{ ansible_play_hosts_all }}"
EOF
    chown ubuntu:ubuntu "$PLAYBOOK_FILE"

    echo "Scanning hosts to populate known_hosts..."
    sudo -u ubuntu bash -c "ssh-keyscan -H -f /home/ubuntu/inventory.ini >> /home/ubuntu/.ssh/known_hosts" || true

    echo "Running Ansible playbook to distribute SSH keys..."
    sudo -u ubuntu bash -c "ansible-playbook -i /home/ubuntu/inventory.ini /home/ubuntu/distribute_keys.yml"
    echo "Finished distributing SSH keys."
else
    echo "No clients or storage servers deployed, skipping passwordless SSH setup."
fi

# --- ECGroup Configuration ---

if [ -n "$${ECGROUP_INSTANCES}" ]; then
    echo "Configuring ECGroup..."
    # Build the ECGroup ansible playbook
    cat <<EOF > /tmp/ecgroup.yml
- name: Configure ECGroup from the controller node
  hosts: all
  gather_facts: false
  vars:
    ecgroup_name: ecg
    ansible_user: admin
    ansible_ssh_private_key_file: /home/ubuntu/.ssh/ansible_admin_key
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  become: true
  tasks:
    - name: Create the cluster
      shell: >
        /opt/rozofs-installer/rozo_rozofs_create.sh -n {{ ecgroup_name }} -s "${ECGROUP_NODES}" -t external -d 3
      register: create_cluster_result

    - name: Add CTDB nodes
      shell: >
        /opt/rozofs-installer/rozo_rozofs_ctdb_node_add.sh -n {{ ecgroup_name }} -c "${ECGROUP_NODES}"
      register: ctdb_node_add_result

    - name: Setup DRBD
      shell: >
        /opt/rozofs-installer/rozo_drbd.sh -y -n {{ ecgroup_name }} -d "${ECGROUP_METADATA_ARRAY}"
      register: drbd_result

    - name: Create the array
      shell: >
        /opt/rozofs-installer/rozo_compute_cluster_balanced.sh -y -n {{ ecgroup_name }} -d "${ECGROUP_STORAGE_ARRAY}"
      register: compute_cluster_result

    - name: Propagate the configuration
      shell: >
        /opt/rozofs-installer/rozo_rozofs_install.sh -n {{ ecgroup_name }}
      register: install_result
  run_once: true
EOF

    # Wait for the instances to be ready
    PEERS=($ECGROUP_NODES)
    ALL=true
    for ip in "$${PEERS[@]}"; do
        echo "Waiting for $ip to open port 22..."
        SECONDS=0
        while ! nc -z -w1 "$ip" 22 &>/dev/null; do
            sleep 2
            if (( SECONDS >= 240 )); then
                echo "ERROR: $ip did not open port 22 after 240 seconds."
                ALL=false
                break
            fi
        done
    done

    if [ "$ALL" = true ]; then
        echo "All ECGroup instances are ready, provisioning!"
        sudo ansible-playbook /tmp/ecgroup.yml -i "$${ECGROUP_HOSTS},"
    else
        echo "Could not get all ECGroup instances in a ready state! Aborting configuration."
    fi
    echo "Finished ECGroup configuration."
else
    echo "No ECGroup deployed, skipping ECGroup configuration."
fi

# --- Hammerspace Anvil Configuration ---

if [ -n "${MGMT_IP}" ] && \
   [ "$(wc -w <<< "${STORAGE_INSTANCES}")" -gt 0 ] && \
   [ "$(wc -w <<< "${ECGROUP_INSTANCES}")" -gt 0 ]; then
    echo "Configuring Hammerspace Anvil..."
    cat > /tmp/anvil.yml << EOF
data_cluster_mgmt_ip: "${MGMT_IP}"
hsuser: admin
password: "${ANVIL_ID}"
volume_group_name: "${VG_NAME}"
share_name: "${SHARE_NAME}"
EOF

    NODE_SRC="$${ECGROUP_NODES:-$${STORAGE_INSTANCES}}"

    if [ -n "$NODE_SRC" ]; then
      if [ -n "$${ECGROUP_NODES}" ]; then
        FIRST_IP=$(echo "$NODE_SRC" | awk '{print $1}')
        cat > /tmp/nodes.yml <<EOF
    storages:
      - name: "ECGroup"
        nodeType: "OTHER"
        mgmtIpAddress:
          address: "$FIRST_IP"
        _type: "NODE"
EOF
    
      else
        printf '%s' "$NODE_SRC" | jq -r '
          "storages:",
          map(
            "- name: \"" + .name + "\"\n" +
            "  nodeType: \"OTHER\"\n" +
            "  mgmtIpAddress:\n" +
            "    address: \"" + .private_ip + "\"\n" +
            "  _type: \"NODE\""
          )[]
        ' > /tmp/nodes.yml
      fi
    fi

    printf '%s' 'share:
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

    sudo wget -O /tmp/hs-ansible.yml https://raw.githubusercontent.com/hammerspace-solutions/Terraform-AWS/main/modules/ansible/hs-ansible.yml
    sudo ansible-playbook /tmp/hs-ansible.yml -e @/tmp/anvil.yml -e @/tmp/nodes.yml -e @/tmp/share.yml
    echo "Finished Hammerspace Anvil configuration."
else
    echo "Either storage servers, ecgroup, or Anvil missing. Skipping Anvil configuration."
fi

echo "Ansible controller setup complete."
