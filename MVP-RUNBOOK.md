# MVP Runbook — One Working EBS 12.1.3 Instance

Beginner-oriented, literal step-by-step for the simplest-first MVP described in
`PLAN.md` §0. **Follow in order. Do not skip Step 1.** Stop at MVP-A; do MVP-B
(Forms client) after the instance is safely snapshotted.

Two milestones:
- **MVP-A:** EBS is up, the HTML login page responds, and the instance is
  snapshotted. *(This is the real milestone.)*
- **MVP-B:** one Forms screen opens from a client machine.

Honesty note: keep this lab **offline / LAN-only**, non-commercial, self-study.
Never expose it to the internet. Default seeded passwords from Oracle must be
changed and never committed to this repo.

---

## Cost and licensing — the $0 guarantee

Every component in this MVP is **free to obtain and run**. The only cost is your
time and electricity. There are **no sub-charges, no trials that expire, and no
paid APIs/cloud calls** anywhere in this runbook.

| Component | Cost | The catch you must know |
|-----------|------|-------------------------|
| Proxmox VE host | $0 | Free/GPL. The optional "Enterprise repo" needs a paid subscription, but the free **no-subscription** repo is fine. Ignore the "You do not have a valid subscription" message — it is a nag, not a charge. |
| Oracle account (SSO) | $0 | Free sign-up; no card required. Used only to reach edelivery. |
| EBS 12.1.3 Vision appliance | $0 to download | **Not free software.** Download is free but Oracle's terms apply. See restrictions below. |
| Guest OS (Oracle Linux 6.5, inside the appliance) | $0 | Already included. A paid Oracle Linux support subscription is **not** needed and not purchased. |
| Client Java runtime (MVP-B) | $0 | The **applet plugin** needs **32-bit Oracle JRE 8** (the plugin `libnpjp2.so` exists only in Oracle JRE, not OpenJDK). Java SE 8 is free to download; Oracle's commercial-use terms apply only to paid/commercial use. For JWS you can instead use **OpenJDK 8 + IcedTea-Web** (GPL). |
| Client OS (MVP-B) | $0 | **Oracle Linux 7.9** ISO is free from yum.oracle.com. OL7 is EOL but fine offline. |
| Firefox ESR 52 **32-bit** (legacy applet client) | $0 | MPL, free from the Mozilla archive. Only the **32-bit** build keeps NPAPI. EOL/unsupported → offline only. |
| Console access | $0 | **noVNC in-browser** needs nothing installed; **SPICE** needs free `virt-viewer`. |
| Debian/ISO for any later VM | $0 | Free downloads. |

**Not part of this free path (avoid unless you already own a licence):**
- a **Windows** client VM (Windows itself is licensed), and
- **Oracle Java 8 for *commercial* use** — Java SE 8 is free to download and fine
  for self-study, but paid use needs a subscription. Note the applet plugin
  requires Oracle JRE 8 (OpenJDK 8 has no `libnpjp2.so`); for JWS you can use
  OpenJDK 8 + IcedTea-Web instead.

**Restrictions you must respect (they are legal, not technical):**
- Offline / LAN-only; non-commercial; development/self-study; **no redistribution**;
  **no production use**.
- Do not expose EBS to the public internet.
- Do not commit Oracle seeded passwords or any Oracle account credentials to git.
- edelivery downloads for this product are free. If the site ever asks for a paid
  **Support Identifier (CSI)**, a support contract, or payment, **STOP** — that is
  a different/entitled product; do not pay. Tell me and we'll find another route.

---

## Prerequisites (gather before you start)

- [ ] Access to the Proxmox web UI: `https://<proxmox-ip>:8006` (root or a user).
- [ ] Ability to open a **shell on the host** (web UI: select node → *Shell*, or
      `ssh root@<proxmox-ip>`).
- [ ] A free **Oracle account** (SSO) for edelivery — <https://profile.oracle.com>.
- [ ] A PC with a normal browser for testing.
- [ ] A place to save notes (seeded passwords, IPs, filenames) — **not** in git.

`<...>` = fill in your real values. Anything marked **(verify)** must be confirmed
on the actual host/VM before you trust it.

---

## Step 1 — Verify the host (read-only, 5 minutes)

In the Proxmox host shell:

```bash
pveversion
lscpu
free -h
pvesm status
vgs
lvs
df -h
```

