# Implementation Progress

Live status of the EBS lab build. **Update this file as you go** — it is the
"where did I leave off" record. Plan details live in `README.md`, `PLAN.md`,
`MVP-RUNBOOK.md`; this file only tracks *execution*.

- **Last updated:** 2026-10-02
- **Overall status:** Stage 0–4 done · **Stage 5 in progress (VM boots; network
  DHCP `192.168.100.223`; SSH working)**
- **Next action:** set static IP, start EBS via the `app` menu, verify the login
  page, change default passwords → then Stage 6 snapshot.
- **Key fixes so far:** EBS VMs need **`--cpu Westmere`** (not `host`); SSH to the
  appliance needs **`-oHostKeyAlgorithms=+ssh-rsa`**.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked

---

## Verified environment (real host — replaces the assumptions in older docs)

| Item | Value |
|------|-------|
| Host | HP ProLiant DL360 (Skylake-SP era, not Gen6/7) |
| CPU | 2× Intel Xeon Gold 6138 = **40 cores / 80 threads** |
| RAM | **188 GiB** (~178 GiB free) |
| Proxmox VE | **9.2.20** (kernel `7.0.14-19-pve`) |
| EBS VM CPU model | **`Westmere`** (using `host` panics the OL6 UEK kernel — see Known issues) |
| x86-64-v2 flags | all present (`cx16 popcnt sse4_2 lahf_lm`) — plus AVX-512 |
| Storage for clones | **`local-lvm`** — LVM-thin pool `data`, **1.67 TiB**, ~0.4% used |
| `local` (dir) | ~85 GiB free |
| Host root fs | ~82 GiB free → **too small for staging** (hence the LV below) |
| Network (MVP) | **`vmbr0`** = 192.168.100.222/24, gw 192.168.100.1 (no `vmbr1` yet) |
| Host staging LV | `/dev/pve/ebs-staging` = 300 GiB thin, mounted at `/srv/ebs-media`, NFS-exported to 192.168.100.0/24 |
| Staging VM | VMID **900** `ebs-staging`, **Debian 13.7.0**, 2 vCPU / 3 GB / 32 GB OS disk |
| Secrets | `/root/.ebs-lab.env` (mode 600) inside `ebs-staging` |
| Existing VM (do not touch) | VMID **100** `ubuntu-server-vm` (running) |
| Appliance access | **SSH works**, but OL6 only offers legacy `ssh-rsa` → from the Proxmox host use `ssh -oHostKeyAlgorithms=+ssh-rsa root@192.168.100.223` |

Reserved VMIDs: staging **900**, golden **9000**, class **9010**, EBS clones
**9101–9112**, client template **9200**, client clones **9201–9212**.

---

## Stage 0 — Host verification — `[x]` DONE
- [x] `pveversion` → 9.2.20
- [x] CPU flags (x86-64-v2) present
- [x] `pvesm status` → `local` (dir) + `local-lvm` (lvmthin)
- [x] RAM / free space recorded
- [x] Network bridges → only `vmbr0`

## Stage 1 — Staging VM + 300 GiB thin LV + NFS — `[x]` DONE

### 1a. Create + install `ebs-staging` — `[x]`
- [x] `qm create 900` (2 vCPU / 3 GB / 32 GB, `vmbr0`)
- [x] Attached `debian-13.7.0-amd64-netinst.iso` and installed (no desktop, SSH server)
- [x] Installed GRUB to `/dev/sda`
- [x] `qm set 900 --boot order='scsi0'` and `--delete ide2`

### 1b. Host staging LV + NFS — `[x]`
- [x] `lvcreate -V 300G -T pve/data -n ebs-staging` → `/dev/pve/ebs-staging`
- [x] `mkfs.ext4 /dev/pve/ebs-staging`
- [x] Mounted at `/srv/ebs-media` + added to `/etc/fstab`
- [x] Installed `nfs-kernel-server`, exported `/srv/ebs-media` to 192.168.100.0/24
- [x] `exportfs -ra` + service enabled

### 1c. Mount inside `ebs-staging` + secrets — `[x]`
- [x] Installed `wget unzip tar nfs-common`
- [x] Mounted `192.168.100.222:/srv/ebs-media` at `/srv/ebs-media` + fstab
- [x] Created `/root/.ebs-lab.env` (mode 600)

