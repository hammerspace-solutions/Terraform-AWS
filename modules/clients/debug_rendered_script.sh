#!/bin/bash

# Update system and install required packages
#
# You can modify this based upon your needs

sudo apt-get -y update
sudo apt-get install -y pip git bc nfs-common screen net-tools fio

# Upgrade all the installed packages

sudo apt-get -y upgrade

# WARNING!!
# DO NOT MODIFY ANYTHING BELOW THIS LINE OR INSTANCES MAY NOT START CORRECTLY!
# ----------------------------------------------------------------------------

TARGET_USER='ubuntu'
TARGET_HOME='/home/ubuntu'
SSH_KEYS='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC07v6lqSClHrUmP10bVCrTpEg3NUjjm5TEuievmpVaLKNjDKST0juDU0TaSrhLAf/5RTFvCYeL8dWxn6w4CcFBMzblHJ3EFR13+M+0dLeZWv+RV/1Ag/X/jNIJLQ9ozQYQyTqKJaVQJimV/BKuGRmsjYljUrTqIqFAFEy1CzeT6Of0Cb5YnK5BM9i00MbK6FNb+QMl0r+62uI/cJj5jQSnpvKCJtlix1yIH2itzf3KcuDazDe5XHsu4i78zNjhs6U8qb4b84uMF0wzJ/iPsBbyiSBQoJBVQf4PDqDU15UPxjZ/lipblq0igXoLYFv/XaqeQxfbafHGS6UCLMFqETZ4HBuCeYIx8MG5KDtQCEyK9kMSyG65VK8Fj7eWUWAISHP4bA0nRIez+40wIfoiTv4yoTRt49zRuQgIZ3CPnnl2NzuvMTo6pnp8spR+mLNfrp5sB46gE58AmsihXt6hrR/Al9ooK3xbsO0UAW5kYLQhURUH8XJCrBmB3ep7/NpYmEHvydFIzKBDQjvOG4PZKJtNkgYjO0Uw3R/M2SeNhkL+3l8iOZU1HqRfxmR8YT7XbiV6v1j+OVS9OnO8ABtq3/VLY4/uIJKQF0tJDKiei0+z7dL3hX/lJmKtMHuxAWzLR36HDII0i58jIDAazJ029i2WoQPEDjgmnFzKH4gfleT9iQ==
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJUNuIQ6+g6FRdgupLy6LWvxqEuVSLzAGw8OdhoQp1ji berat.ulualan@Berats-MacBook-Pro.local
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCqUjqN8+Y2ziKzpYQvU0J/Wy/wY41ItY1VfQXp/Ju/iCHQEPTQyTZSJi57LnUgz/qFlc0O0neErw4pJAVgaDzqsq36sahFne/vuUnbtttl7DRadMDxrPutozZFlIfLT0fJZXyYGGDiEWjPwZuaf7tlm1uqMgE6owqi8sMO0iYnXAp0FqG4gS5jw0eDYhEh/rq/IXowLghF+Q/zqEbYLgLDnmi0owgRRU+T5y/MHBe7DWd7+I8OR29Yd40quYAO3jNBK3NbAIqylPBCJzDbefH5gJCi7eLI2+T99Gdq6aKszIxKysB2wR7Baq/MwTxQXYpYsFbXGCGxUjJqFWHRPra9Ru6POiBidvMxu6hAzIHXhTbhc6gNAh8sEBVbHMC5u1ET7+Mo7iVJHBBzWyxrrVaWyygs5xcIFya3tfTzhcKj1pADSPhrEYXAWEor5/iFKiWUvUaVO9tGr23o9+5xKv9zBD2y+sZBVV43aDVMNigUQeH5khiCXAtzgntBrx4dAExhZ469dLVZTmfqqH19vJ0rBG6mcv6Z8XQhFU0w0G3rWvub+bs2aYqc0XkAQPIewTeGqSvU8qhmFmt0uTrJPdulkz5GAXtBOl475jKxh5h5gbNQQJFCzCHKq45XqGbL99cRduY4nGI80I6PxAGzeNK7rd1jiaSyS/Se3HdtUcepuQ== jonathan.flynn@hammerspace.com
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClMyzDJ1Omo5UogSKPhS3NCsgCPzsJbX0HhmO7PLYr0OLdzzOINuDfYj4eVAQEvn0oa5AE3MozriBX9TsBZSNiJlQ6b5Wlh5mu29OO2o2+ZNxc1dwkhwDm//wuIFioXNyADiCeOK26MZ0ujSGH0ZJ2eVbtU545XuZlxWTrOWxpZW9c7TfwRqYBODjypMprBmigDKhPV7Z70lKAhegCdUkUX+ECxSVPLNxJ35y/+luSUXMI4WrwM4W1uWV/3r8Kb1SFxy695aqw/4KUevWSrwFP2W8TSX8RQ3LwWRgJSimZUz8Iu+p25ufK9IUN59iDdywpc6lmhRXuw+uqrlbLvrT/If3GTVDytYYDp8zdCoBYStZqldT6cJ9PMknnlT7ZGBcsFETo8IQCT2D8e8OaTtj+TE+J+1Zu21dBCwKpI04DpU+fyXQjRIhOpN5+6WB4CTgPUzfPmEo4gCGpV5Ew1CoWMJ+kHs4wHJK4gjNWJxVmM2LUTzu4VyT/Sun9HKkk3P0= mike.kade@Mike-Kades-MacBook-Pro.local
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF/0oPU4yqAZ7U37EH/d1t09Mgzr/Iv2MJUAPf+knnrG keith.mannthey@mctodd-MacBook-Pro'
ALLOW_ROOT='true'
TIER0=''
ROOT_USER='root'
ROOT_HOME='/root'

