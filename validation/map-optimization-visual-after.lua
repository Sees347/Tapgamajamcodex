-- 真实运行的跨格绘制数量、视口边界和原资源解码验收。
local GS = require "core.state"
local P = require "core.player"
local R = require "core.render"
local L = require "core.level"
local TS = require "core.tilesets"
local C = require "core.camera_bounds"
local HUD = require "ui.hud"
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    LoadLevel("world", nil)
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    P.node.parent.updateEnabled = false
    R.shakeTime, R.flashTime = 0, 0
    local bounds = C.fromLevel(L.def)
    V.assert(bounds.minX == 0 and bounds.maxX == 300 and bounds.minY == -192 and bounds.maxY == 8, "相机边界取精确300×200米网格")
    V.assert(#L.platformRects == 91 and #L.crateNodes == 91, "真实场景91合并地形盒和91独立箱体")
    V.assert(math.abs(R.camY + 184) < 1e-9 and math.abs(R.viewH - 16) < 1e-9, "出生首帧有效16米视野不越底边")
end)
V.atFrame(119, function()
    local stats = TS.lastLayerStats.ground
    V.assert(stats and stats.cells > 0 and stats.macroFills > 0 and stats.fills < stats.cells, "真实绘制使用跨格组而非逐格fallback")
    if stats then print(string.format("[MapOptimizationDraw] visibleCells=%d fills=%d macroFills=%d", stats.cells, stats.fills, stats.macroFills)) end
    local b = C.fromLevel(L.def)
    V.assert(R.camX - R.viewW / 2 >= b.minX - 1e-9 and R.camX + R.viewW / 2 <= b.maxX + 1e-9
        and R.camY - R.viewH / 2 >= b.minY - 1e-9 and R.camY + R.viewH / 2 <= b.maxY + 1e-9, "最终截图完整视口位于地图范围")
end)
