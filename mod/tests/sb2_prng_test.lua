-- mod/tests/sb2_prng_test.lua
-- Standalone test pre sb2_prng.lua. Bezi mimo Starbound (lua5.1 / lua5.3):
--   python3 tools/run_lua_tests.py  (alebo lua5.1 mod/tests/sb2_prng_test.lua z korena repa)
-- V Starbounde sa nespusta – nema ziadne sb.* zavislosti.

package.path = "./mod/scripts/?.lua;./mod/tests/?.lua;" .. package.path
local sb2_prng = require("sb2_prng")
local t = require("sb2_test_harness")
local check = t.check

-- 1. Determinizmus: rovnaky seed -> rovnaka sekvencia
local a = sb2_prng.new(12345)
local b = sb2_prng.new(12345)
local same = true
for _ = 1, 1000 do
  if a:next() ~= b:next() then same = false end
end
check(same, "same seed gives same sequence")

-- 2. Rozne seedy -> rozne sekvencie
local c = sb2_prng.new(12346)
check(sb2_prng.new(12345):next() ~= c:next(), "different seed gives different first value")

-- 3. Rozsah [0, 1)
local p = sb2_prng.new(777)
local in_range = true
for _ = 1, 10000 do
  local v = p:next()
  if v < 0 or v >= 1 then in_range = false end
end
check(in_range, "next() stays in [0, 1)")

-- 4. Priemer blizko 0.5 (hruby test rovnomernosti)
local sum = 0
local n = 20000
local q = sb2_prng.new(4242)
for _ = 1, n do sum = sum + q:next() end
local mean = sum / n
check(math.abs(mean - 0.5) < 0.02, string.format("mean ~ 0.5 (got %.4f)", mean))

-- 5. Park-Miller referencna hodnota: seed 1 -> 10000. ťah = 1043618065
local r = sb2_prng.new(1)
for _ = 1, 10000 do r:next() end
check(r:getState() == 1043618065, "Park-Miller reference state after 10000 draws")

-- 6. Hash: deterministicky, citlivy na poradie a hranice argumentov
check(sb2_prng.hash("a3f9c2e1", "outpost_terramart_01", 145)
   == sb2_prng.hash("a3f9c2e1", "outpost_terramart_01", 145), "hash is deterministic")
check(sb2_prng.hash("ab", "c") ~= sb2_prng.hash("a", "bc"), "hash separates argument boundaries")
check(sb2_prng.hash("x", 1) ~= sb2_prng.hash("x", 2), "hash distinguishes day index")
local h = sb2_prng.hash("seed", "station", 1)
check(h >= 1 and h < 2147483647 and h == math.floor(h), "hash is integer in [1, m-1]")

-- 7. Jitter symetricky v [-amp/2, +amp/2)
local j = sb2_prng.new(99)
local jitter_ok = true
for _ = 1, 5000 do
  local v = j:jitter(0.05)
  if v < -0.025 or v >= 0.025 then jitter_ok = false end
end
check(jitter_ok, "jitter(0.05) stays in [-0.025, 0.025)")

-- 8. nextInt inclusive hranice
local k = sb2_prng.new(5)
local seen_low, seen_high, out = false, false, false
for _ = 1, 5000 do
  local v = k:nextInt(3, 7)
  if v == 3 then seen_low = true end
  if v == 7 then seen_high = true end
  if v < 3 or v > 7 or v ~= math.floor(v) then out = true end
end
check(seen_low and seen_high and not out, "nextInt(3,7) covers both bounds, never leaves range")

-- 9. getState / setState round-trip
local s1 = sb2_prng.new(31337)
s1:next(); s1:next()
local saved = s1:getState()
local s2 = sb2_prng.new(1)
s2:setState(saved)
check(s1:next() == s2:next(), "setState restores sequence")

-- 10. Seed 0 a zaporny seed sa normalizuju bez chyby
local z = sb2_prng.new(0)
local neg = sb2_prng.new(-5)
check(z:next() > 0 and neg:next() >= 0, "seed 0 and negative seed are normalized")

t.finish()
