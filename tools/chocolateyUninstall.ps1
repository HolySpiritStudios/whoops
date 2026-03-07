$ErrorActionPreference = 'Stop'

$markerBegin = '# >>> whoops >>>'
$markerEnd   = '# <<< whoops <<<'

$profilePaths = @($PROFILE)

$ps7Profile = [System.IO.Path]::Combine(
    [Environment]::GetFolderPath('MyDocuments'),
    "PowerShell", "Microsoft.PowerShell_profile.ps1"
)
if ($ps7Profile -ne $PROFILE) {
    $profilePaths += $ps7Profile
}

foreach ($prof in $profilePaths) {
    if (-not (Test-Path $prof)) { continue }

    $content = Get-Content $prof -Raw
    if ($content -match [regex]::Escape($markerBegin)) {
        $pattern = "(?s)\r?\n?$([regex]::Escape($markerBegin)).*?$([regex]::Escape($markerEnd))\r?\n?"
        $content = [regex]::Replace($content, $pattern, "`n")
        $content = $content.TrimEnd() + "`n"
        Set-Content -Path $prof -Value $content -Encoding UTF8
        Write-Host "Removed whoops integration from $prof"
    }
}

$configDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) ".whoops"
if (Test-Path $configDir) {
    Write-Host ""
    Write-Host "Note: Your blocklist at $configDir was preserved." -ForegroundColor DarkYellow
    Write-Host "Delete it manually if you no longer need it." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Whoops uninstalled. Restart your terminal." -ForegroundColor Green
