local tree = require 'android_project_view.tree'
local NT   = tree.NodeType
local M    = {}

-- ─── Highlight groups ────────────────────────────────────────────────────────

local HL = {
  ROOT     = 'AndroidPVRoot',
  MODULE   = 'AndroidPVModule',
  CATEGORY = 'AndroidPVCategory',
  PACKAGE  = 'AndroidPVPackage',
  RES_TYPE = 'AndroidPVResType',
  FILE     = 'AndroidPVFile',
  ICON     = 'AndroidPVIcon',
  HELP     = 'AndroidPVHelp',
}

local function setup_highlights()
  vim.api.nvim_set_hl(0, HL.ROOT,     { bold = true })
  vim.api.nvim_set_hl(0, HL.MODULE,   { fg = '#a6e3a1' })
  vim.api.nvim_set_hl(0, HL.CATEGORY, { fg = '#cba6f7' })
  vim.api.nvim_set_hl(0, HL.PACKAGE,  { fg = '#89dceb' })
  vim.api.nvim_set_hl(0, HL.RES_TYPE, { fg = '#f9e2af' })
  vim.api.nvim_set_hl(0, HL.FILE,     { link = 'Normal' })
  vim.api.nvim_set_hl(0, HL.ICON,     { fg = '#6c7086' })
  vim.api.nvim_set_hl(0, HL.HELP,     { fg = '#585b70', italic = true })
end

-- ─── Icons ───────────────────────────────────────────────────────────────────

local ICON = {
  EXPANDED  = '▾ ',
  COLLAPSED = '▸ ',
  FILE      = '  ',  -- two spaces indent for alignment with folder icons
  MODULE    = '⬡ ',
}

local function node_icon(node)
  if node.type == NT.FILE then
    -- Try nvim-web-devicons
    local ok, devicons = pcall(require, 'nvim-web-devicons')
    if ok then
      local ext = node.path and node.path:match '%.([^%.]+)$' or ''
      local icon, _ = devicons.get_icon(node.name, ext, { default = true })
      if icon then
        return icon .. ' '
      end
    end
    return ICON.FILE
  end
  if node.type == NT.MODULE then
    return node.expanded and (ICON.EXPANDED) or (ICON.COLLAPSED)
  end
  return node.expanded and ICON.EXPANDED or ICON.COLLAPSED
end

local function node_hl(node)
  local map = {
    [NT.ROOT]     = HL.ROOT,
    [NT.MODULE]   = HL.MODULE,
    [NT.CATEGORY] = HL.CATEGORY,
    [NT.PACKAGE]  = HL.PACKAGE,
    [NT.RES_TYPE] = HL.RES_TYPE,
    [NT.FILE]     = HL.FILE,
  }
  return map[node.type] or HL.FILE
end

-- ─── State ───────────────────────────────────────────────────────────────────

local state = {
  buf          = nil,
  win          = nil,
  root         = nil,
  display_list = {},   -- { node = <TreeNode>, depth = <int> }
  show_help    = false,
}

M.state = state

-- ─── Buffer / window helpers ─────────────────────────────────────────────────

local HELP_LINES = {
  '  <CR>/<o>  open file / toggle expand',
  '  <Tab>     toggle expand',
  '  <r>       refresh',
  '  <R>       collapse all',
  '  <q>       close',
  '  <?>       toggle this help',
  '',
}

local function buf_is_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

function M.win_is_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('buftype',    'nofile',           { buf = buf })
  vim.api.nvim_set_option_value('bufhidden',  'hide',             { buf = buf })
  vim.api.nvim_set_option_value('swapfile',   false,              { buf = buf })
  vim.api.nvim_set_option_value('filetype',   'AndroidProjectView', { buf = buf })
  vim.api.nvim_set_option_value('modifiable', false,              { buf = buf })
  vim.bo[buf].buflisted = false
  return buf
end

