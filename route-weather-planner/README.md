# Route Weather Planner

A service that provides weather information along a route between two points.

## Features
- Route planning using Google Maps API
- Weather information from OpenWeatherMap
- Multi-architecture support (AMD64/ARM64)
- Production-ready with Gunicorn WSGI server

## Prerequisites

- Python 3.9 or higher
- Docker (for containerized deployment)
- Kubernetes cluster (for production deployment)
- Google Maps API key with the following APIs enabled:
  - Maps JavaScript API
  - Geocoding API
  - Directions API
  - Places API

## Environment Setup

1. Copy the environment template:
   ```bash
   cp .env.template .env
   ```

2. Update the `.env` file with your API keys:
   ```env
   GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
   API_URL=http://localhost:30080  # For local development
   ```

## Local Development

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Run the application:
   ```bash
   flask run
   ```

The application will be available at `http://localhost:5000`

## Docker Deployment

1. Build the Docker image:
   ```bash
   docker build -t route-weather-planner .
   ```

2. Run the container:
   ```bash
   docker run -p 5000:5000 --env-file .env route-weather-planner
   ```

## Kubernetes Deployment

1. Create the required secrets:
   ```bash
   kubectl create secret generic weatherservice-secrets \
     --from-literal=GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
   ```

2. Apply the Kubernetes manifests:
   ```bash
   kubectl apply -f k8s/
   ```

## API Integration

The application communicates with a separate weather API service. In Kubernetes, this is configured through the `API_URL` environment variable, which points to the internal service name `http://api:80`.

For local development, the API service should be running and accessible at `http://localhost:30080`.

## Features

- Route planning with multiple waypoints
- Weather information along the route
- Interactive map display
- Route optimization options
- Weather-based route recommendations

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details. 