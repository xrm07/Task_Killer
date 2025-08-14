#!/usr/bin/env bash
set -euo pipefail

# Simple TaskWarrior helper for Gemini CLI
# - Adds tasks with due/priority normalization
# - Updates progress (UDA progress: 0-100)
# - Starts/stops/done tasks by title lookup
# - Lists and shows info

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd task
require_cmd jq

log() { printf '[tw] %s\n' "$*" >&2; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# Return ISO-like format YYYY-MM-DDTHH:MM
# Accepts inputs like:
#  - YYYY-MM-DDTHH:MM
#  - YYYY-MM-DD HH:MM
#  - MM-DD-HH:MM
#  - MM/DD HH:MM
#  - 12-30-23:50
normalize_datetime() {
  local raw="$1"

  # If already like YYYY-MM-DDTHH:MM or YYYY-MM-DD HH:MM, normalize the separator
  if echo "$raw" | grep -Eq '^([0-9]{4}-[0-9]{2}-[0-9]{2})[ T][0-9]{2}:[0-9]{2}$'; then
    printf '%s\n' "$raw" | sed -E 's/ /T/'
    return 0
  fi

  # Extract digits and infer
  local digits
  digits=$(echo "$raw" | sed -E 's/[^0-9]+/ /g' | awk '{$1=$1};1')
  local count
  count=$(wc -w <<< "$digits" | awk '{print $1}')

  local year month day hour minute
  local now_year
  now_year=$(date +%Y)

  if [[ $count -eq 5 ]]; then
    # y m d h m
    read -r year month day hour minute <<< "$digits"
  elif [[ $count -eq 4 ]]; then
    # m d h m (assume current year, possibly roll over to next year if in the past)
    year=$now_year
    read -r month day hour minute <<< "$digits"
  else
    # last-resort: let date try to parse
    local maybe
    if maybe=$(date -d "$raw" +%FT%R 2>/dev/null); then
      echo "$maybe"
      return 0
    fi
    fail "Could not parse datetime: $raw"
  fi

  # zero-pad
  printf -v month '%02d' "$month"
  printf -v day '%02d' "$day"
  printf -v hour '%02d' "$hour"
  printf -v minute '%02d' "$minute"

  local candidate epoch now_epoch
  candidate="${year}-${month}-${day}T${hour}:${minute}"
  if ! epoch=$(date -d "$candidate" +%s 2>/dev/null); then
    fail "Invalid datetime after normalization: $candidate"
  fi
  now_epoch=$(date +%s)

  # If input had no explicit year and candidate is in the past, roll over to next year
  if [[ $count -eq 4 && $epoch -le $now_epoch ]]; then
    year=$((year + 1))
    candidate="${year}-${month}-${day}T${hour}:${minute}"
    if ! date -d "$candidate" +%s >/dev/null 2>&1; then
      fail "Invalid datetime after year rollover: $candidate"
    fi
  fi

  echo "$candidate"
}

# Find candidates by description substring (pending tasks by default)
find_candidates() {
  local query="$1"
  task rc.verbose:off status:pending export \
    | jq -r --arg q "$query" '.[] | select(.description | contains($q)) | "\(.id)\t\(.description)"'
}

# Get first matching id by description substring
first_id_by_description() {
  local query="$1"
  task rc.verbose:off status:pending export \
    | jq -r --arg q "$query" 'map(select(.description | contains($q)))[0].id // empty'
}

# Map Japanese priority words to H/M/L
normalize_priority() {
  local raw="$1"
  case "$raw" in
    H|h|high|High|HIGH) echo H ;;
    M|m|mid|medium|Medium|MEDIUM) echo M ;;
    L|l|low|Low|LOW) echo L ;;
    * )
      # Japanese words
      if [[ "$raw" =~ 高|最優先|重要 ]]; then echo H; return 0; fi
      if [[ "$raw" =~ 中|普通 ]]; then echo M; return 0; fi
      if [[ "$raw" =~ 低 ]]; then echo L; return 0; fi
      echo "$raw" # pass-through
      ;;
  esac
}

