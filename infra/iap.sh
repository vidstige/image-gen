#!/usr/bin/env bash
# Point IAP at an OAuth client and allowlist the account.
#
# The client itself has to be made by hand in the console: OAuth clients
# cannot be created through any API, and the Google-managed client IAP
# would otherwise use only exists for projects inside an organisation.
set -euo pipefail
cd "$(dirname "$0")" && source env.sh

test $# -eq 2 || { echo "usage: iap.sh CLIENT_ID CLIENT_SECRET" >&2; exit 1; }

gcloud iap web enable --resource-type=cloud-run \
  --region=$REGION --service=$SERVICE --project=$PROJECT \
  --oauth2-client-id="$1" --oauth2-client-secret="$2"

gcloud beta iap web add-iam-policy-binding --resource-type=cloud-run \
  --service=$SERVICE --region=$REGION --project=$PROJECT \
  --member=user:$USER_ACCOUNT --role=roles/iap.httpsResourceAccessor
