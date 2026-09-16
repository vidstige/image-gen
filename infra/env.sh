# Mirrors config.py. Sourced by every script in this directory.
# Identifiers come from ../.env, which is not committed.
set -a
. "$(dirname "${BASH_SOURCE[0]:-$0}")/../.env"
set +a

PROJECT=$IMGEN_PROJECT
BUCKET=$IMGEN_BUCKET
CODE=$IMGEN_CODE_BUCKET
USER_ACCOUNT=$IMGEN_USER

REGION=europe-west4
ZONE=europe-west4-ai1a
NETWORK=imgen
SUBNET=imgen
VM=imgen-gpu
VM_TYPE=g4-standard-48
ACCELERATOR=type=nvidia-rtx-pro-6000,count=1
DISK_GB=200
SERVICE=imgen
PORT=8000
BUDGET=200SEK   # the billing account is in SEK; ~$20
