-- 裂钳蟹实机：移动 + 抛出石子（含飞行与命中碎裂）。
local GS = require "core/state"
local P = require "core/player"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local B = require "core/bullets"
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
    E.spawn(L.scene, "crab", 4, 1.2)
    E.spawn(L.scene, "crab", 8, 1.2)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    P.node.position2D = Vector2(1, 1.2)
    GS.mode = "playing"
    P.dead = false
end)
V.atFrame(200, function() GS.mode = "paused" end)
