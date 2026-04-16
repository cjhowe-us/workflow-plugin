# Scan one or more GitHub repositories for coordinator-managed pull requests
# and emit one JSON record per PR on stdout. A PR is in scope when it is
# open, draft, and carries a `phase:<name>` label.
#
# Usage:
#   pwsh -NoProfile -File pr-scan.ps1 -Repos <owner/name>,<owner/name>
#
# Record shape (one per line):
#   {
#     "repo": "owner/name",
#     "number": 12,
#     "state": "open",
#     "is_draft": true,
#     "head_ref_name": "coordinator/specify-login",
#     "phase": "specify",
#     "lock_owner": "macbook:sess1:worker-1" | "",
#     "lock_expires_at": "2026-04-16T18:45:00Z" | "",
#     "blocked_by": [42, 57]
#   }

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]]$Repos
)

$ErrorActionPreference = 'Stop'
$markerRegex = '(?m)^<!-- coordinator = (\{.*\}) -->$'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Error "gh is required"
  exit 2
}

function Extract-MarkerJson {
  param([string]$Body)
  $m = [regex]::Match($Body, $markerRegex)
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

foreach ($repo in $Repos) {
  $raw = & gh pr list --repo $repo --state open --limit 100 `
    --json 'number,state,isDraft,headRefName,labels,body'
  $prs = $raw | ConvertFrom-Json
  foreach ($pr in $prs) {
    $phase = ''
    foreach ($l in $pr.labels) {
      if ($l.name -like 'phase:*') { $phase = $l.name.Substring(6); break }
    }
    if (-not $phase) { continue }

    $body       = if ($null -eq $pr.body) { '' } else { [string]$pr.body }
    $markerJson = Extract-MarkerJson -Body $body
    $lockOwner = ''; $lockExpiresAt = ''; $blockedBy = @()
    if ($markerJson) {
      $obj = $markerJson | ConvertFrom-Json
      if ($obj.lock_owner)      { $lockOwner     = [string]$obj.lock_owner }
      if ($obj.lock_expires_at) { $lockExpiresAt = [string]$obj.lock_expires_at }
      if ($obj.blocked_by)      { $blockedBy     = @($obj.blocked_by) }
    }

    $state = ''
    if ($pr.state) { $state = ([string]$pr.state).ToLower() }

    $record = [ordered]@{
      repo            = $repo
      number          = $pr.number
      state           = $state
      is_draft        = [bool]$pr.isDraft
      head_ref_name   = $pr.headRefName
      phase           = $phase
      lock_owner      = $lockOwner
      lock_expires_at = $lockExpiresAt
      blocked_by      = $blockedBy
    }
    $record | ConvertTo-Json -Compress -Depth 10
  }
}
