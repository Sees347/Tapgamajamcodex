-- 编辑器真实操作验收：mock地图沙箱读写，绝不覆盖用户world或正式玩家存档。
---@class EditorGameplayTestHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V")) --[[@as EditorGameplayTestHarness]]
local UI = require "urhox-libs/UI"
local ME = require "core.map_editor"
local EG = require "core.editor_gameplay"
local Export = require "ui.map_export"
local Editor = require "ui.map_editor"
local GS = require "core.state"
local PT = require "core.playtest"
local L = require "core.level"
local P = require "core.player"
local HUD = require "ui.hud"
local Menus = require "ui.menus"
local originalPeek, originalMapWrite, originalPlayerWrite = ME.peekSandbox, ME.saveToSandbox, GS.saveGame
local originalClipboardWrite, originalClipboardRead = ui.SetClipboardText, ui.GetClipboardText
local clipboard, mapWrites, playerWrites = "", 0, 0
local savedMap = {}
local formal = GS.defaultSave()
formal.shells, formal.spring = 73, "old_formal_spring"
formal.flags.picked_editor_validation_1 = true
local source = {
    id = "world", level = "world", progressId = "editor_validation", seamless = true,
    cols = 14, rows = 7, tile = 1, originX = 0, originY = 7,
    map = "              \n              \n              \n  S  P  D S   \n $ O   A      \n              \n##############",
    spawn = { x = 1.5, y = 2 }, story = {}, wires = {},
}
local expectedX, expectedY = 0, 0

local function find(widget, predicate)
    if predicate(widget) then return widget end
    for _, child in ipairs(widget:GetChildren()) do local result = find(child, predicate); if result then return result end end
    if widget.GetHitTestChildren then
        for _, child in ipairs(widget:GetHitTestChildren() or {}) do local result = find(child, predicate); if result then return result end end
    end
    return nil
end
local function click(text, tree)
    local button = find(tree or UI.GetTopOverlay() or HUD.root, function(w) return w._className == "Button" and w.props.text == text end)
    V.assert(button ~= nil, "可操作按钮：" .. text)
    if button then button.props.onClick(button) end
    UI.Layout()
end
local function contains(text, tree)
    return find(tree or UI.GetTopOverlay() or HUD.root, function(w) return type(w.props.text) == "string" and w.props.text:find(text, 1, true) ~= nil end) ~= nil
end

V.atFrame(10, function()
    GS.save, GS.saveGame = formal, function() playerWrites = playerWrites + 1 end
    savedMap = source
    ME.peekSandbox = function(id) return id == "world" and savedMap or nil end
    ME.saveToSandbox = function() savedMap = ME.captureData(); ME.dirty = false; mapWrites = mapWrites + 1; return true end
    ui.SetClipboardText = function(_, text) clipboard = text end
    ui.GetClipboardText = function() return clipboard end
    assert(rawget(_G, "LoadLevel"))("world")
    assert(rawget(_G, "OpenMapEditor"))()
    ME.setLayer("ground"); ME.selectTiles("builtin", 1, 1, 1, 4, "ground"); ME.applyBrush(2, 7, false)
    ME.setLayer("foreground"); ME.selectTiles("builtin", 5, 1, 1, 4, "decoration"); ME.applyBrush(3, 6, false)
    ME.collisionCells["2:7"] = false
    ME.setLayer("gameplay")
    Editor.selectElement()
end)

