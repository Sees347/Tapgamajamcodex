-- 离屏验证：只使用内存存档，不调用 GS.newGame/GS.saveGame。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local A = require "core/abilities"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local HUD = require "ui/hud"
local R = require "core/render"

local function expect(key, label)
    local active = Art.getPlayback()
    V.assert(active == key, label .. ": " .. tostring(active))
end

local function steady()
    P.onGround = true
    P.body.linearVelocity = Vector2(0, 0)
    P.body.gravityScale = 0
end

local function testTurns()
    GS.save.equipped = {}
    for _, form in ipairs({ "liquid", "solid", "gas" }) do
        P.form = form
        steady()
        P.facing = -1
        Art.reset()
        local clip = clips[form .. "_turn"]
        V.assert(clip ~= nil and not clip.loop and clip.count / clip.fps == 0.25, form .. "转身配置为单次0.25秒")
        V.assert(cache:Exists(clip.path), form .. "转身图集存在")
        local radius = P.bodyShape.radius
        local position = P.node.position2D
        for _, facing in ipairs({ 1, -1 }) do
            P.facing = facing
            Art.update(0)
            expect(form .. "_turn", form .. "双向转身")
            local _, first = Art.getPlayback()
            V.assert(first == 1, form .. "双向转身从首帧开始")
            Art.update(1 / clip.fps)
            local _, second = Art.getPlayback()
            V.assert(second == 2, form .. "按配置逐帧推进")
            Art.update(0.5)
            expect(form .. "_idle", form .. "转完恢复待机")
        end
        P.facing = 1
        Art.update(0)
        Art.update(2 / clip.fps)
        local _, middle = Art.getPlayback()
        P.facing = -1
        Art.update(0)
        local _, reversed = Art.getPlayback()
        V.assert(reversed == middle, form .. "快速反向保持当前帧，不跳首帧")
        Art.update(1 / clip.fps)
        local _, previous = Art.getPlayback()
        V.assert(previous == middle - 1, form .. "快速反向倒播到最新朝向")
        P.facing = 1
        Art.update(0)
        local _, resumed = Art.getPlayback()
        V.assert(resumed == previous, form .. "再次反向仍保持帧连续")
        Art.update(0.5)
        expect(form .. "_idle", form .. "连续反向结束朝向正确")
        V.assert(P.facing == 1 and P.bodyShape.radius == radius, form .. "表现层不改朝向与碰撞")
        V.assert(P.node.position2D.x == position.x and P.node.position2D.y == position.y, form .. "转身不改物理位置")

        P.facing = -1
        Art.reset()
        P.facing = 1
        Art.update(0)
        Art.update(form == "solid" and 0.0625 or 0.10)
        local _, alternatingStart = Art.getPlayback()
        local progressed = false
        for i = 1, 20 do
            P.facing = -P.facing
            Art.update(i % 2 == 1 and 0.04 or 0.01)
            local key, frame = Art.getPlayback()
            if key ~= form .. "_turn" or frame ~= alternatingStart then progressed = true end
        end
        V.assert(progressed, form .. "不等间隔连续反向保留亚帧进度，不冻结中间帧")
        Art.update(0.5)
        expect(form .. "_idle", form .. "交替转向后可正常结束")
        Art.reset()
        P.facing = -P.facing
        Art.update(0)
        GS.mode = "paused"
        local _, frozen = Art.getPlayback()
        Art.update(1)
        local _, paused = Art.getPlayback()
        V.assert(paused == frozen, form .. "暂停不推进转身")
        GS.mode = "playing"
        Art.reset()
        expect(form .. "_idle", form .. "重置清除转身")
        P.onGround = false
        P.facing = 1
        Art.update(0)
        expect(form == "gas" and "gas_turn" or form .. "_jump", form .. "空中动作优先级")
        steady()
        Art.reset()
    end

    P.form = "liquid"
    P.facing = 1
    Art.reset()
    GS.save.equipped = { "flyfish" }
    P.facing = -1
    Art.update(0)
    expect("liquid_flyfish", "装备组合当帧不被普通转身替换")
    GS.save.equipped = {}
    Art.reset()
    P.facing = 1
    Art.update(0)
    P.onGround = false
    Art.update(0)
    expect("liquid_jump", "起跳抢断液态转身")
    steady()
    Art.reset()
    P.form = "solid"
    Art.reset()
    P.facing = -1
    Art.update(0)
    GS.save.equipped = { "eel" }
    V.assert(Art.triggerElectric(), "冰电可抢断固态转身")
    expect("solid_electric", "冰电动作优先于转身")
    P.facing = 1
    Art.update(0)
    expect("solid_electric", "冰电中转向不抢断技能")
    GS.save.equipped = {}
    P.form = "gas"
    Art.reset()
    P.facing = -1
    Art.update(0)
    GS.emit("playerAttack")
    expect("gas_attack", "气态攻击抢断转身")
    Art.update(1)
    P.facing = 1
    Art.update(0)
    GS.emit("playerHurt", "enemy")
    expect("gas_hurt", "气态受击抢断转身")
    P.form = "liquid"
    Art.reset()
    P.facing = -1
    Art.update(0)
    P.setForm("solid")
    expect("liquid_to_solid", "变形抢断转身")
    P.facing = 1
    Art.update(0)
    expect("liquid_to_solid", "变形中转向不抢断变形")
    Art.update(1)
    expect("solid_idle", "变形后不补播过时转身")
    P.setForm("liquid")
    Art.update(1)
    P.facing = 1
    steady()
    Art.reset()
