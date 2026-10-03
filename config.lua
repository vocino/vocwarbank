local name, ns = ...
local config = {}
ns.config = config

local defaults = {
  priceSource = "auto",      -- auto | vendor | auctionator | tsm | oribos
  inventorySource = "auto",  -- auto | blizzard | syndicator (warbank only)
  tsmKey = "DBMarket",       -- TSM price source expression
  enchanter = "",            -- character to mail disenchantables to
  ahThreshold = 100000,      -- copper; above this, SELL beats VENDOR
  neverSell = {},            -- itemID -> true
  alwaysSell = {},           -- itemID -> true
  scope = "bags",            -- warbank | bank | bags | all
  autoOpenVendor = false,    -- pop up beside the merchant window
  autoOpenAuction = false,   -- pop up beside the auction house
}

function config.init()
  for k, v in pairs(defaults) do
    if ns.db[k] == nil then ns.db[k] = v end
  end
  -- 0.x migration: single `source` split into price/inventory sources.
  if ns.db.source ~= nil then
    if ns.db.source == "builtin" then ns.db.priceSource = "vendor" end
    if ns.db.source == "baganator" then ns.db.inventorySource = "syndicator" end
    ns.db.source = nil
  end
end

function config.get(k) return ns.db[k] end
function config.set(k, v) ns.db[k] = v end

function config.parseItemID(s)
  if not s or s == "" then return nil end
  return tonumber(s) or tonumber(tostring(s):match("item:(%d+)"))
end

function config.setListItem(which, itemID, on)
  local list = ns.db[which]
  if type(list) ~= "table" or not itemID then return false end
  if on then list[itemID] = true else list[itemID] = nil end
  return true
end
