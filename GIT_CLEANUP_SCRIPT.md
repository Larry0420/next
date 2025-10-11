# Git History Cleanup Script for Flutter Build Artifacts

## Problem Identified
Several commits in the repository contain Flutter build artifacts that should not be tracked:

### Build-Related Commits to Clean:
- `8952ec2`: "Add/Update web build" - Contains .dart_tool/, build/, android/.gradle/ etc.
- `c8dff45`: "Track build/web" - Contains build/web directory
- `1049b0e`: "Web commit" - Contains .dart_tool/, ephemeral files
- `202cb32`: "Web commit" - Likely similar build artifacts
- `0b8afe3`: "Web 20251007" - Probably contains build artifacts

### Clean Commits to Keep:
- `ec2b3b2`: "Optimize icons for all platforms..." - Icon optimizations (KEEP)
- `22c29ed`: "Fix: Resolve Android APK issues..." - Important fixes (KEEP) 
- `017eb8d`: "main.dart" - Source code changes (KEEP)
- Earlier commits without build artifacts (EVALUATE)

## Cleanup Strategy

### Option 1: Interactive Rebase (Recommended)
```bash
# Start interactive rebase from a safe point
git rebase -i a356646  # "first commit"

# In the editor, mark build-related commits as 'drop' or 'squash'
# Keep source code commits as 'pick'
```

### Option 2: Filter-Branch (Nuclear Option)
```bash
# Remove build artifacts from entire history
git filter-branch --tree-filter '
  rm -rf .dart_tool build android/.gradle ios/Flutter/ephemeral \
         linux/flutter/ephemeral macos/Flutter/ephemeral \
         windows/flutter/ephemeral .flutter-plugins-dependencies
' --prune-empty HEAD
```

### Option 3: Fresh Start with Cleaned History
```bash
# Create new orphan branch with clean history
git checkout --orphan clean-main
git rm -rf .
git clean -fxd

# Add only essential files
git checkout main -- lib/ android/ ios/ web/ linux/ macos/ windows/
git checkout main -- pubspec.yaml pubspec.lock analysis_options.yaml
git checkout main -- README.md .gitignore .metadata devtools_options.yaml
git checkout main -- assets/

# Commit clean version
git add .
git commit -m "Clean Flutter project without build artifacts"
```

## Files That Should Never Be Committed

### .gitignore Entries (Already Added)
```ignore
# Build artifacts
**/build/
.dart_tool/
.flutter-plugins-dependencies

# Platform-specific generated files
android/.gradle/
android/app/build/
ios/Flutter/Generated.xcconfig
ios/Flutter/ephemeral/
linux/flutter/ephemeral/
macos/Flutter/ephemeral/
windows/flutter/ephemeral/

# IDE generated files
.idea/workspace.xml
.idea/libraries/
*.iml

# Large native libraries
**/lib/arm*/*.so
**/lib/x86*/*.so
**/merged_native_libs/
**/intermediates/
**/outputs/
```

## Recommended Actions

1. **Backup Current State** ✅ (Already created backup-before-cleanup)
2. **Use Option 3** - Fresh start for cleanest history
3. **Force push to origin** to update remote
4. **Verify build still works** after cleanup

## Implementation Commands

```bash
# Backup current state (DONE)
git branch backup-before-cleanup

# Option 3: Fresh start
git checkout --orphan clean-main
git rm -rf . 2>/dev/null || true
git clean -fxd

# Restore essential files only
git checkout main -- lib/ android/ ios/ web/ linux/ macos/ windows/ test/ assets/
git checkout main -- pubspec.yaml pubspec.lock analysis_options.yaml
git checkout main -- README.md .gitignore .metadata devtools_options.yaml
git checkout main -- *.md

# Clean up any accidentally included build artifacts
rm -rf .dart_tool build android/.gradle android/app/build
rm -rf ios/Flutter/Generated.xcconfig ios/Flutter/ephemeral
rm -rf linux/flutter/ephemeral macos/Flutter/ephemeral windows/flutter/ephemeral
rm -rf .flutter-plugins-dependencies

# Commit clean version
git add .
git commit -m "Clean Flutter LRT project - removed build artifacts

- Source code for Light Rail Transit next train app
- Platform configurations for Android, iOS, web, Windows, macOS, Linux  
- Optimized icons and PWA manifest
- Comprehensive documentation and guides
- No build artifacts or generated files"

# Replace main branch
git branch -D main
git branch -m clean-main main

# Force push to update remote
git push --force-with-lease origin main
```

## Verification After Cleanup

```bash
# Verify no build artifacts
git ls-files | grep -E "(\.dart_tool|build/|\.gradle|ephemeral|Generated\.xcconfig)"

# Test build still works
flutter clean
flutter pub get
flutter build web
flutter build apk --debug

# Check repository size
git count-objects -vH
```

This will create a clean repository with only source code and essential files, removing all Flutter build artifacts from git history.