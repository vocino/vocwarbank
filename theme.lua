local _, ns = ...
local theme = {}
ns.theme = theme

-- Theme engine. One window, three looks, picked live:
--   ellesmere -> the suite's own textured shell, applied through its
--     public facade, so it matches by construction, not by imitation.
--   baganator -> a faithful replication of Baganator's Dark skin recipe
--     (same asset files, same backdrop sizes, same colors), used when
--     Baganator is loaded and running its Dark skin.
--   default   -> stock Blizzard chrome. This is also what Baganator's
--     own Blizzard skin looks like, so Blizzard-skin users match too.
--
-- Priority is EllesmereUI first: when both suites are present Baganator
-- itself auto-enables its EllesmereUI skin, so following the same order
-- keeps all three windows in one family.
--
-- Exact-token sources (read, not guessed):
--   EUI:  EllesmereUIBlizzardSkin_WindowEngine.lua + _SkinAPI.lua
--     (installed suite, v2 facade). Shell = modern_blizz.png cover-fit
--     + black 0.62 overlay + 25px top bar + AdventureMap_TopBorder.
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
local eui = nil -- facade handle, set when the suite skins us
local current = "default"
local skinError = nil
local errorPrinted = {}
local euiLegacyStrip -- forward: applyEllesmere runs before its definition

-- EUI facade calls outside apply() (fresh widgets arriving mid-session,
-- per-paint refreshes) degrade to stock on failure instead of breaking
-- the render. Loud once, like the apply() fallback.
local function euiCall(fn)
  local ok, err = pcall(fn)
  if ok then return true end
  skinError = skinError or { style = "ellesmere", err = tostring(err) }
  if not errorPrinted.ellesmere then
    errorPrinted.ellesmere = true
    ns.say("the ellesmere look failed (" .. tostring(err) .. "); using stock. See /vw theme.")
  end
  return false
end

function theme.current() return current end

function theme.init(r)
  refs = refs or {}
  for k, v in pairs(r) do refs[k] = v end
  refs.buttons = refs.buttons or {}
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

-- Baganator Dark: StyleButton from Skins/Dark.lua, nil-safe for our
-- bare buttons. Colors are precomputed (Lighten of achromatic grays).
local function bgrStyleButton(b)
  if b.bgrStyled then
    -- Re-apply after a clear: hooks persist, colors do not.
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
      if b[key] and b[key].Hide then b[key]:Hide() end
    end
    b:SetBackdropColor(0, 0, 0, b:IsEnabled() and 0.5 or 0.1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
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
  b:SetBackdropColor(0, 0, 0, 0.5)
  b:SetBackdropBorderColor(0, 0, 0, 1)
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
  b:HookScript("OnLeave", function()
    b:SetBackdropColor(0, 0, 0, 0.5)
    b:SetBackdropBorderColor(0, 0, 0, 1)
  end)
  b:HookScript("OnDisable", function() b:SetBackdropColor(0, 0, 0, 0.1) end)
  b:HookScript("OnEnable", function() b:SetBackdropColor(0, 0, 0, 0.5) end)
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
-- tabs through a no-op skinner). EUI still styles everything.
function theme.styleButton(b, withLabel, skipDark)
  refs = refs or { buttons = {} } -- widgets announce before init hands over refs
  refs.buttons[#refs.buttons + 1] = { b = b, label = withLabel, skipDark = skipDark }
  if current == "ellesmere" and eui then
    eui.Button(b)
    if withLabel then eui.StateButtonLabel(b) end
  elseif current == "baganator" and not skipDark then
    bgrStyleButton(b)
  end
end

function theme.styleIcon(r)
  if current == "ellesmere" and eui then
    local S = eui
    euiCall(function()
      if not r.button.IconBorder then
        -- Follow-mode reads quality back off the button's ring (shown,
        -- vertex-colored; the packs alpha theirs to 0 the same way).
        -- Our buttons have no Blizzard ring, so we carry the color on
        -- a hidden texture of our own under the exact field name.
        local ring = r.button:CreateTexture(nil, "OVERLAY")
        ring:SetAlpha(0)
        r.button.IconBorder = ring
      end
      S.Button(r.button, { "Icon", "Sel", "Dot", "IconBorder" })
      S.SquareIcon(r.icon, r.button, true)
      S.Font(r.count)
      S.Font(r.level)
    end)
  -- Square icons are opt-in upstream (skins.dark.square_icons, off by
  -- default). paintIcon owns the per-paint truth; this is just early.
  elseif current == "baganator" and baganatorDarkOpt("square_icons", false) then
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end

function theme.styleHeader(r)
  if current == "ellesmere" and eui then
    local S, label = eui, r.label
    euiCall(function()
      S.Font(label)
      S.White(label)
    end)
  end
  -- Other looks keep the creation font (GameFontNormalMed2): upstream
  -- sets it in view code, independent of the active skin.
end

