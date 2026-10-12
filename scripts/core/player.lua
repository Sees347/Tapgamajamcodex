-- ============================================================================
-- core/player.lua - 水精灵玩家控制器
-- 系统覆盖: 移动(P0-1) / 水量(P0-2) / 形态(P0-3) / 失败恢复(P0-7)
-- ============================================================================

local Config = require "config"
local GS = require "core/state"

---@class Player
local P = {}

---@type Node
P.node = nil
---@type RigidBody2D
P.body = nil
---@type CollisionCircle2D
P.bodyShape = nil
---@type CollisionCircle2D
P.footShape = nil

P.form = "liquid"          -- liquid / gas / solid
---@type number
P.water = Config.PLAYER.initWater
P.onGround = false
P.groundContacts = 0
P.facing = 1               -- 1 右 / -1 左
P.invuln = 0.0             -- 无敌计时
P.jumpBuffer = 0.0
P.coyote = 0.0
P.canDoubleJump = false
P.doubleJumpUsed = false
P.dead = false

-- 固态撞击
P.ramming = false
P.ramDir = 1

-- 位移（Shift 冲刺）：液态/固态仅落地可用，气态可空中；期间完全无敌、可穿过小怪、不穿墙
P.dashing = false
P.dashTimer = 0.0
P.dashCd = 0.0
P.dashDirX = 1

-- 飞鱼气态冲刺：空中点按跳跃触发的短促位移（不无敌），可连按连续冲
P.flyDashing = false
P.flyDashTimer = 0.0
P.flyDashCd = 0.0
P.flyDashDirX = 1

-- 青蛙液态钩爪：发射绳状水柱，命中地形后把玩家拉过去（泰拉瑞亚风格）
P.grappling = false       -- 钩爪是否已挂住
P.grappleX = 0.0          -- 挂点世界坐标
P.grappleY = 0.0
P.grappleLen = 0.0        -- 当前绳索长度（供渲染）

-- 剑鱼固态格挡：举盾姿态时减免敌人伤害
P.blocking = false        -- 本帧是否处于格挡姿态（由 main 写入）
P.blockFlash = 0.0        -- 格挡成功闪光（渲染用）

-- 剑鱼近战挥砍僵直：挥砍瞬间短暂锁定水平移动，增强打击感
P.swingLock = 0.0         -- 剩余僵直时间（秒）

-- 可变跳跃高度：记录本次跳跃已上升时长，松手时截断上升速度
P.jumpHoldTimer = 0.0     -- 本次跳跃已按住时长（秒）
P.jumpRising = false      -- 是否处于"本次跳跃的上升段"（用于松手截断）

local TERRAIN_CHECK = nil
---@param fn fun(x:number, y:number):boolean
function P.setTerrainCheck(fn) TERRAIN_CHECK = fn end

-- 视觉状态（供渲染）
P.squash = 1.0             -- 挤压拉伸
P.formFlash = 0.0          -- 变形闪光
P.hurtFlash = 0.0
P.animTime = 0.0

local groundSensorOn = false

-- ===================== 创建 =====================

---@param scene Scene
---@param x number
---@param y number
function P.create(scene, x, y)
    P.destroy()
    P.node = scene:CreateChild("Player")
    P.node:SetPosition2D(x, y)

    P.body = P.node:CreateComponent("RigidBody2D")
    P.body.bodyType = BT_DYNAMIC
    P.body.fixedRotation = true
    P.body.linearDamping = 0
    P.body.angularDamping = 0
    P.body.gravityScale = 1

    P.bodyShape = P.node:CreateComponent("CollisionCircle2D")
    P.bodyShape.radius = Config.FORMS.liquid.radius
    P.bodyShape.density = 1.0
    P.bodyShape.friction = 0.0
    P.bodyShape.restitution = 0.0
    P.bodyShape.categoryBits = Config.COL.PLAYER
    P.bodyShape.maskBits = Config.COL.TERRAIN + Config.COL.ENEMY

    -- 脚底传感器（center 偏移，见 lua-scripting-guide）
    P.footShape = P.node:CreateComponent("CollisionCircle2D")
    P.footShape.radius = Config.FORMS.liquid.radius * 0.6
    P.footShape.center = Vector2(0, -Config.FORMS.liquid.radius * 0.92)
    P.footShape.trigger = true
    P.footShape.categoryBits = Config.COL.FOOT
    P.footShape.maskBits = Config.COL.TERRAIN

    P.form = "liquid"
    P.dead = false
    P.invuln = 0.0
    P.ramming = false
    P.dashing = false
    P.dashTimer = 0.0
    P.dashCd = 0.0
    P.groundContacts = 0
    P.onGround = false
    P.doubleJumpUsed = false
    P.jumpBuffer = 0.0
    P.coyote = 0.0
    P.jumpHoldTimer = 0.0
    P.jumpRising = false
    P.water = GS.save.water
    groundSensorOn = false
    print("[Player] 创建于", x, y)
