-- Headless WoW API stubs for VocWarbank tests.
-- Installs fake globals; tests then load the addon files against them:
--   local mock = dofile("tests/mock.lua")
--   mock.install()

local unpack = unpack or table.unpack -- retail client is 5.1, probes run newer

local mock = {}

function mock.reset()
  mock.items = {}            -- itemID -> item fields
  mock.completedQuests = {}  -- questID -> title
  mock.tooltips = {}         -- itemID -> { lines }
  mock.sets = {}             -- setID -> { itemID, ... }
  mock.professionIndices = {} -- fake GetProfessions returns
  mock.professionSkills = {}  -- index -> skillID
  mock.transmog = {}         -- itemID -> true (collected)
  mock.pets = {}             -- itemID -> { speciesID, owned }
  mock.mounts = {}           -- itemID -> { mountID, collected }
  mock.toys = {}             -- itemID -> true (owned)
  mock.decor = {}            -- itemID -> { stored, placed, redeemable }
  mock.prices = {}           -- itemID -> copper
  mock.bags = {}             -- bagID -> { [slot] = { link, count, ... } }
  mock.expansionLevel = 11   -- midnight
  mock.cfg = {
    neverSell = {}, alwaysSell = {},
    ahThreshold = 100000, inventorySource = "auto", enchanter = "",
  }
  mock.provider = {
    GetMarketValue = function(link)
      local id = tonumber(link:match("item:(%d+)"))
      return id and mock.prices[id] or nil
    end,
  }
end

-- register a fake item; fields land in C_Item.GetItemInfo positions
function mock.item(id, f)
  f = f or {}
  mock.items[id] = {
    name = f.name or ("Item " .. id),
    link = "|cffffffff|Hitem:" .. id .. "|h[" .. (f.name or ("Item " .. id)) .. "]|h|r",
    quality = f.quality or 1,
    level = f.level or 1,
    equipLoc = f.equipLoc,
    sellPrice = f.sellPrice or 0,
    classID = f.classID,
    subclassID = f.subclassID,
    bindType = f.bindType,
    expansionID = f.expansionID,
  }
end

-- addon namespace with stubbed config/providers
function mock.ns()
  return {
    config = {
      get = function(k) return mock.cfg[k] end,
      set = function(k, v) mock.cfg[k] = v end,
      parseItemID = function(s)
        if not s or s == "" then return nil end
        return tonumber(s) or tonumber(tostring(s):match("item:(%d+)"))
      end,
      setListItem = function(which, itemID, on)
        local list = mock.cfg[which]
        if type(list) ~= "table" or not itemID then return false end
        if on then list[itemID] = true else list[itemID] = nil end
        return true
      end,
    },
    providers = {
      get = function() return mock.provider end,
    },
  }
end

function mock.tooltip(name)
  local tip = {}
  function tip:SetOwner() end
  function tip:ClearLines() end
  function tip:SetHyperlink(link)
    local itemID = tonumber(link:match("item:(%d+)"))
    local lines = mock.tooltips[itemID] or {}
    for i, text in ipairs(lines) do
      _G[name .. "TextLeft" .. i] = { GetText = function() return text end }
    end
    tip._n = #lines
  end
  function tip:NumLines() return tip._n or 0 end
  return tip
end

function mock.install()
  -- slot names used by ranking.lua's NO_APPEARANCE table
  for _, k in ipairs({ "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_FINGER",
      "INVTYPE_TRINKET", "INVTYPE_NECK", "INVTYPE_AMMO", "INVTYPE_QUIVER",
      "INVTYPE_BAG", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON" }) do
    if _G[k] == nil then _G[k] = k end
  end

  _G.UIParent = _G.UIParent or {}
  _G.GetExpansionLevel = function() return mock.expansionLevel end

  _G.C_Item = {
    GetItemInfo = function(itemID)
      local it = mock.items[itemID]
      if not it then return nil end
      return it.name, it.link, it.quality, it.level,
        nil, nil, nil, nil, it.equipLoc,
        nil, it.sellPrice, it.classID, it.subclassID, it.bindType, it.expansionID
    end,
    IsDecorItem = function(itemID) return mock.decor[itemID] ~= nil end,
  }

  _G.C_TransmogCollection = {
    PlayerHasTransmog = function(itemID) return mock.transmog[itemID] == true end,
  }

  _G.C_EquipmentSet = {
    GetEquipmentSetIDs = function()
      local ids = {}
      for id in pairs(mock.sets) do ids[#ids + 1] = id end
      return ids
    end,
    GetItemIDs = function(setID) return mock.sets[setID] or {} end,
  }

  _G.GetProfessions = function() return unpack(mock.professionIndices) end
  _G.GetProfessionInfo = function(index)
    return nil, nil, nil, nil, nil, nil, mock.professionSkills[index]
  end

  _G.C_HousingCatalog = {
    GetCatalogEntryInfoByItem = function(itemID)
      local d = mock.decor[itemID]
      if not d then return nil end
      return { totalNumStored = d.stored or 0, totalNumPlaced = d.placed or 0,
               remainingRedeemable = d.redeemable or 0 }
    end,
  }

  _G.C_PetJournal = {
    GetPetInfoByItemID = function(itemID)
      local p = mock.pets[itemID]
      if not p then return nil end
      return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil, p.speciesID
    end,
    GetNumCollectedInfo = function(speciesID)
      for _, p in pairs(mock.pets) do
        if p.speciesID == speciesID then return p.owned or 0 end
      end
      return 0
    end,
  }

  _G.C_MountJournal = {
    GetMountFromItem = function(itemID)
      local m = mock.mounts[itemID]
      return m and m.mountID or nil
    end,
    GetMountInfoByID = function(mountID)
      for _, m in pairs(mock.mounts) do
        if m.mountID == mountID then
          return nil,nil,nil,nil,nil,nil,nil,nil,nil,nil, m.collected
        end
      end
      return nil
    end,
  }

  _G.C_ToyBox = {
    GetToyInfo = function(itemID)
      if mock.toys[itemID] == nil then return nil end
      return itemID
    end,
  }
  _G.PlayerHasToy = function(itemID) return mock.toys[itemID] == true end

  _G.C_QuestLog = {
    GetAllCompletedQuestIDs = function()
      local ids = {}
      for id in pairs(mock.completedQuests) do ids[#ids + 1] = id end
      return ids
    end,
    GetTitleForQuestID = function(id) return mock.completedQuests[id] end,
  }

  _G.C_Container = {
    GetContainerNumSlots = function(bag)
      local b = mock.bags[bag]
      if not b then return 0 end
      local n = 0
      for slot in pairs(b) do if slot > n then n = slot end end
      return n
    end,
    GetContainerItemLink = function(bag, slot)
      local s = mock.bags[bag] and mock.bags[bag][slot]
      return s and s.link or nil
    end,
    GetContainerItemInfo = function(bag, slot)
      local s = mock.bags[bag] and mock.bags[bag][slot]
      if not s then return nil end
      return { stackCount = s.count or 1, hasLoot = s.openable,
               quality = s.quality, iconFileID = s.icon, isBound = s.bound }
    end,
  }

  _G.CreateFrame = function(ftype, name)
    if ftype == "GameTooltip" then return mock.tooltip(name) end
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript() end
    return frame
  end
end

return mock
