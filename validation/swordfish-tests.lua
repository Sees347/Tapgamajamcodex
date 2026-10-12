-- 剑鱼专项回归：内存上下文，不写存档，不进入发行包。
local Config = require "config"
local GS = require "core/state"
local P = require "core/player"
local A = require "core/abilities"
local FISH = require "data/fish"
local clips = require "data/art"

local attacks = {}
GS.on("playerMelee", function(x, y, ax, ay, range, stage, index)
    attacks[#attacks + 1] = { ax = ax, ay = ay, range = range, stage = stage, index = index }
end)

V.atFrame(10, function()
    local oldSave, oldMode = GS.save, GS.mode
    local oldForm, oldFacing, oldLock, oldDead = P.form, P.facing, P.swingLock, P.dead
    local oldCooldowns = A.cooldowns
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = { "swordfish" }
    GS.mode = "playing"
    P.dead = false
    local hits = {}
    local bullets = {}
    local ctx = {
        playerPos = Vector2(0, 0), aimWorld = Vector2(-8, 8),
        spawnBullet = function(o) bullets[#bullets + 1] = o; return o end,
        meleeHit = function(e) hits[e.id] = (hits[e.id] or 0) + 1 end,
        enemies = {},
    }
    local function reset(form)
        P.form = form or "liquid"
        A.resetLiquidMelee()
        A.cooldowns = {}
        A.fireRequest = false
        attacks, hits, bullets = {}, {}, {}
    end
    local function tick(dt, held)
        A.fireRequest = held or false
        A.update(dt, ctx)
    end
    local function click()
        A.requestAttack()
        A.update(0, ctx)
    end
    local function enemy(id, x, y)
        return { id = id, radius = 0.2, dead = false, node = { position2D = Vector2(x, y) } }
    end

    for _, form in ipairs({ "liquid", "solid" }) do
        for _, facing in ipairs({ -1, 1 }) do
            reset(form)
            P.facing = facing
            ctx.aimWorld = Vector2(-facing * 8, 8)
            local range = FISH.swordfish[form].range
            ctx.enemies = {
                enemy("front", facing, 0), enemy("diagonal", facing, 1),
                enemy("back", -facing, 0), enemy("nearBack", -facing * 0.000001, 0),
                enemy("center", 0, 0), enemy("above", 0, 1),
                enemy("outsideCone", facing * 0.1, 1),
                enemy("edge", facing * (range + 0.2), 0),
                enemy("tooFar", facing * (range + 0.201), 0),
            }
            click()
            local label = form .. "/" .. facing
            V.assert(#attacks == 1 and attacks[1].ax == facing and attacks[1].ay == 0, label .. " 攻击轴只认角色朝向，不跟鼠标")
            V.assert(hits.front == 1 and hits.diagonal == 1 and hits.edge == 1, label .. " 前方扇形和射程边界命中")
            V.assert(not hits.back and not hits.nearBack and not hits.center and not hits.above, label .. " 背后、重叠中心、垂直中心线不命中")
            V.assert(not hits.outsideCone and not hits.tooFar, label .. " 扇形外和射程外不命中")
        end
    end
    ctx.enemies = {}
    P.facing = 1
    reset()
    click()
    V.assert(attacks[1].index == 1 and P.swingLock == 0.14, "第一次点按立即开始第一段")
    for i = 1, 100 do tick(0.01, true) end
    V.assert(#attacks == 1, "长按一秒不会自动挥砍或自动连段")
    click()
    V.assert(attacks[2].index == 1, "续段超时后重新从第一段开始")

    reset()
    click()
    local interval1 = A.liquidRecovery
    tick(0.03)
    click()
    click()
    V.assert(#attacks == 1 and A.liquidBuffered, "快速点击只缓冲下一刀，不能立即叠刀")
    tick(interval1 - 0.031)
    V.assert(#attacks == 1, "收招完成前不允许提前出第二段")
    tick(0.002)
    V.assert(#attacks == 2 and attacks[2].index == 2 and not A.liquidBuffered, "收招后消费一次缓冲并进入第二段")
    local interval2 = A.liquidRecovery
    for i = 1, 45 do tick(0.01, true) end
    V.assert(#attacks == 2, "同一段内多次过快点击不会预排第三刀")
    click()
    V.assert(#attacks == 3 and attacks[3].index == 3, "续按第三段")
    local interval3 = A.liquidRecovery
    V.assert(interval2 > interval1 and interval3 > interval2, "液态节奏逐段变化，第三段收招更长")
    local expectedKeys = { "slash_swordfish_003_3", "slash_swordfish_003_4", "slash_swordfish_003_2" }
    for i, attack in ipairs(attacks) do
        local stage = attack.stage
        V.assert(stage == Config.LIQUID_MELEE.stages[i], "第 " .. i .. " 段传递独立特效参数")
        V.assert(stage.artKey == expectedKeys[i], "第 " .. i .. " 段按刀光003的3、4、2选图")
        local clip = clips[stage.artKey]
        V.assert(clip.singleImage and clip.count == 1 and cache:Exists(clip.path), "第 " .. i .. " 段独立图片已打包，不按旧图集切格")
        local interval = math.max(FISH.swordfish.liquid.freq * stage.intervalMul, stage.fxDuration + 0.10)
        V.assert(interval - stage.fxDuration >= 0.09999, "第 " .. i .. " 段刀光播完后至少有 0.10 秒留白")
    end
    V.assert(attacks[2].stage.flipY and attacks[3].stage.sizeMul > attacks[1].stage.sizeMul, "第二段反向切斩，第三段刀光更大")
    click()
    tick(interval3 + 0.001)
    V.assert(#attacks == 4 and attacks[4].index == 1, "三段结束后下一点击回到第一段")

    reset()
    click()
    tick(0.40)
    click()
    V.assert(#attacks == 2 and attacks[2].index == 2, "恢复后续段窗口内的点击仍接第二段")
    reset()
    click()
    click()
    P.facing = -1
    tick(0.36)
    V.assert(attacks[2].ax == -1, "缓冲刀在实际出手时读取新朝向")

    reset()
    local down = VariantMap()
    down["Button"] = MOUSEB_LEFT
    HandleMouseDown("MouseButtonDown", down)
    local up = VariantMap()
    up["Button"] = MOUSEB_LEFT
    HandleMouseUp("MouseButtonUp", up)
    V.assert(A.attackPressed, "完整按下松开事件在时停未更新期间保留点击")
    A.update(0, ctx)
    for i = 1, 40 do tick(0.01, true) end
    V.assert(#attacks == 1, "PC 事件与长按轮询不重复生成第二段")

    for _, event in ipairs({ "formChanged", "fishChanged", "playerDied" }) do
        reset()
        click()
        click()
        if event == "formChanged" then
            P.form = "solid"
            GS.emit(event, "solid", "liquid")
        else
            GS.emit(event)
        end
        V.assert(A.liquidStage == 0 and not A.liquidBuffered and not A.attackPressed, event .. " 清空段号和缓冲")
        if event == "playerDied" then V.assert(P.swingLock == 0, "死亡时释放挥刀僵直，不带入复活") end
    end
    reset()
    click()
    click()
    GS.setMode("paused")
    V.assert(A.liquidStage == 0 and not A.fireRequest and A.liquidRecovery > 0, "暂停取消续段但保留剩余收招")
    GS.mode = "playing"
    click()
    V.assert(#attacks == 1 and A.liquidBuffered, "恢复后立即点击不能绕过液态收招")
    tick(0.36)
    V.assert(#attacks == 2 and attacks[2].index == 1, "恢复后收招结束再从第一段开始")
    reset()
    click()
    click()
    P.form = "solid"
    tick(0.1)
    V.assert(A.liquidStage == 0 and not A.liquidBuffered, "形态变化无事件时也清空液态缓冲")
    reset()
    click()
    click()
    GS.save.equipped = {}
    tick(0.1)
    V.assert(A.liquidStage == 0 and not A.liquidBuffered, "卸下剑鱼后也不会留下液态连段")
    GS.save.equipped = { "swordfish" }
    reset()
    click()
    click()
    P.dead = true
    tick(1)
    V.assert(#attacks == 1 and not A.liquidBuffered, "死亡后不补发缓冲刀")
    P.dead = false

    reset("solid")
    click()
    V.assert(attacks[1].stage == nil and P.swingLock == Config.MELEE_FX.swingLock, "固态不套用液态段落和僵直")
    V.assert(A.cooldowns.__melee__ == 0.6 and A.meleeDmg == 12, "固态频率和伤害保持原值")
    for i = 1, 80 do tick(0.01, true) end
    V.assert(#attacks == 2 and attacks[2].stage == nil, "固态仍可长按按原冷却连续攻击")

    reset()
    GS.save.equipped = { "swordfish", "archerfish" }
    click()
    for i = 1, 110 do tick(0.01, true) end
    V.assert(#attacks == 1 and #bullets >= 3 and bullets[1].dx < 0, "剑鱼点按不改变组合鱼长按射击和鼠标瞄准")
    -- 钩爪改由右键触发后，左键不再被钩爪抑制：近战与远程弹照常出手。
    GS.save.equipped = { "swordfish", "frog" }
    reset()
    click()
    V.assert(#attacks == 1, "青蛙钩爪改到右键后，左键近战不再被抑制")
    GS.save.equipped = { "swordfish", "frog", "archerfish" }
    reset()
    click()
    V.assert(#attacks == 1 and #bullets >= 1, "青蛙+剑鱼+射水鱼：左键同时出近战与远程弹")
    GS.save.equipped = { "swordfish" }
    reset("gas")
    click()
    V.assert(#attacks == 0 and #bullets == 3, "剑鱼气态三连弹幕不受影响")

    UnloadLevel()
    A.resetLiquidMelee()
    A.fireRequest = false
    A.cooldowns = oldCooldowns
    GS.save, GS.mode = oldSave, oldMode
    P.form, P.facing, P.swingLock, P.dead = oldForm, oldFacing, oldLock, oldDead
    print("[SwordfishTest] 剑鱼朝向、连段、输入和固态回归验收完成")
end)
