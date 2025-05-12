from flask import Flask, render_template, request, jsonify
import requests
from geopy.geocoders import Nominatim
from geopy.distance import geodesic
import os
from dotenv import load_dotenv
import math
import googlemaps

load_dotenv()

app = Flask(__name__)

# Configuration
WEATHER_API_URL = os.getenv('WEATHER_API_URL', 'http://api:80')
GOOGLE_MAPS_API_KEY = os.getenv('GOOGLE_MAPS_API_KEY')
gmaps = googlemaps.Client(key=GOOGLE_MAPS_API_KEY)
geolocator = Nominatim(
    user_agent="route_weather_planner",
    timeout=10  # Increase timeout to 10 seconds
)

# Get API URL from environment variable, default to localhost for development
API_URL = os.getenv('API_URL', 'http://localhost:30080')

def get_coordinates_and_zip(address):
    """Get coordinates and zip code for an address using Google Maps API"""
    try:
        # First try Google Geocoding
        geocode_result = gmaps.geocode(address)
        if not geocode_result:
            return None, None, f"Could not find location for address: {address}"
        
        location = geocode_result[0]
        lat = location['geometry']['location']['lat']
        lon = location['geometry']['location']['lng']
        
        # Get zip code from Google's result
        zip_code = None
        for component in location['address_components']:
            if 'postal_code' in component['types']:
                zip_code = component['long_name']
                break
        
        # If no zip code found in Google's result, try Nominatim as backup
        if not zip_code:
            try:
                nominatim_location = geolocator.reverse(f"{lat}, {lon}", timeout=10)
                if nominatim_location and nominatim_location.raw.get('address', {}).get('postcode'):
                    zip_code = nominatim_location.raw['address']['postcode']
            except Exception:
                pass  # Silently fail and continue without zip code
        
        return lat, lon, zip_code
    except Exception as e:
        return None, None, f"Error finding location for address {address}: {str(e)}"

def get_zip_code(lat, lon):
    """Get zip code from coordinates using Google Maps API first, then Nominatim as backup"""
    try:
        # Try Google Geocoding first
        reverse_result = gmaps.reverse_geocode((lat, lon))
        if reverse_result:
            for component in reverse_result[0]['address_components']:
                if 'postal_code' in component['types']:
                    return component['long_name']
        
        # If Google doesn't return a zip code, try Nominatim as backup
        location = geolocator.reverse(f"{lat}, {lon}", timeout=10)
        if location and location.raw.get('address', {}).get('postcode'):
            return location.raw['address']['postcode']
        return None
    except Exception as e:
        print(f"Error getting zip code for coordinates ({lat}, {lon}): {str(e)}")
        return None

def get_weather_data(lat_or_zip, lon=None):
    """Get weather data from our weather service"""
    try:
        if lon is None:
            # If only one argument is provided, assume it's a zip code
            zip_code = lat_or_zip
        else:
            # If two arguments are provided, get zip code from coordinates
            zip_code = get_zip_code(lat_or_zip, lon)
            if not zip_code:
                print(f"Could not find zip code for coordinates: ({lat_or_zip}, {lon})")
                return None

        try:
            response = requests.get(f"{WEATHER_API_URL}/weather/{zip_code}", timeout=5)
            response.raise_for_status()
            weather_data = response.json()
            weather_data['zip_code'] = zip_code  # Add zip code to the response
            return weather_data
        except requests.RequestException as e:
            print(f"Error fetching weather data for zip {zip_code}: {e}")
            # Return a minimal weather object with the zip code
            return {
                'zip_code': zip_code,
                'temperatureC': None,
                'temperatureF': None,
                'summary': 'Weather service unavailable'
            }
    except Exception as e:
        print(f"Error in get_weather_data: {str(e)}")
        return None

def calculate_intermediate_points(start_lat, start_lon, end_lat, end_lon, interval_distance=10):
    """Calculate intermediate points between two coordinates"""
    # Calculate total distance
    distance = geodesic((start_lat, start_lon), (end_lat, end_lon)).miles
    
    # Calculate number of points needed based on interval
    num_points = max(2, math.ceil(distance / interval_distance))
    
    points = []
    for i in range(num_points + 1):
        fraction = i / num_points
        lat = start_lat + (end_lat - start_lat) * fraction
        lon = start_lon + (end_lon - start_lon) * fraction
        points.append({
            'lat': lat,
            'lon': lon
        })
    return points

def get_route_points(coordinates, interval_distance=10):
    """Get all points along the route including intermediate points"""
    all_points = []
    
    # Add first point
    all_points.append({
        'lat': coordinates[0]['lat'],
        'lon': coordinates[0]['lon'],
        'address': coordinates[0]['address'],
        'is_stop': True
    })
    
    # Add intermediate points between each pair of coordinates
    for i in range(len(coordinates) - 1):
        start = coordinates[i]
        end = coordinates[i + 1]
        
        # Calculate distance between points
        distance = geodesic(
            (start['lat'], start['lon']),
            (end['lat'], end['lon'])
        ).miles
        
        # Number of intermediate points based on distance and interval
        # One point every interval_distance miles, minimum 2 points
        num_points = max(2, math.ceil(distance / interval_distance))
        
        # Get intermediate points
        intermediate_points = calculate_intermediate_points(
            start['lat'], start['lon'],
            end['lat'], end['lon'],
            num_points
        )
        
        # Add intermediate points (skip first and last as they're the stops)
        for point in intermediate_points[1:-1]:
            all_points.append({
                'lat': point['lat'],
                'lon': point['lon'],
                'is_stop': False
            })
        
        # Add the end point
        all_points.append({
            'lat': end['lat'],
            'lon': end['lon'],
            'address': end['address'],
            'is_stop': True
        })
    
    return all_points

