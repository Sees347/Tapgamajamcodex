-- 地图碰撞优化验收：仅解析内存数据并记录绘制调用，不创建物理场景、不写存档。
-- 官方运行器：main.lua -validate-test scripts/tests/map_optimization_validation.lua
---@class MapOptimizationHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "此测试只能由官方验证运行器加载") --[[@as MapOptimizationHarness]]
local TM = require "core.tilemap"
local TR = require "core.tile_render"
local GridRegions = require "core.grid_regions"

---@class MapOptimizationRaster
---@field cells table<string, integer>
---@field area number
---@field aligned boolean
---@field overlaps integer
---@field duplicates integer
---@field outside integer

local LAYERS = { "background", "ground", "foreground" }

---@param a number
---@param b number
---@return boolean
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- 独立占用判据：false/true 最终覆盖，否则字符 #/= OR 任意图片层 ground。
-- 不复用解析器的 collisionKind/normalizeLayers/纵向合并结果作为期望值。
---@param src table
---@param col integer
---@param row integer
---@param ch string
---@return string|nil
local function expectedKind(src, col, row, ch)
    local key = col .. ":" .. row
    local override = (src.collisionCells or {})[key]
    if override == false then return nil end
    if override == true then return "solid" end
    for _, id in ipairs(LAYERS) do
        local layer = (src.visualLayers or {})[id]
        local cell = layer and (layer.cells or {})[key]
        if cell and cell.collider == "ground" then return "solid" end
    end
    if ch == "#" then return "solid" end
    if ch == "=" then return "platform" end
    return nil
end

-- 优化前的水平段参考。连续占用不按 #/= 分段，混合段提升为 solid。
---@param src table
---@param lines string[]
---@return TerrainCollisionRect[]
local function horizontalReference(src, lines)
    local result = {} ---@type TerrainCollisionRect[]
    for row, line in ipairs(lines) do
        local col = 1
        while col <= #line do
            local kind = expectedKind(src, col, row, line:sub(col, col))
            if kind then
                local first = col
                col = col + 1
                while col <= #line do
                    local nextKind = expectedKind(src, col, row, line:sub(col, col))
                    if not nextKind then break end
                    if nextKind == "solid" then kind = "solid" end
                    col = col + 1
                end
                local width = col - first
                result[#result + 1] = {
                    x = (src.originX or 0) + (first - 1 + width / 2) * (src.tile or 1),
                    y = (src.originY or 0) - (row - 0.5) * (src.tile or 1),
                    w = width * (src.tile or 1), h = src.tile or 1, kind = kind,
                }
            else
                col = col + 1
            end
        end
    end
    return result
end

---@param rects TerrainCollisionRect[]
---@param data TilemapData
---@return MapOptimizationRaster
local function rasterize(rects, data)
    local result = { cells = {}, area = 0, aligned = true, overlaps = 0, duplicates = 0, outside = 0 } ---@type MapOptimizationRaster
    local seen = {} ---@type table<string, boolean>
    for i, rect in ipairs(rects) do
        local c = (rect.x - rect.w / 2 - data.originX) / data.tile
        local r = (data.originY - rect.y - rect.h / 2) / data.tile
        local w, h = rect.w / data.tile, rect.h / data.tile
        local col, row = math.floor(c + 0.5), math.floor(r + 0.5)
        local width, height = math.floor(w + 0.5), math.floor(h + 0.5)
        result.aligned = result.aligned and near(c, col) and near(r, row)
            and near(w, width) and near(h, height) and width > 0 and height > 0
        result.area = result.area + rect.w * rect.h
        local key = string.format("%d:%d:%d:%d", col, row, width, height)
        if seen[key] then result.duplicates = result.duplicates + 1 end
        seen[key] = true
        for rr = row + 1, row + height do
            for cc = col + 1, col + width do
                if cc < 1 or cc > data.cols or rr < 1 or rr > data.rows then
                    result.outside = result.outside + 1
                end
                local cellKey = cc .. ":" .. rr
                result.cells[cellKey] = (result.cells[cellKey] or 0) + 1
            end
        end
        -- 严格正面积重叠；共边/共点不算重叠。
        for j = 1, i - 1 do
            local other = assert(rects[j])
            local ox = math.min(rect.x + rect.w / 2, other.x + other.w / 2)
                - math.max(rect.x - rect.w / 2, other.x - other.w / 2)
            local oy = math.min(rect.y + rect.h / 2, other.y + other.h / 2)
                - math.max(rect.y - rect.h / 2, other.y - other.h / 2)
            if ox > 1e-9 and oy > 1e-9 then result.overlaps = result.overlaps + 1 end
        end
    end
    return result
