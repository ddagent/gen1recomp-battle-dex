# Battle Dex

Open a POKéDEX entry from inside a battle — press SELECT to read the
opponent, or pick DEX in the PKMN menu to read one of your own.

Persona: **the quality-of-life author** — no data is changed, no battle
outcome moves, and every addition is a door into a page the engine already
draws.

## Updating

`manifest.json` carries `"github": "ddagent/gen1recomp-battle-dex"`, so the
launcher's MODS tab checks this repo's releases and offers **Update** when a
newer one appears. Update checks are cached for 6 hours; the tab's refresh
forces a re-check.

A release is picked up when its tag is `vX.Y.Z` and it carries a `.zip`
asset — `battle_dex-<version>.zip` is preferred by name. Cutting one:

```sh
python3 tools/modkit.py pack battle_dex -o battle_dex-<version>.zip
gh release create v<version> --title <version> battle_dex-<version>.zip
```

## Test it

```sh
luajit mods/battle_dex/tests/battle_dex_test.lua   # 43 checks, no ROM needed
python3 tools/modkit.py validate battle_dex
python3 tools/modkit.py lint battle_dex
```

## What it adds

| Where | Input | Shows |
| --- | --- | --- |
| FIGHT/PKMN/ITEM/RUN prompt | SELECT (rebindable to START, or off) | the opponent's dex entry |
| PKMN → a mon | the new `DEX` row under `STATS` | that party mon's dex entry |

Both doors push the engine's own `DexEntryMenu`. The battle underneath is
paused, not advanced — only the top state updates — and `B` returns you to
exactly the prompt you left.

## The badge

A small plate appears at the battle prompt showing a POKéDEX device and the
button's name:

```
┌────────────────────────────┐
│  FOE HUD        ┌─────────┐│
│                 │▣ SELECT ││
│                 └─────────┘│
│  [YOU]        your HUD     │
├──────────┬─────────────────┤
│          │ ▶FIGHT      PKMN│
│          │  ITEM       RUN │
└──────────┴─────────────────┘
```

It is drawn through `battle.overlay` in battle-surface pixels, so it scales
with the game and holds its corner at any zoom or BATTLE SIZE setting. The
icon is a 10×10 bitmap authored in `main.lua` — the mod ships no art files
and nothing derived from a ROM.

`TOP RIGHT` (the default) overlaps the top ~14px of the foe's sprite slot in
both layouts, which is why the badge carries its own plate. Most Gen 1 front
sprites leave those rows empty, but a tall mon will be clipped there — switch
`BADGE CORNER` to `BOTTOM LEFT` if that bothers you. On the OG layout that
corner is genuinely empty (the menu box only covers x64–160); on WIDE it
shares space with "What will X do?".

## Options

Set these in the in-game mod manager.

- **FOE DEX BUTTON** — `SELECT` (default), `START`, or `OFF`. The battle menu
  reads only the d-pad and A, so both buttons are genuinely free there.
- **DEX IN PKMN MENU** — the `DEX` row, on by default.
- **SHOW DEX BADGE** — the on-screen hint, on by default.
- **BADGE CORNER** — `TOP RIGHT` (default) or `BOTTOM LEFT`.
- **SHOW UNSEEN DATA** — on by default. Mirrors pokered's `StarterDex`
  `forceOwned`, so height/weight/description show for a mon you have not
  caught yet. Turn it off for a vanilla-strict run and unseen mons render
  the blank page the POKéDEX would. Neither setting writes the owned bit, so
  dex completion is unaffected.

## What it deliberately will not do

- **Link battles.** Pushing a screen pauses your side only; the peer walks
  the turn without you. That is a desync, not a pause.
- **The GHOST encounter.** Naming the unidentified GHOST is what the SILPH
  SCOPE is for.
- **Mid-turn.** The hotkey only answers at the battle prompt, never while a
  move is animating.

## Known behaviour

The page opens one fixed step (~16 ms) after the press, because `input.step`
runs before `Input:step` promotes queued edges. Each press is still observed
exactly once.

## Layout

- `manifest.json` — identity, version range, load order
- `main.lua` — the entry chunk; receives the `mod` object
- `mod.card` — sharing metadata for the manager's detail pane
- `tests/` — the ROM-free suite; excluded from the package by `.modkitignore`
