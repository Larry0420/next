# Netlify Deployment Verification Script (PowerShell)
# Run this to check if Netlify has the latest code

Write-Host "🔍 Checking Netlify Deployment Status..." -ForegroundColor Cyan
Write-Host ""

# Get current local commit
$localCommit = git rev-parse --short HEAD
Write-Host "📍 Local HEAD: $localCommit" -ForegroundColor Green

# Get remote commit
$remoteCommit = git rev-parse --short origin/main
Write-Host "📍 Remote HEAD: $remoteCommit" -ForegroundColor Green

if ($localCommit -eq $remoteCommit) {
    Write-Host "✅ Local and remote are in sync" -ForegroundColor Green
} else {
    Write-Host "⚠️ Local and remote are out of sync!" -ForegroundColor Yellow
    Write-Host "   Run: git push origin main" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "📦 Latest commits:" -ForegroundColor Cyan
git log --oneline -5

Write-Host ""
Write-Host "🌐 Next steps:" -ForegroundColor Cyan
Write-Host "1. Go to https://app.netlify.com" -ForegroundColor White
Write-Host "2. Select your site" -ForegroundColor White
Write-Host "3. Click 'Deploys' tab" -ForegroundColor White
Write-Host "4. Verify latest deploy shows commit: $localCommit" -ForegroundColor White
Write-Host "5. If not, click 'Trigger deploy' → 'Clear cache and deploy site'" -ForegroundColor Yellow
Write-Host ""
Write-Host "After deploy completes, verify at your site:" -ForegroundColor Cyan
Write-Host "fetch('/version.json').then(r => r.json()).then(console.log)" -ForegroundColor Gray
Write-Host ""
Write-Host "Expected output:" -ForegroundColor Cyan
Write-Host '{"version":"1.4.2","build_number":"7","features":["auto_refresh",...]}' -ForegroundColor Gray
Write-Host ""

# Check if we can fetch version from deployed site (optional)
Write-Host "Enter your Netlify site URL to check deployed version (or press Enter to skip): " -NoNewline
$siteUrl = Read-Host
if ($siteUrl) {
    try {
        $versionUrl = "$siteUrl/version.json"
        $response = Invoke-RestMethod -Uri $versionUrl
        Write-Host ""
        Write-Host "🌍 Currently deployed version:" -ForegroundColor Cyan
        Write-Host "   Version: $($response.version)" -ForegroundColor White
        Write-Host "   Build: $($response.build_number)" -ForegroundColor White
        if ($response.features) {
            Write-Host "   Features: $($response.features -join ', ')" -ForegroundColor White
        }
    } catch {
        Write-Host "❌ Could not fetch version from $versionUrl" -ForegroundColor Red
    }
}
