# Route Weather Planner

A web application that helps plan routes and shows weather conditions along the way. The application integrates with Google Maps for route planning and uses a weather service to provide weather information for locations along the route.

## Features

- Plan routes with multiple stops
- View route on Google Maps
- Get weather information for each stop
- Responsive design for desktop and mobile

## Prerequisites

- Docker
- Kubernetes cluster (e.g., kind)
- Google Maps API key
- Access to the weather service API

## Setup

1. Clone the repository
2. Copy `.env.template` to `.env` and add your Google Maps API key:
   ```
   GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
   WEATHER_API_URL=http://api:80
   ```

3. Build the Docker image:
   ```bash
   docker build -t route-weather-planner:latest .
   ```

4. Create the Kubernetes secret for the Google Maps API key:
   ```bash
   kubectl create secret generic route-weather-planner-secrets \
     --from-literal=GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
   ```

5. Deploy to Kubernetes:
   ```bash
   kubectl apply -f k8s/
   ```

6. Port forward to access the application:
   ```bash
   kubectl port-forward service/route-weather-planner 8080:80
   ```

7. Access the application at http://localhost:8080

## Usage

1. Enter your starting address
2. Click "Add Stop" to add more destinations
3. Click "Plan Route" to see the route and weather information
4. The map will show the route with markers for each stop
5. Weather information will be displayed for each stop

## Development

To run the application locally for development:

1. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Run the Flask application:
   ```bash
   python app.py
   ```

3. Access the application at http://localhost:5000 