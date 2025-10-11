# Netlify Deployment Troubleshooting Guide

## Issue: Netlify Building from Old Commit

**Problem**: Netlify shows "Production: main@HEAD" but builds from an old commit instead of the latest code.

## Current Status
- **Local Repository**: Up to date with latest changes (commit `b598d15`)
- **Remote Repository (GitHub)**: Successfully pushed all changes
- **Auto-Refresh Feature**: Implemented in commit `12787c2`
- **Version**: 1.4.2+7

## Solutions (Try in Order)

### Solution 1: Manual Deploy with Cache Clear (RECOMMENDED)

This forces Netlify to pull fresh code and rebuild everything:

1. **Go to Netlify Dashboard**: https://app.netlify.com
2. **Select Your Site**: Click on your deployed site
3. **Navigate to Deploys**: Click "Deploys" in the top navigation
4. **Trigger Clean Deploy**:
   - Click the "Trigger deploy" dropdown button
   - Select **"Clear cache and deploy site"**
5. **Watch Build Log**: 
   - You should see it start building commit `b598d15`
   - Build command: `flutter build web --release`
   - Should take 5-10 minutes

### Solution 2: Check Deploy Settings

Verify Netlify is watching the correct branch:

1. **Go to Site Settings** → **Build & deploy** → **Continuous Deployment**
2. **Check Production Branch**:
   - Should say: `main` (not a specific commit hash)
   - If it shows a commit hash like `main@a1c736b`, change it to just `main`
3. **Check Deploy Contexts**:
   - Production branch: `main`
   - Deploy previews: Enabled
   - Branch deploys: Enabled for `main`

### Solution 3: Verify Build Settings

1. **Go to Site Settings** → **Build & deploy** → **Build settings**
2. **Verify Build Command** (updated to work with Netlify):
   ```bash
   bash -c 'if [ -d flutter ]; then cd flutter; git pull; cd ..; else git clone https://github.com/flutter/flutter.git; fi; flutter/bin/flutter clean; flutter/bin/flutter config --enable-web; flutter/bin/flutter build web --release --no-tree-shake-icons --source-maps'
   ```
3. **Verify Publish Directory**: `build/web`
4. **Check "Stop builds" toggle**: Should be OFF

### Solution 4: Check Auto-Deploy

1. **Go to Site Settings** → **Build & deploy** → **Build hooks**
2. **Verify GitHub Integration**: Should show your repository `Larry0420/next`
3. **Check Deploy Notifications**: Should be enabled for pushes to `main`

## How to Verify Deployment Worked

After deploying, check these:

### 1. Check Build Log
- Should see commit hash `b598d15` or later
- Should see `flutter build web --release` command
- Should complete successfully

### 2. Check Deployed Version
Visit your site and open browser console:
```javascript
fetch('/version.json').then(r => r.json()).then(console.log)
```

Should show:
```json
{
  "app_name": "lrt_next_train",
  "version": "1.4.2",
  "build_number": "7",
  "features": ["auto_refresh", "exponential_backoff", "O1_selection", "lazy_loading"]
}
```

### 3. Test Auto-Refresh Feature
1. Go to **Routes** page
2. Select any route
3. Expand a station card
4. Open browser DevTools → Console
5. Should see logs every 30 seconds:
   ```
   🔄 AUTO-REFRESH: Started for station 123 (route 505)
   🔄 AUTO-REFRESH: Refreshing station 123...
   ✅ AUTO-REFRESH: Station 123 refreshed successfully
   ```

### 4. Check main.dart.js Size
The compiled `main.dart.js` should be:
- **With auto-refresh**: ~2.5-3.5 MB
- **Old version (without auto-refresh)**: ~2.0-2.5 MB

## Common Issues & Fixes

### Issue: "Build is up-to-date, skipping..."
**Cause**: Netlify thinks nothing changed
**Fix**: Clear cache and force rebuild (Solution 1)

### Issue: Build succeeds but old code still shown
**Cause**: Browser cache or CDN cache
**Fix**: 
1. Hard refresh: `Ctrl + Shift + R` (Windows) or `Cmd + Shift + R` (Mac)
2. Clear browser cache
3. Try incognito/private window
4. Wait 5-10 minutes for CDN to update

### Issue: Build fails with "flutter: command not found"
**Cause**: Netlify build script error
**Fix**: Check build command in netlify.toml (should clone Flutter if not present)

### Issue: Deploys not triggering on git push
**Cause**: Auto-deploy disabled or GitHub webhook broken
**Fix**:
1. Check Site Settings → Build & deploy → Build hooks
2. Recreate GitHub webhook if needed
3. Manually trigger deploy

## Expected Timeline

After triggering deploy:
- **0-1 min**: Build queued
- **1-3 min**: Flutter SDK download (if not cached)
- **3-8 min**: `flutter build web` compilation
- **8-10 min**: Deploy to CDN
- **10-15 min**: CDN propagation worldwide

**Total**: 10-15 minutes from trigger to live

## Verification Checklist

- [ ] Latest commit (`b598d15`) visible in Netlify deploy log
- [ ] Build completes successfully
- [ ] `/version.json` shows version 1.4.2+7
- [ ] Auto-refresh logs appear in browser console when station expanded
- [ ] No console errors in browser DevTools
- [ ] Hard refresh shows updated code

## Still Not Working?

If none of the above work:

1. **Delete and Re-import Site**:
   - Delete the Netlify site (keep domain settings)
   - Re-import from GitHub
   - This forces Netlify to rebuild configuration

2. **Check Repository Connection**:
   - Verify GitHub repository is `Larry0420/next`
   - Check branch is `main`
   - Verify Netlify has GitHub access permissions

3. **Contact Support**:
   - Netlify support: https://www.netlify.com/support/
   - Provide build log and commit hash

## Useful Commands

```bash
# Check current commit
git log -1 --oneline

# Force push (use with caution)
git push origin main --force

# Verify remote is correct
git remote -v

# Check what's on remote main
git log origin/main -5 --oneline
```

---

**Last Updated**: October 11, 2025  
**Current Commit**: `b598d15`  
**Current Version**: 1.4.2+7  
**Auto-Refresh**: ✅ Implemented (commit `12787c2`)
