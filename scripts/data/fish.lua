-- ============================================================================
-- data/fish.lua - 水生生物（装备）配置表
-- 来源: docs/装备配置表.txt + docs/水生生物.txt
-- 身份/颜色/描述在本文件；各形态效果数值以 config.lua 的 Config.FISH_STATS 为权威源。
-- ============================================================================

local Config = require "config"

---@class FishFormEffect
---@field range number|nil        攻击距离 (米)
---@field dir string|nil          攻击方向: mouse/orbit/down/auto/homing/self
---@field dmg number|nil          攻击力
---@field freq number|nil         攻击频率 (秒/发)
---@field poisonDps number|nil    中毒秒伤
---@field paralysis number|nil    麻痹时间 (秒)
---@field stickMax number|nil     同时存在黏附上限
---@field stickDur number|nil     黏附持续时间 (秒)
---@field devourCd number|nil     吞噬时间间隔 (秒)
---@field lightRange number|nil   光圈范围 (米)
---@field hoverDur number|nil     弹幕悬停时间 (秒)
---@field bounceMax number|nil    最大反弹次数
---@field speedUp number|nil      移速提升 (比例)
---@field ramDmg number|nil       撞击伤害
---@field slow number|nil         延缓敌人速度 (比例)
---@field blindRange number|nil   目盲范围 (米)
---@field blindDur number|nil     目盲时间 (秒)
---@field doubleJump boolean|nil  能否二段跳
---@field glide boolean|nil       滑翔
---@field dash boolean|nil        冲刺（飞鱼气态）
---@field grapple boolean|nil     钩爪：发射绳状水柱粘住地形并拉近（青蛙液态）
---@field melee boolean|nil       近战攻击（剑鱼液态/固态）
---@field block boolean|nil       格挡攻击（剑鱼固态）
---@field burst integer|nil       连发数（剑鱼气态 3 连发）
---@field fly boolean|nil         自由飞行
---@field recoil boolean|nil      发射时自身反向弹开（猛击）

---@class FishDef
---@field id integer
---@field key string
---@field name string
---@field itemType integer        1=鱼类, 2=其他水生生物
---@field desc string             形态连携描述
---@field color number[]          渲染主色 RGB
---@field accent number[]         渲染辅色 RGB
---@field liquid FishFormEffect
---@field gas FishFormEffect
---@field solid FishFormEffect

---@type table<string, FishDef>
local FISH = {}

FISH.archerfish = {
    id = 10001, key = "archerfish", name = "射水鱼", itemType = 1,
    desc = "液态：提高玩家攻击频率，远程攻击。\n气态：短暂蓄力，将空气炮射出，自身反方向弹开。\n固态：射出冰锥，伤害更高，并且可以减缓敌人速度。",
    color = { 90, 200, 160 }, accent = { 220, 250, 240 },
    liquid = { range = 3, dir = "mouse", dmg = 5, freq = 0.5 },
    gas    = { range = 3, dir = "mouse", dmg = 10, freq = 1.0, recoil = true },
    solid  = { range = 3, dir = "mouse", dmg = 15, freq = 1.0, slow = 0.4 },
}

FISH.eel = {
    id = 10002, key = "eel", name = "电鳗", itemType = 1,
    desc = "液态：弹幕形成电场，持续对周围敌人造成伤害和产生麻痹效果。\n气态：玩家攻击切换为劈出闪电。\n固态：玩家周身环绕电流，怪物触碰有电流伤害。",
    color = { 120, 110, 200 }, accent = { 250, 250, 140 },
    liquid = { range = 1, dir = "orbit", dmg = 6, freq = 0.5, paralysis = 0.5 },
    gas    = { range = 4, dir = "down", dmg = 4, freq = 0.5 },
    solid  = { range = 0, dir = "self", dmg = 8, freq = 0.5 },
}

