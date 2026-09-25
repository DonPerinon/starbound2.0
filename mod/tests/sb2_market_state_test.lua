-- mod/tests/sb2_market_state_test.lua – 2.1, 4.1, 6.1–6.3
package.path = "./mod/scripts/?.lua;./mod/tests/?.lua;" .. package.path
local t = require("sb2_test_harness")
local sb2_config = require("sb2_config")
local ms = require("sb2_market_state")
local tags = require("sb2_economy_tags")

local cfg = sb2_config.load("/configs/sb2_economy.config")
local tc = sb2_config.load("/configs/sb2_economy_tags.config")
tags.validate(tc)

local function fresh()
  local s = ms.new("outpost_terramart_01", { 123, 456, 7 }, 145)
  ms.ensureItem(s, "liquidwater", 5, tags.getItemParams("liquidwater", "food", tc, cfg))
  ms.ensureItem(s, "corefragment", 30, tags.getItemParams("corefragment", "ore", tc, cfg))
  ms.ensureItem(s, "titaniumbar", 12, tags.getItemParams("titaniumbar", "refined_metal", tc, cfg))
  ms.recomputeAll(s, cfg)
  return s
end

local s = fresh()
t.check(ms.validate(s) == true, "fresh state validates")
t.check(s.schema_version == 1 and s.day_index == 145, "schema v1, day index kept")
t.check(s.items.liquidwater.params.daily_turnover_baseline == 600, "item carries its params")
t.check(s.items.liquidwater.last_final_price == 5, "fresh item price equals base")
t.expectError(function() ms.ensureItem(s, "newitem", nil, {}) end, "base_price", "ensureItem without base errors")
t.expectError(function() ms.validate({ schema_version = 2 }) end, "schema_version", "wrong schema refuses")

-- recompute with universe context refreshes caches and reasons
local r = ms.recomputeItem(s, "corefragment", cfg, { regional = { regional_blockade_apex = 0.30 }, global = { faction_floran_hunger = 1.18 } })
t.check(r.final_price == 46, "blockade + hunger price 30*1.3*1.18 = 46 (got " .. r.final_price .. ")")
t.check(s.items.corefragment.top_reasons_cache[1].label == "regional_blockade_apex", "top reason cached after recompute")
t.check(s.last_recompute_day == 145, "recompute stamps day")
t.check(ms.isStale(s, cfg) == false, "not stale right after recompute")

-- transaction: sell 500 water (baseline 600) -> share 0.83, pressure ~ -0.335, price 5 -> 3
s = fresh()
local tx = ms.applyTransaction(s, "liquidwater", 500, true, cfg)
t.approx(tx.share, 500 / 600, 1e-9, "share computed against item baseline")
t.approx(tx.pressure, -0.15 * math.log(1 + (500 / 600) * 10), 1e-9, "sell pressure matches formula")
t.check(s.items.liquidwater.last_final_price == 3, "price drops after big sell (got " .. s.items.liquidwater.last_final_price .. ")")
t.check(s.daily_turnover.liquidwater == 500, "daily turnover accumulates")
t.check(tx.extreme == nil, "no extreme event below 5x baseline")
-- cumulative: splitting into small sells still accumulates (no exploit)
for _ = 1, 10 do ms.applyTransaction(s, "liquidwater", 500, true, cfg) end
t.approx(s.items.liquidwater.player_pressure, -0.5, 1e-9, "pressure caps at -0.5 over many sells")

