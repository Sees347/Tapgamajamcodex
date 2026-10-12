-- 剑鱼受控刀光采样：暂停冻结，实际 NanoVG 渲染，内存存档。
local Config = require "config"
local GS = require "core/state"
local P = require "core/player"
local A = require "core/abilities"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local R = require "core/render"
local Art = require "core/art"
local MeleeFX = require "core/melee_fx"
local HUD = require "ui/hud"
local SAMPLE = 3
local PROGRESS = 1.05
local FACING = 1

V.atFrame(30, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = { "swordfish" }
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    P.node.position2D = Vector2(8, 3)
    P.body.linearVelocity = Vector2(0, 0)
    P.body.gravityScale = 0
    P.form = SAMPLE == 5 and "solid" or "liquid"
    P.facing = SAMPLE == 5 and -1 or FACING
    P.invuln, P.hurtFlash, P.formFlash = 0, 0, 0
    R.particles = {}
    R.clearMeleeSlashes()
    Art.reset()
    R.camX, R.camY = 8, 3
    R.flashTime, R.shakeTime = 0, 0
    local ctx = { playerPos = Vector2(8, 3), aimWorld = Vector2(8 - P.facing * 4, 5), enemies = {} }
    local stage = SAMPLE < 4 and Config.LIQUID_MELEE.stages[SAMPLE] or nil
    if SAMPLE ~= 4 then A.meleeAttack(A.currentEffects(), ctx, stage, stage and SAMPLE or nil) end
    local duration = stage and stage.fxDuration or Art.duration("slash_swordfish")
    MeleeFX.update(SAMPLE == 5 and 0.085 or duration * PROGRESS)
    GS.mode = "paused"
    HUD.setHint(SAMPLE == 5 and "固态 · 朝左挥砍（原有节奏）" or SAMPLE == 4 and "液态 · 段间留白（无残留刀光）" or "液态 · 第 " .. SAMPLE .. " 段刀光")
end)

local drawn = 0
local original = Art.drawProjectile
Art.drawProjectile = function(vg, key, time, x, y, size, angle)
    if string.find(key, "slash_swordfish", 1, true) == 1 then
        local stage = Config.LIQUID_MELEE.stages[SAMPLE]
        local expectedKey = SAMPLE == 5 and "slash_swordfish" or stage.artKey
        local expectedTime = SAMPLE == 5 and 0.085 or PROGRESS * Art.duration(key)
        local actual = original(vg, key, time, x, y, size, angle)
        if drawn == 0 then
            V.assert(key == expectedKey, "真实渲染按3、4、2选择独立刀光，固态保留旧图集")
            V.assert(math.abs(time - expectedTime) < 0.00001, "刀光进度按当前段时长映射")
            V.assert(actual, "刀光图片成功绘制，不依赖弧线兜底")
        end
        drawn = drawn + 1
        return actual
    end
    return original(vg, key, time, x, y, size, angle)
end
V.atFrame(155, function()
    local empty = SAMPLE == 4 or SAMPLE < 4 and PROGRESS >= 1
    V.assert(empty and drawn == 0 or not empty and drawn > 0, "真实渲染刀光/段间留白状态正确")
end)
