-- 固态空中逐帧尺寸验收：只用内存存档，所有画面以受控时间采样。
local GS = require "core/state"
local P = require "core/player"
local Art = require "core/art"
local clips = require "data/art"
local Config = require "config"
local R = require "core/render"
local E = require "core/enemies"
local H = require "core/hazards"
local HUD = require "ui/hud"
local ready, checked = false, false
local font = -1

V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    GS.save.equipped = {}
    HUD.hideOverlay()
    E.clear()
    H.clear()
    P.setForm("solid")
    Art.update(1)
    P.body.gravityScale = 0
    P.body.linearVelocity = Vector2(0,0)
    P.onGround = true
    GS.mode = "paused"
end)
V.atFrame(110,function() ready=true end)

local function measure(vg,x,y,ppu)
    local oldSave,oldRestore=nvgSave,nvgRestore
    local oldTranslate,oldScale,oldRect=nvgTranslate,nvgScale,nvgRect
    local tf={sx=1,sy=1,x=0,y=0}
    local stack={}
    local result={w=0,h=0,cx=0,bottom=0,scale=0}
    nvgSave=function(ctx)
        stack[#stack+1]={sx=tf.sx,sy=tf.sy,x=tf.x,y=tf.y}
        oldSave(ctx)
    end
    nvgRestore=function(ctx) tf=table.remove(stack);oldRestore(ctx) end
    nvgTranslate=function(ctx,tx,ty)
        tf.x=tf.x+tx*tf.sx;tf.y=tf.y+ty*tf.sy
        oldTranslate(ctx,tx,ty)
    end
    nvgScale=function(ctx,sx,sy)
        tf.sx=tf.sx*sx;tf.sy=tf.sy*sy
        oldScale(ctx,sx,sy)
    end
    nvgRect=function(ctx,left,top,w,h)
        local key,frame=Art.getPlayback()
        local b=clips[key].frameBounds[frame]
        local x1=tf.x+(left+b[1])*tf.sx
        local x2=tf.x+(left+b[3])*tf.sx
        local y1=tf.y+(top+b[2])*tf.sy
        local y2=tf.y+(top+b[4])*tf.sy
        result={w=math.abs(x2-x1),h=math.abs(y2-y1),cx=(x1+x2)/2-x,bottom=math.max(y1,y2)-y,scale=math.abs(tf.sx)}
        if not checked then V.assert(math.abs(math.abs(tf.sx)-math.abs(tf.sy))<0.00001,"固态空中保持等比缩放") end
        oldRect(ctx,left,top,w,h)
    end
    local ok=Art.drawPlayer(vg,x,y,ppu)
    nvgSave,nvgRestore=oldSave,oldRestore
    nvgTranslate,nvgScale,nvgRect=oldTranslate,oldScale,oldRect
    if not checked then V.assert(ok,"固态实际图集绘制成功") end
    return result
end

SubscribeToEvent("NanoVGRender",function()
    if not ready or not R.vg then return end
    local vg=R.vg
    if font<0 then font=nvgCreateFont(vg,"solid-air-audit","Fonts/MiSans-Regular.ttf") end
    local dpr=graphics:GetDPR()
    local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    nvgBeginFrame(vg,w,h,dpr)
    nvgBeginPath(vg);nvgRect(vg,0,0,w,h)
    nvgFillColor(vg,nvgRGBA(20,25,40,255));nvgFill(vg)
    nvgFontFace(vg,"solid-air-audit");nvgFontSize(vg,16)
    local cw,ch=w/10,h/2
    for row,facing in ipairs({1,-1}) do
        P.form="solid"
        P.facing=facing
        P.onGround=true
        P.body.linearVelocity=Vector2(0,0)
        GS.mode="playing"
        Art.reset()
        local reference={w=0,h=0,cx=0,bottom=0,scale=0}
        local radius=P.bodyShape.radius
        local position=P.node.position2D
        for col=1,10 do
            if col==2 then
                P.onGround=false
                P.body.linearVelocity=Vector2(0,5)
                Art.update(0)
            elseif col>=3 and col<=9 then
                if col>=6 then P.body.linearVelocity=Vector2(0,-5) end
                -- 使用确定时间重新采样，避免累加 1/12 的浮点误差落在前一帧。
                Art.reset()
                Art.update(0)
                Art.update((col-2)/clips.solid_jump.fps+0.000001)
            elseif col==10 then
                -- 长时间坠落保持最后一帧，然后落地。
                Art.update(2)
                if not checked then
                    local key,frame=Art.getPlayback()
                    V.assert(key=="solid_jump" and frame==8,"长时间坠落保持固态末帧")
                end
                P.onGround=true
                P.body.linearVelocity=Vector2(0,0)
                Art.update(0)
            end
            local x,y=(col-0.5)*cw,(row-0.5)*ch+20
            local key,frame=Art.getPlayback()
            nvgFillColor(vg,nvgRGBA(221,232,248,255))
            nvgText(vg,(col-1)*cw+5,(row-1)*ch+18,(facing==1 and "R " or "L ")..(col==1 and "idle" or col==10 and "land" or "air "..tostring(frame)))
            nvgBeginPath(vg);nvgMoveTo(vg,x-65,y+60);nvgLineTo(vg,x+65,y+60)
            nvgStrokeColor(vg,nvgRGBA(80,103,140,200));nvgStrokeWidth(vg,1);nvgStroke(vg)
            local value=measure(vg,x,y,140)
            if col==1 then reference=value
            elseif not checked then
                local areaRatio=value.w*value.h/(reference.w*reference.h)
                V.assert(math.abs(areaRatio-1)<0.00001,"固态各空中帧主体面积匹配待机")
                V.assert(math.abs(value.cx-reference.cx)<0.00001,"固态主体中心无左右偏移")
                V.assert(math.abs(value.bottom-reference.bottom)<0.00001,"固态底边锚点衔接待机")
                if col==2 or col==9 or col==10 then
                    V.assert(math.abs(value.w/reference.w-1)<0.03 and math.abs(value.h/reference.h-1)<0.03,"起跳/坠落/落地主体宽高差小于3%")
                end
                if col>=2 and col<=9 then
                    V.assert(key=="solid_jump" and frame==col-1,"受控上升/下降帧采样正确")
                    local b=clips.solid_jump.frameBounds[frame]
                    local originalRatio=(b[3]-b[1])/(b[4]-b[2])
                    V.assert(math.abs(value.w/value.h-originalRatio)<0.00001,"原有腾空拉伸与压扁比例保留")
                    V.assert(value.scale>reference.scale*1.10,"空中主体放大补偿生效")
                else
                    V.assert(key=="solid_idle","落地恢复固态待机")
                end
            end
        end
        if not checked then
            P.onGround=false
            Art.reset()
            P.body.linearVelocity=Vector2(0,5)
            Art.update(0)
            Art.update(0.36)
            local _, beforeFall=Art.getPlayback()
            P.body.linearVelocity=Vector2(0,-5)
            Art.update(0)
            local _, afterFall=Art.getPlayback()
            V.assert(beforeFall==afterFall,"上升切到下降不重播动画")
            V.assert(P.bodyShape.radius==radius,"动画尺寸补偿不改碰撞半径")
            V.assert(P.node.position2D.x==position.x and P.node.position2D.y==position.y,"绘制锚点不改物理位置")
        end
    end
    GS.mode="paused"
    checked=true
    nvgEndFrame(vg)
end)
V.atFrame(125,function() V.assert(checked,"左右固态空中八帧尺寸实际验收完成") end)
