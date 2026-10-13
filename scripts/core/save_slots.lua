-- ============================================================================
-- core/save_slots.lua - 多存档槽管理（存档界面数据层）
-- 索引 saves/index.json：{ version, importedLegacy, nextId, slots=[{id,name,created}] }
-- 槽文件 saves/slot_<id>.json：完整 SaveData。读取失败不覆盖，写入失败显式返回 false。
-- ============================================================================
local SaveSlots = {}

local DIR = "saves"
local INDEX = DIR .. "/index.json"
local LEGACY = "yongquan_save.json"

---@class SaveSlotMeta
---@field id integer
---@field name string
---@field created string

---@param name string
---@return string 去掉路径与越界字符后的单行名称
local function sanitize(name)
    local s = tostring(name or ""):gsub("[\r\n/\\]", "")
    if #s > 40 then s = s:sub(1, 40) end
    if s == "" then s = "新存档" end
    return s
end

local function readJson(path)
    if not fileSystem:FileExists(path) then return nil end
    ---@type File?
    local f = File(path, FILE_READ)
    if not f or not f:IsOpen() then return nil end
    local content = f:ReadString()
    f:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

---@param path string
---@param data table
---@return boolean
local function writeJson(path, data)
    local encoded, content = pcall(cjson.encode, data)
    if not encoded then print("[存档槽] 编码失败：" .. tostring(content)) return false end
    ---@type File?
    local f = nil
    local ok, written = pcall(function()
        f = File(path, FILE_WRITE)
        if not f or not f:IsOpen() then return false end
        local success = f:WriteString(content)
        if success then f:Flush() end
        return success == true
    end)
    if f then pcall(function() f:Dispose() end) end
    if not ok or not written then print("[存档槽] 写入失败：" .. path) return false end
    return true
end

---@return table 至少含 slots 数组的有效索引；损坏时返回内存空表（不落盘覆盖）
local function loadIndex()
    local data = readJson(INDEX)
    if type(data) ~= "table" or type(data.slots) ~= "table" then
        return { version = 1, importedLegacy = false, nextId = 1, slots = {} }
    end
    data.nextId = tonumber(data.nextId) or 1
    return data
end

--- 首次使用时导入旧单档 yongquan_save.json；保留原文件不删除。
---@return boolean changed
local function importLegacy(index)
    if index.importedLegacy or not fileSystem:FileExists(LEGACY) then return false end
    local legacy = readJson(LEGACY)
    index.importedLegacy = true
    if type(legacy) ~= "table" or type(legacy.map) == "string" then return true end
    local id = index.nextId
    local meta = { id = id, name = os.date("旧存档_%Y-%m-%d.txt"), created = os.date("%Y-%m-%d %H:%M") }
    index.slots[#index.slots + 1] = meta
    index.nextId = id + 1
    if writeJson(DIR .. "/slot_" .. id .. ".json", legacy) then
        print("[存档槽] 旧单档已导入为槽 " .. id .. "（原文件保留）")
    else
        table.remove(index.slots)
        index.nextId = id
    end
    return true
end

--- 列出全部槽（按创建顺序）。
---@return SaveSlotMeta[]
function SaveSlots.list()
    local index = loadIndex()
    if importLegacy(index) then
        fileSystem:CreateDir(DIR)
        writeJson(INDEX, index)
    end
    local result = {}
    for _, meta in ipairs(index.slots) do
        if type(meta) == "table" and tonumber(meta.id) then
            result[#result + 1] = { id = math.floor(meta.id), name = sanitize(meta.name), created = tostring(meta.created or "") }
        end
    end
    return result
end

--- 新建槽；data 可为 nil（空槽），返回 meta 或 nil,错误。
---@param name string
---@param data? table
---@return SaveSlotMeta|nil
---@return string|nil
function SaveSlots.create(name, data)
    fileSystem:CreateDir(DIR)
    local index = loadIndex()
    importLegacy(index)
    local id = index.nextId
    local meta = { id = id, name = sanitize(name), created = os.date("%Y-%m-%d %H:%M") }
    if data ~= nil and not writeJson(DIR .. "/slot_" .. id .. ".json", data) then
        return nil, "存档写入失败"
    end
    index.slots[#index.slots + 1] = meta
    index.nextId = id + 1
    if not writeJson(INDEX, index) then
        if data ~= nil then pcall(function() fileSystem:Delete(DIR .. "/slot_" .. id .. ".json") end) end
        return nil, "存档索引写入失败"
    end
    print("[存档槽] 新建槽 " .. id .. "：" .. meta.name)
    return meta, nil
end

--- 覆盖写入既有槽。
---@param id integer
---@param data table
---@return boolean
function SaveSlots.write(id, data)
    fileSystem:CreateDir(DIR)
    return writeJson(DIR .. "/slot_" .. id .. ".json", data)
end

--- 读取槽数据；空槽/坏档返回 nil（不写任何文件）。
---@param id integer
---@return table|nil
function SaveSlots.read(id)
    local data = readJson(DIR .. "/slot_" .. math.floor(tonumber(id) or 0) .. ".json")
    if type(data) ~= "table" then return nil end
    return data
end

--- 删除槽与索引项；文件不存在也算成功。
---@param id integer
---@return boolean
function SaveSlots.remove(id)
    local index = loadIndex()
    local kept = {}
    for _, meta in ipairs(index.slots) do
        if math.floor(tonumber(meta.id) or 0) ~= math.floor(tonumber(id) or 0) then kept[#kept + 1] = meta end
    end
    index.slots = kept
    local removed = not fileSystem:FileExists(DIR .. "/slot_" .. math.floor(tonumber(id) or 0) .. ".json")
        or fileSystem:Delete(DIR .. "/slot_" .. math.floor(tonumber(id) or 0) .. ".json")
    if not removed then return false end
    if not writeJson(INDEX, index) then return false end
    print("[存档槽] 已删除槽 " .. tostring(id))
    return true
end

---@param id integer
---@return SaveSlotMeta|nil
function SaveSlots.get(id)
    for _, meta in ipairs(SaveSlots.list()) do if meta.id == id then return meta end end
    return nil
end

---@return boolean
function SaveSlots.hasAny()
    return #SaveSlots.list() > 0
end

--- 最近创建的非空槽 id（主菜单继续游戏用）。
---@return integer|nil
function SaveSlots.latestFilled()
    local slots = SaveSlots.list()
    for i = #slots, 1, -1 do
        if SaveSlots.read(slots[i].id) then return slots[i].id end
    end
    return nil
end

return SaveSlots
