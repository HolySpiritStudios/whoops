BeforeAll {
    . (Join-Path $PSScriptRoot "..\tools\whoops-core.ps1")

    $script:FixtureDir = Join-Path $TestDrive "whoops-fixtures"
    New-Item -ItemType Directory -Path $script:FixtureDir -Force | Out-Null

    function New-Blocklist {
        param([object[]]$Commands)
        $path = Join-Path $script:FixtureDir "blocklist-$(Get-Random).json"
        @{
            version          = 1
            blocked_commands = $Commands
        } | ConvertTo-Json -Depth 3 | Set-Content $path -Encoding UTF8
        return $path
    }

    $script:DefaultEntry = @{
        pattern  = "git reset --hard"
        reason   = "Destroys uncommitted work permanently"
        added_at = "2026-03-07T00:00:00Z"
        severity = "critical"
    }
}

# ─── Blocklist loading ───

Describe "Get-WhoopsBlocklist" {
    It "loads a valid blocklist" {
        $path = New-Blocklist -Commands @($script:DefaultEntry)
        $result = Get-WhoopsBlocklist -Path $path

        $result | Should -Not -BeNullOrEmpty
        $result.version | Should -Be 1
        $result.blocked_commands.Count | Should -Be 1
        $result.blocked_commands[0].pattern | Should -Be "git reset --hard"
    }

    It "loads multiple entries" {
        $entries = @(
            $script:DefaultEntry
            @{ pattern = "rm -rf /"; reason = "Recursive delete from root"; added_at = "2026-03-07T00:00:00Z"; severity = "critical" }
            @{ pattern = "DROP TABLE"; reason = "Destructive SQL"; added_at = "2026-03-07T00:00:00Z"; severity = "high" }
        )
        $path = New-Blocklist -Commands $entries
        $result = Get-WhoopsBlocklist -Path $path

        $result.blocked_commands.Count | Should -Be 3
    }

    It "returns null for missing file" {
        $result = Get-WhoopsBlocklist -Path "C:\nonexistent\path\blocklist.json"
        $result | Should -BeNullOrEmpty
    }

    It "returns null for malformed JSON" {
        $path = Join-Path $script:FixtureDir "bad.json"
        Set-Content $path -Value "not json at all" -Encoding UTF8
        $result = Get-WhoopsBlocklist -Path $path
        $result | Should -BeNullOrEmpty
    }

    It "returns null for wrong version" {
        $path = Join-Path $script:FixtureDir "wrongver.json"
        @{ version = 99; blocked_commands = @() } |
            ConvertTo-Json | Set-Content $path -Encoding UTF8
        $result = Get-WhoopsBlocklist -Path $path
        $result | Should -BeNullOrEmpty
    }

    It "returns null for missing blocked_commands key" {
        $path = Join-Path $script:FixtureDir "nokey.json"
        @{ version = 1 } | ConvertTo-Json | Set-Content $path -Encoding UTF8
        $result = Get-WhoopsBlocklist -Path $path
        $result | Should -BeNullOrEmpty
    }
}

# ─── Pattern matching ───

