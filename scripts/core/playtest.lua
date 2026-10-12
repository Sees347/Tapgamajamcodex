-- 编辑试玩只克隆玩家进度，清试玩收集标记；结束后恢复原对象和写盘函数。
local GS = require "core.state"
local PT = { active = false }
---@type table?
PT.worldSource = nil
---@type SaveData?
local originalSave = nil
---@type function?
local originalWriter = nil

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

---@param source? table 当前编辑地图的独立快照，试玩复活不得重新读取共享/旧草稿
function PT.begin(source)
    PT.finish()
    PT.worldSource = source and require("core.world_map").prepare(source) or nil
    originalSave, originalWriter = GS.save, GS.saveGame
    local saved = GS.save or GS.defaultSave()
    local test = copy(saved)
    test.flags, test.visited, test.spring = {}, {}, ""
    test.water = (require("config").PLAYER.maxWaterBase) + (test.quanxin or 0) * require("config").HEART_PER_QQUANXIN
    GS.save = test
    GS.saveGame = function() print("[编辑试玩] 临时进度不写入正式存档") end
    PT.active = true
    print("[编辑试玩] 开始独立进度；从指定初始出生点测试完整玩法")
end

function PT.finish()
    if not PT.active then return end
    GS.save = originalSave
    GS.saveGame = originalWriter
    originalSave, originalWriter = nil, nil
    PT.worldSource = nil
    PT.active = false
    print("[编辑试玩] 已恢复正式游戏进度")
end

return PT
