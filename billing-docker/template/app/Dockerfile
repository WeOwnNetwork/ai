FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN chmod +x /app/start.sh
EXPOSE 8000
# entrypoint is the Infisical wrapper (bind-mounted by compose); command = start.sh
CMD ["/app/start.sh"]
