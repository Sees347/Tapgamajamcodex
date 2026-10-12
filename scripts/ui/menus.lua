-- ============================================================================
-- ui/menus.lua - 菜单系统: 主菜单 / 暂停 / 死亡 / 装备切换 / 图鉴 / 剧情对话
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local FISH = require "data/fish"
local Art = require "core/art"
local Audio = require "core/audio"
local MON = require "data/monsters"
local D = require "data/items"
local HUD = require "ui/hud"
local UI = require "urhox-libs/UI"

-- 展示顺序（内联，避免数据表混入数组导致 LSP union 污染）
local FISH_ORDER = { "archerfish", "eel", "flyfish", "anglerfish", "ray", "barnacle", "frog", "swordfish" }
local RELIC_ORDER = { "waterPendant", "heatCrystal", "coldShell", "bulletShard", "vaporFilm" }

---@class Menus
local M = {}

M.onContinue = nil     -- 由 main 注入
M.onNewGame = nil
M.onTestMap = nil
M.onEditMap = nil
M.onRetry = nil
M.onQuitToMenu = nil
M.onEquipChanged = nil

local PAL = Config.PAL

-- ===================== 样式辅助 =====================

local function title(text, size)
    return UI.Label {
        text = text,
        fontSize = size or 30,
        fontColor = { 210, 235, 255, 255 },
    }
end

local function subtitle(text)
    return UI.Label {
        text = text,
        fontSize = 14,
        fontColor = { 140, 160, 195, 220 },
    }
end

local function btn(text, onClick, opts)
    opts = opts or {}
    return UI.Button {
        text = text,
        variant = opts.variant or "primary",
        width = opts.width or 220,
        fontSize = opts.fontSize or 15,
        onClick = function(self)
            GS.emit("sfx", "click")
            if onClick then onClick(self) end
        end,
    }
end

local function card(children, opts)
    opts = opts or {}
    return UI.Panel {
        width = opts.width or 420,
        padding = opts.padding or 28,
        gap = opts.gap or 12,
        backgroundColor = { 18, 24, 40, 240 },
        borderRadius = 16,
        borderWidth = 1,
        borderColor = { 70, 90, 140, 150 },
        alignItems = opts.alignItems or "center",
        children = children,
    }
end

local function audioControls()
    local music, effects = Audio.getVolumes()
    return UI.Panel {
        width = 220, gap = 4,
        children = {
            subtitle("背景音乐音量"),
            UI.Slider {
                width = "100%", min = 0, max = 1, step = 0.01, value = music,
                onChange = function(self, value)
                    local _, currentEffects = Audio.getVolumes()
                    Audio.setVolumes(value, currentEffects)
                end,
            },
            subtitle("音效音量"),
            UI.Slider {
                width = "100%", min = 0, max = 1, step = 0.01, value = effects,
                onChange = function(self, value)
                    local currentMusic = Audio.getVolumes()
                    Audio.setVolumes(currentMusic, value)
                end,
            },
        },
    }
end

-- ===================== 主菜单 =====================

function M.showMainMenu()
    local hasSave = GS.hasSaveFile()
    local children = {
        UI.Label {
            text = "涌 泉",
            fontSize = 52,
            fontColor = { 150, 215, 255, 255 },
        },
        UI.Label {
            text = "操控苏醒的水精灵，以水为生命，探索干旱破败的世界",
            fontSize = 13,
            fontColor = { 150, 170, 205, 220 },
        },
        UI.Panel { height = 16, children = {} },
    }
    if hasSave then
        table.insert(children, btn("继续游戏", function()
            HUD.hideOverlay()
            GS.setMode("playing")
            if M.onContinue then M.onContinue() end
        end, { variant = "primary" }))
        table.insert(children, btn("新的旅程", function()
            GS.newGame()
            HUD.hideOverlay()
            GS.setMode("playing")
            if M.onNewGame then M.onNewGame() end
        end, { variant = "secondary" }))
    else
        table.insert(children, btn("开始游戏", function()
            GS.newGame()
            HUD.hideOverlay()
            GS.setMode("playing")
            if M.onNewGame then M.onNewGame() end
        end, { variant = "primary" }))
    end
    table.insert(children, btn("功能测试地图", function()
        print("[Menus] 点击：功能测试地图")
        if not GS.save then GS.newGame() end
        HUD.hideOverlay()
        GS.setMode("playing")
        if M.onTestMap then M.onTestMap() else print("[Menus] !! onTestMap 未绑定") end
    end, { variant = "secondary" }))
    table.insert(children, btn("编辑无缝大地图", function()
        if not GS.save then GS.newGame() end
        HUD.hideOverlay()
        GS.setMode("playing")
        if M.onEditMap then M.onEditMap() end
    end, { variant = "secondary" }))
    table.insert(children, UI.Panel { height = 8, children = {} })
    table.insert(children, audioControls())
    table.insert(children, subtitle("A/D 移动 · 空格跳跃 · 按住左键射击 · E 交互/冰态电鳗技能 · TAB 装备 · ESC 暂停"))

    HUD.showOverlay({
        card(children, { width = 480 }),
    }, { dimColor = { 6, 8, 16, 245 } })
    GS.setMode("menu")
