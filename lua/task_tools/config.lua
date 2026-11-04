local M = {}

M.defaults = {
  output = { max_lines = 10000, max_line_bytes = 16384, flush_ms = 40 },
  history = 100,
  height = 12,
  open = true,
  focus = false,
  shell = nil, -- nil uses &shell for interactive terminals
  terminal = { position = 'float', width = 0.9, height = 0.9, border = 'rounded', zindex = 50, winblend = 0 },
  env = {},
  tasks = {},
  providers = true,
  python = 'python3', -- string or function(context) returning an executable
  watch_debounce = 150,
}
M.values = vim.deepcopy(M.defaults)

local function validate_terminal(opts)
  assert(type(opts) == 'table', 'terminal must be a table')
  assert(vim.tbl_contains({ 'float', 'bottom', 'top', 'left', 'right' }, opts.position), 'invalid terminal.position')
  for _, key in ipairs({ 'width', 'height' }) do
    local value = opts[key]
    assert(
      type(value) == 'number' and value > 0 and value < math.huge and (value <= 1 or value % 1 == 0),
      'invalid terminal.' .. key
    )
  end
  assert(
    vim.tbl_contains({ 'none', 'single', 'double', 'rounded', 'solid', 'shadow' }, opts.border),
    'invalid terminal.border'
  )
  assert(
    type(opts.zindex) == 'number' and opts.zindex >= 1 and opts.zindex < math.huge and opts.zindex % 1 == 0,
    'invalid terminal.zindex'
  )
  assert(
    type(opts.winblend) == 'number' and opts.winblend >= 0 and opts.winblend <= 100 and opts.winblend % 1 == 0,
    'invalid terminal.winblend'
  )
end

function M.terminal(opts)
  local result = vim.tbl_deep_extend('force', {}, M.values.terminal, opts or {})
  validate_terminal(result)
  return result
end

function M.setup(opts)
  local c = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  for _, key in ipairs({ 'max_lines', 'max_line_bytes', 'flush_ms' }) do
    assert(type(c.output[key]) == 'number' and c.output[key] >= 1 and c.output[key] % 1 == 0, 'invalid output.' .. key)
  end
  assert(type(c.history) == 'number' and c.history >= 1 and c.history % 1 == 0, 'invalid history')
  assert(type(c.height) == 'number' and c.height >= 1, 'invalid height')
  assert(type(c.watch_debounce) == 'number' and c.watch_debounce >= 1, 'invalid watch_debounce')
  assert(type(c.env) == 'table', 'env must be a table')
  assert(type(c.tasks) == 'table' or type(c.tasks) == 'function', 'tasks must be a list or function')
  validate_terminal(c.terminal)
  M.values = c
end

return M
