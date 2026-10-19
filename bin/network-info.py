#!/usr/bin/env python3
"""
network-info.py - Network and IP telemetry collector for nertwork.network-info Omarchy plugin.
Supports --local, --public, --public-cached, and --all output modes.
"""

import sys
sys.dont_write_bytecode = True
import os
import json
import signal
import subprocess
import urllib.request
import time
import html
import re
import ipaddress

CACHE_DIR = os.path.expanduser("~/.cache/omarchy")
PUBLIC_CACHE_FILE = os.path.join(CACHE_DIR, "network-info-public.json")
MAX_HTTP_RESPONSE_BYTES = 16384
MAX_CACHE_FILE_BYTES = 16384
PUBLIC_ENDPOINT_TIMEOUT_SECS = 3.0
PUBLIC_FETCH_DEADLINE_SECS = 6.0
HELPER_HARD_DEADLINE_SECS = 10


def sanitize_str(val, max_len=128):
    if not isinstance(val, str):
        return ""
    cleaned = re.sub(r"<[^>]*>", "", val)
    cleaned = html.unescape(cleaned)
    cleaned = "".join(ch for ch in cleaned if ch.isprintable() and ch not in '<>"\'`')
    return cleaned.strip()[:max_len]


def validate_ip(val):
    if not val or not isinstance(val, str):
        return ""
    cleaned = val.strip()
    try:
        ipaddress.ip_address(cleaned)
        return cleaned
    except ValueError:
        return ""


def prefix_to_netmask(prefix):
    try:
        prefix = int(prefix)
        if prefix < 0 or prefix > 32:
            return ""
        mask = (0xFFFFFFFF >> (32 - prefix)) << (32 - prefix) if prefix > 0 else 0
        return f"{(mask >> 24) & 0xFF}.{(mask >> 16) & 0xFF}.{(mask >> 8) & 0xFF}.{mask & 0xFF}"
    except Exception:
        return ""


def read_eth_link_details(ifname):
    speed = ""
    duplex = ""
    try:
        speed_path = f"/sys/class/net/{ifname}/speed"
        if os.path.isfile(speed_path):
            with open(speed_path, "r") as sf:
                sp = sf.read().strip()
                if sp and not sp.startswith("-"):
                    speed = f"{sanitize_str(sp, 16)} Mbps"
        dup_path = f"/sys/class/net/{ifname}/duplex"
        if os.path.isfile(dup_path):
            with open(dup_path, "r") as df:
                duplex = sanitize_str(df.read().strip(), 16)
    except Exception:
        pass
    return speed, duplex


