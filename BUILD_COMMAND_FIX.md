# Netlify Build Command Fix

## Problem
The original build command used `&&` operator which is not allowed in Netlify's build configuration:

```bash
# ❌ OLD (doesn't work on Netlify)
if cd flutter; then git pull && cd ..; else git clone https://github.com/flutter/flutter.git; fi && flutter/bin/flutter clean && flutter/bin/flutter config --enable-web && flutter/bin/flutter build web --release
```

## Solution
Wrap the command in `bash -c` and use semicolons (`;`) instead of `&&`:

```bash
# ✅ NEW (works on Netlify)
bash -c 'if [ -d flutter ]; then cd flutter; git pull; cd ..; else git clone https://github.com/flutter/flutter.git; fi; flutter/bin/flutter clean; flutter/bin/flutter config --enable-web; flutter/bin/flutter build web --release --no-tree-shake-icons --source-maps'
```

## Key Changes

1. **Wrapped in `bash -c '...'`**: Ensures the command runs in bash shell
2. **Changed `&&` to `;`**: Semicolons work in Netlify, `&&` doesn't
3. **Fixed `if cd flutter`**: Changed to `if [ -d flutter ]` (proper directory check)
4. **Simplified logic**: 
   - If `flutter` directory exists → `cd flutter; git pull; cd ..`
   - If not → `git clone https://github.com/flutter/flutter.git`

## What This Does

1. **Check if Flutter SDK exists**:
   - If yes: Update it (`cd flutter; git pull; cd ..`)
   - If no: Download it (`git clone ...`)

2. **Clean previous build**: `flutter/bin/flutter clean`

3. **Enable web support**: `flutter/bin/flutter config --enable-web`

4. **Build for web**: `flutter/bin/flutter build web --release --no-tree-shake-icons --source-maps`
   - `--release`: Production build (optimized, minified)
   - `--no-tree-shake-icons`: Include all Material icons
   - `--source-maps`: Generate source maps for debugging

## Next Steps

After this fix is deployed:

1. **Go to Netlify Dashboard**: https://app.netlify.com
2. **Trigger Deploy**: "Clear cache and deploy site"
3. **Watch Build Log**: Should succeed without errors
4. **Verify Output**: Check your deployed site has the latest code

## Expected Build Time

- **First build** (downloads Flutter SDK): ~8-10 minutes
- **Subsequent builds** (Flutter cached): ~3-5 minutes

## Troubleshooting

If build still fails:

### Error: "bash: command not found"
**Solution**: Netlify supports bash by default. This shouldn't happen. If it does, contact Netlify support.

### Error: "git: command not found"
**Solution**: Git is pre-installed on Netlify. Check build image settings.

### Error: "flutter: No such file or directory"
**Solution**: The git clone might have failed. Check:
1. GitHub is accessible from Netlify
2. No rate limiting from GitHub
3. Build log for any clone errors

### Build succeeds but site shows old code
**Solution**: Browser cache. Hard refresh with `Ctrl + Shift + R`

## Commit History

- **fcb3322**: Fix: Rewrite Netlify build command to use bash -c with semicolons
- **b598d15**: Update web version.json to 1.4.2+7
- **0f49368**: Bump version to 1.4.2+7 - Force Netlify rebuild
- **12787c2**: feat: Implement auto-refresh for Routes page

---

**Status**: ✅ Fixed  
**Last Updated**: October 11, 2025  
**Current Commit**: `fcb3322`
