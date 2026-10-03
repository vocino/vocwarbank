local name, ns = ...

-- ns.providers is set by providers.lua; do not reset it here
ns.scopes = { "warbank", "bank", "bags" }

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, addon)
  if addon ~= name then return end
  WarbankAuditDB = WarbankAuditDB or {}
  ns.db = WarbankAuditDB
  ns.config.init()
  ns.providers.init()
  ns.ui.init()
  ns.settings.init()
  boot:UnregisterEvent("ADDON_LOADED")
end)

local function help()
  print("Warbank Audit: /ww [source <auto|vendor|auctionator|tsm|oribos>]"
    .. " [inventory <auto|blizzard|syndicator>] [scope <warbank|bank|bags|all>]"
    .. " [threshold <gold>] [enchanter <name>] [never|always|unnever|unalways <item>] [config]")
end

local priceSources = { auto = true, vendor = true, auctionator = true, tsm = true, oribos = true }
local inventorySources = { auto = true, blizzard = true, syndicator = true }

SLASH_WARBANKAUDIT1 = "/ww"
SLASH_WARBANKAUDIT2 = "/warbankaudit"
SlashCmdList.WARBANKAUDIT = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    ns.ui.toggle()
  elseif cmd == "config" then
    ns.settings.open()
  elseif cmd == "source" and priceSources[rest] then
    ns.config.set("priceSource", rest)
    ns.providers.init()
    print("Warbank Audit: price source set to " .. rest .. ".")
  elseif cmd == "inventory" and inventorySources[rest] then
    ns.config.set("inventorySource", rest)
    print("Warbank Audit: warbank source set to " .. rest .. ".")
  elseif cmd == "scope" and (rest == "warbank" or rest == "bank" or rest == "bags" or rest == "all") then
    ns.config.set("scope", rest)
    print("Warbank Audit: scope set to " .. rest .. ".")
  elseif cmd == "threshold" and tonumber(rest) and tonumber(rest) > 0 then
    ns.config.set("ahThreshold", math.floor(tonumber(rest) * 10000))
    print("Warbank Audit: auction threshold set to " .. rest .. "g.")
  elseif cmd == "enchanter" and rest ~= "" then
    ns.config.set("enchanter", rest)
    print("Warbank Audit: enchanter set to " .. rest .. ".")
  elseif cmd == "never" or cmd == "unnever" then
    local id = ns.config.parseItemID(rest)
    if not id then print("Warbank Audit: give an item link or ID.")
    else
      ns.config.setListItem("neverSell", id, cmd == "never")
      print("Warbank Audit: item " .. id .. (cmd == "never" and " will always be kept." or " removed from never-sell."))
    end
  elseif cmd == "always" or cmd == "unalways" then
    local id = ns.config.parseItemID(rest)
    if not id then print("Warbank Audit: give an item link or ID.")
    else
      ns.config.setListItem("alwaysSell", id, cmd == "always")
      print("Warbank Audit: item " .. id .. (cmd == "always" and " will always sell." or " removed from always-sell."))
    end
  else
    help()
  end
end
