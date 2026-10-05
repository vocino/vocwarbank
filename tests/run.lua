-- Headless tests for VocWarbank. No game client needed.
-- Run from the repo root:  lua tests/run.lua

local mock = dofile("tests/mock.lua")
mock.install()

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1
  else fail = fail + 1 print("FAIL " .. name) end
end

local function loadAddon(file)
  local ns = mock.ns()
  assert(loadfile(file))("VocWarbank", ns)
  return ns
end

local function rank(id, extra)
  local ns = loadAddon("ranking.lua")
  local item = { itemID = id, scope = "bags", bag = 0, slot = 1,
                 link = mock.items[id] and mock.items[id].link or "|Hitem:1|h[x]|h|r" }
  if extra then for k, v in pairs(extra) do item[k] = v end end
  return ns.ranking.rank({ item })[1]
end

-- class IDs: 0 consumable, 2 weapon, 4 armor, 7 tradegoods, 12 quest,
-- 19 profession. qualities: 1 common, 2 green, 3 blue.

-- 1. uncollected appearance -> keep
mock.reset()
mock.item(101, { classID = 2, equipLoc = "INVTYPE_HEAD", quality = 3, expansionID = 11 })
local r = rank(101)
check("uncollected look keeps", r.verdict == "keep" and r.reason == "uncollected look")

mock.reset()
mock.item(101, { classID = 2, equipLoc = "INVTYPE_HEAD", quality = 3, expansionID = 11 })
mock.transmog[101] = true
r = rank(101)
check("collected look falls through", r.verdict == "keep" and r.reason == "needs review")

-- 2. equipment set -> keep
mock.reset()
mock.item(102, { classID = 4, equipLoc = "INVTYPE_CHEST", quality = 3, expansionID = 11 })
mock.transmog[102] = true
mock.sets[1] = { 102 }
r = rank(102)
check("equipment set keeps", r.verdict == "keep" and r.reason == "in equipment set")

-- 3. current-expansion tradegood -> keep; old one falls through
mock.reset()
mock.item(103, { classID = 7, expansionID = 11 })
r = rank(103)
check("current mats keep", r.verdict == "keep" and r.reason == "current mats")

mock.reset()
mock.item(103, { classID = 7, expansionID = 9, sellPrice = 50 })
r = rank(103)
check("old tradegood vendors", r.verdict == "vendor" and r.reason == "vendor price")

-- 4/5. never-sell / always-sell
mock.reset()
mock.item(104, { classID = 7, expansionID = 9, sellPrice = 50 })
mock.cfg.neverSell[104] = true
r = rank(104)
check("never-sell keeps", r.verdict == "keep" and r.reason == "never-sell list")

mock.reset()
mock.item(105, { classID = 7, expansionID = 9, sellPrice = 50 })
mock.cfg.alwaysSell[105] = true
mock.prices[105] = 200000
r = rank(105)
check("always-sell with value sells", r.verdict == "sell")

mock.reset()
mock.item(105, { classID = 7, expansionID = 9, sellPrice = 50 })
mock.cfg.alwaysSell[105] = true
r = rank(105)
check("always-sell without value vendors", r.verdict == "vendor")

-- 6. profession tool for a known profession -> keep
mock.reset()
mock.item(106, { classID = 19, subclassID = 0 })
mock.professionIndices = { 1 }
mock.professionSkills = { [1] = 164 }
r = rank(106)
check("profession tool keeps", r.verdict == "keep" and r.reason == "profession tool")

-- 7. openable -> use
mock.reset()
mock.item(107, { classID = 0, expansionID = 9 })
r = rank(107, { openable = true })
check("openable uses", r.verdict == "use" and r.reason == "openable")

-- 8. uncollected pet -> use; collected pet falls through
mock.reset()
mock.item(108, { classID = 0, expansionID = 9 })
mock.pets[108] = { speciesID = 42, owned = 0 }
r = rank(108)
check("uncollected pet uses", r.verdict == "use" and r.reason == "uncollected pet")

mock.reset()
mock.item(108, { classID = 0, expansionID = 9, sellPrice = 25 })
mock.pets[108] = { speciesID = 42, owned = 3 }
r = rank(108)
check("collected pet falls through", r.verdict == "vendor")

