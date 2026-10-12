-- 趋光菌兽回归：图集配置 + 文档需求（靠近光源 / 受击追击 / 扑咬2次）。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local MON = require "data/monsters"
local Config = require "config"

V.atFrame(20, function()
    local oldSave, oldMode, oldDead = GS.save, GS.mode, P.dead
    local oldLight = GS.lightSources
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    E.clear()
    H.clear()
    GS.mode = "playing"
    P.dead = false

    -- 图集配置
    for _, k in ipairs({ "enemy_lightseeker_idle", "enemy_lightseeker_move", "enemy_lightseeker_attack" }) do
        V.assert(clips[k] ~= nil and clips[k].count == 8, k .. " 配置 8 帧")
        V.assert(cache:Exists(clips[k].path), k .. " 图集文件存在")
    end
    V.assert(MON.lightBeast.atkAnimTime == 0.6, "趋光菌兽攻击动画时长为 0.6s")

    -- 文档：未交战时向感知范围内的光源靠近
    P.node.position2D = Vector2(2, 1.2)
    local e = E.spawn(L.scene, "lightBeast", 10, 1.2)
    e.aggro = false
    GS.lightSources = { { x = 5, y = 1.2 } }
    for _ = 1, 60 do E.update(1 / 60, nil) end
    V.assert(e.state == "seek", "未交战时进入寻光状态")
    V.assert(e.body.linearVelocity.x < 0, "速度朝光源方向（光源在左侧）")

    -- 文档：受到攻击后优先追击玩家
    e.aggro = true
    e.attractTimer = 0
    P.node.position2D = Vector2(14, 1.2)
    for _ = 1, 30 do E.update(1 / 60, nil) end
    V.assert(e.state == "chase", "受击后转入追击状态")
    V.assert(e.body.linearVelocity.x > 0, "速度朝玩家方向（玩家在右侧）")

    -- 文档：接近后进行短距离扑咬 2 次
    P.node.position2D = Vector2(e.node.position2D.x + 1.0, 1.2)
    local bites, hits = 0, 0
    GS.on("enemyMelee", function(ev) if ev == e then hits = hits + 1 end end)
    local seen = 0
    for _ = 1, 240 do
        local before = e.bites
        P.node.position2D = Vector2(e.node.position2D.x + 1.0, 1.2)
        E.update(1 / 60, nil)
        if e.bites ~= before then seen = seen + 1 end
    end
    V.assert(hits >= 2, "接近后确实咬中（" .. hits .. " 次）")

    -- 伤害不在起手瞬间结算
    E.clear()
    local e2 = E.spawn(L.scene, "lightBeast", 10, 1.2)
    e2.aggro = true
    P.node.position2D = Vector2(11.0, 1.2)
    local waterAtSwing, hitFrame = nil, nil
    local sawSwing = false
    for i = 1, 120 do
        E.update(1 / 60, nil)
        if e2.atkAnimTimer > 0 and not sawSwing then sawSwing = true; waterAtSwing = GS.save.water end
        if sawSwing and hitFrame == nil and GS.save.water < (waterAtSwing or 0) then hitFrame = i end
    end
    V.assert(sawSwing, "趋光菌兽起手")
    V.assert(hitFrame == nil or hitFrame > 3, "扑咬伤害不在起手瞬间结算（延迟到咬中帧）")

    GS.lightSources = oldLight
    UnloadLevel()
    GS.save, GS.mode, P.dead = oldSave, oldMode, oldDead
    print("[LightSeekerTest] 图集与文档需求验收完成")
end)
