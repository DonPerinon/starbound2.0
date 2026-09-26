-- mod/scripts/sb2_pricing.lua
-- Ciste cenove formuly DPS (docs/economy-system.md sekcia 3).
-- Ziadny stav, ziadne engine API – vsetko su funkcie nad tabulkami.
-- Used by: sb2_market_state (recompute, transakcie, day tick), sb2_market UI
-- Performance: hot path (compute_price < 0.2 ms, O(pocet modifikatorov))
-- Lua 5.1 striktne.

-- Internal: nacita zavislost v Starbounde (asset cesta, modul sa registruje ako
-- global) aj v standalone Lua (package.path, modul vracia tabulku).
local function sb2_load(name)
  if _G[name] ~= nil then return _G[name] end
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then return mod end
  require("/scripts/" .. name .. ".lua")
  return _G[name]
end

local sb2_util = sb2_load("sb2_util")

local sb2_pricing = {}

-- Internal: sucin hodnot tabulky (multiplikativna vrstva)
local function _product(tbl)
  local result = 1.0
  for _, v in pairs(tbl) do
    result = result * v
  end
  return result
end

-- Internal: sucet hodnot tabulky (aditivna vrstva)
local function _sum(tbl)
  local result = 0.0
  for _, v in pairs(tbl) do
    result = result + v
  end
  return result
end

-- Public API (stable)
-- Vypocet ceny podla 3.2:
--   final = base * M_local * (1 + A_regional) * M_global * (1 + P_pressure), clamp [0.1x, 10x]
-- item_state: { base_price, local_modifiers, regional_modifiers_cached,
--               global_modifiers_cached, player_pressure, jitter }
-- Vrati { final_price, raw_price, m_local, a_regional, m_global, p_pressure, clamped }.
function sb2_pricing.computePrice(item_state, cfg)
  local base = item_state.base_price
  sb2_util.require(type(base) == "number" and base >= 0, "computePrice: invalid base_price")

  local bounds = cfg.modifier_bounds
  local m_local = sb2_util.clamp(_product(item_state.local_modifiers or {}), bounds.local_min, bounds.local_max)
  local m_global = sb2_util.clamp(_product(item_state.global_modifiers_cached or {}), bounds.global_min, bounds.global_max)
  local a_regional = _sum(item_state.regional_modifiers_cached or {}) + (item_state.jitter or 0.0)
  a_regional = sb2_util.clamp(a_regional, bounds.regional_min, bounds.regional_max)
  local p_pressure = sb2_util.clamp(item_state.player_pressure or 0.0, -cfg.player_pressure_cap, cfg.player_pressure_cap)

  local raw = base * m_local * (1.0 + a_regional) * m_global * (1.0 + p_pressure)
  local floor = base * cfg.min_price_factor
  local ceiling = base * cfg.max_price_factor
  local rounded = sb2_util.round(raw)
  local final = sb2_util.clamp(rounded, floor, ceiling)
  -- cena je vzdy cele cislo pixelov a nikdy nie menej ako 1, ak je base > 0
  final = sb2_util.round(final)
  if base > 0 and final < 1 then final = 1 end

  return {
    final_price = final,
    raw_price = raw,
    m_local = m_local,
    a_regional = a_regional,
    m_global = m_global,
    p_pressure = p_pressure,
    clamped = (rounded ~= final)
  }
end

-- Public API (stable)
-- Logaritmicky player impact (3.4). Vrati novy P_pressure a aplikovanu deltu.
-- volume: pocet jednotiek v transakcii, baseline: daily_turnover_baseline itemu.
function sb2_pricing.applyPlayerPressure(current_pressure, volume, baseline, is_sell, cfg)
  sb2_util.require(volume >= 0, "applyPlayerPressure: negative volume")
  local share = volume / math.max(1, baseline)
  local sign = is_sell and -1 or 1
  local delta = sign * cfg.impact_coefficient * math.log(1 + share * cfg.scale_factor)
  local new_pressure = sb2_util.clamp((current_pressure or 0) + delta, -cfg.player_pressure_cap, cfg.player_pressure_cap)
  return new_pressure, delta, share
end

-- Public API (stable)
-- Mean reversion (3.5): modifier_new = base + (old - base) * factor^n
-- n = pocet dni (batch pre inactivity catch-up, 6.1).
function sb2_pricing.decay(value, base_value, decay_factor, days)
  days = days or 1
  if days <= 0 then return value end
  return base_value + (value - base_value) * (decay_factor ^ days)
end

-- Public API (stable)
-- Top N dovodov ceny pre UI (5.3). Kazdy modifikator dostane delta_pct,
-- zoradene podla absolutnej hodnoty. Labely su lokalizacne kluce
-- (sb2.economy.reason.<label>), nie hotove texty.
function sb2_pricing.topReasons(item_state, cfg)
  local reasons = {}
  local function add(label, delta_pct)
    if math.abs(delta_pct) >= 0.5 then
      reasons[#reasons + 1] = { label = label, delta_pct = sb2_util.round(delta_pct) }
    end
  end
  for label, value in pairs(item_state.local_modifiers or {}) do
    add(label, (value - 1.0) * 100)
  end
  for label, value in pairs(item_state.global_modifiers_cached or {}) do
    add(label, (value - 1.0) * 100)
  end
  for label, value in pairs(item_state.regional_modifiers_cached or {}) do
    add(label, value * 100)
  end
  if item_state.jitter and item_state.jitter ~= 0 then
    add("jitter", item_state.jitter * 100)
  end
  if item_state.player_pressure and item_state.player_pressure ~= 0 then
    add("player_pressure", item_state.player_pressure * 100)
  end
  -- deterministicke poradie: podla |delta|, potom podla labelu
  table.sort(reasons, function(a, b)
    local da, db = math.abs(a.delta_pct), math.abs(b.delta_pct)
    if da ~= db then return da > db end
    return a.label < b.label
  end)
  local limit = cfg.top_reasons_count or 3
  local top = {}
  for i = 1, math.min(limit, #reasons) do
    top[i] = reasons[i]
  end
  return top
end

_G["sb2_pricing"] = sb2_pricing
return sb2_pricing
