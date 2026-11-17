#!/usr/bin/env python3
"""collect.py - EBS lab status collector (one long-lived process).

Runs inside the lab-portal LXC (VMID 9300).  Every COLLECT_INTERVAL seconds it
walks the guests of every endpoint listed in endpoints.conf and atomically
rewrites state.json, which nginx serves to the status page.

Design (agreed 2026-11-14):
  * serial - one guest at a time, COLLECT_INTERVAL seconds after a pass ends
  * PROBE_TIMEOUT seconds for every network operation
  * CYCLE_BUDGET caps a pass; the next pass resumes where it stopped
  * read-only - the Proxmox API token only needs PVEAuditor

Usage:
  collect.py            run forever (systemd unit lab-portal-collect)
  collect.py --once     run one pass, print a summary, exit
  collect.py --dump     print the state JSON to stdout (implies --once)
"""
from __future__ import annotations

import json
import logging
import os
import re
import signal
import socket
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

DEFAULT_CONF = os.environ.get("PORTAL_CONF", "/etc/lab-portal/portal.conf")

DEFAULTS = {
    "COLLECT_INTERVAL": "10",
    "PROBE_TIMEOUT": "5",
    "CYCLE_BUDGET": "30",
    "WEB_ROOT": "/var/www/lab-portal",
    "ENDPOINTS_FILE": "/etc/lab-portal/endpoints.conf",
    "APP_PORT": "8000",
    "APPS_PATH": "/OA_HTML/AppsLogin",
    "DB_PORT": "1521",
    "DB_SID": "EBSDB",
    "VNC_PORT": "5900",
    # Probing VNC opens (and closes) a TCP connection, which the guest's x11vnc
    # logs.  Check it every Nth pass only; the result is reused in between.
    "VNC_PROBE_EVERY": "6",
}

log = logging.getLogger("collect")
STOP = threading.Event()

# The Proxmox API uses a self-signed certificate on the LAN.  The token is
# read-only, so accepting it without verification is an accepted trade-off.
SSL_CTX = ssl.create_default_context()
SSL_CTX.check_hostname = False
SSL_CTX.verify_mode = ssl.CERT_NONE


class AuthError(Exception):
    """401/403 - bad token or missing PVEAuditor.  Back off, do not hammer."""


class EndpointError(Exception):
    """Endpoint unreachable, or answered something unusable."""


# --------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------
def read_conf(path):
    conf = dict(DEFAULTS)
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.split("#", 1)[0].strip()
                if not line or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                conf[key.strip()] = val.strip().strip("'\"")
    except OSError as exc:
        log.warning("config %s: %s - using defaults", path, exc)
    return conf


def read_endpoints(path):
    """Each line: <label> <url> <token-file>"""
    endpoints = []
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) != 3:
                    log.warning("endpoints: ignoring malformed line %r", line)
                    continue
                label, url, token_file = parts
                endpoints.append(
                    {"label": label, "url": url.rstrip("/"), "token_file": token_file}
                )
    except OSError as exc:
        log.error("endpoints file %s: %s", path, exc)
    return endpoints


def read_token(path):
    try:
        with open(path, encoding="utf-8") as fh:
            token = fh.read().strip()
    except OSError as exc:
        raise EndpointError(f"token file {path}: {exc}") from exc
    if not token:
        raise EndpointError(f"token file {path} is empty")
    return token


