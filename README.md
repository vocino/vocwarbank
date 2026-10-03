# Warbank Audit

Every expansion leaves junk in your warbank: old reagents, dead
quest items, gear with no purpose. Warbank Audit scans your warband
bank, bank, or bags, ranks everything by usefulness, and lets you
draw the line — everything below it gets vendored, disenchanted,
mailed, or trashed. You confirm every action; it never sells or
destroys anything on its own.

## Installation

Copy the folder into `Interface/AddOns` and rename it to
`WarbankAudit` (the folder name must match the `.toc` file).
CurseForge and Wago packages are coming later.

## Usage

```
/ww
```

Pick a scope (warbank, bank, bags) and browse the icon grid, grouped
by category or expansion. Filter by verdict, click to queue what
goes, review the dry-run summary, hit go. Uncollected appearances
and equipment sets stay, current-expansion mats stay, everything
else gets a verdict: use, sell, disenchant, vendor, trash, or destroy.

Tune it in the settings panel (`/ww config`) or on the slash line:
`/ww source <auto|vendor|auctionator|tsm|oribos>`, `/ww inventory
<auto|blizzard|syndicator>`, `/ww scope <warbank|bank|bags|all>`,
`/ww threshold <gold>`, `/ww enchanter <name>`, `/ww never <item>`,
`/ww auto <vendor|auction> <on|off>`.

## How it works

Two layers: providers fetch the data behind one contract, and the UI
never talks to third-party addons directly. Prices cascade from
Auctionator, TSM, and Oribos Exchange down to vendor prices;
Syndicator (Baganator) feeds warbank contents when present.

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

## License

MIT
