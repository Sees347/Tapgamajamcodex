-- 剑鱼近战砍箱回归：只动内存与测试关卡，不写存档、不进发行包。
---@class MeleeCrateTestHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "此测试只能由官方验证运行器加载") --[[@as MeleeCrateTestHarness]]
local GS = require "core/state"
local P = require "core/player"
local A = require "core/abilities"
local L = require "core/level"

V.atFrame(10, function()
    local oldSave, oldMode = GS.save, GS.mode
    local oldForm, oldFacing, oldLock, oldDead = P.form, P.facing, P.swingLock, P.dead
    local oldCooldowns = A.cooldowns
    GS.save = GS.defaultSave()
    LoadLevel("testmap", nil)
    GS.mode = "playing"
    P.dead = false

    -- 箱体只保留数据 + 空节点存根：damageCrate 破碎时会调 node:Remove()。
    local function box(x, y)
        return {
            x = x, y = y, w = 0.9, h = 0.9, hp = 4,
            destroyed = false, hitFlash = 0,
            node = { Remove = function() end },
        }
    end
    local crate = box(30, 0.35)
    L.crateNodes = { crate }

    local function reset(c)
        c.hp, c.destroyed, c.hitFlash = 4, false, 0
    end
    -- 与 main.lua 一致的接线：近战伤害按 meleeDmg * playerDmg 结算
    local function makeCtx(px, py, dmg)
        return {
            playerPos = Vector2(px, py),
            aimWorld = Vector2(px + 8, py),
            enemies = {},
            crates = L.crateNodes,
            meleeCrateHit = function(c) L.damageCrate(c, dmg) end,
        }
    end
    local function swing(px, py, dmg, facing)
        P.facing = facing or 1
        A.meleeAttack({ meleeRange = 2.4, meleeDmg = dmg }, makeCtx(px, py, dmg))
    end

    -- 命中：正前方，箱体在射程内 → 4 - 6 = -2，破碎
    reset(crate)
    swing(28, 0.35, 6)
    V.assert(crate.hp == -2 and crate.destroyed, "正前方近战命中箱体并按伤害扣血直至破碎")

    -- 未命中：背后
    reset(crate)
    swing(32, 0.35, 6, 1)
    V.assert(crate.hp == 4 and not crate.destroyed, "背后的箱子不被近战命中")

    -- 未命中：射程外
    reset(crate)
    swing(26, 0.35, 6, 1)
    V.assert(crate.hp == 4 and not crate.destroyed, "射程外的箱子不被近战命中")

    -- 命中：斜前 45° 且在扇形内
    reset(crate)
    swing(28, 1.35, 6, 1)
    V.assert(crate.destroyed, "斜前方 45° 扇形内的箱子被命中")

    -- 伤害口径：固态 12 一击必碎 4 血箱
    reset(crate)
    swing(28, 0.35, 12)
    V.assert(crate.destroyed, "固态 12 点近战一击破碎 4 血箱")

    -- 已破碎的箱子不再重复结算
    local hpBefore = crate.hp
    swing(28, 0.35, 12)
    V.assert(crate.hp == hpBefore and crate.destroyed, "已破碎箱体不重复扣血")

    -- 多箱：仅身前扇形内的箱子受损
    local near = box(30, 0.35)
    local far = box(34, 0.35)
    local back = box(27, 0.35)
    L.crateNodes = { near, far, back }
    swing(28, 0.35, 6)
    V.assert(near.destroyed and far.hp == 4 and back.hp == 4, "多箱时只命中身前射程内的箱子")

    UnloadLevel()
    L.crateNodes = {}
    A.cooldowns = oldCooldowns
    GS.save, GS.mode = oldSave, oldMode
    P.form, P.facing, P.swingLock, P.dead = oldForm, oldFacing, oldLock, oldDead
    print("[MeleeCrateTest] 剑鱼近战砍箱命中/边界/伤害口径验收完成")
end)
