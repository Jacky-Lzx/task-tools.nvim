local M = {}
local windows = {}
local group

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
  M.setup()
  local settings = require('task_tools.config').terminal(opts.window)
  local win
  if settings.position == 'float' then
    win = vim.api.nvim_open_win(buf, opts.focus ~= false, geometry(settings, title))
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
  windows[win] = { settings = settings, title = title, buf = buf }
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

function M.setup()
  if group then
    return
  end
  group = vim.api.nvim_create_augroup('TaskToolsTerminalWindows', { clear = true })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      for win, entry in pairs(windows) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == entry.buf then
          if entry.settings.position == 'float' then
            vim.api.nvim_win_set_config(win, geometry(entry.settings, entry.title))
          end
          -- Update the child before the next terminal input can query its size.
          local channel = vim.bo[entry.buf].channel
          if channel > 0 then
            pcall(vim.fn.jobresize, channel, vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win))
          end
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
end

function M.dispose()
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end
  for win, entry in pairs(windows) do
    if
      vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == entry.buf
      and not vim.bo[entry.buf].modified
    then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
  windows = {}
end

return M
