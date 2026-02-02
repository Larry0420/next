# Seq/Bound Alignment Fix

## Problem
The JSON may not be parsing correctly because `seq` is not properly aligned with `bound` (direction/dir). This causes:
- ETA lookup failures (composite key mismatch)
- Stops displaying with wrong ETAs or no ETAs
- Cross-bound ETA collisions

## Root Cause
The composite key format `"bound_seq"` (e.g., `"I_5"`, `"O_10"`) is used to map stops to their ETAs. When:
1. The bound field is missing or incorrectly extracted from the stop data
2. The composite key becomes malformed (e.g., `"_5"` instead of `"I_5"`)
3. ETA lookup fails and returns empty results

## Solution Implemented

### 1. **Strict Composite Key Validation**
- **Before**: Allowed empty bound keys → malformed keys like `"_5"`
- **After**: Skip stops/ETAs with missing bound → only create valid keys like `"I_5"`, `"O_5"`

```dart
// ✅ FIXED: ETAs are now skipped if bound cannot be determined
if (etaBoundChar == null || etaBoundChar.isEmpty) {
  debugPrint('⚠️  Warning: ETA seq=$seq has no bound information, skipping');
  continue; // Skip to maintain key consistency
}
final compositeKey = '${etaBoundChar}_$seq';
```

### 2. **Removed Fallback ETA Lookup**
- **Before**: `etaByStop[compositeKey] ?? etaByStop[seq] ?? []`  
  ❌ Fallback to seq-only causes cross-bound collisions
- **After**: `etaByStop[compositeKey] ?? []`  
  ✅ Only use composite key, fail gracefully with empty list

```dart
// ⚠️ NO MORE FALLBACK - this caused stops to show wrong ETAs
final List<Map<String, dynamic>> etas = compositeKey.isNotEmpty 
  ? (etaByStop[compositeKey] ?? [])
  : [];
```

### 3. **Enhanced Stop Deduplication**
Stops are now validated during deduplication:

```dart
// ✅ CRITICAL: Validate bound exists before using
final boundKey = normChar(stop['bound'] ?? stop['dir'] ?? stop['direction']);
if (boundKey == null || boundKey.isEmpty) {
  debugPrint('⚠️  Warning: Stop seq=$seq has no bound information');
  continue; // Skip invalid stops
}
final compositeKey = '${boundKey}_$seq';
```

## JSON Structure Requirements

### ✅ Correct Structure
```json
{
  "1": {
    "I": {
      "dest_en": "Central",
      "dest_tc": "中環",
      "stops": [
        {
          "seq": "1",
          "stop": "HK0001",
          "dir": "I",      // ← MUST be present
          "co": "CTB"
        },
        {
          "seq": "2",
          "stop": "HK0002",
          "dir": "I",      // ← Consistent with parent key
          "co": "CTB"
        }
      ]
    },
    "O": {
      "dest_en": "Stanley",
      "dest_tc": "赤柱",
      "stops": [
        {
          "seq": "1",
          "stop": "HK0100",
          "dir": "O",      // ← MUST match parent key
          "co": "CTB"
        }
      ]
    }
  }
}
```

### ❌ Invalid Structures

**Missing dir field:**
```json
{
  "stops": [
    { "seq": "1", "stop": "HK0001" }  // ❌ No dir/bound
  ]
}
```
Result: Stop skipped with warning

**Mismatched dir:**
```json
"I": {
  "stops": [
    { "seq": "1", "stop": "HK0001", "dir": "O" }  // ❌ dir doesn't match parent
  ]
}
```
Result: Bound extracted from dir field (correct, but inconsistent)

**Missing seq:**
```json
{
  "stops": [
    { "stop": "HK0001", "dir": "I" }  // ❌ No seq
  ]
}
```
Result: Stop skipped with warning

## Composite Key Format

The system uses composite keys throughout: `"bound_seq"`

### Key Construction
```
bound_seq = direction (I or O) + underscore + seq (numeric string)

Examples:
  "I_1"   ← Inbound stop 1
  "I_5"   ← Inbound stop 5
  "O_1"   ← Outbound stop 1
  "O_10"  ← Outbound stop 10
```

### Key Usage Points

| Location | Purpose | Format |
|----------|---------|--------|
| `_etaBySeqCache` | ETA storage by stop | `"I_5" → [eta1, eta2, ...]` |
| ETA lookup | Find ETAs for a stop | `etaByStop["I_5"]` |
| Stop deduplication | Handle same seq in different bounds | Prevents duplicates |
| Stop display | Match stop with its ETAs | `compositeKey` must be consistent |

## Data Flow with Seq/Bound Alignment

```
JSON Parsing:
  Route 1, Inbound
  └─ stop seq=5: { seq: "5", stop: "HK123", dir: "I" }
       ↓
Bound Extraction: normChar("I") → "I"
       ↓
Deduplication Key: "I_5"
       ↓
Stop Stored: uniqueStopsMap["I_5"] = stop

ETA Fetching:
  ETA: { seq: "5", stop: "HK123", bound: "I", eta: "14:35" }
       ↓
Bound Extraction: normChar("I") → "I"
       ↓
Cache Key: "I_5"
       ↓
ETA Stored: _etaBySeqCache["I_5"] = [{ eta_obj }]

ETA Lookup:
  Display stop with seq="5", bound="I"
       ↓
Build composite key: "I_5"
       ↓
etas = _etaBySeqCache["I_5"]  ✅ Match found!
       ↓
Display ETA: "5 min (14:35)"
```

## Validation Checklist

When populating/verifying JSON:

- ✅ All stops have a `seq` field (numeric string: "1", "2", "3")
- ✅ All stops have a `dir` or `bound` field
- ✅ `dir` field matches the parent direction key (I or O)
- ✅ `seq` values are unique within each route + direction
- ✅ `seq` values are in ascending order (1, 2, 3, ...)
- ✅ Parent structure has "I" and/or "O" keys
- ✅ `dest_en` and `dest_tc` provided for each direction

## Debugging

### Check logs for alignment issues:
```
⚠️  Warning: Stop seq=5 has no bound information: HK123
⚠️  Warning: ETA seq=5 has no bound information, skipping
⚠️  Warning: Stop with no seq field found: HK456
```

### Verify composite keys:
If ETAs are missing, check:
1. Does the stop have the correct `dir`/`bound` field?
2. Do ETAs include the matching `seq` and `bound`?
3. Are composite keys being built identically for both?

### Test alignment:
```dart
// Debug: Print constructed keys
final stopKey = "I_5";        // From stop
final etaKey = "I_5";         // From ETA
assert(stopKey == etaKey);    // Should match!
```

## Migration from Old Code

Old code supported fallback:
```dart
// ❌ OLD: Allowed mismatched lookups
etaByStop[compositeKey] ?? etaByStop[seq] ?? []
```

New code is strict:
```dart
// ✅ NEW: Only exact composite key match
etaByStop[compositeKey] ?? []
```

This breaks compatibility with malformed JSON but ensures data integrity.

## Performance Impact

- **Skipped stops**: Small memory savings
- **Skipped ETAs**: Small memory savings  
- **Removed fallback lookup**: Slightly faster ETA retrieval (no extra hashmap lookups)
- **Validation checks**: Negligible overhead (only during startup)

## Expected Warning Messages

Normal operation may show warnings for data quality issues:

```
⚠️  Warning: Stop seq=5 has no bound information: HK123
```

This indicates the JSON is missing the `dir`/`bound` field for that stop. It will be skipped to maintain data integrity.
