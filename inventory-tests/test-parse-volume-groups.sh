#!/usr/bin/env bash
# Portable test parser for non-ECGroup volume_groups -> node mapping
# - No associative arrays, no mapfile (works on old bash)
# - Robust [all:vars] extractor, CR stripping, locale set

set -euo pipefail
LC_ALL=C

STRICT=0
if [[ "${1:-}" == "--strict" ]]; then STRICT=1; shift || true; fi
INV="${1:-/var/ansible/trigger/inventory.ini}"
[ -f "$INV" ] || { echo "ERROR: inventory file not found: $INV" >&2; exit 1; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found" >&2; exit 1; }; }
need_cmd jq; need_cmd awk; need_cmd sed; need_cmd tr

warns=0; errs=0
warn(){ echo "WARNING: $*" >&2; warns=$((warns+1)); }
err(){  echo "ERROR: $*"   >&2; errs=$((errs+1)); }

# Anchored extractor; returns JSON on the same line as key
ini_get_var_json_oneline() {
  local key="$1" file="$2"
  awk '
    /^\[all:vars\]$/ {f=1; next}
    /^\[.*\]$/       {f=0}
    f && $0 ~ "^'"$key"'[[:space:]]*=" { sub(/.*=[[:space:]]*/, ""); print; exit }
  ' "$file" | tr -d '\r'
}

# --- parse [storage_servers] preserving order ---
STORAGE_NAMES=()
{
  section=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^\[(.*)\][[:space:]]*$ ]]; then section="${BASH_REMATCH[1]}"; continue; fi
    [[ "$section" != "storage_servers" ]] && continue
    [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] || continue
    ip=$(awk '{print $1}' <<<"$line")
    name=$(grep -oE 'node_name="[^"]+"' <<<"$line" | sed -E 's/node_name="(.*)"/\1/' || true)
    [ -z "$name" ] && name="${ip//./-}"
    STORAGE_NAMES+=("$name")
  done < "$INV"
}

if [ ${#STORAGE_NAMES[@]} -eq 0 ]; then
  err "No hosts found under [storage_servers] in: $INV"
  [ $STRICT -eq 1 ] && exit 2 || exit 0
fi

# --- get config_ansible JSON (one-line) ---
CONFIG_JSON="$(ini_get_var_json_oneline 'config_ansible' "$INV" || true)"
if [ -z "${CONFIG_JSON:-}" ]; then
  err "config_ansible not found under [all:vars]"
  [ $STRICT -eq 1 ] && exit 2 || exit 0
fi
if ! echo "$CONFIG_JSON" | jq -e . >/dev/null 2>&1; then
  err "config_ansible is not valid JSON"
  [ $STRICT -eq 1 ] && exit 2 || exit 0
fi

# Show what we parsed (useful debug)
echo
echo "=== Extracted config_ansible (pretty) ==="
echo "$CONFIG_JSON" | jq .

# Verify volume_groups exists
if ! echo "$CONFIG_JSON" | jq -e 'has("volume_groups") and (.volume_groups|type=="object") and ((.volume_groups|keys|length) > 0)' >/dev/null 2>&1; then
  err "config_ansible.volume_groups missing or empty"
  [ $STRICT -eq 1 ] && exit 2 || exit 0
fi

# helpers
dedupe_preserve(){ awk 'NF && !seen[$0]++'; }
index_to_name() {
  local idx="$1" total="${#STORAGE_NAMES[@]}"
  [[ "$idx" =~ ^[0-9]+$ ]] || { warn "Non-numeric index: '$idx'"; return 1; }
  local zero=$((idx - 1))
  if (( zero < 0 || zero >= total )); then warn "Index $idx out of range (1..$total)"; return 1; fi
  printf '%s\n' "${STORAGE_NAMES[$zero]}"
}
in_csv(){ case ",$1," in *,"$2",*) return 0;; *) return 1;; esac; }

resolve_group() {
  local group="$1" stack_csv="$2"
  if in_csv "$stack_csv" "$group"; then err "Cycle in add_groups at '$group' (stack: $stack_csv)"; echo ""; return 1; fi
  local new_stack="$stack_csv"; [ -n "$new_stack" ] && new_stack="$new_stack,$group" || new_stack="$group"

  if ! echo "$CONFIG_JSON" | jq -e --arg g "$group" '.volume_groups|has($g)' >/dev/null; then
    warn "Missing volume_groups entry: '$group'"; echo ""; return 0
  fi

  local vols_json adds_json nodes=""
  vols_json="$(echo "$CONFIG_JSON" | jq -cr --arg g "$group" '.volume_groups[$g].volumes // []')"
  adds_json="$( echo "$CONFIG_JSON" | jq -cr --arg g "$group" '.volume_groups[$g].add_groups // []')"

  # direct nodes
  while IFS= read -r idx; do
    [ -z "$idx" ] && continue
    local name; if name="$(index_to_name "$idx")"; then nodes="${nodes}${name}"$'\n'; fi
  done < <(jq -r '.[]|tostring' <<<"$vols_json")

  # recurse
  while IFS= read -r child; do
    [ -z "$child" ] && continue
    local sub; sub="$(resolve_group "$child" "$new_stack" || true)"
    [ -n "$sub" ] && nodes="${nodes}${sub}"
  done < <(jq -r '.[]' <<<"$adds_json")

  printf '%s' "$nodes" | dedupe_preserve
}

# --- stream group keys directly from jq (no bash arrays) ---

echo
echo "=== Storage Servers (index → name) ==="
for ((i=0;i<${#STORAGE_NAMES[@]};i++)); do
  printf "  %d → %s\n" "$((i+1))" "${STORAGE_NAMES[$i]}"
done

echo
echo "=== Volume Group Resolution ==="

groups_count=0
warnings_before=$warns
errors_before=$errs

# Stream groups; avoid arrays / mapfile
echo "$CONFIG_JSON" | jq -r '.volume_groups | keys[]' | while IFS= read -r g; do
  [ -z "$g" ] && continue
  groups_count=$((groups_count+1))

  idx_list="$(echo "$CONFIG_JSON" | jq -r --arg k "$g" '(.volume_groups[$k].volumes // []) | join(",")')"
  add_list="$(echo "$CONFIG_JSON" | jq -r --arg k "$g" '(.volume_groups[$k].add_groups // []) | join(",")')"
  [ -z "$idx_list" ] && idx_list="(none)"
  [ -z "$add_list" ] && add_list="(none)"

  resolved="$(resolve_group "$g" "")" || true
  resolved_line="$(printf '%s' "$resolved" | tr '\n' ',' | sed 's/,$//')"
  [ -z "$resolved_line" ] && resolved_line="(none)"

  echo "- group: $g"
  echo "    volumes (1-based): $idx_list"
  echo "    add_groups:        $add_list"
  echo "    resolved nodes:    $resolved_line"
done

echo
echo "=== Summary ==="
echo "  Warnings: $warns"
echo "  Errors:   $errs"
echo "  Strict:   ${STRICT:-0}"
echo "  Groups:   $groups_count"
