-- ============================================================================
-- core/abilities.lua - 鱼类携带与能力系统 (P0-4)
-- 7 种鱼 × 3 形态 = 21 种弹幕/被动效果
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local FISH = require "data/fish"
local P = require "core/player"

---@class Abilities
local A = {}

-- 弹幕冷却计时（按装备槽分别计时）
A.cooldowns = {}
-- 电场/环绕弹幕状态
A.orbitAngle = 0.0
-- 吞噬冷却（青蛙液态）
A.devourCd = 0.0
-- 近战伤害（剑鱼，update 中根据装备写入，main 的 meleeHit 读取）
---@type number
A.meleeDmg = 0
-- 黏附中的弹幕（藤壶液态）由 bullets 模块处理，这里提供配置
-- 环绕闪电计时（电鳗固态 self 模式）
A.selfZapTimer = 0.0
-- 环绕电场命中冷却计时（main 写入，key = "orb"..uid）
---@type table<string, number>
A.orbitHitTimers = {}
-- 电鳗固态周身电流参数（update 中根据装备写入，enemies 读取）
---@type number
A.selfZapDmg = 0
---@type number
A.selfZapRange = 0.9
---@type number
A.selfZapFreq = 0.5
---@type table<string, number>  -- 周身电流命中冷却（enemies 写入，key="zap"..uid）
A.selfZapTimers = {}
-- 环绕电场（电鳗液态）激活状态
---@type boolean
A.orbitActive = false
---@type FishFormEffect?
A.orbitFx = nil
---@type string?
A.orbitFish = nil
-- 射击触发脉冲（由 main 在按住左键时设置，consume 后归零）
A.fireRequest = false
-- 点按攻击脉冲：液态近战只消费按下沿，不把长按变成自动连段。
A.attackPressed = false
A.liquidStage = 0
A.liquidRecovery = 0.0
A.liquidChainTime = 0.0
A.liquidBuffered = false
-- 猛击反冲请求（射水鱼气态，交给 player 施加）
A.recoilRequest = nil

--- PC/移动端统一入口；时停期间保留点击，重复通知合并为一次。
function A.requestAttack()
    A.attackPressed = true
    A.fireRequest = true
end

--- 取消输入/续段，但保留收招；暂停恢复不能跳过两刀之间的间隔。
function A.cancelLiquidChain()
    A.attackPressed = false
    A.liquidStage = 0
    A.liquidChainTime = 0.0
    A.liquidBuffered = false
end

--- 变形、卸装、死亡或切关时取消液态续段，不改变固态冷却。
function A.resetLiquidMelee()
    A.cancelLiquidChain()
    A.liquidRecovery = 0.0
end

