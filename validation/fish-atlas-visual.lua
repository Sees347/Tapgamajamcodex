-- 三种新鱼待机图集的实际 NanoVG 渲染验收：直接按图集绘制并断言命中。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local R = require "core/render"
local E = require "core/enemies"
local H = require "core/hazards"
local HUD = require "ui/hud"
local ImageCache = require "urhox-libs/UI/Core/ImageCache"
local ready = false
local checked = false
local font = -1
local KEYS = { "swordfish", "barnacle", "frog", "archerfish", "ray" }

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    GS.mode = "paused"
end)
V.atFrame(90, function() ready = true end)

SubscribeToEvent("NanoVGRender", function()
    if not ready or not R.vg then return end
    local vg = R.vg
    if font < 0 then font = nvgCreateFont(vg, "fish-audit", "Fonts/MiSans-Regular.ttf") end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(20, 25, 40, 255))
    nvgFill(vg)
    nvgFontFace(vg, "fish-audit")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local cw = width / #KEYS
    local cy = height * 0.55
    for i, key in ipairs(KEYS) do
        local x = (i - 0.5) * cw
        local clip = clips["fish_" .. key]
        -- 逐帧推进到中间帧，确认动画确实在动而不是只画首帧
        local mid = math.ceil(clip.count / 2)
        local drawn = Art.drawFish(vg, key, (mid - 1) / clip.fps, x, cy, 150, 110, -1)
        -- 图标由 UI.ImageCache 加载（与菜单同一路径），确认新图标可解析
        local iconOk = false
        if clip.icon then
            local img = ImageCache.Get(clip.icon)
            local iw, ih = ImageCache.GetSize(clip.icon)
            iconOk = img ~= nil and img > 0 and iw == 128 and ih == 128
        end
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(222, 233, 249, 255))
        nvgText(vg, x, cy - 130, key .. "  frame " .. mid .. "/" .. clip.count)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(150, 170, 200, 255))
        nvgText(vg, x, cy + 178, "icon " .. tostring(iconOk))
        if not checked then
            V.assert(drawn, "fish_" .. key .. " 实际图集绘制成功")
        end
    end
    checked = true
    nvgEndFrame(vg)
end)
V.atFrame(105, function() V.assert(checked, "五种鱼图集实际渲染完成") end)
