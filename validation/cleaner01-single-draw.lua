-- 残影回归：任意一帧里，清洁机器人-001 只应画出一套动画（不会同时画移动+攻击）。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"

local cur = {}
local everMove, everAttack, bothSameFrame = false, false, false
local orig = Art.drawEnemy
Art.drawEnemy = function(vg, key, ...)
    if key == "enemy_cleaner01_move" then cur.move = true; everMove = true end
    if key == "enemy_cleaner01_attack" then cur.attack = true; everAttack = true end
    return orig(vg, key, ...)
end

local active = false
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    local e = E.spawn(L.scene, "cleaner01", 4, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    P.node.position2D = Vector2(2, 1.2)
    GS.mode = "paused"
    e.facing = 1
    e.state = "chase"
    e.hitSquash = 0
    e.atkAnimTimer = 0
end)
V.atFrame(40, function() active = true end)
V.atFrame(55, function() local e = E.list[1]; if e then e.atkAnimTimer = E.attackAnimTime(e.def) * 0.5 end end)

SubscribeToEvent("NanoVGRender", function()
    if not active then return end
    -- 检查刚过去这一帧是否同时画了两套动画（残影）
    if cur.move and cur.attack then bothSameFrame = true end
    cur = {}
end)

V.atFrame(75, function()
    Art.drawEnemy = orig
    V.assert(everMove, "追击阶段确实画出了移动动画")
    V.assert(everAttack, "攻击阶段确实画出了攻击动画")
    V.assert(not bothSameFrame, "不存在同一帧叠加两套动画的残影")
    print("[SingleDraw] 残影回归通过")
end)
