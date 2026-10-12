local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local HUD = require "ui/hud"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local R = require "core/render"
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones = {}
    L.itemNodes = {}
    P.body.linearVelocity = Vector2(0, 0)
    P.body.gravityScale = 0
    P.onGround = true
    P.setForm("gas", true)
    GS.save.equipped = {  }
    Art.reset()
    Art.update(0)
    
    Art.update(0.2)
    P.hurtFlash = 0
    P.invuln = 0
    P.formFlash = 0
    R.flashTime = 0
    R.shakeTime = 0
    HUD.refreshAll()
    HUD.refreshForm(nil, P.form)
    GS.mode = "paused"
end)
