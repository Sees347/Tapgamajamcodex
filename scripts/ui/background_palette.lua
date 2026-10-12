-- 背景素材面板：控件树只构建一次，实例与属性在 EB.revision 改变时同步。
-- 所有修改交给 editor_backgrounds，背景保存在 metadata，不写地图格或碰撞。
local UI = require "urhox-libs/UI"
local EB = require "core.editor_backgrounds"
local B = require "core.map_backgrounds"

local COLORS = {
    surface = { 36, 39, 44, 255 }, inset = { 27, 30, 34, 255 },
    border = { 64, 69, 77, 255 }, selected = { 58, 103, 153, 255 },
    text = { 225, 228, 233, 255 }, muted = { 157, 165, 176, 255 },
}
local ASSET_ID = "industrial_backdrop"

local function label(text, muted)
    return UI.Label { text = text, fontSize = 11, width = "100%",
        whiteSpace = "normal", wordBreak = "break-word", fontColor = muted and COLORS.muted or COLORS.text }
end
local function button(text, callback, danger)
    return UI.Button { text = text, width = "100%", height = 32, minWidth = 0,
        paddingHorizontal = 6, borderRadius = 3, fontSize = 11,
        backgroundColor = danger and { 102, 51, 47, 255 } or COLORS.surface,
        textColor = COLORS.text, borderWidth = 1, borderColor = COLORS.border, onClick = callback }
end
local function field(submit)
    return UI.TextField { value = "", width = "100%", minWidth = 0, height = 34,
        fontSize = 11, paddingHorizontal = 7, borderRadius = 3,
        backgroundColor = COLORS.inset, filledBgColor = COLORS.inset, focusedBgColor = COLORS.inset,
        textColor = COLORS.text, borderColor = COLORS.border, onSubmit = submit }
