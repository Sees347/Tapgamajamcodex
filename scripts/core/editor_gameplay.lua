-- 地图玩法属性：泉眼出生选择、显式机关连接。坐标保持1基，不自动连最近的门。
local ME = require "core.map_editor"
local TM = require "core.tilemap"
local EG = {}

local LABELS = {}
for _, item in ipairs(ME.PALETTE) do LABELS[item.char] = item.label end
LABELS.t = "出生点"

---@param col integer
---@param row integer
---@return string
function EG.key(col, row) return col .. ":" .. row end

function EG.id(col, row)
    return string.format("%s_%d_%d", ME.metadata.progressId or ME.currentLevel or "world", col - 1, row - 1)
end

function EG.select(col, row)
    -- 空格也允许选中：碰撞体调节需要给无玩法标记的格（仅视觉瓦片）改碰撞。
    if not ME.grid[row] or ME.grid[row][col] == nil then return false end
    ME.selectedCell = { col = col, row = row }
    return true
end

function EG.selected()
    local cell = ME.selectedCell
    if not cell or not ME.grid[cell.row] then return nil end
    local char = ME.grid[cell.row][cell.col]
    if not char or char == " " then return nil end
    return { col = cell.col, row = cell.row, char = char, key = EG.key(cell.col, cell.row),
        id = EG.id(cell.col, cell.row), label = LABELS[char] or char }
end

function EG.list(chars)
    local list = {}
    for row, line in ipairs(ME.grid) do
        for col, char in ipairs(line) do
            if char ~= " " and chars:find(char, 1, true) then
                list[#list + 1] = { col = col, row = row, char = char, key = EG.key(col, row),
                    id = EG.id(col, row), label = (LABELS[char] or char) .. "（" .. col .. "," .. row .. "）" }
            end
        end
    end
    return list
end

---@param key string
---@return boolean, string
function EG.setInitial(key)
    local col, row = TM.cellCoords(key, ME.cols, ME.rows)
    if not col or not row then return false, "出生点坐标无效" end
    local char = ME.grid[row][col]
    if char ~= "S" and char ~= "t" then return false, "请选择泉眼或出生点标记" end
    local state = ME.getLayerState("gameplay")
    if state.locked or not state.visible then return false, "请先显示并解锁玩法标记层" end
    ME.metadata.initialSpawnCell = { col = col, row = row }
    local x, y = ME.cellToWorld(col, row)
    ME.metadata.spawn = { x = x, y = y + (char == "S" and 0.8 or 0.4) }
    ME.markDirty()
    print("[地图玩法] 初始出生选择 " .. key)
    return true, "已设初始出生点（" .. col .. "," .. row .. "）；试玩从此处开始"
end

function EG.initialKey()
    local cell = ME.metadata.initialSpawnCell
    if type(cell) ~= "table" then return "" end
    if not TM.validDimensions(cell.col, cell.row) or not ME.grid[cell.row] then return "" end
    local char = ME.grid[cell.row][cell.col]
    return (char == "S" or char == "t") and EG.key(cell.col, cell.row) or ""
end

function EG.properties(key)
    local all = ME.metadata.elementProperties
    return type(all) == "table" and type(all[key]) == "table" and all[key] or {}
end

function EG.setProperty(key, name, value)
    local col, row = TM.cellCoords(key, ME.cols, ME.rows)
    if not col or not row then return false end
    local state = ME.getLayerState("gameplay")
    if state.locked or not state.visible then return false end
    if name ~= "active" and name ~= "needsPower" and name ~= "open" then return false end
    ME.metadata.elementProperties = ME.metadata.elementProperties or {}
    ME.metadata.elementProperties[key] = ME.metadata.elementProperties[key] or {}
    ME.metadata.elementProperties[key][name] = value == true
    ME.markDirty()
    return true
end

