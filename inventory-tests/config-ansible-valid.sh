#!/bin/bash

CONFIG_JSON="$(awk '/^\[all:vars\]$/{f=1;next} /^\[.*\]$/{f=0} f && /^config_ansible = /{sub(/.*= /,"");print;exit}' inventory.ini)"
[ -z "$CONFIG_JSON" ] && { echo "config_ansible not found"; exit 1; }

echo "$CONFIG_JSON" | jq -e '
  def strings_array: type=="array" and (all(.[]; type=="string"));
  def group_ok:
    (has("volumes") and (.volumes|strings_array)) and
    ((has("share")|not) or (.share|type=="string")) and
    ((has("volume_group")|not) or (.volume_group|type=="string")) and
    ((has("add_groups")|not) or (.add_groups|strings_array));

  type=="object" and
  has("allow_root") and (.allow_root|type=="boolean") and
  has("volume_groups") and (.volume_groups|type=="object") and
  ([.volume_groups[] | group_ok] | all)
' >/dev/null \
&& echo "config_ansible: STRUCTURE OK" \
|| echo "config_ansible: STRUCTURE INVALID"
