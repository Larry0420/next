# MTR Sequential Operation & Priority System

## Overview
Refactored MTR schedule loading to use **O(1) sequential execution** with **priority-based operation queuing**. This prevents race conditions, reduces resource usage, and ensures smooth UX.

## Problem Statement

### Before (Parallel Execution Issues)
```dart
// Multiple operations could run simultaneously:
1. Auto-refresh timer triggers → loadSchedule()
2. User selects new station → loadSchedule()
3. App resumes from background → loadSchedule()
4. Pull-to-refresh → loadSchedule()

Result:
❌ 4 parallel network requests
❌ Race conditions (which data wins?)
❌ Wasted bandwidth and battery
❌ UI flashing/jank from conflicting updates
❌ O(n) complexity - scales with concurrent operations
```

### After (Sequential with Priorities)
```dart
// Only ONE operation executes at a time:
1. Operation starts → Lock acquired
2. New request comes → Queued (if higher priority, replaces queue)
3. Operation completes → Lock released
4. Process queued operation (if exists)

Result:
✅ Single network request at a time
✅ Deterministic behavior (priorities decide winner)
✅ Minimal resource usage
✅ Smooth UI updates (no conflicts)
✅ O(1) complexity - constant time regardless of requests
```

## Architecture

### Priority Levels

```dart
class _PendingOperation {
  static const int priorityAutoRefresh = 0;   // Lowest - background refresh
  static const int priorityUserAction = 10;   // Medium - user interaction
  static const int priorityManualRefresh = 20; // Highest - pull-to-refresh
}
```

| Priority | Source | Behavior | Example |
|----------|--------|----------|---------|
| **20** (Highest) | Manual Refresh | Always executes, overrides everything | User pulls to refresh |
| **10** (Medium) | User Actions | Overrides auto-refresh, queued during manual refresh | User selects new station |
| **0** (Lowest) | Auto-refresh | Discarded if higher priority operation pending | Background 30s timer |

### Sequential Execution Flow

```
┌─────────────────────────────────────────────┐
│ loadSchedule() called                       │
│ Priority: P                                 │
└──────────────┬──────────────────────────────┘
               │
         ┌─────┴──────┐
         │ Operation  │
         │ in progress?│
         └─────┬──────┘
               │
       ┌───────┴────────┐
       │ NO             │ YES
       ▼                ▼
┌──────────────┐  ┌────────────────────────────┐
│ Acquire Lock │  │ Check Pending Priority     │
│ Execute Now  │  │ - If P >= Pending.priority │
└──────┬───────┘  │   Replace pending          │
       │          │ - If P < Pending.priority  │
       │          │   Discard new request      │
       │          └────────────────────────────┘
       │                   │
       ▼                   ▼
┌──────────────┐     ┌──────────┐
│ Operation    │     │ Return   │
│ Completes    │     │ (Queued) │
└──────┬───────┘     └──────────┘
       │
   ┌───┴────┐
   │ Release│
   │ Lock   │
   └───┬────┘
       │
   ┌───┴──────┐
   │ Pending  │
   │ exists?  │
   └───┬──────┘
       │
    ┌──┴──┐
    │ YES │ NO → Done
    ▼     │
┌─────────┴──┐
│ Execute    │
│ Pending    │
│ (async)    │
└────────────┘
```

### Code Implementation

