"""Run real Lua enemy AI with engine boundaries stubbed; no preview/build."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.tmp/lua-test-deps'))
from lupa.lua54 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = " + repr((ROOT / 'scripts/?.lua').as_posix() + ';') + " .. package.path")
lua.execute(r'''
Vector2 = function(x, y) return { x=x, y=y } end
local events, shots = {}, {}
package.loaded['core/state'] = { on=function() end, emit=function(name) events[#events+1]=name end }
package.loaded['core/player'] = { dead=false }
package.loaded['core/abilities'] = {}
package.loaded['core/bullets'] = { spawnEnemyBullet=function(...) shots[#shots+1]={...} end }
local E = require 'core/enemies'
local MON = require 'data/monsters'
local function upvalue(fn, want)
    for i=1,100 do
        local name, value = debug.getupvalue(fn, i)
        if name == want then return value end
        if not name then break end
    end
    error('missing upvalue '..want)
end
local ai = upvalue(E.update, 'AI').crab
local function enemy(kind)
    return {def=MON.crab, node={position2D=Vector2(0,0)}, body={linearVelocity=Vector2(2,0)},
        radius=0.6, slowTimer=0, facing=1, state='attack', atkTimer=0,
        atkAnimTimer=0.2, warnTimer=0, pendingAttack=kind, clawSide=1}
end
for _,kind in ipairs({'ranged','melee'}) do
    local e=enemy(kind)
    ai(e, 1/60, Vector2(kind=='ranged' and -1 or -4,0))
    assert(e.pendingAttack==kind and e.warnTimer==0, 'active '..kind..' attack changed type')
    assert(e.state=='attack' and e.facing==1, 'active attack state/facing was overwritten')
    assert(e.body.linearVelocity.x==0, 'crab moves during attack')
end
for _,kind in ipairs({'ranged','melee'}) do
    local e=enemy(kind)
    e.atkAnimTimer=0; e.warnTimer=0.01; e.state='warn'
    events,shots={},{}
    ai(e, 0.02, Vector2(kind=='ranged' and 1 or 4,0))
    assert(e.pendingAttack==kind and e.atkAnimTimer>0, 'warning switched attack type')
    assert((kind=='ranged' and #shots==1 and #events==0) or
        (kind=='melee' and #events==1 and #shots==0), 'mixed melee/ranged effects')
end
local clips=require 'data/art'
assert(clips.enemy_crab_melee.count==16, 'new melee sheet must play all 16 frames')
assert(math.abs(E.attackAnimTime(MON.crab,'melee')-16/clips.enemy_crab_melee.fps)<1e-8,
    'melee timer truncates animation')
assert(math.abs(E.attackAnimTime(MON.crab,'ranged')-4/clips.enemy_crab_ranged.fps)<1e-8,
    'ranged timer differs from animation')
assert(clips.enemy_fly and clips.enemy_fly.count==8, 'fly animation missing')
print('PASS: attack lock, movement lock, exclusive effects, complete clip durations')

-- The real rendering branch must choose only the locked clip, including warning.
for _,name in ipairs({'core/hazards','core/level','core/melee_fx','core/combat_fx',
    'core/editor_render','core/tile_render','core/tilesets','core/map_backgrounds'}) do
    local stub={}
    package.loaded[name]=stub
    package.loaded[(name:gsub('/','.'))]=stub
end
local Art=require 'core/art'
local R=require 'core/render'
local drawEnemy=upvalue(upvalue(R.drawWorld,'drawEnemies'),'drawEnemyShape')
local calls={}
local original=Art.drawEnemy
Art.drawEnemy=function(_,key,tm,x,y,r,facing,offset)
    calls[#calls+1]={key=key,offset=offset,time=tm}; return true
end
for _,kind in ipairs({'melee','ranged'}) do
    for _,side in ipairs({-1,1}) do
        for _,warn in ipairs({false,true}) do
            local e=enemy(kind)
            e.clawSide=side; e.animTime=0; e.hitFlash=0
            if warn then e.atkAnimTimer=0; e.warnTimer=0.2 end
            calls={}; drawEnemy({},e,0,0,30)
            assert(#calls==1 and calls[1].key=='enemy_crab_'..kind,'wrong/mixed attack clip')
            assert(calls[1].offset==((kind=='ranged' and side==-1) and 4 or 0),
                'melee must play whole sequence; ranged must stay in selected claw sequence')
        end
    end
end
calls={}
drawEnemy({}, {def=MON.fly,animTime=1,hitFlash=0,facing=-1},0,0,30)
assert(#calls==1 and calls[1].key=='enemy_fly','fly still uses vector fallback')
Art.drawEnemy=original
print('PASS: real render selects exclusive ranged/melee clips and fly sprite')

-- Exercise real Art.drawEnemy and its sampler; capture only NanoVG boundaries.
local images=upvalue(upvalue(Art.drawEnemy,'draw'),'images')
local current, transform, pattern={},{},{}
for _,name in ipairs({'nvgSave','nvgRestore','nvgBeginPath','nvgRect','nvgFillPaint','nvgFill'}) do
    _G[name]=function() end
end
nvgTranslate=function(_,x,y) transform.x=x; transform.y=y end
nvgScale=function(_,x,y) transform.sx=x; transform.sy=y end
nvgImageSize=function() return current.width,current.height end
nvgImagePattern=function(_,x,y) pattern.x=x; pattern.y=y; return {} end
for _,key in ipairs({'enemy_crab_move','enemy_crab_melee','enemy_crab_ranged'}) do
    local clip=clips[key]
    images[clip.path]=1
    for offset=0,(key=='enemy_crab_ranged' and 4 or 0),4 do
        for i=1,clip.count do
            current={width=1024,height=(key=='enemy_crab_melee' and 1024 or 512)}
            Art.drawEnemy({},key,(i-1)/clip.fps+1e-8,100,200,30,1,offset)
            local sampleX=-pattern.x-clip.pivotX
            local sampleY=-pattern.y-clip.pivotY
            local frame=offset+i-1
            assert(sampleX==(frame%4)*256+2 and sampleY==math.floor(frame/4)*256+2,
                'sampler skips/repeats animation frames')
            assert(transform.y==230 and transform.sy>0, 'floor anchor/scale incorrect')
        end
    end
end
print('PASS: all 16 melee and both ranged sequences sampled in order with floor anchor')

-- Hand-inspected source direction: melee swings left; ranged rows throw left/right.
-- Exercise render -> real atlas sampler for both world directions and both claws.
for _,kind in ipairs({'melee','ranged'}) do
    for _,side in ipairs({-1,1}) do
        for _,facing in ipairs({-1,1}) do
            for _,warn in ipairs({false,true}) do
                local e=enemy(kind)
                e.facing=facing; e.clawSide=side; e.animTime=0; e.hitFlash=0
                if warn then e.atkAnimTimer=0; e.warnTimer=0.2 end
                current={width=1024,height=(kind=='melee' and 1024 or 512)}
                drawEnemy({},e,100,200,30)
                local sourceDirection=(kind=='ranged' and side==-1) and 1 or -1
                assert(sourceDirection*transform.sx*facing>0,
                    kind..' artwork points opposite to attack: claw='..side..' facing='..facing)
            end
        end
    end
end
print('PASS: melee and both ranged claw animations point along the attack direction')
''')

# Independent alpha measurements check the actual ground gap in rendered pixels.
import numpy as np
from PIL import Image
clips = lua.eval("require('data/art')")
for key, count in [('enemy_crab_move', 8), ('enemy_crab_melee', 16), ('enemy_crab_ranged', 8)]:
    clip = clips[key]
    im = Image.open(ROOT / 'assets' / clip['path']).convert('RGBA')
    for i in range(count):
        frame = im.crop(((i % 4)*256+2, (i//4)*256+2, (i % 4)*256+254, (i//4)*256+254))
        ys, xs = np.where(np.asarray(frame)[:, :, 3] > 10)
        bottom = int(ys.max())+1
        gap = (clip['pivotY']-bottom)*60/clip['sourceHeight']
        assert abs(gap) <= 1.2, (key, i, gap)
print('PASS: every crab frame has <=1.2px floor gap at 60px body height')
