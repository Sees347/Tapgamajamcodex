-- ============================================================================
-- core/tilemap.lua - 字符玩法地图 + 分层图片瓦片解析器
--
-- 字符源只负责旧地形与玩法标记；图片层不会覆盖字符或生成重复玩法实体。
-- 网格 col/row 与图片 cell 键均为 1 基，世界单位为米，左上角为 originX/Y。
-- 旧版无 cols/rows 的 [[地图]] 保留首尾空行裁剪；显式尺寸的 v2 地图不裁空白。
-- ============================================================================

local Backgrounds = require "core.map_backgrounds"
local Tilemap = {}

Tilemap.MAX_COLS, Tilemap.MAX_ROWS, Tilemap.MAX_CELLS = 2048, 512, 1048576

--- 在分配网格前验证尺寸；不把超限存档静默截断到默认画布。
---@param cols number
---@param rows number
---@return boolean
function Tilemap.validDimensions(cols, rows)
    return type(cols) == "number" and type(rows) == "number"
        and cols == cols and rows == rows and cols % 1 == 0 and rows % 1 == 0
        and cols >= 1 and cols <= Tilemap.MAX_COLS and rows >= 1 and rows <= Tilemap.MAX_ROWS
        and cols * rows <= Tilemap.MAX_CELLS
end

