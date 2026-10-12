-- ============================================================================
-- ui/tuning.lua - 运行时调参面板（可视化）
-- 从暂停菜单进入；拖动滑块实时改 Config 值（各模块实时读取），松手自动存沙箱。
-- 参数清单来自 core/tuning.lua 的 SCHEMA；完整数值仍在 config.lua。
-- ============================================================================

local Tuning = require "core/tuning"
local HUD = require "ui/hud"
local UI = require "urhox-libs/UI"

---@class TuningUI
local TuningUI = {}

--- 按步长选择小数位显示
local function fmtFor(step)
    if step >= 1 then return "%.0f"
    elseif step >= 0.1 then return "%.1f"
    else return "%.2f" end
end

local function actionBtn(text, onClick, variant, width)
    return UI.Button {
        text = text, variant = variant or "secondary",
        width = width or 132, fontSize = 13,
        onClick = function() onClick() end,
    }
end

--- 打开调参面板
---@param onClose fun()|nil 关闭后回调（通常回到暂停菜单）
function TuningUI.show(onClose)
    local body = {}

    for _, grp in ipairs(Tuning.SCHEMA) do
        -- 分组标题
        table.insert(body, UI.Label {
            text = grp.group, fontSize = 14,
            fontColor = { 150, 215, 255, 255 },
        })
        for _, p in ipairs(grp.items) do
            local cur = Tuning.get(p.path, p) or p.min
            local fmt = fmtFor(p.step)
            local modified = Tuning.isModified(p.path)
            -- 值标签（闭包引用，滑块拖动时刷新）
            local valLabel = UI.Label {
                text = fmt:format(cur), fontSize = 12, width = 56,
                textAlign = "right",
                fontColor = modified and { 250, 215, 130, 255 } or { 170, 185, 215, 220 },
            }
            table.insert(body, UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Label {
                        text = p.label, fontSize = 12, width = 138,
                        fontColor = { 205, 218, 240, 235 },
                    },
                    valLabel,
                    UI.Slider {
                        flex = 1, flexShrink = 1,
                        min = p.min, max = p.max, step = p.step, value = cur,
                        onChange = function(self, value)
                            Tuning.set(p.path, value, p)       -- 实时生效（派生参数自动换算）
                            valLabel:SetText(fmt:format(value))
                        end,
                        onChangeEnd = function(self, value)
                            Tuning.set(p.path, value, p)
                            Tuning.save()                       -- 松手自动存沙箱
                        end,
                    },
                },
            })
        end
        table.insert(body, UI.Panel { height = 8, children = {} })
    end

    HUD.showOverlay({
        UI.Panel {
            width = 660, maxWidth = "94%", maxHeight = "88%",
            padding = 20, gap = 10,
            backgroundColor = { 16, 21, 36, 245 },
            borderRadius = 14, borderWidth = 1, borderColor = { 70, 90, 140, 150 },
            children = {
                -- 标题行
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label { text = "调参面板", fontSize = 20, fontColor = { 210, 235, 255, 255 } },
                        UI.Label { text = "实时生效 · 松手自动保存", fontSize = 11, fontColor = { 140, 160, 195, 220 } },
                    },
                },
                -- 参数列表
                UI.ScrollView {
                    width = "100%", flex = 1, flexShrink = 1,
                    children = {
                        UI.Panel { width = "100%", gap = 5, children = body },
                    },
                },
                -- 底部按钮
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "center", gap = 10,
                    children = {
                        actionBtn("恢复默认", function()
                            Tuning.reset()
                            Tuning.save()
                            HUD.toast("已恢复默认参数")
                            HUD.hideOverlay()
                            if onClose then onClose() end
                        end, "secondary"),
                        actionBtn("导出到控制台", function()
                            Tuning.exportText()
                            HUD.toast("参数已导出到控制台（可粘回 config.lua）")
                        end, "secondary"),
                        actionBtn("关闭", function()
                            HUD.hideOverlay()
                            if onClose then onClose() end
                        end, "primary"),
                    },
                },
            },
        },
    })
end

return TuningUI
