# MTR Auto-load Cached Selection Setting

## Overview
Added a new toggle in settings to control whether the MTR schedule page automatically loads the last selected station or shows the station list for manual selection.

## Feature Details

### Setting Location
**Settings → Developer Settings → Auto-load Last MTR Station**

### Behavior

#### When Enabled (Default)
- ✅ Automatically loads your last selected line and station
- ✅ Immediately shows train schedule for that station
- ✅ Auto-refresh starts automatically (if enabled)
- ✅ Saves time for frequent users checking the same station

#### When Disabled
- 📋 Shows the station list on page load
- 👆 User must manually select a station to view schedule
- ⏸️ Auto-refresh does NOT start until a station is selected
- 🆕 Better for users who want to browse different stations

## User Benefits

### For Regular Commuters (Enable)
- **Faster access**: Jump directly to your usual station's schedule
- **No extra taps**: Schedule loads immediately
- **Consistent experience**: Always see your home/work station first

### For Explorers (Disable)
- **Browse freely**: View station list without auto-loading
- **Compare stations**: Easier to check multiple stations
- **Privacy**: Don't auto-reveal last checked station

## Technical Implementation

### Files Modified

1. **`main.dart`** - DeveloperSettingsProvider
   - Added `_mtrAutoLoadCachedSelectionKey` constant
   - Added `_mtrAutoLoadCachedSelection` boolean field (default: `true`)
   - Added `mtrAutoLoadCachedSelection` getter
   - Added `setMtrAutoLoadCachedSelection()` method
   - Added UI toggle in settings page

2. **`mtr_schedule_page.dart`** - MtrCatalogProvider & _MtrSchedulePageState
   - Added `_hasAppliedUserPreference` flag to track preference application
   - Modified `_loadMtrData()` to accept `loadCachedSelection` parameter
   - Updated constructor to NOT auto-load cached selection
   - Added `initializeWithSettings()` method to apply preference after settings are ready
   - Added `reloadWithSettings()` method for re-initialization
   - Removed `applyCachedSelection()` method (replaced with `initializeWithSettings()`)
   - Modified `_MtrSchedulePageState.initState()` to call `_initializeCatalogAndSchedule()`
   - Updated `_initializeCatalogAndSchedule()` to call `catalog.initializeWithSettings()`
   - Modified `_loadScheduleIfNeeded()` to respect auto-load setting
   - Modified `didChangeDependencies()` to respect auto-load setting

### Code Flow

```
App Starts
    ↓
MtrCatalogProvider constructor
    ↓
Load JSON data (WITHOUT cached selection)
    ↓
Set to first line/station (temporary default)
    ↓
DeveloperSettingsProvider initializes
    ↓
User opens MTR page
    ↓
_initializeCatalogAndSchedule() called
    ↓
catalog.initializeWithSettings(autoLoadEnabled)
    ↓
┌─────────────────────────────────────────────┐
│ Auto-load ENABLED?                          │
├─────────────────────────────────────────────┤
│ YES → Load cached line/station              │
│       → Load schedule data                  │
│       → Start auto-refresh (if enabled)     │
│                                             │
│ NO  → Keep first line/station (default)    │
│       → Show station list                   │
│       → Wait for user selection             │
│       → Then load schedule                  │
└─────────────────────────────────────────────┘
```

## Settings UI

### English
- **Title**: "Auto-load Last MTR Station"
- **Subtitle (ON)**: "Automatically load your last selected station"
- **Subtitle (OFF)**: "Start with station list (manual selection)"

### 中文
- **標題**: "自動載入上次港鐵站"
- **副標題（開啟）**: "自動載入您上次選擇的車站"
- **副標題（關閉）**: "從車站列表開始（手動選擇）"

## Default Value
**`true`** (enabled) - Maintains current behavior for existing users while providing opt-out for new use case.

## Use Cases

### Case 1: Daily Commuter ✅ (Default)
*"I check the same station every day (my work station)"*
- **Setting**: Enable auto-load
- **Experience**: Opens app → Sees schedule immediately → Done

### Case 2: Tourist/Explorer ⚠️
*"I want to explore different stations without the app remembering"*
- **Setting**: Disable auto-load
- **Experience**: Opens app → Sees station list → Chooses station → Views schedule

### Case 3: Multiple Routine Stations 🔄
*"I alternate between 2-3 stations daily"*
- **Setting**: Enable auto-load
- **Experience**: Opens app → Sees last station → Tap station selector → Switch easily

## Testing Checklist

- [ ] Toggle setting ON → Close app → Reopen → Verify last station loads
- [ ] Toggle setting OFF → Close app → Reopen → Verify station list shown (first station selected by default)
- [ ] With setting OFF → Select station → Verify schedule loads
- [ ] With setting OFF → Verify auto-refresh does NOT start until selection
- [ ] With setting ON → Verify auto-refresh starts immediately (if enabled)
- [ ] Change setting → Navigate to MTR page → Verify behavior changes
- [ ] Verify setting persists across app restarts
- [ ] **App Restart Test**: Kill app completely → Reopen → Navigate to MTR page → Verify setting is respected

## Important: App Restart Behavior

### The Problem
When the app starts, providers initialize in this order:
1. `MtrCatalogProvider()` constructor runs (loads JSON data)
2. `DeveloperSettingsProvider()` initializes (loads user preferences)
3. User navigates to MTR page

This means the catalog provider can't check the setting during construction.

### The Solution
- **Constructor**: Loads JSON data WITHOUT applying cached selection
- **Default**: Sets to first line/station (temporary default)
- **Page Load**: Calls `initializeWithSettings()` which checks user preference
- **Flag**: `_hasAppliedUserPreference` ensures preference is only applied once

### Result
✅ Setting is respected on every app restart
✅ No race condition between provider initialization
✅ User preference applied at the right time (when page loads)

## Future Enhancements (Optional)

1. **Quick Switch Mode**: Add floating action button to quickly toggle between auto-load and manual browse
2. **Favorite Stations**: Save multiple favorite stations for quick access (with auto-load disabled)
3. **Smart Auto-load**: Auto-load only during commute hours (morning/evening)
4. **Station History**: Show recent stations when auto-load is disabled

## Related Documentation
- `SEAMLESS_REFRESH_OPTIMIZATION.md` - Auto-refresh behavior details
- `INTERCHANGE_UX_IMPROVEMENTS.md` - Station selector UX enhancements

---

**Implementation Date**: October 18, 2025  
**Status**: ✅ Complete  
**Default**: Enabled (maintains current UX)
