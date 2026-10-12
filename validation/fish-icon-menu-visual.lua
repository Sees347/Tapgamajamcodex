-- 装备/图鉴菜单图标验收：持有全部鱼并打开图鉴，确认新图标实际加载渲染。
local GS = require "core/state"
local HUD = require "ui/hud"
local Menus = require "ui/menus"
local Art = require "core/art"
local FISH = require "data/fish"

local ready = false
V.atFrame(20, function()
    GS.save = GS.defaultSave()
    GS.save.water = 12
    LoadLevel("testmap", nil)
    -- 只持有三种新鱼：图鉴顶部即显示新图标，便于直接核对
    GS.save.fish = { "swordfish", "barnacle", "frog" }
    HUD.hideOverlay()
    Menus.showInventory(true)
end)
V.atFrame(90, function() ready = true end)

V.atFrame(100, function()
    -- 新图标必须都能解析到真实文件，否则菜单会退回文字
    for _, key in ipairs({ "swordfish", "barnacle", "frog" }) do
        local icon = Art.fishIcon(key)
        V.assert(icon ~= nil, "fish_" .. key .. " 图标路径存在")
        V.assert(cache:GetResource("Texture2D", icon) ~= nil, "fish_" .. key .. " 图标纹理可加载")
    end
end)
