-- 运行时地图编辑器：Unity Tile Palette 式停靠面板之间保留透明世界画布。
-- 所有界面控件使用 urhox-libs/UI，世界地图仍由 R 渲染。
local UI = require "urhox-libs/UI"
local ME = require "core.map_editor"
local HUD = require "ui/hud"
local TilePalette = require "ui.tile_palette"
local MapExport = require "ui.map_export"
local EG = require "core.editor_gameplay"
local WorldMap = require "core.world_map"

---@class MapEditorUI
local UIEditor = {}

local COLORS = {
    surface = { 36, 39, 44, 255 }, inset = { 27, 30, 34, 255 },
    border = { 64, 69, 77, 255 }, selected = { 58, 103, 153, 255 },
    text = { 225, 228, 233, 255 }, muted = { 157, 165, 176, 255 },
    error = { 255, 157, 145, 255 },
}
local TOOLS = { { key = "brush", label = "画笔" }, { key = "erase", label = "橡皮" }, { key = "rect", label = "矩形" }, { key = "select", label = "选取" }, { key = "background", label = "背景" } }
local BRUSH_SIZES = { 1, 3, 5, 7, 11 }

---@class EditorUISession
---@field visible boolean
---@field compact boolean
---@field panelOpen boolean
---@field width number
---@field height number
---@field scale number
---@field message string
---@field messageTime number
---@field onExit? function
---@field onExport? function
---@field onSelectSource? fun(kind:string)
---@field root? Panel
---@field overlay? Panel
---@field canvas? Panel
---@field palette? EditorTilePalette
---@field paletteSettings table
---@field floating? Panel
---@field panelToggle? Button
---@field status? Label
---@field size? Dropdown
---@field layerRows table<string, Panel>
---@field toolButtons table<string, Button>
---@field modals table<Modal, boolean>
local session = {
    visible = false, compact = false, panelOpen = false, width = 0, height = 0, scale = 1,
    message = "", messageTime = 0,
    paletteSettings = { setId = "industrial_walls", mode = "tiles", zoom = 36 },
    layerRows = {}, toolButtons = {}, modals = {},
} --[[@as EditorUISession]]

local function label(text, size, muted)
    return UI.Label {
        text = text, fontSize = size or 11, whiteSpace = "normal", wordBreak = "break-word",
        fontColor = muted and COLORS.muted or COLORS.text,
    }
end
local function button(text, callback, width, danger)
    return UI.Button {
        text = text, width = width, height = 34, minWidth = 0, flexShrink = 0,
        paddingHorizontal = 10, fontSize = 11, borderRadius = 3,
        backgroundColor = danger and { 102, 51, 47, 255 } or COLORS.surface,
        textColor = COLORS.text, borderWidth = 1, borderColor = COLORS.border,
        onClick = callback,
    }
end
local function row(children, extra)
    local props = extra or {}
    props.flexDirection, props.alignItems, props.gap, props.children = "row", "center", props.gap or 6, children
    return UI.Panel(props)
end

local function closeDropdowns(widget)
    if widget._className == "Dropdown" then
        local dropdown = widget --[[@as Dropdown]]
        dropdown:Close()
    end
    for _, child in ipairs(widget:GetChildren()) do closeDropdowns(child) end
    if widget._className == "EditorDialog" then
        local modal = widget --[[@as Modal]]
        for _, child in ipairs(modal:GetHitTestChildren() or {}) do closeDropdowns(child) end
    end
end

-- Modal 的内容与页脚是独立的 Yoga 子树，Widget.Destroy 只释放常规 children。
-- 因此关闭编辑器弹窗后显式释放这两棵子树，避免残留焦点与布局节点。
---@class EditorDialog : Modal
local EditorDialog = UI.Modal:Extend("EditorDialog")
function EditorDialog:Destroy()
    closeDropdowns(self)
    local detached = self:GetHitTestChildren() or {}
    for _, child in ipairs(detached) do child:Destroy() end
    UI.Widget.Destroy(self)
end

