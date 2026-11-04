local M = {}

-- A bounded ring, including unterminated lines. Never retain an unbounded chunk.
function M.new(opts)
  return { first = 1, count = 0, lines = {}, fragments = {}, dropped = 0, opts = vim.deepcopy(opts) }
end

function M.push(s, line)
  if #line > s.opts.max_line_bytes then
    line = line:sub(1, s.opts.max_line_bytes) .. ' [truncated]'
  end
  if s.count == s.opts.max_lines then
    s.lines[s.first] = nil
    s.first = s.first + 1
    s.count = s.count - 1
    s.dropped = s.dropped + 1
  end
  s.lines[s.first + s.count] = line
  s.count = s.count + 1
end

function M.receive(s, channel, data)
  local fragment = s.fragments[channel] or ''
  for i, part in ipairs(data) do
    -- job callbacks encode embedded NUL as NL inside a list element.
    part = part:gsub('\n', '^@')
    local room = s.opts.max_line_bytes - #fragment
    if room > 0 then
      fragment = fragment .. part:sub(1, room)
    end
    if #part > room then
      s.truncated = s.truncated or {}
      s.truncated[channel] = true
    end
    if i < #data then
      M.push(s, fragment .. (s.truncated and s.truncated[channel] and ' [truncated]' or ''))
      fragment = ''
      if s.truncated then
        s.truncated[channel] = nil
      end
    end
  end
  s.fragments[channel] = fragment
end

function M.finish(s)
  for _, channel in ipairs({ 'stdout', 'stderr' }) do
    local fragment = s.fragments[channel]
    if fragment and fragment ~= '' then
      M.push(s, fragment .. (s.truncated and s.truncated[channel] and ' [truncated]' or ''))
    end
  end
  s.fragments = {}
end

function M.lines(s, partial)
  local lines = {}
  for i = s.first, s.first + s.count - 1 do
    lines[#lines + 1] = s.lines[i]
  end
  if partial then
    for _, channel in ipairs({ 'stdout', 'stderr' }) do
      if s.fragments[channel] and s.fragments[channel] ~= '' then
        lines[#lines + 1] = s.fragments[channel]
      end
    end
  end
  return lines
end

return M
