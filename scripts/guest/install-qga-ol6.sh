#!/bin/bash
# Runs INSIDE an OL6 EBS guest as root: install qemu-guest-agent from a local RPM
# (pushed to /tmp/qga.rpm by the host) and enable/start it.
#   usage: ssh root@<guest> 'bash -s' < install-qga-ol6.sh
set -u
RPM=/tmp/qga.rpm
[ -s "$RPM" ] || { echo "  ERROR: $RPM not present"; exit 1; }
echo "  installing $(basename "$(ls -1 "$RPM")")"
rpm -Uvh --nodeps "$RPM" >/tmp/qga-install.log 2>&1 || true   # "already installed" is fine
if grep -qi 'already installed' /tmp/qga-install.log; then echo "  rpm already installed"; else echo "  rpm installed"; fi
rm -f "$RPM"
# OL6 uses sysvinit; the service is named 'qemu-ga'
if [ -x /etc/init.d/qemu-ga ]; then
  chkconfig qemu-ga on 2>/dev/null || true
  service qemu-ga start 2>/dev/null || true
fi
if [ -x /etc/init.d/qemu-guest-agent ]; then
  chkconfig qemu-guest-agent on 2>/dev/null || true
  service qemu-guest-agent start 2>/dev/null || true
fi
if ps -ef | grep -q '[q]emu-ga'; then
  echo "  qemu-ga RUNNING: $(command -v qemu-ga)"
else
  echo "  qemu-ga NOT running (check /var/log)"
fi