-- Icon paint hook. Quality and verdict stay visible in every theme:
-- EUI reads it off a hidden ring, Baganator off its border texture,
-- stock falls back to the quality plate.
function theme.paintIcon(r, quality, qcolor)
  if current == "ellesmere" and eui then
    local S = eui
    local painted = euiCall(function()
      local c = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality])
        or { r = qcolor[1], g = qcolor[2], b = qcolor[3] }
      local ring = r.button.IconBorder
      if ring then
        ring:SetVertexColor(c.r, c.g, c.b, 1)
        ring:Show()
      end
      -- The rarity border carries quality now; the plate stands down.
      r.bg:Hide()
      if r.bgrBorder then r.bgrBorder:Hide() end
      S.SquareIcon(r.icon, r.button, true)
    end)
    if painted then return end
    -- A failed EUI paint falls through to the stock plate below.
  end
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
    -- Restore anything EUI stood down: the fallback path can land
    -- here after a failed EUI apply, and retries must repaint clean.
    r.bg:SetAlpha(1)
    r.bg:Show()
    if r.button.IconBorder then r.button.IconBorder:Hide() end
    r.bg:SetColorTexture(qcolor[1], qcolor[2], qcolor[3], 1)
    if r.bgrBorder then r.bgrBorder:Hide() end
  end
  -- Upstream hides slot backgrounds on request, whatever the icon shape.
  if current == "baganator" and baganatorDarkOpt("empty_slot_background", false) then
    r.bg:Hide()
  end
end

local function applyEllesmere()
  local S = eui
  S.Shell(refs.window)
  if refs.window.Inset then S.Inset(refs.window.Inset) end
  S.Panel(refs.scroll)
  S.CloseButton(refs.close)
  local sb = refs.scrollBar
  -- Shape dispatch: modern bars through the engine, legacy Slider
  -- bars stripped to the house look by hand (see euiLegacyStrip).
  if sb and sb.Track then S.ScrollBar(sb)
  elseif sb and sb.ThumbTexture then euiLegacyStrip(sb) end
  for _, rec in ipairs(refs.buttons) do
    S.Button(rec.b)
    if rec.label then S.StateButtonLabel(rec.b) end
  end
  S.Font(refs.title)
  S.White(refs.title)
  for _, t in ipairs(refs.texts) do S.Font(t) end
  for _b in refs.headPool:EnumerateActive() do theme.styleHeader(_b._rec) end
  for _b in refs.iconPool:EnumerateActive() do theme.styleIcon(_b._rec) end
end

local function applyBaganator()
  applyBaganatorWindow(refs.window)
  for _, rec in ipairs(refs.buttons) do
    if not rec.skipDark then bgrStyleButton(rec.b) end
  end
  for _b in refs.headPool:EnumerateActive() do theme.styleHeader(_b._rec) end
  for _b in refs.iconPool:EnumerateActive() do theme.styleIcon(_b._rec) end
end

local function clearBaganator()
  clearBaganatorWindow(refs.window)
  for _, rec in ipairs(refs.buttons) do bgrUnstyleButton(rec.b) end
end

-- The engine skins modern (Track/Thumb) bars only, and ours is the
-- legacy Slider bar (up/down steppers, knob thumb). Same house recipe
-- on our shape: steppers gone, thumb a 4px white 0.3 strip that the
-- Slider keeps positioning for us. Not called through S: marking the
-- bar skinned with nothing painted would poison a future engine pass.
function euiLegacyStrip(sb)
  if sb.ScrollUpButton and sb.ScrollUpButton.Hide then sb.ScrollUpButton:Hide() end
  if sb.ScrollDownButton and sb.ScrollDownButton.Hide then sb.ScrollDownButton:Hide() end
  local thumb = sb.ThumbTexture
  if thumb and thumb.SetColorTexture then
    if thumb.SetTexture then thumb:SetTexture("") end
    thumb:SetColorTexture(1, 1, 1, 0.3)
    if thumb.SetSize then thumb:SetSize(4, 24) end
  end
end

local function apply(style)
  if style == current then return end
  if current == "baganator" then
    clearBaganator()
  end
  -- EUI visuals are reload-bound by the suite's own design (their
  -- facade has no un-apply), so ellesmere never needs clearing here:
  -- leaving it always goes through a reload, which re-decides.
  current = style
  local ok, err = xpcall(function()
    if style == "ellesmere" then applyEllesmere()
    elseif style == "baganator" then applyBaganator() end
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
      ns.say("the " .. style .. " look failed (" .. tostring(err) .. "); using stock. See /vw theme.")
    end
  end
  if refs.repaint then refs.repaint() end
end

-- Re-resolve the look and apply it on change. EUI is sticky: once the
-- suite fires our callback it owns the chrome until reload.
function theme.decide()
  if not refs then return end
  if eui then apply("ellesmere")
  elseif baganatorDark() then
    apply("baganator")
    -- Options are live: refresh the dressing on every scan even when
    -- the look itself didn't change. Icons repaint in render().
    if current == "baganator" and refs.window then
      applyBaganatorWindow(refs.window)
    end
  else apply("default") end
end

-- Read-only diagnosis for /vw theme. The EllesmereUIDB keys mirror
-- the suite's own toggle checks (see its SkinAPI gating).
function theme.status()
  local db = _G and _G.EllesmereUIDB or nil
  local perAddon = db and db.thirdPartySkinAddons or nil
  local bgrLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    and C_AddOns.IsAddOnLoaded("Baganator")
  return {
    look = current,
    euiFacade = eui ~= nil,
    baganator = bgrLoaded or false,
    baganatorSkin = baganatorSkinKey(),
    euiMaster = not (db and db.thirdPartySkinsOff),
    euiAddon = not (perAddon and perAddon["VocWarbank"] == false),
    error = skinError,
  }
end

function theme.onEUISkin(S)
  eui = S
  theme.decide()
end