## Stage 2 — Download the appliance — `[x]` DONE
> Completed **inside `ebs-staging`**, in `/srv/ebs-media` (300 GiB LV via NFS).

- [x] Signed in to edelivery; found **Oracle VM Virtual Appliance for Oracle
      E-Business Suite 12.1.3.0.0**
- [x] Confirmed it is the **2014 Virtual Appliances** pack (part numbers
      **V465xx**) — Single Node Vision, 7 parts × 2 halves = **14 zips, ~51.5 GB**
- [x] Selected the correct set: **Single Node Vision Install (1 of 7 … 7 of 7)**
- [x] Oracle generated a **wget download script** (bearer token + per-file URLs)
- [x] **Download complete** in `/srv/ebs-media` (14 zips)
- [x] All 14 zips present and full-size
- [x] Unzipped successfully (see Stage 3)
- [!] Readme / seeded passwords **not found** in the media → use the researched
      try-first values in "Seeded credentials" below; confirm at first boot

Result:
```
14 zips downloaded (~51.5 GB): V46557-01 … V46563-01 (each _1of2 / _2of2).
Each zip held one fixed-size OVA segment:
  Oracle-E-Business-Suite-12.1.3-VISION-INSTALL.ova.00 … .13  (4000 MiB each)
No separate readme in the zips; no published checksums.
```

### Files in this set (Single Node Vision — the only ones we need)
| Part | Zip files | Size each |
|------|-----------|-----------|
| 1 of 7 | `V46557-01_1of2.zip`, `V46557-01_2of2.zip` | 3.8 + 3.8 GB |
| 2 of 7 | `V46558-01_1of2.zip`, `V46558-01_2of2.zip` | 3.6 + 3.6 GB |
| 3 of 7 | `V46559-01_1of2.zip`, `V46559-01_2of2.zip` | 3.7 + 3.8 GB |
| 4 of 7 | `V46560-01_1of2.zip`, `V46560-01_2of2.zip` | 3.7 + 3.8 GB |
| 5 of 7 | `V46561-01_1of2.zip`, `V46561-01_2of2.zip` | 3.7 + 3.6 GB |
| 6 of 7 | `V46562-01_1of2.zip`, `V46562-01_2of2.zip` | 3.6 + 3.9 GB |
| 7 of 7 | `V46563-01_1of2.zip`, `V46563-01_2of2.zip` | 3.9 + 3.0 GB |

**Total ≈ 51.5 GB.**

**Explicitly NOT downloaded** (other media packs in the same release):
`V46057-01` (Sparse Tier/OS), `V46047–V46051` (Vision Demo DB Tier),
`V46055/V46056` (Production DB Tier), `V46053/V46054` (Application Tier).

### Notes / gotchas
- The Oracle script embeds a **bearer token with ~1 h expiry**. Keep the script
  `chmod 600`, **never commit it**; if it expires mid-download, regenerate a fresh
  script from edelivery and re-run.
- The generated script used `wget -O` **without `-c`** and ran all 14 files in
  **parallel**; if one fails, a restart may begin that file from zero.
- Monitor progress: `tmux attach -t dl` (detach: Ctrl-B, D). Log: `wgetlog-*.log`
  in `/srv/ebs-media`.

## Stage 3 — Extract the OVA — `[x]` DONE (inside `ebs-staging`)
> Each zip held a fixed **4000 MiB** OVA segment; 14 zips → `.ova.00 … .ova.13`.

- [x] Unzipped all 14 zips → `Oracle-E-Business-Suite-12.1.3-VISION-INSTALL.ova.00 … .13`
- [x] Concatenated the segments into one OVA
- [x] `tar xf` → `.ovf` + `.vmdk` (no README inside)
- [x] Recorded filenames:
  - `Oracle-E-Business-Suite-12.1.3-VISION-INSTALL.ovf` — 14 K
  - `Oracle-E-Business-Suite-12.1.3-VISION-INSTALL-disk1.vmdk` — **54 G**

## Stage 4 — Import into Proxmox (golden VM) — `[x]` DONE (on the host)
> IMPORTANT: `qm importovf` **creates the VM itself** and fails if VMID 9000
> exists. So for our forced hardware settings, use **create + `qm importdisk`**
> (do NOT combine create + importovf).
> NOTE: the VMDK's **virtual size is 300 GiB** (the `54 G` on disk was sparse),
> so `qm importdisk` transfers/allocates 300 GiB — slow on HDD.
> **CPU must be `Westmere` (or `kvm64`), NOT `host`** — `host` panics the UEK
> kernel (see "Known issues" below).

