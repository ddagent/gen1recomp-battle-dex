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
    -- Off by default now.  On, this forced the entry open as though the
    -- species were caught -- which overrode dex_pages' own OWNED DATA ONLY
    -- gate, so a POKeMON you had merely glimpsed in battle handed over its
    -- stats, its locations and its whole movelist.  Seen gets you the
    -- picture; owned gets you the data, which is both what the engine's own
    -- dex does and how it works in the show.
    { key = "full_entry", label = "SHOW UNSEEN DATA", type = "toggle",
      default = false },
    { key = "hint", label = "SHOW DEX BADGE", type = "toggle", default = true },
    -- TOP RIGHT is over the foe's pic slot in both layouts, so the badge
    -- carries its own plate.  BOTTOM LEFT is the genuinely empty corner on
    -- the OG layout (the menu box only covers x64-160), but on WIDE that
    -- space holds "What will X do?" -- hence a setting rather than a guess.
    { key = "hint_pos", label = "BADGE CORNER", type = "choice",
      default = "top_right",
      choices = { { "TOP RIGHT", "top_right" },
                  { "BOTTOM LEFT", "bottom_left" } } },
    -- Percent of the arena's own magnification.  Only the arena honours it:
    -- the flat layouts draw one GB pixel to one and have nothing to give
    -- back, so anything under 100 there would resample the art rather than
    -- shrink it.  Read every frame, so turning the dial moves the badge as
    -- you turn it.
    { key = "badge_scale", label = "BADGE SIZE %", type = "number",
      default = 60, min = 30, max = 100, step = 5 },
    { key = "badge_inset", label = "BADGE INSET", type = "number",
      default = 2, min = 0, max = 16, step = 1 },
    -- The first time you meet a species, open its page for you once the
    -- intro text is done and you have control.  "First time" is tracked by
    -- this mod, not read off the dex, because by the time any mod can see a
    -- wild battle the engine has already marked the species seen --
    -- markSeen runs inside BattleState.newWild, before battle.started.
    { key = "auto_open", label = "AUTO DEX ON NEW", type = "toggle",
      default = true },
  })

  -- battle.started hands over the live BattleState.  Nothing else in this
  -- file knows how to find one, which is the point: no private require, no
  -- engine table reached behind the loader's back.
  local battle = nil

  -- ------- "have I met this one before?"
  --
  -- The dex cannot answer this by the time we are allowed to ask.  markSeen
  -- runs inside BattleState.newWild (BattleState.lua:618), well before
  -- enter() emits battle.started, so save.pokedex.seen[species] is already
  -- true for the mon standing in front of you -- a naive check would be
  -- false every single time and the toggle would look broken rather than
  -- quiet.  So the mod keeps its own roll in its own save bucket.
  --
  -- Seeding happens at save.loaded / save.created, which is the only moment
  -- the dex can be read honestly: Game:adoptSave has already pointed
  -- mod.save at this slot's modData (Game.lua:1099) and the event fires
  -- after (:1128), while no battle -- and therefore no markSeen -- has run
  -- yet.  So the roll is the dex exactly as it stood, with nothing to
  -- subtract and nothing to guess.
  local function seedFrom(save)
    if type(mod.save:get("met")) == "table" then return end   -- already ours
    local roll = {}
    local dex = save and save.pokedex
    for id in pairs(dex and dex.seen or {}) do roll[id] = true end
    mod.save:set("met", roll)
  end

  mod.events:on("save.loaded", function(ev) seedFrom(ev and ev.save) end)
  mod.events:on("save.created", function(ev) seedFrom(ev and ev.save) end)

  -- Last resort, if a battle somehow arrives before either event.  Here the
  -- dex has already been written by markSeen, so the current species has to
  -- be subtracted back out -- a guess, and the reason the real seeding
  -- above exists: it cannot tell "markSeen just added this" from "this was
  -- already known", so a first battle against a species you HAD seen would
  -- open once.
  local function met(game, species)
    local roll = mod.save:get("met")
    if type(roll) ~= "table" then
      roll = {}
      local dex = game and game.save and game.save.pokedex
      for id in pairs(dex and dex.seen or {}) do
        if id ~= species then roll[id] = true end
      end
      mod.save:set("met", roll)
      mod.log:warn("seeded the met roll from a battle rather than save.loaded; "
        .. "%s may open once even if you had met it", tostring(species))
    end
    return roll
  end

  -- armed at battle.started, spent at the first prompt: the auto-open has to
  -- wait for the intro text to finish, and "the player has control" is the
  -- same moment the hotkey becomes legal
  local pendingAuto = false

  -- One species, one decision -- shared by the battle's opening and by
  -- every send-out after it.
  local function consider(theBattle, species)
    if not species then return end
    local roll = met(theBattle and theBattle.game, species)
    -- record the meeting whatever the toggle says, so switching it on later
    -- does not replay every species you have already fought
    if not roll[species] then
      pendingAuto = mod.options:get("auto_open") == true
      roll[species] = true
      mod.save:set("met", roll)
    end
  end

  mod.events:on("battle.started", function(ev)
    battle = ev.battle
    pendingAuto = false
    consider(battle, ev.species
      or (battle and battle.enemy and battle.enemy.mon
          and battle.enemy.mon.species))
  end)

  -- A trainer with six unseen mons is six first meetings, but battle.started
  -- only fires once -- so without this the dex opened for their lead and
  -- stayed shut for the rest of the team.  battle.battler_switched covers
  -- both a mid-fight switch and the send-out after a faint.
  mod.events:on("battle.battler_switched", function(ev)
    local theBattle = ev and ev.battle
    if not (theBattle and battle and theBattle == battle) then return end
    -- both sides fire this; only the foe's side is a new face to us
    local battler = ev.battler
    if not (battler and battler == theBattle.enemy) then return end
    consider(theBattle, battler.mon and battler.mon.species)
  end)

  mod.events:on("battle.ended", function()
    battle = nil
    pendingAuto = false
  end)

  -- The POKeDEX has to exist before it can be opened.  OAK hands it over
  -- after the parcel; until then the game has no dex at all -- START does
  -- not even list it.  Without this the mod opened an entry for the rival's
  -- EEVEE during the very first battle in the lab, well before the player
  -- owns one.  Checked here rather than at each door, because the auto-open
  -- and the hotkey both come through this one function.
  local function hasDex(game)
    local flags = game and game.save and game.save.flags
    return (flags and flags.EVENT_GOT_POKEDEX) == true
  end

  local function openEntry(game, species)
    if not species then return end
    if not hasDex(game) then return end
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
    -- no dex, no badge: it advertises a page that cannot be opened yet
    if not hasDex(theBattle.game) then return nil end
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
    if not battle then return result end

    -- The auto-open rides the same guards as the hotkey -- foeSpecies is
    -- what refuses link, ghost, mid-turn and a screen already on top -- so
    -- it can only land at the prompt, never over the intro text it is
    -- waiting for.
    if pendingAuto then
      local species = foeSpecies(game)
      if species then
        pendingAuto = false
        openEntry(game, species)
        return result
      end
    end

    local button = mod.options:get("foe_button")
    if button == "off" then return result end
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

  -- Three glyphs rather than the whole word: the label is a reminder, not a
  -- sentence, and every character costs a full 8px cell in a box that is
  -- already rounded up to whole tiles.  SELECT -> SEL takes the box from 11
  -- tiles to 8.
  local SHORT = { select = "SEL", start = "STA" }

  -- Inside the arena the badge is drawn magnified -- around 6.8x on a 1080p
  -- handheld -- so shrinking it is a matter of giving some of that
  -- magnification back, NOT of resampling anything.  At 60% every source
  -- pixel still covers about four screen pixels, so the sprite and the font
  -- stay pixel-exact; they simply take less room.  The flat layouts get no
  -- multiplier because there is none to give back: they draw one GB pixel
  -- to one GB pixel, and anything under 100 there would genuinely destroy
  -- the art.  They get the shorter label instead.
  local function arenaScale()
    local pct = tonumber(mod.options:get("badge_scale")) or 60
    return math.max(0.3, math.min(1, pct / 100))
  end

  local function inset()
    return tonumber(mod.options:get("badge_inset")) or PAD
  end

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

  -- The chrome is the engine's own box, not a rectangle of our own:
  -- Font.drawBox paints a white interior and then the four corners and two
  -- runs from Font.BORDER, which src/ui/Theme.lua rebuilds from
  -- field.theme.border.  Drawing it ourselves would have frozen this badge
  -- to the default border while a theme mod restyled every other box in the
  -- game around it.  Boxes are tile-aligned, so the badge is sized in tiles
  -- and the interior starts one tile in.
  local TILE = 8

  local function boxTiles(iconW, iconH, label)
    local content = iconW + GAP + #label * GLYPH_W
    return math.ceil(content / TILE) + 2, math.ceil(iconH / TILE) + 2
  end

  -- The arena's glass is not a wash we can mix ourselves.  BattleHud.panel
  -- draws a BLURRED COPY OF THE WORLD BEHIND THE RECT at FROST, and only
  -- then a white tint at TINT -- so the panel keeps the scene's own colour
  -- and merely lifts it toward white.  Any flat white of our own reads more
  -- opaque than that no matter what alpha we pick, because it throws the
  -- scene away instead of blurring it.  So call theirs: it is a documented
  -- entry point ("in that target's own coordinates ... world pixels
  -- (world = true) for a panel laid straight onto the world image"), and
  -- OverworldBattle lays the HUDs AND the text box with the same call.
  local hudLib, hudTried = nil, false

  local function battleHud()
    if hudTried then return hudLib end
    hudTried = true
    local handle = type(mod.find) == "function" and mod.find("DRAMATIC_SHAPE")
    local lib = handle and handle.exports and handle.exports.lib
    if not lib or type(lib.require) ~= "function" then return nil end
    local ok, hud = pcall(lib.require, "BattleHud")
    if ok and type(hud) == "table" and type(hud.panel) == "function" then
      hudLib = hud
      mod.log:info("glass: using DRAMATIC_SHAPE's own BattleHud.panel")
    end
    return hudLib
  end

  -- true once the real frosted panel is down.  It returns false of its own
  -- accord when the frost buffer is not built yet (early frames, or a
  -- device where the canvas could not be made), which is exactly when we
  -- still owe the glyphs a backing -- hence the flat fallback below.
  local FALLBACK_WASH = 0.67

  local function arenaGlass(x, y, w, h, shot)
    local hud = battleHud()
    if not hud then return false end
    local ok, drew = pcall(hud.panel, { x, y, w, h }, shot, true)
    return ok and drew == true
  end

  -- Font.drawBox's interior is an opaque white fill, which is exactly the
  -- signature OverworldBattle.withoutBoxFill strips so the diorama shows
  -- through every other box.  Inside the arena we do the same to ours and
  -- lay the glass in its place; outside, the interior IS the plate.
  local function boxWithoutFill(fn)
    local g = love.graphics
    local rectangle = g.rectangle
    g.rectangle = function(mode, ...)
      if mode == "fill" then
        local r, gr, b, a = g.getColor()
        if r > 0.99 and gr > 0.99 and b > 0.99 and a > 0.99 then return end
      end
      return rectangle(mode, ...)
    end
    local ok, err = pcall(fn)
    g.rectangle = rectangle
    if not ok then mod.log:error("badge chrome failed: %s", tostring(err)) end
  end

  -- Draws at the origin in GB pixels; the caller owns the transform.
  -- `glassed` says the frosted panel is already down, so the interior must
  -- not be painted over it.
  local function drawBadge(theBattle, label, iconW, iconH, solid, glassed)
    local g = love.graphics
    local Font = mod.ui.Font
    local tw, th = boxTiles(iconW, iconH, label)

    if solid then
      Font.drawBox(0, 0, tw, th)
    else
      if not glassed then
        g.setColor(1, 1, 1, FALLBACK_WASH)
        g.rectangle("fill", 0, 0, tw * TILE, th * TILE)
      end
      g.setColor(1, 1, 1, 1)
      boxWithoutFill(function() Font.drawBox(0, 0, tw, th) end)
    end

    g.setColor(1, 1, 1, 1)
    local art = dexSprite(theBattle)
    if art then
      g.draw(art.image, art.quad, TILE, TILE)
    else
      g.setColor(0, 0, 0, 1)
      for _, span in ipairs(ICON_SPANS) do
        g.rectangle("fill", TILE + span.x, TILE + span.y, span.w, 1)
      end
    end
    g.setColor(0, 0, 0, 1)
    -- glyphs are 8 tall; centre them against whichever icon we drew
    Font.draw(label, TILE + iconW + GAP,
              TILE + math.floor((iconH - 8) / 2))
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

    local label = SHORT[button] or "SEL"
    local art = dexSprite(theBattle)
    local iconW = art and SPRITE_W or ICON_W
    local iconH = art and SPRITE_H or ICON_H
    local tw, th = boxTiles(iconW, iconH, label)
    local boxW, boxH = tw * TILE, th * TILE
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
      -- the badge's own magnification; the margin keeps the arena's, so the
      -- badge sits the same distance off the edge as it did at full size
      local eff = s * arenaScale()
      local bw, bh = boxW * eff, boxH * eff
      local pad = inset()
      -- All four edges are the canvas's, not the Game Boy frame's.  The
      -- engine's own HUD panels are frame-relative vertically (their rects
      -- are shot.ly + y * s) because they belong to the battle's layout --
      -- the foe's panel has to sit level with the foe.  This badge does not
      -- belong to that layout; it is a hint about a button, and pinning it
      -- to the frame's top edge left shot.ly of dead screen above it (about
      -- 36px on a 1080p handheld) while the opposite corner was already
      -- using shot.ph.  Same corner logic on every side now.
      local ox, oy
      if bottomLeft then
        ox, oy = pad * s, shot.ph - bh - pad * s
      else
        ox, oy = shot.pw - bw - pad * s, pad * s
      end
      g.setCanvas(shot.canvas)
      -- the same blend OverworldBattle sets before its own panel run
      if g.setBlendMode then g.setBlendMode("alpha") end
      -- panel draws in the target's own coordinates, so it goes down BEFORE
      -- the transform, with the rect in world pixels
      local glassed = arenaGlass(ox, oy, bw, bh, shot)
      g.translate(ox, oy)
      g.scale(eff, eff)
      drawBadge(theBattle, label, iconW, iconH, false, glassed)
    else
      local w, h = 160, 144
      if theBattle.uiSize then
        local uw, uh = theBattle:uiSize()
        w, h = uw or w, uh or h
      end
      if bottomLeft then
        g.translate(inset(), h - boxH - inset())
      else
        g.translate(w - boxW - inset(), inset())
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
