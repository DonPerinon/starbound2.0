-- mod/scripts/sb2_util.lua
-- Male pomocne funkcie zdielane economy modulmi.
-- Used by: sb2_pricing, sb2_market_state, sb2_migrations, sb2_storage
-- Performance: hot path safe (ziadne alokacie okrem deepCopy)
-- Lua 5.1 striktne.

local sb2_util = {}

-- Public API (stable)
function sb2_util.clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

-- Public API (stable)
-- Zaokruhlenie na cele cislo (half up), Lua 5.1 nema math.round.
function sb2_util.round(value)
  return math.floor(value + 0.5)
end

-- Public API (stable)
-- Hlboka kopia JSON-kompatibilnej tabulky (bez metatables, bez cyklov).
function sb2_util.deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = sb2_util.deepCopy(v)
  end
  return copy
end

-- Public API (stable)
-- Kontrola vstupu: pri zlyhani crash s jasnou spravou (no silent failures).
function sb2_util.require(condition, message)
  if not condition then
    error("[SB2] " .. tostring(message), 2)
  end
end

-- Public API (stable)
-- Pocet prvkov v tabulke s lubovolnymi klucmi.
function sb2_util.count(tbl)
  local n = 0
  for _ in pairs(tbl) do n = n + 1 end
  return n
end

-- Public API (stable)
-- Zoradene kluce tabulky (deterministicke iterovanie pre co-op).
function sb2_util.sortedKeys(tbl)
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

_G["sb2_util"] = sb2_util
return sb2_util
