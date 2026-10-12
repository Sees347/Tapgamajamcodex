-- 清洁机器人-002 回归：1 秒一次、弹幕与挥臂出手帧同步、图集渲染。
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local B = require "core/bullets"
local Config = require "config"

V.atFrame(20, function()
    local oldSave, oldMode, oldDead = GS.save, GS.mode, P.dead
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    E.clear()
    H.clear()
    GS.mode = "playing"
    P.dead = false

    -- 站定射击：玩家进入射程后应反复出手
    local e = E.spawn(L.scene, "cleaner02", 6, 1.2)
    P.node.position2D = Vector2(8, 1.2)
    e.facing = 1
    V.assert(e.def.attacks[1].freq == 1.0, "攻击间隔为 1 秒")

    local swings, shots = {}, 0
    local tAcc = 0
    local origSpawn = B.spawnEnemyBullet
    B.spawnEnemyBullet = function(...) shots = shots + 1; return origSpawn(...) end
    for _ = 1, 300 do
        local before = e.atkAnimTimer
        E.update(1 / 60, nil)
        tAcc = tAcc + 1 / 60
        if e.atkAnimTimer > before then swings[#swings + 1] = tAcc end
    end
    B.spawnEnemyBullet = origSpawn
    V.assert(#swings >= 2, "机器人-02 反复挥臂（" .. #swings .. " 次）")
    local gaps = {}
    for i = 2, #swings do gaps[#gaps + 1] = swings[i] - swings[i - 1] end
    local minGap = math.huge
    for _, g in ipairs(gaps) do minGap = math.min(minGap, g) end
    V.assert(minGap > 0.9, "挥臂间隔不小于 1 秒（最小 " .. string.format("%.2f", minGap) .. "）")
    V.assert(shots >= 2, "确实发射了弹幕（" .. shots .. " 发）")

    -- 弹幕不是起手瞬间发射：起手当帧不应立刻出弹
    E.clear()
    local e2 = E.spawn(L.scene, "cleaner02", 6, 1.2)
    P.node.position2D = Vector2(8, 1.2)
    e2.facing = 1
    local bulletsAtSwing, firedFrame = nil, nil
    local sawSwing = false
    local shotCount = 0
    B.spawnEnemyBullet = function(...) shotCount = shotCount + 1; return origSpawn(...) end
    for i = 1, 90 do
        local beforeShots = shotCount
        E.update(1 / 60, nil)
        if e2.atkAnimTimer > 0 and not sawSwing then sawSwing = true; bulletsAtSwing = shotCount end
        if sawSwing and firedFrame == nil and shotCount > bulletsAtSwing then firedFrame = i end
    end
    B.spawnEnemyBullet = origSpawn
    V.assert(sawSwing, "机器人-02 起手")
    V.assert(firedFrame == nil or firedFrame > 3, "弹幕不在起手瞬间发射（延迟到出手帧）")

    UnloadLevel()
    GS.save, GS.mode, P.dead = oldSave, oldMode, oldDead
    print("[Cleaner02Test] 节奏与挥臂同步验收完成")
end)
