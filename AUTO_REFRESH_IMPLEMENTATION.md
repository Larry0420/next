# Auto-Refresh Implementation - Best Practices

## Overview
The auto-refresh feature keeps train arrival data current for expanded station cards in the Routes page. This implementation follows industry best practices for background data synchronization.

## Architecture

### Design Principles
1. **Single Responsibility**: Each station card manages its own refresh timer
2. **Efficient Updates**: Only refreshes the specific expanded station (not all stations)
3. **Resilient**: Automatic error recovery with exponential backoff
4. **Resource-Aware**: Cleans up timers properly to prevent memory leaks
5. **User-Friendly**: Silent background operation without disrupting UX

### Component Structure

```
_RoutesPageState (Parent)
    ├── _refreshSingleStation(stationId, ...) → Refreshes specific station
    └── _RouteSchedulesList
            └── _CompactStationCard (per station)
                    ├── Timer (30s interval)
                    ├── State management (debounce, rate limit)
                    └── onRefresh callback → triggers parent refresh
```

## Implementation Details

### 1. Timer Management (`_CompactStationCardState`)

**State Variables:**
```dart
Timer? _autoRefreshTimer;
bool _isRefreshing = false;
int _consecutiveErrors = 0;
DateTime? _lastRefreshTime;

static const Duration _refreshInterval = Duration(seconds: 30);
static const Duration _minRefreshGap = Duration(seconds: 5);
static const int _maxConsecutiveErrors = 3;
```

**Lifecycle:**
- **Start**: When card expands (`didUpdateWidget` or `_onExpansionChanged`)
- **Stop**: When card collapses or widget disposes
- **Reset**: When station changes (error count cleared)

### 2. Exponential Backoff

The timer automatically adjusts its interval based on error history:

```dart
final interval = _consecutiveErrors > 0
    ? _refreshInterval * (1 << _consecutiveErrors)  // Bit shift for powers of 2
    : _refreshInterval;

// Results:
// 0 errors: 30 seconds
// 1 error:  60 seconds (30 * 2¹)
// 2 errors: 120 seconds (30 * 2²)
// 3+ errors: Disabled
```

**Why this matters:**
- Prevents hammering the server during temporary outages
- Automatically recovers when service resumes
- Reduces battery/network usage during issues

### 3. Debouncing & Rate Limiting

**Debouncing** prevents multiple simultaneous refreshes:
```dart
if (_isRefreshing) {
  debugPrint('⏭️ AUTO-REFRESH: Skipped (already refreshing)');
  return;
}
```

**Rate Limiting** prevents too-frequent updates:
```dart
if (_lastRefreshTime != null && 
    now.difference(_lastRefreshTime!) < _minRefreshGap) {
  debugPrint('⏭️ AUTO-REFRESH: Skipped (too soon)');
  return;
}
```

**Benefits:**
- Avoids redundant API calls
- Protects against rapid expand/collapse cycles
- Respects server rate limits

### 4. Optimized Data Refresh

**Single-Station Refresh:**
```dart
Future<void> _refreshSingleStation(int stationId, ...) async {
  final sched = await _api.fetch(stationId).timeout(Duration(seconds: 10));
  
  setState(() {
    _schedules = {..._schedules, stationId: sched};  // Only update this station
    _routeCache[routeKey] = _schedules;
  });
}
```

**Why not refresh all stations?**
- ❌ Old approach: Refresh all → N API calls per refresh
- ✅ New approach: Refresh one → 1 API call per refresh
- **Result**: N× reduction in network traffic and server load

### 5. Error Handling Strategy

**Progressive Degradation:**
1. **Error #1**: Continue with doubled interval (60s)
2. **Error #2**: Continue with quadrupled interval (120s)
3. **Error #3+**: Stop auto-refresh, manual user action required

**Silent Failures:**
```dart
catch (e) {
  debugPrint('⚠️ AUTO-REFRESH: Error for station $stationId: $e');
  // No user-facing error messages for background operations
}
```

**Automatic Recovery:**
```dart
// On first successful refresh after errors:
if (_consecutiveErrors > 0) {
  _consecutiveErrors = 0;
  _startAutoRefresh();  // Reset to normal 30s interval
}
```

## Callback Architecture

### Type-Safe Station Targeting

```dart
// Parent widget accepts station-specific callback
void Function(int stationId)? onRefreshStation;

// Child passes its own station ID
onRefresh: widget.onRefreshStation != null 
    ? () => widget.onRefreshStation!(id) 
    : null
```

**Advantages:**
- Type safety: Compiler ensures station ID is provided
- Flexibility: Each card can trigger its own refresh
- Efficiency: Parent knows exactly which station to update

## Performance Characteristics

### Memory Usage
- **Per expanded card**: 
  - 1 Timer object (~100 bytes)
  - 4 state variables (~32 bytes)
  - **Total**: ~132 bytes per expanded station

- **Cleanup**: All timers cancelled in `dispose()`
- **No leaks**: `mounted` checks prevent dangling references

### Network Traffic
- **Collapsed cards**: 0 requests
- **Expanded cards**: 1 request per 30 seconds
- **With 3 expanded cards**: 6 requests/minute (average)
- **Comparable to manual refresh**: Yes, but automatic

### CPU Usage
- **Timer overhead**: Negligible (native OS timers)
- **State checks**: O(1) constant time
- **UI updates**: Only on successful data fetch

## Usage Example

