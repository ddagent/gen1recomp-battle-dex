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
luajit mods/battle_dex/tests/battle_dex_test.lua   # 88 checks, no ROM needed
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
│                 │▣ SEL    ││
│                 └─────────┘│
│  [YOU]        your HUD     │
├──────────┬─────────────────┤
│          │ ▶FIGHT      PKMN│
│          │  ITEM       RUN │
└──────────┴─────────────────┘
```

The icon is the real POKéDEX from OAK's table — `SPRITE_POKEDEX`, read from
your own imported cache at draw time. Nothing is bundled, so the package
still ships no ROM-derived bytes; a cache without that sprite falls back to a
small drawn glyph rather than losing the badge.

The chrome is the engine's own `Font.drawBox`, so the border comes from
`Font.BORDER` — the table `Theme.lua` rebuilds from `field.theme.border`. A
theme mod restyles this badge along with every other box rather than leaving
it the one square frame in the game.

Placement and backing follow whatever is compositing the battle:

| Frame | Anchor | Backing | Scale |
| --- | --- | --- | --- |
| OG / WIDE | the battle surface's own edge | the box's own opaque interior | 1:1 |
| DRAMATIC_SHAPE arena | the canvas corner | `BattleHud.panel` — the arena's real frosted glass | `BADGE SIZE %` |

Inside the arena, `OverworldBattle.withoutBoxFill` strips every opaque white
fill so the diorama shows through the engine's boxes; the badge's interior is
stripped the same way and the glass goes in its place. That glass is not
imitated — it is `BattleHud.panel(rect, shot, true)`, the same call the arena
makes for its own HUDs and text box. It blurs the world behind the rect and
lifts it toward white, which is why no flat fill of ours ever matched it: a
flat fill throws the scene away instead of blurring it, and reads more opaque
at any alpha.

The arena's own HUD panels are frame-relative vertically (`shot.ly + y * s`)
because they belong to the battle's layout — the foe's panel has to sit level
with the foe. The badge does not belong to that layout; it is a hint about a
button, so it takes the canvas corner instead. Anchoring it to the frame left
`shot.ly` of dead screen above it (~36px on a 1080p handheld).

`BADGE CORNER` moves it to `BOTTOM LEFT` if you prefer. On the OG layout that
corner is genuinely empty — the menu box only covers x64–160 — while on WIDE
it shares space with "What will X do?". In the flat layouts `TOP RIGHT`
overlaps the top rows of the foe's 7×7 pic slot, which the box's interior
covers; in the voxel arena the foe is a model in the scene rather than a
slot, so nothing is obscured there.

`BADGE SIZE %` shrinks the badge without resampling it. The arena already
draws it at roughly 6.8× on a 1080p handheld, so 60% gives some of that
magnification back — every source pixel still covers about four screen
pixels and the sprite and font stay pixel-exact. The flat layouts ignore it,
because one GB pixel to one GB pixel leaves nothing to give back.

## Options

Set these in the in-game mod manager.

Every one is read at the moment it is used, so changes take effect the
instant you make them — no restart, and the size dials move the badge while
you turn them.

| Option | Type | Default |
| --- | --- | --- |
| `FOE DEX BUTTON` | SELECT / START / OFF | `SELECT` |
| `AUTO DEX ON NEW` | on / off | on |
| `DEX IN PKMN MENU` | on / off | on |
| `SHOW UNSEEN DATA` | on / off | on |
| `SHOW DEX BADGE` | on / off | on |
| `BADGE CORNER` | TOP RIGHT / BOTTOM LEFT | `TOP RIGHT` |
| `BADGE SIZE %` | 30–100, step 5 | `60` |
| `BADGE INSET` | 0–16, step 1 | `2` |

- **FOE DEX BUTTON** — the battle menu reads only the d-pad and A, so both
  SELECT and START are genuinely free there.
- **AUTO DEX ON NEW** — the first time you meet a species, its page opens
  itself once the intro text is done and you have control. See *Knowing what
  is new* below for why that is not simply a POKéDEX lookup.
- **DEX IN PKMN MENU** — the `DEX` row under `STATS`.
- **SHOW DEX BADGE** — the on-screen hint.
- **BADGE CORNER** — `TOP RIGHT` or `BOTTOM LEFT`.
- **BADGE SIZE %** — percent of the arena's own magnification. Only the
  voxel arena honours it: the flat layouts draw one GB pixel to one and have
  nothing to give back, so anything under 100 there would resample the art
  rather than shrink it.
- **BADGE INSET** — distance from the corner, in GB pixels.
- **SHOW UNSEEN DATA** — mirrors pokered's `StarterDex`
  `forceOwned`, so height/weight/description show for a mon you have not
  caught yet. Turn it off for a vanilla-strict run and unseen mons render
  the blank page the POKéDEX would. Neither setting writes the owned bit, so
  dex completion is unaffected.

## Knowing what is new

`AUTO DEX ON NEW` cannot ask the POKéDEX whether a species is new, because by
the time a mod may ask, the answer is always yes. `markSeen` runs inside
`BattleState.newWild` — the constructor — while `battle.started` is emitted
later from `enter()`, so the species is already flagged seen before any mod
hears about the battle. A naive check would be false every single time and
the feature would look broken rather than quiet.

So the mod keeps its own roll in `mod.save`, seeded from your dex at
`save.loaded` / `save.created`. That is the only honest moment: `Game:adoptSave`
has already pointed `mod.save` at the slot's `modData`, the event fires after
it, and no battle — and therefore no `markSeen` — has run yet.

Because the roll lives in the save's `modData`, it is **per save slot**. A
second playthrough starts fresh and auto-opens for everything again.

A meeting is recorded even when the toggle is off, so switching it on later
does not replay every species you have already fought.

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
