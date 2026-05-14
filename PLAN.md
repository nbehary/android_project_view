# Plan: android-project-view.nvim

## Context

The goal is a Neovim plugin that replicates the **Android Studio "Android Project View"** — a sidebar tree that shows Android project files grouped by logical role (Manifests, Java/Kotlin sources, Resources, Gradle Scripts) rather than raw filesystem layout. This is distinct from NvimTree, which mirrors the directory tree 1:1. The plugin will live as a standalone vim.pack plugin alongside the existing setup.

The existing Android tooling (DAP, JDTLS, kotlin.lua, `lua/android/`) provides strong patterns to follow. The plugin augments them by giving an Android-aware navigation panel.

---

## File Structure

```
~/.config/nvim/pack/github/start/android-project-view.nvim/
├── plugin/
│   └── android_project_view.lua   # Auto-sourced: registers :AndroidProjectView* commands
└── lua/
    └── android_project_view/
        ├── init.lua               # Public API: setup(), open(), close(), toggle(), refresh()
        ├── scanner.lua            # Filesystem scan → virtual tree data
        ├── tree.lua               # TreeNode types and builder utilities
        └── renderer.lua           # Buffer rendering, keymaps, highlight groups
```

Integration file to modify:
- `~/.config/nvim/after/plugin/plugin-configs.lua` — add setup call and `<leader>ap` keybind

---

## Node Types (tree.lua)

```lua
local NodeType = {
  ROOT     = "root",      -- Project root (shows project name)
  MODULE   = "module",    -- Android module (app, core, feature-*)
  CATEGORY = "category",  -- Virtual group: Manifests | Java | Res | Gradle Scripts
  PACKAGE  = "package",   -- Java/Kotlin package hierarchy (virtual, no path)
  RES_TYPE = "res_type",  -- drawable | layout | values | mipmap | raw | menu
  FILE     = "file",      -- Actual file on disk (has .path)
}
```

Each node:
```lua
{
  type      = NodeType.*,
  name      = "display name",
  path      = "/abs/path" or nil,  -- nil for virtual nodes
  children  = {},
  expanded  = false,                -- toggled by user
  parent    = <node ref>,
}
```

---

## Scanner Logic (scanner.lua)

### 1. Find project root
```lua
vim.fs.find({ 'gradlew', 'settings.gradle', 'settings.gradle.kts' }, {
  upward = true,
  path = vim.fn.expand('%:p:h'),
})
```

### 2. Find modules
Parse `settings.gradle(.kts)` for lines matching:
- Groovy DSL: `include ':app'`, `include ':core'`
- Kotlin DSL: `include(":app")`, `include(":core")`

Map module name (`:app` → `app`) to `<root>/app/` directory.

### 3. Per-module scanning

**Manifests**: `vim.fn.glob(mod .. '/src/*/AndroidManifest.xml', false, true)`

**Sources** (build package tree):
```lua
local java_files  = vim.fn.glob(mod .. '/src/*/java/**/*.java', false, true)
local kotlin_files = vim.fn.glob(mod .. '/src/*/kotlin/**/*.kt', false, true)
```
Strip the `src/<variant>/java/` prefix, split remaining path by `/`, build PACKAGE nodes for each component, FILE node as leaf. Files from `src/main/`, `src/test/`, `src/debug/` are merged into the same package tree (source variant inferred from path and shown as a label suffix if non-main).

**Resources**:
```lua
vim.fn.glob(mod .. '/src/*/res/*', false, true)  -- returns res-type dirs
```
Group files by res-type dir name (drawable, layout, values, mipmap, etc.).

### 4. Gradle scripts
Collect from:
- `<root>/build.gradle(.kts)`
- `<root>/settings.gradle(.kts)`
- `<root>/gradle.properties`
- `<root>/gradle/wrapper/gradle-wrapper.properties`
- `<root>/<module>/build.gradle(.kts)` for each module

Show with labels: `build.gradle (Project: myapp)`, `build.gradle (Module: app)`, etc.

---

## Renderer (renderer.lua)

### Internal state
```lua
local state = {
  buf         = nil,   -- scratch buffer handle
  win         = nil,   -- sidebar window handle
  root        = nil,   -- root TreeNode
  display_list = {},   -- { node, depth } entries, one per rendered line
}
```

