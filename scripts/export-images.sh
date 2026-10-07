#!/usr/bin/env bash
# export-images.sh — DR: archive the golden + client templates so the lab can be
# rebuilt without re-downloading the appliance.
#
#   scripts/export-images.sh                 # -> /srv/ebs-media/backups (default)
#   scripts/export-images.sh --storage local # -> a Proxmox storage's dump dir
#   OUT=/mnt/nas/ebs scripts/export-images.sh
#
# The golden (9000) is the only irreplaceable artifact; the client template
# (9200) is small. Both are stopped templates, so --mode stop is safe.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

STORAGE=""
[ "${1:-}" = "--storage" ] && STORAGE="${2:?--storage <name>}"
OUT="${OUT:-/srv/ebs-media/backups}"
STAMP="$(date +%Y%m%d)"
[ -z "$STORAGE" ] && mkdir -p "$OUT"

for id in 9000 9200; do
  name=$(qm config "$id" 2>/dev/null | sed -n 's/^name: //p')
  [ -n "$name" ] || { echo "skip: VM $id not found"; continue; }
  echo "== vzdump $id ($name) -> ${STORAGE:-$OUT} =="
  if [ -n "$STORAGE" ]; then
    vzdump "$id" --mode stop --compress zstd --storage "$STORAGE" \
      --notes-template "$name exported $STAMP"
  else
    vzdump "$id" --mode stop --compress zstd --dumpdir "$OUT" \
      --notes-template "$name exported $STAMP"
  fi
done
echo "Done. Restore with:  qmrestore <file.vma.zst> <vmid>"
