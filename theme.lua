local _, ns = ...
local theme = {}
ns.theme = theme

-- Theme engine. One window, two looks, picked live:
--   baganator -> a faithful replication of Baganator's Dark skin recipe
--     (same asset files, same backdrop sizes, same colors), used when
--     Baganator is loaded and running its Dark skin.
--   default   -> stock Blizzard chrome. This is also what Baganator's
--     own Blizzard skin looks like, so Blizzard-skin users match too.
--
-- Exact-token sources (read, not guessed):
--   Baganator: Skins/Dark.lua from the v833 retail build (Wago zip;
--     the GitHub org is gone, so the shipped build is ground truth).
--     Window = dark-backgroundfile/dark-edgefile backdrop, edge 9,
--     fill (0.05,0.05,0.05) at alpha 1-transparency (default 0.7),
--     border Lighten(+0.3) = (0.35,0.35,0.35). Buttons = edge 6,
--     fill black 0.5, hover (0.3) 0.8, pressed (0.2) 0.8.
--     Transparency, frame borders, square icons, and slot backgrounds
--     follow the user's live skins.dark.* options (same defaults).
--
-- Baganator exposes Baganator.Skins.AddFrame, but its skinners assume
-- Baganator frame shapes (Left/Right/Middle, SlotBackground), so calling
-- them on foreign frames errors out. Replicating the recipe with our own
-- code is the only exact route.

local BGR_BG = "Interface/AddOns/Baganator/Assets/Skins/dark-backgroundfile"
local BGR_EDGE = "Interface/AddOns/Baganator/Assets/Skins/dark-edgefile"
local BGR_ICON_BORDER = "Interface/AddOns/Baganator/Assets/Skins/dark-icon-border"
local BGR_FILL = { 0.05, 0.05, 0.05 }
local BGR_BORDER = { 0.35, 0.35, 0.35 } -- Lighten(+0.3) of the fill

local STRIP_KEYS = {
  "TitleBg", "Bg", "TopTileStreaks",
  "BotLeftCorner", "BotRightCorner", "BottomBorder", "LeftBorder",
  "RightBorder", "TopRightCorner", "TopLeftCorner", "TopBorder",
}

local refs = nil
local current = "default"
local skinError = nil
local errorPrinted = {}

function theme.current() return current end