end

-- ===================== 暂停菜单 =====================

function M.showPause()
    if GS.mode ~= "playing" and GS.mode ~= "paused" then return end
    GS.setMode("paused")
    HUD.showOverlay({
        card({
            title("已暂停", 26),
            audioControls(),
            UI.Panel { height = 8, children = {} },
            btn("继续游戏", function()
                HUD.hideOverlay()
                GS.setMode("playing")
            end),
            btn("装备与图鉴", function()
                M.showInventory()
            end, { variant = "secondary" }),
            btn("调参面板", function()
                local TuningUI = require "ui/tuning"
                TuningUI.show(function()
                    M.showPause()   -- 关闭后回到暂停菜单
                end)
            end, { variant = "secondary" }),
            btn("功能测试地图", function()
                HUD.hideOverlay()
                GS.setMode("playing")
                if M.onTestMap then M.onTestMap() end
            end, { variant = "secondary" }),
            btn("编辑无缝大地图", function()
                if not GS.save then GS.newGame() end
                HUD.hideOverlay()
                GS.setMode("playing")
                if M.onEditMap then M.onEditMap() end
            end, { variant = "secondary" }),
            btn("保存并回主菜单", function()
                GS.saveGame()
                HUD.hideOverlay()
                if M.onQuitToMenu then M.onQuitToMenu() end
            end, { variant = "secondary" }),
        }),
    })
end

function M.resumeFromPause()
    if GS.mode == "paused" then
        HUD.hideOverlay()
        GS.setMode("playing")
    end
end

-- ===================== 死亡界面 =====================

function M.showDeath()
    HUD.showOverlay({
        card({
            UI.Label {
                text = "水量耗尽……",
                fontSize = 28,
                fontColor = { 255, 140, 120, 255 },
            },
            subtitle("水精灵在最近的泉眼处重新凝聚"),
            UI.Panel { height = 10, children = {} },
            btn("在泉眼苏醒", function()
                HUD.hideOverlay()
                if M.onRetry then M.onRetry() end
            end),
            btn("回主菜单", function()
                GS.saveGame()
                HUD.hideOverlay()
                if M.onQuitToMenu then M.onQuitToMenu() end
            end, { variant = "secondary" }),
        }),
    }, { dimColor = { 30, 8, 8, 210 } })
end

-- ===================== 装备与图鉴 =====================

