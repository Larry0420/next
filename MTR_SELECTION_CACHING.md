# MTR Selection Caching - Implementation Guide

## Overview

The MTR schedule page now has **complete caching** for all user selections:
- ✅ Line selection
- ✅ Station selection  
- ✅ Direction selection

All selections are persisted using `SharedPreferences` and automatically restored when the app restarts (if auto-load setting is enabled).

---

## Implementation Details

### Cached Data Keys

```dart
// SharedPreferences keys
'mtr_selected_line'       // Line code (e.g., "TCL", "AEL")
'mtr_selected_station'    // Station code (e.g., "HOK", "TST")
'mtr_selected_direction'  // Direction (e.g., "UP", "DOWN", "IN", "OUT")
```

### Cache Behavior by Method

#### 1. `selectLine(MtrLine line)`
**Location**: `mtr_schedule_page.dart` ~line 988

**What it does**:
- Sets selected line
- Resets to first station of the new line
- **Clears direction** (each line has different directions)
- Saves line + station to cache
- **Removes cached direction** (no longer valid)

```dart
Future<void> selectLine(MtrLine line) async {
  _selectedLine = line;
  _selectedStation = line.stations.isNotEmpty ? line.stations.first : null;
  _selectedDirection = null; // Reset direction
  notifyListeners();
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('mtr_selected_line', line.lineCode);
  if (_selectedStation != null) {
    await prefs.setString('mtr_selected_station', _selectedStation!.stationCode);
  }
  await prefs.remove('mtr_selected_direction'); // Clear old direction
}
```

#### 2. `selectStation(MtrStation station)`
**Location**: `mtr_schedule_page.dart` ~line 1007

**What it does**:
- Sets selected station
- **Keeps current direction** (same line, direction still valid)
- Saves line + station + direction to cache

```dart
Future<void> selectStation(MtrStation station) async {
  _selectedStation = station;
  notifyListeners();
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('mtr_selected_station', station.stationCode);
  // Save line for consistency
  if (_selectedLine != null) {
    await prefs.setString('mtr_selected_line', _selectedLine!.lineCode);
  }
  // Keep current direction
  if (_selectedDirection != null) {
    await prefs.setString('mtr_selected_direction', _selectedDirection!);
  }
}
```

#### 3. `selectDirection(String direction)` ⭐ NEW
**Location**: `mtr_schedule_page.dart` ~line 1025

**What it does**:
- Sets selected direction
- Saves complete selection (line + station + direction) to cache

```dart
Future<void> selectDirection(String direction) async {
  _selectedDirection = direction;
  notifyListeners();
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('mtr_selected_direction', direction);
  // Save line and station for completeness
  if (_selectedLine != null) {
    await prefs.setString('mtr_selected_line', _selectedLine!.lineCode);
  }
  if (_selectedStation != null) {
    await prefs.setString('mtr_selected_station', _selectedStation!.stationCode);
  }
}
```

---

## Usage in UI

### How to Use the New `selectDirection` Method

If you have a direction picker (e.g., dropdown or buttons), call:

```dart
// Example: Direction dropdown
DropdownButton<String>(
  value: catalog.selectedDirection,
  items: catalog.availableDirections.map((dir) {
    return DropdownMenuItem(value: dir, child: Text(dir));
  }).toList(),
  onChanged: (direction) {
    if (direction != null) {
      catalog.selectDirection(direction); // This now saves to cache!
    }
  },
)

// Example: Direction buttons
Row(
  children: catalog.availableDirections.map((dir) {
    return ElevatedButton(
      onPressed: () => catalog.selectDirection(dir),
      child: Text(dir),
    );
  }).toList(),
)
```

### Existing Usage (Already Works)

```dart
// Line selection (already caches)
catalog.selectLine(selectedLine);

// Station selection (already caches)
catalog.selectStation(selectedStation);
```

---

## Cache Restoration Flow

### On App Start

```
1. MtrCatalogProvider() constructor
   ↓
2. _loadMtrData(loadCachedSelection: false)
   ↓
3. Load MTR catalog from JSON
   ↓
4. DON'T load cached selection yet (wait for settings)
   ↓
5. _MtrSchedulePageState calls initializeWithSettings()
   ↓
6. Check devSettings.mtrAutoLoadCachedSelection
   ↓
7. If enabled: _loadSavedSelection()
   ↓
8. Restore line + station + direction from SharedPreferences
   ↓
9. notifyListeners() → UI shows cached selection
```

### _loadSavedSelection() Method

**Location**: `mtr_schedule_page.dart` ~line 949

