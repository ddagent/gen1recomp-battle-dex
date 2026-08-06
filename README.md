# Battle Dex

> This mod was coded by AI.

Read a POKéDEX entry without leaving a battle.

At the FIGHT/PKMN/ITEM/RUN prompt, press **SELECT** to open the opponent's
entry. Press **B** to close it and you are back at the prompt, same turn,
nothing lost.

For your own party, choose **PKMN**, pick a mon, and take the new **DEX** row
under STATS.

And the first time you ever meet a species, its entry opens on its own once
the intro text is done — so you never miss the one Pokémon you had not seen
before.

Try it: walk into any grass, wait for the prompt, press SELECT.

## What it does

- **SELECT at the battle prompt** — the opponent's POKéDEX entry.
- **PKMN → a mon → DEX** — that party mon's entry.
- **A new species** — its entry opens automatically, once per species.
- **A small badge** at the prompt shows the button, so you do not have to
  remember it.

Height, weight and the description show even for a Pokémon you have not
caught yet, which is the point of looking mid-battle. Opening an entry never
marks anything as seen or caught, so your dex completion is unaffected.

If you also run a mod that improves the POKéDEX page itself, you get that
page — this mod decides *when* you can reach one, not what it looks like.

## Options

Set these in the in-game mod manager. Changes apply straight away.

| Option | | Default |
| --- | --- | --- |
| `FOE DEX BUTTON` | SELECT / START / OFF | SELECT |
| `AUTO DEX ON NEW` | open a species' entry the first time you meet it | on |
| `DEX IN PKMN MENU` | the DEX row | on |
| `SHOW UNSEEN DATA` | height/weight/text for a mon you have not caught | on |
| `SHOW DEX BADGE` | the on-screen hint | on |
| `BADGE CORNER` | TOP RIGHT / BOTTOM LEFT | TOP RIGHT |
| `BADGE SIZE %` | how big the badge is | 60 |
| `BADGE INSET` | how far from the corner | 2 |

The size dials move the badge while you turn them, so you can see what you
are choosing.

## Notes

- It does nothing in **link battles** — pausing your side only would desync
  your partner.
- It does nothing against the **GHOST** in Lavender Tower. Identifying that
  is what the SILPH SCOPE is for.
- The automatic opening only counts species you meet **after installing**,
  so it will not replay Pokémon you already knew. Each save slot keeps its
  own record.
- Works on Red, Blue and Yellow.

## Install

Download the `.zip` from
[Releases](https://github.com/ddagent/gen1recomp-battle-dex/releases) and
install it from the game: **MODS → Import mod .zip**. After that the launcher
offers **Update** whenever a new version appears.
