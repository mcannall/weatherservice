from app import app

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)

# Only expose the app variable, don't run the development server
# Gunicorn will use this app variable directly 