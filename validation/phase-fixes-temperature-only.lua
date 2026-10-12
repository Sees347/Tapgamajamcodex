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

    GS.setMode("paused")
end)
