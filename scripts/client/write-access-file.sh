#!/usr/bin/env bash
# write-access-file.sh — put a per-trainee "your_access.txt" cheat-sheet on each
# client VM's desktop, and set the guest hostname to client-stuNN.
#
#   scripts/client/write-access-file.sh                 # every client in inventory
#   scripts/client/write-access-file.sh 9201 9204       # selected clients (VMID or index)
#
# Credentials come from the git-ignored .env and topology from scripts/inventory.conf,
# so THIS SCRIPT CONTAINS NO SECRETS. It is safe to re-run any time the lab is up —
# that is the "refresh with up-to-date info" step (e.g. after DHCP gives a client a
# new IP). Called automatically by build-client-template.sh / add-students.sh /
# reset-student.sh. See README section 10.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

PIN="${VNC_PIN:-29999}"

# --- values that go in the sheet (a share of them are lab-wide constants) ----
LABPW="${OS_ROOT_PASSWORD:-}"
[ -n "$LABPW" ] || { echo "ERROR: OS_ROOT_PASSWORD not set in .env (needed to render the sheet)"; exit 1; }
STUDENT_PW="${EBS_STUDENT_PASSWORD:-$LABPW}"
APPS_PW="${DB_APPS_SCHEMA_PASSWORD:-apps}"
PUB_PW="${DB_APPLSYSPUB_PASSWORD:-PUB}"
DEMO_PW="${EBS_DEMO_USER_PASSWORD:-welcome}"

CLIP=$(ebs_rows | awk '$1==9010{print $4}')
[ -n "$CLIP" ] || { echo "ERROR: class 9010 (shared instance) not in $INVENTORY"; exit 1; }

# --- the sheet itself --------------------------------------------------------
render() {  # render NN CNAME CIP SIP SNN
  local NN="$1" CNAME="$2" CIP="$3" SIP="$4" SNN="$5" PVE="stu$1" UN="$((10#$1))"
  cat <<EOF
=====================================================================
   EBS TRAINING LAB  --  ACCESS SHEET                trainee: STU${NN}
=====================================================================
   Offline, LAN-only lab.   Shared password everywhere:  ${LABPW}
   (OS root/oracle/applmgr, DB SYSDBA, EBS web)   demo/seed users use:  ${DEMO_PW}
   (instructor) refresh this sheet:  scripts/client/write-access-file.sh
---------------------------------------------------------------------

 1) THIS DESKTOP   (your client VM: ${CNAME})
    Connect from your own PC with any VNC viewer:
         ${CIP}:5900            VNC PIN / password:  ${PIN}
    Or the Proxmox web UI:  https://<pve-host>:8006
         user ${PVE}   (realm: Proxmox VE)   ->   ${CNAME}   ->   Console
    Change your VNC PIN any time:  desktop icon "Change VNC password".

 2) EBS APPLICATION  --  the shared CLASS instance  (functional / screens)
    URL          http://${CLIP}:8000/         (opens in Firefox ESR)
    Your login   STU${NN}   /  ${STUDENT_PW}      (System Administrator)
    Admin login  SYSADMIN   /  ${LABPW}

 3) YOUR OWN SANDBOX  --  EBS instance #${UN}  (Apps DBA / admin practice)
    VM           ebs1213-stu${NN}   (Proxmox ${SNN})   IP ${SIP}
    Web          http://${SIP}:8000/          login SYSADMIN / ${LABPW}
    SSH          ssh root@${SIP}               pw ${LABPW}
                 oracle  / ${LABPW}    (owns DB + app tier)
                 applmgr / ${LABPW}    (owns app tier)
    Database     host ${SIP}   port 1521   SID/service EBSDB
                 apps / ${APPS_PW}             (APPS schema)
                 system / ${LABPW}             (SYSTEM)
                 sys / ${LABPW}  as SYSDBA     (connect sys/..@EBSDB as sysdba)
                 APPLSYSPUB / ${PUB_PW}        (public/guest)

 4) CONNECTING WITH THESE DESKTOP TOOLS
    SQLcl / SQL*Plus (terminal):
         sql apps/${APPS_PW}@EBSDB_STU${NN}     # your sandbox DB
         sql apps/${APPS_PW}@EBSDB_CLASS        # the class instance DB
         # as SYSDBA:  connect sys/${LABPW}@EBSDB_STU${NN} as sysdba
    SQL Developer / DBeaver:
         TNS aliases are preconfigured (tnsnames.ora): EBSDB_CLASS and
         EBSDB_STU01..STU09.  Choose the alias, then a user/password above.
    FileZilla (SFTP):  sftp://${SIP}    user root    password ${LABPW}
    PuTTY (SSH):       host ${SIP}      user root    password ${LABPW}
    Firefox:           the class + sandbox URLs above (Forms applet = IcedTea-Web).
    Geany (text editor): open .txt/.log/.sql/.conf files — it is also the default
                         editor when you double-click such a file.

 5) SANDBOX PATHS & COMMANDS   (as oracle; first run
       . /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env )
    DB tier    /u01/install/VISION      startvisiondb.sh / stopvisiondb.sh
    App tier   /u01/install/APPS        startapps.sh / stopapps.sh  (in APPS/scripts)
    App log    /u01/install/APPS/apps/apps_st/appl/admin/EBSDB/log

 Legend: ${LABPW} = the lab's shared password (OS root/oracle/applmgr, DB
 SYS/SYSTEM, EBS SYSADMIN + the STU logins).  apps/${APPS_PW} = APPS schema;
 APPLSYSPUB/${PUB_PW} = public user.  Instructor reset: scripts/reset-ebs-password.sh
