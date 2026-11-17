#!/usr/bin/env bash
# install-lab-autostart.sh — bring the whole lab up automatically after a host boot.
#
#   scripts/install-lab-autostart.sh            # install + enable (idempotent)
#   scripts/install-lab-autostart.sh --status   # show whether it is installed
#   scripts/install-lab-autostart.sh --remove   # disable + delete the units
#
# Installs two systemd units on the Proxmox host:
#
#   ebs-lab-autostart.service   oneshot  -> scripts/lab-start.sh
#   ebs-lab-autostart.timer     fires the service 2 min after each boot
#
# Why a timer instead of `qm set --onboot 1` on the EBS guests:
#   * onboot only powers the VM on; it does NOT start the Oracle DB or the app
#     tier, so AppsLogin would still be down (the appliance does not autostart
#     EBS — see PROGRESS.md Stage 9).
#   * onboot starts every guest at once, ignoring lab-start.sh's CONCURRENCY
#     cap (default 4) — on this HDD-backed host that is a known I/O thrash.
#   * The timer also boots the client VMs, but only after the EBS guests report
#     AppsLogin=302, which is what lab-start.sh already does end to end.
# The status portal (LXC 9300) keeps its own onboot=1 + startup order=1, so it
# is up first and can show the lab coming online.
#
# Safe to re-run. `systemctl start ebs-lab-autostart.service` runs lab-start.sh
# by hand; `lab-start.sh` is idempotent, so that is harmless on a running lab.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
START="$REPO/scripts/lab-start.sh"

SERVICE=/etc/systemd/system/ebs-lab-autostart.service
TIMER=/etc/systemd/system/ebs-lab-autostart.timer
LOCK=/run/lock/ebs-lab-start.lock
BOOT_DELAY="${BOOT_DELAY:-2min}"

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

status() {
  echo "service : $SERVICE"
  [ -f "$SERVICE" ] && echo "          present" || echo "          MISSING"
  echo "timer   : $TIMER"
  [ -f "$TIMER" ] && echo "          present" || echo "          MISSING"
  if systemctl list-unit-files ebs-lab-autostart.timer >/dev/null 2>&1; then
    printf 'enabled : %s\n' "$(systemctl is-enabled ebs-lab-autostart.timer 2>/dev/null || echo no)"
  fi
  systemctl list-timers ebs-lab-autostart.timer --no-pager 2>/dev/null || true
  echo
  echo "host EBS onboot flags (expected 0 — the timer drives startup):"
  while read -r id name role _; do
    [ "$role" = ebs ] || continue
    printf '  %-5s %-16s onboot=%s\n' "$id" "$name" \
      "$(qm config "$id" 2>/dev/null | awk -F': ' '/^onboot:/{print $2}')"
  done < <(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$REPO/scripts/inventory.conf")
}

REMOVE=0
for arg in "$@"; do
  case "$arg" in
    --remove) REMOVE=1 ;;
    --status) status; exit 0 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "run as root on the Proxmox host"
command -v systemctl >/dev/null || die "systemd not found"
[ -f "$START" ] || die "missing $START"

if [ "$REMOVE" -eq 1 ]; then
  say "removing lab autostart"
  systemctl disable --now ebs-lab-autostart.timer >/dev/null 2>&1 || true
  rm -f "$TIMER" "$SERVICE"
  systemctl daemon-reload
  systemctl reset-failed ebs-lab-autostart.service >/dev/null 2>&1 || true
  echo "removed $SERVICE and $TIMER"
  exit 0
fi

[ -f "$REPO/.env" ] || echo "WARN: $REPO/.env missing — the service will power on the VMs but cannot start EBS over SSH." >&2
[ -x "$START" ] || chmod +x "$START"

say "writing $SERVICE"
cat >"$SERVICE" <<EOF
[Unit]
Description=EBS training lab auto-start (boot VMs, start DB/app tier, start clients)
Documentation=file:$REPO/README.md
After=pve-guests.service network-online.target
Wants=network-online.target
ConditionPathExists=$START

[Service]
Type=oneshot
# -n: if a lab-start.sh is already running (manual run), let it own the lab.
ExecStart=/usr/bin/flock -n $LOCK $START
TimeoutStartSec=0
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=6
StandardOutput=journal
StandardError=journal
EOF

say "writing $TIMER"
cat >"$TIMER" <<EOF
[Unit]
Description=Start the EBS training lab shortly after boot

[Timer]
OnBootSec=$BOOT_DELAY
AccuracySec=15s
Unit=ebs-lab-autostart.service

[Install]
WantedBy=timers.target
EOF

say "enabling"
systemctl daemon-reload
# --now would fire immediately (OnBootSec is relative to boot), racing a manual
# lab-start; enabling is enough for the next boot.
# Do NOT start/restart the timer now: OnBootSec is relative to boot, so on a
# host that has been up for hours it would fire at once and race a running
# lab-start. Enabling is enough — timers.target loads it on the next boot.
systemctl enable ebs-lab-autostart.timer >/dev/null

systemd-analyze verify "$SERVICE" "$TIMER" 2>/dev/null || true

say "installed"
status
cat <<EOF

Next boot: about $BOOT_DELAY after the host comes up, ebs-lab-autostart.service
runs scripts/lab-start.sh (EBS VMs -> DB/app tier -> AppsLogin=302 -> clients).
  journalctl -u ebs-lab-autostart -b          # this boot's run
  systemctl start ebs-lab-autostart.service   # run it now (idempotent)
  scripts/install-lab-autostart.sh --remove   # turn it off
EOF
