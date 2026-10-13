-- ============================================================================
-- data/art.lua - 上传美术的运行用图集与独立特效图片
-- 图集单格 256，透明留边 2；singleImage 使用整张图片，不按图集切格。
-- 原始素材保留在 image/PlayerAnim 与 image/FishAnim，不参与运行包。
-- ============================================================================

---@class ArtClip
---@field path string
---@field count integer
---@field fps number
---@field loop boolean
---@field facing number
---@field bounds? number[]    图集内各帧包围盒（用 pivot/source* 定位时可省略）
---@field icon? string
---@field holdFrom? integer
---@field holdLast? boolean     播完停在最后一帧（不循环、不回绕）
---@field pivotX? number
---@field pivotY? number
---@field sourceHeight? number
---@field sourceWidth? number  用宽度作缩放基准（横向长条素材，如新版水弹）
---@field frameBounds? number[][] 各帧主体范围，供液态转身匹配前后姿态大小
---@field rotation? number     原图方向转为朝右所需弧度
---@field staticFrame? integer 固定帧(1起)：不随时间播放。用于飞行中定格的子弹，
---                            视觉寿命=子弹寿命(由射程决定)，不会因动画播完而提前消失
---@field frameOffset? integer 图集子序列起始偏移（从 0 起）
---@field singleImage? boolean 独立图片，整图采样并保留原始宽高比

