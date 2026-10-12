-- 背景资源登记：整图独立放置，不切瓦片、无碰撞。尺寸比按上传原图精确保留。
---@class MapBackgroundAsset
---@field id string
---@field name string
---@field path string
---@field pixelWidth integer
---@field pixelHeight integer
---@field imageWidth? integer
---@field imageHeight? integer

---@type MapBackgroundAsset[]
local backgrounds = {
    { id = "industrial_backdrop", name = "工业实验室背景", path = "image/地图/backgrounds/industrial_backdrop.jpg",
        pixelWidth = 6443, pixelHeight = 2106, imageWidth = 4096, imageHeight = 1339 },
}
return backgrounds
