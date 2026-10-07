#!/usr/bin/env bash
# lab-stop.sh — cleanly shut the EBS training lab down.
#
#   scripts/lab-stop.sh              # stop all guests, leave the host running
#   scripts/lab-stop.sh --poweroff   # stop all guests, then power off the host
#
# The EBS guests do NOT honour ACPI, so qm shutdown would hang; each is stopped
# from inside (stopapps.sh -> stopvisiondb.sh -> shutdown -h now). Client VMs are
# disposable and are hard-stopped. Unrelated VM 100 is shut down gracefully.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

STOP_EBS() {
  local id="$1" name="$2" role="$3" ip="$4"
  if vm_running "$id"; then
    echo "  $name ($ip): stopapps -> stopvisiondb -> shutdown -h now"
    timeout 220 ssh_ebs "$ip" '
        su - oracle -c "/u01/install/APPS/scripts/stopapps.sh"       >/dev/null 2>&1
        su - oracle -c "/u01/install/VISION/scripts/stopvisiondb.sh" >/dev/null 2>&1
        sync; /sbin/shutdown -h now' >/dev/null 2>&1
  else
    echo "  $name: already stopped"
  fi
}
case "${1:-}" in --stop-ebs) shift; STOP_EBS "$@"; exit 0 ;; esac

POWEROFF=0
[ "${1:-}" = "--poweroff" ] && POWEROFF=1
CONCURRENCY="${CONCURRENCY:-3}"

EBS_LIST=$(mktemp)
ebs_rows > "$EBS_LIST"
trap 'rm -f "$ASKPASS" "$EBS_LIST"' EXIT

echo "== lab-stop =="
echo "== 0) unrelated VM 100 (ubuntu-server-vm): graceful shutdown =="
if vm_running 100; then
  timeout 150 qm shutdown 100 --timeout 120 >/dev/null 2>&1 || qm stop 100 >/dev/null 2>&1
  echo "  100 done"
else
  echo "  100 not running"
fi

echo "== 1) EBS guests: clean Oracle DB/app stop then OS shutdown =="
xargs -P "$CONCURRENCY" -L1 "$HERE/lab-stop.sh" --stop-ebs < "$EBS_LIST"

echo "== 2) client guests: qm stop (disposable) =="
while read -r id name role ip; do
  [ "$role" = client ] || continue
  vm_running "$id" && qm stop "$id" >/dev/null 2>&1 && echo "  $name stopped"
done < <(inventory_rows)

echo "== 3) waiting for all VMs to stop (up to ~10 min) =="
for i in $(seq 1 120); do
  n=$(qm list | awk 'NR>1 && $3=="running"' | wc -l)
  [ "$n" -eq 0 ] && break
  sleep 5
done
qm list | awk 'NR>1 && $3=="running"{printf "  still running: %s %s\n",$1,$2}'
if [ "$(qm list | awk 'NR>1 && $3=="running"' | wc -l)" -eq 0 ]; then
  echo "  all guests stopped"
fi

sync
if [ "$POWEROFF" = 1 ]; then
  echo "== powering off host now =="
  systemctl poweroff
else
  echo
  echo "All guests stopped. Power off the host with:  systemctl poweroff"
fi
