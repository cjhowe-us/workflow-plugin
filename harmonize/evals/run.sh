#!/bin/bash
# Data-driven structural sanity eval for the workflow repo.
# Reads cases.yaml and runs deterministic checks on agents, hooks,
# hooks.json files, and plugin manifests. No LLM, no flakes.
# Always exits 0 (no hard cutoff); aggregated report to stdout.

set -u
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CASES_FILE="$SCRIPT_DIR/cases.yaml"

if [ ! -f "$CASES_FILE" ]; then
  printf 'ERROR: cases file not found: %s\n' "$CASES_FILE" >&2
  exit 2
fi
if ! command -v yq >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'ERROR: yq and jq required\n' >&2
  exit 2
fi

CASES_JSON="$(yq -o=json '.' "$CASES_FILE")"

PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS + 1)); printf '  PASS %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  FAIL %s\n' "$1"; }

# Read a field from cases.yaml. Usage: q '.agents.model_regex'
q() { printf '%s' "$CASES_JSON" | jq -r "$1"; }

# Read an array field. Usage: q_array '.agents.globs'
q_array() { printf '%s' "$CASES_JSON" | jq -r "$1 // [] | .[]"; }

extract_frontmatter() {
  awk '/^---$/{c++; next} c==1{print} c>1{exit}' "$1"
}

expand_globs() {
  local -a out=()
  local glob abs
  while IFS= read -r glob; do
    [ -z "$glob" ] && continue
    for abs in "$WORKFLOW_DIR"/$glob; do
      [ -e "$abs" ] && out+=("$abs")
    done
  done < <(q_array "$1")
  printf '%s\n' "${out[@]}"
}

# --- agent suite --------------------------------------------------------------

