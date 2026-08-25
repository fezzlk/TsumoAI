FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY ml/output/tile_classifier.tflite ml/output/labels.txt ./ml/output/

# Used only by the scheduled accuracy-eval Cloud Run Job (scripts/evaluate_recognition_set.py),
# not by the API service itself. Kept in the same image so both the service and the job
# deploy from a single build (see cloudbuild.yaml).
#
# NOTE: data/eval_images/ (the actual eval photos) is gitignored and therefore not
# available to COPY here — Cloud Build clones from git, so a COPY of that path fails
# the build entirely. Until the eval images are sourced from somewhere Cloud Build can
# reach (e.g. GCS) instead of the git tree, `evaluate_recognition_set.py --record` run
# from this image will find no images and record nothing.
COPY scripts/evaluate_recognition_set.py ./scripts/evaluate_recognition_set.py
COPY data/recognition_eval_set.jsonl ./data/recognition_eval_set.jsonl

EXPOSE 8080

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
