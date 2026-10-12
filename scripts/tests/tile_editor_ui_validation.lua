-- 真实 UI 验收：隔离测试地图，检查编辑器布局、输入阻挡及退出试玩恢复。
---@class TileEditorUITestHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "此测试只能由官方验证运行器加载") --[[@as TileEditorUITestHarness]]
local UI = require "urhox-libs/UI"
local Editor = require "ui.map_editor"
local ME = require "core.map_editor"
local HUD = require "ui.hud"
local GS = require "core.state"
local Controls = require "urhox-libs.UI.VirtualControls"
local testId = "__tile_editor_ui_validation__"
local originalSaveGame = GS.saveGame
local originalClear = Controls.Clear
local originalJoystick = Controls.CreateJoystick
local originalButton = Controls.CreateButton
local joystickCount, buttonCount = 0, 0

local function findButton(widget, text)
    if widget._className == "Button" and widget.props.text == text then return widget end
    for _, child in ipairs(widget:GetChildren()) do
        local found = findButton(child, text)
        if found then return found end
    end
    return nil
end

local function findClass(widget, className)
    if widget._className == className then return widget end
    for _, child in ipairs(widget:GetChildren()) do
        local found = findClass(child, className)
        if found then return found end
    end
    return nil
end

local function click(text)
    local button = HUD.root and findButton(HUD.root, text)
    V.assert(button ~= nil, "存在按钮：" .. text)
    if button then button.props.onClick(button) end
    UI.Layout()
end

V.atFrame(10, function()
    Controls.Clear = function()
        joystickCount, buttonCount = 0, 0
        originalClear()
    end
    Controls.CreateJoystick = function(config)
        joystickCount = joystickCount + 1
        return originalJoystick(config)
    end
    Controls.CreateButton = function(config)
        buttonCount = buttonCount + 1
        return originalButton(config)
    end
    GS.saveGame = function() return true end
    GS.save = GS.defaultSave()
    local load = assert(rawget(_G, "LoadLevel"), "游戏入口提供 LoadLevel")
    local open = assert(rawget(_G, "OpenMapEditor"), "游戏入口提供 OpenMapEditor")
    load("world")
    open("world")
    -- 通用 UI 回归固定使用4列基础图集；上传素材的默认预选由专门测试验收。
    local palette = findClass(HUD.root, "EditorTilePalette")
    if palette then palette.dropdown_:SetValue("builtin") end
    ME.currentLevel = testId
    ME.loadSource({ id = testId, cols = 32, rows = 16, tile = 1, originX = 0, originY = 16,
        map = string.rep("                                \n", 15) .. "################################", spawn = { x = 3, y = 2 } })
    ME.selectTiles("builtin", 1, 1, 1, 4, "ground")
    ME.setLayer("ground")
    ME.applyRect(3, 13, 10, 13, false)
    ME.setLayer("foreground")
    ME.selectTiles("builtin", 5, 1, 1, 4, "decoration")
    ME.applyBrush(7, 12, false)
    ME.setLayer("ground")
    ME.selectTiles("builtin", 1, 1, 1, 4, "ground")
    ME.centerCamera()
    UI.Layout()
end)

V.atFrame(35, function()
    V.assert(ME.active, "编辑器已激活")
    V.assert(HUD.gameHudLayer and not HUD.gameHudLayer:IsVisible(), "游戏HUD在编辑时隐藏")
    V.assert(joystickCount == 0 and buttonCount == 0, "编辑器不残留虚拟移动跳跃射击按钮")
    local canvas = Editor.getCanvasRect()
    V.assert(canvas.w > 80 and canvas.h > 80, "中央画布保留有效空间")
    V.assert(not Editor.isCanvasPoint(0, 0), "顶部工具区拒绝落笔")
    if graphics:GetWidth() / UI.GetScale() < 960 then click("图层 / 瓦片") end
end)

V.atFrame(80, function()
    local canvas = Editor.getCanvasRect()
    local x, y = canvas.x + canvas.w * 0.25, canvas.y + canvas.h * 0.5
    V.assert(Editor.isCanvasPoint(x, y), "画布内可落笔且不受游戏UI阻挡")
    local palette = HUD.root:FindById("editorCanvas")
    V.assert(palette ~= nil, "布局保留稳定画布标识")
    local grid = findClass(HUD.root, "EditorTileGrid")
    V.assert(grid ~= nil, "图集包含可交互瓦片网格")
    if grid then
        local l = grid:GetAbsoluteLayoutForHitTest()
        local col, row = grid:CellAt(l.x + grid.cellSize_ * 1.5, l.y + grid.cellSize_ * 0.5)
        V.assert(col == 2 and row == 1, "调色板命中使用实际布局坐标")
        grid.startCol_, grid.startRow_, grid.endCol_, grid.endRow_ = 1, 1, 2, 2
        grid:ApplySelection()
        V.assert(ME.tileSelection.width == 2 and ME.tileSelection.height == 2 and ME.tileSelection.columns == 4, "调色板多格选择保持原图列行")
    end
end)

