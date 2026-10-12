-- ============================================================================
-- main.lua - 《涌泉》主入口
-- 2D 类银河战士恶魔城：水精灵以水量为生命，三形态转化，鱼共生装备弹幕
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local P = require "core/player"
local A = require "core/abilities"
local B = require "core/bullets"
local E = require "core/enemies"
local H = require "core/hazards"
local L = require "core/level"
local BF = require "core/bossfx"
local R = require "core/render"
local Art = require "core/art"
local Audio = require "core/audio"
local Tuning = require "core/tuning"
local Playtest = require "core.playtest"
local EditorGameplay = require "core.editor_gameplay"
local EditorBackgrounds = require "core.editor_backgrounds"
local EditorCollision = require "core.editor_collision"
local Backgrounds = require "core.map_backgrounds"
local MapEditor = require "core.map_editor"
local Tilesets = require "core.tilesets"
local WorldMap = require "core.world_map"
local Tilemap = require "core.tilemap"
local CameraBounds = require "core.camera_bounds"
local UIEditor = require "ui/map_editor"
local HUD = require "ui/hud"
local Menus = require "ui/menus"
local UI = require "urhox-libs/UI"
local FISH = require "data/fish"
local ITEMS = require("data/items").ITEMS

require "LuaScripts/Utilities/Sample"
require "urhox-libs.UI.GameHUD"

-- ============================================================================
-- 全局
-- ============================================================================

---@type Scene?
local scene_ = nil
---@type Node?
local cameraNode_ = nil
---@type PhysicsWorld2D?
local physicsWorld_ = nil
---@type NVGContextWrapper?  -- 自建 NanoVG 上下文（世界渲染）
local nvg_ = nil

local gameTime_ = 0.0
local hudTimer_ = 0.0

-- 命中时停（hitstop）
local hitstopTimer_ = 0.0      -- 剩余冻结时间
local hitstopCooldown_ = 0.0   -- 距上次时停的间隔（防止连发持续卡顿）

-- 地图编辑器拖拽状态（1=左键放置, 2=右键擦除, false=未拖拽）
local editorDragging_ = false
-- 编辑器相机平移（中键拖拽的屏幕位移，累积后每帧消费）
local editorPanDX_, editorPanDY_ = 0, 0
local editorPanning_ = false
local editorLastMX_, editorLastMY_ = 0, 0
-- 输入状态
local aimWorld_ = Vector2(0, 0)     -- 瞄准点（世界坐标）
local aimSX_, aimSY_ = 0, 0          -- 瞄准点（屏幕坐标）
local mouseAimActive_ = false
local inputState_ = { moveX = 0, jumpPressed = false, jumpHeld = false, downHeld = false, dashPressed = false, grappleHeld = false }
local prevJump_ = false
local prevDash_ = false
local prevRight_ = false

-- GameHUD（移动端虚拟控制）
---@type VirtualJoystick?
local joystick_ = nil
---@type VirtualButton?
local jumpButton_ = nil
---@type VirtualButton?
local fireButton_ = nil
---@type VirtualButton?
local dashButton_ = nil
---@type VirtualButton?
local grappleButton_ = nil
local gameControlsVisible_ = false

--- VirtualControls 没有统一显隐按钮 API，通过公开 Clear/Create 隔离编辑与游戏输入。
---@param visible boolean
function SetGameControlsVisible(visible)
    if gameControlsVisible_ == visible then return end
    gameControlsVisible_ = visible
    VirtualControls.Clear()
    joystick_, jumpButton_, fireButton_, dashButton_, grappleButton_ = nil, nil, nil, nil, nil
    prevJump_, prevDash_, prevRight_ = false, false, false
    mouseAimActive_ = false
    A.fireRequest = false
    if not visible then return end
    local hud = GameHUD.Create({ enableJump = true })
    joystick_, jumpButton_ = hud.joystick, hud.jumpButton
    fireButton_ = VirtualControls.CreateButton({
        position = Vector2(-30, -140), alignment = { HA_RIGHT, VA_BOTTOM },
        radius = 32, label = "射", opacity = 0.5, activeOpacity = 0.9, alwaysShow = true,
        color = { 100, 180, 255 }, pressedColor = { 160, 210, 255 },
        on_press = function()
            if GS.mode == "playing" and not MapEditor.active and not P.dead then A.requestAttack() end
        end,
    })
    dashButton_ = VirtualControls.CreateButton({
        position = Vector2(-285, -155), alignment = { HA_RIGHT, VA_BOTTOM },
        radius = 46, label = "闪", keyBinding = "LSHIFT",
        opacity = 0.5, activeOpacity = 0.9, alwaysShow = true,
        color = { 170, 230, 140 }, pressedColor = { 210, 250, 180 },
    })
    -- 钩爪（青蛙液态）：右键 / 手机端「爪」按钮，按住发射并保持，松开释放。
    -- mouseBinding 让 PC 端判定为“已有鼠标绑定”而不显示该按钮（PC 直接右键）；
    -- 触屏无鼠标绑定，按钮照常显示，isPressed 供输入分支读取。
    grappleButton_ = VirtualControls.CreateButton({
        position = Vector2(-30, -230), alignment = { HA_RIGHT, VA_BOTTOM },
        radius = 28, label = "爪", mouseBinding = "RMB",
        opacity = 0.5, activeOpacity = 0.9,
        color = { 150, 220, 180 }, pressedColor = { 200, 245, 210 },
    })
end


-- 关卡
local currentLevel_ = nil

--- 同一个收束出口供出生、resize 和平滑跟随使用；编辑器相机完全绕过。
---@param x number
---@param y number
local function ApplyGameCamera(x, y)
    if MapEditor.active then return end
    local nx, ny = CameraBounds.clamp(CameraBounds.fromLevel(currentLevel_), x, y, R.viewW, R.viewH)
    R.setCamera(nx, ny)
    if cameraNode_ then cameraNode_:SetPosition(Vector3(nx, ny, -10)) end
end

-- 延迟弹界面计时（在事件回调闭包中赋值）
---@type number?
local deathDelay_ = nil
---@type number?
local victoryDelay_ = nil
local mouseMoved_ = false
local airborneForLanding_ = false

-- ============================================================================
-- 启动
-- ============================================================================

