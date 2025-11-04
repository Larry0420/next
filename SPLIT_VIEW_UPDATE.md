# Split View Implementation - Map + List Simultaneously

## Overview
Updated the KMB Route Status page to show both the map view and list view **simultaneously** in a split-screen layout, with independent scrolling for each view.

## Key Changes

### 1. Split View Layout
When map view is enabled (via the map button), the app now shows:

**Portrait Mode (Vertical Split):**
```
┌─────────────────┐
│   Map View      │
│   (Top Half)    │
│                 │
├─────────────────┤
│   List View     │
│   (Bottom Half) │
│                 │
└─────────────────┘
```

**Landscape Mode (Horizontal Split):**
```
┌────────┬────────┐
│  Map   │  List  │
│  View  │  View  │
│ (Left) │ (Right)│
│        │        │
└────────┴────────┘
```

### 2. Independent Scrolling
- Each view has its own scroll controller
- Map can be panned/zoomed independently
- List can be scrolled independently
- **No scroll interference** between the two views

### 3. Layout Behavior
- **Map OFF**: Shows only the list view (full screen)
- **Map ON (Portrait)**: 50/50 vertical split (map top, list bottom)
- **Map ON (Landscape)**: 50/50 horizontal split (map left, list right)
- Automatically adapts to screen orientation

### 4. Updated UI Elements

#### AppBar Button
- **Icon**: Changed from `Icons.map`/`Icons.list` to `Icons.splitscreen`/`Icons.map`
- **Tooltip**: 
  - Map OFF: "Show map + list" / "顯示地圖+列表"
  - Map ON: "Show list only" / "僅顯示列表"

#### Location Button
- Now available in **both** modes (map + list view)
- Works with the list view portion in split mode

### 5. Code Structure

#### New Methods
```dart
Widget _buildListView(DeveloperSettingsProvider devSettings)
```
- Extracted list view logic into reusable method
- Shows route details card + stop list
- Handles loading/error states

#### Updated Methods
```dart
Widget _buildMapView()
```
- Now self-contained with error states
- Shows route destination header in all states
- Works independently in split view

### 6. Responsive Design
- Detects screen orientation automatically
- Adjusts layout dynamically
- Each half gets equal space (`Expanded(flex: 1)`)
- 8px spacing between views for visual clarity

## User Experience Benefits

1. **Compare Views**: See map location and ETA list simultaneously
2. **Find Stops Easily**: Tap stop on map, check ETA in list
3. **Better Context**: Geographic and temporal information together
4. **Flexible Workflow**: Toggle between full-list and split-view modes
5. **No Conflicts**: Each view scrolls/zooms independently

## Technical Implementation

### Layout Logic
```dart
showSplitView
  ? (isLandscape 
      ? Row([Map, List])      // Side by side
      : Column([Map, List]))  // Top and bottom
  : ListView                  // List only
```

### Scroll Independence
- Map: Uses `MapController` for pan/zoom
- List: Uses separate `ScrollController`
- No shared scroll state

### Responsive Split Ratios
- Each view: `Expanded(flex: 1)` = 50% of available space
- Future: Could make ratios adjustable (e.g., 60/40, 70/30)

## Usage

1. **Enable Split View**: Tap the map/splitscreen icon in AppBar
2. **Portrait Mode**: 
   - Map shows on top half
   - List shows on bottom half
   - Swipe/scroll each independently
3. **Landscape Mode**:
   - Map shows on left half
   - List shows on right half
   - Pan map, scroll list independently
4. **Disable Split View**: Tap icon again to return to list-only

## Future Enhancements

Possible improvements:
- Adjustable split ratio (drag divider)
- Sync map center with scrolled list position
- Highlight stop on map when tapped in list
- Remember split view preference
- Triple view option (map + upcoming + all stops)
- Floating map overlay option (PiP-style)
