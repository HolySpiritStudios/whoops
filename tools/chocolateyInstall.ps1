$ErrorActionPreference = 'Stop'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) ".whoops"
$blocklistDest = Join-Path $configDir "whoops-blocklist.json"
$profileScript = Join-Path $toolsDir "whoops-profile.ps1"

$markerBegin = '# >>> whoops >>>'
$markerEnd   = '# <<< whoops <<<'

# --- 1. Seed the blocklist if not already customized ---

if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

if (-not (Test-Path $blocklistDest)) {
    Copy-Item (Join-Path $toolsDir "whoops-blocklist.json") $blocklistDest
    Write-Host "Created default blocklist at $blocklistDest"
} else {
    Write-Host "Blocklist already exists at $blocklistDest (not overwritten)"
}

# --- 2. Wire up $PROFILE ---

$profilePaths = @($PROFILE)

$ps7Profile = [System.IO.Path]::Combine(
    [Environment]::GetFolderPath('MyDocuments'),
    "PowerShell", "Microsoft.PowerShell_profile.ps1"
)
if ($ps7Profile -ne $PROFILE -and (Test-Path (Split-Path $ps7Profile))) {
    $profilePaths += $ps7Profile
}

$sourceBlock = @"

$markerBegin
if (Get-Module PSReadLine) { . '$profileScript' }
$markerEnd
"@

foreach ($prof in $profilePaths) {
    $profDir = Split-Path $prof
    if (-not (Test-Path $profDir)) {
        New-Item -ItemType Directory -Path $profDir -Force | Out-Null
    }

    if (-not (Test-Path $prof)) {
        Set-Content -Path $prof -Value $sourceBlock -Encoding UTF8
        Write-Host "Created $prof with whoops integration"
        continue
    }

    $content = Get-Content $prof -Raw
    if ($content -match [regex]::Escape($markerBegin)) {
        $pattern = "(?s)$([regex]::Escape($markerBegin)).*?$([regex]::Escape($markerEnd))"
        $content = [regex]::Replace($content, $pattern, $sourceBlock.TrimStart())
        Set-Content -Path $prof -Value $content -Encoding UTF8
        Write-Host "Updated existing whoops block in $prof"
    } else {
        Add-Content -Path $prof -Value $sourceBlock -Encoding UTF8
        Write-Host "Added whoops integration to $prof"
    }
}

Write-Host ""
Write-Host "Whoops installed. Open a new terminal to activate." -ForegroundColor Green
Write-Host "Blocklist: $blocklistDest" -ForegroundColor DarkGray