- [x] `qm create 9000` (pc/seabios/lsi/e1000/balloon 0, **cpu Westmere**)
- [x] `qm importdisk` the 300 GiB VMDK to `local-lvm`
- [x] `qm set 9000 --scsi0 local-lvm:vm-9000-disk-0` + `--boot order=scsi0`
- [x] `qm config 9000` correct; **VM boots** (after CPU fix)

```bash
# 1) create the golden VM shell with our exact hardware
qm create 9000 --name ebs1213-golden \
  --memory 12288 --cores 4 --sockets 1 \
  --cpu Westmere --machine pc --bios seabios \
  --scsihw lsi --ostype l26 --balloon 0 \
  --net0 e1000,bridge=vmbr0 --onboot 0

# 2) import the VMDK  (watch for the volume name, usually vm-9000-disk-0)
qm importdisk 9000 \
  "/srv/ebs-media/Oracle-E-Business-Suite-12.1.3-VISION-INSTALL-disk1.vmdk" local-lvm

# 3) attach as scsi0 + boot order + console
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga std

# 4) review then boot
qm config 9000
qm start 9000
```
Alternate single-command route (lets the OVF set hardware; skip step 1+2):
```bash
qm importovf 9000 /srv/ebs-media/Oracle-E-Business-Suite-12.1.3-VISION-INSTALL.ovf local-lvm
qm set 9000 --machine pc --bios seabios --scsihw lsi --balloon 0 --cpu Westmere --net0 e1000,bridge=vmbr0
```

## Known issues & fixes
- **UEK DTrace kernel panic on boot with `--cpu host`** — the OL 6.5 UEK kernel
  panics in `dtrace_psinfo_alloc` (during `execve` of init) when KVM exposes the
  host's newer CPU features. **FIX: `qm set 9000 --cpu Westmere`** (fallback
  `kvm64`). Confirmed working 2026-10-02. All EBS VMs/clones must use this.
- If Westmere ever fails, boot the **RHCK** (`2.6.32-...el6`, no DTrace) from the
  GRUB menu and make it default (`default=1` in `/boot/grub/grub.conf`), then
  remove `dtrace-modules` (`rpm -qa | grep dtrace` → `yum remove`).
- **SSH "no matching host key type found … offer: ssh-rsa,ssh-dss"** — modern
  OpenSSH disabled `ssh-rsa`; OL6 only offers the legacy types. Fix on the client:
  `ssh -oHostKeyAlgorithms=+ssh-rsa root@192.168.100.223` (add
  `-oKexAlgorithms=+diffie-hellman-group14-sha1,…` / `-oCiphers=+aes128-cbc…` if
  further negotiation errors appear). Confirmed working 2026-10-02.

## Seeded credentials (try-first — UNVERIFIED until first boot)
> No readme was found in the media; MOS 1906691.1 is login-gated. These come from
> Oracle's 12.1.3 VM-template hands-on lab, Pythian, and simpleoracle. Confirm on
> the console and **change everything**.

| Login | Try |
|-------|-----|
| OS `root` | `ovsroot` |
| OS `oracle` | `oracle` |
| OS `applmgr` | `applmgr` |
| DB `SYS` | `change_on_install` |
| DB `SYSTEM` | `manager` |
| EBS schema `APPS` (and CM password) | `apps` |
| EBS web `SYSADMIN` | `sysadmin` |
| EBS web `OPERATIONS` / demo users | `welcome` |
| DB SID | `VIS` |
| Hostname | none baked in — set at first boot |

## Stage 5 — First boot, network, verify EBS — `[~]` IN PROGRESS
- [x] VM boots (after `--cpu Westmere`); console shows the appliance menu
      (`app` = manage start/stop, `reboot`, `none` = login to VM)
- [x] Logged in as `root` (via `none`); discovered:
  - hostname `ebs.example.com`
  - `eth0` (e1000), **DHCP** → `192.168.100.223`; `ifcfg-eth0`: `BOOTPROTO=dhcp`
  - `sshd` running / enabled
  - SSH works from the Proxmox host with `-oHostKeyAlgorithms=+ssh-rsa`
