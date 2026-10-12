-- 只读共享地图渲染基线：内存进度、冻结场景，不写地图或玩家存档。
local GS = require "core.state"
local P = require "core.player"
local R = require "core.render"
local L = require "core.level"
local HUD = require "ui.hud"
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("world", nil)
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    P.node.parent.updateEnabled = false
    R.camX, R.camY = 16.0111111111, -185.7
    R.shakeTime, R.shakeMag, R.flashTime = 0, 0, 0
    print(string.format("[TileSeamBaseline] spawn=(%.3f,%.3f) viewH=%.3f ppu=%.3f cols=%d rows=%d",
        R.camX, R.camY, R.viewH, R.ppu, L.def.tilemapData.cols, L.def.tilemapData.rows))
end)
