-- Explicit inspection does not configure or start the plugin.
require('task_tools.user_command').create('TaskInfo', function()
  vim.notify(
    vim.inspect({
      state = require('task_tools').status(),
      definitions = {
        require('task_tools.providers').discover({
          buf = vim.bo.filetype == 'checkhealth' and vim.fn.bufnr('#') > 0 and vim.fn.bufnr('#') or nil,
        }),
      },
    }),
    vim.log.levels.INFO,
    { title = 'task-tools.nvim', filetype = 'lua' }
  )
end, { desc = 'Inspect configuration and current runtime state' })
