-- mod/scripts/sb2_storage.lua
-- Storage vrstva DPS s vymenitelnym backendom (docs/economy-system.md 4.1, 4.2, 8.2).
-- Per-station stav: world property na svete stanice (backend worldProperty).
-- Universe stav: backend sa doplni podla vysledkov prototypu Q1/Q2 – zatial je
-- k dispozicii memory backend (testy) a playerProperty backend (kandidat).
-- Used by: sb2_market_state loader, sb2_economy_init
-- Performance: cold path (load pri prvej navsteve, save pri recompute)
-- Lua 5.1 striktne.

local sb2_util = require("sb2_util")
local sb2_migrations = require("sb2_migrations")

local sb2_storage = {}

local MARKET_KEY_PREFIX = "sb2_market_state_"

-- Public API (stable)
-- Backend v pamati – pre testy a ako referencna implementacia rozhrania.
-- Rozhranie: load(key) -> table|nil, save(key, tbl), delete(key), keys() -> list
function sb2_storage.newMemoryBackend()
  local store = {}
  return {
    name = "memory",
    load = function(key) return sb2_util.deepCopy(store[key]) end,
    save = function(key, value)
      sb2_util.require(type(value) == "table", "memory.save: value must be table")
      store[key] = sb2_util.deepCopy(value)
    end,
    delete = function(key) store[key] = nil end,
    keys = function() return sb2_util.sortedKeys(store) end
  }
end

-- Public API (stable)
-- Backend nad world.getProperty / world.setProperty (per-world).
-- Starbound uklada JSON tabulky priamo, netreba serializovat do stringu.
function sb2_storage.newWorldPropertyBackend()
  sb2_util.require(type(world) == "table" and world.getProperty and world.setProperty,
    "worldProperty backend requires world API (not available in this context)")
  return {
    name = "worldProperty",
    load = function(key)
      local value = world.getProperty(key)
      if value == nil then return nil end
      sb2_util.require(type(value) == "table", "worldProperty.load: property " .. key .. " is not a table")
      return value
    end,
    save = function(key, value)
      sb2_util.require(type(value) == "table", "worldProperty.save: value must be table")
      world.setProperty(key, value)
    end,
    delete = function(key) world.setProperty(key, nil) end,
    keys = function() return {} end  -- world API nevie vymenovat properties
  }
end

-- Public API (stable)
-- Backend nad player.getProperty / player.setProperty (kandidat pre universe stav,
-- rozhodne prototyp Q1/Q2). Dostupne iba v player script contexte.
function sb2_storage.newPlayerPropertyBackend()
  sb2_util.require(type(player) == "table" and player.getProperty and player.setProperty,
    "playerProperty backend requires player API (not available in this context)")
  return {
    name = "playerProperty",
    load = function(key)
      local value = player.getProperty(key)
      if value == nil then return nil end
      sb2_util.require(type(value) == "table", "playerProperty.load: property " .. key .. " is not a table")
      return value
    end,
    save = function(key, value)
      sb2_util.require(type(value) == "table", "playerProperty.save: value must be table")
      player.setProperty(key, value)
    end,
    delete = function(key) player.setProperty(key, nil) end,
    keys = function() return {} end
  }
end

-- Public API (stable)
function sb2_storage.marketKey(station_id)
  return MARKET_KEY_PREFIX .. station_id
end

-- Public API (stable)
-- Nacita stav, spusti migracie (s backupom cez ten isty backend) a vrati ho.
-- Vrati nil, ak stav neexistuje. Chyba pri korupcii (no silent failures).
-- hooks = { now = fn, log = fn }
function sb2_storage.loadState(backend, key, state_type, current_version, hooks)
  hooks = hooks or {}
  local raw = backend.load(key)
  if raw == nil then return nil end
  local result = sb2_migrations.migrate(state_type, raw, current_version, {
    backup = function(_, state, old_version)
      backend.save(key .. "_bak_v" .. old_version, state)
      return backend.load(key .. "_bak_v" .. old_version) ~= nil
    end,
    now = hooks.now,
    log = hooks.log
  })
  if result.migrated then
    backend.save(key, result.state)
  end
  return result.state
end

-- Public API (stable)
function sb2_storage.saveState(backend, key, state)
  sb2_util.require(type(state.schema_version) == "number", "saveState: state has no schema_version")
  backend.save(key, state)
end

return sb2_storage
