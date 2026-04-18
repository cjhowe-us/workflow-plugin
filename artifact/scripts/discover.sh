#!/usr/bin/env bash
# discover.sh
#
# Rebuild the artifact registry. Thin wrapper over the SessionStart hook;
# call during a session to pick up newly-installed plugins without
# reopening Claude Code.
set -euo pipefail
plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
exec "$plugin_root/hooks/sessionstart-discover.sh"
