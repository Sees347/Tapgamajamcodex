-- 背景整图实际编辑验收：仅mock内存world快照，不保存用户地图或正式玩家进度。
---@class BackgroundValidationHarness
---@field atFrame fun(frame:integer, callback:function)
---@field assert fun(condition:any, message:string)
local V = assert(rawget(_G, "V")) --[[@as BackgroundValidationHarness]]
local ME = require "core.map_editor"
local EB = require "core.editor_backgrounds"
local B = require "core.map_backgrounds"
local TM = require "core.tilemap"
local R = require "core.render"
local UI = require "urhox-libs/UI"
local Editor = require "ui.map_editor"
local Export = require "ui.map_export"
local GS = require "core.state"
local HUD = require "ui.hud"
local L = require "core.level"
local PT = require "core.playtest"
local originalPeek, originalMapWrite, originalWrite = ME.peekSandbox, ME.saveToSandbox, GS.saveGame
local saved = { id = "world", tile = 1, originX = 0, originY = 12, cols = 30, rows = 12,
    map = string.rep(string.rep(" ", 30) .. "\n", 11) .. string.rep("#", 30), spawn = { x = 15, y = 5 } }
local writes = 0
local selectedId = ""
local expected = {}
local function find(widget, predicate)
    if predicate(widget) then return widget end
    for _, child in ipairs(widget:GetChildren()) do local found = find(child, predicate); if found then return found end end
    if widget.GetHitTestChildren then for _, child in ipairs(widget:GetHitTestChildren() or {}) do local found = find(child, predicate); if found then return found end end end
    return nil
end
local function click(text, tree)
    local button = find(tree or UI.GetTopOverlay() or HUD.root, function(w) return w._className == "Button" and w.props.text == text end)
    V.assert(button ~= nil, "背景操作按钮存在：" .. text)
    if button then button.props.onClick(button) end
    UI.Layout()
end
local function atWorld(x, y) return R.w2s(x, y) end

V.atFrame(10, function()
    GS.save = GS.defaultSave(); GS.saveGame = function() writes = writes + 1 end
    ME.peekSandbox = function(id) return id == "world" and saved or nil end
    ME.saveToSandbox = function() saved = ME.captureData(); ME.dirty = false; return true end
    assert(rawget(_G, "LoadLevel"))("world")
    assert(rawget(_G, "OpenMapEditor"))()
    -- 默认入口已改为共享地图；显式载入本测试的隔离空图，不假定旧沙箱覆盖共享源。
    assert(ME.loadSource(saved))
    ME.centerCamera()
    Editor.selectBackground()
    UI.Layout()
end)

