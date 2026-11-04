local M = {}

M.defaults = {
  output = { max_lines = 10000, max_line_bytes = 16384, flush_ms = 40 },
  history = 100,
  height = 12,
  open = true,
  focus = false,
  shell = nil, -- nil uses &shell for interactive terminals
  env = {},
  tasks = {},
  providers = true,
  python = 'python3', -- string or function(context) returning an executable
  watch_debounce = 150,
}
M.values = vim.deepcopy(M.defaults)

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
  M.values = c
end

return M