### Rendering
1. Traverse tree; add each visible node (root + expanded nodes' children) to `display_list`.
2. Build a `lines` table (one string per display_list entry): `indent + icon + name`.
3. Set buffer with `vim.api.nvim_buf_set_lines`.
4. Apply highlight extmarks per line based on node type.

### Icons (text symbols, no emoji — plays well with terminals)
```
▾ / ▸   expanded / collapsed folder/category
  (nvim-web-devicons for file icons; fallback to space)
  Module: ⬡   Category: use text label   Package: ·
```

### Highlight groups
```
AndroidPVRoot     – bold
AndroidPVModule   – #a6e3a1 (green)
AndroidPVCategory – #cba6f7 (mauve)
AndroidPVPackage  – #89dceb (sky)
AndroidPVResType  – #f9e2af (yellow)
AndroidPVFile     – normal fg
```
Linked to catppuccin-mocha colors via `vim.api.nvim_set_hl`.

### Buffer-local keymaps
| Key       | Action                                               |
|-----------|------------------------------------------------------|
| `<CR>`    | FILE → open in previous win; else toggle expand      |
| `o`       | Same as `<CR>`                                       |
| `<Tab>`   | Toggle expand/collapse on any node                   |
| `<Space>` | Same as `<Tab>`                                      |
| `q`       | Close window                                         |
| `r`       | Refresh (re-scan, preserve expanded state by path)   |
| `?`       | Toggle inline help at buffer top                     |
| `R`       | Collapse all (reset all expanded = false)            |

---

## Public API (init.lua)

```lua
local M = {}

M.config = {
  side  = "left",    -- sidebar split direction
  width = 40,
}

function M.setup(opts) ... end  -- merge opts, no-op if called again
function M.open()    ... end    -- create split + buffer if not open
function M.close()   ... end    -- close window (keep buffer)
function M.toggle()  ... end    -- open if closed, close if open
function M.refresh() ... end    -- re-scan project, re-render
```

---

## plugin/ Auto-Sourced Commands

```lua
-- plugin/android_project_view.lua
vim.api.nvim_create_user_command('AndroidProjectView',       function() require('android_project_view').open()    end, {})
vim.api.nvim_create_user_command('AndroidProjectViewClose',  function() require('android_project_view').close()   end, {})
vim.api.nvim_create_user_command('AndroidProjectViewToggle', function() require('android_project_view').toggle()  end, {})
vim.api.nvim_create_user_command('AndroidProjectViewRefresh',function() require('android_project_view').refresh() end, {})
```

---

## Integration: plugin-configs.lua

Add inside the `VimEnter` callback alongside the existing NvimTree and Android setup blocks:

```lua
-- Android Project View
pcall(function()
  require('android_project_view').setup()
  vim.keymap.set('n', '<leader>ap', '<cmd>AndroidProjectViewToggle<cr>', { desc = '[A]ndroid [P]roject view' })
end)
```

---

## Implementation Order

1. **tree.lua** — node type constants + `make_node()` helper
2. **scanner.lua** — root detection, module discovery, manifest/source/res/gradle scanning, `build_tree()`
3. **renderer.lua** — buffer creation, `render()` (display list + lines + highlights), keymaps, `open_file()`
4. **init.lua** — state wiring, `setup/open/close/toggle/refresh`
5. **plugin/android_project_view.lua** — user commands
6. **plugin-configs.lua** — setup call + keybind

---

## Verification

1. Open an Android project (e.g., the one used with existing `lua/android/` tooling).
2. Press `<leader>ap` — sidebar should open showing project name, modules, categories.
3. Expand a module → Manifests / Java / Res / Gradle Scripts appear.
4. Expand Java → package hierarchy (e.g., `com` → `example` → `app` → `MainActivity.kt`).
5. Press `<CR>` on a file → opens in the main window.
6. Press `r` → refreshes without losing expanded state.
7. Press `q` → closes sidebar; `<leader>ap` re-opens at same state.
8. Test with a multi-module project: each module is a top-level collapsible node.
9. Verify Gradle Scripts section lists build/settings files with module labels.
