-- 青蛙装备输入回归：钩爪改右键后，左键照常发射弹幕，且钩爪标记仍在。
---@class FrogInputTestHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "此测试只能由官方验证运行器加载") --[[@as FrogInputTestHarness]]
local GS = require "core/state"
local P = require "core/player"
local A = require "core/abilities"
local FISH = require "data/fish"

V.atFrame(10, function()
    local oldSave, oldMode = GS.save, GS.mode
    local oldForm, oldDead = P.form, P.dead
    local oldCooldowns = A.cooldowns
    GS.save = GS.defaultSave()
    LoadLevel("testmap", nil)
    GS.mode = "playing"
    P.dead = false

    local function effectsFor(equipped, form)
        GS.save.equipped = equipped
        P.form = form
        return A.currentEffects()
    end

    -- 青蛙液态：钩爪标记保留（供 main 的右键分支使用），同时左键有基础水弹
    local m = effectsFor({ "frog" }, "liquid")
    V.assert(m.grapple == true, "青蛙液态仍带钩爪标记，供右键触发")
    V.assert(#m.bullets == 1 and m.bullets[1].fishKey == "__base__",
        "青蛙液态左键回退为基础水弹，不再被钩爪屏蔽")

    -- 青蛙气态：无钩爪，仍为基础水弹
    m = effectsFor({ "frog" }, "gas")
    V.assert(m.grapple == false, "青蛙气态无钩爪")
    V.assert(#m.bullets == 1 and m.bullets[1].fishKey == "__base__", "青蛙气态左键基础水弹")

    -- 青蛙固态：二段跳保留，左键基础水弹
    m = effectsFor({ "frog" }, "solid")
    V.assert(m.doubleJump == true, "青蛙固态保留二段跳")
    V.assert(#m.bullets == 1 and m.bullets[1].fishKey == "__base__", "青蛙固态左键基础水弹")

    -- 青蛙 + 射水鱼：左键走射水鱼弹幕，钩爪标记仍在（右键仍可钩）
    m = effectsFor({ "frog", "archerfish" }, "liquid")
    V.assert(m.grapple == true, "青蛙+射水鱼仍带钩爪标记")
    V.assert(#m.bullets == 1 and m.bullets[1].fishKey == "archerfish",
        "青蛙+射水鱼左键发射水鱼弹幕而非基础水弹")

    -- 左键实际结算：青蛙液态按住左键应生成弹幕
    local bullets = {}
    A.cooldowns = {}
    A.fireRequest = false
    P.form = "liquid"
    GS.save.equipped = { "frog" }
    local ctx = {
        playerPos = Vector2(0, 0), aimWorld = Vector2(8, 0),
        spawnBullet = function(o) bullets[#bullets + 1] = o; return o end,
        enemies = {},
    }
    A.fireRequest = true
    A.update(0.016, ctx)
    V.assert(#bullets >= 1, "青蛙液态按住左键实际发射出弹幕")

    -- 钩爪机制本身不受改绑影响：朝地形发射→挂住→松开释放。
    local hits, releases = 0, 0
    local onHit = function() hits = hits + 1 end
    local onRelease = function() releases = releases + 1 end
    GS.on("grappleHit", onHit)
    GS.on("grappleRelease", onRelease)
    P.form = "liquid"
    P.dead = false
    P.setTerrainCheck(function(x, y) return x >= 4 end)   -- 右侧 4 米外有墙
    local grabbed = P.fireGrapple(1, 0)
    V.assert(grabbed and P.grappling and hits == 1, "青蛙液态朝地形发射钩爪成功挂住")
    P.update(0.016, { moveX = 0, jumpPressed = false, jumpHeld = false, downHeld = false,
                      dashPressed = false, grappleHeld = false }, { grapple = true })
    V.assert(not P.grappling and releases == 1, "松开右键（grappleHeld=false）即释放钩爪")
    P.setTerrainCheck(nil)
    P.form = "gas"
    V.assert(not P.fireGrapple(1, 0), "非液态无法发射钩爪")

    UnloadLevel()
    A.cooldowns = oldCooldowns
    GS.save, GS.mode = oldSave, oldMode
    P.form, P.dead = oldForm, oldDead
    print("[FrogInputTest] 青蛙左键弹幕/右键钩爪标记验收完成")
end)
