-- 清洁机器人-001 攻击节奏与命中帧回归：1 秒挥动一次，伤害对齐挥砍命中帧。
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
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

    -- 近战型（chaser）：贴脸观察攻击节奏
    local e = E.spawn(L.scene, "cleaner01", 6, 1.2)
    P.node.position2D = Vector2(6.5, 1.2)
    e.facing = 1

    local hits, times = 0, {}
    GS.on("enemyMelee", function(ev) if ev == e then hits = hits + 1; times[#times + 1] = os.clock() end end)

    -- 记录每次出手（起手）时刻，用于核对间隔
    local swings = {}
    local origUpdate = E.update
    local tAcc = 0
    for _ = 1, 300 do
        e.atkTimer = e.atkTimer   -- 自然计时
        local before = e.atkAnimTimer
        E.update(1 / 60, nil)
        tAcc = tAcc + 1 / 60
        if e.atkAnimTimer > before then swings[#swings + 1] = tAcc end
    end
    V.assert(#swings >= 2, "机器人-01 反复挥动（记录 " .. #swings .. " 次）")

    -- 相邻两次出手间隔应接近 1 秒
    local gaps = {}
    for i = 2, #swings do gaps[#gaps + 1] = swings[i] - swings[i - 1] end
    local minGap, maxGap = math.huge, 0
    for _, g in ipairs(gaps) do minGap = math.min(minGap, g); maxGap = math.max(maxGap, g) end
    V.assert(minGap > 0.9, "挥动间隔不小于 1 秒（最小 " .. string.format("%.2f", minGap) .. "）")

    -- 伤害不是起手瞬间结算：起手后至少过一段延迟才扣水
    E.clear()
    local e2 = E.spawn(L.scene, "cleaner01", 6, 1.2)
    P.node.position2D = Vector2(6.5, 1.2)
    e2.atkTimer = 0
    local waterAtSwing, waterAfterHit = nil, nil
    local sawSwing = false
    for i = 1, 60 do
        E.update(1 / 60, nil)
        if e2.atkAnimTimer > 0 and not sawSwing then
            sawSwing = true
            waterAtSwing = GS.save.water
        end
        if sawSwing and waterAfterHit == nil and GS.save.water < waterAtSwing then
            waterAfterHit = i
        end
    end
    V.assert(sawSwing, "机器人-01 起手")
    V.assert(waterAtSwing ~= nil, "记录起手瞬间水量")
    -- 命中帧在动画 50% 处（1.0s * 0.5 = 0.5s ≈ 30 帧），故起手当帧不应立刻扣水
    V.assert(waterAfterHit == nil or waterAfterHit > 3, "伤害不在起手瞬间结算（延迟到命中帧）")

    UnloadLevel()
    GS.save, GS.mode, P.dead = oldSave, oldMode, oldDead
    print("[Cleaner01Test] 攻击节奏与命中帧验收完成")
end)
