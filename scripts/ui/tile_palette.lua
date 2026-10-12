-- Unity Tile Palette 式资源浏览器。仅自定义瓦片图形使用 NanoVG 绘制；
-- 菜单、表单与文本留在 UI 控件树内，并使用 UI 管理的独立绘图上下文。
local UI = require "urhox-libs/UI"
local ME = require "core.map_editor"
local TS = require "core.tilesets"

local COLORS = {
    surface = { 36, 39, 44, 255 },
    inset = { 27, 30, 34, 255 },
    border = { 64, 69, 77, 255 },
    selected = { 58, 103, 153, 255 },
    text = { 225, 228, 233, 255 },
    muted = { 157, 165, 176, 255 },
}

---@class EditorTileGrid : Widget
---@field setId_ string
---@field cellSize_ number
---@field selecting_ boolean
---@field startCol_ integer
---@field startRow_ integer
---@field endCol_ integer
---@field endRow_ integer
---@field onSelection_ function
local TileGrid = UI.Widget:Extend("EditorTileGrid")

function TileGrid:Init(props)
    self.setId_ = props.setId or "builtin"
    self.cellSize_ = props.cellSize or 48
    self.selecting_ = false
    self.startCol_, self.startRow_, self.endCol_, self.endRow_ = 1, 1, 1, 1
    self.onSelection_ = props.onSelection
    props.width, props.height = 1, 1
    props.flexShrink = 0
    props.backgroundColor = COLORS.inset
    UI.Widget.Init(self, props)
    self:RefreshSize()
end

function TileGrid:RefreshSize()
    local def = TS.get(self.setId_)
    local columns = def and def.columns or 0
    local rows = def and def.rows or 0
    self:SetStyle({ width = math.max(1, columns * self.cellSize_), height = math.max(1, rows * self.cellSize_) })
end

function TileGrid:SetTileset(id)
    self.setId_ = id
    self.selecting_ = false
    self:RefreshSize()
end

function TileGrid:SetCellSize(size)
    self.cellSize_ = size
    self:RefreshSize()
end

--- 指针使用 UI 基准像素。绘制读取未滚动布局，命中读取滚动后布局；
--- 混用两种坐标会导致滚动后的瓦片框选位置错误。
function TileGrid:CellAt(x, y)
    local def = TS.get(self.setId_)
    if not def or def.count < 1 or def.columns < 1 or def.rows < 1 then return nil, nil end
    local l = self:GetAbsoluteLayoutForHitTest()
    local col = math.max(1, math.min(def.columns, math.floor((x - l.x) / self.cellSize_) + 1))
    local row = math.max(1, math.min(def.rows, math.floor((y - l.y) / self.cellSize_) + 1))
    if (row - 1) * def.columns + col > def.count then return nil, nil end
    return col, row
end

function TileGrid:ApplySelection()
    local def = TS.get(self.setId_)
    if not def or def.columns < 1 then return end
    local c0, r0 = math.min(self.startCol_, self.endCol_), math.min(self.startRow_, self.endRow_)
    local c1, r1 = math.max(self.startCol_, self.endCol_), math.max(self.startRow_, self.endRow_)
    local id = (r0 - 1) * def.columns + c0
    if self.onSelection_ then
        self.onSelection_(self.setId_, id, c1 - c0 + 1, r1 - r0 + 1, def.columns, TS.tileCollider(self.setId_, id))
    end
end

function TileGrid:OnPointerDown(event)
    if not event:IsPrimaryButton() then
        if self.parent then self.parent:OnPointerDown(event) end
        return
    end
    local col, row = self:CellAt(event.x, event.y)
    if not col then return end
    self.selecting_ = true
    self.startCol_, self.startRow_, self.endCol_, self.endRow_ = col, row, col, row
    self:ApplySelection()
    event:PreventDefault()
    event:StopPropagation()
end

---@param x number
---@param y number
function TileGrid:MoveSelection(x, y)
    if not self.selecting_ then return end
    local col, row = self:CellAt(x, y)
    if col then
        self.endCol_, self.endRow_ = col, row
        self:ApplySelection()
    end
end

function TileGrid:OnPointerMove(event)
    self:MoveSelection(event.x, event.y)
end

function TileGrid:OnPointerUp(event)
    self:MoveSelection(event.x, event.y)
    self.selecting_ = false
    self.state.isDragging = false
