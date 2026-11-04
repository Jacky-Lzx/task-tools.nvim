local M = {}
local config = require('task_tools.config')
local registered = {}
local markers = {
  '.task-tools.json',
  'Cargo.toml',
  'package.json',
  'Makefile',
  'makefile',
  'CMakeLists.txt',
  'pyproject.toml',
  '.git',
}

function M.context(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' then
    file = ''
  end
  local dir = file ~= '' and vim.fs.dirname(file) or vim.fn.getcwd()
  local root = opts.cwd or vim.fs.root(dir, markers) or dir
  return {
    buf = buf,
    file = file,
    filetype = vim.bo[buf].filetype,
    cwd = vim.fs.normalize(vim.fn.fnamemodify(root, ':p')),
  }
end

function M.read_json(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  assert(stat.type == 'file' and stat.size <= 1024 * 1024, 'JSON file must be at most 1 MiB: ' .. path)
  local lines = vim.fn.readfile(path)
  return vim.json.decode(table.concat(lines, '\n'))
end

function M.register(name, provider)
  assert(type(name) == 'string' and type(provider) == 'function', 'provider needs a name and callback')
  registered[name] = provider
end

local function builtins(ctx)
  local result = {}
  local function add(name, cmd, extra)
    result[#result + 1] = vim.tbl_extend('force', { name = name, cmd = cmd, cwd = ctx.cwd }, extra or {})
  end
  local function exists(path)
    return vim.uv.fs_stat(ctx.cwd .. '/' .. path) ~= nil
  end
  if exists('Cargo.toml') then
    for _, action in ipairs({ 'build', 'run', 'test', 'check' }) do
      add('cargo ' .. action, { 'cargo', action }, { mode = action == 'run' and 'terminal' or 'pipe' })
    end
  end
  if exists('Makefile') or exists('makefile') then
    add('make', { 'make' })
    local path = ctx.cwd .. '/' .. (exists('Makefile') and 'Makefile' or 'makefile')
    local seen = {}
    for _, line in ipairs(vim.fn.readfile(path, '', 10000)) do
      local target = line:match('^([%w_][%w_.%-]*)%s*:')
      if target and not seen[target] then
        seen[target] = true
        add('make ' .. target, { 'make', target })
      end
    end
  end
  if exists('CMakeLists.txt') then
    add('cmake configure', { 'cmake', '-S', '.', '-B', 'build' })
    add('cmake build', { 'cmake', '--build', 'build' })
    add('ctest', { 'ctest', '--test-dir', 'build', '--output-on-failure' })
  end
  if exists('package.json') then
    local package = M.read_json(ctx.cwd .. '/package.json')
    assert(type(package) == 'table', 'package.json must be an object')
    local manager = exists('pnpm-lock.yaml') and 'pnpm'
      or (exists('yarn.lock') and 'yarn' or (exists('bun.lock') or exists('bun.lockb')) and 'bun' or 'npm')
    for _, name in ipairs(vim.tbl_keys(type(package.scripts) == 'table' and package.scripts or {})) do
      add(manager .. ' run ' .. name, { manager, 'run', name }, { mode = 'terminal' })
    end
  end
  if ctx.file == '' then
    return result
  end
  local cwd = vim.fs.dirname(ctx.file)
  if ctx.filetype == 'python' then
    local python = type(config.values.python) == 'function' and config.values.python(ctx) or config.values.python
    add('Python: run file', { python, ctx.file }, { cwd = cwd, mode = 'terminal' })
  elseif ctx.filetype == 'c' or ctx.filetype == 'cpp' then
    local executable = ctx.file:gsub('%.[^/.]+$', '')
    if executable == ctx.file then
      executable = ctx.file .. '.out'
    end
    add(
      'C/C++: build file',
      { ctx.filetype == 'cpp' and 'c++' or 'cc', '-Wall', '-g', ctx.file, '-o', executable },
      { cwd = cwd }
    )
    add('C/C++: run executable', { executable }, { cwd = cwd, mode = 'terminal' })
  elseif ctx.filetype == 'sh' then
    add('Shell: run file', { 'sh', ctx.file }, { cwd = cwd, mode = 'terminal' })
  elseif ctx.filetype == 'tex' then
    add('LaTeX: latexmk', { 'latexmk', ctx.file }, { cwd = cwd })
    add(
      'LaTeX: tectonic',
      { 'tectonic', '-X', 'compile', ctx.file, '--synctex', '--keep-logs', '--keep-intermediates' },
      { cwd = cwd }
    )
  elseif ctx.filetype == 'typst' then
    add('Typst: compile', { 'typst', 'compile', ctx.file }, { cwd = cwd })
    add('Typst: watch', { 'typst', 'watch', ctx.file }, { cwd = cwd })
  elseif ctx.filetype == 'markdown' then
    add(
      'Markdown: PDF',
      { 'pandoc', ctx.file, '-o', ctx.file:gsub('%.[^/.]+$', '') .. '.pdf', '--pdf-engine=xelatex' },
      { cwd = cwd }
    )
    add('Markdown: preview', { 'gh', 'markdown-preview', '--port', '3333', ctx.file }, { cwd = cwd })
  elseif (ctx.filetype == 'verilog' or ctx.filetype == 'systemverilog') and exists('compile.sh') then
    add('Verilog: compile.sh', { 'sh', 'compile.sh' })
  end
  return result
end

local function project(ctx)
  local data = M.read_json(ctx.cwd .. '/.task-tools.json')
  if not data then
    return {}
  end
  assert(
    type(data) == 'table' and data.version == 1 and type(data.tasks) == 'table' and vim.islist(data.tasks),
    '.task-tools.json requires version = 1 and a tasks list'
  )
  return data.tasks
end

function M.discover(opts)
  local ctx = M.context(opts)
  local result, errors, names = {}, {}, {}
  local function collect(source, fn)
    local ok, definitions = pcall(fn, ctx)
    if not ok then
      errors[#errors + 1] = source .. ': ' .. tostring(definitions)
      return
    end
    if type(definitions) ~= 'table' or not vim.islist(definitions) then
      errors[#errors + 1] = source .. ': expected a list'
      return
    end
    for _, spec in ipairs(definitions) do
      local valid, normalized = pcall(function()
        assert(type(spec) == 'table', 'expected task definition')
        spec = vim.deepcopy(spec)
        if spec.cwd and not vim.startswith(spec.cwd, '/') and not spec.cwd:match('^%a:[/\\]') then
          spec.cwd = ctx.cwd .. '/' .. spec.cwd
        end
        spec.cwd = spec.cwd or ctx.cwd
        return require('task_tools.core').normalize(spec)
      end)
      if valid then
        if not names[normalized.name] then
          names[normalized.name] = true
          result[#result + 1] = normalized
        end
      else
        errors[#errors + 1] = source .. ': ' .. tostring(normalized)
      end
    end
  end
  -- Explicit configuration wins over project and generated names.
  collect('config', function()
    return type(config.values.tasks) == 'function' and config.values.tasks(ctx) or config.values.tasks
  end)
  collect('project', project)
  for _, name in ipairs(vim.fn.sort(vim.tbl_keys(registered))) do
    collect(name, registered[name])
  end
  if config.values.providers then
    collect('builtin', builtins)
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result, errors, ctx
end

return M