end

function P.destroy()
    if P.node then
        P.node:Remove()
        P.node = nil
        P.body = nil
    end
end

--- 传送（存档点复活）
function P.teleport(x, y)
    if not P.body then return end
    P.body.linearVelocity = Vector2(0, 0)
    P.node:SetPosition2D(x, y)
    P.dead = false
    P.ramming = false
    P.dashing = false
    P.dashTimer = 0.0
    P.invuln = 1.0
    GS.emit("playerTeleport", x, y)
end

-- ===================== 水量 =====================

---@return number
function P.getWater()
    return GS.save.water
end

--- 补水（正数）/扣血（负数）
---@param delta number
---@param src string|nil 伤害来源（Config.DMG.*）
---@return boolean 是否死亡
function P.changeWater(delta, src)
    if P.dead then return false end
    if delta < 0 then
        -- 位移期间完全无敌：子弹/近战/火焰/陷阱全部免疫
        if P.dashing then return false end
        if P.invuln > 0 then return false end
        -- 怪物伤害全局倍率（面板可调难度；仅作用于敌人/BOSS，不影响环境火焰/低温/陷阱）
        if (src == Config.DMG.ENEMY or src == Config.DMG.BOSS) then
            delta = delta * Config.BALANCE.monsterDmg
            -- 剑鱼固态格挡：举盾姿态时减免敌人伤害
            if P.blocking then
                delta = delta * (1 - Config.BLOCK.reduce)
                P.blockFlash = 0.2
                GS.emit("playerBlock")
            end
        end
        -- 饰品减伤
        if src == Config.DMG.FIRE and GS.hasRelic("heatCrystal") then
            delta = delta + 1
        elseif src == Config.DMG.COLD and GS.hasRelic("coldShell") then
            delta = delta + 1
        elseif src == Config.DMG.ENEMY and P.form == "gas" and GS.hasRelic("vaporFilm") then
            delta = delta + 0.5
        end
        if delta >= 0 then
            P.invuln = 0.6
            P.hurtFlash = 0.3
            GS.emit("toast", "饰品抵消了伤害！")
            return false
        end
    end

    GS.save.water = math.max(0, math.min(GS.maxWater(), GS.save.water + delta))
    GS.emit("waterChanged", GS.save.water, GS.maxWater())

    if delta < 0 then
        P.invuln = Config.PLAYER.hurtInvuln
        P.hurtFlash = 0.35
        P.squash = 0.7
        GS.emit("playerHurt", src)
    end

    if GS.save.water <= 0 then
        P.die()
        return true
    end
    return false
end

function P.healFull()
    GS.save.water = GS.maxWater()
    GS.emit("waterChanged", GS.save.water, GS.maxWater())
end

function P.die()
    if P.dead then return end
    P.dead = true
    GS.emit("playerDied")
    GS.setMode("dead")
    print("[Player] 水量归零，等待泉眼复活")
end

-- ===================== 形态 =====================

--- 切换形态
---@param newForm string
---@param silent boolean|nil 静默初始化，不触发特效或自动起跳
function P.setForm(newForm, silent)
    if P.form == newForm then return end
    local old = P.form
    P.form = newForm
    local f = Config.FORMS[newForm]

    -- 重建碰撞体尺寸/密度
    P.bodyShape.radius = f.radius
    P.bodyShape.density = f.density
    P.footShape.radius = f.radius * 0.6
    P.footShape.center = Vector2(0, -f.radius * 0.92)

    -- 形态切换打断位移，并恢复碰撞掩码（位移期间为"穿过小怪"临时改过）
    if P.dashing then
        P.dashing = false
        P.dashTimer = 0.0
        P.dashCd = Config.DASH.cooldown
    end
    P.bodyShape.maskBits = Config.COL.TERRAIN + Config.COL.ENEMY
    if newForm ~= "solid" then P.ramming = false end

    -- 固→液时原地起跳：只设置液态正常跳速，不叠加原速度，也不瞬移穿过天花板。
    -- 自动起跳不依赖跳跃键，清掉旧短跳状态与缓冲；静默初始化不触发。
    if old == "solid" and newForm == "liquid" and not silent and not P.dead then
        local velocity = P.body.linearVelocity
        P.body.linearVelocity = Vector2(velocity.x, f.jumpVel)
        P.body.gravityScale = f.gravUp
        P.body.linearDamping = 0
        P.body.awake = true
        P.onGround = false
        P.coyote = 0
        P.jumpBuffer = 0
        P.jumpHoldTimer = 0
        P.jumpRising = false
        GS.emit("playerJump")
    end

    if not silent then
        P.formFlash = 0.4
        P.squash = 0.6
        GS.emit("formChanged", newForm, old)
        print("[Player] 形态切换: " .. old .. " -> " .. newForm)
    end
