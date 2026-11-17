#!/usr/bin/env bash
# portal-rebuild.sh - destroy and recreate the lab status portal container.
#
#   scripts/portal/portal-rebuild.sh [portal-install options]
#
# The page, the collector and the container itself are all reproducible from
# scripts/portal/ - nothing of value lives inside the container (the Proxmox
# API token is recreated by portal-install.sh).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/portal.conf"

if pct status "$PORTAL_VMID" >/dev/null 2>&1; then
  printf '==> destroying LXC %s\n' "$PORTAL_VMID"
  pct set "$PORTAL_VMID" --protection 0 >/dev/null 2>&1 || true
  if [ "$(pct status "$PORTAL_VMID" | awk '{print $2}')" = running ]; then
    pct stop "$PORTAL_VMID" || true
  fi
  pct destroy "$PORTAL_VMID" --purge --force 1
else
  printf '==> LXC %s does not exist\n' "$PORTAL_VMID"
fi

exec "$HERE/portal-install.sh" "$@"
