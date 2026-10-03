local name, ns = ...
local scanner = {}
ns.scanner = scanner

-- container-agnostic. every scope yields item records:
--   { link, itemID, count, bag, slot, scope }
-- warbank records from Syndicator carry no bag/slot (view-only).

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
        }
      end
    end
  end
end

local function scanBank(out)
  -- TODO: character bank slots via C_Container (bank bags) + BankFrame
end

local function syndicatorReady()
  return Syndicator and Syndicator.API and Syndicator.API.IsReady
    and Syndicator.API.GetWarband and true or false
end

-- Warbank contents via Syndicator (Baganator's data backend). View-only:
-- Syndicator gives no container slots, and remote actions need the bank
-- open anyway, so these records carry no bag/slot. No local install has
-- Syndicator, so this path needs in-game verification.
local function scanWarbankSyndicator(out)
  local api = Syndicator.API
  if api.IsReady and not api.IsReady() then return end
  local ok, warband = pcall(api.GetWarband, 1)
  if not ok or type(warband) ~= "table" or type(warband.bank) ~= "table" then return end
  for tabIndex, tab in pairs(warband.bank) do
    if type(tab) == "table" then
      local slots = tab.slots or tab
      if type(slots) == "table" then
        for _, slot in pairs(slots) do
          if type(slot) == "table" then
            local link = slot.itemLink
            local itemID = slot.itemID or (link and tonumber(link:match("item:(%d+)")) or nil)
            if link or itemID then
              out[#out + 1] = {
                link = link, itemID = itemID,
                count = slot.itemCount or slot.count or 1,
                bag = nil, slot = nil, scope = "warbank", tab = tabIndex,
              }
            end
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
  -- TODO: Blizzard C_Bank path once the container api is verified in game.
end

function scanner.scan(scope)
  local out = {}
  if scope == "bags" or scope == "all" then scanBags(out) end
  if scope == "bank" or scope == "all" then scanBank(out) end
  if scope == "warbank" or scope == "all" then scanWarbank(out) end
  return out
end