Record:
```
Proxmox VE version:            (from pveversion)
CPU model / sockets / cores:   (from lscpu)
Total RAM:                     (from free -h)
Storage names + types:         (from pvesm status — look for lvmthin/ZFS/dir)
Free space:                    (from df -h / vgs)
```

**Checkpoints:**
- [ ] Proxmox VE 8.x or 9.x — note which (this host: **9.2.20**).
- [ ] CPU flags for PVE 8/9 (must show all four):
      `lscpu | grep -o -E 'cx16|popcnt|sse4_2|lahf_lm' | sort -u`
- [ ] At least one storage supports snapshots/linked clones (**LVM-thin, ZFS, or
      dir/qcow2**; needed later for clones, not for MVP-A).
- [ ] Enough free space for staging (Step 4) — see the size you read in Step 3.

> Send these outputs back so the rest of the plan can be sized to your real host.
> `lvs`/`pvesm status` tell us the exact storage name to use in Step 5 instead of
> the `local-lvm` placeholder.

---

## Step 2 — Create the `ebs-staging` VM (the staging workspace)

Per decision (2026-09-29): all download/staging happens in a dedicated Proxmox
VM, **not** on the host.

**What OS and how many resources:**
- **OS: Debian 12/13 minimal** (netinst ISO). No GUI.
- **vCPU 2 · RAM 3 GB · OS disk ~32 GB.** (Download is network-bound; unzip/tar is
  CPU+disk. More RAM/CPU buys nothing.)
- **Staging space ~300 GB**, ideally on a folder the **host exports** (NFS/9p,
  e.g. `/srv/ebs-media`) so the host can import directly with no second copy.
  If you'd rather keep it on the VM's own disk, make that disk ~300 GB and plan to
  copy the final `.ovf`/`.vmdk` back to the host before import.
- VMID e.g. **900**; throwaway — delete it after the golden disk is imported.

Create the VM shell (as built on this host: Debian 13, `vmbr0`):
```bash
# NOTE: --cpu host is fine for the Debian staging VM (modern kernel).
qm create 900 --name ebs-staging \
  --memory 3072 --cores 2 --sockets 1 \
  --cpu host --machine pc --bios seabios \
  --scsihw virtio-scsi-pci --ostype l26 \
  --net0 virtio,bridge=vmbr0 --onboot 0 \
  --scsi0 local-lvm:32                     # ~32 GB OS disk
qm set 900 --ide2 local:iso/debian-13.7.0-amd64-netinst.iso,media=cdrom
qm set 900 --boot order=scsi0\;ide2
qm start 900
```

Then, inside Debian, create the staging mount (host-exported NFS example):
```bash
sudo apt update && sudo apt install -y wget unzip tar nfs-common
sudo mkdir -p /srv/ebs-media
# sudo mount <host>:/srv/ebs-media /srv/ebs-media    # or 9p/virtiofs
df -h /srv/ebs-media        # confirm ~300 GB free before downloading
```

Save credentials locally, never in git:
```bash
umask 077
cat >> ~/.ebs-lab.env <<'EOF'
# EBS 12.1.3 lab secrets — chmod 600, never commit
EBS_STAGING_HOST=<proxmox-host>
EOF
chmod 600 ~/.ebs-lab.env
```

**Deferred:** no Docker/LXC for this; the `ebs-staging` VM replaces staging on the
host. (Per-student client VMs and a DNS server come later.)

---

## Step 3 — Get the appliance from Oracle

Do this in a browser on your PC.

1. Go to <https://edelivery.oracle.com> and sign in with your Oracle account.
2. Filter by **Linux/OVM/VMs**.
3. Search the **Release** for `Oracle VM Virtual Appliance for Oracle
   E-Business Suite 12.1.3` (or search "e-business").
