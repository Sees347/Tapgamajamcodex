-- ============================================================================
-- core/tuning.lua - 运行时调参系统
-- 职责：
--   1. 定义「核心可调参数」的 schema（分组 + 每项 path/label/min/max/step）
--   2. 沿 path 读写 config.lua 的值（config 是唯一数据源，各模块实时读取）
--   3. 沙箱持久化：把改动存到存档区 override 文件，启动时自动加载覆盖默认值
--   4. 副作用钩子：个别参数（如相机视野）改后需要额外动作，由 main 注册
-- 说明：scripts/ 是只读源码区，无法运行时改写 config.lua 本身；
--       因此「持久化」= 存一份 override 到沙箱，下次启动覆盖到内存中的 Config。
--       想把调好的值固化进版本，用 exportText() 打印 Lua 文本手动粘回 config.lua。
-- ============================================================================

local Config = require "config"

---@class TuningParam
---@field path string       config 内的点分路径，如 "FORMS.liquid.speed"
---@field label string      面板显示名
---@field min number        滑块下限（若提供了 toDisplay，则为显示单位）
---@field max number        滑块上限（同上）
---@field step number       步长（同上）
---@field toDisplay? fun(raw:number):number    内部值 → 显示值（派生参数用）
---@field fromDisplay? fun(disp:number):number 显示值 → 内部值

---@class TuningGroup
---@field group string
---@field items TuningParam[]

---@class Tuning
local Tuning = {}

Tuning.SAVE_FILE = "yongquan_tuning.json"

-- ===================== 跳跃：高度 ↔ 初速 换算（通用，按形态） =====================
-- 上升期有重力缩放(gravUp)与空气阻尼(damping，气态才有)，高度与初速非线性。
-- 用与 player.lua/Box2D 相同的积分步进求真实高度；再二分反解初速。
---@param form string 形态键（liquid/gas/solid）
---@param v0 number 跳跃初速 (米/秒)
---@return number 实际跳跃高度 (米)
local function jumpHeightOf(form, v0)
    local f = Config.FORMS[form]
    if not f then return 0 end
    local g = Config.GRAVITY * f.gravUp
    local damp = f.damping
    local dt = 1 / 60
    local v, y = v0, 0.0
    for _ = 1, 600 do
        v = v + (-g) * dt            -- Box2D: 先加重力
        v = v / (1 + damp * dt)      -- Box2D: 再乘阻尼
        y = y + v * dt
        if v <= 0 then break end
    end
    return y
end

--- 反解：给定目标高度(米)，求所需跳跃初速。
---@param form string
---@param h number 目标高度 (米)
---@return number 初速 (米/秒)
local function jumpVelForHeightOf(form, h)
    local lo, hi = 0.1, 80.0
    for _ = 1, 40 do
        local mid = (lo + hi) * 0.5
        if jumpHeightOf(form, mid) < h then lo = mid else hi = mid end
    end
    return (lo + hi) * 0.5
end

