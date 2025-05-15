# Documentation Resources

## Screenshots and Images

Place application screenshots in the `images/` directory. The main README.md file references these images.

### Adding New Screenshots

1. Take a high-quality screenshot of the application (recommended resolution: 1280x720 or higher)
2. Optimize the image for web (compress to reduce file size without losing quality)
3. Name the file descriptively (e.g., `route-planner-radar-view.png`, `weather-api-response.png`)
4. Place the file in the `images/` directory
5. Reference the image in markdown using relative paths:

```markdown
![Description of the image](docs/images/your-image-filename.png)
```

### Recommended Screenshot Content

For the Route Weather Planner:
- Main interface with a plotted route
- Weather information cards
- Radar overlay active on the map
- Mobile responsive view

For the Weather API:
- Example JSON response
- API documentation interface
- Weather data visualization

### Image Requirements

- File formats: PNG or JPG
- Maximum file size: 1MB per image
- Minimum resolution: 1280x720
- No sensitive information (API keys, user data, etc.) 