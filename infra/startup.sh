#!/usr/bin/env bash
# Runs on every boot. Installs whatever is missing, then serves.
# Everything it builds lives on the boot disk, so a VM that is stopped
# and started again — or preempted — comes back in under a minute.
set -euo pipefail

CODE=gs://your-project-code/src.tar.gz
# Blackwell needs the R580 branch and its OPEN kernel module. The
# proprietary module loads and then refuses the device, and the kernel is
# built with gcc-12, so the module has to be too.
DRIVER=https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU19.6/NVIDIA-Linux-x86_64-580.178.04-grid.run
VENV=/opt/venv
SRC=/opt/imgen
export HF_HOME=/opt/hf

mkdir -p $SRC $HF_HOME

if ! nvidia-smi >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq gcc gcc-12 make python3-venv "linux-headers-$(uname -r)"
  curl -sS -o /tmp/grid.run "$DRIVER"
  CC=gcc-12 bash /tmp/grid.run --silent --kernel-module-type=open
  modprobe nvidia
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

gcloud storage cat $CODE | tar xz -C $SRC
cd $SRC

[ -d $VENV ] || python3 -m venv $VENV
[ -f .deps ] || { $VENV/bin/pip install -q -r requirements-gpu.txt && touch .deps; }

# Weights land on the disk, pinned. Only the first boot pays for this.
$VENV/bin/python - <<'PY'
import config
from huggingface_hub import snapshot_download
snapshot_download(config.MODEL, revision=config.MODEL_REVISION, max_workers=16)
PY

exec $VENV/bin/python serve.py
