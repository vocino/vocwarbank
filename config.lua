local _, ns = ...
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
  sortMode = "off",          -- off | quality | value | name
  sortReverse = false,       -- flip the sort comparator
  collapsedGroups = {},      -- section key -> true
  queue = {},                -- action -> itemID -> { link, n, scope }
}

local enums = {
  priceSource = { auto = true, vendor = true, auctionator = true, tsm = true, oribos = true },
  inventorySource = { auto = true, blizzard = true, syndicator = true },
  scope = { warbank = true, bank = true, bags = true, all = true },
  sortMode = { off = true, quality = true, value = true, name = true },
}

local function fresh(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = v end
  return copy
end

-- The live table: ns.db after boot, the SavedVariable before it, a
-- scratch table if neither exists yet (pre-load slash use).
local function db()
  if type(ns.db) == "table" then return ns.db end
  if type(VocWarbankDB) == "table" then ns.db = VocWarbankDB return ns.db end
  ns.db = ns.db or {}
  return ns.db
end

function config.init()
  local d = db()
  for k, v in pairs(defaults) do
    if d[k] == nil then d[k] = fresh(v) end
  end
  -- 0.x migration: single `source` split into price/inventory sources.
  if d.source ~= nil then
    if d.source == "builtin" then d.priceSource = "vendor" end
    if d.source == "baganator" then d.inventorySource = "syndicator" end
    d.source = nil
  end
  -- Repair corrupt values (hand-edited SavedVariables, stale shapes).
  -- Wrong-typed or out-of-range settings fall back to defaults instead
  -- of breaking scans, sorts, and comparisons downstream.
  for k, allowed in pairs(enums) do
    if not allowed[d[k]] then d[k] = defaults[k] end
  end
  for _, k in ipairs({ "neverSell", "alwaysSell", "collapsedGroups", "queue" }) do
    if type(d[k]) ~= "table" then d[k] = {} end
  end
  -- Queue rows must be well-formed (hand edits, older shapes); ragged
  -- actions and rows drop, valid ones stay.
  for action, rows in pairs(d.queue) do
    if type(rows) ~= "table" then
      d.queue[action] = nil
    else
      for id, row in pairs(rows) do
        if type(row) ~= "table" or type(row.n) ~= "number" or row.n <= 0 then
          rows[id] = nil
        end
      end
      if next(rows) == nil then d.queue[action] = nil end
    end
  end
  if type(d.ahThreshold) ~= "number" or d.ahThreshold <= 0 then
    d.ahThreshold = defaults.ahThreshold
  end
  if type(d.tsmKey) ~= "string" or d.tsmKey == "" then d.tsmKey = defaults.tsmKey end
  if type(d.enchanter) ~= "string" then d.enchanter = defaults.enchanter end
  for _, k in ipairs({ "autoOpenVendor", "autoOpenAuction", "sortReverse" }) do
    if type(d[k]) ~= "boolean" then d[k] = defaults[k] end
  end
end

function config.get(k)
  local v = db()[k]
  if v == nil then return defaults[k] end
  return v
end

-- The default for a key (a copy, for tables). The Settings panel
-- reads it so defaults are declared exactly once.
function config.default(k) return fresh(defaults[k]) end

function config.set(k, v) db()[k] = v end

function config.parseItemID(s)
  if not s or s == "" then return nil end
  return tonumber(s) or tonumber(tostring(s):match("item:(%d+)"))
end

function config.setListItem(which, itemID, on)
  local list = db()[which]
  if type(list) ~= "table" or not itemID then return false end
  if on then list[itemID] = true else list[itemID] = nil end
  return true
end
