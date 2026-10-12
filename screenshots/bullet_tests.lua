-- 子弹替换回归验收：只在运行器中执行，不写存档、不进入发行包。
local GS = require "core/state"
local A = require "core/abilities"
local B = require "core/bullets"
local P = require "core/player"
local R = require "core/render"
local Art = require "core/art"
local clips = require "data/art"
local FISH = require "data/fish"

V.atFrame(10, function()
    local saved = GS.save
    local oldForm = P.form
    GS.save = GS.defaultSave()
    local captured = {}
    local ctx = {
        playerPos = Vector2(0, 0), aimWorld = Vector2(1, 0),
        spawnBullet = function(o)
            local b = B.spawn(o)
            captured[#captured + 1] = b
            return b
        end,
    }
    local function fire(key, form, paralysis)
        P.form = form
        local merged = A.currentEffects()
        merged.paralysis = paralysis or 0
        A.fireOne(key, FISH[key] and FISH[key][form] or {dir = "mouse"}, merged, ctx)
        return captured[#captured]
    end
    B.clear()
    local water = fire("__base__", "liquid")
    V.assert(water.artKey == "bullet_water", "基础水弹使用上传素材")
    V.assert(water.radius == 0.14 and water.animTime == 0, "水弹碰撞半径和独立动画时间")
    V.assert(fire("archerfish", "liquid").artKey == "bullet_water", "射水鱼液态水弹")
    V.assert(fire("archerfish", "gas").artKey == "bullet_water", "射水鱼气态水弹")
    local ice = fire("archerfish", "solid")
    V.assert(ice.artKey == "bullet_ice" and ice.isIce and ice.dmg == 15 and ice.radius == 0.18, "冰弹只替换美术，伤害和判定不变")
    V.assert(fire("archerfish", "liquid", 0.5).artKey == "bullet_electric", "麻痹射出水弹使用带电素材")
    V.assert(fire("archerfish", "solid", 0.5).artKey == "bullet_ice", "冰锥外观优先级")
    local lightning = fire("eel", "gas")
    V.assert(lightning.artKey == "bullet_lightning" and lightning.vy < 0, "闪电仅对应电鳗气态向下攻击")
    V.assert(math.abs(lightning.angle - math.pi / 2) < 0.001, "世界向下转换为屏幕向下")
    V.assert(fire("anglerfish", "liquid").artKey == nil, "普通光弹外观保持原样")
    B.spawnEnemyBullet(0, 0, 1, 0, 5, 2, {255, 100, 50}, 0, "ice")
    V.assert(B.list[#B.list].artKey == nil, "敌方元素弹不误替换")

    B.clear()
    R.bulletImpacts = {}
    B.setTerrainCheck(function() return false end)
    local enemy = {uid = 123, radius = 0.2, dead = false, node = {position2D = Vector2(1, 0)}}
    local hits = 0
    local b = B.spawn({x = 0, y = 0, dx = 1, dy = 0, speed = 10, range = 10, dmg = 15, isIce = true, artKey = "bullet_ice"})
    B.update(0.1, {enemies = {enemy}, hitEnemy = function() hits = hits + 1 end})
    V.assert(hits == 1 and b.dead, "冰弹正常命中并死亡")
    V.assert(#R.bulletImpacts == 1, "冰弹命中仅生成一次爆发")
    B.update(0.1, {enemies = {enemy}, hitEnemy = function() hits = hits + 1 end})
    V.assert(hits == 1 and #R.bulletImpacts == 1 and #B.list == 0, "爆发不重复伤害、不依赖存活子弹")
    R.update(Art.duration("bullet_ice_hit") + 0.01)
    V.assert(#R.bulletImpacts == 0, "命中动画播放后释放")

    B.clear()
    B.setTerrainCheck(function() return true end)
    b = B.spawn({x = 0, y = 0, dx = 1, dy = 0, speed = 10, range = 10, isIce = true, artKey = "bullet_ice", bounceMax = 1})
    B.update(0.01, {})
    V.assert(b.bounceCount == 1 and not b.dead and math.abs(math.abs(b.angle) - math.pi) < 0.001, "反弹更新朝向，不提前爆发")
    V.assert(#R.bulletImpacts == 0, "反弹没有命中爆发")
    B.update(0.01, {})
    V.assert(b.dead and #R.bulletImpacts == 1, "撞墙销毁触发冰弹爆发")

    B.clear()
    R.bulletImpacts = {}
    B.setTerrainCheck(function() return false end)
    b = B.spawn({x = 0, y = 0, dx = -1, dy = 0, speed = 10, range = 0.1, hoverDur = 0.5, artKey = "bullet_water"})
    B.update(0.02, {})
    local lastAngle = b.angle
    B.update(0.02, {})
    V.assert(b.state == "hover" and b.vx == 0 and b.angle == lastAngle and b.animTime > 0, "悬停保留朝向并继续动画")
    B.clear()
    b = B.spawn({x = 0, y = 0, dx = 1, dy = 0, speed = 10, range = 0.01, isIce = true, artKey = "bullet_ice"})
    B.update(0.02, {})
    V.assert(b.dead and #R.bulletImpacts == 0, "射程到期不伪造命中爆发")
    B.clear()
    B.setTerrainCheck(require("core/level").isSolid)
    GS.save = saved
    P.form = oldForm
end)

V.atFrame(100, function()
    for _, key in ipairs({"bullet_water", "bullet_electric", "bullet_ice", "bullet_ice_hit", "bullet_lightning"}) do
        local clip = clips[key]
        V.assert(clip ~= nil and clip.count > 0 and Art.duration(key) > 0, key .. " 配置完整")
        V.assert(cache:Exists(clip.path), key .. " 图集可加载")
    end
    V.assert(clips.bullet_ice.loop and not clips.bullet_ice_hit.loop, "飞行循环，爆发单次")
end)
