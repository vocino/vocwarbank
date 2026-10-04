local name, ns = ...
local scanner = {}
ns.scanner = scanner

-- container-agnostic. every scope yields item records:
--   { link, itemID, count, bag, slot, scope, openable,
--     quality, icon, bound, tab, index }
-- bags records carry bag/slot (actionable). warbank records carry
-- tab/index into their source: Syndicator slots are view-only, while
-- Blizzard warbank bags carry real C_Container bag/slot too.
-- (Syndicator shapes verified against its source in
-- .reference/Syndicator, Tracking/BagCache.lua.)

local function scanBags(out)
  for bag = 0, 5 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        out[#out + 1] = {
          link = link, itemID = tonumber(link:match("item:(%d+)")),
          count = info and info.stackCount or 1,
          bag = bag, slot = slot, scope = "bags",
          openable = info and info.hasLoot or nil,
          quality = info and info.quality or nil,
          icon = info and info.iconFileID or nil,
          bound = info and info.isBound or nil,
        }
      end
    end
  end
end

-- Character bank: main bank, bank bags, reagent bank. Plain
-- C_Container bags; contents read empty unless the bank is open,
-- same as the Blizzard warbank path.
local function scanBank(out)
  local ids, seen = {}, {}
  local function add(id)
    if id and not seen[id] then seen[id] = true ids[#ids + 1] = id end
  end
  local bagIndex = Enum and Enum.BagIndex or nil
  if bagIndex then
    add(bagIndex.Bank)
    for i = 1, 7 do add(bagIndex["BankBag_" .. i]) end
    add(bagIndex.Reagentbank)
    add(bagIndex.ReagentBank)
  end
  -- legacy numeric IDs, stable across clients
  add(-1) -- BANK_CONTAINER
  for i = 5, 11 do add(i) end -- bank bags
  add(-3) -- REAGENTBANK_CONTAINER
  for _, bagID in ipairs(ids) do
    local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagID)
    if ok and numSlots and numSlots > 0 then
      for slot = 1, numSlots do
        local link = C_Container.GetContainerItemLink(bagID, slot)
        if link then
          local info = C_Container.GetContainerItemInfo(bagID, slot)
          out[#out + 1] = {
            link = link, itemID = tonumber(link:match("item:(%d+)")),
            count = info and info.stackCount or 1,
            bag = bagID, slot = slot, scope = "bank",
            openable = info and info.hasLoot or nil,
            quality = info and info.quality or nil,
            icon = info and info.iconFileID or nil,
            bound = info and info.isBound or nil,
          }
        end
      end
    end
  end
end

local function syndicatorReady()
  return Syndicator and Syndicator.API and Syndicator.API.IsReady
    and Syndicator.API.GetWarband and true or false
end

-- Warbank contents via Syndicator (Baganator's data backend). Dense
-- arrays: bank[tabIndex].slots[slotID]; empty slots are bare tables.
local function scanWarbankSyndicator(out)
  local api = Syndicator.API
  if api.IsReady and not api.IsReady() then return end
  local ok, warband = pcall(api.GetWarband, 1)
  if not ok or type(warband) ~= "table" or type(warband.bank) ~= "table" then return end
  for tabIndex, tab in ipairs(warband.bank) do
    if type(tab) == "table" and type(tab.slots) == "table" then
      for slotID, slot in ipairs(tab.slots) do
        if type(slot) == "table" and slot.itemID then
          out[#out + 1] = {
            link = slot.itemLink, itemID = slot.itemID,
            count = slot.itemCount or 1,
            bag = nil, slot = nil, scope = "warbank",
            tab = tabIndex, index = slotID,
            quality = slot.quality, icon = slot.iconTexture,
            bound = slot.isBound,
          }
        end
      end
    end
  end
end

-- Warbank tabs are plain C_Container bags (Enum.BagIndex.AccountBankTab_1
-- .. _5, per Syndicator's Constants). Reads empty when the bank is closed.
local function scanWarbankBlizzard(out)
  local bagIndex = Enum and Enum.BagIndex or nil
  if not bagIndex then return end
  for tab = 1, 5 do
    local bagID = bagIndex["AccountBankTab_" .. tab]
    if bagID then
      local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagID)
      if ok and numSlots then
        for slot = 1, numSlots do
          local link = C_Container.GetContainerItemLink(bagID, slot)
          if link then
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            out[#out + 1] = {
              link = link, itemID = tonumber(link:match("item:(%d+)")),
              count = info and info.stackCount or 1,
              bag = bagID, slot = slot, scope = "warbank",
              tab = tab, index = slot,
              openable = info and info.hasLoot or nil,
              quality = info and info.quality or nil,
              icon = info and info.iconFileID or nil,
              bound = info and info.isBound or nil,
            }
          end
        end
      end
    end
  end
end

local function scanWarbank(out)
  local want = ns.config.get("inventorySource") or "auto"
  if want == "syndicator" or want == "auto" then
    if syndicatorReady() then scanWarbankSyndicator(out) return end
    if want == "syndicator" then return end
  end
  scanWarbankBlizzard(out)
end

function scanner.scan(scope)
  local out = {}
  if scope == "bags" or scope == "all" then scanBags(out) end
  if scope == "bank" or scope == "all" then scanBank(out) end
  if scope == "warbank" or scope == "all" then scanWarbank(out) end
  return out
end
