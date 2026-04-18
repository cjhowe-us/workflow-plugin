#!/usr/bin/env bash
# Per-OS path resolver for artifact plugin state.
#
# Sourced by other scripts. Exports:
#   ARTIFACT_CONFIG_DIR  — preferences, per-scheme defaults, tutor flags
#   ARTIFACT_CACHE_DIR   — graph cache, discovery registry
#   ARTIFACT_STATE_DIR   — flocks, ephemeral runtime state
#
# Paths honor XDG on Linux; use Library dirs on macOS; use %APPDATA% /
# %LOCALAPPDATA% on Windows (MSYS/Cygwin/Git-Bash).

set -euo pipefail

__artifact_xdg_resolve() {
  local os
  os="$(uname -s 2>/dev/null || echo unknown)"

  case "$os" in
    Darwin)
      : "${ARTIFACT_CONFIG_DIR:=$HOME/Library/Application Support/artifact}"
      : "${ARTIFACT_CACHE_DIR:=$HOME/Library/Caches/artifact}"
      : "${ARTIFACT_STATE_DIR:=$HOME/Library/Application Support/artifact/state}"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      local appdata="${APPDATA:-$HOME/AppData/Roaming}"
      local localappdata="${LOCALAPPDATA:-$HOME/AppData/Local}"
      : "${ARTIFACT_CONFIG_DIR:=$appdata/artifact}"
      : "${ARTIFACT_CACHE_DIR:=$localappdata/artifact/cache}"
      : "${ARTIFACT_STATE_DIR:=$localappdata/artifact/state}"
      ;;
    *)
      : "${ARTIFACT_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/artifact}"
      : "${ARTIFACT_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/artifact}"
      : "${ARTIFACT_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/artifact}"
      ;;
  esac

  export ARTIFACT_CONFIG_DIR ARTIFACT_CACHE_DIR ARTIFACT_STATE_DIR
}

__artifact_xdg_resolve

# When invoked directly (not sourced), print resolved paths as JSON.
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  printf '{"config_dir":%s,"cache_dir":%s,"state_dir":%s}\n' \
    "$(printf '%s' "$ARTIFACT_CONFIG_DIR" | jq -Rs .)" \
    "$(printf '%s' "$ARTIFACT_CACHE_DIR"  | jq -Rs .)" \
    "$(printf '%s' "$ARTIFACT_STATE_DIR"  | jq -Rs .)"
fi
