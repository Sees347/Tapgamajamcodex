-- ============================================================================
-- data/monsters.lua - 怪物配置表
-- 来源: docs/怪物.txt + docs/怪物配置表.txt
-- atkType: 1=近战挥打, 2=远程抛射, 3=冲刺撞击
-- tier:    "small" 小怪, "elite" 精英怪, "boss" BOSS
-- ============================================================================

local Config = require "config"

---@class MonsterAttackDef
---@field atkType integer         1=近战 2=远程 3=冲撞
---@field special boolean         是否为特殊攻击
---@field desc string
---@field range number            攻击距离 (米)
---@field dmg integer             攻击力
---@field freq number             攻击频率 (秒/次)

---@class MonsterDef
---@field id integer
---@field key string
---@field name string
---@field tier string             small / elite / boss
---@field hp integer
---@field speed number            巡逻/追击移速 (米/秒)
---@field detectRange number      感知半径 (米)
---@field radius number           碰撞半径 (米)
---@field flying boolean          是否飞行
---@field color number[]
---@field accent number[]
---@field attacks MonsterAttackDef[]
---@field ai string               AI 行为标识: chaser/shooter/dasher/fixed/lightSeeker/crab
---@field phototaxis string|nil   "light" 趋光 / "dark" 畏光 / nil 无
---@field weight number           重量（压板判定用，>1 可压开）

---@type table<string, MonsterDef>
local MON = {}

-- ===================== 小怪 =====================

MON.cleaner01 = {
    id = 20001, key = "cleaner01", name = "清洁机器人-01", tier = "small",
    hp = 35, speed = 2.2, detectRange = 6.0, radius = 0.45, flying = false,
    color = { 165, 175, 190 }, accent = { 90, 200, 160 },
    ai = "chaser", weight = 2.0,
    attacks = {
        { atkType = 1, special = true, desc = "挥动手臂", range = 1, dmg = 1, freq = 1.0 },
    },
}

MON.cleaner02 = {
    id = 20002, key = "cleaner02", name = "清洁机器人-02", tier = "small",
    hp = 20, speed = 0.0, detectRange = 7.0, radius = 0.4, flying = false,
    color = { 150, 160, 178 }, accent = { 230, 200, 120 },
    ai = "shooter", weight = 2.0,
    attacks = {
        { atkType = 2, special = true, desc = "发射海绵", range = 3, dmg = 1, freq = 1.2 },
    },
}

MON.fly = {
    id = 20003, key = "fly", name = "变异飞蝇", tier = "small",
    hp = 15, speed = 3.4, detectRange = 7.5, radius = 0.3, flying = true,
    color = { 120, 100, 90 }, accent = { 200, 120, 180 },
    ai = "dasher", weight = 0.2,
    attacks = {
        { atkType = 3, special = false, desc = "朝玩家冲撞1次", range = 2, dmg = 1, freq = 1.0 },
    },
}

MON.lightBeast = {
    id = 20004, key = "lightBeast", name = "趋光菌兽", tier = "elite",
    hp = 50, speed = 2.8, detectRange = 8.0, radius = 0.55, flying = false,
    color = { 110, 140, 120 }, accent = { 220, 250, 150 },
    ai = "lightSeeker", phototaxis = "light", weight = 3.0,
    attacks = {
        { atkType = 1, special = true,
          desc = "未交战时向感知范围内的光源靠近；受到攻击后优先追击玩家，接近后进行短距离扑咬2次。",
          range = 1, dmg = 1, freq = 1.2 },
    },
}

MON.spore = {
    id = 20005, key = "spore", name = "喷孢菌", tier = "small",
    hp = 18, speed = 0.0, detectRange = 8.0, radius = 0.38, flying = false,
    color = { 140, 120, 150 }, accent = { 200, 240, 130 },
    ai = "fixed", weight = 1.0,
    attacks = {
        { atkType = 2, special = true,
          desc = "固定在原地，发现玩家后朝玩家方向喷出3枚扇形孢子弹，每枚造成直接伤害。",
          range = 3, dmg = 1, freq = 2.0 },
    },
}

