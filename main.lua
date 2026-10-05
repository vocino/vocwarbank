local name, ns = ...

-- ns.providers is set by providers.lua; do not reset it here

-- Chat voice shared by every Voc addon (see FAMILY.md): one line, the
-- addon name as a colored prefix, then the message.
ns.PREFIX_COLOR = "ff66ccff"
function ns.say(msg)
  print("|c" .. ns.PREFIX_COLOR .. name .. "|r: " .. tostring(msg))
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" then
    if addon ~= name then return end
    if type(VocWarbankDB) ~= "table" then VocWarbankDB = {} end
    ns.db = VocWarbankDB
    ns.config.init()
    ns.providers.init()
    ns.ui.init()
    ns.settings.init()
    boot:UnregisterEvent("ADDON_LOADED")
  else
    ns.settings.init() -- in case the Settings API wasn't up at ADDON_LOADED
    boot:UnregisterEvent("PLAYER_LOGIN")
  end
end)

-- Slash grammar shared by every Voc addon (FAMILY.md): the bare command
-- does the one main thing, `config` opens the panel, `help` lists the
-- rest, and anything unrecognized prints help instead of acting.
ns.HELP = {
  "/vw                                 open or close the window",
  "/vw scope <bags|bank|warbank|all>   what to scan",
  "/vw source <auto|vendor|auctionator|tsm|oribos>   price source",
  "/vw inventory <auto|blizzard|syndicator>   warbank source",
  "/vw threshold <gold>                auction threshold for BoE gear",
  "/vw enchanter <name>                who gets disenchantables by mail",
  "/vw tsmkey <key>                    TSM price key (default DBMarket)",
  "/vw never|unnever <item>            pin or unpin a never-sell item",
  "/vw always|unalways <item>          pin or unpin an always-sell item",
  "/vw auto <vendor|auction> <on|off>  auto-open at vendors or the AH",
  "/vw theme                           report the active look",
  "/vw config                          open Settings > AddOns > VocWarbank",
  "/vw help                            this list (/vocwarbank works too)",
}

function ns.help()
  ns.say("commands")
  for _, line in ipairs(ns.HELP) do print("  " .. line) end
end

local priceSources = { auto = true, vendor = true, auctionator = true, tsm = true, oribos = true }
local inventorySources = { auto = true, blizzard = true, syndicator = true }
local scopeValues = { warbank = true, bank = true, bags = true, all = true }

-- Settings changed under an open window apply immediately.
local function refresh()
  if ns.ui and ns.ui.isOpen and ns.ui.isOpen() and ns.ui.rescan then
    ns.ui.rescan(true)
  end
end

local function theme()
  local s = ns.theme.status()
  ns.say("look: " .. s.look
    .. " (eui:" .. (s.euiFacade and "yes" or "no")
    .. " baganator:" .. (s.baganator and s.baganatorSkin or "absent") .. ")")
  if not s.euiMaster then ns.say("EUI third-party skins are OFF (master toggle).") end
  if not s.euiAddon then ns.say("EUI skin for VocWarbank is OFF (per-addon toggle).") end
  if s.error then ns.say("last skin error [" .. s.error.style .. "]: " .. s.error.err) end
end

local function auto(rest)
  local which, val = rest:match("^(%S+)%s*(%S*)%s*$")
  which, val = (which or ""):lower(), (val or ""):lower()
  local key = (which == "vendor" or which == "vendors" or which == "merchant") and "autoOpenVendor"
    or ((which == "auction" or which == "ah" or which == "auctionhouse") and "autoOpenAuction" or nil)
  if rest == "" then
    ns.say("auto-open at vendors is "
      .. (ns.config.get("autoOpenVendor") and "ON" or "off")
      .. ", at the auction house " .. (ns.config.get("autoOpenAuction") and "ON" or "off") .. ".")
  elseif key and (val == "on" or val == "off") then
    ns.config.set(key, val == "on")
    ns.say("auto-open " .. (key == "autoOpenVendor" and "at vendors" or "at the auction house")
      .. " " .. (val == "on" and "enabled." or "disabled."))
  else
    ns.say("usage: /vw auto <vendor|auction> <on|off>")
  end
end

local function pin(which, rest, on)
  local id = ns.config.parseItemID(rest)
  if not id then ns.say("give an item link or ID.") return end
  ns.config.setListItem(which, id, on)
  refresh()
  if which == "neverSell" then
    ns.say("item " .. id .. (on and " will always be kept." or " removed from never-sell."))
  else
    ns.say("item " .. id .. (on and " will always sell." or " removed from always-sell."))
  end
end

-- Blizzard's slash dispatcher reads SLASH_* globals by name, so these
-- cannot be namespaced (they are declared in .luacheckrc instead).
SLASH_VOCWARBANK1 = "/vw"
SLASH_VOCWARBANK2 = "/vocwarbank"
SlashCmdList.VOCWARBANK = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local arg = rest:lower()
  if cmd == "" then
    ns.ui.toggle()
  elseif cmd == "auto" then
    auto(rest)
  elseif cmd == "config" then
    ns.settings.open()
  elseif cmd == "theme" then
    theme()
  elseif cmd == "source" and priceSources[arg] then
    ns.config.set("priceSource", arg)
    ns.providers.init()
    refresh()
    ns.say("price source set to " .. arg .. ".")
  elseif cmd == "inventory" and inventorySources[arg] then
    ns.config.set("inventorySource", arg)
    refresh()
    ns.say("warbank source set to " .. arg .. ".")
  elseif cmd == "scope" and scopeValues[arg] then
    ns.config.set("scope", arg)
    refresh()
    ns.say("scope set to " .. arg .. ".")
  elseif cmd == "threshold" and tonumber(rest) and tonumber(rest) > 0 then
    ns.config.set("ahThreshold", math.floor(tonumber(rest) * 10000))
    refresh()
    ns.say("auction threshold set to " .. rest .. "g.")
  elseif cmd == "enchanter" and rest ~= "" then
    ns.config.set("enchanter", rest)
    ns.say("enchanter set to " .. rest .. ".")
  elseif cmd == "tsmkey" and rest ~= "" then
    ns.config.set("tsmKey", rest)
    refresh()
    ns.say("TSM price key set to " .. rest .. ".")
  elseif cmd == "never" or cmd == "unnever" then
    pin("neverSell", rest, cmd == "never")
  elseif cmd == "always" or cmd == "unalways" then
    pin("alwaysSell", rest, cmd == "always")
  else
    ns.help()
  end
end
