FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV API_URL=http://weather-api:80

# Create startup script
RUN echo '#!/bin/sh\n\
exec gunicorn --workers=4 --bind=0.0.0.0:5000 --access-logfile=- --error-logfile=- --log-level=info app:app\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 5000

# Use the startup script
CMD ["/app/start.sh"] 