-- ============================================================================
-- core/render.lua - NanoVG 世界渲染
-- 主题: 废弃实验室（烧焦痕迹、闪烁顶灯、结霜出口）
-- 渲染顺序: 世界底色 → 整图背景 → 背景瓦片 → 旧地形兜底 → 地形瓦片 → 实体/玩家 → 前景瓦片 → 后效
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local B = require "core/bullets"
local L = require "core/level"
local A = require "core/abilities"
local FISH = require "data/fish"
local MON = require "data/monsters"
local Art = require "core/art"
local MeleeFX = require "core/melee_fx"
local CombatFX = require "core/combat_fx"
local EditorRender = require "core.editor_render"
local TileRender = require "core.tile_render"
local TS = require "core.tilesets"
local Backgrounds = require "core.map_backgrounds"
local CameraBounds = require "core.camera_bounds"

---@class Render
local R = {}

---@type NVGContextWrapper?
R.vg = nil
---@type number
R.camX = 0.0
---@type number
R.camY = 0.0
R.viewW = 16.0   -- 视口宽（米）
R.viewH = 12.0
R.ppu = 60.0     -- pixels per unit（运行时按屏幕计算）
R.screenW = 1280.0
R.screenH = 720.0
R.shakeTime = 0.0
R.shakeMag = 0.0
R.flashTime = 0.0
R.flashColor = { 255, 255, 255 }

-- 特效粒子池
R.particles = {}
R.toasts = {}       -- 由 UI 层处理, 这里只发事件
R.droppedShells = {} -- {x,y,vx,vy,life}
---@type {x:number, y:number, time:number, duration:number}[]
R.bulletImpacts = {}
local impactsBound = false

-- 位移残影 {x, y, form, life, maxLife}
---@type table[]
local dashTrail = {}
local dashTrailTimer = 0.0

-- 可破坏箱碎片 {x, y, vx, vy, rot, vrot, size, life, maxLife, color}
---@type table[]
local crateShards = {}

local function rgba(c, a)
    return nvgRGBA(c[1], c[2], c[3], a or 255)
end

---@param vg NVGContextWrapper
function R.init(vg)
    R.vg = assert(vg, "[Render] 初始化缺少 NanoVG 上下文")
    if not impactsBound then
        impactsBound = true
        GS.on("bulletImpact", function(b)
            if b.artKey ~= "bullet_ice" then return end
            table.insert(R.bulletImpacts, {
                x = b.x, y = b.y, time = 0,
                duration = Art.duration("bullet_ice_hit"),
            })
            if #R.bulletImpacts > 48 then table.remove(R.bulletImpacts, 1) end
        end)
        MeleeFX.bind()
        CombatFX.bind()
        -- 可破坏箱：受击迸溅小碎屑；破碎时炸开一圈碎块
        GS.on("crateHit", function(crate)
            for i = 1, 5 do
                local ang = math.random() * math.pi * 2
                local spd = 2.0 + math.random() * 2.5
                table.insert(crateShards, {
                    x = crate.x, y = crate.y,
                    vx = math.cos(ang) * spd, vy = math.sin(ang) * spd + 1.0,
                    rot = math.random() * math.pi * 2, vrot = (math.random() - 0.5) * 12,
                    size = 0.05 + math.random() * 0.06,
                    life = 0.35, maxLife = 0.35,
                    color = { 170, 120, 70 },
                })
            end
            while #crateShards > 200 do table.remove(crateShards, 1) end
        end)
        GS.on("crateBroken", function(crate)
            for i = 1, 16 do
                local ang = math.random() * math.pi * 2
                local spd = 3.0 + math.random() * 4.5
                table.insert(crateShards, {
                    x = crate.x + (math.random() - 0.5) * crate.w,
                    y = crate.y + (math.random() - 0.5) * crate.h,
                    vx = math.cos(ang) * spd, vy = math.sin(ang) * spd + 2.0,
                    rot = math.random() * math.pi * 2, vrot = (math.random() - 0.5) * 16,
                    size = 0.06 + math.random() * 0.10,
                    life = 0.55 + math.random() * 0.3, maxLife = 0.85,
                    color = math.random() < 0.35 and { 210, 170, 110 } or { 150, 100, 55 },
                })
            end
            while #crateShards > 200 do table.remove(crateShards, 1) end
        end)
        -- 敌人受击：血液飞溅（伤害数字由 CombatFX 维护）
        GS.on("enemyHit", function(e, dmg)
            if not e or not e.node then return end
            local ep = e.node.position2D
            -- 颗粒感血液飞溅（向受击反方向/四周发散）
            local HF = Config.HIT_FX
            for i = 1, HF.bloodCount do
                local ang = math.random() * math.pi * 2
                local spd = HF.bloodSpeed * (0.4 + math.random() * 0.8)
                table.insert(R.particles, {
                    x = ep.x, y = ep.y,
                    vx = math.cos(ang) * spd,
                    vy = math.sin(ang) * spd + 1.5,
                    life = HF.bloodLife * (0.6 + math.random() * 0.8),
                    maxLife = HF.bloodLife,
                    color = HF.bloodColor,
                    size = 0.03 + math.random() * 0.05,
                })
            end
            while #R.particles > 300 do table.remove(R.particles, 1) end
        end)
    end
end

--- 切关/死亡时取消未播放完的战斗特效，避免残留到新关卡。
function R.clearMeleeSlashes()
    MeleeFX.clear()
    CombatFX.clear()
end

--- 屏幕尺寸变化时更新；游戏传边界，编辑器传 nil，不修改请求的 Config.VIEW_H。
function R.updateScreen(w, h, viewH, bounds)
    CameraBounds.fitScreen(R, w, h, viewH or Config.VIEW_H, bounds)
end

--- 世界坐标 → 屏幕坐标
function R.w2s(wx, wy)
    return (wx - R.camX) * R.ppu + R.screenW / 2,
           R.screenH / 2 - (wy - R.camY) * R.ppu
end

function R.setCamera(x, y)
    R.camX = x
    R.camY = y
end

function R.shake(mag, dur)
    -- 取较大者，但加 NaN/负值防御（调参面板可能传入异常值）
    mag = (type(mag) == "number" and mag == mag and mag > 0) and mag or 0
    dur = (type(dur) == "number" and dur == dur and dur > 0) and dur or 0
    R.shakeMag = math.max(R.shakeMag, mag)
    R.shakeTime = math.max(R.shakeTime, dur)
end

function R.flash(color, dur)
    R.flashColor = color
    R.flashTime = dur
end

--- 粒子
function R.spawnParticles(x, y, color, count, speed, life)
    for i = 1, count do
        local a = math.random() * math.pi * 2
        local s = (0.3 + math.random() * 0.7) * (speed or 3)
        table.insert(R.particles, {
            x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s + 1,
            life = (life or 0.6) * (0.6 + math.random() * 0.8),
            maxLife = life or 0.6, color = color, size = 0.05 + math.random() * 0.07,
        })
    end
    -- 上限保护
    while #R.particles > 300 do table.remove(R.particles, 1) end
end

function R.dropShell(x, y)
    table.insert(R.droppedShells, {
        x = x, y = y, vx = (math.random() - 0.5) * 3, vy = 2 + math.random() * 2,
        life = 30, collected = false,
    })
end

--- 抖动/闪光衰减。独立于 R.update：即使游戏暂停/死亡/对话也必须衰减，
--- 否则一次抖动后进入这些状态，shakeTime 永不递减 → 屏幕持续抖动。
---@param dt number
function R.updateShake(dt)
    if R.shakeTime > 0 then
        R.shakeTime = R.shakeTime - dt
        if R.shakeTime <= 0 then
            R.shakeTime = 0
            R.shakeMag = 0
        end
    end
    if R.flashTime > 0 then R.flashTime = R.flashTime - dt end