=====================================================================
EOF
}

# --- which clients -----------------------------------------------------------
rows="$(client_rows)"
if [ "$#" -gt 0 ]; then
  rows=""
  for arg in "$@"; do
    case "$arg" in
      92[0-9][0-9]) id="$arg" ;;
      *[!0-9]*)     echo "skip '$arg' (give a VMID 920N or an index N)" >&2; continue ;;
      *)            id=$((9200+arg)) ;;
    esac
    r=$(client_rows | awk -v i="$id" '$1==i')
    if [ -n "$r" ]; then rows+="$r"$'\n'; else echo "skip $arg: VMID $id is not a client in $INVENTORY" >&2; fi
  done
fi
[ -n "${rows//[[:space:]]/}" ] || { echo "no client VMs selected"; exit 0; }

# --- per client: find it, name it, drop the sheet ----------------------------
fail=0
while read -r id name role xip; do
  [ -n "$id" ] || continue
  idx=$((id-9200)); NN=$(printf %02d "$idx")
  cname="client-stu${NN}"; SBID=$((9100+idx))
  SIP=$(ebs_rows | awk -v i="$SBID" '$1==i{print $4}'); SIP=${SIP:-192.168.100.???}
  echo "== $cname (client $id -> sandbox $SBID @ $SIP) =="

  vm_running "$id" || { echo "   VM not running — start it then re-run"; fail=1; continue; }

  # find its DHCP address (guest agent first, then ARP by MAC) and wait for SSH
  cip=""; mac=$(vm_mac "$id")
  for i in $(seq 1 36); do
    cip=$(timeout 15 qm guest cmd "$id" network-get-interfaces 2>/dev/null \
          | grep -oE '"192\.168\.100\.[0-9]+"' | tr -d '"' | grep -v '127\.0\.0\.1' | head -1)
    [ -n "$cip" ] || cip=$(arp-scan -I vmbr0 192.168.100.0/24 2>/dev/null \
          | awk -v m="$mac" 'tolower($2)==m{print $1;exit}')
    [ -n "$cip" ] && ssh_ebs "$cip" true </dev/null 2>/dev/null && break
    cip=""; sleep 5
  done
  [ -n "$cip" ] || { echo "   no IP/SSH after ~3 min — start the VM / re-run later"; fail=1; continue; }

  # hostname -> client-stuNN (+ /etc/hosts + live transient name for the VNC banner)
  ssh_ebs "$cip" "
    hostnamectl set-hostname '$cname' >/dev/null 2>&1
    if grep -q '^127\.0\.1\.1' /etc/hosts; then sed -i 's/^127\.0\.1\.1.*/127.0.1.1 $cname/' /etc/hosts
    else echo '127.0.1.1 $cname' >> /etc/hosts; fi
    hostname '$cname' 2>/dev/null || true
  " </dev/null >/dev/null 2>&1 || true

  # the sheet
  render "$NN" "$cname" "$cip" "$SIP" "$SBID" \
    | ssh_ebs "$cip" 'cat > /home/student/Desktop/your_access.txt' 2>/dev/null \
    && ssh_ebs "$cip" 'chown student:student /home/student/Desktop/your_access.txt; chmod 644 /home/student/Desktop/your_access.txt' </dev/null >/dev/null 2>&1 \
    && echo "   wrote your_access.txt (hostname=$cname, ip=$cip)" \
    || { echo "   FAILED to write the sheet"; fail=1; }
done <<< "$rows"

exit "$fail"