end

function P.getFormName()
    return Config.FORMS[P.form].name
end

-- ===================== 位移（Shift 冲刺） =====================
-- 液态/固态只能在落地时位移；气态可以在空中位移。
-- 位移期间完全无敌（子弹/近战/火焰/陷阱全部免疫），可穿过小怪，撞墙立即停下。

--- 当前是否处于闪避状态（位移无敌）
---@return boolean
function P.isDodging()
    return P.dashing
end

--- 尝试触发位移
---@param moveX number 当前水平输入（0 时朝面向）
---@return boolean 是否成功触发
function P.tryDash(moveX)
    if P.dead or P.dashing or P.dashCd > 0 then return false end
    -- 液态/固态：仅落地可用；气态：空中也可用
    local airAllowed = Config.DASH.airForms[P.form] == true
    if not P.onGround and not airAllowed then return false end

    local dir = (moveX ~= 0) and (moveX > 0 and 1 or -1) or P.facing
    P.dashing = true
    P.dashTimer = Config.DASH.duration
    P.dashDirX = dir
    P.facing = dir
    P.squash = 0.75
    -- 穿过小怪：位移期间碰撞掩码只保留地形
    if P.bodyShape then
        P.bodyShape.maskBits = Config.COL.TERRAIN
    end
    GS.emit("playerDash", dir)
    print(string.format("[Player] 位移触发: form=%s dir=%d grounded=%s", P.form, dir, tostring(P.onGround)))
    return true
end

--- 结束位移（正常结束或撞墙提前结束）
local function endDash()
    if not P.dashing then return end
    P.dashing = false
    P.dashCd = Config.DASH.cooldown
    if P.bodyShape then
        P.bodyShape.maskBits = Config.COL.TERRAIN + Config.COL.ENEMY
    end
    if P.body then
        local v = P.body.linearVelocity
        P.body.linearVelocity = Vector2(v.x * Config.DASH.endSpeedKeep, v.y)
    end
end

--- 位移中的每帧推进（水平直线，撞墙即停）
---@param dt number
local function updateDash(dt)
    P.dashTimer = P.dashTimer - dt
    local speed = Config.DASH.distance / Config.DASH.duration
    local pos = P.node.position2D
    local r = Config.FORMS[P.form].radius
    -- 前方探针：不穿墙，撞墙立即结束位移
    if TERRAIN_CHECK then
        local probeX = pos.x + P.dashDirX * (r + speed * dt + 0.06)
        if TERRAIN_CHECK(probeX, pos.y) or TERRAIN_CHECK(probeX, pos.y + r * 0.6)
            or TERRAIN_CHECK(probeX, pos.y - r * 0.6) then
            P.body.linearVelocity = Vector2(0, 0)
            P.body.gravityScale = 1
            endDash()
            return
        end
    end
    P.body.linearVelocity = Vector2(P.dashDirX * speed, 0)
    P.body.gravityScale = 0
    P.body.awake = true
    if P.dashTimer <= 0 then
        P.body.gravityScale = 1
        endDash()
    end
end

-- ===================== 飞鱼气态冲刺 =====================
-- 空中点按跳跃触发短促位移（不无敌，纯机动）；连按可连续冲刺。
-- 有方向输入则沿输入方向，否则沿面向；不穿墙（撞墙即停）。

--- 尝试触发飞鱼冲刺（仅气态 + 装备飞鱼时由 update 调用）
---@param moveX number
---@return boolean
function P.tryFlyDash(moveX)
    if P.dead or P.flyDashing or P.flyDashCd > 0 or P.onGround then return false end
    local dir = (moveX ~= 0) and (moveX > 0 and 1 or -1) or P.facing
    P.flyDashing = true
    P.flyDashTimer = Config.FLYDASH.duration
    P.flyDashDirX = dir
    P.facing = dir
    P.squash = 0.85
    GS.emit("playerFlyDash", dir)
    return true
