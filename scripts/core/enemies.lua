-- ============================================================================
-- core/enemies.lua - 怪物 AI 系统
-- AI 行为: chaser(清洁01) / shooter(清洁02) / dasher(变异飞蝇) / fixed(喷孢菌)
--          lightSeeker(趋光菌兽) / crab(裂钳蟹) / manyHands(门帝克3型)
--          bossIceFire(冰火人 BOSS, 3阶段)
-- 数值来源: docs/怪物配置表.txt (freq=攻击间隔秒, dmg=水量伤害)
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local MON = require "data/monsters"
local Bullets = require "core/bullets"
local P = require "core/player"
local A = require "core/abilities"
local ArtClips = require "data/art"

---@class Enemies
local E = {}

---@class Enemy
---@field uid integer
---@field def MonsterDef
---@field node Node
---@field body RigidBody2D|nil
---@field hp number
---@field maxHp number      实际最大血量（def.hp × BALANCE.monsterHp）
---@field dead boolean
---@field atkTimer number
---@field state string
---@field stateTimer number
---@field facing number
---@field animTime number
---@field hitFlash number
---@field hitSquash number   受击缩放计时（>0 时敌人被压扁/膨胀）
---@field hpBarTimer number  血条显示计时（受伤后重置）
---@field stunTimer number
---@field slowTimer number
---@field slowAmount number
---@field blindTimer number
---@field poisonDps number
---@field poisonTimer number
---@field paralysisTimer number
---@field baseY number
---@field patrolDir number
---@field radius number
---@field tier string
---@field phase integer      BOSS 阶段
---@field warnTimer number   攻击预警（裂钳蟹抬螯）
---@field chargeDir number

E.list = {}
local nextUid = 1

local TERRAIN_CHECK = nil
function E.setTerrainCheck(fn) TERRAIN_CHECK = fn end

--- 攻击动画时长：怪物各自配置，缺省用全局值。
---@param def table
---@param attackKind string|nil 裂钳蟹按当前动作的完整帧数计时
---@return number
function E.attackAnimTime(def, attackKind)
    if def and def.ai == "crab" and attackKind then
        local clip = ArtClips["enemy_crab_" .. attackKind]
        if clip then return clip.count / clip.fps end
    end
    return (def and def.atkAnimTime) or Config.HIT_FX.attackAnimTime
end

--- 出手起手：记录待结算的近战伤害与剩余“命中帧”延迟，挥动到命中帧才真正扣血。
---@param e Enemy
---@param dmg number
---@param range number
local function beginMeleeWindup(e, dmg, range)
    e.pendingMelee = { dmg = dmg, range = range, delay = E.attackAnimTime(e.def) * Config.HIT_FX.meleeHitAt }
    e.atkAnimTimer = E.attackAnimTime(e.def)
end

--- 出手起手（远程）：记录待发射的弹幕参数，挥臂到出手帧才真正发射。
---@param e Enemy
---@param dx number
---@param dy number
---@param speed number
---@param dmg number
---@param color number[]|nil
---@param gravity number
local function beginRangedWindup(e, dx, dy, speed, dmg, color, gravity)
    e.pendingShot = {
        dx = dx, dy = dy, speed = speed, dmg = dmg, color = color, gravity = gravity,
        delay = E.attackAnimTime(e.def) * Config.HIT_FX.rangedFireAt,
    }
    e.atkAnimTimer = E.attackAnimTime(e.def)
end

