local M = {}
local api = vim.api

local DEFAULTS = {
  width = 45,   -- sidebar columns
  max = 1000,   -- max matches shown
  mouse = true, -- double click on a word searches it
  preview = { width = 90, height = 15 }, -- max size of the preview popup
  colors = {
    banner = '#74DBEF', -- title row background and preview border: dark -> light shades of it
    status = '#FFDE7D', -- "word · N matches" row background: 70% -> 100% of it
    icon = '#019833',   -- Neovim icon
    text = '#0b2a33',   -- text on both header rows
  },
}
local C = vim.deepcopy(DEFAULTS)
local S = { win = nil, buf = nil, prev = nil, pwin = nil, root = nil, items = {}, word = nil, job = 0, hl = nil }
local ns = api.nvim_create_namespace('neocont')
local nsb = api.nvim_create_namespace('neocont_banner')

local PRE = ' %4d  ' -- line number column in front of each match
local NAME = 'NeoCont'
local ICON = '\u{f36f}' -- nf-linux-neovim, needs a Nerd Font
local HINT = 'q close '
local function valid(w) return w and api.nvim_win_is_valid(w) end

local function lerp(a, b, t)
  local c = {}
  for i = 2, 6, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    c[#c + 1] = string.format('%02x', math.floor(x + (y - x) * t + 0.5))
  end
  return '#' .. table.concat(c)
end

local function set_lines(first, last, lines)
  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, first, last, false, lines)
  vim.bo[S.buf].modifiable = false
end

local function banner_shades() return lerp(C.colors.banner, '#000000', 0.45), lerp(C.colors.banner, '#ffffff', 0.4) end

-- preview border: diagonal gradient of the banner shades, dark top-left -> light bottom-right
local BORDER = {}
for i, ch in ipairs({ '╭', '─', '╮', '│', '╯', '─', '╰', '│' }) do
  BORDER[i] = { ch, 'NeoContEdge' .. ({ 1, 2, 3, 4, 5, 4, 3, 2 })[i] }
end

-- per-cell look of the header rows
local function look(kind)
  local ink = C.colors.text
  return ({
    icon = { fg = C.colors.icon, bold = true },
    name = { fg = ink, bold = true, italic = true },
    hint = { fg = ink, italic = true },
    word = { fg = ink, bold = true },
    bg = { fg = ink },
  })[kind]
end

