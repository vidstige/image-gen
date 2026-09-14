#!/usr/bin/env bash
# Runs on every boot of the GPU VM. Installs what is missing, then serves.
set -euo pipefail

CODE=your-project-code
# The card in the AI zone is presented as a vGPU, which the open kernel
# module in the base image refuses to drive. This is the GRID build.
DRIVER=gs://nvidia-drivers-us-public/GRID/vGPU20.2/NVIDIA-Linux-x86_64-595.91.07-grid.run

meta() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/$1"
}

export HF_HOME=/opt/hf
export HF_TOKEN=$(meta attributes/hf-token || true)

mkdir -p /opt/imgen $HF_HOME

if ! nvidia-smi >/dev/null 2>&1; then
  apt-get update
  apt-get install -y gcc make dkms "linux-headers-$(uname -r)"
  gcloud storage cp "$DRIVER" /tmp/grid.run
  bash /tmp/grid.run --silent --dkms
fi

gcloud storage cp "gs://$CODE/src.tar.gz" - | tar xz -C /opt/imgen

if [ ! -f /opt/imgen/.deps ]; then
  /opt/conda/bin/pip install -r /opt/imgen/requirements-gpu.txt
  touch /opt/imgen/.deps
fi

# Weights land on the local disk, pinned. The disk survives preemption,
# so only the first boot pays for this.
/opt/conda/bin/python - <<'PY'
import config
from huggingface_hub import snapshot_download
snapshot_download(config.MODEL, revision=config.MODEL_REVISION)
PY

cd /opt/imgen && exec /opt/conda/bin/python serve.py
