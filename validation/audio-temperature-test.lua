-- 音频与温度回归：纯内存存档，泉眼测试临时替换存档函数，绝不覆盖玩家文件。
local GS = require "core/state"
local P = require "core/player"
local H = require "core/hazards"
local B = require "core/bullets"
local BF = require "core/bossfx"
local A = require "core/abilities"
local E = require "core/enemies"
local L = require "core/level"
local Config = require "config"
local Audio = require "core/audio"
local HUD = require "ui/hud"
local Menus = require "ui/menus"
local R = require "core/render"

local signals = {}
GS.on("sfx", function(key) signals[key] = (signals[key] or 0) + 1 end)
local function pos(x, y)
    P.node:SetPosition2D(x, y or 100)
    P.body.linearVelocity = Vector2(0, 0)
end
local function fresh(form)
    H.clear()
    B.clear()
    BF.reset()
    GS.save.water = 12
    GS.save.relics = {}
    P.dead = false
    P.invuln = 0
    P.setForm(form, true)
    pos(200, 100)
end
local function zone(kind, x)
    return H.add({ kind = kind, x = x or 200, y = 100, w = 2, h = 2 })
end
local function tick(n, dt)
    for _ = 1, n do H.update(dt or 1 / 60, false) end
end
local function form(expected, label)
    V.assert(P.form == expected, label .. ": " .. P.form)
end
local function findButton(widget, text)
    if widget.props.text == text and widget.props.onClick then return widget end
    for _, child in ipairs(widget:GetChildren()) do
        local found = findButton(child, text)
        if found then return found end
    end
