vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/task-tools.lua')
local api = require('task_tools')
local root = assert(vim.env.TASK_TOOLS_TEST_DIR)
local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
local function screen()
  vim.cmd('redraw!')
  local lines = {}
  for row = 1, vim.o.lines do
    local line = ''
    for col = 1, vim.o.columns do
      line = line .. vim.fn.screenstring(row, col)
    end
    lines[#lines + 1] = line
  end
  return table.concat(lines, '\n')
end
local function stage(name, ready, callback)
  vim.fn.writefile({ name }, root .. '/stage')
  local started = vim.uv.hrtime()
  local function poll()
    local ok, err = xpcall(function()
      if ready() then
        callback()
        return
      end
      assert((vim.uv.hrtime() - started) / 1e9 < 7, 'timeout: ' .. name .. '\n' .. screen())
      vim.defer_fn(poll, 15)
    end, debug.traceback)
    if not ok then
      vim.fn.writefile({ err, screen() }, root .. '/result')
      vim.cmd('cquit 1')
    end
  end
  vim.defer_fn(poll, 15)
end
local function active(id)
  return require('task_tools.core').active(api.get(id))
end
local function setup()
  local ok, err = xpcall(function()
    api.setup({ open = false, watch_debounce = 30 })
    vim.o.hidden = true
    vim.o.laststatus = 2
    vim.fn.writefile({ 'int main(void) {', '  return missing_symbol;', '}' }, root .. '/source file.c')
    vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/source file.c'))
    local source = vim.api.nvim_get_current_buf()
    local build =
      assert(api.run({ name = 'C build 100%', cmd = { 'cc', '-fsyntax-only', root .. '/source file.c' }, cwd = root }))
    stage('wait_build', function()
      return not active(build)
    end, function()
      check(api.get(build).status == 'failure', 'actual compiler failure')
      stage('list', function()
        return vim.bo.filetype == 'tasktools'
      end, function()
        local text = screen()
        check(text:find('failure') and text:find('C build 100%%'), 'rendered task list')
        check(vim.api.nvim_win_get_cursor(0)[1] == 3, 'task row selected')
        stage('output', function()
          return vim.bo.filetype == 'tasktoolsoutput'
        end, function()
          check(screen():find('missing_symbol'), 'rendered compiler output')
          local items = require('task_tools.parser').parse(api.output(build), root)
          for row, item in ipairs(items) do
            if item.valid == 1 then
              vim.api.nvim_win_set_cursor(0, { row, 0 })
              break
            end
          end
          stage('jump', function()
            return vim.api.nvim_get_current_buf() == source
          end, function()
            check(vim.api.nvim_win_get_cursor(0)[1] == 2, 'Enter jumps to compiler location')
            local terminal_options = {
              key = 'test',
              cwd = root,
              cmd = {
                'sh',
                '-c',
                'printf "READY> "; read a; printf "ANSWER:%s\n" "$a"; read b; stty size; read c; printf "DONE\n"',
              },
            }
            vim.keymap.set({ 'n', 't' }, '<F6>', function()
              api.terminal(terminal_options)
            end)
            local term = api.terminal(terminal_options)
            local job = api.get(term).job
            stage('terminal_ready', function()
              return screen():find('READY>') and vim.api.nvim_get_mode().mode == 't'
            end, function()
              stage('terminal_input', function()
                return table.concat(api.output(term)):find('ANSWER:hello from PTY')
                  and screen():find('ANSWER:hello from PTY')
              end, function()
                check(screen():find('ANSWER:hello from PTY'), 'typed terminal input rendered')
                stage('terminal_normal', function()
                  return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n'
                end, function()
                  stage('hide', function()
                    return #vim.fn.win_findbuf(api.get(term).buf) == 0
                  end, function()
                    check(active(term), 'hidden terminal keeps process alive')
                    stage('reopen', function()
                      return #vim.fn.win_findbuf(api.get(term).buf) > 0 and vim.api.nvim_get_mode().mode == 't'
                    end, function()
                      check(
                        api.get(term).job == job and screen():find('ANSWER:hello from PTY'),
                        'toggle reuses PTY and scrollback'
                      )
                      stage('resize', function()
                        return vim.o.columns == 72
                      end, function()
                        local rows, cols = vim.api.nvim_win_get_height(0), vim.api.nvim_win_get_width(0)
                        stage('size_input', function()
                          return table.concat(api.output(term), '\n'):find(rows .. ' ' .. cols)
                        end, function()
                          check(true, 'PTY receives resize')
                          stage('finish', function()
                            return not active(term) and screen():find('DONE')
                          end, function()
                            check(api.get(term).status == 'success' and screen():find('DONE'), 'terminal final output')
                            vim.cmd('stopinsert')
                            vim.api.nvim_set_current_win(vim.fn.bufwinid(source))
                            local watch = api.run({
                              name = 'save watcher',
                              cmd = { 'sh', '-c', 'printf watching; sleep 10' },
                              cwd = root,
                              watch = { '*.c' },
                            })
                            stage('save', function()
                              return api.list()[1].id ~= watch
                            end, function()
                              local rerun = api.list()[1].id
                              check(api.get(watch).status == 'stopped' and active(rerun), 'real write restarts watcher')
                              api.stop(rerun)
                              stage('wait_stop', function()
                                return not active(rerun)
                              end, function()
                                check(not api.get(rerun).watch_id, 'manual stop removes watch')
                                vim.fn.writefile(
                                  { ('PASS TUI: %d checks'):format(checks), screen() },
                                  root .. '/result'
                                )
                                vim.cmd('qa!')
                              end)
                            end)
                          end)
                        end)
                      end)
                    end)
                  end)
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end, debug.traceback)
  if not ok then
    vim.fn.writefile({ err }, root .. '/result')
    vim.cmd('cquit 1')
  end
end
-- Allow the user's normal startup handlers to finish before injecting the test.
vim.defer_fn(setup, 150)
