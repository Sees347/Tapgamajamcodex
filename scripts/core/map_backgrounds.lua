-- ============================================================================
-- core/map_backgrounds.lua - 目录白名单整图背景（米制中心坐标，无瓦片/碰撞）
-- 沿用调用方的 NanoVG 坐标空间和 clip；不创建 context、不调整分辨率。
-- 资源只请求一次，每个 context 各自创建/核实句柄；失败保留数据并显式返回错误。
-- ============================================================================
local catalog = require "data.backgrounds"
local B = {}

---@class MapBackgroundImage
---@field id string 实例唯一 ID
---@field assetId string data.backgrounds 中的资源 ID，存档不接受路径
---@field x number 中心世界坐标，米
---@field y number 中心世界坐标，米，Y 向上
---@field width number 世界宽度，米；高度只能由原图比例推导

---@alias MapBackgroundProjection TilesetProjection

---@class MapBackgroundHandle
---@field handle integer
---@field width integer
---@field height integer
---@field error string|nil

---@class MapBackgroundContext
---@field vg NVGContextWrapper
---@field alive boolean
---@field images table<string, MapBackgroundHandle>

---@class MapBackgroundResource
---@field path string
---@field requested boolean
---@field ready boolean
---@field busy boolean
---@field error string|nil
---@field group integer|nil

---@type MapBackgroundAsset[]
local assets = {}
---@type table<string, MapBackgroundAsset>
local byId = {}
---@type table<NVGContextWrapper, MapBackgroundContext>
local contexts = {}
---@type table<string, MapBackgroundResource>
local resources = {}
local generation = 0
---@type string|nil
local lastValidationError = nil
local INSTANCE_FIELDS = { id = true, assetId = true, x = true, y = true, width = true }

---@param value any
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---@param value any
---@return boolean
local function positiveInteger(value)
    return finite(value) and value >= 1 and value % 1 == 0
end

---@param asset MapBackgroundAsset
---@return MapBackgroundAsset
local function copyAsset(asset)
    return {
        id = asset.id, name = asset.name, path = asset.path,
        pixelWidth = asset.pixelWidth, pixelHeight = asset.pixelHeight,
        imageWidth = asset.imageWidth, imageHeight = asset.imageHeight,
    }
end

