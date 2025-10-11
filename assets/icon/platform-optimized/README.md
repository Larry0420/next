# Platform-Optimized Icon Assets

This directory contains platform-specific optimized icon assets for the Light Rail Transit app.

## Platform-Specific Optimizations

### Web Platform Icons
- **PWA Icons**: Multiple sizes for different contexts (512x512, 192x192, etc.)
- **Maskable Icons**: Safe area compliance for adaptive icons
- **Favicon**: 32x32 ICO format for browser tabs

### iOS Platform Icons
- **App Store Icon**: 1024x1024 without transparency
- **Device Icons**: Various sizes from 20x20 to 180x180
- **No Transparency**: iOS requires solid backgrounds

### Windows Platform Icons
- **ICO Format**: Multi-resolution ICO file
- **High DPI**: 256x256 for crisp display on high-DPI screens
- **Square Design**: Optimized for Windows tile system

### macOS Platform Icons
- **ICNS Format**: Apple's native icon format
- **Rounded Squares**: Following macOS design guidelines
- **Multiple Resolutions**: From 16x16 to 1024x1024

### Linux Platform Icons
- **PNG Format**: Standard Linux icon format
- **Desktop Integration**: Proper size for desktop environments
- **Scalable**: SVG source for infinite scaling

## Usage
These optimized assets are automatically used by flutter_launcher_icons when building for each platform.

## Maintenance
Update the corresponding source SVG files and regenerate platform-specific assets as needed.