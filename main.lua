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
  boot:UnregisterEvent("ADDON_LOADED")
end)

local function help()
  print("Warbank Audit: /ww [source <auto|builtin|baganator>] [scope <warbank|bank|bags|all>]"
    .. " [threshold <gold>] [enchanter <name>]")
end

SLASH_WARBANKAUDIT1 = "/ww"
SLASH_WARBANKAUDIT2 = "/warbankaudit"
SlashCmdList.WARBANKAUDIT = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    ns.ui.toggle()
  elseif cmd == "source" and (rest == "auto" or rest == "builtin" or rest == "baganator") then
    ns.config.set("source", rest)
    ns.providers.init()
    print("Warbank Audit: data source set to " .. rest .. ".")
  elseif cmd == "scope" and (rest == "warbank" or rest == "bank" or rest == "bags" or rest == "all") then
    ns.config.set("scope", rest)
    print("Warbank Audit: scope set to " .. rest .. ".")
  elseif cmd == "threshold" and tonumber(rest) and tonumber(rest) > 0 then
    ns.config.set("ahThreshold", math.floor(tonumber(rest) * 10000))
    print("Warbank Audit: auction threshold set to " .. rest .. "g.")
  elseif cmd == "enchanter" and rest ~= "" then
    ns.config.set("enchanter", rest)
    print("Warbank Audit: enchanter set to " .. rest .. ".")
  else
    help()
  end
end
