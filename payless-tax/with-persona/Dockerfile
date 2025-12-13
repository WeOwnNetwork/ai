
FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir --upgrade pip

COPY pyproject.toml /app/pyproject.toml

RUN pip install --no-cache-dir streamlit==1.39.0 requests==2.32.3 stripe==14.0.1 mysql-connector-python==9.0.0 python-dotenv==1.0.1 pandas==2.2.3

COPY . /app

EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