end

function R.update(dt)
    Art.update(dt)
    for i = #R.bulletImpacts, 1, -1 do
        local impact = R.bulletImpacts[i]
        impact.time = impact.time + dt
        if impact.time >= impact.duration then table.remove(R.bulletImpacts, i) end
    end

    -- 位移残影采集：位移/飞鱼冲刺进行中按间隔记录位置
    if (P.dashing or P.flyDashing) and P.node then
        dashTrailTimer = dashTrailTimer - dt
        if dashTrailTimer <= 0 then
            dashTrailTimer = Config.DASH.trailInterval
            local pp = P.node.position2D
            table.insert(dashTrail, {
                x = pp.x, y = pp.y, form = P.form,
                life = 0.28, maxLife = 0.28,
            })
            while #dashTrail > 24 do table.remove(dashTrail, 1) end
        end
    else
        dashTrailTimer = 0.0
    end
    for i = #dashTrail, 1, -1 do
        local g = dashTrail[i]
        g.life = g.life - dt
        if g.life <= 0 then table.remove(dashTrail, i) end
    end

    MeleeFX.update(dt)
    CombatFX.update(dt)

    -- 可破坏箱碎片：重力 + 地形反弹/停靠 + 旋转
    for i = #crateShards, 1, -1 do
        local s = crateShards[i]
        s.life = s.life - dt
        if s.life <= 0 then
            table.remove(crateShards, i)
        else
            s.vy = s.vy - 18 * dt
            local nx = s.x + s.vx * dt
            local ny = s.y + s.vy * dt
            if L.isSolid and L.isSolid(nx, ny) then
                -- 撞地：水平衰减 + 竖直弹跳
                s.vx = s.vx * 0.5
                s.vy = -s.vy * 0.35
                s.vrot = s.vrot * 0.6
                if math.abs(s.vy) < 0.6 then s.vy = 0 end
            else
                s.x, s.y = nx, ny
            end
            s.rot = s.rot + s.vrot * dt
        end
    end

    -- 粒子
    local i = 1
    while i <= #R.particles do
        local p = R.particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(R.particles, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy - 6 * dt
            i = i + 1
        end
    end

    -- 掉落贝壳（简易物理 + 磁吸拾取）
    i = 1
    local pp = P.node and P.node.position2D
    while i <= #R.droppedShells do
        local s = R.droppedShells[i]
        s.life = s.life - dt
        if s.life <= 0 or s.collected then
            table.remove(R.droppedShells, i)
        else
            s.vy = s.vy - 14 * dt
            s.x = s.x + s.vx * dt
            s.y = s.y + s.vy * dt
            -- 落地
            if L.isSolid(s.x, s.y - 0.15) then
                s.y = s.y + 0.05
                s.vy = 0
                s.vx = s.vx * 0.8
            end
            -- 磁吸
            if pp then
                local d = math.sqrt((pp.x - s.x) ^ 2 + (pp.y - s.y) ^ 2)
                if d < 2.0 then
                    s.vx = s.vx + (pp.x - s.x) * dt * 8
                    s.vy = s.vy + (pp.y - s.y) * dt * 8
                end
                if d < 0.5 then
                    s.collected = true
                    GS.addShells(Config.ECONOMY.dropShellValue)
                    GS.emit("shellGet")
                end
            end
            i = i + 1
        end
    end
end

-- ===================== 绘制 =====================

local function drawCrates(vg, t)
    for _, c in ipairs(L.crateNodes) do
        if not c.destroyed then
            local sx, sy = R.w2s(c.x - c.w / 2, c.y + c.h / 2)
            local w, h = c.w * R.ppu, c.h * R.ppu
            -- 实验品箱：金属色 + 标签
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, w, h, 4)
            nvgFillColor(vg, c.hitFlash > 0 and nvgRGBA(255, 200, 150, 255) or nvgRGBA(110, 96, 80, 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(60, 52, 42, 255))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
            -- 标签
            nvgBeginPath(vg)
            nvgRect(vg, sx + w * 0.2, sy + h * 0.35, w * 0.6, h * 0.3)
            nvgFillColor(vg, nvgRGBA(220, 210, 180, 255))
            nvgFill(vg)
            if c.hitFlash > 0 then c.hitFlash = c.hitFlash - 0.016 end
        end
    end
end

local function drawHazards(vg, t)
    for _, hz in ipairs(H.list) do
        local sx, sy = R.w2s(hz.x - hz.w / 2, hz.y + hz.h / 2)
        local w, h = hz.w * R.ppu, hz.h * R.ppu
        if sx + w < -80 or sx > R.screenW + 80 then goto continue end

        if hz.kind == "water" and not hz.usedUp then
            -- 凝珠：发光水珠（圆润珠子 + 内芯 + 脉动光晕 + 上下浮动）
            local bob = math.sin(t * 2.2 + hz.x * 1.7) * h * 0.12
            local cx, cy = sx + w / 2, sy + h / 2 + bob
            local r = math.min(w, h) * 0.46
            local pulse = 0.7 + math.sin(t * 3 + hz.x) * 0.3
            local glow = nvgRadialGradient(vg, cx, cy, r * 0.4, r * 2.4,
                nvgRGBA(120, 210, 255, math.floor(90 * pulse)), nvgRGBA(120, 210, 255, 0))
            nvgBeginPath(vg); nvgCircle(vg, cx, cy, r * 2.4); nvgFillPaint(vg, glow); nvgFill(vg)
            local g = nvgRadialGradient(vg, cx - r * 0.35, cy - r * 0.35, r * 0.1, r * 1.15,
                nvgRGBA(215, 245, 255, 245), nvgRGBA(60, 150, 235, 235))
            nvgBeginPath(vg); nvgCircle(vg, cx, cy, r); nvgFillPaint(vg, g); nvgFill(vg)
            nvgBeginPath(vg); nvgCircle(vg, cx, cy, r * 0.42)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(150 + 60 * pulse))); nvgFill(vg)
            nvgBeginPath(vg); nvgCircle(vg, cx - r * 0.34, cy - r * 0.38, r * 0.16)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 235)); nvgFill(vg)

        elseif hz.kind == "fire" or hz.kind == "weakfire" then
            if not hz.usedUp then
                -- 火焰：多层摆动火舌
                local scale = hz.kind == "weakfire" and 0.6 or 1.0
                for li = 1, 3 do
                    local ph = t * (5 + li) + hz.x * 3 + li * 2
                    local fx = sx + w / 2 + math.sin(ph) * w * 0.22
                    local fy = sy + h
                    local fh = h * scale * (1.3 - li * 0.25) * (0.85 + math.sin(ph * 1.7) * 0.15)
                    local fw = w * (0.42 - li * 0.08)
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, fx - fw, fy)
                    nvgBezierTo(vg, fx - fw * 0.6, fy - fh * 0.6, fx - fw * 0.2, fy - fh * 0.8, fx, fy - fh)
                    nvgBezierTo(vg, fx + fw * 0.2, fy - fh * 0.8, fx + fw * 0.6, fy - fh * 0.6, fx + fw, fy)
                    nvgClosePath(vg)
                    local col = li == 1 and { 255, 90, 30 } or (li == 2 and { 255, 150, 40 } or { 255, 220, 120 })
                    nvgFillColor(vg, rgba(col, 200))
                    nvgFill(vg)
                end
                -- 光晕
                local gl = nvgRadialGradient(vg, sx + w / 2, sy + h * 0.6, 4, w * 1.6,
                    nvgRGBA(255, 140, 50, 70), nvgRGBA(255, 140, 50, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, sx + w / 2, sy + h * 0.6, w * 1.6)
                nvgFillPaint(vg, gl)
                nvgFill(vg)
            end

        elseif hz.kind == "cold" then
            -- 低温区：冰晶地板 + 寒气
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, w, h)
            local g = nvgLinearGradient(vg, sx, sy, sx, sy + h,
                nvgRGBA(160, 220, 255, 120), nvgRGBA(90, 160, 230, 160))
            nvgFillPaint(vg, g)
            nvgFill(vg)
            -- 冰尖
            for si = 0, math.floor(w / 14) do
                local ix = sx + si * 14 + 4
                nvgBeginPath(vg)
                nvgMoveTo(vg, ix, sy)
                nvgLineTo(vg, ix + 5, sy - 10 - math.sin(si * 2.3) * 5)
                nvgLineTo(vg, ix + 10, sy)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(200, 240, 255, 180))
                nvgFill(vg)
            end
            -- 寒气粒子
            for pi = 1, 3 do
                local px2 = sx + ((t * 20 + pi * 60 + hz.x * 30) % w)
                local py2 = sy - 10 - math.sin(t * 2 + pi) * 12
                nvgBeginPath(vg)
                nvgCircle(vg, px2, py2, 3)
                nvgFillColor(vg, nvgRGBA(220, 245, 255, 100))
                nvgFill(vg)
            end

        elseif hz.kind == "sponge" then
            -- 海绵：黄色多孔（吸水后变深膨胀）
            local swollen = hz.swollen or 0
            local sw = w * (1 + swollen * 0.15)
            local sh = h * (1 + swollen * 0.15)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx + (w - sw) / 2, sy + (h - sh) / 2, sw, sh, 6)
            nvgFillColor(vg, hz.usedUp and nvgRGBA(120, 110, 80, 255)
                or nvgRGBA(230, 200, 90, 255))
            nvgFill(vg)
            -- 孔洞
            nvgFillColor(vg, nvgRGBA(180, 150, 60, 255))
            for hi2 = 1, 5 do
                local hx = sx + w * (0.2 + (hi2 % 3) * 0.3)
                local hy = sy + h * (0.3 + math.floor(hi2 / 3) * 0.35)
                nvgBeginPath(vg)
                nvgCircle(vg, hx, hy, 3)
                nvgFill(vg)
            end

        elseif hz.kind == "spring" then
            -- 泉眼：奇怪的饮水机形象（存档点）
            local cx2, cy2 = R.w2s(hz.x, hz.y)
            -- 底座
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx2 - 22, cy2 - 6, 44, 30, 4)
            nvgFillColor(vg, nvgRGBA(90, 100, 120, 255))
            nvgFill(vg)
            -- 水胆（发光）
            local glow = 0.6 + math.sin(t * 2.5) * 0.25
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx2 - 14, cy2 - 42, 28, 38, 10)
            local g2 = nvgLinearGradient(vg, cx2, cy2 - 42, cx2, cy2,
                nvgRGBA(140, 220, 255, math.floor(255 * glow)), nvgRGBA(60, 150, 230, 255))
            nvgFillPaint(vg, g2)
            nvgFill(vg)
            -- 气泡
            for bi = 1, 3 do
                local by = cy2 - 10 - ((t * 20 + bi * 12) % 28)
                nvgBeginPath(vg)
                nvgCircle(vg, cx2 - 5 + bi * 5, by, 2)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
                nvgFill(vg)
            end
            -- 光晕
            local sg = nvgRadialGradient(vg, cx2, cy2 - 20, 5, 60,
                nvgRGBA(120, 200, 255, 60), nvgRGBA(120, 200, 255, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx2, cy2 - 20, 60)
            nvgFillPaint(vg, sg)
            nvgFill(vg)

        elseif hz.kind == "plate" then
            -- 压板开关
            local press = hz.platePressed and 4 or 0
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy + press, w, h - press, 3)
            nvgFillColor(vg, hz.platePressed and nvgRGBA(120, 220, 140, 255) or nvgRGBA(150, 150, 165, 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(60, 60, 70, 255))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

        elseif hz.kind == "door" then
            -- 电子门（开时半透明下滑）
            local d = hz.doorRef
            if d then
                local openOff = d.open and h * 0.85 or 0
                if openOff < h then
                    nvgBeginPath(vg)
                    nvgRect(vg, sx, sy + openOff, w, h - openOff)
                    nvgFillColor(vg, d.open and nvgRGBA(100, 160, 200, 100) or nvgRGBA(120, 130, 155, 255))
                    nvgFill(vg)
                    -- 门框灯
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx + w / 2, sy - 6, 4)
                    nvgFillColor(vg, d.open and nvgRGBA(120, 255, 140, 255) or nvgRGBA(255, 100, 80, 255))
                    nvgFill(vg)
                end
            end

        elseif hz.kind == "outlet" then
            -- 电力接口
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, w, h, 4)
            nvgFillColor(vg, nvgRGBA(70, 75, 95, 255))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, sx + w / 2, sy + h / 2, w * 0.25)
            nvgFillColor(vg, hz.powered and nvgRGBA(255, 240, 120, 255) or nvgRGBA(110, 120, 140, 255))
            nvgFill(vg)
            -- 电火花
            if hz.powered then
                nvgStrokeColor(vg, nvgRGBA(255, 250, 150, 220))
                nvgStrokeWidth(vg, 1.5)
                for si2 = 1, 3 do
                    local a2 = t * 8 + si2 * 2.1
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, sx + w / 2, sy + h / 2)
                    nvgLineTo(vg, sx + w / 2 + math.cos(a2) * w, sy + h / 2 + math.sin(a2) * h)
                    nvgStroke(vg)
                end
            end

        elseif hz.kind == "alarm" then
            -- 烟雾报警器
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, w, h, 3)
            nvgFillColor(vg, nvgRGBA(180, 80, 70, 255))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, sx + w / 2, sy + h / 2, 3)
            nvgFillColor(vg, hz.powered and nvgRGBA(120, 255, 120, 255) or nvgRGBA(80, 80, 80, 255))
            nvgFill(vg)
        end
        ::continue::
    end