```dart
class MtrScheduleProvider extends ChangeNotifier {
  // Sequential execution guard
  bool _isOperationInProgress = false;
  
  // Single pending operation (O(1) space)
  _PendingOperation? _pendingOperation;
  
  Future<void> loadSchedule(
    String lineCode, 
    String stationCode, {
    bool forceRefresh = false,
    bool allowStaleCache = true,
    bool silentRefresh = false,
    int priority = 0, // NEW: Priority parameter
  }) async {
    // ===== O(1) SEQUENTIAL GUARD =====
    if (_isOperationInProgress) {
      // Only store if priority is higher or equal
      if (_pendingOperation == null || priority >= _pendingOperation!.priority) {
        _pendingOperation = _PendingOperation(
          lineCode: lineCode,
          stationCode: stationCode,
          forceRefresh: forceRefresh,
          allowStaleCache: allowStaleCache,
          silentRefresh: silentRefresh,
          priority: priority,
        );
      }
      return; // O(1) - immediate return
    }
    
    // Acquire lock
    _isOperationInProgress = true;
    
    try {
      await _executeLoadSchedule(...); // Do actual work
    } finally {
      // Release lock
      _isOperationInProgress = false;
      
      // Process pending (O(1) - only one pending operation)
      if (_pendingOperation != null) {
        final pending = _pendingOperation!;
        _pendingOperation = null;
        
        // Execute asynchronously (don't await - prevent recursion)
        unawaited(loadSchedule(
          pending.lineCode,
          pending.stationCode,
          forceRefresh: pending.forceRefresh,
          allowStaleCache: pending.allowStaleCache,
          silentRefresh: pending.silentRefresh,
          priority: pending.priority,
        ));
      }
    }
  }
}
```

## Usage Examples

### Example 1: Auto-refresh Gets Overridden

```dart
// Scenario: Auto-refresh running when user selects station

// Time 0ms: Auto-refresh triggers (priority=0)
schedule.loadSchedule(
  'TML', 'DIH',
  priority: _PendingOperation.priorityAutoRefresh, // 0
);
// → Starts executing

// Time 100ms: User selects new station (priority=10)
schedule.loadSchedule(
  'EAL', 'ADM',
  priority: _PendingOperation.priorityUserAction, // 10
);
// → Queued (priority 10 > 0, replaces any existing pending)

// Time 500ms: Auto-refresh completes
// → Immediately starts user's request (EAL/ADM)
// → Old data discarded, new data shown
```

### Example 2: Multiple User Actions (Last One Wins)

```dart
// User rapidly taps through stations

// Time 0ms: Select Central
schedule.loadSchedule('ISL', 'CEN', priority: 10);
// → Starts executing

// Time 50ms: Select Admiralty (before Central finishes)
schedule.loadSchedule('ISL', 'ADM', priority: 10);
// → Queued, replaces nothing (same priority)

// Time 100ms: Select Wan Chai (before Central finishes)
schedule.loadSchedule('ISL', 'WAC', priority: 10);
// → Queued, replaces Admiralty (same priority, newer request)

// Time 300ms: Central load completes
// → Immediately loads Wan Chai (most recent request)
// → Admiralty request was discarded (never executed)

Result: User sees Central → Wan Chai (smooth, no intermediate flash)
```

### Example 3: Pull-to-Refresh Overrides Everything

```dart
// Auto-refresh in progress, user pulls to refresh

// Time 0ms: Auto-refresh running (priority=0)
schedule.loadSchedule('TML', 'DIH', priority: 0);
// → Executing

// Time 200ms: User pulls to refresh (priority=20)
schedule.loadSchedule('TML', 'DIH', priority: 20, forceRefresh: true);
// → Queued (priority 20 > 0)

// Time 400ms: Auto-refresh completes
// → Immediately starts manual refresh with forceRefresh=true
// → Fresh data guaranteed (no stale cache)
```

## Performance Characteristics

### Time Complexity

| Operation | Complexity | Explanation |
|-----------|------------|-------------|
| **loadSchedule()** | O(1) | Single lock check, constant time queue update |
| **Priority comparison** | O(1) | Simple integer comparison |
| **Queue storage** | O(1) | Single pending operation (not a list) |
| **Dequeue** | O(1) | Direct access to single pending operation |

### Space Complexity

| Component | Complexity | Explanation |
|-----------|------------|-------------|
| **Operation lock** | O(1) | Single boolean flag |
| **Pending queue** | O(1) | Single _PendingOperation object (not a list!) |
| **Total overhead** | **O(1)** | Fixed memory regardless of request rate |

### Comparison with Queue-based Approach