end

function TileGrid:OnPointerCancel(event)
    self.selecting_ = false
    self.state.isDragging = false
end

-- 触摸拖动用于框选，不交给外层 ScrollView 抢走手势。
-- 浏览图片仍可使用滚动条、滚轮或显式方向按钮。
---@param event GestureEvent
---@return boolean
function TileGrid:OnPanStart(event)
    if not self.selecting_ then return false end
    self.state.isDragging = true
    return true
end
---@param event GestureEvent
function TileGrid:OnPanMove(event)
    self:MoveSelection(event.x, event.y)
end
---@param event GestureEvent
function TileGrid:OnPanEnd(event)
    self:MoveSelection(event.x, event.y)
    self.selecting_ = false
    self.state.isDragging = false
end

function TileGrid:Render(vg)
    local def = TS.get(self.setId_)
    if not def or def.count < 1 or def.columns < 1 then return end
    local l = self:GetAbsoluteLayout()
    local hit = self:GetAbsoluteLayoutForHitTest()
    -- 只绘制视口内的切片，大图集也不逐帧遍历全部瓦片。
    local viewport = self.parent and self.parent:GetAbsoluteLayoutForHitTest() or hit
    local firstCol = math.max(1, math.floor((viewport.x - hit.x) / self.cellSize_) + 1)
    local lastCol = math.min(def.columns, math.ceil((viewport.x + viewport.w - hit.x) / self.cellSize_))
    local firstRow = math.max(1, math.floor((viewport.y - hit.y) / self.cellSize_) + 1)
    local lastRow = math.min(def.rows, math.ceil((viewport.y + viewport.h - hit.y) / self.cellSize_))
    local size = self.cellSize_
    nvgSave(vg)
    for row = firstRow, lastRow do
        for col = firstCol, lastCol do
            local id = (row - 1) * def.columns + col
            local x, y = l.x + (col - 1) * size, l.y + (row - 1) * size
            nvgBeginPath(vg)
            nvgRect(vg, x, y, size, size)
            nvgFillColor(vg, (col + row) % 2 == 0 and nvgRGBA(37, 41, 47, 255) or nvgRGBA(30, 33, 38, 255))
            nvgFill(vg)
            if id <= def.count then TS.drawTile(vg, self.setId_, id, x, y, size, size, 1) end
            nvgBeginPath(vg)
            nvgRect(vg, x + 0.5, y + 0.5, size - 1, size - 1)
            nvgStrokeColor(vg, nvgRGBA(91, 98, 108, 115))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end
    local selection = ME.tileSelection
    if selection and selection.tilesetId == self.setId_ then
        local col = (selection.tileId - 1) % def.columns + 1
        local row = math.floor((selection.tileId - 1) / def.columns) + 1
        local x, y = l.x + (col - 1) * size, l.y + (row - 1) * size
        local w, h = (selection.width or 1) * size, (selection.height or 1) * size
        nvgBeginPath(vg)
        nvgRect(vg, x + 1, y + 1, w - 2, h - 2)
        nvgFillColor(vg, nvgRGBA(84, 156, 232, 48))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(120, 187, 255, 255))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

local function label(text, muted)
    return UI.Label { text = text, fontSize = 11, whiteSpace = "normal", wordBreak = "break-word", fontColor = muted and COLORS.muted or COLORS.text }
end
local function button(text, callback, width)
    return UI.Button { text = text, width = width, height = 32, minWidth = 0, paddingHorizontal = 8, borderRadius = 3, fontSize = 11, backgroundColor = COLORS.surface, textColor = COLORS.text, onClick = callback }
end

local GP = require "ui.gameplay_properties"
local CollisionEditor = require "ui.collision_editor"
local BackgroundPalette = require "ui.background_palette"
local CATEGORIES = {
    { name = "地形碰撞", chars = "#=", layer = "collision" },
    { name = "环境与机关", chars = "FfCZSPDOAX", layer = "gameplay" },
    { name = "出生点", chars = "t", layer = "gameplay" },
    { name = "敌人与首领", chars = "12yscbmB", layer = "gameplay" },
    { name = "收集与探索奖励", chars = "W$QHuh oip", layer = "gameplay" },
    { name = "水生伙伴", chars = "aeljrngw", layer = "gameplay" },
}