local function make_win(buf, cfg)
  local side = (cfg.side == 'right') and 'botright' or 'topleft'
  vim.cmd(side .. ' vertical ' .. cfg.width .. ' split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_option_value('winfixwidth',  true,  { win = win })
  vim.api.nvim_set_option_value('number',       false, { win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win })
  vim.api.nvim_set_option_value('wrap',         false, { win = win })
  vim.api.nvim_set_option_value('spell',        false, { win = win })
  vim.api.nvim_set_option_value('signcolumn',   'no',  { win = win })
  vim.api.nvim_set_option_value('foldcolumn',   '0',   { win = win })
  vim.api.nvim_set_option_value('cursorline',   true,  { win = win })
  return win
end

-- ─── Rendering ───────────────────────────────────────────────────────────────

local INDENT_UNIT = '  '

local function build_display_list(node, depth, list)
  table.insert(list, { node = node, depth = depth })
  if node.expanded then
    for _, child in ipairs(node.children) do
      build_display_list(child, depth + 1, list)
    end
  end
end

function M.render()
  if not buf_is_valid() then
    return
  end

  state.display_list = {}
  if state.root then
    build_display_list(state.root, 0, state.display_list)
  end

  local lines = {}
  local ns = vim.api.nvim_create_namespace 'AndroidProjectView'

  -- Help header
  if state.show_help then
    for _, h in ipairs(HELP_LINES) do
      table.insert(lines, h)
    end
  end

  local display_offset = #lines

  for _, entry in ipairs(state.display_list) do
    local node  = entry.node
    local depth = entry.depth
    local indent = INDENT_UNIT:rep(depth)
    local icon   = node_icon(node)
    table.insert(lines, indent .. icon .. node.name)
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.buf })

  -- Apply highlights via extmarks
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  if state.show_help then
    for i = 0, display_offset - 1 do
      vim.api.nvim_buf_add_highlight(state.buf, ns, HL.HELP, i, 0, -1)
    end
  end

  for i, entry in ipairs(state.display_list) do
    local lnum    = display_offset + i - 1
    local node    = entry.node
    local depth   = entry.depth
    local indent  = INDENT_UNIT:rep(depth)
    local hl      = node_hl(node)
    -- Highlight just the name portion (after indent + icon)
    local icon    = node_icon(node)
    local name_start = #indent + #icon
    vim.api.nvim_buf_add_highlight(state.buf, ns, HL.ICON, lnum, #indent, name_start)
    vim.api.nvim_buf_add_highlight(state.buf, ns, hl, lnum, name_start, -1)
  end
end

-- ─── Interaction helpers ──────────────────────────────────────────────────────

local function display_offset()
  return state.show_help and #HELP_LINES or 0
end

local function node_at_cursor()
  if not M.win_is_valid() then
    return nil
  end
  local row  = vim.api.nvim_win_get_cursor(state.win)[1]
  local idx  = row - display_offset()
  if idx < 1 or idx > #state.display_list then
    return nil
  end
  return state.display_list[idx].node
end

local function open_file(node)
  if not node or node.type ~= NT.FILE or not node.path then
    return
  end
  -- Switch to the previous window (or a non-APV split)
  local prev = vim.fn.winnr '#'
  if prev > 0 then
    vim.cmd(prev .. 'wincmd w')
  else
    vim.cmd 'wincmd p'
  end
  -- If we ended up back in the APV window, open a new split
  if vim.api.nvim_get_current_win() == state.win then
    vim.cmd 'wincmd l'
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(node.path))
end

local function toggle_expand(node)
  if not node then
    return
  end
  if node.type == NT.FILE then
    open_file(node)
    return
  end
  node.expanded = not node.expanded
  M.render()
end

local function collapse_all(node)
  node = node or state.root
  if not node then
    return
  end
  if node.type ~= NT.ROOT then
    node.expanded = false
  end
  for _, child in ipairs(node.children) do
    collapse_all(child)
  end
end

-- ─── Buffer keymaps ──────────────────────────────────────────────────────────

local function set_keymaps(buf)
  local opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  local function map(key, fn, desc)
    vim.keymap.set('n', key, fn, vim.tbl_extend('force', opts, { desc = desc }))
  end

  map('<CR>', function()
    local node = node_at_cursor()
    if not node then return end
    if node.type == NT.FILE then
      open_file(node)
    else
      toggle_expand(node)
    end
  end, 'Open file / toggle expand')

  map('o', function()
    local node = node_at_cursor()
    if not node then return end
    if node.type == NT.FILE then
      open_file(node)
    else
      toggle_expand(node)
    end
  end, 'Open file / toggle expand')

  map('<Tab>', function()
    toggle_expand(node_at_cursor())
  end, 'Toggle expand')

  map('<Space>', function()
    toggle_expand(node_at_cursor())
  end, 'Toggle expand')

  map('q', function()
    require('android_project_view').close()
  end, 'Close Android Project View')

  map('r', function()
    require('android_project_view').refresh()
  end, 'Refresh')

  map('R', function()
    collapse_all()
    if state.root then state.root.expanded = true end
    M.render()
  end, 'Collapse all')

  map('?', function()
    state.show_help = not state.show_help
    M.render()
  end, 'Toggle help')
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function M.open(cfg)
  setup_highlights()

  if not buf_is_valid() then
    state.buf = make_buf()
    set_keymaps(state.buf)
  end

  if not M.win_is_valid() then
    local prev_win = vim.api.nvim_get_current_win()
    state.win = make_win(state.buf, cfg)
    vim.api.nvim_set_current_win(prev_win)
  end
end

function M.close()
  if M.win_is_valid() then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

function M.set_tree(root_node)
  state.root = root_node
  M.render()
end

return M
