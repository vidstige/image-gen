#!/usr/bin/env bash
# Ship the source the GPU VM runs, .env included: the box needs the same
# identifiers, and one mechanism beats two.
set -euo pipefail
cd "$(dirname "$0")/.." && source infra/env.sh

tar cz config.py params.py storage.py .env gpu \
  | gcloud storage cp - gs://$CODE/src.tar.gz

state=$(gcloud compute instances describe $VM --zone=$ZONE \
  --format='value(status)' 2>/dev/null || echo NONE)
[ "$state" = "RUNNING" ] && gcloud compute instances reset $VM --zone=$ZONE
