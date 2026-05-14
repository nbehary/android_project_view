# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Neovim plugin (`android-project-view.nvim`) that replicates the Android Studio "Android Project View" sidebar — a tree that groups Android project files by logical role (Manifests, Java/Kotlin sources, Resources, Gradle Scripts) rather than raw filesystem layout. It is installed as a vim.pack plugin alongside the user's Neovim setup.

## Installation location

The plugin lives at `~/.config/nvim/pack/github/start/android-project-view.nvim/`. Integration (setup call + `<leader>ap` keybind) is added to `~/.config/nvim/after/plugin/plugin-configs.lua`.

## No build step or tests

This is pure Lua; there is no build command, test runner, or CI. Manual verification is done by opening an Android project in Neovim and exercising the sidebar (see PLAN.md §Verification).

## Architecture

Data flow: `scanner` builds a tree → `init` wires state and calls `renderer` → `renderer` owns the buffer/window and renders from the tree.

### `lua/android_project_view/tree.lua`
Defines `NodeType` constants (`ROOT`, `MODULE`, `CATEGORY`, `PACKAGE`, `RES_TYPE`, `FILE`) and helpers for constructing/traversing the node tree. Each node: `{ type, name, path, children, expanded, parent }`. Virtual nodes (CATEGORY, PACKAGE) have `path = nil`. `collect_expanded_paths` / `restore_expanded` preserve expand state across refreshes by keying on `path` for file nodes and `type:name` for virtual nodes.

### `lua/android_project_view/scanner.lua`
Builds the virtual tree from disk:
- **Root detection**: walks upward from the current file's directory looking for `gradlew`, `settings.gradle`, or `settings.gradle.kts`.
- **Module discovery**: parses `settings.gradle(.kts)` for `include ':mod'` / `include(":mod")` lines; falls back to globbing for `*/build.gradle*`.
- **Sources**: two-stage glob — first finds `src/<variant>` dirs, then recurses within `src/<variant>/java/` and `src/<variant>/kotlin/`. Strips the lang-dir prefix, splits remaining path into PACKAGE nodes, adds FILE leaf. Non-`main` variants get a `(variant)` suffix on the filename.
- **Resources**: globs `src/*/res/*` dirs, groups files by res-type name, sorts using `RES_ORDER` canonical list.
- **Gradle Scripts**: collects well-known filenames from the project root and per-module build files, labelled `(Project: name)` / `(Module: name)`.

### `lua/android_project_view/renderer.lua`
Owns all Neovim buffer/window state in a module-local `state` table (also exposed as `M.state` for `init.lua` to read `state.root`). `render()` walks the tree into a flat `display_list`, writes lines to the scratch buffer, and applies extmark highlights. Icons use text symbols (`▾`/`▸`/`⬡`); `nvim-web-devicons` is used for file icons when available. Highlight groups are catppuccin-mocha colors hardcoded via `nvim_set_hl`. Buffer keymaps: `<CR>`/`o` open file or toggle expand, `<Tab>`/`<Space>` toggle expand, `q` close, `r` refresh, `R` collapse all, `?` toggle help.

### `lua/android_project_view/init.lua`
Public API (`setup`, `open`, `close`, `toggle`, `refresh`). `scan_and_render` orchestrates: detect root → save expanded state → `scanner.build_tree` → restore expanded state → `renderer.set_tree`. Config defaults: `side = 'left'`, `width = 40`.

### `plugin/android_project_view.lua`
Auto-sourced by vim.pack. Registers `:AndroidProjectView`, `:AndroidProjectViewClose`, `:AndroidProjectViewToggle`, `:AndroidProjectViewRefresh` user commands.

## Key design constraints

- **No path for virtual nodes**: CATEGORY and PACKAGE nodes have `path = nil`; only FILE nodes have paths. Code that opens files must guard `node.type == NT.FILE and node.path`.
- **Expanded state keying**: virtual nodes use `type:name` as a key — this means two PACKAGE nodes with the same name at different depths will both be restored if either was expanded. Fine for the current use case.
- **Empty category pruning**: `build_tree` removes Java, Res, and Gradle Scripts categories from the tree if they have no children (`table.remove(mod_node.children)` after adding the category as the last child).
- **Renderer `state` is module-local but exposed**: `init.lua` reads `renderer.state.root` to check if a prior tree exists before refresh. Don't restructure this without updating both files.
