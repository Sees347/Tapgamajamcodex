-- 上传音频的运行版本；原文件保留在 audio/Music 和 audio/SoundsEffects。
---@class AudioClip
---@field path string
---@field music boolean
---@field gain number
---@field interval number

---@type table<string, AudioClip>
local clips = {
    menu = { path = "audio/runtime/menu.ogg", music = true, gain = 0.38, interval = 0 },
    game = { path = "audio/runtime/game.ogg", music = true, gain = 0.35, interval = 0 },
    click = { path = "audio/runtime/click.wav", music = false, gain = 0.65, interval = 0.06 },
    absorb = { path = "audio/runtime/absorb.wav", music = false, gain = 0.5, interval = 0.22 },
    spring = { path = "audio/runtime/spring.wav", music = false, gain = 0.65, interval = 0.3 },
    waterShot = { path = "audio/runtime/water_shot.wav", music = false, gain = 0.45, interval = 0.07 },
    bulletHit = { path = "audio/runtime/bullet_hit.wav", music = false, gain = 0.55, interval = 0.02 },
    -- 玩家水精灵跳跃或坠落后的首次触地。
    landing = { path = "audio/runtime/landing.wav", music = false, gain = 0.62, interval = 0.1 },
    robotLaser = { path = "audio/runtime/robot_laser.wav", music = false, gain = 0.5, interval = 0.1 },
    -- 位移（Shift 冲刺）：短促的水汽破空声
    dash = { path = "audio/sfx/dash.mp3", music = false, gain = 0.55, interval = 0.08 },
    -- 以下为 2026-10 上传的新音效（runtime 版）
    shoot = { path = "audio/runtime/shoot.wav", music = false, gain = 0.45, interval = 0.06 },
    slash = { path = "audio/runtime/slash.wav", music = false, gain = 0.55, interval = 0.1 },
    enemyHit = { path = "audio/runtime/enemy_hit.wav", music = false, gain = 0.5, interval = 0.06 },
    lightning = { path = "audio/runtime/lightning.wav", music = false, gain = 0.5, interval = 0.15 },
    -- 可破坏箱破碎
    crate = { path = "audio/sfx/crate_break.mp3", music = false, gain = 0.6, interval = 0.08 },
}
return clips
