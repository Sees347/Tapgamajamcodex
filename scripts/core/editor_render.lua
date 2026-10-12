-- ============================================================================
-- core/editor_render.lua - 分层地图、碰撞辅助线与图片笔刷预览
-- 编辑器与游戏共用 tilesets 的图集裁切；网格只在中央画布范围内绘制。
-- ============================================================================
local ME = require "core.map_editor"
local TS = require "core.tilesets"
local Backgrounds = require "core.map_backgrounds"
local EB = require "core.editor_backgrounds"
local EC = require "core.editor_collision"
local EditorUI = require "ui/map_editor"

local EditorRender = {}
local COLORS = {
    ["#"] = { 90, 100, 130 }, ["="] = { 120, 135, 165 },
    ["F"] = { 255, 120, 50 }, ["f"] = { 220, 150, 80 },
    ["C"] = { 150, 210, 245 }, ["W"] = { 90, 180, 255 },
    ["Z"] = { 230, 200, 90 }, ["S"] = { 140, 220, 255 },
    ["P"] = { 150, 150, 165 }, ["D"] = { 120, 130, 155 },
    ["O"] = { 70, 75, 95 }, ["A"] = { 180, 80, 70 },
    ["1"] = { 165, 175, 190 }, ["2"] = { 150, 160, 178 },
    ["y"] = { 120, 100, 90 }, ["s"] = { 140, 120, 150 },
    ["c"] = { 185, 110, 95 }, ["b"] = { 110, 140, 120 },
    ["m"] = { 130, 120, 150 }, ["B"] = { 200, 100, 80 },
    ["$"] = { 250, 220, 160 }, ["Q"] = { 200, 190, 255 },
    ["H"] = { 150, 240, 200 }, ["X"] = { 110, 96, 80 },
    ["T"] = { 180, 120, 255 }, ["t"] = { 120, 200, 255 },
    ["a"] = { 90, 200, 160 }, ["e"] = { 120, 110, 200 },
    ["l"] = { 130, 190, 235 }, ["j"] = { 60, 70, 110 },
    ["r"] = { 150, 140, 175 }, ["n"] = { 170, 150, 120 },
    ["g"] = { 110, 190, 90 }, ["w"] = { 90, 130, 180 },
    ["u"] = { 140, 220, 255 }, ["h"] = { 255, 170, 110 },
    ["o"] = { 150, 220, 250 }, ["i"] = { 220, 200, 130 },
    ["p"] = { 220, 240, 250 },
}

local function solidAt(c, r)
    local key = c .. ":" .. r
    if ME.collisionCells[key] ~= nil then return ME.collisionCells[key] == true end
    local ch = ME.grid[r] and ME.grid[r][c]
    if ch == "#" or ch == "=" then return true end
    for _, id in ipairs({ "background", "ground", "foreground" }) do
        local cell = ME.getVisualCell(id, c, r)
        if cell and cell.collider == "ground" then return true end
    end
    return false
end

--- 绘制手绘碰撞多边形：本体描边 + 选中高亮 + 顶点手柄 + 绘制中的预览。
---@param vg NVGContextWrapper
---@param R table
local function drawCollisionPolygons(vg, R)
    if not ME.active then return end
    local selectedId = EC.selectedId
    for _, poly in ipairs(EC.list()) do
        local verts = poly.vertices
        if #verts >= 2 then
            nvgBeginPath(vg)
            local first = true
            for _, v in ipairs(verts) do
                local x, y = R.w2s(v.x, v.y)
                if first then nvgMoveTo(vg, x, y); first = false else nvgLineTo(vg, x, y) end
            end
            if #verts >= 3 then nvgClosePath(vg) end
            nvgFillColor(vg, nvgRGBA(80, 230, 130, 40))
            nvgFill(vg)
            nvgStrokeColor(vg, poly.id == selectedId and nvgRGBA(120, 255, 160, 255) or nvgRGBA(100, 235, 150, 205))
            nvgStrokeWidth(vg, poly.id == selectedId and 2.5 or 1.5)
            nvgStroke(vg)
        end
    end
    -- 顶点手柄（仅选中多边形）
    local sel = EC.selected()
    if sel then
        for i, v in ipairs(sel.vertices) do
            local x, y = R.w2s(v.x, v.y)
            nvgBeginPath(vg)
            nvgCircle(vg, x, y, i == EC.selectedVertex and 7 or 5)
            nvgFillColor(vg, i == EC.selectedVertex and nvgRGBA(255, 225, 110, 255) or nvgRGBA(120, 255, 160, 255))
            nvgFill(vg)
        end
    end
    -- 绘制中的预览
    if EC.isDrawing() then
        local verts = EC.drawPreview()
        nvgBeginPath(vg)
        local first = true
        for _, v in ipairs(verts) do
            local x, y = R.w2s(v.x, v.y)
            if first then nvgMoveTo(vg, x, y); first = false else nvgLineTo(vg, x, y) end
        end
        nvgStrokeColor(vg, nvgRGBA(255, 225, 110, 230))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        for _, v in ipairs(verts) do
            local x, y = R.w2s(v.x, v.y)
            nvgBeginPath(vg)
            nvgCircle(vg, x, y, 5)
            nvgFillColor(vg, nvgRGBA(255, 225, 110, 255))
            nvgFill(vg)
        end
    end
