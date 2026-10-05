# VocWarbank

Every expansion leaves junk in your warbank: old reagents, dead
quest items, gear with no purpose. VocWarbank scans your warband
bank, bank, or bags, ranks everything by usefulness, and lets you
draw the line. Everything below it gets vendored, disenchanted,
mailed, or trashed. You confirm every action; it never sells or
destroys anything on its own.

## Install

Download the latest zip from [GitHub
Releases](https://github.com/vocino/vocwarbank/releases) (also on
CurseForge and Wago), copy the folder into `Interface/AddOns`, and
make sure it is named `VocWarbank` (the folder name must match the
`.toc` file).

## Use

Open the window, pick a scope, and browse the icon grid grouped by
category or expansion. Filter by verdict, click to queue what goes,
review the dry-run summary, hit go. Uncollected appearances and
equipment sets stay, current-expansion mats stay, everything else
gets a verdict: use, sell, disenchant, vendor, trash, or destroy.

```
/vw                                 open or close the window
/vw scope <bags|bank|warbank|all>   what to scan
/vw source <auto|vendor|auctionator|tsm|oribos>   price source
/vw inventory <auto|blizzard|syndicator>   warbank source
/vw threshold <gold>                auction threshold for BoE gear
/vw enchanter <name>                who gets disenchantables by mail
/vw tsmkey <key>                    TSM price key (default DBMarket)
/vw never|unnever <item>            pin or unpin a never-sell item
/vw always|unalways <item>          pin or unpin an always-sell item
/vw auto <vendor|auction> <on|off>  auto-open at vendors or the AH
/vw theme                           report the active look
/vw config                          open Settings > AddOns > VocWarbank
/vw help                            this list (/vocwarbank works too)
```

## Config

Settings > AddOns > VocWarbank, or `/vw config`:

- Price source (default Auto: Auctionator, TSM, Oribos Exchange, then vendor prices)
- Warbank source (default Auto: Syndicator when present, else the Blizzard API)
- Scope (default bags)
- Auction threshold (default 10g; any value via `/vw threshold`)
- Open automatically at vendors / at the auction house (default off)

Enchanter name, TSM price key, and the never/always-sell lists are
set on the slash line. Every change applies to an open window at once.

## How it works

Two layers: providers fetch the data behind one contract, and the UI
never talks to third-party addons directly. Prices cascade from
Auctionator, TSM, and Oribos Exchange down to vendor prices;
Syndicator (Baganator) feeds warbank contents when present. The
window wears stock Blizzard chrome, or matches
Baganator's Dark skin when it is running. `SPEC.md` has
the ranking rules and the full design.

## What's inside

- `main.lua`: boot, slash command, chat voice
- `config.lua`: settings defaults and repair, never/always-sell lists
- `providers.lua`: data layer behind one contract
- `scanner.lua`: container-agnostic item scan
- `ranking.lua`: the verdict rules
- `ui.lua`: the triage window
- `theme.lua`: matches Baganator Dark when present
- `settings.lua`: native Settings panel
- `SPEC.md`: the full spec
- `tests/`: headless tests with stubbed WoW APIs

## Tests

```
lua tests/run.lua
luacheck .
```

## License

MIT

---

Part of the Voc family: tiny addons that do one job.
Siblings: [VocWarbank](https://github.com/vocino/vocwarbank) ·
[VocGear](https://github.com/vocino/vocgear)
