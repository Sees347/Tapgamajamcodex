-- 整张背景编辑：独立实例、中心米坐标、等比四角缩放；拖动预览不写地图或存档。
local ME = require "core.map_editor"
local B = require "core.map_backgrounds"
local EB = { revision = 0, selectedId = "", pendingAsset = "", dragging = false }
---@type table?
local metadataRef = nil
---@type {kind:string,assetId:string,id:string,x:number,y:number,width:number,startX:number,startY:number,anchorX:number,anchorY:number,signX:number,signY:number}?
local drag = nil

local function sync()
    if metadataRef ~= ME.metadata then
        metadataRef = ME.metadata
        EB.selectedId, EB.pendingAsset = "", ""
        drag, EB.dragging = nil, false
        EB.revision = EB.revision + 1
    end
end
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function editable()
    local state = ME.getLayerState("background")
    return ME.active and state and state.visible and not state.locked
end
local function changed()
    ME.markDirty()
    EB.revision = EB.revision + 1
end
---@return MapBackgroundImage[]
function EB.list()
    sync()
    return ME.metadata.backgroundImages or {}
end
---@return MapBackgroundImage?
function EB.selected()
    for _, image in ipairs(EB.list()) do if image.id == EB.selectedId then return image end end
    return nil
end
function EB.cancel()
    if drag or EB.pendingAsset ~= "" then EB.revision = EB.revision + 1 end
    drag, EB.dragging, EB.pendingAsset = nil, false, ""
end
function EB.selectInstance(id)
    sync(); EB.cancel()
    for _, image in ipairs(EB.list()) do
        if image.id == id then
            EB.selectedId, EB.pendingAsset = id, ""
            ME.tool = "background"; ME.setLayer("background")
            EB.revision = EB.revision + 1
            return true, "已选中背景，可拖动或拖四角等比缩放"
        end
    end
    return false, "背景实例不存在"
end
function EB.selectAsset(assetId)
    sync(); EB.cancel()
    if not B.get(assetId) then return false, "背景素材不存在" end
    EB.pendingAsset, EB.selectedId = assetId, ""
    ME.tool = "background"; ME.setLayer("background")
    EB.revision = EB.revision + 1
    return true, "点击画布放置背景；放置后可拖动和等比缩放"
end
local function world(sx, sy, R)
    return R.camX + (sx - R.screenW / 2) / R.ppu, R.camY - (sy - R.screenH / 2) / R.ppu
end
local function defaultWidth()
    return math.max(0.1, math.min(10000, math.min(ME.cols * ME.tile, 60)))
end
function EB.beginAssetDrag(assetId, sx, sy)
    local ok, message = EB.selectAsset(assetId)
    if not ok then return false, message end
    if not editable() then EB.pendingAsset = ""; return false, "请先显示并解锁背景装饰层" end
    local used, previewId = {}, "preview"
    local images = EB.list()
    if #images >= 64 then EB.cancel(); return false, "最多放置64张背景" end
    for _, image in ipairs(images) do used[image.id] = true end
    while used[previewId] do previewId = previewId .. "_" end
    drag = { kind = "asset", assetId = assetId, id = previewId, x = 0, y = 0, width = defaultWidth(),
        startX = sx, startY = sy, anchorX = 0, anchorY = 0, signX = 1, signY = 1 }
    EB.dragging = true
    return true, "拖至地图画布后松开放置背景"
end
local function copy(image)
    return { id = image.id, assetId = image.assetId, x = image.x, y = image.y, width = image.width }
end
local function corners(image)
    local halfW, halfH = image.width / 2, B.height(image) / 2
    return {
        { x = image.x - halfW, y = image.y + halfH, signX = -1, signY = 1 },
        { x = image.x + halfW, y = image.y + halfH, signX = 1, signY = 1 },
        { x = image.x - halfW, y = image.y - halfH, signX = -1, signY = -1 },
        { x = image.x + halfW, y = image.y - halfH, signX = 1, signY = -1 },
    }
end
function EB.beginPointer(sx, sy, R)
    sync()
    if not editable() then return false, "请先显示并解锁背景装饰层" end
    if EB.pendingAsset ~= "" then
        local ok, message = EB.beginAssetDrag(EB.pendingAsset, sx, sy)
        if ok then EB.movePointer(sx, sy, R) end
        return ok, message
    end
    local selected = EB.selected()
    if selected then
        for _, corner in ipairs(corners(selected)) do
            local cx, cy = R.w2s(corner.x, corner.y)
            if math.abs(cx - sx) <= 12 and math.abs(cy - sy) <= 12 then
                drag = { kind = "resize", assetId = selected.assetId, id = selected.id,
                    x = selected.x, y = selected.y, width = selected.width, startX = sx, startY = sy,
                    anchorX = selected.x - corner.signX * selected.width / 2,
                    anchorY = selected.y - corner.signY * B.height(selected) / 2,
                    signX = corner.signX, signY = corner.signY }
                EB.dragging = true
                return true, "拖四角保持原图比例缩放"
            end
        end
    end
    local wx, wy = world(sx, sy, R)
    local images = EB.list()
    for index = #images, 1, -1 do
        local image = images[index]
        if math.abs(wx - image.x) <= image.width / 2 and math.abs(wy - image.y) <= B.height(image) / 2 then
            EB.selectInstance(image.id)
            drag = { kind = "move", assetId = image.assetId, id = image.id, x = image.x, y = image.y, width = image.width,
                startX = wx - image.x, startY = wy - image.y, anchorX = 0, anchorY = 0, signX = 1, signY = 1 }
            EB.dragging = true
            return true, "拖动背景移动位置"
        end
    end
    EB.selectedId = ""; EB.revision = EB.revision + 1
    return false, "点击背景选中；可从右侧素材区拖入新背景"
