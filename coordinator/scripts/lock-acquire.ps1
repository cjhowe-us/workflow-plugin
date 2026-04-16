# Acquire the coordinator lock on a pull request by splicing an HTML-comment
# marker into the PR body.
#
# Marker format (single line, appended to the body):
#   <!-- coordinator = {"lock_owner":"...","lock_expires_at":"...","blocked_by":[...]} -->
#
# Usage:
#   pwsh -NoProfile -File lock-acquire.ps1 `
#       -Repo <owner/name> -Pr <N> `
#       -Owner <string> -ExpiresAt <YYYY-MM-DDTHH:MM:SSZ>
#
# Exit 0 on success, 1 on race (another owner holds a non-expired lock),
# 2 on usage error.

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$Repo,
  [Parameter(Mandatory = $true)] [int]$Pr,
  [Parameter(Mandatory = $true)] [string]$Owner,
  [Parameter(Mandatory = $true)] [string]$ExpiresAt
)

$ErrorActionPreference = 'Stop'
$markerRegex = '(?m)^<!-- coordinator = (\{.*\}) -->$'

function Read-PrBody {
  param([int]$PrNumber, [string]$RepoName)
  $out = & gh pr view $PrNumber --repo $RepoName --json body -q '.body' 2>$null
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

$nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$body   = Read-PrBody -PrNumber $Pr -RepoName $Repo
$curJson = Extract-MarkerJson -Body $body
$curOwner = ''; $curExpiry = ''; $curBlockedBy = @()
if ($curJson) {
  $obj = $curJson | ConvertFrom-Json
  if ($obj.lock_owner)      { $curOwner      = [string]$obj.lock_owner }
  if ($obj.lock_expires_at) { $curExpiry     = [string]$obj.lock_expires_at }
  if ($obj.blocked_by)      { $curBlockedBy  = @($obj.blocked_by) }
}

# Abort if another owner holds a non-expired lock.
if ($curOwner -and $curExpiry -and ([string]::Compare($curExpiry, $nowIso) -gt 0) -and ($curOwner -ne $Owner)) {
  Write-Error "raced: held by $curOwner until $curExpiry"
  exit 1
}

$newObj = [ordered]@{
  lock_owner      = $Owner
  lock_expires_at = $ExpiresAt
  blocked_by      = $curBlockedBy
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

# gh pr edit reads body-file from stdin via `-`.
$newBody | & gh pr edit $Pr --repo $Repo --body-file - | Out-Null

# Race mitigation: 100-500ms backoff, re-read, verify ownership.
Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)

$verifyJson = Extract-MarkerJson -Body (Read-PrBody -PrNumber $Pr -RepoName $Repo)
$verOwner = ''
if ($verifyJson) { $verOwner = [string](($verifyJson | ConvertFrom-Json).lock_owner) }

if ($verOwner -ne $Owner) {
  try {
    & (Join-Path $PSScriptRoot 'lock-release.ps1') -Repo $Repo -Pr $Pr 2>$null | Out-Null
  } catch { }
  Write-Error "raced: overwritten by $verOwner after write"
  exit 1
}

[ordered]@{
  acquired   = $true
  owner      = $Owner
  expires_at = $ExpiresAt
  at         = $nowIso
  pr_number  = $Pr
  repo       = $Repo
} | ConvertTo-Json -Compress
