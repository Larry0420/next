# MTR Direction Filter Toggle - Implementation Guide

## Overview

The MTR schedule page now includes a **direction filter toggle** that allows users to filter train schedules by specific directions (UP/DOWN for most lines, IN/OUT for Airport Express, etc.).

This feature provides a cleaner, more focused view when users only want to see trains in one direction.

---

## UI Location

The direction filter toggle appears **between the station selector and the schedule display**:

```
┌─────────────────────────────┐
│  Line Selector              │
│  🚆 Tuen Ma Line           │
└─────────────────────────────┘

┌─────────────────────────────┐
│  Station Selector           │
│  📍 Tin Shui Wai           │
└─────────────────────────────┘

┌─────────────────────────────┐  ← NEW DIRECTION FILTER
│  ⇅ Direction  [All] [Up] [Down] │
└─────────────────────────────┘

┌─────────────────────────────┐
│  Auto-refresh controls      │
└─────────────────────────────┘

┌─────────────────────────────┐
│  Train Schedule Display     │
│  ▶ Upbound                  │
│    • Train 1                │
│    • Train 2                │
└─────────────────────────────┘
```

---

## Features

### 1. **Dynamic Direction Options**
- Automatically shows directions available for the selected line
- Hides toggle if line has no direction information
- Adapts to each line's specific direction system:
  - **Tung Chung Line, Tuen Ma Line, etc.**: UP / DOWN
  - **Airport Express**: IN / OUT
  - **Other lines**: Line-specific directions

### 2. **Toggle Buttons**
- **All**: Show all directions (default)
- **Direction-specific buttons**: Filter to one direction only
- Bilingual labels (English / 繁體中文)
- Visual feedback with color and border changes

### 3. **Persistent Selection**
- Direction preference cached using SharedPreferences
- Restored on app restart (if auto-load setting enabled)
- Cleared automatically when changing lines

### 4. **Smart Filtering**
- Real-time filter applied to schedule display
- Shows "No trains for this direction" if filter results in empty list
- Seamless toggle without reloading data

---

## Implementation Details

### New Widget: `_buildDirectionToggle()`

**Location**: `mtr_schedule_page.dart` ~line 2035

```dart
Widget _buildDirectionToggle(BuildContext context, MtrCatalogProvider catalog, bool isEnglish) {
  // Compact card with direction toggle buttons
  // - Icon: swap_vert_rounded (vertical arrows)
  // - Label: "Direction" / "方向"
  // - Buttons: All, Up, Down (or IN/OUT, etc.)
}
```

### New Widget: `_buildDirectionButton()`

**Location**: `mtr_schedule_page.dart` ~line 2088

```dart
Widget _buildDirectionButton({
  required String label,
  required bool isSelected,
  required Color color,
  required VoidCallback onTap,
}) {
  // Individual toggle button with:
  // - Animated background color
  // - Border color change on selection
  // - Font weight change on selection
  // - Haptic feedback on tap
}
```

### Direction Label Formatting: `_formatDirectionLabel()`

**Location**: `mtr_schedule_page.dart` ~line 2107

Maps direction codes to user-friendly labels:

| Code | English | 繁體中文 |
|------|---------|---------|
| UP | Up | 上行 |
| DOWN | Down | 下行 |
| IN | Inbound | 入站 |
| OUT | Outbound | 出站 |

### Schedule Filtering Logic

**Location**: `_MtrScheduleBody` ~line 2704

```dart
// Filter directions based on selected direction
final selectedDirection = catalog.selectedDirection;
var directionEntries = data!.directionTrains.entries.toList();

// Apply direction filter if a specific direction is selected
if (selectedDirection != null && selectedDirection.isNotEmpty) {
  directionEntries = directionEntries.where((entry) {
    return entry.key.toUpperCase() == selectedDirection.toUpperCase();
  }).toList();
}

// Handle case where filtering results in no trains
if (directionEntries.isEmpty) {
  // Show "No trains for this direction" message
}
```

---

## User Interaction Flow

