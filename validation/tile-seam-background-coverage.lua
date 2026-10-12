-- 黑/白底上的背景共边覆盖测试，区分素材色差与抗锯齿漏底。
local GS = require "core.state"
local P = require "core.player"
local R = require "core.render"
local L = require "core.level"
local B = require "core.map_backgrounds"
local HUD = require "ui.hud"
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
            for index = 0, 3 do
                nvgSave(vg)
                nvgTranslate(vg, index * 460, pass * 400)
                nvgBeginPath(vg)
                nvgRect(vg, 0, 0, 460, 400)
                nvgFillColor(vg, pass == 0 and nvgRGBA(0, 0, 0, 255) or nvgRGBA(255, 255, 255, 255))
                nvgFill(vg)
                B.draw(vg, L.def.tilemapData.backgroundImages, { screenW = 460, screenH = 400,
                    camX = 121.085489391457 - index * 0.25 / 67.5, camY = -178.85, ppu = 67.5 })
                nvgRestore(vg)
            end
        end
    end
end)
