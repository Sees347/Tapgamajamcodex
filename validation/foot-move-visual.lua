-- 液态移动姿态脚底验证：地面参考线 + 强制 move 动画，截图看脚是否贴线。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"
local R = require "core/render"
local Config = require "config"
local ready = false

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    P.node.position2D = Vector2(8, 3)
    P.body.linearVelocity = Vector2(0, 0)
    GS.mode = "playing"
    P.dead = false
end)
V.atFrame(120, function()
    GS.mode = "playing"
    ready = true
end)

SubscribeToEvent("NanoVGRender", function()
    if not ready or not R.vg then return end
    local vg = R.vg
    -- 每帧渲染前重置水平速度：本帧 P.update 已按无输入减速，这里拉回 3 保持 move 状态
    P.body.linearVelocity = Vector2(3, 0)
    Art.update(0.016)
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(20, 25, 40, 255))
    nvgFill(vg)
    local pp = P.node.position2D
    -- 地面参考线：世界 y=0（平台表面）
    local gx, gy = R.w2s(8, 0)
    nvgBeginPath(vg)
    nvgMoveTo(vg, gx - 260, gy)
    nvgLineTo(vg, gx + 260, gy)
    nvgStrokeColor(vg, nvgRGBA(255, 90, 90, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    -- 碰撞底参考线：node.y - r
    local cx, cy = R.w2s(8, pp.y - Config.FORMS.liquid.radius)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 260, cy)
    nvgLineTo(vg, cx + 260, cy)
    nvgStrokeColor(vg, nvgRGBA(120, 255, 140, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    -- 玩家（move 动画）。注意 w2s 返回两个值，须先接住再用（规则 #4.5）
    local nx, ny = R.w2s(8, pp.y)
    Art.drawPlayer(vg, nx, ny, R.ppu)
    nvgEndFrame(vg)
end)
