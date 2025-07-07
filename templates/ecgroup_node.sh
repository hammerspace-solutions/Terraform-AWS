#!/bin/bash

# Terraform-provided variables (single $ for Terraform interpolation)

SSH_KEYS="${SSH_KEYS}"

set -euo pipefail
shopt -s failglob

# SSH Key Management

if [ -n "$${SSH_KEYS}" ]; then
    mkdir -p "/home/admin/.ssh"
    chmod 700 "/home/admin/.ssh"
    touch "/home/admin/.ssh/authorized_keys"

    # Process keys line by line
    echo "$${SSH_KEYS}" | while read -r key; do
        if [ -n "$${key}" ] && ! grep -qF "$${key}" "/home/admin/.ssh/authorized_keys"; then
            echo "$${key}" >> "/home/admin/.ssh/authorized_keys"
        fi
    done

    chmod 600 "/admin/.ssh/authorized_keys"
    chown -R "admin:admin" "/home/admin/.ssh"
fi