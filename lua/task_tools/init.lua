local M = {}
local core = require('task_tools.core')
local config = require('task_tools.config')
local terminals = {}

local function report(value, err)
  if err then
    vim.notify('task-tools: ' .. tostring(err), vim.log.levels.WARN)
  end
  return value, err
end

function M.setup(opts)
  assert(opts == nil or type(opts) == 'table', 'task-tools.nvim: setup expects a table')
  opts = vim.deepcopy(opts or {})
  config.setup(opts)
  core.setup()
  for _, name in ipairs({ 'watch', 'ui', 'terminal_window' }) do
    local module = package.loaded['task_tools.' .. name]
    if module then
      module.setup()
    end
  end
end
-- Stop owned work without deleting output buffers or completed history.
function M.dispose()
  for _, name in ipairs({ 'watch', 'ui', 'terminal_window' }) do
    local module = package.loaded['task_tools.' .. name]
    if module then
      module.dispose()
    end
  end
  core.dispose()
  terminals = {}
  config.setup()
end

function M.get(id)
  return core.get(id)
end
function M.list()
  return core.list()
end
function M.output(id)
  return core.output(id)
end
function M.subscribe(callback)
  return core.subscribe(callback)
end

function M.run(spec, opts)
  opts = opts or {}
  if type(spec) == 'table' and spec.mode == 'terminal' and opts.window then
    local valid, err = pcall(config.terminal, opts.window)
    if not valid then
      return report(nil, err)
    end
  end
  local watching = type(spec) == 'table' and spec.watch
  local id, err
  if watching then
    id, err = require('task_tools.watch').start(spec)
  else
    id, err = core.run(spec)
  end
  if id and (opts.open == true or (opts.open == nil and config.values.open)) then
    local focus = opts.focus
    if focus == nil then
      focus = config.values.focus
    end
    require('task_tools.ui').output(id, { focus = focus, window = opts.window })
  end
  return report(id, err)
end

function M.shell(command, opts)
  opts = opts or {}
  return M.run({ name = command, cmd = command, cwd = opts.cwd, env = opts.env, mode = opts.mode or 'pipe' }, opts)
end

function M.prompt(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local last = core.spec()
  vim.ui.input({
    prompt = 'Task command: ',
    default = last and type(last.cmd) == 'string' and last.cmd or '',
    completion = 'shellcmd',
  }, function(input)
    if input and vim.trim(input) ~= '' then
      M.shell(input, vim.tbl_extend('force', opts, { cwd = cwd }))
    end
  end)
end

function M.discover(opts)
  return require('task_tools.providers').discover(opts)
end
function M.register_provider(name, provider)
  require('task_tools.providers').register(name, provider)
end

function M.select(name, opts)
  local definitions, errors = M.discover(opts)
  for _, err in ipairs(errors) do
    vim.notify(err, vim.log.levels.WARN)
  end
  if name and name ~= '' then
    for _, spec in ipairs(definitions) do
      if spec.name == name then
        return M.run(spec, opts)
      end
    end
    return report(nil, 'unknown task: ' .. name)
  end
  if #definitions == 0 then
    return M.prompt(opts)
  end
  vim.ui.select(definitions, {
    prompt = 'Run task',
    format_item = function(spec)
      return spec.name
    end,
  }, function(spec)
    if spec then
      M.run(spec, opts)
    end
  end)
end

function M.stop(id)
  local task = core.get(id)
  if task and task.watch_id then
    require('task_tools.watch').disable(task.watch_id)
  end
  return report(core.stop(task and task.id or id))
end

function M.rerun(id, opts)
  local task = core.get(id)
  if not task then
    return report(nil, 'no task selected')
  end
  if core.active(task) then
    return report(nil, 'task is running; stop it before rerunning')
  end
  local spec = core.spec(task.id)
  if task.watch_id then
    for _, entry in ipairs(require('task_tools.watch').definitions()) do
      if entry.task == task.id then
        spec = entry.spec
      end
    end
    require('task_tools.watch').disable(task.watch_id)
  end
  return M.run(spec, opts)
end

function M.remove(id)
  local task = core.get(id)
  if not task then
    return report(false, 'no task selected')
  end
  if core.active(task) then
    return report(false, 'stop the task before removing it')
  end
  if task.watch_id then
    require('task_tools.watch').disable(task.watch_id)
  end
  return report(core.remove(task.id))
end

function M.toggle_watch(id)
  local task = core.get(id)
  if not task then
    return report(nil, 'no task selected')
  end
  if task.watch_id then
    return require('task_tools.watch').disable(task.watch_id)
  end
  if core.active(task) then
    return report(nil, 'stop the task before enabling watch')
  end
  local spec = core.spec(task.id)
  spec.watch = true
  return M.run(spec, { open = false })
end

function M.open(opts)
  return require('task_tools.ui').open(opts)
end
function M.close()
  return require('task_tools.ui').close()
end
function M.toggle(opts)
  return require('task_tools.ui').toggle(opts)
end
function M.show(id, opts)
  return report(require('task_tools.ui').output(id, opts))
end
function M.quickfix(id, opts)
  return report(require('task_tools.ui').quickfix(id, opts))
end
function M.send(id, data)
  return report(core.send(id, data))
end

function M.terminal(opts)
  opts = opts or {}
  local cwd = vim.fs.normalize(vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ':p'))
  local key = opts.key or cwd
  local task = core.get(terminals[key])
  if not terminals[key] then
    task = nil
  end
  if task and core.active(task) and task.buf and vim.api.nvim_buf_is_valid(task.buf) then
    local wins = vim.fn.win_findbuf(task.buf)
    if #wins > 0 then
      for _, win in ipairs(wins) do
        if #vim.api.nvim_list_wins() > 1 then
          vim.api.nvim_win_close(win, false)
        else
          vim.api.nvim_win_call(win, function()
            vim.cmd('enew')
          end)
        end
      end
      return task.id
    end
    M.show(task.id, { focus = true, window = opts.window })
    return task.id
  end
  local command = opts.cmd or config.values.shell or { vim.o.shell }
  local id = M.run(
    { name = opts.name or 'Terminal', cmd = command, cwd = cwd, env = opts.env, mode = 'terminal' },
    { open = true, focus = true, window = opts.window }
  )
  if id then
    terminals[key] = id
  end
  return id
end

function M.status()
  local counts = { running = 0, stopping = 0, success = 0, failure = 0, stopped = 0, watch = 0 }
  for _, task in ipairs(core.list()) do
    counts[task.status] = counts[task.status] + 1
    if task.watch_id then
      counts.watch = counts.watch + 1
    end
  end
  return counts
end

function M.save(path)
  local ok, result = pcall(require('task_tools.session').save, path)
  return report(ok and result or nil, not ok and result or nil)
end

function M.load(path)
  local ok, result = pcall(require('task_tools.session').load, path)
  return report(ok and result or nil, not ok and result or nil)
end

return M