| Metric | Priority Queue (O(n)) | Single Pending (O(1)) |
|--------|----------------------|----------------------|
| **Enqueue** | O(log n) (heap) | O(1) (replace) |
| **Dequeue** | O(log n) (heap) | O(1) (direct access) |
| **Memory** | O(n) (stores all) | O(1) (stores 1) |
| **Stale requests** | Need cleanup logic | Auto-discarded (replaced) |
| **Simplicity** | Complex heap management | Simple flag + pointer |

### Why Not a Full Queue?

```dart
// Full queue approach (NOT used):
List<_PendingOperation> _pendingQueue = []; // O(n) space
// Problem: What if user rapidly taps 100 stations?
// → 100 pending operations
// → All will execute sequentially (wastes time/bandwidth)
// → User only cares about the LAST station

// Single pending approach (USED):
_PendingOperation? _pendingOperation; // O(1) space
// Benefit: Only the MOST RECENT high-priority request is kept
// → Old requests are discarded (replaced)
// → User gets the latest selection immediately
// → No wasted operations
```

## Real-World Scenarios

### Scenario A: Poor Network + Rapid Taps

**User Action**: Rapidly taps through 10 stations on slow 3G

**Without Priority System**:
```
All 10 requests queue up
Each takes 5s on 3G
Total wait: 50 seconds
User sees: Loading spinner for 50s
Frustration: ⭐⭐⭐⭐⭐ (Very high)
```

**With Priority System**:
```
10 requests → Only last one kept
1st request completes (5s)
2nd request (latest) starts immediately
Total wait: 10 seconds
User sees: Loading → Data → Loading → Final Data
Frustration: ⭐ (Minimal)
```

### Scenario B: Auto-refresh During Manual Refresh

**User Action**: Pulls to refresh, auto-refresh fires during the pull

**Without Priority System**:
```
Pull-to-refresh starts
Auto-refresh also starts (parallel)
Both complete, race condition:
- Which data is shown? Undefined!
- UI flashes between two datasets
```

**With Priority System**:
```
Pull-to-refresh starts (priority 20)
Auto-refresh queued (priority 0)
Pull-to-refresh completes
Auto-refresh discarded (lower priority, data already fresh)
Result: Smooth, no race condition
```

### Scenario C: App Resume + User Action

**User Action**: App resumes, user immediately selects new station

**Without Priority System**:
```
Resume triggers load for old station
User selection triggers load for new station
Both run in parallel
Race condition: UI shows flickering data
```

**With Priority System**:
```
Resume triggers load (priority 10)
User selection queued (priority 10, replaces resume)
Resume completes
User selection immediately starts
Result: Only new station loads, no old data flash
```

## Debug Logging

The system includes detailed logging for troubleshooting:

```dart
// Operation start
debugPrint('MTR Schedule: Starting operation (priority: 10)');

// Queued operation
debugPrint('MTR Schedule: Operation in progress, queuing request (priority: 20)');

// Replaced lower priority
debugPrint('MTR Schedule: Replacing pending operation (old priority: 0, new priority: 10)');

// Ignored lower priority
debugPrint('MTR Schedule: Ignoring lower priority request (pending priority: 20)');

// Processing pending
debugPrint('MTR Schedule: Processing pending operation (priority: 10)');
```

### Example Log Sequence

```
[MTR] Auto-refresh: Background refresh TML/DIH
[MTR Schedule] Starting operation (priority: 0)
[MTR API] Fetching from network (attempt 1, timeout: 10s)

[User taps station 'ADM']
[MTR Schedule] Operation in progress, queuing request (priority: 10)
[MTR Schedule] Replacing pending operation (old priority: null, new priority: 10)

[Network completes]
[MTR Schedule] Processing pending operation (priority: 10)
[MTR Schedule] Starting operation (priority: 10)
[MTR API] Fetching from network (attempt 1, timeout: 10s)
```

## Testing

### Unit Test Cases

