local M = {}

function M.check()
  vim.health.start('task-tools.nvim')
  if vim.fn.has('nvim-0.11') == 1 then
    vim.health.ok('Neovim 0.11+ is available')
  else
    vim.health.error('Neovim 0.11+ is required')
  end
  if vim.fn.executable(vim.o.shell) == 1 then
    vim.health.ok('Shell: ' .. vim.o.shell)
  else
    vim.health.error('Shell is not executable: ' .. vim.o.shell)
  end
  vim.health.info('No plugin dependencies. Built-in task templates require their corresponding tools.')
  local _, errors = require('task_tools.providers').discover()
  for _, err in ipairs(errors) do
    vim.health.warn(err)
  end
  if #errors == 0 then
    vim.health.ok('Task definitions are valid for this buffer')
  end
end

return M
