-- 同一新限位相机、同一共享出生点/尺寸，强制旧逐格墙绘制，仅用于图像前后比较。
local T = require "core.terrain_tiles"
local oldSupports = T.supports
T.supports = function() return false end
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
    V.assert(math.abs(R.camY + 184) < 1e-9, "前后图固定同一限位后的相机中心")
end)
V.atFrame(124, function() T.supports = oldSupports end)
