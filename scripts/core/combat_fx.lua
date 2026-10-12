-- 战斗命中特效：固态撞击的冰蓝冲击环/放射光芒，以及敌人受击伤害数字。
-- 独立于世界渲染，所有位置在命中时快照，敌人死亡移除后特效仍能播放完。
local GS = require "core/state"
local C = {}

---@type {x:number, y:number, life:number, maxLife:number}[]
C.ramImpacts = {}
---@type table[]
local damageNumbers = {}

function C.bind()
    GS.on("ramHit", function(e, x, y)
        table.insert(C.ramImpacts, { x = x, y = y, life = 0.32, maxLife = 0.32 })
        if #C.ramImpacts > 16 then table.remove(C.ramImpacts, 1) end
    end)
    GS.on("enemyHit", function(e, dmg)
        if not e or not e.node or not dmg or dmg <= 0 then return end
        local ep = e.node.position2D
        table.insert(damageNumbers, {
            x = ep.x + (math.random() - 0.5) * 0.4,
            y = ep.y + 0.5,
            dmg = math.floor(dmg + 0.5),
            life = 0.75, maxLife = 0.75,
            vx = (math.random() - 0.5) * 1.2, vy = 2.2,
        })
        if #damageNumbers > 40 then table.remove(damageNumbers, 1) end
    end)
end

function C.clear()
    C.ramImpacts = {}
    damageNumbers = {}
end

---@param dt number
function C.update(dt)
    for i = #C.ramImpacts, 1, -1 do
        local impact = C.ramImpacts[i]
        impact.life = impact.life - dt
        if impact.life <= 0 then table.remove(C.ramImpacts, i) end
    end
    for i = #damageNumbers, 1, -1 do
        local n = damageNumbers[i]
        n.life = n.life - dt
        if n.life <= 0 then
            table.remove(damageNumbers, i)
        else
            n.x = n.x + n.vx * dt
            n.y = n.y + n.vy * dt
            n.vy = n.vy - 3.5 * dt
            n.vx = n.vx * 0.94
        end
    end
end

---@param vg NVGContextWrapper
---@param render Render
function C.draw(vg, render)
    for _, impact in ipairs(C.ramImpacts) do
        local sx, sy = render.w2s(impact.x, impact.y)
        local progress = 1 - impact.life / impact.maxLife
        local alpha = (1 - progress) ^ 2
        local radius = (0.12 + 0.85 * (1 - (1 - progress) ^ 3)) * render.ppu
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, radius * 1.5)
        nvgFillPaint(vg, nvgRadialGradient(vg, sx, sy, 0, radius * 1.5,
            nvgRGBA(200, 240, 255, math.floor(170 * alpha)), nvgRGBA(100, 200, 255, 0)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, radius)
        nvgStrokeWidth(vg, (0.02 + 0.06 * alpha) * render.ppu)
        nvgStrokeColor(vg, nvgRGBA(200, 240, 255, math.floor(255 * alpha)))
        nvgStroke(vg)
        nvgBeginPath(vg)
        for i = 1, 8 do
            local angle = i * math.pi / 4
            local dx, dy = math.cos(angle), math.sin(angle)
            nvgMoveTo(vg, sx + dx * radius * 0.45, sy + dy * radius * 0.45)
            nvgLineTo(vg, sx + dx * radius * 1.35, sy + dy * radius * 1.35)
        end
        nvgStrokeWidth(vg, 0.035 * render.ppu)
        nvgStrokeColor(vg, nvgRGBA(235, 250, 255, math.floor(230 * alpha)))
        nvgStroke(vg)
    end

    if #damageNumbers == 0 then return end
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, n in ipairs(damageNumbers) do
        local sx, sy = render.w2s(n.x, n.y)
        if sx > -60 and sx < render.screenW + 60 and sy > -60 and sy < render.screenH + 60 then
            local a = math.min(1, n.life / (n.maxLife * 0.6))
            local pop = 1 + (1 - math.min(1, (n.maxLife - n.life) / 0.12)) * 0.5
            nvgFontSize(vg, 18 * pop)
            nvgFillColor(vg, nvgRGBA(20, 26, 40, math.floor(220 * a)))
            local txt = tostring(n.dmg)
            nvgText(vg, sx + 1.5, sy + 1.5, txt, nil)
            nvgFillColor(vg, nvgRGBA(255, 230, 130, math.floor(255 * a)))
            nvgText(vg, sx, sy, txt, nil)
        end
    end
end

return C
