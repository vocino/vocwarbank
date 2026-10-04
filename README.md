# VocWarbank

Every expansion leaves junk in your warbank: old reagents, dead
quest items, gear with no purpose. VocWarbank scans your warband
bank, bank, or bags, ranks everything by usefulness, and lets you
draw the line — everything below it gets vendored, disenchanted,
mailed, or trashed. You confirm every action; it never sells or
destroys anything on its own.

## Installation

Download the latest zip from [GitHub
Releases](https://github.com/vocino/vocwarbank/releases), copy
the folder into `Interface/AddOns` and rename it to `VocWarbank`
(the folder name must match the `.toc` file).

## Usage

```
/vw
```

Pick a scope (warbank, bank, bags) and browse the icon grid, grouped
by category or expansion. Filter by verdict, click to queue what
goes, review the dry-run summary, hit go. Uncollected appearances
and equipment sets stay, current-expansion mats stay, everything
else gets a verdict: use, sell, disenchant, vendor, trash, or destroy.

Tune it in the settings panel (`/vw config`) or on the slash line:
`/vw source <auto|vendor|auctionator|tsm|oribos>`, `/vw inventory
<auto|blizzard|syndicator>`, `/vw scope <warbank|bank|bags|all>`,
`/vw threshold <gold>`, `/vw enchanter <name>`, `/vw never <item>`,
`/vw auto <vendor|auction> <on|off>`.

## How it works

Two layers: providers fetch the data behind one contract, and the UI
never talks to third-party addons directly. Prices cascade from
Auctionator, TSM, and Oribos Exchange down to vendor prices;
Syndicator (Baganator) feeds warbank contents when present.

## Tests

Headless tests run the ranking rules and the scanner against
stubbed WoW APIs. No game client needed:

    lua tests/run.lua

## What's inside

- `main.lua`: boot, slash command
- `config.lua`: settings, never-sell lists
- `providers.lua`: data layer behind one contract
- `scanner.lua`: container-agnostic item scan
- `ranking.lua`: the verdict rules
- `ui.lua`: the triage window
- `theme.lua`: matches EllesmereUI or Baganator Dark when present
- `settings.lua`: options panel
- `SPEC.md`: the full spec
- `tests/`: headless tests with stubbed WoW APIs

## License

MIT
