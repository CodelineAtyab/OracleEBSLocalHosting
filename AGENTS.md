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
9. **Credentials** live in `~/.ebs-lab.env` (mode `600`) in that staging VM —
   never committed to git, never in this repo (confirmed 2026-09-29).
10. **Student client access = one client VM per student** (confirmed 2026-09-29):
    build one **client template**, linked-clone to `client-stu01..12`.
    - OS: **Oracle Linux 7.9 (64-bit)**.
    - Stack: **32-bit Firefox ESR 52 + 32-bit Oracle JRE 8** NPAPI plugin
      (legacy applet vs the stock 12.1.3 server — no server patching). This is a
      community/uncertified Linux config (Oracle certifies this plugin path on
      Windows only); see `RESEARCH.md` §7.
    - Access: **noVNC in-browser by default** (zero student install), **SPICE
      optional** (`vga: qxl`, `virt-viewer`). RDP rejected (xrdp unavailable on
      OL7 — EPEL 7 EOL).

## Reference architecture
```
ebs1213-golden (template, shut down, snapshotted)
   |-- ebs1213-class        (shared functional instance)
   `-- ebs1213-stu01..12    (linked clones, Apps DBA sandboxes)
client-template (OL7.9 + 32-bit Firefox ESR52 + 32-bit Oracle JRE 8)
   `-- client-stu01..12 (linked clones)
                                        -> students connect via noVNC (or SPICE)
lab VLAN vmbr1 10.10.10.0/24 with static IPs + local DNS/hosts
```