end

local function drawPortals(vg, t)
    local portals = L.def and L.def.portals
    if not portals then return end
    for _, p in ipairs(portals) do
        local sx, sy = R.w2s(p.x, p.y)
        local w, h = (p.w or 1.6) * R.ppu, (p.h or 2.6) * R.ppu
        if sx + w < -80 or sx - w > R.screenW + 80 then goto continue end
        local cx, cy = sx, sy      -- p.y 为传送门中心（与 checkExit 检测区一致）
        local rx, ry = w * 0.5, h * 0.5
        -- 外发光
        local pulse = 0.7 + math.sin(t * 3) * 0.3
        local glow = nvgRadialGradient(vg, cx, cy, ry * 0.4, ry * 1.5,
            nvgRGBA(150, 110, 255, math.floor(70 * pulse)), nvgRGBA(150, 110, 255, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, cx, cy, rx * 1.8, ry * 1.3)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
        -- 门体（椭圆漩涡）
        local g = nvgRadialGradient(vg, cx, cy, ry * 0.1, ry,
            nvgRGBA(230, 210, 255, 245), nvgRGBA(90, 60, 200, 240))
        nvgBeginPath(vg)
        nvgEllipse(vg, cx, cy, rx, ry)
        nvgFillPaint(vg, g)
        nvgFill(vg)
        -- 旋转的水流纹
        for k = 1, 3 do
            local a0 = t * (1.4 + k * 0.3) + k * 2.0
            nvgBeginPath(vg)
            nvgEllipse(vg, cx, cy, rx * (0.3 + k * 0.22), ry * (0.3 + k * 0.22))
            nvgStrokeColor(vg, nvgRGBA(220, 235, 255, math.floor(150 - k * 30)))
            nvgStrokeWidth(vg, 2)
            -- 用 arc 做开口，模拟旋转
            nvgStroke(vg)
        end
        -- 门框
        nvgBeginPath(vg)
        nvgEllipse(vg, cx, cy, rx, ry)
        nvgStrokeColor(vg, nvgRGBA(180, 150, 255, 220))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        -- 核心亮点
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, rx * 0.18 * pulse)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgFill(vg)
        ::continue::
    end
