#!/usr/bin/env bash
# provision-sandbox.sh — configure or repair one EBS sandbox (from the Proxmox host).
#
#   scripts/provision-sandbox.sh <vmid>
#
# Idempotent. Ensures the guest is running, has the inventory IP + /etc/hosts
# (with ARPCHECK=no so OL6 ifup cannot refuse the address), the single-node
# javacache setting, FND_NODES.SERVER_ADDRESS = its own IP, EBS started, and
# AppsLogin = 302. Handles the fresh-clone ".230 placeholder" boot.
#
# SAFETY: every address it touches is MAC-verified against the VM's NIC, so it
# can never reconfigure a different host that happens to hold the placeholder.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

PLACEHOLDER_IP="${PLACEHOLDER_IP:-192.168.100.230}"
VMID="${1:?usage: provision-sandbox.sh <vmid>}"

row=$(inventory_rows | awk -v id="$VMID" '$1==id')
[ -n "$row" ] || { echo "ERROR: VMID $VMID not in $INVENTORY"; exit 1; }
read -r id name role ip <<<"$row"
[ "$role" = ebs ] || { echo "ERROR: $id role=$role (expected ebs)"; exit 1; }
mymac=$(vm_mac "$id")
[ -n "$mymac" ] || { echo "ERROR: cannot read network MAC for VM $id"; exit 1; }
echo "== provision $name ($id): target ip=$ip mac=$mymac =="

# --- safety: never touch an address answered by a different NIC -------------
for cand in "$ip" "$PLACEHOLDER_IP"; do
  [ -n "$cand" ] || continue
  holder=$(ip_mac "$cand")
  if [ -n "$holder" ] && [ "$holder" != "$mymac" ]; then
    echo "ERROR: $cand is held by another host (MAC $holder) — refusing to touch it."
    echo "       Free that address (stop the VM using it) or fix the address plan."
    exit 1
  fi
done

locate() {  # echo the MAC-verified IP this VM answers on ("" if none)
  local cand
  for cand in "$ip" "$PLACEHOLDER_IP"; do
    [ -n "$cand" ] || continue
    ip_is_vm "$cand" "$id" || continue
    ssh_ebs "$cand" true </dev/null 2>/dev/null && { echo "$cand"; return; }
  done
}

vm_running "$id" || { echo "starting VM $id"; qm start "$id" >/dev/null 2>&1; }

# Give a freshly started/cloned guest time to boot before assuming it is stuck.
cur=""
for i in $(seq 1 24); do cur=$(locate); [ -n "$cur" ] && break; sleep 5; done
if [ -z "$cur" ]; then
  echo "guest not answering after 2 min; hard-resetting $id ..."
  qm reset "$id" >/dev/null 2>&1
  for i in $(seq 1 36); do cur=$(locate); [ -n "$cur" ] && break; sleep 5; done
fi
[ -n "$cur" ] || { echo "ERROR: $name unreachable at $ip or $PLACEHOLDER_IP — check its console"; exit 1; }
echo "guest reachable at $cur"

# Always (re)assert addressing; if still on the placeholder, reboot to apply.
ssh_ebs "$cur" 'bash -s' -- "$ip" < "$HERE/guest/set-ip.sh" >/dev/null 2>&1
if [ "$cur" != "$ip" ]; then
  echo "== rebooting to apply $ip (ARPCHECK=no) =="
  ssh_ebs "$cur" 'reboot' </dev/null >/dev/null 2>&1 || true
  ok=0
  for i in $(seq 1 60); do
    ip_is_vm "$ip" "$id" && ssh_ebs "$ip" true </dev/null 2>/dev/null && { ok=1; break; }
    sleep 5
  done
  [ "$ok" = 1 ] || { echo "ERROR: $name still not up at $ip after reboot"; exit 1; }
fi

echo "== in-guest provisioning (start EBS + FND_NODES + verify) =="
ssh_ebs "$ip" 'bash -s' < "$HERE/guest/provision.sh"
