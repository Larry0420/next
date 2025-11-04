# OpenStreetMap Integration for KMB Route Status Page

## Overview
Added OpenStreetMap integration to the KMB Route Status page, allowing users to view bus route stops on an interactive map alongside the existing list view.

## Changes Made

### 1. Package Dependencies
Added to `pubspec.yaml`:
- `flutter_map: ^7.0.2` - Flutter widget for displaying OpenStreetMap tiles
- `latlong2: ^0.9.1` - Latitude/longitude coordinate handling

### 2. Code Changes in `kmb_route_status_page.dart`

#### Imports
- Added `package:flutter_map/flutter_map.dart`
- Added `package:latlong2/latlong.dart`

#### State Variables
- `bool _showMapView = false` - Controls whether map or list view is displayed
- `MapController _mapController` - Controls the map widget

#### UI Features

##### AppBar Toggle Button
- Added map/list toggle button (shows map icon in list view, list icon in map view)
- Button switches between map and list views
- Location scroll button only shows in list view (not applicable to map view)

##### Map View (`_buildMapView()`)
The map view includes:

1. **Route Destination Header**
   - Shows route origin → destination
   - Direction indicator (inbound/outbound)
   - Service type badge

2. **Interactive Map**
   - OpenStreetMap tile layer
   - Blue polyline connecting all stops along the route
   - Numbered circular markers for each bus stop
   - Red location marker for user's current position (when available)
   - Auto-calculated center and zoom level based on route extent

3. **Stop Markers**
   - Blue circular markers with stop sequence number
   - Tap to show bottom sheet with:
     - Stop name (localized)
     - Stop ID
     - Coordinates
     - "View in list" button to switch to list view

4. **Legend**
   - Shows marker meanings (Bus Stop, Your Location)
   - Semi-transparent background with blur effect

##### Map Features
- **Automatic bounds calculation**: Map centers and zooms to fit all stops
- **Route polyline**: Visual path connecting stops in sequence
- **Responsive zoom levels**: Adjusts based on route geographic extent
- **Filtered by direction/service**: Only shows stops matching selected variant
- **Tap interactions**: Touch any stop marker to see details

### 3. User Experience

#### Switching Views
- Tap map icon in AppBar → Shows map with all stops
- Tap list icon in AppBar → Returns to traditional list view
- State is preserved when switching between views

#### Map Interactions
- **Pan**: Drag to move around the map
- **Zoom**: Pinch or double-tap to zoom in/out
- **Stop Details**: Tap any numbered marker to view stop information
- **Quick Return**: Use "View in list" button to jump back to list view

#### Location Integration
- If location permission granted, user's position shows as red marker
- Helps identify nearest stops visually
- Works alongside existing "scroll to nearest" feature in list view

## Benefits

1. **Visual Route Overview**: See the entire route path at a glance
2. **Geographic Context**: Understand stop locations relative to landmarks
3. **Distance Assessment**: Visual representation of stop spacing
4. **Alternative to Scrolling**: Quickly jump to any stop via map tap
5. **Dual Mode**: Choose between detailed list or visual map based on preference

## Technical Details

### Map Configuration
- **Tile Source**: OpenStreetMap public tiles
- **Zoom Range**: 10.0 (overview) to 18.0 (detailed)
- **User Agent**: `com.example.lrt_next_train`
- **Route Polyline**: 4px blue line with white border
- **Stop Markers**: 80x80px touch targets with 20px circular indicators

### Data Flow
1. Fetches same route-stop data as list view
2. Filters by selected direction and service type
3. Enriches with stop metadata (coordinates, names)
4. Builds markers and polyline from coordinates
5. Calculates optimal map bounds automatically

### Performance Considerations
- Map view lazy-loads (only renders when selected)
- Reuses existing data caching infrastructure
- Markers built efficiently from filtered stop list
- Map controller disposed properly to prevent leaks

## Future Enhancements

Potential additions:
- Real-time bus positions on map (if API available)
- ETA display in stop marker popups
- Route comparison (multiple routes on same map)
- Custom map styles/themes
- Satellite view toggle
- Traffic layer overlay
- Save favorite map zoom/position
- Export route as image

## Usage

1. Navigate to any KMB route (e.g., route 1, 2, etc.)
2. Tap the **map icon** (🗺️) in the top-right AppBar
3. View all stops along the route with:
   - Blue numbered markers for stops
   - Blue line showing route path
   - Red marker for your location (if enabled)
4. Tap any stop marker to see details
5. Tap the **list icon** (📋) to return to list view

## Compatibility

- **Android**: Fully supported
- **iOS**: Fully supported
- **Web**: Supported (OpenStreetMap works in browsers)
- **Desktop**: Supported (Windows, macOS, Linux)

## Attribution

Map data © [OpenStreetMap](https://www.openstreetmap.org/) contributors
