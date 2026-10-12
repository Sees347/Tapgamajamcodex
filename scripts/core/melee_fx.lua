-- 剑鱼刀光：液态使用刀光003的三张独立图片，固态保留原图集节奏。
local Config = require "config"
local GS = require "core/state"
local Art = require "core/art"
local M = {}

---@type table[]
local slashes = {}

function M.bind()
    GS.on("playerMelee", function(x, y, ax, ay, range, stage)
        local artKey = stage and stage.artKey or "slash_swordfish"
        local clipDur = Art.duration(artKey)
        if clipDur <= 0 then clipDur = 0.18 end
        local dur = stage and stage.fxDuration or clipDur
        table.insert(slashes, {
            x = x, y = y, ax = ax, ay = ay, range = range or 1.6,
            life = dur, maxLife = dur, playbackRate = clipDur / dur,
            artKey = artKey, singleImage = stage and stage.artKey ~= nil or false,
            sweep = stage and stage.sweep or 0,
            sizeMul = stage and stage.sizeMul or 1,
            tilt = stage and stage.tilt or 0,
            flipY = stage and stage.flipY or false,
        })
        if #slashes > 12 then table.remove(slashes, 1) end
    end)
end

function M.clear()
    slashes = {}
end

---@param dt number
function M.update(dt)
    for i = #slashes, 1, -1 do
        local s = slashes[i]
        s.life = s.life - dt
        if s.life <= 0 then table.remove(slashes, i) end
    end
end

---@param vg NVGContextWrapper
---@param render Render
function M.draw(vg, render)
    for _, s in ipairs(slashes) do
        local offset = s.range * Config.MELEE_FX.forwardOffset
        local sx, sy = render.w2s(s.x + s.ax * offset, s.y + s.ay * offset)
        local a = s.life / s.maxLife
        local progress = 1 - a
        local scale, opacity, sweep = 1, 1, 0
        if s.singleImage then
            -- 前半段快速挥出，后半段保留短促余光；不改变判定、僵直或段间留白。
            local swing = math.min(1, progress / 0.55)
            local eased = 1 - (1 - swing) ^ 3
            scale = 0.82 + 0.18 * eased + 0.04 * progress
            sweep = (eased - 0.5) * s.sweep
            local fade = math.max(0, math.min(1, (progress - 0.38) / 0.62))
            opacity = (0.85 + 0.15 * math.min(1, progress / 0.12)) * (1 - fade * fade * (3 - 2 * fade))
        end
        local ang = math.atan(-s.ay, s.ax) + (s.tilt + sweep) * s.ax
        local rad = s.range * render.ppu
        -- 旧图集仍完整播放；独立图片由进度驱动挥动、缩放和淡出。
        local elapsed = (s.maxLife - s.life) * s.playbackRate
        nvgSave(vg)
        -- 刀光和兜底弧线均裁剪到本刀朝向侧，放大/倾斜也不会越过玩家中心。
        local originX = render.w2s(s.x, s.y)
        if s.ax > 0 then
            nvgIntersectScissor(vg, originX, 0, math.max(0, render.screenW - originX), render.screenH)
        else
            nvgIntersectScissor(vg, 0, 0, math.max(0, originX), render.screenH)
        end
        nvgTranslate(vg, sx, sy)
        nvgRotate(vg, ang)
        -- 朝左独立刀光做真正的水平镜像，不把上下切斩顺序也旋转颠倒。
        if s.singleImage and s.ax < 0 then nvgScale(vg, 1, -1) end
        if s.flipY then nvgScale(vg, 1, -1) end
        nvgGlobalAlpha(vg, opacity)
        local drawn = Art.drawProjectile(vg, s.artKey, elapsed, 0, 0,
                                         rad * Config.MELEE_FX.sizeMul * s.sizeMul * scale, 0)
        if not drawn then
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, rad * (0.7 + (1 - a) * 0.5) * s.sizeMul,
                   -0.7, 0.7, NVG_CW)
            nvgStrokeColor(vg, nvgRGBA(200, 235, 255, math.floor(220 * a)))
            nvgStrokeWidth(vg, 5 * a + 1)
            nvgStroke(vg)
        end
        nvgRestore(vg)
    end
end

return M