end

---@param src table
---@param name string
---@return table def, TerrainCollisionRect[] horizontal, integer occupied
local function verify(src, name)
    local def = TM.parse(src)
    local data = def.tilemapData --[[@as TilemapData]]
    local lines = TM.readRows(src.map, src.cols, src.rows)
    local horizontal = horizontalReference(src, lines)
    local before, after = rasterize(horizontal, data), rasterize(def.platforms, data)
    local occupied, mismatches = 0, 0
    for row = 1, data.rows do
        for col = 1, data.cols do
            local key = col .. ":" .. row
            local expected = expectedKind(src, col, row, (lines[row] or ""):sub(col, col)) ~= nil
            local count = after.cells[key] or 0
            if expected then occupied = occupied + 1 end
            if (count > 0) ~= expected or count ~= (before.cells[key] or 0) then
                mismatches = mismatches + 1
            end
        end
    end
    V.assert(mismatches == 0, name .. " 全网格占用与原水平段/独立OR判据等价")
    V.assert(near(after.area, occupied * data.tile * data.tile) and near(after.area, before.area), name .. " 面积严格守恒")
    V.assert(after.aligned and after.outside == 0, name .. " 整格对齐且不超出地图")
    V.assert(after.overlaps == 0 and after.duplicates == 0, name .. " 无同位重复/正面积重叠")
    local sameVisuals = #def.visualPlatformRects == #horizontal
    for i, rect in ipairs(horizontal) do
        local visual = def.visualPlatformRects[i] --[[@as TerrainCollisionRect?]]
        sameVisuals = sameVisuals and visual ~= nil and near(rect.x, visual.x) and near(rect.y, visual.y)
            and near(rect.w, visual.w) and near(rect.h, visual.h) and rect.kind == visual.kind
        for _, collider in ipairs(def.platforms) do
            if visual == collider then sameVisuals = false end
        end
    end
    V.assert(sameVisuals, name .. " 原水平视觉段未变且不与碰撞共享可变表")
    return def, horizontal, occupied
end

---@param map string
---@param overrides? table<string, boolean>
---@param visuals? table
---@param tile? number
---@return table
local function fixture(map, overrides, visuals, tile)
    local lines, cols, rows = TM.readRows(map, nil, nil)
    -- 显式尺寸也保留完全空白的视觉/碰撞层fixture，不让旧首尾裁剪丢掉它。
    if #lines == 0 then cols, rows = #map, 1 end
    return { id = "__map_optimization__", map = map, tile = tile or 1, cols = cols, rows = rows,
        originX = -2.5, originY = 7.25, collisionCells = overrides or {}, visualLayers = visuals or {} }
end

---@param collider string
---@return table
local function cell(collider) return { tilesetId = "fixture", tileId = 1, collider = collider } end

