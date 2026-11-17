#!/usr/bin/env bash
# portal-add-host.sh - add another Proxmox endpoint to the status board.
#
#   scripts/portal/portal-add-host.sh <label> <api-url> <token-file>
#
# Example:
#   scripts/portal/portal-add-host.sh site-b https://192.168.100.50:8006 /root/site-b.token
#
# On the second Proxmox host, create a read-only token first:
#   pveum user add portal@pve --comment "EBS lab status portal (read-only)"
#   pveum acl modify / --users portal@pve --roles PVEAuditor
#   pveum user token add portal@pve collector --privsep 0 --output-format json
# The file passed here must contain the full token string, exactly as Proxmox
# prints it:   portal@pve!collector=<uuid>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/portal.conf"

label="${1:-}"
url="${2:-}"
token_file="${3:-}"

if [ -z "$label" ] || [ -z "$url" ] || [ -z "$token_file" ]; then
  echo "usage: $0 <label> <api-url> <token-file>" >&2
  exit 2
fi
case "$label" in
  *[!a-z0-9-]*) echo "label must be lowercase letters, digits and '-'" >&2; exit 2 ;;
esac
if [ ! -s "$token_file" ]; then
  echo "token file '$token_file' is missing or empty" >&2
  exit 2
fi
if ! pct status "$PORTAL_VMID" >/dev/null 2>&1; then
  echo "container $PORTAL_VMID does not exist - run portal-install.sh first" >&2
  exit 1
fi

printf '==> pushing token for %s\n' "$label"
pct push "$PORTAL_VMID" "$token_file" "/etc/lab-portal/${label}.token" --perms 0600

printf '==> updating endpoints.conf\n'
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
pct exec "$PORTAL_VMID" -- cat /etc/lab-portal/endpoints.conf 2>/dev/null \
  | awk -v l="$label" 'NF==3 && $1!=l' >"$tmp" || true
printf '%s %s /etc/lab-portal/%s.token\n' "$label" "$url" "$label" >>"$tmp"
pct push "$PORTAL_VMID" "$tmp" /etc/lab-portal/endpoints.conf --perms 0600

printf '==> restarting collector\n'
pct exec "$PORTAL_VMID" -- systemctl restart lab-portal-collect.service
sleep 2
pct exec "$PORTAL_VMID" -- python3 /opt/lab-portal/collect.py --once
