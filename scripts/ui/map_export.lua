-- 完整地图文本导出/导入。仅使用已核实的 UI 和系统剪贴板 API。
-- File 是项目/用户沙箱（Web 刷新即丢失），不是浏览器下载；本模块不写任何沙箱。
local UI = require "urhox-libs/UI"
local ME = require "core.map_editor"
local TS = require "core.tilesets"
local Tilemap = require "core.tilemap"
local Backgrounds = require "core.map_backgrounds"

local Export = {}
local PAGE_BYTES = 512 -- TextField 每帧逐字测量，绝不能把百万格全文交给它渲染。
local MAX_BYTES = 64 * 1024 * 1024
local VISUAL_IDS = { "background", "ground", "foreground" }
local COLORS = { text = {225, 228, 233, 255}, muted = {157, 165, 176, 255}, error = {255, 157, 145, 255} }

---@class MapExportOptions
---@field modalFactory fun(title:string):Modal
---@field notify fun(text:string)
---@field onImport? function
---@field onExport? fun(text:string)

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function integer(value, minimum, maximum)
    return finite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end
local function requireValue(condition, message)
    if not condition then error(message, 0) end
end
local function array(value, name, maximum)
    requireValue(type(value) == "table", name .. " 必须是数组")
    local count = 0
    for key in pairs(value) do
        requireValue(integer(key, 1, maximum), name .. " 必须是一基连续数组")
        count = count + 1
    end
    requireValue(count == #value and count <= maximum, name .. " 数量超限或数组不连续")
    for index = 1, count do requireValue(value[index] ~= nil, name .. " 数组不连续") end
end

-- JSON 往返不可保留函数、循环引用、非有限数或混合/稀疏数字键，不能静默丢字段。
local function validateValue(value, depth, seen, budget)
    budget.count = budget.count + 1
    requireValue(budget.count <= 8000000 and depth <= 40, "数据过大或嵌套超过40层")
    local kind = type(value)
    if kind == "string" then
        requireValue(#value <= MAX_BYTES and utf8.len(value) ~= nil, "字符串过大或不是有效UTF-8")
    elseif kind == "number" then requireValue(finite(value), "数据包含非有限数值")
    elseif kind == "table" then
        requireValue(not seen[value], "数据包含循环引用")
        seen[value] = true
        local numeric, textual, count = false, false, 0
        for key, child in pairs(value) do
            if type(key) == "number" then
                requireValue(integer(key, 1, 8000000), "JSON 数字键必须是正整数数组索引")
                numeric = true
            else
                requireValue(type(key) == "string" and utf8.len(key) ~= nil, "JSON 对象键必须是UTF-8字符串")
                textual = true
            end
            count = count + 1
            validateValue(child, depth + 1, seen, budget)
        end
        requireValue(not (numeric and textual) and (not numeric or count == #value), "JSON 不支持混合键或稀疏数组；请取走完整Lua SRC")
        if numeric then for index = 1, count do requireValue(value[index] ~= nil, "JSON不支持稀疏数组") end end
        seen[value] = nil
    else requireValue(kind == "boolean", "数据只能包含JSON纯数据，不能含 null、函数或对象") end
end

local function sameData(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not sameData(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function cellKey(key, cols, rows)
    local c, r = Tilemap.cellCoords(key, cols, rows)
    requireValue(c ~= nil and r ~= nil and key == tostring(c) .. ":" .. tostring(r), "格子键无效或越界：" .. tostring(key))
end
local function layerState(value, name)
    requireValue(type(value) == "table", name .. " 缺少状态对象")
    requireValue(type(value.visible) == "boolean" and type(value.locked) == "boolean", name .. " 的 visible/locked 必须是布尔值")
end

-- 完整验证在任何编辑器/瓦片集写操作之前进行，不使用宽松 normalize 截断坏数据。
local function validateData(data)
    validateValue(data, 0, {}, { count = 0 })
    requireValue(type(data) == "table" and data.version == 2, "仅支持本编辑器导出的 version=2 完整JSON")
    requireValue(type(data.level) == "string" and data.level == (ME.currentLevel or "world"), "地图ID必须与当前地图一致，不能把其它关卡覆盖为world")
    requireValue(Tilemap.validDimensions(data.cols, data.rows), "地图尺寸无效（宽1–2048，高1–512，总格数≤1048576）")
    requireValue(finite(data.tile) and data.tile > 0 and finite(data.originX) and finite(data.originY), "tile必须为正有限米数，originX/Y必须是有限数")
    requireValue(finite(data.originX + data.cols * data.tile) and finite(data.originY - data.rows * data.tile), "地图世界边界计算溢出")
    requireValue(type(data.map) == "string" and #data.map <= Tilemap.MAX_CELLS + Tilemap.MAX_ROWS, "缺少map或字符地图过大")
    local lineCount = 0
    for line in (data.map .. "\n"):gmatch("([^\n]*)\n") do
        lineCount = lineCount + 1
        requireValue(#line == data.cols, "字符地图每行必须恰好为cols格，不能裁剪或补齐")
        requireValue(not line:find("[^ -~]"), "字符地图只能使用单字节ASCII标记和空格")
    end
    requireValue(lineCount == data.rows, "字符地图行数与rows不符（含首尾空白行）")
    requireValue(type(data.visualLayers) == "table" and type(data.layerStates) == "table" and type(data.collisionCells) == "table", "缺少视觉层、图层状态或碰撞覆盖")
    array(data.tilesets, "tilesets", 256)
    local sets = { builtin = true }
    for _, definition in ipairs(data.tilesets) do
        requireValue(type(definition) == "table" and type(definition.id) == "string" and #definition.id <= 64
            and definition.id:match("^[%w_-]+$") and not sets[definition.id], "瓦片集ID无效或重复")
        sets[definition.id] = true
        -- 切片/路径的完整验证由TS.loadDefinitions原子执行；此处只读预检。
        requireValue(type(definition.path) == "string" and definition.path:sub(1, #"image/地图/tiles/") == "image/地图/tiles/", "瓦片集资源路径不在image/地图/tiles/")
        requireValue(integer(definition.cellWidth, 1, 65536) and integer(definition.cellHeight, 1, 65536)
            and integer(definition.margin, 0, 65536) and integer(definition.spacing, 0, 65536), "瓦片集切片参数无效")
        requireValue(definition.collider == "ground" or definition.collider == "decoration", "瓦片集碰撞类型无效")
    end
    for id in pairs(data.visualLayers) do
        requireValue(id == "background" or id == "ground" or id == "foreground", "存在不支持的视觉图层：" .. tostring(id))
    end
    for _, id in ipairs(VISUAL_IDS) do
        local layer = data.visualLayers[id]
        layerState(layer, id)
        requireValue(type(layer.cells) == "table", id .. " 缺少cells")
        for key, cell in pairs(layer.cells) do
            cellKey(key, data.cols, data.rows)
            requireValue(type(cell) == "table" and sets[cell.tilesetId] == true and integer(cell.tileId, 1, 2147483647)
                and (cell.collider == "ground" or cell.collider == "decoration"), "瓦片无效、缺少对应tilesets定义或碰撞类型错误：" .. tostring(key))
            if cell.tilesetId == "builtin" then requireValue(cell.tileId <= 8, "builtin瓦片编号必须为1–8") end
        end
    end
    for key, value in pairs(data.collisionCells) do
        cellKey(key, data.cols, data.rows)
        requireValue(type(value) == "boolean", "碰撞覆盖必须是布尔值（false不能省略）")
    end
    layerState(data.layerStates.collision, "collision")
    layerState(data.layerStates.gameplay, "gameplay")
    requireValue(type(data.metadata) == "table", "缺少完整metadata")
    local warnings = {}
    local metadata = data.metadata
    requireValue(data.backgroundImages == nil, "完整v2 JSON的backgroundImages必须放在metadata，不能重复放在顶层")
    if metadata.backgroundImages ~= nil then
        local valid, err = Backgrounds.validate(metadata.backgroundImages)
        requireValue(valid, "地图背景配置无效：" .. tostring(err))
    end
    requireValue(metadata.tilesets == nil, "完整v2 JSON的tilesets必须放在顶层，不能重复嵌套在metadata")
    for _, name in ipairs({ "spawn", "arrival" }) do
        if metadata[name] ~= nil then
            requireValue(type(metadata[name]) == "table" and finite(metadata[name].x) and finite(metadata[name].y), name .. " 必须包含有限数x/y")
        end
    end
    for _, name in ipairs({ "id", "name", "subtitle", "theme", "startForm", "progressId", "bgMusic" }) do
        requireValue(metadata[name] == nil or type(metadata[name]) == "string", "metadata." .. name .. "必须是字符串")
    end
    requireValue(metadata.seamless == nil or type(metadata.seamless) == "boolean", "metadata.seamless必须是布尔值")
    requireValue(metadata.deathY == nil or finite(metadata.deathY), "metadata.deathY必须是有限数")
    if metadata.bounds ~= nil then
        requireValue(type(metadata.bounds) == "table", "metadata.bounds必须是对象")
        for _, name in ipairs({ "minX", "maxX", "minY", "maxY" }) do requireValue(finite(metadata.bounds[name]), "bounds." .. name .. "必须是有限数") end
        requireValue(metadata.bounds.minX <= metadata.bounds.maxX and metadata.bounds.minY <= metadata.bounds.maxY, "bounds最小值不能大于最大值")
    end
    for _, name in ipairs({ "story", "exits", "wires" }) do
        if metadata[name] ~= nil then array(metadata[name], "metadata." .. name, 1048576) end
    end
    local spawn = metadata.initialSpawnCell
    if spawn ~= nil then
        requireValue(type(spawn) == "table" and finite(spawn.col) and spawn.col % 1 == 0
            and finite(spawn.row) and spawn.row % 1 == 0, "initialSpawnCell的col/row必须为整数")
        local lines = Tilemap.readRows(data.map, data.cols, data.rows)
        local ch = lines[spawn.row] and lines[spawn.row]:sub(spawn.col, spawn.col)
        if not integer(spawn.col, 1, data.cols) or not integer(spawn.row, 1, data.rows) or (ch ~= "S" and ch ~= "t") then
            warnings[#warnings + 1] = "初始存档点选择已失效，数据原样保留；请在玩法层选取S/t重新设置。"
        end
    end
    if metadata.elementProperties ~= nil then
        requireValue(type(metadata.elementProperties) == "table", "elementProperties必须是对象")
        for key, props in pairs(metadata.elementProperties) do
            requireValue(type(key) == "string" and key:match("^%d+:%d+$") and type(props) == "table", "玩法属性必须为col:row对象")
            for _, field in ipairs({ "active", "needsPower", "open", "powered" }) do
                requireValue(props[field] == nil or type(props[field]) == "boolean", "玩法属性" .. field .. "必须是布尔值")
            end
            for _, field in ipairs({ "w", "h" }) do
                requireValue(props[field] == nil or (finite(props[field]) and props[field] > 0), "玩法属性" .. field .. "必须是正有限米数")
            end
            requireValue(props.charges == nil or integer(props.charges, 1, 2147483647), "玩法属性charges必须为正整数")
        end
    end
    local knownEndpoints = {}
    local progressId = metadata.progressId or metadata.id or data.level
    if metadata.wires and #metadata.wires > 0 then
        local rows = Tilemap.readRows(data.map, data.cols, data.rows)
        for r, line in ipairs(rows) do
            for c = 1, data.cols do
                local ch = line:sub(c, c)
                if ch == "P" or ch == "O" or ch == "D" or ch == "A" then
                    knownEndpoints[("%s_%d_%d"):format(progressId, c - 1, r - 1)] = ch
                end
            end
        end
    end
    local invalidWires = 0
    for _, wire in ipairs(metadata.wires or {}) do
        requireValue(type(wire) == "table" and type(wire.from) == "string" and type(wire.to) == "string", "wires的from/to必须是字符串")
        local from, to = knownEndpoints[wire.from], knownEndpoints[wire.to]
        if (from ~= "P" and from ~= "O") or (to ~= "D" and to ~= "A") then invalidWires = invalidWires + 1 end
    end
    if invalidWires > 0 then warnings[#warnings + 1] = ("%d条旧连接的端点已失效，原样保留；请在玩法属性重新配置。"):format(invalidWires) end
    return table.concat(warnings, "\n")
end

--- 只解码/验证，不修改地图；不执行Lua，不读取/写入沙箱。
---@param text string
---@return table? data
---@return string? error
---@return string? warning
function Export.decode(text)
    if type(text) ~= "string" or #text == 0 or #text > MAX_BYTES then return nil, "请粘贴完整JSON，最多64MiB" end
    local ok, data, warning = pcall(function()
        local result = cjson.decode(text)
        return result, validateData(result)
    end)
    if not ok then return nil, tostring(data) end
    return data --[[@as table]], nil, warning
end

--- 先准备完整网格，再原子安装瓦片注册表；任何失败恢复原地图对象/状态。
---@param data table
---@return boolean
---@return string? error
function Export.apply(data)
    local valid, validation = pcall(validateData, data)
    if not valid then return false, tostring(validation) end
    local previous = {}
    for _, key in ipairs({ "grid", "cols", "rows", "tile", "originX", "originY", "currentLevel", "metadata",
        "visualLayers", "collisionCells", "layerStates", "rectPreviewStart", "rectPreviewCur", "selectedCell", "editRevision", "dirty", "saveStatus" }) do
        previous[key] = ME[key]
    end
    local source = {}
    for key, value in pairs(data) do source[key] = value end
    source.tilesets = nil -- loadSource会吞瓦片注册失败，所以注册表必须单独检查。
    local ok, err = pcall(function()
        requireValue(ME.loadSource(source) == true, "地图载入失败")
        local installed, reason = TS.loadDefinitions(data.tilesets)
        requireValue(installed == true, "瓦片集载入失败：" .. tostring(reason))
    end)
    if not ok then
        for _, key in ipairs({ "grid", "cols", "rows", "tile", "originX", "originY", "currentLevel", "metadata",
            "visualLayers", "collisionCells", "layerStates", "rectPreviewStart", "rectPreviewCur", "selectedCell", "editRevision", "dirty", "saveStatus" }) do
            ME[key] = previous[key]
        end
        return false, tostring(err)
    end
    ME.markDirty()
    ME.centerCamera()
    return true
end

-- TextField只有单行且逐字测量；分块保证原文无截断，同时整份复制永远使用完整字符串。
---@param text string
---@param first integer
---@return integer
local function pageEnd(text, first)
    local last = math.min(#text, first + PAGE_BYTES - 1)
    if last < #text then
        while last >= first and text:byte(last + 1) >= 128 and text:byte(last + 1) < 192 do last = last - 1 end
    end
    return last
end
---@param text string
---@return string[]
function Export.pages(text)
    local pages, first = {}, 1
    while first <= #text do
        local last = pageEnd(text, first)
        pages[#pages + 1] = text:sub(first, last)
        first = last + 1
    end
    if #pages == 0 then pages[1] = "" end
    return pages
end

local function textLabel(text, muted)
    return UI.Label { text = text, fontSize = 11, whiteSpace = "normal", wordBreak = "break-word", fontColor = muted and COLORS.muted or COLORS.text }
end
local function action(text, callback)
    return UI.Button { text = text, height = 34, minWidth = 0, paddingHorizontal = 9, fontSize = 11, borderRadius = 3, onClick = callback }
end
local function buttons(children)
    return UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6, children = children }
end

local function copyText(text)
    local ok, readBack = pcall(function()
        ui:SetUseSystemClipboard(true)
        ui:SetClipboardText(text) -- 返回nil，不是假定true成功；写后回读，但Web仍需用户外部验证。
        return ui:GetClipboardText()
    end)
    if not ok or readBack ~= text then return false, "无法确认系统剪贴板写入；请重试，或逐页全选后Ctrl+C/长按拷贝。原文仍保留。" end
    if GetPlatform() == "Web" then return true, "已调用系统复制；浏览器权限/异步写入无法确认，请立即在游戏外粘贴验证。不是文件下载。" end
    return true, "文本已复制并回读一致；请在游戏外粘贴保存为文件。"
end

-- 只读但仍可全选/复制；disabled会禁止选择/拷贝，故采用TextField子类。
---@class MapExportTextField : TextField
---@overload fun(props?:TextFieldProps):MapExportTextField
local ReadOnlyField = UI.TextField:Extend("MapExportTextField")
function ReadOnlyField:OnTextInput(text) end
function ReadOnlyField:DoCut() UI.TextField.DoCopy(self) end
function ReadOnlyField:OnKeyDown(key)
    if key ~= KEY_BACKSPACE and key ~= KEY_DELETE then UI.TextField.OnKeyDown(self, key) end
end

-- 不给TextField巨量value，粘贴事件直接存入独立缓冲；可接收完整或连续分段JSON。
---@class MapJsonPasteField : TextField
---@overload fun(props?:TextFieldProps):MapJsonPasteField
local PasteField = UI.TextField:Extend("MapJsonPasteField")
function PasteField:OnTextInput(text)
    if self.state.focused and not self.props.disabled and self.props.onChange then self.props.onChange(self, text) end
end

---@param options MapExportOptions
function Export.openImport(options)
    local modal = options.modalFactory("导入完整地图JSON")
    modal:SetSize("fullscreen")
    local buffer = { text = "" }
    local status = textLabel("未载入JSON。只改变当前会话；确认前验证，失败保留原地图与沙箱。", true)
    local preview = textLabel("", true)
    local function message(text, failed)
        status:SetText(text)
        status:SetFontColor(failed and COLORS.error or COLORS.text)
        options.notify(text)
    end
    local function update(text, append)
        local incoming = append and (buffer.text .. text) or text
        if #incoming > MAX_BYTES then message("JSON超过64MiB，输入未接收。", true); return end
        buffer.text = incoming
        status:SetText(("已接收 %d 字节，尚未应用；点击验证后确认覆盖。\n"):format(#incoming))
        preview:SetText("开头预览（不影响完整导入）：\n" .. incoming:sub(1, pageEnd(incoming, 1)))
    end
    local paste = PasteField {
        width = "100%", height = 38, fontSize = 11, placeholder = "点击后Ctrl+V / 长按粘贴完整JSON（可连续分段）",
        onChange = function(_, text) update(text, true) end,
    }
    local form = UI.Panel { width = "100%", gap = 8, children = {
        textLabel("请先在外部备份当前地图。只接受导出的captureData JSON，不接受Lua SRC，不执行代码。地图ID须相同。图片文件不会嵌入JSON，仍需当前版本包含对应资源。", true),
        paste,
        buttons({
            action("读取剪贴板", function()
                local ok, text = pcall(function() ui:SetUseSystemClipboard(true); return ui:GetClipboardText() end)
                if not ok or type(text) ~= "string" or text == "" then message("读取剪贴板失败或为空；请点击输入框Ctrl+V/长按粘贴。", true); return end
                update(text, false)
            end),
            action("清空输入", function() buffer.text = ""; preview:SetText(""); status:SetText("输入已清空，地图未修改。") end),
        }), status, preview,
    } }
    modal:AddContent(UI.ScrollView { width = "100%", height = math.max(120, UI.GetHeight() * 0.65 - 100), bounces = false, children = { form } })
    modal:SetFooter(buttons({
        action("取消", function() modal:Close() end),
        action("验证JSON", function()
            local data, err, warning = Export.decode(buffer.text)
            if not data then message("导入验证失败，原地图未修改：" .. tostring(err), true); return end
            local confirmation = options.modalFactory("确认覆盖当前会话地图")
            local content = textLabel(("地图结构已验证：%d×%d 格、三张视觉层、玩法/碰撞、metadata与tilesets。瓦片集登记将在确认时复核，失败保留原地图。将替换当前会话地图（不可撤销），不写沙箱；原世界进度不变。\n%s"):format(data.cols, data.rows, warning or ""))
            confirmation:AddContent(UI.ScrollView { width = "100%", height = math.max(90, math.min(200, UI.GetHeight() * 0.4)), bounces = false, children = { content } })
            confirmation:SetFooter(buttons({
                action("取消", function() confirmation:Close() end),
                action("确认导入", function()
                    local applied, applyError = Export.apply(data)
                    if not applied then
                        confirmation:Close()
                        message("导入失败，已保留原地图：" .. tostring(applyError), true)
                        return
                    end
                    confirmation:Close(); modal:Close()
                    if options.onImport then options.onImport() end
                    options.notify("JSON已导入当前会话，等待保存；未覆盖沙箱。" .. (warning or ""))
                end),
            }))
            confirmation:Open()
        end),
    }))
    modal:Open()
end

---@param options MapExportOptions
function Export.open(options)
    local id = ME.currentLevel or "world"
    local name = type(ME.metadata.name) == "string" and ME.metadata.name or id
    local sourceOK, source = pcall(ME.exportLevelFile, id, name)
    local jsonOK, json = pcall(function()
        local data = ME.captureData()
        validateValue(data, 0, {}, { count = 0 })
        local encoded = cjson.encode(data)
        requireValue(#encoded <= MAX_BYTES, "JSON超过64MiB")
        requireValue(sameData(data, cjson.decode(encoded)), "JSON编码往返不能完整保留数据/数值精度；请取走Lua SRC")
        return encoded
    end)
    if sourceOK and type(source) ~= "string" then sourceOK, source = false, "源文件接口没有返回文本" end
    local documents = {
        json = { text = jsonOK and json or "", error = not jsonOK and tostring(json) or nil, filename = id .. ".json" },
        src = { text = sourceOK and source or "", error = not sourceOK and tostring(source) or nil, filename = "scripts/levels/" .. id .. "_src.lua" },
    }
    local modal = options.modalFactory("完整地图导出 / 取走文本")
    modal:SetSize("fullscreen")
    local current = { format = jsonOK and "json" or "src", page = 1, pages = {} }
    local filename = textLabel("")
    local pageLabel = textLabel("", true)
    local status = textLabel("", true)
    local raw = ReadOnlyField { width = "100%", height = 38, value = "", fontSize = 10 }
    local preview = textLabel("", true)
    local function message(text, failed)
        status:SetText(text)
        status:SetFontColor(failed and COLORS.error or COLORS.text)
        options.notify(text)
    end
    local function showPage()
        local page = current.pages[current.page] or ""
        raw:SetValue(page); raw:ClearSelection(); raw:SetState({ cursorPos = 0, scrollX = 0 })
        preview:SetText(page)
        pageLabel:SetText(("原文第 %d / %d 页（无省略），%d 字节；逐页复制时按顺序拼接，不加分隔/换行。"):format(current.page, #current.pages, #documents[current.format].text))
    end
    local function choose(format)
        current.format, current.page = format, 1
        local document = documents[format]
        current.pages = Export.pages(document.text)
        filename:SetText("外部另存为 " .. document.filename)
        showPage()
        if document.error then message("此格式导出失败：" .. document.error, true)
        else status:SetText("完整文本已生成。可整份复制；下方全部分页可选择。尚未保存为系统文件。"); status:SetFontColor(COLORS.text) end
    end
    local form = UI.Panel { width = "100%", gap = 8, children = {
        textLabel("当前Lua API未提供可核实的浏览器文件下载/平台文件分享，本窗口不会声称下载成功。点击整份复制后在游戏外粘贴并另存为文件；Web须外部验证复制。沙箱仅属项目/用户，网页刷新会丢失，不等于版本源码。本操作不写沙箱。", true),
        textLabel("JSON是完整captureData（尺寸、三视觉层、玩法map、true/false碰撞、metadata、tilesets），可重新导入。Lua SRC包含完整源表；替换*_src.lua，不要替换解析包装文件。图集只含路径/切片参数，不嵌入图片。", true),
        buttons({ action("完整JSON", function() choose("json") end), action("完整Lua SRC", function() choose("src") end) }),
        filename, status,
        buttons({
            action("复制整份", function()
                local document = documents[current.format]
                if document.error then message("无法复制：" .. document.error, true); return end
                local ok, result = copyText(document.text); message(result, not ok)
            end),
            action("上一页", function() current.page = math.max(1, current.page - 1); showPage() end),
            action("下一页", function() current.page = math.min(#current.pages, current.page + 1); showPage() end),
            action("全选本页", function() UI.SetFocus(raw); raw:SelectAll() end),
            action("复制本页", function() local ok, result = copyText(current.pages[current.page] or ""); message(result, not ok) end),
        }), pageLabel, raw,
        textLabel("换行阅读预览（原文仍在上方可选择输入框，整份复制不受分页影响）：", true), preview,
    } }
    modal:AddContent(UI.ScrollView { width = "100%", height = math.max(120, UI.GetHeight() * 0.72 - 90), bounces = false, children = { form } })
    modal:SetFooter(buttons({
        action("重新导入JSON", function() modal:Close(); Export.openImport(options) end),
        action("关闭", function() modal:Close() end),
    }))
    choose(current.format)
    modal:Open()
    if sourceOK and options.onExport then
        local called, err = pcall(options.onExport, source)
        if not called then message("文本已生成，但外部导出回调失败：" .. tostring(err), true) end
    end
    options.notify((jsonOK or sourceOK) and "已打开完整地图导出窗口；请复制到游戏外保存，不是文件下载。" or "两种格式均导出失败，原地图保留；详情见弹窗。")
end

return Export
