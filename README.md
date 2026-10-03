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

Pick a scope (warbank, bank, bags), look at the ranked list, drag
the line to where your comfort level is, review the dry-run summary,
hit go. Uncollected appearances and equipment sets stay,
current-expansion mats stay, everything else gets a verdict: sell,
disenchant, vendor, trash, or destroy.

## How it works

Two layers: providers fetch the data behind one contract, and the UI
never talks to third-party addons directly. The builtin provider
always works; Baganator, TSM, or Auctionator plug in for better
expansion and price data when you have them.

## What's inside

- `main.lua`: boot, slash command
- `config.lua`: settings, never-sell lists
- `providers.lua`: data layer behind one contract
- `scanner.lua`: container-agnostic item scan
- `ranking.lua`: the verdict rules
- `ui.lua`: the triage window
- `SPEC.md`: the full spec

## License

MIT
