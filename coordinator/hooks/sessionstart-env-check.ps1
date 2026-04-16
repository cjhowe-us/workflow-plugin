# SessionStart hook (PowerShell). Hard-blocks if agent teams is not enabled.
# Warns about missing `gh` auth or missing `repos:` config, but does not
# block those.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Read stdin payload (hooks receive JSON on stdin). Ignore if empty.
$inputJson = ''
if ([Console]::IsInputRedirected) {
  $inputJson = [Console]::In.ReadToEnd()
}

# Agent teams experimental flag — REQUIRED.
if ($env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -ne '1') {
  [Console]::Error.WriteLine("coordinator plugin: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is not set to 1.")
  [Console]::Error.WriteLine("The orchestrator cannot dispatch workers without agent teams.")
  [Console]::Error.WriteLine("")
  [Console]::Error.WriteLine("Invoke the env-setup plugin's skill to persist it for your shell:")
  [Console]::Error.WriteLine("    /env-setup:env-setup CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1")
  [Console]::Error.WriteLine("")
  [Console]::Error.WriteLine("Or run the scripts directly:")
  [Console]::Error.WriteLine("  bash/zsh/fish:  env-setup/skills/env-setup/scripts/ensure-env.sh --var CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS --value 1")
  [Console]::Error.WriteLine("  PowerShell:     pwsh -NoProfile -File env-setup/skills/env-setup/scripts/ensure-env.ps1 -VarName CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -VarValue 1")
  [Console]::Error.WriteLine("")
  [Console]::Error.WriteLine("Then restart your terminal.")
  exit 2
}

$warnings = New-Object System.Collections.Generic.List[string]

# gh CLI present and authenticated
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  $warnings.Add("gh CLI is not installed — coordinator drives GitHub via gh.")
} else {
  & gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    $warnings.Add("gh CLI is not authenticated — run 'gh auth login' with repo scope.")
  }
}

# Coordinator config file with `repos:` list.
$cwd = $null
if ($inputJson) {
  try {
    $cwd = ($inputJson | ConvertFrom-Json).cwd
  } catch { }
}
if (-not $cwd) { $cwd = (Get-Location).Path }
$cfg = Join-Path $cwd '.claude/coordinator.local.md'
if (-not (Test-Path $cfg)) {
  $warnings.Add("No .claude/coordinator.local.md found at $cwd — orchestrator will prompt for the repos list on first /coordinator invocation.")
} else {
  $hasRepos = $false
  foreach ($line in Get-Content -Path $cfg) {
    if ($line -match '^repos:\s*$') { $hasRepos = $true; break }
  }
  if (-not $hasRepos) {
    $warnings.Add("$cfg has no 'repos:' list — orchestrator will prompt for it on first /coordinator invocation.")
  }
}

if ($warnings.Count -eq 0) {
  '{}'
  exit 0
}

$msg = "coordinator plugin warnings:`n"
foreach ($w in $warnings) { $msg += "  - $w`n" }

[ordered]@{
  hookSpecificOutput = [ordered]@{
    hookEventName     = 'SessionStart'
    additionalContext = $msg
  }
} | ConvertTo-Json -Compress -Depth 10
