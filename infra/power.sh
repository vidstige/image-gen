#!/usr/bin/env bash
# Show or change the GPU VM's power state from the command line.
set -euo pipefail
cd "$(dirname "$0")" && source env.sh
gc="gcloud compute instances"

case "${1:-status}" in
  on)  $gc start $VM --zone=$ZONE --project=$PROJECT ;;
  off) $gc stop $VM --zone=$ZONE --project=$PROJECT ;;
  status)
    $gc describe $VM --zone=$ZONE --project=$PROJECT \
      --format='value(status,lastStartTimestamp)'
    ;;
  *) echo "usage: power.sh [status|on|off]" >&2; exit 1 ;;
esac
