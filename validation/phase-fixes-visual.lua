-- 固态撞击真实渲染验收：在冻结场景中显示一个受控进度，不写玩家存档。
local GS = require "core.state"
local P = require "core.player"
local E = require "core.enemies"
local H = require "core.hazards"
local R = require "core.render"
local C = require "core.combat_fx"
local HUD = require "ui.hud"
local Config = require "config"
local PROGRESS = 0.15

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    E.clear()
    H.clear()
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    P.node.parent.updateEnabled = false
    P.setForm("solid", true)
    P.node:SetPosition2D(3, 2)
    P.body.linearVelocity = Vector2(7, 0)
    P.ramming = true
    P.onGround = true
    P.invuln = 0
    local e = E.spawn(P.node.parent, "cleaner01", 3.65, 2)
    e.atkTimer = 2
    E.update(0.016)
    V.assert(#C.ramImpacts == 1 and e.hp == e.maxHp - Config.PLAYER.ramDamage,
        "真实固态撞击触发一次特效")
    C.update(PROGRESS * 0.32)
    P.body.linearVelocity = Vector2(0, 0)
    R.camX, R.camY = 3.5, 3.4
    R.shakeTime, R.shakeMag, R.flashTime = 0, 0, 0
end)
