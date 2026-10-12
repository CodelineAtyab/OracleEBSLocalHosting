#!/usr/bin/env bash
# vnc-credentials.sh — student access sheet: each client VM's live IP + VNC info.
#
#   scripts/client/vnc-credentials.sh
#
# Clients are on DHCP (stable while the node stays up). Connect with any VNC
# viewer to <ip>:5900. Default PIN is 29999 (students change it from the desktop
# "Change VNC password" launcher).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

PIN="${VNC_PIN:-29999}"
PORT=5900
echo "EBS lab — student VNC access   (default PIN: $PIN — change after first login)"
printf "%-16s %-6s %-24s %s\n" "CLIENT" "VMID" "VNC ADDRESS" "STATE"
printf "%-16s %-6s %-24s %s\n" "------" "----" "-----------" "-----"
scan=$(arp-scan -I vmbr0 192.168.100.0/24 2>/dev/null)
while read -r id name role ip; do
  [ "$role" = client ] || continue
  mac=$(vm_mac "$id")
  cip=$(echo "$scan" | awk -v m="$mac" 'tolower($2)==m{print $1;exit}')
  st=$(qm status "$id" 2>/dev/null | awk '{print $2}')
  if [ -n "$cip" ]; then addr="$cip:$PORT"; else addr="<no ip>"; fi
  printf "%-16s %-6s %-24s %s\n" "$name" "$id" "$addr" "$st"
done < <(inventory_rows)
