# VocWarbank — Spec

A tiny WoW addon. Audit your stuff anywhere, see everything ranked by
usefulness, draw a line, clean house.

## Name (decided 2026-10-02)

**VocWarbank.** "Warbank" is the player term for warband bank;
short, distinctive, no collision risk, "bank" in the name for
CurseForge/Wago search. Listing description carries the keywords:
"audit and clean your warband bank, bank, and bags."

`Voc` is the author namespace: every global carries the
`VocWarbank` prefix — frames, SavedVariables (`VocWarbankDB`),
slash command (`SLASH_VOCWARBANK`), popups (`VOCWARBANK_*`),
chat (`VocWarbank:`). Never introduce an unprefixed global.
v0.1.x shipped under the old "Warbank Audit" name, so the rename
resets saved settings once.

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
- `/vw` slash command. No minimap button.

## Architecture

Two layers. The UI never talks to third-party addons directly.

```
VocWarbank/
  main.lua      boot, slash command
  config.lua    settings, never/always-sell lists
  providers.lua data layer behind one contract (Data)
  scanner.lua   container-agnostic item scan
  ranking.lua   verdict rules (Core)
  ui.lua        the triage window (UI)
  theme.lua     Baganator Dark / stock looks
  settings.lua  options panel
  tests/        headless tests (lua tests/run.lua)
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
Warbank contents come from Syndicator (Baganator's data) when present;
otherwise the Blizzard account-bank bags (empty unless the bank is open).
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
3. Current-expansion consumable, reagent, trade good, or (non-BoE)
   gear -> KEEP (priced BoEs list at rule 10 instead)
4. On the never-sell list -> KEEP
5. On the always-sell list -> SELL (valued) or VENDOR
6. Currency token (Mark of Honor and confirmed kin) -> KEEP
7. Profession tool for a profession you have -> KEEP
8. Openable container -> USE
9. Housing decor -> USE (first copy unlocks, extras stock the
   chest); uncollected pet, mount, or toy -> USE
10. Bind-on-equip gear, market value above threshold
   -> SELL (auction house)
11. Old-expansion uncommon or rare gear -> DISENCHANT (epics keep
   buyback through VENDOR instead)
12. Quest item for a completed quest -> DESTROY (dead quest item,
   quest-log lookup); other quest items -> KEEP
13. Has a vendor price -> VENDOR
14. Anything else -> KEEP ("needs review"; never destroy by default)

## The window

Two columns, 660x640 (the design mock is `mock/triage.html`; the
Lua follows it). Verdicts assess, buttons operate: the flow reads
narrow -> select -> act, left to right.

- Sidebar (left, tinted): search; the verdict facet list ("All" plus
  every verdict the scan produced, each with its count, the active row
  highlighted); Group by (Category / Expansion, the active one held
  pressed); Selection (Select shown, Clear); Actions (a stack of
  full-width buttons: Use, Sell, Disenchant, Vendor, Destroy, each
  with its queued count); the active data source pinned at the bottom.
- Content (right): stats line (item count, slots to free, estimated
  gold); sort cluster (direction arrow plus a Sort dropdown: Bag
  order / Quality / Value / Name); the Baganator-style icon grid
  grouped by category or expansion, sub-split on the other axis
  (Armor: The War Within). Never-sell and always-sell lists pin to
  their own leading sections. Icons show stack count, item level,
  quality border, and a verdict dot; hover for name, value, and
  reason tag. The dry-run footer ("Selected: 142 items, 38 slots,
  ~12,400g", then the per-verdict split) sits under the grid.
- Selection: click icons or shift-click group headers to queue them.
  The Actions label reads "Actions · N selected" live; with nothing
  selected the group dims behind a hint.
- The grid live-updates on inventory changes, preserving the queue.
- Search dims non-matches in place; headers show matches/total while
  a search is active ("Armor (2/3)"), and collapsed headers holding
  matches pulse. Headers collapse with a click; collapse, sort mode,
  and direction persist.
- The merchant handoff: with vendor items queued, opening any
  merchant pops a small dialog beside the merchant frame listing the
  queued rows with one Sell button (whole stacks sell) and Not now
  (closes, keeps the queue). `/vw queue` lists the queue, `/vw queue
  clear [action]` drops it.

## Looks

One window, two looks, picked live by theme.lua:

- Baganator loaded and running its Dark skin: a faithful
  replication of Skins/Dark.lua — same backdrop assets
  (dark-backgroundfile/dark-edgefile, edge 9 window / 6 buttons),
  same fill (0.05 at alpha 0.7) and border (0.35), same button
  hover/press/disabled behavior, category headers in
  GameFontNormalMed2, icons cropped with dark-icon-border in
  quality colors.
- Otherwise stock Blizzard chrome, which is also what
  Baganator's own Blizzard skin looks like.

Quality and verdict colors stay ours in every look — they are
data, not chrome. Looks re-resolve on every scan. A failed look
falls back to stock, says so once in chat, and retries on the
next scan; `/vw theme` reports the live look and any skin error.

## Actions

- Use: consumes one-click items from bags (open caches, collect decor).
- Vendor: queue from the window, sell at the merchant. The button
  toggles the selected vendor-verdict items in and out of the
  persisted queue (counts merge by itemID); queued icons carry a
  gold ring. Opening a merchant with a queued list pops the handoff
  dialog beside the merchant frame: the queued rows (missing/stowed
  dimmed with their reasons) and one Sell button for the lot, whole
  stacks selling, buyback intact.
- Disenchant adapts to who is at the keyboard. On an enchanter the
  button reads "Disenchant" and casts in person, one item per click,
  through a secure macro button (`/cast Disenchant` + `/use bag
  slot`, the path Blizzard's own macros take; never in combat).
  Otherwise it reads "Mail for DE": one-click mail to the enchanter
  named in settings (at a mailbox, with confirmation, 12 items per
  mail), disabled until an enchanter is set. Whatever can go neither
  way is listed under the stack ("2 can't go: 1 soulbound, 1 stowed"):
  soulbound items cannot be mailed, and bank or warbank items cannot
  be targeted from the bag path.
- Sell: hands off to TSM/Auctionator when present; otherwise flags
  for manual listing.
- Destroy: with confirmation. Dead quest items rank here; there is no
  separate "trash" verdict.

## Settings

Settings are account-wide. The panel is a native Blizzard Settings
category (Settings > AddOns > VocWarbank, or `/vw config`), the same
shape as every Voc addon (see FAMILY.md); every option also has a
slash form, and both apply live to an open window.

Panel (dropdowns and checkboxes bound to the live SavedVariables):

- Price source: Auto / Auctionator / TSM / Oribos Exchange / Vendor.
- Warbank source: Auto / Syndicator / Blizzard API.
- Scope: Bags / Character bank / Warband bank / All three.
- Auction threshold: gold presets (1 to 5000); a slash-set value that
  is not a preset shows as "(custom)".
- Auto-open at vendors / the auction house (both off by default).
  The window docks beside the merchant or AH frame when it auto-opens.
  Vendor auto-open pre-selects the vendor filter.

Slash line only (free text, no native control): enchanter name
(`/vw enchanter`), TSM price key (`/vw tsmkey`, default DBMarket),
never/always-sell lists (`/vw never|always|unnever|unalways <item>`).
The panel ends with a pointer to `/vw help`.

## Slash

`/vw` and `/vocwarbank`. The bare command opens or closes the window;
`/vw help` lists every subcommand; anything unrecognized prints help
and never acts. Chat lines carry the family's colored `VocWarbank:`
prefix via `ns.say`.

## Build notes

- Target the current retail interface version.
- OptionalDeps on Baganator, Syndicator, TradeSkillMaster,
  Auctionator, OribosExchange. Never hard-require them.
- SavedVariables are account-wide.
- MIT license. Public repo under vocino.
- Looks follow theme.lua (see Looks); suites are never hard-required.
- Conventions shared with the other Voc addons live in FAMILY.md.
- `lua tests/run.lua` and `luacheck .` run in CI on every push.

## Open questions

- Syndicator warbank shape needs in-game verification (no local install).
- TSM/Auctionator/Oribos calls need in-game verification (no local installs).
- Confirm CurseForge/Wago received the v0.1.x packages
  (GitHub Releases did); the next tag ships the VocWarbank rename.
- Toy rule needs in-game confirmation that GetToyInfo covers
  uncollected toys.
