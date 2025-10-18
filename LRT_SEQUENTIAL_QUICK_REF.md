# LRT Sequential Operation System - Quick Reference

## 🎯 Purpose
Prevent data corruption and race conditions during rapid LRT station/route switching by enforcing sequential operation execution with intelligent priority handling.

## 🔑 Key Concepts

### Sequential Execution
- **Only 1 operation at a time** (no parallel loads)
- **O(1) space**: Single pending operation queue
- **Deterministic**: Operations execute in priority order

### Priority System (Higher Number = Higher Priority)

| Priority | Constant | Use Case | Example |
|----------|----------|----------|---------|
| **0** | `priorityAutoRefresh` | Background timer | 30-second auto-refresh |
| **10** | `priorityRouteSwitch` | Route selection | User changed route |
| **15** | `priorityStationSwitch` | Station selection | User clicked station, app resumed |
| **20** | `priorityManualRefresh` | Pull-to-refresh | User manually refreshed |

## 📝 How to Use

### Basic Usage (No Priority Specified)
```dart
// Uses default priority (10 - route switch)
await scheduleProvider.load(stationId);
```

### With Explicit Priority
```dart
// Auto-refresh (priority 0 - lowest)
await scheduleProvider.load(
  stationId,
  forceRefresh: true,
  priority: _LrtPendingOperation.priorityAutoRefresh,
);

// Route switch (priority 10)
await scheduleProvider.load(
  stationId,
  priority: _LrtPendingOperation.priorityRouteSwitch,
);

// Station switch (priority 15)
await scheduleProvider.load(
  stationId,
  priority: _LrtPendingOperation.priorityStationSwitch,
);

// Manual refresh (priority 20 - highest)
await scheduleProvider.load(
  stationId,
  forceRefresh: true,
  priority: _LrtPendingOperation.priorityManualRefresh,
);
```

## 🔄 Execution Flow

### When Operation is Free
```
load(stationId, priority: X)
  ↓
No operation in progress
  ↓
Lock → Execute → Unlock
  ↓
Check pending → Execute if exists
```

### When Operation is In Progress
```
load(stationId, priority: X)
  ↓
Operation locked (busy)
  ↓
Compare priorities:
  - X >= pending priority → QUEUE (replace existing)
  - X < pending priority → DISCARD (ignore)
  ↓
Return immediately (don't block)
```

## 🎯 Priority Behavior

### Higher Priority Replaces Lower
```
Operation A (priority 10) in progress
User clicks → Operation B (priority 15)
  ↓
Result: B queued, will execute after A
```

### Lower Priority Discarded
```
Operation A (priority 15) in progress
Pending: Operation B (priority 15)
Timer triggers → Operation C (priority 0)
  ↓
Result: C discarded, B remains queued
```

### Same Priority Replaces
```
Operation A (priority 15) in progress
Pending: Operation B (priority 15)
User clicks → Operation C (priority 15)
  ↓
Result: C replaces B (latest action wins)
```

## 📍 Call Sites

### 1. Auto-Refresh Timer (Priority 0)
**Location**: `startAutoRefresh()` ~line 2994
```dart
_autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
  if (_currentStationId != null) {
    await load(_currentStationId!, 
      forceRefresh: true,
      priority: _LrtPendingOperation.priorityAutoRefresh,
    );
  }
});
```

### 2. Route Switch (Priority 10)
**Location**: `load()` default parameter ~line 3001
```dart
Future<void> load(
  int stationId, {
  bool forceRefresh = false,
  BuildContext? context,
  int priority = _LrtPendingOperation.priorityRouteSwitch,
}) async { /* ... */ }
```

### 3. Station Switch (Priority 15)
**Location**: Station selector ~line 9849
```dart
onTap: () {
  widget.scheduleProvider.load(
    station.id,
    priority: _LrtPendingOperation.priorityStationSwitch,
  );
  Navigator.pop(context);
}
```

