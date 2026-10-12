-- 清洁机器人-002 图集实际渲染验收 + 世界内展示。
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
local KEYS = { "enemy_cleaner02_idle", "enemy_cleaner02_attack" }

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
    E.spawn(L.scene, "cleaner02", 3, 1.2)
    E.spawn(L.scene, "cleaner02", 6, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    GS.mode = "paused"
end)
V.atFrame(60, function()
    for _, k in ipairs(KEYS) do
        V.assert(clips[k] ~= nil and clips[k].count == 8, k .. " 配置 8 帧")
        V.assert(cache:Exists(clips[k].path), k .. " 图集文件存在")
    end
    ready = true
end)

SubscribeToEvent("NanoVGRender", function()
    if not ready or checked or not R.vg then return end
    checked = true
    local vg = R.vg
    nvgBeginFrame(vg, R.screenW, R.screenH, 1)
    for r, k in ipairs(KEYS) do
        for i = 1, 8 do
            local t = (i - 1) / clips[k].fps
            V.assert(Art.drawEnemy(vg, k, t, 120 + i * 120, 200 + (r - 1) * 120, 24, 1),
                k .. " 第 " .. i .. " 帧绘制成功")
        end
    end
    nvgEndFrame(vg)
end)
V.atFrame(75, function() V.assert(checked, "清洁机器人-002 图集实际渲染完成") end)
