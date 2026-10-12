-- ============================================================================
-- core/bossfx.lua - 冰火人 BOSS 技能特效
-- P1: 冰火交替吐息 / 落地冲击(冲击波+火冰地面) / 散弹投射
-- P2: 火焰浪潮(气态漂浮躲) / 火球弹幕 / 砸地
-- P3: 冰环扩散(单次降温) / 冰柱坠落 / 冰火冲撞
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local H = require "core/hazards"
local B = require "core/bullets"
local P = require "core/player"
local R = nil -- render（延迟 require 避免循环依赖）

---@class BossFX
local BF = {}

BF.rings = {}      -- 冰环 { x, y, radius, speed, maxRadius, hit }
BF.waves = {}      -- 火焰浪潮标记
BF.active = false

function BF.reset()
    BF.rings = {}
    BF.waves = {}
    BF.active = false
end

local function render()
    if not R then R = require "core/render" end
    return R
end

--- 临时火区/低温区（BOSS 生成，持续一段时间后消失）
local function tempZone(kind, x, y, w, h, dur)
    local hz = H.add({ kind = kind, x = x, y = y, w = w, h = h, temporary = true })
    hz.respawnTimer = dur
    hz.maxCharges = 999
    return hz
end

-- ===================== 技能实现 =====================

--- P1 冰火交替吐息：横向火束/冰束（命中附加形态转换）
function BF.breath(e, kind)
    local ep = e.node.position2D
    local color = kind == "fire" and Config.PAL.bossFire or Config.PAL.bossIce
    for i = 1, 5 do
        local dx = e.facing
        local dy = (i - 3) * 0.12
        local b = B.spawn({
            x = ep.x + e.facing * 1.2, y = ep.y + 0.2,
            dx = dx, dy = dy, speed = 11 + i * 0.5,
            dmg = 1, color = color, range = 11, fromEnemy = true,
        })
        if b then
            b.element = kind
            b.radius = 0.22
            b.gravity = 0
        end
    end
    render().shake(0.3, 0.25)
    GS.emit("sfx", kind == "fire" and "breathFire" or "breathIce")
end

--- P1 落地冲击：冲击波 + 落点火/低温地面
function BF.slamLand(e)
    local ep = e.node.position2D
    -- 左右冲击波（贴地弹）
    for _, dir in ipairs({ -1, 1 }) do
        local b = B.spawn({
            x = ep.x + dir * 1.0, y = ep.y - 0.6,
            dx = dir, dy = 0, speed = 8,
            dmg = 1, color = { 250, 200, 120 }, range = 9, fromEnemy = true,
        })
        if b then
            b.radius = 0.3
            b.gravity = 0
            b.slamWave = true
        end
    end
    -- 落点随机火区/低温区
    local kind = math.random() < 0.5 and "fire" or "cold"
    tempZone(kind, ep.x + (math.random() - 0.5) * 4, ep.y - 0.7, 2.6, 0.8, 5.0)
    render().shake(0.8, 0.4)
    GS.emit("sfx", "slam")
end

--- P2 火焰浪潮：地面铺火，只有气态升高漂浮才能躲开
function BF.wave(e, kind)
    local ep = e.node.position2D
    local dir = e.facing
    -- 沿地面依次生成火区（波前推进感）
    for i = 1, 8 do
        local x = ep.x + dir * (1.5 + i * 1.6)
        local zone = tempZone(kind == "fire" and "fire" or "cold", x, ep.y - 0.7, 1.8, 0.9, 3.5 + i * 0.25)
        zone.waveDelay = i * 0.12
        zone.active = false
    end
    GS.emit("sfx", "wave")
end

--- P3 冰环扩散：以 BOSS 为中心扩张，一次接触降低一级形态
function BF.ring(e)
    local ep = e.node.position2D
    table.insert(BF.rings, {
        x = ep.x, y = ep.y - 0.5,
        radius = 0.5, speed = 6.0, maxRadius = 12.0,
        hitPlayer = false,
    })
    GS.emit("sfx", "ring")
end

-- ===================== 更新 =====================

function BF.update(dt)
    -- 浪潮区域的延迟激活/失效由 H.update 在温度接触检测前统一处理。
    -- 冰环
    local i = 1
    while i <= #BF.rings do
        local ring = BF.rings[i]
        ring.radius = ring.radius + ring.speed * dt
        if ring.radius > ring.maxRadius then
            table.remove(BF.rings, i)
        else
            -- 玩家踩环判定：玩家在地面附近且与环半径接近
            if not ring.hitPlayer and P.node and not P.dead then
                local pp = P.node.position2D
                local d = math.sqrt((pp.x - ring.x) ^ 2 + (pp.y - ring.y) ^ 2)
                if math.abs(d - ring.radius) < 0.7 and pp.y < ring.y + 1.5 then
                    ring.hitPlayer = true
                    -- 冷环带一次降温：气→液、液→冰；保留每个环只命中一次。
                    P.onColdHit()
                    P.changeWater(-1, Config.DMG.BOSS)
                    GS.emit("sfx", "freeze")
                end
            end
            i = i + 1
        end
    end
end

--- 绘制冰环（render 调用）
function BF.drawRings(vg, w2s, ppu)
    for _, ring in ipairs(BF.rings) do
        local sx, sy = w2s(ring.x, ring.y)
        local rr = ring.radius * ppu
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy, rr, rr * 0.35)
        nvgStrokeColor(vg, nvgRGBA(150, 215, 255, 200))
        nvgStrokeWidth(vg, 5)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, sy, rr, rr * 0.35)
        nvgStrokeColor(vg, nvgRGBA(220, 245, 255, 90))
        nvgStrokeWidth(vg, 12)
        nvgStroke(vg)
    end
end

-- ===================== 事件绑定 =====================

function BF.bindEvents()
    GS.on("bossBreath", function(e, kind) BF.breath(e, kind) end)
    GS.on("bossSlamLand", function(e) BF.slamLand(e) end)
    GS.on("bossWave", function(e, kind) BF.wave(e, kind) end)
    GS.on("bossRing", function(e) BF.ring(e) end)
    GS.on("bossCharge", function(e)
        render().shake(0.4, 0.3)
        GS.emit("sfx", "charge")
    end)
    GS.on("bossPhase", function(phase)
        local r = render()
        r.flash(phase == 2 and Config.PAL.bossFire or Config.PAL.bossIce, 0.4)
        r.shake(1.0, 0.5)
        GS.emit("toast", phase == 2 and "冰火人：火焰侧过载！" or "冰火人：寒冰侧过载！")
    end)
end

return BF
