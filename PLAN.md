# Lab Plan — OS Choices, Resources, and Verification

Planning + decision layer for the EBS 12.1.3 training lab. **Nothing has been
executed yet; all major decisions are locked (2026-09-29).** It answers:

1. **Which OS for each role in the lab** (Proxmox host, EBS guest, staging VM,
   student client VM).
2. **How to verify each process step-by-step** so a failed step is caught before
   it costs hours of slow-download or clone time.

`README.md` is the runbook (what to do). `PHASE1-CHECKLIST.md` is the tickable
download checklist. `PROGRESS.md` is the live execution status. This file is the
decision + verification layer above them.

Honesty note: EBS is not free software; this lab is **offline/LAN-only,
non-commercial, self-study, no redistribution, no production use**. Oracle does
**not** certify any Linux desktop as an EBS 12.1.3 client — any Linux client path
below is a documented community workaround, not an Oracle-supported config.

---

## 0. Simplest-first path (MVP) — do this first

Prioritise **getting one working instance** over the full multi-student lab.
Optimise only after the MVP is proven. This is a deliberate sequencing choice,
not a change to the target architecture.

**MVP goal:** one EBS 12.1.3 instance, reachable from one browser, with the login
page and one Forms screen working, and a clean snapshot for rollback.

MVP steps (a subset of the phases, in order):
1. Host verification — `README.md` §3 (cannot be skipped).
2. Create the **`ebs-staging` VM** (Debian 12/13) and download the appliance there —
   `PHASE1-CHECKLIST.md`.
3. Stage + extract inside `ebs-staging`, exposing the media to the host.
4. Import and create **one** VM (VMID 9000) — `README.md` §6.
5. First boot: static IP + hostname, reconfigure per MOS 1906691.1, start
   services, verify login page + one Forms screen, change default passwords —
   `README.md` §7.
6. Snapshot `golden-clean` — `README.md` §8. **MVP done.**

Simple defaults to adopt now:
- **All staging work happens in the `ebs-staging` VM** (Debian 12/13, 2 vCPU, 2–4 GB,
  ~32 GB OS disk + ~300 GB host-shared staging) — see §1.3. Media is exposed to the
  host for import.
- Credentials saved in `~/.ebs-lab.env` (mode `600`) inside `ebs-staging`.
- A **single full clone** for actual use; accept the disk cost initially.
- Client: **MVP-B is deferred**; validate the HTML login page from any existing PC
  first. When built, use the locked **OL7.9 client VM** (see §1.4), not a random PC.
- Networking: one static IP + `/etc/hosts`. No DNS server.

### Deferred until after the MVP (optimise later)
- Shared class instance + 12 linked EBS clones (`--full 0`) and clone tuning.
- Per-student client VMs (build the client template 9200 → clones 9201–9212, §1.4).
- Optional **JWS migration** on 12.1.3 (server-side patches) — not needed for the
  chosen legacy-applet client.
- LXC/Docker helper services (file server, DNS) and Ansible automation.
- Capacity tuning (RAM/disk) and multi-instance concurrency testing.
- The optional R12.2.12 instance.

---

## 1. OS decision matrix (all roles)

There are four distinct OS roles. Only one of them is actually a free choice;
the other three are effectively fixed by what Oracle ships.

| Role | Recommended | Alternative | Why / caveat |
|------|-------------|-------------|--------------|
| Proxmox host | **Proxmox VE 9.x** (Debian 13 base) — installed as 9.2.20 | PVE 8.x / 7.x fallback | PVE 8/9 need CPU x86-64-v2; the host's Gold 6138 passes. |
| EBS guest | **Oracle Linux 6.5 x86-64** (what the appliance ships) | none (do NOT change) | Fixed by Oracle's pre-built appliance. Do not upgrade/replace — it breaks Autoconfig/EBS. |
| Staging / helper VM | **Debian 12/13 minimal** | Oracle Linux 8/9 minimal; or run on the host | Only needs `wget`, `unzip`, `tar`, and lots of disk. Small + free + still-supported. |
| Student client VM | **Oracle Linux 7.9 + 32-bit Firefox ESR 52 + 32-bit Oracle JRE 8** (one VM per student, legacy applet) | Windows/macOS + JRE 8 + JWS (certified); OpenJDK 8 + IcedTea-Web (free, less proven) | **Decided 2026-09-29.** Uncapped $0; uncertified Linux config. Access via noVNC (default) or SPICE. See §1.4. |