---@class EditorTilePaletteProps : PanelProps
---@field notify? fun(text:string)
---@field modalFactory? function
---@field onChange? fun()
---@field settings? table
---@field viewportHeight? number
---@field backgroundContent? EditorBackgroundPalette
---@field isCanvasPoint? fun(sx:number,sy:number):boolean
---@field getRenderer? fun():table
---@class EditorTilePalette : Panel
---@overload fun(props?: EditorTilePaletteProps): EditorTilePalette
---@field props EditorTilePaletteProps
---@field notify_ function
---@field modalFactory_ function
---@field onChange_ function
---@field setId_ string
---@field mode_ string
---@field zoom_ number
---@field revision_ any
---@field dropdown_ Dropdown
---@field grid_ EditorTileGrid
---@field viewport_ ScrollView
---@field info_ Label
---@field selectionInfo_ Label
---@field collider_ Dropdown
---@field tileContent_ Panel
---@field gameplayContent_ Panel
---@field backgroundContent_ EditorBackgroundPalette
---@field properties_ Panel
---@field propertiesToggle_ Button
---@field propertiesExpanded_ boolean
---@field tileTab_ Button
---@field gameplayTab_ Button
---@field backgroundTab_ Button
---@field collisionTab_ Button
---@field gameplayButtons_ table<string, Button>
---@field refreshGameplay_ function
---@field collisionContent_ Panel
---@field refreshCollision_ function
local Palette = UI.Panel:Extend("EditorTilePalette")

