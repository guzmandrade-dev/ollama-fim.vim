#!/usr/bin/env bash
# Run the headless test suite.
#   bash scripts/test.sh          # uses `vim` from PATH
#   VIM=/path/to/vim bash scripts/test.sh
set -u
cd "$(dirname "$0")/.."
VIM="${VIM:-vim}"
RESULTS="test_results.txt"
rm -f "$RESULTS"
"$VIM" -Nu tests/minimal.vim -n -es -S tests/run_tests.vim
status=$?
cat "$RESULTS" 2>/dev/null
exit "$status"
