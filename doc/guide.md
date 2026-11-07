# Workflow and integration guide

[Quick start](../README.md) · [Complete reference](task-tools.txt)

Configuration defaults and API contracts are maintained in the help reference.
The examples here illustrate particular workflows.

## Installation details

For lazy.nvim (the `main` field is necessary because the Lua module uses an underscore):

```lua
{
  "Jacky-Lzx/task-tools.nvim",
  main = 'task_tools',
  cmd = {
    'TaskRun', 'TaskShell', 'TaskOpen', 'TaskClose', 'TaskToggle',
    'TaskStop', 'TaskRerun', 'TaskOutput', 'TaskQuickfix', 'TaskDelete',
    'TaskWatch', 'TaskTerminal', 'TaskSave', 'TaskLoad',
  },
  opts = {},
}
```

Or put the plugin in `pack/*/start/`. No mappings or editor-wide UI overrides are
installed. `vim.ui.input` / `vim.ui.select` use your existing UI, including
selection-tools when it owns `vim.ui.select`.

## Commands

| Command | Action |
| --- | --- |
| `:TaskRun [name]` | Select a discovered task, or run an exact name. `!` focuses its output. |
| `:TaskShell [command]` | Run a shell command; omitted command opens a prompt. |
| `:TaskShell! [command]` | Run the command in a focused interactive PTY. |
| `:TaskTerminal` | Toggle a persistent interactive shell for the current directory. |
| `:TaskOpen`, `:TaskClose`, `:TaskToggle` | Show/hide the task list. |
| `:TaskOutput [id]` | Show a task's output and focus it. |
| `:TaskStop [id]` | Disable its watcher and stop the process. |
| `:TaskRerun [id]` | Run the captured definition again with a new ID. |
| `:TaskWatch [id]` | Disable watch, or rerun a completed task with watch enabled. |
| `:TaskQuickfix [id]` | Export retained output into a new quickfix snapshot. |
| `:TaskDelete [id]` | Remove a completed task and its output buffer. |
| `:TaskSave {file}`, `:TaskLoad {file}` | Save/restore task definitions as JSON. |

An omitted ID means the **most recent run**, not the currently focused output.
In the task list, actions apply to the selected row:
`Enter` output, `r` rerun, `s` stop, `w` toggle watch, `d` delete,
`c` quickfix, `q`/`Esc` close. Active tasks must finish or be stopped before
rerunning, deleting, or enabling watch.

Output buffers use `q` to hide and `gq` to export quickfix. In pipe output,
`Enter` jumps to a file location. In terminals, `Ctrl-]` enters Terminal-Normal
mode; the native `Ctrl-\ Ctrl-N` also works. Then `q` hides the window. Hiding
keeps the process alive; wiping a terminal buffer stops its process and watcher.

Example mappings (add them yourself when ready to integrate):

```lua
vim.keymap.set('n', '<leader>tr', '<cmd>TaskRun<cr>')
vim.keymap.set('n', '<leader>tt', '<cmd>TaskToggle<cr>')
vim.keymap.set('n', '<leader>tc', '<cmd>TaskShell<cr>')
vim.keymap.set({ 'n', 't' }, '<A-i>', function()
  require('task_tools').terminal()
end)
```

## Project tasks

`:TaskRun` discovers the nearest ancestor containing `.task-tools.json`,
`Cargo.toml`, `package.json`, `Makefile`/`makefile`, `CMakeLists.txt`,
`pyproject.toml` or `.git`. Without a marker it uses the current file's directory;
non-file buffers use `:pwd`. Discovery captures the source buffer before opening
the picker. Files are run from disk; buffers are not saved automatically.

Built-ins include Cargo build/run/test/check, Make targets, CMake configure/build
and CTest, package scripts (pnpm/yarn/bun/npm selected by lockfile), current Python,
C/C++, shell, LaTeX, Typst, Markdown and Verilog tasks. C/C++ build and run are
separate tasks. Tools must be installed separately. Existing TeX language/build
plugins keep ownership of their automatic behavior; these are explicit commands.

Add `.task-tools.json` to a project:

