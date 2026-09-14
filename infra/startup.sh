#!/usr/bin/env bash
# Runs on every boot of the GPU VM. Installs deps once, then serves.
set -euo pipefail

CODE=your-project-code
meta() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/$1"
}

export HF_HOME=/opt/hf
export HF_TOKEN=$(meta attributes/hf-token || true)

mkdir -p /opt/imgen $HF_HOME
gcloud storage cp "gs://$CODE/src.tar.gz" - | tar xz -C /opt/imgen

if [ ! -f /opt/imgen/.deps ]; then
  /opt/conda/bin/pip install -r /opt/imgen/requirements-gpu.txt
  touch /opt/imgen/.deps
fi

# Weights land on the local disk, pinned; boots after the first are fast.
/opt/conda/bin/python - <<'PY'
import config
from huggingface_hub import snapshot_download
snapshot_download(config.MODEL, revision=config.MODEL_REVISION)
PY

cd /opt/imgen && exec /opt/conda/bin/python serve.py
