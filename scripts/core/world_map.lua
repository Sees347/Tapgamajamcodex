-- 普通运行默认加载项目共享地图；个人/旧编辑草稿只能显式选择。
-- 不删除或覆盖旧地图；旧三章只归档，不自动混入当前世界。
local Tilemap = require "core.tilemap"
local ME = require "core.map_editor"
local defaultSource = require "levels.world_src"
local legacySource = require "levels.editor_map_src"

local WorldMap = { id = "world" }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function normalize(source, progressId)
    assert(Tilemap.validSource(source), "世界地图尺寸无效或超限；原数据未覆盖")
    local result = copy(source)
    assert(finite(result.tile) and result.tile > 0, "世界地图 tile 必须为正米数")
    assert(finite(result.originX) and finite(result.originY), "世界地图原点无效")
    local lines, cols, rows = Tilemap.readRows(result.map, result.cols, result.rows)
    result.cols, result.rows = cols, rows
    -- 旧 T 不再产生出口；保存旧原始文件即可恢复归档数据。
    for row, line in ipairs(lines) do lines[row] = line:gsub("T", " ") end
    result.map = table.concat(lines, "\n")
    result.id, result.level = "world", "world"
    result.name, result.subtitle = "涌泉 · 无缝大地图", "持续探索 · 同一世界"
    result.seamless, result.progressId = true, progressId
    result.exits, result.arrival = {}, nil
    result.metadata = type(result.metadata) == "table" and result.metadata or {}
    result.metadata.id, result.metadata.level = "world", "world"
    result.metadata.seamless, result.metadata.progressId = true, progressId
    result.metadata.exits, result.metadata.arrival = {}, nil
    local tile, x, y = result.tile, result.originX, result.originY
    result.bounds = { minX = x, maxX = x + cols * tile, minY = y - rows * tile, maxY = y }
    result.deathY = y - rows * tile - 4
    result.metadata.bounds, result.metadata.deathY = copy(result.bounds), result.deathY
    if result.spawn then
        assert(type(result.spawn) == "table" and finite(result.spawn.x) and finite(result.spawn.y), "世界出生点无效")
    end
    assert(type(result.story or {}) == "table" and type(result.wires or {}) == "table", "世界玩法元数据无效")
    return result
end

local function apply(base, saved)
    local result = copy(base)
    for key, value in pairs(type(saved.metadata) == "table" and saved.metadata or {}) do result[key] = copy(value) end
    for key, value in pairs(saved) do result[key] = copy(value) end
    -- 老沙箱没有显式尺寸时，从实际 map 推导，不继承默认世界的 256×64。
    result.cols, result.rows = saved.cols, saved.rows
    return result
end

--- 只查询存在性；单独封装以便验收使用一致的内存快照，不触碰真实地图。
---@param id string
---@return boolean
function WorldMap.snapshotExists(id)
    return fileSystem:FileExists("mapedit_" .. id .. ".json")
end

--- 试玩与草稿沿用世界规范化，重算缩放/裁图后的边界，不改变原始快照。
---@param source table
---@return table
function WorldMap.prepare(source)
    local metadata = type(source.metadata) == "table" and source.metadata or {}
    return normalize(apply(legacySource, source), source.progressId or metadata.progressId or "world")
end

--- 项目版本的共享地图，绝不被任何用户本地草稿或坏存档遮盖。
---@return table
function WorldMap.sharedSource()
    return normalize(defaultSource, defaultSource.progressId or "world")
end

--- 默认游戏入口统一使用共享版本。查看本地地图必须调用 draftSource。
---@return table
function WorldMap.source()
    return WorldMap.sharedSource()
end

--- 显式读取个人草稿；指定槽不存在/损坏时拒绝，不偷偷换成其它地图。
---@param slot? string
---@return table
---@return string 实际保存槽（与逻辑world ID分离）
function WorldMap.draftSource(slot)
    if slot and slot ~= "world" then
        assert(slot == "world_shared_draft" or slot == "editor_map", "不支持的地图草稿槽")
        local snapshot = ME.peekSandbox(slot)
        assert(snapshot, "所选个人草稿不存在或无法解析，原文件未修改")
        return WorldMap.prepare(snapshot), slot
    end
    local saved = ME.peekSandbox("world")
    if saved then
        return WorldMap.prepare(saved), "world"
    end
    assert(not WorldMap.snapshotExists("world"), "world存档无法解析；请先备份修复，原文件未覆盖")
    local legacy = ME.peekSandbox("editor_map")
    if legacy then
        return normalize(apply(legacySource, legacy), "editor_map"), "editor_map"
    end
    assert(not WorldMap.snapshotExists("editor_map"), "旧编辑存档无法解析；原文件未覆盖")
    error("没有个人旧地图草稿，请加载项目共享地图")
end

return WorldMap
