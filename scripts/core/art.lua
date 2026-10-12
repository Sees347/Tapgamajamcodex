-- ============================================================================
-- core/art.lua - 序列帧美术播放与等比例绘制，独立于物理判定
-- ============================================================================

local clips = require "data/art"
local Config = require "config"
local GS = require "core/state"
local P = require "core/player"

local Art = {}
---@type NVGContextWrapper?
local context = nil
---@type table<string, integer>
local images = {}
---@type integer?
local downloadGroup = nil
local generation = 0
local bound = false
local currentKey = "liquid_idle"
local elapsed = 0.0
local actionKey = ""
local actionTime = 0.0
local transitionFrom = "liquid"
local comboKey = ""
local airborne = false
local pendingElectric = false
local lastFacing = 1
local turnFacing = 1
local turnReversed = false
---@type number[][]
local turnSizes = {}
local turnRestKey = "liquid_idle"
---@type number[]
local handoffSize = { 1.0, 1.0, 0.0, 0.5 }
local handoffTime = 0.0
local loadAttempts = 0
local retryDelay = 0.0

-- 统一使用待机画布的锚点，不逐帧裁剪/缩放，保留动画本身的位移与挤压。
-- 锚点 = 内容包围盒中心 + 内容高度（与 gas/solid 锚点同规则）。
-- liquid 锚点对应 2026-10 重制的 8 帧 idle 图集（1024×512，256/格，内容并集 186×161.25）。
local anchors = {
    liquid = { x = 95.0, y = 82.625, height = 161.25 },
    -- 转身图集共用固定中心与各形态主体高度，不改变碰撞尺寸。
    liquid_turn = { x = 95.0, y = 92.5, height = 137.0 },
    solid_turn = { x = 126.0, y = 126.0, height = 193.0 },
    gas_turn = { x = 126.0, y = 126.0, height = 209.0 },
    -- 移动/跳跃图集的内容在各自格子里偏右下，必须用各自的内容中心做 pivot；
    -- 若沿用待机锚点，内容中心会偏离物理节点约 58px（下）/23px（跳），造成下沉穿模。
    -- height 仍与待机一致，保证缩放与大小相同。
    -- move 的 y 按约定“内容底=碰撞底”取值（213 − height/2），跑动时脚底贴地不浮空。
    liquid_move = { x = 133.0, y = 132.375, height = 161.25 },
    liquid_jump = { x = 119.5, y = 106.0, height = 161.25 },
    solid = { x = 121.5, y = 111.5, height = 193.0 },
    gas = { x = 124.5, y = 137.5, height = 209.0 },
    liquid_flyfish = { x = 121.5, y = 126.0, height = 144.0 },
    liquid_anglerfish = { x = 121.5, y = 163.5, height = 144.0 },
    liquid_anglerfish_off = { x = 121.5, y = 163.5, height = 144.0 },
}

function Art.reset()
    currentKey = P.form .. "_idle"
    elapsed = 0
    actionKey = ""
    actionTime = 0
    comboKey = ""
    airborne = false
    pendingElectric = false
    lastFacing = P.facing
    turnFacing = P.facing
    turnReversed = false
    handoffTime = 0
end

---@param key string
local function play(key)
    if not clips[key] then return end
    currentKey = key
    elapsed = 0
    actionKey = key
    actionTime = 0
    turnReversed = false
    handoffTime = 0
end

---@param key string
---@return boolean
local function isTurn(key)
    return key == "liquid_turn" or key == "solid_turn" or key == "gas_turn"
end

--- 同时装备时按槽位顺序，只决定外观，不改变能力。
---@return string
function Art.getCombo()
    if P.form ~= "liquid" or not GS.save then return "" end
    for _, key in ipairs(GS.save.equipped) do
        if key == "flyfish" or key == "anglerfish" then return "liquid_" .. key end
    end
    return ""
end

