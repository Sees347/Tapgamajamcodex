-- 手绘多边形碰撞体编辑：新建/拖顶点/加点/删点，与瓦片碰撞并存。
-- 数据存在 ME.metadata.collisionPolygons，顶点为世界米坐标；Box2D 单多边形上限 8 顶点。
local ME = require "core.map_editor"
local EC = { revision = 0, selectedId = "", selectedVertex = 0, dragging = false }

EC.MAX_VERTICES = 8
EC.MIN_VERTICES = 3
local HANDLE_R = 12   -- 顶点手柄命中半径（屏幕像素）
local EDGE_R = 9      -- 边命中半径

---@type table?
local metadataRef = nil
---@type {vertices:{x:number,y:number}[]}|nil
local draw = nil

local function sync()
    if metadataRef ~= ME.metadata then
        metadataRef = ME.metadata
        EC.selectedId, EC.selectedVertex, EC.dragging = "", 0, false
        draw = nil
        EC.revision = EC.revision + 1
    end
end

local function changed()
    ME.markDirty()
    EC.revision = EC.revision + 1
end

---@return {id:string,vertices:{x:number,y:number}[]}[]
function EC.list()
    sync()
    return ME.metadata.collisionPolygons or {}
end

---@return table?
function EC.selected()
    if EC.selectedId == "" then return nil end
    for _, poly in ipairs(EC.list()) do
        if poly.id == EC.selectedId then return poly end
    end
    return nil
end

function EC.clear()
    EC.selectedId, EC.selectedVertex, EC.dragging, draw = "", 0, false, nil
    EC.revision = EC.revision + 1
end

-- ============================================================================
-- 绘制新多边形
-- ============================================================================

function EC.beginDraw()
    sync()
    draw = { vertices = {} }
    EC.selectedId, EC.selectedVertex = "", 0
    EC.revision = EC.revision + 1
end

function EC.isDrawing()
    return draw ~= nil
end

--- 绘制中的顶点预览（世界米坐标副本）。
---@return {x:number,y:number}[]
function EC.drawPreview()
    return draw and draw.vertices or {}
end

---@return integer
function EC.drawCount()
    return draw and #draw.vertices or 0
end

