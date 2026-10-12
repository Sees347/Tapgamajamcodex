-- ============================================================================
-- core/map_editor.lua - Unity Tile Palette 式分层编辑器（数据与逻辑）
-- 图片层与字符玩法独立；碰撞只有 ground（整格实体）/decoration（无碰撞）。
-- v2 沙箱保存显式尺寸、三张图片层、碰撞覆盖与原关卡元数据，兼容旧字符地图。
-- ============================================================================

local Tilemap = require "core.tilemap"
local TS = require "core.tilesets"
local Backgrounds = require "core.map_backgrounds"

---@class MapEditor
---@field grid string[][]
---@field visualLayers MapVisualLayers
---@field collisionCells table<string, boolean>
---@field layerStates table<string, MapLayerState>
---@field tileSelection MapTileSelection
---@field metadata table
---@field currentLevel string|nil
---@field selectedCell? {col:integer,row:integer}
local ME = {}

ME.active = false          -- 是否处于编辑模式
---@type string[][]
ME.grid = {}               -- 二维字符网格 grid[row][col]（row/col 从 1 开始）
ME.cols = 0
ME.rows = 0
ME.tile = 1.0              -- 每格米数
ME.originX = 0.0
ME.originY = 0.0
ME.brush = "#"             -- 当前玩法字符（保留旧 #/= 地形）
ME.tool = "brush"          -- brush / erase / rect / select / collision / background
ME.brushSize = 1
---@type integer[]|nil
ME.rectPreviewStart = nil
---@type integer[]|nil
ME.rectPreviewCur = nil
---@type string|nil
ME.currentLevel = nil
ME.layerDefs = {
    { id = "foreground", label = "前景装饰" },
    { id = "ground", label = "地形外观" },
    { id = "background", label = "背景装饰" },
    { id = "collision", label = "碰撞" },
    { id = "gameplay", label = "玩法标记" },
}
ME.selectedLayer = "ground"
---@type MapVisualLayers
ME.visualLayers = {
    background = { cells = {}, visible = true, locked = false },
    ground = { cells = {}, visible = true, locked = false },
    foreground = { cells = {}, visible = true, locked = false },
}
---@type table<string, boolean>
ME.collisionCells = {}
---@type table<string, MapLayerState>
ME.layerStates = {
    collision = { visible = true, locked = false },
    gameplay = { visible = true, locked = false },
}
---@type MapTileSelection
ME.tileSelection = { tilesetId = "", tileId = 1, width = 1, height = 1, columns = 1, collider = "ground" }
ME.syncCollision = true
ME.dirty = false
ME.editRevision = 0
---@type {col:integer,row:integer}?
ME.selectedCell = nil
ME.saveStatus = "未修改"
ME.draftSlot = ""          -- 个人保存槽，不改变逻辑world ID或正式玩家进度
ME.protectDraft = false   -- 从共享源码新开会话，首次写同名草稿前保留原文件
ME.sourceLabel = "项目共享地图"
---@type table
ME.metadata = {}

local VISUAL_IDS = { "background", "ground", "foreground" }
local DATA_KEYS = {
    version = true, level = true, tile = true, originX = true, originY = true,
    cols = true, rows = true, map = true, visualLayers = true, collisionCells = true,
    layerStates = true, metadata = true, tilesets = true,
}

--- 脱离源表的快照；元数据中的表不与源码共享可变引用。
---@param value any
---@param seen table|nil
---@return any
local function copyValue(value, seen)
    if type(value) ~= "table" then return value end
    local visited = seen or {}
    if visited[value] then return visited[value] end
    local result = {}
    visited[value] = result
    for key, item in pairs(value) do result[key] = copyValue(item, visited) end
    return result
end

