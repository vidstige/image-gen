#!/usr/bin/env bash
# Create the GPU VM. No public IP: only the control plane can reach it.
# Spot, because on-demand quota for this card is denied and preemption
# costs one user with an idle timer very little. A preempted VM stops
# rather than being deleted, so the weights on its disk survive.
set -euo pipefail
cd "$(dirname "$0")" && source env.sh

test -n "${HF_TOKEN:-}" || { echo "set HF_TOKEN (gated weights)"; exit 1; }

gcloud compute instances create $VM --project=$PROJECT --zone=$ZONE \
  --machine-type=$VM_TYPE --accelerator=$ACCELERATOR \
  --image-family=common-cu129-ubuntu-2204-nvidia-580 \
  --image-project=deeplearning-platform-release \
  --boot-disk-size=${DISK_GB}GB --boot-disk-type=hyperdisk-balanced \
  --maintenance-policy=TERMINATE --no-restart-on-failure \
  --provisioning-model=SPOT --instance-termination-action=STOP \
  --subnet=$SUBNET --no-address \
  --scopes=cloud-platform \
  --service-account=imgen-gpu@$PROJECT.iam.gserviceaccount.com \
  --metadata=install-nvidia-driver=True,hf-token=$HF_TOKEN \
  --metadata-from-file=startup-script=startup.sh

gcloud compute instances add-iam-policy-binding $VM --zone=$ZONE \
  --member=serviceAccount:imgen-control@$PROJECT.iam.gserviceaccount.com \
  --role=projects/$PROJECT/roles/vmPower
