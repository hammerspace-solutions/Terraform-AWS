#!/bin/bash
#
# Ansible Job: Manage Volume Groups (per config_ansible)
#
# Creates/updates Hammerspace Volume Groups from inventory.ini config_ansible.
# - Requires: jq
# - If config_ansible is absent/invalid: prints message and exits 0 (no-op)
# - Interprets "volumes" as 1-based indexes into [storage_servers] order
# - Per-VG idempotence tracked under STATE_DIR
#

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_DIR="/var/run/ansible_jobs_status/vg_states"  # one file per VG

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ANSIBLE_LIB_PATH"

echo "--- Starting Manage Volume Group Job ---"

# 1) Verify inventory exists
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

# Extract single var value from [all:vars]
ini_get_var() {
  local key="$1" file="$2"
  awk '
    /^\[all:vars\]$/ {flag=1; next}
    /^\[.*\]$/       {flag=0}
    flag && $0 ~ "^'"$key"' = " { sub(/.*= /, ""); print; exit }
  ' "$file"
}

need_cmd jq

# 2) Parse credentials and config_ansible JSON gate
hs_username="$(ini_get_var 'hs_username' "$INVENTORY_FILE" || true)"
hs_password="$(ini_get_var 'hs_password' "$INVENTORY_FILE" || true)"
config_ansible_json="$(ini_get_var 'config_ansible' "$INVENTORY_FILE" || true)"

if [ -z "${config_ansible_json:-}" ]; then
  echo "INFO: No 'config_ansible' found in inventory [all:vars]; skipping VG management."
  exit 0
fi
if ! echo "$config_ansible_json" | jq -e . >/dev/null 2>&1; then
  echo "INFO: 'config_ansible' is not valid JSON; skipping VG management."
  exit 0
fi

# Ensure volume_groups exists and non-empty
vg_keys=$(echo "$config_ansible_json" | jq -r '(.volume_groups // {}) | keys[]?' || true)
if [ -z "$vg_keys" ]; then
  echo "INFO: config_ansible.volume_groups is empty; nothing to manage. Exiting."
  exit 0
fi

echo "Parsed hs_username: ${hs_username:-<unset>}"
echo "Parsed hs_password: ${hs_password:-<unset>}"
echo "Found volume groups: $(echo "$vg_keys" | tr '\n' ' ')"

# 3) Parse hammerspace and storage_servers (PRESERVE ORDER for storage_map!)
#    We DO NOT sort storage_map — indices refer to listed order.
all_hammerspace=""
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[hammerspace\]$ ]]; then flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[hammerspace\]$ ]]; then flag="0"
  elif [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    all_hammerspace+="$line"$'\n'
  fi
done < "$INVENTORY_FILE"

storage_map=()   # array of "IP:node_name"
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[storage_servers\]$ ]]; then flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[storage_servers\]$ ]]; then flag="0"
  elif [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "${ip//./-}")
    storage_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

# For diagnostics, compute lists (display only)
all_storage_servers_disp=$(printf "%s\n" "${storage_map[@]}" | awk -F: '{print $1}' | tr '\n' ' ')
all_storage_names_disp=$(printf "%s\n" "${storage_map[@]}" | cut -d: -f2- | tr '\n' ' ')
all_hammerspace_disp=$(echo "$all_hammerspace" | grep -v '^$' | tr '\n' ' ' || true)

echo "Parsed hammerspace: $all_hammerspace_disp"
echo "Parsed storage_servers (IPs): $all_storage_servers_disp"
echo "Parsed storage_servers (names): $all_storage_names_disp"

if [ -z "$all_hammerspace_disp" ] || [ "${#storage_map[@]}" -eq 0 ]; then
  echo "No hammerspace or storage_servers found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

# 4) Helpers for VG management

