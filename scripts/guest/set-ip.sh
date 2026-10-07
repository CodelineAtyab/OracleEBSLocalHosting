#!/bin/bash
# Runs INSIDE an EBS guest as root: set the static IPv4 + hostname mapping.
#   usage: ssh root@<guest> 'bash -s -- <IP>' < set-ip.sh
set -u
TARGET="${1:?usage: set-ip.sh <ip>}"
IFCFG=/etc/sysconfig/network-scripts/ifcfg-eth0

set_kv() {  # set_kv KEY VALUE
  if grep -q "^$1=" "$IFCFG"; then sed -i "s#^$1=.*#$1=$2#" "$IFCFG"; else echo "$1=$2" >> "$IFCFG"; fi
}
set_kv BOOTPROTO static
set_kv IPADDR    "$TARGET"
set_kv NETMASK   255.255.255.0
set_kv GATEWAY   192.168.100.1
set_kv DEVICE    eth0
set_kv ONBOOT    yes
set_kv TYPE      Ethernet
# OL6 ifup refuses a static IP if its ARP probe thinks it is in use (false
# positives caused real outages here). Disable the check for this lab.
sed -i '/^ARPCHECK=/d' "$IFCFG"; echo 'ARPCHECK=no' >> "$IFCFG"

sed -i "s/^192\.168\.100\.[0-9]\+[[:space:]]\+ebs\.example\.com.*/$TARGET\tebs.example.com ebs/" /etc/hosts
grep -q 'ebs\.example\.com' /etc/hosts || printf "%s\tebs.example.com ebs\n" "$TARGET" >> /etc/hosts

echo "=== $IFCFG ==="; cat "$IFCFG"
echo "=== /etc/hosts ==="; cat /etc/hosts