---@param value number|nil
---@param fallback integer
---@return integer
local function dimension(value, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(0, math.floor(value))
end

---@param cols integer
---@param rows integer
---@return string[][]
local function emptyGrid(cols, rows)
    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do grid[r][c] = " " end
    end
    return grid
end

function ME.markDirty()
    ME.editRevision = ME.editRevision + 1
    ME.dirty = true
    ME.saveStatus = "未保存"
end

--- 状态对象是活动引用：UI 修改 visible/locked 后需显式 markDirty()。
---@param id string
---@return MapLayerState|nil
function ME.getLayerState(id)
    local visual = ME.visualLayers[id] --[[@as MapVisualLayer?]]
    if visual then return visual end
    return ME.layerStates[id]
end

---@param id string
---@return boolean
function ME.setLayer(id)
    if not ME.getLayerState(id) then return false end
    ME.selectedLayer = id
    ME.rectPreviewStart, ME.rectPreviewCur = nil, nil
    return true
end

--- 进入碰撞体调节：解锁并显示碰撞层，选中该层，并切到独立的 collision 工具。
--- 用独立工具值而非 "select"，避免 main 的选取分支把面板切回玩法页；且该工具不写入任何碰撞。
function ME.selectCollisionCell()
    local state = ME.getLayerState("collision")
    if state then state.locked, state.visible = false, true end
    ME.setLayer("collision")
    ME.tool = "collision"
    return true
end

---@param layer string
---@param col integer
---@param row integer
---@return MapTileCell|nil
function ME.getVisualCell(layer, col, row)
    local visual = ME.visualLayers[layer] --[[@as MapVisualLayer?]]
    if not visual then return nil end
    return visual.cells[col .. ":" .. row]
end

---@param setId string
---@param tileId integer
---@param width integer|nil
---@param height integer|nil
---@param columns integer|nil
---@param collider 'ground'|'decoration'|nil
function ME.selectTiles(setId, tileId, width, height, columns, collider)
    local atlasCols = math.max(1, dimension(columns, 1))
    local firstId = math.max(1, dimension(tileId, 1))
    local availableWidth = atlasCols - ((firstId - 1) % atlasCols)
    ME.tileSelection = {
        tilesetId = setId or "", tileId = firstId,
        width = math.min(availableWidth, math.max(1, dimension(width, 1))),
        height = math.max(1, dimension(height, 1)), columns = atlasCols,
        collider = collider == "decoration" and "decoration" or "ground",
    }
end

---@param kind 'ground'|'decoration'
---@return boolean
function ME.setTileCollider(kind)
    if kind ~= "ground" and kind ~= "decoration" then return false end
    ME.tileSelection.collider = kind
    return true
end

-- 可编辑的元素列表（供 UI 面板展示）
---@type {char:string, label:string}[]
ME.PALETTE = {
    { char = "#", label = "地面" },
    { char = "=", label = "平台" },
    { char = "F", label = "火" },
    { char = "f", label = "弱火" },
    { char = "C", label = "低温" },
    { char = "W", label = "凝珠(回3水)" },
    { char = "Z", label = "海绵" },
    { char = "S", label = "存档点(泉眼)" },
    { char = "P", label = "压板" },
    { char = "D", label = "电子门" },
    { char = "O", label = "电力接口" },
    { char = "A", label = "烟雾报警器" },
    { char = "1", label = "机器人01" },
    { char = "2", label = "机器人02" },
    { char = "y", label = "飞蝇" },
    { char = "s", label = "喷孢菌" },
    { char = "c", label = "裂钳蟹" },
    { char = "b", label = "趋光菌兽" },
    { char = "m", label = "门帝克3型" },
    { char = "B", label = "BOSS冰火人" },
    { char = "$", label = "贝壳" },
    { char = "Q", label = "破碎泉心" },
    { char = "H", label = "共生碎片" },
    { char = "X", label = "可破坏箱" },
    -- 章节传送
    { char = "T", label = "传送门(终点)" },
    { char = "t", label = "传送点(落点)" },
    -- 水生生物
    { char = "a", label = "射水鱼" },
    { char = "e", label = "电鳗" },
    { char = "l", label = "飞鱼" },
    { char = "j", label = "鮟鱇鱼" },
    { char = "r", label = "鳐鱼" },
    { char = "n", label = "藤壶" },
    { char = "g", label = "青蛙" },
    { char = "w", label = "剑鱼" },
    -- 探索奖励
    { char = "u", label = "凝水坠饰" },
    { char = "h", label = "耐热结晶" },
    { char = "o", label = "隔冷壳" },
    { char = "i", label = "弹壳碎片" },
    { char = "p", label = "水汽护膜" },
}

--- 初始化/清空所有内容（默认全空），保留世界坐标、元数据和层显示/锁定状态。
---@param cols integer
---@param rows integer
---@return boolean changed
function ME.initGrid(cols, rows)
    if not Tilemap.validDimensions(cols, rows) then
        print("[MapEditor] 尺寸无效或超限，当前地图未修改")
        return false
    end
    local width, height = dimension(cols, 0), dimension(rows, 0)
    local changed = width ~= ME.cols or height ~= ME.rows or next(ME.collisionCells) ~= nil
    for _, line in ipairs(ME.grid) do
        for _, ch in ipairs(line) do if ch ~= " " then changed = true end end
    end
    for _, id in ipairs(VISUAL_IDS) do
        if next(ME.visualLayers[id].cells) ~= nil then changed = true end
        ME.visualLayers[id].cells = {}
    end
    if type(ME.metadata.backgroundImages) == "table" and #ME.metadata.backgroundImages > 0 then
        ME.metadata.backgroundImages = {}
        changed = true
    end
    ME.cols, ME.rows = width, height
    ME.grid = emptyGrid(width, height)
    ME.collisionCells = {}
    ME.rectPreviewStart, ME.rectPreviewCur = nil, nil
    if changed then ME.markDirty() end
    return changed
end

--- 载入图片/碰撞层；旧格式没有这些字段时创建空层，尺寸以当前网格为准。
---@param data table
function ME.loadVisualData(data)
    local layers, collision, states = Tilemap.normalizeLayers(data or {}, ME.cols, ME.rows)
    ME.visualLayers, ME.collisionCells, ME.layerStates = layers, collision, states
end

--- 加载完整源数据（v2 或旧 SRC）。顶层元数据优先于 metadata 子表。
---@param src table
---@return boolean
function ME.loadSource(src)
    if type(src) ~= "table" or type(src.map) ~= "string" then
        print("[MapEditor] 地图载入失败：需要包含 map 字符串的源表")
        return false
    end
    if not Tilemap.validSource(src) then
        print("[MapEditor] 地图尺寸无效或超限，原数据未修改")
        return false
    end
    local sourceMetadata = type(src.metadata) == "table" and src.metadata or {}
    local images = src.backgroundImages
    if images == nil then images = sourceMetadata.backgroundImages end
    if images ~= nil then
        local valid, err = Backgrounds.validate(images)
        if not valid then print("[地图背景] 载入失败，原地图未修改：" .. tostring(err)); return false end
    end
    local incomingTilesets = src.tilesets
    if incomingTilesets == nil then incomingTilesets = sourceMetadata.tilesets end
    if incomingTilesets ~= nil then
        local loaded, err = TS.loadDefinitions(incomingTilesets)
        if not loaded then print("[MapEditor] 地图瓦片集配置载入失败（保留当前有效配置）：" .. tostring(err)) end
    end
    local lines, cols, rows = Tilemap.readRows(src.map, src.cols, src.rows)
    ME.cols, ME.rows = cols, rows
    ME.grid = emptyGrid(cols, rows)
    for r, line in ipairs(lines) do
        for c = 1, cols do ME.grid[r][c] = line:sub(c, c) end
    end
    ME.tile = (type(src.tile) == "number" and src.tile > 0 and src.tile < math.huge) and src.tile or 1.0
    ME.originX = src.originX or 0.0
    ME.originY = src.originY or 0.0
    ME.currentLevel = src.level or src.id or ME.currentLevel
    ME.metadata = copyValue(sourceMetadata)
    ME.metadata.tilesets = nil -- 旧嵌套注册表提升为 captureData.tilesets，避免重复/过期配置。
    for key, value in pairs(src) do
        if not DATA_KEYS[key] then ME.metadata[key] = copyValue(value) end
    end
    ME.loadVisualData(src)
    ME.rectPreviewStart, ME.rectPreviewCur = nil, nil
    ME.selectedCell = nil
    ME.editRevision = ME.editRevision + 1
    ME.dirty, ME.saveStatus = false, "未修改"
    print(string.format("[MapEditor] 已载入地图 %s：%d × %d，保留分层与玩法元数据",
        tostring(ME.currentLevel or "未命名"), cols, rows))
    return true
end

--- 旧接口继续可用；可选显式尺寸可保留首尾空行/空白地图。
---@param mapStr string
---@param cols integer|nil
---@param rows integer|nil
---@return boolean
function ME.loadFromString(mapStr, cols, rows)
    return ME.loadSource({
        map = mapStr, cols = cols, rows = rows, level = ME.currentLevel,
        tile = ME.tile, originX = ME.originX, originY = ME.originY, metadata = ME.metadata,
    })
end

--- 世界坐标 → 网格坐标（1 基）。返回 nil 表示超出网格。
---@param wx number
---@param wy number
---@return integer|nil col, integer|nil row
function ME.worldToCell(wx, wy)
    local col = math.floor((wx - ME.originX) / ME.tile) + 1
    local row = math.floor((ME.originY - wy) / ME.tile) + 1
    if col < 1 or col > ME.cols or row < 1 or row > ME.rows then return nil, nil end
    return col, row
end

--- 网格坐标 → 世界坐标（格子中心）
---@param col integer
---@param row integer
---@return number wx, number wy
function ME.cellToWorld(col, row)
    return ME.originX + (col - 0.5) * ME.tile,
           ME.originY - (row - 0.5) * ME.tile
end

---@param col integer
---@param row integer
---@param ch string
---@return boolean
local function writeCharacter(col, row, ch)
    if col < 1 or col > ME.cols or row < 1 or row > ME.rows then return false end
    local value = (ch or " "):sub(1, 1)
    if value == "" then value = " " end
    if ME.grid[row][col] == value then return false end
    -- 保留失效的出生选择供界面提示重选，不能退回过期spawn坐标悄悄测试。
    if type(ME.metadata.elementProperties) == "table" then ME.metadata.elementProperties[col .. ":" .. row] = nil end
    local id = string.format("%s_%d_%d", ME.metadata.progressId or ME.currentLevel or "world", col - 1, row - 1)
    if type(ME.metadata.wires) == "table" then
        local wires = {}
        for _, wire in ipairs(ME.metadata.wires) do
            if wire.from ~= id and wire.to ~= id then wires[#wires + 1] = wire end
        end
        ME.metadata.wires = wires
    end
    if value == "t" and ME.currentLevel == "world" then
        -- 世界只有一个默认出生标记；落笔时同步元数据，退出试玩立即使用新出生点。
        for _, line in ipairs(ME.grid) do
            for c, previous in ipairs(line) do if previous == "t" then line[c] = " " end end
        end
        local x, y = ME.cellToWorld(col, row)
        ME.metadata.spawn = { x = x, y = y + 0.4 }
        ME.metadata.initialSpawnCell = { col = col, row = row }
    end
    ME.grid[row][col] = value
    return true
end

--- 保留旧公共接口的字符语义；新增分层绘制应调用 applyBrush/applyRect。
---@param col integer
---@param row integer
---@return boolean
function ME.paint(col, row)
    return ME.paintArea(col, row, ME.tool == "erase" and " " or ME.brush, 1)
end

---@param col integer
---@param row integer
---@param ch string
---@param size integer|nil
---@return boolean
function ME.paintArea(col, row, ch, size)
    if ME.layerStates.gameplay.locked or not ME.layerStates.gameplay.visible then return false end
    local side = math.max(1, dimension(size, 1))
    local half = math.floor((side - 1) / 2)
    local changed = false
    for r = math.max(1, row - half), math.min(ME.rows, row - half + side - 1) do
        for c = math.max(1, col - half), math.min(ME.cols, col - half + side - 1) do
            if writeCharacter(c, r, ch) then changed = true end
        end
    end
    if changed then ME.markDirty() end
    return changed
end

---@param c0 integer
---@param r0 integer
---@param c1 integer
---@param r1 integer
---@param ch string
---@return boolean
function ME.fillRect(c0, r0, c1, r1, ch)
    if ME.layerStates.gameplay.locked or not ME.layerStates.gameplay.visible then return false end
    local changed = false
    for r = math.max(1, math.min(r0, r1)), math.min(ME.rows, math.max(r0, r1)) do
        for c = math.max(1, math.min(c0, c1)), math.min(ME.cols, math.max(c0, c1)) do
            if writeCharacter(c, r, ch) then changed = true end
        end
    end
    if changed then ME.markDirty() end
    return changed
end

--- 写当前层的矩形；pattern=false 表示大画笔单格重复，true 表示组合图案平铺。
---@param c0 integer
---@param r0 integer
---@param c1 integer
---@param r1 integer
---@param erase boolean
---@param pattern boolean
---@return boolean
local function applyRegion(c0, r0, c1, r1, erase, pattern)
    local state = ME.getLayerState(ME.selectedLayer)
    if not state or state.locked or not state.visible then return false end
    local layer = ME.visualLayers[ME.selectedLayer] --[[@as MapVisualLayer?]]
    local selection = ME.tileSelection
    if layer and not erase and selection.tilesetId == "" then return false end
    local left, top = math.min(c0, c1), math.min(r0, r1)
    local right, bottom = math.max(c0, c1), math.max(r0, r1)
    local patternW = math.max(1, selection.width)
    local patternH = math.max(1, selection.height)
    local changed = false
    for r = math.max(1, top), math.min(ME.rows, bottom) do
        for c = math.max(1, left), math.min(ME.cols, right) do
            local key = c .. ":" .. r
            if layer then
                local old = layer.cells[key]
                if erase then
                    -- 旧 #/= 与图片瓦片都归地形外观层；同时移除，避免图片擦掉后旧灰块重现。
                    -- 只删当前层来源；独立碰撞覆盖、其它图片层和非地形玩法保持不变。
                    if old then layer.cells[key] = nil; changed = true end
                    if ME.selectedLayer == "ground" then
                        local ch = ME.grid[r][c]
                        if ch == "#" or ch == "=" then
                            ME.grid[r][c] = " "
                            changed = true
                        end
                    end
                else
                    local dx = pattern and ((c - left) % patternW) or 0
                    local dy = pattern and ((r - top) % patternH) or 0
                    local tileId = selection.tileId + dx + dy * selection.columns
                    local collider = ME.syncCollision and selection.collider or "decoration"
                    if not old or old.tilesetId ~= selection.tilesetId or old.tileId ~= tileId
                        or old.collider ~= collider then
                        layer.cells[key] = { tilesetId = selection.tilesetId, tileId = tileId, collider = collider }
                        changed = true
                    end
                end
            elseif ME.selectedLayer == "collision" then
                local value = not erase
                -- false 是显式擦除覆盖，不能用 nil 或真假判断代替。
                if ME.collisionCells[key] ~= value then ME.collisionCells[key] = value; changed = true end
            elseif ME.selectedLayer == "gameplay" then
                if writeCharacter(c, r, erase and " " or ME.brush) then changed = true end
            end
        end
    end
    if changed then ME.markDirty() end
    return changed
end

--- 单格画笔：组合瓦片以鼠标格为左上角；大画笔以鼠标格为中心重复首个瓦片。
--- 橡皮始终仅按 brushSize 范围，不受上次组合选择宽高影响。
--- erase=nil 沿用 tool；false 可以显式绘制，true 只擦当前选中层。
---@param col integer
---@param row integer
---@param erase boolean|nil
---@return boolean changed
function ME.applyBrush(col, row, erase)
    if ME.tool == "select" and erase ~= true then return false end
    local remove = erase == true or (erase == nil and ME.tool == "erase")
    local size = math.max(1, dimension(ME.brushSize, 1))
    if size > 1 then
        local half = math.floor((size - 1) / 2)
        return applyRegion(col - half, row - half, col - half + size - 1, row - half + size - 1, remove, false)
    end
    if not remove and ME.visualLayers[ME.selectedLayer] then
        return applyRegion(col, row, col + ME.tileSelection.width - 1, row + ME.tileSelection.height - 1, false, true)
    end
    return applyRegion(col, row, col, row, remove, false)
end

--- 含端点矩形；图案从矩形左上角开始平铺，裁剪时不改变图案相位。
---@param c0 integer
---@param r0 integer
---@param c1 integer
---@param r1 integer
---@param erase boolean|nil
---@return boolean changed
function ME.applyRect(c0, r0, c1, r1, erase)
    local remove = erase == true or (erase == nil and ME.tool == "erase")
    return applyRegion(c0, r0, c1, r1, remove, true)
end

--- 导出为字符地图字符串（可直接粘进 levels/*.lua 的 map = [[...]]）
---@return string
function ME.exportString()
    local lines = {}
    for r = 1, ME.rows do
        lines[#lines + 1] = table.concat(ME.grid[r] or {})
    end
    return table.concat(lines, "\n")
end

--- 完整 v2 快照，可用于沙箱、试玩和导出；所有表均与编辑器状态脱离。
---@return table
function ME.captureData()
    return {
        version = 2, level = ME.currentLevel,
        tile = ME.tile, originX = ME.originX, originY = ME.originY,
        cols = ME.cols, rows = ME.rows, map = ME.exportString(),
        visualLayers = copyValue(ME.visualLayers),
        collisionCells = copyValue(ME.collisionCells),
        layerStates = copyValue(ME.layerStates),
        metadata = copyValue(ME.metadata),
        tilesets = TS.exportDefinitions(),
    }
end

--- 数据型 Lua 序列化（含 false、稀疏表、中文键和换行）；禁止执行元数据字符串。
---@param value any
---@param depth integer
---@param seen table
---@return string
local function serializeLua(value, depth, seen)
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "string" then return string.format("%q", value) end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge, "导出元数据包含非法数值")
        return tostring(value)
    end
    assert(kind == "table", "导出元数据只支持数据型值：" .. kind)
    assert(not seen[value], "导出元数据不能包含循环表")
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        assert(type(key) == "string" or type(key) == "number" or type(key) == "boolean", "导出表键类型不支持")
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
        return type(a) .. tostring(a) < type(b) .. tostring(b)
    end)
    local lines = { "{" }
    local indent = string.rep("    ", depth + 1)
    for _, key in ipairs(keys) do
        lines[#lines + 1] = indent .. "[" .. serializeLua(key, depth + 1, seen) .. "] = "
            .. serializeLua(value[key], depth + 1, seen) .. ","
    end
    lines[#lines + 1] = string.rep("    ", depth) .. "}"
    seen[value] = nil
    return table.concat(lines, "\n")
end

--- 导出完整新地图和原关卡元数据，不再生成硬编码出生点/主题。
---@param id string
---@param name string
---@return string
function ME.exportLevelFile(id, name)
    local data = ME.captureData()
    for key, value in pairs(ME.metadata) do
        if not DATA_KEYS[key] then data[key] = copyValue(value) end
    end
    data.id = id or ME.currentLevel or "editor_map"
    data.level = data.id
    data.name = name or ME.metadata.name or "未命名地图"
    data.metadata.id, data.metadata.name = data.id, data.name
    return table.concat({
        "-- 由游戏内分层地图编辑器导出（v2，含玩法元数据）",
        "-- 保存到 levels/*_src.lua；对应关卡包装文件负责 Tilemap.parse(SRC)。", "",
        "local SRC = " .. serializeLua(data, 0, {}), "",
        "return SRC",
    }, "\n")
end

--- 进入/退出编辑模式
---@param on boolean
function ME.setActive(on)
    ME.active = on
end

-- ===================== 沙箱持久化（防止编辑丢失） =====================
-- 编辑器改动自动存到所选个人草稿槽；默认启动只读取项目共享源码。
-- 注意：源码文件 scripts/ 只读，无法直接改写；要固化进版本需用「导出」复制完整JSON/Lua SRC。

--- 沙箱存档路径（按关卡区分）
---@param levelId string
---@return string
local function savePath(levelId)
    return "mapedit_" .. (levelId or "unknown") .. ".json"
end

--- File.WriteString 返回 boolean；编码/打开/写入失败都不能假装已保存。
---@param path string
---@param data table
---@return boolean
local function writeJson(path, data)
    local encoded, content = pcall(cjson.encode, data)
    if not encoded then
        print("[MapEditor] 存档编码失败：" .. tostring(content))
        return false
    end
    ---@type File|nil
    local file = nil
    local ok, written = pcall(function()
        file = File(path, FILE_WRITE)
        if not file or not file:IsOpen() then return false end
        local success = file:WriteString(content)
        if success then file:Flush() end
        return success == true
    end)
    if file then pcall(function() file:Dispose() end) end
    if not ok or not written then
        print("[MapEditor] 沙箱写入失败（可重试）：" .. path .. (ok and "" or " / " .. tostring(written)))
        return false
    end
    return true
end

---@param path string
---@return table|nil
local function readJson(path)
    ---@type File|nil
    local file = nil
    local ok, content = pcall(function()
        if not fileSystem:FileExists(path) then return nil end
        file = File(path, FILE_READ)
        if not file or not file:IsOpen() then return nil end
        return file:ReadString()
    end)
    if file then pcall(function() file:Dispose() end) end
    if not ok or type(content) ~= "string" then return nil end
    local decoded, data = pcall(cjson.decode, content)
    if not decoded or type(data) ~= "table" then
        print("[MapEditor] 沙箱存档解析失败：" .. path)
        return nil
    end
    return data
end

--- 新开共享编辑会话不得覆盖未恢复的旧草稿；原字节复制成功才允许写原槽。
local function protectExistingDraft(path)
    if not fileSystem:FileExists(path) then return true end
    for index = 1, 10000 do
        local backup = path .. ".backup_" .. index
        if not fileSystem:FileExists(backup) then
            if not fileSystem:Copy(path, backup) or not fileSystem:FileExists(backup) then
                print("[地图草稿] 备份失败，原草稿未覆盖：" .. path)
                return false
            end
            print("[地图草稿] 已保留原草稿副本：" .. backup)
            return true
        end
    end
    print("[地图草稿] 备份槽已满，拒绝覆盖原草稿")
    return false
end

--- 保存成功才清 dirty；源码浏览未修改不写草稿，失败保留完整内存地图。
---@return boolean
function ME.saveToSandbox()
    if ME.protectDraft and not ME.dirty then return true end
    local slot = ME.currentLevel == "world" and ME.draftSlot ~= "" and ME.draftSlot or ME.currentLevel
    local path = slot and savePath(slot) or ""
    local protected = not ME.protectDraft or (path ~= "" and protectExistingDraft(path))
    if not slot or not protected or not writeJson(path, ME.captureData()) then
        ME.dirty = true
        ME.saveStatus = "保存失败（可重试）"
        return false
    end
    ME.protectDraft = false
    ME.dirty = false
    ME.saveStatus = "已保存（个人草稿）"
    return true
end

--- 优先保留已载入同关卡的 SRC 元数据，旧沙箱没有 metadata 也不丢玩法配置。
---@param levelId string
---@return boolean
function ME.loadFromSandbox(levelId)
    local data = ME.peekSandbox(levelId)
    if not data then return false end
    local inherited = ME.currentLevel == levelId and copyValue(ME.metadata) or {}
    if type(data.metadata) == "table" then
        for key, value in pairs(data.metadata) do inherited[key] = copyValue(value) end
    end
    local source = copyValue(data)
    source.level = levelId
    source.metadata = inherited
    source.tile = data.tile or ME.tile
    source.originX = data.originX or ME.originX
    source.originY = data.originY or ME.originY
    if not ME.loadSource(source) then return false end
    ME.draftSlot, ME.protectDraft, ME.sourceLabel = levelId, false, "个人地图草稿"
    ME.saveStatus = "已保存（个人草稿）"
    print("[MapEditor] 已加载沙箱分层地图：" .. levelId)
    return true
end

--- 只读快照，不污染编辑器；返回完整 v2 数据，旧存档仍可读取。
---@param levelId string
---@return table|nil
function ME.peekSandbox(levelId)
    local data = readJson(savePath(levelId))
    if not data or type(data.map) ~= "string" then return nil end
    return data
end

--- 删除某关卡的沙箱编辑内容（回退到源码地图）
---@param levelId string
function ME.clearSandbox(levelId)
    local path = savePath(levelId)
    if fileSystem:FileExists(path) then
        fileSystem:Delete(path)
    end
end

-- ===================== 自定义章节（新建章节） =====================
-- scripts/ 只读，无法新增 .lua 文件；新建的章节全部存放在沙箱：
--   mapedit_chapters.json  —— 章节注册表（id/name 列表）
--   mapedit_<id>.json      —— 该章节的地图数据（与编辑器自动存档同格式）

local CHAPTERS_PATH = "mapedit_chapters.json"

--- 读取自定义章节注册表（数组：{ id, name }）
---@return {id:string, name:string}[]
function ME.getCustomChapters()
    local data = readJson(CHAPTERS_PATH)
    if not data or type(data.chapters) ~= "table" then return {} end
    return data.chapters
end

---@param list {id:string, name:string}[]
---@return boolean
local function saveCustomChapters(list)
    return writeJson(CHAPTERS_PATH, { chapters = list })
end

--- 生成下一个可用的章节 id（lab04、lab05……），避开内置与已注册章节。
---@return string
function ME.nextChapterId()
    local maxN = 3   -- 内置章节到 lab03
    local list = ME.getCustomChapters()
    for _, c in ipairs(list) do
        local n = tonumber(tostring(c.id):match("^lab(%d+)$"))
        if n and n > maxN then maxN = n end
    end
    return string.format("lab%02d", maxN + 1)
end

--- 新建章节：生成一张空白地图（底部一整条地面 + 一个传送点），注册并返回 id。
--- 之后用 ME.loadFromSandbox(id) 载入编辑，或直接进游戏游玩。
---@param name string|nil 章节名
---@param cols integer|nil 宽（默认 60）
---@param rows integer|nil 高（默认 16）
---@return string id 新章节 id
function ME.createChapter(name, cols, rows)
    local width = math.max(1, dimension(cols, 60))
    local height = math.max(6, dimension(rows, 16))
    local id = ME.nextChapterId()
    local chapterName = (name and name ~= "" and name) or ("新章节 " .. id)
    local grid = emptyGrid(width, height)
    for c = 1, width do grid[height][c] = "#" end
    local arrivalCol = math.min(2, width)
    grid[height - 1][arrivalCol] = "t"
    local lines = {}
    for r = 1, height do lines[r] = table.concat(grid[r] or {}) end
    ME.loadSource({
        id = id, name = chapterName, subtitle = "编辑器新建章节", theme = "lab",
        map = table.concat(lines, "\n"), cols = width, rows = height,
        tile = 1.0, originX = 0.0, originY = height + 2,
        spawn = { x = arrivalCol - 0.5, y = 3.9 },
        startForm = "liquid", story = {}, exits = {}, wires = {},
    })
    ME.markDirty()
    ME.centerCamera()
    local saved = ME.saveToSandbox()
    local list = ME.getCustomChapters()
    table.insert(list, { id = id, name = chapterName })
    local registered = saveCustomChapters(list)
    if not registered then
        ME.dirty = true
        ME.saveStatus = "章节注册失败（可重试）"
        print("[MapEditor] 章节注册失败，当前地图仍保留在内存：" .. id)
    end
    print(string.format("[MapEditor] 新建章节：%s（%d × %d），地图保存=%s，注册=%s",
        id, width, height, tostring(saved), tostring(registered)))
    return id
end

-- ===================== 自由相机（编辑模式下平移视角） =====================
ME.camX = 0.0
ME.camY = 0.0
ME.camSpeed = 12.0        -- 键盘平移速度（米/秒）
-- 缩放：视野高度（米）。越小 → 放得越大。滚轮调整。
ME.viewH = 20.0
ME.viewHMin = 4.0         -- 最大放大
ME.viewHMax = 80.0        -- 最大缩小
ME.zoomStep = 1.15        -- 每格滚轮的缩放倍率

--- 滚轮缩放。wheel > 0 放大（视野变小），< 0 缩小。
---@param wheel number
function ME.zoom(wheel)
    if wheel == 0 then return end
    if wheel > 0 then
        ME.viewH = math.max(ME.viewHMin, ME.viewH / ME.zoomStep)
    else
        ME.viewH = math.min(ME.viewHMax, ME.viewH * ME.zoomStep)
    end
end

--- 编辑模式下每帧更新相机：键盘 WASD/方向键平移 + 可选鼠标拖拽
---@param dt number
---@param input table {left,right,up,down} 布尔
---@param mouseDX number 鼠标拖拽位移（屏幕像素，0 表示无拖拽）
---@param mouseDY number
---@param ppu number 每米像素数
function ME.updateCamera(dt, input, mouseDX, mouseDY, ppu)
    local dx, dy = 0, 0
    if input.left then dx = dx - 1 end
    if input.right then dx = dx + 1 end
    if input.up then dy = dy + 1 end
    if input.down then dy = dy - 1 end
    ME.camX = ME.camX + dx * ME.camSpeed * dt
    ME.camY = ME.camY + dy * ME.camSpeed * dt
    -- 鼠标拖拽平移（屏幕像素 → 世界米，方向相反）
    if mouseDX ~= 0 or mouseDY ~= 0 then
        ME.camX = ME.camX - mouseDX / ppu
        ME.camY = ME.camY + mouseDY / ppu
    end
end

--- 把相机对准地图中心（新建/载入地图后调用）
function ME.centerCamera()
    ME.camX = ME.originX + ME.cols * ME.tile / 2
    ME.camY = ME.originY - ME.rows * ME.tile / 2
end

--- 新建指定尺寸的空白画布：清所有层内容，保留当前关卡玩法元数据和世界尺寸。
---@param cols integer
---@param rows integer
---@return boolean changed
function ME.newMap(cols, rows)
    local changed = ME.initGrid(cols, rows)
    ME.centerCamera()
    return changed
end

--- 清空地图但不裁掉空白尺寸；有 id 时只清对应层，遵守该层 locked。
---@param layerId string|nil nil = 清所有层
---@return boolean changed
function ME.clear(layerId)
    if not layerId then return ME.initGrid(ME.cols, ME.rows) end
    local state = ME.getLayerState(layerId)
    if not state or state.locked then return false end
    local changed = false
    local visual = ME.visualLayers[layerId] --[[@as MapVisualLayer?]]
    if visual then
        changed = next(visual.cells) ~= nil
        visual.cells = {}
        if layerId == "background" and type(ME.metadata.backgroundImages) == "table" and #ME.metadata.backgroundImages > 0 then
            ME.metadata.backgroundImages = {}
            changed = true
        end
    elseif layerId == "collision" then
        -- 清碰撞层意为禁用全部网格碰撞，与 collision 橡皮一致。
        for r = 1, ME.rows do
            for c = 1, ME.cols do
                local key = c .. ":" .. r
                if ME.collisionCells[key] ~= false then ME.collisionCells[key] = false; changed = true end
            end
        end
    elseif layerId == "gameplay" then
        return ME.fillRect(1, 1, ME.cols, ME.rows, " ")
    end
    if changed then ME.markDirty() end
    return changed
end

--- 同步调整字符网格、三张图片层和碰撞覆盖（包括 false）；新区域全空。
---@param cols integer
---@param rows integer
---@return boolean changed
function ME.resize(cols, rows)
    if not Tilemap.validDimensions(cols, rows) then
        print("[MapEditor] 尺寸无效或超限，当前地图未修改")
        return false
    end
    local width, height = dimension(cols, ME.cols), dimension(rows, ME.rows)
    if width == ME.cols and height == ME.rows then return false end
    local grid = emptyGrid(width, height)
    for r = 1, math.min(height, ME.rows) do
        for c = 1, math.min(width, ME.cols) do grid[r][c] = ME.grid[r][c] end
    end
    local layers, collision, states = Tilemap.normalizeLayers(ME, width, height)
    ME.cols, ME.rows, ME.grid = width, height, grid
    ME.visualLayers, ME.collisionCells, ME.layerStates = layers, collision, states
    ME.rectPreviewStart, ME.rectPreviewCur = nil, nil
    ME.markDirty()
    ME.centerCamera()
    print(string.format("[MapEditor] 地图尺寸已调整为 %d × %d，分层同步裁剪", width, height))
    return true
end

return ME
