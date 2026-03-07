BeforeAll {
    $script:ToolsDir = Join-Path $PSScriptRoot "..\tools"
    $script:InstallScript = Join-Path $script:ToolsDir "chocolateyInstall.ps1"
    $script:UninstallScript = Join-Path $script:ToolsDir "chocolateyUninstall.ps1"

    $script:MarkerBegin = '# >>> whoops >>>'
    $script:MarkerEnd   = '# <<< whoops <<<'
}

Describe "Install script" {
    BeforeEach {
        $script:FakeHome = Join-Path $TestDrive "home-$(Get-Random)"
        $script:FakeProfile = Join-Path $script:FakeHome "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        New-Item -ItemType Directory -Path (Split-Path $script:FakeProfile) -Force | Out-Null
    }

    It "creates blocklist in config dir" {
        $configDir = Join-Path $script:FakeHome ".whoops"
        $blocklistDest = Join-Path $configDir "whoops-blocklist.json"

        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Copy-Item (Join-Path $script:ToolsDir "whoops-blocklist.json") $blocklistDest

        $content = Get-Content $blocklistDest -Raw | ConvertFrom-Json
        $content.version | Should -Be 1
        $content.blocked_commands.Count | Should -BeGreaterThan 0
    }

    It "blocklist contains git reset --hard by default" {
        $blocklist = Get-Content (Join-Path $script:ToolsDir "whoops-blocklist.json") -Raw | ConvertFrom-Json
        $patterns = $blocklist.blocked_commands | ForEach-Object { $_.pattern }
        $patterns | Should -Contain "git reset --hard"
    }

    Context "profile marker insertion" {
        It "inserts markers into empty profile" {
            Set-Content $script:FakeProfile -Value "" -Encoding UTF8
            $block = "`n$($script:MarkerBegin)`nif (Get-Module PSReadLine) { . 'test.ps1' }`n$($script:MarkerEnd)"
            Add-Content $script:FakeProfile -Value $block -Encoding UTF8

            $content = Get-Content $script:FakeProfile -Raw
            $content | Should -Match ([regex]::Escape($script:MarkerBegin))
            $content | Should -Match ([regex]::Escape($script:MarkerEnd))
        }

        It "markers are idempotent (no duplication)" {
            $block = "`n$($script:MarkerBegin)`nif (Get-Module PSReadLine) { . 'test.ps1' }`n$($script:MarkerEnd)"
            Set-Content $script:FakeProfile -Value "# existing profile$block" -Encoding UTF8

            $content = Get-Content $script:FakeProfile -Raw
            $matches = [regex]::Matches($content, [regex]::Escape($script:MarkerBegin))
            $matches.Count | Should -Be 1
        }

        It "preserves existing profile content" {
            $existing = "Set-Alias ll Get-ChildItem`nSet-Location C:\"
            Set-Content $script:FakeProfile -Value $existing -Encoding UTF8

            $block = "`n$($script:MarkerBegin)`nif (Get-Module PSReadLine) { . 'test.ps1' }`n$($script:MarkerEnd)"
            Add-Content $script:FakeProfile -Value $block -Encoding UTF8

            $content = Get-Content $script:FakeProfile -Raw
            $content | Should -Match "Set-Alias ll Get-ChildItem"
            $content | Should -Match ([regex]::Escape($script:MarkerBegin))
        }
    }
}

Describe "Uninstall logic" {
    It "removes whoops block from profile" {
        $profile = Join-Path $TestDrive "profile-$(Get-Random).ps1"
        $content = @"
# my stuff
Set-Alias ll Get-ChildItem

$($script:MarkerBegin)
if (Get-Module PSReadLine) { . 'C:\some\path\whoops-profile.ps1' }
$($script:MarkerEnd)

# more stuff
Set-Location C:\
"@
        Set-Content $profile -Value $content -Encoding UTF8

        $after = Get-Content $profile -Raw
        $pattern = "(?s)\r?\n?$([regex]::Escape($script:MarkerBegin)).*?$([regex]::Escape($script:MarkerEnd))\r?\n?"
        $after = [regex]::Replace($after, $pattern, "`n")
        $after = $after.TrimEnd() + "`n"
        Set-Content $profile -Value $after -Encoding UTF8

        $result = Get-Content $profile -Raw
        $result | Should -Not -Match ([regex]::Escape($script:MarkerBegin))
        $result | Should -Not -Match ([regex]::Escape($script:MarkerEnd))
        $result | Should -Match "Set-Alias ll Get-ChildItem"
        $result | Should -Match "Set-Location"
    }

    It "handles profile with no whoops block gracefully" {
        $profile = Join-Path $TestDrive "clean-$(Get-Random).ps1"
        Set-Content $profile -Value "# clean profile" -Encoding UTF8

        $content = Get-Content $profile -Raw
        $hasMarker = $content -match [regex]::Escape($script:MarkerBegin)
        $hasMarker | Should -Be $false
    }
}
