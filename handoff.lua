local _, ns = ...
local handoff = {}
ns.handoff = handoff

-- Merchant handoff dialog (DESIGN 10, mock/triage.html #vw-handoff): a
-- light frame docked beside the merchant listing the queued vendor
-- items, with one Sell button. The dialog never sells on its own; the
-- click is the confirmation (SPEC: no auto-sell). Shaped for future
-- actions: show/refresh take the action, only vendor has a trigger
-- today (MERCHANT_SHOW, wired in ui.lua).

local HW_W = 300
local HW_ROW_Y, HW_ROW_PITCH, HW_ROW_H = 30, 24, 20
local HW_MAX_ROWS = 8
local HW_MARGIN = 12
local HW_FOOT_H = 42
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local ACTION_TITLE = { vendor = "Vendor" }

local dialog, sellBtn, laterBtn, moreNote
local rows = {}
local currentAction = nil
local currentResolved = nil

-- A fresh full-scope scan, priced like ui.rescan. Stowed detection
-- needs the bank/warbank scopes, not just bags.
local function scanAll()
  local ranked = ns.ranking.rank(ns.scanner.scan("all"))
  local provider = ns.providers.get()
  for _, entry in ipairs(ranked) do
    local price = provider and provider.GetMarketValue(entry.item.link) or nil
    entry.value = price and price * (entry.item.count or 1) or nil
  end
  return ranked
end

local function buildRow(i)
  local f = CreateFrame("Frame", nil, dialog)
  f:SetSize(HW_W - HW_MARGIN * 2, HW_ROW_H)
  f:SetPoint("TOPLEFT", dialog, "TOPLEFT", HW_MARGIN, -(HW_ROW_Y + (i - 1) * HW_ROW_PITCH))
  local art = f:CreateTexture(nil, "ARTWORK")
  art:SetSize(HW_ROW_H, HW_ROW_H)
  art:SetPoint("LEFT", f, "LEFT", 0, 0)
  local name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  name:SetPoint("LEFT", art, "RIGHT", 6, 0)
  name:SetWidth(170)
  name:SetJustifyH("LEFT")
  local val = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  val:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f:Hide()
  return { frame = f, art = art, name = name, val = val }
end

local function paintRow(r, icon, text, value, dim)
  if icon then r.art:SetTexture(icon)
  else r.art:SetTexture(QUESTION_MARK) end
  r.name:SetText(text)
  r.val:SetText(value or "")
  r.frame:SetAlpha(dim and 0.55 or 1)
  r.frame:Show()
end

local function buildDialog()
  dialog = CreateFrame("Frame", "VocWarbankHandoff", UIParent, "BasicFrameTemplateWithInset")
  dialog:SetSize(HW_W, 120)
  dialog:SetPoint("CENTER")
  dialog:SetMovable(true)
  dialog:EnableMouse(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", dialog.StartMoving)
  dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
  dialog:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "VocWarbankHandoff") end
  dialog.TitleText:SetText("VocWarbank")
  -- BasicFrameTemplate ships its own CloseButton (UIPanelTemplates.xml);
  -- an older template without one gets a stock close button.
  if not dialog.CloseButton then
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)
  end
  for i = 1, HW_MAX_ROWS do rows[i] = buildRow(i) end
  moreNote = dialog:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  moreNote:SetPoint("TOPLEFT", dialog, "TOPLEFT", HW_MARGIN, -HW_ROW_Y)
  moreNote:Hide()
  sellBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  sellBtn:SetSize(184, 22)
  sellBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", HW_MARGIN, 12)
  sellBtn:SetScript("OnClick", function() handoff.sell() end)
  if sellBtn.SetMotionScriptsWhileDisabled then sellBtn:SetMotionScriptsWhileDisabled(true) end
  ns.theme.styleButton(sellBtn)
  laterBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  laterBtn:SetSize(80, 22)
  laterBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -HW_MARGIN, 12)
  laterBtn:SetText("Not now")
  laterBtn.tooltipText = "Close this dialog; the queue stays for next time"
  laterBtn:SetScript("OnClick", function() dialog:Hide() end)
  ns.theme.styleButton(laterBtn)
  ns.theme.styleWindow(dialog)
end

function handoff.hide()
  currentAction = nil
  currentResolved = nil
  if dialog then dialog:Hide() end
end

function handoff.isShown()
  return dialog and dialog:IsShown() or false
end

