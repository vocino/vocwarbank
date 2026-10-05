local _, ns = ...
local queue = {}
ns.queue = queue

-- Action queue. Rows are item identities, not bag slots: a slot goes
-- stale the moment anything moves, while an itemID re-resolves against
-- a fresh scan at handoff time -- even on another character, since the
-- SavedVariable is account-wide and the scan is whoever is at the
-- keyboard.
--
-- Stored shape (config "queue"): action -> itemID -> { link, n, scope }
--   link: last seen item link, for names when no scan holds the item
--   n: how many are queued
--   scope: where the item was when queued, for the "stowed" hint
--
-- Pure model: no frames, no WoW calls. handoff.lua resolves rows
-- against a live scan; ui.lua paints the queued ring from queuedAs.

local function store()
  local q = ns.config.get("queue")
  if type(q) ~= "table" then return {} end
  return q
end

local function rowsFor(action, create)
  local q = store()
  local rows = q[action]
  if type(rows) ~= "table" then
    if not create then return nil end
    rows = {}
    q[action] = rows
    ns.config.set("queue", q)
  end
  return rows
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return tostring(a) < tostring(b)
  end)
  return keys
end

-- Actions holding at least one row, sorted. Empty when nothing is queued.
function queue.actions()
  local q, out = store(), {}
  for _, action in ipairs(sortedKeys(q)) do
    if type(q[action]) == "table" and next(q[action]) ~= nil then
      out[#out + 1] = action
    end
  end
  return out
end

-- Rows for an action as { id, link, n, scope }, sorted by itemID.
function queue.list(action)
  local rows, out = rowsFor(action, false), {}
  if not rows then return out end
  for _, id in ipairs(sortedKeys(rows)) do
    local row = rows[id]
    if type(row) == "table" then
      out[#out + 1] = { id = id, link = row.link, n = row.n or 0, scope = row.scope }
    end
  end
  return out
end

-- Total queued items for an action (0 when empty or unknown).
function queue.count(action)
  local n = 0
  for _, row in ipairs(queue.list(action)) do n = n + (row.n or 0) end
  return n
end

function queue.empty(action)
  return queue.count(action) == 0
end

-- Queue ranked entries under an action. Counts merge by itemID; the
-- link and scope refresh to the latest seen. Returns items added.
function queue.add(action, entries)
  local added = 0
  local rows = rowsFor(action, true)
  for _, entry in ipairs(entries or {}) do
    local item = entry and entry.item
    local id = item and item.itemID
    if id then
      local n = item.count or 1
      local row = rows[id]
      if type(row) ~= "table" then row = {} rows[id] = row end
      row.n = (row.n or 0) + n
      if item.link then row.link = item.link end
      if item.scope then row.scope = item.scope end
      added = added + n
    end
  end
  return added
end

-- Unqueue n of an item (the whole row when n is nil). Returns items removed.
function queue.remove(action, itemID, n)
  if n ~= nil and (type(n) ~= "number" or n <= 0) then return 0 end
  local rows = rowsFor(action, false)
  local row = rows and rows[itemID]
  if type(row) ~= "table" then return 0 end
  local have = row.n or 0
  local take = (n == nil or n >= have) and have or n
  if take >= have then rows[itemID] = nil
  else row.n = have - take end
  return take
end

-- Toggle ranked entries: queued items unqueue by the given counts,
-- new items queue. Per itemID, so one click never half-queues a stack.
-- Returns added, removed.
function queue.toggle(action, entries)
  local byID, rep = {}, {}
  for _, entry in ipairs(entries or {}) do
    local item = entry and entry.item
    local id = item and item.itemID
    if id then
      byID[id] = (byID[id] or 0) + (item.count or 1)
      if not rep[id] then rep[id] = entry end
    end
  end
  local added, removed = 0, 0
  for _, id in ipairs(sortedKeys(byID)) do
    local rows = rowsFor(action, false)
    if rows and rows[id] ~= nil then
      removed = removed + queue.remove(action, id, byID[id])
    else
      local item = rep[id].item
      local stub = { item = { itemID = id, link = item.link,
        count = byID[id], scope = item.scope } }
      added = added + queue.add(action, { stub })
    end
  end
  return added, removed
end

-- Drop one action's rows, or the whole queue when action is nil.
function queue.clear(action)
  if action == nil then
    ns.config.set("queue", {})
  else
    local q = store()
    q[action] = nil
    ns.config.set("queue", q)
  end
end

-- The action an entry is queued under, or nil. Ranked entries carry
-- the itemID; anything without one is never queued.
function queue.queuedAs(entry)
  local item = entry and entry.item
  local id = item and item.itemID
  if not id then return nil end
  local q = store()
  for _, action in ipairs(sortedKeys(q)) do
    local rows = q[action]
    if type(rows) == "table" and rows[id] ~= nil then return action end
  end
  return nil
end

-- Resolve an action's rows against a fresh ranked scan (all scopes).
-- Bag stacks with real slots are ready, in scan order, up to the queued
-- count; a partly covered stack sells whole (the merchant call addresses
-- the slot, not the count), so it joins ready with its full stack.
-- Leftovers found only outside bags report stowed, the rest missing;
-- both carry the uncovered remainder. Deterministic: rows by itemID,
-- ready in scan order.
function queue.resolve(action, ranked)
  local ready, missing, stowed = {}, {}, {}
  ranked = ranked or {}
  for _, row in ipairs(queue.list(action)) do
    local need = row.n or 0
    if need > 0 then
      local seenElsewhere = false
      for _, entry in ipairs(ranked) do
        local item = entry.item
        if item and item.itemID == row.id then
          if need > 0 and item.scope == "bags"
              and type(item.bag) == "number" and type(item.slot) == "number" then
            ready[#ready + 1] = entry
            need = need - (item.count or 1)
          elseif item.scope ~= "bags" then
            seenElsewhere = true
          end
        end
      end
      if need > 0 then
        local leftover = { id = row.id, link = row.link, n = need, scope = row.scope }
        if seenElsewhere then stowed[#stowed + 1] = leftover
        else missing[#missing + 1] = leftover end
      end
    end
  end
  return { ready = ready, missing = missing, stowed = stowed }
end

-- Forget sold stacks after a handoff. sold is ranked entries (or plain
-- { itemID, count } shapes); rows drain by itemID and vanish at zero.
-- Returns the action's remaining queued count.
function queue.prune(action, sold)
  for _, entry in ipairs(sold or {}) do
    local id = entry.itemID or (entry.item and entry.item.itemID)
    local n = entry.count or (entry.item and entry.item.count) or 1
    if id then queue.remove(action, id, n) end
  end
  return queue.count(action)
end
