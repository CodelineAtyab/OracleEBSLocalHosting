# Platform Research & Decision Record — EBS 12.1.3 vs 12.2.12

Why this file exists: so a future session (or a future cohort) can see **what was
researched, what the sources said, and why a decision was made** — without
re-doing the web work. When a decision changes, update §4 and add a dated note.

Verification date: **2026-09-29**. Confidence legend: **H** = Oracle-documented /
directly observed · **M** = reputable community / multiple sources · **L** =
unverified / login-gated. MOS notes are gated; where used they are marked (gated).

Context (host verified 2026-10-01): single Proxmox VE host — DL360, **Proxmox VE
9.2.20**, 2× Intel Xeon Gold 6138 (**40 cores / 80 threads**), **188 GiB RAM**,
**~1.67 TiB LVM-thin** (HDD, no SSD), slow internet, **$0**.
Goal: a free offline EBS lab with the **Vision** dataset so **10+ students**
practise concurrently (functional navigation + some Apps DBA).

---

## 1. The question

Is the older **EBS 12.1.3 Vision** appliance the *easiest and most acceptable*
route for this exact hardware/budget, or is there a better free option?

---

## 2. Findings

### 2.1 Resource footprint (Single Node Vision)

| Item | EBS 12.1.3 | EBS 12.2.12 |
|------|-----------|-------------|
| OS / DB / app stack | OL 6.5; DB **11.2.0.4**; Forms/Reports 10.1.2.3; **OC4J/OracleAS 10.1.3.5 — no WebLogic**; JDK 1.7.0_60 **(H)** | OL 7.9; DB **19c (19.18 RU)**; **WebLogic 10.3.6**; Web Tier 11.1.1.9; JDK 1.7.0_371; JRE 8u361; **JWS enabled by default (H)** |
| Media / staging | ~6 catalog parts → ~14 OVA parts; assembled **VMDK ≈ 57 GB** **(M)** (~2–3× staging) | **10 files ≈ 68 GB**; +~80 GB unzip +~75 GB concat → budget **200–250 GB staging** **(M)** |
| Deployed guest disk | Vision DB filesystem **≈ 208 GB** fresh; total install ≈ 233 GB **(H)** | DB node Vision ≈ 200 GB + app tier ≈ 64 GB ≈ **~265 GB** full (dual fs1/fs2) **(H)** |
| Oracle-documented RAM | **No public number confirmed** — sizing guide gives factors only; deployment guide MOS 1906691.1 **(gated, L)** | **6 GB DB + 10 GB app ≈ 16 GB** for "≤10 users"; **4+6 GB** for 0–10 OAF light/medium **(H)** |
| vCPU | commonly 2–4; no Oracle number confirmed **(L)** | **2 per tier** minimum (0–10 user table) **(H)** |
| App-side memory baseline | lower (OC4J + OHS + Forms) **(M)** | higher (WebLogic AdminServer + managed servers) **(M)** |

### 2.2 Concurrency (10–15 light users)

Oracle rules of thumb **(H)**:
- Minimum single-node (**6 GB DB + 10 GB app**) "would typically support **no more
  than ten users**."
- App tier: **2 GB JVM heap + 2 CPUs per 150–180 self-service users**;
  **40 MB per concurrent Forms user**; DB **30 MB PGA per open Forms session**.
- 12.2 Online Patching (ADOP) needs extra **2 GB (DB) + 3 GB (app)** free.

Interpretation **(M–H)**:
- **12.1.3 at 12–16 GB total:** 10–15 light concurrent users realistic.
- **12.2.12 at 24–32 GB:** comfortable; 16 GB is tight (WebLogic + 19c baseline).
- For light functional use, **neither CPU nor RAM is the limit at 10–15 users** —
  the **DB is the I/O-bound tier**; disk is the binding constraint.

### 2.3 Host bottleneck (HDD, no SSD)

- Given ~188 GiB RAM and many cores, **the spinning disk is the design limit**,
  not RAM/CPU. **(M)**
- Oracle I/O guidance: aim for **average disk service time < 10–15 ms**; **> 50 ms
  sustained is a concern**. A 7.2k HDD gives only ~75–150 random IOPS. **(H/M)**
