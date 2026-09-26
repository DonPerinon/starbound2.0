-- mod/tests/sb2_market_view_test.lua – filter, format, dovody (5.4) + sb2_station
package.path = "./mod/scripts/?.lua;./mod/tests/?.lua;" .. package.path
local t = require("sb2_test_harness")
local sb2_config = require("sb2_config")
local view = require("sb2_market_view")
local station = require("sb2_station")
local ms = require("sb2_market_state")
local tags = require("sb2_economy_tags")

local cfg = sb2_config.load("/configs/sb2_economy.config")
local tc = sb2_config.load("/configs/sb2_economy_tags.config")
local reasons_cfg = sb2_config.load("/configs/sb2_economy_reasons.config")
tags.validate(tc)

-- realne riadky z market state
local s = ms.new("st", {}, 10)
ms.ensureItem(s, "liquidwater", 5, tags.getItemParams("liquidwater", "food", tc, cfg))
ms.ensureItem(s, "corefragment", 30, tags.getItemParams("corefragment", "ore", tc, cfg))
ms.ensureItem(s, "titaniumbar", 12, tags.getItemParams("titaniumbar", "refined_metal", tc, cfg))
ms.recomputeAll(s, cfg)
ms.queueEvent(s, { type = "regional_event", label = "blockade_apex", magnitude = 0.30, day = 11, expires_day = 20 })
ms.dayTick(s, cfg, "seed")
ms.applyTransaction(s, "liquidwater", 150, true, cfg)
local rows = ms.breakdownRows(s, cfg)

t.check(#view.filterRows(rows, "all", false) == 3, "filter all keeps every row")
t.check(#view.filterRows(rows, "ore", false) == 1 and view.filterRows(rows, "ore", false)[1].item == "corefragment", "filter by category")
t.check(#view.filterRows(rows, nil, false) == 3, "nil category means all")
local changed = view.filterRows(rows, "all", true)
t.check(#changed >= 1, "changed-only keeps rows with non-zero delta")
for i = 1, #changed do t.check(changed[i].delta_pct ~= 0, "changed row " .. changed[i].item .. " has delta") end
t.check(table.concat(view.categories(rows), ",") == "food,ore,refined_metal", "categories sorted")

local fmt = "%-14s %5d %6.2f %+6.2f %6.2f %+4d%% %6d %+5d%%"
local line = view.formatRow(rows[1], fmt, 14)
t.check(string.find(line, "^corefragment ") ~= nil, "row starts with item name")
t.check(string.find(line, "%%") ~= nil, "row has percent columns")
local long = view.formatRow({ item = "averyveryverylongitemname", base = 1, m_local = 1, a_regional = 0, m_global = 1, p_pressure = 0, final = 1, delta_pct = 0 }, fmt, 14)
t.check(string.find(long, "^averyveryvery~") ~= nil, "long item name truncated with ~")

local lines = view.reasonLines({ { label = "blockade_apex", delta_pct = 30 }, { label = "player_pressure", delta_pct = -8 }, { label = "mystery", delta_pct = 3 } }, reasons_cfg.labels, "%+d%% %s")
t.check(lines[1] == "+30% Blokada apex", "prefix label + dynamic suffix (got '" .. lines[1] .. "')")
t.check(lines[2] == "-8% Hracsky tlak (24h)", "known label translated")
t.check(lines[3] == "+3% mystery", "unknown label shown raw, not hidden")
t.check(#view.reasonLines(nil, reasons_cfg.labels) == 0, "nil reasons gives empty list")

-- sb2_station
t.check(station.resolveStationId("outpost_terramart_01", "x") == "outpost_terramart_01", "explicit id wins")
t.check(station.resolveStationId(nil, "CelestialWorld:12:34:5:6") == "CelestialWorld_12_34_5_6", "world id sanitized")
t.check(station.resolveStationId("", "InstanceWorld:outpost:-:-") == "InstanceWorld_outpost_-_-", "empty explicit falls back, dash kept")
t.expectError(function() station.resolveStationId(nil, nil) end, "neither", "no id at all errors")
t.check(station.systemKey({ 12, 34, 5 }) == "system_12_34_5" and station.systemKey(nil) == "system_unknown", "system key from coords")

t.finish()
