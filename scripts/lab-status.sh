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
echo "templates (never started): 9000 ebs1213-golden, 9200 client-template"
echo "host RAM:"; free -h | sed -n '2p'