### 1.1 Proxmox host OS
- **Keep Proxmox VE as installed.** Do not re-install a plain Debian/other
  hypervisor — the whole `qm` workflow in `README.md` depends on Proxmox.
- **Version gate:** PVE 8/9 need CPU flags `cx16 popcnt sse4_2 lahf_lm`. The
  verified host passes; otherwise use PVE 7.x (Debian 11, x86-64-v1).
- **Verify (read-only):**
  ```bash
  pveversion
  lscpu | grep -o -E 'cx16|popcnt|sse4_2|lahf_lm' | sort -u      # expect all 4
  pvesm status
  ```

### 1.2 EBS appliance guest OS (no choice)
- Ships **Oracle Linux 6.5 (64-bit)** with EBS 12.1.3 (Applications **RPC1**,
  CPU **Apr 2014**), DB **11.2.0.4**, Forms/Reports **10.1.2.3**, Java ORACLE_HOME
  10.1.3.5, JDK **1.7.0_60** (per Oracle's 2014 appliance announcement, MOS
  1906691.1). EBS 12.1.3 entered **Sustaining Support on 2022-01-01**.
- **Oracle Linux 6 is EOL** (extended support ended 2024-12-31); OL 6.5 in
  particular is far past EOL. Acceptable only because this lab is **offline and
  non-commercial**. Never expose it.
- **Do not** upgrade the guest OS or its kernel — EBS 12.1.3 Autoconfig, the
  listener and Forms are tightly coupled to this stack.
- **No separate OS install and no CentOS needed.** The EBS OS is baked into the
  appliance; you never install Linux for EBS. (CentOS appears in most EBS guides
  only because those describe a from-scratch Rapid Install, which we deliberately
  avoid. CentOS Linux 7/8 are also EOL.)

### 1.3 Staging VM (`ebs-staging`) — DECIDED (2026-09-29) · BUILT 2026-10-01

All staging runs in a dedicated Proxmox VM, **not** on the host. It is throwaway.
**As built:** the ~300 GB is a **thin LV `/dev/pve/ebs-staging`** (pool `pve/data`)
mounted on the host at `/srv/ebs-media` and NFS-exported to the VM — the host
root/local dirs were too small. See `PROGRESS.md` for exact state.

- **OS: Debian 12/13 minimal** (no GUI). Only needs `wget`, `unzip`, `tar`, and
  `openssl` (checksums) — plus `nfs-common` if using a host NFS share.
  (CentOS/Rocky/Oracle Linux would work too, but CentOS Linux is EOL and Debian
  is smaller and simpler; the choice is irrelevant to EBS.)
- **Resources: vCPU 2, RAM 2–4 GB, OS disk ~32 GB.** Download is network-bound;
  unzip/tar is CPU+disk. More RAM buys nothing here.
- **Staging space ~300 GB thin.** Assembled 12.1.3 VMDK is ~57 GB; worst case with
  zips + parts + concatenated OVA + extracted VMDK all present ≈ 150–200 GB, so
  300 GB gives headroom. Delete intermediates as you go.
- **Where the staging space lives (important):** `qm importovf`/`qm importdisk`
  read a file path **on the host**. Best: put the ~300 GB on a **folder the host
  exports** (NFS/9p, e.g. `/srv/ebs-media`); mount it in the VM and stage there —
  no second copy, and the host imports directly. If you instead put ~300 GB on the
  VM's own disk, you must `scp`/`rsync` the final `.ovf`+`.vmdk` back to the host.
