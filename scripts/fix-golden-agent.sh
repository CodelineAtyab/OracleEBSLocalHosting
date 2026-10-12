#!/usr/bin/env bash
# fix-golden-agent.sh — install qemu-guest-agent into the golden template (9000)
# and enable the agent channel, so every FUTURE clone reports its IP in Proxmox.
#
#   scripts/fix-golden-agent.sh
#
# The OL6 appliance's yum repos are dead, so the agent RPM is fetched on the host
# and pushed into the guest.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

GOLD=9000
RPM="${QGA_RPM:-/srv/ebs-media/client/tools/qemu-guest-agent-el6.rpm}"
RPM_URL="${QGA_URL:-https://yum.oracle.com/repo/OracleLinux/OL6/latest/x86_64/getPackage/qemu-guest-agent-0.12.1.2-2.503.el6.x86_64.rpm}"

[ -s "$RPM" ] || { echo "fetching agent rpm"; curl -fsSL -o "$RPM" "$RPM_URL" || { echo "download failed"; exit 1; }; }
qm config "$GOLD" >/dev/null 2>&1 || { echo "ERROR: golden $GOLD not found"; exit 1; }

echo "== stop clients (free the .230 placeholder) =="
for c in $(client_rows | awk '{print $1}'); do qm stop "$c" >/dev/null 2>&1; done

CONF="/etc/pve/qemu-server/$GOLD.conf"
if grep -q '^template:' "$CONF"; then
  tmpf=$(mktemp); grep -v '^template:' "$CONF" > "$tmpf"; cat "$tmpf" > "$CONF"; rm -f "$tmpf"; echo "template flag removed"
fi
lvchange -prw "pve/base-${GOLD}-disk-0" >/dev/null 2>&1 && echo "base LV -> writable"
qm set "$GOLD" --agent 1 >/dev/null 2>&1 && echo "agent=1 set"

echo "== booting golden =="
qm start "$GOLD" >/dev/null 2>&1
mac=$(vm_mac "$GOLD"); ip=""
for i in $(seq 1 60); do
  ip=$(arp-scan -I vmbr0 192.168.100.0/24 2>/dev/null | awk -v m="$mac" 'tolower($2)==m{print $1;exit}')
  [ -n "$ip" ] && break; sleep 5
done
[ -n "$ip" ] || { echo "ERROR: golden got no IP"; exit 1; }
echo "golden at $ip"
ok=0
for i in $(seq 1 60); do ssh_ebs "$ip" true </dev/null 2>/dev/null && { ok=1; break; }; sleep 5; done
[ "$ok" = 1 ] || { echo "ERROR: no SSH to golden at $ip"; exit 1; }

echo "== installing agent =="
ssh_ebs "$ip" 'cat > /tmp/qga.rpm' < "$RPM" 2>/dev/null
ssh_ebs "$ip" 'bash -s' < "$HERE/guest/install-qga-ol6.sh" 2>&1 | sed 's/^/  /'

echo "== shutdown + re-template =="
ssh_ebs "$ip" 'shutdown -h now' </dev/null >/dev/null 2>&1 || true
for i in $(seq 1 60); do vm_running "$GOLD" || break; sleep 5; done
vm_running "$GOLD" && { echo "ERROR: golden still running"; exit 1; }
timeout 60 qm template "$GOLD" >/dev/null 2>&1 && echo "golden is a template again (agent=1)"

echo "== restart clients =="
for c in $(client_rows | awk '{print $1}'); do qm start "$c" >/dev/null 2>&1; done
echo "done."