end
local function click(text)
    local overlay = HUD.root:FindById("overlay")
    local button = overlay and findButton(overlay, text)
    V.assert(button ~= nil, "界面存在按钮: " .. text)
    if button then button.props.onClick(button) end
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
    GS.setMode("paused")

    fresh("gas")
    zone("cold")
    tick(1)
    form("liquid", "气态进入低温只凝为液态")
    tick(120)
    form("liquid", "冷区持续停留不连续结冰")
    V.assert(GS.save.water == 12, "低温区不扣水")
    pos(205); tick(1); pos(200); tick(1)
    form("solid", "离开冷区重新进入液态结冰")
    tick(60); form("solid", "冰态停留不变")

    fresh("solid"); zone("fire"); tick(1)
    form("liquid", "冰态碰火只熔成液态")
    V.assert(GS.save.water == 11, "首个火接触只扣一次水")
    tick(60); form("liquid", "持续碰火不自动汽化")
    P.invuln = 0; tick(1)
    V.assert(GS.save.water == 10, "保留持续灼烧伤害")
    form("liquid", "第二次灼烧不再次变形")
    pos(205); tick(1); pos(200); tick(1)
    form("gas", "液态重新碰火变气态")

    fresh("liquid"); zone("fire"); tick(1); form("gas", "液态首次碰火汽化")
    fresh("solid"); local weak = zone("weakfire"); tick(1)
    form("liquid", "冰态碰弱火只熔化")
    tick(5); form("liquid", "弱火不会次帧再汽化")
    fresh("liquid"); weak = zone("weakfire"); tick(1)
    form("gas", "液态碰弱火汽化")
    V.assert(weak.usedUp, "液态熄灭弱火")

    fresh("gas"); zone("cold", 199.5); zone("cold", 200.5); tick(1)
    form("liquid", "两个重叠冷区合为一次接触")
    tick(30); form("liquid", "重叠冷区停留不重复")
    fresh("solid"); zone("fire", 199.5); zone("fire", 200.5); tick(1)
    form("liquid", "重叠火区不跳过液态")
    V.assert(GS.save.water == 11, "重叠火区同帧只扣一次水")
    pos(200.9); tick(1); form("liquid", "在连续火区间移动不再次汽化")

    fresh("gas"); zone("cold"); pos(201.46); tick(1)
    form("liquid", "冷区擦边气态进入")
    tick(30); form("liquid", "半径缩小不造成假重入")
    pos(201.51); tick(1); pos(201.3); tick(1)
    form("solid", "彻底离开边界后重入才结冰")

    fresh("gas"); local delayed = zone("cold")
    delayed.active = false; delayed.waveDelay = 0.1
    tick(1, 0.05); form("gas", "延迟区未激活不转换")
    tick(1, 0.06); form("liquid", "脚下延迟区激活算首次进入")
    tick(10); form("liquid", "延迟区激活后不重复转换")
    delayed.active = false; tick(1); delayed.active = true; tick(1)
    form("solid", "区域失效后重新激活允许再进入")

    fresh("gas"); local expired = zone("cold")
    expired.temporary = true; expired.respawnTimer = 0.01
    tick(1, 0.02); form("gas", "已到期临时冷区不幽灵命中")
    fresh("gas"); zone("cold"); tick(1)
    P.teleport(200, 100); tick(1)
    form("solid", "传送清理温度接触生命周期")
    fresh("solid"); zone("fire"); P.invuln = 2; tick(1)
    form("liquid", "受伤无敌不阻止首次环境熔化")
    V.assert(GS.save.water == 12, "无敌挡火伤害")
    fresh("solid"); zone("fire"); GS.save.relics = { "heatCrystal" }; tick(1)
    form("liquid", "火抗抵消伤害不阻止熔化")
    V.assert(GS.save.water == 12, "火抗保持原减伤")

    for _, dt in ipairs({ 1 / 30, 1 / 60, 1 / 120 }) do
        fresh("gas"); zone("cold"); tick(1, dt); tick(60, dt)
        form("liquid", "不同帧率冷区转换一致 " .. dt)
    end

    fresh("solid"); P.onElementHit("fire", 2, Config.DMG.ENEMY)
    form("liquid", "火元素弹固态只熔化一级")
    V.assert(GS.save.water == 10, "元素弹仅扣自身伤害")
    P.onElementHit("fire", 2, Config.DMG.ENEMY)
    form("liquid", "无敌挡后续火弹")
    P.invuln = 0; P.onElementHit("fire", 1, Config.DMG.ENEMY)
    form("gas", "下一次有效火弹将液态汽化")
    fresh("gas"); P.onElementHit("ice", 1, Config.DMG.ENEMY)
    form("liquid", "冰元素弹气态不直接强制冰态")
    V.assert(GS.save.water == 11, "冰弹伤害只扣一次")
    fresh("liquid"); P.onElementHit("ice", 1, Config.DMG.ENEMY)
    form("solid", "液态冰弹结冰")
    B.clear(); B.spawnEnemyBullet(210, 100, 0, -1, 8, 1, Config.PAL.bossFire, 2, "fire")
    V.assert(B.list[1].element == "fire", "敌人火弹保留元素标记")
    B.clear(); B.spawnEnemyBullet(210, 100, 0, -1, 8, 1, Config.PAL.bossIce, 1, "ice")
    V.assert(B.list[1].element == "ice", "敌人冰柱保留元素标记")

    fresh("gas")
    BF.rings = { { x = 200, y = 100, radius = 0.5, speed = 0, maxRadius = 12, hitPlayer = false } }
    BF.update(0); form("liquid", "冰环也只凝结一级")
    BF.update(0); form("liquid", "同一冰环不重复命中")
    V.assert(GS.save.water == 11, "冰环只扣一次原伤害")

    fresh("solid")
    GS.setMode("playing")
    B.spawn({ x = 200, y = 100, dx = 0, dy = 0, speed = 1, range = 10,
        dmg = 1, fromEnemy = true, element = "fire" })
    local updateEvent = VariantMap()
    updateEvent["TimeStep"] = 0.001
    HandleUpdate("Update", updateEvent)
    form("liquid", "主循环真实火弹命中也只熔化一级")
    V.assert(GS.save.water == 11, "主循环火弹只有一次伤害")
    B.clear()
    P.invuln = 2
    local farBullet = B.spawn({ x = 210, y = 100, dx = 0, dy = 0, speed = 1, range = 10,
        dmg = 1, fromEnemy = true, element = "fire" })
    HandleUpdate("Update", updateEvent)
    V.assert(not farBullet.dead, "受伤无敌不清除远处尚未命中的敌弹")
    local nearBullet = B.spawn({ x = 200, y = 100, dx = 0, dy = 0, speed = 1, range = 10,
        dmg = 1, fromEnemy = true, element = "fire" })
    HandleUpdate("Update", updateEvent)
    V.assert(nearBullet.dead and GS.save.water == 11, "无敌期只消耗真正碰到玩家的弹丸且不扣水")
    form("liquid", "无敌期实际命中不再次变形")
    GS.setMode("paused")
    fresh("gas")
    local bossNode = P.node.parent:CreateChild("TemperatureTestBoss")
    bossNode:SetPosition2D(200, 100)
    BF.wave({ node = bossNode, facing = 1 }, "fire")
    P.setForm("solid", true); pos(203.9, 99.3); tick(1, 0.3)
    form("liquid", "实际BOSS火浪相邻段不连续汽化")
    tick(10); form("liquid", "实际BOSS火浪停留保持液态")
    bossNode:Dispose()

    fresh("liquid")
    GS.setMode("playing")
    L.platformRects = { { x = 200, y = 0, w = 10, h = 1 } }
    P.onGround = false
    P.node:SetPosition2D(200, 3)
    P.body.linearVelocity = Vector2(0, 3)
    local landingBefore = signals.landing or 0
    GS.emit("playerJump")
    DetectGround()
    V.assert(not P.onGround and (signals.landing or 0) == landingBefore,
        "跳跃上升未触地不播放落地声")
    P.node:SetPosition2D(200, 0.96)
    P.body.linearVelocity = Vector2(0, -3)
    DetectGround()
    V.assert(P.onGround and signals.landing == landingBefore + 1,
        "跳跃下落首次触地播放一次史莱姆落地声")
    DetectGround()
    V.assert(signals.landing == landingBefore + 1, "站在地面不重复播放落地声")

    fresh("liquid")
    GS.setMode("playing")
    L.platformRects = { { x = 200, y = 0, w = 10, h = 1 } }
    P.node:SetPosition2D(200, 0.96)
    P.body.linearVelocity = Vector2(0, 0)
    P.onGround = false
    DetectGround()
    V.assert(P.onGround, "高处坠落测试先站上平台")
    L.platformRects = {}
    P.body.linearVelocity = Vector2(0, -2)
    DetectGround()
    V.assert(not P.onGround and (signals.landing or 0) == landingBefore + 1,
        "离开高台开始下落时不提前播放落地声")
    L.platformRects = { { x = 300, y = 0, w = 10, h = 1 } }
    P.node:SetPosition2D(300, 0.96)
    P.body.linearVelocity = Vector2(0, -5)
    DetectGround()
    V.assert(P.onGround and signals.landing == landingBefore + 2,
        "从高台坠落落地播放一次史莱姆落地声")
    DetectGround()
    V.assert(signals.landing == landingBefore + 2, "高台落地后保持站立不重复播放")

    P.teleport(300, 3)
    P.node:SetPosition2D(300, 3)
    P.body.linearVelocity = Vector2(0, -2)
    P.onGround = false
    DetectGround()
    V.assert(not P.onGround and signals.landing == landingBefore + 2,
        "传送后仍可追踪出生下落但不会误播")
    P.node:SetPosition2D(300, 0.96)
    P.body.linearVelocity = Vector2(0, -2)
    DetectGround()
    V.assert(signals.landing == landingBefore + 3,
        "传送后的下落触地仍能播放落地声")

    fresh("liquid")
    local count = signals.waterShot or 0
    local ctx = { playerPos = Vector2(200, 100), aimWorld = Vector2(205, 100), spawnBullet = B.spawn }
    A.fireOne("__base__", { dir = "mouse" }, A.currentEffects(), ctx)
    V.assert((signals.waterShot or 0) == count + 1, "基础水弹发射事件")
    A.fireOne("archerfish", { dir = "mouse" }, A.currentEffects(), ctx)
    V.assert((signals.waterShot or 0) == count + 2, "射水鱼水球发射事件")
    P.setForm("solid", true)
    A.fireOne("archerfish", { dir = "mouse" }, A.currentEffects(), ctx)
    V.assert((signals.waterShot or 0) == count + 2, "冰锥不用水弹声")
    P.setForm("gas", true)
    A.fireOne("eel", { dir = "down" }, A.currentEffects(), ctx)
    V.assert((signals.waterShot or 0) == count + 2, "闪电不用水弹声")
    fresh("liquid")
    GS.setMode("paused")
    pos(0, 1.2)
