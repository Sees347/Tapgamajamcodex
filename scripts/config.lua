-- ============================================================================
-- config.lua - 《涌泉》全局配置常量
-- ============================================================================

local Config = {}

-- 物理/世界
Config.GRAVITY = 22              -- 重力加速度 (m/s^2)
Config.VIEW_H = 18.5             -- 相机视野高度 (米)（拉远相机：拍摄更大区域，角色/怪物在屏幕上更小）
Config.DEATH_Y = -5.0            -- 坠落死亡线 (相对关卡 y=0, 具体见关卡数据 deathY)

-- 玩家形态参数（三形态手感）
Config.FORMS = {
    liquid = {
        name = "液态", radius = 0.42, density = 1.0,
        speed = 10, accelGround = 14.0, accelAir = 10.0, decel = 16.0,
        jumpVel = 12.4, gravUp = 1.0, gravDown = 1.15, damping = 0.0,
        color = { 80, 170, 255 },
    },
    gas = {
        name = "气态", radius = 0.5, density = 0.25,
        speed = 8, accelGround = 8.0, accelAir = 7.0, decel = 4.0,
        jumpVel = 13.3203, gravUp = 0.5, gravDown = 0.75, damping = 0.9,
        color = { 225, 235, 245 },
    },
    solid = {
        name = "固态", radius = 0.4, density = 3.0,
        speed = 11.2, accelGround = 3.2, accelAir = 2.5, decel = 0.9,  -- 打滑：低加/减速度
        jumpVel = 8.5, gravUp = 1.25, gravDown = 1.4, damping = 0.0,
        color = { 150, 220, 255 },
    },
}

-- 玩家通用参数
Config.PLAYER = {
    initWater = 3,               -- 初始水量
    maxWaterBase = 12,           -- 水量上限基准
    hurtInvuln = 1.2,            -- 受击无敌时间 (秒)
    jumpBufferTime = 0.12,       -- 跳跃输入缓冲
    coyoteTime = 0.10,           -- 土狼时间
    ramSpeed = 6.0,              -- 固态撞击最低速度
    ramDamage = 3,               -- 固态撞击伤害
    baseAtk = 2,                 -- 无装备基础弹幕伤害
    baseAtkRange = 7,            -- 基础弹幕射程 (米)
    baseAtkFreq = 0.35,          -- 基础弹幕频率 (秒/发)
    baseBulletSpeed = 18.5,      -- 弹幕速度 (米/秒)
    flyFlap = 14.5,              -- 飞鱼气态：空中每次点按空格的扇动上升速度 (米/秒)
    flyDamping = 0.975,          -- 飞鱼气态：未扇动时上升速度每帧衰减（越接近1越飘、飞得越远）
    -- 可变跳跃高度（经典 2D 平台手感）：按住跳跃键越久跳得越高。
    -- 松开时若仍在上升，把上升速度乘以该值。
    -- 调小则点按跳得更矮；实际高度取决于形态、重力和松手时机。
    jumpCutMul = 0.38,
    -- 达到该上升时长后视为"满跳"，再按住也不会更高（防止无限飘）。
    jumpHoldMaxTime = 0.5,
}

-- 青蛙液态钩爪：发射绳状水柱，命中地形后把玩家拉过去（泰拉瑞亚风格）。
Config.GRAPPLE = {
    maxLength = 9.0,             -- 最大绳长 (米)
    pullSpeed = 16.0,            -- 拉拽速度 (米/秒)
}

-- 命中时停（hitstop）：击中敌人瞬间短暂冻结画面，增强打击感
Config.HITSTOP = {
    enabled = true,
    duration = 0.055,            -- 每次命中的冻结时长（秒）
    bossDuration = 0.09,         -- 命中 BOSS/精英时更长的冻结
    minInterval = 0.06,          -- 两次时停之间的最小间隔（防止连发时持续卡顿）
}

