-- battle_dex: read a POKéDEX entry without leaving the battle.
--
-- The battle has two menus, so this has two doors:
--
--   SELECT at the FIGHT/PKMN/ITEM/RUN prompt   -> the opponent's entry
--   PKMN -> a mon -> DEX                       -> that party mon's entry
--
-- Nothing here reaches behind the loader.  The opponent arrives in the
-- battle.started payload, the page is the engine's own DexEntryMenu pushed
-- through mod.ui, and both doors are switchable in the manager's OPTIONS.

local ENTRY_SCREEN = "DexEntryMenu"

return function(mod)
  mod.options:define({
    -- The battle menu reads the d-pad and A only, so SELECT and START are
    -- both genuinely free there.  SELECT is the default because a lone
    -- START is one quarter of the soft-reset chord and reads as riskier,
    -- even though that chord needs all four held for 16 consecutive polls.
    { key = "foe_button", label = "FOE DEX BUTTON", type = "choice",
      default = "select",
      choices = { { "SELECT", "select" }, { "START", "start" },
                  { "OFF", "off" } } },
    { key = "party_row", label = "DEX IN PKMN MENU", type = "toggle",
      default = true },
    -- Off keeps the vanilla gate, where an unseen mon's page is blank the
    -- way the POKéDEX itself would show it.  On mirrors StarterDex's
    -- forceOwned (engine/events/starter_dex.asm), which is what makes this
    -- worth opening on a first encounter.  Neither setting writes the owned
    -- bit, so dex completion is untouched either way.
    { key = "full_entry", label = "SHOW UNSEEN DATA", type = "toggle",
      default = true },
    { key = "hint", label = "SHOW DEX BADGE", type = "toggle", default = true },
    -- TOP RIGHT is over the foe's pic slot in both layouts, so the badge
    -- carries its own plate.  BOTTOM LEFT is the genuinely empty corner on
    -- the OG layout (the menu box only covers x64-160), but on WIDE that
    -- space holds "What will X do?" -- hence a setting rather than a guess.
    { key = "hint_pos", label = "BADGE CORNER", type = "choice",
      default = "top_right",
      choices = { { "TOP RIGHT", "top_right" },
                  { "BOTTOM LEFT", "bottom_left" } } },
  })

  -- battle.started hands over the live BattleState.  Nothing else in this
  -- file knows how to find one, which is the point: no private require, no
  -- engine table reached behind the loader's back.
  local battle = nil
  mod.events:on("battle.started", function(ev) battle = ev.battle end)
  mod.events:on("battle.ended", function() battle = nil end)

  local function openEntry(game, species)
    if not species then return end
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[species]
    if not def then
      -- a mod-added species with no content.pokemon record would crash the
      -- page on its sprite lookup; refuse and name the fix
      mod.log:warn("no species record for %s -- register it in "
        .. "content.pokemon before it can have a dex page", tostring(species))
      return
    end
    mod.ui.push(game, ENTRY_SCREEN,
      { species = species, forceOwned = mod.options:get("full_entry") })
  end

  -- ------- door 1: the opponent, from the battle menu

  -- Every line here is a reason NOT to fire.  Split from foeSpecies because
  -- the badge and the hotkey do not share the stack test: battle.overlay is
  -- only reached while the battle is being drawn, and it is handed the
  -- battle rather than the game.
  local function readableFoe(theBattle)
    if not theBattle then return nil end
    -- only at the FIGHT/PKMN/ITEM/RUN prompt: mid-turn the battle is
    -- animating, and a pushed screen would freeze it mid-sequence
    if theBattle.phase ~= "menu" then return nil end
    local kind = theBattle.battleKind and theBattle:battleKind() or nil
    -- link: pushing a screen pauses this side only and the peer walks the
    -- turn without us, which is a desync rather than a pause.
    -- ghost: the unidentified GHOST is the encounter -- naming it is the
    -- one thing the SILPH SCOPE is for.
    if kind == "link" or kind == "ghost" then return nil end
    local foe = theBattle.enemy and theBattle.enemy.mon
    return foe and foe.species or nil
  end

  -- Exported so the tests can assert each refusal on its own rather than
  -- inferring it from a push.
  local function foeSpecies(game)
    if not battle then return nil end
    -- a text box, the bag or the party list can sit above the battle; only
    -- act when the battle itself is the state taking input
    if not (game.stack and game.stack.top and game.stack:top() == battle) then
      return nil
    end
    return readableFoe(battle)
  end

  mod.exports.foeSpecies = foeSpecies

  mod.hooks:wrap("input.step", function(nextFn, game, dt)
    local result = nextFn(game, dt)
    local button = mod.options:get("foe_button")
    if button == "off" or not battle then return result end
    if not (game and game.input and game.input.wasPressed) then return result end
    -- input.step runs before Input:step promotes queued edges (Game.lua), so
    -- this reads the previous tick's edge: the page opens one fixed step
    -- (~16ms) after the press, and each press is still observed exactly once
    if not game.input:wasPressed(button) then return result end
    local species = foeSpecies(game)
    if species then openEntry(game, species) end
    return result
  end)

  -- ------- the badge
  --
  -- battle.overlay is draw-only and fires at the end of the battle's own
  -- draw, so everything below is measured in GB pixels and placed by a
  -- transform.  One drawing routine, three frames of reference.

  -- The icon is the POKeDEX as it sits on OAK's table -- SPRITE_POKEDEX,
  -- the same overworld sprite the lab draws.  It is read from the player's
  -- own imported cache at draw time, never bundled, so the package still
  -- ships no ROM-derived bytes.  A cache without it (or a mod that removed
  -- it) falls back to the hand-drawn glyph below rather than losing the
  -- badge.
  local SPRITE_ID = "SPRITE_POKEDEX"
  local SPRITE_W, SPRITE_H = 16, 16

  -- 10x10 1-bit stand-in: round indicator light, small companion, screen.
  -- 10 wide rather than 8 because at 8x8 a full device outline eats nearly
  -- half the pixels and the whole thing reads as a solid block.
  local ICON = {
    ".###......",
    "#...#.##..",
    "#...#.##..",
    ".###......",
    "..........",
    ".########.",
    ".#......#.",
    ".#......#.",
    ".########.",
    "..........",
  }
  local ICON_W, ICON_H = 10, 10
  local GLYPH_W, GAP, PAD = 8, 2, 2

  -- Resolved to horizontal runs once at load: 14 rectangles a frame instead
  -- of 64, which is the difference that matters on the LOW performance tier.
  local ICON_SPANS = {}
  for row = 1, #ICON do
    local line, col = ICON[row], 1
    while col <= #line do
      if line:sub(col, col) == "#" then
        local run = 0
        while line:sub(col + run, col + run) == "#" do run = run + 1 end
        ICON_SPANS[#ICON_SPANS + 1] = { x = col - 1, y = row - 1, w = run }
        col = col + run
      else
        col = col + 1
      end
    end
  end

  -- The cache path is stable for a session but the image is not ours, so it
  -- is resolved once and held rather than reloaded 60 times a second.
  local sprite = nil          -- { image, quad } once resolved
  local spriteTried = false

  local function dexSprite(theBattle)
    if spriteTried then return sprite end
    spriteTried = true
    local data = theBattle.game and theBattle.game.data
    local def = data and data.sprites and data.sprites[SPRITE_ID]
    local path = def and def.image
    if not path then
      mod.log:info("%s is not in this cache; using the drawn icon", SPRITE_ID)
      return nil
    end
    local ok, image = pcall(love.graphics.newImage, path)
    if not ok or not image then
      mod.log:warn("could not load %s (%s); using the drawn icon",
                   SPRITE_ID, tostring(image))
      return nil
    end
    -- overworld sheets stack their frames vertically; the resting frame is
    -- the first one, and a 16x16 quad off the top-left is it whatever else
    -- the sheet carries
    local iw, ih = image:getDimensions()
    sprite = { image = image,
               quad = love.graphics.newQuad(0, 0, SPRITE_W, SPRITE_H, iw, ih) }
    return sprite
  end

  -- Inside the voxel arena the engine's own boxes lose their fill --
  -- OverworldBattle.withoutBoxFill drops every opaque white rectangle so the
  -- diorama shows through -- and an opaque plate here would read as a
  -- sticker pasted over the scene.  But bare black glyphs over a dark wall
  -- are unreadable, which is why DRAMATIC_SHAPE's own HUD panels are not
  -- bare either: BattleHud lays a blurred capture at 0.55 under a white
  -- wash at 0.26, and its comment is explicit that "the panel's tint is what
  -- earns it its contrast".  One translucent wash reaches the same place
  -- without reaching into another mod for its frost canvas: still glass,
  -- still shows the scene, still legible over the worst ground.
  local ARENA_WASH = 0.72

  -- Draws at the origin in GB pixels; the caller owns the transform.
  local function drawBadge(theBattle, label, iconW, iconH, solid)
    local g = love.graphics
    local w = iconW + GAP + #label * GLYPH_W
    g.setColor(1, 1, 1, solid and 1 or ARENA_WASH)
    g.rectangle("fill", -PAD, -PAD, w + PAD * 2, iconH + PAD * 2)
    g.setColor(0, 0, 0, 1)
    g.rectangle("line", -PAD + 0.5, -PAD + 0.5,
                w + PAD * 2 - 1, iconH + PAD * 2 - 1)
    local art = dexSprite(theBattle)
    if art then
      g.setColor(1, 1, 1, 1)
      g.draw(art.image, art.quad, 0, 0)
      g.setColor(0, 0, 0, 1)
    else
      for _, span in ipairs(ICON_SPANS) do
        g.rectangle("fill", span.x, span.y, span.w, 1)
      end
    end
    -- glyphs are 8 tall; centre them against whichever icon we drew
    mod.ui.Font.draw(label, iconW + GAP, math.floor((iconH - 8) / 2))
  end

  mod.hooks:wrap("battle.overlay", function(nextFn, theBattle)
    local result = nextFn(theBattle)
    if not mod.options:get("hint") then return result end
    local button = mod.options:get("foe_button")
    -- the badge advertises the hotkey, so it goes away with it
    if button == "off" then return result end
    if not readableFoe(theBattle) then return result end
    -- a hook may hide the bottom UI; the prompt it points at is gone too
    if theBattle.bottomUIVisible and not theBattle:bottomUIVisible() then
      return result
    end

    local label = button == "start" and "START" or "SELECT"
    local art = dexSprite(theBattle)
    local iconW = art and SPRITE_W or ICON_W
    local iconH = art and SPRITE_H or ICON_H
    local badgeW = iconW + GAP + #label * GLYPH_W
    local bottomLeft = mod.options:get("hint_pos") == "bottom_left"

    -- DRAMATIC_SHAPE publishes the arena's geometry on the battle it is
    -- drawing: `scale` GB-pixels-to-window, `lx`/`ly` where the 160x144
    -- frame lands, `pw`/`ph` the whole canvas.  Its own HUDs do not stay
    -- inside the GB frame under it -- OverworldBattle pins the foe's panel
    -- to x=0 and the player's to pw, the true screen edges -- so a badge
    -- that stayed in the frame would float short of the corner while
    -- everything around it went wide.  Follow the HUDs, not the frame.
    local shot = rawget(theBattle, "dramaticShapeShot")
    if shot and not (shot.canvas and shot.scale and shot.scale > 0
                     and shot.pw and shot.ph and shot.lx and shot.ly) then
      shot = nil   -- a partially-built shot is not one we can place against
    end

    local g = love.graphics
    local prevCanvas = g.getCanvas()
    g.push("all")

    if shot then
      local s = shot.scale
      g.setCanvas(shot.canvas)
      if bottomLeft then
        g.translate(PAD * 2 * s, shot.ph - (iconH + PAD * 3) * s)
      else
        g.translate(shot.pw - (badgeW + PAD * 2) * s, shot.ly + PAD * 2 * s)
      end
      g.scale(s, s)
      drawBadge(theBattle, label, iconW, iconH, false)
    else
      local w, h = 160, 144
      if theBattle.uiSize then
        local uw, uh = theBattle:uiSize()
        w, h = uw or w, uh or h
      end
      if bottomLeft then
        -- the menu's own text row, so the badge sits on the FIGHT baseline
        g.translate(PAD + 2, h - 32)
      else
        g.translate(w - badgeW - PAD - 2, PAD + 2)
      end
      drawBadge(theBattle, label, iconW, iconH, true)
    end

    g.pop()
    -- push("all") restores the canvas on every LOVE we target, but the cost
    -- of being explicit is one call and the cost of being wrong is drawing
    -- the rest of the frame into the arena's canvas
    g.setCanvas(prevCanvas)
    g.setColor(1, 1, 1, 1)
    return result
  end)

  -- ------- door 2: your own party, from PKMN

  -- Anchored on the entry's `action`, not its label: a translation mod
  -- renames STATS through Strings() and a label anchor would silently miss
  -- and append.  Falls back to appending when no stats row exists, which
  -- keeps the row reachable either way.
  local function insertAfterStats(items, row)
    for i, item in ipairs(items) do
      if item.action == "stats" then
        table.insert(items, i + 1, row)
        return items
      end
    end
    items[#items + 1] = row
    return items
  end

  mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    -- call next first, then decorate what it returns: another mod's row
    -- survives and the vanilla rows are never rebuilt by hand
    local out = nextFn(game, items, mon, ctx)
    if type(out) ~= "table" then return out end
    if not mod.options:get("party_row") then return out end
    -- in battle only: out of battle the POKéDEX is a START-menu entry away
    if not (ctx and ctx.battle) then return out end
    return insertAfterStats(out, {
      label = "DEX",
      onSelect = function(m, g) openEntry(g or game, m and m.species) end,
    })
  end)
end