- Where contention bites:
  1. shared class instance (datafiles + redo/undo + Forms temp + CM output)
  2. 12 linked clones — reads hit the shared base (good), but every **write**
     triggers copy-on-write deltas (bad for HDD random I/O)
  3. reports/batch/concurrent managers are the heaviest I/O
  4. snapshot/rollback between cohorts is I/O-heavy — do it when idle
- Mitigations **(M):** keep clones linked (`--full 0`), stagger batch/report
  exercises, limit simultaneously-running sandboxes, avoid ARCHIVELOG for a
  training lab, put DB/redo on separate spindles if the DL360 has multiple disks.
- **No Oracle-published "EBS on HDD vs SSD" benchmark found** — the service-time
  guidance is the closest citable position. **(L on any hard number)**

### 2.4 Why 12.1.3 is "lighter" (architecture)

| | 12.1.3 | 12.2.x |
|---|--------|--------|
| App tier | OracleAS 10g + OC4J; **no WebLogic** **(H)** | WebLogic 10.3.6 + Web Tier 11.1.1.9 **(H)** |
| DB | 11gR2 **(H)** | 12c/19c **(H)** |
| Patching | `adpatch` (downtime) | **Online Patching (ADOP)** + EBR **(H)** |
| File systems | single APPL_TOP **(H)** | dual APPL_TOP (fs1+fs2) → ~2× app disk **(H)** |

Rough per-tier examples **(H):** 12.2.5 ORACLE_HOME 9.3 GB; fs1 41 GB + fs2 34 GB
+ fs_ne 1 GB. 12.1 base: app node 35 GB; DB node Vision 208 GB. Exact per-tier
MB for 12.1 vs 12.2 is not published in one table — treat as directional. **(M)**

### 2.5 Vision data & sharing one instance

- Vision is a full fictitious company (multiple operating units, inventory orgs,
  legal entities); enough functional content for order-to-cash, P2P, GL/AP/AR. **(M)**
- The appliance unlocks ~**36 demo users** with a shared default password —
  **NOT 10+ isolated student accounts**. Create **one EBS user per student** and
  copy responsibilities. **(M–H)**
- Sharing one instance causes: data conflicts (same rows), single Standard
  Manager queue contention, shared setup drift, shared-password/audit problems. **(M)**
- This validates the architecture: **one shared class instance for functional
  navigation + per-student linked clones for Apps DBA isolation**. **(H, design)**

### 2.6 Deployment methods ranked by effort (beginner, slow internet)

| Rank | Method | Effort | Verdict |
|------|--------|--------|---------|
| 1 | **Pre-built Oracle OVA** (12.1.3 or 12.2.12 Vision) | Lowest | **Recommended** — only sanctioned free source. **(H)** |
| 2 | Community re-hosted OVA | Same | No saving; tampering/checksum/licensing risk. **(L)** |
| 3 | Cloud (OCI) EBS demo image | Low op effort | **Not free**; appliance is **on-premises-only**. **(H)** |
| 4 | Rapid Install from media | Highest (stage ~47 GB, accounts, `rapidwiz`, patches, Autoconfig) | Avoid for a first environment. **(H)** |

### 2.7 Alternative routes (what actually exists in 2026)

- **12.2.12 appliance — exists and is current** (announced 2023-05-10; OL 7.9 +
  DB 19c + WebLogic + **JWS preconfigured**; guide MOS 2933812.1 (gated)). **(H)**
  Note: the top-level Oracle VM Templates page looked stale (still listed up to
  12.2.4) — the blog + MOS note are authoritative. **(M)**
- **No separate "Oracle Linux KVM" EBS image** — supported import targets are
  Oracle VM Manager (Xen) and VirtualBox; **Proxmox (KVM) is uncertified**. **(H/L)**
- **OCI Always Free cannot run EBS**: Always Free = 2× AMD micro (1 GB) + Ampere
  A1 at 2 OCPU/12 GB, 200 GB block, idle reclaim; EBS isn't an eligible image,
  needs x86-64, ~233 GB/instance. **(H)**
- **"Sparse" app tier** only adds a secondary app tier to an existing install —
  not standalone Vision. **(H)**
- **Community OVAs** are re-hosted Oracle media — same terms, no support. **(L)**

