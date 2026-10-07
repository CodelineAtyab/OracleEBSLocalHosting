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
  provision)    exec "$HERE/scripts/provision-sandbox.sh"  "$@" ;;
  reset)        exec "$HERE/scripts/reset-student.sh"      "$@" ;;
  class-users)  exec "$HERE/scripts/create-class-users.sh" "$@" ;;
  export)       exec "$HERE/scripts/export-images.sh"      "$@" ;;
  build-golden) exec "$HERE/scripts/build-golden.sh"       "$@" ;;
  help|*)       cat <<'EOF'
Usage: ./run.sh <command> [args]
  up                     start the whole lab
  down [--poweroff]      stop the whole lab (optionally power off the host)
  status                 VM + AppsLogin status
  init N                 add N students
  provision <vmid>       (re)configure / repair one EBS sandbox
  reset <student|vmid> [--client]
                         wipe a student's sandbox back to the template
  class-users            create class EBS logins for all students
  export [--storage S]   back up golden + client template (DR)
  build-golden           rebuild the golden from pristine media (rare)
EOF
  ;;
esac
