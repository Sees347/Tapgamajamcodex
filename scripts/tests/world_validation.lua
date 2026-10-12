-- 单世界迁移和连续区域验收：mock只读地图及玩家存档写入，不覆盖用户沙箱。
---@class WorldValidationHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V"), "仅供官方验证运行器使用") --[[@as WorldValidationHarness]]
local World = require "core.world_map"
local TM = require "core.tilemap"
local ME = require "core.map_editor"
local GS = require "core.state"
local L = require "core.level"
local P = require "core.player"
local E = require "core.enemies"
local HUD = require "ui.hud"
local UI = require "urhox-libs/UI"
local Menus = require "ui.menus"
local originalPeek, originalSave = ME.peekSandbox, GS.saveGame
local originalExists, originalMapWrite = World.snapshotExists, ME.saveToSandbox
local snapshots = {}
local originalLoad = assert(rawget(_G, "LoadLevel"))
local originalUpdate = P.update
---@type Scene?
local sameScene = nil
---@type Node?
local samePlayer = nil
local sameDef = {}
local reloadCount = 0

local function findText(widget, text)
    if widget.props and widget.props.text == text then return true end
    for _, child in ipairs(widget:GetChildren()) do if findText(child, text) then return true end end
    return false
end

V.atFrame(10, function()
    GS.saveGame = function() return true end
    -- 有效旧编辑快照：图片层、碰撞false、泉眼、电线、剧情及拾取序号。
    local legacy = {
        level = "editor_map", tile = 1, originX = 0, originY = 5, cols = 8, rows = 5,
        map = "        \n $ Tt   \n SPD    \n        \n########",
        visualLayers = { ground = { cells = { ["2:5"] = { tilesetId = "industrial_walls", tileId = 24, collider = "ground" } } },
            foreground = { cells = { ["3:4"] = { tilesetId = "industrial_pipes", tileId = 16, collider = "decoration" } } } },
        collisionCells = { ["2:5"] = false },
        metadata = { spawn = { x = 2, y = 2 }, story = { { id = "old", x = 1, y = 2, r = 1, text = "保留", once = true } },
            wires = { { from = "editor_map_2_2", to = "editor_map_3_2" } } },
        tilesets = require("core.tilesets").exportDefinitions(),
    }
    snapshots.editor_map = legacy
    ME.peekSandbox = function(id) return snapshots[id] end
    World.snapshotExists = function(id) return snapshots[id] ~= nil end
    ME.saveToSandbox = function() ME.dirty = false; return true end
    local src = World.source()
    V.assert(src.id == "world" and src.level == "world" and src.seamless, "旧编辑地图迁移为单一world身份")
    V.assert(src.cols == 8 and src.rows == 5 and src.originY == 5, "迁移保留用户真实尺寸与坐标，不扩成默认画布")
    V.assert(src.progressId == "editor_map", "保留旧进度命名空间")
    V.assert(src.visualLayers.ground.cells["2:5"].tileId == 24 and src.visualLayers.foreground.cells["3:4"].tileId == 16, "迁移保留真实图片层与切片编号")
    V.assert(src.collisionCells["2:5"] == false and #src.tilesets == 4, "迁移保留碰撞false与完整图集")
    V.assert(src.spawn.x == 2 and #src.story == 1 and #src.wires == 1, "迁移保留出生剧情电线元数据")
    V.assert(src.bounds.maxX == 8 and src.bounds.minY == 0 and src.deathY == -4, "世界边界按实际尺寸重算")
    V.assert(not src.map:find("T", 1, true) and legacy.map:find("T", 1, true), "清除运行出口但不改原始归档数据")
    local def = TM.parse(src)
    V.assert(#def.portals == 0 and #def.exits == 0 and def.arrival ~= nil, "world没有章节出口，保留t出生标记")
    V.assert(def.hazards[1].id == "editor_map_1_2", "泉眼ID兼容旧地图")
    src.visualLayers.ground.cells["2:5"].tileId = 1
    V.assert(legacy.visualLayers.ground.cells["2:5"].tileId == 24, "迁移使用独立深复制")
    local oldSave = GS.defaultSave()
    oldSave.level, oldSave.spring, oldSave.shells = "lab02", "lab02_s1", 73
    oldSave.fish, oldSave.equipped = { "frog", "eel" }, { "frog" }
    oldSave.flags.picked_editor_map_1 = true
    oldSave.flags.story_editor_map_old = true
    GS.migrateWorldSave(oldSave)
    V.assert(oldSave.level == "world" and oldSave.spring == "" and oldSave.legacyLevel == "lab02", "旧章节位置归档并回世界出生点")
    V.assert(oldSave.shells == 73 and #oldSave.fish == 2 and oldSave.equipped[1] == "frog", "迁移不清装备货币")
    oldSave.spring = "editor_map_1_2"
    GS.migrateWorldSave(oldSave)
    V.assert(oldSave.spring == "editor_map_1_2" and oldSave.legacyLevel == "lab02", "迁移幂等，不清有效世界泉眼")
    GS.save = oldSave
    originalLoad("world", oldSave.spring)
    V.assert(L.def.id == "world" and L.itemNodes[1].taken and L.storyZones[1].fired, "载入恢复旧拾取及剧情标记")
    V.assert(math.abs(P.node.position2D.x - 1.5) < 0.01, "旧编辑泉眼作为世界复活落点")
    originalLoad("testmap")
    originalLoad("world", GS.save.spring)
    V.assert(GS.save.spring == "editor_map_1_2" and math.abs(P.node.position2D.x - 1.5) < 0.01, "功能测试地图往返保留世界绑定泉眼")
    local savedWorld = { map = "t  \n###", tile = 2, originX = 10, originY = 6, progressId = "custom_world", metadata = { story = {}, wires = {}, spawn = { x = 11, y = 5 } } }
    snapshots.world = savedWorld
    local chosen = World.source()
    V.assert(chosen.cols == 3 and chosen.rows == 2 and chosen.tile == 2, "已有world优先且无尺寸旧快照不继承256×64")
    V.assert(chosen.progressId == "custom_world" and chosen.bounds.maxX == 16, "已有world进度及米制边界保留")
    local direct = TM.parse({ id = "world", map = "Tt\n##", seamless = true, exits = { { target = "lab01" } } })
    V.assert(#direct.portals == 0 and #direct.exits == 0 and direct.spawn.x == 1.5, "解析器也禁用T及显式跨图出口，t可默认出生")
    V.assert(TM.validDimensions(2048, 512) and not TM.validDimensions(2049, 512) and not TM.validDimensions(5, math.huge), "核心大图上限与非有限数校验")
    savedWorld.cols = 3000
    V.assert(not pcall(World.source), "超限world阻止载入，不静默覆盖用户内容")
    local oldDef = L.def
    originalLoad("world")
    V.assert(GS.mode == "menu" and L.def == oldDef, "坏世界存档回菜单而不是空玩家状态继续运行")
    assert(rawget(_G, "RespawnAtSpring"))()
    V.assert(GS.mode == "menu", "复活失败不会把安全菜单重新改成playing")
    snapshots.world, snapshots.editor_map = nil, nil
    GS.save = GS.defaultSave()
    originalLoad("world")
    V.assert(L.def.tilemapData.cols == 256 and L.def.tilemapData.rows == 64, "无用户快照时加载256×64默认世界")
    V.assert(not L.isSolid(59.5, -5.5) and L.isSolid(80, -6.5), "默认旧右墙开步行口且地板延续到新区域")
    sameScene, samePlayer, sameDef = L.scene, P.node, L.def
    -- 真实物理行走跨过原60格边界，测试仅注入水平输入，不传送或换图。
    P.node:SetPosition2D(58, -5.5)
    P.invuln = 30
    P.update = function(dt, state, fx)
        state.moveX = 1
        return originalUpdate(dt, state, fx)
    end
    _G.LoadLevel = function(...) reloadCount = reloadCount + 1; return originalLoad(...) end
end)

V.atFrame(100, function()
    P.update = originalUpdate
    V.assert(P.node.position2D.x > 60, "真实行走穿过旧右边界，进入延伸区域")
    V.assert(L.scene == sameScene and P.node == samePlayer and L.def == sameDef and reloadCount == 0, "跨原地图边界仍同一场景与角色，无区域LoadLevel")
    V.assert(GS.save.level == "world" and not P.dead, "跨边界后持续游玩world")
    V.assert(#E.list > 0, "原区域敌人数据没有被区域切换清空")
    V.assert(not findText(HUD.root, "编辑第一章") and not findText(HUD.root, "编辑第二章"), "游戏UI不含章节入口")
    Menus.showPause()
    V.assert(findText(HUD.root, "编辑无缝大地图"), "暂停可返回编辑同一世界")
    HUD.hideOverlay()
    GS.setMode("playing")
    assert(rawget(_G, "OpenMapEditor"))()
    V.assert(ME.currentLevel == "world" and ME.cols == 256 and ME.active, "编辑与游戏使用同一world数据")
    V.assert(findText(HUD.root, "无缝大地图（world）") and not findText(HUD.root, "新建"), "编辑器固定世界名称，无独立章节新建")
    ME.setLayer("gameplay")
    local snapshot = ME.captureData()
    ME.brush = "t"
    ME.applyBrush(5, 10, false)
    local sx, sy = ME.cellToWorld(5, 10)
    V.assert(ME.metadata.spawn.x == sx and math.abs(ME.metadata.spawn.y - sy - 0.4) < 0.001, "出生点笔刷同步世界spawn元数据")
    ME.applyBrush(7, 10, false)
    V.assert(ME.grid[10][5] == " " and ME.grid[10][7] == "t", "移动出生点不会留下多个标记")
    ME.loadSource(snapshot)
    local palette = HUD.root:FindById("editorCanvas")
    V.assert(palette ~= nil and UI.GetRoot() ~= nil, "编辑画布仍可用")
end)

V.atFrame(190, function()
    -- 不调用保存/退出按钮，测试不生成mapedit_world；结束前禁用自动保存。
    ME.dirty = false
    require("ui.map_editor").hide()
    ME.peekSandbox, GS.saveGame = originalPeek, originalSave
    World.snapshotExists, ME.saveToSandbox = originalExists, originalMapWrite
    P.update = originalUpdate
    _G.LoadLevel = originalLoad
end)
