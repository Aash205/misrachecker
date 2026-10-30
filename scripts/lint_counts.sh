#!/usr/bin/env bash
# Run the lint and print finding counts per rule id, plus a total. Used to record and compare
# baselines between refactoring steps. Exit status is always 0; read the numbers.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

bash "$ROOT/scripts/lint.sh" >"$log" 2>&1
grep -o -E '\[[a-zA-Z0-9.-]+\]$' "$log" | tr -d '[]' | sort | uniq -c | sort -rn
echo "$(grep -c -E '\[[a-zA-Z0-9.-]+\]$' "$log") total"
