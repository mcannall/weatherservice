using api;

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
app.MapGet("/weather/{zipCode}", async (string zipCode, WeatherService weatherService) =>
{
    try
    {
        var forecast = await weatherService.GetWeatherByZipCodeAsync(zipCode);
        return Results.Ok(forecast);
    }
    catch (WeatherServiceException ex)
    {
        return Results.Problem(
            title: "Weather Service Error",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable
        );
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Internal Server Error",
            detail: "An unexpected error occurred while processing your request.",
            statusCode: StatusCodes.Status500InternalServerError
        );
    }
})
.WithName("GetWeatherByZipCode")
.Produces<WeatherForecast>(StatusCodes.Status200OK)
.ProducesProblem(StatusCodes.Status503ServiceUnavailable)
.ProducesProblem(StatusCodes.Status500InternalServerError);

app.Run();

public record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}
