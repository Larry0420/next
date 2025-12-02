# ETA Fetch Issue Analysis - kmb_route_status_page.dart

## Problem Summary
The ETA data is cached using the wrong key (`seq` instead of `stop`/`stopId`), causing mismatches when looking up ETAs for stop cards.

## Current Flow

### 1. ETA Cache Building (_fetchRouteEta - Lines 1345-1369)
```dart
// Build O(1) lookup cache: HashMap seq -> List<ETA>
final Map<String, List<Map<String, dynamic>>> etaBySeq = {};

for (final e in entries) {
  final seqNum = e['seq']?.toString() ?? '';
  if (seqNum.isEmpty) continue;
  
  etaBySeq.putIfAbsent(seqNum, () => []).add(Map<String, dynamic>.from(e));
}
```
**Issue**: Uses `e['seq']` as the key

### 2. ETA Cache Usage (Lines 1747, 1856)
```dart
// Line 1747 in _buildVariantStationList
final List<Map<String, dynamic>> etas = etaByStop[seq] ?? [];

// Line 1856 in _buildOptimizedStationList  
final List<Map<String, dynamic>> etas = etaByStop[seq] ?? [];
```
**Issue**: Looks up using `seq` (which is the stop sequence number)

## Root Cause
The API response structure likely uses:
- `seq`: Stop sequence number (e.g., 1, 2, 3...)
- `stop`: Stop ID/code (e.g., "HK12345", "KL98765")

The ETA entries from `Kmb.fetchRouteEta()` contain a `stop` field (the stop identifier), not multiple entries per sequence. The cache needs to be keyed by stop ID to match ETAs to stops correctly.

## Evidence
1. **Stop card builder** (Line 1731-1747):
   - Extracts `stopId` from stop data: `final stopId = s['stop']?.toString() ?? '';`
   - Uses `seq` for ETA lookup: `final List<Map<String, dynamic>> etas = etaByStop[seq] ?? [];`
   
2. **ETA cache structure** assumes:
   - Key = `seq` (stop sequence number)
   - Value = List of ETAs for that sequence
   
3. **But the data structure likely is**:
   - ETA entries have a `stop` field (the stop ID)
   - Multiple ETAs can exist for the same stop (different routes/destinations)
   - Should be keyed by `stop`, not `seq`

## Fix Required
Change the ETA cache key from `seq` to `stop`:

```dart
// In _fetchRouteEta (Line 1345)
final Map<String, List<Map<String, dynamic>>> etaByStop = {}; // Changed variable name

for (final e in entries) {
  // Filter by direction if selected
  if (selectedBoundChar != null) {
    final etaBound = e['dir']?.toString().trim().toUpperCase() ?? '';
    if (etaBound.isEmpty || etaBound[0] != selectedBoundChar) continue;
  }
  
  final stopId = e['stop']?.toString() ?? ''; // Use 'stop' instead of 'seq'
  if (stopId.isEmpty) continue;
  
  etaByStop.putIfAbsent(stopId, () => []).add(Map<String, dynamic>.from(e));
}
```

Then update lookups to use `stopId` instead of `seq`:

```dart
// In _buildVariantStationList and _buildOptimizedStationList
final List<Map<String, dynamic>> etas = etaByStop[stopId] ?? [];
```

## Impact
- **Current**: ETAs not found for stops (empty lists returned)
- **After Fix**: ETAs correctly associated with their respective stops