-- replaces `row` with `cells` (one char each), background going from -> to across them
local function paint(row, cells, kind, from, to)
  set_lines(row, row + 1, { table.concat(cells) })
  api.nvim_buf_clear_namespace(S.buf, nsb, row, row + 1)
  local col = 0
  for i, c in ipairs(cells) do
    local bg = lerp(from, to, #cells > 1 and (i - 1) / (#cells - 1) or 0)
    local g = 'NeoContHead_' .. kind[i] .. bg:sub(2)
    api.nvim_set_hl(0, g, vim.tbl_extend('force', look(kind[i]), { bg = bg }))
    api.nvim_buf_set_extmark(S.buf, nsb, row, col, { end_col = col + #c, hl_group = g })
    col = col + #c
  end
end

local function blank(w)
  local cells, kind = {}, {}
  for i = 1, w do cells[i], kind[i] = ' ', 'bg' end
  return cells, kind
end

-- row 1: blue gradient, green Neovim icon and the name centered, close hint on the right
-- row 2: status gradient with "word · status"
local function banner()
  if not (S.buf and api.nvim_buf_is_valid(S.buf) and valid(S.win) and S.head) then return end
  local width = api.nvim_win_get_width(S.win)
  local w = width - (vim.fn.strdisplaywidth(ICON) - 1)
  local cells, kind = blank(w)
  local title = vim.fn.split(ICON .. ' ' .. NAME, [[\zs]])
  local s = math.max(0, math.floor((w - #title) / 2))
  for i, c in ipairs(title) do cells[s + i], kind[s + i] = c, i == 1 and 'icon' or 'name' end
  if w - #HINT > s + #title then
    for i = 1, #HINT do cells[w - #HINT + i], kind[w - #HINT + i] = HINT:sub(i, i), 'hint' end
  end
  paint(0, cells, kind, banner_shades())

  local word = vim.fn.split(' ' .. S.head[1], [[\zs]])
  local rest = vim.fn.split(' · ' .. S.head[2], [[\zs]])
  cells, kind = blank(math.max(width, #word + #rest))
  for i, c in ipairs(word) do cells[i], kind[i] = c, 'word' end
  for i, c in ipairs(rest) do cells[#word + i] = c end
  paint(1, cells, kind, lerp(C.colors.status, '#000000', 0.3), C.colors.status)
end

local function set_hl()
  for g, link in pairs({ NeoContWord = 'Search', NeoContFile = 'Directory', NeoContLnum = 'LineNr' }) do
    api.nvim_set_hl(0, g, { link = link, default = true })
  end
  local from, to = banner_shades()
  local bg = api.nvim_get_hl(0, { name = 'NormalFloat', link = false }).bg
  for i = 1, 5 do api.nvim_set_hl(0, 'NeoContEdge' .. i, { fg = lerp(from, to, (i - 1) / 4), bg = bg }) end
  banner()
end

local function path(it) return vim.fs.joinpath(S.root, it.file) end

local function close_preview()
  if valid(S.pwin) then api.nvim_win_close(S.pwin, true) end
  S.pwin = nil
end

local function jump()
  close_preview()
  local it = S.items[api.nvim_win_get_cursor(0)[1]]
  if not it then return end
  if not valid(S.prev) then
    vim.cmd('topleft vnew')
    S.prev = api.nvim_get_current_win()
    api.nvim_win_set_width(S.win, C.width)
  end
  api.nvim_set_current_win(S.prev)
  vim.cmd.edit(vim.fn.fnameescape(path(it)))
  api.nvim_win_set_cursor(0, { it.lnum, it.col })
  vim.cmd('normal! zz')
end

-- floating window left of the sidebar showing the match under the cursor in its file
function M.preview()
  close_preview()
  local it = valid(S.win) and S.items[api.nvim_win_get_cursor(S.win)[1]]
  if not it then return end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(path(it)))
  vim.bo[buf].modifiable = false
  -- highlight without setting 'filetype', so no FileType autocmds (LSP, linters...) run on the preview
  local ft = vim.filetype.match({ filename = it.file }) or ''
  if not pcall(vim.treesitter.start, buf, vim.treesitter.language.get_lang(ft) or ft) then vim.bo[buf].syntax = ft end
  api.nvim_buf_set_extmark(buf, ns, it.lnum - 1, it.col, { end_col = it.col + #S.word, hl_group = 'NeoContWord', strict = false })

  local h = math.max(3, math.min(C.preview.height, vim.o.lines - 6))
  local w = math.max(20, math.min(C.preview.width, vim.o.columns - C.width - 4))
  local row = api.nvim_win_call(S.win, vim.fn.winline) - 1 - math.floor(h / 2)
  S.pwin = api.nvim_open_win(buf, false, {
    relative = 'win', win = S.win, anchor = 'NE', col = -1,
    row = math.max(0, math.min(row, api.nvim_win_get_height(S.win) - h - 2)),
    width = w, height = h, style = 'minimal', border = BORDER, focusable = false,
    title = ' ' .. it.file .. ':' .. it.lnum .. ' ', title_pos = 'center',
  })
  vim.wo[S.pwin].number, vim.wo[S.pwin].cursorline = true, true
  api.nvim_win_set_cursor(S.pwin, { it.lnum, it.col })
  api.nvim_win_call(S.pwin, function() vim.cmd('normal! zz') end)
end

local function ensure()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then
    S.buf = api.nvim_create_buf(false, true)
    vim.bo[S.buf].bufhidden = 'hide'
    vim.bo[S.buf].filetype = 'neocont'
    vim.keymap.set('n', '<CR>', jump, { buffer = S.buf })
    vim.keymap.set('n', 'q', M.close, { buffer = S.buf })
    -- one click previews the match, double click opens it. Act on the release: jumping on the
    -- press leaves the release to start a visual selection in the file
    local armed = false
    vim.keymap.set('n', '<2-LeftMouse>', function()
      armed = true
      vim.schedule(close_preview) -- expr mappings can't close windows (textlock)
      return '<LeftMouse>'
    end, { buffer = S.buf, expr = true })
    for _, k in ipairs({ '<LeftRelease>', '<2-LeftRelease>' }) do
      vim.keymap.set('n', k, function()
        local double = armed
        armed = false
        vim.schedule(double and jump or M.preview)
      end, { buffer = S.buf })
    end
    api.nvim_create_autocmd('BufLeave', { buffer = S.buf, callback = close_preview })
  end
  if not valid(S.win) then
    S.win = api.nvim_open_win(S.buf, false, { split = 'right', win = -1, width = C.width })
    local wo = vim.wo[S.win]
    wo.number, wo.relativenumber, wo.list = false, false, false
    wo.signcolumn, wo.cursorline, wo.winfixwidth = 'no', true, true
    -- long lines wrap aligned under the text, past the line number column
    wo.wrap, wo.linebreak, wo.breakindent, wo.breakindentopt = true, true, true, 'list:-1'
    vim.bo[S.buf].formatlistpat = [[^\s*\d\+\s\+]]
  end
end

local function render(word, results, truncated, status)
  local lines, hls = { '', '' }, {} -- header rows, painted by banner()
  local items, last, files = {}, nil, 0
  for _, r in ipairs(results) do
    if r.file ~= last then
      last, files = r.file, files + 1
      lines[#lines + 1] = ' ' .. r.file
      hls[#hls + 1] = { #lines - 1, 0, -1, 'NeoContFile' }
    end
    local pre = PRE:format(r.lnum)
    lines[#lines + 1] = pre .. r.text
    items[#lines] = r
    hls[#hls + 1] = { #lines - 1, 0, #pre, 'NeoContLnum' }
    hls[#hls + 1] = { #lines - 1, #pre + r.hcol, #pre + r.hcol + #word, 'NeoContWord' }
  end
  status = status or #results == 0 and 'no matches'
      or string.format('%d%s %s in %d %s', #results, truncated and '+' or '', #results == 1 and 'match' or 'matches',
        files, files == 1 and 'file' or 'files')
  S.head = { word, status }

  S.items = items
  set_lines(0, -1, lines)
  api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    local len = #lines[h[1] + 1]
    api.nvim_buf_set_extmark(S.buf, ns, h[1], h[2], { end_col = h[3] == -1 and len or math.min(h[3], len), hl_group = h[4] })
  end
  banner()
  if valid(S.win) then api.nvim_win_set_cursor(S.win, { 2, 0 }) end
end

-- "file:lnum:text" lines from rg/grep -> results (rg/grep output is grouped by file).
-- col: 0-based byte offset of the word in the file line; text/hcol: the line without indentation or tabs, as shown
function M._parse(out, word)
  local res = {}
  local pat = '%f[%w_]' .. word:gsub('%p', '%%%0') .. '%f[^%w_]'
  for line in out:gmatch('[^\n]+') do
    local file, lnum, raw = line:match('^(.-):(%d+):(.*)$')
    if file then
      local text = raw:gsub('^%s+', ''):gsub('\t', ' ')
      local col, hcol = (raw:find(pat) or 1) - 1, (text:find(pat) or 1) - 1
      res[#res + 1] = { file = (file:gsub('^%./', '')), lnum = tonumber(lnum), col = col, hcol = hcol, text = text }
      if #res >= C.max then return res, true end
    end
  end
  return res, false
end

function M.search(word)
  if api.nvim_get_current_buf() ~= S.buf then S.prev = api.nvim_get_current_win() end
  ensure()
  close_preview()
  S.word = word
  S.job = S.job + 1
  local id = S.job
  render(word, {}, false, 'searching…')
  S.root = vim.fs.root(0, '.git') or vim.fn.getcwd()
  local cmd = vim.fn.executable('rg') == 1
      and { 'rg', '-n', '-H', '--no-heading', '--color=never', '-F', '-w', '--', word, '.' }
      or { 'grep', '-rnIHwF', '--exclude-dir=.git', '--', word, '.' }
  vim.system(cmd, { cwd = S.root, text = true }, function(r)
    vim.schedule(function()
      if id ~= S.job or not (S.buf and api.nvim_buf_is_valid(S.buf)) then return end
      render(word, M._parse(r.stdout or '', word))
    end)
  end)
end

local function highlight(word)
  if S.hl and valid(S.hl[1]) then pcall(vim.fn.matchdelete, S.hl[2], S.hl[1]) end
  local pat = '\\V\\<' .. vim.fn.escape(word, '\\') .. '\\>'
  S.hl = { api.nvim_get_current_win(), vim.fn.matchadd('NeoContWord', pat) }
end

-- inside the sidebar open the match, elsewhere search the word under the cursor
function M.lookup()
  if api.nvim_get_current_buf() == S.buf then return jump() end
  if vim.bo.buftype ~= '' then return end
  local word = vim.fn.expand('<cword>')
  if not word:match('[%w_]') then return end
  S.prev = api.nvim_get_current_win()
  highlight(word)
  if word == S.word and valid(S.win) then return end
  M.search(word)
end

function M.close()
  close_preview()
  if valid(S.win) then api.nvim_win_close(S.win, true) end
  S.win, S.word = nil, nil
end

function M.setup(opts)
  C = vim.tbl_deep_extend('force', C, opts or {})
  for k, v in pairs(C.colors) do
    if type(v) ~= 'string' or not v:match('^#%x%x%x%x%x%x$') then
      vim.notify(('NeoCont: colors.%s must be "#rrggbb", got %s; using the default'):format(k, vim.inspect(v)), vim.log.levels.WARN)
      C.colors[k] = DEFAULTS.colors[k]
    end
  end
  set_hl()
  local group = api.nvim_create_augroup('neocont', {})
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_hl })
  api.nvim_create_autocmd('WinResized', { group = group, callback = banner })
  if C.mouse then
    -- double click selects the word (Neovim default), then search it
    vim.keymap.set('n', '<2-LeftMouse>', function()
      vim.schedule(M.lookup)
      return '<2-LeftMouse>'
    end, { expr = true, desc = 'NeoCont: search the word' })
  else -- setup() may run twice (plugin/ file, then the user's opts)
    pcall(vim.keymap.del, 'n', '<2-LeftMouse>')
  end
  api.nvim_create_user_command('NeoCont', function(a)
    if a.args ~= '' then return M.search(a.args) end
    if valid(S.win) then return M.close() end
    M.lookup()
  end, { nargs = '?', desc = 'NeoCont: search a word (no argument: toggle with the word under the cursor)' })
  api.nvim_create_user_command('NeoContClose', M.close, { desc = 'NeoCont: close the sidebar' })
end

M._state = S
return M
