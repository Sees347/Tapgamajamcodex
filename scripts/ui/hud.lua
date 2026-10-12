-- ============================================================================
-- ui/hud.lua - HUD 与菜单 (P0-9 状态显示 / P1-13 菜单 / 对话 / 死亡 / 暂停)
-- 使用 urhox-libs/UI (Yoga Flexbox + NanoVG)
-- ============================================================================

local Config = require "config"
local GS = require "core/state"
local FISH = require "data/fish"
local Art = require "core/art"
local UI = require "urhox-libs/UI"

---@class HUD
local HUD = {}

HUD.root = nil
HUD.gameHudLayer = nil
HUD.visible = false

local toastQueue = {}
local toastTimer = 0
local toastLabel = nil
local notePanel = nil
local noteLabel = nil
local dialogQueue = {}

-- ===================== 初始化 =====================

function HUD.init()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

-- ===================== 游戏 HUD =====================

local function buildWaterBar()
    local drops = {}
    for i = 1, 16 do
        drops[i] = UI.Panel {
            id = "drop" .. i,
            width = 16, height = 22,
            marginRight = 2,
            borderRadius = 8,
            backgroundColor = { 60, 140, 220, 255 },
            borderWidth = 1,
            borderColor = { 160, 220, 255, 180 },
        }
    end
    return UI.Panel {
        id = "waterBar",
        flexDirection = "row",
        alignItems = "center",
        children = drops,
    }
end

function HUD.buildGameUI()
    -- gameHudLayer: 游戏内 HUD（水量/形态/贝壳/提示），主菜单时隐藏
    local gameHudLayer = UI.Panel {
        id = "gameHudLayer",
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 左上: 水量 + 形态 + 装备鱼
            UI.Panel {
                id = "hudTopLeft",
                position = "absolute",
                top = 12, left = 12,
                gap = 6,
                pointerEvents = "none",
                children = {
                    buildWaterBar(),
                    UI.Label {
                        id = "waterText",
                        text = "3 / 12",
                        fontSize = 13,
                        fontColor = { 200, 230, 255, 230 },
                    },
                    UI.Label {
                        id = "formLabel",
                        text = "液态",
                        fontSize = 15,
                        fontColor = { 255, 255, 255, 240 },
                    },
                    UI.Panel {
                        id = "fishRow",
                        flexDirection = "row",
                        gap = 6,
                        children = {},
                    },
                },
            },
            -- 右上: 贝壳 + 碎片进度
            UI.Panel {
                id = "hudTopRight",
                position = "absolute",
                top = 12, right = 12,
                alignItems = "flex-end",
                gap = 4,
                pointerEvents = "none",
                children = {
                    UI.Label {
                        id = "shellLabel",
                        text = "贝壳 x 0",
                        fontSize = 15,
                        fontColor = { 250, 220, 160, 240 },
                    },
                    UI.Label {
                        id = "fragLabel",
                        text = "",
                        fontSize = 12,
                        fontColor = { 150, 240, 200, 200 },
                    },
                    UI.Label {
                        id = "pieceLabel",
                        text = "",
                        fontSize = 12,
                        fontColor = { 200, 190, 255, 200 },
                    },
                },
            },
            -- 中央 toast
            UI.Label {
                id = "toastLabel",
                position = "absolute",
                top = "18%", left = 0, right = 0,
                textAlign = "center",
                text = "",
                fontSize = 17,
                fontColor = { 255, 255, 255, 240 },
                pointerEvents = "none",
            },
            -- 纸条/记录面板
            UI.Panel {
                id = "notePanel",
                visible = false,
                position = "absolute",
                top = "26%", left = 0, right = 0,
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Panel {
                        maxWidth = 480, width = "80%",
                        padding = 16,
                        backgroundColor = { 35, 32, 26, 235 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { 120, 105, 70, 200 },
                        children = {
                            UI.Label {
                                id = "noteLabel",
                                text = "",
                                fontSize = 16,
                                fontColor = { 235, 225, 195, 255 },
                                textAlign = "center",
                            },
                        },
                    },
                },
            },
            -- 底部提示
            UI.Label {
                id = "hintLabel",
                position = "absolute",
                bottom = 10, left = 0, right = 0,
                textAlign = "center",
                text = "",
                fontSize = 12,
                fontColor = { 180, 195, 220, 160 },
                pointerEvents = "none",
            },
        },
    }

    -- root 始终存在（主菜单也用它承载 overlay）
    HUD.root = UI.Panel {
        id = "gameRoot",
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = { gameHudLayer },
    }
    UI.SetRoot(HUD.root)
    HUD.gameHudLayer = HUD.root:FindById("gameHudLayer")
    toastLabel = HUD.root:FindById("toastLabel") --[[@as Label?]]
    notePanel = HUD.root:FindById("notePanel")
    noteLabel = HUD.root:FindById("noteLabel") --[[@as Label?]]
    HUD.visible = true
end

--- 显示/隐藏游戏内 HUD（主菜单隐藏，进关卡显示）
---@param v boolean
function HUD.setGameHudVisible(v)
    if HUD.gameHudLayer then HUD.gameHudLayer:SetVisible(v) end
end

-- ===================== HUD 刷新 =====================