end

local function drawItems(vg, t)
    local ITEMS = require("data/items").ITEMS
    local RELICS = require("data/items").RELICS
    for _, it in ipairs(L.itemNodes) do
        if not it.taken then
            local bob = math.sin(t * 2.5 + it.x) * 0.12
            local sx, sy = R.w2s(it.x, it.y + bob)
            if sx > -60 and sx < R.screenW + 60 then
                if it.kind == "shell" then
                    -- 贝壳
                    nvgBeginPath(vg)
                    nvgArc(vg, sx, sy, 9, math.pi, 0, NVG_CW)
                    nvgClosePath(vg)
                    nvgFillColor(vg, rgba(Config.PAL.shell))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(200, 170, 110, 255))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                    for ri = 1, 3 do
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, sx, sy)
                        nvgLineTo(vg, sx + math.cos(math.pi + ri * math.pi / 4) * 9,
                                     sy + math.sin(math.pi + ri * math.pi / 4) * 9)
                        nvgStrokeColor(vg, nvgRGBA(200, 170, 110, 200))
                        nvgStrokeWidth(vg, 1)
                        nvgStroke(vg)
                    end
                elseif it.kind == "fish" then
                    local def = FISH[it.fishKey]
                    if def then
                        -- 全部鱼种均有上传图集；缺失时保留原图形兜底。
                        if not Art.drawFish(vg, it.fishKey, t, sx, sy, 38, 26, -1) then
                            local c = def.color
                            nvgBeginPath(vg)
                            nvgEllipse(vg, sx, sy, 14, 8)
                            nvgFillColor(vg, rgba(c))
                            nvgFill(vg)
                            nvgBeginPath(vg)
                            nvgMoveTo(vg, sx - 12, sy)
                            nvgLineTo(vg, sx - 20, sy - 6)
                            nvgLineTo(vg, sx - 20, sy + 6)
                            nvgClosePath(vg)
                            nvgFillColor(vg, rgba(c, 200))
                            nvgFill(vg)
                            nvgBeginPath(vg)
                            nvgCircle(vg, sx + 7, sy - 2, 2)
                            nvgFillColor(vg, nvgRGBA(20, 25, 35, 255))
                            nvgFill(vg)
                        end
                        -- 名字提示
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, 11)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
                        nvgText(vg, sx, sy + 12, def.name, nil)
                    end
                elseif it.kind == "relic" then
                    local def = RELICS[it.relicKey]
                    if def then
                        -- 饰品：发光菱形
                        local gl = nvgRadialGradient(vg, sx, sy, 3, 26,
                            rgba(def.color, 120), rgba(def.color, 0))
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, 26)
                        nvgFillPaint(vg, gl)
                        nvgFill(vg)
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, sx, sy - 11)
                        nvgLineTo(vg, sx + 8, sy)
                        nvgLineTo(vg, sx, sy + 11)
                        nvgLineTo(vg, sx - 8, sy)
                        nvgClosePath(vg)
                        nvgFillColor(vg, rgba(def.color))
                        nvgFill(vg)
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, 11)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
                        nvgText(vg, sx, sy + 14, def.name, nil)
                    end
                else
                    local def = ITEMS[it.kind]
                    if def then
                        -- 通用道具：发光圆
                        local gl = nvgRadialGradient(vg, sx, sy, 2, 20,
                            rgba(def.color, 100), rgba(def.color, 0))
                        nvgBeginPath(vg)
                        nvgCircle(vg, sx, sy, 20)
                        nvgFillPaint(vg, gl)
                        nvgFill(vg)
                        nvgBeginPath(vg)
                        if it.kind == "symbShard" or it.kind == "symbCore" then
                            -- 共生碎片/核心: 三角
                            nvgMoveTo(vg, sx, sy - 10)
                            nvgLineTo(vg, sx + 9, sy + 7)
                            nvgLineTo(vg, sx - 9, sy + 7)
                            nvgClosePath(vg)
                        else
                            nvgCircle(vg, sx, sy, 9)
                        end
                        nvgFillColor(vg, rgba(def.color))
                        nvgFill(vg)
                    end
                end
            end
        end
    end
    -- 掉落贝壳
    for _, s in ipairs(R.droppedShells) do
        local sx, sy = R.w2s(s.x, s.y)
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, 6, math.pi, 0, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, rgba(Config.PAL.shell, 230))
        nvgFill(vg)
    end
end

