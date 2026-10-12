-- 碰撞体调节面板：地形格三态覆盖（默认/实心/无碰撞）+ 机关碰撞盒尺寸（米）。
-- 挂在瓦片面板的玩法 tab 下，复用 EG.selected() 的选中格，不引入独立选中状态。
local UI = require "urhox-libs/UI"
local ME = require "core.map_editor"
local EG = require "core.editor_gameplay"
local EC = require "core.editor_collision"
local TM = require "core.tilemap"
local CE = {}

local COLORS = {
    text = { 225, 228, 233, 255 },
    muted = { 150, 156, 166, 255 },
    inset = { 26, 28, 32, 255 },
    surface = { 36, 39, 44, 255 },
    selected = { 58, 96, 140, 255 },
    border = { 58, 62, 70, 255 },
}

local function label(text, muted)
    return UI.Label { text = text, fontSize = 11, whiteSpace = "normal", wordBreak = "break-word",
        fontColor = muted and COLORS.muted or COLORS.text }
end

--- 行内等分按钮：不预设宽度，交给 flex 分配，避免多个按钮横向溢出。
local function rowButton(text, callback)
    return UI.Button { text = text, height = 32, minWidth = 0, fontSize = 11,
        paddingHorizontal = 6, borderRadius = 3, backgroundColor = COLORS.surface,
        textColor = COLORS.text, flexGrow = 1, flexBasis = 0, flexShrink = 1, onClick = callback }
end

local function modeButton(text, active, callback)
    local b = rowButton(text, callback)
    b:SetStyle({ backgroundColor = active and COLORS.selected or COLORS.inset })
    return b
end

local function sizeField(value)
    return UI.TextField { width = "100%", height = 42, fontSize = 16, value = tostring(value) }
end

--- 整行大按钮：手指/鼠标都好点。
local function bigButton(text, callback)
    return UI.Button { text = text, width = "100%", height = 44, minWidth = 0, fontSize = 13,
        paddingHorizontal = 6, borderRadius = 4, backgroundColor = COLORS.surface,
        textColor = COLORS.text, onClick = callback }
end

