local M = {}
local core = require('task_tools.core')
local parser = require('task_tools.parser')
local config = require('task_tools.config')
local list_buf, list_win, rows, origin
local unsubscribe
local ns = vim.api.nvim_create_namespace('TaskTools')
local rendered = {}
local colors = {
  running = 'DiagnosticInfo',
  stopping = 'DiagnosticWarn',
  success = 'DiagnosticOk',
  failure = 'DiagnosticError',
  stopped = 'Comment',
}

local function safe(text)
  return tostring(text):gsub('[\r\n\t]', ' ')
end

local function close(win)
  if win and vim.api.nvim_win_is_valid(win) then
    if #vim.api.nvim_list_wins() > 1 then
      vim.api.nvim_win_close(win, false)
    else
      vim.cmd('enew')
    end
  end
end

local function window(buf, opts)
  opts = opts or {}
  if not opts.terminal and opts.win and vim.api.nvim_win_is_valid(opts.win) then
    vim.api.nvim_win_set_buf(opts.win, buf)
    return opts.win
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      if opts.focus ~= false then
        vim.api.nvim_set_current_win(win)
      end
      return win
    end
  end
  local previous = vim.api.nvim_get_current_win()
  if vim.bo.buftype == '' then
    origin = previous
  end
  local win
  if opts.terminal then
    win = require('task_tools.terminal_window').open(buf, opts, opts.title)
  else
    vim.cmd('botright ' .. math.max(1, math.floor(opts.height or config.values.height)) .. 'split')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end
  vim.wo[win].number, vim.wo[win].relativenumber = false, false
  vim.wo[win].signcolumn, vim.wo[win].foldcolumn = 'no', '0'
  vim.wo[win].statuscolumn, vim.wo[win].winbar = '', ''
  vim.wo[win].colorcolumn, vim.wo[win].list = '', false
  if opts.focus == false and vim.api.nvim_win_is_valid(previous) then
    vim.api.nvim_set_current_win(previous)
  end
  return win
end

local function statusline(task)
  return (' Task #%d [%s] %s'):format(task.id, task.status, safe(task.name)):gsub('%%', '%%%%')
end

local function render_output(task)
  if not task.buf or not vim.api.nvim_buf_is_valid(task.buf) then
    return
  end
  if task.mode == 'pipe' or vim.bo[task.buf].buftype ~= 'terminal' then
    local follows = {}
    local previous_drop = rendered[task.buf] or 0
    local shift = task.dropped - previous_drop - (previous_drop == 0 and task.dropped > 0 and 1 or 0)
    for _, win in ipairs(vim.fn.win_findbuf(task.buf)) do
      local cursor = vim.api.nvim_win_get_cursor(win)
      follows[win] = {
        tail = cursor[1] >= vim.api.nvim_buf_line_count(task.buf),
        view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
      }
    end
    local lines = core.output(task.id)
    for i, line in ipairs(lines) do
      lines[i] = parser.clean(line)
    end
    if task.dropped > 0 then
      table.insert(lines, 1, ('[%d older lines discarded]'):format(task.dropped))
    end
    vim.bo[task.buf].modifiable = true
    vim.api.nvim_buf_set_lines(task.buf, 0, -1, false, lines)
    vim.bo[task.buf].modifiable = false
    for win, follow in pairs(follows) do
      if follow.tail then
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(task.buf), 0 })
      else
        follow.view.lnum = math.max(1, follow.view.lnum - shift)
        follow.view.topline = math.max(1, follow.view.topline - shift)
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview(follow.view)
        end)
      end
    end
    rendered[task.buf] = task.dropped
  end
  for _, win in ipairs(vim.fn.win_findbuf(task.buf)) do
    vim.wo[win].statusline = statusline(task)
    if task.mode == 'terminal' then
      require('task_tools.terminal_window').title(
        win,
        (' Task #%d [%s] %s '):format(task.id, task.status, safe(task.name))
      )
    end
  end
end

function M.jump(id)
  local task = core.get(id)
  if not task then
    return
  end
  local line = vim.api.nvim_get_current_line()
  local ok, items = pcall(parser.parse, { line }, task.cwd, core.spec(id).errorformat)
  if not ok then
    vim.notify(items, vim.log.levels.ERROR)
    return
  end
  local item = items[1]
  if not item or item.valid ~= 1 then
    return
  end
  if origin and vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  else
    vim.cmd('aboveleft split')
  end
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_buf(0, item.bufnr)
  vim.api.nvim_win_set_cursor(
    0,
    { math.min(item.lnum, vim.api.nvim_buf_line_count(item.bufnr)), math.max(0, item.col - 1) }
  )
end

function M.output(id, opts)
  M.setup()
  opts = opts or {}
  local task = core.get(id)
  if not task then
    return false, 'no task selected'
  end
  if task.mode == 'terminal' then
    local valid, err = pcall(config.terminal, opts.window)
    if not valid then
      return false, tostring(err)
    end
  end
  if not task.buf or not vim.api.nvim_buf_is_valid(task.buf) then
    if task.mode == 'terminal' then
      return false, 'terminal buffer was deleted'
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'task-tools://output/' .. task.id)
    vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'nofile', 'hide', false
    vim.bo[buf].filetype = 'tasktoolsoutput'
    core.set_buffer(task.id, buf)
    task = core.get(task.id)
  end
  local buf = task.buf
  vim.keymap.set('n', 'q', function()
    close(vim.api.nvim_get_current_win())
  end, { buffer = buf, silent = true, desc = 'Hide task output' })
  vim.keymap.set('n', 'gq', function()
    require('task_tools').quickfix(task.id)
  end, { buffer = buf, desc = 'Task quickfix' })
  if task.mode == 'pipe' then
    vim.keymap.set('n', '<CR>', function()
      M.jump(task.id)
    end, { buffer = buf, desc = 'Jump to output location' })
  else
    vim.keymap.set('t', '<C-]>', '<C-\\><C-n>', { buffer = buf, desc = 'Terminal normal mode' })
  end
  opts = vim.tbl_extend('force', {}, opts, { terminal = task.mode == 'terminal', title = safe(task.name) })
  local win = window(buf, opts)
  render_output(core.get(task.id))
  vim.wo[win].wrap = false
  if task.mode == 'terminal' and opts.focus ~= false and core.active(task) then
    vim.cmd('startinsert')
  end
  return true