function Start()
    SampleStart()
    graphics.windowTitle = "涌泉 · YongQuan"

    -- 世界渲染 NanoVG（UI 库有自己的上下文）
    nvg_ = nvgCreate(1)
    assert(nvg_, "[Render] 世界 NanoVG 上下文创建失败")
    R.init(nvg_)
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")
    Art.init(nvg_)
    Tilesets.init(nvg_)
    Backgrounds.init(nvg_)

    -- 加载调参覆盖（必须在 CreateScene 之前：让相机/物理用调好的值初始化）
    Tuning.load()
    -- 相机视野副作用钩子：面板改 VIEW_H 后实时重设 orthoSize 与投影
    Tuning.setHook("VIEW_H", function()
        UpdateScreenSize()
    end)

    -- UI/HUD
    HUD.init()
    HUD.buildGameUI()          -- 提前创建 root（主菜单 overlay 也挂在它上面）
    HUD.setGameHudVisible(false)  -- 主菜单阶段隐藏游戏内 HUD

    CreateScene()

    -- 事件总线绑定
    BindGameEvents()
    BF.bindEvents()
    Audio.init()

    -- 输入
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleContactBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleContactEnd")

    -- 虚拟控制只在游玩时创建；编辑、菜单、暂停时清空，避免独立渲染层遮挡界面。
    GameHUD.Initialize()
    SetGameControlsVisible(false)

    -- 菜单回调（onContinue 确保 GS.save 已加载，避免 nil 崩溃）
    -- 注意：所有正常游戏的入口都要强制退出编辑模式，否则会残留编辑器相机。
    Menus.onContinue = function()
        Playtest.finish()
        if not GS.save and not GS.loadGame() then GS.newGame() end
        LoadLevel("world", GS.save.spring)
    end
    Menus.onNewGame = function()
        Playtest.finish()
        GS.newGame()
        LoadLevel("world", nil)
    end
    Menus.onTestMap = function()
        Playtest.finish()
        if not GS.save then GS.newGame() end
        LoadLevel("testmap", nil)
    end
    Menus.onEditMap = function()
        if not GS.save then GS.newGame() end
        if not currentLevel_ or currentLevel_.id ~= "world" then LoadLevel("world", nil) end
        OpenMapEditor()
    end
    Menus.onRetry = function() RespawnAtSpring() end
    Menus.onQuitToMenu = function()
        Playtest.finish()
        UnloadLevel()
        currentLevel_ = nil
        HUD.setGameHudVisible(false)   -- 回主菜单隐藏游戏内 HUD
        Menus.showMainMenu()
    end
    Menus.onEquipChanged = function() end

    -- 屏幕尺寸
    UpdateScreenSize()
    SubscribeToEvent("ScreenMode", "HandleScreenMode")

    -- 若已有存档则加载（供"继续游戏"使用）；否则保持 nil（主菜单显示"开始游戏"）
    -- 注意：绝不在启动时 newGame()，否则会覆盖玩家已有进度
    if GS.hasSaveFile() then
        GS.loadGame()
    end
    Menus.showMainMenu()

    print("=== 《涌泉》启动完成 ===")
end

function Stop()
    Playtest.finish()
    if MapEditor.active and MapEditor.dirty then MapEditor.saveToSandbox() end
    UIEditor.hide()
    EditorBackgrounds.cancel()
    Backgrounds.shutdown()
    Tilesets.shutdown()
    GameHUD.Shutdown()
    UI.Shutdown()
    Audio.shutdown()
    Art.shutdown()
    if nvg_ then nvgDelete(nvg_) end
end

function UpdateScreenSize()
    local dpr = math.max(1, graphics:GetDPR())
    local w, h = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    local bounds = not MapEditor.active and CameraBounds.fromLevel(currentLevel_) or nil
    R.updateScreen(w, h, MapEditor.active and MapEditor.viewH or Config.VIEW_H, bounds)
    -- 相机使用有效视野，不反写调参请求；暂停/死亡/时停中也立即同步。
    if cameraNode_ then
        local cam = cameraNode_:GetComponent("Camera")
        if cam then cam.orthoSize = R.viewH end
    end
    ApplyGameCamera(R.camX, R.camY)
end

function HandleScreenMode(eventType, eventData)
    UpdateScreenSize()
end

-- ============================================================================
-- 场景
-- ============================================================================

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.gravity = Vector2(0, -Config.GRAVITY)
    physicsWorld_.autoClearForces = true

    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = Config.VIEW_H
    cameraNode_.position = Vector3(0, 0, -10)

    renderer:SetViewport(0, Viewport:new(scene_, cameraNode_:GetComponent("Camera")))

    B.setTerrainCheck(L.isSolid)
    B.setCrateHooks(L.crateAt, function(crate, dmg) L.damageCrate(crate, dmg) end)
    E.setTerrainCheck(L.isSolid)
    P.setTerrainCheck(L.isSolid)   -- 位移撞墙检测
end

-- ============================================================================
-- 单世界管理（功能测试地图仅供开发验收，不参与世界区域切换）
-- ============================================================================
local TEST_MAP = require "levels.testmap"

local function sandboxTestMap(id)
    if not id:match("^__.*__$") then return nil end
    local data = MapEditor.peekSandbox(id)
    if not data then return nil end
    return Tilemap.parse(data)
end

