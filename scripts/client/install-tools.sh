#!/bin/bash
# install-tools.sh — runs INSIDE an OL7.9 client guest AS ROOT.
# Installs the free native dev/DB tools for the EBS lab, from an HTTP staging URL.
#   usage: bash install-tools.sh <http-base-url>
# Idempotent-ish: re-running re-extracts/updates in place.
set -u
BASE="${1:?usage: install-tools.sh <http-base-url>}"
DEST=/opt/ebs-tools
mkdir -p "$DEST"
LOG=/var/log/ebs-tools-install.log
exec > >(tee -a "$LOG") 2>&1
echo "==================================================================="
echo " EBS client tools install — $(date) — base=$BASE"
echo "==================================================================="
export PATH="$PATH:/usr/sbin:/sbin"

have() { command -v "$1" >/dev/null 2>&1; }
step() { echo; echo "---- $* ----"; }

fetch() {  # fetch <filename> <destpath>
  local f="$1" d="$2" i
  for i in 1 2 3 4; do
    echo "  fetch $f (attempt $i)"
    if curl -fL --retry 2 --retry-delay 5 -C - -o "$d" "$BASE/$f"; then return 0; fi
    sleep 5
  done
  echo "  !! FAILED to fetch $f"; return 1
}

step "base packages"
have unzip || yum -y install unzip >/dev/null 2>&1
have curl  || yum -y install curl  >/dev/null 2>&1
have rsync || yum -y install rsync >/dev/null 2>&1

# EPEL 7 (archived) for FileZilla / PuTTY
if ! ls /etc/yum.repos.d/ | grep -qi 'epel'; then
  cat > /etc/yum.repos.d/epel-archive.repo <<'EOF'
[epel-archive]
name=EPEL 7 archive
baseurl=https://dl.fedoraproject.org/pub/archive/epel/7/x86_64/
enabled=1
gpgcheck=0
EOF
fi

step "QEMU guest agent (so Proxmox shows the guest IP + metrics)"
yum -y install qemu-guest-agent >/dev/null 2>&1 || echo "  (qemu-guest-agent install returned non-zero)"
systemctl enable qemu-guest-agent >/dev/null 2>&1
systemctl start  qemu-guest-agent >/dev/null 2>&1 || true

step "Oracle Instant Client + sqlplus"
mkdir -p "$DEST/ic"
fetch instantclient-basiclite-linuxx64.zip "$DEST/ic/basic.zip" && unzip -oq "$DEST/ic/basic.zip" -d "$DEST/ic/"
fetch instantclient-sqlplus-linuxx64.zip    "$DEST/ic/sqlplus.zip" && unzip -oq "$DEST/ic/sqlplus.zip" -d "$DEST/ic/"
icdir=$(ls -d "$DEST"/ic/instantclient_* 2>/dev/null | head -1)
ln -sfn "$icdir" "$DEST/instantclient"
mkdir -p "$DEST/instantclient/network/admin"

step "Temurin JDK 17 (for SQL Developer / SQLcl)"
if [ ! -x "$DEST/jdk-17/bin/java" ]; then
  fetch temurin17.tar.gz "$DEST/temurin17.tar.gz" && \
  mkdir -p "$DEST/jdk-17" && tar xzf "$DEST/temurin17.tar.gz" -C "$DEST/jdk-17" --strip-components=1
fi

step "SQLcl"
[ -d "$DEST/sqlcl" ] || { fetch sqlcl-latest.zip "$DEST/sqlcl.zip" && unzip -oq "$DEST/sqlcl.zip" -d "$DEST/"; }

step "SQL Developer (no-jre)"
if [ ! -x "$DEST/sqldeveloper/sqldeveloper.sh" ] && [ ! -d "$DEST/sqldeveloper" ]; then
  fetch sqldeveloper-nojre.zip "$DEST/sqldeveloper.zip" && unzip -oq "$DEST/sqldeveloper.zip" -d "$DEST/sqldev_tmp/"
  sd=$(ls -d "$DEST"/sqldev_tmp/sqldeveloper* 2>/dev/null | head -1); [ -n "$sd" ] && mv "$sd" "$DEST/sqldeveloper"
  rm -rf "$DEST/sqldev_tmp"
fi
# point SQL Developer at JDK 17
if [ -d "$DEST/sqldeveloper" ]; then
  printf 'SetJavaHome %s\n' "$DEST/jdk-17" >> "$DEST/sqldeveloper/sqldeveloper/bin/sqldeveloper.conf" 2>/dev/null || true
fi

