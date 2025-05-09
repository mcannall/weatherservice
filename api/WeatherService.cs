using System.Net.Http.Json;
using System.Text.Json;

namespace api;

/// <summary>
/// Custom exception for weather service related errors.
/// </summary>
public class WeatherServiceException : Exception
{
    public WeatherServiceException(string message) : base(message) { }
    public WeatherServiceException(string message, Exception innerException) : base(message, innerException) { }
}

/// <summary>
/// Service responsible for retrieving weather data from OpenWeatherMap API.
/// This service provides methods to fetch current weather conditions for specific locations.
/// </summary>
public class WeatherService
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<WeatherService> _logger;

    /// <summary>
    /// Initializes a new instance of the WeatherService class.
    /// </summary>
    /// <param name="httpClient">The HTTP client used for making API requests.</param>
    /// <param name="configuration">The configuration containing API settings.</param>
    /// <param name="logger">The logger instance for recording service operations.</param>
    public WeatherService(HttpClient httpClient, IConfiguration configuration, ILogger<WeatherService> logger)
    {
        _httpClient = httpClient;
        _configuration = configuration;
        _logger = logger;
    }

    /// <summary>
    /// Retrieves current weather data for a specified US zip code.
    /// </summary>
    /// <param name="zipCode">The US zip code to get weather data for.</param>
    /// <returns>
    /// A WeatherForecast object containing the current temperature and weather conditions.
    /// </returns>
    /// <exception cref="WeatherServiceException">
    /// Thrown when:
    /// - The API key is missing or invalid
    /// - The zip code is invalid
    /// - The API request fails
    /// - The response cannot be parsed
    /// - The service is unavailable
    /// </exception>
    public async Task<WeatherForecast> GetWeatherByZipCodeAsync(string zipCode)
    {
        try
        {
            // Validate configuration
            var apiKey = _configuration["OpenWeatherMap:ApiKey"];
            var baseUrl = _configuration["OpenWeatherMap:BaseUrl"];

            if (string.IsNullOrEmpty(apiKey))
            {
                _logger.LogError("OpenWeatherMap API key is missing in configuration");
                throw new WeatherServiceException("Weather service is not properly configured: Missing API key");
            }

            // Log API key prefix and URL for debugging
            _logger.LogInformation("Using API key starting with: {ApiKeyPrefix}", apiKey.Substring(0, Math.Min(4, apiKey.Length)));
            var requestUrl = $"{baseUrl}/weather?zip={zipCode},us&appid={apiKey}&units=metric";
            _logger.LogInformation("Making request to URL: {RequestUrl}", requestUrl.Replace(apiKey, "REDACTED"));

            if (string.IsNullOrEmpty(baseUrl))
            {
                _logger.LogError("OpenWeatherMap base URL is missing in configuration");
                throw new WeatherServiceException("Weather service is not properly configured: Missing base URL");
            }

            // Validate zip code
            if (string.IsNullOrWhiteSpace(zipCode) || !zipCode.All(char.IsDigit) || zipCode.Length != 5)
            {
                _logger.LogWarning("Invalid zip code format: {ZipCode}", zipCode);
                throw new WeatherServiceException($"Invalid zip code format: {zipCode}. Must be 5 digits.");
            }

            // Set timeout for the request
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));

            try
            {
                var response = await _httpClient.GetFromJsonAsync<OpenWeatherResponse>(
                    $"{baseUrl}/weather?zip={zipCode},us&appid={apiKey}&units=metric",
                    cts.Token);

                if (response == null)
                {
                    _logger.LogError("Received null response from OpenWeatherMap API for zip code: {ZipCode}", zipCode);
                    throw new WeatherServiceException("Unable to retrieve weather data: Empty response from service");
                }

                if (response.Main == null || response.Weather == null)
                {
                    _logger.LogError("Received incomplete weather data for zip code: {ZipCode}", zipCode);
                    throw new WeatherServiceException("Incomplete weather data received from service");
                }

                var forecast = new WeatherForecast(
                    DateOnly.FromDateTime(DateTime.Now),
                    (int)response.Main.Temp,
                    response.Weather.FirstOrDefault()?.Description ?? "No description available"
                );

                _logger.LogInformation("Successfully retrieved weather data for zip code: {ZipCode}", zipCode);
                return forecast;
            }
            catch (OperationCanceledException)
            {
                _logger.LogError("Request timeout while fetching weather data for zip code: {ZipCode}", zipCode);
                throw new WeatherServiceException("Weather service request timed out");
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request failed for zip code: {ZipCode}", zipCode);
                throw new WeatherServiceException("Unable to connect to weather service", ex);
            }
            catch (JsonException ex)
            {
                _logger.LogError(ex, "Failed to parse weather data for zip code: {ZipCode}", zipCode);
                throw new WeatherServiceException("Unable to process weather service response", ex);
            }
        }
        catch (WeatherServiceException)
        {
            // Rethrow WeatherServiceException as it's already properly formatted
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error while fetching weather data for zip code: {ZipCode}", zipCode);
            throw new WeatherServiceException("An unexpected error occurred while retrieving weather data", ex);
        }
    }
}

/// <summary>
/// Represents the response structure from the OpenWeatherMap API.
/// This class maps the JSON response to a strongly-typed object.
/// </summary>
public class OpenWeatherResponse
{
    /// <summary>
    /// Contains the main weather data including temperature.
    /// </summary>
    public MainData Main { get; set; } = new();

    /// <summary>
    /// List of weather conditions and their descriptions.
    /// Typically contains one item with the current weather state.
    /// </summary>
    public List<WeatherData> Weather { get; set; } = new();
}

/// <summary>
/// Contains the main weather measurements from the API response.
/// </summary>
public class MainData
{
    /// <summary>
    /// The current temperature in Celsius.
    /// </summary>
    public float Temp { get; set; }
}

/// <summary>
/// Represents detailed weather condition information.
/// </summary>
public class WeatherData
{
    /// <summary>
    /// A text description of the current weather conditions.
    /// Examples: "clear sky", "light rain", "scattered clouds"
    /// </summary>
    public string Description { get; set; } = string.Empty;
} 