--- 载入关卡
---@param levelId string
---@param springId string|nil 从指定泉眼出生（nil=关卡默认出生点）
---@param spawnOverride table|nil 显式出生点 {x,y}（优先于 springId）
---@param useArrival boolean|nil 用本关「传送点(t)」作为出生点（传送门落点）
function LoadLevel(levelId, springId, spawnOverride, useArrival)
    -- 任何游戏入口先关闭编辑界面，恢复默认投影，避免编辑层和旧缩放残留。
    if MapEditor.active then
        if MapEditor.dirty and not MapEditor.saveToSandbox() then
            UIEditor.notify("保存失败，未离开编辑器，请先导出地图")
            return false
        end
        if not UIEditor.hide() then return false end
        UpdateScreenSize()
    end
    if scene_ then scene_.updateEnabled = true end
    MapEditor.setActive(false)
    if not GS.save then GS.newGame() end   -- 防御：确保存档存在
    local def
    if levelId == "testmap" then
        def = TEST_MAP
    else
        def = sandboxTestMap(levelId)
        if not def then
            local ok, parsed = pcall(function()
                local source = Playtest.active and Playtest.worldSource or WorldMap.source()
                return Tilemap.parse(source)
            end)
            if not ok then
                print("[世界地图] 载入失败，保留原数据：" .. tostring(parsed))
                GS.setMode("menu")
                SetGameControlsVisible(false)
                HUD.setGameHudVisible(false)
                Menus.showMainMenu()
                HUD.toast("世界地图载入失败，原存档未覆盖")
                return
            end
            def = parsed
            levelId = "world"
            GS.migrateWorldSave(GS.save)
            if springId ~= nil then springId = GS.save.spring ~= "" and GS.save.spring or nil end
        end
    end
    UnloadLevel()

    if def.tilemapData and def.tilemapData.tilesets then
        local ok, err = Tilesets.loadDefinitions(def.tilemapData.tilesets)
        if not ok then print("[MapEditor] 地图瓦片配置载入失败: " .. tostring(err)) end
    end
    currentLevel_ = def
    if levelId == "testmap" and GS.save.level == "world" then
        GS.save.returnWorldSpring = GS.save.spring
    end
    GS.save.level = levelId
    if not scene_ then return false end
    L.load(scene_, def)

    -- 出生点：显式落点 > 传送点(t) > 指定泉眼 > 默认
    local spawn = def.spawn
    if spawnOverride then
        spawn = spawnOverride
    elseif useArrival and def.arrival then
        spawn = { x = def.arrival.x, y = def.arrival.y + 0.4 }
    elseif springId and springId ~= "" then
        local sp = H.getById(springId)
        if sp then
            spawn = { x = sp.x, y = sp.y + 0.8 }
        elseif levelId == "world" then
            GS.save.spring = ""
            print("[世界地图] 旧泉眼不存在，使用世界出生点")
        end
    end
    P.create(scene_, spawn.x, spawn.y)
    if Playtest.active and def.initialSpringId and (springId == nil or springId == "") then
        GS.save.spring = def.initialSpringId
    end
    airborneForLanding_ = false
    if def.startForm then P.setForm(def.startForm, true) end
    Art.reset()

    BF.reset()
    -- 必须在所有出生优先级/初始形态处理后收束，第一帧即同步 Camera node。
    local cameraSpawn = P.node.position2D
    R.setCamera(cameraSpawn.x, cameraSpawn.y)
    UpdateScreenSize()

    -- HUD
    if not HUD.root then HUD.buildGameUI() end
    HUD.setGameHudVisible(true)   -- 进关卡显示游戏内 HUD
    HUD.refreshAll()
    HUD.setHint("A/D 移动 · 空格跳跃 · Shift 位移闪避 · 按住左键射击 · E 交互/冰态电鳗技能 · TAB 装备 · ESC 暂停")

    GS.save.visited[levelId] = true
    GS.setMode("playing")
    SetGameControlsVisible(true)
    print(string.format("[Main] 进入关卡: %s (id=%s, 平台数=%d)", def.name, levelId, #L.platformRects))
    HUD.toast("进入：" .. def.name, 2.5)
    return true
end

function UnloadLevel()
    R.shakeTime, R.shakeMag = 0.0, 0.0  -- 跨关/回菜单不继承旧震屏
    A.resetLiquidMelee()
    A.fireRequest = false
    R.clearMeleeSlashes()
    P.swingLock = 0
    if not scene_ then return end
    -- 清掉旧关卡所有节点（保留 Camera）
    local children = scene_:GetChildren()
    for _, node in ipairs(children) do
        if node.name ~= "Camera" then
            node:Remove()
        end
    end
    B.clear()
    E.clear()
    H.clear()
    BF.reset()
    R.particles = {}
    R.bulletImpacts = {}
    R.droppedShells = {}
end

--- 泉眼复活（失败恢复系统 P0-7）
function RespawnAtSpring()
    local springId = GS.save.spring
    local levelId = GS.save.level
    -- 重置关卡（水/机关/敌人恢复）
    if not LoadLevel(levelId, springId) then return end
    GS.save.water = GS.maxWater()
    P.water = GS.save.water
    P.toLiquid()
    HUD.refreshAll()
    GS.setMode("playing")
    HUD.toast("水精灵在泉眼重新凝聚……")
end

-- ============================================================================
-- 事件总线 → 游戏反馈
-- ============================================================================

function BindGameEvents()
    GS.on("waterChanged", function(w, maxW) HUD.refreshWater() end)
    GS.on("shellsChanged", function() HUD.refreshCurrency() end)
    GS.on("fishChanged", function() HUD.refreshFish() end)
    GS.on("maxWaterChanged", function() HUD.refreshWater() end)
    GS.on("slotsChanged", function() HUD.refreshFish() end)
    GS.on("relicsChanged", function() end)

    GS.on("formChanged", function(newForm, old)
        HUD.refreshForm(nil, newForm)
        local c = Config.FORMS[newForm].color
        R.spawnParticles(P.node.position2D.x, P.node.position2D.y, c, 14, 4, 0.5)
        GS.emit("sfx", "transform")
    end)

    GS.on("playerHurt", function(src)
        R.shake(0.5, 0.25)
        R.flash({ 255, 80, 60 }, 0.15)
        GS.emit("sfx", "hurt")
    end)

    GS.on("playerTeleport", function()
        airborneForLanding_ = false
    end)
    GS.on("playerJump", function()
        airborneForLanding_ = true
    end)
    GS.on("playerDoubleJump", function()
        airborneForLanding_ = true
    end)
    GS.on("playerLanded", function()
        -- 气态落地不播落地声：水汽轻飘飘落地，不需要"咚"的一声
        if P.form == "gas" then return end
        GS.emit("sfx", "landing")
    end)

    -- 位移：粒子拖尾 + 破空音效
    GS.on("playerDash", function(dir)
        local pp = P.node.position2D
        local c = Config.FORMS[P.form].color
        R.spawnParticles(pp.x, pp.y, c, 10, 3.5, 0.35)
        GS.emit("sfx", "dash")
    end)

    GS.on("playerDied", function()
        airborneForLanding_ = false
        P.swingLock = 0
        R.clearMeleeSlashes()
        R.flash({ 255, 255, 255 }, 0.5)
        R.shake(1.2, 0.6)
        R.spawnParticles(P.node.position2D.x, P.node.position2D.y, { 120, 200, 255 }, 30, 6, 1.0)
        -- 延迟弹出死亡界面
        deathDelay_ = 1.2
    end)

    GS.on("toast", function(text) HUD.toast(text) end)

    GS.on("itemGet", function(name)
        HUD.toast("获得 " .. name)
        HUD.refreshCurrency()
        HUD.refreshFish()
    end)

    GS.on("itemPickup", function(it)
        if it.kind == "shell" then
            GS.addShells(Config.ECONOMY.pickupShellValue)
            HUD.toast("贝壳 +" .. Config.ECONOMY.pickupShellValue)
            GS.emit("sfx", "pickup")
        elseif it.kind == "fish" then
            GS.addFish(it.fishKey)
            GS.emit("sfx", "pickupBig")
        elseif it.kind == "symbShard" then
            GS.addFragment()
        elseif it.kind == "brokenQuanxin" then
            GS.addPiece()
        elseif it.kind == "relic" then
            GS.addRelic(it.relicKey)
            GS.emit("sfx", "pickupBig")
        end
        GS.saveGame()
        R.spawnParticles(it.x, it.y, { 255, 240, 180 }, 10, 3, 0.5)
    end)

    GS.on("dropShell", function(x, y) R.dropShell(x, y) end)

    GS.on("absorbWater", function(hz)
        R.spawnParticles(hz.x, hz.y, { 130, 210, 255 }, 8, 2.5, 0.4)
        GS.emit("sfx", "absorb")
    end)

    GS.on("springTouch", function(hz)
        HUD.toast("泉眼存档 · 水量回满 · 形态重置")
        R.flash({ 140, 220, 255 }, 0.3)
        R.spawnParticles(hz.x, hz.y, { 160, 230, 255 }, 24, 4, 0.9)
        GS.emit("sfx", "spring")
        H.resetWaters()
    end)

    GS.on("enemyKilled", function(e)
        R.spawnParticles(e.node.position2D.x, e.node.position2D.y, e.def.accent, 18, 5, 0.6)
        GS.emit("sfx", "kill")
        -- 击杀镜头抖动：按敌人强度分级（小怪轻微 / 精英中等 / BOSS 强烈）
        local shake = Config.FEEL.killShake[e.def.tier]
        if shake then R.shake(shake[1], shake[2]) end
        if e.def.tier == "boss" then
            -- BOSS 击败奖励：凝珠(共生核心)、大量贝壳、开启下一区域
            HUD.toast("冰火人被击败了！获得共生核心与大量贝壳")
            GS.save.cores = GS.save.cores + 1
            GS.addShells(Config.ECONOMY.bossRewardShells)
            GS.autoEquip()
            GS.setFlag("bossIceFireDead")
            GS.saveGame()
            R.flash({ 255, 255, 255 }, 0.8)
            BF.reset()
        elseif e.def.tier == "elite" then
            HUD.toast("精英怪 " .. e.def.name .. " 被击败！")
            -- 精英怪掉共生碎片
            GS.addFragment()
            GS.saveGame()
        end
    end)

    -- 固态撞击：接触点冰蓝碎屑 + 镜头轻震 + 命中时停，冲击环由 CombatFX 播放。
    GS.on("ramHit", function(e, x, y)
        R.spawnParticles(x, y, Config.FORMS.solid.color, 18, 5.5, 0.4)
        R.shake(0.65, 0.18)
        triggerHitstop(e)
        GS.emit("sfx", "enemyHit")
    end)

    GS.on("crateBroken", function(c)
        R.spawnParticles(c.x, c.y, { 160, 140, 110 }, 14, 4, 0.5)
        GS.emit("sfx", "crate")
        -- 打击感：短时停 + 镜头轻抖
        hitstopTimer_ = math.max(hitstopTimer_, 0.045)
        R.shake(Config.FEEL.crateShake, 0.12)
    end)

    GS.on("story", function(z)
        if z.mode == "cutscene" then
            Menus.showCutscene(z.text)
        elseif z.mode == "note" then
            HUD.showNote(z.text, 3.5)
        else
            HUD.toast(z.text, 3.0)
        end
    end)

    GS.on("doorOpen", function() GS.emit("sfx", "door") end)
    GS.on("doorClose", function() GS.emit("sfx", "door") end)
    GS.on("plateChanged", function(hz, pressed)
        GS.emit("sfx", "plate")
    end)
    GS.on("fireExtinguished", function(hz)
        HUD.toast("弱火被熄灭了")
        R.spawnParticles(hz.x, hz.y + 0.4, { 200, 200, 210 }, 12, 2.5, 0.6)
    end)

    -- 近战/冲撞命中玩家
    GS.on("enemyMelee", function(e, dmg, range)
        if not P.node or P.dead then return end
        local pp = P.node.position2D
        local ep = e.node.position2D
        local d = math.sqrt((pp.x - ep.x) ^ 2 + (pp.y - ep.y) ^ 2)
        if d <= range then
            P.changeWater(-dmg, Config.DMG.ENEMY)
        end
    end)
    GS.on("enemyDash", function(e, dmg)
        -- 冲撞判定在 enemies.update 的接触检测中处理
    end)

    -- BOSS 死亡后显示胜利
    GS.on("flagSet", function(flag)
        if flag == "bossIceFireDead" then
            victoryDelay_ = 2.0
        end
    end)
end

-- ============================================================================
-- 输入
-- ============================================================================

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if MapEditor.active then
        -- 编辑器的 ESC 留给弹窗；TAB/交互/游戏快捷键不再替换编辑覆盖层。
        if key == KEY_F5 and not UIEditor.isInputFocused() then
            UIEditor.notify(MapEditor.saveToSandbox() and "地图已保存（本次会话）" or "地图保存失败，请导出备份")
        end
        return
    end
    if key == KEY_ESCAPE then
        if GS.mode == "playing" then
            Menus.showPause()
        elseif GS.mode == "paused" then
            Menus.resumeFromPause()
        end
    elseif key == KEY_TAB then
        if GS.mode == "playing" or GS.mode == "paused" then
            if GS.save then Menus.showInventory() end
        end
    elseif key == KEY_E then
        Art.triggerElectric()
        TryInteract()
    elseif key == KEY_F5 then
        -- 调试: 快速存档
        GS.saveGame()
        HUD.toast("已保存")
    elseif key == KEY_F9 then
        Playtest.finish()
        if not GS.save then GS.newGame() end
        LoadLevel(GS.save.level == "testmap" and "world" or "testmap", nil)
    elseif key == KEY_F8 then
        if not GS.save then GS.newGame() end
        if not currentLevel_ or currentLevel_.id ~= "world" then LoadLevel("world", nil) end
        OpenMapEditor()
    end
end

--- 打开同一世界的地图编辑器；隔离测试地图仍可由测试脚本显式指定。
---@param levelId string|nil
---@param sourceKind? string shared=项目共享，draft=个人旧草稿，sharedDraft=共享编辑草稿
function OpenMapEditor(levelId, sourceKind)
    Playtest.finish()
    local ME = MapEditor
    EditorBackgrounds.cancel()
    levelId = levelId or "world"
    if ME.active and ME.dirty and not ME.saveToSandbox() then
        UIEditor.notify("当前地图保存失败，原内容仍在编辑器")
        return
    end
    if levelId:match("^__.*__$") then
        if not ME.loadFromSandbox(levelId) then return end
    else
        local kind = sourceKind or "shared"
        local ok, source, slot = pcall(function()
            if kind == "draft" then return WorldMap.draftSource("world") end
            if kind == "sharedDraft" then return WorldMap.draftSource("world_shared_draft") end
            return WorldMap.sharedSource(), "world_shared_draft"
        end)
        if not ok then
            UIEditor.notify("地图来源载入失败，当前地图与草稿保留：" .. tostring(source))
            return false
        end
        if not ME.loadSource(source) then return false end
        ME.draftSlot, ME.protectDraft = slot, kind == "shared"
        ME.sourceLabel = kind == "shared" and "项目共享地图" or (kind == "sharedDraft" and "我的共享编辑草稿" or "我的旧地图草稿")
        levelId = "world"
    end
    -- 大画布仍从当前角色/出生点开始编辑，不把镜头移到空白地图中心。
    local spawn = ME.metadata.spawn or { x = ME.originX + ME.tile, y = ME.originY - ME.tile }
    if not sourceKind and P.node and currentLevel_ and currentLevel_.id == levelId then
        ME.camX, ME.camY = P.node.position2D.x, P.node.position2D.y
    else
        ME.camX, ME.camY = spawn.x, spawn.y
    end
    editorDragging_, editorPanning_ = false, false
    editorPanDX_, editorPanDY_ = 0, 0
    ME.rectPreviewStart, ME.rectPreviewCur = nil, nil
    SetGameControlsVisible(false)
    if scene_ then scene_.updateEnabled = false end
    hitstopTimer_, hitstopCooldown_ = 0.0, 0.0
    UIEditor.show(function()
        local editedId = ME.currentLevel or "world"
        if scene_ then scene_.updateEnabled = true end
        UpdateScreenSize()
        Playtest.begin(editedId == "world" and ME.captureData() or nil)
        if not LoadLevel(editedId, nil) then Playtest.finish(); return end
        HUD.toast("编辑试玩：从初始出生点开始，进度不写入正式存档", 4)
    end, nil, function(kind) OpenMapEditor("world", kind) end)
    print("[地图编辑器] 编辑同一世界，游戏 HUD 与虚拟控制已隔离")
end

--- 鼠标屏幕坐标 → 网格坐标
local function editorCellAtMouse()
    local ME = MapEditor
    if not UIEditor.isCanvasPoint(aimSX_, aimSY_) then return nil end
    local mwx = R.camX + (aimSX_ - R.screenW / 2) / R.ppu
    local mwy = R.camY - (aimSY_ - R.screenH / 2) / R.ppu
    local col, row = ME.worldToCell(mwx, mwy)
    if not col then return nil end
    return col, row
end

--- 编辑模式下：应用当前工具到鼠标处（画笔/橡皮 = 范围笔刷；矩形 = 拖框填入）
local function editorPaintAtMouse(erase)
    local ME = MapEditor
    if not ME.active or ME.tool == "background" then return end
    local col, row = editorCellAtMouse()
    if not col or not row then return end
    ME.applyBrush(col, row, erase or ME.tool == "erase")
end

--- 矩形工具：从 (c0,r0) 拖到 (c1,r1) 填入当前笔刷
local function editorRectCommit()
    local ME = MapEditor
    if not ME.rectPreviewStart or not ME.rectPreviewCur then return end
    ME.applyRect(ME.rectPreviewStart[1], ME.rectPreviewStart[2], ME.rectPreviewCur[1], ME.rectPreviewCur[2], false)
end

--- 编辑器改动节流保存（每 0.8 秒最多写一次盘）
local editorSaveCd_ = 0.0
local function editorAutoSave(dt)
    if not MapEditor.active or not MapEditor.dirty then return end
    editorSaveCd_ = editorSaveCd_ - dt
    if editorSaveCd_ <= 0 then
        editorSaveCd_ = 0.8
        -- 失败仍保留 dirty，下次重试；不把未保存的内容标成已保存。
        MapEditor.saveToSandbox()
    end
end

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if MapEditor.active then
        local dpr = math.max(1, graphics:GetDPR())
        local mouse = input:GetMousePosition()
        aimSX_, aimSY_ = mouse.x / dpr, mouse.y / dpr
        if not UIEditor.isCanvasPoint(aimSX_, aimSY_) then return end
        if button == MOUSEB_MIDDLE then
            -- 中键拖拽 = 平移视角
            editorPanning_ = true
            editorLastMX_, editorLastMY_ = aimSX_, aimSY_
        elseif button == MOUSEB_LEFT then
            if MapEditor.tool == "background" then
                local _, message = EditorBackgrounds.beginPointer(aimSX_, aimSY_, R)
                UIEditor.selectBackground()
                UIEditor.notify(message)
            elseif MapEditor.tool == "collision" then
                if EditorCollision.isDrawing() then
                    local _, msg = EditorCollision.addDrawVertex(aimSX_, aimSY_, R)
                    UIEditor.notify(msg)
                else
                    -- 只选中格子/多边形，停留在碰撞体页，不切回玩法页。
                    local col, row = editorCellAtMouse()
                    if col and row then EditorGameplay.select(col, row) end
                    local _, msg = EditorCollision.beginPointer(aimSX_, aimSY_, R)
                    UIEditor.notify(msg)
                end
            elseif MapEditor.tool == "select" then
                local col, row = editorCellAtMouse()
                if col and row then
                    EditorGameplay.select(col, row)
                    MapEditor.setLayer("gameplay")
                    UIEditor.selectElement()
                    UIEditor.notify("已选中格（" .. col .. "," .. row .. "）；在玩法元素面板查看属性")
                end
            elseif MapEditor.tool == "rect" then
                -- 矩形工具：记录起点，拖动预览，抬起时填入
                local col, row = editorCellAtMouse()
                if col then MapEditor.rectPreviewStart = { col, row }; MapEditor.rectPreviewCur = { col, row } end
            else
                editorDragging_ = 1
                editorPaintAtMouse(false)
            end
        elseif button == MOUSEB_RIGHT then
            -- 右键始终擦除（范围笔刷）
            editorDragging_ = 2
            editorPaintAtMouse(true)
        end
        return
    end
    if button == MOUSEB_LEFT and GS.mode == "playing" and not P.dead then
        mouseAimActive_ = true
        A.requestAttack()
    end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_MIDDLE then editorPanning_ = false end
    if button == MOUSEB_LEFT then
        if MapEditor.active and EditorBackgrounds.dragging then
            local mouse = input:GetMousePosition()
            local dpr = math.max(1, graphics:GetDPR())
            local _, message = EditorBackgrounds.endPointer(mouse.x / dpr, mouse.y / dpr, R, UIEditor.isCanvasPoint)
            if message ~= "" then UIEditor.notify(message) end
        end
        if MapEditor.active and EditorCollision.dragging then
            EditorCollision.endPointer(aimSX_, aimSY_, R)
        end
        if MapEditor.active and MapEditor.tool == "rect" then
            if UIEditor.isCanvasPoint(aimSX_, aimSY_) then editorRectCommit() end
            MapEditor.rectPreviewStart, MapEditor.rectPreviewCur = nil, nil
        end
        editorDragging_ = false
    end
    if button == MOUSEB_RIGHT then editorDragging_ = false end
    if button == MOUSEB_LEFT then
        mouseAimActive_ = false
    end
end

function HandleMouseMove(eventType, eventData)
    if not MapEditor.active and GS.mode ~= "playing" then return end
    local dpr = math.max(1, graphics:GetDPR())
    local x = eventData["X"]:GetInt() / dpr
    local y = eventData["Y"]:GetInt() / dpr
    aimSX_, aimSY_ = x, y
    R.aimSX, R.aimSY = x, y
    mouseMoved_ = true
    -- 屏幕 → 世界
    aimWorld_ = Vector2(
        R.camX + (x - R.screenW / 2) / R.ppu,
        R.camY - (y - R.screenH / 2) / R.ppu
    )
    -- 整图背景的拖动只更新预览，松开才提交；不触发瓦片笔刷。
    if MapEditor.active and EditorBackgrounds.dragging then EditorBackgrounds.movePointer(x, y, R) end
    if MapEditor.active and EditorCollision.dragging then EditorCollision.movePointer(x, y, R) end
    -- 编辑模式：中键拖拽平移视角
    if editorPanning_ then
        editorPanDX_ = editorPanDX_ + (x - editorLastMX_)
        editorPanDY_ = editorPanDY_ + (y - editorLastMY_)
        editorLastMX_, editorLastMY_ = x, y
    end
    -- 编辑模式：矩形工具更新预览框
    if MapEditor.rectPreviewStart then
        local col, row = editorCellAtMouse()
        if col then MapEditor.rectPreviewCur = { col, row } end
    end
    -- 编辑模式：按住拖拽连续绘制
    if editorDragging_ then
        editorPaintAtMouse(editorDragging_ == 2)
    end
end

--- 滚轮：编辑器模式下缩放视野
---@param eventType string
---@param eventData MouseWheelEventData
function HandleMouseWheel(eventType, eventData)
    if not MapEditor.active or not UIEditor.isCanvasPoint(aimSX_, aimSY_) then return end
    local wheel = eventData["Wheel"]:GetInt()
    MapEditor.zoom(wheel)
    -- 立即应用新缩放（ppu = 屏幕高 / 视野高）
    R.viewH = MapEditor.viewH
    R.ppu = R.screenH / R.viewH
    R.viewW = R.screenW / R.ppu
end

--- 每帧刷新瞄准点（相机移动后屏幕→世界需要重算；鼠标未动过则朝面向）
function UpdateAim()
    if mouseMoved_ then
        aimWorld_ = Vector2(
            R.camX + (aimSX_ - R.screenW / 2) / R.ppu,
            R.camY - (aimSY_ - R.screenH / 2) / R.ppu
        )
    elseif P.node then
        local pp = P.node.position2D
        aimWorld_ = Vector2(pp.x + P.facing * 3, pp.y)
    end
end

--- E 键交互：纸条重读 / 出口
function TryInteract()
    if not P.node or GS.mode ~= "playing" then return end
    local pp = P.node.position2D
    -- 可重复触发的 note 类剧情（离开又进入会重置 fired）
    for _, z in ipairs(L.storyZones) do
        local dx, dy = pp.x - z.x, pp.y - z.y
        if dx * dx + dy * dy <= (z.r + 0.8) * (z.r + 0.8) then
            if z.mode == "note" then
                HUD.showNote(z.text, 4.0)
                return
            end
        end
    end
end

-- ============================================================================
-- 主更新
-- ============================================================================

--- 触发命中时停。精英/BOSS 冻结更久；有最小间隔，避免连发时持续卡顿。
---@param e table|nil 被命中的敌人（用于按 tier 选择时长）
function triggerHitstop(e)
    local HS = Config.HITSTOP
    if not HS.enabled then return end
    if hitstopCooldown_ > 0 then return end
    local dur = HS.duration
    if e and (e.tier == "boss" or e.tier == "elite") then
        dur = HS.bossDuration
    end
    hitstopTimer_ = math.max(hitstopTimer_, dur)
    hitstopCooldown_ = HS.minInterval
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local realDt = eventData["TimeStep"]:GetFloat()
    local dt = realDt

    -- 命中时停（hitstop）：冻结玩法更新（dt=0），但渲染/抖动/闪光照常衰减。
    if hitstopTimer_ > 0 then
        hitstopTimer_ = hitstopTimer_ - realDt
        if hitstopTimer_ > 0 then dt = 0 end
    end
    if hitstopCooldown_ > 0 then hitstopCooldown_ = hitstopCooldown_ - realDt end

    gameTime_ = gameTime_ + realDt
    Art.updateLoading(realDt)
    Tilesets.update(realDt)
    SetGameControlsVisible(GS.mode == "playing" and not MapEditor.active)
    if MapEditor.active then UIEditor.update(realDt) end
    Audio.update(realDt)
    -- 抖动/闪光衰减必须在任何模式判断之前：否则暂停/死亡时抖动会卡住不消失。
    R.updateShake(realDt)

    if GS.mode == "menu" then return end
    -- 时停期间不推进玩法（但上面的渲染相关仍已更新）
    if dt == 0 then return end
    -- 地图编辑模式：冻结玩法，使用自由相机（WASD/方向键平移视角，滚轮缩放）
    if MapEditor.active then
        -- 应用编辑器缩放（滚轮改 viewH → 重算 ppu）
        R.viewH = MapEditor.viewH
        R.ppu = R.screenH / R.viewH
        R.viewW = R.screenW / R.ppu
        local focused = UIEditor.isInputFocused()
        local camIn = {
            left = not focused and (input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)),
            right = not focused and (input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)),
            up = not focused and (input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP)),
            down = not focused and (input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN)),
        }
        MapEditor.updateCamera(dt, camIn, editorPanDX_, editorPanDY_, R.ppu)
        editorPanDX_, editorPanDY_ = 0, 0
        editorAutoSave(dt)   -- 改动节流写入沙箱，防止丢失
        -- 应用到相机
        R.camX = MapEditor.camX
        R.camY = MapEditor.camY
        if cameraNode_ then cameraNode_:SetPosition(Vector3(R.camX, R.camY, -10)) end
        R.setCamera(R.camX, R.camY)
        R.update(dt)
        HUD.update(dt)
        return
    end

    -- 死亡延迟 → 弹死亡界面
    if deathDelay_ then
        deathDelay_ = deathDelay_ - dt
        if deathDelay_ <= 0 then
            deathDelay_ = nil
            Menus.showDeath()
        end
        return
    end
    -- 胜利延迟
    if victoryDelay_ then
        victoryDelay_ = victoryDelay_ - dt
        if victoryDelay_ <= 0 then
            victoryDelay_ = nil
            HUD.toast("冰火人已被击败！可以继续探索世界", 4)
        end
    end

    if GS.mode ~= "playing" then return end

    -- ============ 采集输入 ============
    local moveX = 0
    if joystick_ then
        local jx = joystick_:getMovement()
        if jx < -0.1 then moveX = -1
        elseif jx > 0.1 then moveX = 1 end
    end

    local jumpHeld = input:GetKeyDown(KEY_SPACE) or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP)
    if jumpButton_ and jumpButton_.isPressed then jumpHeld = true end
    local jumpPressed = jumpHeld and not prevJump_
    prevJump_ = jumpHeld
    local downHeld = input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN)

    -- 位移：Shift（左/右）或手机端「闪」按钮（按钮 keyBinding 已绑定 LSHIFT，isPressed 自动联动）
    local dashHeld = input:GetKeyDown(KEY_LSHIFT) or input:GetKeyDown(KEY_RSHIFT)
    if dashButton_ and dashButton_.isPressed then dashHeld = true end
    local dashPressed = dashHeld and not prevDash_
    prevDash_ = dashHeld

    -- 射击：弹幕/固态保留长按；液态剑鱼点按由 MouseButtonDown / on_press 记录。
    -- 不在此把点按转成请求，避免同一点击在事件和轮询中触发两段。
    local fireHeld = input:GetMouseButtonDown(MOUSEB_LEFT)
    if fireButton_ and fireButton_.isPressed then fireHeld = true end

    -- 钩爪（青蛙液态）：右键 / 触屏「爪」按钮按住发射并保持，松开释放；
    -- 左键照常发射基础水弹，两者互不抢占。
    local fx = A.currentEffects()
    local grappleAvail = fx.grapple and P.form == "liquid"
    local grappleHeld = false
    -- 剑鱼固态：格挡为被动能力（受击时自动减伤），不占用按键；射击键仍用于近战。
    P.blocking = (fx.block and P.form == "solid") or false
    if grappleAvail then
        local rightHeld = input:GetMouseButtonDown(MOUSEB_RIGHT)
        if grappleButton_ and grappleButton_.isPressed then rightHeld = true end
        local rightPressed = rightHeld and not prevRight_
        prevRight_ = rightHeld
        grappleHeld = rightHeld
        if rightPressed and P.node then
            local pp0 = P.node.position2D
            local ax, ay = aimWorld_.x - pp0.x, aimWorld_.y - pp0.y
            local len = math.sqrt(ax * ax + ay * ay)
            if len < 0.001 then ax, ay = P.facing, 0 else ax, ay = ax / len, ay / len end
            P.fireGrapple(ax, ay)
        end
    else
        prevRight_ = false
    end
    if GS.mode == "playing" and fireHeld then
        A.fireRequest = true
    end

    inputState_.moveX = moveX
    inputState_.jumpPressed = jumpPressed
    inputState_.jumpHeld = jumpHeld
    inputState_.downHeld = downHeld
    inputState_.dashPressed = dashPressed
    inputState_.grappleHeld = grappleHeld

    -- ============ 玩家 ============
    DetectGround()
    fx = A.currentEffects()      -- 复用输入阶段已取的效果（含钩爪/近战标记）
    P.update(dt, inputState_, fx)

    -- 坠落死亡
    local pp = P.node.position2D
    if pp.y < (currentLevel_ and currentLevel_.deathY or -8) then
        P.changeWater(-99, Config.DMG.TRAP)
    end

    -- ============ 能力/弹幕 ============
    UpdateAim()
    A.update(dt, {
        playerPos = pp,
        aimWorld = aimWorld_,
        spawnBullet = function(o) return B.spawn(o) end,
        enemies = E.list,
        -- 近战命中（剑鱼）：按近战伤害结算
        meleeHit = function(e)
            GS.emit("sfx", "enemyHit")
            triggerHitstop(e)
            E.damage(e, (A.meleeDmg or 6) * Config.BALANCE.playerDmg)
        end,
        -- 近战砍箱（剑鱼）：与弹幕同口径伤害，箱破时复用 crateBroken 反馈
        crates = L.crateNodes,
        meleeCrateHit = function(c)
            L.damageCrate(c, (A.meleeDmg or 6) * Config.BALANCE.playerDmg)
        end,
    })

    B.update(dt, {
        enemies = E.list,
        playerPos = pp,
        hitEnemy = function(e, b)
            GS.emit("sfx", "enemyHit")
            triggerHitstop(e)
            -- 青蛙液态：吞噬小怪（一击必杀）
            if b.devour and e.tier == "small" then
                if b.opts.onDevour then b.opts.onDevour() end
                E.damage(e, 999, b)
                HUD.toast("吞噬！")
                GS.emit("sfx", "devour")
                return
            end
            E.damage(e, b.dmg, b)
        end,
        hitPlayer = function(b)
            if P.dead then return end
            -- 位移期间闪避子弹：弹丸直接穿过玩家，不销毁不结算
            if P.isDodging() then return end
            local d = math.sqrt((pp.x - b.x) ^ 2 + (pp.y - b.y) ^ 2)
            local pr = Config.FORMS[P.form].radius + b.radius
            if d <= pr then
                b.dead = true
                -- 命中特效：自定义贴图（如裂钳蟹石子碎裂）
                if b.hitArtKey then
                    table.insert(R.bulletImpacts, {
                        x = b.x, y = b.y, time = 0, key = b.hitArtKey,
                        duration = Art.duration(b.hitArtKey),
                    })
                    if #R.bulletImpacts > 48 then table.remove(R.bulletImpacts, 1) end
                end
                -- 元素弹一次命中只转换一级，伤害由玩家统一结算一次。
                P.onElementHit(b.element, b.dmg, Config.DMG.ENEMY)
            end
        end,
    })

    -- ============ 敌人 ============
    -- 电鳗液态环绕电场：持续对周围敌人伤害+麻痹
    if A.orbitActive and A.orbitFx and not P.dead then
        A.orbitHitTimers = A.orbitHitTimers or {}
        for _, e in ipairs(E.list) do
            if not e.dead and e.node then
                local ep2 = e.node.position2D
                local od = math.sqrt((ep2.x - pp.x) ^ 2 + (ep2.y - pp.y) ^ 2)
                local k2 = "orb" .. e.uid
                local t2 = A.orbitHitTimers[k2] or 0
                if t2 > 0 then
                    A.orbitHitTimers[k2] = t2 - dt
                elseif od <= Config.ABILITIES.orbitHitRange + e.radius then
                    E.damage(e, A.orbitFx.dmg or 6)
                    e.paralysisTimer = math.max(e.paralysisTimer, A.orbitFx.paralysis or 0.5)
                    A.orbitHitTimers[k2] = A.orbitFx.freq or 0.5
                end
            end
        end
    end
    local hasEel = false
    for _, k in ipairs(GS.save.equipped) do
        if k == "eel" then hasEel = true end
    end
    E.update(dt, fx.lightRange > 0 and pp or nil)

    -- 维护场景光源（鮟鱇鱼液态光圈 → 趋光菌兽寻光）
    GS.lightSources = {}
    if fx.lightRange > 0 and not P.dead then
        table.insert(GS.lightSources, { x = pp.x, y = pp.y })
    end

    -- ============ 机关 ============
    H.update(dt, hasEel)
    L.syncDoors()

    -- 同一世界内只检测剧情/物品；跨区域步行不会卸载或重建场景。
    L.checkStory(pp.x, pp.y)
    L.checkItems(pp.x, pp.y, Config.FORMS[P.form].radius)

    -- BOSS 特效
    BF.update(dt)

    -- ============ 相机（P0-8: 跟随 + 边界限制） ============
    UpdateCamera(dt)

    -- ============ 渲染辅助 ============
    R.update(dt)
    HUD.update(dt)
    HUD.updateNote(dt)

    -- HUD 低频刷新
    hudTimer_ = hudTimer_ - dt
    if hudTimer_ <= 0 then
        hudTimer_ = 0.25
        HUD.refreshWater()
    end