-- Re-resolve the queue against a live scan and repaint. No-op while
-- hidden (bag traffic must not pop the dialog); empties close it.
function handoff.refresh()
  if not (dialog and dialog:IsShown() and currentAction) then return end
  if ns.queue.empty(currentAction) then handoff.hide() return end
  local res = ns.queue.resolve(currentAction, scanAll())
  currentResolved = res
  local shown, more, gold = 0, 0, 0
  local function show(icon, text, value, dim)
    if shown >= HW_MAX_ROWS then more = more + 1 return end
    shown = shown + 1
    paintRow(rows[shown], icon, text, value, dim)
  end
  for _, entry in ipairs(res.ready) do
    local item = entry.item
    gold = gold + (entry.value or 0)
    local icon = item.icon or (item.itemID and C_Item.GetItemIconByID(item.itemID)) or nil
    local text = ns.ui.linkName(item.link) .. ((item.count or 1) > 1 and (" ×" .. item.count) or "")
    show(icon, text, entry.value and ns.ui.formatGold(entry.value) or nil, false)
  end
  local function showLeftover(list, why)
    for _, row in ipairs(list) do
      local icon = row.id and C_Item.GetItemIconByID(row.id) or nil
      local text = ns.ui.linkName(row.link)
        .. (row.n > 1 and (" ×" .. row.n) or "") .. " (" .. why .. ")"
      show(icon, text, nil, true)
    end
  end
  showLeftover(res.stowed, "stowed")
  showLeftover(res.missing, "not in bags")
  for i = shown + 1, HW_MAX_ROWS do rows[i].frame:Hide() end
  dialog:SetHeight(HW_ROW_Y + shown * HW_ROW_PITCH + HW_FOOT_H + (more > 0 and 16 or 0))
  if more > 0 then
    moreNote:SetText("+" .. more .. " more")
    moreNote:ClearAllPoints()
    moreNote:SetPoint("TOPLEFT", dialog, "TOPLEFT", HW_MARGIN, -(HW_ROW_Y + shown * HW_ROW_PITCH))
    moreNote:Show()
  else
    moreNote:Hide()
  end
  local stacks = #res.ready == 1 and "stack" or "stacks"
  sellBtn:SetText("Sell " .. #res.ready .. " " .. stacks .. " (~" .. ns.ui.formatGold(gold) .. ")")
  if #res.ready > 0 then
    sellBtn:Enable()
    sellBtn.tooltipText = "Sell the listed stacks (whole stacks sell)"
  else
    sellBtn:Disable()
    sellBtn.tooltipText = "Nothing in bags to sell"
  end
end

-- Sell the resolved stacks. The button click is the hardware event that
-- makes the protected container calls legal; ui.vendorQueued runs them
-- and rescans the main window, then the sold rows drain from the queue.
function handoff.sell()
  if not (currentAction and currentResolved) then return end
  local ready = currentResolved.ready
  if #ready == 0 then return end
  local n = ns.ui.vendorQueued(ready)
  local left = ns.queue.prune(currentAction, ready)
  if left == 0 then handoff.hide()
  else handoff.refresh() end
  ns.say("sold " .. n .. " " .. (n == 1 and "stack" or "stacks")
    .. (left > 0 and (" (" .. left .. " still queued)") or "") .. ".")
end

-- Pop the dialog for an action. Docks beside the merchant, away from
-- the main window when it is open; an undockable screen centers it.
function handoff.show(action)
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  currentAction = action
  if not dialog then buildDialog() end
  dialog.TitleText:SetText("VocWarbank: " .. (ACTION_TITLE[action] or action))
  dialog:Show()
  handoff.refresh()
  if not dialog:IsShown() then return end -- emptied under us
  local preferLeft = false
  if ns.ui.isOpen() then
    local main = _G.VocWarbankWindow
    local mx = main and main.GetCenter and main:GetCenter() or nil
    local hx = MerchantFrame:GetCenter()
    if mx and hx and mx > hx then preferLeft = true end
  end
  if not ns.ui.dockBeside(dialog, MerchantFrame, preferLeft) then
    dialog:ClearAllPoints()
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- Show only when there is something to hand off.
function handoff.maybeShow(action)
  if ns.queue.empty(action) then return end
  handoff.show(action)
end

-- The queue changed out from under the dialog (slash clear): re-resolve
-- or close.
function handoff.onQueueChanged()
  if not (dialog and dialog:IsShown() and currentAction) then return end
  if ns.queue.empty(currentAction) then handoff.hide()
  else handoff.refresh() end
end
