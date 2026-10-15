#!/usr/bin/env bash
# restore-ebs-lab.sh — rebuild the EBS training lab on a FRESH Proxmox host from
# a backup made by scripts/backup-to-usb.sh.
#
# Copy of this script lives inside the backup dir. On the new host:
#   mount the USB disk, then:
#   sudo bash /path/to/ebs-lab-backup-*/restore-ebs-lab.sh [N]
#
# Restores the golden + client templates and the repo (scripts + .env), then
# builds the class + N student sandboxes (unless full VM backups were included,
# in which case those are restored). Host networking and the Proxmox user DB are
# NOT overwritten — reference copies are in hostconfig/.
set -u
SELF="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$SELF}"
N="${2:-9}"
STORAGE="${STORAGE:-local-lvm}"
WORKDIR="${WORKDIR:-/root/work_area/OracleEBSLocalHosting}"

echo "== EBS lab restore =="
[ "$(id -u)" = 0 ] || { echo "ERROR: run as root"; exit 1; }
command -v qm >/dev/null 2>&1 || { echo "ERROR: not a Proxmox host (qm missing)"; exit 1; }
[ -d "$SRC/vzdump" ] || { echo "ERROR: no vzdump/ under $SRC — run from the backup dir"; exit 1; }
pvesm status 2>/dev/null | grep -q "^$STORAGE" || { echo "ERROR: storage '$STORAGE' not found"; pvesm status; exit 1; }

echo "== 1/5  restore the repo (+ .env + scripts) to $WORKDIR =="
mkdir -p "$(dirname "$WORKDIR")"
tar xzf "$SRC/repo/ebs-lab-repo.tar.gz" -C "$(dirname "$WORKDIR")"
REPO="$WORKDIR"
[ -f "$REPO/scripts/lib.sh" ] || { echo "ERROR: repo restore failed"; exit 1; }

echo "== 2/5  restore the templates =="
gp=$(ls "$SRC"/vzdump/*9000*.vma.zst 2>/dev/null | head -1)
cpf=$(ls "$SRC"/vzdump/*9200*.vma.zst 2>/dev/null | head -1)
[ -n "$gp" ] || { echo "ERROR: golden backup (*9000*.vma.zst) not found"; exit 1; }
if qm config 9000 >/dev/null 2>&1; then echo "  9000 already present"; else
  qmrestore "$gp" 9000 --storage "$STORAGE" && qm template 9000 >/dev/null 2>&1 || true; fi
if [ -n "$cpf" ]; then
  if qm config 9200 >/dev/null 2>&1; then echo "  9200 already present"; else
    qmrestore "$cpf" 9200 --storage "$STORAGE" && qm template 9200 >/dev/null 2>&1 || true; fi
fi

echo "== 3/5  restore any class/sandbox backups that were included =="
restored_students=0
for f in "$SRC"/vzdump/*.vma.zst; do
  base=$(basename "$f")
  case "$base" in *9000*|*9200*) continue ;; esac
  id=$(echo "$base" | sed -n 's/.*-\([0-9]\{3,\}\)-.*/\1/p')
  [ -n "$id" ] || continue
  if qm config "$id" >/dev/null 2>&1; then echo "  $id already present"; continue; fi
  echo "  qmrestore $base -> $id"
  qmrestore "$f" "$id" --storage "$STORAGE" || echo "  WARN: restore $id failed"
  case "$id" in 91[0-9][0-9]|92[0-9][0-9]) restored_students=1 ;; esac
done

echo "== 4/5  build the fleet =="
if [ "$restored_students" = 1 ]; then
  echo "  full VM backups were restored — re-provisioning + syncing ACLs"
  bash "$REPO/scripts/sync-acls.sh" || true
else
  echo "  no student backups — rebuilding class + $N students from templates"
  bash "$REPO/scripts/lab-rebuild.sh" "$N"
fi
# Always re-assert the students' VM ACLs (qm destroy/qmrestore drop them).
bash "$REPO/scripts/sync-acls.sh" || echo "  WARN: sync-acls failed"
# Always (re)assert the class EBS logins to the documented default password,
# including when a class instance was restored from a backup (its STU* passwords
# may have drifted).
echo "  re-asserting class EBS logins (@codeline@)"
bash "$REPO/scripts/create-class-users.sh" || echo "  WARN: class login reset failed"

echo "== 5/5  start the lab =="
bash "$REPO/scripts/lab-start.sh"
bash "$REPO/scripts/lab-status.sh"

cat <<EOF

Restore complete.
  repo : $REPO   (contains .env — keep mode 600, never commit)
  host : reference config in $SRC/hostconfig/ (interfaces, etc-pve.tar.gz, host-state.txt)
Next  : confirm the IPs in scripts/inventory.conf match this host's network,
        then see README.md §14.
EOF

if [ -d "$SRC/media" ]; then
  cat <<EOF
  media: pristine appliance media is at $SRC/media
         (offline golden rebuild, if ever needed:
           MEDIA_DIR=$SRC/media scripts/build-golden.sh --yes )
EOF
fi
