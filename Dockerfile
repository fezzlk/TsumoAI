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
COPY scripts/evaluate_recognition_set.py ./scripts/evaluate_recognition_set.py
COPY data/recognition_eval_set.jsonl ./data/recognition_eval_set.jsonl
COPY data/eval_images ./data/eval_images

EXPOSE 8080

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
