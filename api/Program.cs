using api;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Caching.Memory;
using System;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.Extensions.Diagnostics.HealthChecks;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHttpClient();
builder.Services.AddScoped<WeatherService>();
builder.Services.AddLogging(logging =>
{
    logging.AddConsole();
    logging.AddDebug();
});
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(builder =>
    {
        builder.AllowAnyOrigin()
               .AllowAnyMethod()
               .AllowAnyHeader();
    });
});

// Add Memory Cache
builder.Services.AddMemoryCache();

// Add HTTP Client
builder.Services.AddHttpClient("OpenWeatherMap", client =>
{
    var apiKey = builder.Configuration["OpenWeatherMap:ApiKey"];
    var baseUrl = builder.Configuration["OpenWeatherMap:BaseUrl"] ?? "https://api.openweathermap.org/data/2.5";
    
    client.BaseAddress = new Uri(baseUrl);
    client.DefaultRequestHeaders.Add("Accept", "application/json");
});

// Add health checks
builder.Services.AddHealthChecks()
    .AddCheck("OpenWeatherMap API Key", () => {
        var apiKey = builder.Configuration["OpenWeatherMap:ApiKey"];
        if (string.IsNullOrEmpty(apiKey)) {
            return HealthCheckResult.Unhealthy("OpenWeatherMap API key is missing");
        }
        return HealthCheckResult.Healthy("OpenWeatherMap API key is configured");
    });

// Configure Kestrel to listen on all interfaces
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(80); // HTTP only
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();

// Add a default endpoint for the root URL
app.MapGet("/", () => "Welcome to Tom's weather forecasting api! Use /weather/{zipCode} to get weather data for a specific US zip code.");

// Weather endpoint for real weather data by zip code
app.MapGet("/weather/{zipCode}", async (string zipCode, WeatherService weatherService, ILogger<Program> logger) =>
{
    try
    {
        // Validate input
        if (string.IsNullOrWhiteSpace(zipCode) || !zipCode.All(char.IsDigit))
        {
            logger.LogWarning("Invalid ZIP code format: {ZipCode}", zipCode);
            return Results.BadRequest(new { error = "Invalid ZIP code format. Please provide a valid US ZIP code." });
        }

        var forecast = await weatherService.GetWeatherByZipCodeAsync(zipCode);
        return Results.Ok(forecast);
    }
    catch (WeatherServiceException ex)
    {
        logger.LogError(ex, "Weather service error for ZIP {ZipCode}: {Message}", zipCode, ex.Message);
        
        // Provide more specific error messages based on exception data
        var detail = ex.Message;
        if (ex.InnerException != null)
        {
            detail += $" Details: {ex.InnerException.Message}";
        }
        
        if (detail.Contains("api key") || detail.Contains("API key") || detail.Contains("unauthorized"))
        {
            return Results.Problem(
                title: "API Configuration Error",
                detail: "The OpenWeatherMap API key is missing, invalid or unauthorized. Please check your API key configuration.",
                statusCode: StatusCodes.Status503ServiceUnavailable
            );
        }
        
        if (detail.Contains("not found"))
        {
            return Results.NotFound(new { error = $"Weather data for ZIP code {zipCode} not found" });
        }
        
        return Results.Problem(
            title: "Weather Service Error",
            detail: detail,
            statusCode: StatusCodes.Status503ServiceUnavailable
        );
    }
    catch (HttpRequestException ex)
    {
        logger.LogError(ex, "HTTP request error for ZIP {ZipCode}: {Message}", zipCode, ex.Message);
        return Results.Problem(
            title: "Connection Error",
            detail: $"Unable to connect to weather service: {ex.Message}",
            statusCode: StatusCodes.Status503ServiceUnavailable
        );
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Unexpected error processing weather request for ZIP {ZipCode}: {Message}", zipCode, ex.Message);
        return Results.Problem(
            title: "Internal Server Error",
            detail: "An unexpected error occurred while processing your request.",
            statusCode: StatusCodes.Status500InternalServerError
        );
    }
})
.WithName("GetWeatherByZipCode")
.Produces<WeatherForecast>(StatusCodes.Status200OK)
.ProducesProblem(StatusCodes.Status400BadRequest)
.ProducesProblem(StatusCodes.Status404NotFound)
.ProducesProblem(StatusCodes.Status503ServiceUnavailable)
.ProducesProblem(StatusCodes.Status500InternalServerError);

// Add a simple health check endpoint
app.MapHealthChecks("/health");

// Add a config status endpoint
app.MapGet("/config/status", (IConfiguration config) => {
    var apiKey = config["OpenWeatherMap:ApiKey"];
    var hasApiKey = !string.IsNullOrEmpty(apiKey);
    
    return new { 
        openWeatherMapConfigured = hasApiKey,
        apiKeyLength = hasApiKey ? apiKey.Length : 0,
        baseUrlConfigured = !string.IsNullOrEmpty(config["OpenWeatherMap:BaseUrl"])
    };
});

// Add a more detailed diagnostics endpoint
app.MapGet("/debug", (IConfiguration config, IWebHostEnvironment env) => {
    var apiKey = config["OpenWeatherMap:ApiKey"];
    return new {
        environment = env.EnvironmentName,
        hasApiKey = !string.IsNullOrEmpty(apiKey),
        apiKeyLength = !string.IsNullOrEmpty(apiKey) ? apiKey.Length : 0,
        baseUrl = config["OpenWeatherMap:BaseUrl"] ?? "Not configured",
        time = DateTime.Now.ToString("o"),
        osVersion = Environment.OSVersion.ToString(),
        processArchitecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString()
    };
});

app.Run();

public record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
    public string Country { get; init; } = "US";  // Default to US since we're only handling US zip codes
}
