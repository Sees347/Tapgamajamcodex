-- ============================================================================
-- core/tilesets.lua - Tile Palette 的图集注册、下载、切片与绘制
-- 基于二维脚手架的初始化/更新/释放范式；不创建场景、字体或 NanoVG 上下文。
-- 调用方在自己的 NanoVGRender 帧内绘制，并提供同一坐标空间的尺寸和投影。
-- 世界 vg 与 UI.vg 的图片句柄分别缓存；必须先 TS.shutdown，再销毁这些上下文。
-- ============================================================================

local sourceDefinitions = require "data.tilesets"
local TerrainTiles = require "core.terrain_tiles"

---@class MapTilesetInput
---@field id? string
---@field name? string
---@field path string 已构建的本地资源路径，不是工作机文件名
---@field cellWidth integer
---@field cellHeight integer
---@field margin? integer
---@field spacing? integer
---@field collider? 'ground'|'decoration'

---@class TilesetImage
---@field handle integer
---@field width integer
---@field height integer
---@field error? string

---@class TilesetContext
---@field vg NVGContextWrapper
---@field alive boolean
---@field images table<string, TilesetImage>

---@class TilesetResource
---@field path string
---@field downloaded boolean
---@field busy boolean
---@field group? integer
---@field attempts integer
---@field retryDelay number
---@field width integer
---@field height integer
---@field error? string

---@class TilesetProjection
---@field camX number
---@field camY number
---@field screenW number 当前绘制坐标空间的宽，不在本模块换算 DPR
---@field screenH number
---@field ppu number 当前坐标空间的每米像素数

---@class VisualMapCell
---@field tilesetId string
---@field tileId integer 一基固定编号
---@field collider 'ground'|'decoration'

---@class VisualMapLayer
---@field cells table<string, VisualMapCell> 键为一基 col:row
---@field visible? boolean 仅编辑辅助，游戏绘制忽略
---@field locked? boolean 仅影响编辑，不影响绘制

---@class TilesetMapData
---@field tile number 每格米数
---@field originX number 左上角世界坐标
---@field originY number
---@field cols integer
---@field rows integer
---@field visualLayers MapVisualLayers
---@field editRevision? integer 编辑修改后失效跨格绘制缓存

local TS = {}
TS.lastLayerStats = {} ---@type table<string, { cells: integer, fills: integer, macroFills: integer }>
local RESOURCE_ROOT = "image/地图/tiles/"
local WALL_FILL_PATH = "image/地图/tiles/industrial_wall_fill.png"
local SAVE_PATH = "tilesets.json"
local MAX_DEFINITIONS = 256
local MAX_SLICE_VALUE = 65536
local MAX_ATTEMPTS = 3
local active = false
local generation = 0
local changeRevision = 0
---@type string?
local lastError = nil
---@type NVGContextWrapper?
local defaultContext = nil
---@type MapTilesetDefinition[]
local definitions = {}
---@type table<string, MapTilesetDefinition>
local byId = {}
---@type table<string, MapTilesetInput>
local overrides = {}
---@type table<string, TilesetResource>
local resources = {}
---@type table<NVGContextWrapper, TilesetContext>
local contexts = {}
local imageExtensions = {
    png = true, jpg = true, jpeg = true, bmp = true, tga = true,
    dds = true, ktx = true, pvr = true, etc = true, astc = true,
}

local function changed()
    changeRevision = changeRevision + 1
end

---@param value any
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

---@param value any
---@param minimum integer
---@return boolean
local function sliceInteger(value, minimum)
    return finite(value) and value >= minimum and value <= MAX_SLICE_VALUE
        and value == math.floor(value)
end

