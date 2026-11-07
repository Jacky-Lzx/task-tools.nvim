local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local real = require('task_tools')
local tasks = require('task_tools.workflows')
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
check(
  vim.deep_equal(
    tasks.argv([[one 'two words' "" escaped\ space "a\"b" '$HOME']]),
    { 'one', 'two words', '', 'escaped space', 'a"b', '$HOME' }
  ),
  'literal argv parsing'
)
check(not tasks.argv([["unclosed]]), 'unclosed arguments rejected')
check(not tasks.argv('trailing\\'), 'trailing escape rejected')

local api = {}
local launched, last_spec, next_id, selected, selected_id = {}, nil, 0, '/selected/python', nil
api.run = function(spec)
  next_id = next_id + 1
  launched[#launched + 1], last_spec = vim.deepcopy(spec), vim.deepcopy(spec)
  return next_id
end
api.get = function(id)
  return { id = id }
end
api.rerun = function(id)
  selected_id = id
  return api.run(launched[id])
end
api.stop = function(id)
  selected_id = id
end
api.show = api.stop
api.quickfix = api.stop
api.list = function()
  return launched
end
package.loaded.task_tools = api
require('task_tools.config').setup({
  python = function()
    return selected
  end,
})
local previous_input = vim.ui.input
vim.ui.input = function(opts, callback)
  check(opts.default == 'make', 'initial build command')
  callback('printf build')
end
tasks.prompt({ default = 'make' })
local build_id, build_cwd = next_id, last_spec.cwd
api.run({ cmd = 'terminal' })
tasks.rerun()
check(
  selected_id == build_id and last_spec.cwd == build_cwd and last_spec.cmd == 'printf build',
  'manual rerun is independent of latest terminal'
)
local repeat_id = next_id
tasks.stop()
check(selected_id == repeat_id, 'manual stop uses build ID')
tasks.output()
check(selected_id == repeat_id, 'manual output uses build ID')
tasks.quickfix()
check(selected_id == repeat_id, 'manual quickfix uses build ID')
local before = #launched
vim.ui.input = function(_, callback)
  callback(nil)
end
tasks.prompt({ default = 'make' })
check(#launched == before, 'build cancellation')
vim.api.nvim_buf_set_name(0, root .. '/a file.py')
vim.bo.filetype = 'python'
vim.ui.input = function(_, callback)
  selected = '/new interpreter/python'
  callback([['a b' "" '$HOME']])
end
tasks.run_file()
check(
  vim.deep_equal(last_spec.cmd, { selected, root .. '/a file.py', 'a b', '', '$HOME' }) and last_spec.mode == 'terminal',
  'Python args and interpreter captured at run time'
)
vim.api.nvim_buf_set_name(0, root .. '/a file.cpp')
vim.bo.filetype = 'cpp'
local prompt = 0
vim.ui.input = function(opts, callback)
  prompt = prompt + 1
  if prompt == 1 then
    check(opts.default == root .. '/a file', 'C++ default executable')
    callback('./other program')
  else
    callback([[--name "a b"]])
  end
end
tasks.run_file()
check(
  vim.deep_equal(last_spec.cmd, { root .. '/other program', '--name', 'a b' }),
  'C++ executable and args remain separate argv entries'
)
before = #launched
vim.ui.input = function(_, callback)
  callback(nil)
end
tasks.run_file()
check(#launched == before, 'executable cancellation')
-- A deleted history item can still be rerun, and disposal forgets the manual slot.
api.get = function()
  return nil
end
tasks.rerun()
check(last_spec.cmd == 'printf build', 'manual spec survives history removal')
tasks.dispose()
vim.ui.input = function(opts, callback)
  check(opts.default == 'make', 'rerun forwards personal first-command default')
  callback(nil)
end
tasks.rerun({ default = 'make' })
vim.ui.input = previous_input
package.loaded.task_tools = real
tasks.dispose()
print('tasks: ' .. checks .. ' checks passed')
