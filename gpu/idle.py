"""Idle shutdown. The VM stops itself, so nothing else has to remember to."""

import subprocess
import threading
import time

import config

CHECK_SECONDS = 30

_last = time.monotonic()


def touch() -> None:
    global _last
    _last = time.monotonic()


def idle_seconds() -> float:
    return time.monotonic() - _last


def watch() -> None:
    """Counts from boot, so a VM nobody talks to still stops itself.

    The server runs as root from the boot script, so no sudo.
    """
    while idle_seconds() < config.IDLE_MINUTES * 60:
        time.sleep(CHECK_SECONDS)
    subprocess.run(["shutdown", "-h", "now"])


def start() -> None:
    threading.Thread(target=watch, daemon=True).start()
