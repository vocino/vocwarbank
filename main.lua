local name, ns = ...

-- ns.providers is set by providers.lua; do not reset it here
ns.scopes = { "warbank", "bank", "bags" }

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, addon)
  if addon ~= name then return end
  VocWarbankDB = VocWarbankDB or {}
  ns.db = VocWarbankDB
  ns.config.init()
  ns.providers.init()
  ns.ui.init()
  ns.settings.init()
  boot:UnregisterEvent("ADDON_LOADED")
end)

local function help()
  print("VocWarbank: /ww [source <auto|vendor|auctionator|tsm|oribos>] [theme]"
    .. " [inventory <auto|blizzard|syndicator>] [scope <warbank|bank|bags|all>]"
    .. " [threshold <gold>] [enchanter <name>] [never|always|unnever|unalways <item>]"
    .. " [auto <vendor|auction> <on|off>] [config]")
end

local priceSources = { auto = true, vendor = true, auctionator = true, tsm = true, oribos = true }
local inventorySources = { auto = true, blizzard = true, syndicator = true }

SLASH_VOCWARBANK1 = "/ww"
SLASH_VOCWARBANK2 = "/vocwarbank"
SlashCmdList.VOCWARBANK = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    ns.ui.toggle()
  elseif cmd == "auto" then
    local which, val = rest:match("^(%S+)%s*(%S*)%s*$")
    which, val = (which or ""):lower(), (val or ""):lower()
    local key = (which == "vendor" or which == "vendors" or which == "merchant") and "autoOpenVendor"
      or ((which == "auction" or which == "ah" or which == "auctionhouse") and "autoOpenAuction" or nil)
    if rest == "" then
      print("VocWarbank: auto-open at vendors is "
        .. (ns.config.get("autoOpenVendor") and "ON" or "off")
        .. ", at the auction house " .. (ns.config.get("autoOpenAuction") and "ON" or "off") .. ".")
    elseif key and (val == "on" or val == "off") then
      ns.config.set(key, val == "on")
      print("VocWarbank: auto-open " .. (key == "autoOpenVendor" and "at vendors" or "at the auction house")
        .. " " .. (val == "on" and "enabled." or "disabled."))
    else
      print("VocWarbank: /ww auto <vendor|auction> <on|off>")
    end
  elseif cmd == "config" then
    ns.settings.open()
  elseif cmd == "theme" then
    local s = ns.theme.status()
    print("VocWarbank look: " .. s.look
      .. " (eui:" .. (s.euiFacade and "yes" or "no")
      .. " baganator:" .. (s.baganator and s.baganatorSkin or "absent") .. ")")
    if not s.euiMaster then print("VocWarbank: EUI third-party skins are OFF (master toggle).") end
    if not s.euiAddon then print("VocWarbank: EUI skin for VocWarbank is OFF (per-addon toggle).") end
    if s.error then print("VocWarbank: last skin error [" .. s.error.style .. "]: " .. s.error.err) end
  elseif cmd == "source" and priceSources[rest] then
    ns.config.set("priceSource", rest)
    ns.providers.init()
    print("VocWarbank: price source set to " .. rest .. ".")
  elseif cmd == "inventory" and inventorySources[rest] then
    ns.config.set("inventorySource", rest)
    print("VocWarbank: warbank source set to " .. rest .. ".")
  elseif cmd == "scope" and (rest == "warbank" or rest == "bank" or rest == "bags" or rest == "all") then
    ns.config.set("scope", rest)
    print("VocWarbank: scope set to " .. rest .. ".")
  elseif cmd == "threshold" and tonumber(rest) and tonumber(rest) > 0 then
    ns.config.set("ahThreshold", math.floor(tonumber(rest) * 10000))
    print("VocWarbank: auction threshold set to " .. rest .. "g.")
  elseif cmd == "enchanter" and rest ~= "" then
    ns.config.set("enchanter", rest)
    print("VocWarbank: enchanter set to " .. rest .. ".")
  elseif cmd == "never" or cmd == "unnever" then
    local id = ns.config.parseItemID(rest)
    if not id then print("VocWarbank: give an item link or ID.")
    else
      ns.config.setListItem("neverSell", id, cmd == "never")
      print("VocWarbank: item " .. id .. (cmd == "never" and " will always be kept." or " removed from never-sell."))
    end
  elseif cmd == "always" or cmd == "unalways" then
    local id = ns.config.parseItemID(rest)
    if not id then print("VocWarbank: give an item link or ID.")
    else
      ns.config.setListItem("alwaysSell", id, cmd == "always")
      print("VocWarbank: item " .. id .. (cmd == "always" and " will always sell." or " removed from always-sell."))
    end
  else
    help()
  end
end
