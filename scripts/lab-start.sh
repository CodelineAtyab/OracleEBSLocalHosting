#!/usr/bin/env bash
# lab-start.sh — bring the EBS training lab up.
#
#   scripts/lab-start.sh              # everything: EBS guests + client VMs
#   scripts/lab-start.sh ebs          # EBS guests only (boot + start DB/app tier)
#   scripts/lab-start.sh clients      # client VMs only
#
# Boots the EBS VMs, waits for SSH, starts the Oracle DB and the app tier
# (startvisiondb.sh + startapps.sh) on each, waits until AppsLogin returns 302,
# then boots the client VMs. Idempotent: already-running services are skipped.
#
# Concurrency is capped by $CONCURRENCY (default 4) to avoid HDD thrash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

# ---------- single-VM workers (invoked via xargs) ---------------------------
ONE_EBS() {
  local id="$1" name="$2" role="$3" ip="$4"
  {
    echo "=== $name ($id) @ $ip  $(date) ==="
    vm_running "$id" || qm start "$id"
    if wait_ssh "$ip" 300; then
      ssh_ebs "$ip" '
        pgrep -f "[p]mon_EBSDB" >/dev/null || su - oracle -c "/u01/install/VISION/scripts/startvisiondb.sh"
        pgrep -f "[o]c4j"       >/dev/null || su - oracle -c "/u01/install/APPS/scripts/startapps.sh"
        true'
      echo "$name: EBS start issued"
    else
      echo "$name: ERROR — no SSH at $ip after 300s"
    fi
  } >>"$LOGDIR/$name.log" 2>&1
}

CHECK_EBS() {
  local id="$1" name="$2" role="$3" ip="$4" code=000 i
  for i in $(seq 1 60); do
    code=$(ebs_login_code "$ip"); [ "$code" = 302 ] && break; sleep 10
  done
  printf "  %-16s %-16s %s\n" "$name" "$ip" "$code"
}

ONE_CLIENT() {
  local id="$1" name="$2" role="$3"
  vm_running "$id" || qm start "$id" >/dev/null 2>&1
  echo "  $name: VM started"
}

case "${1:-}" in
  --one-ebs)    shift; ONE_EBS "$@";    exit 0 ;;
  --check-ebs)  shift; CHECK_EBS "$@";  exit 0 ;;
  --one-client) shift; ONE_CLIENT "$@"; exit 0 ;;
esac

# ---------- main ------------------------------------------------------------
WHAT="${1:-all}"
CONCURRENCY="${CONCURRENCY:-4}"

EBS_LIST=$(mktemp); CLI_LIST=$(mktemp)
{ [ "$WHAT" = clients ] || ebs_rows;    } > "$EBS_LIST"
{ [ "$WHAT" = ebs ]     || client_rows; } > "$CLI_LIST"
trap 'rm -f "$ASKPASS" "$EBS_LIST" "$CLI_LIST"' EXIT

n_ebs=$(wc -l < "$EBS_LIST"); n_cli=$(wc -l < "$CLI_LIST")
echo "== lab-start: $n_ebs EBS VM(s), $n_cli client VM(s), concurrency $CONCURRENCY =="

if [ "$n_ebs" -gt 0 ]; then
  echo "== 1/3  booting EBS VMs + starting Oracle DB/app tier =="
  xargs -P "$CONCURRENCY" -L1 "$HERE/lab-start.sh" --one-ebs < "$EBS_LIST"
  echo "   per-VM logs: $LOGDIR/<name>.log"
  echo "== 2/3  waiting for AppsLogin = 302 (up to ~10 min) =="
  printf "  %-16s %-16s %s\n" "VM" "IP" "AppsLogin"
  xargs -P "$CONCURRENCY" -L1 "$HERE/lab-start.sh" --check-ebs < "$EBS_LIST"
fi

if [ "$n_cli" -gt 0 ]; then
  echo "== 3/3  starting client VMs =="
  xargs -P "$CONCURRENCY" -L1 "$HERE/lab-start.sh" --one-client < "$CLI_LIST"
fi

echo; echo "== summary =="
qm list | awk 'NR>1{printf "  %-6s %-18s %s\n",$1,$2,$3}'
echo "Done. (EBS guests keep hostname ebs.example.com; clients use DHCP + noVNC.)"