--- 获取当前形态下所有装备鱼的效果（合并）
---@return table merged 合并后的效果表
---@return FishDef[] equipped 装备定义列表
function A.currentEffects()
    local merged = {
        bullets = {},   -- 主动弹幕配置列表
        speedUp = 0,
        doubleJump = false,
        glide = false,
        dash = false,                     -- 飞鱼气态：冲刺
        grapple = false,                  -- 青蛙液态：钩爪
        melee = false,                    -- 剑鱼液态/固态：近战攻击
        meleeRange = 0, meleeDmg = 0,     -- 近战参数
        block = false,                    -- 剑鱼固态：格挡攻击
        burst = 0,                        -- 剑鱼气态：连发数
        stickMax = 0, stickDur = 0,      -- 藤壶液态
        hoverDur = 0,                     -- 藤壶气态
        bounceMax = 0,                    -- 藤壶固态
        poisonDps = 0,                    -- 鳐鱼液态
        paralysis = 0,                    -- 电鳗液态
        slow = 0,                         -- 射水鱼固态
        blindRange = 0, blindDur = 0,     -- 鮟鱇鱼固态
        lightRange = 0,                   -- 鮟鱇鱼液态
        selfZap = 0,                      -- 电鳗固态
        homing = false,                   -- 鮟鱇鱼气态
        recoil = false,                   -- 射水鱼气态
    }
    local equipped = {}
    if not GS.save then return merged, equipped end

    local hasFlyfish, hasEel = false, false
    for _, key in ipairs(GS.save.equipped) do
        local def = FISH[key]
        if def then
            table.insert(equipped, def)
            if key == "flyfish" then hasFlyfish = true end
            if key == "eel" then hasEel = true end
            local fx = def[P.form] or {}
            -- 被动移动类
            if fx.speedUp then merged.speedUp = merged.speedUp + fx.speedUp end
            if fx.doubleJump then merged.doubleJump = true end
            if fx.glide then merged.glide = true end
            if fx.dash then merged.dash = true end
            if fx.grapple then merged.grapple = true end
            if fx.block then merged.block = true end
            -- 近战攻击（剑鱼液态/固态）：不生成弹幕，改为近身判定
            if fx.melee then
                merged.melee = true
                merged.meleeRange = fx.range or 1.6
                merged.meleeDmg = fx.dmg or 6
                merged.meleeFreq = fx.freq or 0.4
            end
            if fx.burst and fx.burst > 0 then merged.burst = fx.burst end
            -- 弹幕修饰类（合并到全局）
            if fx.stickMax then merged.stickMax = fx.stickMax; merged.stickDur = fx.stickDur or 3 end
            if fx.hoverDur then merged.hoverDur = fx.hoverDur end
            if fx.bounceMax then merged.bounceMax = fx.bounceMax end
            if fx.poisonDps then merged.poisonDps = fx.poisonDps end
            if fx.paralysis then merged.paralysis = merged.paralysis + fx.paralysis end
            if fx.slow then merged.slow = fx.slow end
            if fx.blindRange then merged.blindRange = fx.blindRange; merged.blindDur = fx.blindDur or 1 end
            if fx.lightRange then merged.lightRange = fx.lightRange end
            if fx.dir == "homing" then merged.homing = true end
            if fx.recoil then merged.recoil = true end
            -- 主动弹幕类
            if fx.dir and fx.dir ~= "self" and fx.dmg then
                table.insert(merged.bullets, { fishKey = key, fx = fx })
            end
            -- 电鳗固态：环绕电流（接触伤害，不用弹幕）
            if fx.dir == "self" and fx.dmg then
                merged.selfZap = math.max(merged.selfZap, fx.dmg)
                merged.selfZapFreq = fx.freq or 0.5
            end
        end
    end

    -- 组合效果：气态 + 飞鱼 + 电鳗 → 空中横移加速（仅气态空中生效，player 读取）
    merged.airSpeedUp = (P.form == "gas" and hasFlyfish and hasEel)
        and Config.COMBO.gasFlyEelAirSpeed or 0

    -- 无弹幕类装备 → 基础水弹（主角攻击机制：按住左键发射弹幕）
    -- 近战（剑鱼）不产生弹幕，故不触发此回退；青蛙钩爪改由右键触发，
    -- 左键仍走基础水弹，因此不再豁免 grapple。
    if #merged.bullets == 0 and not merged.melee then
        table.insert(merged.bullets, {
            fishKey = "__base__",
            fx = { range = Config.PLAYER.baseAtkRange, dir = "mouse",
                   dmg = Config.PLAYER.baseAtk, freq = Config.PLAYER.baseAtkFreq },
        })
    end
    return merged, equipped
end

