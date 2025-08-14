# Task_Killer

Turn natural-language (Japanese) instructions into TaskWarrior commands via a tiny helper script and AI prompting.

## Overview

Task_Killer streamlines day-to-day TaskWarrior operations in two ways:

- Helper script: `Task_Killer/scripts/tw.sh` normalizes dates and priorities, finds tasks by fuzzy title, updates a progress UDA, and performs common operations non-interactively.
- AI prompt guide: `Task_Killer/GEMINI.md` documents how to translate Japanese free-form text into executable TaskWarrior commands (Gemini CLI assumed), including few-shot examples and normalization rules.

## Features

- Natural-language friendly operations: add, update progress, start/stop/done, list, and info
- Date normalization: accepts inputs like `MM-DD-HH:MM` or `M/D HH:MM` and converts to `YYYY-MM-DDTHH:MM`, rolling over to next year if necessary
- Priority normalization: maps common Japanese words (e.g., “高/最優先/重要” → H, “普通” → M, “低/低め” → L)
- Progress UDA updates: `uda.progress` (integer 0–100)
- Fuzzy task selection by description substring, with candidate listing when ambiguous
- Non-interactive execution with `rc.confirmation:no`

## Requirements

- TaskWarrior
- jq
- bash (for `tw.sh`)
- UDA setup in `~/.taskrc` (example below)

```ini
# ~/.taskrc example
uda.progress.type=numeric
uda.progress.label=Progress
```

If using an AI CLI (e.g., Gemini CLI), set it up separately. See `Task_Killer/GEMINI.md` for details.

## Installation

```bash
# Clone the repository
git clone https://github.com/your-username/Task_Killer.git
cd Task_Killer

# Make the helper executable (if needed)
chmod +x Task_Killer/scripts/tw.sh

# Optional: add to PATH for convenience (consider adding to your shell profile)
export PATH="$PWD/Task_Killer/scripts:$PATH"
```

## Usage (script)

`tw.sh` wraps common TaskWarrior operations and prints the command it is about to run.

```bash
# Add a task (date/priority will be normalized)
Task_Killer/scripts/tw.sh \
  add --title "Formal Languages and Automata" --due "12-30-23:50" --priority 高め

# Update progress (0–100)
Task_Killer/scripts/tw.sh \
  progress --title "Formal Languages and Automata" --value 50

# Start / stop / complete
Task_Killer/scripts/tw.sh start --title "Formal Languages and Automata"
Task_Killer/scripts/tw.sh stop  --title "Formal Languages and Automata"
Task_Killer/scripts/tw.sh done  --title "Formal Languages and Automata"

# List / info
Task_Killer/scripts/tw.sh list
Task_Killer/scripts/tw.sh info --title "Formal Languages and Automata"
```

Tips:
- You can use `--id` instead of `--title` for `progress/start/stop/done/info`.
- If multiple or no matches are found, the script prints candidates and exits with code 2.

## AI Integration (Gemini CLI example)

`Task_Killer/GEMINI.md` describes prompting strategies, normalization rules, and few-shot examples that convert Japanese free-form inputs into executable TaskWarrior commands.

```bash
# From the repository root
gemini    # follow the guidance in Task_Killer/GEMINI.md
```

## Examples

```bash
# Example 1: Add (auto-completes year and normalizes to ISO-like format)
Task_Killer/scripts/tw.sh \
  add --title "Formal Languages and Automata" --due "12-30-23:50" --priority 高め

# Example 2: Mark as in progress
Task_Killer/scripts/tw.sh start --title "Formal Languages and Automata"

# Example 3: Update progress to 65
Task_Killer/scripts/tw.sh progress --title "Formal Languages and Automata" --value 65

# Example 4: Show current task list
Task_Killer/scripts/tw.sh list
```

## Project Structure

```
Task_Killer/
├─ LICENSE
├─ README.md
└─ Task_Killer/
   ├─ GEMINI.md
   └─ scripts/
      └─ tw.sh
```

## Contributing

Issues and pull requests are welcome. The script is written in bash and uses `set -euo pipefail`. For larger changes, please open an issue to discuss before submitting a PR.

## License

MIT License. See `LICENSE` for details.

## Troubleshooting

- “Could not parse datetime” or “Invalid datetime”: verify the input format, or use `YYYY-MM-DDTHH:MM` explicitly.
- Multiple/no candidates: provide a more specific title or use `--id`.
- `task`/`jq` not found: ensure both are installed and available in `PATH`.
