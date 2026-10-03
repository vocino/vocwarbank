local name, ns = ...
local ranking = {}
ns.ranking = ranking

ranking.verdictOrder = {
  "keep", "use", "sell", "disenchant", "vendor", "trash", "destroy",
}

-- C_Item.GetItemInfo return positions.
local Q_QUALITY, Q_EQUIPLOC = 3, 9
local Q_LEVEL = 4
local Q_SELLPRICE, Q_CLASS, Q_BIND, Q_EXPANSION = 11, 12, 14, 15

local CLASS_CONSUMABLE, CLASS_WEAPON, CLASS_ARMOR = 0, 2, 4
local CLASS_REAGENT, CLASS_TRADEGOODS, CLASS_QUEST = 5, 7, 12
local BIND_EQUIP, BIND_QUEST = 2, 4
local QUALITY_UNCOMMON, QUALITY_RARE = 2, 3

-- Slots with no transmog appearance; checking them would keep everything.
local NO_APPEARANCE = {
  INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_NECK = true,
  INVTYPE_AMMO = true, INVTYPE_QUIVER = true, INVTYPE_BAG = true,
  [""] = true,
}

local function itemData(item)
  if not item.itemID then return nil end
  local info = { C_Item.GetItemInfo(item.itemID) }
  if info[1] == nil then return nil end -- not cached yet
  return {
    quality = info[Q_QUALITY], equipLoc = info[Q_EQUIPLOC] or "", level = info[Q_LEVEL] or 0,
    sellPrice = info[Q_SELLPRICE] or 0, classID = info[Q_CLASS],
    bindType = info[Q_BIND], expansionID = info[Q_EXPANSION],
  }
end

local function setItemIDs()
  local inSet = {}
  for _, setID in pairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
    for _, itemID in pairs(C_EquipmentSet.GetItemIDs(setID) or {}) do
      if itemID then inSet[itemID] = true end
    end
  end
  return inSet
end

local function marketValue(item, provider)
  if not provider then return nil end
  return provider.GetMarketValue(item.link)
end

local rules = {}

