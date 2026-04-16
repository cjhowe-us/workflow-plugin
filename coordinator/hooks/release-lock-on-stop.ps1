# SubagentStop / TaskCompleted hook (PowerShell). Releases any PR locks held
# by the stopped coordinator-worker by scanning each configured repo and
# clearing markers whose lock_owner matches the stopped worker's id.
# Idempotent.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$inputJson = ''
if ([Console]::IsInputRedirected) {
  $inputJson = [Console]::In.ReadToEnd()
}

if (-not $inputJson) { '{}'; exit 0 }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { '{}'; exit 0 }

try {
  $payload = $inputJson | ConvertFrom-Json
} catch {
  '{}'; exit 0
}

$agentId = $payload.agent_id
if (-not $agentId) { $agentId = $payload.subagent_id }
if (-not $agentId) { $agentId = $payload.task_id }
if (-not $agentId) { '{}'; exit 0 }

# Skip if not a coordinator worker.
$subagentType = $payload.subagent_type
if (-not $subagentType) { $subagentType = $payload.agent_type }
if ($subagentType -and $subagentType -ne 'coordinator-worker') { '{}'; exit 0 }

$cwd = $payload.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$cfg = Join-Path $cwd '.claude/coordinator.local.md'
if (-not (Test-Path $cfg)) { '{}'; exit 0 }

# Parse repos list from YAML frontmatter.
$repos = New-Object System.Collections.Generic.List[string]
$inFm = $false; $inRepos = $false
foreach ($line in Get-Content -Path $cfg) {
  if ($line -match '^---\s*$') { $inFm = -not $inFm; continue }
  if (-not $inFm) { continue }
  if ($line -match '^repos:\s*$') { $inRepos = $true; continue }
  if ($inRepos -and $line -match '^\s*-\s*(.+?)\s*$') {
    $name = $Matches[1].Trim('"').Trim("'")
    if ($name) { $repos.Add($name) }
  } elseif ($inRepos -and $line -match '^[^\s]') {
    $inRepos = $false
  }
}
if ($repos.Count -eq 0) { '{}'; exit 0 }

$pluginRoot = $env:CLAUDE_PLUGIN_ROOT
if (-not $pluginRoot) {
  $pluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$scan    = Join-Path $pluginRoot 'scripts/pr-scan.ps1'
$release = Join-Path $pluginRoot 'scripts/lock-release.ps1'

foreach ($repo in $repos) {
  try {
    $lines = & pwsh -NoProfile -File $scan -Repos $repo 2>$null
  } catch {
    continue
  }
  foreach ($line in $lines) {
    if (-not $line) { continue }
    try {
      $rec = $line | ConvertFrom-Json
    } catch { continue }
    if (-not $rec.number) { continue }
    if ($rec.lock_owner -and ($rec.lock_owner -like "*$agentId*")) {
      try {
        & pwsh -NoProfile -File $release `
          -Repo $repo -Pr $rec.number -ExpectedOwner $rec.lock_owner *> $null
      } catch { }
    }
  }
}

'{}'
