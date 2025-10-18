# MTR Auto-load Setting - Quick Reference

## What's New?
Added a toggle in **Settings** to control whether the MTR page automatically loads your last selected station.

## Where to Find It?
**Settings → Developer Settings → "Auto-load Last MTR Station"**

## Quick Decision Guide

### Enable (Default) ✅
**Best for**: Regular commuters checking the same station daily
- Opens app → Schedule loads immediately
- Auto-refresh starts automatically (if enabled)
- Fastest experience for routine use

### Disable ⚠️
**Best for**: Users who want to browse different stations
- Opens app → Shows station list first
- Must manually select a station
- Better for exploring or checking multiple stations

## Behavior Changes

| Setting | Page Load | Schedule | Auto-refresh |
|---------|-----------|----------|--------------|
| **ON** (default) | Last station | Loads immediately | Starts automatically |
| **OFF** | Station list | Waits for selection | Starts after selection |

## Example Use Cases

### ✅ Daily Commuter (Enable)
```
You: "I check Central Station every morning"
App: Opens → Shows Central Station schedule → Done
```

### 📋 Explorer (Disable)
```
You: "I want to see different stations today"
App: Opens → Shows all stations → You pick one → Shows schedule
```

## How It Works

```
┌──────────────────────────────────────┐
│ App Starts / Restart                 │
└──────────────┬───────────────────────┘
               │
       ┌───────┴────────┐
       │ Load Providers │
       │ 1. MTR Catalog │
       │ 2. Settings    │
       └───────┬────────┘
               │
┌──────────────┴──────────────────────┐
│ User Opens MTR Schedule Page        │
└──────────────┬──────────────────────┘
               │
       ┌───────┴────────┐
       │ Check Setting  │
       └───────┬────────┘
               │
    ┌──────────┴──────────┐
    │                     │
    ▼                     ▼
┌───────┐            ┌─────────┐
│ ON    │            │ OFF     │
├───────┤            ├─────────┤
│ Load  │            │ Show    │
│ Last  │            │ Default │
│ Cache │            │ Station │
└───┬───┘            └────┬────┘
    │                     │
    │ Auto-load          │ User must
    │ schedule           │ select first
    ▼                     ▼
┌─────────────────────────────┐
│ Display Schedule & Start    │
│ Auto-refresh (if enabled)   │
└─────────────────────────────┘
```

## App Restart Behavior ⚠️

**Important**: This setting works correctly even after app restart!

### How It Handles Restart:
1. **App starts** → Providers initialize
2. **Catalog loads** → Sets temporary default (first station)
3. **Settings load** → User preference loaded
4. **User opens MTR page** → Preference applied
   - If **ON**: Loads cached station (replaces default)
   - If **OFF**: Keeps default station (user can browse)

✅ No race condition - setting always respected!

## Testing Steps

1. **Enable Setting**
   - Go to Settings → Toggle ON
   - Exit to main screen
   - Open MTR page → Should see last station schedule

2. **Disable Setting**
   - Go to Settings → Toggle OFF
   - Exit to main screen
   - Open MTR page → Should see default (first) station
   - Select a station → Should load schedule

3. **Verify Persistence**
   - Change setting
   - Close app completely
   - Reopen app → Setting should persist

4. **App Restart Test** ⭐ **IMPORTANT**
   - Toggle setting to OFF
   - Kill app completely (swipe away from recents)
   - Reopen app
   - Navigate to MTR page → Should respect OFF setting (show default station)
   - Go to Settings → Toggle to ON
   - Navigate back to MTR page → Should now show cached station

## Default Value
**Enabled (`true`)** - Maintains existing behavior for current users

## Files Modified
- `lib/main.dart` (DeveloperSettingsProvider + UI)
- `lib/mtr_schedule_page.dart` (Catalog provider + page state)

## Related Settings
- **MTR Auto-refresh**: Works with this setting (only starts when schedule is loaded)
- **Show MTR Arrival Details**: Display preference (unaffected by this setting)

---
**Date**: October 18, 2025  
**Status**: ✅ Ready to Test