--- 创建怪物
---@param scene Scene
---@param key string
---@param x number
---@param y number
---@param opts table|nil { hpMul, noPhysics }
function E.spawn(scene, key, x, y, opts)
    local def = MON[key]
    if not def then
        print("[Enemy] 未知怪物: " .. tostring(key))
        return nil
    end
    opts = opts or {}
    local node = scene:CreateChild("Enemy_" .. key)
    node:SetPosition2D(x, y)

    local hpMax = def.hp * Config.BALANCE.monsterHp
    ---@type Enemy
    local e = {
        uid = nextUid,
        def = def, node = node, hp = hpMax + 0.0, dead = false,
        maxHp = hpMax,
        atkTimer = (def.attacks[1] and def.attacks[1].freq) or 1.0,
        state = "idle", stateTimer = 0.0, facing = -1, animTime = math.random() * 10,
        hitFlash = 0.0, hitSquash = 0.0, hpBarTimer = 0.0, atkAnimTimer = 0.0,
        stunTimer = 0.0, slowTimer = 0.0, slowAmount = 0.0,
        blindTimer = 0.0, poisonDps = 0.0, poisonTimer = 0.0, paralysisTimer = 0.0,
        baseY = y, patrolDir = 1, radius = def.radius, tier = def.tier,
        phase = 1, warnTimer = 0.0, chargeDir = 1,
        homeX = x, homeY = y,
        dashCd = 0.0, bites = 0,
    }
    nextUid = nextUid + 1

    if not def.flying then
        e.body = node:CreateComponent("RigidBody2D")
        e.body.bodyType = BT_DYNAMIC
        e.body.fixedRotation = true
        e.body.linearDamping = 4.0
        e.body.gravityScale = 1.0
        local shape = node:CreateComponent("CollisionCircle2D")
        shape.radius = def.radius
        shape.density = 1.5
        shape.friction = 0.2
        shape.restitution = 0
        shape.categoryBits = Config.COL.ENEMY
        shape.maskBits = Config.COL.TERRAIN + Config.COL.PLAYER + Config.COL.ENEMY
    else
        -- 飞行怪：kinematic，自行控制位置
        e.body = node:CreateComponent("RigidBody2D")
        e.body.bodyType = BT_KINEMATIC
        e.body.fixedRotation = true
        local shape = node:CreateComponent("CollisionCircle2D")
        shape.radius = def.radius
        shape.categoryBits = Config.COL.ENEMY
        shape.maskBits = Config.COL.PLAYER
    end

    e.isFlying = def.flying
    table.insert(E.list, e)
    return e
end

function E.clear()
    for _, e in ipairs(E.list) do
        if e.node then e.node:Remove() end
    end
    E.list = {}
end

--- 移除单个
function E.remove(e)
    e.dead = true
    if e.node then e.node:Remove() end
end

--- 对敌人造成伤害
---@param e Enemy
---@param dmg number
---@param b Bullet|nil 弹幕（携带修饰效果）
function E.damage(e, dmg, b)
    if e.dead then return end
    e.hp = e.hp - dmg
    -- 受击反馈：变白 + 缩放压扁 + 血条弹出（时长见 Config.HIT_FX）
    e.hitFlash = Config.HIT_FX.flashTime
    e.hitSquash = Config.HIT_FX.squashTime
    e.hpBarTimer = Config.HIT_FX.hpBarShowTime
    if b then
        if b.poisonDps then
            e.poisonDps = b.poisonDps
            e.poisonTimer = 3.0
        end
        if b.paralysis then
            e.paralysisTimer = b.paralysis
        end
        if b.slow then
            e.slowAmount = b.slow
            e.slowTimer = 2.0
        end
        if b.light and e.def.phototaxis == "light" then
            -- 鮟鱇鱼液态光弹吸引趋光生物
            e.attractX = b.x
            e.attractY = b.y
            e.attractTimer = 2.0
        end
    end
    GS.emit("enemyHit", e, dmg)
    if e.hp <= 0 then
        E.kill(e)
    end
end

--- 击杀
function E.kill(e)
    if e.dead then return end
    e.dead = true
    GS.emit("enemyKilled", e)
    -- 掉落贝壳（受 ECONOMY 基础值 + BALANCE.dropRate 倍率）
    local EC = Config.ECONOMY
    local base = e.tier == "boss" and EC.shellDropBoss
        or (e.tier == "elite" and EC.shellDropElite or EC.shellDropSmall)
    local shells = math.max(1, math.floor(base * Config.BALANCE.dropRate))
    local piles = math.min(EC.shellDropPiles, math.ceil(shells / 4))
    for i = 1, piles do
        GS.emit("dropShell", e.node.position2D.x + (math.random() - 0.5), e.node.position2D.y + 0.3)
    end
    E.remove(e)
end

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function setVel(e, vx, vy)
    if not e.body then return end
    e.body.linearVelocity = Vector2(vx, vy)
    e.body.awake = true
