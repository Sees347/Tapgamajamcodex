-- ============================================================================
-- core/bullets.lua - 弹幕系统
-- 支持修饰: 黏附(藤壶液) / 悬停(藤壶气) / 反弹(藤壶固) / 吞噬(青蛙液)
--          追踪(鮟鱇气) / 中毒(鳐鱼液) / 麻痹(电鳗液) / 减速(射水固)
-- ============================================================================

local GS = require "core/state"
local Config = require "config"

---@class Bullets
local B = {}

---@class Bullet
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field life number      剩余寿命 (秒)
---@field dmg number
---@field radius number
---@field color number[]
---@field opts table
---@field state string     fly / stick / hover
---@field stickTimer number
---@field bounceCount integer
---@field hitEnemies table<number, boolean>
---@field dead boolean
---@field trail table      尾迹点
---@field isIce boolean
---@field homing boolean
---@field light boolean
---@field poisonDps number|nil
---@field paralysis number|nil
---@field slow number|nil
---@field devour boolean|nil
---@field fromEnemy boolean|nil
---@field element string|nil  fire / ice，仅用于明确的冰火弹丸
---@field artKey? string       玩家上传动画，不影响伤害或碰撞半径
---@field animTime number
---@field angle number         屏幕空间朝向，静止后保留最后方向

B.list = {}   ---@type Bullet[]

-- 黏附中的弹幕总数（藤壶上限）
local stickCount = 0

local TERRAIN_CHECK = nil -- 由 main 注入: function(x,y) -> boolean 是否在地形内
local CRATE_CHECK = nil   -- 由 main 注入: function(x,y) -> crate|nil 该点上的可破坏箱
local CRATE_HIT = nil     -- 由 main 注入: function(crate, dmg) 箱子受击

function B.setTerrainCheck(fn)
    TERRAIN_CHECK = fn
end

function B.setCrateHooks(check, hit)
    CRATE_CHECK = check
    CRATE_HIT = hit
end

--- 生成弹幕
---@param o table
function B.spawn(o)
    if o.stickDur then
        if stickCount >= (o.stickMax or 6) then return end -- 同时存在黏附上限
    end
    ---@type Bullet
    local b = {
        x = o.x, y = o.y,
        vx = o.dx * (o.speed or 14), vy = o.dy * (o.speed or 14),
        life = (o.range or 6) / math.max(0.1, o.speed or 14),
        dmg = o.dmg or 2,
        radius = o.isIce and Config.BULLETS.iceRadius or Config.BULLETS.playerRadius,
        color = o.color or { 90, 180, 255 },
        opts = o,
        state = "fly",
        stickTimer = 0,
        bounceCount = 0,
        hitEnemies = {},
        dead = false,
        trail = {},
        isIce = o.isIce or false,
        homing = o.homing or false,
        light = o.light or false,
        poisonDps = o.poisonDps,
        paralysis = o.paralysis,
        slow = o.slow,
        devour = o.devour,
        fromEnemy = o.fromEnemy or false,
        element = o.element,
        artKey = o.artKey,
        animTime = 0,
        angle = math.atan(-o.dy, o.dx),
    }
    table.insert(B.list, b)
    return b
end

--- 敌人弹幕（简化：直线飞行，碰玩家造成伤害）
---@param artKey string|nil 自定义飞行贴图（图集键）；缺省用矢量兜底
---@param hitArtKey string|nil 命中时播放的贴图（图集键）
function B.spawnEnemyBullet(x, y, dx, dy, speed, dmg, color, gravity, element, artKey, hitArtKey)
    local b = B.spawn({
        x = x, y = y, dx = dx, dy = dy, speed = speed,
        dmg = dmg, color = color, range = Config.BULLETS.enemyRange, fromEnemy = true, element = element,
        artKey = artKey,
    })
    if b then
        b.gravity = gravity or 0
        b.radius = Config.BULLETS.enemyRadius
        b.hitArtKey = hitArtKey
    end
end

function B.clear()
    B.list = {}
    stickCount = 0
end

