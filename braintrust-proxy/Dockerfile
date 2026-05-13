FROM python:3.12-slim

WORKDIR /app

# Security: Create non-root user
RUN useradd -m -u 1001 appuser

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app.py .

# Switch to non-root user
USER appuser

EXPOSE 8080

ENV PORT=8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