end

function UpdateCamera(dt)
    if MapEditor.active or not P.node or not cameraNode_ then return end
    local pp = P.node.position2D

    -- 保留三形态的平滑跟随及跳跃向上看，再统一 clamp（不把随机 shake 写回）。
    local targetY = pp.y + math.max(0, P.body.linearVelocity.y * 0.15)
    local k = math.min(1, dt * 6)
    local nx = R.camX + (pp.x - R.camX) * k
    local ny = R.camY + (targetY - R.camY) * k
    ApplyGameCamera(nx, ny)
end

---@param eventType string
---@param eventData PostUpdateEventData
function HandlePostUpdate(eventType, eventData)
    -- 物理调试（Z 键）
end

-- ============================================================================
-- 碰撞事件（保留订阅用于扩展；地面检测使用探针方案）
-- ============================================================================

--- 地面探测：脚底 3 点探针（箱子/平台/关闭的门都算地面）
-- 落地音设计（单位米）：空中玩家 (O) 下方三点探针 (• • •) 首次命中地面 (====)，且垂直速度向下时触发。
-- 站立不重复、上升擦边不播；从平台边缘离地、跳跃或关卡生成后的下落都可进入空中状态。
function DetectGround()
    if not P.node or not P.body then return end
    local wasGrounded = P.onGround
    local pp = P.node.position2D
    local r = Config.FORMS[P.form].radius
    local probeY = pp.y - r - 0.12
    local grounded = L.isSolid(pp.x, probeY)
        or L.isSolid(pp.x - r * 0.6, probeY)
        or L.isSolid(pp.x + r * 0.6, probeY)
    P.onGround = grounded
    local velocityY = P.body.linearVelocity.y
    if (wasGrounded and not grounded) or (not grounded and velocityY < 0) then
        -- 跳跃事件和平台边缘离地都会追踪；新关卡出生/传送后自由下落也有效。
        airborneForLanding_ = true
    end
    local descending = velocityY <= 0
    if airborneForLanding_ and not wasGrounded and grounded and descending then
        airborneForLanding_ = false
        GS.emit("playerLanded")
    end
