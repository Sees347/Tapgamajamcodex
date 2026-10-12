-- ============================================================================
-- levels/testmap.lua - 功能测试地图
-- 包含: 全部 7 种鱼 / 全部怪物与精英怪 / 冰火人 BOSS / 全部饰品
--       全部机关（水火低温海绵泉眼压板电力接口电子门烟雾报警器）
--       三形态转换测试区
-- ============================================================================

---@type table
local LEVEL = {
    id = "testmap",
    name = "功能测试场",
    subtitle = "全要素测试地图",
    theme = "lab",
    deathY = -8.0,
    bounds = { minX = -6, maxX = 170, minY = -8, maxY = 30 },
    spawn = { x = 0, y = 1.2 },
    startForm = "liquid",

    platforms = {
        -- 出生平台（全鱼全道具补给区）
        { x = 0, y = -0.5, w = 16, h = 1 },
        -- 形态测试区
        { x = 16, y = -0.5, w = 14, h = 1 },
        -- 机关测试区
        { x = 34, y = -0.5, w = 20, h = 1 },
        { x = 40, y = 2.0, w = 3, h = 0.4 },
        { x = 47, y = 4.0, w = 3, h = 0.4 },
        -- 小怪竞技场
        { x = 62, y = -0.5, w = 20, h = 1 },
        { x = 58, y = 1.8, w = 0.8, h = 4, solid = true },   -- 隔离墙（液态跳不过，气态可翻越）
        -- 精英怪竞技场
        { x = 88, y = -0.5, w = 22, h = 1 },
        { x = 84, y = 1.8, w = 0.8, h = 4, solid = true },
        -- BOSS 竞技场
        { x = 122, y = -0.5, w = 30, h = 1 },
        { x = 110, y = 1.8, w = 0.8, h = 4, solid = true },
        { x = 116, y = 4.0, w = 2.5, h = 0.4 },
        { x = 128, y = 4.0, w = 2.5, h = 0.4 },
        { x = 122, y = 7.0, w = 2.5, h = 0.4 },
        -- 高台（气态飞行测试）
        { x = 140, y = 10, w = 4, h = 0.5 },
        { x = 150, y = 13, w = 20, h = 1 },   -- 顶层奖励区
        { x = 152, y = 2.0, w = 0.8, h = 24, solid = true }, -- 右侧墙
        -- 天花板
        { x = 80, y = 24, w = 180, h = 1, solid = true },
    },

    hazards = {
        -- 出生区泉眼
        { kind = "spring", id = "test_s1", x = -6, y = 0.6, w = 1.2, h = 1.2 },

        -- 形态测试区：火(冰→液→气) / 低温(气→液→冰)，每次进入只变一级
        { kind = "fire", x = 12, y = 0.4, w = 1.6, h = 1.0 },
        { kind = "weakfire", x = 14.5, y = 0.4, w = 1.4, h = 1.0 },
        { kind = "cold", x = 18, y = 0.4, w = 2.0, h = 1.0 },
        { kind = "water", x = 21, y = 0.4, w = 0.8, h = 0.8, charges = 99 },
        { kind = "water", x = 22, y = 0.4, w = 0.8, h = 0.8, charges = 99 },
        -- 海绵陷阱
        { kind = "sponge", x = 25, y = 0.5, w = 1.0, h = 1.0 },

        -- 机关测试区: 压板 + 电子门 + 电力接口(电鳗) + 烟雾报警器
        { kind = "plate", id = "test_plate1", x = 36, y = 0.15, w = 1.6, h = 0.3 },
        { kind = "door", id = "test_door1", x = 43.5, y = 0.9, w = 0.8, h = 2.8, needsPower = true },
        { kind = "outlet", id = "test_outlet1", x = 42.5, y = 0.6, w = 0.6, h = 0.6 },
        { kind = "alarm", id = "test_alarm1", x = 47, y = 6.5, w = 0.7, h = 0.5, needsPower = true },
        { kind = "water", x = 49.5, y = 0.4, w = 0.8, h = 0.8, charges = 99 },
        -- 低温通道（固态打滑测试）
        { kind = "cold", x = 52, y = 0.3, w = 3.0, h = 0.8 },

        -- BOSS 场地内的水源（对策：用水灭火区）
        { kind = "water", x = 112, y = 0.4, w = 0.8, h = 0.8, charges = 99 },
        { kind = "water", x = 133, y = 0.4, w = 0.8, h = 0.8, charges = 99 },
        -- BOSS 房内泉眼
        { kind = "spring", id = "test_s2", x = 111, y = 0.6, w = 1.2, h = 1.2 },
    },

    wires = {
        { from = "test_outlet1", to = "test_door1" },
        { from = "test_outlet1", to = "test_alarm1" },
    },

    enemies = {
        -- 小怪竞技场（4 种小怪）
        { key = "cleaner01", x = 60, y = 0.6 },
        { key = "cleaner02", x = 66, y = 0.6 },
        { key = "fly", x = 63, y = 2.5 },
        { key = "fly", x = 68, y = 3.0 },
        { key = "spore", x = 71, y = 0.5 },
        -- 精英怪竞技场（3 种精英）
        { key = "crab", x = 87, y = 0.7 },
        { key = "lightBeast", x = 93, y = 0.6 },
        { key = "manyHands", x = 98, y = 0.8 },
        -- BOSS
        { key = "bossIceFire", x = 126, y = 1.2 },
    },

    crates = {
        { x = 30, y = 0.35, w = 0.9, h = 0.9, hp = 4 },
        { x = 31.2, y = 0.35, w = 0.9, h = 0.9, hp = 4 },
        { x = 80, y = 0.35, w = 0.9, h = 0.9, hp = 4 },
    },

    items = {
        -- 出生区: 全部 7 种鱼（测试装备切换）
        { kind = "fish", fishKey = "archerfish", x = -4, y = 0.5 },
        { kind = "fish", fishKey = "eel", x = -3, y = 0.5 },
        { kind = "fish", fishKey = "flyfish", x = -2, y = 0.5 },
        { kind = "fish", fishKey = "anglerfish", x = -1, y = 0.5 },
        { kind = "fish", fishKey = "ray", x = 0, y = 0.5 },
        { kind = "fish", fishKey = "barnacle", x = 1, y = 0.5 },
        { kind = "fish", fishKey = "frog", x = 2, y = 0.5 },
        { kind = "fish", fishKey = "swordfish", x = 3, y = 0.5 },
        -- 共生碎片与核心
        { kind = "symbShard", x = 4, y = 0.5 },
        { kind = "symbShard", x = 5, y = 0.5 },
        { kind = "symbShard", x = 6, y = 0.5 },
        -- 破碎泉心
        { kind = "brokenQuanxin", x = 7.5, y = 0.5 },
        { kind = "brokenQuanxin", x = 8.5, y = 0.5 },
        -- 贝壳
        { kind = "shell", x = 10, y = 0.5 },
        { kind = "shell", x = 10.8, y = 0.5 },
        { kind = "shell", x = 11.6, y = 0.5 },
        -- 全部 5 种饰品（顶层奖励区）
        { kind = "relic", relicKey = "waterPendant", x = 146, y = 13.8 },
        { kind = "relic", relicKey = "heatCrystal", x = 148, y = 13.8 },
        { kind = "relic", relicKey = "coldShell", x = 150, y = 13.8 },
        { kind = "relic", relicKey = "bulletShard", x = 152, y = 13.8 },
        { kind = "relic", relicKey = "vaporFilm", x = 154, y = 13.8 },
    },

    story = {
        -- 开场用 cutscene（大字弹窗）以便一眼确认已进入测试地图，而非闯关关卡。
        { id = "test_intro", x = 0, y = 1, r = 4, once = true, mode = "cutscene",
          text = "【功能测试场】\n左侧拾取全部鱼类 · 右方依次为形态/机关/小怪/精英/BOSS 测试区" },
        { id = "test_form", x = 16, y = 1, r = 2.5, once = true, mode = "toast",
          text = "形态测试: 碰火冰→液→气 · 进入低温气→液→冰 · 离开后重入再变一级" },
        { id = "test_mech", x = 34, y = 1, r = 2.5, once = true, mode = "toast",
          text = "机关测试: 固态压压板 · 装备电鳗靠近电力接口供电开门" },
        { id = "test_boss", x = 111, y = 1, r = 3, once = true, mode = "toast",
          text = "BOSS 冰火人: 120 血 3 阶段 · 火焰浪潮需气态漂浮 · 冰环降低一级形态" },
    },

    exits = {},
}

return LEVEL
