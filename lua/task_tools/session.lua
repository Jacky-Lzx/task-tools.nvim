local M = {}
local restored = {}
local keys = { 'name', 'cmd', 'cwd', 'mode', 'errorformat', 'watch' }

function M.definitions()
  return vim.deepcopy(restored)
end

function M.save(path)
  assert(type(path) == 'string' and path ~= '', 'session path required')
  local core = require('task_tools.core')
  local definitions, seen = {}, {}
  local watching = {}
  for _, entry in ipairs(require('task_tools.watch').definitions()) do
    watching[entry.task] = entry.spec
  end
  for _, task in ipairs(core.list()) do
    local spec = watching[task.id] or core.spec(task.id)
    local entry = {}
    for _, key in ipairs(keys) do
      entry[key] = spec[key]
    end
    local fingerprint = vim.json.encode(entry)
    if not seen[fingerprint] then
      seen[fingerprint] = true
      definitions[#definitions + 1] = entry
    end
  end
  path = vim.fn.fnamemodify(path, ':p')
  local temp = path .. '.tmp-' .. vim.fn.getpid() .. '-' .. vim.uv.hrtime()
  local ok, err = pcall(function()
    assert(
      vim.fn.writefile({ vim.json.encode({ version = 1, tasks = definitions }) }, temp) == 0,
      'cannot write session'
    )
    assert(vim.uv.fs_rename(temp, path), 'cannot install session')
  end)
  if not ok then
    vim.fn.delete(temp)
    error(err)
  end
  return #definitions
end

function M.load(path)
  local data = require('task_tools.providers').read_json(path)
  assert(
    type(data) == 'table' and data.version == 1 and type(data.tasks) == 'table' and vim.islist(data.tasks),
    'invalid task session'
  )
  local definitions = {}
  for _, spec in ipairs(data.tasks) do
    definitions[#definitions + 1] = require('task_tools.core').normalize(spec)
  end
  restored = definitions
  -- Registration only: restoring a session never spawns a process or watcher.
  require('task_tools.providers').register('session', function()
    return M.definitions()
  end)
  return #definitions
end

return M
