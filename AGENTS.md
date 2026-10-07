# AGENTS.md — Core Context

Read this first. It is the persistent memory for new sessions working on this
project. All planning/research is already captured in this repo — **do not
re-fetch it online unless a decision is being revisited.**

## Docs map (read in this order)
| File | What it is |
|------|-----------|
| `PROGRESS.md` | **Live build status — where execution left off (read this too)** |
| `AGENTS.md` | This file — context, locked decisions, status |
| `README.md` | The runbook (what to do, phase by phase) |
| `PLAN.md` | OS choices, resource budget, per-phase verification, fact-check log |
| `MVP-RUNBOOK.md` | Literal step-by-step to stand up the first working instance |
| `PHASE1-CHECKLIST.md` | Tickable checklist for host verify + appliance download |
| `RESEARCH.md` | Why decisions were made (12.1.3 vs 12.2.12, client stack, sources) |

**Execution order for a new session:** `MVP-RUNBOOK.md` Step 1 → Step 8 (MVP-A),
optionally Step 9 (MVP-B), then `README.md` §9–§11 for the full lab. Start by
running host verification (`README.md` §3) and confirming the appliance is still
on edelivery (`PHASE1-CHECKLIST.md` §3).

## Action → script (what to run when the user asks)

Use these **repo scripts** instead of ad-hoc commands. They read secrets from the
git-ignored `.env` and the VM list from `scripts/inventory.conf`.

| If the user asks to… | Run |
|----------------------|-----|
| **bring the lab up** / start everything (e.g. after a reboot) | `scripts/lab-start.sh` |
| **stop the lab** | `scripts/lab-stop.sh` |
| **shut the whole host down** (e.g. to enter BIOS) | `scripts/lab-stop.sh --poweroff` |
| **check status** — "is the lab up?" | `scripts/lab-status.sh` |
| **add N students** | `scripts/add-students.sh N` |
| **fix / reconfigure one sandbox** | `scripts/provision-sandbox.sh <vmid>` |
| **reset a student's sandbox** (wipe + re-clone; `--client` too) | `scripts/reset-student.sh <student> [--client]` |
| **student can't see their VM** in the Proxmox UI (esp. after a reset) | `scripts/sync-acls.sh` |
| **create the class EBS logins** (functional users) | `scripts/create-class-users.sh` |
| **back up the golden + templates** (DR) | `scripts/export-images.sh` |
| **rebuild the golden from pristine media** (rare, DR) | `scripts/build-golden.sh --yes` |

Dependency-free wrapper: `./run.sh up | down [--poweroff] | status | init N |
provision <vmid> | reset <student> [--client] | sync-acls | class-users | export | build-golden`
(an optional `Makefile` exposes the same as `make up`, `make init N=3`, …).

**Rules:** never keep operational logic in `/tmp` (tmpfs — wiped on reboot; only
`scripts/` survives). Never commit secrets — they live in `.env` (mode `600`).
See `README.md` §14 for the full script reference.

## What this project is
Build and maintain a **free, offline Oracle E-Business Suite (EBS) training lab**
on a single Proxmox host, so students (and each new cohort) can practise EBS
functional and Apps DBA skills at zero license cost.

## Hard constraints (do not change without the user)
- Host (verified 2026-10-01): **DL360, 2× Xeon Gold 6138 (40c/80t)**, **188 GiB
  RAM**, **~1.67 TiB LVM-thin** (`local-lvm`) + ~85 GiB `local` dir.
- Hypervisor: **Proxmox VE 9.2.20** (kernel 7.0.14-19-pve).
- Internet: **slow** — prefer smaller downloads; never re-download unnecessarily.
- Audience: **6–15 concurrent** students, **informal / non-commercial** training.
- Budget: **$0** (no paid licenses, no cloud subscriptions).
- Primary platform: **EBS 12.1.3 Vision** pre-built Oracle VM appliance.
- Optional later: **EBS 12.2.12 Vision** for ADOP/WebLogic/19c.
- Not an Oracle Academy institution.

