#!/bin/bash
#
# Ansible Job: Create ECGroup Share
#
# Reads config_ansible.{ecgroup_share_name, ecgroup_volume_group} from inventory.ini
# and creates the share if missing (idempotent via STATE_FILE).
#
# Behavior:
#   - Requires: jq
#   - If config_ansible missing/invalid OR ecgroup_share_name empty OR ecgroup_volume_group empty: exit 0 (no-op)
#

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/created_shares.txt"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ANSIBLE_LIB_PATH"

echo "--- Starting Create ECGroup Share Job ---"

# 1) Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# --- Helpers ---
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "FATAL: required command '$1' is not installed or not in PATH" >&2
    exit 1
  }
}

# Extract a single var value from [all:vars]
ini_get_var() {
  local key="$1" file="$2"
  awk '
    /^\[all:vars\]$/ {flag=1; next}
    /^\[.*\]$/       {flag=0}
    flag && $0 ~ "^'"$key"' = " { sub(/.*= /, ""); print; exit }
  ' "$file"
}

need_cmd jq

# 2) Parse credentials + config_ansible (gate)
hs_username="$(ini_get_var 'hs_username' "$INVENTORY_FILE" || true)"
hs_password="$(ini_get_var 'hs_password' "$INVENTORY_FILE" || true)"
config_ansible_json="$(ini_get_var 'config_ansible' "$INVENTORY_FILE" || true)"

if [ -z "${config_ansible_json:-}" ]; then
  echo "INFO: No 'config_ansible' in inventory [all:vars]; skipping share creation."
  exit 0
fi
if ! echo "$config_ansible_json" | jq -e . >/dev/null 2>&1; then
  echo "INFO: 'config_ansible' is not valid JSON; skipping share creation."
  exit 0
fi

HS_SHARE_NAME="$(echo "$config_ansible_json" | jq -r '.ecgroup_share_name // ""')"
HS_VOLUME_GROUP="$(echo "$config_ansible_json" | jq -r '.ecgroup_volume_group // ""')"

if [ -z "$HS_SHARE_NAME" ] || [ "$HS_SHARE_NAME" = "null" ]; then
  echo "INFO: config_ansible.ecgroup_share_name not set; skipping share creation."
  exit 0
fi
if [ -z "$HS_VOLUME_GROUP" ] || [ "$HS_VOLUME_GROUP" = "null" ]; then
  echo "INFO: config_ansible.ecgroup_volume_group not set; skipping share creation (confine objective requires VG)."
  exit 0
fi

echo "Parsed hs_username: ${hs_username:-<unset>}"
echo "Parsed hs_password: ${hs_password:-<unset>}"
echo "Using ECGroup share name: $HS_SHARE_NAME"
echo "Using ECGroup volume group: $HS_VOLUME_GROUP"

# 3) Parse hammerspace (mgmt IP) and ensure ECGroup nodes exist (for sanity)
all_hammerspace=""
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[hammerspace\]$ ]]; then 
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[hammerspace\]$ ]]; then 
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    all_hammerspace+="$line"$'\n'
  fi
done < "$INVENTORY_FILE"

all_ecgroup_servers=""
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[ecgroup_nodes\]$ ]]; then 
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[ecgroup_nodes\]$ ]]; then 
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    all_ecgroup_servers+="$ip"$'\n'
  fi
done < "$INVENTORY_FILE"

all_hammerspace="$(echo "$all_hammerspace" | grep -v '^$' | sort -u || true)"
all_ecgroup_servers="$(echo "$all_ecgroup_servers" | grep -v '^$' | sort -u || true)"

echo "Parsed hammerspace: $all_hammerspace"
echo "Parsed ecgroup_servers: $all_ecgroup_servers"

if [ -z "$all_ecgroup_servers" ] || [ -z "$all_hammerspace" ]; then
  echo "No ECGroup Cluster or Hammerspace Anvil found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip="$(echo "$all_hammerspace" | head -1)"

# 4) Idempotence: skip if share already created
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"
if grep -q -F -x "$HS_SHARE_NAME" "$STATE_FILE"; then
  echo "Share $HS_SHARE_NAME already created. Exiting."
  exit 0
fi

# 5) Build share JSON body safely with jq
SHARE_BODY="$(jq -n --arg name "$HS_SHARE_NAME" --arg vg "$HS_VOLUME_GROUP" '
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
}
')"

# 6) One-off playbook to create share
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

echo "Running Ansible playbook to create ECGroup share '$HS_SHARE_NAME'..."
ansible-playbook "$tmp_playbook"

# 7) Update state and cleanup
echo "$HS_SHARE_NAME" >> "$STATE_FILE"
rm -f "$tmp_playbook"

echo "--- Create ECGroup Share Job Complete ---"
