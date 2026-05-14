local tree = require 'android_project_view.tree'
local NT   = tree.NodeType
local M    = {}

-- ─── Root detection ──────────────────────────────────────────────────────────

function M.find_root(start_path)
  start_path = start_path or vim.fn.expand '%:p:h'
  local markers = { 'gradlew', 'settings.gradle', 'settings.gradle.kts' }
  local matches = vim.fs.find(markers, { upward = true, path = start_path, limit = 1 })
  if not matches or #matches == 0 then
    return nil
  end
  return vim.fn.fnamemodify(matches[1], ':h')
end

-- ─── Module discovery ────────────────────────────────────────────────────────

local function parse_modules_from_settings(settings_path)
  local lines = vim.fn.readfile(settings_path)
  local modules = {}
  for _, line in ipairs(lines) do
    -- Groovy:  include ':app', ':core'  or  include ':app'
    -- Kotlin:  include(":app")          or  include(":app", ":core")
    for mod in line:gmatch '["\'](:?[%w_%-]+)["\']' do
      -- Accept :app or app style
      local name = mod:match '^:?(.+)$'
      if name then
        table.insert(modules, name)
      end
    end
  end
  return modules
end

function M.find_modules(root)
  -- Try settings file first for explicit list
  for _, fname in ipairs { 'settings.gradle.kts', 'settings.gradle' } do
    local settings = root .. '/' .. fname
    if vim.fn.filereadable(settings) == 1 then
      local names = parse_modules_from_settings(settings)
      if #names > 0 then
        -- Filter to names that have build.gradle or build.gradle.kts
        local valid = {}
        for _, name in ipairs(names) do
          -- Support nested modules: feature:login -> feature/login
          local dir = root .. '/' .. name:gsub(':', '/')
          if vim.fn.isdirectory(dir) == 1 then
            table.insert(valid, { name = name, dir = dir })
          end
        end
        if #valid > 0 then
          return valid
        end
      end
    end
  end

  -- Fallback: any direct subdir with a build file
  local result = {}
  local subdirs = vim.fn.glob(root .. '/*/build.gradle*', false, true)
  for _, path in ipairs(subdirs) do
    local dir  = vim.fn.fnamemodify(path, ':h')
    local name = vim.fn.fnamemodify(dir, ':t')
    table.insert(result, { name = name, dir = dir })
  end
  return result
end

-- ─── Manifest scanning ───────────────────────────────────────────────────────

function M.scan_manifests(module_dir)
  return vim.fn.glob(module_dir .. '/src/*/AndroidManifest.xml', false, true)
end

-- ─── Source scanning ─────────────────────────────────────────────────────────

