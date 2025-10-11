# Web Platform Icon Optimization Script

## PWA Icon Requirements
- 512x512: Main app icon for PWA manifests
- 192x192: Standard app icon
- 180x180: iOS Safari bookmark icon
- 152x152: iPad home screen
- 144x144: Windows tile
- 120x120: iPhone home screen
- 96x96: Android home screen
- 72x72: iPad app icon
- 48x48: Favicon base
- 32x32: Favicon standard
- 16x16: Favicon small

## Maskable Icon Safe Area
- Total icon: 512x512
- Safe area: 410x410 (centered)
- Minimum safe area: 320x320
- Background should extend to edges

## Implementation
The web icons should be generated from the high-resolution SVG source with proper safe areas for maskable icons.