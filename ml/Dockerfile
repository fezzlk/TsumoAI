FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    tensorflow-cpu==2.15.1 \
    scikit-learn>=1.3 \
    Pillow>=10.0

COPY . .

CMD ["python", "train.py"]
