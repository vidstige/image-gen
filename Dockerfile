# The control plane only. The GPU box runs from source on the VM.
FROM python:3.12-slim

WORKDIR /app
COPY requirements-control.txt .
RUN pip install --no-cache-dir -r requirements-control.txt

COPY config.py params.py storage.py ./
COPY control/ ./
COPY tests/test_page.py ./tests/

# The identifiers are supplied by Cloud Run at run time; the smoke test
# only needs the app to import and the page to render.
RUN pip install --no-cache-dir pytest==8.4.2 \
 && IMGEN_PROJECT=smoke IMGEN_BUCKET=smoke python -m pytest -q tests/test_page.py

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 900 main:app
