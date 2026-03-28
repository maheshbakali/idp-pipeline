FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY src/python_pipeline /app/src/python_pipeline

WORKDIR /app/src/python_pipeline

ENTRYPOINT ["python", "main.py"]

