#!/usr/bin/env bash
# run.sh — thin entrypoint for the EBS lab. No dependencies beyond bash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-help}"; shift || true
case "$cmd" in
  up|start)     exec "$HERE/scripts/lab-start.sh"          "$@" ;;
  down|stop)    exec "$HERE/scripts/lab-stop.sh"           "$@" ;;
  status)       exec "$HERE/scripts/lab-status.sh"         "$@" ;;
  init)         exec "$HERE/scripts/add-students.sh"       "$@" ;;
  rebuild)      exec "$HERE/scripts/lab-rebuild.sh"        "$@" ;;
  provision)    exec "$HERE/scripts/provision-sandbox.sh"  "$@" ;;
  reset)        exec "$HERE/scripts/reset-student.sh"      "$@" ;;
  sync-acls)    exec "$HERE/scripts/sync-acls.sh"          "$@" ;;
  class-users)  exec "$HERE/scripts/create-class-users.sh" "$@" ;;
  access-files) exec "$HERE/scripts/client/write-access-file.sh" "$@" ;;
  vnc)          exec "$HERE/scripts/client/vnc-credentials.sh"   "$@" ;;
  backup)       exec "$HERE/scripts/backup-to-usb.sh"      "$@" ;;
  base-backup)  exec "$HERE/scripts/backup-to-usb.sh" "${1:-}" --with-media ;;
  export)       exec "$HERE/scripts/export-images.sh"      "$@" ;;
  build-golden) exec "$HERE/scripts/build-golden.sh"       "$@" ;;
  help|*)       cat <<'EOF'
Usage: ./run.sh <command> [args]
  up                     start the whole lab
  down [--poweroff]      stop the whole lab (optionally power off the host)
  status                 VM + AppsLogin status
  init N                 add N students
  rebuild [N]            build class + N students from the templates (clean build)
  provision <vmid>       (re)configure / repair one EBS sandbox
  reset <student|vmid> [--client]
                         wipe a student's sandbox back to the template
  sync-acls              re-assert student Proxmox users + VM ACLs
  class-users            create class EBS logins for all students
  access-files [vmid…]   write/refresh each client's your_access.txt + hostname
  vnc                    show each client's live VNC address + PIN
  backup <mount> [--with-class] [--with-sandboxes] [--with-media]
                         full DR backup to an external disk (USB)
  base-backup <mount>    base DR backup: templates + repo + pristine media
  export [--storage S]   back up golden + client template (DR)
  build-golden           rebuild the golden from pristine media (rare)
EOF
  ;;
esac
