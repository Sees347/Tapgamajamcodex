-- ============================================================================
-- data/items.lua - 道具表 + 探索奖励（饰品）
-- 来源: docs/道具表.txt + docs/探索奖励.txt
-- ============================================================================

---@class ItemDef
---@field key string
---@field name string
---@field desc string
---@field color number[]
---@field radius number
---@field kind string   currency / fragment / core / shard / quanxin / relic / shell

---@type table<string, ItemDef>
local ITEMS = {}

ITEMS.shell = {
    key = "shell", name = "贝壳", kind = "currency", radius = 0.24,
    desc = "现在流通的通用货币，可以在 NPC 处购买物品。",
    color = { 250, 220, 160 },
}

ITEMS.symbShard = {
    key = "symbShard", name = "共生碎片", kind = "fragment", radius = 0.28,
    desc = "收集 3 个合成共生核心，提升可携带的水生生物数量。",
    color = { 150, 240, 200 },
}

ITEMS.symbCore = {
    key = "symbCore", name = "共生核心", kind = "core", radius = 0.34,
    desc = "提升可携带的水生生物数量（解锁一个共生槽）。",
    color = { 90, 230, 180 },
}

ITEMS.brokenQuanxin = {
    key = "brokenQuanxin", name = "破碎泉心", kind = "shard", radius = 0.28,
    desc = "收集 3 个合成泉心，提升水量上限。",
    color = { 200, 190, 255 },
}

ITEMS.quanxin = {
    key = "quanxin", name = "泉心", kind = "quanxin", radius = 0.34,
    desc = "提升水量上限（+2 水量上限）。",
    color = { 160, 140, 255 },
}

-- =============== 探索奖励饰品（docs/探索奖励.txt） ===============

---@class RelicDef
---@field key string
---@field name string
---@field source string   获取方式
---@field desc string     效果
---@field color number[]
---@field effect table    效果参数

---@type table<string, RelicDef>
local RELICS = {}

RELICS.waterPendant = {
    key = "waterPendant", name = "凝水坠饰",
    source = "零号实验室隐藏房间",
    desc = "吸收水源时额外 +0.5 水量（上限依旧受泉心限制，不能突破上限）。",
    color = { 140, 220, 255 },
    effect = { absorbBonus = 0.5 },
}

RELICS.heatCrystal = {
    key = "heatCrystal", name = "耐热结晶",
    source = "零号实验室精英怪掉落",
    desc = "受到火焰伤害 -1；依旧会被火变成气态，只是扣血少一点。",
    color = { 255, 170, 110 },
    effect = { fireResist = 1 },
}

RELICS.coldShell = {
    key = "coldShell", name = "隔冷壳",
    source = "冷冻库宝箱",
    desc = "受到低温伤害 -1；依旧会被冻成固态。",
    color = { 150, 220, 250 },
    effect = { coldResist = 1 },
}

RELICS.bulletShard = {
    key = "bulletShard", name = "弹壳碎片",
    source = "多手的怪物击败后宝箱",
    desc = "固态形态撞击敌人有小概率短暂眩晕敌人。",
    color = { 220, 200, 130 },
    effect = { ramStunChance = 0.25, ramStunDur = 1.2 },
}

RELICS.vaporFilm = {
    key = "vaporFilm", name = "水汽护膜",
    source = "冷冻库隐藏跳跳乐",
    desc = "气态形态受到伤害小幅降低。",
    color = { 220, 240, 250 },
    effect = { gasResist = 0.5 },
}

return { ITEMS = ITEMS, RELICS = RELICS }