-- 敌人受击反馈
Config.HIT_FX = {
    flashTime = 0.14,            -- 受击变白持续时间（秒）
    squashTime = 0.16,           -- 受击缩放持续时间（秒）
    squashAmount = 0.42,         -- 缩放幅度（受击瞬间压扁到 1-该值）
    bloodCount = 14,             -- 每次受击飞溅的颗粒数
    bloodSpeed = 5.5,            -- 颗粒初速 (米/秒)
    bloodLife = 0.55,            -- 颗粒寿命 (秒)
    bloodColor = { 210, 60, 70 },-- 血液颜色（偏红）
    hpBarAlwaysShow = true,      -- 所有敌人是否常驻血条（false=仅受伤后显示）
    hpBarShowTime = 3.0,         -- 受伤后血条显示时长（hpBarAlwaysShow=false 时生效）
    attackAnimTime = 0.45,       -- 攻击动画时长（秒）：出手后按此时长播放攻击图集
    meleeHitAt = 0.5,            -- 近战命中帧：动画播放到该比例时结算伤害（0.5 = 挥到一半）
    rangedFireAt = 0.9,          -- 远程出手帧：动画播放到该比例时发射弹幕（0.9 ≈ 挥臂末端）
}

-- 手感反馈（镜头抖动等）
Config.FEEL = {
    -- 抖动幅度换算：实际像素 = 强度 × ppu × shakeScale。
    -- 调大这个值 → 所有抖动整体更明显（面板可实时调）。
    shakeScale = 0.6,
    -- 可破坏箱破碎时的镜头抖动强度
    crateShake = 0.5,
    -- 击杀镜头抖动：tier -> { 强度, 时长(秒) }
    killShake = {
        small = { 1, 0.2 },
        elite = { 1, 0.25 },
        boss  = { 1.6, 0.6 },
    },
}

-- 剑鱼近战刀光特效
Config.MELEE_FX = {
    -- 刀光绘制尺寸 = 近战射程 × ppu × 此系数（越大越显眼）。
    sizeMul = 0.85,
    -- 刀光沿攻击方向前移的距离 = 近战射程 × 此系数（0.5=出现在身前半程处）。
    forwardOffset = 0.6,
    -- 挥砍僵直：挥砍瞬间锁死水平移动的时长（秒）。
    swingLock = 0.14,
}

-- 液态剑鱼三段点按连击：003/3 → 003/4 → 003/2，第三段延长收招。
-- intervalMul 乘液态剑鱼 freq；独立刀光在 fxDuration 内挥出并淡出，不影响固态。
Config.LIQUID_MELEE = {
    chainWindow = 0.32,          -- 收招后允许续段的时间（秒）
    stages = {
        { artKey = "slash_swordfish_003_3", intervalMul = 1.0, fxDuration = 0.19, swingLock = 0.14, sizeMul = 0.9, tilt = -0.24, sweep = 0.48, flipY = false },
        { artKey = "slash_swordfish_003_4", intervalMul = 1.15, fxDuration = 0.22, swingLock = 0.17, sizeMul = 1.0, tilt = 0.24, sweep = -0.48, flipY = true },
        { artKey = "slash_swordfish_003_2", intervalMul = 1.75, fxDuration = 0.30, swingLock = 0.24, sizeMul = 1.2, tilt = 0, sweep = 0.32, flipY = false },
    },
}

-- 剑鱼固态格挡：面朝攻击来源时减免受到的敌人伤害。
Config.BLOCK = {
    reduce = 0.7,                -- 格挡成功时减免比例（0.7 = 只受 30% 伤害）
    facingDot = 0.3,             -- 朝向判定阈值（越大越要求正对）
}

-- 飞鱼气态冲刺：空中点按跳跃触发的短促位移，可连按连续冲刺（替代原自由飞行）。
-- 与 Shift 位移不同：不无敌（纯机动），有独立冷却，落地后重置。
Config.FLYDASH = {
    distance = 3.0,              -- 每次冲刺距离 (米)
    duration = 0.18,             -- 单次冲刺持续 (秒)
    cooldown = 0.22,             -- 冲刺间隔 (秒，连按可连续冲)
}

