# dual-review uninstaller for Windows (PowerShell).
# Removes only the symlink; backups (.bak.*) are left alone.

$ErrorActionPreference = 'Stop'

if ($env:CLAUDE_HOME) {
    $ClaudeHome = $env:CLAUDE_HOME
} elseif ($env:USERPROFILE) {
    $ClaudeHome = Join-Path $env:USERPROFILE '.claude'
} else {
    Write-Error 'ERROR: neither CLAUDE_HOME nor USERPROFILE is set; cannot determine install destination'
    exit 1
}

$SkillDst = Join-Path $ClaudeHome 'skills\dual-review'

# Defensive guard.
if ($SkillDst -like '-*') {
    Write-Error "ERROR: SKILL_DST must not start with '-': $SkillDst"
    exit 1
}

if (Test-Path $SkillDst) {
    $item = Get-Item $SkillDst -Force
    $isSymlink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isSymlink) {
        Remove-Item -LiteralPath $SkillDst -Force
        Write-Host "Removed symlink: $SkillDst"
    } else {
        Write-Error "ERROR: $SkillDst is not a symlink. Skipping (manual removal required)."
        exit 1
    }
} else {
    Write-Host "Nothing to remove at $SkillDst"
}
