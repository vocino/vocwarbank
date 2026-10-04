local name, ns = ...
local settings = {}
ns.settings = settings

settings.priceOptions = {
  { value = "auto", text = "Auto (best available)" },
  { value = "auctionator", text = "Auctionator" },
  { value = "tsm", text = "TradeSkillMaster" },
  { value = "oribos", text = "Oribos Exchange" },
  { value = "vendor", text = "Vendor prices" },
}

settings.inventoryOptions = {
  { value = "auto", text = "Auto (Syndicator if present)" },
  { value = "syndicator", text = "Syndicator (Baganator)" },
  { value = "blizzard", text = "Blizzard API" },
}

local panel, category
local refreshers = {}

local function makeDropdown(y, label, options, get, set)
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
  title:SetText(label)
  local dd = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -8)
  UIDropDownMenu_SetWidth(dd, 220)
  local function refresh()
    local current = get()
    for _, opt in ipairs(options) do
      if opt.value == current then UIDropDownMenu_SetText(dd, opt.text) return end
    end
    UIDropDownMenu_SetText(dd, tostring(current))
  end
  UIDropDownMenu_Initialize(dd, function()
    for _, opt in ipairs(options) do
      UIDropDownMenu_AddButton({
        text = opt.text, value = opt.value,
        checked = get() == opt.value,
        func = function() set(opt.value) refresh() end,
      })
    end
  end)
  refreshers[#refreshers + 1] = refresh
  refresh()
  return -64
end

local function makeField(y, label, get, set)
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
  title:SetText(label)
  local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  box:SetSize(220, 20)
  box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  box:SetAutoFocus(false)
  box:SetText(get())
  box:SetScript("OnEnterPressed", function(self)
    set(self:GetText())
    self:SetText(get())
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText(get())
    self:ClearFocus()
  end)
  refreshers[#refreshers + 1] = function() box:SetText(get()) end
  return -56
end

local function makeCheckbox(y, label, get, set)
  local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
  local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("LEFT", box, "RIGHT", 4, 0)
  text:SetText(label)
  box:SetChecked(get())
  box:SetScript("OnClick", function(self) set(self:GetChecked()) end)
  refreshers[#refreshers + 1] = function() box:SetChecked(get()) end
  return -32
end

function settings.init()
  if panel then return end
  panel = CreateFrame("Frame")
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText("VocWarbank")
  local y = -52
  y = y + makeDropdown(y, "Price source", settings.priceOptions,
    function() return ns.config.get("priceSource") end,
    function(v) ns.config.set("priceSource", v) ns.providers.init() end)
  y = y + makeDropdown(y, "Warbank source", settings.inventoryOptions,
    function() return ns.config.get("inventorySource") end,
    function(v) ns.config.set("inventorySource", v) end)
  y = y + makeField(y, "TSM price key",
    function() return ns.config.get("tsmKey") end,
    function(v) if v ~= "" then ns.config.set("tsmKey", v) end end)
  y = y + makeField(y, "Enchanter (mail disenchantables to)",
    function() return ns.config.get("enchanter") end,
    function(v) ns.config.set("enchanter", v) end)
  y = y + makeField(y, "Auction threshold (gold)",
    function() return tostring((ns.config.get("ahThreshold") or 0) / 10000) end,
    function(v)
      local g = tonumber(v)
      if g and g > 0 then ns.config.set("ahThreshold", math.floor(g * 10000)) end
    end)
  y = y + makeCheckbox(y, "Open automatically at vendors",
    function() return ns.config.get("autoOpenVendor") end,
    function(v) ns.config.set("autoOpenVendor", v) end)
  y = y + makeCheckbox(y, "Open automatically at the auction house",
    function() return ns.config.get("autoOpenAuction") end,
    function(v) ns.config.set("autoOpenAuction", v) end)
  local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  note:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
  note:SetWidth(400)
  note:SetJustifyH("LEFT")
  note:SetText("Never/always-sell lists live on the slash line: /ww never <item>, "
    .. "/ww always <item>, /ww unnever <item>, /ww unalways <item>.")
  panel.OnRefresh = function()
    for _, refresh in ipairs(refreshers) do refresh() end
  end
  category = Settings.RegisterCanvasLayoutCategory(panel, "VocWarbank")
  Settings.RegisterAddOnCategory(category)
end

function settings.open()
  if category and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  end
end
