#!/usr/bin/env bash
# build-golden.sh — REBUILD the golden R12.1.3 template (VM 9000) from the
# pristine appliance media. This is the rare disaster-recovery path; the normal
# path is to restore the exported images (scripts/export-images.sh) or to clone
# the existing template. See README §6–§8.
#
#   scripts/build-golden.sh --yes
#   GUEST_IP=192.168.100.x scripts/build-golden.sh --yes   # if the pristine guest
#                                                          # does not start on .230
#
# WARNING: untested end-to-end. The in-guest fixups (AutoConfig, password
# changes) are appliance-specific — verify against README §6–§8 before trusting.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

MEDIA_DIR="${MEDIA_DIR:-/srv/ebs-media}"
STORAGE="${STORAGE:-local-lvm}"
PLACEHOLDER_IP="${PLACEHOLDER_IP:-192.168.100.230}"
GUEST_IP="${GUEST_IP:-$PLACEHOLDER_IP}"
GOLDEN_VMID=9000

[ "${1:-}" = "--yes" ] || { echo "This recreates VM $GOLDEN_VMID. Re-run with --yes."; exit 1; }

VMDK=$(ls "$MEDIA_DIR"/*.vmdk 2>/dev/null | head -1)
[ -n "$VMDK" ] || { echo "ERROR: no *.vmdk in $MEDIA_DIR (pristine media not found)"; exit 1; }
if qm config "$GOLDEN_VMID" >/dev/null 2>&1; then
  echo "ERROR: VM $GOLDEN_VMID exists. Destroy it first: qm destroy $GOLDEN_VMID --purge"; exit 1
fi
echo "== golden rebuild: media=$VMDK storage=$STORAGE guest_ip=$GUEST_IP =="

echo "== create + import =="
qm create "$GOLDEN_VMID" --name ebs1213-golden --memory 12288 --cores 4 \
  --cpu Westmere --machine pc --bios seabios --balloon 0 \
  --net0 e1000,bridge=vmbr0 --onboot 0
qm importdisk "$GOLDEN_VMID" "$VMDK" "$STORAGE"
qm set "$GOLDEN_VMID" --sata0 "$STORAGE:vm-$GOLDEN_VMID-disk-0"     # SATA, never LSI
qm set "$GOLDEN_VMID" --boot order=sata0
qm start "$GOLDEN_VMID"

echo "== wait for guest SSH at $GUEST_IP (find it via the console if this fails) =="
wait_ssh "$GUEST_IP" 900 || { echo "ERROR: golden guest not reachable at $GUEST_IP"; exit 1; }

echo "== set placeholder IP + /etc/hosts =="
ssh_ebs "$GUEST_IP" 'bash -s' -- "$PLACEHOLDER_IP" < "$HERE/guest/set-ip.sh"

echo "== in-guest first-boot fixups =="
ssh_ebs "$PLACEHOLDER_IP" 'bash -s' < "$HERE/guest/golden-firstboot.sh"

echo "== clean shutdown + templatize =="
ssh_ebs "$PLACEHOLDER_IP" 'shutdown -h now' </dev/null >/dev/null 2>&1 || true
for i in $(seq 1 60); do vm_running "$GOLDEN_VMID" || break; sleep 5; done
vm_running "$GOLDEN_VMID" && { echo "ERROR: golden still running; not templating"; exit 1; }
qm template "$GOLDEN_VMID"
echo "== golden template $GOLDEN_VMID ready. Re-provision sandboxes with scripts/provision-sandbox.sh =="
