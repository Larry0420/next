# MTR Chip Consistency - Quick Reference

## Summary
Unified all chip components (line, station, direction, interchange) to have consistent sizing, styling, and visual appearance.

## Key Changes

### 1. Direction Filter Buttons
**Standardized to match line/station chips:**
- Padding: `8h x 4v` → `10h x 6v` ✅
- Border radius: `12px` → `8px` ✅  
- Font size: `10.5px` → `11.5px` ✅
- Border opacity: `0.3/1.5` → `0.2/1.5` ✅
- Shadow: `3px blur` → `4px blur` ✅

### 2. Interchange Indicator
**Optimized for height consistency:**
- Height: `Fixed 20px` → `Natural height` ✅
- Padding: `6h x 2v` → `4h x 0v` ✅
- Border radius: `10px` → `8px` ✅
- Circle size: `10x10` → `8x8` ✅
- Empty state: `SizedBox(20)` → `SizedBox.shrink()` ✅

## Unified Constants

```dart
UIConstants.chipPaddingH      // 10px - Horizontal padding
UIConstants.chipPaddingV      // 6px  - Vertical padding
UIConstants.chipRadius        // 8px  - Border radius
UIConstants.chipFontSize      // 11.5px - Text size
UIConstants.chipBorderWidth   // 1.0px - Normal border
UIConstants.selectedChipBorderWidth // 1.5px - Selected border
UIConstants.chipBorderOpacity // 0.2 - Normal opacity
UIConstants.selectedChipBorderOpacity // 0.5 - Selected opacity
```

## Visual Result

**Before:**
- ❌ Direction buttons smaller than chips
- ❌ Interchange stations had taller chips
- ❌ Inconsistent visual weight

**After:**
- ✅ All chips same size (10h x 6v padding)
- ✅ Consistent height across all chip types
- ✅ Unified visual design system

## Consistency Matrix

| Component | Size | Style | Behavior |
|-----------|------|-------|----------|
| Line Chips | ✅ Consistent | ✅ Unified | ✅ Standard |
| Station Chips | ✅ Consistent | ✅ Unified | ✅ Standard |
| Direction Buttons | ✅ Consistent | ✅ Unified | ✅ Standard |
| Interchange Badge | ✅ Fits naturally | ✅ Compact | ✅ Non-intrusive |

## Impact
- 🎨 **Visual**: Professional, cohesive appearance
- 👆 **UX**: Consistent tap targets and feedback
- 📱 **Mobile**: Better touch accuracy
- 🔧 **Maintainability**: Single source of truth (UIConstants)

## Files Modified
- `lib/mtr_schedule_page.dart` (2 methods)
  - `_buildCompactDirectionButton()` - Lines ~2546-2595
  - `_buildInterchangeIndicator()` - Lines ~2869-2946

---
**Status**: ✅ Complete | **Date**: Oct 19, 2025