--- 液态点按连段：最多预存下一刀，收招到点才出手，不因点击过快叠刀。
---@param dt number
---@param merged table
---@param ctx table
local function updateLiquidMelee(dt, merged, ctx)
    local combo = Config.LIQUID_MELEE
    A.liquidRecovery = math.max(0, A.liquidRecovery - dt)
    A.liquidChainTime = math.max(0, A.liquidChainTime - dt)
    if A.liquidChainTime <= 0 then A.liquidStage = 0 end

    if A.attackPressed then A.liquidBuffered = true end
    if not A.liquidBuffered or A.liquidRecovery > 0 then return end
    A.liquidBuffered = false

    local nextStage = A.liquidStage + 1
    if nextStage > #combo.stages then nextStage = 1 end
    local stage = combo.stages[nextStage]
    A.liquidStage = nextStage
    -- 调参把 freq 降得很低时仍保证刀光完整播放，并保留至少 0.10 秒留白。
    local interval = math.max((merged.meleeFreq or 0.35) * stage.intervalMul, stage.fxDuration + 0.10)
    A.liquidRecovery = interval
    A.liquidChainTime = interval + combo.chainWindow
    A.meleeAttack(merged, ctx, stage, nextStage)
end

--- 每帧更新：处理射击请求、环绕弹幕、电场、吞噬冷却
---@param dt number
---@param ctx table { playerPos, aimWorld, spawnBullet, enemies }
function A.update(dt, ctx)
    local merged = A.currentEffects()
    if P.dead then
        A.resetLiquidMelee()
        A.fireRequest = false
        return
    end
    A.orbitAngle = A.orbitAngle + dt * Config.ABILITIES.orbitSpeed
    if A.devourCd > 0 then A.devourCd = A.devourCd - dt end

    -- 电鳗固态：周身电流，怪物触碰受伤（由 enemy AI 检测距离实现，这里只存参数）
    A.selfZapDmg = merged.selfZap
    A.selfZapRange = Config.ABILITIES.selfZapRange
    -- 近战伤害（剑鱼）：供 main 的 meleeHit 回调结算
    A.meleeDmg = merged.meleeDmg

    -- 电鳗液态：环绕电场（持续伤害 + 麻痹）——每帧重算，避免切换装备后残留
    A.orbitActive = false
    A.orbitFx = nil
    A.orbitFish = nil
    if merged.selfZap == 0 then
        for _, b in ipairs(merged.bullets) do
            if b.fx.dir == "orbit" then
                -- 环绕弹幕常驻，不需要射击请求；伤害判定在 main 按环绕距离做
                A.orbitActive = true
                A.orbitFx = b.fx
                A.orbitFish = b.fishKey
                break
            end
        end
    end

    -- 液态近战使用独立收招计时；固态仍按原有冷却持续挥砍。
    -- 钩爪改由右键触发，不再与左键的近战互斥。
    local liquidMelee = merged.melee and P.form == "liquid"
    if liquidMelee then
        updateLiquidMelee(dt, merged, ctx)
    else
        A.resetLiquidMelee()
    end
    A.attackPressed = false

    -- 钩爪改由右键触发，不再独占液态左键；左键照常发射基础水弹。
    -- 主动射击（按住左键 / 射击按钮），不改变其他鱼的弹幕输入。
    if A.fireRequest then
        A.fireRequest = false
        -- 固态近战保留原来的频率、僵直和刀光时长。
        if merged.melee and not liquidMelee then
            local cd = A.cooldowns["__melee__"] or 0
            if cd <= 0 then
                A.cooldowns["__melee__"] = merged.meleeFreq or 0.4
                A.meleeAttack(merged, ctx)
            end
        end
        for _, b in ipairs(merged.bullets) do
            local cdKey = b.fishKey
            local cd = A.cooldowns[cdKey] or 0
            local fx = b.fx
            if fx.dir ~= "orbit" and cd <= 0 then
                A.cooldowns[cdKey] = fx.freq or 0.4
                A.fireOne(b.fishKey, fx, merged, ctx)
            end
        end
    end

    -- 冷却递减
    for k, v in pairs(A.cooldowns) do
        if v > 0 then A.cooldowns[k] = v - dt end
    end

    -- 猛击反冲（射水鱼气态）
    if A.recoilRequest and P.body then
        local vel = P.body.linearVelocity
        P.body.linearVelocity = Vector2(vel.x + A.recoilRequest.x, vel.y + A.recoilRequest.y)
        P.body.awake = true
        A.recoilRequest = nil
    end
