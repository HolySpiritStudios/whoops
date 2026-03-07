# Whoops - Core matching logic
# Pure functions, no PSReadLine dependency. Testable in isolation.

function Get-WhoopsBlocklist {
    param([string]$Path)

    if (-not $Path) {
        $Path = [System.IO.Path]::Combine(
            [Environment]::GetFolderPath('UserProfile'),
            ".whoops", "whoops-blocklist.json"
        )
    }

    if (-not [System.IO.File]::Exists($Path)) {
        return $null
    }

    try {
        $json = [System.IO.File]::ReadAllText($Path)
        $blocklist = $json | ConvertFrom-Json

        if ($blocklist.version -ne 1 -or -not $blocklist.blocked_commands) {
            return $null
        }

        return $blocklist
    } catch {
        return $null
    }
}

function Test-WhoopsBlocked {
    param(
        [string]$Command,
        [object[]]$BlockedCommands
    )

    if ([string]::IsNullOrWhiteSpace($Command) -or -not $BlockedCommands) {
        return $null
    }

    $cmdLower = $Command.ToLower().TrimStart()

    foreach ($entry in $BlockedCommands) {
        $patternLower = $entry.pattern.ToLower()

        if ($cmdLower.Contains($patternLower)) {
            return $entry
        }
    }

    return $null
}
