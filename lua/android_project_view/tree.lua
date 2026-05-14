local M = {}

M.NodeType = {
  ROOT     = 'root',
  MODULE   = 'module',
  CATEGORY = 'category',
  PACKAGE  = 'package',
  RES_TYPE = 'res_type',
  FILE     = 'file',
}

function M.make_node(type, name, path)
  return {
    type     = type,
    name     = name,
    path     = path or nil,
    children = {},
    expanded = false,
    parent   = nil,
  }
end

function M.add_child(parent, child)
  child.parent = parent
  table.insert(parent.children, child)
  return child
end

-- Insert a child, keeping children sorted alphabetically by name
function M.add_child_sorted(parent, child)
  child.parent = parent
  local inserted = false
  for i, existing in ipairs(parent.children) do
    if child.name < existing.name then
      table.insert(parent.children, i, child)
      inserted = true
      break
    end
  end
  if not inserted then
    table.insert(parent.children, child)
  end
  return child
end

-- Find a direct child by name
function M.find_child(node, name)
  for _, child in ipairs(node.children) do
    if child.name == name then
      return child
    end
  end
  return nil
end

-- Collect all file paths in the tree (for preserving expanded state across refresh)
function M.collect_expanded_paths(node, result)
  result = result or {}
  if node.expanded and node.path then
    result[node.path] = true
  end
  -- Also key virtual nodes (no path) by type+name chain
  if node.expanded then
    local key = (node.type or '') .. ':' .. (node.name or '')
    result[key] = true
  end
  for _, child in ipairs(node.children) do
    M.collect_expanded_paths(child, result)
  end
  return result
end

-- Restore expanded state from a saved set
function M.restore_expanded(node, saved)
  if node.path and saved[node.path] then
    node.expanded = true
  end
  local key = (node.type or '') .. ':' .. (node.name or '')
  if saved[key] then
    node.expanded = true
  end
  for _, child in ipairs(node.children) do
    M.restore_expanded(child, saved)
  end
end

return M
