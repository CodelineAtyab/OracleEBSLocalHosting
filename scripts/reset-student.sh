#!/usr/bin/env bash
# reset-student.sh — wipe a student's sandbox back to the pristine template state.
#
#   scripts/reset-student.sh <student|vmid>            # EBS sandbox only
#   scripts/reset-student.sh <student|vmid> --client   # also reset the client VM
#
# <student> is the number (e.g. 1 for stu01); you may also pass the sandbox VMID
# (e.g. 9101). It destroys the linked clone(s) and re-clones from the templates
# (9000 / 9200), then re-provisions the sandbox (IP, /etc/hosts, FND_NODES,
# start EBS, verify 302). The VMIDs and the Proxmox user/ACLs are unchanged, so
# nothing else needs touching.
#
# NOTE: this is destructive — any work stored in the sandbox/client is lost.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

ARG="${1:?usage: reset-student.sh <student|vmid> [--client]}"
WITH_CLIENT=0; [ "${2:-}" = "--client" ] && WITH_CLIENT=1

if [ "$ARG" -ge 9000 ] 2>/dev/null; then EBS="$ARG"; N=$((EBS-9100)); else N="$ARG"; EBS=$((9100+N)); fi
CLI=$((9200+N))

row=$(inventory_rows | awk -v id="$EBS" '$1==id')
[ -n "$row" ] || { echo "ERROR: sandbox VMID $EBS not in $INVENTORY"; exit 1; }
read -r id name role ip <<<"$row"
[ "$role" = ebs ] || { echo "ERROR: $EBS role=$role (expected ebs)"; exit 1; }
qm config 9000 >/dev/null 2>&1 || { echo "ERROR: golden template 9000 missing"; exit 1; }
echo "== reset student $N: sandbox $EBS ($name) ip=$ip  client=$([ "$WITH_CLIENT" = 1 ] && echo "yes ($CLI)" || echo no) =="

# Free the .230 placeholder that a fresh clone boots on (clients often hold it).
echo "== stopping client VMs (frees the .230 placeholder) =="
for c in $(client_rows | awk '{print $1}'); do qm stop "$c" >/dev/null 2>&1; done

echo "== re-cloning sandbox from golden 9000 =="
qm stop "$EBS" --skiplock 1 >/dev/null 2>&1 || true
qm destroy "$EBS" --purge 1 >/dev/null 2>&1 || true
qm clone 9000 "$EBS" --name "$name" --full 0 >/dev/null || { echo "ERROR: clone $EBS failed"; exit 1; }
qm set "$EBS" --memory 12288 --cores 4 --onboot 0 >/dev/null

if [ "$WITH_CLIENT" = 1 ]; then
  crow=$(inventory_rows | awk -v id="$CLI" '$1==id')
  read -r cid cname crole cip <<<"$crow"
  echo "== re-cloning client $CLI ($cname) from template 9200 =="
  qm stop "$CLI" --skiplock 1 >/dev/null 2>&1 || true
  qm destroy "$CLI" --purge 1 >/dev/null 2>&1 || true
  qm clone 9200 "$CLI" --name "$cname" --full 0 >/dev/null || { echo "ERROR: clone $CLI failed"; exit 1; }
  qm set "$CLI" --memory 2048 --cores 2 --onboot 0 >/dev/null
fi

echo "== provisioning the fresh sandbox =="
"$HERE/provision-sandbox.sh" "$EBS"

echo "== starting client VMs =="
for c in $(client_rows | awk '{print $1}'); do qm start "$c" >/dev/null 2>&1 || true; done
echo "== reset complete: student $N sandbox $EBS restored and healthy =="
