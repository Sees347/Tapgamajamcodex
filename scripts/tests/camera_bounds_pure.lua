-- 纯 Lua 5.4 回归：引擎/资源/存档全部 mock，只加载本次修改的三个脚本。
-- 运行：lua scripts/tests/camera_bounds_pure.lua（不调用 build 或启动 runtime）。
local scripts = assert(debug.getinfo(1, "S").source:match("^@(.*/)tests/"), "请从文件运行")
local C = assert(loadfile(scripts .. "core/camera_bounds.lua"))()
local checks, cases = 0, 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
local function near(a, b, message)
    check(math.abs(a - b) < 1e-9, message .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function case(name, run)
    run()
    cases = cases + 1
    print("PASS " .. name)
end
local function inside(bounds, x, y, w, h)
    check(x - w / 2 >= bounds.minX - 1e-9 and x + w / 2 <= bounds.maxX + 1e-9
        and y - h / 2 >= bounds.minY - 1e-9 and y + h / 2 <= bounds.maxY + 1e-9, "完整可见矩形不能越界")
end
local exact = { minX = -7.25, maxX = 92.75, minY = -29.5, maxY = 20.5 }
local level = {
    id = "world", name = "camera fixture", spawn = { x = -7, y = 20 }, startForm = "liquid",
    bounds = { minX = -1000, maxX = 1000, minY = -1000, maxY = 1000 },
    tilemapData = { originX = -7.25, originY = 20.5, tile = 0.5, cols = 200, rows = 100 },
}
case("精确地图矩形优先于旧 bounds，保留空白画布", function()
    local bounds = assert(C.fromLevel(level))
    for key, value in pairs(exact) do near(bounds[key], value, key) end
    check(bounds ~= level.bounds, "不改地图旧 bounds")
    check(C.fromLevel(nil) == nil and not C.valid(nil), "无关卡无约束")
    check(not C.valid({ minX = 0, maxX = 0, minY = 0, maxY = 1 }), "拒绝退化矩形")
    check(not C.valid({ minX = 0, maxX = math.huge, minY = 0, maxY = 1 }), "拒绝 Infinity")
    check(not C.valid({ minX = 0 / 0, maxX = 1, minY = 0, maxY = 1 }), "拒绝 NaN")
    check(C.fromLevel({ bounds = exact }) == exact, "手工测试场仍使用显式 bounds")
end)
case("横竖屏与单格小地图 fit 不改变请求", function()
    for _, aspect in ipairs({ 0.4, 1, 16 / 9, 4, 12 }) do
        for _, size in ipairs({ { 100, 50 }, { 1, 50 }, { 100, 1 }, { 1, 1 } }) do
            local bounds = { minX = -3, maxX = -3 + size[1], minY = 6, maxY = 6 + size[2] }
            local height = C.viewHeight(bounds, 12, aspect)
            check(height > 0 and height <= 12, "有效视野为正且不大于请求")
            local x, y = C.clamp(bounds, -9999, 9999, height * aspect, height)
            inside(bounds, x, y, height * aspect, height)
        end
    end
    near(C.viewHeight(nil, 12, 2), 12, "无地图不 fit")
    near(C.viewHeight(exact, 0 / 0, 0), 12, "异常请求安全兜底")
    local x, y = C.clamp(exact, 1000, -1000, 200, 100)
    near(x, 42.75, "超宽视野居中")
    near(y, -4.5, "超高视野居中")
end)

local function noop() end
local Config = { VIEW_H = 12, GRAVITY = 20, FEEL = { shakeScale = 1 } }
local GS = { mode = "menu", save = { level = "world", spring = "", visited = {} } }
GS.on, GS.migrateWorldSave = noop, noop
GS.setMode = function(mode) GS.mode = mode end
GS.hasSaveFile = function() return false end
local P = { swingLock = 0, form = "liquid", body = { linearVelocity = { y = 0 } } }
local formShift = 0
P.create = function(_, x, y) P.node = { position2D = { x = x, y = y } } end
P.setForm = function(form)
    P.form = form
    P.node.position2D.x = P.node.position2D.x + formShift
end
local L = { platformRects = {}, crateNodes = {}, itemNodes = {}, isSolid = function() return false end }
L.load = function(_, def) L.def = def end
local springs = { edge = { x = 90, y = -29 } }
local H = { list = {}, clear = noop, getById = function(id) return springs[id] end }
local A = { resetLiquidMelee = noop }
local B = { list = {}, clear = noop, setTerrainCheck = noop, setCrateHooks = noop }
local E = { list = {}, clear = noop, setTerrainCheck = noop }
P.setTerrainCheck = noop
local Art = { init = noop, reset = noop, update = noop, updateLoading = noop }
local BF = { reset = noop, bindEvents = noop }
local ME = { active = false, viewH = 80, dirty = false }
ME.setActive = function(active) ME.active = active end
ME.peekSandbox = function() return level end
ME.zoom = function() ME.viewH = ME.viewH + 10 end
local UIEditor = { hide = function() ME.active = false; return true end, isCanvasPoint = function() return true end }
local HUD = { root = {}, init = noop, buildGameUI = noop, setGameHudVisible = noop, refreshAll = noop, setHint = noop, toast = noop }
local Menus = { showMainMenu = noop }
local hooks = {}
local Tuning = { load = noop, setHook = function(key, hook) hooks[key] = hook end }
local Playtest = { active = false }
local legacy = { id = "testmap", name = "legacy", bounds = exact, spawn = { x = 0, y = 0 }, startForm = "liquid" }
local modules = {
    config = Config, ["core.state"] = GS, ["core.player"] = P, ["core.abilities"] = A,
    ["core.bullets"] = B, ["core.enemies"] = E, ["core.hazards"] = H, ["core.level"] = L,
    ["core.bossfx"] = BF, ["core.art"] = Art, ["core.camera_bounds"] = C,
    ["core.audio"] = { init = noop }, ["core.tuning"] = Tuning, ["core.playtest"] = Playtest,
    ["core.editor_gameplay"] = {}, ["core.editor_backgrounds"] = {},
    ["core.map_editor"] = ME, ["core.world_map"] = { source = function() return level end },
    ["core.tilemap"] = { parse = function(source) return source end },
    ["ui.map_editor"] = UIEditor, ["ui.hud"] = HUD, ["ui.menus"] = Menus,
    ["urhox-libs.UI"] = {}, ["data.fish"] = {}, ["data.items"] = { ITEMS = {} }, ["data.monsters"] = {},
    ["LuaScripts.Utilities.Sample"] = {}, ["urhox-libs.UI.GameHUD"] = {}, ["levels.testmap"] = legacy,
    ["core.melee_fx"] = { clear = noop, bind = noop, draw = noop },
    ["core.combat_fx"] = { clear = noop, bind = noop, draw = noop },
}
local camera, cameraNode, currentScene = {}, {}, {}
local function newNode(name)
    local node = { name = name }
    node.CreateComponent = function(_, kind) if kind == "Camera" then return camera end; return {} end
    node.GetComponent = function() return camera end
    node.SetPosition = function(self, position) self.position = position end
    node.Remove = noop
    return node
end
local graphics = { w = 1600, h = 900, dpr = 1 }
graphics.GetWidth = function() return graphics.w end
graphics.GetHeight = function() return graphics.h end
graphics.GetDPR = function() return graphics.dpr end
local tx, ty, stack, drawnCenter = 0, 0, {}, {}
local editorDraws = 0
modules["core.editor_render"] = { draw = function() editorDraws = editorDraws + 1 end }
local R
modules["core.tile_render"] = {
    drawBackground = function()
        check(tx == 0 and ty == 0, "世界背景不受全屏 transform 震屏")
        drawnCenter = { R.camX, R.camY }
    end, drawTerrain = noop,
}
modules["core.tilesets"] = {
    init = noop, loadDefinitions = function() return true end,
    drawLayer = function(_, _, _, projection)
        near(projection.camX, drawnCenter[1], "图片层裁剪采用实际视觉 X")
        near(projection.camY, drawnCenter[2], "图片层裁剪采用实际视觉 Y")
        check(tx == 0 and ty == 0, "图片层全屏 scissor 不平移")
        local sx, sy = R.w2s(projection.camX, projection.camY)
        near(sx, R.screenW / 2, "w2s 与图片层视觉投影 X 一致")
        near(sy, R.screenH / 2, "w2s 与图片层视觉投影 Y 一致")
    end,
}
modules["core.map_backgrounds"] = { init = noop, draw = noop }
local env = setmetatable({
    require = function(name) return assert(modules[name:gsub("/", ".")], "未 mock 的模块: " .. name) end,
    graphics = graphics, SampleStart = noop, SubscribeToEvent = noop,
    GameHUD = { Initialize = noop, Create = function() return {} end },
    VirtualControls = { Clear = noop, CreateButton = function() return {} end },
    nvgCreate = function() return {} end, nvgCreateFont = noop,
    Vector2 = function(x, y) return { x = x, y = y } end,
    Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    Viewport = { new = function() return {} end }, renderer = { SetViewport = noop },
    Scene = function()
        currentScene = { CreateComponent = function() return {} end }
        currentScene.CreateChild = function(_, name) cameraNode = newNode(name); return cameraNode end
        currentScene.GetChildren = function() return { cameraNode } end
        return currentScene
    end,
    nvgSave = function() stack[#stack + 1] = { tx, ty } end,
    nvgTranslate = function(_, x, y) tx, ty = tx + x, ty + y end,
    nvgRestore = function() local v = assert(table.remove(stack), "变换栈未配对"); tx, ty = v[1], v[2] end,
}, { __index = _G })
R = assert(loadfile(scripts .. "core/render.lua", "t", env))()
modules["core.render"] = R
assert(loadfile(scripts .. "main.lua", "t", env))()
-- Start 也只运行 mock，验证实际 VIEW_H hook，而非源码字符串断言。
env.Start()
check(type(hooks.VIEW_H) == "function", "注册 VIEW_H 即时回调")

local function synced()
    near(camera.orthoSize, R.viewH, "引擎与 NanoVG 视野一致")
    near(cameraNode.position.x, R.camX, "Camera node X 立即同步")
    near(cameraNode.position.y, R.camY, "Camera node Y 立即同步")
    near(cameraNode.position.z, -10, "Camera 深度保留")
    inside(assert(C.fromLevel(L.def)), R.camX, R.camY, R.viewW, R.viewH)
    near(Config.VIEW_H, 12, "不修改 Config.VIEW_H")
end
case("LoadLevel 最终出生立即 clamp（默认/泉眼/传送/显式）", function()
    for _, form in ipairs({ "liquid", "solid", "gas" }) do
        level.startForm = form
        formShift = 1.25
        check(env.LoadLevel("world"), "默认载入成功")
        check(P.form == form, "三形态初始设置保留")
        synced()
        formShift = 0
    end
    GS.save.spring = "edge" -- 世界载入会从迁移后的存档读取当前泉眼。
    check(env.LoadLevel("world", "edge"), "泉眼载入")
    near(P.node.position2D.y, -28.2, "泉眼出生偏移保留")
    synced()
    level.arrival = { x = 90, y = 20 }
    check(env.LoadLevel("world", "edge", nil, true), "传送点载入")
    near(P.node.position2D.y, 20.4, "传送点优先于泉眼")
    synced()
    formShift = 1.25
    check(env.LoadLevel("world", "edge", { x = 20, y = 0 }, true), "显式出生载入")
    near(R.camX, 21.25, "取形态处理后的实际位置而非原 spawn")
    near(R.camY, 0, "显式优先于传送点")
    synced()
    formShift = 0
end)
case("resize/DPR/VIEW_H 即时 fit-clamp，暂停也同步", function()
    GS.mode = "paused"
    for _, screen in ipairs({ { 900, 1600, 1 }, { 6400, 900, 2 }, { 1600, 900, 1 } }) do
        graphics.w, graphics.h, graphics.dpr = table.unpack(screen)
        R.setCamera(999, -999)
        env.HandleScreenMode()
        synced()
        near(R.screenW, screen[1] / screen[3], "系统逻辑宽")
    end
    Config.VIEW_H = 48
    hooks.VIEW_H()
    near(camera.orthoSize, R.viewH, "VIEW_H hook 同步有效投影")
    inside(exact, R.camX, R.camY, R.viewW, R.viewH)
    near(Config.VIEW_H, 48, "fit 不改调参请求")
    Config.VIEW_H = 12
    hooks.VIEW_H()
    graphics.w, graphics.h = 0, 0
    env.UpdateScreenSize()
    synced()
    graphics.w, graphics.h = 1600, 900
end)
case("小地图 fit 后恢复大地图/手工测试场请求视野", function()
    level.tilemapData.cols, level.tilemapData.rows = 2, 2
    check(env.LoadLevel("world"), "小地图载入")
    near(R.viewW, 1, "小地图完整宽")
    synced()
    level.tilemapData.cols, level.tilemapData.rows = 200, 100
    check(env.LoadLevel("world"), "大地图恢复")
    near(R.viewH, 12, "恢复请求高度而非继承小地图 fit")
    check(env.LoadLevel("testmap"), "手工场载入")
    synced()
    check(env.LoadLevel("world"), "回世界")
end)
case("三形态平滑跟随后 clamp 与向上看不变", function()
    for _, form in ipairs({ "liquid", "solid", "gas" }) do
        P.form = form
        P.node.position2D = { x = 40, y = 0 }
        P.body.linearVelocity.y = 10
        R.setCamera(20, -4)
        env.UpdateCamera(0.1)
        near(R.camX, 32, "平滑系数 6 保留")
        near(R.camY, -0.7, "跳跃向上看保留")
        synced()
        P.node.position2D = { x = 9999, y = 9999 }
        env.UpdateCamera(1)
        synced()
    end
end)
case("震屏每次真实视觉中心在矩形内且不累计逻辑 cam", function()
    P.node = nil -- 不测试玩家绘制，不加载任何资源。
    local random = math.random
    for _, corner in ipairs({ { -999, -999 }, { -999, 999 }, { 999, -999 }, { 999, 999 }, { 40, 0 } }) do
        R.setCamera(C.clamp(exact, corner[1], corner[2], R.viewW, R.viewH))
        local x, y = R.camX, R.camY
        local nodeX, nodeY = cameraNode.position.x, cameraNode.position.y
        R.shake(100, 1)
        for i = 1, 40 do
            local sample = 0
            math.random = function()
                sample = sample + 1
                return ((i + sample) % 4 < 2) and 0 or 1
            end
            R.drawWorld(i)
            inside(exact, drawnCenter[1], drawnCenter[2], R.viewW, R.viewH)
            if corner[1] == 40 then
                check(drawnCenter[1] ~= x or drawnCenter[2] ~= y, "地图内部保留实际震屏效果")
            end
            near(R.camX, x, "震屏不累计 X")
            near(R.camY, y, "震屏不累计 Y")
            near(cameraNode.position.x, nodeX, "视觉震屏不写 Camera node X")
            near(cameraNode.position.y, nodeY, "视觉震屏不写 Camera node Y")
            check(#stack == 0 and tx == 0 and ty == 0, "每次绘制变换严格恢复")
        end
    end
    math.random = random
    for _, invalid in ipairs({ -1, 0, math.huge, 0 / 0 }) do
        local x, y = C.shakeCenter(exact, R.camX, R.camY, R.viewW, R.viewH, 1, invalid)
        near(x, R.camX, "无效 shake scale X")
        near(y, R.camY, "无效 shake scale Y")
    end
    R.updateShake(2)
    check(R.shakeTime == 0 and R.shakeMag == 0, "暂停/死亡更新可清震屏")
    R.shake(1, 1)
    check(env.LoadLevel("world"), "带旧震屏切关")
    check(R.shakeTime == 0 and R.shakeMag == 0, "跨关清旧 shake")
end)
case("fit 单格地图震幅为零", function()
    local b = { minX = 0, maxX = 1, minY = 0, maxY = 1 }
    for i = 1, 20 do
        local x, y = C.shakeCenter(b, 0.5, 0.5, 1, 1, 20, 1)
        near(x, 0.5, "fit 宽轴不震")
        near(y, 0.5, "fit 高轴不震")
    end
end)
case("编辑器任意越界、缩放、resize、渲染均不受游戏边界限制", function()
    ME.active, ME.viewH = true, 80
    R.setCamera(-5000, 5000)
    local oldPosition = cameraNode.position
    env.UpdateScreenSize()
    near(R.viewH, 80, "编辑器视野不 fit")
    near(R.camX, -5000, "编辑器不 clamp X")
    near(R.camY, 5000, "编辑器不 clamp Y")
    check(cameraNode.position == oldPosition, "resize 不调用游戏 Camera 收束")
    env.UpdateCamera(1)
    near(R.camX, -5000, "游戏 UpdateCamera 编辑器中不跟随")
    local wheelEvent = { Wheel = { GetInt = function() return -1 end } } --[[@as MouseWheelEventData]]
    env.HandleMouseWheel(nil, wheelEvent)
    near(R.viewH, 90, "编辑缩放自由，不受小地图限制")
    R.shake(50, 1)
    R.drawWorld(1)
    check(editorDraws == 1 and tx == 0 and ty == 0 and #stack == 0, "编辑器绕过游戏震屏与变换")
    near(Config.VIEW_H, 12, "编辑缩放不影响游戏请求")
    ME.active = false
    check(env.LoadLevel("world"), "从编辑器回游戏")
    synced()
    env.UnloadLevel()
    check(R.shakeTime == 0 and R.shakeMag == 0, "UnloadLevel 独立清震屏")
end)
print(string.format("Camera pure tests: %d cases, %d assertions passed", cases, checks))
return { cases = cases, assertions = checks }
