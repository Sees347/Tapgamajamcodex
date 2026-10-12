-- ============================================================================
-- core/audio.lua - BGM 与上传音效播放
-- 独立持有声音场景，避免卸载关卡清除 BGM；一次性音效未就绪时不延迟补播。
-- ============================================================================
local GS = require "core/state"
local Config = require "config"
local PlatformUtils = require "urhox-libs.Platform.PlatformUtils"
local clips = require "data/audio"

local Audio = {}
---@type Scene?
local soundScene = nil
---@type SoundSource?
local musicSource = nil
---@type SoundSource[]
local effectSources = {}
---@type SoundSource[]
local uiSources = {}
---@type table<string, Sound>
local sounds = {}
---@type table<string, number>
local lastPlayed = {}
---@type integer?
local downloadGroup = nil
local generation = 0
local attempts = 0
local retryDelay = 0.0
local clock = 0.0
local initialized = false
local bound = false
-- 待应用的输出缓冲（毫秒）。Web 上音频可能晚于 Audio.init 才就绪，
-- 首次拿不到有效采样率时挂起，等就绪后重试；最多尝试 3 次。
local pendingBufferMs = nil
local bufferAttempts = 0
local bufferRetryDelay = 0.0
local wantedMusic = "menu"
local currentMusic = ""
local musicVolume = 1.0
local effectVolume = 1.0
local modeGain = 1.0

local function refreshMusicGain()
    local clip = clips[currentMusic]
    if musicSource and clip then
        musicSource:SetGain(clip.gain * musicVolume * modeGain)
    end
end

local function startMusic()
    if not initialized or not musicSource or currentMusic == wantedMusic then return end
    local sound = sounds[wantedMusic]
    local clip = clips[wantedMusic]
    if not sound or not clip then return end
    musicSource:StopImmediate()
    musicSource:Play(sound, 0, clip.gain * musicVolume * modeGain)
    currentMusic = wantedMusic
    print("[Audio] BGM: " .. currentMusic)
end

---@param mode string
function Audio.setMode(mode)
    if mode == "menu" then
        wantedMusic = "menu"
        modeGain = 1
    else
        wantedMusic = "game"
        modeGain = mode == "paused" and 0.4 or mode == "dialog" and 0.6 or mode == "dead" and 0.35 or 1
    end
    -- 同一首音乐只调音量，不因暂停、装备、复活或切换关卡重复启动。
    if wantedMusic ~= currentMusic and musicSource then
        musicSource:StopImmediate()
        currentMusic = ""
    end
    startMusic()
    refreshMusicGain()
    if mode ~= "playing" then
        for _, source in ipairs(effectSources) do source:StopImmediate() end
    end
end

