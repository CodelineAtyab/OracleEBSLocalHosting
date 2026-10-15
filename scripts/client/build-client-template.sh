#!/usr/bin/env bash
# build-client-template.sh — bake the free native dev/DB tools into the client
# template (9200) and recreate all client VMs from it. Runs on the Proxmox host.
#
#   scripts/client/build-client-template.sh
#
# SAFE ORDER: destroy existing client clones FIRST (they share the template's
# base disk), then edit 9200, install, re-template, then recreate the clients.
# Destructive to the client VMs (their desktop state is lost) — that's intended.
# Nothing here touches the USB backup.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

TEMPLATE=9200
TOOLS_DIR="${TOOLS_DIR:-/srv/ebs-media/client/tools}"
HTTP_PORT="${HTTP_PORT:-8099}"
HOST_IP="${HOST_IP:-192.168.100.222}"
CLIENT_MEM="${CLIENT_MEM:-6144}"
LOG="${LOG:-/tmp/ebs-client-build.log}"
STATUS="${STATUS:-/tmp/ebs-client-build.status}"
GUEST_PW="${LAB_SSH_PW}"

mkdir -p "$TOOLS_DIR"
exec > >(tee -a "$LOG") 2>&1
echo "###################################################################"
echo "# client template build — $(date)  (log: $LOG)"
echo "###################################################################"
SRV_PID=""
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null || true; }
trap cleanup EXIT

ok()   { echo "  OK: $*"; }
warn() { echo "  WARN: $*"; }
fail() { echo "  FAIL: $*"; echo "FAILED: $*" > "$STATUS"; }

retry() { local n="$1"; shift; local i; for ((i=1;i<=n;i++)); do "$@" && return 0; echo "    (attempt $i/$n failed: $*)"; sleep 5; done; return 1; }

# --- SSH helpers (root@<ip>, password from .env) ----------------------------
ASKPASS="$(mktemp)"; printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$GUEST_PW" > "$ASKPASS"; chmod 700 "$ASKPASS"
trap 'cleanup; rm -f "$ASKPASS"' EXIT
sshc() { local ip="$1"; shift; SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force \
  timeout "${SSH_TMOUT:-120}" setsid -w ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null \
    -oPubkeyAuthentication=no -oPreferredAuthentications=password -oNumberOfPasswordPrompts=1 \
    -oConnectTimeout=15 root@"$ip" "$@"; }

guest_ip_of() { local mac; mac=$(vm_mac "$1"); arp-scan -I vmbr0 192.168.100.0/24 2>/dev/null | awk -v m="$mac" 'tolower($2)==m{print $1; exit}'; }
wait_ssh_host() { local ip="$1" secs="${2:-300}" i; for ((i=0;i<secs/5;i++)); do sshc "$ip" true </dev/null 2>/dev/null && return 0; sleep 5; done; return 1; }

# ===========================================================================
echo; echo "=== 1/8  stage tool downloads on the host (idempotent) ==="
declare -A DL=(
  [sqlcl-latest.zip]="https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"
  [instantclient-basiclite-linuxx64.zip]="https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linuxx64.zip"
  [instantclient-sqlplus-linuxx64.zip]="https://download.oracle.com/otn_software/linux/instantclient/instantclient-sqlplus-linuxx64.zip"
  [sqldeveloper-nojre.zip]="https://download.oracle.com/otn_software/java/sqldeveloper/sqldeveloper-26.2.0.186.2220-no-jre.zip"
  [dbeaver-ce-linux.tar.gz]="https://dbeaver.io/files/dbeaver-ce-latest-linux.gtk.x86_64.tar.gz"
  [temurin17.tar.gz]="https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
)
for f in "${!DL[@]}"; do
  if [ -s "$TOOLS_DIR/$f" ]; then ok "$f already staged ($(du -h "$TOOLS_DIR/$f"|cut -f1))"; continue; fi
  echo "  downloading $f ..."
  for i in 1 2 3 4; do
    wget -c -q --show-progress --tries=2 --timeout=60 -O "$TOOLS_DIR/$f.part" "${DL[$f]}" && mv "$TOOLS_DIR/$f.part" "$TOOLS_DIR/$f" && break
    echo "    download attempt $i failed"; sleep 10
  done
  [ -s "$TOOLS_DIR/$f" ] && ok "$f ($(du -h "$TOOLS_DIR/$f"|cut -f1))" || warn "could not fetch $f (continuing)"
done
cp -a "$HERE/client/install-tools.sh" "$TOOLS_DIR/install-tools.sh"

echo; echo "=== 2/8  destroy existing client clones (free the shared base) ==="
for row in $(client_rows | awk '{print $1}'); do
  qm stop "$row" --skiplock 1 >/dev/null 2>&1 || true
  timeout 120 qm destroy "$row" --purge 1 >/dev/null 2>&1 && ok "destroyed $row" || warn "destroy $row"
done

echo; echo "=== 3/8  flip template $TEMPLATE -> VM and set RAM ${CLIENT_MEM}MB ==="
CONF="/etc/pve/qemu-server/$TEMPLATE.conf"
[ -f "$CONF" ] || { fail "no $CONF"; exit 1; }
if grep -q '^template:' "$CONF"; then
  tmpf=$(mktemp); grep -v '^template:' "$CONF" > "$tmpf"; cat "$tmpf" > "$CONF"; rm -f "$tmpf"
  ok "template flag removed"
