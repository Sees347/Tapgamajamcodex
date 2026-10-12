-- ============================================================================
-- levels/lab03.lua - 第三章「干涸河谷」（解析入口）
-- 地图数据在 levels/lab03_src.lua，本文件负责解析成标准 LevelDef。
-- ============================================================================

local Tilemap = require "core.tilemap"
local SRC = require "levels.lab03_src"

return Tilemap.parse(SRC)
