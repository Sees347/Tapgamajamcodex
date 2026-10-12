-- Independent controlled seam matrix, based on tile-seam-{background-,}coverage.lua.
-- Runs inside the real main.lua NanoVGRender callback. No production files are written.
-- Original 1m grid and original background dimensions are retained; panel clips trim
-- the visible window, never scale the scene to fit. Black/white copies differ only
-- by an integer half-screen translation and the underlying solid color.
local GS = require "core.state"
local P = require "core.player"
local R = require "core.render"
local L = require "core.level"
local TS = require "core.tilesets"
local Backgrounds = require "core.map_backgrounds"
local HUD = require "ui.hud"
local BF = require "core.bossfx"

local scenarios = {
    { mode = "game", viewH = 8 },
    { mode = "game", viewH = 16 },
    { mode = "game", viewH = 26 },
    { mode = "editor", viewH = 4 },
    { mode = "editor", viewH = 80 },
}
local offsets = { 0, 0.25, 0.5, 0.75 }
local state = { draws = 0, wallMinCount = 100000, backgroundsOK = true, firstError = "", emitted = false }
local cases = {}
local cells = {} ---@type table<string, VisualMapCell>
for row = 1, 8 do
    for col = 1, 8 do
        cells[string.format("%d:%d", col, row)] = {
            tilesetId = "industrial_walls", tileId = 1, collider = "ground",
        }
    end
end
---@type TilesetMapData
local data = { tile = 1, originX = 0, originY = 0, cols = 8, rows = 8,
    visualLayers = { ground = { cells = cells, visible = true, locked = false } } }
---@type MapBackgroundImage[]
local images = {}
local seamX, seamY = 0, 0
local physicalW, physicalH, dpr = 0, 0, 1

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param color NVGcolor
local function rect(vg, x, y, w, h, color)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, color)
    nvgFill(vg)
end

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    LoadLevel("world", nil)
    V.assert(L.def ~= nil and L.def.tilemapData ~= nil, "world loaded for real main render callback")
    P.node.parent.updateEnabled = false
    GS.setMode("paused")
    BF.reset()
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    SetGameControlsVisible(false)
    physicalW, physicalH, dpr = graphics:GetWidth(), graphics:GetHeight(), math.max(1, graphics:GetDPR())
    V.assert(dpr == 1, "surfaceless matrix uses physical-pixel offsets with DPR=1")
    local source = L.def.tilemapData
    data.tile = source.tile
    V.assert(data.tile == 1, "controlled wall grid retains original world 1m tile size")
    for _, image in ipairs(source.backgroundImages) do
        if image.id == "background_2" or image.id == "background_3" then
            images[#images + 1] = {
                id = image.id, assetId = image.assetId, x = image.x, y = image.y, width = image.width,
            }
        end
    end
    V.assert(#images == 2, "exact original background 2/3 instances selected")
    seamX = images[1].x + images[1].width / 2
    seamY = (images[1].y + images[2].y) / 2
    V.assert(math.abs(seamX - (images[2].x - images[2].width / 2)) < 1e-10,
        "background 2 right equals background 3 left in metres")
    local screenW, screenH = physicalW / dpr, physicalH / dpr
    local halfH = math.floor(screenH / 2)
    local panelW = math.floor(screenW / 8)
    local panelH = math.floor(halfH / 5)
    for row, scenario in ipairs(scenarios) do
        for oi, offset in ipairs(offsets) do
            for kindIndex, kind in ipairs({ "walls", "background23" }) do
                cases[#cases + 1] = {
                    kind = kind, mode = scenario.mode, viewH = scenario.viewH,
                    offsetX = offset, offsetY = offset, ppu = screenH / scenario.viewH,
                    x = ((oi - 1) * 2 + kindIndex - 1) * panelW,
                    y = (row - 1) * panelH, w = panelW, h = panelH,
                    whiteDeltaY = halfH, clipInset = 6,
                    anchorX = math.floor(panelW / 2) + offset,
                    anchorY = math.floor(panelH / 2) + offset,
                }
            end
        end
    end
    print("[TileSeamMatrixLayout] " .. cjson.encode({ version = 1, physicalW = physicalW,
        physicalH = physicalH, dpr = dpr, tileMetres = data.tile, gridCols = data.cols,
        gridRows = data.rows, originalBackgrounds = images, backgroundSeamX = seamX,
        backgroundSeamY = seamY, offsetConvention = "both X/Y in physical pixels; wall/background seam anchor",
        layout = "5 rows x 8 columns per half; black top / white bottom; original ppu=fullScreenH/viewH",
        cases = cases }))

    R.drawWorld = function()
        state.draws = state.draws + 1
        local vg = R.vg
        for pass = 0, 1 do
            nvgSave(vg)
            nvgShapeAntiAlias(vg, 0)
            rect(vg, 0, pass * halfH, screenW, halfH,
                pass == 0 and nvgRGBA(0, 0, 0, 255) or nvgRGBA(255, 255, 255, 255))
            nvgRestore(vg)
            for _, case in ipairs(cases) do
                nvgSave(vg)
                nvgTranslate(vg, case.x, case.y + pass * halfH)
                -- Positive control: 50%-alpha marker and untouched underlay in the
                -- 6px gutter prove corresponding black/white pixels really differ.
                nvgSave(vg)
                nvgShapeAntiAlias(vg, 0)
                rect(vg, 2, 2, 3, 3, nvgRGBA(200, 40, 160, 128))
                nvgRestore(vg)
                nvgIntersectScissor(vg, case.clipInset, case.clipInset,
                    case.w - case.clipInset * 2, case.h - case.clipInset * 2)
                local cx = case.kind == "walls" and data.tile * 4 or seamX
                local cy = case.kind == "walls" and -data.tile * 4 or seamY
                ---@type TilesetProjection
                local projection = { screenW = case.w, screenH = case.h, ppu = case.ppu,
                    camX = cx + (case.w / 2 - case.anchorX) / case.ppu,
                    camY = cy + (case.anchorY - case.h / 2) / case.ppu }
                if case.kind == "walls" then
                    local count = TS.drawLayer(vg, "ground", data, projection, case.mode == "editor")
                    state.wallMinCount = math.min(state.wallMinCount, count)
                else
                    local ok, err = Backgrounds.draw(vg, images, projection)
                    if not ok then
                        state.backgroundsOK = false
                        state.firstError = state.firstError ~= "" and state.firstError or tostring(err)
                    end
                end
                nvgRestore(vg)
            end
        end
        if state.draws == 100 and not state.emitted then
            state.emitted = true
            print("[TileSeamMatrixRender] " .. cjson.encode(state))
        end
    end
end)

V.atFrame(124, function()
    local status, err = TS.status("industrial_walls", R.vg)
    V.assert(status == "ready" and err == nil, "wall atlas actually ready in world vg")
    local ready, backgroundError = Backgrounds.init(R.vg)
    V.assert(ready and backgroundError == nil, "original background image actually loaded with default filtering")
    V.assert(state.draws >= 100, "controlled real render callback ran at least 100 times")
    V.assert(state.wallMinCount > 0, "all clipped wall panels rendered real atlas tiles")
    V.assert(state.backgroundsOK, "all background 2/3 panels drawn successfully: " .. state.firstError)
    V.assert(GS.mode == "paused" and not P.node.parent.updateEnabled, "world remains paused with physics update disabled")
    print("[TileSeamMatrixFinal] " .. cjson.encode(state))
end)
