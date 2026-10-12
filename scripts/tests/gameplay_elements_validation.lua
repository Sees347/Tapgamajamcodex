-- 玩法元素触发验收：仅内存 + 独立 Scene；不加载/覆盖用户地图，不写玩家存档。
-- 由主线程统一构建后通过官方 validation 接口运行，不是运行入口。
---@class GameplayElementsValidationHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "仅供官方验证运行器使用") --[[@as GameplayElementsValidationHarness]]
local TM = require "core.tilemap"
local H = require "core.hazards"
local L = require "core.level"
local P = require "core.player"
local E = require "core.enemies"
local GS = require "core.state"
local Config = require "config"
local CombatFX = require "core.combat_fx"
local R = require "core.render"

---@type Scene?
local testScene = nil

V.atFrame(10, function()
    local originalSave, originalEmit, originalSaveGame = GS.save, GS.emit, GS.saveGame
    local originalMode, originalPending = GS.mode, GS.pendingMode
    local playerFields = { "node", "body", "bodyShape", "footShape", "form", "dead", "invuln", "water",
        "onGround", "groundContacts", "doubleJumpUsed", "ramming", "dashing", "dashTimer", "dashCd",
        "formFlash", "squash", "hurtFlash", "jumpBuffer", "coyote", "jumpRising", "jumpHoldTimer",
        "canDoubleJump", "facing", "animTime", "flyDashCd", "flyDashing", "swingLock", "blocking", "grappling" }
    local levelFields = { "scene", "def", "platformRects", "crateNodes", "itemNodes", "doorNodes", "storyZones", "decorList" }
    local savedPlayer, savedLevel = {}, {}
    for _, key in ipairs(playerFields) do savedPlayer[key] = P[key] end
    for _, key in ipairs(levelFields) do savedLevel[key] = L[key] end
    local originalHazards, originalWires, originalEnemies = H.list, H.wires, E.list
    local originalRamTimers = E.ramTimers
    local events = {}
    local ramPosition = {}
    local saves = 0
    GS.save = GS.defaultSave()
    GS.save.relics = {}
    GS.saveGame = function() saves = saves + 1; return true end
    -- 隔离视觉/音效监听器；用与 main 一致的奖励和泉眼回调验收实际状态变化。
    GS.emit = function(event, ...)
        events[event] = (events[event] or 0) + 1
        local obj = ...
        if event == "springTouch" then
            H.resetWaters()
        elseif event == "itemPickup" then
            if obj.kind == "shell" then GS.addShells(Config.ECONOMY.pickupShellValue)
            elseif obj.kind == "fish" then GS.addFish(obj.fishKey)
            elseif obj.kind == "relic" then GS.addRelic(obj.relicKey)
            elseif obj.kind == "symbShard" then GS.addFragment()
            elseif obj.kind == "brokenQuanxin" then GS.addPiece() end
        elseif event == "enemyMelee" then
            local _, damage = ...
            P.changeWater(-damage, Config.DMG.ENEMY)
        elseif event == "ramHit" then
            local _, x, y = ...
            ramPosition = { x = x, y = y }
        end
    end
    P.node, P.body = nil, nil
    H.list, H.wires, E.list = {}, {}, {}
    testScene = Scene()
    local physics = testScene:CreateComponent("PhysicsWorld2D")
    physics.gravity = Vector2(0, -Config.GRAVITY)

    local function player(form, x, y, water)
        P.dead, P.dashing, P.ramming, P.invuln = false, false, false, 0
        P.dashCd, P.dashTimer, P.jumpBuffer, P.coyote = 0, 0, 0, 0
        P.jumpRising, P.flyDashing, P.grappling, P.swingLock = false, false, false, 0
        P.setForm(form, true)
        local node = assert(P.node) --[[@as Node]]
        local body = assert(P.body) --[[@as RigidBody2D]]
        node:SetPosition2D(x, y)
        body.linearVelocity = Vector2(0, 0)
        GS.save.water = water or GS.maxWater()
    end
    local function isolated(form, x, y, water)
        H.clear()
        player(form, x or 0, y or 0, water)
    end
    local function count(event) return events[event] or 0 end
    local ok, problem = xpcall(function()
        local source = { id = "__gameplay_validation__", progressId = "__elements__", cols = 11, rows = 3,
            originX = 0, originY = 3, tile = 1, spawn = { x = -5, y = -5 },
            map = "P O D A S t\n           \n###########",
            metadata = {
                initialSpawnCell = { col = 9, row = 1 },
                elementProperties = { ["5:1"] = { active = true }, ["7:1"] = { needsPower = true },
                    ["9:1"] = { w = 1.8 }, ["1:1"] = { kind = "fire", x = 100 } },
                wires = { { from = "__elements___0_0", to = "__elements___4_0" },
                    { from = "__elements___2_0", to = "__elements___4_0" },
                    { from = "__elements___2_0", to = "__elements___6_0" } },
            } }
        local def = TM.parse(source)
        V.assert(def.initialSpringId == "__elements___8_0" and def.spawn.x == 8.5
            and math.abs(def.spawn.y - 3.3) < 0.001, "指定泉眼初始出生、米制偏移与旧ID正确")
        V.assert(def.hazards[1].kind == "plate" and def.hazards[1].x == 0.5
            and def.hazards[1].cellKey == "1:1", "格属性不改写元素身份/位置，cellKey保持1基")
        V.assert(def.hazards[3].needsPower and def.hazards[4].needsPower
            and def.hazards[5].w == 1.8, "D/A默认需要供电，合法属性真正传入hazard")
        source.metadata.initialSpawnCell = { col = 11.0, row = 1.0 }
        local arrival = TM.parse(source)
        V.assert(arrival.spawn.x == 10.5 and math.abs(arrival.spawn.y - 2.9) < 0.001
            and arrival.initialSpringId == nil, "浮点JSON整数的t选择可解析且无泉眼绑定")
        source.metadata.initialSpawnCell = nil
        V.assert(TM.parse(source).spawn.x == -5, "无初始选择保持旧spawn而不抢出生点")
        source.metadata.initialSpawnCell = { col = 5, row = 1 }
        V.assert(TM.parse(source).spawn.x == -5, "选中非S/t不覆盖旧spawn")
        source.metadata.initialSpawnCell = { col = 9000, row = 1 }
        V.assert(TM.parse(source).spawn.x == -5, "陈旧越界选择不造成解析失败")

        L.load(testScene, def)
        P.create(testScene, 0.5, 2.5)
        local door = assert(H.getById("__elements___4_0"))
        local plate = assert(H.getById("__elements___0_0"))
        local outlet = assert(H.getById("__elements___2_0"))
        V.assert(L.isSolid(door.x, door.y) and L.doorNodes[1].node.enabled, "未供电门真实碰撞闭合")
        player("solid", plate.x, plate.y)
        local opened = count("doorOpen")
        H.update(0.016, false)
        V.assert(plate.platePressed and door.open and count("doorOpen") == opened + 1
            and not L.isSolid(door.x, door.y), "压板当帧开门，无接口末尾false覆盖，无查询帧延迟")
        L.syncDoors()
        V.assert(not L.doorNodes[1].node.enabled, "电控开门实际禁用Box2D碰撞节点")
        H.update(0.016, false)
        V.assert(count("doorOpen") == opened + 1, "稳定高信号只发一次开门沿")
        player("liquid", 20, 20)
        H.update(0.016, false)
        L.syncDoors()
        V.assert(not plate.platePressed and not door.open and door.active and L.doorNodes[1].node.enabled,
            "离开压板门关闭，active未被断电锁死")
        player("liquid", outlet.x, outlet.y)
        H.update(0.016, true)
        L.syncDoors()
        V.assert(outlet.powered and door.open and not L.doorNodes[1].node.enabled, "装备电鳗靠近接口真实供电开门")
        H.update(0.016, false)
        V.assert(not door.open and not outlet.powered, "移除电鳗同帧断电")
        player("solid", plate.x, plate.y)
        H.update(0.016, false)
        V.assert(door.open, "断电后可重新压板开门")
        plate.active = false
        H.update(0.016, false)
        V.assert(not plate.platePressed and not door.open, "失活压板立即释放，不保留旧高信号")
        V.assert(not H.addWire(door.id, plate.id) and not H.addWire("missing", door.id)
            and not H.addWire(outlet.id, door.id), "无效端点/反向/重复连线不激活")
        H.wires = {}
        door.open = true
        H.updateCircuit(false)
        V.assert(not door.open and not door.powered, "无连线电控门强制闭合，不自动猜配线")
        local manualDef = TM.parse({ id = "__manual__", map = "D", cols = 1, rows = 1,
            metadata = { elementProperties = { ["1:1"] = { needsPower = false, open = true } } } })
        L.load(testScene, manualDef)
        V.assert(L.doorNodes[1].hz.open and not L.doorNodes[1].node.enabled
            and not L.isSolid(0.5, -0.5), "手动常开配置在加载帧同步查询与物理")

        isolated("solid")
        local coldPlate = H.add({ kind = "plate", id = "plate", x = 0, y = 0 })
        local coldDoor = H.add({ kind = "door", id = "door", x = 5, y = 0 })
        H.add({ kind = "cold", x = 0, y = 0 })
        H.addWire("plate", "door")
        player("liquid", 0, 0)
        H.update(0.016, false)
        V.assert(P.form == "solid" and coldPlate.platePressed and coldDoor.open, "同帧低温结冰后压板即生效")
        H.add({ kind = "spring", x = 0, y = 0, id = "spring" })
        H.update(0.016, false)
        V.assert(P.form == "liquid" and not coldPlate.platePressed and not coldDoor.open,
            "同帧泉眼回液态后压板即释放")

        isolated("solid")
        local fire = H.add({ kind = "fire", x = 0, y = 0, w = 2, h = 2 })
        H.add({ kind = "fire", x = 0.1, y = 0, w = 2, h = 2 })
        local waterBefore = GS.save.water
        H.update(0.016, false)
        V.assert(P.form == "liquid" and GS.save.water == waterBefore - 1, "重叠火区仅升温一级并真实扣水")
        H.update(0.016, false)
        V.assert(P.form == "liquid", "持续火接触不会逐帧再次升温")
        player("liquid", 10, 10)
        H.update(0.016, false)
        player("liquid", fire.x, fire.y)
        H.update(0.016, false)
        V.assert(P.form == "gas", "离开再进入火区可再次升温")
        isolated("liquid")
        local weakfire = H.add({ kind = "weakfire", x = 0, y = 0 })
        H.update(0.016, false)
        V.assert(weakfire.usedUp and count("fireExtinguished") > 0, "液态触发弱火熄灭")
        isolated("gas")
        H.add({ kind = "cold", x = 0, y = 0 })
        waterBefore = GS.save.water
        H.update(0.016, false)
        V.assert(P.form == "liquid" and GS.save.water == waterBefore, "低温气态凝回液态，不额外扣水")
        H.update(0.016, false)
        V.assert(P.form == "liquid", "持续冷区接触不逐帧再结冰")

        isolated("liquid")
        fire = H.add({ kind = "fire", x = 0, y = 0, w = 2, h = 2 })
        H.add({ kind = "fire", x = 0.1, y = 0, w = 2, h = 2 })
        waterBefore = GS.save.water
        P.onGround = true
        V.assert(P.tryDash(1), "液态落地真实触发冲刺")
        H.update(0.016, false)
        V.assert(P.form == "liquid" and GS.save.water == waterBefore,
            "冲刺中进入重叠火区不变形也不扣水")
        P.update(Config.DASH.duration + 0.01, { moveX = 0, jumpHeld = false }, {})
        V.assert(not P.dashing, "冲刺时长结束解除无敌")
        H.update(0.016, false)
        V.assert(P.form == "gas" and GS.save.water == waterBefore - 1,
            "冲刺结束仍在火区首次有效接触汽化并只扣一次水")

        isolated("solid")
        fire = H.add({ kind = "fire", x = 0, y = 0, w = 2, h = 2 })
        P.onGround = true
        P.tryDash(1)
        H.update(0.016, false)
        P.update(Config.DASH.duration + 0.01, { moveX = 0, jumpHeld = false }, {})
        H.update(0.016, false)
        V.assert(P.form == "liquid" and P.body.linearVelocity.y == Config.FORMS.liquid.jumpVel,
            "固态冲刺结束受火只熔化一级并自动起跳")
        P.invuln = 0
        H.update(0.016, false)
        V.assert(P.form == "liquid", "补算升温后持续火伤不反复汽化")
        P.onGround = true
        P.dashCd = 0
        P.tryDash(1)
        H.update(0.016, false)
        P.update(Config.DASH.duration + 0.01, { moveX = 0, jumpHeld = false }, {})
        H.update(0.016, false)
        V.assert(P.form == "liquid", "已经升温的连续接触不因再次冲刺重新转换")

        isolated("liquid")
        weakfire = H.add({ kind = "weakfire", x = 0, y = 0 })
        P.onGround = true
        P.tryDash(1)
        H.update(0.016, false)
        V.assert(not weakfire.usedUp and P.form == "liquid", "冲刺免疫时不提前熄灭弱火")
        P.update(Config.DASH.duration + 0.01, { moveX = 0, jumpHeld = false }, {})
        H.update(0.016, false)
        V.assert(weakfire.usedUp and P.form == "gas", "冲刺结束接触弱火才汽化与熄灭")
        isolated("liquid")
        H.add({ kind = "fire", x = 0, y = 0 })
        P.onGround = true
        P.tryDash(1)
        H.update(0.016, false)
        P.node:SetPosition2D(10, 10)
        H.update(0.016, false)
        P.update(Config.DASH.duration + 0.01, { moveX = 0, jumpHeld = false }, {})
        H.update(0.016, false)
        V.assert(P.form == "liquid" and GS.save.water == GS.maxWater(),
            "冲刺已经离开火区后不在安全位置补算火伤")
        isolated("gas")
        H.add({ kind = "cold", x = 0, y = 0 })
        P.tryDash(1)
        H.update(0.016, false)
        V.assert(P.form == "gas", "冲刺进入冷区不提前凝结")
        P.update(Config.DASH.duration + 0.01, { moveX = 0, jumpHeld = false }, {})
        H.update(0.016, false)
        V.assert(P.form == "liquid", "冲刺结束仍在冷区只凝结一级")

        -- 自动起跳在空中也重设初速度，不叠加下降速度，不消耗青蛙二段跳。
        isolated("solid", 0, 10)
        P.body.linearVelocity = Vector2(2, -12)
        P.jumpRising, P.jumpBuffer, P.coyote, P.doubleJumpUsed = true, 0.1, 0.1, true
        local jumps = count("playerJump")
        P.toLiquid()
        V.assert(P.form == "liquid" and P.body.linearVelocity.x == 2
            and P.body.linearVelocity.y == Config.FORMS.liquid.jumpVel
            and not P.jumpRising and P.jumpBuffer == 0 and P.coyote == 0 and P.doubleJumpUsed,
            "固→液重设满跳初速、保留横向速度、清除旧跳跃输入")
        P.update(0.016, { moveX = 0, jumpPressed = false, jumpHeld = false }, {})
        V.assert(P.body.linearVelocity.y == Config.FORMS.liquid.jumpVel,
            "自动起跳不被松开跳跃键截断")
        P.toLiquid()
        V.assert(count("playerJump") == jumps + 1, "同一次固→液只触发一次起跳")
        isolated("gas", 0, 10)
        P.body.linearVelocity = Vector2(0, -2)
        P.toLiquid()
        V.assert(P.body.linearVelocity.y == -2, "气→液凝结不附带固态弹跳")
        isolated("solid", 0, 10)
        P.setForm("liquid", true)
        V.assert(P.body.linearVelocity.y == 0, "静默出生/测试形态初始化不自动跳跃")

        -- 同一个独立物理世界实测两条上升轨迹，自动起跳应与按住键满跳同高。
        local function riseHeight(melting)
            player(melting and "solid" or "liquid", 100, 100)
            P.jumpRising, P.jumpBuffer, P.coyote = false, 0, Config.PLAYER.coyoteTime
            P.grappling, P.swingLock, P.flyDashing = false, 0, false
            if melting then P.toLiquid() end
            local top = P.node.position2D.y
            for i = 1, 160 do
                P.update(1 / 120, { moveX = 0, jumpPressed = not melting and i == 1,
                    jumpHeld = not melting }, {})
                testScene:Update(1 / 120)
                top = math.max(top, P.node.position2D.y)
                if P.body.linearVelocity.y <= 0 then break end
            end
            return top - 100
        end
        local fullJump, meltJump = riseHeight(false), riseHeight(true)
        V.assert(fullJump > 1 and math.abs(fullJump - meltJump) < 0.03,
            string.format("真实物理满跳/融化跳高度一致：%.3f / %.3f 米", fullJump, meltJump))

        -- 飞蝇与玩家圆形外缘相碰即可伤害液/气态，固态免疫但不是所有敌人免疫。
        for _, form in ipairs({ "liquid", "gas", "solid" }) do
            E.clear()
            isolated(form, 100, 100)
            P.blocking = false
            local fly = assert(E.spawn(testScene, "fly", 100.2, 100)) --[[@as Enemy]]
            fly.node:SetPosition2D(100 + fly.radius + Config.FORMS[form].radius, 100)
            fly.state, fly.stateTimer, fly.dashCd = "dash", 0.3, 1
            local before = GS.save.water
            E.update(0.016)
            V.assert(GS.save.water == before - (form == "solid" and 0 or 1),
                "飞蝇外缘接触形态伤害正确：" .. form)
            if form == "gas" then
                P.invuln = 0
                P.onGround = false
                P.tryDash(1)
                E.update(0.016)
                V.assert(GS.save.water == before - 1, "气态仍保留冲刺闪避飞蝇的能力")
            end
        end
        E.clear()
        isolated("solid", 100, 100)
        local chaser = assert(E.spawn(testScene, "cleaner01", 100.2, 100)) --[[@as Enemy]]
        E.update(0.016)
        V.assert(GS.save.water < GS.maxWater(), "固态不免疫非飞行怪的普通接触伤害")

        E.clear()
        isolated("solid", 100, 100)
        local ramEnemy = assert(E.spawn(testScene, "fly", 100.6, 100)) --[[@as Enemy]]
        P.ramming = true
        P.body.linearVelocity = Vector2(Config.PLAYER.ramSpeed + 1, 0)
        local rams = count("ramHit")
        E.update(0.016)
        V.assert(ramEnemy.hp == ramEnemy.maxHp - Config.PLAYER.ramDamage and count("ramHit") == rams + 1
            and math.abs(ramPosition.x - 100.3) < 0.001 and ramPosition.y == 100,
            "固态撞击真实结算伤害并提供接触点特效坐标")
        E.update(0.016)
        V.assert(count("ramHit") == rams + 1, "持续接触冷却期间不重复播放撞击特效")
        ramEnemy.hp = 1
        E.ramTimers = {}
        E.update(0.016)
        V.assert(ramEnemy.dead and count("ramHit") == rams + 2 and ramPosition.x ~= nil,
            "致命撞击移除敌人后仍携带有效特效位置")
        -- 通过原事件总线检查真实特效监听器，不靠替换的计数函数证明视觉接线。
        local originalParticles, originalShakeTime, originalShakeMag = R.particles, R.shakeTime, R.shakeMag
        local originalImpacts = CombatFX.ramImpacts
        R.particles = {}
        CombatFX.ramImpacts = {}
        originalEmit("ramHit", ramEnemy, ramPosition.x, ramPosition.y)
        V.assert(#CombatFX.ramImpacts == 1 and #R.particles == 18 and R.shakeTime > 0,
            "真实撞击监听器生成冲击环、冰蓝碎屑与震屏")
        CombatFX.update(0.5)
        V.assert(#CombatFX.ramImpacts == 0, "撞击特效播放完可靠回收")
        R.particles, R.shakeTime, R.shakeMag = originalParticles, originalShakeTime, originalShakeMag
        CombatFX.ramImpacts = originalImpacts
        E.clear()
        isolated("solid", 100, 100)
        local fatalChaser = assert(E.spawn(testScene, "cleaner01", 100.6, 100)) --[[@as Enemy]]
        fatalChaser.hp = 1
        P.ramming = true
        E.update(0.016)
        V.assert(fatalChaser.dead and GS.save.water == GS.maxWater(),
            "被撞死的地面怪不能同帧继续攻击玩家")

        isolated("liquid", 0, 0, 1)
        local water = H.add({ kind = "water", x = 0, y = 0, charges = 2 })
        H.update(0.06, false)
        V.assert(GS.save.water == 1 + Config.ECONOMY.absorbAmount and water.charges == 1,
            "凝珠真实补水且消耗一次charges")
        H.update(0.06, false)
        V.assert(water.usedUp and water.charges == 0, "配置多次凝珠最后一次消失")
        local absorbed = count("absorbWater")
        H.update(0.06, false)
        V.assert(count("absorbWater") == absorbed, "用尽水源不重复吸收")
        local inactiveWater = H.add({ kind = "water", x = 0, y = 0, active = false })
        GS.save.water = 1
        H.update(0.1, false)
        V.assert(GS.save.water == 1 and inactiveWater.charges == 1, "失活水源不偷触发")
        isolated("liquid")
        water = H.add({ kind = "water", x = 0, y = 0 })
        H.update(0.1, false)
        V.assert(not water.usedUp and water.charges == 1, "满水不吞掉未吸收凝珠")

        isolated("liquid")
        local sponge = H.add({ kind = "sponge", x = 0, y = 0 })
        waterBefore = GS.save.water
        H.update(0.4, false)
        player("liquid", 10, 10)
        H.update(0.01, false)
        player("liquid", 0, 0)
        H.update(0.4, false)
        V.assert(GS.save.water == GS.maxWater(), "海绵分段短接触不攒成一次扣水")
        H.update(0.4, false)
        V.assert(GS.save.water == GS.maxWater() - 1 and sponge.swollen == 1, "海绵连续0.8秒真实扣水与膨胀")
        P.invuln = 0
        H.update(0.8, false)
        V.assert(sponge.usedUp and sponge.swollen == 2, "海绵两次吸水后暂时失效")
        player("liquid", 10, 10)
        H.update(7.2, false)
        V.assert(not sponge.usedUp and sponge.swollen == 0, "海绵超时跨过零秒也可靠复原")

        isolated("solid", 0, 0, 1)
        water = H.add({ kind = "water", x = 10, y = 10, charges = 3 })
        water.usedUp, water.charges = true, 0
        sponge = H.add({ kind = "sponge", x = 10, y = 10 })
        sponge.usedUp, sponge.swollen, sponge.drainTimer = true, 2, 0.7
        weakfire = H.add({ kind = "weakfire", x = 10, y = 10 })
        weakfire.usedUp = true
        local spring = H.add({ kind = "spring", x = 0, y = 0, id = "spring_check" })
        local oldSaves = saves
        H.update(0.016, false)
        V.assert(P.form == "liquid" and GS.save.water == GS.maxWater() and GS.save.spring == spring.id
            and saves == oldSaves + 1, "泉眼真实回液态补满绑定并发起存档")
        V.assert(not water.usedUp and water.charges == 3 and not sponge.usedUp and sponge.drainTimer == 0
            and not weakfire.usedUp, "泉眼重置水源charges/海绵计时/弱火")
        H.update(0.016, false)
        V.assert(saves == oldSaves + 1, "持续站泉眼不重复存档")
        isolated("liquid", 0, 0, 1)
        H.add({ kind = "fire", x = 0, y = 0 })
        spring = H.add({ kind = "spring", x = 0, y = 0, id = "must_not_save" })
        oldSaves = saves
        H.update(0.016, false)
        V.assert(P.dead and GS.save.water == 0 and saves == oldSaves and not spring.touched,
            "致命火伤同帧不靠泉眼回血/存档")

        isolated("gas", 0, 1)
        outlet = H.add({ kind = "outlet", x = 0, y = 1, id = "power" })
        local alarm = H.add({ kind = "alarm", x = 0, y = 2, id = "alarm" })
        H.addWire("power", "alarm")
        H.update(0.5, false)
        V.assert(count("alarmSpray") == 0, "报警器无电不喷洒")
        H.update(0.6, true)
        player("gas", 10, 10)
        H.update(0.01, true)
        player("gas", 0, 1)
        H.update(0.6, true)
        V.assert(count("alarmSpray") == 0, "报警器离开/断电归零不攒旧接触")
        H.update(0.4, true)
        local sprayWater = H.list[#H.list]
        V.assert(alarm.powered and count("alarmSpray") == 1 and sprayWater.kind == "water"
            and sprayWater.temporary and sprayWater.respawnTimer == 5, "报警器当前帧电鳗+气态实际喷出临时水")
        player("liquid", sprayWater.x, sprayWater.y, 1)
        H.update(0.06, false)
        V.assert(sprayWater.usedUp and GS.save.water == 1 + Config.ECONOMY.absorbAmount,
            "报警器水源可实际吸收补水")
        player("liquid", 10, 10)
        H.update(5.1, false)
        V.assert(not sprayWater.active and sprayWater.usedUp, "报警器临时水到期实际失效")
        H.resetWaters()
        V.assert(sprayWater.usedUp, "泉眼不复活报警器临时水")
        isolated("gas", 0, 1)
        alarm = H.add({ kind = "alarm", x = 0, y = 2, needsPower = false })
        H.update(1, false)
        V.assert(alarm.powered and count("alarmSpray") == 2, "显式无需供电报警器可工作")

        H.clear()
        local pickupMap = "$QHaeljrngwuhoipX12yscbmB Tt"
        local pickups = TM.parse({ id = "__pickups__", map = pickupMap, cols = #pickupMap, rows = 1 })
        L.load(testScene, pickups)
        player("liquid", -10, 10)
        for _, item in ipairs(L.itemNodes) do
            local before = count("itemPickup")
            L.checkItems(item.x, item.y, 0.1)
            V.assert(item.taken and GS.save.flags[item.flagKey] and count("itemPickup") > before,
                "每个拾取物按位置真正触发且设置稳定flag: " .. item.kind)
        end
        local picked = count("itemPickup")
        for _, item in ipairs(L.itemNodes) do L.checkItems(item.x, item.y, 0.1) end
        V.assert(count("itemPickup") == picked and #GS.save.fish == 8 and #GS.save.relics == 5
            and GS.save.shells == Config.ECONOMY.pickupShellValue and GS.save.fragments == 1 and GS.save.pieces == 1,
            "所有鱼/饰品/贝壳/碎片奖励实际到账且不重复")
        local crate = assert(L.crateNodes[1]) --[[@as table]]
        V.assert(L.crateAt(crate.x, crate.y) == crate and L.isSolid(crate.x, crate.y), "箱真实参与碰撞与命中查询")
        V.assert(not L.damageCrate(crate, 1) and crate.hp == 3, "箱受伤但未破坏")
        V.assert(L.damageCrate(crate, 3) and crate.destroyed and L.crateAt(crate.x, crate.y) == nil
            and not L.isSolid(crate.x, crate.y) and count("crateBroken") == 1, "箱耗尽生命实际移除碰撞且发破坏事件")
        V.assert(not L.damageCrate(crate, 1) and count("crateBroken") == 1, "已破坏箱不重复结算")
        local enemy = E.list[1]
        player("liquid", enemy.node.position2D.x + 0.1, enemy.node.position2D.y)
        waterBefore = GS.save.water
        enemy.atkTimer = 0
        E.update(0.016)
        E.update(E.attackAnimTime(enemy.def) * Config.HIT_FX.meleeHitAt + 0.01)
        V.assert(GS.save.water < waterBefore and count("enemyMelee") > 0, "地图敌人AI在接近玩家时真实攻击扣水")
        local killed = count("enemyKilled")
        for _, e in ipairs(E.list) do
            local hp = e.hp
            E.damage(e, 1)
            V.assert(e.hp < hp and e.hitFlash > 0, "每种敌人可实际受击: " .. e.def.name)
            E.damage(e, hp + 1)
            V.assert(e.dead, "每种敌人生命归零实际死亡: " .. e.def.name)
        end
        V.assert(count("enemyKilled") == killed + 8 and count("dropShell") > 0,
            "8种地图敌人可击杀并触发掉落，不是纯图标")
        local exit = assert(pickups.exits[1]) --[[@as table]]
        V.assert(L.checkExit(exit.x, exit.y) == exit and L.checkExit(-10, 10) == nil,
            "章节模式T出口有真实触发区域，t落点保留")
        local seamless = TM.parse({ id = "__seamless__", seamless = true, map = "Tt", cols = 2, rows = 1 })
        V.assert(#seamless.exits == 0 and #seamless.portals == 0 and seamless.arrival ~= nil,
            "无缝模式不误生成章节切换出口")
    end, debug.traceback)

    -- 即使断言抛错也恢复整个运行环境，不把测试Scene/存档留给后续帧。
    P.destroy()
    for _, key in ipairs(playerFields) do P[key] = savedPlayer[key] end
    for _, key in ipairs(levelFields) do L[key] = savedLevel[key] end
    H.list, H.wires, E.list = originalHazards, originalWires, originalEnemies
    E.ramTimers = originalRamTimers
    H.resetTemperatureContacts()
    GS.save, GS.emit, GS.saveGame = originalSave, originalEmit, originalSaveGame
    GS.mode, GS.pendingMode = originalMode, originalPending
    if testScene then testScene:Dispose(); testScene = nil end
    V.assert(ok, "玩法元素触发验收完成: " .. tostring(problem or "通过"))
end)
