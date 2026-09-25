-- mod/scripts/sb2_config.lua
-- Nacitanie JSON configov modu. V Starbounde cez root.assetJson, mimo hry
-- (standalone testy) cez globalnu tabulku SB2_TEST_CONFIGS[path].
-- Used by: sb2_economy_init, testy
-- Performance: one-time pri init (vysledok cache-ovat, nie volat v hot path)
-- Lua 5.1 striktne.

local sb2_util = require("sb2_util")

local sb2_config = {}

local cache = {}

-- Public API (stable)
function sb2_config.load(path)
  if cache[path] then return cache[path] end
  local value
  if type(root) == "table" and root.assetJson then
    value = root.assetJson(path)
  elseif type(SB2_TEST_CONFIGS) == "table" then
    value = SB2_TEST_CONFIGS[path]
  end
  sb2_util.require(type(value) == "table", "config not found or not a table: " .. tostring(path))
  sb2_util.require(type(value.schema_version) == "number", "config " .. path .. " has no schema_version")
  cache[path] = value
  return value
end

-- Public API (stable)
function sb2_config.clearCache()
  cache = {}
end

return sb2_config
