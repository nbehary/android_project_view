# android-project-view.nvim

A Neovim plugin that replicates the **Android Studio "Android Project View"** sidebar — a tree that groups Android project files by logical role rather than raw filesystem layout.

Built with the assistance of [Claude](https://claude.ai) (Anthropic).

## What it looks like

```
▾ ⬡ myapp
  ▾ ⬡ app
    ▾ manifests
        AndroidManifest.xml
    ▾ java
      ▾ com
        ▾ example
          ▾ app
              MainActivity.kt
              MainViewModel.kt
    ▾ res
      ▾ layout
          activity_main.xml
      ▾ values
          strings.xml
          themes.xml
  ▾ Gradle Scripts
      build.gradle (Project: myapp)
      settings.gradle (Project: myapp)
      build.gradle (Module: app)
```

## Features

- Groups files by **Manifests**, **Java/Kotlin** (package tree), **Resources** (by type), and **Gradle Scripts**
- Supports **multi-module** projects; modules are discovered from `settings.gradle(.kts)`
- Source variants (`debug`, `test`, etc.) are merged into the package tree with a variant label suffix
- Expanded state is **preserved across refreshes**
- File icons via `nvim-web-devicons` (falls back to text alignment)
- Catppuccin-mocha highlight colors

## Requirements

- Neovim 0.9+
- An Android project with a `settings.gradle` or `settings.gradle.kts` at the root
- `nvim-web-devicons` (optional, for file icons)

## Installation

Install as a vim.pack plugin:

```sh
mkdir -p ~/.config/nvim/pack/github/start
git clone https://github.com/nbehary/android-project-view.nvim \
  ~/.config/nvim/pack/github/start/android-project-view.nvim
```

Then add setup and a keybind to your config (e.g. `after/plugin/plugin-configs.lua`):

```lua
pcall(function()
  require('android_project_view').setup()
  vim.keymap.set('n', '<leader>ap', '<cmd>AndroidProjectViewToggle<cr>',
    { desc = '[A]ndroid [P]roject view' })
end)
```

## Configuration

```lua
require('android_project_view').setup({
  side  = 'left',   -- 'left' or 'right'
  width = 40,
})
```

## Commands

| Command                        | Description              |
|-------------------------------|--------------------------|
| `:AndroidProjectView`         | Open the sidebar         |
| `:AndroidProjectViewClose`    | Close the sidebar        |
| `:AndroidProjectViewToggle`   | Toggle the sidebar       |
| `:AndroidProjectViewRefresh`  | Re-scan and re-render    |

## Keymaps (inside the sidebar)

| Key          | Action                              |
|-------------|--------------------------------------|
| `<CR>` / `o` | Open file, or toggle expand/collapse |
| `<Tab>` / `<Space>` | Toggle expand/collapse        |
| `r`          | Refresh (re-scan project)           |
| `R`          | Collapse all                        |
| `q`          | Close sidebar                       |
| `?`          | Toggle inline help                  |
