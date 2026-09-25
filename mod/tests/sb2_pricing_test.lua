-- mod/tests/sb2_pricing_test.lua – formuly zo sekcie 3 economy docu
package.path = "./mod/scripts/?.lua;./mod/tests/?.lua;" .. package.path
local t = require("sb2_test_harness")
local sb2_config = require("sb2_config")
local sb2_pricing = require("sb2_pricing")

local cfg = sb2_config.load("/configs/sb2_economy.config")

-- 3.2 zakladna formula: 30 * 1.70 * (1 + 0.40) * 1.0 * (1 + 0) = 71.4 -> 71
local item = {
  base_price = 30,
  local_modifiers = { supply_demand = 1.42, station_specialization = 1.2 },   -- 1.704
  regional_modifiers_cached = { trade_flow = 0.10, regional_blockade_apex = 0.30 },
  global_modifiers_cached = { faction_event = 1.0 },
  player_pressure = 0.0
}
local r = sb2_pricing.computePrice(item, cfg)
t.approx(r.m_local, 1.704, 1e-9, "M_local is product of local modifiers")
t.approx(r.a_regional, 0.40, 1e-9, "A_regional is sum of regional modifiers")
t.check(r.final_price == 72, "final price rounds raw " .. r.raw_price .. " to 72")
t.check(r.clamped == false, "no clamp for normal range")

-- clamp: 5 zapornych multiplikativnych modifikatorov nesmie ist pod 0.1x
local crash = { base_price = 100, local_modifiers = { a = 0.3, b = 0.3, c = 0.3 }, regional_modifiers_cached = { x = -0.5 }, global_modifiers_cached = { g = 0.3 }, player_pressure = -0.5 }
r = sb2_pricing.computePrice(crash, cfg)
t.check(r.final_price == 10, "floor clamp at base * 0.1 (got " .. r.final_price .. ")")
t.check(r.clamped == true, "clamped flag set on floor")
local boom = { base_price = 100, local_modifiers = { a = 5, b = 5 }, regional_modifiers_cached = { x = 2.0 }, global_modifiers_cached = { g = 5 }, player_pressure = 0.5 }
r = sb2_pricing.computePrice(boom, cfg)
t.check(r.final_price == 1000, "ceiling clamp at base * 10 (got " .. r.final_price .. ")")
t.approx(r.m_local, 10.0, 1e-9, "M_local itself is bounded to 10")

-- cena nikdy nie je 0 pre base > 0
r = sb2_pricing.computePrice({ base_price = 1, local_modifiers = { a = 0.1 }, regional_modifiers_cached = {}, global_modifiers_cached = {}, player_pressure = -0.5 }, cfg)
t.check(r.final_price == 1, "minimum price is 1 pixel for base 1")

-- 3.4 player pressure: share 0.01 -> ~0.014, share 1.0 -> ~0.36, clamp 0.5
local p, d, share = sb2_pricing.applyPlayerPressure(0, 2, 200, false, cfg)
t.approx(share, 0.01, 1e-9, "share = volume / baseline")
t.approx(d, 0.15 * math.log(1.1), 1e-9, "small buy delta matches doc (~0.014)")
p, d = sb2_pricing.applyPlayerPressure(0, 200, 200, true, cfg)
t.approx(d, -0.15 * math.log(11), 1e-9, "full-baseline sell delta matches doc (~-0.36)")
p = sb2_pricing.applyPlayerPressure(-0.4, 200, 200, true, cfg)
t.approx(p, -0.5, 1e-9, "cumulative pressure clamps at -cap")
p = sb2_pricing.applyPlayerPressure(0, 5000, 200, false, cfg)
t.approx(p, 0.5, 1e-9, "single mega buy clamps at +cap")
t.expectError(function() sb2_pricing.applyPlayerPressure(0, -1, 200, true, cfg) end, "negative volume", "negative volume errors")

-- 3.5 decay: 0.30 * 0.85^10 ~= 0.059 (doc: modifier pod 1.06)
t.approx(sb2_pricing.decay(1.30, 1.0, 0.85, 10), 1.0 + 0.30 * 0.85 ^ 10, 1e-12, "decay over 10 days")
t.approx(sb2_pricing.decay(0.30, 0.0, 0.85, 1), 0.255, 1e-12, "additive decay toward 0")
t.check(sb2_pricing.decay(1.5, 1.0, 0.85, 0) == 1.5, "zero days is a no-op")

-- 5.3 top reasons: 3 najvacsie podla |delta|, deterministicke poradie
local reasons = sb2_pricing.topReasons(item, cfg)
t.check(#reasons == 3, "top reasons limited to 3")
t.check(reasons[1].label == "supply_demand" and reasons[1].delta_pct == 42, "largest reason first (+42 supply_demand)")
t.check(reasons[2].label == "regional_blockade_apex" and reasons[2].delta_pct == 30, "second reason +30 blockade")
t.check(reasons[3].label == "station_specialization" and reasons[3].delta_pct == 20, "third reason +20 specialization")
local quiet = sb2_pricing.topReasons({ base_price = 5, local_modifiers = { supply_demand = 1.0 }, regional_modifiers_cached = {}, global_modifiers_cached = {}, player_pressure = 0 }, cfg)
t.check(#quiet == 0, "no reasons when nothing moves the price")

t.finish()