-- 白名单仅来自可信源码；list/get 的副本不能修改内部路径或原图比例。
for _, asset in ipairs(catalog) do
    assert(type(asset) == "table" and type(asset.id) == "string" and asset.id ~= ""
        and type(asset.name) == "string" and type(asset.path) == "string" and asset.path ~= ""
        and positiveInteger(asset.pixelWidth) and positiveInteger(asset.pixelHeight),
        "[地图背景] data.backgrounds 目录条目无效")
    assert(not byId[asset.id], "[地图背景] 目录资源 ID 重复：" .. asset.id)
    assert((asset.imageWidth == nil and asset.imageHeight == nil)
        or (positiveInteger(asset.imageWidth) and positiveInteger(asset.imageHeight)),
        "[地图背景] 运行图片尺寸必须成对提供正整数：" .. asset.id)
    local entry = copyAsset(asset)
    assets[#assets + 1] = entry
    byId[entry.id] = entry
end

---@return MapBackgroundAsset[] 独立目录快照，不代表图片已加载成功
function B.list()
    local result = {} ---@type MapBackgroundAsset[]
    for i, asset in ipairs(assets) do result[i] = copyAsset(asset) end
    return result
end

---@param assetId string
---@return MapBackgroundAsset|nil 独立目录快照；未知 ID 返回 nil
function B.get(assetId)
    local asset = byId[assetId]
    return asset and copyAsset(asset) or nil
end

--- JSON 预检：只接受稠密数组与五个实例字段，绝不静默丢弃无效条目。
---@param images any
---@return boolean valid
---@return string|nil error
function B.validate(images)
    if type(images) ~= "table" or getmetatable(images) ~= nil then
        return false, "backgroundImages 必须是普通数组"
    end
    local count = 0
    for key in next, images do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 64 then
            return false, "backgroundImages 只接受 1 基数组，最多 64 个实例"
        end
        count = count + 1
    end
    local ids = {} ---@type table<string, boolean>
    for i = 1, count do
        local image = rawget(images, i)
        local prefix = "backgroundImages[" .. i .. "]"
        if type(image) ~= "table" or getmetatable(image) ~= nil then
            return false, prefix .. " 必须是普通实例表；数组不能有空洞"
        end
        for field in next, image do
            if not INSTANCE_FIELDS[field] then
                return false, prefix .. " 不接受未知字段：" .. tostring(field)
            end
        end
        if type(image.id) ~= "string" or image.id == "" then
            return false, prefix .. ".id 必须是非空字符串"
        end
        if ids[image.id] then return false, prefix .. ".id 重复：" .. image.id end
        if type(image.assetId) ~= "string" or not byId[image.assetId] then
            return false, prefix .. ".assetId 不在背景资源目录中"
        end
        if not finite(image.x) or image.x < -1e7 or image.x > 1e7
            or not finite(image.y) or image.y < -1e7 or image.y > 1e7 then
            return false, prefix .. ".x/y 必须是 ±10000000 范围内的有限米数"
        end
        if not finite(image.width) or image.width < 0.1 or image.width > 10000 then
            return false, prefix .. ".width 必须是 0.1..10000 范围内的有限米数"
        end
        ids[image.id] = true
    end
    return true, nil
end

--- 验证失败抛错，成功时拷贝数组及每个实例；不修改源世界或沙箱数据。
---@param images any
---@return MapBackgroundImage[]
function B.normalize(images)
    local ok, err = B.validate(images)
    if not ok then error("[地图背景] " .. tostring(err), 2) end
    local result = {} ---@type MapBackgroundImage[]
    for i, image in ipairs(images) do
        result[i] = { id = image.id, assetId = image.assetId, x = image.x, y = image.y, width = image.width }
    end
    return result
end

---@param image MapBackgroundImage
---@return number 高度，米；采用原始 pixelWidth/pixelHeight，不采用缩小运行图的舍入比例
function B.height(image)
    assert(type(image) == "table" and type(image.assetId) == "string", "[地图背景] height 缺少资源 ID")
    local asset = byId[image.assetId]
    assert(asset, "[地图背景] height 未知资源 ID：" .. image.assetId)
    assert(finite(image.width) and image.width >= 0.1 and image.width <= 10000,
        "[地图背景] height 需要 0.1..10000 范围内的有限宽度")
    return image.width * asset.pixelHeight / asset.pixelWidth
end

---@param context MapBackgroundContext
---@param asset MapBackgroundAsset
---@param resource MapBackgroundResource
local function loadImage(context, asset, resource)
    if not context.alive or not resource.ready or context.images[asset.id] then return end
    local image = { handle = 0, width = 0, height = 0 } ---@type MapBackgroundHandle
    -- 在尝试加载之前登记，失败也缓存，防止逐帧创建/解码。
    context.images[asset.id] = image
    local ok, handle = pcall(nvgCreateImage, context.vg, asset.path, 0)
    if not ok or not positiveInteger(handle) then
        image.error = "背景图片读取失败：" .. asset.path .. (ok and "" or "（" .. tostring(handle) .. "）")
    else
        image.handle = handle
        local sizeOK, width, height = pcall(nvgImageSize, context.vg, handle)
        local expectedWidth = asset.imageWidth or asset.pixelWidth
        local expectedHeight = asset.imageHeight or asset.pixelHeight
        if not sizeOK or not positiveInteger(width) or not positiveInteger(height)
            or width ~= expectedWidth or height ~= expectedHeight then
            image.error = "背景图片真实尺寸不符：" .. asset.path .. "（预期 "
                .. expectedWidth .. "×" .. expectedHeight .. "，读取 " .. tostring(width) .. "×" .. tostring(height) .. "）"
        elseif math.abs(width * asset.pixelHeight - height * asset.pixelWidth) > asset.pixelWidth then
            -- 缩小图的高度四舍五入允许最多 1 像素；不接受裁切图/错误宽高比。
            image.error = "背景图片与原图比例不符：" .. asset.path
        else
            image.width, image.height = width, height
            print(string.format("[地图背景] 首载真实整图：%s，%d×%d（原图 %d×%d）",
                asset.path, width, height, asset.pixelWidth, asset.pixelHeight))
        end
        if image.error then
            local deleted, deleteError = pcall(nvgDeleteImage, context.vg, handle)
            if deleted then image.handle = 0
            else print("[地图背景] 释放无效句柄失败：" .. tostring(deleteError)) end
        end
    end
    if image.error then print("[地图背景] " .. image.error) end
end

---@param resource MapBackgroundResource
local function loadContexts(resource)
    for _, context in pairs(contexts) do
        for _, asset in ipairs(assets) do
            if asset.path == resource.path then loadImage(context, asset, resource) end
        end
    end
end

---@param resource MapBackgroundResource
local function requestResource(resource)
    if resource.requested then return end
    resource.requested = true
    local existsOK, exists = pcall(function() return cache:Exists(resource.path) end)
    if existsOK and exists then
        resource.ready = true
        loadContexts(resource)
        return
    end
    resource.busy = true
    local ticket, completed = generation, false
    local ok, group = pcall(function()
        return cache:DownloadResources({ resource.path }, function(success)
            completed = true
            if ticket ~= generation or resources[resource.path] ~= resource then return end
            resource.busy, resource.group = false, nil
            local localOK, localExists = pcall(function() return cache:Exists(resource.path) end)
            if success and localOK and localExists then
                resource.ready = true
                loadContexts(resource)
            else
                resource.error = "背景图片下载未就绪或失败：" .. resource.path
                print("[地图背景] " .. resource.error)
            end
        end)
    end)
    if not completed and ok then resource.group = group end
    if not ok then
        resource.busy, resource.group = false, nil
        resource.error = "无法请求背景图片：" .. resource.path .. "（" .. tostring(group) .. "）"
        print("[地图背景] " .. resource.error)
    end
end

---@param vg NVGContextWrapper
---@return MapBackgroundContext
local function attachContext(vg)
    local context = contexts[vg]
    if not context then
        context = { vg = vg, alive = true, images = {} }
        contexts[vg] = context
        for _, asset in ipairs(assets) do
            local resource = resources[asset.path]
            if not resource then
                resource = { path = asset.path, requested = false, ready = false, busy = false }
                resources[asset.path] = resource
            end
            requestResource(resource)
            loadImage(context, asset, resource)
        end
    end
    return context
end

---@param context MapBackgroundContext
---@param asset MapBackgroundAsset
---@return MapBackgroundHandle|nil
---@return string|nil
local function readyImage(context, asset)
    local image = context.images[asset.id]
    if image and not image.error and image.handle > 0 then return image, nil end
    local resource = resources[asset.path]
    return nil, (image and image.error) or (resource and resource.error) or ("背景图片加载中：" .. asset.path)
end

--- 可在启动时预热；对已绑定 context 幂等。true 仅代表该 context 全部真实图已就绪。
---@param vg NVGContextWrapper
---@return boolean
---@return string|nil
function B.init(vg)
    if not vg then return false, "背景初始化缺少 NanoVG context" end
    local context = attachContext(vg)
    for _, asset in ipairs(assets) do
        local image, err = readyImage(context, asset)
        if not image then return false, err end
    end
    return true, nil
end

---@param vg NVGContextWrapper
---@param handle integer
---@param x number
---@param y number
---@param width number
---@param height number
---@param opacity number
---@param hardEdges? boolean
local function paintImage(vg, handle, x, y, width, height, opacity, hardEdges)
    nvgSave(vg)
    -- 地图整图矩形按精确边界覆盖；形状软边会使相接背景在亚像素位置漏底。
    -- 仅关闭矩形抗锯齿，不改变图片的默认过滤；UI 缩略图保留原软边。
    if hardEdges then nvgShapeAntiAlias(vg, 0) end
    nvgBeginPath(vg)
    nvgRect(vg, x, y, width, height)
    nvgFillPaint(vg, nvgImagePattern(vg, x, y, width, height, 0, handle, opacity))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 整张图直接投影。保留数组顺序、上方为 +Y；不读取编辑 visible/locked。
---@param vg NVGContextWrapper
---@param images MapBackgroundImage[]
---@param R TilesetProjection
---@param opacity? number 默认 1，范围 0..1
---@return boolean 所有视野内实例均成功绘制；加载中/失败不会宣称成功
---@return string|nil
function B.draw(vg, images, R, opacity)
    local valid, validationError = B.validate(images)
    if not valid then
        if lastValidationError ~= validationError then
            lastValidationError = validationError
            print("[地图背景] " .. tostring(validationError))
        end
        return false, validationError
    end
    if not vg or type(R) ~= "table" or not finite(R.ppu) or R.ppu <= 0
        or not finite(R.camX) or not finite(R.camY) or not finite(R.screenW) or R.screenW <= 0
        or not finite(R.screenH) or R.screenH <= 0 then
        return false, "背景绘制需要有效 context 和与 TS 相同的米制投影"
    end
    local alpha = opacity == nil and 1 or opacity
    if not finite(alpha) or alpha < 0 or alpha > 1 then return false, "背景 opacity 必须是 0..1 的有限数" end
    if #images == 0 or alpha == 0 then return true, nil end
    local context = attachContext(vg)
    local success = true
    ---@type string|nil
    local firstError = nil
    nvgSave(vg)
    nvgIntersectScissor(vg, 0, 0, R.screenW, R.screenH)
    for _, image in ipairs(images) do
        local height = B.height(image)
        local widthPixels, heightPixels = image.width * R.ppu, height * R.ppu
        local x = R.screenW / 2 + (image.x - image.width / 2 - R.camX) * R.ppu
        local y = R.screenH / 2 - (image.y + height / 2 - R.camY) * R.ppu
        if not finite(x) or not finite(y) or not finite(widthPixels) or not finite(heightPixels) then
            success, firstError = false, firstError or "背景投影结果不是有限数"
        elseif x < R.screenW and x + widthPixels > 0 and y < R.screenH and y + heightPixels > 0 then
            local handle, err = readyImage(context, byId[image.assetId])
            if handle then paintImage(vg, handle.handle, x, y, widthPixels, heightPixels, alpha, true)
            else success, firstError = false, firstError or err end
        end
    end
    nvgRestore(vg)
    return success, firstError
end

--- UI 缩略图：在给定屏幕矩形里 contain 整图，居中、不切片、不裁图、不改原图比例。
---@param vg NVGContextWrapper
---@param assetId string
---@param x number
---@param y number
---@param width number
---@param height number
---@param opacity? number
---@return boolean
---@return string|nil
function B.drawThumbnail(vg, assetId, x, y, width, height, opacity)
    local asset = byId[assetId]
    if not asset then return false, "缩略图资源不在背景目录中" end
    local alpha = opacity == nil and 1 or opacity
    if not vg or not finite(x) or not finite(y) or not finite(width) or width <= 0
        or not finite(height) or height <= 0 or not finite(alpha) or alpha < 0 or alpha > 1 then
        return false, "缩略图需要有效 context、有限正尺寸和 0..1 opacity"
    end
    local image, err = readyImage(attachContext(vg), asset)
    if not image then return false, err end
    local drawWidth = math.min(width, height * asset.pixelWidth / asset.pixelHeight)
    local drawHeight = drawWidth * asset.pixelHeight / asset.pixelWidth
    local drawX, drawY = x + (width - drawWidth) / 2, y + (height - drawHeight) / 2
    if not finite(drawX) or not finite(drawY) then return false, "缩略图投影结果不是有限数" end
    if alpha == 0 then return true, nil end
    nvgSave(vg)
    nvgIntersectScissor(vg, x, y, width, height)
    paintImage(vg, image.handle, drawX, drawY, drawWidth, drawHeight, alpha)
    nvgRestore(vg)
    return true, nil
end

--- 必须在调用方删除 world/UI NanoVG contexts 前调用；不删除调用方的 context。
function B.shutdown()
    generation = generation + 1
    for _, context in pairs(contexts) do context.alive = false end
    for _, resource in pairs(resources) do
        local group = resource.group
        resource.group, resource.busy = nil, false
        if group then
            local ok, err = pcall(function() cache:CancelDownloadGroup(group) end)
            if not ok then print("[地图背景] 取消下载失败：" .. tostring(err)) end
        end
    end
    for vg, context in pairs(contexts) do
        for _, image in pairs(context.images) do
            if image.handle > 0 then
                local ok, err = pcall(nvgDeleteImage, vg, image.handle)
                if not ok then print("[地图背景] 释放图片句柄失败：" .. tostring(err)) end
            end
        end
    end
    contexts, resources, lastValidationError = {}, {}, nil
end

return B
