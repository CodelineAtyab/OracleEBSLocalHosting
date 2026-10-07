#!/bin/bash
# Runs INSIDE an EBS guest as root: idempotent single-node fixups + start EBS + verify.
#   usage: ssh root@<guest> 'bash -s' < provision.sh
set -u
. /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env
MYIP=$(getent hosts ebs.example.com | awk '{print $1}')
echo "myip=$MYIP"

# --- single-node: disable the distributed JTF cache -------------------------
J="$INST_TOP/ora/10.1.3/javacache/admin/javacache.xml"
[ -f "$J" ] && sed -i 's#<isDistributed>true</isDistributed>#<isDistributed>false</isDistributed>#' "$J"

# --- start DB then app tier (if not already running) -----------------------
pgrep -f "[p]mon_EBSDB" >/dev/null && echo "DB already up" || {
  echo "starting DB"; su - oracle -c "/u01/install/VISION/scripts/startvisiondb.sh" >/dev/null 2>&1; }
pgrep -f "[o]c4j" >/dev/null && echo "app tier already up" || {
  echo "starting app tier"; su - oracle -c "/u01/install/APPS/scripts/startapps.sh" >/dev/null 2>&1; }
sleep 45

# --- FND_NODES.SERVER_ADDRESS -> this clone's own IP (only if changed) -----
CUR=$(sqlplus -s apps/apps@EBSDB <<SQL 2>/dev/null
set head off pages 0 feed off
select server_address from fnd_nodes where node_name='EBS';
exit
SQL
)
CUR=$(echo "$CUR" | tr -d '[:space:]')
echo "fnd_nodes.server_address was='$CUR'"
if [ "$CUR" != "$MYIP" ]; then
  echo "updating FND_NODES -> $MYIP (restart OACORE)"
  sqlplus -s apps/apps@EBSDB <<SQL >/dev/null 2>&1
set feed off pages 0
update fnd_nodes set server_address='$MYIP' where node_name='EBS';
commit;
exit
SQL
  su - oracle -c ". /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env; \$ADMIN_SCRIPTS_HOME/adoacorectl.sh stop"  >/dev/null 2>&1
  sleep 8
  su - oracle -c ". /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env; \$ADMIN_SCRIPTS_HOME/adoacorectl.sh start" >/dev/null 2>&1
fi

# --- wait for a healthy login page -----------------------------------------
code=000
for i in $(seq 1 36); do
  code=$(curl -s -m5 -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/OA_HTML/AppsLogin)
  [ "$code" = 302 ] && break
  sleep 10
done
echo "AppsLogin=$code"
[ "$code" = 302 ]