-- extreme glut: > 5x baseline in one go -> outbound neighbor event
s = fresh()
tx = ms.applyTransaction(s, "corefragment", 500, true, cfg)   -- baseline 80 -> share 6.25
t.check(tx.extreme ~= nil and tx.extreme.type == "extreme_glut", "extreme glut event created")
t.approx(tx.extreme.magnitude, -0.10, 1e-9, "neighbor modifier -10%")
t.check(tx.extreme.expires_day == 145 + 1 + 3 and tx.extreme.target == "neighbors", "event targets neighbors for 3 days")
t.check(#s.outbound_events == 1, "outbound event queued on state")
tx = ms.applyTransaction(s, "corefragment", 500, false, cfg)
t.check(tx.extreme.type == "extreme_scarcity" and tx.extreme.magnitude > 0, "extreme buy creates scarcity event")
t.expectError(function() ms.applyTransaction(s, "ghost", 1, true, cfg) end, "unknown item", "transaction on unknown item errors")

-- day tick: resets, decays, jitters deterministically, applies events
s = fresh()
s.items.corefragment.local_modifiers.supply_demand = 1.5
ms.applyTransaction(s, "liquidwater", 100, true, cfg)
ms.queueEvent(s, { type = "trade_flow_arrival", item = "titaniumbar", magnitude = 0.12, day = 146 })
ms.queueEvent(s, { type = "regional_event", label = "regional_blockade_apex", magnitude = 0.30, day = 146, expires_day = 148 })
ms.queueEvent(s, { type = "trade_flow_arrival", item = "titaniumbar", magnitude = 0.50, day = 150 })
ms.dayTick(s, cfg, "seedA")
t.check(s.day_index == 146, "day advances")
t.check(s.items.liquidwater.player_pressure == 0 and s.daily_turnover.liquidwater == 0, "pressure and turnover reset")
t.approx(s.items.corefragment.local_modifiers.supply_demand, 1.0 + 0.5 * 0.85, 1e-9, "local modifier decays by category factor")
t.approx(s.items.titaniumbar.regional_modifiers_cached.trade_flow, -0.12, 1e-9, "arrival lowers price via trade_flow")
t.approx(s.items.titaniumbar.regional_modifiers_cached.regional_blockade_apex, 0.30, 1e-9, "regional event applied to all items")
t.check(#s.pending_events == 1 and s.pending_events[1].day == 150, "future event stays pending")
local jittered = 0
for _, item in pairs(s.items) do if item.jitter ~= 0 then jittered = jittered + 1 end end
t.check(jittered == 1, "exactly one item gets jitter per day")
local s2 = fresh(); s2.items.corefragment.local_modifiers.supply_demand = 1.5
ms.applyTransaction(s2, "liquidwater", 100, true, cfg)
ms.queueEvent(s2, { type = "trade_flow_arrival", item = "titaniumbar", magnitude = 0.12, day = 146 })
ms.queueEvent(s2, { type = "regional_event", label = "regional_blockade_apex", magnitude = 0.30, day = 146, expires_day = 148 })
ms.dayTick(s2, cfg, "seedA")
local same = true
for name, item in pairs(s.items) do if item.jitter ~= s2.items[name].jitter then same = false end end
t.check(same, "jitter is deterministic for same seed/station/day (co-op)")
local s3 = fresh(); ms.dayTick(s3, cfg, "seedB")
local differs = false
for name, item in pairs(s.items) do if item.jitter ~= s3.items[name].jitter then differs = true end end
t.check(differs, "different world seed gives different jitter")

-- active source keeps blockade flat until expiry, then decays
ms.dayTick(s, cfg, "seedA")   -- 147
t.approx(s.items.titaniumbar.regional_modifiers_cached.regional_blockade_apex, 0.30, 1e-9, "active blockade does not decay (day 147 < 148)")
ms.dayTick(s, cfg, "seedA")   -- 148 (expires)
t.approx(s.items.titaniumbar.regional_modifiers_cached.regional_blockade_apex, 0.30 * 0.90, 1e-9, "blockade decays after expiry")
t.check(s.items.titaniumbar.active_sources.regional_blockade_apex == nil, "expired source cleared")

-- catch-up 6.1: batch decay equals n single ticks for modifiers (jitter aside)
local a = fresh(); a.items.corefragment.local_modifiers.supply_demand = 1.8
local b = fresh(); b.items.corefragment.local_modifiers.supply_demand = 1.8
t.check(ms.advanceTo(a, 145, cfg, "s") == 0, "advanceTo same day is a no-op")
ms.advanceTo(a, 150, cfg, "s")      -- 5 days: loop
ms.advanceTo(b, 165, cfg, "s")      -- 20 days: batch
t.check(a.day_index == 150 and b.day_index == 165, "both states reach target day")
t.approx(a.items.corefragment.local_modifiers.supply_demand, 1.0 + 0.8 * 0.85 ^ 5, 1e-9, "5 looped ticks decay 0.85^5")
t.approx(b.items.corefragment.local_modifiers.supply_demand, 1.0 + 0.8 * 0.85 ^ 20, 1e-9, "20-day batch decays 0.85^20 in one step")
t.check(b.items.corefragment.local_modifiers.supply_demand < 1.04, "after ~20 idle days modifier is near base")

-- breakdown rows for sb2_market terminal (5.4)
local rows = ms.breakdownRows(s, cfg)
t.check(#rows == 3 and rows[1].item == "corefragment" and rows[3].item == "titaniumbar", "breakdown rows sorted by item name")
t.check(type(rows[1].m_local) == "number" and type(rows[1].delta_pct) == "number", "rows carry layer values and delta")

t.finish()
