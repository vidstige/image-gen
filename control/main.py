"""Cloud Run front door and control plane (M4).

Serves the page, holds the Google login (IAP guards this URL), starts and
stops the GPU VM, and proxies generation to it over the private VPC.
"""

import json
import time
import urllib.request
from pathlib import Path

from flask import Flask, jsonify, request

import config
import storage
import vm

PAGE = Path(__file__).with_name("index.html")
TIMEOUT = 600
BOOT_SECONDS = 600

app = Flask(__name__)


@app.errorhandler(Exception)
def surface(error: Exception):
    """Cloud errors arrive as generic 500s; the reason belongs on the page."""
    return jsonify(error=type(error).__name__, message=str(error)), 500


def call_vm(path: str, payload: dict | None = None) -> dict:
    url = f"http://{vm.address()}:{config.PORT}{path}"
    data = json.dumps(payload).encode() if payload else None
    headers = {"Content-Type": "application/json"}
    call = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(call, timeout=TIMEOUT) as response:
        return json.load(response)


def defaults() -> dict:
    return {
        "steps": config.STEPS,
        "guidance": config.GUIDANCE,
        "width": config.WIDTH,
        "height": config.HEIGHT,
        "count": config.BATCH,
        "negative_prompt": config.NEGATIVE_PROMPT,
        "model": config.MODEL,
        "cost_per_hour": config.VM_COST_PER_HOUR,
        "idle_minutes": config.IDLE_MINUTES,
    }


@app.get("/")
def page():
    return PAGE.read_text().replace("__DEFAULTS__", json.dumps(defaults()))


def health() -> dict:
    """Empty while the VM is off, or up but still loading the model."""
    if vm.state() != vm.RUNNING:
        return {}
    try:
        return call_vm("/health")
    except OSError:
        return {}


@app.get("/power")
def power():
    return jsonify(state=vm.state(), **health())


@app.post("/power")
def set_power():
    if request.get_json()["on"]:
        vm.start()
    else:
        vm.stop()
    return jsonify(state=vm.state())


def wake() -> None:
    """Start the VM if needed and wait for the model to finish loading."""
    if vm.state() != vm.RUNNING:
        vm.start()
    deadline = time.monotonic() + BOOT_SECONDS
    while time.monotonic() < deadline:
        try:
            call_vm("/health")
            return
        except OSError:
            time.sleep(5)
    raise TimeoutError("GPU VM did not come up")


@app.post("/generate")
def generate():
    wake()
    return jsonify(call_vm("/generate", request.get_json()))


@app.get("/gallery")
def gallery():
    return jsonify(images=storage.gallery())


@app.get("/image/<path:name>")
def image(name: str):
    """Images are served through here, so IAP guards them too."""
    return storage.download(name), 200, {"Content-Type": "image/png"}
