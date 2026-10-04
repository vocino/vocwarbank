-- Headless tests for Warbank Audit. No game client needed.
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
  assert(loadfile(file))("WarbankAudit", ns)
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

-- 11. quest: completed -> trash, live -> keep
mock.reset()
mock.item(111, { classID = 12, expansionID = 9 })
mock.completedQuests[77] = "The Nexus Job"
mock.tooltips[111] = { "Scrap of Notes", "The Nexus Job" }
r = rank(111)
check("dead quest item trashes", r.verdict == "trash" and r.reason == "quest complete")

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

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail > 0 and 1 or 0)