### Selecting a Direction

```
1. User taps "Up" button
   ↓
2. HapticFeedback.selectionClick() (tactile response)
   ↓
3. catalog.selectDirection("UP")
   ↓
4. MtrCatalogProvider._selectedDirection = "UP"
   ↓
5. Save to SharedPreferences: 'mtr_selected_direction' = 'UP'
   ↓
6. notifyListeners() → UI updates
   ↓
7. Schedule display filters trains to show only "UP" direction
   ↓
8. Button shows selected state (darker color, thicker border)
```

### Selecting "All"

```
1. User taps "All" button
   ↓
2. catalog.selectDirection("")
   ↓
3. Remove 'mtr_selected_direction' from SharedPreferences
   ↓
4. notifyListeners() → UI updates
   ↓
5. Schedule display shows all directions
```

### Changing Lines

```
1. User selects different line (e.g., TCL → AEL)
   ↓
2. catalog.selectLine(AEL)
   ↓
3. _selectedDirection = null (cleared)
   ↓
4. Remove 'mtr_selected_direction' from SharedPreferences
   ↓
5. Direction toggle updates to show AEL directions (IN, OUT)
   ↓
6. "All" button selected by default
```

---

## Caching Behavior

### Cache Keys
```dart
'mtr_selected_direction'  // User's last selected direction filter
```

### Cache Logic

| Event | Direction Cache Behavior |
|-------|-------------------------|
| **Line changed** | Cleared (different direction system) |
| **Station changed** | Preserved (same line) |
| **Direction toggled** | Saved immediately |
| **App restart** | Restored (if auto-load enabled) |
| **"All" selected** | Removed from cache |

---

## Visual Design

### Button States

#### Unselected State
```
┌──────────┐
│   Down   │  ← Light gray background
└──────────┘  ← Thin gray border
```

#### Selected State
```
┌──────────┐
│   Down   │  ← Light line-color background (e.g., pink for TML)
└──────────┘  ← Thick line-color border, bold text
```

### Color Scheme
- **Selected background**: `lineColor.withOpacity(0.15)`
- **Selected border**: `lineColor` (1.5px)
- **Selected text**: `lineColor` (bold)
- **Unselected background**: `surfaceContainerHighest`
- **Unselected border**: `outline.withOpacity(0.3)` (1px)
- **Unselected text**: `onSurfaceVariant` (medium)

---

## Edge Cases Handled

### 1. No Directions Available
```dart
if (catalog.availableDirections.isEmpty) {
  // Don't show direction toggle at all
}
```

### 2. Filtering Results in No Trains
```dart
if (directionEntries.isEmpty) {
  // Show friendly message:
  // "No trains for this direction" / "此方向沒有列車"
}
```

### 3. Line Without Direction Data
```dart
// Direction toggle automatically hides
// Only shows when availableDirections.isNotEmpty
```

### 4. App Restart with Cached Direction
```dart
// On restart:
// 1. Load cached line (e.g., "TML")
// 2. Load cached station (e.g., "TIS")
// 3. Load cached direction (e.g., "UP")
// 4. Direction toggle shows "Up" as selected
// 5. Schedule display shows only UP trains
```

---

## API Integration

### MtrCatalogProvider Updates

#### New Getter
```dart
List<String> get availableDirections {
  if (_selectedLine == null) return const [];
  return _selectedLine!.directionTermini.keys.toList()..sort();
}
```

#### Enhanced selectDirection()
```dart
Future<void> selectDirection(String direction) async {
  _selectedDirection = direction;
  notifyListeners();
  
  // Save to SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('mtr_selected_direction', direction);
  
  // Also save line and station for consistency
  if (_selectedLine != null) {
    await prefs.setString('mtr_selected_line', _selectedLine!.lineCode);
  }
  if (_selectedStation != null) {
    await prefs.setString('mtr_selected_station', _selectedStation!.stationCode);
  }
}
```

---

## Testing Scenarios