Describe "Test-WhoopsBlocked" {
    BeforeAll {
        $script:Entries = @(
            [PSCustomObject]@{ pattern = "git reset --hard"; reason = "Destroys work"; severity = "critical" }
            [PSCustomObject]@{ pattern = "rm -rf /"; reason = "Root delete"; severity = "critical" }
            [PSCustomObject]@{ pattern = "DROP TABLE"; reason = "Destructive SQL"; severity = "high" }
        )
    }

    Context "exact matches" {
        It "blocks exact pattern" {
            $result = Test-WhoopsBlocked -Command "git reset --hard" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
            $result.pattern | Should -Be "git reset --hard"
        }

        It "blocks exact pattern: rm -rf /" {
            $result = Test-WhoopsBlocked -Command "rm -rf /" -BlockedCommands $script:Entries
            $result.pattern | Should -Be "rm -rf /"
        }
    }

    Context "prefix matching" {
        It "blocks command with trailing arguments" {
            $result = Test-WhoopsBlocked -Command "git reset --hard HEAD~3" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
            $result.pattern | Should -Be "git reset --hard"
        }

        It "blocks command with long trailing args" {
            $result = Test-WhoopsBlocked -Command "git reset --hard abc123def456" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
        }

        It "blocks rm -rf with path" {
            $result = Test-WhoopsBlocked -Command "rm -rf /home/user" -BlockedCommands $script:Entries
            $result.pattern | Should -Be "rm -rf /"
        }
    }

    Context "mid-command matching" {
        It "blocks pattern after sudo" {
            $result = Test-WhoopsBlocked -Command "sudo git reset --hard" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
            $result.pattern | Should -Be "git reset --hard"
        }

        It "blocks pattern after pipe prefix" {
            $result = Test-WhoopsBlocked -Command "echo yes | rm -rf /" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
        }

        It "blocks SQL in query tool" {
            $result = Test-WhoopsBlocked -Command "psql -c 'DROP TABLE users'" -BlockedCommands $script:Entries
            $result.pattern | Should -Be "DROP TABLE"
        }
    }

    Context "case insensitivity" {
        It "matches uppercase input" {
            $result = Test-WhoopsBlocked -Command "GIT RESET --HARD" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
        }

        It "matches mixed case" {
            $result = Test-WhoopsBlocked -Command "Git Reset --Hard HEAD" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
        }

        It "matches mixed case SQL" {
            $result = Test-WhoopsBlocked -Command "drop table users" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "safe commands pass through" {
        It "allows git status" {
            $result = Test-WhoopsBlocked -Command "git status" -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }

        It "allows git reset (soft)" {
            $result = Test-WhoopsBlocked -Command "git reset --soft HEAD~1" -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }

        It "allows git reset (mixed, default)" {
            $result = Test-WhoopsBlocked -Command "git reset HEAD~1" -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }

        It "allows ls" {
            $result = Test-WhoopsBlocked -Command "ls -la" -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }

        It "allows rm on a specific file" {
            $result = Test-WhoopsBlocked -Command "rm temp.txt" -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }

        It "allows SELECT queries" {
            $result = Test-WhoopsBlocked -Command "psql -c 'SELECT * FROM users'" -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }
    }

    Context "edge cases" {
        It "returns null for empty string" {
            $result = Test-WhoopsBlocked -Command "" -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }

        It "returns null for whitespace" {
            $result = Test-WhoopsBlocked -Command "   " -BlockedCommands $script:Entries
            $result | Should -BeNullOrEmpty
        }

        It "returns null for null blocklist" {
            $result = Test-WhoopsBlocked -Command "git reset --hard" -BlockedCommands $null
            $result | Should -BeNullOrEmpty
        }

        It "returns null for empty blocklist" {
            $result = Test-WhoopsBlocked -Command "git reset --hard" -BlockedCommands @()
            $result | Should -BeNullOrEmpty
        }

        It "handles leading whitespace in command" {
            $result = Test-WhoopsBlocked -Command "  git reset --hard" -BlockedCommands $script:Entries
            $result | Should -Not -BeNullOrEmpty
        }

        It "does not false-positive on partial pattern" {
            $result = Test-WhoopsBlocked -Command "git resettle --hardly" -BlockedCommands $script:Entries
            # "git resettle" starts with "git reset" but not "git reset --hard"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "returns correct match metadata" {
        It "returns reason and severity" {
            $result = Test-WhoopsBlocked -Command "git reset --hard" -BlockedCommands $script:Entries
            $result.reason | Should -Be "Destroys work"
            $result.severity | Should -Be "critical"
        }

        It "returns first matching entry" {
            $entries = @(
                [PSCustomObject]@{ pattern = "git"; reason = "Broad git"; severity = "medium" }
                [PSCustomObject]@{ pattern = "git reset --hard"; reason = "Specific"; severity = "critical" }
            )
            $result = Test-WhoopsBlocked -Command "git reset --hard" -BlockedCommands $entries
            $result.reason | Should -Be "Broad git"
        }
    }
}
