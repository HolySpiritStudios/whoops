# Whoops

Guards against accidental re-execution of dangerous terminal commands from history.

Ever scrolled through your terminal history and accidentally hit Enter on `git reset --hard`? Whoops prevents that.

## Install

```powershell
choco install whoops
```

## How It Works

Whoops hooks into PSReadLine's key handlers. When you recall a blocked command from history (Up/Down arrow, Ctrl+R, F8) and press Enter without editing it, the command is rejected:

```
whoops! Not executable from history.

  git reset --hard HEAD~3
  Destroys uncommitted work permanently [critical]
```

Manually typed commands always pass through -- the guard only blocks unedited history recall.

## Default Blocklist

| Pattern | Severity | Reason |
|---------|----------|--------|
| `git reset --hard` | critical | Destroys uncommitted work permanently |

## Managing the Blocklist

Edit `~/.whoops/whoops-blocklist.json` directly:

```json
{
  "version": 1,
  "blocked_commands": [
    {
      "pattern": "git reset --hard",
      "reason": "Destroys uncommitted work permanently",
      "added_at": "2026-03-07T00:00:00Z",
      "severity": "critical"
    },
    {
      "pattern": "rm -rf /",
      "reason": "Recursive delete from root",
      "added_at": "2026-03-07T00:00:00Z",
      "severity": "critical"
    }
  ]
}
```

Patterns are matched as case-insensitive substrings. `git reset --hard` catches `git reset --hard`, `git reset --hard HEAD~3`, `sudo git reset --hard`, etc.

## Uninstall

```powershell
choco uninstall whoops
```

Your blocklist at `~/.whoops/` is preserved on uninstall.

## How It's Wired Up

The installer adds a fenced block to your PowerShell `$PROFILE` (both 5.1 and 7 if present):

```powershell
# >>> whoops >>>
if (Get-Module PSReadLine) { . 'C:\ProgramData\chocolatey\lib\whoops\tools\whoops-profile.ps1' }
# <<< whoops <<<
```

Non-interactive sessions (automation, scripts, `-NoProfile`) skip this entirely.

## Performance

| Metric | P50 | P99 |
|--------|-----|-----|
| Profile load | 13ms | 32ms |
| Per-keystroke check | 0.6ms | 1.2ms |
| Pattern match | 0.05ms | 1.8ms |

Zero overhead for non-interactive sessions.

## Testing

Requires [Pester](https://pester.dev/) v5+.

```powershell
# Unit and integration tests
Import-Module Pester; Invoke-Pester tests\ -Output Detailed

# Performance benchmarks
powershell -NoProfile -File tests\Whoops.Benchmark.ps1
```

## License

MIT
