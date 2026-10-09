local name, ns = ...

-- ns.providers is set by providers.lua; do not reset it here

-- Chat voice shared by every Voc addon (see FAMILY.md): one line, the
-- addon name as a colored prefix, then the message.
ns.PREFIX_COLOR = "ff66ccff"
function ns.say(msg)
  print("|c" .. ns.PREFIX_COLOR .. name .. "|r: " .. tostring(msg))
end

-- Confirmation sounds shared by every Voc addon (FAMILY.md "Sounds"):
-- SOUNDKIT names first, the numeric IDs behind them so a Blizzard
-- rename never silences the polish. Presence-gated: no sound API, no
-- sound, never an error.
ns.SOUNDS = {
  on = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
  off = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857 },
  open = { "IG_MAINMENU_OPEN", 850 },
  close = { "IG_MAINMENU_CLOSE", 851 },
}
function ns.play(kind)
  local s = ns.SOUNDS[kind]
  if not s or type(PlaySound) ~= "function" then return end
  local id = type(SOUNDKIT) == "table" and SOUNDKIT[s[1]] or nil
  pcall(PlaySound, type(id) == "number" and id or s[2])
end

-- Addon compartment (FAMILY.md "Addon compartment"): the toc names
-- these three globals; Blizzard's compartment menu calls them with
-- (addonName, button). The click does what the bare slash does (open
-- or close the window); hover follows the tooltip contract: gold
-- title, one line, the slash hint.
function VocWarbank_CompartmentClick()
  ns.ui.toggle()
end

function VocWarbank_CompartmentEnter(_, button)
  if type(GameTooltip) ~= "table" then return end
  local c = ns.COLORS
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText("VocWarbank", c.gold[1], c.gold[2], c.gold[3])
  GameTooltip:AddLine("Audits your warband bank, bank, and bags: ranks everything, you draw the line.",
    c.text[1], c.text[2], c.text[3], true)
  GameTooltip:AddLine("/vw opens the window. /vw help lists the rest.",
    c.muted[1], c.muted[2], c.muted[3], true)
  GameTooltip:Show()
end

function VocWarbank_CompartmentLeave()
  if type(GameTooltip) == "table" then GameTooltip:Hide() end
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
  "/vw queue                           list queued handoff items",
  "/vw queue clear [action]            drop queued items",
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
  if ns.handoff and ns.handoff.onQueueChanged then
    ns.handoff.onQueueChanged()
  end
end

local function theme()
  local s = ns.theme.status()
  ns.say("look: " .. s.look
    .. " (baganator:" .. (s.baganator and s.baganatorSkin or "absent") .. ")")
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
      .. ", at the auction house " .. (ns.config.get("autoOpenAuction") and "ON" or "off"))
  elseif key and (val == "on" or val == "off") then
    ns.config.set(key, val == "on")
    ns.say("auto-open " .. (key == "autoOpenVendor" and "at vendors" or "at the auction house")
      .. " " .. (val == "on" and "enabled" or "disabled"))
  else
    ns.say("usage: /vw auto <vendor|auction> <on|off>")
  end
end

local function pin(which, rest, on)
  local id = ns.config.parseItemID(rest)
  if not id then ns.say("give an item link or ID") return end
  ns.config.setListItem(which, id, on)
  refresh()
  if which == "neverSell" then
    ns.say("item " .. id .. (on and " will always be kept" or " removed from never-sell"))
  else
    ns.say("item " .. id .. (on and " will always sell" or " removed from always-sell"))
  end
end

-- Actions with a handoff queue (queue.lua). New actions extend this
-- when they grow a queue-and-handoff flow.
local queueActions = { vendor = true }

local function queueCmd(rest)
  if not ns.queue then ns.help() return end
  local sub, arg = rest:match("^(%S*)%s*(.-)%s*$")
  sub, arg = (sub or ""):lower(), (arg or ""):lower()
  if sub == "" and arg == "" then
    local actions = ns.queue.actions()
    if #actions == 0 then ns.say("nothing queued") return end
    for _, action in ipairs(actions) do
      ns.say(action .. " (" .. ns.queue.count(action) .. " queued):")
      for _, row in ipairs(ns.queue.list(action)) do
        local itemName = (ns.ui and ns.ui.linkName and ns.ui.linkName(row.link))
          or ("item:" .. tostring(row.id))
        print("  " .. itemName .. (row.n > 1 and (" ×" .. row.n) or ""))
      end
    end
  elseif sub == "clear" and (arg == "" or queueActions[arg]) then
    ns.queue.clear(arg == "" and nil or arg)
    refresh()
    ns.say(arg == "" and "queue cleared" or (arg .. " queue cleared"))
  else
    ns.say("usage: /vw queue [clear [action]]")
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
    ns.say("price source set to " .. arg)
  elseif cmd == "inventory" and inventorySources[arg] then
    ns.config.set("inventorySource", arg)
    refresh()
    ns.say("warbank source set to " .. arg)
  elseif cmd == "scope" and scopeValues[arg] then
    ns.config.set("scope", arg)
    refresh()
    ns.say("scope set to " .. arg)
  elseif cmd == "threshold" and tonumber(rest) and tonumber(rest) > 0 then
    ns.config.set("ahThreshold", math.floor(tonumber(rest) * 10000))
    refresh()
    ns.say("auction threshold set to " .. rest .. "g")
  elseif cmd == "enchanter" and rest ~= "" then
    ns.config.set("enchanter", rest)
    ns.say("enchanter set to " .. rest)
  elseif cmd == "tsmkey" and rest ~= "" then
    ns.config.set("tsmKey", rest)
    refresh()
    ns.say("TSM price key set to " .. rest)
  elseif cmd == "never" or cmd == "unnever" then
    pin("neverSell", rest, cmd == "never")
  elseif cmd == "always" or cmd == "unalways" then
    pin("alwaysSell", rest, cmd == "always")
  elseif cmd == "queue" then
    queueCmd(rest)
  else
    ns.help()
  end
end
