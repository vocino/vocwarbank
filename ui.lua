local name, ns = ...
local ui = {}
ns.ui = ui

local window = nil
local cutoff = 0 -- index of the line; everything below is queued

function ui.init()
  -- TODO: build with blizzard templates at build time.
  -- layout: header (totals + active source), scroll list grouped by
  -- verdict, draggable line, footer (dry-run summary + action buttons).
end

function ui.toggle()
  -- TODO: show/hide. rescan on open.
  print("warbank audit: ui not built yet. see SPEC.md")
end

function ui.setCutoff(index)
  cutoff = index
end

function ui.getCutoff() return cutoff end
