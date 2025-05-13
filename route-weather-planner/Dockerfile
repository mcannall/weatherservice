FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Environment variables
ENV API_URL=http://weather-api:80
ENV PYTHONUNBUFFERED=1
ENV FLASK_APP=wsgi.py
ENV FLASK_ENV=production
ENV FLASK_DEBUG=0
ENV FLASK_RUN_FROM_CLI=false
ENV WERKZEUG_RUN_MAIN=false
ENV GOOGLE_MAPS_API_KEY=""

EXPOSE 5000

# Remove flask command and ensure only gunicorn is available
RUN rm -f /usr/local/bin/flask && \
    echo '#!/bin/sh' > /usr/local/bin/start-server && \
    echo 'gunicorn --workers=4 --bind=0.0.0.0:5000 --access-logfile=- --error-logfile=- --log-level=info --preload wsgi:app' >> /usr/local/bin/start-server && \
    chmod +x /usr/local/bin/start-server

# Use a simple entrypoint that only runs our start script
ENTRYPOINT ["/usr/local/bin/start-server"] 