end

--- 发射一发弹幕
---@param fishKey string
---@param fx FishFormEffect
---@param merged table
---@param ctx table
function A.fireOne(fishKey, fx, merged, ctx)
    local px, py = ctx.playerPos.x, ctx.playerPos.y
    local dirMode = fx.dir or "mouse"
    local speed = Config.PLAYER.baseBulletSpeed
    -- 射程 × 全局倍率：面板/配置改 bulletRange 时，所有弹幕（含各鱼）同步变远
    local range = (fx.range or Config.PLAYER.baseAtkRange) * Config.BALANCE.bulletRange
    -- 玩家伤害 × 全局平衡倍率（面板实时调难度）
    local dmg = (fx.dmg or Config.PLAYER.baseAtk) * Config.BALANCE.playerDmg
    GS.emit("playerAttack")

    local function spawn(dx, dy, opts)
        opts = opts or {}
        local isIce = P.form == "solid" and fishKey == "archerfish"
        -- 子弹视觉均为定格单帧：视觉寿命=子弹寿命(射程×倍率)，不随动画播完消失。
        ---@type string?
        local artKey = nil
        if isIce then artKey = "bullet_ice"
        elseif fishKey == "eel" and dirMode == "down" then artKey = "bullet_lightning"
        elseif merged.paralysis > 0 then artKey = "bullet_electric"
        elseif fishKey == "__base__" or fishKey == "archerfish" then artKey = "bullet_water" end
        local bullet = ctx.spawnBullet({
            x = px + dx * 0.5, y = py + dy * 0.5,
            dx = dx, dy = dy,
            speed = opts.speed or speed,
            range = opts.range or range,
            dmg = dmg,
            fishKey = fishKey,
            poisonDps = merged.poisonDps > 0 and merged.poisonDps or nil,
            paralysis = merged.paralysis > 0 and merged.paralysis or nil,
            slow = merged.slow > 0 and merged.slow or nil,
            stickDur = merged.stickDur > 0 and merged.stickDur or nil,
            stickMax = merged.stickMax > 0 and merged.stickMax or nil,
            hoverDur = merged.hoverDur > 0 and merged.hoverDur or nil,
            bounceMax = merged.bounceMax > 0 and merged.bounceMax or nil,
            homing = merged.homing or (dirMode == "homing"),
            light = merged.lightRange > 0,
            isIce = isIce,
            artKey = artKey,
            color = (FISH[fishKey] and FISH[fishKey].color) or Config.PAL.water,
            recoilFrom = opts.recoilFrom,
        })
        -- 发射音效：所有玩家弹幕都出声（此前漏了剑鱼等非 archerfish 的弹）
        if bullet then
            GS.emit("sfx", "shoot")
        end
    end

    if dirMode == "mouse" or dirMode == "homing" then
        local ax, ay = ctx.aimWorld.x - px, ctx.aimWorld.y - py
        local len = math.sqrt(ax * ax + ay * ay)
        if len < 0.001 then ax, ay, len = P.facing, 0, 1 end
        -- 连发（剑鱼气态）：同一方向扇形散开多枚
        local n = merged.burst or 0
        if n > 1 then
            local spread = 0.14
            for i = 1, n do
                local off = (i - (n + 1) / 2) * spread
                local a = math.atan(ay, ax) + off
                spawn(math.cos(a), math.sin(a))
            end
        else
            spawn(ax / len, ay / len)
        end
        -- 射水鱼气态：猛击，自身反方向弹开
        if fx.recoil and len > 0.001 then
            local boost = Config.ABILITIES.recoilBoost
            A.recoilRequest = { x = -ax / len * boost, y = -ay / len * boost * Config.ABILITIES.recoilVertical }
        end
    elseif dirMode == "down" then
        -- 电鳗气态：向下劈出闪电
        GS.emit("sfx", "lightning")
        spawn(0, -1, { speed = speed * Config.ABILITIES.downLightningSpeedMul })
    end
