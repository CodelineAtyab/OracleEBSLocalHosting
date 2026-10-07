#!/usr/bin/env bash
# Shared helpers for the EBS lab control scripts. Source it — don't execute it.
#   source "$(dirname "$0")/lib.sh"
#
# Secrets are read from the git-ignored .env (mode 600) in the repo root;
# nothing secret is ever written into the repo.

set -u

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-$LAB_DIR/scripts/inventory.conf}"
ENV_FILE="${ENV_FILE:-$LAB_DIR/.env}"
LOGDIR="${LOGDIR:-${TMPDIR:-/tmp}/ebs-lab}"
mkdir -p "$LOGDIR"

# --- load secrets -----------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
else
  echo "WARN: $ENV_FILE not found — EBS guests cannot be reached over SSH." >&2
fi
LAB_SSH_PW="${OS_ROOT_PASSWORD:-}"
export LAB_SSH_PW
# Password for the Proxmox student logins (stuNN@pve). Defaults to the lab
# password; override with PVE_PASSWORD in .env if it ever differs.
PVE_PASSWORD="${PVE_PASSWORD:-${OS_ROOT_PASSWORD:-}}"
export PVE_PASSWORD

# --- passwordless-prompt SSH to a guest (password from .env) ----------------
ASKPASS="$(mktemp -p "${TMPDIR:-/tmp}")"
umask 077
cat > "$ASKPASS" <<'EOF'
#!/bin/sh
printf '%s\n' "$LAB_SSH_PW"
EOF
chmod 700 "$ASKPASS"
trap 'rm -f "$ASKPASS"' EXIT

ssh_ebs() {            # ssh_ebs <ip> <remote-command...>   (stdin is inherited)
  local ip="$1"; shift
  SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force \
    setsid -w ssh \
      -oHostKeyAlgorithms=+ssh-rsa -oStrictHostKeyChecking=no \
      -oUserKnownHostsFile=/dev/null -oPubkeyAuthentication=no \
      -oPreferredAuthentications=password -oNumberOfPasswordPrompts=1 \
      -oConnectTimeout=15 root@"$ip" "$@"
}

# --- inventory helpers ------------------------------------------------------
# Each row: prints "<vmid> <name> <role> <ip>"
inventory_rows() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$INVENTORY"; }
ebs_rows()   { inventory_rows | awk '$3=="ebs"'; }
client_rows(){ inventory_rows | awk '$3=="client"'; }

vm_running() { [ "$(qm status "$1" 2>/dev/null | awk '{print $2}')" = running ]; }

# NIC MAC of a VM (lowercase), from its net0 line:  net0: e1000=BC:24:...:FF,bridge=...
vm_mac() { qm config "$1" 2>/dev/null | awk -F'[=,]' '/^net0:/{print tolower($2)}'; }

# MAC currently answering an IP (lowercase), via a targeted ARP scan ("" if none)
ip_mac() { arp-scan -I vmbr0 "$1" 2>/dev/null | awk -v ip="$1" '$1==ip{print tolower($2); exit}'; }

# True if <ip> is answered by the NIC of VM <id>
ip_is_vm() { [ -n "$(vm_mac "$2")" ] && [ "$(ip_mac "$1")" = "$(vm_mac "$2")" ]; }

# wait_ssh <ip> <seconds>  -> returns 0 if SSH answers
wait_ssh() {
  local ip="$1" secs="${2:-300}" i
  for ((i=0; i<secs/5; i++)); do
    ssh_ebs "$ip" true </dev/null 2>/dev/null && return 0
    sleep 5
  done
  return 1
}

# ebs_healthy <ip> -> echoes HTTP code for AppsLogin
ebs_login_code() {
  ssh_ebs "$1" 'curl -s -m6 -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/OA_HTML/AppsLogin' </dev/null 2>/dev/null
}
