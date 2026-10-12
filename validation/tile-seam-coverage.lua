-- 成对底色检测：不透明内部墙面若正确覆盖，黑/白底上的对应像素必须相同。
local GS = require "core.state"
local P = require "core.player"
local R = require "core.render"
local TS = require "core.tilesets"
local HUD = require "ui.hud"
local cells = {}
for row = 1, 3 do
    for col = 1, 4 do
        cells[string.format("%d:%d", col, row)] = { tilesetId = "industrial_walls", tileId = 1, collider = "ground" }
    end
end
local data = { tile = 1, originX = 0, originY = 0, cols = 4, rows = 3,
    visualLayers = { ground = { cells = cells } } }
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    LoadLevel("world", nil)
    P.node.parent.updateEnabled = false
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    R.drawWorld = function()
        local vg = R.vg
        for pass = 0, 1 do
            nvgBeginPath(vg)
            nvgRect(vg, 0, pass * 400, R.screenW, 400)
            nvgFillColor(vg, pass == 0 and nvgRGBA(0, 0, 0, 255) or nvgRGBA(255, 255, 255, 255))
            nvgFill(vg)
            for index = 0, 3 do
                local x, y = 50 + index * 400 + index * 0.25, 100 + pass * 400 + index * 0.25
                TS.drawLayer(vg, "ground", data, { screenW = R.screenW, screenH = R.screenH,
                    camX = (R.screenW / 2 - x) / 67.5, camY = (y - R.screenH / 2) / 67.5, ppu = 67.5 })
            end
        end
    end
end)
