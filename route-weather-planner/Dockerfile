FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV API_URL=http://weather-api:80
ENV PYTHONUNBUFFERED=1
ENV FLASK_APP=app.py
ENV FLASK_ENV=production
ENV GUNICORN_CMD_ARGS="--workers=4 --bind=0.0.0.0:5000 --access-logfile=- --error-logfile=- --log-level=info"

EXPOSE 5000

# Run Gunicorn directly
ENTRYPOINT ["gunicorn", "app:app"] 