V.atFrame(35, function()
    local asset = B.get("industrial_backdrop")
    V.assert(asset and asset.pixelWidth == 6443 and asset.pixelHeight == 2106, "登记上传背景精确原图比例")
    local ready = B.init(require("urhox-libs.UI.Core.ImageCache").GetContext())
    V.assert(ready, "UI绘图上下文加载并核实真实背景资源")
    local thumb = find(HUD.root, function(w) return w._className == "EditorBackgroundThumbnail" end)
    V.assert(thumb ~= nil, "背景页显示可拖放真实缩略图")
    local canvas = Editor.getCanvasRect()
    local sx, sy = canvas.x + canvas.w * 0.4, canvas.y + canvas.h * 0.5
    local l = thumb and thumb:GetAbsoluteLayoutForHitTest()
    V.assert(l ~= nil, "真实缩略图命中区域存在")
    local scale, dpr = UI.GetScale(), graphics:GetDPR()
    local sourceX = l and (l.x + l.w / 2) * scale or (canvas.x + canvas.w + 20) * dpr
    local sourceY = l and (l.y + l.h / 2) * scale or sy * dpr
    -- 走完整UI命中与pressedWidget路由，不直接调用背景控制器代替素材拖放。
    UI.HandleMouseDown(sourceX, sourceY, MOUSEB_LEFT)
    V.assert(EB.dragging and EB.pendingAsset == "industrial_backdrop", "真实缩略图按下开始背景拖放")
    UI.HandleMouseMove(sx * dpr, sy * dpr)
    V.assert(#EB.list() == 0 and #EB.renderImages() == 1, "拖放预览不先写入地图")
    UI.HandleMouseUp(sx * dpr, sy * dpr, MOUSEB_LEFT)
    V.assert(not EB.dragging and #EB.list() == 1, "离开缩略图后UI松开仍提交画布放置")
    V.assert(#EB.list() == 1 and ME.tool == "background" and ME.selectedLayer == "background", "背景是独立实例而非瓦片或碰撞")
    selectedId = EB.selectedId
    local image = EB.selected()
    V.assert(image and math.abs(B.height(image) / image.width - 2106 / 6443) < 1e-12, "放置后高度由原图比例精确推导")
    local map = ME.exportString()
    V.assert(EB.setWidth(18), "属性等比宽度可修改")
    V.assert(EB.moveTo(15, 6), "属性位置可修改")
    V.assert(ME.exportString() == map and next(ME.collisionCells) == nil, "背景操作不改玩法字符和碰撞")
    UI.Layout()
end)

V.atFrame(45, function()
    local thumb = find(HUD.root, function(w) return w._className == "EditorBackgroundThumbnail" end)
    if not thumb then V.assert(false, "触摸拖放缩略图存在"); return end
    local l = thumb:GetAbsoluteLayoutForHitTest()
    local scale, dpr = UI.GetScale(), graphics:GetDPR()
    local px, py = (l.x + l.w / 2) * scale, (l.y + l.h / 2) * scale
    local canvas = Editor.getCanvasRect()
    local tx, ty = (canvas.x + canvas.w * 0.4) * dpr, (canvas.y + canvas.h * 0.5) * dpr
    UI.HandleTouchBegin(81, px, py, 1)
    UI.HandleTouchMove(81, px, (l.y + l.h + 16) * scale, 1)
    V.assert(EB.dragging, "触摸首步划出缩略图不被父滚动区取消")
    UI.HandleTouchMove(81, tx, ty, 1)
    UI.HandleTouchEnd(81, tx, ty)
    V.assert(not EB.dragging and #EB.list() == 2, "完整触摸拖放只新增一个背景实例")
    EB.removeSelected(); EB.selectInstance(selectedId)
    UI.HandleTouchBegin(82, px, py, 1)
    UI.HandleTouchCancel(82)
    V.assert(not EB.dragging and #EB.list() == 1 and EB.pendingAsset == "", "触摸取消不写地图或残留拖动")
    EB.selectInstance(selectedId)
    UI.Layout()
end)

V.atFrame(70, function()
    click("放大 20%", HUD.root)
    V.assert(math.abs(EB.selected().width - 21.6) < 0.001, "UI放大按钮等比调整背景")
    click("缩小 20%", HUD.root)
    V.assert(math.abs(EB.selected().width - 17.28) < 0.001, "UI缩小按钮等比调整背景")
    EB.setWidth(18)
    local image = EB.selected()
    local beforeX, beforeY, beforeW = image.x, image.y, image.width
    local sx, sy = atWorld(image.x, image.y)
    local dx, dy = atWorld(image.x + 1, image.y + 0.5)
    V.assert(EB.beginPointer(sx, sy, R), "背景内部可开始移动")
    Editor.selectBackground()
    V.assert(EB.dragging, "刷新同背景页不取消刚开始的拖动")
    EB.movePointer(dx, dy, R)
    V.assert(image.x == beforeX and EB.renderImages()[1].x ~= beforeX, "移动仅改变预览未提交实例")
    V.assert(EB.endPointer(dx, dy, R, true), "移动释放提交")
    V.assert(math.abs(image.x - beforeX - 1) < 0.001 and math.abs(image.y - beforeY - 0.5) < 0.001 and image.width == beforeW, "拖内部平移不变尺寸")
    local h = B.height(image)
    local anchorX, anchorY = image.x - image.width / 2, image.y - h / 2
    local cx, cy = atWorld(image.x + image.width / 2, image.y + h / 2)
    local tx, ty = atWorld(anchorX + 24, anchorY + 24 * 2106 / 6443)
    V.assert(EB.beginPointer(cx, cy, R), "右上角手柄可开始等比缩放")
    EB.movePointer(tx, ty, R)
    V.assert(EB.endPointer(tx, ty, R, true), "缩放释放提交")
    V.assert(math.abs(image.width - 24) < 0.001 and math.abs(image.x - image.width / 2 - anchorX) < 0.001
        and math.abs(image.y - B.height(image) / 2 - anchorY) < 0.001, "四角缩放固定对角锚点并保持比例")
    local oldWidth = image.width
    ME.getLayerState("background").locked = true
    V.assert(not EB.setWidth(50) and not EB.removeSelected() and image.width == oldWidth, "锁定背景层阻止修改和删除")
    ME.getLayerState("background").locked = false
    ME.getLayerState("background").visible = false
    V.assert(not EB.beginPointer(cx, cy, R), "隐藏背景层不误选拖动")
    ME.getLayerState("background").visible = true
    local oldX = image.x
    sx, sy = atWorld(image.x, image.y)
    EB.beginPointer(sx, sy, R); EB.movePointer(sx + 20, sy, R); EB.endPointer(0, 0, R, false)
    V.assert(image.x == oldX and not EB.dragging, "拖到界面外取消不提交错误位置")
    EB.selectAsset("industrial_backdrop"); EB.cancel()
    V.assert(EB.pendingAsset == "", "切回其它工具不会残留待放置背景")
    EB.selectInstance(selectedId)
    local captured = ME.captureData()
    local data, err = Export.decode(cjson.encode(captured))
    V.assert(data ~= nil and err == nil and #data.metadata.backgroundImages == 1, "完整JSON包含背景位置与等比宽度")
    V.assert(Export.apply(captured), "JSON往返加载背景成功")
    EB.selectInstance(selectedId)
    local decoded = TM.parse(captured)
    V.assert(#decoded.tilemapData.backgroundImages == 1 and #decoded.platforms == 1, "游戏解析背景不生成额外碰撞平台")
    local bad = ME.captureData(); bad.metadata.backgroundImages[1].assetId = "missing"
    local grid = ME.grid
    V.assert(Export.decode(cjson.encode(bad)) == nil and not ME.loadSource(bad) and ME.grid == grid, "无效背景资源拒绝载入且保留原地图")
    local shadow = ME.captureData(); shadow.backgroundImages = false
    V.assert(Export.decode(cjson.encode(shadow)) == nil and not ME.loadSource(shadow) and ME.grid == grid,
        "顶层false不能绕过背景校验或覆盖有效metadata")
    V.assert(not B.validate({ { id = "x", assetId = "industrial_backdrop", x = 0, y = 0, width = -1 } }), "负尺寸背景被拒绝")
    local original = EB.selected()
    EB.beginAssetDrag("industrial_backdrop", sx, sy)
    EB.endPointer(sx, sy, R, true)
    V.assert(#EB.list() == 2, "同一素材可独立重复放置")
    EB.removeSelected()
    V.assert(#EB.list() == 1 and EB.list()[1].id == original.id, "删除仅移除所选背景实例")
    EB.selectInstance(selectedId)
    expected = { x = EB.selected().x, y = EB.selected().y, width = EB.selected().width }
    EB.focusSelected()
    UI.Layout()
end)

V.atFrame(140, function()
    click("退出并测试", HUD.root)
    V.assert(not ME.active and PT.active and #L.def.tilemapData.backgroundImages == 1, "编辑背景保存后退出试玩保留实例")
    local image = L.def.tilemapData.backgroundImages[1]
    V.assert(image.x == expected.x and image.y == expected.y and image.width == expected.width, "试玩与编辑背景位置尺寸一致")
    V.assert(#L.platformRects == 1 and writes == 0, "背景试玩不产生碰撞且不写正式进度")
end)
V.atFrame(190, function()
    PT.finish(); ME.dirty = false; Editor.hide(); EB.cancel()
    ME.peekSandbox, ME.saveToSandbox, GS.saveGame = originalPeek, originalMapWrite, originalWrite
end)
