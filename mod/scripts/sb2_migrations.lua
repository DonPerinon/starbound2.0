-- mod/scripts/sb2_migrations.lua
-- Migration runner pre perzistentne stavy (docs/economy-system.md 4.4 a 8).
-- Used by: sb2_storage pri kazdom load
-- Performance: one-time pri load
-- Lua 5.1 striktne.

local sb2_util = require("sb2_util")

local sb2_migrations = {}

-- registry[state_type][from_version] = function(state) -> state (schema_version = from + 1)
local registry = {}

-- Public API (stable)
-- Zaregistruje migraciu z verzie `from_version` na `from_version + 1`.
function sb2_migrations.register(state_type, from_version, migrate_fn)
  sb2_util.require(type(state_type) == "string", "register: state_type must be string")
  sb2_util.require(type(from_version) == "number", "register: from_version must be number")
  sb2_util.require(type(migrate_fn) == "function", "register: migrate_fn must be function")
  registry[state_type] = registry[state_type] or {}
  sb2_util.require(registry[state_type][from_version] == nil,
    "register: migration " .. state_type .. " v" .. from_version .. " already registered")
  registry[state_type][from_version] = migrate_fn
end

-- Public API (stable)
-- Vymaze registry (iba pre testy).
function sb2_migrations.reset()
  registry = {}
end

-- Public API (stable)
-- Spusti migracnu retaz. hooks = { backup = fn(state_type, state, old_version) -> bool,
-- now = fn() -> iso string, log = fn(msg) }.
-- Vrati { state, migrated = bool, from = N, to = M }.
-- Novsi stav ako current_version → error (odmietame tichu korupciu).
-- Chybajuci schema_version → error.
function sb2_migrations.migrate(state_type, state, current_version, hooks)
  sb2_util.require(type(state) == "table", "migrate: state must be a table")
  local version = state.schema_version
  sb2_util.require(type(version) == "number", "migrate: " .. state_type .. " has no schema_version (refusing to load)")
  local log = hooks.log or function() end

  if version == current_version then
    return { state = state, migrated = false, from = version, to = version }
  end

  if version > current_version then
    error(string.format("[SB2] P0: %s state has schema v%d but this mod supports v%d. Not loading, backup untouched.",
      state_type, version, current_version))
  end

  -- backup PRED akoukolvek mutaciou; zlyhanie = migracia sa neuskutocni
  local ok = hooks.backup(state_type, state, version)
  sb2_util.require(ok == true, "migrate: backup of " .. state_type .. " v" .. version .. " failed, migration aborted")

  local working = sb2_util.deepCopy(state)
  for v = version, current_version - 1 do
    local fn = registry[state_type] and registry[state_type][v]
    sb2_util.require(fn ~= nil, string.format("migrate: no migration registered for %s v%d -> v%d", state_type, v, v + 1))
    local before = working.schema_version
    working = fn(working)
    sb2_util.require(type(working) == "table", "migrate: migration " .. state_type .. " v" .. v .. " returned non-table")
    sb2_util.require(working.schema_version == v + 1,
      string.format("migrate: %s v%d migration must set schema_version=%d (got %s)", state_type, v, v + 1, tostring(working.schema_version)))
    working.migration_history = working.migration_history or {}
    working.migration_history[#working.migration_history + 1] = {
      from = before, to = v + 1, at_day = working.day_index or working.current_day or 0,
      at_realtime_iso = hooks.now and hooks.now() or ""
    }
    log(string.format("[SB2] Migration %s v%d -> v%d completed", state_type, v, v + 1))
  end

  return { state = working, migrated = true, from = version, to = current_version }
end

return sb2_migrations