step "DBeaver CE"
if [ ! -d "$DEST/dbeaver" ]; then
  fetch dbeaver-ce-linux.tar.gz "$DEST/dbeaver.tgz" && mkdir -p "$DEST/dbeaver" && tar xzf "$DEST/dbeaver.tgz" -C "$DEST/dbeaver" --strip-components=1
fi

step "FileZilla + PuTTY (EPEL)"
yum -y install filezilla putty >/dev/null 2>&1 || echo "  (filezilla/putty install returned non-zero — continuing)"

step "Geany (native text editor) + default text-file handler"
yum -y install geany >/dev/null 2>&1 || echo "  (geany install returned non-zero — continuing)"
if command -v geany >/dev/null 2>&1; then
  # Make Geany the default handler for text-ish files.  Thunar/Xfce resolve
  # "open with" through the XDG mimeapps lists (system + per-user).
  cat > /etc/xdg/mimeapps.list <<'EOF'
[Default Applications]
text/plain=geany.desktop
text/x-log=geany.desktop
text/x-sql=geany.desktop
text/x-python=geany.desktop
text/csv=geany.desktop
application/x-shellscript=geany.desktop
application/x-perl=geany.desktop
application/x-desktop=geany.desktop
text/html=geany.desktop
EOF
  mkdir -p /home/student/.config
  cp /etc/xdg/mimeapps.list /home/student/.config/mimeapps.list
  chown -R student:student /home/student/.config 2>/dev/null || true
fi

step "profile + network config"
cat > /etc/profile.d/ebs-tools.sh <<EOF
# EBS lab client tools
export JAVA_HOME=$DEST/jdk-17
export PATH="$DEST/jdk-17/bin:$DEST/instantclient:$DEST/sqlcl/bin:\$PATH"
export LD_LIBRARY_PATH="$DEST/instantclient:\$LD_LIBRARY_PATH"
export TNS_ADMIN="$DEST/instantclient/network/admin"
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
EOF
chmod 644 /etc/profile.d/ebs-tools.sh

cat > "$DEST/instantclient/network/admin/sqlnet.ora" <<'EOF'
NAMES.DIRECTORY_PATH= (TNSNAMES, EZCONNECT)
EOF

{
  echo "# EBS lab DB aliases (class + sandboxes)"
  echo "EBSDB_CLASS=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=192.168.100.223)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=EBSDB)(INSTANCE_NAME=EBSDB)))"
  i=1; for ip in 231 232 233 234 235 241 242 243 244; do
    printf "EBSDB_STU%02d=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=192.168.100.%s)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=EBSDB)(INSTANCE_NAME=EBSDB)))\n" "$i" "$ip"
    i=$((i+1))
  done
} > "$DEST/instantclient/network/admin/tnsnames.ora"

# /etc/hosts friendly names (idempotent)
grep -q 'ebs-class' /etc/hosts || {
  { echo "192.168.100.223 ebs-class class"; i=1
    for ip in 231 232 233 234 235 241 242 243 244; do printf "192.168.100.%s ebs-stu%02d\n" "$ip" "$i"; i=$((i+1)); done
  } >> /etc/hosts
}

step "VNC server (x11vnc sharing the console :0, default PIN 29999)"
# x11vnc (EPEL) hard-requires Xvfb, which is in the ol7_optional_latest repo
yum -y --enablerepo=ol7_optional_latest install xorg-x11-server-Xvfb x11vnc zenity >/dev/null 2>&1 \
  || echo "  (x11vnc install returned non-zero — continuing)"
if command -v x11vnc >/dev/null 2>&1; then
  # default VNC password (students can change it later via the desktop launcher)
  x11vnc -storepasswd "${VNC_PIN:-29999}" /etc/x11vnc.pass >/dev/null 2>&1
  chmod 600 /etc/x11vnc.pass
  cat > /etc/systemd/system/x11vnc.service <<'UNIT'