end

local function moveTo(e, tx, speed, dt)
    if not e.body then return end
    local pos = e.node.position2D
    local dx = tx - pos.x
    if math.abs(dx) > 0.1 then
        e.facing = dx > 0 and 1 or -1
    end
    local speedMul = e.slowTimer > 0 and (1 - e.slowAmount) or 1
    setVel(e, math.max(-speed, math.min(speed, dx * 3)) * speedMul, e.body.linearVelocity.y)
end

--- 玩家可见位置
local function playerPos()
    return P.node and P.node.position2D or nil
end

local function canSee(e, pp, range)
    if not pp or P.dead then return false, 0, 0 end
    local d = dist(e.node.position2D.x, e.node.position2D.y, pp.x, pp.y)
    return d <= range, d, pp
end

-- ===================== AI 行为 =====================

local function aiChaser(e, dt, pp)
    -- 清洁机器人-01: 乱晃，检测到玩家靠近后体术攻击
    local atk = e.def.attacks[1]
    local see, d = canSee(e, pp, e.def.detectRange)
    local speedMul = e.slowTimer > 0 and (1 - e.slowAmount) or 1
    if see then
        e.state = "chase"
        moveTo(e, pp.x, e.def.speed, dt)
        if d <= atk.range + e.radius + 0.5 then
            e.atkTimer = e.atkTimer - dt
            if e.atkTimer <= 0 then
                e.atkTimer = atk.freq
                e.state = "attack"
                e.stateTimer = 0.25
                beginMeleeWindup(e, atk.dmg, atk.range + e.radius + 0.5)
            end
        end
    else
        -- 乱晃巡逻
        e.stateTimer = e.stateTimer - dt
        if e.stateTimer <= 0 then
            e.stateTimer = 1 + math.random() * 2
            e.patrolDir = math.random() < 0.5 and -1 or 1
        end
        setVel(e, e.patrolDir * e.def.speed * 0.4 * speedMul, e.body.linearVelocity.y)
        e.facing = e.patrolDir
    end
end

local function aiShooter(e, dt, pp)
    -- 清洁机器人-02: 站定，远程发射海绵
    local atk = e.def.attacks[1]
    local see, d = canSee(e, pp, e.def.detectRange)
    if see then
        e.facing = (pp.x > e.node.position2D.x) and 1 or -1
        e.state = "aim"
        e.atkTimer = e.atkTimer - dt
        if e.atkTimer <= 0 and d <= atk.range + 2 then
            e.atkTimer = atk.freq
            e.state = "attack"
            e.stateTimer = 0.2
            -- 弹幕延迟到挥臂出手帧发射，与动画同步。
            local ep = e.node.position2D
            local dx, dy = pp.x - ep.x, pp.y - ep.y
            local len = math.sqrt(dx * dx + dy * dy)
            beginRangedWindup(e, dx / len, dy / len + 0.3, 7, atk.dmg, e.def.accent, 9.0)
        end
    else
        e.state = "idle"
    end
end

local function aiDasher(e, dt, pp)
    -- 变异飞蝇: 飞行巡逻，检测到玩家冲刺撞击
    local atk = e.def.attacks[1]
    local ep = e.node.position2D
    local see, d = canSee(e, pp, e.def.detectRange)
    if e.dashCd > 0 then e.dashCd = e.dashCd - dt end

    if see and e.dashCd <= 0 and d <= atk.range + 2.5 then
        -- 冲刺
        e.state = "dash"
        e.stateTimer = 0.35
        e.dashCd = atk.freq + 0.5
        local dx, dy = pp.x - ep.x, pp.y - ep.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.001 then dx, dy, len = e.facing, 0, 1 end
        e.chargeDir = 1
        setVel(e, dx / len * e.def.speed * 2.6, dy / len * e.def.speed * 2.6)
        e.facing = dx > 0 and 1 or -1
        GS.emit("enemyDash", e, atk.dmg)
    elseif e.state == "dash" then
        e.stateTimer = e.stateTimer - dt
        if e.stateTimer <= 0 then e.state = "idle" end
    else
        -- 飞行巡逻：正弦漂浮 + 缓慢移动
        e.stateTimer = e.stateTimer + dt
        local tx = e.homeX + math.sin(e.stateTimer * 0.5) * 2.5
        local ty = e.baseY + math.sin(e.stateTimer * 1.7) * 0.4
        local pos = e.node.position2D
        setVel(e, (tx - pos.x) * 1.2, (ty - pos.y) * 2.0)
        e.facing = (tx > pos.x) and 1 or -1
        e.state = "patrol"
    end
