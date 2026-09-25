-- mod/tests/sb2_economy_tags_test.lua – coverage pravidlo 4.3 a drift scan 6.4
package.path = "./mod/scripts/?.lua;./mod/tests/?.lua;" .. package.path
local t = require("sb2_test_harness")
local sb2_config = require("sb2_config")
local tags = require("sb2_economy_tags")

local cfg = sb2_config.load("/configs/sb2_economy.config")
local tc = sb2_config.load("/configs/sb2_economy_tags.config")

t.check(tags.validate(tc) == true, "shipped tags config validates")
t.expectError(function() tags.validate({ schema_version = 1, tracked_fu_tags = { "ghost" }, category_defaults = {} }) end, "no category_defaults", "tracked tag without defaults errors")

t.check(tags.resolveCategory("ironore", { "ore", "misc" }, tc) == "ore", "tracked tag resolves category")
t.check(tags.resolveCategory("ironore", { "ore", "sb2_static" }, tc) == nil, "sb2_static override wins")
t.check(tags.resolveCategory("liquidwater", { "misc" }, tc) == "food", "item_overrides.category wins over missing tag")
t.check(tags.resolveCategory("mysterygoo", { "sb2_dynamic" }, tc) == tc.tracked_fu_tags[1], "sb2_dynamic without known tag falls back to first category")
t.check(tags.resolveCategory("dirt", { "block" }, tc) == nil, "untagged item is not tracked")
t.check(tags.resolveCategory("bar", { "food", "ore" }, tc) == "ore", "first tag in tracked_fu_tags order decides")

local params = tags.getItemParams("liquidwater", "food", tc, cfg)
t.check(params.daily_turnover_baseline == 600, "item override baseline applied (600)")
t.approx(params.decay_factor, 0.80, 1e-9, "category default decay applied")
t.approx(params.jitter_amplitude, 0.08, 1e-9, "category default jitter applied")
t.expectError(function() tags.getItemParams("x", "nope", tc, cfg) end, "unknown category", "unknown category errors")

-- drift scan: 2 z 3 override itemov stratili tag -> drift
local lost = { liquidwater = { "misc" }, corefragment = { "misc" }, titaniumbar = { "refined_metal" } }
local scan = tags.scanTaxonomyDrift(tc, function(name) return lost[name] end)
t.check(scan.checked == 3, "scan checks all override items")
t.check(#scan.mismatched == 2 and scan.drift == true, "drift detected when >20% mismatch")
local fine = { liquidwater = { "food" }, corefragment = { "ore" }, titaniumbar = { "refined_metal" } }
scan = tags.scanTaxonomyDrift(tc, function(name) return fine[name] end)
t.check(#scan.mismatched == 0 and scan.drift == false, "no drift when tags match")

t.finish()