end

---@param vg NVGContextWrapper
---@param R table
function EditorRender.draw(vg, R)
    if not ME.active or ME.tile <= 0 then return end
    local canvas = EditorUI.getCanvasRect()
    if canvas.w <= 0 or canvas.h <= 0 then return end
    nvgSave(vg)
    nvgIntersectScissor(vg, canvas.x, canvas.y, canvas.w, canvas.h)
    nvgBeginPath(vg)
    nvgRect(vg, canvas.x, canvas.y, canvas.w, canvas.h)
    nvgFillColor(vg, nvgRGBA(35, 40, 50, 255))
    nvgFill(vg)

    -- EB 仅依赖 ME/B；临时移动/等比缩放预览不写回 metadata。
    -- 保留中央画布 intersect scissor，整图位于全部瓦片和网格后方。
    if ME.getLayerState("background").visible then
        Backgrounds.draw(vg, EB.renderImages(), R)
    end

    local tile, px = ME.tile, ME.tile * R.ppu
    local minX = R.camX + (canvas.x - R.screenW / 2) / R.ppu
    local maxX = minX + canvas.w / R.ppu
    local maxY = R.camY - (canvas.y - R.screenH / 2) / R.ppu
    local minY = maxY - canvas.h / R.ppu
    local c0 = math.max(1, math.floor((minX - ME.originX) / tile) + 1)
    local c1 = math.min(ME.cols, math.ceil((maxX - ME.originX) / tile))
    local r0 = math.max(1, math.floor((ME.originY - maxY) / tile) + 1)
    local r1 = math.min(ME.rows, math.ceil((ME.originY - minY) / tile))

    ---@type TilesetMapData
    local mapData = {
        tile = ME.tile, originX = ME.originX, originY = ME.originY,
        cols = ME.cols, rows = ME.rows, editRevision = ME.editRevision,
        visualLayers = { background = ME.visualLayers.background, ground = ME.visualLayers.ground, foreground = ME.visualLayers.foreground },
    }
    for _, id in ipairs({ "background", "ground", "foreground" }) do
        TS.drawLayer(vg, id, mapData, R, true)
    end

    -- 旧字符地形归地形外观层，显示/擦除与图片地面一致；其它字符归玩法层。
    local terrainVisible = ME.getLayerState("ground").visible
    local gameplayVisible = ME.getLayerState("gameplay").visible
    if terrainVisible or gameplayVisible then
        for r = r0, r1 do
            for c = c0, c1 do
                local ch = ME.grid[r] and ME.grid[r][c]
                local color = COLORS[ch]
                local terrain = ch == "#" or ch == "="
                local covered = ME.getVisualCell("ground", c, r)
                    or ME.getVisualCell("background", c, r) or ME.getVisualCell("foreground", c, r)
                local visible = terrain and terrainVisible or (not terrain and gameplayVisible)
                if color and visible and (not terrain or not covered) then
                    local wx, wy = ME.cellToWorld(c, r)
                    local sx, sy = R.w2s(wx - tile / 2, wy + tile / 2)
                    nvgBeginPath(vg)
                    nvgRect(vg, sx + 1, sy + 1, math.max(0, px - 2), math.max(0, px - 2))
                    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], terrain and 175 or 130))
                    nvgFill(vg)
                    if not terrain and px >= 18 then
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, math.min(16, px * 0.55))
                        nvgTextAlign(vg, NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                        nvgText(vg, sx + px / 2, sy + px / 2, ch)
                    end
                end
            end
        end
    end

    if ME.getLayerState("collision").visible then
        nvgBeginPath(vg)
        for r = r0, r1 do
            for c = c0, c1 do
                if solidAt(c, r) then
                    local wx, wy = ME.cellToWorld(c, r)
                    local sx, sy = R.w2s(wx - tile / 2, wy + tile / 2)
                    nvgRect(vg, sx + 1, sy + 1, math.max(0, px - 2), math.max(0, px - 2))
                end
            end
        end
        nvgFillColor(vg, nvgRGBA(80, 230, 130, 38))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 235, 150, 205))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    if px >= 6 then
        nvgBeginPath(vg)
        for c = c0, c1 + 1 do
            local x, y = R.w2s(ME.originX + (c - 1) * tile, ME.originY - (r0 - 1) * tile)
            nvgMoveTo(vg, x, y)
            nvgLineTo(vg, x, y + (r1 - r0 + 1) * px)
        end
        for r = r0, r1 + 1 do
            local x, y = R.w2s(ME.originX + (c0 - 1) * tile, ME.originY - (r - 1) * tile)
            nvgMoveTo(vg, x, y)
            nvgLineTo(vg, x + (c1 - c0 + 1) * px, y)
        end
        nvgStrokeColor(vg, nvgRGBA(140, 160, 190, 55))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
    EB.drawSelection(vg, R)
    drawCollisionPolygons(vg, R)
    local mapX, mapY = R.w2s(ME.originX, ME.originY)
    nvgBeginPath(vg)
    nvgRect(vg, mapX, mapY, ME.cols * px, ME.rows * px)
    nvgStrokeColor(vg, nvgRGBA(140, 185, 235, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    local initial = ME.metadata.initialSpawnCell
    if type(initial) == "table" and require("core.editor_gameplay").initialKey() ~= "" then
        local wx, wy = ME.cellToWorld(initial.col, initial.row)
        local x, y = R.w2s(wx - tile / 2, wy + tile / 2)
        nvgBeginPath(vg)
        nvgRect(vg, x + 2, y + 2, math.max(0, px - 4), math.max(0, px - 4))
        nvgStrokeColor(vg, nvgRGBA(255, 215, 70, 255))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end
    if ME.selectedCell then
        local wx, wy = ME.cellToWorld(ME.selectedCell.col, ME.selectedCell.row)
        local x, y = R.w2s(wx - tile / 2, wy + tile / 2)
        nvgBeginPath(vg)
        nvgRect(vg, x + 1, y + 1, math.max(0, px - 2), math.max(0, px - 2))
        nvgStrokeColor(vg, nvgRGBA(90, 185, 255, 255))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end
    if R.aimSX and EditorUI.isCanvasPoint(R.aimSX, R.aimSY) then
        local wx = R.camX + (R.aimSX - R.screenW / 2) / R.ppu
        local wy = R.camY - (R.aimSY - R.screenH / 2) / R.ppu
        local col, row = ME.worldToCell(wx, wy)
        if col and row then
            local selection = ME.tileSelection
            local size = math.max(1, ME.brushSize)
            local half = math.floor((size - 1) / 2)
            local left, top = col - half, row - half
            local w, h = size, size
            if ME.tool == "rect" and ME.rectPreviewStart and ME.rectPreviewCur then
                local s, e = ME.rectPreviewStart, ME.rectPreviewCur
                left, top = math.min(s[1], e[1]), math.min(s[2], e[2])
                w, h = math.abs(s[1] - e[1]) + 1, math.abs(s[2] - e[2]) + 1
            elseif ME.selectedLayer ~= "collision" and ME.selectedLayer ~= "gameplay" and ME.tool ~= "erase" and ME.tool ~= "select" then
                if size == 1 and (selection.width > 1 or selection.height > 1) then
                    left, top, w, h = col, row, selection.width, selection.height
                end
                if selection.tilesetId ~= "" then
                    for dy = 0, h - 1 do
                        for dx = 0, w - 1 do
                            local c, r = left + dx, top + dy
                            if c >= 1 and c <= ME.cols and r >= 1 and r <= ME.rows then
                                local cellX, cellY = ME.cellToWorld(c, r)
                                local x, y = R.w2s(cellX - tile / 2, cellY + tile / 2)
                                local id = selection.tileId
                                if size == 1 then
                                    id = selection.tileId + (dy % selection.height) * selection.columns + dx % selection.width
                                end
                                TS.drawTile(vg, selection.tilesetId, id, x, y, px, px, 0.5)
                            end
                        end
                    end
                end
            end
            local cellX, cellY = ME.cellToWorld(left, top)
            local x, y = R.w2s(cellX - tile / 2, cellY + tile / 2)
            nvgBeginPath(vg)
            nvgRect(vg, x, y, w * px, h * px)
            nvgStrokeColor(vg, ME.getLayerState(ME.selectedLayer).locked
                and nvgRGBA(245, 105, 105, 220) or nvgRGBA(255, 225, 110, 230))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    end
    nvgRestore(vg)
end

return EditorRender
