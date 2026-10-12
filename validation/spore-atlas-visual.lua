-- 喷孢菌图集实际渲染验收：待机循环 + 攻击单次播放，均走 Art.drawEnemy。
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
    -- 只留喷孢菌，摆一排便于观察
    local keep = {}
    for _, it in ipairs(L.itemNodes) do keep[#keep + 1] = it end
    for i = #L.itemNodes, 1, -1 do table.remove(L.itemNodes, i) end
    E.spawn(L.scene, "spore", 2, 1.2)
    E.spawn(L.scene, "spore", 5, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    GS.mode = "paused"
end)
V.atFrame(60, function()
    V.assert(clips.enemy_spore_idle ~= nil and clips.enemy_spore_idle.count == 8, "待机图集配置 8 帧")
    V.assert(clips.enemy_spore_attack ~= nil and clips.enemy_spore_attack.count == 8, "攻击图集配置 8 帧")
    V.assert(cache:Exists(clips.enemy_spore_idle.path), "待机图集文件存在")
    V.assert(cache:Exists(clips.enemy_spore_attack.path), "攻击图集文件存在")
    ready = true
end)

SubscribeToEvent("NanoVGRender", function()
    if not ready or checked or not R.vg then return end
    checked = true
    local vg = R.vg
    nvgBeginFrame(vg, R.screenW, R.screenH, 1)
    local x, y = 300, 300
    -- 待机：逐帧扫过 8 帧，确认每帧都能采样绘制
    for i = 1, 8 do
        local t = (i - 1) / clips.enemy_spore_idle.fps
        V.assert(Art.drawEnemy(vg, "enemy_spore_idle", t, x + i * 60, y, 24, 1),
            "待机图集第 " .. i .. " 帧绘制成功")
    end
    -- 攻击：单次播放，末尾帧也应绘制
    V.assert(Art.drawEnemy(vg, "enemy_spore_attack", 0, x, y + 140, 24, 1), "攻击图集首帧绘制成功")
    V.assert(Art.drawEnemy(vg, "enemy_spore_attack", Art.duration("enemy_spore_attack"), x + 80, y + 140, 24, 1),
        "攻击图集末帧绘制成功")
    -- 未知键应安全返回 false（触发矢量兜底）
    V.assert(not Art.drawEnemy(vg, "enemy_does_not_exist", 0, x, y, 24, 1), "未知敌人图集返回 false")
    nvgEndFrame(vg)
end)
V.atFrame(75, function() V.assert(checked, "喷孢菌图集实际渲染完成") end)
