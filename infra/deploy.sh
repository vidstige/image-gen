#!/usr/bin/env bash
# Build and deploy the control plane, behind Google login via IAP.
set -euo pipefail
cd "$(dirname "$0")/.." && source infra/env.sh

gcloud run deploy $SERVICE --source=. --project=$PROJECT --region=$REGION --quiet \
  --service-account=imgen-control@$PROJECT.iam.gserviceaccount.com \
  --network=$NETWORK --subnet=$SUBNET --vpc-egress=private-ranges-only \
  --no-allow-unauthenticated --iap \
  --cpu=1 --memory=512Mi --min-instances=0 --max-instances=1 --timeout=900

gcloud beta iap web add-iam-policy-binding \
  --resource-type=cloud-run --service=$SERVICE --region=$REGION \
  --member=user:$USER_ACCOUNT --role=roles/iap.httpsResourceAccessor
