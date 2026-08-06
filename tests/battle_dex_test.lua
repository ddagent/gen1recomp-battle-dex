-- Standalone: luajit mods/battle_dex/tests/battle_dex_test.lua
--
-- ROM-free: everything runs against tests/fixture_data through the real
-- Loader, the real Hooks bus and the real Screens resolver, so a green run
-- means the mod really loads and really pushes a page in the game.
--
-- The two doors are tested from opposite directions.  The party row is
-- asserted on the list the hook returns; the foe hotkey is asserted on what
-- reaches game.stack, because a guard that silently declines and a guard
-- that fires look identical from inside the hook.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")

local Data = T.fixtures.fresh()
local SPECIES = T.fixtures.ids.species[1]   -- FIXMON_A

local run = T.sdk.loadMod("mods/battle_dex", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

-- ------- test doubles
--
-- The stub screen is registered in data.screens, which is the branch
-- Screens.resolve prefers over the builtin require -- so the push travels
-- the production path without dragging Font, sprites and a ROM cache in.

local pushed = {}
Data.screens = Data.screens or {}
Data.screens.DexEntryMenu = function(_, opts)
  pushed[#pushed + 1] = opts
  return { stub = true }
end
Screens.invalidate()

local function newGame(pressed)
  return {
    data = Data,
    save = {},
    input = { wasPressed = function(_, btn) return pressed == btn end },
    stack = {
      states = {},
      push = function(self, state) self.states[#self.states + 1] = state end,
      top = function(self) return self.states[#self.states] end,
    },
  }
end

-- stands in for a BattleState: only the fields the mod is allowed to read
local function newBattle(over)
  local battle = { phase = "menu", kind = "wild", surface = { 160, 144 },
                   enemy = { mon = { species = SPECIES, level = 5 } } }
  for k, v in pairs(over or {}) do battle[k] = v end
  function battle:battleKind() return self.kind end
  function battle:uiSize() return self.surface[1], self.surface[2] end
  function battle:bottomUIVisible() return self.bottomUI ~= false end
  return battle
end

local function step(game) Runtime.call("input.step", function() end, game, 1 / 60) end

local function startBattle(game, battle)
  game.stack:push(battle)
  Runtime.emit("battle.started", { battle = battle })
  return battle
end

local function endBattle(game)
  table.remove(game.stack.states)
  Runtime.emit("battle.ended", {})
end

-- ------- door 1: the foe hotkey

do
  local game = newGame("select")
  step(game)
  T.eq(#pushed, 0, "no battle: SELECT does nothing")

  local battle = startBattle(game, newBattle())
  step(game)
  T.eq(#pushed, 1, "SELECT at the battle menu opens a page")
  T.eq(pushed[1].species, SPECIES, "the page is the opponent's species")
  T.eq(pushed[1].forceOwned, true, "SHOW UNSEEN DATA defaults to the full entry")
  T.eq(game.stack:top().stub, true, "the page lands on the stack above the battle")

  -- with the page on top the battle is no longer the input state, so a
  -- second press must not stack a second page
  step(game)
  T.eq(#pushed, 1, "a press while the page is open does not stack another")

  table.remove(game.stack.states)   -- close the page
  endBattle(game)
  step(game)
  T.eq(#pushed, 1, "after battle.ended the hotkey goes quiet")
end

-- every refusal on its own, through the export rather than the push
do
  local game = newGame("select")
  local battle = startBattle(game, newBattle())
  local foeSpecies = run.loader.exports.battle_dex.foeSpecies
  T.eq(foeSpecies(game), SPECIES, "the happy path resolves the foe")

  battle.phase = "moveSelect"
  T.eq(foeSpecies(game), nil, "mid-turn phases refuse")
  battle.phase = "menu"

  game.stack:push({ other = true })
  T.eq(foeSpecies(game), nil, "a screen above the battle refuses")
  table.remove(game.stack.states)

  battle.kind = "link"
  T.eq(foeSpecies(game), nil, "link battles refuse: a one-sided pause desyncs")
  battle.ghost = true
  battle.kind = "ghost"
  T.eq(foeSpecies(game), nil, "the GHOST encounter refuses")
  battle.kind = "wild"
  battle.ghost = nil

  battle.enemy = nil
  T.eq(foeSpecies(game), nil, "a battle with no enemy battler refuses")
  endBattle(game)
end

-- a wrong button is not the button
do
  local game = newGame("b")
  startBattle(game, newBattle())
  local before = #pushed
  step(game)
  T.eq(#pushed, before, "B does not open the page")
  endBattle(game)
end

-- an unknown species is refused, not crashed into the sprite loader
do
  local game = newGame("select")
  startBattle(game, newBattle({ enemy = { mon = { species = "NO_SUCH_MON" } } }))
  local before = #pushed
  step(game)
  T.eq(#pushed, before, "a species with no content record is declined")
  endBattle(game)
end

-- ------- door 2: the party submenu row

local function submenu(items, ctx)
  return Runtime.call("ui.party.submenu",
    function(_, list) return list end,
    newGame(), items, { species = SPECIES }, ctx)
end

do
  -- the real in-battle list (PartyMenu.lua SwitchStatsCancelText)
  local vanilla = { { label = "SWITCH", action = "battle_switch" },
                    { label = "STATS", action = "stats" },
                    { label = "CANCEL", action = "cancel" } }
  local out = submenu(vanilla, { battle = {} })
  T.eq(#out, 4, "the hook added exactly one row")
  T.eq(out[3].label, "DEX", "DEX sits directly under STATS")
  T.eq(out[4].label, "CANCEL", "the vanilla rows keep their order")
  T.eq(out[3].action, nil, "the row carries onSelect, not an engine action id")

  -- anchored on action, so a renamed STATS label still places correctly
  local translated = { { label = "ESTADO", action = "stats" },
                       { label = "CANCELAR", action = "cancel" } }
  local tout = submenu(translated, { battle = {} })
  T.eq(tout[2].label, "DEX", "the anchor survives a translated label")
end

do
  local field = { { label = "STATS", action = "stats" },
                  { label = "SWITCH", action = "switch" } }
  local out = submenu(field, { overworld = {} })
  T.eq(#out, 2, "out of battle the list is untouched")
end

do
  -- an upstream mod that returns a non-table must not be papered over
  local out = Runtime.call("ui.party.submenu", function() return nil end,
    newGame(), {}, {}, { battle = {} })
  T.eq(out, nil, "a non-table upstream result is passed through unchanged")
end

-- the row's onSelect opens that mon's page
do
  local game = newGame()
  local out = Runtime.call("ui.party.submenu",
    function(_, list) return list end,
    game, { { label = "STATS", action = "stats" } }, {}, { battle = {} })
  local before = #pushed
  out[2].onSelect({ species = SPECIES }, game)
  T.eq(#pushed, before + 1, "choosing DEX opens a page")
  T.eq(pushed[#pushed].species, SPECIES, "it is the focused mon's page")
end

-- ------- the badge
--
-- The stub's graphics calls are no-ops, so the assertions are on what the
-- overlay decides to draw and where, never on pixels -- the same contract
-- the engine's own headless suites keep.

-- The badge places itself with a transform now, so the interesting value is
-- the origin it translates to, not the coordinates it hands Font.draw.  Spy
-- on the transform and the fills; the stub's graphics calls are no-ops, so
-- these assertions are about decisions, never pixels.
local Font = require("src.render.Font")
local realFontDraw = Font.draw
local realRectangle = love.graphics.rectangle
local realTranslate = love.graphics.translate
local realScale = love.graphics.scale
local realSetCanvas = love.graphics.setCanvas
local realSetColor = love.graphics.setColor
local alpha = 1
local drawn, fills, origin, scaled, canvases

local function resetSpies()
  drawn, fills, origin, scaled, canvases = {}, {}, nil, nil, {}
end

Font.draw = function(text, x, y)
  drawn[#drawn + 1] = { text = text, x = x, y = y }
  return #tostring(text) * 8
end
-- the icon's own spans are fills too, so record geometry: the plate is the
-- only fill that spans the whole badge
love.graphics.setColor = function(_, _, _, a) alpha = a or 1 end
love.graphics.rectangle = function(mode, x, y, w, h)
  if mode == "fill" then
    fills[#fills + 1] = { x = x, y = y, w = w, h = h, alpha = alpha }
  end
end
love.graphics.translate = function(x, y) origin = { x = x, y = y } end
love.graphics.scale = function(s) scaled = s end
-- nil is a real value here (restoring "no canvas"), and t[#t+1] = nil is a
-- no-op, so it would vanish from the log
love.graphics.setCanvas = function(c) canvases[#canvases + 1] = c or "NONE" end

-- the plate is the only fill spanning the whole badge; its alpha is what
-- separates the opaque plate from the arena's glass wash
local function plate(width)
  for _, r in ipairs(fills) do
    if (r.w or 0) >= width then return r end
  end
  return nil
end

-- options live on the loader; setting them here is what the manager's
-- options pane does at runtime
local function setOptions(over)
  run.loader.modOptions.battle_dex = over or {}
end

local function overlay(b)
  resetSpies()
  Runtime.call("battle.overlay", function() end, b)
  return drawn[1]
end

-- the fixture has no SPRITE_POKEDEX, so these exercise the drawn-icon
-- fallback: 10px icon + 2px gap + 6 glyphs = 60 wide
local BADGE_W = 10 + 2 + 6 * 8

do
  setOptions({})
  local label = overlay(newBattle())
  T.check(label ~= nil, "the badge draws at the battle prompt")
  T.eq(label.text, "SELECT", "the badge names the configured button")
  T.eq(plate(BADGE_W).alpha, 1, "outside the arena the plate is opaque")
  T.eq(origin.x, 160 - BADGE_W - 4, "TOP RIGHT is pinned to the surface's right edge")
  T.check(origin.x + BADGE_W <= 160, "and the badge stays inside the surface")
  T.check(origin.y < 72, "TOP RIGHT puts it in the upper half")
  T.eq(label.x, 12, "the label follows the icon within the badge")

  local before = origin.x
  overlay(newBattle({ surface = { 304, 144 } }))
  T.eq(origin.x - before, 144, "the wide surface shifts it by the width delta")
end

do
  setOptions({ hint_pos = "bottom_left" })
  overlay(newBattle())
  T.check(origin.x < 24, "BOTTOM LEFT hugs the left edge")
  T.eq(origin.y, 112, "and sits on the OG menu's own text row")
end

-- ------- the voxel arena (DRAMATIC_SHAPE)
--
-- Its OverworldBattle pins the foe's HUD to x=0 and the player's to pw, the
-- true screen edges, and drops every opaque white fill so the diorama shows
-- through. A badge that ignored either would float short of the corner and
-- read as a sticker, which is exactly what the device showed.

local function voxelBattle(over)
  local b = newBattle(over)
  b.dramaticShapeShot = { canvas = "CANVAS", scale = 4,
                          pw = 1920, ph = 1080, lx = 460, ly = 60 }
  return b
end

do
  setOptions({})
  local label = overlay(voxelBattle())
  T.check(label ~= nil, "the badge still draws inside the arena")
  T.eq(scaled, 4, "it is scaled by the arena's GB-to-window scale")
  T.eq(canvases[1], "CANVAS", "and drawn into the arena's own canvas")
  local wash = plate(BADGE_W)
  T.check(wash ~= nil, "the arena still gets a backing so the glyphs read")
  T.check(wash.alpha < 1,
    "but translucent: an opaque white is what withoutBoxFill strips")
  T.check(wash.alpha > 0.4, "and opaque enough to earn contrast over dark ground")
  -- pinned to pw like the player HUD, not to the 160-wide frame
  T.eq(origin.x, 1920 - (BADGE_W + 4) * 4, "TOP RIGHT pins to the true screen edge")
  T.check(origin.x > 460, "which is right of where the GB frame ends")
  T.eq(origin.y, 60 + 4 * 4, "and hangs off the frame's top edge")

  setOptions({ hint_pos = "bottom_left" })
  overlay(voxelBattle())
  T.check(origin.x < 100, "BOTTOM LEFT pins to the far left in the arena too")
  T.check(origin.y > 900, "and to the bottom")
  setOptions({})
end

do
  -- a half-built shot must not be placed against; fall back to the frame
  local partial = newBattle()
  partial.dramaticShapeShot = { canvas = "CANVAS", scale = 4 }  -- no pw/lx/ly
  overlay(partial)
  T.eq(origin.x, 160 - BADGE_W - 4, "an incomplete shot falls back to the GB frame")
  T.eq(canvases[1], "NONE", "and never redirects the canvas")
end

do
  setOptions({ foe_button = "start" })
  T.eq(overlay(newBattle()).text, "START", "the badge tracks the button choice")

  setOptions({ foe_button = "off" })
  T.eq(overlay(newBattle()), nil, "no hotkey, no badge advertising it")

  setOptions({ hint = false })
  T.eq(overlay(newBattle()), nil, "SHOW DEX BADGE off hides it")
  setOptions({})
end

do
  T.eq(overlay(newBattle({ phase = "messages" })), nil,
    "the badge is gone while the battle is animating")
  T.eq(overlay(newBattle({ kind = "link" })), nil, "and in link battles")
  T.eq(overlay(newBattle({ kind = "ghost", ghost = true })), nil,
    "and against the GHOST")
  T.eq(overlay(newBattle({ bottomUI = false })), nil,
    "and when a hook has hidden the bottom UI")
  -- pairs() cannot carry a nil through the override table, so clear it here
  local noFoe = newBattle()
  noFoe.enemy = nil
  T.eq(overlay(noFoe), nil, "and with no enemy battler")
end

do
  -- a battle object with none of the optional methods must not throw: the
  -- overlay runs every frame, so a nil-index here would be a hard crash
  setOptions({})
  local bare = { phase = "menu", kind = "wild",
                 enemy = { mon = { species = SPECIES } } }
  local ok = pcall(Runtime.call, "battle.overlay", function() end, bare)
  T.check(ok, "a battle without uiSize/bottomUIVisible degrades to 160x144")
end

-- ------- the POKeDEX sprite
--
-- The icon is OAK's table POKeDEX read from the player's cache, so it only
-- exists once a ROM has been imported.  The sprite lookup is resolved once
-- and remembered, which means a second mod instance -- against data that
-- HAS the sprite -- is the only honest way to exercise the other branch.

run.release()

do
  local spriteData = T.fixtures.fresh()
  spriteData.screens = { DexEntryMenu = function() return { stub = true } end }
  spriteData.sprites = spriteData.sprites or {}
  spriteData.sprites.SPRITE_POKEDEX = { image = "cache/sprites/pokedex.png" }

  local drawnImages = {}
  local realDraw, realNewImage = love.graphics.draw, love.graphics.newImage
  love.graphics.newImage = function(path) return { path = path,
    getDimensions = function() return 16, 16 end } end
  love.graphics.draw = function(image) drawnImages[#drawnImages + 1] = image end

  local run2 = T.sdk.loadMod("mods/battle_dex", { data = spriteData })
  T.eq(#run2.errors, 0, "loads clean against sprite-bearing data")
  run2.loader.modOptions.battle_dex = {}

  local battle = newBattle()
  battle.game = { data = spriteData }
  resetSpies()
  Runtime.call("battle.overlay", function() end, battle)

  T.eq(#drawnImages, 1, "the badge draws the cached sprite, not the fallback")
  T.eq(drawnImages[1].path, "cache/sprites/pokedex.png",
    "and it is SPRITE_POKEDEX out of the player's own cache")
  -- 16px sprite widens the badge from 60 to 66, so the right pin moves left
  T.eq(origin.x, 160 - (16 + 2 + 6 * 8) - 4,
    "the badge widens to the sprite and stays pinned right")
  T.eq(drawn[1].y, 4, "8px glyphs are centred against the 16px sprite")

  love.graphics.draw, love.graphics.newImage = realDraw, realNewImage
  run2.release()
end

Font.draw = realFontDraw
love.graphics.rectangle = realRectangle
love.graphics.translate = realTranslate
love.graphics.scale = realScale
love.graphics.setCanvas = realSetCanvas
love.graphics.setColor = realSetColor

Screens.invalidate()
T.finish("battle_dex")
