#!/usr/bin/env bash
# backup-to-usb.sh — back the lab up to an external disk for disaster recovery.
#
#   scripts/backup-to-usb.sh <mountpoint> [options]
#
# Always backs up: golden template (9000), client template (9200), a host-config
# snapshot, and the whole repo (INCLUDING the git-ignored .env).
# Options:
#   --with-class      also dump the shared class instance (9010)
#   --with-sandboxes  also dump every student sandbox + client VM
#   --with-media      also copy the pristine appliance media (/srv/ebs-media)
#
# The backup dir gets a self-contained restore-ebs-lab.sh you run on the new host.
#
# Deliberately EXCLUDES host secrets / remote-access config: /root/.bash_history
# and /etc/cloudflared (the Proxmox access tunnel). Never add them to a backup.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

DEST_ROOT="${1:?usage: backup-to-usb.sh <mountpoint> [--with-class] [--with-sandboxes] [--with-media]}"; shift || true
WITH_CLASS=0; WITH_SANDBOXES=0; WITH_MEDIA=0
for a in "$@"; do case "$a" in
  --with-class)     WITH_CLASS=1 ;;
  --with-sandboxes) WITH_SANDBOXES=1 ;;
  --with-media)     WITH_MEDIA=1 ;;
  *) echo "unknown option: $a"; exit 1 ;;
esac; done

[ -d "$DEST_ROOT" ] || { echo "ERROR: mountpoint $DEST_ROOT not found"; exit 1; }
mountpoint -q "$DEST_ROOT" || echo "WARN: $DEST_ROOT is not a mountpoint — is the disk mounted?"
STAMP="$(date +%Y%m%d-%H%M)"; DEST="$DEST_ROOT/ebs-lab-backup-$STAMP"
mkdir -p "$DEST/vzdump" "$DEST/hostconfig" "$DEST/repo"
echo "== EBS lab backup -> $DEST =="

echo "== host config snapshot =="
{ echo "host: $(hostname)"; echo "date: $(date)"; echo
  pveversion; echo; pvesm status; echo
  echo "--- vgs ---"; vgs; echo "--- lvs ---"; lvs; echo
  echo "--- qm list ---"; qm list; echo
  echo "--- pveum user list ---"; pveum user list; echo "--- pveum acl list ---"; pveum acl list; echo
  echo "--- ip -4 addr ---"; ip -4 a; } > "$DEST/hostconfig/host-state.txt" 2>&1
cp -a /etc/network/interfaces "$DEST/hostconfig/interfaces" 2>/dev/null || true
cp -a /etc/hosts /etc/hostname /etc/fstab "$DEST/hostconfig/" 2>/dev/null || true
tar czf "$DEST/hostconfig/etc-pve.tar.gz" -C /etc pve 2>/dev/null || true

echo "== repo (incl. .env + scripts + docs) =="
tar czf "$DEST/repo/ebs-lab-repo.tar.gz" -C "$(dirname "$LAB_DIR")" "$(basename "$LAB_DIR")" 2>/dev/null

if [ "$WITH_MEDIA" = 1 ]; then
  echo "== pristine media (/srv/ebs-media, for offline golden rebuild) =="
  mkdir -p "$DEST/media"
  cp -a /srv/ebs-media/. "$DEST/media/" 2>/dev/null || true
  rm -rf "$DEST/media/lost+found" 2>/dev/null || true
  echo "   media copied:"; du -sh "$DEST/media" 2>/dev/null
fi

backup_vm() {  # <vmid>
  local id="$1" name mode
  name=$(qm config "$id" 2>/dev/null | sed -n 's/^name: //p')
  [ -n "$name" ] || { echo "  skip: VM $id not found"; return 0; }
  if vm_running "$id"; then mode=snapshot; else mode=stop; fi
  echo "== vzdump $id ($name, mode=$mode) =="
  vzdump "$id" --mode "$mode" --compress zstd --dumpdir "$DEST/vzdump" \
    || echo "  WARN: vzdump $id failed"
}

backup_vm 9000
backup_vm 9200
[ "$WITH_CLASS" = 1 ] && backup_vm 9010
if [ "$WITH_SANDBOXES" = 1 ]; then
  for id in $(ebs_rows | awk '$1!=9010{print $1}'); do backup_vm "$id"; done
  for id in $(client_rows | awk '{print $1}'); do backup_vm "$id"; done
fi

echo "== shipping the restore script =="
cp -a "$HERE/restore-ebs-lab.sh" "$DEST/restore-ebs-lab.sh" 2>/dev/null || true
chmod 755 "$DEST/restore-ebs-lab.sh" 2>/dev/null || true

# Safety: never ship host secrets / remote-access config (bash history, the
# Proxmox access-tunnel token, etc.). Strip them if a future edit pulled them in.
find "$DEST" \( -iname '*bash_history*' -o -path '*cloudflared*' -o -name 'token' \) -print0 2>/dev/null \
  | while IFS= read -r -d '' f; do rm -rf "$f" 2>/dev/null; echo "  removed (not allowed in backup): $f"; done

echo "== manifest + checksums =="
{ echo "EBS lab backup"; echo "host: $(hostname)"; echo "pve: $(pveversion)"; echo "date: $(date)"; echo
  echo "contents:"; ( cd "$DEST" && find . -type f | sort ); } > "$DEST/MANIFEST.txt"
( cd "$DEST" && find . -type f ! -name sha256sums.txt -print0 | xargs -0 sha256sum > sha256sums.txt )

echo "== backup complete: $DEST =="
du -sh "$DEST"