function theme.init(r)
  refs = refs or {}
  for k, v in pairs(r) do refs[k] = v end
  refs.buttons = refs.buttons or {}
  refs.dropdowns = refs.dropdowns or {}
  refs.windows = refs.windows or {}
  if r.window then refs.windows[#refs.windows + 1] = r.window end
end

local function ensureRefs()
  refs = refs or {} -- widgets announce before init hands over refs
  refs.buttons = refs.buttons or {}
  refs.dropdowns = refs.dropdowns or {}
  refs.windows = refs.windows or {}
  return refs
end

-- Guarded read of the user's Baganator skin key. Profiles live in
-- BAGANATOR_CONFIG.Profiles[BAGANATOR_CURRENT_PROFILE]; anything
-- unreadable means stock, which is the Blizzard skin.
-- Guarded walk to the user's Baganator profile table. Skin options
-- live nested under profile.skins.<skin> (their Config nests dotted
-- keys); anything unreadable falls back to the passed default.
local function baganatorProfile()
  local cfg = _G and _G.BAGANATOR_CONFIG or nil
  local prof = (_G and _G.BAGANATOR_CURRENT_PROFILE) or "DEFAULT"
  return cfg and cfg.Profiles and cfg.Profiles[prof] or nil
end

local function baganatorDarkOpt(key, default)
  local p = baganatorProfile()
  local dark = p and p.skins and p.skins.dark
  local v = dark and dark[key]
  if v == nil then return default end
  return v
end

local function baganatorSkinKey()
  local cfg = _G and _G.BAGANATOR_CONFIG or nil
  local prof = (_G and _G.BAGANATOR_CURRENT_PROFILE) or "DEFAULT"
  local p = cfg and cfg.Profiles and cfg.Profiles[prof]
  local key = p and p.current_skin
  return type(key) == "string" and key or "blizzard"
end

local function baganatorDark()
  if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Baganator")) then
    return false
  end
  return baganatorSkinKey() == "dark"
end

local function mixinBackdrop(frame)
  if Mixin and BackdropTemplateMixin and frame.Mixin then
    -- Avoid double-mixing: SetBackdrop existing means done.
    if not frame.SetBackdrop then frame:Mixin(BackdropTemplateMixin) end
  elseif Mixin and BackdropTemplateMixin and not frame.SetBackdrop then
    Mixin(frame, BackdropTemplateMixin)
  end
end

local function hideRegions(frame)
  for _, key in ipairs(STRIP_KEYS) do
    local r = frame[key]
    if r and r.SetAlpha then r:SetAlpha(0) end
    if r and r.Hide then r:Hide() end
  end
  if frame.NineSlice then
    for _, r in ipairs({ frame.NineSlice:GetRegions() }) do
      if r.SetAlpha then r:SetAlpha(0) end
      if r.Hide then r:Hide() end
    end
    if frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
  end
end

-- Resting colors for a Dark-look button: black fill, dimmer when
-- disabled, a gold tint while the button is held "pressed" (the active
-- Group-by mode, the reversed sort direction).
local function bgrRest(b)
  if not b.SetBackdropColor then return end
  if not b:IsEnabled() then
    b:SetBackdropColor(0, 0, 0, 0.1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
  elseif b.vwPressed then
    b:SetBackdropColor(ns.rgb(ns.COLORS.gold, 0.18))
    b:SetBackdropBorderColor(ns.rgb(ns.COLORS.gold, 1))
  else
    b:SetBackdropColor(0, 0, 0, 0.5)
    b:SetBackdropBorderColor(0, 0, 0, 1)
  end
end

-- Baganator Dark: StyleButton from Skins/Dark.lua, nil-safe for our
-- bare buttons. Colors are precomputed (Lighten of achromatic grays).
local function bgrStyleButton(b)
  if b.bgrStyled then
    -- Re-apply after a clear: hooks persist, colors do not.
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
      if b[key] and b[key].Hide then b[key]:Hide() end
    end
    bgrRest(b)
    return
  end
  b.bgrStyled = true
  for _, key in ipairs({ "Left", "Middle", "Right" }) do
    if b[key] and b[key].Hide then b[key]:Hide() end
  end
  if b.ClearHighlightTexture then b:ClearHighlightTexture() end
  mixinBackdrop(b)
  if not b.SetBackdrop then return end
  b:SetBackdrop({ bgFile = BGR_BG, edgeFile = BGR_EDGE,
    tile = true, tileEdge = true, tileSize = 32, edgeSize = 6 })
  bgrRest(b)
  b:HookScript("OnEnter", function()
    if b:IsEnabled() then
      b:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
      b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
  end)
  b:HookScript("OnMouseDown", function()
    if b:IsEnabled() then
      b:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
      b:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    end
  end)
  b:HookScript("OnMouseUp", function()
    if b:IsEnabled() and b:IsMouseOver() then
      b:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
      b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
  end)
  b:HookScript("OnLeave", function() bgrRest(b) end)
  b:HookScript("OnDisable", function() bgrRest(b) end)
  b:HookScript("OnEnable", function() bgrRest(b) end)
end

local function bgrUnstyleButton(b)
  -- The hooks stay (harmless: they recolor an invisible backdrop), but
  -- the backdrop itself goes transparent so stock art shows through.
  if b.SetBackdropColor then
    b:SetBackdropColor(0, 0, 0, 0)
    b:SetBackdropBorderColor(0, 0, 0, 0)
  end
  for _, key in ipairs({ "Left", "Middle", "Right" }) do
    if b[key] and b[key].Show then b[key]:Show() end
  end
end

-- Stock pressed look: the same texture swap UIPanelButton_OnMouseDown
-- does (SecureUIPanelTemplates.lua), held while vwPressed. The
-- template resets its art on mouse-up, show, and enable, so those are
-- hooked to re-apply. Under Dark the backdrop tint carries it instead.
local PANEL_UP = "Interface\\Buttons\\UI-Panel-Button-Up"
local PANEL_DOWN = "Interface\\Buttons\\UI-Panel-Button-Down"

local function paintPressed(b)
  if current == "baganator" and b.bgrStyled then
    bgrRest(b)
    return
  end
  if not (b.Left and b.Middle and b.Right and b:IsEnabled()) then return end
  local tex = b.vwPressed and PANEL_DOWN or PANEL_UP
  b.Left:SetTexture(tex)
  b.Middle:SetTexture(tex)
  b.Right:SetTexture(tex)
end

-- Dark look for the sort dropdown (WowStyle1DropdownTemplate): the
-- stock text-holder art goes, the button backdrop recipe takes over,
-- arrow and text stay. Approximates upstream, which skins its own
-- dropdowns the same way.
local function bgrStyleDropdown(d)
  if d.Background and d.Background.SetAlpha then d.Background:SetAlpha(0) end
  bgrStyleButton(d)
end

local function bgrUnstyleDropdown(d)
  if d.Background and d.Background.SetAlpha then d.Background:SetAlpha(1) end
  bgrUnstyleButton(d)
end

-- Sidebar tint and divider per look (mock: #vw-side).
local function paintSidebar()
  local s = refs and refs.sidebar
  if not s then return end
  if current == "baganator" then
    s.bg:SetColorTexture(0, 0, 0, 0.35)
    s.divider:SetColorTexture(0.165, 0.165, 0.165, 1)
  else
    s.bg:SetColorTexture(0, 0, 0, 0.25)
    s.divider:SetColorTexture(0.06, 0.07, 0.09, 1)
  end
end

-- Baganator Dark: ButtonFrame from Skins/Dark.lua. Their tag-driven top
-- button seating is skipped (those are their frames, not ours).
local function applyBaganatorWindow(window)
  hideRegions(window)
  if window.Inset then hideRegions(window.Inset) end
  mixinBackdrop(window)
  if not window.SetBackdrop then return end
  window:SetBackdrop({ bgFile = BGR_BG, edgeFile = BGR_EDGE,
    tile = true, tileEdge = true, tileSize = 32, edgeSize = 9 })
  -- Transparency and frame borders are live user options upstream.
  local t = tonumber(baganatorDarkOpt("view_transparency", 0.3)) or 0.3
  t = math.max(0, math.min(1, t))
  window:SetBackdropColor(BGR_FILL[1], BGR_FILL[2], BGR_FILL[3], 1 - t)
  if baganatorDarkOpt("no_frame_borders", false) then
    window:SetBackdropBorderColor(1, 1, 1, 0)
  else
    window:SetBackdropBorderColor(BGR_BORDER[1], BGR_BORDER[2], BGR_BORDER[3], 1)
  end
end

local function clearBaganatorWindow(window)
  if window.SetBackdropColor then
    window:SetBackdropColor(0, 0, 0, 0)
    window:SetBackdropBorderColor(0, 0, 0, 0)
  end
end

-- Per-widget styling. Called for every widget at creation (styles for
-- the current look) and re-run wholesale whenever the look changes.
-- skipDark leaves a button stock under the Dark look (upstream routes
-- tabs through a no-op skinner).
function theme.styleButton(b, skipDark)
  ensureRefs()
  refs.buttons[#refs.buttons + 1] = { b = b, skipDark = skipDark }
  if not b.vwPressHooked and b.HookScript then
    b.vwPressHooked = true
    for _, script in ipairs({ "OnMouseUp", "OnShow", "OnEnable" }) do
      b:HookScript(script, function(self) paintPressed(self) end)
    end
  end
  if current == "baganator" and not skipDark then
    bgrStyleButton(b)
  end
end

-- Hold a button in its pressed look (toggle state), or release it.
function theme.setPressed(b, on)
  b.vwPressed = on and true or false
  paintPressed(b)
end

function theme.styleDropdown(d)
  ensureRefs()
  refs.dropdowns[#refs.dropdowns + 1] = d
  if current == "baganator" then bgrStyleDropdown(d) end
end

-- Extra top-level frames (the handoff dialog) that dress with the look.
function theme.styleWindow(frame)
  ensureRefs()
  refs.windows[#refs.windows + 1] = frame
  if current == "baganator" then applyBaganatorWindow(frame) end
end

-- The sidebar panel: { bg = Texture, divider = Texture }.
function theme.styleSidebar(side)
  ensureRefs()
  refs.sidebar = side
  paintSidebar()
end

function theme.styleIcon(r)
  -- Square icons are opt-in upstream (skins.dark.square_icons, off by
  -- default). paintIcon owns the per-paint truth; this is just early.
  if current == "baganator" and baganatorDarkOpt("square_icons", false) then
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end

-- Icon paint hook. Quality and verdict stay visible in every theme:
-- Baganator re-borders icons when the user opts into square icons,
-- stock falls back to the quality plate.
function theme.paintIcon(r, quality, qcolor)
  -- Upstream crops and re-borders icons only when the user opts into
  -- square icons (off by default); otherwise icons keep the Blizzard
  -- rings, which our quality plate approximates below.
  if current == "baganator" and baganatorDarkOpt("square_icons", false) then
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.bg:SetColorTexture(0, 0, 0, 0.3) -- SlotBackground
    if not r.bgrBorder then
      r.bgrBorder = r.button:CreateTexture(nil, "ARTWORK", nil, 2)
      r.bgrBorder:SetTexture(BGR_ICON_BORDER)
      r.bgrBorder:SetAllPoints(r.icon)
    end
    local c = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality])
      or { r = qcolor[1], g = qcolor[2], b = qcolor[3] }
    r.bgrBorder:SetVertexColor(c.r, c.g, c.b, quality > 1 and 1 or 0.5)
    r.bgrBorder:Show()
  else
    r.icon:SetTexCoord(0, 1, 0, 1)
    r.bg:Show()
    r.bg:SetColorTexture(qcolor[1], qcolor[2], qcolor[3], 1)
    if r.bgrBorder then r.bgrBorder:Hide() end
  end
  -- Upstream hides slot backgrounds on request, whatever the icon shape.
  if current == "baganator" and baganatorDarkOpt("empty_slot_background", false) then
    r.bg:Hide()
  end
end

-- Queued ring (DESIGN 10). Queue state is data, not chrome, so the
-- gold inner edge is identical in every look; only the on/off lives
-- here so look changes re-dress it with everything else.
function theme.paintQueued(r, action)
  if not r.qr then return end
  if action then r.qr:Show() else r.qr:Hide() end
end

local function applyBaganator()
  for _, w in ipairs(refs.windows or {}) do applyBaganatorWindow(w) end
  for _, rec in ipairs(refs.buttons) do
    if not rec.skipDark then bgrStyleButton(rec.b) end
  end
  for _, d in ipairs(refs.dropdowns) do bgrStyleDropdown(d) end
  for _b in refs.iconPool:EnumerateActive() do theme.styleIcon(_b._rec) end
end

local function clearBaganator()
  for _, w in ipairs(refs.windows or {}) do clearBaganatorWindow(w) end
  for _, rec in ipairs(refs.buttons) do bgrUnstyleButton(rec.b) end
  for _, d in ipairs(refs.dropdowns) do bgrUnstyleDropdown(d) end
end

local function apply(style)
  if style == current then return end
  if current == "baganator" then
    clearBaganator()
  end
  current = style
  local ok, err = xpcall(function()
    if style == "baganator" then applyBaganator() end
  end, function(e) return e end)
  if not ok then
    -- Fall back to stock, stay retryable: decide() runs on every
    -- scan, so a transient failure heals and a systematic one shows
    -- here instead of wedging the look forever. Loud once, because a
    -- silently unskinned window is otherwise undebuggable.
    skinError = { style = style, err = tostring(err) }
    current = "default"
    if not errorPrinted[style] then
      errorPrinted[style] = true
      ns.say("the " .. style .. " look failed (" .. tostring(err) .. "), using stock; see /vw theme")
    end
  end
  -- Look-independent state re-dressed for the new look.
  for _, rec in ipairs(refs.buttons) do paintPressed(rec.b) end
  paintSidebar()
  if refs.repaint then refs.repaint() end
end

-- Re-resolve the look and apply it on change.
function theme.decide()
  if not refs then return end
  if baganatorDark() then
    apply("baganator")
    -- Options are live: refresh the dressing on every scan even when
    -- the look itself didn't change. Icons repaint in render().
    if current == "baganator" then
      for _, w in ipairs(refs.windows or {}) do applyBaganatorWindow(w) end
    end
  else apply("default") end
end

-- Read-only diagnosis for /vw theme.
function theme.status()
  local bgrLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    and C_AddOns.IsAddOnLoaded("Baganator")
  return {
    look = current,
    baganator = bgrLoaded or false,
    baganatorSkin = baganatorSkinKey(),
    error = skinError,
  }
end
