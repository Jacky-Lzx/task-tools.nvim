vim.opt.rtp:prepend(vim.fn.getcwd())
local tasks = require('task_tools')
local adapter = require('task_tools.integrations.notification_tools')
local core = require('task_tools.core')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function wait(test, message)
  assert(vim.wait(5000, test, 5), message or 'task transition timed out')
end
local function done(id)
  wait(function()
    return not core.active(tasks.get(id))
  end)
end
local function gated(name)
  local gate = root .. '/' .. name
  local id = assert(tasks.run({
    name = name,
    cmd = {
      'python3',
      '-u',
      '-c',
      'import pathlib,sys,time; print("ready",flush=True); gate=pathlib.Path(sys.argv[1]); deadline=time.monotonic()+10\nwhile not gate.exists() and time.monotonic()<deadline: time.sleep(.01)\nprint("finished",flush=True)',
      gate,
    },
  }, { open = false }))
  wait(function()
    return table.concat(tasks.output(id), '\n'):find('ready', 1, true) ~= nil
  end)
  return id, gate
end
local skipped = false
local ok, err = xpcall(function()
  tasks.setup({ open = false })
  adapter.setup()
  local cold = assert(tasks.run({ cmd = { 'sh', '-c', 'exit 0' } }, { open = false }))
  done(cold)
  assert(not package.loaded['notification-tools'], 'Optional provider was loaded implicitly')
  adapter.dispose()
  local notification_root = vim.env.TASK_TOOLS_NOTIFICATION_ROOT or vim.fn.getcwd() .. '/../notification-tools.nvim'
  if vim.fn.filereadable(notification_root .. '/lua/notification-tools/init.lua') == 0 then
    skipped = true
    return
  end
  vim.opt.rtp:append(notification_root)
  local notices = require('notification-tools')
  notices.setup({ notify = false, lsp = { enabled = false }, progress = { done_ttl = 10000, error_ttl = 10000 } })
  local function row(id)
    for _, item in ipairs(notices.tasks()) do
      if item.id == 'task-tools:' .. id then
        return item
      end
    end
  end
  adapter.setup()
  local slow, gate = gated('parallel task')
  assert(row(slow) and not row(slow).done)
  assert(not pcall(adapter.setup, false), 'Invalid setup must preserve the live adapter')
  adapter.setup()
  assert(core.active(tasks.get(slow)) and not row(slow).done)
  local failure = assert(
    tasks.run({ name = 'failed check', cmd = { 'sh', '-c', 'printf "failure detail\n"; exit 7' } }, { open = false })
  )
  done(failure)
  assert(row(failure).status == 'error' and row(failure).message:find('Exit 7: failure detail', 1, true))
  local errors = notices.history({ source = 'task-tools' })
  assert(#errors == 1 and errors[1].message:find('failure detail', 1, true))
  assert(core.active(tasks.get(slow)), 'A sibling failure cancelled a task')
  assert(adapter.open_last_output())
  assert(
    vim.bo.filetype == 'tasktoolsoutput'
      and table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('failure detail', 1, true)
  )
  vim.fn.writefile({}, gate)
  done(slow)
  assert(row(slow).status == 'success')
  assert(#notices.history({ source = 'task-tools' }) == 1, 'Success duplicated error-only history')
  local stopped = gated('cancelled task')
  assert(tasks.stop(stopped))
  done(stopped)
  assert(row(stopped).status == 'cancelled')
  local detached, detached_gate = gated('detached task')
  adapter.dispose()
  assert(core.active(tasks.get(detached)), 'Detaching presentation stopped its job')
  local count = #notices.tasks()
  vim.fn.writefile({}, detached_gate)
  done(detached)
  assert(#notices.tasks() == count and row(detached).status == 'cancelled', 'Late exit revived a disposed adapter')
  adapter.setup()
  local pending = gated('owner disposal')
  tasks.dispose()
  assert(row(pending).status == 'cancelled' and tasks.get(pending).status == 'stopped')
  local count = #notices.tasks()
  tasks.setup({ open = false })
  local silent = assert(tasks.run({ cmd = { 'sh', '-c', 'exit 0' } }, { open = false }))
  done(silent)
  assert(#notices.tasks() == count, 'Disposed subscription survived reinitialization')
  adapter.setup()
  local spawn = assert(tasks.run({ name = 'spawn failure', cmd = { root .. '/missing' } }, { open = false }))
  assert(row(spawn).status == 'error')
  notices.teardown()
end, debug.traceback)
adapter.dispose()
tasks.dispose()
vim.fn.delete(root, 'rf')
assert(ok, err)
if skipped then
  print('Task notifications: cold optional loading passed; SKIP real provider (set TASK_TOOLS_NOTIFICATION_ROOT)')
  return
end
print(
  'Task notifications: optional loading, concurrent jobs, summaries/history, output, cancellation, reconfiguration and disposal passed'
)
