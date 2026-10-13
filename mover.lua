local _, ns = ...
local mover = {}
ns.mover = mover

-- Live item moves between bank/warbank and bags: the cleanout loop.
--
-- Every move runs synchronously inside a button-click handler (a
-- hardware event): that is what makes the protected C_Container calls
-- legal. No timers, no background moves, no OnUpdate pumps.
--
-- Safety: the cursor is checked empty before every pickup
-- (CursorHasItem, still live on 12.1.5); a dirty cursor aborts the run
-- instead of risking a misdrop. Combat aborts too. Bank moves need the
-- bank open -- container reads go empty otherwise -- so the whole flow
-- gates on BANKFRAME_OPENED/CLOSED.

mover.bankOpen = false
mover.lastEmptyScope = nil -- where the last Empty withdrew from; Deposit returns there

-- Container IDs, probed at use time: GetContainerNumSlots on a dead ID
-- returns 0 under pcall, so probing never errors.
local function probe(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local ok, n = pcall(C_Container.GetContainerNumSlots, id)
    if ok and n and n > 0 then out[#out + 1] = id end
  end
  return out
end

-- Character bank containers: the 12.1.5 tab model first, legacy names
-- as fallback (the scanner carries the same dual list).
function mover.bankContainers()
  local bagIndex = Enum and Enum.BagIndex or nil
  local ids = {}
  if bagIndex then
    for i = 1, 6 do ids[#ids + 1] = bagIndex["CharacterBankTab_" .. i] end
  end
  local tabs = probe(ids)
  if #tabs > 0 then return tabs end
  ids = { -1 }
  if bagIndex then
    for i = 1, 7 do ids[#ids + 1] = bagIndex["BankBag_" .. i] end
  else
    for i = 5, 11 do ids[#ids + 1] = i end
  end
  return probe(ids)
end

function mover.warbankContainers()
  local bagIndex = Enum and Enum.BagIndex or nil
  local ids = {}
  if bagIndex then
    for tab = 1, 5 do ids[#ids + 1] = bagIndex["AccountBankTab_" .. tab] end
  end
  return probe(ids)
end

function mover.scopeContainers(scope)
  if scope == "warbank" then return mover.warbankContainers() end
  return mover.bankContainers()
end

-- Free {bag, slot} pairs across the backpack and bag slots.
function mover.freeBagSlots()
  local out = {}
  for bag = 0, 4 do
    local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
    for slot = 1, (ok and n or 0) do
      if C_Container.GetContainerItemLink(bag, slot) == nil then
        out[#out + 1] = { bag = bag, slot = slot }
      end
    end
  end
  return out
end

-- Free {bag, slot} pairs across a container list.
function mover.freeSlotsIn(containers)
  local out = {}
  for _, bag in ipairs(containers) do
    local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
    for slot = 1, (ok and n or 0) do
      if C_Container.GetContainerItemLink(bag, slot) == nil then
        out[#out + 1] = { bag = bag, slot = slot }
      end
    end
  end
  return out
end

local function cursorEmpty()
  if type(CursorHasItem) == "function" then
    local ok, has = pcall(CursorHasItem)
    if ok then return not has end
  end
  if type(C_Cursor) == "table" and type(C_Cursor.GetCursorItem) == "function" then
    local ok, item = pcall(C_Cursor.GetCursorItem)
    if ok then return item == nil end
  end
  return false -- unknown state: fail closed
end

-- One move: lift from src, drop on an empty dst slot. True on a clean
-- move; false aborts the run. A failed place tries to put the item
-- back; if that fails too the item stays on the cursor for the player
-- to drop, and the run stops.
function mover.move(srcBag, srcSlot, dstBag, dstSlot)
  if not cursorEmpty() then return false end
  local ok = pcall(C_Container.PickupContainerItem, srcBag, srcSlot)
  if not ok or cursorEmpty() then return false end
  local ok2 = pcall(C_Container.PickupContainerItem, dstBag, dstSlot)
  if not ok2 or not cursorEmpty() then
    pcall(C_Container.PickupContainerItem, srcBag, srcSlot)
    return false
  end
  return true
end

local function movesAllowed()
  if InCombatLockdown and InCombatLockdown() then
    ns.say("can't move items in combat")
    return false
  end
  if not mover.bankOpen then
    ns.say("open the bank first")
    return false
  end
  return true
end

-- Empty: withdraw everything movable from the bank scope into bags.
-- Moves what fits and stops cleanly when bags fill: the wave model.
-- Records without real bag/slot (Syndicator view-only) are skipped.
-- Returns moved, left.
function mover.withdraw(scope)
  if not movesAllowed() then return 0, 0 end
  local src = {}
  for _, r in ipairs(ns.scanner.scan(scope)) do
    if type(r.bag) == "number" and type(r.slot) == "number" then
      src[#src + 1] = r
    end
  end
  if #src == 0 then
    ns.say("nothing to withdraw")
    return 0, 0
  end
  local free = mover.freeBagSlots()
  if #free == 0 then
    ns.say("bags are full")
    return 0, #src
  end
  local moved = 0
  for i, r in ipairs(src) do
    if i > #free then break end
    local dst = free[i]
    if mover.move(r.bag, r.slot, dst.bag, dst.slot) then
      moved = moved + 1
    else
      break
    end
  end
  mover.lastEmptyScope = scope
  local left = #src - moved
  if left > 0 then
    ns.say("moved " .. moved .. " to bags (bags full, " .. left .. " left -- sort and empty again)")
  else
    ns.say("moved " .. moved .. " to bags (bank empty)")
  end
  return moved, left
end

-- Deposit: move bag items back into the bank scope's free slots.
-- entries are ranked entries ({item = scanner record, ...}).
-- Returns the count moved.
function mover.deposit(entries, scope)
  if not movesAllowed() then return 0 end
  scope = scope or mover.lastEmptyScope or "warbank"
  local free = mover.freeSlotsIn(mover.scopeContainers(scope))
  if #free == 0 then
    ns.say("no room in the " .. scope)
    return 0
  end
  local actionable = {}
  for _, e in ipairs(entries or {}) do
    local item = e.item or e
    if item.scope == "bags" and type(item.bag) == "number" and type(item.slot) == "number" then
      actionable[#actionable + 1] = item
    end
  end
  if #actionable == 0 then
    ns.say("nothing to deposit")
    return 0
  end
  local moved = 0
  for i, item in ipairs(actionable) do
    if i > #free then break end
    local dst = free[i]
    if mover.move(item.bag, item.slot, dst.bag, dst.slot) then
      moved = moved + 1
    else
      break
    end
  end
  ns.say("deposited " .. moved .. " to the " .. scope)
  return moved
end

-- Gatekeeper: hold the bar. Snapshot the banks on open; on close, flag
-- anything newly stored that falls below the keep line. Quiet when
-- nothing new arrived. The cleanout's own deposits are keep-verdict,
-- so they never trip it.
local openSnapshot = nil

local function snapshot()
  local counts = {}
  local function add(scope)
    for _, r in ipairs(ns.scanner.scan(scope)) do
      if r.itemID then
        local key = scope .. ":" .. r.itemID
        local row = counts[key]
        if not row then
          row = { count = 0, link = r.link, record = r }
          counts[key] = row
        end
        row.count = row.count + (r.count or 1)
      end
    end
  end
  add("bank")
  add("warbank")
  return counts
end

local function gatekeeperCheck()
  if not openSnapshot then return end
  if ns.config.get("gatekeeper") == false then return end
  local now = snapshot()
  local fresh = {}
  for key, row in pairs(now) do
    local before = openSnapshot[key]
    if not before or row.count > before.count then
      fresh[#fresh + 1] = row.record
    end
  end
  openSnapshot = nil
  if #fresh == 0 then return end
  local below = {}
  for _, entry in ipairs(ns.ranking.rank(fresh)) do
    if entry.verdict ~= "keep" then below[#below + 1] = entry end
  end
  if #below == 0 then return end
  local links = {}
  for i, entry in ipairs(below) do
    if i > 5 then break end
    links[#links + 1] = entry.item.link
  end
  local more = #below > 5 and (" (+" .. (#below - 5) .. " more)") or ""
  ns.say("stored " .. #below .. " below-the-line item" .. (#below == 1 and "" or "s")
    .. ": " .. table.concat(links, " ") .. more)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:SetScript("OnEvent", function(_, event)
  if event == "BANKFRAME_OPENED" then
    mover.bankOpen = true
    openSnapshot = snapshot()
  elseif event == "BANKFRAME_CLOSED" then
    mover.bankOpen = false
    gatekeeperCheck()
  end
end)
