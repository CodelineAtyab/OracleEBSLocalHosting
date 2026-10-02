# Oracle E-Business Suite Training Lab on Proxmox

A self-hosted, offline, zero-license-cost lab for training students on **Oracle
E-Business Suite (EBS) R12.1.3 Vision**, built on a single HP ProLiant DL360
running Proxmox VE.

The goal is upskilling: give each student (and each new cohort) a working EBS
environment to practise on — functional navigation and setups, plus Apps DBA
work (patching, Autoconfig, cloning, admin utilities, DB administration).

---

## 1. Context and constraints

| Item | Value |
|------|-------|
| Host | HP ProLiant DL360 (2× Xeon Gold 6138, 40c/80t) |
| Hypervisor | **Proxmox VE 9.2.20** |
| RAM | **188 GiB** |
| Storage | **~1.67 TiB LVM-thin** (`local-lvm`) + ~85 GiB `local` dir |
| Internet | **Slow** (favours smaller downloads) |
| Audience | **6–15 concurrent** students |
| Budget | **$0** — no paid licenses, no cloud |
| Institution | Informal / non-commercial training (not Oracle Academy eligible) |
| Primary platform | **EBS 12.1.3 Vision** (pre-built Oracle VM appliance) |
| Optional later | EBS 12.2.12 Vision (for ADOP / WebLogic / DB 19c skills) |

### Why 12.1.3 first
- Pre-built single-node Vision **virtual appliance** is free to download from
  Oracle Software Delivery Cloud (`edelivery.oracle.com`).
- Much **lighter** than 12.2 (no WebLogic, database is 11g) → more instances fit
  on ~1.67 TiB / 188 GiB.
- Teaches core EBS architecture, Autoconfig, patching (`adpatch`), AD utilities,
  concurrent managers, cloning, and DBA fundamentals.

### Known trade-off
R12.1.3 is **end-of-life** and is *not* what most employers run today (modern
work is 12.2 + WebLogic + Online Patching/ADOP). Keep 12.1.3 for breadth and
scale, and add **one 12.2.12 instance** in a later phase for employability.

### Licensing (honest scope)
EBS is **not** free or open-source software. The edelivery download is free to
obtain but is governed by Oracle's standard terms. There is **no explicit free
classroom license**; Oracle Academy would be that route but this is not an
accredited institution. This lab is therefore scoped as an **offline, LAN-only,
non-commercial, development/self-study environment** with **no redistribution
and no production use**. Do not expose it to the public internet or use it to
deliver paid client work.

---

## 2. Target architecture

```
                        Proxmox VE host (DL360, 188 GiB RAM / ~1.67 TiB)
                                     |
        vmbr1 (lab VLAN, e.g. 10.10.10.0/24), local DNS/hosts
                                     |
   +----------------+   +----------------------+   +---------------------------+
   | Golden template|   | Shared class instance |   | Per-student EBS sandboxes |
   | ebs1213-golden |   | ebs1213-class         |   | ebs1213-stu01 .. stu12    |
   | (shut down,    |   | functional setups &   |   | Apps DBA practice:        |
   |  snapshotted)  |   | navigation for many   |   | patching, autoconfig,     |
   |                |   | students at once      |   | adadmin, cloning, RMAN    |
   +----------------+   +----------------------+   +---------------------------+
                                     |
                   +---------------------------------------+
                   | client-template 9200                  |
                   | -> client-stu01..12 (linked clones)   |
                   | OL7.9 + 32-bit FF ESR52 + 32-bit JRE8 |
                   +---------------------------------------+
                              -> students connect via noVNC (or SPICE)

  ebs-staging (900, Debian 12/13) = temporary download/extract workspace, deleted after import
```

- **Golden template** — pristine, shut down, snapshotted. Never boot it for class.
- **Shared class instance** — one instance, many EBS users/responsibilities.
- **Per-student instances** — **linked clones** (qcow2 backing chain on dir/ZFS, or
  LVM-thin snapshots) so the ~150 GB base image is shared and each clone adds only
  a small delta.
- **Client VMs** — one per student (OL7.9 + 32-bit Firefox ESR52 + 32-bit Oracle
  JRE 8) to run the Forms applet; accessed via noVNC or SPICE (§10).
- **Staging VM** — throwaway; see `PLAN.md` §1.3.

### Resource budget (host: 188 GiB RAM, ~1.67 TiB)