# --------------------------------------------------------------------------
# Proxmox API (read-only)
# --------------------------------------------------------------------------
def api_get(base, token, path, timeout):
    req = urllib.request.Request(
        base + path,
        headers={
            "Authorization": "PVEAPIToken=" + token,
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise AuthError(f"HTTP {exc.code} for {path} (token/ACL problem)") from exc
        raise EndpointError(f"HTTP {exc.code} for {path}") from exc
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise EndpointError(f"{path}: {exc}") from exc
    return payload.get("data")


# --------------------------------------------------------------------------
# guest probes
# --------------------------------------------------------------------------
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """We want the raw status code - 302 is what we are looking for."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_NO_REDIRECT = urllib.request.build_opener(_NoRedirect)


def http_status(ip, port, path, timeout):
    try:
        with _NO_REDIRECT.open(f"http://{ip}:{port}{path}", timeout=timeout) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:  # noqa: BLE001 - any failure means "not answering"
        return None


def tcp_open(ip, port, timeout):
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def agent_ip(base, token, node, vmid, timeout):
    """First non-loopback IPv4 reported by the QEMU guest agent."""
    data = api_get(
        base,
        token,
        f"/api2/json/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces",
        timeout,
    )
    # the agent endpoint wraps its answer: {"data": {"result": [...]}}
    if isinstance(data, dict):
        data = data.get("result")
    if not isinstance(data, list):
        return None
    for iface in data:
        for addr in iface.get("ip-addresses") or []:
            if addr.get("ip-address-type") != "ipv4":
                continue
            ip = addr.get("ip-address") or ""
            if not ip or ip.startswith("127.") or ip.startswith("169.254."):
                continue
            return ip
    return None


def classify(name):
    low = name.lower()
    if low.startswith("client"):
        return "client"
    if low.startswith("ebs"):
        return "ebs"
    return "other"


def student_of(name):
    match = re.search(r"stu(?:dent)?[_-]?0*(\d{1,3})$", name, re.I)
    return int(match.group(1)) if match else None


def probe_checks(role, ip, conf, timeout):
    if role == "ebs":
        return {
            "apps": http_status(
                ip, int(conf["APP_PORT"]), conf["APPS_PATH"], timeout
            ),
            "db": tcp_open(ip, int(conf["DB_PORT"]), timeout),
        }
    if role == "client":
        return {"vnc": tcp_open(ip, int(conf["VNC_PORT"]), timeout)}
    return {}


# --------------------------------------------------------------------------
# collector
# --------------------------------------------------------------------------
def iso(epoch=None):
    stamp = time.time() if epoch is None else epoch
    return datetime.fromtimestamp(stamp, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_previous(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    guests = {}
    for guest in data.get("guests") or []:
        if "site" in guest and "vmid" in guest:
            guests[(guest["site"], guest["vmid"])] = guest
    return guests


def write_state(path, state):
    tmp = path + ".tmp"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=1)
        fh.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)  # atomic: nginx never sees a partial file


class Collector:
    def __init__(self, conf):
        self.conf = conf
        self.endpoints = read_endpoints(conf["ENDPOINTS_FILE"])
        self.state_path = os.path.join(conf["WEB_ROOT"], "state.json")
        self.previous = load_previous(self.state_path)
        self.tokens = {}
        self.endpoint_health = {}
        self.cursor = 0
        self.cycle_no = 0
        self.first_pass = True

    # -- one pass ---------------------------------------------------------
    def pass_once(self):
        started = time.monotonic()
        timeout = float(self.conf["PROBE_TIMEOUT"])
        budget = float(self.conf["CYCLE_BUDGET"])
        now = time.time()

        endpoints_out = []
        order = []          # (endpoint, token, vm) for every qemu guest
        guests = []
        auth_blocked = False

        for endpoint in self.endpoints:
            label = endpoint["label"]
            known = self.endpoint_health.get(label, {})
            item = {
                "label": label,
                "url": endpoint["url"],
                "ok": False,
                "error": None,
                "guests": 0,
                "nodes": [],
                "last_ok": known.get("last_ok"),
            }
            before = len(order)
            try:
                token = self.tokens.get(label) or read_token(endpoint["token_file"])
                self.tokens[label] = token
                resources = (
                    api_get(
                        endpoint["url"],
                        token,
                        "/api2/json/cluster/resources",
                        timeout,
                    )
                    or []
                )
                item["nodes"] = self.fetch_nodes(endpoint, token, timeout)
                item["ok"] = True
                item["last_ok"] = iso(now)
                self.endpoint_health[label] = {
                    "ok": True,
                    "error": None,
                    "last_ok": item["last_ok"],
                }
                for vm in resources:
                    if vm.get("type") != "qemu" or vm.get("template"):
                        continue
                    order.append((endpoint, token, vm))
            except AuthError as exc:
                auth_blocked = True
                item["error"] = str(exc)
                self.endpoint_health[label] = {
                    "ok": False,
                    "error": str(exc),
                    "last_ok": item["last_ok"],
                }
                log.error("%s: %s", label, exc)
            except EndpointError as exc:
                item["error"] = str(exc)
                self.endpoint_health[label] = {
                    "ok": False,
                    "error": str(exc),
                    "last_ok": item["last_ok"],
                }
                log.error("%s: %s", label, exc)
            item["guests"] = len(order) - before
            endpoints_out.append(item)

        # -- walk the guests serially, bounded by CYCLE_BUDGET ------------
        total = len(order)
        checked = 0
        complete = True
        if total:
            start = self.cursor % total
            for index in range(total):
                if time.monotonic() - started > budget:
                    complete = False
                    log.warning(
                        "cycle budget %.0fs hit after %d/%d guests; resuming at %d",
                        budget,
                        index,
                        total,
                        (start + index) % total,
                    )
                    break
                endpoint, token, vm = order[(start + index) % total]
                checked = index + 1
                try:
                    guests.append(self.collect_guest(endpoint, token, vm, timeout))
                except AuthError:
                    raise
                except Exception:  # noqa: BLE001 - never abort the whole pass
                    log.exception("collecting %s/%s failed", endpoint["label"], vm["vmid"])
            self.cursor = (start + checked) % total

        # -- carry forward what we could not refresh ----------------------
        seen = {(guest["site"], guest["vmid"]) for guest in guests}
        down = {item["label"] for item in endpoints_out if not item["ok"]}
        alive = {
            (endpoint["label"], int(vm["vmid"])) for endpoint, _, vm in order
        } | {key for key in self.previous if key[0] in down}
        for key in alive - seen:
            old = self.previous.get(key)
            if old:
                guests.append(dict(old, carried=True, ip_stale=bool(old.get("ip"))))

        for item in endpoints_out:
            if not item["ok"]:
                complete = False

        guests = self.annotate(guests)
        warnings = self.build_warnings(endpoints_out, guests, complete)

        state = {
            "generated": iso(),
            "generated_epoch": int(time.time()),
            "interval": int(float(self.conf["COLLECT_INTERVAL"])),
            "cycle_ms": int((time.monotonic() - started) * 1000),
            "complete": complete,
            "endpoints": endpoints_out,
            "guests": guests,
            "warnings": warnings,
            "db_sid": self.conf["DB_SID"],
            "app_port": int(self.conf["APP_PORT"]),
            "db_port": int(self.conf["DB_PORT"]),
            "vnc_port": int(self.conf["VNC_PORT"]),
        }

        self.log_changes(guests, endpoints_out)
        write_state(self.state_path, state)
        self.previous = {(g["site"], g["vmid"]): g for g in guests}
        self.first_pass = False
        self.cycle_no += 1
        return state, auth_blocked

    # -- helpers ----------------------------------------------------------
    def fetch_nodes(self, endpoint, token, timeout):
        nodes = []
        try:
            data = api_get(endpoint["url"], token, "/api2/json/nodes", timeout) or []
        except EndpointError:
            return nodes
        for node in data:
            nodes.append(
                {
                    "node": node.get("node"),
                    "status": node.get("status"),
                    "mem": node.get("mem"),
                    "maxmem": node.get("maxmem"),
                    "disk": node.get("disk"),
                    "maxdisk": node.get("maxdisk"),
                    "uptime": node.get("uptime"),
                }
            )
        return nodes

    def collect_guest(self, endpoint, token, vm, timeout):
        name = vm.get("name") or f"vm-{vm['vmid']}"
        guest = {
            "site": endpoint["label"],
            "vmid": int(vm["vmid"]),
            "node": vm.get("node"),
            "name": name,
            "role": classify(name),
            "student": student_of(name),
            "state": vm.get("status") or "unknown",
            "uptime": vm.get("uptime"),
            "mem": vm.get("mem"),
            "maxmem": vm.get("maxmem"),
            "ip": None,
            "ip_source": "none",
            "ip_stale": False,
            "last_seen": None,
            "checks": {},
        }
        key = (guest["site"], guest["vmid"])
        old = self.previous.get(key) or {}

        if guest["state"] == "running":
            try:
                ip = agent_ip(
                    endpoint["url"], token, vm.get("node"), guest["vmid"], timeout
                )
            except AuthError:
                raise
            except EndpointError as exc:
                log.debug("%s/%s agent: %s", guest["site"], guest["vmid"], exc)
                ip = None
            if ip:
                guest["ip"] = ip
                guest["ip_source"] = "agent"
                guest["last_seen"] = iso()
                guest["checks"] = self.guest_checks(guest, ip, old, timeout)
                return guest

        # stopped, agent silent, or no address yet: keep the last known one
        if old.get("ip"):
            guest["ip"] = old["ip"]
            guest["ip_source"] = old.get("ip_source") or "cached"
            guest["ip_stale"] = True
            guest["last_seen"] = old.get("last_seen")
        return guest

    def guest_checks(self, guest, ip, old, timeout):
        """Probe the guest.  Client VNC is only probed every Nth pass: each
        probe appears in the guest's x11vnc log, and the answer rarely changes."""
        if guest["role"] != "client":
            return probe_checks(guest["role"], ip, self.conf, timeout)
        every = max(1, int(self.conf.get("VNC_PROBE_EVERY", "6")))
        cached = old.get("checks") or {}
        if self.cycle_no % every == 0 or "vnc" not in cached:
            return probe_checks(guest["role"], ip, self.conf, timeout)
        return dict(cached)

    def annotate(self, guests):
        """Flag duplicate addresses within one site (flat LAN, DHCP pool)."""
        by_site = {}
        for guest in guests:
            if guest.get("ip") and guest.get("state") == "running":
                by_site.setdefault(guest["site"], {}).setdefault(guest["ip"], []).append(guest)
        for groups in by_site.values():
            for group in groups.values():
                if len(group) < 2:
                    continue
                labels = ", ".join(sorted(g["name"] for g in group))
                for guest in group:
                    guest["conflict"] = labels
        return guests

    def build_warnings(self, endpoints_out, guests, complete):
        warnings = []
        for item in endpoints_out:
            if not item["ok"]:
                warnings.append(
                    {
                        "severity": "error",
                        "text": f"{item['label']}: endpoint unreachable - {item['error']}",
                    }
                )
        if not complete:
            warnings.append(
                {
                    "severity": "warn",
                    "text": "this pass was incomplete; some values may be stale",
                }
            )
        seen_conflicts = set()
        for guest in guests:
            if guest["state"] != "running":
                warnings.append(
                    {"severity": "warn", "text": f"{guest['name']} is {guest['state']}"}
                )
            elif not guest.get("ip"):
                warnings.append(
                    {"severity": "warn", "text": f"{guest['name']}: no IP address yet"}
                )
            conflict = guest.get("conflict")
            if conflict and conflict not in seen_conflicts:
                seen_conflicts.add(conflict)
                warnings.append(
                    {
                        "severity": "error",
                        "text": f"IP conflict on {guest['ip']}: {conflict}",
                    }
                )
            if (
                guest["state"] == "running"
                and guest["role"] == "ebs"
                and guest.get("ip")
                and guest["checks"].get("apps") != 302
            ):
                code = guest["checks"].get("apps")
                warnings.append(
                    {
                        "severity": "warn",
                        "text": f"{guest['name']}: AppsLogin returned "
                        f"{code if code is not None else 'no answer'}",
                    }
                )
        return warnings

    def log_changes(self, guests, endpoints_out):
        if self.first_pass:
            log.info(
                "first pass: %d guests, %d endpoints",
                len(guests),
                len(endpoints_out),
            )
            return
        current = {(g["site"], g["vmid"]): g for g in guests}
        for key, guest in current.items():
            old = self.previous.get(key)
            if old is None:
                log.info("%s/%s %s: new (%s)", key[0], key[1], guest["name"], guest["state"])
                continue
            new_sig = (
                guest["state"],
                guest.get("ip"),
                tuple(sorted((guest.get("checks") or {}).items())),
            )
            old_sig = (
                old["state"],
                old.get("ip"),
                tuple(sorted((old.get("checks") or {}).items())),
            )
            if new_sig != old_sig:
                log.info(
                    "%s/%s %s: %s ip=%s checks=%s",
                    key[0],
                    key[1],
                    guest["name"],
                    guest["state"],
                    guest.get("ip") or "-",
                    guest.get("checks") or "-",
                )
        for key in set(self.previous) - set(current):
            log.info("%s/%s gone", key[0], key[1])


def main(argv):
    once = "--once" in argv or "--dump" in argv
    dump = "--dump" in argv

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,   # keep stdout clean for --dump / --once
    )

    conf = read_conf(DEFAULT_CONF)
    collector = Collector(conf)

    if not collector.endpoints:
        log.error("no endpoints configured in %s", conf["ENDPOINTS_FILE"])
        return 1

    if once:
        state, auth_blocked = collector.pass_once()
        if dump:
            json.dump(state, sys.stdout, indent=1)
            sys.stdout.write("\n")
        else:
            print(
                f"{len(state['guests'])} guests from {len(state['endpoints'])} endpoint(s) "
                f"in {state['cycle_ms']} ms, {len(state['warnings'])} warning(s)"
            )
        return 2 if auth_blocked else 0

    def stop(_signum, _frame):
        STOP.set()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    interval = float(conf["COLLECT_INTERVAL"])
    while not STOP.is_set():
        try:
            _, auth_blocked = collector.pass_once()
        except AuthError as exc:
            log.error("authentication failed: %s", exc)
            auth_blocked = True
        except Exception:  # noqa: BLE001 - keep the daemon alive
            log.exception("collector pass failed")
            auth_blocked = False
        STOP.wait(60 if auth_blocked else interval)
    log.info("stopping")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