cmd_add() {
  local title="" due_raw="" priority_raw=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2;;
      --due) due_raw="$2"; shift 2;;
      --priority) priority_raw="$2"; shift 2;;
      *) fail "Unknown arg for add: $1";;
    esac
  done
  [[ -n "$title" ]] || fail "--title is required"
  [[ -n "$due_raw" ]] || fail "--due is required"
  [[ -n "$priority_raw" ]] || fail "--priority is required"

  local due_iso priority
  due_iso=$(normalize_datetime "$due_raw")
  priority=$(normalize_priority "$priority_raw")

  log "task rc.confirmation:no add \"$title\" due:$due_iso priority:$priority"
  task rc.confirmation:no add "$title" due:"$due_iso" priority:"$priority"
}

cmd_progress() {
  local title="" id="" value=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2;;
      --id) id="$2"; shift 2;;
      --value) value="$2"; shift 2;;
      *) fail "Unknown arg for progress: $1";;
    esac
  done
  [[ -n "$value" ]] || fail "--value is required (0-100)"
  [[ "$value" =~ ^[0-9]{1,3}$ ]] || fail "progress must be integer 0-100"
  if (( value < 0 || value > 100 )); then fail "progress out of range: $value"; fi

  if [[ -z "$id" ]]; then
    [[ -n "$title" ]] || fail "--title or --id is required"
    id=$(first_id_by_description "$title")
  fi
  [[ -n "$id" ]] || { find_candidates "$title" | sed '1s/^/Multiple or no matches:\n/'; exit 2; }

  log "task rc.confirmation:no $id modify progress:$value"
  task rc.confirmation:no "$id" modify progress:"$value"
}

cmd_start_stop_done() {
  local action="$1"; shift
  local title="" id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2;;
      --id) id="$2"; shift 2;;
      *) fail "Unknown arg for $action: $1";;
    esac
  done
  if [[ -z "$id" ]]; then
    [[ -n "$title" ]] || fail "--title or --id is required"
    id=$(first_id_by_description "$title")
  fi
  [[ -n "$id" ]] || { find_candidates "$title" | sed '1s/^/Multiple or no matches:\n/'; exit 2; }

  log "task rc.confirmation:no $id $action"
  task rc.confirmation:no "$id" "$action"
}

cmd_list() {
  task next | cat
}

cmd_info() {
  local title="" id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2;;
      --id) id="$2"; shift 2;;
      *) fail "Unknown arg for info: $1";;
    esac
  done
  if [[ -z "$id" ]]; then
    [[ -n "$title" ]] || fail "--title or --id is required"
    id=$(first_id_by_description "$title")
  fi
  [[ -n "$id" ]] || { find_candidates "$title" | sed '1s/^/Multiple or no matches:\n/'; exit 2; }
  task "$id" info | cat
}

usage() {
  cat <<'USAGE'
tw.sh - TaskWarrior helper

Commands:
  add --title "TITLE" --due "12-30-23:50" --priority H|M|L
  progress --title "TITLE" --value 0-100
  start --title "TITLE"
  stop --title "TITLE"
  done --title "TITLE"
  list
  info --title "TITLE"

Notes:
  - --id can be used instead of --title for progress/start/stop/done/info
  - --due supports MM-DD-HH:MM or YYYY-MM-DDTHH:MM
USAGE
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    add) cmd_add "$@" ;;
    progress) cmd_progress "$@" ;;
    start) cmd_start_stop_done start "$@" ;;
    stop) cmd_start_stop_done stop "$@" ;;
    done) cmd_start_stop_done done "$@" ;;
    list) cmd_list ;;
    info) cmd_info "$@" ;;
    -h|--help|help|"") usage ;;
    *) fail "Unknown command: $cmd" ;;
  esac
}

main "$@"


