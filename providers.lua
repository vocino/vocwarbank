local name, ns = ...
local providers = {}
ns.providers = providers

-- Price sources. Each entry is { label, available(), fetch(link, itemID) }.
-- External calls are presence-gated and pcall-guarded: a broken or
-- missing pricing addon must never break a scan. Availability is
-- checked live on every lookup, so late-loading addons just work.
local registry = {}

local function safeFetch(entry, link, itemID)
  local ok, price = pcall(entry.fetch, link, itemID)
  if ok and type(price) == "number" and price > 0 then return price end
  return nil
end

function providers.register(key, entry)
  registry[key] = entry
end

local function parseItemID(link, itemID)
  return itemID or (link and tonumber(link:match("item:(%d+)")) or nil)
end

-- Vendor sell price. Always available; ends every cascade.
providers.register("vendor", {
  label = "Vendor prices",
  available = function() return true end,
  fetch = function(link, itemID)
    if not link then return nil end
    return select(11, C_Item.GetItemInfo(link))
  end,
})

-- Auctionator: realm min-buyout from its scan database.
providers.register("auctionator", {
  label = "Auctionator",
  available = function()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and (api.GetAuctionPriceByItemID or api.GetAuctionPriceByItemLink) and true or false
  end,
  fetch = function(link, itemID)
    local api = Auctionator.API.v1
    if itemID and api.GetAuctionPriceByItemID then
      return api.GetAuctionPriceByItemID(name, itemID)
    elseif link and api.GetAuctionPriceByItemLink then
      return api.GetAuctionPriceByItemLink(name, link)
    end
    return nil
  end,
})

-- TradeSkillMaster: evaluates a price-source key (default DBMarket).
providers.register("tsm", {
  label = "TradeSkillMaster",
  available = function()
    return TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString and true or false
  end,
  fetch = function(link, itemID)
    if not link then return nil end
    local itemStr = TSM_API.ToItemString(link)
    if not itemStr then return nil end
    return TSM_API.GetCustomPriceValue(ns.config.get("tsmKey") or "DBMarket", itemStr)
  end,
})

-- Oribos Exchange: realm market value, region fallback.
providers.register("oribos", {
  label = "Oribos Exchange",
  available = function() return type(OEMarketInfo) == "function" end,
  fetch = function(link, itemID)
    local info = {}
    OEMarketInfo(link or itemID, info)
    if info.market and info.market > 0 then return info.market end
    if info.region and info.region > 0 then return info.region end
    return nil
  end,
})

-- Auto order follows install base: most likely installed first.
local AUTO_ORDER = { "auctionator", "tsm", "oribos", "vendor" }

local function chain()
  local want = ns.config and ns.config.get("priceSource") or "auto"
  if want ~= "auto" and registry[want] then
    if want == "vendor" then return { "vendor" } end
    return { want, "vendor" }
  end
  return AUTO_ORDER
end

function providers.getPrice(link, itemID)
  itemID = parseItemID(link, itemID)
  for _, key in ipairs(chain()) do
    local entry = registry[key]
    if entry and entry.available() then
      local price = safeFetch(entry, link, itemID)
      if price then return price, key end
    end
  end
  return nil, nil
end

function providers.describe()
  local want = ns.config and ns.config.get("priceSource") or "auto"
  if want ~= "auto" then return want end
  for _, key in ipairs(AUTO_ORDER) do
    local entry = registry[key]
    if entry and entry.available() then return "auto:" .. key end
  end
  return "auto"
end

-- Expansion keys come from the item's own data; no external addon
-- provides them. LE_EXPANSION_* ids: 0 classic ... 10 tww, 11 midnight.
local expansionKeys = {
  [0] = "classic", [1] = "tbc", [2] = "wotlk", [3] = "cata",
  [4] = "mop", [5] = "wod", [6] = "legion", [7] = "bfa",
  [8] = "sl", [9] = "df", [10] = "tww", [11] = "midnight",
}

local function getExpansion(itemID)
  if not itemID then return nil end
  local expansionID = select(15, C_Item.GetItemInfo(itemID))
  return expansionID and expansionKeys[expansionID] or nil
end

-- Composite provider behind the stable two-function contract.
local composite = {}
function composite.GetMarketValue(link)
  local price = providers.getPrice(link, nil)
  return price
end
composite.GetExpansion = getExpansion

function providers.get() return composite end

function providers.init()
  ns.activeSource = providers.describe()
end
