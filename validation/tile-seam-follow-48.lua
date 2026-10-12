-- 实际共享地图碰撞回归：隔离 Scene 使用同一份编译地形，真实玩家控制器/Box2D/跟随相机。
-- 不修改碰撞，不写玩家进度；检查水平格缝、满跳跨缝与落地。
local GS = require "core.state"
local P = require "core.player"
local L = require "core.level"
local R = require "core.render"
local TM = require "core.tilemap"
local World = require "core.world_map"
local Config = require "config"
local HUD = require "ui.hud"
local scene = Scene()
local physics = scene:CreateComponent("PhysicsWorld2D")
physics.gravity = Vector2(0, -Config.GRAVITY)
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    LoadLevel("world", nil)
    P.node.parent.updateEnabled = false
    local def = TM.parse(World.source())
    L.load(scene, { id = "__tile_seam_physics__", name = "格缝碰撞回归", platforms = def.platforms, tilemapData = def.tilemapData })
    P.create(scene, 120.5, -181)
    R.setCamera(120.5, -181)
    GS.setMode("paused")
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    local dt = 1 / 120
    local function step(move, jump, held)
        DetectGround()
        P.update(dt, { moveX = move, jumpPressed = jump, jumpHeld = held }, {})
        scene:Update(dt)
        UpdateCamera(dt)
    end
    for _ = 1, 120 do step(0, false, false) end
    local start = P.node.position2D
    local floorY = start.y
    local minY, maxY = floorY, floorY
    for _ = 1, 60 do
        step(1, false, false)
        local y = P.node.position2D.y
        minY, maxY = math.min(minY, y), math.max(maxY, y)
    end
    local crossed = P.node.position2D
    V.assert(crossed.x - start.x > 2.0, "真实共享地形水平跨越至少2条格缝，没有卡住")
    V.assert(maxY - minY < 0.03, "水平跨格地面高度稳定，抖动小于0.03米")
    V.assert(math.abs(crossed.y - floorY) < 0.03, "水平跨格没有掉落")
    local jumpStart = crossed.x
    local peakY = floorY
    for index = 1, 48 do
        step(index <= 48 and 1 or 0, index == 1, true)
        peakY = math.max(peakY, P.node.position2D.y)
    end
    print(string.format("[TileSeamFollow] frame=%d player=(%.5f,%.5f) camera=(%.5f,%.5f)",
        48, P.node.position2D.x, P.node.position2D.y, R.camX, R.camY))
    scene.updateEnabled = false
end)