- **Delete** the VM and its media after the golden disk is imported.

> Rejected: staging directly on the host (works, but the user chose VM isolation).

### 1.4 Student client VM — DECIDED (2026-09-29): one OL7.9 VM per student

R12.1.3 Forms runs as a **Java applet**. The chosen route is the **legacy NPAPI
applet** served by a dedicated per-student client VM, so the **stock appliance
needs no server patching** (unlike JWS).

**Locked build (every artifact verified obtainable, $0):**
- OS: **Oracle Linux 7.9 (64-bit)** — ISO still freely downloadable from
  yum.oracle.com. OL7 is EOL (Extended Support to Jun 2028, paid — irrelevant
  offline). i686 multilib packages ARE present in OL7's x86_64 repo.
- Browser: **32-bit Firefox ESR 52.9.0esr** (Mozilla archive `linux-i686`) — the
  last NPAPI-capable Firefox.
- Runtime: **32-bit Oracle JRE 8** (`linux-i586`) — the only runtime shipping
  `libnpjp2.so`. Needs a free Oracle account + licence click; fine for
  non-commercial/self-study.
- Wiring: `ln -s <jre>/lib/i386/libnpjp2.so ~/.mozilla/plugins/`, verify in
  `about:plugins`.
- Access: **noVNC in-browser by default** (zero student install; Proxmox user
  with `VM.Console`), **SPICE optional** (`vga: qxl` + `virt-viewer`). **RDP is
  rejected** — xrdp is unavailable on OL7 (EPEL 7 EOL).
- Desktop: **minimal install + a light DE (Xfce/LXQt)**, not full GNOME, so each
  client VM stays low on RAM/CPU. (Recommendation — confirm at build.)

**Verified caveats (see `RESEARCH.md` §7):**
- **Community/uncertified Linux config** — Oracle certifies the FF-ESR52 + JRE8
  plugin path on **Windows only** (MOS 389422.1 / 393931.1).
- Expect JRE security friction: add the EBS URL to the **Exception Site List**,
  allow unsigned/SHA-1 JARs (`deployment.security.level`), possibly set
  `plugin.load_flash_only=false`, and disable Firefox auto-update.
- No security updates on any component — offline lab only.