function EG.connect(sourceKey, targetKey)
    local sc, sr = TM.cellCoords(sourceKey, ME.cols, ME.rows)
    local tc, tr = TM.cellCoords(targetKey, ME.cols, ME.rows)
    if not sc or not sr or not tc or not tr then return false, "请选择有效连接端点" end
    local source, target = ME.grid[sr][sc], ME.grid[tr][tc]
    if (source ~= "P" and source ~= "O") or (target ~= "D" and target ~= "A") then return false, "仅支持压板/电力接口连接门/报警器" end
    local state = ME.getLayerState("gameplay")
    if state.locked or not state.visible then return false, "请先显示并解锁玩法标记层" end
    local from, to = EG.id(sc, sr), EG.id(tc, tr)
    ME.metadata.wires = ME.metadata.wires or {}
    for _, wire in ipairs(ME.metadata.wires) do
        if wire.from == from and wire.to == to then return false, "该连接已经存在" end
    end
    ME.metadata.wires[#ME.metadata.wires + 1] = { from = from, to = to }
    EG.setProperty(targetKey, "needsPower", true)
    print("[地图玩法] 连接 " .. from .. " -> " .. to)
    return true, "连接已添加；压板需固态踩下，电力接口需装备电鳗并靠近"
end

function EG.disconnect(targetKey)
    local col, row = TM.cellCoords(targetKey, ME.cols, ME.rows)
    if not col or not row then return false end
    local state = ME.getLayerState("gameplay")
    if state.locked or not state.visible then return false end
    local id, wires, changed = EG.id(col, row), {}, false
    for _, wire in ipairs(ME.metadata.wires or {}) do
        if wire.to == id then changed = true else wires[#wires + 1] = wire end
    end
    if changed then ME.metadata.wires = wires; ME.markDirty() end
    return changed
end

-- ============================================================================
-- 碰撞体调节：地形格三态覆盖 + 机关碰撞盒尺寸（米）。
-- 地形只改碰撞不改外观：默认(删覆盖) / 实心(true) / 无碰撞(false)。
-- 机关尺寸写入 elementProperties[key].w/h，运行时按米替换默认盒。
-- ============================================================================

--- 地形碰撞三态；'default' 表示删除覆盖、回落到字符/图片层规则。
---@param col integer
---@param row integer
---@return 'solid'|'none'|'default'
function EG.terrainCollision(col, row)
    local override = ME.collisionCells[EG.key(col, row)]
    if override == true then return "solid" end
    if override == false then return "none" end
    return "default"
end

--- 设置地形碰撞覆盖；mode 取值 solid/none/default。
---@param col integer
---@param row integer
---@param mode string
---@return boolean
function EG.setTerrainCollision(col, row, mode)
    local state = ME.getLayerState("collision")
    if state.locked or not state.visible then return false end
    if not ME.grid[row] or ME.grid[row][col] == nil then return false end
    local key = EG.key(col, row)
    local current = EG.terrainCollision(col, row)
    if mode == "default" then
        if current == "default" then return false end
        ME.collisionCells[key] = nil
    else
        local value = mode == "solid"
        if ME.collisionCells[key] == value then return false end
        ME.collisionCells[key] = value
    end
    ME.markDirty()
    return true
end

--- 机关（火区/水/门等）当前碰撞盒尺寸；未覆盖时回落 LEGEND 默认。
---@param col integer
---@param row integer
---@return number? w
---@return number? h
function EG.collisionBox(col, row)
    local char = ME.grid[row] and ME.grid[row][col]
    local el = char and TM.LEGEND[char]
    if not el or el.type ~= "hazard" then return nil, nil end
    local props = EG.properties(EG.key(col, row))
    local w = type(props.w) == "number" and props.w or el.w or 1
    local h = type(props.h) == "number" and props.h or el.h or 1
    return w, h
end

--- 设置机关碰撞盒尺寸；传 nil 删除覆盖、回落默认。
---@param col integer
---@param row integer
---@param w number|nil
---@param h number|nil
---@return boolean
function EG.setCollisionBox(col, row, w, h)
    local char = ME.grid[row] and ME.grid[row][col]
    local el = char and TM.LEGEND[char]
    if not el or el.type ~= "hazard" then return false end
    local key = EG.key(col, row)
    ME.metadata.elementProperties = ME.metadata.elementProperties or {}
    local props = ME.metadata.elementProperties[key]
    local function apply(name, value)
        if value == nil then
            if props then props[name] = nil end
            return
        end
        props = props or {}
        ME.metadata.elementProperties[key] = props
        props[name] = value
    end
    apply("w", w)
    apply("h", h)
    props = ME.metadata.elementProperties[key]
    if props and next(props) == nil then ME.metadata.elementProperties[key] = nil end
    ME.markDirty()
    return true
end

return EG
