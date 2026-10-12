-- ============================================================================
-- core/hazards.lua - 环境与机关交互系统 (P0-6)
-- 水源 / 火焰 / 低温区 / 海绵 / 泉眼 / 压板开关 / 电力接口 / 电子门 / 烟雾报警器
-- 规则来源: docs/场景机制.txt
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local P = require "core/player"

---@class Hazards
local H = {}

---@class Hazard
---@field kind string  water/fire/weakfire/cold/sponge/spring/plate/door/alarm/outlet
---@field x number
---@field y number
---@field w number
---@field h number
---@field id string|nil
---@field active boolean
---@field usedUp boolean     水源被吸干
---@field respawnTimer number 泉眼重置关卡水源
---@field animTime number
---@field cellKey string|nil  编辑器 1 基 col:row，id 仍是旧 0 基端点
---@field powered boolean
---@field needsPower boolean
---@field open boolean
---@field platePressed boolean
---@field charges number
---@field maxCharges number
---@field temporary boolean
---@field touched boolean
---@field waveDelay number|nil
---@field absorbTimer number|nil
---@field drainTimer number|nil
---@field swollen number|nil
---@field sprayTimer number|nil
---@field doorRef table|nil

---@type Hazard[]
H.list = {}
---@type {from:string, to:string}[]
H.wires = {}

-- 温度接触设计（米；沿用圆形玩家对矩形区域的包围盒检测）：
--      [ 火区 A ][ 火区 B ]       [ 低温区 ]
--              (玩家 r)
-- 同温区域的连续接触合并：无接触→有接触时只转换一级；火伤害独立持续结算。
-- 重叠火浪不能同帧连变两次；离开全部同温区域后，重新进入才再次转换。
-- 进入用当前形态半径；退出保留接触期间最大半径，防缩小后假离开再重入。
-- 延迟激活/失效在检测前处理；火冷同时接触各算一次，固定先升温再降温。
-- 冲刺只记录几何接触，不消耗温度转换；结束后仍接触才补算，已转换过的不重复。
local fireInside = false
local coldInside = false
local fireApplied = false
local coldApplied = false
local fireRadius = 0.0
local coldRadius = 0.0

function H.resetTemperatureContacts()
    fireInside = false
    coldInside = false
    fireApplied = false
    coldApplied = false
    fireRadius = 0
    coldRadius = 0
end

GS.on("playerTeleport", function() H.resetTemperatureContacts() end)

function H.clear()
    H.list = {}
    H.wires = {}
    H.resetTemperatureContacts()
end

--- 添加机关/危险区
---@param o table { kind, x, y, w, h, id, cellKey, needsPower, open, active }
---@return Hazard
function H.add(o)
    local needsPower = o.needsPower
    if type(needsPower) ~= "boolean" then needsPower = o.kind == "door" or o.kind == "alarm" end
    local charges = o.charges or 1
    ---@type Hazard
    local hz = {
        kind = o.kind, x = o.x, y = o.y,
        w = o.w or (o.kind == "door" and 0.8 or 1),
        h = o.h or (o.kind == "door" and 2.8 or 1),
        id = o.id, cellKey = o.cellKey, active = o.active ~= false, usedUp = false,
        respawnTimer = 0, animTime = math.random() * 10,
        powered = o.powered == true, needsPower = needsPower,
        -- 电控门初始不借 open 绕过电路；手动常开门必须明确 needsPower=false。
        open = not needsPower and o.open == true,
        platePressed = false,
        charges = charges,
        maxCharges = charges,
        temporary = o.temporary or false,
        touched = false,
    }
    table.insert(H.list, hz)
    return hz
end

local function overlaps(hz, px, py, r)
    return px + r > hz.x - hz.w / 2 and px - r < hz.x + hz.w / 2
        and py + r > hz.y - hz.h / 2 and py - r < hz.y + hz.h / 2
end

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- 电路契约：plate（固态压板）或 outlet（装备电鳗且靠近） → door/alarm。
-- 连线只用真实 id，不按距离自动配线；多个输入按 OR 聚合，不受连线顺序影响。
---@param fromId string
---@param toId string
---@return boolean
function H.addWire(fromId, toId)
    if type(fromId) ~= "string" or fromId == "" or type(toId) ~= "string" or toId == "" then return false end
    local src, dst = H.getById(fromId), H.getById(toId)
    if not src or not dst or (src.kind ~= "plate" and src.kind ~= "outlet")
        or (dst.kind ~= "door" and dst.kind ~= "alarm") then return false end
    for _, wire in ipairs(H.wires) do
        if wire.from == fromId and wire.to == toId then return false end
    end
    table.insert(H.wires, { from = fromId, to = toId })
    return true
end

--- 查询某 id 的机关
---@param id string|nil
---@return Hazard|nil
function H.getById(id)
    if not id then return nil end
    for _, hz in ipairs(H.list) do
        if hz.id == id then return hz end
    end
    return nil
end

