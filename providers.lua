local name, ns = ...
local providers = {}
ns.providers = providers

-- every provider implements:
--   GetExpansion(itemID) -> expansion key ("tww", "midnight", ...) or nil
--   GetMarketValue(itemLink) -> copper or nil

local registry = {}
local active = nil

function providers.register(key, provider)
  registry[key] = provider
end

local function pick()
  local want = ns.config.get("source")
  if want ~= "auto" and registry[want] then return registry[want], want end
  -- auto: best available first
  for _, key in ipairs({ "baganator", "tsm", "auctionator", "builtin" }) do
    if registry[key] then return registry[key], key end
  end
end

function providers.init()
  local provider, key = pick()
  active = provider
  ns.activeSource = key or "none"
end

function providers.get() return active end

-- builtin: always available, no dependencies.
-- expansion table is generated per patch (see SPEC.md).
-- value falls back to vendor sell price.
local builtin = {}
local expansionTable = {} -- TODO: generate from data at build time

function builtin.GetExpansion(itemID)
  return expansionTable[itemID]
end

function builtin.GetMarketValue(itemLink)
  local price = select(11, C_Item.GetItemInfo(itemLink))
  return price -- vendor sell price in copper; nil if uncached, 0 if unsellable
end

providers.register("builtin", builtin)

-- external providers: guarded, xpcall-wrapped, verify exact calls in game.
-- baganator/syndicator: expansion classification (Baganator.API is public).
-- tsm / auctionator: market values.
local function tryRegister(key, addonName, build)
  if not C_AddOns.IsAddOnLoaded(addonName) then return end
  local ok, provider = xpcall(build, geterrorhandler())
  if ok and provider then providers.register(key, provider) end
end

-- TODO: fill in at build time after verifying each addon's public api
-- tryRegister("baganator", "Baganator", function() ... end)
-- tryRegister("tsm", "TradeSkillMaster", function() ... end)
-- tryRegister("auctionator", "Auctionator", function() ... end)