-- 1. Appearance not collected -> keep. Only false keeps; nil (unknown)
-- falls through instead of guessing.
rules[#rules + 1] = function(item, data, ctx)
  if not data then return nil end
  if data.classID ~= CLASS_WEAPON and data.classID ~= CLASS_ARMOR then return nil end
  if NO_APPEARANCE[data.equipLoc] then return nil end
  if C_TransmogCollection.PlayerHasTransmog(item.itemID) == false then
    return "keep", "uncollected look"
  end
end

-- 2. In a saved equipment set -> keep
rules[#rules + 1] = function(item, data, ctx)
  if item.itemID and ctx.inSet[item.itemID] then return "keep", "in equipment set" end
end

-- 3. Current-expansion consumable, reagent, or trade good -> keep
rules[#rules + 1] = function(item, data, ctx)
  if not data or data.expansionID ~= ctx.currentExp then return nil end
  if data.classID == CLASS_CONSUMABLE or data.classID == CLASS_REAGENT
      or data.classID == CLASS_TRADEGOODS then
    return "keep", "current mats"
  end
end

-- 4. On the never-sell list -> keep
rules[#rules + 1] = function(item, data, ctx)
  if item.itemID and ns.config.get("neverSell")[item.itemID] then return "keep", "never-sell list" end
end

-- 5. On the always-sell list -> sell when valued, else vendor
rules[#rules + 1] = function(item, data, ctx)
  if item.itemID and ns.config.get("alwaysSell")[item.itemID] then
    local price = marketValue(item, ctx.provider)
    if price and price > 0 then return "sell", "always-sell list" end
    return "vendor", "always-sell list"
  end
end

-- 6. Openable container (cache, lockbox, gift) -> use. Contents
-- can't be triaged until the box is opened.
rules[#rules + 1] = function(item, data, ctx)
  if item.openable then return "use", "openable" end
end

-- Definitive-false collectable checks. Each returns true only on a
-- proven "is one, owns zero"; anything else (not one, unknown, API
-- missing or erroring) returns false and the item falls through.
local function uncollectedDecor(itemID)
  if not (C_Item and C_Item.IsDecorItem) then return false end
  local ok, isDecor = pcall(C_Item.IsDecorItem, itemID)
  if not ok or isDecor ~= true then return false end
  local cat = C_HousingCatalog
  if not (cat and cat.GetCatalogEntryInfoByItem) then return false end
  local okEntry, info = pcall(cat.GetCatalogEntryInfoByItem, itemID)
  if not okEntry or type(info) ~= "table" then return false end
  return (info.totalNumStored or 0) + (info.totalNumPlaced or 0)
    + (info.remainingRedeemable or 0) == 0
end

local function uncollectedPet(itemID)
  local pj = C_PetJournal
  if not (pj and pj.GetPetInfoByItemID and pj.GetNumCollectedInfo) then return false end
  local ok, speciesID = pcall(function() return select(13, pj.GetPetInfoByItemID(itemID)) end)
  if not ok or speciesID == nil then return false end
  local okCount, owned = pcall(pj.GetNumCollectedInfo, speciesID)
  return (okCount and owned == 0) or false
end

local function uncollectedMount(itemID)
  local mj = C_MountJournal
  if not (mj and mj.GetMountFromItem and mj.GetMountInfoByID) then return false end
  local ok, mountID = pcall(mj.GetMountFromItem, itemID)
  if not ok or mountID == nil then return false end
  local okInfo, collected = pcall(function() return select(11, mj.GetMountInfoByID(mountID)) end)
  return (okInfo and collected == false) or false
end

local function uncollectedToy(itemID)
  local tb = C_ToyBox
  if not (tb and tb.GetToyInfo and PlayerHasToy) then return false end
  local ok, toyID = pcall(tb.GetToyInfo, itemID)
  if not ok or toyID == nil then return false end
  return PlayerHasToy(itemID) == false
end

-- 7. Uncollected collectable (decor, pet, mount, toy) -> use. Extra
-- copies of owned collectables fall through to the normal rules.
rules[#rules + 1] = function(item, data, ctx)
  if not item.itemID then return nil end
  if uncollectedDecor(item.itemID) then return "use", "uncollected decor" end
  if uncollectedPet(item.itemID) then return "use", "uncollected pet" end
  if uncollectedMount(item.itemID) then return "use", "uncollected mount" end
  if uncollectedToy(item.itemID) then return "use", "uncollected toy" end
end

-- 8. Bind-on-equip gear, market value above threshold -> sell.
-- Any expansion: a priced current BoE should list, not vendor.
rules[#rules + 1] = function(item, data, ctx)
  if not data then return nil end
  if data.classID ~= CLASS_WEAPON and data.classID ~= CLASS_ARMOR then return nil end
  if data.bindType ~= BIND_EQUIP then return nil end
  local price = marketValue(item, ctx.provider)
  if price and price > ns.config.get("ahThreshold") then return "sell", "worth listing" end
end

-- 9. Old-expansion uncommon/rare gear -> disenchant. Epics fall through
-- to vendor so buyback stays available; greens/blues are safe to break.
rules[#rules + 1] = function(item, data, ctx)
  if not data then return nil end
  if data.classID ~= CLASS_WEAPON and data.classID ~= CLASS_ARMOR then return nil end
  if data.quality ~= QUALITY_UNCOMMON and data.quality ~= QUALITY_RARE then return nil end
  if data.expansionID == nil or data.expansionID >= ctx.currentExp then return nil end
  return "disenchant", "disenchantable"
end

-- 10. Quest item -> keep. Trashing dead quest items needs a quest-log
-- lookup (TODO); until then these stay out of harm's way.
rules[#rules + 1] = function(item, data, ctx)
  if not data then return nil end
  if data.classID == CLASS_QUEST or data.bindType == BIND_QUEST then
    return "keep", "quest item"
  end
end

-- 11. Has a vendor price -> vendor
rules[#rules + 1] = function(item, data, ctx)
  if data and data.sellPrice and data.sellPrice > 0 then return "vendor", "vendor price" end
end

-- 12. Anything else -> keep. Destroy-by-default deleted Hearthstones;
-- unclassified items wait for review instead.
function ranking.rank(items)
  local ctx = {
    provider = ns.providers.get(),
    currentExp = GetExpansionLevel(),
    inSet = setItemIDs(),
  }
  local ranked = {}
  for _, item in ipairs(items) do
    local data = itemData(item)
    local verdict, reason = "keep", "needs review"
    for _, rule in ipairs(rules) do
      local v, r = rule(item, data, ctx)
      if v then verdict, reason = v, r break end
    end
    ranked[#ranked + 1] = { item = item, verdict = verdict, reason = reason, detail = data }
  end
  return ranked
end