**Location**: App resume ~line 3229
```dart
await load(_currentStationId!,
  forceRefresh: true,
  priority: _LrtPendingOperation.priorityStationSwitch,
);
```

### 4. Pull-to-Refresh (Priority 20)
**Location**: RefreshIndicator ~line 3527
```dart
onRefresh: () async {
  await sched.load(sched.currentStationId!,
    forceRefresh: true,
    priority: _LrtPendingOperation.priorityManualRefresh,
  );
}
```

## 🧪 Testing Checklist

- [ ] **Rapid Station Switching**: Click 3+ stations quickly → Last clicked loads
- [ ] **Auto-Refresh + User Action**: Timer fires, then click station → User action wins
- [ ] **Pull-to-Refresh During Auto-Refresh**: Should override background refresh
- [ ] **Route Switch + Station Switch**: Station switch should execute (higher priority)
- [ ] **No Flickering**: UI should show smooth transitions, no data jumping
- [ ] **Single Network Request**: Check network tab - max 1 concurrent request

## ⚠️ Common Pitfalls

### ❌ DON'T: Call without priority in time-sensitive code
```dart
// Bad - uses default priority 10, might be wrong for your use case
await load(stationId);
```

### ✅ DO: Specify priority explicitly
```dart
// Good - clear intent
await load(stationId, priority: _LrtPendingOperation.priorityStationSwitch);
```

### ❌ DON'T: Use priority 20 for background operations
```dart
// Bad - manual refresh priority for auto-refresh
await load(stationId, priority: _LrtPendingOperation.priorityManualRefresh);
```

### ✅ DO: Use appropriate priority for operation type
```dart
// Good - auto-refresh gets lowest priority
await load(stationId, priority: _LrtPendingOperation.priorityAutoRefresh);
```

## 📊 Performance

| Metric | Value | Description |
|--------|-------|-------------|
| **Space Complexity** | O(1) | Only 2 sync fields |
| **Time Complexity** | O(1) | Single comparison |
| **Max Concurrent Requests** | 1 | Sequential execution |
| **Max Queue Size** | 1 | Single pending operation |

## 🔍 Debugging

### Check If System is Working
1. Rapid station switching → Should see only first + last load (middle ones cancelled)
2. Network tab → Max 1 request at a time
3. No UI flickering between different stations
4. Auto-refresh doesn't interrupt user navigation

### Debug Logging (Optional)
Add to `load()` method:
```dart
if (_isOperationInProgress) {
  print('⏳ Busy - Queuing: station=$stationId, priority=$priority');
  if (_pendingOperation != null) {
    print('   Replacing: station=${_pendingOperation!.stationId}, priority=${_pendingOperation!.priority}');
  }
}
```

## 📚 Related Docs

- **`LRT_SEQUENTIAL_OPERATION_SYSTEM.md`**: Complete technical specification
- **`MTR_SEQUENTIAL_OPERATION_SYSTEM.md`**: MTR equivalent implementation
- **`NETWORK_OPTIMIZATION_GUIDE.md`**: Overall network optimization strategies

## 💡 Quick Decision Guide

**Which priority should I use?**

```
Is it a background timer?
  → Priority 0 (priorityAutoRefresh)

Is the user changing routes?
  → Priority 10 (priorityRouteSwitch)

Is the user selecting a station or app resumed?
  → Priority 15 (priorityStationSwitch)

Is the user pulling to refresh?
  → Priority 20 (priorityManualRefresh)
```

## ✅ Success Criteria

The system is working correctly when:
- ✅ Only latest user action loads (intermediate cancelled)
- ✅ Background refresh never overrides user action
- ✅ No data corruption during rapid switching
- ✅ Max 1 network request at a time
- ✅ Smooth UI transitions without flickering
- ✅ Pull-to-refresh always gets fresh data

---

**Last Updated**: Implementation complete
**Status**: ✅ Active - All call sites updated
**Code Location**: `lib/main.dart` ~line 2755-3527