function Palette:Init(props)
    self.notify_ = props.notify or function(text) print("[地图编辑界面] " .. text) end
    self.modalFactory_ = props.modalFactory
    self.onChange_ = props.onChange or function() end
    local settings = props.settings or {}
    local selection = ME.tileSelection
    self.setId_ = settings.setId or (selection and selection.tilesetId) or "builtin"
    self.mode_ = settings.mode or "tiles"
    self.zoom_ = settings.zoom or 48
    self.revision_ = -1
    self.gameplayButtons_ = {}
    self.propertiesExpanded_ = false
    props.width, props.height, props.flexShrink = "100%", "100%", 1
    props.backgroundColor = COLORS.surface
    props.padding, props.gap = 8, 8
    local init = UI.Panel.Init --[[@as fun(...: any)]]
    init(self, props)

    self.tileTab_ = button("瓦片", function() self:SetMode("tiles") end)
    self.gameplayTab_ = button("玩法", function() self:SetMode("gameplay") end)
    self.backgroundTab_ = button("背景", function() self:SetMode("background") end)
    self.collisionTab_ = button("碰撞体", function() self:SetMode("collision") end)
    for _, tab in ipairs({ self.tileTab_, self.gameplayTab_, self.backgroundTab_, self.collisionTab_ }) do
        tab:SetStyle({ flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, paddingHorizontal = 2, fontSize = 10 })
    end
    self:AddChild(UI.Panel { width = "100%", flexDirection = "row", gap = 4,
        children = { self.tileTab_, self.gameplayTab_, self.backgroundTab_, self.collisionTab_ } })

    self.dropdown_ = UI.Dropdown {
        width = "100%", minWidth = 0, height = 34, fontSize = 11, options = {},
        value = self.setId_, maxVisibleItems = 6, triggerBgColor = COLORS.inset,
        onChange = function(_, value)
            self.setId_ = value
            self.grid_:SetTileset(value)
            self.viewport_:SetScroll(0, 0)
            self:SelectFirstReady()
            self:Refresh(true)
        end,
    }
    self.grid_ = TileGrid {
        setId = self.setId_, cellSize = self.zoom_,
        onSelection = function(setId, id, width, height, columns, collider)
            if not ME.visualLayers[ME.selectedLayer] then ME.setLayer("ground") end
            ME.selectTiles(setId, id, width, height, columns, collider)
            if ME.tool == "erase" or ME.tool == "select" or ME.tool == "background" or ME.tool == "collision" then ME.tool = "brush" end
            self:RefreshSelection()
            self.onChange_()
        end,
    }
    self.viewport_ = UI.ScrollView {
        width = "100%", height = props.viewportHeight or 220,
        scrollX = true, scrollY = true, bounces = false,
        scrollbarInteractive = true, backgroundColor = COLORS.inset,
        children = { self.grid_ },
    }
    self.info_ = label("", true)
    local zoom = UI.Dropdown {
        width = 112, minWidth = 0, height = 32, fontSize = 11, value = self.zoom_,
        options = {
            { value = 24, label = "缩放 50%" }, { value = 36, label = "缩放 75%" },
            { value = 48, label = "缩放 100%" }, { value = 72, label = "缩放 150%" },
            { value = 96, label = "缩放 200%" },
        },
        onChange = function(_, value)
            self.zoom_ = value
            self.grid_:SetCellSize(value)
            self.viewport_:SetScroll(0, 0)
        end,
    }
    local scrollControls = UI.Panel { flexDirection = "row", gap = 3, children = {
        button("<", function() self.viewport_:ScrollBy(-self.zoom_ * 2, 0) end, 28),
        button(">", function() self.viewport_:ScrollBy(self.zoom_ * 2, 0) end, 28),
        button("上", function() self.viewport_:ScrollBy(0, -self.zoom_ * 2) end, 28),
        button("下", function() self.viewport_:ScrollBy(0, self.zoom_ * 2) end, 28),
    } }
    self.tileContent_ = UI.Panel { width = "100%", gap = 7, children = {
        label("瓦片集"), self.dropdown_,
        UI.Panel { flexDirection = "row", gap = 4, children = {
            button("导入图片", function() self:OpenImport(false) end),
            button("切片配置", function() self:OpenImport(true) end),
        } },
        self.info_, zoom, self.viewport_, scrollControls,
        label("点击单格；拖动框选多格。滚轮或滚动条浏览。", true),
    } }
    self.gameplayContent_ = self:BuildGameplay()
    self.backgroundContent_ = props.backgroundContent or BackgroundPalette {
        notify = self.notify_, onChange = self.onChange_,
        isCanvasPoint = props.isCanvasPoint, getRenderer = props.getRenderer,
    }
    local gameplayProperties, refreshGameplay = GP.create(self.notify_)
    self.refreshGameplay_ = refreshGameplay
    self.gameplayContent_:InsertChild(gameplayProperties, 1)
    local collisionEditor, refreshCollision = CollisionEditor.create(self.notify_)
    self.refreshCollision_ = refreshCollision
    self.collisionContent_ = UI.Panel { width = "100%", gap = 8, children = { collisionEditor } }
    self.selectionInfo_ = label("", true)
    self.collider_ = UI.Dropdown {
        width = "100%", minWidth = 0, height = 34, fontSize = 11,
        value = selection and selection.collider or "ground",
        options = { { value = "ground", label = "地面 ground · 整格碰撞" }, { value = "decoration", label = "装饰 decoration · 无碰撞" } },
        onChange = function(_, kind)
            ME.setTileCollider(kind)
            self:RefreshSelection()
            self.onChange_()
        end,
    }
    self.properties_ = UI.Panel { width = "100%", gap = 7, children = {
        self.selectionInfo_, label("碰撞属性"), self.collider_,
        label("地面在碰撞同步开启时写入整格碰撞；装饰不产生碰撞。属性用于之后的笔刷放置。", true),
    } }
    self.properties_:SetVisible(false)
    self.propertiesToggle_ = button("属性  +", function(selfButton)
        self.propertiesExpanded_ = not self.propertiesExpanded_
        self.properties_:SetVisible(self.propertiesExpanded_)
        selfButton:SetText(self.propertiesExpanded_ and "属性  -" or "属性  +")
    end)
    self.propertiesToggle_:SetStyle({ width = "100%" })
    self:AddChild(UI.ScrollView {
        width = "100%", flexGrow = 1, flexBasis = 0, flexShrink = 1, bounces = false,
        children = { UI.Panel { width = "100%", gap = 10, children = {
            self.tileContent_, self.gameplayContent_, self.backgroundContent_, self.collisionContent_,
            self.propertiesToggle_, self.properties_,
        } } },
    })
    self:SetMode(self.mode_)
    self:Refresh(true)
end

