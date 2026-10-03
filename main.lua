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

SLASH_WARBANKAUDIT1 = "/ww"
SLASH_WARBANKAUDIT2 = "/warbankaudit"
SlashCmdList.WARBANKAUDIT = function()
  ns.ui.toggle()
end
