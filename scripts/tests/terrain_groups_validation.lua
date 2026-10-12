-- 跨格内填充的占用等价、外边保留与编辑缓存验收，不改玩家存档或原地图。
---@class TerrainGroupsHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V")) --[[@as TerrainGroupsHarness]]
local T = require "core.terrain_tiles"
local TM = require "core.tilemap"
local TS = require "core.tilesets"

V.atFrame(10, function()
    local source = require "levels.world_src"
    local def = TM.parse(source)
    local data = assert(def.tilemapData)
    local layer = data.visualLayers.ground
    local plan = T.plan(layer, data.cols, data.rows)
    local seen = {} ---@type table<string, integer>
    local overlaps, wrongCells, count = 0, 0, 0
    for _, group in pairs(plan.groups) do
        local area = 0
        for _, rect in ipairs(group.regions) do
            for r = group.row + rect.row - 1, group.row + rect.row + rect.height - 2 do
                for c = group.col + rect.col - 1, group.col + rect.col + rect.width - 2 do
                    local key = string.format("%d:%d", c, r)
                    if seen[key] then overlaps = overlaps + 1 end
                    seen[key] = (seen[key] or 0) + 1
                    if not plan.interior[key] then wrongCells = wrongCells + 1 end
                    area, count = area + 1, count + 1
                end
            end
        end
        if area ~= group.cells then wrongCells = wrongCells + 1 end
    end
    local total, missing = 0, 0
    for key in pairs(layer.cells) do
        total = total + 1
        if plan.interior[key] and not seen[key] then missing = missing + 1 end
    end
    V.assert(total == 9684, "原地图仍保留9684个可编辑墙格")
    V.assert(plan.boundaryCells == 2221 and plan.interiorCells == 7463, "2221外边格保留，7463内部格参与跨格绘制")
    V.assert(plan.groupCount == 661, "内部合为661个固定4×4世界网格组")
    V.assert(plan.boundaryCells + plan.groupCount == 2882, "全图墙体绘制分组9684降至2882")
    V.assert(count == plan.interiorCells and missing == 0 and wrongCells == 0, "内部子路径覆盖原格并集，无填洞、漏格或越界")
    V.assert(overlaps == 0, "内部子路径无正面积重叠")
    V.assert(T.plan(layer, data.cols, data.rows) == plan, "不可变游戏地图复用缓存")

    local cells = {} ---@type table<string, VisualMapCell>
    for r = 1, 8 do
        for c = 1, 8 do cells[string.format("%d:%d", c, r)] = { tilesetId = "industrial_walls", tileId = 1, collider = "ground" } end
    end
    local sample = { cells = cells } ---@type VisualMapLayer
    local first = T.plan(sample, 8, 8, 0)
    V.assert(first.interiorCells == 36 and first.boundaryCells == 28 and first.groupCount == 4, "8×8墙面仅内部合并，外轮廓不变")
    cells["4:4"] = nil
    local second = T.plan(sample, 8, 8, 1)
    V.assert(second ~= first and not second.interior["4:4"], "编辑revision增加立即使擦除格生效")
    V.assert(not second.interior["3:4"] and not second.interior["5:4"]
        and not second.interior["4:3"] and not second.interior["4:5"], "孔洞四周重新保留外露轮廓")
    V.assert(second.interiorCells == 31, "擦除只影响该格及四邻接内外判定")
    cells["2:2"].tileId = 2
    cells["6:6"].collider = "decoration"
    local third = T.plan(sample, 8, 8, 2)
    V.assert(not third.interior["2:2"] and not third.interior["6:6"], "其他墙切片和装饰不误合并")
    local resized = T.plan(sample, 4, 4, 2)
    V.assert(resized ~= third and not resized.interior["6:6"], "同cells调整地图尺寸不会沿用越界缓存")
    local original = source.visualLayers.ground.cells["1:1"]
    V.assert(not original or original.tileId == 1, "编译及渲染计划不改原source瓦片编号")
end)

V.atFrame(85, function()
    -- 16邻接组合：边框条带+连续内区严格分割原裁切，面积不增且不重叠。
    local wall = assert(TS.get("industrial_walls"))
    for mask = 0, 15 do
        local cells = { ["2:2"] = { tilesetId = wall.id, tileId = 1, collider = "ground" } }
        for i, key in ipairs({ "1:2", "3:2", "2:1", "2:3" }) do
            if (mask & (1 << (i - 1))) ~= 0 then cells[key] = { tilesetId = wall.id, tileId = 1, collider = "ground" } end
        end
        local crop = assert(T.sourceRect(wall, { cells = cells }, 2, 2))
        local x0, x1, y0, y1 = 24 - crop.x, 232 - crop.x, 16 - crop.y, 240 - crop.y
        local rects = { { x0, y0, x1 - x0, y1 - y0 } }
        if y0 > 0 then rects[#rects + 1] = { 0, 0, crop.width, y0 } end
        if y1 < crop.height then rects[#rects + 1] = { 0, y1, crop.width, crop.height - y1 } end
        if x0 > 0 then rects[#rects + 1] = { 0, y0, x0, y1 - y0 } end
        if x1 < crop.width then rects[#rects + 1] = { x1, y0, crop.width - x1, y1 - y0 } end
        local area, overlap = 0, false
        for i, a in ipairs(rects) do
            area = area + a[3] * a[4]
            for j = 1, i - 1 do
                local b = rects[j]
                if math.min(a[1] + a[3], b[1] + b[3]) > math.max(a[1], b[1])
                    and math.min(a[2] + a[4], b[2] + b[4]) > math.max(a[2], b[2]) then overlap = true end
            end
        end
        V.assert(area == crop.width * crop.height and not overlap, "边框/内区无补格或重叠：" .. mask)
    end
    local wallStatus = TS.get("industrial_walls")
    V.assert(wallStatus and wallStatus.status == "ready" and T.supports(wallStatus), "真实原墙图解码后才启用跨格绘制")
    if wallStatus then
        wallStatus.cellWidth = 128
        V.assert(not T.supports(wallStatus), "用户自定义切片配置不套用4×4原图优化")
    end
end)
