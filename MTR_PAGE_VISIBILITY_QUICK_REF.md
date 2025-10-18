# MTR Auto-Refresh Page Visibility - Quick Reference

## 🎯 What Changed
Auto-refresh now **only runs when MTR page is visible** to the user.

## 🔑 Key Behaviors

### ✅ Auto-Refresh STARTS When:
- User navigates to MTR tab (and auto-refresh is enabled)
- User returns to MTR tab from another page
- App resumes from background **while** on MTR tab

### ⏸️ Auto-Refresh STOPS When:
- User switches away from MTR tab
- App goes to background (home button pressed)
- User manually disables auto-refresh

### ❌ Auto-Refresh DOES NOT RUN When:
- User is on Schedule tab
- User is on Routes tab
- User is on Settings tab
- App is in background

## 📊 Resource Savings

| Scenario | Before | After | Savings |
|----------|--------|-------|---------|
| User spends 50% time on other tabs | 100% API calls | 50% API calls | **50%** |
| User browses all 4 tabs equally | 100% API calls | 25% API calls | **75%** |
| App in background 10 minutes | 20 API calls | 0 API calls | **100%** |

## 🔍 How to Verify

### Check Debug Console:
```
✅ "MTR Page: Starting auto-refresh (page is visible)"
   → Auto-refresh activated

⏸️ "MTR Page: Pausing auto-refresh (page is hidden)"
   → Auto-refresh paused

🔄 "MTR Page: Resuming auto-refresh (page became visible)"
   → Auto-refresh resumed

📱 "MTR Page: App resumed, but page is hidden - skipping refresh"
   → Smart behavior: no unnecessary refresh
```

## 🧪 Quick Test

1. **Test Tab Switching**:
   - Go to MTR tab → See auto-refresh icon spinning
   - Switch to Settings → Icon should stop spinning
   - Return to MTR → Icon should resume spinning

2. **Test App Backgrounding**:
   - Go to MTR tab → Auto-refresh running
   - Press home button → Auto-refresh stops
   - Open app on different tab → Auto-refresh stays off
   - Switch to MTR tab → Auto-refresh resumes

3. **Test Manual Control**:
   - Toggle auto-refresh OFF in settings
   - Switch between tabs → No auto-refresh
   - Toggle auto-refresh ON
   - Switch to MTR tab → Auto-refresh starts

## 💡 Implementation Details

### Technology Stack:
- **`AutomaticKeepAliveClientMixin`**: Keeps page state alive
- **`ModalRoute.of(context)?.isCurrent`**: Detects page visibility
- **`_isPageVisible` flag**: Tracks visibility state
- **`WidgetsBindingObserver`**: Monitors app lifecycle

### Code Locations:
```dart
// Visibility tracking
_MtrSchedulePageState._checkPageVisibility()

// Auto-refresh control
_MtrSchedulePageState._handleVisibilityChanged()

// Lifecycle integration
_MtrSchedulePageState.didChangeAppLifecycleState()
```

## 🐛 Troubleshooting

### Auto-refresh not stopping when switching tabs?
- Check debug console for visibility logs
- Ensure `AutomaticKeepAliveClientMixin` is properly mixed in
- Verify `super.build(context)` is called in build method

### Auto-refresh not resuming when returning to MTR tab?
- Check if auto-refresh is enabled in settings
- Verify a station is selected
- Look for visibility change logs in debug console

### Auto-refresh running on wrong page?
- Clear app cache and restart
- Check `ModalRoute.of(context)?.isCurrent` value
- Verify PageView navigation is working correctly

## 📈 Performance Impact

### Before:
- Auto-refresh runs 24/7 regardless of page
- ~2 requests/minute × 60 minutes = 120 requests/hour

### After:
- Auto-refresh only when MTR page visible
- If user views MTR 25% of time: ~30 requests/hour
- **75% reduction in API calls** 🎉

## 🎓 Best Practices

1. **Let it work automatically**: No need to manually stop/start
2. **Use settings toggle**: Control auto-refresh behavior globally
3. **Monitor debug logs**: Verify expected behavior during development
4. **Test on real devices**: Ensure lifecycle events work correctly

## 📝 Related Documentation
- `MTR_AUTO_REFRESH_PAGE_VISIBILITY.md` - Full technical details
- `MTR_AUTO_REFRESH_QUICK_REFERENCE.md` - General auto-refresh guide
- `NETWORK_OPTIMIZATION_QUICK_REF.md` - Network optimization strategies

---

**Last Updated**: Implementation Date  
**Version**: 1.0  
**Status**: ✅ Production Ready