end

--- 结束飞鱼冲刺
local function endFlyDash()
    if not P.flyDashing then return end
    P.flyDashing = false
    P.flyDashCd = Config.FLYDASH.cooldown
    if P.body then
        local v = P.body.linearVelocity
        P.body.linearVelocity = Vector2(v.x * 0.3, v.y)
    end
end

--- 飞鱼冲刺每帧推进（水平直线，撞墙即停）
---@param dt number
local function updateFlyDash(dt)
    P.flyDashTimer = P.flyDashTimer - dt
    local speed = Config.FLYDASH.distance / Config.FLYDASH.duration
    local pos = P.node.position2D
    local r = Config.FORMS[P.form].radius
    if TERRAIN_CHECK then
        local probeX = pos.x + P.flyDashDirX * (r + speed * dt + 0.06)
        if TERRAIN_CHECK(probeX, pos.y) or TERRAIN_CHECK(probeX, pos.y + r * 0.6)
            or TERRAIN_CHECK(probeX, pos.y - r * 0.6) then
            P.body.linearVelocity = Vector2(0, 0)
            endFlyDash()
            return
        end
    end
    -- 冲刺期间保持一定上升趋势，形成"空中滑翔冲刺"观感
    P.body.linearVelocity = Vector2(P.flyDashDirX * speed, P.body.linearVelocity.y * 0.2)
    P.body.gravityScale = 0.2
    P.body.awake = true
    if P.flyDashTimer <= 0 then
        P.body.gravityScale = 1
        endFlyDash()
    end
end

-- ===================== 青蛙液态钩爪 =====================
-- 朝瞄准方向发射绳状水柱；命中地形则挂住并把玩家拉过去（泰拉瑞亚风格）。
-- 再次按下（或落地/切换形态）释放。发射时沿射线步进检测地形。

--- 发射钩爪（青蛙液态）。朝瞄准点方向射线检测地形。
---@param ax number 方向单位向量 x
---@param ay number 方向单位向量 y
---@return boolean 是否成功挂住
function P.fireGrapple(ax, ay)
    if P.dead or P.form ~= "liquid" then return false end
    local pos = P.node.position2D
    local maxLen = Config.GRAPPLE.maxLength
    local step = 0.15
    local hitX, hitY = nil, nil
    if TERRAIN_CHECK then
        local d = 0.2
        while d <= maxLen do
            local tx = pos.x + ax * d
            local ty = pos.y + ay * d
            if TERRAIN_CHECK(tx, ty) then
                hitX, hitY = tx, ty
                break
            end
            d = d + step
        end
    end
    if not hitX then
        GS.emit("grappleMiss")
        return false
    end
    P.grappling = true
    P.grappleX = hitX
    P.grappleY = hitY
    P.grappleLen = math.sqrt((hitX - pos.x) ^ 2 + (hitY - pos.y) ^ 2)
    GS.emit("grappleHit", hitX, hitY)
    return true
end

--- 释放钩爪
function P.releaseGrapple()
    if P.grappling then
        P.grappling = false
        GS.emit("grappleRelease")
    end
end

--- 钩爪每帧推进：把玩家朝挂点拉近。
---@param dt number
local function updateGrapple(dt)
    if not P.grappling then return end
    local pos = P.node.position2D
    local dx, dy = P.grappleX - pos.x, P.grappleY - pos.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.5 then
        -- 到达挂点附近：释放并保留一点冲量
        P.releaseGrapple()
        return
    end
    local speed = Config.GRAPPLE.pullSpeed
    P.body.linearVelocity = Vector2(dx / dist * speed, dy / dist * speed)
    P.body.gravityScale = 0     -- 拉拽期间不受重力，避免下坠
    P.body.awake = true
end

--- 一次升温只转换一级；与伤害分离，元素弹不会额外扣水。
function P.heatStep()
    if P.dead or P.dashing then return end
    if P.form == "solid" then
        P.toLiquid()
    elseif P.form == "liquid" then
        P.setForm("gas")
    end
end

--- 单次火接触：固→液、液→气，然后结算一次火伤害。
function P.onFireHit()
    if P.dead then return end
    P.heatStep()
    P.changeWater(-1, Config.DMG.FIRE)
end