## Locked decisions
1. Use Oracle's **pre-built VM appliance** from `edelivery.oracle.com`; do not
   build EBS from Rapid Install media (heavier, slower to stand up).
2. **12.1.3 first** (confirmed 2026-09-29; see `RESEARCH.md` §4.4) because it is
   lighter and scales to more concurrent instances. A 12.2.12 instance is
   **optional/later** — add it only if ADOP/WebLogic skills are needed (not
   required just to teach EBS concepts).
3. **One golden template + linked clones** (qcow2 backing chain on dir/ZFS, or
   LVM-thin snapshots — all support linked clones) to fit 1.6 TB. Do not
   full-clone 15 instances.
4. **One shared class instance** for functional use + **~12 per-student
   sandboxes** for Apps DBA work.
5. Isolate the lab on a private VLAN/bridge with static IPs + local DNS/hosts.
   **(As built 2026-10-03: flat `vmbr0` LAN — 192.168.100.0/24 — with unique
   static IPs for the EBS VMs and `/etc/hosts` for names; clients on DHCP. The
   isolated `vmbr1` VLAN + local DNS remains an optional later refinement.)**
6. Solve Forms access with a dedicated client, **not** by upgrading browsers.
   (See decision 10 for the locked config; JWS on 12.1.3 needs server patches and
   is deferred — `PLAN.md` §1.4.)
7. **Simplest-first:** get one working instance + snapshot (MVP) before
   building clones, the client VM, or helper containers. Defer optimization —
   see `PLAN.md` §0.
8. **All staging work happens in a dedicated Proxmox VM** (`ebs-staging`,
   Debian 12/13), not on the Proxmox host (confirmed 2026-09-29). Media is exposed
   to the host for `qm importovf`/`qm importdisk` via a shared folder (see
   `PLAN.md` §1.3).
9. **Credentials** — the original staging secrets live in `~/.ebs-lab.env`
   (mode `600`) in the `ebs-staging` VM. For the built lab, a local **`.env`
   (mode `600`) in the repo directory is permitted** as the working credential
   store; it is **git-ignored** (`.gitignore`) and must **never be committed,
   copied into docs, or shared**. The Oracle account credentials and the
   edelivery `wget` bearer token must never be written to the repo at all.
   (Updated 2026-10-03.)
10. **Student client access = one client VM per student** (confirmed 2026-09-29):
    build one **client template**, linked-clone to `client-stu01..12`.
    - OS: **Oracle Linux 7.9 (64-bit)**.
    - Stack — **UPDATED 2026-10-03 (free path):** **Oracle Linux 7.9 (64-bit) +
      Xfce (archived EPEL 7) + Firefox ESR 52.9.0esr (x86_64) + OpenJDK 8 (x86_64)
      + IcedTea-Web 1.7.1** NPAPI plugin (`/usr/lib64/IcedTeaPlugin.so`). OpenJDK
      ships no plugin, so IcedTea-Web supplies it — **arch must match**, hence the
      64-bit stack. Original plan was 32-bit Oracle JRE 8; **fallback** to 32-bit
      Oracle JRE 8 + 32-bit Firefox if IcedTea-Web can't run the applet. Legacy
      applet vs the stock 12.1.3 server (no server patching); community/uncertified
      (Oracle certifies the plugin path on Windows only); see `RESEARCH.md` §7.
    - Access: **noVNC in-browser by default** (zero student install), **SPICE
      optional** (`vga: qxl`, `virt-viewer`). RDP rejected (xrdp unavailable on
      OL7 — EPEL 7 EOL).

## Reference architecture
```
ebs1213-golden  (VM 9000, Proxmox TEMPLATE, stopped -- no snapshot)
   |-- ebs1213-class        (VM 9010, full clone, static .223, shared functional)
   `-- ebs1213-stu01..09    (VMs 9101-9109, linked clones; static .231-.235 + .241-.244,
                             Apps DBA sandboxes)      [target: stu10..12 -> 9110-9112]