**Alternatives considered:** JWS on 12.1.3 (needs server patches — deferred, not
chosen); Windows client (licensed); OpenJDK 8 + IcedTea-Web (uncertified;
OpenWebStart can't run applet-style JNLP).

> Per-student client VMs (template **9200** → clones **9201–9212**) sized
> **2 vCPU / 2 GB / 20–40 GB**. Mind the **~188 GiB RAM budget** (see §2.1).

> Decision locked 2026-09-29: **one Oracle Linux 7.9 client VM per student**
> with the legacy applet stack. The client VM is an optimisation, not part of
> MVP-A — validate the login page from an existing PC first.

---

## 2. Resource inventory (bill of materials)

### 2.1 Compute / storage budget (host: 188 GiB RAM, ~1.67 TiB)

| Item | vCPU | RAM | Disk | Notes |
|------|------|-----|------|-------|
| Proxmox host | — | ~2–4 GB | — | Reserve headroom for host |
| Staging/helper VM (temporary) | 2 | 2–4 GB | ~32 GB (staging on host share) | Delete after import |
| EBS appliance (golden) | 4 | 12 GB | **300 GiB thin** (VMDK virtual size) | Shut down after snapshot |
| Shared class instance | 4 | 12 GB | clone | `--full 1` |
| 12 × student EBS clones | 4 each | 10 GB each | linked deltas | `--full 0` |
| Client template | 2 | 2 GB | 20–40 GB | OL7.9 + FF ESR52 + JRE 8 |
| 12 × client clones | 2 each | 2 GB each | linked deltas | `--full 0` |

RAM check: 12×10 (EBS) + 12 (class) + 12×2 (clients) ≈ **156 GB of ~188 GiB**
(~24 GB host headroom). **Tight:** running all 12 EBS sandboxes + 12 clients +
class at once nearly fills RAM — cap concurrent sandboxes (e.g. ~8) or accept
swap risk. Clients at 4 GB each would not fit; keep them at **2 GB**.
Storage check: EBS base ~300 GiB + class full clone ~300 GiB + deltas + client
base/clones ≈ **800–900 GiB of 1.67 TiB**. Fine. Both work **only if clones are
linked** — do not full-clone.

### 2.2 Software / media to obtain

| Item | Source | Approx size | Account needed |
|------|--------|-------------|----------------|
| EBS 12.1.3 Vision Virtual Appliance (multi-part) | edelivery.oracle.com | tens of GB (**confirm in readme**) | Oracle SSO (free) |
| **Oracle Linux 7.9** x86_64 DVD ISO (client template) | yum.oracle.com | ~4 GB | none (free) |
| Debian 12/13 netinst (staging VM) | debian.org | ~0.6 GB | none |
| Firefox 52.9.0esr **32-bit** tarball — `linux-i686` | archive.mozilla.org | ~60 MB | none |
| 32-bit Oracle JRE 8 (`linux-i586`, has `libnpjp2.so`) | Java SE 8 archive (oracle.com) | ~70–80 MB | Oracle SSO + licence click |
| OpenJDK 8 + IcedTea-Web / OpenWebStart — JWS only, uncertified | distro repo / GitHub | small | none |

### 2.3 Reused / no-cost assets
- Proxmox VE (already installed), the DL360 itself, local DNS/`/etc/hosts`.
- Client connection: Proxmox **noVNC in-browser** (default, no install) or
  **SPICE** (`virt-viewer`) — both free. RDP rejected on OL7.

---

## 3. Phase-by-phase plan with step-by-step verification

Format: **Steps → Verify (command → expected result) → If it fails.**
Exact ports/passwords/paths are marked *verify-on-VM* because they vary by
appliance revision.

### Phase 0 — Host verification (before any download)
Steps: run the read-only checks in `README.md` §3.
- **Verify:** `pveversion` → `pve-manager/8.x`.
- **Verify:** `lscpu | grep -o -E 'cx16|popcnt|sse4_2|lahf_m' | sort -u` → all 4
  flags present (else use PVE 7).
- **Verify:** `pvesm status` → a storage type supporting snapshots/linked clones
  (**LVM-thin, ZFS, or dir/qcow2** all qualify).
- **Verify:** `vgs` and `df -h` → free space ≥ ~300 GB for staging.
- **If it fails:** resolve CPU/storage before downloading. A failed flag or
  non-snapshot storage invalidates the clone strategy.

### Phase 1 — Acquire the appliance (`PHASE1-CHECKLIST.md`)
Steps: Oracle SSO → edelivery → 12.1.3 Vision pack → accept terms → read readme →
resumable download with `wget -c`.
- **Verify:** filenames/part count match the media-pack readme exactly.
- **Verify:** `sha256sum <file>` matches every published checksum.
- **Verify:** `ls -lh` file sizes are complete (not truncated parts).
- **If it fails:** re-run `wget -c <url>` (resumes); re-download only the bad part.

### Phase 2 — Stage and extract the OVA (`README.md` §5)
Steps: unzip parts → concatenate → `tar xf` the OVA → get `.ovf` + `.vmdk`.
- **Verify:** `unzip -t <zips>` → "No errors detected".
- **Verify:** concatenated size = sum of parts (`ls -l` arithmetic).
- **Verify:** `tar tf <ova>` lists exactly one `.ovf` + one `.vmdk` (+ manifest).
- **If it fails:** wrong concatenation order or a corrupt part → re-download that
  part; confirm the exact part naming (`.part*` vs `.0xx`) from the readme.

### Phase 3 — Import into Proxmox and create the VM (`README.md` §6)
Steps: `qm create 9000` (i440fx/SeaBIOS/LSI, **`--cpu Westmere`** — `host` panics
the OL6 UEK kernel, `--balloon 0`, `e1000` NIC) → **`qm importdisk`** the VMDK →
`qm set --scsi0` → boot order. (`qm importovf` is an alternative that creates the
VM itself — don't also run `qm create`.)
- **Verify:** `qm config 9000` → machine `pc`, bios `seabios`, scsihw `lsi`,
  `e1000`/`virtio` NIC on the chosen bridge, `balloon: 0`.
- **Verify:** `lvs` / `qm config 9000` → `scsi0` points at the imported disk.
- **Verify:** disk is thin and roughly 150–200 GB after resize.
- **If it fails:** "no bootable disk" → wrong controller (must be LSI SCSI or
  SATA, not virtio-scsi) or wrong boot order; `--format qcow2` errors on
  LVM-thin → drop it or use `dir`/ZFS storage.

### Phase 4 — First boot, network reconfigure, verification (`README.md` §7)
Steps: boot → log in (readme creds) → static IP + hostname + `/etc/hosts` →
reconfigure per MOS 1906691.1 (listener, `tnsnames`, context, Autoconfig) → start
EBS services → change all default passwords.
- **Verify:** `hostname -f` resolves; `ping <self>` and `ping <hostname>` succeed.
- **Verify:** if NIC is `eth1`, delete `70-persistent-net.rules`, fix
  `ifcfg-eth0`, reboot (expected on clones).
- **Verify:** `lsnrctl status` → listener `READY`.
- **Verify:** `$ADMIN_SCRIPTS_HOME/adapcctl.sh status` and `adcmctl.sh status`.
- **Verify:** `netstat -tlnp | grep -E '8000|1521'` → listening (*verify-on-VM*).
  (`7001` does **not** apply to 12.1.3 — that is a 12.2/WebLogic port.)
- **Verify:** `curl -I http://<ip>:8000/OA_HTML/AppsLogin` → HTTP 200/302.
- **Verify:** log in to EBS as a seeded user; open a Forms screen (this is the
  real "Forms works" test — do it before templating).
- **If it fails:** services won't start after IP change → re-run Autoconfig; check
  hostname/`/etc/hosts` consistency.

### Phase 5 — Golden template and snapshot (`README.md` §8)
Steps: clean shutdown → `qm snapshot 9000 golden-clean` → (optional) `qm template`.
- **Verify:** `qm shutdown 9000` exits cleanly (no forced stop).
- **Verify:** `qm listsnapshot 9000` → `golden-clean` present.
- **Verify:** `qm config 9000` unchanged after snapshot.
- **If it fails:** snapshot fails → storage lacks snapshot support (go back to §1.1).

### Phase 6 — Class instance, student EBS clones, and client clones (`README.md` §9)
Steps: full clone → class; 12 linked clones → student EBS sandboxes; build **one
client template** then 12 linked client clones (9201–9212).
- **Verify:** `qm list` → 9010 + 9101–9112 + 9200 template + 9201–9212, with
  expected memory (EBS 10–12 GB; clients 2 GB).
- **Verify:** linked clones are small deltas (check `lvs`/disk after clone).
- **Verify per clone:** boot one EBS clone and one client clone; confirm unique IPs
  and that the EBS login page responds from the client.
- **If it fails:** disk explosion → clones were `--full 1`; re-clone with `--full 0`.

### Phase 7 — Client access (Forms applet) (`README.md` §10)
Decided: **one Oracle Linux 7.9 client VM per student**, built from the client
template, running the legacy applet stack (**32-bit Firefox ESR52 + 32-bit Oracle
JRE 8 plugin**). Access via **noVNC in-browser** (default) or **SPICE**. For
**MVP-A this phase is skipped entirely** — validate the HTML login page from an
existing PC.
- **Verify:** `java -version` → 1.8.0_x (32-bit) on the client.
- **Verify:** `about:plugins` in **32-bit** Firefox 52 lists the Java plugin.
- **Verify:** open the EBS login page and launch at least one Forms screen.
- **Verify:** a student can reach their own client VM console (noVNC) and no
  other's (Proxmox `VM.Console` scoping).
- **If it fails:** applet error → JRE security config (Exception Site List,
  `deployment.security.level`); see `RESEARCH.md` §7. Do not switch methods
  mid-course.
- **Disable auto-updates** on the client and re-test after any change.

### Phase 8 — Curriculum, batches, reset (`README.md` §11)
Steps: publish tracks; between cohorts roll back or re-clone.
- **Verify:** `qm rollback 9101 golden-clean` completes and the clone boots clean.
- **Verify:** full reset path (`stop`/`destroy`/`clone`) yields a fresh sandbox.
- **If it fails:** locked VM → `qm stop <id> --skiplock 1` before rollback.

---

## 4. Open questions (decide before execution)

> Platform-choice research and rationale live in **`RESEARCH.md`** (12.1.3 vs
> 12.2.12, concurrency, HDD bottleneck, decision record). Read it before changing
> the platform decision.

1. ~~Thin-client method~~ — **DECIDED:** legacy 32-bit applet on a per-student
   Oracle Linux 7.9 client VM (no server patching). See §1.4 / `RESEARCH.md` §7.
2. ~~Staging location~~ — **DECIDED:** dedicated `ebs-staging` VM (Debian 12/13), see
   §1.3. Media exposed to the host for import.
3. ~~Client OS~~ — **DECIDED:** Oracle Linux 7.9; access via noVNC (SPICE
   optional); RDP rejected on OL7.
4. ~~Guest credentials~~ — **DECIDED:** `~/.ebs-lab.env` (mode `600`) in the
   `ebs-staging` VM; never committed. Change all seeded passwords at first boot.
5. **12.2.12 phase:** confirm it stays deferred until 12.1.3 is stable.

---

## 5. References

- Oracle VM Templates for EBS (ships Oracle Linux 6.5 for 12.1.3) —
  <https://www.oracle.com/virtualization/technologies/vm/e-business-suite.html>
- MOS **1906691.1** — EBS 12.1.3 Virtual Appliance Deployment Guide
- MOS **389422.1** — Recommended Browsers for EBS 12.1.3 (Windows/macOS only)
- MOS **393931.1** — Deploying JRE (Native Plug-in) for Windows Clients
- MOS **2188898.1** — Using Java Web Start with Oracle E-Business Suite
- Oracle Java SE Support Roadmap (Deployment Stack removal) —
  <https://www.oracle.com/java/technologies/java-se-support-roadmap.html>
- Firefox 52.9.0esr release notes —
  <https://www.firefox.com/en-US/firefox/52.9.0/releasenotes/>
- Firefox archive (52.9.0esr) — <https://archive.mozilla.org/pub/firefox/releases/52.9.0esr/>
- IcedTea-Web — <https://github.com/AdoptOpenJDK/IcedTea-Web>
- Oracle Linux lifecycle (OL6/OL7 EOL) — <https://endoflife.date/oracle-linux>
- Oracle Linux ISOs (free) — <https://yum.oracle.com/oracle-linux-isos.html>
- Java SE 8 archive — <https://www.oracle.com/java/technologies/javase/javase8-archive-downloads.html>
- Proxmox VE admin guide (SPICE/noVNC, linked clones) —
  <https://pve.proxmox.com/pve-docs/pve-admin-guide.html>

---

## 6. Online verification log (checked 2026-09-29)

Every factual claim in this repo was checked against current public sources.
Confidence: **H**=high, **M**=medium, **L**=unverified. MOS notes are
login-gated and were confirmed only indirectly where noted.

### Confirmed
- **H** 12.1.3 appliance is Oracle Linux 6.5 with Apps RPC1 (CPU Apr 2014), DB
  11.2.0.4, Forms/Reports 10.1.2.3, JDK 1.7.0_60. Oracle's EBS VM page still
  lists the 12.1.3 Single Node Vision appliance and cites MOS 1906691.1.
  <https://www.oracle.com/virtualization/technologies/vm/e-business-suite.html>
- **H** EBS 12.1.3 entered **Sustaining Support 2022-01-01**.
  <https://blogs.oracle.com/ebstech/reminder-ebs-1213-moves-to-sustaining-support-on-jan-1-2022>
- **H** 12.2.12 appliance announced **May 2023** (OL 7.9, DB 19c, JWS
  preconfigured), deployment guide MOS 2933812.1.
  <https://blogs.oracle.com/ebstech/oracle-vm-virtual-appliance-for-ebs-122-now-available>
- **H** JWS is supported for **12.1.3** (MOS 2188898.1, Apr 2017); min JRE
  **8u121 b33**; last JRE certified for 12.1 is **8u311**; enabling it on 12.1.3
  needs server-side patches + `s_forms_launch_method=jws`.
  <https://blogs.oracle.com/ebstech/java-web-start-now-available-for-ebs-121-and-122>
- **H** Oracle certifies **no Linux desktop** client; only Windows/macOS/Android
  (MOS 389422.1). The NPAPI plugin exists **only in Oracle JRE**, and only the
  **32-bit** Firefox **ESR 52** keeps NPAPI.
  <https://blogs.oracle.com/ebstech/confused-about-e-business-server-vs-desktop-operating-system-certifications>
- **H** Proxmox: disk-bus/BIOS must match the source; VirtIO is preferred but
  not for OSes lacking drivers. `--format qcow2` is meaningless on LVM-thin.
  <https://pve.proxmox.com/wiki/Migrate_to_Proxmox_VE>
- **H** 8000 (HTTP) and 1521 (DB) are the 12.1.3 ports; **7001 is 12.2-only**.

### Uncertain / verify on VM
- **L** Whether the 12.1.3 pack is still downloadable on eDelivery **today**
  (catalog is now behind sign-in; last public confirmation was 2022). — **Log in
  and check before the long download.**
- **M** No **CSI/support contract** is required for the appliance download.
- **M** Whether the appliance already includes any JWS configuration (stock
  expectation: no).
- **M** Linux client via OpenJDK 8 + IcedTea-Web can launch EBS Forms JNLP
  (<https://github.com/AdoptOpenJDK/IcedTea-Web/issues/815>); OpenWebStart does
  **not** support applet-style JNLP (<https://github.com/karakun/OpenWebStart>).
- **L** Exact media-pack part count/total size (one 2014 user report: ~14 OVA
  parts, ~57 GB VMDK). Confirm from the readme.

### Corrections applied to earlier drafts
1. `qm importdisk … local-lvm --format qcow2` was wrong → use `qm importovf` or
   drop `--format`.
2. `7001` port reference was wrong for 12.1.3 → removed.
3. Appliance env path `/u01/install/APPS/APPS<CONTEXT>.env` was the 12.2 layout →
   corrected to `/u01/install/VISION` + `$APPL_TOP/APPS<CONTEXT>.env`.
4. "JWS removes the client problem" was overstated → JWS on 12.1.3 needs server
   patches; Linux clients are uncertified; the applet plugin needs 32-bit
   Firefox ESR 52 + 32-bit **Oracle** JRE 8.
5. Added the 2013-Xen-template warning and the `--balloon 0` / `e1000` tweaks.
6. **`--cpu host` panics the OL6 UEK kernel** (`dtrace_psinfo_alloc` during
   `execve`) → use **`--cpu Westmere`** (verified working 2026-10-02). Applies to
   the golden VM and all clones.
7. Golden disk is actually **300 GiB** (VMDK virtual size; 54 G was sparse).
