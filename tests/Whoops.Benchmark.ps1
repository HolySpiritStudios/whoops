# Whoops Performance Benchmark
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Whoops.Benchmark.ps1

$toolsDir = Join-Path $PSScriptRoot "..\tools"
$corePath = Join-Path $toolsDir "whoops-core.ps1"
$blocklistPath = Join-Path $toolsDir "whoops-blocklist.json"

function Measure-Average {
    param([scriptblock]$Block, [int]$Iterations = 100)
    $Block.Invoke()
    $times = @()
    for ($i = 0; $i -lt $Iterations; $i++) {
        $times += (Measure-Command $Block).TotalMilliseconds
    }
    $sorted = $times | Sort-Object
    $p50 = $sorted[[math]::Floor($Iterations * 0.5)]
    $p99 = $sorted[[math]::Floor($Iterations * 0.99)]
    return @{
        Avg = [math]::Round(($times | Measure-Object -Average).Average, 2)
        P50 = [math]::Round($p50, 2)
        P99 = [math]::Round($p99, 2)
        Min = [math]::Round(($times | Measure-Object -Minimum).Minimum, 2)
        Max = [math]::Round(($times | Measure-Object -Maximum).Maximum, 2)
    }
}

Write-Host ""
Write-Host "Whoops Performance Benchmark" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

# --- Core module load ---

Write-Host "1. Core module load (whoops-core.ps1)" -ForegroundColor Yellow
$r = Measure-Average -Iterations 50 -Block { . $corePath }
Write-Host "   Avg: $($r.Avg)ms | P50: $($r.P50)ms | P99: $($r.P99)ms"
Write-Host ""

# --- Blocklist parse ---

Write-Host "2. Blocklist parse (Get-WhoopsBlocklist)" -ForegroundColor Yellow
. $corePath
$r = Measure-Average -Block { Get-WhoopsBlocklist -Path $blocklistPath }
Write-Host "   Avg: $($r.Avg)ms | P50: $($r.P50)ms | P99: $($r.P99)ms"
Write-Host ""

# --- Pattern matching (hit) ---

Write-Host "3. Pattern match - BLOCKED command" -ForegroundColor Yellow
$blocklist = Get-WhoopsBlocklist -Path $blocklistPath
$r = Measure-Average -Block {
    Test-WhoopsBlocked -Command "git reset --hard HEAD~3" -BlockedCommands $blocklist.blocked_commands
}
Write-Host "   Avg: $($r.Avg)ms | P50: $($r.P50)ms | P99: $($r.P99)ms"
Write-Host ""

# --- Pattern matching (miss) ---

Write-Host "4. Pattern match - SAFE command" -ForegroundColor Yellow
$r = Measure-Average -Block {
    Test-WhoopsBlocked -Command "git status" -BlockedCommands $blocklist.blocked_commands
}
Write-Host "   Avg: $($r.Avg)ms | P50: $($r.P50)ms | P99: $($r.P99)ms"
Write-Host ""

# --- Full Enter-key path (load + parse + match) ---

Write-Host "5. Full check path (load blocklist + match)" -ForegroundColor Yellow
$r = Measure-Average -Block {
    $bl = Get-WhoopsBlocklist -Path $blocklistPath
    if ($null -ne $bl) {
        Test-WhoopsBlocked -Command "git reset --hard HEAD" -BlockedCommands $bl.blocked_commands
    }
}
Write-Host "   Avg: $($r.Avg)ms | P50: $($r.P50)ms | P99: $($r.P99)ms"
Write-Host ""

# --- Full Enter-key path for safe command ---

Write-Host "6. Full check path - SAFE command (typical case)" -ForegroundColor Yellow
$r = Measure-Average -Block {
    $bl = Get-WhoopsBlocklist -Path $blocklistPath
    if ($null -ne $bl) {
        Test-WhoopsBlocked -Command "npm install" -BlockedCommands $bl.blocked_commands
    }
}
Write-Host "   Avg: $($r.Avg)ms | P50: $($r.P50)ms | P99: $($r.P99)ms"
Write-Host ""

# --- Missing blocklist (graceful degradation) ---

Write-Host "7. Missing blocklist (graceful degradation)" -ForegroundColor Yellow
$r = Measure-Average -Block {
    $bl = Get-WhoopsBlocklist -Path "C:\nonexistent\blocklist.json"
}
Write-Host "   Avg: $($r.Avg)ms | P50: $($r.P50)ms | P99: $($r.P99)ms"
Write-Host ""

Write-Host "Done." -ForegroundColor Green
