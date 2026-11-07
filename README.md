# task-tools.nvim

Builds, commands, watch tasks and interactive terminals share one execution engine.
Requires **Neovim 0.11+**. No plugin dependencies; `setup()` is optional.

- Run concurrent jobs with independent IDs, working directories, environment and output.
- Stream bounded output without taking over quickfix or source focus.
- Jump from compiler output with Enter, or export a quickfix snapshot.
- Keep interactive PTYs alive while hidden, including terminal resize and scrollback.
- Discover project tasks and current-file runners; extend discovery with Lua providers.
- Restart tasks on editor saves, with debounce and no overlapping runs per watcher.
- Explicitly save/load task definitions; loading never starts a process or watcher.

## Installation

For lazy.nvim (the `main` field is necessary because the Lua module uses an underscore):

```lua
{
  dir = '/path/to/task-tools.nvim',
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

## Lua API

```lua
local tasks = require('task_tools')
tasks.setup({
  open = true,         -- Show output at launch
  focus = false,       -- Keep source focus by default
  height = 12,
  history = 100,       -- Prune completed runs when starting new ones
  output = { max_lines = 10000, max_line_bytes = 16384, flush_ms = 40 },
  watch_debounce = 150,
  env = {},            -- Added to the inherited process environment
  shell = nil,         -- nil: { vim.o.shell }; otherwise an argv list/string
  terminal = {
    position = 'float', -- 'float', 'bottom', 'top', 'left', 'right'
    width = 0.9, height = 0.9, -- <= 1: fraction; > 1: cells
    border = 'rounded', zindex = 50, winblend = 0,
  },
  python = 'python3',   -- Or function(context) returning the selected interpreter
  providers = true,    -- Built-in providers
  tasks = {},          -- Definitions, or function(context) returning definitions
})

local id, err = tasks.run({
  name = 'Tests',
  cmd = { 'cargo', 'test' }, -- argv avoids shell interpolation
  cwd = '/path/to/project',
  env = { RUST_BACKTRACE = '1' },
  mode = 'pipe',           -- 'pipe' or 'terminal'
  -- errorformat = '%f:%l:%c: %m',
  -- stdin = 'input',      -- Pipe input, closed after sending
  -- watch = { '*.rs' },
}, { open = true, focus = false })

tasks.shell('make -j4 && ./demo', { cwd = '/path/to/project' })
tasks.rerun(id, { open = false })
tasks.stop(id)
tasks.show(id, { focus = true })
tasks.quickfix(id, { open = true, focus = false })
tasks.open(); tasks.close(); tasks.toggle()
tasks.toggle_watch(id); tasks.remove(id)
tasks.terminal({ cwd = '/path/to/project', key = 'server', cmd = { 'sh' } })
tasks.send(id, 'input\n') -- Active terminal only
local task = tasks.get(id) -- Snapshot, nil for unknown ID; omitted ID means latest
local newest_first = tasks.list()
local lines = tasks.output(id)
local counts = tasks.status() -- running/stopping/success/failure/stopped/watch
local unsubscribe = tasks.subscribe(function(snapshot, kind) end)
unsubscribe()
```

`run()` returns `id, err`. Invalid definitions return `nil, err` without starting
a process. A launch failure still has an ID and a failure record (`exit_code = -1`).
Mutating snapshots never changes the running job. `stop`/`send`/`remove` return
`boolean, err`; errors are also reported through `vim.notify`.

`terminal()` toggles one shell per directory by default. An explicit `key` creates
an independent slot. Command/environment options are used when creating the slot;
while alive, toggling reuses the original process. A finished slot starts a new run.

Terminals (including `TaskShell!` and terminal-mode tasks) open in a centered
floating window by default. Floats resize with the editor, clamp to fit small
screens and preserve the source split layout. `terminal.width` / `height` accept
fractions up to 1 or integer cell counts above 1. Border choices are `none`,
`single`, `double`, `rounded`, `solid`, `shadow`; `zindex` and `winblend` (0–100)
apply to floats. `height` controls top/bottom splits; `width` controls left/right.
The top-level `height` option still controls pipe output, task lists and quickfix.
Override the layout for an opening without changing the process:

```lua
tasks.terminal({ window = { position = 'right', width = 60 } })
tasks.show(id, { window = { position = 'float', width = 0.8, height = 0.7 } })
```

`run(..., { window = {...} })` also accepts these terminal layout overrides.
Options apply when creating a window; hide and reopen to change an existing view.

Add your own task discovery (e.g. interpreter selection or specialized builds):

```lua
tasks.register_provider('project-test', function(ctx)
  -- ctx = { buf, file, filetype, cwd }
  return { { name = 'unit tests', cmd = { 'make', 'test' }, cwd = ctx.cwd } }
end)
local definitions, errors, context = tasks.discover()
```

Status bars can read `tasks.status()`. Subscribers and the `User TaskToolsChanged`
autocommand receive kinds `start`, `output` (throttled), `stop`, `exit`, `watch`,
`wipe`, `removed`. Autocommand `event.data` contains `{ task, kind }`.
Callbacks should observe state rather than start nested jobs during launch.

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

## Command ownership

Commands belong to the plugin; choose global entry keys and short aliases in
your configuration. Registration reports same-name conflicts without replacing
user commands. Reconfiguration refreshes only commands still owned by this
plugin, and cleanup preserves subsequent user replacements.

## Setup contract

`setup(nil)` uses defaults. Configuration must be a table; caller-owned tables
are copied before use. Invalid configuration types do not replace live handlers
or commands. Repeating setup must not accumulate automatic registrations.

Setup resolves fresh options without stopping running tasks. `dispose()` stops
owned jobs/watch reruns, invalidates late output, releases automatic UI/watch/job
observers and floating terminal windows, and resets setup options. Existing
output buffers, completed history and caller subscriptions remain available.
Disposal is repeatable; later explicit setup/run/watch/open rebuilds its needed
observers. Buffer content is never force-deleted by disposal.

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

## Health and inspection

Health reports actionable failures and a compact result for applicable checks. Disabled,
optional and not-yet-activated features do not warn solely because they are inactive.
Inspection does not configure plugins, start services or install dependencies.
Use `:TaskInfo` for detailed configuration and runtime information.