local function drawEnemyShape(vg, e, sx, sy, r)
    local def = e.def
    local c = e.hitFlash > 0 and { 255, 255, 255 } or def.color
    local ac = def.accent
    local t = e.animTime

    if def.ai == "dasher" then
        -- 变异飞蝇：椭圆身体 + 摆动翅膀
        local wing = math.sin(t * 30) * 8
        nvgBeginPath(vg)
        nvgEllipse(vg, sx - r * 0.3, sy - r * 0.8, r * 0.9, math.abs(wing) * 0.4 + 3)
        nvgFillColor(vg, nvgRGBA(230, 235, 245, 90))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgEllipse(vg, sx + r * 0.3, sy - r * 0.8, r * 0.9, math.abs(wing) * 0.4 + 3)
        nvgFillColor(vg, nvgRGBA(230, 235, 245, 90))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy, r, r * 0.7)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx + e.facing * r * 0.5, sy - r * 0.2, r * 0.22)
        nvgFillColor(vg, rgba(ac))
        nvgFill(vg)

    elseif def.ai == "chaser" then
        -- 清洁机器人-01：只画一套动画——攻击优先，其余移动循环；缺图集时回退矢量。
        local atkTime = E.attackAnimTime(def)
        local drew
        if e.atkAnimTimer > 0 then
            drew = Art.drawEnemy(vg, "enemy_cleaner01_attack", atkTime - e.atkAnimTimer, sx, sy, r, e.facing)
        else
            drew = Art.drawEnemy(vg, "enemy_cleaner01_move", t, sx, sy, r, e.facing)
        end
        if drew then return end
        -- 兜底：方身 + 独眼 + 轮子
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - r, sy - r, r * 2, r * 2, 4)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx + e.facing * r * 0.35, sy - r * 0.2, r * 0.35)
        nvgFillColor(vg, e.state == "attack" and nvgRGBA(255, 80, 60, 255) or rgba(ac))
        nvgFill(vg)
        -- 挥动的手臂
        local armA = e.state == "attack" and math.sin(e.stateTimer * 30) * 0.8 or math.sin(t * 3) * 0.3
        nvgStrokeColor(vg, rgba(c, 220))
        nvgStrokeWidth(vg, 4)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + e.facing * r, sy)
        nvgLineTo(vg, sx + e.facing * (r + 10), sy - 6 + armA * 10)
        nvgStroke(vg)
        -- 轮子
        nvgBeginPath(vg)
        nvgCircle(vg, sx - r * 0.5, sy + r, r * 0.3)
        nvgCircle(vg, sx + r * 0.5, sy + r, r * 0.3)
        nvgFillColor(vg, nvgRGBA(50, 55, 70, 255))
        nvgFill(vg)

    elseif def.ai == "shooter" then
        -- 清洁机器人-02：只画一套动画——攻击优先，其余待机循环；缺图集时回退矢量。
        local c2AtkTime = E.attackAnimTime(def)
        local c2Drew
        if e.atkAnimTimer > 0 then
            c2Drew = Art.drawEnemy(vg, "enemy_cleaner02_attack", c2AtkTime - e.atkAnimTimer, sx, sy, r, e.facing)
        else
            c2Drew = Art.drawEnemy(vg, "enemy_cleaner02_idle", t, sx, sy, r, e.facing)
        end
        if c2Drew then return end
        -- 兜底：细高身 + 炮口
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - r * 0.7, sy - r * 1.2, r * 1.4, r * 2.4, 5)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, sx + e.facing * r * 0.7, sy - r * 0.3, e.facing * r * 0.9, r * 0.5)
        nvgFillColor(vg, rgba(ac))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy - r * 0.7, r * 0.3)
        nvgFillColor(vg, e.state == "aim" and nvgRGBA(255, 200, 60, 255) or nvgRGBA(90, 220, 160, 255))
        nvgFill(vg)

    elseif def.ai == "fixed" then
        -- 喷孢菌：只画一套动画——攻击优先，其余待机循环；缺图集时回退矢量。
        local sporeAtkTime = E.attackAnimTime(def)
        local sporeDrew
        if e.atkAnimTimer > 0 then
            sporeDrew = Art.drawEnemy(vg, "enemy_spore_attack", sporeAtkTime - e.atkAnimTimer, sx, sy, r, e.facing)
        else
            sporeDrew = Art.drawEnemy(vg, "enemy_spore_idle", t, sx, sy, r, e.facing)
        end
        if sporeDrew then return end
        -- 兜底：菌伞 + 斑点
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy + r * 0.3, r * 1.1, math.pi, 0, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, sx - r * 0.25, sy + r * 0.3, r * 0.5, r * 0.8)
        nvgFillColor(vg, nvgRGBA(200, 190, 200, 255))
        nvgFill(vg)
        for si = 1, 3 do
            nvgBeginPath(vg)
            nvgCircle(vg, sx - r * 0.5 + si * r * 0.5, sy - r * 0.2 + (si % 2) * r * 0.3, r * 0.15)
            nvgFillColor(vg, rgba(ac, 200))
            nvgFill(vg)
        end

    elseif def.ai == "lightSeeker" then
        -- 趋光菌兽：只画一套动画——扑咬优先，追击/寻光用移动，其余待机；缺图集回退矢量。
        local lsAtkTime = E.attackAnimTime(def)
        local lsDrew
        if e.atkAnimTimer > 0 then
            lsDrew = Art.drawEnemy(vg, "enemy_lightseeker_attack", lsAtkTime - e.atkAnimTimer, sx, sy, r, e.facing)
        elseif e.state == "chase" or e.state == "seek" then
            lsDrew = Art.drawEnemy(vg, "enemy_lightseeker_move", t, sx, sy, r, e.facing)
        else
            lsDrew = Art.drawEnemy(vg, "enemy_lightseeker_idle", t, sx, sy, r, e.facing)
        end
        if lsDrew then return end
        -- 兜底：兽形 + 发光菌斑
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy, r * 1.2, r * 0.9)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
        -- 四肢
        nvgStrokeColor(vg, rgba(c, 220))
        nvgStrokeWidth(vg, 4)
        for li = -1, 1, 2 do
            local la = math.sin(t * 8 + li) * 4
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + li * r * 0.6, sy + r * 0.6)
            nvgLineTo(vg, sx + li * r * 0.7, sy + r * 1.2 + la)
            nvgStroke(vg)
        end
        -- 发光斑点
        local gl = 0.5 + math.sin(t * 4) * 0.3
        for si = 1, 3 do
            nvgBeginPath(vg)
            nvgCircle(vg, sx - r * 0.5 + si * r * 0.5, sy - r * 0.3, 3)
            nvgFillColor(vg, rgba(ac, math.floor(255 * gl)))
            nvgFill(vg)
        end
        -- 眼
        nvgBeginPath(vg)
        nvgCircle(vg, sx + e.facing * r * 0.7, sy - r * 0.25, 3)
        nvgFillColor(vg, e.aggro and nvgRGBA(255, 100, 80, 255) or nvgRGBA(250, 250, 180, 255))
        nvgFill(vg)

    elseif def.ai == "crab" then
        -- 裂钳蟹：攻击/预警用攻击图集（按 clawSide 取左/右螯 4 帧），否则移动循环。
        local crabAtkTime = E.attackAnimTime(def)
        local crabOffset = (e.clawSide == -1) and 4 or 0
        local crabDrew
        local crabKey = (e.pendingAttack == "ranged") and "enemy_crab_ranged" or "enemy_crab_melee"
        if e.atkAnimTimer > 0 then
            crabDrew = Art.drawEnemy(vg, crabKey, crabAtkTime - e.atkAnimTimer, sx, sy, r, e.facing, crabOffset)
        elseif e.warnTimer > 0 then
            -- 预警：定格在攻击动画首帧（抬起对应螯）
            crabDrew = Art.drawEnemy(vg, crabKey, 0, sx, sy, r, e.facing, crabOffset)
        else
            crabDrew = Art.drawEnemy(vg, "enemy_crab_move", t, sx, sy, r, e.facing)
        end
        if crabDrew then return end
        -- 兜底：宽身 + 双大螯（预警时抬起）
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy, r * 1.1, r * 0.75)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
        -- 腿
        nvgStrokeColor(vg, rgba(c, 230))
        nvgStrokeWidth(vg, 3)
        for li = -2, 2 do
            if li ~= 0 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, sx + li * r * 0.4, sy + r * 0.4)
                nvgLineTo(vg, sx + li * r * 0.6, sy + r * 1.0)
                nvgStroke(vg)
            end
        end
        -- 双螯（warn 状态抬起预警）
        local clawY = e.state == "warn" and -r * 0.9 or 0
        for ci = -1, 1, 2 do
            local cx2 = sx + ci * r * 1.3
            nvgBeginPath(vg)
            nvgEllipse(vg, cx2, sy + clawY, r * 0.45, r * 0.35)
            nvgFillColor(vg, rgba(ac, 255))
            nvgFill(vg)
            -- 螯口
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx2 + ci * r * 0.2, sy + clawY - r * 0.2)
            nvgLineTo(vg, cx2 + ci * r * 0.55, sy + clawY - r * 0.35)
            nvgLineTo(vg, cx2 + ci * r * 0.2, sy + clawY + r * 0.05)
            nvgStrokeColor(vg, nvgRGBA(120, 60, 50, 255))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
        -- 眼柄
        for ci = -1, 1, 2 do
            nvgBeginPath(vg)
            nvgCircle(vg, sx + ci * r * 0.3, sy - r * 0.75, 3.5)
            nvgFillColor(vg, nvgRGBA(30, 30, 40, 255))
            nvgFill(vg)
        end

    elseif def.ai == "manyHands" then
        -- 门帝克3型：高躯干 + 4 只手（2 远程 2 近战）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - r * 0.8, sy - r * 1.3, r * 1.6, r * 2.6, 6)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
        -- 4 只手
        for hi = 1, 4 do
            local side = hi <= 2 and -1 or 1
            local idx = (hi - 1) % 2
            local armT = e.state == "attack" and math.sin(t * 20) * 6 or math.sin(t * 2 + hi) * 4
            local hx = sx + side * (r * 1.0 + idx * r * 0.4)
            local hy = sy - r * 0.8 + idx * r * 1.0 + armT
            nvgStrokeColor(vg, rgba(c, 230))
            nvgStrokeWidth(vg, 4)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + side * r * 0.6, sy - r * 0.5 + idx * r * 0.9)
            nvgLineTo(vg, hx, hy)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, hx, hy, 5)
            nvgFillColor(vg, rgba(ac))
            nvgFill(vg)
        end
        -- 核心眼
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy - r * 0.6, r * 0.35)
        nvgFillColor(vg, e.state == "attack" and nvgRGBA(255, 90, 60, 255) or rgba(ac, 220))
        nvgFill(vg)

    elseif def.ai == "bossIceFire" then
        -- 冰火人：故障温控装置，左火右冰
        local rr = r
        -- 主体
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - rr, sy - rr * 1.3, rr * 2, rr * 2.6, 10)
        nvgFillColor(vg, nvgRGBA(70, 75, 95, 255))
        nvgFill(vg)
        -- 左半火焰
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - rr, sy - rr * 1.3, rr, rr * 2.6, 10)
        local fg = nvgLinearGradient(vg, sx - rr, sy, sx, sy,
            rgba(Config.PAL.bossFire, e.phase >= 2 and 230 or 140), rgba(Config.PAL.bossFire, 40))
        nvgFillPaint(vg, fg)
        nvgFill(vg)
        -- 右半寒冰
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy - rr * 1.3, rr, rr * 2.6, 10)
        local ig = nvgLinearGradient(vg, sx + rr, sy, sx, sy,
            rgba(Config.PAL.bossIce, e.phase >= 3 and 230 or 140), rgba(Config.PAL.bossIce, 40))
        nvgFillPaint(vg, ig)
        nvgFill(vg)
        -- 喷口
        nvgBeginPath(vg)
        nvgCircle(vg, sx - rr * 0.6, sy - rr * 0.2, rr * 0.28)
        nvgFillColor(vg, rgba(Config.PAL.bossFire))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx + rr * 0.6, sy - rr * 0.2, rr * 0.28)
        nvgFillColor(vg, rgba(Config.PAL.bossIce))
        nvgFill(vg)
        -- 中央核心（阶段变色）
        local coreC = e.phase == 1 and { 220, 220, 230 } or (e.phase == 2 and Config.PAL.bossFire or Config.PAL.bossIce)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy - rr * 0.5, rr * 0.3 * (1 + math.sin(t * 5) * 0.1))
        nvgFillColor(vg, rgba(coreC))
        nvgFill(vg)
        -- 腿
        nvgStrokeColor(vg, nvgRGBA(50, 55, 70, 255))
        nvgStrokeWidth(vg, 8)
        for li = -1, 1, 2 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + li * rr * 0.5, sy + rr * 1.2)
            nvgLineTo(vg, sx + li * rr * 0.6, sy + rr * 1.6)
            nvgStroke(vg)
        end
    else
        -- 默认圆形
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r)
        nvgFillColor(vg, rgba(c))
        nvgFill(vg)
    end
