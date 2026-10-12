-- 裂钳蟹图集实际渲染验收 + 世界内展示。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local R = require "core/render"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"
local ready = false
local checked = false

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones = {}
    for i = #L.itemNodes, 1, -1 do table.remove(L.itemNodes, i) end
    E.spawn(L.scene, "crab", 3, 1.2)
    E.spawn(L.scene, "crab", 6, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    GS.mode = "paused"
end)
V.atFrame(60, function() ready = true end)

SubscribeToEvent("NanoVGRender", function()
    if not ready or not R.vg then return end
    local vg = R.vg
    local doAssert = not checked
    nvgBeginFrame(vg, R.screenW, R.screenH, 1)
    -- 移动 8 帧
    for i = 1, 8 do
        local ok = Art.drawEnemy(vg, "enemy_crab_move", (i - 1) / clips.enemy_crab_move.fps, 100 + i * 120, 150, 30, 1)
        if doAssert then V.assert(ok, "移动第 " .. i .. " 帧") end
    end
    -- 近战左/右螯各 4 帧
    for i = 1, 4 do
        local t = (i - 1) / clips.enemy_crab_melee.fps
        local okA = Art.drawEnemy(vg, "enemy_crab_melee", t, 100 + i * 120, 330, 30, 1, 0)
        local okB = Art.drawEnemy(vg, "enemy_crab_melee", t, 100 + i * 120, 470, 30, 1, 4)
        if doAssert then V.assert(okA and okB, "近战左右螯第 " .. i .. " 帧") end
    end
    -- 远程左/右螯 + 石子
    for i = 1, 4 do
        local t = (i - 1) / clips.enemy_crab_ranged.fps
        local ok = Art.drawEnemy(vg, "enemy_crab_ranged", t, 620 + i * 120, 330, 30, 1, 0)
        if doAssert then V.assert(ok, "远程左螯第 " .. i .. " 帧") end
    end
    for i = 1, 2 do
        Art.drawProjectile(vg, "enemy_crab_stone_fly", (i - 1) / clips.enemy_crab_stone_fly.fps, 620 + i * 130, 470, 40, 0)
    end
    Art.drawProjectile(vg, "enemy_crab_stone_hit", 0, 1000, 470, 40, 0)
    if doAssert then V.assert(Art.drawProjectile(vg, "enemy_crab_stone_hit", 0, 1000, 470, 40, 0), "石子碎裂帧") end
    checked = true
    nvgEndFrame(vg)
end)
V.atFrame(75, function() V.assert(checked, "裂钳蟹图集实际渲染完成") end)
