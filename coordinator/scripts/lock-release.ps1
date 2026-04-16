# Release the coordinator lock on a pull request by stripping its HTML-comment
# marker from the PR body. Idempotent.
#
# Usage:
#   pwsh -NoProfile -File lock-release.ps1 -Repo <owner/name> -Pr <N>
#       Strip the marker regardless of owner. Used on graceful worker finish.
#
#   pwsh -NoProfile -File lock-release.ps1 -Repo <owner/name> -Pr <N> `
#       -ExpectedOwner <string>
#       Strip only if the current marker's lock_owner matches.

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$Repo,
  [Parameter(Mandatory = $true)] [int]$Pr,
  [string]$ExpectedOwner
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
  [ordered]@{
    released  = $false
    pr_number = $Pr
    repo      = $Repo
    reason    = 'no-marker'
  } | ConvertTo-Json -Compress
  exit 0
}

if ($ExpectedOwner) {
  $curOwner = [string](($curJson | ConvertFrom-Json).lock_owner)
  if ($curOwner -ne $ExpectedOwner) {
    [ordered]@{
      released       = $false
      pr_number      = $Pr
      repo           = $Repo
      reason         = 'owner-mismatch'
      current_owner  = $curOwner
    } | ConvertTo-Json -Compress
    exit 0
  }
}

$stripped = Strip-Marker -Body $body
$stripped = $stripped.TrimEnd("`n", "`r")

$stripped | & gh pr edit $Pr --repo $Repo --body-file - | Out-Null

[ordered]@{
  released  = $true
  pr_number = $Pr
  repo      = $Repo
} | ConvertTo-Json -Compress
