-- 清洁机器人-001 攻击姿态世界内渲染：冻结在攻击动画中段截帧。
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local Config = require "config"
local HUD = require "ui/hud"

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    local e = E.spawn(L.scene, "cleaner01", 6, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    P.node.position2D = Vector2(2, 1.2)
    GS.mode = "paused"
    e.facing = 1
    e.state = "chase"
    e.hitSquash = 0
    -- 冻结在攻击动画中段：计时器 = 总时长的一半
    e.atkAnimTimer = E.attackAnimTime(e.def) * 0.5
end)