end)

V.atFrame(90, function()
    for _, key in ipairs({ "menu", "game", "click", "absorb", "spring", "waterShot", "bulletHit", "landing", "robotLaser" }) do
        local sound = Audio.getSound(key)
        V.assert(sound ~= nil and sound:GetLength() > 0, key .. " 实际引擎可解码")
        if sound then
            V.assert(math.abs(sound:GetFrequency() - 44100) < 1, key .. " 采样率正确")
            V.assert(sound:IsLooped() == (key == "menu" or key == "game"), key .. " 循环标记正确")
        end
    end
    local wanted, current, source = Audio.getMusicState()
    V.assert(wanted == "game" and current == "game" and source ~= nil, "进入关卡启用游戏BGM")
    if source then
        V.assert(source:GetSound() == Audio.getSound("game"), "BGM声音实例绑定正确资源")
        V.assert(math.abs(source:GetFrequency() - 44100) < 1, "BGM使用绝对采样率原速播放")
        source:Seek(3)
        local before = source:GetTimePosition()
        GS.setMode("playing"); GS.setMode("paused"); GS.setMode("dialog")
        local _, nextKey, nextSource = Audio.getMusicState()
        V.assert(nextKey == "game" and nextSource == source, "暂停剧情不重建BGM实例")
        V.assert(math.abs(source:GetTimePosition() - before) < 0.01, "暂停剧情不重头播放BGM")
        V.assert(math.abs(source:GetGain() - 0.35 * 0.6) < 0.001, "剧情背景音乐降音量")
    end
    GS.setMode("menu")
    local _, key, menuSource = Audio.getMusicState()
    V.assert(key == "menu" and menuSource:GetSound() == Audio.getSound("menu"), "回主菜单切主界面BGM")
    Audio.update(1)
    V.assert(Audio.playEffect("click"), "菜单点击可播放")
    V.assert(not Audio.playEffect("waterShot"), "菜单不播放战斗音效")
    V.assert(not Audio.playEffect("transform"), "未上传变形音效不乱套其他声音")
    GS.setMode("playing")
    Audio.update(1)
    for _, effect in ipairs({ "waterShot", "bulletHit", "absorb", "spring", "landing" }) do
        V.assert(Audio.playEffect(effect), effect .. " 开始播放")
    end
    V.assert(not Audio.playEffect("waterShot"), "密集同类音效节流")
    Audio.setVolumes(0, 0)
    V.assert(not Audio.playEffect("click"), "音效静音生效")
    local _, _, bgm = Audio.getMusicState()
    V.assert(bgm:GetGain() == 0, "BGM静音生效")
    Audio.setVolumes(1, 1)
    local music, effects = Audio.getVolumes()
    V.assert(music == 1 and effects == 1, "独立音量可恢复")

    -- 泉眼事件只替换测试期间的写盘函数，真实存档文件保持不变。
    local saveGame = GS.saveGame
    local saveCount = 0
    GS.saveGame = function() saveCount = saveCount + 1 end
    fresh("liquid"); zone("spring")
    local springBefore = signals.spring or 0
    tick(1); tick(3)
    V.assert(saveCount == 1 and signals.spring == springBefore + 1, "泉眼持续接触只存档并播一次")
    pos(205); tick(1); pos(200); tick(1)
    V.assert(saveCount == 2 and signals.spring == springBefore + 2, "再次进入泉眼重新播放存档音效")
    GS.saveGame = saveGame
    fresh("liquid"); zone("water"); GS.save.water = 5
    local absorbBefore = signals.absorb or 0
    tick(1, 0.3)
    V.assert(GS.save.water == 6 and signals.absorb == absorbBefore + 1, "实际吸水产生补水音效事件")

    fresh("liquid")
    pos(0, 1.2)
    GS.setMode("playing")
    Menus.showPause()
    V.assert(GS.mode == "paused", "带音量控件的暂停菜单正常创建")
    click("装备与图鉴")
    click("关闭")
    local overlay = HUD.root:FindById("overlay")
    V.assert(GS.mode == "paused" and overlay and overlay:IsVisible() and findButton(overlay, "继续游戏") ~= nil,
        "暂停菜单打开装备再关闭仍显示暂停菜单")
    Menus.resumeFromPause()
    GS.save.fish = { "archerfish" }
    GS.save.equipped = {}
    Menus.showInventory()
    click("装备")
    click("关闭")
    V.assert(GS.mode == "playing", "游戏中打开装备并刷新列表后关闭正确恢复游戏")
    Audio.update(1)
    local clickBefore = signals.click or 0
    Menus.showPause(); click("继续游戏")
    V.assert(signals.click == clickBefore + 1, "真实菜单按钮回调发出点击音效")
    R.flashTime = 0; R.shakeTime = 0; P.hurtFlash = 0; P.invuln = 0
    GS.setMode("paused")
end)

V.atFrame(130, function()
    Audio.shutdown()
    V.assert(Audio.getSound("game") == nil and not Audio.playEffect("click"), "停止时释放音频并拒绝播放")
    Audio.init()
end)
V.atFrame(155, function()
    V.assert(Audio.getSound("game") ~= nil, "重新初始化音频可恢复加载")
    fresh("liquid")
    GS.save.water = 1
    zone("fire"); zone("spring")
    local saveGame = GS.saveGame
    local saved = false
    GS.saveGame = function() saved = true end
    tick(1)
    V.assert(P.dead and GS.save.water == 0 and not saved,
        "致命火焰与泉眼重叠不在死亡后回血或写盘")
    GS.saveGame = saveGame
    GS.setMode("menu")
    HUD.setGameHudVisible(false)
    Menus.showMainMenu()
end)