def get_local_info():
    info = {
        "connected": False,
        "primary": {},
        "interfaces": [],
        "dns": []
    }

    # 1. Primary route via probe destination (1.1.1.1)
    primary_dev = ""
    primary_src = ""
    primary_gw = ""

    try:
        r = subprocess.run(
            ["ip", "-j", "route", "get", "1.1.1.1"],
            capture_output=True, text=True, timeout=2
        )
        if r.returncode == 0:
            routes = json.loads(r.stdout)
            if routes and isinstance(routes, list):
                rt = routes[0]
                primary_dev = rt.get("dev", "")
                primary_src = rt.get("prefsrc", "")
                primary_gw = rt.get("gateway", "")
    except Exception:
        pass

    # Fallback to default route if probe did not answer
    if not primary_dev:
        try:
            r = subprocess.run(
                ["ip", "-j", "route", "show", "default"],
                capture_output=True, text=True, timeout=2
            )
            if r.returncode == 0:
                routes = json.loads(r.stdout)
                if routes and isinstance(routes, list):
                    rt = routes[0]
                    primary_dev = rt.get("dev", "")
                    primary_src = rt.get("prefsrc", "")
                    primary_gw = rt.get("gateway", "")
        except Exception:
            pass

    if primary_dev:
        info["connected"] = True
        info["primary"] = {
            "iface": sanitize_str(primary_dev, 32),
            "ip": validate_ip(primary_src),
            "gateway": validate_ip(primary_gw),
            "mac": "",
            "type": "other",
            "operstate": "DOWN",
            "prefix": "",
            "netmask": "",
            "ipv6": "",
            "ipv6Prefix": "",
            "speed": "",
            "duplex": "",
            "ssid": "",
            "signal": "",
            "gatewayPingMs": ""
        }

    # 2. Inspect all network interfaces
    try:
        r = subprocess.run(
            ["ip", "-j", "addr", "show"],
            capture_output=True, text=True, timeout=2
        )
        if r.returncode == 0:
            links = json.loads(r.stdout)
            for link in links:
                ifname = link.get("ifname", "")
                if not ifname or ifname == "lo":
                    continue
                mac = sanitize_str(link.get("address", ""), 32)
                operstate = sanitize_str(link.get("operstate", ""), 16)
                flags = link.get("flags", [])

                is_up = "UP" in flags or operstate == "UP"
                normalized_state = "UP" if is_up else (operstate if operstate else "DOWN")

                itype = "other"
                if os.path.isdir(f"/sys/class/net/{ifname}/wireless") or ifname.startswith("wl"):
                    itype = "wifi"
                elif ifname.startswith("en") or ifname.startswith("eth"):
                    itype = "ethernet"
                elif "tailscale" in ifname:
                    itype = "tailscale"
                elif ifname.startswith("tun") or ifname.startswith("wg") or "POINTOPOINT" in flags:
                    itype = "vpn"

                v4_list = []
                v6_list = []
                for a in link.get("addr_info", []):
                    fam = a.get("family")
                    local = a.get("local")
                    prefix = a.get("prefixlen")
                    if fam == "inet" and local:
                        valid_v4 = validate_ip(local)
                        if valid_v4:
                            v4_list.append({
                                "ip": valid_v4,
                                "prefix": sanitize_str(str(prefix if prefix is not None else ""), 8)
                            })
                    elif fam == "inet6" and local:
                        valid_v6 = validate_ip(local)
                        if valid_v6:
                            v6_list.append({
                                "ip": valid_v6,
                                "prefix": sanitize_str(str(prefix if prefix is not None else ""), 8),
                                "scope": sanitize_str(str(a.get("scope", "")), 16)
                            })

                # Select first global / non-link-local IPv6
                chosen_v6 = ""
                chosen_v6_prefix = ""
                for a6 in v6_list:
                    if a6.get("scope") == "global":
                        chosen_v6 = a6["ip"]
                        chosen_v6_prefix = a6["prefix"]
                        break
                if not chosen_v6:
                    for a6 in v6_list:
                        if not a6["ip"].lower().startswith("fe80"):
                            chosen_v6 = a6["ip"]
                            chosen_v6_prefix = a6["prefix"]
                            break

                eth_speed = ""
                eth_duplex = ""
                if itype == "ethernet" and (ifname == primary_dev or normalized_state == "UP"):
                    eth_speed, eth_duplex = read_eth_link_details(ifname)

                wifi_ssid = ""
                if itype == "wifi" and ifname == primary_dev:
                    try:
                        nm_out = subprocess.run(
                            ["nmcli", "-t", "-f", "GENERAL.CONNECTION", "dev", "show", ifname],
                            capture_output=True, text=True, timeout=1
                        )
                        if nm_out.returncode == 0:
                            for line in nm_out.stdout.splitlines():
                                if line.startswith("GENERAL.CONNECTION:"):
                                    raw_ssid = line.split(":", 1)[1].strip()
                                    if raw_ssid and raw_ssid != "--":
                                        wifi_ssid = sanitize_str(raw_ssid, 64)
                                    break
                    except Exception:
                        pass

                if ifname == primary_dev:
                    info["primary"]["mac"] = mac
                    info["primary"]["type"] = itype
                    info["primary"]["operstate"] = normalized_state
                    info["primary"]["ipv6"] = chosen_v6
                    info["primary"]["ipv6Prefix"] = chosen_v6_prefix
                    info["primary"]["speed"] = eth_speed
                    info["primary"]["duplex"] = eth_duplex
                    info["primary"]["ssid"] = wifi_ssid
                    if v4_list:
                        info["primary"]["prefix"] = v4_list[0]["prefix"]
                        info["primary"]["netmask"] = prefix_to_netmask(v4_list[0]["prefix"])
                        if not info["primary"]["ip"]:
                            info["primary"]["ip"] = v4_list[0]["ip"]

                for v4 in v4_list:
                    ip_val = v4["ip"]
                    info["interfaces"].append({
                        "iface": sanitize_str(ifname, 32),
                        "type": itype,
                        "ip": ip_val,
                        "prefix": v4["prefix"],
                        "netmask": prefix_to_netmask(v4["prefix"]),
                        "ipv6": chosen_v6,
                        "ipv6Prefix": chosen_v6_prefix,
                        "mac": mac,
                        "state": normalized_state,
                        "speed": eth_speed,
                        "duplex": eth_duplex,
                        "ssid": wifi_ssid,
                        "isP2P": "POINTOPOINT" in flags,
                        "isPrimary": (ifname == primary_dev and ip_val == info["primary"].get("ip"))
                    })
    except Exception:
        pass

    # 3. Gateway Ping Latency
    gw = info.get("primary", {}).get("gateway")
    if gw:
        try:
            r = subprocess.run(
                ["ping", "-c", "1", "-W", "1", gw],
                capture_output=True, text=True, timeout=1.5
            )
            if r.returncode == 0:
                for line in r.stdout.splitlines():
                    if "time=" in line or "time<" in line:
                        part = line.split("time=")[-1] if "time=" in line else line.split("time<")[-1]
                        info["primary"]["gatewayPingMs"] = sanitize_str(part.split()[0].strip(), 16)
                        break
        except Exception:
            pass

    # 4. DNS Servers via resolvectl
    try:
        r = subprocess.run(
            ["resolvectl", "dns"],
            capture_output=True, text=True, timeout=1.5
        )
        if r.returncode == 0:
            dns_set = set()
            for line in r.stdout.splitlines():
                parts = line.split(":", 1)
                if len(parts) > 1:
                    for s in parts[1].strip().split():
                        # Strip optional interface scope or port suffix if present
                        token = s.split("%")[0].split("#")[0]
                        validated = validate_ip(token)
                        if validated and not validated.startswith("fd") and not validated.startswith("fe80"):
                            dns_set.add(validated)
            info["dns"] = sorted(list(dns_set))
    except Exception:
        pass

    return info


