# ETA Refetch Optimization - Quick Reference

## What Changed?

### Before
- Manual "Refresh" button always visible in expanded state
- No automatic refetch when expanding card
- No visual feedback while fetching
- Collapsed state showed nothing or repeated ETA information

### After ✨
- **Auto-refetch on expand**: Automatically fetches fresh ETAs when card opens
- **Smooth loading animation**: Spinner + "Fetching..." text shown during fetch
- **Clean collapsed state**: Compact "No buses" / "無班次" placeholder
- **Manual refresh still available**: Optional button for extra control
- **All animations smooth**: 300ms transitions throughout

## Key Features

### Display States (Expanded Only)

| State | Display | Duration |
|-------|---------|----------|
| Collapsed (Initial) | "No buses" / "無班次" | Default |
| Loading/Refetching | Spinner + "Fetching..." / "更新中..." | ≥1.5s |
| Empty | "No upcoming buses" / "沒有即將到站的巴士" | Until data loads |
| With ETAs | Up to 3 times with colors/remarks | Until card collapses |

### Animation Timeline
1. **Tap → Expand** (0ms)
   - Card smoothly expands (AnimatedSize 300ms)
   
2. **Expand → Auto-Refetch** (0-50ms)
   - Spinner appears (AnimatedSwitcher 300ms)
   - "Fetching..." text shown
   
3. **Fetching** (50-1500ms+)
   - Loading spinner visible
   - Minimum 1.5s guaranteed for UX feedback
   
4. **Data Ready → Display** (1500ms+)
   - Spinner fades (AnimatedSwitcher 300ms)
   - ETAs or "No upcoming buses" shown
   
5. **Collapse → Placeholder** (>1500ms)
   - Card smoothly collapses
   - Back to "No buses" placeholder

## Code Methods

### Auto-Refetch (Automatic)
```dart
_autoRefetchOnExpand() // Triggered on expand
  ├─ Show spinner (1.5s minimum)
  ├─ Fetch via Kmb.fetchStopEta(stopId)
  └─ Hide spinner + show results
```

### Manual Refresh (Optional Button)
```dart
_manualRefetchStopEta() // User clicks Refresh button
  ├─ Show spinner (800ms)
  ├─ Fetch via Kmb.fetchStopEta(stopId)
  └─ Hide spinner
```

### Toggle Expand/Collapse
```dart
_toggleExpanded() // User taps card
  ├─ Toggle _isExpanded bool
  └─ If expanding: trigger _autoRefetchOnExpand()
```

## State Flags

| Flag | Purpose | Resets |
|------|---------|--------|
| `_isExpanded` | Card expansion state | On tap |
| `_shouldShowRefreshAnimation` | Auto-refetch loading state | After 1.5s |
| `_etaRefreshing` | Manual refresh loading state | After fetch completes |

## Languages Supported

- **English**: "No buses" → "Fetching..." → "No upcoming buses" → ETAs
- **Traditional Chinese**: "無班次" → "更新中..." → "沒有即將到站的巴士" → ETAs

## Color Coding (ETA Times)

- 🔴 **Red** - Due within 2 minutes
- 🟠 **Orange** - Due within 5 minutes  
- 🟢 **Green** - Due within 10 minutes
- 🔵 **Blue** - Due after 10 minutes
- ⚪ **Grey** - Departed/No data

## Action Buttons (Expanded Only)

| Button | Icon | Action |
|--------|------|--------|
| Refresh | 🔄 | Manual ETA refetch |
| Pin | 📌 | Add to favorites |
| Map | 🗺️ | Jump to map view |
| View | 👁️ | Street view (placeholder) |

## Performance

- **Auto-refetch cost**: Single `Kmb.fetchStopEta(stopId)` call per expand
- **Animation overhead**: Minimal (2 AnimatedSwitcher, 1 AnimatedSize)
- **Memory**: No new state except 2 boolean flags
- **Network**: Only when expanding (smart, on-demand)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Spinner shows but no data appears | Check network/API response |
| Animation feels jumpy | Ensure min 1.5s delay is working |
| Collapsed text misaligned | Verify `bodySmall` theme style applied |
| Refresh button disabled | Check if `_etaRefreshing` is stuck true |
| Dark mode colors wrong | Verify `colorScheme.primary` is correct theme |

## Future Enhancements

- [ ] Add pull-to-refresh gesture
- [ ] Cache ETA results with TTL
- [ ] Add haptic feedback on refresh
- [ ] Smart refetch intervals based on ETA times
- [ ] Show "Last updated: 2m ago" timestamp