---@param notify fun(text:string)
---@return Panel
---@return fun()
function CE.create(notify)
    notify = notify or function(text) print("[碰撞体调节] " .. text) end
    local root = UI.Panel { width = "100%", gap = 7 }

    ---@type TextField?
    local wField, hField
    ---@type fun()
    local rebuild

    local function selectCell()
        ME.selectCollisionCell()
        notify("请直接点地图上的格子（可改碰撞的格会有绿色高亮）")
    end

    local function applyTerrainMode(mode)
        local selected = EG.selected()
        if not selected then return end
        if EG.setTerrainCollision(selected.col, selected.row, mode) then
            local text = mode == "default" and "已恢复默认碰撞" or (mode == "solid" and "已设为实心碰撞" or "已设为无碰撞")
            notify(text .. "（" .. selected.col .. "," .. selected.row .. "）")
        else
            notify("碰撞层已锁定或隐藏，或该格已是此状态")
        end
        rebuild()
    end

    local function applyBox()
        local selected = EG.selected()
        if not selected or not wField or not hField then return end
        local w = tonumber(wField:GetValue())
        local h = tonumber(hField:GetValue())
        if not w or not h or w <= 0 or h <= 0 or w ~= w or h ~= h then
            notify("碰撞盒宽/高必须是正数（米）")
            return
        end
        if EG.setCollisionBox(selected.col, selected.row, w, h) then
            notify(("碰撞盒已设为 %.2f × %.2f 米"):format(w, h))
        end
        rebuild()
    end

    local function resetBox()
        local selected = EG.selected()
        if not selected then return end
        if EG.setCollisionBox(selected.col, selected.row, nil, nil) then
            notify("碰撞盒已恢复默认尺寸")
        end
        rebuild()
    end

    local lastSignature = ""
    rebuild = function()
        local selected = EG.selected()
        local selectedKey = selected and selected.key or ""
        local poly = EC.selected()
        -- 签名只取离散状态：拖动顶点不改变顶点数，避免拖拽时反复重建输入框。
        local signature = table.concat({
            tostring(ME.editRevision), selectedKey,
            tostring(EC.isDrawing()), tostring(EC.drawCount()),
            tostring(EC.selectedId), poly and tostring(#poly.vertices) or "0",
            poly and tostring(EC.isConvex(poly.vertices)) or "-",
        }, "|")
        if signature == lastSignature then return end
        lastSignature = signature
        wField, hField = nil, nil
        local previous = { table.unpack(root:GetChildren()) }
        root:ClearChildren()
        for _, child in ipairs(previous) do
            local dropdown = child --[[@as any]]
            if dropdown.Close then dropdown:Close() end
            child:Destroy()
        end

        root:AddChild(label("格子碰撞", false))
        root:AddChild(bigButton("点我，然后点地图格子", selectCell))

        -- 手绘多边形碰撞体
        root:AddChild(label("手绘多边形碰撞", false))
        local drawing = EC.isDrawing()
        if drawing then
            local n = EC.drawCount()
            root:AddChild(label(("绘制中：已加 %d 顶点（点画布加点，需 3–8 个）"):format(n), true))
            root:AddChild(UI.Panel { width = "100%", flexDirection = "row", gap = 6, children = {
                rowButton("完成", function()
                    local _, msg = EC.finishDraw(); notify(msg); rebuild()
                end),
                rowButton("撤销点", function()
                    EC.undoDrawVertex(); rebuild()
                end),
                rowButton("取消", function()
                    EC.cancelDraw(); notify("已取消绘制"); rebuild()
                end),
            } })
        else
            local polyCount = #EC.list()
            root:AddChild(label(("已有 %d 个多边形。新建后在画布依次点顶点。"):format(polyCount), true))
            root:AddChild(bigButton("＋ 新建多边形碰撞", function()
                ME.selectCollisionCell()
                EC.beginDraw()
                notify("在画布上依次点击顶点，加够后点「完成」")
                rebuild()
            end))
            local poly = EC.selected()
            if poly then
                local _, convex = EC.selectedConvex()
                root:AddChild(label(("已选多边形（%d 顶点）%s"):format(#poly.vertices,
                    convex and "" or " · 凹形！Box2D 会异常，请改凸"), true))
                root:AddChild(UI.Panel { width = "100%", flexDirection = "row", gap = 6, children = {
                    rowButton("删顶点", function()
                        local _, msg = EC.removeSelectedVertex(); notify(msg); rebuild()
                    end),
                    rowButton("删整个", function()
                        local _, msg = EC.removeSelected(); notify(msg); rebuild()
                    end),
                } })
                root:AddChild(label("拖黄点改形状；点边线插顶点（≤8）。", true))
            end
        end

        if not selected then
            root:AddChild(label("点上面的「点我」按钮，再点地图格，可改格子碰撞。", true))
            return
        end

        local char = selected.char
        local el = TM.LEGEND[char]
        local name = (char == " ") and "空格（仅视觉瓦片）" or selected.label
        root:AddChild(label(("已选 %s（%d,%d）"):format(name, selected.col, selected.row)))

        if el and el.type == "hazard" then
            local w, h = EG.collisionBox(selected.col, selected.row)
            root:AddChild(label("机关碰撞盒（米）：运行时按此尺寸替换默认盒。", true))
            wField, hField = sizeField(w), sizeField(h)
            local function cell(text, field)
                return UI.Panel { flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 4,
                    children = { label(text), field } }
            end
            root:AddChild(UI.Panel { width = "100%", flexDirection = "row", gap = 8, children = {
                cell("宽（米）", wField), cell("高（米）", hField),
            } })
            root:AddChild(UI.Panel { width = "100%", flexDirection = "row", gap = 6, children = {
                rowButton("应用尺寸", applyBox),
                rowButton("恢复默认", resetBox),
            } })
        else
            local mode = EG.terrainCollision(selected.col, selected.row)
            local modeText = mode == "solid" and "实心" or (mode == "none" and "无碰撞" or "默认")
            root:AddChild(label("地形格碰撞（不改外观）：" .. modeText, true))
            root:AddChild(UI.Panel { width = "100%", flexDirection = "row", gap = 6, children = {
                modeButton("默认", mode == "default", function() applyTerrainMode("default") end),
                modeButton("实心", mode == "solid", function() applyTerrainMode("solid") end),
                modeButton("无碰撞", mode == "none", function() applyTerrainMode("none") end),
            } })
        end
    end

    rebuild()
    return root, rebuild
end

return CE
