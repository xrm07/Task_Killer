#!/usr/bin/env bash
set -euo pipefail

# Generate a Markdown report of open (pending) TaskWarrior tasks.
# Usage:
#   report_open_tasks.sh --output ./reports/open_tasks.md [--project NAME]

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd task
require_cmd jq

log() { printf '[report] %s\n' "$*" >&2; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

main() {
  local output_path="" project_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output) output_path="$2"; shift 2;;
      --project) project_filter="$2"; shift 2;;
      *) fail "Unknown arg: $1";;
    esac
  done
  [[ -n "$output_path" ]] || fail "--output is required (path to markdown file)"

  local tmpfile
  tmpfile=$(mktemp)

  {
    printf '# Open Tasks\n\n'
    printf -- '- Generated: %s\n' "$(date -Is)"
    if [[ -n "$project_filter" ]]; then
      printf -- '- Filter: project=%s\n' "$project_filter"
    fi
    printf '\n'
    printf '| ID | Project | Priority | Due | Progress | Description |\n'
    printf '|---:|:--------|:--------:|:----|---------:|:------------|\n'

    if [[ -n "$project_filter" ]]; then
      task rc.verbose:off status:pending project:"$project_filter" export \
        | jq -r '
          def esc(x): if x == null then "-" else (x|tostring|gsub("\\|"; "\\|")) end;
          .[] | "| \(.id) | \(esc(.project)) | \(esc(.priority)) | \(esc(.due)) | \(esc(.progress)) | \(esc(.description)) |"'
    else
      task rc.verbose:off status:pending export \
        | jq -r '
          def esc(x): if x == null then "-" else (x|tostring|gsub("\\|"; "\\|")) end;
          .[] | "| \(.id) | \(esc(.project)) | \(esc(.priority)) | \(esc(.due)) | \(esc(.progress)) | \(esc(.description)) |"'
    fi
  } >"$tmpfile"

  mkdir -p "$(dirname -- "$output_path")"
  mv "$tmpfile" "$output_path"
  log "Markdown report written to: $output_path"
}

main "$@"


