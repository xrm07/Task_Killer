#!/usr/bin/env bash
set -euo pipefail

# Stage, commit, and push a report file if it changed.
# Usage: git_sync_report.sh --path ./reports/open_tasks.md [--branch BRANCH]

log() { printf '[git-sync] %s\n' "$*" >&2; }
warn() { printf '[git-sync][warn] %s\n' "$*" >&2; }
fail() { printf '[git-sync][error] %s\n' "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "command not found: $1"; }

require_cmd git

main() {
  local path="" branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path) path="$2"; shift 2;;
      --branch) branch="$2"; shift 2;;
      *) fail "Unknown arg: $1";;
    esac
  done
  [[ -n "$path" ]] || fail "--path is required"

  # Determine repo root relative to this script
  local repo_root
  repo_root="$(cd "$(dirname -- "$0")/../.." && pwd)"
  cd "$repo_root"

  # Ensure file exists; if not, nothing to do
  [[ -f "$path" ]] || { warn "file not found: $path"; exit 0; }

  # Stage target file
  git add -- "$path"

  # If no staged changes, exit quietly
  if git diff --cached --quiet -- "$path"; then
    log "no changes to commit for $path"
    exit 0
  fi

  # Commit with a deterministic message
  git commit -m "chore(report): auto-update open tasks report [skip ci]"

  # Determine branch if not provided
  if [[ -z "$branch" ]]; then
    branch="$(git rev-parse --abbrev-ref HEAD || echo main)"
  fi

  # Prefer token-based push if available
  local token="${GIT_SYNC_TOKEN:-${GITHUB_TOKEN:-}}"
  local remote_url owner_repo token_url
  remote_url="$(git config --get remote.origin.url || true)"
  if [[ -n "$token" && -n "$remote_url" ]]; then
    # Extract owner/repo from remote URL
    owner_repo="$(echo "$remote_url" | sed -E 's#(git@github.com:|https://github.com/)([^/.]+/[^/.]+)(\.git)?$#\2#')"
    if [[ -n "$owner_repo" ]]; then
      token_url="https://x-access-token:${token}@github.com/${owner_repo}.git"
      if ! git push "$token_url" "$branch" 2>/dev/null; then
        warn "token push failed; falling back to origin"
      else
        log "synced $path to origin/$branch (token)"; exit 0
      fi
    fi
  fi

  # Try normal push; if rejected, rebase and retry once
  if ! git push origin "$branch"; then
    warn "initial push failed; attempting pull --rebase and retry"
    git pull --rebase --autostash || { warn "pull --rebase failed"; }
    git push origin "$branch" || warn "push failed; leaving local commit only"
  fi

  log "synced $path to origin/$branch"
}

main "$@"