end
function EB.movePointer(sx, sy, R)
    if not drag or not finite(R.ppu) or R.ppu <= 0 then return end
    local wx, wy = world(sx, sy, R)
    if drag.kind == "resize" then
        local asset = B.get(drag.assetId)
        if not asset then return end
        local ratio = asset.pixelHeight / asset.pixelWidth
        local projected = ((wx - drag.anchorX) * drag.signX + (wy - drag.anchorY) * drag.signY * ratio) / (1 + ratio * ratio)
        local width = math.max(0.1, math.min(10000, projected))
        drag.width = width
        drag.x = drag.anchorX + drag.signX * width / 2
        drag.y = drag.anchorY + drag.signY * width * ratio / 2
    elseif drag.kind == "move" then
        drag.x, drag.y = wx - drag.startX, wy - drag.startY
    else drag.x, drag.y = wx, wy end
end
local function nextId()
    local used = {}
    for _, image in ipairs(EB.list()) do used[image.id] = true end
    for i = 1, 65 do if not used["background_" .. i] then return "background_" .. i end end
    return ""
end
function EB.endPointer(sx, sy, R, allowed)
    if not drag then return false, "" end
    local inside = type(allowed) == "function" and allowed(sx, sy) or allowed == true
    if not inside or not editable() then EB.cancel(); return false, "未放入画布，拖动已取消" end
    EB.movePointer(sx, sy, R)
    local preview = copy(drag)
    if drag.kind == "asset" then
        local images = EB.list()
        if #images >= 64 then EB.cancel(); return false, "最多放置64张背景" end
        preview.id = nextId()
        local valid, err = B.validate({ preview })
        if not valid then EB.cancel(); return false, err end
        ME.metadata.backgroundImages = ME.metadata.backgroundImages or {}
        table.insert(ME.metadata.backgroundImages, preview)
        EB.selectedId, EB.pendingAsset = preview.id, ""
        EB.cancel(); changed()
        print("[地图背景] 已放置 " .. preview.id .. "：" .. preview.width .. "米宽")
        return true, "背景已放置；拖四角等比缩放，拖内部移动"
    end
    local selected = EB.selected()
    if not selected then EB.cancel(); return false, "背景已不存在" end
    local valid, err = B.validate({ preview })
    if not valid then EB.cancel(); return false, err end
    local modified = selected.x ~= preview.x or selected.y ~= preview.y or selected.width ~= preview.width
    if modified then selected.x, selected.y, selected.width = preview.x, preview.y, preview.width end
    EB.cancel()
    if modified then changed() end
    return true, modified and "背景位置与等比尺寸已更新" or "已选中背景"
end
function EB.setWidth(width)
    local selected = EB.selected()
    if not selected then return false, "请先选中背景" end
    if not editable() then return false, "请先显示并解锁背景装饰层" end
    if not finite(width) or width < 0.1 or width > 10000 then return false, "背景宽度范围0.1–10000米" end
    EB.cancel()
    if selected.width ~= width then selected.width = width; changed() end
    return true, "背景已等比缩放，保持中心不变"
end
function EB.moveTo(x, y)
    local selected = EB.selected()
    if not selected then return false, "请先选中背景" end
    if not editable() then return false, "请先显示并解锁背景装饰层" end
    if not finite(x) or not finite(y) or math.abs(x) > 1e7 or math.abs(y) > 1e7 then return false, "位置必须为±10000000内的有限米坐标" end
    EB.cancel()
    if selected.x ~= x or selected.y ~= y then selected.x, selected.y = x, y; changed() end
    return true, "背景位置已更新"
end
function EB.removeSelected()
    local selected = EB.selected()
    if not selected then return false, "请先选中背景" end
    if not editable() then return false, "请先显示并解锁背景装饰层" end
    local remaining = {}
    for _, image in ipairs(EB.list()) do if image.id ~= selected.id then remaining[#remaining + 1] = image end end
    EB.cancel(); ME.metadata.backgroundImages = remaining; EB.selectedId = ""; changed()
    return true, "已移除选中背景，素材与其它图层保留"
end
function EB.focusSelected()
    local selected = EB.selected()
    if not selected then return false, "请先选中背景" end
    ME.camX, ME.camY = selected.x, selected.y
    return true, "镜头已定位选中背景"
end
---@return MapBackgroundImage[]
function EB.renderImages()
    sync()
    if not ME.getLayerState("background").visible then return {} end
    local result = {}
    for _, image in ipairs(EB.list()) do
        result[#result + 1] = drag and drag.id == image.id and copy(drag) or image
    end
    if drag and drag.kind == "asset" then result[#result + 1] = copy(drag) end
    return result
end
function EB.drawSelection(vg, R)
    if ME.tool ~= "background" or not ME.getLayerState("background").visible then return end
    local image = drag or EB.selected()
    if not image then return end
    local x, y = R.w2s(image.x - image.width / 2, image.y + B.height(image) / 2)
    nvgBeginPath(vg); nvgRect(vg, x, y, image.width * R.ppu, B.height(image) * R.ppu)
    nvgStrokeColor(vg, nvgRGBA(110, 190, 255, 255)); nvgStrokeWidth(vg, 2); nvgStroke(vg)
    for _, corner in ipairs(corners(image)) do
        local sx, sy = R.w2s(corner.x, corner.y)
        nvgBeginPath(vg); nvgRect(vg, sx - 5, sy - 5, 10, 10)
        nvgFillColor(vg, nvgRGBA(220, 240, 255, 255)); nvgFill(vg)
    end
end
return EB
