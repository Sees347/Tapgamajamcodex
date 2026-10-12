-- 世界内鱼拾取物渲染验收：把镜头移到 testmap 出生区的鱼群，实际渲染三种新鱼。
local GS = require "core/state"
local P = require "core/player"
local R = require "core/render"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"
local ready = false

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    -- 只留三种新鱼与相邻的鳐鱼作对照，镜头对准拾取物一排
    local keep = { swordfish = true, barnacle = true, frog = true, ray = true }
    for i = #L.itemNodes, 1, -1 do
        local it = L.itemNodes[i]
        if it.kind ~= "fish" or not keep[it.fishKey] then table.remove(L.itemNodes, i) end
    end
    P.node.position2D = Vector2(1, 0.5)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0, 0)
    R.camX, R.camY = 1, 0.5
    GS.mode = "paused"
end)
V.atFrame(90, function() ready = true end)
V.atFrame(100, function()
    local names = {}
    for _, it in ipairs(L.itemNodes) do names[#names + 1] = it.fishKey end
    V.assert(#names >= 4, "出生区保留四种待验收鱼： " .. table.concat(names, ","))
end)
