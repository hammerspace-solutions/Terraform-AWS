#!/bin/bash

CONFIG_JSON="$(awk '/^\[all:vars\]$/{f=1;next} /^\[.*\]$/{f=0} f && /^config_ansible = /{sub(/.*= /,"");print;exit}' inventory.ini)"
[ -z "$CONFIG_JSON" ] && { echo "config_ansible not found"; exit 1; }
echo "$CONFIG_JSON" | jq -e . >/dev/null && echo "JSON OK" || echo "Invalid JSON"