end

local function drawEnemies(vg)
    for _, e in ipairs(E.list) do
        if not e.dead and e.node then
            local pos = e.node.position2D
            local sx, sy = R.w2s(pos.x, pos.y)
            local r = e.radius * R.ppu
            if sx > -120 and sx < R.screenW + 120 then
                -- 受击缩放：压扁回弹（横向拉宽、纵向压扁），带一点"打击感"
                local sq = 0
                if e.hitSquash and e.hitSquash > 0 then
                    local k = e.hitSquash / Config.HIT_FX.squashTime   -- 1→0
                    sq = Config.HIT_FX.squashAmount * k
                end
                if sq > 0 then
                    nvgSave(vg)
                    nvgTranslate(vg, sx, sy)
                    nvgScale(vg, 1 + sq * 0.5, 1 - sq * 0.5)
                    nvgTranslate(vg, -sx, -sy)
                    drawEnemyShape(vg, e, sx, sy, r)
                    nvgRestore(vg)
                else
                    drawEnemyShape(vg, e, sx, sy, r)
                end

                -- 状态效果指示
                if e.poisonTimer > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy - r - 12, 4)
                    nvgFillColor(vg, nvgRGBA(120, 220, 100, 200))
                    nvgFill(vg)
                end
                if e.paralysisTimer > 0 then
                    nvgStrokeColor(vg, nvgRGBA(255, 250, 130, 220))
                    nvgStrokeWidth(vg, 1.5)
                    nvgBeginPath(vg)
                    for zi = 1, 3 do
                        local za = e.animTime * 10 + zi * 2.1
                        nvgMoveTo(vg, sx + math.cos(za) * r * 1.3, sy + math.sin(za) * r * 1.3)
                        nvgLineTo(vg, sx + math.cos(za + 0.5) * r * 1.6, sy + math.sin(za + 0.5) * r * 1.6)
                    end
                    nvgStroke(vg)
                end
                if e.blindTimer > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy - r - 8, 6)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 150))
                    nvgFill(vg)
                end

                -- 血条：所有敌人都有（小怪也显示）；受伤后短暂弹出，或常驻
                local HF = Config.HIT_FX
                local showBar = HF.hpBarAlwaysShow or (e.hpBarTimer and e.hpBarTimer > 0)
                    or e.tier == "boss" or e.tier == "elite"
                if showBar then
                    local bw = e.tier == "boss" and 200 or (e.tier == "elite" and 50 or 34)
                    local bh = e.tier == "boss" and 8 or (e.tier == "elite" and 5 or 4)
                    local bx = e.tier == "boss" and R.screenW / 2 - bw / 2 or sx - bw / 2
                    local by = e.tier == "boss" and 64 or sy - r - 18
                    -- 受击瞬间血条放大（打击反馈）
                    local barScale = 1
                    if e.hitSquash and e.hitSquash > 0 then
                        barScale = 1 + (e.hitSquash / HF.squashTime) * 0.35
                    end
                    if barScale ~= 1 then
                        nvgSave(vg)
                        nvgTranslate(vg, bx + bw / 2, by + bh / 2)
                        nvgScale(vg, barScale, barScale)
                        nvgTranslate(vg, -(bx + bw / 2), -(by + bh / 2))
                    end
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, bx - 1, by - 1, bw + 2, bh + 2, 3)
                    nvgFillColor(vg, nvgRGBA(20, 24, 34, 220))
                    nvgFill(vg)
                    local ratio = math.max(0, e.hp / (e.maxHp or e.def.hp))
                    -- 血条受击闪白：hp 条在受击瞬间亮白，快速回落到本色
                    local flashing = e.hitFlash and e.hitFlash > 0
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, bx, by, bw * ratio, bh, 2)
                    if flashing then
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    else
                        nvgFillColor(vg, e.tier == "boss"
                            and nvgRGBA(255, 120, 80, 255)
                            or (e.tier == "elite" and nvgRGBA(250, 200, 90, 255)
                                or nvgRGBA(240, 110, 110, 255)))
                    end
                    nvgFill(vg)
                    if barScale ~= 1 then nvgRestore(vg) end
                    if e.tier == "boss" then
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, 16)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                        nvgFillColor(vg, rgba(Config.PAL.text))
                        nvgText(vg, R.screenW / 2, by - 6, e.def.name .. " · P" .. e.phase, nil)
                    end
                end
            end
        end
    end
end

