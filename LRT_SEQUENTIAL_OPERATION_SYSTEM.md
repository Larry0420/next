# LRT Sequential Operation System - Complete Technical Specification

## Overview

The LRT Sequential Operation System prevents data corruption and race conditions by ensuring only one schedule loading operation executes at a time, with intelligent priority-based queuing for pending requests.

## Problem Statement

### Issues Before Implementation

1. **Race Conditions**: Multiple parallel operations when rapidly switching between:
   - Districts
   - Routes
   - Stations
   - While auto-refresh active

2. **Data Corruption**: Stale responses completing after newer requests, causing:
   - Wrong station data displayed
   - Incorrect route information
   - UI state inconsistencies

3. **Resource Waste**: Multiple concurrent network requests for obsolete data

4. **Unpredictable Behavior**: No priority system meant background operations could override user actions

### Root Cause

The original implementation allowed unlimited parallel calls to `load()`:
- No coordination between auto-refresh timer and user actions
- No cancellation of obsolete requests
- No priority system for operation ordering
- Race conditions between lifecycle events (resume) and user interactions

## Solution Architecture

### Core Components

#### 1. Operation Lock (`_isOperationInProgress`)
```dart
bool _isOperationInProgress = false;
```
- **Purpose**: Prevent parallel operations (O(1) space)
- **Behavior**: Only one network request executes at a time
- **Guarantee**: Sequential, deterministic data updates

#### 2. Pending Operation Queue (`_pendingOperation`)
```dart
_LrtPendingOperation? _pendingOperation;
```
- **Purpose**: Store next operation while current one executes
- **Size**: Single item (O(1) space, not unlimited queue)
- **Logic**: Higher priority replaces lower priority in queue

#### 3. Priority System (`_LrtPendingOperation` class)
```dart
class _LrtPendingOperation {
  final int stationId;
  final bool forceRefresh;
  final int priority;
  final BuildContext? context;

  // Priority levels (higher number = higher priority)
  static const int priorityAutoRefresh = 0;      // Lowest - background timer
  static const int priorityRouteSwitch = 10;     // Medium - route selection
  static const int priorityStationSwitch = 15;   // High - station selection
  static const int priorityManualRefresh = 20;   // Highest - pull-to-refresh
}
```

### Execution Flow

#### Normal Operation (No Queue)
```
User clicks station
  ↓
load(stationId, priority: 15) called
  ↓
Check: _isOperationInProgress? → NO
  ↓
Set _isOperationInProgress = true (LOCK)
  ↓
Execute _executeLoad() → network request
  ↓
Update state, notifyListeners()
  ↓
Set _isOperationInProgress = false (UNLOCK)
  ↓
Check: _pendingOperation exists? → NO
  ↓
Done ✓
```

#### With Pending Operation (Priority Handling)
```
Scenario: Auto-refresh active (priority 0), user clicks station (priority 15)

Timer triggers auto-refresh
  ↓
load(stationA, priority: 0) called
  ↓
_isOperationInProgress = true (LOCKED)
  ↓
Executing _executeLoad(stationA)...
  │
  │ [While network request in progress]
  │
  ├─→ User clicks stationB
  │   ↓
  │   load(stationB, priority: 15) called
  │   ↓
  │   Check: _isOperationInProgress? → YES (LOCKED)
  │   ↓
  │   Check: priority (15) >= pending priority? → YES (no pending yet)
  │   ↓
  │   Queue: _pendingOperation = LrtPendingOperation(stationB, priority: 15)
  │   ↓
  │   Return (don't execute yet)
  │
  ↓
StationA data received, state updated
  ↓
_isOperationInProgress = false (UNLOCKED)
  ↓
Check: _pendingOperation exists? → YES
  ↓
Extract pending: stationB, priority 15
  ↓
Clear _pendingOperation = null
  ↓
Recursive call: load(stationB, priority: 15)
  ↓
Execute stationB load (user's desired station)
  ↓
Done ✓ (User sees correct station)
```

#### Priority Replacement (Stale Cancellation)
```
Scenario: Two rapid user actions while operation in progress

Operation in progress (stationA, priority 15)
  │
  ├─→ User clicks stationB (priority 15)
  │   ↓
  │   Queue: _pendingOperation = (stationB, priority: 15)
  │
  ├─→ User clicks stationC (priority 15) [before stationA completes]
  │   ↓
  │   Check: priority (15) >= pending priority (15)? → YES
  │   ↓
  │   REPLACE: _pendingOperation = (stationC, priority: 15)
  │   ↓
  │   Result: StationB request CANCELLED (never executed)
  │
  ↓
StationA completes
  ↓
Execute pending: stationC
  ↓
Done ✓ (Latest action wins, stationB skipped)
```

### Priority Assignment by Operation Type