def _alarm_handler(_signum, _frame):
    raise TimeoutError("network-info helper deadline exceeded")


def read_bounded_cache(path, max_bytes=MAX_CACHE_FILE_BYTES):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "rb") as cf:
            raw = cf.read(max_bytes + 1)
        if len(raw) > max_bytes:
            return None
        data = json.loads(raw.decode("utf-8"))
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def fetch_bounded_url(url, headers, deadline, max_bytes=MAX_HTTP_RESPONSE_BYTES):
    remaining = deadline - time.monotonic()
    if remaining <= 0.05:
        raise TimeoutError("public IP transfer deadline exceeded")
    sock_timeout = min(PUBLIC_ENDPOINT_TIMEOUT_SECS, remaining)
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=sock_timeout) as resp:
        cl = resp.headers.get("Content-Length") if hasattr(resp, "headers") and resp.headers else None
        if cl is not None:
            try:
                cl_int = int(cl)
            except ValueError:
                cl_int = 0
            if cl_int > max_bytes:
                raise ValueError("HTTP Content-Length exceeds maximum byte limit")
        chunks = []
        total = 0
        while True:
            rem = deadline - time.monotonic()
            if rem <= 0:
                raise TimeoutError("public IP transfer deadline exceeded")
            try:
                if hasattr(resp, "fp") and resp.fp is not None and hasattr(resp.fp, "raw"):
                    sock = getattr(resp.fp.raw, "_sock", None)
                    if sock is not None:
                        sock.settimeout(min(PUBLIC_ENDPOINT_TIMEOUT_SECS, rem))
            except Exception:
                pass
            read_fn = getattr(resp, "read1", resp.read)
            chunk = read_fn(min(4096, max_bytes + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError("HTTP response exceeds maximum byte limit")
            chunks.append(chunk)
        return b"".join(chunks).decode("utf-8")


def get_public_info(use_cache_fallback=True):
    # Try reading cache if fresh (< 5 minutes)
    now = time.time()
    if use_cache_fallback:
        cached = read_bounded_cache(PUBLIC_CACHE_FILE)
        if cached:
            cached_time = cached.get("_timestamp", 0)
            valid_cached_ip = validate_ip(cached.get("ip", ""))
            if isinstance(cached_time, (int, float)) and now - cached_time < 300 and valid_cached_ip:
                cached["ip"] = valid_cached_ip
                cached["fromCache"] = True
                return cached

    res = {
        "ip": "",
        "hostname": "",
        "city": "",
        "region": "",
        "country": "",
        "org": "",
        "loc": "",
        "status": "offline",
        "_timestamp": now,
        "fromCache": False
    }

    req_headers = {
        "User-Agent": "OmarchyNetworkInfo/1.0",
        "Accept": "application/json"
    }
    deadline = time.monotonic() + PUBLIC_FETCH_DEADLINE_SECS
    prev_handler = None
    try:
        prev_handler = signal.signal(signal.SIGALRM, _alarm_handler)
        signal.setitimer(signal.ITIMER_REAL, PUBLIC_FETCH_DEADLINE_SECS)
    except Exception:
        pass

    try:
        # 1. Primary: ipinfo.io/json
        if time.monotonic() < deadline:
            try:
                body = fetch_bounded_url("https://ipinfo.io/json", req_headers, deadline)
                data = json.loads(body)
                if isinstance(data, dict):
                    ip = validate_ip(data.get("ip"))
                    if ip:
                        res["ip"] = ip
                        res["hostname"] = sanitize_str(data.get("hostname", ""), 128)
                        res["city"] = sanitize_str(data.get("city", ""), 64)
                        res["region"] = sanitize_str(data.get("region", ""), 64)
                        res["country"] = sanitize_str(data.get("country", ""), 64)
                        res["org"] = sanitize_str(data.get("org", ""), 128)
                        res["loc"] = sanitize_str(data.get("loc", ""), 64)
                        res["status"] = "online"
            except Exception:
                pass

        # 2. Fallback: api.ipify.org
        if not res["ip"] and time.monotonic() < deadline:
            try:
                body = fetch_bounded_url("https://api.ipify.org?format=json", req_headers, deadline)
                data = json.loads(body)
                if isinstance(data, dict):
                    ip = validate_ip(data.get("ip"))
                    if ip:
                        res["ip"] = ip
                        res["status"] = "online"
            except Exception:
                pass

        # 3. Fallback: icanhazip.com
        if not res["ip"] and time.monotonic() < deadline:
            try:
                raw_ip = fetch_bounded_url("https://icanhazip.com", {"User-Agent": "OmarchyNetworkInfo/1.0"}, deadline).strip()
                ip = validate_ip(raw_ip)
                if ip:
                    res["ip"] = ip
                    res["status"] = "online"
            except Exception:
                pass
    finally:
        try:
            signal.setitimer(signal.ITIMER_REAL, 0)
            if prev_handler is not None:
                signal.signal(signal.SIGALRM, prev_handler)
        except Exception:
            pass

    # Save cache if successful
    if res["ip"]:
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(PUBLIC_CACHE_FILE, "w") as cf:
                json.dump(res, cf)
        except Exception:
            pass
    elif use_cache_fallback:
        # Stale cache fallback if available
        cached = read_bounded_cache(PUBLIC_CACHE_FILE)
        if cached:
            valid_cached_ip = validate_ip(cached.get("ip", ""))
            if valid_cached_ip:
                cached["ip"] = valid_cached_ip
                cached["fromCache"] = True
                cached["status"] = "stale"
                return cached

    return res


def main():
    try:
        signal.signal(signal.SIGALRM, _alarm_handler)
        signal.alarm(HELPER_HARD_DEADLINE_SECS)
    except Exception:
        pass
    mode = "--local"
    if len(sys.argv) > 1:
        mode = sys.argv[1]

    if mode == "--local":
        print(json.dumps(get_local_info()))
    elif mode == "--public":
        print(json.dumps(get_public_info(use_cache_fallback=False)))
    elif mode == "--public-cached":
        print(json.dumps(get_public_info(use_cache_fallback=True)))
    elif mode == "--all":
        out = {
            "local": get_local_info(),
            "public": get_public_info(use_cache_fallback=True)
        }
        print(json.dumps(out))
    else:
        print(json.dumps(get_local_info()))


if __name__ == "__main__":
    main()