check_agent() {
  local file="$1"
  local base
  base="$(basename "$file" .md)"
  local rel="${file#"$WORKFLOW_DIR"/}"
  printf '\n[agent] %s\n' "$rel"

  local fm
  fm="$(extract_frontmatter "$file")"
  if [ -z "$fm" ] || ! echo "$fm" | yq eval '.' - >/dev/null 2>&1; then
    fail "$base: frontmatter parse"
    return
  fi
  pass "$base: frontmatter parse"

  local req
  while IFS= read -r req; do
    [ -z "$req" ] && continue
    local val
    val="$(echo "$fm" | yq eval ".${req} // \"\"" -)"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      fail "$base: missing .${req}"
    else
      pass "$base: has .${req}"
    fi
  done < <(q_array '.agents.required_fields')

  local name
  name="$(echo "$fm" | yq eval '.name // ""' -)"
  if [ "$name" != "$base" ]; then
    fail "$base: name '$name' != filename"
  else
    pass "$base: name matches filename"
  fi

  local desc desc_len dmin dmax
  desc="$(echo "$fm" | yq eval '.description // ""' -)"
  desc_len=${#desc}
  dmin=$(q '.agents.description_min_length')
  dmax=$(q '.agents.description_max_length')
  if [ "$desc_len" -lt "$dmin" ] || [ "$desc_len" -gt "$dmax" ]; then
    fail "$base: description length $desc_len out of [$dmin,$dmax]"
  else
    pass "$base: description length $desc_len"
  fi

  local model mregex
  model="$(echo "$fm" | yq eval '.model // ""' -)"
  mregex=$(q '.agents.model_regex')
  if echo "$model" | grep -Eq "$mregex"; then
    pass "$base: model '$model'"
  else
    fail "$base: model '$model' !~ $mregex"
  fi

  local tool_count tmin
  tool_count="$(echo "$fm" | yq eval '.tools | length' - 2>/dev/null || echo 0)"
  tmin=$(q '.agents.tools_min_length')
  if [ "${tool_count:-0}" -lt "$tmin" ]; then
    fail "$base: tools count $tool_count < $tmin"
  else
    pass "$base: tools count $tool_count"
  fi

  local body body_lines bmin
  body="$(awk '/^---$/{c++; next} c>=2' "$file")"
  body_lines=$(printf '%s' "$body" | wc -l | tr -d ' ')
  bmin=$(q '.agents.body_min_lines')
  if [ "${body_lines:-0}" -lt "$bmin" ]; then
    fail "$base: body lines $body_lines < $bmin"
  else
    pass "$base: body lines $body_lines"
  fi

  if [ "$(q '.agents.body_require_h1')" = "true" ]; then
    if printf '%s' "$body" | grep -q '^# '; then
      pass "$base: body has H1"
    else
      fail "$base: body missing H1"
    fi
  fi
}

# --- hook script suite --------------------------------------------------------

check_hook_script() {
  local script="$1"
  local rel="${script#"$WORKFLOW_DIR"/}"
  printf '\n[hook] %s\n' "$rel"

  if [ ! -f "$script" ]; then
    fail "$rel: missing"
    return
  fi
  pass "$rel: exists"

  if [ "$(q '.hook_scripts.require_executable')" = "true" ]; then
    if [ -x "$script" ]; then
      pass "$rel: executable"
    else
      fail "$rel: not executable"
    fi
  fi

  if [ "$(q '.hook_scripts.require_shebang')" = "true" ]; then
    if head -1 "$script" | grep -q '^#!'; then
      pass "$rel: has shebang"
    else
      fail "$rel: missing shebang"
    fi
  fi

  if [ "$(q '.hook_scripts.require_shellcheck_clean')" = "true" ] &&
     command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x "$script" >/dev/null 2>&1; then
      pass "$rel: shellcheck clean"
    else
      fail "$rel: shellcheck warnings"
    fi
  fi
}

# --- hooks.json suite ---------------------------------------------------------

# resolve_mode: plugin = Claude ${CLAUDE_PLUGIN_ROOT} (parent of hooks/);
#               cursor_plugin = Cursor plugin root (parent of hooks/), commands ./...
check_hooks_json() {
  local hooks_json="$1"
  local resolve_mode="${2:-plugin}"
  local rel="${hooks_json#"$WORKFLOW_DIR"/}"
  printf '\n[hooks.json] %s\n' "$rel"

  if [ ! -f "$hooks_json" ]; then
    fail "$rel: missing"
    return
  fi
  if ! jq -e '.' "$hooks_json" >/dev/null 2>&1; then
    fail "$rel: invalid JSON"
    return
  fi
  pass "$rel: valid JSON"

  local require_resolve="false"
  if [ "$resolve_mode" = "cursor_plugin" ]; then
    [ "$(q '.hooks_json_cursor_plugins.require_commands_resolve')" = "true" ] && require_resolve="true"
  else
    [ "$(q '.hooks_json.require_commands_resolve')" = "true" ] && require_resolve="true"
  fi

  if [ "$require_resolve" = "true" ]; then
    local plugin_dir cmds missing=0 resolved
    plugin_dir="$(cd "$(dirname "$hooks_json")/.." && pwd)"
    cmds="$(jq -r '.. | .command? // empty' "$hooks_json" 2>/dev/null)"
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      if [ "$resolve_mode" = "cursor_plugin" ]; then
        if [[ "$cmd" == *'${'* ]]; then
          fail "$rel: use paths relative to plugin root (./...), not: $cmd"
          missing=$((missing + 1))
          continue
        fi
        if [[ "$cmd" == /* ]]; then
          resolved="$cmd"
        elif [[ "$cmd" == ./* ]]; then
          resolved="${plugin_dir}/${cmd#./}"
        else
          resolved="${plugin_dir}/$cmd"
        fi
      else
        resolved="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$plugin_dir}"
      fi
      if [ ! -f "$resolved" ]; then
        fail "$rel: command not found: $cmd"
        missing=$((missing + 1))
      fi
    done <<< "$cmds"
    [ "$missing" -eq 0 ] && pass "$rel: all commands resolve"
  fi
}

# --- plugin manifest suite ----------------------------------------------------

check_plugin_manifest() {
  local manifest="$1"
  local rel="${manifest#"$WORKFLOW_DIR"/}"
  printf '\n[plugin.json] %s\n' "$rel"

  if [ ! -f "$manifest" ]; then
    fail "$rel: missing"
    return
  fi
  if ! jq -e '.' "$manifest" >/dev/null 2>&1; then
    fail "$rel: invalid JSON"
    return
  fi
  pass "$rel: valid JSON"

  local field val
  while IFS= read -r field; do
    [ -z "$field" ] && continue
    val="$(jq -r ".${field} // \"\"" "$manifest")"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      fail "$rel: missing .${field}"
    else
      pass "$rel: has .${field}"
    fi
  done < <(q_array '.plugin_manifests.required_fields')
}

# --- run ----------------------------------------------------------------------

printf '=== workflow sanity eval ===\n'
printf 'cases: %s\n' "$CASES_FILE"

printf '\n-- agents --\n'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_agent "$f"
done < <(expand_globs '.agents.globs')

printf '\n-- hook scripts --\n'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_hook_script "$f"
done < <(expand_globs '.hook_scripts.globs')

printf '\n-- hooks.json (Claude plugins) --\n'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_hooks_json "$WORKFLOW_DIR/$f" plugin
done < <(q_array '.hooks_json.files')

printf '\n-- hooks.json (Cursor plugins) --\n'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_hooks_json "$WORKFLOW_DIR/$f" cursor_plugin
done < <(q_array '.hooks_json_cursor_plugins.files')

printf '\n-- plugin manifests --\n'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  check_plugin_manifest "$WORKFLOW_DIR/$f"
done < <(q_array '.plugin_manifests.files')

# --- summary ------------------------------------------------------------------

TOTAL=$((PASS + FAIL))
printf '\n=== summary ===\n'
printf 'total  %d\n' "$TOTAL"
printf 'pass   %d\n' "$PASS"
printf 'fail   %d\n' "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  printf '\nfailures:\n'
  for f in "${FAILURES[@]}"; do
    printf '  - %s\n' "$f"
  done
fi

exit 0
