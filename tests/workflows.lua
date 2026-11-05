vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/task-tools.lua')
local api = require('task_tools')
local core = require('task_tools.core')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/src', 'p')
root = vim.uv.fs_realpath(root)
local checks = 0
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
local function wait(id)
  assert(
    vim.wait(5000, function()
      return not core.active(core.get(id))
    end),
    'task timeout'
  )
end
local function write(path, lines)
  vim.fn.writefile(lines, root .. '/' .. path)
end
local function save_event(file)
  vim.api.nvim_exec_autocmds('BufWritePost', { pattern = file, modeline = false })
end
local function count()
  return #api.list()
end
local function find(defs, name)
  for _, def in ipairs(defs) do
    if def.name == name then
      return def
    end
  end
end
local function latest()
  return api.list()[1]
end
local ok, err = xpcall(function()
  api.setup({ open = false, watch_debounce = 20, output = { flush_ms = 5 } })
  write('Makefile', { 'all:', '\t@printf built', 'test: all', '\t@printf tested' })
  write('package.json', { '{"scripts":{"test":"echo test","dev":"echo dev"}}' })
  write('pnpm-lock.yaml', {})
  write(
    '.task-tools.json',
    { vim.json.encode({ version = 1, tasks = { { name = 'custom', cmd = { 'printf', 'custom' }, cwd = 'src' } } }) }
  )
  write('src/main.py', { 'print("hello")' })
  vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/src/main.py'))
  vim.bo.filetype = 'python'
  local defs, errors, ctx = api.discover()
  check(#errors == 0 and ctx.cwd == root, 'nearest project root')
  check(find(defs, 'make test') and find(defs, 'pnpm run dev'), 'make and package scripts discovered')
  check(find(defs, 'custom').cwd == root .. '/src', 'project cwd resolved')
  check(find(defs, 'Python: run file').cmd[2] == root .. '/src/main.py', 'current-file provider')
  api.setup({
    open = false,
    tasks = function()
      return { { name = 'make', cmd = 'printf override' } }
    end,
    python = function(context)
      assert(context.buf == vim.api.nvim_get_current_buf())
      return '/selected/python'
    end,
    python_env = function(context)
      return { VIRTUAL_ENV = '/selected', PATH = '/selected/bin', SOURCE = context.file }
    end,
  })
  defs = api.discover()
  check(
    find(defs, 'make').cmd == 'printf override' and find(defs, 'Python: run file').cmd[1] == '/selected/python',
    'config and interpreter providers'
  )
  check(
    find(defs, 'Python: run file').env.VIRTUAL_ENV == '/selected'
      and find(defs, 'Python: run file').env.SOURCE == root .. '/src/main.py',
    'project Python child environment'
  )
  api.register_provider('broken', function()
    error('provider exploded')
  end)
  defs, errors = api.discover()
  check(#errors == 1 and find(defs, 'custom'), 'provider failure isolated')
  api.register_provider('broken', function()
    return {}
  end)
  write('package.json', { '{bad json' })
  defs, errors = api.discover()
  check(#errors == 1 and find(defs, 'custom'), 'malformed JSON isolated')
  write('package.json', { '{"scripts":{}}' })
  local before = count()
  vim.ui.select = function(_, _, callback)
    callback(nil)
  end
  api.select()
  check(count() == before, 'picker cancellation')
  local input_opts
  vim.ui.input = function(opts, callback)
    input_opts = opts
    callback(nil)
  end
  api.prompt()
  check(count() == before and input_opts.completion == 'shellcmd', 'prompt cancellation')
  local custom = api.select('custom')
  wait(custom)
  check(api.output(custom)[1] == 'custom', 'named task execution')
  local source_win = vim.api.nvim_get_current_win()
  local id = api.run({
    name = 'diagnostics',
    cmd = { 'sh', '-c', 'printf "src/main.py:1:2: broken\n"; sleep .1; printf done' },
    cwd = root,
  }, { open = true })
  check(vim.api.nvim_get_current_win() == source_win, 'output preserves source focus')
  vim.fn.setqflist({}, ' ', { title = 'user list', items = { { text = 'preserved' } } })
  wait(id)
  check(vim.fn.getqflist({ title = 0 }).title == 'user list', 'background tasks preserve quickfix')
  local output_buf = api.get(id).buf
  check(table.concat(vim.api.nvim_buf_get_lines(output_buf, 0, -1, false), '\n'):find('done'), 'streamed output buffer')
  api.quickfix(id, { open = false })
  local item = vim.fn.getqflist()[1]
  check(item.valid == 1 and item.lnum == 1 and item.col == 2, 'quickfix export')
  local streaming = api.run({
    cmd = {
      'sh',
      '-c',
      'i=1; while [ "$i" -le 30 ]; do printf "%s\n" "$i"; i=$((i+1)); done; sleep .15; printf "new output\n"',
    },
  }, { open = true, focus = true })
  check(
    vim.wait(1000, function()
      return vim.api.nvim_buf_line_count(api.get(streaming).buf) >= 30
    end),
    'initial streamed lines rendered'
  )
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  wait(streaming)
  check(vim.api.nvim_win_get_cursor(0)[1] == 5, 'streaming preserves scrolled cursor')
  local missing_terminal = api.run(
    { cmd = { '/no-such-task-tools-program' }, mode = 'terminal' },
    { open = true, focus = true }
  )
  check(
    vim.api.nvim_get_current_line():find('Cannot start command') and api.get(missing_terminal).status == 'failure',
    'terminal launch failure is visible'
  )
  vim.cmd('lcd ' .. vim.fn.fnameescape(vim.fs.dirname(root)))
  local repeat_id = api.rerun(custom)
  wait(repeat_id)
  check(repeat_id ~= custom and api.get(repeat_id).cwd == root .. '/src', 'rerun has fresh ID and original cwd')
  api.show(id)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  require('task_tools.ui').jump(id)
  check(
    vim.api.nvim_buf_get_name(0) == root .. '/src/main.py' and vim.api.nvim_win_get_cursor(0)[2] == 1,
    'output location jump'
  )
  api.open()
  check(vim.bo.filetype == 'tasktools', 'task list opens')
  api.toggle()
  check(vim.bo.filetype ~= 'tasktools', 'task list toggle closes')
  api.setup({ open = false, watch_debounce = 20 })
  local watch_id =
    api.run({ name = 'watch', cmd = { 'sh', '-c', 'printf start; sleep 10' }, cwd = root, watch = { '*.py' } })
  before = count()
  save_event(root .. '/src/ignored.txt')
  vim.wait(60)
  check(count() == before, 'watch ignores nonmatching files')
  for _ = 1, 5 do
    save_event(root .. '/src/main.py')
  end
  check(
    vim.wait(3000, function()
      return count() == before + 1
    end),
    'watch restarted'
  )
  local restarted = latest()
  check(
    api.get(watch_id).status == 'stopped' and restarted.watch_id ~= nil,
    'watch stops previous process before new run'
  )
  vim.wait(80)
  check(count() == before + 1, 'watch debounce collapses saves')
  check(not api.rerun(restarted.id), 'active rerun rejected')
  check(not api.remove(restarted.id), 'active deletion rejected')
  api.stop(restarted.id)
  wait(restarted.id)
  before = count()
  save_event(root .. '/src/main.py')
  vim.wait(60)
  check(count() == before and not api.get(restarted.id).watch_id, 'manual stop disables watcher')
  local wipe_watch = api.run({ cmd = { 'sleep', '10' }, mode = 'terminal', cwd = root, watch = true })
  vim.api.nvim_buf_delete(api.get(wipe_watch).buf, { force = true })
  wait(wipe_watch)
  check(not api.get(wipe_watch).watch_id, 'wiping watched terminal disables watcher')
  local completed_watch = api.run({ cmd = { 'printf', 'watch done' }, cwd = root, watch = true })
  wait(completed_watch)
  before = count()
  save_event(root .. '2/outside.py')
  vim.wait(60)
  check(count() == before, 'watch directory boundary')
  save_event(root .. '/src/main.py')
  check(
    vim.wait(2000, function()
      return count() > before
    end),
    'completed task watch reruns'
  )
  wait(latest().id)
  api.toggle_watch(latest().id)
  local saved = api.save(root .. '/session.json')
  check(saved and saved > 0, 'session saved')
  before = count()
  check(api.load(root .. '/session.json') == saved and count() == before, 'session restoration does not execute')
  local session_text = table.concat(vim.fn.readfile(root .. '/session.json'))
  check(not session_text:find('"env"') and not session_text:find('"job"'), 'session omits runtime and environment')
  local sessions = require('task_tools.session').definitions()
  write('invalid.json', { '{"version":1,"tasks":[{"cmd":"echo","cwd":"/no-such-task-tools-dir"}]}' })
  check(
    not api.load(root .. '/invalid.json') and vim.deep_equal(sessions, require('task_tools.session').definitions()),
    'invalid session load is atomic'
  )
  vim.cmd('TaskShell printf command | tr a-z A-Z')
  wait(latest().id)
  check(api.output(latest().id)[1] == 'COMMAND', 'shell command operators preserved')
  check(not pcall(vim.cmd, 'TaskStop invalid'), 'invalid command ID rejected')
  local counts = api.status()
  check(counts.running == 0 and counts.success > 0 and counts.stopped > 0, 'status counts')
  api.setup({ open = false, history = 2 })
  local a = api.run('printf a')
  wait(a)
  local b = api.run('printf b')
  wait(b)
  check(count() <= 2 and api.get(b) ~= nil, 'completed history pruned')
end, debug.traceback)
for _, task in ipairs(api.list()) do
  if core.active(task) then
    api.stop(task.id)
    wait(task.id)
  end
end
vim.fn.delete(root, 'rf')
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
end
print(('PASS workflows: %d checks'):format(checks))
vim.cmd('qa!')