# Build node name list (ordered, deduped) from 1-based indexes into storage_map
# Args: list of indexes (strings or ints)
nodes_from_indexes() {
  local -a idxs=("$@")
  local -A seen=()
  local out=()
  for idx in "${idxs[@]}"; do
    if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
      echo "WARNING: volume index '$idx' is not numeric; skipping." >&2
      continue
    fi
    local zero=$((idx - 1))
    if (( zero < 0 || zero >= ${#storage_map[@]} )); then
      echo "WARNING: volume index '$idx' out of range (1..${#storage_map[@]}); skipping." >&2
      continue
    fi
    local name="${storage_map[$zero]#*:}"
    if [[ -z "${seen[$name]+x}" ]]; then
      out+=("$name")
      seen["$name"]=1
    fi
  done
  printf "%s\n" "${out[@]}"
}

# Build JSON array for NODE_LOCATIONs from a list of node names (stdin)
vg_locations_nodes_json_from_stdin() {
  jq -R -s '
    split("\n") | map(select(length>0)) |
    map({ "_type":"NODE_LOCATION", "node": {"_type": "NODE", "name": . }})
  '
}

# Build JSON array for VOLUME_GROUP references from a list (stdin) of group names
vg_locations_groups_json_from_stdin() {
  jq -R -s '
    split("\n") | map(select(length>0)) |
    map({ "_type":"VOLUME_GROUP", "name": . })
  '
}

# 5) Ensure state dir
mkdir -p "$STATE_DIR"

# 6) Iterate each volume group in config_ansible
changed_any=0
while IFS= read -r group_key; do
  # Determine VG name
  vg_name=$(echo "$config_ansible_json" | jq -r --arg k "$group_key" '(.volume_groups[$k].volume_group // $k)')

  # Extract volumes (list of strings/numbers)
  mapfile -t vol_indexes < <(echo "$config_ansible_json" | jq -r --arg k "$group_key" '
      (.volume_groups[$k].volumes // [])[] | tostring
  ')

  # Extract add_groups (list of strings)
  mapfile -t add_groups < <(echo "$config_ansible_json" | jq -r --arg k "$group_key" '
      (.volume_groups[$k].add_groups // [])[]?
  ')

  if [ "${#vol_indexes[@]}" -eq 0 ] && [ "${#add_groups[@]}" -eq 0 ]; then
    echo "INFO: Group '$group_key' has no 'volumes' and no 'add_groups'; skipping."
    continue
  fi

  # Map indexes -> node names (ordered, unique)
  mapfile -t nodes_for_vg < <(nodes_from_indexes "${vol_indexes[@]}")
  # Build NODE_LOCATION JSON (may be empty [])
  vg_node_locations="$(printf "%s\n" "${nodes_for_vg[@]}" | vg_locations_nodes_json_from_stdin)"
  # Build VOLUME_GROUP references JSON (may be empty [])
  vg_group_refs="$(printf "%s\n" "${add_groups[@]}" | vg_locations_groups_json_from_stdin)"

  # Combine to final "locations" array: nodes + group refs
  vg_locations="$(jq -c --argjson a "$vg_node_locations" --argjson b "$vg_group_refs" -n '$a + $b')"

  # For state comparison, we include both node names and add_groups (sorted)
  current_items_sorted="$(
    { printf "%s\n" "${nodes_for_vg[@]}"; printf "%s\n" "${add_groups[@]}"; } \
      | grep -v '^$' | sort | tr '\n' ','
  )"

  state_file="$STATE_DIR/${vg_name}.txt"
  touch "$state_file"
  saved_items_sorted="$(sort "$state_file" 2>/dev/null | tr '\n' ',' || true)"

  if [ "$current_items_sorted" = "$saved_items_sorted" ]; then
    echo "VG '$vg_name' already up to date. Skipping."
    continue
  fi

  echo "VG '$vg_name' needs update. Nodes: ${nodes_for_vg[*]}  AddGroups: ${add_groups[*]:-<none>}"

  # One-off playbook to create/update VG
  tmp_playbook="$(mktemp)"
  cat > "$tmp_playbook" <<EOF
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$hs_username"
    hs_password: "$hs_password"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    volume_group_name: "$vg_name"
    vg_locations: $vg_locations

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
                  "locations": vg_locations
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
                  "locations": vg_locations
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

  echo "Running Ansible playbook for VG '$vg_name'..."
  ansible-playbook "$tmp_playbook"

  # Update per-VG state (unsorted, one name per line)
  { printf "%s\n" "${nodes_for_vg[@]}"; printf "%s\n" "${add_groups[@]}"; } | sort > "$state_file"

  # Cleanup
  rm -f "$tmp_playbook"
  changed_any=1
done <<< "$vg_keys"

if [ "$changed_any" -eq 0 ]; then
  echo "All volume groups already up to date. Exiting."
else
  echo "--- Manage Volume Group Job Complete ---"
fi
