-- 优化前真实共享地图：冻结物理与HUD，保留旧视野/出生相机作为前后对照。
local GS = require "core.state"
local P = require "core.player"
local R = require "core.render"
local L = require "core.level"
local HUD = require "ui.hud"
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    LoadLevel("world", nil)
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    P.node.parent.updateEnabled = false
    R.shakeTime, R.flashTime = 0, 0
    print(string.format("[MapOptimization] physicsRects=%d camera=(%.5f,%.5f) view=(%.5f,%.5f)",
        #L.platformRects, R.camX, R.camY, R.viewW, R.viewH))
end)
