local _, ns = ...
local ui = {}
ns.ui = ui

-- Layout follows mock/triage.html (DESIGN 7): a 660x640 window split
-- into a sidebar (x12..192: search, verdict facets, group-by,
-- selection, actions, source) and a content column (x200..648: stats,
-- sort, the icon grid, the dry-run footer). Lua -N px == CSS N px
-- from the same edge.
local ICON_SIZE = 36
local PITCH = 40
local COLS = 10
local HEAD_H = 20
local SIDE_X, SIDE_W = 20, 164      -- sidebar controls: left edge, width
local CONTENT_X = 200               -- content column left edge
local CHILD_W, HEAD_W = 412, 404    -- scroll child, section headers
local FACET_Y, FACET_PITCH = 76, 22 -- verdict facet rows
local ACTION_Y, ACTION_PITCH = 408, 26
local PLUS_TEX = "Interface\\Buttons\\UI-PlusButton-UP"
local MINUS_TEX = "Interface\\Buttons\\UI-MinusButton-UP"
local SORT_ARROW_ATLAS = "auctionhouse-ui-sortarrow" -- Blizzard_AuctionHouseTableBuilder.xml
local DISENCHANT_SPELL = 13262

local ACTIONABLE = {
  sell = true, disenchant = true, vendor = true, destroy = true, use = true,
}

local VERDICT_LABEL = {
  keep = "Keep", sell = "Sell", disenchant = "Disenchant",
  vendor = "Vendor", destroy = "Destroy", use = "Use",
}

