-- ============================================================================
-- core/level.lua - 关卡加载器：根据关卡数据创建物理地形、机关、敌人、物品
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local H = require "core/hazards"
local E = require "core/enemies"

---@class Level
local L = {}

L.def = nil
L.scene = nil
L.platformRects = {}   -- 静态矩形（供地形碰撞查询）
L.crateNodes = {}      -- 可破坏箱
L.itemNodes = {}       -- 拾取物
L.doorNodes = {}       -- 电子门实体（开关闭合碰撞）
L.storyZones = {}      -- 剧情触发区
L.decorList = {}       -- 装饰（纯视觉）

--- 地形碰撞检测（弹幕/敌人用）
---@param x number
---@param y number
---@return boolean
function L.isSolid(x, y)
    for _, r in ipairs(L.platformRects) do
        if x >= r.x - r.w / 2 and x <= r.x + r.w / 2
            and y >= r.y - r.h / 2 and y <= r.y + r.h / 2 then
            return true
        end
    end
    for _, c in ipairs(L.crateNodes) do
        if not c.destroyed then
            if x >= c.x - c.w / 2 and x <= c.x + c.w / 2
                and y >= c.y - c.h / 2 and y <= c.y + c.h / 2 then
                return true
            end
        end
    end
    -- 关闭的电子门也是实体
    for _, d in ipairs(L.doorNodes) do
        if not d.hz.open then
            if x >= d.x - d.w / 2 and x <= d.x + d.w / 2
                and y >= d.y - d.h / 2 and y <= d.y + d.h / 2 then
                return true
            end
        end
    end
    return false
end

