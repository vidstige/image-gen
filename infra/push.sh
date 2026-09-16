#!/usr/bin/env bash
# Ship the source the GPU VM runs. Restarts it only if it is up.
set -euo pipefail
cd "$(dirname "$0")/.." && source infra/env.sh

tar cz config.py pipeline.py params_io.py storage.py idle.py \
  serve.py generate.py requirements-gpu.txt .env \
  | gcloud storage cp - gs://$CODE/src.tar.gz

state=$(gcloud compute instances describe $VM --zone=$ZONE \
  --format='value(status)' 2>/dev/null || echo NONE)
[ "$state" = "RUNNING" ] && gcloud compute instances reset $VM --zone=$ZONE