| Operation Type | Priority | Constant | Use Case |
|---------------|----------|----------|----------|
| Auto-refresh timer | 0 | `priorityAutoRefresh` | Background 30s timer |
| Route switch | 10 | `priorityRouteSwitch` | User changed route |
| Station switch | 15 | `priorityStationSwitch` | User selected station, app resume |
| Pull-to-refresh | 20 | `priorityManualRefresh` | User manually refreshed |

### Priority Behavior Matrix

| Current Operation | Incoming Operation | Priority | Behavior |
|------------------|-------------------|----------|----------|
| Auto-refresh (0) | Station switch (15) | Incoming HIGHER | Queue station switch (will execute) |
| Station switch (15) | Auto-refresh (0) | Incoming LOWER | Discard auto-refresh (won't execute) |
| Station switch (15) | Station switch (15) | Same | Replace (latest wins) |
| Route switch (10) | Manual refresh (20) | Incoming HIGHER | Queue manual refresh |

## Implementation Details

### Modified Methods

#### `load()` - Entry Point with Priority
```dart
Future<void> load(
  int stationId, {
  bool forceRefresh = false,
  BuildContext? context,
  int priority = _LrtPendingOperation.priorityStationSwitch, // Default: user action
}) async {
  // If operation in progress, queue or discard based on priority
  if (_isOperationInProgress) {
    if (_pendingOperation == null || priority >= _pendingOperation!.priority) {
      _pendingOperation = _LrtPendingOperation(
        stationId: stationId,
        forceRefresh: forceRefresh,
        context: context,
        priority: priority,
      );
    }
    // Else: Lower priority, discard (don't queue)
    return;
  }

  // No operation in progress, execute immediately
  _isOperationInProgress = true;
  try {
    await _executeLoad(stationId, forceRefresh: forceRefresh, context: context);
  } finally {
    _isOperationInProgress = false;

    // Process pending operation if exists
    if (_pendingOperation != null) {
      final pending = _pendingOperation!;
      _pendingOperation = null;
      await load(
        pending.stationId,
        forceRefresh: pending.forceRefresh,
        context: pending.context,
        priority: pending.priority,
      );
    }
  }
}
```

#### `_executeLoad()` - Internal Execution
```dart
Future<void> _executeLoad(
  int stationId, {
  bool forceRefresh = false,
  BuildContext? context,
}) async {
  // Original load logic moved here
  // - Update _currentStationId
  // - Set _isLoading = true
  // - Make network request
  // - Handle success/error
  // - Update _schedules
  // - notifyListeners()
  // - Start auto-refresh if needed
}
```

### Call Site Updates

#### 1. Auto-Refresh Timer (Priority 0 - Lowest)
```dart
// Location: startAutoRefresh() ~line 2994
_autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
  if (_currentStationId != null) {
    await load(
      _currentStationId!,
      forceRefresh: true,
      priority: _LrtPendingOperation.priorityAutoRefresh, // Background refresh
    );
  }
});
```

#### 2. Route Switch (Priority 10 - Medium)
```dart
// Location: load() default parameter ~line 3001
Future<void> load(
  int stationId, {
  bool forceRefresh = false,
  BuildContext? context,
  int priority = _LrtPendingOperation.priorityRouteSwitch, // Default for route changes
}) async {
  // ...
}
```

#### 3. Station Switch & App Resume (Priority 15 - High)
```dart
// Location: _checkAndStartAutoRefresh() ~line 3205
if (_currentStationId != null) {
  await load(
    _currentStationId!,
    forceRefresh: true,
    priority: _LrtPendingOperation.priorityStationSwitch, // User action / resume
  );
}

// Location: didChangeAppLifecycleState() ~line 3229
await load(
  _currentStationId!,
  forceRefresh: true,
  priority: _LrtPendingOperation.priorityStationSwitch, // App resumed
);

// Location: Station selector ~line 9849
onTap: () {
  widget.scheduleProvider.load(
    station.id,
    priority: _LrtPendingOperation.priorityStationSwitch, // User selected
  );
  Navigator.pop(context);
}
```

#### 4. Pull-to-Refresh (Priority 20 - Highest)
```dart
// Location: RefreshIndicator ~line 3527
onRefresh: () async {
  await sched.load(
    sched.currentStationId!,
    forceRefresh: true,
    priority: _LrtPendingOperation.priorityManualRefresh, // Highest priority
  );
}
```

## Performance Characteristics

### Space Complexity
- **O(1)**: Only 2 fields for synchronization
  - `_isOperationInProgress`: 1 boolean
  - `_pendingOperation`: 1 object or null
  - No lists, no unlimited queue

### Time Complexity
- **O(1)**: Priority check and queue update
  - Simple comparison: `priority >= _pendingOperation!.priority`
  - Single object assignment
  - No iteration, no sorting

### Resource Optimization
- **Network**: Maximum 1 concurrent request at a time
- **Memory**: Constant space usage regardless of request frequency
- **CPU**: Minimal overhead (boolean checks, single comparison)

## Benefits

### Before vs After

| Aspect | Before | After |
|--------|--------|-------|
| **Parallel Operations** | Unlimited | Max 1 (sequential) |
| **Queue Size** | N/A (all run) | Max 1 (O(1)) |
| **Data Corruption** | Frequent | Eliminated |
| **Race Conditions** | Common | Impossible |
| **Resource Usage** | High (N requests) | Low (1 request) |
| **User Experience** | Unpredictable | Deterministic |
| **Stale Requests** | Execute anyway | Cancelled if lower priority |

### Specific Improvements

1. **Rapid Station Switching**: Latest selection always wins
2. **Auto-Refresh Overlap**: Background refresh never overrides user action
3. **App Resume**: Resume + user action = user action wins
4. **Pull-to-Refresh**: Manual refresh overrides everything
5. **Network Efficiency**: No wasted requests for obsolete data

## Testing Scenarios

### Scenario 1: Rapid Station Switching
**Steps:**
1. Click Station A (priority 15)
2. Immediately click Station B (priority 15)
3. Immediately click Station C (priority 15)

**Expected Behavior:**
- Station A starts loading (locked)
- Station B queued (replaces nothing)
- Station C queued (replaces B)
- Station A completes → UI shows A briefly
- Station C loads → UI shows C
- **Result**: Station B never executed (cancelled)

### Scenario 2: Auto-Refresh + User Action
**Steps:**
1. Auto-refresh timer triggers (priority 0)
2. While loading, user clicks station (priority 15)

**Expected Behavior:**
- Auto-refresh starts loading (locked)
- User action queued (priority 15 > 0)
- Auto-refresh completes → UI shows auto-refresh data
- User action executes → UI shows user's station
- **Result**: User's choice wins

### Scenario 3: Pull-to-Refresh During Auto-Refresh
**Steps:**
1. Auto-refresh timer triggers (priority 0)
2. User pulls to refresh (priority 20)

**Expected Behavior:**
- Auto-refresh starts loading (locked)
- Manual refresh queued (priority 20 > 0)
- Auto-refresh completes
- Manual refresh executes with forceRefresh=true
- **Result**: Fresh data from manual refresh

### Scenario 4: Multiple Actions During Long Network Request
**Steps:**
1. Click Station A (priority 15) - slow network
2. Change route (priority 10)
3. Click Station B (priority 15)
4. Pull to refresh (priority 20)

**Expected Behavior:**
- Station A starts (locked)
- Route change queued (priority 10)
- Station B replaces route (priority 15 >= 10)
- Manual refresh replaces Station B (priority 20 >= 15)
- Station A completes
- Manual refresh executes (only this one)
- **Result**: Only Station A + Manual refresh executed, route and Station B cancelled

## Debugging and Monitoring

### Debug Logging Points (Optional Implementation)
```dart
// When queuing:
print('Queued operation: stationId=$stationId, priority=$priority, replacing=${_pendingOperation?.priority}');

// When discarding:
print('Discarded operation: stationId=$stationId, priority=$priority < ${_pendingOperation!.priority}');

// When executing pending:
print('Executing pending: stationId=${pending.stationId}, priority=${pending.priority}');
```

### Key Indicators of Correct Behavior
- ✅ Only one loading indicator visible at a time
- ✅ Latest user action always completes
- ✅ No flickering between different station data
- ✅ Background refresh doesn't interrupt user navigation
- ✅ Network tab shows max 1 concurrent request

## Migration Notes

### Breaking Changes
None - all existing code continues to work with default priority.

### Backward Compatibility
- `load(stationId)` still works (uses default priority 10)
- Optional parameters preserve existing behavior
- No changes required for calling code

## Related Documentation

- **MTR Sequential Operation System**: Similar implementation for MTR schedule loading
- **MTR Sequential Quick Reference**: Quick reference for MTR system
- **Network Optimization Guide**: Overall network optimization strategies

## Maintenance

### Adding New Priority Levels
If you need to add a new priority level:

1. Add constant to `_LrtPendingOperation`:
```dart
static const int priorityNewOperation = 12; // Between route (10) and station (15)
```

2. Update call site with new priority:
```dart
await load(stationId, priority: _LrtPendingOperation.priorityNewOperation);
```

3. Update documentation with new priority level in tables

### Modifying Priority Values
If relative priorities need adjustment:
- Keep spacing between levels for future additions
- Update all documentation tables
- Test all scenarios to ensure expected behavior

## Summary

The LRT Sequential Operation System ensures **deterministic, corruption-free schedule loading** through:
- ✅ Sequential execution (no parallel operations)
- ✅ Priority-based queuing (user actions > background)
- ✅ O(1) space complexity (constant memory)
- ✅ Smart cancellation (obsolete requests dropped)
- ✅ Resource efficiency (minimal network/CPU usage)

This implementation eliminates race conditions, prevents data corruption, and provides a smooth user experience even during rapid interactions.
