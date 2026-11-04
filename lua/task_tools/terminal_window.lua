local M = {}
local windows = {}

local function dimension(value, available)
  return math.max(1, math.min(available, math.floor(value <= 1 and available * value or value)))
end

local function geometry(settings, title)
  local columns = math.max(1, vim.o.columns)
  local lines = math.max(1, vim.o.lines - math.max(1, vim.o.cmdheight))
  local border = (columns < 3 or lines < 3) and 'none' or settings.border
  -- Reserve the border when centering, including shadow's right/bottom cells.
  local padding = border == 'none' and 0 or 2
  local width = dimension(settings.width, math.max(1, columns - padding))
  local height = dimension(settings.height, math.max(1, lines - padding))
  local opts = {
    relative = 'editor',
    style = 'minimal',
    border = border,
    width = width,
    height = height,
    row = math.max(0, math.floor((lines - height - padding) / 2)),
    col = math.max(0, math.floor((columns - width - padding) / 2)),
    zindex = settings.zindex,
  }
  if border ~= 'none' and border ~= 'shadow' then
    opts.title, opts.title_pos = title, 'center'
  end
  return opts
end

function M.open(buf, opts, title)
  local settings = require('task_tools.config').terminal(opts.window)
  local win
  if settings.position == 'float' then
    win = vim.api.nvim_open_win(buf, opts.focus ~= false, geometry(settings, title))
    windows[win] = { settings = settings, title = title }
    vim.wo[win].winblend = settings.winblend
  else
    local vertical = settings.position == 'left' or settings.position == 'right'
    local placement = (settings.position == 'top' or settings.position == 'left') and 'topleft' or 'botright'
    local size = dimension(
      vertical and settings.width or settings.height,
      math.max(1, (vertical and vim.o.columns or vim.o.lines - math.max(1, vim.o.cmdheight)) - 2)
    )
    vim.cmd(('%s %d%s'):format(placement, size, vertical and 'vsplit' or 'split'))
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end
  return win
end

function M.title(win, title)
  local entry = windows[win]
  if entry then
    entry.title = title
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.title then
      vim.api.nvim_win_set_config(win, { title = title, title_pos = 'center' })
    end
  end
end

local group = vim.api.nvim_create_augroup('TaskToolsTerminalWindows', { clear = true })
vim.api.nvim_create_autocmd('VimResized', {
  group = group,
  callback = function()
    for win, entry in pairs(windows) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_config(win, geometry(entry.settings, entry.title))
      else
        windows[win] = nil
      end
    end
  end,
})
vim.api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(event)
    windows[tonumber(event.match)] = nil
  end,
})

return M
