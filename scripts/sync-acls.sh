#!/usr/bin/env bash
# sync-acls.sh — ensure every student has their Proxmox user + PVEVMUser ACLs.
#
#   scripts/sync-acls.sh
#
# Repairs the failure where a student "cannot see their VM" in the Proxmox UI:
# `qm destroy --purge` (used by reset/add) DELETES the VM's ACL, so after a
# re-clone the student loses access to /vms/91NN — this re-asserts it.
# Also creates the stuNN@pve user if it is missing (password from .env).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

n=0
for row in $(ebs_rows | awk '$1!=9010{print $1}'); do
  idx=$((row-9100)); num=$(printf %02d "$idx"); u="stu$num@pve"
  ebs="$row"; cli=$((row+100))          # 9101 -> 9201
  if pveum user list 2>/dev/null | grep -q "$u"; then
    :
  else
    pveum user add "$u" --password "$PVE_PASSWORD" --comment "EBS lab student $idx" >/dev/null 2>&1 \
      && echo "  created user $u"
  fi
  acl_ensure "$u" "$ebs"
  acl_ensure "$u" "$cli"
  echo "  $u -> /vms/$ebs + /vms/$cli"
  n=$((n+1))
done
echo "synced ACLs for $n student(s)"