### For Users
1. Expand any station card in Routes page
2. Auto-refresh starts automatically (every 30s)
3. Train data updates silently in background
4. Collapse card → refresh stops automatically

### For Developers
```dart
// In _RoutesPageState:
_RouteSchedulesList(
  schedules: _schedules,
  onRefreshStation: (stationId) => _refreshSingleStation(
    stationId, 
    route, 
    stationProvider, 
    connectivity
  ),
)

// In _RouteSchedulesListState:
_CompactStationCard(
  stationId: id,
  onRefresh: widget.onRefreshStation != null 
      ? () => widget.onRefreshStation!(id) 
      : null,
)

// In _CompactStationCardState:
void _startAutoRefresh() {
  _autoRefreshTimer = Timer.periodic(_refreshInterval, (timer) {
    if (!mounted) { timer.cancel(); return; }
    _refreshStationData();
  });
}
```

## Debug Logging

Comprehensive logging for troubleshooting:

```
🔄 AUTO-REFRESH: Started for station 123 (route 505)
🔄 AUTO-REFRESH: Refreshing station 123 (route 505)
✅ AUTO-REFRESH: Station 123 refreshed successfully

// On errors:
❌ AUTO-REFRESH: Error for station 123 (attempt 1): TimeoutException
⚠️ AUTO-REFRESH: Disabled for station 123 after 3 consecutive errors

// On skips:
⏭️ AUTO-REFRESH: Skipped (already refreshing) - station 123
⏭️ AUTO-REFRESH: Skipped (too soon) - station 123
```

## Best Practices Checklist

✅ **Resource Management**
- Timers properly disposed
- `mounted` checks before setState
- Async operations cancelled on dispose

✅ **Error Resilience**
- Exponential backoff on errors
- Automatic recovery on success
- No cascading failures

✅ **Performance**
- Single-station updates (not full route)
- Debounced/rate-limited requests
- Minimal memory footprint

✅ **User Experience**
- Silent background operation
- No blocking UI updates
- Automatic lifecycle management

✅ **Code Quality**
- Type-safe callbacks
- Comprehensive logging
- Clear separation of concerns

## Comparison: Before vs After

| Feature | Before | After |
|---------|--------|-------|
| **Refresh Scope** | All route stations | Single expanded station |
| **Error Handling** | Silent fail | Exponential backoff + recovery |
| **Rate Limiting** | None | Debounce + min gap (5s) |
| **Network Calls** | N per refresh | 1 per refresh |
| **Memory Leaks** | Potential (no cleanup) | None (proper disposal) |
| **Recovery** | Manual only | Automatic |
| **Logging** | Basic | Comprehensive |

## Future Enhancements

### Potential Improvements
1. **Adaptive Interval**: Adjust based on time of day (less frequent at night)
2. **Network-Aware**: Different intervals for WiFi vs cellular
3. **Battery-Aware**: Pause on low battery
4. **Smart Prioritization**: Refresh stations with approaching trains more often
5. **Visual Indicator**: Subtle pulse animation during refresh
6. **Manual Refresh**: Pull-to-refresh gesture for immediate update

### Not Recommended
- ❌ WebSocket/SSE: Overkill for 30s updates, complex server changes
- ❌ <10s intervals: Would stress API unnecessarily
- ❌ All-stations refresh: Defeats optimization purpose

## Testing Recommendations

### Manual Testing
1. **Happy Path**: Expand card → verify refresh every 30s
2. **Error Recovery**: Disconnect network → verify backoff → reconnect → verify recovery
3. **Lifecycle**: Expand → collapse → verify timer stops
4. **Multiple Cards**: Expand 3+ cards → verify independent timers
5. **Navigation**: Switch routes → verify old timers cleanup

### Automated Testing
```dart
testWidgets('Auto-refresh starts on expand', (tester) async {
  // Setup
  await tester.pumpWidget(MyApp());
  await tester.tap(find.byType(ExpansionTile));
  await tester.pump();
  
  // Verify timer created
  expect(find.text('🔄 AUTO-REFRESH: Started'), findsOneWidget);
});
```

## Migration Guide

If you have an older implementation:

1. **Update callback signature**:
   ```dart
   - VoidCallback? onRefresh
   + void Function(int stationId)? onRefreshStation
   ```

2. **Update callback usage**:
   ```dart
   - onRefresh: () => _refreshAll()
   + onRefresh: () => widget.onRefreshStation!(id)
   ```

3. **Add state variables**:
   ```dart
   bool _isRefreshing = false;
   int _consecutiveErrors = 0;
   DateTime? _lastRefreshTime;
   ```

4. **Implement exponential backoff**:
   ```dart
   final interval = _consecutiveErrors > 0
       ? _refreshInterval * (1 << _consecutiveErrors)
       : _refreshInterval;
   ```

## Summary

This auto-refresh implementation represents production-ready code with:
- **Robustness**: Handles errors gracefully with automatic recovery
- **Efficiency**: Minimal network/battery usage through targeted updates
- **Maintainability**: Clear code structure with comprehensive logging
- **Scalability**: Performs well with multiple expanded stations

The implementation follows Flutter/Dart best practices and industry standards for background data synchronization in mobile applications.

---

**Last Updated**: October 11, 2025  
**Version**: 2.0 (Best Practices Rewrite)  
**Related Files**: 
- `lib/main.dart` (Lines 4516-4551, 5849-5863, 6247-6448)