function M.scan_sources(module_dir, java_cat_node)
  local seen = {}

  -- Stage 1: glob for src/<variant> dirs — single-level, always reliable
  local variant_dirs = vim.fn.glob(module_dir .. '/src/*', false, true)

  for _, variant_dir in ipairs(variant_dirs) do
    if vim.fn.isdirectory(variant_dir) == 1 then
      local variant = vim.fn.fnamemodify(variant_dir, ':t')

      for _, lang in ipairs { 'java', 'kotlin' } do
        local lang_dir = variant_dir .. '/' .. lang
        if vim.fn.isdirectory(lang_dir) == 1 then
          -- Stage 2: recurse within the known lang_dir (single ** from a fixed root)
          local files = vim.fn.glob(lang_dir .. '/**/*.java', false, true)
          vim.list_extend(files, vim.fn.glob(lang_dir .. '/**/*.kt', false, true))

          for _, file_path in ipairs(files) do
            if not seen[file_path] then
              seen[file_path] = true
              -- Relative path from lang_dir: strip "lang_dir/"
              local rel   = file_path:sub(#lang_dir + 2)
              local parts = vim.split(rel, '/', { plain = true })
              local fname = table.remove(parts) -- last element is the filename

              local display = fname
              if variant ~= 'main' then
                display = display .. '  (' .. variant .. ')'
              end

              -- Walk/create PACKAGE nodes for each path component
              local node = java_cat_node
              for _, part in ipairs(parts) do
                local existing = tree.find_child(node, part)
                if not existing then
                  existing = tree.add_child_sorted(node, tree.make_node(NT.PACKAGE, part, nil))
                end
                node = existing
              end
              tree.add_child_sorted(node, tree.make_node(NT.FILE, display, file_path))
            end
          end
        end
      end
    end
  end
end

-- ─── Resource scanning ───────────────────────────────────────────────────────

-- Canonical ordering for resource type directories
local RES_ORDER = {
  'drawable', 'drawable-hdpi', 'drawable-mdpi', 'drawable-xhdpi', 'drawable-xxhdpi', 'drawable-xxxhdpi',
  'layout', 'menu', 'mipmap', 'mipmap-hdpi', 'mipmap-mdpi', 'mipmap-xhdpi', 'mipmap-xxhdpi', 'mipmap-xxxhdpi',
  'raw', 'values', 'values-night', 'xml', 'font', 'color', 'anim', 'animator', 'interpolator',
}

local function res_sort_key(name)
  for i, n in ipairs(RES_ORDER) do
    if name == n or name:sub(1, #n) == n then
      return string.format('%04d_%s', i, name)
    end
  end
  return '9999_' .. name
end

function M.scan_resources(module_dir, res_cat_node)
  -- Collect all res-type dirs from all variants
  local res_type_dirs = vim.fn.glob(module_dir .. '/src/*/res/*', false, true)

  -- Group by res-type name, collecting files from all variants
  local type_map = {} -- res_type_name -> { file_path, ... }
  for _, type_dir in ipairs(res_type_dirs) do
    if vim.fn.isdirectory(type_dir) == 1 then
      local type_name = vim.fn.fnamemodify(type_dir, ':t')
      type_map[type_name] = type_map[type_name] or {}
      for _, file in ipairs(vim.fn.glob(type_dir .. '/*', false, true)) do
        if vim.fn.isdirectory(file) == 0 then
          table.insert(type_map[type_name], file)
        end
      end
    end
  end

  -- Sort type names canonically, then add to tree
  local type_names = vim.tbl_keys(type_map)
  table.sort(type_names, function(a, b)
    return res_sort_key(a) < res_sort_key(b)
  end)

  for _, type_name in ipairs(type_names) do
    local type_node = tree.add_child(res_cat_node, tree.make_node(NT.RES_TYPE, type_name, nil))
    local files = type_map[type_name]
    table.sort(files)
    for _, file_path in ipairs(files) do
      local fname = vim.fn.fnamemodify(file_path, ':t')
      tree.add_child(type_node, tree.make_node(NT.FILE, fname, file_path))
    end
  end
end

-- ─── Gradle scripts ──────────────────────────────────────────────────────────

local GRADLE_FILES = {
  'build.gradle',
  'build.gradle.kts',
  'settings.gradle',
  'settings.gradle.kts',
  'gradle.properties',
  'local.properties',
}

local GRADLE_WRAPPER = 'gradle/wrapper/gradle-wrapper.properties'

function M.scan_gradle_scripts(root, modules, gradle_cat_node)
  local project_name = vim.fn.fnamemodify(root, ':t')

  -- Root-level gradle files
  for _, fname in ipairs(GRADLE_FILES) do
    local path = root .. '/' .. fname
    if vim.fn.filereadable(path) == 1 then
      local label = fname .. ' (Project: ' .. project_name .. ')'
      tree.add_child(gradle_cat_node, tree.make_node(NT.FILE, label, path))
    end
  end

  -- Gradle wrapper
  local wrapper = root .. '/' .. GRADLE_WRAPPER
  if vim.fn.filereadable(wrapper) == 1 then
    tree.add_child(gradle_cat_node, tree.make_node(NT.FILE, 'gradle-wrapper.properties', wrapper))
  end

  -- Per-module build files
  for _, mod in ipairs(modules) do
    for _, fname in ipairs { 'build.gradle', 'build.gradle.kts' } do
      local path = mod.dir .. '/' .. fname
      if vim.fn.filereadable(path) == 1 then
        local label = fname .. ' (Module: ' .. mod.name .. ')'
        tree.add_child(gradle_cat_node, tree.make_node(NT.FILE, label, path))
      end
    end
    -- Proguard / other common module files
    for _, fname in ipairs { 'proguard-rules.pro', 'consumer-rules.pro' } do
      local path = mod.dir .. '/' .. fname
      if vim.fn.filereadable(path) == 1 then
        local label = fname .. ' (Module: ' .. mod.name .. ')'
        tree.add_child(gradle_cat_node, tree.make_node(NT.FILE, label, path))
      end
    end
  end
end

-- ─── Build tree ──────────────────────────────────────────────────────────────

function M.build_tree(root)
  local project_name = vim.fn.fnamemodify(root, ':t')
  local root_node = tree.make_node(NT.ROOT, project_name, root)
  root_node.expanded = true

  local modules = M.find_modules(root)

  for _, mod in ipairs(modules) do
    local mod_node = tree.add_child(root_node, tree.make_node(NT.MODULE, mod.name, mod.dir))

    -- Manifests
    local manifests = M.scan_manifests(mod.dir)
    if #manifests > 0 then
      local cat = tree.add_child(mod_node, tree.make_node(NT.CATEGORY, 'manifests', nil))
      for _, path in ipairs(manifests) do
        local variant = path:match '/src/([^/]+)/AndroidManifest%.xml$' or 'main'
        local label = variant == 'main' and 'AndroidManifest.xml'
          or 'AndroidManifest.xml (' .. variant .. ')'
        tree.add_child(cat, tree.make_node(NT.FILE, label, path))
      end
    end

    -- Java/Kotlin
    local java_cat = tree.add_child(mod_node, tree.make_node(NT.CATEGORY, 'java', nil))
    M.scan_sources(mod.dir, java_cat)
    -- Remove java category if empty
    if #java_cat.children == 0 then
      table.remove(mod_node.children)
    end

    -- Resources
    local res_cat = tree.add_child(mod_node, tree.make_node(NT.CATEGORY, 'res', nil))
    M.scan_resources(mod.dir, res_cat)
    if #res_cat.children == 0 then
      table.remove(mod_node.children)
    end
  end

  -- Gradle Scripts (shared, at root level)
  local gradle_cat = tree.add_child(root_node, tree.make_node(NT.CATEGORY, 'Gradle Scripts', nil))
  M.scan_gradle_scripts(root, modules, gradle_cat)
  if #gradle_cat.children == 0 then
    table.remove(root_node.children)
  end

  return root_node
end

return M