## Per-instance sizing (R12.1.3)
- vCPU 4, RAM 10–12 GB, disk **300 GiB** (the appliance VMDK's virtual size).
- Import VM style: **i440fx (`--machine pc`) + SeaBIOS + LSI SCSI or SATA**,
  **`--cpu Westmere`** (NOT `host` — OL6 UEK panics on host CPU flags), `--balloon 0`,
  **e1000 NIC** preferred (virtio usually works). Keeps guest disk as `sda`.

## Staging VM (`ebs-staging`) — BUILT 2026-10-01
- OS: **Debian 13.7.0** (netinst, no GUI). VMID **900**.
- vCPU **2**, RAM **3 GB**, OS disk **~32 GB** on `local-lvm`.
- **Staging space:** a **300 GiB thin LV** `/dev/pve/ebs-staging` in pool
  `pve/data`, `mkfs.ext4`, mounted at **`/srv/ebs-media`** (in `/etc/fstab`) and
  NFS-exported to `192.168.100.0/24`; mounted inside the VM at the same path.
  (Host root/local dir are too small — the LV is why staging works.)
- Secrets: `/root/.ebs-lab.env` (mode 600).
- Purpose: download → unzip → concatenate → extract the appliance OVA.
- Delete the VM, the NFS export, the fstab line and the LV after import
  (`lvremove /dev/pve/ebs-staging`).
- See `PROGRESS.md` for exact state.

## Client VM (`client-*`)
- OS: **Oracle Linux 7.9 (64-bit)**; one template **9200** → clones **9201–9212**.
- vCPU **2**, RAM **2–4 GB** (use **2 GB** to protect the ~188 GiB budget), disk
  **20–40 GB**.
- Stack: **32-bit Firefox ESR 52 + 32-bit Oracle JRE 8**; auto-updates disabled.
- Desktop: **minimal OL7.9 install + a light DE (Xfce or LXQt)** — avoid full
  GNOME to keep each client's RAM/CPU low. (Recommendation; confirm at build.)
- Access: **noVNC in-browser** (default; needs a Proxmox user with `VM.Console`),
  **SPICE** optional (`vga: qxl` + `virt-viewer`). RDP rejected on OL7.
- **Budget watch:** linked clones save disk, not RAM — 12 client VMs + 12 EBS
  sandboxes + class can approach ~188 GiB. Cap concurrent sandboxes/CPU.

## Key IDs / names used by convention
- Staging VM (`ebs-staging`): **900** (throwaway; delete after import)
- Golden template VMID: **9000**
- Shared class VMID: **9010**
- Student clones: **9101–9112**
- Client template VMID: **9200**
- Student client clones: **9201–9212**
- Proxmox storage in examples: `local-lvm` (adjust to the actual host)
- Golden snapshot name: `golden-clean`

## Common commands
```bash
# host checks
pveversion; lscpu; pvesm status; vgs; lvs; df -h

# create/import (see README §6 for full commands)
# NOTE: --cpu Westmere (host panics the OL6 UEK kernel)
qm create 9000 --name ebs1213-golden --memory 12288 --cores 4 \
  --cpu Westmere --machine pc --bios seabios --scsihw lsi --balloon 0 \
  --net0 e1000,bridge=vmbr0
qm importdisk 9000 /srv/ebs-media/EBS1213.vmdk local-lvm   # after create; no --format on LVM-thin
# alt: qm importovf creates the VM itself (do NOT also run create)
qm importovf 9000 /srv/ebs-media/EBS1213.ovf local-lvm

# template + clones
qm snapshot 9000 golden-clean
qm clone 9000 9010 --name ebs1213-class --full 1
qm clone 9000 9101 --name ebs1213-stu01 --full 0
qm clone 9200 9201 --name client-stu01 --full 0

# batch reset
qm rollback 9101 golden-clean
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
- Never commit secrets, seeded passwords, or the Oracle account credentials.
- Keep everything reproducible: commands belong in `README.md`.
- "Verify" markers: exact ports, passwords, env-script names, and media file
  names vary by appliance — confirm on the actual VM before hard-coding.
- Do not boot the golden template for class; always clone.

## Current status
- Docs written (`README.md`, `AGENTS.md`, `PLAN.md`, `RESEARCH.md`,
  `MVP-RUNBOOK.md`, `PHASE1-CHECKLIST.md`). **Live execution state: `PROGRESS.md`.**
- **Done:** Stage 0 (host verify); Stage 1 (`ebs-staging` VM + 300 GiB thin LV +
  NFS); Stage 2 (appliance downloaded); Stage 3 (OVA extracted, VMDK 300 GiB
  virtual / 54 G sparse); Stage 4 (golden VM 9000 created + VMDK imported + boots).
- **Key fixes:** EBS VMs need **`--cpu Westmere`** (host panics the OL6 UEK
  kernel); SSH to the appliance needs **`-oHostKeyAlgorithms=+ssh-rsa`**.
- **In progress:** Stage 5 — VM boots, host `ebs`/`ebs.example.com`, static IP
  `192.168.100.223`. EBS **started** (DB `EBSDB` + app tier, ports 8000/1521), but
  the **HTTP login page returns 500** (OC4J servlet error). Suspect the FND `.dbc`
  still has a placeholder DB host → see `PROGRESS.md` "Stage 5 blocker".
- **Not yet done:** resolve the 500, change passwords, snapshot `golden-clean`
  (Stage 6), then clones + client VMs.
- Resolved 2026-09-29: platform **12.1.3**; staging **`ebs-staging` VM**;
  credentials `~/.ebs-lab.env` (mode `600`); client = **one OL7.9 VM per student**
  with 32-bit Firefox ESR52 + 32-bit Oracle JRE 8, accessed via **noVNC**
  (or SPICE).
- Open decisions (see `PLAN.md` §4): whether/when to add the 12.2.12 instance.
- Facts checked online **2026-09-29** — corrections and sources in `PLAN.md` §6.
  Key gotchas: 12.1.3 JWS needs server patches (not OOTB), applet needs **32-bit**
  Firefox ESR 52 + **32-bit Oracle JRE 8**, and `--format qcow2` is invalid on
  LVM-thin.
- Platform choice researched (12.1.3 vs 12.2.12) — see **`RESEARCH.md`**. Decision:
  **12.1.3 first** (lighter for HDD/slow link). 12.2.12 is easier for Forms (JWS
  preconfigured) and more employable but ~2× RAM/disk — deferred. Main real-world
  risk on this host is **HDD I/O**, not RAM.