-- 9. BoE above threshold -> sell
mock.reset()
mock.item(109, { classID = 2, equipLoc = "INVTYPE_HEAD", bindType = 2, quality = 3, expansionID = 11 })
mock.transmog[109] = true
mock.prices[109] = 500000
r = rank(109)
check("valuable BoE sells", r.verdict == "sell" and r.reason == "worth listing")

-- 10. old green -> disenchant
mock.reset()
mock.item(110, { classID = 4, equipLoc = "INVTYPE_CHEST", quality = 2, expansionID = 9 })
mock.transmog[110] = true
r = rank(110)
check("old green disenchants", r.verdict == "disenchant" and r.reason == "disenchantable")

-- 11. quest: completed -> destroy, live -> keep
mock.reset()
mock.item(111, { classID = 12, expansionID = 9 })
mock.completedQuests[77] = "The Nexus Job"
mock.tooltips[111] = { "Scrap of Notes", "The Nexus Job" }
r = rank(111)
check("dead quest item destroys", r.verdict == "destroy" and r.reason == "quest complete")

mock.reset()
mock.item(111, { classID = 12, expansionID = 9 })
mock.tooltips[111] = { "Scrap of Notes", "The Ongoing Job" }
r = rank(111)
check("live quest item keeps", r.verdict == "keep" and r.reason == "quest item")

-- 12. vendor price -> vendor
mock.reset()
mock.item(112, { classID = 7, expansionID = 9, sellPrice = 150 })
r = rank(112)
check("vendor price vendors", r.verdict == "vendor" and r.reason == "vendor price")

-- 13. unknown item -> keep for review
mock.reset()
local ns = loadAddon("ranking.lua")
r = ns.ranking.rank({ { itemID = 99999, link = "|Hitem:99999|h[x]|h|r",
                        scope = "bags", bag = 0, slot = 1 } })[1]
check("unknown keeps for review", r.verdict == "keep" and r.reason == "needs review")

