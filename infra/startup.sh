#!/usr/bin/env bash
# Runs on every boot. Installs whatever is missing, then serves.
# Everything it builds lives on the boot disk, so a VM that is stopped
# and started again — or preempted — comes back in under a minute.
set -euo pipefail

# Blackwell needs the R580 branch and its OPEN kernel module. The
# proprietary module loads and then refuses the device, and the kernel is
# built with gcc-12, so the module has to be too.
DRIVER=https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU19.6/NVIDIA-Linux-x86_64-580.178.04-grid.run
VENV=/opt/venv
SRC=/opt/imgen
DEPS=/opt/.deps
export HF_HOME=/opt/hf

# Which bucket holds the code is the one thing that cannot come from the
# code; vm.sh puts it in instance metadata. The rest is in the .env that
# ships with the source, which config.py reads.
CODE=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/code-bucket)

mkdir -p $HF_HOME

if ! nvidia-smi >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq gcc gcc-12 make python3-venv "linux-headers-$(uname -r)"
  curl -sS -o /tmp/grid.run "$DRIVER"
  CC=gcc-12 bash /tmp/grid.run --silent --kernel-module-type=open
  modprobe nvidia
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

# Emptied first, so what runs is exactly what was shipped and a file
# that has been renamed or deleted does not linger to shadow it.
rm -rf $SRC && mkdir -p $SRC
gcloud storage cat "gs://$CODE/src.tar.gz" | tar xz -C $SRC
cd $SRC

[ -d $VENV ] || python3 -m venv $VENV
[ -f $DEPS ] || { $VENV/bin/pip install -q -r gpu/requirements-gpu.txt && touch $DEPS; }

# Weights land on the disk, pinned. Only the first boot pays for this.
PYTHONPATH=$SRC $VENV/bin/python - <<'PY'
import config
from huggingface_hub import snapshot_download
snapshot_download(config.MODEL, revision=config.MODEL_REVISION, max_workers=16)
PY

exec env PYTHONPATH=$SRC $VENV/bin/python gpu/serve.py
