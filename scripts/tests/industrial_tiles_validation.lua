-- 上传工业瓦片的真实解码、图集顺序、碰撞和保存试玩验收。
-- 使用隔离地图，不修改玩家原关卡和进度。
---@class IndustrialTilesTestHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "此测试只能由官方验证运行器加载") --[[@as IndustrialTilesTestHarness]]
local TS = require "core.tilesets"
local TerrainTiles = require "core.terrain_tiles"
local ME = require "core.map_editor"
local TM = require "core.tilemap"
local Editor = require "ui.map_editor"
local UI = require "urhox-libs/UI"
local HUD = require "ui.hud"
local GS = require "core.state"
local testId = "__industrial_tiles_validation__"
local originalSave = GS.saveGame
local expected = {
    { id = "industrial_walls", cols = 6, rows = 4, count = 24, collider = "ground" },
    { id = "industrial_platforms", cols = 5, rows = 1, count = 5, collider = "ground" },
    { id = "industrial_pipes", cols = 4, rows = 4, count = 16, collider = "decoration" },
    { id = "industrial_panels", cols = 3, rows = 2, count = 6, collider = "decoration" },
}

local function findClass(widget, className)
    if widget._className == className then return widget end
    for _, child in ipairs(widget:GetChildren()) do
        local found = findClass(child, className)
        if found then return found end
    end
    return nil
end

V.atFrame(10, function()
    GS.saveGame = function() return true end
    GS.save = GS.defaultSave()
    assert(rawget(_G, "LoadLevel"))("world")
    assert(rawget(_G, "OpenMapEditor"))("world")
    ME.currentLevel = testId
    ME.loadSource({ id = testId, cols = 22, rows = 14, tile = 1, originX = 0, originY = 14,
        map = string.rep("                      \n", 13) .. "######################", spawn = { x = 4, y = 2 } })
    ME.setLayer("ground")
    ME.selectTiles("industrial_walls", 1, 6, 4, 6, "ground")
    ME.applyBrush(8, 5, false)
    ME.selectTiles("industrial_platforms", 1, 5, 1, 5, "ground")
    ME.applyBrush(7, 11, false)
    ME.setLayer("foreground")
    ME.selectTiles("industrial_pipes", 1, 4, 1, 4, "decoration")
    ME.applyBrush(7, 10, false)
    ME.selectTiles("industrial_panels", 1, 3, 1, 3, "decoration")
    ME.applyBrush(13, 10, false)
    ME.setLayer("ground")
    ME.selectTiles("industrial_walls", 1, 1, 1, 6, "ground")
    ME.centerCamera()
    UI.Layout()
end)

V.atFrame(80, function()
    local total = 0
    for _, spec in ipairs(expected) do
        local def = TS.get(spec.id)
        V.assert(def and def.status == "ready", spec.id .. " 真实图片已加载")
        if def then
            V.assert(def.columns == spec.cols and def.rows == spec.rows and def.count == spec.count, spec.id .. " 列行数量正确且没有空槽")
            V.assert(def.imageWidth == spec.cols * 256 and def.imageHeight == spec.rows * 256, spec.id .. " 真实像素尺寸正确")
            V.assert(TS.tileCollider(spec.id, 1) == spec.collider, spec.id .. " 默认碰撞类型正确")
            total = total + def.count
        end
    end
    V.assert(total == 51, "四个图集合计51块原画切片")
    local wall = assert(TS.get("industrial_walls"))
    for mask = 0, 15 do
        local cells = { ["2:2"] = { tilesetId = wall.id, tileId = 1, collider = "ground" } }
        local keys = { "1:2", "3:2", "2:1", "2:3" }
        for index, key in ipairs(keys) do
            if (mask & (1 << (index - 1))) ~= 0 then
                cells[key] = { tilesetId = wall.id, tileId = 1, collider = "ground" }
            end
        end
        local rect = TerrainTiles.sourceRect(wall, { cells = cells }, 2, 2)
        local x0, x1 = (mask & 1) ~= 0 and 24 or 12, (mask & 2) ~= 0 and 232 or 243
        local y0, y1 = (mask & 4) ~= 0 and 16 or 4, (mask & 8) ~= 0 and 240 or 252
        V.assert(rect and rect.x == x0 and rect.y == y0
            and rect.width == x1 - x0 and rect.height == y1 - y0,
            "墙体四邻接精确裁切：" .. mask)
        V.assert(cells["2:2"].tileId == 1, "邻接绘制不修改序列化瓦片编号：" .. mask)
    end
    local malformed = { cells = { ["2:2"] = { tilesetId = wall.id, tileId = 1, collider = "ground" }, ["1:2"] = false } }
    local safe = TerrainTiles.sourceRect(wall, malformed --[[@as VisualMapLayer]], 2, 2)
    V.assert(safe and safe.x == 12, "畸形邻格视为空，不崩溃或错误连通")
    local lone = { cells = { ["2:2"] = { tilesetId = wall.id, tileId = 2, collider = "ground" } } }
    V.assert(TerrainTiles.sourceRect(wall, lone, 2, 2) == nil, "其他23片原墙体保持原切片")
    lone.cells["2:2"].tileId, lone.cells["2:2"].collider = 1, "decoration"
    V.assert(TerrainTiles.sourceRect(wall, lone, 2, 2) == nil, "装饰墙片不触发地形裁切")
    lone.cells["2:2"].collider = "ground"
    wall.cellWidth = 128
    V.assert(TerrainTiles.sourceRect(wall, lone, 2, 2) == nil, "自定义切片尺寸不套用原图测量")
    local grid = findClass(HUD.root, "EditorTileGrid")
    V.assert(grid and grid.setId_ == "industrial_walls", "编辑器默认预选上传墙体而不是基础测试")
    V.assert(TS.status("industrial_walls", UI.vg) == "ready", "UI上下文真实图集也已解码")
    local compiled = TM.parse(ME.captureData())
    V.assert(#compiled.platforms == 3, "同位同宽墙体纵向合并，装饰不增加碰撞")
    V.assert(#compiled.visualPlatformRects == 6, "纵向碰撞合并仍保留6个原水平视觉段")
    V.assert(ME.getVisualCell("ground", 13, 8).tileId == 24, "框选按图集原行列编号放置最后一片")
    V.assert(ME.getVisualCell("foreground", 7, 10).collider == "decoration", "管道不产生自动阻挡")
    V.assert(#ME.captureData().tilesets == 4, "保存包含完整四份图集配置")
end)

V.atFrame(125, function()
    local palette = findClass(HUD.root, "EditorTilePalette")
    V.assert(palette ~= nil, "存在真实瓦片调色板")
    if palette then palette.dropdown_:SetValue("industrial_pipes") end
    UI.Layout()
end)

V.atFrame(160, function()
    V.assert(TS.status("industrial_pipes", UI.vg) == "ready", "切换管道图集后UI解码正常")
    V.assert(ME.saveToSandbox(), "真实瓦片地图保存成功")
    V.assert(Editor.hide(), "保存成功后编辑器可关闭")
    assert(rawget(_G, "LoadLevel"))(testId)
    local level = require "core.level"
    V.assert(level.def.tilemapData.visualLayers.ground.cells["13:8"].tileId == 24, "试玩恢复墙体最后一片")
    V.assert(level.def.tilemapData.visualLayers.foreground.cells["7:10"].tilesetId == "industrial_pipes", "试玩恢复装饰及其图集")
end)

V.atFrame(190, function()
    ME.clearSandbox(testId)
    GS.saveGame = originalSave
end)
