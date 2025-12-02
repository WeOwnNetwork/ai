FROM python:3.11-slim

WORKDIR /app

# Copy application files
COPY pyproject.toml ./
COPY app.py db.py persona_client.py ./

# Install Python dependencies (matches pyproject.toml)
RUN pip install --no-cache-dir \
    streamlit>=1.30.0 \
    requests>=2.31.0 \
    mysql-connector-python>=8.2.0 \
    python-dotenv>=1.0.0 \
    pandas>=2.0.0

EXPOSE 8501

ENV PYTHONUNBUFFERED=1

CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0", "--server.port=8501"]
