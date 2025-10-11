# PWA Theme Color Guide

## Dark/Light Theme Support

### Implementation

#### **index.html** (Recommended Approach)
```html
<!-- Theme color with dark/light mode support -->
<meta name="theme-color" content="#F67C0F" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#D66A0C" media="(prefers-color-scheme: dark)">
```

#### **manifest.json** (Fallback)
```json
{
  "theme_color": "#F67C0F"
}
```

**Note:** `manifest.json` does NOT support media queries for `theme_color`. The HTML meta tags take precedence and provide the adaptive behavior.

---

## Color Specifications

### Light Mode
- **Color:** `#F67C0F` (Orange)
- **RGB:** rgb(246, 124, 15)
- **HSL:** hsl(28, 93%, 51%)
- **Usage:** Bright, vibrant orange for light backgrounds

### Dark Mode
- **Color:** `#D66A0C` (Darker Orange)
- **RGB:** rgb(214, 106, 12)
- **HSL:** hsl(28, 89%, 44%)
- **Usage:** Slightly darker, less intense orange for dark backgrounds
- **Contrast:** Better visibility against dark UI elements

---

## How It Works

### Browser Behavior
1. Browser checks system/browser theme preference (`prefers-color-scheme`)
2. If **light mode**: Uses `#F67C0F` from first `<meta>` tag
3. If **dark mode**: Uses `#D66A0C` from second `<meta>` tag
4. If no media query match: Falls back to `manifest.json` value

### Platform Support

| Platform | Light/Dark Theme Support | Notes |
|----------|--------------------------|-------|
| Chrome (Android) | ✅ Full support | Respects media queries |
| Chrome (Desktop) | ✅ Full support | Tab/toolbar color changes |
| Safari (iOS) | ⚠️ Partial | Uses `apple-mobile-web-app-status-bar-style` |
| Edge | ✅ Full support | Same as Chrome |
| Firefox | ✅ Full support | Since Firefox 95+ |

---

## Alternative Approaches

### Option 1: JavaScript Dynamic Update (Most Flexible)
```html
<script>
  // Update theme color based on system preference
  const updateThemeColor = () => {
    const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    const metaThemeColor = document.querySelector('meta[name="theme-color"]');
    metaThemeColor.setAttribute('content', isDark ? '#D66A0C' : '#F67C0F');
  };

  // Initial update
  updateThemeColor();

  // Listen for theme changes
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateThemeColor);
</script>
```

### Option 2: CSS Variables + JavaScript
```html
<style>
  :root {
    --theme-color-light: #F67C0F;
    --theme-color-dark: #D66A0C;
  }
</style>
<script>
  const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const color = getComputedStyle(document.documentElement)
    .getPropertyValue(isDark ? '--theme-color-dark' : '--theme-color-light');
  document.querySelector('meta[name="theme-color"]').setAttribute('content', color);
</script>
```

### Option 3: Material Design Approach (Neutral)
Use a neutral color that works in both modes:
```html
<meta name="theme-color" content="#424242">
```

---

## Color Accessibility

### Light Mode (`#F67C0F`)
- ✅ **WCAG AAA** on white background (contrast ratio: 4.8:1)
- ✅ **WCAG AA** for large text
- ⚠️ May be too bright for some users

### Dark Mode (`#D66A0C`)
- ✅ Better contrast on dark backgrounds
- ✅ Reduced eye strain in dark environments
- ✅ Maintains brand identity with slight adjustment

---

## Testing

### Test on Different Devices
```bash
# Chrome DevTools
1. Open DevTools (F12)
2. Ctrl+Shift+P → "Show Rendering"
3. Emulate CSS media feature: prefers-color-scheme
4. Toggle between light/dark

# Firefox DevTools
1. Open DevTools (F12)
2. Settings (F1) → Inspector
3. Enable "prefers-color-scheme" simulation
```

### Manual Testing
1. **Android:** Settings → Display → Dark theme
2. **iOS:** Settings → Display & Brightness → Dark
3. **Windows:** Settings → Personalization → Colors → Choose your mode
4. **macOS:** System Preferences → General → Appearance

---

## Best Practices

### ✅ Do
- Use media queries in HTML `<meta>` tags
- Choose colors with good contrast
- Test on real devices
- Keep colors consistent with brand
- Consider accessibility (WCAG guidelines)

### ❌ Don't
- Don't rely only on `manifest.json` for theme adaptation
- Don't use colors with poor contrast
- Don't forget to test dark mode
- Don't use pure white/black (too harsh)

---

## Current Configuration Summary

| Property | Light Mode | Dark Mode | Fallback |
|----------|-----------|-----------|----------|
| Theme Color | `#F67C0F` | `#D66A0C` | `#F67C0F` |
| Background | `#F67C0F` | `#F67C0F` | `#F67C0F` |
| Method | HTML meta | HTML meta | manifest.json |
| Support | ✅ Modern browsers | ✅ Modern browsers | ✅ All browsers |

---

## Future Enhancements

### Dynamic Background Color
Consider adding dynamic background color support in Flutter:
```dart
// In main.dart
MaterialApp(
  theme: ThemeData(
    primaryColor: Color(0xFFF67C0F), // Light
    colorScheme: ColorScheme.fromSeed(
      seedColor: Color(0xFFF67C0F),
      brightness: Brightness.light,
    ),
  ),
  darkTheme: ThemeData(
    primaryColor: Color(0xFFD66A0C), // Dark
    colorScheme: ColorScheme.fromSeed(
      seedColor: Color(0xFFD66A0C),
      brightness: Brightness.dark,
    ),
  ),
  themeMode: ThemeMode.system, // Follow system theme
)
```

---

## References
- [MDN: theme-color](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta/name/theme-color)
- [Web.dev: PWA Manifest](https://web.dev/add-manifest/)
- [WCAG Color Contrast](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)
