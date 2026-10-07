#!/usr/bin/env bash
# create-class-users.sh — ensure one EBS login per student on the shared class
# instance (9010), with the System Administrator responsibility.
#
#   scripts/create-class-users.sh
#
# Logins are STU01..STUNN (one per sandbox in the inventory) using the password
# from .env (EBS_STUDENT_PASSWORD, falling back to the lab password).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

CLASS_ROW=$(ebs_rows | awk '$1==9010')
[ -n "$CLASS_ROW" ] || { echo "ERROR: class 9010 not in inventory"; exit 1; }
read -r cid cname crole cip <<<"$CLASS_ROW"

vm_running "$cid" || { echo "starting class $cid"; qm start "$cid" >/dev/null 2>&1; }
wait_ssh "$cip" 300 || { echo "ERROR: class instance not reachable at $cip"; exit 1; }

PW="${EBS_STUDENT_PASSWORD:-${OS_ROOT_PASSWORD:-}}"
[ -n "$PW" ] || { echo "ERROR: no student password (EBS_STUDENT_PASSWORD) in .env"; exit 1; }

n=0
for row in $(ebs_rows | awk '$1!=9010{print $1}'); do
  idx=$((row-9100)); user="STU$(printf %02d "$idx")"
  echo "== class login $user =="
  ssh_ebs "$cip" 'bash -s' -- "$user" "$PW" < "$HERE/guest/create-ebs-user.sh" | sed 's/^/   /'
  n=$((n+1))
done
echo "ensured $n class login(s) on $cname"
echo "Test: log in at http://${cip}:8000/ as STU01..STU$(printf %02d "$n")"
