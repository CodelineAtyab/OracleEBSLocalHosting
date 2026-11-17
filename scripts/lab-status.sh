#!/usr/bin/env bash
# lab-status.sh — quick status of the EBS training lab.
#
#   scripts/lab-status.sh
#
# Prints each VM's state and, for running EBS guests, the AppsLogin HTTP code
# (302 = healthy). Client VMs are IP-independent (noVNC), so only VM state shows.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

printf "%-6s %-18s %-8s %-16s %s\n" "VMID" "NAME" "ROLE" "IP" "STATE / AppsLogin"
printf "%-6s %-18s %-8s %-16s %s\n" "----" "----" "----" "--" "----------------"
while read -r id name role ip; do
  st=$(qm status "$id" 2>/dev/null | awk '{print $2}')
  extra=""
  if [ "$role" = ebs ] && [ "$st" = running ]; then
    code=$(ebs_login_code "$ip")
    case "$code" in
      302) extra="AppsLogin=$code  (OK)" ;;
      000) extra="AppsLogin=$code  (not answering yet)" ;;
      *)   extra="AppsLogin=$code  (NOT 302)" ;;
    esac
  fi
  printf "%-6s %-18s %-8s %-16s %s %s\n" "$id" "$name" "$role" "$ip" "${st:-?}" "$extra"
done < <(inventory_rows)

echo
# status portal container (not in inventory.conf - it is an LXC, not a guest)
if [ -f "$HERE/portal/portal.conf" ]; then
  # shellcheck disable=SC1091
  . "$HERE/portal/portal.conf"
  if st=$(pct status "$PORTAL_VMID" 2>/dev/null); then
    printf "%-6s %-18s %-8s %-16s %s\n" "$PORTAL_VMID" "$PORTAL_HOSTNAME" "portal" "$PORTAL_IP" \
      "$(echo "$st" | awk '{print $2}')  http://$PORTAL_IP:$PORTAL_PORT/"
  fi
fi
echo "templates (never started): 9000 ebs1213-golden, 9200 client-template"
if [ -f /etc/systemd/system/ebs-lab-autostart.timer ] && \
   systemctl is-enabled ebs-lab-autostart.timer >/dev/null 2>&1; then
  echo "boot autostart: enabled (systemd timer -> lab-start.sh ~2 min after boot)"
else
  echo "boot autostart: disabled (scripts/install-lab-autostart.sh)"
fi
echo "host RAM:"; free -h | sed -n '2p'
