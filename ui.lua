local name, ns = ...
local ui = {}
ns.ui = ui

local ICON_SIZE = 36
local PITCH = 40
local COLS = 14
local HEAD_H = 20

local ACTIONABLE = {
  sell = true, disenchant = true, vendor = true,
  trash = true, destroy = true,
}

local VERDICT_LABEL = {
  keep = "Keep", sell = "Sell", disenchant = "Disenchant",
  vendor = "Vendor", trash = "Trash", destroy = "Destroy",
}

local VERDICT_COLOR = {
  keep = { 0.1, 0.9, 0.1 }, sell = { 1, 0.85, 0 },
  disenchant = { 0.2, 0.6, 1 }, vendor = { 0.7, 0.7, 0.7 },
  trash = { 1, 0.4, 0.1 }, destroy = { 0.7, 0.1, 0.1 },
}

local QUALITY_COLOR = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
  [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
  [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

local CATEGORY_LABEL = {
  [0] = "Consumables", [1] = "Containers", [2] = "Weapons", [3] = "Gems",
  [4] = "Armor", [5] = "Reagents", [6] = "Projectiles", [7] = "Trade Goods",
  [8] = "Enhancements", [9] = "Recipes", [12] = "Quest Items", [15] = "Miscellaneous",
}
local CATEGORY_ORDER = { 2, 4, 0, 7, 5, 3, 8, 9, 1, 12, 15 }
local EXP_LABEL = {
  midnight = "Midnight", tww = "The War Within", df = "Dragonflight",
  sl = "Shadowlands", bfa = "Battle for Azeroth", legion = "Legion",
  wod = "Draenor", mop = "Pandaria", cata = "Cataclysm",
  wotlk = "Wrath", tbc = "Burning Crusade", classic = "Classic",
}
local EXP_ORDER = {
  "midnight", "tww", "df", "sl", "bfa", "legion",
  "wod", "mop", "cata", "wotlk", "tbc", "classic",
}

local TAB_WIDTH = {
  all = 44, keep = 56, sell = 48, disenchant = 88,
  vendor = 62, trash = 56, destroy = 66,
}

-- Pure helpers. Public so macros and tests can reuse them. ---------------
function ui.formatGold(copper)
  if copper == nil then return "?" end
  if copper >= 10000 then
    local grouped = (tostring(math.floor(copper / 10000)):reverse():gsub("(%d%d%d)", "%1,"))
    return grouped:reverse():gsub("^,", "") .. "g"
  elseif copper >= 100 then
    return math.floor(copper / 100) .. "s"
  else
    return math.floor(copper) .. "c"
  end
end

function ui.linkName(link)
  if not link then return "Unknown item" end
  local color = link:match("^|c(%x%x%x%x%x%x%x%x)")
  local text = link:match("%[(.-)%]")
  if color and text then return "|c" .. color .. text .. "|r" end
  return text or link
end

function ui.entryKey(entry)
  local item = entry.item
  return (item.scope or "?") .. ":" .. (item.bag or "?") .. ":" .. (item.slot or "?")
end

-- Sections for the grid. mode is "category" or "expansion", filter is
-- "all" or a verdict. getExpansion maps itemID -> expansion key.
function ui.buildSections(ranked, mode, getExpansion, filter)
  local buckets, seen = {}, {}
  for _, entry in ipairs(ranked) do
    if filter == "all" or entry.verdict == filter then
      local key, label
      if mode == "expansion" then
        key = entry.item.itemID and getExpansion(entry.item.itemID) or nil
        label = (key and EXP_LABEL[key]) or "Unknown"
        key = key or "unknown"
      else
        local classID = entry.detail and entry.detail.classID
        key = (classID ~= nil and CATEGORY_LABEL[classID]) and classID or "misc"
        if classID == nil then key = "other" end
        label = (key == "misc" and "Miscellaneous") or (key == "other" and "Other")
          or CATEGORY_LABEL[key]
      end
      if not buckets[key] then buckets[key] = {} seen[#seen + 1] = key end
      buckets[key].label = buckets[key].label or label
      buckets[key][#buckets[key] + 1] = entry
    end
  end
  local order = mode == "expansion" and EXP_ORDER or CATEGORY_ORDER
  local sections, done = {}, {}
  for _, key in ipairs(order) do
    if buckets[key] then
      sections[#sections + 1] = { label = buckets[key].label, entries = buckets[key] }
      done[key] = true
    end
  end
  for _, key in ipairs(seen) do
    if not done[key] then
      sections[#sections + 1] = { label = buckets[key].label, entries = buckets[key] }
    end
  end
  return sections
end

-- Dry-run totals over the selected entries. Keeps have no action, so
-- they count separately instead of inflating the queue.
function ui.computeSelection(ranked, selected)
  local queued, keepCount = {}, 0
  local totals = { items = 0, slots = 0, gold = 0, groups = {} }
  for _, entry in ipairs(ranked) do
    if selected[ui.entryKey(entry)] then
      if ACTIONABLE[entry.verdict] then
        queued[#queued + 1] = entry
        totals.slots = totals.slots + 1
        totals.items = totals.items + (entry.item.count or 1)
        totals.gold = totals.gold + (entry.value or 0)
        totals.groups[entry.verdict] = (totals.groups[entry.verdict] or 0) + 1
      else
        keepCount = keepCount + 1
      end
    end
  end
  return queued, totals, keepCount
end

-- Window state ------------------------------------------------------------
local window, headerStats, headerSource, scroll, child
local footer, footerGroups, emptyNote, closeBtn
local iconPool, headPool, tabPool, buttons = {}, {}, {}, {}
local groupButtons = {}
local lastRanked, lastSections = {}, {}
local lastQueued, lastTotals, lastKeeps = {}, { items = 0, slots = 0, gold = 0, groups = {} }, 0
local selected = {}
local groupMode, filter = "category", "all"
local merchantOpen = false

local function verdictLabel(v) return VERDICT_LABEL[v] or v end

-- The theme engine (theme.lua) owns every look decision. Widgets just
-- announce themselves as they are created; the engine styles them for
-- the current look and re-styles them wholesale on look changes.
local function getIcon(i)
  local r = iconPool[i]
  if r then return r end
  local f = CreateFrame("Button", nil, child)
  f:SetSize(ICON_SIZE, ICON_SIZE)
  local sel = f:CreateTexture(nil, "BACKGROUND")
  sel:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
  sel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
  sel:SetColorTexture(1, 0.82, 0, 0.9)
  sel:Hide()
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.5, 0.5, 0.5, 1)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
  icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  local dot = f:CreateTexture(nil, "OVERLAY")
  dot:SetSize(8, 8)
  dot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3, 3)
  local count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 1)
  local level = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  level:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -1)
  r = { button = f, sel = sel, bg = bg, icon = icon, dot = dot,
    count = count, level = level, key = nil, entry = nil }
  f:SetScript("OnClick", function() ui.toggleKey(r.key) end)
  f:SetScript("OnEnter", function(self)
    local entry = r.entry
    if not entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(entry.item.link)
    GameTooltip:AddLine(verdictLabel(entry.verdict) .. " — " .. (entry.reason or ""), 1, 1, 1)
    if entry.value then
      GameTooltip:AddLine("Value: " .. ui.formatGold(entry.value), 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  iconPool[i] = r
  ns.theme.styleIcon(r)
  return r
end

local function getHeader(i)
  local r = headPool[i]
  if r then return r end
  local f = CreateFrame("Button", nil, child)
  f:SetHeight(HEAD_H)
  local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("LEFT", f, "LEFT", 2, 0)
  r = { button = f, label = label, entries = nil }
  f:SetScript("OnClick", function() ui.toggleSection(r.entries) end)
  headPool[i] = r
  ns.theme.styleHeader(r)
  return r
end

local function paintIcon(r, entry)
  local item, detail = entry.item, entry.detail or {}
  r.key = ui.entryKey(entry)
  r.entry = entry
  local iconID = item.itemID and C_Item.GetItemIconByID(item.itemID) or nil
  if iconID then r.icon:SetTexture(iconID)
  else r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
  local q = QUALITY_COLOR[detail.quality] or QUALITY_COLOR[1]
  ns.theme.paintIcon(r, detail.quality or 1, q)
  local v = VERDICT_COLOR[entry.verdict] or VERDICT_COLOR.keep
  r.dot:SetColorTexture(v[1], v[2], v[3], 1)
  if (item.count or 1) > 1 then r.count:SetText(item.count) r.count:Show()
  else r.count:Hide() end
  if (detail.classID == 2 or detail.classID == 4) and (detail.level or 0) > 1 then
    r.level:SetText(detail.level) r.level:Show()
  else r.level:Hide() end
  if selected[r.key] then r.sel:Show() else r.sel:Hide() end
end

local function setButton(b, label, n, ctxOK)
  b:SetText(label .. " (" .. n .. ")")
  if n > 0 and ctxOK then b:Enable() else b:Disable() end
end

local function updateTexts()
  local items, slots, gold = 0, 0, 0
  for _, entry in ipairs(lastRanked) do
    items = items + (entry.item.count or 1)
    slots = slots + 1
    gold = gold + (entry.value or 0)
  end
  headerStats:SetText(items .. " items  •  " .. slots .. " slots  •  ~" .. ui.formatGold(gold))
  headerSource:SetText("Source: " .. (ns.activeSource or "none"))
  local t, g = lastTotals, lastTotals.groups
  local sel = "Selected: " .. t.items .. " items, " .. t.slots .. " slots, ~" .. ui.formatGold(t.gold)
  if lastKeeps > 0 then sel = sel .. " (+" .. lastKeeps .. " keeps)" end
  footer:SetText(sel)
  footerGroups:SetText("sell " .. (g.sell or 0) .. "  •  disenchant " .. (g.disenchant or 0)
    .. "  •  vendor " .. (g.vendor or 0) .. "  •  trash " .. ((g.trash or 0) + (g.destroy or 0)))
  setButton(buttons.vendor, "Vendor", g.vendor or 0, merchantOpen)
  setButton(buttons.disenchant, "Disenchant", g.disenchant or 0, true)
  setButton(buttons.sell, "Sell", g.sell or 0, true)
  setButton(buttons.trash, "Trash", (g.trash or 0) + (g.destroy or 0), true)
end

local function expansionGetter()
  local provider = ns.providers.get()
  return function(itemID)
    return provider and provider.GetExpansion(itemID) or nil
  end
end

local render -- forward declaration; tab buttons call it
local function refreshTabs()
  local present, seen = { "all" }, { all = true }
  for _, entry in ipairs(lastRanked) do
    if not seen[entry.verdict] then
      seen[entry.verdict] = true
      present[#present + 1] = entry.verdict
    end
  end
  table.sort(present, function(a, b)
    if a == "all" then return true end
    if b == "all" then return false end
    local order = {}
    for i, v in ipairs(ns.ranking.verdictOrder) do order[v] = i end
    return (order[a] or 99) < (order[b] or 99)
  end)
  local x = 12
  for i, v in ipairs(present) do
    local b = tabPool[i]
    if not b then
      b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
      b:SetHeight(20)
      ns.theme.styleButton(b, true)
      tabPool[i] = b
    end
    local label = v == "all" and "All" or verdictLabel(v)
    if v == filter then label = "[ " .. label .. " ]" end
    b:SetText(label)
    b:SetWidth(TAB_WIDTH[v] or 64)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", window, "TOPLEFT", x, -76)
    b:SetScript("OnClick", function() filter = v render(lastRanked) end)
    b:Show()
    x = x + (TAB_WIDTH[v] or 64) + 4
  end
  for i = #present + 1, #tabPool do tabPool[i]:Hide() end
end

function render(ranked)
  lastRanked = ranked or {}
  lastSections = ui.buildSections(lastRanked, groupMode, expansionGetter(), filter)
  local hi, ii, y = 0, 0, 0
  for _, sec in ipairs(lastSections) do
    hi = hi + 1
    local h = getHeader(hi)
    h.entries = sec.entries
    h.button:ClearAllPoints()
    h.button:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    h.button:SetWidth(560)
    h.button:Show()
    h.label:SetText(sec.label .. " (" .. #sec.entries .. ")")
    y = y + HEAD_H
    for j, entry in ipairs(sec.entries) do
      ii = ii + 1
      local r = getIcon(ii)
      paintIcon(r, entry)
      local col = (j - 1) % COLS
      local row = math.floor((j - 1) / COLS)
      r.button:ClearAllPoints()
      r.button:SetPoint("TOPLEFT", child, "TOPLEFT", 4 + col * PITCH, -(y + row * PITCH))
      r.button:Show()
    end
    y = y + math.ceil(#sec.entries / COLS) * PITCH + 6
  end
  for i = ii + 1, #iconPool do iconPool[i].button:Hide() end
  for i = hi + 1, #headPool do headPool[i].button:Hide() end
  child:SetHeight(math.max(y, 1))
  scroll:UpdateScrollChildRect()
  if #lastSections == 0 then emptyNote:Show() else emptyNote:Hide() end
  refreshTabs()
  local active = groupMode == "category" and 1 or 2
  groupButtons[1]:SetText(active == 1 and "[ Category ]" or "Category")
  groupButtons[2]:SetText(active == 2 and "[ Expansion ]" or "Expansion")
  lastQueued, lastTotals, lastKeeps = ui.computeSelection(lastRanked, selected)
  updateTexts()
end

-- Actions. Each runs from a button click (a hardware event), which is
-- what makes the protected container calls legal. ------------------------
local function selectedWhere(pred)
  local out = {}
  for _, entry in ipairs(lastRanked) do
    if selected[ui.entryKey(entry)] and pred(entry) then out[#out + 1] = entry end
  end
  return out
end

function ui.vendorQueued(list)
  if not (MerchantFrame and MerchantFrame:IsShown()) then return 0 end
  local n, skipped = 0, 0
  list = list or selectedWhere(function(e) return e.verdict == "vendor" end)
  for _, entry in ipairs(list) do
    local item = entry.item
    if item.scope == "bags" and type(item.bag) == "number" and type(item.slot) == "number" then
      C_Container.UseContainerItem(item.bag, item.slot)
      n = n + 1
    else
      skipped = skipped + 1
    end
  end
  if skipped > 0 then
    print("Warbank Audit: skipped " .. skipped .. " items outside bags (not supported yet).")
  end
  ui.rescan()
  return n
end

function ui.disenchantQueued(list)
  list = list or selectedWhere(function(e) return e.verdict == "disenchant" end)
  if #list == 0 then return 0 end
  -- TODO: one-click handling needs the enchanter/mail flow verified in
  -- game (see SPEC.md open questions). For now, prepare the package.
  local who = ns.config.get("enchanter")
  if who and who ~= "" then
    print("Warbank Audit: " .. #list .. " items prepared for " .. who
      .. " — open a mailbox to send them. (One-click mail coming in a later version.)")
  else
    print("Warbank Audit: " .. #list .. " items to disenchant — set your enchanter with"
      .. " /ww enchanter <name>, or disenchant them directly.")
  end
  for _, entry in ipairs(list) do print("  " .. ui.linkName(entry.item.link)) end
  return #list
end

function ui.sellQueued(list)
  list = list or selectedWhere(function(e) return e.verdict == "sell" end)
  if #list == 0 then return 0 end
  local helper = nil
  if C_AddOns.IsAddOnLoaded("TradeSkillMaster") then helper = "TSM"
  elseif C_AddOns.IsAddOnLoaded("Auctionator") then helper = "Auctionator" end
  if helper then
    print("Warbank Audit: " .. #list .. " items ready — list them in " .. helper
      .. ". (Automatic handoff coming in a later version.)")
  else
    print("Warbank Audit: " .. #list .. " items flagged for manual listing (no auction addon found).")
  end
  for _, entry in ipairs(list) do print("  " .. ui.linkName(entry.item.link)) end
  return #list
end

function ui.destroyQueued(list)
  local n, skipped, pending = 0, 0, false
  list = list or lastQueued
  for _, entry in ipairs(list) do
    if entry.verdict == "trash" or entry.verdict == "destroy" then
      local item = entry.item
      if item.scope ~= "bags" or type(item.bag) ~= "number" or type(item.slot) ~= "number" then
        skipped = skipped + 1
      else
        C_Container.PickupContainerItem(item.bag, item.slot)
        DeleteCursorItem()
        -- Blizzard confirms quest and high-quality items itself. A
        -- pending confirm leaves the item on the cursor, so stop the
        -- batch there instead of swapping it into another slot.
        if GetCursorInfo() ~= nil then pending = true break end
        n = n + 1
      end
    end
  end
  ui.rescan()
  if pending then
    print("Warbank Audit: paused for Blizzard's confirmation — click Trash again to continue"
      .. " (put the item back first if you cancelled).")
  elseif skipped > 0 then
    print("Warbank Audit: destroyed " .. n .. ", skipped " .. skipped .. " outside bags.")
  else
    print("Warbank Audit: destroyed " .. n .. " items.")
  end
  return n
end

local function confirmTrash()
  local n = 0
  for _, entry in ipairs(lastQueued) do
    if entry.verdict == "trash" or entry.verdict == "destroy" then n = n + 1 end
  end
  if n == 0 then return end
  StaticPopup_Show("WARBANKAUDIT_CONFIRM_TRASH", n)
end

function ui.toggleKey(key)
  if not key then return end
  if selected[key] then selected[key] = nil else selected[key] = true end
  render(lastRanked)
end

function ui.toggleSection(entries)
  if not entries or #entries == 0 then return end
  local all = true
  for _, entry in ipairs(entries) do
    if not selected[ui.entryKey(entry)] then all = false break end
  end
  for _, entry in ipairs(entries) do
    if all then selected[ui.entryKey(entry)] = nil
    else selected[ui.entryKey(entry)] = true end
  end
  render(lastRanked)
end

function ui.selectShown()
  for _, sec in ipairs(lastSections) do
    for _, entry in ipairs(sec.entries) do selected[ui.entryKey(entry)] = true end
  end
  render(lastRanked)
end

function ui.clearSelection()
  selected = {}
  render(lastRanked)
end

function ui.rescan()
  if not window then ui.init() end
  selected = {}
  merchantOpen = MerchantFrame and MerchantFrame:IsShown() or false
  local provider = ns.providers.get()
  local ranked = ns.ranking.rank(ns.scanner.scan(ns.config.get("scope")))
  for _, entry in ipairs(ranked) do
    local price = provider and provider.GetMarketValue(entry.item.link) or nil
    entry.value = price and price * (entry.item.count or 1) or nil
  end
  ns.activeSource = ns.providers.describe()
  ns.theme.decide()
  render(ranked)
  return ranked
end

function ui.init()
  if window then return end
  window = CreateFrame("Frame", "WarbankAuditWindow", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(660, 640)
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "WarbankAuditWindow") end
  window.TitleText:SetText("Warbank Audit")
  closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() window:Hide() end)
  headerStats = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  headerStats:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -30)
  headerSource = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  headerSource:SetPoint("TOPRIGHT", window, "TOPRIGHT", -44, -30)
  local modes = { "category", "expansion" }
  local labels = { "Category", "Expansion" }
  for i = 1, 2 do
    local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    b:SetSize(i == 1 and 78 or 82, 20)
    b:SetPoint("TOPLEFT", window, "TOPLEFT", i == 1 and 12 or 94, -52)
    b:SetScript("OnClick", function() groupMode = modes[i] render(lastRanked) end)
    ns.theme.styleButton(b, true)
    groupButtons[i] = b
  end
  local selBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  selBtn:SetSize(100, 20)
  selBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -134, -52)
  selBtn:SetText("Select shown")
  selBtn:SetScript("OnClick", function() ui.selectShown() end)
  ns.theme.styleButton(selBtn, true)
  local clrBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  clrBtn:SetSize(60, 20)
  clrBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -70, -52)
  clrBtn:SetText("Clear")
  clrBtn:SetScript("OnClick", function() ui.clearSelection() end)
  ns.theme.styleButton(clrBtn, true)
  scroll = CreateFrame("ScrollFrame", "WarbankAuditScroll", window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -100)
  scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, 86)
  child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(580)
  child:SetHeight(1)
  scroll:SetScrollChild(child)
  emptyNote = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  emptyNote:SetPoint("TOP", scroll, "TOP", 0, -40)
  emptyNote:SetText("No items match this filter.")
  emptyNote:Hide()
  footer = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 64)
  footer:SetWidth(620)
  footer:SetJustifyH("LEFT")
  footerGroups = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  footerGroups:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 50)
  footerGroups:SetWidth(620)
  footerGroups:SetJustifyH("LEFT")
  local defs = {
    { "vendor", 16, function() ui.vendorQueued() end },
    { "disenchant", 134, function() ui.disenchantQueued() end },
    { "sell", 252, function() ui.sellQueued() end },
    { "trash", 370, function() confirmTrash() end },
  }
  for _, def in ipairs(defs) do
    local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    b:SetSize(112, 22)
    b:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", def[2], 16)
    b:SetScript("OnClick", def[3])
    ns.theme.styleButton(b, true)
    buttons[def[1]] = b
  end
  StaticPopupDialogs["WARBANKAUDIT_CONFIRM_TRASH"] = {
    text = "Destroy %d queued items? This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ui.destroyQueued() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  local ctx = CreateFrame("Frame")
  ctx:RegisterEvent("MERCHANT_SHOW")
  ctx:RegisterEvent("MERCHANT_CLOSED")
  ctx:SetScript("OnEvent", function(_, event)
    merchantOpen = (event == "MERCHANT_SHOW")
    if window:IsShown() then updateTexts() end
  end)
  ns.theme.init({
    window = window, close = closeBtn, scroll = scroll,
    title = window.TitleText, headPool = headPool, iconPool = iconPool,
    texts = { headerStats, headerSource, footer, footerGroups, emptyNote },
    repaint = function()
      for i = 1, #iconPool do
        local r = iconPool[i]
        if r.button:IsShown() and r.entry then paintIcon(r, r.entry) end
      end
    end,
  })
  local login = CreateFrame("Frame")
  login:RegisterEvent("PLAYER_LOGIN")
  login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ns.theme.decide()
  end)
  ns.theme.decide()
  if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("WarbankAudit", ns.theme.onEUISkin)
  end
end

function ui.toggle()
  if not window then ui.init() end
  if window:IsShown() then window:Hide()
  else ui.rescan() window:Show() end
end

function ui.isOpen()
  return window and window:IsShown() or false
end

function ui.getSelection() return lastQueued, lastTotals, lastKeeps end
