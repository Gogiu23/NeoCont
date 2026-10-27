-- Drives NeoCont inside a real terminal and takes screenshots. Run via assets/capture/run.sh.
local root = vim.fn.getcwd()
local out = root .. '/assets/'
local api = vim.api
-- Load this checkout's code even if a plugin manager installed another copy of NeoCont
local n = dofile(root .. '/lua/neocont/init.lua')
package.loaded.neocont = n
n.setup()
local S = n._state

local function winid()
  return vim.trim(vim.fn.system({ 'swift', root .. '/assets/capture/winid.swift', 'NeoContDemo' }))
end

local function shot(name)
  vim.system({ 'screencapture', '-o', '-x', '-l', winid(), out .. name })
end

-- the pointer isn't captured, so a caption at the bottom says what the mouse does
local cap
local function caption(text)
  if cap and api.nvim_win_is_valid(cap) then api.nvim_win_close(cap, true) end
  if not text then return end
  local buf = api.nvim_create_buf(false, true)
  local line = ' \u{f037d}  ' .. text .. ' ' -- nf-md-mouse
  local w = vim.fn.strdisplaywidth(line)
  api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  cap = api.nvim_open_win(buf, false, {
    relative = 'editor', row = vim.o.lines - 5, col = math.floor((vim.o.columns - w) / 2),
    width = w, height = 1, style = 'minimal', border = 'rounded', focusable = false, zindex = 300,
  })
  vim.wo[cap].winhighlight = 'Normal:NeoContDemoCap,FloatBorder:NeoContDemoCap'
end
api.nvim_set_hl(0, 'NeoContDemoCap', { fg = '#0b2a33', bg = '#FFDE7D', bold = true })

-- screen position (0-based, for nvim_input_mouse) of byte `col` (1-based) of line `lnum` in `win`
local function at(win, lnum, col)
  local p = vim.fn.screenpos(win, lnum, col)
  return p.row - 1, p.col - 1
end

local function click(times, row, col)
  for _ = 1, times do
    api.nvim_input_mouse('left', 'press', '', 0, row, col)
    api.nvim_input_mouse('left', 'release', '', 0, row, col)
  end
end

-- sidebar line of the k-th match
local function match_line(k)
  local ls = vim.tbl_keys(S.items)
  table.sort(ls)
  return ls[math.min(k, #ls)]
end

-- GIF mode: grabs window frames back to back and writes an ffmpeg concat list with each frame's real duration.
local frames, recording = os.getenv('NEOCONT_FRAMES'), false
local function record()
  local id, list = winid(), {}
  recording = true
  local function grab(i, t)
    local f = ('%s/%04d.png'):format(frames, i)
    vim.system({ 'screencapture', '-o', '-x', '-l', id, f }, {}, function()
      local now = vim.uv.hrtime()
      if t then list[#list].d = (now - t) / 1e9 end
      list[#list + 1] = { f = f }
      if recording then grab(i + 1, now) end
    end)
  end
  grab(1)
  return function()
    recording = false
    local lines = {}
    for _, e in ipairs(list) do
      lines[#lines + 1] = ("file '%s'"):format(e.f)
      lines[#lines + 1] = ('duration %.3f'):format(e.d or 1)
    end
    lines[#lines + 1] = ("file '%s'"):format(list[#list].f) -- concat demuxer ignores the last duration otherwise
    vim.fn.writefile(lines, frames .. '/list.txt')
  end
end

vim.cmd.edit('lua/neocont/init.lua')
vim.fn.search('^local function valid')
vim.cmd('normal! zt')
local src = api.nvim_get_current_win()
local lnum = vim.fn.line('.')
local wcol = vim.fn.getline('.'):find('valid')

local stop
local steps = {
  function() if frames then stop = record() end end,
  function() caption('double click a word') end,
  function() click(2, at(src, lnum, wcol + 1)) end,
  function() if not frames then shot('sidebar.png') end end,
  function() caption('click a match: preview') end,
  function() click(1, at(S.win, match_line(4), 3)) end,
  function() if not frames then shot('preview.png') end end,
  function() click(1, at(S.win, match_line(7), 3)) end,
  function() caption('double click: open the file') end,
  function() click(2, at(S.win, match_line(7), 3)) end,
  function() if not frames then shot('open.png') end end,
  function() caption() end,
  function() if stop then stop() end end,
  function() vim.cmd('qa!') end,
}

local function run(i)
  if not steps[i] then return end
  steps[i]()
  vim.defer_fn(function() run(i + 1) end, frames and 1500 or 1200)
end

vim.defer_fn(function() run(1) end, 2000)
