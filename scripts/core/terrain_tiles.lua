-- 连续墙体的四邻接切片；不修改地图编号、格坐标、碰撞或原图。
-- 仅修正已测量的工业墙体第 1 槽：透明槽边不进格，完整外轮廓只保留在外露边。
local T = {}
local GridRegions = require "core.grid_regions"
local MACRO_SIZE = 4

---@class TerrainMacroGroup
---@field col integer
---@field row integer
---@field regions GridRegion[]
---@field cells integer

---@class TerrainRenderPlan
---@field interior table<string, boolean>
---@field groups table<string, TerrainMacroGroup>
---@field boundaryCells integer
---@field interiorCells integer
---@field groupCount integer
---@field cols integer
---@field rows integer
---@field revision integer

---@type table<table, TerrainRenderPlan>
local plans = setmetatable({}, { __mode = "k" })

---@class TerrainSourceRect
---@field x integer
---@field y integer
---@field width integer
---@field height integer

---@param definition { id: string }
---@param cell VisualMapCell?
---@return boolean
local function connects(definition, cell)
    return type(cell) == "table" and cell.tilesetId == definition.id and cell.tileId == 1
        and cell.collider == "ground"
end

---@param definition MapTilesetDefinition
---@param layer VisualMapLayer
---@param col integer
---@param row integer
---@return TerrainSourceRect?
function T.sourceRect(definition, layer, col, row)
    -- 自定义切片配置、其他墙片、薄平台和装饰仍按原槽绘制。
    if definition.id ~= "industrial_walls"
        or definition.path ~= "image/地图/tiles/industrial_walls.png"
        or definition.cellWidth ~= 256 or definition.cellHeight ~= 256
        or definition.margin ~= 0 or definition.spacing ~= 0
        or definition.imageWidth ~= 1536 or definition.imageHeight ~= 1024
        or not connects(definition, layer.cells[string.format("%d:%d", col, row)]) then return nil end

    -- bbox 为 [12,243)×[4,252)；内填充 [24,232)×[16,240) 全 alpha=255。
    -- 连通边使用内部纹理，外露边/外转角保留原轮廓；不扩大目标格或叠画邻格。
    local left = connects(definition, layer.cells[string.format("%d:%d", col - 1, row)])
    local right = connects(definition, layer.cells[string.format("%d:%d", col + 1, row)])
    local above = connects(definition, layer.cells[string.format("%d:%d", col, row - 1)])
    local below = connects(definition, layer.cells[string.format("%d:%d", col, row + 1)])
    local x0, x1 = left and 24 or 12, right and 232 or 243
    local y0, y1 = above and 16 or 4, below and 240 or 252
    return { x = x0, y = y0, width = math.floor(x1 - x0), height = math.floor(y1 - y0) }
end

---@param definition MapTilesetDefinition
---@return boolean
function T.supports(definition)
    return definition.id == "industrial_walls"
        and definition.path == "image/地图/tiles/industrial_walls.png"
        and definition.cellWidth == 256 and definition.cellHeight == 256
        and definition.margin == 0 and definition.spacing == 0
        and definition.imageWidth == 1536 and definition.imageHeight == 1024
end

--- 固定世界网格的 4×4 内填充组：路径只覆盖实有内部格，绝不填洞或扩轮廓。
--- 外露边仍使用原四邻接切片；原格子留给编辑、碰撞和序列化。
---@param layer VisualMapLayer
---@param cols integer
---@param rows integer
---@param revision? integer 编辑修改时显式增加；游戏已编译地图不可变
---@return TerrainRenderPlan
function T.plan(layer, cols, rows, revision)
    local version = revision or 0
    local cached = plans[layer.cells]
    if cached and cached.cols == cols and cached.rows == rows and cached.revision == version then return cached end
    local plan = { interior = {}, groups = {}, boundaryCells = 0, interiorCells = 0,
        groupCount = 0, cols = cols, rows = rows, revision = version } ---@type TerrainRenderPlan
    local definition = { id = "industrial_walls" }
    for key, cell in pairs(layer.cells) do
        local cs, rs
        if type(key) == "string" then cs, rs = key:match("^(%d+):(%d+)$") end
        local c, r = tonumber(cs), tonumber(rs)
        if c and r and key == string.format("%d:%d", c, r)
            and c >= 1 and c <= cols and r >= 1 and r <= rows and connects(definition, cell) then
            if c > 1 and c < cols and r > 1 and r < rows
                and connects(definition, layer.cells[string.format("%d:%d", c - 1, r)])
                and connects(definition, layer.cells[string.format("%d:%d", c + 1, r)])
                and connects(definition, layer.cells[string.format("%d:%d", c, r - 1)])
                and connects(definition, layer.cells[string.format("%d:%d", c, r + 1)]) then
                plan.interior[key] = true
                plan.interiorCells = plan.interiorCells + 1
                local gc, gr = math.floor((c - 1) / MACRO_SIZE) * MACRO_SIZE + 1,
                    math.floor((r - 1) / MACRO_SIZE) * MACRO_SIZE + 1
                local groupKey = string.format("%d:%d", gc, gr)
                local group = plan.groups[groupKey]
                if not group then
                    group = { col = gc, row = gr, regions = {}, cells = 0 }
                    plan.groups[groupKey] = group
                    plan.groupCount = plan.groupCount + 1
                end
                group.cells = group.cells + 1
            else
                plan.boundaryCells = plan.boundaryCells + 1
            end
        end
    end
    for _, group in pairs(plan.groups) do
        group.regions = GridRegions.regions(MACRO_SIZE, MACRO_SIZE, function(c, r)
            return plan.interior[string.format("%d:%d", group.col + c - 1, group.row + r - 1)] and "fill" or nil
        end)
    end
    plans[layer.cells] = plan
    return plan
end

return T