V.atFrame(105, function()
    local palette = findClass(HUD.root, "EditorTilePalette")
    ME.setLayer("collision")
    ME.tool = "erase"
    ME.selectTiles("", 1, 1, 1, 1, "ground")
    if palette then palette:Refresh(true) end
    V.assert(ME.selectedLayer == "collision" and ME.tool == "erase", "图集刷新不会偷偷切走橡皮的碰撞层")
    ME.setLayer("ground")
    ME.brushSize = 1
    -- 在实际编辑画布通过主输入事件擦两格，模式paused也应允许编辑拖擦。
    local R = require "core.render"
    local down = assert(rawget(_G, "HandleMouseDown"))
    local move = assert(rawget(_G, "HandleMouseMove"))
    local up = assert(rawget(_G, "HandleMouseUp"))
    local wx, wy = ME.cellToWorld(5, 13)
    local sx, sy = R.w2s(wx, wy)
    V.assert(Editor.isCanvasPoint(sx, sy), "旧地形擦除验收点位于真实画布内")
    ME.grid[13][5], ME.grid[13][6] = "#", "="
    GS.setMode("paused")
    local originalMousePosition = input.GetMousePosition
    input.GetMousePosition = function() return IntVector2(math.floor(sx * graphics:GetDPR()), math.floor(sy * graphics:GetDPR())) end
    down("MouseButtonDown", { Button = { GetInt = function() return MOUSEB_LEFT end } })
    input.GetMousePosition = originalMousePosition
    local nextWX, nextWY = ME.cellToWorld(6, 13)
    local nextX, nextY = R.w2s(nextWX, nextWY)
    move("MouseMove", { X = { GetInt = function() return math.floor(nextX * graphics:GetDPR()) end }, Y = { GetInt = function() return math.floor(nextY * graphics:GetDPR()) end } })
    up("MouseButtonUp", { Button = { GetInt = function() return MOUSEB_LEFT end } })
    V.assert(ME.grid[13][5] == " " and ME.getVisualCell("ground", 5, 13) == nil, "橡皮左键一次擦掉图片和旧地形")
    V.assert(ME.grid[13][6] == " " and ME.getVisualCell("ground", 6, 13) == nil, "非playing编辑状态仍可连续拖擦")
    GS.setMode("playing")
    ME.tool = "brush"
end)

V.atFrame(125, function()
    click("导入图片")
    V.assert(UI.GetTopOverlay() ~= nil and Editor.isInputFocused(), "导入弹窗阻挡地图输入")
    local canvas = Editor.getCanvasRect()
    V.assert(not Editor.isCanvasPoint(canvas.x + canvas.w / 2, canvas.y + canvas.h / 2), "弹窗打开后不误涂地图")
end)

V.atFrame(145, function()
    local modal = UI.GetTopOverlay()
    if modal then modal:Close() end
    click("地图设置")
    V.assert(UI.GetTopOverlay() ~= nil, "地图尺寸设置独立弹窗可打开")
end)

V.atFrame(165, function()
    local modal = UI.GetTopOverlay()
    if modal then modal:Close() end
    click("退出并测试")
    V.assert(not ME.active and GS.mode == "playing", "退出后进入当前编辑地图试玩")
    V.assert(HUD.gameHudLayer:IsVisible(), "试玩恢复游戏HUD")
    V.assert(joystickCount > 0 and buttonCount > 0, "试玩恢复虚拟控制")
    local level = require "core.level"
    V.assert(level.def.tilemapData.visualLayers.ground.cells["3:13"] ~= nil, "试玩读取已保存地面瓦片")
    V.assert(level.def.tilemapData.visualLayers.foreground.cells["7:12"].collider == "decoration", "试玩保持装饰无碰撞类型")
end)

V.atFrame(190, function()
    require("core.playtest").finish()
    ME.clearSandbox(testId)
    GS.saveGame = originalSaveGame
    Controls.Clear, Controls.CreateJoystick, Controls.CreateButton = originalClear, originalJoystick, originalButton
end)
