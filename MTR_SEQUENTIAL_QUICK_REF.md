# MTR Sequential Operations - Quick Reference

## ✅ What Was Fixed

**Before**: Multiple refresh operations could run in parallel (race conditions, wasted resources)  
**After**: Sequential execution with priority-based queuing (O(1) complexity, smooth UX)

## Priority Levels

```dart
// In code:
_PendingOperation.priorityAutoRefresh = 0;   // Background timer
_PendingOperation.priorityUserAction = 10;   // Station selection
_PendingOperation.priorityManualRefresh = 20; // Pull-to-refresh
```

| Priority | When Used | Overrides |
|----------|-----------|-----------|
| **20** | Pull-to-refresh | Everything |
| **10** | User selects station/line | Auto-refresh only |
| **0** | Auto-refresh timer | Nothing (gets discarded) |

## How It Works

```
Request comes in
    ↓
Operation in progress?
    ├─ NO → Execute now
    └─ YES → Check priority
              ├─ Higher/Equal? → Replace pending
              └─ Lower? → Discard
```

## Code Usage

### Auto-refresh (Background)
```dart
schedule.loadSchedule(
  lineCode,
  stationCode,
  priority: _PendingOperation.priorityAutoRefresh, // 0
  silentRefresh: true,
);
```

### User Action (Station/Line Selection)
```dart
schedule.loadSchedule(
  lineCode,
  stationCode,
  priority: _PendingOperation.priorityUserAction, // 10
  forceRefresh: true,
);
```

### Manual Refresh (Pull-to-Refresh)
```dart
schedule.manualRefresh(lineCode, stationCode);
// Internally uses priority 20 (highest)
```

## Real-World Examples

### Example 1: User Rapidly Taps Stations
```
Tap Central → Starts loading
Tap Admiralty (while Central loading) → Queued
Tap Wan Chai (while Central loading) → Replaces Admiralty in queue
Central completes → Wan Chai starts immediately
Result: Only Central and Wan Chai load (Admiralty skipped)
```

### Example 2: Auto-refresh During User Action
```
Auto-refresh timer fires → Starts loading
User taps new station → Queued (higher priority)
Auto-refresh completes → User's station starts immediately
Result: User's selection not delayed by auto-refresh
```

### Example 3: Pull-to-Refresh Overrides All
```
Auto-refresh running → Loading old data
User pulls to refresh → Queued (highest priority)
Auto-refresh completes → Manual refresh starts immediately
Result: Fresh data loaded, ignoring any pending auto-refresh
```

## Key Benefits

### Performance
- ✅ **O(1) complexity** - Constant time/space
- ✅ **No parallel requests** - Single network call at a time
- ✅ **Auto-discard stale** - Old requests replaced automatically

### User Experience
- ✅ **No race conditions** - Deterministic data updates
- ✅ **Smooth UI** - No flickering between datasets
- ✅ **Responsive** - Latest action always wins

### Resource Usage
- ✅ **Minimal memory** - Single pending operation
- ✅ **Reduced bandwidth** - Only essential requests
- ✅ **Better battery** - Fewer concurrent operations

## Debug Logging

Enable debug logging to see operation flow:

```
[MTR Schedule] Starting operation (priority: 10)
[MTR Schedule] Operation in progress, queuing request (priority: 20)
[MTR Schedule] Replacing pending operation (old: 0, new: 20)
[MTR Schedule] Processing pending operation (priority: 20)
```

## Testing

### Quick Verification Steps

1. **Sequential Execution**
   - Tap station → See loading
   - Immediately tap another station
   - Verify: No parallel loading spinners

2. **Priority Replacement**
   - Let auto-refresh run
   - Pull to refresh mid-operation
   - Verify: Manual refresh executes after auto-refresh

3. **Rapid Selection**
   - Rapidly tap through 10 stations
   - Verify: Only first and last stations load data

## Common Patterns

### Pattern 1: Initialization with User Preference
```dart
// Initial load when app starts
schedule.loadSchedule(
  lineCode,
  stationCode,
  priority: _PendingOperation.priorityUserAction, // Medium priority
);
```

### Pattern 2: Background Auto-refresh
```dart
Timer.periodic(Duration(seconds: 30), (_) {
  schedule.loadSchedule(
    lineCode,
    stationCode,
    priority: _PendingOperation.priorityAutoRefresh, // Low priority
    silentRefresh: true,
  );
});
```

### Pattern 3: User Interaction
```dart
onStationChanged: (station) {
  schedule.loadSchedule(
    lineCode,
    station.stationCode,
    priority: _PendingOperation.priorityUserAction, // Medium priority
    forceRefresh: true,
  );
}
```

## Complexity Analysis

| Component | Time | Space | Explanation |
|-----------|------|-------|-------------|
| `loadSchedule()` | O(1) | O(1) | Single lock check + replace |
| Priority check | O(1) | - | Integer comparison |
| Queue storage | O(1) | O(1) | Single object (not a list) |
| **Total** | **O(1)** | **O(1)** | Constant regardless of load |

## Architecture Diagram

```
┌─────────────────────────────────────────┐
│          loadSchedule()                 │
│  Parameters: lineCode, stationCode,     │
│             priority, ...               │
└──────────────┬──────────────────────────┘
               │
         ┌─────┴──────┐
         │ Lock Check │
         └─────┬──────┘
               │
       ┌───────┴────────┐
       │ Locked?        │
       ├────────────────┤
       │ NO  → Execute  │
       │ YES → Queue    │
       │       (by pri) │
       └───────┬────────┘
               │
         ┌─────┴──────┐
         │ Execute    │
         │ Network    │
         │ Request    │
         └─────┬──────┘
               │
         ┌─────┴──────┐
         │ Release    │
         │ Lock       │
         └─────┬──────┘
               │
         ┌─────┴──────┐
         │ Process    │
         │ Pending    │
         │ (if any)   │
         └────────────┘
```

## Files Modified

- `lib/mtr_schedule_page.dart`
  - Added `_PendingOperation` class with priority levels
  - Added `_isOperationInProgress` lock
  - Added `_pendingOperation` queue (single item)
  - Refactored `loadSchedule()` to use sequential execution
  - Updated `startAutoRefresh()` with priority 0
  - Updated `manualRefresh()` with priority 20
  - Updated all user actions with priority 10

## Related Documentation

- `MTR_SEQUENTIAL_OPERATION_SYSTEM.md` - Full technical documentation
- `SEAMLESS_REFRESH_OPTIMIZATION.md` - Background refresh details
- `NETWORK_OPTIMIZATION_GUIDE.md` - Network resilience patterns

---

**Date**: October 18, 2025  
**Complexity**: O(1) time and space  
**Status**: ✅ Production Ready