end

local function aiFixed(e, dt, pp)
    -- 喷孢菌: 固定原地，3 枚扇形孢子弹
    local atk = e.def.attacks[1]
    local see, d = canSee(e, pp, e.def.detectRange)
    local ep = e.node.position2D
    if see and d <= atk.range + 3 then
        e.facing = (pp.x > ep.x) and 1 or -1
        e.atkTimer = e.atkTimer - dt
        e.state = "aim"
        if e.atkTimer <= 0 then
            e.atkTimer = atk.freq
            e.state = "attack"
            e.stateTimer = 0.25
            local dx, dy = pp.x - ep.x, pp.y - ep.y
            local base = math.atan(dy, dx)
            for i = -1, 1 do
                local a = base + i * 0.28
                Bullets.spawnEnemyBullet(ep.x, ep.y + 0.25, math.cos(a), math.sin(a), 6.5,
                    atk.dmg, e.def.accent, 3.0)
            end
        end
    else
        e.state = "idle"
    end
end

local function aiLightSeeker(e, dt, pp)
    -- 趋光菌兽: 未交战向光源靠近；受攻击后追击玩家，短距离扑咬 2 次
    local atk = e.def.attacks[1]
    local see, d = canSee(e, pp, e.def.detectRange)

    if e.aggro then
        e.state = "chase"
        moveTo(e, pp.x, e.def.speed * 1.3, dt)
        if d <= atk.range + e.radius + 0.4 then
            if e.bites < 2 then
                e.atkTimer = e.atkTimer - dt
                if e.atkTimer <= 0 then
                    e.atkTimer = 0.6
                    e.bites = e.bites + 1
                    e.state = "attack"
                    e.stateTimer = 0.22
                    -- 伤害对齐扑咬的咬中帧，而不是起手瞬间。
                    beginMeleeWindup(e, atk.dmg, atk.range + e.radius + 0.4)
                    -- 扑咬：小跳
                    if e.body then
                        local v = e.body.linearVelocity
                        setVel(e, v.x + e.facing * 3, 4.5)
                    end
                    if e.bites >= 2 then
                        e.bites = 0
                        e.atkTimer = atk.freq + 0.8
                    end
                end
            end
        else
            e.bites = 0
            e.atkTimer = math.min(e.atkTimer, 0.35)
        end
    else
        -- 向感知范围内的光源移动（玩家鮟鱇鱼液态光圈 / 场景光源）
        local targetX = nil
        if e.attractTimer and e.attractTimer > 0 then
            e.attractTimer = e.attractTimer - dt
            targetX = e.attractX
        elseif GS.lightSources then
            local bestD = e.def.detectRange
            for _, ls in ipairs(GS.lightSources) do
                local dd = dist(e.node.position2D.x, e.node.position2D.y, ls.x, ls.y)
                if dd < bestD then bestD = dd; targetX = ls.x end
            end
        end
        if targetX then
            e.state = "seek"
            moveTo(e, targetX, e.def.speed * 0.7, dt)
        else
            e.stateTimer = e.stateTimer - dt
            if e.stateTimer <= 0 then
                e.stateTimer = 1.5 + math.random() * 2
                e.patrolDir = math.random() < 0.5 and -1 or 1
            end
            local speedMul = e.slowTimer > 0 and (1 - e.slowAmount) or 1
            setVel(e, e.patrolDir * e.def.speed * 0.35 * speedMul, e.body.linearVelocity.y)
            e.state = "wander"
        end
        if see and d < 2.5 then e.aggro = true end
    end
end

