#!/usr/bin/env bash
set -euo pipefail

# Required:
# - gcloud auth/login済み
# - GCP ProjectにCloud Run/Artifact Registry/Cloud Build APIを有効化済み
# - GCS_BUCKET_NAME は feedback 保存先バケット
#
# Optional:
# - OPENAI_API_KEY_SECRET: Secret Manager secret name (default: openai-api-key)
# - OPENAI_MODEL (default: gpt-4o-mini)
# - REGION (default: asia-northeast1)
# - SERVICE_NAME (default: tsumoai-api)
# - SERVICE_ACCOUNT_NAME (default: tsumoai-runner)

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-asia-northeast1}"
SERVICE_NAME="${SERVICE_NAME:-tsumoai-api}"
GCS_BUCKET_NAME="${GCS_BUCKET_NAME:-}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
OPENAI_API_KEY_SECRET="${OPENAI_API_KEY_SECRET:-openai-api-key}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-tsumoai-runner}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "ERROR: PROJECT_ID is required"
  exit 1
fi

if [[ -z "${GCS_BUCKET_NAME}" ]]; then
  echo "ERROR: GCS_BUCKET_NAME is required"
  exit 1
fi

gcloud config set project "${PROJECT_ID}"

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com

if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --display-name "TsumoAI Cloud Run runtime"
fi

gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET_NAME}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/storage.objectCreator" >/dev/null

SECRET_FLAG=()
if gcloud secrets describe "${OPENAI_API_KEY_SECRET}" >/dev/null 2>&1; then
  gcloud secrets add-iam-policy-binding "${OPENAI_API_KEY_SECRET}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" >/dev/null
  SECRET_FLAG+=(--set-secrets "OPENAI_API_KEY=${OPENAI_API_KEY_SECRET}:latest")
else
  echo "WARN: Secret '${OPENAI_API_KEY_SECRET}' not found. OPENAI_API_KEY is not set."
fi

gcloud run deploy "${SERVICE_NAME}" \
  --source . \
  --region "${REGION}" \
  --allow-unauthenticated \
  --service-account "${SERVICE_ACCOUNT_EMAIL}" \
  --set-env-vars "OPENAI_MODEL=${OPENAI_MODEL},GCS_BUCKET_NAME=${GCS_BUCKET_NAME},GCS_FEEDBACK_PREFIX=score-feedback" \
  "${SECRET_FLAG[@]}"

echo "Deployment complete."
