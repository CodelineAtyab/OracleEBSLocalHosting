#!/usr/bin/env bash
# reset-ebs-password.sh — reset EBS application-login passwords on the class.
#
#   scripts/reset-ebs-password.sh <user> <password>   # one user
#   scripts/reset-ebs-password.sh --students          # all STU users -> .env value
#
# Uses FND_USER_PKG.UPDATEUSER (admin reset; no old password required), then
# verifies with FND_USER_PKG.VALIDATELOGIN.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

CLASS_ROW=$(ebs_rows | awk '$1==9010'); [ -n "$CLASS_ROW" ] || { echo "ERROR: class 9010 not in inventory"; exit 1; }
read -r cid cname crole cip <<<"$CLASS_ROW"
vm_running "$cid" || { echo "starting class"; qm start "$cid" >/dev/null 2>&1; }
wait_ssh "$cip" 300 || { echo "ERROR: class not reachable at $cip"; exit 1; }

set_one() {
  ssh_ebs "$cip" 'bash -s' -- "$1" "$2" < "$HERE/guest/set-ebs-password.sh" | grep -v '^$'
}

case "${1:-}" in
  --students)
    PW="${EBS_STUDENT_PASSWORD:-}"
    [ -n "$PW" ] || { echo "ERROR: EBS_STUDENT_PASSWORD not set in .env"; exit 1; }
    n=0
    for row in $(ebs_rows | awk '$1!=9010{print $1}'); do
      u="STU$(printf %02d $((row-9100)))"; echo "== $u =="; set_one "$u" "$PW"; n=$((n+1))
    done
    echo "reset $n student password(s) to the .env value"
    ;;
  "")
    echo "usage: reset-ebs-password.sh <user> <password> | --students"; exit 1 ;;
  *)
    set_one "$1" "${2:?usage: reset-ebs-password.sh <user> <password>}" ;;
esac
