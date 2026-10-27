-- nvim --headless -u NONE --cmd 'set rtp+=.' -l tests/smoke.lua
vim.opt.rtp:prepend('.')
local n = require('neocont')
n.setup()

local res, cut = n._parse('./a.lua:3:local foo = 1\nb/c.lua:10:\t\treturn foobar, foo\n', 'foo')
assert(#res == 2 and not cut)
assert(res[1].file == 'a.lua' and res[1].lnum == 3 and res[1].col == 6)
-- indentation stripped for display, highlight skips "foobar", col still points into the real line
assert(res[2].file == 'b/c.lua' and res[2].text == 'return foobar, foo')
assert(res[2].hcol == 15 and res[2].col == 17, res[2].hcol .. ' ' .. res[2].col)

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. '/sub', 'p')
vim.fn.writefile({ 'local foo = 1', 'local foobar = 2' }, dir .. '/a.lua')
vim.fn.writefile({ 'print(foo)' }, dir .. '/sub/b.lua')
vim.cmd.cd(dir)
vim.cmd.edit('a.lua')
local src = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 1, 7 })
n.lookup()

local S = n._state
assert(vim.wait(3000, function() return vim.tbl_count(S.items) == 2 end), 'expected 2 matches (foobar excluded)')
local lines = vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)
assert(lines[2]:find('foo') and lines[2]:find('2 matches in 2 files'), lines[2])
assert(lines[1]:find('NeoCont') and lines[1]:find('q close'))
assert(vim.fn.strdisplaywidth(lines[1]) == vim.api.nvim_win_get_width(S.win), 'banner must fill the width without wrapping')

-- preview, then open the sub/b.lua match from the sidebar
vim.api.nvim_set_current_win(S.win)
for l, it in pairs(S.items) do
  if it.file == 'sub/b.lua' then vim.api.nvim_win_set_cursor(0, { l, 0 }) end
end
n.preview()
assert(S.pwin and vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(S.pwin), 0, -1, false)[1] == 'print(foo)')
assert(vim.api.nvim_win_get_cursor(S.pwin)[1] == 1)
n.lookup()
assert(S.pwin == nil, 'opening a match closes the preview')
assert(vim.api.nvim_get_current_win() == src)
assert(vim.fn.expand('%:t') == 'b.lua' and vim.api.nvim_win_get_cursor(0)[2] == 6)

n.close()
assert(#vim.api.nvim_list_wins() == 1)
print('ok')
