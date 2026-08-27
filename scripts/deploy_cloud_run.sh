#!/usr/bin/env bash
set -euo pipefail

echo "Direct source deployment is disabled." >&2
echo "Verify the single regional trigger first:" >&2
echo "  gcloud builds triggers list --project=tsumoai --region=asia-northeast1" >&2
echo "Then run the reviewed cloudbuild.yaml trigger:" >&2
echo "  gcloud builds triggers run tsumoai-deploy --project=tsumoai --region=asia-northeast1 --branch=main" >&2
exit 1
