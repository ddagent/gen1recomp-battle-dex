# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.3.0

### Changed

- The badge is drawn with the engine's own `Font.drawBox` instead of a
  hand-rolled rectangle, so its border comes from `Font.BORDER` — the table
  `src/ui/Theme.lua` rebuilds from `field.theme.border`. A theme mod now
  restyles this badge along with every other box in the game.
- The arena's glass is derived from DRAMATIC_SHAPE's own `BattleHud.FROST`
  and `BattleHud.TINT`, read through its public `exports.lib` at draw time,
  rather than a constant picked by eye. Falls back to 0.67 when that mod is
  absent.
- Inside the arena the box's opaque white interior is stripped exactly the
  way `OverworldBattle.withoutBoxFill` strips every other box's, with the
  glass laid in its place.

### Note

Boxes are tile-aligned, so the badge is now 88x32 rather than 70x20.

## 1.2.0

### Changed

- The badge icon is now the real POKeDEX overworld sprite — `SPRITE_POKEDEX`,
  the one on OAK's table — read from the player's own imported cache at draw
  time. Nothing is bundled; a cache without it falls back to the drawn glyph.
- The badge follows the arena instead of the Game Boy frame. Under
  DRAMATIC_SHAPE it pins to the true screen edge like the engine's own HUDs
  do, scaled by the arena's scale and drawn into its canvas.
- No opaque plate inside the arena, matching `OverworldBattle.withoutBoxFill`,
  which drops every white fill so the diorama shows through. Outside the
  arena the plate is unchanged.

## 1.1.0

### Added

- An on-screen badge at the battle prompt: a 10x10 hand-drawn POKéDEX device
  and the button's name, drawn through `battle.overlay`.
- `SHOW DEX BADGE` and `BADGE CORNER` (TOP RIGHT / BOTTOM LEFT) options.

### Changed

- The badge tracks `FOE DEX BUTTON`: it reads `START` when the hotkey does,
  and disappears entirely when the hotkey is `OFF`.

## 1.0.0

### Added

- SELECT at the FIGHT/PKMN/ITEM/RUN prompt opens the opponent's dex entry.
- A `DEX` row under `STATS` in the in-battle PKMN submenu, for your own party.
- `FOE DEX BUTTON`, `DEX IN PKMN MENU` and `SHOW UNSEEN DATA` mod options.
- `foeSpecies(game)` export, so another mod can reuse the guard set.
