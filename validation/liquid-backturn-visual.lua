-- 受控多帧：两向、待机呼吸和移动挤压的切入/切出；测量实际绘制变换。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local R = require "core/render"
local E = require "core/enemies"
local H = require "core/hazards"
local HUD = require "ui/hud"
local ready, checked = false, false
local font = -1
local cases = {
    { facing = 1, moving = false, time = 0, name = "idle R" },
    { facing = -1, moving = false, time = 0.5, name = "breath L" },
    { facing = 1, moving = true, time = 0, name = "move R" },
    { facing = -1, moving = true, time = 0.25, name = "squash L" },
}
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    E.clear()
    H.clear()
    HUD.hideOverlay()
    P.body.gravityScale = 0
    P.onGround = true
    GS.mode = "paused"
end)
V.atFrame(110, function() ready = true end)

local function measure(vg, x, y)
    local oldSave, oldRestore = nvgSave, nvgRestore
    local oldTranslate, oldScale, oldRect = nvgTranslate, nvgScale, nvgRect
    local transform = { sx=1, sy=1, x=0, y=0 }
    local stack = {}
    local result = {}
    nvgSave = function(ctx)
        stack[#stack+1] = { sx=transform.sx, sy=transform.sy, x=transform.x, y=transform.y }
        oldSave(ctx)
    end
    nvgRestore = function(ctx) transform = table.remove(stack); oldRestore(ctx) end
    nvgTranslate = function(ctx, tx, ty)
        transform.x = transform.x + tx * transform.sx
        transform.y = transform.y + ty * transform.sy
        oldTranslate(ctx, tx, ty)
    end
    nvgScale = function(ctx, sx, sy)
        transform.sx = transform.sx * sx
        transform.sy = transform.sy * sy
        oldScale(ctx, sx, sy)
    end
    nvgRect = function(ctx, left, top, w, h)
        local key, frame = Art.getPlayback()
        local b = clips[key].frameBounds[frame]
        local x1 = transform.x + (left+b[1]) * transform.sx
        local x2 = transform.x + (left+b[3]) * transform.sx
        local y1 = transform.y + (top+b[2]) * transform.sy
        local y2 = transform.y + (top+b[4]) * transform.sy
        result = { w=math.abs(x2-x1), h=math.abs(y2-y1), cx=(x1+x2)/2-x, bottom=math.max(y1,y2)-y }
        oldRect(ctx, left, top, w, h)
    end
    local drawn = Art.drawPlayer(vg,x,y,120)
    nvgSave, nvgRestore = oldSave, oldRestore
    nvgTranslate, nvgScale, nvgRect = oldTranslate, oldScale, oldRect
    if not checked then V.assert(drawn, "真实液态图集绘制") end
    return result
end
local function same(a,b,label)
    for _, field in ipairs({"w","h","cx","bottom"}) do
        V.assert(math.abs(a[field]-b[field]) < 0.001,label .. " " .. field)
    end
end
SubscribeToEvent("NanoVGRender", function()
    if not ready or not R.vg then return end
    local vg = R.vg
    if font < 0 then font = nvgCreateFont(vg,"liquid-back-audit","Fonts/MiSans-Regular.ttf") end
    local dpr=graphics:GetDPR()
    local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    nvgBeginFrame(vg,w,h,dpr)
    nvgBeginPath(vg)
    nvgRect(vg,0,0,w,h)
    nvgFillColor(vg,nvgRGBA(20,25,40,255))
    nvgFill(vg)
    nvgFontFace(vg,"liquid-back-audit")
    nvgFontSize(vg,15)
    local cw,ch=w/10,h/4
    for row,c in ipairs(cases) do
        P.form="liquid"
        P.onGround=true
        P.body.linearVelocity=Vector2(c.moving and 3 or 0,0)
        P.facing=-c.facing
        GS.mode="playing"
        Art.reset()
        Art.update(0)
        Art.update(c.time)
        local before, first, last
        for col=1,10 do
            if col==2 then P.facing=c.facing; Art.update(0)
            elseif col>=3 and col<=9 then Art.update(1/clips.liquid_turn.fps)
            elseif col==10 then Art.update(1/clips.liquid_turn.fps+0.00001) end
            local x,y=(col-0.5)*cw,(row-0.5)*ch
            local key,frame=Art.getPlayback()
            nvgFillColor(vg,nvgRGBA(210,224,244,255))
            nvgText(vg,(col-1)*cw+5,(row-1)*ch+10,c.name .. " " .. (col==1 and "before" or col==10 and "after" or tostring(frame)))
            local measured=measure(vg,x,y)
            if col==1 then before=measured
            elseif col==2 then first=measured
            elseif col==9 then last=measured
            elseif col==10 and not checked then
                same(before,first,c.name .. "切入转身尺寸/锚点不跳变")
                same(last,measured,c.name .. "转身收尾尺寸/锚点不跳变")
                V.assert(key==(c.moving and "liquid_move" or "liquid_idle"),c.name .. "恢复原有姿态")
            end
        end
    end
    if not checked then
        local function start(moving, time)
            P.body.linearVelocity=Vector2(moving and 3 or 0,0)
            P.facing=1
            Art.reset()
            Art.update(0)
            Art.update(time)
            P.facing=-1
            Art.update(0)
        end
        start(false,0.5)
        local a=measure(vg,100,100)
        P.facing=1
        Art.update(1/60)
        local b=measure(vg,100,100)
        same(a,b,"呼吸高帧立刻反向不跳变")
        for i=1,8 do
            local before=measure(vg,100,100)
            P.facing=-P.facing
            Art.update(1/60)
            local after=measure(vg,100,100)
            same(before,after,"同一首帧交替反向不跳变")
        end
        start(false,0.5)
        local beforeCombined=measure(vg,100,100)
        P.facing=1
        P.body.linearVelocity=Vector2(3,0)
        Art.update(1/60)
        local afterCombined=measure(vg,100,100)
        same(beforeCombined,afterCombined,"首帧快速反向与起步同帧不跳变")
        start(true,0)
        Art.update(0.225)
        a=measure(vg,100,100)
        P.body.linearVelocity=Vector2(0,0)
        Art.update(1/120)
        b=measure(vg,100,100)
        same(a,b,"末帧刹停不跳变")
        P.facing=1
        Art.update(0)
        local c=measure(vg,100,100)
        same(b,c,"末帧刹停后反向不撤回尺寸衔接")
        Art.update(0.5)
        a=measure(vg,100,100)
        Art.update(0)
        b=measure(vg,100,100)
        same(a,b,"倒播完成移交普通姿态不跳变")
        start(false,0)
        Art.update(0.225)
        a=measure(vg,100,100)
        P.body.linearVelocity=Vector2(3,0)
        Art.update(1/120)
        b=measure(vg,100,100)
        same(a,b,"末帧起步不跳变")
        Art.update(0.03)
        c=measure(vg,100,100)
        same(b,c,"末帧起步移交移动不跳变")
        Art.update(0.10)
        V.assert(Art.getPlayback()=="liquid_move","平滑移交后继续移动动画")
    end
    GS.mode="paused"
    checked=true
    nvgEndFrame(vg)
end)
V.atFrame(125,function() V.assert(checked,"背侧转向全八帧实际渲染完成") end)
