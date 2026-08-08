# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.7.6

### Fixed

- **The entry page opens again, whether or not you own it.** 1.7.5 stopped
  forcing it, which was a step too far: pointing the POKeDEX at something
  and being told what it is *is* the POKeDEX, and it is what the FUCHSIA
  placards do. Browsing the dex from the menu still hides an unowned
  species -- that is the engine's rule and it stays.
- `SHOW UNSEEN DATA` now decides only what sits **behind** the entry page:
  the stats, the catch odds, the locations and the movelist. Off (the
  default), those follow real ownership, so a glimpse in battle stays a
  glimpse.
## 1.7.5

### Changed

- **`SHOW UNSEEN DATA` now defaults OFF.** On, it forced the entry open as
  though the species were caught, which overrode dex_pages' own
  `OWNED DATA ONLY` gate -- so a POKeMON you had merely glimpsed in battle
  handed over its stats, its locations and its whole movelist. Seen gets you
  the picture; owned gets you the data, which is both what the engine's own
  dex does and how it works in the show. Turn it back on if you prefer the
  old behaviour.
## 1.7.4

### Fixed

- **A dex page opened before the player owned a POKeDEX.** The mod only
  asked "have I met this species", never "is there a dex to open" -- so the
  rival's EEVEE in OAK's lab, the very first battle in the game, opened a
  full entry hours before OAK hands one over. Both doors and the badge now
  check `EVENT_GOT_POKEDEX`.

## 1.7.3

### Changed

- Rewrote the description shown in the mod manager. It never mentioned
  `AUTO DEX ON NEW` -- the entry opening itself the first time you meet a
  species -- which had been in since 1.7.0.

## 1.7.2

### Fixed

- Against a trainer, only their lead was auto-opened. `battle.started` fires
  once per battle, so every mon they sent out afterwards was never checked
  — a team of six unseen mons produced one page. The mod now also listens to
  `battle.battler_switched`, which covers both a mid-fight switch and the
  send-out after a faint, and ignores your own side.

## 1.7.1

### Fixed

- A species you had already seen could auto-open once, if it happened to be
  the first battle after installing. The roll was seeded at that first
  battle, by which point `markSeen` had already written the dex, so it had
  to subtract the current species back out — and it could not tell "markSeen
  just added this" from "this was already known".
- Seeding now happens at `save.loaded` / `save.created`, which is the only
  honest moment: `Game:adoptSave` has already pointed `mod.save` at the
  slot's `modData` (Game.lua:1099) and the event fires after (:1128), while
  no battle has run. Nothing to subtract, nothing to guess. The battle-time
  path survives as a warned fallback.

## 1.7.0

### Added

- `AUTO DEX ON NEW` (on by default): the first time you meet a species, its
  page opens itself once the intro text is done and you have control. It
  rides the same guards as the hotkey, so it never lands over the appeared
  text, in a link battle, or against the GHOST.
- `BADGE SIZE %` (30-100, default 60) and `BADGE INSET` (0-16, default 2) —
  both read every frame, so the badge moves as you turn the dial.

### Note

"First time" is tracked by this mod in its own save bucket, not read off the
POKeDEX. `markSeen` runs inside `BattleState.newWild`, before `enter()` emits
`battle.started`, so by the time any mod can look at a wild battle the
species is already flagged seen -- a naive check would be false every time.
The roll is seeded from your dex on the first battle after install, minus
that battle's own species.

## 1.6.0

### Fixed

- `TOP RIGHT` sat about 36px lower than it needed to. Its right edge was
  pinned to the canvas (`shot.pw`) but its top to the Game Boy frame
  (`shot.ly`), so the letterbox offset showed as dead space above the badge —
  while `BOTTOM LEFT`, two lines away, was already using `shot.ph`. Every
  edge is the canvas's now.

## 1.5.0

### Changed

- The badge is smaller. The label is abbreviated (`SELECT` -> `SEL`), which
  takes the box from 11 tiles to 8, and inside the arena the badge is drawn
  at 0.6 of the arena's own magnification.
- Nothing is resampled to achieve that. The arena already draws the badge at
  roughly 6.8x on a 1080p handheld, so 0.6 simply gives some of that back;
  every source pixel still covers about four screen pixels and the sprite and
  font stay pixel-exact. The flat layouts get no multiplier because they draw
  one GB pixel to one GB pixel and have none to give back — anything under
  1.0 there would destroy the art. They get the shorter label alone.

## 1.4.0

### Fixed

- The badge read more opaque than the game's other panels. It was painting a
  flat white wash; DRAMATIC_SHAPE's panels draw a *blurred copy of the world
  behind the rect* at `FROST` and only then a white tint at `TINT`, so they
  keep the scene's own colour instead of covering it. No flat fill can
  imitate that at any alpha.
- The badge now calls `BattleHud.panel(rect, shot, true)` — the documented
  world-pixel form, the same call `OverworldBattle` uses for both HUDs and
  the text box — so its glass is literally the same glass. The flat wash
  remains only for when that panel declines (frost buffer not built yet) or
  the voxel mod is not installed.

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
