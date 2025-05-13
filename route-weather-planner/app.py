from flask import Flask, render_template, request, jsonify
import requests
from geopy.geocoders import Nominatim
from geopy.distance import geodesic
import os
from dotenv import load_dotenv
import math
import googlemaps
import logging
import polyline

load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
API_URL = os.getenv('API_URL', 'http://api:80')
GOOGLE_MAPS_API_KEY = os.getenv('GOOGLE_MAPS_API_KEY')
gmaps = googlemaps.Client(key=GOOGLE_MAPS_API_KEY)
geolocator = Nominatim(
    user_agent="route_weather_planner",
    timeout=10  # Increase timeout to 10 seconds
)

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
        logger.debug(f"Attempting to get zip code for coordinates: ({lat}, {lon})")
        # Try Google Geocoding first
        reverse_result = gmaps.reverse_geocode((lat, lon))
        if reverse_result:
            for component in reverse_result[0]['address_components']:
                if 'postal_code' in component['types']:
                    zip_code = component['long_name']
                    logger.debug(f"Found zip code {zip_code} using Google Maps API")
                    return zip_code
            logger.debug("No zip code found in Google Maps API response")
        
        # If Google doesn't return a zip code, try Nominatim as backup
        logger.debug("Attempting to get zip code using Nominatim")
        location = geolocator.reverse(f"{lat}, {lon}", timeout=10)
        if location and location.raw.get('address', {}).get('postcode'):
            zip_code = location.raw['address']['postcode']
            logger.debug(f"Found zip code {zip_code} using Nominatim")
            return zip_code
        logger.warning(f"Could not find zip code for coordinates ({lat}, {lon})")
        return None
    except Exception as e:
        logger.error(f"Error getting zip code for coordinates ({lat}, {lon}): {str(e)}")
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
            response = requests.get(f"{API_URL}/weather/{zip_code}", timeout=5)
            response.raise_for_status()
            weather_data = response.json()
            weather_data['zip_code'] = zip_code  # Add zip code to the response
            weather_data['country'] = weather_data.get('country', 'US')  # Ensure country is set, default to US
            return weather_data
        except requests.RequestException as e:
            print(f"Error fetching weather data for zip {zip_code}: {e}")
            # Return a minimal weather object with the zip code
            return {
                'zip_code': zip_code,
                'temperatureC': None,
                'temperatureF': None,
                'summary': 'Weather service unavailable',
                'country': 'US'  # Default to US for error cases
            }
    except Exception as e:
        print(f"Error in get_weather_data: {str(e)}")
        return None

def calculate_route_points(directions_result, interval_distance):
    """Calculate points along the actual driving route using the detailed path from Google Directions API"""
    points = []
    total_distance = 0  # Track distance in meters
    interval_meters = interval_distance * 1609.34  # Convert miles to meters
    
    logger.debug(f"Calculating route points with interval: {interval_distance} miles ({interval_meters:.0f} meters)")
    
    # Process each leg of the journey
    for leg in directions_result['legs']:
        leg_steps = leg['steps']
        
        for step in leg_steps:
            # Get the detailed path for this step
            path = polyline.decode(step['polyline']['points'])
            step_distance = step['distance']['value']  # Distance in meters
            
            logger.debug(f"Processing step with distance: {step_distance/1609.34:.2f} miles")
            
            # If this step is longer than our interval, we need points within it
            if step_distance > interval_meters:
                # Calculate how many intervals fit in this step
                num_intervals = math.ceil(step_distance / interval_meters)
                
                # Get points along the actual path
                for i in range(num_intervals + 1):
                    # Calculate the fraction of the way through this step
                    fraction = i / num_intervals
                    
                    # Get the point along the path
                    if fraction == 0:
                        point = path[0]
                    elif fraction == 1:
                        point = path[-1]
                    else:
                        # Find the closest point in the path to our desired fraction
                        path_index = int(fraction * (len(path) - 1))
                        point = path[path_index]
                    
                    points.append({
                        'lat': point[0],  # polyline returns [lat, lng] pairs
                        'lng': point[1],
                        'distance': total_distance + (step_distance * fraction)
                    })
            else:
                # Step is shorter than interval, just add the end point
                end_point = path[-1]
                points.append({
                    'lat': end_point[0],
                    'lng': end_point[1],
                    'distance': total_distance + step_distance
                })
            
            total_distance += step_distance
    
    return points

@app.route('/')
def index():
    return render_template('index.html', google_maps_api_key=GOOGLE_MAPS_API_KEY)

@app.route('/get_route_weather', methods=['POST'])
def get_route_weather():
    try:
        logger.info("Starting new route weather request")
        data = request.get_json()
        addresses = data.get('addresses', [])
        interval_distance = data.get('interval_distance', 10)
        preferences = data.get('preferences', {})
        
        logger.info(f"Processing route from {addresses[0]} to {addresses[-1]}")
        logger.info(f"Interval distance: {interval_distance} miles")
        logger.debug(f"Preferences: {preferences}")

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

            # Get points along the actual driving route
            route_points = calculate_route_points(directions_result[0], interval_distance)
            
            # Process points to get weather data
            route_path = []
            last_zip = None
            seen_zips = set()
            
            logger.info("Starting route point analysis")
            
            # Add the origin point
            origin_zip = get_zip_code(coordinates[0]['lat'], coordinates[0]['lon'])
            logger.info(f"Origin point - Address: {coordinates[0]['address']}, Zip: {origin_zip}")
            route_path.append({
                'lat': coordinates[0]['lat'],
                'lon': coordinates[0]['lon'],
                'address': coordinates[0]['address'],
                'is_stop': True
            })
            
            if origin_zip:
                seen_zips.add(origin_zip)
                last_zip = origin_zip
                logger.debug(f"Added origin zip code: {origin_zip}")

            # Process each route point
            for point in route_points:
                current_zip = get_zip_code(point['lat'], point['lng'])
                logger.debug(f"Checking point - Current zip: {current_zip}, Last zip: {last_zip}")
                
                if current_zip and current_zip != last_zip:
                    logger.info(f"Adding point due to zip code change: {last_zip} -> {current_zip}")
                    route_path.append({
                        'lat': point['lat'],
                        'lon': point['lng'],
                        'address': 'Route Point',
                        'is_stop': False
                    })
                    last_zip = current_zip
                    seen_zips.add(current_zip)

            # Add the final destination
            final_zip = get_zip_code(coordinates[-1]['lat'], coordinates[-1]['lon'])
            logger.info(f"Adding final destination - Address: {coordinates[-1]['address']}, Zip: {final_zip}")
            route_path.append({
                'lat': coordinates[-1]['lat'],
                'lon': coordinates[-1]['lon'],
                'address': coordinates[-1]['address'],
                'is_stop': True
            })
            
            if final_zip:
                seen_zips.add(final_zip)

            logger.info("Route planning complete")
            logger.info(f"Total points added: {len(route_path)}")
            logger.info(f"Unique zip codes found: {len(seen_zips)}")
            logger.debug(f"All zip codes found: {sorted(list(seen_zips))}")

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
                'api_url': API_URL
            })
        else:
            return jsonify({
                'status': 'error',
                'message': 'Failed to get weather data',
                'api_url': API_URL
            }), 500
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Error: {str(e)}',
            'api_url': API_URL
        }), 500 