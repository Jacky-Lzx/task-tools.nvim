if vim.g.loaded_task_tools then
  return
end
vim.g.loaded_task_tools = true
if vim.fn.has('nvim-0.11') == 0 then
  vim.notify('task-tools.nvim requires Neovim 0.11+', vim.log.levels.ERROR)
  return
end

local function api()
  return require('task_tools')
end
local function id(args)
  if args.args == '' then
    return nil
  end
  local number = tonumber(args.args)
  if not number or number < 1 or number % 1 ~= 0 then
    error('task-tools: expected a positive task ID')
  end
  return number
end
local function ids()
  return vim.tbl_map(function(task)
    return tostring(task.id)
  end, api().list())
end
local function create(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts or {})
end
create('TaskRun', function(args)
  api().select(args.args, { open = true, focus = args.bang })
end, {
  nargs = '*',
  bang = true,
  complete = function(prefix, line)
    prefix = line:match('^%s*TaskRun!?%s+(.*)$') or prefix
    local definitions = api().discover()
    local names = {}
    for _, spec in ipairs(definitions) do
      if vim.startswith(spec.name, prefix) then
        names[#names + 1] = spec.name
      end
    end
    return names
  end,
})
create('TaskShell', function(args)
  local opts = { mode = args.bang and 'terminal' or 'pipe', focus = args.bang }
  if args.args == '' then
    api().prompt(opts)
  else
    api().shell(args.args, opts)
  end
end, { nargs = '*', bang = true, complete = 'shellcmd' })
for name, method in pairs({
  TaskStop = 'stop',
  TaskRerun = 'rerun',
  TaskOutput = 'show',
  TaskQuickfix = 'quickfix',
  TaskDelete = 'remove',
  TaskWatch = 'toggle_watch',
}) do
  create(name, function(args)
    api()[method](id(args))
  end, { nargs = '?', complete = ids })
end
create('TaskOpen', function()
  api().open()
end)
create('TaskClose', function()
  api().close()
end)
create('TaskToggle', function()
  api().toggle()
end)
create('TaskTerminal', function()
  api().terminal()
end)
create('TaskSave', function(args)
  api().save(vim.fn.expand(args.args))
end, { nargs = 1, complete = 'file' })
create('TaskLoad', function(args)
  api().load(vim.fn.expand(args.args))
end, { nargs = 1, complete = 'file' })
