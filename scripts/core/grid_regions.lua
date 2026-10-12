-- 整数网格矩形合并：只合并相邻行中起点、终点和类型均一致的水平段。
-- 碰撞设计： [####]  [##] → 同宽同位段向下延伸；孔洞/false/类型变化立即截断。
-- 占用联合严格不变，不跨缝补格、不重叠，地面/天花板沿用整格双向碰撞。
local G = {}

---@class GridRegion
---@field col integer
---@field row integer
---@field width integer
---@field height integer
---@field kind string

---@param cols integer
---@param rows integer
---@param kindAt fun(col:integer, row:integer):string?
---@return GridRegion[]
function G.regions(cols, rows, kindAt)
    local result = {} ---@type GridRegion[]
    local previous = {} ---@type table<string, GridRegion?>
    for row = 1, rows do
        local current = {} ---@type table<string, GridRegion>
        local col = 1
        while col <= cols do
            local kind = kindAt(col, row)
            if kind then
                local start = col
                col = col + 1
                while col <= cols and kindAt(col, row) == kind do col = col + 1 end
                local width = math.floor(col - start)
                local key = string.format("%d:%d:%s", start, width, kind)
                local rect = previous[key]
                if rect then
                    rect.height = rect.height + 1
                else
                    rect = { col = start, row = row, width = width, height = 1, kind = kind }
                    result[#result + 1] = rect
                end
                current[key] = rect
            else
                col = col + 1
            end
        end
        previous = current
    end
    return result
end

return G
