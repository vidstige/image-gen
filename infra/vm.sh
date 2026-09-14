#!/usr/bin/env bash
# Create the GPU VM. No public IP: only the control plane can reach it.
set -euo pipefail
cd "$(dirname "$0")" && source env.sh

test -n "${HF_TOKEN:-}" || { echo "set HF_TOKEN (gated weights)"; exit 1; }

gcloud compute instances create $VM --project=$PROJECT --zone=$ZONE \
  --machine-type=$VM_TYPE --accelerator=$ACCELERATOR \
  --image-family=pytorch-latest-gpu \
  --image-project=deeplearning-platform-release \
  --boot-disk-size=${DISK_GB}GB --boot-disk-type=pd-balanced \
  --maintenance-policy=TERMINATE --no-restart-on-failure \
  --subnet=$SUBNET --no-address \
  --scopes=cloud-platform \
  --service-account=imgen-gpu@$PROJECT.iam.gserviceaccount.com \
  --metadata=install-nvidia-driver=True,hf-token=$HF_TOKEN \
  --metadata-from-file=startup-script=startup.sh

gcloud compute instances add-iam-policy-binding $VM --zone=$ZONE \
  --member=serviceAccount:imgen-control@$PROJECT.iam.gserviceaccount.com \
  --role=projects/$PROJECT/roles/vmPower
