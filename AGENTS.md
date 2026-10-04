# AGENTS.md

## Code Map

- `main.lua`: boot, slash command (`/ww`, `/vocwarbank`)
- `config.lua`: settings, never/always-sell lists
- `providers.lua`: price/expansion data layer behind one contract
- `scanner.lua`: container-agnostic scan (warbank, bank, bags)
- `ranking.lua`: the verdict rules
- `theme.lua`: EllesmereUI / Baganator Dark / stock looks
- `ui.lua`: the triage window
- `settings.lua`: options panel
- `tests/`: headless tests (`lua tests/run.lua` from the repo root)
- `SPEC.md`: the full spec
- `.github`: project configuration

## Namespace

Every global carries the `VocWarbank` prefix: frames
(`VocWarbankWindow`), SavedVariables (`VocWarbankDB`), slash
(`SLASH_VOCWARBANK`), popups (`VOCWARBANK_*`), chat
(`VocWarbank:`). Never introduce an unprefixed global.

## Tests

Run `lua tests/run.lua` from the repo root after behavior changes.
Tests are excluded from the packaged addon (see `.pkgmeta`).

## Releases

- Follow `VERSIONING.md` when cutting a release; never retag.