function Palette:SetMode(mode)
    if mode ~= "tiles" and mode ~= "gameplay" and mode ~= "background" and mode ~= "collision" then mode = "tiles" end
    if mode ~= self.mode_ then self:CloseOverlays() end
    self.mode_ = mode
    if mode == "background" then
        -- 只切工具/图层，不改旧笔刷与图集；下次画布点击由 EB 处理。
        ME.tool = "background"
        ME.setLayer("background")
    elseif mode == "collision" then
        -- 解锁/显示碰撞层并切到选取工具：点画布任意格直接选中，不写入碰撞。
        ME.selectCollisionCell()
    elseif ME.tool == "background" then
        ME.tool = "brush"
    end
    self.tileContent_:SetVisible(mode == "tiles")
    self.gameplayContent_:SetVisible(mode == "gameplay")
    self.backgroundContent_:SetVisible(mode == "background")
    self.collisionContent_:SetVisible(mode == "collision")
    self.propertiesToggle_:SetVisible(mode == "tiles")
    self.properties_:SetVisible(mode == "tiles" and self.propertiesExpanded_)
    self.tileTab_:SetBackgroundColor(mode == "tiles" and COLORS.selected or COLORS.inset)
    self.gameplayTab_:SetBackgroundColor(mode == "gameplay" and COLORS.selected or COLORS.inset)
    self.backgroundTab_:SetBackgroundColor(mode == "background" and COLORS.selected or COLORS.inset)
    self.collisionTab_:SetBackgroundColor(mode == "collision" and COLORS.selected or COLORS.inset)
    self:RefreshSelection()
    self.onChange_()
end

