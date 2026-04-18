#!/usr/bin/env bash
# backend-conformance.sh
#
# Validate an artifact backend directory against the contract.
#
# Checks:
#   - manifest.json: name, description, contract_version, backs_schemes (>=1)
#   - artifact.sh:   exists + executable
#   - artifact.sh:   unknown subcommand → non-zero exit + JSON {"error":...}
#   - For each scheme in backs_schemes: the backend's artifact.sh contains
#     case arms for every `required: true` subcommand in that scheme's
#     schema.json (if the scheme's provider is discoverable in this
#     workspace).
#
# Usage:
#   backend-conformance.sh <path-to-backend-dir> [<path-to-plugins-root>]

set -euo pipefail

dir="${1:?backend directory required}"
plugins_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
[ -d "$dir" ] || { echo "not-found: $dir" >&2; exit 2; }

fail=0
warn() { echo "backend-conformance: $*" >&2; fail=1; }

manifest="$dir/manifest.json"
script="$dir/artifact.sh"

[ -f "$manifest" ] || warn "missing manifest.json"
[ -x "$script" ]   || warn "artifact.sh missing or not executable"

backs_schemes=""
if [ -f "$manifest" ]; then
  python3 - "$manifest" <<'PY' || fail=1
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
try:
    m = json.loads(p.read_text())
except json.JSONDecodeError as e:
    print(f"backend-conformance: invalid manifest JSON: {e}", file=sys.stderr); sys.exit(1)
missing = [k for k in ("name","description","contract_version","backs_schemes") if k not in m]
if missing:
    print(f"backend-conformance: manifest missing keys: {missing}", file=sys.stderr); sys.exit(1)
bs = m.get("backs_schemes")
if not isinstance(bs, list) or not bs:
    print("backend-conformance: backs_schemes must be a non-empty array", file=sys.stderr); sys.exit(1)
sys.exit(0)
PY
  backs_schemes="$(jq -r '.backs_schemes // [] | .[]' "$manifest" 2>/dev/null || true)"
fi

if [ -x "$script" ]; then
  if out=$("$script" __definitely_not_a_subcommand__ 2>&1); rc=$?; :; then :; fi
  if [ "${rc:-0}" -eq 0 ]; then
    warn "unknown-subcommand exited 0 (expected non-zero)"
  elif ! jq -e '.error' >/dev/null 2>&1 <<< "$out"; then
    warn "unknown-subcommand did not return {\"error\":...}"
  fi

  # Required-subcommand coverage. For each scheme the backend backs,
  # look up the scheme's schema.json anywhere under plugins_root and
  # confirm each required subcommand has a matching case arm.
  while IFS= read -r scheme; do
    [ -n "$scheme" ] || continue
    schema=$(find "$plugins_root" -type f -path "*/artifact-providers/$scheme/schema.json" 2>/dev/null | head -1)
    if [ -z "$schema" ]; then
      echo "backend-conformance: (info) scheme '$scheme' not locally discoverable; skipping subcommand coverage" >&2
      continue
    fi
    required=$(jq -r '.subcommands | to_entries[] | select(.value.required == true) | .key' "$schema" 2>/dev/null)
    while IFS= read -r sub; do
      [ -n "$sub" ] || continue
      if ! grep -qE "(^|[[:space:]|])${sub}(\)|\|)" "$script"; then
        warn "scheme=$scheme: required subcommand '$sub' not found in artifact.sh"
      fi
    done <<< "$required"
  done <<< "$backs_schemes"
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "backend-conformance: $dir OK"
exit 0