```dart
Future<void> _loadSavedSelection() async {
  final prefs = await SharedPreferences.getInstance();
  final savedLineCode = prefs.getString('mtr_selected_line');
  final savedStationCode = prefs.getString('mtr_selected_station');
  final savedDirection = prefs.getString('mtr_selected_direction'); // ✅ Restored
  
  if (savedLineCode != null && savedStationCode != null) {
    final line = _lines.firstWhere(
      (l) => l.lineCode == savedLineCode,
      orElse: () => _lines.first,
    );
    final station = line.stations.firstWhere(
      (s) => s.stationCode == savedStationCode,
      orElse: () => line.stations.first,
    );
    
    _selectedLine = line;
    _selectedStation = station;
    _selectedDirection = savedDirection; // ✅ Direction restored
  }
}
```

---

## Cache Consistency Rules

### Rule 1: Line Change → Clear Direction
When user changes line, direction is cleared because:
- Different lines have different direction systems
- TCL has "UP"/"DOWN"
- AEL has "IN"/"OUT"  
- Direction from old line is invalid for new line

### Rule 2: Station Change → Keep Direction
When user changes station on same line, direction is kept because:
- Same line has consistent direction system
- Direction is still valid
- User likely wants to see same direction for new station

### Rule 3: Direction Change → Keep Line & Station
When user changes direction:
- Line stays the same
- Station stays the same
- Only direction updates

---

## Testing Scenarios

### ✅ Test 1: Complete Selection Persistence
1. Select line (e.g., TCL)
2. Select station (e.g., Hong Kong)
3. Select direction (e.g., UP)
4. Restart app
5. **Expected**: All 3 selections restored (if auto-load enabled)

### ✅ Test 2: Line Change Clears Direction
1. Select TCL → Hong Kong → UP
2. Change to AEL line
3. **Expected**: Direction cleared, station reset to first of AEL

### ✅ Test 3: Station Change Keeps Direction
1. Select TCL → Hong Kong → UP
2. Change station to Kowloon
3. **Expected**: Direction still "UP", only station changed

### ✅ Test 4: Auto-Load Toggle
1. Enable auto-load in settings
2. Select line/station/direction
3. Restart app
4. **Expected**: Selections restored
5. Disable auto-load in settings
6. Restart app
7. **Expected**: Default to first line/station, no direction

---

## Benefits

### Before Enhancement
- ✅ Line caching
- ✅ Station caching
- ❌ Direction caching (missing)
- ❌ Inconsistent cache updates

### After Enhancement
- ✅ Line caching (improved)
- ✅ Station caching (improved)  
- ✅ Direction caching (NEW)
- ✅ Consistent cache updates
- ✅ Proper direction clearing on line change
- ✅ Direction preservation on station change
- ✅ Complete selection restoration

---

## API Reference

### MtrCatalogProvider Methods

```dart
// Selection methods (all cache automatically)
Future<void> selectLine(MtrLine line)           // Saves line+station, clears direction
Future<void> selectStation(MtrStation station)  // Saves line+station+direction
Future<void> selectDirection(String direction)  // Saves line+station+direction (NEW)

// Utility methods
Future<void> initializeWithSettings(bool shouldLoadCachedSelection)
Future<void> reloadWithSettings(bool loadCachedSelection)
Future<void> applyCachedSelection()

// Getters
List<MtrLine> get lines
MtrLine? get selectedLine
MtrStation? get selectedStation
String? get selectedDirection
List<String> get availableDirections
List<MtrStation> get filteredStations
bool get hasSelection
bool get isInitialized
```

---

## Migration Notes

### Breaking Changes
**None** - all existing code continues to work.

### New Functionality
- `selectDirection(String direction)` method added
- Direction now automatically cached
- Direction properly cleared/preserved based on context

### Backward Compatibility
- Existing `selectLine()` and `selectStation()` calls work as before
- New caching logic is additive, not disruptive

---

## Related Documentation

- **`MTR_CARD_QUICK_REFERENCE.md`**: MTR UI component reference
- **`MTR_STATION_PAGE.md`**: MTR page structure
- **`APP_NAMING_GUIDE.md`**: MTR/LRT naming conventions

---

## Summary

The MTR selection caching system now provides:

✅ **Complete Coverage**: Line + Station + Direction all cached
✅ **Smart Behavior**: Direction cleared on line change, kept on station change  
✅ **Consistent Persistence**: All selections saved immediately
✅ **Auto-Restore**: Cached selections restored on app start (if enabled)
✅ **Easy Integration**: Simple `selectDirection()` method for UI
✅ **No Breaking Changes**: Fully backward compatible

The caching system ensures users always return to their last selected MTR line, station, and direction, providing a seamless experience across app restarts.