end
local function finite(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

--- 指针是 UI 基准像素；背景控制器只接受系统逻辑像素（physical / DPR）。
local function screenPoint(x, y)
    local factor = UI.GetScale() / math.max(0.01, graphics:GetDPR())
    return x * factor, y * factor
end

---@class EditorBackgroundThumbnailProps : WidgetProps
---@field assetId string
---@field onBegin fun(sx:number,sy:number)
---@field onMove fun(sx:number,sy:number)
---@field onEnd fun(sx:number,sy:number)
---@field onCancel fun()
---@class EditorBackgroundThumbnail : Widget
---@overload fun(props: EditorBackgroundThumbnailProps): EditorBackgroundThumbnail
---@field props EditorBackgroundThumbnailProps
---@field pointerId_ number?
local Thumbnail = UI.Widget:Extend("EditorBackgroundThumbnail")

function Thumbnail:Init(props)
    self.pointerId_ = nil
    props.width, props.height, props.flexShrink = "100%", 86, 0
    props.backgroundColor, props.borderWidth, props.borderColor = COLORS.inset, 1, COLORS.border
    props.borderRadius = 3
    -- LSP 对子类父方法的隐式 self 推导不正确；调用签名已核实。
    local init = UI.Widget.Init --[[@as fun(...: any)]]
    init(self, props)
end

---@param event PointerEvent
function Thumbnail:OnPointerDown(event)
    if not event:IsPrimaryButton() or not event.isPrimary or self.pointerId_ ~= nil then return end
    self.pointerId_ = event.pointerId
    self.state.isDragging = false
    if event.pointerType == "touch" then
        -- 手势识别早于UI命中；重设此指针目标，快速划出缩略图时不被父滚动区抢走。
        local seed = event:Clone()
        seed.target = self --[[@as Widget]]
        seed.x, seed.y = event.x * UI.GetScale(), event.y * UI.GetScale()
        UI.Gesture.HandlePointerDown(seed)
    end
    UI.ClearFocus()
    local sx, sy = screenPoint(event.x, event.y)
    self.props.onBegin(sx, sy)
    event:PreventDefault()
    event:StopPropagation()
end

---@param event PointerEvent
function Thumbnail:OnPointerMove(event)
    if self.pointerId_ ~= event.pointerId then return end
    local sx, sy = screenPoint(event.x, event.y)
    self.props.onMove(sx, sy)
end

---@param event PointerEvent
function Thumbnail:OnPointerUp(event)
    if self.pointerId_ ~= event.pointerId or not event:IsPrimaryButton() then return end
    self.pointerId_ = nil
    self.state.isDragging = false
    local sx, sy = screenPoint(event.x, event.y)
    -- main 也会处理 up；EB.endPointer 必须幂等，已完成的拖放不会再次放置。
    self.props.onEnd(sx, sy)
    event:PreventDefault()
    event:StopPropagation()
end

---@param event PointerEvent
function Thumbnail:OnPointerCancel(event)
    if self.pointerId_ ~= event.pointerId then return end
    self:Cancel()
end

function Thumbnail:Cancel()
    if self.pointerId_ ~= nil then self.props.onCancel() end
    self.pointerId_ = nil
    self.state.isDragging = false
end

-- 触摸拖素材不能变成外层滚动；move 只预览，最终提交由 endPointer 完成。
---@param event GestureEvent
---@return boolean
function Thumbnail:OnPanStart(event)
    if self.pointerId_ == nil then return false end
    self.state.isDragging = true
    return true
end
---@param event GestureEvent
function Thumbnail:OnPanMove(event)
    if self.pointerId_ == nil then return end
    local sx, sy = screenPoint(event.x, event.y)
    self.props.onMove(sx, sy)
end
---@param event GestureEvent
function Thumbnail:OnPanEnd(event)
    if self.pointerId_ == nil then return end
    self.pointerId_ = nil
    self.state.isDragging = false
    local sx, sy = screenPoint(event.x, event.y)
    self.props.onEnd(sx, sy)
end

---@param vg NVGContextWrapper
function Thumbnail:Render(vg)
    self:RenderFullBackground(vg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 8 or l.h <= 8 then return end
    -- drawThumbnail 在传入的 UI context 内缓存图片，绝不复用世界 context 的句柄。
    nvgSave(vg)
    nvgIntersectScissor(vg, l.x + 4, l.y + 4, l.w - 8, l.h - 8)
    B.drawThumbnail(vg, self.props.assetId, l.x + 4, l.y + 4, l.w - 8, l.h - 8)
    nvgRestore(vg)
end

---@class EditorBackgroundPaletteProps : PanelProps
---@field notify? fun(text:string)
---@field onChange? fun()
---@field isCanvasPoint? fun(sx:number,sy:number):boolean
---@field getRenderer? fun():table
---@class EditorBackgroundPalette : Panel
---@overload fun(props?: EditorBackgroundPaletteProps): EditorBackgroundPalette
---@field props EditorBackgroundPaletteProps
---@field notify_ fun(text:string)
---@field onChange_ fun()
---@field revision_ integer
---@field syncing_ boolean
---@field geometry_ string
---@field thumbnail_ EditorBackgroundThumbnail
---@field pending_ Label
---@field placed_ Dropdown
---@field selected_ Label
---@field dimensions_ Label
---@field width_ TextField
---@field x_ TextField
---@field y_ TextField
---@field editControls_ Panel
local BackgroundPalette = UI.Panel:Extend("EditorBackgroundPalette")

function BackgroundPalette:Init(props)
    props = props or {}
    self.notify_ = props.notify or function(text) print("[背景素材] " .. text) end
    self.onChange_ = props.onChange or function() end
    self.revision_, self.syncing_, self.geometry_ = -1, false, ""
    props.width, props.gap, props.minWidth = "100%", 7, 0
    local init = UI.Panel.Init --[[@as fun(...: any)]]
    init(self, props)

    self.pending_ = label("", true)
    self.thumbnail_ = Thumbnail {
        assetId = ASSET_ID,
        onBegin = function(sx, sy)
            local ok, message = EB.beginAssetDrag(ASSET_ID, sx, sy)
            if ok == false then self.notify_(tostring(message or "无法拖放背景。")) end
            self:Refresh(false)
            self.onChange_()
        end,
        onMove = function(sx, sy) EB.movePointer(sx, sy, self:GetRenderer()) end,
        onEnd = function(sx, sy)
            local allowed = self.props.isCanvasPoint or function(x, y)
                -- 延迟引用，避免 map_editor -> tile_palette -> 本模块 -> map_editor 循环。
                return require("ui.map_editor").isCanvasPoint(x, y)
            end
            local _, message = EB.endPointer(sx, sy, self:GetRenderer(), allowed)
            if message and message ~= "" then self.notify_(tostring(message)) end
            self:Refresh(false)
            self.onChange_()
        end,
        onCancel = function() EB.cancel() end,
    }
    local chooseAsset = button("点选放置", function()
        self:CloseOverlays()
        local ok, message = EB.selectAsset(ASSET_ID)
        self.notify_(tostring(message or (ok and "点击中央画布放置背景。" or "无法选择背景素材。")))
        self:Refresh(false)
        self.onChange_()
    end)
    self:AddChild(label("背景素材"))
    self:AddChild(self.thumbnail_)
    self:AddChild(label("工业背景 · 6443 × 2106 像素"))
    self:AddChild(chooseAsset)
    self:AddChild(self.pending_)
    self:AddChild(label("按住缩略图拖到画布松开放置；或点「点选放置」后点击画布。", true))
    self:AddChild(label("背景只显示，无碰撞。不会替换瓦片笔刷或图集。", true))

    self.placed_ = UI.Dropdown {
        width = "100%", minWidth = 0, height = 34, fontSize = 11, options = {},
        placeholder = "尚未放置背景", value = "", maxVisibleItems = 6,
        triggerBgColor = COLORS.inset, popupBgColor = COLORS.surface, popupBorderColor = COLORS.border,
        onChange = function(_, id)
            -- SetValue 也会触发 onChange，刷新不能重新选择实例或递增 revision。
            if self.syncing_ or not id or id == "" then return end
            EB.cancel()
            local ok, message = EB.selectInstance(id)
            if ok == false then self.notify_(tostring(message or "背景实例已失效。")) end
            self:Refresh(false)
            self.onChange_()
        end,
    }
    self.selected_, self.dimensions_ = label("尚未选中背景。", true), label("", true)
    self.width_ = field(function() self:ApplyWidth() end)
    self.x_ = field(function() self:ApplyPosition() end)
    self.y_ = field(function() self:ApplyPosition() end)
    self.editControls_ = UI.Panel { width = "100%", gap = 7, children = {
        self.dimensions_, label("宽度（m）"), self.width_, button("应用宽度", function() self:ApplyWidth() end),
        UI.SimpleGrid { width = "100%", columns = 2, gap = 5, children = {
            button("缩小 20%", function() self:ScaleWidth(0.8) end),
            button("放大 20%", function() self:ScaleWidth(1.2) end),
        } },
        label("保持中心等比缩放；也可拖动画布四角手柄。", true),
        UI.SimpleGrid { width = "100%", columns = 2, gap = 5, children = {
            UI.Panel { minWidth = 0, gap = 4, children = { label("X（m）"), self.x_ } },
            UI.Panel { minWidth = 0, gap = 4, children = { label("Y（m）"), self.y_ } },
        } },
        button("应用位置", function() self:ApplyPosition() end),
        button("定位已选背景", function()
            local ok, message = EB.focusSelected(self:GetRenderer())
            if message then self.notify_(tostring(message))
            elseif ok == false then self.notify_("请先选中一个背景实例。") end
            self.onChange_()
        end),
        button("删除背景（仅此实例）", function()
            self:CloseOverlays()
            local ok, message = EB.removeSelected()
            self.notify_(tostring(message or (ok and "已删除所选背景，其他实例不受影响。" or "没有可删除的背景。")))
            self:Refresh(false)
            self.onChange_()
        end, true),
    } }
    self:AddChild(label("已放背景"))
    self:AddChild(self.placed_)
    self:AddChild(self.selected_)
    self:AddChild(self.editControls_)
    self:AddChild(label("背景工具下点击画布背景选取，拖动可移动。属性仅修改所选实例，完整导出保留背景元数据。", true))
    self:Refresh(true)
end

---@return table
function BackgroundPalette:GetRenderer()
    if self.props.getRenderer then return self.props.getRenderer() end
    return require "core/render"
end

function BackgroundPalette:ApplyWidth()
    local width = finite(self.width_:GetValue())
    if not width or width < 0.1 or width > 10000 then self.notify_("宽度必须为 0.1–10000 范围内的有限数值，单位为米。"); return end
    local ok, message = EB.setWidth(width)
    self.notify_(tostring(message or (ok and "背景已等比缩放。" or "无法调整背景宽度。")))
    self:Refresh(false)
    self.onChange_()
end

---@param factor number
function BackgroundPalette:ScaleWidth(factor)
    local selected = EB.selected()
    if not selected then self.notify_("请先选中一个背景实例。"); return end
    local ok, message = EB.setWidth(selected.width * factor)
    if message then self.notify_(tostring(message))
    elseif ok == false then self.notify_("无法调整背景宽度。") end
    self:Refresh(false)
    self.onChange_()
end

function BackgroundPalette:ApplyPosition()
    local x, y = finite(self.x_:GetValue()), finite(self.y_:GetValue())
    if not x or not y then self.notify_("X / Y 必须为有限数值，单位为米。"); return end
    local ok, message = EB.moveTo(x, y)
    self.notify_(tostring(message or (ok and "背景位置已更新。" or "无法移动背景。")))
    self:Refresh(false)
    self.onChange_()
end

--- 刷新仅同步现有控件；不逐帧重建列表/表单，不覆盖未提交的输入。
---@param force? boolean
function BackgroundPalette:Refresh(force)
    -- list 同步换图/导入后的 metadata 引用，可能在这里递增 EB.revision。
    local images = EB.list()
    if not force and self.revision_ == EB.revision then return end
    self.revision_ = EB.revision
    self.syncing_ = true
    local options = { { value = "", label = "请选择背景实例" } }
    for index, image in ipairs(images) do
        options[#options + 1] = { value = image.id,
            label = ("%d · 工业背景 · %s"):format(index, tostring(image.id)) }
    end
    self.placed_:SetOptions(options)
    self.placed_:SetValue(EB.selectedId or "")
    self.placed_.props.placeholder = #options > 1 and "请选择背景实例" or "尚未放置背景"
    self.placed_:SetDisabled(#options == 1)
    local pending = EB.pendingAsset and EB.pendingAsset ~= ""
    self.pending_:SetText(pending and "待放置：工业背景 · 点击画布" or "可多次放置同一素材，各实例独立编辑。")
    self.thumbnail_:SetStyle({ borderColor = EB.pendingAsset == ASSET_ID and COLORS.selected or COLORS.border })
    local selected = EB.selected()
    self.editControls_:SetVisible(selected ~= nil)
    self.selected_:SetText(selected and "已选：" .. tostring(selected.id) or "尚未选中背景，可从列表或画布选取。")
    local geometry = selected and ("%s|%.17g|%.17g|%.17g"):format(selected.id, selected.x, selected.y, selected.width) or ""
    if force or self.geometry_ ~= geometry then
        self.geometry_ = geometry
        self.width_:SetValue(selected and ("%.6g"):format(selected.width) or "")
        self.x_:SetValue(selected and ("%.6g"):format(selected.x) or "")
        self.y_:SetValue(selected and ("%.6g"):format(selected.y) or "")
        -- catalog 的唯一图片宽高已核实，面板显示比例不涉及世界图片句柄。
        self.dimensions_:SetText(selected and ("尺寸 %.3f × %.3f m · 无碰撞"):format(selected.width, B.height(selected)) or "")
    end
    self.syncing_ = false
end

--- 关闭浮层/隐藏面板/切换模式时取消拖放，不能用 endPointer(false) 提交移动。
function BackgroundPalette:CloseOverlays()
    self.placed_:Close()
    self.thumbnail_:Cancel()
    EB.cancel()
end

return BackgroundPalette
