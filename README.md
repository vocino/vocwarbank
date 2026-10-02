# warbank audit

problem
every expansion leaves junk in your warbank: old reagents, dead quest
items, gear with no purpose. you either eyeball hundreds of slots or
never clean at all.

how to install
copy the folder into `interface/addons` and rename it to `WarbankAudit`.
curseforge and wago packages come later.

how to use
```
/ww
```
pick a scope (warbank, bank, bags), look at the ranked list, drag the
line to where your comfort level is, review the dry-run summary, hit
go. everything below the line gets vendored, disenchanted, mailed, or
trashed.

what it does
- scans your warbank, bank, or bags
- ranks every item by usefulness: uncollected appearances and
  equipment sets stay, current-expansion mats stay, everything else
  gets a verdict (sell, disenchant, vendor, trash, destroy)
- never auto-sells or auto-destroys. you confirm every action.
- plugs into baganator, tsm, or auctionator for better data when you
  have them. works fine without them.

what's inside
- `main.lua`: boot, slash command
- `config.lua`: settings, never-sell lists
- `providers.lua`: data layer. one contract, builtin fallback plus
  optional baganator/tsm/auctionator providers
- `scanner.lua`: container-agnostic item scan
- `ranking.lua`: the verdict rules
- `ui.lua`: the triage window
- `SPEC.md`: the full spec
