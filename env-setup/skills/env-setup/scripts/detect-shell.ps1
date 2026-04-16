# Detect the user's interactive shell and emit the right config file + syntax
# for setting a persistent environment variable.
#
# Usage:
#   pwsh -NoProfile -File detect-shell.ps1 [-VarName NAME] [-VarValue VALUE]
#
# Emits JSON on stdout, e.g.:
#   {"shell":"pwsh","config_file":"...","syntax":"env:",
#    "line":"$env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = '1'"}
#
# Cross-platform: runs under pwsh on Windows, macOS, Linux. Under pwsh this
# always reports PowerShell (because that's what's executing); to detect a
# POSIX shell (zsh/bash/fish) call detect-shell.sh from bash instead.

[CmdletBinding()]
param(
  [string]$VarName  = 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS',
  [string]$VarValue = '1'
)

$ErrorActionPreference = 'Stop'

# On Windows, persistent user-scope env vars live in the registry
# (HKCU:\Environment), not a profile script. This is the right place to write
# because it's picked up by every shell and GUI app launched by the user, not
# just PowerShell. Setting via [Environment]::SetEnvironmentVariable(...,'User')
# writes the registry value AND broadcasts WM_SETTINGCHANGE to running apps.
#
# On macOS/Linux under pwsh, there is no Windows registry — fall back to the
# PowerShell $PROFILE file. (POSIX shells use detect-shell.sh instead.)
if ($IsWindows) {
  $obj = [ordered]@{
    shell       = 'pwsh'
    config_file = 'HKCU:\Environment'
    syntax      = 'registry'
    line        = "[Environment]::SetEnvironmentVariable('$VarName', '$VarValue', 'User')"
    var         = $VarName
    value       = $VarValue
  }
  $obj | ConvertTo-Json -Compress
  exit 0
}

$profilePath = $PROFILE
if (-not $profilePath) {
  Write-Error "cannot resolve `$PROFILE — are you running in PowerShell?"
  exit 1
}

$line = "`$env:$VarName = '$VarValue'"

$obj = [ordered]@{
  shell       = 'pwsh'
  config_file = $profilePath
  syntax      = 'env:'
  line        = $line
  var         = $VarName
  value       = $VarValue
}

$obj | ConvertTo-Json -Compress