client-template (VM 9200, OL7.9 + Xfce + Firefox ESR52 x64 + OpenJDK8/IcedTea-Web)
   `-- client-stu01..09     (VMs 9201-9209, linked clones, DHCP) [target: 9210-9212]
network: vmbr0 192.168.100.0/24 -- EBS on static IPs + /etc/hosts; clients DHCP
         (flat-LAN DHCP pool overlaps the static range -> pick ARP-free IPs; vmbr1 planned)
access:  Proxmox web UI :8006 -> noVNC; users stu01-stu09@pve (PVEVMUser, scoped)
```

## Per-instance sizing (R12.1.3)
- vCPU 4, RAM 10–12 GB, disk **300 GiB** (the appliance VMDK's virtual size).
- Import VM style: **i440fx (`--machine pc`) + SeaBIOS + SATA (AHCI) disk**,
  **`--cpu Westmere`** (NOT `host` — OL6 UEK panics on host CPU flags), `--balloon 0`,
  **e1000 NIC** preferred (virtio usually works). Keeps guest disk as `sda`.
- **Do NOT use the LSI SCSI controller** (`--scsihw lsi`): the guest's `sym53c8xx`
  driver panics under KVM (`sym_int_sir` / "Fatal exception in interrupt") under
  I/O load — verified 2026-10-03. Attach the disk as **`sata0`** instead.

## Staging VM (`ebs-staging`) — RETIRED 2026-10-03 (media kept)
- Was Debian 13 VMID **900** (2 vCPU / 3 GB / 32 GB), used only to download →
  unzip → concatenate → extract the appliance OVA. **VM removed 2026-10-03; NFS
  export removed; `nfs-kernel-server` stopped/disabled.**
- **Kept:** the 300 GiB thin LV `/dev/pve/ebs-staging`, still `mkfs.ext4` and
  mounted at **`/srv/ebs-media`** (in `/etc/fstab`) — it now holds only the
  **pristine `disk1.vmdk` (~54 GiB, `streamOptimized`) + its `.ovf`**, so the
  appliance can be re-imported without re-downloading.
- **Deleted at retirement:** the 14 `*.ova.NN` segments, the concatenated
  `EBS1213_VISION.ova`, wget logs, and `download.sh` (had an expired bearer
  token). `fstrim` released the space (thin pool back to ~32%).
- **Full rebuild, if ever needed:** re-import the kept VMDK —
  `qm importdisk <vmid> /srv/ebs-media/Oracle-E-Business-Suite-12.1.3-VISION-INSTALL-disk1.vmdk local-lvm`,
  then attach as **`sata0`** (NOT LSI) — see `README.md` §6. Re-create a Debian
  staging VM + NFS only if you must re-download parts from edelivery.
- See `PROGRESS.md` for exact state.

## Client VM (`client-*`) — template `9200` BUILT 2026-10-03
- OS: **Oracle Linux 7.9 (64-bit)** (minimal install); one template **9200** →
  clones **9201–9212** (built `9201–9209`). Built VM: 2 vCPU / **2 GB** / 30 GB, virtio, DHCP.
- Desktop: **Xfce** (from the archived EPEL 7 repo) with **lightdm autologin**
  (`student` user) — light enough for 2 GB.
- Stack (free path): **Firefox ESR 52.9.0esr x86_64** + **java-1.8.0-openjdk
  (1.8.0_432)** + **icedtea-web 1.7.1**; plugin symlinked into
  `/usr/lib64/mozilla/plugins`, `/opt/firefox/plugins` and `~/.mozilla/plugins`.
  `plugin.load_flash_only=false` via `/opt/firefox/defaults/pref/local-settings.js`
  + `mozilla.cfg`; IcedTea-Web exception site in `/etc/icedtea-web/exception.sites`.
  Auto-updates disabled.
- **Fallback:** 32-bit Oracle JRE 8 + 32-bit Firefox if IcedTea-Web can't launch
  the applet (Oracle JRE is the only source of `libnpjp2.so`).
- Access: **noVNC in-browser** (default; needs a Proxmox user with `VM.Console`),
  **SPICE** optional (`vga: qxl` + `virt-viewer`). RDP rejected on OL7.
- **Student accounts (2026-10-07):** Proxmox users `stu01–stu09@pve` (password =
  lab password) with role **`PVEVMUser`** on `/vms/920N` (client) + `/vms/910N`
  (sandbox) — noVNC/power for their own two VMs only. Client VMs are
  **manual-start** (no `onboot`).
- **Budget watch:** linked clones save disk, not RAM — 12 client VMs + 12 EBS
  sandboxes + class can approach ~188 GiB. Cap concurrent sandboxes/CPU.

## Key IDs / names used by convention
- Staging VM (`ebs-staging`): **900** — **retired 2026-10-03** (media kept at `/srv/ebs-media`)
- Golden template VMID: **9000** (Proxmox **template**; templates cannot hold snapshots)
- Shared class VMID: **9010** (static `192.168.100.223`)
- Student EBS clones: **9101–9112** (built `9101–9109`; static `.231–.235` + `.241–.244`)
- Client template VMID: **9200**
- Student client clones: **9201–9212** (built `9201–9209`, DHCP)
- Student Proxmox users: **`stu01–stu09@pve`** (role `PVEVMUser`)
- Proxmox storage in examples: `local-lvm` (adjust to the actual host)

## Common commands
```bash
# --- lab control (repo scripts/ — use these instead of ad-hoc commands) ---
scripts/lab-start.sh              # boot all EBS VMs + start DB/app tiers + boot clients
scripts/lab-start.sh ebs          # EBS guests only   (clients only: scripts/lab-start.sh clients)
scripts/lab-status.sh             # VM states + AppsLogin code per EBS guest
scripts/lab-stop.sh               # cleanly stop all guests (leave host up)
scripts/lab-stop.sh --poweroff    # ...then power off the host
# inventory (VMID -> name -> role -> IP) is in scripts/inventory.conf; secrets in .env

# host checks
pveversion; lscpu; pvesm status; vgs; lvs; df -h

# create/import (see README §6 for full commands)
# NOTE: --cpu Westmere (host panics the OL6 UEK kernel)
qm create 9000 --name ebs1213-golden --memory 12288 --cores 4 \
  --cpu Westmere --machine pc --bios seabios --balloon 0 \
  --net0 e1000,bridge=vmbr0
qm importdisk 9000 /srv/ebs-media/EBS1213.vmdk local-lvm   # after create; no --format on LVM-thin
qm set 9000 --sata0 local-lvm:vm-9000-disk-0 && qm set 9000 --boot order=sata0
# SATA, NOT --scsihw lsi: the LSI sym53c8xx driver panics under KVM on this OL6 guest.
# alt: qm importovf creates the VM itself (do NOT also run create)
qm importovf 9000 /srv/ebs-media/EBS1213.ovf local-lvm

# template + clones
qm template 9000                                      # golden is a TEMPLATE (no snapshots)
qm clone 9000 9010 --name ebs1213-class --full 1
qm clone 9000 9101 --name ebs1213-stu01 --full 0      # then set FND_NODES.SERVER_ADDRESS
qm clone 9200 9201 --name client-stu01 --full 0

# batch reset: templates cannot hold snapshots -> re-clone instead of rollback
qm destroy 9101 ; qm clone 9000 9101 --name ebs1213-stu01 --full 0
```

## Licensing stance (important — keep it honest)
EBS is **not free software**. The appliance is free to obtain but Oracle's terms
apply; there is no free classroom license for this informal setup. Keep the lab
**offline/LAN-only, non-commercial, dev/self-study, no redistribution, no
production use**. Do not expose it to the public internet. State this scope when
relevant; do not imply the setup is legally "licensed for training."

## Conventions
- Prefer **documented Oracle procedures** (MOS Doc IDs in `README.md`) over
  blog folklore when they conflict.
- Never commit secrets or passwords. Lab credentials may be kept locally in a
  mode-`600`, git-ignored `.env` in this directory; **never** commit it or paste
  its contents into tracked docs. The Oracle account credentials and the
  edelivery `wget` token must never touch the repo.
- Keep everything reproducible: commands belong in `README.md`.
- "Verify" markers: exact ports, passwords, env-script names, and media file
  names vary by appliance — confirm on the actual VM before hard-coding.
- Do not boot the golden template for class; always clone.

## Current status
- Docs written (`README.md`, `AGENTS.md`, `PLAN.md`, `RESEARCH.md`,
  `MVP-RUNBOOK.md`, `PHASE1-CHECKLIST.md`). **Live execution state: `PROGRESS.md`.**
- **Done:** Stages 0–6 (host verify → golden VM `9000` booting EBS; MVP-A); MVP-B
  (Forms from client VM) passed. **Live (2026-10-07):** golden `9000` templatized;
  class `9010` (`.223`); **EBS sandboxes `9101–9109`** (`.231–.235` + `.241–.244`,
  all `302`); client template `9200` + clones `9201–9209`; Proxmox users
  `stu01–stu09@pve`. Full detail: `PROGRESS.md` Stages 7–10.
- **Key fixes:** EBS VMs need **`--cpu Westmere`** (host panics the OL6 UEK
  kernel); SSH to the appliance needs **`-oHostKeyAlgorithms=+ssh-rsa`**; the FND
  `.dbc` must be **generated by AutoConfig** (`adautocfg.sh appspass=apps`), not
  left as the shipped `template.dbc`.
- **Stage 5 blocker RESOLVED (2026-10-03):** the HTTP 500 was caused by the FND
  `.dbc` still being the shipped `template.dbc` (`DB_HOST=host_name`,
  `DB_PORT=port_number`, `TWO_TASK=database`) while the context XML was already
  correct. Fixed by running apps-tier **AutoConfig**
  (`$ADMIN_SCRIPTS_HOME/adautocfg.sh appspass=apps` as `oracle`), then
  `startapps.sh`. `AppsLogin` now 302 → login form; all OC4J services `Alive`.
  Details in `PROGRESS.md` "Stage 5 blocker".
- **Live (2026-10-07):** class `9010` + **EBS sandboxes `9101–9109` (`302`)** +
  client clones `9201–9209`; **Proxmox users `stu01–stu09@pve`** (password = lab)
  hold `PVEVMUser` on `/vms/920N` + `/vms/910N` for noVNC. Next: expand with
  `scripts/add-students.sh N`; optional `vmbr1` VLAN. **Never boot 9000; clone it.**
  EBS clones need `FND_NODES.SERVER_ADDRESS` = their own IP (see `PROGRESS.md`
  "Stage 9/10"); on a flat LAN pick ARP-free static IPs.
- **Assumes:** `qm shutdown` does **not** power off the guest (no acpid) — use a
  clean SSH `shutdown -h now` (documented in `PROGRESS.md` Stage 6).
- Resolved 2026-09-29 (client stack **updated 2026-10-03**): platform **12.1.3**;
  staging VM (now retired); credentials in the git-ignored `.env`; client = **one
  OL7.9 VM per student** with Firefox ESR52 + OpenJDK 8/IcedTea-Web (or Oracle JRE
  fallback), accessed via **noVNC** (or SPICE).
- Open decisions (see `PLAN.md` §4): whether/when to add the 12.2.12 instance.
- Facts checked online **2026-09-29** — corrections and sources in `PLAN.md` §6.
  Key gotchas: 12.1.3 JWS needs server patches (not OOTB); the Forms applet needs
  an NPAPI plugin (32-bit Oracle JRE, or the free 64-bit OpenJDK + IcedTea-Web
  path); `--format qcow2` is invalid on LVM-thin.
- Platform choice researched (12.1.3 vs 12.2.12) — see **`RESEARCH.md`**. Decision:
  **12.1.3 first** (lighter for HDD/slow link). 12.2.12 is easier for Forms (JWS
  preconfigured) and more employable but ~2× RAM/disk — deferred. Main real-world
  risk on this host is **HDD I/O**, not RAM.
