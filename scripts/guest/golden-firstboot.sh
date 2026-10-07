#!/bin/bash
# Runs INSIDE a freshly-imported golden guest (as root), BEFORE templating.
# Best-effort automation of README §6–§8. Validate the result before relying on it.
#   usage: ssh root@<golden> 'bash -s' < golden-firstboot.sh
set -u
. /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env

echo "== single-node javacache =="
J="$INST_TOP/ora/10.1.3/javacache/admin/javacache.xml"
[ -f "$J" ] && sed -i 's#<isDistributed>true</isDistributed>#<isDistributed>false</isDistributed>#' "$J"

echo "== start DB + app tier =="
su - oracle -c "/u01/install/VISION/scripts/startvisiondb.sh" >/dev/null 2>&1
su - oracle -c "/u01/install/APPS/scripts/startapps.sh"       >/dev/null 2>&1
sleep 60

echo "== AutoConfig (generates the FND .dbc; without this AppsLogin = HTTP 500) =="
su - oracle -c ". /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env; cd \$ADMIN_SCRIPTS_HOME; ./adautocfg.sh appspass=apps" >/tmp/golden-autocfg.log 2>&1
echo "   autocfg tail:"; tail -5 /tmp/golden-autocfg.log | sed 's/^/   /'

code=000
for i in $(seq 1 36); do
  code=$(curl -s -m5 -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/OA_HTML/AppsLogin)
  [ "$code" = 302 ] && break; sleep 10
done
echo "== AppsLogin=$code =="

echo "== generalize NIC for cloning (+ placeholder .230 already set by set-ip.sh) =="
rm -f /etc/udev/rules.d/70-persistent-net.rules

echo "== NOTE: change the default OS/DB/app passwords now (README Stage 5), then run: =="
echo "   su - oracle -c stopapps.sh ; su - oracle -c stopvisiondb.sh ; shutdown -h now"

echo "== stopping tiers for a clean shutdown =="
su - oracle -c "/u01/install/APPS/scripts/stopapps.sh"       >/dev/null 2>&1
su - oracle -c "/u01/install/VISION/scripts/stopvisiondb.sh" >/dev/null 2>&1
echo "ready to shut down"
