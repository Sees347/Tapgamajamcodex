-- 喷孢菌攻击动画实机渲染：强制敌人进入 attack 状态，按受控进度截帧。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"
local Config = require "config"
local SAMPLE = 2
local ready = false

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    local e = E.spawn(L.scene, "spore", 6, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    P.node.position2D = Vector2(2, 1.2)
    GS.mode = "paused"
    -- 冻结在攻击动画的受控进度：stateTimer 从 0.25 递减
    e.state = "attack"
    e.atkAnimTimer = E.attackAnimTime(e.def) * (1 - SAMPLE / 4)
    e.hitSquash = 0
end)
V.atFrame(45, function() ready = true end)
V.atFrame(60, function()
    local e = E.list[1]
    V.assert(e.atkAnimTimer > 0, "攻击计时器在有效范围")
    V.assert(e.atkAnimTimer <= Config.HIT_FX.attackAnimTime, "攻击计时器不超过总时长")
end)