### 2.8 Hardware fit

- Capacity is fine (~1.67 TiB); **random I/O is the risk** with many DB instances +
  COW clones. This **strengthens the case for the lighter 12.1.3 stack**. **(L/M)**
- Oracle publishes no single CPU/RAM minimum for 12.1 — sizing depends on users,
  managers, DB size, response time. Our **10–12 GB / 4 vCPU** is a practical
  estimate, not an Oracle figure. **(H on "no number"; M on the estimate)**
- 12.2.12's "24–32 GB / ~400 GB" is a reasonable estimate, unverified against
  the gated guide. **(L/M)**

---

## 3. Verdict as researched

- **12.1.3 is a defensible, acceptable choice** for resource/scale: smaller
  download (~57 GB vs ~68 GB + much larger staging), no WebLogic, DB 11g, single
  APPL_TOP, more instances per TB → best for **10+ users on HDD + slow internet**.
- **But "older = easier" is only half true.** 12.1.3's **client access is harder**
  (legacy 32-bit Firefox ESR 52 + 32-bit Oracle JRE 8, or server patches for
  JWS). **12.2.12 has JWS enabled by default** — Forms "just works" with JRE 8.
- 12.1.3 is **Sustaining Support** (no new fixes; OL6/11g EOL); 12.2.12 is
  **Premier to ≥2037**, DB 19c, ADOP/EBR — more employable.
- **No free cloud escape hatch** — local (on-prem) is the only $0 route.

---

## 4. Decision record

### 4.1 Decision (confirmed by user 2026-09-29)
- Use Oracle's **pre-built VM appliance** (not Rapid Install).
- **Build 12.1.3 Vision first** (lighter, scales to more instances); add **one
  12.2.12** only in a later phase.
- Reason: resource/scale priority + slow internet + HDD. Accepted trade-off: the
  12.1.3 Forms client is harder (legacy applet / JWS patching).

### 4.2 Rationale for 12.1.3-first
1. **Smallest effective download/staging** on a slow link. **(M)**
2. **Lighter RAM/disk** → more concurrent sandboxes within ~188 GiB / ~1.67 TiB. **(M)**
3. **Simplest stack to keep running offline** (no WebLogic, single APPL_TOP). **(H)**
4. Vision has enough functional data for a class. **(M)**
5. The user prioritised hardware fit / scale over Forms-client convenience.

### 4.3 Alternatives considered
- **12.2.12 first** — *held, not rejected.* Better for Forms access (JWS default)
  and employability, but ~2× RAM/disk/download. Revisit if client access proves
  to be the biggest blocker (see §4.5).
- **Rapid Install media** — rejected (much higher effort, bigger staging). **(H)**
- **OCI / cloud** — rejected (not free; appliance on-prem-only). **(H)**
- **Community OVAs** — rejected (trust/checksum/licensing; no effort saving). **(L)**

### 4.4 Client decision — RESOLVED 2026-09-29
- **One client VM per student** (template **9200** → clones **9201–9212**).
- OS **Oracle Linux 7.9 (64-bit)**; **32-bit Firefox ESR 52 + 32-bit Oracle JRE 8**
  NPAPI plugin (legacy applet; no 12.1.3 server patching). All artifacts verified
  obtainable ($0). Full validation in §7 below.
- Access **noVNC in-browser** (default, zero student install) or **SPICE**
  (`vga: qxl`; needs `virt-viewer`). **RDP rejected** — xrdp unavailable on OL7
  (EPEL 7 EOL).
- Accepted: an **uncertified Linux config** (Oracle certifies this plugin path on
  Windows only). JWS deferred.

### 4.4a Related decisions confirmed 2026-09-29
- **Staging location:** a dedicated Proxmox VM (`ebs-staging`, Debian 12/13, 2 vCPU,
  2–4 GB RAM, ~32 GB OS disk + ~300 GB host-shared staging), not the host. Media
  exposed to the host for import (NFS/9p or copy). See `PLAN.md` §1.3.
- **Credentials:** `~/.ebs-lab.env` (mode `600`) in that VM; never committed.

### 4.5 Revisit triggers
- eDelivery no longer lists the 12.1.3 pack → pivot to 12.2.12.
- HDD I/O makes the lab unusable even with few live clones → reconsider design
  (fewer instances, one shared instance only, or add SSD).