end

--- 近战攻击（剑鱼液态/固态）：对身前扇形范围敌人造成伤害。
---@param merged table
---@param ctx table { playerPos, aimWorld, enemies, meleeHit, crates, meleeCrateHit }
---@param stage table|nil 液态连段的独立时机/特效参数；固态不传。
---@param stageIndex number|nil
function A.meleeAttack(merged, ctx, stage, stageIndex)
    local px, py = ctx.playerPos.x, ctx.playerPos.y
    local range = merged.meleeRange or 1.6
    -- 判定设计（单位米，朝右示例；朝左镜像）：
    -- 背后不命中 <--- (玩家 O) | >>> 前方 120° 扇形，半径 range + 敌人半径。
    -- dx * facing > 0 排除背后及中心线；擦边按原 dot > 0.5 判定。
    -- 每刀仅在出手时结算一次，刀光和下一段均不重复本刀伤害。
    local ax, ay = P.facing > 0 and 1 or -1, 0
    P.swingLock = stage and stage.swingLock or Config.MELEE_FX.swingLock
    GS.emit("playerMelee", px, py, ax, ay, range, stage, stageIndex)
    GS.emit("sfx", "slash")
    if ctx.enemies then
        for _, e in ipairs(ctx.enemies) do
            if not e.dead and e.node then
                local ep = e.node.position2D
                local dx, dy = ep.x - px, ep.y - py
                local d = math.sqrt(dx * dx + dy * dy)
                if dx * ax > 0 and d <= range + e.radius then
                    -- 仅命中朝向侧的身前约 120° 扇形。
                    local dot = dx / d * ax
                    if dot > 0.5 then
                        GS.emit("bulletImpact", { x = ep.x, y = ep.y, artKey = nil })
                        if ctx.meleeHit then ctx.meleeHit(e) end
                    end
                end
            end
        end
    end

    -- 可破坏箱：同一扇形判定命中即扣血。取箱体上离玩家最近的一点，
    -- 避免大箱子中心在射程外、贴脸砍却不中的情况。
    if ctx.crates and ctx.meleeCrateHit then
        for _, c in ipairs(ctx.crates) do
            if not c.destroyed then
                local cx = math.max(c.x - c.w * 0.5, math.min(px, c.x + c.w * 0.5))
                local cy = math.max(c.y - c.h * 0.5, math.min(py, c.y + c.h * 0.5))
                local dx, dy = cx - px, cy - py
                local d = math.sqrt(dx * dx + dy * dy)
                if d <= range and dx * ax > 0 then
                    local dot = dx / d * ax
                    if dot > 0.5 then
                        GS.emit("bulletImpact", { x = cx, y = cy, artKey = nil })
                        ctx.meleeCrateHit(c)
                    end
                end
            end
        end
    end
end

--- 环绕电场弹幕位置（电鳗液态），供渲染与伤害
---@param cx number
---@param cy number
---@param t number 时间
---@return number x, number y
function A.orbitPos(cx, cy, t)
    local r = Config.ABILITIES.orbitRadius
    return cx + math.cos(t) * r, cy + math.sin(t) * r * Config.ABILITIES.orbitRadiusY
end

-- 即使暂停界面中卸装再装回，也不能继承上一套连段。
GS.on("formChanged", A.resetLiquidMelee)
GS.on("playerDied", A.resetLiquidMelee)
GS.on("fishChanged", A.resetLiquidMelee)
GS.on("modeChanged", function(mode)
    if mode ~= "playing" then
        A.cancelLiquidChain()
        A.fireRequest = false
    end
end)

return A
