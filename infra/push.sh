#!/usr/bin/env bash
# Ship the source the GPU VM runs, then restart it into the new code.
set -euo pipefail
cd "$(dirname "$0")/.." && source infra/env.sh

tar cz config.py pipeline.py params_io.py storage.py idle.py \
  serve.py generate.py requirements-gpu.txt \
  | gcloud storage cp - gs://$CODE/src.tar.gz

gcloud compute instances reset $VM --zone=$ZONE 2>/dev/null || true
