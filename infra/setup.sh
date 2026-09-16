#!/usr/bin/env bash
# One-time project setup: network, buckets, service accounts, budget.
set -euo pipefail
cd "$(dirname "$0")" && source env.sh

gcloud config set project $PROJECT

gcloud services enable compute.googleapis.com run.googleapis.com \
  storage.googleapis.com iap.googleapis.com iam.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com \
  billingbudgets.googleapis.com cloudresourcemanager.googleapis.com

gcloud compute networks create $NETWORK --subnet-mode=custom
gcloud compute networks subnets create $SUBNET \
  --network=$NETWORK --region=$REGION --range=10.8.0.0/24 \
  --enable-private-ip-google-access

# The GPU VM has no public IP but still has to reach apt and the weights,
# so egress goes through NAT.
gcloud compute routers create imgen-nat --network=$NETWORK --region=$REGION
gcloud compute routers nats create imgen-nat --router=imgen-nat \
  --region=$REGION --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges

# SSH to a VM with no public IP goes through IAP's TCP forwarder.
gcloud compute firewall-rules create iap-ssh \
  --network=$NETWORK --allow=tcp:22 --source-ranges=35.235.240.0/20
gcloud compute firewall-rules create control-to-gpu \
  --network=$NETWORK --allow=tcp:$PORT --source-ranges=10.8.0.0/24

gcloud storage buckets create gs://$BUCKET --location=$REGION \
  --uniform-bucket-level-access
gcloud storage buckets create gs://$CODE --location=$REGION \
  --uniform-bucket-level-access

gcloud iam service-accounts create imgen-gpu --display-name="GPU VM"
gcloud iam service-accounts create imgen-control --display-name="Control plane"

gpu=imgen-gpu@$PROJECT.iam.gserviceaccount.com
control=imgen-control@$PROJECT.iam.gserviceaccount.com

gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:$gpu --role=roles/storage.objectAdmin
gcloud storage buckets add-iam-policy-binding gs://$CODE \
  --member=serviceAccount:$gpu --role=roles/storage.objectViewer
# The front end lists and serves images, and deletes them on request.
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:$control --role=roles/storage.objectUser

# The predefined roles that can start and stop an instance grant far more
# than that, so use a custom role bound to the one instance.
gcloud iam roles create vmPower --project=$PROJECT \
  --title="Start and stop one VM" \
  --permissions=compute.instances.start,compute.instances.stop,compute.instances.get

billing=$(gcloud billing projects describe $PROJECT \
  --format="value(billingAccountName)")
gcloud billing budgets create --billing-account=${billing##*/} \
  --display-name="imgen" --budget-amount=$BUDGET \
  --filter-projects="projects/$(gcloud projects describe $PROJECT --format='value(projectNumber)')" \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0
