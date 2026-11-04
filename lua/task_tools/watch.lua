local M = {}
local core = require('task_tools.core')
local watchers, sequence = {}, 0

local function launch(w)
  if not w.enabled then
    return
  end
  if w.task then
    core.set_watch(w.task, nil)
  end
  local id, err = core.run(w.spec)
  if not id then
    M.disable(w.id)
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  w.task, w.pending = id, false
  core.set_watch(id, w.id)
end

function M.start(spec)
  local ok, normalized = pcall(core.normalize, spec)
  if not ok then
    return nil, normalized
  end
  local patterns = normalized.watch
  if patterns ~= true then
    if type(patterns) ~= 'table' or not vim.islist(patterns) or #patterns == 0 then
      return nil, 'watch must be true or a list of globs'
    end
    for _, pattern in ipairs(patterns) do
      if type(pattern) ~= 'string' then
        return nil, 'watch patterns must be strings'
      end
    end
  end
  normalized.watch = nil
  sequence = sequence + 1
  local w = { id = sequence, spec = normalized, patterns = patterns, enabled = true, ticket = 0 }
  watchers[w.id] = w
  launch(w)
  return w.task
end

function M.disable(id)
  local w = watchers[id]
  if not w then
    return false
  end
  w.enabled, w.pending = false, false
  w.ticket = w.ticket + 1
  core.set_watch(w.task, nil)
  watchers[id] = nil
  return true
end

function M.definitions()
  local result = {}
  for _, w in pairs(watchers) do
    local spec = vim.deepcopy(w.spec)
    spec.watch = vim.deepcopy(w.patterns)
    result[#result + 1] = { task = w.task, spec = spec }
  end
  return result
end

local function matches(w, file)
  file = vim.uv.fs_realpath(file) or file
  local cwd = (vim.uv.fs_realpath(w.spec.cwd) or w.spec.cwd):gsub('/$', '')
  if file:sub(1, #cwd + 1) ~= cwd .. '/' then
    return false
  end
  if w.patterns == true then
    return true
  end
  local relative = file:sub(#cwd + 2)
  for _, pattern in ipairs(w.patterns) do
    local regex = vim.fn.glob2regpat(pattern)
    if vim.fn.match(relative, regex) >= 0 or vim.fn.match(vim.fs.basename(file), regex) >= 0 then
      return true
    end
  end
  return false
end

local group = vim.api.nvim_create_augroup('TaskToolsWatch', { clear = true })
vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(event)
    local file = vim.fs.normalize(vim.fn.fnamemodify(event.file, ':p'))
    for _, w in pairs(watchers) do
      if matches(w, file) then
        w.ticket = w.ticket + 1
        local ticket = w.ticket
        vim.defer_fn(function()
          if not w.enabled or ticket ~= w.ticket then
            return
          end
          if core.active(core.get(w.task)) then
            w.pending = true
            core.stop(w.task)
          else
            launch(w)
          end
        end, require('task_tools.config').values.watch_debounce)
      end
    end
  end,
})

core.subscribe(function(task, kind)
  if kind == 'wipe' then
    if task.watch_id then
      M.disable(task.watch_id)
    end
    return
  end
  if kind ~= 'exit' then
    return
  end
  for _, w in pairs(watchers) do
    if w.task == task.id and w.pending then
      vim.schedule(function()
        launch(w)
      end)
    end
  end
end)

return M