-- 记录 NanoVG 调用而不提交渲染；任何错误也先恢复全局函数，避免污染运行器。
---@param def table
---@param expected TerrainCollisionRect[]
---@param name string
local function verifyDraw(def, expected, name)
    local bodies = {} ---@type TerrainCollisionRect[]
    local latest = { x = 0, y = 0, w = 0, h = 0, kind = "" } ---@type TerrainCollisionRect
    local scorch = 0
    local functions = { "nvgBeginPath", "nvgRect", "nvgLinearGradient", "nvgRGBA", "nvgFillPaint",
        "nvgFill", "nvgFillColor", "nvgStrokeColor", "nvgStrokeWidth", "nvgStroke", "nvgEllipse" }
    local saved = {} ---@type table<string, any>
    for _, id in ipairs(functions) do saved[id] = rawget(_G, id); rawset(_G, id, function() end) end
    rawset(_G, "nvgRect", function(_, x, y, w, h) latest = { x = x, y = y, w = w, h = h, kind = "" } end)
    rawset(_G, "nvgLinearGradient", function() bodies[#bodies + 1] = latest; return {} end)
    rawset(_G, "nvgRGBA", function() return {} end)
    rawset(_G, "nvgEllipse", function() scorch = scorch + 1 end)
    local view = { ppu = 10, screenW = 10000, screenH = 10000, camX = 0, camY = 0,
        w2s = function(x, y) return 5000 + x * 10, 5000 - y * 10 end }
    local context = {} ---@type any
    local ok, err = pcall(function()
        TR.drawTerrain(context --[[@as NVGContextWrapper]], view --[[@as Render]],
            { def = def, platformRects = def.platforms } --[[@as Level]])
    end)
    for _, id in ipairs(functions) do rawset(_G, id, saved[id]) end
    V.assert(ok, name .. " 旧视觉分支安全绘制：" .. tostring(err))
    local matches = #bodies == #expected
    local expectedScorch = 0
    for i, rect in ipairs(expected) do
        local body = bodies[i]
        matches = matches and body ~= nil and near(body.x, 5000 + (rect.x - rect.w / 2) * 10)
            and near(body.y, 5000 - (rect.y + rect.h / 2) * 10)
            and near(body.w, rect.w * 10) and near(body.h, rect.h * 10)
        if math.floor(rect.x * 7 + rect.y * 13) % 3 == 0 then expectedScorch = expectedScorch + 1 end
    end
    V.assert(matches and scorch == expectedScorch, name .. " 旧轮廓/逐行渐变/斑块保持原水平段")
end

-- Level 的破坏逻辑只用内存箱体和空节点。恢复引用与emit，不调用load/save。
local function verifyCrateIndependence()
    local L = require "core.level"
    local GS = require "core.state"
    local oldCrates, oldRects, oldDoors, oldEmit = L.crateNodes, L.platformRects, L.doorNodes, GS.emit
    local nodesRemoved = 0
    local crates = {}
    for i = 1, 3 do
        crates[i] = { x = i * 1.0, y = 0, w = 0.9, h = 0.9, hp = 4,
            destroyed = false, hitFlash = 0, node = { Remove = function() nodesRemoved = nodesRemoved + 1 end } }
    end
    local ok, err = pcall(function()
        L.crateNodes, L.platformRects, L.doorNodes = crates, {}, {}
        GS.emit = function() end
        V.assert(L.crateAt(2, 0) == crates[2] and L.isSolid(2, 0), "相邻箱体逐箱命中且独立提供碰撞")
        V.assert(L.damageCrate(crates[2], 4), "只破坏选中的中间箱体")
        V.assert(crates[1].hp == 4 and not crates[1].destroyed and crates[3].hp == 4 and not crates[3].destroyed
            and nodesRemoved == 1, "破坏中箱不扣邻箱HP、不删除邻箱节点")
        V.assert(not L.isSolid(2, 0) and L.isSolid(1, 0) and L.isSolid(3, 0)
            and L.crateAt(2, 0) == nil, "中箱破碎后留下真实孔洞且邻箱仍独立阻挡")
        V.assert(not L.damageCrate(crates[2], 4) and nodesRemoved == 1, "已破坏箱体不重复删除")
    end)
    L.crateNodes, L.platformRects, L.doorNodes, GS.emit = oldCrates, oldRects, oldDoors, oldEmit
    V.assert(ok, "箱体独立验收完成且恢复运行器状态：" .. tostring(err))
end

V.atFrame(10, function()
    local source = require "levels.world_src"
    local world, horizontal, occupied = verify(source, "共享300×200地图")
    V.assert(world.tilemapData.cols * world.tilemapData.rows == 60000, "共享地图逐格检查60000格")
    V.assert(occupied == 9684 and near(rasterize(world.platforms, world.tilemapData).area, 9684), "共享原9684实心格/9684平方米")
    V.assert(#horizontal == 320 and #world.platforms == 91, "共享地形320水平rect保守纵向合并为91rect")
    local lines = TM.readRows(source.map, source.cols, source.rows)
    local counts = { hazards = 0, enemies = 0, items = 0, crates = 0 }
    local identity = true
    for row, line in ipairs(lines) do
        for col = 1, #line do
            local ch = line:sub(col, col)
            local el = TM.LEGEND[ch]
            if el then
                local list = ({ hazard = "hazards", enemy = "enemies", item = "items", crate = "crates" })[el.type]
                if list then
                    counts[list] = counts[list] + 1
                    local entity = world[list][counts[list]]
                    identity = identity and entity ~= nil and near(entity.x, source.originX + (col - 0.5) * source.tile)
                        and near(entity.y, source.originY - (row - 0.5) * source.tile)
                    if list == "crates" then identity = identity and entity.w == 0.9 and entity.h == 0.9 and entity.hp == 4 end
                end
            end
        end
    end
    V.assert(counts.crates == 91 and #world.crates == 91 and identity, "91箱体及机关/敌人/物品位置顺序独立保留")
    for _, id in ipairs({ "hazards", "enemies", "items", "crates" }) do
        V.assert(#world[id] == counts[id], "共享实体数量不因碰撞合并增减：" .. id)
    end

    local overrides = fixture("###=X \n###=X ", { ["2:1"] = false, ["4:1"] = true, ["5:1"] = true, ["6:1"] = true,
        ["2:2"] = true, ["4:2"] = false, ["5:2"] = false, ["6:2"] = false }, {
        background = { visible = false, locked = true, cells = { ["2:1"] = cell("ground"), ["6:2"] = cell("ground") } },
        ground = { cells = { ["2:1"] = cell("ground"), ["5:2"] = cell("ground") } },
        foreground = { cells = { ["2:1"] = cell("ground"), ["4:2"] = cell("ground") } },
    })
    local covered = verify(overrides, "false/true优先级")
    V.assert(covered.tilemapData.collisionCells["2:1"] == false and covered.tilemapData.collisionCells["6:1"] == true
        and #covered.crates == 2, "false/true序列化保留且不会擦掉玩法X")
    local union = fixture("      ", nil, {
        background = { visible = false, locked = true, cells = { ["1:1"] = cell("ground"), ["4:1"] = cell("ground") } },
        ground = { cells = { ["2:1"] = cell("ground"), ["4:1"] = cell("ground"), ["5:1"] = cell("decoration") } },
        foreground = { cells = { ["3:1"] = cell("ground"), ["4:1"] = cell("ground"), ["6:1"] = cell("decoration") } },
    })
    local merged = verify(union, "三层OR/装饰/隐藏锁定")
    V.assert(#merged.platforms == 1 and merged.platforms[1].w == 4, "三层ground合并一次且装饰不碰撞")

    local thin = verify(fixture("====\n====\n===="), "薄platform相邻三行")
    V.assert(#thin.platforms == 3 and thin.platforms[1].kind == "platform"
        and thin.platforms[1].h == 1 and thin.platforms[2].h == 1 and thin.platforms[3].h == 1, "纯=平台不跨行合并")
    local mixed = verify(fixture("=#==\n====\n##==\n=###"), "薄平台/solid混合")
    V.assert(#mixed.platforms == 3 and mixed.platforms[1].h == 1 and mixed.platforms[2].kind == "platform"
        and mixed.platforms[3].kind == "solid" and mixed.platforms[3].h == 2, "混合段旧规则solid提升且平台行阻断纵向合并")
    local holes = verify(fixture("#######\n##   ##\n##   ##\n#######\n  ###  \n   #   "), "孔洞/凹口/宽度变化")
    V.assert(#holes.platforms == 6, "孔洞和凹口不补格，只有同位同宽相邻段延伸")
    local gap = verify(fixture("###  \n###  \n     \n###  \n ### \n ### "), "空行/同宽错位")
    V.assert(#gap.platforms == 3, "不跨空行、不合并同宽但错位的rect")
    local fractional = verify(fixture("##\n##\n##\n##", nil, nil, 0.1), "非整数米制tile")
    V.assert(#fractional.platforms == 1 and fractional.platforms[1].h == 4 * 0.1
        and fractional.platforms[1].y == 7.25 - 2 * 0.1, "整数行高统一换算无逐次浮点累积")

    -- 地形外观来自字符而非碰撞false/true；有任一视觉来源就不补灰底。
    local visualSource = fixture("##=   ", { ["1:1"] = false, ["4:1"] = true }, {
        foreground = { cells = { ["2:1"] = cell("decoration") } },
    })
    local visualDef = verify(visualSource, "碰撞与视觉独立")
    verifyDraw(visualDef, {
        { x = -2, y = 6.75, w = 1, h = 1, kind = "solid" },
        { x = 0, y = 6.75, w = 1, h = 1, kind = "platform" },
    }, "false仍画字符/true不补灰底/装饰覆盖字符")
    for _, id in ipairs({ "lab01", "lab02", "lab03" }) do
        local def, original = verify(require("levels." .. id .. "_src"), "无visual旧图" .. id)
        verifyDraw(def, original, "无visual旧图" .. id)
    end
    local direct = { platforms = { { x = 2, y = -1, w = 3, h = 0.4, kind = "platform" } } }
    verifyDraw(direct, direct.platforms, "无tilemap矩形定义关卡")

    -- 源数据/解析实例互不共享；修改一次解析的碰撞或视觉不影响后续解析。
    local oldMap, oldTrue = visualSource.map, visualSource.collisionCells["4:1"]
    local oldCell = visualSource.visualLayers.foreground.cells["2:1"] --[[@as MapTileCell]]
    local oldY = visualDef.visualPlatformRects[1].y
    visualDef.platforms[1].y = 999
    V.assert(visualDef.visualPlatformRects[1].y == oldY and visualSource.map == oldMap
        and visualSource.collisionCells["4:1"] == oldTrue and oldCell.tileId == 1, "合并输出/视觉副本/源地图互不污染")
    local again = TM.parse(visualSource)
    V.assert(again.platforms[1].y ~= 999 and again.platforms[1] ~= visualDef.platforms[1], "重复解析不共享碰撞实体表")
    local adjacentCrates = verify(fixture("XXX\nXXX"), "相邻可破坏箱")
    V.assert(#adjacentCrates.platforms == 0 and #adjacentCrates.crates == 6
        and adjacentCrates.crates[1] ~= adjacentCrates.crates[2], "相邻6箱体不进入地形rect也不相互合并")
    verifyCrateIndependence()

    -- GridRegions保留纯网格/按类型视觉用途，不套用碰撞的混合段和薄平台语义。
    local grid = { "aa b", "aa b", "a bb", "   b" }
    local regions = GridRegions.regions(4, 4, function(col, row)
        local kind = (grid[row] or ""):sub(col, col)
        if kind ~= " " then return kind end
        return nil
    end)
    V.assert(#regions == 5 and regions[1].width == 2 and regions[1].height == 2,
        "GridRegions仍按类型/同位同宽合并，留给视觉模块")
    print(string.format("[MapOptimizationValidation] checkedCells=60000 occupied=%d area=9684 horizontal=%d merged=%d crates=%d duplicates=0 positiveOverlaps=0",
        occupied, #horizontal, #world.platforms, #world.crates))
end)
