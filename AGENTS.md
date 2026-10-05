# AGENTS.md

## Code Map

- `main.lua`: boot, slash command (`/vw`, `/vocwarbank`), chat voice (`ns.say`)
- `config.lua`: settings defaults and repair, never/always-sell lists
- `providers.lua`: price/expansion data layer behind one contract
- `scanner.lua`: container-agnostic scan (warbank, bank, bags)
- `ranking.lua`: the verdict rules
- `theme.lua`: Baganator Dark / stock looks
- `ui.lua`: the triage window
- `mock/triage.html`: the HTML design mock the window follows (dev only, never packaged)
- `settings.lua`: native Settings panel (Settings > AddOns > VocWarbank)
- `tests/`: headless tests (`lua tests/run.lua` from the repo root)
- `SPEC.md`: the full spec
- `FAMILY.md`: conventions shared by every Voc addon
- `VERSIONING.md`: tag-driven semver releases (identical across the family)
- `.luacheckrc`: lint config declaring the addon's globals
- `.github`: `test.yml` (tests + lint) and `release.yml` (packager)

## API references

Code targets the build in `## Interface:` of the `.toc`. Verify every
WoW API fact against that build, in this order, and nothing else:

1. Blizzard's own API docs for the build: `/api` in the client, or the
   mirror at https://github.com/Gethe/wow-ui-source, branch `live`,
   folder `Interface/AddOns/Blizzard_APIDocumentationGenerated/`.
   Names, namespaces, arguments, returns, and events come from here.
2. Blizzard's UI source in the same mirror for templates, mixins, and
   `Blizzard_Deprecated*` (what is leaving, what replaces it).
3. The Lua 5.1 manual, https://www.lua.org/manual/5.1/. The client is
   Lua 5.1 in a sandbox; nothing from 5.2+ exists there.
4. https://warcraft.wiki.gg for prose only, after checking its patch
   note; a signature there is confirmed in source 1 before use.

Never Wowpedia (fandom), WoWWiki, forums, tutorials, or memory of an
older patch. A bare global that now lives in a `C_*` namespace is the
usual sign of stale information. `.luacheckrc` is the allowlist of
verified globals: lint fails on any other, and a name is added only
after confirming it in source 1 for the current build. Full rule and
a local-checkout recipe: `FAMILY.md`, Sources of truth.

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