---@param returnToGame boolean|nil 保留装备列表刷新前的返回位置
function M.showInventory(returnToGame)
    local wasPlaying = returnToGame
    if wasPlaying == nil then wasPlaying = GS.mode == "playing" end
    if GS.mode == "playing" then GS.setMode("paused") end

    local fishRows = {}
    for _, key in ipairs(FISH_ORDER) do
        local def = FISH[key]
        local owned = GS.hasFish(key)
        local equippedSet = {}
        for _, ek in ipairs(GS.save.equipped) do equippedSet[ek] = true end
        local isEquipped = equippedSet[key] == true

        local descText = owned and def.desc or "？？？（尚未遇见）"
        local icon = owned and Art.fishIcon(key)
        local iconContent = icon and UI.Panel {
            width = 30, height = 30,
            backgroundImage = icon,
            backgroundFit = "contain",
        } or UI.Label {
            text = owned and string.sub(def.name, 1, 3) or "?",
            fontSize = 10,
            fontColor = { 255, 255, 255, 240 },
        }
        table.insert(fishRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            padding = 8,
            borderRadius = 8,
            backgroundColor = isEquipped and { 40, 70, 110, 200 } or { 28, 34, 52, 160 },
            borderWidth = 1,
            borderColor = isEquipped and { 120, 190, 255, 200 } or { 60, 70, 100, 120 },
            children = {
                -- 鱼图标
                UI.Panel {
                    width = 36, height = 36, borderRadius = 18,
                    backgroundColor = owned
                        and { def.color[1], def.color[2], def.color[3], 220 }
                        or { 60, 66, 84, 160 },
                    justifyContent = "center", alignItems = "center",
                    children = { iconContent },
                },
                -- 名称 + 描述
                UI.Panel {
                    flex = 1, flexShrink = 1, gap = 2,
                    children = {
                        UI.Label {
                            text = owned and def.name or "未知生物",
                            fontSize = 14,
                            fontColor = owned and { 230, 240, 255, 255 } or { 120, 130, 155, 200 },
                        },
                        UI.Label {
                            text = descText,
                            fontSize = 10,
                            fontColor = { 160, 175, 205, 200 },
                        },
                    },
                },
                -- 装备按钮
                owned and UI.Button {
                    text = isEquipped and "卸下" or "装备",
                    fontSize = 12,
                    variant = isEquipped and "secondary" or "primary",
                    width = 62,
                    onClick = (function(k)
                        return function()
                            GS.emit("sfx", "click")
                            GS.equipFish(k)
                            HUD.refreshFish()
                            if M.onEquipChanged then M.onEquipChanged() end
                            M.showInventory(wasPlaying) -- 刷新界面时保留关闭后的返回目标
                        end
                    end)(key),
                } or UI.Label { text = "", fontSize = 12 },
            },
        })
    end

    -- 饰品行
    local relicRows = {}
    for _, key in ipairs(RELIC_ORDER) do
        local def = D.RELICS[key]
        local owned = GS.hasRelic(key)
        table.insert(relicRows, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
            padding = 5, borderRadius = 6,
            backgroundColor = { 28, 34, 52, 120 },
            children = {
                UI.Panel {
                    width = 10, height = 10, borderRadius = 5,
                    backgroundColor = owned and { def.color[1], def.color[2], def.color[3], 255 }
                        or { 70, 76, 95, 200 },
                },
                UI.Label {
                    text = owned and (def.name .. " — " .. def.desc) or (def.name .. "（未发现 · " .. def.source .. "）"),
                    fontSize = 10, flexShrink = 1,
                    fontColor = owned and { 210, 225, 245, 230 } or { 110, 120, 145, 180 },
                },
            },
        })
    end

    HUD.showOverlay({
        UI.Panel {
            width = 640, maxWidth = "92%", maxHeight = "86%",
            padding = 22, gap = 10,
            backgroundColor = { 16, 21, 36, 245 },
            borderRadius = 14,
            borderWidth = 1,
            borderColor = { 70, 90, 140, 150 },
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = ("共生装备（槽位 %d/%d）"):format(#GS.save.equipped, GS.slotCount()),
                            fontSize = 18, fontColor = { 210, 235, 255, 255 },
                        },
                        UI.Label {
                            text = ("贝壳 %d · 碎片 %d/3 · 泉心 %d"):format(
                                GS.save.shells, GS.save.fragments, GS.save.quanxin),
                            fontSize = 12, fontColor = { 240, 215, 150, 220 },
                        },
                    },
                },
                UI.ScrollView {
                    width = "100%", flex = 1, flexShrink = 1,
                    children = {
                        UI.Panel { width = "100%", gap = 6, children = fishRows },
                        UI.Panel { height = 10, children = {} },
                        UI.Label {
                            text = "饰品收藏", fontSize = 15,
                            fontColor = { 200, 215, 240, 240 },
                        },
                        UI.Panel { width = "100%", gap = 4, children = relicRows },
                    },
                },
                btn("关闭", function()
                    HUD.hideOverlay()
                    if wasPlaying then
                        GS.setMode("playing")
                    else
                        M.showPause()
                    end
                end, { variant = "secondary", width = 140 }),
            },
        },
    })
end

-- ===================== 剧情对话（cutscene 模式） =====================

function M.showCutscene(text, onFinish)
    GS.setMode("dialog")
    HUD.showOverlay({
        card({
            UI.Label {
                text = text,
                fontSize = 16,
                fontColor = { 225, 235, 250, 255 },
                textAlign = "center",
            },
            UI.Panel { height = 8, children = {} },
            btn("继续", function()
                HUD.hideOverlay()
                GS.setMode("playing")
                if onFinish then onFinish() end
            end, { width = 140 }),
        }, { width = 520 }),
    }, { dimColor = { 5, 7, 14, 225 } })
end

return M
