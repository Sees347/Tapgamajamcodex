-- 分层地图数据回归：只改内存与指定测试沙箱，不覆盖玩家地图和进度。
---@class TileEditorTestHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "此测试只能由官方验证运行器加载") --[[@as TileEditorTestHarness]]
local ME = require "core.map_editor"
local TM = require "core.tilemap"
local TS = require "core.tilesets"
local savedState = {}
local fields = { "active", "grid", "cols", "rows", "tile", "originX", "originY", "brush", "tool", "brushSize", "rectPreviewStart", "rectPreviewCur", "currentLevel", "metadata", "visualLayers", "collisionCells", "layerStates", "selectedLayer", "tileSelection", "syncCollision", "dirty", "saveStatus" }

V.atFrame(10, function()
    for _, key in ipairs(fields) do savedState[key] = ME[key] end
    ME.loadSource({ id = "__tile_editor_regression__", map = "     \n     \n     \n     ", cols = 5, rows = 4, tile = 1, originX = 0, originY = 4,
        spawn = { x = 1, y = 3 }, story = { { id = "note", x = 1, y = 2, r = 1, text = "保留剧情" } }, wires = { { from = "a", to = "b" } } })
    ME.tool, ME.brushSize, ME.syncCollision = "brush", 1, true
    V.assert(ME.cols == 5 and ME.rows == 4 and #ME.grid == 4, "空白地图保持显式尺寸与首尾行")
    ME.setLayer("ground")
    ME.selectTiles("builtin", 1, 1, 1, 4, "ground")
    V.assert(ME.applyBrush(2, 3, false), "地面图片笔刷产生变化")
    local src = ME.captureData()
    local def = TM.parse(src)
    V.assert(#def.platforms == 1 and def.platforms[1].x == 1.5 and def.platforms[1].y == 1.5, "地面图片生成一份整格碰撞")
    V.assert(#def.story == 1 and #def.wires == 1 and def.spawn.x == 1, "玩法元数据随快照保留")
    V.assert(not ME.applyBrush(2, 3, false), "相同瓦片重复落笔无额外变化")
    ME.setLayer("foreground")
    ME.selectTiles("builtin", 5, 1, 1, 4, "decoration")
    ME.applyBrush(2, 3, false)
    V.assert(#TM.parse(ME.captureData()).platforms == 1, "叠加装饰不增加重复碰撞")
    ME.setLayer("gameplay")
    ME.brush = "W"
    ME.applyBrush(2, 3, false)
    ME.setLayer("ground")
    ME.applyBrush(2, 3, true)
    def = TM.parse(ME.captureData())
    V.assert(#def.platforms == 0 and #def.hazards == 1, "擦地面不擦装饰与玩法，地面碰撞随来源移除")
    V.assert(ME.getVisualCell("foreground", 2, 3).tileId == 5, "另一图片层完整保留")
    ME.selectTiles("builtin", 1, 2, 2, 4, "ground")
    ME.applyRect(1, 1, 5, 2, false)
    V.assert(ME.getVisualCell("ground", 1, 1).tileId == 1 and ME.getVisualCell("ground", 2, 1).tileId == 2 and ME.getVisualCell("ground", 3, 1).tileId == 1, "矩形瓦片图案横向平铺")
    V.assert(ME.getVisualCell("ground", 1, 2).tileId == 5, "矩形瓦片图案保持图集列偏移")
    ME.getLayerState("ground").locked = true
    V.assert(not ME.applyBrush(5, 4, false), "锁定层拒绝绘制")
    ME.getLayerState("ground").locked = false
    ME.getLayerState("ground").visible = false
    V.assert(not ME.applyBrush(5, 4, false), "隐藏层拒绝绘制")
    ME.getLayerState("ground").visible = true
    ME.brushSize = 3
    ME.applyBrush(3, 3, false)
    V.assert(ME.getVisualCell("ground", 2, 2).tileId == 1 and ME.getVisualCell("ground", 4, 4).tileId == 1, "大画笔重复首格而非组合选择")
    ME.applyBrush(3, 3, true)
    V.assert(ME.getVisualCell("ground", 2, 2) == nil and ME.getVisualCell("ground", 4, 4) == nil and ME.getVisualCell("foreground", 2, 3) ~= nil, "大橡皮只擦当前层和实际画笔范围")
    ME.brushSize = 1
    ME.applyRect(1, 1, 5, 2, false)
    ME.setLayer("collision")
    ME.applyBrush(1, 1, true)
    V.assert(ME.collisionCells["1:1"] == false, "碰撞擦除保存显式false")
    def = TM.parse(ME.captureData())
    V.assert(def.platforms[1].x == 3 and def.platforms[1].w == 4, "显式false切断图像地面碰撞段")
    local snapshot = ME.captureData()
    snapshot.visualLayers.ground.cells["2:1"].tileId = 8
    V.assert(ME.getVisualCell("ground", 2, 1).tileId == 2, "捕获数据不引用活动网格")
    ME.resize(3, 3)
    V.assert(ME.cols == 3 and ME.rows == 3 and ME.getVisualCell("ground", 5, 1) == nil, "缩小地图裁剪图片层")
    V.assert(ME.getVisualCell("foreground", 2, 3) ~= nil and ME.grid[3][2] == "W", "缩放保留交集内装饰与玩法")
    local export = ME.exportLevelFile("__tile_editor_regression__", "测试")
    V.assert(export:find("visualLayers", 1, true) ~= nil and export:find("collisionCells", 1, true) ~= nil and export:find("保留剧情", 1, true) ~= nil, "完整导出保留视觉碰撞与元数据")
    V.assert(ME.saveToSandbox(), "测试地图保存沙箱成功")
    ME.newMap(5, 5)
    V.assert(ME.loadFromSandbox("__tile_editor_regression__") and ME.cols == 3 and ME.rows == 3, "沙箱恢复新地图尺寸")
    V.assert(ME.collisionCells["1:1"] == false and ME.getVisualCell("ground", 2, 1).tileId == 2 and ME.grid[3][2] == "W", "沙箱往返保留false图片玩法")
    ME.newMap(7, 6)
    V.assert(ME.saveToSandbox() and ME.loadFromSandbox("__tile_editor_regression__") and ME.cols == 7 and ME.rows == 6, "全空地图保存不被裁成零行")
    local builtin = TS.get("builtin")
    V.assert(builtin and builtin.count == 8 and builtin.columns == 4 and builtin.rows == 2, "内置测试瓦片集稳定编号")
    V.assert(TS.tileCollider("builtin", 1) == "ground" and TS.tileCollider("builtin", 5) == "decoration", "瓦片仅两种碰撞类型")
    V.assert(not TS.register({ path = "/workspace/assets/image/地图/tiles/a.png", cellWidth = 32, cellHeight = 32 }), "登记拒绝工作机绝对路径")
    V.assert(not TS.register({ path = "image/地图/tiles/../a.png", cellWidth = 32, cellHeight = 32 }), "登记拒绝目录穿越")
    ME.loadSource({ id = "__tile_editor_regression__", map = "#=W  \n#####\n     ", cols = 5, rows = 3, tile = 1, originX = 0, originY = 3 })
    ME.setLayer("ground")
    ME.tool, ME.brushSize = "erase", 1
    V.assert(ME.applyBrush(1, 1) and ME.grid[1][1] == " ", "地形外观橡皮可擦旧字符地面")
    V.assert(ME.applyBrush(2, 1, true) and ME.grid[1][2] == " ", "右键擦除语义可擦旧字符平台")
    V.assert(not ME.applyBrush(3, 1, true) and ME.grid[1][3] == "W", "地形橡皮不误删非地形玩法")
    ME.setLayer("foreground")
    V.assert(not ME.applyBrush(1, 2, true) and ME.grid[2][1] == "#", "前景橡皮不会跨层删旧地面")
    ME.setLayer("ground")
    ME.getLayerState("ground").locked = true
    V.assert(not ME.applyBrush(1, 2, true) and ME.grid[2][1] == "#", "旧地面遵守地形层锁定")
    ME.getLayerState("ground").locked = false
    ME.getLayerState("ground").visible = false
    V.assert(not ME.applyBrush(1, 2, true) and ME.grid[2][1] == "#", "旧地面遵守地形层隐藏")
    ME.getLayerState("ground").visible = true
    ME.selectTiles("builtin", 1, 1, 1, 4, "ground")
    ME.applyBrush(1, 2, false)
    ME.applyBrush(1, 2, true)
    V.assert(ME.getVisualCell("ground", 1, 2) == nil and ME.grid[2][1] == " ", "图片与旧地形重叠一次擦除不会露出旧灰块")
    ME.collisionCells["2:2"] = true
    ME.collisionCells["3:2"] = false
    ME.applyBrush(2, 2, true)
    ME.applyBrush(3, 2, true)
    V.assert(ME.collisionCells["2:2"] == true and ME.collisionCells["3:2"] == false, "地形擦除保留独立碰撞true和false覆盖")
    ME.brushSize = 3
    ME.applyBrush(4, 2, true)
    V.assert(ME.grid[2][4] == " " and ME.grid[2][5] == " ", "范围橡皮按格擦除旧地面")
    def = TM.parse(ME.captureData())
    V.assert(#def.platforms == 1 and def.platforms[1].x == 1.5 and #def.hazards == 1, "编译后不复生旧地面，仅保留独立碰撞和玩法")
    V.assert(ME.saveToSandbox() and ME.loadFromSandbox("__tile_editor_regression__") and ME.grid[1][1] == " " and ME.grid[2][1] == " ", "擦除旧地面保存重载后保持为空")
    ME.clearSandbox("__tile_editor_regression__")
    for _, key in ipairs(fields) do ME[key] = savedState[key] end
end)
