#!/bin/bash

CONFIG_JSON="$(awk '/^\[all:vars\]$/{f=1;next} /^\[.*\]$/{f=0} f && /^config_ansible = /{sub(/.*= /,"");print;exit}' inventory.ini)"
[ -z "$CONFIG_JSON" ] && { echo "config_ansible not found"; exit 1; }

echo "$CONFIG_JSON" | jq -r '
  .volume_groups
  | to_entries
  | .[]
  | .key as $k
  | $k, (.value.share // ($k + "_share")) as $share
  | ($share + " -> " + (.value.volume_group // $k))
' | paste - -   # format as "share_name -> volume_group"