| Item | vCPU | RAM | Disk |
|------|------|-----|------|
| EBS appliance (golden) | 4 | 12 GB | **300 GiB thin** (VMDK virtual size) |
| Shared class instance | 4 | 12 GB | clone |
| 12 × student EBS clones | 4 each | 10 GB each | linked deltas |
| Client template | 2 | 2 GB | 20–40 GB |
| 12 × client clones | 2 each | 2 GB each | linked deltas |

RAM: 12×10 + 12 + 12×2 = **~156 GB of ~188 GiB** — workable but **tight**; cap how
many EBS sandboxes run at once. Storage: golden ~300 GiB + class full clone + deltas
≈ **800–900 GiB of 1.67 TiB**, and only fits because clones are linked. Full detail:
`PLAN.md` §2.1.

---

## 3. Prerequisites

- Oracle account (free) for `edelivery.oracle.com`.
- A resuming download manager or `wget -c` (slow link; download is tens of GB).
- Free staging space (~**300 GB**) on the Proxmox host, exposed to the
  `ebs-staging` VM via NFS/9p (unzip + concatenate + extract).
- Proxmox storage that supports **linked clones / snapshots** — **LVM-thin, ZFS,
  or dir/qcow2** all qualify. Check with `pvesm status`.
- Local DNS or static `/etc/hosts` so EBS hostnames resolve for clients.

### Host verification (run these first — read-only)
```bash
pveversion
lscpu | grep -E 'Model name|Virtualization'
# Proxmox VE 8/9 needs x86-64-v2; the Gold 6138 passes:
lscpu | grep -o -E 'cx16|popcnt|sse4_2|lahf_lm' | sort -u
pvesm status
vgs; lvs
df -h
```

---

## 4. Phase 1 — Acquire the R12.1.3 Vision appliance

1. Sign in at <https://edelivery.oracle.com> (sign-in is now required even to
   browse).
2. Filter products by **Linux/OVM/VMs**.
3. Search by **Release** for `Oracle VM Virtual Appliance for Oracle E-Business
   Suite 12.1.3` (or search "e-business").
4. Confirm it is the **2014 "Virtual Appliances"** pack (Oracle Linux 6.5,
   compatible with Oracle VM Manager **and** VirtualBox) — **not** the older 2013
   "Oracle VM Templates" pack (Oracle Linux 5 + a **Xen-PV** kernel that will not
   boot on Proxmox). The Single Node VISION pack's catalog part numbers are
   **V46557-01 … V46562-01** (six entries, each split 1-of-2 / 2-of-2).
5. Continue → accept the Oracle Standard Terms and Restrictions → download the
   media pack. Download is free with a free Oracle account; **no Support
   Identifier (CSI) is required**. If the site demands a CSI or payment, STOP —
   that is a different product.
6. Read the included **readme** — it lists the seeded OS/EBS passwords and the
   exact part/file names.

> Availability caveat (checked 2026-09-29): Oracle's EBS VM page still lists the
> 12.1.3 appliance and cites Doc 1906691.1, but the eDelivery catalog is now
> behind sign-in and the latest *public* confirmation of the 12.1.3 pack on
> eDelivery is 2022. Confirm it is actually there before committing to the long
> download. EBS 12.1.3 entered **Sustaining Support on 2022-01-01**.

> Reference deployment guide: **My Oracle Support Doc ID 1906691.1 — Oracle VM
> Virtual Appliances for Oracle E-Business Suite Deployment Guide, Release 12.1.3.**
> The appliance ships **Oracle Linux 6.5**, EBS 12.1.3 (Apps RPC1, CPU Apr 2014),
> DB **11.2.0.4**, Forms/Reports **10.1.2.3**, JDK **1.7.0_60**.

Download with resume (slow links), **inside the `ebs-staging` VM**, into the
shared staging folder:
```bash
mkdir -p /srv/ebs-media && cd /srv/ebs-media   # mount of the host-shared folder
wget -c <each-file-url>
```

---

## 5. Phase 2 — Stage and extract the OVA

**All of Phase 1–2 runs inside the dedicated `ebs-staging` VM** (Debian 12/13, 2
vCPU, 2–4 GB RAM, ~32 GB OS disk + ~300 GB host-shared staging space) — not on
the host. Stage on a folder the host can later read for import (host NFS/9p
share, e.g. `/srv/ebs-media`). See `PLAN.md` §1.3.

