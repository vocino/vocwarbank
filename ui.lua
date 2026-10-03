local name, ns = ...
local ui = {}
ns.ui = ui

local ROW_H = 20
local HEAD_H = 18
local LINE_H = 6

local ACTIONABLE = {
  sell = true, disenchant = true, vendor = true,
  trash = true, destroy = true,
}

local VERDICT_LABEL = {
  keep = "Keep", sell = "Sell", disenchant = "Disenchant",
  vendor = "Vendor", trash = "Trash", destroy = "Destroy",
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

function ui.group(ranked)
  local byVerdict, seen = {}, {}
  for _, entry in ipairs(ranked) do
    local v = entry.verdict or "destroy"
    if not byVerdict[v] then byVerdict[v] = {}; seen[#seen + 1] = v end
    byVerdict[v][#byVerdict[v] + 1] = entry
  end
  local sections, done = {}, {}
  for _, v in ipairs(ns.ranking.verdictOrder) do
    if byVerdict[v] then
      sections[#sections + 1] = { verdict = v, rows = byVerdict[v] }
      done[v] = true
    end
  end
  for _, v in ipairs(seen) do
    if not done[v] then sections[#sections + 1] = { verdict = v, rows = byVerdict[v] } end
  end
  return sections
end

function ui.flatten(sections)
  local flat = {}
  for _, sec in ipairs(sections) do
    flat[#flat + 1] = { kind = "header", verdict = sec.verdict, count = #sec.rows }
    for _, entry in ipairs(sec.rows) do
      flat[#flat + 1] = { kind = "row", entry = entry }
    end
  end
  return flat
end

local function nodeHeight(node)
  return node.kind == "header" and HEAD_H or ROW_H
end

-- How many leading entries sit fully above a content offset (px).
function ui.indexAtOffset(flat, offset)
  local y = 0
  for i, node in ipairs(flat) do
    y = y + nodeHeight(node)
    if offset < y then return i - 1 end
  end
  return #flat
end

-- Entries below the cutoff that have an action, plus dry-run totals.
function ui.computeQueue(flat, cutoff)
  local queued = {}
  local totals = { items = 0, slots = 0, gold = 0, groups = {} }
  for i = cutoff + 1, #flat do
    local node = flat[i]
    if node.kind == "row" then
      local entry = node.entry
      if ACTIONABLE[entry.verdict] then
        queued[#queued + 1] = entry
        totals.slots = totals.slots + 1
        totals.items = totals.items + (entry.item.count or 1)
        totals.gold = totals.gold + (entry.value or 0)
        totals.groups[entry.verdict] = (totals.groups[entry.verdict] or 0) + 1
      end
    end
  end
  return queued, totals
end

-- Window state ------------------------------------------------------------
local window, headerStats, headerSource, scroll, child, line
local footer, footerGroups
local rowPool, headPool, buttons = {}, {}, {}
local lastRanked, lastFlat = {}, {}
local lastQueued, lastTotals = {}, { items = 0, slots = 0, gold = 0, groups = {} }
local cutoff = 0 -- leading flat entries above the line; the rest is queued
local merchantOpen = false

local function verdictLabel(v) return VERDICT_LABEL[v] or v end

local function getRow(i)
  local r = rowPool[i]
  if r then return r end
  local f = CreateFrame("Button", nil, child)
  f:SetSize(460, ROW_H)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("LEFT", f, "LEFT", 2, 0)
  local nm = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  nm:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  nm:SetWidth(210)
  nm:SetJustifyH("LEFT")
  local count = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  count:SetPoint("LEFT", nm, "RIGHT", 4, 0)
  count:SetWidth(40)
  count:SetJustifyH("RIGHT")
  local value = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  value:SetPoint("LEFT", count, "RIGHT", 4, 0)
  value:SetWidth(70)
  value:SetJustifyH("RIGHT")
  local reason = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  reason:SetPoint("LEFT", value, "RIGHT", 4, 0)
  reason:SetWidth(90)
  reason:SetJustifyH("LEFT")
  r = { frame = f, icon = icon, name = nm, count = count, value = value, reason = reason }
  rowPool[i] = r
  return r
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
  footer:SetText("Below the line: " .. t.items .. " items, " .. t.slots
    .. " slots, ~" .. ui.formatGold(t.gold))
  footerGroups:SetText("sell " .. (g.sell or 0) .. "  •  disenchant " .. (g.disenchant or 0)
    .. "  •  vendor " .. (g.vendor or 0) .. "  •  trash " .. ((g.trash or 0) + (g.destroy or 0)))
  setButton(buttons.vendor, "Vendor", g.vendor or 0, merchantOpen)
  setButton(buttons.disenchant, "Disenchant", g.disenchant or 0, true)
  setButton(buttons.sell, "Sell", g.sell or 0, true)
  setButton(buttons.trash, "Trash", (g.trash or 0) + (g.destroy or 0), true)
end

local function render(ranked)
  lastRanked = ranked or {}
  lastFlat = ui.flatten(ui.group(lastRanked))
  if cutoff > #lastFlat then cutoff = #lastFlat end
  lastQueued, lastTotals = ui.computeQueue(lastFlat, cutoff)
  local ri, hi, y = 0, 0, 0
  for _, node in ipairs(lastFlat) do
    if node.kind == "header" then
      hi = hi + 1
      local h = headPool[hi]
      if not h then
        h = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetWidth(460)
        h:SetJustifyH("LEFT")
        headPool[hi] = h
      end
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
      h:SetText(verdictLabel(node.verdict) .. " (" .. node.count .. ")")
      h:Show()
      y = y + HEAD_H
    else
      ri = ri + 1
      local r = getRow(ri)
      local entry, item = node.entry, node.entry.item
      r.frame:ClearAllPoints()
      r.frame:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
      r.frame:Show()
      local iconID = item.itemID and C_Item.GetItemIconByID(item.itemID) or nil
      if iconID then r.icon:SetTexture(iconID)
      else r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
      r.name:SetText(ui.linkName(item.link))
      r.count:SetText("x" .. (item.count or 1))
      r.value:SetText(ui.formatGold(entry.value))
      r.reason:SetText(entry.reason or "")
      y = y + ROW_H
    end
  end
  for i = ri + 1, #rowPool do rowPool[i].frame:Hide() end
  for i = hi + 1, #headPool do headPool[i]:Hide() end
  child:SetHeight(math.max(y, 1))
  scroll:UpdateScrollChildRect()
  local ly = 0
  for i = 1, cutoff do ly = ly + nodeHeight(lastFlat[i]) end
  line:ClearAllPoints()
  line:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -ly + LINE_H / 2)
  line:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -ly + LINE_H / 2)
  line:Show()
  updateTexts()
end

local function trackLine(self)
  if not IsMouseButtonDown("LeftButton") then
    self:SetScript("OnUpdate", nil)
    return
  end
  local _, cursorY = GetCursorPosition()
  local scale = child:GetEffectiveScale()
  ui.setCutoff(ui.indexAtOffset(lastFlat, child:GetTop() * scale - cursorY))
end

-- Actions. Each runs from a button click (a hardware event), which is
-- what makes the protected container calls legal. ------------------------
local function queuedWhere(pred)
  local out = {}
  for _, entry in ipairs(lastQueued) do
    if pred(entry) then out[#out + 1] = entry end
  end
  return out
end

function ui.vendorQueued(list)
  if not (MerchantFrame and MerchantFrame:IsShown()) then return 0 end
  local n, skipped = 0, 0
  list = list or queuedWhere(function(e) return e.verdict == "vendor" end)
  for _, entry in ipairs(list) do
    local item = entry.item
    if item.scope == "bags" then
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
  list = list or queuedWhere(function(e) return e.verdict == "disenchant" end)
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
  list = list or queuedWhere(function(e) return e.verdict == "sell" end)
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
      if item.scope ~= "bags" then
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

function ui.rescan()
  if not window then ui.init() end
  merchantOpen = MerchantFrame and MerchantFrame:IsShown() or false
  local provider = ns.providers.get()
  local ranked = ns.ranking.rank(ns.scanner.scan(ns.config.get("scope")))
  for _, entry in ipairs(ranked) do
    local price = provider and provider.GetMarketValue(entry.item.link) or nil
    entry.value = price and price * (entry.item.count or 1) or nil
  end
  render(ranked)
  return ranked
end

function ui.init()
  if window then return end
  window = CreateFrame("Frame", "WarbankAuditWindow", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(540, 580)
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "WarbankAuditWindow") end
  window.TitleText:SetText("Warbank Audit")
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() window:Hide() end)
  headerStats = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  headerStats:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -30)
  headerSource = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  headerSource:SetPoint("TOPRIGHT", window, "TOPRIGHT", -44, -30)
  scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -52)
  scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, 86)
  child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(470)
  child:SetHeight(1)
  scroll:SetScrollChild(child)
  line = CreateFrame("Button", nil, child)
  line:SetHeight(LINE_H)
  local bar = line:CreateTexture(nil, "OVERLAY")
  bar:SetAllPoints()
  bar:SetColorTexture(1, 0.82, 0, 0.9)
  line:SetScript("OnMouseDown", function(self) self:SetScript("OnUpdate", trackLine) end)
  line:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  footer = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 64)
  footer:SetWidth(508)
  footer:SetJustifyH("LEFT")
  footerGroups = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  footerGroups:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 50)
  footerGroups:SetWidth(508)
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
end

function ui.toggle()
  if not window then ui.init() end
  if window:IsShown() then window:Hide()
  else ui.rescan() window:Show() end
end

function ui.isOpen()
  return window and window:IsShown() or false
end

function ui.setCutoff(index)
  cutoff = math.max(0, math.min(index or 0, #lastFlat))
  if window then render(lastRanked) end
end

function ui.getCutoff() return cutoff end

function ui.getQueue() return lastQueued, lastTotals end
