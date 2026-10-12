-- 游戏相机的米制边界约束；编辑器不调用，不改变请求视野设置。
local C = {}

---@class CameraBounds
---@field minX number
---@field maxX number
---@field minY number
---@field maxY number

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---@param bounds CameraBounds?
---@return boolean
function C.valid(bounds)
    return type(bounds) == "table" and finite(bounds.minX) and finite(bounds.maxX)
        and finite(bounds.minY) and finite(bounds.maxY)
        and bounds.maxX > bounds.minX and bounds.maxY > bounds.minY
end

--- 左上角原点，行向下；只取完整地图矩形，不取非空瓦片包围盒或旧 bounds 留白。
--- 无 tilemapData 的手工功能测试场仍使用显式 bounds。
---@param level table?
---@return CameraBounds?
function C.fromLevel(level)
    if not level then return nil end
    local data = level.tilemapData
    if type(data) == "table" and finite(data.originX) and finite(data.originY)
        and finite(data.tile) and data.tile > 0
        and finite(data.cols) and data.cols >= 1 and data.cols % 1 == 0
        and finite(data.rows) and data.rows >= 1 and data.rows % 1 == 0 then
        local bounds = {
            minX = data.originX, maxX = data.originX + data.cols * data.tile,
            minY = data.originY - data.rows * data.tile, maxY = data.originY,
        }
        if C.valid(bounds) then return bounds end
    end
    return C.valid(level.bounds) and level.bounds or nil
end

---@param bounds CameraBounds?
---@param requested number
---@param aspect number
---@return number
function C.viewHeight(bounds, requested, aspect)
    local height = finite(requested) and requested > 0 and requested or 12.0
    local ratio = finite(aspect) and aspect > 0 and aspect or 1.0
    if not bounds or not C.valid(bounds) then return height end
    return math.min(height, bounds.maxY - bounds.minY, (bounds.maxX - bounds.minX) / ratio)
end

--- 系统逻辑像素投影；最小化/暂时零尺寸时保留上一有效屏幕，避免除零。
---@param render table
---@param w number
---@param h number
---@param requested number
---@param bounds CameraBounds?
function C.fitScreen(render, w, h, requested, bounds)
    local width = finite(w) and w > 0 and w or render.screenW
    local height = finite(h) and h > 0 and h or render.screenH
    render.screenW, render.screenH = width, height
    render.viewH = C.viewHeight(bounds, requested, width / height)
    render.ppu = height / render.viewH
    render.viewW = width / render.ppu
end

---@param bounds CameraBounds?
---@param x number
---@param y number
---@param width number
---@param height number
---@return number, number
function C.clamp(bounds, x, y, width, height)
    if not bounds or not C.valid(bounds) then return x, y end
    local halfW, halfH = width / 2, height / 2
    local nx = width >= bounds.maxX - bounds.minX and (bounds.minX + bounds.maxX) / 2
        or math.max(bounds.minX + halfW, math.min(bounds.maxX - halfW, x))
    local ny = height >= bounds.maxY - bounds.minY and (bounds.minY + bounds.maxY) / 2
        or math.max(bounds.minY + halfH, math.min(bounds.maxY - halfH, y))
    return nx, ny
end

--- 随机偏移只用于本次绘制，不写回逻辑 cam。真实视觉中心用于投影和可视格裁剪。
--- 贴边只能向内震，fit 轴无震幅；不平移 NanoVG 全屏 scissor/屏幕背景。
---@param bounds CameraBounds?
---@param x number
---@param y number
---@param width number
---@param height number
---@param mag number
---@param scale number
---@return number, number
function C.shakeCenter(bounds, x, y, width, height, mag, scale)
    if not finite(mag) or mag <= 0 or not finite(scale) or scale <= 0
        or not finite(mag * scale) then return x, y end
    local amplitude = mag * scale
    return C.clamp(bounds,
        x + (math.random() - 0.5) * amplitude, y + (math.random() - 0.5) * amplitude, width, height)
end

return C
