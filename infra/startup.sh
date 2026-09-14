#!/usr/bin/env bash
# Runs on every boot of the GPU VM. Installs what is missing, then serves.
set -euo pipefail

CODE=your-project-code
# Blackwell needs the R580 branch and its OPEN kernel module; the
# proprietary one loads but then refuses the device. The kernel is built
# with gcc-12, so the module has to be too, or the build fails on a flag
# gcc-11 does not know.
DRIVER=https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU19.6/NVIDIA-Linux-x86_64-580.178.04-grid.run

export HF_HOME=/opt/hf
VENV=/opt/venv

mkdir -p /opt/imgen $HF_HOME

if ! nvidia-smi >/dev/null 2>&1; then
  apt-get update
  apt-get install -y gcc gcc-12 make python3-venv "linux-headers-$(uname -r)"
  curl -sS -o /tmp/grid.run "$DRIVER"
  CC=gcc-12 bash /tmp/grid.run --silent --kernel-module-type=open
  modprobe nvidia
  nvidia-smi
fi

gcloud storage cp "gs://$CODE/src.tar.gz" - | tar xz -C /opt/imgen

[ -d $VENV ] || python3 -m venv $VENV

if [ ! -f /opt/imgen/.deps ]; then
  $VENV/bin/pip install -r /opt/imgen/requirements-gpu.txt
  touch /opt/imgen/.deps
fi

# Weights land on the local disk, pinned. The disk survives preemption,
# so only the first boot pays for this.
$VENV/bin/python - <<'PY'
import config
from huggingface_hub import snapshot_download
snapshot_download(config.MODEL, revision=config.MODEL_REVISION)
PY

cd /opt/imgen && exec $VENV/bin/python serve.py
