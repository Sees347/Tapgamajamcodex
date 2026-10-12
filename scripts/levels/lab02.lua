-- ============================================================================
-- levels/lab02.lua - 第二章「废弃冷冻库」（解析入口）
-- 地图数据在 levels/lab02_src.lua，本文件负责解析成标准 LevelDef。
-- ============================================================================

local Tilemap = require "core.tilemap"
local SRC = require "levels.lab02_src"

return Tilemap.parse(SRC)
