FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV API_URL=http://weather-api:80

EXPOSE 5000

# Use Gunicorn with 4 worker processes
CMD ["gunicorn", "--workers=4", "--bind=0.0.0.0:5000", "--access-logfile=-", "--error-logfile=-", "--log-level=info", "app:app"] 