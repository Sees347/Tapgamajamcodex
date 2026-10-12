-- ============================================================================
-- core/state.lua - 全局游戏状态 + 存档 + 事件总线
-- ============================================================================

local Config = require "config"

---@class SaveData
---@field version integer
---@field water number            当前水量
---@field quanxin integer         泉心数量
---@field shells integer          贝壳
---@field fragments integer       共生碎片（3 合成 1 核心）
---@field cores integer           共生核心
---@field pieces integer          破碎泉心（3 合成 1 泉心）
---@field fish string[]           拥有的鱼
---@field equipped string[]       装备中的鱼
---@field relics string[]         拥有的饰品
---@field level string            所在地图
---@field legacyLevel? string      迁移前地图，仅归档
---@field legacySpring? string     迁移前泉眼，仅归档
---@field returnWorldSpring? string 开发测试前的世界泉眼
---@field spring string           绑定的泉眼 id
---@field flags table<string, boolean>
---@field visited table<string, boolean>

---@class GameState
local GS = {}

GS.SAVE_FILE = "yongquan_save.json"

-- 运行模式: menu / playing / paused / dead / dialog / victory / mapTransition
---@type string
GS.mode = "menu"
---@type string|nil
GS.pendingMode = nil

---@type SaveData
GS.save = nil

-- 场景光源列表（趋光菌兽寻光用）：{ {x=,y=}, ... }，由 main 每帧维护
---@type table[]
GS.lightSources = {}

-- 事件总线
local listeners = {}

--- 订阅事件
---@param evt string
---@param fn function
function GS.on(evt, fn)
    if not listeners[evt] then listeners[evt] = {} end
    table.insert(listeners[evt], fn)
end

--- 触发事件
function GS.emit(evt, ...)
    local fns = listeners[evt]
    if fns then
        for i = 1, #fns do fns[i](...) end
    end
end

function GS.clearListeners()
    listeners = {}
end

-- ===================== 派生数值 =====================

--- 当前水量上限
---@return number
function GS.maxWater()
    return Config.PLAYER.maxWaterBase + (GS.save.quanxin or 0) * Config.HEART_PER_QQUANXIN
end

--- 共生槽数量（初始 1 + 核心数）
---@return integer
function GS.slotCount()
    return 1 + (GS.save.cores or 0)
end

--- 是否拥有饰品
---@param key string
---@return boolean
function GS.hasRelic(key)
    for _, k in ipairs(GS.save.relics) do
        if k == key then return true end
    end
    return false
end

--- 是否拥有某条鱼
---@param key string
---@return boolean
function GS.hasFish(key)
    for _, k in ipairs(GS.save.fish) do
        if k == key then return true end
    end
    return false
end

-- ===================== 收集操作 =====================

function GS.addWater(amount)
    local s = GS.save
    s.water = math.min(GS.maxWater(), s.water + amount)
    GS.emit("waterChanged", s.water, GS.maxWater())
end

function GS.addShells(n)
    GS.save.shells = GS.save.shells + n
    GS.emit("shellsChanged", GS.save.shells)
end

--- 获得共生碎片，自动合成核心
function GS.addFragment()
    local s = GS.save
    s.fragments = s.fragments + 1
    GS.emit("itemGet", "共生碎片")
    if s.fragments >= Config.FRAGMENT_PER_CORE then
        s.fragments = s.fragments - Config.FRAGMENT_PER_CORE
        s.cores = s.cores + 1
        GS.emit("itemGet", "共生核心！共生槽 +1")
        GS.emit("slotsChanged", GS.slotCount())
        GS.autoEquip()
    end
end

--- 获得破碎泉心，自动合成泉心
function GS.addPiece()
    local s = GS.save
    s.pieces = s.pieces + 1
    GS.emit("itemGet", "破碎泉心")
    if s.pieces >= Config.PIECE_PER_QUANXIN then
        s.pieces = s.pieces - Config.PIECE_PER_QUANXIN
        s.quanxin = s.quanxin + 1
        GS.emit("itemGet", "泉心！水量上限 +2")
        GS.emit("maxWaterChanged", GS.maxWater())
    end
end

--- 获得鱼（若槽位有空自动装备）
---@param key string
function GS.addFish(key)
    if GS.hasFish(key) then
        GS.addShells(Config.ECONOMY.dupeFishShells) -- 重复转化贝壳
        GS.emit("itemGet", "重复的水生生物 → 贝壳 x" .. Config.ECONOMY.dupeFishShells)
        return
    end
    table.insert(GS.save.fish, key)
    GS.autoEquip()
    local FISH = require "data/fish"
    local def = FISH[key]
    GS.emit("itemGet", (def and def.name or key) .. " 加入了共生！")
    GS.emit("fishChanged")
