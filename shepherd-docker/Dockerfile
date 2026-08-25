# Shepherd POC HTTP surface (PRJ-435).
# Upstream has no published web image; this wraps pinned shepherd-ai + a stdlib
# health/status server on :8080. MOCK_PROVIDER=true keeps the offline lane.

FROM python:3.12.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    SHEPHERD_PORT=8080 \
    TRACES_DIR=/data/traces

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 shepherd \
    && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin shepherd \
    && mkdir -p /data/traces /app \
    && chown -R shepherd:shepherd /data /app

WORKDIR /app

# Pin the public wheel (deterministic/offline extra is the default install).
RUN pip install --no-cache-dir "shepherd-ai==0.3.0"

COPY --chown=shepherd:shepherd app/server.py /app/server.py

USER 1000:1000

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=3).read()"]

CMD ["python", "/app/server.py"]
