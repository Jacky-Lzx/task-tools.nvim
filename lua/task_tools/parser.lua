local M = {}

M.errorformat = table.concat({
  '%f:%l:%c: %m',
  '%f:%l: %m',
  '%f(%l\\,%c): %m',
  '%f(%l): %m',
  '%\\s%#--> %f:%l:%c',
  '%\\s%#::: %f:%l:%c',
  '%\\s%#File "%f"\\, line %l%m',
  '%f:%l:%c:%m',
  '%f:%l:%m',
  '%f:%l:%c',
  '%f:%l',
}, ',')

function M.clean(line)
  return line
    :gsub('\27%][^\7\27]*\7', '')
    :gsub('\27%][^\7\27]*\27\\', '')
    :gsub('\27%[[0-?]*[ -/]*[@-~]', '')
    :gsub('\r$', '')
    :gsub('.*\r', '')
end

function M.parse(lines, cwd, efm)
  local previous = vim.fn.getcwd()
  local restore = vim.fn.haslocaldir() == 1 and 'lcd' or (vim.fn.haslocaldir(-1) ~= 0 and 'tcd' or 'cd')
  vim.api.nvim_cmd({ cmd = 'lcd', args = { cwd }, mods = { noautocmd = true } }, {})
  local ok, result = pcall(function()
    local items = {}
    for _, line in ipairs(lines) do
      line = M.clean(line)
      local parsed = vim.fn.getqflist({ lines = { line }, efm = efm or M.errorformat }).items
      local item = { text = line, valid = 0 }
      for _, candidate in ipairs(parsed) do
        if candidate.valid == 1 and candidate.bufnr > 0 and candidate.lnum > 0 then
          item = candidate
          item.text = line
          break
        end
      end
      items[#items + 1] = item
    end
    return items
  end)
  vim.api.nvim_cmd({ cmd = restore, args = { previous }, mods = { noautocmd = true } }, {})
  if not ok then
    error(result)
  end
  return result
end

return M