local VERDICT_COLOR = {
  keep = { 0.1, 0.9, 0.1 }, sell = { 1, 0.85, 0 },
  disenchant = { 0.2, 0.6, 1 }, vendor = { 0.7, 0.7, 0.7 },
  destroy = { 0.7, 0.1, 0.1 }, use = { 0.75, 0.5, 1 },
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

local function entryName(entry)
  local link = entry.item.link or ""
  return (link:match("%[(.-)%]") or link):lower()
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

-- Sort modes as the dropdown lists them; "off" is bag order.
ui.SORT_LABEL = { off = "Bag order", quality = "Quality", value = "Value", name = "Name" }
ui.SORT_MODES = { "off", "quality", "value", "name" }

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
    names[e] = entryName(e)
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
    elseif mode ~= "name" then
      return pos[a] < pos[b] -- "off": bag order; "name" falls through
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

-- Verdict facets for the sidebar: "all" first, then every verdict the
-- scan produced, in ranking order (unknown verdicts trail, sorted).
-- Returns the ordered list and the per-verdict counts.
function ui.facetCounts(ranked, order)
  local counts = { all = #ranked }
  for _, entry in ipairs(ranked) do
    counts[entry.verdict] = (counts[entry.verdict] or 0) + 1
  end
  local present, known = { "all" }, {}
  for _, v in ipairs(order or {}) do
    known[v] = true
    if counts[v] then present[#present + 1] = v end
  end
  local extra = {}
  for v in pairs(counts) do
    if v ~= "all" and not known[v] then extra[#extra + 1] = v end
  end
  table.sort(extra)
  for _, v in ipairs(extra) do present[#present + 1] = v end
  return present, counts
end

-- Disenchant readiness. In person (an enchanter at the keyboard) any
-- bag item goes, soulbound included; by mail, soulbound items cannot
-- attach. Stowed items (bank, warbank) go neither way: the secure
-- /use path only addresses bag slots. Returns the ready list and the
-- blocked counts { soulbound, stowed, total }.
function ui.dePartition(list, inPerson)
  local ready, blocked = {}, { soulbound = 0, stowed = 0, total = 0 }
  for _, entry in ipairs(list) do
    local item = entry.item
    if item.scope ~= "bags" or type(item.bag) ~= "number" or type(item.slot) ~= "number" then
      blocked.stowed = blocked.stowed + 1
      blocked.total = blocked.total + 1
    elseif not inPerson and item.bound then
      blocked.soulbound = blocked.soulbound + 1
      blocked.total = blocked.total + 1
    else
      ready[#ready + 1] = entry
    end
  end
  return ready, blocked
end

-- The Vendor click acts whenever something is selected or queued:
-- queuing needs no prior queue, unlike the immediate actions.
function ui.vendorEnabled(selVendor, qVendor)
  return (selVendor or 0) > 0 or (qVendor or 0) > 0
end

-- "3 can't go: 2 soulbound, 1 stowed", or nil when nothing is blocked.
function ui.blockedNote(blocked)
  if not blocked or blocked.total == 0 then return nil end
  local parts = {}
  if blocked.soulbound > 0 then parts[#parts + 1] = blocked.soulbound .. " soulbound" end
  if blocked.stowed > 0 then parts[#parts + 1] = blocked.stowed .. " stowed" end
  return blocked.total .. " can't go: " .. table.concat(parts, ", ")
end

-- Window state ------------------------------------------------------------
local window, side, headerStats, sourceText, scroll, child
local footer, footerGroups, emptyNote, noMatchNote
local iconPool, headPool, facetPool -- CreateObjectPools, built in init
local buttons = {}                  -- action buttons by verdict
local actionLabel, actionHint, deNote
local sortDrop, sortBtn, sortDir, sortArrow
local searchBox, searchHint
local searchText = ""
local poolReset = FramePool_HideAndClearAnchors or Pool_HideAndClearAnchors
  or function(_, f) f:Hide() f:ClearAllPoints() end
local groupButtons = {}
local lastRanked, lastSections = {}, {}
local lastQueued, lastTotals, lastKeeps = {}, { items = 0, slots = 0, gold = 0, groups = {} }, 0
local selected = {}
local groupMode, filter = "category", "all"
local merchantOpen = false
local deSecure = false     -- the disenchant button is a secure action button
local deInPerson = false   -- an enchanter is at the keyboard: cast, don't mail
local deSpellName = nil    -- localized Disenchant, for the secure macro

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
  -- Queued ring (DESIGN 10): gold, inset 1, created before the icon so
  -- it sits under it and reads as an inner edge on the quality plate.
  -- theme.paintQueued owns the on/off.
  local qr = f:CreateTexture(nil, "ARTWORK")
  qr:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  qr:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  qr:SetColorTexture(1, 0.82, 0, 1)
  qr:Hide()
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
    count = count, level = level, key = nil, entry = nil, searchName = "", qr = qr }
  f._rec = r
  f:SetScript("OnClick", function() ui.toggleKey(r.key) end)
  f:SetScript("OnEnter", function(self)
    local entry = r.entry
    if not entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- Syndicator slots can carry an itemID with no link; SetHyperlink
    -- errors on nil, so fall back to a plain label.
    if entry.item.link then
      GameTooltip:SetHyperlink(entry.item.link)
    else
      GameTooltip:SetText("Item " .. tostring(entry.item.itemID or "?"))
    end
    GameTooltip:AddLine(verdictLabel(entry.verdict) .. " — " .. (entry.reason or ""), 1, 1, 1)
    local queuedAction = ns.queue and ns.queue.queuedAs(entry)
    if queuedAction then
      GameTooltip:AddLine("Queued: " .. verdictLabel(queuedAction), 1, 0.82, 0)
    end
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
  local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
  label:SetPoint("LEFT", f, "LEFT", 20, 0)
  local toggle = f:CreateTexture(nil, "ARTWORK")
  toggle:SetSize(14, 14)
  toggle:SetPoint("LEFT", f, "LEFT", 0, 0)
  toggle:SetTexture(PLUS_TEX)
  local pulse = f:CreateAnimationGroup()
  local function addFade(region)
    local f1 = pulse:CreateAnimation("Alpha")
    f1:SetFromAlpha(1)
    f1:SetToAlpha(0.4)
    f1:SetDuration(0.5)
    f1:SetTarget(region)
    f1:SetOrder(1)
    f1:SetSmoothing("IN_OUT")
    local f2 = pulse:CreateAnimation("Alpha")
    f2:SetFromAlpha(0.4)
    f2:SetToAlpha(1)
    f2:SetDuration(0.5)
    f2:SetTarget(region)
    f2:SetOrder(2)
    f2:SetSmoothing("IN_OUT")
  end
  addFade(label)
  addFade(toggle)
  pulse:SetLooping("REPEAT")
  local r = { button = f, label = label, toggle = toggle, pulse = pulse,
    key = nil, entries = nil, base = "" }
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
  return r
end

local function acquireHeader()
  local f = headPool:Acquire()
  return f._rec or buildHeader(f)
end

-- Verdict facet rows (mock: #vw-tabs): label left, scan count right,
-- the active row tinted with a gold bar. Plain rows in both looks.
local function buildFacet(b)
  b:SetSize(SIDE_W, 20)
  local active = b:CreateTexture(nil, "BACKGROUND")
  active:SetAllPoints()
  active:SetColorTexture(1, 0.82, 0, 0.12)
  local bar = b:CreateTexture(nil, "BORDER")
  bar:SetWidth(2)
  bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  bar:SetColorTexture(1, 0.82, 0, 1)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.06)
  local name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  name:SetPoint("LEFT", b, "LEFT", 8, 0)
  name:SetJustifyH("LEFT")
  local count = b:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  count:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  local r = { button = b, active = active, bar = bar, name = name, count = count, verdict = nil, n = 0 }
  b._rec = r
  b:SetScript("OnClick", function()
    if r.verdict then filter = r.verdict render(lastRanked) end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if r.verdict == "all" then
      GameTooltip:AddLine("Show everything (" .. r.n .. ")")
    else
      GameTooltip:AddLine("Show only " .. verdictLabel(r.verdict):lower() .. " items (" .. r.n .. ")")
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function acquireFacet()
  local f = facetPool:Acquire()
  return f._rec or buildFacet(f)
end

local function paintIcon(r, entry)
  local item, detail = entry.item, entry.detail or {}
  r.key = ui.entryKey(entry)
  r.entry = entry
  r.searchName = entryName(entry)
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
  ns.theme.paintQueued(r, ns.queue and ns.queue.queuedAs(entry))
  r.button:SetAlpha(ui.searchMatch(r.searchName, searchText) and 1 or 0.35)
end

local function sectionHits(entries)
  local hits = 0
  for _, entry in ipairs(entries or {}) do
    if ui.searchMatch(entryName(entry), searchText) then hits = hits + 1 end
  end
  return hits
end

-- Header text: "Armor (3)", or "Armor (2/3)" while a search narrows
-- the set, so collapsed groups still tell what they hold.
local function paintHeaderLabel(r)
  local n = #(r.entries or {})
  if searchText ~= "" then
    r.label:SetText(r.base .. " (" .. sectionHits(r.entries) .. "/" .. n .. ")")
  else
    r.label:SetText(r.base .. " (" .. n .. ")")
  end
end

local function selectedWhere(pred)
  local out = {}
  for _, entry in ipairs(lastRanked) do
    if selected[ui.entryKey(entry)] and pred(entry) then out[#out + 1] = entry end
  end
  return out
end

local function isDisenchant(e) return e.verdict == "disenchant" end

-- Label, enabled state, and the hover title (UIPanelButtonMixin reads
-- tooltipText; motion scripts stay on while disabled so the title
-- explains why).
local function setButton(b, label, n, ctxOK, tip)
  b:SetText(label .. " (" .. n .. ")")
  b.tooltipText = tip
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
  sourceText:SetText("Source: " .. (ns.activeSource or "none"))
  local t, g = lastTotals, lastTotals.groups
  local sel = "Selected: " .. t.items .. " items, " .. t.slots .. " slots, ~" .. ui.formatGold(t.gold)
  if lastKeeps > 0 then sel = sel .. " (+" .. lastKeeps .. " keeps)" end
  footer:SetText(sel)
  footerGroups:SetText("use " .. (g.use or 0) .. "  •  sell " .. (g.sell or 0)
    .. "  •  disenchant " .. (g.disenchant or 0) .. "  •  vendor " .. (g.vendor or 0)
    .. "  •  destroy " .. (g.destroy or 0))
  setButton(buttons.use, "Use", g.use or 0, true, "Use the selected items")
  setButton(buttons.sell, "Sell", g.sell or 0, true, "List the selected items (auction helper)")
  -- Disenchant adapts (DESIGN 9): cast in person on an enchanter, else
  -- mail to the configured one; what can go neither way is listed.
  local ready, blocked = ui.dePartition(selectedWhere(isDisenchant), deInPerson)
  local who = ns.config.get("enchanter") or ""
  local note = ui.blockedNote(blocked)
  local label, tip, ctxOK
  if deInPerson then
    label, ctxOK = "Disenchant", true
    tip = "Disenchant the selected items in person, one per click"
  elseif who == "" then
    label, ctxOK = "Mail for DE", false
    tip = "Set an enchanter first: /vw enchanter <name>"
  else
    label, ctxOK = "Mail for DE", true
    tip = "Mail the selected items to " .. who
  end
  if note then tip = tip .. " (" .. note .. ")" end
  setButton(buttons.disenchant, label, #ready, ctxOK, tip)
  deNote:SetText(note or "")
  deNote:SetShown(note ~= nil)
  -- Vendor queues (DESIGN 10): the count is the queued total, and the
  -- button stays up whenever there is something to queue or queued.
  local qVendor = ns.queue and ns.queue.count("vendor") or 0
  local selVendor = g.vendor or 0
  local vendorTip = "Queue the selected items for the vendor"
    .. (qVendor > 0 and (" (" .. qVendor .. " queued)") or "")
    .. " — click again to unqueue"
  local vendorOK = ui.vendorEnabled(selVendor, qVendor)
  setButton(buttons.vendor, "Vendor", qVendor, vendorOK, vendorTip)
  -- setButton gates on the label count too, so the empty-queue case it
  -- just disabled re-enables here when a selection is waiting.
  if vendorOK then buttons.vendor:Enable() end
  setButton(buttons.destroy, "Destroy", g.destroy or 0, true, "Destroy the selected items (with confirmation)")
  -- The Actions group frames itself around the live selection
  -- (DESIGN 8): narrow -> select -> act.
  local nSel = t.slots + lastKeeps
  actionLabel:SetText(nSel > 0 and ("Actions · " .. nSel .. " selected") or "Actions")
  actionLabel:SetAlpha(nSel > 0 and 1 or 0.55)
  actionHint:SetShown(nSel == 0)
end

local function expansionGetter()
  local provider = ns.providers.get()
  return function(itemID)
    return provider and provider.GetExpansion(itemID) or nil
  end
end

-- Collapsed headers holding search matches pulse, so hidden hits are
-- discoverable. Mirrors upstream's fade loop (0.5s, 1 -> 0.4 -> 1).
local function updateHeaderPulse()
  if not headPool then return end
  local shut = ns.config.get("collapsedGroups") or {}
  for b in headPool:EnumerateActive() do
    local r = b._rec
    if r and r.entries and r.pulse then
      local hit = shut[r.key] and searchText ~= "" and sectionHits(r.entries) > 0
      if hit then r.pulse:Play() else r.pulse:Stop() end
    end
  end
end

-- "No matches for "x"" when a search finds nothing in a non-empty grid.
local function updateSearchNote()
  local noMatch = searchText ~= "" and #lastSections > 0
  if noMatch then
    for _, sec in ipairs(lastSections) do
      if sectionHits(sec.entries) > 0 then noMatch = false break end
    end
  end
  if noMatch then
    noMatchNote:SetText("No matches for \"" .. searchBox:GetText() .. "\"")
    noMatchNote:Show()
  else
    noMatchNote:Hide()
  end
end

-- Search dims in place: no re-layout, headers relabel, hidden hits pulse.
local function applySearch()
  if not iconPool then return end
  for b in iconPool:EnumerateActive() do
    local r = b._rec
    if r and r.entry then
      r.button:SetAlpha(ui.searchMatch(r.searchName, searchText) and 1 or 0.35)
    end
  end
  for b in headPool:EnumerateActive() do
    if b._rec and b._rec.entries then paintHeaderLabel(b._rec) end
  end
  updateHeaderPulse()
  updateSearchNote()
end

-- Sort cluster: the dropdown shows the mode, the arrow the direction.
-- Arrow coords follow the auction house header (sorted vs reversed).
local function refreshSort()
  local mode = ns.config.get("sortMode") or "off"
  local reverse = ns.config.get("sortReverse") and true or false
  if sortDrop then
    if not (sortDrop.IsMenuOpen and sortDrop:IsMenuOpen()) then sortDrop:GenerateMenu() end
  elseif sortBtn then
    sortBtn:SetText("Sort: " .. (ui.SORT_LABEL[mode] or mode))
  end
  if reverse then sortArrow:SetTexCoord(0, 1, 0, 1) else sortArrow:SetTexCoord(0, 1, 1, 0) end
  ns.theme.setPressed(sortDir, reverse)
end

local function refreshFacets()
  local present, counts = ui.facetCounts(lastRanked, ns.ranking.verdictOrder)
  if not counts[filter] and filter ~= "all" then
    -- A pre-selected filter (auto-open at a vendor) with nothing to show
    -- still gets its row, so the empty grid is explained.
    present[#present + 1] = filter
    counts[filter] = 0
  end
  facetPool:ReleaseAll()
  local y = FACET_Y
  for _, v in ipairs(present) do
    local r = acquireFacet()
    r.verdict, r.n = v, counts[v]
    r.name:SetText(v == "all" and "All" or verdictLabel(v))
    r.count:SetText(counts[v])
    local on = v == filter
    r.active:SetShown(on)
    r.bar:SetShown(on)
    if on then r.count:SetTextColor(1, 0.82, 0) else r.count:SetTextColor(0.5, 0.5, 0.5) end
    r.button:ClearAllPoints()
    r.button:SetPoint("TOPLEFT", window, "TOPLEFT", SIDE_X, -y)
    r.button:Show()
    y = y + FACET_PITCH
  end
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
    h.key, h.entries, h.base = sec.key, sec.entries, sec.label
    h.button:ClearAllPoints()
    h.button:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    h.button:SetWidth(HEAD_W)
    h.button:Show()
    local shut = collapsed[sec.key]
    paintHeaderLabel(h)
    h.toggle:SetTexture(shut and PLUS_TEX or MINUS_TEX)
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
  refreshFacets()
  refreshSort()
  updateHeaderPulse()
  updateSearchNote()
  ns.theme.setPressed(groupButtons[1], groupMode == "category")
  ns.theme.setPressed(groupButtons[2], groupMode == "expansion")
  lastQueued, lastTotals, lastKeeps = ui.computeSelection(lastRanked, selected)
  updateTexts()
end

-- Actions. Each runs from a button click (a hardware event), which is
-- what makes the protected container calls legal. ------------------------

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
    ns.say("skipped " .. equippable .. " equippable items (using would bind them).")
  end
  if skipped > 0 then
    ns.say("skipped " .. skipped .. " items outside bags (not supported yet).")
  end
  ui.rescan(true)
  return n
end

-- Queue the selected vendor-verdict items (DESIGN 10): toggled per
-- itemID so clicking again unqueues, counts merging by item. Queued
-- items sell from the merchant handoff, which pops at once when a
-- merchant is already open.
function ui.queueVendor()
  local sel = selectedWhere(function(e) return e.verdict == "vendor" end)
  if #sel == 0 then
    if not ns.queue.empty("vendor") then
      ns.say(ns.queue.count("vendor") .. " items queued for the vendor.")
    end
    return
  end
  local added, removed = ns.queue.toggle("vendor", sel)
  if added > 0 and removed > 0 then
    ns.say("queued " .. added .. ", unqueued " .. removed .. " items.")
  elseif added > 0 then
    ns.say("queued " .. added .. " items for the vendor.")
  elseif removed > 0 then
    ns.say("unqueued " .. removed .. " items.")
  end
  if merchantOpen and ns.handoff then ns.handoff.show("vendor") end
  render(lastRanked)
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
    ns.say("skipped " .. skipped .. " items outside bags (not supported yet).")
  end
  ui.rescan(true)
  return n
end

-- Disenchant by mail goes to the enchanter named in settings. The
-- button click is the hardware event that makes the protected container
-- calls legal. Mail goes out in 12-item batches; anything that won't
-- attach (soulbound etc.) is put back and reported, never lost.
local MAIL_BATCH = 12

local function atMailbox()
  return MailFrame and MailFrame:IsShown()
end

local function mailToEnchanter(who, items)
  local sent, skipped = 0, 0
  local i = 1
  while i <= #items do
    SendMailNameEditBox:SetText(who)
    SendMailSubjectEditBox:SetText("VocWarbank: disenchantables")
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
  ns.say("mailed " .. sent .. " items to " .. who
    .. (skipped > 0 and " (skipped " .. skipped .. " unmailable)" or "") .. ".")
  return sent
end

function ui.disenchantQueued(list)
  list = list or selectedWhere(isDisenchant)
  if #list == 0 then return 0 end
  local who = ns.config.get("enchanter")
  if not who or who == "" then
    ns.say("" .. #list .. " items to disenchant — set your enchanter with"
      .. " /vw enchanter <name>, or disenchant them directly.")
    for _, entry in ipairs(list) do print("  " .. ui.linkName(entry.item.link)) end
    return #list
  end
  local ready, blocked = ui.dePartition(list, false)
  local note = ui.blockedNote(blocked)
  if #ready == 0 then
    ns.say("nothing mailable" .. (note and (" — " .. note) or "") .. ".")
    return 0
  end
  local mailable = {}
  for _, entry in ipairs(ready) do mailable[#mailable + 1] = entry.item end
  if not atMailbox() then
    ns.say("" .. #mailable .. " items ready for " .. who
      .. " — open a mailbox to send them" .. (note and (" (" .. note .. ")") or "") .. ".")
    return #mailable
  end
  StaticPopup_Show("VOCWARBANK_CONFIRM_MAIL", #mailable, who, { who = who, items = mailable })
  return #mailable
end

-- In-person disenchant rides a secure action button: PreClick writes
-- the next ready bag slot into a "/cast Disenchant" + "/use bag slot"
-- macro (the same path Blizzard's own macros take, SlashCommands.lua
-- CAST/USE -> CastSpellByName, C_Container.UseContainerItem), the
-- template's own OnClick runs it, PostClick clears it. One item per
-- click: a cast is in flight after each. Attributes cannot change in
-- combat, so the click does nothing there and says so.
local function armDisenchant(b, _, down)
  if not deInPerson then return end
  if InCombatLockdown() then
    if down then ns.say("can't disenchant during combat.") end
    return
  end
  local ready = ui.dePartition(selectedWhere(isDisenchant), true)
  local first = ready[1]
  if not first or not deSpellName then
    b:SetAttribute("type", nil)
    return
  end
  b:SetAttribute("type", "macro")
  b:SetAttribute("macrotext", "/cast " .. deSpellName .. "\n/use " .. first.item.bag .. " " .. first.item.slot)
end

local function afterDisenchant(b, _, down)
  if not InCombatLockdown() then b:SetAttribute("type", nil) end
  if not deInPerson and not down then ui.disenchantQueued() end
end

-- An enchanter at the keyboard disenchants in person. Needs the secure
-- button, Enchanting on this character, and the spell's localized name
-- (nil when the client has no such spell).
local function detectEnchanter()
  if not deSecure then return false end
  if not (ns.ranking.hasProfession and ns.ranking.hasProfession(ns.ranking.SKILL_ENCHANTING)) then
    return false
  end
  if not (C_Spell and C_Spell.GetSpellName) then return false end
  local ok, name = pcall(C_Spell.GetSpellName, DISENCHANT_SPELL)
  if not ok or type(name) ~= "string" or name == "" then return false end
  deSpellName = name
  return true
end

function ui.sellQueued(list)
  list = list or selectedWhere(function(e) return e.verdict == "sell" end)
  if #list == 0 then return 0 end
  local helper = nil
  if C_AddOns.IsAddOnLoaded("TradeSkillMaster") then helper = "TSM"
  elseif C_AddOns.IsAddOnLoaded("Auctionator") then helper = "Auctionator" end
  if helper then
    ns.say("" .. #list .. " items ready — list them in " .. helper
      .. ". (Automatic handoff coming in a later version.)")
  else
    ns.say("" .. #list .. " items flagged for manual listing (no auction addon found).")
  end
  for _, entry in ipairs(list) do print("  " .. ui.linkName(entry.item.link)) end
  return #list
end

function ui.destroyQueued(list)
  local n, skipped, pending = 0, 0, false
  list = list or lastQueued
  for _, entry in ipairs(list) do
    if entry.verdict == "destroy" then
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
    ns.say("paused for Blizzard's confirmation — click Destroy again to continue"
      .. " (put the item back first if you cancelled).")
  elseif skipped > 0 then
    ns.say("destroyed " .. n .. ", skipped " .. skipped .. " outside bags.")
  else
    ns.say("destroyed " .. n .. " items.")
  end
  return n
end

local function confirmDestroy()
  local n = 0
  for _, entry in ipairs(lastQueued) do
    if entry.verdict == "destroy" then n = n + 1 end
  end
  if n == 0 then return end
  StaticPopup_Show("VOCWARBANK_CONFIRM_DESTROY", n)
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

-- Dock `mover` top-aligned beside `target`, right side first unless
-- preferLeft. Shared with the handoff dialog; the main window keeps its
-- old call shape through anchorBeside below.
function ui.dockBeside(mover, target, preferLeft)
  if not (mover and target and target.IsShown and target:IsShown()) then return false end
  local screenW = UIParent and UIParent:GetWidth() or 1920
  local screenH = UIParent and UIParent:GetHeight() or 1080
  local w, h = mover:GetSize()
  local left, right, top = target:GetLeft(), target:GetRight(), target:GetTop()
  if not (w and h and left and right and top) then return false end
  local y = 0
  if top > screenH - AUTO_MARGIN then y = (screenH - AUTO_MARGIN) - top end
  if top + y - h < AUTO_MARGIN then y = AUTO_MARGIN + h - top end
  local sides
  if preferLeft then
    sides = { { "TOPRIGHT", "TOPLEFT", -AUTO_GAP }, { "TOPLEFT", "TOPRIGHT", AUTO_GAP } }
  else
    sides = { { "TOPLEFT", "TOPRIGHT", AUTO_GAP }, { "TOPRIGHT", "TOPLEFT", -AUTO_GAP } }
  end
  for _, s in ipairs(sides) do
    local room = s[3] > 0 and (screenW - right - AUTO_GAP) or (left - AUTO_GAP)
    if room >= w then
      mover:ClearAllPoints()
      mover:SetPoint(s[1], target, s[2], s[3], y)
      return true
    end
  end
  return false
end

local function anchorBeside(frame)
  return ui.dockBeside(window, frame)
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
  deInPerson = detectEnchanter()
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

-- Widget factories for init ----------------------------------------------

-- Add a handler without clobbering one a template installed.
local function addScript(frame, name, fn)
  if frame:GetScript(name) then frame:HookScript(name, fn) else frame:SetScript(name, fn) end
end

local function sideLabel(text, y)
  local fs = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  fs:SetPoint("TOPLEFT", window, "TOPLEFT", SIDE_X, -y)
  fs:SetText(text)
  return fs
end

local function sideButton(text, y, width, x, onClick)
  local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  b:SetSize(width or SIDE_W, 20)
  b:SetPoint("TOPLEFT", window, "TOPLEFT", x or SIDE_X, -y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  ns.theme.styleButton(b)
  return b
end

-- The sort dropdown (WowStyle1DropdownTemplate, Blizzard_Menu): radios
-- per mode, the button text mirroring the selection. A client without
-- the template keeps a cycling button instead.
local function buildSortDropdown()
  local ok, d = pcall(CreateFrame, "DropdownButton", nil, window, "WowStyle1DropdownTemplate")
  if not (ok and d and d.SetupMenu) then return nil end
  d:SetSize(120, 22)
  d:SetPoint("TOPLEFT", window, "TOPLEFT", 516, -29)
  if d.SetDefaultText then d:SetDefaultText("Sort: " .. ui.SORT_LABEL.off) end
  if d.SetSelectionTranslator then
    d:SetSelectionTranslator(function(selection) return "Sort: " .. tostring(selection.text or "") end)
  end
  d:SetupMenu(function(_, root)
    for _, m in ipairs(ui.SORT_MODES) do
      root:CreateRadio(ui.SORT_LABEL[m],
        function() return (ns.config.get("sortMode") or "off") == m end,
        function() ns.config.set("sortMode", m) render(lastRanked) end)
    end
  end)
  addScript(d, "OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Sort items within each group")
    GameTooltip:Show()
  end)
  addScript(d, "OnLeave", function() GameTooltip:Hide() end)
  ns.theme.styleDropdown(d)
  return d
end

local function buildSortCycleButton()
  local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  b:SetSize(120, 20)
  b:SetPoint("TOPLEFT", window, "TOPLEFT", 516, -30)
  b:SetScript("OnClick", function()
    local cur = ns.config.get("sortMode") or "off"
    local nextMode = ui.SORT_MODES[1]
    for i, m in ipairs(ui.SORT_MODES) do
      if m == cur then nextMode = ui.SORT_MODES[i % #ui.SORT_MODES + 1] end
    end
    ns.config.set("sortMode", nextMode)
    render(lastRanked)
  end)
  b.tooltipText = "Click: cycle sort"
  ns.theme.styleButton(b)
  return b
end

local function buildDisenchantButton(y)
  local ok, b = pcall(CreateFrame, "Button", nil, window, "SecureActionButtonTemplate, UIPanelButtonTemplate")
  deSecure = ok and b ~= nil and type(b.SetAttribute) == "function"
  if not deSecure then
    b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  end
  b:SetSize(SIDE_W, 22)
  b:SetPoint("TOPLEFT", window, "TOPLEFT", SIDE_X, -y)
  if deSecure then
    -- Both edges registered: the template fires the action on the one
    -- the ActionButtonUseKeyDown cvar picks (SecureTemplates.lua).
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("PreClick", armDisenchant)
    b:SetScript("PostClick", afterDisenchant)
  else
    b:SetScript("OnClick", function() ui.disenchantQueued() end)
  end
  if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
  ns.theme.styleButton(b)
  return b
end

function ui.init()
  if window then return end
  window = CreateFrame("Frame", "VocWarbankWindow", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(660, 640)
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "VocWarbankWindow") end
  window.TitleText:SetText("VocWarbank")
  -- BasicFrameTemplate ships its own CloseButton (UIPanelTemplates.xml);
  -- an older template without one gets a stock close button.
  if not window.CloseButton then
    local closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() window:Hide() end)
  end

  -- Sidebar panel: tinted, with a divider against the content column.
  side = CreateFrame("Frame", nil, window)
  side:SetPoint("TOPLEFT", window, "TOPLEFT", 4, -24)
  side:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 4, 4)
  side:SetWidth(188)
  side.bg = side:CreateTexture(nil, "BACKGROUND")
  side.bg:SetAllPoints()
  side.divider = side:CreateTexture(nil, "BORDER")
  side.divider:SetWidth(1)
  side.divider:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0)
  side.divider:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
  ns.theme.styleSidebar(side)

  -- Sidebar: search.
  searchBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
  searchBox:SetSize(138, 20)
  searchBox:SetPoint("TOPLEFT", window, "TOPLEFT", SIDE_X, -30)
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
  addScript(searchBox, "OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Find items by name — non-matches dim")
    GameTooltip:Show()
  end)
  addScript(searchBox, "OnLeave", function() GameTooltip:Hide() end)
  sideButton("x", 30, 22, 162, function() searchBox:SetText("") searchBox:ClearFocus() end)
  window:SetScript("OnHide", function()
    if searchBox:GetText() ~= "" then searchBox:SetText("") end
  end)

  -- Sidebar: verdict facets (a button pool; rows are laid out per scan).
  sideLabel("Verdict", 56)
  facetPool = CreateObjectPool(function()
    return CreateFrame("Button", nil, window)
  end, poolReset)

  -- Sidebar: group by.
  sideLabel("Group by", 256)
  local modes = { "category", "expansion" }
  for i = 1, 2 do
    local b = sideButton(i == 1 and "Category" or "Expansion", 276, 80, i == 1 and SIDE_X or 104,
      function() groupMode = modes[i] render(lastRanked) end)
    b.tooltipText = i == 1 and "Group by category" or "Group by expansion"
    groupButtons[i] = b
  end

  -- Sidebar: selection.
  sideLabel("Selection", 302)
  sideButton("Select shown", 322, nil, nil, function() ui.selectShown() end)
  sideButton("Clear", 346, nil, nil, function() ui.clearSelection() end)

  -- Sidebar: actions, framed around the live selection.
  actionLabel = sideLabel("Actions", 372)
  actionHint = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  actionHint:SetPoint("TOPLEFT", window, "TOPLEFT", SIDE_X, -390)
  actionHint:SetWidth(SIDE_W)
  actionHint:SetJustifyH("LEFT")
  actionHint:SetText("Select items to act on them.")
  local defs = {
    { "use", function() ui.useQueued() end },
    { "sell", function() ui.sellQueued() end },
    { "disenchant" },
    { "vendor", function() ui.queueVendor() end },
    { "destroy", function() confirmDestroy() end },
  }
  for i, def in ipairs(defs) do
    local y = ACTION_Y + (i - 1) * ACTION_PITCH
    local b
    if def[1] == "disenchant" then
      b = buildDisenchantButton(y)
    else
      b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
      b:SetSize(SIDE_W, 22)
      b:SetPoint("TOPLEFT", window, "TOPLEFT", SIDE_X, -y)
      b:SetScript("OnClick", def[2])
      if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
      ns.theme.styleButton(b)
    end
    buttons[def[1]] = b
  end
  deNote = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  deNote:SetPoint("TOPLEFT", window, "TOPLEFT", SIDE_X, -(ACTION_Y + #defs * ACTION_PITCH + 2))
  deNote:SetWidth(SIDE_W)
  deNote:SetJustifyH("LEFT")
  deNote:Hide()
  sourceText = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  sourceText:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", SIDE_X, 16)

  -- Content: stats and the sort cluster.
  headerStats = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  headerStats:SetPoint("TOPLEFT", window, "TOPLEFT", CONTENT_X, -30)
  sortDir = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  sortDir:SetSize(24, 20)
  sortDir:SetPoint("TOPLEFT", window, "TOPLEFT", 488, -30)
  sortArrow = sortDir:CreateTexture(nil, "OVERLAY")
  sortArrow:SetAtlas(SORT_ARROW_ATLAS, true)
  sortArrow:SetPoint("CENTER", sortDir, "CENTER", 0, 0)
  sortDir.tooltipText = "Reverse sort order"
  sortDir:SetScript("OnClick", function()
    ns.config.set("sortReverse", not ns.config.get("sortReverse"))
    render(lastRanked)
  end)
  ns.theme.styleButton(sortDir)
  sortDrop = buildSortDropdown()
  if not sortDrop then sortBtn = buildSortCycleButton() end

  -- Content: the grid. The scroll frame is anonymous: nothing addresses
  -- it by name (the bar is reached via scroll.ScrollBar), so it must
  -- not cost a global.
  scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", window, "TOPLEFT", CONTENT_X, -56)
  scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, 86)
  child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(CHILD_W)
  child:SetHeight(1)
  scroll:SetScrollChild(child)
  iconPool = CreateObjectPool(function()
    return CreateFrame("Button", nil, child)
  end, poolReset)
  headPool = CreateObjectPool(function()
    return CreateFrame("Button", nil, child)
  end, poolReset)
  emptyNote = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  emptyNote:SetPoint("TOP", scroll, "TOP", 0, -120)
  emptyNote:SetText("No items match this filter.")
  emptyNote:Hide()
  noMatchNote = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  noMatchNote:SetPoint("TOP", scroll, "TOP", 0, -120)
  noMatchNote:Hide()

  -- Content: dry-run footer across the content column.
  footer = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", CONTENT_X, 64)
  footer:SetWidth(436)
  footer:SetJustifyH("LEFT")
  footerGroups = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  footerGroups:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", CONTENT_X, 50)
  footerGroups:SetWidth(436)
  footerGroups:SetJustifyH("LEFT")

  StaticPopupDialogs["VOCWARBANK_CONFIRM_DESTROY"] = {
    text = "Destroy %d queued items? This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ui.destroyQueued() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopupDialogs["VOCWARBANK_CONFIRM_MAIL"] = {
    text = "Mail %d items to %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) mailToEnchanter(data.who, data.items) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  -- Coalescing flag for the GET_ITEM_INFO_RECEIVED rescan below.
  local itemInfoPending = false
  local ctx = CreateFrame("Frame")
  ctx:RegisterEvent("MERCHANT_SHOW")
  ctx:RegisterEvent("MERCHANT_CLOSED")
  ctx:RegisterEvent("AUCTION_HOUSE_SHOW")
  ctx:RegisterEvent("BAG_UPDATE_DELAYED")
  ctx:RegisterEvent("BANKFRAME_OPENED")
  ctx:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  ctx:RegisterEvent("QUEST_TURNED_IN")
  ctx:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
      merchantOpen = true
      if ns.config.get("autoOpenVendor") then autoShow(MerchantFrame, "vendor") end
      if ns.handoff then ns.handoff.maybeShow("vendor") end
    elseif event == "MERCHANT_CLOSED" then
      merchantOpen = false
      if ns.handoff then ns.handoff.hide() end
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
      if ns.handoff then ns.handoff.refresh() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
      -- Cold-cache items rank as "needs review"; re-rank once the data
      -- lands. Coalesced: one delayed rescan per burst, not one per item.
      if window:IsShown() and not itemInfoPending and C_Timer and C_Timer.After then
        itemInfoPending = true
        C_Timer.After(0.5, function()
          itemInfoPending = false
          if window:IsShown() then ui.rescan(true) end
        end)
      end
    elseif event == "QUEST_TURNED_IN" then
      ns.ranking.refreshQuests()
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
    window = window, headPool = headPool, iconPool = iconPool,
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
