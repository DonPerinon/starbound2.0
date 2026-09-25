-- mod/tests/sb2_migrations_test.lua – runner 4.4 / 8.1
package.path = "./mod/scripts/?.lua;./mod/tests/?.lua;" .. package.path
local t = require("sb2_test_harness")
local m = require("sb2_migrations")

m.reset()
m.register("market_state", 0, function(s) s.schema_version = 1; s.items = s.items or {}; return s end)
m.register("market_state", 1, function(s) s.schema_version = 2; s.outbound_events = {}; return s end)
t.expectError(function() m.register("market_state", 1, function(s) return s end) end, "already registered", "duplicate registration errors")

local backups = {}
local hooks = {
  backup = function(state_type, state, old) backups[#backups + 1] = { old = old, snapshot = state.marker }; return true end,
  now = function() return "2026-09-25T00:00:00Z" end
}

-- same version: no-op
local same = { schema_version = 2, marker = "a" }
local r = m.migrate("market_state", same, 2, hooks)
t.check(r.migrated == false and r.state == same, "same version returns state untouched")
t.check(#backups == 0, "no backup when nothing to migrate")

-- chain v0 -> v2 with history and backup before mutation
local old = { schema_version = 0, marker = "orig", day_index = 7 }
r = m.migrate("market_state", old, 2, hooks)
t.check(r.migrated == true and r.from == 0 and r.to == 2, "chain migrated v0 -> v2")
t.check(r.state.schema_version == 2 and r.state.outbound_events ~= nil and r.state.items ~= nil, "both migrations applied")
t.check(#r.state.migration_history == 2 and r.state.migration_history[1].from == 0 and r.state.migration_history[2].to == 2, "migration_history has two entries")
t.check(r.state.migration_history[1].at_realtime_iso == "2026-09-25T00:00:00Z" and r.state.migration_history[1].at_day == 7, "history entry carries time and day")
t.check(#backups == 1 and backups[1].old == 0, "exactly one backup of the original version")
t.check(old.schema_version == 0, "input state is not mutated (pure migration)")

-- refuse newer
t.expectError(function() m.migrate("market_state", { schema_version = 3 }, 2, hooks) end, "P0", "newer schema refuses to load")
-- refuse missing version
t.expectError(function() m.migrate("market_state", { marker = 1 }, 2, hooks) end, "no schema_version", "missing schema_version refuses to load")
-- backup failure aborts
t.expectError(function() m.migrate("market_state", { schema_version = 0 }, 2, { backup = function() return false end }) end, "backup", "failed backup aborts migration")
-- missing migration step
t.expectError(function() m.migrate("market_state", { schema_version = 0 }, 3, hooks) end, "no migration registered", "gap in chain errors")
-- migration that forgets to bump version
m.register("global", 1, function(s) return s end)
t.expectError(function() m.migrate("global", { schema_version = 1 }, 2, hooks) end, "must set schema_version", "migration without version bump errors")

m.reset()
t.finish()
