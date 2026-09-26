-- objects/sb2_market/sb2_market.lua
-- Server-side skript terminalu sb2_market (economy-system.md 5.2, 5.4).
-- Pane (klient) si pyta data cez entity message; tento skript cita market state
-- z world property backendu a vracia riadky breakdownu. Ziadny obchod, iba citanie.
-- Used by: sb2_market.object; volany z sb2_market_pane.lua cez world.sendEntityMessage
-- Performance: event-driven (per otvorenie panelu), ziadny update tick
-- Lua 5.1 striktne.

require("/scripts/sb2_util.lua")
require("/scripts/sb2_config.lua")
require("/scripts/sb2_station.lua")
require("/scripts/sb2_storage.lua")
require("/scripts/sb2_migrations.lua")
require("/scripts/sb2_economy_tags.lua")
require("/scripts/sb2_market_state.lua")

local ECONOMY_CONFIG = "/configs/sb2_economy.config"
local TAGS_CONFIG = "/configs/sb2_economy_tags.config"

local function log(msg)
  sb.logInfo("[SB2_MARKET] " .. msg)
end

-- Internal: station id z parametra objektu alebo zo sveta (sb2_station)
local function _stationId()
  return sb2_station.resolveStationId(config.getParameter("sb2_station_id"), world.id())
end

-- Internal: nacita stav stanice (s migraciou) alebo nil
local function _loadState(backend, station_id)
  return sb2_storage.loadState(backend, sb2_storage.marketKey(station_id),
    sb2_market_state.STATE_TYPE, sb2_market_state.SCHEMA_VERSION, { log = log })
end

-- Message: sb2_market.getBreakdown() -> { ok, station_id, day_index, rows } | { ok=false, reason }
local function handleGetBreakdown()
  local ok, result = pcall(function()
    local cfg = sb2_config.load(ECONOMY_CONFIG)
    local station_id = _stationId()
    local backend = sb2_storage.newWorldPropertyBackend()
    local state = _loadState(backend, station_id)
    if state == nil then
      return { ok = false, reason = "no_state", station_id = station_id }
    end
    sb2_market_state.validate(state)
    return {
      ok = true,
      station_id = station_id,
      day_index = state.day_index,
      last_recompute_day = state.last_recompute_day,
      rows = sb2_market_state.breakdownRows(state, cfg)
    }
  end)
  if not ok then
    log("getBreakdown failed: " .. tostring(result))
    return { ok = false, reason = "error", detail = tostring(result) }
  end
  return result
end

-- Message: sb2_market.seedDemo() – DEV: vytvori ukazkovy stav stanice, aby sa dal
-- terminal otestovat skor, ako existuje merchant hook. Iba pre admina (kontroluje pane).
local function handleSeedDemo()
  local ok, result = pcall(function()
    local cfg = sb2_config.load(ECONOMY_CONFIG)
    local tags_config = sb2_config.load(TAGS_CONFIG)
    sb2_economy_tags.validate(tags_config)
    local station_id = _stationId()
    local backend = sb2_storage.newWorldPropertyBackend()

    local state = sb2_market_state.new(station_id, {}, 1)
    local names = sb2_util.sortedKeys(tags_config.item_overrides)
    local demo_base = { liquidwater = 5, corefragment = 30, titaniumbar = 12 }
    for i = 1, #names do
      local name = names[i]
      local category = tags_config.item_overrides[name].category
      local params = sb2_economy_tags.getItemParams(name, category, tags_config, cfg)
      sb2_market_state.ensureItem(state, name, demo_base[name] or 10, params)
    end
    sb2_market_state.recomputeAll(state, cfg)
    -- trochu pohybu: blokada, konvoj, predaj hraca, dva day ticky
    sb2_market_state.queueEvent(state, { type = "regional_event", label = "blockade_apex", magnitude = 0.30, day = 2, expires_day = 9 })
    sb2_market_state.queueEvent(state, { type = "trade_flow_arrival", item = "titaniumbar", magnitude = 0.12, day = 2 })
    sb2_market_state.dayTick(state, cfg, world.id())
    sb2_market_state.dayTick(state, cfg, world.id())
    if state.items.liquidwater then
      sb2_market_state.applyTransaction(state, "liquidwater", 150, true, cfg)
    end
    sb2_storage.saveState(backend, sb2_storage.marketKey(station_id), state)
    log("demo state seeded for " .. station_id .. " (" .. #names .. " items)")
    return { ok = true, station_id = station_id }
  end)
  if not ok then
    log("seedDemo failed: " .. tostring(result))
    return { ok = false, reason = "error", detail = tostring(result) }
  end
  return result
end

function init()
  object.setInteractive(true)
  message.setHandler("sb2_market.getBreakdown", function(_, _, args) return handleGetBreakdown(args) end)
  message.setHandler("sb2_market.seedDemo", function() return handleSeedDemo() end)
end