function Palette:BuildGameplay()
    local content = UI.Panel { width = "100%", gap = 10 }
    local assigned = {}
    local function addGroup(name, items, targetLayer)
        if #items == 0 then return end
        content:AddChild(label(name))
        local grid = UI.SimpleGrid { width = "100%", columns = 2, gap = 5 }
        for _, item in ipairs(items) do
            local choice = UI.Button {
                text = "", height = 54, minWidth = 0, padding = 6,
                backgroundColor = COLORS.inset, borderRadius = 3,
                children = { UI.Label {
                    text = item.label, width = "100%", height = "100%", fontSize = 11,
                    whiteSpace = "normal", wordBreak = "break-word", textAlign = "center",
                    verticalAlign = "middle", fontColor = COLORS.text, pointerEvents = "none",
                } },
                onClick = function()
                    ME.setLayer(targetLayer)
                    ME.brush = item.char
                    if ME.tool == "erase" or ME.tool == "select" or ME.tool == "background" then ME.tool = "brush" end
                    self:RefreshSelection()
                    self.onChange_()
                end,
            }
            self.gameplayButtons_[item.char] = choice
            grid:AddChild(choice)
        end
        content:AddChild(grid)
    end
    for _, category in ipairs(CATEGORIES) do
        local items = {}
        for _, item in ipairs(ME.PALETTE) do
            if category.chars:find(item.char, 1, true) and not assigned[item.char] then
                assigned[item.char] = true
                items[#items + 1] = item.char == "t" and { char = "t", label = "出生点" } or item
            end
        end
        addGroup(category.name, items, category.layer)
    end
    local remaining = {}
    for _, item in ipairs(ME.PALETTE) do
        if item.char ~= "T" and not assigned[item.char] then remaining[#remaining + 1] = item end
    end
    addGroup("其他已有元素", remaining, "gameplay")
    return content
end

function Palette:SelectFirstReady()
    local def = TS.get(self.setId_)
    if not def or def.count < 1 then return end
    local selection = ME.tileSelection
    if selection and selection.tilesetId == self.setId_ and selection.tileId >= 1 and selection.tileId <= def.count then
        local col = (selection.tileId - 1) % def.columns + 1
        local row = math.floor((selection.tileId - 1) / def.columns) + 1
        local width = math.min(selection.width or 1, def.columns - col + 1)
        local height = math.min(selection.height or 1, def.rows - row + 1)
        if selection.columns ~= def.columns or selection.width ~= width or selection.height ~= height then
            ME.selectTiles(self.setId_, selection.tileId, width, height, def.columns, selection.collider)
            self.onChange_()
        end
        return
    end
    -- 图集后台解码/刷新只补齐选择，不改变用户正在擦除的碰撞/玩法层。
    -- 用户点击具体瓦片时，由 onSelection 显式切到地形外观层。
    ME.selectTiles(self.setId_, 1, 1, 1, def.columns, TS.tileCollider(self.setId_, 1))
    self.onChange_()
end

function Palette:Refresh(force)
    self.backgroundContent_:Refresh(force)
    -- 背景页后台更新不能经 SelectFirstReady 修改原瓦片笔刷。
    if self.mode_ == "background" then return end
    local revision = TS.revision()
    if not force and revision == self.revision_ then
        self:RefreshSelection()
        return
    end
    self.revision_ = revision
    local options = {}
    for _, def in ipairs(TS.list()) do
        local suffix = def.status == "ready" and "" or (def.status == "error" and " · 验证失败" or " · 待验证")
        options[#options + 1] = { value = def.id, label = def.name .. suffix }
    end
    self.dropdown_:SetOptions(options)
    if not TS.get(self.setId_) then self.setId_ = "builtin" end
    self.dropdown_:SetValue(self.setId_)
    self.grid_:SetTileset(self.setId_)
    local def = TS.get(self.setId_)
    if def then
        if def.status == "ready" and def.count > 0 then
            self.info_:SetText(("%d列 × %d行 · %d瓦片 · %d×%d像素/格"):format(def.columns, def.rows, def.count, def.cellWidth, def.cellHeight))
            self:SelectFirstReady()
        elseif def.error and def.error ~= "" then
            self.info_:SetText("图片/切片验证失败：" .. tostring(def.error))
        else
            self.info_:SetText("已登记，等待图片下载与实际尺寸验证…")
        end
    else
        self.info_:SetText("未找到瓦片集。可先使用内置测试瓦片。")
    end
    self:RefreshSelection()
end

function Palette:RefreshSelection()
    if self.mode_ == "background" then self.backgroundContent_:Refresh(false); return end
    if self.mode_ == "collision" then
        if self.refreshCollision_ then self.refreshCollision_() end
        return
    end
    if self.mode_ == "gameplay" and self.refreshGameplay_ then self.refreshGameplay_() end
    local selection = ME.tileSelection
    if selection then
        local description = TS.describe(selection.tilesetId, selection.tileId)
        local kind = selection.collider == "decoration" and "装饰 · 无碰撞" or "地面 · 整格碰撞"
        self.selectionInfo_:SetText(tostring(description or selection.tilesetId) .. ("\n框选 %d×%d 格 · 当前笔刷：%s"):format(selection.width or 1, selection.height or 1, kind))
        self.collider_:SetValue(selection.collider or "ground")
    else
        self.selectionInfo_:SetText("请在瓦片网格选择笔刷。")
    end
    self.collider_:SetStyle({ opacity = ME.visualLayers[ME.selectedLayer] and 1 or 0.5 })
    self.collider_.props.disabled = not ME.visualLayers[ME.selectedLayer]
    for char, choice in pairs(self.gameplayButtons_) do
        choice:SetBackgroundColor(ME.brush == char and not ME.visualLayers[ME.selectedLayer] and ME.tool ~= "erase" and COLORS.selected or COLORS.inset)
    end
end

function Palette:GetSettings()
    return { setId = self.setId_, mode = self.mode_, zoom = self.zoom_ }
end

function Palette:CloseOverlays()
    self.backgroundContent_:CloseOverlays()
    local function close(widget)
        if widget._className == "Dropdown" then
            local dropdown = widget --[[@as Dropdown]]
            dropdown:Close()
        end
        for _, child in ipairs(widget:GetChildren()) do close(child) end
    end
    close(self)
    self.grid_.selecting_ = false
    self.grid_.state.isDragging = false
end

--- 只登记实际选择或输入的真实资源路径，不捏造图片。
--- register 返回 true 仅代表登记完成，不代表下载或切片验证已经成功。
function Palette:OpenImport(reslice)
    if not self.modalFactory_ then return end
    self:CloseOverlays()
    local current = reslice and TS.get(self.setId_) or nil
    if reslice and (not current or not current.path) then
        self.notify_("内置瓦片无需切片；请先导入 image/地图/tiles/ 中的真实图片。")
        return
    end
    local modal = self.modalFactory_(reslice and "瓦片集切片配置" or "导入瓦片图片")
    local path = UI.TextField { width = "100%", height = 34, value = current and current.path or "", placeholder = "image/地图/tiles/ 下的真实图片资源路径", fontSize = 11 }
    local name = UI.TextField { width = "100%", height = 34, value = current and current.name or "", placeholder = "瓦片集名称", fontSize = 11 }
    local files = {}
    for _, file in ipairs(TS.availableFiles()) do
        files[#files + 1] = { value = file, label = file }
    end
    local fileDropdown = UI.Dropdown {
        width = "100%", minWidth = 0, height = 34, fontSize = 11, options = files,
        placeholder = #files > 0 and "选择已上传图片" or "目录暂无已上传图片", value = current and current.path or nil,
        onChange = function(_, value) path:SetValue(value) end,
    }
    local function field(value)
        return UI.TextField { width = "100%", height = 34, fontSize = 11, value = tostring(value) }
    end
    local cellW = field(current and current.cellWidth or 32)
    local cellH = field(current and current.cellHeight or 32)
    local margin = field(current and current.margin or 0)
    local spacing = field(current and current.spacing or 0)
    local collider = UI.Dropdown {
        width = "100%", minWidth = 0, height = 34, fontSize = 11, value = current and current.collider or "ground",
        options = { { value = "ground", label = "地面 · 整格碰撞" }, { value = "decoration", label = "装饰 · 无碰撞" } },
    }
    local form = UI.Panel { width = "100%", gap = 7, children = {
        label("资源根路径：image/地图/tiles/。图片尚未上传时可先使用 builtin 基础测试集。", true),
        fileDropdown, label("图片路径"), path, label("瓦片集名称"), name,
        UI.SimpleGrid { width = "100%", columns = 2, gap = 8, children = {
            UI.Panel { gap = 4, children = { label("单格宽（像素）"), cellW } },
            UI.Panel { gap = 4, children = { label("单格高（像素）"), cellH } },
            UI.Panel { gap = 4, children = { label("边距 margin"), margin } },
            UI.Panel { gap = 4, children = { label("间距 spacing"), spacing } },
        } },
        label("默认碰撞属性"), collider,
        label("格数由图片实际尺寸计算。登记后等待下载验证，不将未加载图片当成已切片。", true),
    } }
    modal:AddContent(UI.ScrollView {
        width = "100%", height = math.max(100, math.min(400, UI.GetHeight() * 0.60 - 100)),
        bounces = false, children = { form },
    })
    modal:SetFooter(UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", justifyContent = "flex-end", gap = 8, children = {
        button("取消", function() modal:Close() end),
        button("登记并验证", function()
            local w = tonumber(tostring(cellW:GetValue() or "")) or -1.0
            local h = tonumber(tostring(cellH:GetValue() or "")) or -1.0
            local m = tonumber(tostring(margin:GetValue() or "")) or -1.0
            local s = tonumber(tostring(spacing:GetValue() or "")) or -1.0
            if w < 1 or h < 1 or w > 4096 or h > 4096 or m < 0 or s < 0
                or w % 1 ~= 0 or h % 1 ~= 0 or m % 1 ~= 0 or s % 1 ~= 0 then
                self.notify_("切片参数必须为整数：宽高1–4096，边距与间距不小于0。")
                return
            end
            local source = tostring(path:GetValue() or ""):match("^%s*(.-)%s*$") or ""
            if not source:match("^image/地图/tiles/.+") or source:find("..", 1, true) or source:find("\\", 1, true) then
                self.notify_("请输入 image/地图/tiles/ 下的真实图片路径，不带 assets/ 前缀。")
                return
            end
            local displayName = tostring(name:GetValue() or ""):match("^%s*(.-)%s*$") or ""
            if displayName == "" then displayName = source:match("([^/]+)$") or source end
            local ok, err = TS.register({
                id = current and current.id or nil, name = displayName, path = source,
                cellWidth = math.floor(w), cellHeight = math.floor(h), margin = math.floor(m), spacing = math.floor(s), collider = collider:GetValue(),
            })
            if not ok then self.notify_("登记失败：" .. tostring(err or "未知错误")); return end
            -- register 可能自动分配标识，通过权威瓦片集列表找到登记结果。
            for _, def in ipairs(TS.list()) do
                if def.path == source and def.name == displayName then self.setId_ = def.id end
            end
            ME.markDirty()
            modal:Close()
            self:Refresh(true)
            self.notify_("已登记，等待图片验证；验证结果显示在瓦片集下方。")
            self.onChange_()
        end),
    } })
    modal:Open()
end

return Palette
