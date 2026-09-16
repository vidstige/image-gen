#!/usr/bin/env bash
# Point IAP at an OAuth client and allowlist the account.
#
# The client itself has to be made by hand in the console: OAuth clients
# cannot be created through any API, and the Google-managed client IAP
# would otherwise use only exists for projects inside an organisation.
# Note this is `iap settings set`, not `iap web enable` — the latter does
# not know about Cloud Run.
set -euo pipefail
cd "$(dirname "$0")" && source env.sh

test $# -eq 2 || { echo "usage: iap.sh CLIENT_ID CLIENT_SECRET" >&2; exit 1; }

settings=$(mktemp)
trap 'rm -f "$settings"' EXIT
cat > "$settings" <<YAML
access_settings:
  oauth_settings:
    client_id: $1
    client_secret: $2
YAML

gcloud iap settings set "$settings" --resource-type=cloud-run \
  --region=$REGION --service=$SERVICE --project=$PROJECT

gcloud beta iap web add-iam-policy-binding --resource-type=cloud-run \
  --service=$SERVICE --region=$REGION --project=$PROJECT \
  --member=user:$USER_ACCOUNT --role=roles/iap.httpsResourceAccessor
