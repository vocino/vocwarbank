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

1. **Builtin** (always available). Reads the expansion key from
   the item's own expansionID. Falls back to vendor sell price for value.
2. **Baganator/Syndicator** (optional). Expansion classification when
   loaded. Baganator exposes a documented public `Baganator.API`
   (other addons integrate with it today); Syndicator is the data
   library underneath it. Exact call to verify at build time.
3. **TSM** (optional). Market value via its public API. Exact call to
   verify at build time.
4. **Auctionator** (optional). Market value via its public API. Exact
   call to verify at build time.

Every external call is wrapped so a broken provider falls back to
Builtin. The user picks a source in settings (Auto / Builtin /
Baganator); the window header shows which source is active.

## Ranking

Each item is checked against these rules in order. First match sets
the verdict.

1. Appearance not collected -> KEEP
2. In a saved equipment set -> KEEP
3. Current-expansion consumable, reagent, or trade good -> KEEP
4. On the never-sell list -> KEEP
5. On the always-sell list -> SELL (valued) or VENDOR
6. Bind-on-equip gear, market value above threshold
   -> SELL (auction house)
7. Old-expansion uncommon or rare gear -> DISENCHANT (epics keep
   buyback through VENDOR instead)
8. Quest item -> KEEP (log check is future work)
9. Has a vendor price -> VENDOR
10. Anything else -> KEEP ("needs review"; never destroy by default)

## The window

- Header: item count, slots to free, estimated gold, active data
  source.
- Body: one scroll list grouped by verdict (Keep / Sell /
  Disenchant / Vendor / Trash). Each row shows icon, name, count,
  value, and a reason tag like "uncollected look" or "old reagent".
- The line: a draggable divider. Everything below it is queued.
- Footer: dry-run summary first ("142 items, 38 slots, ~12,400g"),
  then per-group action buttons.

## Actions

- Vendor: sells at a merchant, keeps buyback intact.
- Disenchant: on an enchanter; otherwise prepares mail to the
  enchanter named in settings.
- Sell: hands off to TSM/Auctionator when present; otherwise flags
  for manual listing.
- Trash: destroy with confirmation.

## Settings

- Data source: Auto / Builtin / Baganator.
- Enchanter character name.
- Auction-house value threshold (Sell vs Vendor).
- Never-sell and always-sell lists, account-wide.

## Build notes

- Target the current retail interface version.
- OptionalDeps on Baganator, Syndicator, TradeSkillMaster,
  Auctionator. Never hard-require them.
- SavedVariables are account-wide.
- MIT license. Public repo under vocino.
- EllesmereUI skin via RegisterSkin when present (optional).

## Open questions

- Exact Baganator/Syndicator expansion call. Verify at build.
- Exact TSM/Auctionator price calls. Verify at build.
- Warband bank scan API details. Verify at build.
- CurseForge and Wago publishing: after v1 works, not before.