--- E 技能只绑定冰电动画；现有周身电流伤害参数保持原样。
---@return boolean
function Art.triggerElectric()
    if GS.mode ~= "playing" or P.dead or P.form ~= "solid" or not GS.save then return false end
    for _, key in ipairs(GS.save.equipped) do
        if key == "eel" then
            if string.find(actionKey, "_to_", 1, true) then
                pendingElectric = true
            elseif actionKey ~= "solid_electric" then
                play("solid_electric")
            end
            return true
        end
    end
    return false
end

-- 只重试失败图集，最多三次；用下载回调补建句柄，不逐帧轮询下载状态。
local function requestImages()
    if not context or downloadGroup or loadAttempts >= 3 then return end
    local paths = {}
    for _, clip in pairs(clips) do
        if not images[clip.path] then paths[#paths + 1] = clip.path end
    end
    if #paths == 0 then return end
    table.sort(paths)
    loadAttempts = loadAttempts + 1
    retryDelay = 0
    local ticket = generation
    local completed = false
    local group = cache:DownloadResources(paths, function(success, failedCount)
        completed = true
        if ticket ~= generation or not context then return end
        downloadGroup = nil
        local missing = 0
        for _, path in ipairs(paths) do
            if cache:Exists(path) then
                local handle = nvgCreateImage(context, path, 0)
                if handle > 0 then images[path] = handle
                else missing = missing + 1 end
            else
                missing = missing + 1
            end
        end
        if missing > 0 and loadAttempts < 3 then
            retryDelay = loadAttempts * 2
            print("[Art] " .. missing .. " 张图集未就绪，将有限重试")
        elseif missing > 0 then
            print("[Art] 图集加载失败: " .. missing .. " 张，保留显示兜底")
        else
            print("[Art] 运行图集加载完成: " .. #paths)
        end
    end)
    -- 本地资源可同步回调，不把已完成的 group 再记回活动任务。
    if not completed then downloadGroup = group end
end

---@param vg NVGContextWrapper
function Art.init(vg)
    Art.shutdown()
    context = vg
    generation = generation + 1
    loadAttempts = 0
    retryDelay = 0
    requestImages()
    if not bound then
        bound = true
        GS.on("formChanged", function(newForm, oldForm)
            transitionFrom = oldForm
            lastFacing = P.facing
            turnFacing = P.facing
            turnReversed = false
            pendingElectric = false
            comboKey = ""
            local key = oldForm .. "_to_" .. newForm
            if clips[key] then play(key) else Art.reset() end
        end)
        GS.on("playerHurt", function(src)
            -- 形态变化优先，避免火伤动画把刚触发的变形覆盖。
            if string.find(actionKey, "_to_", 1, true) then return end
            if P.form == "gas" then play("gas_hurt")
            elseif src == Config.DMG.FIRE then play(P.form .. "_scald") end
        end)
        GS.on("playerAttack", function()
            if P.form == "gas" and (actionKey == "" or isTurn(actionKey)) then play("gas_attack") end
        end)
        GS.on("playerTeleport", Art.reset)
    end
    Art.reset()
end

function Art.shutdown()
    generation = generation + 1
    if downloadGroup then cache:CancelDownloadGroup(downloadGroup) end
    downloadGroup = nil
    retryDelay = 0
    if context then
        for _, image in pairs(images) do nvgDeleteImage(context, image) end
    end
    images = {}
    context = nil
end

function Art.updateLoading(dt)
    if not context or retryDelay <= 0 then return end
    retryDelay = math.max(0, retryDelay - dt)
    if retryDelay == 0 then requestImages() end
end

--- 转身两端匹配实际已显示的姿态，避免待机呼吸/移动挤压切入时突然变大。
---@param key string
---@param time number
---@return number[]
local function liquidSize(key, time)
    local clip = clips[key]
    local anchor = anchors[key] or anchors.liquid
    if not clip or not clip.frameBounds then return { 1.0, 1.0, 0.0, 0.5 } end
    local frame = math.floor(math.max(0, time) * clip.fps)
    local index = clip.loop and frame % clip.count + 1 or math.min(clip.count, frame + 1)
    local bounds = clip.frameBounds[index]
    return { (bounds[3] - bounds[1]) / anchor.height, (bounds[4] - bounds[2]) / anchor.height,
        ((bounds[1] + bounds[3]) / 2 - anchor.x) / anchor.height,
        (bounds[4] - anchor.y) / anchor.height }
end

---@return string
local function liquidRestKey()
    return math.abs(P.body.linearVelocity.x) > 0.25 and "liquid_move" or "liquid_idle"
end

---@param time number
---@return integer
local function liquidTurnFrame(time)
    local clip = clips.liquid_turn
    if turnReversed then
        local frame = math.max(0, math.ceil(time * clip.fps - 0.0000001) - 1)
        return math.max(1, clip.count - frame)
    end
    return math.min(clip.count, math.floor(time * clip.fps + 0.0000001) + 1)
end

---@param key string
---@param time number
---@return number[]
local function liquidRestSize(key, time)
    local target = liquidSize(key, time)
    if handoffTime <= 0 then return target end
    local blend = 1 - handoffTime / 0.10
    blend = blend * blend * (3 - 2 * blend)
    local value = {}
    for i = 1, 4 do value[i] = handoffSize[i] + (target[i] - handoffSize[i]) * blend end
    return value
end

---@param frame integer
local function retargetLiquidTurn(frame)
    local count = clips.liquid_turn.count
    local finish = turnReversed and 1 or count
    local from = turnSizes[frame]
    local target = liquidSize(liquidRestKey(), 0)
    if turnReversed then target[3] = -target[3] end
    local steps = math.abs(finish - frame)
    turnRestKey = liquidRestKey()
    if steps == 0 then return end
    local direction = turnReversed and -1 or 1
    for step = 1, steps do
        local t = step / steps
        t = t * t * (3 - 2 * t)
        local value = {}
        for axis = 1, 4 do value[axis] = from[axis] + (target[axis] - from[axis]) * t end
        turnSizes[frame + step * direction] = value
    end
    turnRestKey = liquidRestKey()
end

---@param dt number
function Art.update(dt)
    if not P.node or P.dead or GS.mode ~= "playing" then return end
    local previousElapsed = elapsed
    local previousTurnFrame = liquidTurnFrame(elapsed)
    elapsed = elapsed + dt
    if handoffTime > 0 then handoffTime = math.max(0, handoffTime - dt) end

    -- 转身只是表现层：P.facing 立即生效，不延迟移动、挥砍或格挡方向。
    -- 水/冰起跳优先；气态悬浮时也可转身。组合外观不能被普通转身替换。
    local canTurn = (P.onGround or P.form == "gas") and Art.getCombo() == ""
    if isTurn(actionKey) and not canTurn then actionKey = "" end
    if P.facing ~= lastFacing then
        lastFacing = P.facing
        if isTurn(actionKey) then
            local clip = clips[actionKey]
            local duration = clip.count / clip.fps
            -- 连续反向从当前画面倒播，保留亚帧时间；边界取帧统一交给 frameAt。
            -- 若先 floor 再重建时间，不等间隔的左右输入会反复丢失进度。
            local oldFrame = actionKey == "liquid_turn" and liquidTurnFrame(elapsed) or 1
            turnReversed = not turnReversed
            elapsed = math.max(0, duration - elapsed)
            actionTime = elapsed
            if actionKey == "liquid_turn" then retargetLiquidTurn(oldFrame) end
        elseif actionKey == "" and canTurn then
            if P.form == "liquid" then
                local from = liquidRestSize(currentKey, previousElapsed)
                from[3] = -from[3]
                local target = liquidSize(liquidRestKey(), 0)
                turnSizes = {}
                for i = 1, clips.liquid_turn.count do
                    local t = (i - 1) / (clips.liquid_turn.count - 1)
                    local value = {}
                    for axis = 1, 4 do value[axis] = from[axis] + (target[axis] - from[axis]) * t end
                    turnSizes[i] = value
                end
                turnRestKey = liquidRestKey()
            end
            turnFacing = P.facing
            play(P.form .. "_turn")
        end
        -- 高优先级动作直接按最新朝向绘制，结束后不补播过时的转身请求。
    end

    if actionKey == "liquid_turn" and turnRestKey ~= liquidRestKey() then
        retargetLiquidTurn(previousTurnFrame)
    end
    if actionKey ~= "" then
        actionTime = elapsed
        local clip = clips[actionKey]
        if clip and actionTime < clip.count / clip.fps then return end
        local finishedLiquidTurn = actionKey == "liquid_turn"
        actionKey = ""
        if finishedLiquidTurn then
            local finish = turnReversed and 1 or clips.liquid_turn.count
            handoffSize = { table.unpack(turnSizes[finish]) }
            if turnReversed then handoffSize[3] = -handoffSize[3] end
            handoffTime = 0.10
            currentKey = liquidRestKey()
            elapsed = 0
        end
        if pendingElectric then
            pendingElectric = false
            if Art.triggerElectric() then return end
        end
    end

    local nextCombo = Art.getCombo()
    if comboKey ~= nextCombo then
        local oldCombo = comboKey
        comboKey = nextCombo
        if oldCombo == "liquid_anglerfish" and nextCombo == "" then
            play("liquid_anglerfish_off")
            return
        end
        if nextCombo ~= "" then
            currentKey = nextCombo
            elapsed = 0
        end
    end
    if comboKey ~= "" then
        if currentKey ~= comboKey then elapsed = 0 end
        currentKey = comboKey
        return
    end

    local velocity = P.body.linearVelocity
    local key = P.form .. "_idle"
    if not P.onGround then
        if P.form == "gas" then key = velocity.y >= 0 and "gas_up" or "gas_down"
        else key = P.form .. "_jump" end
    elseif math.abs(velocity.x) > 0.25 then
        key = P.form .. "_move"
    end
    if key ~= currentKey or (not P.onGround and not airborne) then
        currentKey = key
        elapsed = 0
    end
    airborne = not P.onGround
end

---@param clip ArtClip
---@param time number
---@return integer
local function frameAt(clip, time)
    -- 定格帧：子弹飞行中固定显示一帧，视觉寿命完全由子弹寿命（射程）决定
    if clip.staticFrame then return clip.staticFrame end
    local frame = math.floor(math.max(0, time) * clip.fps)
    -- 播完定格：整段动画播一次，之后一直停在最后一帧（用于"生长完成后保持"）
    if clip.holdLast then return math.min(clip.count, frame + 1) end
    if clip.holdFrom and frame >= clip.count then
        return clip.holdFrom + (frame - clip.count) % (clip.count - clip.holdFrom + 1)
    end
    if clip.loop then return frame % clip.count + 1 end
    return math.min(clip.count, frame + 1)
end

---@param clip ArtClip
---@param time number
---@param key string
---@return integer
local function playbackFrame(clip, time, key)
    if key == "liquid_turn" then return liquidTurnFrame(time) end
    if not isTurn(key) then return frameAt(clip, time) end
    -- 正播 floor、倒播 ceil 使用同一边界，反复反向不消耗/丢弃亚帧时间。
    if turnReversed then
        local frame = math.max(0, math.ceil(time * clip.fps - 0.0000001) - 1)
        return math.max(1, clip.count - frame)
    end
    return math.min(clip.count, math.floor(time * clip.fps + 0.0000001) + 1)
end

--- 绘制单格；图集采样原点反向偏移，不拉伸宽高、不串到相邻帧。
---@param vg NVGContextWrapper
---@param key string
---@param time number
---@param x number
---@param y number
---@param scale number
---@param pivotX number
---@param pivotY number
---@param facing number
---@param frameOffset number|nil 子区间起始帧（一张图集含多段动作时用）
---@return boolean
local function draw(vg, key, time, x, y, scale, pivotX, pivotY, facing, frameOffset)
    local clip = clips[key]
    if not clip then return false end
    local image = images[clip.path]
    if not image then return false end
    local width, height = nvgImageSize(vg, image)
    -- 独立刀光不是四列图集，不能套用 256/格采样；整图按同一比例缩放。
    local cellX, cellY, cellW, cellH = 0, 0, width, height
    if not clip.singleImage then
        local frame = playbackFrame(clip, time, key) - 1
        -- 子区间：一张图集内含多段动作（如裂钳蟹左右螯各 4 帧），按 offset 取段。
        frame = (frameOffset or 0) + frame
        cellX = (frame % 4) * 256 + 2
        cellY = math.floor(frame / 4) * 256 + 2
        cellW, cellH = 252, 252
    end
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgScale(vg, (facing == clip.facing and 1 or -1) * scale, scale)
    local left, top = -pivotX, -pivotY
    nvgBeginPath(vg)
    nvgRect(vg, left, top, cellW, cellH)
    nvgFillPaint(vg, nvgImagePattern(vg, left - cellX, top - cellY, width, height, 0, image, 1))
    nvgFill(vg)
    nvgRestore(vg)
    return true
end

---@return number[]
local function liquidTurnSize()
    return turnSizes[liquidTurnFrame(elapsed)] or liquidSize("liquid_idle", 0)
end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
---@return boolean
function Art.drawPlayer(vg, x, y, ppu)
    local anchor = anchors[P.form]
    local pivotX, pivotY = anchor.x, anchor.y
    local size = Config.FORMS[P.form].radius * 2 * ppu
    local sourceHeight = anchor.height
    local customAnchor = anchors[currentKey]
    if customAnchor then
        pivotX, pivotY = customAnchor.x, customAnchor.y
        sourceHeight = customAnchor.height
    end
    if string.find(currentKey, "_to_", 1, true) then
        local source = anchors[transitionFrom]
        local clip = clips[currentKey]
        local progress = math.min(1, elapsed / (clip.count / clip.fps))
        pivotX = source.x + (anchor.x - source.x) * progress
        pivotY = source.y + (anchor.y - source.y) * progress
        sourceHeight = source.height + (anchor.height - source.height) * progress
        size = (Config.FORMS[transitionFrom].radius * (1 - progress) + Config.FORMS[P.form].radius * progress) * 2 * ppu
    end
    if currentKey == "solid_jump" then
        local clip = clips.solid_jump
        local frame = playbackFrame(clip, elapsed, currentKey)
        local bounds = clip.frameBounds[frame]
        local idleBounds = clips.solid_idle.frameBounds[1]
        local width, height = bounds[3] - bounds[1], bounds[4] - bounds[2]
        local idleWidth, idleHeight = idleBounds[3] - idleBounds[1], idleBounds[4] - idleBounds[2]
        -- 相同主体面积的等比放大：保留腾空拉长、落地压扁，不把每帧硬拉成矩形。
        local compensation = math.sqrt(idleWidth * idleHeight / (width * height))
        local scale = size / anchors.solid.height * compensation
        local centerX = (bounds[1] + bounds[3]) / 2
        local drawnX = x + ((idleBounds[1] + idleBounds[3]) / 2 - anchors.solid.x) * size / anchors.solid.height * P.facing
        local drawnY = y + (idleBounds[4] - anchors.solid.y) * size / anchors.solid.height
        return draw(vg, currentKey, elapsed, drawnX, drawnY, scale, centerX, bounds[4], P.facing)
    end
    -- 鱼组合与普通液态共用主体尺度，灯和鱼鳍不会被压扁。
    local drawFacing = isTurn(currentKey) and turnFacing or P.facing
    local liquidHandoff = handoffTime > 0 and (currentKey == "liquid_idle" or currentKey == "liquid_move")
    if currentKey == "liquid_turn" or liquidHandoff then
        local visual = liquidHandoff and liquidRestSize(currentKey, elapsed) or liquidTurnSize()
        local clip = clips[currentKey]
        local frame = playbackFrame(clip, elapsed, currentKey)
        local bounds = clip.frameBounds[frame]
        local width, height = bounds[3] - bounds[1], bounds[4] - bounds[2]
        local sx, sy = size * visual[1] / width, size * visual[2] / height
        local centerX = (bounds[1] + bounds[3]) / 2
        local drawnX = x + size * visual[3] * drawFacing
        local drawnY = y + size * visual[4]
        nvgSave(vg)
        nvgTranslate(vg, drawnX, drawnY)
        nvgScale(vg, sx, sy)
        local drawn = draw(vg, currentKey, elapsed, 0, 0, 1, centerX, bounds[4], drawFacing)
        nvgRestore(vg)
        return drawn
    end
    return draw(vg, currentKey, elapsed, x, y, size / sourceHeight, pivotX, pivotY, drawFacing)
end

---@param vg NVGContextWrapper
---@param fishKey string
---@param time number
---@param x number
---@param y number
---@param width number
---@param height number
---@param facing number
---@return boolean
function Art.drawFish(vg, fishKey, time, x, y, width, height, facing)
    local key = "fish_" .. fishKey
    local clip = clips[key]
    if not clip then return false end
    local bounds = clip.bounds
    local scale = math.min(width / (bounds[3] - bounds[1]), height / (bounds[4] - bounds[2]))
    return draw(vg, key, time, x, y, scale, (bounds[1] + bounds[3]) / 2, (bounds[2] + bounds[4]) / 2, facing)
end

--- 敌人图集绘制：按包围盒高度定标，底部中心对齐碰撞圆心。
--- 与矢量兜底一致（脚底在 sy + r），受击挤压由调用方在外层做变换。
---@param vg NVGContextWrapper
---@param key string 图集键（如 enemy_spore_idle）
---@param time number
---@param x number
---@param y number 碰撞圆心屏幕坐标
---@param r number 碰撞半径（像素）
---@param facing number
---@param frameOffset number|nil 子区间起始帧（一张图集含多段动作时用）
---@return boolean
function Art.drawEnemy(vg, key, time, x, y, r, facing, frameOffset)
    local clip = clips[key]
    if not clip then return false end
    local bounds = clip.bounds
    if not bounds then return false end
    local bh = bounds[4] - bounds[2]
    -- 底部对齐圆心下方 r，等比缩放：碰撞半径越大画得越大，且不因菌盖宽窄变形。
    local scale = (r * 2) / bh
    local pivotX = (bounds[1] + bounds[3]) / 2
    return draw(vg, key, time, x, y + r, scale, pivotX, bounds[4], facing, frameOffset)
end

--- 子弹/特效图集沿方向旋转，锚点与碰撞圆心对齐。
---@param vg NVGContextWrapper
---@param key string
---@param time number
---@param x number
---@param y number
---@param size number 绘制后最长边的像素长度
---@param angle number
---@return boolean
function Art.drawProjectile(vg, key, time, x, y, size, angle)
    local clip = clips[key]
    if not clip then return false end
    local bounds = clip.bounds
    local pivotX = clip.pivotX or (bounds and (bounds[1] + bounds[3]) / 2) or 128
    local pivotY = clip.pivotY or (bounds and (bounds[2] + bounds[4]) / 2) or 128
    -- sourceWidth 用于横向长条素材（新版水弹）：以宽度为缩放基准，
    -- 使 `size` 表示"绘制后最长边的像素长度"。否则沿用 sourceHeight。
    local source = clip.sourceWidth or clip.sourceHeight or (bounds and (bounds[4] - bounds[2])) or 252
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, angle + (clip.rotation or 0))
    local drawn = draw(vg, key, time, 0, 0, size / source, pivotX, pivotY, clip.facing, clip.frameOffset)
    nvgRestore(vg)
    return drawn
end

---@param key string
---@return number
function Art.duration(key)
    local clip = clips[key]
    return clip and clip.count / clip.fps or 0
end

--- 只认实际播放且已加载的组合，变形途中仍保留跟随鱼。
---@param fishKey string
---@return boolean
function Art.isIntegrated(fishKey)
    local key = "liquid_" .. fishKey
    local clip = clips[key]
    return currentKey == key and clip ~= nil and images[clip.path] ~= nil
end

---@param fishKey string
---@return string|nil
function Art.fishIcon(fishKey)
    local clip = clips["fish_" .. fishKey]
    return clip and clip.icon
end

--- 供运行验收检查当前动画，不影响玩法状态。
---@return string
---@return integer
function Art.getPlayback()
    local clip = clips[currentKey]
    return currentKey, clip and playbackFrame(clip, elapsed, currentKey) or 1
end

return Art