fi
# Template base volumes are READ-ONLY in LVM; make writable so the VM can boot.
lvchange -prw "pve/base-${TEMPLATE}-disk-0" >/dev/null 2>&1 && ok "LV base-${TEMPLATE}-disk-0 -> writable" || true
lvchange -prw "pve/vm-${TEMPLATE}-disk-0"   >/dev/null 2>&1 || true
timeout 30 qm set "$TEMPLATE" --memory "$CLIENT_MEM" --onboot 0 --agent 1 >/dev/null 2>&1 && ok "RAM=$CLIENT_MEM, agent=1"

echo; echo "=== 4/8  boot template + wait for SSH ==="
qm start "$TEMPLATE" >/dev/null 2>&1 && ok "started $TEMPLATE" || warn "qm start $TEMPLATE returned non-zero"
ip=""
for i in $(seq 1 48); do ip=$(guest_ip_of "$TEMPLATE"); [ -n "$ip" ] && break; sleep 5; done
[ -n "$ip" ] || { fail "template got no IP"; exit 1; }
ok "template at $ip"
retry 3 wait_ssh_host "$ip" 300 || { fail "no SSH to client template at $ip"; exit 1; }
ok "SSH OK"

echo; echo "=== 5/8  serve tools + install in the guest ==="
( cd "$TOOLS_DIR" && python3 -m http.server "$HTTP_PORT" --bind 0.0.0.0 >/tmp/ebs-http.log 2>&1 ) &
SRV_PID=$!; sleep 2
sshc "$ip" "curl -fsS -o /root/install-tools.sh http://$HOST_IP:$HTTP_PORT/install-tools.sh" </dev/null \
  && ok "installer copied" || warn "installer copy failed (guest will retry via bash -s)"
SSH_TMOUT=3600 sshc "$ip" "bash /root/install-tools.sh http://$HOST_IP:$HTTP_PORT" </dev/null \
  && ok "install completed" || warn "install returned non-zero (check /var/log/ebs-tools-install.log in guest)"
# summary from the guest
echo "----- guest install summary -----"
sshc "$ip" 'tail -n 12 /var/log/ebs-tools-install.log 2>/dev/null' </dev/null || true
kill "$SRV_PID" 2>/dev/null; SRV_PID=""

echo; echo "=== 6/8  generalize + shutdown ==="
sshc "$ip" '
  yum clean all >/dev/null 2>&1 || true
  rm -f /etc/ssh/ssh_host_* 2>/dev/null || true
  : > /etc/machine-id 2>/dev/null || true
  rm -f /var/lib/dbus/machine-id 2>/dev/null || true
  for l in /var/log/*.log /var/log/messages /var/log/secure; do [ -f "$l" ] && : > "$l"; done
  rm -rf /tmp/* /var/tmp/* /root/.bash_history /home/student/.bash_history 2>/dev/null || true
  sync
  shutdown -h now' </dev/null || true
for i in $(seq 1 60); do vm_running "$TEMPLATE" || break; sleep 5; done
vm_running "$TEMPLATE" && { fail "template did not shut down"; exit 1; }
ok "template shut down"

echo; echo "=== 7/8  re-template + recreate client VMs ==="
timeout 60 qm template "$TEMPLATE" >/dev/null 2>&1 && ok "9200 is a template again" || warn "qm template"
for row in $(ebs_rows | awk '$1!=9010{print $1}'); do
  idx=$((row-9100)); cli=$((9200+idx)); name="client-stu$(printf %02d "$idx")"
  timeout 300 qm clone "$TEMPLATE" "$cli" --name "$name" --full 0 >/dev/null 2>&1 \
    && timeout 30 qm set "$cli" --memory "$CLIENT_MEM" --cores 2 --onboot 0 --agent 1 >/dev/null 2>&1 \
    && ok "created $name ($cli, ${CLIENT_MEM}MB, agent=1)" || warn "clone/set $cli"
done

# Re-cloning destroyed the client VMs (and with them their ACLs) — re-assert the
# students' access so they can still see their client VM in the Proxmox UI.
"$HERE/scripts/sync-acls.sh" || warn "sync-acls failed (students may not see their client VM)"

echo; echo "=== 8/8  start clients + verify ==="
for row in $(client_rows | awk '{print $1}'); do qm start "$row" >/dev/null 2>&1 || true; done
sleep 40
# per-trainee access sheet + hostname (waits for each client's DHCP/SSH)
"$HERE/client/write-access-file.sh" \
  || warn "access-sheet generation had errors — re-run scripts/client/write-access-file.sh"
cip=$(guest_ip_of 9201)
if [ -n "$cip" ] && wait_ssh_host "$cip" 180; then
  echo "----- client-stu01 tool check -----"
  sshc "$cip" 'ls -d /opt/ebs-tools/* 2>/dev/null; echo; command -v filezilla putty 2>/dev/null; /opt/ebs-tools/jdk-17/bin/java -version 2>&1 | head -1' </dev/null || true
  ok "client-stu01 reachable and tools present"
else
  warn "client-stu01 not reachable yet (DHCP/boot timing) — check manually"
fi

echo; echo "###################################################################"
echo "# build finished — $(date)"
echo "###################################################################"
echo "DONE" > "$STATUS"
