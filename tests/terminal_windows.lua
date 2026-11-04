vim.opt.rtp:prepend(vim.fn.getcwd())
local api = require('task_tools')
local core = require('task_tools.core')
local config = require('task_tools.config')
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
local function window(id)
  return vim.fn.win_findbuf(api.get(id).buf)[1]
end
local function stop(id)
  api.stop(id)
  assert(vim.wait(2000, function()
    return not core.active(api.get(id))
  end))
  api.remove(id)
end
local function launch(opts)
  return assert(api.run({ cmd = { 'sleep', '10' }, mode = 'terminal' }, opts or { open = true, focus = false }))
end
local ok, err = xpcall(function()
  vim.o.columns, vim.o.lines = 120, 40
  local source = vim.api.nvim_get_current_win()
  local original_layout = vim.fn.winlayout()
  local id = launch()
  local win = window(id)
  local geometry = vim.api.nvim_win_get_config(win)
  check(geometry.relative == 'editor' and geometry.border[1] == '╭', 'default terminal is a rounded float')
  check(
    vim.api.nvim_get_current_win() == source and vim.deep_equal(original_layout, vim.fn.winlayout()),
    'background float preserves focus and splits'
  )
  check(
    geometry.width < 120 and geometry.height < 40 and geometry.col > 0 and geometry.row > 0,
    'default float fits within editor'
  )
  stop(id)
  api.setup({ terminal = { width = 64, height = 16, border = 'double', zindex = 80, winblend = 15 } })
  id = launch()
  win = window(id)
  geometry = vim.api.nvim_win_get_config(win)
  check(geometry.width == 64 and geometry.height == 16 and geometry.border[1] == '╔', 'absolute size and border')
  check(geometry.zindex == 80 and vim.wo[win].winblend == 15, 'layer and transparency')
  vim.o.columns, vim.o.lines = 48, 14
  vim.api.nvim_exec_autocmds('VimResized', {})
  geometry = vim.api.nvim_win_get_config(win)
  check(
    geometry.width <= 46 and geometry.height <= 11 and geometry.col >= 0 and geometry.row >= 0,
    'resize clamps oversized float'
  )
  vim.o.columns, vim.o.lines = 120, 40
  vim.api.nvim_exec_autocmds('VimResized', {})
  check(
    vim.api.nvim_win_get_width(win) == 64 and vim.api.nvim_win_get_height(win) == 16,
    'resize restores requested absolute size'
  )
  stop(id)
  for _, position in ipairs({ 'bottom', 'top', 'left', 'right' }) do
    api.setup({ terminal = { position = position, width = 30, height = 8 } })
    id = launch()
    win = window(id)
    local pos = vim.api.nvim_win_get_position(win)
    local source_pos = vim.api.nvim_win_get_position(source)
    check(vim.api.nvim_win_get_config(win).relative == '', position .. ' creates a split')
    if position == 'left' or position == 'right' then
      check(
        vim.api.nvim_win_get_width(win) == 30
          and (position == 'left' and pos[2] < source_pos[2] or position == 'right' and pos[2] > source_pos[2]),
        position .. ' split size and side'
      )
    else
      check(
        vim.api.nvim_win_get_height(win) == 8
          and (position == 'top' and pos[1] < source_pos[1] or position == 'bottom' and pos[1] > source_pos[1]),
        position .. ' split size and side'
      )
    end
    stop(id)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  api.setup({ terminal = { position = 'bottom', height = 8 } })
  id =
    launch({ open = true, focus = false, window = { position = 'float', width = 0.5, height = 0.5, border = 'none' } })
  geometry = vim.api.nvim_win_get_config(window(id))
  check(
    geometry.relative == 'editor' and geometry.width == 60 and geometry.title == nil,
    'per-opening override with borderless fractional size'
  )
  stop(id)
  api.setup({ terminal = { border = 'shadow' } })
  id = launch({ open = true, focus = false, window = { position = 'float' } })
  check(vim.api.nvim_win_get_config(window(id)).relative == 'editor', 'shadow border supported')
  stop(id)
  for _, invalid in ipairs({
    { position = 'unknown' },
    { width = 0 },
    { height = 1.5 },
    { border = 'bad' },
    { winblend = 101 },
    { zindex = 0 },
  }) do
    local previous = vim.deepcopy(config.values)
    check(
      not pcall(api.setup, { terminal = invalid }) and vim.deep_equal(previous, config.values),
      'invalid style rejected atomically'
    )
  end
  local before = #api.list()
  local notify = vim.notify
  vim.notify = function() end
  check(
    not api.run({ cmd = { 'sleep', '10' }, mode = 'terminal' }, { window = { width = 0 } }) and #api.list() == before,
    'invalid override launches no job'
  )
  vim.notify = notify
end, debug.traceback)
for _, task in ipairs(api.list()) do
  if core.active(task) then
    stop(task.id)
  end
end
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
end
print(('PASS terminal windows: %d checks'):format(checks))
vim.cmd('qa!')
