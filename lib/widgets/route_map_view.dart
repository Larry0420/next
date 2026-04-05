import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';

/// Reusable route map view widget
/// 
/// Provides a consistent map interface for all route status pages:
/// - Stop markers with customizable styling
/// - Route line visualization
/// - User location marker
/// - Interactive camera controls
/// - Highlighted stop animation
/// 
/// Eliminates ~800 lines of duplicated map-building code across CTB, KMB, NLB, GMB pages
class RouteMapView extends StatefulWidget {
  /// List of stops to display on the map
  final List<Map<String, dynamic>> stops;
  
  /// Map controller for camera control
  final MapController mapController;
  
  /// User's current position (optional)
  final LatLng? userPosition;
  
  /// Initially highlighted stop ID (optional)
  final String? highlightedStopId;
  
  /// Callback when a stop is tapped
  final Function(String stopId)? onStopTap;
  
  /// Callback when map is tapped
  final Function(LatLng position)? onMapTap;
  
  /// Initial camera position
  final LatLng initialCenter;
  
  /// Initial zoom level
  final double initialZoom;
  
  /// Whether to show user location marker
  final bool showUserLocation;
  
  /// Whether to enable location following
  final bool followUserLocation;
  
  const RouteMapView({
    super.key,
    required this.stops,
    required this.mapController,
    this.userPosition,
    this.highlightedStopId,
    this.onStopTap,
    this.onMapTap,
    required this.initialCenter,
    this.initialZoom = 14.0,
    this.showUserLocation = true,
    this.followUserLocation = false,
  });

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  String? _currentHighlightedStopId;
  
  @override
  void initState() {
    super.initState();
    _currentHighlightedStopId = widget.highlightedStopId;
  }
  
  @override
  void didUpdateWidget(RouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedStopId != oldWidget.highlightedStopId) {
      setState(() {
        _currentHighlightedStopId = widget.highlightedStopId;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        minZoom: 10.0,
        maxZoom: 18.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onTap: widget.onMapTap != null
            ? (tapPosition, point) => widget.onMapTap!(point)
            : null,
      ),
      children: [
        // OpenStreetMap tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.snake_app',
          maxZoom: 19,
        ),
        
        // User location marker
        if (widget.showUserLocation && widget.userPosition != null)
          _buildUserLocationMarker(),
        
        // Route line (connecting stops)
        if (widget.stops.length > 1)
          _buildRouteLine(),
        
        // Stop markers
        ..._buildStopMarkers(),
        
        // Location following widget
        if (widget.followUserLocation)
          const CurrentLocationLayer(),
      ],
    );
  }
  
  /// Build user location marker
  Widget _buildUserLocationMarker() {
    return MarkerLayer(
      markers: [
        Marker(
          point: widget.userPosition!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  /// Build route line connecting stops
  Widget _buildRouteLine() {
    final points = widget.stops
        .where((stop) => stop['lat'] != null && stop['lng'] != null)
        .map((stop) => LatLng(
              stop['lat'] as double,
              stop['lng'] as double,
            ))
        .toList();
    
    if (points.length < 2) return const SizedBox.shrink();
    
    return PolylineLayer(
      polylines: [
        Polyline(
          points: points,
          strokeWidth: 4.0,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        ),
      ],
    );
  }
  
  /// Build stop markers
  List<Widget> _buildStopMarkers() {
    return [
      MarkerLayer(
        markers: widget.stops
            .where((stop) => stop['lat'] != null && stop['lng'] != null)
            .map((stop) => _buildStopMarker(stop))
            .toList(),
      ),
    ];
  }
  
  /// Build individual stop marker
  Marker _buildStopMarker(Map<String, dynamic> stop) {
    final stopId = stop['stop_id']?.toString() ?? '';
    final lat = stop['lat'] as double;
    final lng = stop['lng'] as double;
    final isHighlighted = stopId == _currentHighlightedStopId;
    
    return Marker(
      point: LatLng(lat, lng),
      width: isHighlighted ? 48 : 36,
      height: isHighlighted ? 48 : 36,
      child: GestureDetector(
        onTap: () {
          if (widget.onStopTap != null) {
            widget.onStopTap!(stopId);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isHighlighted
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: isHighlighted
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
              width: isHighlighted ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              _getStopSequence(stop),
              style: TextStyle(
                color: isHighlighted
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: isHighlighted ? 14 : 12,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// Get stop sequence number for display
  String _getStopSequence(Map<String, dynamic> stop) {
    final seq = stop['seq']?.toString();
    return seq?.isNotEmpty == true ? seq! : '';
  }
}

/// Simplified route map view with minimal configuration
class SimpleRouteMapView extends StatelessWidget {
  /// List of stops with lat/lng coordinates
  final List<Map<String, double?>> stops;
  
  /// Map controller
  final MapController mapController;
  
  /// Initial center point
  final LatLng center;
  
  const SimpleRouteMapView({
    super.key,
    required this.stops,
    required this.mapController,
    required this.center,
  });

  @override
  Widget build(BuildContext context) {
    final formattedStops = stops
        .where((stop) => stop['lat'] != null && stop['lng'] != null)
        .map((stop) => {
              'lat': stop['lat'] as double,
              'lng': stop['lng'] as double,
              'stop_id': stop['stop_id']?.toString() ?? '',
              'seq': stop['seq']?.toString() ?? '',
            })
        .toList();
    
    return RouteMapView(
      stops: formattedStops,
      mapController: mapController,
      initialCenter: center,
      showUserLocation: false,
    );
  }
}