-- ===================== 参数 schema（面板只放核心高频项） =====================
-- 完整的怪物/鱼/子弹/经济数值都在 config.lua 里，改文件重新构建即可；
-- 面板聚焦最常反复调的手感/难度/相机参数。
---@type TuningGroup[]
Tuning.SCHEMA = {
    {
        group = "世界与相机",
        items = {
            { path = "VIEW_H",   label = "相机视野高度(米)", min = 8,  max = 26, step = 0.5 },
            { path = "GRAVITY",  label = "重力加速度",       min = 5,  max = 40, step = 0.5 },
        },
    },
    {
        group = "玩家生命",
        items = {
            { path = "PLAYER.initWater",     label = "初始水量",       min = 1,  max = 20, step = 1 },
            { path = "PLAYER.maxWaterBase",  label = "水量上限基准",   min = 4,  max = 30, step = 1 },
            { path = "PLAYER.hurtInvuln",    label = "受击无敌(秒)",   min = 0,  max = 3,  step = 0.1 },
        },
    },
    {
        group = "三形态手感",
        items = {
            { path = "FORMS.liquid.speed",   label = "液态 移速",      min = 1,  max = 16, step = 0.1 },
            -- 三形态跳跃都用「高度(米)」表达（比初速直观）；内部仍存 jumpVel，联动非线性换算。
            { path = "FORMS.liquid.jumpVel", label = "液态 跳跃高度(米)", min = 0.5, max = 10, step = 0.1,
              toDisplay = function(v) return jumpHeightOf("liquid", v) end,
              fromDisplay = function(h) return jumpVelForHeightOf("liquid", h) end },
            { path = "FORMS.gas.speed",      label = "气态 移速",      min = 1,  max = 16, step = 0.1 },
            { path = "FORMS.gas.jumpVel",    label = "气态 跳跃高度(米)", min = 0.5, max = 12, step = 0.1,
              toDisplay = function(v) return jumpHeightOf("gas", v) end,
              fromDisplay = function(h) return jumpVelForHeightOf("gas", h) end },
            { path = "PLAYER.flyFlap",       label = "气态飞鱼 扇动上升", min = 2, max = 24, step = 0.5 },
            { path = "PLAYER.flyDamping",    label = "气态飞鱼 飘浮保持", min = 0.8, max = 0.999, step = 0.005 },
            -- 可变跳跃高度：点按跳多矮 / 满跳需按住多久
            { path = "PLAYER.jumpCutMul",     label = "跳跃 松手截断系数", min = 0.1, max = 1, step = 0.02 },
            { path = "PLAYER.jumpHoldMaxTime", label = "跳跃 满跳按住时长", min = 0.1, max = 1, step = 0.02 },
            { path = "FORMS.solid.speed",    label = "固态 移速",      min = 1,  max = 18, step = 0.1 },
            { path = "FORMS.solid.jumpVel",  label = "固态 跳跃高度(米)", min = 0.5, max = 10, step = 0.1,
              toDisplay = function(v) return jumpHeightOf("solid", v) end,
              fromDisplay = function(h) return jumpVelForHeightOf("solid", h) end },
        },
    },
    {
        group = "位移 (Shift)",
        items = {
            { path = "DASH.distance", label = "位移距离(米)",   min = 1,    max = 10, step = 0.1 },
            { path = "DASH.duration", label = "位移时长(秒)",   min = 0.05, max = 1,  step = 0.01 },
            { path = "DASH.cooldown", label = "位移冷却(秒)",   min = 0,    max = 3,  step = 0.05 },
        },
    },
    {
        group = "弹幕",
        items = {
            { path = "PLAYER.baseAtk",          label = "基础伤害",        min = 0.5, max = 50, step = 0.5 },
            { path = "PLAYER.baseAtkRange",     label = "基础射程(米)",    min = 1,   max = 20, step = 0.5 },
            { path = "BALANCE.bulletRange",     label = "全弹幕射程倍率",  min = 0.2, max = 5,  step = 0.1 },
            { path = "PLAYER.baseAtkFreq",      label = "射击间隔(秒/发)", min = 0.05, max = 2, step = 0.05 },
            { path = "PLAYER.baseBulletSpeed",  label = "弹速(米/秒)",     min = 4,   max = 40, step = 0.5 },
            { path = "BULLETS.waterArtSizeMul", label = "水弹 绘制大小",   min = 1,   max = 12, step = 0.5 },
            { path = "BULLETS.lightningArtSizeMul", label = "闪电 绘制大小", min = 1, max = 16, step = 0.5 },
        },
    },
    {
        group = "难度平衡",
        items = {
            { path = "BALANCE.monsterHp",  label = "怪物血量倍率", min = 0.1, max = 5,  step = 0.1 },
            { path = "BALANCE.monsterDmg", label = "怪物伤害倍率", min = 0,   max = 5,  step = 0.1 },
            { path = "BALANCE.playerDmg",  label = "玩家伤害倍率", min = 0.1, max = 10, step = 0.1 },
            { path = "BALANCE.dropRate",   label = "掉落倍率",     min = 0,   max = 5,  step = 0.1 },
        },
    },
    {
        group = "装备组合",
        items = {
            { path = "COMBO.gasFlyEelAirSpeed", label = "飞鱼+电鳗 空中横移", min = 0, max = 3, step = 0.1 },
        },
    },
    {
        group = "新装备机制",
        items = {
            { path = "FLYDASH.distance", label = "飞鱼冲刺 距离(米)", min = 1,   max = 8,  step = 0.1 },
            { path = "FLYDASH.cooldown", label = "飞鱼冲刺 冷却(秒)", min = 0.05, max = 1, step = 0.01 },
            { path = "GRAPPLE.maxLength", label = "青蛙钩爪 绳长(米)", min = 3,  max = 16, step = 0.5 },
            { path = "GRAPPLE.pullSpeed", label = "青蛙钩爪 拉速(米/秒)", min = 5, max = 30, step = 0.5 },
            { path = "BLOCK.reduce",      label = "剑鱼格挡 减伤比例", min = 0,  max = 0.95, step = 0.05 },
        },
    },
    {
        group = "打击手感",
        items = {
            -- 抖动幅度总系数：实际像素 = 强度 × ppu × 此值
            { path = "FEEL.shakeScale", label = "镜头抖动 幅度", min = 0, max = 2, step = 0.05 },
            -- 各强度敌人的抖动（强度 / 时长）
            { path = "FEEL.killShake.small.1", label = "小怪 抖动强度", min = 0, max = 4, step = 0.05 },
            { path = "FEEL.killShake.small.2", label = "小怪 抖动时长", min = 0, max = 1, step = 0.02 },
            { path = "FEEL.killShake.elite.1", label = "精英 抖动强度", min = 0, max = 4, step = 0.05 },
            { path = "FEEL.killShake.elite.2", label = "精英 抖动时长", min = 0, max = 1, step = 0.02 },
            { path = "FEEL.killShake.boss.1",  label = "BOSS 抖动强度", min = 0, max = 6, step = 0.05 },
            { path = "FEEL.killShake.boss.2",  label = "BOSS 抖动时长", min = 0, max = 2, step = 0.02 },
            { path = "MELEE_FX.swingLock",     label = "剑鱼挥砍 定身(秒)", min = 0, max = 0.5, step = 0.01 },
        },
    },
}