### ✅ Test 1: Direction Toggle Visibility
1. Select line with directions (e.g., TML)
2. **Expected**: Direction toggle visible with "All", "Up", "Down"
3. Select line without directions (if any)
4. **Expected**: Direction toggle hidden

### ✅ Test 2: Filter Functionality
1. Select TML → Tin Shui Wai
2. Tap "Up" button
3. **Expected**: Only upbound trains shown, button highlighted
4. Tap "Down" button
5. **Expected**: Only downbound trains shown, button highlighted
6. Tap "All" button
7. **Expected**: Both directions shown, "All" button highlighted

### ✅ Test 3: Cache Persistence
1. Select TML → TIS → "Up"
2. Restart app (with auto-load enabled)
3. **Expected**: TML, TIS, "Up" all restored

### ✅ Test 4: Line Change Clears Direction
1. Select TML → "Up" filter active
2. Change to AEL line
3. **Expected**: Direction cleared, "All" selected, shows "In"/"Out" buttons

### ✅ Test 5: Station Change Keeps Direction
1. Select TML → TIS → "Up"
2. Change station to LOP (Long Ping)
3. **Expected**: "Up" filter still active

### ✅ Test 6: Empty Filter Result
1. Select a station/direction with no trains (edge case)
2. **Expected**: "No trains for this direction" message shown

---

## Performance Considerations

### Efficient Filtering
- **O(n) complexity**: Single pass through direction entries
- **No network request**: Filter applied to existing data
- **Minimal re-renders**: Only filtered list updates

### Memory Impact
- **Minimal**: Only stores single direction string in state
- **Cache size**: ~10 bytes in SharedPreferences

### UI Responsiveness
- **Instant toggle**: No loading state needed
- **Smooth animation**: 200ms duration for button state changes
- **Haptic feedback**: Immediate tactile response

---

## Accessibility

### Features
- **Tap targets**: 44pt minimum touch area for buttons
- **Color contrast**: Sufficient contrast for all states
- **Labels**: Clear, descriptive text for all buttons
- **Bilingual**: Full support for English and Traditional Chinese

---

## Related Features

### Works With
- ✅ **MTR Selection Caching**: Direction filter cached and restored
- ✅ **Auto-Load Setting**: Respects user's auto-load preference
- ✅ **Sequential Operations**: No conflicts with background refresh
- ✅ **Pull-to-Refresh**: Filter persists after manual refresh

### Consistent With
- **LRT System**: Can be replicated for LRT if needed
- **UI Design**: Matches existing card-based MTR UI
- **Color Scheme**: Uses line colors consistently

---

## Future Enhancements (Optional)

### Possible Additions
1. **Swipe Gesture**: Swipe left/right to toggle directions
2. **Quick Switch**: Double-tap station card to flip direction
3. **Animation**: Smooth transition when changing filter
4. **Badge**: Show train count per direction on buttons
5. **Auto-Select**: Auto-select direction if only one available

---

## Code Locations

| Component | File | Line |
|-----------|------|------|
| Direction Toggle Widget | `mtr_schedule_page.dart` | ~2035 |
| Direction Button Widget | `mtr_schedule_page.dart` | ~2088 |
| Label Formatting | `mtr_schedule_page.dart` | ~2107 |
| Filtering Logic | `mtr_schedule_page.dart` | ~2704 |
| MtrCatalogProvider | `mtr_schedule_page.dart` | ~785 |

---

## Summary

The MTR direction filter toggle provides:

✅ **User Control**: Easy filtering of train schedules by direction
✅ **Smart Caching**: Direction preference persisted and restored
✅ **Clean UI**: Compact toggle integrated seamlessly into existing design
✅ **Bilingual Support**: Full English and Traditional Chinese localization
✅ **Line-Aware**: Adapts to each line's specific direction system
✅ **Edge Case Handling**: Graceful behavior when no trains match filter
✅ **Performance**: Instant filtering with no network overhead
✅ **Consistency**: Follows established MTR UI patterns and caching behavior

Users can now focus on trains in their desired direction, reducing visual clutter and improving the experience when planning their journey.
