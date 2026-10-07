#!/usr/bin/env bash
# add-students.sh — add N new students end-to-end.
#
#   scripts/add-students.sh <N>
#
# For each new student it:
#   1. finds a free static IP (ARP scan; flat-LAN best effort),
#   2. linked-clones 9000 -> 91NN (EBS) and 9200 -> 92NN (client),
#   3. appends both rows to scripts/inventory.conf,
#   4. provisions the EBS sandbox (scripts/provision-sandbox.sh),
#   5. boots the client VM,
#   6. creates the Proxmox user stuNN@pve with PVEVMUser on its two VMs.
#
# NOTE: flat-LAN static IPs overlap the router's DHCP pool. Prefer reserving a
# block on the router or moving the lab to an isolated vmbr1 (see PROGRESS.md).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib.sh"

N="${1:?usage: add-students.sh <N>}"
GOLDEN=9000; CLIENT_TEMPLATE=9200
IP_FIRST="${IP_FIRST:-244}"; IP_LAST="${IP_LAST:-254}"

max=$(ebs_rows | awk '$1!=9010{print $1-9100}' | sort -n | tail -1); max=${max:-0}
echo "== add-students: existing=$max, adding $N -> student $((max+1))..$((max+N)) =="

# --- find N free IPs --------------------------------------------------------
inuse=$(arp-scan -I vmbr0 192.168.100.0/24 2>/dev/null | awk '/^192/{print $1}')
used=$(inventory_rows | awk '$4 ~ /^192/{print $4}')
free=()
for last in $(seq "$IP_FIRST" "$IP_LAST"); do
  c="192.168.100.$last"
  echo "$inuse" | grep -qx "$c" && continue
  echo "$used"  | grep -qx "$c" && continue
  free+=("$c"); [ "${#free[@]}" -ge "$N" ] && break
done
[ "${#free[@]}" -ge "$N" ] || { echo "ERROR: only ${#free[@]} free IP(s) in .$IP_FIRST-.$IP_LAST (need $N)"; exit 1; }
echo "free IPs: ${free[*]}"

# --- clone + inventory ------------------------------------------------------
for k in $(seq 1 "$N"); do
  idx=$((max+k)); ebs=$((9100+idx)); cli=$((9200+idx)); ip=${free[$((k-1))]}
  ename="ebs1213-stu$(printf %02d "$idx")"; cname="client-stu$(printf %02d "$idx")"
  echo "== student $idx: $ename ($ebs) -> $ip ; $cname ($cli) =="
  qm clone "$GOLDEN" "$ebs" --name "$ename" --full 0 >/dev/null || { echo "clone $ebs failed"; exit 1; }
  qm set "$ebs" --memory 12288 --cores 4 --onboot 0 >/dev/null
  qm clone "$CLIENT_TEMPLATE" "$cli" --name "$cname" --full 0 >/dev/null || { echo "clone $cli failed"; exit 1; }
  qm set "$cli" --memory 2048 --cores 2 --onboot 0 >/dev/null
  printf "%-5s %-17s %-8s %s\n" "$ebs" "$ename" "ebs"    "$ip" >> "$INVENTORY"
  printf "%-5s %-17s %-8s %s\n" "$cli" "$cname" "client" "-"   >> "$INVENTORY"
done

# --- free the .230 placeholder, then provision the new EBS sandboxes --------
# A running client VM often holds .230 by DHCP, which would collide with a
# fresh clone's placeholder boot; stop clients first, restart them after.
echo "== stopping client VMs during provisioning (frees the .230 placeholder) =="
for row in $(client_rows | awk '{print $1}'); do qm stop "$row" >/dev/null 2>&1; done
for k in $(seq 1 "$N"); do "$HERE/provision-sandbox.sh" $((9100+max+k)) || echo "WARN: provision $((9100+max+k)) failed"; done

# --- boot all client VMs ----------------------------------------------------
for row in $(client_rows | awk '{print $1}'); do qm start "$row" >/dev/null 2>&1 || true; done

# --- Proxmox users + ACLs ---------------------------------------------------
for k in $(seq 1 "$N"); do
  idx=$(printf %02d $((max+k))); u="stu$idx@pve"
  if pveum user list 2>/dev/null | grep -q "$u"; then
    pveum user modify "$u" --password "$PVE_PASSWORD" >/dev/null 2>&1 || true
  else
    pveum user add "$u" --password "$PVE_PASSWORD" --comment "EBS lab student $((max+k))" >/dev/null 2>&1 || true
  fi
  pveum acl modify "/vms/$((9100+max+k))" --users "$u" --roles PVEVMUser >/dev/null 2>&1 || true
  pveum acl modify "/vms/$((9200+max+k))" --users "$u" --roles PVEVMUser >/dev/null 2>&1 || true
  echo "  $u -> /vms/$((9100+max+k)) + /vms/$((9200+max+k))"
done

echo
echo "Done. Next: create the EBS login(s) on the class instance with"
echo "  scripts/create-class-users.sh"
"$HERE/lab-status.sh"