```json
{
  "version": 1,
  "tasks": [
    { "name": "build", "cmd": ["cargo", "build"], "watch": ["*.rs", "Cargo.toml"] },
    { "name": "server", "cmd": ["npm", "run", "dev"], "mode": "terminal" },
    { "name": "tests", "cmd": "make test 2>&1 | tee test.log", "cwd": "." }
  ]
}
```

Reading the file only registers choices. Commands run when explicitly selected.
JSON accepts data only; project Lua is never loaded. Relative `cwd` is resolved
against the discovered root. Names are unique: configured definitions win over
project definitions, registered providers, and built-ins, in that order.

Watch uses `BufWritePost`, matching saves within the task's captured directory.
`watch = true` matches every saved file there; a list matches relative paths or
basenames with Vim globs. A burst of saves debounces into a stop/restart; the new
run waits for the previous process to exit. Only the latest run owns the watcher.
External filesystem changes are not watched. A native command such as
`typst watch` already handles filesystem watching and does not need `watch = true`.

## Output and sessions

Pipe output strips ANSI/OSC escapes and recognizes GCC/Clang locations, Rust
location arrows, Python traceback locations and MSVC locations. Relative paths
resolve from the captured task directory even if the editor later changes cwd.
Formats parse one line at a time; custom `errorformat` should use single-line
patterns. Shell `cd` and recursive Make directory stacks are not tracked.

Quickfix is an explicit snapshot: running output never overwrites another list.
Run `:TaskQuickfix` again for new output. Scroll to the end of pipe output to
follow; scrolling away preserves your view. Terminal screen rendering is native
Neovim; quickfix uses the captured PTY stream, which is useful for compiler logs
but does not reconstruct full-screen TUIs.

Completed output is bounded by `max_lines` and each line by `max_line_bytes`.
Pipe and PTY logs include a final unterminated line; embedded NUL displays as
`^@`. PTY scrollback has its own native Neovim bound. When starting a new run,
old completed runs are pruned to `history`; active runs and live watchers are
retained even if they exceed that limit. Jobs are stopped when Neovim exits.

`:TaskSave` writes a JSON bundle atomically, keeping the newest definition for
each unique command/name/directory/mode/watch combination. It excludes process
state, output, environment values and stdin. `:TaskLoad` validates the whole file
and registers its choices in `:TaskRun`, without starting anything. Environments
come from the new editor process and current configuration. It does not install
automatic session hooks. Sessions should exclude task UI/terminal buffers; save
task definitions explicitly in your session integration.

This plugin does not provide snippet interpreter semantics, debugger ownership,
dependency graphs, or compatibility shims for compile.nvim/Overseer/Snacks.

## Validation

```sh
./tests/run.sh
stylua --check lua plugin tests
# Optional: exercise your existing config without editing it
TASK_TOOLS_CONFIGURED=1 python3 tests/tui.py
```

Tests use real processes, a C compiler, and a real Neovim TUI/nested PTY with
physical key input and rendered-cell assertions. Requires Python 3, `cc`, `sh`,
`sleep`, `head`, `tr`, `stty`, and `printf`. `:checkhealth task_tools` checks the
runtime shell. Use `:TaskInfo` for project definitions and current task state.

Python task definitions accept `python_env = function(context) return { VIRTUAL_ENV = ..., PATH = ... } end`
(or a table) alongside the `python` interpreter provider. This changes only the task child process.

## Optional task progress notifications

After configuring task-tools, enable the adapter with
`require('task_tools.integrations.notification_tools').setup()`.
It uses an already-loaded notification-tools.nvim provider, with one progress
handle per task. Result summaries are bounded, failures include the exit code and
last output line, and the default history policy retains errors. It does not
load notification-tools or create a second job/cancellation mechanism.

Pass `filter = function(task) return ... end`, `history = true/false/'errors'`,
or `provider = function() return notification_api end` to customize it.
`open_last_output()` opens the last completed accepted task's original output;
`dispose()` unsubscribes and closes progress without stopping tasks. Repeated
setup replaces the subscription; task-tools disposal also detaches the adapter.