4. Select the **12.1.3 VISION** virtual appliance → add to cart → Continue.
   - Confirm it is the **2014 "Virtual Appliances"** pack (Oracle Linux 6.5,
     OVM + VirtualBox compatible), **not** the older 2013 "Oracle VM Templates"
     pack (Oracle Linux 5 + a **Xen** kernel that won't boot on Proxmox).
   - The Single Node VISION pack's catalog part numbers are
     **V46557-01 … V46563-01** (**seven** entries, each split 1-of-2 / 2-of-2 =
     14 zips, ~51.5 GB).
5. Accept the **Oracle Standard Terms and Restrictions**. No Support Identifier
   (CSI) is required — if it demands one or payment, STOP.

> **Availability caveat (checked 2026-09-29):** Oracle's EBS VM page still lists
> the 12.1.3 appliance and cites MOS 1906691.1, but the eDelivery catalog is now
> behind sign-in and the latest *public* confirmation of the 12.1.3 pack is 2022.
> Confirm it is actually listed before committing to the long download.
6. **Open the media-pack readme / documentation.** **Note:** the 2014 pack we
   downloaded had **no readme inside the zips and no published checksums** —
   record whatever the edelivery page shows and treat seeded passwords as
   *try-first* (verify on the VM). Record:
   - exact file names + how many parts,
   - published checksums (if any),
   - seeded OS / EBS / DB passwords (**local note only**).
7. Copy each file's download URL, then **inside the `ebs-staging` VM** (Step 2)
   download resumably into the shared folder:
   ```bash
   cd /srv/ebs-media
   wget -c '<each-file-url>'        # -c resumes if the slow link drops
   # repeat the same command until each file reports 100%
   ```

```
Files + sizes:
Checksums published? (y/n):
Approx total size:
```

**Checkpoints:**
- [ ] All parts present and full-size (`ls -lh`).
- [ ] Checksums match (if published): `sha256sum <file>`.
- [ ] Exact appliance **OS/EBS versions** recorded (expected OL 6.5 + EBS 12.1.3).

**If the product is not found / not downloadable**, stop and tell me — the
edelivery catalog changes, and we may need an alternative acquisition route.

---

## Step 4 — Unzip, concatenate, extract the OVA

Still inside the `ebs-staging` VM, in the shared folder `/srv/ebs-media`.
**The exact part naming comes from the readme — adjust the glob to match.**

```bash
cd /srv/ebs-media

# 1) Unzip every part (keep any already-extracted files)
for z in ./*.zip; do unzip -n "$z"; done
ls -lh

# 2) Concatenate the split OVA parts into one OVA.
#    Match the real names from the readme, e.g. *.ova.part* or *.ova.00*
cat ./*.ova.part* > EBS1213_VISION.ova     # (verify) adjust pattern
ls -lh EBS1213_VISION.ova

# 3) Extract the OVF + VMDK
tar xf EBS1213_VISION.ova
ls -lh ./*.ovf ./*.vmdk
```

**Checkpoints:**
- [ ] `unzip -t <zips>` → "No errors detected".
- [ ] Concatenated `.ova` size = sum of the parts.
- [ ] `tar tf` listed one `.ovf` + one `.vmdk` (+ manifest) — now extracted.
- [ ] Note the **exact VMDK filename** for Step 5.

---

## Step 5 — Create the VM and import the disk

Use i440fx + SeaBIOS + LSI SCSI so the guest keeps its expected `sda` disk.
Replace `local-lvm` with your real storage name from Step 1.

> **Why create + `importdisk`:** `qm importovf` *creates the VM itself* and fails
> if VMID 9000 already exists. Since we want to force the hardware (i440fx /
> SeaBIOS / LSI / e1000), create the shell first, then `qm importdisk` the VMDK.

```bash
# 1) Create the VM shell (golden, VMID 9000)
# NOTE: --cpu Westmere, NOT host -- the OL6 UEK kernel panics on host CPU flags.
qm create 9000 --name ebs1213-golden \
  --memory 12288 --cores 4 --sockets 1 \
  --cpu Westmere --machine pc --bios seabios \
  --scsihw lsi --ostype l26 --balloon 0 \
  --net0 e1000,bridge=vmbr0 --onboot 0

# 2) Import the extracted VMDK. NOTE: on LVM-thin (local-lvm) the disk is stored
#    as raw; --format qcow2 is only valid for file storage (dir/NFS) -> omit it.
qm importdisk 9000 "/srv/ebs-media/<VMDK-FILENAME>" local-lvm

# 3) Attach it as scsi0 and make it bootable
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --boot order=scsi0

# 4) Console access
qm set 9000 --serial0 socket --vga std

# 5) Review BEFORE booting
qm config 9000
```

Alternate single command (lets the OVF set the hardware; **do not** also run step 1):
```bash
qm importovf 9000 /srv/ebs-media/<OVF-FILENAME> local-lvm
qm set 9000 --machine pc --bios seabios --scsihw lsi --balloon 0 --net0 e1000,bridge=vmbr0
```

**Checkpoints:**
- [ ] `qm config 9000` shows `machine: pc`, `bios: seabios`, `scsihw: lsi`,
      `balloon: 0`, an `e1000` NIC, and `scsi0` on your real storage.
- [ ] The disk is thin and the right size (resize later if needed).

> `e1000` is the safe first NIC for this Oracle Linux 6.5 guest (the appliance
> was built for Oracle VM/VirtualBox); `virtio` usually works but verify.
> `vmbr0` is the verified bridge on this host. The private lab VLAN (`vmbr1`) is
> part of the full build, not strictly required for MVP-A.

---

## Step 6 — First boot and network

```bash
qm start 9000
qm terminal 9000        # or use the web UI console; Ctrl-O then Ctrl-Q to exit
```

In the guest console, log in as `root` (there was **no readme in the media** — use
a community-seeded credential and change it).

```bash
# What network interface do we have?
ip addr
cat /etc/sysconfig/network-scripts/ifcfg-eth0 2>/dev/null

# If it came up as eth1 instead of eth0 (common after import), fix and reboot:
rm -f /etc/udev/rules.d/70-persistent-net.rules
# edit ifcfg-eth0 to the right device, then:
# reboot
```

Set a **static IP** (the appliance ships hostname `ebs` / `ebs.example.com`, and
the EBS context is already built around it — **do not invent a new hostname**):
```bash
# Preferred: the appliance's own helper (updates the context and runs AutoConfig)
sh /u01/install/scripts/configstatic.sh

# Manual fallback — NOTE: Oracle Linux 6.5 has NO `hostnamectl` (that is OL7+):
vi /etc/sysconfig/network                      # HOSTNAME=ebs.example.com
vi /etc/sysconfig/network-scripts/ifcfg-eth0   # BOOTPROTO=static, IPADDR, NETMASK, GATEWAY
vi /etc/hosts                                  # <ip>  ebs.example.com  ebs
service network restart
```

> The 2014 appliance ships wrapper scripts — check `/u01/install/scripts/`
> (e.g. `configstatic.sh`) and `/u01/install/VISION/scripts/`. Using the
> provided script for static IP/hostname re-runs the EBS configuration for you,
> which is safer than hand-editing. **(verify on VM.)**

**Checkpoints:**
- [ ] `hostname -f` returns the expected name.
- [ ] `ping -c2 <its-own-ip>` and `ping -c2 ebs` succeed.
- [ ] `ip addr` shows the intended IP.

> Changing hostname/IP usually requires an EBS reconfigure (Step 7). Prefer the
> appliance's own scripts / **MOS 1906691.1**; do not guess. (There is **no readme
> in the media** — see Step 3.)

