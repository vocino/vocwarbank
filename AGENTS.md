# AGENTS.md

## Code Map

- `main.lua`: boot, slash command (`/vw`, `/vocwarbank`), chat voice (`ns.say`)
- `config.lua`: settings defaults and repair, never/always-sell lists
- `providers.lua`: price/expansion data layer behind one contract
- `scanner.lua`: container-agnostic scan (warbank, bank, bags)
- `ranking.lua`: the verdict rules
- `theme.lua`: EllesmereUI / Baganator Dark / stock looks
- `ui.lua`: the triage window
- `settings.lua`: native Settings panel (Settings > AddOns > VocWarbank)
- `tests/`: headless tests (`lua tests/run.lua` from the repo root)
- `SPEC.md`: the full spec
- `FAMILY.md`: conventions shared by every Voc addon
- `VERSIONING.md`: tag-driven semver releases (identical across the family)
- `.luacheckrc`: lint config declaring the addon's globals
- `.github`: `test.yml` (tests + lint) and `release.yml` (packager)

## Family

VocWarbank is one of the Voc addons. Naming, slash grammar, chat
voice, settings, layout, and docs follow `FAMILY.md`; that file is
identical in every sibling repo, so edit it everywhere or not at all.

## Namespace

Every global carries the `VocWarbank` prefix: frames
(`VocWarbankWindow`), SavedVariables (`VocWarbankDB`), slash
(`SLASH_VOCWARBANK*`), popups (`VOCWARBANK_*`), Settings variables
(`VocWarbank_*`), chat (`VocWarbank:` via `ns.say`). Never introduce
an unprefixed global; `luacheck .` enforces it.

## Tests

Run `lua tests/run.lua` (Lua 5.1 or 5.4) and `luacheck .` from the
repo root after behavior changes. Both run in CI on every push.
Tests are excluded from the packaged addon (see `.pkgmeta`).

## Releases

Follow `VERSIONING.md` when cutting a release; never retag.

## Live testing

Point `_retail_\Interface\AddOns\VocWarbank` at this repo with a
directory junction so edits go live on `/reload`. The client only
loads `.toc`-listed files; dev files (`tests/`, `.git`, docs) in the
folder are ignored.

Recreate: `New-Item -ItemType Junction -Path '<AddOns>\VocWarbank' -Target <path-to-this-repo>`
Remove: `Remove-Item '<AddOns>\VocWarbank'` (link only, never `-Recurse`)