[Unit]
Description=x11vnc - share the console display :0 (VNC on port 5900)
After=display-manager.service network.target
[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -forever -shared -loop \
  -rfbauth /etc/x11vnc.pass -rfbport 5900 -o /var/log/x11vnc.log
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable x11vnc.service >/dev/null 2>&1
  systemctl restart x11vnc.service >/dev/null 2>&1 || true
  # open the port if firewalld is running
  if systemctl is-active firewalld >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=5900/tcp >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1
  fi
  # root helper to change the VNC password (invoked via sudo by the launcher)
  cat > /usr/local/bin/set-vnc-password <<'HELPER'
#!/bin/bash
NEW="$(zenity --password --title='Set VNC password' 2>/dev/null)" || exit 1
[ -n "$NEW" ] || exit 1
x11vnc -storepasswd "$NEW" /etc/x11vnc.pass >/dev/null 2>&1
chmod 600 /etc/x11vnc.pass
systemctl restart x11vnc.service
zenity --info --text='VNC password changed.' 2>/dev/null
HELPER
  chmod 755 /usr/local/bin/set-vnc-password
  echo 'student ALL=(root) NOPASSWD: /usr/local/bin/set-vnc-password' > /etc/sudoers.d/vnc-password
  chmod 440 /etc/sudoers.d/vnc-password
fi

step "desktop launchers"
mkl() {  # mkl <name> <Exec> [icon]
  local name="$1" exec="$2" icon="${3:-}"
  {
    echo "[Desktop Entry]"
    echo "Type=Application"
    echo "Name=${name}"
    [ -n "$icon" ] && echo "Icon=${icon}"
    echo "Exec=env JAVA_HOME=$DEST/jdk-17 ${exec}"
    echo "Terminal=false"
    echo "Categories=Development;Database;"
  } > "/usr/share/applications/${name}.desktop"
  cp "/usr/share/applications/${name}.desktop" "/home/student/Desktop/${name}.desktop" 2>/dev/null || true
}
mkdir -p /home/student/Desktop
mkl "SQL-Developer" "$DEST/sqldeveloper/sqldeveloper.sh" "$DEST/sqldeveloper/icon.png"
mkl "DBeaver"       "$DEST/dbeaver/dbeaver"             "$DEST/dbeaver/icon.xpm"
mkl "FileZilla"     "/usr/bin/filezilla"                "/usr/share/icons/hicolor/48x48/apps/filezilla.png"
mkl "PuTTY"         "/usr/bin/putty"                    "/usr/share/pixmaps/putty.png"
cat > "/home/student/Desktop/SQLcl.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=SQLcl (terminal)
Icon=utilities-terminal
Exec=xfce4-terminal --hold -e "bash -lc 'sql /nolog'"
Terminal=false
Categories=Development;Database;
EOF
cat > "/home/student/Desktop/SSH-EBS.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=SSH - EBS class
Icon=utilities-terminal
Exec=xfce4-terminal --hold -e "bash -lc 'ssh -oStrictHostKeyChecking=no root@192.168.100.223'"
Terminal=false
EOF
cat > "/usr/share/applications/ChangeVNC.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Change VNC password
Icon=preferences-system-network
Exec=sudo /usr/local/bin/set-vnc-password
Terminal=false
Categories=System;
EOF
cp "/usr/share/applications/ChangeVNC.desktop" "/home/student/Desktop/ChangeVNC.desktop" 2>/dev/null || true
# Firefox launcher icon (created earlier without one)
for f in /home/student/Desktop/firefox-ebs.desktop /usr/share/applications/firefox-ebs.desktop; do
  [ -f "$f" ] && { grep -q '^Icon=' "$f" || echo 'Icon=/opt/firefox/browser/icons/mozicon128.png' >> "$f"; }
done
# Geany (native editor / default .txt handler) — ship the RPM's launcher
for d in /usr/share/applications/geany.desktop /usr/share/applications/org.geany.Geany.desktop; do
  [ -f "$d" ] && { cp "$d" "/home/student/Desktop/$(basename "$d")"; break; }
done
chown -R student:student /home/student/Desktop 2>/dev/null || true
chmod +x /home/student/Desktop/*.desktop 2>/dev/null || true

step "cleanup"
rm -f "$DEST"/ic/*.zip "$DEST"/*.zip "$DEST"/*.tgz "$DEST"/temurin17.tar.gz 2>/dev/null || true
echo; echo "=== install summary ==="
for p in "$DEST/instantclient/sqlplus" "$DEST/sqlcl/bin/sql" "$DEST/jdk-17/bin/java" "$DEST/dbeaver/dbeaver" "$DEST/sqldeveloper/sqldeveloper.sh"; do
  [ -e "$p" ] && echo "  OK  $p" || echo "  MISSING  $p"
done
command -v filezilla >/dev/null && echo "  OK  filezilla" || echo "  MISSING filezilla"
command -v putty     >/dev/null && echo "  OK  putty" || echo "  MISSING putty"
command -v geany     >/dev/null && echo "  OK  geany ($(geany --version 2>/dev/null | head -1))" || echo "  MISSING geany"
if command -v x11vnc >/dev/null; then
  echo "  OK  x11vnc (port 5900, service=$(systemctl is-enabled x11vnc 2>/dev/null || echo n/a))"
else
  echo "  MISSING x11vnc"
fi
if command -v qemu-ga >/dev/null; then
  echo "  OK  qemu-guest-agent (service=$(systemctl is-enabled qemu-guest-agent 2>/dev/null || echo n/a))"
else
  echo "  MISSING qemu-guest-agent"
fi
echo "=== done $(date) ==="
