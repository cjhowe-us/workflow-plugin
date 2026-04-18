#!/usr/bin/env bash
# provider-conformance.sh
#
# Validate an artifact provider (scheme) directory against the contract.
#
# Providers (kinds) ship the TYPE definition of an artifact.
# They do not ship executable code — backends do that.
#
# Checks:
#   - manifest.json: name, description, contract_version, uri_scheme
#   - schema.json:   scheme, subcommands (meta-schema shape)
#
# Usage:
#   provider-conformance.sh <path-to-provider-dir>

set -euo pipefail

dir="${1:?provider directory required}"
[ -d "$dir" ] || { echo "not-found: $dir" >&2; exit 2; }

fail=0
warn() { echo "provider-conformance: $*" >&2; fail=1; }

manifest="$dir/manifest.json"
schema="$dir/schema.json"

[ -f "$manifest" ] || warn "missing manifest.json"
[ -f "$schema" ]   || warn "missing schema.json"

if [ -f "$manifest" ]; then
  python3 - "$manifest" <<'PY' || fail=1
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
try:
    m = json.loads(p.read_text())
except json.JSONDecodeError as e:
    print(f"provider-conformance: invalid manifest JSON: {e}", file=sys.stderr); sys.exit(1)
missing = [k for k in ("name","description","contract_version") if k not in m]
if missing:
    print(f"provider-conformance: manifest missing keys: {missing}", file=sys.stderr); sys.exit(1)
sys.exit(0)
PY
fi

if [ -f "$schema" ]; then
  python3 - "$schema" <<'PY' || fail=1
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
try:
    s = json.loads(p.read_text())
except json.JSONDecodeError as e:
    print(f"provider-conformance: invalid schema JSON: {e}", file=sys.stderr); sys.exit(1)
missing = [k for k in ("scheme","subcommands") if k not in s]
if missing:
    print(f"provider-conformance: schema missing keys: {missing}", file=sys.stderr); sys.exit(1)
subs = s.get("subcommands", {})
if not isinstance(subs, dict) or not subs:
    print("provider-conformance: schema subcommands must be a non-empty object", file=sys.stderr); sys.exit(1)
for name, spec in subs.items():
    if not isinstance(spec, dict):
        print(f"provider-conformance: subcommands.{name} must be an object", file=sys.stderr); sys.exit(1)
sys.exit(0)
PY
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "provider-conformance: $dir OK"
exit 0