```bash
cd /srv/ebs-media           # or wherever the shared staging folder is mounted
# 1) Unzip all parts
for z in *.zip; do unzip -n "$z"; done

# 2) Concatenate the split OVA parts into one file
#    (adjust the exact names to match the media pack readme)
cat Oracle-E-Business-Suite-12.1.3_VISION_INSTALL.ova.part* \
    > EBS1213_VISION.ova

# 3) Extract the OVF + VMDK
tar xf EBS1213_VISION.ova
ls -lh *.ovf *.vmdk
```

> If the parts are `.ova.00`, `.ova.01`, ... use those names instead.
> You can delete the extracted/staging copies after the disk is imported.

---

## 6. Phase 3 — Import into Proxmox and create the VM

Use **i440fx + SeaBIOS + LSI SCSI (or SATA)** so the guest keeps its expected
disk device (`sda`) and does not need initramfs/virtio surgery.

```bash
# Create the VM shell (adjust VMID/storage names)
# NOTE: use --cpu Westmere, NOT host — the OL6 UEK kernel panics on host CPU flags.
qm create 9000 --name ebs1213-golden \
  --memory 12288 --cores 4 --sockets 1 \
  --cpu Westmere --machine pc --bios seabios \
  --scsihw lsi --ostype l26 --balloon 0 \
  --net0 e1000,bridge=vmbr0 --onboot 0

# Import the extracted VMDK, then attach it.
# NOTE: on LVM-thin (local-lvm) the disk is stored as raw; --format qcow2 only
# applies to file storage (dir/NFS), so omit it here.
qm importdisk 9000 /srv/ebs-media/<VMDK-FILENAME> local-lvm
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --boot order=scsi0

# Optional: console access
qm set 9000 --serial0 socket --vga std

qm start 9000
qm terminal 9000      # or use the web console
```
> `qm importovf` is an alternative that **creates the VM itself** (don't also run
> `qm create`): `qm importovf 9000 /srv/ebs-media/<OVF-FILENAME> local-lvm`, then
> `qm set 9000 --machine pc --bios seabios --scsihw lsi --balloon 0 --net0 e1000,bridge=vmbr0`.

Notes:
- Use the **2014 "Virtual Appliances" media pack** (OL 6.5, OVM/VirtualBox
  compatible), **not** the older 2013 "Oracle VM Templates" pack (Oracle Linux 5
  and a **Xen-PV** kernel that will not boot outside Oracle VM).
- NIC: `e1000` is the safe first choice for this Oracle Linux 6.5 guest;
  `virtio` usually works but verify. Keep `--balloon 0` (fixed RAM) for the DB.
- If networking is broken, check NIC name drift: OL6 normally uses `eth0`. Fix
  `/etc/udev/rules.d/70-persistent-net.rules` and
  `/etc/sysconfig/network-scripts/ifcfg-eth0` if it came up as `eth1`.
- Keep the deployed disk reasonably sized (e.g. 150–200 GB) and **thin** where
  possible.
- This is an Oracle VM/VirtualBox appliance running on an **uncertified**
  Proxmox/KVM path — treat it like any OVA import.

---

## 7. Phase 4 — First boot, network reconfigure, verification

1. Boot the VM and log in with the seeded `root` credentials from the readme.
2. Set a **static IP** on the lab VLAN and configure hostname + `/etc/hosts`.
3. Reconfigure the EBS network/hostname per **MOS Doc 1906691.1** (listener,
   `tnsnames`, context file, then Autoconfig).
4. Start the EBS services via the appliance's admin scripts, then verify the
   login page:
   - Default HTTP port is typically **8000**; the DB listener is **1521**.
     (Forget `7001` — that is a 12.2/WebLogic port, not 12.1.3.) Confirm, e.g.:
     ```bash
     netstat -tlnp | grep -E '8000|1521'
     ```
   - Browse to `http://<ip>:8000/OA_HTML/AppsLogin`.
5. **Change every default password** (OS users, DB SYS/SYSTEM/APPS, EBS seeded
   users, WebLogic/OC4J if applicable).