end

--- 获得饰品
---@param key string
function GS.addRelic(key)
    if GS.hasRelic(key) then return end
    table.insert(GS.save.relics, key)
    local D = require "data/items"
    local def = D.RELICS[key]
    GS.emit("itemGet", "获得饰品：" .. (def and def.name or key))
    GS.emit("relicsChanged")
end

--- 自动装备：按拥有顺序装备前 slotCount 条鱼
function GS.autoEquip()
    local s = GS.save
    local slots = GS.slotCount()
    s.equipped = {}
    for i = 1, math.min(slots, #s.fish) do
        table.insert(s.equipped, s.fish[i])
    end
    GS.emit("fishChanged")
end

--- 手动交换装备（菜单中）：把 ownedIdx 的鱼装上
---@param fishKey string
function GS.equipFish(fishKey)
    local s = GS.save
    if not GS.hasFish(fishKey) then return end
    -- 已装备则取消
    for i, k in ipairs(s.equipped) do
        if k == fishKey then
            table.remove(s.equipped, i)
            GS.emit("fishChanged")
            return
        end
    end
    if #s.equipped >= GS.slotCount() then
        -- 替换第一个
        s.equipped[1] = fishKey
    else
        table.insert(s.equipped, fishKey)
    end
    GS.emit("fishChanged")
end

function GS.setFlag(flag)
    GS.save.flags[flag] = true
    GS.emit("flagSet", flag)
end

function GS.hasFlag(flag)
    return GS.save.flags[flag] == true
end

-- ===================== 存档 =====================

function GS.defaultSave()
    return {
        version = 2,
        water = Config.PLAYER.initWater,
        quanxin = 0,
        shells = 0,
        fragments = 0,
        cores = 0,
        pieces = 0,
        fish = {},
        equipped = {},
        relics = {},
        level = "world",
        spring = "",
        flags = {},
        visited = {},
    }
end

--- 在有效世界载入后迁移玩家位置；装备、货币、flags 和访问记录原样保留。
--- 不写盘，不覆盖旧档；重复调用不会清除已绑定的世界泉眼。
---@param data table
function GS.migrateWorldSave(data)
    if data.level ~= "world" then
        data.legacyLevel = data.legacyLevel or data.level
        data.legacySpring = data.legacySpring or data.spring
        if data.level == "testmap" then
            data.spring = data.returnWorldSpring or ""
            data.returnWorldSpring = nil
        elseif data.level ~= "editor_map" then
            data.spring = ""
        end
        data.level = "world"
        print("[Save] 旧地图位置迁移到同一世界，收集与装备进度保留")
    end
    data.version = math.max(data.version or 1, 2)
end

function GS.newGame()
    GS.save = GS.defaultSave()
    GS.saveGame()
end

function GS.hasSaveFile()
    return fileSystem:FileExists(GS.SAVE_FILE)
end

function GS.loadGame()
    if not fileSystem:FileExists(GS.SAVE_FILE) then return false end
    ---@type File?
    local f = File(GS.SAVE_FILE, FILE_READ)
    if not f or not f:IsOpen() then return false end
    local content = f:ReadString()
    f:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then
        print("[Save] 解析失败，使用新存档")
        return false
    end
    -- 补齐字段（向前兼容）
    local def = GS.defaultSave()
    for k, v in pairs(def) do
        if data[k] == nil then data[k] = v end
    end
    GS.save = data
    print("[Save] 读取成功: 关卡=" .. tostring(data.level) .. " 水量=" .. tostring(data.water))
    return true
end

function GS.saveGame()
    if not GS.save then return end
    ---@type File?
    local f = File(GS.SAVE_FILE, FILE_WRITE)
    if not f or not f:IsOpen() then
        print("[Save] 写入失败")
        return
    end
    f:WriteString(cjson.encode(GS.save))
    f:Close()
    print("[Save] 已保存")
end

function GS.deleteSave()
    GS.save = GS.defaultSave()
    GS.saveGame()
end

-- ===================== 模式切换 =====================

---@param mode string
function GS.setMode(mode)
    GS.mode = mode
    GS.emit("modeChanged", mode)
end

return GS
