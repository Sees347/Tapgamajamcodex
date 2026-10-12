-- ============================================================================
-- levels/editor_map.lua - 字符瓦片地图（解析入口）
--
-- 地图数据在 levels/editor_map_src.lua（也可用游戏内「编辑地图」可视化编辑后导出）。
-- 本文件只负责把它解析成标准 LevelDef。
-- ============================================================================

local Tilemap = require "core.tilemap"
local SRC = require "levels.editor_map_src"

return Tilemap.parse(SRC)
