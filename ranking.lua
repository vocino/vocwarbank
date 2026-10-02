local name, ns = ...
local ranking = {}
ns.ranking = ranking

-- verdicts, in priority order. first match wins.
-- returns verdict, reasonTag
local rules = {}

-- 1. appearance not collected -> keep
rules[#rules + 1] = function(item)
  -- TODO: C_TransmogCollection appearance check
  return nil
end

-- 2. in a saved equipment set -> keep
rules[#rules + 1] = function(item)
  -- TODO: C_EquipmentSet.GetItemIDs
  return nil
end

-- 3. current-expansion reagent or consumable -> keep
-- 4. never-sell list -> keep
-- 5. old gear, boe, market value above threshold -> sell
-- 6. disenchantable, mat value above vendor -> disenchant
-- 7. has vendor price -> vendor
-- 8. quest item, quest not in log -> trash
-- 9. else -> destroy

function ranking.rank(items)
  local provider = ns.providers.get()
  local ranked = {}
  for _, item in ipairs(items) do
    local verdict, reason = "destroy", "no use found"
    for _, rule in ipairs(rules) do
      local v, r = rule(item, provider)
      if v then verdict, reason = v, r break end
    end
    ranked[#ranked + 1] = {
      item = item, verdict = verdict, reason = reason,
    }
  end
  -- sort: keep first, destroy last (verdict order), then value desc
  return ranked
end

ranking.verdictOrder = {
  "keep", "sell", "disenchant", "vendor", "trash", "destroy",
}