--- 遇低温 → 液态结冰为固态；气态遇低温凝回液态（涌现表）；不扣水量
function P.onColdHit()
    if P.dead or P.dashing then return end
    if P.form == "liquid" then
        P.setForm("solid")
        GS.emit("coldFreeze")
    elseif P.form == "gas" then
        P.toLiquid()
        GS.emit("coldCondense")
    end
end

--- 独立元素命中：保留攻击自身伤害及无敌规则，不叠加环境火伤害。
---@param element string|nil
---@param damage number
---@param source string
function P.onElementHit(element, damage, source)
    if P.dead or P.invuln > 0 then return end
    P.changeWater(-damage, source)
    if element == "fire" then
        P.heatStep()
    elseif element == "ice" then
        P.onColdHit()
    end
end

--- 气态遇低温 / 固态遇火 → 液态（场景机制表；泉眼回液态）
function P.toLiquid()
    if P.form ~= "liquid" then
        P.setForm("liquid")
    end
end

-- ===================== 碰撞回调（由 main 分发） =====================

function P.onGroundContactBegin()
    P.groundContacts = P.groundContacts + 1
    P.onGround = true
    P.coyote = Config.PLAYER.coyoteTime
    P.doubleJumpUsed = false
    if P.ramming then
        GS.emit("ramEnd")
        P.ramming = false
    end
end

function P.onGroundContactEnd()
    P.groundContacts = P.groundContacts - 1
    if P.groundContacts <= 0 then
        P.groundContacts = 0
        P.onGround = false
    end
end

-- ===================== 更新 =====================

