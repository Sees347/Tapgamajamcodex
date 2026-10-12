-- ============================================================================
-- core/tile_render.lua - 世界背景与旧字符地形的视觉兜底
-- 图片层交给 tilesets 绘制；统一碰撞矩形不是外观，不能给装饰图补整格灰底。
-- 所有绘制沿用调用方 R 的坐标空间，不另建 NanoVG 上下文或调整分辨率。
-- ============================================================================
local Config = require "config"
local Tilemap = require "core.tilemap"

local TileRender = {}

---@class TerrainRowsCache
---@field map string
---@field cols integer
---@field rows integer
---@field lines string[]
---@field width integer
---@field height integer
---@type TerrainRowsCache
local rowCache = { map = "", cols = -1, rows = -1, lines = {}, width = 0, height = 0 }
---@type table<string, MapTileCell>
local emptyCells = {}

---@param color number[]
---@param alpha? integer
local function rgba(color, alpha)
    return nvgRGBA(color[1] or 0, color[2] or 0, color[3] or 0, alpha or 255)
end

--- 游戏背景保留实验室视差管道与闪烁顶灯；编辑画布由 EditorRender 独立负责。
---@param vg NVGContextWrapper
---@param R Render
---@param t number
function TileRender.drawBackground(vg, R, t)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, R.screenW, R.screenH)
    local g = nvgLinearGradient(vg, 0, 0, 0, R.screenH,
        rgba(Config.PAL.bgTop), rgba(Config.PAL.bgBottom))
    nvgFillPaint(vg, g)
    nvgFill(vg)

    -- 背景实验室结构（视差 0.3）：立柱与横梁。
    nvgStrokeColor(vg, nvgRGBA(40, 48, 68, 120))
    nvgStrokeWidth(vg, 2)
    local offX = -R.camX * 0.3 * R.ppu
    local spacing = 6 * R.ppu
    local startX = offX % spacing
    for sx = startX - spacing, R.screenW + spacing, spacing do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, 0)
        nvgLineTo(vg, sx, R.screenH)
        nvgStroke(vg)
    end
    -- 远处管道（视差 0.5）。
    nvgStrokeColor(vg, nvgRGBA(52, 62, 84, 100))
    nvgStrokeWidth(vg, 6)
    local pipeY = R.screenH * 0.25 - R.camY * 0.5 * R.ppu
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, pipeY)
    nvgLineTo(vg, R.screenW, pipeY)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, pipeY + 40)
    nvgLineTo(vg, R.screenW, pipeY + 40)
    nvgStroke(vg)

    -- 闪烁顶灯（烧焦氛围）。
    for li = 0, 4 do
        local lx = (li * 9 - R.camX * 0.5) * R.ppu + R.screenW / 2
        if lx > -100 and lx < R.screenW + 100 then
            local flick = math.sin(t * 7 + li * 3) > 0.3 and 1 or 0.15
            local ly = pipeY - 30
            local lg = nvgRadialGradient(vg, lx, ly, 2, 90,
                nvgRGBA(255, 240, 200, math.floor(60 * flick)), nvgRGBA(255, 240, 200, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, lx, ly, 90)
            nvgFillPaint(vg, lg)
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRect(vg, lx - 14, ly - 3, 28, 6)
            nvgFillColor(vg, nvgRGBA(80, 88, 105, 200))
            nvgFill(vg)
        end
    end
end

---@param vg NVGContextWrapper
---@param R Render
---@param x number
---@param y number
---@param width number
---@param height number
local function drawPlatform(vg, R, x, y, width, height)
    local sx, sy = R.w2s(x - width / 2, y + height / 2)
    local w, h = width * R.ppu, height * R.ppu
    if sx + w < -50 or sx > R.screenW + 50 then return end
    -- 主体、顶面亮线、边缘与烧焦斑块沿用旧地形效果。
    nvgBeginPath(vg)
    nvgRect(vg, sx, sy, w, h)
    local g = nvgLinearGradient(vg, sx, sy, sx, sy + h,
        rgba(Config.PAL.platformTop), rgba(Config.PAL.platform))
    nvgFillPaint(vg, g)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, sx, sy, w, math.min(3, h))
    nvgFillColor(vg, nvgRGBA(130, 145, 180, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, sx, sy, w, h)
    nvgStrokeColor(vg, rgba(Config.PAL.platformEdge))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    local seed = math.floor(x * 7 + y * 13)
    if seed % 3 == 0 then
        nvgBeginPath(vg)
        nvgEllipse(vg, sx + w * 0.3, sy + h * 0.3, w * 0.15, h * 0.2)
        nvgFillColor(vg, rgba(Config.PAL.scorch, 120))
        nvgFill(vg)
    end
end

---@param vg NVGContextWrapper
---@param R Render
---@param L Level
local function drawPlatforms(vg, R, L)
    -- Tilemap 的碰撞可以纵向合并，但旧图的逐行顶线/渐变/斑块不可随之改变。
    -- 直接矩形定义的关卡没有此列表，仍沿用它自身的 platformRects。
    local visuals = L.def and L.def.visualPlatformRects --[[@as TerrainCollisionRect[]?]]
    for _, rect in ipairs(visuals or L.platformRects) do
        drawPlatform(vg, R, rect.x, rect.y, rect.w, rect.h)
    end
end

---@param data TilemapData
---@param id string
---@return table<string, MapTileCell>
local function layerCells(data, id)
    local layers = data.visualLayers
    local layer = type(layers) == "table" and layers[id] or nil
    return type(layer) == "table" and type(layer.cells) == "table" and layer.cells or emptyCells
end

--- 旧地图保留合并平台外观；有图片或碰撞覆盖时，外观只从字符源读取。
--- collisionCells=false 只改碰撞，仍保留 #/= 的外观；纯碰撞 true 格不补灰色方块。
--- 三张图片层任一格有视觉来源便跳过旧地形，visible/locked 仅用于编辑器。
---@param vg NVGContextWrapper
---@param R Render
---@param L Level
function TileRender.drawTerrain(vg, R, L)
    local data = L.def and L.def.tilemapData --[[@as TilemapData?]]
    if not data or type(data.map) ~= "string" then
        drawPlatforms(vg, R, L)
        return
    end
    local background = layerCells(data, "background")
    local ground = layerCells(data, "ground")
    local foreground = layerCells(data, "foreground")
    local hasVisuals = next(background) ~= nil or next(ground) ~= nil or next(foreground) ~= nil
    local hasOverrides = type(data.collisionCells) == "table" and next(data.collisionCells) ~= nil
    if not hasVisuals and not hasOverrides then
        drawPlatforms(vg, R, L)
        return
    end
    if data.tile <= 0 or R.ppu <= 0 then return end

    -- 只在字符内容或尺寸改变时拆行；逐帧只扫描视野内的行列。
    if rowCache.map ~= data.map or rowCache.cols ~= data.cols or rowCache.rows ~= data.rows then
        rowCache.map, rowCache.cols, rowCache.rows = data.map, data.cols, data.rows
        rowCache.lines, rowCache.width, rowCache.height = Tilemap.readRows(data.map, data.cols, data.rows)
    end
    local tile = data.tile
    local minX = R.camX - R.screenW / (2 * R.ppu)
    local maxX = R.camX + R.screenW / (2 * R.ppu)
    local maxY = R.camY + R.screenH / (2 * R.ppu)
    local minY = R.camY - R.screenH / (2 * R.ppu)
    local c0 = math.max(1, math.floor((minX - data.originX) / tile))
    local c1 = math.min(rowCache.width, math.ceil((maxX - data.originX) / tile) + 1)
    local r0 = math.max(1, math.floor((data.originY - maxY) / tile))
    local r1 = math.min(rowCache.height, math.ceil((data.originY - minY) / tile) + 1)
    for row = r0, r1 do
        local line = rowCache.lines[row] or ""
        for col = c0, c1 do
            local ch = line:sub(col, col)
            if ch == "#" or ch == "=" then
                local key = col .. ":" .. row
                if not background[key] and not ground[key] and not foreground[key] then
                    drawPlatform(vg, R, data.originX + (col - 0.5) * tile,
                        data.originY - (row - 0.5) * tile, tile, tile)
                end
            end
        end
    end
end

return TileRender
