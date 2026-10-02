local name, ns = ...
local config = {}
ns.config = config

local defaults = {
  source = "auto",       -- auto | builtin | baganator
  enchanter = "",        -- character to mail disenchantables to
  ahThreshold = 100000,  -- copper; above this, SELL beats VENDOR
  neverSell = {},        -- itemID -> true
  alwaysSell = {},       -- itemID -> true
  scope = "warbank",     -- warbank | bank | bags | all
}

function config.init()
  for k, v in pairs(defaults) do
    if ns.db[k] == nil then ns.db[k] = v end
  end
end

function config.get(k) return ns.db[k] end
function config.set(k, v) ns.db[k] = v end