local function drawBullets(vg)
    for _, b in ipairs(B.list) do
        local sx, sy = R.w2s(b.x, b.y)
        if not b.dead and sx > -96 and sx < R.screenW + 96 and sy > -96 and sy < R.screenH + 96 then
            local r = b.radius * R.ppu
            -- 子弹素材尺寸系数：水弹/闪电素材偏小，需放大到有存在感
            local sizeMul = 2
            if b.artKey == "bullet_water" then
                sizeMul = Config.BULLETS.waterArtSizeMul
            elseif b.artKey == "bullet_lightning" then
                sizeMul = Config.BULLETS.lightningArtSizeMul
            end
            -- 敌人自定义贴图（如裂钳蟹石子）用固定尺寸，避免碰撞半径决定外观；
            -- 玩家弹幕仍按碰撞半径 × sizeMul 绘制。
            local drawSize = (b.fromEnemy and b.artKey) and (R.ppu * 0.62) or (r * sizeMul)
            local animated = b.artKey and Art.drawProjectile(vg, b.artKey, b.animTime, sx, sy, drawSize, b.angle)
            -- 新素材自带拖尾；只有下载前兜底与其他弹种保留原矢量尾迹。
            if not animated and #b.trail > 1 and b.state == "fly" then
                nvgStrokeColor(vg, rgba(b.color, 80))
                nvgStrokeWidth(vg, r * 0.9)
                nvgBeginPath(vg)
                for ti, tp in ipairs(b.trail) do
                    local tx, ty = R.w2s(tp.x, tp.y)
                    if ti == 1 then nvgMoveTo(vg, tx, ty) else nvgLineTo(vg, tx, ty) end
                end
                nvgStroke(vg)
            end
            -- 未替换弹种和加载前的主体兜底。
            if not animated then
                nvgBeginPath(vg)
                if b.isIce then
                    nvgMoveTo(vg, sx + r * 1.6, sy)
                    nvgLineTo(vg, sx, sy - r)
                    nvgLineTo(vg, sx - r * 1.2, sy)
                    nvgLineTo(vg, sx, sy + r)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(190, 235, 255, 240))
                else
                    nvgCircle(vg, sx, sy, r * (b.state == "stick" and 1.3 or 1))
                    local g = nvgRadialGradient(vg, sx - r * 0.3, sy - r * 0.3, 1, r * 1.4,
                        nvgRGBA(255, 255, 255, 220), rgba(b.color, 230))
                    nvgFillPaint(vg, g)
                end
                nvgFill(vg)
            end
            -- 黏附/悬停标识环
            if b.state == "stick" or b.state == "hover" then
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, r * 1.8)
                nvgStrokeColor(vg, rgba(b.color, 120))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end
            -- 鮟鱇鱼光弹发光
            if b.light then
                local lg = nvgRadialGradient(vg, sx, sy, 2, r * 5,
                    nvgRGBA(255, 245, 180, 90), nvgRGBA(255, 245, 180, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, r * 5)
                nvgFillPaint(vg, lg)
                nvgFill(vg)
            end
        end
    end

    -- 命中动画独立于已销毁的弹丸，只播放一次，不增加范围伤害。
    for _, impact in ipairs(R.bulletImpacts) do
        local sx, sy = R.w2s(impact.x, impact.y)
        if sx > -96 and sx < R.screenW + 96 and sy > -96 and sy < R.screenH + 96 then
            if impact.key then
                -- 自定义命中贴图（如裂钳蟹石子碎裂），按自身尺寸绘制。
                local sz = impact.key == "enemy_crab_stone_hit" and R.ppu * 0.7 or R.ppu * 0.5
                Art.drawProjectile(vg, impact.key, impact.time, sx, sy, sz, 0)
            else
                Art.drawProjectile(vg, "bullet_ice_hit", impact.time, sx, sy, R.ppu * 0.36, 0)
            end
        end
    end

    -- 电鳗液态环绕电场
    if A.orbitActive and A.orbitFx and P.node then
        local pp = P.node.position2D
        for oi = 1, 3 do
            local ox, oy = A.orbitPos(pp.x, pp.y, A.orbitAngle + oi * math.pi * 2 / 3)
            local sx, sy = R.w2s(ox, oy)
            local r = 0.18 * R.ppu
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, r)
            nvgFillColor(vg, nvgRGBA(250, 250, 140, 220))
            nvgFill(vg)
            -- 电弧连线
            local px2, py2 = R.w2s(pp.x, pp.y)
            nvgStrokeColor(vg, nvgRGBA(200, 200, 255, 90))
            nvgStrokeWidth(vg, 1.5)
            nvgBeginPath(vg)
            nvgMoveTo(vg, px2, py2)
            local mx = (px2 + sx) / 2 + math.sin(A.orbitAngle * 7 + oi) * 8
            local my = (py2 + sy) / 2 + math.cos(A.orbitAngle * 7 + oi) * 8
            nvgLineTo(vg, mx, my)
            nvgLineTo(vg, sx, sy)
            nvgStroke(vg)
        end
    end

    -- 电鳗固态周身电流
    if P.form == "solid" and A.selfZapDmg and A.selfZapDmg > 0 and P.node then
        local pp = P.node.position2D
        local sx, sy = R.w2s(pp.x, pp.y)
        local rr = A.selfZapRange * R.ppu
        nvgStrokeColor(vg, nvgRGBA(180, 180, 255, 130))
        nvgStrokeWidth(vg, 2)
        nvgBeginPath(vg)
        local segs = 12
        for si = 0, segs do
            local a2 = si / segs * math.pi * 2
            local wob = math.sin(a2 * 5 + R.t * 12) * 5
            local x2 = sx + math.cos(a2) * (rr + wob)
            local y2 = sy + math.sin(a2) * (rr * 0.8 + wob)
            if si == 0 then nvgMoveTo(vg, x2, y2) else nvgLineTo(vg, x2, y2) end
        end
        nvgClosePath(vg)
        nvgStroke(vg)
    end
end

local function drawDashTrail(vg)
    for _, g in ipairs(dashTrail) do
        local sx, sy = R.w2s(g.x, g.y)
        if sx > -60 and sx < R.screenW + 60 then
            local a = g.life / g.maxLife
            local c = Config.FORMS[g.form].color
            local r = Config.FORMS[g.form].radius * R.ppu * (0.6 + a * 0.4)
            nvgBeginPath(vg)
            nvgEllipse(vg, sx, sy, r, r * 0.9)
            nvgFillColor(vg, rgba(c, math.floor(90 * a)))
            nvgFill(vg)
        end
    end
end

--- 可破坏箱碎片：小方块旋转飞出，落地弹跳
local function drawCrateShards(vg)
    if #crateShards == 0 then return end
    for _, s in ipairs(crateShards) do
        local sx, sy = R.w2s(s.x, s.y)
        if sx > -40 and sx < R.screenW + 40 and sy > -40 and sy < R.screenH + 40 then
            local a = math.min(1, s.life / (s.maxLife * 0.7))
            local r = s.size * R.ppu
            nvgSave(vg)
            nvgTranslate(vg, sx, sy)
            nvgRotate(vg, s.rot)
            nvgBeginPath(vg)
            nvgRect(vg, -r, -r, r * 2, r * 2)
            nvgFillColor(vg, rgba(s.color, math.floor(255 * a)))
            nvgFill(vg)
            nvgRestore(vg)
        end
    end
end

--- 钩爪绳索（青蛙液态）：从玩家画到挂点的绳状水柱
local function drawGrapple(vg, t)
    if not P.grappling or not P.node then return end
    local pos = P.node.position2D
    local sx, sy = R.w2s(pos.x, pos.y)
    local hx, hy = R.w2s(P.grappleX, P.grappleY)
    -- 绳身：略带波动的粗线
    nvgStrokeColor(vg, nvgRGBA(150, 220, 160, 220))
    nvgStrokeWidth(vg, 4)
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy)
    local segs = 8
    for i = 1, segs - 1 do
        local k = i / segs
        local wob = math.sin(t * 20 + i) * 4
        nvgLineTo(vg, sx + (hx - sx) * k + wob, sy + (hy - sy) * k)
    end
    nvgLineTo(vg, hx, hy)
    nvgStroke(vg)
    -- 钩头
    nvgBeginPath(vg)
    nvgCircle(vg, hx, hy, 6)
    nvgFillColor(vg, nvgRGBA(110, 190, 90, 255))
    nvgFill(vg)
end