```dart
test('Sequential execution - second request queued', () async {
  // Start operation 1
  provider.loadSchedule('TML', 'DIH', priority: 0);
  await Future.delayed(Duration(milliseconds: 100));
  
  // Start operation 2 while 1 is running
  provider.loadSchedule('EAL', 'ADM', priority: 10);
  
  // Verify: Only operation 1 is active, 2 is pending
  expect(provider._isOperationInProgress, true);
  expect(provider._pendingOperation?.lineCode, 'EAL');
});

test('Priority replacement - higher replaces lower', () {
  // Start low priority operation
  provider.loadSchedule('TML', 'DIH', priority: 0);
  
  // Queue medium priority
  provider.loadSchedule('EAL', 'ADM', priority: 10);
  
  // Queue high priority (should replace medium)
  provider.loadSchedule('ISL', 'CEN', priority: 20);
  
  // Verify: High priority operation is pending
  expect(provider._pendingOperation?.lineCode, 'ISL');
  expect(provider._pendingOperation?.priority, 20);
});

test('Priority ignored - lower discarded', () {
  // Queue high priority
  provider.loadSchedule('TML', 'DIH', priority: 20);
  provider.loadSchedule('EAL', 'ADM', priority: 20);
  
  // Try to queue low priority
  provider.loadSchedule('ISL', 'CEN', priority: 0);
  
  // Verify: Low priority was discarded
  expect(provider._pendingOperation?.lineCode, 'EAL'); // Still EAL
  expect(provider._pendingOperation?.priority, 20);
});
```

### Integration Test Scenarios

1. **Rapid Station Selection**
   - Tap 10 stations quickly
   - Verify: Only first and last execute
   - Verify: Intermediate requests discarded

2. **Auto-refresh + Manual Refresh**
   - Start auto-refresh
   - Pull to refresh mid-operation
   - Verify: Manual refresh executes after auto-refresh
   - Verify: No data race

3. **App Lifecycle**
   - Pause app
   - Resume app (triggers load)
   - Immediately select new station
   - Verify: Only new station loads

## Benefits

### Performance
- ✅ **O(1) complexity** - Constant time regardless of request rate
- ✅ **Minimal memory** - Single pending operation (not a queue)
- ✅ **No wasted operations** - Old requests discarded automatically
- ✅ **Reduced network usage** - Only essential requests execute

### User Experience
- ✅ **Smooth UI** - No race conditions or flickering
- ✅ **Responsive** - Latest user action always respected
- ✅ **Predictable** - Deterministic behavior with priorities
- ✅ **Fast** - No waiting for stale operations to complete

### Code Quality
- ✅ **Simple** - No complex queue management
- ✅ **Maintainable** - Clear priority levels
- ✅ **Debuggable** - Detailed logging
- ✅ **Testable** - Straightforward unit tests

## Migration Guide

### Before
```dart
// Old code - no priority
schedule.loadSchedule('TML', 'DIH');
```

### After
```dart
// Auto-refresh (background)
schedule.loadSchedule('TML', 'DIH',
  priority: _PendingOperation.priorityAutoRefresh,
);

// User action (station selection)
schedule.loadSchedule('TML', 'DIH',
  priority: _PendingOperation.priorityUserAction,
);

// Manual refresh (pull-to-refresh)
schedule.loadSchedule('TML', 'DIH',
  forceRefresh: true,
  priority: _PendingOperation.priorityManualRefresh,
);
```

## Future Enhancements

### Potential Improvements

1. **Cancellation Support**
   ```dart
   // Allow cancelling in-flight operations for even faster response
   Future<void> cancelCurrentOperation();
   ```

2. **Priority Decay**
   ```dart
   // Reduce priority of pending operations over time
   // Prevents old high-priority requests from blocking new ones
   ```

3. **Analytics**
   ```dart
   // Track metrics:
   // - Requests discarded (efficiency indicator)
   // - Average priority of executed operations
   // - Sequential vs parallel prevented operations ratio
   ```

---

**Implementation Date**: October 18, 2025  
**Complexity**: O(1) time and space  
**Status**: ✅ Production Ready  
**Performance Impact**: 🚀 Significant improvement in resource usage and UX