-- 接触区域（米）设计：
--   [压板矩形 w×h]∩(固态玩家 r)  OR  电鳗玩家距 [接口中心]≤1.6
--                                ↓ 指定连线 → 门/报警器
-- 压板沿用原矩形重叠，不增设实体；相切不压下，失活/死亡/离开立即清信号。
-- 当帧先采样全部输入再赋值每个输出一次；断电不改 active，避免门永远无法重启。
-- 无输入的电控门关闭，电控报警停止；显式 needsPower=false 才使用手动模式。
---@param playerHasEel boolean
function H.updateCircuit(playerHasEel)
    local livePlayer = P.node ~= nil and not P.dead
    local pp = livePlayer and P.node.position2D or Vector2(0, 0)
    local pr = Config.FORMS[P.form].radius
    ---@type table<string, Hazard>
    local byId = {}
    ---@type table<string, boolean>
    local inputs = {}
    for _, hz in ipairs(H.list) do
        if hz.id then byId[hz.id] = hz end
        if hz.kind == "plate" then
            local pressed = hz.active and not hz.usedUp and livePlayer and P.form == "solid"
                and overlaps(hz, pp.x, pp.y, pr)
            if pressed ~= hz.platePressed then
                hz.platePressed = pressed
                GS.emit("plateChanged", hz, pressed)
            end
            hz.powered = pressed
        elseif hz.kind == "outlet" then
            hz.powered = hz.active and not hz.usedUp and livePlayer and playerHasEel
                and dist(pp.x, pp.y, hz.x, hz.y) <= 1.6
        end
    end
    for _, wire in ipairs(H.wires) do
        local src, dst = byId[wire.from], byId[wire.to]
        if src and dst and (src.kind == "plate" or src.kind == "outlet")
            and (dst.kind == "door" or dst.kind == "alarm") then
            inputs[wire.to] = inputs[wire.to] == true or src.powered == true
        end
    end
    for _, hz in ipairs(H.list) do
        if hz.kind == "door" or hz.kind == "alarm" then
            hz.powered = hz.active and not hz.usedUp
                and (not hz.needsPower or (hz.id ~= nil and inputs[hz.id] == true))
            if hz.kind == "door" and hz.needsPower then
                local wasOpen = hz.open
                hz.open = hz.powered
                if hz.open ~= wasOpen then GS.emit(hz.open and "doorOpen" or "doorClose", hz) end
            end
        end
    end
end

