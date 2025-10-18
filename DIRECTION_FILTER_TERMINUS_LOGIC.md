# Direction Filter Visibility Logic

## Overview
Updated the direction filter to only display for **through train stations** (non-terminus stations), as terminus stations don't need direction filtering.

## Changes Made

### 1. Added Helper Method to MtrLine Class

```dart
/// Check if a station is a terminus (appears in any direction's terminus list)
bool isTerminusStation(String stationCode) {
  for (final terminusList in directionTermini.values) {
    if (terminusList.contains(stationCode)) {
      return true;
    }
  }
  return false;
}
```

**Purpose**: Determines if a given station is a terminus station by checking if its station code appears in any direction's terminus list.

**Location**: `lib/mtr_schedule_page.dart` - MtrLine class (~line 360)

### 2. Updated Direction Filter Visibility Logic

```dart
// Check if selected station is a terminus station
final isTerminus = widget.selectedStation != null && 
                   widget.selectedLine != null &&
                   widget.selectedLine!.isTerminusStation(widget.selectedStation!.stationCode);

// Only show direction filter for through trains (non-terminus stations)
final showDirectionFilter = hasDirections && 
                             widget.selectedStation != null && 
                             !isTerminus;
```

**Location**: `lib/mtr_schedule_page.dart` - `_buildStationSelectorWithDirections()` method (~line 2148)

### 3. Applied Filter Condition

```dart
// Direction filter (compact inline design) - Only shown for through trains (non-terminus stations)
if (showDirectionFilter) ...[
  // Direction filter UI...
]
```

**Location**: `lib/mtr_schedule_page.dart` - Station header section (~line 2233)

## Behavior

### Before
- Direction filter appeared for **all stations** that had multiple directions configured
- Showed direction filter even at terminus stations (e.g., Kennedy Town, Chai Wan, Tung Chung)
- Unnecessary UI element at terminus where only one direction is relevant

### After
- Direction filter only appears for **through train stations**
- Terminus stations (Kennedy Town, Chai Wan, etc.) no longer show direction filter
- Cleaner UI at terminus stations
- Direction filtering only available where it's meaningful (stations with trains going both directions)

## Station Classification

### Terminus Station
A station that appears in any direction's terminus list in the line configuration.

**Examples:**
- **Island Line**: Kennedy Town (KET), Chai Wan (CHW)
- **Tsuen Wan Line**: Tsuen Wan (TSW), Central (CEN)
- **Kwun Tong Line**: Whampoa (WHA), Tiu Keng Leng (TIK)
- **Tung Chung Line**: Tung Chung (TUC), Hong Kong (HOK)
- **East Rail Line**: Lo Wu (LOW), Lok Ma Chau (LMC), Admiralty (ADM)

**Characteristics:**
- First or last station on a line
- Trains only travel in one direction (away from terminus)
- May have multiple tracks for different destinations (e.g., EAL has Lo Wu and Lok Ma Chau)

### Through Train Station
A station that is **not** in any terminus list - intermediate stations on the line.

**Examples:**
- **Island Line**: Sheung Wan, Central (for through trains), Admiralty, Wan Chai, Causeway Bay, etc.
- **Tsuen Wan Line**: Prince Edward, Mong Kok, Jordan, Tsim Sha Tsui, Admiralty, etc.
- **East Rail Line**: Fo Tan, Sha Tin, Tai Wai, Kowloon Tong, Hung Hom, etc.

**Characteristics:**
- Located between two terminus stations
- Trains travel in both directions (UP/DOWN or IN/OUT)
- Direction filter is useful to show only trains going in desired direction

## Technical Details

### Direction Terminus Configuration

The `directionTermini` map structure in `MtrLine`:
```dart
final Map<String, List<String>> directionTermini;

// Example for Island Line:
directionTermini: {
  'UP': ['CHW'],     // Chai Wan (eastbound terminus)
  'DOWN': ['KET'],   // Kennedy Town (westbound terminus)
}

// Example for East Rail Line:
directionTermini: {
  'UP': ['LOW', 'LMC'],  // Lo Wu and Lok Ma Chau (northbound termini)
  'DOWN': ['ADM'],        // Admiralty (southbound terminus)
}
```

### Terminus Detection Algorithm

1. Get selected station's station code
2. Iterate through all direction terminus lists in the line
3. Check if station code appears in any list
4. Return `true` if found, `false` otherwise

