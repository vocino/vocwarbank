local name, ns = ...
local ui = {}
ns.ui = ui

local ICON_SIZE = 36
local PITCH = 40
local COLS = 14
local HEAD_H = 20

local ACTIONABLE = {
  sell = true, disenchant = true, vendor = true,
  trash = true, destroy = true, use = true,
}

local VERDICT_LABEL = {
  keep = "Keep", sell = "Sell", disenchant = "Disenchant",
  vendor = "Vendor", trash = "Trash", destroy = "Destroy", use = "Use",
}

local VERDICT_COLOR = {
  keep = { 0.1, 0.9, 0.1 }, sell = { 1, 0.85, 0 },
  disenchant = { 0.2, 0.6, 1 }, vendor = { 0.7, 0.7, 0.7 },
  trash = { 1, 0.4, 0.1 }, destroy = { 0.7, 0.1, 0.1 },
  use = { 0.75, 0.5, 1 },
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
  [17] = "Battle Pets", [19] = "Profession", [20] = "Housing",
}
local CATEGORY_ORDER = { 2, 4, 0, 7, 5, 3, 8, 9, 1, 12, 15, 17, 19, 20 }
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
  vendor = 62, trash = 56, destroy = 66, use = 48,
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
  return (item.scope or "?") .. ":" .. (item.bag or item.tab or "?") .. ":" .. (item.slot or item.index or "?")
end

-- Group specs. Priority is display order (lower rank wins); pins always
-- lead and the catch-all always trails, Baganator-style first-match
-- consumption: each entry lands in exactly one section.
local function mainKeyFor(entry, mode, getExpansion)
  if mode == "expansion" then
    return entry.item.itemID and getExpansion(entry.item.itemID) or nil
  end
  local classID = entry.detail and entry.detail.classID
  return (classID ~= nil and CATEGORY_LABEL[classID]) and classID or nil
end

local function mainLabel(mode, key)
  if mode == "expansion" then return EXP_LABEL[key] end
  return CATEGORY_LABEL[key]
end

local function subKeyFor(entry, mode, getExpansion)
  if mode == "expansion" then
    local classID = entry.detail and entry.detail.classID
    return (classID ~= nil and CATEGORY_LABEL[classID]) and classID or nil
  end
  return entry.item.itemID and getExpansion(entry.item.itemID) or nil
end

local function subLabel(mode, key)
  if mode == "expansion" then return CATEGORY_LABEL[key] end
  return EXP_LABEL[key]
end

local SORT_LABEL = { off = "Off", quality = "Quality", value = "Value", name = "Name" }
local SORT_MODES = { "off", "quality", "value", "name" }

function ui.searchMatch(nameLower, query)
  return query == "" or (nameLower and nameLower:find(query, 1, true) ~= nil)
end

-- Deterministic in-section sort. mode is off/quality/value/name;
-- reverse flips the comparator but keeps the stability tiebreak.
function ui.sortEntries(entries, mode, reverse)
  mode = mode or "off"
  local pos, names = {}, {}
  for i, e in ipairs(entries) do
    pos[e] = i
    names[e] = ((e.item.link or ""):match("%[(.-)%]") or e.item.link or ""):lower()
  end
  local function quality(e)
    local d = e.detail or {}
    return d.quality or e.item.quality or -1
  end
  local function ordered(a, b)
    if mode == "quality" then
      local qa, qb = quality(a), quality(b)
      if qa ~= qb then return qa > qb end
      local la, lb = (a.detail or {}).level or 0, (b.detail or {}).level or 0
      if la ~= lb then return la > lb end
      local va, vb = a.value or -1, b.value or -1
      if va ~= vb then return va > vb end
    elseif mode == "value" then
      local va, vb = a.value or -1, b.value or -1
      if va ~= vb then return va > vb end
      local qa, qb = quality(a), quality(b)
      if qa ~= qb then return qa > qb end
    elseif mode == "name" then
      -- falls to the name compare below
    else
      return pos[a] < pos[b]
    end
    if names[a] ~= names[b] then return names[a] < names[b] end
    return pos[a] < pos[b]
  end
  if reverse then
    table.sort(entries, function(a, b)
      if ordered(a, b) then return false end
      if ordered(b, a) then return true end
      return pos[a] < pos[b]
    end)
  else
    table.sort(entries, function(a, b) return ordered(a, b) end)
  end
  return entries
end