V.atFrame(35, function()
    local choice = HUD.root:FindById("initialSpawnChoice") --[[@as Dropdown?]]
    V.assert(choice ~= nil and #EG.list("S") == 2, "玩法面板可从两个泉眼明确选择初始出生点")
    if choice then choice.props.onChange(choice, "11:4", { value = "11:4", label = "泉眼" }) end
    expectedX, expectedY = ME.cellToWorld(11, 4)
    expectedY = expectedY + 0.8
    V.assert(EG.initialKey() == "11:4", "选择不是第一个泉眼的初始点")
    EG.select(9, 4); Editor.selectElement()
    V.assert(EG.connect("6:4", "9:4"), "固态压板可显式连接门")
    V.assert(EG.connect("4:5", "8:5"), "电力接口可显式连接报警器")
    V.assert(not EG.connect("11:4", "9:4"), "不能把泉眼错连为电源")
    V.assert(not EG.connect("6:4", "9:4"), "重复连线被拒绝")
    ME.tool = "select"
    V.assert(not ME.applyBrush(1, 1, false), "选取模式不修改地图")
    local palette = find(HUD.root, function(w) return w._className == "EditorTilePalette" end)
    if palette then
        palette.gameplayButtons_.P.props.onClick()
        V.assert(ME.tool == "brush", "选择玩法素材后从选取切回画笔")
        ME.tool = "select"
        palette.grid_.startCol_, palette.grid_.startRow_, palette.grid_.endCol_, palette.grid_.endRow_ = 1, 1, 1, 1
        palette.grid_:ApplySelection()
        V.assert(ME.tool == "brush", "选择图片瓦片后从选取切回画笔")
    end
    click("导出", HUD.root)
    V.assert(UI.GetTopOverlay() ~= nil and UI.GetTopOverlay().props.title == "完整地图导出 / 取走文本", "导出点击后打开可见窗口，不依赖控制台")
    V.assert(Editor.isInputFocused(), "导出窗口阻挡地图误绘")
    click("复制整份")
    clipboard = ui:GetClipboardText()
    print("[导出验收] 当前复制字节", #clipboard, "前缀", clipboard:sub(1, 160))
    local data = cjson.decode(clipboard)
    V.assert(data.cols == 14 and data.rows == 7 and data.map == ME.exportString(), "复制JSON包含完整已编辑地图")
    V.assert(data.visualLayers.ground.cells["2:7"].tileId == 1 and data.visualLayers.foreground.cells["3:6"].tileId == 5, "复制保留不同视觉层")
    V.assert(data.collisionCells["2:7"] == false and data.metadata.initialSpawnCell.col == 11 and #data.metadata.wires == 2, "复制保留碰撞false、选定出生点及机关连线")
    V.assert(#data.tilesets == #require("core.tilesets").exportDefinitions(), "复制包含完整瓦片集配置")
end)

V.atFrame(80, function()
    click("完整Lua SRC")
    click("复制整份")
    clipboard = ui:GetClipboardText()
    print("[导出验收] SRC复制字节", #clipboard, "前缀", clipboard:sub(1, 160))
    V.assert(clipboard:find("initialSpawnCell", 1, true) and clipboard:find("elementProperties", 1, true)
        and clipboard:find("collisionCells", 1, true) and clipboard:find("return SRC", 1, true), "Lua SRC导出也保留完整玩法配置与视觉碰撞")
    click("关闭")
    V.assert(UI.GetTopOverlay() == nil, "关闭导出释放弹窗并恢复编辑")
    local text = string.rep("涌泉地图\n", 180)
    local pages, valid = Export.pages(text), true
    for _, page in ipairs(pages) do if not utf8.len(page) or #page > 512 then valid = false end end
    V.assert(valid and table.concat(pages) == text, "中文分页保持完整UTF-8且无截断")
    local snapshot = ME.captureData()
    local decoded, err = Export.decode(cjson.encode(snapshot))
    V.assert(decoded ~= nil and err == nil, "完整JSON可验证重新导入")
    local oldGrid = ME.grid
    local bad = ME.captureData(); bad.rows = 10000
    V.assert(Export.decode(cjson.encode(bad)) == nil and ME.grid == oldGrid, "坏JSON验证不覆盖活动地图")
    local malformed = ME.captureData(); malformed.tilesets[1].path = "image/地图/tiles/../bad.png"
    V.assert(not Export.apply(malformed) and ME.grid == oldGrid, "图集安装失败回滚整个地图")
    V.assert(Export.apply(snapshot) and EG.initialKey() == "11:4" and #ME.metadata.wires == 2, "JSON应用后出生和连接保持有效")
    ME.setLayer("gameplay"); ME.tool = "erase"
    ME.applyBrush(6, 4, true)
    V.assert(#ME.metadata.wires == 1, "擦除压板清理其连接，不残留失效输入")
    ME.loadSource(snapshot)
    Editor.selectElement()
end)

V.atFrame(110, function()
    ME.setLayer("gameplay"); ME.tool = "erase"; ME.applyBrush(11, 4, true)
    local writesBefore = mapWrites
    click("退出并测试", HUD.root)
    V.assert(ME.active and not PT.active and contains("初始出生"), "删除选中初始点后阻止过期坐标测试并提示重选")
    V.assert(mapWrites == writesBefore, "出生选择失效时不保存、不退出")
    local ok = EG.setInitial("3:4")
    V.assert(ok, "可重选另一个仍存在的泉眼")
    expectedX, expectedY = ME.cellToWorld(3, 4); expectedY = expectedY + 0.8
    click("退出并测试", HUD.root)
    V.assert(not ME.active and PT.active and GS.mode == "playing", "实际退出按钮进入独立试玩")
    V.assert(math.abs(P.node.position2D.x - expectedX) < 0.001 and math.abs(P.node.position2D.y - expectedY) < 0.001, "试玩实际玩家从所选泉眼出生，而不是旧正式绑定点")
    V.assert(GS.save.spring == "editor_validation_2_3", "试玩初始泉眼同时成为复活绑定点")
    V.assert(not L.itemNodes[1].taken, "旧正式拾取flag不隐藏新编辑奖励")
    V.assert(GS.save ~= formal and formal.spring == "old_formal_spring" and formal.flags.picked_editor_validation_1, "试玩不修改正式存档对象或旧标记")
    GS.save.shells = 999; GS.saveGame()
    V.assert(formal.shells == 73 and playerWrites == 0, "试玩奖励和存档调用不写正式进度")
end)

V.atFrame(165, function()
    Menus.onQuitToMenu()
    V.assert(not PT.active and GS.save == formal and GS.saveGame ~= originalPlayerWrite, "退出试玩恢复原存档对象和测试前写入函数")
    V.assert(formal.shells == 73 and formal.spring == "old_formal_spring", "试玩退出后正式货币和绑定点完全保留")
end)

V.atFrame(190, function()
    PT.finish(); ME.dirty = false; Editor.hide()
    ME.peekSandbox, ME.saveToSandbox, GS.saveGame = originalPeek, originalMapWrite, originalPlayerWrite
    ui.SetClipboardText, ui.GetClipboardText = originalClipboardWrite, originalClipboardRead
end)
