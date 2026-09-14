# The control plane only. The GPU box runs from source on the VM.
FROM python:3.12-slim

WORKDIR /app
COPY requirements-control.txt .
RUN pip install --no-cache-dir -r requirements-control.txt

COPY config.py pipeline.py storage.py ./
COPY control/ ./
COPY tests/test_page.py ./tests/

RUN pip install --no-cache-dir pytest==8.4.2 && python -m pytest -q tests/test_page.py

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 900 main:app