MON.crab = {
    id = 20006, key = "crab", name = "裂钳蟹", tier = "elite",
    hp = 57, speed = 1.6, detectRange = 7.0, radius = 0.6, flying = false,
    color = { 185, 110, 95 }, accent = { 240, 200, 170 },
    ai = "crab", weight = 4.0,
    attacks = {
        { atkType = 1, special = true,
          desc = "近距离时，两只大螯交替砸击，每次攻击使用一只；攻击前抬起对应的螯进行预警，近战与远程共用冷却。",
          range = 1, dmg = 1, freq = 1.5 },
        { atkType = 2, special = true,
          desc = "远距离时，两只小螯交替抛出碎石，每次发射1枚。",
          range = 3, dmg = 1, freq = 1.5 },
    },
}

MON.manyHands = {
    id = 20007, key = "manyHands", name = "门帝克3型", tier = "elite",
    hp = 65, speed = 2.4, detectRange = 8.5, radius = 0.7, flying = false,
    color = { 130, 120, 150 }, accent = { 250, 180, 90 },
    ai = "manyHands", weight = 5.0,
    attacks = {
        { atkType = 2, special = true, desc = "2只手负责远程攻击", range = 4, dmg = 1, freq = 1.2 },
        { atkType = 1, special = true, desc = "2只手负责近战攻击", range = 1.4, dmg = 1, freq = 1.2 },
    },
}

-- ===================== BOSS =====================

MON.bossIceFire = {
    id = 30001, key = "bossIceFire", name = "冰火人", tier = "boss",
    hp = 120, speed = 3.0, detectRange = 20.0, radius = 1.1, flying = false,
    color = { 200, 100, 80 }, accent = { 130, 210, 255 },
    ai = "bossIceFire", weight = 10.0,
    attacks = {
        { atkType = 2, special = true, desc = "P1 冰火交替吐息", range = 9, dmg = 1, freq = 2.0 },
        { atkType = 3, special = true, desc = "P1 落地冲击 / P3 冰火冲撞", range = 6, dmg = 2, freq = 5.0 },
        { atkType = 2, special = true, desc = "P1 散弹投射：火球、冰球交叉散射", range = 12, dmg = 1, freq = 3.0 },
    },
}

-- 展示顺序（图鉴用）: fly, cleaner01, cleaner02, spore, crab, lightBeast, manyHands, bossIceFire
-- BOSS 阶段血量阈值: 见 Config.BOSS.phaseP2 / phaseP3

-- ============================================================================
-- 数值合并：本文件只维护身份/结构（id、名字、tier、颜色、AI、weight、攻击描述），
-- 数值（hp/speed/detectRange/radius/攻击 range·dmg·freq）以 config.lua 的
-- Config.MONSTER_STATS 为唯一权威来源，在此覆盖到 MON 定义上。
-- 改数值 → 改 config.lua（或游戏内调参面板）；改行为/文案 → 改本文件。
-- ============================================================================
local function mergeStats()
    local STATS = Config.MONSTER_STATS or {}
    for key, def in pairs(MON) do
        local st = STATS[key]
        if st then
            def.hp = st.hp
            def.speed = st.speed
            def.detectRange = st.detectRange
            def.radius = st.radius
            def.atkAnimTime = st.atkAnimTime or def.atkAnimTime
            -- 逐条覆盖攻击数值（保持本文件的 atkType/special/desc 结构）
            for i, atk in ipairs(def.attacks) do
                local sa = st.attacks and st.attacks[i]
                if sa then
                    atk.range = sa.range
                    atk.dmg = sa.dmg
                    atk.freq = sa.freq
                end
            end
        else
            print("[Monsters] 警告: " .. key .. " 在 Config.MONSTER_STATS 中缺少数值，沿用本文件默认")
        end
    end
end

mergeStats()

return MON
