#!/usr/bin/env bash
# Shared helpers sourced by every script in scripts/.
set -euo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_LIB_DIR}/.." && pwd)"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '\033[1;33m[%s] WARN:\033[0m %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
err()  { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command '$c' not found in PATH"
  done
}

require_file() {
  [[ -f "$1" ]] || die "required file not found: $1"
}

require_env() {
  local var
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || die "required environment variable '$var' is not set (did you source config/env.sh?)"
  done
}

# render_template <template-file> <output-file>
# Expands ${VAR} references from the current environment via envsubst.
render_template() {
  local template="$1" output="$2"
  require_cmd envsubst
  require_file "$template"
  mkdir -p "$(dirname "$output")"
  envsubst < "$template" > "$output"
  log "rendered $(basename "$template") -> $output"
}

# wait_until <timeout-seconds> <interval-seconds> <description> <command...>
# Retries <command...> until it exits 0, or dies after <timeout-seconds>.
wait_until() {
  local timeout="$1" interval="$2" desc="$3"
  shift 3
  local waited=0
  log "waiting for: ${desc} (timeout ${timeout}s)"
  until "$@" >/dev/null 2>&1; do
    if (( waited >= timeout )); then
      die "timed out after ${timeout}s waiting for: ${desc}"
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done
  log "ready: ${desc}"
}

load_env() {
  local env_file="${REPO_ROOT}/config/env.sh"
  [[ -f "$env_file" ]] || die "missing ${env_file} — copy config/env.example.sh to config/env.sh and edit it first"
  # shellcheck disable=SC1090
  source "$env_file"
  mkdir -p "${WORK_DIR}/generated"
}
