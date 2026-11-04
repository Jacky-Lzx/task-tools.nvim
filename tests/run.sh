#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export NVIM_LOG_FILE="${TMPDIR:-/tmp}/task-tools-test-nvim.log"
"${NVIM_BIN:-nvim}" --headless -u NONE -i NONE -l tests/core.lua
"${NVIM_BIN:-nvim}" --headless -u NONE -i NONE -l tests/workflows.lua
"${NVIM_BIN:-nvim}" --headless -u NONE -i NONE -l tests/terminal_windows.lua
python3 tests/tui.py
