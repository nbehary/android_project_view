-- Auto-sourced by vim.pack. Registers user commands; actual setup is called
-- by the user's plugin-configs.lua via require('android_project_view').setup().

vim.api.nvim_create_user_command('AndroidProjectView', function()
  require('android_project_view').open()
end, { desc = 'Open Android Project View' })

vim.api.nvim_create_user_command('AndroidProjectViewClose', function()
  require('android_project_view').close()
end, { desc = 'Close Android Project View' })

vim.api.nvim_create_user_command('AndroidProjectViewToggle', function()
  require('android_project_view').toggle()
end, { desc = 'Toggle Android Project View' })

vim.api.nvim_create_user_command('AndroidProjectViewRefresh', function()
  require('android_project_view').refresh()
end, { desc = 'Refresh Android Project View' })
