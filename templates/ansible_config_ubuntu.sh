#!/bin/bash

# Update system and install required packages
#
# You can modify this based upon your needs


sudo apt-get -y update
sudo apt-get install -y pip git bc ansible screen net-tools jq

cat > /tmp/anvil.yml << EOF
data_cluster_mgmt_ip: "${MGMT_IP}"
hsuser: admin 
password: "${ANVIL_ID}"
volume_group_name: "${VG_NAME}"
share_name: "${SHARE_NAME}"
EOF

echo '${STORAGE_INSTANCES}'

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

# Upgrade all the installed packages

sudo apt-get -y upgrade

sudo git clone https://github.com/BeratUlualan/HS-Terraform.git /tmp/HS-Terraform
sudo ansible-playbook /tmp/HS-Terraform/hs-aistudio.yml -e @/tmp/anvil.yml -e @/tmp/nodes.yml -e @/tmp/share.yml


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

# Reboot
#sudo reboot
