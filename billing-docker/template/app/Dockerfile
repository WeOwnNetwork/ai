FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Non-root (DS002): uid 1000 matches the fleet convention; staticfiles must be
# writable for collectstatic at startup.
RUN chmod +x /app/start.sh \
    && useradd -m -u 1000 appuser \
    && mkdir -p /app/staticfiles \
    && chown -R appuser:appuser /app
USER appuser
EXPOSE 8000
HEALTHCHECK --start-period=45s --interval=15s --timeout=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/healthz', timeout=5).status==200 else 1)"
# entrypoint is the Infisical wrapper (bind-mounted by compose); command = start.sh
CMD ["/app/start.sh"]
