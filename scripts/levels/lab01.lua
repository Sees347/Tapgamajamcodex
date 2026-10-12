-- ============================================================================
-- levels/lab01.lua - 第一章「零号实验室」（解析入口）
-- 地图数据在 levels/lab01_src.lua。
-- 编辑器改动（沙箱）由 main.lua 的 LoadLevel 优先应用，见 applyEditorOverride。
-- ============================================================================

local Tilemap = require "core.tilemap"
local SRC = require "levels.lab01_src"

return Tilemap.parse(SRC)