---

## Step 7 — Start EBS and verify the login page (MVP-A core)

The 2014 appliance puts **both tiers on one VM**: the **DB** under
`/u01/install/VISION` and the **apps tier** under `/u01/install/APPS`. Start them
as the **`oracle`** user via the appliance wrappers (they feed the APPS password
for you):

```bash
# as root:
su - oracle -c "/u01/install/VISION/scripts/startvisiondb.sh"   # listener + DB
su - oracle -c "/u01/install/APPS/scripts/startapps.sh"         # app tier

# sanity / env
su - oracle
source /u01/install/APPS/apps/apps_st/appl/APPSEBSDB_ebs.env   # CONTEXT_NAME=EBSDB_ebs
echo "$ADMIN_SCRIPTS_HOME $APPL_TOP $ORACLE_HOME"
$ADMIN_SCRIPTS_HOME/adopmnctl.sh status                        # oacore/forms/oafm/OHS
```

> **If the login page returns HTTP 500** (OC4J servlet error), the FND `.dbc` is
> almost certainly still the shipped template (`DB_HOST=host_name`): run
> `$ADMIN_SCRIPTS_HOME/adautocfg.sh appspass=apps` as `oracle`, then
> `/u01/install/APPS/scripts/startapps.sh`.
> **Timing:** OACORE/OAFM can read `Init` for ~30–60 s after start — wait and
> re-check `adopmnctl.sh status` before concluding it failed.

Verify the web tier (12.1.3 uses HTTP **8000** and DB **1521**; **not** 7001):
```bash
netstat -tlnp | grep -E '8000|1521'
curl -I http://127.0.0.1:8000/OA_HTML/AppsLogin
```

