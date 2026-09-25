-- mod/scripts/sb2_market_state.lua
-- Per-station market state DPS: vytvorenie, recompute, transakcie, day tick,
-- catch-up po neaktivite (docs/economy-system.md 2.1, 4.1, 6.1–6.3).
-- Cisty modul nad tabulkami – storage a engine API su mimo (sb2_storage, init).
-- Used by: sb2_economy_init (day tick), merchant hook (recompute, transakcia), sb2_market UI
-- Performance: recomputeItem hot path (<0.2 ms); dayTick cold path (<2 ms per market)
-- Lua 5.1 striktne.

local sb2_util = require("sb2_util")
local sb2_pricing = require("sb2_pricing")
local sb2_prng = require("sb2_prng")

local sb2_market_state = {}

sb2_market_state.SCHEMA_VERSION = 1
sb2_market_state.STATE_TYPE = "market_state"

-- Public API (stable)
-- Novy prazdny stav stanice (schema 4.1).
function sb2_market_state.new(station_id, world_coords, day_index)
  sb2_util.require(type(station_id) == "string" and #station_id > 0, "new: station_id required")
  return {
    schema_version = sb2_market_state.SCHEMA_VERSION,
    station_id = station_id,
    world_coords = world_coords or {},
    last_recompute_day = day_index or 0,
    day_index = day_index or 0,
    daily_turnover = {},
    items = {},
    pending_events = {},
    outbound_events = {},
    migration_history = {}
  }
end

-- Public API (stable)
-- Strukturalna validacia (no silent failures). Vrati true alebo error.
function sb2_market_state.validate(state)
  sb2_util.require(type(state) == "table", "validate: state must be table")
  sb2_util.require(state.schema_version == sb2_market_state.SCHEMA_VERSION,
    "validate: unexpected schema_version " .. tostring(state.schema_version))
  sb2_util.require(type(state.station_id) == "string", "validate: station_id missing")
  sb2_util.require(type(state.day_index) == "number", "validate: day_index missing")
  sb2_util.require(type(state.items) == "table", "validate: items missing")
  for name, item in pairs(state.items) do
    sb2_util.require(type(item.base_price) == "number", "validate: item " .. name .. " has no base_price")
    sb2_util.require(type(item.local_modifiers) == "table", "validate: item " .. name .. " has no local_modifiers")
  end
  return true
end

-- Public API (stable)
-- Zabezpeci zaznam itemu; params z sb2_economy_tags.getItemParams.
function sb2_market_state.ensureItem(state, item_name, base_price, params)
  local item = state.items[item_name]
  if item then
    return item
  end
  sb2_util.require(type(base_price) == "number", "ensureItem: base_price required for " .. item_name)
  sb2_util.require(type(params) == "table", "ensureItem: params required for " .. item_name)
  item = {
    base_price = base_price,
    params = {
      category = params.category,
      daily_turnover_baseline = params.daily_turnover_baseline,
      decay_factor = params.decay_factor,
      jitter_amplitude = params.jitter_amplitude
    },
    local_modifiers = { supply_demand = 1.0, station_specialization = 1.0 },
    regional_modifiers_cached = { trade_flow = 0.0 },
    global_modifiers_cached = {},
    active_sources = {},
    player_pressure = 0.0,
    jitter = 0.0,
    last_final_price = base_price,
    top_reasons_cache = {}
  }
  state.items[item_name] = item
  state.daily_turnover[item_name] = 0
  return item
end

-- Public API (stable)
-- Prepocet jedneho itemu. context = { regional = {label=val}, global = {label=val} }
-- (hodnoty z universe stavu; nil = pouzi cache). Zapise last_final_price a
-- top_reasons_cache (5.3). Vrati vysledok sb2_pricing.computePrice.
function sb2_market_state.recomputeItem(state, item_name, cfg, context)
  local item = state.items[item_name]
  sb2_util.require(item ~= nil, "recomputeItem: unknown item " .. tostring(item_name))
  context = context or {}
  if context.regional then
    for label, value in pairs(context.regional) do
      item.regional_modifiers_cached[label] = value
    end
  end
  if context.global then
    for label, value in pairs(context.global) do
      item.global_modifiers_cached[label] = value
    end
  end
  local result = sb2_pricing.computePrice(item, cfg)
  item.last_final_price = result.final_price
  item.top_reasons_cache = sb2_pricing.topReasons(item, cfg)
  state.last_recompute_day = state.day_index
  return result
end

-- Public API (stable)
function sb2_market_state.recomputeAll(state, cfg, context)
  local names = sb2_util.sortedKeys(state.items)
  for i = 1, #names do
    sb2_market_state.recomputeItem(state, names[i], cfg, context)
  end
end

-- Public API (stable)
-- Cena je zastarana, ak posledny recompute je starsi ako recompute_max_age_days (2.1).
function sb2_market_state.isStale(state, cfg)
  return (state.day_index - state.last_recompute_day) >= cfg.recompute_max_age_days
end

-- Public API (stable)
-- Hracska transakcia (3.4, 6.2, 6.3). Vrati { pressure, delta, share, extreme }.
-- extreme = nil alebo outbound event pre susedne stanice.
function sb2_market_state.applyTransaction(state, item_name, volume, is_sell, cfg)
  local item = state.items[item_name]
  sb2_util.require(item ~= nil, "applyTransaction: unknown item " .. tostring(item_name))
  sb2_util.require(type(volume) == "number" and volume > 0, "applyTransaction: volume must be > 0")

  local baseline = item.params.daily_turnover_baseline
  local pressure, delta, share = sb2_pricing.applyPlayerPressure(item.player_pressure, volume, baseline, is_sell, cfg)
  item.player_pressure = pressure
  state.daily_turnover[item_name] = (state.daily_turnover[item_name] or 0) + volume

  local extreme = nil
  if share > cfg.extreme_share_threshold then
    extreme = {
      type = is_sell and "extreme_glut" or "extreme_scarcity",
      item = item_name,
      source_station = state.station_id,
      magnitude = (is_sell and -1 or 1) * cfg.extreme_neighbor_modifier,
      day = state.day_index + 1,
      expires_day = state.day_index + 1 + cfg.extreme_neighbor_days,
      target = "neighbors"
    }
    state.outbound_events[#state.outbound_events + 1] = extreme
  end

  sb2_market_state.recomputeItem(state, item_name, cfg)
  return { pressure = pressure, delta = delta, share = share, extreme = extreme }
end

-- Public API (stable)
-- Zaradi event do pending_events. Typy:
--   trade_flow_departure / trade_flow_arrival: { item, magnitude, day }
--   regional_event: { label, magnitude, day, expires_day }  (napr. blokada)
--   global_event:   { label, magnitude, day, expires_day }  (multiplikativne, base 1.0)
function sb2_market_state.queueEvent(state, event)
  sb2_util.require(type(event.type) == "string", "queueEvent: type required")
  sb2_util.require(type(event.day) == "number", "queueEvent: day required")
  state.pending_events[#state.pending_events + 1] = event
end

-- Internal: aplikuje jeden event na stav
local function _applyEvent(state, event)
  if event.type == "trade_flow_departure" or event.type == "trade_flow_arrival" then
    local item = state.items[event.item]
    if item then
      local sign = (event.type == "trade_flow_arrival") and 1 or -1
      -- prichod tovaru = vacsia ponuka = nizsia cena; odchod = vyssia
      item.regional_modifiers_cached.trade_flow =
        (item.regional_modifiers_cached.trade_flow or 0) - sign * event.magnitude
    end
  elseif event.type == "regional_event" or event.type == "global_event" then
    local names = sb2_util.sortedKeys(state.items)
    for i = 1, #names do
      local item = state.items[names[i]]
      if event.type == "regional_event" then
        item.regional_modifiers_cached[event.label] = event.magnitude
      else
        item.global_modifiers_cached[event.label] = event.magnitude
      end
      if event.expires_day then
        item.active_sources[event.label] = event.expires_day
      end
    end
  else
    error("[SB2] unknown pending event type: " .. tostring(event.type))
  end
end

-- Public API (stable)
-- Aplikuje vsetky pending events s day <= day a odstrani ich.
function sb2_market_state.applyPendingEvents(state, day)
  local remaining = {}
  for i = 1, #state.pending_events do
    local event = state.pending_events[i]
    if event.day <= day then
      _applyEvent(state, event)
    else
      remaining[#remaining + 1] = event
    end
  end
  state.pending_events = remaining
end

-- Internal: decay vsetkych modifikatorov itemu o `days` dni (3.5)
local function _decayItem(item, day_index, days, cfg)
  local factor = item.params.decay_factor or cfg.default_decay_factor
  for label, value in pairs(item.local_modifiers) do
    item.local_modifiers[label] = sb2_pricing.decay(value, 1.0, factor, days)
  end
  for label, value in pairs(item.global_modifiers_cached) do
    local expires = item.active_sources[label]
    if expires and day_index < expires then
      -- aktivny zdroj: decay_factor = 1.0 (3.5)
    else
      item.global_modifiers_cached[label] = sb2_pricing.decay(value, 1.0, factor, days)
      item.active_sources[label] = nil
    end
  end
  for label, value in pairs(item.regional_modifiers_cached) do
    local expires = item.active_sources[label]
    if expires and day_index < expires then
      -- aktivny zdroj, neklesa
    else
      item.regional_modifiers_cached[label] = sb2_pricing.decay(value, 0.0, factor, days)
      item.active_sources[label] = nil
    end
  end
end

-- Internal: deterministicky jitter pre jeden nahodny item (3.6)
local function _applyJitter(state, world_seed, cfg)
  local names = sb2_util.sortedKeys(state.items)
  for i = 1, #names do
    state.items[names[i]].jitter = 0.0
  end
  if #names == 0 then return nil end
  local prng = sb2_prng.new(sb2_prng.hash(world_seed or "", state.station_id, state.day_index))
  local chosen = names[prng:nextInt(1, #names)]
  local item = state.items[chosen]
  item.jitter = prng:jitter(item.params.jitter_amplitude or cfg.default_jitter_amplitude)
  return chosen
end

-- Public API (stable)
-- Jeden sb2_economy_day tick (2.1): day_index +1, reset denneho obratu a
-- hracskeho tlaku, decay, jitter, pending events, recompute.
function sb2_market_state.dayTick(state, cfg, world_seed)
  state.day_index = state.day_index + 1
  local names = sb2_util.sortedKeys(state.items)
  for i = 1, #names do
    local item = state.items[names[i]]
    state.daily_turnover[names[i]] = 0
    item.player_pressure = 0.0
    _decayItem(item, state.day_index, 1, cfg)
  end
  _applyJitter(state, world_seed, cfg)
  sb2_market_state.applyPendingEvents(state, state.day_index)
  sb2_market_state.recomputeAll(state, cfg)
end

-- Public API (stable)
-- Catch-up po neaktivite (6.1): do inactivity_threshold_days tikaj po dnoch,
-- nad prah aplikuj decay v jednom batchi. Vrati pocet dobehnutych dni.
function sb2_market_state.advanceTo(state, target_day, cfg, world_seed)
  local elapsed = target_day - state.day_index
  if elapsed <= 0 then return 0 end
  if elapsed <= cfg.inactivity_threshold_days then
    for _ = 1, elapsed do
      sb2_market_state.dayTick(state, cfg, world_seed)
    end
    return elapsed
  end
  -- batch: n-nasobny decay, jeden reset, jeden jitter pre cielovy den
  local names = sb2_util.sortedKeys(state.items)
  state.day_index = target_day
  for i = 1, #names do
    local item = state.items[names[i]]
    state.daily_turnover[names[i]] = 0
    item.player_pressure = 0.0
    _decayItem(item, state.day_index, elapsed, cfg)
  end
  _applyJitter(state, world_seed, cfg)
  sb2_market_state.applyPendingEvents(state, state.day_index)
  sb2_market_state.recomputeAll(state, cfg)
  return elapsed
end

-- Public API (stable)
-- Riadky pre breakdown panel (5.4): item | base | M_local | A_regional | M_global | tlak | final | delta vs vcera
function sb2_market_state.breakdownRows(state, cfg)
  local rows = {}
  local names = sb2_util.sortedKeys(state.items)
  for i = 1, #names do
    local item = state.items[names[i]]
    local previous = item.last_final_price or item.base_price
    local result = sb2_pricing.computePrice(item, cfg)
    rows[#rows + 1] = {
      item = names[i],
      category = item.params.category,
      base = item.base_price,
      m_local = result.m_local,
      a_regional = result.a_regional,
      m_global = result.m_global,
      p_pressure = result.p_pressure,
      final = result.final_price,
      delta_pct = previous > 0 and sb2_util.round((result.final_price - previous) / previous * 100) or 0,
      top_reasons = item.top_reasons_cache
    }
  end
  return rows
end

return sb2_market_state