local function aiCrab(e, dt, pp)
    -- 裂钳蟹: 近距大螯交替砸击，远距小螯抛碎石；攻击前抬螯预警；共用冷却
    local melee, ranged = e.def.attacks[1], e.def.attacks[2]
    local see, d = canSee(e, pp, e.def.detectRange)
    local ep = e.node.position2D

    -- 从预警到完整动画结束锁定攻击类型、朝向与螯，不进入另一攻击分支。
    if e.atkAnimTimer > 0 then
        e.state = "attack"
        setVel(e, 0, e.body and e.body.linearVelocity.y or 0)
        return
    end

    if e.warnTimer > 0 then
        e.state = "warn"
        setVel(e, 0, e.body and e.body.linearVelocity.y or 0)
        e.warnTimer = math.max(0, e.warnTimer - dt)
        if e.warnTimer == 0 then
            if not pp or P.dead then
                e.pendingAttack = nil
                e.state = "idle"
                return
            end
            e.atkAnimTimer = E.attackAnimTime(e.def, e.pendingAttack)
            e.state = "attack"
            e.stateTimer = e.atkAnimTimer
            if e.pendingAttack == "melee" then
                GS.emit("enemyMelee", e, melee.dmg, melee.range + e.radius + 0.5)
                e.atkTimer = melee.freq
            elseif e.pendingAttack == "ranged" then
                local dx, dy = pp.x - ep.x, pp.y - ep.y
                local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
                Bullets.spawnEnemyBullet(ep.x, ep.y + 0.4, dx / len, dy / len + 0.45, 8,
                    ranged.dmg, e.def.accent, 12.0, nil, "enemy_crab_stone_fly", "enemy_crab_stone_hit")
                e.atkTimer = ranged.freq
            end
        end
        return
    end
    e.pendingAttack = nil

    if see then
        e.facing = (pp.x > ep.x) and 1 or -1
        if d <= melee.range + e.radius + 0.6 then
            e.state = "chase"
            moveTo(e, pp.x, e.def.speed * 0.8, dt)
            e.atkTimer = e.atkTimer - dt
            if e.atkTimer <= 0 then
                -- 每次出手换一只螯；出手后保持不变，避免左右螯动画逐帧闪烁穿帮。
                e.clawSide = -(e.clawSide or 1)
                e.pendingAttack = "melee"
                e.warnTimer = 0.45
                e.state = "warn"
                setVel(e, 0, e.body and e.body.linearVelocity.y or 0)
            end
        else
            e.state = "chase"
            moveTo(e, pp.x, e.def.speed, dt)
            e.atkTimer = e.atkTimer - dt
            if e.atkTimer <= 0 and d <= ranged.range + 1.5 then
                e.clawSide = -(e.clawSide or 1)
                e.pendingAttack = "ranged"
                e.warnTimer = 0.4
                e.state = "warn"
                setVel(e, 0, e.body and e.body.linearVelocity.y or 0)
            end
        end
    else
        e.state = "idle"
    end
end

local function aiManyHands(e, dt, pp)
    -- 门帝克3型: 远程(2手) + 近战(2手) 独立
    local ranged, melee = e.def.attacks[1], e.def.attacks[2]
    local see, d = canSee(e, pp, e.def.detectRange)
    local ep = e.node.position2D

    if see then
        e.facing = (pp.x > ep.x) and 1 or -1
        e.state = "chase"
        if d > melee.range + 1 then
            moveTo(e, pp.x, e.def.speed, dt)
        else
            setVel(e, 0, e.body.linearVelocity.y)
        end
        -- 远程手
        e.rangedTimer = (e.rangedTimer or ranged.freq) - dt
        if e.rangedTimer <= 0 and d <= ranged.range + 2 then
            e.rangedTimer = ranged.freq
            e.state = "attack"
            e.stateTimer = 0.2
            local dx, dy = pp.x - ep.x, pp.y - ep.y
            local len = math.sqrt(dx * dx + dy * dy)
            for i = -1, 1, 2 do
                local a = math.atan(dy, dx) + i * 0.15
                Bullets.spawnEnemyBullet(ep.x, ep.y + 0.5, math.cos(a), math.sin(a), 8,
                    ranged.dmg, e.def.accent, 4.0)
            end
        end
        -- 近战手
        e.atkTimer = e.atkTimer - dt
        if e.atkTimer <= 0 and d <= melee.range + e.radius + 0.5 then
            e.atkTimer = melee.freq
            e.state = "attack"
            e.stateTimer = 0.25
            GS.emit("enemyMelee", e, melee.dmg, melee.range + e.radius + 0.5)
        end
    else
        e.state = "idle"
    end
