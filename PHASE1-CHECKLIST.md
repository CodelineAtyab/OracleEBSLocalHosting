# Phase 1 — Acquire the R12.1.3 Vision Appliance (Execution Checklist)

Working checklist for `README.md` §3–§4. Tick boxes as each step is proven on the
**actual Proxmox host**. Commands use `<...>` placeholders — fill in real values
and record them; do not assume filenames, URLs, or checksums.

Legend: `[ ]` not done · `[x]` done · `[!]` blocked.

---

## 0. Pre-flight — host verification (README §3)

Run on the Proxmox host, read-only. Paste output into the notes below.

- [ ] `pveversion` — record Proxmox VE version
- [ ] `lscpu | grep -E 'Model name|Virtualization'` — record CPU + VT-x
- [ ] `lscpu | grep -o -E 'cx16|popcnt|sse4_2|lahf_lm' | sort -u` — must include
      all four for Proxmox VE 8/9 (x86-64-v2); the Gold 6138 passes
- [ ] `pvesm status` — confirm storage supports snapshots/linked clones
      (**LVM-thin, ZFS, or dir/qcow2**)
- [ ] `vgs; lvs` — record free VG space
- [ ] `df -h` — confirm free space for staging
- [ ] Confirm host staging space: ~**300 GB** free for the media (DECIDED
      2026-09-29: staging is a dedicated **`ebs-staging` Debian 12/13 VM**; space is
      a host-exported folder, e.g. `/srv/ebs-media`, per `PLAN.md` §1.3)

```
# Notes (fill in from above)
Proxmox VE version:
CPU model / VT-x:
x86-64-v2 flags:
Storage backend for clones:
Free VG / free disk:
Staging path:
```

**Gate:** if any CPU flag is missing, or storage can't do linked clones, stop and
resolve before downloading tens of GB.

---

## 1. Prepare the `ebs-staging` VM and space

- [ ] Create the VM: **Debian 12/13 minimal**, vCPU **2**, RAM **3 GB**, OS disk
      **~32 GB** (VMID e.g. 900) — see `PLAN.md` §1.3 / `MVP-RUNBOOK.md` Step 2
- [ ] Give it **~300 GB** staging space on a host-exported folder (NFS/9p, e.g.
      `/srv/ebs-media`) so the host can import directly
- [ ] Inside the VM: `sudo mkdir -p /srv/ebs-media` and mount the shared folder
- [ ] Confirm free space `df -h /srv/ebs-media` >= ~300 GB
- [ ] `sudo apt install -y wget unzip tar nfs-common`; confirm `command -v wget`
- [ ] Create `~/.ebs-lab.env` with `umask 077` and `chmod 600` (secrets, never
      committed)

---

## 2. Get access to Oracle Software Delivery Cloud

- [ ] Create/confirm a free Oracle account (SSO) at
      <https://profile.oracle.com> — needed for edelivery
- [ ] Sign in at <https://edelivery.oracle.com>
- [ ] Filter products by **Linux/OVM/VMs**

---

## 3. Locate the correct media pack

- [ ] Search by **Release**: `Oracle VM Virtual Appliance for Oracle E-Business
      Suite 12.1.3` (or search "e-business")
- [ ] Confirm it is the **12.1.3 Vision** virtual appliance (not Rapid Install
      media, not 12.2.x)
- [ ] Confirm it is the **2014 "Virtual Appliances"** pack (Oracle Linux 6.5,
      OVM + VirtualBox compatible) — **not** the 2013 "Oracle VM Templates" pack
      (Oracle Linux 5 + a **Xen** kernel that won't boot on Proxmox). Single Node
      VISION part numbers: **V46557-01 … V46562-01**.
- [ ] Confirm **no Support Identifier (CSI)** or payment is demanded; if so, STOP.
- [ ] Record the exact product name + release/patch shown on screen

```
Product name as shown:
Release / patch:
```

---

## 4. Accept terms and record media metadata (before download)

- [ ] Add the media pack to the cart → Continue
- [ ] Accept the **Oracle Standard Terms and Restrictions**
- [ ] Open the **media pack readme first** and record:
  - [ ] exact filenames + count of parts
  - [ ] any published checksums
  - [ ] seeded OS / EBS / DB passwords (do **not** commit them to this repo)
- [ ] Record each file's name and size below

```
Files + sizes:
Checksums provided? (y/n):
```

> Reference deployment guide: **MOS Doc 1906691.1 — Oracle VM Virtual Appliances
> for Oracle E-Business Suite Deployment Guide, Release 12.1.3.** Appliance ships
> **Oracle Linux 6.5**, EBS 12.1.3 (Apps RPC1, CPU Apr 2014), DB **11.2.0.4**,
> Forms/Reports **10.1.2.3**, JDK **1.7.0_60**.

> **Availability caveat (checked 2026-09-29):** Oracle's EBS VM page still lists
> the 12.1.3 appliance and cites Doc 1906691.1, but eDelivery now requires sign-in
> and the latest public confirmation of the 12.1.3 pack there is 2022. Confirm it
> is listed before the long download. EBS 12.1.3 is in **Sustaining Support**
> (since 2022-01-01).

---

## 5. Download (slow link → always resumable)

- [ ] Copy the real signed URL(s) from edelivery for each file
- [ ] Download with resume; re-run the same command after any interruption:

```bash
cd /srv/ebs-media
# Repeat for each file URL; -c resumes, -O keeps the expected filename
wget -c <each-file-url>
```

- [ ] If a download stalls, re-run `wget -c` against the same URL
- [ ] (Optional, if `aria2c` present) multi-connection resume:
      `aria2c -c -x4 -s4 <url>`

---

## 6. Verify and hand off

- [ ] Verify checksums for **every** file (only against published values):
      `sha256sum <file>` (or the algorithm the readme states)
- [ ] Confirm the parts look like a split OVA / zip set (names match the readme)
- [ ] Store the seeded passwords in a **local, non-committed** note
- [ ] Leave media in place for Phase 2 (§5): unzip → concatenate → extract OVA

```
Download complete? (y/n):
Checksums verified? (y/n):
Ready for Phase 2? (y/n):
```

---

## Blockers / notes

- (record anything that blocks or differs from the runbook here, then update
  `README.md` so the next cohort inherits the correction)
