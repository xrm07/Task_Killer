#!/usr/bin/env bash
set -euo pipefail

# Install TaskWarrior hooks that regenerate the open-tasks Markdown report
# whenever tasks are added/modified/done/deleted.

TARGET_REPORT_PATH_DEFAULT="$(pwd)/reports/open_tasks.md"

usage() {
  cat <<'USAGE'
install_taskwarrior_hooks.sh - Install hooks to auto-refresh open tasks report

Options:
  --report-path PATH   Output markdown path (default: ./reports/open_tasks.md)
  --project NAME       Optional project filter for the report
  --branch NAME        Git branch to push to (default: current HEAD branch)

Notes:
  - This will create symlinks in ~/.task/hooks pointing to the local scripts.
  - Hooks: on-exit（TaskWarrior終了時に実行）。大量イベントでの過負荷を避けるため on-add/on-modify は使用しません。
USAGE
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; }; }

require_cmd task
require_cmd ln
require_cmd bash

main() {
  local report_path="$TARGET_REPORT_PATH_DEFAULT" project_filter="" branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --report-path) report_path="$2"; shift 2;;
      --project) project_filter="$2"; shift 2;;
      --branch) branch="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; usage; exit 2;;
    esac
  done

  local hooks_dir="$HOME/.task/hooks"
  mkdir -p "$hooks_dir"

  local repo_root
  repo_root="$(cd "$(dirname -- "$0")/.." && pwd)"

  # Ensure helper scripts are executable
  chmod +x "$repo_root/scripts/report_open_tasks.sh" || true
  chmod +x "$repo_root/scripts/git_sync_report.sh" || true

  # Create wrapper that calls report and then git-sync with configured path/filter/branch
  local wrapper="$repo_root/scripts/_report_wrapper.sh"
  cat > "$wrapper" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
"$repo_root/scripts/report_open_tasks.sh" --output "$report_path" ${project_filter:+--project "$project_filter"}
"$repo_root/scripts/git_sync_report.sh" --path "$report_path" ${branch:+--branch "$branch"}
WRAP
  chmod +x "$wrapper"

  # Create symlinked hooks
  ln -sf "$wrapper" "$hooks_dir/on-exit"
  chmod +x "$hooks_dir/on-exit"

  echo "Hooks installed to: $hooks_dir"
  echo "Report target: $report_path ${project_filter:+(project=$project_filter)}"
}

main "$@"


