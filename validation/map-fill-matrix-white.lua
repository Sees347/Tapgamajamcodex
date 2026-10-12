-- 同位置黑白底检测：真实原瓦片+连续内填充，边界格共边/4格宏块共边都不得漏底。
local R = require "core.render"
local TS = require "core.tilesets"
local GS = require "core.state"
local P = require "core.player"
local HUD = require "ui.hud"
local UNDERLAY = 255
local cells = {}
for r = 1, 8 do for c = 1, 8 do cells[string.format("%d:%d", c, r)] = { tilesetId = "industrial_walls", tileId = 1, collider = "ground" } end end
local data = { cols = 8, rows = 8, tile = 1, originX = 0, originY = 0, visualLayers = { ground = { cells = cells } } }
local views = { 8, 16, 26, 4, 80 }
local offsets = { 0, 0.25, 0.5, 0.75 }
local draws = 0
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    LoadLevel("world")
    P.node.parent.updateEnabled = false
    GS.setMode("paused")
    HUD.hideOverlay(); HUD.setGameHudVisible(false)
    local w, h = R.screenW, R.screenH
    local pw, ph = math.floor(w / 8), math.floor(h / 5)
    print(string.format("[MapFillMatrix] w=%d h=%d panelW=%d panelH=%d", w, h, pw, ph))
    R.drawWorld = function()
        draws = draws + 1
        local vg = R.vg
        nvgSave(vg); nvgShapeAntiAlias(vg, 0)
        nvgBeginPath(vg); nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(UNDERLAY, UNDERLAY, UNDERLAY, 255)); nvgFill(vg)
        for ri, view in ipairs(views) do
            for oi, offset in ipairs(offsets) do
                for subject = 1, 2 do
                    local x, y = ((oi - 1) * 2 + subject - 1) * pw, (ri - 1) * ph
                    local ppu = h / view
                    local anchorX, anchorY = math.floor(pw / 2) + offset, math.floor(ph / 2) + offset
                    local seamX = subject == 1 and 1 or 4
                    local seamY = -4
                    nvgSave(vg); nvgTranslate(vg, x, y)
                    nvgBeginPath(vg); nvgRect(vg, 2, 2, 3, 3)
                    nvgFillColor(vg, nvgRGBA(200, 40, 160, 128)); nvgFill(vg)
                    nvgIntersectScissor(vg, 6, 6, pw - 12, ph - 12)
                    TS.drawLayer(vg, "ground", data, { screenW = pw, screenH = ph, ppu = ppu,
                        camX = seamX + (pw / 2 - anchorX) / ppu,
                        camY = seamY + (anchorY - ph / 2) / ppu }, ri >= 4)
                    nvgRestore(vg)
                end
            end
        end
        nvgRestore(vg)
    end
end)
V.atFrame(124, function()
    V.assert(draws >= 100, "受控渲染矩阵真实绘制至少100帧")
    V.assert(TS.lastLayerStats.ground and TS.lastLayerStats.ground.macroFills > 0, "矩阵启用真实跨格纹理而非旧逐格fallback")
end)
