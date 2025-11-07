#!/bin/bash

awk '/^\[all:vars\]$/{f=1;next} /^\[.*\]$/{f=0} f && /^config_ansible = /{sub(/.*= /,"");print;exit}' inventory.ini | jq .