-- scanner: bags
mock.reset()
mock.bags[0] = {
  [1] = { link = "|Hitem:201|h[x]|h|r", count = 5, quality = 1 },
  [3] = { link = "|Hitem:202|h[x]|h|r" },
}
local sns = loadAddon("scanner.lua")
local out = sns.scanner.scan("bags")
check("scanBags finds 2", #out == 2)
check("scanBags fields", out[1].scope == "bags" and out[1].bag == 0
  and out[1].itemID == 201 and out[1].count == 5)

-- scanner: bank (main bank, bank bag, reagent bank)
mock.reset()
mock.bags[-1] = { [1] = { link = "|Hitem:301|h[x]|h|r" } }
mock.bags[5] = { [2] = { link = "|Hitem:302|h[x]|h|r", count = 3 } }
mock.bags[-3] = { [1] = { link = "|Hitem:303|h[x]|h|r" } }
sns = loadAddon("scanner.lua")
out = sns.scanner.scan("bank")
check("scanBank finds 3", #out == 3)
check("scanBank scope", out[1].scope == "bank" and out[1].bag == -1 and out[1].itemID == 301)

-- scanner: empty bank
mock.reset()
sns = loadAddon("scanner.lua")
out = sns.scanner.scan("bank")
check("empty bank scans clean", #out == 0)

-- main.lua: slash registration and chat voice
_G.SlashCmdList = _G.SlashCmdList or {}
local mainNs = loadAddon("main.lua")
check("short slash is /vw", _G.SLASH_VOCWARBANK1 == "/vw")
check("long slash is /vocwarbank", _G.SLASH_VOCWARBANK2 == "/vocwarbank")
check("slash handler installed", type(_G.SlashCmdList.VOCWARBANK) == "function")
do
  local said
  local realPrint = print
  print = function(s) said = s end
  mainNs.say("hello")
  print = realPrint
  check("say prefixes the addon name", said == "|c" .. mainNs.PREFIX_COLOR .. "VocWarbank|r: hello")
  check("family prefix color", mainNs.PREFIX_COLOR == "ff66ccff")
end

-- config: the real module against a scratch SavedVariable
local function loadConfig(db)
  local cns = { db = db }
  assert(loadfile("config.lua"))("VocWarbank", cns)
  return cns
end

do
  local cns = loadConfig({})
  cns.config.init()
  check("config fills defaults",
    cns.db.priceSource == "auto" and cns.db.scope == "bags"
    and cns.db.ahThreshold == 100000 and type(cns.db.neverSell) == "table")
  cns.db.neverSell[5] = true
  cns.db = {}
  cns.config.init()
  check("config table defaults are not shared", cns.db.neverSell[5] == nil)
end

do
  local cns = loadConfig({
    neverSell = "junk", alwaysSell = 42, collapsedGroups = 7,
    ahThreshold = "lots", scope = "everywhere", priceSource = "ebay",
    inventorySource = "syndicator", sortMode = "chaos",
    autoOpenVendor = "yes", tsmKey = "", enchanter = 42,
  })
  cns.config.init()
  check("config repairs corrupt lists",
    type(cns.db.neverSell) == "table" and next(cns.db.neverSell) == nil
    and type(cns.db.alwaysSell) == "table" and type(cns.db.collapsedGroups) == "table")
  check("config repairs corrupt threshold", cns.db.ahThreshold == 100000)
  check("config repairs bad enums",
    cns.db.scope == "bags" and cns.db.priceSource == "auto" and cns.db.sortMode == "off")
  check("config repairs bad scalars",
    cns.db.autoOpenVendor == false and cns.db.tsmKey == "DBMarket" and cns.db.enchanter == "")
  check("config keeps valid values", cns.db.inventorySource == "syndicator")
end

do
  local cns = loadConfig({ source = "builtin" })
  cns.config.init()
  check("config migrates legacy source",
    cns.db.priceSource == "vendor" and cns.db.source == nil)
end

do
  local cns = loadConfig(nil)
  check("config.get safe before load", cns.config.get("scope") == "bags")
  cns.config.set("scope", "all") -- must not error
  check("config.set safe before load", cns.config.get("scope") == "all")
end

-- scanner: modern bank numbering with Enum (reagent bag 5 excluded, bank bag 12 kept)
mock.reset()
_G.Enum = { BagIndex = {
  Bank = -1, Reagentbank = -3,
  BankBag_1 = 6, BankBag_2 = 7, BankBag_3 = 8, BankBag_4 = 9,
  BankBag_5 = 10, BankBag_6 = 11, BankBag_7 = 12,
} }
mock.bags[5] = { [1] = { link = "|Hitem:401|h[x]|h|r" } }
mock.bags[12] = { [1] = { link = "|Hitem:402|h[x]|h|r" } }
sns = loadAddon("scanner.lua")
out = sns.scanner.scan("bank")
check("modern bank skips reagent bag, keeps bank bags",
  #out == 1 and out[1].itemID == 402 and out[1].bag == 12)
_G.Enum = nil

-- ranking: quest cache invalidates on demand
mock.reset()
mock.item(111, { classID = 12, expansionID = 9 })
mock.tooltips[111] = { "Scrap of Notes", "The Nexus Job" }
local qns = loadAddon("ranking.lua")
local qi = { itemID = 111, scope = "bags", bag = 0, slot = 1, link = mock.items[111].link }
check("live quest item keeps", qns.ranking.rank({ qi })[1].verdict == "keep")
mock.completedQuests[77] = "The Nexus Job"
check("quest cache is sticky within session",
  qns.ranking.rank({ qi })[1].verdict == "keep")
qns.ranking.refreshQuests()
local q3 = qns.ranking.rank({ qi })[1]
check("quest refresh re-ranks to destroy", q3.verdict == "destroy" and q3.reason == "quest complete")
local hasTrash = false
for _, v in ipairs(qns.ranking.verdictOrder) do if v == "trash" then hasTrash = true end end
check("trash is no longer a verdict", not hasTrash and qns.ranking.verdictOrder[#qns.ranking.verdictOrder] == "destroy")

-- ranking: live profession check for the window's disenchant button
mock.reset()
mock.professionIndices = { 1 }
mock.professionSkills = { [1] = 333 }
local pns2 = loadAddon("ranking.lua")
check("enchanting skill constant", pns2.ranking.SKILL_ENCHANTING == 333)
check("hasProfession sees enchanting", pns2.ranking.hasProfession(333) == true)
check("hasProfession misses others", pns2.ranking.hasProfession(164) == false)

-- main.lua: slash arg handling (chat captured, then restored before checks)
mock.reset()
local mns = loadAddon("main.lua")
mns.providers.init = function() end
local rescans, toggles, opened = 0, 0, 0
mns.ui = {
  isOpen = function() return true end,
  rescan = function() rescans = rescans + 1 end,
  toggle = function() toggles = toggles + 1 end,
}
mns.settings = { open = function() opened = opened + 1 end }
local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end
_G.SlashCmdList.VOCWARBANK("source TSM")
_G.SlashCmdList.VOCWARBANK("inventory Blizzard")
_G.SlashCmdList.VOCWARBANK("scope BAGS")
_G.SlashCmdList.VOCWARBANK("threshold 5")
_G.SlashCmdList.VOCWARBANK("never 123")
_G.SlashCmdList.VOCWARBANK("tsmkey DBMinBuyout")
local beforeHelp = #printed
_G.SlashCmdList.VOCWARBANK("bogus-command")
local afterBogus = #printed
_G.SlashCmdList.VOCWARBANK("help")
_G.SlashCmdList.VOCWARBANK("")
_G.SlashCmdList.VOCWARBANK("config")
print = realPrint
check("slash source is case-insensitive", mock.cfg.priceSource == "tsm")
check("slash inventory is case-insensitive", mock.cfg.inventorySource == "blizzard")
check("slash scope is case-insensitive", mock.cfg.scope == "bags")
check("slash threshold sets copper", mock.cfg.ahThreshold == 50000)
check("slash never lists the item", mock.cfg.neverSell[123] == true)
check("slash tsmkey keeps case", mock.cfg.tsmKey == "DBMinBuyout")
check("slash refreshes the open window", rescans == 6)
check("unknown command prints help", afterBogus - beforeHelp == 1 + #mns.HELP)
check("help prints every line", #printed - afterBogus == 1 + #mns.HELP)
check("bare /vw toggles the window", toggles == 1)
check("/vw config opens the panel", opened == 1)
check("chat lines carry the prefix", printed[1]:find("^|cff66ccffVocWarbank|r: ") ~= nil)

-- settings.lua: native panel bound to the live SavedVariables
do
  local reg, checks, drops, callbacks = {}, 0, {}, {}
  local openedID, headers = nil, {}
  _G.Settings = {
    RegisterVerticalLayoutCategory = function(n)
      return { name = n, GetID = function() return 7 end }
    end,
    RegisterAddOnCategory = function() end,
    RegisterAddOnSetting = function(_, var, key, tbl, typ, label, default)
      reg[key] = { var = var, tbl = tbl, type = typ, label = label, default = default }
      local s = {}
      s.SetValueChangedCallback = function(_, fn) callbacks[key] = fn end
      return s
    end,
    CreateCheckbox = function() checks = checks + 1 end,
    CreateDropdown = function(_, _, options) drops[#drops + 1] = options end,
    CreateControlTextContainer = function()
      local t = { data = {} }
      t.Add = function(_, v, text) t.data[#t.data + 1] = { value = v, text = text } end
      t.GetData = function() return t.data end
      return t
    end,
    OpenToCategory = function(id) openedID = id end,
  }
  _G.SettingsPanel = { GetLayout = function() return {
    AddInitializer = function(_, init) headers[#headers + 1] = init end,
  } end }
  _G.CreateSettingsListSectionHeaderInitializer = function(text) return text end
  local pns = { db = {} }
  assert(loadfile("config.lua"))("VocWarbank", pns)
  pns.config.init()
  local inits, panelRescans = 0, 0
  pns.providers = { init = function() inits = inits + 1 end }
  pns.ui = { isOpen = function() return true end, rescan = function() panelRescans = panelRescans + 1 end }
  assert(loadfile("settings.lua"))("VocWarbank", pns)
  pns.settings.init()
  for _, key in ipairs({ "priceSource", "inventorySource", "scope", "ahThreshold",
      "autoOpenVendor", "autoOpenAuction" }) do
    check("panel registers " .. key, reg[key] ~= nil and reg[key].var == "VocWarbank_" .. key)
    check("panel binds " .. key .. " to the live table", reg[key] and reg[key].tbl == pns.db)
    check("panel default for " .. key .. " matches config",
      reg[key] and reg[key].default == pns.config.default(key)
      and reg[key].type == type(pns.config.default(key)))
  end
  check("four dropdowns, two checkboxes", #drops == 4 and checks == 2)
  check("slash-line note added", headers[1] == "More on the slash line: /vw help")
  local scopeData = drops[3]()
  check("scope dropdown lists all four", #scopeData == 4 and scopeData[1].value == "bags")
  local th = drops[4]()
  check("threshold presets only by default", #th == #pns.settings.thresholdGold
    and th[3].value == 100000 and th[3].text == "10g")
  pns.db.ahThreshold = 123450 -- /vw threshold 12.345
  th = drops[4]()
  local custom
  for i, opt in ipairs(th) do
    if opt.value == 123450 then custom = opt end
    if i > 1 then check("threshold list stays sorted", th[i - 1].value < opt.value) end
  end
  check("custom threshold joins the list", custom ~= nil and custom.text == "12.35g (custom)")
  callbacks.priceSource()
  check("price source change re-inits providers and rescans", inits == 1 and panelRescans == 1)
  callbacks.scope()
  check("scope change rescans", panelRescans == 2)
  pns.settings.open()
  check("open goes to the category", openedID == 7)
  pns.settings.init()
  check("init is idempotent", #drops == 4)
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
end

-- settings.lua without the Settings API: no-op init, open says where
do
  local nns = { db = {} }
  assert(loadfile("config.lua"))("VocWarbank", nns)
  nns.config.init()
  local said
  nns.say = function(line) said = line end
  assert(loadfile("settings.lua"))("VocWarbank", nns)
  nns.settings.init()
  nns.settings.open()
  check("open without Settings prints the path", said == "open Settings > AddOns > VocWarbank")
end

-- theme.lua: two looks, no Ellesmere. decide() resolves baganator vs
-- default from the live Baganator state; status() reports no EUI fields.
do
  local tns = loadAddon("theme.lua")
  local emptyPool = { EnumerateActive = function() return function() end end }
  tns.theme.init({ window = {}, headPool = emptyPool, iconPool = emptyPool })
  _G.C_AddOns = nil
  _G.BAGANATOR_CONFIG, _G.BAGANATOR_CURRENT_PROFILE = nil, nil
  tns.theme.decide()
  check("stock without Baganator", tns.theme.current() == "default")
  local st = tns.theme.status()
  check("status has no EUI fields", st.euiFacade == nil and st.euiMaster == nil and st.euiAddon == nil)
  check("status reports stock", st.look == "default" and st.baganator == false)
  _G.C_AddOns = { IsAddOnLoaded = function(name) return name == "Baganator" end }
  _G.BAGANATOR_CURRENT_PROFILE = "DEFAULT"
  _G.BAGANATOR_CONFIG = { Profiles = { DEFAULT = { current_skin = "dark" } } }
  tns.theme.decide()
  check("dark Baganator picks baganator", tns.theme.current() == "baganator")
  st = tns.theme.status()
  check("status reports baganator", st.look == "baganator" and st.baganatorSkin == "dark")
  check("no EUI entry point", tns.theme.onEUISkin == nil)
  _G.C_AddOns, _G.BAGANATOR_CONFIG, _G.BAGANATOR_CURRENT_PROFILE = nil, nil, nil
end

-- ui.lua: pure helpers behind the window (no frames needed at load)
do
  mock.reset()
  local uns = loadAddon("ui.lua")
  local u = uns.ui
  local function e(id, verdict, extra)
    local entry = { verdict = verdict, reason = "x",
      item = { itemID = id, scope = "bags", bag = 0, slot = id, count = 1,
               link = "|cffffffff|Hitem:" .. id .. "|h[Item " .. id .. "]|h|r" } }
    for k, v in pairs(extra or {}) do entry.item[k] = v end
    return entry
  end
  check("gold formats with grouping", u.formatGold(12400000) == "1,240g"
    and u.formatGold(1234567) == "123g" and u.formatGold(250) == "2s" and u.formatGold(nil) == "?")

  -- facets: "all" leads, verdicts follow ranking order, unknowns trail
  local order = { "keep", "use", "sell", "disenchant", "vendor", "destroy" }
  local ranked = { e(1, "vendor"), e(2, "keep"), e(3, "destroy"), e(4, "vendor"), e(5, "zzz") }
  local present, counts = u.facetCounts(ranked, order)
  check("facets lead with all", present[1] == "all" and counts.all == 5)
  check("facets follow verdict order", present[2] == "keep" and present[3] == "vendor" and present[4] == "destroy")
  check("facets count per verdict", counts.vendor == 2 and counts.keep == 1 and counts.destroy == 1)
  check("unknown verdicts trail", present[5] == "zzz" and #present == 5)

  -- disenchant partition: in person any bag item goes; by mail soulbound
  -- stays; stowed never goes
  local de = { e(10, "disenchant"), e(11, "disenchant", { bound = true }),
    e(12, "disenchant", { scope = "bank", bag = -1, slot = 3 }) }
  local ready, blocked = u.dePartition(de, true)
  check("in person takes soulbound", #ready == 2 and blocked.soulbound == 0 and blocked.stowed == 1)
  check("in person note", u.blockedNote(blocked) == "1 can't go: 1 stowed")
  ready, blocked = u.dePartition(de, false)
  check("mail skips soulbound", #ready == 1 and ready[1].item.itemID == 10
    and blocked.soulbound == 1 and blocked.stowed == 1 and blocked.total == 2)
  check("mail note lists both", u.blockedNote(blocked) == "2 can't go: 1 soulbound, 1 stowed")
  check("no note when clear", u.blockedNote({ soulbound = 0, stowed = 0, total = 0 }) == nil)

  -- selection totals: destroy queues, keep counts aside
  local sel = {}
  for _, entry in ipairs(ranked) do sel[u.entryKey(entry)] = true end
  local queued, totals, keeps = u.computeSelection(ranked, sel)
  check("destroy is actionable", totals.groups.destroy == 1 and totals.groups.vendor == 2)
  check("keep and unknown verdicts are not queued", #queued == 3 and keeps == 2)
  check("trash is not a verdict the window knows", totals.groups.trash == nil)

  -- sort: value desc, reverse flips, ties keep bag order
  local list = { e(1, "vendor"), e(2, "vendor"), e(3, "vendor") }
  list[1].value, list[2].value, list[3].value = 50, 500, 500
  u.sortEntries(list, "value", false)
  check("value sort descends, stable", list[1].item.itemID == 2 and list[2].item.itemID == 3 and list[3].item.itemID == 1)
  u.sortEntries(list, "value", true)
  check("reverse sort ascends", list[1].item.itemID == 1)
  check("sort labels name bag order", u.SORT_LABEL.off == "Bag order" and u.SORT_MODES[1] == "off")

  -- sections: pins lead, sub-split on the other axis
  local armor = { e(20, "keep"), e(21, "keep"), e(22, "keep") }
  for _, entry in ipairs(armor) do entry.detail = { classID = 4 } end
  armor[3].item.itemID = 9001
  local exp = { [20] = "tww", [21] = "df", [9001] = "tww" }
  local sections = u.buildSections(armor, "category", function(id) return exp[id] end, "all",
    { never = { [9001] = true }, always = {} })
  check("never-sell pins first", sections[1].label == "Never Sell" and #sections[1].entries == 1)
  check("armor splits by expansion", sections[2].label == "Armor: The War Within"
    and sections[3].label == "Armor: Dragonflight")
  check("filter narrows sections", #u.buildSections(armor, "category", function() return nil end, "vendor") == 0)
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail > 0 and 1 or 0)
