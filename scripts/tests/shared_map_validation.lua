-- 仅验收共享/个人来源切换；地图与进度写入都隔离在内存，不触碰真实草稿。
local V = assert(rawget(_G, "V"))
local ME = require "core.map_editor"
local World = require "core.world_map"
local PT = require "core.playtest"
local GS = require "core.state"
local UI = require "urhox-libs/UI"
local HUD = require "ui.hud"
local Editor = require "ui.map_editor"
local L = require "core.level"
local realSave, realPeek, realExists, realProgress = ME.saveToSandbox, ME.peekSandbox, World.snapshotExists, GS.saveGame
local old = { level = "world", cols = 8, rows = 5, tile = 1, originX = 0, originY = 5,
    map = "        \n t      \n        \n        \n########", metadata = { spawn = { x = 1.5, y = 3.9 } } }
local memory = { world = old }
local mapWrites, progressWrites = 0, 0
local expected = ""
local function find(widget, text)
    if widget._className == "Button" and widget.props.text == text then return widget end
    for _, child in ipairs(widget:GetChildren()) do local result = find(child, text); if result then return result end end
    if widget.GetHitTestChildren then
        for _, child in ipairs(widget:GetHitTestChildren() or {}) do local result = find(child, text); if result then return result end end
    end
end
local function click(text)
    local target = find(UI.GetTopOverlay() or HUD.root, text)
    V.assert(target ~= nil, "来源操作入口存在：" .. text)
    if target then target.props.onClick(target) end
    UI.Layout()
end
V.atFrame(10, function()
    GS.save = GS.defaultSave()
    GS.saveGame = function() progressWrites = progressWrites + 1 end
    ME.peekSandbox = function(id) return memory[id] end
    World.snapshotExists = function(id) return memory[id] ~= nil end
    ME.saveToSandbox = function()
        if ME.protectDraft and not ME.dirty then return realSave() end
        mapWrites = mapWrites + 1
        memory[ME.draftSlot] = ME.captureData()
        ME.dirty, ME.protectDraft = false, false
        return true
    end
    local shared = World.source()
    V.assert(shared.cols == 300 and shared.rows == 200, "旧8×5个人存档不会遮盖上传的300×200共享地图")
    assert(rawget(_G, "LoadLevel"))("world")
    V.assert(L.def.tilemapData.cols == 300 and #L.def.tilemapData.backgroundImages == 4, "普通游戏使用上传的共享地图与4张背景")
    local images = L.def.tilemapData.backgroundImages
    local right2 = images[2].x + images[2].width / 2
    local left3 = images[3].x - images[3].width / 2
    V.assert(math.abs(right2 - left3) < 0.000000001, "背景2/3精确相接，不放大或额外搭接")
    V.assert(images[3].width == 60 and images[3].y == -178.91364506846, "背景黑线修正保留宽度、比例和纵向布局")
    assert(rawget(_G, "OpenMapEditor"))()
    V.assert(ME.cols == 300 and ME.sourceLabel == "项目共享地图", "默认编辑器也使用共享版本并明确来源")
    click("保存")
    V.assert(mapWrites == 0 and memory.world == old, "共享图未修改不写入或覆盖个人旧草稿")
end)
V.atFrame(35, function()
    click("地图来源"); click("查看我的旧地图草稿")
    V.assert(ME.cols == 8 and ME.draftSlot == "world" and ME.sourceLabel == "我的旧地图草稿", "可显式继续旧图，逻辑ID仍为world")
    ME.grid[3][3] = "$"; ME.markDirty()
    click("地图来源"); click("加载项目共享地图")
    V.assert(ME.cols == 300 and memory.world.map:find("$", 1, true) ~= nil, "切回共享版本前保留个人草稿修改")
    V.assert(ME.draftSlot == "world_shared_draft" and ME.protectDraft, "共享编辑保存槽与旧个人world隔离")
    ME.grid[1][1] = "$"; ME.markDirty()
    expected = ME.exportString()
    click("退出并测试")
    V.assert(PT.active and not ME.active and PT.worldSource ~= nil, "退出试玩固定当前编辑快照")
    V.assert(L.def.tilemapData.map == expected and L.def.tilemapData.cols == 300, "试玩不回到旧个人图或未修改共享图")
    V.assert(memory.world.cols == 8 and memory.world_shared_draft.cols == 300, "共享编辑草稿另存且旧图保留")
    V.assert(progressWrites == 0, "来源切换与试玩不写正式玩家进度")
end)
V.atFrame(75, function()
    PT.finish(); ME.dirty = false; Editor.hide()
    ME.saveToSandbox, ME.peekSandbox, World.snapshotExists, GS.saveGame = realSave, realPeek, realExists, realProgress
end)
