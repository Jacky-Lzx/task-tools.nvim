# task-tools.nvim

Builds, watch tasks and interactive terminals in one execution engine.

## Features

- Run concurrent jobs with bounded output and separate environments.
- Keep interactive terminals alive while their windows are hidden.
- Discover project tasks and explicitly save or restore task definitions.

## Requirements

Neovim **0.11+**. No plugin dependencies. Tasks use the executables and shell supplied by your environment.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/task-tools.nvim",
  main = "task_tools",
  opts = {},
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("task_tools").setup({})
```

## Usage

```vim
:TaskRun
:TaskOpen
:TaskInfo
```

## Documentation

- [Complete reference](doc/task-tools.txt) — `:help task-tools`.
- [Workflow and integration guide](doc/guide.md).
- Diagnose availability with `:checkhealth task_tools`.

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.

[License](LICENSE).
