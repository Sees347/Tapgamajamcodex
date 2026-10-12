-- 青蛙液态左键弹幕实机渲染验收：装备青蛙，按住左键，确认弹幕真的画出来。
local GS = require "core/state"
local P = require "core/player"
local A = require "core/abilities"
local B = require "core/bullets"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"
local ready = false

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = { "frog" }
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    P.form = "liquid"
    P.node.position2D = Vector2(8, 4)
    P.body.linearVelocity = Vector2(0, 0)
    P.body.gravityScale = 0
    GS.mode = "playing"
end)
V.atFrame(60, function() ready = true end)
V.atFrame(100, function()
    -- 模拟按住左键：直接置 fireRequest（与轮询分支等价），推进若干帧
    local before = #B.list
    for i = 1, 30 do
        A.fireRequest = true
        A.update(1 / 60, {
            playerPos = P.node.position2D,
            aimWorld = Vector2(P.node.position2D.x + 8, P.node.position2D.y),
            spawnBullet = function(o) return B.spawn(o) end,
            enemies = {},
        })
        B.update(1 / 60, { enemies = {}, playerPos = P.node.position2D,
                           hitEnemy = function() end, hitPlayer = function() end })
    end
    V.assert(#B.list > before, "青蛙液态按住左键生成弹幕（数量 " .. before .. "→" .. #B.list .. "）")
    GS.mode = "paused"
end)