local function drawPlayer(vg, t)
    if not P.node then return end
    local pos = P.node.position2D
    local sx, sy = R.w2s(pos.x, pos.y)
    local f = Config.FORMS[P.form]
    local r = f.radius * R.ppu * (2 - P.squash) * 0.5
    local rY = f.radius * R.ppu * P.squash
    local c = f.color

    -- 位移中：半透明残像（表示闪避无敌状态）
    if P.dashing then
        nvgGlobalAlpha(vg, 0.55)
    elseif P.invuln > 0 and math.floor(t * 14) % 2 == 0 then
        -- 受击/无敌闪烁
        nvgGlobalAlpha(vg, 0.4)
    end

    local playerArt = Art.drawPlayer(vg, sx, sy, R.ppu)
    if not playerArt then
        -- 下载未完成时的轮廓兜底，真实图集就绪后自动替换。
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy, f.radius * R.ppu, f.radius * R.ppu)
        nvgFillColor(vg, rgba(c, 180))
        nvgFill(vg)
    end

    -- 格挡姿态：面朝方向的水盾弧（剑鱼固态举盾）
    if P.blocking then
        nvgBeginPath(vg)
        local a0 = P.facing > 0 and -0.9 or (math.pi - 0.9)
        nvgArc(vg, sx, sy, r * 1.5, a0, a0 + 1.8, P.facing > 0 and NVG_CW or NVG_CCW)
        nvgStrokeColor(vg, nvgRGBA(150, 220, 255, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    -- 格挡成功闪光
    if P.blockFlash > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r * 1.6)
        nvgStrokeColor(vg, nvgRGBA(200, 240, 255, math.floor(P.blockFlash * 900)))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    -- 受击红闪
    if P.hurtFlash > 0 then
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy, r * 1.1, rY * 1.1)
        nvgFillColor(vg, nvgRGBA(255, 80, 60, math.floor(P.hurtFlash * 400)))
        nvgFill(vg)
    end

    -- 变形闪光环
    if P.formFlash > 0 then
        local fr = r * (1.5 + (0.4 - P.formFlash) * 4)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, fr)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(P.formFlash * 500)))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    -- 鮟鱇鱼液态/固态光圈
    local fx = A.currentEffects()
    if fx.lightRange > 0 then
        local lr = fx.lightRange * R.ppu
        local lg = nvgRadialGradient(vg, sx, sy, 5, lr,
            nvgRGBA(255, 245, 190, 55), nvgRGBA(255, 245, 190, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, lr)
        nvgFillPaint(vg, lg)
        nvgFill(vg)
    end

    -- 装备的小鱼跟随（视觉表现"鱼在水精灵体内/身旁"）
    local equipped = GS.save and GS.save.equipped or {}
    for ei, fkey in ipairs(equipped) do
        local def = FISH[fkey]
        -- 已融入组合主角的鱼不再重复绕身显示，其他槽位仍跟随。
        local integrated = playerArt and Art.isIntegrated(fkey)
        if def and not integrated then
            local ea = t * 2.2 + ei * (math.pi * 2 / math.max(1, #equipped))
            local ex = sx + math.cos(ea) * (r + 14)
            local ey = sy + math.sin(ea) * (r + 10) * 0.7
            if not Art.drawFish(vg, fkey, t, ex, ey, 22, 18, P.facing) then
                nvgBeginPath(vg)
                nvgEllipse(vg, ex, ey, 7, 4)
                nvgFillColor(vg, rgba(def.color, 235))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, ex - 6, ey)
                nvgLineTo(vg, ex - 10, ey - 3)
                nvgLineTo(vg, ex - 10, ey + 3)
                nvgClosePath(vg)
                nvgFillColor(vg, rgba(def.color, 200))
                nvgFill(vg)
            end
        end
    end

    nvgGlobalAlpha(vg, 1.0)
end

local function drawParticles(vg)
    for _, p in ipairs(R.particles) do
        local sx, sy = R.w2s(p.x, p.y)
        local a = math.floor(255 * math.min(1, p.life / p.maxLife))
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, p.size * R.ppu)
        nvgFillColor(vg, rgba(p.color, a))
        nvgFill(vg)
    end
end

local function drawAimCursor(vg)
    -- 瞄星（PC 鼠标位置）
    if R.aimSX then
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 130))
        nvgStrokeWidth(vg, 1.5)
        nvgBeginPath(vg)
        nvgCircle(vg, R.aimSX, R.aimSY, 8)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, R.aimSX - 12, R.aimSY)
        nvgLineTo(vg, R.aimSX - 5, R.aimSY)
        nvgMoveTo(vg, R.aimSX + 5, R.aimSY)
        nvgLineTo(vg, R.aimSX + 12, R.aimSY)
        nvgMoveTo(vg, R.aimSX, R.aimSY - 12)
        nvgLineTo(vg, R.aimSX, R.aimSY - 5)
        nvgMoveTo(vg, R.aimSX, R.aimSY + 5)
        nvgLineTo(vg, R.aimSX, R.aimSY + 12)
        nvgStroke(vg)
    end
end

--- 主绘制入口（在 nvgBeginFrame/nvgEndFrame 之间调用）
---@param t number 累计时间
function R.drawWorld(t)
    R.t = t
    local vg = R.vg

    -- 编辑器模式只使用独立画布渲染，避免游戏地形/实体残留在地图下方。
    local ME = require "core.map_editor"
    if ME.active then
        EditorRender.draw(vg, R)
        return
    end

    -- 只借用本帧视觉中心：图片层裁剪用真实视野，屏幕 scissor 不随震屏平移。
    local logicalX, logicalY = R.camX, R.camY
    if R.shakeTime > 0 then
        R.setCamera(CameraBounds.shakeCenter(CameraBounds.fromLevel(L.def),
            logicalX, logicalY, R.viewW, R.viewH, R.shakeMag, Config.FEEL.shakeScale))
    end

    -- 直接读取运行关卡的数据；visible/locked 只影响编辑，不隐藏游戏图片层。
    local tilemapData = L.def and L.def.tilemapData
    -- 明确投影类型，避免把含世界状态的 Render 当作图集接口传入。
    ---@type TilesetProjection
    local projection = {
        camX = R.camX, camY = R.camY,
        screenW = R.screenW, screenH = R.screenH, ppu = R.ppu,
    }
    TileRender.drawBackground(vg, R, t)
    if tilemapData then
        Backgrounds.draw(vg, tilemapData.backgroundImages == nil and {} or tilemapData.backgroundImages, projection)
    end
    if tilemapData then TS.drawLayer(vg, "background", tilemapData, projection, false) end
    TileRender.drawTerrain(vg, R, L)
    if tilemapData then TS.drawLayer(vg, "ground", tilemapData, projection, false) end
    drawCrates(vg, t)
    drawHazards(vg, t)
    drawPortals(vg, t)
    drawItems(vg, t)
    drawEnemies(vg)
    drawBullets(vg)
    drawDashTrail(vg)
    drawGrapple(vg, t)
    drawPlayer(vg, t)
    if tilemapData then TS.drawLayer(vg, "foreground", tilemapData, projection, false) end
    -- 前景之后绘制反馈特效，保证刀光、碎片与伤害数字不被图片层盖住。
    MeleeFX.draw(vg, R)
    drawCrateShards(vg)
    CombatFX.draw(vg, R)
    drawParticles(vg)
    R.setCamera(logicalX, logicalY)  -- 必须恢复，后续跟随/瞄准/BOSS环不累计随机偏移。
    drawAimCursor(vg)              -- 瞄星与全屏闪光固定在屏幕，不跟着世界震。

    -- 全屏闪光
    if R.flashTime > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, R.screenW, R.screenH)
        nvgFillColor(vg, rgba(R.flashColor, math.floor(255 * math.min(0.7, R.flashTime * 2))))
        nvgFill(vg)
    end
end

return R
