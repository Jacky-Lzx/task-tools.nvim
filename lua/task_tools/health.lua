local M = {}

function M.check()
  vim.health.start('task-tools.nvim')
  if vim.fn.has('nvim-0.11') == 0 then
    vim.health.error('Neovim 0.11+ is required', { 'Upgrade Neovim' })
    return
  end
  local issues = {}
  local function problem(level, message, advice)
    issues[#issues + 1] = { level = level, message = message, advice = advice }
  end
  if vim.fn.executable(vim.o.shell) == 0 then
    problem(
      'error',
      'Shell is not executable: ' .. vim.o.shell .. '; tasks cannot start.',
      { 'Set shell to a usable executable' }
    )
  end
  -- Provider discovery may execute project callbacks; leave it to explicit TaskInfo.

  table.sort(issues, function(a, b)
    if a.level ~= b.level then
      return a.level == 'error'
    end
    return a.message < b.message
  end)
  for _, issue in ipairs(issues) do
    vim.health[issue.level](issue.message, issue.advice)
  end
  if #issues == 0 then
    vim.health.ok('Task execution runtime requirements are satisfied.')
  end
  vim.health.info('Details: :TaskInfo')
end

return M