local function createModal(title)
    if session.root then closeDropdowns(session.root) end
    local modal = EditorDialog {
        title = title, size = session.compact and "fullscreen" or "md", headerHeight = 44,
        headerContentGap = 8, contentPadding = 12, contentGap = 8,
        titleFontSize = 14, titleTextColor = COLORS.text, closeIconColor = COLORS.muted,
        backgroundColor = COLORS.surface, borderColor = COLORS.border, borderRadius = 4,
        closeOnOverlay = false, closeOnEscape = true,
        onClose = function(self)
            UI.ClearFocus()
            session.modals[self] = nil
            self:Destroy()
        end,
    }
    session.modals[modal] = true
    return modal
end

local function closeModals()
    local list = {}
    for modal in pairs(session.modals) do list[#list + 1] = modal end
    for _, modal in ipairs(list) do
        if modal:IsOpen() then modal:Close() else modal:Destroy(); session.modals[modal] = nil end
    end
end

local function confirm(title, message, action)
    local modal = createModal(title)
    modal:AddContent(label(message, 12))
    modal:SetFooter(row({
        button("取消", function() modal:Close() end),
        button("确认", function() modal:Close(); action() end, nil, true),
    }, { width = "100%", justifyContent = "flex-end", flexWrap = "wrap" }))
    modal:Open()
end

local function layerLabel(id)
    for _, def in ipairs(ME.layerDefs) do if def.id == id then return def.label end end
    return id
end

local function refreshControls()
    for key, choice in pairs(session.toolButtons) do
        choice:SetBackgroundColor(ME.tool == key and COLORS.selected or COLORS.surface)
    end
    if session.size then session.size:SetValue(ME.brushSize) end
    for id, layerRow in pairs(session.layerRows) do
        layerRow:SetBackgroundColor(ME.selectedLayer == id and COLORS.selected or COLORS.inset)
        local state = ME.getLayerState(id)
        local visibility = layerRow:FindById("visible_" .. id) --[[@as Button?]]
        local lock = layerRow:FindById("locked_" .. id) --[[@as Button?]]
        if visibility then visibility:SetText(state.visible == false and "隐" or "显") end
        if lock then lock:SetText(state.locked and "锁" or "开") end
    end
end

local function saveCurrent()
    local callOK, saved = pcall(ME.saveToSandbox)
    if not callOK or not saved then
        UIEditor.notify("保存失败，地图仍保留在本次会话。请重试或导出后再离开。")
        print("[地图编辑界面] 保存失败：" .. tostring(saved))
        return false
    end
    return true
end

function UIEditor.notify(text)
    session.message, session.messageTime = tostring(text), 5
    print("[地图编辑界面] " .. session.message)
    if session.status then session.status:SetText(session.message) end
end

local function changed(message)
    ME.markDirty()
    refreshControls()
    if message then UIEditor.notify(message) end
end

local function exitEditor()
    if EG.initialKey() == "" and (#EG.list("S") > 0 or ME.metadata.initialSpawnCell ~= nil) then
        UIEditor.selectElement()
        UIEditor.notify("请在玩法元素页选取地图中的泉眼S或出生点t，设为初始出生点后再测试；失效选择不会自动回退或随机挑选。")
        return
    end
    if not saveCurrent() then return end
    local callback = session.onExit
    if not UIEditor.hide() then return end
    if callback then callback() end
end

local function validDimensions(widthField, heightField)
    local w, h = tonumber(widthField:GetValue()), tonumber(heightField:GetValue())
    if not w or not h or w % 1 ~= 0 or h % 1 ~= 0 or w < 5 or w > 2048 or h < 5 or h > 512 then
        UIEditor.notify("地图尺寸必须为整数：宽5–2048格，高5–512格，总面积不超过1048576格。")
        return nil, nil
    end
    if w * h > 1048576 then
        UIEditor.notify("地图总面积不能超过1048576格。")
        return nil, nil
    end
    return math.floor(w), math.floor(h)
end

local function dimensionFields()
    local width = UI.TextField { width = "100%", height = 34, fontSize = 12, value = tostring(ME.cols) }
    local height = UI.TextField { width = "100%", height = 34, fontSize = 12, value = tostring(ME.rows) }
    local fields = UI.SimpleGrid { width = "100%", columns = 2, gap = 10, children = {
        UI.Panel { gap = 5, children = { label("宽（格）"), width } },
        UI.Panel { gap = 5, children = { label("高（格）"), height } },
    } }
    return fields, width, height
end

local function openMapSettings()
    local modal = createModal("地图设置")
    local fields, wField, hField = dimensionFields()
    local form = UI.Panel { width = "100%", gap = 12, children = {
        label("无缝大地图（world） · " .. ME.cols .. "×" .. ME.rows .. " 格", 12),
        fields,
        label("尺寸范围：宽5–2048格，高5–512格，总面积不超过1048576格。应用尺寸保留交集区域，缩小会裁掉边缘格内容。新建空白与清空只删除各图层的格内容，保留出生点、故事、主题等元数据，不会重置世界进度。覆盖前再次确认。", 11, true),
        row({
            button("应用尺寸", function()
                local w, h = validDimensions(wField, hField)
                if not w or not h then return end
                modal:Close()
                confirm("确认调整地图尺寸", ("尺寸改为 %d×%d 格。原有内容保留在交集区域，超出新边界的内容将删除。"):format(w, h), function()
                    ME.resize(w, h)
                    changed(("已调整为 %d×%d 格，等待保存。"):format(w, h))
                end)
            end),
            button("新建空白", function()
                local w, h = validDimensions(wField, hField)
                if not w or not h then return end
                modal:Close()
                confirm("覆盖无缝大地图为空白", ("使用 %d×%d 格空白画布替换 world 所有图层的格内容。保留出生点、故事、主题等元数据；不会重置世界。不能撤销。"):format(w, h), function()
                    ME.newMap(w, h)
                    changed("所有图层的格内容已替换为空白，出生点与故事等元数据保留，等待保存。")
                end)
            end, nil, true),
            button("清空所有图层", function()
                modal:Close()
                confirm("清空无缝大地图格内容", "保留地图尺寸，清空前景、地面、背景、碰撞与玩法层的格内容。出生点、故事、主题等元数据保留，不会重置世界。不能撤销。", function()
                    ME.newMap(ME.cols, ME.rows)
                    changed("所有图层的格内容已清空，出生点与故事等元数据保留，等待保存。")
                end)
            end, nil, true),
        }, { width = "100%", flexWrap = "wrap" }),
    } }
    modal:AddContent(UI.ScrollView {
        width = "100%", height = math.max(120, math.min(260, UI.GetHeight() * 0.55 - 80)),
        bounces = false, children = { form },
    })
    modal:SetFooter(row({ button("关闭", function() modal:Close() end) }, { width = "100%", justifyContent = "flex-end" }))
    modal:Open()
end

local function exportMap()
    MapExport.open({
        modalFactory = createModal, notify = UIEditor.notify, onExport = session.onExport,
        onImport = function()
            refreshControls()
            if session.palette then session.palette:Refresh(true); session.palette:RefreshSelection() end
        end,
    })
end

local function openMapSource()
    local modal = createModal("地图来源")
    local shared = WorldMap.sharedSource()
    modal:AddContent(label("当前：" .. ME.sourceLabel .. " · " .. ME.cols .. "×" .. ME.rows .. " 格", 12))
    modal:AddContent(label("项目共享版本：" .. shared.cols .. "×" .. shared.rows .. " 格。协作者应加载此版本；上传文件后须重新打开最新预览。", 12, true))
    modal:AddContent(label("切换前会保存有改动的个人草稿，保存失败则不切换。项目共享地图不会自动合并个人草稿，旧地图文件不删除。", 12, true))
    local function choose(kind)
        modal:Close()
        if session.onSelectSource then session.onSelectSource(kind) end
    end
    modal:AddContent(UI.Panel { width = "100%", gap = 8, children = {
        button("加载项目共享地图", function() choose("shared") end),
        button("继续我的共享编辑草稿", function() choose("sharedDraft") end),
        button("查看我的旧地图草稿", function() choose("draft") end),
    } })
    modal:SetFooter(row({ button("关闭", function() modal:Close() end) }, { width = "100%", justifyContent = "flex-end" }))
    modal:Open()
end

local function openHelp()
    local modal = createModal("地图编辑帮助")
    local content = UI.Panel { width = "100%", gap = 12, children = {
        label("地图与相机", 13),
        label("只在中央透明画布里编辑。左键绘制，右键擦除；画笔与橡皮使用工具栏的格数。矩形工具拖框填入。WASD/方向键或中键拖动平移，滚轮缩放。输入框获得焦点或弹窗打开时，地图输入暂停。", 12, true),
        label("图层", 13),
        label("前景、地面、背景是视觉瓦片图层；碰撞层编辑地形阻挡；玩法层放置世界元素，t 是出生点，不使用章节传送门。点图层名称选择，显/隐只控制编辑器显示，锁/开控制能否修改。锁定或隐藏图层时请先解锁/显示再绘制。", 12, true),
        label("橡皮擦除", 13),
        label("橡皮与右键只擦当前选中层。地形外观层可擦图片地面及旧灰色地面/平台；前景、背景瓦片请选对应图层。绿色边框是碰撞辅助线，不是图片，独立碰撞需在碰撞层擦除。锁定或隐藏层不会被橡皮修改。", 12, true),
        label("Tile Palette", 13),
        label("瓦片页按原始图片的列行排布，不打乱切片顺序。点击选单格，拖动框选矩形多格笔刷；调色板缩放仅影响预览。用滚轮、滚动条或方向按钮浏览图片。玩法元素按类别双列排列，选中后切到对应碰撞/玩法层。", 12, true),
        label("背景素材", 13),
        label("背景页提供工业背景整图。按住缩略图拖到中央画布松开放置；也可点「点选放置」后点击画布。背景工具下点击已放背景选取，拖动移动；四角手柄与宽度/±20%按钮保持中心等比缩放，X/Y以米为单位。已放背景列表可选取、定位；删除只影响所选实例。背景只显示无碰撞，存入metadata，不修改瓦片或玩法格，完整导出/重新导入保留。切回瓦片/玩法可恢复画笔，收起面板取消拖放。", 12, true),
        label("碰撞属性", 13),
        label("ground 地面是整格碰撞；decoration 装饰无碰撞。开启碰撞同步时，地面笔刷同步写入碰撞层；装饰不会新增阻挡。属性下拉用于后续放置，碰撞层可单独编辑。", 12, true),
        label("素材导入", 13),
        label("先把真实图片放到 /workspace/assets/image/地图/tiles/，重新构建把图片加入当前版本，再输入 image/地图/tiles/ 开头的资源路径。已登记图片可从下拉框选择。设置单格像素宽高、margin、spacing。登记成功只表示等待验证，实际格数要等图片加载成功并验证实际尺寸后才出现；错误在调色板显示。没有图片也可使用 builtin 4×2 测试瓦片。", 12, true),
        label("保存与测试", 13),
        label("默认运行和打开编辑器加载项目共享地图；顶部「地图来源」可显式继续个人草稿或查看旧图。保存只写当前个人草稿，不同步协作者；从共享版重新编辑会先保留同槽旧草稿副本。退出试玩使用当前编辑快照，不会回到共享/旧图。保存失败不关闭编辑器；网页刷新可能丢失沙箱，要共享需导出替换 scripts/levels/world_src.lua 后构建，并重新打开最新预览。", 12, true),
        label("导出与重新导入", 13),
        label("导出窗口提供完整captureData JSON与Lua SRC、整份复制和无省略的可选择分页原文。复制后必须在游戏外粘贴另存为文件；浏览器剪贴板权限/异步结果无法确认，请验证粘贴内容。本版没有可核实的原生文件下载/文件分享API，不能把沙箱保存当成下载。Lua SRC替换scripts/levels/world_src.lua，不替换解析包装文件；JSON可在导出窗口重新导入，先验证后确认，失败保留原地图，不写沙箱。所有图层、true/false碰撞、尺寸、metadata和图集路径/切片参数保留，图片资源本身不包含在文本里。", 12, true),
        label("初始泉眼与机关连接", 13),
        label("先打开玩法元素页，再用选取工具点地图中的泉眼S，在属性区设为初始出生点；多个泉眼不会随机挑选一个。点出生点t也可设初始。选取压板P/电力接口O后在属性区明确连接电子门D/报警器A；不会自动连最近的门。属性和连接保存在metadata，完整导出/重新导入保留；失效的旧初始选择会提示重新设置。", 12, true),
        label("画布设置与小屏", 13),
        label("编辑器固定编辑无缝大地图（world），不再切换或新建章节。地图设置里的新建空白/清空只覆盖图层的格内容，保留出生点、故事、主题等元数据，不会重置世界，操作前必须确认。窄屏顶部自动分行；图层、瓦片与属性合并为一个可收起浮动面板，收起后可使用更大的画布。", 12, true),
    } }
    modal:AddContent(UI.ScrollView {
        width = "100%", height = math.max(120, math.min(430, UI.GetHeight() * 0.64 - 95)),
        bounces = false, children = { content },
    })
    modal:SetFooter(row({ button("知道了", function() modal:Close() end) }, { width = "100%", justifyContent = "flex-end" }))
    modal:Open()
end

local function buildLayers(compact)
    local children = {}
    session.layerRows = {}
    for _, def in ipairs(ME.layerDefs) do
        local choose = button(def.label, function()
            ME.setLayer(def.id)
            refreshControls()
            if session.palette then
                session.palette:SetMode(ME.visualLayers[def.id] and "tiles" or "gameplay")
                session.palette:RefreshSelection()
            end
        end)
        choose:SetStyle({ flexGrow = 1, flexShrink = 1, flexBasis = 0, paddingHorizontal = 5, borderWidth = 0 })
        local visibility = button("显", function()
            local state = ME.getLayerState(def.id)
            state.visible = state.visible == false
            changed(layerLabel(def.id) .. (state.visible and "已显示。" or "已隐藏（运行时内容不受影响）。"))
        end, 28)
        visibility.props.id, visibility.id = "visible_" .. def.id, "visible_" .. def.id
        visibility:SetStyle({ paddingHorizontal = 2, fontSize = 10 })
        local lock = button("开", function()
            local state = ME.getLayerState(def.id)
            state.locked = not state.locked
            changed(layerLabel(def.id) .. (state.locked and "已锁定。" or "已解锁。"))
        end, 28)
        lock.props.id, lock.id = "locked_" .. def.id, "locked_" .. def.id
        lock:SetStyle({ paddingHorizontal = 2, fontSize = 10 })
        local layerRow = row({ choose, visibility, lock }, { width = "100%", gap = 3, padding = 3, backgroundColor = COLORS.inset })
        session.layerRows[def.id] = layerRow
        children[#children + 1] = layerRow
    end
    children[#children + 1] = UI.Checkbox {
        checked = ME.syncCollision, label = "碰撞同步", size = 18, fontSize = 11,
        onChange = function(_, checked) ME.syncCollision = checked; changed("碰撞同步" .. (checked and "已开启。" or "已关闭。")) end,
    }
    local content = UI.Panel { width = "100%", gap = 5, padding = 8, children = children }
    if compact then return content end
    return UI.Panel {
        width = 180, height = "100%", backgroundColor = COLORS.surface, borderRightWidth = 1,
        borderRightColor = COLORS.border, children = {
            UI.Panel { height = 38, paddingHorizontal = 10, justifyContent = "center", children = { label("图层", 12) } },
            UI.ScrollView { width = "100%", flexGrow = 1, flexBasis = 0, flexShrink = 1, bounces = false, children = { content } },
        },
    }
end

local function togglePanel()
    session.panelOpen = not session.panelOpen
    if not session.panelOpen and session.palette then session.palette:CloseOverlays() end
    if session.floating then
        closeDropdowns(session.floating)
        session.floating:SetVisible(session.panelOpen)
    end
    if session.panelToggle then session.panelToggle:SetText(session.panelOpen and "收起面板" or "图层 / 瓦片") end
end

--- 选取玩法元素后展示其属性；窄屏同时展开面板，不改变已选地图格。
function UIEditor.selectElement()
    if session.palette then
        session.palette:SetMode("gameplay")
        session.palette:RefreshSelection()
    end
    if session.compact and not session.panelOpen then togglePanel() end
end

--- 选中背景后切到独立属性页；不触碰旧瓦片笔刷或玩法元素选择。
function UIEditor.selectBackground()
    if session.palette then
        session.palette:SetMode("background")
        session.palette:RefreshSelection()
    end
    if session.compact and not session.panelOpen then togglePanel() end
end

local function buildTopBar()
    session.toolButtons = {}
    local world = UI.Label {
        text = "无缝大地图（world）", fontSize = 11, fontColor = COLORS.text,
        width = session.compact and 165 or 190, height = 34,
        whiteSpace = "nowrap", verticalAlign = "middle", flexShrink = 0,
    }
    local title = UI.Label {
        text = "地图编辑器", fontSize = 14, fontColor = COLORS.text,
        width = 120, height = 34, whiteSpace = "nowrap", verticalAlign = "middle", flexShrink = 0,
    }
    local actions = {
        button("地图来源", openMapSource), button("地图设置", openMapSettings),
        button("导出", exportMap), button("退出并测试", exitEditor),
    }
    local toolbar = UI.Panel {
        width = "100%", padding = 8, gap = 6, backgroundColor = COLORS.surface,
        borderBottomWidth = 1, borderBottomColor = COLORS.border,
    }
    if session.compact then
        toolbar:AddChild(row({ title, world }, { width = "100%", flexWrap = "wrap" }))
        toolbar:AddChild(row(actions, { width = "100%", flexWrap = "wrap" }))
    else
        local first = { title, world, UI.Spacer() }
        for _, action in ipairs(actions) do first[#first + 1] = action end
        toolbar:AddChild(row(first, { width = "100%" }))
    end
    local tools = {}
    for _, tool in ipairs(TOOLS) do
        local choice = button(tool.label, function()
            if session.palette then session.palette:CloseOverlays() end
            ME.tool = tool.key
            ME.rectPreviewStart, ME.rectPreviewCur = nil, nil
            if tool.key == "background" then
                UIEditor.selectBackground()
            elseif session.palette and session.palette:GetSettings().mode == "background" then
                session.palette:SetMode(ME.visualLayers[ME.selectedLayer] and "tiles" or "gameplay")
            end
            refreshControls()
            if session.palette then session.palette:RefreshSelection() end
        end)
        session.toolButtons[tool.key] = choice
        tools[#tools + 1] = choice
    end
    local sizeLabel = UI.Label {
        text = "大小", fontSize = 11, fontColor = COLORS.muted,
        width = 40, height = 34, whiteSpace = "nowrap", verticalAlign = "middle", flexShrink = 0,
    }
    tools[#tools + 1] = sizeLabel
    local sizes = {}
    for _, size in ipairs(BRUSH_SIZES) do sizes[#sizes + 1] = { value = size, label = size .. " × " .. size .. " 格" } end
    session.size = UI.Dropdown {
        width = 105, minWidth = 0, height = 34, fontSize = 11, options = sizes, value = ME.brushSize,
        triggerBgColor = COLORS.inset, onChange = function(_, size) ME.brushSize = size end,
    }
    tools[#tools + 1] = session.size
    if session.compact then
        session.panelToggle = button(session.panelOpen and "收起面板" or "图层 / 瓦片", togglePanel)
        tools[#tools + 1] = session.panelToggle
    end
    toolbar:AddChild(row(tools, { width = "100%", flexWrap = "wrap" }))
    return toolbar
end

local function destroyShell()
    UI.ClearFocus()
    closeModals()
    if session.palette then
        session.paletteSettings = session.palette:GetSettings()
        session.palette:CloseOverlays()
    end
    if session.root then closeDropdowns(session.root) end
    if session.overlay then session.overlay:Destroy() end
    session.root, session.overlay, session.canvas, session.palette = nil, nil, nil, nil
    session.floating, session.panelToggle, session.status, session.size = nil, nil, nil, nil
    session.layerRows, session.toolButtons = {}, {}
end

local function buildShell()
    local scale = math.max(0.01, UI.GetScale())
    session.width, session.height, session.scale = graphics:GetWidth() / scale, graphics:GetHeight() / scale, scale
    session.compact = session.width < 960
    local topBar = buildTopBar()
    session.canvas = UI.Panel {
        id = "editorCanvas", flexGrow = 1, flexBasis = 0, flexShrink = 1, height = "100%",
        backgroundColor = { 0, 0, 0, 0 }, pointerEvents = "none",
    }
    local middle = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0, flexShrink = 1,
        flexDirection = "row", pointerEvents = "box-none", overflow = "hidden",
    }
    local viewportHeight = math.max(96, math.min(260, session.height * 0.35))
    if session.compact then
        middle:AddChild(session.canvas)
        local layers = buildLayers(true)
        session.palette = TilePalette {
            notify = UIEditor.notify, modalFactory = createModal, onChange = refreshControls,
            settings = session.paletteSettings, viewportHeight = viewportHeight,
            isCanvasPoint = UIEditor.isCanvasPoint,
        }
        local layerToggle = button("图层  +", function(self)
            local expanded = not layers:IsVisible()
            layers:SetVisible(expanded)
            self:SetText(expanded and "图层  -" or "图层  +")
        end)
        layers:SetVisible(false)
        local paletteTitle = UI.Label {
            text = "Tile Palette", fontSize = 12, fontColor = COLORS.text,
            width = 125, height = 34, whiteSpace = "nowrap", verticalAlign = "middle", flexShrink = 0,
        }
        session.floating = UI.Panel {
            position = "absolute", right = 8, top = 8, bottom = 8, width = math.min(280, session.width - 24),
            visible = session.panelOpen, zIndex = 20, backgroundColor = COLORS.surface,
            borderWidth = 1, borderColor = COLORS.border, borderRadius = 4,
            children = {
                row({ paletteTitle, UI.Spacer(), button("收起", togglePanel) }, { width = "100%", padding = 6 }),
                UI.ScrollView {
                    width = "100%", flexGrow = 1, flexBasis = 0, flexShrink = 1, bounces = false,
                    children = { UI.Panel { width = "100%", gap = 4, children = {
                        layerToggle, layers,
                        UI.Panel { width = "100%", height = math.max(280, session.height * 0.65), children = { session.palette } },
                    } } },
                },
            },
        }
        middle:AddChild(session.floating)
    else
        middle:AddChild(buildLayers(false))
        middle:AddChild(session.canvas)
        session.palette = TilePalette {
            notify = UIEditor.notify, modalFactory = createModal, onChange = refreshControls,
            settings = session.paletteSettings, viewportHeight = viewportHeight,
            isCanvasPoint = UIEditor.isCanvasPoint,
        }
        middle:AddChild(UI.Panel {
            width = 260, height = "100%", backgroundColor = COLORS.surface,
            borderLeftWidth = 1, borderLeftColor = COLORS.border, children = { session.palette },
        })
    end
    session.status = UI.Label {
        text = "", fontSize = 10, fontColor = COLORS.muted, maxLines = 1,
        flexGrow = 1, flexBasis = 0, flexShrink = 1, whiteSpace = "nowrap",
    }
    local footer = row({
        session.status, button("保存", function() if saveCurrent() then UIEditor.notify(ME.protectDraft and "共享地图未修改，无需保存；个人旧草稿保留。" or "已保存个人草稿；不会自动同步协作者，请导出更新项目版本。") end end),
        button("编辑帮助", openHelp),
    }, { width = "100%", height = 44, paddingHorizontal = 8, backgroundColor = COLORS.surface, borderTopWidth = 1, borderTopColor = COLORS.border })
    session.root = UI.Panel {
        width = "100%", height = "100%", pointerEvents = "box-none", children = {
            UI.SafeAreaView {
                width = "100%", height = "100%", nativeMenuInset = true,
                pointerEvents = "box-none", children = { topBar, middle, footer },
            },
        },
    }
    session.overlay = HUD.showOverlay({ session.root }, { dimColor = { 0, 0, 0, 0 }, pointerEvents = "box-none" })
    HUD.setGameHudVisible(false)
    refreshControls()
    UI.Layout()
end

--- 覆盖在现有 HUD 根节点上打开编辑器，不替换游戏界面。
---@param onExit? function
---@param onExport? fun(text:string)
---@param onSelectSource? fun(kind:string)
function UIEditor.show(onExit, onExport, onSelectSource)
    if session.visible then destroyShell() end
    session.onExit, session.onExport, session.onSelectSource = onExit, onExport, onSelectSource
    session.visible = true
    ME.setActive(true)
    buildShell()
    print("[地图编辑界面] 打开 " .. tostring(ME.currentLevel) .. (session.compact and "（窄屏浮动布局）" or "（宽屏停靠布局）"))
end

--- 由 main 每帧调用；HUD 已负责 UI 事件，此处不能重复调用 UI.Update。
function UIEditor.update(dt)
    if not session.visible then return end
    local scale = math.max(0.01, UI.GetScale())
    local width, height = graphics:GetWidth() / scale, graphics:GetHeight() / scale
    if math.abs(width - session.width) > 0.5 or math.abs(height - session.height) > 0.5 or math.abs(scale - session.scale) > 0.001 then
        -- 尺寸改变会使下拉框锚点和独立弹窗命中区域失效，先关闭再重建。
        destroyShell()
        buildShell()
    end
    if session.palette then session.palette:Refresh(false) end
    refreshControls()
    session.messageTime = math.max(0, session.messageTime - dt)
    if session.status then
        local state = ME.getLayerState(ME.selectedLayer)
        local status = tostring(ME.saveStatus or "")
        local failed = status == "error" or status == "failed" or status == "save_failed" or status:find("失败", 1, true) ~= nil
        local saveText = "源码已载入 · 会话未修改"
        if failed then
            saveText = "保存失败 · 会话仍在"
        elseif status == "saving" or status:find("保存中", 1, true) then
            saveText = "保存中…"
        elseif ME.dirty then
            saveText = "会话有改动 · 等待保存"
        elseif status == "saved" or status:find("已保存", 1, true) then
            saveText = "已保存（个人草稿）"
        elseif status == "unsaved" or status == "未保存" then
            saveText = "会话未保存"
        end
        local text = ("%s · %d×%d · %s%s · %s"):format(
            ME.sourceLabel .. " · world", ME.cols, ME.rows, layerLabel(ME.selectedLayer),
            state.locked and "（锁定）" or (state.visible == false and "（隐藏）" or ""), saveText)
        if session.messageTime > 0 then text = session.message .. "  |  " .. ME.sourceLabel .. " · " .. ME.cols .. "×" .. ME.rows .. " · " .. saveText end
        session.status:SetText(text)
        session.status:SetFontColor(failed and COLORS.error or COLORS.muted)
    end
end

--- 中央世界画布的系统逻辑像素矩形（物理像素 / DPR），不是 UI 基准像素。
--- R 的裁剪与 main 的地图输入必须使用相同换算；这里只查询布局，不重复重排。
---@return table {x:number,y:number,w:number,h:number}
function UIEditor.getCanvasRect()
    local dpr = math.max(0.01, graphics:GetDPR())
    if not session.visible or not session.canvas then
        return { x = 0, y = 0, w = graphics:GetWidth() / dpr, h = graphics:GetHeight() / dpr }
    end
    local l = session.canvas:GetAbsoluteLayout()
    local factor = UI.GetScale() / dpr
    return { x = l.x * factor, y = l.y * factor, w = l.w * factor, h = l.h * factor }
end

---@param x number 系统逻辑像素，不是物理像素或 UI 基准像素
---@param y number
---@return boolean
function UIEditor.isCanvasPoint(x, y)
    if not session.visible or UI.GetTopOverlay() or UIEditor.isInputFocused() then return false end
    local rect = UIEditor.getCanvasRect()
    if rect.w <= 0 or rect.h <= 0 or x < rect.x or y < rect.y or x >= rect.x + rect.w or y >= rect.y + rect.h then return false end
    if session.compact and session.panelOpen and session.floating then
        local l = session.floating:GetAbsoluteLayout()
        local factor = UI.GetScale() / math.max(0.01, graphics:GetDPR())
        if x >= l.x * factor and x < (l.x + l.w) * factor and y >= l.y * factor and y < (l.y + l.h) * factor then return false end
    end
    return true
end

--- UI.Input 仅跟踪指针，真实焦点通过 UI.GetFocus() 查询；浮层也应阻挡地图键盘。
---@return boolean
function UIEditor.isInputFocused()
    if not session.visible then return false end
    if UI.GetTopOverlay() then return true end
    local focus = UI.GetFocus()
    return focus ~= nil and focus._className == "TextField"
end

--- 外部关闭也尝试保存脏数据，保存失败则保留编辑器。
--- 退出按钮此前已保存；主调用方必须尊重 hide 返回的 false。
---@return boolean
function UIEditor.hide()
    if session.visible and ME.dirty and not saveCurrent() then return false end
    destroyShell()
    session.visible = false
    ME.setActive(false)
    HUD.hideOverlay()
    HUD.setGameHudVisible(false)
    return true
end

return UIEditor
