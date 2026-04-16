# Parity test: every *.sh under the plugin root must have a sibling *.ps1,
# and every *.ps1 must parse under pwsh (parse errors fail the test).
#
# Runs cross-platform under pwsh (Windows/macOS/Linux). Exit 0 = pass,
# non-zero = fail.
#
# Usage:
#   pwsh -NoProfile -File env-setup/tests/test-parity.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$pluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$failures = New-Object System.Collections.Generic.List[string]
$checked  = 0

# The parity test itself is pwsh-only by nature. Exclude it from the
# bidirectional check.
$excludeBasenames = @('test-parity.ps1', 'test-parity.sh')

$shFiles = Get-ChildItem -Path $pluginRoot -Filter '*.sh' -File -Recurse |
  Where-Object { $excludeBasenames -notcontains $_.Name }
foreach ($sh in $shFiles) {
  $checked++
  $psPath = [System.IO.Path]::ChangeExtension($sh.FullName, '.ps1')
  if (-not (Test-Path $psPath)) {
    $failures.Add("MISSING: $($sh.FullName) -> expected $psPath")
    continue
  }

  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $psPath, [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) {
    foreach ($e in $parseErrors) {
      $failures.Add("PARSE ERROR: $psPath — $($e.Message) (line $($e.Extent.StartLineNumber))")
    }
  }
}

$psFiles = Get-ChildItem -Path $pluginRoot -Filter '*.ps1' -File -Recurse |
  Where-Object { $excludeBasenames -notcontains $_.Name }
foreach ($ps in $psFiles) {
  $shPath = [System.IO.Path]::ChangeExtension($ps.FullName, '.sh')
  if (-not (Test-Path $shPath)) {
    $failures.Add("ORPHAN: $($ps.FullName) has no sibling .sh (parity is bidirectional)")
  }
}

if ($failures.Count -eq 0) {
  Write-Host "parity OK — checked $checked .sh file(s), all .ps1 companions present and parseable"
  exit 0
}

Write-Host "parity FAILED:" -ForegroundColor Red
foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
exit 1
