from app import app

# Only expose the app variable, don't run the development server
# Gunicorn will use this app variable directly 