-- 位移（Shift 冲刺 / 手机端「闪」按钮）
-- 液态/固态只能在落地时位移；气态可在空中位移。
-- 位移期间完全无敌（躲子弹/近战/火焰/陷阱），不穿墙（撞墙即停），可穿过小怪。
Config.DASH = {
    distance = 3.5,              -- 位移距离 (米)
    duration = 0.25,             -- 位移持续时间 (秒)
    cooldown = 0.5,              -- 冷却时间 (秒)
    airForms = { gas = true },   -- 允许空中位移的形态
    endSpeedKeep = 0.35,         -- 位移结束后保留的水平速度比例
    trailInterval = 0.03,        -- 残影生成间隔 (秒)
}

-- 水量上限/共生槽
Config.HEART_PER_QQUANXIN = 2    -- 每个泉心提升水量上限 +2
Config.SLOT_BASE = 2             -- 初始共生槽数量
Config.FRAGMENT_PER_CORE = 3     -- 3 碎片合成 1 核心
Config.PIECE_PER_QUANXIN = 3     -- 3 破碎泉心合成 1 泉心

-- ============================================================================
-- 弹幕/子弹（原硬编码于 core/bullets.lua、core/abilities.lua）
-- ============================================================================
Config.BULLETS = {
    playerRadius = 0.14,         -- 玩家弹丸碰撞半径 (米)
    iceRadius = 0.18,            -- 冰锥弹半径 (米)
    -- 水弹绘制尺寸系数（相对碰撞直径 2r 的倍数）。
    -- 新版素材是正常圆形水泡，用较小的倍数即可；调大则水泡更大。
    waterArtSizeMul = 4.5,
    -- 闪电素材绘制尺寸系数（相对碰撞直径 2r 的倍数）；原尺寸过小。
    lightningArtSizeMul = 6.0,
    enemyRadius = 0.16,          -- 敌方弹丸半径 (米)
    enemyRange = 14.0,           -- 敌方弹丸射程 (米)
    trailMax = 6,                -- 尾迹保留点数
    homingRange = 5.0,           -- 追踪弹索敌半径 (米)
    homingTurn = 5.0,            -- 追踪转向强度 (越大越急)
    bounceKeep = 0.9,            -- 反弹后速度保留比例
}

-- ============================================================================
-- 能力（原硬编码于 core/abilities.lua）
-- ============================================================================
Config.ABILITIES = {
    orbitRadius = 1.2,           -- 电鳗液态环绕电场半径 (米)
    orbitRadiusY = 0.6,          -- 环绕电场纵向压扁比例
    orbitSpeed = 4.0,            -- 环绕角速度
    orbitHitRange = 1.5,         -- 环绕电场命中判定半径 (米，实际判定=此值+敌人半径)
    recoilBoost = 9.0,           -- 射水鱼气态猛击反冲力
    recoilVertical = 0.6,        -- 反冲纵向比例
    selfZapRange = 0.9,          -- 电鳗固态周身电流半径 (米)
    downLightningSpeedMul = 0.45,-- 电鳗气态向下闪电弹速倍率（放慢→闪电可见更长）
}

-- ============================================================================
-- 装备组合效果（同时装备特定鱼时触发的额外加成）
-- ============================================================================
Config.COMBO = {
    -- 气态 + 同时携带飞鱼与电鳗：空中横移速度加成（比例，仅空中生效）
    gasFlyEelAirSpeed = 3,
}

-- ============================================================================
-- BOSS（原硬编码于 core/enemies.lua）
-- ============================================================================
Config.BOSS = {
    phaseP2 = 80,                -- 进入 P2 的血量阈值
    phaseP3 = 40,                -- 进入 P3 的血量阈值
}

-- ============================================================================
-- 全局平衡倍率（便于整体调难度；面板可实时改）
-- 这些倍率在“消费点”生效：怪物血量在生成时、玩家伤害在发射时、
-- 怪物伤害在攻击时、掉落数量在击杀时。
-- ============================================================================
Config.BALANCE = {
    monsterHp = 1.0,             -- 全体怪物血量倍率
    monsterDmg = 1.0,            -- 全体怪物伤害倍率
    playerDmg = 1.0,             -- 玩家弹幕伤害倍率
    bulletRange = 1.8,           -- 玩家弹幕射程倍率（作用于所有弹幕，含各鱼）
    dropRate = 1.0,              -- 贝壳掉落数量倍率
}

