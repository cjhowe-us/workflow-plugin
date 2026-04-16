# Extend the lock_expires_at on a pull request's marker. Caller must already
# hold the lock; the current lock_owner is verified before writing.
#
# Usage:
#   pwsh -NoProfile -File lock-heartbeat.ps1 `
#       -Repo <owner/name> -Pr <N> `
#       -ExpectedOwner <string> -ExpiresAt <YYYY-MM-DDTHH:MM:SSZ>
#
# Exit 0 on success, 1 if the lock has been stolen (owner mismatch or marker
# missing), 2 on usage error.

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$Repo,
  [Parameter(Mandatory = $true)] [int]$Pr,
  [Parameter(Mandatory = $true)] [string]$ExpectedOwner,
  [Parameter(Mandatory = $true)] [string]$ExpiresAt
)

$ErrorActionPreference = 'Stop'
$markerRegex = '(?m)^<!-- coordinator = (\{.*\}) -->$'

function Read-PrBody {
  $out = & gh pr view $Pr --repo $Repo --json body -q '.body' 2>$null
  if ($null -eq $out) { return '' }
  return [string]$out
}

function Extract-MarkerJson {
  param([string]$Body)
  $m = [regex]::Match($Body, $markerRegex)
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

function Strip-Marker {
  param([string]$Body)
  return [regex]::Replace($Body, "$markerRegex\r?\n?", '')
}

$body    = Read-PrBody
$curJson = Extract-MarkerJson -Body $body
if (-not $curJson) {
  Write-Error "stolen: marker missing on PR #$Pr"
  exit 1
}

$obj      = $curJson | ConvertFrom-Json
$curOwner = [string]$obj.lock_owner
if ($curOwner -ne $ExpectedOwner) {
  Write-Error "stolen: current owner is '$curOwner' (expected '$ExpectedOwner')"
  exit 1
}

$blockedBy = @()
if ($obj.blocked_by) { $blockedBy = @($obj.blocked_by) }

$newObj = [ordered]@{
  lock_owner      = $ExpectedOwner
  lock_expires_at = $ExpiresAt
  blocked_by      = $blockedBy
}
$newJson   = $newObj | ConvertTo-Json -Compress -Depth 10
$newMarker = "<!-- coordinator = $newJson -->"

$stripped = Strip-Marker -Body $body
$stripped = $stripped.TrimEnd("`n", "`r")
if ($stripped) {
  $newBody = "$stripped`n`n$newMarker"
} else {
  $newBody = $newMarker
}

$newBody | & gh pr edit $Pr --repo $Repo --body-file - | Out-Null

[ordered]@{
  heartbeat  = 'ok'
  expires_at = $ExpiresAt
  pr_number  = $Pr
  repo       = $Repo
} | ConvertTo-Json -Compress
