-- 清洁机器人-001 追击移动中的世界内渲染（用于确认无残影）。
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones, L.itemNodes = {}, {}
    E.spawn(L.scene, "cleaner01", 3, 1.2)
    E.spawn(L.scene, "cleaner01", 6, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    P.node.position2D = Vector2(2, 1.2)
    GS.mode = "playing"
    P.dead = false
end)
V.atFrame(120, function() GS.mode = "paused" end)