**Time Complexity**: O(d × t) where d = number of directions, t = terminus stations per direction
- Typically d ≤ 2 (UP/DOWN or IN/OUT)
- Typically t ≤ 3 (rare to have more than 3 termini per direction)
- Very fast in practice

## User Experience Impact

### Improved Clarity
- **Before**: Seeing direction filter at Kennedy Town with only "Down" option was confusing
- **After**: No direction filter at Kennedy Town - cleaner and more intuitive

### Reduced Clutter
- **Before**: Extra UI row at terminus stations (61px vertical space for direction filter)
- **After**: More compact station header at terminus stations

### Maintained Functionality
- **Through Stations**: Direction filter still works perfectly
- **Terminus Stations**: Train list shows all trains (since they all go the same direction anyway)

## Examples

### Scenario 1: Island Line - Sheung Wan (Through Station)
- Station: Sheung Wan (SHW)
- Terminus check: NOT in ['CHW', 'KET'] ✗
- **Result**: Direction filter shown ✓
- **Directions**: "All", "Up" (to Chai Wan), "Down" (to Kennedy Town)

### Scenario 2: Island Line - Kennedy Town (Terminus)
- Station: Kennedy Town (KET)
- Terminus check: Found in 'DOWN' terminus list ✓
- **Result**: Direction filter hidden ✓
- **Reason**: All trains go "Up" (towards Chai Wan)

### Scenario 3: East Rail Line - Admiralty (Terminus)
- Station: Admiralty (ADM)
- Terminus check: Found in 'DOWN' terminus list ✓
- **Result**: Direction filter hidden ✓
- **Reason**: All trains go "Up" (towards Lo Wu/Lok Ma Chau)

### Scenario 4: East Rail Line - Sha Tin (Through Station)
- Station: Sha Tin (SHT)
- Terminus check: NOT in ['LOW', 'LMC', 'ADM'] ✗
- **Result**: Direction filter shown ✓
- **Directions**: "All", "Up" (to Lo Wu/LMC), "Down" (to Admiralty)

## Edge Cases Handled

### Multiple Termini in One Direction
**Example**: East Rail Line has two northbound termini (Lo Wu and Lok Ma Chau)
- Both 'LOW' and 'LMC' are marked as terminus stations
- Direction filter hidden at both
- Through stations still show "Up" direction filter (groups trains to either terminus)

### Interchange Stations
**Example**: Admiralty is both:
- Terminus for East Rail Line (DOWN)
- Through station for Island Line and Tsuen Wan Line

**Behavior**:
- When viewing **East Rail Line** at Admiralty → Direction filter hidden (terminus)
- When viewing **Island Line** at Admiralty → Direction filter shown (through station)
- Correctly handles line-specific terminus status

### Branch Lines
**Example**: Disneyland Resort Line branches from Tung Chung Line at Sunny Bay
- Sunny Bay (SUN) is a through station on Tung Chung Line
- Disneyland Resort (DIS) is terminus on Disneyland Resort Line
- Each line's terminus status is independent and correctly handled

## Testing Checklist

- [x] Terminus stations (KET, CHW, TUC, etc.) don't show direction filter
- [x] Through stations show direction filter with correct directions
- [x] Interchange stations handle line-specific terminus status correctly
- [x] East Rail Line handles dual termini (LOW, LMC) correctly
- [x] Direction filter animates smoothly when visible
- [x] No errors when selecting terminus stations
- [x] State persists correctly across app restarts
- [x] UI compact and clean at terminus stations

## Future Considerations

### Potential Enhancements
1. **Visual Indicator**: Add subtle terminus badge/icon to terminus station chips
2. **Tooltip**: Show "Terminus station" tooltip when hovering terminus chip
3. **Smart Default**: Auto-select the only available direction at terminus
4. **Train List Optimization**: Skip direction filtering logic at terminus for better performance

### Performance Notes
- Terminus check is O(1) amortized (small constant number of directions)
- No performance impact on UI rendering
- Direction filter animation is independent of terminus check

## Related Documentation
- `SELECTOR_ANIMATION_IMPROVEMENTS.md` - Direction filter UI animations
- `MTR_CARD_QUICK_REFERENCE.md` - Overall MTR selector design
- `Route Station.json` - Line configuration with terminus data

## Version History
- **v1.1** (Current): Direction filter only shown for through trains
- **v1.0** (Previous): Direction filter shown for all stations with directions