From your PC's browser:
```
http://<guest-ip>:8000/OA_HTML/AppsLogin
```

**Checkpoints:**
- [ ] Listener `READY`; Apache + concurrent managers report running.
- [ ] `curl` returns HTTP 200/302 (not connection refused).
- [ ] Login page **renders in a normal browser**.
- [ ] Log in with a seeded EBS user.
- [ ] **Change every default password** (OS, DB SYS/SYSTEM/APPS, seeded users)
      and record them locally.

> If the login page doesn't load, it's almost always networking (hostname/IP
> mismatch) or a service not started — not Forms.

---

## Step 8 — Snapshot (MVP-A done)

```bash
qm shutdown 9000                 # clean shutdown, do not force-stop
qm snapshot 9000 golden-clean --description "Pristine R12.1.3 Vision, pw changed"
qm listsnapshot 9000             # expect golden-clean present
```

**MVP-A is complete:** one working instance + a rollback point. Stop here.

**Deferred:** do *not* yet build clones, the class instance, the client VM, or
helper containers. Bask in the working instance first.

---

## Step 9 — MVP-B: one Forms screen (client)

R12.1.3 Forms needs a Java runtime. **Decided 2026-09-29:** build a dedicated
**Oracle Linux 7.9 client VM per student** (template **9200** → clones
**9201–9212**) running the **legacy applet** stack — so the stock appliance needs
**no server patching**:

- Browser: **32-bit Firefox ESR 52.9.0esr** (Mozilla archive) — last NPAPI build.
- Runtime: **32-bit Oracle JRE 8** (`linux-i586`) — only runtime with
  `libnpjp2.so`; free for non-commercial/self-study.
- Wiring: `ln -s <jre>/lib/i386/libnpjp2.so ~/.mozilla/plugins/` → check
  `about:plugins`.
- Access: **noVNC in-browser** (default) or **SPICE** (`vga: qxl`). RDP rejected
  on OL7.
- Disable auto-updates; add the EBS URL to the Java **Exception Site List** and
  allow legacy/SHA-1 JARs.

Build the client template **once**, verify a Forms screen opens, then snapshot and
linked-clone it. (The Oracle-supported alternative, Java Web Start, needs
server-side patches on 12.1.3 — deferred.)

For MVP-B it's **fine to test from your own PC first**, and fine to **stop at
MVP-A** for now. This is an uncertified Linux config; expect to spend the
troubleshooting time on JRE security settings — see `RESEARCH.md` §7.

**Checkpoint:**
- [ ] At least one Forms screen opens (e.g. a basic navigation form).

---

## Troubleshooting quick table

| Symptom | Likely fix |
|---------|-----------|
| VM won't boot / "no bootable device" | Controller must be **LSI SCSI or SATA**; boot order `scsi0`. |
| Kernel panic on boot (`dtrace_psinfo_alloc` / `oops_end`) | OL6 UEK panics with `--cpu host` → `qm set 9000 --cpu Westmere` |
| NIC is `eth1` after import | Delete `70-persistent-net.rules`, fix `ifcfg-eth0`, reboot. |
| Login page times out | Guest IP/hostname mismatch; service not started; firewall. |
| Services won't start after IP change | Re-run Autoconfig; check `/etc/hosts` + hostname. |
| Login page **HTTP 500** (OC4J servlet error) | FND `.dbc` is still the shipped template (`DB_HOST=host_name`) → `adautocfg.sh appspass=apps` as `oracle`, then `startapps.sh`. |
| OACORE/OAFM show `Init` right after start | Timing — wait 30–60 s, re-check `adopmnctl.sh status`. |
| Forms won't launch | Applet needs **32-bit** Firefox ESR 52 + **32-bit Oracle JRE 8**; JWS needs server patches. See Step 9. |
| `qm importdisk --format qcow2` errors | `qcow2` is invalid on LVM-thin → drop `--format` or use `dir`/ZFS. |
| Product not on edelivery | Stop — catalog changes; confirm the 2014 "Virtual Appliances" pack is listed. |
| Out of staging space | Delete `.zip`/parts/`.ova` after successful import. |

---

## Do NOT do yet (deferred optimisation)

- Shared class instance + 12 per-student EBS clones (post-MVP).
- Per-student client VMs (client template 9200 → clones 9201–9212).
- Docker/LXC helper services, DNS server, Ansible.
- R12.2.12 instance.
- Exposing anything to the internet.