--- 每帧更新
---@param dt number
---@param playerHasEel boolean
function H.update(dt, playerHasEel)
    if not P.node or P.dead then
        H.updateCircuit(false)
        return
    end
    local pp = P.node.position2D
    local pr = Config.FORMS[P.form].radius

    local fireProbe = fireInside and math.max(pr, fireRadius) or pr
    local coldProbe = coldInside and math.max(pr, coldRadius) or pr
    ---@type Hazard[]
    local touchingFire = {}
    local touchingCold = false
    for _, hz in ipairs(H.list) do
        hz.animTime = hz.animTime + dt
        if hz.respawnTimer > 0 then hz.respawnTimer = hz.respawnTimer - dt end
        if hz.waveDelay then
            hz.waveDelay = hz.waveDelay - dt
            if hz.waveDelay <= 0 then
                hz.waveDelay = nil
                hz.active = true
            end
        end
        if hz.temporary and hz.respawnTimer <= 0 and not hz.waveDelay then
            hz.active = false
            if hz.kind == "water" then hz.usedUp = true end
        end
        if hz.active then
            if (hz.kind == "fire" or hz.kind == "weakfire") and not hz.usedUp
                and overlaps(hz, pp.x, pp.y, fireProbe) then
                touchingFire[#touchingFire + 1] = hz
            elseif hz.kind == "cold" and overlaps(hz, pp.x, pp.y, coldProbe) then
                touchingCold = true
            end
        end
    end

    local hasFire = #touchingFire > 0
    if not hasFire then fireApplied = false end
    if not touchingCold then coldApplied = false end
    local dodging = P.isDodging()
    local fireEntered = hasFire and not fireApplied and not dodging
    local coldEntered = touchingCold and not coldApplied and not dodging
    fireInside = hasFire
    coldInside = touchingCold
    fireRadius = hasFire and fireProbe or 0
    coldRadius = touchingCold and coldProbe or 0
    if fireEntered then fireApplied = true end
    if coldEntered then coldApplied = true end
    if hasFire and not dodging then
        local before = P.form
        if fireEntered then P.heatStep() end
        -- 持续灼烧仍受原无敌时间及火抗饰品约束，不重复触发升温。
        P.changeWater(-1, Config.DMG.FIRE)
        for _, hz in ipairs(touchingFire) do
            if hz.kind == "weakfire" and before == "liquid" then
                hz.usedUp = true
                GS.emit("fireExtinguished", hz)
            elseif hz.kind == "fire" and fireEntered then
                GS.emit("touchFire", hz)
            end
        end
    end
    if coldEntered then P.onColdHit() end
    -- 致命火伤不能在同帧继续触发泉眼回血/存档，造成满水量的死亡状态。
    if P.dead then
        H.updateCircuit(false)
        return
    end
    -- 温度转换后的半径用于其余接触；电路在所有形态变化（含泉眼）后采样。
    local contactRadius = Config.FORMS[P.form].radius

    for _, hz in ipairs(H.list) do
        if P.dead then break end
        if hz.active then
            local hit = overlaps(hz, pp.x, pp.y, contactRadius)

            if hz.kind == "water" then
                -- 凝珠：吸收一次回 3 格水量（absorbAmount），随后消失
                if hit and not hz.usedUp and GS.save.water < GS.maxWater() then
                    hz.absorbTimer = (hz.absorbTimer or 0) + dt
                    if hz.absorbTimer >= 0.05 then
                        hz.absorbTimer = 0
                        local bonus = GS.hasRelic("waterPendant") and Config.ECONOMY.waterPendantBonus or 0
                        P.changeWater(Config.ECONOMY.absorbAmount + bonus)
                        hz.charges = (hz.charges or 1) - 1
                        GS.emit("absorbWater", hz)
                        if hz.charges <= 0 then
                            hz.usedUp = true
                            GS.emit("waterUsedUp", hz)
                        end
                    end
                elseif not hit then
                    hz.absorbTimer = 0
                end

            elseif hz.kind == "fire" or hz.kind == "weakfire" or hz.kind == "cold" then
                -- 已在上方统一处理温度进入沿与持续火伤害。

            elseif hz.kind == "sponge" then
                -- 海绵：吸水陷阱（扣水量），吸水后膨胀一段时间失效
                if hit and not hz.usedUp then
                    hz.drainTimer = (hz.drainTimer or 0) + dt
                    if hz.drainTimer >= 0.8 then
                        hz.drainTimer = 0
                        P.changeWater(-1, Config.DMG.TRAP)
                        hz.swollen = (hz.swollen or 0) + 1
                        GS.emit("spongeDrain", hz)
                        if hz.swollen >= 2 then
                            hz.usedUp = true
                            hz.respawnTimer = 6.0
                        end
                    end
                else
                    hz.drainTimer = 0
                end
                if hz.usedUp and hz.respawnTimer <= 0 then
                    hz.usedUp = false
                    hz.swollen = 0
                    hz.drainTimer = 0
                end

            elseif hz.kind == "spring" then
                -- 泉眼：存档点，触碰回满水、变回液态、重置关卡中的水
                if hit and not hz.touched then
                    hz.touched = true
                    P.toLiquid()
                    P.healFull()
                    GS.save.spring = hz.id or GS.save.spring
                    GS.save.water = GS.maxWater()
                    GS.saveGame()
                    GS.emit("springTouch", hz)
                    print("[泉眼] 存档于 " .. tostring(hz.id))
                end
                if not hit then hz.touched = false end

            elseif hz.kind == "plate" or hz.kind == "outlet" or hz.kind == "door" or hz.kind == "alarm" then
                -- 接触处理结束后统一采样电路与报警喷洒，避免列表顺序/上一帧信号。
            end
        end

        -- 临时区域回收（BOSS 火区/冰区、报警器喷出的水）: 倒计时结束即失效
        if hz.temporary and hz.respawnTimer <= 0 and not hz.waveDelay then
            hz.active = false
            if hz.kind == "water" then hz.usedUp = true end
        end
    end
    H.updateCircuit(playerHasEel)
    if P.dead then return end
    -- 当前帧供电 + 当前形态决定是否喷洒；离开/断电归零，禁止攒零碎接触时间。
    -- 新水源不进入本轮更新，保持完整 5 秒寿命，不把大 dt 直接扣到刚生成的水上。
    local count = #H.list
    for i = 1, count do
        local hz = H.list[i]
        if hz.kind == "alarm" then
            if hz.active and hz.powered and P.form == "gas"
                and dist(pp.x, pp.y, hz.x, hz.y) <= 2.5 and pp.y < hz.y then
                hz.sprayTimer = (hz.sprayTimer or 0) + dt
                if hz.sprayTimer >= 1.0 then
                    hz.sprayTimer = 0
                    GS.emit("alarmSpray", hz)
                    local water = H.add({ kind = "water", x = hz.x, y = hz.y - 2.0,
                        w = 0.8, h = 0.8, charges = 1, temporary = true })
                    water.respawnTimer = 5.0
                end
            else
                hz.sprayTimer = 0
            end
        end
    end
end

--- 泉眼重置关卡中的水（存档点机制）
function H.resetWaters()
    for _, hz in ipairs(H.list) do
        if hz.kind == "water" and not hz.temporary then
            hz.usedUp = false
            hz.charges = hz.maxCharges or 1
            hz.absorbTimer = 0
        end
        if hz.kind == "sponge" then
            hz.usedUp = false
            hz.swollen = 0
            hz.respawnTimer = 0
            hz.drainTimer = 0
        end
        if hz.kind == "weakfire" then
            hz.usedUp = false
        end
    end
    GS.emit("watersReset")
end

return H
