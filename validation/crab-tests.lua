-- 裂钳蟹回归：图集配置、左右螯交替取子区间、石子弹幕贴图与命中图。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local B = require "core/bullets"
local MON = require "data/monsters"

-- 跨 atFrame 块共享（穿帮回归用）
local oldSave, oldMode, oldDead
local flickerEnemy, flickerOffsets, flickerRestore

V.atFrame(20, function()
    oldSave, oldMode, oldDead = GS.save, GS.mode, P.dead
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    E.clear()
    H.clear()
    GS.mode = "playing"
    P.dead = false

    -- 图集配置
    for _, k in ipairs({ "enemy_crab_move", "enemy_crab_melee", "enemy_crab_ranged",
                         "enemy_crab_stone_fly", "enemy_crab_stone_hit" }) do
        V.assert(clips[k] ~= nil, k .. " 配置存在")
        V.assert(cache:Exists(clips[k].path), k .. " 图集文件存在")
    end
    V.assert(clips.enemy_crab_melee.count == 4 and clips.enemy_crab_ranged.count == 4,
        "近战/远程各取 4 帧（单侧螯）")
    V.assert(clips.enemy_crab_stone_fly.frameOffset == 1, "石子飞行取第 2-3 帧")
    V.assert(clips.enemy_crab_stone_hit.frameOffset == 3, "石子命中取第 4 帧")
    V.assert(MON.crab.atkAnimTime == 0.28, "裂钳蟹攻击动画时长 0.28s")

    -- 远距离应触发抛石，且弹幕带石子贴图与命中图
    local e = E.spawn(L.scene, "crab", 6, 1.2)
    P.node.position2D = Vector2(10.2, 1.2)   -- 超出近战、在远程射程内
    e.facing = 1
    local spawned = {}
    local origSpawn = B.spawnEnemyBullet
    B.spawnEnemyBullet = function(x, y, dx, dy, sp, dm, col, g, el, artKey, hitKey)
        spawned[#spawned + 1] = { artKey = artKey, hitKey = hitKey }
        return origSpawn(x, y, dx, dy, sp, dm, col, g, el, artKey, hitKey)
    end
    local sawRanged = false
    for _ = 1, 240 do
        E.update(1 / 60, nil)
        if e.pendingAttack == "ranged" then sawRanged = true end
    end
    B.spawnEnemyBullet = origSpawn
    V.assert(sawRanged, "远距离触发远程抛石")
    V.assert(#spawned > 0, "抛出了石子弹幕")
    V.assert(spawned[1].artKey == "enemy_crab_stone_fly", "石子弹幕带飞行贴图")
    V.assert(spawned[1].hitKey == "enemy_crab_stone_hit", "石子弹幕带命中碎裂贴图")

    -- 左右螯交替：连续攻击应看到 clawSide 翻转
    E.clear()
    local e2 = E.spawn(L.scene, "crab", 6, 1.2)
    P.node.position2D = Vector2(10.2, 1.2)
    local sides = {}
    for _ = 1, 400 do
        E.update(1 / 60, nil)
        if e2.atkAnimTimer > 0 then
            local s = e2.clawSide
            if #sides == 0 or sides[#sides] ~= s then sides[#sides + 1] = s end
        end
    end
    V.assert(#sides >= 2 and sides[1] ~= sides[2], "左右螯交替出手（记录 " .. #sides .. " 次翻转）")

    -- 穿帮回归：一次攻击内左右螯子区间保持不变（不逐帧闪烁）。
    -- 依赖真实帧渲染：这里只装钩子并触发出手，断言在下面的 atFrame(140) 里做。
    E.clear()
    flickerEnemy = E.spawn(L.scene, "crab", 6, 1.2)
    P.node.position2D = Vector2(10.2, 1.2)
    flickerOffsets = {}
    local origDraw = Art.drawEnemy
    flickerRestore = function() Art.drawEnemy = origDraw end
    Art.drawEnemy = function(vg, key, tm, x, y, r, fc, off)
        if flickerEnemy and flickerEnemy.atkAnimTimer > 0
            and (key == "enemy_crab_melee" or key == "enemy_crab_ranged") then
            flickerOffsets[#flickerOffsets + 1] = off
        end
        return origDraw(vg, key, tm, x, y, r, fc, off)
    end
    flickerEnemy.atkTimer = 0
end)

V.atFrame(140, function()
    if flickerRestore then flickerRestore(); flickerRestore = nil end
    V.assert(#flickerOffsets >= 4, "攻击动画被实际绘制（记录 " .. #flickerOffsets .. " 帧）")
    local first = flickerOffsets[1]
    local same = true
    for _, o in ipairs(flickerOffsets) do if o ~= first then same = false end end
    V.assert(same, "一次攻击内左右螯子区间恒定，不闪烁穿帮")

    UnloadLevel()
    GS.save, GS.mode, P.dead = oldSave, oldMode, oldDead
    print("[CrabTest] 图集/交替/石子贴图验收完成")
end)