end

function HandleContactBegin(eventType, eventData)
    -- 预留：敌人弹幕/特殊触发
end

function HandleContactEnd(eventType, eventData)
    -- 预留
end

-- ============================================================================
-- 渲染
-- ============================================================================

function HandleRender(eventType, eventData)
    if nvg_ == nil then return end
    local dpr = math.max(1, graphics:GetDPR())
    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr

    nvgBeginFrame(nvg_, w, h, dpr)

    if currentLevel_ then
        R.drawWorld(gameTime_)
        if not MapEditor.active then BF.drawRings(nvg_, R.w2s, R.ppu) end
    else
        -- 主菜单背景动画
        DrawMenuBackground(nvg_, w, h)
    end

    nvgEndFrame(nvg_)
end

function DrawMenuBackground(vg, w, h)
    -- 深水渐变 + 漂浮气泡（主菜单氛围）
    local g = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(8, 12, 24, 255), nvgRGBA(20, 40, 70, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, g)
    nvgFill(vg)

    for i = 1, 14 do
        local bx = (math.sin(gameTime_ * 0.3 + i * 1.7) * 0.5 + 0.5) * w
        local by = h - ((gameTime_ * (14 + i * 3) + i * 130) % (h + 60))
        local br = 4 + (i % 4) * 3
        nvgBeginPath(vg)
        nvgCircle(vg, bx, by, br)
        nvgFillColor(vg, nvgRGBA(140, 210, 255, 40 + (i % 3) * 20))
        nvgFill(vg)
    end
end
