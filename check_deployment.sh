#!/bin/bash
# Netlify Deployment Verification Script
# Run this to check if Netlify has the latest code

echo "🔍 Checking Netlify Deployment Status..."
echo ""

# Get current local commit
LOCAL_COMMIT=$(git rev-parse --short HEAD)
echo "📍 Local HEAD: $LOCAL_COMMIT"

# Get remote commit
REMOTE_COMMIT=$(git rev-parse --short origin/main)
echo "📍 Remote HEAD: $REMOTE_COMMIT"

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    echo "✅ Local and remote are in sync"
else
    echo "⚠️ Local and remote are out of sync!"
    echo "   Run: git push origin main"
fi

echo ""
echo "📦 Latest commits:"
git log --oneline -5

echo ""
echo "🌐 Next steps:"
echo "1. Go to https://app.netlify.com"
echo "2. Select your site"
echo "3. Click 'Deploys' tab"
echo "4. Verify latest deploy shows commit: $LOCAL_COMMIT"
echo "5. If not, click 'Trigger deploy' → 'Clear cache and deploy site'"
echo ""
echo "After deploy completes, verify at your site:"
echo "fetch('/version.json').then(r => r.json()).then(console.log)"
echo ""
echo "Expected output:"
echo '{"version":"1.4.2","build_number":"7","features":["auto_refresh",...]}'
