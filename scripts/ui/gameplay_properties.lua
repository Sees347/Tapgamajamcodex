-- 编辑器元素属性面板：从多个泉眼中选择出生点，显式连接压板/接口与机关。
local UI = require "urhox-libs/UI"
local ME = require "core.map_editor"
local EG = require "core.editor_gameplay"
local GP = {}

local function label(text)
    return UI.Label { text = text, fontSize = 11, whiteSpace = "normal", wordBreak = "break-word", fontColor = { 225, 228, 233, 255 } }
end
local function button(text, callback)
    return UI.Button { text = text, width = "100%", height = 32, minWidth = 0, fontSize = 11,
        paddingHorizontal = 6, borderRadius = 3, backgroundColor = { 36, 39, 44, 255 }, onClick = callback }
end

local DETAILS = {
    S = "泉眼：触碰回血、变回液态并绑定复活点。初始出生点需要下方明确指定。",
    t = "普通出生标记：不存档。下方可设为初始出生点。",
    P = "压板：固态玩家踩下后输出信号，需要连接到门或报警器。",
    O = "电力接口：装备电鳗后靠近供电，需要连接到门或报警器。",
    D = "电子门：连接压板/接口后开启，失去信号关闭；没有连接时默认关闭。",
    A = "报警器：通电后，气态玩家在其下方靠近触发喷水。",
    F = "火区：进入升温一级并持续扣水。", f = "弱火：液态接触可熄灭，仍有火伤。",
    C = "低温：进入降低一级形态。", W = "凝珠：水量未满时触碰吸收3水，随后消耗。",
    Z = "海绵：接触持续吸水。", X = "箱子：阻挡移动，受到攻击后破坏。",
}

function GP.create(notify)
    local root = UI.Panel { width = "100%", gap = 7 }
    local revision, selection = "", ""
    local function rebuild()
        local selected = EG.selected()
        local selectedKey = selected and selected.key or ""
        local signature = tostring(ME.editRevision)
        if signature == revision and selectedKey == selection then return end
        revision, selection = signature, selectedKey
        local initialOptions = { { value = "", label = "请选择泉眼或出生点" } }
        for _, item in ipairs(EG.list("St")) do
            initialOptions[#initialOptions + 1] = { value = item.key, label = item.label }
        end
        local sources = EG.list("PO")
        local previous = { table.unpack(root:GetChildren()) }
        root:ClearChildren()
        for _, child in ipairs(previous) do
            local dropdown = child --[[@as Dropdown]]
            if dropdown.Close then dropdown:Close() end
            child:Destroy()
        end
        root:AddChild(label("初始出生点"))
        root:AddChild(UI.Dropdown { id = "initialSpawnChoice", width = "100%", height = 34, fontSize = 11,
            options = initialOptions, value = EG.initialKey(), maxVisibleItems = 6,
            onChange = function(_, key)
                if key == "" then return end
                local _, message = EG.setInitial(key)
                notify(message)
                revision = ""
            end })
        root:AddChild(label("可放多个泉眼，但只有选定的一个是新游戏/编辑试玩的初始点；正式游戏继续与死亡仍用最近绑定泉眼。"))
        root:AddChild(button("选取地图元素", function()
            ME.tool = "select"
            notify("点击地图中的玩法标记，再查看这里的属性")
        end))
        if not selected then
            root:AddChild(label("尚未选中玩法元素。图片瓦片只是外观，不会自动变成泉眼、门或敌人；需放置相应玩法标记。"))
            return
        end
        root:AddChild(label("已选：" .. selected.label .. "（" .. selected.col .. "," .. selected.row .. "）"))
        root:AddChild(label(DETAILS[selected.char] or "退出并测试后生成对应敌人/拾取物；编辑状态只显示位置标记。"))
        if selected.char == "S" or selected.char == "t" then
            root:AddChild(button("设为初始出生点", function()
                local _, message = EG.setInitial(selected.key)
                notify(message)
                revision = ""
            end))
        end
        if selected.char == "D" or selected.char == "A" then
            local options = { { value = "", label = "选择压板或电力接口" } }
            for _, item in ipairs(sources) do options[#options + 1] = { value = item.key, label = item.label } end
            local sourceKey = ""
            root:AddChild(UI.Dropdown { id = "wireSourceChoice", width = "100%", height = 34, fontSize = 11,
                options = options, value = "", maxVisibleItems = 6, onChange = function(_, key) sourceKey = key end })
            root:AddChild(button("连接到所选机关", function()
                local _, message = EG.connect(sourceKey, selected.key)
                notify(message)
                revision = ""
            end))
            local count, sourceIds, connected = 0, {}, {}
            for _, source in ipairs(sources) do sourceIds[source.id] = true end
            for _, wire in ipairs(ME.metadata.wires or {}) do
                if wire.to == selected.id and sourceIds[wire.from] and not connected[wire.from] then
                    count = count + 1
                    connected[wire.from] = true
                end
            end
            root:AddChild(label("有效输入连接数：" .. count .. "（多个输入按任一激活）"))
            root:AddChild(button("移除此机关的输入连接", function()
                notify(EG.disconnect(selected.key) and "输入连接已移除" or "没有可移除的连接")
                revision = ""
            end))
        end
    end
    rebuild()
    return root, rebuild
end

return GP