-- ===================== path 读写 =====================

--- 把 "A.B.C" 解析为 (父表, 末键)
---@param path string
---@return table|nil parent, string|nil key
local function resolve(path)
    ---@type any
    local t = Config
    local keys = {}
    for k in path:gmatch("[^%.]+") do
        -- 纯数字段按数组下标处理（如 killShake.small.1）
        keys[#keys + 1] = tonumber(k) or k
    end
    for i = 1, #keys - 1 do
        t = t[keys[i]]
        if type(t) ~= "table" then return nil, nil end
    end
    return t, keys[#keys]
end

--- 读取参数当前值（派生参数返回「显示值」）
---@param path string
---@param param TuningParam|nil 若提供且含 toDisplay，则转换为显示值
---@return number|nil
function Tuning.get(path, param)
    local parent, key = resolve(path)
    if parent and key then
        local v = parent[key]
        if type(v) == "number" then
            if param and param.toDisplay then return param.toDisplay(v) end
            return v
        end
    end
    return nil
end

--- 写入参数（立即生效：各模块实时读 Config）
---@param path string
---@param value number 若 param 含 fromDisplay，则 value 是「显示值」，需转回内部值
---@param param TuningParam|nil
function Tuning.set(path, value, param)
    local parent, key = resolve(path)
    if parent and key then
        local raw = (param and param.fromDisplay) and param.fromDisplay(value) or value
        parent[key] = raw
        Tuning.overrides[path] = raw      -- 持久化内部值，加载/导出无需特殊处理
        local hook = Tuning.hooks[path]
        if hook then hook(raw) end
    end
end

-- ===================== 默认值快照 & override =====================

---@type table<string, number>  被改动的 path → value（持久化对象）
Tuning.overrides = {}
---@type table<string, number>  出厂默认值快照（reset 用）
Tuning.defaults = {}
---@type table<string, fun(value:number)>  path → 副作用钩子
Tuning.hooks = {}

--- 注册副作用钩子（如相机视野改后需重设 orthoSize）
---@param path string
---@param fn fun(value:number)
function Tuning.setHook(path, fn)
    Tuning.hooks[path] = fn
end

--- 拍默认值快照（require 时调用一次，此时 Config 尚未被 override 覆盖）
local function buildDefaults()
    for _, grp in ipairs(Tuning.SCHEMA) do
        for _, p in ipairs(grp.items) do
            local v = Tuning.get(p.path)     -- 内部值（不传 param）
            if v then Tuning.defaults[p.path] = v end
        end
    end
end

--- 是否被改过（面板高亮用）
---@param path string
---@return boolean
function Tuning.isModified(path)
    return Tuning.overrides[path] ~= nil
end

--- 恢复全部默认（清 override，写回 Config；不自动 save，由面板决定）
function Tuning.reset()
    for _, grp in ipairs(Tuning.SCHEMA) do
        for _, p in ipairs(grp.items) do
            local d = Tuning.defaults[p.path]
            if d then
                local parent, key = resolve(p.path)
                if parent and key then
                    parent[key] = d
                    local hook = Tuning.hooks[p.path]
                    if hook then hook(d) end
                end
            end
        end
    end
    Tuning.overrides = {}
end

-- ===================== 沙箱持久化 =====================

--- 启动时加载 override 并应用到 Config（在 CreateScene 之前调用）
---@return boolean 是否成功读到存档
function Tuning.load()
    if not fileSystem:FileExists(Tuning.SAVE_FILE) then return false end
    ---@type File?
    local f = File(Tuning.SAVE_FILE, FILE_READ)
    if not f or not f:IsOpen() then return false end
    local content = f:ReadString()
    f:Close()
    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then
        print("[Tuning] 解析失败，使用默认参数")
        return false
    end
    local n = 0
    for path, value in pairs(data) do
        if type(value) == "number" and Tuning.get(path) ~= nil then
            Tuning.set(path, value)   -- 写 Config + 记 override + 触发 hook
            n = n + 1
        end
    end
    print("[Tuning] 已加载 " .. n .. " 项调参覆盖")
    return n > 0
end

--- 保存当前 override 到沙箱
function Tuning.save()
    ---@type File?
    local f = File(Tuning.SAVE_FILE, FILE_WRITE)
    if not f or not f:IsOpen() then
        print("[Tuning] 写入失败")
        return
    end
    f:WriteString(cjson.encode(Tuning.overrides))
    f:Close()
    local cnt = 0
    for _ in pairs(Tuning.overrides) do cnt = cnt + 1 end
    print("[Tuning] 已保存 " .. cnt .. " 项调参")
end

--- 删除调参存档（下次启动回默认）
function Tuning.deleteSave()
    if fileSystem:FileExists(Tuning.SAVE_FILE) then
        fileSystem:Delete(Tuning.SAVE_FILE)
    end
    Tuning.overrides = {}
end

--- 精简数字：整数不带小数，其余最多 4 位并去掉尾零。
---@param v number
---@return string
local function fmtNum(v)
    if v % 1 == 0 and math.abs(v) < 1e9 then return string.format("%d", v) end
    local s = string.format("%.4f", v)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

--- 导出改动过的参数为可粘贴的 Lua 文本。
--- 写的是 config 内部值（可直接覆盖对应字段）；派生参数在注释里附上面板显示值。
---@return string
function Tuning.exportText()
    local lines = { "-- 《涌泉》调参导出（粘贴覆盖 config.lua 对应字段）" }
    for _, grp in ipairs(Tuning.SCHEMA) do
        for _, p in ipairs(grp.items) do
            local v = Tuning.get(p.path)
            if v and Tuning.isModified(p.path) then
                local comment = p.label
                if p.toDisplay then
                    comment = comment .. ("（面板显示 %s）"):format(fmtNum(p.toDisplay(v)))
                end
                lines[#lines + 1] = string.format("Config.%s = %s   -- %s", p.path, fmtNum(v), comment)
            end
        end
    end
    if #lines == 1 then lines[#lines + 1] = "-- （无改动）" end
    local text = table.concat(lines, "\n")
    print(text)
    return text
end

buildDefaults()

return Tuning
