# Whoops - Terminal Command Guard
# Blocks dangerous commands recalled from history. Manually typed commands pass through.
# Blocklist: ~/.whoops/whoops-blocklist.json

. (Join-Path $PSScriptRoot "whoops-core.ps1")

if (Get-Module -Name PSReadLine) {
    $global:_whoopsRecalledLine = $null

    function global:_whoopsSnapshotHistory {
        $l = $null; $c = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$l, [ref]$c)
        $global:_whoopsRecalledLine = $l
    }

    function global:_wb {
        $info = $global:_whoopsBlockInfo
        $global:_whoopsBlockInfo = $null
        if ($null -eq $info) { return }

        $y = [Console]::CursorTop - 1
        if ($y -lt 0) { $y = 0 }
        [Console]::SetCursorPosition(0, $y)
        [Console]::Write((" " * [Console]::WindowWidth))
        [Console]::SetCursorPosition(0, $y)

        Write-Host "whoops! " -ForegroundColor Red -NoNewline
        Write-Host "Not executable from history." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  $($info.Cmd)" -ForegroundColor DarkGray
        Write-Host "  $($info.Reason) [$($info.Severity)]" -ForegroundColor DarkYellow
        Write-Host ""
    }

    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        if ($line -eq '_wb') { return $false }
        return $true
    }

    Set-PSReadLineKeyHandler -Key UpArrow -BriefDescription "WhoopsUp" -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::PreviousHistory($null, $null)
        _whoopsSnapshotHistory
    }

    Set-PSReadLineKeyHandler -Key DownArrow -BriefDescription "WhoopsDown" -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::NextHistory($null, $null)
        _whoopsSnapshotHistory
    }

    Set-PSReadLineKeyHandler -Key Ctrl+r -BriefDescription "WhoopsCtrlR" -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::ReverseSearchHistory($null, $null)
        _whoopsSnapshotHistory
    }

    Set-PSReadLineKeyHandler -Key F8 -BriefDescription "WhoopsF8" -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::HistorySearchBackward($null, $null)
        _whoopsSnapshotHistory
    }

    Set-PSReadLineKeyHandler -Key Shift+F8 -BriefDescription "WhoopsShiftF8" -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::HistorySearchForward($null, $null)
        _whoopsSnapshotHistory
    }

    Set-PSReadLineKeyHandler -Key Enter -BriefDescription "WhoopsGuard" `
        -LongDescription "Rejects blocked commands recalled from history without edits" `
        -ScriptBlock {
        param($key, $arg)

        $line = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $recalledLine = $global:_whoopsRecalledLine
        $global:_whoopsRecalledLine = $null

        $fromHistory = ($null -ne $recalledLine) -and ($line -eq $recalledLine)

        if ($fromHistory -and -not [string]::IsNullOrWhiteSpace($line)) {
            try {
                $blocklist = Get-WhoopsBlocklist
                if ($null -ne $blocklist) {
                    $match = Test-WhoopsBlocked -Command $line -BlockedCommands $blocklist.blocked_commands
                    if ($null -ne $match) {
                        $global:_whoopsBlockInfo = @{
                            Cmd      = $line
                            Reason   = $match.reason
                            Severity = $match.severity
                        }
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, "_wb")
                        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
                        return
                    }
                }
            } catch { }
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}