--- 只数行列，不分配完整网格；兼容旧地图首尾空行规则。
---@param source table
---@return boolean
function Tilemap.validSource(source)
    if type(source.map) ~= "string" then return false end
    local lines, width = {}, 0
    for line in (source.map:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
        width = math.max(width, #line)
    end
    if source.cols == nil and source.rows == nil then
        while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
        while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
    end
    return Tilemap.validDimensions(source.cols or width, source.rows or #lines)
end

---@class TerrainCollisionRect
---@field x number
---@field y number
---@field w number
---@field h number
---@field kind string

---@class TerrainCollisionRun
---@field rect TerrainCollisionRect
---@field row integer
---@field height integer

---@class MapTileCell
---@field tilesetId string
---@field tileId integer
---@field collider 'ground'|'decoration'

---@class MapLayerState
---@field visible boolean
---@field locked boolean

---@class MapVisualLayer : MapLayerState
---@field cells table<string, MapTileCell>

---@class MapVisualLayers
---@field background MapVisualLayer
---@field ground MapVisualLayer
---@field foreground MapVisualLayer

---@class MapTileSelection : MapTileCell
---@field width integer
---@field height integer
---@field columns integer

---@class TilemapData
---@field tile number
---@field originX number
---@field originY number
---@field cols integer
---@field rows integer
---@field map string
---@field visualLayers MapVisualLayers
---@field collisionCells table<string, boolean>
---@field layerStates table<string, MapLayerState>
---@field tilesets MapTilesetInput[]|nil
---@field backgroundImages? MapBackgroundImage[]

-- 图例：字符 → 元素定义。用户改地图时对照这张表即可。
-- type: solid 实心地形 / platform 平台 / hazard 机关 / enemy 敌人 / item 物品 / crate 可破坏箱
Tilemap.LEGEND = {
    -- ---- 地形 ----
    ["#"] = { type = "solid" },        -- 实心地面/墙
    ["="] = { type = "platform" },     -- 平台（可站立，视觉更薄）
    -- ---- 危险与机关 ----
    ["F"] = { type = "hazard", kind = "fire", w = 1.6, h = 1.0 },
    ["f"] = { type = "hazard", kind = "weakfire", w = 1.4, h = 1.0 },
    ["C"] = { type = "hazard", kind = "cold", w = 2.0, h = 0.8 },
    -- 凝珠：吸收一次回 3 格水量（absorbAmount），然后消失
    ["W"] = { type = "hazard", kind = "water", w = 0.8, h = 0.8, charges = 1 },
    ["S"] = { type = "hazard", kind = "spring", w = 1.2, h = 1.2 },
    ["P"] = { type = "hazard", kind = "plate", w = 1.6, h = 0.3 },
    ["D"] = { type = "hazard", kind = "door", w = 0.8, h = 2.8, needsPower = true },
    ["O"] = { type = "hazard", kind = "outlet", w = 0.6, h = 0.6 },
    ["A"] = { type = "hazard", kind = "alarm", w = 0.7, h = 0.5, needsPower = true },
    ["Z"] = { type = "hazard", kind = "sponge", w = 1.0, h = 1.0 },
    -- ---- 章节传送 ----
    -- T：终点传送门。经过后传送到下一章的「传送点」(t)。
    ["T"] = { type = "portal", w = 1.6, h = 2.6 },
    -- t：章节传送点。从上一章传送门过来时的落点（不写则用关卡默认出生点）。
    ["t"] = { type = "arrival" },
    -- ---- 敌人 ----
    ["1"] = { type = "enemy", key = "cleaner01" },
    ["2"] = { type = "enemy", key = "cleaner02" },
    ["y"] = { type = "enemy", key = "fly" },
    ["s"] = { type = "enemy", key = "spore" },
    ["c"] = { type = "enemy", key = "crab" },
    ["b"] = { type = "enemy", key = "lightBeast" },
    ["m"] = { type = "enemy", key = "manyHands" },
    ["B"] = { type = "enemy", key = "bossIceFire" },
    -- ---- 物品 ----
    ["$"] = { type = "item", kind = "shell" },
    ["Q"] = { type = "item", kind = "brokenQuanxin" },
    ["H"] = { type = "item", kind = "symbShard" },
    ["X"] = { type = "crate" },        -- 可破坏箱
    -- ---- 水生生物（装备拾取物）----
    ["a"] = { type = "item", kind = "fish", fishKey = "archerfish" },   -- 射水鱼
    ["e"] = { type = "item", kind = "fish", fishKey = "eel" },          -- 电鳗
    ["l"] = { type = "item", kind = "fish", fishKey = "flyfish" },      -- 飞鱼
    ["j"] = { type = "item", kind = "fish", fishKey = "anglerfish" },   -- 鮟鱇鱼
    ["r"] = { type = "item", kind = "fish", fishKey = "ray" },          -- 鳐鱼
    ["n"] = { type = "item", kind = "fish", fishKey = "barnacle" },     -- 藤壶
    ["g"] = { type = "item", kind = "fish", fishKey = "frog" },         -- 青蛙
    ["w"] = { type = "item", kind = "fish", fishKey = "swordfish" },    -- 剑鱼
    -- ---- 探索奖励（饰品拾取物）----
    ["u"] = { type = "item", kind = "relic", relicKey = "waterPendant" },  -- 凝水坠饰
    ["h"] = { type = "item", kind = "relic", relicKey = "heatCrystal" },   -- 耐热结晶
    ["o"] = { type = "item", kind = "relic", relicKey = "coldShell" },     -- 隔冷壳
    ["i"] = { type = "item", kind = "relic", relicKey = "bulletShard" },   -- 弹壳碎片
    ["p"] = { type = "item", kind = "relic", relicKey = "vaporFilm" },     -- 水汽护膜
}

-- 可作为"地形"合并的字符
local TERRAIN_CHARS = { ["#"] = "solid", ["="] = "platform" }
local VISUAL_IDS = { "background", "ground", "foreground" }

--- 读取旧字符串或显式尺寸地图。显式尺寸时，首尾空行都是有效网格行。
---@param mapStr string
---@param cols number|nil
---@param rowCount number|nil
---@return string[] lines, integer width, integer height
function Tilemap.readRows(mapStr, cols, rowCount)
    local lines = {}
    for line in (mapStr:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    if cols == nil and rowCount == nil then
        while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
        while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
    end
    local width = 0
    for _, line in ipairs(lines) do width = math.max(width, #line) end
    if type(cols) == "number" and cols == cols and cols > -math.huge and cols < math.huge then
        width = math.max(0, math.floor(cols))
    end
    local height = #lines
    if type(rowCount) == "number" and rowCount == rowCount and rowCount > -math.huge and rowCount < math.huge then
        height = math.max(0, math.floor(rowCount))
    end
    local result = {}
    for r = 1, height do
        local line = (lines[r] or ""):sub(1, width)
        result[r] = line .. string.rep(" ", math.max(0, width - #line))
    end
    return result, width, height
end

--- 字符串键 col:row → 1 基坐标；拒绝越界或非整数键。
---@param key any
---@param cols integer
---@param rows integer
---@return integer|nil col, integer|nil row
function Tilemap.cellCoords(key, cols, rows)
    if type(key) ~= "string" then return nil, nil end
    local cs, rs = key:match("^(%d+):(%d+)$")
    local c, r = tonumber(cs), tonumber(rs)
    if not c or not r or c < 1 or c > cols or r < 1 or r > rows then return nil, nil end
    return math.floor(c), math.floor(r)
end

--- 统一旧/新数据为三张独立图片层，绝不引用或修改源数据。
---@param data table
---@param cols integer
---@param rows integer
---@return MapVisualLayers layers, table<string, boolean> collision, table<string, MapLayerState> states
function Tilemap.normalizeLayers(data, cols, rows)
    ---@type MapVisualLayers
    local layers = {
        background = { cells = {}, visible = true, locked = false },
        ground = { cells = {}, visible = true, locked = false },
        foreground = { cells = {}, visible = true, locked = false },
    }
    ---@type table<string, boolean>
    local collision = {}
    ---@type table<string, MapLayerState>
    local states = {
        collision = { visible = true, locked = false },
        gameplay = { visible = true, locked = false },
    }
    local savedLayers = type(data.visualLayers) == "table" and data.visualLayers or {}
    local savedStates = type(data.layerStates) == "table" and data.layerStates or {}
    for _, id in ipairs(VISUAL_IDS) do
        local layer = layers[id] --[[@as MapVisualLayer]]
        local saved = savedLayers[id]
        if type(saved) == "table" then
            layer.visible = saved.visible ~= false
            layer.locked = saved.locked == true
            if type(saved.cells) == "table" then
                for key, cell in pairs(saved.cells) do
                    local c, r = Tilemap.cellCoords(key, cols, rows)
                    if c and r and type(cell) == "table" and type(cell.tilesetId) == "string"
                        and cell.tilesetId ~= "" and type(cell.tileId) == "number"
                        and cell.tileId >= 1 and cell.tileId < math.huge then
                        layer.cells[c .. ":" .. r] = {
                            tilesetId = cell.tilesetId,
                            tileId = math.floor(cell.tileId),
                            collider = cell.collider == "ground" and "ground" or "decoration",
                        }
                    end
                end
            end
        end
        -- 兼容把图片层状态单独存到 layerStates 的版本；图片层自身状态优先。
        local state = savedStates[id]
        if type(state) == "table" then
            if type(saved) ~= "table" or saved.visible == nil then layer.visible = state.visible ~= false end
            if type(saved) ~= "table" or saved.locked == nil then layer.locked = state.locked == true end
        end
    end
    for _, id in ipairs({ "collision", "gameplay" }) do
        local state = savedStates[id]
        if type(state) == "table" then
            states[id] = { visible = state.visible ~= false, locked = state.locked == true }
        end
    end
    if type(data.collisionCells) == "table" then
        for key, value in pairs(data.collisionCells) do
            local c, r = Tilemap.cellCoords(key, cols, rows)
            if c and r and type(value) == "boolean" then collision[c .. ":" .. r] = value end
        end
    end
    return layers, collision, states
end

--- 把字符玩法与图片碰撞编译成 LevelDef；src.metadata 提供沙箱元数据兜底。
---@param src table
---@return table LevelDef
function Tilemap.parse(src)
    assert(type(src) == "table", "Tilemap.parse: 需要地图表")
    assert(type(src.map) == "string", "Tilemap.parse: 缺少 map 字符串")
    assert(Tilemap.validSource(src), "Tilemap.parse: 地图尺寸无效或超限")
    local metadata = type(src.metadata) == "table" and src.metadata or {}
    local function option(key, fallback)
        if src[key] ~= nil then return src[key] end
        if metadata[key] ~= nil then return metadata[key] end
        return fallback
    end
    local tile = option("tile", 1.0)
    assert(type(tile) == "number" and tile > 0 and tile < math.huge, "Tilemap.parse: tile 必须为正米数")
    local originX = option("originX", 0.0)
    local originY = option("originY", 0.0)
    local rows, maxCols, rowCount = Tilemap.readRows(src.map, src.cols, src.rows)
    local visualLayers, collisionCells, layerStates = Tilemap.normalizeLayers(src, maxCols, rowCount)
    assert(type(originX) == "number" and originX > -math.huge and originX < math.huge
        and type(originY) == "number" and originY > -math.huge and originY < math.huge,
        "Tilemap.parse: originX/Y 必须为有限米数")
    -- 编辑器配置契约：属性键为 1 基 col:row，连线端点仍用旧 progressId_col0_row0。
    -- 不允许配置改写 kind/x/y/id，避免陈旧属性把换笔刷后的元素变成另一个实体。
    local savedProperties = option("elementProperties", {})
    local elementProperties = type(savedProperties) == "table" and savedProperties or {}
    local wires = {}
    local savedWires = option("wires", {})
    if type(savedWires) == "table" then
        for _, wire in ipairs(savedWires) do
            if type(wire) == "table" and type(wire.from) == "string" and wire.from ~= ""
                and type(wire.to) == "string" and wire.to ~= "" then
                wires[#wires + 1] = { from = wire.from, to = wire.to }
            end
        end
    end

    -- 内部实体坐标沿用旧版 0 基换算；图片键始终 1 基。
    local function cellCenter(col, row)
        return originX + (col + 0.5) * tile,
               originY - (row + 0.5) * tile
    end

    local platforms = {} ---@type TerrainCollisionRect[]
    local visualPlatformRects = {} ---@type TerrainCollisionRect[]
    -- 手绘多边形碰撞：世界米坐标，Box2D 要求每块 3–8 顶点且为凸形。
    local collisionPolygons = {}
    local savedPolygons = option("collisionPolygons", {})
    if type(savedPolygons) == "table" then
        for _, poly in ipairs(savedPolygons) do
            if type(poly) == "table" and type(poly.vertices) == "table" then
                local verts = {}
                for _, v in ipairs(poly.vertices) do
                    if type(v) == "table" and type(v.x) == "number" and type(v.y) == "number"
                        and v.x == v.x and v.y == v.y and v.x > -math.huge and v.x < math.huge
                        and v.y > -math.huge and v.y < math.huge then
                        verts[#verts + 1] = { x = v.x, y = v.y }
                    end
                end
                if #verts >= 3 and #verts <= 8 then
                    collisionPolygons[#collisionPolygons + 1] = { id = tostring(poly.id or #collisionPolygons + 1), vertices = verts }
                end
            end
        end
    end
    local def = {
        id = option("id", src.level or "map"),
        seamless = option("seamless", false),
        progressId = option("progressId", option("id", src.level or "map")),
        name = option("name", "未命名地图"),
        subtitle = option("subtitle", ""),
        theme = option("theme", "lab"),
        deathY = option("deathY", originY - rowCount * tile - 4),
        bounds = option("bounds", {
            minX = originX - tile,
            maxX = originX + maxCols * tile + tile,
            minY = originY - rowCount * tile - tile,
            maxY = originY + tile,
        }),
        spawn = option("spawn", { x = originX + tile, y = originY - tile }),
        startForm = option("startForm", "liquid"),
        bgMusic = option("bgMusic"),
        platforms = platforms,
        -- 手绘多边形碰撞体（与瓦片平台并存）。
        collisionPolygons = collisionPolygons,
        -- 未纵向合并的原水平段，仅供无图片/覆盖的旧地图保留逐行外观。
        visualPlatformRects = visualPlatformRects,
        hazards = {},
        enemies = {},
        items = {},
        crates = {},
        portals = {},
        arrival = option("arrival"),
        story = option("story", {}),
        exits = {},
        wires = wires,
        tilemapData = {
            tile = tile, originX = originX, originY = originY,
            cols = maxCols, rows = rowCount, map = table.concat(rows, "\n"),
            visualLayers = visualLayers, collisionCells = collisionCells, layerStates = layerStates,
            tilesets = option("tilesets"),
            backgroundImages = Backgrounds.normalize(option("backgroundImages", {})),
        },
    }
    if not def.seamless then
        for _, ex in ipairs(option("exits", {})) do table.insert(def.exits, ex) end
    end

    -- 碰撞设计（整格实体；无斜坡/单向平台；visible/locked 仅是编辑/显示状态）：
    -- 行 r:    [ # ][图片 ground][ = ][ false ][true][装饰]
    -- 横向:    |----一个水平整格矩形----|  空    |实体| 空
    -- 行 r+1:  |----同起点、同宽 solid---|  空    |实体| 空 → 只向下延伸
    -- 行 r+2:  |---更短---| 空 |实体|       → 宽度变化/孔洞/凹口立即截断
    -- 目的：旧地形 OR 三层图片 ground，再由 collisionCells true/false 最终覆盖。
    -- 边界：false 切断段；薄 platform 段不跨行；混合段沿用旧规则提升为 solid；
    --       首尾/单格、地面/天花板同一规则，邻接段允许共边但绝不正面积重叠；
    --       实体独立扫描，箱子/门/拾取物等绝不参与地形合并。
    ---@param col integer
    ---@param row integer
    ---@param ch string
    ---@return string|nil
    local function collisionKind(col, row, ch)
        local key = col .. ":" .. row
        local override = collisionCells[key]
        if override == false then return nil end
        if override == true then return "solid" end
        for _, id in ipairs(VISUAL_IDS) do
            local cell = visualLayers[id].cells[key]
            if cell and cell.collider == "ground" then return "solid" end
        end
        return TERRAIN_CHARS[ch]
    end
    -- 同起终点的相邻 solid 行向下合并；薄平台保留每行语义，碰撞联合不变。
    -- 保留整数首行/高度并一次换算世界坐标，避免长柱逐次浮点偏移累积。
    local previousRuns = {} ---@type table<string, TerrainCollisionRun?>
    for rowIdx, line in ipairs(rows) do
        local currentRuns = {} ---@type table<string, TerrainCollisionRun>
        local col = 1
        while col <= maxCols do
            local kind = collisionKind(col, rowIdx, line:sub(col, col))
            if kind then
                local start = col
                col = col + 1
                while col <= maxCols do
                    local nextKind = collisionKind(col, rowIdx, line:sub(col, col))
                    if not nextKind then break end
                    if nextKind == "solid" then kind = "solid" end
                    col = col + 1
                end
                local span = math.floor(col - start)
                local rect = {
                    x = originX + (start - 1 + span / 2) * tile,
                    y = originY - (rowIdx - 0.5) * tile,
                    w = span * tile, h = tile, kind = kind,
                } ---@type TerrainCollisionRect
                -- 必须是独立副本：碰撞合并不能移动旧视觉顶线、拉伸纹理/斑块。
                def.visualPlatformRects[#def.visualPlatformRects + 1] = {
                    x = rect.x, y = rect.y, w = rect.w, h = rect.h, kind = rect.kind,
                }
                local runKey = string.format("%d:%d", start, span)
                local run = kind == "solid" and previousRuns[runKey] or nil
                if run then
                    run.height = run.height + 1
                    run.rect.y = originY - (run.row - 1 + run.height / 2) * tile
                    run.rect.h = run.height * tile
                else
                    def.platforms[#def.platforms + 1] = rect
                    run = { rect = rect, row = rowIdx, height = 1 }
                end
                if kind == "solid" then currentRuns[runKey] = run end
            else
                col = col + 1
            end
        end

        previousRuns = currentRuns

        -- 字符源生成玩法实体，图片层和碰撞覆盖绝不擦掉玩法。
        local r = rowIdx - 1
        for c = 1, maxCols do
            local ch = line:sub(c, c)
            local col0 = c - 1
            local el = Tilemap.LEGEND[ch]
            if el and not TERRAIN_CHARS[ch] then
                local wx, wy = cellCenter(col0, r)
                if el.type == "hazard" then
                    local cellKey = c .. ":" .. rowIdx
                    local hazard = {
                        kind = el.kind, x = wx, y = wy,
                        w = el.w or 1, h = el.h or 1, charges = el.charges,
                        needsPower = el.needsPower == true,
                        id = string.format("%s_%d_%d", def.progressId, col0, r),
                        cellKey = cellKey,
                    }
                    local properties = elementProperties[cellKey]
                    if type(properties) == "table" then
                        for _, key in ipairs({ "needsPower", "open", "active", "powered" }) do
                            if type(properties[key]) == "boolean" then hazard[key] = properties[key] end
                        end
                        for _, key in ipairs({ "w", "h", "charges" }) do
                            local value = properties[key]
                            if type(value) == "number" and value > 0 and value < math.huge
                                and (key ~= "charges" or value % 1 == 0) then
                                hazard[key] = value
                            end
                        end
                    end
                    table.insert(def.hazards, hazard)
                elseif el.type == "enemy" then
                    table.insert(def.enemies, { key = el.key, x = wx, y = wy })
                elseif el.type == "item" then
                    table.insert(def.items, {
                        kind = el.kind, x = wx, y = wy,
                        fishKey = el.fishKey, relicKey = el.relicKey,
                    })
                elseif el.type == "crate" then
                    table.insert(def.crates, { x = wx, y = wy, w = 0.9, h = 0.9, hp = 4 })
                elseif el.type == "portal" and not def.seamless then
                    table.insert(def.portals, { x = wx, y = wy, w = el.w or 1.6, h = el.h or 2.6 })
                    table.insert(def.exits, { x = wx, y = wy, w = el.w or 1.6, h = el.h or 2.6 })
                elseif el.type == "arrival" then
                    if not def.arrival then
                        def.arrival = { x = wx, y = wy }
                        if def.seamless and option("spawn") == nil then def.spawn = { x = wx, y = wy + 0.4 } end
                    end
                end
            end
        end
    end

    -- 只在明确选中泉眼/章节落点时改变初始出生；缺字段/无效字段保留旧逻辑。
    local initialSpawnCell = option("initialSpawnCell")
    if type(initialSpawnCell) == "table" and type(initialSpawnCell.col) == "number"
        and type(initialSpawnCell.row) == "number" and initialSpawnCell.col % 1 == 0
        and initialSpawnCell.row % 1 == 0 then
        local key = math.floor(initialSpawnCell.col) .. ":" .. math.floor(initialSpawnCell.row)
        local c, r = Tilemap.cellCoords(key, maxCols, rowCount)
        if c and r then
            local line = rows[r] or ""
            local ch = line:sub(c, c)
            local wx, wy = cellCenter(c - 1, r - 1)
            if ch == "S" then
                def.spawn = { x = wx, y = wy + 0.8 }
                def.initialSpringId = string.format("%s_%d_%d", def.progressId, c - 1, r - 1)
            elseif ch == "t" then
                def.spawn = { x = wx, y = wy + 0.4 }
            end
        end
    end

    print(string.format("[Tilemap] 解析 %s：%d 行 × %d 列，合并碰撞 %d 块，机关 %d，敌人 %d，物品 %d",
        def.id, rowCount, maxCols, #def.platforms, #def.hazards, #def.enemies, #def.items))
    return def
end

return Tilemap