-- ============================================================================
-- 经济/掉落（原硬编码于 core/state.lua、core/enemies.lua、main.lua）
-- ============================================================================
Config.ECONOMY = {
    shellDropSmall = 4,          -- 小怪掉落贝壳数
    shellDropElite = 12,         -- 精英怪掉落贝壳数
    shellDropBoss = 60,          -- BOSS 掉落贝壳数
    shellDropPiles = 6,          -- 掉落贝壳堆数上限
    pickupShellValue = 5,        -- 场景拾取贝壳值 (main itemPickup)
    dropShellValue = 3,          -- 击杀掉落单个贝壳值 (render 磁吸拾取)
    bossRewardShells = 40,       -- 击败 BOSS 的固定贝壳奖励 (main enemyKilled)
    dupeFishShells = 10,         -- 重复获得鱼转化贝壳数
    absorbAmount = 3,            -- 吸收凝珠回水量（3 格血量）
    absorbInterval = 0.25,       -- 吸收 tick 间隔 (秒)
    waterPendantBonus = 0.5,     -- 凝水坠饰吸收加成
}

-- 碰撞分组位
Config.COL = {
    TERRAIN = 1,     -- 地形/平台/墙
    PLAYER = 2,      -- 玩家本体
    FOOT = 4,        -- 玩家脚底传感器
    ENEMY = 8,       -- 敌人本体
    HEAVY = 16,      -- 重物（压板可被固态/重物触发，用触发器区域检测）
}

-- 调色板（暗色实验室基调）
Config.PAL = {
    bgTop = { 12, 16, 28 },
    bgBottom = { 24, 30, 48 },
    platform = { 58, 66, 88 },
    platformTop = { 86, 98, 126 },
    platformEdge = { 34, 40, 56 },
    ice = { 150, 210, 245 },
    scorch = { 40, 30, 30 },
    text = { 230, 238, 250 },
    textDim = { 150, 162, 185 },
    water = { 90, 180, 255 },
    fire = { 255, 140, 50 },
    shell = { 250, 220, 160 },
    hp = { 110, 200, 255 },
    hpEmpty = { 40, 52, 74 },
    bossFire = { 255, 110, 60 },
    bossIce = { 120, 200, 255 },
}

-- 伤害来源标记
Config.DMG = {
    FIRE = "fire",
    COLD = "cold",
    ENEMY = "enemy",
    TRAP = "trap",
    BOSS = "boss",
}

-- ============================================================================
-- 音频
-- ============================================================================
Config.AUDIO = {
    -- 音频输出缓冲（毫秒）。引擎默认约 100ms，会让音效比画面"慢半拍"。
    -- 调小 → 音效更跟手；太小可能爆音/卡顿。0 或 nil = 不改引擎默认。
    -- ⚠️ 仅桌面/原生平台生效；Web(WASM) 上由浏览器托管音频设备，
    --    代码会跳过此项以避免引擎音频回调除零崩溃（见 core/audio.lua）。
    bufferMs = 45,
}

