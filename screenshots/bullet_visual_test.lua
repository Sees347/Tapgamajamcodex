-- 仅供离屏验收，冻结四种玩家弹丸和命中动画的采样时间，不写存档。
local GS = require "core/state"
local P = require "core/player"
local B = require "core/bullets"
local E = require "core/enemies"
local H = require "core/hazards"
local R = require "core/render"
local HUD = require "ui/hud"
local UI = require "urhox-libs/UI"
local Art = require "core/art"

V.atFrame(12, function()
    GS.save = GS.defaultSave()
    LoadLevel("testmap", nil)
    HUD.hideOverlay()
    E.clear()
    H.clear()
    P.node.position = Vector3(10, 3, 0)
    P.body.linearVelocity = Vector2(0, 0)
    R.setCamera(10, 3)
    GS.mode = "paused"
    UI.SetRoot(UI.Panel {width = "100%", height = "100%", pointerEvents = "none"})
    B.clear()
    local specs = {
        {key = "bullet_water", x = 7, y = 4.5, dx = 1, dy = 0, time = 0.1},
        {key = "bullet_electric", x = 10, y = 4.5, dx = 1, dy = 0, time = 0.12},
        {key = "bullet_ice", x = 13, y = 4.5, dx = -1, dy = 0, time = 0.08},
        {key = "bullet_lightning", x = 7, y = 2, dx = 0, dy = -1, time = 0.02},
        {key = "bullet_water", x = 10, y = 2, dx = -1, dy = 0, time = 0.15},
        {key = "bullet_ice", x = 13, y = 2, dx = 0.7, dy = 0.7, time = 0.14},
    }
    for _, s in ipairs(specs) do
        local b = B.spawn({x=s.x, y=s.y, dx=s.dx, dy=s.dy, artKey=s.key, isIce=s.key=="bullet_ice"})
        b.animTime = s.time
    end
    R.bulletImpacts = {{x=11.5, y=0.5, time=0.2, duration=Art.duration("bullet_ice_hit")}}
end)
V.atFrame(130, function()
    for _, b in ipairs(B.list) do
        b.animTime = b.artKey == "bullet_lightning" and 0.05 or 0.18
    end
    R.bulletImpacts[1].time = 0.32
end)
V.atFrame(150, function()
    for _, b in ipairs(B.list) do
        b.animTime = b.artKey == "bullet_lightning" and 0.08 or 0.24
    end
    R.bulletImpacts[1].time = 0.46
end)
V.atFrame(110, function()
    for _, b in ipairs(B.list) do
        V.assert(b.artKey ~= nil, "验收弹丸有动画配置")
    end
end)
