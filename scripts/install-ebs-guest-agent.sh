#!/usr/bin/env bash
# install-ebs-guest-agent.sh — install + enable the QEMU guest agent on the EBS
# VMs that are already running (class + sandboxes), so Proxmox shows their IP.
#
#   scripts/install-ebs-guest-agent.sh          # all EBS guests in inventory
#   scripts/install-ebs-guest-agent.sh 9010     # just the class
#
# Uses a locally-cached EL6 RPM (the OL6 appliance's yum repos are dead).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

RPM="${QGA_RPM:-/srv/ebs-media/client/tools/qemu-guest-agent-el6.rpm}"
RPM_URL="${QGA_URL:-https://yum.oracle.com/repo/OracleLinux/OL6/latest/x86_64/getPackage/qemu-guest-agent-0.12.1.2-2.503.el6.x86_64.rpm}"
[ -s "$RPM" ] || { echo "fetching agent rpm"; curl -fsSL -o "$RPM" "$RPM_URL" || { echo "download failed"; exit 1; }; }

IDS="${1:-}"
if [ -z "$IDS" ]; then IDS=$(ebs_rows | awk '{print $1}'); fi

for id in $IDS; do
  row=$(inventory_rows | awk -v i="$id" '$1==i'); [ -n "$row" ] || { echo "skip $id (not in inventory)"; continue; }
  read -r vid name role ip <<<"$row"
  echo "== $name ($vid @ $ip) =="
  qm set "$vid" --agent 1 >/dev/null 2>&1 && echo "  agent=1 set"
  vm_running "$vid" || { echo "  not running"; continue; }
  if ! wait_ssh "$ip" 60; then echo "  no SSH at $ip — skipping"; continue; fi
  # is the agent already running?
  if ssh_ebs "$ip" 'ps -ef | grep -q "[q]emu-ga"' </dev/null 2>/dev/null; then
    echo "  qemu-ga already running"; continue
  fi
  ssh_ebs "$ip" 'cat > /tmp/qga.rpm' < "$RPM" 2>/dev/null
  ssh_ebs "$ip" 'bash -s' < "$HERE/guest/install-qga-ol6.sh" 2>&1 | sed 's/^/  /'
done
echo
echo "Note: the Proxmox VM summary shows the IP once the agent is up; a VM that was"
echo "already running may need a restart for the agent virtio-serial channel."
