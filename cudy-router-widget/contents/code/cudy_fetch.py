#!/usr/bin/env python3
"""Fetch the Cudy router device list and print ONE JSON line on stdout.

Config comes from the environment (CUDY_URL, CUDY_PASSWORD) so the widget
settings are the single source of truth. The auth token and mDNS salt are
cached between runs, so repeated polls skip the slow mDNS discovery + login.
"""

import contextlib
import json
import math
import os
import sys
from pathlib import Path


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def cache_file():
    base = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(os.path.expanduser("~"), ".cache")
    return Path(base) / "cudy-plasma-widget.json"


def load_cache(url):
    try:
        data = json.loads(cache_file().read_text())
        if data.get("url") == url:
            return data
    except Exception:
        pass
    return {}


def save_cache(url, token, salt):
    try:
        fd = os.open(cache_file(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump({"url": url, "token": token, "salt": salt}, f)
    except Exception:
        pass


def safe(value):
    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        return None if math.isnan(value) or math.isinf(value) else value
    return str(value)


def device_to_dict(d):
    def g(name):
        return safe(getattr(d, name, None))

    return {
        "name": g("hostname") or g("device_name") or g("mac_address") or "unknown",
        "ip": g("ip_address"),
        "mac": g("mac_address"),
        "type": g("connection_type"),
        "signal": g("signal_strength"),
        "down": g("formatted_bandwidth_down"),
        "up": g("formatted_bandwidth_up"),
        "active": g("recently_active"),
    }


def main():
    url = os.environ.get("CUDY_URL", "").strip()
    password = os.environ.get("CUDY_PASSWORD", "")
    if not url or not password:
        emit({"ok": False, "error": "Router URL and password are required"})
        return 1

    # The library (and urllib3) may print/log; keep stdout clean for our JSON.
    with contextlib.redirect_stdout(sys.stderr):
        try:
            import urllib3

            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
            from cudypy import CudyRouter
        except ImportError as e:
            emit({"ok": False, "error": f"Cannot import cudypy ({e}). Set the Python command in settings."})
            return 1

        cache = load_cache(url)
        try:
            router = CudyRouter(
                url,
                password=password,
                auth_token=cache.get("token") or None,
                salt=cache.get("salt") or None,
                timeout=8,
            )
            try:
                devices = router.get_devices()
                token, salt = router.auth_token, router.salt  # close() wipes the token
            finally:
                router.close()
        except Exception as e:  # report anything to the widget instead of crashing
            save_cache(url, None, cache.get("salt"))
            emit({"ok": False, "error": f"{type(e).__name__}: {e}"})
            return 1

    save_cache(url, token, salt)
    emit({"ok": True, "devices": [device_to_dict(d) for d in devices]})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