# Get rid of fingerprint checking on ssh
# We need this in case somebody wants to run automated scripts. Otherwise,
# they will have to modify their scripts to answer the stupid question of
# "are you sure"?

sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
sudo tee -a /etc/ssh/sshd_config > /dev/null <<'EOF'
    PermitRootLogin yes
    PubkeyAuthentication yes
EOF

# Restart the sshd

systemctl restart ssh

# SSH Key Management

if [ -n "${SSH_KEYS}" ]; then
    mkdir -p "${TARGET_HOME}/.ssh"
    chmod 700 "${TARGET_HOME}/.ssh"
    touch "${TARGET_HOME}/.ssh/authorized_keys"

    # Process keys one by one to avoid multi-line issues

    echo "${SSH_KEYS}" | while read -r key; do
        if [ -n "${key}" ] && ! grep -qF "${key}" "${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "${key}" >> "${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "${TARGET_USER}":"${TARGET_USER}" "${TARGET_HOME}/.ssh"
fi

# --- SSH Key Management for additional keys (This is ONLY for root) ---

if [ -n "${SSH_KEYS}" ] && [ "${ALLOW_ROOT}" = "true" ]; then
    echo "Starting SSH Key Management Deployment for ${ROOT_USER}"

    if [ ! -d "${ROOT_HOME}/.ssh" ]; then
      mkdir -p "${ROOT_HOME}/.ssh"
      chmod 700 "${ROOT_HOME}/.ssh"
      touch "${ROOT_HOME}/.ssh/authorized_keys"
    fi
    
    # Process keys line by line
    
    echo "${SSH_KEYS}" | while read -r key; do
        if [ -n "${key}" ] && ! grep -qF "${key}" "${ROOT_HOME}/.ssh/authorized_keys"; then
            echo "${key}" >> "${ROOT_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "${ROOT_HOME}/.ssh/authorized_keys"
    chown -R "${ROOT_USER}":"${ROOT_USER}" "${ROOT_HOME}/.ssh"
    echo "Ending SSH Key Management Deployment for ${ROOT_USER}"
fi

# Build NFS mountpoint

sudo mkdir -p /mnt/nfs-test
sudo chmod 777 /mnt/nfs-test

# If Tier0 is enabled, then work on the nvme drives

if [ -n "${TIER0}" ]; then
    echo "Tier0 is enabled (${TIER0}). Installing mdadm & detecing NVMe..."

    # Load packages needed for Tier0

    echo "Loading Tier0 packages"
    sudo apt -y update
    sudo apt -y install mdadm nvme-cli jq nfs-kernel-server sysstat

    # Read each matching NVMe device into one array element per line
    
    mapfile -t NVME_DEVICES < <(
      nvme list | awk '/Amazon EC2 NVMe Instance Storage/ {print $1}'
    )
    echo "Found ${#NVME_DEVICES[@]} NVMe device(s): ${NVME_DEVICES[*]}"

    # If none, bail out cleanly

    if [ "${#NVME_DEVICES[@]}" -eq 0 ]; then
        echo "No NVMe instance-store devices found; skipping RAID creation."
        exit 0
    fi

    # Determine minimum count per RAID level

    TOTAL_DEVICES="${#NVME_DEVICES[@]}"

    case "${TIER0}" in
    raid-0)
        MIN_REQUIRED=2
        raid_options="--level=0 --raid-devices=${TOTAL_DEVICES}"
        ;;
    raid-5)
        MIN_REQUIRED=3
        raid_options="--level=5 --raid-devices=${TOTAL_DEVICES}"
        ;;
    raid-6)
        MIN_REQUIRED=4
        raid_options="--level=6 --raid-devices=${TOTAL_DEVICES}"
        ;;
      *)
        echo "Error: Invalid TIER0 value ${TIER0}." 2>&1
        exit 1
        ;;
    esac

    if [ "${TOTAL_DEVICES}" -lt "${MIN_REQUIRED}" ]; then
        echo "Error: Insufficient devices (${TOTAL_DEVICES}) for ${TIER0} (needs ≥ ${MIN_REQUIRED}). Skipping."
        exit 1
    fi

    # Build the RAID device

    RAID_NUM="${TIER0#raid-}"
    echo "Creating RAID${RAID_NUM} on ${TOTAL_DEVICES} devices…"
    sudo mdadm --create --verbose /dev/md0 \
     ${raid_options} ${NVME_DEVICES[*]}

    # Format, mount, permissions

    sudo mkfs.xfs /dev/md0
    sudo mkdir -p /tier0
    sudo mount /dev/md0 /tier0
    sudo chown -R "${TARGET_USER}":"${TARGET_USER}" /tier0
    sudo chmod 777 /tier0

    # Persist in fstab & mdadm config

    echo "/dev/md0 /tier0 xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
    sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
    sudo update-initramfs -u

    # Configure NFS exports

    echo "/tier0 *(rw,sync,no_root_squash,secure,mp,no_subtree_check)" | sudo tee -a /etc/exports

    # Optimize NFS config

    sudo tee /etc/nfs.conf.d/local.conf > /dev/null <<'EOF'
[nfsd]
threads = 128
vers3=y
vers4.0=n
vers4.1=n
vers4.2=y
rdma=y
rdma-port=20049

[mountd]
manage-gids = 1
EOF

    # Increase NFS threads

    sudo tee /etc/default/nfs-kernel-server > /dev/null <<'EOF'
RPCNFSDCOUNT=128
RPCMOUNTDOPTS="--manage-gids"
EOF

    # Start services

    sudo systemctl restart nfs-kernel-server

else
    echo "Tier0 is not enabled on this machine"
fi

# Reboot
sudo reboot
