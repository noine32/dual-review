# dual-review installer for Windows (PowerShell).
# Equivalent to ./install.sh on Linux/macOS, but uses Windows-style symlinks.
#
# Requires:
# - PowerShell 5.1+ (built into Windows 10+)
# - Developer Mode ON (Settings -> Update & Security -> For developers)
#   OR run as Administrator (symlink creation needs SeCreateSymbolicLinkPrivilege)
# - Codex CLI installed and in PATH (`codex login` done with ChatGPT Plus)
# - Git Bash or WSL for bash runtime (the skill calls scripts/run-codex.sh)
#
# Usage:
#   .\install.ps1
#   $env:CLAUDE_HOME = 'C:\custom\.claude'; .\install.ps1

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillSrc = Join-Path $ScriptDir 'skills\dual-review'

if (-not (Test-Path $SkillSrc -PathType Container)) {
    Write-Error "ERROR: skill source missing: $SkillSrc"
    exit 1
}

# Determine destination (CLAUDE_HOME or %USERPROFILE%\.claude).
if ($env:CLAUDE_HOME) {
    $ClaudeHome = $env:CLAUDE_HOME
} elseif ($env:USERPROFILE) {
    $ClaudeHome = Join-Path $env:USERPROFILE '.claude'
} else {
    Write-Error 'ERROR: neither CLAUDE_HOME nor USERPROFILE is set; cannot determine install destination'
    exit 1
}

$SkillDst = Join-Path $ClaudeHome 'skills\dual-review'

# Defensive: refuse paths starting with `-` (matches install.sh behavior).
if ($SkillSrc -like '-*' -or $SkillDst -like '-*') {
    Write-Error 'ERROR: install paths must not start with -'
    exit 1
}

# Ensure parent directory exists.
$ParentDir = Split-Path -Parent $SkillDst
if (-not (Test-Path $ParentDir)) {
    New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
}

# Handle existing destination.
if (Test-Path $SkillDst) {
    $item = Get-Item $SkillDst -Force
    $isSymlink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isSymlink) {
        Write-Host "Removing old symlink: $SkillDst"
        # Remove-Item handles symlinks correctly without recursing into target.
        Remove-Item -LiteralPath $SkillDst -Force
    } else {
        # Backup with timestamp + PID + random to avoid collisions.
        $stamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $rand = Get-Random -Minimum 1000 -Maximum 99999
        $Backup = "$SkillDst.bak.$stamp.$PID.$rand"
        Write-Host "Backing up existing path to: $Backup"
        Move-Item -LiteralPath $SkillDst -Destination $Backup
    }
}

# Create symbolic link.
try {
    New-Item -ItemType SymbolicLink -Path $SkillDst -Target $SkillSrc -ErrorAction Stop | Out-Null
    Write-Host "Installed: $SkillDst -> $SkillSrc"
} catch {
    Write-Error @"
Failed to create symlink.

Enable Developer Mode (Settings -> Update & Security -> For developers ->
'Developer Mode' = ON), or run this script as Administrator.

Original error: $_
"@
    exit 1
}

# Codex CLI presence check (warning only).
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    Write-Warning 'codex CLI not found in PATH. Install Codex CLI >= 0.57 (npm install -g @openai/codex) and run `codex login`.'
}

# Bash runtime check (warning only — required for scripts/run-codex.sh).
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Write-Warning 'bash not found in PATH. The skill calls scripts/run-codex.sh which requires bash. Install Git for Windows (https://git-scm.com/download/win) or use WSL.'
}

# timeout command check (informational — we handle absence via DUAL_ALLOW_NO_TIMEOUT).
if (-not (Get-Command timeout -ErrorAction SilentlyContinue) -and -not (Get-Command gtimeout -ErrorAction SilentlyContinue)) {
    Write-Host @"

Note: GNU 'timeout' / 'gtimeout' is not on PATH (this is normal on Windows).
By default, run-codex.sh refuses to run without a timeout (to avoid hangs).
To allow no-timeout execution, set:
  [System.Environment]::SetEnvironmentVariable('DUAL_ALLOW_NO_TIMEOUT', '1', 'User')
or in your shell:
  $env:DUAL_ALLOW_NO_TIMEOUT = '1'
"@
}
