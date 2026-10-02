local name, ns = ...
local scanner = {}
ns.scanner = scanner

-- container-agnostic. every scope yields the same item records:
--   { link, itemID, count, bag, slot, scope }
-- TODO: verify warbank container api in game (see SPEC.md open questions).

local function scanBags(out)
  for bag = 0, 5 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        local _, count = C_Container.GetContainerItemInfo(bag, slot)
        out[#out + 1] = {
          link = link, itemID = tonumber(link:match("item:(%d+)")),
          count = count, bag = bag, slot = slot, scope = "bags",
        }
      end
    end
  end
end

local function scanBank(out)
  -- TODO: character bank slots via C_Container (bank bags) + BankFrame
end

local function scanWarbank(out)
  -- TODO: warband bank tabs. verify the C_Bank / container api in game.
end

function scanner.scan(scope)
  local out = {}
  if scope == "bags" or scope == "all" then scanBags(out) end
  if scope == "bank" or scope == "all" then scanBank(out) end
  if scope == "warbank" or scope == "all" then scanWarbank(out) end
  return out
end
