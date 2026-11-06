-- Optional presentation adapter. task-tools retains process and output ownership.
local M = {}
local unsubscribe, handles, last_completed
local generation = 0

function M.dispose()
  generation = generation + 1
  if unsubscribe then
    unsubscribe()
    unsubscribe = nil
  end
  for _, handle in pairs(handles or {}) do
    if handle:is_active() then
      handle:cancel('Progress detached')
    end
  end
  handles, last_completed = {}, nil
end

function M.setup(opts)
  opts = opts == nil and {} or opts
  assert(type(opts) == 'table', 'task notification options must be a table')
  assert(opts.provider == nil or type(opts.provider) == 'function', 'provider must be a function')
  assert(opts.filter == nil or type(opts.filter) == 'function', 'filter must be a function')
  assert(
    opts.history == nil or opts.history == false or opts.history == true or opts.history == 'errors',
    'invalid history policy'
  )
  local previous = last_completed
  M.dispose()
  last_completed = previous
  local current = generation
  local tasks = require('task_tools')
  local provider = opts.provider or function()
    return package.loaded['notification-tools']
  end
  local function summary(task)
    local lines = tasks.output(task.id)
    for index = #lines, 1, -1 do
      if vim.trim(lines[index]) ~= '' then
        return vim.fn.strcharpart(lines[index], 0, 180)
      end
    end
    return ''
  end
  local function changed(task, kind)
    if current ~= generation or (kind ~= 'start' and kind ~= 'stop' and kind ~= 'exit') then
      return
    end
    local running = task.status == 'running' or task.status == 'stopping'
    if not running and kind ~= 'exit' then
      return
    end
    if opts.filter and not opts.filter(task) then
      return
    end
    if not running then
      last_completed = task.id
    end
    local tools = provider()
    if not tools then
      return
    end
    local handle = handles[task.id]
    if not handle then
      handle = tools.progress({
        id = 'task-tools:' .. task.id,
        source = 'task-tools',
        title = task.name,
        history = opts.history == nil and 'errors' or opts.history,
      })
      handles[task.id] = handle
    end
    if not handle:is_active() then
      if not running then
        handles[task.id] = nil
      end
      return
    end
    local message = running and '' or summary(task)
    if running then
      handle:update({ message = task.status == 'stopping' and 'Stopping…' or message })
    elseif task.status == 'failure' then
      handle:finish('Exit ' .. tostring(task.exit_code) .. (message ~= '' and ': ' .. message or ''), 'error')
    elseif task.status == 'stopped' then
      handle:cancel(message ~= '' and message or 'Stopped')
    else
      handle:finish(message ~= '' and message or nil)
    end
    if not running then
      handles[task.id] = nil
    end
  end
  unsubscribe = tasks.subscribe(changed)
  for _, task in ipairs(tasks.list()) do
    if task.status == 'running' or task.status == 'stopping' then
      changed(task, 'start')
    end
  end
end

function M.open_last_output()
  if not last_completed or not require('task_tools').get(last_completed) then
    return nil, 'No completed task output available'
  end
  return require('task_tools').show(last_completed, { focus = true })
end
return M
