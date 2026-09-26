-- mod/scripts/sb2_prng.lua
-- Deterministicky PRNG pre DPS jitter a vsetko, co musi byt reprodukovatelne
-- medzi co-op klientmi (docs/economy-system.md sekcia 3.6, otvorena otazka 4).
-- Used by: sb2_economy_day tick (jitter per market per day), buduce faction AI
-- Performance: cold path (day tick); jeden next() je par aritmetickych operacii
--
-- Algoritmus: Park-Miller "minimal standard" LCG, a = 16807, m = 2^31 - 1.
-- Zamerne bez bitovych operatorov: 16807 * (m - 1) < 2^53, takze double
-- aritmetika je presna a kod bezi identicky v Lua 5.1 aj 5.3.
-- Perioda 2^31 - 2 staci pre jitter (jeden ci dva ťahy per market per den).
-- math.random() sa nepouziva – nie je seedovatelne per instancia.

local sb2_prng = {}

local MODULUS = 2147483647   -- 2^31 - 1 (prvocislo)
local MULTIPLIER = 16807     -- 7^5
local HASH_MULTIPLIER = 31

-- Internal: prevedie lubovolnu hodnotu na string pre hash
local function _toHashString(value)
  local value_type = type(value)
  if value_type == "string" then
    return value
  elseif value_type == "number" then
    -- %.17g je stabilne pre integer aj float, bez zavislosti na tostring()
    return string.format("%.17g", value)
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value == nil then
    return ""
  end
  error("sb2_prng.hash: unsupported argument type '" .. value_type .. "'")
end

-- Public API (stable)
-- Deterministicky hash lubovolneho poctu argumentov (string, number, boolean).
-- Vracia integer v rozsahu [1, MODULUS - 1], priamo pouzitelny ako seed.
-- Priklad: sb2_prng.hash(world_seed, station_id, day_index)
function sb2_prng.hash(...)
  local hash = 7
  local arg_count = select("#", ...)
  for i = 1, arg_count do
    local text = _toHashString((select(i, ...)))
    -- oddelovac zabezpeci, ze ("ab","c") a ("a","bc") daju iny hash
    hash = (hash * HASH_MULTIPLIER + 1) % MODULUS
    for pos = 1, #text do
      hash = (hash * HASH_MULTIPLIER + string.byte(text, pos)) % MODULUS
    end
  end
  if hash == 0 then
    hash = 1
  end
  return hash
end

-- Internal: normalizuje seed do [1, MODULUS - 1]
local function _normalizeSeed(seed)
  if type(seed) ~= "number" then
    error("sb2_prng.new: seed must be a number, got " .. type(seed))
  end
  seed = math.floor(math.abs(seed)) % MODULUS
  if seed == 0 then
    seed = 1
  end
  return seed
end

local Prng = {}
Prng.__index = Prng

-- Public API (stable)
-- Vytvori novu instanciu so stavom odvodenym zo seedu.
function sb2_prng.new(seed)
  local instance = { state = _normalizeSeed(seed) }
  return setmetatable(instance, Prng)
end

-- Public API (stable)
-- Vrati float v rozsahu [0, 1).
function Prng:next()
  self.state = (self.state * MULTIPLIER) % MODULUS
  return (self.state - 1) / (MODULUS - 1)
end

-- Public API (stable)
-- Vrati integer v uzavretom rozsahu [low, high].
function Prng:nextInt(low, high)
  if high < low then
    error("sb2_prng.nextInt: high < low")
  end
  return low + math.floor(self:next() * (high - low + 1))
end

-- Public API (stable)
-- Vrati float v rozsahu [low, high).
function Prng:nextRange(low, high)
  return low + self:next() * (high - low)
end

-- Public API (stable)
-- Jitter podla economy-system.md 3.6: (next() - 0.5) * amplitude, teda
-- symetricky okolo nuly v rozsahu [-amplitude/2, +amplitude/2).
function Prng:jitter(amplitude)
  return (self:next() - 0.5) * amplitude
end

-- Public API (stable)
-- Vrati serializovatelny stav (pre ulozenie do market state, ak bude treba).
function Prng:getState()
  return self.state
end

-- Public API (stable)
-- Obnovi stav zo serializovanej hodnoty.
function Prng:setState(state)
  self.state = _normalizeSeed(state)
end

_G["sb2_prng"] = sb2_prng
return sb2_prng