end

function M.quickfix(id, opts)
  local task = core.get(id)
  if not task then
    return false, 'no task selected'
  end
  local ok, items = pcall(parser.parse, core.output(task.id), task.cwd, core.spec(task.id).errorformat)
  if not ok then
    return false, tostring(items)
  end
  vim.fn.setqflist({}, ' ', {
    title = statusline(task),
    items = items,
    context = { task_tools = true, id = task.id, cwd = task.cwd, status = task.status },
  })
  if not opts or opts.open ~= false then
    local previous = vim.api.nvim_get_current_win()
    vim.cmd('botright copen ' .. math.floor(config.values.height))
    if opts and opts.focus == false then
      vim.api.nvim_set_current_win(previous)
    end
  end
  return true
end

local function selected()
  return rows and rows[vim.api.nvim_win_get_cursor(0)[1]]
end

local function render_list()
  if not list_buf or not vim.api.nvim_buf_is_valid(list_buf) then
    return
  end
  local current
  if list_win and vim.api.nvim_win_is_valid(list_win) and rows then
    current = rows[vim.api.nvim_win_get_cursor(list_win)[1]]
  end
  local lines = { ' Tasks   <Enter> output   r rerun   s stop   w watch   d delete   c errors   q close', '' }
  rows = {}
  local cursor
  for _, task in ipairs(core.list()) do
    lines[#lines + 1] = (' #%d  %-8s %s%s'):format(
      task.id,
      task.status,
      safe(task.name),
      task.watch_id and '  [watch]' or ''
    )
    rows[#lines] = task.id
    if current == task.id then
      cursor = #lines
    end
  end
  if #lines == 2 then
    lines[#lines + 1] = ' No tasks. Use :TaskRun or :TaskShell.'
  end
  vim.bo[list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
  vim.bo[list_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(list_buf, ns, 0, -1)
  for line, id in pairs(rows) do
    vim.api.nvim_buf_set_extmark(
      list_buf,
      ns,
      line - 1,
      0,
      { end_col = #lines[line], hl_group = colors[core.get(id).status] }
    )
  end
  if list_win and vim.api.nvim_win_is_valid(list_win) and vim.api.nvim_win_get_buf(list_win) == list_buf then
    vim.api.nvim_win_set_cursor(list_win, { cursor or math.min(3, #lines), 0 })
  end
end

function M.open(opts)
  M.setup()
  if not list_buf or not vim.api.nvim_buf_is_valid(list_buf) then
    list_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(list_buf, 'task-tools://list')
    vim.bo[list_buf].buftype, vim.bo[list_buf].bufhidden, vim.bo[list_buf].filetype = 'nofile', 'hide', 'tasktools'
    local actions = {
      ['<CR>'] = function(id)
        M.output(id, { win = vim.api.nvim_get_current_win() })
      end,
      r = function(id)
        require('task_tools').rerun(id, { open = false })
      end,
      s = function(id)
        require('task_tools').stop(id)
      end,
      d = function(id)
        require('task_tools').remove(id)
      end,
      c = function(id)
        require('task_tools').quickfix(id)
      end,
      w = function(id)
        require('task_tools').toggle_watch(id)
      end,
    }
    local descriptions = {
      ['<CR>'] = 'Show selected task output',
      r = 'Rerun selected task',
      s = 'Stop selected task',
      d = 'Remove selected task',
      c = 'Open selected task quickfix',
      w = 'Toggle selected task file watch',
    }
    for key, action in pairs(actions) do
      vim.keymap.set('n', key, function()
        local id = selected()
        if id then
          action(id)
          render_list()
        end
      end, { buffer = list_buf, silent = true, desc = descriptions[key] })
    end
    vim.keymap.set('n', 'q', function()
      M.close()
    end, { buffer = list_buf, silent = true, desc = 'Close task list' })
    vim.keymap.set('n', '<Esc>', function()
      M.close()
    end, { buffer = list_buf, silent = true, desc = 'Close task list' })
  end
  list_win = window(list_buf, opts)
  vim.wo[list_win].statusline = ' Task Tools'
  render_list()
end

function M.close()
  if list_win and vim.api.nvim_win_is_valid(list_win) and vim.api.nvim_win_get_buf(list_win) == list_buf then
    close(list_win)
  end
  list_win = nil
end

function M.toggle(opts)
  if list_win and vim.api.nvim_win_is_valid(list_win) and vim.api.nvim_win_get_buf(list_win) == list_buf then
    M.close()
  else
    M.open(opts)
  end
end

function M.setup()
  if unsubscribe then
    return
  end
  unsubscribe = core.subscribe(function(task, kind)
    if kind ~= 'output' then
      render_list()
    end
    if task then
      render_output(task)
    end
  end)
end

function M.dispose()
  M.close()
  if unsubscribe then
    unsubscribe()
    unsubscribe = nil
  end
  rendered = {}
end

return M