--- 每帧移动逻辑（input 状态由 main 提供）
---@param dt number
---@param inputState table {moveX, jumpPressed, jumpHeld, downHeld, dashPressed}
---@param fishFx table 当前形态的鱼效果合并（来自 abilities 模块）
function P.update(dt, inputState, fishFx)
    if not P.body or P.dead then return end

    P.animTime = P.animTime + dt
    if P.invuln > 0 then P.invuln = P.invuln - dt end
    if P.hurtFlash > 0 then P.hurtFlash = P.hurtFlash - dt end
    if P.formFlash > 0 then P.formFlash = P.formFlash - dt end
    if P.blockFlash > 0 then P.blockFlash = P.blockFlash - dt end
    if P.swingLock > 0 then P.swingLock = P.swingLock - dt end
    if P.dashCd > 0 then P.dashCd = P.dashCd - dt end
    if P.flyDashCd > 0 then P.flyDashCd = P.flyDashCd - dt end
    -- 落地重置飞鱼冲刺冷却（便于落地后立刻再冲）
    if P.onGround then P.flyDashCd = 0 end
    -- squash 回弹
    P.squash = P.squash + (1.0 - P.squash) * math.min(1, dt * 10)
    if P.coyote > 0 then P.coyote = P.coyote - dt end
    if P.jumpBuffer > 0 then P.jumpBuffer = P.jumpBuffer - dt end

    local f = Config.FORMS[P.form]
    local vel = P.body.linearVelocity

    -- 跳跃输入缓冲（放在位移分支前，位移末尾按跳不丢输入）
    if inputState.jumpPressed then P.jumpBuffer = Config.PLAYER.jumpBufferTime end

    -- 位移触发（Shift / 手机端「闪」按钮）
    if inputState.dashPressed then
        P.tryDash(inputState.moveX)
    end

    -- 位移推进：接管水平移动，跳过常规移动/跳跃/重力逻辑
    if P.dashing then
        updateDash(dt)
        return
    end

    -- 钩爪（青蛙液态）：挂住时把玩家拉向挂点，接管移动
    if P.grappling then
        if not inputState.grappleHeld then
            P.releaseGrapple()          -- 松开按键即释放
        else
            updateGrapple(dt)
            return
        end
    end

    -- 地面状态由 main 每帧探测写入（L.isSolid 探针）
    if P.onGround then
        P.coyote = Config.PLAYER.coyoteTime
        P.doubleJumpUsed = false
        -- 注意：不要在这里清 jumpRising。起跳后探针仍会短暂贴着地面，
        -- 每帧重置会导致可变高度逻辑从不执行（短跳/长跳无区别）。
        -- 落地结束由下方"上升速度 <= 0"自然处理。
        P.releaseGrapple()      -- 落地自动松开钩爪
        if P.ramming and math.abs(vel.x) < Config.PLAYER.ramSpeed * 0.7 then
            P.ramming = false
        end
    end

    -- 装备移速加成（飞鱼固态/鳐鱼气态）
    local speedBonus = fishFx.speedUp or 0
    -- 组合效果：气态 + 飞鱼 + 电鳗 → 空中横移加速（仅在离地时生效）
    if not P.onGround then speedBonus = speedBonus + (fishFx.airSpeedUp or 0) end
    local moveSpeed = f.speed * (1 + speedBonus)

    -- 二段跳能力（青蛙固态）
    P.canDoubleJump = fishFx.doubleJump == true

    -- 水平移动：按形态加速度插值（固态打滑）
    -- 挥砍僵直期间锁死水平移动（保留朝向），增强近战打击感
    local moveInput = P.swingLock > 0 and 0 or inputState.moveX
    local targetVx = moveInput * moveSpeed
    local accel = P.onGround and f.accelGround or f.accelAir
    if moveInput == 0 then accel = P.swingLock > 0 and 40 or f.decel end
    local newVx = vel.x + (targetVx - vel.x) * math.min(1, accel * dt)
    if inputState.moveX > 0.1 then P.facing = 1
    elseif inputState.moveX < -0.1 then P.facing = -1 end

    -- 固态撞击：速度够快撞怪造成伤害（形态特点）
    if P.form == "solid" and not P.ramming and P.onGround and math.abs(newVx) >= Config.PLAYER.ramSpeed then
        P.ramming = true
        P.ramDir = newVx > 0 and 1 or -1
    end
    if P.ramming and math.abs(newVx) < Config.PLAYER.ramSpeed * 0.7 then
        P.ramming = false
    end

    -- 垂直：跳跃（jumpBuffer 已在位移分支前统一写入）
    local newVy = vel.y

    -- 重力缩放：气态"像棉花被抛出空中然后落下"（低重力 + 阻尼）
    local gScale = newVy > 0 and f.gravUp or f.gravDown
    P.body.gravityScale = gScale
    P.body.linearDamping = (P.form == "gas" and not P.onGround) and f.damping or 0.0

    -- 滑翔/飞行（飞鱼）
    local flying = false
    if not P.onGround then
        if fishFx.dash and P.form == "gas" then
            -- 气态冲刺：空中点按跳跃触发一次短促冲刺，可连按连续冲（替代原自由飞行）。
            flying = true
            if inputState.jumpPressed then
                P.tryFlyDash(inputState.moveX)
                P.jumpBuffer = 0        -- 冲刺已消费输入，避免落地瞬间误触发跳跃
            end
            if P.flyDashing then
                updateFlyDash(dt)
                return
            end
        elseif fishFx.glide and P.form == "liquid" and inputState.jumpHeld and newVy < 0 then
            -- 液态滑翔：下落速度受限
            flying = true
            newVy = math.max(newVy, -2.2)
        end
    end

    if P.jumpBuffer > 0 then
        if P.coyote > 0 and not flying then
            newVy = f.jumpVel
            P.jumpBuffer = 0
            P.coyote = 0
            P.squash = 1.3
            -- 开始一次可变高度跳跃
            P.jumpHoldTimer = 0.0
            P.jumpRising = true
            GS.emit("playerJump")
        elseif P.canDoubleJump and not P.doubleJumpUsed and not P.onGround then
            newVy = f.jumpVel * 0.92
            P.doubleJumpUsed = true
            P.jumpBuffer = 0
            P.squash = 1.3
            P.jumpHoldTimer = 0.0
            P.jumpRising = true
            GS.emit("playerDoubleJump")
        end
    end

    -- 可变跳跃高度（经典 2D 平台手感）：
    -- 上升段内按住跳跃键可继续升高；提前松手则截断上升速度 → 跳得矮。
    if P.jumpRising then
        if newVy <= 0 then
            -- 到达顶点，结束本次跳跃的上升段
            P.jumpRising = false
        elseif not inputState.jumpHeld then
            -- 松手：按系数削减上升速度（点按跳得矮）
            newVy = newVy * Config.PLAYER.jumpCutMul
            P.jumpRising = false
        else
            P.jumpHoldTimer = P.jumpHoldTimer + dt
            if P.jumpHoldTimer >= Config.PLAYER.jumpHoldMaxTime then
                P.jumpRising = false     -- 已满跳，防止无限飘
            end
        end
    end

    -- 速度上限（气态漂浮）
    if newVy < -22 then newVy = -22 end

    P.body.linearVelocity = Vector2(newVx, newVy)
    P.body.awake = true
end

--- 屏幕坐标 → 世界坐标（由 main 的相机换算提供，渲染模块调用）
function P.worldPos()
    if P.node then return P.node.position2D end
    return Vector2(0, 0)
end

return P
