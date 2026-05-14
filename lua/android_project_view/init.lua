local scanner  = require 'android_project_view.scanner'
local tree_mod = require 'android_project_view.tree'
local renderer = require 'android_project_view.renderer'
local M        = {}

M.config = {
  side      = 'left',
  width     = 40,
  auto_open = false,
}

local _setup_done = false

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend('force', M.config, opts)
  end
  _setup_done = true
  if M.config.auto_open then
    vim.api.nvim_create_autocmd('VimEnter', {
      once     = true,
      callback = function()
        -- find_root starts from cwd when no file is open yet
        local root = scanner.find_root(vim.fn.getcwd())
        if root then
          local no_file = vim.fn.bufname() == ''
          M.open(true)
          if no_file and renderer.win_is_valid() then
            vim.api.nvim_set_current_win(renderer.state.win)
          end
        end
      end,
    })
  end
end

local function scan_and_render(silent)
  local root_dir = scanner.find_root()
  if not root_dir then
    if not silent then
      vim.notify('Android Project View: no Android project root found', vim.log.levels.WARN)
    end
    renderer.set_tree(nil)
    return
  end

  -- Preserve expanded state across refreshes
  local saved_expanded = {}
  if renderer.state.root then
    saved_expanded = tree_mod.collect_expanded_paths(renderer.state.root)
  end

  local root_node = scanner.build_tree(root_dir)

  -- Restore expanded state if refreshing
  if next(saved_expanded) ~= nil then
    tree_mod.restore_expanded(root_node, saved_expanded)
  end

  renderer.set_tree(root_node)
end

function M.open(silent)
  renderer.open(M.config)
  scan_and_render(silent)
end

function M.close()
  renderer.close()
end

function M.toggle()
  if renderer.win_is_valid() then
    M.close()
  else
    M.open()
  end
end

function M.refresh()
  if not renderer.win_is_valid() then
    return
  end
  scan_and_render()
end

return M
