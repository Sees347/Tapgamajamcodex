-- 辅助内填充解码失败时回退旧图，工业墙重试后恢复跨格绘制；测试结束恢复全局函数。
local TS = require "core.tilesets"
local R = require "core.render"
local P = require "core.player"
local GS = require "core.state"
local HUD = require "ui.hud"
local createImage = nvgCreateImage
local failFill = false
local failures = 0
V.atFrame(20, function()
    GS.save = GS.defaultSave(); LoadLevel("world")
    P.node.parent.updateEnabled = false
    GS.setMode("paused"); HUD.hideOverlay(); HUD.setGameHudVisible(false)
    R.shakeTime = 0
end)
V.atFrame(85, function()
    failFill = true
    nvgCreateImage = function(vg, path, flags)
        if failFill and path == "image/地图/tiles/industrial_wall_fill.png" then failures = failures + 1; return 0 end
        return createImage(vg, path, flags)
    end
    TS.releaseContext(R.vg)
end)
V.atFrame(90, function()
    local stats = TS.lastLayerStats.ground
    V.assert(failures == 1 and stats and stats.macroFills == 0 and stats.cells == stats.fills, "辅助解码失败缓存一次并安全回退原墙图")
    failFill = false
    nvgCreateImage = createImage
    V.assert(TS.retry("industrial_walls"), "墙图重试同时清除辅助内填充失败状态")
end)
V.atFrame(119, function()
    nvgCreateImage = createImage
    local stats = TS.lastLayerStats.ground
    V.assert(stats and stats.macroFills > 0 and stats.fills < stats.cells, "资源重试后真实恢复跨格绘制而非永久fallback")
end)
