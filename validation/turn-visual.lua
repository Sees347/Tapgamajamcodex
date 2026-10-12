-- 实际 NanoVG 绘制的确定性转身帧：三态、双向、首/中/末帧与待机对照。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local R = require "core/render"
local E = require "core/enemies"
local H = require "core/hazards"
local HUD = require "ui/hud"
local ready = false
local checked = false
local font = -1

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
    P.onGround = true
    GS.mode = "paused"
end)
V.atFrame(110, function() ready = true end)

SubscribeToEvent("NanoVGRender", function()
    if not ready or not R.vg then return end
    local vg = R.vg
    if font < 0 then font = nvgCreateFont(vg, "turn-audit", "Fonts/MiSans-Regular.ttf") end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(20, 25, 40, 255))
    nvgFill(vg)
    nvgFontFace(vg, "turn-audit")
    nvgFontSize(vg, 17)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local cw, ch = width / 8, height / 3
    for row, form in ipairs({ "liquid", "solid", "gas" }) do
        for col = 1, 8 do
            local facing = col <= 4 and 1 or -1
            local step = (col - 1) % 4
            P.form = form
            P.onGround = true
            P.facing = step == 0 and facing or -facing
            Art.reset()
            GS.mode = "playing"
            local clip = clips[form .. "_turn"]
            if step > 0 then
                P.facing = facing
                Art.update(0)
                local frame = step == 1 and 1 or step == 2 and math.ceil(clip.count / 2) or clip.count
                Art.update((frame - 1) / clip.fps)
            end
            GS.mode = "paused"
            local key, frame = Art.getPlayback()
            local x, y = (col - 0.5) * cw, (row - 0.5) * ch + 15
            nvgFillColor(vg, nvgRGBA(222, 233, 249, 255))
            nvgText(vg, (col - 1) * cw + 8, (row - 1) * ch + 12, form .. (facing == 1 and " R " or " L ") .. (step == 0 and "idle" or tostring(frame)))
            nvgBeginPath(vg)
            nvgMoveTo(vg, x - 12, y)
            nvgLineTo(vg, x + 12, y)
            nvgMoveTo(vg, x, y - 12)
            nvgLineTo(vg, x, y + 12)
            nvgStrokeColor(vg, nvgRGBA(87, 109, 149, 150))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            local drawn = Art.drawPlayer(vg, x, y, 130)
            if not checked then
                V.assert(drawn, key .. "实际图集绘制 " .. tostring(facing) .. "/" .. tostring(frame))
                V.assert(key == form .. (step == 0 and "_idle" or "_turn"), form .. "受控动作键正确")
            end
        end
    end
    checked = true
    nvgEndFrame(vg)
end)
V.atFrame(125, function() V.assert(checked, "双向三态多帧实际渲染完成") end)
