# ETA Refetch Optimization - Implementation Summary

## Overview
Optimized the `ExpandableStopCard` widget to provide automatic ETA refetching with smooth animations on card expansion, and a clean collapsed state showing compact placeholder text.

## Key Changes

### 1. **Automatic Refetch on Expand (No Manual Button Required)**
- **Method**: `_autoRefetchOnExpand()` - Triggered automatically when card expands
- **Behavior**:
  - Shows loading spinner with "Fetching..." / "更新中..." text for minimum 1.5 seconds
  - Automatically calls `Kmb.fetchStopEta(stopId)` to fetch fresh data
  - Smooth animation ensures users see the action is happening
  - Silently handles errors without disruptive snackbars

### 2. **Smart Expansion Toggle**
- **Method**: `_toggleExpanded()` - Replaces inline expand/collapse logic
- **Features**:
  - Only triggers auto-refetch when expanding (not collapsing)
  - Tracks previous expansion state to avoid redundant refetches
  - Clean, reusable toggle logic

### 3. **Optimized Display States**

#### Collapsed State (Most of the time - Initial view)
- Shows compact placeholder: **"No buses"** (EN) / **"無班次"** (TC)
- Small, unobtrusive text using `bodySmall` style
- Minimal visual weight while still providing context

#### Expanded State - Three Sub-States

1. **Loading/Refetching** (`_shouldShowRefreshAnimation = true`)
   - Spinner icon + "Fetching..." / "更新中..." text
   - Primary color highlighting to draw attention
   - Smooth 300ms AnimatedSwitcher transition
   - Guaranteed minimum 1.5s display for UX feedback

2. **Empty Data** (No ETAs available)
   - Shows: "No upcoming buses" / "沒有即將到站的巴士"
   - Larger `bodyMedium` style for better readability
   - Useful feedback when there are genuinely no buses

3. **With ETAs** (Normal state)
   - Shows up to 3 ETAs with times and remarks
   - Large, bold text for time (titleLarge 20px)
   - Color-coded based on arrival time (red < 2min, orange < 5min, green < 10min)
   - Remarks displayed below with truncation if needed

### 4. **Action Buttons (Expanded Only)**
Visible only when card is expanded with smooth `AnimatedSize` transition:

- **Refresh** (Manual) - Shows spinner during manual refetch
- **Pin** - Add to favorites
- **Map** - Jump to map view (if coordinates available)
- **View** - Street view placeholder

*Note: Automatic refetch happens on expand, manual refresh button provides additional control if needed.*

### 5. **Smooth Animations**
- **AnimatedSwitcher** (300ms): Smooth transition between collapsed/expanded ETA displays
- **AnimatedSize** (300ms): Smooth appearance/disappearance of action buttons
- **Loading Animation** (1.5s minimum): Ensures visible feedback during auto-refetch

## State Management

### New State Variable
```dart
bool _shouldShowRefreshAnimation = false;  // Controls loading state during auto-refetch
```

### State Flags
- `_isExpanded`: Tracks card expansion state
- `_etaRefreshing`: Tracks manual refresh button state (separate from auto-refresh)

## User Experience Flow

```
User taps stop card
  ↓
Card expands (smooth animation)
  ↓
Auto-refetch triggered immediately
  ↓
"Fetching..." spinner shown (min 1.5s)
  ↓
ETAs loaded and displayed (or "No upcoming buses" if empty)
  ↓
Spinner fades out, ETAs visible
  ↓
User can manually refresh via button or collapse card
```

## Benefits

1. **No Manual Toggle Button**: Auto-refetch is seamless, happens automatically on expand
2. **Cleaner Collapsed State**: Compact "No buses" text instead of empty space
3. **Visual Feedback**: Loading animation clearly indicates data is being fetched
4. **Minimal Disruption**: Silently handles errors, no error snackbars for auto-refresh
5. **Smooth Transitions**: All state changes animated for polished UX
6. **Language Support**: Full English/Traditional Chinese support for all text
7. **Responsive**: Adapts to Material 3 theme colors and Dark mode

## Implementation Details

### Refetch Flow
1. User expands card → `_toggleExpanded()` called
2. `_isExpanded = true` and `_autoRefetchOnExpand()` triggered
3. `_shouldShowRefreshAnimation = true` → Shows spinner UI
4. `Kmb.fetchStopEta(stopId)` called asynchronously
5. Waits minimum 1.5 seconds for smooth visual feedback
6. `_shouldShowRefreshAnimation = false` → Hides spinner, shows ETAs
7. Parent widget receives updated ETAs via `widget.etas` parameter

### Manual Refetch
- Separate `_manualRefetchStopEta()` method for Refresh button
- Uses `_etaRefreshing` flag (doesn't interfere with auto-refetch state)
- Shorter animation duration (800ms) for manual refresh

## Files Modified
- `lib/kmb_route_status_page.dart`
  - `_ExpandableStopCardState` class (Lines ~2535-2950)

## Testing Checklist
- [ ] Expand card → Auto-refetch triggers with spinner
- [ ] Spinner shows for at least 1.5 seconds
- [ ] ETAs display after loading completes
- [ ] Empty state shows "No upcoming buses" when applicable
- [ ] Manual Refresh button works independently
- [ ] Collapse card → Shows "No buses" placeholder
- [ ] Dark mode colors look correct
- [ ] Animations are smooth (no jank)
- [ ] Language toggle works (EN/TC)
