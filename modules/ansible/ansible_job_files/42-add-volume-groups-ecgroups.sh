#!/bin/bash
#
# Ansible Job: Add Volume Group for ECGroup
#
# Creates/updates a Hammerspace Volume Group for all ECGroup nodes based on:
#   config_ansible.ecgroup_volume_group: <string>  # VG name to create/update
#   config_ansible.ecgroup_share_name:  <string>   # optional (not used here)
#
# Behavior:
#   - Requires: jq
#   - If config_ansible is missing/invalid OR ecgroup_volume_group unset: exit 0 (no-op)
#   - Includes ALL hosts listed under [ecgroup_nodes] in inventory.ini
#   - Idempotence per VG via a state file
#

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_DIR="/var/run/ansible_jobs_status/ecgroup_vg_states"   # one file per VG

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ANSIBLE_LIB_PATH"

echo "--- Starting Add Volume Group Job for ECGroup ---"

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

# 2) Parse creds + config_ansible (gate)
hs_username="$(ini_get_var 'hs_username' "$INVENTORY_FILE" || true)"
hs_password="$(ini_get_var 'hs_password' "$INVENTORY_FILE" || true)"
config_ansible_json="$(ini_get_var 'config_ansible' "$INVENTORY_FILE" || true)"

if [ -z "${config_ansible_json:-}" ]; then
  echo "INFO: No 'config_ansible' found in inventory [all:vars]; skipping ECGroup VG."
  exit 0
fi
if ! echo "$config_ansible_json" | jq -e . >/dev/null 2>&1; then
  echo "INFO: 'config_ansible' is not valid JSON; skipping ECGroup VG."
  exit 0
fi

# Pull VG name; must be non-empty to proceed
ecgroup_vg_name="$(echo "$config_ansible_json" | jq -r '.ecgroup_volume_group // ""')"
if [ -z "$ecgroup_vg_name" ] || [ "$ecgroup_vg_name" = "null" ]; then
  echo "INFO: 'ecgroup_volume_group' not set in config_ansible; nothing to do. Exiting."
  exit 0
fi

ecgroup_share_name="$(echo "$config_ansible_json" | jq -r '.ecgroup_share_name // ""')"
echo "Using ECGroup VG name: $ecgroup_vg_name"
[ -n "$ecgroup_share_name" ] && echo "ECGroup share name (unused here): $ecgroup_share_name"

# 3) Parse hammerspace and ecgroup_nodes (include ALL ecgroup nodes)
all_hammerspace=""
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[hammerspace\]$ ]]; then flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[hammerspace\]$ ]]; then flag="0"
  elif [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    all_hammerspace+="$line"$'\n'
  fi
done < "$INVENTORY_FILE"

ec_map=()   # "IP:node_name"
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[ecgroup_nodes\]$ ]]; then flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[ecgroup_nodes\]$ ]]; then flag="0"
  elif [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "${ip//./-}")
    ec_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

hs_disp=$(echo "$all_hammerspace" | grep -v '^$' | tr '\n' ' ' || true)
ec_names_disp=$(printf "%s\n" "${ec_map[@]}" | cut -d: -f2- | tr '\n' ' ')

echo "Parsed hammerspace: $hs_disp"
echo "Parsed ecgroup_nodes (names): $ec_names_disp"

if [ -z "$hs_disp" ] || [ "${#ec_map[@]}" -eq 0 ]; then
  echo "No ECGroup nodes or Hammerspace Anvil found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip="$(echo "$all_hammerspace" | head -1)"

# 4) Build nodes list (ALL ecgroup node names; ordered unique)
declare -A seen=()
nodes_for_vg=()
for entry in "${ec_map[@]}"; do
  name="${entry#*:}"
  if [[ -z "${seen[$name]+x}" ]]; then
    nodes_for_vg+=("$name")
    seen["$name"]=1
  fi
done

echo "ECGroup VG '$ecgroup_vg_name' will include nodes: ${nodes_for_vg[*]}"

# 5) Idempotence check (per VG)
mkdir -p "$STATE_DIR"
state_file="$STATE_DIR/${ecgroup_vg_name}.txt"
touch "$state_file"
current_sorted="$(printf "%s\n" "${nodes_for_vg[@]}" | sort | tr '\n' ',')"
saved_sorted="$(sort "$state_file" 2>/dev/null | tr '\n' ',' || true)"

if [ "$current_sorted" = "$saved_sorted" ]; then
  echo "VG '$ecgroup_vg_name' already up to date. Exiting."
  exit 0
fi

# 6) Build vg_node_locations JSON from node names
vg_node_locations="$(printf "%s\n" "${nodes_for_vg[@]}" | jq -R -s '
  split("\n") | map(select(length>0)) |
  map({ "_type":"NODE_LOCATION", "node": {"_type": "NODE", "name": . }})
')"

# 7) One-off playbook to create/update VG
tmp_playbook="$(mktemp)"
cat > "$tmp_playbook" <<EOF
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$hs_username"
    hs_password: "$hs_password"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    volume_group_name: "$ecgroup_vg_name"
    vg_node_locations: $vg_node_locations

  tasks:
    - name: Get all volume groups
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: volume_groups_response
      until: volume_groups_response.status == 200
      retries: 30
      delay: 10

    - name: Set fact for VG exists
      set_fact:
        vg_exists: "{{ volume_group_name in (volume_groups_response.json | map(attribute='name') | list) }}"

    - name: Create volume group if missing
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups"
        method: POST
        body: >-
          {{
            {
              "name": volume_group_name,
              "_type": "VOLUME_GROUP",
              "expressions": [
                {
                  "operator": "IN",
                  "locations": vg_node_locations
                }
              ]
            }
          }}
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 200
        body_format: json
        validate_certs: false
        timeout: 30
      when: not vg_exists
      register: vg_create
      until: vg_create.status == 200
      retries: 30
      delay: 10

    - name: Update volume group if exists
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups/{{ volume_group_name }}"
        method: PUT
        body: >-
          {{
            {
              "name": volume_group_name,
              "_type": "VOLUME_GROUP",
              "expressions": [
                {
                  "operator": "IN",
                  "locations": vg_node_locations
                }
              ]
            }
          }}
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 200
        body_format: json
        validate_certs: false
        timeout: 30
      when: vg_exists
      register: vg_update
      until: vg_update.status == 200
      retries: 30
      delay: 10
EOF

echo "Running Ansible playbook to manage ECGroup VG '$ecgroup_vg_name'..."
ansible-playbook "$tmp_playbook"

# 8) Update state and cleanup
printf "%s\n" "${nodes_for_vg[@]}" | sort > "$state_file"
rm -f "$tmp_playbook"

echo "--- Manage ECGroup Volume Group Job Complete ---"