---@param path any
---@return boolean
---@return string?
local function validPath(path)
    if type(path) ~= "string" or #path > 1024 then
        return false, "请填写本地资源路径"
    end
    if path:sub(1, #RESOURCE_ROOT) ~= RESOURCE_ROOT then
        return false, "图片路径必须位于 image/地图/tiles/，不能填写 URL 或绝对路径"
    end
    if path:find("[%c\\:%?#%%]") or path:find("//", 1, true) then
        return false, "图片路径包含不允许的字符"
    end
    local relative = path:sub(#RESOURCE_ROOT + 1)
    for segment in relative:gmatch("[^/]+") do
        if segment == "." or segment == ".." then
            return false, "图片路径不能包含目录跳转"
        end
    end
    local ext = relative:match("%.([%w]+)$")
    if not ext or not imageExtensions[ext:lower()] then
        return false, "请选择 PNG 或支持的本地图像格式"
    end
    return true
end

--- 只查询当前构建的资源清单和本地资源缓存，不扫描工作机或用户存档目录。
---@param path string
---@return boolean
local function resourceKnown(path)
    if not cache then return false end
    local ok, info = pcall(function() return cache:GetResInfo(path) end)
    if ok and info then return true end
    local existsOK, exists = pcall(function() return cache:Exists(path) end)
    return existsOK and exists == true
end

---@param path string
---@return string
local function idForPath(path)
    local checksum = 0
    for index = 1, #path do
        checksum = (checksum * 131 + path:byte(index)) % 2147483647
    end
    return "tiles_" .. string.format("%08x", math.floor(checksum))
end

---@param input any
---@return MapTilesetInput?
---@return string?
local function validateInput(input)
    if type(input) ~= "table" then return nil, "瓦片集配置必须是表" end
    local pathOK, pathError = validPath(input.path)
    if not pathOK then return nil, pathError end
    if input.id ~= nil and (type(input.id) ~= "string" or #input.id < 1
        or #input.id > 64 or not input.id:match("^[%w_-]+$")) then
        return nil, "瓦片集 ID 只允许 1–64 位字母、数字、下划线和短横线"
    end
    if input.id == "builtin" then return nil, "基础测试瓦片集不能被覆盖" end
    if input.name ~= nil and (type(input.name) ~= "string" or #input.name > 200
        or input.name:find("%c")) then
        return nil, "瓦片集名称不合法"
    end
    local margin = input.margin == nil and 0 or input.margin
    local spacing = input.spacing == nil and 0 or input.spacing
    if not sliceInteger(input.cellWidth, 1) or not sliceInteger(input.cellHeight, 1) then
        return nil, "格子宽高必须为 1–65536 的正整数像素"
    end
    if not sliceInteger(margin, 0) or not sliceInteger(spacing, 0) then
        return nil, "外边距和间距必须为 0–65536 的整数像素"
    end
    local collider = input.collider or "ground"
    if collider ~= "ground" and collider ~= "decoration" then
        return nil, "碰撞类型只能是 ground（整格）或 decoration（无碰撞）"
    end
    local name = input.name
    if not name or name == "" then name = input.path:match("([^/]+)$") end
    ---@type MapTilesetInput
    local result = {
        id = input.id or idForPath(input.path),
        name = name,
        path = input.path,
        cellWidth = math.floor(input.cellWidth),
        cellHeight = math.floor(input.cellHeight),
        margin = math.floor(margin),
        spacing = math.floor(spacing),
        collider = collider,
    }
    return result
end

--- 不采信配置中的 columns/rows/count，始终由真实图片尺寸推导。
--- 外边距在两边对称；间距只在相邻格之间。残缺的一行或一列直接报配置错误。
---@param definition MapTilesetDefinition
---@param width integer
---@param height integer
---@return integer columns
---@return integer rows
---@return string?
local function sliceDimensions(definition, width, height)
    local innerW = width - definition.margin * 2
    local innerH = height - definition.margin * 2
    if innerW < definition.cellWidth or innerH < definition.cellHeight then
        return 0, 0, "图片扣除外边距后放不下一个完整格子"
    end
    local strideW = definition.cellWidth + definition.spacing
    local strideH = definition.cellHeight + definition.spacing
    if (innerW + definition.spacing) % strideW ~= 0
        or (innerH + definition.spacing) % strideH ~= 0 then
        return 0, 0, string.format("真实尺寸 %d×%d 无法按当前格子、外边距和间距完整切片", width, height)
    end
    return math.floor((innerW + definition.spacing) / strideW),
        math.floor((innerH + definition.spacing) / strideH)
end

---@param config MapTilesetInput
---@param source 'source'|'sandbox'
---@return MapTilesetDefinition
local function definitionFor(config, source)
    return {
        id = config.id or idForPath(config.path), name = config.name or config.path,
        path = config.path, cellWidth = config.cellWidth, cellHeight = config.cellHeight,
        margin = config.margin or 0, spacing = config.spacing or 0,
        columns = 0, rows = 0, count = 0, collider = config.collider or "ground",
        status = "pending", source = source, imageWidth = 0, imageHeight = 0,
    }
end

---@param definition MapTilesetDefinition
local function refreshDefinition(definition)
    if definition.id == "builtin" then return end
    local resource = definition.path and resources[definition.path]
    local oldStatus, oldError = definition.status, definition.error
    local oldW, oldH, oldCount = definition.imageWidth, definition.imageHeight, definition.count
    definition.columns, definition.rows, definition.count = 0, 0, 0
    definition.imageWidth = resource and resource.width or 0
    definition.imageHeight = resource and resource.height or 0
    if resource and resource.width > 0 and resource.height > 0 then
        local columns, rows, err = sliceDimensions(definition, resource.width, resource.height)
        definition.columns, definition.rows, definition.count = columns, rows, columns * rows
        definition.status, definition.error = err and "error" or "ready", err
    elseif resource and resource.error then
        definition.status, definition.error = "error", resource.error
    else
        definition.status, definition.error = active and "loading" or "pending", nil
    end
    if oldStatus ~= definition.status or oldError ~= definition.error or oldCount ~= definition.count
        or oldW ~= definition.imageWidth or oldH ~= definition.imageHeight then changed() end
end

---@param path string
local function refreshPath(path)
    for _, definition in ipairs(definitions) do
        if definition.path == path then refreshDefinition(definition) end
    end
end

---@param definition MapTilesetDefinition
---@return MapTilesetDefinition
local function snapshot(definition)
    ---@type MapTilesetDefinition
    local copy = {
        id = definition.id, name = definition.name, path = definition.path,
        cellWidth = definition.cellWidth, cellHeight = definition.cellHeight,
        margin = definition.margin, spacing = definition.spacing,
        columns = definition.columns, rows = definition.rows, count = definition.count,
        collider = definition.collider, status = definition.status, error = definition.error,
        imageWidth = definition.imageWidth, imageHeight = definition.imageHeight,
        source = definition.source,
    }
    if definition.tiles then
        copy.tiles = {}
        for _, tile in ipairs(definition.tiles) do
            copy.tiles[#copy.tiles + 1] = {
                id = tile.id, label = tile.label, collider = tile.collider,
                color = { tile.color[1], tile.color[2], tile.color[3] },
            }
        end
    end
    return copy
end

local function installSource()
    definitions, byId = {}, {}
    for _, original in ipairs(sourceDefinitions) do
        if original.id == "builtin" then
            local builtin = snapshot(original)
            builtin.status, builtin.source = "ready", "builtin"
            definitions[#definitions + 1] = builtin
            byId[builtin.id] = builtin
        else
            local config, err = validateInput(original)
            if config then
                local definition = definitionFor(config, "source")
                if not byId[definition.id] then
                    definitions[#definitions + 1] = definition
                    byId[definition.id] = definition
                else
                    print("[瓦片集] 源码注册表存在重复 ID：" .. definition.id)
                end
            else
                print("[瓦片集] 源码配置错误：" .. tostring(err))
            end
        end
    end
    changed()
end

---@param vg NVGContextWrapper
---@return TilesetContext
local function attachContext(vg)
    local context = contexts[vg]
    if not context then
        context = { vg = vg, alive = true, images = {} }
        contexts[vg] = context
    end
    return context
end

---@param path string
---@return TilesetResource
local function resourceFor(path)
    local resource = resources[path]
    if not resource then
        resource = {
            path = path, downloaded = false, busy = false, attempts = 0,
            retryDelay = 0, width = 0, height = 0,
        }
        resources[path] = resource
    end
    return resource
end

--- 图片解码只在下载完成/新上下文首次使用时执行；失败也缓存，避免逐帧创建。
---@param context TilesetContext
---@param resource TilesetResource
---@return TilesetImage?
local function loadContextImage(context, resource)
    if not active or not context.alive or not resource.downloaded then return nil end
    local existing = context.images[resource.path]
    if existing then return existing end
    local image = { handle = 0, width = 0, height = 0 } ---@type TilesetImage
    context.images[resource.path] = image
    local flags = resource.path == WALL_FILL_PATH and (NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY) or NVG_IMAGE_NEAREST
    local ok, handle = pcall(nvgCreateImage, context.vg, resource.path, flags)
    if not ok or not handle or handle <= 0 then
        image.error = "图片解码失败，保留占位瓦片"
    else
        image.handle = handle
        local sizeOK, width, height = pcall(nvgImageSize, context.vg, handle)
        if not sizeOK or not sliceInteger(width, 1) or not sliceInteger(height, 1) then
            nvgDeleteImage(context.vg, handle)
            image.handle, image.error = 0, "无法读取真实图片尺寸"
        elseif resource.width > 0 and (resource.width ~= width or resource.height ~= height) then
            nvgDeleteImage(context.vg, handle)
            image.handle, image.error = 0, "不同绘制上下文的图集尺寸不一致，请重新加载"
        else
            image.width, image.height = width, height
            resource.width, resource.height, resource.error = width, height, nil
            print(string.format("[瓦片集] 已读取真实图集：%s，%d×%d", resource.path, width, height))
        end
    end
    if image.error then
        if resource.width == 0 then resource.error = image.error end
        changed()
        print("[瓦片集] " .. resource.path .. "：" .. image.error)
    end
    refreshPath(resource.path)
    return image
end

---@param resource TilesetResource
local function loadBoundContexts(resource)
    for _, context in pairs(contexts) do loadContextImage(context, resource) end
end

---@param resource TilesetResource
local function requestResource(resource)
    if not active or resource.busy or resource.downloaded or resource.attempts >= MAX_ATTEMPTS then return end
    if not resourceKnown(resource.path) then
        resource.error = "资源未包含在当前构建中；请先上传至 assets 并在源码注册表追加路径，再统一构建"
        resource.retryDelay, resource.attempts = 0, MAX_ATTEMPTS
        refreshPath(resource.path)
        print("[瓦片集] " .. resource.path .. "：" .. resource.error)
        return
    end
    resource.busy, resource.error, resource.retryDelay = true, nil, 0
    resource.attempts = resource.attempts + 1
    refreshPath(resource.path)
    local ticket = generation
    local completed = false
    local ok, group = pcall(function()
        return cache:DownloadResources({ resource.path }, function(success, failedCount)
            completed = true
            if not active or ticket ~= generation or resources[resource.path] ~= resource then return end
            resource.busy, resource.group = false, nil
            local existsOK, exists = pcall(function() return cache:Exists(resource.path) end)
            if existsOK and exists then
                resource.downloaded, resource.error = true, nil
                loadBoundContexts(resource)
            else
                resource.error = "资源下载未就绪，保留占位瓦片"
                if resource.attempts < MAX_ATTEMPTS then resource.retryDelay = resource.attempts * 2 end
                print(string.format("[瓦片集] 下载失败：%s（第 %d 次，失败数 %d）",
                    resource.path, resource.attempts, failedCount or 1))
            end
            refreshPath(resource.path)
        end)
    end)
    -- 已在本地的资源可能同步回调；不能把已完成的 group 再写回活动任务。
    if not completed and ok then resource.group = group end
    if not ok and ticket == generation and active then
        resource.busy, resource.group = false, nil
        resource.error = "无法请求已构建资源，保留占位瓦片"
        if resource.attempts < MAX_ATTEMPTS then resource.retryDelay = resource.attempts * 2 end
        print("[瓦片集] 下载接口失败：" .. resource.path)
        refreshPath(resource.path)
    end
end

local function prepareDefinitions()
    local fill = resourceFor(WALL_FILL_PATH)
    if fill.downloaded then loadBoundContexts(fill) else requestResource(fill) end
    for _, definition in ipairs(definitions) do
        if definition.path then
            local resource = resourceFor(definition.path)
            if resource.downloaded then loadBoundContexts(resource) else requestResource(resource) end
            refreshDefinition(definition)
        end
    end
end

---@return integer 每次注册、状态或尺寸变化时增加，UI 在 Update 中低频轮询即可
function TS.revision()
    return changeRevision
end

---@return MapTilesetDefinition[] 只读快照；pending/loading/error 的未知图集 count 为 0
function TS.list()
    local result = {} ---@type MapTilesetDefinition[]
    for _, definition in ipairs(definitions) do result[#result + 1] = snapshot(definition) end
    return result
end

---@param id string
---@return MapTilesetDefinition?
function TS.get(id)
    local definition = byId[id]
    return definition and snapshot(definition) or nil
end

---@param id string
---@param vg? NVGContextWrapper 可选检查当前 UI/world 上下文自己的解码失败
---@return string status
---@return string? error
function TS.status(id, vg)
    local definition = byId[id]
    if not definition then return "error", "不存在的瓦片集" end
    if vg and definition.path then
        local context = contexts[vg]
        local image = context and context.images[definition.path]
        if image and image.error then return "error", image.error end
    end
    return definition.status or "pending", definition.error
end

---@return string?
function TS.error()
    return lastError
end

--- 导出完整路径和切片元数据，供地图源码固化并让构建器追踪资源引用。
--- 不导出 builtin、图片句柄、推导尺寸或运行状态。
---@return MapTilesetInput[]
function TS.exportDefinitions()
    local result = {} ---@type MapTilesetInput[]
    for _, definition in ipairs(definitions) do
        if definition.path then
            result[#result + 1] = {
                id = definition.id, name = definition.name, path = definition.path,
                cellWidth = definition.cellWidth, cellHeight = definition.cellHeight,
                margin = definition.margin, spacing = definition.spacing, collider = definition.collider,
            }
        end
    end
    return result
end

--- 完整验证后将地图自带注册表按 ID 替换/追加；不写用户沙箱，不触碰 builtin。
--- 资源下载/真实尺寸尚未就绪时保留 count=0，通过 status/error/revision 反馈。
---@param list MapTilesetInput[]
---@return boolean
---@return string?
function TS.loadDefinitions(list)
    if type(list) ~= "table" then return false, "地图瓦片集注册表必须是数组" end
    local configs = {} ---@type MapTilesetInput[]
    local seen = {} ---@type table<string, boolean>
    local entries, added = 0, 0
    for key in pairs(list) do
        entries = entries + 1
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false, "地图瓦片集注册表必须是一基连续数组"
        end
    end
    if entries ~= #list or entries > MAX_DEFINITIONS then return false, "地图瓦片集数量不合法" end
    for _, input in ipairs(list) do
        local config, err = validateInput(input)
        if not config then lastError = err; changed(); return false, err end
        local id = config.id or idForPath(config.path)
        if seen[id] then return false, "地图注册表存在重复瓦片集 ID：" .. id end
        seen[id] = true
        if not byId[id] then added = added + 1 end
        local resource = resources[config.path]
        if resource and resource.width > 0 then
            local _, _, boundaryError = sliceDimensions(definitionFor(config, "source"), resource.width, resource.height)
            if boundaryError then lastError = boundaryError; changed(); return false, boundaryError end
        end
        configs[#configs + 1] = config
    end
    if #definitions + added > MAX_DEFINITIONS then return false, "瓦片集注册数量已达上限" end
    -- 先完成整个注册表的原子替换，再发起可能同步回调的下载。
    for _, config in ipairs(configs) do
        local definition = definitionFor(config, "source")
        local id = definition.id
        if byId[id] then
            for index, old in ipairs(definitions) do
                if old.id == id then definitions[index] = definition; break end
            end
        else
            definitions[#definitions + 1] = definition
        end
        byId[id] = definition
    end
    lastError = nil
    changed()
    if active then prepareDefinitions() end
    return true
end

--- FileSystem.ScanDir 查询的是沙箱存档，不代表资源清单，故不把它用于发现工作机 assets。
--- 未登记且未下载资源无可移植枚举接口时，返回空候选表并允许 UI 手填资源路径。
---@return string[] 已登记且存在于当前构建的本地图片路径；当前空目录下返回空数组
function TS.availableFiles()
    local result, seen = {}, {} ---@type string[], table<string, boolean>
    for _, definition in ipairs(definitions) do
        local path = definition.path
        if path and not seen[path] and resourceKnown(path) then
            seen[path] = true
            result[#result + 1] = path
        end
    end
    table.sort(result)
    return result
end

--- 只保存运行时覆写配置；不保存推导尺寸、状态或上下文图片句柄。
---@return boolean
---@return string?
function TS.save()
    local configs = {} ---@type MapTilesetInput[]
    for _, config in pairs(overrides) do configs[#configs + 1] = config end
    table.sort(configs, function(a, b) return (a.id or "") < (b.id or "") end)
    local encodedOK, text = pcall(function() return cjson.encode({ version = 1, tilesets = configs }) end)
    if not encodedOK then
        lastError = "瓦片集配置编码失败"
        changed()
        return false, lastError
    end
    local openOK, file = pcall(function() return File(SAVE_PATH, FILE_WRITE) end)
    if not openOK or not file then
        lastError = "无法创建沙箱 tilesets.json"
        changed()
        return false, lastError
    end
    if not file:IsOpen() then
        file:Dispose()
        lastError = "无法打开沙箱 tilesets.json（服务器模式不支持本地保存）"
        changed()
        return false, lastError
    end
    local writeOK, written = pcall(function() return file:WriteString(text) end)
    file:Dispose()
    if not writeOK or not written then
        lastError = "写入沙箱 tilesets.json 失败"
        changed()
        return false, lastError
    end
    lastError = nil
    print("[瓦片集] 已保存沙箱注册表：" .. #configs .. " 项")
    return true
end

--- 整份配置验证后再替换注册表，损坏的沙箱文件不会清空当前有效配置。
---@return boolean
---@return string?
function TS.reload()
    local existsOK, exists = pcall(function() return fileSystem:FileExists(SAVE_PATH) end)
    local incoming = {} ---@type table<string, MapTilesetInput>
    if existsOK and exists then
        local openOK, file = pcall(function() return File(SAVE_PATH, FILE_READ) end)
        if not openOK or not file then return false, "无法读取沙箱 tilesets.json" end
        if not file:IsOpen() then file:Dispose(); return false, "无法打开沙箱 tilesets.json" end
        local readOK, text = pcall(function() return file:ReadString() end)
        file:Dispose()
        if not readOK then return false, "读取沙箱 tilesets.json 失败" end
        local decodedOK, data = pcall(function() return cjson.decode(text) end)
        if not decodedOK or type(data) ~= "table" or data.version ~= 1 or type(data.tilesets) ~= "table" then
            lastError = "沙箱瓦片集配置格式不正确，需要 version=1 和 tilesets 数组"
            changed()
            return false, lastError
        end
        local entries = 0
        for key in pairs(data.tilesets) do
            entries = entries + 1
            if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
                return false, "沙箱 tilesets 必须是一基连续数组"
            end
        end
        if entries ~= #data.tilesets or entries > MAX_DEFINITIONS then
            return false, "沙箱瓦片集数量不合法或数组不连续"
        end
        for _, input in ipairs(data.tilesets) do
            local config, err = validateInput(input)
            if not config then return false, err end
            local id = config.id or idForPath(config.path)
            if incoming[id] then return false, "沙箱注册表有重复瓦片集 ID：" .. id end
            incoming[id] = config
        end
    end
    installSource()
    overrides = incoming
    local ids = {} ---@type string[]
    for id in pairs(overrides) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local definition = definitionFor(overrides[id], "sandbox")
        local old = byId[id]
        if old then
            for index, value in ipairs(definitions) do
                if value.id == id then definitions[index] = definition; break end
            end
        else
            definitions[#definitions + 1] = definition
        end
        byId[id] = definition
    end
    lastError = nil
    changed()
    if active then prepareDefinitions() end
    return true
end

--- true 表示配置已登记；未知尺寸时 status=loading/count=0，稍后只按实际尺寸更新。
--- false 表示配置、路径、已知切片边界或保存失败；错误不冒充已成功注册。
---@param input MapTilesetInput
---@return boolean
---@return string?
function TS.register(input)
    local config, err = validateInput(input)
    if not config then lastError = err; changed(); return false, err end
    if not resourceKnown(config.path) then
        err = "当前版本没有此资源；请通过聊天上传图片到 assets/image/地图/tiles/，追加源码路径后再构建"
        lastError = err
        changed()
        return false, err
    end
    -- 未传 ID 时优先复用同路径的登记，保证再次修改切片参数不会产生新 ID。
    if input.id == nil then
        for _, value in ipairs(definitions) do
            if value.path == config.path then config.id = value.id; break end
        end
    end
    local id = config.id or idForPath(config.path)
    local previous = byId[id]
    if previous and input.id == nil and previous.path ~= config.path then
        return false, "自动 ID 冲突，请填写不同的瓦片集 ID"
    end
    if not previous and #definitions >= MAX_DEFINITIONS then return false, "瓦片集注册数量已达上限" end
    local definition = definitionFor(config, "sandbox")
    local resource = resourceFor(config.path)
    if active then
        if resource.downloaded then loadBoundContexts(resource) else requestResource(resource) end
    end
    if resource.width > 0 then
        local _, _, boundaryError = sliceDimensions(definition, resource.width, resource.height)
        if boundaryError then lastError = boundaryError; changed(); return false, boundaryError end
    end
    local oldOverride = overrides[id]
    overrides[id] = config
    local saved, saveError = TS.save()
    if not saved then overrides[id] = oldOverride; return false, saveError end
    if previous then
        for index, value in ipairs(definitions) do
            if value.id == id then definitions[index] = definition; break end
        end
    else
        definitions[#definitions + 1] = definition
    end
    byId[id] = definition
    refreshDefinition(definition)
    changed()
    print("[瓦片集] 已登记：" .. id .. "，" .. config.path)
    return true
end

--- 仅释放该上下文内的图片；不删除调用方的 vg。UI 重建前可单独调用。
---@param vg NVGContextWrapper
function TS.releaseContext(vg)
    local context = contexts[vg]
    if not context then return end
    context.alive = false
    contexts[vg] = nil
    for _, image in pairs(context.images) do
        if image.handle > 0 then pcall(nvgDeleteImage, vg, image.handle) end
    end
    context.images = {}
    if defaultContext == vg then defaultContext = nil end
end

function TS.shutdown()
    active = false
    generation = generation + 1
    -- 先失效生命周期标记，再取消任务：取消本身可能触发旧回调。
    for _, resource in pairs(resources) do
        local group = resource.group
        resource.group, resource.busy, resource.retryDelay = nil, false, 0
        if group and cache then pcall(function() cache:CancelDownloadGroup(group) end) end
    end
    local allContexts = {} ---@type NVGContextWrapper[]
    for vg in pairs(contexts) do allContexts[#allContexts + 1] = vg end
    for _, vg in ipairs(allContexts) do TS.releaseContext(vg) end
    resources, contexts, defaultContext = {}, {}, nil
    for _, definition in ipairs(definitions) do refreshDefinition(definition) end
    changed()
end

---@param vg NVGContextWrapper
---@return boolean
---@return string?
function TS.init(vg)
    TS.shutdown()
    if not vg then return false, "瓦片集初始化需要有效的 NanoVG 上下文" end
    defaultContext = vg
    active = true
    attachContext(vg)
    local ok, err = TS.reload()
    if not ok then
        lastError = err
        overrides = {}
        installSource()
        prepareDefinitions()
        print("[瓦片集] 沙箱配置加载失败，使用源码注册表：" .. tostring(err))
    end
    print("[瓦片集] 初始化完成；真实图片未上传时可使用基础测试瓦片")
    return true, err
end

---@param dt number
function TS.update(dt)
    if not active or not finite(dt) or dt < 0 then return end
    for _, resource in pairs(resources) do
        if resource.retryDelay > 0 then
            resource.retryDelay = math.max(0, resource.retryDelay - dt)
            if resource.retryDelay == 0 then requestResource(resource) end
        end
    end
end

--- 用户修正资源后主动重试；不是每帧调用。加载失败的上下文句柄也在此清理。
---@param id string
---@return boolean
function TS.retry(id)
    local definition = byId[id]
    if not active or not definition or not definition.path then return false end
    local resource = resourceFor(definition.path)
    if resource.busy then return false end
    local retryFill = TerrainTiles.supports(definition)
    for _, context in pairs(contexts) do
        local image = context.images[resource.path]
        if image and image.handle > 0 then nvgDeleteImage(context.vg, image.handle) end
        context.images[resource.path] = nil
    end
    resource.downloaded, resource.attempts, resource.width, resource.height = false, 0, 0, 0
    resource.error, resource.retryDelay = nil, 0
    requestResource(resource)
    -- 工业墙重试也恢复其辅助内填充，包含已缓存的解码失败和用尽的下载次数。
    -- 未就绪时仍回退原墙图，不让辅助资源失败改变地形形体。
    if retryFill then
        local fill = resourceFor(WALL_FILL_PATH)
        if not fill.busy then
            for _, context in pairs(contexts) do
                local image = context.images[WALL_FILL_PATH]
                if image and image.handle > 0 then nvgDeleteImage(context.vg, image.handle) end
                context.images[WALL_FILL_PATH] = nil
            end
            fill.downloaded, fill.attempts, fill.width, fill.height = false, 0, 0, 0
            fill.error, fill.retryDelay = nil, 0
            requestResource(fill)
        end
    end
    return true
end

---@param definition MapTilesetDefinition
---@param tileId integer
---@return BuiltinMapTile?
local function builtinTile(definition, tileId)
    for _, tile in ipairs(definition.tiles or {}) do
        if tile.id == tileId then return tile end
    end
    return nil
end

---@param id string
---@param tileId integer
---@return 'ground'|'decoration'
function TS.tileCollider(id, tileId)
    local definition = byId[id]
    if not definition then return "decoration" end
    local tile = definition.id == "builtin" and builtinTile(definition, tileId) or nil
    return tile and tile.collider or definition.collider
end

---@param id string
---@param tileId integer
---@return string
function TS.describe(id, tileId)
    local definition = byId[id]
    if not definition then return "未知瓦片集 / " .. tostring(tileId) end
    local tile = definition.id == "builtin" and builtinTile(definition, tileId) or nil
    local label = tile and tile.label or ("瓦片 " .. tostring(tileId))
    local collider = TS.tileCollider(id, tileId) == "ground" and "整格碰撞" or "无碰撞"
    return definition.name .. " / " .. label .. " · " .. collider
end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param alpha number
local function drawFallback(vg, x, y, w, h, alpha)
    nvgSave(vg)
    nvgIntersectScissor(vg, x, y, w, h)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(64, 49, 79, math.floor(255 * alpha)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w / 2, h / 2)
    nvgRect(vg, x + w / 2, y + h / 2, w / 2, h / 2)
    nvgFillColor(vg, nvgRGBA(159, 89, 177, math.floor(255 * alpha)))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 基础地面铺满整格，装饰保留透明背景；不依赖任何图片或字体资源。
---@param vg NVGContextWrapper
---@param tile BuiltinMapTile
---@param x number
---@param y number
---@param w number
---@param h number
---@param alpha number
local function drawBuiltin(vg, tile, x, y, w, h, alpha)
    nvgSave(vg)
    nvgIntersectScissor(vg, x, y, w, h)
    nvgTranslate(vg, x, y)
    nvgScale(vg, w / 32, h / 32)
    local color = tile.color
    local opacity = math.floor(255 * alpha)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], opacity))
    nvgBeginPath(vg)
    if tile.collider == "ground" then
        nvgShapeAntiAlias(vg, 0)
        nvgRect(vg, 0, 0, 32, 32)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, 32, 4)
        nvgFillColor(vg, nvgRGBA(math.min(255, color[1] + 35), math.min(255, color[2] + 35),
            math.min(255, color[3] + 35), opacity))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, 3 + tile.id, 12, 7, 3)
        nvgRect(vg, 18, 24 - tile.id, 8, 3)
        nvgFillColor(vg, nvgRGBA(math.max(0, color[1] - 28), math.max(0, color[2] - 28),
            math.max(0, color[3] - 28), opacity))
        nvgFill(vg)
    elseif tile.id == 5 then
        nvgMoveTo(vg, 8, 28); nvgLineTo(vg, 4, 12); nvgLineTo(vg, 13, 23)
        nvgLineTo(vg, 14, 7); nvgLineTo(vg, 19, 22); nvgLineTo(vg, 28, 13)
        nvgLineTo(vg, 24, 28); nvgClosePath(vg); nvgFill(vg)
    elseif tile.id == 6 then
        nvgMoveTo(vg, 16, 4)
        nvgBezierTo(vg, 9, 13, 6, 17, 6, 21)
        nvgBezierTo(vg, 6, 33, 26, 33, 26, 21)
        nvgBezierTo(vg, 26, 17, 23, 13, 16, 4)
        nvgClosePath(vg); nvgFill(vg)
    elseif tile.id == 7 then
        nvgMoveTo(vg, 16, 3); nvgLineTo(vg, 27, 16); nvgLineTo(vg, 16, 30)
        nvgLineTo(vg, 5, 16); nvgClosePath(vg); nvgFill(vg)
    else
        nvgRoundedRect(vg, 13, 5, 6, 17, 2)
        nvgCircle(vg, 16, 27, 3); nvgFill(vg)
    end
    nvgRestore(vg)
end

--- 返回 false 时已绘制棋盘占位（无效坐标/透明度除外），调用方无需每帧重载图片。
--- 最近邻采样且禁用矩形边缘抗锯齿，不生成 mipmap，不采到相邻格子。
---@param vg NVGContextWrapper
---@param tilesetId string
---@param tileId integer
---@param x number
---@param y number
---@param w number
---@param h number
---@param alpha? number
---@param sourceRect? TerrainSourceRect 仅地图连续地形使用；调色板保留原切片
---@param borderOnly? boolean 配合连续内填充，只提交外露边框带，不覆盖或重叠内区
---@return boolean
function TS.drawTile(vg, tilesetId, tileId, x, y, w, h, alpha, sourceRect, borderOnly)
    if not vg or not finite(x) or not finite(y) or not finite(w) or not finite(h) or w <= 0 or h <= 0 then
        return false
    end
    local alphaValue = alpha == nil and 1.0 or alpha
    if not finite(alphaValue) then return false end
    local opacity = math.max(0, math.min(1, alphaValue or 1.0))
    if opacity == 0 then return true end
    local definition = byId[tilesetId]
    if not definition or not finite(tileId) or tileId < 1 or tileId ~= math.floor(tileId) then
        drawFallback(vg, x, y, w, h, opacity)
        return false
    end
    if definition.id == "builtin" then
        local tile = builtinTile(definition, math.floor(tileId))
        if tile then drawBuiltin(vg, tile, x, y, w, h, opacity); return true end
    elseif active and definition.path then
        local context = attachContext(vg)
        local resource = resourceFor(definition.path)
        -- 新 UI 上下文只在首次用到该图片时创建自己的句柄。
        local image = loadContextImage(context, resource)
        if not resource.downloaded and resource.attempts == 0 then requestResource(resource) end
        image = context.images[definition.path] or image
        if image and image.handle > 0 and definition.status == "ready" and tileId <= definition.count then
            local index = tileId - 1
            local cellX = definition.margin + (index % definition.columns) * (definition.cellWidth + definition.spacing)
            local cellY = definition.margin + math.floor(index / definition.columns) * (definition.cellHeight + definition.spacing)
            if sourceRect and (type(sourceRect) ~= "table"
                or not sliceInteger(sourceRect.x, 0) or not sliceInteger(sourceRect.y, 0)
                or not sliceInteger(sourceRect.width, 1) or not sliceInteger(sourceRect.height, 1)) then
                drawFallback(vg, x, y, w, h, opacity)
                return false
            end
            local cropX, cropY = sourceRect and sourceRect.x or 0, sourceRect and sourceRect.y or 0
            local cropW = sourceRect and sourceRect.width or definition.cellWidth
            local cropH = sourceRect and sourceRect.height or definition.cellHeight
            if cropX < 0 or cropY < 0 or cropW <= 0 or cropH <= 0
                or cropX + cropW > definition.cellWidth or cropY + cropH > definition.cellHeight then
                drawFallback(vg, x, y, w, h, opacity)
                return false
            end
            -- 使用该上下文 nvgImageSize 的真实整图宽高；裁切不改变目标格尺寸。
            nvgSave(vg)
            -- 连续墙的矩形本身限制绘制范围；逐格软 scissor 会在亚像素共边漏底。
            -- 其他切片保留原裁剪，地图视口裁剪仍由 drawLayer 执行。
            if not sourceRect then nvgIntersectScissor(vg, x, y, w, h) end
            nvgTranslate(vg, x, y)
            nvgScale(vg, w / cropW, h / cropH)
            nvgShapeAntiAlias(vg, 0)
            nvgBeginPath(vg)
            if borderOnly and sourceRect then
                local x0, x1 = 24 - cropX, 232 - cropX
                local y0, y1 = 16 - cropY, 240 - cropY
                if y0 > 0 then nvgRect(vg, 0, 0, cropW, y0) end
                if y1 < cropH then nvgRect(vg, 0, y1, cropW, cropH - y1) end
                if x0 > 0 then nvgRect(vg, 0, y0, x0, y1 - y0) end
                if x1 < cropW then nvgRect(vg, x1, y0, cropW - x1, y1 - y0) end
            else
                nvgRect(vg, 0, 0, cropW, cropH)
            end
            nvgFillPaint(vg, nvgImagePattern(vg, -cellX - cropX, -cellY - cropY,
                image.width, image.height, 0, image.handle, opacity))
            nvgFill(vg)
            nvgRestore(vg)
            return true
        end
    end
    drawFallback(vg, x, y, w, h, opacity)
    return false
end

--- 内部纹理跨 4×4 格只提交一次 fill，多个矩形子路径构成真实占用并集。
--- 不用宏块包围盒填充，也不用逐格软 scissor，避免堵通道和亚像素漏底。
---@param vg NVGContextWrapper
---@param group TerrainMacroGroup
---@param image TilesetImage
---@param left number
---@param top number
---@param cellPixels number
---@param firstCol integer
---@param lastCol integer
---@param firstRow integer
---@param lastRow integer
---@return integer 可视内部格数
local function drawTerrainGroup(vg, group, image, left, top, cellPixels, firstCol, lastCol, firstRow, lastRow)
    local count = 0
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgBeginPath(vg)
    for _, region in ipairs(group.regions) do
        local col, row = group.col + region.col - 1, group.row + region.row - 1
        local c0, c1 = math.max(col, firstCol), math.min(col + region.width - 1, lastCol)
        local r0, r1 = math.max(row, firstRow), math.min(row + region.height - 1, lastRow)
        if c1 >= c0 and r1 >= r0 then
            local x, y = left + (c0 - 1) * cellPixels, top + (r0 - 1) * cellPixels
            local right, bottom = left + c1 * cellPixels, top + r1 * cellPixels
            nvgRect(vg, x, y, right - x, bottom - y)
            count = count + math.floor((c1 - c0 + 1) * (r1 - r0 + 1))
        end
    end
    if count > 0 then
        -- 同一全局原点，4米周期；连续纹理不在每个格或宏块边重新起笔。
        nvgFillPaint(vg, nvgImagePattern(vg, left, top, 4 * cellPixels, 4 * cellPixels, 0, image.handle, 1))
        nvgFill(vg)
    end
    nvgRestore(vg)
    return count
end

--- 仅遍历可视行列与可视宏块，不逐帧重建整个 cells。
--- 本模块只画视觉层，不导入 ME、不产生碰撞体；ground/decoration 由地图编译器处理。
---@param vg NVGContextWrapper
---@param layerId string
---@param data TilesetMapData
---@param projection TilesetProjection
---@param editor? boolean
---@return integer 已成功绘制的瓦片数（加载失败占位不计入）
function TS.drawLayer(vg, layerId, data, projection, editor)
    if not vg or type(data) ~= "table" or type(data.visualLayers) ~= "table"
        or type(projection) ~= "table" then return 0 end
    local layer = data.visualLayers[layerId]
    if type(layer) ~= "table" or type(layer.cells) ~= "table" or (editor and layer.visible == false) then return 0 end
    if not finite(data.tile) or data.tile <= 0 or not finite(data.originX) or not finite(data.originY)
        or not finite(data.cols) or not finite(data.rows) or data.cols < 1 or data.rows < 1
        or not finite(projection.camX) or not finite(projection.camY)
        or not finite(projection.ppu) or projection.ppu <= 0
        or not finite(projection.screenW) or not finite(projection.screenH)
        or projection.screenW <= 0 or projection.screenH <= 0 then return 0 end
    local cellPixels = data.tile * projection.ppu
    local left = projection.screenW / 2 + (data.originX - projection.camX) * projection.ppu
    local top = projection.screenH / 2 - (data.originY - projection.camY) * projection.ppu
    if not finite(cellPixels) or cellPixels <= 0 or not finite(left) or not finite(top) then return 0 end
    local firstCol = math.max(1, math.floor(-left / cellPixels) + 1)
    local lastCol = math.min(math.floor(data.cols), math.ceil((projection.screenW - left) / cellPixels))
    local firstRow = math.max(1, math.floor(-top / cellPixels) + 1)
    local lastRow = math.min(math.floor(data.rows), math.ceil((projection.screenH - top) / cellPixels))
    local count, fills, macroFills = 0, 0, 0
    ---@type TerrainRenderPlan?
    local terrainPlan = nil
    ---@type TilesetImage?
    local terrainImage = nil
    local wall = byId.industrial_walls
    if layerId == "ground" and active and wall and wall.path and wall.status == "ready" and TerrainTiles.supports(wall) then
        local image = loadContextImage(attachContext(vg), resourceFor(WALL_FILL_PATH))
        if image and image.handle > 0 then
            terrainImage = image
            terrainPlan = TerrainTiles.plan(layer, math.floor(data.cols), math.floor(data.rows), data.editRevision)
        end
    end
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, projection.screenW, projection.screenH)
    if terrainPlan and terrainImage then
        for gr = math.floor((firstRow - 1) / 4) * 4 + 1, lastRow, 4 do
            for gc = math.floor((firstCol - 1) / 4) * 4 + 1, lastCol, 4 do
                local group = terrainPlan.groups[string.format("%d:%d", gc, gr)]
                if group then
                    local drawn = drawTerrainGroup(vg, group, terrainImage, left, top, cellPixels,
                        firstCol, lastCol, firstRow, lastRow)
                    if drawn > 0 then count = count + drawn; fills = fills + 1; macroFills = macroFills + 1 end
                end
            end
        end
    end
    for row = firstRow, lastRow do
        local y = top + (row - 1) * cellPixels
        local bottom = top + row * cellPixels
        for col = firstCol, lastCol do
            local key = string.format("%d:%d", col, row)
            local cell = layer.cells[key]
            if type(cell) == "table" and type(cell.tilesetId) == "string"
                and not (terrainPlan and terrainPlan.interior[key]) then
                local definition = byId[cell.tilesetId]
                local sourceRect = layerId == "ground" and definition
                    and TerrainTiles.sourceRect(definition, layer, col, row) or nil
                local x = left + (col - 1) * cellPixels
                local right = left + col * cellPixels
                -- 共边由同一整数端点公式得到，不分别取整位置/宽度，也不加重叠像素。
                local width, height = sourceRect and right - x or cellPixels,
                    sourceRect and bottom - y or cellPixels
                if TS.drawTile(vg, cell.tilesetId, cell.tileId, x, y,
                    width, height, nil, sourceRect, terrainPlan ~= nil and sourceRect ~= nil) then count = count + 1; fills = fills + 1 end
            end
        end
    end
    -- 边界格只保留实测外轮廓带；其内填充与宏块共用世界纹理，不再重复整片管道。
    -- sourceRect 的 alpha 外沿不改，不扩格、不越外轮廓，全部边界内区一次 fill。
    if terrainPlan and terrainImage and wall then
        local boundaryCount = 0
        nvgSave(vg)
        nvgShapeAntiAlias(vg, 0)
        nvgBeginPath(vg)
        for row = firstRow, lastRow do
            for col = firstCol, lastCol do
                local key = string.format("%d:%d", col, row)
                if not terrainPlan.interior[key] then
                    local crop = TerrainTiles.sourceRect(wall, layer, col, row)
                    if crop then
                        local insetL, insetR = (24 - crop.x) / crop.width, (crop.x + crop.width - 232) / crop.width
                        local insetT, insetB = (16 - crop.y) / crop.height, (crop.y + crop.height - 240) / crop.height
                        local x, y = left + (col - 1 + insetL) * cellPixels, top + (row - 1 + insetT) * cellPixels
                        local right, bottom = left + (col - insetR) * cellPixels, top + (row - insetB) * cellPixels
                        nvgRect(vg, x, y, right - x, bottom - y)
                        boundaryCount = boundaryCount + 1
                    end
                end
            end
        end
        if boundaryCount > 0 then
            nvgFillPaint(vg, nvgImagePattern(vg, left, top, 4 * cellPixels, 4 * cellPixels, 0, terrainImage.handle, 1))
            nvgFill(vg)
            fills = fills + 1
        end
        nvgRestore(vg)
    end
    nvgRestore(vg)
    TS.lastLayerStats[layerId] = { cells = count, fills = fills, macroFills = macroFills }
    return count
end

---@param vg NVGContextWrapper
---@param data TilesetMapData
---@param projection TilesetProjection
---@param layerIds string[] 明确提供顺序，避免 pairs 带来随机图层顺序
---@param editor? boolean
---@return integer
function TS.drawLayers(vg, data, projection, layerIds, editor)
    local count = 0
    for _, id in ipairs(layerIds) do count = count + TS.drawLayer(vg, id, data, projection, editor) end
    return count
end

-- require 后即可枚举基础瓦片；图集资源仅在 init 后按需下载和创建。
installSource()
return TS
