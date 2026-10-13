-- 裂钳蟹近战 / 远程中帧世界内渲染，确认两种动作分别取正确图集。
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
    local a = E.spawn(L.scene, "crab", 3, 1.2)
    local b = E.spawn(L.scene, "crab", 6, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    P.node.position2D = Vector2(1, 1.2)
    GS.mode = "paused"
    -- 冻结在攻击中段：a 完整近战，b 右螯远程。
    a.facing = 1; a.hitSquash = 0; a.pendingAttack = "melee"
    a.clawSide = 1; a.atkAnimTimer = E.attackAnimTime(a.def, "melee") * 0.5
    b.facing = 1; b.hitSquash = 0; b.pendingAttack = "ranged"
    b.clawSide = -1; b.atkAnimTimer = E.attackAnimTime(b.def, "ranged") * 0.5
end)