---@param sx number
---@param sy number
---@param R table
---@return boolean, string
function EC.addDrawVertex(sx, sy, R)
    if not draw then return false, "未在绘制状态" end
    if #draw.vertices >= EC.MAX_VERTICES then
        return false, ("单个多边形最多 %d 个顶点（Box2D 限制）"):format(EC.MAX_VERTICES)
    end
    local wx = R.camX + (sx - R.screenW / 2) / R.ppu
    local wy = R.camY - (sy - R.screenH / 2) / R.ppu
    draw.vertices[#draw.vertices + 1] = { x = wx, y = wy }
    EC.revision = EC.revision + 1
    return true, ("已加顶点 %d/%d"):format(#draw.vertices, EC.MAX_VERTICES)
end

--- 撤销最后一个待放置顶点。
function EC.undoDrawVertex()
    if not draw or #draw.vertices == 0 then return false end
    table.remove(draw.vertices)
    EC.revision = EC.revision + 1
    return true
end

---@return boolean, string
function EC.finishDraw()
    if not draw then return false, "未在绘制状态" end
    if #draw.vertices < EC.MIN_VERTICES then
        return false, ("至少需要 %d 个顶点"):format(EC.MIN_VERTICES)
    end
    local used = {}
    for _, poly in ipairs(EC.list()) do used[poly.id] = true end
    local id = ""
    for i = 1, 999 do
        if not used["poly_" .. i] then id = "poly_" .. i break end
    end
    if id == "" then return false, "多边形数量已达上限" end
    local vertices = {}
    for i, v in ipairs(draw.vertices) do vertices[i] = { x = v.x, y = v.y } end
    ME.metadata.collisionPolygons = ME.metadata.collisionPolygons or {}
    table.insert(ME.metadata.collisionPolygons, { id = id, vertices = vertices })
    EC.selectedId, EC.selectedVertex, draw = id, 0, nil
    changed()
    print(("[碰撞多边形] 已创建 %s（%d 顶点）"):format(id, #vertices))
    return true, ("已创建碰撞多边形（%d 顶点）"):format(#vertices)
end

function EC.cancelDraw()
    if draw then draw = nil; EC.revision = EC.revision + 1 end
end

-- ============================================================================
-- 选中与编辑
-- ============================================================================

function EC.removeSelected()
    local poly = EC.selected()
    if not poly then return false, "未选中多边形" end
    local list, kept = EC.list(), {}
    for _, item in ipairs(list) do if item ~= poly then kept[#kept + 1] = item end end
    ME.metadata.collisionPolygons = kept
    EC.clear()
    changed()
    return true, "已删除多边形"
end

function EC.removeSelectedVertex()
    local poly = EC.selected()
    if not poly or EC.selectedVertex < 1 then return false, "未选中顶点" end
    if #poly.vertices <= EC.MIN_VERTICES then
        return false, ("至少保留 %d 个顶点，可直接删除整个多边形"):format(EC.MIN_VERTICES)
    end
    table.remove(poly.vertices, EC.selectedVertex)
    EC.selectedVertex = 0
    changed()
    return true, "已删除顶点"
end

---@param id string
---@return boolean
function EC.selectById(id)
    sync()
    for _, poly in ipairs(EC.list()) do
        if poly.id == id then
            EC.selectedId, EC.selectedVertex = id, 0
            EC.revision = EC.revision + 1
            return true
        end
    end
    return false
end

--- 顶点绕向一致的凸多边形判定；凹形会给出提示（Box2D 需要凸形）。
---@param vertices {x:number,y:number}[]
---@return boolean
function EC.isConvex(vertices)
    local n = #vertices
    if n < 3 then return false end
    local sign = 0
    for i = 1, n do
        local a, b, c = vertices[i], vertices[i % n + 1], vertices[(i + 1) % n + 1]
        local cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
        if cross ~= 0 then
            local s = cross > 0 and 1 or -1
            if sign == 0 then sign = s elseif s ~= sign then return false end
        end
    end
    return true
end

-- ============================================================================
-- 指针交互（屏幕坐标，与背景编辑器同约定）
-- ============================================================================

local function world(sx, sy, R)
    return R.camX + (sx - R.screenW / 2) / R.ppu, R.camY - (sy - R.screenH / 2) / R.ppu
end

local function distToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) end
    local cx, cy = ax + t * dx, ay + t * dy
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2), t
end

---@return integer? 顶点索引
local function vertexAt(poly, sx, sy, R)
    for i, v in ipairs(poly.vertices) do
        local hx, hy = R.w2s(v.x, v.y)
        if math.abs(hx - sx) <= HANDLE_R and math.abs(hy - sy) <= HANDLE_R then return i end
    end
    return nil
end

---@return integer? 边索引, number? 边上的插值位置
local function edgeAt(poly, sx, sy, R)
    local n = #poly.vertices
    for i = 1, n do
        local a, b = poly.vertices[i], poly.vertices[i % n + 1]
        local ax, ay = R.w2s(a.x, a.y)
        local bx, by = R.w2s(b.x, b.y)
        local d, t = distToSegment(sx, sy, ax, ay, bx, by)
        if d <= EDGE_R then return i, t end
    end
    return nil, nil
end

local function inside(poly, wx, wy)
    local n, insideFlag = #poly.vertices, false
    local j = n
    for i = 1, n do
        local a, b = poly.vertices[i], poly.vertices[j]
        if ((a.y > wy) ~= (b.y > wy))
            and (wx < (b.x - a.x) * (wy - a.y) / (b.y - a.y) + a.x) then
            insideFlag = not insideFlag
        end
        j = i
    end
    return insideFlag
end

---@param sx number
---@param sy number
---@param R table
---@return boolean, string
function EC.beginPointer(sx, sy, R)
    sync()
    local wx, wy = world(sx, sy, R)
    local selected = EC.selected()
    -- 1. 已选中多边形：先抓顶点手柄
    if selected then
        local vi = vertexAt(selected, sx, sy, R)
        if vi then
            EC.selectedVertex, EC.dragging = vi, true
            return true, "拖动顶点改变形状"
        end
        -- 2. 选中多边形边上点击 = 插入顶点
        local ei, t = edgeAt(selected, sx, sy, R)
        if ei and t then
            if #selected.vertices >= EC.MAX_VERTICES then
                return false, ("最多 %d 个顶点"):format(EC.MAX_VERTICES)
            end
            local a = selected.vertices[ei]
            local b = selected.vertices[ei % #selected.vertices + 1]
            local nv = { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }
            table.insert(selected.vertices, ei + 1, nv)
            EC.selectedVertex = ei + 1
            changed()
            return true, "已在边上插入顶点"
        end
    end
    -- 3. 命中其它多边形：选中
    local list = EC.list()
    for i = #list, 1, -1 do
        local poly = list[i]
        if vertexAt(poly, sx, sy, R) or edgeAt(poly, sx, sy, R) or inside(poly, wx, wy) then
            EC.selectedId, EC.selectedVertex = poly.id, 0
            EC.revision = EC.revision + 1
            return true, "已选中多边形；拖顶点改形，点边加点"
        end
    end
    EC.selectedId, EC.selectedVertex = "", 0
    EC.revision = EC.revision + 1
    return false, "点击多边形可选中"
end

---@param sx number
---@param sy number
---@param R table
function EC.movePointer(sx, sy, R)
    if not EC.dragging then return end
    local poly = EC.selected()
    if not poly or EC.selectedVertex < 1 then return end
    local wx, wy = world(sx, sy, R)
    poly.vertices[EC.selectedVertex] = { x = wx, y = wy }
    EC.revision = EC.revision + 1
end

---@param sx number
---@param sy number
---@param R table
---@return boolean
function EC.endPointer(sx, sy, R)
    if not EC.dragging then return false end
    EC.dragging = false
    changed()
    return true
end

--- 当前选中多边形的凸性（用于 UI 提示）。
---@return boolean, boolean
function EC.selectedConvex()
    local poly = EC.selected()
    if not poly then return false, true end
    return true, EC.isConvex(poly.vertices)
end

return EC
