-- mod/tests/sb2_storage_test.lua – memory backend + load s migraciou a backupom (8.2)
package.path = "./mod/scripts/?.lua;./mod/tests/?.lua;" .. package.path
local t = require("sb2_test_harness")
local storage = require("sb2_storage")
local m = require("sb2_migrations")

local b = storage.newMemoryBackend()
t.check(b.load("nothing") == nil, "missing key loads nil")
b.save("k", { schema_version = 1, x = { 1, 2 } })
local v = b.load("k")
t.check(v.x[2] == 2, "roundtrip keeps nested data")
v.x[2] = 99
t.check(b.load("k").x[2] == 2, "load returns a copy, not a reference")
t.expectError(function() b.save("k", "string") end, "must be table", "non-table save errors")

m.reset()
m.register("market_state", 1, function(s) s.schema_version = 2; s.added = true; return s end)
local key = storage.marketKey("outpost_terramart_01")
t.check(key == "sb2_market_state_outpost_terramart_01", "market key prefix")
b.save(key, { schema_version = 1, station_id = "outpost_terramart_01", day_index = 3 })

local logged = {}
local state = storage.loadState(b, key, "market_state", 2, { now = function() return "T" end, log = function(msg) logged[#logged + 1] = msg end })
t.check(state.schema_version == 2 and state.added == true, "loadState migrates to current version")
t.check(b.load(key).schema_version == 2, "migrated state written back")
t.check(b.load(key .. "_bak_v1") ~= nil and b.load(key .. "_bak_v1").schema_version == 1, "backup key holds the v1 original")
t.check(#logged == 1, "migration logged once")
t.check(storage.loadState(b, "absent", "market_state", 2) == nil, "loadState returns nil for absent key")
t.expectError(function() storage.saveState(b, "bad", { no_version = true }) end, "schema_version", "saveState refuses state without schema_version")
t.expectError(function() storage.newWorldPropertyBackend() end, "world API", "worldProperty backend errors outside world context")

m.reset()
t.finish()
