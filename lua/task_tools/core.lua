local M = {}
local config = require('task_tools.config')
local stream = require('task_tools.stream')
local tasks, order, next_id = {}, {}, 0
local listeners = {}
local fields =
  { 'id', 'name', 'cmd', 'cwd', 'mode', 'status', 'exit_code', 'started_at', 'finished_at', 'buf', 'job', 'watch_id' }

function M.get(id)
  local task = tasks[id or order[#order]]
  if not task then
    return nil
  end
  local result = {}
  for _, key in ipairs(fields) do
    result[key] = vim.deepcopy(task[key])
  end
  result.dropped = task.output.dropped
  return result
end

function M.list()
  local result = {}
  for i = #order, 1, -1 do
    result[#result + 1] = M.get(order[i])
  end
  return result
end

function M.active(task)
  return task and (task.status == 'running' or task.status == 'stopping')
end

local function emit(task, kind)
  local snapshot = M.get(task.id) or { id = task.id, status = task.status }
  for _, callback in ipairs(vim.list_slice(listeners)) do
    local ok, err = pcall(callback, snapshot, kind)
    if not ok then
      vim.schedule(function()
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end)
    end
  end
  pcall(
    vim.api.nvim_exec_autocmds,
    'User',
    { pattern = 'TaskToolsChanged', modeline = false, data = { task = snapshot, kind = kind } }
  )
end

function M.subscribe(callback)
  assert(type(callback) == 'function', 'subscriber must be a function')
  listeners[#listeners + 1] = callback
  return function()
    for i, item in ipairs(listeners) do
      if item == callback then
        table.remove(listeners, i)
        break
      end
    end
  end
end

function M.output(id)
  local t = tasks[id or order[#order]]
  return t and stream.lines(t.output, true) or {}
end

function M.spec(id)
  local t = tasks[id or order[#order]]
  return t and vim.deepcopy(t.spec) or nil
end

local function changed(task)
  if task.scheduled then
    return
  end
  task.scheduled = true
  vim.defer_fn(function()
    task.scheduled = false
    if tasks[task.id] == task then
      emit(task, 'output')
    end
  end, config.values.output.flush_ms)
end

function M.normalize(spec)
  if type(spec) == 'string' then
    spec = { cmd = spec }
  end
  assert(type(spec) == 'table', 'task must be a command string or definition')
  spec = vim.deepcopy(spec)
  local cmd = spec.cmd
  assert(
    type(cmd) == 'string' or (type(cmd) == 'table' and vim.islist(cmd) and #cmd > 0),
    'cmd must be a string or nonempty argv list'
  )
  if type(cmd) == 'table' then
    for _, value in ipairs(cmd) do
      assert(type(value) == 'string' and not value:find('\0', 1, true), 'argv must contain strings without NUL')
    end
    assert(cmd[1] ~= '', 'executable must not be empty')
  else
    assert(vim.trim(cmd) ~= '' and not cmd:find('\0', 1, true), 'cmd must not be empty or contain NUL')
  end
  spec.cwd = vim.fs.normalize(vim.fn.fnamemodify(spec.cwd or vim.fn.getcwd(), ':p'))
  assert(vim.fn.isdirectory(spec.cwd) == 1, 'task directory does not exist: ' .. spec.cwd)
  spec.mode = spec.mode or 'pipe'
  assert(spec.mode == 'pipe' or spec.mode == 'terminal', 'mode must be pipe or terminal')
  spec.name = spec.name or (type(cmd) == 'string' and cmd or table.concat(cmd, ' '))
  assert(type(spec.name) == 'string' and spec.name ~= '', 'name must be nonempty')
  assert(spec.env == nil or type(spec.env) == 'table', 'env must be a table')
  spec.env = vim.tbl_extend('force', config.values.env, spec.env or {})
  for key, value in pairs(spec.env) do
    assert(
      type(key) == 'string' and type(value) == 'string' and not key:find('[=%z]') and not value:find('%z'),
      'env must contain string names and values'
    )
  end
  assert(spec.stdin == nil or type(spec.stdin) == 'string', 'stdin must be a string')
  if spec.watch ~= nil and spec.watch ~= false and spec.watch ~= true then
    assert(
      type(spec.watch) == 'table' and vim.islist(spec.watch) and #spec.watch > 0,
      'watch must be true or a nonempty glob list'
    )
    for _, pattern in ipairs(spec.watch) do
      assert(type(pattern) == 'string', 'watch globs must be strings')
    end
  end
  if spec.errorformat then
    require('task_tools.parser').parse({ '' }, spec.cwd, spec.errorformat)
  end
  return spec
end

function M.remove(id)
  local task = tasks[id]
  if not task then
    return false, 'unknown task'
  end
  if M.active(task) then
    return false, 'stop the task before removing it'
  end
  if task.buf and vim.api.nvim_buf_is_valid(task.buf) then
    vim.api.nvim_buf_delete(task.buf, { force = true })
  end
  tasks[id] = nil
  for i, value in ipairs(order) do
    if value == id then
      table.remove(order, i)
      break
    end
  end
  emit(task, 'removed')
  return true
end

local function prune()
  while #order >= config.values.history do
    local found
    for _, id in ipairs(order) do
      if not M.active(tasks[id]) and not tasks[id].watch_id then
        found = id
        break
      end
    end
    if not found then
      break
    end
    M.remove(found)
  end
end

function M.run(spec)
  local ok, normalized = pcall(M.normalize, spec)
  if not ok then
    return nil, tostring(normalized)
  end
  spec = normalized
  prune()
  next_id = next_id + 1
  local task = {
    id = next_id,
    spec = spec,
    name = spec.name,
    cmd = spec.cmd,
    cwd = spec.cwd,
    mode = spec.mode,
    status = 'running',
    started_at = os.time(),
    output = stream.new(config.values.output),
  }
  tasks[task.id], order[#order + 1] = task, task.id
  local opts = {
    cwd = task.cwd,
    env = next(spec.env) and spec.env or nil,
    on_stdout = function(_, data)
      stream.receive(task.output, 'stdout', data)
      changed(task)
    end,
    on_stderr = function(_, data)
      stream.receive(task.output, 'stderr', data)
      changed(task)
    end,
    on_exit = function(_, code)
      stream.finish(task.output)
      task.exit_code, task.finished_at = code, os.time()
      task.status = task.stop_requested and 'stopped' or (code == 0 and 'success' or 'failure')
      emit(task, 'exit')
    end,
  }
  local launch = function()
    return vim.fn.jobstart(task.cmd, opts)
  end
  if task.mode == 'terminal' then
    task.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[task.buf].bufhidden = 'hide'
    vim.bo[task.buf].swapfile = false
    opts.term = true
    vim.bo[task.buf].scrollback = math.min(config.values.output.max_lines, 100000)
    launch = function()
      return vim.api.nvim_buf_call(task.buf, function()
        return vim.fn.jobstart(task.cmd, opts)
      end)
    end
  end
  local started, job = pcall(launch)
  if not started or job <= 0 then
    task.status, task.finished_at = 'failure', os.time()
    task.exit_code = -1
    for _, line in ipairs(vim.split('Cannot start command: ' .. tostring(job), '\n', { plain = true })) do
      stream.push(task.output, line)
    end
    if task.buf and vim.api.nvim_buf_is_valid(task.buf) then
      vim.bo[task.buf].buftype = 'nofile'
      vim.bo[task.buf].filetype = 'tasktoolsoutput'
    end
    emit(task, 'exit')
    return task.id, 'cannot start command: ' .. tostring(job)
  end
  task.job = job
  if task.mode == 'pipe' then
    if spec.stdin then
      local sent, input_error = pcall(vim.fn.chansend, job, spec.stdin)
      if not sent then
        stream.push(task.output, 'Cannot send stdin: ' .. tostring(input_error):gsub('\n', ' '))
      end
    end
    pcall(vim.fn.chanclose, job, 'stdin')
  end
  if task.buf then
    local group = vim.api.nvim_create_augroup('TaskToolsBuffer' .. task.id, { clear = true })
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = group,
      buffer = task.buf,
      once = true,
      callback = function()
        emit(task, 'wipe')
        if M.active(task) then
          M.stop(task.id)
        end
        vim.schedule(function()
          pcall(vim.api.nvim_del_augroup_by_id, group)
        end)
      end,
    })
  end
  emit(task, 'start')
  return task.id
end

function M.stop(id)
  local task = tasks[id or order[#order]]
  if not M.active(task) or not task.job then
    return false, 'task is not running'
  end
  if task.status == 'stopping' then
    return true
  end
  task.status = 'stopping'
  task.stop_requested = true
  local ok, result = pcall(vim.fn.jobstop, task.job)
  if not ok or result ~= 1 then
    task.status = 'running'
    return false, 'could not stop task'
  end
  emit(task, 'stop')
  return true
end

function M.send(id, data)
  local task = tasks[id]
  if not M.active(task) or task.mode ~= 'terminal' then
    return false, 'task is not an active terminal'
  end
  local ok, err = pcall(vim.fn.chansend, task.job, data)
  return ok, not ok and tostring(err) or nil
end

function M.set_buffer(id, buf)
  if tasks[id] then
    tasks[id].buf = buf
  end
end
function M.set_watch(id, watch_id)
  if tasks[id] then
    tasks[id].watch_id = watch_id
    emit(tasks[id], 'watch')
  end
end

local group = vim.api.nvim_create_augroup('TaskToolsJobs', { clear = true })
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    for _, task in pairs(tasks) do
      if M.active(task) then
        pcall(vim.fn.jobstop, task.job)
      end
    end
  end,
})

return M