end

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    HUD.hideOverlay()
    E.clear()
    H.clear()
    L.storyZones = {}
    L.itemNodes = {}
    P.body.gravityScale = 0
    GS.mode = "paused"
    steady()
    Art.reset()
    GS.mode = "playing"
    testTurns()
    Art.update(0)
    expect("liquid_idle", "液态待机")
    P.body.linearVelocity = Vector2(3, 0)
    Art.update(0)
    expect("liquid_move", "液态移动")

    -- 朝向反转时先播放一次转身图集，再回到当前移动姿态。
    P.facing = 1
    Art.update(0)
    P.facing = -1
    Art.update(0)
    expect("liquid_turn", "液态朝向反转播放转身动画")
    local _, turnFrame1 = Art.getPlayback()
    Art.update(0.12)
    local turnKey, turnFrame2 = Art.getPlayback()
    V.assert(turnKey == "liquid_turn" and turnFrame2 ~= turnFrame1, "转身图集随时间推进")
    Art.update(0.5)
    expect("liquid_move", "转身结束恢复液态移动")

    P.onGround = false
    P.body.linearVelocity = Vector2(0, 4)
    Art.update(0)
    expect("liquid_jump", "液态跳跃")
    local _, frame1 = Art.getPlayback()
    Art.update(0.12)
    local _, frame2 = Art.getPlayback()
    V.assert(frame2 ~= frame1, "序列帧随时间推进")

    steady()
    GS.save.equipped = { "flyfish", "anglerfish" }
    Art.reset()
    Art.update(0)
    expect("liquid_flyfish", "第一个槽位飞鱼外观优先")
    GS.save.equipped = { "anglerfish", "flyfish" }
    Art.update(0)
    expect("liquid_anglerfish", "第一个槽位鮟鱇鱼外观优先")
    Art.update(2)
    local _, held = Art.getPlayback()
    V.assert(held >= 9, "鮟鱇鱼合体后保持完成外观，不重复变形")
    GS.save.equipped = {}
    Art.update(0)
    expect("liquid_anglerfish_off", "卸下鮟鱇鱼播放解除动画")
    Art.update(1)
    expect("liquid_idle", "解除后恢复液态")

    P.setForm("solid")
    expect("liquid_to_solid", "液态变冰态")
    Art.update(1)
    steady()
    Art.update(0)
    expect("solid_idle", "冰态待机")
    local radius = P.bodyShape.radius
    GS.save.equipped = { "eel" }
    local data = VariantMap()
    data["Key"] = KEY_E
    HandleKeyDown("KeyDown", data)
    expect("solid_electric", "E键触发冰态电鳗技能动画")
    V.assert(P.bodyShape.radius == radius, "电鳗动画不改变碰撞")
    Art.update(1)
    steady()
    Art.update(0)
    expect("solid_idle", "冰电结束回到待机")
    GS.save.equipped = {}
    V.assert(not Art.triggerElectric(), "未装备电鳗不触发冰电")

    P.setForm("gas")
    expect("solid_to_gas", "冰态变气态")
    Art.update(1)
    steady()
    Art.update(0)
    expect("gas_idle", "气态待机")
    GS.emit("playerAttack")
    expect("gas_attack", "气态攻击动画")
    Art.update(1)
    GS.emit("playerHurt", "enemy")
    expect("gas_hurt", "气态受击动画")
    Art.update(1)
    P.setForm("liquid")
    expect("gas_to_liquid", "气态变液态")
    Art.update(1)
    V.assert(math.abs(P.bodyShape.radius - 0.42) < 0.00001, "变形后液态碰撞半径未改动")
    V.assert(Art.fishIcon("eel") ~= nil, "电鳗图标存在")
    V.assert(Art.fishIcon("frog") ~= nil, "青蛙图标存在")
    V.assert(Art.fishIcon("barnacle") ~= nil, "藤壶图标存在")
    V.assert(Art.fishIcon("swordfish") ~= nil, "剑鱼图标存在")
    local turnClip = clips.liquid_turn
    V.assert(turnClip ~= nil and turnClip.count == 8 and turnClip.fps == 32, "液态背侧转身图集配置完整")
    V.assert(cache:Exists(turnClip.path), "液态转身图集可加载")

    GS.save.equipped = { "eel" }
    P.setForm("solid")
    V.assert(Art.triggerElectric(), "变形期间接受E技能动画请求")
    expect("liquid_to_solid", "E键不抢断变形")
    Art.update(0.6)
    expect("solid_electric", "变形后补播冰电")
    Art.update(1)
    GS.save.equipped = { "flyfish" }
    P.setForm("liquid")
    V.assert(not Art.isIntegrated("flyfish"), "变回液态途中不提前隐藏跟随鱼")
    Art.update(0.6)
    expect("liquid_flyfish", "变形结束恢复装备组合")

    GS.save.fish = { "archerfish", "eel", "flyfish", "anglerfish", "ray" }
    GS.save.cores = 4
    GS.save.equipped = { "anglerfish", "flyfish", "eel", "archerfish", "ray" }
    steady()
    Art.reset()
    Art.update(0)
    Art.update(1)
    HUD.refreshAll()
    P.invuln = 0
    P.hurtFlash = 0
    P.formFlash = 0
    R.flashTime = 0
    R.shakeTime = 0
    GS.mode = "paused"
end)

-- 在 NanoVGRender 事件内检查真正的图集采样，不在逻辑回调中画图。
local rendered = false
SubscribeToEvent("NanoVGRender", function()
    if rendered or GS.mode ~= "paused" or not P.node then return end
    local vg = R.vg
    if not vg then return end
    rendered = true
    nvgBeginFrame(vg, R.screenW, R.screenH, 1)
    V.assert(Art.drawPlayer(vg, 300, 300, R.ppu), "主角使用真实图集而非兜底轮廓")
    for i, key in ipairs({ "archerfish", "eel", "flyfish", "anglerfish", "ray", "swordfish", "barnacle", "frog" }) do
        V.assert(Art.drawFish(vg, key, 0.4, 400 + i * 50, 300, 38, 26, -1), key .. "鱼图集加载及切帧")
    end
    nvgEndFrame(vg)
end)

V.atFrame(135, function()
    V.assert(rendered, "实际执行过资源绘制验证")
end)
