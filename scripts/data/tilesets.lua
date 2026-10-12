-- ============================================================================
-- data/tilesets.lua - 瓦片集源码注册表
-- 上传的工业墙体素材已按独立透明图块裁切，另保留原图和原尺寸 slices/。
-- 编辑图集采用 256×256 等格槽，等比例适配并透明补边，不拉伸原画。
-- 地面碰撞仍是整格；管道、盖板默认装饰，可在编辑器改后续笔刷属性。
-- path 必须写完整本地资源路径字面量，不带 assets/，不能填写 URL 或工作机绝对路径。
-- 构建器由 core/tilesets.lua 的静态 require 追踪本表中的真实 path 字面量。
-- 沙箱 tilesets.json 只保存切片配置，不能上传图片或把新资源加入已发布版本。
-- ============================================================================

---@class BuiltinMapTile
---@field id integer 固定的一基瓦片编号，不随 UI 排序变化
---@field label string
---@field collider 'ground'|'decoration' ground 为整格碰撞，decoration 无碰撞
---@field color { [1]: integer, [2]: integer, [3]: integer }

---@class MapTilesetDefinition
---@field id string
---@field name string
---@field path? string
---@field cellWidth integer
---@field cellHeight integer
---@field margin integer
---@field spacing integer
---@field columns integer 未读取真实图片尺寸前必须为 0
---@field rows integer 未读取真实图片尺寸前必须为 0
---@field count integer 未读取真实图片尺寸前必须为 0
---@field collider 'ground'|'decoration'
---@field tiles? BuiltinMapTile[]
---@field status? 'pending'|'loading'|'ready'|'error'
---@field error? string
---@field imageWidth? integer
---@field imageHeight? integer
---@field source? 'builtin'|'source'|'sandbox'

---@type MapTilesetDefinition[]
local definitions = {
    {
        id = "industrial_walls",
        name = "工业墙体与转角 · 24块",
        path = "image/地图/tiles/industrial_walls.png",
        cellWidth = 256, cellHeight = 256, margin = 0, spacing = 0,
        columns = 0, rows = 0, count = 0, collider = "ground",
    },
    {
        id = "industrial_platforms",
        name = "工业平台 · 5块",
        path = "image/地图/tiles/industrial_platforms.png",
        cellWidth = 256, cellHeight = 256, margin = 0, spacing = 0,
        columns = 0, rows = 0, count = 0, collider = "ground",
    },
    {
        id = "industrial_pipes",
        name = "工业管道 · 16块装饰",
        path = "image/地图/tiles/industrial_pipes.png",
        cellWidth = 256, cellHeight = 256, margin = 0, spacing = 0,
        columns = 0, rows = 0, count = 0, collider = "decoration",
    },
    {
        id = "industrial_panels",
        name = "工业盖板 · 6块装饰",
        path = "image/地图/tiles/industrial_panels.png",
        cellWidth = 256, cellHeight = 256, margin = 0, spacing = 0,
        columns = 0, rows = 0, count = 0, collider = "decoration",
    },
    {
        id = "builtin",
        name = "基础测试",
        cellWidth = 32,
        cellHeight = 32,
        margin = 0,
        spacing = 0,
        columns = 4,
        rows = 2,
        count = 8,
        collider = "ground",
        tiles = {
            { id = 1, label = "草地", collider = "ground", color = { 77, 133, 80 } },
            { id = 2, label = "泥土", collider = "ground", color = { 153, 109, 72 } },
            { id = 3, label = "石块", collider = "ground", color = { 114, 129, 148 } },
            { id = 4, label = "冰块", collider = "ground", color = { 98, 187, 215 } },
            { id = 5, label = "草簇", collider = "decoration", color = { 117, 210, 139 } },
            { id = 6, label = "水滴", collider = "decoration", color = { 104, 197, 244 } },
            { id = 7, label = "晶石", collider = "decoration", color = { 199, 158, 240 } },
            { id = 8, label = "标记", collider = "decoration", color = { 244, 190, 93 } },
        },
    },
}

return definitions