FISH.flyfish = {
    id = 10003, key = "flyfish", name = "飞鱼", itemType = 1,
    desc = "液态：玩家获得滑翔能力。\n气态：玩家获得冲刺能力。\n固态：硬化翅膀，提升移速，提高撞击伤害。",
    color = { 130, 190, 235 }, accent = { 240, 250, 255 },
    liquid = { glide = true },
    gas    = { dash = true },
    solid  = { speedUp = 0.4, ramDmg = 12 },
}

FISH.anglerfish = {
    id = 10004, key = "anglerfish", name = "鮟鱇鱼", itemType = 1,
    desc = "液态：发光吸引趋光性生物。\n气态：赋予弹幕自动追踪靠近的敌人。\n固态：使靠近的敌人目盲数秒。",
    color = { 60, 70, 110 }, accent = { 255, 240, 170 },
    liquid = { lightRange = 3.0, dir = "mouse", dmg = 4, freq = 0.6, range = 6 },
    gas    = { dir = "homing", dmg = 5, freq = 0.5, range = 7 },
    solid  = { blindRange = 3.5, blindDur = 1.0 },
}

FISH.ray = {
    id = 10005, key = "ray", name = "鳐鱼", itemType = 1,
    desc = "液态：弹幕附带中毒效果。\n气态：提升玩家移动速度。",
    color = { 150, 140, 175 }, accent = { 200, 230, 200 },
    liquid = { dir = "mouse", dmg = 3, freq = 0.5, range = 5, poisonDps = 3 },
    gas    = { speedUp = 0.3 },
    solid  = {},
}

FISH.barnacle = {
    id = 10006, key = "barnacle", name = "藤壶", itemType = 2,
    desc = "液态：弹幕命中敌人或地形后黏附3秒，保留附带效果。\n气态：弹幕飞至射程终点后悬停3秒，保留附带效果。\n固态：弹幕碰到地形后反弹，最多反弹2次，保留附带效果。",
    color = { 170, 150, 120 }, accent = { 230, 220, 200 },
    liquid = { stickMax = 4, stickDur = 3.0 },
    gas    = { hoverDur = 3.0 },
    solid  = { bounceMax = 2 },
}

FISH.frog = {
    id = 10007, key = "frog", name = "青蛙", itemType = 2,
    desc = "液态：玩家自身发一个绳子状的水柱，可粘在地面、墙面、天花板（参考泰拉瑞亚的钩爪）。\n固态：玩家自身获得二段跳。",
    color = { 110, 190, 90 }, accent = { 230, 250, 200 },
    liquid = { grapple = true },
    gas    = {},
    solid  = { doubleJump = true },
}

FISH.swordfish = {
    id = 10008, key = "swordfish", name = "剑鱼", itemType = 1,
    desc = "液态：攻击切换为近战攻击，提高攻击频率。\n气态：攻击弹幕变成3连发。\n固态：攻击切换为近战攻击，保留冲撞伤害，同时获得格挡攻击能力。",
    color = { 90, 130, 180 }, accent = { 200, 225, 245 },
    liquid = { melee = true, range = 2.4, dmg = 6, freq = 0.35 },
    gas    = { range = 3, dir = "mouse", dmg = 4, freq = 0.8, burst = 3 },
    solid  = { melee = true, range = 2.6, dmg = 12, freq = 0.6, block = true },
}

-- ============================================================================
-- 数值合并：各形态效果（range/dmg/freq/特效数值）以 config.lua 的
-- Config.FISH_STATS 为唯一权威来源，在此整体替换本文件的 liquid/gas/solid 表。
-- 上方内联数值仅作缺省兜底（config 缺该鱼时保留）。
-- 改数值 → 改 config.lua（或游戏内调参面板）；改文案/颜色 → 改本文件。
-- ============================================================================
local function mergeFishStats()
    local STATS = Config.FISH_STATS or {}
    for key, def in pairs(FISH) do
        local st = STATS[key]
        if st then
            def.liquid = st.liquid or def.liquid
            def.gas = st.gas or def.gas
            def.solid = st.solid or def.solid
        else
            print("[Fish] 警告: " .. key .. " 在 Config.FISH_STATS 中缺少数值，沿用本文件默认")
        end
    end
end

mergeFishStats()

return FISH