--- 更新
---@param dt number
---@param ctx table { enemies: table[], hitEnemy: fun(enemy, bullet), hitPlayer: fun(bullet), playerPos: Vector2 }
function B.update(dt, ctx)
    local i = 1
    while i <= #B.list do
        local b = B.list[i]
        if b.dead then
            if b.state == "stick" then stickCount = math.max(0, stickCount - 1) end
            table.remove(B.list, i)
        else
            b.life = b.life - dt
            b.animTime = b.animTime + dt

            if b.state == "stick" then
                -- 黏附：静止，倒计时，仍可对接触敌人造成伤害一次
                b.stickTimer = b.stickTimer - dt
                if b.stickTimer <= 0 then b.dead = true end
            elseif b.state == "hover" then
                -- 悬停：停止移动，倒计时
                b.vx, b.vy = 0, 0
                b.stickTimer = b.stickTimer - dt
                if b.stickTimer <= 0 then b.dead = true end
            else
                -- 追踪（鮟鱇鱼气态）
                if b.homing and ctx.enemies then
                    local best, bestD = nil, Config.BULLETS.homingRange
                    for _, e in ipairs(ctx.enemies) do
                        if not e.dead then
                            local d = math.huge
                            if e.node then
                                local ep = e.node.position2D
                                d = math.sqrt((ep.x - b.x) ^ 2 + (ep.y - b.y) ^ 2)
                            end
                            if d < bestD then best, bestD = e, d end
                        end
                    end
                    if best and best.node then
                        local ep = best.node.position2D
                        local ax, ay = ep.x - b.x, ep.y - b.y
                        local len = math.sqrt(ax * ax + ay * ay)
                        if len > 0.01 then
                            local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
                            local tx, ty = ax / len * speed, ay / len * speed
                            b.vx = b.vx + (tx - b.vx) * math.min(1, dt * Config.BULLETS.homingTurn)
                            b.vy = b.vy + (ty - b.vy) * math.min(1, dt * Config.BULLETS.homingTurn)
                        end
                    end
                end

                if b.gravity and b.gravity > 0 then
                    b.vy = b.vy - b.gravity * dt
                end

                b.x = b.x + b.vx * dt
                b.y = b.y + b.vy * dt

                -- 尾迹
                table.insert(b.trail, { x = b.x, y = b.y })
                if #b.trail > Config.BULLETS.trailMax then table.remove(b.trail, 1) end

                -- 可破坏箱：玩家弹幕命中箱子 → 扣血（箱子在 isSolid 里也算地形）
                if not b.dead and CRATE_CHECK and not b.fromEnemy then
                    local crate = CRATE_CHECK(b.x, b.y)
                    if crate then
                        GS.emit("bulletImpact", b)
                        if CRATE_HIT then CRATE_HIT(crate, b.dmg) end
                        b.dead = true
                    end
                end

                -- 地形碰撞
                if not b.dead and TERRAIN_CHECK and TERRAIN_CHECK(b.x, b.y) then
                    if b.opts.bounceMax and b.bounceCount < b.opts.bounceMax then
                        -- 藤壶固态：反弹（简化：速度反向）
                        b.bounceCount = b.bounceCount + 1
                        b.vx, b.vy = -b.vx * Config.BULLETS.bounceKeep, -b.vy * Config.BULLETS.bounceKeep
                        b.x = b.x + b.vx * dt * 2
                        b.y = b.y + b.vy * dt * 2
                        GS.emit("bulletBounce")
                    elseif b.opts.stickDur then
                        -- 藤壶液态：黏附在地形上
                        b.state = "stick"
                        b.stickTimer = b.opts.stickDur
                        stickCount = stickCount + 1
                    else
                        GS.emit("bulletImpact", b)
                        b.dead = true
                    end
                end

                -- 保留最后非零方向，追踪/反弹更新动画，黏附/悬停不突然转向。
                if b.vx * b.vx + b.vy * b.vy > 0.0001 then
                    b.angle = math.atan(-b.vy, b.vx)
                end

                -- 射程终点：藤壶气态悬停
                if not b.dead and b.life <= 0 and b.opts.hoverDur then
                    b.state = "hover"
                    b.stickTimer = b.opts.hoverDur
                end
            end

            -- 寿命到期
            if b.life <= 0 and b.state == "fly" and not b.opts.hoverDur then
                b.dead = true
            end

            -- 与敌人 / 玩家碰撞
            if not b.dead then
                if b.fromEnemy then
                    if ctx.hitPlayer then ctx.hitPlayer(b) end
                elseif ctx.enemies and ctx.hitEnemy then
                    for _, e in ipairs(ctx.enemies) do
                        if not e.dead and not b.hitEnemies[e.uid] and e.node then
                            local ep = e.node.position2D
                            local rr = e.radius + b.radius
                            if (ep.x - b.x) ^ 2 + (ep.y - b.y) ^ 2 <= rr * rr then
                                GS.emit("bulletImpact", b)
                                ctx.hitEnemy(e, b)
                                b.hitEnemies[e.uid] = true
                                if b.devour and e.tier == "small" then
                                    -- 青蛙液态：吞噬小怪（一击必杀）
                                    if b.opts.onDevour then b.opts.onDevour() end
                                    GS.emit("devour", e)
                                elseif b.opts.stickDur then
                                    -- 黏附到敌人
                                    b.state = "stick"
                                    b.stickTimer = b.opts.stickDur
                                    b.stickTo = e.uid
                                    stickCount = stickCount + 1
                                else
                                    b.dead = true
                                end
                                break
                            end
                        end
                    end
                end
            end
            i = i + 1
        end
    end
end

return B