@app.route('/')
def index():
    return render_template('index.html', google_maps_api_key=GOOGLE_MAPS_API_KEY)

@app.route('/get_route_weather', methods=['POST'])
def get_route_weather():
    try:
        data = request.get_json()
        addresses = data.get('addresses', [])
        interval_distance = data.get('interval_distance', 10)
        preferences = data.get('preferences', {})
        
        if len(addresses) < 2:
            return jsonify({'error': 'At least two addresses are required'}), 400
            
        if interval_distance < 1 or interval_distance > 100:
            return jsonify({'error': 'Interval distance must be between 1 and 100 miles'}), 400

        # Get coordinates for each address
        coordinates = []
        for address in addresses:
            lat, lon, result = get_coordinates_and_zip(address)
            if lat is None or lon is None:
                return jsonify({'error': result}), 400
            
            coordinates.append({
                'lat': lat,
                'lon': lon,
                'address': address
            })

        # First, get the optimized route using Google Directions API
        try:
            # Build the avoid list based on preferences
            avoid_list = []
            if preferences.get('avoid_highways'):
                avoid_list.append('highways')
            if preferences.get('avoid_tolls'):
                avoid_list.append('tolls')
            
            directions_result = gmaps.directions(
                origin=coordinates[0]['address'],
                destination=coordinates[-1]['address'],
                waypoints=[coord['address'] for coord in coordinates[1:-1]],
                optimize_waypoints=preferences.get('optimize_route', False),
                mode="driving",
                avoid=avoid_list if avoid_list else None,
                alternatives=False
            )
            
            if not directions_result:
                return jsonify({'error': 'Could not calculate route'}), 400

            # Extract the route path points
            route_path = []
            last_point = None
            
            # Add the origin
            route_path.append({
                'lat': coordinates[0]['lat'],
                'lon': coordinates[0]['lon'],
                'address': coordinates[0]['address'],
                'is_stop': True
            })
            last_point = route_path[0]

            # Add points from each leg of the journey
            for leg in directions_result[0]['legs']:
                for step in leg['steps']:
                    current_point = {
                        'lat': step['end_location']['lat'],
                        'lon': step['end_location']['lng'],
                        'address': step['html_instructions'],
                        'is_stop': False
                    }
                    
                    # Calculate distance from last point
                    if last_point:
                        distance = geodesic(
                            (last_point['lat'], last_point['lon']),
                            (current_point['lat'], current_point['lon'])
                        ).miles
                        
                        # Only add point if it's far enough from the last point
                        if distance >= interval_distance:
                            route_path.append(current_point)
                            last_point = current_point

            # Add the final destination if it's not already included
            if route_path[-1]['lat'] != coordinates[-1]['lat'] or route_path[-1]['lon'] != coordinates[-1]['lon']:
                route_path.append({
                    'lat': coordinates[-1]['lat'],
                    'lon': coordinates[-1]['lon'],
                    'address': coordinates[-1]['address'],
                    'is_stop': True
                })

            # Now add weather data for all points
            route_with_weather = []
            weather_service_available = True

            for point in route_path:
                if weather_service_available:
                    weather = get_weather_data(point['lat'], point['lon'])
                    if weather and weather.get('temperatureC') is None:
                        weather_service_available = False
                else:
                    weather = {
                        'zip_code': get_zip_code(point['lat'], point['lon']),
                        'temperatureC': None,
                        'temperatureF': None,
                        'summary': 'Weather service unavailable'
                    }

                route_with_weather.append({
                    'lat': point['lat'],
                    'lon': point['lon'],
                    'address': point['address'],
                    'is_stop': point['is_stop'],
                    'weather': weather,
                    'zip_code': weather['zip_code'] if weather else None
                })

            return jsonify({'route': route_with_weather})

        except Exception as e:
            print(f"Error calculating route: {str(e)}")
            return jsonify({'error': f'Error calculating route: {str(e)}'}), 500

    except Exception as e:
        print(f"Error in get_route_weather: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/weather/<zip_code>')
def get_weather(zip_code):
    try:
        # Call the API service
        response = requests.get(f"{API_URL}/weather/{zip_code}")
        response.raise_for_status()
        return jsonify(response.json())
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Error fetching weather data: {str(e)}"}), 500

@app.route('/test-weather-connection')
def test_weather_connection():
    try:
        # Test with a known zip code
        weather_data = get_weather_data('90210')
        if weather_data:
            return jsonify({
                'status': 'success',
                'message': 'Successfully connected to weather API',
                'weather_data': weather_data,
                'api_url': WEATHER_API_URL
            })
        else:
            return jsonify({
                'status': 'error',
                'message': 'Failed to get weather data',
                'api_url': WEATHER_API_URL
            }), 500
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Error: {str(e)}',
            'api_url': WEATHER_API_URL
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000) 