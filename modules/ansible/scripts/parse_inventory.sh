#!/bin/bash

INV=$1
CFG=$(awk '/^\[all:vars\]$/{f=1;next} /^\[.*\]$/{f=0} f && /^config_ansible = /{sub(/^[^=]*= /,"");print;exit}' "$INV")

# Get Group -> Share (tab separated)

echo "$CFG" | jq -r '
  select(.!=null)
  | (.volume_groups // {}) 
  | to_entries[] 
  | "\(.key)\t\(.value.share)"
'

# Get the share names (one per line)

echo "$CFG" | jq -r '
  select(.!=null)
  | (.volume_groups // {})
  | to_entries[]
  | .value.share
'
# JSON map of group -> share

echo "$CFG" | jq '
  select(.!=null)
  | (.volume_groups // {})
  | with_entries(.value = .value.share)
'

# Include the option ecgroup_share_name if set

echo "$CFG" | jq -r '
  select(.!=null)
  | [
      (if (.ecgroup_share_name // null) then {"group":"ecgroup","share":.ecgroup_share_name} else empty end),
      ((.volume_groups // {}) | to_entries[] | {group:.key, share:.value.share})
    ]
  | .[] | "\(.group)\t\(.share)"
'
