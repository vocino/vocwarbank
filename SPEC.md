# Warbank Audit — Spec

A tiny WoW addon. Audit your stuff anywhere, see everything ranked by
usefulness, draw a line, clean house.

## Name (decided 2026-10-02)

**Warbank Audit.** "Warbank" is the player term for warband bank;
short, distinctive, no collision risk, "bank" in the name for
CurseForge/Wago search. Listing description carries the keywords:
"audit and clean your warband bank, bank, and bags."

Candidates considered: Bank Audit (most literal, too generic),
Warband Bank Cleaner (matches search phrasing, forgettable).

## Problem

Every expansion leaves junk in the warband bank: old reagents, dead
quest items, gear with no purpose. Nothing triages it. You either
eyeball hundreds of slots or never clean at all.

## Non-goals

- Not a bag addon. Not an auction addon.
- No auto-sell, no auto-destroy. The user confirms every action.
- No website, no backend, no account. Pure client addon.

## V1 Scope

- The scanner is container-agnostic from day one. Scope picker:
  warband bank, character bank, bags, or all three at once.
- The ranking core is identical for every scope; only the item
  source changes.
- One window: ranked list, draggable cutoff line, action queue.
- `/ww` slash command. No minimap button.

## Architecture

Two layers. The UI never talks to third-party addons directly.

```
WarbankAudit/
  main.lua      boot, slash command
  config.lua    settings, never-sell lists
  providers.lua data layer behind one contract (Data)
  scanner.lua   container-agnostic item scan
  ranking.lua   verdict rules (Core)
  ui.lua        the triage window (UI)
```

### Provider contract

```lua
-- expansion key like "tww", "midnight", or nil if unknown
Provider.GetExpansion(itemID) -> string | nil

-- market value in copper, or nil if unknown
Provider.GetMarketValue(itemLink) -> number | nil
```

### Providers

Prices cascade through the configured source, then vendor. Auto
order follows install base: Auctionator -> TSM -> Oribos Exchange
-> vendor prices. Expansion always comes from the item itself.

1. **Auctionator** (optional). Realm min-buyout from its scan DB.
2. **TSM** (optional). Evaluates the configured price key (DBMarket).
3. **Oribos Exchange** (optional). Realm market value, region fallback.
4. **Vendor** (always available). Sell price ends every cascade.
Warbank contents come from Syndicator (Baganator's data) when
present; Blizzard bank scans are future work.
All external calls are presence-gated and pcall-guarded, so a
broken pricing addon can never break a scan.
The user picks price and warbank sources in settings (Auto by
default); the window header shows the active price source.

Availability is checked live on every lookup, so late-loading
addons join the cascade with no reload.
(Auctioneer has no Midnight retail build and is not supported.)

## Ranking

Each item is checked against these rules in order. First match sets
the verdict.

1. Appearance not collected -> KEEP
2. In a saved equipment set -> KEEP
3. Current-expansion consumable, reagent, or trade good -> KEEP
4. On the never-sell list -> KEEP
5. On the always-sell list -> SELL (valued) or VENDOR
6. Openable container -> USE
7. Uncollected collectable (decor, pet, mount, toy) -> USE
8. Bind-on-equip gear, market value above threshold
   -> SELL (auction house)
9. Old-expansion uncommon or rare gear -> DISENCHANT (epics keep
   buyback through VENDOR instead)
10. Quest item -> KEEP (log check is future work)
11. Has a vendor price -> VENDOR
12. Anything else -> KEEP ("needs review"; never destroy by default)

## The window

- Header: item count, slots to free, estimated gold, active data
  source.
- Body: Baganator-style icon grid grouped by category or expansion.
  Icons show stack count, item level, quality border, and a verdict
  dot; hover for name, value, and reason tag.
- Selection: click icons or group headers to queue them. Verdict
  filter tabs narrow the grid.
- Footer: dry-run summary ("142 items, 38 slots, ~12,400g"), then per-group action buttons.

## Looks

One window, three looks, picked live by theme.lua:

- EllesmereUI present (and skinning us): the suite's own textured
  shell through its public facade — Shell, Panel, Inset, Button,
  SquareIcon in follow-mode off a hidden quality ring per tile,
  and a replicated house thumb strip on our legacy scrollbar (the
  engine only skins modern bars) — matching by construction,
  construction, including the Modern flat variant.
- Baganator loaded and running its Dark skin: a faithful
  replication of Skins/Dark.lua — same backdrop assets
  (dark-backgroundfile/dark-edgefile, edge 9 window / 6 buttons),
  same fill (0.05 at alpha 0.7) and border (0.35), same button
  hover/press/disabled behavior, category headers in
  GameFontNormalMed2, icons cropped with dark-icon-border in
  quality colors.
- Otherwise stock Blizzard chrome, which is also what
  Baganator's own Blizzard skin looks like.

EllesmereUI wins when both are present (Baganator itself
auto-enables its EllesmereUI skin then, so all three match).
Quality and verdict colors stay ours in every look — they are
data, not chrome. Looks re-resolve on every scan; EUI is sticky
until reload by the suite's own design. A failed look falls back
to stock, says so once in chat, and retries on the next scan; `/ww
theme` reports the live look, the EUI toggles, and any skin error.

## Actions

- Use: consumes one-click items from bags (open caches, collect decor).
- Vendor: sells at a merchant, keeps buyback intact.
- Disenchant: on an enchanter; otherwise prepares mail to the
  enchanter named in settings.
- Sell: hands off to TSM/Auctionator when present; otherwise flags
  for manual listing.
- Trash: destroy with confirmation.

## Settings

Settings are account-wide, edited in the addon panel (`/ww config`)
or on the slash line.

- Price source: Auto / Vendor / Auctionator / TSM / Oribos Exchange.
- Warbank source: Auto / Syndicator / Blizzard API.
- TSM price key (default DBMarket), enchanter name, auction threshold.
- Never/always-sell lists via /ww never|always <item>.
- Auto-open at vendors / the auction house (both off by default).
  The window docks beside the merchant or AH frame when it auto-opens.
  Vendor auto-open pre-selects the vendor filter.

## Build notes

- Target the current retail interface version.
- OptionalDeps on Baganator, Syndicator, TradeSkillMaster,
  Auctionator, EllesmereUI, OribosExchange. Never hard-require them.
- SavedVariables are account-wide.
- MIT license. Public repo under vocino.
- Looks follow theme.lua (see Looks); suites are never hard-required.

## Open questions

- Syndicator warbank shape needs in-game verification (no local install).
- TSM/Auctionator/Oribos calls need in-game verification (no local installs).
- Blizzard C_Bank path for warbank (Syndicator covers it meanwhile).
- CurseForge and Wago publishing: after v1 works, not before.
- Decor owned-count semantics need in-game verification (bag items
  vs storage counts).
- Toy rule needs in-game confirmation that GetToyInfo covers
  uncollected toys.