-- ============================================================================
-- 怪物数值表（唯一数据源；身份/颜色/AI 类型仍在 data/monsters.lua，数值合并自此）
-- 字段: hp 血量 / speed 移速 / detectRange 感知半径 / radius 碰撞半径
--       attacks[] 攻击组: range 攻击距离(米) / dmg 伤害 / freq 攻击频率(秒/次)
-- 注: dmg 会再乘 Config.BALANCE.monsterDmg，hp 会再乘 Config.BALANCE.monsterHp
-- ============================================================================
Config.MONSTER_STATS = {
    cleaner01 = {
        hp = 35, speed = 2.2, detectRange = 6.0, radius = 0.45,
        atkAnimTime = 1.0,   -- 挥动一遍耗时；与 freq 对齐则每秒挥动一次
        attacks = { { range = 1, dmg = 1, freq = 1.0 } },
    },
    cleaner02 = {
        hp = 20, speed = 0.0, detectRange = 7.0, radius = 0.4,
        atkAnimTime = 1.0,   -- 挥臂一遍耗时；与 freq 对齐则每秒挥动一次
        attacks = { { range = 3, dmg = 1, freq = 1.0 } },
    },
    fly = {
        hp = 15, speed = 3.4, detectRange = 7.5, radius = 0.3,
        attacks = { { range = 2, dmg = 1, freq = 1.0 } },
    },
    lightBeast = {
        hp = 50, speed = 2.8, detectRange = 8.0, radius = 0.55,
        atkAnimTime = 0.6,   -- 单次扑咬耗时（两次扑咬之间约 0.6s）
        attacks = { { range = 1, dmg = 1, freq = 1.2 } },
    },
    spore = {
        hp = 18, speed = 0.0, detectRange = 8.0, radius = 0.38,
        atkAnimTime = 0.45,
        attacks = { { range = 3, dmg = 1, freq = 2.0 } },
    },
    crab = {
        hp = 57, speed = 1.6, detectRange = 7.0, radius = 0.6,
        atkAnimTime = 0.28,   -- 单次砸击/抛石动画时长（4 帧 × 14fps）
        attacks = { { range = 1, dmg = 1, freq = 1.5 }, { range = 3, dmg = 1, freq = 1.5 } },
    },
    manyHands = {
        hp = 65, speed = 2.4, detectRange = 8.5, radius = 0.7,
        attacks = { { range = 4, dmg = 1, freq = 1.2 }, { range = 1.4, dmg = 1, freq = 1.2 } },
    },
    bossIceFire = {
        hp = 120, speed = 3.0, detectRange = 20.0, radius = 1.1,
        attacks = { { range = 9, dmg = 1, freq = 2.0 }, { range = 6, dmg = 2, freq = 5.0 }, { range = 12, dmg = 1, freq = 3.0 } },
    },
}

-- ============================================================================
-- 鱼类装备数值表（唯一数据源；身份/颜色/描述仍在 data/fish.lua，数值合并自此）
-- 每种鱼按形态 liquid/gas/solid 给出该形态的效果数值。
-- 字段沿用 FishFormEffect：range 射程 / dmg 伤害 / freq 频率(秒/发) / 各特效数值。
-- ============================================================================
Config.FISH_STATS = {
    archerfish = {
        liquid = { range = 3, dir = "mouse", dmg = 5, freq = 0.5 },
        gas    = { range = 3, dir = "mouse", dmg = 10, freq = 1.0, recoil = true },
        solid  = { range = 3, dir = "mouse", dmg = 15, freq = 1.0, slow = 0.4 },
    },
    eel = {
        liquid = { range = 1, dir = "orbit", dmg = 6, freq = 0.5, paralysis = 0.5 },
        gas    = { range = 4, dir = "down", dmg = 4, freq = 0.5 },
        solid  = { range = 0, dir = "self", dmg = 8, freq = 0.5 },
    },
    flyfish = {
        liquid = { glide = true },
        gas    = { dash = true },
        solid  = { speedUp = 0.4, ramDmg = 12 },
    },
    anglerfish = {
        liquid = { lightRange = 3.0, dir = "mouse", dmg = 4, freq = 0.6, range = 6 },
        gas    = { dir = "homing", dmg = 5, freq = 0.5, range = 7 },
        solid  = { blindRange = 3.5, blindDur = 1.0 },
    },
    ray = {
        liquid = { dir = "mouse", dmg = 3, freq = 0.5, range = 5, poisonDps = 3 },
        gas    = { speedUp = 0.3 },
        solid  = {},
    },
    barnacle = {
        liquid = { stickMax = 4, stickDur = 3.0 },
        gas    = { hoverDur = 3.0 },
        solid  = { bounceMax = 2 },
    },
    frog = {
        liquid = { grapple = true },
        gas    = {},
        solid  = { doubleJump = true },
    },
    swordfish = {
        -- 近战范围适当放大，避免"贴不到敌人像没攻击"
        liquid = { melee = true, range = 2.4, dmg = 6, freq = 0.35 },
        gas    = { range = 3, dir = "mouse", dmg = 4, freq = 0.8, burst = 3 },
        solid  = { melee = true, range = 2.6, dmg = 12, freq = 0.6, block = true },
    },
}

return Config
