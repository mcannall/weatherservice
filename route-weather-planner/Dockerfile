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
ENV GUNICORN_WORKERS=4
ENV GUNICORN_BIND=0.0.0.0:5000
ENV GUNICORN_LOG_LEVEL=info

EXPOSE 5000

# Create a wrapper script that enforces Gunicorn
RUN echo '#!/bin/sh\n\
exec gunicorn \\\n\
    --workers=$GUNICORN_WORKERS \\\n\
    --bind=$GUNICORN_BIND \\\n\
    --log-level=$GUNICORN_LOG_LEVEL \\\n\
    --access-logfile=- \\\n\
    --error-logfile=- \\\n\
    --preload \\\n\
    wsgi:app\n\
' > /usr/local/bin/start.sh \
&& chmod +x /usr/local/bin/start.sh

# Use the wrapper script as the entrypoint
ENTRYPOINT ["/usr/local/bin/start.sh"] 