- [ ] Set a **static IP `192.168.100.223`** (keep hostname `ebs.example.com` to
      avoid an Autoconfig reconfigure); ensure `/etc/hosts` maps the name
- [ ] Confirm appliance paths: `ls /u01/install/ /u01/install/scripts/`
- [ ] Start EBS via the `app` menu (or scripts)
- [ ] Verify: `lsnrctl status`, `adapcctl.sh status`, `adcmctl.sh status`,
      `netstat -tlnp | grep -E '8000|1521'`
- [ ] Login page loads: `http://192.168.100.223:8000/OA_HTML/AppsLogin` (try `SYSADMIN`/`sysadmin`)
- [ ] **Change all default passwords**

## Stage 6 — Snapshot (MVP-A done) — `[ ]` TODO
```bash
qm shutdown 9000
qm snapshot 9000 golden-clean --description "Pristine R12.1.3 Vision, pw changed"
qm listsnapshot 9000
```
- [ ] Snapshot `golden-clean` exists

---

## Post-MVP (not started)
- [ ] Import/verify Forms from a client (MVP-B)
- [ ] Build client template 9200 (OL7.9 + 32-bit FF ESR52 + 32-bit Oracle JRE 8)
- [ ] Create class instance 9010 + EBS clones 9101–9112 + client clones 9201–9212
- [ ] Create isolated `vmbr1` lab VLAN + static IPs
- [ ] Optional later: 12.2.12 instance

---

## Change log
- **2026-10-01** — Stage 0 verified; Stage 1 (a–c) complete.
  Host confirmed as PVE 9.2.20 / Xeon Gold 6138 / 188 GiB; staging via 300 GiB
  thin LV on `local-lvm`; Debian 13.7.0 used for the staging VM.
- **2026-10-01 (later)** — Stage 2: confirmed the **2014 Virtual Appliances**
  Single Node Vision pack on edelivery (V46557–V46563 = 14 zips, ~51.5 GB);
  obtained Oracle's wget script; download started in `/srv/ebs-media` under
  `tmux`. Excluded the other media packs (Sparse/Prod/Vision-DB/App tiers).
- **2026-10-01 (cont.)** — **Stage 2 DONE** (all 14 zips downloaded). **Stage 3
  started**: unzipped all 14 zips → `Oracle-E-Business-Suite-12.1.3-VISION-INSTALL.ova.00 … .13`.
  No readme found in the media → added an unverified "Seeded credentials
  (try-first)" table (root/ovsroot, oracle/oracle, applmgr/applmgr, APPS/apps,
  SYSADMIN/sysadmin). Next: concatenate the `.ova.??` segments and `tar xf`.
- **2026-10-02** — **Stage 3 DONE**: concatenated to `EBS1213_VISION.ova` and
  extracted:
  - `Oracle-E-Business-Suite-12.1.3-VISION-INSTALL.ovf` (14 K)
  - `Oracle-E-Business-Suite-12.1.3-VISION-INSTALL-disk1.vmdk` (**54 G**)
  No README inside the OVA. Fixed Stage 4 docs: use **create + `qm importdisk`**
  (`qm importovf` creates the VM itself and conflicts with an existing VMID).
- **2026-10-02 (cont.)** — Stage 4 started: `qm create 9000` done; `qm importdisk`
  running. Discovered the **VMDK virtual size is 300 GiB** (the 54 G was sparse),
  so the import transfers/allocates ~300 GiB. Updated disk-size assumptions in
  `PLAN.md` §2.1 / `README.md` §2 / `AGENTS.md` (150–200 GB → 300 GiB).
- **2026-10-02 (cont.)** — **Stage 4 DONE.** Import finished; `scsi0` attached;
  first boot **panicked** in UEK `dtrace_psinfo_alloc` under `--cpu host`.
  **Fixed with `qm set 9000 --cpu Westmere`** → VM boots. Recorded as a known
  issue; updated all VM-create commands to use Westmere.
- **2026-10-02 (cont.)** — **Stage 5 started.** Console menu (`none` logs in);
  hostname `ebs.example.com`; `eth0` DHCP `192.168.100.223`; `sshd` running.
  SSH works from the Proxmox host with `-oHostKeyAlgorithms=+ssh-rsa` (OL6 only
  offers legacy host keys). Next: static IP + start EBS via the `app` menu.
