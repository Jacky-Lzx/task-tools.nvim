vim.opt.rtp:prepend(vim.fn.getcwd())
local core = require('task_tools.core')
local config = require('task_tools.config')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/with space', 'p')
root = vim.uv.fs_realpath(root)
local checks = 0
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
  return core.get(id)
end
local function run(spec)
  local id, err = core.run(spec)
  assert(id, err)
  return id
end
local ok, err = xpcall(function()
  config.setup({ output = { max_lines = 20, max_line_bytes = 128, flush_ms = 5 } })
  local id =
    run({ cmd = { 'sh', '-c', 'printf abc; sleep .05; printf "def\n"; printf "err\n" >&2; printf final' }, cwd = root })
  check(wait(id).status == 'success', 'success status')
  check(vim.deep_equal(core.output(id), { 'abcdef', 'err', 'final' }), 'chunked stdout and stderr')
  local snapshot = core.get(id)
  snapshot.cmd[1] = 'bad'
  check(core.get(id).cmd[1] == 'sh', 'snapshots are isolated')
  local slow = run({ cmd = { 'sh', '-c', 'sleep 10' } })
  local fast = run({ cmd = 'printf parallel' })
  check(wait(fast).status == 'success' and core.active(core.get(slow)), 'parallel jobs')
  check(core.stop(slow), 'stop accepted')
  check(wait(slow).status == 'stopped', 'stop final state')
  check(not core.stop(slow), 'completed task cannot stop')
  local fail = run({ cmd = { 'sh', '-c', 'exit 17' } })
  check(wait(fail).exit_code == 17 and core.get(fail).status == 'failure', 'failure status')
  local env =
    run({ cmd = { 'sh', '-c', 'printf "%s" "$TASK_TEST"; cat' }, env = { TASK_TEST = 'value' }, stdin = 'stdin' })
  wait(env)
  check(table.concat(core.output(env)) == 'valuestdin', 'environment and stdin')
  local cwd = run({ cmd = { 'pwd' }, cwd = root .. '/with space' })
  vim.cmd('lcd /private/tmp')
  wait(cwd)
  check(vim.uv.fs_realpath(core.output(cwd)[1]) == vim.uv.fs_realpath(root .. '/with space'), 'captured cwd')
  local bad, validation = core.run({ cmd = '' })
  check(not bad and validation:find('empty'), 'invalid command')
  check(not core.run({ cmd = { 'echo', 1 } }), 'invalid argv')
  check(not core.run({ cmd = 'echo', cwd = root .. '/missing' }), 'invalid cwd')
  local missing = run({ cmd = { '/definitely-missing-task-tools-command' } })
  check(core.get(missing).status == 'failure', 'missing executable recorded')
  local huge = run({
    cmd = {
      'sh',
      '-c',
      'i=0; while [ "$i" -lt 200 ]; do printf "line %s\n" "$i"; i=$((i+1)); done; head -c 100000 /dev/zero | tr "\\0" x',
    },
  })
  wait(huge)
  check(#core.output(huge) == 20 and core.get(huge).dropped == 181, 'bounded ring')
  check(#core.output(huge)[20] < 160, 'bounded unterminated output')
  local parser = require('task_tools.parser')
  local before = { vim.fn.getcwd(), vim.fn.haslocaldir() }
  local items = parser.parse({ '\27[31mwith space/a.c:12:4: error: test\27[0m', 'ordinary' }, root)
  check(items[1].valid == 1 and items[1].lnum == 12 and items[1].col == 4, 'locations parsed')
  check(vim.api.nvim_buf_get_name(items[1].bufnr) == root .. '/with space/a.c', 'relative paths')
  check(
    items[2].valid == 0 and vim.deep_equal(before, { vim.fn.getcwd(), vim.fn.haslocaldir() }),
    'logs and cwd scope preserved'
  )
  local term = run({
    cmd = { 'sh', '-c', 'printf "PTY> "; read answer; printf "ANSWER:%s\n" "$answer"' },
    mode = 'terminal',
    cwd = root,
  })
  check(
    vim.wait(2000, function()
      return table.concat(core.output(term), '\n'):find('PTY>') ~= nil
    end),
    'terminal output'
  )
  check(core.send(term, 'hello\n'), 'terminal input')
  check(wait(term).status == 'success' and table.concat(core.output(term)):find('ANSWER:hello'), 'interactive PTY')
  local active = run({ cmd = { 'sleep', '10' }, mode = 'terminal' })
  vim.api.nvim_buf_delete(core.get(active).buf, { force = true })
  check(wait(active).status == 'stopped', 'wiped terminal stops process')
  check(core.remove(id) and core.get(id) == nil, 'remove completed task')
end, debug.traceback)
vim.fn.delete(root, 'rf')
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
end
print(('PASS core: %d checks'):format(checks))
vim.cmd('qa!')
