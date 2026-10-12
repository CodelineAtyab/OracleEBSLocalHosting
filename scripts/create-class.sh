#!/usr/bin/env bash
# create-class.sh — create the shared class instance (9010) from the golden
# template. Used by the restore/rebuild path. Idempotent-ish (refuses if 9010
# already exists).
#
#   scripts/create-class.sh [ip]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

CLASS_VMID=9010
IP="${1:-${CLASS_IP:-192.168.100.223}}"

qm config 9000 >/dev/null 2>&1 || { echo "ERROR: golden template 9000 not found"; exit 1; }
if qm config "$CLASS_VMID" >/dev/null 2>&1; then
  echo "class $CLASS_VMID already exists — nothing to do"; exit 0
fi

# free the .230 placeholder that a fresh clone boots on
for c in $(client_rows | awk '{print $1}'); do qm stop "$c" >/dev/null 2>&1; done

echo "== cloning class $CLASS_VMID from golden 9000 (full) =="
qm clone 9000 "$CLASS_VMID" --name ebs1213-class --full 1 >/dev/null || { echo "clone failed"; exit 1; }
qm set "$CLASS_VMID" --memory 12288 --cores 4 --onboot 0 >/dev/null

grep -q "^$CLASS_VMID[[:space:]]" "$INVENTORY" || \
  printf "%-5s %-17s %-8s %s\n" "$CLASS_VMID" "ebs1213-class" "ebs" "$IP" >> "$INVENTORY"

echo "== provisioning class =="
"$HERE/provision-sandbox.sh" "$CLASS_VMID"

for c in $(client_rows | awk '{print $1}'); do qm start "$c" >/dev/null 2>&1; done
echo "== class ready at $IP =="