local function requestSounds()
    if not initialized or downloadGroup or attempts >= 3 then return end
    local paths = {}
    for key, clip in pairs(clips) do
        if not sounds[key] then paths[#paths + 1] = clip.path end
    end
    if #paths == 0 then return end
    table.sort(paths)
    attempts = attempts + 1
    retryDelay = 0
    local ticket = generation
    local completed = false
    local group = cache:DownloadResources(paths, function()
        completed = true
        if ticket ~= generation or not initialized then return end
        downloadGroup = nil
        local missing = 0
        for key, clip in pairs(clips) do
            if not sounds[key] then
                if cache:Exists(clip.path) then
                    local sound = cache:GetResource("Sound", clip.path)
                    if sound and sound:GetLength() > 0 then
                        sound:SetLooped(clip.music)
                        sounds[key] = sound
                    else
                        missing = missing + 1
                    end
                else
                    missing = missing + 1
                end
            end
        end
        if missing > 0 and attempts < 3 then
            retryDelay = attempts * 2
            print("[Audio] " .. missing .. " 份音频未就绪，将有限重试")
        elseif missing > 0 then
            print("[Audio] 音频加载失败: " .. missing .. " 份；玩法继续运行")
        else
            print("[Audio] 9 份上传音频已就绪")
        end
        -- 只补启动当前需要的 BGM，不播放加载期间已经过时的点击/攻击声音。
        startMusic()
    end)
    if not completed then downloadGroup = group end
end

---@param key string
---@return boolean 是否开始播放
function Audio.playEffect(key)
    if not initialized then return false end
    local clip = clips[key]
    local sound = sounds[key]
    if not clip or clip.music or not sound or effectVolume <= 0 then return false end
    if key ~= "click" and GS.mode ~= "playing" then return false end
    local last = lastPlayed[key]
    if last and clock - last < clip.interval then return false end
    local sources = key == "click" and uiSources or effectSources
    -- 有限声道池：密集弹幕不能无限创建节点，也不抢断已有音效。
    for _, source in ipairs(sources) do
        if not source:IsPlaying() and not source:IsFadingOut() then
            source:Play(sound, 0, clip.gain * effectVolume)
            lastPlayed[key] = clock
            return true
        end
    end
    return false
end

---@param music number 0..1
---@param effects number 0..1
function Audio.setVolumes(music, effects)
    musicVolume = math.max(0, math.min(1, music))
    effectVolume = math.max(0, math.min(1, effects))
    refreshMusicGain()
    -- 调整已播放的一次性音效，下次 Play 仍显式设置采样率和音量。
    for _, sources in ipairs({ effectSources, uiSources }) do
        for _, source in ipairs(sources) do
            local sound = source:GetSound()
            for key, resource in pairs(sounds) do
                if resource == sound and not clips[key].music then
                    source:SetGain(clips[key].gain * effectVolume)
                    break
                end
            end
        end
    end
end

function Audio.getVolumes()
    return musicVolume, effectVolume
end

--- 尝试应用输出缓冲。
--- Web Audio 的输出缓冲/采样率由浏览器托管；引擎在 Web 上调用 Audio:SetMode 会重建
--- 音频设备、破坏 SDL2 音频回调状态，使混音步进（播放频率 / mixRate）除零，
--- 触发 wasm "divide by zero" 崩溃（报错栈落在 scriptProcessorNode.onaudioprocess）。
--- 故 Web 上完全跳过 SetMode，仅桌面/原生平台生效。
---@return boolean 是否已处理完毕（成功或放弃）
local function tryApplyBuffer()
    if not pendingBufferMs or pendingBufferMs <= 0 then return true end
    -- Web：不干预音频设备，直接放弃（保证不崩溃）
    if PlatformUtils.IsWebPlatform() then
        pendingBufferMs = nil
        return true
    end
    bufferAttempts = bufferAttempts + 1

    local ok, mixRate = pcall(function() return audio:GetMixRate() end)
    if not ok or type(mixRate) ~= "number" or mixRate ~= mixRate or mixRate <= 0 then
        -- mixRate 无效（nil / 0 / NaN）：放弃或稍后重试
        if bufferAttempts >= 3 then
            pendingBufferMs = nil
            return true
        end
        bufferRetryDelay = 1.0
        return false
    end

    -- pcall 兜底：即使引擎内部抛错也不让游戏崩溃
    pcall(function()
        audio:SetMode(pendingBufferMs, mixRate, audio.stereo, audio.interpolation)
    end)
    pendingBufferMs = nil
    return true
end

---@param dt number
function Audio.update(dt)
    if not initialized then return end
    clock = clock + dt
    if retryDelay > 0 then
        retryDelay = math.max(0, retryDelay - dt)
        if retryDelay == 0 then requestSounds() end
    end
    -- 输出缓冲重试（Web 上音频晚就绪时）
    if pendingBufferMs then
        bufferRetryDelay = bufferRetryDelay - dt
        if bufferRetryDelay <= 0 then tryApplyBuffer() end
    end
end

function Audio.init()
    if initialized then return end
    generation = generation + 1
    initialized = true
    sounds = {}
    lastPlayed = {}
    attempts = 0
    retryDelay = 0
    clock = 0
    currentMusic = ""
    soundScene = Scene()

    -- 音频输出缓冲：引擎默认约 100ms，会让音效比画面"慢半拍"。
    -- 缩小缓冲降低延迟（Config.AUDIO.bufferMs）。
    -- 注意：Web(WASM) 上 GetMixRate() 可能返回 0，直接把 0 传给 SetMode 会让
    -- 混音步进（频率 / mixRate）除零崩溃。因此仅在采样率有效时才设置；
    -- 无效时挂起重试（见 Audio.update），绝不把 0/NaN 传给引擎。
    pendingBufferMs = (Config.AUDIO and Config.AUDIO.bufferMs) or nil
    bufferAttempts = 0
    bufferRetryDelay = 0.0
    tryApplyBuffer()

    musicSource = soundScene:CreateChild("Music"):CreateComponent("SoundSource")
    musicSource:SetSoundType(SOUND_MUSIC)
    effectSources = {}
    uiSources = {}
    for i = 1, 10 do
        local source = soundScene:CreateChild("Effect" .. i):CreateComponent("SoundSource")
        source:SetSoundType(SOUND_EFFECT)
        effectSources[#effectSources + 1] = source
    end
    for i = 1, 2 do
        local source = soundScene:CreateChild("UIClick" .. i):CreateComponent("SoundSource")
        source:SetSoundType(SOUND_EFFECT)
        uiSources[#uiSources + 1] = source
    end
    if not bound then
        bound = true
        GS.on("sfx", function(key) Audio.playEffect(key) end)
        GS.on("modeChanged", function(mode) Audio.setMode(mode) end)
    end
    Audio.setMode(GS.mode)
    requestSounds()
end

function Audio.shutdown()
    initialized = false
    generation = generation + 1
    if downloadGroup then cache:CancelDownloadGroup(downloadGroup) end
    downloadGroup = nil
    if musicSource then musicSource:StopImmediate() end
    for _, sources in ipairs({ effectSources, uiSources }) do
        for _, source in ipairs(sources) do source:StopImmediate() end
    end
    if soundScene then soundScene:Dispose() end
    soundScene = nil
    musicSource = nil
    effectSources = {}
    uiSources = {}
    sounds = {}
    lastPlayed = {}
    currentMusic = ""
    pendingBufferMs = nil
    bufferAttempts = 0
    bufferRetryDelay = 0.0
end

-- 验收读取接口，不暴露声音场景的所有权。
function Audio.getMusicState()
    return wantedMusic, currentMusic, musicSource
end

---@param key string
---@return Sound?
function Audio.getSound(key)
    return sounds[key]
end

return Audio
