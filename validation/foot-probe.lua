-- 液态脚底浮空测量：待机落稳后输出节点高度、地面表面与视觉脚线。
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"
local Config = require "config"

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    -- 放到已知平台上空，让其自然落稳（testmap 出生平台附近）
    P.node.position2D = Vector2(8, 3)
    P.body.linearVelocity = Vector2(0, 0)
    GS.mode = "playing"
    P.dead = false
end)

V.atFrame(120, function()
    GS.mode = "paused"
    local pp = P.node.position2D
    local r = Config.FORMS.liquid.radius
    -- 向下扫描地面表面
    local surface = nil
    local y = pp.y - r + 0.05
    while y > pp.y - r - 2 do
        if L.isSolid(pp.x, y) then surface = y; break end
        y = y - 0.02
    end
    local footIdle = pp.y - 0.9969 * r      -- idle 锚点的视觉脚线
    local footMove = pp.y - 0.8868 * r      -- move 锚点的视觉脚线
    print(string.format("[FootProbe] node.y=%.4f surface=%s r=%.2f", pp.y,
        surface and string.format("%.4f", surface) or "nil", r))
    if surface then
        print(string.format("[FootProbe] 物理底(node.y-r)=%.4f  距表面=%.4f", pp.y - r, (pp.y - r) - surface))
        print(string.format("[FootProbe] idle脚线=%.4f 距表面=%.4f | move脚线=%.4f 距表面=%.4f",
            footIdle, footIdle - surface, footMove, footMove - surface))
    end
    V.assert(surface ~= nil, "脚下找到地面")
end)
