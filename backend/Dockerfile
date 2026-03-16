FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Ensure data directory exists (Render mounts persistent disk here)
RUN mkdir -p /app/data

# Render sets PORT dynamically; default 8443 for local Docker
ENV PORT=8443
EXPOSE ${PORT}

CMD uvicorn main:app --host 0.0.0.0 --port ${PORT}