function HUD.refreshWater()
    if not HUD.root then return end
    local water = GS.save.water
    local maxW = GS.maxWater()
    local fullDrops = math.floor(water)
    local halfDrop = (water - fullDrops) >= 0.5

    for i = 1, 16 do
        local drop = HUD.root:FindById("drop" .. i)
        if drop then
            if i <= maxW then
                drop:SetVisible(true)
                if i <= fullDrops then
                    drop:SetStyle({ backgroundColor = { 60, 150, 235, 255 } })
                elseif i == fullDrops + 1 and halfDrop then
                    drop:SetStyle({ backgroundColor = { 60, 150, 235, 130 } })
                else
                    drop:SetStyle({ backgroundColor = Config.PAL.hpEmpty })
                end
            else
                drop:SetVisible(false)
            end
        end
    end
    local wt = HUD.root:FindById("waterText") --[[@as Label?]]
    if wt then wt:SetText(string.format("%.1f / %d", water, maxW)) end
end

function HUD.refreshForm(formName, formKey)
    if not HUD.root then return end
    local label = HUD.root:FindById("formLabel") --[[@as Label?]]
    if label then
        local icon = formKey == "gas" and "☁ 气态" or (formKey == "solid" and "❄ 固态" or "💧 液态")
        label:SetText(icon)
        local col = Config.FORMS[formKey or "liquid"].color
        label:SetStyle({ fontColor = { col[1], col[2], col[3], 255 } })
    end
end

function HUD.refreshFish()
    if not HUD.root then return end
    local row = HUD.root:FindById("fishRow")
    if not row then return end
    -- 重建装备槽显示
    local children = {}
    local slots = GS.slotCount()
    for i = 1, slots do
        local key = GS.save.equipped[i]
        local def = key and FISH[key]
        local icon = key and Art.fishIcon(key)
        local content = icon and UI.Panel {
            width = 28, height = 28,
            backgroundImage = icon,
            backgroundFit = "contain",
        } or UI.Label {
            text = def and string.sub(def.name, 1, 3) or "空",
            fontSize = def and 11 or 10,
            fontColor = { 255, 255, 255, def and 250 or 120 },
        }
        children[i] = UI.Panel {
            width = 34, height = 34,
            borderRadius = 17,
            backgroundColor = def and { def.color[1], def.color[2], def.color[3], 200 }
                or { 50, 58, 76, 160 },
            borderWidth = def and 2 or 1,
            borderColor = def and { 255, 255, 255, 160 } or { 90, 100, 130, 140 },
            justifyContent = "center",
            alignItems = "center",
            children = { content },
        }
    end
    row:ClearChildren()
    for _, child in ipairs(children) do
        row:AddChild(child)
    end
end

function HUD.refreshCurrency()
    if not HUD.root then return end
    local sl = HUD.root:FindById("shellLabel") --[[@as Label?]]
    if sl then sl:SetText("贝壳 x " .. GS.save.shells) end
    local fl = HUD.root:FindById("fragLabel") --[[@as Label?]]
    if fl then
        local txt = ""
        if GS.save.fragments > 0 then txt = txt .. ("共生碎片 %d/3"):format(GS.save.fragments) end
        if GS.save.cores > 0 then txt = txt .. ("  核心 x%d"):format(GS.save.cores) end
        fl:SetText(txt)
    end
    local pl = HUD.root:FindById("pieceLabel") --[[@as Label?]]
    if pl then
        local txt = ""
        if GS.save.pieces > 0 then txt = txt .. ("破碎泉心 %d/3"):format(GS.save.pieces) end
        if GS.save.quanxin > 0 then txt = txt .. ("  泉心 x%d"):format(GS.save.quanxin) end
        pl:SetText(txt)
    end
end

function HUD.refreshAll()
    HUD.refreshWater()
    HUD.refreshForm(nil, nil)
    HUD.refreshFish()
    HUD.refreshCurrency()
end

function HUD.setHint(text)
    if not HUD.root then return end
    local hl = HUD.root:FindById("hintLabel") --[[@as Label?]]
    if hl then hl:SetText(text or "") end
end

-- ===================== Toast =====================

function HUD.toast(text, duration)
    toastQueue[#toastQueue + 1] = { text = text, dur = duration or 2.2 }
end

function HUD.update(dt)
    -- toast 队列
    if toastTimer > 0 then
        toastTimer = toastTimer - dt
        if toastTimer <= 0 and toastLabel then
            toastLabel:SetText("")
        end
    elseif #toastQueue > 0 then
        local t = table.remove(toastQueue, 1)
        if toastLabel then toastLabel:SetText(t.text) end
        toastTimer = t.dur
    end
end

-- ===================== 纸条/对话 =====================

local noteTimer = 0

function HUD.showNote(text, duration)
    if notePanel and noteLabel then
        noteLabel:SetText(text)
        notePanel:SetVisible(true)
        noteTimer = duration or 3.5
    end
end

function HUD.updateNote(dt)
    if noteTimer > 0 then
        noteTimer = noteTimer - dt
        if noteTimer <= 0 and notePanel then
            notePanel:SetVisible(false)
        end
    end
end

function HUD.hideNote()
    if notePanel then notePanel:SetVisible(false) end
    noteTimer = 0
end

-- ===================== 覆盖层菜单 =====================

local overlayRoot = nil

function HUD.hideOverlay()
    if overlayRoot then
        overlayRoot:SetVisible(false)
    end
end

function HUD.showOverlay(children, opts)
    opts = opts or {}
    if overlayRoot then
        overlayRoot:Remove()
        overlayRoot = nil
    end
    overlayRoot = UI.Panel {
        id = "overlay",
        width = "100%", height = "100%",
        position = "absolute",
        top = 0, left = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = opts.dimColor or { 8, 10, 18, 200 },
        -- box-none：overlay 自身不拦截鼠标（子控件仍可点击），
        -- 供地图编辑器这类"要点到画面网格"的场景使用。
        pointerEvents = opts.pointerEvents or "auto",
        children = children,
    }
    if HUD.root then
        HUD.root:AddChild(overlayRoot)
    end
    return overlayRoot
end

return HUD
