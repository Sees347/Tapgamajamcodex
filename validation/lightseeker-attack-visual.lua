-- 趋光菌兽扑咬姿态世界内渲染：冻结在咬中帧截帧。
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
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
    local e = E.spawn(L.scene, "lightBeast", 6, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    P.node.position2D = Vector2(2, 1.2)
    GS.mode = "paused"
    e.facing = 1
    e.aggro = true
    e.hitSquash = 0
    e.state = "attack"
    -- 冻结在咬中帧（已播放 50%）
    e.atkAnimTimer = E.attackAnimTime(e.def) * 0.5
end)
