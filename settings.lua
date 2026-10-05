local _, ns = ...
local settings = {}
ns.settings = settings

-- Native Blizzard Settings category (Settings > AddOns > VocWarbank),
-- the same API and shape as every Voc addon (FAMILY.md): dropdowns and
-- checkboxes bound straight to the live SavedVariables table, so the
-- panel and the slash line always agree. Free-text options (enchanter,
-- TSM key, never/always lists) stay on the slash line; the panel says so.

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

settings.scopeOptions = {
  { value = "bags", text = "Bags" },
  { value = "bank", text = "Character bank" },
  { value = "warbank", text = "Warband bank" },
  { value = "all", text = "All three" },
}

-- Auction threshold presets, in gold. A value set on the slash line
-- that is not a preset joins the list as "(custom)" so the dropdown
-- always shows the truth.
settings.thresholdGold = { 1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000 }

local category

-- An open window re-ranks immediately so settings apply live.
local function changed()
  if ns.ui and ns.ui.isOpen and ns.ui.isOpen() and ns.ui.rescan then
    ns.ui.rescan(true)
  end
end

local function goldLabel(copper)
  local gold = copper / 10000
  if gold == math.floor(gold) then return string.format("%dg", gold) end
  return string.format("%.2fg", gold)
end

-- Dropdown data builders. Settings.CreateDropdown takes a function so
-- the list is rebuilt each time the control opens.
local function optionsFrom(list)
  return function()
    local container = Settings.CreateControlTextContainer()
    for _, opt in ipairs(list) do container:Add(opt.value, opt.text, opt.tooltip or "") end
    return container:GetData()
  end
end

function settings.thresholdOptions()
  local container = Settings.CreateControlTextContainer()
  local values, preset = {}, {}
  for _, g in ipairs(settings.thresholdGold) do
    local copper = g * 10000
    values[#values + 1] = copper
    preset[copper] = true
  end
  local current = ns.config.get("ahThreshold")
  if type(current) == "number" and current > 0 and not preset[current] then
    values[#values + 1] = current
  end
  table.sort(values)
  for _, copper in ipairs(values) do
    local label = goldLabel(copper)
    if not preset[copper] then label = label .. " (custom)" end
    container:Add(copper, label, "")
  end
  return container:GetData()
end

-- Without setting callbacks the panel still works, just without the
-- live re-rank.
local function onChange(setting, fn)
  if setting and type(setting.SetValueChangedCallback) == "function" then
    setting:SetValueChangedCallback(fn)
  end
end

local function register(key, label)
  local default = ns.config.default(key)
  return Settings.RegisterAddOnSetting(
    category, "VocWarbank_" .. key, key, ns.db, type(default), label, default)
end

local function dropdown(key, label, options, tooltip, fn)
  local s = register(key, label)
  Settings.CreateDropdown(category, s, options, tooltip)
  onChange(s, fn or changed)
end

local function checkbox(key, label, tooltip)
  local s = register(key, label)
  Settings.CreateCheckbox(category, s, tooltip)
  onChange(s, changed)
end

-- A section header is the one plain-text element the vertical layout
-- offers; it carries the pointer to the slash-only options. Guarded:
-- the panel is complete without it.
local function note(text)
  if type(CreateSettingsListSectionHeaderInitializer) ~= "function" then return end
  if not (SettingsPanel and type(SettingsPanel.GetLayout) == "function") then return end
  pcall(function()
    local layout = SettingsPanel:GetLayout(category)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
  end)
end

function settings.init()
  if category then return end
  if type(Settings) ~= "table" then return end
  if type(Settings.RegisterVerticalLayoutCategory) ~= "function" then return end
  if type(ns.db) ~= "table" then return end
  category = Settings.RegisterVerticalLayoutCategory("VocWarbank")
  Settings.RegisterAddOnCategory(category)
  dropdown("priceSource", "Price source", optionsFrom(settings.priceOptions),
    "Where item values come from. Auto takes the first installed: "
    .. "Auctionator, TradeSkillMaster, Oribos Exchange, then vendor prices.",
    function() ns.providers.init() changed() end)
  dropdown("inventorySource", "Warbank source", optionsFrom(settings.inventoryOptions),
    "Who reads the warband bank. Syndicator sees it from anywhere; "
    .. "the Blizzard API only while the bank is open.")
  dropdown("scope", "Scope", optionsFrom(settings.scopeOptions),
    "What the window scans: bags, the character bank, the warband bank, or all three.")
  dropdown("ahThreshold", "Auction threshold", settings.thresholdOptions,
    "Bind-on-equip gear worth more than this is marked Sell instead of Vendor. "
    .. "Any other value: /vw threshold <gold>.")
  checkbox("autoOpenVendor", "Open automatically at vendors",
    "Pop the window up beside the merchant, filtered to Vendor.")
  checkbox("autoOpenAuction", "Open automatically at the auction house",
    "Pop the window up beside the auction house.")
  note("More on the slash line: /vw help")
end

function settings.open()
  local ok = category ~= nil
    and pcall(function() Settings.OpenToCategory(category:GetID()) end)
  if not ok then ns.say("open Settings > AddOns > VocWarbank") end
end