---@type table<string, ArtClip>
local clips = {
    -- 水弹（2026-10 第二版，9 帧水泡由小变大）：
    -- 快速播完生长过程（高 fps），之后定格在最后一帧（完整水泡）直到命中/消失。
    bullet_water = { path = "image/runtime/bullet_water.png", count = 9, fps = 40, loop = false, holdLast = true, facing = 1, pivotX = 128, pivotY = 128, sourceHeight = 226.8 },
    bullet_electric = { path = "image/runtime/bullet_electric.png", count = 8, fps = 24, loop = true, facing = 1, bounds = { 7, 91, 245, 162 }, pivotX = 209.0342, pivotY = 125.5361, sourceHeight = 50.0989, staticFrame = 1 },
    bullet_ice = { path = "image/runtime/bullet_ice.png", count = 7, fps = 30, loop = true, facing = 1, bounds = { 46, 56, 221, 201 }, pivotX = 129.7474, pivotY = 128.0819, sourceHeight = 74.9488, staticFrame = 2 },
    bullet_ice_hit = { path = "image/runtime/bullet_ice_hit.png", count = 14, fps = 28, loop = false, facing = 1, bounds = { 9, 6, 244, 246 }, pivotX = 129.7474, pivotY = 128.0819, sourceHeight = 74.9488 },
    -- 闪电（2026-10 新版 15 帧，已抠背景）：垂直电弧，向下劈；循环播放覆盖整段射程。
    bullet_lightning = { path = "image/runtime/bullet_lightning.png", count = 15, fps = 22, loop = true, facing = 1, pivotX = 128, pivotY = 128, sourceHeight = 231.8, rotation = -math.pi / 2 },
    -- 固态剑鱼保留原 15 帧刀光和播放节奏。
    slash_swordfish = { path = "image/runtime/slash_swordfish.png", count = 15, fps = 22, loop = false, facing = 1, pivotX = 128, pivotY = 128, sourceHeight = 231.8 },
    -- 刀光003独立图片，按 3 → 4 → 2 用于液态连击；原图弧口朝右，旋转后刃缘朝前。
    -- 使用真实图片尺寸与中心，保持宽高比，挥动/淡出由 melee_fx 控制。
    slash_swordfish_003_3 = { path = "image/runtime/slash_swordfish_003_3.png", count = 1, fps = 1, loop = false, facing = 1, singleImage = true, pivotX = 47, pivotY = 64, sourceHeight = 128, rotation = math.pi },
    slash_swordfish_003_4 = { path = "image/runtime/slash_swordfish_003_4.png", count = 1, fps = 1, loop = false, facing = 1, singleImage = true, pivotX = 25.5, pivotY = 50, sourceHeight = 100, rotation = math.pi },
    slash_swordfish_003_2 = { path = "image/runtime/slash_swordfish_003_2.png", count = 1, fps = 1, loop = false, facing = 1, singleImage = true, pivotX = 48, pivotY = 56, sourceHeight = 112, rotation = math.pi },
    -- 敌人受击特效（20 帧，单次播放）
    enemy_hit = { path = "image/runtime/enemy_hit.png", count = 20, fps = 24, loop = false, facing = 1, pivotX = 128, pivotY = 128, sourceHeight = 167.3 },
    -- 喷孢菌（4 列 × 2 行 = 8 帧，与通用 256/格采样一致）
    enemy_spore_idle = { path = "image/runtime/enemy_spore_idle.png", count = 8, fps = 8, loop = true, facing = 1, bounds = { 2, 23, 254, 233 } },
    enemy_spore_attack = { path = "image/runtime/enemy_spore_attack.png", count = 8, fps = 12, loop = false, facing = 1, bounds = { 2, 22, 254, 233 } },
    -- 清洁机器人-001（逐帧素材；未用待机动画，移动循环 + 攻击单次）
    enemy_cleaner01_move = { path = "image/runtime/enemy_cleaner01_move.png", count = 8, fps = 10, loop = true, facing = 1, bounds = { 2, 157, 254, 253 } },
    enemy_cleaner01_attack = { path = "image/runtime/enemy_cleaner01_attack.png", count = 8, fps = 8, loop = false, facing = 1, bounds = { 5, 158, 251, 253 } },
    -- 清洁机器人-002（逐帧素材；站定射击，待机循环 + 攻击单次）
    enemy_cleaner02_idle = { path = "image/runtime/enemy_cleaner02_idle.png", count = 8, fps = 8, loop = true, facing = 1, bounds = { 14, 112, 242, 253 } },
    enemy_cleaner02_attack = { path = "image/runtime/enemy_cleaner02_attack.png", count = 8, fps = 8, loop = false, facing = 1, bounds = { 2, 116, 254, 253 } },
    -- 趋光菌兽（4 列 × 2 行 = 8 帧；待机/移动循环 + 扑咬单次）
    enemy_lightseeker_idle = { path = "image/runtime/enemy_lightseeker_idle.png", count = 8, fps = 8, loop = true, facing = 1, bounds = { 2, 12, 254, 244 } },
    enemy_lightseeker_move = { path = "image/runtime/enemy_lightseeker_move.png", count = 8, fps = 10, loop = true, facing = 1, bounds = { 8, 17, 247, 239 } },
    enemy_lightseeker_attack = { path = "image/runtime/enemy_lightseeker_attack.png", count = 8, fps = 13, loop = false, facing = 1, bounds = { 6, 15, 250, 241 } },
    -- 飞蝇：4×2 八帧振翅，原图朝左，按移动朝向镜像。
    enemy_fly = { path = "image/runtime/enemy_fly.png", count = 8, fps = 16, loop = true, facing = -1, bounds = { 1, 6, 251, 245 } },
    -- 裂钳蟹：新版近战为完整 4×4 十六帧；远程仍是左右小螯各四帧。
    -- 三套共用身体高度与眼睛横向锚点，真实像素底边落在碰撞圆底部。
    -- 坐标已扣除采样时的 2px 留边，透明画布不参与贴地和体型计算。
    enemy_crab_move = { path = "image/runtime/enemy_crab_move.png", count = 8, fps = 8, loop = true, facing = 1, bounds = { 35, 148, 217, 252 }, pivotX = 126, pivotY = 252, sourceHeight = 101.5 },
    -- 近战原图向左挥钳；远程首组向左抛石，第二组向右（渲染时单独反转）。
    enemy_crab_melee = { path = "image/runtime/enemy_crab_melee.png", count = 16, fps = 24, loop = false, facing = -1, bounds = { 0, 128, 232, 252 }, pivotX = 126, pivotY = 252, sourceHeight = 101.5 },
    enemy_crab_ranged = { path = "image/runtime/enemy_crab_ranged.png", count = 4, fps = 14, loop = false, facing = -1, bounds = { 16, 127, 234, 252 }, pivotX = 126, pivotY = 252, sourceHeight = 101.5 },
    -- 石子（4 帧：大石 → 飞行×2 → 碎裂）。飞行取第 2-3 帧循环（frameOffset=1），
    -- 命中取第 4 帧碎裂（frameOffset=3）。同一张图集，按子区间取用。
    enemy_crab_stone_fly = { path = "image/runtime/enemy_crab_stone.png", count = 2, fps = 14, loop = true, facing = 1, frameOffset = 1, bounds = { 2, 35, 254, 221 } },
    enemy_crab_stone_hit = { path = "image/runtime/enemy_crab_stone.png", count = 1, fps = 1, loop = false, facing = 1, frameOffset = 3, bounds = { 2, 35, 254, 221 } },
    fish_archerfish = { path = "image/runtime/fish_archerfish.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 58, 87, 192, 165 }, icon = "image/runtime/fish_archerfish_icon.png" },
    fish_eel = { path = "image/runtime/fish_eel.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 49, 43, 201, 230 }, icon = "image/runtime/fish_eel_icon.png" },
    fish_flyfish = { path = "image/runtime/fish_flyfish.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 48, 88, 215, 232 }, icon = "image/runtime/fish_flyfish_icon.png" },
    fish_anglerfish = { path = "image/runtime/fish_anglerfish.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 24, 29, 228, 225 }, icon = "image/runtime/fish_anglerfish_icon.png" },
    fish_ray = { path = "image/runtime/fish_ray.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 33, 44, 212, 241 }, icon = "image/runtime/fish_ray_icon.png" },
    fish_swordfish = { path = "image/runtime/fish_swordfish.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 30, 74, 215, 172 }, icon = "image/runtime/fish_swordfish_icon.png" },
    fish_barnacle = { path = "image/runtime/fish_barnacle.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 68, 72, 181, 168 }, icon = "image/runtime/fish_barnacle_icon.png" },
    fish_frog = { path = "image/runtime/fish_frog.png", count = 4, fps = 8, loop = true, facing = -1, bounds = { 69, 61, 192, 180 }, icon = "image/runtime/fish_frog_icon.png" },
    liquid_idle = { path = "image/runtime/liquid_idle.png", count = 8, fps = 8, loop = true, facing = 1, bounds = { 2, 2, 188, 163 }, frameBounds = { {5,24,183,161}, {2,22,186,162}, {0,11,184,161}, {0,2,183,160}, {4,0,177,160}, {8,4,176,160}, {2,15,183,161}, {4,26,184,161} } },
    -- 液态改走背侧：左侧面 → 背侧（无正面五官）→ 右侧面，水彩阴影沿用主角。
    liquid_turn = { path = "image/runtime/liquid_turn.png", count = 8, fps = 32, loop = false, facing = 1, pivotX = 95, pivotY = 92.5, sourceHeight = 137, frameBounds = { {8,24,186,161}, {8,24,185,161}, {8,24,184,161}, {8,24,184,161}, {7,24,183,161}, {7,24,183,161}, {6,24,183,161}, {5,24,183,161} } },
    liquid_move = { path = "image/runtime/liquid_move.png", count = 7, fps = 12, loop = true, facing = 1, bounds = { 10, 66, 252, 213 }, frameBounds = { {26,69,201,204}, {20,82,203,205}, {13,98,216,206}, {26,84,250,208}, {48,76,236,210}, {50,81,231,210}, {50,81,231,210} } },
    liquid_jump = { path = "image/runtime/liquid_jump.png", count = 19, fps = 20, loop = false, facing = 1, bounds = { 7, 2, 228, 206 } },
    liquid_scald = { path = "image/runtime/liquid_scald.png", count = 16, fps = 18, loop = false, facing = 1, bounds = { 1, 9, 249, 206 } },
    liquid_to_solid = { path = "image/runtime/liquid_to_solid.png", count = 8, fps = 16, loop = false, facing = 1, bounds = { 25, 13, 216, 223 } },
    liquid_to_gas = { path = "image/runtime/liquid_to_gas.png", count = 8, fps = 16, loop = false, facing = 1, bounds = { 4, 16, 238, 239 } },
    solid_idle = { path = "image/runtime/solid_idle.png", count = 8, fps = 10, loop = true, facing = 1, bounds = { 32, 15, 211, 208 }, frameBounds = { {35,17,209,206}, {35,17,209,206}, {35,17,209,206}, {35,17,209,205}, {35,17,209,206}, {35,17,209,206}, {35,17,209,206}, {35,17,209,206} } },
    solid_turn = { path = "image/runtime/solid_turn.png", count = 4, fps = 16, loop = false, facing = 1, pivotX = 126, pivotY = 126, sourceHeight = 193.0 },
    solid_move = { path = "image/runtime/solid_move.png", count = 8, fps = 12, loop = true, facing = 1, bounds = { 30, 11, 221, 217 } },
    -- 主体逐帧范围不含透明留白；空中按待机面积等比补偿，保留拉伸/挤压。
    solid_jump = { path = "image/runtime/solid_jump.png", count = 8, fps = 12, loop = false, facing = 1, bounds = { 22, 29, 223, 240 }, frameBounds = { {46,77,198,238}, {46,77,198,238}, {46,68,196,233}, {49,32,192,200}, {49,31,192,199}, {51,51,191,221}, {25,108,220,238}, {46,77,198,238} } },
    solid_scald = { path = "image/runtime/solid_scald.png", count = 8, fps = 12, loop = false, facing = 1, bounds = { 0, 7, 252, 231 } },
    solid_electric = { path = "image/runtime/solid_electric.png", count = 8, fps = 12, loop = false, facing = 1, bounds = { 0, 18, 252, 235 } },
    solid_to_liquid = { path = "image/runtime/solid_to_liquid.png", count = 8, fps = 16, loop = false, facing = 1, bounds = { 23, 12, 218, 222 } },
    solid_to_gas = { path = "image/runtime/solid_to_gas.png", count = 8, fps = 16, loop = false, facing = 1, bounds = { 36, 0, 211, 243 } },
    gas_idle = { path = "image/runtime/gas_idle.png", count = 4, fps = 8, loop = true, facing = 1, bounds = { 19, 33, 230, 242 } },
    gas_turn = { path = "image/runtime/gas_turn.png", count = 5, fps = 20, loop = false, facing = 1, pivotX = 126, pivotY = 126, sourceHeight = 209.0 },
    gas_move = { path = "image/runtime/gas_move.png", count = 8, fps = 12, loop = true, facing = 1, bounds = { 12, 21, 242, 243 } },
    gas_up = { path = "image/runtime/gas_up.png", count = 4, fps = 8, loop = true, facing = 1, bounds = { 8, 36, 245, 246 } },
    gas_down = { path = "image/runtime/gas_down.png", count = 4, fps = 8, loop = true, facing = 1, bounds = { 8, 36, 245, 246 } },
    gas_attack = { path = "image/runtime/gas_attack.png", count = 8, fps = 16, loop = false, facing = 1, bounds = { 18, 39, 252, 235 } },
    gas_hurt = { path = "image/runtime/gas_hurt.png", count = 8, fps = 16, loop = false, facing = 1, bounds = { 16, 0, 238, 243 } },
    gas_to_liquid = { path = "image/runtime/gas_to_liquid.png", count = 8, fps = 16, loop = false, facing = 1, bounds = { 0, 30, 239, 230 } },
    liquid_flyfish = { path = "image/runtime/liquid_flyfish.png", count = 8, fps = 12, loop = true, facing = 1, bounds = { 44, 21, 197, 243 } },
    liquid_anglerfish = { path = "image/runtime/liquid_anglerfish.png", count = 11, fps = 16, loop = true, facing = 1, bounds = { 19, 36, 225, 236 }, holdFrom = 9 },
    liquid_anglerfish_off = { path = "image/runtime/liquid_anglerfish_off.png", count = 6, fps = 16, loop = false, facing = 1, bounds = { 18, 36, 219, 236 } },
}

return clips