### Useful EBS environment
```bash
# 2014 appliance layout: install dir is /u01/install/VISION with wrapper scripts
ls /u01/install/VISION/ 2>/dev/null
ls /u01/install/scripts/ 2>/dev/null      # e.g. configstatic.sh (set static IP+hostname)
# Standard apps-tier env file is $APPL_TOP/APPS<CONTEXT>.env (name varies):
source $APPL_TOP/APPS<CONTEXT>.env
# Common admin script dirs:
echo $ADMIN_SCRIPTS_HOME $COMMON_TOP $APPL_TOP   # ADMIN_SCRIPTS_HOME=$INST_TOP/admin/scripts
$ADMIN_SCRIPTS_HOME/adautocfg.sh             # Autoconfig
$ADMIN_SCRIPTS_HOME/adapcctl.sh status       # Apache
$ADMIN_SCRIPTS_HOME/adcmctl.sh status        # Concurrent managers
$ADMIN_SCRIPTS_HOME/adstrtal.sh              # start all (prompts for APPS password)
$ADMIN_SCRIPTS_HOME/adstpall.sh              # stop all
```
> Exact paths/script names vary by appliance revision — confirm on the VM.
> This is not the 12.2 layout (`/u01/install/APPS/EBSapps.env`).

---

## 8. Phase 5 — Golden template and snapshots

```bash
# Shut down cleanly, then snapshot the pristine state
qm shutdown 9000
qm snapshot 9000 golden-clean --description "Pristine R12.1.3 Vision, pw changed"

# Convert to a template (optional; keeps it from accidental boots)
qm template 9000
```

Booting the golden VM for class is forbidden — clone it instead.

---

## 9. Phase 6 — Shared class instance, student EBS clones, and client clones

```bash
# Shared functional instance
qm clone 9000 9010 --name ebs1213-class --full 1
qm set 9010 --memory 12288 --onboot 1

# Per-student EBS linked clones (small deltas; requires linked-clone storage)
for i in $(seq -w 1 12); do
  qm clone 9000 91$i --name ebs1213-stu$i --full 0
  qm set 91$i --memory 10240 --onboot 0
done
```

Then clone the **client template (9200)** built in §10:
```bash
for i in $(seq -w 1 12); do
  qm clone 9200 92$i --name client-stu$i --full 0
  qm set 92$i --memory 2048 --onboot 0
done
```

Networking: give each clone a unique static IP on `vmbr1` and matching
`/etc/hosts`/DNS entry so the EBS hostname resolves. Keep hostnames consistent
with the EBS context (changing the IP alone is usually fine; changing the
hostname requires Autoconfig).

> **RAM budget:** 12×EBS (10 GB) + class (12 GB) + 12×client (2 GB) ≈ **156 GB of
> ~188 GiB**. Cap how many EBS sandboxes run simultaneously.

---

## 10. Phase 7 — Client access (Forms applet)

**Decided 2026-09-29:** one **Oracle Linux 7.9 client VM per student** (template
**9200** → clones **9201–9212**), running the legacy applet stack so the **stock
12.1.3 appliance needs no server patching**:

- Browser: **32-bit Firefox ESR 52.9.0esr** (Mozilla archive) — last NPAPI build.
- Runtime: **32-bit Oracle JRE 8** (`linux-i586`) — the only runtime with
  `libnpjp2.so`; free for non-commercial/self-study.
- Wiring: `ln -s <jre>/lib/i386/libnpjp2.so ~/.mozilla/plugins/` → verify in
  `about:plugins`.
- Access: **noVNC in-browser** (default; Proxmox user with `VM.Console`),
  **SPICE** optional (`vga: qxl` + `virt-viewer`). RDP rejected (xrdp unavailable
  on Oracle Linux 7).
- Disable auto-updates; add the EBS URL to the Java **Exception Site List** and
  allow legacy/SHA-1 JARs.

**Build the client template once** (install OL7.9 + i686 libs, Firefox ESR52,
JRE 8, plugin), confirm a Forms screen opens, then snapshot and linked-clone it to
9201–9212. See `PLAN.md` §1.4 and `RESEARCH.md` §7.

**Community/uncertified config:** Oracle certifies the FF-ESR52 + JRE8 plugin path
on **Windows only**. The Oracle-supported alternative — **Java Web Start (JWS)** —
needs server-side patches on 12.1.3 and is deferred. MVP-A skips all of this;
validate the HTML login page from any browser first.

---

## 11. Phase 8 — Curriculum, batches, and reset

### Free learning material
- Oracle **MyLearn / Learning Explorer** — free EBS and Database courses.
- Oracle EBS 12.1.3 Documentation Library.
- Community walkthroughs (e.g. techgoeasy, rishoradev) for cross-checks.