--- 加载关卡
---@param scene Scene
---@param def table
function L.load(scene, def)
    L.scene = scene
    L.def = def
    L.platformRects = {}
    L.crateNodes = {}
    L.itemNodes = {}
    L.doorNodes = {}
    L.storyZones = {}
    L.decorList = {}
    H.clear()
    E.clear()

    -- 地形
    for _, p in ipairs(def.platforms or {}) do
        local node = scene:CreateChild("Platform")
        node:SetPosition2D(p.x, p.y)
        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(p.w, p.h)
        shape.friction = 0.6
        shape.restitution = 0
        shape.categoryBits = Config.COL.TERRAIN
        shape.maskBits = 0xFFFF
        table.insert(L.platformRects, { x = p.x, y = p.y, w = p.w, h = p.h })
    end

    -- 手绘多边形碰撞体（静态，与瓦片平台并存）
    for _, poly in ipairs(def.collisionPolygons or {}) do
        local verts = poly.vertices
        if type(verts) == "table" and #verts >= 3 and #verts <= 8 then
            local node = scene:CreateChild("CollisionPolygon")
            node:SetPosition2D(0, 0)
            local body = node:CreateComponent("RigidBody2D")
            body.bodyType = BT_STATIC
            local shape = node:CreateComponent("CollisionPolygon2D")
            -- 逐个设置顶点：SetVertices 的 tolua 绑定在部分平台不接受 Lua 数组。
            shape:SetVertexCount(#verts)
            for i, v in ipairs(verts) do
                shape:SetVertex(i - 1, Vector2(v.x, v.y))
            end
            shape.friction = 0.6
            shape.restitution = 0
            shape.categoryBits = Config.COL.TERRAIN
            shape.maskBits = 0xFFFF
        end
    end

    -- 机关/危险区
    for _, hz in ipairs(def.hazards or {}) do
        local h = H.add(hz)
        -- 电子门实体（关闭时阻挡）
        if hz.kind == "door" then
            local node = scene:CreateChild("Door")
            node:SetPosition2D(hz.x, hz.y)
            local body = node:CreateComponent("RigidBody2D")
            body.bodyType = BT_STATIC
            local shape = node:CreateComponent("CollisionBox2D")
            shape:SetSize(h.w, h.h)
            shape.friction = 0.4
            shape.categoryBits = Config.COL.TERRAIN
            shape.maskBits = 0xFFFF
            local door = { x = h.x, y = h.y, w = h.w, h = h.h,
                           node = node, shape = shape, open = h.open, hz = h, id = h.id }
            node:SetEnabled(not h.open)
            table.insert(L.doorNodes, door)
            h.doorRef = door
        end
    end

    -- 电线
    H.wires = {}
    for _, w in ipairs(def.wires or {}) do
        if type(w) == "table" and not H.addWire(w.from, w.to) then
            print("[Level] 忽略无效/重复电路端点: " .. tostring(w.from) .. " -> " .. tostring(w.to))
        end
    end

    -- 敌人
    for _, ed in ipairs(def.enemies or {}) do
        E.spawn(scene, ed.key, ed.x, ed.y)
    end

    -- 可破坏箱
    for _, c in ipairs(def.crates or {}) do
        local node = scene:CreateChild("Crate")
        node:SetPosition2D(c.x, c.y)
        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(c.w, c.h)
        shape.friction = 0.5
        shape.categoryBits = Config.COL.TERRAIN
        shape.maskBits = 0xFFFF
        table.insert(L.crateNodes, {
            x = c.x, y = c.y, w = c.w, h = c.h, hp = c.hp or 4,
            node = node, shape = shape, destroyed = false, hitFlash = 0,
        })
    end

    -- 拾取键沿用旧地图进度命名空间；扫描序号在地图内容不变时稳定。
    for idx, it in ipairs(def.items or {}) do
        local flagKey = it.flagKey or ("picked_" .. (def.progressId or def.id) .. "_" .. idx)
        table.insert(L.itemNodes, {
            kind = it.kind, x = it.x, y = it.y,
            fishKey = it.fishKey, relicKey = it.relicKey,
            flagKey = flagKey, taken = false, animTime = math.random() * 10,
        })
    end

    -- 剧情触发区
    for _, s in ipairs(def.story or {}) do
        table.insert(L.storyZones, {
            id = s.id, x = s.x, y = s.y, r = s.r, once = s.once ~= false,
            mode = s.mode, text = s.text, fired = false,
        })
    end

    GS.save.visited[def.id] = true

    -- 恢复已拾取标记
    for _, item in ipairs(L.itemNodes) do
        if GS.save.flags[item.flagKey] then
            item.taken = true
        end
    end
    -- 已触发的一次性剧情
    for _, z in ipairs(L.storyZones) do
        if z.once and GS.save.flags["story_" .. (def.progressId or def.id) .. "_" .. z.id] then
            z.fired = true
        end
    end

    print("[Level] 加载完成: " .. def.name .. " (" .. def.id .. ")")
end

--- 查询某点上的可破坏箱（用于弹幕命中判定）
---@param x number
---@param y number
---@return table|nil
function L.crateAt(x, y)
    for _, c in ipairs(L.crateNodes) do
        if not c.destroyed then
            local hw, hh = c.w * 0.5, c.h * 0.5
            if x >= c.x - hw and x <= c.x + hw and y >= c.y - hh and y <= c.y + hh then
                return c
            end
        end
    end
    return nil
end

--- 破坏箱
---@param crate table
---@param dmg number
---@return boolean destroyed
function L.damageCrate(crate, dmg)
    if crate.destroyed then return false end
    crate.hp = crate.hp - dmg
    crate.hitFlash = 0.15
    GS.emit("crateHit", crate)
    if crate.hp <= 0 then
        crate.destroyed = true
        crate.node:Remove()
        GS.emit("crateBroken", crate)
        return true
    end
    return false
end

--- 电子门状态同步（每帧由 main 调用）
function L.syncDoors()
    for _, d in ipairs(L.doorNodes) do
        local hzOpen = d.hz.open
        if hzOpen ~= d.open then
            d.open = hzOpen
            d.node:SetEnabled(not hzOpen)
        end
    end
end

--- 剧情触发检测
---@param px number
---@param py number
function L.checkStory(px, py)
    for _, z in ipairs(L.storyZones) do
        if not z.fired then
            local dx, dy = px - z.x, py - z.y
            if dx * dx + dy * dy <= z.r * z.r then
                z.fired = true
                if z.once then
                    GS.save.flags["story_" .. (L.def.progressId or L.def.id) .. "_" .. z.id] = true
                end
                GS.emit("story", z)
            end
        elseif not z.once then
            -- 可重复触发（如记录纸条）：离开再进入可重读
            local dx, dy = px - z.x, py - z.y
            if dx * dx + dy * dy > (z.r + 0.5) * (z.r + 0.5) then
                z.fired = false
            end
        end
    end
end

--- 物品拾取检测
---@param px number
---@param py number
---@param radius number
function L.checkItems(px, py, radius)
    for _, it in ipairs(L.itemNodes) do
        if not it.taken then
            local dx, dy = px - it.x, py - it.y
            local rr = radius + 0.55
            if dx * dx + dy * dy <= rr * rr then
                it.taken = true
                GS.save.flags[it.flagKey] = true
                GS.emit("itemPickup", it)
            end
        end
    end
end

--- 出口检测
---@param px number
---@param py number
---@return table|nil exit
function L.checkExit(px, py)
    for _, ex in ipairs(L.def.exits or {}) do
        if px >= ex.x - ex.w / 2 and px <= ex.x + ex.w / 2
            and py >= ex.y - ex.h / 2 and py <= ex.y + ex.h / 2 then
            return ex
        end
    end
    return nil
end

return L