end

-- ===================== BOSS: 冰火人 =====================
-- 总血量 120, 3 阶段: P1 120→80 平衡, P2 80→40 火焰过载, P3 40→0 寒冰过载
-- 阶段阈值随 BALANCE.monsterHp 倍率等比缩放（以 def.hp 为基准血量）。

local function bossPhase(e)
    local base = e.def.hp
    local scale = (base > 0) and (e.maxHp / base) or 1
    local p2 = Config.BOSS.phaseP2 * scale
    local p3 = Config.BOSS.phaseP3 * scale
    if e.hp > p2 then return 1 end
    if e.hp > p3 then return 2 end
    return 3
end

local function aiBoss(e, dt, pp)
    local ep = e.node.position2D
    local newPhase = bossPhase(e)
    if newPhase ~= e.phase then
        e.phase = newPhase
        e.atkTimer = 1.5
        GS.emit("bossPhase", e.phase)
        print("[BOSS] 进入阶段 P" .. e.phase)
    end
    if not pp then return end
    e.facing = (pp.x > ep.x) and 1 or -1

    e.atkTimer = e.atkTimer - dt

    -- 冰火冲撞执行（P3，优先于 attack 状态处理）
    if e.chargeState == "charge" then
        e.chargeState = "dash"
        e.chargeTimer = 0.8
        setVel(e, e.facing * 11, 0)
    elseif e.chargeState == "dash" then
        e.chargeTimer = e.chargeTimer - dt
        if e.chargeTimer <= 0 then e.chargeState = nil end
        return
    end

    if e.state == "attack" then
        e.stateTimer = e.stateTimer - dt
        if e.stateTimer <= 0 then e.state = "idle" end
        return
    end
    if e.atkTimer > 0 then
        -- 间歇性移动
        moveTo(e, pp.x, e.def.speed * 0.5, dt)
        return
    end

    local roll = math.random()
    if e.phase == 1 then
        if roll < 0.4 then
            -- 冰火交替吐息
            e.state = "attack"; e.stateTimer = 0.9; e.atkTimer = 2.2
            e.breathSide = -(e.breathSide or 1)
            GS.emit("bossBreath", e, e.breathSide > 0 and "fire" or "ice")
        elseif roll < 0.7 then
            -- 落地冲击：跳起砸地，冲击波 + 火/低温地面
            e.state = "attack"; e.stateTimer = 1.1; e.atkTimer = 3.0
            if e.body then setVel(e, e.facing * 4, 9) end
            e.pendingSlam = true
            GS.emit("bossSlamStart", e)
        else
            -- 散弹投射：火球冰球交叉散射
            e.state = "attack"; e.stateTimer = 0.8; e.atkTimer = 3.0
            for i = 1, 5 do
                local a = math.atan(pp.y - ep.y, pp.x - ep.x) + (i - 3) * 0.22
                local isFire = (i % 2 == 1)
                Bullets.spawnEnemyBullet(ep.x, ep.y + 0.8, math.cos(a), math.sin(a) + 0.25, 9, 1,
                    isFire and Config.PAL.bossFire or Config.PAL.bossIce, 6.0, isFire and "fire" or "ice")
            end
            GS.emit("bossVolley", e)
        end
    elseif e.phase == 2 then
        -- 火焰侧过载：火焰浪潮 / 火球弹幕 / 砸地
        if roll < 0.4 then
            e.state = "attack"; e.stateTimer = 1.2; e.atkTimer = 2.6
            GS.emit("bossWave", e, "fire")
        elseif roll < 0.75 then
            e.state = "attack"; e.stateTimer = 1.0; e.atkTimer = 2.4
            for i = 1, 6 do
                local tx = ep.x + (math.random() - 0.5) * 14
                Bullets.spawnEnemyBullet(tx, ep.y + 6, 0, -1, 6 + math.random() * 3, 1,
                    Config.PAL.bossFire, 2.0, "fire")
            end
            GS.emit("bossRain", e, "fire")
        else
            e.state = "attack"; e.stateTimer = 1.1; e.atkTimer = 3.0
            if e.body then setVel(e, e.facing * 4, 9) end
            e.pendingSlam = true
            GS.emit("bossSlamStart", e)
        end
    else
        -- 寒冰侧过载：冰环扩散 / 冰柱坠落 / 冰火冲撞
        if roll < 0.35 then
            e.state = "attack"; e.stateTimer = 1.4; e.atkTimer = 2.8
            GS.emit("bossRing", e)
        elseif roll < 0.65 then
            e.state = "attack"; e.stateTimer = 1.2; e.atkTimer = 2.6
            for i = 1, 5 do
                local tx = ep.x + (math.random() - 0.5) * 14
                Bullets.spawnEnemyBullet(tx, ep.y + 7, 0, -1, 8, 1, Config.PAL.bossIce, 1.0, "ice")
            end
            GS.emit("bossRain", e, "ice")
        else
            e.state = "attack"; e.stateTimer = 0.9; e.atkTimer = 3.2
            e.chargeState = "charge"
            GS.emit("bossCharge", e)
        end
    end