-- Sections for the grid. mode is "category" or "expansion", filter is
-- "all" or a verdict. getExpansion maps itemID -> expansion key. pins
-- is { never = {id=true}, always = {id=true} } or nil.
function ui.buildSections(ranked, mode, getExpansion, filter, pins)
  local order = mode == "expansion" and EXP_ORDER or CATEGORY_ORDER
  local rank = {}
  for i, key in ipairs(order) do rank[key] = i end
  local function sortKey(key)
    if key == "pinned:never" then return -2 end
    if key == "pinned:always" then return -1 end
    if key == "other" then return 1e9 end
    return rank[key] or 1e8
  end
  local mains, seen = {}, {}
  local function bucket(key)
    local b = mains[key]
    if not b then
      b = { key = key, entries = {} }
      mains[key] = b
      seen[#seen + 1] = key
    end
    return b
  end
  for _, entry in ipairs(ranked) do
    if filter == "all" or entry.verdict == filter then
      local id = entry.item.itemID
      local key
      if id and pins and pins.never[id] then key = "pinned:never"
      elseif id and pins and pins.always[id] then key = "pinned:always"
      else key = mainKeyFor(entry, mode, getExpansion) or "other" end
      local b = bucket(key)
      b.entries[#b.entries + 1] = entry
    end
  end
  local seenAt = {}
  for i, key in ipairs(seen) do seenAt[key] = i end
  table.sort(seen, function(a, b)
    local ra, rb = sortKey(a), sortKey(b)
    if ra ~= rb then return ra < rb end
    return seenAt[a] < seenAt[b]
  end)
  local subOrder = mode == "expansion" and CATEGORY_ORDER or EXP_ORDER
  local subRank = {}
  for i, key in ipairs(subOrder) do subRank[key] = i end
  local sections = {}
  for _, key in ipairs(seen) do
    local main = mains[key]
    local label
    if key == "pinned:never" then label = "Never Sell"
    elseif key == "pinned:always" then label = "Always Sell"
    elseif key == "other" then label = mode == "expansion" and "Unknown" or "Other"
    else label = mainLabel(mode, key) end
    local splittable = key ~= "other" and key ~= "pinned:never" and key ~= "pinned:always"
    if not splittable then
      sections[#sections + 1] = { key = mode .. ":" .. tostring(key), label = label, entries = main.entries }
    else
      -- Sub-split on the other axis when it actually divides the group.
      local subs, subSeen = {}, {}
      for _, entry in ipairs(main.entries) do
        local sk = subKeyFor(entry, mode, getExpansion) or "other"
        if not subs[sk] then subs[sk] = {} subSeen[#subSeen + 1] = sk end
        subs[sk][#subs[sk] + 1] = entry
      end
      if #subSeen < 2 then
        sections[#sections + 1] = { key = mode .. ":" .. tostring(key), label = label, entries = main.entries }
      else
        local subAt = {}
        for i, sk in ipairs(subSeen) do subAt[sk] = i end
        table.sort(subSeen, function(a, b)
          local ra, rb = subRank[a] or 1e9, subRank[b] or 1e9
          if ra ~= rb then return ra < rb end
          return subAt[a] < subAt[b]
        end)
        for _, sk in ipairs(subSeen) do
          local suffix = ""
          if sk ~= "other" then
            local sl = subLabel(mode, sk)
            if sl then suffix = ": " .. sl end
          end
          sections[#sections + 1] = {
            key = mode .. ":" .. tostring(key) .. ":" .. tostring(sk),
            label = label .. suffix,
            entries = subs[sk],
          }
        end
      end
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
local iconPool, headPool, tabPool -- CreateObjectPools, built in init
local buttons = {}
local sortBtn, searchBox, searchClear, searchHint
local searchText = ""
local poolReset = FramePool_HideAndClearAnchors or Pool_HideAndClearAnchors
  or function(_, f) f:Hide() f:ClearAllPoints() end
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
local render -- forward declaration; header buttons re-render on collapse

local function buildIcon(f)
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
  local r = { button = f, sel = sel, bg = bg, icon = icon, dot = dot,
    count = count, level = level, key = nil, entry = nil, searchName = "" }
  f._rec = r
  f.Icon, f.Dot, f.Sel = icon, dot, sel -- named so the EUI tile fade can keep them
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
  ns.theme.styleIcon(r)
  return r
end

local function acquireIcon()
  local f = iconPool:Acquire()
  return f._rec or buildIcon(f)
end

local function buildHeader(f)
  f:SetHeight(HEAD_H)
  local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("LEFT", f, "LEFT", 2, 0)
  local r = { button = f, label = label, key = nil, entries = nil }
  f._rec = r
  f:SetScript("OnClick", function()
    if IsShiftKeyDown() then ui.toggleSection(r.entries)
    else
      local collapsed = ns.config.get("collapsedGroups") or {}
      if collapsed[r.key] then collapsed[r.key] = nil else collapsed[r.key] = true end
      render(lastRanked)
    end
  end)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Click: collapse section")
    GameTooltip:AddLine("Shift-click: select section")
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ns.theme.styleHeader(r)
  return r
end

local function acquireHeader()
  local f = headPool:Acquire()
  return f._rec or buildHeader(f)
end

local function paintIcon(r, entry)
  local item, detail = entry.item, entry.detail or {}
  r.key = ui.entryKey(entry)
  r.entry = entry
  r.searchName = ((item.link or ""):match("%[(.-)%]") or item.link or ""):lower()
  local iconID = item.icon or (item.itemID and C_Item.GetItemIconByID(item.itemID)) or nil
  if iconID then r.icon:SetTexture(iconID)
  else r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
  local qual = detail.quality or item.quality or 1
  local q = QUALITY_COLOR[qual] or QUALITY_COLOR[1]
  ns.theme.paintIcon(r, qual, q)
  local v = VERDICT_COLOR[entry.verdict] or VERDICT_COLOR.keep
  r.dot:SetColorTexture(v[1], v[2], v[3], 1)
  if (item.count or 1) > 1 then r.count:SetText(item.count) r.count:Show()
  else r.count:Hide() end
  if (detail.classID == 2 or detail.classID == 4) and (detail.level or 0) > 1 then
    r.level:SetText(detail.level) r.level:Show()
  else r.level:Hide() end
  if selected[r.key] then r.sel:Show() else r.sel:Hide() end
  r.button:SetAlpha(ui.searchMatch(r.searchName, searchText) and 1 or 0.35)
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
  footerGroups:SetText("use " .. (g.use or 0) .. "  •  sell " .. (g.sell or 0) .. "  •  disenchant " .. (g.disenchant or 0)
    .. "  •  vendor " .. (g.vendor or 0) .. "  •  trash " .. ((g.trash or 0) + (g.destroy or 0)))
  setButton(buttons.use, "Use", g.use or 0, true)
  setButton(buttons.sell, "Sell", g.sell or 0, true)
  setButton(buttons.disenchant, "Disenchant", g.disenchant or 0, true)
  setButton(buttons.vendor, "Vendor", g.vendor or 0, merchantOpen)
  setButton(buttons.trash, "Trash", (g.trash or 0) + (g.destroy or 0), true)
end

local function expansionGetter()
  local provider = ns.providers.get()
  return function(itemID)
    return provider and provider.GetExpansion(itemID) or nil
  end
end

local function applySearch()
  if not iconPool then return end
  for b in iconPool:EnumerateActive() do
    local r = b._rec
    if r and r.entry then
      r.button:SetAlpha(ui.searchMatch(r.searchName, searchText) and 1 or 0.35)
    end
  end
end

local function updateSortButton(x)
  local mode = ns.config.get("sortMode") or "off"
  local rev = ns.config.get("sortReverse") and " (R)" or ""
  sortBtn:SetText("Sort: " .. (SORT_LABEL[mode] or mode) .. rev)
  sortBtn:ClearAllPoints()
  sortBtn:SetPoint("TOPLEFT", window, "TOPLEFT", x, -76)
  sortBtn:Show()
end

local function refreshTabs()
  local present, seen = { "all" }, { all = true }
  for _, entry in ipairs(lastRanked) do
    if not seen[entry.verdict] then
      seen[entry.verdict] = true
      present[#present + 1] = entry.verdict
    end
  end
  local order = {}
  for i, v in ipairs(ns.ranking.verdictOrder) do order[v] = i end
  table.sort(present, function(a, b)
    if a == "all" then return true end
    if b == "all" then return false end
    return (order[a] or 99) < (order[b] or 99)
  end)
  tabPool:ReleaseAll()
  local x = 12
  for _, v in ipairs(present) do
    local b = tabPool:Acquire()
    if not b._rec then
      b:SetHeight(20)
      ns.theme.styleButton(b, true)
      b._rec = true
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
  updateSortButton(x)
end

function render(ranked)
  lastRanked = ranked or {}
  lastSections = ui.buildSections(lastRanked, groupMode, expansionGetter(), filter, {
    never = ns.config.get("neverSell") or {}, always = ns.config.get("alwaysSell") or {},
  })
  local sortMode = ns.config.get("sortMode") or "off"
  local sortReverse = ns.config.get("sortReverse") or false
  local collapsed = ns.config.get("collapsedGroups") or {}
  iconPool:ReleaseAll()
  headPool:ReleaseAll()
  local y = 0
  for _, sec in ipairs(lastSections) do
    ui.sortEntries(sec.entries, sortMode, sortReverse)
    local h = acquireHeader()
    h.key, h.entries = sec.key, sec.entries
    h.button:ClearAllPoints()
    h.button:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    h.button:SetWidth(560)
    h.button:Show()
    local shut = collapsed[sec.key]
    h.label:SetText((shut and "+ " or "- ") .. sec.label .. " (" .. #sec.entries .. ")")
    y = y + HEAD_H
    if not shut then
      for j, entry in ipairs(sec.entries) do
        local r = acquireIcon()
        paintIcon(r, entry)
        local col = (j - 1) % COLS
        local row = math.floor((j - 1) / COLS)
        r.button:ClearAllPoints()
        r.button:SetPoint("TOPLEFT", child, "TOPLEFT", 4 + col * PITCH, -(y + row * PITCH))
        r.button:Show()
      end
      y = y + math.ceil(#sec.entries / COLS) * PITCH + 6
    end
  end
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

-- Use consumes one-click collectables (caches, uncollected decor) from
-- bags. Equippables never route here, but if a future rule slips one in,
-- skip it: using would bind it.
function ui.useQueued(list)
  local n, skipped, equippable = 0, 0, 0
  list = list or selectedWhere(function(e) return e.verdict == "use" end)
  for _, entry in ipairs(list) do
    local item = entry.item
    local detail = entry.detail or {}
    if (detail.classID == 2 or detail.classID == 4) and detail.equipLoc ~= nil and detail.equipLoc ~= "" then
      equippable = equippable + 1
    elseif item.scope == "bags" and type(item.bag) == "number" and type(item.slot) == "number" then
      C_Container.UseContainerItem(item.bag, item.slot)
      n = n + 1
    else
      skipped = skipped + 1
    end
  end
  if equippable > 0 then
    print("Warbank Audit: skipped " .. equippable .. " equippable items (using would bind them).")
  end
  if skipped > 0 then
    print("Warbank Audit: skipped " .. skipped .. " items outside bags (not supported yet).")
  end
  ui.rescan(true)
  return n
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
  ui.rescan(true)
  return n
end

-- Disenchant mails to the enchanter. The footer button click is the
-- hardware event that makes the protected container calls legal.
-- Mail goes out in 12-item batches; anything that won't attach
-- (soulbound etc.) is put back and reported, never lost.
local MAIL_BATCH = 12

local function atMailbox()
  return MailFrame and MailFrame:IsShown()
end

local function mailToEnchanter(who, items)
  local sent, skipped = 0, 0
  local i = 1
  while i <= #items do
    SendMailNameEditBox:SetText(who)
    SendMailSubjectEditBox:SetText("Warbank Audit: disenchantables")
    local attached = 0
    while attached < MAIL_BATCH and i <= #items do
      local item = items[i]
      C_Container.PickupContainerItem(item.bag, item.slot)
      if GetCursorInfo() then
        ClickSendMailItemButton()
        if GetCursorInfo() then
          C_Container.PickupContainerItem(item.bag, item.slot) -- put it back
          skipped = skipped + 1
        else
          attached = attached + 1
        end
      else
        skipped = skipped + 1
      end
      i = i + 1
    end
    if attached > 0 then
      SendMailMailButton:Click()
      sent = sent + attached
    end
  end
  ui.rescan(true)
  print("Warbank Audit: mailed " .. sent .. " items to " .. who
    .. (skipped > 0 and " (skipped " .. skipped .. " unmailable)" or "") .. ".")
  return sent
end

function ui.disenchantQueued(list)
  list = list or selectedWhere(function(e) return e.verdict == "disenchant" end)
  if #list == 0 then return 0 end
  local who = ns.config.get("enchanter")
  if not who or who == "" then
    print("Warbank Audit: " .. #list .. " items to disenchant — set your enchanter with"
      .. " /ww enchanter <name>, or disenchant them directly.")
    for _, entry in ipairs(list) do print("  " .. ui.linkName(entry.item.link)) end
    return #list
  end
  local mailable = {}
  for _, entry in ipairs(list) do
    local item = entry.item
    if item.scope == "bags" and type(item.bag) == "number" and type(item.slot) == "number" then
      mailable[#mailable + 1] = item
    end
  end
  if #mailable == 0 then
    print("Warbank Audit: nothing mailable — the disenchant queue is all bank/warbank items.")
    return 0
  end
  if not atMailbox() then
    print("Warbank Audit: " .. #mailable .. " items ready for " .. who
      .. " — open a mailbox to send them.")
    return #mailable
  end
  StaticPopup_Show("WARBANKAUDIT_CONFIRM_MAIL", #mailable, who, { who = who, items = mailable })
  return #mailable
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
  ui.rescan(true)
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
  local collapsed = ns.config.get("collapsedGroups") or {}
  for _, sec in ipairs(lastSections) do
    if not collapsed[sec.key] then
      for _, entry in ipairs(sec.entries) do selected[ui.entryKey(entry)] = true end
    end
  end
  render(lastRanked)
end

function ui.clearSelection()
  selected = {}
  render(lastRanked)
end

-- Auto-open docking. When the window pops itself up beside the merchant
-- or auction house, it docks top-aligned to whichever side has room and
-- clamps vertically so it never runs off screen. An unusable anchor (no
-- frame, too narrow a screen) leaves the position alone and reports
-- false; the window still opens.
local AUTO_GAP, AUTO_MARGIN = 8, 20

local function anchorBeside(frame)
  if not (window and frame and frame.IsShown and frame:IsShown()) then return false end
  local screenW = UIParent and UIParent:GetWidth() or 1920
  local screenH = UIParent and UIParent:GetHeight() or 1080
  local w, h = window:GetSize()
  local left, right, top = frame:GetLeft(), frame:GetRight(), frame:GetTop()
  if not (w and h and left and right and top) then return false end
  local y = 0
  if top > screenH - AUTO_MARGIN then y = (screenH - AUTO_MARGIN) - top end
  if top + y - h < AUTO_MARGIN then y = AUTO_MARGIN + h - top end
  local point, relPoint, x
  if right + AUTO_GAP + w <= screenW then
    point, relPoint, x = "TOPLEFT", "TOPRIGHT", AUTO_GAP
  elseif left - AUTO_GAP - w >= 0 then
    point, relPoint, x = "TOPRIGHT", "TOPLEFT", -AUTO_GAP
  else
    return false
  end
  window:ClearAllPoints()
  window:SetPoint(point, frame, relPoint, x, y)
  return true
end

-- Pop the window up for a merchant/AH visit. Never repositions an
-- already-open window. An optional verdict pre-selects the filter.
-- Returns nil when nothing was opened.
local function autoShow(frame, defaultFilter)
  if window and window:IsShown() then return nil end
  if defaultFilter then filter = defaultFilter end
  ui.rescan()
  local docked = anchorBeside(frame)
  window:Show()
  return docked
end

function ui.rescan(keepSelection)
  if not window then ui.init() end
  merchantOpen = MerchantFrame and MerchantFrame:IsShown() or false
  local provider = ns.providers.get()
  local ranked = ns.ranking.rank(ns.scanner.scan(ns.config.get("scope")))
  for _, entry in ipairs(ranked) do
    local price = provider and provider.GetMarketValue(entry.item.link) or nil
    entry.value = price and price * (entry.item.count or 1) or nil
  end
  if keepSelection then
    local present = {}
    for _, entry in ipairs(ranked) do present[ui.entryKey(entry)] = true end
    for k in pairs(selected) do if not present[k] then selected[k] = nil end end
  else
    selected = {}
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
  searchBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
  searchBox:SetSize(190, 20)
  searchBox:SetPoint("TOPLEFT", window, "TOPLEFT", 186, -52)
  searchBox:SetAutoFocus(false)
  searchHint = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  searchHint:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
  searchHint:SetText("Search items...")
  searchBox:SetScript("OnTextChanged", function(self)
    searchText = self:GetText():lower()
    if self:GetText() == "" then searchHint:Show() else searchHint:Hide() end
    applySearch()
  end)
  searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  searchClear = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  searchClear:SetSize(22, 20)
  searchClear:SetPoint("TOPLEFT", window, "TOPLEFT", 380, -52)
  searchClear:SetText("x")
  searchClear:SetScript("OnClick", function() searchBox:SetText("") searchBox:ClearFocus() end)
  ns.theme.styleButton(searchClear, true)
  window:SetScript("OnHide", function()
    if searchBox:GetText() ~= "" then searchBox:SetText("") end
  end)
  sortBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  sortBtn:SetSize(124, 20)
  sortBtn:RegisterForClicks("AnyUp")
  sortBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.config.set("sortReverse", not ns.config.get("sortReverse"))
    else
      local cur = ns.config.get("sortMode") or "off"
      local nextMode = SORT_MODES[1]
      for i, m in ipairs(SORT_MODES) do
        if m == cur then nextMode = SORT_MODES[i % #SORT_MODES + 1] end
      end
      ns.config.set("sortMode", nextMode)
    end
    render(lastRanked)
  end)
  sortBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Left-click: cycle sort")
    GameTooltip:AddLine("Right-click: reverse")
    GameTooltip:Show()
  end)
  sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ns.theme.styleButton(sortBtn, true)
  scroll = CreateFrame("ScrollFrame", "WarbankAuditScroll", window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -100)
  scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, 86)
  child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(580)
  child:SetHeight(1)
  scroll:SetScrollChild(child)
  iconPool = CreateObjectPool(function()
    return CreateFrame("Button", nil, child)
  end, poolReset)
  headPool = CreateObjectPool(function()
    return CreateFrame("Button", nil, child)
  end, poolReset)
  tabPool = CreateObjectPool(function()
    return CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  end, poolReset)
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
    { "use", 16, function() ui.useQueued() end },
    { "sell", 134, function() ui.sellQueued() end },
    { "disenchant", 252, function() ui.disenchantQueued() end },
    { "vendor", 370, function() ui.vendorQueued() end },
    { "trash", 488, function() confirmTrash() end },
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
  StaticPopupDialogs["WARBANKAUDIT_CONFIRM_MAIL"] = {
    text = "Mail %d items to %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) mailToEnchanter(data.who, data.items) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  local ctx = CreateFrame("Frame")
  ctx:RegisterEvent("MERCHANT_SHOW")
  ctx:RegisterEvent("MERCHANT_CLOSED")
  ctx:RegisterEvent("AUCTION_HOUSE_SHOW")
  ctx:RegisterEvent("BAG_UPDATE_DELAYED")
  ctx:RegisterEvent("BANKFRAME_OPENED")
  ctx:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
      merchantOpen = true
      if ns.config.get("autoOpenVendor") then autoShow(MerchantFrame, "vendor") end
    elseif event == "MERCHANT_CLOSED" then
      merchantOpen = false
    elseif event == "AUCTION_HOUSE_SHOW" then
      -- The AH frame loads on demand, so a missed dock gets one delayed
      -- retry, skipped if the user moved the window meanwhile.
      if ns.config.get("autoOpenAuction") then
        if autoShow(AuctionHouseFrame) == false and C_Timer and C_Timer.After then
          local left, top = window:GetLeft(), window:GetTop()
          C_Timer.After(0.25, function()
            if window and window:IsShown()
                and window:GetLeft() == left and window:GetTop() == top then
              anchorBeside(AuctionHouseFrame)
            end
          end)
        end
      end
    elseif event == "BAG_UPDATE_DELAYED" or event == "BANKFRAME_OPENED" then
      if window:IsShown() then ui.rescan(true) end
    end
    if window:IsShown() then updateTexts() end
  end)
  -- Live inventory updates. Blizzard events cover bags and the bank;
  -- Syndicator callbacks (same names Baganator uses) cover its cached
  -- scopes, including the warbank while offline. All preserve selection.
  if Syndicator and Syndicator.CallbackRegistry
      and Syndicator.CallbackRegistry.RegisterCallback then
    local registry = Syndicator.CallbackRegistry
    pcall(registry.RegisterCallback, registry, "BagCacheUpdate",
      function() if window:IsShown() then ui.rescan(true) end end)
    pcall(registry.RegisterCallback, registry, "WarbandBankCacheUpdate",
      function() if window:IsShown() then ui.rescan(true) end end)
  end
  ns.theme.init({
    window = window, close = closeBtn, scroll = scroll,
    title = window.TitleText, headPool = headPool, iconPool = iconPool,
    scrollBar = scroll.ScrollBar,
    texts = { headerStats, headerSource, footer, footerGroups, emptyNote },
    repaint = function()
      for b in iconPool:EnumerateActive() do
        local r = b._rec
        if r.entry then paintIcon(r, r.entry) end
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