- The 12.1.3 Forms client becomes the dominant blocker → stand up 12.2.12.

---

## 5. Unconfirmed / to verify
- **(L)** Oracle's documented RAM/vCPU for the **12.1.3 appliance** (MOS
  1906691.1 gated).
- **(L)** Exact decompressed VMDK size for 12.1.3 single-node (~57 GB is a 2014
  user observation; guest disk is thin).
- **L** Exact 12.2.12 appliance RAM/disk minima (MOS 2933812.1 gated).
- **M** Whether 1.6 TB is one disk or a multi-disk array (still unknown) — changes
  the I/O analysis. Host CPU/RAM are now verified (Xeon Gold 6138, 188 GiB).
- **(L)** Whether the 12.1.3 pack is still on eDelivery today (see `PLAN.md` §6).
- **(L)** Proxmox/KVM is an uncertified path for this OVA.

---

## 6. Source register

| Source | Covers | Conf. |
|--------|--------|-------|
| Oracle VM Templates for EBS — https://www.oracle.com/virtualization/technologies/vm/e-business-suite.html | appliance list, Sparse tier, Xen/VirtualBox import; cites MOS 1906691.1 | H |
| Oracle blog, 12.1.3 appliances — https://blogs.oracle.com/ebstech/oracle-vm-virtual-appliances-for-e-business-suite-1213-now-available | OL 6.5, DB 11.2.0.4, Forms 10.1.2.3, JDK 1.7.0_60 | H |
| Oracle blog, 12.2.12 appliance (Wayback) — https://web.archive.org/web/20260113213150/https://blogs.oracle.com/ebstech/oracle-vm-virtual-appliance-for-ebs-122-now-available | OL 7.9, DB 19c, JWS default, on-prem-only, MOS 2933812.1 | H |
| Oracle EBS Upgrade Guide, system requirements (12.2) — https://docs.oracle.com/cd/E26401_01/doc.122/e73540/T660854T660861.htm | 6+10 GB "≤10 users", JVM/PGA per user, ADOP overhead | H |
| Oracle Rapid Install Guide 12.1 — https://docs.oracle.com/cd/E18727_01/doc.121/e12842/T422699i4773.htm | 35/55/208 GB; Vision sizes | H |
| Oracle Lifetime Support Policy: Applications (PDF) — https://www.oracle.com/us/support/library/lifetime-support-applications-069216.pdf | 12.1 Sustaining; 12.2 Premier ≥2037 | H |
| Oracle blog, 12.1.3 Sustaining Support — https://blogs.oracle.com/ebstech/reminder-ebs-1213-moves-to-sustaining-support-on-jan-1-2022 | what Sustaining excludes | H |
| OCI Always Free Resources — https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm | free-tier limits; no EBS | H |
| Oracle Cloud Free Tier — https://www.oracle.com/cloud/free/ | Always Free service list (EBS absent) | H |
| VirtualBox forum (2014) — https://forums.virtualbox.org/viewtopic.php?t=64015 | ~14 OVA parts, ~57 GB VMDK | M |
| techgoeasy, 12.2.12 on VirtualBox — https://techgoeasy.com/step-by-step-r12-2-6-ebs-installation-on-virtual-box/ | 12.2 staging sizes | M |
| Pythian, 12.1.3 VirtualBox in 1 hour — https://www.pythian.com/blog/build-an-ebs-12.1.3-sandbox-in-virtualbox-in-1-hour | older 12.1 templates, Xen caveat, small RAM floor | M |
| rishoradev, EBS R12 on VirtualBox — https://blog.rishoradev.com/2021/04/12/oracle-ebs-r12-on-virtualbox/ | appliance layout, ports | M |
| funoracleapps, EBS on OCI — https://www.funoracleapps.com/2022/08/provision-ebs-oracle-apps-instance-on.html | ~36 demo users | M |

> Gated MOS refs referenced above but not readable here: **1906691.1** (12.1.3
> deployment), **2933812.1** (12.2.12 deployment), KB367223 (12.1.x sizing),
> 396009.1 (DB init params / SGA).

---

## 7. Client stack research (2026-09-29)