end

local AI = {
    chaser = aiChaser,
    shooter = aiShooter,
    dasher = aiDasher,
    fixed = aiFixed,
    lightSeeker = aiLightSeeker,
    crab = aiCrab,
    manyHands = aiManyHands,
    bossIceFire = aiBoss,
}

-- ===================== 主更新 =====================

---@param dt number
---@param lightPos Vector2|nil 玩家光源（鮟鱇鱼固态目盲/液态吸引）
function E.update(dt, lightPos)
    local pp = playerPos()
    for _, e in ipairs(E.list) do
        if not e.dead then
            e.animTime = e.animTime + dt
            if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
            if e.hitSquash > 0 then e.hitSquash = e.hitSquash - dt end
            if e.hpBarTimer > 0 then e.hpBarTimer = e.hpBarTimer - dt end
            if e.atkAnimTimer > 0 then e.atkAnimTimer = e.atkAnimTimer - dt end
            -- 近战伤害对齐挥砍命中帧：起手后延迟到命中帧才结算一次
            local pm = e.pendingMelee
            if pm then
                pm.delay = pm.delay - dt
                if pm.delay <= 0 then
                    e.pendingMelee = nil
                    GS.emit("enemyMelee", e, pm.dmg, pm.range)
                end
            end
            -- 远程弹幕对齐挥臂出手帧：起手后延迟到出手帧才发射
            local ps = e.pendingShot
            if ps then
                ps.delay = ps.delay - dt
                if ps.delay <= 0 then
                    e.pendingShot = nil
                    local ep = e.node.position2D
                    Bullets.spawnEnemyBullet(ep.x, ep.y + 0.2, ps.dx, ps.dy, ps.speed, ps.dmg,
                        ps.color, ps.gravity)
                end
            end
            if e.slowTimer > 0 then e.slowTimer = e.slowTimer - dt end
            if e.blindTimer > 0 then e.blindTimer = e.blindTimer - dt end

            -- 中毒持续伤害（鳐鱼液态）
            if e.poisonTimer > 0 then
                e.poisonTimer = e.poisonTimer - dt
                e.hp = e.hp - e.poisonDps * dt
                if e.hp <= 0 then E.kill(e) goto continue end
            end

            -- 麻痹（电鳗液态）
            if e.paralysisTimer > 0 then
                e.paralysisTimer = e.paralysisTimer - dt
                goto continue
            end

            -- 电鳗固态：周身电流，怪物触碰受伤
            if P.form == "solid" and A.selfZapDmg > 0 and pp then
                local zapCdKey = "zap" .. e.uid
                local t = A.selfZapTimers[zapCdKey] or 0
                if t > 0 then
                    A.selfZapTimers[zapCdKey] = t - dt
                else
                    local ep = e.node.position2D
                    if dist(ep.x, ep.y, pp.x, pp.y) <= A.selfZapRange + e.radius then
                        E.damage(e, A.selfZapDmg)
                        A.selfZapTimers[zapCdKey] = A.selfZapFreq
                        GS.emit("zapHit", e)
                    end
                end
            end

            -- 固态高速撞击（形态特点 + 弹壳碎片眩晕）
            if P.form == "solid" and P.ramming and pp then
                local ep = e.node.position2D
                if dist(ep.x, ep.y, pp.x, pp.y) <= e.radius + 0.5 then
                    local ramCdKey = "ram" .. e.uid
                    E.ramTimers = E.ramTimers or {}
                    if not E.ramTimers[ramCdKey] or E.ramTimers[ramCdKey] <= 0 then
                        E.ramTimers[ramCdKey] = 0.6
                        -- 命中位置先快照，击杀会移除敌人节点；特效在接触点独立播放。
                        local hitX, hitY = (pp.x + ep.x) * 0.5, (pp.y + ep.y) * 0.5
                        E.damage(e, Config.PLAYER.ramDamage)
                        GS.emit("ramHit", e, hitX, hitY)
                        -- 弹壳碎片：小概率眩晕
                        if GS.hasRelic("bulletShard") and math.random() < 0.25 then
                            e.stunTimer = 1.2
                            e.paralysisTimer = 1.2
                            GS.emit("toast", "弹壳碎片触发：敌人眩晕！")
                        end
                        if P.body then
                            local v = P.body.linearVelocity
                            P.body.linearVelocity = Vector2(v.x * 0.3, v.y)
                        end
                    end
                end
            end
            -- 撞击冷却递减
            E.ramTimers = E.ramTimers or {}
            for k, v in pairs(E.ramTimers) do
                if v > 0 then E.ramTimers[k] = v - dt end
            end

            if e.dead then goto continue end
            if e.stunTimer > 0 then
                e.stunTimer = e.stunTimer - dt
                goto continue
            end

            -- 目盲（鮟鱇鱼固态）：靠近玩家的敌人被目盲
            if lightPos and e.blindTimer <= 0 then
                local fx = A.currentEffects()
                if fx.blindRange > 0 then
                    local ep = e.node.position2D
                    if dist(ep.x, ep.y, lightPos.x, lightPos.y) <= fx.blindRange then
                        e.blindTimer = fx.blindDur
                        GS.emit("enemyBlind", e)
                    end
                end
            end
            if e.blindTimer > 0 then
                -- 目盲：原地不动
                if e.body then setVel(e, 0, e.body.linearVelocity.y) end
                goto continue
            end

            -- BOSS 砸地落地检测
            if e.pendingSlam and e.body then
                local v = e.body.linearVelocity
                if math.abs(v.y) < 0.5 and e.stateTimer < 0.8 then
                    e.pendingSlam = false
                    GS.emit("bossSlamLand", e)
                end
            end
            if e.chargeState == "dash" then
                e.chargeTimer = e.chargeTimer - dt
                if e.chargeTimer <= 0 then e.chargeState = nil end
            end

            -- 执行 AI
            local fn = AI[e.def.ai]
            if fn then fn(e, dt, pp) end

            -- 接触伤害：圆形敌人 (rE) 与玩家 (rP) 外缘相碰即命中，留 0.06 米接触容差。
            -- 使用当前形态半径，气态半径较大时不能被 Box2D 挡在固定判定范围之外。
            -- 飞行怪撞不伤固态；液态/气态、其他怪物仍按无敌与伤害规则结算。
            if pp and not P.dead and P.invuln <= 0 and not (e.def.flying and P.form == "solid") then
                local ep = e.node.position2D
                local contactRange = e.radius + Config.FORMS[P.form].radius + 0.06
                if dist(ep.x, ep.y, pp.x, pp.y) <= contactRange then
                    if e.state == "dash" or e.def.ai == "chaser" or e.chargeState == "dash" then
                        local dmg = e.chargeState == "dash" and 2 or 1
                        P.changeWater(-dmg, Config.DMG.ENEMY)
                    end
                end
            end
        end
        ::continue::
    end
end

--- 受击标记 aggro（趋光菌兽被攻击后追击玩家）
GS.on("enemyHit", function(e, dmg)
    if e.def.ai == "lightSeeker" then e.aggro = true end
end)

return E
