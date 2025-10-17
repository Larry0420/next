# Network Optimization Quick Reference

## 🎯 At a Glance

### Cache Strategy
| Cache Type | TTL | Max Age | Purpose |
|------------|-----|---------|---------|
| **Memory** | 45s | 5min | Instant response |
| **Persistent** | N/A | 30min | Offline support |

### Refresh Intervals
| Condition | Interval | Trigger |
|-----------|----------|---------|
| **Normal** | 30s | Good network |
| **Slow Network** | 60s | Avg fetch > 5s |
| **Circuit Breaker** | 120s | 5+ errors |
| **Gradual Backoff** | 30s-120s | Incremental errors |

### Retry Configuration
| Attempt | Timeout | Delay Before |
|---------|---------|--------------|
| **1** | 10s | 0ms |
| **2** | 15s | 2s + jitter |
| **3** | 20s | 6s + jitter |

---

## 💡 Key APIs

### MtrApiService
```dart
// Standard fetch (with cache + retry)
await api.fetchSchedule('TML', 'DIH');

// Force network refresh (skip cache)
await api.fetchSchedule('TML', 'DIH', forceRefresh: true);

// Fetch but don't allow stale cache
await api.fetchSchedule('TML', 'DIH', allowStale: false);

// Clear all caches
await api.clearAllCaches();
```

### MtrScheduleProvider
```dart
// Load with smart caching
await provider.loadSchedule('TML', 'DIH');

// Force refresh (bypass cache)
await provider.manualRefresh('TML', 'DIH');

// Start adaptive auto-refresh
provider.startAutoRefresh('TML', 'DIH');

// Stop auto-refresh
provider.stopAutoRefresh();

// Check network state
if (provider.isNetworkSlow) { /* ... */ }
if (provider.isCircuitBreakerOpen) { /* ... */ }
```

---

## 🔍 Debug Checklist

### Network Issues
- [ ] Check `_consecutiveErrors` count
- [ ] Verify `isCircuitBreakerOpen` state
- [ ] Review logs for "MTR API: Attempt X/3 failed"
- [ ] Check current refresh interval

### Cache Issues
- [ ] Verify cache key format: `{LINE}_{STATION}`
- [ ] Check persistent cache exists in SharedPreferences
- [ ] Look for "Serving fresh/stale cache" logs
- [ ] Validate cache timestamps

### Performance Issues
- [ ] Monitor `_recentFetchDurations` moving average
- [ ] Check if `isNetworkSlow` is true
- [ ] Verify timeout values (10s→15s→20s)
- [ ] Review in-flight request deduplication

---

## 🚨 Common Error Messages

| Message | Cause | Solution |
|---------|-------|----------|
| "Circuit breaker open" | 5+ consecutive errors | Wait 2min or `manualRefresh()` |
| "No internet connection" | SocketException | Check device WiFi/data |
| "Request timed out" | TimeoutException | Slow network, retry or cache served |
| "Showing cached data" | Network error | Using fallback cache |

---

## 📊 Performance Metrics

### Good Network (WiFi)
- First load: ~500ms
- Cached load: ~5ms
- Refresh interval: 30s
- Retry delay: None (no errors)

### Slow Network (3G)
- First load: ~3-8s
- Cached load: ~5ms
- Refresh interval: 60s (adaptive)
- Retry delay: 2s → 6s → 14s

### Offline
- First load: ~5ms (cache)
- Cached load: ~5ms
- Refresh interval: 120s (circuit breaker)
- Error: "Showing cached data"

---

## 🛠️ Quick Tuning

### Make Caching More Aggressive
```dart
// Increase cache TTL (fresher longer)
static const Duration _memoryCacheTTL = Duration(seconds: 90);

// Increase max age (keep longer)
static const Duration _memoryCacheMaxAge = Duration(minutes: 10);
```

### Make Refresh More Frequent
```dart
// Decrease default interval
static const Duration _defaultRefreshInterval = Duration(seconds: 15);
```

### Make Retry More Patient
```dart
// Increase max retries
static const int _maxRetries = 5;

// Increase base delay
static const Duration _baseRetryDelay = Duration(seconds: 3);
```

### Make Circuit Breaker More Lenient
```dart
// Increase error threshold
static const int _maxConsecutiveErrors = 10;

// Decrease reset time
static const Duration _circuitBreakerResetDuration = Duration(minutes: 1);
```

---

## ✅ Testing Commands

### Simulate Poor Network
```bash
# Chrome DevTools → Network → Throttling → Slow 3G
# Or use Android ADB:
adb shell settings put global mobile_data_always_on 0
```

### Clear Persistent Cache
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.clear();
```

### Force Circuit Breaker Open
```dart
provider._consecutiveErrors = 5;
provider._openCircuitBreaker();
```

### Monitor Cache State
```dart
debugPrint('Memory cache size: ${MtrApiService._memoryCache.length}');
debugPrint('In-flight requests: ${MtrApiService._inflightRequests.length}');
```

---

## 📈 Expected Behavior

### Normal Flow
1. **First Request**: Network fetch → Cache → Display (500ms)
2. **Subsequent**: Memory cache → Display (5ms)
3. **After 45s**: Stale cache → Display + Background refresh
4. **After 5min**: Expired → Network fetch → Update cache

### Error Flow
1. **Error 1-4**: Retry with backoff → Success or fail
2. **Error 5**: Open circuit breaker → Stop refresh
3. **After 2min**: Close circuit breaker → Resume
4. **All Retries Failed**: Persistent cache → Display with error

### Offline Flow
1. **No Network**: Check persistent cache → Display
2. **Cache > 30min**: Error: "Data too old"
3. **No Cache**: Error: "No cached data available"

---

## 🎓 Best Practices

1. **Always allow stale cache** in auto-refresh for instant UX
2. **Force refresh only on manual pull** to respect network
3. **Monitor circuit breaker** to detect persistent issues
4. **Clear cache on logout/switch accounts** if user-specific
5. **Test with network throttling** before production

---

## 📞 Support

For issues or questions:
- Review [NETWORK_OPTIMIZATION_GUIDE.md](NETWORK_OPTIMIZATION_GUIDE.md) for details
- Check debug logs with filter: "MTR API" or "MTR Schedule"
- File issue with: network state, error logs, cache state

---

**Last Updated**: 2025-10-18
**Version**: 1.0.0