### Suggested tracks
- **Functional:** navigation, responsibilities, setups, order-to-cash,
  procure-to-pay, GL/AP/AR basics.
- **Apps DBA:** `adadmin`, `adpatch`, Autoconfig, AD utilities, concurrent
  managers, file system layout, cloning, RMAN, 11g database administration.

### Reset between batches
```bash
# Option A: roll student clones back to the snapshot
for i in $(seq -w 1 12); do qm rollback 91$i golden-clean; done

# Option B: destroy and re-clone from the template (cleanest)
for i in $(seq -w 1 12); do
  qm stop 91$i --skiplock 1 || true
  qm destroy 91$i --purge 1
  qm clone 9000 91$i --name ebs1213-stu$i --full 0
done

# Client clones: same idea, from the client template (9200)
for i in $(seq -w 1 12); do
  qm stop 92$i --skiplock 1 || true
  qm destroy 92$i --purge 1
  qm clone 9200 92$i --name client-stu$i --full 0
done
```

---

## 12. Phase 9 (optional) — Add one R12.2.12 instance

For modern employability skills (WebLogic, **Online Patching/ADOP**, DB 19c,
Edition-Based Redefinition):
- Download **Oracle VM Virtual Appliance for Oracle E-Business Suite 12.2.12**
  (announced May 2023; deployment guide **MOS 2933812.1**). Size is large
  (tens of GB, roughly ~68 GB across multiple parts — *verify on edelivery*).
- Same import method; allow **24–32 GB RAM** and **~400 GB** disk.
- R12.2.12 ships **Oracle Linux 7.9 + DB 19c + WebLogic + Forms/Reports 10.1.2.3**.
- 12.2.12 has **Java Web Start (JWS) preconfigured**, so Forms access is easier
  than 12.1.3 (which needs JWS patching) — still needs a client JRE 8.

Budget impact: one 12.2 instance reduces the number of 12.1 clones you can run
concurrently. Add it only after the 12.1 lab is stable.

---

## 13. Troubleshooting quick reference

| Symptom | Likely cause / fix |
|---------|--------------------|
| Boot hangs / no disk | Wrong controller; use LSI SCSI or SATA, i440fx + SeaBIOS |
| Kernel panic on boot (`dtrace_psinfo_alloc`) | `--cpu host` panics the OL6 UEK kernel → use `qm set <id> --cpu Westmere` |
| SSH "no matching host key type found" | OL6 sshd only offers `ssh-rsa` → `ssh -oHostKeyAlgorithms=+ssh-rsa root@<ip>` |
| NIC is `eth1` | Delete `/etc/udev/rules.d/70-persistent-net.rules`, fix `ifcfg-eth0`, reboot |
| Login page blank / applet error | Client browser/JRE mismatch — see §10 and `PLAN.md` §1.4 (applet needs 32-bit FF ESR52 + 32-bit Oracle JRE 8) |
| DB not up | Check listener (`lsnrctl status`), `$ORACLE_HOME`, alert log |
| Services won't start after clone | Verify hostname/IP/`/etc/hosts`, run Autoconfig |
| Out of space on host | Remove staging OVA/zips; use linked clones; check `lvs`/`df` |

---

## 14. Repository files

| File | Purpose |
|------|---------|
| `PROGRESS.md` | **Live execution status — where the build left off** |
| `README.md` | This plan and runbook |
| `AGENTS.md` | Core context for AI agents starting a new session |
| `PLAN.md` | OS choices (all roles), resource BOM, and per-phase verification |
| `RESEARCH.md` | Platform research + decision record (12.1.3 vs 12.2.12, sources) |
| `MVP-RUNBOOK.md` | Literal step-by-step for the first working instance (MVP-A/B) |
| `PHASE1-CHECKLIST.md` | Tickable Phase 1 execution checklist (host verify + appliance download) |

---

## 15. References

- Oracle Software Delivery Cloud — <https://edelivery.oracle.com>
- Oracle VM Templates for E-Business Suite —
  <https://www.oracle.com/virtualization/technologies/vm/e-business-suite.html>
- MOS Doc **1906691.1** — Deployment Guide, EBS 12.1.3 Virtual Appliances
  (12.2.12 guide: **2933812.1**)
- Oracle EBS 12.1.3 Documentation Library
- Oracle MyLearn — <https://mylearn.oracle.com>
"# OracleEBSLocalHosting" 
