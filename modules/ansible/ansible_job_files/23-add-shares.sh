#!/bin/bash
#
# Ansible Job: Create Share(s)
#
# Requires: jq
# Behavior: If inventory lacks config_ansible, log and exit 0 (no-op).
# Idempotence: tracked via STATE_FILE (one line per created share name).
#

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/created_shares.txt"

# --- Source the function library (if required by your env) ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ANSIBLE_LIB_PATH"

echo "--- Starting Create Share(s) Job ---"

# 1) Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# --- Utilities ---
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "FATAL: required command '$1' is not installed or not in PATH" >&2
    exit 1
  }
}

# Extract a single var line value from [all:vars]
ini_get_var() {
  local key="$1" file="$2"
  awk '
    /^\[all:vars\]$/ {flag=1; next}
    /^\[.*\]$/       {flag=0}
    flag && $0 ~ "^'"$key"' = " { sub(/.*= /, ""); print; exit }
  ' "$file"
}

# Ensure jq exists
need_cmd jq

# 2) Parse needed vars from inventory
hs_username="$(ini_get_var 'hs_username' "$INVENTORY_FILE")"
hs_password="$(ini_get_var 'hs_password' "$INVENTORY_FILE")"
config_ansible_json="$(ini_get_var 'config_ansible' "$INVENTORY_FILE" || true)"

# If no config_ansible, exit 0 (no-op)
if [ -z "${config_ansible_json:-}" ]; then
  echo "INFO: No 'config_ansible' defined in inventory [all:vars]; skipping share creation."
  exit 0
fi

echo "Parsed hs_username: $hs_username"
echo "Parsed hs_password: $hs_password"
echo "Found config_ansible JSON (length: ${#config_ansible_json})"

# 3) Parse hammerspace and storage_servers sections

# --- hammerspace ---
all_hammerspace=""
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[hammerspace\]$ ]]; then
    flag="hammerspace"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[hammerspace\]$ ]]; then
    flag="0"
  fi
  if [ "$flag" = "hammerspace" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    all_hammerspace+="$line"$'\n'
  fi
done < "$INVENTORY_FILE"

# --- storage_servers ---
all_storage_servers=""
storage_map=() # Array of "IP:name"
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[storage_servers\]$ ]]; then
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[storage_servers\]$ ]]; then
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "${ip//./-}")
    all_storage_servers+="$ip"$'\n'
    storage_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

all_hammerspace=$(echo "$all_hammerspace" | grep -v '^$' | sort -u || true)
all_storage_servers=$(echo "$all_storage_servers" | grep -v '^$' | sort -u || true)

echo "Parsed hammerspace:"
echo "$all_hammerspace"
echo "Parsed storage_servers:"
echo "$all_storage_servers"

if [ -z "$all_storage_servers" ] || [ -z "$all_hammerspace" ]; then
  echo "No storage_servers or hammerspace found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

# 4) Helper to build share JSON body (confine-to-<vg>)
build_share_body() {
  local share_name="$1" vg="$2"
  jq -n --arg name "$share_name" --arg vg "$vg" '
  {
    name: $name,
    path: ("/" + $name),
    maxShareSize: "0",
    alertThreshold: "90",
    maxShareSizeType: "TB",
    smbAliases: [],
    exportOptions: [{subnet:"*", rootSquash:"false", accessPermissions:"RW"}],
    shareSnapshots: [],
    shareObjectives: [
      {objective:{name:"no-atime"}, applicability:"TRUE"},
      {objective:{name:("confine-to-" + $vg)}, applicability:"TRUE"}
    ],
    smbBrowsable: "true",
    shareSizeLimit: "0"
  }'
}

# 5) Determine target pairs "<share_name>::<vg_target>" from config_ansible
declare -a PAIRS=()
while IFS= read -r key; do
  share_name="$(jq -r --arg k "$key" '.volume_groups[$k].share // ($k + "_share")' <<<"$config_ansible_json")"
  vg_target="$(jq -r  --arg k "$key" '(.volume_groups[$k].volume_group // $k)' <<<"$config_ansible_json")"
  PAIRS+=("${share_name}::${vg_target}")
done < <(jq -r '(.volume_groups // {}) | keys[]' <<<"$config_ansible_json")

if [ "${#PAIRS[@]}" -eq 0 ]; then
  echo "INFO: config_ansible.volume_groups is empty; nothing to create. Exiting."
  exit 0
fi

# 6) Ensure state file exists
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

# 7) For each pair, create share if missing (idempotent)
for pair in "${PAIRS[@]}"; do
  HS_SHARE_NAME="${pair%%::*}"
  HS_VOLUME_GROUP="${pair##*::}"

  if grep -q -F -x "$HS_SHARE_NAME" "$STATE_FILE"; then
    echo "Share $HS_SHARE_NAME already created. Skipping."
    continue
  fi

  echo "Creating share '$HS_SHARE_NAME' confined to VG '$HS_VOLUME_GROUP' ..."

  SHARE_BODY="$(build_share_body "$HS_SHARE_NAME" "$HS_VOLUME_GROUP")"

  tmp_playbook="$(mktemp)"
  cat > "$tmp_playbook" <<EOF
---
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$hs_username"
    hs_password: "$hs_password"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    share_name: "$HS_SHARE_NAME"
    share: $SHARE_BODY

  tasks:
    - name: Get all shares
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/shares"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: shares_response
      until: shares_response.status == 200
      retries: 30
      delay: 10

    - name: Set fact for share exists
      set_fact:
        share_exists: "{{ share_name in (shares_response.json | map(attribute='name') | list) }}"

    - name: Create share if missing
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/shares"
        method: POST
        body: '{{ share }}'
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 202
        body_format: json
        validate_certs: false
        timeout: 30
      register: share_create
      until: share_create.status == 202
      retries: 30
      delay: 10
      when: not share_exists

    - name: Wait for completion
      uri:
        url: "{{ share_create.location }}"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        status_code: 200
        body_format: json
        timeout: 30
      register: _result
      until: _result.json.status == "COMPLETED"
      retries: 30
      delay: 10
      when: share_create.status == 202
EOF

  echo "Running Ansible playbook to create share '$HS_SHARE_NAME'..."
  ansible-playbook "$tmp_playbook"

  # Update state
  echo "$HS_SHARE_NAME" >> "$STATE_FILE"

  # Clean up
  rm -f "$tmp_playbook"
done

echo "--- Create Share Job Complete ---"