Validated the decided client: **Oracle Linux 7.9 + 32-bit Firefox ESR 52.9.0esr +
32-bit Oracle JRE 8**, one VM per student, accessed via Proxmox noVNC/SPICE.

### 7.1 Verified obtainable ($0)
- **Oracle Linux 7.9 ISO** — free at <https://yum.oracle.com/oracle-linux-isos.html>.
  OL7 Premier ended **2024-12-31**; Extended Support (paid) to ~**Jun 2028**.
  Irrelevant offline. **(H)**
- **i686 multilib** — present in OL7's **x86_64** repo (Oracle's `OL7/latest/x86_64`
  metadata parsed: ~27k packages, ~**4,502 i686**, incl. `glibc`, `gtk3`,
  `dbus-glib`, `libXt`, `alsa-lib`, `nspr`, `nss`). Install with `yum install
  <pkg>.i686`. **(H)**
- **Firefox ESR 52.9.0esr i686** — Mozilla archive
  `https://ftp.mozilla.org/pub/firefox/releases/52.9.0esr/linux-i686/en-US/firefox-52.9.0esr.tar.bz2`
  (SHA256 `6a99d34d…b7ce`). Self-contained tarball; runs on 64-bit OL7 with the
  i686 libs. **Last NPAPI (non-Flash) Firefox; only the 32-bit build keeps it.** **(H)**
- **32-bit Oracle JRE 8 (`linux-i586`)** — Java SE 8 archive, needs free Oracle
  account + licence click. Ships `lib/i386/libnpjp2.so`. Free for
  non-commercial/self-study. **(H on availability; M–H on licence nuance)**

### 7.2 Wiring & gotchas
- `mkdir -p ~/.mozilla/plugins && ln -s <jre>/lib/i386/libnpjp2.so ~/.mozilla/plugins/`
  → confirm in `about:plugins`. Arch must match (32-bit browser ↔ 32-bit plugin). **(H)**
- Expect JRE security friction: **Exception Site List** for the EBS URL, unsigned/
  **SHA-1** JAR handling (`deployment.security.level`), possibly
  `plugin.load_flash_only=false`; disable Firefox auto-update. **(M)** (MOS
  393931.1/389422.1 gated.)

### 7.3 Access method (Proxmox)
- **noVNC in-browser** — per-VM, no client install; grant students a Proxmox user
  with **`VM.Console`** (API tokens cannot access consoles). Default choice. **(H)**
  `pveproxy` default `MAX_WORKERS=3`; raise for many simultaneous consoles. **(M)**
- **SPICE** — per-VM; needs `virt-viewer` installed per student; proxy port
  **3128**; requires `vga: qxl`. macOS SPICE is experimental. **(H)**
- **RDP** — rejected: **xrdp is not available on OL7** (EPEL 7 EOL; only EPEL 8/9
  builds exist). **(M–H)**
- **Linked clones** — supported on **LVM-thin** (snapshots) as well as dir/ZFS
  (qcow2 backing chain), so `local-lvm` is fine. **(H)**

### 7.4 Verdict
Valid, buildable, $0 — but a **community/uncertified** Linux configuration; expect
troubleshooting time on **JRE security settings**, not on binary availability.
The Oracle-supported alternative (JWS on 12.1.3) needs server patches and is
deferred.

### 7.5 Client-stack sources
- Oracle Linux ISOs — https://yum.oracle.com/oracle-linux-isos.html
- OL7 Extended Support — https://blogs.oracle.com/linux/extend-your-os-upgrade-timeline-oracle-linux-7s-extended-support-with-expanded-coverage
- Firefox 52.9.0esr notes — https://www.firefox.com/en-US/firefox/52.9.0/releasenotes/
- Oracle, FF ESR 52 certified (Wayback) — https://web.archive.org/web/20200918144805/https://blogs.oracle.com/ebstech/firefox-esr-52-certified-with-ebs-121-and-122
- Java SE 8 archive — https://www.oracle.com/java/technologies/javase/javase8-archive-downloads.html
- Proxmox VE admin guide — https://pve.proxmox.com/pve-docs/pve-admin-guide.html
- xrdp (EPEL note) — https://github.com/neutrinolabs/xrdp
