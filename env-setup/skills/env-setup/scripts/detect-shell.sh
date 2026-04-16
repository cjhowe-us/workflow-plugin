#!/usr/bin/env bash
# Detect the user's interactive shell and emit the right config file + syntax
# for setting a persistent environment variable.
#
# Usage: detect-shell.sh [--var NAME] [--value VALUE]
#   --var    env var name (default: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)
#   --value  env var value (default: 1)
#
# Emits JSON on stdout, e.g.:
#   {"shell":"zsh","config_file":"/Users/me/.zshrc","syntax":"export",
#    "line":"export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"}
#
# Exits non-zero if the shell cannot be detected or is unsupported.
#
# PowerShell on native Windows is out of scope for this bash script — use
# the companion `detect-shell.ps1` instead. Bash-compatible shells on
# Windows (Git Bash, WSL) are covered here.
set -euo pipefail

VAR="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
VALUE="1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --var)   VAR="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

shell_path="${SHELL:-}"
shell_bin=$(basename "$shell_path" 2>/dev/null || true)

if [[ -z "$shell_bin" ]]; then
  echo "cannot detect shell: \$SHELL is empty" >&2
  exit 1
fi

cfg=""
syntax=""
line=""
case "$shell_bin" in
  zsh)
    cfg="$HOME/.zshrc"
    syntax="export"
    line="export ${VAR}=${VALUE}"
    ;;
  bash)
    # On macOS, Terminal.app runs bash as a login shell by default, which
    # reads ~/.bash_profile. On Linux, interactive non-login shells read
    # ~/.bashrc. Prefer the file that already exists; else pick the
    # platform-conventional default.
    if [[ -f "$HOME/.bash_profile" ]]; then
      cfg="$HOME/.bash_profile"
    elif [[ -f "$HOME/.bashrc" ]]; then
      cfg="$HOME/.bashrc"
    elif [[ "${OSTYPE:-}" == darwin* ]]; then
      cfg="$HOME/.bash_profile"
    else
      cfg="$HOME/.bashrc"
    fi
    syntax="export"
    line="export ${VAR}=${VALUE}"
    ;;
  fish)
    cfg="$HOME/.config/fish/config.fish"
    syntax="set -gx"
    line="set -gx ${VAR} ${VALUE}"
    ;;
  sh|dash|ksh)
    # POSIX-ish. ~/.profile is the standard login-shell rc.
    cfg="$HOME/.profile"
    syntax="export"
    line="export ${VAR}=${VALUE}"
    ;;
  pwsh|powershell)
    # Running PowerShell through a bash wrapper is unusual but possible on
    # Linux/macOS. Defer to detect-shell.ps1 for native Windows usage.
    echo "PowerShell detected via \$SHELL — run detect-shell.ps1 in PowerShell itself to get the correct profile path." >&2
    exit 3
    ;;
  *)
    echo "unsupported shell: $shell_bin (path: $shell_path)" >&2
    exit 1
    ;;
esac

# jq is nice but not guaranteed. Hand-roll minimal JSON escaping — the values
# we emit are filesystem paths and simple identifiers, no quotes/newlines.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

printf '{"shell":"%s","config_file":"%s","syntax":"%s","line":"%s","var":"%s","value":"%s"}\n' \
  "$(esc "$shell_bin")" \
  "$(esc "$cfg")" \
  "$(esc "$syntax")" \
  "$(esc "$line")" \
  "$(esc "$VAR")" \
  "$(esc "$VALUE")"
