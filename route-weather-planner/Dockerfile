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
ENV GUNICORN_CMD_ARGS="--preload --workers=4 --bind=0.0.0.0:5000 --access-logfile=- --error-logfile=- --log-level=info"

EXPOSE 5000

# Create a script to ensure Gunicorn is used
RUN echo '#!/bin/bash\n\
if [[ "$1" == "flask" || "$1" == "python" ]]; then\n\
    echo "Error: Direct Flask/Python execution is disabled. Use Gunicorn."\n\
    exit 1\n\
fi\n\
exec "$@"\n\
' > /usr/local/bin/entrypoint.sh \
&& chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["gunicorn", "wsgi:app"] 