# Ensure a user-scope environment variable is persisted for the user.
#
# On Windows: writes to HKCU:\Environment via
#   [Environment]::SetEnvironmentVariable(name, value, 'User')
# which updates the registry and broadcasts WM_SETTINGCHANGE so every new
# process (cmd, PowerShell, Git Bash, GUI apps) picks it up. This is the
# right persistence mechanism for user-scope env vars on Windows — a
# PowerShell $PROFILE file only affects PowerShell sessions.
#
# On macOS/Linux (pwsh): appends to the PowerShell $PROFILE file. There is
# no OS-wide user-env registry on these platforms; POSIX shells should use
# ensure-env.sh instead.
#
# Idempotent on both platforms.
#
# Usage:
#   pwsh -NoProfile -File ensure-env.ps1 -VarName <NAME> -VarValue <VALUE> [-Comment <TEXT>] [-DryRun]

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$VarName,
  [Parameter(Mandatory = $true)] [string]$VarValue,
  [string]$Comment,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Windows path: registry (HKCU:\Environment)
# ---------------------------------------------------------------------------
if ($IsWindows) {
  $current = [Environment]::GetEnvironmentVariable($VarName, 'User')
  if ($current -eq $VarValue) {
    Write-Host "already set in HKCU:\Environment ($VarName=$current). No change."
    exit 0
  }

  if ($DryRun) {
    Write-Host "would set user env var via registry:"
    Write-Host "    [Environment]::SetEnvironmentVariable('$VarName', '$VarValue', 'User')"
    Write-Host "    (writes HKCU:\Environment\$VarName and broadcasts WM_SETTINGCHANGE)"
    if ($null -ne $current) {
      Write-Host "    current value: '$current'"
    } else {
      Write-Host "    current value: (not set)"
    }
    exit 0
  }

  [Environment]::SetEnvironmentVariable($VarName, $VarValue, 'User')
  Write-Host "set $VarName=$VarValue in HKCU:\Environment (user scope)."
  Write-Host "New processes (incl. new terminals) will inherit it automatically."
  Write-Host "The current process's env is unchanged — relaunch this shell to see it."
  exit 0
}

# ---------------------------------------------------------------------------
# macOS/Linux pwsh path: $PROFILE file
# ---------------------------------------------------------------------------
$line = "`$env:$VarName = '$VarValue'"

$profilePath = $PROFILE
if (-not $profilePath) {
  Write-Error "Could not resolve `$PROFILE — are you running in PowerShell?"
  exit 1
}

if (Test-Path $profilePath) {
  $existing = Get-Content -Raw -Path $profilePath -ErrorAction SilentlyContinue
  if ($existing -match [regex]::Escape($VarName)) {
    Write-Host "already set in $profilePath. No change."
    exit 0
  }
}

if ($DryRun) {
  Write-Host "would append to ${profilePath}:"
  Write-Host "    $line"
  exit 0
}

$dir = Split-Path -Parent $profilePath
if (-not (Test-Path $dir)) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
if (-not (Test-Path $profilePath)) {
  New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$header = if ($Comment) { "# $Comment" } else { '' }

@"

$header
$line
"@ | Add-Content -Path $profilePath -Encoding UTF8

Write-Host "appended $VarName=$VarValue to $profilePath."
Write-Host "Open a new PowerShell session (or '. $profilePath') to pick it up."
