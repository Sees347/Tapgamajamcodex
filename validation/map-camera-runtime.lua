-- 相机真实引擎验收：边角、三形态、视野变更、震屏投影与编辑器绕过。
local GS = require "core.state"
local P = require "core.player"
local R = require "core.render"
local L = require "core.level"
local C = require "core.camera_bounds"
local ME = require "core.map_editor"
local Config = require "config"
local TS = require "core.tilesets"
local TR = require "core.tile_render"
local HUD = require "ui.hud"
local function inside(b, x, y)
    return x - R.viewW / 2 >= b.minX - 1e-9 and x + R.viewW / 2 <= b.maxX + 1e-9
        and y - R.viewH / 2 >= b.minY - 1e-9 and y + R.viewH / 2 <= b.maxY + 1e-9
end
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    LoadLevel("world")
    local scene = P.node.parent
    scene.updateEnabled = false
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    local b = assert(C.fromLevel(L.def))
    local cameraNode = assert(scene:GetChild("Camera"))
    local cam = assert(cameraNode:GetComponent("Camera"))
    V.assert(inside(b, R.camX, R.camY), "真实LoadLevel首帧整个视口在图内")
    V.assert(cameraNode.position.x == R.camX and cameraNode.position.y == R.camY and cam.orthoSize == R.viewH, "真实Camera节点与NanoVG立即同步")
    for _, form in ipairs({ "liquid", "solid", "gas" }) do
        P.setForm(form, true)
        for _, p in ipairs({ { -100, 100 }, { 400, 100 }, { -100, -300 }, { 400, -300 } }) do
            P.node.position2D = Vector2(p[1], p[2])
            P.body.linearVelocity = Vector2(0, 10)
            UpdateCamera(1)
            V.assert(inside(b, R.camX, R.camY), form .. "跟随地图四角完整视口不越界")
            local delta = math.max(math.abs(cameraNode.position.x - R.camX), math.abs(cameraNode.position.y - R.camY))
            V.assert(delta < 0.0001, form .. "边缘Camera浮点位置与NanoVG误差小于0.1毫米")
            print(string.format("[CameraNodePrecision] form=%s errorMetres=%.9f", form, delta))
        end
    end
    local requested = Config.VIEW_H
    Config.VIEW_H = 1000
    UpdateScreenSize()
    V.assert(inside(b, R.camX, R.camY) and R.viewH < 1000 and Config.VIEW_H == 1000, "过大请求只fit有效视野不改设置")
    Config.VIEW_H = requested
    UpdateScreenSize()
    local data = L.def.tilemapData
    local oldCols, oldRows = data.cols, data.rows
    data.cols, data.rows = 1, 1
    UpdateScreenSize()
    local small = assert(C.fromLevel(L.def))
    V.assert(inside(small, R.camX, R.camY) and R.viewW <= 1 + 1e-9 and R.viewH <= 1 + 1e-9, "真实单格小地图有效视野按屏幕比例缩小")
    data.cols, data.rows = oldCols, oldRows
    UpdateScreenSize()
    V.assert(math.abs(R.viewH - requested) < 1e-9, "回大地图恢复原请求视野")
    local oldActive, oldView = ME.active, ME.viewH
    ME.active, ME.viewH = true, 80
    R.setCamera(-5000, 5000)
    UpdateScreenSize()
    UpdateCamera(1)
    V.assert(R.camX == -5000 and R.camY == 5000 and R.viewH == 80, "真实编辑器相机仍自由越界缩放")
    ME.active, ME.viewH = oldActive, oldView
    UpdateScreenSize()
    LoadLevel("world")
    P.node.parent.updateEnabled = false
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    R.flashTime = 0
end)

local oldLayer, oldBackground = TS.drawLayer, TR.drawBackground
local drawChecks, failures = 0, 0
V.atFrame(90, function()
    local b = assert(C.fromLevel(L.def))
    R.setCamera(C.clamp(b, 999, -999, R.viewW, R.viewH))
    R.shake(25, 20)
    local logicalX, logicalY = R.camX, R.camY
    TS.drawLayer = function(vg, id, data, projection, editor)
        drawChecks = drawChecks + 1
        if not inside(b, projection.camX, projection.camY) or projection.camX ~= R.camX or projection.camY ~= R.camY then failures = failures + 1 end
        return oldLayer(vg, id, data, projection, editor)
    end
    TR.drawBackground = function(vg, render, t)
        if not inside(b, render.camX, render.camY) then failures = failures + 1 end
        return oldBackground(vg, render, t)
    end
    V.atFrame(120, function()
        TS.drawLayer, TR.drawBackground = oldLayer, oldBackground
        V.assert(drawChecks >= 30 and failures == 0, "真实NanoVG震屏连续多帧三层图片采用图内视觉中心")
        V.assert(R.camX == logicalX and R.camY == logicalY, "震屏每帧结束恢复逻辑相机，不累积")
        R.shake(1, 2)
        LoadLevel("world")
        V.assert(R.shakeTime == 0 and R.shakeMag == 0, "真实跨关清旧震屏")
        P.node.parent.updateEnabled = false
        GS.setMode("paused")
        HUD.hideOverlay()
        HUD.setGameHudVisible(false)
    end)
end)
